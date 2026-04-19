local addonName, SFA = ...
SFA = _G[addonName] or SFA

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitName = UnitName
local UnitClass = UnitClass
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitAffectingCombat = UnitAffectingCombat
local UnitCanAssist = UnitCanAssist
local UnitCanAttack = UnitCanAttack
local UnitIsEnemy = UnitIsEnemy
local UnitIsUnit = UnitIsUnit
local IsActiveBattlefieldArena = IsActiveBattlefieldArena
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local InCombatLockdown = InCombatLockdown
local GetArenaOpponentSpec = GetArenaOpponentSpec
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local C_NamePlate = C_NamePlate
local C_QuestLog = C_QuestLog
local IsShiftKeyDown = IsShiftKeyDown

SFA.frames = { friendly = {}, enemy = {} }
SFA.headers = {}
SFA.pendingRefresh = false
SFA.pendingLayout = false
SFA.pendingVisibility = false
SFA.healerSpecs = {
  [105] = true,
  [256] = true,
  [257] = true,
  [264] = true,
  [270] = true,
  [65] = true,
  [1468] = true,
}

SFA.tankSpecs = {
  [250] = true,
  [581] = true,
  [104] = true,
  [268] = true,
  [66] = true,
  [73] = true,
}


local function SpellTextureSafe(spellID, fallback)
  if C_Spell and C_Spell.GetSpellTexture then
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    if ok and tex then return tex end
  end
  if GetSpellTexture then
    local ok, tex = pcall(GetSpellTexture, spellID)
    if ok and tex then return tex end
  end
  return fallback or "Interface\\Icons\\INV_Misc_QuestionMark"
end


SFA.simulationClassPools = {
  healers = { "DRUID", "PRIEST", "SHAMAN", "MONK", "PALADIN", "EVOKER" },
  dpsTanks = { "ROGUE", "MAGE", "WARLOCK", "WARRIOR", "DEMONHUNTER", "HUNTER", "DEATHKNIGHT", "MONK", "DRUID", "PALADIN", "EVOKER", "WARRIOR" },
}

SFA.simulationSpellSamples = {
  buffs = {
    DRUID = {774, 33763}, PRIEST = {139, 17}, SHAMAN = {61295, 974}, MONK = {119611, 124682}, PALADIN = {53563, 1022}, EVOKER = {355941, 364343},
    WARRIOR = {6673}, MAGE = {1459}, WARLOCK = {5697}, ROGUE = {315496}, HUNTER = {186265}, DEATHKNIGHT = {195181}, DEMONHUNTER = {203981},
  },
  debuffs = {
    DRUID = {1079, 155722}, PRIEST = {589, 15487}, SHAMAN = {188389, 196840}, MONK = {123725, 116095}, PALADIN = {853, 62124}, EVOKER = {357209, 370898},
    WARRIOR = {1715, 385060}, MAGE = {12654, 122}, WARLOCK = {980, 30108}, ROGUE = {703, 1943}, HUNTER = {120679, 162487}, DEATHKNIGHT = {55095, 191587}, DEMONHUNTER = {179057, 198813},
  },
}

