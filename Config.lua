local addonName, SFA = ...
SFA = SFA or {}
_G[addonName] = SFA

SFA.defaults = {
  locked = false,
  panel = {
    width = 940,
    height = 940,
  },
  buffBlacklist = {},
  hideHeaders = false,
  minimap = {
    enabled = true,
    angle = 220,
  },
  other = {
    showQuestIndicator = false,
    showTargetXMark = false,
  },
  simulation = {
    enabled = false,
    scenario = "arena3v3",
  },
friendly = {
  enabled = true,
  classColor = true,
  showDebuffs = true,
  showHealerIcon = true,
  showTankIcon = true,
  width = 180,
  height = 34,
  scale = 1.0,
  spacing = 6,
  point = { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = -260, y = -40 },
  scenarioPoints = {
    smallGroup = { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = -260, y = -40 },
    raid10 = { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = -260, y = -40 },
    raid25 = { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = -260, y = -40 },
  },
  units = { "player", "party1", "party2", "party3", "party4" },
  autoShrinkLargeGroups = true,
  largeGroupScale = 0.85,
  showMyHotsOnly = false,
  hideBlizzardRaidFrames = false,
  clicks = {
    LeftButton = "/target [@unit]",
    RightButton = "/cast [@unit,help,nodead] Rejuvenation",
    MiddleButton = "/cast [@unit,help,nodead] Remove Corruption",
    Button4 = "",
    Button5 = "",
  },
},
enemy = {
  enabled = true,
  showDebuffs = true,
  showHealerIcon = true,
  showTankIcon = true,
  width = 180,
  height = 34,
  scale = 1.0,
  spacing = 6,
  point = { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 260, y = -40 },
  scenarioPoints = {
    default = { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 260, y = -40 },
  },
  units = { "arena1", "arena2", "arena3" },
  healerMarker = true,
  classColor = true,
  clicks = {
    LeftButton = "/target [@unit]",
    RightButton = "/cast [@unit,harm,nodead] Cyclone",
    MiddleButton = "/cast [@unit,harm,nodead] Skull Bash",
    Button4 = "",
    Button5 = "",
  },
},

}

local function DeepCopy(src)
  if type(src) ~= "table" then return src end
  local out = {}
  for k, v in pairs(src) do
    out[k] = DeepCopy(v)
  end
  return out
end

local function MergeDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      MergeDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

function SFA:InitializeDB()
  if type(SFA_DB) ~= "table" then
    SFA_DB = DeepCopy(self.defaults)
  else
    MergeDefaults(SFA_DB, self.defaults)
  end
  self.db = SFA_DB
  self.session = self.session or {}
  self.session.simulationEnabled = false
  self.session.simulationProfile = nil
  if self.db.simulation then
    self.db.simulation.enabled = false
  end
end

function SFA:GetGroupDB(group)
  return self.db and self.db[group]
end

function SFA:GetClickMacro(group, button)
  local groupDB = self:GetGroupDB(group)
  return groupDB and groupDB.clicks and groupDB.clicks[button] or ""
end

function SFA:SetClickMacro(group, button, text)
  local groupDB = self:GetGroupDB(group)
  if not groupDB then return end
  groupDB.clicks[button] = text or ""
end
