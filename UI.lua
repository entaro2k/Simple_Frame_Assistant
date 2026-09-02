local addonName, SFA = ...
SFA = _G[addonName] or SFA


-- ============================================================
-- SHARED AUTOCOMPLETE DATA
-- ============================================================
local UI_AC_SLASH = {
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
local UI_AC_CONDS = {
  "mod:alt","mod:ctrl","mod:shift",
  "mod:lalt","mod:ralt","mod:lctrl","mod:rctrl","mod:lshift","mod:rshift",
  "combat","nocombat","stealth","nostealth","mounted","nomounted",
  "swimming","flyable","flying","exists","noexists","dead","nodead",
  "harm","noharm","help","nohelp","indoors","outdoors","party","raid",
  "vehicle","cursor","btn:1","btn:2","btn:3",
  "stance:1","stance:2","stance:3","stance:4",
  "form:0","form:1","form:2","form:3","form:4",
  "spec:1","spec:2","channeling:","equipped:",
  "unithasvehicleui","canexitvehicle",
  "target=target","target=player","target=focus",
  "target=mouseover","target=cursor","target=pet","target=none",
}
local UI_AC_UNITS = {
  "target","player","focus","mouseover","cursor","none",
  "pet","pettarget",
  "arena1","arena2","arena3","arena1target","arena2target","arena3target",
  "party1","party2","party3","party4",
  "party1target","party2target","party3target","party4target",
  "boss1","boss2","boss3","raid1","raid2","raid3",
  "lasttarget","lastunit",
}
local UI_AC_COLORS = {
  slash="|cff88ddff", cond="|cff88ff99", unit="|cffffcc66", spell="|cffddaaff",
}
local UI_AC_TYPE_NAMES = {slash="cmd", cond="[cond]", unit="@unit", spell="spell"}

local function UI_AC_GetSuggestions(editBox)
  local text   = editBox:GetText() or ""
  local cursor = editBox:GetCursorPosition() or 0
  local before = text:sub(1, cursor)
  local line   = before:match("[^\n]*$") or ""
  local lLine  = line:lower()
  local sugs, mode = {}, nil

  local slashToken = lLine:match("^(/%S*)$")
  if slashToken and #slashToken >= 1 then
    mode = "slash"
    for _, cmd in ipairs(UI_AC_SLASH) do
      if cmd:sub(1,#slashToken)==slashToken then
        sugs[#sugs+1]={insert=cmd,label=cmd,mode="slash"}
        if #sugs>=8 then break end
      end
    end
  elseif line:find("%[") and not line:match("%[[^%[]*%]") then
    local unitPartial = lLine:match("@([%w]*)$")
    if unitPartial then
      mode = "unit"
      for _, u in ipairs(UI_AC_UNITS) do
        if u:sub(1,#unitPartial)==unitPartial then
          sugs[#sugs+1]={insert=u,label="@"..u,mode="unit"}
          if #sugs>=8 then break end
        end
      end
    else
      local partial = lLine:match("[%[,]%s*([%w:!%-]*)$") or ""
      mode = "cond"
      for _, cond in ipairs(UI_AC_CONDS) do
        if cond:sub(1,#partial)==partial then
          sugs[#sugs+1]={insert=cond,label=cond,mode="cond"}
          if #sugs>=8 then break end
        end
      end
    end
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
      if not SFA.macroOrgSpellSet then
        if SFA.MacroOrg_BuildSpellSet then SFA:MacroOrg_BuildSpellSet() end
      end
      local spellSet = SFA.macroOrgSpellSet or {}
      local seen = {}
      for spell in pairs(spellSet) do
        if spell:find(spellPart,1,true) and not seen[spell] then
          seen[spell]=true
          local proper=spell:gsub("(%a)([%w']*)",function(f,r) return f:upper()..r end)
          sugs[#sugs+1]={insert=proper,label=proper,mode="spell"}
          if #sugs>=8 then break end
        end
      end
      table.sort(sugs,function(a,b)
        local aS=a.label:lower():find(spellPart,1,true)==1
        local bS=b.label:lower():find(spellPart,1,true)==1
        if aS~=bS then return aS end
        return a.label<b.label
      end)
    end
  end
  return sugs, mode, line, cursor
end

local function UI_AC_Apply(state)
  local sugs=state.sugs; local sel=state.selected; local edit=state.editBox
  if not sugs or sel<1 or sel>#sugs or not edit then return end
  local sug=sugs[sel]
  local text=edit:GetText() or ""
  -- Read the live cursor at apply time. Using the stale cursorSnap could target the
  -- wrong line if the editbox refreshed between suggestion and apply, which caused
  -- autocomplete on line 2 to incorrectly rewrite line 1.
  local cursor = edit:GetCursorPosition() or state.cursorSnap or 0
  if cursor > #text then cursor = #text end

  -- Split the full text at the cursor, then isolate just the current line so the
  -- gsub replacements below operate strictly within that line and never reach back
  -- into a previous line.
  local beforeAll = text:sub(1, cursor)
  local afterAll  = text:sub(cursor + 1)

  -- Current line = text from the last newline before the cursor up to the cursor.
  local lineStart = (beforeAll:match(".*()\n") or 1)
  if beforeAll:sub(lineStart, lineStart) == "\n" then lineStart = lineStart + 1 end
  local linePrefix = beforeAll:sub(1, lineStart - 1)   -- everything up to & including prior newline
  local before     = beforeAll:sub(lineStart)          -- the part of the current line before the cursor
  local after      = afterAll

  local newBefore
  if sug.mode=="slash" then
    newBefore=before:gsub("(/%S*)$",sug.insert)
  elseif sug.mode=="cond" then
    newBefore=before:gsub("([%[,]%s*)([%w:!%-]*)$",function(p) return p..sug.insert end)
  elseif sug.mode=="unit" then
    newBefore=before:gsub("@[%w]*$","@"..sug.insert)
  elseif sug.mode=="spell" then
    local semiPos=before:find(";[^;]*$")
    if semiPos then
      local prefix=before:match("^(.*;%s*)"); if prefix then newBefore=prefix..sug.insert.." " end
    end
    if not newBefore or newBefore==before then
      newBefore=before:gsub("([%]%s])([%w%s\'%-]*)$",function(sep) return sep..sug.insert.." " end)
    end
    if not newBefore or newBefore==before then
      newBefore=before:gsub("(%s)([%S]*)$",function(sp) return sp..sug.insert.." " end)
    end
    if not newBefore or newBefore==before then newBefore=before..sug.insert.." " end
  end
  if newBefore and newBefore~=before then
    local rebuilt = linePrefix .. newBefore
    edit:SetText(rebuilt..after); edit:SetCursorPosition(#rebuilt)
  end
end

local CreateFrame = CreateFrame

local function GetAddonVersion()
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(addonName, "Version") or "Unknown"
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(addonName, "Version") or "Unknown"
  end
  return "Unknown"
end

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
  local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", x, y - 16)
  local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)
  title:SetText(label .. ": " .. tostring(value))
  slider:SetMinMaxValues(minVal, maxVal)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)
  slider:SetWidth(240)
  slider:SetValue(value)

  -- Hide the built-in template Low/High labels (they show wrong values)
  if slider.Low then slider.Low:SetText("") end
  if slider.High then slider.High:SetText("") end

  -- Custom Low label (numeric minVal) below the left end of the slider
  local low = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
  low:SetText(tostring(minVal))

  -- Custom High label (numeric maxVal) below the right end of the slider
  local high = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  high:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
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
  -- Use no template so WoW's InputBoxTemplate:OnShow cannot reset our text
  local box = CreateFrame("EditBox", nil, parent)
  box:SetSize(width or 50, 22)
  box:SetPoint("TOPLEFT", x, y)
  box:SetAutoFocus(false)
  box:SetNumeric(false)
  box:SetMaxLetters(10)
  box:SetFontObject("GameFontHighlightSmall")
  box:SetTextInsets(4, 4, 0, 0)
  box:SetTextColor(1, 1, 1, 1)

  -- Manual border/background (visually matches InputBoxTemplate)
  local bg = box:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.6)

  local border = CreateFrame("Frame", nil, box, "BackdropTemplate")
  border:SetAllPoints()
  border:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  border:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

  box:SetText(tostring(value or "0"))
  box:SetCursorPosition(0)

  local function commit()
    local text = box:GetText() or ""
    local num = tonumber(text)
    if not num then num = 0 end
    box:SetText(tostring(math.floor(num + 0.5)))
    box:SetCursorPosition(0)
    onCommit(math.floor(num + 0.5))
  end

  box:SetScript("OnEnterPressed", function(self)
    commit()
    self:ClearFocus()
  end)
  box:SetScript("OnEditFocusLost", function()
    commit()
  end)
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
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


local macroEditBoxCounter = 0


-- Shared popup editor window (created once, reused for all macro editboxes)
local MacroPopup = nil

local function GetMacroPopup()
  if MacroPopup then return MacroPopup end

  local W, H = 480, 200
  local pop = CreateFrame("Frame", "SFAMacroPopup", UIParent, "BackdropTemplate")
  pop:SetSize(W, H)
  pop:SetFrameStrata("DIALOG")
  pop:SetMovable(true); pop:EnableMouse(true)
  pop:RegisterForDrag("LeftButton")
  pop:SetScript("OnDragStart", function(f) f:StartMoving() end)
  pop:SetScript("OnDragStop",  function(f) f:StopMovingOrSizing() end)
  pop:SetClampedToScreen(true)
  if pop.SetBackdrop then
    pop:SetBackdrop({
      bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
      tile=true, tileSize=32, edgeSize=32,
      insets={left=8,right=8,top=8,bottom=8},
    })
    pop:SetBackdropColor(0.04,0.04,0.07,0.97)
    pop:SetBackdropBorderColor(0.4,0.4,0.5,1)
  end
  pop:Hide()

  -- Title
  local titleStr = pop:CreateFontString(nil,"OVERLAY","GameFontNormal")
  titleStr:SetPoint("TOP",0,-10)
  pop.titleStr = titleStr

  -- Close button
  local xBtn = CreateFrame("Button",nil,pop,"UIPanelCloseButton")
  xBtn:SetPoint("TOPRIGHT",-2,-2)
  xBtn:SetScript("OnClick", function()
    if pop.onCommit then pop.onCommit(pop.edit:GetText()) end
    pop:Hide()
  end)

  -- Hint
  local hint = pop:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT",12,12)
  hint:SetText("|cff888888Enter = newline  |cff88ddffTab|r = autocomplete  |cffff8800Esc|r = close|r")

  -- Body
  local bodyBG = CreateFrame("Frame",nil,pop,"BackdropTemplate")
  bodyBG:SetPoint("TOPLEFT",10,-32); bodyBG:SetPoint("BOTTOMRIGHT",-10,32)
  if bodyBG.SetBackdrop then
    bodyBG:SetBackdrop({
      bgFile="Interface/Tooltips/UI-Tooltip-Background",
      edgeFile="Interface/Tooltips/UI-Tooltip-Border",
      tile=true,tileSize=8,edgeSize=8,
      insets={left=2,right=2,top=2,bottom=2},
    })
    bodyBG:SetBackdropColor(0.02,0.02,0.04,0.95)
    bodyBG:SetBackdropBorderColor(0.25,0.25,0.35,0.8)
  end

  local bodyScroll = CreateFrame("ScrollFrame",nil,bodyBG,"UIPanelScrollFrameTemplate")
  bodyScroll:SetPoint("TOPLEFT",4,-4); bodyScroll:SetPoint("BOTTOMRIGHT",-26,4)

  local edit = CreateFrame("EditBox",nil,bodyScroll)
  edit:SetSize(W-60,300)
  edit:SetMultiLine(true); edit:SetAutoFocus(false)
  edit:SetMaxLetters(255)
  edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
  edit:SetTextColor(1,1,1,1); edit:SetJustifyH("LEFT"); edit:SetJustifyV("TOP")
  edit:SetTextInsets(4,4,4,4); edit:SetText("")
  bodyScroll:SetScrollChild(edit)
  pop.edit = edit

  -- AC state
  local ac = {rows={},sugs={},selected=0,cursorSnap=0,editBox=edit,isHovered=false}

  local acFrame = CreateFrame("Frame",nil,pop,"BackdropTemplate")
  acFrame:SetSize(W-20,20)
  acFrame:SetPoint("BOTTOMLEFT",bodyBG,"TOPLEFT",0,2)
  acFrame:SetFrameStrata("FULLSCREEN_DIALOG"); acFrame:SetFrameLevel(200)
  if acFrame.SetBackdrop then
    acFrame:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
      edgeFile="Interface/Tooltips/UI-Tooltip-Border",
      tile=true,tileSize=8,edgeSize=6,insets={left=2,right=2,top=2,bottom=2}})
    acFrame:SetBackdropColor(0.04,0.04,0.10,0.97)
    acFrame:SetBackdropBorderColor(0.38,0.58,0.90,1)
  end
  acFrame:EnableMouse(true)
  acFrame:SetScript("OnEnter",function() ac.isHovered=true end)
  acFrame:SetScript("OnLeave",function() ac.isHovered=false end)
  acFrame:Hide(); ac.frame=acFrame

  local acHeader = acFrame:CreateFontString(nil,"OVERLAY")
  acHeader:SetFont("Fonts\\FRIZQT__.TTF",9,"")
  acHeader:SetPoint("TOPLEFT",6,-3); acHeader:SetTextColor(0.5,0.7,1,0.8)
  acHeader:SetText("Macro Autocomplete")

  for i=1,8 do
    local row=CreateFrame("Button",nil,acFrame)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT",0,-(i-1)*18-16); row:SetPoint("TOPRIGHT",0,-(i-1)*18-16)
    local hl=row:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.3,0.55,0.95,0.25)
    local selTex=row:CreateTexture(nil,"BACKGROUND"); selTex:SetAllPoints(); selTex:SetColorTexture(0.18,0.42,0.80,0.30); selTex:Hide()
    row.selTex=selTex
    local typeLbl=row:CreateFontString(nil,"OVERLAY"); typeLbl:SetFont("Fonts\\FRIZQT__.TTF",9,"")
    typeLbl:SetPoint("LEFT",6,0); typeLbl:SetWidth(52); typeLbl:SetJustifyH("LEFT"); row.typeLbl=typeLbl
    local textLbl=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    textLbl:SetPoint("LEFT",62,0); textLbl:SetPoint("RIGHT",-4,0); textLbl:SetJustifyH("LEFT"); row.textLbl=textLbl
    row:SetScript("OnEnter",function() ac.isHovered=true end)
    row:SetScript("OnLeave",function() ac.isHovered=false end)
    row:SetScript("OnClick",function()
      ac.selected=i; UI_AC_Apply(ac)
      edit:SetFocus()
      acFrame:Hide(); ac.selected=0; ac.sugs={}
    end)
    row:Hide(); ac.rows[i]=row
  end

  local function triggerAC()
    local sugs,mode=UI_AC_GetSuggestions(edit)
    if #sugs==0 or not mode then acFrame:Hide(); ac.selected=0; ac.sugs={}; return end
    ac.sugs=sugs; ac.cursorSnap=edit:GetCursorPosition()
    for i,row in ipairs(ac.rows) do
      local sug=sugs[i]
      if sug then
        row.typeLbl:SetText((UI_AC_COLORS[sug.mode] or "|cffaaaaaa")..(UI_AC_TYPE_NAMES[sug.mode] or "").."  |r")
        row.textLbl:SetText(sug.label); row.suggestion=sug; row:Show()
      else row:Hide() end
      row.selTex:Hide()
    end
    acFrame:SetHeight(16+#sugs*18+2)
    if ac.selected<1 or ac.selected>#sugs then ac.selected=1 end
    for i,row in ipairs(ac.rows) do if row.selTex then row.selTex:SetShown(i==ac.selected) end end
    acFrame:Show(); acFrame:Raise()
  end
  local function applyAC() UI_AC_Apply(ac); acFrame:Hide(); ac.selected=0; ac.sugs={} end
  local function navigateAC(dir)
    local n=#(ac.sugs or {}); if n==0 then return end
    ac.selected=ac.selected+dir
    if ac.selected<1 then ac.selected=n end
    if ac.selected>n then ac.selected=1 end
    for i,row in ipairs(ac.rows) do if row.selTex then row.selTex:SetShown(i==ac.selected) end end
  end

  edit:SetScript("OnTextChanged",function(self,user)
    if user then triggerAC() end
    if pop.onChange and user then pop.onChange(self:GetText()) end
  end)
  edit:SetScript("OnEnterPressed",function(self)
    if acFrame:IsShown() and ac.selected>0 then applyAC(); return end
    self:Insert("\n")
  end)
  edit:SetScript("OnKeyDown",function(self,key)
    self:SetPropagateKeyboardInput(false)
    if acFrame:IsShown() then
      if key=="TAB" then applyAC()
      elseif key=="UP" then navigateAC(-1)
      elseif key=="DOWN" then navigateAC(1)
      elseif key=="ESCAPE" then acFrame:Hide(); ac.selected=0; ac.sugs={} end
    elseif key=="ESCAPE" then
      if pop.onCommit then pop.onCommit(self:GetText()) end
      pop:Hide()
    end
  end)
  edit:SetScript("OnKeyUp", nil)
  edit:SetScript("OnEditFocusLost",function()
    C_Timer.After(0.15,function() if not ac.isHovered then acFrame:Hide(); ac.selected=0; ac.sugs={} end end)
  end)

  MacroPopup = pop
  return pop
end

local function CreateMacroEditBox(parent, label, x, y, width, text, onCommit, onChange)
  local title = CreateLabel(parent, label, x, y, "GameFontHighlightSmall")
  title.baseLabel = label  -- remembered so we can re-append "(SpecName)" on refresh

  -- Display frame in options panel (read-only, shows current macro text)
  local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  bg:SetSize(width, 56)
  bg:SetPoint("TOPLEFT", x, y - 18)
  if bg.SetBackdrop then
    bg:SetBackdrop({
      bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile=true, tileSize=8, edgeSize=8,
      insets={left=2,right=2,top=2,bottom=2},
    })
    bg:SetBackdropColor(0.02,0.02,0.02,0.9)
    bg:SetBackdropBorderColor(0.35,0.35,0.35,0.8)
  end

  -- Text display inside the bg. Shows the full macro including extra lines so the
  -- user can see at a glance that a multi-line macro is stored (not just line 1).
  local display = bg:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  display:SetPoint("TOPLEFT",6,-6); display:SetPoint("BOTTOMRIGHT",-58,6)
  display:SetJustifyH("LEFT"); display:SetJustifyV("TOP")
  display:SetWordWrap(true)
  display:SetMaxLines(3)

  -- Internal raw value keeps the real macro text (with newlines) so commits and
  -- re-opens never lose lines, even if the visible FontString clips long content.
  local rawText = text or ""
  display:SetText(rawText)

  -- Edit button
  local editBtn = CreateFrame("Button",nil,bg,"UIPanelButtonTemplate")
  editBtn:SetSize(50,22); editBtn:SetPoint("TOPRIGHT",-4,-4)
  editBtn:SetText("Edit")

  -- Click anywhere on bg also opens popup
  bg:EnableMouse(true)
  bg:SetScript("OnMouseDown", function()
    local pop = GetMacroPopup()
    pop.titleStr:SetText(label)
    pop.onCommit = function(t)
      rawText = t or ""
      if onCommit then onCommit(t) end
      display:SetText(rawText)
    end
    pop.onChange = function(t)
      rawText = t or ""
      if onChange then onChange(t) end
    end
    -- Load the full stored macro text (with all lines), not the possibly clipped display.
    pop.edit:SetText(rawText)
    pop.edit:SetCursorPosition(0)
    pop:SetPoint("CENTER")
    pop:Show()
    C_Timer.After(0.05, function() pop.edit:SetFocus() end)
  end)
  editBtn:SetScript("OnClick", function()
    bg:GetScript("OnMouseDown")(bg)
  end)

  -- Exposed interface for layout code
  local fakeEdit = {}
  fakeEdit.bg = bg
  fakeEdit.title = title
  fakeEdit.hint = nil
  fakeEdit.tip  = nil
  fakeEdit.GetText = function() return rawText end
  fakeEdit.SetText = function(_, t)
    rawText = t or ""
    text = t
    display:SetText(rawText)
  end

  return fakeEdit, title, bg, bg
end

local function StackBelow(widget, anchor, gap)
  if not widget or not anchor then return end
  widget:ClearAllPoints()
  widget:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 8))
end

local function CreateSectionHeader(parent, text, x, y)
  local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", x, y)
  title:SetText(text)
  return title
end

local function NormalizeSafeString(value)
  -- Returns a normal Lua string copy, or nil if Blizzard marks it as secret.
  -- IMPORTANT: never call tostring(), lower(), format(), concat, SetText, or compare
  -- on the raw value outside this pcall.
  local ok, text = pcall(function()
    if type(value) ~= "string" or value == "" then return nil end
    return "" .. value
  end)
  if ok and type(text) == "string" and text ~= "" then return text end
  return nil
end

local function NormalizeSafeSpellID(value)
  -- Secret numbers can also explode on tostring/string.format or as table keys.
  -- Convert through string.format inside pcall, then tonumber the copied string.
  local ok, text = pcall(function()
    if not value then return nil end
    local n = tonumber(value)
    if not n then return nil end
    return string.format("%d", n)
  end)
  if ok and text then return tonumber(text) end
  return nil
end

local function GetSpellNameSafe(spellID)
  local safeID = NormalizeSafeSpellID(spellID)
  if not safeID then return nil end
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, safeID)
    if ok then
      name = NormalizeSafeString(name)
      if name then return name end
    end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, safeID)
    if ok and info then
      local name = NormalizeSafeString(info.name)
      if name then return name end
    end
  end
  if GetSpellInfo then
    local ok, name = pcall(GetSpellInfo, safeID)
    if ok then
      name = NormalizeSafeString(name)
      if name then return name end
    end
  end
  return nil
