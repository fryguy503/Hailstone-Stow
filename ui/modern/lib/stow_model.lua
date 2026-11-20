local existing = rawget(_G, "HailstoneStowModel")
if existing then return existing end

local Rules = dofile("lib/stow_rules.lua")
local API = hs.UI
local Inventory = API.inventory
local Windows = API.windows
local M = {}
local prefs, snapshot, views = nil, nil, {}
local characterFrame, identityTime, permissionTime, actionPermission = -1, -math.huge, -math.huge, false
local cursorFrame, cursorItem = -1, nil
local message, messageUntil = nil, 0
local merchantHandled, wasLooting = false, false
local presetNames, builtinNames = {}, {}
for _, preset in ipairs(Rules.presets) do presetNames[preset.id] = preset end
for _, category in ipairs(Rules.categories) do builtinNames[category[1]] = category[2] end

local function invalidate()
  views = {}
end

local function resetSession()
  snapshot, views = nil, {}
  merchantHandled, wasLooting = false, false
  permissionTime = -math.huge
  cursorFrame, cursorItem = -1, nil
  message, messageUntil = nil, 0
end

local function current()
  local frame = ui.GetFrameCount()
  if frame == characterFrame then return prefs end
  characterFrame = frame
  local character = API.session.InGame() and API.character.Name()
  if not character or character == "" then
    if prefs then resetSession() end
    prefs = nil
    return nil
  end
  local now = ui.GetTime()
  if prefs and prefs.character == character and now >= identityTime and now - identityTime < 1 then return prefs end

  local owner = API.plugins.Get("stow")
  local server = owner and owner.server_identity()
  if not server then
    if prefs then resetSession() end
    prefs = nil
    return nil
  end
  local path = "stow." .. Rules.encode(server .. "|" .. character:lower()) .. "."
  identityTime = now
  if prefs and prefs.path == path then return prefs end
  resetSession()
  local function map(name, keyConvert, valueConvert)
    return Rules.unpackMap(ui.GetSetting(path .. name), keyConvert or Rules.identity, valueConvert or Rules.identity)
  end
  prefs = {
    character = character, path = path, config = {},
    assignments = map("assignments", tonumber), custom = map("categories"), disabled = map("disabled"),
    order = map("order", Rules.identity, tonumber), junk = map("junk", tonumber),
    baseline = map("baseline", tonumber, tonumber), locks = map("locks"), filters = map("bagFilters"),
    customPresets = map("presets"),
  }
  for key in pairs(Rules.defaults) do
    prefs.config[key] = Rules.setting(key, ui.GetSetting(path .. "option." .. key))
  end
  return prefs
end

local function save(name, values)
  local p = current()
  if p then ui.SetSetting(p.path .. name, Rules.packMap(values)) end
  invalidate()
end

function M.info(text)
  message, messageUntil = text, ui.GetTime() + 8
end

function M.status()
  if ui.GetTime() < messageUntil then return message end
end

function M.get(key)
  local p = current()
  if p then return p.config[key] end
  return Rules.defaults[key]
end

function M.set(key, value)
  local p = current()
  value = Rules.setting(key, value)
  if not p or value == nil or p.config[key] == value then return false end
  p.config[key] = value
  ui.SetSetting(p.path .. "option." .. key, value)
  invalidate()
  return true
end

function M.active()
  return current() ~= nil and M.get("enabled")
end

function M.actions()
  if not current() then return false end
  local now = ui.GetTime()
  if now < permissionTime or now - permissionTime >= 1 then
    -- An empty dry-run has no effects. A blocked binding returns nil instead of a count.
    actionPermission = type(Inventory.BulkItems("sell", {}, true)) == "number"
    permissionTime = now
  end
  return actionPermission
end

