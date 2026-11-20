local Stow = dofile("lib/stow_model.lua")
local Options = dofile("lib/stow_options.lua")
local settingsOpen, lastPoll = false, -math.huge

ui.window("Stow Maintenance", function()
  if not hs.UI.session.InGame() then settingsOpen = false; return end
  Stow.pulse()
  local now = ui.GetTime()
  if now < lastPoll or now - lastPoll >= 0.2 then
    local owner = hs.UI.plugins.Get("stow")
    if owner and owner.take_settings_request() then settingsOpen = true end
    lastPoll = now
  end
  if not settingsOpen then return end
  ui.SetNextWindowSize(525, 460, ui.Cond.FirstUseEver)
  local visible, open = ui.Begin("Stow Settings###stow.settings", true)
  if visible then Options.draw(Stow) end
  ui.End()
  settingsOpen = open
end)
