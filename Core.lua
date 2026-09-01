local addonName, SFA = ...
SFA = _G[addonName] or SFA

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitAffectingCombat = UnitAffectingCombat
local UnitCanAttack = UnitCanAttack
local UnitIsEnemy = UnitIsEnemy
local UnitIsUnit = UnitIsUnit
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue
local C_Timer = C_Timer
local C_NamePlate = C_NamePlate
local C_QuestLog = C_QuestLog

local function GetAddonVersion()
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(addonName, "Version") or "Unknown"
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(addonName, "Version") or "Unknown"
  end
  return "Unknown"
end

SFA.auraDebug = false -- toggled by /sfaauradebug or the Debug options tab; synced with self.db.auraDebugEnabled at login so it survives /reload

-- Sets aura-debug chat printing on/off and persists the choice to
-- self.db.auraDebugEnabled (a plain SavedVariable field) so it survives
-- /reload -- previously this was only a runtime table field that silently
-- reset to off on every reload.
function SFA:SetAuraDebug(enabled)
  self.auraDebug = enabled and true or false
  if self.db then
    self.db.auraDebugEnabled = self.auraDebug
  end
end

-- ---------------------------------------------------------------------
-- Persisted diagnostic log. taint.log (Blizzard's own taint tracer) turned
-- out to not cover the "secret value" access-block introduced by Midnight's
-- Secret Values system at all -- it only sees classic taint (global var
-- reads/writes, blocked protected-function calls), not this newer,
-- separate restriction. So instead we log our own trace directly into a
-- SavedVariable: it survives to disk on /reload or logout (same as any
-- other addon SavedVariable, under the account's SavedVariables folder),
-- with no dependency on Blizzard debug cvars at all. /sfaclearlog resets it
-- before a repro run so the log stays small and easy to read.
-- ---------------------------------------------------------------------
SFA_DebugLog = SFA_DebugLog or {}
local SFA_LOG_MAX = 1000
function SFA:Log(fmt, ...)
  -- Gated on the Enable checkbox (self.auraDebug): previously this wrote
  -- unconditionally regardless of the toggle, so the log kept filling up
  -- even with debug disabled. Now nothing is appended while disabled.
  if not self.auraDebug then return end
  local okFmt, msg = pcall(string.format, fmt, ...)
  if not okFmt then msg = tostring(fmt) end
  local t = (GetTime and GetTime()) or 0
  SFA_DebugLog[#SFA_DebugLog + 1] = string.format("[%.2f] %s", t, msg)
  if #SFA_DebugLog > SFA_LOG_MAX then
    table.remove(SFA_DebugLog, 1)
  end
end

-- Like SFA:Log, but bypasses the Enable-debug checkbox entirely -- reserved
-- for diagnostics that fire from live gameplay (e.g. a click on the native
-- arena frame), where relying on the user to remember to enable debug first
-- has repeatedly wasted whole test rounds (see project notes, 0.24.28/29).
-- Capped at SFA_FORCE_LOG_MAX total entries for the addon's lifetime this
-- session, so an unexpectedly chatty event can't quietly fill/roll the
-- entire 400-entry ring buffer on its own.
local SFA_ForceLogCount = 0
local SFA_FORCE_LOG_MAX = 40
function SFA:LogForce(fmt, ...)
  if SFA_ForceLogCount >= SFA_FORCE_LOG_MAX then return end
  SFA_ForceLogCount = SFA_ForceLogCount + 1
  local okFmt, msg = pcall(string.format, fmt, ...)
  if not okFmt then msg = tostring(fmt) end
  local t = (GetTime and GetTime()) or 0
  SFA_DebugLog[#SFA_DebugLog + 1] = string.format("[%.2f] %s", t, msg)
  if #SFA_DebugLog > SFA_LOG_MAX then
    table.remove(SFA_DebugLog, 1)
  end
end
local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff7cc6ffSFA:|r " .. tostring(msg))
end
SFA.Print = Print

function SFA:IsValidQuestIndicatorMob(unit)
  if not unit or not UnitExists(unit) then
    return false
  end

  -- Quest/scenario indicators are only valid for attackable, alive mobs.
  -- Some scenario mobs are attackable without always passing UnitIsEnemy reliably,
  -- so use UnitCanAttack as the primary hostile check.
  if UnitCanAttack and not UnitCanAttack("player", unit) then return false end
  if UnitIsEnemy and not UnitCanAttack and not UnitIsEnemy("player", unit) then return false end
  if UnitIsDead(unit) then return false end
  if UnitIsPlayer(unit) then return false end
  if UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit) then return false end

  return true
end

function SFA:GetQuestTooltipScanner()
  if self.questTooltipScanner then
    return self.questTooltipScanner
  end

  local scanner = CreateFrame("GameTooltip", "SFA_QuestTooltipScanner", UIParent, "GameTooltipTemplate")
  scanner:SetOwner(UIParent, "ANCHOR_NONE")
  self.questTooltipScanner = scanner
  return scanner
end

function SFA:TooltipLineStartsWithDash(text)
  if not text then return false end

  local ok, result = pcall(function()
    text = tostring(text)
    text = text:match("^%s*(.-)%s*$") or text
    return text:find("^%-") ~= nil
  end)

  return ok and result or false
end

function SFA:GetTooltipDataLineText(line)
  if not line then return nil end

  if TooltipUtil and TooltipUtil.SurfaceArgs then
    pcall(TooltipUtil.SurfaceArgs, line)
  end

  return line.leftText or line.text or line.rightText
end

function SFA:HasQuestObjectiveTooltip(unit)
  -- Prefer the tooltip data API. Reading GameTooltip FontString text on nameplates
  -- can return protected/secret strings and taint string comparisons.
  if C_TooltipInfo and C_TooltipInfo.GetUnit then
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if ok and data and data.lines and #data.lines > 4 then
      local lineText = self:GetTooltipDataLineText(data.lines[5])
      if self:TooltipLineStartsWithDash(lineText) then
        return true
      end

      -- In scenarios, Blizzard can expose the fifth tooltip line as a protected/secret
      -- string. If the unit is already validated as an attackable mob and the tooltip
      -- has the objective-style layout (>4 lines), keep the indicator active instead
      -- of failing the string comparison. This is what catches scenario objectives.
      return true
    end
  end

  -- Do NOT fall back to GameTooltip:SetUnit here. In PvP/arena and some
  -- protected UI paths, SetUnit can taint Blizzard tooltip data and throw
  -- secret-value errors from GameTooltip:SetWatch. C_TooltipInfo is the safe
  -- path; if it does not provide usable objective lines, fail closed.
  return false
end

function SFA:IsQuestUnit(unit)
  if not self:IsValidQuestIndicatorMob(unit) then
    return false
  end

  if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
    local ok, result = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
    if ok and result then
      return true
    end
  end

  return self:HasQuestObjectiveTooltip(unit)
end


local SFA_BUILDER_SPENDER_POWER = {
  DRUID = 4,      -- Combo Points
  ROGUE = 4,      -- Combo Points
  PALADIN = 9,    -- Holy Power
  MONK = 12,      -- Chi
  WARLOCK = 7,    -- Soul Shards
  EVOKER = 19,    -- Essence
}

local SFA_RESOURCE_VOICE_INFO = {
  DRUID = { enum = "ComboPoints", fallback = 4, label = "COMBO FULL", file = "combo_full.ogg", tts = "Combo Points Full" },
  ROGUE = { enum = "ComboPoints", fallback = 4, label = "COMBO FULL", file = "combo_full.ogg", tts = "Combo Points Full" },
  PALADIN = { enum = "HolyPower", fallback = 9, label = "HOLY POWER FULL", file = "holy_power_full.ogg", tts = "Holy Power Full" },
  MONK = { enum = "Chi", fallback = 12, label = "CHI FULL", file = "chi_full.ogg", tts = "Chi Full" },
  WARLOCK = { enum = "SoulShards", fallback = 7, label = "SOUL SHARDS FULL", file = "soul_shards_full.ogg", tts = "Soul Shards Full" },
  EVOKER = { enum = "Essence", fallback = 19, label = "ESSENCE FULL", file = "essence_full.ogg", tts = "Essence Full" },
}

function SFA:GetBuilderSpenderResourceInfo()
  local _, classTag = UnitClass("player")
  if not classTag then return nil end

  local info = SFA_RESOURCE_VOICE_INFO[classTag]
  if not info then return nil end

  local powerType = info.fallback
  if Enum and Enum.PowerType and info.enum and Enum.PowerType[info.enum] then
    powerType = Enum.PowerType[info.enum]
  end

  return powerType, info
end

function SFA:GetBuilderSpenderPowerType()
  local powerType = self:GetBuilderSpenderResourceInfo()
  return powerType
end

function SFA:GetResourceVoiceVolumeFile(info)
  if not (info and info.file) then return nil end

  local cfg = self.db and self.db.other and self.db.other.resourceVoiceAlerts
  local sliderVolume = tonumber(cfg and cfg.volume) or 5
  sliderVolume = math.floor(sliderVolume + 0.5)

  if sliderVolume < 0 then sliderVolume = 0 end
  if sliderVolume > 10 then sliderVolume = 10 end
  if sliderVolume == 0 then return nil, 0 end

  -- PRO voice-pack logic: uses *_1.ogg and *_2.ogg variants.
  -- Not random; it alternates predictably for less repetitive alerts.
  local baseFile = info.file:gsub("%.ogg$", "")
  self.resourceVoiceVariantIndex = (self.resourceVoiceVariantIndex == 1) and 2 or 1
  local file = baseFile .. "_" .. tostring(self.resourceVoiceVariantIndex) .. ".ogg"

  return file, sliderVolume
end

function SFA:GetResourceVoiceStyle()
  local cfg = self.db and self.db.other and self.db.other.resourceVoiceAlerts
  local style = cfg and cfg.voiceStyle or "male"
  if style ~= "female" then
    style = "male"
  end
  return style
end

function SFA:GetResourceVoiceLayerCount(sliderVolume)
  sliderVolume = tonumber(sliderVolume) or 5
  if sliderVolume <= 0 then return 0 end
  if sliderVolume <= 3 then return 1 end
  if sliderVolume <= 7 then return 2 end
  return 3
end

function SFA:PlayResourceVoiceFile(ignoreFullCheck)
  local cfg = self.db and self.db.other and self.db.other.resourceVoiceAlerts
  if not cfg then return end
  if not self:GetCharResourceVoiceEnabled() then return end
  if not ignoreFullCheck and not self:IsBuilderSpenderFull() then return end

  local powerType, info = self:GetBuilderSpenderResourceInfo()
  if not (powerType and info) then return end

  local sliderVolume = tonumber(cfg.volume) or 5
  sliderVolume = math.floor(sliderVolume + 0.5)
  if sliderVolume <= 0 then return end
  if sliderVolume > 10 then sliderVolume = 10 end

  -- Speak the resource name (e.g. "Combo Points Full") via TTS. No audio clips.
  if info.tts then self:SpeakViaTTS(info.tts, sliderVolume) end
end
function SFA:PlayFullResourceVoiceReminder()
  local cfg = self.db and self.db.other and self.db.other.resourceVoiceAlerts
  if not (cfg and cfg.enabled) then return end
  if not self:IsBuilderSpenderFull() then return end

  local now = GetTime and GetTime() or 0
  local cooldown = tonumber(cfg.cooldown) or 1.0
  if cooldown < 0 then cooldown = 0 end
  if self.lastResourceVoiceTime and (now - self.lastResourceVoiceTime) < cooldown then return end

  self.lastResourceVoiceTime = now
  self:PlayResourceVoiceFile(false)
end

function SFA:PreviewFullResourceVoice()
  local now = GetTime and GetTime() or 0
  if self.lastResourceVoicePreviewTime and (now - self.lastResourceVoicePreviewTime) < 0.35 then return end
  self.lastResourceVoicePreviewTime = now
  self:PlayResourceVoiceFile(true)
end

function SFA:GetProcReadyConfig()
  return self:GetCharProcReadyConfig()
end

function SFA:AddProcReadySpell(spellID)
  local ok, id = pcall(function() return tonumber(spellID) end)
  if not ok or not id then return end
  local cfg = self:GetProcReadyConfig()
  if not cfg then return end
  cfg.spells[id] = true
  self:GetProcReadyKnownCooldown(id)
  self.procReadyState = self.procReadyState or {}
  self.procReadyState[id] = { announced = false, lastAlert = 0 }
  local spellName = self:GetSpellNameSafe(id)
  Print(spellName and ("Added proc ready alert: " .. id .. " (" .. spellName .. ")") or ("Added proc ready alert: " .. id))
  if self.RefreshProcReadyUI then self:RefreshProcReadyUI() end
end

function SFA:RemoveProcReadySpell(spellID)
  local ok, id = pcall(function() return tonumber(spellID) end)
  if not ok or not id then return end
  local cfg = self:GetProcReadyConfig()
  if cfg and cfg.spells then cfg.spells[id] = nil end
  if self.procReadyState then self.procReadyState[id] = nil end
  local spellName = self:GetSpellNameSafe(id)
  Print(spellName and ("Removed proc ready alert: " .. id .. " (" .. spellName .. ")") or ("Removed proc ready alert: " .. id))
  if self.RefreshProcReadyUI then self:RefreshProcReadyUI() end
end


function SFA:GetProcReadyKnownCooldown(spellID)
  local id = tonumber(spellID)
  if not id then return nil end

  local cfg = self:GetProcReadyConfig()
  local cached = cfg and cfg.cooldowns and tonumber(cfg.cooldowns[id])
  if cached and cached > 0 then return cached end

  -- Cache the base cooldown only outside combat. This is informational/fallback only;
  -- the live ready check below does not compare cooldown numbers in combat.
  if not (InCombatLockdown and InCombatLockdown()) and GetSpellBaseCooldown then
    local ok, baseMS = pcall(GetSpellBaseCooldown, id)
    if ok and type(baseMS) == "number" and baseMS and baseMS > 0 then
      cfg.cooldowns = cfg.cooldowns or {}
      cfg.cooldowns[id] = baseMS / 1000
      return cfg.cooldowns[id]
    end
  end

  return nil
end

function SFA:NoteProcReadySpellCast(spellID)
  local id = tonumber(spellID)
  if not id then return end
  local cfg = self:GetProcReadyConfig()
  if not (cfg and cfg.spells and cfg.spells[id]) then return end

  self.procReadyState = self.procReadyState or {}
  local state = self.procReadyState[id] or { announced = false, lastAlert = 0 }
  self.procReadyState[id] = state

  -- Just cast: treat as on cooldown now (the cooldown API may lag a moment).
  -- Mark announced so the brief post-cast "still looks ready" window doesn't
  -- fire a false alert; reset streaks so re-arm needs fresh consistent ticks.
  state.announced = true
  state.readyStreak = 0
  state.notReadyStreak = 0
  state.lastCast = GetTime and GetTime() or 0
  state.wasReady = false
  state.wasOnCooldown = true
end

function SFA:IsProcReadySpellOnCooldown(spellID)
  local id = tonumber(spellID)
  if not id then return true end

  -- IMPORTANT: do not read/compare startTime or duration here.
  -- In protected combat paths those cooldown numbers can be "secret" and taint.
  -- Boolean flags are enough for the generic proc-ready state machine.
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, cd = pcall(C_Spell.GetSpellCooldown, id)
    if ok and type(cd) == "table" then
      local active = (cd.isActive == true)
      local gcdOnly = (cd.isOnGCD == true)

      -- Real cooldown active: not ready.
      -- GCD-only active: do not treat it as the spell's own cooldown.
      if active and not gcdOnly then
        return true
      end

      return false
    end
  end

  -- If cooldown status cannot be read safely, be conservative and avoid a false alert.
  return true
end

function SFA:IsProcReadySpellUsable(spellID)
  local id = tonumber(spellID)
  if not id then return false end

  local usableClassic = nil
  if IsUsableSpell then
    local ok, canUse = pcall(IsUsableSpell, id)
    if ok then usableClassic = (canUse == true) end
  end

  -- Classic usability is stricter and matches action button usability well.
  -- If it says false, do not let another API force a ready alert.
  if usableClassic ~= nil then
    return usableClassic == true
  end

  if C_Spell and C_Spell.IsSpellUsable then
    local ok, canUse = pcall(C_Spell.IsSpellUsable, id)
    if ok then return canUse == true end
  end

  return false
end

function SFA:IsProcReadySpellReady(spellID)
  local id = tonumber(spellID)
  if not id then return false end

  self.procReadyState = self.procReadyState or {}
  local state = self.procReadyState[id] or { announced = false, lastAlert = 0 }
  self.procReadyState[id] = state

  local usable = self:IsProcReadySpellUsable(id)
  local onCooldown = self:IsProcReadySpellOnCooldown(id)

  state.wasReady = (usable == true and onCooldown ~= true)
  state.wasUsable = usable == true
  state.wasOnCooldown = onCooldown == true

  return state.wasReady == true
end

function SFA:GetTTSVoiceObject()
  if self._ttsVoiceCache ~= nil then
    if self._ttsVoiceCache == false then return nil end
    return self._ttsVoiceCache
  end
  local voice
  if C_VoiceChat and C_VoiceChat.GetTtsVoices then
    local ok, v = pcall(C_VoiceChat.GetTtsVoices)
    if ok and type(v) == "table" and v[1] then voice = v[1] end
  end
  if not voice and _G.GetTTSVoices then
    local ok, v = pcall(_G.GetTTSVoices)
    if ok and type(v) == "table" then voice = v[1] end
  end
  self._ttsVoiceCache = voice or false
  return voice
end

-- Speak arbitrary text via the Blizzard TTS engine (the one that actually
-- plays audio on Midnight). The 0-10 addon slider maps to the engine's
-- internal 0-100 volume so louder slider = louder speech. Returns true on success.
function SFA:SpeakViaTTS(text, sliderVolume)
  if not text or text == "" then return false end
  if not _G.TextToSpeech_Speak then return false end

  local voice = self:GetTTSVoiceObject()
  if not voice then return false end

  local vol = tonumber(sliderVolume) or 5
  vol = math.floor(vol + 0.5)
  if vol <= 0 then return false end
  if vol > 10 then vol = 10 end

  -- Guard against re-triggering the same announcement back-to-back (e.g. from
  -- flickering cooldown reads), so we never stack overlapping speech.
  local now = GetTime and GetTime() or 0
  if self._lastTTSStart and (now - self._lastTTSStart) < 0.6 then
    return true
  end
  self._lastTTSStart = now

  -- Volume is controlled by the TTS engine's own volume setting (max here).
  if C_TTSSettings and C_TTSSettings.SetSpeechVolume then
    pcall(C_TTSSettings.SetSpeechVolume, 100)
  end
  if C_TTSSettings and C_TTSSettings.SetSpeechRate then
    pcall(C_TTSSettings.SetSpeechRate, 0)
  end

  -- "Audio ducking": briefly lower the music and ambience so the spoken alert
  -- stands out, then restore. The slider controls how aggressively other audio
  -- is dipped (higher slider = quieter background = the voice is more prominent).
  self:DuckAudioForTTS(vol)

  -- Speak exactly ONCE. TextToSpeech_Speak queues utterances and plays them
  -- sequentially, so issuing multiple copies produced "Chomp Ready, Chomp
  -- Ready, Chomp Ready..." repeated aloud - that was the repetition being heard.
  local ok = pcall(_G.TextToSpeech_Speak, text, voice)
  return ok == true
end

function SFA:DuckAudioForTTS(sliderVolume)
  if not (GetCVar and SetCVar) then return end

  local vol = tonumber(sliderVolume) or 5
  if vol < 1 then vol = 1 end
  if vol > 10 then vol = 10 end

  -- How much of the background volume to keep, scaled by the slider:
  --   slider 1  -> keep ~90% (barely ducked)
  --   slider 10 -> keep ~20% (strongly ducked, voice very prominent)
  local keepFactor = 0.9 - (vol - 1) * (0.7 / 9)
  if keepFactor < 0.1 then keepFactor = 0.1 end
  if keepFactor > 1.0 then keepFactor = 1.0 end

  -- CVars whose volume we temporarily reduce so speech cuts through.
  local cvars = { "Sound_MusicVolume", "Sound_AmbienceVolume" }

  -- Save the originals only if we aren't already in the middle of a duck, so a
  -- second alert during the dip doesn't capture the already-lowered values.
  if not self._ttsDucking then
    self._ttsDuckSaved = {}
    for _, cv in ipairs(cvars) do
      local ok, v = pcall(GetCVar, cv)
      if ok and v ~= nil then
        self._ttsDuckSaved[cv] = v
      end
    end
    self._ttsDucking = true
  end

  -- Apply the reduced volumes.
  for _, cv in ipairs(cvars) do
    local saved = self._ttsDuckSaved and self._ttsDuckSaved[cv]
    local base = tonumber(saved)
    if base ~= nil then
      pcall(SetCVar, cv, tostring(base * keepFactor))
    end
  end

  -- (Re)schedule restoration. Each alert pushes the restore time out so the
  -- background stays dipped until speech is actually done (~2s per utterance).
  self._ttsDuckToken = (self._ttsDuckToken or 0) + 1
  local myToken = self._ttsDuckToken
  if C_Timer and C_Timer.After then
    C_Timer.After(2.0, function()
      if not SFA then return end
      -- Only the most recent scheduled restore runs, to avoid restoring early
      -- when alerts overlap.
      if SFA._ttsDuckToken ~= myToken then return end
      SFA:RestoreAudioAfterTTS()
    end)
  end
end

function SFA:RestoreAudioAfterTTS()
  if not (SetCVar and self._ttsDuckSaved) then
    self._ttsDucking = false
    return
  end
  for cv, v in pairs(self._ttsDuckSaved) do
    if v ~= nil then
      pcall(SetCVar, cv, tostring(v))
    end
  end
  self._ttsDuckSaved = nil
  self._ttsDucking = false
end

function SFA:SpeakProcReadySpellName(spellID, sliderVolume)
  -- Announce "<SpellName> Ready" via Text-To-Speech.
  local id = tonumber(spellID)
  if not id then return false end
  local name = self:GetSpellNameSafe(id)
  if not name or name == "" then return false end
  return self:SpeakViaTTS(name .. " Ready", sliderVolume)
end

function SFA:PlayProcReadyVoice(spellID)
  local cfg = self.db and self.db.other and self.db.other.resourceVoiceAlerts
  local sliderVolume = tonumber(cfg and cfg.volume) or 5
  sliderVolume = math.floor(sliderVolume + 0.5)
  if sliderVolume <= 0 then return end
  if sliderVolume > 10 then sliderVolume = 10 end

  -- Speak the spell name (e.g. "Chomp Ready") via TTS. No local audio clips.
  self:SpeakProcReadySpellName(spellID, sliderVolume)
end

function SFA:ResetProcReadyStates()
  self.procReadyState = self.procReadyState or {}
  for _, state in pairs(self.procReadyState) do
    if type(state) == "table" then state.announced = false end
  end
end

function SFA:StopProcReadyTicker()
  if self.procReadyTicker and self.procReadyTicker.Cancel then
    self.procReadyTicker:Cancel()
  end
  self.procReadyTicker = nil
end

function SFA:StartProcReadyTicker()
  local cfg = self:GetProcReadyConfig()
  if not (cfg and cfg.enabled and InCombatLockdown and InCombatLockdown()) then
    self:StopProcReadyTicker()
    return
  end
  if self.procReadyTicker then return end
  if C_Timer and C_Timer.NewTicker then
    self.procReadyTicker = C_Timer.NewTicker(0.20, function()
      if not (SFA and SFA.UpdateProcReadyAlerts) then return end
      if not InCombatLockdown() then
        SFA:StopProcReadyTicker()
        SFA:ResetProcReadyStates()
        return
      end
      SFA:UpdateProcReadyAlerts()
    end)
  end
end

function SFA:UpdateProcReadyAlerts()
  local cfg = self:GetProcReadyConfig()
  if not (cfg and cfg.enabled) then return end

  if not InCombatLockdown() then
    self:ResetProcReadyStates()
    return
  end

  self.procReadyState = self.procReadyState or {}
  local now = GetTime and GetTime() or 0
  local voiceCfg = self.db and self.db.other and self.db.other.resourceVoiceAlerts
  local cooldown = tonumber(voiceCfg and voiceCfg.cooldown) or 1.0
  if cooldown < 0 then cooldown = 0 end

  for spellID, enabled in pairs(cfg.spells or {}) do
    local id = tonumber(spellID)
    if enabled and id then
      local state = self.procReadyState[id]
      if not state then
        state = { announced = false, lastAlert = 0 }
        self.procReadyState[id] = state
      end

      local usable = self:IsProcReadySpellUsable(id)
      local onCd = self:IsProcReadySpellOnCooldown(id)
      local ready = (usable == true and onCd ~= true)

      -- Announce when the spell becomes ready and we haven't announced this
      -- activation yet. This fires on the rising edge for both:
      --   Feral Frenzy: ready the moment it leaves cooldown.
      --   Chomp: ready the moment its proc/condition turns usable while off CD.
      if ready and not state.announced and (now - (state.lastAlert or 0)) >= cooldown then
        state.announced = true
        state.lastAlert = now
        self:PlayProcReadyVoice(id)
        if self.procReadyDebug then
          DEFAULT_CHAT_FRAME:AddMessage("|cff7cc6ffSFA:|r announce " .. id .. " usable=" .. tostring(usable) .. " onCD=" .. tostring(onCd))
        end
      end

      -- Re-arm when the spell has actually gone on cooldown (reliable "used"
      -- signal), OR when it has been clearly NOT usable for several consecutive
      -- ticks. The multi-tick requirement filters out the rapid 1-tick flicker
      -- of the usable flag (e.g. Feral Frenzy with energy) that previously
      -- caused repeated alerts, while still re-arming for proc-gated spells like
      -- Chomp whose proc genuinely drops for a sustained period.
      if not ready then
        state.notUsableStreak = (state.notUsableStreak or 0) + 1
      else
        state.notUsableStreak = 0
      end

      local wentOnCd = (onCd == true)
      local sustainedNotReady = (state.notUsableStreak or 0) >= 4  -- ~0.8s

      if state.announced and (wentOnCd or sustainedNotReady) then
        state.announced = false
        if self.procReadyDebug then
          DEFAULT_CHAT_FRAME:AddMessage("|cff7cc6ffSFA:|r re-arm " .. id .. (wentOnCd and " (on cooldown)" or " (proc dropped)"))
        end
      end
    end
  end
end

function SFA:CheckFullResourceVoiceOnReachFull()
  local cfg = self.db and self.db.other and self.db.other.resourceVoiceAlerts
  if not cfg then return end
  if not self:GetCharResourceVoiceEnabled() then return end

  local isFull = self:IsBuilderSpenderFull()
  if isFull and not self.wasBuilderSpenderFull then
    self.wasBuilderSpenderFull = true
    self:PlayFullResourceVoiceReminder()
  elseif not isFull then
    self.wasBuilderSpenderFull = false
  end
end

function SFA:IsBuilderSpenderFull()
  if not (self.db and self.db.other and self.db.other.showBuilderSpenderIndicator) then
    return false
  end

  local powerType = self:GetBuilderSpenderPowerType()
  if not powerType then return false end

  local current = UnitPower("player", powerType) or 0
  local maxPower = UnitPowerMax("player", powerType) or 0

  if maxPower <= 0 then return false end

  return current >= maxPower
end

function SFA:ShouldShowComboCircle()
  return self:IsBuilderSpenderFull()
end

function SFA:ApplyBuilderSpenderOrbVisual(orb)
  if not orb then return end

  -- fixed clean red color
  orb:SetVertexColor(1, 0.15, 0.15, 1)

  if orb.SFAPulse then
    orb.SFAPulse:Stop()
    orb.SFAPulse = nil
  end

  orb:SetScale(1)
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

  -- Story Mode / raid nameplates may be forbidden/protected.
  -- Never create regions directly on a ForbiddenNamePlate; attach to UnitFrame when safe.
  local parent = frame.UnitFrame or frame
  if not parent or not parent.CreateFontString then return nil end
  if parent.IsForbidden and parent:IsForbidden() then return nil end

  if parent.SFAQuestIcon then
    return parent.SFAQuestIcon
  end

  local icon = parent:CreateFontString(nil, "OVERLAY")
  icon:SetFont("Fonts\\FRIZQT__.TTF", 18, "THICKOUTLINE")
  icon:SetText("!")
  icon:SetTextColor(1, 0.82, 0, 1)
  icon:SetShadowOffset(1, -1)
  icon:SetShadowColor(0, 0, 0, 1)

  local anchor = self:GetNameplateAnchor(frame)
  if anchor and not (anchor.IsForbidden and anchor:IsForbidden()) then
    icon:SetPoint("RIGHT", anchor, "LEFT", -18, 0)
  else
    icon:SetPoint("CENTER", parent, "TOP", 0, -10)
  end

  icon:Hide()
  parent.SFAQuestIcon = icon
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
    if anchor and not (anchor.IsForbidden and anchor:IsForbidden()) then
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

	local function HideComboOrb()
	if frame.SFAComboOrb then
    if frame.SFAComboOrb.SFAPulse then
      frame.SFAComboOrb.SFAPulse:Stop()
      frame.SFAComboOrb.SFAPulse = nil
    end
    frame.SFAComboOrb:SetScale(1)
    frame.SFAComboOrb:Hide()
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

    if frame.SFAComboOrb and self:ShouldShowComboCircle() then
      self:ApplyBuilderSpenderOrbVisual(frame.SFAComboOrb)
      frame.SFAComboOrb:Show()
      self:CheckFullResourceVoiceOnReachFull()
    else
      HideComboOrb()
    end
  else
    xMark:Hide()
    if frame.SFAComboCircle then frame.SFAComboCircle:Hide() end
    if frame.SFAComboDot then frame.SFAComboDot:Hide() end
    HideComboOrb()
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

local function SFA_CondHasTarget(condBody)
  if not condBody then return false end
  if condBody:find("@", 1, true) then return true end
  if condBody:lower():find("target%s*=") then return true end
  return false
end

-- Processes a single ";"-separated segment of a cast/use command,
-- injecting @<unit> into any conditional that lacks a target,
-- or prepending [@<unit>] when the segment has a spell but no conditional.
local function SFA_ProcessSegment(seg, unit)
  local leadWs = seg:match("^(%s*)") or ""
  local body = seg:sub(#leadWs + 1)

  -- Pull off all leading [..] conditional blocks
  local conds = {}
  while true do
    local cond = body:match("^(%[[^%]]*%])")
    if not cond then break end
    conds[#conds + 1] = cond
    body = body:sub(#cond + 1)
  end
  local spell = body

  if #conds == 0 then
    -- No conditional. If there's an actual spell, bind it to the frame unit.
    if spell:match("%S") then
      return leadWs .. "[@" .. unit .. "]" .. spell
    end
    return seg
  end

  local rebuilt = {}
  for _, cond in ipairs(conds) do
    local inner = cond:sub(2, -2) -- strip [ ]
    if SFA_CondHasTarget(inner) then
      rebuilt[#rebuilt + 1] = cond
    elseif inner:match("^%s*$") then
      rebuilt[#rebuilt + 1] = "[@" .. unit .. "]"
    else
      rebuilt[#rebuilt + 1] = "[@" .. unit .. "," .. inner .. "]"
    end
  end
  return leadWs .. table.concat(rebuilt) .. spell
end

-- Resolves a click macro for a given unit:
--   1. Replaces any explicit @unit token with @<unit> (legacy behavior).
--   2. Auto-injects @<unit> into cast/use clauses that have no target.
local function SFA_ResolveMacroForUnit(macroText, unit)
  macroText = tostring(macroText):gsub("@unit", "@" .. unit)

  local outLines = {}
  for line in (macroText .. "\n"):gmatch("(.-)\n") do
    local cmd, rest = line:match("^(%s*/%w+%s*)(.*)$")
    local lower = line:lower()
    local isCast = lower:find("^%s*/cast")
      or lower:find("^%s*/use")
      or lower:find("^%s*/target")
      or lower:find("^%s*/focus")
    if cmd and isCast then
      local segments = {}
      for seg in (rest .. ";"):gmatch("(.-);") do
        segments[#segments + 1] = SFA_ProcessSegment(seg, unit)
      end
      outLines[#outLines + 1] = cmd .. table.concat(segments, ";")
    else
      outLines[#outLines + 1] = line
    end
  end
  return table.concat(outLines, "\n")
end

-- Moved up (0.25.5 bugfix) to before every call site: this was previously
-- declared much further down the file, so any call to it from code defined
-- EARLIER (like the click-cast driver section right below) resolved to a
-- nil global instead of this local, throwing "attempt to call a nil value"
-- the moment it was ever actually reached. Confirmed via a live debug dump
-- (2026-08-31): "friendlyattr apply-native ok=false err=...Core.lua:1312:
-- attempt to call a nil value" -- one unconditional call to it inside
-- SFA_ApplyNativeClickToFrame's new capture-logging line (0.25.4) threw on
-- the very first frame processed, aborting the ENTIRE apply pass before any
-- frame got its click-cast attributes -- which is why click-cast broke
-- completely (not just the Ctrl+Alt menu feature) as soon as that line
-- started actually running. A second, older, latent instance of the same
-- bug also existed in the RegisterForClicks log line just below
-- (`okReg and "" or SFA_DescribeValue(regErr)`) -- it never manifested
-- before because Lua's short-circuit "and/or" only evaluates the
-- SFA_DescribeValue(regErr) branch when okReg is false, which in practice
-- it never was.
local function SFA_IsSecretSafe(v)
  if v == nil or not issecretvalue then return false end
  local ok, r = pcall(issecretvalue, v)
  return ok and r or false
end

local function SFA_DescribeValue(v)
  if v == nil then return "nil" end
  if SFA_IsSecretSafe(v) then return "<secret>" end
  local ok, s = pcall(tostring, v)
  return ok and s or "<unprintable>"
end

-- ---------------------------------------------------------------------
-- Secure click-cast attribute driver.
--
-- Writing to Blizzard's reserved action-button attributes (unit, type1-5,
-- macrotext1-5, *type1-5, *macrotext1-5) directly from insecure addon Lua
-- -- even a single, non-redundant write -- taints that execution. That
-- taint is what was escalating into a hard "*** ForceTaint_Strong ***"
-- block, which then prevented this addon from reading secret aura data
-- (HoTs/debuffs) in combat for the rest of the session.
--
-- The Blizzard-sanctioned fix (used by Cell, Clique, Grid2, VuhDo, etc.)
-- is to never write those attributes directly. Instead:
--   1. A single hidden "driver" frame is created with SecureHandlerBaseTemplate
--      + SecureHandlerAttributeTemplate.
--   2. Each unit button is registered with the driver via
--      SecureHandlerSetFrameRef -- itself a safe, non-tainting bridge from
--      insecure code into the secure world.
--   3. Insecure code only ever stages plain, arbitrary-named attributes
--      (sfa-pending-*) on the driver, then fires a trigger attribute.
--   4. The driver's _onattributechanged snippet -- which executes inside
--      Blizzard's secure/restricted environment, not as addon code -- is
--      the only thing that ever calls SetAttribute() with the reserved
--      names on the actual unit buttons. Because that write happens
--      inside a secure snippet, it does not accrue insecure-addon taint.
-- ---------------------------------------------------------------------

-- SecureHandlerBaseTemplate alone only provides the secure execution
-- environment (Run/Execute/SetFrameRef); it does NOT by itself wire up the
-- "_onattributechanged" attribute to actually fire when an attribute
-- changes. SecureHandlerAttributeTemplate is the template that does that
-- wiring (it also inherits SecureHandlerBaseTemplate). Without it, setting
-- "_onattributechanged" below was inert -- the snippet was stored but
-- never executed, so buttons never received their click attributes at
-- all, which is why click-casting stopped working entirely.
--
-- 0.25.0 redesign: this addon no longer renders its own unit frames, so
-- the driver only ever touches Blizzard-owned frames now ("sfa-apply-
-- native" below) -- it never writes the "unit" attribute, only ever
-- Left/Right/Middle-click type/macrotext, and only when the user has
-- actually configured that button.
local SFA_ClickDriver = CreateFrame("Frame", "SFA_ClickCastDriver", UIParent, "SecureHandlerBaseTemplate, SecureHandlerAttributeTemplate")
SFA_ClickDriver:Hide()

SFA_ClickDriver:SetAttribute("_onattributechanged", [==[
  if name == "sfa-apply-native" then
    -- Supplemental click-cast on a Blizzard-owned secure frame. Never
    -- touches "unit" -- that stays entirely Blizzard's. Each button's
    -- type/macrotext attributes are ONLY written when the matching
    -- "sfa-native-setN" flag is true, meaning the user has actually
    -- configured a macro for that button. An unconfigured button is left
    -- completely alone so Blizzard's default for it (left-click-to-target,
    -- right-click-menu, etc.) keeps working untouched.
    local btn = self:GetFrameRef(self:GetAttribute("sfa-apply-native-target"))
    if btn then
      -- 0.25.9 fix: each button now ALWAYS writes something, one way or
      -- the other -- either the configured macro (setN true) or an
      -- explicit nil/clear (setN false). Before this, an unconfigured
      -- button just skipped the whole block, which meant a button that
      -- USED to be configured (macro removed, or the whole group disabled
      -- via the new per-character enable checkbox) kept whatever type/
      -- macrotext it was last given -- Blizzard's default for that button
      -- never actually came back. Clearing explicitly hands control back.
      if self:GetAttribute("sfa-native-set1") then
        btn:SetAttribute("type1", self:GetAttribute("sfa-native-type1"))
        btn:SetAttribute("macrotext1", self:GetAttribute("sfa-native-macrotext1"))
        btn:SetAttribute("*type1", self:GetAttribute("sfa-native-type1"))
        btn:SetAttribute("*macrotext1", self:GetAttribute("sfa-native-macrotext1"))
      else
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("macrotext1", nil)
        btn:SetAttribute("*type1", nil)
        btn:SetAttribute("*macrotext1", nil)
      end
      if self:GetAttribute("sfa-native-set2") then
        btn:SetAttribute("type2", self:GetAttribute("sfa-native-type2"))
        btn:SetAttribute("macrotext2", self:GetAttribute("sfa-native-macrotext2"))
        btn:SetAttribute("*type2", self:GetAttribute("sfa-native-type2"))
        btn:SetAttribute("*macrotext2", self:GetAttribute("sfa-native-macrotext2"))
      else
        btn:SetAttribute("type2", nil)
        btn:SetAttribute("macrotext2", nil)
        btn:SetAttribute("*type2", nil)
        btn:SetAttribute("*macrotext2", nil)
      end
      if self:GetAttribute("sfa-native-set3") then
        btn:SetAttribute("type3", self:GetAttribute("sfa-native-type3"))
        btn:SetAttribute("macrotext3", self:GetAttribute("sfa-native-macrotext3"))
        btn:SetAttribute("*type3", self:GetAttribute("sfa-native-type3"))
        btn:SetAttribute("*macrotext3", self:GetAttribute("sfa-native-macrotext3"))
      else
        btn:SetAttribute("type3", nil)
        btn:SetAttribute("macrotext3", nil)
        btn:SetAttribute("*type3", nil)
        btn:SetAttribute("*macrotext3", nil)
      end
    end
  end
]==])

local SFA_ClickApplySeq = 0

-- Registers a unit button with the secure driver so the driver's snippet
-- can look it up later via GetFrameRef. Must be called once per button,
-- from insecure code (this specific API is designed to be safe to call
-- that way), typically right after the button is created.
--
-- refKey is an explicit ref-name override. SecureHandlerSetFrameRef only
-- needs SOME unique string key -- it does NOT have to be the frame's own
-- GetName() -- which matters because some of Blizzard's own native frames
-- (e.g. the individual member buttons inside the modern unified
-- "PartyFrame") are created anonymously (GetName() == nil) and would
-- otherwise be unreachable here. Falls back to frame:GetName() when no
-- refKey is given, for callers that only ever deal in named frames.
local function SFA_RegisterClickFrame(frame, refKey)
  if not frame then return end
  refKey = refKey or frame:GetName()
  if not refKey then return end
  frame.sfaNativeClickRefKey = refKey
  SecureHandlerSetFrameRef(SFA_ClickDriver, refKey, frame)
end

-- ---------------------------------------------------------------------
-- Supplemental click-cast on Blizzard's own native arena-enemy frames.
--
-- Found via /sfascanarena (2026-08-31, see project notes): Midnight's
-- replacement for the old ArenaEnemyFrame1-5 globals is
-- ArenaEnemyMatchFrame1-5, each a secure unit button already bound to
-- arena1-5. Unlike this addon's own enemy frames, Blizzard's frame isn't
-- subject to the Secret Values restriction, so it already shows real
-- CC/debuffs/role info. Explicit user request: keep this addon's own
-- frames exactly as they are, but ALSO let the user's configured
-- click-cast macros fire when clicking Blizzard's frame -- purely
-- additive, nothing here changes what SFA's own frames do.
--
-- This uses a SEPARATE, more restrictive driver path ("sfa-apply-native",
-- defined on SFA_ClickDriver above) than the addon's own frames use.
-- "unit" is never touched -- that stays Blizzard's own. Each button
-- (Left/Right/Middle/4/5, type1-5) is only ever written when the user has
-- actually configured a macro for it (a per-button "setN" flag on the
-- driver); an unconfigured button is left completely alone so Blizzard's
-- default for it (left-click-to-target, right-click-menu, etc.) keeps
-- working untouched. Found via live testing 2026-08-31: the original
-- version of this feature hardcoded Middle/4/5-only coverage on the
-- assumption that users keep Blizzard's Left/Right defaults -- wrong for
-- a user whose primary CC macro is on LeftButton, which this addon's own
-- frames already fully override. The setN-flag design generalizes to
-- both cases.
-- ---------------------------------------------------------------------

-- 0.24.39, ROOT CAUSE FOUND: the shown/visible dump (0.24.37) proved it --
-- ArenaEnemyMatchFrame1-5 report shown=true but visible=false (an ancestor
-- is hidden -- they're not actually on screen), while CompactArenaFrameMember
--1-5 (the "raid-style" arena panel, same unit-button family as compact
-- raid/party frames) report shown=true AND visible=true, with the exact
-- same unit=arenaN binding. This user has raid-style arena frames active,
-- so every click test so far landed on CompactArenaFrameMember -- a frame
-- our feature never wrote a single attribute to. That's why attributes were
-- always correct, RegisterForClicks always succeeded, and every hook on
-- ArenaEnemyMatchFrame1-5 (and its HealthBar/ManaBar) stayed silent no
-- matter what: none of it was the frame actually being clicked. Both
-- families use the identical type1-5/macrotext1-5/unit attribute
-- convention, so simply adding CompactArenaFrameMember1-5 here extends
-- every existing code path (attribute writes, RegisterForClicks, the
-- diagnostic hooks) to it for free -- writing harmless attributes to
-- whichever family isn't currently shown costs nothing.
local SFA_NATIVE_ARENA_FRAME_NAMES = {
  "ArenaEnemyMatchFrame1",
  "ArenaEnemyMatchFrame2",
  "ArenaEnemyMatchFrame3",
  "ArenaEnemyMatchFrame4",
  "ArenaEnemyMatchFrame5",
  "CompactArenaFrameMember1",
  "CompactArenaFrameMember2",
  "CompactArenaFrameMember3",
  "CompactArenaFrameMember4",
  "CompactArenaFrameMember5",
}

-- 0.25.0 redesign, step 1: supplemental click-cast on Blizzard's native
-- FRIENDLY frames (player/party/raid), mirroring the arena-enemy approach
-- above -- same lesson applies (see the arena "shown vs visible" saga in
-- the project notes): Blizzard exposes more than one frame family for the
-- same role depending on user display settings, so every plausible family
-- is listed here and whichever one isn't actually on screen just gets
-- harmless unused attribute writes. Covers:
--   - PlayerFrame (self)
--   - PartyMemberFrame1-4 (classic, non-raid-style party frames)
--   - CompactPartyFrameMember1-5 (raid-style party frames)
--   - CompactRaidFrame1-40 ("Combined Groups" raid layout)
--   - CompactRaidGroup1Member1 .. CompactRaidGroup8Member5 ("By Group" raid layout)
local SFA_NATIVE_FRIENDLY_FRAME_NAMES = (function()
  local names = { "PlayerFrame" }
  for i = 1, 4 do names[#names + 1] = "PartyMemberFrame" .. i end
  for i = 1, 5 do names[#names + 1] = "CompactPartyFrameMember" .. i end
  for i = 1, 40 do names[#names + 1] = "CompactRaidFrame" .. i end
  for g = 1, 8 do
    for m = 1, 5 do
      names[#names + 1] = "CompactRaidGroup" .. g .. "Member" .. m
    end
  end
  return names
end)()

-- Diagnostic helper (0.24.35): our OnClick/OnMouseDown/OnMouseUp hooks on
-- ArenaEnemyMatchFrame1-5 itself never fired even in a live test where the
-- user confirmed clicking did visibly select/target the unit. That means
-- the mouse click isn't landing on THIS frame object at all -- most likely
-- a child region (health bar, etc.) is the actual mouse-interactive widget
-- and is either handling the click itself or is simply what's on top under
-- the cursor. This walks the frame's mouse-enabled state and its direct
-- children (name + IsMouseEnabled) so we can see which sub-object is
-- actually positioned to receive the click.
local function SFA_DescribeFrameChildren(f)
  local okSelfMouse, selfMouse = pcall(f.IsMouseEnabled, f)
  local parts = { string.format("self.IsMouseEnabled=%s", tostring(okSelfMouse and selfMouse)) }

  local okChildren, children = pcall(function() return { f:GetChildren() } end)
  if not okChildren then
    parts[#parts + 1] = "children=<error>"
    return table.concat(parts, " ")
  end

  for i, child in ipairs(children) do
    local okName, name = pcall(child.GetName, child)
    local okType, objType = pcall(child.GetObjectType, child)
    local okMouse, mouseOn = pcall(child.IsMouseEnabled, child)
    parts[#parts + 1] = string.format("child%d=%s(type=%s,mouse=%s)", i,
      (okName and name) or "<unnamed>",
      (okType and objType) or "?",
      tostring(okMouse and mouseOn))
  end
  return table.concat(parts, " ")
end

local SFA_NATIVE_CLICK_ATTR_KEYS = {
  "type1", "macrotext1", "set1",
  "type2", "macrotext2", "set2",
  "type3", "macrotext3", "set3",
}

-- 0.25.6 bugfix: this used to skip the actual attribute write whenever
-- `desired` matched the last-applied signature we cached on the frame
-- object (frame.sfaNativeClickSig), on the assumption that identical
-- input means nothing needs to change on screen. That assumption breaks
-- for any frame Blizzard itself resets or recycles after we've applied to
-- it once -- which is exactly what happens to the anonymous/pooled party
-- and raid member buttons (and possibly others) on roster changes: our
-- cache still remembers "already applied successfully", so every later
-- pass with the same macros short-circuited and never rewrote the actual
-- type1-3/macrotext1-3 attributes Blizzard had since wiped, leaving every
-- managed frame stuck at nil despite ok=true and no error anywhere. Since
-- these writes are cheap and only run on discrete events (not every
-- frame), always writing unconditionally is the safe fix -- no more
-- caching, no more risk of a stale "already applied" belief going stale.
local function SFA_ApplyNativeClickDriver(frame, desired)
  local refKey = frame and frame.sfaNativeClickRefKey
  if not refKey then return end

  for _, key in ipairs(SFA_NATIVE_CLICK_ATTR_KEYS) do
    SFA_ClickDriver:SetAttribute("sfa-native-" .. key, desired[key])
  end
  SFA_ClickApplySeq = SFA_ClickApplySeq + 1
  SFA_ClickDriver:SetAttribute("sfa-apply-native-target", refKey)
  SFA_ClickDriver:SetAttribute("sfa-apply-native", SFA_ClickApplySeq)
end

-- Generic supplemental click-cast applier: takes any list of native
-- Blizzard secure unit-button frame names plus which per-spec macro table
-- ("friendly" or "enemy") to pull Left/Right/Middle macros from, and drives
-- them all through the same additive, non-tainting mechanism proven out on
-- arena frames (see SFA_ApplyNativeClickDriver above). "unit" is never
-- touched -- that stays entirely Blizzard's. Deliberately NOT gated on
-- InCombatLockdown(): only the actual reserved-attribute writes are
-- combat-restricted, and those happen inside the secure snippet, which
-- Blizzard explicitly allows to run during combat. Gating the staging
-- calls here was a proven bug on arena (2026-08-31 live test) -- roster/
-- combat updates fire constantly during a fight, so gating them out here
-- could mean a whole encounter passes without ever applying.
local SFA_NATIVE_CLICK_BUTTON_KEYS = {
  LeftButton = { "type1", "macrotext1", "set1" },
  RightButton = { "type2", "macrotext2", "set2" },
  MiddleButton = { "type3", "macrotext3", "set3" },
}

-- 0.25.7, second attempt at the Ctrl+Alt+RightClick "restore Blizzard's
-- menu" request -- completely reworked approach after the 0.25.2/0.25.4
-- attempts both failed (see project notes for the full postmortem: the
-- native "togglemenu" secure action type is dead on this client, and
-- Blizzard's actual default right-click behavior isn't attribute-driven at
-- all, so there was nothing to capture-and-replay either).
--
-- This version is DELIBERATELY a plain, insecure OnClick hook -- it never
-- touches the type/macrotext secure-attribute system that drives
-- click-cast above, so unlike the previous two attempts, a bug or a wrong
-- guess here CANNOT break click-cast again: worst case, this one handler
-- throws (caught by pcall) or the menu API call does nothing.
--
-- We could not find documented, verified proof of the exact modern
-- Blizzard call that reopens a unit's NATIVE popup menu (research pointed
-- at a new "Menu" API -- MenuUtil.CreateContextMenu + MENU_UNIT_* tags --
-- but not a confirmed entry point for triggering one for an arbitrary
-- unit/frame). Rather than guess at unverified internal Blizzard functions
-- (risky: an unverified call into Blizzard's menu internals could taint
-- something even if it doesn't throw an error pcall would catch), this
-- ships two things instead:
--   1. A small custom menu built entirely from the OFFICIALLY CONFIRMED
--      MenuUtil.CreateContextMenu API (verified via Blizzard's own
--      published implementation guide) with a couple of always-safe,
--      never-protected actions (Whisper, Inspect) as a working proof that
--      the trigger + menu pipeline functions end-to-end.
--   2. SFA:DumpMenuAPI() (wired to a Debug-tab button) that enumerates the
--      real Menu/MenuUtil table contents and a handful of legacy globals
--      on THIS live client, so the next iteration can target the actual
--      confirmed function name instead of guessing again.
-- 0.25.13: now that the sniffer confirmed a REAL tag ("MENU_UNIT_SELF" for
-- PlayerFrame, 2026-09-01 live log), and the dump showed a promising
-- Menu.PopulateDescription function, the plan changes: instead of trying
-- to get BLIZZARD'S OWN click handler to fire (confirmed impossible once
-- click-cast has touched a frame this session -- see the 0.25.9/0.25.10
-- saga), we build our OWN menu container via the already-working
-- MenuUtil.CreateContextMenu, then ask Blizzard's Menu system to fill it
-- with the SAME content it would generate for that tag. This doesn't rely
-- on the frame's own click routing at all, so it should work regardless of
-- whether click-cast is enabled for that frame.
--
-- Tag names beyond MENU_UNIT_SELF are still unconfirmed -- returns an
-- ordered list of plausible candidates per unit so SFA_TryPopulateNativeMenu
-- can try each and log which (if any) actually worked, refining this list
-- from real data rather than more guessing.
local function SFA_ResolveMenuTagCandidates(unit)
  if not unit then return {} end
  local okExists, exists = pcall(UnitExists, unit)
  if not (okExists and exists) then return {} end

  local okSelf, isSelf = pcall(UnitIsUnit, unit, "player")
  if okSelf and isSelf then return { "MENU_UNIT_SELF" } end

  local okParty, isParty = pcall(UnitInParty, unit)
  local unitUpper = unit:upper()
  if okParty and isParty then
    return { "MENU_UNIT_" .. unitUpper, "MENU_UNIT_PARTY" }
  end

  local okRaid, isRaid = pcall(UnitInRaid, unit)
  if okRaid and isRaid then
    return { "MENU_UNIT_RAID", "MENU_UNIT_" .. unitUpper }
  end

  local okIsPlayer, isPlayer = pcall(UnitIsPlayer, unit)
  if okIsPlayer and isPlayer then
    local okFriend, isFriend = pcall(UnitIsFriend, "player", unit)
    if okFriend and isFriend then
      return { "MENU_UNIT_PLAYER" }
    end
    return { "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_PLAYER" }
  end

  -- Non-player unit (NPC/creature/dummy) -- least confirmed category.
  return { "MENU_UNIT_UNIT", "MENU_UNIT_ENEMY_PLAYER" }
end

-- Tries Menu.PopulateDescription with a few plausible argument orders
-- (signature not confirmed by documentation) against each candidate tag,
-- stopping at the first that doesn't error. Logs every attempt either way
-- -- a tag that's simply wrong/unregistered may not error at all, just
-- populate nothing, so the log plus the user's visual report together are
-- what actually confirms success, not the pcall result alone.
local function SFA_TryPopulateNativeMenu(self, rootDescription, unit)
  if not (Menu and type(Menu.PopulateDescription) == "function") then
    self:Log("native-click ctrlalt-menu Menu.PopulateDescription unavailable")
    return false
  end

  local candidates = SFA_ResolveMenuTagCandidates(unit)
  if #candidates == 0 then
    self:Log("native-click ctrlalt-menu no-tag-candidates unit=%s", SFA_DescribeValue(unit))
    return false
  end

  local contextData = { unit = unit }
  for _, tag in ipairs(candidates) do
    local signatures = {
      function() return Menu.PopulateDescription(rootDescription, tag, contextData) end,
      function() return Menu.PopulateDescription(tag, rootDescription, contextData) end,
      function() return Menu.PopulateDescription(rootDescription, tag) end,
    }
    for sigIndex, attempt in ipairs(signatures) do
      local ok, err = pcall(attempt)
      self:Log("native-click ctrlalt-menu populate tag=%s sig=%d ok=%s err=%s",
        tag, sigIndex, tostring(ok), ok and "" or SFA_DescribeValue(err))
      if ok then return true, tag, sigIndex end
    end
  end
  return false
end

-- 0.25.18: live-tested (2026-09-01) that MENU_UNIT_UNIT -- the fallback tag
-- used for any non-player unit (NPCs, critters, etc) -- opens successfully
-- (no double-prefix, sniffer confirms tags={[1]=MENU_UNIT_UNIT}) but is
-- populated with basically nothing: title only, no buttons, for a friendly
-- NPC target. This means the unit-RELATIONSHIP-based guessing in
-- SFA_ResolveMenuTagCandidates is the wrong axis entirely for TargetFrame
-- and FocusFrame specifically: Blizzard's real target/focus right-click
-- menu is a single fixed tag keyed by FRAME IDENTITY ("TARGET"/"FOCUS"),
-- populated with whatever options make sense for the current target/focus
-- internally by Blizzard's own menu system -- not chosen by us via a
-- per-unit-type tag guess. (SFA_MENU_OBSERVER_TAGS already anticipated
-- MENU_UNIT_TARGET/MENU_UNIT_FOCUS back in 0.25.15, but the resolver never
-- actually tried them.) Frame identity is known and fixed for PlayerFrame/
-- TargetFrame/FocusFrame, so those get a confident single-tag hint tried
-- FIRST; for party/raid/arena member frames the identity is still a good
-- signal (a party member's menu should be "PARTY" regardless of who's in
-- that slot) but is not yet live-confirmed, so those hints are tried before
-- -- but do not replace -- the existing unit-relationship guesses as a
-- fallback chain.
local function SFA_ResolveFrameMenuTagHints(refKey)
  if type(refKey) ~= "string" then return {} end
  if refKey == "PlayerFrame" then return { "SELF" } end
  if refKey == "TargetFrame" then return { "TARGET" } end
  if refKey == "FocusFrame" then return { "FOCUS" } end
  if refKey:find("Party", 1, true) then return { "PARTY" } end
  if refKey:find("Raid", 1, true) then return { "RAID_PLAYER", "RAID" } end
  if refKey:find("Arena", 1, true) then return { "ARENAENEMY", "ENEMY_PLAYER" } end
  return {}
end

-- 0.25.14: Menu.PopulateDescription (0.25.13) turned out to be a dead end
-- -- live-tested (2026-09-01): it returns ok=true (no Lua error) for both
-- MENU_UNIT_SELF and MENU_UNIT_UNIT, but visibly produces nothing, only
-- the Whisper/Inspect fallback showed. That means either the tag names are
-- wrong, the contextData shape is wrong, or this simply isn't the right
-- function for "give me tag X's content right now" -- no way to tell
-- which from a silent no-op. Falling back to the OTHER real lead from the
-- API dump: UnitPopup_OpenMenu is a genuine live function (confirmed via
-- SFA:DumpMenuAPI, "= function", not nil) and its very name suggests it
-- OPENS a menu outright rather than filling a description object --
-- tried first, before building our own MenuUtil container, since if it
-- works we don't need our own container at all. Every candidate is
-- logged regardless of outcome (same reasoning as SFA_TryPopulateNativeMenu:
-- a wrong argument shape may not error, it may just do nothing).
local function SFA_TryOpenUnitMenuLegacy(self, unit, refKey)
  if not (UnitPopup_OpenMenu and type(UnitPopup_OpenMenu) == "function") then
    self:Log("native-click ctrlalt-menu UnitPopup_OpenMenu unavailable")
    return false
  end

  -- 0.25.17 fix: live-tested (2026-09-01) that passing the FULL tag
  -- ("MENU_UNIT_SELF") as "which" produces a menu literally tagged
  -- "MENU_UNIT_MENU_UNIT_SELF" (confirmed via the sniffer log) -- meaning
  -- UnitPopup_OpenMenu prepends "MENU_UNIT_" itself, so "which" must be
  -- the bare suffix ("SELF"). That's why the menu opened (with the right
  -- name, read straight from contextData.unit) but was always empty: it
  -- was really open under a tag nothing is registered against. Suffix
  -- candidates now tried FIRST.
  --
  -- 0.25.18: frame-identity hints (SFA_ResolveFrameMenuTagHints) go FIRST,
  -- ahead of the unit-relationship guesses -- live-tested (2026-09-01) that
  -- MENU_UNIT_UNIT opens successfully but empty for a friendly NPC target,
  -- meaning relationship-based guessing is the wrong axis for TargetFrame/
  -- FocusFrame specifically (see comment on SFA_ResolveFrameMenuTagHints).
  local whichCandidates = {}
  local seen = {}
  for _, suffix in ipairs(SFA_ResolveFrameMenuTagHints(refKey)) do
    if not seen[suffix] then seen[suffix] = true; whichCandidates[#whichCandidates + 1] = suffix end
  end
  local tagCandidates = SFA_ResolveMenuTagCandidates(unit)
  for _, tag in ipairs(tagCandidates) do
    local suffix = tag:match("^MENU_UNIT_(.+)$")
    if suffix and not seen[suffix] then seen[suffix] = true; whichCandidates[#whichCandidates + 1] = suffix end
  end
  for _, tag in ipairs(tagCandidates) do
    if not seen[tag] then seen[tag] = true; whichCandidates[#whichCandidates + 1] = tag end
  end

  for _, which in ipairs(whichCandidates) do
    local contextData = { unit = unit }
    local signatures = {
      function() return UnitPopup_OpenMenu(which, contextData) end,
      function() return UnitPopup_OpenMenu(unit, contextData) end,
      function() return UnitPopup_OpenMenu(which, unit) end,
    }
    for sigIndex, attempt in ipairs(signatures) do
      local ok, err = pcall(attempt)
      self:Log("native-click ctrlalt-menu legacy-open which=%s sig=%d ok=%s err=%s",
        tostring(which), sigIndex, tostring(ok), ok and "" or SFA_DescribeValue(err))
      if ok then return true, which, sigIndex end
    end
  end
  return false
end

local function SFA_OnManagedFrameClick(self, frame, refKey, button)
  if button ~= "RightButton" then return end

  local unit = frame.unit
  if type(unit) ~= "string" then
    local okAttr, attrUnit = pcall(frame.GetAttribute, frame, "unit")
    if okAttr and type(attrUnit) == "string" then unit = attrUnit end
  end

  -- 0.25.9: sniff which native menu tag(s), if any, Blizzard just opened
  -- for this click -- only actually opens something when click-cast is
  -- disabled for this group (new per-character checkbox), since otherwise
  -- our own macro/menu takes over RightButton entirely and there's no
  -- native menu to sniff. Unconditional on modifiers, read-only, no side
  -- effects -- purpose is to learn the real MENU_UNIT_* tag name Blizzard
  -- uses for each frame type (player/party/target/etc), from the live
  -- client, since that couldn't be confirmed from documentation alone.
  if Menu and type(Menu.GetOpenMenuTags) == "function" then
    C_Timer.After(0, function()
      local okTags, tags = pcall(Menu.GetOpenMenuTags)
      if not okTags then
        self:Log("native-click menu-tag-sniff frame=%s error=%s", refKey, SFA_DescribeValue(tags))
        return
      end
      if type(tags) ~= "table" then
        self:Log("native-click menu-tag-sniff frame=%s tags-type=%s", refKey, type(tags))
        return
      end
      local parts = {}
      for k, v in pairs(tags) do
        parts[#parts + 1] = string.format("[%s]=%s", SFA_DescribeValue(k), SFA_DescribeValue(v))
      end
      self:Log("native-click menu-tag-sniff frame=%s unit=%s tags={%s}",
        refKey, SFA_DescribeValue(unit), table.concat(parts, ", "))
    end)
  end

  if not (IsAltKeyDown and IsControlKeyDown and IsAltKeyDown() and IsControlKeyDown()) then return end

  self:Log("native-click ctrlalt-menu trigger frame=%s unit=%s", refKey, SFA_DescribeValue(unit))

  -- 0.25.14: try the legacy-named-but-live UnitPopup_OpenMenu first -- if
  -- it actually opens Blizzard's own menu, we're done and don't need our
  -- own MenuUtil container at all.
  local openedLegacy, legacyWhich, legacySig = SFA_TryOpenUnitMenuLegacy(self, unit, refKey)
  self:Log("native-click ctrlalt-menu legacy-opened=%s which=%s sig=%s",
    tostring(openedLegacy), tostring(legacyWhich), tostring(legacySig))
  if openedLegacy then return end

  if not (MenuUtil and type(MenuUtil.CreateContextMenu) == "function") then
    self:Log("native-click ctrlalt-menu MenuUtil.CreateContextMenu unavailable")
    return
  end

  local okMenu, menuErr = pcall(function()
    MenuUtil.CreateContextMenu(frame, function(owner, rootDescription)
      rootDescription:CreateTitle(SFA_DescribeValue(unit))

      -- 0.25.13: try to fill the menu with Blizzard's REAL content for
      -- this unit (see SFA_TryPopulateNativeMenu). Independent of the
      -- frame's own click routing, so this should work whether or not
      -- click-cast is currently overriding this button.
      local populated, matchedTag, matchedSig = SFA_TryPopulateNativeMenu(self, rootDescription, unit)
      self:Log("native-click ctrlalt-menu populated=%s tag=%s sig=%s",
        tostring(populated), tostring(matchedTag), tostring(matchedSig))

      -- Always-present safety net (proven working since 0.25.7) so the
      -- menu is never completely empty even if native population above
      -- silently did nothing (wrong/unregistered tag).
      rootDescription:CreateButton("Whisper", function()
        pcall(function()
          local name = UnitName(unit)
          if name and ChatFrame_SendTell then ChatFrame_SendTell(name) end
        end)
      end)

      rootDescription:CreateButton("Inspect", function()
        pcall(function()
          if InspectUnit then
            InspectUnit(unit)
          elseif NotifyInspect then
            NotifyInspect(unit)
          end
        end)
      end)
    end)
  end)
  self:Log("native-click ctrlalt-menu open ok=%s err=%s",
    tostring(okMenu), okMenu and "" or SFA_DescribeValue(menuErr))
end

-- 0.25.11 fix: HookScript("OnClick") registration used to live inside
-- SFA_ApplyNativeClickToFrame's "not registered" branch -- which, since
-- 0.25.10, is entirely SKIPPED for a frame whose group is disabled and
-- never touched before (that's the fix that let Blizzard's native
-- right-click menu come back). Bug: that also skipped attaching the
-- OnClick hook, so the menu-tag sniffer and the Ctrl+Alt experimental menu
-- never fired on exactly the frames we most want to observe -- confirmed
-- live (2026-09-01): disabling friendly + reload DID bring back the native
-- menu, but nothing was sniffed because the hook was never attached.
-- Split out as its own step, called unconditionally (regardless of
-- enabled/disabled) BEFORE the enabled-gated type/macrotext registration
-- below -- HookScript only ADDS an observer that runs after Blizzard's own
-- click handling, it never touches type/macrotext attributes or
-- RegisterForClicks, so (unlike those) it should not be what disables
-- Blizzard's default menu setup. Guarded by its own flag so it only
-- attaches once per frame either way.
local function SFA_EnsureClickHook(self, frame, refKey)
  if not frame or frame.sfaClickHookRegistered then return end
  local okHook, hookErr = pcall(frame.HookScript, frame, "OnClick", function(_, button)
    SFA_OnManagedFrameClick(self, frame, refKey, button)
  end)
  if not okHook then
    self:Log("native-click ctrlalt-menu hook-failed frame=%s err=%s",
      refKey, SFA_DescribeValue(hookErr))
  end
  frame.sfaClickHookRegistered = true
end

-- Enumerates the real Menu/MenuUtil API surface (and a few legacy globals)
-- on the live client into the debug log -- pure read-only diagnostics, no
-- side effects. Ground truth for building out SFA_OnManagedFrameClick's
-- menu properly once we know the actual confirmed function names.
function SFA:DumpMenuAPI()
  local prevDebug = self.auraDebug
  self.auraDebug = true
  self:Log("MENU API DUMP START")
  self:Log("menuapi Menu=%s MenuUtil=%s", type(_G.Menu), type(_G.MenuUtil))

  local function dumpTable(name, t)
    if type(t) ~= "table" then
      self:Log("menuapi %s is not a table (%s)", name, type(t))
      return
    end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local okV, v = pcall(function() return t[k] end)
      self:Log("menuapi %s.%s = %s", name, k, okV and type(v) or "<error>")
    end
    self:Log("menuapi %s key-count=%d", name, #keys)
  end

  dumpTable("Menu", _G.Menu)
  dumpTable("MenuUtil", _G.MenuUtil)

  local legacyNames = {
    "UnitPopup_OpenMenu", "UnitPopup_ShowMenu", "ToggleDropDownMenu",
    "UnitPopupFrames", "UIDropDownMenu_Initialize", "EasyMenu", "InspectUnit",
  }
  for _, name in ipairs(legacyNames) do
    self:Log("menuapi global %s = %s", name, type(_G[name]))
  end

  self:Log("MENU API DUMP DONE")
  self.auraDebug = prevDebug
  DEFAULT_CHAT_FRAME:AddMessage("|cff7cc6ffSFA:|r menu API dump done -- written to debug log")
end

-- 0.25.15: UnitPopup_OpenMenu (0.25.14) turned out to be real progress --
-- live-tested (2026-09-01): calling it with ("MENU_UNIT_SELF", {unit =
-- "player"}) DOES open a genuine Blizzard menu shell (confirmed by the
-- correct character name "Entaro" as its title -- our own placeholder
-- menu would only ever show the literal string "player") but with an
-- EMPTY body underneath -- no buttons. That means the container opens for
-- real, but whatever contextData shape Blizzard's own registered content
-- generator for that tag expects isn't what we're passing it, and there's
-- no way to discover the right shape from outside.
--
-- So: use Menu.ModifyMenu -- the SAME confirmed-real API addons use to ADD
-- items to a tag's menu -- purely as a PASSIVE OBSERVER. Register a
-- pcall-wrapped callback per plausible tag that just logs every field in
-- whatever contextData it's handed, every time a menu of that tag opens by
-- ANY means (our own UnitPopup_OpenMenu attempts, or a real Blizzard-
-- triggered open via the disable+reload flow). This can't taint or break
-- anything else using that tag -- Menu.ModifyMenu callbacks are designed
-- to be safely combinable, and ours is read-only. Installed once at
-- PLAYER_LOGIN so it's silently collecting data for every test from here
-- on, no extra button presses needed.
local SFA_MENU_OBSERVER_TAGS = {
  "MENU_UNIT_SELF", "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER",
  "MENU_UNIT_PARTY", "MENU_UNIT_PARTY1", "MENU_UNIT_PARTY2", "MENU_UNIT_PARTY3", "MENU_UNIT_PARTY4",
  "MENU_UNIT_RAID", "MENU_UNIT_UNIT", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS",
}

function SFA:InstallMenuTagObservers()
  if self._menuTagObserversInstalled then return end
  if not (Menu and type(Menu.ModifyMenu) == "function") then return end

  for _, tag in ipairs(SFA_MENU_OBSERVER_TAGS) do
    -- 0.25.16: log the REGISTRATION outcome too, not just callback
    -- firings -- 0.25.15 shipped without this and the callback never once
    -- fired even though registration was assumed to have succeeded (no
    -- error was ever surfaced either way, so we couldn't tell registration
    -- failure from "legitimately never triggered").
    local okReg, regErr = pcall(Menu.ModifyMenu, tag, function(owner, rootDescription, contextData)
      local okCall, callErr = pcall(function()
        local parts = {}
        if type(contextData) == "table" then
          for k, v in pairs(contextData) do
            parts[#parts + 1] = string.format("%s=%s", SFA_DescribeValue(k), SFA_DescribeValue(v))
          end
        else
          parts[1] = "contextData-type=" .. type(contextData)
        end
        self:Log("native-click menu-modify-observed tag=%s owner=%s contextData={%s}",
          tag, SFA_DescribeValue(owner and (owner.GetName and owner:GetName())), table.concat(parts, ", "))
      end)
      if not okCall then
        self:Log("native-click menu-modify-observed-error tag=%s err=%s", tag, SFA_DescribeValue(callErr))
      end
    end)
    self:Log("native-click menu-tag-observer-register tag=%s ok=%s err=%s",
      tag, tostring(okReg), okReg and "" or SFA_DescribeValue(regErr))
  end

  self._menuTagObserversInstalled = true
  self:Log("native-click menu-tag-observers installed count=%d", #SFA_MENU_OBSERVER_TAGS)
end

-- Shared per-frame apply logic, factored out (0.25.1) so it can be driven
-- either by a known global frame name (the arena/friendly name lists) or
-- by a live frame object found via a runtime scan (anonymous, unnamed
-- frames -- see SFA_ApplyNativeClickToAnonymousFriendlyFrames below).
-- refKey is whatever unique string this frame should be registered under
-- with the secure driver; it does not have to be the frame's own name.
local function SFA_ApplyNativeClickToFrame(self, frame, refKey, clicks)
  if not frame then return end

  if not frame.sfaNativeClickRegistered then
    SFA_RegisterClickFrame(frame, refKey)

    -- "AnyUp, AnyDown" is the broadest RegisterForClicks option and
    -- REPLACES (not adds to) whatever Blizzard had registered, but since
    -- it's a superset of any narrower registration, this can only add
    -- coverage (e.g. Middle-click) -- confirmed safe and non-tainting via
    -- the arena investigation.
    local okReg, regErr = pcall(frame.RegisterForClicks, frame, "AnyUp", "AnyDown")
    self:Log("native-click RegisterForClicks frame=%s ok=%s err=%s",
      refKey, tostring(okReg), okReg and "" or SFA_DescribeValue(regErr))

    frame.sfaNativeClickRegistered = true
  else
    -- Some frames (anonymous pool members) can be reused for a different
    -- unit between passes, or a fresh frame object can be found under the
    -- same refKey later. Re-pointing the ref every pass is cheap and safe
    -- (SecureHandlerSetFrameRef is designed to be called repeatedly from
    -- insecure code) and keeps the driver's lookup correct either way.
    SFA_RegisterClickFrame(frame, refKey)
  end

  local unit = frame.unit
  if type(unit) ~= "string" then
    local okAttr, attrUnit = pcall(frame.GetAttribute, frame, "unit")
    if okAttr and type(attrUnit) == "string" then unit = attrUnit end
  end

  local desired = {}
  for button, keys in pairs(SFA_NATIVE_CLICK_BUTTON_KEYS) do
    local macroText = clicks[button]
    if macroText and macroText ~= "" and unit then
      desired[keys[1]] = "macro"
      desired[keys[2]] = SFA_ResolveMacroForUnit(macroText, unit)
      desired[keys[3]] = true
    else
      -- Not configured for this button: leave Blizzard's default
      -- completely untouched (the secure snippet skips this button's
      -- attributes entirely when its setN flag is false/nil).
      desired[keys[1]] = nil
      desired[keys[2]] = nil
      desired[keys[3]] = false
    end
  end

  SFA_ApplyNativeClickDriver(frame, desired)
end

local function SFA_ApplyNativeClickBindingsForFrames(self, frameNames, clickGroup)
  local clicks = self:GetSpecClickTable(clickGroup)
  if type(clicks) ~= "table" then clicks = {} end
  local enabled = self:GetCharEnabled(clickGroup)
  if not enabled then clicks = {} end

  for _, frameName in ipairs(frameNames) do
    local frame = _G[frameName]
    if frame then
      -- 0.25.11: attach the read-only OnClick hook (sniffer + Ctrl+Alt
      -- menu) unconditionally, regardless of enabled/disabled -- see
      -- SFA_EnsureClickHook. Deliberately BEFORE the enabled gate below so
      -- it still works on a frame we otherwise leave completely alone.
      SFA_EnsureClickHook(self, frame, frameName)

      -- 0.25.10 fix: clearing our own type/macrotext back to nil (0.25.9)
      -- was NOT enough to bring back Blizzard's native right-click menu --
      -- live-tested (2026-09-01): with the group disabled, right-click did
      -- neither the macro NOR the native menu. This means Blizzard decides
      -- ONCE (likely at the frame's own setup, or the first time an addon
      -- touches its attributes/click registration) whether to install its
      -- own default click handling, and that decision doesn't get
      -- reconsidered just because we later clear the attribute back to
      -- nil. So for a frame we have NEVER touched yet this session, a
      -- disabled group now skips it completely (no RegisterForClicks, no
      -- SetAttribute at all) so Blizzard's default is never disturbed in
      -- the first place. A frame already touched earlier this session
      -- (e.g. the group was enabled at login, then disabled afterward)
      -- still gets the clear-to-nil treatment as before -- the best we can
      -- do without a reload at that point.
      if enabled or frame.sfaNativeClickRegistered then
        SFA_ApplyNativeClickToFrame(self, frame, frameName, clicks)
      end
    end
  end
end

function SFA:ApplyNativeArenaClickBindings()
  SFA_ApplyNativeClickBindingsForFrames(self, SFA_NATIVE_ARENA_FRAME_NAMES, "enemy")
end

-- Friendly roster unit tokens covered by the anonymous-frame scan below.
local SFA_FRIENDLY_ANON_UNIT_TOKENS = (function()
  local t = { player = true }
  for i = 1, 4 do t["party" .. i] = true end
  for i = 1, 40 do t["raid" .. i] = true end
  return t
end)()

-- Recursively walks a Blizzard-owned container frame's descendants (bounded
-- depth) looking for secure, protected Button-type children whose "unit"
-- attribute is a friendly roster token, collecting them into `results`.
-- Deliberately scoped to a specific known Blizzard container (PartyFrame /
-- CompactRaidFrameContainer) rather than a global EnumerateFrames() sweep
-- of the whole UI: this account also runs several other unit-frame addons
-- (VuhDo, Grid2, HealBot, Gladius/GladiusEx) that create their own secure
-- buttons bound to the same party/raid unit tokens, and a global sweep
-- would start overwriting THEIR click-cast attributes too. Staying inside
-- Blizzard's own native container makes that impossible.
local function SFA_FindUnitButtonsUnder(container, unitTokenSet, results, depth)
  if not container or depth > 6 then return end
  local okChildren, children = pcall(function() return { container:GetChildren() } end)
  if not okChildren then return end
  for _, child in ipairs(children) do
    local okAttr, unitAttr = pcall(child.GetAttribute, child, "unit")
    if okAttr and type(unitAttr) == "string" and unitTokenSet[unitAttr] then
      local okType, objType = pcall(child.GetObjectType, child)
      local okProt, isProt = pcall(child.IsProtected, child)
      if okType and objType == "Button" and okProt and isProt then
        results[#results + 1] = child
      end
    end
    SFA_FindUnitButtonsUnder(child, unitTokenSet, results, depth + 1)
  end
end

-- 0.25.1 fix: Blizzard's modern unified party frame ("PartyFrame" -- the
-- frame actually shown for a 5-man group on this account, confirmed via
-- the friendly-frame scan/dump diagnostics, 2026-08-31) builds its member
-- buttons from an anonymous object pool -- they have no stable global
-- name, so SFA_NATIVE_FRIENDLY_FRAME_NAMES (which can only look things up
-- by name) can never reach them. This is exactly the "shown vs visible"
-- trap the arena investigation hit: CompactPartyFrameMember1-5 exist and
-- get bindings applied fine, but IsVisible()=false on this account -- the
-- real, clickable frame is one of these anonymous pool members instead.
-- Since they have no name, walk PartyFrame's (and CompactRaidFrameContain-
-- er's) descendants fresh each apply pass and bind by object reference --
-- SecureHandlerSetFrameRef only needs a unique string key, not a name.
local function SFA_ApplyNativeClickToAnonymousFriendlyFrames(self, clicks, enabled)
  local results = {}
  SFA_FindUnitButtonsUnder(_G["PartyFrame"], SFA_FRIENDLY_ANON_UNIT_TOKENS, results, 1)
  SFA_FindUnitButtonsUnder(_G["CompactRaidFrameContainer"], SFA_FRIENDLY_ANON_UNIT_TOKENS, results, 1)

  for _, frame in ipairs(results) do
    local okAttr, unitAttr = pcall(frame.GetAttribute, frame, "unit")
    local unit = (okAttr and type(unitAttr) == "string") and unitAttr or "unknown"
    local refKey = "sfa-friendly-anon-" .. unit

    -- 0.25.11: read-only hook, unconditional -- see SFA_EnsureClickHook.
    SFA_EnsureClickHook(self, frame, refKey)

    -- 0.25.10: same "never touch it in the first place when disabled"
    -- rule as the named-frame path -- see SFA_ApplyNativeClickBindingsForFrames.
    if enabled or frame.sfaNativeClickRegistered then
      SFA_ApplyNativeClickToFrame(self, frame, refKey, clicks)
    end
  end
  return #results
end

-- 0.25.0 redesign, step 1: same mechanism, applied to Blizzard's native
-- friendly frames (player/party/raid) using the "friendly" per-spec macro
-- table. Additive and independent of this addon's own friendly-frame
-- enable state, same as the arena/enemy version.
function SFA:ApplyNativeFriendlyClickBindings()
  SFA_ApplyNativeClickBindingsForFrames(self, SFA_NATIVE_FRIENDLY_FRAME_NAMES, "friendly")

  local enabled = self:GetCharEnabled("friendly")
  local clicks = self:GetSpecClickTable("friendly")
  if type(clicks) ~= "table" then clicks = {} end
  if not enabled then clicks = {} end
  local n = SFA_ApplyNativeClickToAnonymousFriendlyFrames(self, clicks, enabled)
  if n > 0 then
    self:Log("native-click anon-friendly matches=%d", n)
  end
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

-- Edge-triggered persisted log: only writes when a slot-1 aura read flips
-- between working and blocked for a given context+unit, instead of every
-- refresh tick. Always active (not gated by /sfaauradebug) so a repro run
-- doesn't require remembering to toggle chat debug first -- just
-- /sfaclearlog, reproduce, /reload or logout, then read the SavedVariable.
-- 0.25.0 redesign: this addon no longer renders its own unit frames, so
-- there's nothing left to lay out or hide/show here -- just reapply the
-- supplemental click-cast on whichever native Blizzard frames are
-- relevant. Kept as one small function (rather than inlining every call
-- site) so all the various roster/spec/target/combat events below can
-- funnel through a single place.
function SFA:ApplyAllNativeClickBindings()
  self:ApplyNativeArenaClickBindings()
  self:ApplyNativeFriendlyClickBindings()
  self:ApplyNativeTargetFocusClickBindings()
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
  -- 0.25.0 redesign step 2: keep Target/Focus click-cast in sync with
  -- whatever the player is currently targeting/focusing. Deliberately
  -- unconditional (not gated on combat, and not folded into the big
  -- if/elseif chain below) for the same reason the arena/friendly appliers
  -- above aren't gated -- the actual reserved-attribute writes happen
  -- inside the secure snippet, which Blizzard allows during combat, and
  -- target changes happen constantly mid-fight.
  if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
    self:ApplyNativeTargetFocusClickBindings()
  end

  if event == "PLAYER_LOGIN" then
    self:InitializeDB()
    self.auraDebug = (self.db and self.db.auraDebugEnabled) and true or false
    self:CreateOptionsPanel()
    self:RegisterSlash()
    self:CreateMinimapButton()
    self:RefreshQuestIndicators()
    self:MacroFrame_Init()
    self:ApplyAllNativeClickBindings()
    if self.InstallMenuTagObservers then self:InstallMenuTagObservers() end
    -- Hook the WoW Settings window directly so values refresh whenever the user opens it,
    -- regardless of which subcategory navigation mechanism WoW uses internally.
    local function hookSettingsRefresh()
      local panel = SettingsPanel or InterfaceOptionsFrame
      if panel and panel.HookScript then
        panel:HookScript("OnShow", function()
          C_Timer.After(0, function()
            if SFA and SFA.RefreshOptionsPanel then SFA:RefreshOptionsPanel() end
          end)
        end)
      end
    end
    C_Timer.After(0, hookSettingsRefresh)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7cc6ffSFA Version " .. GetAddonVersion() .. ".|r Type /sfa")
    return
  end

  if event == "PLAYER_SPECIALIZATION_CHANGED" then
    -- Click macros are stored per-spec, so reapply bindings and refresh the
    -- options panel so the displayed macros match the new specialization.
    self:ApplyAllNativeClickBindings()
    if self.RefreshOptionsPanel then self:RefreshOptionsPanel() end
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    self:Log("COMBAT END (PLAYER_REGEN_ENABLED)")
    self:StopProcReadyTicker()
    self:ResetProcReadyStates()
    self:UpdateMinimapButtonPosition()
    self:RefreshEnemyNameplateOverlays()
    return
  end

  if event == "PLAYER_REGEN_DISABLED" or event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_USABLE" or event == "UNIT_SPELLCAST_SUCCEEDED" then
    if event == "PLAYER_REGEN_DISABLED" then
      self:Log("COMBAT START (PLAYER_REGEN_DISABLED)")
      self:StartProcReadyTicker()
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      local unit, _, spellID = ...
      if unit == "player" then self:NoteProcReadySpellCast(spellID) end
    end
    self:UpdateProcReadyAlerts()
    if C_Timer and C_Timer.After then
      C_Timer.After(0.10, function() if SFA and SFA.UpdateProcReadyAlerts then SFA:UpdateProcReadyAlerts() end end)
      C_Timer.After(0.35, function() if SFA and SFA.UpdateProcReadyAlerts then SFA:UpdateProcReadyAlerts() end end)
    end
  end

  if event == "NAME_PLATE_UNIT_ADDED" then
    local unit = ...
    self:UpdateNameplateQuestIndicator(unit)
    C_Timer.After(0.20, function()
      if SFA and SFA.db then
        SFA:UpdateNameplateQuestIndicator(unit)
      end
    end)
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
  elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "SCENARIO_UPDATE" or event == "SCENARIO_CRITERIA_UPDATE" then
    self:RefreshQuestIndicators()

  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    if UnitExists("mouseover") then
      self:UpdateNameplateQuestIndicator("mouseover")
    end

  elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
    local unit = ...
    if unit == "player" then
      self:RefreshEnemyNameplateOverlays()
      self:CheckFullResourceVoiceOnReachFull()
    end

  elseif event == "PLAYER_TARGET_CHANGED" or event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" or event == "ARENA_OPPONENT_UPDATE" or event == "UNIT_NAME_UPDATE" then
    if event == "PLAYER_TARGET_CHANGED" and UnitExists("target") then
      self:UpdateNameplateQuestIndicator("target")
    end
    self:RefreshEnemyNameplateOverlays()
  end

  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "GROUP_ROSTER_UPDATE" or event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" or event == "ARENA_OPPONENT_UPDATE" then
    self:ApplyAllNativeClickBindings()
    -- Frame creation on entering arena/party/raid can lag the event by a
    -- beat (Blizzard frames not fully populated yet), so reapply a couple
    -- more times shortly after rather than trusting one immediate pass.
    C_Timer.After(0.20, function() if SFA and SFA.ApplyAllNativeClickBindings then SFA:ApplyAllNativeClickBindings() end end)
    C_Timer.After(0.75, function() if SFA and SFA.ApplyAllNativeClickBindings then SFA:ApplyAllNativeClickBindings() end end)
  end

  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" or event == "ARENA_OPPONENT_UPDATE" then
    C_Timer.After(0.15, function()
      if SFA and SFA.db then
        SFA:RefreshQuestIndicators()
        SFA:RefreshEnemyNameplateOverlays()
      end
    end)
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
  self.eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
  self.eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
  self.eventFrame:RegisterEvent("UNIT_POWER_FREQUENT")
  self.eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  self.eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  self.eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
  self.eventFrame:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
  self.eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
  self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
  self.eventFrame:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
  self.eventFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
  self.eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  self.eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  self.eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
  self.eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
  self.eventFrame:RegisterEvent("QUEST_ACCEPTED")
  self.eventFrame:RegisterEvent("QUEST_REMOVED")
  self.eventFrame:RegisterEvent("SCENARIO_UPDATE")
  self.eventFrame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
  self.eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  self.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

SFA:RegisterEvents()

-- ---------------------------------------------------------------------
-- One-off diagnostic: hunt for whatever frame(s) currently represent the
-- native Blizzard arena-enemy UI, since Midnight removed/renamed the old
-- ArenaEnemyFrame1-5 globals and no documentation has surfaced yet for
-- their replacement. Logs every candidate to SFA_DebugLog (via /sfaauradebug
-- or the Debug tab's Enable checkbox) instead of just chat, so results
-- survive a /reload and don't need to be manually copied out of the chat
-- window. Safe to leave shipped -- only runs when explicitly invoked via
-- /sfascanarena, does a single pass, no ongoing cost.
-- ---------------------------------------------------------------------
function SFA:ScanArenaFrames()
  -- One-off diagnostic, explicitly triggered (button/command) -- always
  -- write to the log regardless of the Enable-debug checkbox, so a
  -- forgotten toggle can't make this silently produce nothing (this bit
  -- the arena-frame investigation more than once before this was added).
  local prevDebug = self.auraDebug
  self.auraDebug = true

  self:Log("ARENA SCAN START")
  local nameMatches, attrMatches = 0, 0

  local f = EnumerateFrames()
  while f do
    local ok, name = pcall(f.GetName, f)
    name = (ok and name) or nil

    if name and name:lower():find("arena") then
      nameMatches = nameMatches + 1
      local okShown, shown = pcall(f.IsShown, f)
      self:Log("arenascan name-match frame=%s shown=%s", name, tostring(okShown and shown))
    end

    -- unitAttr/unitField may be Blizzard "secret values" (frames bound to
    -- restricted-content units) -- comparing to nil is safe, but calling
    -- tostring()/:match() directly on the raw value is NOT and throws an
    -- uncaught error, silently killing the whole scan. Use the existing
    -- pcall-protected SFA_DescribeValue() helper instead, which returns
    -- "<secret>" for secret values rather than crashing.
    local okAttr, unitAttr = pcall(f.GetAttribute, f, "unit")
    if okAttr and unitAttr ~= nil then
      local descAttr = SFA_DescribeValue(unitAttr)
      if descAttr:match("^arena%d$") then
        attrMatches = attrMatches + 1
        self:Log("arenascan attr-match frame=%s unit=%s", name or SFA_DescribeValue(f), descAttr)
      elseif descAttr == "<secret>" then
        self:Log("arenascan attr-secret frame=%s unit=<secret>", name or SFA_DescribeValue(f))
      end
    end

    local okField, unitField = pcall(function() return f.unit end)
    if okField and unitField ~= nil then
      local descField = SFA_DescribeValue(unitField)
      if descField:match("^arena%d$") then
        attrMatches = attrMatches + 1
        self:Log("arenascan field-match frame=%s unit=%s", name or SFA_DescribeValue(f), descField)
      elseif descField == "<secret>" then
        self:Log("arenascan field-secret frame=%s unit=<secret>", name or SFA_DescribeValue(f))
      end
    end

    f = EnumerateFrames(f)
  end

  if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
    for i = 1, 5 do
      local unit = "arena" .. i
      local okNp, np = pcall(C_NamePlate.GetNamePlateForUnit, unit)
      self:Log("arenascan nameplate unit=%s found=%s", unit, tostring(okNp and np ~= nil))
    end
  end

  self:Log("ARENA SCAN DONE name-matches=%d attr-matches=%d", nameMatches, attrMatches)
  self.auraDebug = prevDebug
  DEFAULT_CHAT_FRAME:AddMessage(string.format(
    "|cff7cc6ffSFA:|r arena scan done (%d name-match, %d attr/field-match) -- written to debug log",
    nameMatches, attrMatches))
end

-- ---------------------------------------------------------------------
-- Diagnostic for the 0.24.26/27 native-arena-frame click-cast feature:
-- user reports middle-click on ArenaEnemyMatchFrameN still does Blizzard's
-- default "select" behavior instead of firing the configured macro, even
-- after the 0.24.27 combat-lockdown-guard fix. This forces one apply pass
-- (SFA:ApplyNativeArenaClickBindings) and then reads back the ACTUAL
-- attributes Blizzard's frame ends up with -- both for ArenaEnemyMatchFrameN
-- and CompactArenaFrameMemberN -- to see whether our SetAttribute writes
-- are (a) landing at all, (b) being overwritten by Blizzard's own code
-- afterward, or (c) landing on a frame/attribute the click handler simply
-- doesn't consult. Call via /run SFA:DumpArenaFrameAttributes() (typed
-- /sfa slash commands can be swallowed by chat autocomplete, see
-- /sfascanarena notes) -- writes everything to SFA_DebugLog.
-- ---------------------------------------------------------------------
function SFA:DumpArenaFrameAttributes()
  -- One-off diagnostic, explicitly triggered (button/command) -- always
  -- write to the log regardless of the Enable-debug checkbox, so a
  -- forgotten toggle can't make this silently produce nothing.
  local prevDebug = self.auraDebug
  self.auraDebug = true

  self:Log("ARENA ATTR DUMP START")

  -- Force one apply pass right now so the dump reflects a fresh write.
  local okApply, applyErr = pcall(function() self:ApplyNativeArenaClickBindings() end)
  self:Log("arenaattr apply-native ok=%s err=%s", tostring(okApply), okApply and "" or SFA_DescribeValue(applyErr))

  local function dumpFrame(frameName)
    local f = _G[frameName]
    if not f then
      self:Log("arenaattr frame=%s MISSING", frameName)
      return
    end

    local okProt, isProt = pcall(f.IsProtected, f)
    local okType, objType = pcall(f.GetObjectType, f)
    -- 0.24.37: neither the parent button nor its HealthBar/ManaBar children
    -- ever fired a hooked mouse event during a live click test (0.24.36),
    -- even though the user visibly saw target-selection happen. That raises
    -- a new suspect: if the user has "Raid-Style Arena Frames" enabled in
    -- Blizzard's options, the frames actually SHOWN and clicked on screen
    -- would be CompactArenaFrameMember1-5, not ArenaEnemyMatchFrame1-5 --
    -- our diagnostics have only ever been watching the classic family.
    -- IsShown/IsVisible here settles it directly.
    local okShown, isShown = pcall(f.IsShown, f)
    local okVisible, isVisible = pcall(f.IsVisible, f)
    self:Log("arenaattr frame=%s protected=%s objType=%s shown=%s visible=%s",
      frameName, tostring(okProt and isProt), tostring(okType and objType or "?"),
      tostring(okShown and isShown), tostring(okVisible and isVisible))

    local keys = {
      "unit",
      "type1", "macrotext1",
      "type2", "macrotext2",
      "type3", "macrotext3",
      "type4", "macrotext4",
      "type5", "macrotext5",
    }
    for _, key in ipairs(keys) do
      local okAttr, val = pcall(f.GetAttribute, f, key)
      local desc = okAttr and SFA_DescribeValue(val) or "<error>"
      self:Log("arenaattr frame=%s %s=%s", frameName, key, desc)
    end
  end

  for i = 1, 5 do
    dumpFrame("ArenaEnemyMatchFrame" .. i)
  end
  for i = 1, 5 do
    dumpFrame("CompactArenaFrameMember" .. i)
  end

  self:Log("ARENA ATTR DUMP DONE")
  self.auraDebug = prevDebug
  DEFAULT_CHAT_FRAME:AddMessage("|cff7cc6ffSFA:|r arena attribute dump done -- written to debug log")
end

-- 0.25.0 redesign, step 2: reactive click-cast on TargetFrame/FocusFrame.
-- Unlike arena/party/raid (where a frame's role -- friendly or enemy -- is
-- fixed), Target/Focus show whatever the player last targeted/focused, so
-- the SAME frame must swap between the "friendly" and "enemy" per-spec
-- macro table depending on the current unit's reaction, and clear entirely
-- when the unit doesn't exist. Uses the same non-tainting driver as
-- everything else above -- only the macro-table choice differs.
local function SFA_ApplyNativeReactiveClickBindings(self, frameName)
  local frame = _G[frameName]
  if not frame then return end

  -- 0.25.10: resolve the current unit/group BEFORE deciding whether to
  -- register at all -- see SFA_ApplyNativeClickBindingsForFrames above for
  -- why: a frame we've never touched yet this session, whose CURRENT
  -- group is disabled, is skipped completely (no RegisterForClicks, no
  -- HookScript, no SetAttribute) so Blizzard's own default right-click
  -- menu is never disturbed in the first place. A frame already touched
  -- earlier this session (e.g. it showed an enabled-group unit before)
  -- keeps being driven as before -- clearing to nil is the best we can do
  -- for it without a reload.
  local unit = frame.unit
  if type(unit) ~= "string" then unit = nil end

  local okExists, exists = pcall(UnitExists, unit)
  local clickGroup = nil
  if unit and okExists and exists then
    local okFriend, isFriend = pcall(UnitIsFriend, "player", unit)
    clickGroup = (okFriend and isFriend) and "friendly" or "enemy"
  end
  local enabled = clickGroup and self:GetCharEnabled(clickGroup)

  -- 0.25.11: read-only hook, unconditional regardless of enabled/disabled
  -- -- see SFA_EnsureClickHook. Must happen even when we're about to skip
  -- registration below, so the sniffer/Ctrl+Alt menu still works on a
  -- frame we otherwise leave completely alone.
  SFA_EnsureClickHook(self, frame, frameName)

  if not frame.sfaNativeClickRegistered then
    -- 0.25.19: TargetFrame/FocusFrame have no fixed click group -- unlike
    -- arena/friendly frames, which group applies depends on WHO is
    -- currently targeted, so at PLAYER_LOGIN (before any target exists)
    -- `enabled` above is nil even when the user wants click-cast on. That
    -- left a real gap: the very first touch (the one that permanently
    -- decides, for this session, whether Blizzard's own native menu stays
    -- installed on this frame -- see the one-time-decision finding above)
    -- was deferred until a target/focus actually existed, instead of
    -- happening deterministically at login. In practice a same-session
    -- carryover (e.g. an earlier disable-checkbox test before a later
    -- re-enable, with no reload in between) could leave the frame's
    -- decision already locked to native from earlier in the session, with
    -- no way for a later "enabled" apply to reclaim it -- confirmed live
    -- (2026-09-01): the user saw click-and-cast fail to fire on TargetFrame
    -- until their next reload, matching this exact gap. Fix: if EITHER
    -- group is currently enabled, touch (register) the frame immediately
    -- even with no unit/clickGroup yet -- an empty attribute set is
    -- harmless (SFA_ApplyNativeClickDriver below still runs with `desired`
    -- unset when clickGroup is nil) but it claims the one-time decision for
    -- the addon right at login, before the user can possibly interact with
    -- the frame at all. Only truly skip touching (preserving native
    -- end-to-end) when BOTH groups are disabled, since we can't yet know
    -- which group this frame will actually need.
    local anyGroupEnabled = self:GetCharEnabled("friendly") or self:GetCharEnabled("enemy")
    if not (enabled or anyGroupEnabled) then return end

    SFA_RegisterClickFrame(frame)
    local okReg, regErr = pcall(frame.RegisterForClicks, frame, "AnyUp", "AnyDown")
    self:Log("native-click RegisterForClicks frame=%s ok=%s err=%s",
      frameName, tostring(okReg), okReg and "" or SFA_DescribeValue(regErr))

    frame.sfaNativeClickRegistered = true
  end

  if not clickGroup then
    SFA_ApplyNativeClickDriver(frame, {})
    return
  end

  local clicks = self:GetSpecClickTable(clickGroup)
  if type(clicks) ~= "table" then clicks = {} end
  if not enabled then clicks = {} end

  local buttonKeys = {
    LeftButton = { "type1", "macrotext1", "set1" },
    RightButton = { "type2", "macrotext2", "set2" },
    MiddleButton = { "type3", "macrotext3", "set3" },
  }

  local desired = {}
  for button, keys in pairs(buttonKeys) do
    local macroText = clicks[button]
    if macroText and macroText ~= "" then
      desired[keys[1]] = "macro"
      desired[keys[2]] = SFA_ResolveMacroForUnit(macroText, unit)
      desired[keys[3]] = true
    else
      desired[keys[1]] = nil
      desired[keys[2]] = nil
      desired[keys[3]] = false
    end
  end

  SFA_ApplyNativeClickDriver(frame, desired)
end

function SFA:ApplyNativeTargetFocusClickBindings()
  SFA_ApplyNativeReactiveClickBindings(self, "TargetFrame")
  SFA_ApplyNativeReactiveClickBindings(self, "FocusFrame")
end

-- ---------------------------------------------------------------------
-- Diagnostic (0.25.0 redesign step 1): the friendly-frame equivalent of
-- ScanArenaFrames/DumpArenaFrameAttributes above. Party frames failed
-- outright on the first live test (unlike arena, which at least had
-- correct-but-unused attributes) -- broaden the net with a live frame-tree
-- scan rather than guessing more fixed names blind.
-- ---------------------------------------------------------------------
function SFA:ScanFriendlyFrames()
  local prevDebug = self.auraDebug
  self.auraDebug = true

  self:Log("FRIENDLY SCAN START")
  local nameMatches, attrMatches = 0, 0

  local f = EnumerateFrames()
  while f do
    local ok, name = pcall(f.GetName, f)
    name = (ok and name) or nil

    if name and (name:lower():find("party") or name:lower():find("compactraid") or name:lower():find("follower")) then
      nameMatches = nameMatches + 1
      local okShown, shown = pcall(f.IsShown, f)
      local okVisible, visible = pcall(f.IsVisible, f)
      self:Log("friendlyscan name-match frame=%s shown=%s visible=%s",
        name, tostring(okShown and shown), tostring(okVisible and visible))
    end

    local okAttr, unitAttr = pcall(f.GetAttribute, f, "unit")
    if okAttr and unitAttr ~= nil then
      local descAttr = SFA_DescribeValue(unitAttr)
      if descAttr:match("^party%d$") or descAttr:match("^raid%d+$") or descAttr == "player" then
        attrMatches = attrMatches + 1
        local okShown2, shown2 = pcall(f.IsShown, f)
        self:Log("friendlyscan attr-match frame=%s unit=%s shown=%s",
          name or SFA_DescribeValue(f), descAttr, tostring(okShown2 and shown2))

        -- 0.25.1: also log the parent chain (up to 6 levels) for unnamed
        -- matches, so if the anonymous-frame scan (SFA_FindUnitButtonsUnder,
        -- scoped to PartyFrame/CompactRaidFrameContainer) ever comes up
        -- empty for a match seen here, we already have what's needed to
        -- retarget it -- no need for another diagnostic round-trip.
        if not name then
          local chain = {}
          local p = f
          for i = 1, 6 do
            local okP, parent = pcall(p.GetParent, p)
            if not okP or not parent then break end
            local okPName, pName = pcall(parent.GetName, parent)
            chain[#chain + 1] = (okPName and pName) or "<unnamed>"
            p = parent
          end
          self:Log("friendlyscan attr-match parent-chain frame=%s chain=%s",
            SFA_DescribeValue(f), table.concat(chain, " < "))
        end
      elseif descAttr == "<secret>" then
        self:Log("friendlyscan attr-secret frame=%s unit=<secret>", name or SFA_DescribeValue(f))
      end
    end

    f = EnumerateFrames(f)
  end

  self:Log("FRIENDLY SCAN DONE name-matches=%d attr-matches=%d", nameMatches, attrMatches)
  self.auraDebug = prevDebug
  DEFAULT_CHAT_FRAME:AddMessage(string.format(
    "|cff7cc6ffSFA:|r friendly scan done (%d name-match, %d attr-match) -- written to debug log",
    nameMatches, attrMatches))
end

function SFA:DumpFriendlyFrameAttributes()
  local prevDebug = self.auraDebug
  self.auraDebug = true

  self:Log("FRIENDLY ATTR DUMP START")

  local okApply, applyErr = pcall(function() self:ApplyNativeFriendlyClickBindings() end)
  self:Log("friendlyattr apply-native ok=%s err=%s", tostring(okApply), okApply and "" or SFA_DescribeValue(applyErr))
  local okApply2, applyErr2 = pcall(function() self:ApplyNativeTargetFocusClickBindings() end)
  self:Log("friendlyattr apply-native-targetfocus ok=%s err=%s", tostring(okApply2), okApply2 and "" or SFA_DescribeValue(applyErr2))

  local function dumpFrame(frameName)
    local f = _G[frameName]
    if not f then return end -- skip absent names; the friendly name list is large

    local okProt, isProt = pcall(f.IsProtected, f)
    local okType, objType = pcall(f.GetObjectType, f)
    local okShown, isShown = pcall(f.IsShown, f)
    local okVisible, isVisible = pcall(f.IsVisible, f)
    self:Log("friendlyattr frame=%s protected=%s objType=%s shown=%s visible=%s",
      frameName, tostring(okProt and isProt), tostring(okType and objType or "?"),
      tostring(okShown and isShown), tostring(okVisible and isVisible))

    local keys = { "unit", "type1", "macrotext1", "type2", "macrotext2", "type3", "macrotext3" }
    for _, key in ipairs(keys) do
      local okAttr, val = pcall(f.GetAttribute, f, key)
      local desc = okAttr and SFA_DescribeValue(val) or "<error>"
      self:Log("friendlyattr frame=%s %s=%s", frameName, key, desc)
    end

    local okDesc, desc = pcall(SFA_DescribeFrameChildren, f)
    self:Log("friendlyattr frame=%s structure: %s", frameName, okDesc and desc or "<error describing>")
  end

  for _, frameName in ipairs(SFA_NATIVE_FRIENDLY_FRAME_NAMES) do
    dumpFrame(frameName)
  end
  dumpFrame("TargetFrame")
  dumpFrame("FocusFrame")

  -- 0.25.1: also report what the anonymous-frame scan (PartyFrame /
  -- CompactRaidFrameContainer descendants) actually found and bound,
  -- since these are the frames a "shown but not visible" named frame
  -- (e.g. CompactPartyFrameMember1-5) turned out to be masking.
  local anonResults = {}
  SFA_FindUnitButtonsUnder(_G["PartyFrame"], SFA_FRIENDLY_ANON_UNIT_TOKENS, anonResults, 1)
  SFA_FindUnitButtonsUnder(_G["CompactRaidFrameContainer"], SFA_FRIENDLY_ANON_UNIT_TOKENS, anonResults, 1)
  self:Log("friendlyattr anon-scan matches=%d", #anonResults)
  for _, f in ipairs(anonResults) do
    local okAttr, unitAttr = pcall(f.GetAttribute, f, "unit")
    local okShown, isShown = pcall(f.IsShown, f)
    local okVisible, isVisible = pcall(f.IsVisible, f)
    local okName, name = pcall(f.GetName, f)
    self:Log("friendlyattr anon frame=%s unit=%s shown=%s visible=%s",
      (okName and name) or SFA_DescribeValue(f),
      (okAttr and SFA_DescribeValue(unitAttr)) or "?",
      tostring(okShown and isShown), tostring(okVisible and isVisible))
  end

  self:Log("FRIENDLY ATTR DUMP DONE")
  self.auraDebug = prevDebug
  DEFAULT_CHAT_FRAME:AddMessage("|cff7cc6ffSFA:|r friendly attribute dump done -- written to debug log")
end

-- 0.24.40: prep work for "use Blizzard arena frames instead of SFA's own,
-- positioned where SFA's frames are". Repositioning a Blizzard-owned frame
-- from addon code is a known taint source specifically when that frame is
-- managed by Blizzard's Edit Mode system (Edit Mode re-applies its own
-- stored layout, fighting any SetPoint an addon makes) -- confirmed via
-- research, not yet directly tested against these two frame families.
-- Before writing any actual repositioning code, walk each family's parent
-- chain (frame:GetParent() repeatedly up to UIParent/nil) and log every
-- ancestor's name/objType/current anchor point, so we know exactly which
-- frame is the real "move this one and the rest follows" container, and
-- whether it's plausibly an Edit Mode system (Edit Mode elements are
-- typically the outermost frame with a specific point in UIParent) before
-- attempting to touch it.
local SFA_GCDText = SFA_GCDText
local SFA_GCD_SPELL_ID = 61304
local SFA_BASE_GCD = 1.5
local SFA_MIN_GCD = 0.75
local SFA_lastGCD = nil
local SFA_lastHaste = nil
local SFA_lastSource = nil
local SFA_gcdPendingUntil = 0

local function SFA_Now()
    if type(GetTime) == "function" then
        local ok, t = pcall(GetTime)
        if ok and type(t) == "number" then return t end
    end
    return 0
end

local function SFA_IsGCDPending()
    return SFA_gcdPendingUntil and SFA_gcdPendingUntil > SFA_Now()
end

local function SFA_ClearGCDCache(reason)
    SFA_lastGCD = nil
    SFA_lastHaste = nil
    SFA_lastSource = reason or "refreshing"
end

local function SFA_SafeNumber(value)
    local ok, n = pcall(function()
        if type(value) ~= "number" then return nil end
        if value ~= value then return nil end
        if value < 0 or value > 1000 then return nil end
        return value
    end)
    if ok then return n end
    return nil
end

local function SFA_SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    return nil
end

local function SFA_IsRestrictedForGCDDisplay()
    -- Hard stop before reading any stat/cooldown APIs that may return secret values in PvP instances.
    local okCombat, inCombat = pcall(function()
        return (type(InCombatLockdown) == "function" and InCombatLockdown()) or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player"))
    end)
    if okCombat and inCombat then return true end

    local okInstance, inInstance, instanceType = pcall(IsInInstance)
    if okInstance and inInstance and (instanceType == "arena" or instanceType == "pvp") then
        return true
    end

    return false
end

local function SFA_HideGCDText()
    if SFA_GCDText then
        SFA_GCDText:SetText("")
        SFA_GCDText:Hide()
    end
end

local function SFA_GCDFromHaste(hastePercent)
    local haste = SFA_SafeNumber(hastePercent)
    if not haste then return nil end
    local ok, gcd = pcall(function()
        return math.max(SFA_MIN_GCD, SFA_BASE_GCD / (1 + haste / 100))
    end)
    if ok then return SFA_SafeNumber(gcd) end
    return nil
end

local function SFA_ReadEngineGCD()
    local start, duration

    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local info = SFA_SafeCall(C_Spell.GetSpellCooldown, SFA_GCD_SPELL_ID)
        if type(info) == "table" then
            start = info.startTime
            duration = info.duration
        end
    end

    if not duration and type(GetSpellCooldown) == "function" then
        start, duration = SFA_SafeCall(GetSpellCooldown, SFA_GCD_SPELL_ID)
    end

    duration = SFA_SafeNumber(duration)
    if duration and duration >= SFA_MIN_GCD and duration <= SFA_BASE_GCD + 0.10 then
        return duration
    end
    return nil
end

local function SFA_ReadSafeHaste()
    local value

    if type(GetHaste) == "function" then
        value = SFA_SafeNumber(SFA_SafeCall(GetHaste))
        if value then return value, "GetHaste" end
    end

    if C_PaperDollInfo and type(C_PaperDollInfo.GetHaste) == "function" then
        value = SFA_SafeNumber(SFA_SafeCall(C_PaperDollInfo.GetHaste))
        if value then return value, "C_PaperDollInfo.GetHaste" end
    end

    if type(UnitSpellHaste) == "function" then
        value = SFA_SafeNumber(SFA_SafeCall(UnitSpellHaste, "player"))
        if value then return value, "UnitSpellHaste" end
    end

    if type(GetMeleeHaste) == "function" then
        value = SFA_SafeNumber(SFA_SafeCall(GetMeleeHaste))
        if value then return value, "GetMeleeHaste" end
    end

    return nil, nil
end

local function SFA_GetSavedGCD()
    if SFA_lastGCD then return SFA_lastGCD, SFA_lastHaste, SFA_lastSource end
    if SFA and SFA.db and SFA.db.other and type(SFA.db.other.gcdLast) == "table" then
        local last = SFA.db.other.gcdLast
        local gcd = SFA_SafeNumber(last.gcd)
        local haste = SFA_SafeNumber(last.haste)
        if gcd and gcd >= SFA_MIN_GCD and gcd <= SFA_BASE_GCD + 0.10 then
            return gcd, haste, last.source or "saved"
        end
    end
    return nil, nil, nil
end

local function SFA_SaveGCD(gcd, haste, source)
    gcd = SFA_SafeNumber(gcd)
    haste = SFA_SafeNumber(haste)
    if not gcd then return end
    SFA_lastGCD = gcd
    SFA_lastHaste = haste
    SFA_lastSource = source or "unknown"
    if SFA and SFA.db and SFA.db.other then
        SFA.db.other.gcdLast = {
            gcd = gcd,
            haste = haste,
            source = source or "unknown",
        }
    end
end

local function SFA_GetBestGCD(allowSaved)
    local pending = SFA_IsGCDPending()

    local gcd = SFA_ReadEngineGCD()
    if gcd then
        SFA_SaveGCD(gcd, nil, "engine")
        return gcd, nil, "engine"
    end

    local haste, hasteSource = SFA_ReadSafeHaste()
    gcd = SFA_GCDFromHaste(haste)
    if gcd then
        SFA_SaveGCD(gcd, haste, hasteSource or "haste")
        return gcd, haste, hasteSource or "haste"
    end

    if allowSaved and not pending then
        local savedGCD, savedHaste, savedSource = SFA_GetSavedGCD()
        if savedGCD then
            return savedGCD, savedHaste, savedSource or "saved"
        end
    end

    return SFA_BASE_GCD, nil, pending and "refreshing" or "base"
end

function SFA_UpdateCharacterGCD()
    if not CharacterFrame then return end

    -- Do not show or calculate in combat / Arena / BG. This avoids secret value taint completely.
    if SFA_IsRestrictedForGCDDisplay() then
        SFA_HideGCDText()
        return
    end

    local okVisible, visible = pcall(function() return CharacterFrame:IsShown() end)
    if okVisible and not visible then return end

    local enabled = true
    if SFA and SFA.db and SFA.db.other and SFA.db.other.showCharacterGCD ~= nil then
        enabled = SFA.db.other.showCharacterGCD
    end

    if not SFA_GCDText then
        SFA_GCDText = CharacterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        SFA_GCDText:SetJustifyH("CENTER")
    end

    SFA_GCDText:ClearAllPoints()
    if CharacterStatsPane then
        SFA_GCDText:SetPoint("TOP", CharacterStatsPane, "BOTTOM", 0, -20)
    else
        SFA_GCDText:SetPoint("BOTTOM", CharacterFrame, "BOTTOM", 0, 38)
    end

    if not enabled then
        SFA_HideGCDText()
        return
    end

    local gcd = SFA_GetBestGCD(true)
    local oneButton = gcd * 1.25

    -- Haste is intentionally not displayed here; Character Panel already has it.
    SFA_GCDText:SetText(string.format("Calculated GCD: %.2f\nOne-Button GCD: %.2f", gcd, oneButton))
    SFA_GCDText:Show()
end

local function SFA_ScheduleCharacterGCDUpdates(forceRefresh)
    if SFA_IsRestrictedForGCDDisplay() then
        SFA_HideGCDText()
        return
    end

    if forceRefresh then
        SFA_ClearGCDCache("refreshing")
        SFA_gcdPendingUntil = SFA_Now() + 2.0
    end

    if C_Timer then
        C_Timer.After(0.05, SFA_UpdateCharacterGCD)
        C_Timer.After(0.15, SFA_UpdateCharacterGCD)
        C_Timer.After(0.30, SFA_UpdateCharacterGCD)
        C_Timer.After(0.60, SFA_UpdateCharacterGCD)
        C_Timer.After(1.00, SFA_UpdateCharacterGCD)
        C_Timer.After(1.50, SFA_UpdateCharacterGCD)
        C_Timer.After(2.00, SFA_UpdateCharacterGCD)
    else
        SFA_UpdateCharacterGCD()
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("UNIT_INVENTORY_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("COMBAT_RATING_UPDATE")
f:RegisterEvent("UNIT_STATS")
f:RegisterEvent("UNIT_SPELL_HASTE")
f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
f:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
f:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:SetScript("OnEvent", function(_, event, unit)
    if (event == "UNIT_STATS" or event == "UNIT_SPELL_HASTE") and unit and unit ~= "player" then return end

    if event == "PLAYER_REGEN_DISABLED" or SFA_IsRestrictedForGCDDisplay() then
        SFA_HideGCDText()
        return
    end

    local forceRefresh = (event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SHAPESHIFT_FORMS" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED")
    SFA_ScheduleCharacterGCDUpdates(forceRefresh)
end)

local function SFA_HookCharacterFrameShow()
    if CharacterFrame and not CharacterFrame.SFA_GCDHooked then
        CharacterFrame.SFA_GCDHooked = true
        CharacterFrame:HookScript("OnShow", function() SFA_ScheduleCharacterGCDUpdates(false) end)
    end
end
SFA_HookCharacterFrameShow()
