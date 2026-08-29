-- UI/Frame_PracticeKeys.lua
-- The workbench's Keys page: what detection found for every rotation key, an override capture per ability, and the practice-only proc keys (Lust, Drums, Pot, DST, RF, QS) that pop a proc on the sim.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("PracticeKeysView", "AceEvent-3.0")
local Skin = Nock.Skin

local MARGIN = 8
local TOP_PAD = 10
local HEAD_H = 18
local ROW_H = 30
local ROW_GAP = 3
local BLOCK_GAP = 12
local NAME_W = 150
local COL_GAP = 12            -- between the two columns (rotation | proc)
local KEY_BTN_W = 120
local CLEAR_W = 24
local FOOT_H = 34
local MAX_ROWS = 24

local function practice() return Nock:GetModule("Practice", true) end
local function workbench() return Nock:GetModule("PracticeWorkbench", true) end

local function openOptions()
  local dialog = LibStub("AceConfigDialog-3.0", true)
  if dialog then
    dialog:Open("Nock")
    if dialog.SelectGroup then dialog:SelectGroup("Nock", "utilities", "practice", "keys") end
  elseif Nock.OpenConfig then
    Nock:OpenConfig()
  end
end

-- The keys a capture ignores on their own: a modifier is a prefix, never a
-- bind (AceGUIWidget-Keybinding's list).
local IGNORE = {
  UNKNOWN = true, LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
  BUTTON1 = true, BUTTON2 = true,
}
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

----------------------------------------------------------------------------
-- Capture. One capture at a time: the page frame takes the keyboard while
-- `_waiting` names the row, the row's button reads "press a key". ESC
-- clears the bind; a modifier alone is ignored; Shift/Ctrl/Alt prefix the
-- key the way GetBindingKey spells it, and NormalizeKey makes a typed key
-- and a detected one read identically. Mouse buttons 3-5 come in through
-- the button's own OnMouseDown (1 and 2 are the click and the clear).
----------------------------------------------------------------------------
-- A capture target is a page row, or the weave-key dialog's pseudo-row
-- (`kind = "weave"`, its own `frame` for the keyboard, a `paint` of its own).
function View:BeginCapture(row)
  if self._waiting and self._waiting ~= row then self:EndCapture() end
  self._waiting = row
  Skin.SetButtonText(row.keyBtn, "press a key", row.keyBtnW or KEY_BTN_W)
  Skin.ButtonKind(row.keyBtn, "primary")
  local f = row.frame or self.frame
  self._capFrame = f
  f:EnableKeyboard(true)
  if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(false) end
end

function View:EndCapture()
  local row = self._waiting
  self._waiting = nil
  local f = self._capFrame or self.frame
  self._capFrame = nil
  if f then
    f:EnableKeyboard(false)
    if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(true) end
  end
  if row then
    if row.paint then row:paint() else self:PaintRow(row) end
  end
end

-- A key arrived for the waiting row: "" clears, anything else binds.
function View:Commit(key)
  local row = self._waiting
  if not row then return end
  local p = practice()
  local norm = (p and p.NormalizeKey) and p.NormalizeKey(key) or key
  if norm == "" then norm = nil end
  local db = Nock.db and Nock.db.profile
  if row.kind == "weave" then
    -- The real bind, not a practice override (Options -> Weave Bind's own
    -- refusals apply: never the chat or the menu key).
    if norm and GetBindingAction then
      local action = GetBindingAction(norm)
      if action == "OPENCHAT" or action == "OPENCHATSLASH" or action == "TOGGLEGAMEMENU" then
        Nock:Print(("Weave Bind: refusing to override the '%s' key -- you'd lose chat or the game menu."):format(_G["BINDING_NAME_" .. action] or action))
        self:EndCapture()
        return
      end
    end
    if db then
      db.weaveBindKey = norm or ""
      if norm then db.weaveBindEnabled = true end
    end
    self:EndCapture()
    Nock:SendMessage("NOCK_WEAVEBIND_CHANGED")
    self:Rebuild()
    self:PaintDialog()
    return
  end
  if db then
    local store = row.kind == "proc" and "practiceProcKeys" or "practiceKeys"
    db[store] = db[store] or {}
    db[store][row.id] = norm
  end
  self:EndCapture()
  if p and p.ReapplyKeys then p:ReapplyKeys() end
  self:Rebuild()
end

function View:OnKeyDown(key)
  if not self._waiting then return end
  if key == "ESCAPE" then self:Commit("") return end
  if IGNORE[key] then return end
  local out = key
  if IsShiftKeyDown and IsShiftKeyDown() then out = "SHIFT-" .. out end
  if IsControlKeyDown and IsControlKeyDown() then out = "CTRL-" .. out end
  if IsAltKeyDown and IsAltKeyDown() then out = "ALT-" .. out end
  self:Commit(out)
end

local function keyBtnClick(b, button)
  local row = b.row
  if View._waiting == row then
    -- A click on the waiting button with a bindable mouse button binds it;
    -- the left one is a cancel.
    local mb = MOUSE[button]
    if mb then View:OnKeyDown(mb) else View:EndCapture() end
    return
  end
  if button == "RightButton" then
    View._waiting = row
    View:Commit("")
    return
  end
  View:BeginCapture(row)
end

local function weaveBind() return Nock:GetModule("WeaveBind", true) end

local function keyBtnMouseDown(b, button)
  -- A middle/side button while waiting is the bind itself (OnClick would
  -- see it too late: the client fires OnClick for registered buttons only).
  if View._waiting == b.row and MOUSE[button] then View:OnKeyDown(MOUSE[button]) end
end

----------------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------------
function View:AcquireRow()
  local n = self._nRows + 1
  self._nRows = n
  local row = self.rows[n]
  if not row then
    row = CreateFrame("Frame", nil, self.frame)
    row:SetHeight(ROW_H)
    Skin.Surface(row, "surface2", "lineSoft")
    local name = row:CreateFontString(nil, "OVERLAY")
    Skin.Font(name, "uiMedium", Skin.SIZES.body)
    name:SetPoint("LEFT", row, "LEFT", 12, 0)
    name:SetWidth(NAME_W)
    name:SetJustifyH("LEFT"); name:SetWordWrap(false)
    Skin.Text(name, "ink")
    row.name = name
    local info = row:CreateFontString(nil, "OVERLAY")
    Skin.Font(info, "mono", Skin.SIZES.key)
    info:SetPoint("LEFT", name, "RIGHT", 10, 0)
    info:SetJustifyH("LEFT"); info:SetWordWrap(false)
    Skin.Text(info, "ink3")
    row.info = info
    local clear = Skin.Button(row, "x", "ghost", CLEAR_W, ROW_H - 8)
    Skin.Font(clear.text, "monoMedium", Skin.SIZES.key)
    clear:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    clear.row = row
    clear:SetScript("OnClick", function(b) View._waiting = b.row; View:Commit("") end)
    row.clear = clear
    local keyBtn = Skin.Button(row, "", "ghost", KEY_BTN_W, ROW_H - 8)
    Skin.Font(keyBtn.text, "monoMedium", Skin.SIZES.key)
    keyBtn:SetPoint("RIGHT", clear, "LEFT", -6, 0)
    keyBtn.row = row
    keyBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    keyBtn:SetScript("OnClick", keyBtnClick)
    keyBtn:SetScript("OnMouseDown", keyBtnMouseDown)
    row.keyBtn = keyBtn
    info:SetPoint("RIGHT", keyBtn, "LEFT", -10, 0)
    -- The weave row's third button: Import from Grounded / Undo import.
    local imp = Skin.Button(row, "Import from Grounded", "ghost")
    Skin.Font(imp.text, "monoMedium", Skin.SIZES.key)
    imp:SetPoint("RIGHT", keyBtn, "LEFT", -6, 0)
    imp.row = row
    imp:SetScript("OnClick", function(b)
      local wb = weaveBind()
      if not wb then return end
      if b.undo then
        if wb.UndoGroundedImport then wb:UndoGroundedImport() end
      elseif wb.ImportFromGrounded then wb:ImportFromGrounded() end
      View:Rebuild()
    end)
    imp:Hide()
    row.import = imp
    self.rows[n] = row
  end
  row:ClearAllPoints()
  row:Show()
  return row
end

-- The row off its record: the override on the button (or "set key"), the
-- clear only when there is one, the info line (what detection found, or the
-- key another row already holds).
function View:PaintRow(row)
  local r = row.rec
  if not r then return end
  local short = Nock:GetModule("Practice", true)
  short = short and short.ShortKey or function(s) return s end
  local over = r.override
  if self._waiting == row then
    Skin.SetButtonText(row.keyBtn, "press a key", KEY_BTN_W)
    Skin.ButtonKind(row.keyBtn, "primary")
  elseif over then
    Skin.SetButtonText(row.keyBtn, short(over) or over, KEY_BTN_W)
    Skin.ButtonKind(row.keyBtn, "ghost")
    Skin.Text(row.keyBtn.text, "accent")
  else
    Skin.SetButtonText(row.keyBtn, "set key", KEY_BTN_W)
    Skin.ButtonKind(row.keyBtn, "ghost")
  end
  if over then row.clear:Show() else row.clear:Hide() end
  -- The weave row's import / undo button, and the info line's right edge.
  local imp = row.import
  if imp then
    local show = row.kind == "weave" and (r.grounded or r.imported)
    if show then
      imp.undo = (r.imported and not r.grounded) and true or nil
      Skin.SetButtonText(imp, imp.undo and "Undo import" or "Import from Grounded")
      imp:Show()
    else
      imp:Hide()
    end
    row.info:ClearAllPoints()
    row.info:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.info:SetPoint("RIGHT", show and imp or row.keyBtn, "LEFT", -10, 0)
  end
  local text, color
  if row.kind == "weave" then
    if not over and r.grounded then
      text, color = ("Grounded holds %s - import it"):format(r.grounded), "bad"
    elseif over and r.grounded then
      text, color = ("Grounded also holds %s - the import replaces yours"):format(r.grounded), "wait"
    elseif not over then
      text, color = "not set - a weave paper is graded without you", "bad"
    elseif not r.enabled then
      text, color = "set, but Weave Bind is off (Options -> Weave Bind)", "bad"
    elseif r.imported then
      text, color = "Nock's weave bind (from Grounded)", "ink3"
    else
      text, color = "Nock's weave bind: hold to step in, release to step out", "ink3"
    end
  elseif r.clash then
    text, color = ("in use by %s"):format(r.clash), "bad"
  elseif row.kind == "proc" then
    text, color = r.hint or "", "ink3"
  elseif r.detected and r.detected ~= "" then
    text, color = "on your bars: " .. r.detected, "ink3"
  else
    text, color = "not on a bar", "bad"
  end
  row.info:SetText(text)
  Skin.Text(row.info, color)
end

function View:AcquireHead()
  local n = self._nHeads + 1
  self._nHeads = n
  local h = self.heads[n]
  if not h then
    h = self.frame:CreateFontString(nil, "OVERLAY")
    Skin.Font(h, "monoMedium", Skin.SIZES.key)
    h:SetJustifyH("LEFT"); h:SetWordWrap(false)
    Skin.Text(h, "ink3")
    self.heads[n] = h
  end
  h:ClearAllPoints()
  h:Show()
  return h
end

----------------------------------------------------------------------------
-- Frame: the page. Page only -- without a workbench the keys live in Options.
----------------------------------------------------------------------------
function View:OnInitialize()
  local wb = workbench()
  local host = wb and wb.PageFrame and wb:PageFrame() or nil
  if not host then return end
  self._host = host
  local f = CreateFrame("Frame", "NockPracticeKeys", host)
  f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
  f:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
  f:SetHeight(TOP_PAD + FOOT_H)
  f:EnableKeyboard(false)
  f:SetScript("OnKeyDown", function(_, key) View:OnKeyDown(key) end)
  self.frame = f
  self.rows, self.heads = {}, {}
  self._nRows, self._nHeads = 0, 0

  local foot = CreateFrame("Frame", nil, f)
  foot:SetHeight(FOOT_H)
  foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MARGIN, 0)
  foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -MARGIN, 0)
  local note = foot:CreateFontString(nil, "OVERLAY")
  Skin.Font(note, "mono", Skin.SIZES.key)
  note:SetPoint("LEFT", foot, "LEFT", 4, 0)
  note:SetJustifyH("LEFT"); note:SetWordWrap(false)
  Skin.Text(note, "ink3")
  note:SetText("keys are taken over only while practice is on; right-click a key to clear it")
  foot.note = note
  local opts = Skin.Button(foot, "More in Options", "ghost")
  opts:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
  opts:SetScript("OnClick", openOptions)
  foot.opts = opts
  local dump = Skin.Button(foot, "Show detection", "ghost")
  dump:SetPoint("RIGHT", opts, "LEFT", -6, 0)
  dump:SetScript("OnClick", function()
    local p = practice()
    if p and p.DumpKeys then p:DumpKeys() end
  end)
  foot.dump = dump
  self.foot = foot

  if wb.RegisterPage then wb:RegisterPage("keys", f, self) end
  f:Hide()