local function SFA_SimPick(list, index, salt)
  if not list or #list == 0 then return nil end
  local i = ((index - 1 + (salt or 0)) % #list) + 1
  return list[i]
end

local function SFA_SimBuildEntry(name, classFile, health, healer, target, tank)
  local buffs = (SFA.simulationSpellSamples.buffs[classFile] or {})
  local debuffs = (SFA.simulationSpellSamples.debuffs[classFile] or {})
  local out = {
    name = name,
    class = classFile,
    health = health or 0.8,
    healer = healer and true or false,
    tank = tank and true or false,
    target = target and true or false,
    buffSpellIDs = {},
    debuffSpellIDs = {},
    value = "",
  }
  for i=1, math.min(2, #buffs) do out.buffSpellIDs[i] = buffs[i] end
  for i=1, math.min(2, #debuffs) do out.debuffSpellIDs[i] = debuffs[i] end
  return out
end

function SFA:BuildSimulationProfile(scenario)
  scenario = scenario or "arena3v3"
  local profile = { friendly = {}, enemy = {} }

  if scenario == "arena3v3" then
    local fh = SFA_SimPick(self.simulationClassPools.healers, 1, math.random(0, 5)) or "PRIEST"
    local eh = SFA_SimPick(self.simulationClassPools.healers, 3, math.random(0, 5)) or "MONK"
    local ed2 = SFA_SimPick(self.simulationClassPools.dpsTanks, 5, math.random(0, 11)) or "WARRIOR"
    profile.friendly = {
      SFA_SimBuildEntry("You", "DRUID", 0.82, false, false),
      SFA_SimBuildEntry("Friendly Healer", fh, 0.64, true, false),
      SFA_SimBuildEntry("Friendly Tank", "WARRIOR", 0.77, false, false, true),
    }
    profile.enemy = {
      SFA_SimBuildEntry("Enemy Healer", eh, 0.71, true, false),
      SFA_SimBuildEntry("Enemy Tank", "WARRIOR", 0.59, false, true, true),
      SFA_SimBuildEntry("Enemy DPS", ed2, 0.88, false, false),
    }
  elseif scenario == "dungeon" then
    local healer = SFA_SimPick(self.simulationClassPools.healers, 2, math.random(0, 5)) or "SHAMAN"
    local tank = "WARRIOR"
    local d1 = SFA_SimPick(self.simulationClassPools.dpsTanks, 1, math.random(0, 11)) or "MAGE"
    local d2 = SFA_SimPick(self.simulationClassPools.dpsTanks, 3, math.random(0, 11)) or "ROGUE"
    local d3 = SFA_SimPick(self.simulationClassPools.dpsTanks, 5, math.random(0, 11)) or "WARLOCK"
    profile.friendly = {
      SFA_SimBuildEntry("You", "DRUID", 0.91, false, false),
      SFA_SimBuildEntry("Tank", tank, 0.48, false, false, true),
      SFA_SimBuildEntry("Healer", healer, 0.79, true, false),
      SFA_SimBuildEntry("DPS 1", d1, 0.95, false, false),
      SFA_SimBuildEntry("DPS 2", d2, 0.67, false, false),
    }
    profile.enemy = {
      SFA_SimBuildEntry("Dungeon Enemy", d3, 0.61, false, true)
    }
  elseif scenario == "raid10" or scenario == "raid25" then
    local total = scenario == "raid25" and 25 or 10
    for i = 1, total do
      local classFile
      local healer = false
      local tank = false

      if i == 1 then
        classFile = "DRUID"
      elseif (i % 5) == 2 then
        classFile = SFA_SimPick(self.simulationClassPools.healers, i, i) or "PRIEST"
        healer = true
      elseif (i % 5) == 3 then
        classFile = "WARRIOR"
        tank = true
      else
        classFile = SFA_SimPick(self.simulationClassPools.dpsTanks, i, i) or "MAGE"
      end

      local hp = 0.55 + ((i % 5) * 0.08)
      local name = i == 1 and "You" or ("Raid " .. i)
      profile.friendly[#profile.friendly + 1] = SFA_SimBuildEntry(name, classFile, hp, healer, false, tank)
    end

    profile.enemy = {
      SFA_SimBuildEntry("Raid Target", "WARRIOR", 0.62, false, true, true),
    }
  else
    local enemy = SFA_SimPick(self.simulationClassPools.dpsTanks, 6, math.random(0, 11)) or "ROGUE"
    profile.friendly = {
      SFA_SimBuildEntry("You", "DRUID", 0.93, false, false)
    }
    profile.enemy = {
      SFA_SimBuildEntry("World Target", enemy, 0.44, false, true)
    }
  end

  return profile
end

function SFA:IsSimulationEnabled()
  return self.session and self.session.simulationEnabled == true
end

function SFA:GetSimulationScenario()
  return (self.db and self.db.simulation and self.db.simulation.scenario) or "arena3v3"
end

function SFA:GetSimulationProfile()
  if not self.session then self.session = {} end
  if not self.session.simulationProfile then
    self.session.simulationProfile = self:BuildSimulationProfile(self:GetSimulationScenario())
  end
  return self.session.simulationProfile
end

function SFA:SetSimulationEnabled(enabled)
  self.session = self.session or {}
  self.session.simulationEnabled = enabled and true or false
  if self.db and self.db.simulation then
    self.db.simulation.enabled = false
  end
  if enabled then
    self.session.simulationProfile = self:BuildSimulationProfile(self:GetSimulationScenario())
  else
    self.session.simulationProfile = nil
  end
  if not InCombatLockdown() then
    self:RefreshGroup("friendly")
    self:RefreshGroup("enemy")
    if self.RefreshOptionsPanel then self:RefreshOptionsPanel() end
  else
    self:QueueRefresh(0.05)
  end
end


function SFA:IsSimulationUnit(unit)
  return type(unit) == "string" and unit:match("^sfa_sim_")
end

function SFA:GetSimulationData(unit)
  if not self:IsSimulationUnit(unit) then return nil end
  local group, index = unit:match("^sfa_sim_(friendly|enemy)_(%d+)$")
  index = tonumber(index)
  if not group or not index then return nil end
  local profile = self:GetSimulationProfile()
  return profile and profile[group] and profile[group][index] or nil
end


local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff7cc6ffSFA:|r " .. tostring(msg))
end
SFA.Print = Print

function SFA:IsQuestUnit(unit)
  if not unit or not UnitExists(unit) or not C_QuestLog then
    return false
  end

  if C_QuestLog.UnitIsRelatedToActiveQuest then
    local ok, result = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
    if ok and result then
      return true
    end
  end

  return false
end



function SFA:ShouldShowComboCircle()
  local _, classTag = UnitClass("player")
  if classTag ~= "DRUID" then
    return false
  end
  local comboType = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
  local comboPoints = UnitPower("player", comboType)
  return comboPoints and comboPoints >= 5
end

function SFA:GetNameplateAnchor(frame)
  if not frame then return nil end
  if frame.UnitFrame and frame.UnitFrame.name then
    return frame.UnitFrame.name
  end
  if frame.UnitFrame and frame.UnitFrame.nameText then
    return frame.UnitFrame.nameText
  end
  return frame.UnitFrame or frame
end

function SFA:EnsureQuestIcon(frame)
  if not frame then return nil end
  if frame.SFAQuestIcon then
    return frame.SFAQuestIcon
  end

  local icon = frame:CreateFontString(nil, "OVERLAY")
  icon:SetFont("Fonts\\FRIZQT__.TTF", 18, "THICKOUTLINE")
  icon:SetText("!")
  icon:SetTextColor(1, 0.82, 0, 1)
  icon:SetShadowOffset(1, -1)
  icon:SetShadowColor(0, 0, 0, 1)

  local anchor = self:GetNameplateAnchor(frame)
  if anchor then
    icon:SetPoint("RIGHT", anchor, "LEFT", -18, 0)
  else
    icon:SetPoint("CENTER", frame, "TOP", 0, -10)
  end

  icon:Hide()
  frame.SFAQuestIcon = icon
  return icon
end

function SFA:UpdateNameplateQuestIndicator(unit)
  if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
  local frame = C_NamePlate.GetNamePlateForUnit(unit, true) or C_NamePlate.GetNamePlateForUnit(unit)
  if not frame then return end

  local icon = self:EnsureQuestIcon(frame)
  if not icon then return end

  local enabled = self.db and self.db.other and self.db.other.showQuestIndicator
  if enabled and self:IsQuestUnit(unit) then
    local anchor = self:GetNameplateAnchor(frame)
    if anchor then
      icon:ClearAllPoints()
      icon:SetPoint("RIGHT", anchor, "LEFT", -18, 0)
    end
    icon:Show()
  else
    icon:Hide()
  end
end

function SFA:RefreshQuestIndicators()
  if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
  local plates = C_NamePlate.GetNamePlates(false) or {}
  for _, frame in ipairs(plates) do
    local unit = frame.namePlateUnitToken or (frame.UnitFrame and frame.UnitFrame.unit)
    if unit then
      self:UpdateNameplateQuestIndicator(unit)
    elseif frame.SFAQuestIcon then
      frame.SFAQuestIcon:Hide()
    end
  end
end







function SFA:GetFriendlyScenarioKeyForMode(mode)
  mode = mode or "world"
  if mode == "arena3v3" then
    return "arena"
  elseif mode == "raid10" then
    return "raid10"
  elseif mode == "raid25" then
    return "raid25"
  elseif mode == "dungeon" then
    return "dungeon"
  else
    return "world"
  end
end


function SFA:GetFriendlyContextKeyForSimulationScenario()
  return self:GetFriendlyScenarioKeyForMode(self:GetSimulationScenario())
end

function SFA:GetFriendlyScenarioPoint(mode)
  local cfg = self.db and self.db.friendly
  if not cfg then return nil end
  cfg.scenarioPoints = cfg.scenarioPoints or {}
  local key = self:GetFriendlyScenarioKeyForMode(mode)
  if type(cfg.scenarioPoints[key]) ~= "table" then
    local base = cfg.point or { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = -260, y = -40 }
    cfg.scenarioPoints[key] = {
      anchor = base.anchor or "CENTER",
      relativeTo = "UIParent",
      relativePoint = base.relativePoint or "CENTER",
      x = base.x or 0,
      y = base.y or 0,
    }
  end
  return cfg.scenarioPoints[key], key
end

function SFA:SetFriendlyScenarioPoint(mode, x, y, anchor, relativePoint)
  local point, key = self:GetFriendlyScenarioPoint(mode)
  if not point then return false end
  point.anchor = anchor or point.anchor or "CENTER"
  point.relativeTo = "UIParent"
  point.relativePoint = relativePoint or point.relativePoint or "CENTER"
  point.x = tonumber(x) or 0
  point.y = tonumber(y) or 0
  return true
end

function SFA:GetFriendlyContextKeyForSimulationScenario()
  local scenario = self:GetSimulationScenario()
  if scenario == "raid10" then
    return "raid10"
  elseif scenario == "raid25" then
    return "raid25"
  else
    return "smallGroup"
  end
end


function SFA:SaveCurrentFriendlyPositionForSimulation()
  local header = self.headers and self.headers.friendly
  if not header then return false end

  local p, _, rp, x, y = header:GetPoint(1)
  if not p then return false end

  local key = self:GetFriendlyScenarioKeyForMode(self:GetSimulationScenario())
  local point = {
    anchor = p,
    relativeTo = "UIParent",
    relativePoint = rp,
    x = math.floor(x + 0.5),
    y = math.floor(y + 0.5),
  }

  self:SetLastContextPoint("friendly", key, point)

  self.db.friendly.point = self.db.friendly.point or {}
  self.db.friendly.point.anchor = point.anchor
  self.db.friendly.point.relativeTo = point.relativeTo
  self.db.friendly.point.relativePoint = point.relativePoint
  self.db.friendly.point.x = point.x
  self.db.friendly.point.y = point.y

  if not InCombatLockdown() then
    self:ApplyLayout("friendly")
    self:RefreshGroup("friendly")
    self:RefreshOptionsPanel()
  else
    self.pendingLayout = true
  end
  return true
end

function SFA:GetFriendlyCountBasedContextKey()
  local count = 1

  if self.GetSimulationEnabled and self:GetSimulationEnabled() then
    local profile = self:GetSimulationProfile() or {}
    count = #(profile.friendly or {})
  else
    local units = self:GetDisplayedUnits("friendly") or {}
    count = #units
  end

  if count >= 25 then
    return "raid25"
  elseif count >= 10 then
    return "raid10"
  else
    return "smallGroup"
  end
end


function SFA:GetCurrentLayoutContextKey(group)
  if group == "enemy" then
    return "default"
  end

  if group == "friendly" and self.IsSimulationEnabled and self:IsSimulationEnabled() then
    return self:GetFriendlyScenarioKeyForMode(self:GetSimulationScenario())
  end

  local raidUnits = self.GetFriendlyRaidUnits and self:GetFriendlyRaidUnits() or {}
  local count = #raidUnits
  if count >= 25 then
    return "raid25"
  elseif count >= 10 then
    return "raid10"
  end

  if self.IsInArenaContext and self:IsInArenaContext() then
    return "arena"
  end

  local inGroup = false
  if IsInGroup then
    local ok, result = pcall(IsInGroup)
    inGroup = ok and result or false
  end

  if inGroup then
    local partyCount = 1
    if GetNumSubgroupMembers then
      local ok, result = pcall(GetNumSubgroupMembers)
      if ok and type(result) == "number" then
        partyCount = math.max(1, result + 1)
      end
    end
    if partyCount > 1 then
      return "dungeon"
    end
  end

  return "world"
end

function SFA:EnsureScenarioPoints(group)
  local cfg = self.db and self.db[group]
  if not cfg then return nil end
  cfg.scenarioPoints = cfg.scenarioPoints or {}
  local base = cfg.point or { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = 0 }

  local function clonePoint(src)
    return {
      anchor = src.anchor or "CENTER",
      relativeTo = "UIParent",
      relativePoint = src.relativePoint or "CENTER",
      x = src.x or 0,
      y = src.y or 0,
    }
  end

  if group == "friendly" then
    if type(cfg.scenarioPoints.smallGroup) ~= "table" then cfg.scenarioPoints.smallGroup = clonePoint(base) end
    if type(cfg.scenarioPoints.raid10) ~= "table" then cfg.scenarioPoints.raid10 = clonePoint(base) end
    if type(cfg.scenarioPoints.raid25) ~= "table" then cfg.scenarioPoints.raid25 = clonePoint(base) end
  else
    if type(cfg.scenarioPoints.default) ~= "table" then cfg.scenarioPoints.default = clonePoint(base) end
  end

  return cfg.scenarioPoints
end


function SFA:GetActivePointData(group)
  local cfg = self.db and self.db[group]
  if not cfg then return nil end
  cfg.scenarioPoints = cfg.scenarioPoints or {}

  local key = self:GetCurrentLayoutContextKey(group)

  if group == "friendly" then
    local point = cfg.scenarioPoints[key]
    if type(point) ~= "table" then
      local base = cfg.point or { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = -260, y = -40 }
      point = {
        anchor = base.anchor or "CENTER",
        relativeTo = "UIParent",
        relativePoint = base.relativePoint or "CENTER",
        x = base.x or 0,
        y = base.y or 0,
      }
      cfg.scenarioPoints[key] = point
    end
    return point
  else
    if type(cfg.scenarioPoints.default) ~= "table" then
      cfg.scenarioPoints.default = cfg.point or { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 260, y = -40 }
    end
    return cfg.scenarioPoints.default
  end
end




function SFA:SetLastContextPoint(group, key, point)
  local cfg = self.db and self.db[group]
  if not cfg then return end
  cfg.scenarioPoints = cfg.scenarioPoints or {}

  local saved = {
    anchor = point.anchor,
    relativeTo = "UIParent",
    relativePoint = point.relativePoint,
    x = point.x,
    y = point.y,
  }

  if group == "friendly" then
    local mapped = self:GetFriendlyScenarioKeyForMode(key)
    cfg.scenarioPoints[mapped] = saved
  else
    cfg.scenarioPoints.default = saved
  end
end

local function SafePoint(frame, pointData)
  frame:ClearAllPoints()
  frame:SetPoint(pointData.anchor, UIParent, pointData.relativePoint, pointData.x, pointData.y)
end


function SFA:EnsureEnemySpecNameplateIcon(frame)
  return nil
end




function SFA:EnsureEnemyTargetXNameplate(frame)
  if not frame then return nil end

  if not frame.SFATargetXMark then
    local xMark = frame:CreateFontString(nil, "OVERLAY")
    xMark:SetFont("Fonts\\FRIZQT__.TTF", 18, "THICKOUTLINE")
    xMark:SetText("X")
    xMark:SetTextColor(1, 0.1, 0.1, 1)
    xMark:SetShadowOffset(1, -1)
    xMark:SetShadowColor(0, 0, 0, 1)
    xMark:Hide()
    frame.SFATargetXMark = xMark
  end

  -- Hide legacy indicators from older builds
  if frame.SFAComboCircle then frame.SFAComboCircle:Hide() end
  if frame.SFAComboDot and frame.SFAComboDot.Hide then frame.SFAComboDot:Hide() end

  if not frame.SFAComboOrb then
    local orb = frame:CreateTexture(nil, "OVERLAY")
    orb:SetTexture("Interface\\COMMON\\Indicator-Red")
    orb:SetSize(20, 20)
    orb:Hide()
    frame.SFAComboOrb = orb
  end

  return frame.SFATargetXMark
end





function SFA:UpdateEnemyNameplateOverlays(unit)
  if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end

  local frame = C_NamePlate.GetNamePlateForUnit(unit, true) or C_NamePlate.GetNamePlateForUnit(unit)
  if not frame then return end

  local xMark = self:EnsureEnemyTargetXNameplate(frame)

  local shouldShow = false
  if self.db and self.db.other and self.db.other.showTargetXMark then
    local targetExists = false
    if UnitExists then
      local ok, result = pcall(UnitExists, "target")
      targetExists = ok and result or false
    end
    if targetExists and UnitIsUnit then
      local ok, result = pcall(UnitIsUnit, unit, "target")
      shouldShow = ok and result or false
    end
  end

  if shouldShow then
    local anchor = self:GetNameplateAnchor(frame)
    if anchor then
      xMark:ClearAllPoints()
      xMark:SetPoint("BOTTOM", anchor, "TOP", 0, 2)

      if frame.SFAComboOrb then
        frame.SFAComboOrb:ClearAllPoints()
        frame.SFAComboOrb:SetPoint("LEFT", xMark, "RIGHT", 4, 3)
      end
    end

    xMark:Show()
    if frame.SFAComboCircle then frame.SFAComboCircle:Hide() end
    if frame.SFAComboDot then frame.SFAComboDot:Hide() end

    if frame.SFAComboOrb then
      if self:ShouldShowComboCircle() then
        frame.SFAComboOrb:Show()
      else
        frame.SFAComboOrb:Hide()
      end
    end
  else
    xMark:Hide()
    if frame.SFAComboCircle then frame.SFAComboCircle:Hide() end
    if frame.SFAComboDot then frame.SFAComboDot:Hide() end
    if frame.SFAComboOrb then frame.SFAComboOrb:Hide() end
  end
end

function SFA:RefreshEnemyNameplateOverlays()
  if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
  local plates = C_NamePlate.GetNamePlates(false) or {}
  for _, frame in ipairs(plates) do
    local unit = frame.namePlateUnitToken or (frame.UnitFrame and frame.UnitFrame.unit)
    if unit then
      self:UpdateEnemyNameplateOverlays(unit)
    else
      if frame.SFAEnemySpecIcon then frame.SFAEnemySpecIcon:Hide() end
      if frame.SFATargetXMark then frame.SFATargetXMark:Hide() end
      if frame.SFAComboCircle then frame.SFAComboCircle:Hide() end
      if frame.SFAComboDot then frame.SFAComboDot:Hide() end
      if frame.SFAComboOrb then frame.SFAComboOrb:Hide() end
    end
  end
end

local function SetBackdropBasic(frame)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0, 0, 0, 0.18)
  frame:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.55)
end

local function CreateAuraIcon(parent, index, anchorMode)
  local icon = CreateFrame("Button", nil, parent)
  icon:SetSize(14, 14)
  icon:SetFrameStrata(parent:GetFrameStrata())
  icon:SetFrameLevel(parent:GetFrameLevel() + 20)
  icon.tex = icon:CreateTexture(nil, "ARTWORK")
  icon.tex:SetAllPoints()
  icon.border = icon:CreateTexture(nil, "OVERLAY")
  icon.border:SetTexture("Interface/Buttons/UI-Debuff-Overlays")
  icon.border:SetTexCoord(.296875, .5703125, 0, .515625)
  icon.border:SetAllPoints(icon)
  icon.count = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  icon.count:SetPoint("BOTTOMRIGHT", 1, -1)
  icon.count:SetText("")
  icon.spellID = nil
  if icon.SetPropagateMouseClicks then icon:SetPropagateMouseClicks(true) end
  icon:EnableMouse(true)
  icon:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() and self.spellID and SFA and SFA.AddBuffToBlacklist then
      SFA:AddBuffToBlacklist(self.spellID)
    end
  end)
  if anchorMode == "bar" then
    if index == 1 then
      icon:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    else
      icon:SetPoint("RIGHT", parent.buffIcons[index - 1], "LEFT", -2, 0)
    end
  else
    if index == 1 then
      icon:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", -2, -2)
    else
      icon:SetPoint("RIGHT", parent.debuffIcons[index - 1], "LEFT", -2, 0)
    end
  end
  icon:Hide()
  return icon
end

function SFA:GetEnemySpecID(unit)
  local idx = unit and unit:match("arena(%d)")
  idx = idx and tonumber(idx)
  if not idx then return nil end
  return GetArenaOpponentSpec and GetArenaOpponentSpec(idx) or nil
end

function SFA:IsHealerUnit(unit, frame)
  local sim = frame and frame.simulationData or self:GetSimulationData(unit)
  if sim then
    return sim.healer == true, nil
  end

  local specID = self:GetEnemySpecID(unit)
  if specID and self.healerSpecs[specID] then
    return true, specID
  end

  if UnitGroupRolesAssigned then
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    if ok and role == "HEALER" then
      return true, nil
    end
  end

  if unit == "player" and GetSpecialization and GetSpecializationInfo then
    local specIndex = GetSpecialization()
    if specIndex then
      local spec = GetSpecializationInfo(specIndex)
      if spec and self.healerSpecs[spec] then
        return true, spec
      end
    end
  end

  return false, nil
end


function SFA:ApplyClickBindings(frame, group)
  if not frame then return end

  local clicks = self.db[group] and self.db[group].clicks
  if type(clicks) ~= "table" then return end

  local unit = frame.unit
  frame:SetAttribute("unit", unit)

  local allowedButtons = {
    LeftButton = { "type1", "macrotext1", "*type1", "*macrotext1" },
    RightButton = { "type2", "macrotext2", "*type2", "*macrotext2" },
    MiddleButton = { "type3", "macrotext3", "*type3", "*macrotext3" },
    Button4 = { "type4", "macrotext4", "*type4", "*macrotext4" },
    Button5 = { "type5", "macrotext5", "*type5", "*macrotext5" },
  }

  for button, keys in pairs(allowedButtons) do
    local macroText = clicks[button]
    if macroText and macroText ~= "" and unit then
      local resolved = tostring(macroText):gsub("@unit", "@" .. unit)
      frame:SetAttribute(keys[1], "macro")
      frame:SetAttribute(keys[2], resolved)
      frame:SetAttribute(keys[3], "macro")
      frame:SetAttribute(keys[4], resolved)
    else
      frame:SetAttribute(keys[1], nil)
      frame:SetAttribute(keys[2], nil)
      frame:SetAttribute(keys[3], nil)
      frame:SetAttribute(keys[4], nil)
    end
  end
end

function SFA:IsInArenaContext()
  if IsActiveBattlefieldArena and IsActiveBattlefieldArena() then
    return true
  end
  return UnitExists("arena1") or UnitExists("arena2") or UnitExists("arena3")
end

local function AddUniqueUnit(units, unit)
  if not unit then return false end
  local isSim = type(unit) == "string" and unit:match("^sfa_sim_")
  if not isSim and not UnitExists(unit) then return false end
  for _, existing in ipairs(units) do
    if existing == unit then
      return false
    end
    if not isSim and not (type(existing) == "string" and existing:match("^sfa_sim_")) and UnitIsUnit(existing, unit) then
      return false
    end
  end
  units[#units + 1] = unit
  return true
end





function SFA:GetArenaEnemySlotCount()
  local inArena = false
  if IsActiveBattlefieldArena then
    local ok, result = pcall(IsActiveBattlefieldArena)
    inArena = ok and result or false
  end
  if not inArena then
    return 0
  end

  local count = 0

  if GetNumArenaOpponentSpecs then
    local ok, result = pcall(GetNumArenaOpponentSpecs)
    if ok and type(result) == "number" and result > 0 then
      count = math.max(count, result)
    end
  end

  for i = 1, 3 do
    local unit = "arena" .. i
    local exists = false
    if UnitExists then
      local ok, result = pcall(UnitExists, unit)
      exists = ok and result or false
    end
    if exists then
      count = math.max(count, i)
    end
  end

  if count <= 0 then
    -- conservative fallback: 2 slots until a third is confirmed
    count = 2
  end

  if count > 3 then count = 3 end
  return count
end

function SFA:IsReservedArenaEnemySlot(group, unit)
  if group ~= "enemy" or not unit then return false end
  local idx = tonumber(tostring(unit):match("^arena(%d+)$"))
  if not idx then return false end
  local count = self:GetArenaEnemySlotCount()
  return idx <= count
end





function SFA:GetFriendlyEffectiveScaleForCount(count)
  local db = self.db and self.db.friendly
  if not db then return 1 end
  local baseScale = db.scale or 1

  if not db.autoShrinkLargeGroups then
    return baseScale
  end

  count = tonumber(count) or 1
  if count > 5 then
    return tonumber(db.largeGroupScale) or 0.85
  end

  return baseScale
end

function SFA:GetFriendlyEffectiveScale()
  local count = 1

  if self.GetSimulationEnabled and self:GetSimulationEnabled() then
    local profile = self:GetSimulationProfile() or {}
    count = #(profile.friendly or {})
  else
    if IsInRaid and GetNumGroupMembers then
      local okRaid, inRaid = pcall(IsInRaid)
      if okRaid and inRaid then
        local ok, result = pcall(GetNumGroupMembers)
        if ok and type(result) == "number" and result > 0 then
          count = result
        end
      elseif GetNumSubgroupMembers then
        local ok, result = pcall(GetNumSubgroupMembers)
        if ok and type(result) == "number" then
          count = math.max(1, result + 1)
        end
      end
    elseif GetNumSubgroupMembers then
      local ok, result = pcall(GetNumSubgroupMembers)
      if ok and type(result) == "number" then
        count = math.max(1, result + 1)
      end
    end
  end

  return self:GetFriendlyEffectiveScaleForCount(count)
end


function SFA:IsFriendlyAuraAllowed(aura, group)
  if group ~= "friendly" then
    return true
  end

  local db = self.db and self.db.friendly
  if not (db and db.showMyHotsOnly) then
    return true
  end

  return aura ~= nil
end



function SFA:GetFriendlyRaidUnits()
  local units = {}
  if not IsInRaid or not GetNumGroupMembers or not GetRaidRosterInfo then
    return units
  end

  local okRaid, inRaid = pcall(IsInRaid)
  if not okRaid or not inRaid then
    return units
  end

  local okCount, count = pcall(GetNumGroupMembers)
  if not okCount or type(count) ~= "number" or count <= 0 then
    return units
  end

  local entries = {}
  for i = 1, count do
    local unit = "raid" .. i
    local exists = false
    if UnitExists then
      local ok, result = pcall(UnitExists, unit)
      exists = ok and result or false
    end
    if exists then
      local name, rank, subgroup = GetRaidRosterInfo(i)
      entries[#entries + 1] = {
        unit = unit,
        subgroup = tonumber(subgroup) or 99,
        name = name or unit,
      }
    end
  end

  table.sort(entries, function(a, b)
    if a.subgroup ~= b.subgroup then
      return a.subgroup < b.subgroup
    end
    return tostring(a.name) < tostring(b.name)
  end)

  for _, entry in ipairs(entries) do
    units[#units + 1] = entry.unit
  end

  return units
end

function SFA:GetFriendlyLayoutMetrics(visibleCount)
  visibleCount = math.max(tonumber(visibleCount) or 0, 1)
  if visibleCount <= 5 then
    return 1, visibleCount
  end
  local columns = math.ceil(visibleCount / 5)
  return columns, 5
end

function SFA:GetDisplayedUnits(group)
  if self.GetSimulationEnabled and self:GetSimulationEnabled() then
    local scenario = (self.db and self.db.simulation and self.db.simulation.scenario) or "arena3v3"
    if scenario == "arena3v3" then
      if group == "friendly" then
        return { "sfa_sim_friendly_1", "sfa_sim_friendly_2", "sfa_sim_friendly_3" }
      else
        return { "sfa_sim_enemy_1", "sfa_sim_enemy_2", "sfa_sim_enemy_3" }
      end
    elseif scenario == "dungeon" then
      if group == "friendly" then
        return { "sfa_sim_friendly_1", "sfa_sim_friendly_2", "sfa_sim_friendly_3", "sfa_sim_friendly_4", "sfa_sim_friendly_5" }
      else
        return { "sfa_sim_enemy_1" }
      end
    elseif scenario == "raid10" then
      if group == "friendly" then
        local units = {}
        for i = 1, 10 do units[#units + 1] = "sfa_sim_friendly_" .. i end
        return units
      else
        return { "sfa_sim_enemy_1" }
      end
    elseif scenario == "raid25" then
      if group == "friendly" then
        local units = {}
        for i = 1, 25 do units[#units + 1] = "sfa_sim_friendly_" .. i end
        return units
      else
        return { "sfa_sim_enemy_1" }
      end
    else
      if group == "friendly" then
        return { "sfa_sim_friendly_1" }
      else
        return { "sfa_sim_enemy_1" }
      end
    end
  end

  local units = {}

  if group == "friendly" then
    local raidUnits = self:GetFriendlyRaidUnits()
    if #raidUnits > 0 then
      return raidUnits
    end

    table.insert(units, "player")

    local inGroup = false
    if IsInGroup then
      local ok, result = pcall(IsInGroup)
      inGroup = ok and result or false
    end

    if inGroup then
      for i = 1, 4 do
        local unit = "party" .. i
        local exists = false
        if UnitExists then
          local ok, result = pcall(UnitExists, unit)
          exists = ok and result or false
        end
        if exists then
          table.insert(units, unit)
        end
      end
    end

    return units
  end

  local inArena = false
  if IsActiveBattlefieldArena then
    local ok, result = pcall(IsActiveBattlefieldArena)
    inArena = ok and result or false
  end

  if inArena then
    local count = self:GetArenaEnemySlotCount()
    local arenaUnits = {}
    for i = 1, count do
      arenaUnits[#arenaUnits + 1] = "arena" .. i
    end
    return arenaUnits
  else
    local targetExists = false
    if UnitExists then
      local ok, result = pcall(UnitExists, "target")
      targetExists = ok and result or false
    end
    if targetExists then
      local canAttack = false
      if UnitCanAttack then
        local ok, result = pcall(UnitCanAttack, "player", "target")
        canAttack = ok and result or false
      end
      if canAttack then
        table.insert(units, "target")
      end
    end
  end

  return units
end


local function GetTargetHighlightColor(mode)
  if mode == "none" then
    return nil
  elseif mode == "soft" then
    return 1, 0.40, 0.40, 0.90
  elseif mode == "subtle" then
    return 0.80, 0.30, 0.30, 0.70
  end
  return 0.90, 0.35, 0.35, 0.85
end

function SFA:GetSpellNameSafe(spellID)
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

local function FillAuraIcon(icon, texture, borderR, borderG, borderB, spellID)
  icon.spellID = spellID
  icon.tex:SetTexture(texture)
  icon.border:SetVertexColor(borderR or 1, borderG or 0.82, borderB or 0)
  icon:Show()
end


function SFA:IsBlacklistedBuff(spellID)
  if not (spellID and self.db and self.db.buffBlacklist) then
    return false
  end
  local ok, result = pcall(function()
    local id = tonumber(spellID)
    if not id then return false end
    return self.db.buffBlacklist[id] == true
  end)
  if ok then
    return result and true or false
  end
  return false
end

function SFA:AddBuffToBlacklist(spellID)
  local ok, id = pcall(function()
    return tonumber(spellID)
  end)
  if not ok or not id then return end
  self.db.buffBlacklist = self.db.buffBlacklist or {}
  if self.db.buffBlacklist[id] then
    Print("Spell ID already blacklisted: " .. id)
    return
  end
  self.db.buffBlacklist[id] = true
  local spellName = self:GetSpellNameSafe(id)
  Print(spellName and ("Added buff to blacklist: " .. id .. " (" .. spellName .. ")") or ("Added buff to blacklist: " .. id))
  if self.RefreshAll then self:RefreshAll() end
  if self.RefreshBlacklistUI then self:RefreshBlacklistUI() end
end

function SFA:RemoveBuffFromBlacklist(spellID)
  local ok, id = pcall(function()
    return tonumber(spellID)
  end)
  if not ok or not id or not self.db or not self.db.buffBlacklist then return end
  self.db.buffBlacklist[id] = nil
  local spellName = self:GetSpellNameSafe(id)
  Print(spellName and ("Removed buff from blacklist: " .. id .. " (" .. spellName .. ")") or ("Removed buff from blacklist: " .. id))
  if self.RefreshAll then self:RefreshAll() end
  if self.RefreshBlacklistUI then self:RefreshBlacklistUI() end
end


function SFA:UpdateAuraIcons(frame, group)
  local cfg = self.db[group]
  for _, icon in ipairs(frame.buffIcons) do
    icon.spellID = nil
    icon:Hide()
  end
  for _, icon in ipairs(frame.debuffIcons) do
    icon.spellID = nil
    icon:Hide()
  end

  local function addBuff(texture, spellID)
    local idx = 1
    while frame.buffIcons[idx] and frame.buffIcons[idx]:IsShown() do
      idx = idx + 1
    end
    local icon = frame.buffIcons[idx]
    if not icon then return false end
    icon:ClearAllPoints()
    if idx == 1 then
      icon:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    else
      icon:SetPoint("RIGHT", frame.buffIcons[idx - 1], "LEFT", -2, 0)
    end
    FillAuraIcon(icon, texture, 0.2, 0.85, 0.35, spellID)
    return true
  end

  local function addDebuff(texture, spellID)
    local idx = 1
    while frame.debuffIcons[idx] and frame.debuffIcons[idx]:IsShown() do
      idx = idx + 1
    end
    local icon = frame.debuffIcons[idx]
    if not icon then return false end
    icon:ClearAllPoints()
    if idx == 1 then
      icon:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -2, -2)
    else
      icon:SetPoint("RIGHT", frame.debuffIcons[idx - 1], "LEFT", -2, 0)
    end
    FillAuraIcon(icon, texture, 0.9, 0.15, 0.15, spellID)
    return true
  end

  local sim = frame.simulationData or self:GetSimulationData(frame.unit)
  if sim then
    if group == "friendly" then
      for _, spellID in ipairs(sim.buffSpellIDs or {}) do
        if not self:IsBlacklistedBuff(spellID) then
          if not addBuff(SpellTextureSafe(spellID), spellID) then break end
        end
      end
    end
    if cfg.showDebuffs then
      for _, spellID in ipairs(sim.debuffSpellIDs or {}) do
        if not self:IsBlacklistedBuff(spellID) then
          if not addDebuff(SpellTextureSafe(spellID), spellID) then break end
        end
      end
    end
    return
  end

  if not UnitExists(frame.unit) or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
    return
  end

  if group == "friendly" then
    local helpfulFilter = "HELPFUL"
    if self.db and self.db.friendly and self.db.friendly.showMyHotsOnly then
      helpfulFilter = "HELPFUL|PLAYER"
    end

    for i = 1, 16 do
      local aura = C_UnitAuras.GetAuraDataByIndex(frame.unit, i, helpfulFilter)
      if not aura then break end
      local spellID = aura.spellId or aura.spellID
      local texture = aura.icon or aura.iconFileID
      if texture and self:IsFriendlyAuraAllowed(aura, group) and not self:IsBlacklistedBuff(spellID) then
        if not addBuff(texture, spellID) then break end
      end
    end
  end

  if cfg.showDebuffs then
    for i = 1, 16 do
      local aura = C_UnitAuras.GetAuraDataByIndex(frame.unit, i, "HARMFUL")
      if not aura then break end
      local spellID = aura.spellId or aura.spellID
      local texture = aura.icon or aura.iconFileID
      if texture and not self:IsBlacklistedBuff(spellID) then
        if not addDebuff(texture, spellID) then break end
      end
    end
  end
end




function SFA:UpdateTargetXMark(frame, group)
  if frame and frame.targetXMark then frame.targetXMark:Hide() end
end

function SFA:UpdateTargetHighlight(frame, group)
  if group ~= "enemy" or not frame.unit then
    frame.targetBorder:Hide()
    return
  end

  local shouldHighlight = UnitExists("target") and UnitIsUnit(frame.unit, "target")
  if shouldHighlight then
    local r, g, b, a = GetTargetHighlightColor((self.db.enemy and self.db.enemy.targetColor) or "medium")
    if not r then
      frame.targetBorder:Hide()
      return
    end
    frame.targetBorder.top:SetColorTexture(r, g, b, a)
    frame.targetBorder.bottom:SetColorTexture(r, g, b, a)
    frame.targetBorder.left:SetColorTexture(r, g, b, a)
    frame.targetBorder.right:SetColorTexture(r, g, b, a)
    frame.targetBorder:Show()
  else
    frame.targetBorder:Hide()
  end
end







function SFA:UpdateFrameDataOnly(frame, group)
  local unit = frame.unit
  local sim = frame.simulationData or self:GetSimulationData(unit)

  if sim then
    frame.health:SetMinMaxValues(0, 100)
    frame.health:SetValue(math.floor((sim.health or 1) * 100 + 0.5))
    frame.name:SetText(sim.name or unit)

    local r, g, b = 0.1, 0.8, 0.2
    if group == "enemy" and self.db.enemy.classColor and sim.class and RAID_CLASS_COLORS[sim.class] then
      local c = RAID_CLASS_COLORS[sim.class]
      r, g, b = c.r, c.g, c.b
    elseif group == "friendly" and sim.class and RAID_CLASS_COLORS[sim.class] then
      local c = RAID_CLASS_COLORS[sim.class]
      r, g, b = c.r * 0.7 + 0.1, c.g * 0.7 + 0.1, c.b * 0.7 + 0.1
    end
    frame.health:SetStatusBarColor(r, g, b, 0.58)
    frame.value:SetText(sim.value or "")

    frame.role:SetText("")
    if frame.roleIcon then frame.roleIcon:Hide() end
    if sim.healer then
      frame.role:SetText("+")
      frame.role:SetTextColor(1, 0.12, 0.12, 1)
      frame.role:Show()
    elseif sim.tank then
      if frame.roleIcon then
        frame.roleIcon:SetTexture("Interface\\Icons\\INV_Shield_06")
        frame.roleIcon:SetVertexColor(1, 1, 1, 1)
        frame.roleIcon:Show()
      end
      frame.role:Hide()
    else
      frame.role:Hide()
    end

    self:UpdateAuraIcons(frame, group)
    self:UpdateTargetXMark(frame, group)
    self:UpdateTargetHighlight(frame, group)
    return
  end

  local exists = unit and UnitExists(unit)
  local reservedArenaEnemy = self:IsReservedArenaEnemySlot(group, unit)

  if not exists and not reservedArenaEnemy then
    return
  end

  if not exists and reservedArenaEnemy then
    frame.health:SetMinMaxValues(0, 100)
    frame.health:SetValue(0)
    frame.name:SetText(frame.lastKnownName or ("Enemy " .. tostring(unit):gsub("arena", "")))
    frame.health:SetStatusBarColor(0.35, 0.35, 0.35, 0.58)
    frame:SetAlpha(1)
    frame.value:SetText("")
    frame.role:SetText("")
    if frame.roleIcon then frame.roleIcon:Hide() end
    self:UpdateAuraIcons(frame, group)
    self:UpdateTargetXMark(frame, group)
    self:UpdateTargetHighlight(frame, group)
    return
  end

  local current = UnitHealth(unit)
  local maxHealth = UnitHealthMax(unit)
  frame.health:SetMinMaxValues(0, maxHealth or 1)
  frame.health:SetValue(current or 0)

  local name = UnitName(unit) or unit
  frame.lastKnownName = name
  local _, classFile = UnitClass(unit)
  frame.name:SetText(name)

  local r, g, b = 0.1, 0.8, 0.2
  if group == "enemy" and self.db.enemy.classColor and classFile and RAID_CLASS_COLORS[classFile] then
    local c = RAID_CLASS_COLORS[classFile]
    r, g, b = c.r, c.g, c.b
  elseif group == "friendly" then
    if self.db.friendly and self.db.friendly.classColor and classFile and RAID_CLASS_COLORS[classFile] then
      local c = RAID_CLASS_COLORS[classFile]
      r, g, b = c.r, c.g, c.b
    else
      r, g, b = 0.1, 0.75, 0.25
    end
  end

  if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then
    r, g, b = 0.35, 0.35, 0.35
  end
  frame.health:SetStatusBarColor(r, g, b, 0.58)

  if not UnitIsConnected(unit) then
    frame.value:SetText("OFF")
  elseif UnitIsDeadOrGhost(unit) then
    frame.value:SetText("DEAD")
  else
    frame.value:SetText("")
  end

  local roleVisual = nil
  if (group == "enemy" and self.db.enemy.healerMarker) or group == "friendly" then
    roleVisual = self:GetUnitRoleVisual(unit, frame)
  end
  frame.role:SetText("")
  if frame.roleIcon then frame.roleIcon:Hide() end
  if roleVisual == "HEALER" then
    frame.role:SetText("+")
    frame.role:SetTextColor(1, 0.12, 0.12, 1)
    frame.role:Show()
  elseif roleVisual == "TANK" then
    if frame.roleIcon then
      frame.roleIcon:SetTexture("Interface\\Icons\\INV_Shield_06")
      frame.roleIcon:SetVertexColor(1, 1, 1, 1)
      frame.roleIcon:Show()
    end
    frame.role:Hide()
  else
    frame.role:Hide()
  end

  self:UpdateAuraIcons(frame, group)
  self:UpdateTargetXMark(frame, group)
  self:UpdateTargetHighlight(frame, group)
  frame:SetAlpha(1)
end

function SFA:UpdateFrameVisual(frame, group)
  local unit = frame.unit

  local sim = frame.simulationData or self:GetSimulationData(unit)
  if sim then
    if not sim then
      frame.targetBorder:Hide()
      frame:Hide()
      return
    end

    frame:Show()
    frame.health:SetMinMaxValues(0, 100)
    frame.health:SetValue(math.floor((sim.health or 1) * 100 + 0.5))
    frame.name:SetText(sim.name or unit)

    local r, g, b = 0.1, 0.8, 0.2
    if group == "enemy" and self.db.enemy.classColor and sim.class and RAID_CLASS_COLORS[sim.class] then
      local c = RAID_CLASS_COLORS[sim.class]
      r, g, b = c.r, c.g, c.b
    elseif group == "friendly" and sim.class and RAID_CLASS_COLORS[sim.class] then
      local c = RAID_CLASS_COLORS[sim.class]
      r, g, b = c.r * 0.7 + 0.1, c.g * 0.7 + 0.1, c.b * 0.7 + 0.1
    end
    frame.health:SetStatusBarColor(r, g, b, 0.58)
    frame.value:SetText(sim.value or "")
    frame.role:SetText("")
    if frame.roleIcon then frame.roleIcon:Hide() end
    if sim.healer then
      frame.role:SetText("+")
      frame.role:SetTextColor(1, 0.12, 0.12, 1)
      frame.role:Show()
    elseif sim.tank then
      if frame.roleIcon then
        frame.roleIcon:SetTexture("Interface\\Icons\\INV_Shield_06")
        frame.roleIcon:SetVertexColor(1, 1, 1, 1)
        frame.roleIcon:Show()
      end
      frame.role:Hide()
    else
      frame.role:Hide()
    end

    self:UpdateAuraIcons(frame, group)
    self:UpdateTargetXMark(frame, group)

    if group == "enemy" and sim.target then
      local r2, g2, b2, a2 = GetTargetHighlightColor((self.db.enemy and self.db.enemy.targetColor) or "medium")
      if r2 then
        frame.targetBorder.top:SetColorTexture(r2, g2, b2, a2)
        frame.targetBorder.bottom:SetColorTexture(r2, g2, b2, a2)
        frame.targetBorder.left:SetColorTexture(r2, g2, b2, a2)
        frame.targetBorder.right:SetColorTexture(r2, g2, b2, a2)
        frame.targetBorder:Show()
      else
        frame.targetBorder:Hide()
      end
    else
      frame.targetBorder:Hide()
    end
    return
  end

  local exists = unit and UnitExists(unit)
  local reservedArenaEnemy = self:IsReservedArenaEnemySlot(group, unit)

  if not exists and not reservedArenaEnemy then
    frame.targetBorder:Hide()
    frame:Hide()
    return
  end

  frame:Show()

  if not exists and reservedArenaEnemy then
    frame.health:SetMinMaxValues(0, 100)
    frame.health:SetValue(0)
    frame.name:SetText(frame.lastKnownName or ("Enemy " .. tostring(unit):gsub("arena", "")))
    frame.health:SetStatusBarColor(0.35, 0.35, 0.35, 0.58)
    frame.value:SetText("")
    frame.role:SetText("")
    if frame.roleIcon then frame.roleIcon:Hide() end
    self:UpdateAuraIcons(frame, group)
    self:UpdateTargetXMark(frame, group)
    self:UpdateTargetHighlight(frame, group)
    return
  end

  local current = UnitHealth(unit)
  local maxHealth = UnitHealthMax(unit)
  frame.health:SetMinMaxValues(0, maxHealth or 1)
  frame.health:SetValue(current or 0)

  local name = UnitName(unit) or unit
  local _, classFile = UnitClass(unit)
  frame.name:SetText(name)

  local r, g, b = 0.1, 0.8, 0.2
  if group == "enemy" and self.db.enemy.classColor and classFile and RAID_CLASS_COLORS[classFile] then
    local c = RAID_CLASS_COLORS[classFile]
    r, g, b = c.r, c.g, c.b
  elseif group == "friendly" then
    if self.db.friendly and self.db.friendly.classColor and classFile and RAID_CLASS_COLORS[classFile] then
      local c = RAID_CLASS_COLORS[classFile]
      r, g, b = c.r, c.g, c.b
    else
      r, g, b = 0.1, 0.75, 0.25
    end
  end

  if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then
    r, g, b = 0.35, 0.35, 0.35
  end
  frame.health:SetStatusBarColor(r, g, b, 0.58)

  if not UnitIsConnected(unit) then
    frame.value:SetText("OFF")
  elseif UnitIsDeadOrGhost(unit) then
    frame.value:SetText("DEAD")
  else
    frame.value:SetText("")
  end

  local roleVisual = nil
  if (group == "enemy" and self.db.enemy.healerMarker) or group == "friendly" then
    roleVisual = self:GetUnitRoleVisual(unit, frame)
  end
  frame.role:SetText("")
  if frame.roleIcon then frame.roleIcon:Hide() end
  if roleVisual == "HEALER" then
    frame.role:SetText("+")
    frame.role:SetTextColor(1, 0.12, 0.12, 1)
    frame.role:Show()
  elseif roleVisual == "TANK" then
    if frame.roleIcon then
      frame.roleIcon:SetTexture("Interface\\Icons\\INV_Shield_06")
      frame.roleIcon:SetVertexColor(1, 1, 1, 1)
      frame.roleIcon:Show()
    end
    frame.role:Hide()
  else
    frame.role:Hide()
  end

  self:UpdateAuraIcons(frame, group)
  self:UpdateTargetXMark(frame, group)
  self:UpdateTargetHighlight(frame, group)
end







function SFA:ShouldThrottleFriendlyRefresh()
  if not self or not self.db or not self.db.friendly then
    return false
  end

  if self:IsSimulationEnabled() then
    return false
  end

  local units = self:GetDisplayedUnits("friendly")
  return #units > 10
end

function SFA:CanRunFriendlyRefreshNow()
  if not self:ShouldThrottleFriendlyRefresh() then
    return true
  end

  self.session = self.session or {}
  local now = GetTime and GetTime() or 0
  local last = self.session.lastFriendlyRefresh or 0
  local minInterval = 0.18

  if (now - last) >= minInterval then
    self.session.lastFriendlyRefresh = now
    return true
  end

  return false
end

function SFA:GetFriendlyVisibleUnitCount()
  local units = self:GetDisplayedUnits("friendly")
  return #units
end

function SFA:FlushPendingStructuralUpdates()
  local hadPending = self.pendingLayout or self.pendingVisibility or self.pendingRefresh
  self.pendingLayout = false
  self.pendingVisibility = false
  self.pendingRefresh = false
  if not hadPending then return end
  if not self.db then return end
  self:RefreshGroup("friendly")
  self:RefreshGroup("enemy")
  self:RefreshEnemyNameplateOverlays()
end


function SFA:RefreshGroup(group)
  local cfg = self.db[group]
  local inCombat = InCombatLockdown()

  if not cfg.enabled then
    if inCombat then
      self.pendingVisibility = true
      return
    end
    if self.headers[group] then self.headers[group]:Hide() end
    for _, frame in ipairs(self.frames[group]) do
      frame.simulationData = nil
      frame.unit = nil
      frame:SetAttribute("unit", nil)
      frame:SetAlpha(1)
      frame:Hide()
    end
    return
  end

  if self:IsSimulationEnabled() then
    local header = self.headers[group]
    local profile = self:GetSimulationProfile() or {}
    local entries = (profile[group] or {})

    if inCombat then
      self.pendingVisibility = true
      for i, frame in ipairs(self.frames[group]) do
        local sim = entries[i]
        frame.simulationData = sim
        frame.unit = nil
        if sim then
          self:UpdateFrameDataOnly(frame, group)
        end
      end
      return
    end

    if header then
      header:SetScale(group == "friendly" and self:GetFriendlyEffectiveScaleForCount(#entries) or cfg.scale)
      header:SetShown(#entries > 0)
      if header.label then header.label:SetShown(not self.db.hideHeaders) end
    end

    for i, frame in ipairs(self.frames[group]) do
      local sim = entries[i]
      frame.unit = nil
      frame.simulationData = sim
      if sim then
        self:ApplyClickBindings(frame, group)
        self:UpdateFrameVisual(frame, group)
      else
        frame:SetAlpha(1)
        frame:Hide()
      end
    end
    self:ApplyLayout(group)
    return
  end

  local header = self.headers[group]
  local units = self:GetDisplayedUnits(group)
  local activeCount = #units

  if inCombat then
    self.pendingVisibility = true
    -- only update data for frames that already have assigned units or reserved arena slots
    for i, frame in ipairs(self.frames[group]) do
      local keepUnit = frame.unit
      local nextUnit = units[i]
      if keepUnit then
        self:UpdateFrameDataOnly(frame, group)
      elseif nextUnit and self.IsReservedArenaEnemySlot and self:IsReservedArenaEnemySlot(group, nextUnit) then
        frame.unit = nextUnit
        self:UpdateFrameDataOnly(frame, group)
      end
    end
    return
  end

  for _, frame in ipairs(self.frames[group]) do
    frame.simulationData = nil
  end

  if header then
    header:SetScale(group == "friendly" and self:GetFriendlyEffectiveScaleForCount(activeCount) or cfg.scale)
    header:SetShown(activeCount > 0)
    if header.label then header.label:SetShown(not self.db.hideHeaders) end
  end

  for i, frame in ipairs(self.frames[group]) do
    local unit = units[i]
    frame.unit = unit
    if unit then
      self:ApplyClickBindings(frame, group)
      self:UpdateFrameVisual(frame, group)
    else
      frame.unit = nil
      frame:SetAttribute("unit", nil)
      frame:SetAlpha(1)
      frame:Hide()
    end
  end

  self:ApplyLayout(group)
end


function SFA:QueueRefresh(delay)
  if self.pendingRefresh then return end
  self.pendingRefresh = true

  local actualDelay = delay or 0.08
  if self:ShouldThrottleFriendlyRefresh() then
    actualDelay = math.max(actualDelay, 0.15)
  end

  C_Timer.After(actualDelay, function()
    if not self.db then
      self.pendingRefresh = false
      return
    end

    if InCombatLockdown() then
      self.pendingLayout = true
      self.pendingVisibility = true
      self.pendingRefresh = false
      return
    end

    self.pendingRefresh = false

    if self:CanRunFriendlyRefreshNow() then
      self:RefreshGroup("friendly")
    else
      self.pendingRefresh = true
      C_Timer.After(0.10, function()
        if SFA and SFA.db then
          SFA.pendingRefresh = false
          if not InCombatLockdown() then
            SFA:RefreshGroup("friendly")
          else
            SFA.pendingLayout = true
            SFA.pendingVisibility = true
          end
        end
      end)
    end

    self:RefreshGroup("enemy")
  end)
end

function SFA:QueueArenaRefreshes()
  self:QueueRefresh(0.05)
  C_Timer.After(0.20, function()
    if SFA and SFA.db then SFA:QueueRefresh(0.05) end
  end)
  C_Timer.After(0.60, function()
    if SFA and SFA.db then SFA:QueueRefresh(0.05) end
  end)
  C_Timer.After(1.20, function()
    if SFA and SFA.db then SFA:QueueRefresh(0.05) end
  end)
  C_Timer.After(2.50, function()
    if SFA and SFA.db then SFA:QueueRefresh(0.05) end
  end)
end

local function StartMoving(header, group)
  if SFA.db.locked or InCombatLockdown() then return end
  if IsShiftKeyDown and not IsShiftKeyDown() then return end
  header:StartMoving()
  header.isMoving = true
  header.group = group
end


local function StopMoving(header)
  if not header.isMoving then return end
  header:StopMovingOrSizing()
  header.isMoving = false

  local p, _, rp, x, y = header:GetPoint(1)
  local cfg = SFA.db[header.group]
  local key = SFA:GetCurrentLayoutContextKey(header.group)

  local point = {
    anchor = p,
    relativeTo = "UIParent",
    relativePoint = rp,
    x = math.floor(x + 0.5),
    y = math.floor(y + 0.5),
  }

  SFA:SetLastContextPoint(header.group, key, point)

  cfg.point = cfg.point or {}
  cfg.point.anchor = point.anchor
  cfg.point.relativeTo = point.relativeTo
  cfg.point.relativePoint = point.relativePoint
  cfg.point.x = point.x
  cfg.point.y = point.y

  if header.group == "friendly" then
    cfg.scenarioPoints = cfg.scenarioPoints or {}
    cfg.scenarioPoints[key] = {
      anchor = point.anchor,
      relativeTo = "UIParent",
      relativePoint = point.relativePoint,
      x = point.x,
      y = point.y,
    }
  end

  SFA:QueueRefresh()
  if SFA.RefreshOptionsPanel then SFA:RefreshOptionsPanel() end
end

function SFA:CreateUnitFrame(parent, unit, group, index)
  local cfg = self.db[group]
  local frame = CreateFrame("Button", addonName .. group .. index, parent, "SecureUnitButtonTemplate")
  frame.unit = unit
  frame:SetAttribute("unit", unit)
  frame:RegisterForClicks("AnyUp")
  frame:SetSize(cfg.width, cfg.height)
  if index == 1 then
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  else
    frame:SetPoint("TOPLEFT", self.frames[group][index - 1], "BOTTOMLEFT", 0, -cfg.spacing)
  end
  SetBackdropBasic(frame)
  frame:SetScript("OnMouseDown", function(self, button)
    if not SFA.db.locked and button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
      StartMoving(parent, group)
    end
  end)
  frame:SetScript("OnMouseUp", function(self, button)
    if parent and parent.isMoving then
      StopMoving(parent)
    end
  end)
  frame:SetFrameStrata("MEDIUM")

  frame.targetBorder = CreateFrame("Frame", nil, frame)
  frame.targetBorder:SetAllPoints(frame)
  frame.targetBorder:SetFrameLevel(frame:GetFrameLevel() + 8)

  frame.targetBorder.top = frame.targetBorder:CreateTexture(nil, "OVERLAY")
  frame.targetBorder.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  frame.targetBorder.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  frame.targetBorder.top:SetHeight(1)

  frame.targetBorder.bottom = frame.targetBorder:CreateTexture(nil, "OVERLAY")
  frame.targetBorder.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  frame.targetBorder.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  frame.targetBorder.bottom:SetHeight(1)

  frame.targetBorder.left = frame.targetBorder:CreateTexture(nil, "OVERLAY")
  frame.targetBorder.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  frame.targetBorder.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  frame.targetBorder.left:SetWidth(1)

  frame.targetBorder.right = frame.targetBorder:CreateTexture(nil, "OVERLAY")
  frame.targetBorder.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  frame.targetBorder.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  frame.targetBorder.right:SetWidth(1)

  frame.targetBorder:Hide()

  frame.health = CreateFrame("StatusBar", nil, frame)
  frame.health:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  frame.health:SetPoint("TOPLEFT", 2, -2)
  frame.health:SetPoint("BOTTOMRIGHT", -2, 2)
  frame.health:SetAlpha(0.58)

  frame.bg = frame.health:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetColorTexture(0.08, 0.08, 0.08, 0.10)

  frame.specIcon = frame:CreateTexture(nil, "OVERLAY")
  frame.specIcon:SetSize(18, 18)
  if frame.name then
    frame.specIcon:SetPoint("BOTTOM", frame.name, "TOP", 0, 6)
  else
    frame.specIcon:SetPoint("BOTTOM", frame, "TOP", 0, 4)
  end
  frame.specIcon:Hide()

  frame.targetXMark = frame:CreateFontString(nil, "OVERLAY")
  frame.targetXMark:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
  if frame.name then
    frame.targetXMark:SetPoint("BOTTOMLEFT", frame.name, "TOPLEFT", 0, 2)
  else
    frame.targetXMark:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 2, 2)
  end
  frame.targetXMark:SetText("X")
  frame.targetXMark:SetTextColor(1, 0.1, 0.1, 1)
  frame.targetXMark:Hide()

  frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.name:SetPoint("LEFT", frame, "LEFT", 6, 0)
  frame.name:SetJustifyH("LEFT")
  frame.name:SetWidth(cfg.width - 42)

  frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.value:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
  frame.value:SetJustifyH("RIGHT")

  frame.roleIcon = frame:CreateTexture(nil, "OVERLAY")
frame.roleIcon:SetSize(14,14)
frame.roleIcon:SetPoint("CENTER", frame.health or frame, "CENTER", 0, 0)
frame.roleIcon:Hide()

frame.role = frame:CreateFontString(nil, "OVERLAY")
  frame.role:SetFont("Fonts\\FRIZQT__.TTF", 32, "THICKOUTLINE")
  frame.role:ClearAllPoints()
  frame.role:SetPoint("CENTER", frame.health or frame, "CENTER", 0, 0)

  frame.buffIcons = {}
  frame.debuffIcons = {}
  for i = 1, 4 do
    frame.buffIcons[i] = CreateAuraIcon(frame, i, "bar")
    frame.debuffIcons[i] = CreateAuraIcon(frame, i, "under")
  end

  frame:SetScript("OnEnter", function(self)
    if not self.unit then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetUnit(self.unit)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

  self:ApplyClickBindings(frame, group)
  frame:Hide()
  return frame
end

function SFA:CreateHeader(group)
  local cfg = self.db[group]
  local header = CreateFrame("Frame", addonName .. group .. "Header", UIParent)
  header:SetMovable(true)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetClampedToScreen(true)
  header:SetScript("OnDragStart", function(self) StartMoving(self, group) end)
  header:SetScript("OnDragStop", StopMoving)
  local pointData = self:GetActivePointData(group) or cfg.point
  SafePoint(header, pointData)

  local count = group == "friendly" and 40 or #cfg.units
  header:SetSize(cfg.width, (cfg.height * math.max(count, 1)) + ((math.max(count, 1) - 1) * cfg.spacing) + 20)

  header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  header.label:SetPoint("BOTTOM", header, "TOP", 0, 4)
  header.label:SetText(group == "friendly" and "SFA Friendly" or "SFA Enemy")
  header.label:SetShown(not self.db.hideHeaders)

  self.headers[group] = header

  for i = 1, count do
    local unit = cfg.units[i]
    self.frames[group][i] = self:CreateUnitFrame(header, unit, group, i)
    if unit and not InCombatLockdown() then
      self:ApplyClickBindings(self.frames[group][i], group)
    end
  end
end

function SFA:RebuildGroup(group)
  if InCombatLockdown() then
    Print("Cannot rebuild secure frames in combat.")
    return
  end

  for _, frame in ipairs(self.frames[group]) do
    frame:Hide()
    frame:SetParent(nil)
  end
  wipe(self.frames[group])

  if self.headers[group] then
    self.headers[group]:Hide()
    self.headers[group]:SetParent(nil)
    self.headers[group] = nil
  end

  self:CreateHeader(group)
  self:RefreshGroup(group)
end

function SFA:RefreshAll()
  self:RefreshGroup("friendly")
  self:RefreshGroup("enemy")
end

function SFA:ApplyLayout(group)
  if InCombatLockdown() then
    self.pendingLayout = true
    return
  end

  local cfg = self.db[group]
  local header = self.headers[group]
  if not header then return end

  local units = self:GetDisplayedUnits(group)
  local visibleCount = math.max(self:IsSimulationEnabled() and #((self:GetSimulationProfile() or {})[group] or {}) or #units, 1)
  local effectiveScale = group == "friendly" and self:GetFriendlyEffectiveScaleForCount(visibleCount) or cfg.scale
  local activeKey = self:GetCurrentLayoutContextKey(group)
  local pointData = self:GetActivePointData(group) or cfg.point
  SafePoint(header, pointData)
  header:SetScale(effectiveScale)
  if header.label then header.label:SetShown(not self.db.hideHeaders) end

  local columnGap = cfg.spacing + 10
  local columns, rows = 1, visibleCount
  if group == "friendly" then
    columns, rows = self:GetFriendlyLayoutMetrics(visibleCount)
  end

  local totalWidth = (cfg.width * columns) + (columnGap * math.max(columns - 1, 0))
  local totalHeight = (cfg.height * rows) + ((rows - 1) * cfg.spacing) + 20
  header:SetSize(totalWidth, totalHeight)
  if header.dragOverlay then
    header.dragOverlay:ClearAllPoints()
    header.dragOverlay:SetAllPoints(header)
  end

  for i, frame in ipairs(self.frames[group]) do
    frame:SetSize(cfg.width, cfg.height)
    frame.name:SetWidth(cfg.width - 42)
    frame:ClearAllPoints()

    local isVisibleFrame = (frame.unit ~= nil) or (frame.simulationData ~= nil and self:IsSimulationEnabled())
    if isVisibleFrame then
      if group == "friendly" and visibleCount > 5 then
        local index = i - 1
        local col = math.floor(index / 5)
        local row = index % 5
        local x = -(col * (cfg.width + columnGap))
        local y = -(row * (cfg.height + cfg.spacing))
        frame:SetPoint("TOPRIGHT", header, "TOPRIGHT", x, y)
      else
        if i == 1 then
          frame:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
        else
          local prev = self.frames[group][i - 1]
          if prev and ((prev.unit ~= nil) or (prev.simulationData ~= nil and self:IsSimulationEnabled())) then
            frame:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -cfg.spacing)
          else
            frame:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
          end
        end
      end
    else
      frame:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    end
  end
end

function SFA:InitializeFrames()
  self:CreateHeader("friendly")
  self:CreateHeader("enemy")
  self:RefreshGroup("friendly")
  self:RefreshGroup("enemy")
end





function SFA:MigrateFriendlySettings()
  if not (self and self.db) then return end

  local function clonePoint(src)
    return {
      anchor = (src and src.anchor) or "CENTER",
      relativeTo = "UIParent",
      relativePoint = (src and src.relativePoint) or "CENTER",
      x = (src and src.x) or 0,
      y = (src and src.y) or 0,
    }
  end

  for _, group in ipairs({ "friendly", "enemy" }) do
    local entry = self.db[group]
    if entry then
      local clicks = entry.clicks
      if type(clicks) == "table" then
        local keys = {
          autoShrinkLargeGroups = true,
          largeGroupScale = true,
          grayOutOfRange = true,
          rangeThreshold = true,
          showMyHotsOnly = true,
          hideBlizzardRaidFrames = true,
        }

        for key in pairs(keys) do
          if clicks[key] ~= nil and entry[key] == nil then
            entry[key] = clicks[key]
          end
          clicks[key] = nil
        end
      end

      entry.grayOutOfRange = nil
      entry.rangeThreshold = nil
      self:EnsureScenarioPoints(group)

      local fallback = clonePoint(entry.point)
      local sp = entry.scenarioPoints or {}

      if group == "friendly" then
        if type(sp.smallGroup) ~= "table" then
          sp.smallGroup = clonePoint(sp.smallGroup or sp.world or sp.arena or sp.dungeon or fallback)
        end
        if type(sp.raid10) ~= "table" then
          sp.raid10 = clonePoint(sp.raid10 or fallback)
        end
        if type(sp.raid25) ~= "table" then
          sp.raid25 = clonePoint(sp.raid25 or fallback)
        end

        sp.world = nil
        sp.arena = nil
        sp.dungeon = nil

        if entry.autoShrinkLargeGroups == nil then entry.autoShrinkLargeGroups = true end
        if entry.largeGroupScale == nil then entry.largeGroupScale = 0.85 end
        if entry.showMyHotsOnly == nil then entry.showMyHotsOnly = false end
        if entry.hideBlizzardRaidFrames == nil then entry.hideBlizzardRaidFrames = false end
      else
        if type(sp.default) ~= "table" then
          sp.default = clonePoint(sp.default or sp.world or sp.arena or sp.dungeon or sp.raid10 or sp.raid25 or fallback)
        end
        sp.world = nil
        sp.arena = nil
        sp.dungeon = nil
        sp.raid10 = nil
        sp.raid25 = nil
      end

      entry.scenarioPoints = sp
    end
  end
end



function SFA:ApplyBlizzardRaidFramesVisibility()
  if InCombatLockdown() then
    self.pendingLayout = true
    return
  end

  local hide = self.db and self.db.friendly and self.db.friendly.hideBlizzardRaidFrames

  local function applyToFrame(frame, shouldHide)
    if not frame then return end
    if shouldHide then
      frame:Hide()
      if frame.UnregisterAllEvents then pcall(frame.UnregisterAllEvents, frame) end
      if frame.SetDontSavePosition then pcall(frame.SetDontSavePosition, frame, true) end
    else
      frame:Show()
    end
  end

  applyToFrame(CompactRaidFrameManager, hide)
  applyToFrame(CompactRaidFrameContainer, hide)
end




function SFA:UpdateMinimapButtonPosition()
  if not self.minimapButton or not Minimap then return end
  local db = self.db and self.db.minimap
  if not db then return end

  local angle = math.rad(tonumber(db.angle) or 220)
  local radius = 104
  local x = math.cos(angle) * radius
  local y = math.sin(angle) * radius

  self.minimapButton:ClearAllPoints()
  self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
  self.minimapButton:SetShown(db.enabled ~= false)
end

function SFA:CreateMinimapButton()
  if self.minimapButton or not Minimap then return end

  self.db.minimap = self.db.minimap or {}
  if self.db.minimap.enabled == nil then
    self.db.minimap.enabled = true
  end
  if self.db.minimap.angle == nil then
    self.db.minimap.angle = 220
  end

  local button = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
  button:SetSize(32, 32)
  button:SetFrameStrata("MEDIUM")
  button:EnableMouse(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\AddOns\\Simple_Frame_Assistant\\Icon")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER")
  button.icon = icon

  local overlay = button:CreateTexture(nil, "OVERLAY")
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetSize(54, 54)
  overlay:SetPoint("TOPLEFT")
  button.overlay = overlay

  local function updateAngleFromCursor()
    if not Minimap then return end
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or UIParent:GetScale() or 1
    px, py = px / scale, py / scale
    local angle = math.deg(math.atan2(py - my, px - mx))
    if angle < 0 then
      angle = angle + 360
    end
    SFA.db.minimap.angle = angle
    SFA:UpdateMinimapButtonPosition()
  end

  button:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
      if SFA and SFA.ToggleOptions then
        SFA:ToggleOptions()
      end
    else
      if SFA and SFA.ToggleOptions then
        SFA:ToggleOptions()
      end
    end
  end)

  button:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then return end
    self.dragging = true
    updateAngleFromCursor()
  end)

  button:SetScript("OnDragStop", function(self)
    if not self.dragging then return end
    self.dragging = false
    updateAngleFromCursor()
  end)

  button:SetScript("OnUpdate", function(self)
    if not self.dragging then return end
    updateAngleFromCursor()
  end)

  self.minimapButton = button
  self:UpdateMinimapButtonPosition()
end

function SFA:OnEvent(event, ...)
  if event == "PLAYER_LOGIN" then
    self:InitializeDB()
    self:MigrateFriendlySettings()
    self:InitializeFrames()
    self:CreateOptionsPanel()
    self:RegisterSlash()
    self:CreateMinimapButton()
    self:RefreshQuestIndicators()
    self:ApplyBlizzardRaidFramesVisibility()
    Print("Loaded. Type /sfa")
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    self:FlushPendingStructuralUpdates()
    self:ApplyBlizzardRaidFramesVisibility()
    self:UpdateMinimapButtonPosition()
    self:RefreshEnemyNameplateOverlays()
    return
  end

  if event == "NAME_PLATE_UNIT_ADDED" then
    local unit = ...
    self:UpdateNameplateQuestIndicator(unit)
    self:UpdateEnemyNameplateOverlays(unit)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    local unit = ...
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
      local frame = C_NamePlate.GetNamePlateForUnit(unit, true) or C_NamePlate.GetNamePlateForUnit(unit)
      if frame and frame.SFAQuestIcon then frame.SFAQuestIcon:Hide() end
      if frame and frame.SFAEnemySpecIcon then frame.SFAEnemySpecIcon:Hide() end
      if frame and frame.SFATargetXMark then frame.SFATargetXMark:Hide() end
      if frame and frame.SFAComboCircle then frame.SFAComboCircle:Hide() end
      if frame and frame.SFAComboDot then frame.SFAComboDot:Hide() end
      if frame and frame.SFAComboOrb then frame.SFAComboOrb:Hide() end
    end
  elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
    self:RefreshQuestIndicators()

elseif event == "UNIT_POWER_UPDATE" then
  local unit, powerType = ...
  if unit == "player" and (powerType == "COMBO_POINTS" or powerType == "COMBOPOINTS") then
    self:RefreshEnemyNameplateOverlays()
  end
  elseif event == "PLAYER_TARGET_CHANGED" or event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" or event == "ARENA_OPPONENT_UPDATE" or event == "UNIT_NAME_UPDATE" then
    self:RefreshEnemyNameplateOverlays()
  end

  -- Data-only combat updates
  if InCombatLockdown() then
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_AURA" or event == "UNIT_NAME_UPDATE" or event == "UNIT_FLAGS" or event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ROLES_ASSIGNED" or event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE" then
      if self:CanRunFriendlyRefreshNow() then self:RefreshGroup("friendly") else self.pendingRefresh = true end
      self:RefreshGroup("enemy")
    else
      self.pendingLayout = true
      self.pendingVisibility = true
    end
    return
  end

  if not InCombatLockdown() and (event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "GROUP_ROSTER_UPDATE") then
    self:ApplyBlizzardRaidFramesVisibility()
  end

  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" or event == "ARENA_OPPONENT_UPDATE" then
    self:QueueArenaRefreshes()
    C_Timer.After(0.15, function()
      if SFA and SFA.db then
        SFA:RefreshQuestIndicators()
        if not InCombatLockdown() then
          SFA:RefreshEnemyNameplateOverlays()
        end
      end
    end)
  else
    self:QueueRefresh()
  end
end

function SFA:RegisterEvents()
  self.eventFrame = CreateFrame("Frame")
  self.eventFrame:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
  self.eventFrame:RegisterEvent("PLAYER_LOGIN")
  self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
  self.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  self.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
  self.eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
  self.eventFrame:RegisterEvent("UNIT_HEALTH")
  self.eventFrame:RegisterEvent("UNIT_MAXHEALTH")
  self.eventFrame:RegisterEvent("UNIT_AURA")
  self.eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
  self.eventFrame:RegisterEvent("UNIT_FLAGS")
  self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  self.eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
  self.eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
  self.eventFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
  self.eventFrame:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
  self.eventFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
  self.eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  self.eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  self.eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
  self.eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
  self.eventFrame:RegisterEvent("QUEST_ACCEPTED")
  self.eventFrame:RegisterEvent("QUEST_REMOVED")
end

SFA:RegisterEvents()


function SFA:GetUnitRoleVisual(unit, frame)
  local sim = frame and frame.simulationData or self:GetSimulationData(unit)
  if sim then
    if sim.healer then
      return "HEALER"
    elseif sim.tank then
      return "TANK"
    end
    return nil
  end

  local specID = self:GetEnemySpecID(unit)
  if specID and self.healerSpecs[specID] then
    return "HEALER"
  end
  if specID and self.tankSpecs and self.tankSpecs[specID] then
    return "TANK"
  end

  if UnitGroupRolesAssigned then
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    if ok and (role == "HEALER" or role == "TANK") then
      return role
    end
  end

  if unit == "player" and GetSpecialization and GetSpecializationInfo then
    local specIndex = GetSpecialization()
    if specIndex then
      local spec = GetSpecializationInfo(specIndex)
      if spec and self.healerSpecs[spec] then
        return "HEALER"
      end
      if spec and self.tankSpecs and self.tankSpecs[spec] then
        return "TANK"
      end
    end
  end

  return nil
end


function SFA:ShouldShowRoleIcon(group, roleVisual)
  return roleVisual == "HEALER" or roleVisual == "TANK"
end


function SFA:GetSpecIconForUnit(unit)
  return nil
end


function SFA:UpdateEnemySpecIcon(frame, group, unit)
  if frame and frame.specIcon then frame.specIcon:Hide() end
end


-- === SFA GCD Stats (Character Frame) ===
local function SFA_UpdateCharacterGCD()
    if not CharacterFrame or not CharacterFrame:IsShown() then return end

    local enabled = true
    if SFA and SFA.db and SFA.db.other and SFA.db.other.showCharacterGCD ~= nil then
        enabled = SFA.db.other.showCharacterGCD
    end

    if not enabled then
        if SFA_GCDText then
            SFA_GCDText:SetText("")
            SFA_GCDText:Hide()
        end
        return
    end

    local haste = UnitSpellHaste("player") / 100
    local gcd = math.max(0.75, 1.5 / (1 + haste))
    local one = gcd * 1.25

    if not SFA_GCDText then
        SFA_GCDText = CharacterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        SFA_GCDText:SetPoint("TOPLEFT", CharacterStatsPane, "BOTTOMLEFT", 0, -20)
        SFA_GCDText:SetJustifyH("LEFT")
    end

    SFA_GCDText:SetText(string.format("Estimated GCD: %.2f\nOne-Button GCD: %.2f", gcd, one))
    SFA_GCDText:Show()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("UNIT_INVENTORY_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
    C_Timer.After(0.1, SFA_UpdateCharacterGCD)
end)

hooksecurefunc("PaperDollFrame_UpdateStats", SFA_UpdateCharacterGCD)
