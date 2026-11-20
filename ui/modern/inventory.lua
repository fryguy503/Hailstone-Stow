local V = dofile("lib/stow_view.lua")
local W = dofile("lib/widgets.lua")
local TC = dofile("lib/trade_common.lua")
local API = hs.UI
local S = V.model
local SCREEN = "InventoryWindow"
local COIN = { "IW_Money0", "IW_Money1", "IW_Money2", "IW_Money3" }
local character = false

local function close()
  character = false
  API.windows.ClickChild(SCREEN, "IW_DoneButton", "left")
end

local function inventory(scale)
  V.storage("inventory", scale, 84 * scale)
  ui.Separator()
  if ui.Button("Character") then character = true end
  if ui.IsItemHovered() then ui.SetTooltip("Equipment, stats, bandolier and alternate currency") end
  ui.SameLine()
  if ui.Button("Advanced Inventory") then API.windows.Show("InventoryManagerWnd", true) end
  ui.SameLine()
  W.Button(SCREEN, "Hailstone_AutoInventory", "Auto-Inventory")
  local cursor = API.inventory.Item(API.inventory.CursorSlot)
  if cursor and ui.GetContentRegionAvail() >= 70 * scale then
    ui.SameLine()
    W.Button(SCREEN, "IW_Destroy", "Destroy", { danger = true })
  end
  local parcels = API.inventory.Parcels() ~= nil and API.windows.TabPage("MerchantWnd", "MW_MerchantSubwindows") == 2
  TC.MoneyButtons(SCREEN, COIN, scale, parcels and "Click to send money by parcel (Shift: all)"
    or "Pick up coin (Shift: all)")
  if cursor then ui.TextDisabled("Holding " .. cursor.name) end
end

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
  V.window(SCREEN, "Stow", "inventory", 510, 550, inventory, close)
end)
