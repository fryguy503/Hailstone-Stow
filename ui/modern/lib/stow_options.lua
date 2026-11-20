local O = {}

local views = {
  { "grouped", "Category cards" },
  { "combined", "Combined" },
  { "bags", "By physical bag" },
}

local sorts = {
  { "name", "Name" },
  { "type", "Item type" },
  { "value", "Vendor value" },
  { "id", "Item ID" },
  { "slot", "Physical slot" },
}

local bankThemes = {
  { "default", "Current UI" },
  { "slate", "Slate" },
  { "blue", "Blue" },
}

local newName, renameName, presetName = "", "", ""
local selectedCategory, renameCategory, renameLabel, selectedPreset

local function tip(text)
  if text and ui.IsItemHovered() then ui.SetTooltip(text) end
end

local function toggle(S, key, label, help)
  local value, changed = ui.Checkbox(label, S.get(key) == true)
  if changed then S.set(key, value) end
  tip(help)
end

local function slider(S, key, label, minimum, maximum, format)
  ui.SetNextItemWidth(160)
  local value, changed = ui.SliderInt(label, S.get(key), minimum, maximum, format)
  if changed then S.set(key, value) end
end

local function selectSetting(S, key, label, choices)
  local active = S.get(key)
  local preview = choices[1][2]
  for _, choice in ipairs(choices) do
    if choice[1] == active then preview = choice[2] end
  end
  ui.SetNextItemWidth(160)
  if ui.BeginCombo(label, preview) then
    for _, choice in ipairs(choices) do
      if ui.Selectable(choice[2], choice[1] == active) then S.set(key, choice[1]) end
    end
    ui.EndCombo()
  end
end

local function drawPresets(S)
  local presets, current = S.presets(), nil
  for _, preset in ipairs(presets) do
    if preset.id == selectedPreset then current = preset end
  end
  ui.SetNextItemWidth(160)
  if ui.BeginCombo("##stowPreset", current and current.label or "Choose a preset") then
    for _, preset in ipairs(presets) do
      ui.PushID(preset.id)
      if ui.Selectable(preset.label, preset == current) then
        current, selectedPreset = preset, preset.id
      end
      tip(preset.description)
      ui.PopID()
    end
    ui.EndCombo()
  end
  ui.SameLine()
  ui.BeginDisabled(not current)
  if ui.Button("Apply preset") then S.applyPreset(current.id) end
  ui.EndDisabled()
  if current and current.custom then
    ui.SameLine()
    if ui.Button("Delete preset") and S.removePreset(current.id) then selectedPreset = nil end
  end

  ui.SetNextItemWidth(160)
  local submitted
  presetName, submitted = ui.InputTextWithHint("##newpreset", "Preset name", presetName, 64,
                                              ui.InputTextFlags.EnterReturnsTrue)
  ui.SameLine()
  if (ui.Button("Save current layout") or submitted) and S.savePreset(presetName) then presetName = "" end
end

local function drawViews(S)
  drawPresets(S)
  ui.Separator()
  toggle(S, "enabled", "Enable Stow")
  toggle(S, "replaceBank", "Use Stow for Bank")
  toggle(S, "replaceBags", "Use Stow for bag windows")
  ui.Separator()
  selectSetting(S, "inventoryMode", "Open All Bags layout", views)
  selectSetting(S, "bankMode", "Bank layout", views)
  selectSetting(S, "visualSort", "Inventory sort", sorts)
  selectSetting(S, "bankSort", "Bank sort", sorts)
  toggle(S, "bankFiltering", "Group bank items by category")
end

local function drawAppearance(S)
  slider(S, "columns", "Columns", 4, 16)
  slider(S, "size", "Item size", 24, 60, "%d px")
  selectSetting(S, "bankTheme", "Bank color", bankThemes)
  toggle(S, "hideEmptyGroups", "Hide empty categories")
  toggle(S, "compressEmpty", "Combine empty slots")
  toggle(S, "showBagBar", "Show bags when opening Stow")
  toggle(S, "windowLocked", "Lock window position")
  toggle(S, "qualityColors", "Color item borders", "Color item borders by EverQuest item flags.")
  toggle(S, "searchDim", "Dim items outside search results", "Turn this off to hide items that do not match.")
