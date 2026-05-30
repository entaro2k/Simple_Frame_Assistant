local addonName, SFA = ...
SFA = _G[addonName] or SFA

-- ============================================================
-- SFA CUSTOM MACRO WINDOW  (v0.22.00)
-- ============================================================

local CMF = {}
SFA.cmf = CMF

CMF.filter   = "global"
CMF.page     = {global=1, class=1, character=1}
CMF.cache    = {global={}, class={}, character={}}
CMF.selected = nil
CMF.dirty    = false

-- Layout
local WIN_W    = 620
local WIN_H    = 580
local COLS     = 8
local ROWS     = 4
local CELL_W   = 68
local CELL_H   = 50
local PER_PAGE = COLS * ROWS   -- 32

-- Anchors from window top (negative = downward)
local Y_SEP1    = -36
local Y_TAB_TOP = -40
local TAB_H     = 24
local Y_SEP2    = -68
local Y_GRID    = -74
local Y_PAGENAV = Y_GRID - ROWS * CELL_H - 8      -- -250
local Y_SEP3    = Y_PAGENAV - 28                   -- -278
local Y_MACNAME = Y_SEP3 - 10                      -- -288
local Y_NAMEROW = Y_MACNAME - 18                   -- -306
local Y_MACCMD  = Y_NAMEROW - 52                   -- -358
local Y_BODY    = Y_MACCMD - 16                    -- -374
local BODY_H    = 110
local Y_SEP4    = Y_BODY - BODY_H - 6             -- -490
local BTN_Y2    = 36
local BTN_Y1    = 8

-- ============================================================
-- AUTOCOMPLETE DATA
-- ============================================================

local AC_SLASH = {
  "/cast","/castsequence","/castrandom",
  "/use","/userandom",
  "/target","/targetexact","/targetlasttarget","/targetlastenemy",
  "/targetlastfriend","/targetfriend","/targetenemy",
  "/cleartarget","/focus","/clearfocus","/assist",
  "/stopcasting","/stopmacro","/cancelaura","/cancelform",
  "/petattack","/petfollow","/petstay",
  "/petaggressive","/petdefensive","/petpassive",
  "/startattack","/stopattack","/dismount","/leavevehicle",
  "/click","/equip","/equipslot","/swapactionbar","/changeactionbar",
  "/showtooltip","/show","/script","/run",
  "/readycheck","/raidwarning",
  "/say","/yell","/whisper","/party","/guild","/raid","/emote","/me",
  "/in","/s","/y","/w","/p","/g","/ra",
}

local AC_CONDS = {
  "mod:alt","mod:ctrl","mod:shift",
  "mod:lalt","mod:ralt","mod:lctrl","mod:rctrl","mod:lshift","mod:rshift",
  "combat","nocombat",
  "stealth","nostealth",
  "mounted","nomounted",
  "swimming","flyable","flying",
  "exists","noexists",
  "dead","nodead",
  "harm","noharm",
  "help","nohelp",
  "indoors","outdoors",
  "party","raid",
  "vehicle","cursor",
  "btn:1","btn:2","btn:3",
  "stance:1","stance:2","stance:3","stance:4",
  "form:0","form:1","form:2","form:3","form:4",
  "spec:1","spec:2",
  "channeling:","equipped:",
  "unithasvehicleui","canexitvehicle",
  "target=target","target=player","target=focus",
  "target=mouseover","target=cursor","target=pet","target=none",
}

local AC_UNITS = {
  "target","player","focus","mouseover","cursor","none",
  "pet","pettarget",
  "arena1","arena2","arena3",
  "arena1target","arena2target","arena3target",
  "party1","party2","party3","party4",
  "party1target","party2target","party3target","party4target",
  "boss1","boss2","boss3",
  "raid1","raid2","raid3",
  "lasttarget","lastunit",
}

-- Color labels per type
local AC_COLORS = {
  slash = "|cff88ddff",
  cond  = "|cff88ff99",
  unit  = "|cffffcc66",
  spell = "|cffddaaff",
}

-- ============================================================
-- CLASS SPELL DETECTION
-- ============================================================

SFA.MacroOrg_ClassKeywords = {
  DRUID = {
    "cat form","bear form","moonkin form","tree of life","travel form",
    "aquatic form","flight form","swift flight form","astral form",
    "prowl","dash","shred","ferocious bite","rip","rake","swipe",
    "mangle","maul","thrash","tiger's fury","berserk","skull bash",
    "feral frenzy","savage roar","primal wrath",
    "moonfire","sunfire","starsurge","starfall","solar beam",
    "wrath","starfire","stellar flare","fury of elune",
    "regrowth","rejuvenation","lifebloom","wild growth","efflorescence",
    "tranquility","swiftmend","cenarion ward","frenzied regeneration",
    "ironfur","barkskin","cyclone","entangling roots","rebirth",
    "innervate","soothe","remove corruption","wild charge",
    "stampeding roar","nature's swiftness","ursol's vortex",
    "convoke the spirits","incarnation","force of nature",
    "shapeshift","remove poison",
  },
  WARRIOR  = {"charge","execute","mortal strike","whirlwind","colossus smash","shield wall","avatar","bladestorm","overpower","battle shout","recklessness","heroic leap","rallying cry"},
  MAGE     = {"fireball","frostbolt","arcane blast","pyroblast","ice lance","frost nova","blink","time warp","mirror image","combustion","arcane surge","icy veins","polymorph","counterspell"},
  ROGUE    = {"stealth","backstab","sinister strike","eviscerate","rupture","kidney shot","blind","vanish","shadowstep","shadow dance","ambush","mutilate","envenom","garrote","sap"},
  PALADIN  = {"crusader strike","holy shock","judgment","divine shield","lay on hands","hammer of justice","avenging wrath","consecration","divine toll","word of glory","blessing of protection","blessing of freedom"},
  PRIEST   = {"shadow word: pain","mind blast","mind flay","penance","power word: shield","holy nova","flash heal","prayer of healing","fade","dispel magic","mind control"},
  HUNTER   = {"arcane shot","aimed shot","barbed shot","kill shot","rapid fire","bestial wrath","kill command","feign death","disengage","misdirection"},
  WARLOCK  = {"shadow bolt","incinerate","corruption","agony","immolate","chaos bolt","soul fire","demonic gate","dark pact","healthstone","drain soul","haunt"},
  SHAMAN   = {"lightning bolt","earth shock","flame shock","frost shock","chain lightning","lava burst","healing surge","chain heal","earth elemental","fire elemental","ghost wolf","stormstrike","windfury"},
  MONK     = {"tiger palm","blackout kick","rising sun kick","fists of fury","roll","touch of death","leg sweep","vivify","renewing mist","breath of fire","keg smash"},
  DEATHKNIGHT = {"death strike","obliterate","scourge strike","death coil","death grip","anti-magic shell","icebound fortitude","raise dead","frost strike","howling blast"},
  DEMONHUNTER = {"chaos strike","blade dance","metamorphosis","fel rush","vengeful retreat","eye beam","soul cleave","throw glaive","spectral sight"},
  EVOKER   = {"disintegrate","azure strike","fire breath","deep breath","living flame","verdant embrace","spiritbloom","dream breath","return","hover","soar"},
}

