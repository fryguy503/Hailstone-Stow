local S = dofile("lib/stow_model.lua")
local T = dofile("lib/theme.lua")
local style = dofile("lib/style.lua")
local escape = dofile("lib/escape.lua")
local slots = dofile("lib/items.lua")
local Cards = dofile("lib/stow_cards.lua")
local Dock = dofile("lib/stow_dock.lua")
local API = hs.UI
local C = T.color
local V = { model = S }

local bankTints = { slate = { 0.58, 0.65, 0.78, 1 }, blue = { 0.42, 0.74, 0.99, 1 } }
local bagKinds = {
  [2] = { badge = "Q", label = "Quiver" },
  [8] = { badge = "TH", label = "Throwing only" },
  [58] = { badge = "TS", label = "Tradeskill only" },
}
local layouts, compactStates = {}, {}

function V.bagKind(item)
  return item and bagKinds[item.bagType]
end

function V.active(preference)
  return S.get("enabled") and S.get(preference) and (not S.actions or S.actions())
end

local function saveLayout(key, x, y, w, h, scale)
  local value = string.format("%d,%d,%d,%d", math.floor(x), math.floor(y), math.floor(w / scale), math.floor(h / scale))
  if layouts[key] ~= value then
    layouts[key] = value
    ui.SetSetting("stow.layout." .. key, value)
  end
end

function V.window(screen, title, key, defaultW, defaultH, body, onClose)
  local shown, stockX, stockY = API.windows.Replace(screen, true)
  if not shown then return end
  local io = ui.GetIO()
  local scale = io.uiScale or 1
  local saved = layouts[key] or ui.GetSetting("stow.layout." .. key) or ""
  local x, y, w, h = saved:match("^(-?%d+),(-?%d+),(%d+),(%d+)$")
  w, h = math.min(io.width, (tonumber(w) or defaultW) * scale), math.min(io.height, (tonumber(h) or defaultH) * scale)
  x = math.max(0, math.min(tonumber(x) or stockX or 100, io.width - w))
  y = math.max(0, math.min(tonumber(y) or stockY or 100, io.height - h))
  ui.SetNextWindowPos(x, y, ui.Cond.Appearing)
  ui.SetNextWindowSize(w, h, ui.Cond.Appearing)
  local flags = ui.WindowFlags.NoSavedSettings | ui.WindowFlags.NoCollapse
  if S.get("windowLocked") then flags = flags | ui.WindowFlags.NoMove | ui.WindowFlags.NoResize end
  style.Push()
  ui.PushStyleVar(ui.StyleVar.WindowPadding, 12 * scale, 9 * scale)
  local visible, open = ui.Begin(title .. "###stow." .. key, true, flags)
  ui.PopStyleVar()
  local wx, wy = ui.GetWindowPos()
  local ww, wh = ui.GetWindowSize()
  saveLayout(key, wx, wy, ww, wh, scale)
  API.windows.Placed(screen, wx, wy, ww, wh, true)
  if escape.Frame(screen) then open = false end
  T.ResetRightClick()
  if visible then body(scale) end
  ui.End()
  style.Pop()
  if not open then
    if onClose then onClose() else API.windows.Show(screen, false) end
  end
end

function V.actions(scope, bagWindow)
  local done, total, mode = API.inventory.ItemJob()
  if done and total then
    if ui.Button("Stop") then API.inventory.StopItemJob() end
    ui.SameLine()
    ui.TextDisabled(string.format("%s %d / %d", mode or "Moving items", done, total))
    return
  end
  if ui.Button("Sort") then S.run(scope, "sort", bagWindow) end
  ui.SameLine()
  if ui.Button("Stack") then S.run(scope, "stack", bagWindow) end
  ui.SameLine()
  if ui.Button("Tidy") then S.run(scope, "tidy", bagWindow) end
end