end

function View:OnEnable()
  self:RegisterMessage("NOCK_PRACTICE_WEAVEKEY", "OnWeaveKeyMessage")
  if not self.frame then return end
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "OnPracticeChanged")
  self:RegisterMessage("NOCK_WEAVEBIND_CHANGED", "OnPracticeChanged")
end

function View:OnPracticeChanged()
  if self._waiting then return end
  if self.frame and self.frame:IsShown() then self:Rebuild() end
  self:PaintDialog()
end

----------------------------------------------------------------------------
-- The weave-key dialog (user, 2026-08-27: "a prominent button to trigger
-- the same window from the workbench to set up the weave key"). One small
-- skinned window over everything: what the key is for, the key Nock holds
-- (or NOT SET), Set key / Clear, and -- when Grounded holds one -- Import
-- from Grounded / Undo import. Opened by the toolbar's WEAVE KEY button
-- (NOCK_PRACTICE_WEAVEKEY) and by the Keys page; Esc closes it. The
-- capture is the page's own (a pseudo-row of kind "weave").
----------------------------------------------------------------------------
local DLG_W, DLG_PAD, DLG_HEAD_H = 500, 16, 26
local CARD_H, CARD_GAP, CARD_MAX = 50, 6, 4
local DLG_BODY_1 = "The key runs one macro as you press and another as you release. Pick where the two come from - you can change it any time in Options -> Weave Bind."
local DLG_BODY_2 = "Hold it to step in and Raptor Strike, release to step out and shoot again. Every weave paper is graded on this key: without one, each weave note is MISSED."

-- The macro choices are the wizard's own cards (Modules/Onboarding.lua's
-- `weavemacro` page: Default / Clever / Natty / From Grounded): one
-- definition of what each shape does, the wizard and this dialog both read.
local function onboarding() return Nock:GetModule("Onboarding", true) end
local function macroPage()
  local ob = onboarding()
  local pages = ob and ob.Pages
  if not pages then return nil, ob end
  for i = 1, #pages do if pages[i].key == "weavemacro" then return pages[i], ob end end
  return nil, ob
