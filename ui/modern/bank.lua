local V = dofile("lib/stow_view.lua")
local API = hs.UI

local function register(name, screen, prefix)
  local function nativeAction(child)
    return function()
      if API.windows.ChildShown(screen, child) ~= false and API.windows.ChildState(screen, child) ~= false then
        API.windows.ClickChild(screen, child, "left")
      end
    end
  end
  local options = {
    coins = { prefix .. "Money0", prefix .. "Money1", prefix .. "Money2", prefix .. "Money3" },
    sharedCoin = prefix .. "SharedMoney0",
    coinHint = "Pick up banked coin or deposit the coin on your cursor",
    caption = function() return API.windows.Text(screen, prefix .. "BankerName") end,
    extraActions = {
      { label = "Auto-Bank", run = nativeAction("AutoButton") },
      { label = "Auto-Inventory", run = nativeAction("Hailstone_AutoInventory"),
        available = function() return API.windows.ChildState(screen, "Hailstone_AutoInventory") ~= false end },
      { label = "Shroud Bank", run = nativeAction("AltStorageButton"),
        available = function() return API.windows.ChildShown(screen, "AltStorageButton") == true end },
    },
  }
  local function close()
    API.windows.ClickChild(screen, "DoneButton", "left")
  end
  ui.window(name, function()
    if not API.session.InGame() then return end
    if not V.active("replaceBank") then return ui.base_window() end
    V.compact(screen, "Stow Bank", "bank", "bank", options, close)
  end)
end

register("Bank", "BankWnd", "BW_")
register("Big Bank", "BigBankWnd", "BIGB_")