function SFA:MacroOrg_BuildSpellSet()
  local _, classFile = UnitClass("player")
  if not classFile then self.macroOrgSpellSet = {} return end
  local set = {}
  for _, kw in ipairs(self.MacroOrg_ClassKeywords[classFile] or {}) do
    set[kw] = true
  end
  pcall(function()
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
    local count = C_SpellBook.GetNumSpellBookSkillLines()
    if not count then return end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for li = 1, math.min(tonumber(count) or 0, 8) do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(li)
      if info then
        local offset = info.itemIndexOffset or 0
        local num    = info.numSpellBookItems or 0
        for slot = offset+1, offset+num do
          if C_SpellBook.GetSpellBookItemName then
            local n = C_SpellBook.GetSpellBookItemName(slot, bank)
            if type(n)=="string" and n~="" then
              local ok,low = pcall(string.lower, n)
              if ok and low then set[low]=true end
            end
          end
        end
      end
    end
  end)
  self.macroOrgSpellSet = set
end

function SFA:MacroOrg_IsClassMacro(name, body)
  local _, classFile = UnitClass("player")
  if not classFile then return false end
  local playerName = UnitName("player") or ""
  if playerName ~= "" then
    local ok1,lN = pcall(string.lower, tostring(name or ""))
    local ok2,lP = pcall(string.lower, playerName)
    if ok1 and ok2 and lN:find(lP,1,true) then return false end
  end
  local spellSet = self.macroOrgSpellSet
  if not spellSet then
    self:MacroOrg_BuildSpellSet()
    spellSet = self.macroOrgSpellSet or {}
  end
  local ok,lB = pcall(string.lower, tostring(body or ""))
  if not ok then return false end
  for spell in pairs(spellSet) do
    local ok2,pos = pcall(string.find, lB, spell, 1, true)
    if ok2 and pos then return true end
  end
  return false
end

-- ============================================================
-- CACHE
-- ============================================================

