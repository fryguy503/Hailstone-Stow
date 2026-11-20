local M = {}

M.categories = {
  {"new", "New Items"}, {"favorite", "Favorites"}, {"junk", "Junk"}, {"quest", "Quest Items"},
  {"augment", "Augments"}, {"spells", "Spells & Tomes"}, {"supplies", "Consumables"},
  {"weapons", "Weapons"}, {"armor", "Armor"}, {"tradeskill", "Tradeskill Materials"},
  {"other", "Other"},
}

M.bagFilters = {
  {id = "food", label = "Food & Drink"}, {id = "potions", label = "Potions"},
  {id = "tradeskill", label = "Tradeskill Materials"}, {id = "spells", label = "Spells & Tomes"},
  {id = "weapons", label = "Weapons"}, {id = "armor", label = "Armor"}, {id = "augment", label = "Augments"},
}

M.defaults = {
  enabled = true, replaceBank = true, replaceBags = true,
  inventoryMode = "grouped", bankMode = "grouped", columns = 10, size = 31,
  hideEmptyGroups = true, compressEmpty = true, windowLocked = false, showBagBar = false,
  dockGrowth = "auto", emptySlotsCard = false,
  qualityColors = true, searchDim = true, bankFiltering = true, bankTheme = "default",
  visualSort = "name", bankSort = "name", newItems = true, customFirst = true,
  autoSell = false, tidyAfterLoot = false,
}

local modes = {grouped = true, combined = true, bags = true}
local sorts = {name = true, type = true, value = true, id = true, slot = true}
local choices = {
  inventoryMode = modes, bankMode = modes, visualSort = sorts, bankSort = sorts,
  bankTheme = {default = true, slate = true, blue = true},
  dockGrowth = {auto = true, up = true, down = true},
}

function M.setting(key, value)
  local default = M.defaults[key]
  if type(default) == "boolean" then
    if value == true or value == "1" then return true end
    if value == false or value == "0" then return false end
  elseif type(default) == "number" then
    local number = tonumber(value)
    if number and number == number then
      return math.floor(math.max(key == "columns" and 4 or 24, math.min(key == "columns" and 16 or 60, number)))
    end
  elseif choices[key] and choices[key][value] then
    return value
  end
  return default
end

M.presetKeys = {
  "inventoryMode", "bankMode", "columns", "size", "hideEmptyGroups", "compressEmpty", "emptySlotsCard", "showBagBar",
  "qualityColors", "searchDim", "bankFiltering", "bankTheme", "visualSort", "bankSort", "newItems", "customFirst",
}

M.presets = {
  {id = "everyday", label = "Everyday", description = "Category cards with recent loot at the top."},
  {id = "adventure", label = "Adventurer", description = "Large tiles, visible new items, and a compact bank grid.",
    values = {columns = 8, size = 45, bankMode = "combined", bankTheme = "blue"}},
  {id = "crafting", label = "Tradeskiller", description = "Group inventory and keep the bank organized by physical bag.",
    values = {columns = 12, size = 32, bankMode = "bags", visualSort = "type", bankSort = "slot", newItems = false}},
  {id = "compact", label = "Compact", description = "One dense grid per storage area with compressed free space.",
    values = {columns = 14, size = 27, inventoryMode = "combined", bankMode = "combined", showBagBar = false}},
  {id = "classic", label = "Per Bag", description = "View the original bag layout with individual empty slots.",
    values = {inventoryMode = "bags", bankMode = "bags", columns = 8, compressEmpty = false,
      visualSort = "slot", bankSort = "slot"}},
}

function M.place(where, slot, sub)
  local prefix = where == "bank" and "b" or where == "shared" and "s" or "i"
  local top = prefix .. ":" .. slot
  return sub and sub >= 0 and top .. ":" .. sub or top
end

function M.encode(text)
  return (tostring(text):gsub("([^%w_.%-])", function(c) return string.format("%%%02X", c:byte()) end))
end