end


local function TrimText(text)
  text = tostring(text or "")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local spellAutocompleteCache = nil
local spellAutocompleteExact = nil
local spellAutocompleteSeen = nil

local function AddSpellAutocompleteEntry(spellID, spellName)
  local id = NormalizeSafeSpellID(spellID)
  if not id then return end

  -- Use a safe copied name only. In RBG/arena preparation, both aura names and
  -- even spell API names may be secret strings. If the name is secret, skip the
  -- name-based autocomplete entry instead of creating a "Spell <id>" fallback,
  -- because even converting secret values for display can taint.
  local name = GetSpellNameSafe(id) or NormalizeSafeString(spellName)
  if not name then return end

  local okName, lower = pcall(function()
    return string.lower(name)
  end)
  if not okName or not lower or lower == "" then return end

  if SFA and SFA.db then
    SFA.db.spellNameCache = SFA.db.spellNameCache or {}
    SFA.db.spellNameCache[id] = name
  end

  spellAutocompleteCache = spellAutocompleteCache or {}
  spellAutocompleteExact = spellAutocompleteExact or {}
  spellAutocompleteSeen = spellAutocompleteSeen or {}

  if spellAutocompleteSeen[id] then return end
  spellAutocompleteSeen[id] = true

  if not spellAutocompleteExact[lower] then
    spellAutocompleteExact[lower] = id
  end

  spellAutocompleteCache[#spellAutocompleteCache + 1] = {
    id = id,
    name = name,
    search = lower,
  }