end

function View:EnsureDialog()
  if self.dialog then return self.dialog end
  local f = CreateFrame("Frame", "NockPracticeWeaveKey", UIParent)
  f:SetSize(DLG_W, 200)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  Skin.Surface(f, "surface", "line")
  if Nock.UI.RegisterPracticeScale then Nock.UI.RegisterPracticeScale(f) end
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  f:EnableKeyboard(false)
  f:SetScript("OnKeyDown", function(_, key) View:OnKeyDown(key) end)
  f:SetScript("OnHide", function() if View._waiting == View.dlgRow then View:EndCapture() end end)
  if UISpecialFrames then tinsert(UISpecialFrames, "NockPracticeWeaveKey") end

  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  head:SetHeight(DLG_HEAD_H)
  Skin.Surface(head, "surface2")
  local rule = Skin.Rule(head, "lineSoft")
  rule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)
  rule:SetHeight(1)
  local hTitle = head:CreateFontString(nil, "OVERLAY")
  Skin.Font(hTitle, "monoMedium", Skin.SIZES.key)
  hTitle:SetPoint("LEFT", head, "LEFT", 8, 0)
  hTitle:SetText("WEAVE KEY")
  Skin.Text(hTitle, "ink3")
  local stepFs = head:CreateFontString(nil, "OVERLAY")
  Skin.Font(stepFs, "mono", Skin.SIZES.key)
  stepFs:SetPoint("LEFT", hTitle, "RIGHT", 12, 0)
  Skin.Text(stepFs, "ink3")
  local close = Skin.Button(head, "x", "ghost", 22, DLG_HEAD_H - 6)
  Skin.Font(close.text, "monoMedium", Skin.SIZES.key)
  close:SetPoint("RIGHT", head, "RIGHT", -3, 0)
  close:SetScript("OnClick", function() f:Hide() end)

  local title = f:CreateFontString(nil, "OVERLAY")
  Skin.Font(title, "display", Skin.SIZES.title)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", DLG_PAD, -(DLG_HEAD_H + 12))
  title:SetJustifyH("LEFT")
  Skin.Text(title, "ink")
  local body = f:CreateFontString(nil, "OVERLAY")
  Skin.Font(body, "ui", Skin.SIZES.body)
  body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  body:SetPoint("RIGHT", f, "RIGHT", -DLG_PAD, 0)
  body:SetJustifyH("LEFT"); body:SetJustifyV("TOP")
  body:SetHeight(48)
  Skin.Text(body, "ink2")

  -- Step 1: the macro cards, one per row.
  local cardsF = CreateFrame("Frame", nil, f)
  cardsF:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -10)
  cardsF:SetPoint("RIGHT", f, "RIGHT", -DLG_PAD, 0)
  cardsF:SetHeight(CARD_MAX * (CARD_H + CARD_GAP))
  local cards = {}
  for i = 1, CARD_MAX do
    local c = CreateFrame("Button", nil, cardsF)
    c:SetHeight(CARD_H)
    c:SetPoint("TOPLEFT", cardsF, "TOPLEFT", 0, -(i - 1) * (CARD_H + CARD_GAP))
    c:SetPoint("RIGHT", cardsF, "RIGHT", 0, 0)
    Skin.Surface(c, "surface2", "lineSoft")
    local bar = c:CreateTexture(nil, "OVERLAY")
    bar:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, 0)
    bar:SetWidth(3)
    Skin.Paint(bar, "accent")
    bar:Hide()
    c.bar = bar
    local label = c:CreateFontString(nil, "OVERLAY")
    Skin.Font(label, "uiMedium", Skin.SIZES.body)
    label:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -8)
    label:SetJustifyH("LEFT"); label:SetWordWrap(false)
    Skin.Text(label, "ink")
    c.label = label
    local chip = c:CreateFontString(nil, "OVERLAY")
    Skin.Font(chip, "monoMedium", Skin.SIZES.key)
    chip:SetPoint("LEFT", label, "RIGHT", 8, 0)
    chip:SetJustifyH("LEFT"); chip:SetWordWrap(false)
    c.chip = chip
    local desc = c:CreateFontString(nil, "OVERLAY")
    Skin.Font(desc, "ui", Skin.SIZES.small)
    desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    desc:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
    desc:SetHeight(CARD_H - 8 - Skin.SIZES.body - 3 - 4)
    Skin.Text(desc, "ink2")
    c.desc = desc
    c:SetScript("OnEnter", function(b) if not b.selected then Skin.Surface(b, "surface2", "line") end end)
    c:SetScript("OnLeave", function(b) if not b.selected then Skin.Surface(b, "surface2", "lineSoft") end end)
    c:SetScript("OnClick", function(b) View:PickCard(b) end)
    c:Hide()
    cards[i] = c
  end
  local undoBtn = Skin.Button(f, "Undo the Grounded import", "ghost")
  undoBtn:SetScript("OnClick", function()
    local wb = weaveBind()
    if wb and wb.UndoGroundedImport then wb:UndoGroundedImport() end
    View:PaintDialog()
    if View.frame and View.frame:IsShown() then View:Rebuild() end
  end)
  undoBtn:Hide()

  -- Step 2: the key.
  local keyF = CreateFrame("Frame", nil, f)
  keyF:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -10)
  keyF:SetPoint("RIGHT", f, "RIGHT", -DLG_PAD, 0)
  keyF:SetHeight(Skin.SIZES.h2 + 14 + Skin.BUTTON_H + 10 + 14)
  local keyFs = keyF:CreateFontString(nil, "OVERLAY")
  Skin.Font(keyFs, "monoMedium", Skin.SIZES.h2)
  keyFs:SetPoint("TOPLEFT", keyF, "TOPLEFT", 0, 0)
  keyFs:SetJustifyH("LEFT")
  local note = keyF:CreateFontString(nil, "OVERLAY")
  Skin.Font(note, "mono", Skin.SIZES.key)
  note:SetPoint("LEFT", keyFs, "RIGHT", 10, 0)
  note:SetPoint("RIGHT", keyF, "RIGHT", 0, 0)
  note:SetJustifyH("LEFT"); note:SetWordWrap(false)
  local setBtn = Skin.Button(keyF, "Set key", "primary", 110, Skin.BUTTON_H)
  setBtn:SetPoint("TOPLEFT", keyFs, "BOTTOMLEFT", 0, -14)
  setBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local clearBtn = Skin.Button(keyF, "Clear", "ghost", 64, Skin.BUTTON_H)
  clearBtn:SetPoint("LEFT", setBtn, "RIGHT", 6, 0)
  local keyFoot = keyF:CreateFontString(nil, "OVERLAY")
  Skin.Font(keyFoot, "mono", Skin.SIZES.key)
  keyFoot:SetPoint("TOPLEFT", setBtn, "BOTTOMLEFT", 0, -10)
  keyFoot:SetPoint("RIGHT", keyF, "RIGHT", 0, 0)
  keyFoot:SetJustifyH("LEFT"); keyFoot:SetWordWrap(false)
  keyFoot:SetText("Mouse buttons 3-5 work too. Esc while waiting clears the key.")
  Skin.Text(keyFoot, "ink3")

  -- The nav row: Back / Next (Done), and the step's note on the left.
  local nav = CreateFrame("Frame", nil, f)
  nav:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", DLG_PAD, DLG_PAD)
  nav:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -DLG_PAD, DLG_PAD)
  nav:SetHeight(Skin.BUTTON_H)
  local nextBtn = Skin.Button(nav, "Next", "primary", 80, Skin.BUTTON_H)
  nextBtn:SetPoint("RIGHT", nav, "RIGHT", 0, 0)
  nextBtn:SetScript("OnClick", function()
    if View._step == 1 then View:ApplyPick(); View:SetStep(2) else f:Hide() end
  end)
  local backBtn = Skin.Button(nav, "Back", "ghost", 64, Skin.BUTTON_H)
  backBtn:SetPoint("RIGHT", nextBtn, "LEFT", -6, 0)
  backBtn:SetScript("OnClick", function() View:SetStep(1) end)
  undoBtn:SetParent(nav)
  undoBtn:SetPoint("LEFT", nav, "LEFT", 0, 0)
  local navNote = nav:CreateFontString(nil, "OVERLAY")
  Skin.Font(navNote, "mono", Skin.SIZES.key)
  navNote:SetPoint("LEFT", nav, "LEFT", 0, 0)
  navNote:SetPoint("RIGHT", backBtn, "LEFT", -10, 0)
  navNote:SetJustifyH("LEFT"); navNote:SetWordWrap(false)
  Skin.Text(navNote, "ink3")

  -- The pseudo-row the page's capture drives.
  local row = { kind = "weave", id = "weave", frame = f, keyBtn = setBtn, keyBtnW = 110 }
  row.paint = function() View:PaintDialog() end
  setBtn.row = row
  setBtn:SetScript("OnClick", keyBtnClick)
  setBtn:SetScript("OnMouseDown", keyBtnMouseDown)
  clearBtn:SetScript("OnClick", function() View._waiting = row; View:Commit("") end)

  f.stepFs, f.title, f.body, f.cardsF, f.cards, f.undoBtn = stepFs, title, body, cardsF, cards, undoBtn
  f.keyF, f.keyFs, f.note, f.setBtn, f.clearBtn = keyF, keyFs, note, setBtn, clearBtn
  f.nav, f.next, f.back, f.navNote = nav, nextBtn, backBtn, navNote
  f:Hide()
  self.dialog, self.dlgRow = f, row
  self._step = 1
  return f
