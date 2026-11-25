local Stow = dofile("lib/stow_model.lua")
local Options = dofile("lib/stow_options.lua")
local Finder = dofile("lib/stow_alt_finder.lua")
local API = hs.UI
local settingsOpen, lastPoll = false, -math.huge

ui.window("Stow Maintenance", function()
  local update = API.inventory.UpdateAltFinder
  if update then update() end
  if not API.session.InGame() then
    settingsOpen, lastPoll = false, -math.huge
    Finder.frame()
    return
  end
  Stow.pulse()
  local now = ui.GetTime()
  if now < lastPoll or now - lastPoll >= 0.2 then
    local owner = API.plugins.Get("stow")
    if owner and owner.take_settings_request() then settingsOpen = true end
    if owner and owner.take_alt_finder_request then
      local query = owner.take_alt_finder_request()
      if query then Finder.open(query ~= "" and query or nil) end
    end
    lastPoll = now
  end
  Finder.frame()
  if not settingsOpen then return end
  ui.SetNextWindowSize(525, 460, ui.Cond.FirstUseEver)
  local visible, open = ui.Begin("Stow Settings###stow.settings", true)
  if visible then Options.draw(Stow) end
  ui.End()
  settingsOpen = open
end)
