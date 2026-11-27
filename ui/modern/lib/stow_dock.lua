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

local targetNames = {
  inventory = {label = "Inventory"},
  bank = {label = "Personal bank", long = "Personal ", short = "P "},
  shared = {label = "Shared bank", long = "Shared ", short = "S "},
}

local function value(setting)
  if type(setting) == "function" then return setting() end
  return setting
end

function D.measure(screen, scope, opts, state, scale, targets)
  local lineH = select(2, T.TextSize("Ag", T.font.small))
  local h = math.max(18 * scale, lineH + 4 * scale)
  local padding, gap = 3 * scale, 2 * scale
  local dock = {screen = screen, scope = scope, opts = opts, state = state, scale = scale,
    row = h, padding = padding, gap = gap, width = padding * 2 - gap, tokens = {}}
  local function add(record, right)
    record.right = right
    dock.tokens[#dock.tokens + 1] = record
    dock.width = dock.width + record.width + gap
  end
  local function measure(text)
    return T.TextSize(text, T.font.small)
  end
  local function expandedText(record, text)
    record.expandedText = text
    record.expansion = measure(text) - measure(record.text)
    return record
  end
  local title = state.title or "Stow"
  add({id = "move", text = title, width = measure(title) + 15 * scale})
  local coinWindow = opts.coinWindow or screen
  local purse = scope == "inventory" and {API.character.Money()} or nil
  local function coin(id, denomination, shared)
    local count = tonumber((API.windows.Text(coinWindow, id))) or (purse and purse[denomination]) or 0
    local amount = T.Thousands(count)
    local text = shared and "S " .. amount or amount
    local record = {id = id, window = coinWindow, count = count, width = measure(text) + 13 * scale,
      text = text, denomination = denomination, shared = shared}
    if shared then expandedText(record, "Shared " .. amount) end
    add(record)
  end
  for i, id in ipairs(opts.coins or {}) do coin(id, i) end
  if opts.sharedCoin then coin(opts.sharedCoin, 1, true) end
  local done, total, job = API.inventory.ItemJob()
  dock.job = done and total and {done = done, total = total, kind = job} or nil
  add({id = "search", width = h}, true)
  add({id = "altFinder", width = h}, true)
  if scope == "inventory" then add({id = "organize", width = h}, true) end
  for _, id in ipairs({"stack", "bags", "options"}) do
    add({id = id, width = h}, true)
  end
  for _, target in ipairs(targets) do
    local name = targetNames[target.scope]
    local amount = T.Thousands(target.free)
    local text = (name.short or "") .. amount
    local record = {id = "empty", target = target, text = text, width = measure(text) + 14 * scale}
    if name.long then expandedText(record, name.long .. amount) end
    add(record, true)
  end
  add({id = "close", width = h}, true)
  return dock
end

-- Pack compact labels first, then expand labels within each row's unused space.
-- The title and coins start at the left. Each row of tools ends at the right.
local function place(dock, width, visit)
  local gap = dock.gap
  local pad = math.min(dock.padding, math.max(0, (width - 1) / 2))
  local limit = math.max(1, width - pad * 2)
  local y, first, used, right = dock.padding, 1, 0, 0
  local function row(last)
    if not visit then return end
    local expand = {}
    local spare = limit - used
    for i = first, last do
      local token = dock.tokens[i]
      local extra = token.expansion
      if extra and extra <= spare and token.width <= limit then
        expand[i] = extra
        spare = spare - extra
        if token.right then right = right + extra end
      end
    end
    local x, toolX = pad, pad + limit - right
    for i = first, last do
      local token = dock.tokens[i]
      local w = math.min(limit, token.width) + (expand[i] or 0)
      visit(token, token.right and toolX or x, y, w, expand[i] and token.expandedText or token.text)
      if token.right then toolX = toolX + w + gap else x = x + w + gap end
    end
  end
  for i, token in ipairs(dock.tokens) do
    local w = math.min(limit, token.width)
    if used > 0 and used + gap + w > limit then
      row(i - 1)
      first, used, right = i, 0, 0
      y = y + dock.row + gap
    end
    used = used > 0 and used + gap + w or w
    if token.right then right = right > 0 and right + gap + w or w end
  end
  row(#dock.tokens)
  return y + dock.row + dock.padding
end

function D.height(dock, width)
  return place(dock, width)
end

local function label(x, y, h, text, color)
  local _, th = T.TextSize(text, T.font.small)
  T.Text(x, y + (h - th) / 2, text, color, T.font.small)
end

local function drawCoin(dock, token, x, y, w, text)
  local s, h = dock.scale, dock.row
  local click = ui.InvisibleButton("##stowCoin." .. token.id, w, h)
  local hover = ui.IsItemHovered()
  local coin = TC.COIN[token.denomination]
  local accent = coin[3]
  if hover then ui.DrawRectFilled(x, y, x + w, y + h, accent[1], accent[2], accent[3], 0.18, 3 * s) end
  ui.DrawCircleFilled(x + 5 * s, y + h / 2, 3 * s, accent[1], accent[2], accent[3], 1)
  label(x + 10 * s, y, h, T.Fit(text, math.max(1, w - 11 * s), T.font.small),
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
  elseif id == "organize" then
    for n = 0, 2 do
      stroke(x - 5 * s, y + (3 * n - 3) * s, x - n * s, y + (3 * n - 3) * s, c, s)
    end
    local right = x + 3 * s
    stroke(right, y - d, right, y + d, c, s)
    stroke(right - 2 * s, y + 2 * s, right, y + d, c, s)
    stroke(right, y + d, right + 2 * s, y + 2 * s, c, s)
  elseif id == "altFinder" then
    icons.Draw("Advanced Inventory", x, y, 11 * s, c)
  else
    icons.Draw(id == "search" and "Find" or id == "bags" and "Inventory" or "Options", x, y, 11 * s, c)
  end
end

local function availableSlots(cells, preview)
  local first, fallback, compatible, unknown
  compatible, unknown = 0, 0
  for _, cell in ipairs(cells) do
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

function D.drawTarget(dock, target, x, y, w, h, asTile)
  local state, s = dock.state, dock.scale
  local scope, cells = target.scope, target.cells
  local prefix = asTile and "##stowSlot.empty." or "##stowDock.empty."
  ui.SetCursorScreenPos(x, y)
  local hit = ui.InvisibleButton(prefix .. scope, w, h)
  local hover = ui.IsItemHovered()
  local held = (hover or hit) and API.inventory.Item(API.inventory.CursorSlot)
  local expands = S.get("compressEmpty") and #cells > 0
  local destination, compatible, unknown
  if held then destination, compatible, unknown = availableSlots(cells, hover) end
  local stacks = held and scope == "inventory" and S.stackTargets(held, target.pin)
  local scopeColor = scope == "shared" and C.platinum or C.accent
  local color = held and ((stacks or destination) and C.good or C.danger) or scopeColor
  if asTile or hover or (expands and state.expandedFree[scope]) then
    local alpha = (hover or state.expandedFree[scope]) and 0.16 or 0.09
    ui.DrawRectFilled(x, y, x + w, y + h, color[1], color[2], color[3], alpha, 3 * s)
  end
  local amount = T.Thousands(target.free)
  local name = targetNames[scope]
  if asTile then
    ui.DrawRect(x, y, x + w, y + h, color[1], color[2], color[3], 0.55, 3 * s, 1)
    local text = T.Fit(amount, math.max(1, w - 4 * s), T.font.small)
    local _, th = T.TextSize(text, T.font.small)
    T.Text(x + w / 2, y + (h - th) / 2, text, color, T.font.small, "center")
  else
    local mid = y + h / 2
    ui.DrawRect(x + 3 * s, mid - 3 * s, x + 9 * s, mid + 3 * s, color[1], color[2], color[3], 0.9, s, 1)
    local text = (name.short or "") .. amount
    local avail = math.max(1, w - 14 * s)
    if name.long and T.TextSize(name.long .. amount, T.font.small) <= avail then text = name.long .. amount end
    label(x + 12 * s, y, h, T.Fit(text, avail, T.font.small), color)
  end
  if hover then
    local message = string.format("%s\n%s / %s slots free", name.label, amount, T.Thousands(target.capacity))
    if held then
      if API.inventory.CanPlace then
        if unknown > 0 then
          message = message .. string.format("\n%d compatible · %d unchecked", compatible, unknown)
        else
          message = message .. "\n" .. compatible .. " compatible slots"
        end
      end
      if stacks then
        message = message .. "\nClick to fill matching stacks"
      elseif destination then
        message = message .. "\nClick to place the held item"
      end
    end
    if expands then message = message .. "\nRight-click to show or hide individual slots" end
    ui.SetTooltip(message)
    if expands and ui.IsMouseClicked(ui.Mouse.Right) then
      T.TakeRightClick()
      state.expandedFree[scope] = not state.expandedFree[scope]
      return
    end
  end
  if hit then
    if held then
      if stacks then held = S.mergeHeld(stacks, held) end
      if held and destination and S.canPlace(destination) ~= false then S.click(destination, "left") end
    elseif expands then
      state.expandedFree[scope] = not state.expandedFree[scope]
    end
  end
end

local function drawControl(dock, token, x, y, w)
  local id, state, h, s = token.id, dock.state, dock.row, dock.scale
  local click = ui.InvisibleButton("##stowDock." .. id, w, h)
  local hover = ui.IsItemHovered()
  local active = (id == "search" and state.searchOpen) or (id == "bags" and state.showBags) or (id == "stack" and dock.job)
  local busy = id == "organize" and dock.job
  local color = busy and C.faint or ((active or hover) and C.accent or C.muted)
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
    elseif id == "altFinder" then
      tip = "Alt Finder · Search bags and personal banks"
      if click then dofile("lib/stow_alt_finder.lua").open(state.query ~= "" and state.query or nil) end
    elseif id == "organize" then
      tip = busy and "Finish the current item job to sort inventory and clear New Items"
        or "Sort inventory and clear New Items"
      if click then S.organize() end
    elseif id == "stack" then
      if dock.job then
        tip = string.format("Stop %s (%d / %d)", dock.job.kind or "item job", dock.job.done, dock.job.total)
      else
        tip = dock.scope == "bank" and "Restack matching items in the personal bank" or "Restack matching items"
      end
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
  place(dock, width, function(token, dx, dy, w, text)
    local tx, ty = x + dx, y + dy
    if token.target then
      D.drawTarget(dock, token.target, tx, ty, w, dock.row)
    else
      ui.SetCursorScreenPos(tx, ty)
      if token.denomination then drawCoin(dock, token, tx, ty, w, text)
      else drawControl(dock, token, tx, ty, w) end
    end
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
