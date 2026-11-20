-- From the Stow checkout, run: lua tests/test_model.lua
local luaDofile = dofile
function dofile(path)
  return luaDofile(path:match("^lib/") and "ui/modern/" .. path or path)
end

local function eq(actual, expected, context)
  assert(actual == expected, string.format("%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
end

local function item(id, name, category, extra)
  local data = {id = id, name = name, category = category, count = 1, bagSlots = 0, sellable = true}
  for key, value in pairs(extra or {}) do data[key] = value end
  return data
end

local function row(place, where, slot, sub, value, kept)
  return {place = place, where = where, slot = slot, sub = sub, item = value, kept = kept}
end

local function fixture()
  local host = {
    settings = {}, calls = {}, windows = {BankWnd = true}, rowsRead = 0, probes = 0,
    server = "Bastion|eq.example:5998", character = "Tester", frame = 1, time = 5,
    revision = 1, keepRevision = 0, live = true, allowed = true, free = 2, capacity = 6,
    rows = {
      row("i:17", "worn", 17, -1, item(500, "Worn Helm", "armor")),
      row("i:23", "carried", 23, -1, item(90, "Field Pack", "", {bagSlots = 4})),
      row("i:23:0", "carried", 23, 0, item(100, "Bronze Sword", "weapons", {value = 120})),
      row("i:23:1", "carried", 23, 1, item(200, "Tainted Gem", "augments", {augment = true, lore = true}), true),
      row("i:23:2", "carried", 23, 2, item(300, "Sage Leaf", "tradeskill", {count = 5, tradeskill = true})),
      row("i:24", "carried", 24, -1, item(400, "Lost Ledger", "", {questItem = true, sellable = false})),
      row("b:0", "bank", 0, -1, item(91, "Bank Satchel", "", {bagSlots = 3})),
      row("b:0:0", "bank", 0, 0, item(100, "Bronze Sword", "weapons")),
      row("s:0", "shared", 0, -1, item(550, "Shared Shield", "armor")),
    },
  }
  function host:advance(seconds)
    self.frame, self.time = self.frame + 1, self.time + (seconds or 1.1)
  end
  local function effect(name, ...)
    if not host.allowed then return nil end
    host.calls[#host.calls + 1] = {name, ...}
    return true
  end
  ui = {
    GetFrameCount = function() return host.frame end,
    GetTime = function() return host.time end,
    GetSetting = function(key) return host.settings[key] end,
    SetSetting = function(key, value)
      if type(value) == "boolean" then value = value and "1" or "0" end
      host.settings[key] = tostring(value)
      return true
    end,
  }
  hs = {UI = {
    session = {InGame = function() return host.character ~= nil end},
    character = {Name = function() return host.character end},
    plugins = {Get = function(owner)
      eq(owner, "stow", "plugin owner")
      return {server_identity = function() return host.server end}
    end},
    windows = {Shown = function(name) return host.windows[name] == true end},
    inventory = {
      FirstBagSlot = 23, LastBagSlot = 25, CursorSlot = 33,
      HasSlot = function(slot) return slot >= 23 and slot <= 25 end,
      ItemsRevision = function() return host.revision, host.keepRevision end,
      AllItems = function() host.rowsRead = host.rowsRead + 1; return host.rows end,
      InventorySpace = function() return host.free, host.capacity end,
      BankSeen = function() return host.live end,
      Item = function(slot) if slot == 33 then return host.cursor end end,
      ItemJob = function() return host.busy end,
      ClickSlot = function(...) return effect("carried", ...) end,
      BankSlotClick = function(...) return effect("bank", ...) end,
      PlaceClick = function(...) return effect("open", ...) end,
      CanPlace = function(place) return place ~= "i:23:3" end,
      SetItemKept = function(id, name, on)
        if effect("keep", id, name, on) then
          for _, entry in ipairs(host.rows) do
            if entry.item.id == id then entry.kept = on end
          end
          host.keepRevision = host.keepRevision + 1
        end
      end,
      SortItems = function(...)
        effect("sort", ...)
        return host.sortError
      end,
      BulkItems = function(mode, places, dryRun)
        if dryRun then
          eq(mode, "sell", "permission probe mode")
          eq(#places, 0, "permission probe has no item addresses")
          host.probes = host.probes + 1
          if host.allowed then return 0, "Open a merchant first." end
          return nil
        end
        if effect("bulk", mode, places) then return #places end
      end,
    },
  }}
  HailstoneStowModel = nil
  return dofile("lib/stow_model.lua"), host
end

local function group(view, id)
  for _, candidate in ipairs(view.groups) do
    if candidate.id == id then return candidate end
  end
end

local function cell(view, place)
  for _, section in ipairs(view.groups) do
    for _, candidate in ipairs(section.cells) do
      if candidate.place == place then return candidate, section.id end
    end
  end
end

local function testGroupingAndSnapshots()
  local S, host = fixture()
  local initial = S.view("inventory")
  eq(#group(initial, "new").cells, 4, "initial carried items are New")
  eq(S.view("inventory"), initial, "same query reuses the view")
  eq(host.rowsRead, 1, "read the native inventory once")

  local custom = assert(S.addCategory("  Forage, fish = 100%  "))
  eq(S.assign(100, custom), true, "assign an item ID")
  local _, section = cell(S.view("inventory"), "i:23:0")
  eq(section, custom, "custom assignment overrides New by default")
  S.set("customFirst", false)
  _, section = cell(S.view("inventory"), "i:23:0")
  eq(section, "new", "New can take priority over custom assignments")
  S.resetNew()
  eq(group(S.view("inventory"), "new"), nil, "reset uses a fresh baseline")
  eq(group(S.view("inventory"), custom).label, "Forage, fish = 100%", "normalized custom label")
  eq(#group(S.view("inventory"), "quest").cells, 1, "quest metadata routes to Quest Items")
  eq(#group(S.view("inventory"), "augment").cells, 1, "augmentation metadata routes to Augments")
  eq(S.setCategoryEnabled(custom, false), true, "disable a custom category")
  eq(#group(S.view("inventory"), "weapons").cells, 1, "disabled assignment falls back to its type")
  eq(S.setCategoryEnabled(custom, true), true, "reenable a custom category")
  eq(S.renameCategory(custom, "Fishing"), true, "rename custom category")
  eq(S.moveCategory(custom, -1), true, "move custom category up")
  eq(S.categories()[#S.categories() - 2].id, custom, "custom order takes effect")
  eq(host.rowsRead, 1, "config changes rebuild views using the existing snapshot")

  host.rows[5].item.count, host.revision = 7, 2
  eq(#group(S.view("inventory"), "new").cells, 1, "higher quantity marks an existing stack New")
  eq(host.rowsRead, 2, "inventory changes refresh snapshot")
  S.resetNew()
  host.rows[5].item.count, host.revision = 8, 3
  eq(#group(S.view("inventory"), "new").cells, 1, "second reset replaces rather than adds baseline")
  S.removeCategory(custom)
  eq(S.assignment(100), nil, "deleting a category clears assignments")
end

local function testLayoutsAndSearch()
  local S, host = fixture()
  S.resetNew()
  local view = S.view("inventory", "combined")
  eq(#view.groups, 1, "combined view uses one grid")
  eq(#view.groups[1].cells, 6, "combined view retains every occupied and empty place")
  eq(#view.bags, 1, "equipped container shown in bag bar")
  eq(view.bags[1].place, "i:23", "bag bar retains the original slot")
  eq(view.free, 2, "inventory free space")
  eq(view.capacity, 6, "inventory capacity")
  view = S.view("inventory", "bags")
  local pack = group(view, "i:23")
  eq(#pack.cells, 4, "physical bag preserves each of its four slots")
  eq(pack.cells[4].place, "i:23:3", "empty physical slot retains its address")
  eq(pack.cells[4].empty, true, "physical bag empty cell")
  eq(#group(S.view("inventory"), "empty").cells, 2, "grouped view retains physical free places")
  eq(S.view("inventory", "grouped", 'bag:"Field Pack" -is:kept').matched, 2, "conjoined quoted and negated search")
  eq(S.view("inventory", "combined", "BRONZE id:100 type:weapons").matched, 1, "case-insensitive item name, ID and type")
  eq(S.view("inventory", "combined", "is:quest").matched, 1, "quest search uses the item flag")
  eq(cell(S.view("inventory", "combined", "is:quest"), "i:23:0").match, false, "default search retains nonmatching cells")
  S.set("searchDim", false)
  eq(cell(S.view("inventory", "combined", "is:quest"), "i:23:0"), nil, "option to hide search misses")

  S.set("bankFiltering", false)
  view = S.view("bank", "grouped", "id:100")
  eq(view.mode, "combined", "bank grouping can be independently disabled")
  eq(view.matched, 1, "bank search is independent of grouping")
  eq(view.capacity, 18, "personal bank capacity includes contents of open bags")
  eq(S.view("shared", "combined").capacity, 2, "two shared bank slots")
  host.windows.BankWnd, host.live = false, false
  view = S.view("bank", "combined")
  eq(view.live, false, "closed bank uses the saved view")
  eq(view.free, 0, "closed bank cannot promise free slots")
  eq(cell(view, "b:0:0").stale, true, "last-seen bank slots are stale")
end

local function testProfilesAndPresets()
  local S, host = fixture()
  local custom = assert(S.addCategory("Trade, storage = 100%"))
  S.assign(100, custom)
  S.set("replaceBank", false)
  S.set("autoSell", true)
  S.setJunk(300, true)
  S.resetNew()
  eq(S.applyPreset("adventure"), true, "apply a known preset")
  eq(S.get("size"), 45, "preset sets item size")
  eq(S.get("bankMode"), "combined", "preset sets bank layout")
  eq(S.get("replaceBank"), false, "preset leaves takeover decisions alone")
  eq(S.get("autoSell"), true, "preset leaves explicit sale permission alone")
  eq(S.assignment(100), custom, "preset leaves assignments alone")
  eq(S.applyPreset("missing"), false, "unknown preset rejected")
  S.set("compressEmpty", false)
  eq(S.savePreset("My bank, large = 100%"), true, "save the current layout")
  local saved = S.presets()[#S.presets()]
  eq(saved.custom, true, "saved preset is marked editable")
  S.applyPreset("everyday")
  eq(S.get("compressEmpty"), true, "switch away from saved layout")
  eq(S.applyPreset(saved.id), true, "apply the saved layout")
  eq(S.get("compressEmpty"), false, "saved false display setting round-trips")
  host.character = "Second"
  host:advance()
  eq(S.assignment(100), nil, "second character has independent assignments")
  eq(S.get("replaceBank"), true, "second character starts with defaults")
  eq(S.isJunk(300), false, "second character has independent junk marks")
  host.character = nil
  host:advance()
  eq(S.active(), false, "inactive at character selection")
  host.server, host.character = "Other|eq.example:5998", "Tester"
  host:advance()
  eq(S.assignment(100), nil, "same character name on a different server is isolated")
  host.character = nil
  host:advance()
  eq(S.active(), false, "leaving game clears loaded preferences")
  host.server, host.character = "Bastion|eq.example:5998", "Tester"
  host:advance()
  eq(S.assignment(100), custom, "load original assignment on returning")
  eq(S.get("replaceBank"), false, "serialized false preference round-trips")
  eq(S.isJunk(300), true, "serialized junk mark round-trips")
  eq(group(S.view("inventory"), custom).label, "Trade, storage = 100%", "escaped text round-trips")
  eq(group(S.view("inventory"), "new"), nil, "New baseline survives profile changes")
  eq(S.presets()[#S.presets()].label, saved.label, "custom preset survives profile changes")
  eq(S.removePreset(saved.id), true, "delete a saved preset")
  eq(S.applyPreset(saved.id), false, "deleted preset is unavailable")
  eq(S.removePreset("everyday"), false, "built-in presets stay available")
end

local function testActionGuardsAndJunk()
  local S, host = fixture()
  local carried = S.view("inventory", "bags")
  local sword = cell(carried, "i:23:0")
  local empty = cell(carried, "i:23:3")
  local bank = cell(S.view("bank", "combined"), "b:0:0")
  local shared = cell(S.view("shared", "combined"), "s:0")
  eq(S.click(sword, "left"), true, "carried item click uses the original slot")
  eq(host.calls[1][2], 23, "carried top slot")
  eq(host.calls[1][3], 0, "carried bag offset")
  eq(S.click(bank, "rightheld"), true, "personal bank click uses bank API")
  eq(host.calls[2][5], false, "personal bank scope flag")
  eq(S.click(shared, "left"), true, "shared bank click uses bank API")
  eq(host.calls[3][5], true, "shared bank scope flag")
  eq(S.click(sword, "open"), true, "open physical container by place")
  eq(host.calls[4][2], "i:23:0", "open routed place")
  eq(host.probes, 1, "permission probe cached across nearby clicks")
  host.cursor = item(701, "Held Item", "")
  host:advance(0.01)
  eq(S.canPlace(empty), false, "native fit check can reject a slot")
  eq(S.canPlace(cell(carried, "i:25")), true, "native fit check can allow a slot")
  host.cursor = nil
  host:advance(0.01)
  local revisionBefore = host.rowsRead
  eq(S.setKept(sword, true), true, "successful void-returning native Keep action")
  eq(cell(S.view("inventory"), "i:23:0").kept, true, "Keep change reaches the refreshed view")
  eq(host.rowsRead, revisionBefore + 1, "Keep revision invalidates the snapshot")
  S.setKept(sword, false)

  host.allowed = false
  host:advance()
  local effectsBefore = #host.calls
  eq(S.actions(), false, "server policy revoked action capability")
  eq(S.click(sword, "left"), false, "guard refused a carried click")
  eq(S.run("inventory", "stack"), false, "guard refused restack")
  eq(#host.calls, effectsBefore, "denied actions have no side effects")
  host.allowed = true
  host:advance()
  eq(S.actions(), true, "server policy restored action capability")
  host.windows.BankWnd, host.live = false, false
  local stale = cell(S.view("bank", "combined"), "b:0:0")
  eq(S.click(stale, "left"), false, "stale bank view cannot send clicks")

  for _, id in ipairs({90, 100, 200, 400, 500}) do S.setJunk(id, true) end
  host.windows.MerchantWnd = true
  S.pulse()
  eq(#host.calls, effectsBefore, "automated selling defaults off")
  S.set("autoSell", true)
  host.busy = true
  S.pulse()
  eq(#host.calls, effectsBefore, "autosell waits for any active item job")
  host.busy = nil
  S.pulse()
  eq(#host.calls, effectsBefore + 1, "one sale job started after merchant opened")
  local sale = host.calls[#host.calls]
  eq(sale[1], "bulk", "sale uses native bulk job")
  eq(sale[2], "sell", "sale mode")
  eq(#sale[3], 1, "exclude worn, banked, Keep, unsellable, and equipped bags")
  eq(sale[3][1], "i:23:0", "sale targets the specific carried stack")
  S.pulse()
  eq(#host.calls, effectsBefore + 1, "one autosell job per merchant visit")
  host.windows.MerchantWnd = false
  S.pulse()
  host.windows.MerchantWnd = true
  S.pulse()
  eq(#host.calls, effectsBefore + 2, "reopening merchant permits another sale job")

  local bag = S.view("inventory").bags[1]
  eq(S.setBagFilter(bag, "weapons"), true, "set a physical bag filter")
  eq(S.setLocked(sword, true), true, "lock a physical item position")
  eq(S.run("inventory", "stack"), true, "run restack by inventory scope")
  local job = host.calls[#host.calls]
  eq(job[3], "stack", "native restack mode")
  eq(job[4].locked[1], "i:23:0", "native job receives locked physical place")
  eq(job[4].filters["i:23"], "weapons", "native job receives physical bag filter")
  host.windows.MerchantWnd = false
  S.set("tidyAfterLoot", true)
  local beforeLoot = #host.calls
  host.windows.LootWnd = true
  S.pulse()
  eq(#host.calls, beforeLoot, "no tidying while loot is open")
  host.windows.LootWnd = false
  S.pulse()
  eq(#host.calls, beforeLoot + 1, "tidy when loot closes")
  eq(host.calls[#host.calls][3], "tidy", "native tidy mode")
  S.pulse()
  eq(#host.calls, beforeLoot + 1, "do not repeat after loot closes")
end

testGroupingAndSnapshots()
testLayoutsAndSearch()
testProfilesAndPresets()
testActionGuardsAndJunk()
print("Stow model tests passed")