end

-- A card click only CHOOSES (user, 2026-08-27: "import from Grounded should
-- happen on Next, not on select"); Next applies the choice: the wizard's own
-- SelectCard (apply + the messages) with the feature switched on first --
-- the dialog exists to set the bind up, where the wizard leaves enabling to
-- the key step. A choice that is already in force applies nothing.
function View:PickCard(card)
  if not card.opt then return end
  self._pick = card.opt
  self:PaintDialog()
end

function View:ApplyPick()
  local page, ob = macroPage()
  local opt = self._pick
  if not (page and ob and opt) then return end
  local db = Nock.db and Nock.db.profile
  local inForce = opt.isSelected and opt.isSelected(db or {}) and db and db.weaveBindEnabled == true
  if inForce then return end
  if db then db.weaveBindEnabled = true end
  if ob.SelectCard then ob:SelectCard(page, opt) end
  self._pick = nil
  if self.frame and self.frame:IsShown() then self:Rebuild() end
end

function View:SetStep(n)
  self._step = n
  if self._waiting == self.dlgRow then self:EndCapture() end
  self:PaintDialog()
end

local function fixedH() return DLG_HEAD_H + 12 + Skin.SIZES.title + 6 + 48 + 10 end

function View:PaintDialog()
  local f = self.dialog
  if not (f and f:IsShown()) then return end
  local p = practice()
  local db = Nock.db and Nock.db.profile or {}
  local r = (p and p.WeaveKeyState) and p:WeaveKeyState() or {}
  local short = (p and p.ShortKey) or function(s) return s end
  local step = self._step or 1
  f.stepFs:SetText(("STEP %d OF 2"):format(step))
  if step == 1 then
    f.title:SetText("Your weave macros")
    f.body:SetText(DLG_BODY_1)
    f.keyF:Hide()
    f.cardsF:Show()
    local page = macroPage()
    local n = 0
    -- The choice: the card clicked, else the one in force. The highlight
    -- follows the choice; CURRENT names the one in force.
    local pick, current = self._pick, nil
    if page then
      for _, opt in ipairs(page.options or {}) do
        if not (opt.visible and not opt.visible(db)) and opt.isSelected and opt.isSelected(db) and r.enabled then current = opt end
      end
    end
    if not pick then pick = current end
    if page then
      for _, opt in ipairs(page.options or {}) do
        if n < CARD_MAX and not (opt.visible and not opt.visible(db)) then
          n = n + 1
          local c = f.cards[n]
          c.opt = opt
          c.label:SetText(opt.label or opt.value or "")
          c.desc:SetText(opt.desc or "")
          local sel = opt == pick
          c.selected = sel
          if opt == current then c.chip:SetText("CURRENT"); Skin.Text(c.chip, sel and "accent" or "ink3")
          elseif sel then c.chip:SetText("CHOSEN"); Skin.Text(c.chip, "accent")
          else c.chip:SetText(opt.recommended and "RECOMMENDED" or ""); Skin.Text(c.chip, "ink3") end
          if sel then
            Skin.Surface(c, "surface2", "accent")
            c.bar:Show()
          else
            Skin.Surface(c, "surface2", "lineSoft")
            c.bar:Hide()
          end
          c:Show()
        end
      end
    end
    for i = n + 1, CARD_MAX do f.cards[i]:Hide(); f.cards[i].opt = nil end
    f.cardsF:SetHeight(math.max(1, n * (CARD_H + CARD_GAP) - CARD_GAP))
    f.navNote:SetText(page and "" or "Macro choices live in Options -> Weave Bind.")
    if r.imported then f.undoBtn:Show(); f.navNote:Hide() else f.undoBtn:Hide(); f.navNote:Show() end
    f.back:Hide()
    local applies = pick and pick ~= current
    local label = "Next: the key"
    if applies then label = (pick.value == "grounded") and "Import, then the key" or "Apply, then the key" end
    Skin.SetButtonText(f.next, label, applies and 150 or 120)
    f:SetHeight(fixedH() + f.cardsF:GetHeight() + 12 + Skin.BUTTON_H + DLG_PAD)
  else
    f.title:SetText("Your weave key")
    f.body:SetText(DLG_BODY_2)
    f.cardsF:Hide()
    f.undoBtn:Hide()
    f.keyF:Show()
    local over = r.override
    if over then
      f.keyFs:SetText(short(over) or over)
      Skin.Text(f.keyFs, "accent")
    else
      f.keyFs:SetText("NOT SET")
      Skin.Text(f.keyFs, "bad")
    end
    local text, color
    if not over and r.grounded then text, color = ("Grounded holds %s - pick From Grounded on step 1 to bring it along"):format(r.grounded), "bad"
    elseif over and r.grounded then text, color = ("Grounded also holds %s"):format(r.grounded), "wait"
    elseif not over then text, color = "a weave paper is graded without you", "bad"
    elseif not r.enabled then text, color = "set, but Weave Bind is off", "bad"
    elseif r.imported then text, color = "from Grounded", "ink3"
    else text, color = "Nock's weave bind", "ink3" end
    f.note:SetText(text)
    Skin.Text(f.note, color)
    if self._waiting == self.dlgRow then
      Skin.SetButtonText(f.setBtn, "press a key", 110)
      Skin.ButtonKind(f.setBtn, "primary")
    else
      Skin.SetButtonText(f.setBtn, over and "Change key" or "Set key", 110)
      Skin.ButtonKind(f.setBtn, over and "ghost" or "primary")
    end
    if over then f.clearBtn:Show() else f.clearBtn:Hide() end
    f.navNote:SetText("Also in Options -> Weave Bind.")
    f.navNote:Show()
    f.back:Show()
    Skin.SetButtonText(f.next, "Done", 80)
    f:SetHeight(fixedH() + f.keyF:GetHeight() + 12 + Skin.BUTTON_H + DLG_PAD)
  end
end

function View:OpenDialog()
  local f = self:EnsureDialog()
  self._step = 1
  self._pick = nil
  f:Show()
  self:PaintDialog()
end

function View:OnWeaveKeyMessage(_, on)
  if on == false then
    if self.dialog then self.dialog:Hide() end
  else
    self:OpenDialog()
  end
end

function View:OnPageShow() self:Rebuild() end
function View:OnPageHide() if self._waiting then self:EndCapture() end end
function View:PageHeight() return self._pageH or (TOP_PAD + FOOT_H) end

----------------------------------------------------------------------------
-- Build: the rotation keys off Practice:KeyRows (detection + override), the
-- proc keys off Practice.PROC_KEYS with their state.
----------------------------------------------------------------------------
function View:Rebuild()
  local f = self.frame
  if not f then return end
  local p = practice()
  self._nRows, self._nHeads = 0, 0
  -- Two columns (2026-08-27): the rotation keys on the left, the proc keys on
  -- the right. Sixteen rows in one column made this the tallest page (~1250
  -- units at the default scale) and ran it off a 1080p screen.
  local wb = workbench()
  local pageW = (wb and wb.PageWidth and wb:PageWidth()) or 960
  local colW = math.floor((pageW - MARGIN * 2 - COL_GAP) / 2)
  local ys = { TOP_PAD, TOP_PAD }
  local function colX(c) return MARGIN + (c - 1) * (colW + COL_GAP) end
  local function head(c, text)
    local h = self:AcquireHead()
    h:SetPoint("TOPLEFT", f, "TOPLEFT", colX(c) + 4, -ys[c])
    h:SetWidth(colW - 8)
    h:SetText(text)
    ys[c] = ys[c] + HEAD_H
  end
  local function row(c, kind, id, rec, label)
    if self._nRows >= MAX_ROWS then return end
    local r = self:AcquireRow()
    r.kind, r.id, r.rec = kind, id, rec
    r:SetPoint("TOPLEFT", f, "TOPLEFT", colX(c), -ys[c])
    r:SetWidth(colW)
    r.name:SetText(label)
    self:PaintRow(r)
    ys[c] = ys[c] + ROW_H + ROW_GAP
  end

  -- The weave key first (user, 2026-08-27): Nock's own bind, the one the
  -- weave papers are graded on -- and where a Grounded bind comes in.
  head(1, "WEAVE KEY  -  the real bind (Weave Bind), not a practice override")
  local wk = (p and p.WeaveKeyState) and p:WeaveKeyState() or nil
  if wk then row(1, "weave", "weave", wk, "Weave key") end
  ys[1] = ys[1] + BLOCK_GAP
  head(1, "ROTATION KEYS  -  from your bars; an override replaces it")
  local rows = (p and p.KeyRows) and p:KeyRows() or {}
  for i = 1, #rows do
    local rec = rows[i]
    row(1, "rot", rec.name, rec, rec.label)
  end
  head(2, "PROC KEYS  -  practice only: press pops it, again holds it, again off")
  local procs = (p and p.PROC_KEYS) or {}
  for i = 1, #procs do
    local spec = procs[i]
    local rec = (p and p.ProcKeyState) and p:ProcKeyState(spec.name) or { hint = spec.hint }
    rec.hint = rec.hint or spec.hint
    row(2, "proc", spec.name, rec, spec.label)
  end
  for i = self._nRows + 1, #self.rows do self.rows[i]:Hide() end
  for i = self._nHeads + 1, #self.heads do self.heads[i]:Hide() end
  self._pageH = math.max(ys[1], ys[2]) + 6 + FOOT_H
  f:SetHeight(self._pageH)
  Nock:SendMessage("NOCK_PRACTICE_LAYOUT")
end
