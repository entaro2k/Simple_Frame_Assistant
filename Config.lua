local addonName, SFA = ...
SFA = SFA or {}
_G[addonName] = SFA

-- 0.25.0 redesign: this addon no longer renders its own unit frames, so
-- the defaults below only cover what's left -- Smart Assist settings, the
-- minimap button, and the friendly/enemy per-spec click macros (applied
-- to Blizzard's own native frames). Everything about SFA's own frame
-- layout, simulation, and the aura blacklist has been removed.
SFA.defaults = {
  spellNameCache = {},
  macroIconExplicit = {},
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
  friendly = {
    clicks = {
      LeftButton = "/target [@unit]",
      RightButton = "/cast [@unit,help,nodead] Rejuvenation",
      MiddleButton = "/cast [@unit,help,nodead] Remove Corruption",
    },
  },
  enemy = {
    clicks = {
      LeftButton = "/target [@unit]",
      RightButton = "/cast [@unit,harm,nodead] Cyclone",
      MiddleButton = "/cast [mod:alt,@unit,harm,nodead] Soothe; [@unit,harm,nodead] Skull Bash",
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

  -- Per-character, per-specialization click macros.
  -- Keyed by spec ID, each holding friendly/enemy button tables.
  -- The legacy SFA_DB_Char.clicks tables are used as the fallback when a
  -- spec has no stored macro yet (and seed the player's current spec on first run).
  SFA_DB_Char.clicksBySpec = SFA_DB_Char.clicksBySpec or {}

  -- Per-character: friendly/enemy enabled toggles
  if SFA_DB_Char.friendlyEnabled == nil then SFA_DB_Char.friendlyEnabled = true end
  if SFA_DB_Char.enemyEnabled    == nil then SFA_DB_Char.enemyEnabled    = true end

  -- Per-character: voice alert when builder-spender resource is full
  SFA_DB_Char.resourceVoiceAlerts = SFA_DB_Char.resourceVoiceAlerts or {}
  if SFA_DB_Char.resourceVoiceAlerts.enabled == nil then SFA_DB_Char.resourceVoiceAlerts.enabled = false end

  -- Per-character: proc ready voice alerts + monitored spells
  SFA_DB_Char.procReadyAlerts = SFA_DB_Char.procReadyAlerts or {}
  if SFA_DB_Char.procReadyAlerts.enabled == nil then SFA_DB_Char.procReadyAlerts.enabled = false end
  SFA_DB_Char.procReadyAlerts.spells    = SFA_DB_Char.procReadyAlerts.spells    or {}
  SFA_DB_Char.procReadyAlerts.cooldowns = SFA_DB_Char.procReadyAlerts.cooldowns or {}

  -- Merge defaults for clicks if not yet set per character
  local defaultButtons = { "LeftButton", "RightButton", "MiddleButton" }
  for _, btn in ipairs(defaultButtons) do
    if SFA_DB_Char.clicks.friendly[btn] == nil then
      SFA_DB_Char.clicks.friendly[btn] = self.defaults.friendly.clicks[btn] or ""
    end
    if SFA_DB_Char.clicks.enemy[btn] == nil then
      SFA_DB_Char.clicks.enemy[btn] = self.defaults.enemy.clicks[btn] or ""
    end
  end
  self.charDB = SFA_DB_Char
end

-- Returns a short human-readable label for the current spec, e.g.
-- "Feral", or "No specialization" when none is selected.
function SFA:GetCurrentSpecName()
  if GetSpecialization and GetSpecializationInfo then
    local ok, idx = pcall(GetSpecialization)
    if ok and idx then
      local ok2, _, name = pcall(GetSpecializationInfo, idx)
      if ok2 and name and name ~= "" then
        return name
      end
    end
  end
  return "No specialization"
end

function SFA:GetGroupDB(group)
  return self.db and self.db[group]
end

-- Per-character: friendly / enemy enabled
function SFA:GetCharEnabled(group)
  if not self.charDB then return true end
  local key = (group == "friendly") and "friendlyEnabled" or "enemyEnabled"
  local v = self.charDB[key]
  return (v == nil) and true or v
end

function SFA:SetCharEnabled(group, val)
  if not self.charDB then return end
  local key = (group == "friendly") and "friendlyEnabled" or "enemyEnabled"
  self.charDB[key] = val and true or false
end

-- Per-character: resource voice alert enabled
function SFA:GetCharResourceVoiceEnabled()
  return self.charDB and self.charDB.resourceVoiceAlerts and
         self.charDB.resourceVoiceAlerts.enabled == true
end

function SFA:SetCharResourceVoiceEnabled(val)
  if not self.charDB then return end
  self.charDB.resourceVoiceAlerts = self.charDB.resourceVoiceAlerts or {}
  self.charDB.resourceVoiceAlerts.enabled = val and true or false
end

-- Per-character: proc ready config (enabled + spells list)
function SFA:GetCharProcReadyConfig()
  if not self.charDB then return nil end
  self.charDB.procReadyAlerts = self.charDB.procReadyAlerts or {}
  self.charDB.procReadyAlerts.enabled   = self.charDB.procReadyAlerts.enabled   or false
  self.charDB.procReadyAlerts.spells    = self.charDB.procReadyAlerts.spells    or {}
  self.charDB.procReadyAlerts.cooldowns = self.charDB.procReadyAlerts.cooldowns or {}

  -- SavedVariables can turn numeric table keys into strings on reload. Normalize
  -- both tables so every spell ID is a number key. Without this, lookups like
  -- cfg.spells[numericID] miss (the key is "1244258" not 1244258), which broke
  -- the spell-cast bookkeeping and caused proc alerts to repeat endlessly.
  local spells = self.charDB.procReadyAlerts.spells
  local fixedSpells = {}
  for k, v in pairs(spells) do
    local nk = tonumber(k)
    if nk then fixedSpells[nk] = v else fixedSpells[k] = v end
  end
  self.charDB.procReadyAlerts.spells = fixedSpells

  local cds = self.charDB.procReadyAlerts.cooldowns
  local fixedCds = {}
  for k, v in pairs(cds) do
    local nk = tonumber(k)
    if nk then fixedCds[nk] = v else fixedCds[k] = v end
  end
  self.charDB.procReadyAlerts.cooldowns = fixedCds

  return self.charDB.procReadyAlerts
end

-- Returns the current player's specialization ID (e.g. 103 = Feral, 104 = Guardian),
-- or nil if it cannot be determined (then we fall back to legacy shared macros).
function SFA:GetCurrentSpecID()
  if GetSpecialization and GetSpecializationInfo then
    local ok, idx = pcall(GetSpecialization)
    if ok and idx then
      local ok2, specID = pcall(GetSpecializationInfo, idx)
      if ok2 and specID and specID > 0 then
        return specID
      end
    end
  end
  return nil
end

-- Returns the friendly/enemy click table for a given spec, creating it if needed.
-- On first access for a spec, it is seeded from the legacy shared clicks so the
-- player keeps their existing macros instead of starting empty.
function SFA:GetSpecClickTable(group)
  if not self.charDB then return nil end
  local specID = self:GetCurrentSpecID()
  if not specID then
    -- No spec info available: use legacy shared storage.
    self.charDB.clicks = self.charDB.clicks or {}
    self.charDB.clicks[group] = self.charDB.clicks[group] or {}
    return self.charDB.clicks[group]
  end

  self.charDB.clicksBySpec = self.charDB.clicksBySpec or {}
  local specBucket = self.charDB.clicksBySpec[specID]
  if not specBucket then
    specBucket = {}
    self.charDB.clicksBySpec[specID] = specBucket
  end

  if not specBucket[group] then
    specBucket[group] = {}
    -- Seed from legacy shared clicks (if any) so existing setups carry over.
    local legacy = self.charDB.clicks and self.charDB.clicks[group]
    if type(legacy) == "table" then
      for btn, txt in pairs(legacy) do
        specBucket[group][btn] = txt
      end
    end
  end
  return specBucket[group]
end

function SFA:GetClickMacro(group, button)
  local tbl = self:GetSpecClickTable(group)
  return (tbl and tbl[button]) or ""
end

function SFA:SetClickMacro(group, button, text)
  local tbl = self:GetSpecClickTable(group)
  if not tbl then return end
  tbl[button] = text or ""
end