function M.decode(text)
  return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function M.packMap(values)
  local list = {}
  for key, value in pairs(values) do
    list[#list + 1] = M.encode(key) .. "=" .. M.encode(value)
  end
  table.sort(list)
  return table.concat(list, ",")
end

function M.unpackMap(text, keyConvert, valueConvert)
  local values = {}
  for key, value in (text or ""):gmatch("([^,=]+)=([^,]*)") do
    local parsed = keyConvert(M.decode(key))
    if parsed ~= nil then values[parsed] = valueConvert(M.decode(value)) end
  end
  return values
end

function M.identity(value) return value end

function M.count(row)
  return math.max(1, tonumber(row.item and row.item.count) or 1)
end

function M.makeCell(where, slot, sub, item, bag, stale)
  return {
    item = item, place = M.place(where, slot, sub), where = where, slot = slot, sub = sub,
    bag = bag, stale = stale, empty = not item, match = true,
  }
end

function M.searchTerms(query)
  local terms, i = {}, 1
  while i <= #query do
    local first = query:find("%S", i)
    if not first then break end
    local from, to = first, first
    while to <= #query and not query:sub(to, to):match("%s") do
      if query:sub(to, to) == '"' then
        local closing = query:find('"', to + 1, true)
        if not closing then to = #query + 1; break end
        to = closing
      end
      to = to + 1
    end
    local term = query:sub(from, to - 1):gsub('"', "")
    local negate = term:sub(1, 1) == "-"
    if negate then term = term:sub(2) end
    local key, value = term:match("^(%a+):(.+)$")
    if term ~= "" then terms[#terms + 1] = {key = key, value = value or term, negate = negate} end
    i = to + 1
  end
  return terms
end

local function contains(text, needle)
  return (text or ""):lower():find(needle, 1, true) ~= nil
end

function M.matchCell(cell, group, terms, junk)
  local item = cell.item
  for _, term in ipairs(terms) do
    local key, value, found = term.key, term.value, false
    if key == "bag" then found = contains(cell.bag, value)
    elseif key == "type" or key == "group" then
      found = contains(item.category, value) or contains(group.label, value) or group.id == value
    elseif key == "id" then found = tonumber(value) == item.id
    elseif key == "is" then
      if value == "new" then found = cell.new == true
      elseif value == "kept" then found = cell.kept == true
      elseif value == "junk" then found = junk
      elseif value == "quest" then found = item.questItem == true
      elseif value == "tradeskill" then found = item.tradeskill == true
      elseif value == "lore" then found = item.lore == true
      elseif value == "notrade" then found = item.noTrade == true
      elseif value == "usable" then found = item.usable == true end
    else
      found = contains(item.name, value) or contains(group.label, value)
    end
    if found == term.negate then return false end
  end
  return true
end

function M.classifies(id, cell, prefs)
  local item = cell.item
  local category = item.category
  if id == "new" then return cell.new end
  if id == "junk" then return prefs.junk[item.id] == "1" end
  if id == "quest" then return item.questItem == true end
  if id == "augment" then return item.augment or category == "augment" end
  if id == "spells" then return category == "spells" end
  if id == "supplies" then return category == "food" or category == "potions" end
  if id == "weapons" then return category == "weapons" end
  if id == "armor" then return category == "armor" end
  if id == "tradeskill" then return item.tradeskill or category == "tradeskill" end
  return false
end

local function slotOrder(a, b)
  if a.slot ~= b.slot then return a.slot < b.slot end
  return a.sub < b.sub
end

function M.sort(cells, kind)
  table.sort(cells, function(a, b)
    if kind == "slot" then return slotOrder(a, b) end
    if not a.item or not b.item then
      if a.empty ~= b.empty then return not a.empty end
      return slotOrder(a, b)
    end
    if kind == "value" and (a.item.value or 0) ~= (b.item.value or 0) then
      return (a.item.value or 0) > (b.item.value or 0)
    end
    if kind == "type" and (a.item.category or "") ~= (b.item.category or "") then
      return (a.item.category or "") < (b.item.category or "")
    end
    if kind ~= "id" and a.nameKey ~= b.nameKey then return a.nameKey < b.nameKey end
    if a.item.id ~= b.item.id then return a.item.id < b.item.id end
    return slotOrder(a, b)
  end)
end

return M
