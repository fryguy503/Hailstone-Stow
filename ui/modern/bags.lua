local V = dofile("lib/stow_view.lua")
local slots = dofile("lib/items.lua")
local API = hs.UI
local S = V.model
local INVENTORY = "InventoryWindow"
local combinedOptions = {
  coinWindow = INVENTORY,
  coins = { "IW_Money0", "IW_Money1", "IW_Money2", "IW_Money3" },
  coinHint = function()
    local parcels = API.inventory.Parcels() ~= nil and API.windows.TabPage("MerchantWnd", "MW_MerchantSubwindows") == 2
    return parcels and "Click to send money by parcel (Shift: all)" or "Pick up coin (Shift: all)"
  end,
  extraActions = {
    { label = "Auto-Inventory",
      available = function() return API.windows.ChildState(INVENTORY, "Hailstone_AutoInventory") == true end,
      run = function()
        if API.windows.ChildState(INVENTORY, "Hailstone_AutoInventory") == true then
          API.windows.ClickChild(INVENTORY, "Hailstone_AutoInventory", "left")
        end
      end },
  },
}

local bagWindows = {}
for n = 1, 36 do bagWindows[n] = "Bag" .. n end
local previouslyOpen, openedTogether = {}, {}

local function identify(window)
  if not API.windows.Shown(window) then return nil end
  local name, count, combine, scope, slot = API.inventory.BagInfo(window)
  if not name or not count or count < 1 then return nil end
  return { window = window, name = name, count = count, combine = combine, scope = scope, slot = slot }
end

local function stillOpen(bag)
  if not API.windows.Shown(bag.window) then return false end
  local name, _, _, scope, slot = API.inventory.BagInfo(bag.window)
  return name == bag.name and scope == bag.scope and slot == bag.slot
end

local function closeBag(bag)
  if stillOpen(bag) then API.windows.ClickChild(bag.window, "StandardDoneButton", "left") end
end

local function closeInventoryBags(opened)
  local owner = API.plugins.Get("stow")
  if owner and owner.close_inventory_bags and owner.close_inventory_bags() == true then return end
  for n = #opened, 1, -1 do
    local bag = opened[n]
    if bag.scope == "inventory" then closeBag(bag) end
  end
end

local function drawBag(bag)
  if not stillOpen(bag) then return end
  local tile = S.get("size")
  local sortable = bag.scope == "inventory" or bag.scope == "bank"
  local width = math.max(sortable and 175 or 140, math.min(5, bag.count) * (tile + 5) + 19)
  local defaultColumns = math.max(1, (width - 19) // (tile + 5))
  local height = 46 + math.ceil(bag.count / defaultColumns) * (tile + 5) + (bag.combine and 34 or 0) + (sortable and 34 or 0)
  local kind = V.bagKind(API.inventory.BagSlotItem(bag.window, -1))
  local title = bag.name .. (kind and (" · " .. kind.label) or "")
  V.window(bag.window, title, bag.window, width, height, function(scale)
    if bag.combine then
      if ui.Button("Combine") and stillOpen(bag) then
        API.windows.ClickChild(bag.window, "Container_Combine", "left")
      end
      ui.SameLine()
      if ui.Button("Done") then closeBag(bag) end
      ui.Separator()
    end
    if sortable then
      V.actions(bag.scope, bag.window)
      ui.Separator()
    end
    local size, step = S.get("size") * scale, (S.get("size") + 5) * scale
    local columns = math.max(1, math.floor((ui.GetContentRegionAvail() + 5 * scale) / step))
    local x, y = ui.GetCursorScreenPos()
    local cx, cy = ui.GetCursorPos()
    for sub = 0, bag.count - 1 do
      local item = API.inventory.BagSlotItem(bag.window, sub)
      local opts = { held = true, compare = function() return API.compare.BagSlotItem(bag.window, sub) end }
      slots.Slot("##bag-slot." .. sub, x + (sub % columns) * step, y + (sub // columns) * step,
        size, scale, item, nil, bag.name .. ", slot " .. (sub + 1), function(button, outside)
          if not stillOpen(bag) then return false end
          return API.inventory.BagSlotClick(bag.window, sub, button, outside)
        end, opts)
    end
    ui.SetCursorPos(cx, cy)
    ui.Dummy(size, math.ceil(bag.count / columns) * step)
  end, function() closeBag(bag) end)
end

ui.window("Bags", function()
  local inGame = API.session.InGame()
  if not inGame or not V.active("replaceBags") then
    previouslyOpen, openedTogether = {}, {}
    if inGame then return ui.base_window() end
    return
  end
  local opened, carried, newBags, current = {}, {}, {}, {}
  local ordinary = 0
  for _, name in ipairs(bagWindows) do
    local bag = identify(name)
    if bag then
      opened[#opened + 1] = bag
      if bag.scope == "inventory" then
        carried[#carried + 1] = bag
        current[bag.slot] = bag.name
        if not bag.combine then ordinary = ordinary + 1 end
        if previouslyOpen[bag.slot] ~= bag.name then newBags[#newBags + 1] = bag end
      end
    end
  end
  for slot, name in pairs(openedTogether) do
    if current[slot] ~= name then openedTogether[slot] = nil end
  end
  -- Open All creates its windows together. The default chord also identifies the burst when only one bag opens.
  -- Keep the marks by physical slot: native BagN identifiers shift when a window closes.
  if #newBags > 1 or (#newBags == 1 and ui.GetIO().shift and ui.IsKeyPressed(ui.Key.B)) then
    for _, bag in ipairs(newBags) do openedTogether[bag.slot] = bag.name end
  end
  previouslyOpen = current

  local groupOrdinary = not API.windows.Shown(INVENTORY) and ordinary > 1
  local grouped, first = {}, nil
  for _, bag in ipairs(carried) do
    if openedTogether[bag.slot] ~= nil or (groupOrdinary and not bag.combine) then
      grouped[bag.window] = true
      first = first or bag
    end
  end
  if first then
    V.compact(first.window, "Stow Bags", "allBags", "inventory", combinedOptions,
      function() closeInventoryBags(opened) end)
  end
  for _, bag in ipairs(opened) do
    if not grouped[bag.window] then drawBag(bag) end
  end
  local world = identify("WorldContainer")
  if world then drawBag(world) end
end)