function SFA:CMF_BuildCache()
  self:MacroOrg_BuildSpellSet()
  CMF.cache.global    = {}
  CMF.cache.class     = {}
  CMF.cache.character = {}
  local numGlobal, numChar = GetNumMacros()
  numGlobal = numGlobal or 0
  numChar   = numChar   or 0
  for i = 1, numGlobal do
    local n,_,b = GetMacroInfo(i)
    if n then
      if self:MacroOrg_IsClassMacro(n, b or "") then
        CMF.cache.class[#CMF.cache.class+1] = i
      else
        CMF.cache.global[#CMF.cache.global+1] = i
      end
    end
  end
  for i = 1, numChar do
    local n = GetMacroInfo(120+i)
    if n then CMF.cache.character[#CMF.cache.character+1] = 120+i end
  end
end

function SFA:CMF_GetCurrentIndices() return CMF.cache[CMF.filter] or {} end

function SFA:CMF_GetPageIndices()
  local all   = self:CMF_GetCurrentIndices()
  local page  = CMF.page[CMF.filter] or 1
  local start = (page-1)*PER_PAGE + 1
  local result = {}
  for i = 0, PER_PAGE-1 do result[#result+1] = all[start+i] end
  return result, #all
end

-- ============================================================
-- UI HELPERS
-- ============================================================

local function MkBD(f, r,g,b,a, er,eg,eb,ea)
  if not f.SetBackdrop then return end
  f:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
    edgeFile="Interface/Tooltips/UI-Tooltip-Border",
    tile=true,tileSize=16,edgeSize=10,
    insets={left=3,right=3,top=3,bottom=3}})
  f:SetBackdropColor(r,g,b,a or 0.9)
  f:SetBackdropBorderColor(er or 0.3,eg or 0.3,eb or 0.4,ea or 0.8)
end

local function HSep(p, y)
  local s = p:CreateTexture(nil,"ARTWORK")
  s:SetColorTexture(0.22,0.22,0.32,0.7)
  s:SetPoint("TOPLEFT",8,y); s:SetPoint("TOPRIGHT",-8,y); s:SetHeight(1)
end

-- ============================================================
-- CREATE WINDOW
-- ============================================================

function SFA:CMF_CreateWindow()
  if CMF.window then return end

  local win = CreateFrame("Frame","SFACustomMacroWin",UIParent,"BackdropTemplate")
  win:SetSize(WIN_W, WIN_H)
  win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  win:SetMovable(true); win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart",function(f) f:StartMoving() end)
  win:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
  win:SetClampedToScreen(true)
  MkBD(win,0.04,0.04,0.07,0.97,0.35,0.35,0.48,1)
  win:EnableKeyboard(false)
  win:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      SFA:CMF_Close()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)
  win:Hide()
  CMF.window = win

  -- Header
  local ico = win:CreateTexture(nil,"ARTWORK")
  ico:SetSize(22,22); ico:SetPoint("TOPLEFT",8,-8)
  ico:SetTexture("Interface\\AddOns\\Simple_Frame_Assistant\\Icon")

  local title = win:CreateFontString(nil,"OVERLAY","GameFontNormal")
  title:SetPoint("TOPLEFT",34,-10)
  title:SetText("|cff7cc6ffSFA|r Macro Manager")

  local xBtn = CreateFrame("Button",nil,win,"UIPanelCloseButton")
  xBtn:SetPoint("TOPRIGHT",-2,-2)
  xBtn:SetScript("OnClick",function() SFA:CMF_Close() end)

  HSep(win, Y_SEP1)

  -- Tabs
  local _, classFile = UnitClass("player")
  local className  = classFile and (classFile:sub(1,1):upper()..classFile:sub(2):lower()) or "Class"
  local playerName = UnitName("player") or "Character"

  local tabDefs = {
    {key="global",    base="Global"},
    {key="class",     base=className},
    {key="character", base=playerName},
  }
  CMF.tabs = {}
  local tabW = 130; local tabGap = 3
  for i,def in ipairs(tabDefs) do
    local tab = CreateFrame("Button",nil,win,"BackdropTemplate")
    tab:SetSize(tabW, TAB_H)
    tab:SetPoint("TOPLEFT", 8+(i-1)*(tabW+tabGap), Y_TAB_TOP)
    MkBD(tab,0.08,0.08,0.13,0.93,0.22,0.22,0.32,0.8)
    local hl = tab:CreateTexture(nil,"HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.06)
    local lbl = tab:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    lbl:SetAllPoints(); lbl:SetJustifyH("CENTER"); lbl:SetJustifyV("MIDDLE")
    tab.label=lbl; tab.key=def.key; tab.baseLbl=def.base
    local tips={global="Global macros without "..className.." spells.",
      class=className.." macros (class spells detected).",
      character=playerName.."-specific character macros."}
    tab:SetScript("OnClick",function(s) SFA:CMF_SetFilter(s.key) end)
    tab:SetScript("OnEnter",function(s)
      GameTooltip:SetOwner(s,"ANCHOR_TOP")
      GameTooltip:SetText(tips[s.key] or ""); GameTooltip:Show()
    end)
    tab:SetScript("OnLeave",function() GameTooltip:Hide() end)
    CMF.tabs[i] = tab
  end

  HSep(win, Y_SEP2)

  -- Macro Grid (centered)
  CMF.cells = {}
  local gridW = COLS * CELL_W
  local gridLeft = math.floor((WIN_W - gridW) / 2)

  for i = 1, PER_PAGE do
    local row = math.floor((i-1)/COLS)
    local col = (i-1) % COLS
    local cell = CreateFrame("Button",nil,win,"BackdropTemplate")
    cell:SetSize(CELL_W-2, CELL_H-2)
    cell:SetPoint("TOPLEFT", gridLeft + col*CELL_W + 1, Y_GRID - row*CELL_H - 1)
    MkBD(cell,0.09,0.09,0.13,0.9,0.2,0.2,0.28,0.7)

    local icon = cell:CreateTexture(nil,"ARTWORK")
    icon:SetSize(28,28); icon:SetPoint("TOP",0,-4)
    cell.iconTex = icon

    local selHL = cell:CreateTexture(nil,"OVERLAY")
    selHL:SetAllPoints(); selHL:SetColorTexture(0.25,0.55,1,0.22); selHL:Hide()
    cell.selHL = selHL

    local hovHL = cell:CreateTexture(nil,"HIGHLIGHT")
    hovHL:SetAllPoints(); hovHL:SetColorTexture(1,1,1,0.07)

    local nameLbl = cell:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    nameLbl:SetPoint("BOTTOMLEFT",2,2); nameLbl:SetPoint("BOTTOMRIGHT",-2,2)
    nameLbl:SetHeight(12); nameLbl:SetJustifyH("CENTER")
    cell.nameLbl = nameLbl

    cell.macroIndex = nil
    cell:RegisterForDrag("LeftButton")
    cell:SetScript("OnDragStart",function(self)
      if self.macroIndex and not InCombatLockdown() then
        PickupMacro(self.macroIndex)
      end
    end)
    cell:SetScript("OnClick",function(self)
      if self.macroIndex then SFA:CMF_SelectMacro(self.macroIndex) end
    end)
    cell:SetScript("OnEnter",function(self)
      if not self.macroIndex then return end
      local n,_,b = GetMacroInfo(self.macroIndex)
      if not n then return end
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
      GameTooltip:SetText(n,1,1,1)
      if b and b~="" then GameTooltip:AddLine(b:sub(1,200),0.8,0.8,0.8,true) end
      GameTooltip:AddLine("Drag to action bar",0.5,0.5,0.5)
      GameTooltip:Show()
    end)
    cell:SetScript("OnLeave",function() GameTooltip:Hide() end)
    CMF.cells[i] = cell
  end

  -- Page navigation
  local prevBtn = CreateFrame("Button",nil,win,"UIPanelButtonTemplate")
  prevBtn:SetSize(26,20); prevBtn:SetPoint("TOPLEFT",gridLeft,Y_PAGENAV); prevBtn:SetText("<")
  prevBtn:SetScript("OnClick",function()
    local pg = CMF.page[CMF.filter] or 1
    if pg>1 then CMF.page[CMF.filter]=pg-1; SFA:CMF_RefreshGrid() end
  end)
  CMF.prevBtn = prevBtn

  local pageLabel = win:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  pageLabel:SetPoint("LEFT",prevBtn,"RIGHT",4,0); pageLabel:SetText("1 / 1")
  CMF.pageLabel = pageLabel

  local nextBtn = CreateFrame("Button",nil,win,"UIPanelButtonTemplate")
  nextBtn:SetSize(26,20); nextBtn:SetPoint("LEFT",pageLabel,"RIGHT",4,0); nextBtn:SetText(">")
  nextBtn:SetScript("OnClick",function()
    local all = SFA:CMF_GetCurrentIndices()
    local tp = math.max(1,math.ceil(#all/PER_PAGE))
    local pg = CMF.page[CMF.filter] or 1
    if pg<tp then CMF.page[CMF.filter]=pg+1; SFA:CMF_RefreshGrid() end
  end)
  CMF.nextBtn = nextBtn

  local countLabel = win:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
  countLabel:SetPoint("TOPRIGHT",-8,Y_PAGENAV)
  CMF.countLabel = countLabel

  HSep(win, Y_SEP3)

  -- Macro Name
  local macNameHdr = win:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  macNameHdr:SetPoint("TOPLEFT",10,Y_MACNAME); macNameHdr:SetText("Macro Name:")

  local selIconBtn = CreateFrame("Button",nil,win,"BackdropTemplate")
  selIconBtn:SetSize(44,44); selIconBtn:SetPoint("TOPLEFT",8,Y_NAMEROW)
  MkBD(selIconBtn,0.1,0.1,0.15,1,0.3,0.3,0.45,1)
  local selIconTex = selIconBtn:CreateTexture(nil,"ARTWORK")
  selIconTex:SetSize(36,36); selIconTex:SetPoint("CENTER")
  selIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  CMF.selIconTex = selIconTex
  selIconBtn:SetScript("OnClick",function() SFA:CMF_OpenIconPopup() end)
  selIconBtn:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:SetText("Click to change macro icon"); GameTooltip:Show()
  end)
  selIconBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

  local nameBox = CreateFrame("EditBox",nil,win,"InputBoxTemplate")
  nameBox:SetSize(WIN_W-74,22); nameBox:SetPoint("TOPLEFT",58,Y_NAMEROW+2)
  nameBox:SetAutoFocus(false); nameBox:SetMaxLetters(16); nameBox:SetText("")
  nameBox:SetScript("OnTextChanged",function(self,user)
    if user then CMF.dirty=true; SFA:CMF_UpdateActionButtons() end
  end)
  nameBox:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
  nameBox:SetScript("OnEscapePressed",function(self) self:ClearFocus(); SFA:CMF_Close() end)
  CMF.nameBox = nameBox

  -- Macro Commands
  local macCmdHdr = win:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  macCmdHdr:SetPoint("TOPLEFT",8,Y_MACCMD); macCmdHdr:SetText("Enter Macro Commands:")

  -- Hint bar (autocomplete keybinds)
  local acHint = win:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
  acHint:SetPoint("TOPRIGHT",-8,Y_MACCMD)
  acHint:SetText("|cff666666Tab/↵ accept  ↑↓ navigate  Esc close|r")
  acHint:Hide()
  CMF.acHint = acHint

  -- Body frame
  local bodyBG = CreateFrame("Frame",nil,win,"BackdropTemplate")
  bodyBG:SetSize(WIN_W-16, BODY_H); bodyBG:SetPoint("TOPLEFT",8,Y_BODY)
  MkBD(bodyBG,0.03,0.03,0.05,0.95,0.2,0.2,0.3,0.8)
  CMF.bodyBG = bodyBG

  local bodyScroll = CreateFrame("ScrollFrame",nil,bodyBG,"UIPanelScrollFrameTemplate")
  bodyScroll:SetPoint("TOPLEFT",4,-4); bodyScroll:SetPoint("BOTTOMRIGHT",-26,4)

  local bodyEdit = CreateFrame("EditBox",nil,bodyScroll)
  bodyEdit:SetSize(WIN_W-60,300)
  bodyEdit:SetMultiLine(true); bodyEdit:SetAutoFocus(false)
  bodyEdit:SetMaxLetters(255)
  bodyEdit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
  bodyEdit:SetTextColor(1,1,1,1); bodyEdit:SetJustifyH("LEFT"); bodyEdit:SetJustifyV("TOP")
  bodyEdit:SetTextInsets(4,4,4,4); bodyEdit:SetText("")
  bodyScroll:SetScrollChild(bodyEdit)
  CMF.bodyEdit = bodyEdit

  local charCount = win:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
  charCount:SetPoint("BOTTOMLEFT", 10, BTN_Y2 + 2)
  charCount:SetText("0 / 255")
  CMF.charCount = charCount

  bodyEdit:SetScript("OnTextChanged",function(self,user)
    if user then CMF.dirty=true end
    local n = #(self:GetText() or "")
    if CMF.charCount then
      CMF.charCount:SetText(n.." / 255")
      if n>240 then CMF.charCount:SetTextColor(1,0.3,0.3,1)
      elseif n>200 then CMF.charCount:SetTextColor(1,0.75,0.2,1)
      else CMF.charCount:SetTextColor(0.55,0.55,0.55,1) end
    end
    if user then
      SFA:CMF_UpdateActionButtons()
      SFA:CMF_TriggerAutocomplete()
    end
  end)
  bodyEdit:SetScript("OnEnterPressed",function(self)
    if CMF.acFrame and CMF.acFrame:IsShown() and CMF.acSelected > 0 then
      SFA:CMF_ApplyAutocomplete()
    else
      self:Insert("\n")  -- Enter always inserts newline in macro editor
    end
  end)
  bodyEdit:SetScript("OnKeyDown",function(self, key)
    -- Block ALL propagation — no keybindings fire while typing
    self:SetPropagateKeyboardInput(false)
    if key == "ESCAPE" then
      self:ClearFocus()
      if CMF.acFrame then CMF.acFrame:Hide() end
    elseif CMF.acFrame and CMF.acFrame:IsShown() then
      if key == "TAB" then
        SFA:CMF_ApplyAutocomplete()
      elseif key == "UP" then
        SFA:CMF_NavigateAC(-1)
      elseif key == "DOWN" then
        SFA:CMF_NavigateAC(1)
      end
    end
  end)
  bodyEdit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    if CMF.acFrame then CMF.acFrame:Hide() end
  end)
  bodyEdit:SetScript("OnKeyUp", nil)
  bodyEdit:SetScript("OnEditFocusLost",function()
    C_Timer.After(0.15,function()
      if CMF.acFrame and not (CMF.acFrame.isHovered) then
        CMF.acFrame:Hide()
        CMF.acSelected=0
        if CMF.acHint then CMF.acHint:Hide() end
      end
    end)
  end)

  -- ── AUTOCOMPLETE FRAME ──────────────────────────────────────
  local acFrame = CreateFrame("Frame",nil,win,"BackdropTemplate")
  acFrame:SetSize(WIN_W-16, 20)
  acFrame:SetPoint("BOTTOMLEFT", bodyBG, "TOPLEFT", 0, 2)
  acFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  acFrame:SetFrameLevel(200)
  MkBD(acFrame,0.04,0.04,0.10,0.97,0.38,0.58,0.90,1)
  acFrame:EnableMouse(true)
  acFrame:SetScript("OnEnter",function(f) f.isHovered=true end)
  acFrame:SetScript("OnLeave",function(f) f.isHovered=false end)
  acFrame:Hide()
  CMF.acFrame = acFrame
  CMF.acSelected = 0
  CMF.acSuggestions = {}

  -- Header row in autocomplete
  local acHeader = acFrame:CreateFontString(nil,"OVERLAY")
  acHeader:SetFont("Fonts\\FRIZQT__.TTF",9,"")
  acHeader:SetPoint("TOPLEFT",6,-3)
  acHeader:SetTextColor(0.5,0.7,1,0.8)
  acHeader:SetText("Macro Autocomplete")
  CMF.acHeader = acHeader

  local acRows = {}
  for i = 1, 8 do
    local row = CreateFrame("Button",nil,acFrame)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT",0,-(i-1)*18-16)
    row:SetPoint("TOPRIGHT",0,-(i-1)*18-16)

    local hl = row:CreateTexture(nil,"HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(0.3,0.55,0.95,0.25)

    local selTex = row:CreateTexture(nil,"BACKGROUND")
    selTex:SetAllPoints(); selTex:SetColorTexture(0.18,0.42,0.80,0.30); selTex:Hide()
    row.selTex = selTex

    local typeLbl = row:CreateFontString(nil,"OVERLAY")
    typeLbl:SetFont("Fonts\\FRIZQT__.TTF",9,"")
    typeLbl:SetPoint("LEFT",6,0); typeLbl:SetWidth(52); typeLbl:SetJustifyH("LEFT")
    row.typeLbl = typeLbl

    local textLbl = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    textLbl:SetPoint("LEFT",62,0); textLbl:SetPoint("RIGHT",-4,0); textLbl:SetJustifyH("LEFT")
    row.textLbl = textLbl

    row:SetScript("OnEnter",function() acFrame.isHovered=true end)
    row:SetScript("OnLeave",function() acFrame.isHovered=false end)
    row:SetScript("OnClick",function(self)
      CMF.acSelected = i
      SFA:CMF_ApplyAutocomplete()
      if CMF.bodyEdit then CMF.bodyEdit:SetFocus() end
    end)
    row:Hide()
    acRows[i] = row
  end
  CMF.acRows = acRows

  HSep(win, Y_SEP4)

  -- Save / Cancel
  local saveBtn = CreateFrame("Button",nil,win,"UIPanelButtonTemplate")
  saveBtn:SetSize(86,24); saveBtn:SetPoint("BOTTOMRIGHT",-8,BTN_Y2)
  saveBtn:SetText("Save"); saveBtn:SetEnabled(false)
  saveBtn:SetScript("OnClick",function() SFA:CMF_SaveMacro() end)
  CMF.saveBtn = saveBtn

  local cancelBtn = CreateFrame("Button",nil,win,"UIPanelButtonTemplate")
  cancelBtn:SetSize(86,24); cancelBtn:SetPoint("RIGHT",saveBtn,"LEFT",-6,0)
  cancelBtn:SetText("Cancel"); cancelBtn:SetEnabled(false)
  cancelBtn:SetScript("OnClick",function() SFA:CMF_CancelEdit() end)
  CMF.cancelBtn = cancelBtn

  -- Delete / New
  local delBtn = CreateFrame("Button",nil,win,"UIPanelButtonTemplate")
  delBtn:SetSize(86,24); delBtn:SetPoint("BOTTOMLEFT",8,BTN_Y1)
  delBtn:SetText("Delete"); delBtn:SetEnabled(false)
  delBtn:SetScript("OnClick",function() SFA:CMF_DeleteMacro() end)
  CMF.delBtn = delBtn

  local newBtn = CreateFrame("Button",nil,win,"UIPanelButtonTemplate")
  newBtn:SetSize(86,24); newBtn:SetPoint("LEFT",delBtn,"RIGHT",6,0)
  newBtn:SetText("New")
  newBtn:SetScript("OnClick",function() SFA:CMF_NewMacro() end)
end

-- ============================================================
-- AUTOCOMPLETE LOGIC
-- ============================================================

function SFA:CMF_TriggerAutocomplete()
  local edit = CMF.bodyEdit
  if not edit or not CMF.acFrame then return end

  local text   = edit:GetText() or ""
  local cursor = edit:GetCursorPosition() or 0
  local before = text:sub(1, cursor)
  local line   = before:match("[^\n]*$") or ""
  local lLine  = line:lower()

  local sugs = {}
  local mode = nil

  -- 1. Slash command: line starts with /
  local slashToken = lLine:match("^(/%S*)$")
  if slashToken and #slashToken >= 1 then
    mode = "slash"
    for _, cmd in ipairs(AC_SLASH) do
      if cmd:sub(1, #slashToken) == slashToken then
        sugs[#sugs+1] = {insert=cmd, label=cmd, mode="slash"}
        if #sugs >= 8 then break end
      end
    end

  -- 2. Inside unclosed bracket [ → conditions
  elseif line:find("%[") and not line:match("%[[^%[]*%]") then
    -- Partial condition after [ or ,
    local partial = lLine:match("[%[,]%s*([%w:!%-]*)$") or ""
    mode = "cond"
    for _, cond in ipairs(AC_CONDS) do
      if cond:sub(1, #partial) == partial then
        sugs[#sugs+1] = {insert=cond, label=cond, mode="cond"}
        if #sugs >= 8 then break end
      end
    end

    -- Also: @unit inside brackets
    local unitPartial = lLine:match("@([%w]*)$")
    if unitPartial then
      mode = "unit"
      sugs = {}
      for _, u in ipairs(AC_UNITS) do
        if u:sub(1, #unitPartial) == unitPartial then
          sugs[#sugs+1] = {insert=u, label="@"..u, mode="unit"}
          if #sugs >= 8 then break end
        end
      end
    end

  -- 3. Spell name: after any /command, including after ; separator
  elseif lLine:match("/%S+%s") then
    local spellPart = ""
    local afterSemi = line:match(";%s*([^;]*)$")
    if afterSemi then
      spellPart = afterSemi:match("^%s*(.-)%s*$") or ""
    else
      spellPart = line:match("%]%s*(.-)$") or line:match("^%s*/%S+%s+(.-)$") or ""
      spellPart = spellPart:gsub("^%s+","")
    end
    spellPart = spellPart:lower()
    if #spellPart >= 2 then
      mode = "spell"
      local spellSet = self.macroOrgSpellSet or {}
      local seen = {}
      for spell in pairs(spellSet) do
        if spell:find(spellPart, 1, true) and not seen[spell] then
          seen[spell] = true
          local proper = spell:gsub("(%a)([%w']*)",function(f,r) return f:upper()..r end)
          sugs[#sugs+1] = {insert=proper, label=proper, mode="spell"}
          if #sugs >= 8 then break end
        end
      end
      table.sort(sugs, function(a,b)
        local aStart = a.label:lower():find(spellPart,1,true) == 1
        local bStart = b.label:lower():find(spellPart,1,true) == 1
        if aStart ~= bStart then return aStart end
        return a.label < b.label
      end)
    end
  end

  if #sugs == 0 or not mode then
    CMF.acFrame:Hide(); CMF.acSelected=0
    if CMF.acHint then CMF.acHint:Hide() end
    return
  end

  -- Store for navigation/apply
  CMF.acSuggestions = sugs
  CMF.acMode        = mode
  CMF.acCursorSnap  = cursor
  CMF.acLine        = line

  -- Populate rows
  local typeColors = {slash=AC_COLORS.slash, cond=AC_COLORS.cond, unit=AC_COLORS.unit, spell=AC_COLORS.spell}
  local typeNames  = {slash="cmd", cond="[cond]", unit="@unit", spell="spell"}

  for i, row in ipairs(CMF.acRows) do
    local sug = sugs[i]
    if sug then
      local col = typeColors[sug.mode] or "|cffaaaaaa"
      row.typeLbl:SetText(col..(typeNames[sug.mode] or "").."  |r")
      row.textLbl:SetText(sug.label)
      row.suggestion = sug
      row:Show()
    else
      row:Hide()
    end
    row.selTex:Hide()
  end

  -- Height = header(16) + rows(18 each)
  CMF.acFrame:SetHeight(16 + #sugs * 18 + 2)

  -- Default select first
  if CMF.acSelected < 1 or CMF.acSelected > #sugs then
    CMF.acSelected = 1
  end
  self:CMF_UpdateACHighlight()

  CMF.acFrame:Show(); CMF.acFrame:Raise()
  if CMF.acHint then CMF.acHint:Show() end
end

function SFA:CMF_NavigateAC(dir)
  local n = CMF.acSuggestions and #CMF.acSuggestions or 0
  if n == 0 then return end
  CMF.acSelected = CMF.acSelected + dir
  if CMF.acSelected < 1 then CMF.acSelected = n end
  if CMF.acSelected > n then CMF.acSelected = 1 end
  self:CMF_UpdateACHighlight()
end

function SFA:CMF_UpdateACHighlight()
  for i, row in ipairs(CMF.acRows or {}) do
    if row.selTex then row.selTex:SetShown(i == CMF.acSelected) end
  end
end

function SFA:CMF_ApplyAutocomplete()
  local sugs = CMF.acSuggestions
  local sel  = CMF.acSelected
  if not sugs or sel < 1 or sel > #sugs then return end
  local sug  = sugs[sel]
  local edit = CMF.bodyEdit
  if not edit or not sug then return end

  local text   = edit:GetText() or ""
  local cursor = CMF.acCursorSnap or edit:GetCursorPosition()
  local before = text:sub(1, cursor)
  local after  = text:sub(cursor+1)
  local newBefore

  if sug.mode == "slash" then
    -- Replace from last / to cursor
    newBefore = before:gsub("(/%S*)$", sug.insert)

  elseif sug.mode == "cond" then
    -- Replace partial condition after [ or ,
    newBefore = before:gsub("([%[,]%s*)([%w:!%-]*)$",
      function(prefix) return prefix .. sug.insert end)

  elseif sug.mode == "unit" then
    -- Replace after @
    newBefore = before:gsub("@[%w]*$", "@" .. sug.insert)

  elseif sug.mode == "spell" then
    local semiPos = before:find(";[^;]*$")
    if semiPos then
      local prefix = before:match("^(.*;%s*)"); if prefix then newBefore=prefix..sug.insert.." " end
    end
    if not newBefore or newBefore==before then
      newBefore=before:gsub("([%]%s])([%w%s'%-]*)$",function(sep) return sep..sug.insert.." " end)
    end
    if not newBefore or newBefore==before then
      newBefore=before:gsub("(%s)([%S]*)$",function(sp) return sp..sug.insert.." " end)
    end
    if not newBefore or newBefore==before then newBefore=before..sug.insert.." " end
  end

  if newBefore and newBefore ~= before then
    edit:SetText(newBefore .. after)
    edit:SetCursorPosition(#newBefore)
  end

  CMF.acFrame:Hide(); CMF.acSelected=0; CMF.acSuggestions={}
  if CMF.acHint then CMF.acHint:Hide() end
end

-- ============================================================
-- ICON POPUP
-- ============================================================

-- ============================================================
-- ICON PICKER (grid, similar to native WoW MacroPopupFrame)
-- ============================================================

local ICON_PICKER = {}  -- state for the icon picker popup

-- Known WoW icon names for the grid (subset of Interface\Icons\*)
-- We populate dynamically using GetMacroIconInfo which returns (numIcons)
-- and GetMacroIconInfo(index) which returns the texture path.

local function SFA_BuildIconPicker()
  if ICON_PICKER.frame then return end

  local COLS_IP  = 10
  local ROWS_IP  = 9
  local CELL_S   = 36
  local PAD      = 6
  local PIC_W    = COLS_IP * CELL_S + (COLS_IP+1)*PAD + 20  -- +20 for scrollbar
  local PIC_H    = ROWS_IP * CELL_S + (ROWS_IP+1)*PAD + 90

  local pop = CreateFrame("Frame", "SFA_IconPickerFrame", UIParent, "BackdropTemplate")
  pop:SetSize(PIC_W, PIC_H)
  pop:SetPoint("CENTER")
  pop:SetFrameStrata("FULLSCREEN_DIALOG")
  pop:SetMovable(true)
  pop:EnableMouse(true)
  pop:RegisterForDrag("LeftButton")
  pop:SetScript("OnDragStart", pop.StartMoving)
  pop:SetScript("OnDragStop",  pop.StopMovingOrSizing)
  MkBD(pop, 0.05,0.05,0.10,0.99, 0.4,0.4,0.6,1)
  pop:Hide()
  ICON_PICKER.frame = pop

  -- Title
  local title = pop:CreateFontString(nil,"OVERLAY","GameFontHighlight")
  title:SetPoint("TOP",0,-10)
  title:SetText("Choose an Icon:")

  -- Search box
  local searchBox = CreateFrame("EditBox", nil, pop, "InputBoxTemplate")
  searchBox:SetSize(PIC_W - 40, 22)
  searchBox:SetPoint("TOPLEFT", 10, -30)
  searchBox:SetAutoFocus(false)
  searchBox:SetMaxLetters(64)
  ICON_PICKER.searchBox = searchBox

  -- Scroll frame for the icon grid
  local sf = CreateFrame("ScrollFrame", nil, pop, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 10, -58)
  sf:SetPoint("BOTTOMRIGHT", -26, 50)
  ICON_PICKER.scroll = sf

  local grid = CreateFrame("Frame", nil, sf)
  grid:SetSize(COLS_IP * CELL_S + (COLS_IP+1)*PAD, 1)  -- height set dynamically
  sf:SetScrollChild(grid)
  ICON_PICKER.grid = grid

  -- Pre-create cell buttons
  ICON_PICKER.cells = {}
  for row = 0, 39 do   -- 40 rows * 10 cols = 400 cells, enough for full list
    for col = 0, COLS_IP-1 do
      local btn = CreateFrame("Button", nil, grid, "BackdropTemplate")
      btn:SetSize(CELL_S, CELL_S)
      btn:SetPoint("TOPLEFT",
        PAD + col*(CELL_S+PAD),
        -(PAD + row*(CELL_S+PAD)))
      MkBD(btn, 0.1,0.1,0.15,1, 0.25,0.25,0.35,1)

      local tex = btn:CreateTexture(nil,"ARTWORK")
      tex:SetSize(CELL_S-4, CELL_S-4)
      tex:SetPoint("CENTER")
      btn.iconTex = tex

      local hl = btn:CreateTexture(nil,"HIGHLIGHT")
      hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.2)

      local sel = btn:CreateTexture(nil,"OVERLAY")
      sel:SetAllPoints(); sel:SetColorTexture(0.3,0.6,1,0.35); sel:Hide()
      btn.selTex = sel

      btn:SetScript("OnClick", function(self)
        -- deselect previous
        if ICON_PICKER.selectedBtn then
          ICON_PICKER.selectedBtn.selTex:Hide()
        end
        ICON_PICKER.selectedBtn = self
        self.selTex:Show()
        ICON_PICKER.selectedIcon = self.iconPath
      end)

      ICON_PICKER.cells[#ICON_PICKER.cells+1] = btn
    end
  end

  -- Okay / Cancel buttons
  local okBtn = CreateFrame("Button", nil, pop, "UIPanelButtonTemplate")
  okBtn:SetSize(80,22); okBtn:SetText("Okay")
  okBtn:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -40, 14)
  okBtn:SetScript("OnClick", function()
    local icon = ICON_PICKER.selectedIcon
    if icon and icon ~= "" then
      CMF.pendingIcon = icon; CMF.dirty = true
      if CMF.selIconTex then CMF.selIconTex:SetTexture(icon) end
      SFA:CMF_UpdateActionButtons()
    end
    pop:Hide()
  end)

  local cancelBtn = CreateFrame("Button", nil, pop, "UIPanelButtonTemplate")
  cancelBtn:SetSize(80,22); cancelBtn:SetText("Cancel")
  cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -6, 0)
  cancelBtn:SetScript("OnClick", function() pop:Hide() end)

  -- Refresh button (re-collect icons / flush cache)
  local refreshBtn = CreateFrame("Button", nil, pop, "UIPanelButtonTemplate")
  refreshBtn:SetSize(80,22); refreshBtn:SetText("Refresh")
  refreshBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -6, 0)
  refreshBtn:SetScript("OnClick", function() SFA:CMF_RefreshIcons() end)

  -- Filter on search text change
  searchBox:SetScript("OnTextChanged", function()
    SFA_RefreshIconGrid(searchBox:GetText())
  end)
  searchBox:SetScript("OnEnterPressed", function()
    if ICON_PICKER.visibleCount == 1 and ICON_PICKER.cells[1].iconPath then
      ICON_PICKER.selectedIcon = ICON_PICKER.cells[1].iconPath
    end
    okBtn:GetScript("OnClick")()
  end)
  searchBox:SetScript("OnEscapePressed", function()
    pop:Hide()
  end)
  pop:EnableKeyboard(false)
  pop:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      pop:Hide()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)
  pop:SetScript("OnShow", function(self) self:EnableKeyboard(true) end)
  pop:SetScript("OnHide", function(self) self:EnableKeyboard(false) end)
end

-- ============================================================
-- HELPER: collect icon textures from MacroPopupFrame buttons
-- First open: taint accepted once, icons cached in memory.
-- Subsequent opens: instant from cache, no taint.
-- ============================================================

local SFA_ICON_CACHE = nil  -- nil = not yet collected

local function SFA_ScanPopupButtons()
  local list = {}
  local seen = {}
  if not MacroPopupFrame then return list end
  local function scan(f, depth)
    if depth > 8 then return end
    local ok, n = pcall(function() return f:GetNumChildren() end)
    if not ok or not n then return end
    for i = 1, n do
      local ok2, c = pcall(function() return select(i, f:GetChildren()) end)
      if ok2 and c then
        local ot = c:GetObjectType()
        if ot == "Button" or ot == "CheckButton" then
          local tex = nil
          if c.GetNormalTexture then
            local nt = c:GetNormalTexture()
            if nt and nt.GetTexture then tex = nt:GetTexture() end
          end
          if tex then
            local key = tostring(tex)
            if not seen[key] then seen[key] = true; list[#list+1] = tex end
          end
        end
        scan(c, depth + 1)
      end
    end
  end
  scan(MacroPopupFrame, 0)
  return list
end

local SFA_Collecting = false

local function SFA_DoCollect(onDone)
  if SFA_Collecting then return end
  SFA_Collecting = true
  SFA._iconCollecting = true  -- prevent ShowMacroFrame hook from redirecting to our window

  -- Ensure the Blizzard macro UI addon is loaded (it's load-on-demand).
  -- When opening from Settings, MacroFrame may not exist yet.
  local loader = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
  if loader then pcall(loader, "Blizzard_MacroUI") end

  -- Show MacroFrame + click edit button (taint happens here, once per session)
  -- Use the original (un-hooked) ShowMacroFrame so we get the native frame.
  local showFn = SFA._origShowMacroFrame or ShowMacroFrame
  if showFn then showFn()
  elseif MacroFrame then MacroFrame:Show() end

  -- MacroEditButton's OnClick is what populates MacroPopupFrame with icons.
  -- It may not exist until the frame above is shown, so look it up after.
  local function clickEdit()
    local editBtn = _G["MacroEditButton"]
    if editBtn then
      local onclick = editBtn:GetScript("OnClick")
      if onclick then pcall(onclick, editBtn, "LeftButton") end
    end
  end
  clickEdit()
  -- Retry the edit click shortly after, in case the frame loaded async
  C_Timer.After(0.1, clickEdit)

  -- Poll until MacroPopupFrame has icon textures
  local attempts = 0
  local function poll()
    attempts = attempts + 1
    local list = SFA_ScanPopupButtons()
    if #list > 0 then
      SFA_ICON_CACHE = list
      SFA_Collecting = false
      SFA._iconCollecting = false
      -- Hide native frames properly via HideUIPanel to deregister from panel manager
      if MacroPopupFrame then MacroPopupFrame:Hide() end
      if HideUIPanel and MacroFrame then HideUIPanel(MacroFrame)
      elseif HideMacroFrame then HideMacroFrame()
      elseif MacroFrame then MacroFrame:Hide() end
      if onDone then onDone() end
    elseif attempts < 60 then
      -- Keep nudging the native UI to open/populate the icon popup
      if attempts % 5 == 0 then
        local sf = SFA._origShowMacroFrame or ShowMacroFrame
        if sf then sf()
        elseif MacroFrame then MacroFrame:Show() end
        clickEdit()
      end
      C_Timer.After(0.1, poll)
    else
      SFA_ICON_CACHE = {}
      SFA_Collecting = false
      SFA._iconCollecting = false
      if MacroPopupFrame then MacroPopupFrame:Hide() end
      if HideUIPanel and MacroFrame then HideUIPanel(MacroFrame)
      elseif HideMacroFrame then HideMacroFrame()
      elseif MacroFrame then MacroFrame:Hide() end
      if onDone then onDone() end
    end
  end
  C_Timer.After(0.15, poll)
end

function SFA:CMF_PrefetchIcons() end  -- no-op, collection happens on first picker open

function SFA_RefreshIconGrid(filter)
  filter = filter and filter:lower() or ""
  local cells = ICON_PICKER.cells
  local idx   = 0
  for _, c in ipairs(cells) do c:Hide(); c.iconPath = nil end

  local COLS_IP = 10
  local CELL_S  = 36
  local PAD     = 6

  local function showIcon(tex)
    if not tex then return end
    local name = tostring(tex):lower()
    if filter ~= "" and not name:find(filter, 1, true) then return end
    idx = idx + 1
    local c = cells[idx]
    if not c then return end
    c.iconPath = tex
    c.iconTex:SetTexture(tex)
    local row = math.floor((idx-1)/COLS_IP)
    local col = (idx-1) % COLS_IP
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", PAD + col*(CELL_S+PAD), -(PAD + row*(CELL_S+PAD)))
    c:Show()
    if ICON_PICKER.selectedIcon and tostring(tex) == tostring(ICON_PICKER.selectedIcon) then
      c.selTex:Show(); ICON_PICKER.selectedBtn = c
    else
      c.selTex:Hide()
    end
  end

  local numIcons = GetNumMacroIcons and GetNumMacroIcons() or 0
  if numIcons > 0 then
    for i = 1, numIcons do showIcon(GetMacroIconInfo(i)) end
  elseif SFA_ICON_CACHE then
    for _, tex in ipairs(SFA_ICON_CACHE) do showIcon(tex) end
  end

  ICON_PICKER.visibleCount = idx
  local rows = math.ceil(math.max(idx, 1) / COLS_IP)
  ICON_PICKER.grid:SetSize(
    COLS_IP * CELL_S + (COLS_IP+1)*PAD,
    rows * (CELL_S+PAD) + PAD)
end

function SFA:CMF_OpenIconPopup()
  if not CMF.selected then return end

  SFA_BuildIconPicker()

  ICON_PICKER.selectedBtn  = nil
  ICON_PICKER.selectedIcon = nil
  ICON_PICKER.scroll:SetVerticalScroll(0)
  ICON_PICKER.searchBox:SetText("")
  ICON_PICKER.searchBox:ClearFocus()

  local _, currentIcon = GetMacroInfo(CMF.selected)
  if currentIcon then ICON_PICKER.selectedIcon = currentIcon end

  ICON_PICKER.frame:Show()

  -- Always recollect on open (auto cache-flush) so icons reliably appear
  SFA_ICON_CACHE = nil

  if not ICON_PICKER.loadingLabel then
    local lbl = ICON_PICKER.grid:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    lbl:SetPoint("TOPLEFT",10,-10)
    ICON_PICKER.loadingLabel = lbl
  end
  ICON_PICKER.loadingLabel:SetText("Loading icons...")
  ICON_PICKER.loadingLabel:Show()

  SFA_DoCollect(function()
    if ICON_PICKER.loadingLabel then ICON_PICKER.loadingLabel:Hide() end
    if ICON_PICKER.frame:IsShown() then
      SFA_RefreshIconGrid(ICON_PICKER.searchBox:GetText() or "")
    end
  end)
end

-- Public helper for the in-window Refresh button
function SFA:CMF_RefreshIcons()
  SFA_ICON_CACHE = nil
  if ICON_PICKER and ICON_PICKER.frame and ICON_PICKER.frame:IsShown() then
    if ICON_PICKER.loadingLabel then
      ICON_PICKER.loadingLabel:SetText("Loading icons...")
      ICON_PICKER.loadingLabel:Show()
    end
    SFA_DoCollect(function()
      if ICON_PICKER.loadingLabel then ICON_PICKER.loadingLabel:Hide() end
      if ICON_PICKER.frame:IsShown() then
        SFA_RefreshIconGrid(ICON_PICKER.searchBox:GetText() or "")
      end
    end)
  end
end

function SFA:CMF_RefreshGrid()
  if not CMF.cells then return end
  local indices, total = self:CMF_GetPageIndices()
  local page = CMF.page[CMF.filter] or 1
  local totalPages = math.max(1,math.ceil(total/PER_PAGE))

  if CMF.prevBtn  then CMF.prevBtn:SetEnabled(page>1) end
  if CMF.nextBtn  then CMF.nextBtn:SetEnabled(page<totalPages) end
  if CMF.pageLabel then CMF.pageLabel:SetText(page.." / "..totalPages) end
  if CMF.countLabel then CMF.countLabel:SetText(total.." macro(s)") end

  for i,cell in ipairs(CMF.cells) do
    local mIdx = indices[i]
    cell.macroIndex = mIdx
    if mIdx then
      local name,icon = GetMacroInfo(mIdx)
      cell.iconTex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      cell.iconTex:SetVertexColor(1,1,1,1)
      cell.iconTex:Show()
      local short = name or ""
      if #short > 9 then short=short:sub(1,8)..".." end
      cell.nameLbl:SetText(short)
      cell.selHL:SetShown(mIdx == CMF.selected)
    else
      cell.iconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      cell.iconTex:SetVertexColor(0.3,0.3,0.3,0.35)
      cell.iconTex:Show()
      cell.nameLbl:SetText("")
      cell.selHL:Hide()
    end
  end
  self:CMF_UpdateTabLabels()
end

function SFA:CMF_UpdateTabLabels()
  if not CMF.tabs then return end
  local counts = {global=#CMF.cache.global, class=#CMF.cache.class, character=#CMF.cache.character}
  for _,tab in ipairs(CMF.tabs) do
    if tab.label then tab.label:SetText(tab.baseLbl.." ("..tostring(counts[tab.key] or 0)..")") end
    local active = (tab.key == CMF.filter)
    if tab.SetBackdropColor then
      if active then tab:SetBackdropColor(0.18,0.50,0.92,0.95)
      else           tab:SetBackdropColor(0.08,0.08,0.13,0.93) end
    end
    if tab.SetBackdropBorderColor then
      if active then tab:SetBackdropBorderColor(0.42,0.68,1,1)
      else           tab:SetBackdropBorderColor(0.22,0.22,0.32,0.8) end
    end
    if tab.label then
      if active then tab.label:SetTextColor(1,1,1,1); tab.label:SetFont("Fonts\\FRIZQT__.TTF",11,"OUTLINE")
      else tab.label:SetTextColor(0.65,0.65,0.65,1); tab.label:SetFont("Fonts\\FRIZQT__.TTF",10,"") end
    end
  end
end

-- ============================================================
-- SELECT / SAVE / DELETE / NEW
-- ============================================================

function SFA:CMF_SelectMacro(idx)
  if not idx then return end
  CMF.selected=idx; CMF.dirty=false; CMF.pendingIcon=nil
  local name,icon,body = GetMacroInfo(idx)
  if not name then return end
  if CMF.nameBox   then CMF.nameBox:SetText(name); CMF.nameBox:SetCursorPosition(0) end
  if CMF.bodyEdit  then CMF.bodyEdit:SetText(body or ""); CMF.bodyEdit:SetCursorPosition(0) end
  if CMF.selIconTex then CMF.selIconTex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark") end
  if CMF.charCount then CMF.charCount:SetText(#(body or "").." / 255") end
  for _,cell in ipairs(CMF.cells) do cell.selHL:SetShown(cell.macroIndex==idx) end
  self:CMF_UpdateActionButtons()
end

function SFA:CMF_UpdateActionButtons()
  local has = (CMF.selected~=nil)
  if CMF.saveBtn   then CMF.saveBtn:SetEnabled(has and CMF.dirty) end
  if CMF.cancelBtn then CMF.cancelBtn:SetEnabled(has and CMF.dirty) end
  if CMF.delBtn    then CMF.delBtn:SetEnabled(has) end
end

function SFA:CMF_SaveMacro()
  if not CMF.selected then return end
  if InCombatLockdown() then SFA.Print("Cannot save macros in combat.") return end
  local name = CMF.nameBox and CMF.nameBox:GetText() or ""
  local body = CMF.bodyEdit and CMF.bodyEdit:GetText() or ""
  local icon = CMF.pendingIcon or select(2,GetMacroInfo(CMF.selected)) or "INV_Misc_QuestionMark"
  if name=="" then name="Macro" end
  local ok,err = pcall(EditMacro,CMF.selected,name,icon,body)
  if ok then
    CMF.dirty=false; CMF.pendingIcon=nil
    self:CMF_BuildCache(); self:CMF_RefreshGrid()
    SFA.Print("Macro '"..name.."' saved.")
  else SFA.Print("Save error: "..(err or "")) end
  self:CMF_UpdateActionButtons()
end

function SFA:CMF_CancelEdit()
  if CMF.selected then CMF.dirty=false; CMF.pendingIcon=nil; self:CMF_SelectMacro(CMF.selected) end
end

function SFA:CMF_DeleteMacro()
  if not CMF.selected then return end
  if InCombatLockdown() then SFA.Print("Cannot delete macros in combat.") return end
  local name = select(1,GetMacroInfo(CMF.selected)) or "?"
  local ok,err = pcall(DeleteMacro,CMF.selected)
  if ok then
    SFA.Print("Macro '"..name.."' deleted.")
    CMF.selected=nil; CMF.dirty=false
    if CMF.nameBox   then CMF.nameBox:SetText("") end
    if CMF.bodyEdit  then CMF.bodyEdit:SetText("") end
    if CMF.charCount then CMF.charCount:SetText("0 / 255") end
    if CMF.selIconTex then CMF.selIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
    self:CMF_BuildCache(); self:CMF_RefreshGrid()
  else SFA.Print("Delete error: "..(err or "")) end
  self:CMF_UpdateActionButtons()
end

function SFA:CMF_NewMacro()
  if InCombatLockdown() then SFA.Print("Cannot create macros in combat.") return end
  local numGlobal = select(1,GetNumMacros()) or 0
  if numGlobal >= 120 then SFA.Print("Global macro limit (120) reached.") return end
  local ok,newIdx = pcall(CreateMacro,"New Macro","INV_Misc_QuestionMark","",false)
  if ok and newIdx then
    self:CMF_BuildCache()
    CMF.filter="global"
    CMF.page.global=math.ceil(#CMF.cache.global/PER_PAGE)
    self:CMF_RefreshGrid(); self:CMF_SelectMacro(newIdx)
    if CMF.nameBox then CMF.nameBox:SetFocus() end
    SFA.Print("New macro created. Enter name and commands, then Save.")
  else SFA.Print("Could not create macro.") end
end

function SFA:CMF_SetFilter(key)
  CMF.filter=key; self:CMF_RefreshGrid()
end

-- ============================================================
-- OPEN / CLOSE / TOGGLE
-- ============================================================

function SFA:CMF_Open()
  self:CMF_CreateWindow()
  if not CMF.window then return end
  self:CMF_BuildCache()
  CMF.selected=nil; CMF.dirty=false
  if CMF.nameBox   then CMF.nameBox:SetText("") end
  if CMF.bodyEdit  then CMF.bodyEdit:SetText("") end
  if CMF.charCount then CMF.charCount:SetText("0 / 255") end
  if CMF.selIconTex then CMF.selIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
  if CMF.acFrame   then CMF.acFrame:Hide() end
  self:CMF_UpdateActionButtons(); self:CMF_RefreshGrid()
  CMF.window:EnableKeyboard(true)
  CMF.window:Show(); CMF.window:Raise()
end

function SFA:CMF_Close()
  if CMF.window then
    CMF.window:EnableKeyboard(false)
    CMF.window:Hide()
  end
  if CMF.iconPopup then CMF.iconPopup:Hide() end
  if CMF.acFrame then CMF.acFrame:Hide() end
end

function SFA:CMF_Toggle()
  if CMF.window and CMF.window:IsShown() then self:CMF_Close()
  else self:CMF_Open() end
end

-- ============================================================
-- SLASH HOOKS
-- ============================================================

function SFA:MacroFrame_Init()
  if not SFA._origMacroSlash then SFA._origMacroSlash = SlashCmdList["MACRO"] end
  self:MacroFrame_UpdateSlashHook()
  self:MacroFrame_HookGameMenu()
end

function SFA:MacroFrame_UpdateSlashHook()
  if self.db and self.db.other and self.db.other.redesignMacroWindow then
    SlashCmdList["MACRO"] = function() SFA:CMF_Toggle() end
    SLASH_MACRO1 = "/macro"
  else
    if SFA._origMacroSlash then SlashCmdList["MACRO"] = SFA._origMacroSlash end
  end
end

-- Redirect the Game Menu "Macros" button (and any ShowMacroFrame call)
-- to the custom SFA window when the redesign option is enabled.
function SFA:MacroFrame_HookGameMenu()
  if SFA._macroGameMenuHooked then return end
  SFA._macroGameMenuHooked = true

  -- ToggleMacroFrame is what the Game Menu "Macros" button calls.
  if type(ToggleMacroFrame) == "function" and not SFA._origToggleMacroFrame then
    SFA._origToggleMacroFrame = ToggleMacroFrame
    ToggleMacroFrame = function(...)
      if SFA.db and SFA.db.other and SFA.db.other.redesignMacroWindow then
        -- Close the game menu if open, then show our window
        if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
        SFA:CMF_Toggle()
        return
      end
      return SFA._origToggleMacroFrame(...)
    end
  end

  -- Some clients call ShowMacroFrame directly from the menu.
  if type(ShowMacroFrame) == "function" and not SFA._origShowMacroFrame then
    SFA._origShowMacroFrame = ShowMacroFrame
    -- NOTE: we still need the original for icon collection, so only redirect
    -- when the call did NOT come from our own collector.
    ShowMacroFrame = function(...)
      if SFA._iconCollecting then
        return SFA._origShowMacroFrame(...)
      end
      if SFA.db and SFA.db.other and SFA.db.other.redesignMacroWindow then
        if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
        SFA:CMF_Open()
        return
      end
      return SFA._origShowMacroFrame(...)
    end
  end
end

SLASH_SFAMACRO1 = "/sfamacro"
SlashCmdList["SFAMACRO"] = function() SFA:CMF_Toggle() end