local function itemMenu(cell, bagScope, pinned)
  local item = cell.item
  if item then
    ui.Text(item.name)
    ui.Separator()
    if ui.MenuItem("Keep", cell.kept == true) then S.setKept(cell, not cell.kept) end
    local junk = S.isJunk(item.id)
    if ui.MenuItem("Mark for sale", junk, item.sellable == true or junk) then S.setJunk(item.id, not junk) end
    if bagScope then
      local selected = pinned[bagScope] == cell.place
      if ui.MenuItem("Filter to this bag", selected) then pinned[bagScope] = not selected and cell.place or nil end
    end
    if ui.BeginMenu("Category") then
      local current = S.assignment(item.id)
      if ui.MenuItem("Automatic", current == nil) then S.assign(item.id, nil) end
      for _, category in ipairs(S.categories()) do
        if ui.MenuItem(category.label, current == category.id) then S.assign(item.id, category.id) end
      end
      ui.EndMenu()
    end
    if cell.sub == -1 and (item.bagSlots or 0) > 0 and cell.where ~= "shared"
        and S.bagFilters and ui.BeginMenu("Tidy into this bag") then
      local current = S.bagFilter(cell)
      if ui.MenuItem("No preference", not current or current == "") then S.setBagFilter(cell, nil) end
      for _, filter in ipairs(S.bagFilters()) do
        if ui.MenuItem(filter.label, current == filter.id) then S.setBagFilter(cell, filter.id) end
      end
      ui.EndMenu()
    end
  end
  if S.isLocked then
    local locked = S.isLocked(cell)
    if ui.MenuItem("Lock position for sorting", locked) then S.setLocked(cell, not locked) end
  end
end

local function cellLabel(cell)
  local place = cell.where == "shared" and "Shared bank" or (cell.where == "bank" and "Bank" or "Inventory")
  local slot = (cell.slot or 0) + (cell.where == "carried" and (1 - API.inventory.FirstBagSlot) or 1)
  if cell.sub and cell.sub >= 0 then
    return (cell.bag or (place .. " bag " .. slot)) .. ", slot " .. (cell.sub + 1)
  end
  local kind = V.bagKind(cell.item)
  return place .. " slot " .. slot .. (kind and (" · " .. kind.label) or "")
end

local function highlight(x, y, z, scale, color)
  ui.DrawRect(x, y, x + z, y + z, color[1], color[2], color[3], 0.84, 5 * scale, 1.5 * scale)
end

