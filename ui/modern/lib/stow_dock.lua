local S = dofile("lib/stow_model.lua")
local O = dofile("lib/stow_options.lua")
local T = dofile("lib/theme.lua")
local TC = dofile("lib/trade_common.lua")
local icons = dofile("lib/menuicons.lua")
local API = hs.UI
local C = T.color
local D = {}

local views = {
  {id = "grouped", name = "Category cards"}, {id = "combined", name = "Combined"},
  {id = "bags", name = "By physical bag"},
}

local function value(setting)
  if type(setting) == "function" then return setting() end
  return setting
end

function D.measure(screen, scope, opts, state, scale, free, capacity)
  local lineH = select(2, T.TextSize("Ag", T.font.small))
  local h = math.max(18 * scale, lineH + 4 * scale)
  local padding, gap = 3 * scale, 2 * scale
  local dock = {screen = screen, scope = scope, opts = opts, state = state, scale = scale,
    free = free or 0, capacity = capacity or 0, row = h, padding = padding, gap = gap,
    height = h + padding * 2, width = padding * 2 - gap, tokens = {}}
  local function add(record)
    dock.tokens[#dock.tokens + 1] = record
    dock.width = dock.width + record.width + gap
  end
  local function measure(text)
    return T.TextSize(text, T.font.small)
  end
  local title = state.title or "Stow"
  add({id = "move", text = title, width = measure(title) + 15 * scale})
  local coinWindow = opts.coinWindow or screen
  local purse = scope == "inventory" and {API.character.Money()} or nil
  local function coin(id, denomination, shared)
    local count = tonumber((API.windows.Text(coinWindow, id))) or (purse and purse[denomination]) or 0
    local text = (shared and "S " or "") .. T.Thousands(count)
    add({id = id, window = coinWindow, count = count, width = measure(text) + 13 * scale,
      text = text, denomination = denomination, shared = shared})
  end
  for i, id in ipairs(opts.coins or {}) do coin(id, i) end
  if opts.sharedCoin then coin(opts.sharedCoin, 1, true) end
  local done, total, job = API.inventory.ItemJob()
  dock.job = done and total and {done = done, total = total, kind = job} or nil
  for _, id in ipairs({"search", "stack", "bags", "options"}) do
    add({id = id, width = h})
  end
  local freeText = T.Thousands(dock.free)
  add({id = "empty", text = freeText, width = measure(freeText) + 14 * scale})
  add({id = "close", width = h})
  return dock
end

-- Pack a second row only when the available width cannot fit the dock beside the cards.
local function place(dock, width, visit)
  local x, y = dock.padding, dock.padding
  local limit = math.max(1, width - dock.padding * 2)
  for _, token in ipairs(dock.tokens) do
    local w = math.min(limit, token.width)
    if x > dock.padding and x + w > width - dock.padding + 0.5 then
      x, y = dock.padding, y + dock.row + dock.gap
    end
    if visit then visit(token, x, y, w) end
    x = x + w + dock.gap
  end
  return y + dock.row + dock.padding
end

function D.height(dock, width)
  return place(dock, width)
end

local function label(x, y, h, text, color)
  local _, th = T.TextSize(text, T.font.small)
  T.Text(x, y + (h - th) / 2, text, color, T.font.small)
end

local function drawCoin(dock, token, x, y, w)
  local s, h = dock.scale, dock.row
  local click = ui.InvisibleButton("##stowCoin." .. token.id, w, h)
  local hover = ui.IsItemHovered()
  local coin = TC.COIN[token.denomination]
  local accent = coin[3]
  if hover then ui.DrawRectFilled(x, y, x + w, y + h, accent[1], accent[2], accent[3], 0.18, 3 * s) end
  ui.DrawCircleFilled(x + 5 * s, y + h / 2, 3 * s, accent[1], accent[2], accent[3], 1)
  label(x + 10 * s, y, h, T.Fit(token.text, math.max(1, w - 11 * s), T.font.small),
    token.count > 0 and C.text or C.muted)
  if hover then
    local hint = value(dock.opts.coinHint) or "Click to pick up or deposit coin (Shift: all)"
    local name = token.shared and "Shared platinum" or coin[2]
    ui.SetTooltip(name .. "  " .. T.Thousands(token.count) .. "\n" .. hint)
  end
  if click and API.windows.ChildState(token.window, token.id) ~= false then
    API.windows.ClickChild(token.window, token.id, "left")
  end
end

local function stroke(x1, y1, x2, y2, color, s)
  ui.DrawLine(x1, y1, x2, y2, color[1], color[2], color[3], 1, math.max(1, 1.1 * s))
end

local function glyph(id, x, y, c, s)
  local d = 4 * s
  if id == "close" then
    stroke(x - d, y - d, x + d, y + d, c, s)
    stroke(x - d, y + d, x + d, y - d, c, s)
  elseif id == "stop" then
    ui.DrawRectFilled(x - d, y - d, x + d, y + d, c[1], c[2], c[3], 1, s)
  elseif id == "stack" then
    for offset = -2, 2, 4 do
      ui.DrawRect(x - d, y - 3 * s + offset * s, x + d, y + 3 * s + offset * s,
        c[1], c[2], c[3], 1, s, math.max(1, s))
    end
  else
    icons.Draw(id == "search" and "Find" or id == "bags" and "Inventory" or "Options", x, y, 11 * s, c)
  end
end

local function availableSlots(state, preview)
  local first, fallback, compatible, unknown
  compatible, unknown = 0, 0
  for _, cell in ipairs(state.dropCells or state.freeCells or {}) do
    local fit = S.canPlace(cell)
    if fit == true then
      first, compatible = first or cell, compatible + 1
      if not preview then break end
    elseif fit == nil then
      fallback, unknown = fallback or cell, unknown + 1
    end
  end
  return first or fallback, compatible, unknown
end

local function emptyButton(dock, token, x, y, w, hit, hover)
  local state, s, h = dock.state, dock.scale, dock.row
  local held = (hover or hit) and API.inventory.Item(API.inventory.CursorSlot)
  local expands = S.get("compressEmpty") and #(state.freeCells or {}) > 0
  local target, compatible, unknown
  if held then target, compatible, unknown = availableSlots(state, hover) end
  local color = held and (target and C.good or C.danger) or C.accent
  if hover or (expands and state.showFree) then
    ui.DrawRectFilled(x, y, x + w, y + h, color[1], color[2], color[3], 0.16, 3 * s)
  end
  local mid = y + h / 2
  ui.DrawRect(x + 3 * s, mid - 3 * s, x + 9 * s, mid + 3 * s, color[1], color[2], color[3], 0.9, s, 1)
  label(x + 12 * s, y, h, T.Fit(token.text, math.max(1, w - 13 * s), T.font.small), color)
  if hover then
    local message = string.format("%s / %s slots free", token.text, T.Thousands(dock.capacity))
    if held then
      if API.inventory.CanPlace and (compatible > 0 or unknown == 0) then
        message = message .. "\n" .. compatible .. " compatible slots" .. (state.dropLabel or "")
      end
      if target then message = message .. "\nClick to place the held item" end
    end
    if expands then message = message .. "\nRight-click to show or hide individual slots" end
    ui.SetTooltip(message)
    if expands and ui.IsMouseClicked(ui.Mouse.Right) then
      T.TakeRightClick()
      state.showFree = not state.showFree
      return
    end
  end
  if hit then
    if held then
      if target then S.click(target, "left") end
    elseif expands then
      state.showFree = not state.showFree
    end
  end
end

local function drawControl(dock, token, x, y, w)
  local id, state, h, s = token.id, dock.state, dock.row, dock.scale
  local click = ui.InvisibleButton("##stowDock." .. id, w, h)
  local hover = ui.IsItemHovered()
  if id == "empty" then return emptyButton(dock, token, x, y, w, click, hover) end
  local active = (id == "search" and state.searchOpen) or (id == "bags" and state.showBags) or (id == "stack" and dock.job)
  local color = (active or hover) and C.accent or C.muted
  if active or hover then ui.DrawRectFilled(x, y, x + w, y + h, color[1], color[2], color[3], 0.15, 3 * s) end
  local tip
  if id == "move" then
    ui.DrawRectFilled(x + 3 * s, y + h / 2 - 2 * s, x + 7 * s, y + h / 2 + 2 * s,
      C.accent[1], C.accent[2], C.accent[3], 1, s)
    label(x + 11 * s, y, h, T.Fit(token.text, math.max(1, w - 13 * s), T.font.small), C.text)
    if hover then
      local caption = value(dock.opts.caption)
      tip = S.get("windowLocked") and "Window position locked" or "Drag to move"
      if caption and caption ~= "" then tip = caption .. "\n" .. tip end
    end
    state.dragging = not S.get("windowLocked") and ui.IsItemActive() and ui.IsMouseDragging(ui.Mouse.Left, 0)
  else
    glyph(id == "stack" and dock.job and "stop" or id, x + w / 2, y + h / 2, color, s)
    if id == "search" then
      tip = "Find items"
      if click then
        state.searchOpen = not state.searchOpen
        state.focusSearch = state.searchOpen
        if not state.searchOpen then state.query = "" end
      end
    elseif id == "stack" then
      tip = dock.job and (string.format("Stop %s (%d / %d)", dock.job.kind or "item job", dock.job.done, dock.job.total))
        or "Restack matching items"
      if click then
        if dock.job then API.inventory.StopItemJob() else S.run(dock.scope, "stack") end
      end
    elseif id == "bags" then
      tip = state.showBags and "Hide physical bags" or "Show physical bags"
      if click then state.showBags = not state.showBags end
    elseif id == "options" then
      tip = "View and item options"
      if click then ui.OpenPopup("##stowDock.optionsMenu") end
    elseif id == "close" then
      tip = "Close " .. (state.title or "Stow")
      if click then state.closeRequested = true end
    end
  end
  if hover and tip then ui.SetTooltip(tip) end
end

local function interactionMenu(dock)
  if ui.BeginPopup("##stowDock.optionsMenu") then
    local modeKey = dock.scope .. "Mode"
    if ui.BeginMenu("Layout") then
      for _, mode in ipairs(views) do
        if ui.MenuItem(mode.name, S.get(modeKey) == mode.id) then
          if dock.scope == "bank" and mode.id == "grouped" then S.set("bankFiltering", true) end
          S.set(modeKey, mode.id)
        end
      end
      ui.EndMenu()
    end
    if ui.MenuItem("Sort items", false, not dock.job) then S.run(dock.scope, "sort") end
    if ui.MenuItem("Tidy into filtered bags", false, not dock.job) then S.run(dock.scope, "tidy") end
    if dock.scope == "inventory" and API.windows.Shown("MerchantWnd") and ui.MenuItem("Sell marked items", false, not dock.job) then
      S.sell()
    end
    ui.Separator()
    for _, action in ipairs(dock.opts.extraActions or {}) do
      if (not action.available or action.available()) and ui.MenuItem(action.label) then action.run() end
    end
    if ui.MenuItem("Stow Settings") then dock.state.settingsRequested = true end
    ui.EndPopup()
  end
  if dock.state.settingsRequested then
    dock.state.settingsRequested = false
    ui.OpenPopup("##stowDock.settings")
  end
  if ui.BeginPopup("##stowDock.settings") then
    O.draw(S)
    ui.EndPopup()
  end
end

function D.draw(dock, width)
  local x, y = ui.GetCursorScreenPos()
  local cx, cy = ui.GetCursorPos()
  local s, h = dock.scale, D.height(dock, width)
  ui.DrawRectFilled(x, y, x + width, y + h, C.panel[1], C.panel[2], C.panel[3], 0.97, 4 * s)
  ui.DrawRect(x, y, x + width, y + h, C.accent[1], C.accent[2], C.accent[3], 0.28, 4 * s, 1)
  dock.state.dragging = false
  place(dock, width, function(token, dx, dy, w)
    ui.SetCursorScreenPos(x + dx, y + dy)
    if token.denomination then drawCoin(dock, token, x + dx, y + dy, w)
    else drawControl(dock, token, x + dx, y + dy, w) end
  end)
  ui.SetCursorPos(cx, cy)
  ui.Dummy(width, h)
  interactionMenu(dock)
end

function D.search(state, scale, width)
  if state.focusSearch then
    ui.SetKeyboardFocusHere()
    state.focusSearch = false
  end
  ui.SetNextItemWidth(math.max(1, width - 24 * scale))
  state.query = ui.InputTextWithHint("##stowSearch", "Find items", state.query or "", 256)
  if ui.IsItemHovered() then
    ui.SetTooltip('Find by name, type:armor, bag:backpack or is:new.\nUse quotes for phrases and - to exclude a term.')
  end
  ui.SameLine(0, 3 * scale)
  if ui.Button("×##stowClear", 20 * scale) then state.query = "" end
  if ui.IsItemHovered() then ui.SetTooltip("Clear search") end
end

return D