end

local function BuildSpellAutocompleteCache()
  if spellAutocompleteCache then return end
  spellAutocompleteCache = {}
  spellAutocompleteExact = {}
  spellAutocompleteSeen = {}

  local seen = {}
  local function add(id, name)
    id = NormalizeSafeSpellID(id)
    if not id or seen[id] then return end
    seen[id] = true
    AddSpellAutocompleteEntry(id, name or GetSpellNameSafe(id))
  end

  -- Names learned safely outside secure PvP contexts remain searchable later in RBG/arena prep.
  if SFA and SFA.db and type(SFA.db.spellNameCache) == "table" then
    for cachedID, cachedName in pairs(SFA.db.spellNameCache) do
      add(cachedID, cachedName)
    end
  end

  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
    local okLines, lineCount = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if okLines and tonumber(lineCount) then
      for lineIndex = 1, lineCount do
        local okInfo, lineInfo = pcall(C_SpellBook.GetSpellBookSkillLineInfo, lineIndex)
        local offset = lineInfo and (lineInfo.itemIndexOffset or lineInfo.offset)
        local numSlots = lineInfo and (lineInfo.numSpellBookItems or lineInfo.numSlots)
        if okInfo and tonumber(offset) and tonumber(numSlots) then
          for slot = offset + 1, offset + numSlots do
            local name, spellID
            if C_SpellBook.GetSpellBookItemName then
              local okName, n = pcall(C_SpellBook.GetSpellBookItemName, slot, Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0)
              if okName then name = n end
            end
            if C_SpellBook.GetSpellBookItemInfo then
              local okItem, itemInfo = pcall(C_SpellBook.GetSpellBookItemInfo, slot, Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0)
              if okItem and itemInfo then spellID = itemInfo.spellID or itemInfo.actionID end
            end
            if not spellID and name and C_Spell and C_Spell.GetSpellInfo then
              local okSpell, info = pcall(C_Spell.GetSpellInfo, name)
              if okSpell and info then spellID = info.spellID end
            end
            add(spellID, name)
          end
        end
      end
    end
  end

  if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
    local okTabs, tabs = pcall(GetNumSpellTabs)
    if okTabs and tonumber(tabs) then
      for tab = 1, tabs do
        local okTab, _, _, offset, numSlots = pcall(GetSpellTabInfo, tab)
        if okTab and tonumber(offset) and tonumber(numSlots) then
          for slot = offset + 1, offset + numSlots do
            local okName, name = pcall(GetSpellBookItemName, slot, BOOKTYPE_SPELL or "spell")
            if okName and name then
              local spellID
              if GetSpellInfo then
                local okSpell, _, _, _, _, _, id = pcall(GetSpellInfo, name)
                if okSpell then spellID = id end
              end
              add(spellID, name)
            end
          end
        end
      end
    end
  end

  -- Keep insertion order. Avoid table.sort string comparisons here because
  -- instanced PvP can mark some values as secret during preparation.