local function drawCell(cell, x, y, size, scale, query, selectedBag, bagScope, pinned)
  local id, color = cell.place, nil
  local item, down = cell.item, nil
  local io = ui.GetIO()
  local menuChord = io.ctrl and io.alt
  if cell.where == "carried" then
    down = {
      held = true,
      compare = item and function() return API.compare.Item(cell.slot, cell.sub >= 0 and cell.sub or nil) end or nil,
    }
  end
  if cell.stale then down = nil end
  slots.Slot("##" .. id, x, y, size, scale, item, nil, cellLabel(cell), function(button, outside)
    if cell.stale or (outside and button ~= "leftheld") then return false end
    if button == "rightup" and menuChord then return false end
    if button == "left" and cell.empty and S.canPlace(cell) == false then return false end
    return S.click(cell, button)
  end, down)
  local hovered = ui.IsItemHovered()
  local source = selectedBag and cell.sub >= 0 and cell.place:sub(1, #selectedBag + 1) == (selectedBag .. ":")
  if cell.stale or (query ~= "" and cell.match == false and S.get("searchDim")) then
    local shade = C.inset
    ui.DrawRectFilled(x, y, x + size, y + size, shade[1], shade[2], shade[3], 0.63, 5 * scale)
  elseif source or (bagScope and pinned[bagScope] == cell.place) or (query ~= "" and cell.match and item) then
    color = C.accent
  elseif hovered and cell.empty then
    local fits = S.canPlace(cell)
    color = (fits == true and C.good) or (fits == false and C.danger) or nil
  elseif cell.new then
    color = C.gold
  elseif item and S.get("qualityColors") then
    color = (item.attuned and C.gold) or (item.lore and C.accent) or (item.magic and C.magic) or nil
  end
  if color then highlight(x, y, size, scale, color) end
  if item and S.isJunk(item.id) then
    ui.DrawCircleFilled(x + 6 * scale, y + 6 * scale, 2.5 * scale, C.danger[1], C.danger[2], C.danger[3], 1)
  elseif cell.kept then
    ui.DrawCircleFilled(x + 6 * scale, y + 6 * scale, 2.5 * scale, C.good[1], C.good[2], C.good[3], 1)
  end
  if S.isLocked and S.isLocked(cell) then
    ui.DrawRectFilled(x + size - 8 * scale, y + 4 * scale, x + size - 3 * scale, y + 9 * scale,
      C.faint[1], C.faint[2], C.faint[3], 0.9, 1 * scale)
  end
  local kind = bagScope and V.bagKind(item)
  if kind then
    local badgeW, badgeH = T.TextSize(kind.badge, T.font.tiny)
    local left, bottom = x + 2 * scale, y + size - 2 * scale
    ui.DrawRectFilled(left, bottom - badgeH - 2 * scale, left + badgeW + 4 * scale, bottom,
      C.inset[1], C.inset[2], C.inset[3], 0.96, 3 * scale)
    T.Text(left + 2 * scale, bottom - badgeH - scale, kind.badge, C.accent, T.font.tiny)
  end
  if not cell.stale then
    local popup = "##itemActions" .. id
    if hovered and (ui.IsMouseClicked(ui.Mouse.Middle) or (menuChord and ui.IsMouseClicked(ui.Mouse.Right))) then
      ui.OpenPopup(popup)
    end
    if ui.BeginPopup(popup) then
      itemMenu(cell, bagScope, pinned)
      ui.EndPopup()
    end
  end
  return hovered
end

local function inBag(cell, place)
  return not place or cell.place:sub(1, #place + 1) == (place .. ":")
end

local function newCard(id, label, count, cells, columns, scale)
  local closed = ui.GetSetting("stow.collapsed." .. id) == "1"
  local captionWidth = T.TextSize(label, T.font.small) + 29 * scale
  if count then captionWidth = captionWidth + T.TextSize(count, T.font.tiny) + 6 * scale end
  return {id = id, label = label, count = count, cells = cells, tiles = #cells,
    columns = columns, captionWidth = captionWidth, closed = closed}
end

local function collect(data, scope, state, scale, columns, freeCells)
  local cards = {}
  local pin = state.pinned[scope]
  local compress = S.get("compressEmpty")
  local query = state.query
  for _, group in ipairs(data.groups) do
    local cells, total, matched = {}, 0, 0
    for _, cell in ipairs(group.cells) do
      if inBag(cell, pin) then
        if cell.empty and not cell.stale then freeCells[#freeCells + 1] = cell end
        if not (compress and cell.empty and not cell.stale) then cells[#cells + 1] = cell end
        if cell.item then
          total = total + 1
          if cell.match then matched = matched + 1 end
        end
      end
    end
    local showEmptyHeader = group.id ~= "empty" and not pin and not S.get("hideEmptyGroups")
    if #cells > 0 or showEmptyHeader then
      local label = group.label
      local kind = group.bag and V.bagKind(group.bag.item)
      if kind then label = label .. " · " .. kind.label end
      local count = query ~= "" and (matched .. " / " .. total) or nil
      local limit = data.mode == "combined" and columns or math.min(columns, 7)
      cards[#cards + 1] = newCard(scope .. "." .. group.id, label, count, cells, limit, scale)
    end
  end
  return cards
end

local function cleanPin(data, state, scope)
  local pin = state.pinned[scope]
  if not pin then return end
  if state.showBags then
    for _, bag in ipairs(data.bags) do
      if bag.place == pin then return end
    end
  end
  state.pinned[scope] = nil
end

local function cardHeader(card, x, y, w, h, scale, accent)
  local key = "stow.collapsed." .. card.id
  local closed = card.closed
  if T.Hit("##heading." .. card.id, x, y, x + w, y + h, false) then
    closed = not closed
    ui.SetSetting(key, closed and "1" or "0")
  end
  local hovered = ui.IsItemHovered()
  local c = hovered and accent or C.muted
  local middle = y + h / 2
  local cx, k = x + 9 * scale, 2.5 * scale
  if closed then
    ui.DrawLine(cx - k, middle - k, cx, middle, c[1], c[2], c[3], 1, 1.2 * scale)
    ui.DrawLine(cx, middle, cx - k, middle + k, c[1], c[2], c[3], 1, 1.2 * scale)
  else
    ui.DrawLine(cx - k, middle - k / 2, cx, middle + k / 2, c[1], c[2], c[3], 1, 1.2 * scale)
    ui.DrawLine(cx, middle + k / 2, cx + k, middle - k / 2, c[1], c[2], c[3], 1, 1.2 * scale)
  end
  local right = x + w - 7 * scale
  if card.count then
    local countW, countH = T.TextSize(card.count, T.font.tiny)
    T.Text(right, middle - countH / 2, card.count, C.faint, T.font.tiny, "right")
    right = right - countW - 6 * scale
  end
  local left = x + 17 * scale
  local _, textH = T.TextSize(card.label, T.font.small)
  local label = T.Fit(card.label, math.max(1, right - left), T.font.small)
  T.Text(left, middle - textH / 2, label, C.text, T.font.small)
  if hovered and label ~= card.label then ui.SetTooltip(card.label) end
  return not closed
end

local function drawCards(section, x, y, metrics, scale, query, selectedBag, clipTop, clipBottom)
  local accent = section.scope == "inventory" and C.accent or (bankTints[S.get("bankTheme")] or C.accent)
  local step = metrics.tile + metrics.tileGap
  for n, card in ipairs(section.cards) do
    local box = section.packed.boxes[n]
    local xx, yy = x + box.x, y + box.y
    if yy + box.h >= clipTop and yy <= clipBottom then
      ui.DrawRectFilled(xx, yy, xx + box.w, yy + box.h, C.window[1], C.window[2], C.window[3], 0.96, 4 * scale)
      ui.DrawRect(xx, yy, xx + box.w, yy + box.h, accent[1], accent[2], accent[3], 0.33, 4 * scale, 1)
      if cardHeader(card, xx, yy, box.w, metrics.header, scale, accent) and not card.closed then
        for i, cell in ipairs(card.cells) do
          local dy = yy + metrics.header + ((i - 1) // box.columns) * step
          if dy + metrics.tile >= clipTop and dy <= clipBottom then
            local dx = xx + metrics.pad + ((i - 1) % box.columns) * step
            drawCell(cell, dx, dy, metrics.tile, scale, query, selectedBag)
          end
        end
      end
    end
  end
end

local function traySize(data, state, scope, width, scale)
  if not data or #data.bags == 0 or not state.showBags then return nil end
  local tile, slotGap, pad = 27 * scale, 3 * scale, 4 * scale
  local columns = math.min(#data.bags, math.max(1, math.floor((width - 2 * pad + slotGap) / (tile + slotGap))))
  local rows = math.ceil(#data.bags / columns)
  local pin = state.pinned[scope]
  local height = rows * (tile + slotGap) - slotGap + 2 * pad + (pin and 22 * scale or 0)
  return {data = data, scope = scope, columns = columns, tile = tile, slotGap = slotGap, pad = pad,
    width = columns * (tile + slotGap) - slotGap + 2 * pad, height = height}
end

local function drawTray(tray, state, x, y, scale)
  local step = tray.tile + tray.slotGap
  local pick, active
  ui.DrawRectFilled(x, y, x + tray.width, y + tray.height, C.window[1], C.window[2], C.window[3], 0.96, 4 * scale)
  ui.DrawRect(x, y, x + tray.width, y + tray.height, C.frameBorder[1], C.frameBorder[2], C.frameBorder[3],
    0.6, 4 * scale, 1)
  for n, bag in ipairs(tray.data.bags) do
    local bx = x + tray.pad + ((n - 1) % tray.columns) * step
    local by = y + tray.pad + ((n - 1) // tray.columns) * step
    if drawCell(bag, bx, by, tray.tile, scale, "", nil, tray.scope, state.pinned) then pick = bag.place end
    if bag.place == state.pinned[tray.scope] then active = bag end
  end
  if active then
    local by = y + tray.height - 22 * scale
    if T.Button("##clearBag." .. tray.scope, x + 4 * scale, by, x + 22 * scale, by + 17 * scale, scale, "×") then
      state.pinned[tray.scope] = nil
    end
    if ui.IsItemHovered() then ui.SetTooltip("Clear bag filter") end
    T.Text(x + 26 * scale, by + 2 * scale,
      T.Fit(active.item.name, math.max(1, tray.width - 30 * scale), T.font.tiny), C.faint, T.font.tiny)
  end
  return pick
end

local function makeBody(sections, state, cap, metrics, scale)
  local plan = {width = 0, height = 0, blocks = {}}
  local function add(height, width, draw)
    if height <= 0 then return end
    local y = plan.height > 0 and plan.height + metrics.gap or 0
    plan.width = math.max(plan.width, width)
    plan.height = y + height
    plan.blocks[#plan.blocks + 1] = {y = y, height = height, draw = draw}
  end
  local function line(text, color)
    local tw, th = T.TextSize(text, T.font.small)
    add(th + 2 * scale, math.min(cap, tw), function(x, y)
      T.Text(x + 2 * scale, y + scale, T.Fit(text, math.max(1, cap - 4 * scale), T.font.small), color, T.font.small)
    end)
  end
  for _, section in ipairs(sections) do
    local tray = traySize(section.data, state, section.scope, cap, scale)
    local packed = Cards.pack(section.cards, cap, metrics)
    section.packed = packed
    if section.scope == "shared" and (tray or packed.height > 0) then line("Shared bank", C.muted) end
    local hoveredBag
    if tray then
      add(tray.height, tray.width, function(x, y)
        hoveredBag = drawTray(tray, state, x, y, scale)
      end)
    end
    add(packed.height, packed.width, function(x, y, top, bottom)
      drawCards(section, x, y, metrics, scale, state.query, hoveredBag, top, bottom)
    end)
  end
  if plan.height == 0 then
    line(state.query ~= "" and "No matching items" or "No items", C.muted)
  end
  local note = S.status()
  if note then
    local tw, th = T.TextSize(note, T.font.tiny)
    add(th + 2 * scale, math.min(cap, tw + 4 * scale), function(x, y)
      T.Text(x + 2 * scale, y, T.Fit(note, math.max(1, cap - 4 * scale), T.font.tiny), C.muted, T.font.tiny)
      if ui.IsMouseHoveringRect(x, y, x + math.min(cap, tw), y + th) then ui.SetTooltip(note) end
    end)
  end
  return plan
end

local function drawBody(plan, width)
  local x, y = ui.GetCursorScreenPos()
  local _, top = ui.GetWindowPos()
  local _, windowHeight = ui.GetWindowSize()
  local bottom = top + windowHeight
  for _, block in ipairs(plan.blocks) do
    if y + block.y + block.height >= top and y + block.y <= bottom then block.draw(x, y + block.y, top, bottom) end
  end
  ui.SetCursorScreenPos(x, y)
  ui.Dummy(width, plan.height)
end

function V.compact(screen, title, key, scope, opts, onClose)
  local shown, stockX, stockY = API.windows.Replace(screen)
  local state = compactStates[key]
  if not shown then
    if state and state.screen == screen then state.open = false end
    return
  end
  if not state then
    state = {pinned = {}, query = ""}
    compactStates[key] = state
  end
  if not state.open or state.screen ~= screen then
    state.open, state.screen = true, screen
    state.showBags, state.showFree = S.get("showBagBar"), not S.get("compressEmpty")
    state.query, state.searchOpen = "", false
    state.pinned = {}
  end
  state.title, state.closeRequested = title, false

  local io = ui.GetIO()
  local scale = io.uiScale or 1
  local margin = math.min(8 * scale, io.width / 8, io.height / 8)
  local maxWidth, maxHeight = math.max(1, io.width - 2 * margin), math.max(1, io.height - 2 * margin)
  local columns = S.get("columns")
  local metrics = {pad = 4 * scale, gap = 5 * scale, tile = math.max(1, math.min(S.get("size") * scale, maxWidth - 8 * scale)),
    tileGap = 3 * scale, header = math.max(17 * scale, select(2, T.TextSize("Ag", T.font.small)) + 4 * scale)}

  local data = S.view(scope, nil, state.query)
  local shared = scope == "bank" and S.view("shared", nil, state.query) or nil
  local mainFree, sharedFree = {}, {}
  cleanPin(data, state, scope)
  local sections = {{scope = scope, data = data, cards = collect(data, scope, state, scale, columns, mainFree)}}
  if shared then
    cleanPin(shared, state, "shared")
    sections[#sections + 1] = {scope = "shared", data = shared,
      cards = collect(shared, "shared", state, scale, columns, sharedFree)}
  end
  state.freeCells = mainFree
  state.dropCells = state.pinned.shared and sharedFree or mainFree
  state.dropLabel = shared and (state.pinned.shared and " in the shared bank" or " in the personal bank") or nil
  if #sharedFree > 0 then
    state.freeCells = {table.unpack(mainFree)}
    for _, cell in ipairs(sharedFree) do state.freeCells[#state.freeCells + 1] = cell end
  end
  if state.showFree and S.get("compressEmpty") then
    local freeCards = {}
    if #mainFree > 0 then
      freeCards[#freeCards + 1] = newCard(scope .. ".empty", shared and "Personal bank free slots" or "Free slots",
        tostring(#mainFree), mainFree, columns, scale)
    end
    if #sharedFree > 0 then
      freeCards[#freeCards + 1] = newCard("shared.empty", "Shared bank free slots", tostring(#sharedFree), sharedFree, columns, scale)
    end
    sections[#sections + 1] = {scope = scope, cards = freeCards}
  end
  local free = (data.free or 0) + (shared and shared.free or 0)
  local capacity = (data.capacity or 0) + (shared and shared.capacity or 0)
  if state.pinned[scope] or state.pinned.shared then free = #state.freeCells end
  local dock = Dock.measure(screen, scope, opts or {}, state, scale, free, capacity)
  -- The grid option limits normal wrapping width. A wider dock still gets its intrinsic one-row width where it fits.
  local cap = math.min(maxWidth, math.max(dock.width, columns * (metrics.tile + metrics.tileGap)))
  local body = makeBody(sections, state, cap, metrics, scale)
  local width = math.min(math.floor(maxWidth), math.ceil(math.max(body.width, math.min(cap, dock.width))))
  local searchHeight = state.searchOpen and 24 * scale or 0
  local dockHeight = Dock.height(dock, width)
  local bodySpace = math.max(1, maxHeight - searchHeight - dockHeight - metrics.gap)
  local scroll = body.height > bodySpace
  local scrollBar = 10 * scale
  if scroll then
    body = makeBody(sections, state, math.max(1, cap - scrollBar), metrics, scale)
    width = math.min(math.floor(maxWidth), math.ceil(math.max(body.width + scrollBar, math.min(cap, dock.width))))
    dockHeight = Dock.height(dock, width)
    bodySpace = math.max(1, maxHeight - searchHeight - dockHeight - metrics.gap)
  end
  local bodyHeight = math.min(body.height, bodySpace)
  local height = math.min(math.floor(maxHeight), math.ceil(searchHeight + bodyHeight + dockHeight + metrics.gap))

  local positionKey = "stow.compact.pos." .. key
  if state.x == nil then
    local saved = ui.GetSetting(positionKey) or ui.GetSetting("stow.layout." .. key) or ""
    local x, y = saved:match("^(-?%d+),(-?%d+)")
    state.x, state.y = tonumber(x) or stockX or 100, tonumber(y) or stockY or 100
  end
  local x = math.min(math.max(margin, state.x), math.max(margin, io.width - width - margin))
  local y = math.min(math.max(margin, state.y), math.max(margin, io.height - height - margin))
  ui.SetNextWindowPos(math.floor(x), math.floor(y), ui.Cond.Always)
  ui.SetNextWindowSize(width, height, ui.Cond.Always)
  local flags = ui.WindowFlags.NoSavedSettings | ui.WindowFlags.NoTitleBar | ui.WindowFlags.NoBackground
    | ui.WindowFlags.NoResize | ui.WindowFlags.NoMove | ui.WindowFlags.NoCollapse
    | ui.WindowFlags.NoScrollbar | ui.WindowFlags.NoScrollWithMouse
  style.Push()
  ui.PushStyleVar(ui.StyleVar.WindowPadding, 0, 0)
  local visible = ui.Begin(title .. "###stow." .. key, nil, flags)
  ui.PopStyleVar()
  API.windows.Placed(screen, x, y, width, height)
  local close = escape.Frame(screen)
  T.ResetRightClick()
  if visible then
    local cx, cy = ui.GetCursorScreenPos()
    if state.searchOpen then Dock.search(state, scale, width) end
    ui.SetCursorScreenPos(cx, cy + searchHeight)
    if scroll then
      ui.PushStyleVar(ui.StyleVar.ScrollbarSize, scrollBar)
      if ui.BeginChild("##stowGrid", width, bodyHeight, false) then drawBody(body, math.max(1, width - scrollBar)) end
      ui.EndChild()
      ui.PopStyleVar()
    else
      drawBody(body, width)
    end
    ui.SetCursorScreenPos(cx, cy + searchHeight + bodyHeight + metrics.gap)
    state.dragging = false
    Dock.draw(dock, width)
  end
  ui.End()
  style.Pop()
  if state.dragging and not S.get("windowLocked") and ((io.mouseDX or 0) ~= 0 or (io.mouseDY or 0) ~= 0) then
    state.x = math.floor(math.min(math.max(margin, x + (io.mouseDX or 0)), math.max(margin, io.width - width - margin)))
    state.y = math.floor(math.min(math.max(margin, y + (io.mouseDY or 0)), math.max(margin, io.height - height - margin)))
    ui.SetSetting(positionKey, state.x .. "," .. state.y)
  end
  if close or state.closeRequested then
    if onClose then onClose() else API.windows.Show(screen, false) end
    state.open = false
  end
end

return V