function M.presets()
  local p = current()
  if not p then return Rules.presets end
  local custom = {}
  for id, packed in pairs(p.customPresets) do
    local options = Rules.unpackMap(packed, Rules.identity, Rules.identity)
    if options.label then
      custom[#custom + 1] = {id = id, label = options.label, custom = true,
        description = "Your saved display settings.", values = options}
    end
  end
  table.sort(custom, function(a, b) return a.id < b.id end)
  local list = {table.unpack(Rules.presets)}
  for _, entry in ipairs(custom) do list[#list + 1] = entry end
  return list
end

function M.applyPreset(id)
  if not current() then return false end
  local preset = presetNames[id]
  if not preset then
    for _, entry in ipairs(M.presets()) do
      if entry.id == id then preset = entry; break end
    end
  end
  if not preset then return false end
  for _, key in ipairs(Rules.presetKeys) do
    local value = preset.values and preset.values[key]
    if value == nil then value = Rules.defaults[key] end
    M.set(key, value)
  end
  M.info("Applied " .. preset.label .. " preset.")
  return true
end

function M.savePreset(name)
  local p = current()
  if not p or type(name) ~= "string" then return false end
  name = name:match("^%s*(.-)%s*$")
  if name == "" or #name > 48 or name:find("[%c#]") then
    M.info("Use a preset name of 1 to 48 characters.")
    return false
  end
  local id = "preset-" .. name:lower()
  for _, preset in ipairs(Rules.presets) do
    if preset.label:lower() == name:lower() then
      M.info("Choose a name different from the built-in presets.")
      return false
    end
  end
  local count = 0
  for _ in pairs(p.customPresets) do count = count + 1 end
  if not p.customPresets[id] and count >= 24 then M.info("There is room for 24 saved presets."); return false end
  local values = {label = name}
  for _, key in ipairs(Rules.presetKeys) do
    local value = p.config[key]
    if type(value) == "boolean" then value = value and "1" or "0" end
    values[key] = value
  end
  p.customPresets[id] = Rules.packMap(values)
  save("presets", p.customPresets)
  M.info("Saved " .. name .. " preset.")
  return true
end

function M.removePreset(id)
  local p = current()
  if not p or not p.customPresets[id] then return false end
  p.customPresets[id] = nil
  save("presets", p.customPresets)
  return true
end

function M.categories()
  local p = current()
  local out = {}
  for i, category in ipairs(Rules.categories) do
    local id = category[1]
    out[#out + 1] = {id = id, label = category[2], enabled = id == "other" or not (p and p.disabled[id]),
      priority = p and p.order[id] or i}
  end
  if p then
    for id, name in pairs(p.custom) do
      out[#out + 1] = {id = id, label = name, enabled = not p.disabled[id], custom = true,
        priority = p.order[id] or #Rules.categories}
    end
  end
  table.sort(out, function(a, b)
    if a.id == "other" or b.id == "other" then return a.id ~= "other" end
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.id < b.id
  end)
  return out
end

local function validCategory(p, id)
  return id and (builtinNames[id] or p.custom[id])
end

local function categoryName(name, except)
  if type(name) ~= "string" then return nil end
  name = name:match("^%s*(.-)%s*$")
  if name == "" or #name > 48 or name:find("[%c#]") then
    M.info("Use a group name of 1 to 48 characters.")
    return nil
  end
  for _, category in ipairs(M.categories()) do
    if category.id ~= except and category.label:lower() == name:lower() then
      M.info("That group name already exists.")
      return nil
    end
  end
  return name
end

function M.addCategory(name)
  local p = current()
  if not p then return nil end
  name = categoryName(name)
  if not name then return nil end
  local nextId
  for n = 1, 32 do
    local id = "custom-" .. n
    if not p.custom[id] then nextId = id; break end
  end
  if not nextId then M.info("There is room for 32 custom groups."); return nil end
  local order = M.categories()
  for i, entry in ipairs(order) do p.order[entry.id] = i end
  p.order[nextId] = #order
  p.custom[nextId] = name
  save("categories", p.custom)
  save("order", p.order)
  return nextId
end

function M.renameCategory(id, name)
  local p = current()
  if not p or not p.custom[id] then return false end
  name = categoryName(name, id)
  if not name then return false end
  p.custom[id] = name
  save("categories", p.custom)
  return true
end

function M.removeCategory(id)
  local p = current()
  if not p or not p.custom[id] then return false end
  p.custom[id], p.order[id], p.disabled[id] = nil, nil, nil
  for item, group in pairs(p.assignments) do
    if group == id then p.assignments[item] = nil end
  end
  save("categories", p.custom)
  save("order", p.order)
  save("disabled", p.disabled)
  save("assignments", p.assignments)
  return true
end

function M.setCategoryEnabled(id, enabled)
  local p = current()
  if not p or id == "other" or not validCategory(p, id) then return false end
  p.disabled[id] = not enabled and "1" or nil
  save("disabled", p.disabled)
  return true
end

function M.moveCategory(id, delta)
  local p = current()
  if not p or id == "other" or (delta ~= -1 and delta ~= 1) then return false end
  local list = M.categories()
  for i, category in ipairs(list) do
    if category.id == id then
      local j = i + delta
      if j < 1 or j >= #list then return false end
      list[i], list[j] = list[j], list[i]
      for n, entry in ipairs(list) do p.order[entry.id] = n end
      save("order", p.order)
      return true
    end
  end
  return false
end

function M.assignment(itemId)
  local p = current()
  return p and p.assignments[itemId]
end

function M.assign(itemId, groupId)
  local p = current()
  if not p or type(itemId) ~= "number" or (groupId and not validCategory(p, groupId)) then return false end
  p.assignments[itemId] = groupId
  save("assignments", p.assignments)
  return true
end

function M.isJunk(itemId)
  local p = current()
  return p and p.junk[itemId] == "1"
end

function M.setJunk(itemId, on)
  local p = current()
  if not p or type(itemId) ~= "number" then return false end
  p.junk[itemId] = on and "1" or nil
  save("junk", p.junk)
  return true
end

local function bankOpen()
  return Windows.Shown("BankWnd") == true or Windows.Shown("BigBankWnd") == true
end

local function cursor()
  local frame = ui.GetFrameCount()
  if frame ~= cursorFrame then
    cursorFrame, cursorItem = frame, Inventory.Item(Inventory.CursorSlot)
  end
  return cursorItem
end

local function inventorySnapshot()
  if not current() then return nil end
  local inv, keep = Inventory.ItemsRevision()
  local live = Inventory.BankSeen() == true
  local open = bankOpen()
  if snapshot and snapshot.inv == inv and snapshot.keep == keep and snapshot.live == live and snapshot.open == open then
    return snapshot
  end

  local rows = Inventory.AllItems() or {}
  local places, counts = {}, {}
  for _, row in ipairs(rows) do
    row.sub = row.sub or -1
    places[row.place] = row
    if row.where == "carried" or row.where == "worn" then
      counts[row.item.id] = (counts[row.item.id] or 0) + Rules.count(row)
    end
  end
  local held = cursor()
  if held then counts[held.id] = (counts[held.id] or 0) + Rules.count({item = held}) end
  local free, capacity = Inventory.InventorySpace()
  local generalSlots = capacity
  for _, row in ipairs(rows) do
    if row.where == "carried" and row.sub < 0 and (row.item.bagSlots or 0) > 0 then
      generalSlots = generalSlots - row.item.bagSlots + 1
    end
  end
  snapshot = {rows = rows, places = places, counts = counts, inv = inv, keep = keep, live = live,
    open = open, big = open and Windows.Shown("BigBankWnd") == true,
    carriedFree = free, carriedCapacity = capacity,
    lastGeneralSlot = math.min(Inventory.LastBagSlot, Inventory.FirstBagSlot + generalSlots - 1)}
  invalidate()
  return snapshot
end

function M.resetNew()
  local p, data = current(), inventorySnapshot()
  if not p or not data then return false end
  p.baseline = data.counts
  save("baseline", p.baseline)
  M.info("New items cleared.")
  return true
end

local function classify(cell, categories, p)
  local assigned = p.assignments[cell.item.id]
  if cell.new and p.config.newItems and not p.disabled.new and not p.config.customFirst then return "new" end
  if assigned and validCategory(p, assigned) and not p.disabled[assigned] then return assigned end
  for _, category in ipairs(categories) do
    if category.enabled and (category.id ~= "new" or p.config.newItems)
        and Rules.classifies(category.id, cell, p) then return category.id end
  end
  return "other"
end

function M.category(cell)
  local p = current()
  if p and cell.item then return classify(cell, M.categories(), p) end
end

local function cellAt(data, where, slot, sub, bag)
  local row = data.places[Rules.place(where, slot, sub)]
  local cell = Rules.makeCell(where, slot, sub, row and row.item, bag or row and row.bag,
    where ~= "carried" and (not data.live or not data.open or row and row.stale == true))
  cell.kept = row and row.kept == true
  if row then
    cell.nameKey = (row.item.name or ""):lower()
    cell.new = where == "carried" and M.get("newItems")
      and (data.counts[row.item.id] or 0) > (prefs.baseline[row.item.id] or 0)
  end
  return cell
end

local function scopeSpec(scope, data)
  if scope == "inventory" then return "carried", Inventory.FirstBagSlot, data.lastGeneralSlot, true end
  local where = scope == "shared" and "shared" or "bank"
  if not data.open or not data.live then
    local last = -1
    for _, row in ipairs(data.rows) do
      if row.where == where then last = math.max(last, row.slot) end
    end
    return where, 0, last, false
  end
  return where, 0, where == "shared" and 1 or data.big and 23 or 15, true
end

function M.view(scope, mode, search)
  local p, data = current(), inventorySnapshot()
  if not p or not data then return {groups = {}, bags = {}, free = 0, capacity = 0, total = 0, matched = 0} end
  local key = scope == "inventory" and "inventoryMode" or "bankMode"
  mode = Rules.setting(key, mode or p.config[key])
  if key == "bankMode" and not p.config.bankFiltering and mode == "grouped" then mode = "combined" end
  search = (search or ""):lower()
  local cache = views[scope]
  if cache and cache.mode == mode and cache.search == search then return cache end

  local categories = M.categories()
  local terms = Rules.searchTerms(search)
  local byCategory, grouped, physical, all = {}, {}, {}, {id = "all", label = "All Items", cells = {}}
  for _, category in ipairs(categories) do
    if category.enabled and (category.id ~= "new" or p.config.newItems and scope == "inventory") then
      local group = {id = category.id, label = category.label, cells = {}}
      byCategory[category.id] = group
      grouped[#grouped + 1] = group
    end
  end
  local loose = {id = "loose", label = scope == "inventory" and "Loose Items" or "Bank Slots", cells = {}}
  physical[1] = loose
  local empty = {id = "empty", label = "Free Slots", cells = {}}
  local result = {groups = {}, bags = {}, free = 0, capacity = 0, matched = 0, total = 0,
    mode = mode, search = search, live = scope == "inventory" or data.live and data.open}

  local function add(cell, bagGroup)
    result.capacity = result.capacity + 1
    if cell.empty then
      result.free = result.free + 1
      empty.cells[#empty.cells + 1] = cell
    else
      result.total = result.total + 1
      local group = byCategory[classify(cell, categories, p)] or byCategory.other
      cell.match = Rules.matchCell(cell, group, terms, p.junk[cell.item.id] == "1")
      if cell.match then result.matched = result.matched + 1 end
      if not cell.match and not p.config.searchDim then return end
      group.cells[#group.cells + 1] = cell
    end
    all.cells[#all.cells + 1] = cell
    bagGroup.cells[#bagGroup.cells + 1] = cell
  end

  local where, first, last, live = scopeSpec(scope, data)
  for slot = first, last do
    local top = cellAt(data, where, slot, -1)
    local count = top.item and top.item.bagSlots or 0
    if count > 0 then
      result.bags[#result.bags + 1] = top
      local label = top.item.name or "Bag"
      local group = {id = top.place, label = label, cells = {}, bag = top}
      physical[#physical + 1] = group
      for sub = 0, count - 1 do
        local cell = cellAt(data, where, slot, sub, label)
        if live or cell.item then add(cell, group) end
      end
    elseif live or top.item then
      add(top, loose)
    end
  end
  if scope == "inventory" then result.free, result.capacity = data.carriedFree, data.carriedCapacity end
  if #empty.cells > 0 then grouped[#grouped + 1] = empty end

  local layout = mode == "combined" and {all} or mode == "bags" and physical or grouped
  local sort = scope == "inventory" and p.config.visualSort or p.config.bankSort
  for _, group in ipairs(layout) do
    if #group.cells > 0 or not p.config.hideEmptyGroups then
      Rules.sort(group.cells, mode == "bags" and "slot" or sort)
      group.matched, group.total = 0, 0
      for _, cell in ipairs(group.cells) do
        if cell.item then
          group.total = group.total + 1
          if cell.match then group.matched = group.matched + 1 end
        end
      end
      result.groups[#result.groups + 1] = group
    end
  end
  views[scope] = result
  return result
end

function M.click(cell, button, outside)
  if not cell or cell.stale or not M.actions() then return false end
  if button == "open" then
    if cell.where == "shared" then return Inventory.BankSlotClick(cell.slot, -1, "right", true) == true end
    return Inventory.PlaceClick(cell.place, "open") == true
  end
  if cell.where == "carried" then return Inventory.ClickSlot(cell.slot, cell.sub, button, outside) == true end
  return Inventory.BankSlotClick(cell.slot, cell.sub, button, cell.where == "shared") == true
end

function M.canPlace(cell)
  if cell.stale then return false end
  if not cell.empty or not Inventory.CanPlace or not cursor() then return nil end
  return Inventory.CanPlace(cell.place)
end

function M.setKept(cell, on)
  if not cell or not cell.item or cell.stale or not M.actions() then return false end
  Inventory.SetItemKept(cell.item.id, cell.item.name, on)
  return true
end

function M.isLocked(cell)
  local p = current()
  return p and cell and p.locks[cell.place] == "1"
end

function M.setLocked(cell, on)
  local p = current()
  if not p or not cell then return false end
  p.locks[cell.place] = on and "1" or nil
  save("locks", p.locks)
  return true
end

function M.bagFilters()
  return Rules.bagFilters
end

function M.bagFilter(cell)
  local p = current()
  return p and cell and p.filters[cell.place]
end

function M.setBagFilter(cell, key)
  local p = current()
  if not p or not cell or cell.sub >= 0 or cell.where == "shared" then return false end
  p.filters[cell.place] = key
  save("bagFilters", p.filters)
  return true
end

function M.run(scope, mode, bagWindow)
  local p = current()
  if not p or not M.actions() then M.info("Item actions are unavailable."); return false end
  if scope == "shared" then M.info("Move shared bank items through their slots."); return false end
  local data = inventorySnapshot()
  local locked = {}
  for place in pairs(p.locks) do
    locked[#locked + 1] = place
    local row = data and data.places[place]
    if row and row.sub < 0 and (row.item.bagSlots or 0) > 0 then
      for sub = 0, row.item.bagSlots - 1 do
        locked[#locked + 1] = Rules.place(row.where, row.slot, sub)
      end
    end
  end
  local err = Inventory.SortItems(bagWindow or scope, mode, {filters = p.filters, locked = locked})
  M.info(err or (Inventory.ItemJob() and "Working on items." or "Everything is already organized."))
  return not err
end

function M.sell()
  local data = inventorySnapshot()
  if not data or not M.actions() then M.info("Item actions are unavailable."); return false end
  local places = {}
  for _, row in ipairs(data.rows) do
    if row.where == "carried" and M.isJunk(row.item.id) and not row.kept and row.item.sellable
        and (row.item.bagSlots or 0) == 0 then
      places[#places + 1] = row.place
    end
  end
  if #places == 0 then M.info("No marked items to sell."); return false end
  local count, err = Inventory.BulkItems("sell", places)
  M.info(err or string.format("Selling %d marked stacks.", count or 0))
  return count ~= nil and not err
end

function M.pulse()
  if not M.active() then return end
  local autoSell = M.get("autoSell")
  local tidy = M.get("tidyAfterLoot")
  if autoSell then
    if not Windows.Shown("MerchantWnd") then
      merchantHandled = false
    elseif not merchantHandled and not Inventory.ItemJob() and M.actions() then
      merchantHandled = true
      M.sell()
    end
  else
    merchantHandled = false
  end
  if tidy then
    local looting = Windows.Shown("LootWnd") == true
    if wasLooting and not looting and not Inventory.ItemJob() and M.actions() then M.run("inventory", "tidy") end
    wasLooting = looting
  else
    wasLooting = false
  end
end

rawset(_G, "HailstoneStowModel", M)
return M