end


local function AddActivePlayerAurasToAutocompleteCache()
  BuildSpellAutocompleteCache()
  if not UnitExists or not UnitExists("player") then return end
  if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return end

  -- Rated BG / arena preparation can expose secret aura *names*.
  -- We still scan active player auras for autocomplete, but we only read spell IDs
  -- and resolve the display name later through spell APIs. Never use aura.name here.

  local function scan(filter)
    for i = 1, 80 do
      local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
      if not ok or not aura then break end
      local okID, rawSpellID = pcall(function() return aura.spellId or aura.spellID end)
      local spellID = okID and NormalizeSafeSpellID(rawSpellID) or nil
      if spellID then
        -- Use only a safe copied numeric ID from aura data; resolve/display name only
        -- if the spell API returns a normal non-secret string.
        AddSpellAutocompleteEntry(spellID, GetSpellNameSafe(spellID))
      end
    end
  end

  scan("HELPFUL")
  scan("HARMFUL")
end

local function ResolveSpellInput(text)
  text = TrimText(text)
  if text == "" then return nil end

  local numericID = NormalizeSafeSpellID(text)
  if numericID then
    return numericID, GetSpellNameSafe(numericID)
  end

  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, text)
    if ok and info and info.spellID then
      local safeID = NormalizeSafeSpellID(info.spellID)
      if safeID then return safeID, NormalizeSafeString(info.name) or GetSpellNameSafe(safeID) end
    end
  end

  if GetSpellInfo then
    local ok, name, _, _, _, _, spellID = pcall(GetSpellInfo, text)
    if ok and spellID then
      local safeID = NormalizeSafeSpellID(spellID)
      if safeID then return safeID, NormalizeSafeString(name) or GetSpellNameSafe(safeID) end
    end
  end

  AddActivePlayerAurasToAutocompleteCache()
  local exactID = spellAutocompleteExact and spellAutocompleteExact[string.lower(text)]
  if exactID then
    return exactID, GetSpellNameSafe(exactID)
  end

  return nil
end

