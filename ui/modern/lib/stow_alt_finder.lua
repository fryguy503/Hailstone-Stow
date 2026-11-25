local existing = rawget(_G, "HailstoneStowAltFinder")
if existing then return existing end

local API = hs.UI
local Rules = dofile("lib/stow_rules.lua")
local T = dofile("lib/theme.lua")
local Style = dofile("lib/style.lua")
local Icons = dofile("lib/menuicons.lua")
local C = T.color
local Finder = {}
local window = { open = false, query = "", area = "all" }

local TITLE = "Alt Finder###stow.alt-finder"
local AREAS = {
  { "all", "Bags & personal bank" }, { "carried", "Bags only" }, { "bank", "Personal bank only" },
}
local SESSION_LABEL = { ["local"] = "This client", boxed = "Boxed client", offline = "Offline" }
local FONT_CAPTION, FONT_BODY, FONT_TITLE = 3, 5, 6
local WIDTH, HEIGHT = 744, 500
local MIN_WIDTH, MIN_HEIGHT = 385, 330
local LAYOUT_KEY = "stow.layout.altFinder"
local LIVE_DARK, LIVE_LIGHT = { 0.51, 0.85, 0.68, 1 }, { 0.04, 0.37, 0.18, 1 }

local function liveColor()
  return C.window[1] > 0.65 and LIVE_LIGHT or LIVE_DARK
end

local function panel(x, y, w, h, color, alpha, radius)
  ui.DrawRectFilled(x, y, x + w, y + h, color[1], color[2], color[3], alpha or color[4] or 1, radius or 0)
end

local function rule(x1, y1, x2, y2)
  ui.DrawLine(x1, y1, x2, y2, C.ink[1], C.ink[2], C.ink[3], 0.12, 1)
end

local function fit(x, y, text, width, color, font)
  if width <= 0 then return end
  ui.PushClipRect(x, y, x + width, y + select(2, T.TextSize("Ag", font)) + 2, true)
  T.Text(x, y, T.Fit(text, width, font), color, font)
  ui.PopClipRect()
end

local function tile(x, y, size, s, accent)
  panel(x, y, size, size, accent and C.accent or C.ink, accent and 0.12 or 0.065, 4 * s)
  local edge = accent and C.accent or C.ink
  ui.DrawRect(x, y, x + size, y + size, edge[1], edge[2], edge[3], 0.24, 4 * s, 1)
end

local function dot(x, y, s, color)
  ui.DrawCircleFilled(x, y, 2.6 * s, color[1], color[2], color[3], 1)
end

local function ageLabel(age)
  if type(age) ~= "number" then return "Last seen" end
  if age < 60 then return "< 1 min ago" end
  if age < 3600 then return age // 60 .. " min ago" end
  if age < 86400 then return age // 3600 .. " h ago" end
  local days = age // 86400
  return days .. (days == 1 and " day ago" or " days ago")
end

local function slotLabel(item)
  local carried = item.where == "carried"
  local index = carried and (item.slot - 22) or (item.slot + 1)
  local area = carried and "Bag" or "Bank"
  if item.sub and item.sub >= 0 then
    local position = string.format("%s %d, slot %d", area, index, item.sub + 1)
    return item.bag and (item.bag .. " · " .. position) or position, position
  end
  local position = (carried and "General slot " or "Bank slot ") .. index
  return position, position
end

local function searchTerm(query)
  return (query or ""):match("^%s*(.-)%s*$"):lower()
end

local function inventoryView(query)
  local inventory = API.inventory
  local search = inventory.AltFinder
  if type(search) == "function" then
    local view = search(query)
    if type(view) == "table" then return view end
  end

  local name = API.character.Name()
  if not name or name == "" then return nil end
  local rows = inventory.AllItems()
  if not rows then return nil end
  local bankLive, bankAge = inventory.BankSeen()
  local character = { name = name, session = "local", bankSeen = bankLive == true or bankAge ~= nil }
  local items = {}
  for _, row in ipairs(rows) do
    if row.where == "carried" or row.where == "bank" then
      local bank = row.where == "bank"
      if bank then character.bankSeen = true end
      items[#items + 1] = {
        name = row.item.name, icon = row.item.icon, count = Rules.count(row),
        character = name, where = row.where, slot = row.slot, sub = row.sub, bag = row.bag,
        live = not row.stale and (not bank or bankLive == true), age = bank and bankAge or nil,
      }
    end
  end
  return { localOnly = true, characters = { character }, items = items }
end

