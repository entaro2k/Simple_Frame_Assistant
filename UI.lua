local addonName, SFA = ...
SFA = _G[addonName] or SFA

local CreateFrame = CreateFrame
local UIDropDownMenu_CreateInfo = UIDropDownMenu_CreateInfo
local UIDropDownMenu_SetWidth = UIDropDownMenu_SetWidth
local UIDropDownMenu_SetText = UIDropDownMenu_SetText
local UIDropDownMenu_Initialize = UIDropDownMenu_Initialize
local UIDropDownMenu_AddButton = UIDropDownMenu_AddButton

local function CreateLabel(parent, text, x, y, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function CreateCheckbox(parent, label, x, y, checked, onClick)
  local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  box:SetPoint("TOPLEFT", x, y)
  box:SetChecked(checked)
  box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  box.text:SetPoint("LEFT", box, "RIGHT", 2, 0)
  box.text:SetText(label)
  box:SetScript("OnClick", function(self)
    onClick(self:GetChecked())
  end)
  return box
end

local function CreateSlider(parent, label, x, y, minVal, maxVal, step, value, onChanged)
  local title = CreateLabel(parent, label .. ": " .. tostring(value), x, y, "GameFontHighlight")
  local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", x, y - 18)
  slider:SetMinMaxValues(minVal, maxVal)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)
  slider:SetWidth(240)
  slider:SetValue(value)

  local low = CreateLabel(parent, tostring(minVal), x, y - 40, "GameFontHighlightSmall")
  local high = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  high:SetPoint("TOPLEFT", slider, "TOPRIGHT", 0, -22)
  high:SetText(tostring(maxVal))

  slider.title = title
  slider.low = low
  slider.high = high

  slider:SetScript("OnValueChanged", function(self, newValue)
    if step < 1 then
      newValue = math.floor(newValue * 10 + 0.5) / 10
    else
      newValue = math.floor(newValue + 0.5)
    end
    self.title:SetText(label .. ": " .. tostring(newValue))
    onChanged(newValue)
  end)
  return slider
end


local function CreateNumberInput(parent, x, y, width, value, onCommit)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width or 50, 22)
  box:SetPoint("TOPLEFT", x, y)
  box:SetAutoFocus(false)
  box:SetNumeric(false)
  box:SetText(tostring(value or "0"))

  local function commit()
    local text = box:GetText() or ""
    local num = tonumber(text)
    if not num then
      num = 0
    end
    box:SetText(tostring(math.floor(num + 0.5)))
    onCommit(math.floor(num + 0.5))
  end

  box:SetScript("OnEnterPressed", function(self)
    commit()
    self:ClearFocus()
  end)
  box:SetScript("OnEditFocusLost", function()
    commit()
  end)
  return box
end

local function CreateButton(parent, text, x, y, width, height, onClick)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(width or 80, height or 22)
  btn:SetPoint("TOPLEFT", x, y)
  btn:SetText(text)
  btn:SetScript("OnClick", onClick)
  return btn
end

local function CreateEditBox(parent, label, x, y, width, text, onCommit, onChange)
  local title = CreateLabel(parent, label, x, y, "GameFontHighlightSmall")
  local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  edit:SetSize(width, 24)
  edit:SetPoint("TOPLEFT", x, y - 18)
  edit:SetAutoFocus(false)
  edit:SetText(text or "")
  edit:SetCursorPosition(0)

  local function commit()
    if onCommit then onCommit(edit:GetText()) end
  end

  edit:SetScript("OnEnterPressed", function(self)
    commit()
    self:ClearFocus()
  end)
  edit:SetScript("OnEditFocusLost", function()
    commit()
  end)
  edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput and onChange then onChange(self:GetText()) end
  end)
  edit:SetScript("OnEscapePressed", function(self)
    commit()
    self:ClearFocus()
  end)
  return edit, title
end

local function CreateSectionHeader(parent, text, x, y)
  local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", x, y)
  title:SetText(text)
  return title
end

local function GetSpellNameSafe(spellID)
  if not spellID then return nil end
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok and name and name ~= "" then return name end
  end
  if GetSpellInfo then
    local ok, name = pcall(GetSpellInfo, spellID)
    if ok and name and name ~= "" then return name end
  end
  return nil
