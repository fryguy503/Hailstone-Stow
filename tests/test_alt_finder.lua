-- Run from the add-on checkout with Lua 5.4.
local load = dofile
dofile = function(path)
  if path == "lib/stow_rules.lua" then return load("ui/modern/" .. path) end
  return {}
end

local clock, reads, observed = 0, 0, nil
local character, inGame = "Aster", true
local bankLive, bankAge = false, 120
local rows = {
  { where = "carried", item = { name = "Spider Silk", icon = 562, count = 4 }, slot = 23 },
  { where = "bank", item = { name = "Spider Silk", count = 8 }, slot = 2, sub = 1, bag = "Satchel", stale = true },
  { where = "worn", item = { name = "Spider Silk", count = 99 }, slot = 1 },
  { where = "shared", item = { name = "Spider Silk", count = 99 }, slot = 2 },
}
local inventory = {
  AllItems = function() reads = reads + 1; return rows end,
  BankSeen = function() return bankLive, bankAge end,
}

hs = { UI = {
  character = { Name = function() return character end },
  session = { InGame = function() return inGame end },
  inventory = inventory,
} }
ui = { GetTime = function() return clock end }

local Finder = load("ui/modern/lib/stow_alt_finder.lua")
Finder.draw = function(view) observed = view end

Finder.open("  SPIDER SILK  ")
Finder.frame()
assert(observed.localOnly and #observed.characters == 1)
assert(observed.characters[1].name == "Aster" and observed.characters[1].session == "local")
assert(observed.characters[1].bankSeen and #observed.items == 2)
assert(observed.items[1].live and observed.items[1].count == 4 and observed.items[1].icon == 562)
assert(not observed.items[2].live and observed.items[2].age == 120)
assert(observed.items[2].count == 8 and observed.items[2].character == "Aster")
assert(observed.items[2].slot == 2 and observed.items[2].sub == 1 and observed.items[2].bag == "Satchel")

clock = 0.1
Finder.frame()
assert(reads == 1, "fallback uses the existing scan interval")

local native = { characters = { { name = "Box", session = "boxed" } }, items = {} }
inventory.AltFinder = function(query)
  assert(query == "spider silk")
  return native
end
clock = 0.25
Finder.frame()
assert(observed == native and reads == 1, "an empty native search still provides an authoritative roster")

inventory.AltFinder = function() return nil end
clock = 0.5
Finder.frame()
assert(observed.localOnly and reads == 2, "a known binding can be unavailable while in game")

bankLive, bankAge = true, nil
rows[2].stale = nil
clock = 0.75
Finder.frame()
assert(observed.items[2].live and observed.items[2].age == nil)

bankLive = false
rows = {}
clock = 1
Finder.frame()
assert(observed.localOnly and #observed.items == 0 and not observed.characters[1].bankSeen)

character = nil
clock = 1.25
Finder.frame()
assert(observed == nil, "inventory waits for the current character")

inGame = false
Finder.frame()
inGame, character = true, "Briar"
Finder.frame()
assert(observed == nil, "leaving the game closes and clears the old character's view")
Finder.open()
Finder.frame()
assert(observed.characters[1].name == "Briar")
print("Stow Alt Finder tests passed")
