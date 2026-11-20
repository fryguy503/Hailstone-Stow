local S = dofile("lib/stow_model.lua")
local O = dofile("lib/stow_options.lua")
local T = dofile("lib/theme.lua")
local style = dofile("lib/style.lua")
local escape = dofile("lib/escape.lua")
local slots = dofile("lib/items.lua")
local API = hs.UI
local C = T.color
local V = { model = S }

local names = { grouped = "Categories", combined = "Combined", bags = "By bag" }
local modes = { "grouped", "combined", "bags" }
local bankTints = { slate = { 0.58, 0.65, 0.78, 1 }, blue = { 0.42, 0.74, 0.99, 1 } }
local bagKinds = {
  [2] = { badge = "Q", label = "Quiver" },
  [8] = { badge = "TH", label = "Throwing only" },
  [58] = { badge = "TS", label = "Tradeskill only" },
}
local searches, layouts, pinned, expandedFree = {}, {}, {}, {}

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

local function toolbar(scope, scale)
  searches[scope] = searches[scope] or ""
  V.actions(scope)
  ui.SameLine()
  if ui.Button("Settings") then ui.OpenPopup("##stowSettings") end
  if ui.BeginPopup("##stowSettings") then
    O.draw(S)
    ui.EndPopup()
  end

  local modeKey = scope .. "Mode"
  local mode = S.get(modeKey)
  if not names[mode] then mode = "grouped" end
  if scope == "bank" and mode == "grouped" and not S.get("bankFiltering") then mode = "combined" end
  local w = ui.GetContentRegionAvail()
  local modeW = math.min(120 * scale, w * 0.43)
  ui.SetNextItemWidth(math.max(1, w - modeW - 34 * scale))
  searches[scope] = ui.InputTextWithHint("##stowSearch", "Find items", searches[scope], 256)
  if ui.IsItemHovered() then
    ui.SetTooltip('Search by name, type:armor, bag:backpack or is:new.\nUse quotes for phrases and - to exclude a term.')
  end
  ui.SameLine(0, 4 * scale)
  if ui.Button("×##stowClear", 24 * scale) then searches[scope] = "" end
  if ui.IsItemHovered() then ui.SetTooltip("Clear search") end
  ui.SameLine(0, 4 * scale)
  ui.SetNextItemWidth(modeW)
  if ui.BeginCombo("##stowMode", names[mode]) then
    for _, option in ipairs(modes) do
      if ui.Selectable(names[option], option == mode) then
        if scope == "bank" and option == "grouped" then S.set("bankFiltering", true) end
        S.set(modeKey, option)
        mode = option
      end
    end
    ui.EndCombo()
  end
  return mode, searches[scope]
end

local function itemMenu(cell, bagScope)
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

local function drawCell(cell, x, y, size, scale, query, selectedBag, bagScope)
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
      itemMenu(cell, bagScope)
      ui.EndPopup()
    end
  end
  return hovered
end