local function CreateSpellAutocomplete(parent, input)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -3)
  box:SetSize(300, 104)
  box:SetFrameStrata("DIALOG")
  box:SetFrameLevel((input:GetFrameLevel() or 1) + 10)
  box:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  box:SetBackdropColor(0.04, 0.04, 0.04, 0.95)
  box:Hide()

  box.rows = {}
  for i = 1, 5 do
    local row = CreateFrame("Button", nil, box)
    row:SetSize(286, 18)
    row:SetPoint("TOPLEFT", 7, -7 - ((i - 1) * 19))
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self)
      if self.spellID then
        input:SetText(tostring(self.spellID))
        input.spellNameHint:SetText(self.spellName or "")
        box:Hide()
        input:SetFocus()
      end
    end)
    row:Hide()
    box.rows[i] = row
  end

  function box:Refresh(text)
    text = TrimText(text)
    if text == "" or tonumber(text) or #text < 2 then
      self:Hide()
      return
    end

    AddActivePlayerAurasToAutocompleteCache()
    local query = string.lower(text)
    local results = {}
    local used = {}

    for _, entry in ipairs(spellAutocompleteCache or {}) do
      if entry.search == query and not used[entry.id] then
        results[#results + 1] = entry
        used[entry.id] = true
      end
    end
    for _, entry in ipairs(spellAutocompleteCache or {}) do
      if #results >= 5 then break end
      if not used[entry.id] and entry.search:find(query, 1, true) then
        results[#results + 1] = entry
        used[entry.id] = true
      end
    end

    for i, row in ipairs(self.rows) do
      local entry = results[i]
      if entry then
        row.spellID = entry.id
        row.spellName = entry.name
        row.text:SetText(string.format("%s  |cff888888(%d)|r", entry.name, entry.id))
        row:Show()
      else
        row.spellID = nil
        row.spellName = nil
        row:Hide()
      end
    end

    self:SetShown(#results > 0)
  end

  return box
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

-- These three dropdowns used to be built on the legacy UIDropDownMenuTemplate
-- / UIDropDownMenu_Initialize API. That API is a well-known, long-standing
-- taint source: UIDropDownMenu_Initialize() runs the init callback
-- immediately (not just when opened) and both it and UIDropDownMenu_AddButton
-- read/write shared Blizzard globals (UIDROPDOWNMENU_MENU_LEVEL, etc.) that
-- are also touched by Blizzard's own dropdown menus everywhere else in the
-- game UI. taint.log confirmed this was tainting execution the moment the
-- options panel was built (i.e. right at login, before combat), which is
-- exactly the kind of taint that accumulates into "*** ForceTaint_Strong ***"
-- and then blocks secret aura reads later. Rebuilt on Blizzard's modern,
-- non-global-state "DropdownButton" / WowStyle1DropdownTemplate menu API,
-- which doesn't touch that shared global state.
local function SFA_CreateSimpleDropdown(parent, x, y, width, options, currentValue, onSet)
  local drop = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  drop:SetPoint("TOPLEFT", x - 14, y - 18)
  drop:SetWidth(width)

  drop:SetupMenu(function(owner, rootDescription)
    for _, option in ipairs(options) do
      rootDescription:CreateButton(option.text, function()
        onSet(option.value)
        drop:OverrideText(option.text)
      end)
    end
  end)

  local initialLabel = currentValue
  for _, option in ipairs(options) do
    if option.value == currentValue then
      initialLabel = option.text
      break
    end
  end
  drop:OverrideText(initialLabel)
  return drop
end

local function CreateResourceVoiceStyleDropDown(parent, x, y, currentMode, onSet)
  local title = CreateLabel(parent, "Voice style", x, y, "GameFontHighlight")
  local drop = SFA_CreateSimpleDropdown(parent, x, y, 190, {
    { value = "male", text = "Male" },
    { value = "female", text = "Female" },
  }, currentMode or "male", onSet)
  return drop, title
end

function SFA:RefreshOptionsPanel()
  if not self.options then return end
  local db = self.db
if self.options.otherBuilderSpenderIndicator then self.options.otherBuilderSpenderIndicator:SetChecked(db.other and db.other.showBuilderSpenderIndicator ~= false) end
  if self.options.generalTitle then
    self.options.generalTitle:SetText("Simple Frame Assistant")
  end
  if self.options.generalVersion then
    self.options.generalVersion:SetText("Version: " .. GetAddonVersion())
  end
  if self.options.generalSub then
    self.options.generalSub:SetText("Use /sfa as a shortcut to this page. Move unlocked blocks with Shift + drag.")
  end

  if self.options.minimapEnabled then self.options.minimapEnabled:SetChecked(db.minimap and db.minimap.enabled ~= false) end
  if self.options.redesignMacroWindow then self.options.redesignMacroWindow:SetChecked(db.other and db.other.redesignMacroWindow) end
  if self.options.otherQuestIndicator then self.options.otherQuestIndicator:SetChecked(db.other and db.other.showQuestIndicator) end
  if self.options.otherTargetXMark then self.options.otherTargetXMark:SetChecked(db.other and db.other.showTargetXMark) end
  if self.options.otherCharacterGCD then self.options.otherCharacterGCD:SetChecked(db.other and db.other.showCharacterGCD ~= false) end
  if self.options.debugEnabled then self.options.debugEnabled:SetChecked(SFA.auraDebug) end
  if self.RefreshDebugLogDisplay then self:RefreshDebugLogDisplay() end

  -- Refresh per-spec click macro displays + spec name labels.
  local specName = self:GetCurrentSpecName()
  if self.options.friendlySpecLabel then
    self.options.friendlySpecLabel:SetText("|cff7cc6ffClick macros for spec: " .. specName .. "|r")
  end
  if self.options.enemySpecLabel then
    self.options.enemySpecLabel:SetText("|cff7cc6ffClick macros for spec: " .. specName .. "|r")
  end
  local function syncMacroDisplays(section, group)
    if not section then return end
    if section.leftClick   and section.leftClick.SetText   then section.leftClick:SetText(self:GetClickMacro(group, "LeftButton")) end
    if section.rightClick  and section.rightClick.SetText  then section.rightClick:SetText(self:GetClickMacro(group, "RightButton")) end
    if section.middleClick and section.middleClick.SetText then section.middleClick:SetText(self:GetClickMacro(group, "MiddleButton")) end
    -- Append the current spec name in parentheses to each macro label.
    local suffix = (specName and specName ~= "No specialization") and (" (" .. specName .. ")") or ""
    local function setLabel(editObj)
      if editObj and editObj.title and editObj.title.baseLabel then
        editObj.title:SetText(editObj.title.baseLabel .. suffix)
      end
    end
    setLabel(section.leftClick)
    setLabel(section.rightClick)
    setLabel(section.middleClick)
    if section.disableBox then section.disableBox:SetChecked(not self:GetCharEnabled(group)) end
  end
  syncMacroDisplays(self.options.friendlySection, "friendly")
  syncMacroDisplays(self.options.enemySection, "enemy")
end

-- 0.25.0 redesign: this tab used to configure this addon's own rendered
-- frames (enable/debuffs/width/height/scale/spacing) -- all gone now that
-- the addon only applies click-cast macros to Blizzard's native frames.
-- All that's left is the three per-spec macro boxes.
function SFA:BuildGroupSection(parent, group, left, top)
  local title = CreateSectionHeader(parent, group == "friendly" and "Friendly Frames" or "Enemy Frames", left, top)

  -- 0.25.9: lets the user see Blizzard's native right-click menu (Set
  -- Focus, Target Marker Icon, PvP, etc) again on demand, without having
  -- to disable the whole addon -- user-requested (2026-09-01) after
  -- needing to disable the addon entirely just to see what the native
  -- menus actually look like. Wired through the existing (previously
  -- orphaned since the 0.25.0 redesign) GetCharEnabled/SetCharEnabled
  -- per-character flags.
  -- 0.25.12 layout fix: the checkbox's own label used to carry the full
  -- "requires Reload UI" explanation, and the Reload button sat far to the
  -- right (left + 560) -- both got clipped/cut off on a normal (non-
  -- maximized) options window, same class of bug as the arena/friendly
  -- debug buttons before them (see the 0.24.38 note on those). Following
  -- that same fix: short checkbox label, explanation on its own wrapped
  -- line below, button on its own row at the safe left-aligned x=left --
  -- nothing placed far enough right to risk falling off the edge again.
  local disableBox = CreateCheckbox(parent, "Disable click-cast for this group",
    left, top - 20, not self:GetCharEnabled(group), function(checked)
      self:SetCharEnabled(group, not checked)
      self:ApplyAllNativeClickBindings()
    end)

  local disableHint = CreateLabel(parent,
    "Restores Blizzard's native clicks/menu -- only takes full effect on a frame not yet touched this session, so click Reload UI after checking this.",
    left, top - 44, "GameFontHighlightSmall")
  disableHint:SetWidth(600)
  disableHint:SetWordWrap(true)
  disableHint:SetJustifyH("LEFT")

  -- 0.25.11: confirmed live (2026-09-01) that Blizzard only restores its
  -- own native right-click menu on a frame this addon has NEVER touched
  -- yet this session -- toggling the checkbox alone can't undo an already-
  -- applied override, only a fresh reload can. This button saves having to
  -- type /reload manually every time.
  local disableReloadBtn = CreateButton(parent, "Reload UI now", left, top - 78, 130, 20, function()
    ReloadUI()
  end)

  local y = top - 112

  local leftClick = CreateMacroEditBox(parent, "Left click macro", left, y, 360, self:GetClickMacro(group,"LeftButton"), function(text)
    self:SetClickMacro(group,"LeftButton",text)
    self:ApplyAllNativeClickBindings()
  end, function(text)
    self:SetClickMacro(group,"LeftButton",text)
  end)

  local rightClick = CreateMacroEditBox(parent, "Right click macro", left, y, 360, self:GetClickMacro(group,"RightButton"), function(text)
    self:SetClickMacro(group,"RightButton",text)
    self:ApplyAllNativeClickBindings()
  end, function(text)
    self:SetClickMacro(group,"RightButton",text)
  end)

  local middleClick = CreateMacroEditBox(parent, "Middle click macro", left, y, 360, self:GetClickMacro(group,"MiddleButton"), function(text)
    self:SetClickMacro(group,"MiddleButton",text)
    self:ApplyAllNativeClickBindings()
  end, function(text)
    self:SetClickMacro(group,"MiddleButton",text)
  end)

  -- full stack layout for the macro area
  if leftClick.title then
    leftClick.title:ClearAllPoints()
    leftClick.title:SetPoint("TOPLEFT", parent, "TOPLEFT", left, y - 6)
  end
  if leftClick.bg then
    leftClick.bg:ClearAllPoints()
    leftClick.bg:SetPoint("TOPLEFT", leftClick.title, "BOTTOMLEFT", 0, -6)
  end
  if leftClick.hint then
    leftClick.hint:ClearAllPoints()
    leftClick.hint:SetPoint("TOPLEFT", leftClick.bg or leftClick, "BOTTOMLEFT", 0, -8)
  end

  if rightClick.title then
    rightClick.title:ClearAllPoints()
    rightClick.title:SetPoint("TOPLEFT", leftClick.hint or leftClick.bg or leftClick, "BOTTOMLEFT", 0, -16)
  end
  if rightClick.bg then
    rightClick.bg:ClearAllPoints()
    rightClick.bg:SetPoint("TOPLEFT", rightClick.title, "BOTTOMLEFT", 0, -6)
  end
  if rightClick.hint then
    rightClick.hint:ClearAllPoints()
    rightClick.hint:SetPoint("TOPLEFT", rightClick.bg or rightClick, "BOTTOMLEFT", 0, -8)
  end

  if middleClick.title then
    middleClick.title:ClearAllPoints()
    middleClick.title:SetPoint("TOPLEFT", rightClick.hint or rightClick.bg or rightClick, "BOTTOMLEFT", 0, -16)
  end
  if middleClick.bg then
    middleClick.bg:ClearAllPoints()
    middleClick.bg:SetPoint("TOPLEFT", middleClick.title, "BOTTOMLEFT", 0, -6)
  end
  if middleClick.hint then
    middleClick.hint:ClearAllPoints()
    middleClick.hint:SetPoint("TOPLEFT", middleClick.bg or middleClick, "BOTTOMLEFT", 0, -8)
  end

  return {
    title = title,
    disableBox = disableBox,
    leftClick = leftClick,
    rightClick = rightClick,
    middleClick = middleClick,
    leftClickBG = leftClick.bg or leftClick.scrollFrame or leftClick,
    rightClickBG = rightClick.bg or rightClick.scrollFrame or rightClick,
    middleClickBG = middleClick.bg or middleClick.scrollFrame or middleClick,
    middleClickTip = middleClick.hint,
  }
end

function SFA:RefreshProcReadyUI()
  if not self.options or not self.options.procReadyRows then return end
  local cfg = self:GetCharProcReadyConfig()
  local ids = {}
  for spellID, enabled in pairs((cfg and cfg.spells) or {}) do
    if enabled then ids[#ids + 1] = tonumber(spellID) end
  end
  table.sort(ids)

  for i, row in ipairs(self.options.procReadyRows) do
    local spellID = ids[i]
    if spellID then
      local spellName = GetSpellNameSafe(spellID)
      if spellName and spellName ~= "" then
        row.label:SetText(string.format("%s (%d)", spellName, spellID))
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

  if self.options.procReadyEmpty then
    self.options.procReadyEmpty:SetShown(#ids == 0)
  end
end

function SFA:CreateOptionsPanel()
  local root = CreateCanvasFrame(addonName .. "OptionsRoot")
  root.name = "Simple Frame Assistant"
  local rootContent = root.content

  root.title = rootContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  root.title:SetPoint("TOPLEFT", 18, -10)

  root.version = rootContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  root.version:SetPoint("TOPLEFT", root.title, "BOTTOMLEFT", 0, -4)
  root.version:SetTextColor(0.7, 0.7, 0.7)
  root.version:SetText("Version: " .. GetAddonVersion())

  root.sub = rootContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  root.sub:SetPoint("TOPLEFT", root.version, "BOTTOMLEFT", 0, -6)
  root.sub:SetJustifyH("LEFT")
  root.sub:SetText("Use /sfa as a shortcut to this page.")

  local generalHeader = CreateSectionHeader(rootContent, "General", 18, -68)
  local minimapEnabled = CreateCheckbox(rootContent, "Minimap button", 24, -104, self.db.minimap and self.db.minimap.enabled ~= false, function(val)
    self.db.minimap = self.db.minimap or {}
    self.db.minimap.enabled = val
    if self.UpdateMinimapButtonPosition then self:UpdateMinimapButtonPosition() end
  end)

  -- v0.22.00: Redesign Macro Window
  local redesignMacroWindow = CreateCheckbox(rootContent, "Redesign Macro Window (tabs: Global | Class | Character)", 24, -136,
    self.db.other and self.db.other.redesignMacroWindow, function(val)
    self.db.other = self.db.other or {}
    self.db.other.redesignMacroWindow = val
    if SFA and SFA.MacroFrame_UpdateSlashHook then
      SFA:MacroFrame_UpdateSlashHook()
    end
  end)

  local macroHint = rootContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  macroHint:SetPoint("TOPLEFT", 42, -160)
  macroHint:SetText("Use |cff88ddff/macro|r or |cff88ddff/sfamacro|r in chat to open the custom macro window.")

  -- 0.25.0 redesign: this addon no longer renders its own unit frames --
  -- it only applies the Left/Right/Middle click macros below (Friendly
  -- Frame / Enemy Frame tabs) to whichever Blizzard-native frames are
  -- already on screen (player/party/raid/target/focus for friendly, arena
  -- for enemy), positioned wherever Blizzard's own Edit Mode puts them.
  -- 0.25.24: user screenshot showed this text getting clipped hard on the
  -- right edge (mid-word, e.g. "...Enemy Frame" / "Blizzard's own frames"
  -- split across lines with words missing) -- SetWidth(760) does define a
  -- wrap width, but the REAL visible area inside the Settings panel this
  -- frame is embedded in is narrower than the 840px-wide scroll content
  -- frame itself, so a 760-wide wrap wraps later than the visible edge and
  -- gets clipped instead. This exact class of bug hit the checkbox/button
  -- row too (0.25.12) and was fixed there by using a narrower, tested-safe
  -- width (600) instead of guessing wider -- same fix applied here.
  local generalInfo = rootContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  generalInfo:SetPoint("TOPLEFT", 24, -188)
  generalInfo:SetWidth(600)
  generalInfo:SetJustifyH("LEFT")
  generalInfo:SetText("Use /sfa to open this page quickly. This addon applies your Left/Right/Middle click macros (Friendly Frame / Enemy Frame tabs) directly to Blizzard's own frames -- it no longer renders its own. Macro text can use [@unit] and will be expanded automatically. Note: overriding Right-click replaces Blizzard's normal right-click menu (Set Focus, Target Marker, PvP, etc) on that frame.")

  -- 0.25.21: user-requested (2026-09-01) -- the Ctrl+Alt+Right-click note
  -- kept getting missed sitting inline inside the paragraph above, so it's
  -- now its own line: bigger, bold, and red, anchored below generalInfo
  -- (not a fixed pixel offset) so it always lands right under however many
  -- lines that paragraph wraps to. 0.25.24: narrowed to 600 for the same
  -- clipping reason as generalInfo above.
  local ctrlAltNote = rootContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ctrlAltNote:SetPoint("TOPLEFT", generalInfo, "BOTTOMLEFT", 0, -12)
  ctrlAltNote:SetWidth(600)
  ctrlAltNote:SetJustifyH("LEFT")
  ctrlAltNote:SetTextColor(1, 0.15, 0.15)
  ctrlAltNote:SetText("To open the native Frame Settings menu, hold Ctrl+Alt and Right-click on your portrait, Target, Focus, or Party frame. This replaces plain Right-click, now used for Click & Cast.")

  rootContent:SetHeight(420)

  local otherPanel = CreateCanvasFrame(addonName .. "OptionsOther")
  otherPanel.OnRefresh = function() C_Timer.After(0, function() if SFA and SFA.RefreshOptionsPanel then SFA:RefreshOptionsPanel() end end) end
  local otherContent = otherPanel.content
  local otherTitle = otherContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  otherTitle:SetPoint("TOPLEFT", 18, -10)
  otherTitle:SetText("Simple Frame Assistant")
  local otherSub = otherContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  otherSub:SetPoint("TOPLEFT", otherTitle, "BOTTOMLEFT", 0, -6)
  otherSub:SetText("Smart Assist options.")
  local otherHeader = CreateSectionHeader(otherContent, "Smart Assist", 18, -68)
  local otherTargetXMark = CreateCheckbox(otherContent, "Show X mark on enemy target frame", 24, -104, self.db.other and self.db.other.showTargetXMark, function(val)
    self.db.other.showTargetXMark = val
    self:RefreshEnemyNameplateOverlays()
  end)
  local otherCharacterGCD = CreateCheckbox(otherContent, "Show Estimated / One-Button GCD under Character window", 24, -140, self.db.other.showCharacterGCD ~= false, function(val)
    self.db.other.showCharacterGCD = val
    if SFA_UpdateCharacterGCD then
      SFA_UpdateCharacterGCD()
    elseif CharacterFrame and CharacterFrame:IsShown() and SFA_GCDText then
      if val then
        SFA_GCDText:Show()
      else
        SFA_GCDText:SetText("")
        SFA_GCDText:Hide()
      end
    end
  end)

  local otherQuestIndicator = CreateCheckbox(otherContent, "Show quest objective ! on nameplates", 24, -176, self.db.other and self.db.other.showQuestIndicator, function(val)
    self.db.other.showQuestIndicator = val
    self:RefreshQuestIndicators()
  end)
  local otherBuilderSpenderIndicator = CreateCheckbox(otherContent, "Show full builder-spender resource circle", 24, -212, self.db.other.showBuilderSpenderIndicator ~= false, function(val)
    self.db.other.showBuilderSpenderIndicator = val
    self:RefreshEnemyNameplateOverlays()
  end)

  self.db.other.resourceVoiceAlerts = self.db.other.resourceVoiceAlerts or { enabled = false, cooldown = 1.0, volume = 5 }
  if self.db.other.resourceVoiceAlerts.cooldown == nil then self.db.other.resourceVoiceAlerts.cooldown = 1.0 end
  if self.db.other.resourceVoiceAlerts.volume == nil then self.db.other.resourceVoiceAlerts.volume = 5 end
  if self.db.other.resourceVoiceAlerts.voiceStyle ~= "female" then self.db.other.resourceVoiceAlerts.voiceStyle = "male" end

  local otherResourceVoice = CreateCheckbox(otherContent, "Voice alert when builder-spender resource is full", 24, -248, self:GetCharResourceVoiceEnabled(), function(val)
    self:SetCharResourceVoiceEnabled(val)
    if val and SFA.PreviewFullResourceVoice then
      SFA:PreviewFullResourceVoice()
    end
  end)
  local resourceVoiceStyleDropDown = CreateResourceVoiceStyleDropDown(otherContent, 54, -284, self.db.other.resourceVoiceAlerts.voiceStyle or "male", function(val)
    self.db.other.resourceVoiceAlerts.voiceStyle = (val == "female") and "female" or "male"
    if SFA.PreviewFullResourceVoice then
      SFA:PreviewFullResourceVoice()
    end
  end)

  local resourceVoiceVolume = CreateSlider(otherContent, "Voice alert volume", 54, -348, 0, 10, 1, self.db.other.resourceVoiceAlerts.volume or 5, function(val)
    self.db.other.resourceVoiceAlerts.volume = val
    if SFA.PreviewFullResourceVoice then
      SFA:PreviewFullResourceVoice()
    end
  end)

  local resourceVoiceCooldown = CreateSlider(otherContent, "Voice alert cooldown", 54, -404, 0, 5, 0.5, self.db.other.resourceVoiceAlerts.cooldown or 1.0, function(val)
    self.db.other.resourceVoiceAlerts.cooldown = val
  end)


  self.db.other.procReadyAlerts = self.db.other.procReadyAlerts or { enabled = false, spells = {} }
  self.db.other.procReadyAlerts.spells = self.db.other.procReadyAlerts.spells or {}

  local procReadyHeader = CreateSectionHeader(otherContent, "Proc Ready Alerts", 18, -500)
  local procReadyHelp = otherContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  procReadyHelp:SetPoint("TOPLEFT", 24, -530)
  procReadyHelp:SetWidth(780)
  procReadyHelp:SetJustifyH("LEFT")
  procReadyHelp:SetText("Add spell IDs or spell names to announce PROC READY once when they become usable and off cooldown in combat. Uses the existing voice volume and voice alert cooldown.")

  local procReadyEnabled = CreateCheckbox(otherContent, "Enable proc ready voice alerts", 24, -570, self:GetCharProcReadyConfig() and self:GetCharProcReadyConfig().enabled == true or false, function(val)
    local cfg = self:GetCharProcReadyConfig()
    if cfg then cfg.enabled = val end
    if not val and SFA.ResetProcReadyStates then SFA:ResetProcReadyStates() end
  end)

  local procReadyInput = CreateFrame("EditBox", nil, otherContent, "InputBoxTemplate")
  procReadyInput:SetSize(220, 24)
  procReadyInput:SetPoint("TOPLEFT", 24, -610)
  procReadyInput:SetAutoFocus(false)
  procReadyInput:SetNumeric(false)

  local procReadyHint = otherContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  procReadyHint:SetPoint("LEFT", procReadyInput, "RIGHT", 10, 0)
  procReadyHint:SetWidth(260)
  procReadyHint:SetJustifyH("LEFT")
  procReadyHint:SetText("Spell ID or name")
  procReadyInput.spellNameHint = procReadyHint

  local procReadyAutocomplete = CreateSpellAutocomplete(otherContent, procReadyInput)

  local procReadyAdd = CreateButton(otherContent, "Add", 254, -608, 70, 24, function()
    local spellID, spellName = ResolveSpellInput(procReadyInput:GetText())
    if spellID then
      SFA:AddProcReadySpell(spellID)
      if spellName then AddSpellAutocompleteEntry(spellID, spellName) end
      procReadyInput:SetText("")
      procReadyHint:SetText("Spell ID or name")
      procReadyAutocomplete:Hide()
      procReadyInput:ClearFocus()
    else
      procReadyHint:SetText("No spell found")
    end
  end)

  procReadyInput:SetScript("OnTextChanged", function(self)
    local spellID, spellName = ResolveSpellInput(self:GetText())
    if spellID then
      procReadyHint:SetText(spellName and string.format("%s (%d)", spellName, spellID) or tostring(spellID))
    else
      procReadyHint:SetText("Spell ID or name")
    end
    procReadyAutocomplete:Refresh(self:GetText())
  end)
  procReadyInput:SetScript("OnEscapePressed", function(self)
    procReadyAutocomplete:Hide()
    self:ClearFocus()
  end)
  procReadyInput:SetScript("OnEnterPressed", function(self)
    procReadyAdd:Click()
  end)

  local procReadyEmpty = otherContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  procReadyEmpty:SetPoint("TOPLEFT", 24, -646)
  procReadyEmpty:SetText("No proc ready spell IDs yet.")

  local procReadyRows = {}
  for i = 1, 10 do
    local row = CreateFrame("Frame", nil, otherContent)
    row:SetSize(760, 22)
    row:SetPoint("TOPLEFT", 24, -646 - ((i - 1) * 22))
    row.label = CreateLabel(row, "", 0, 0, "GameFontHighlightSmall")
    row.remove = CreateButton(row, "Remove", 310, 2, 80, 20, function(btn)
      if btn.spellID then
        SFA:RemoveProcReadySpell(btn.spellID)
      end
    end)
    row:Hide()
    procReadyRows[#procReadyRows + 1] = row
  end

  otherContent:SetHeight(920)

-- ---------------------------------------------------------------------
-- Debug panel: enable/disable chat debug prints, reload the UI, and view
-- or clear the persisted diagnostic log (SFA_DebugLog -- see Core.lua).
-- That log survives to disk on /reload or logout under the account's
-- SavedVariables folder, but this panel lets it be read/cleared in-game
-- too, without needing to dig through files.
-- ---------------------------------------------------------------------
local debugPanel = CreateCanvasFrame(addonName .. "OptionsDebug")
debugPanel.OnRefresh = function() C_Timer.After(0, function() if SFA and SFA.RefreshOptionsPanel then SFA:RefreshOptionsPanel() end end) end
-- Belt-and-suspenders: also refresh directly on this specific panel's
-- OnShow, in case the Settings canvas system's OnRefresh callback doesn't
-- always fire on every tab switch/reopen.
debugPanel:HookScript("OnShow", function()
  C_Timer.After(0, function() if SFA and SFA.RefreshDebugLogDisplay then SFA:RefreshDebugLogDisplay() end end)
end)
local debugContent = debugPanel.content
local debugTitle = debugContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
debugTitle:SetPoint("TOPLEFT", 18, -10)
debugTitle:SetText("Simple Frame Assistant")
local debugSub = debugContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
debugSub:SetPoint("TOPLEFT", debugTitle, "BOTTOMLEFT", 0, -6)
debugSub:SetText("Diagnostic tools. The log is also saved to disk (SavedVariables) and survives /reload or logout.")

local debugHeader = CreateSectionHeader(debugContent, "Debug", 18, -68)

local debugEnabled = CreateCheckbox(debugContent, "Enable aura debug (prints details to chat, same as /sfaauradebug)", 24, -104, SFA.auraDebug, function(val)
  SFA:SetAuraDebug(val)
end)

local debugReloadBtn = CreateButton(debugContent, "Reload UI", 24, -140, 120, 22, function()
  ReloadUI()
end)
local debugShowBtn = CreateButton(debugContent, "Show log lines", 154, -140, 140, 22, function()
  if SFA.RefreshDebugLogDisplay then SFA:RefreshDebugLogDisplay() end
end)
local debugClearBtn = CreateButton(debugContent, "Clear log", 304, -140, 100, 22, function()
  SFA_DebugLog = {}
  if SFA.RefreshDebugLogDisplay then SFA:RefreshDebugLogDisplay() end
end)

-- Buttons for the two arena-frame diagnostics (SFA:ScanArenaFrames /
-- SFA:DumpArenaFrameAttributes, both in Core.lua). Added as clickable
-- buttons -- not just /run-callable -- because the typed slash-command
-- path proved unreliable in testing (WoW's own chat autocomplete dropdown
-- can swallow Enter for /sfascanarena; and relying on the player to type
-- /run commands in the right order after every /reload led to several
-- rounds of "nothing happened" that turned out to be a stale-code or
-- debug-toggle mixup rather than an addon bug). A button removes all of
-- that -- it always calls the currently-loaded function directly and
-- shows a chat confirmation immediately.
-- 0.24.38: these two used to sit on the same row as Reload/Show/Clear,
-- extending out past x=750 -- wide enough that on a normal (non-maximized)
-- options window the "Dump arena click attrs" button landed off the edge
-- of the visible panel with no way to scroll right to reach it (user
-- screenshot, 2026-08-31). Moved to their own row so every button stays
-- reachable regardless of window width.
local debugArenaScanBtn = CreateButton(debugContent, "Scan arena frames", 24, -172, 150, 22, function()
  if SFA.ScanArenaFrames then SFA:ScanArenaFrames() end
end)
local debugArenaAttrBtn = CreateButton(debugContent, "Dump arena click attrs", 184, -172, 180, 22, function()
  if SFA.DumpArenaFrameAttributes then SFA:DumpArenaFrameAttributes() end
end)

-- 0.25.0 redesign step 1/2: friendly-frame equivalents of the arena scan/
-- dump buttons above, for diagnosing native click-cast on party/raid/
-- player/target/focus frames.
local debugFriendlyScanBtn = CreateButton(debugContent, "Scan friendly frames", 24, -202, 170, 22, function()
  if SFA.ScanFriendlyFrames then SFA:ScanFriendlyFrames() end
end)
local debugFriendlyAttrBtn = CreateButton(debugContent, "Dump friendly click attrs", 204, -202, 200, 22, function()
  if SFA.DumpFriendlyFrameAttributes then SFA:DumpFriendlyFrameAttributes() end
end)

-- 0.25.7: diagnostic for the Ctrl+Alt+RightClick menu experiment -- lists
-- the real Menu/MenuUtil API on this client into the debug log (read-only,
-- no side effects). See SFA:DumpMenuAPI / SFA_OnManagedFrameClick in Core.lua.
local debugMenuApiBtn = CreateButton(debugContent, "Dump menu API", 24, -234, 150, 22, function()
  if SFA.DumpMenuAPI then SFA:DumpMenuAPI() end
end)

local debugLogCountLabel = CreateLabel(debugContent, "", 24, -264, "GameFontHighlightSmall")

local debugLogBG = CreateFrame("Frame", nil, debugContent, "BackdropTemplate")
debugLogBG:SetPoint("TOPLEFT", 24, -284)
debugLogBG:SetSize(780, 480)
if debugLogBG.SetBackdrop then
  debugLogBG:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  debugLogBG:SetBackdropColor(0.02, 0.02, 0.04, 0.95)
  debugLogBG:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.8)
end

local debugLogScroll = CreateFrame("ScrollFrame", nil, debugLogBG, "UIPanelScrollFrameTemplate")
debugLogScroll:SetPoint("TOPLEFT", 4, -4)
debugLogScroll:SetPoint("BOTTOMRIGHT", -26, 4)

local debugLogEdit = CreateFrame("EditBox", nil, debugLogScroll)
debugLogEdit:SetMultiLine(true)
debugLogEdit:SetAutoFocus(false)
debugLogEdit:SetFontObject("GameFontHighlightSmall")
debugLogEdit:SetWidth(750)
debugLogEdit:SetHeight(480)
debugLogEdit:SetMaxLetters(0)
debugLogEdit:SetTextInsets(4, 4, 4, 4)
debugLogEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
debugLogScroll:SetScrollChild(debugLogEdit)

debugContent:SetHeight(792)

-- Populates the log text box from SFA_DebugLog. Called by the "Show log
-- lines" / "Clear log" buttons, and once automatically whenever the Debug
-- subcategory is displayed (via OnRefresh above -> RefreshOptionsPanel).
function SFA:RefreshDebugLogDisplay()
  if not self.options or not self.options.debugLogEdit then return end
  local lines = SFA_DebugLog or {}
  self.options.debugLogEdit:SetText(table.concat(lines, "\n"))
  self.options.debugLogEdit:SetCursorPosition(0)
  self.options.debugLogEdit:SetHeight(math.max(#lines * 14, 480))
  if self.options.debugLogCountLabel then
    self.options.debugLogCountLabel:SetText(#lines .. " log line(s), oldest first.")
  end
end

local friendlyPanel = CreateCanvasFrame(addonName .. "OptionsFriendly")
friendlyPanel.OnRefresh = function() C_Timer.After(0, function() if SFA and SFA.RefreshOptionsPanel then SFA:RefreshOptionsPanel() end end) end
  local friendlyContent = friendlyPanel.content
  local friendlyTitle = friendlyContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  friendlyTitle:SetPoint("TOPLEFT", 18, -10)
  friendlyTitle:SetText("Simple Frame Assistant")
  local friendlySub = friendlyContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  friendlySub:SetPoint("TOPLEFT", friendlyTitle, "BOTTOMLEFT", 0, -6)
  friendlySub:SetText("Friendly frame options.")
  local friendlySpecLabel = friendlyContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  friendlySpecLabel:SetPoint("TOPLEFT", friendlySub, "BOTTOMLEFT", 0, -4)
  friendlySpecLabel:SetText("|cff7cc6ffClick macros are saved per specialization.|r")
local friendlySection = self:BuildGroupSection(friendlyContent, "friendly", 24, -68)
friendlyContent:SetHeight(498)

  local enemyPanel = CreateCanvasFrame(addonName .. "OptionsEnemy")
  enemyPanel.OnRefresh = function() C_Timer.After(0, function() if SFA and SFA.RefreshOptionsPanel then SFA:RefreshOptionsPanel() end end) end
  local enemyContent = enemyPanel.content
  local enemyTitle = enemyContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  enemyTitle:SetPoint("TOPLEFT", 18, -10)
  enemyTitle:SetText("Simple Frame Assistant")
  local enemySub = enemyContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  enemySub:SetPoint("TOPLEFT", enemyTitle, "BOTTOMLEFT", 0, -6)
  enemySub:SetText("Enemy frame options.")
  local enemySpecLabel = enemyContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  enemySpecLabel:SetPoint("TOPLEFT", enemySub, "BOTTOMLEFT", 0, -4)
  enemySpecLabel:SetText("|cff7cc6ffClick macros are saved per specialization.|r")
local enemySection = self:BuildGroupSection(enemyContent, "enemy", 24, -68)
enemyContent:SetHeight(498)

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory and Settings.RegisterCanvasLayoutSubcategory then
    local category = Settings.RegisterCanvasLayoutCategory(root, "Simple Frame Assistant")
    Settings.RegisterAddOnCategory(category)
    self.settingsCategory = category
    self.settingsRootName = "Simple Frame Assistant"

    local generalSubcategory = Settings.RegisterCanvasLayoutSubcategory(category, root, "General")
    Settings.RegisterCanvasLayoutSubcategory(category, friendlyPanel, "Friendly Frame")
    Settings.RegisterCanvasLayoutSubcategory(category, enemyPanel, "Enemy Frame")
    Settings.RegisterCanvasLayoutSubcategory(category, otherPanel, "Smart Assist")
    Settings.RegisterCanvasLayoutSubcategory(category, debugPanel, "Debug")
    self.settingsGeneralSubcategory = generalSubcategory
  end

  self.options = {
    generalTitle = root.title,
    generalVersion = root.version,
    generalSub = root.sub,
    locked = locked,
    hideHeaders = hideHeaders,
    minimapEnabled = minimapEnabled,
    redesignMacroWindow = redesignMacroWindow,
    otherQuestIndicator = otherQuestIndicator,
    otherTargetXMark = otherTargetXMark,
    otherCharacterGCD = otherCharacterGCD,
    procReadyEnabled = procReadyEnabled,
    procReadyInput = procReadyInput,
    procReadyRows = procReadyRows,
    procReadyEmpty = procReadyEmpty,
    otherBuilderSpenderIndicator = otherBuilderSpenderIndicator,
    friendlySection = friendlySection,
    enemySection = enemySection,
    friendlySpecLabel = friendlySpecLabel,
    enemySpecLabel = enemySpecLabel,
    debugEnabled = debugEnabled,
    debugLogEdit = debugLogEdit,
    debugLogCountLabel = debugLogCountLabel,
  }

  if self.RefreshDebugLogDisplay then self:RefreshDebugLogDisplay() end

  self:RefreshOptionsPanel()
  self:RefreshProcReadyUI()
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

  -- Toggle proc-alert debug: prints "announce <id>" / "re-arm <id>" in chat so
  -- repeated alerts can be traced. Off by default; harmless to leave shipped.
  SLASH_SFAPROCDEBUG1 = "/sfaprocdebug"
  SlashCmdList.SFAPROCDEBUG = function()
    SFA.procReadyDebug = not SFA.procReadyDebug
    DEFAULT_CHAT_FRAME:AddMessage("|cff7cc6ffSFA:|r proc debug " .. (SFA.procReadyDebug and "ON" or "OFF"))
  end

  -- Toggle aura debug: prints (at most once/sec) exactly what
  -- C_UnitAuras.GetAuraDataByIndex returned for the first buff/debuff slot
  -- checked -- whether the call failed, legitimately found nothing, or
  -- succeeded but with icon/spellId/name fields coming back as secret
  -- values. Used to diagnose buffs/debuffs vanishing in combat.
  SLASH_SFAAURADEBUG1 = "/sfaauradebug"
  SlashCmdList.SFAAURADEBUG = function()
    SFA:SetAuraDebug(not SFA.auraDebug)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7cc6ffSFA:|r aura debug " .. (SFA.auraDebug and "ON" or "OFF"))
  end

  -- Clears the persisted diagnostic log (SFA_DebugLog, a SavedVariable --
  -- readable on disk in the account's SavedVariables folder after a
  -- /reload or logout) so a fresh repro run starts from an empty log.
  SLASH_SFACLEARLOG1 = "/sfaclearlog"
  SlashCmdList.SFACLEARLOG = function()
    SFA_DebugLog = {}
    DEFAULT_CHAT_FRAME:AddMessage("|cff7cc6ffSFA:|r debug log cleared")
  end

  -- One-off diagnostic: scans all UI frames for anything that looks like
  -- the native Blizzard arena-enemy frame (Midnight renamed/restructured
  -- the old ArenaEnemyFrame1-5 globals). Requires aura debug ON (Debug tab
  -- or /sfaauradebug) for the per-frame results to be written to the log --
  -- the summary line always prints to chat regardless.
  SLASH_SFASCANARENA1 = "/sfascanarena"
  SlashCmdList.SFASCANARENA = function()
    if SFA.ScanArenaFrames then
      SFA:ScanArenaFrames()
    end
  end
end




