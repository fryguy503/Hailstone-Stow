local V = dofile("lib/stow_view.lua")
local API = hs.UI
local SCREEN = "InventoryWindow"
local character = false

local function close()
  character = false
  API.windows.ClickChild(SCREEN, "IW_DoneButton", "left")
end

local function coinHint()
  local parcels = API.inventory.Parcels() ~= nil and API.windows.TabPage("MerchantWnd", "MW_MerchantSubwindows") == 2
  return parcels and "Click to send money by parcel (Shift: all)" or "Pick up coin (Shift: all)"
end

local function nativeAction(child)
  if API.windows.ChildShown(SCREEN, child) ~= false and API.windows.ChildState(SCREEN, child) ~= false then
    API.windows.ClickChild(SCREEN, child, "left")
  end
end

local function holdingItem()
  return API.inventory.Item(API.inventory.CursorSlot) ~= nil
end

local options = {
  coins = { "IW_Money0", "IW_Money1", "IW_Money2", "IW_Money3" },
  coinHint = coinHint,
  extraActions = {
    { label = "Character", run = function() character = true end },
    { label = "Advanced Inventory", run = function()
      API.windows.Show("InventoryManagerWnd", true)
    end },
    { label = "Auto-Inventory", available = holdingItem, run = function()
      nativeAction("Hailstone_AutoInventory")
    end },
    { label = "Destroy held item", available = holdingItem, run = function()
      if holdingItem() then nativeAction("IW_Destroy") end
    end },
  },
}

ui.window("Inventory", function()
  if not API.session.InGame() then character = false return end
  if not V.active("replaceInventory") then
    character = false
    ui.base_window()
    return
  end
  if character then
    if not API.windows.Shown(SCREEN) then character = false return end
    if not ui.base_window() then character = false return end
    ui.SetNextWindowPos(24, 80, ui.Cond.FirstUseEver)
    local visible, open = ui.Begin("Stow###stow.characterReturn", true, ui.WindowFlags.AlwaysAutoResize)
    if visible and ui.Button("Return to Stow") then character = false end
    ui.End()
    if not open then character = false end
    return
  end
  V.compact(SCREEN, "Stow", "inventory", "inventory", options, close)
end)