local function freeCell(group, cells, x, y, size, scale)
  local clicked = T.Hit("##free." .. group, x, y, x + size, y + size, false)
  local over = ui.IsItemHovered()
  local cursor = (over or clicked) and API.inventory.Item(API.inventory.CursorSlot)
  local target, possible, compatible, unknown = nil, nil, 0, 0
  if cursor then
    if not API.inventory.CanPlace then
      possible = cells[1]
    else
      for _, cell in ipairs(cells) do
        local fits = S.canPlace(cell)
        if fits == true then
          target = target or cell
          compatible = compatible + 1
          if not over then break end
        elseif fits == nil then
          possible = possible or cell
          unknown = unknown + 1
        end
      end
    end
  end
  local color = (target and C.good) or (cursor and not possible and C.danger) or C.accent
  ui.DrawRectFilled(x, y, x + size, y + size, color[1], color[2], color[3], over and 0.18 or 0.08, 5 * scale)
  highlight(x, y, size, scale, color)
  local _, line = T.TextSize("Ag", T.font.small)
  T.Text(x + size / 2, y + (size - line) / 2, "+" .. #cells, color, T.font.small, "center")
  if over then
    local count = string.format("%d empty slots", #cells)
    if cursor and API.inventory.CanPlace and unknown < #cells then
      count = string.format("%d / %d compatible slots", compatible, #cells)
      if unknown > 0 then count = count .. string.format(" (%d unknown)", unknown) end
    end
    ui.SetTooltip(count .. "\nClick while holding an item to place it\nRight-click to show individual slots")
    if ui.IsMouseClicked(ui.Mouse.Right) then
      T.TakeRightClick()
      expandedFree[group] = true
    end
  end
  if clicked and (target or possible) then S.click(target or possible, "left") end
end

local function inBag(cell, place)
  return not place or cell.place:sub(1, #place + 1) == (place .. ":")
end

local function grid(group, id, size, scale, query, selectedBag, pinnedBag)
  local compress = S.get("compressEmpty")
  if compress and expandedFree[id] and ui.SmallButton("Combine empty slots##" .. id) then expandedFree[id] = nil end
  local w = ui.GetContentRegionAvail()
  local columns = math.max(1, math.min(S.get("columns"), math.floor((w + 5 * scale) / (size + 5 * scale))))
  local gap = 5 * scale
  local x, y = ui.GetCursorScreenPos()
  local cursorX, cursorY = ui.GetCursorPos()
  local _, top = ui.GetWindowPos()
  local _, windowH = ui.GetWindowSize()
  local bottom = top + windowH
  local n, empty = 0, {}
  compress = compress and not expandedFree[id]
  for _, cell in ipairs(group.cells) do
    if inBag(cell, pinnedBag) then
      if compress and cell.empty and not cell.stale then
        empty[#empty + 1] = cell
      else
        local drawY = y + (n // columns) * (size + gap)
        if drawY + size >= top and drawY <= bottom then
          drawCell(cell, x + (n % columns) * (size + gap), drawY, size, scale, query, selectedBag)
        end
        n = n + 1
      end
    end
  end
  if #empty > 0 then
    freeCell(id, empty, x + (n % columns) * (size + gap), y + (n // columns) * (size + gap), size, scale)
    n = n + 1
  end
  ui.SetCursorPos(cursorX, cursorY)
  ui.Dummy(math.min(w, columns * (size + gap)), math.ceil(n / columns) * (size + gap))
end

local function heading(id, label, count, accent, scale)
  local w = ui.GetContentRegionAvail()
  local x, y = ui.GetCursorScreenPos()
  local h = 26 * scale
  local key = "stow.collapsed." .. id
  local closed = ui.GetSetting(key) == "1"
  if T.Hit("##heading." .. id, x, y, x + w, y + h, false) then
    closed = not closed
    ui.SetSetting(key, closed and "1" or "0")
  end
  ui.DrawRectFilled(x, y, x + w, y + h, accent[1], accent[2], accent[3], ui.IsItemHovered() and 0.16 or 0.09, 6 * scale)
  local _, line = T.TextSize("Ag", T.font.small)
  local mid = y + (h - line) / 2
  T.Text(x + 8 * scale, mid, closed and "+" or "−", accent, T.font.small)
  local countW = T.TextSize(count, T.font.small)
  local short = T.Fit(label, math.max(1, w - countW - 40 * scale), T.font.small)
  T.Text(x + 25 * scale, mid, short, C.text, T.font.small)
  T.Text(x + w - 9 * scale, mid, count, C.muted, T.font.small, "right")
  if short ~= label and ui.IsItemHovered() then ui.SetTooltip(label) end
  return not closed
end

local function bagBar(bags, scope, scale)
  local size = 29 * scale
  local w = ui.GetContentRegionAvail()
  local x, y = ui.GetCursorScreenPos()
  local cursorX, cursorY = ui.GetCursorPos()
  local step = size + 5 * scale
  local cols = math.max(1, math.floor((w + 5 * scale) / step))
  local selected, active
  for n, bag in ipairs(bags) do
    if drawCell(bag, x + ((n - 1) % cols) * step, y + ((n - 1) // cols) * step, size, scale, "", nil, scope) then
      selected = bag.place
    end
    if bag.place == pinned[scope] then active = bag end
  end
  ui.SetCursorPos(cursorX, cursorY)
  ui.Dummy(math.min(w, cols * step), math.ceil(#bags / cols) * step)
  if active then
    if ui.SmallButton("Clear bag filter##" .. scope) then pinned[scope] = nil end
    ui.SameLine()
    ui.TextDisabled(active.item.name)
  else
    pinned[scope] = nil
  end
  return selected
end

local function drawGroups(data, scope, scale, query, selectedBag)
  local accent = scope == "inventory" and C.accent or (bankTints[S.get("bankTheme")] or C.accent)
  local size = S.get("size") * scale
  local pinnedBag = pinned[scope]
  for _, group in ipairs(data.groups) do
    local total, matched, cells = group.total or 0, group.matched or 0, #group.cells
    if pinnedBag then
      total, matched, cells = 0, 0, 0
      for _, cell in ipairs(group.cells) do
        if inBag(cell, pinnedBag) then
          cells = cells + 1
          if cell.item then
            total = total + 1
            if cell.match then matched = matched + 1 end
          end
        end
      end
    end
    if cells > 0 or (not pinnedBag and not S.get("hideEmptyGroups")) then
      local count = query ~= "" and (matched .. " / " .. total) or tostring(total)
      if total == 0 and cells > 0 then count = tostring(cells) end
      local id = scope .. "." .. group.id
      local kind = group.bag and V.bagKind(group.bag.item)
      local label = group.label .. (kind and (" · " .. kind.label) or "")
      if heading(id, label, count, accent, scale) then
        grid(group, id, size, scale, query, selectedBag, pinnedBag)
      end
    end
  end
end

function V.storage(scope, scale, footer)
  local mode, query = toolbar(scope, scale)
  local data = S.view(scope, mode, query)
  local shared = scope == "bank" and S.view("shared", mode, query) or nil
  local cap = string.format("%d / %d free", data.free or 0, data.capacity or 0)
  if query ~= "" then cap = cap .. string.format("   ·   %d matches", (data.matched or 0) + (shared and shared.matched or 0)) end
  ui.TextDisabled(cap)
  ui.SameLine()
  ui.TextDisabled("Middle-click a slot for options")
  local note = S.status()
  if note then ui.TextWrapped(note) end
  local selectedBag, sharedBag
  if S.get("showBagBar") then
    selectedBag = bagBar(data.bags, scope, scale)
    if shared then sharedBag = bagBar(shared.bags, "shared", scale) end
  else
    pinned[scope], pinned.shared = nil, nil
  end
  if ui.BeginChild("##stowGrid", 0, -footer, false) then
    drawGroups(data, scope, scale, query, selectedBag)
    if shared then
      ui.Separator()
      ui.Text("Shared bank")
      drawGroups(shared, "shared", scale, query, sharedBag)
    end
  end
  ui.EndChild()
end

return V