end

local function drawCategories(S)
  toggle(S, "customFirst", "Prioritize custom assignments",
         "Keep manually assigned items in their custom category when they are new.")

  ui.SetNextItemWidth(175)
  local submitted
  newName, submitted = ui.InputTextWithHint("##newcategory", "New category name", newName, 64,
                                           ui.InputTextFlags.EnterReturnsTrue)
  ui.SameLine()
  if ui.Button("Add category") or submitted then
    if S.addCategory(newName) then newName = "" end
  end

  local categories = S.categories()
  local index = 1
  for i, category in ipairs(categories) do
    if category.id == selectedCategory then index = i end
  end
  local current = categories[index]
  if not current then return end

  ui.SetNextItemWidth(175)
  if ui.BeginCombo("Category", current.label) then
    for i, category in ipairs(categories) do
      ui.PushID(category.id)
      if ui.Selectable(category.label, i == index) then
        selectedCategory, index, current = category.id, i, category
      end
      ui.PopID()
    end
    ui.EndCombo()
  end

  local fixed = current.id == "other"
  ui.BeginDisabled(fixed)
  local enabled, changed = ui.Checkbox("Show category", current.enabled == true)
  if changed then S.setCategoryEnabled(current.id, enabled) end
  ui.EndDisabled()
  ui.BeginDisabled(fixed or index == 1)
  if ui.Button("Move up") then S.moveCategory(current.id, -1) end
  ui.EndDisabled()
  ui.SameLine()
  local nextCategory = categories[index + 1]
  ui.BeginDisabled(fixed or not nextCategory or nextCategory.id == "other")
  if ui.Button("Move down") then S.moveCategory(current.id, 1) end
  ui.EndDisabled()

  if current.custom then
    if renameCategory ~= current.id or renameLabel ~= current.label then
      renameCategory, renameLabel, renameName = current.id, current.label, current.label
    end
    ui.SetNextItemWidth(175)
    renameName, submitted = ui.InputTextWithHint("##renamecategory", "Category name", renameName, 64,
                                                  ui.InputTextFlags.EnterReturnsTrue)
    ui.SameLine()
    if ui.Button("Rename") or submitted then S.renameCategory(current.id, renameName) end
    if ui.Button("Delete category") then
      if S.removeCategory(current.id) then selectedCategory, renameCategory = nil, nil end
    end
    tip("Delete this category and its item assignments.")
  else
    renameCategory = nil
  end
end

local function drawItemHandling(S)
  toggle(S, "newItems", "Track new items")
  if ui.Button("Reset New Items") then S.resetNew() end
  tip("Use your current item counts as the baseline for New Items.")
  ui.Separator()
  toggle(S, "autoSell", "Sell marked junk when a merchant opens",
         "Automatically sell carried items you marked as junk. Keep marks are honored.")
  toggle(S, "tidyAfterLoot", "Tidy bags after looting",
         "Move eligible carried items into the physical bags assigned to their categories.")
end

function O.draw(S)
  if ui.BeginTabBar("##stowSettings") then
    if ui.BeginTabItem("Views") then
      drawViews(S)
      ui.EndTabItem()
    end
    if ui.BeginTabItem("Appearance") then
      drawAppearance(S)
      ui.EndTabItem()
    end
    if ui.BeginTabItem("Categories") then
      drawCategories(S)
      ui.EndTabItem()
    end
    if ui.BeginTabItem("Item handling") then
      drawItemHandling(S)
      ui.EndTabItem()
    end
    ui.EndTabBar()
  end
  local status = S.status()
  if status and status ~= "" then
    ui.Separator()
    ui.TextWrapped(status)
  end
end

return O
