local V = dofile("lib/stow_view.lua")
local W = dofile("lib/widgets.lua")
local TC = dofile("lib/trade_common.lua")
local API = hs.UI

local function register(name, screen, prefix)
  local sharedCoin = prefix .. "SharedMoney0"
  local coin = { prefix .. "Money0", prefix .. "Money1", prefix .. "Money2", prefix .. "Money3" }
  local function body(scale)
    local banker = API.windows.Text(screen, prefix .. "BankerName")
    if banker and banker ~= "" then ui.TextDisabled(banker) end
    local shroud = API.windows.ChildShown(screen, "AltStorageButton") == true
    V.storage("bank", scale, (shroud and 122 or 94) * scale)
    ui.Separator()
    TC.MoneyButtons(screen, coin, scale, "Pick up banked coin or deposit the coin on your cursor")
    TC.MoneyButton(screen, sharedCoin, 1, scale, 104 * scale, "Pick up or deposit shared platinum")
    ui.SameLine()
    ui.TextDisabled("Shared platinum")
    W.Button(screen, "AutoButton", "Auto-Bank", { primary = true })
    ui.SameLine()
    W.Button(screen, "Hailstone_AutoInventory", "Auto-Inventory")
    ui.SameLine()
    W.Button(screen, "DoneButton", "Done")
    if shroud then W.Button(screen, "AltStorageButton", "Shroud Bank") end
  end
  ui.window(name, function()
    if not API.session.InGame() then return end
    if not V.active("replaceBank") then return ui.base_window() end
    V.window(screen, "Stow Bank", "bank", 510, 595, body, function()
      API.windows.ClickChild(screen, "DoneButton", "left")
    end)
  end)
end

register("Bank", "BankWnd", "BW_")
register("Big Bank", "BigBankWnd", "BIGB_")
