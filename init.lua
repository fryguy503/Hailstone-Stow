-- Bridge server identity and slash commands into the Modern interface.
local hs = require("hailstone")
local mq = require("mq")
local settingsRequested = false
local finderQuery

hs.ui_function("server_identity", function()
  local server = hs.server()
  if not server then return nil end
  return table.concat({server.host or "", tostring(server.port or ""), server.world or "", server.world_host or ""}, "|")
end)

hs.ui_function("take_settings_request", function()
  local requested = settingsRequested
  settingsRequested = false
  return requested
end)

hs.ui_function("take_alt_finder_request", function()
  local query = finderQuery
  finderQuery = nil
  return query
end)

hs.ui_function("close_inventory_bags", function()
  mq.cmd("/keypress CLOSE_INV_BAGS")
  return true
end)

-- Some servers allow drawing but deny commands. The Stow window still runs there.
if pcall(mq.bind, "/stow", function() settingsRequested = true end) then
  hs.menu("Stow Settings", "/stow")
end
if pcall(mq.bind, "/altfinder", function(...) finderQuery = table.concat({...}, " ") end) then
  hs.menu("Stow Alt Finder", "/altfinder")
end
