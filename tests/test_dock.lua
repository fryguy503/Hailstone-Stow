-- Run from the add-on checkout with Lua 5.4.
local load = dofile
local positions, labels, clicks = {}, {}, {}
local x, y, last, hit, hover, right, held, tooltip, jobScope, jobMode
local finderQuery
local stackTargets, stackRemainder, stackPin, merges
local timeToExpand = true
local consumedRight = 0

local color = setmetatable({}, {__index = function() return {1, 1, 1, 1} end})
local model = {
  get = function(key) return key == "compressEmpty" and timeToExpand or false end,
  canPlace = function(cell) return cell.fits end,
  click = function(cell) clicks[#clicks + 1] = cell.place end,
  stackTargets = function(_, pin) stackPin = pin; return stackTargets end,
  mergeHeld = function(stacks)
    assert(stacks == stackTargets)
    merges = merges + 1
    return stackRemainder
  end,
  run = function(scope, mode) jobScope, jobMode = scope, mode end,
}
local function nop() end
local replacements = {
  ["lib/stow_model.lua"] = model,
  ["lib/stow_options.lua"] = {},
  ["lib/stow_alt_finder.lua"] = {open = function(query) finderQuery = query end},
  ["lib/menuicons.lua"] = {Draw = nop},
  ["lib/trade_common.lua"] = {COIN = {{"pp", "Platinum", color.platinum}}},
  ["lib/theme.lua"] = {
    color = color, font = {small = "small"},
    Text = function(_, _, text) labels[last] = text end,
    TextSize = function(s) return #s * 6, 12 end,
    Thousands = tostring,
    Fit = function(s) return s end,
    TakeRightClick = function() consumedRight = consumedRight + 1 end,
  },
}
dofile = function(path) return replacements[path] or load(path) end
hs = {UI = {
  character = {Money = function() return 1234 end},
  windows = {Text = function(_, id) return id == "shared" and "34" or "1234" end},
  inventory = {
    ItemJob = nop, Item = function() return held end, CursorSlot = 33, CanPlace = nop,
  },
}}
ui = {
  Mouse = {Left = 0, Right = 1},
  GetCursorScreenPos = function() return 0, 0 end,
  GetCursorPos = function() return 0, 0 end,
  SetCursorScreenPos = function(dx, dy) x, y = dx, dy end,
  SetCursorPos = nop,
  InvisibleButton = function(id, w, h)
    positions[id], last = {x = x, y = y, w = w, h = h}, id
    return id == hit
  end,
  SetTooltip = function(text) tooltip = text end,
  IsItemHovered = function() return last == hover end,
  IsMouseClicked = function(button) return button == 1 and right end,
  IsItemActive = function() return false end,
  DrawRect = nop, DrawRectFilled = nop, DrawCircleFilled = nop, DrawLine = nop,
  Dummy = nop, BeginPopup = function() return false end,
}

local dock = load("ui/modern/lib/stow_dock.lua")
local state = {title = "Stow Bank", expandedFree = {}}
local personal = {scope = "bank", free = 3, capacity = 16, cells = {
  {place = "b:0", fits = false}, {place = "b:1", fits = true}, {place = "b:2", fits = true},
}}
local shared = {scope = "shared", free = 2, capacity = 8, cells = {
  {place = "s:0"}, {place = "s:1", fits = true},
}}
local measured = dock.measure("BankWnd", "bank", {coins = {"platinum"}, sharedCoin = "shared"}, state, 1,
  {personal, shared})

local function draw(width)
  positions, labels = {}, {}
  dock.draw(measured, width)
  local rightEdge = positions["##stowDock.close"]
  assert(rightEdge.x + rightEdge.w == width - measured.padding, "close should be at the right edge")
  assert(rightEdge.y + rightEdge.h + measured.padding == dock.height(measured, width))
  assert(positions["##stowDock.move"].x == measured.padding, "label should be at the left edge")
  local ordered = {}
  for id, pos in pairs(positions) do
    assert(pos.x >= measured.padding and pos.x + pos.w <= width - measured.padding, id .. " is outside dock")
    ordered[#ordered + 1] = pos
  end
  table.sort(ordered, function(a, b) return a.y == b.y and a.x < b.x or a.y < b.y end)
  for i = 2, #ordered do
    local prev, next = ordered[i - 1], ordered[i]
    if prev.y == next.y then assert(prev.x + prev.w <= next.x, "dock items overlap") end
  end
end

draw(measured.width)
assert(positions["##stowDock.altFinder"], "Alt Finder is available without the native index")
assert(labels["##stowCoin.shared"] == "S 34")
assert(labels["##stowDock.empty.bank"] == "P 3")
assert(labels["##stowDock.empty.shared"] == "S 2")
local height = dock.height(measured, measured.width)
draw(measured.width + 180)
assert(positions["##stowDock.close"].y == measured.padding)
assert(dock.height(measured, measured.width + 180) == height, "full labels must keep the same one-row height")
assert(labels["##stowCoin.shared"] == "Shared 34")
assert(labels["##stowDock.empty.bank"] == "Personal 3")
assert(labels["##stowDock.empty.shared"] == "Shared 2")
for width = 54, measured.width - 1 do draw(width) end

hit, hover = "##stowDock.stack", "##stowDock.stack"
draw(measured.width)
assert(tooltip == "Restack matching items in the personal bank")
assert(jobScope == "bank" and jobMode == "stack")

local inventory = dock.measure("InventoryWnd", "inventory", {}, {title = "Stow Bags", expandedFree = {}}, 1, {})
dock.draw(inventory, inventory.width)
assert(tooltip == "Restack matching items")
assert(jobScope == "inventory" and jobMode == "stack")

-- Identical controls in the footer and optional cards operate on the scope supplied by the view.
local personalFooter, sharedFooter, sharedTile = "##stowDock.empty.bank", "##stowDock.empty.shared", "##stowSlot.empty.shared"
hit, hover, held = personalFooter, personalFooter, {name = "Held item"}
draw(measured.width)
assert(clicks[#clicks] == "b:1")
assert(tooltip:match("Personal bank") and tooltip:match("2 compatible slots"))
hit, hover = sharedFooter, sharedFooter
draw(measured.width)
assert(clicks[#clicks] == "s:1", "prefer a known eligible slot to an unchecked slot")
assert(tooltip:match("Shared bank") and tooltip:match("1 compatible") and tooltip:match("1 unchecked"))

hit, hover, right = nil, sharedTile, true
dock.drawTarget(measured, shared, 0, 0, 30, 30, true)
assert(state.expandedFree.shared and not state.expandedFree.bank and consumedRight == 1)
hit, hover, right, held = personalFooter, personalFooter, nil, nil
draw(measured.width)
assert(state.expandedFree.bank and state.expandedFree.shared)
hit, hover = sharedFooter, sharedFooter
draw(measured.width)
assert(not state.expandedFree.shared and state.expandedFree.bank)

timeToExpand = false
draw(measured.width)
assert(not state.expandedFree.shared)
assert(#clicks == 2)

local carried = {scope = "inventory", free = 0, capacity = 8, cells = {}, pin = "i:24"}
hit, hover, held = "##stowDock.empty.inventory", "##stowDock.empty.inventory", {name = "Held stack"}
stackTargets, merges = {{place = "i:24:1"}}, 0
dock.drawTarget(inventory, carried, 0, 0, 30, 30, false)
assert(merges == 1 and #clicks == 2 and stackPin == "i:24")
assert(tooltip:match("fill matching stacks"))

hit, hover = "##stowSlot.empty.inventory", "##stowSlot.empty.inventory"
carried.free, carried.cells = 1, {{place = "i:24:2", fits = true}}
dock.drawTarget(inventory, carried, 0, 0, 30, 30, true)
assert(merges == 2 and #clicks == 2, "a completed merge leaves the free slot empty")
stackRemainder = held
dock.drawTarget(inventory, carried, 0, 0, 30, 30, true)
assert(merges == 3 and clicks[3] == "i:24:2", "overflow uses the eligible empty slot")
held = nil

state.query = "Spider Silk"
hit, hover = "##stowDock.altFinder", "##stowDock.altFinder"
measured = dock.measure("BankWnd", "bank", {}, state, 1, {personal, shared})
draw(measured.width)
assert(finderQuery == "Spider Silk" and tooltip:match("Alt Finder"))

local carriedFinder = dock.measure("InventoryWnd", "inventory", {}, state, 1, {})
dock.draw(carriedFinder, carriedFinder.width)
assert(positions["##stowDock.altFinder"], "Alt Finder is available from carried bags too")
print("Stow dock tests passed")