local function resultRows(view, state)
  local query = searchTerm(state.query)
  local previous = state.result
  if previous and previous.view == view and previous.query == query and previous.area == state.area
      and previous.character == state.character then return previous end

  local result = { view = view, query = query, area = state.area, character = state.character,
    sessions = {}, items = {}, live = 0, cached = 0, online = 0 }
  for _, character in ipairs(view and view.characters or {}) do
    result.sessions[character.name] = character
    if character.session ~= "offline" then result.online = result.online + 1 end
  end

  local title, multiple
  for _, item in ipairs(view and view.items or {}) do
    if (not state.character or state.character == item.character)
        and (not state.area or state.area == "all" or state.area == item.where)
        and item.name:lower():find(query, 1, true) then
      result.items[#result.items + 1] = item
      if title and item.name ~= title then multiple = true end
      title = item.name
      if item.live then result.live = result.live + item.count else result.cached = result.cached + item.count end
    end
  end
  if not multiple then result.title = title end
  state.result = result
  return result
end

local function header(view, state, x, y, w, s, maxW, maxH)
  local h, icon, padding = 62 * s, 36 * s, 15 * s
  panel(x, y, w, h, C.titleActive, 1, 5 * s)
  if ui.DrawRectGradient then
    local a = C.accent
    ui.DrawRectGradient(x, y, x + w, y + h, a[1], a[2], a[3], 0.07, a[1], a[2], a[3], 0)
  end
  rule(x, y + h, x + w, y + h)

  local closeX = x + w - 31 * s
  T.Hit("##alt-finder-drag", x + 2 * s, y + 2 * s, closeX, y + h - 2 * s, false)
  if ui.IsItemActive() then
    local mx, my = ui.GetMousePos()
    state.drag = state.drag or { mx - x, my - y }
    if ui.IsMouseDragging(ui.Mouse.Left) then
      state.position = { math.max(0, math.min(mx - state.drag[1], maxW - w)),
        math.max(0, math.min(my - state.drag[2], maxH - select(2, ui.GetWindowSize()))) }
    end
  else
    state.drag = nil
  end
  if T.Button("##alt-finder-close", closeX, y + 10 * s, x + w - 9 * s, y + 32 * s, s, "×", { tooltip = "Close Alt Finder" }) then
    state.open = false
  end

  local iy = y + (h - icon) / 2
  tile(x + padding, iy, icon, s, true)
  Icons.Draw("Advanced Inventory", x + padding + icon / 2, iy + icon / 2, 21 * s, C.accent)
  local tx = x + padding + icon + 11 * s
  local world = view and view.world
  local worldW = world and math.min(T.TextSize(world, FONT_BODY) + 33 * s, w * 0.31) or 0
  local wx = closeX - worldW - 10 * s
  T.Text(tx, y + 12 * s, "STOW", C.accent, FONT_CAPTION)
  if ui.SetWindowFontScale then ui.SetWindowFontScale(1.20) end
  fit(tx, y + 26 * s, "Alt Finder", wx - tx, C.text, FONT_TITLE)
  if ui.SetWindowFontScale then ui.SetWindowFontScale(1) end
  if world and worldW > 30 * s then
    panel(wx, y + 16 * s, worldW, 28 * s, C.window, 0.85, 4 * s)
    Icons.Draw("Web Browser", wx + 13 * s, y + 30 * s, 13 * s, C.accent)
    fit(wx + 24 * s, y + 22 * s, world, worldW - 29 * s, C.text, FONT_BODY)
    if ui.IsMouseHoveringRect(wx, y + 16 * s, wx + worldW, y + 44 * s, true) then ui.SetTooltip("Server: " .. world) end
  end
  return h
end

local function combobox(id, value, options, width)
  local label = options[1][2]
  for _, entry in ipairs(options) do if value == entry[1] then label = entry[2]; break end end
  ui.SetNextItemWidth(width)
  if ui.BeginCombo(id, T.Fit(label, math.max(1, width - 30 * (ui.GetIO().uiScale or 1)), FONT_BODY)) then
    for _, entry in ipairs(options) do
      if ui.Selectable(entry[2] .. "##" .. tostring(entry[1]), entry[1] == value) then value = entry[1] end
    end
    ui.EndCombo()
  end
  return value
end

local function toolbar(view, state, x, y, w, s, sidebar)
  local p, h, gap = 12 * s, 49 * s, 7 * s
  local split = w < 440 * s
  local areaW = math.min(194 * s, w - 2 * p)
  local inputW = split and (w - 2 * p) or (w - 2 * p - areaW - gap)
  panel(x, y, w, h, C.window, 1)
  local fy = y + 10 * s
  local clearW = (state.query or "") ~= "" and 25 * s or 0
  local searchX = x + p + 13 * s
  ui.DrawCircle(searchX - 1 * s, fy + 12 * s, 4.3 * s, C.accent[1], C.accent[2], C.accent[3], 1, 1.4 * s)
  ui.DrawLine(searchX + 2 * s, fy + 15 * s, searchX + 6 * s, fy + 19 * s, C.accent[1], C.accent[2], C.accent[3], 1, 1.4 * s)
  ui.SetCursorScreenPos(x + p + 25 * s, fy)
  if state.focus then ui.SetKeyboardFocusHere(); state.focus = false end
  ui.SetNextItemWidth(math.max(1, inputW - 25 * s - clearW))
  state.query = ui.InputTextWithHint("##alt-finder-query", "Search item names…", state.query or "", 120)
  if clearW > 0 and T.Button("##alt-finder-clear", x + p + inputW - clearW + 2 * s, fy,
      x + p + inputW, fy + 27 * s, s, "×", { tooltip = "Clear search" }) then
    state.query, state.focus = "", true
  end

  local filterX = split and x + p or x + w - p - areaW
  local filterY = split and (y + h) or fy
  ui.SetCursorScreenPos(filterX, filterY)
  state.area = combobox("##alt-finder-place", state.area or "all", AREAS, areaW)
  if split then h = h + 37 * s end

  if not sidebar and not (view and view.localOnly) then
    local options = { { false, "All characters" } }
    for _, character in ipairs(view and view.characters or {}) do
      options[#options + 1] = { character.name, character.name .. " · " .. SESSION_LABEL[character.session] }
    end
    ui.SetCursorScreenPos(x + p, y + h - (split and 0 or 1) * s)
    state.character = combobox("##alt-finder-character", state.character or false, options, w - 2 * p) or nil
    h = h + 37 * s
  end
  rule(x, y + h, x + w, y + h)
  return h
end

local function characterButton(character, state, x, y, w, s)
  local h = 41 * s
  local name = character and character.name
  if T.Hit("##owner-" .. (name and ("character-" .. name) or "all"), x, y, x + w, y + h, false) then
    state.character = name
  end
  local selected = name == state.character
  local hovered = ui.IsItemHovered()
  if selected or hovered then
    panel(x, y, w, h, C.accent, selected and 0.15 or 0.075, 4 * s)
    if selected then
      local a = C.accent
      ui.DrawRect(x, y, x + w, y + h, a[1], a[2], a[3], 0.36, 4 * s, 1)
    end
  end
  local px, py, icon = x + 6 * s, y + 8 * s, 25 * s
  tile(px, py, icon, s)
  if character then
    T.Text(px + icon / 2, py + 4 * s, name:sub(1, 1), C.heading, FONT_BODY, "center")
    fit(px + 32 * s, y + 5 * s, name, w - 44 * s, C.text, FONT_BODY)
    dot(px + 35 * s, y + 28 * s, s, character.session == "offline" and C.faint or liveColor())
    fit(px + 41 * s, y + 22 * s, SESSION_LABEL[character.session], w - 49 * s, C.muted, FONT_CAPTION)
    if hovered and not character.bankSeen then ui.SetTooltip(name .. " has no personal bank snapshot yet.") end
  else
    Icons.Draw("Group Window", px + icon / 2, py + icon / 2, 17 * s, C.heading)
    fit(px + 32 * s, y + 12 * s, "All characters", w - 44 * s, C.text, FONT_BODY)
  end
end

local function roster(view, result, state, x, y, w, h, s)
  panel(x, y, w, h, C.popup, 1)
  rule(x + w, y, x + w, y + h)
  T.Text(x + 11 * s, y + 11 * s, "Characters", C.text, FONT_CAPTION)
  T.Text(x + w - 10 * s, y + 11 * s, result.online .. " online", liveColor(), FONT_CAPTION, "right")
  local top = 34 * s
  ui.SetCursorScreenPos(x + 6 * s, y + top)
  if ui.BeginChild("##alt-finder-roster", w - 12 * s, math.max(1, h - top - 4 * s), false) then
    local cx, cy = ui.GetCursorScreenPos()
    local cw = ui.GetContentRegionAvail()
    characterButton(nil, state, cx, cy, cw, s)
    for k, character in ipairs(view and view.characters or {}) do
      characterButton(character, state, cx, cy + k * 45 * s, cw, s)
    end
  end
  ui.EndChild()
end

local function summary(result, x, y, w, s)
  local h, p, icon = 63 * s, 13 * s, 34 * s
  panel(x, y, w, h, C.titleActive, 1)
  local iy = y + (h - icon) / 2
  local item = result.title and result.items[1]
  local texture, u0, v0, u1, v1
  if item and item.icon then texture, u0, v0, u1, v1 = API.assets.ItemIcon(item.icon) end
  if not T.Icon(x + p, iy, icon, s, texture, u0, v0, u1, v1, C.accent) then
    Icons.Draw("Inventory", x + p + icon / 2, iy + icon / 2, 20 * s, C.accent)
  end
  local slots = #result.items
  local count = slots .. (slots == 1 and " slot" or " slots")
  local right = x + w - p
  local startX = x + p + icon + 11 * s
  T.Text(right, y + 25 * s, count, C.muted, FONT_CAPTION, "right")
  fit(startX, y + 12 * s, result.title or "Item results", right - startX - T.TextSize(count, FONT_CAPTION) - 7 * s,
    C.text, T.font.normal)
  local live = result.live .. " live"
  local cached = result.cached .. " last seen"
  local tx = startX + T.Text(startX, y + 36 * s, live, liveColor(), FONT_CAPTION) + 7 * s
  T.Text(tx, y + 36 * s, "·", C.muted, FONT_CAPTION)
  fit(tx + 10 * s, y + 36 * s, cached, right - tx - 10 * s, C.gold, FONT_CAPTION)
  rule(x, y + h, x + w, y + h)
  return h
end

local function columns(x, w, s)
  local left = x + 12 * s
  local right = x + w - 10 * s
  local freshness = right - math.min(104 * s, w * 0.27)
  local quantity = freshness - 11 * s
  local location = left + math.min(144 * s, (quantity - left) * 0.41)
  return left, location, quantity, freshness, right
end

local function drawRow(result, item, index, x, y, w, h, s)
  if index % 2 == 0 then panel(x, y, w, h, C.ink, 0.035) end
  local left, location, quantity, freshness, right = columns(x, w, s)
  local character = result.sessions[item.character]
  local session = SESSION_LABEL[character and character.session] or SESSION_LABEL.offline
  local characterLine = result.title and item.character or item.name
  local sessionLine = result.title and session or (item.character .. " · " .. session)
  local place = item.where == "bank" and "Personal bank" or "Bags"
  local slot, shortSlot = slotLabel(item)
  local placeWidth = quantity - location - math.max(21 * s, T.TextSize(tostring(item.count), FONT_BODY) + 5 * s)
  local shownSlot = T.TextSize(slot, FONT_CAPTION) > placeWidth and shortSlot or slot

  fit(left, y + 7 * s, characterLine, location - left - 6 * s, C.text, FONT_BODY)
  fit(left, y + 24 * s, sessionLine, location - left - 6 * s, C.muted, FONT_CAPTION)
  local placeX = location
  if placeWidth >= 130 * s then
    Icons.Draw(item.where == "bank" and "Bazaar Search" or "Inventory", location + 6 * s, y + 14 * s, 12 * s, C.accent)
    placeX = placeX + 16 * s
  end
  fit(placeX, y + 7 * s, place, placeWidth - (placeX - location), C.heading, FONT_BODY)
  fit(location, y + 24 * s, shownSlot, placeWidth, C.muted, FONT_CAPTION)
  T.Text(quantity, y + 15 * s, tostring(item.count), C.text, FONT_BODY, "right")
  local freshColor = item.live and liveColor() or C.gold
  if item.live then
    dot(freshness + 3 * s, y + 22 * s, s, freshColor)
  else
    Icons.Draw("Alarm", freshness + 5 * s, y + 15 * s, 10 * s, freshColor)
  end
  fit(freshness + 13 * s, y + (item.live and 15 or 7) * s, item.live and "Live now" or ageLabel(item.age),
    right - freshness - 13 * s, freshColor, FONT_BODY)
  if not item.live then
    local tag = item.where == "bank" and "Bank snapshot" or "Bag snapshot"
    fit(freshness + 13 * s, y + 24 * s, tag, right - freshness - 13 * s, C.muted, FONT_CAPTION)
  end
  if ui.IsWindowHovered() and ui.IsMouseHoveringRect(x, y, x + w, y + h, true) then
    local when = item.live and "Live now" or ageLabel(item.age)
    if not item.live and item.seen and item.seen > 0 then
      local ok, exact = pcall(os.date, "%b %d, %Y at %I:%M %p", item.seen)
      if ok and exact then when = "Last seen " .. exact end
    end
    ui.SetTooltip(item.name .. " × " .. item.count .. "\n" .. item.character .. " · " .. session
      .. "\n" .. place .. " · " .. slot .. "\n" .. when)
  end
  rule(x, y + h, x + w, y + h)
end

local function results(view, result, state, x, y, w, h, s)
  local top = summary(result, x, y, w, s)
  if not view or #result.items == 0 then
    local character = result.sessions[state.character] or (view and view.localOnly and view.characters[1])
    local empty = "No items match this search."
    if not view then empty = "Waiting for your character’s inventory…"
    elseif state.area == "bank" and character and not character.bankSeen then
      empty = "No personal bank snapshot for " .. character.name .. "."
    end
    fit(x + 13 * s, y + top + 23 * s, empty, w - 26 * s, C.muted, FONT_BODY)
    return
  end

  local headerH = 26 * s
  local listH = math.max(1, h - top - headerH)
  local rowH, firstY = 44 * s, y + top + headerH
  panel(x, y + top, w, headerH, C.popup, 1)
  local scrollBarWidth = #result.items * rowH > listH and 10 * s or 0
  local left, location, quantity, freshness = columns(x, w - scrollBarWidth, s)
  local hy = y + top + 6 * s
  fit(left, hy, result.title and "Character" or "Item / character", location - left - 5 * s, C.muted, FONT_CAPTION)
  T.Text(location, hy, "Location", C.muted, FONT_CAPTION)
  T.Text(quantity, hy, "Qty", C.muted, FONT_CAPTION, "right")
  T.Text(freshness, hy, "Last seen", C.muted, FONT_CAPTION)

  ui.SetCursorScreenPos(x, firstY)
  if ui.BeginChild("##alt-finder-results", w, listH, false) then
    if state.displayedQuery ~= result.query or state.displayedArea ~= state.area or state.displayedCharacter ~= state.character then
      ui.SetScrollY(0)
      state.displayedQuery, state.displayedArea, state.displayedCharacter = result.query, state.area, state.character
    end
    local cx, cy = ui.GetCursorScreenPos()
    local scroll = ui.GetScrollY()
    local first = math.min(#result.items, math.floor(scroll / rowH) + 1)
    local last = math.min(#result.items, math.ceil((scroll + listH) / rowH))
    local availableW = ui.GetContentRegionAvail()
    local contentW = math.min(w - scrollBarWidth, availableW)
    for i = first, last do drawRow(result, result.items[i], i, cx, cy + (i - 1) * rowH, contentW, rowH, s) end
    ui.Dummy(contentW, #result.items * rowH)
  end
  ui.EndChild()
end

local function windowBounds(state, io, s)
  if not state.layout then
    local saved = ui.GetSetting(LAYOUT_KEY) or ""
    local x, y, w, h = saved:match("^(%-?%d+),(%-?%d+),(%d+),(%d+)$")
    state.layout = { x = tonumber(x), y = tonumber(y), w = tonumber(w) or WIDTH, h = tonumber(h) or HEIGHT }
  end
  local layout = state.layout
  if state.position then
    layout.x, layout.y = state.position[1], state.position[2]
    state.position, state.saveLayout = nil, true
  end

  local maxW, maxH = math.max(1, io.width - 4 * s), math.max(1, io.height - 4 * s)
  local minW, minH = math.min(MIN_WIDTH * s, maxW), math.min(MIN_HEIGHT * s, maxH)
  local w = math.floor(math.max(minW, math.min(layout.w * s, maxW)))
  local h = math.floor(math.max(minH, math.min(layout.h * s, maxH)))
  local x = math.floor(math.max(0, math.min(layout.x or (io.width - w) / 2, io.width - w)))
  local y = math.floor(math.max(0, math.min(layout.y or (io.height - h) / 2, io.height - h)))

  local drawn = state.drawn
  if not drawn or drawn.w ~= w or drawn.h ~= h then ui.SetNextWindowSize(w, h, ui.Cond.Always) end
  if not drawn or drawn.x ~= x or drawn.y ~= y then ui.SetNextWindowPos(x, y, ui.Cond.Always) end
  if ui.SetNextWindowSizeConstraints then ui.SetNextWindowSizeConstraints(minW, minH, maxW, maxH) end
  return x, y, w, h
end

local function rememberBounds(state, x, y, w, h, s, expectedX, expectedY, expectedW, expectedH)
  state.drawn = { x = x, y = y, w = w, h = h }
  local layout = state.layout
  -- A viewport clamp changes the drawn bounds, while an actual move or resize updates the saved preference.
  if math.abs(x - expectedX) >= 1 then layout.x, state.saveLayout = x, true end
  if math.abs(y - expectedY) >= 1 then layout.y, state.saveLayout = y, true end
  if math.abs(w - expectedW) >= 1 then layout.w, state.saveLayout = w / s, true end
  if math.abs(h - expectedH) >= 1 then layout.h, state.saveLayout = h / s, true end
  if state.saveLayout then
    ui.SetSetting(LAYOUT_KEY, string.format("%d,%d,%d,%d", math.floor(layout.x or x), math.floor(layout.y or y),
      math.floor(layout.w + 0.5), math.floor(layout.h + 0.5)))
    state.saveLayout = false
  end
end

-- The presenter takes its input explicitly so the native UI harness can draw a recorded view.
function Finder.draw(view, state)
  if state.open == false then return false end
  local io = ui.GetIO()
  local s = io.uiScale or 1
  local expectedX, expectedY, expectedW, expectedH = windowBounds(state, io, s)
  if state.raise then
    if ui.SetNextWindowFocus then ui.SetNextWindowFocus() end
    state.raise = false
  end

  Style.Push()
  ui.PushStyleVar(ui.StyleVar.WindowPadding, 0, 0)
  ui.PushStyleVar(ui.StyleVar.FramePadding, 7 * s, 6 * s)
  ui.PushFont(FONT_BODY)
  local flags = ui.WindowFlags.NoSavedSettings | ui.WindowFlags.NoTitleBar | ui.WindowFlags.NoCollapse
    | ui.WindowFlags.NoScrollbar | ui.WindowFlags.NoScrollWithMouse
  local visible = ui.Begin(TITLE, nil, flags)
  if visible then
    local x, wy = ui.GetWindowPos()
    local w, h = ui.GetWindowSize()
    rememberBounds(state, x, wy, w, h, s, expectedX, expectedY, expectedW, expectedH)
    local sidebar = w >= 617 * s and not (view and view.localOnly)
    local sideW = sidebar and 154 * s or 0
    local y = wy + header(view, state, x, wy, w, s, io.width, io.height)
    y = y + toolbar(view, state, x, y, w, s, sidebar)
    local result = resultRows(view, state)
    if state.character and not result.sessions[state.character] then
      state.character = nil
      result = resultRows(view, state)
    end
    local footerH = 32 * s
    local bodyH = math.max(1, wy + h - footerH - y)
    if sidebar then
      roster(view, result, state, x, y, sideW, bodyH, s)
      result = resultRows(view, state)
    end
    results(view, result, state, x + sideW, y, w - sideW, bodyH, s)

    local fy = wy + h - footerH
    panel(x, fy, w, footerH, C.popup, 1, 5 * s)
    rule(x, fy, x + w, fy)
    Icons.Draw("Help", x + 17 * s, fy + 16 * s, 12 * s, C.accent)
    local footer = w < 545 * s and "Last-seen quantities may have changed."
      or "Last-seen quantities may have changed. Bank snapshots refresh when the client receives bank data."
    if view and view.localOnly then
      footer = w < 545 * s and "Current character only."
        or "Current character only. Last-seen bank quantities may have changed."
    end
    fit(x + 29 * s, fy + 9 * s, footer, w - 58 * s, C.muted, FONT_CAPTION)
  end
  ui.End()
  ui.PopFont()
  ui.PopStyleVar(2)
  Style.Pop()
  return state.open ~= false
end

function Finder.open(query)
  if type(query) == "string" then
    window.query, window.area, window.character = query:sub(1, 120), "all", nil
  end
  window.open, window.focus, window.raise = true, true, true
  window.pollAt = nil
end

function Finder.frame()
  if not API.session.InGame() then
    if window.open or window.view then window = { open = false, query = "", area = "all" } end
    return
  end
  if not window.open then return end
  local now = ui.GetTime()
  local query = searchTerm(window.query)
  if window.pollAt == nil or now < window.pollAt or now - window.pollAt >= 0.25 or window.pollQuery ~= query then
    window.view = inventoryView(query)
    window.pollAt, window.pollQuery = now, query
  end
  Finder.draw(window.view, window)
  if not window.open then window.view, window.result = nil, nil end
end

HailstoneStowAltFinder = Finder
return Finder
