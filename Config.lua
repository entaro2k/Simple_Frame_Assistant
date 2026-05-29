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
  spellNameCache = {},
  hideHeaders = false,
  minimap = {
    enabled = true,
    angle = 220,
  },
  other = {
    showQuestIndicator = false,
    showTargetXMark = false,
    showCharacterGCD = true,
	showBuilderSpenderIndicator = true,
    redesignMacroWindow = false,
    resourceVoiceAlerts = {
      enabled = false,
      cooldown = 1.0,
      volume = 5,
      voiceStyle = "male",
    },
    procReadyAlerts = {
      enabled = false,
      spells = {},
    },
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
    world     = { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = -260, y = -40 },
    arena     = { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = -260, y = -40 },
    dungeon   = { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = -260, y = -40 },
    raid10    = { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = -260, y = -40 },
    raid25    = { anchor = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = -260, y = -40 },
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
    MiddleButton = "/cast [mod:alt,@unit,harm,nodead] Soothe; [@unit,harm,nodead] Skull Bash",
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
  -- Global settings (layout, minimap, other, non-click friendly/enemy settings)
  if type(SFA_DB) ~= "table" then
    SFA_DB = DeepCopy(self.defaults)
  else
    MergeDefaults(SFA_DB, self.defaults)
  end
  self.db = SFA_DB

  -- Per-character click macros stored separately
  if type(SFA_DB_Char) ~= "table" then SFA_DB_Char = {} end
  SFA_DB_Char.clicks = SFA_DB_Char.clicks or {}
  SFA_DB_Char.clicks.friendly = SFA_DB_Char.clicks.friendly or {}
  SFA_DB_Char.clicks.enemy    = SFA_DB_Char.clicks.enemy    or {}

  -- Merge defaults for clicks if not yet set per character
  local defaultButtons = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }
  for _, btn in ipairs(defaultButtons) do
    if SFA_DB_Char.clicks.friendly[btn] == nil then
      SFA_DB_Char.clicks.friendly[btn] = self.defaults.friendly.clicks[btn] or ""
    end
    if SFA_DB_Char.clicks.enemy[btn] == nil then
      SFA_DB_Char.clicks.enemy[btn] = self.defaults.enemy.clicks[btn] or ""
    end
  end
  self.charDB = SFA_DB_Char

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
  -- Always read from per-character storage
  return self.charDB and self.charDB.clicks and
         self.charDB.clicks[group] and self.charDB.clicks[group][button] or ""
end

function SFA:SetClickMacro(group, button, text)
  if not self.charDB then return end
  self.charDB.clicks = self.charDB.clicks or {}
  self.charDB.clicks[group] = self.charDB.clicks[group] or {}
  self.charDB.clicks[group][button] = text or ""
end