end

local function CreateCanvasFrame(name)
  local frame = CreateFrame("Frame", name)
  frame:SetSize(900, 760)

  local scroll = CreateFrame("ScrollFrame", name .. "Scroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -12)
  scroll:SetPoint("BOTTOMRIGHT", -28, 12)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(840, 1100)
  scroll:SetScrollChild(content)

  frame.scroll = scroll
  frame.content = content
  return frame
end

local function CreateTargetColorDropDown(parent, x, y, currentMode, onSet)
  local title = CreateLabel(parent, "", x, y, "GameFontHighlight")
  local drop = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  drop:SetPoint("TOPLEFT", x - 14, y - 18)
  UIDropDownMenu_SetWidth(drop, 170)

  UIDropDownMenu_Initialize(drop, function(self, level)
    local function addOption(value, text)
      local info = UIDropDownMenu_CreateInfo()
      info.text = text
      info.func = function()
        onSet(value)
        UIDropDownMenu_SetText(drop, text)
      end
      UIDropDownMenu_AddButton(info, level)
    end
    addOption("none", "None")
    addOption("soft", "Soft")
    addOption("medium", "Mediu")
    addOption("subtle", "Foarte discret")
  end)

  local label = currentMode == "none" and "None" or currentMode == "soft" and "Soft" or currentMode == "subtle" and "Foarte discret" or "Mediu"
  UIDropDownMenu_SetText(drop, label)
  return drop, title
end


local function CreateSimulationScenarioDropDown(parent, x, y, currentMode, onSet)
  local title = CreateLabel(parent, "Scenario", x, y, "GameFontHighlight")
  local drop = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  drop:SetPoint("TOPLEFT", x - 14, y - 18)
  UIDropDownMenu_SetWidth(drop, 180)

  UIDropDownMenu_Initialize(drop, function(self, level)
    local function addOption(value, text)
      local info = UIDropDownMenu_CreateInfo()
      info.text = text
      info.func = function()
        onSet(value)
        UIDropDownMenu_SetText(drop, text)
      end
      UIDropDownMenu_AddButton(info, level)
    end
    addOption("arena3v3", "Arena 3v3")
    addOption("world", "World")
    addOption("dungeon", "Dungeon")
    addOption("raid10", "Raid 10")
    addOption("raid25", "Raid 25")
  end)

  local label = currentMode == "world" and "World" or currentMode == "dungeon" and "Dungeon" or currentMode == "raid10" and "Raid 10" or currentMode == "raid25" and "Raid 25" or "Arena 3v3"
  UIDropDownMenu_SetText(drop, label)
  return drop, title
end

function SFA:RefreshOptionsPanel()
  if not self.options then return end
  local db = self.db

  if self.options.generalTitle then
    self.options.generalTitle:SetText("Simple Frame Assistant")
  end
  if self.options.generalSub then
    self.options.generalSub:SetText("Use /sfa as a shortcut to this page. Move unlocked blocks with Shift + drag.")
  end

  if self.options.locked then self.options.locked:SetChecked(db.locked) end
  if self.options.hideHeaders then self.options.hideHeaders:SetChecked(db.hideHeaders) end
  if self.options.minimapEnabled then self.options.minimapEnabled:SetChecked(db.minimap and db.minimap.enabled ~= false) end
  if self.options.otherQuestIndicator then self.options.otherQuestIndicator:SetChecked(db.other and db.other.showQuestIndicator) end
  if self.options.otherTargetXMark then self.options.otherTargetXMark:SetChecked(db.other and db.other.showTargetXMark) end
  if self.options.simulationEnabled then self.options.simulationEnabled:SetChecked(self:IsSimulationEnabled()) end

local simMode = db.simulation and db.simulation.scenario or "arena3v3"
local function syncSimRow(boxRef, xRef, yRef, mode)
  local active = self:IsSimulationEnabled() and simMode == mode
  if boxRef then boxRef:SetChecked(active) end
  if xRef or yRef then
    local p = self:GetFriendlyScenarioPoint(mode)
    if xRef and p then xRef:SetText(tostring(p.x or 0)) end
    if yRef and p then yRef:SetText(tostring(p.y or 0)) end
  end
end
syncSimRow(self.options.simRowWorld, self.options.simRowWorldX, self.options.simRowWorldY, "world")
syncSimRow(self.options.simRowArena, self.options.simRowArenaX, self.options.simRowArenaY, "arena3v3")
syncSimRow(self.options.simRowDungeon, self.options.simRowDungeonX, self.options.simRowDungeonY, "dungeon")
syncSimRow(self.options.simRowRaid10, self.options.simRowRaid10X, self.options.simRowRaid10Y, "raid10")
syncSimRow(self.options.simRowRaid25, self.options.simRowRaid25X, self.options.simRowRaid25Y, "raid25")

  if self.options.friendlyEnabled then self.options.friendlyEnabled:SetChecked(db.friendly.enabled) end
  if self.options.friendlyDebuffs then self.options.friendlyDebuffs:SetChecked(db.friendly.showDebuffs) end
  if self.options.enemyEnabled then self.options.enemyEnabled:SetChecked(db.enemy.enabled) end
  if self.options.enemyDebuffs then self.options.enemyDebuffs:SetChecked(db.enemy.showDebuffs) end
  if self.options.enemyHealer then self.options.enemyHealer:SetChecked(db.enemy.healerMarker) end
  if self.options.enemyClass then self.options.enemyClass:SetChecked(db.enemy.classColor) end
  if self.options.friendlyClass then self.options.friendlyClass:SetChecked(db.friendly.classColor) end
  if self.options.friendlyAutoShrink then self.options.friendlyAutoShrink:SetChecked(db.friendly.autoShrinkLargeGroups) end
  if self.options.friendlyMyHotsOnly then self.options.friendlyMyHotsOnly:SetChecked(db.friendly.showMyHotsOnly) end
  if self.options.friendlyHideBlizzardRaid then self.options.friendlyHideBlizzardRaid:SetChecked(db.friendly.hideBlizzardRaidFrames) end

  local mode = db.enemy.targetColor or "medium"
  local text = mode == "none" and "None" or mode == "soft" and "Soft" or mode == "subtle" and "Foarte discret" or "Mediu"
  if self.options.targetColorDropDown then
    UIDropDownMenu_SetText(self.options.targetColorDropDown, text)
  end
end

function SFA:BuildGroupSection(parent, group, left, top)
  local db = self.db[group]
  local title = CreateSectionHeader(parent, group == "friendly" and "Friendly Frames" or "Enemy Frames", left, top)

  local y = top - 34
  local enabled = CreateCheckbox(parent, "Enable", left, y, db.enabled, function(val)
    db.enabled = val
    self:RefreshGroup(group)
  end)
  y = y - 30

  local debuffs = CreateCheckbox(parent, group == "friendly" and "Show buff/debuff icons" or "Show debuff icons", left, y, db.showDebuffs, function(val)
    db.showDebuffs = val
    self:RefreshGroup("friendly")
    self:RefreshGroup("enemy")
    self:QueueRefresh()
  end)
  y = y - 42

  local widthSlider = CreateSlider(parent, "Width", left, y, 120, 280, 1, db.width, function(val)
    db.width = val
    if not InCombatLockdown() then self:ApplyLayout(group) else self.pendingLayout = true end
  end)
  y = y - 72

  local heightSlider = CreateSlider(parent, "Height", left, y, 24, 60, 1, db.height, function(val)
    db.height = val
    if not InCombatLockdown() then self:ApplyLayout(group) else self.pendingLayout = true end
  end)
  y = y - 72

  local scaleSlider = CreateSlider(parent, "Scale", left, y, 0.8, 1.4, 0.1, db.scale, function(val)
    db.scale = val
    if not InCombatLockdown() then self:ApplyLayout(group) else self.pendingLayout = true end
  end)
  y = y - 72

  local spacingSlider = CreateSlider(parent, "Spacing", left, y, 0, 16, 1, db.spacing, function(val)
    db.spacing = val
    if not InCombatLockdown() then self:ApplyLayout(group) else self.pendingLayout = true end
  end)
  y = y - 82

  local leftClick = CreateEditBox(parent, "Left click macro", left, y, 360, db.clicks.LeftButton, function(text)
    db.clicks.LeftButton = text
    self:RefreshGroup(group)
  end, function(text)
    db.clicks.LeftButton = text
  end)
  y = y - 62

  local rightClick = CreateEditBox(parent, "Right click macro", left, y, 360, db.clicks.RightButton, function(text)
    db.clicks.RightButton = text
    self:RefreshGroup(group)
  end, function(text)
    db.clicks.RightButton = text
  end)
  y = y - 62

  local middleClick = CreateEditBox(parent, "Middle click macro", left, y, 360, db.clicks.MiddleButton, function(text)
    db.clicks.MiddleButton = text
    self:RefreshGroup(group)
  end, function(text)
    db.clicks.MiddleButton = text
  end)

  return {
    title = title,
    enabled = enabled,
    debuffs = debuffs,
    widthSlider = widthSlider,
    heightSlider = heightSlider,
    scaleSlider = scaleSlider,
    spacingSlider = spacingSlider,
    leftClick = leftClick,
    rightClick = rightClick,
    middleClick = middleClick,
  }
end

function SFA:RefreshBlacklistUI()
  if not self.options or not self.options.blacklistRows then return end
  local ids = {}
  for spellID, enabled in pairs(self.db.buffBlacklist or {}) do
    if enabled then ids[#ids + 1] = tonumber(spellID) end
  end
  table.sort(ids)

  for i, row in ipairs(self.options.blacklistRows) do
    local spellID = ids[i]
    if spellID then
      local spellName = GetSpellNameSafe(spellID)
      if spellName and spellName ~= "" then
        row.label:SetText(string.format("%d (%s)", spellID, spellName))
      else
        row.label:SetText(tostring(spellID))
      end
      row.remove.spellID = spellID
      row:Show()
    else
      row.label:SetText("")
      row.remove.spellID = nil
      row:Hide()
    end
  end

  if self.options.blacklistEmpty then
    self.options.blacklistEmpty:SetShown(#ids == 0)
  end
end

function SFA:CreateOptionsPanel()
  local root = CreateCanvasFrame(addonName .. "OptionsRoot")
  root.name = "Simple Frame Assistant"
  local rootContent = root.content

  root.title = rootContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  root.title:SetPoint("TOPLEFT", 18, -10)
  root.sub = rootContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  root.sub:SetPoint("TOPLEFT", root.title, "BOTTOMLEFT", 0, -6)
  root.sub:SetJustifyH("LEFT")

  local generalHeader = CreateSectionHeader(rootContent, "General", 18, -68)
  local locked = CreateCheckbox(rootContent, "Lock frame blocks (move with Shift + drag when unlocked)", 24, -104, self.db.locked, function(val)
    self.db.locked = val
  end)
  local hideHeaders = CreateCheckbox(rootContent, "Hide header text", 24, -136, self.db.hideHeaders, function(val)
    self.db.hideHeaders = val
    self:RefreshGroup("friendly")
    self:RefreshGroup("enemy")
  end)
  local minimapEnabled = CreateCheckbox(rootContent, "Minimap button", 24, -168, self.db.minimap and self.db.minimap.enabled ~= false, function(val)
    self.db.minimap = self.db.minimap or {}
    self.db.minimap.enabled = val
    if self.UpdateMinimapButtonPosition then self:UpdateMinimapButtonPosition() end
  end)

  local generalInfo = rootContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  generalInfo:SetPoint("TOPLEFT", 24, -204)
  generalInfo:SetWidth(760)
  generalInfo:SetJustifyH("LEFT")
  generalInfo:SetText("Use /sfa to open this page quickly. Move unlocked Friendly or Enemy blocks with Shift + drag. Positions are remembered separately for World, Arena, Party/Dungeon, Raid 10, and Raid 25. Macro text can use [@unit] and will be expanded automatically.")

  local blacklistTop = -282
  local blacklistHeader = CreateSectionHeader(rootContent, "Aura Blacklist", 18, blacklistTop)
  local blacklistHelp = rootContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  blacklistHelp:SetPoint("TOPLEFT", 24, blacklistTop - 28)
  blacklistHelp:SetWidth(780)
  blacklistHelp:SetJustifyH("LEFT")
  blacklistHelp:SetText("Add a buff or debuff spell ID to hide it from SFA. Tip: Shift + Left Click an aura icon to add it instantly.")

  local blacklistInput = CreateFrame("EditBox", nil, rootContent, "InputBoxTemplate")
  blacklistInput:SetSize(120, 24)
  blacklistInput:SetPoint("TOPLEFT", 24, blacklistTop - 62)
  blacklistInput:SetAutoFocus(false)
  blacklistInput:SetNumeric(true)

  local blacklistAdd = CreateButton(rootContent, "Add ID", 154, blacklistTop - 60, 70, 24, function()
    local text = blacklistInput:GetText()
    local spellID = tonumber(text)
    if spellID then
      SFA:AddBuffToBlacklist(spellID)
      blacklistInput:SetText("")
      blacklistInput:ClearFocus()
    else
      SFA.Print("Enter a numeric spell ID.")
    end
  end)
  blacklistInput:SetScript("OnEnterPressed", function(self)
    blacklistAdd:Click()
  end)

  local blacklistEmpty = rootContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  blacklistEmpty:SetPoint("TOPLEFT", 24, blacklistTop - 96)
  blacklistEmpty:SetText("No blacklisted aura IDs yet.")

  local blacklistRows = {}
  for i = 1, 16 do
    local row = CreateFrame("Frame", nil, rootContent)
    row:SetSize(600, 20)
    row:SetPoint("TOPLEFT", 24, blacklistTop - 96 - ((i - 1) * 22))

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetWidth(460)
    row.label:SetJustifyH("LEFT")

    row.remove = CreateButton(row, "Remove", 470, 10, 80, 18, function(btn)
      if btn.spellID then
        SFA:RemoveBuffFromBlacklist(btn.spellID)
      end
    end)
    row.remove:SetPoint("LEFT", row, "LEFT", 470, 0)

    row:Hide()
    blacklistRows[#blacklistRows + 1] = row
  end
  rootContent:SetHeight(780)

  local otherPanel = CreateCanvasFrame(addonName .. "OptionsOther")
  local otherContent = otherPanel.content
  local otherTitle = otherContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  otherTitle:SetPoint("TOPLEFT", 18, -10)
  otherTitle:SetText("Simple Frame Assistant")
  local otherSub = otherContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  otherSub:SetPoint("TOPLEFT", otherTitle, "BOTTOMLEFT", 0, -6)
  otherSub:SetText("Other options.")
  local otherHeader = CreateSectionHeader(otherContent, "Other", 18, -68)
  local otherQuestIndicator = CreateCheckbox(otherContent, "Show quest objective ! on nameplates", 24, -104, self.db.other and self.db.other.showQuestIndicator, function(val)
    self.db.other.showQuestIndicator = val
    self:RefreshQuestIndicators()
  end)
  local otherTargetXMark = CreateCheckbox(otherContent, "Show X mark on enemy target frame", 24, -176, self.db.other and self.db.other.showTargetXMark, function(val)
    self.db.other.showTargetXMark = val
    self:RefreshGroup("enemy")
  end)
  local otherHelp = otherContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  otherHelp:SetPoint("TOPLEFT", 24, -212)
  otherHelp:SetWidth(760)
  otherHelp:SetJustifyH("LEFT")
  otherHelp:SetText("Shows a yellow ! on an NPC nameplate when the NPC is related to an active quest objective.")

local simulationPanel = CreateCanvasFrame(addonName .. "OptionsSimulation")
local simulationContent = simulationPanel.content
local simulationTitle = simulationContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
simulationTitle:SetPoint("TOPLEFT", 18, -10)
simulationTitle:SetText("Simple Frame Assistant")
local simulationSub = simulationContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
simulationSub:SetPoint("TOPLEFT", simulationTitle, "BOTTOMLEFT", 0, -6)
simulationSub:SetText("Simulation and testing. Test mode resets to OFF after reload/relog.")

local simulationHeader = CreateSectionHeader(simulationContent, "Simulation / Testing", 18, -68)
local simulationEnabled = CreateCheckbox(simulationContent, "Enable test mode", 24, -104, self:IsSimulationEnabled(), function(val)
  self:SetSimulationEnabled(val)
  self:RefreshOptionsPanel()
end)

local simulationTableTitle = CreateLabel(simulationContent, "Friendly simulation layouts", 24, -156, "GameFontHighlight")
local simulationTableSub = simulationContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
simulationTableSub:SetPoint("TOPLEFT", 24, -176)
simulationTableSub:SetWidth(780)
simulationTableSub:SetJustifyH("LEFT")
simulationTableSub:SetText("Check one row to preview that Friendly layout. Edit X and Y directly to set the stored position for the matching real layout.")

local simulationHeaderMode = CreateLabel(simulationContent, "Mode", 24, -210, "GameFontHighlightSmall")
local simulationHeaderShow = CreateLabel(simulationContent, "Show", 210, -210, "GameFontHighlightSmall")
local simulationHeaderX = CreateLabel(simulationContent, "X", 280, -210, "GameFontHighlightSmall")
local simulationHeaderY = CreateLabel(simulationContent, "Y", 360, -210, "GameFontHighlightSmall")

local function simulationScenarioRow(y, mode, label)
  local key = self:GetFriendlyScenarioKeyForMode(mode)
  local point = self:GetFriendlyScenarioPoint(mode)

  local name = CreateLabel(simulationContent, label, 24, y, "GameFontHighlightSmall")
  local enabled = (self:IsSimulationEnabled() and self:GetSimulationScenario() == mode)

  local box = CreateCheckbox(simulationContent, "", 218, y + 2, enabled, function(val)
    if val then
      self.db.simulation.scenario = mode
      self.session = self.session or {}
      self.session.simulationProfile = nil
      self:SetSimulationEnabled(true)
    else
      if self:IsSimulationEnabled() and self:GetSimulationScenario() == mode then
        self:SetSimulationEnabled(false)
      end
    end
    self:RefreshOptionsPanel()
  end)

  local xBox = CreateNumberInput(simulationContent, 280, y + 4, 56, point and point.x or 0, function(val)
    local p = self:GetFriendlyScenarioPoint(mode)
    if p then
      p.x = val
      if self:IsSimulationEnabled() and self:GetSimulationScenario() == mode and not InCombatLockdown() then
        self:ApplyLayout("friendly")
        self:RefreshGroup("friendly")
      end
      if self.RefreshSimulationPositionInputs then self:RefreshSimulationPositionInputs() end
    end
  end)

  local yBox = CreateNumberInput(simulationContent, 360, y + 4, 56, point and point.y or 0, function(val)
    local p = self:GetFriendlyScenarioPoint(mode)
    if p then
      p.y = val
      if self:IsSimulationEnabled() and self:GetSimulationScenario() == mode and not InCombatLockdown() then
        self:ApplyLayout("friendly")
        self:RefreshGroup("friendly")
      end
      if self.RefreshSimulationPositionInputs then self:RefreshSimulationPositionInputs() end
    end
  end)

  return name, box, xBox, yBox
end

local simRowWorldLabel, simRowWorld, simRowWorldX, simRowWorldY = simulationScenarioRow(-236, "world", "World")
local simRowArenaLabel, simRowArena, simRowArenaX, simRowArenaY = simulationScenarioRow(-268, "arena3v3", "Arena 3v3")
local simRowDungeonLabel, simRowDungeon, simRowDungeonX, simRowDungeonY = simulationScenarioRow(-300, "dungeon", "Dungeon / Party")
local simRowRaid10Label, simRowRaid10, simRowRaid10X, simRowRaid10Y = simulationScenarioRow(-332, "raid10", "Raid 10")
local simRowRaid25Label, simRowRaid25, simRowRaid25X, simRowRaid25Y = simulationScenarioRow(-364, "raid25", "Raid 25")

local simulationHelp = simulationContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
simulationHelp:SetPoint("TOPLEFT", 24, -408)
simulationHelp:SetWidth(780)
simulationHelp:SetJustifyH("LEFT")
simulationHelp:SetText("Simulation mirrors the real layouts: World, Arena 3v3, Dungeon / Party, Raid 10, and Raid 25. Friendly positions are edited directly here and used by the matching real context. Enemy stays target-only outside arena. Move unlocked blocks with Shift + drag.")
simulationContent:SetHeight(500)

local friendlyPanel = CreateCanvasFrame(addonName .. "OptionsFriendly")
  local friendlyContent = friendlyPanel.content
  local friendlyTitle = friendlyContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  friendlyTitle:SetPoint("TOPLEFT", 18, -10)
  friendlyTitle:SetText("Simple Frame Assistant")
  local friendlySub = friendlyContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  friendlySub:SetPoint("TOPLEFT", friendlyTitle, "BOTTOMLEFT", 0, -6)
  friendlySub:SetText("Friendly frame options.")
  local friendlySection = self:BuildGroupSection(friendlyContent, "friendly", 24, -68)
  local friendlyClass = CreateCheckbox(friendlyContent, "Class color health bar", 24, -652, self.db.friendly.classColor, function(val)
    self.db.friendly.classColor = val
    self:RefreshGroup("friendly")
    self:RefreshGroup("enemy")
    self:QueueRefresh()
  end)
local friendlyAutoShrink = CreateCheckbox(friendlyContent, "Auto shrink in large groups", 24, -688, self.db.friendly.autoShrinkLargeGroups, function(val)
  self.db.friendly.autoShrinkLargeGroups = val
  self:ApplyLayout("friendly")
  self:QueueRefresh()
end)
local friendlyMyHotsOnly = CreateCheckbox(friendlyContent, "Show my HoTs only", 24, -760, self.db.friendly.showMyHotsOnly, function(val)
  self.db.friendly.showMyHotsOnly = val
  self:RefreshGroup("friendly")
end)
local friendlyHideBlizzardRaid = CreateCheckbox(friendlyContent, "Hide Blizzard raid frames", 24, -796, self.db.friendly.hideBlizzardRaidFrames, function(val)
  self.db.friendly.hideBlizzardRaidFrames = val
  if not InCombatLockdown() then
    self:ApplyBlizzardRaidFramesVisibility()
  else
    self.pendingLayout = true
  end
end)
local friendlyLargeScale = CreateSlider(friendlyContent, "Large group scale", 24, -842, 0.50, 1.00, 0.05, self.db.friendly.largeGroupScale or 0.85, function(val)
  self.db.friendly.largeGroupScale = val
  self:ApplyLayout("friendly")
  self:QueueRefresh()
end)
  friendlyContent:SetHeight(1040)

  local enemyPanel = CreateCanvasFrame(addonName .. "OptionsEnemy")
  local enemyContent = enemyPanel.content
  local enemyTitle = enemyContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  enemyTitle:SetPoint("TOPLEFT", 18, -10)
  enemyTitle:SetText("Simple Frame Assistant")
  local enemySub = enemyContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  enemySub:SetPoint("TOPLEFT", enemyTitle, "BOTTOMLEFT", 0, -6)
  enemySub:SetText("Enemy frame options.")
  local enemySection = self:BuildGroupSection(enemyContent, "enemy", 24, -68)
  local enemyClass = CreateCheckbox(enemyContent, "Class color health bar", 24, -688, self.db.enemy.classColor, function(val)
    self.db.enemy.classColor = val
    self:RefreshGroup("friendly")
    self:RefreshGroup("enemy")
    self:QueueRefresh()
  end)
    enemyContent:SetHeight(1060)

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory and Settings.RegisterCanvasLayoutSubcategory then
    local category = Settings.RegisterCanvasLayoutCategory(root, "Simple Frame Assistant")
    Settings.RegisterAddOnCategory(category)
    self.settingsCategory = category
    self.settingsRootName = "Simple Frame Assistant"

    local generalSubcategory = Settings.RegisterCanvasLayoutSubcategory(category, root, "General")
    Settings.RegisterCanvasLayoutSubcategory(category, friendlyPanel, "Friendly Frame")
    Settings.RegisterCanvasLayoutSubcategory(category, enemyPanel, "Enemy Frame")
    Settings.RegisterCanvasLayoutSubcategory(category, otherPanel, "Other")
    Settings.RegisterCanvasLayoutSubcategory(category, simulationPanel, "Simulation")
    self.settingsGeneralSubcategory = generalSubcategory
  end

  self.options = {
    generalTitle = root.title,
    generalSub = root.sub,
    locked = locked,
    hideHeaders = hideHeaders,
    minimapEnabled = minimapEnabled,
    otherQuestIndicator = otherQuestIndicator,
    otherTargetXMark = otherTargetXMark,
    simulationEnabled = simulationEnabled,
    simRowWorld = simRowWorld,
    simRowWorldX = simRowWorldX,
    simRowWorldY = simRowWorldY,
    simRowArena = simRowArena,
    simRowArenaX = simRowArenaX,
    simRowArenaY = simRowArenaY,
    simRowDungeon = simRowDungeon,
    simRowDungeonX = simRowDungeonX,
    simRowDungeonY = simRowDungeonY,
    simRowRaid10 = simRowRaid10,
    simRowRaid10X = simRowRaid10X,
    simRowRaid10Y = simRowRaid10Y,
    simRowRaid25 = simRowRaid25,
    simRowRaid25X = simRowRaid25X,
    simRowRaid25Y = simRowRaid25Y,
    blacklistInput = blacklistInput,
    blacklistRows = blacklistRows,
    blacklistEmpty = blacklistEmpty,
    friendlyEnabled = friendlySection.enabled,
    friendlyDebuffs = friendlySection.debuffs,
    enemyEnabled = enemySection.enabled,
    enemyDebuffs = enemySection.debuffs,
    enemyClass = enemyClass,
    friendlyClass = friendlyClass,
    friendlyAutoShrink = friendlyAutoShrink,
    friendlyMyHotsOnly = friendlyMyHotsOnly,
    friendlyHideBlizzardRaid = friendlyHideBlizzardRaid,
    targetColorDropDown = targetDropDown,
  }

  self:RefreshOptionsPanel()
  self:RefreshBlacklistUI()
end

function SFA:OpenOptions()
  self:RefreshOptionsPanel()
  if Settings and Settings.OpenToCategory and self.settingsCategory then
    local ok = pcall(function()
      if self.settingsCategory.GetID then
        Settings.OpenToCategory(self.settingsCategory:GetID())
      else
        Settings.OpenToCategory("Simple Frame Assistant")
      end
    end)
    if ok then return end
  end
  if InterfaceOptionsFrame_OpenToCategory then
    pcall(InterfaceOptionsFrame_OpenToCategory, "Simple Frame Assistant")
    pcall(InterfaceOptionsFrame_OpenToCategory, "Simple Frame Assistant")
  end
end

function SFA:ToggleOptions()
  self:OpenOptions()
end

function SFA:RegisterSlash()
  SLASH_SIMPLEFRAMEASSISTANT1 = "/sfa"
  SlashCmdList.SIMPLEFRAMEASSISTANT = function()
    SFA:OpenOptions()
  end
end




local function SFA_CreateStandardRoleOptions(parent, anchor, groupKey)
    local healer = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    healer:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    healer.text:SetText("Show healer icon")
    healer:SetChecked(SFA.db[groupKey].showHealerIcon ~= false)
    healer:SetScript("OnClick", function(self)
        SFA.db[groupKey].showHealerIcon = self:GetChecked()
        SFA:RefreshGroup(groupKey)
    end)

    local tank = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    tank:SetPoint("TOPLEFT", healer, "BOTTOMLEFT", 0, -6)
    tank.text:SetText("Show tank icon")
    tank:SetChecked(SFA.db[groupKey].showTankIcon ~= false)
    tank:SetScript("OnClick", function(self)
        SFA.db[groupKey].showTankIcon = self:GetChecked()
        SFA:RefreshGroup(groupKey)
    end)

    return tank
end

-- Added Other option: Show enemy spec icon above frame
