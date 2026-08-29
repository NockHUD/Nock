-- UI/Frame_Practice.lua
-- Practice mode header strip: scenario name, ladder ribbon, state chip, streak,
-- metronome and the fight buttons, over the conveyor stage (proc palette under
-- it). Pure renderer of state.sim; buttons call Modules/Practice.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local PracticeView = Nock:NewModule("PracticeView", "AceEvent-3.0")
local C = Nock.Constants
local Palette = Nock.UI.PracticePalette
-- The practice shell's skin (UI/Skin.lua): the header is the workbench's
-- TOOLBAR now -- scenario name in the display face, mono chips, ghost buttons
-- and one primary Start -- and the stage sits flush under it.
local Skin = Nock.Skin

-- ONE width for the whole practice panel, and the docked stage takes it from
-- here (the conveyor's ApplyDock reads the host's width). 960 is the D2 ruling:
-- WoW's UI scale shrinks a frame to roughly 0.6x at 1440p, so a strip that reads
-- at arm's length in the client has to be drawn far wider than it looks here.
local PANEL_W, PAD = 960, C.DIM.OUTER_PAD
local INNER_W = PANEL_W - PAD * 2

-- The panel is a header strip over the stage. The stage's height is not ours
-- (the conveyor's Host reports it), and the palette row is only there when the
-- drill lets you pop something.
local HEADER_H = 40
-- The toolbar's side insets in the workbench (the "Workbench States" page:
-- 14 px), and the panel's own when it floats without a workbench.
local TOOL_INSET = 8          -- the left one lines up with the stage's row icons
local TOOL_INSET_R = 12
local PAL_SIZE, PAL_GAP = 30, 5
local PAL_ROW_H = PAL_SIZE + 4
local PAL_TOP_GAP = 4

-- The first-run hint bar, between the header and the stage. One line, one X,
-- gone for good once dismissed (per character, `practiceHints.stage`).
local HINT_H, HINT_GAP = 20, 3
local HINT_TEXT =
  "Notes slide toward the gold line - press when they touch it. Your first drill: just Steady, never clip."

local CHIP_H = Skin.CHIP_H
-- The name block is a FIXED width: the sub-line under it re-formats from the
-- tick (the notation changes with haste), and a width that followed the text
-- would move the state chip every time it did.
local NAME_W = 196
local NAME_SIZE, SUB_SIZE = 18, Skin.SIZES.key
local CHEV_GAP = 4            -- the picker's chevron leads the name; this much ink-to-ink between them
-- The ladder ribbon: one pip per rung and `drill n/N`, right of the scenario
-- name, so the ladder's progress is readable without opening the Lesson. A
-- FIXED box for the same reason the name block is one -- the state chip must
-- not shuffle when a rung turns over.
--
-- Round 5b took the ladder from six rungs to eleven (ten since Free play left
-- it, 2026-08-27). The pip count follows it (a ribbon that stopped at six
-- would have hidden the whole weave track), and the pips shrank to pay for
-- the width.
local RIB_DOTS, RIB_DOT, RIB_GAP = 10, 7, 4
local RIB_TEXT_W = 52
local RIB_W = RIB_DOTS * RIB_DOT + (RIB_DOTS - 1) * RIB_GAP + 6 + RIB_TEXT_W
-- The current pip's glow, faked the same way the stage's hit line fakes its
-- own: additive slabs of falling size. { pad, alpha }, widest first.
local RIB_GLOW = { { 6, 0.16 }, { 3, 0.22 } }
local STREAK_W = 58
local BTN_H, BTN_W = Skin.BUTTON_H, 60
local MET_BOX = 14
-- Streak milestones (D2): 5 in a row turns the number good-green, 10 takes it
-- brighter still and puts a coloured shadow behind it. Change-gated by TIER in
-- PaintStreak, so a streak climbing 6..7..8 writes the string and nothing else.
--
-- ONE FontString wears all of it (Round 4). The milestone used to be a SECOND
-- FontString of the same number, a point bigger and thick-outlined, centred on
-- the first: two auto-width strings in two faces do not share a centre, so from
-- 10 up the header read the number twice, side by side and a pixel off. A
-- shadow is the same halo with nothing to misalign.
local STREAK_GREEN, STREAK_GLOW = 5, 10
-- The >= 10 ink, and the shadow behind it. Brighter than GOOD so the tier still
-- reads as a step up, and the shadow is that same green at a one-pixel offset:
-- the client draws it under the glyph, inside the outline, which is where the
-- second FontString was trying to be.
local STREAK_SHADOW = { Skin.COLORS.accent[1], Skin.COLORS.accent[2], Skin.COLORS.accent[3], 0.55 }

-- Verdict colours (the toast). Kept separate from the chip palette: these are
-- the grader's own codes and are shared with the conveyor's marks.
local COLOR = {
  GOOD = { 0.25, 0.85, 0.40 }, LATE = { 0.95, 0.70, 0.15 }, CATCHUP_MISSED = { 0.95, 0.70, 0.15 },
  STEADY_WONT_FIT = { 0.95, 0.70, 0.15 }, CLIP = { 0.95, 0.25, 0.20 },
  WEAVE_OK = { 0.25, 0.85, 0.40 }, WEAVE_SLOW = { 0.95, 0.70, 0.15 }, WEAVE_MISSED = { 0.95, 0.70, 0.15 },
  REARM = { 0.95, 0.70, 0.15 }, DEAD_ZONE = { 0.95, 0.25, 0.20 },
  EARLY = { 0.95, 0.70, 0.15 },
}

-- The streak number's LOOK for the tier it is currently on -- colour, and at
-- tier 3 the halo. Split out of PaintStreak so the header-font registry can
-- re-run it after a font re-apply (SetFont clears the shadow, and PaintStreak's
-- tier gate will not ask again until the number moves). Reads the tier off the
-- module rather than taking it as an argument, because the registry's callback
-- knows only the FontString; before the first paint there is no tier and the
-- number wears the resting look.
local function paintStreakTier(fs)
  if not fs then return end
  -- 0 dim, 1 plain ink, 2 the accent, 3 the accent over its own shadow: one
  -- green (the accent IS good), a step brighter each tier, never a second hue.
  local tier = PracticeView._streakTier or 0
  if tier >= 2 then Skin.Text(fs, "accent")
  elseif tier == 1 then Skin.Text(fs, "ink")
  else Skin.Text(fs, "ink3") end
  if tier == 3 then
    fs:SetShadowColor(STREAK_SHADOW[1], STREAK_SHADOW[2], STREAK_SHADOW[3], STREAK_SHADOW[4])
    fs:SetShadowOffset(1, -1)
  else
    fs:SetShadowColor(0, 0, 0, 0)
    fs:SetShadowOffset(0, 0)
  end
end

-- The four keys a drill cannot run without. Detection finds them on the action
-- bars; the header says so when it found none of them.
local SHOT_KEYS = { "steady", "multi", "arcane", "autoshot" }

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function practice() return Nock:GetModule("Practice", true) end

-- The per-character first-run hint set. Created on demand rather than trusted to
-- exist: an older SavedVariables predates the key, and AceDB only merges the
-- default table for profiles it creates.
local function hints()
  local db = Nock.db and Nock.db.profile
  if not db then return nil end
  local h = db.practiceHints
  if type(h) ~= "table" then h = {}; db.practiceHints = h end
  return h
end

local function toggleDock()
  local cv = Nock:GetModule("PracticeConveyorView", true)
  if cv then cv:ToggleDock() end
end

-- The proc palette lives in UI/PracticePalette.lua (Nock.UI.PracticePalette),
-- shared with the expert combat log since 2026-08-27; the panel seats one
-- under the stage.

----------------------------------------------------------------------------
-- Small parts of the visual system: chips (a bordered pill with centred text,
-- auto-width) and the tooltip helpers the header's small controls share.
----------------------------------------------------------------------------

local function makeChip(parent, size)
  return Skin.Chip(parent, size)
end

-- Text + colours (skin tokens) in one call, then the width follows the
-- string. Callers gate this on their own change check: it is never cheap
-- enough for a tick.
local function setChip(chip, text, fill, ink)
  Skin.SetChip(chip, text, fill, ink)
end

-- Two-line tooltip on any header control. `tipTitle` / `tipText` are set on the
-- frame at build time, so the handlers themselves are shared and allocate
-- nothing.
local function tipEnter(btn)
  if not btn.tipTitle then return end
  GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(btn.tipTitle, 1, 0.82, 0.2)
  if btn.tipText then GameTooltip:AddLine(btn.tipText, 0.8, 0.8, 0.8, true) end
  GameTooltip:Show()
end
local function tipLeave() GameTooltip:Hide() end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------

function PracticeView:OnInitialize()
  local f = CreateFrame("Frame", "NockPracticePanel", UIParent, "BackdropTemplate")
  -- Hosted in the practice workbench when it exists (UI/Frame_Workbench.lua,
  -- loaded first): the panel becomes the workbench's Stage page -- no drag,
  -- no backdrop, no scale or position of its own; the workbench owns those.
  local wb = Nock:GetModule("PracticeWorkbench", true)
  local host = wb and wb.ContentFrame and wb:ContentFrame() or nil
  self._host = host
  -- Every drag/tooltip frame of the panel: mouse-enabled only while no fight
  -- runs. A mouse-enabled frame under the pointer SWALLOWS mouse buttons, and
  -- a weave key is usually one (MOUSE4/5) -- hovering the panel or the strip
  -- docked in it broke the weave (user, 2026-08-24). Buttons keep their own.
  local mouseFrames = { f }
  self._mouseFrames = mouseFrames
  f:SetSize(PANEL_W, HEADER_H + PAD)
  local inset = host and TOOL_INSET or PAD
  local insetR = host and TOOL_INSET_R or PAD
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  -- Practice windows are tools, not HUD chrome: draggable whenever no fight
  -- runs, regardless of the global lock — locked only while a fight is on.
  local function dragStart()
    if Nock.state.sim.fightOn or host then return end
    f:StartMoving()
  end
  local function dragStop()
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    Nock.db.profile.practicePanelPos = { point = point, relPoint = relPoint, x = x, y = y }
  end
  f:SetScript("OnDragStart", dragStart)
  f:SetScript("OnDragStop", dragStop)
  if host then
    f:SetParent(host)
    f:SetToplevel(false)
    f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
  else
    Nock.UI.RegisterPanelBackground(f)
    -- The practice scale (Options -> Practice), on the top-level frame only: the
    -- header's controls and the DOCKED stage are children and inherit it.
    Nock.UI.RegisterPracticeScale(f)
    local pos = profile("practicePanelPos", nil)
    if pos then f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, 160) end
  end

  ------------------------------------------------------------------------
  -- The header strip. The bar itself is the drag handle (same gate), and
  -- everything in the row is a child of it so the controls take the mouse
  -- before the bar's own drag does.
  ------------------------------------------------------------------------
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", inset, 0)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -insetR, 0)
  bar:SetHeight(HEADER_H)
  bar:EnableMouse(true)
  -- The rule under the toolbar, the whole width of the panel: the stage hangs
  -- straight off it.
  local barRule = Skin.Rule(f, "lineSoft")
  barRule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEADER_H)
  barRule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEADER_H)
  barRule:SetHeight(1)
  mouseFrames[#mouseFrames + 1] = bar
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", dragStart)
  bar:SetScript("OnDragStop", dragStop)
  -- The dock flip lives on the whole strip, not just on the grip: the header IS
  -- the panel now, and a right-click anywhere on it is the affordance people
  -- reach for. Children with their own mouse handlers take theirs first.
  bar:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then toggleDock() end
  end)

  -- Grip: three short vertical rules, the mock's drag affordance — and the one
  -- control the footer's Undock button left behind, so it carries the dock flip
  -- on a right-click (the Options toggle is the other way to it).
  local grip = CreateFrame("Button", nil, bar)
  grip:SetSize(11, 14)
  grip:SetPoint("LEFT", bar, "LEFT", 0, 0)
  grip:RegisterForClicks("RightButtonUp")
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", dragStart)
  grip:SetScript("OnDragStop", dragStop)
  grip.tipTitle = "Practice"
  grip.tipText = "Drag to move. Right-click: dock or undock the stage."
  grip:SetScript("OnEnter", tipEnter)
  grip:SetScript("OnLeave", tipLeave)
  grip:SetScript("OnClick", toggleDock)
  local griphl = grip:CreateTexture(nil, "HIGHLIGHT")
  griphl:SetAllPoints()
  griphl:SetColorTexture(1, 1, 1, 0.05)
  for i = 1, 3 do
    local t = grip:CreateTexture(nil, "ARTWORK")
    Skin.Paint(t, "ink3", 0.7)
    t:SetSize(1, 10)
    t:SetPoint("LEFT", grip, "LEFT", (i - 1) * 3, 0)
  end
  -- Hosted, the workbench is the window and the rail has the dock flip's
  -- job: no grip. Hidden, not unmade -- the scenario block anchors to it, and
  -- a hidden frame keeps its geometry, so the block sits where it would.
  if host then grip:Hide(); grip:SetWidth(1) end

  -- Scenario name + its sub-line. The whole block is the picker's button: the
  -- scenario card is gone, and the name is where you now click to change it.
  local scenBtn = CreateFrame("Button", nil, bar)
  scenBtn:SetSize(NAME_W, HEADER_H - 6)
  scenBtn:SetPoint("LEFT", grip, "RIGHT", host and -4 or 5, 0)
  scenBtn.tipTitle = "Scenario"
  scenBtn.tipText = "Click to pick a drill."
  -- Hover: the name and its chevron take the accent -- the block reads as a
  -- control, not a heading (user, 2026-08-27: "you need to know that you
  -- can click there").
  scenBtn:SetScript("OnEnter", function(b)
    b.hot = true
    Skin.Text(b.name, "accent")
    local r, g, bl = Skin.Color("accent")
    b.chev:SetVertexColor(r, g, bl, 1)
    tipEnter(b)
  end)
  scenBtn:SetScript("OnLeave", function(b)
    b.hot = nil
    Skin.Text(b.name, "ink")
    local r, g, bl = Skin.Color("ink3")
    b.chev:SetVertexColor(r, g, bl, 1)
    tipLeave(b)
  end)
  scenBtn:SetScript("OnClick", function() Nock:SendMessage("NOCK_PRACTICE_SCENARIOS_TOGGLE") end)
  local hl = scenBtn:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.05)

  -- The scenario name in the shell's display face; the data line under it
  -- in mono (notation and latency: the display face has holes in its
  -- punctuation). A down-chevron (the pixel atlas) LEADS the name (user,
  -- 2026-08-27: "chevron on the left, ~4 px spacing to the right"): the one
  -- affordance that says "this opens a list". The 24-grid glyph has ~4 px of
  -- its own margin on each side, so the box hangs that far into the gap on
  -- the left and the name is anchored to the box's edge plus CHEV_GAP less
  -- that margin -- ink to ink it is CHEV_GAP.
  local scenChev = scenBtn:CreateTexture(nil, "ARTWORK")
  Skin.Icon(scenChev, "chevron", "ink3", 1)
  local chevSize = Skin.IconSize(scenChev) or 24
  local chevMargin = chevSize * 4 / 24
  scenChev:SetPoint("LEFT", scenBtn, "LEFT", -chevMargin, 0)
  local scenName = scenBtn:CreateFontString(nil, "OVERLAY")
  scenName:SetPoint("TOPLEFT", scenBtn, "TOPLEFT", chevSize - chevMargin * 2 + CHEV_GAP, -3)
  scenName:SetPoint("RIGHT", scenBtn, "RIGHT", 0, 0)
  scenName:SetJustifyH("LEFT"); scenName:SetWordWrap(false)
  Skin.Font(scenName, "display", NAME_SIZE)
  Skin.Text(scenName, "ink")
  scenBtn.name, scenBtn.chev = scenName, scenChev

  local scenSub = scenBtn:CreateFontString(nil, "OVERLAY")
  Skin.Font(scenSub, "mono", SUB_SIZE)
  scenSub:SetPoint("TOPLEFT", scenName, "BOTTOMLEFT", 1, -1)
  scenSub:SetPoint("RIGHT", scenBtn, "RIGHT", 0, 0)
  scenSub:SetJustifyH("LEFT"); scenSub:SetWordWrap(false)
  Skin.Text(scenSub, "ink3")

  -- The ladder ribbon: one pip per rung and `drill n/N`. Repainted from Relayout
  -- (NOCK_PRACTICE_CHANGED / a dock flip) -- the ladder cannot move mid-tick, so
  -- nothing here is ever touched from Refresh.
  --
  -- Flat pips rather than round art: Nock ships no media and every other
  -- indicator in the addon is the same flat texture, so a round one would be the
  -- only piece of borrowed art in the panel -- and the only piece this file
  -- could not verify exists on the Anniversary client.
  local ribbon = CreateFrame("Frame", nil, bar)
  ribbon:SetSize(RIB_W, HEADER_H - 10)
  ribbon:SetPoint("LEFT", scenBtn, "RIGHT", 8, 0)
  ribbon:EnableMouse(true)
  mouseFrames[#mouseFrames + 1] = ribbon
  ribbon.tipTitle = "Drill ladder"
  ribbon.tipText = "Turret, weave, then mastery - easiest first. Open the Lesson to pick one."
  ribbon:SetScript("OnEnter", tipEnter)
  ribbon:SetScript("OnLeave", tipLeave)
  -- The glow: seated on whichever pip is current, by PaintRibbon.
  local ribGlow = {}
  for i = 1, #RIB_GLOW do
    local t = ribbon:CreateTexture(nil, "ARTWORK")
    Skin.Paint(t, "accent", RIB_GLOW[i][2])
    t:SetBlendMode("ADD")
    t:Hide()
    ribGlow[i] = t
  end
  local ribDots = {}
  for i = 1, RIB_DOTS do
    local t = ribbon:CreateTexture(nil, "OVERLAY")
    t:SetSize(RIB_DOT, RIB_DOT)
    t:SetPoint("LEFT", ribbon, "LEFT", (i - 1) * (RIB_DOT + RIB_GAP), 0)
    Skin.Paint(t, "line", 1)
    ribDots[i] = t
  end
  local ribText = ribbon:CreateFontString(nil, "OVERLAY")
  Skin.Font(ribText, "mono", SUB_SIZE)
  ribText:SetPoint("LEFT", ribbon, "LEFT", RIB_DOTS * (RIB_DOT + RIB_GAP) + 1, 0)
  ribText:SetWidth(RIB_TEXT_W)
  ribText:SetJustifyH("LEFT"); ribText:SetWordWrap(false)
  Skin.Text(ribText, "ink3")
  ribbon.dots, ribbon.glow, ribbon.text = ribDots, ribGlow, ribText

  local stateChip = makeChip(bar)
  stateChip:SetPoint("LEFT", ribbon, "RIGHT", 8, 0)
  setChip(stateChip, "READY", "accent", "accentInk")

  -- Detection found nothing to press. Practice still runs, and every shot it
  -- grades is one you cannot fire -- which reads as the addon being broken
  -- rather than as a keybind problem, so the header says which it is.
  local keysChip = makeChip(bar)
  keysChip:SetPoint("LEFT", stateChip, "RIGHT", 4, 0)
  setChip(keysChip, "NO KEYS", "bad", "ink")
  keysChip:EnableMouse(true)
  mouseFrames[#mouseFrames + 1] = keysChip
  keysChip.tipTitle = "No shot keys"
  keysChip.tipText = "Practice found no shot keys on your bars. Run /nock practice keys."
  keysChip:SetScript("OnEnter", tipEnter)
  keysChip:SetScript("OnLeave", tipLeave)
  keysChip:Hide()

  ------------------------------------------------------------------------
  -- ...and the right cluster, laid out right to left.
  ------------------------------------------------------------------------
  -- Right to left: Start (the one primary), Focus, Review (behind its flag),
  -- Lesson, the metronome box, the streak. Hosted, the workbench's title bar
  -- has the close and the rail has Leave, so the panel's own X only exists
  -- when it floats without a workbench.
  local leave
  if not host then
    leave = Nock.UI.CloseButton(bar, 22, function()
      local p = practice(); if p then p:Stop() end
    end)
    leave:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
  end

  -- The label is PaintStateChip's from here on, but that only runs on the first
  -- TICK: without a starting text the button shows up blank for the frame
  -- between Relayout showing the panel and the tick after it.
  local fight = Skin.Button(bar, "Start", "primary", BTN_W, BTN_H)
  if leave then fight:SetPoint("RIGHT", leave, "LEFT", -4, 0)
  else fight:SetPoint("RIGHT", bar, "RIGHT", 0, 0) end
  fight:SetScript("OnClick", function()
    local p = practice()
    if not p then return end
    if Nock.state.sim.fightOn then p:StopFight() else p:StartFight() end
  end)

  -- Focus: the stage alone on the HUD, without arming a fight -- for setting
  -- the strip's spot and width, or just clearing the screen. Start goes there
  -- by itself (practiceFocusOnStart).
  local focus = Skin.Button(bar, "Focus", "ghost", BTN_W, BTN_H)
  focus:SetPoint("RIGHT", fight, "LEFT", -6, 0)
  focus.tipTitle = "Focus"
  focus.tipText = "The stage alone on the HUD. Start goes there by itself; Esc or the head's WORKBENCH button comes back."
  local focusEnter, focusLeave = focus:GetScript("OnEnter"), focus:GetScript("OnLeave")
  focus:SetScript("OnEnter", function(b) if focusEnter then focusEnter(b) end; tipEnter(b) end)
  focus:SetScript("OnLeave", function(b) if focusLeave then focusLeave(b) end; tipLeave(b) end)
  focus:SetScript("OnClick", function()
    local cv = Nock:GetModule("PracticeConveyorView", true)
    local on = cv and cv.IsFocus and cv:IsFocus()
    Nock:SendMessage("NOCK_PRACTICE_FOCUS", not on)
  end)

  -- Expert: the window and the stage go, the combat log (and the weave log
  -- on a weave paper) stay -- the record of what you did, no plan on it.
  local expert = Skin.Button(bar, "Expert", "ghost", BTN_W, BTN_H)
  expert:SetPoint("RIGHT", focus, "LEFT", -6, 0)
  expert.tipTitle = "Expert"
  expert.tipText = "Only two panels: the combat log (movement, autos, casts, melee, cooldowns) and the weave log. No stage, no coach. Esc or the log's WORKBENCH button comes back."
  local expertEnter, expertLeave = expert:GetScript("OnEnter"), expert:GetScript("OnLeave")
  expert:SetScript("OnEnter", function(b) if expertEnter then expertEnter(b) end; tipEnter(b) end)
  expert:SetScript("OnLeave", function(b) if expertLeave then expertLeave(b) end; tipLeave(b) end)
  expert:SetScript("OnClick", function()
    local wb = Nock:GetModule("PracticeWorkbench", true)
    local on = wb and wb.IsExpert and wb:IsExpert()
    Nock:SendMessage("NOCK_PRACTICE_EXPERT", not on)
  end)

  local review = Skin.Button(bar, "Review", "ghost", BTN_W, BTN_H)
  -- A starting seat only: PaintReview owns Lesson's point from the first
  -- Relayout on, because with the review disabled (R8b) the Review button is
  -- not merely hidden, it is out of the row -- a hidden frame keeps its
  -- geometry, so anchoring through it would leave a button-wide hole.
  review:SetPoint("RIGHT", expert, "LEFT", -6, 0)
  review:SetScript("OnClick", function() Nock:SendMessage("NOCK_PRACTICE_TIMELINE_TOGGLE") end)

  local lesson = Skin.Button(bar, "Lesson", "ghost", BTN_W, BTN_H)
  lesson:SetPoint("RIGHT", review, "LEFT", -6, 0)

  -- WEAVE KEY (user, 2026-08-27): the prominent way in for a user who never
  -- ran the wizard. In the row only while Nock has no weave key AND the
  -- armed paper weaves or Grounded holds a bind (PaintLogSeat); opens the
  -- weave-key dialog (UI/Frame_PracticeKeys.lua).
  local weaveKey = Skin.Button(bar, "Set weave key", "primary")
  weaveKey.tipTitle = "Weave key"
  weaveKey.tipText = "The key every weave paper is graded on: set one, use Nock's default macros, or import the bind Grounded holds (the import replaces Nock's key and macros)."
  local wkEnter, wkLeave = weaveKey:GetScript("OnEnter"), weaveKey:GetScript("OnLeave")
  weaveKey:SetScript("OnEnter", function(b) if wkEnter then wkEnter(b) end; tipEnter(b) end)
  weaveKey:SetScript("OnLeave", function(b) if wkLeave then wkLeave(b) end; tipLeave(b) end)
  weaveKey:SetScript("OnClick", function() Nock:SendMessage("NOCK_PRACTICE_WEAVEKEY", true) end)
  weaveKey:Hide()
  f.weaveKeyBtn = weaveKey

  -- LOG: the weave log panel beside the stage in Focus (practiceWeaveLog),
  -- lit while on. Toggled here and on the Focus head, never in Options
  -- (user, 2026-08-26).
  local logBtn = Skin.Button(bar, "Log", "ghost", 44, BTN_H)
  logBtn:SetPoint("RIGHT", lesson, "LEFT", -6, 0)
  logBtn.tipTitle = "Weave log"
  logBtn.tipText = "In Focus: one row per weave - the hit, the legs, the re-arm cost, the verdict."
  local logEnter, logLeave = logBtn:GetScript("OnEnter"), logBtn:GetScript("OnLeave")
  logBtn:SetScript("OnEnter", function(b) if logEnter then logEnter(b) end; tipEnter(b) end)
  logBtn:SetScript("OnLeave", function(b) if logLeave then logLeave(b) end; tipLeave(b) end)
  logBtn:SetScript("OnClick", function()
    if not (Nock.db and Nock.db.profile) then return end
    Nock.db.profile.practiceWeaveLog = not (Nock.db.profile.practiceWeaveLog == true)
    PracticeView:PaintLog()
    local wl = Nock:GetModule("PracticeWeaveLogView", true)
    if wl and wl.Apply then wl:Apply() end
    local cv = Nock:GetModule("PracticeConveyorView", true)
    if cv and cv.PaintLogButton then cv:PaintLogButton() end
  end)
  -- The window itself lands in a later task; until it registers, the message
  -- simply reaches nobody (AceEvent's SendMessage on an unheard message is a
  -- no-op, not an error).
  lesson:SetScript("OnClick", function() Nock:SendMessage("NOCK_PRACTICE_LESSON_TOGGLE") end)

  -- Metronome: a checkbox in everything but the tick mark. A glyph would need a
  -- font that has one; a filled square needs nothing.
  local met = CreateFrame("Button", nil, bar)
  met:SetSize(MET_BOX, MET_BOX)
  met:SetPoint("RIGHT", logBtn, "LEFT", -12, 0)
  Skin.Surface(met, "ground", "line")
  local metFill = met:CreateTexture(nil, "ARTWORK")
  metFill:SetPoint("TOPLEFT", met, "TOPLEFT", 3, -3)
  metFill:SetPoint("BOTTOMRIGHT", met, "BOTTOMRIGHT", -3, 3)
  Skin.Paint(metFill, "accent", 1)
  met.tipTitle = "Metronome"
  met.tipText = "A gold tick on every auto release, a green one when the weave gap opens."
  met:SetScript("OnEnter", tipEnter)
  met:SetScript("OnLeave", tipLeave)
  met:SetScript("OnClick", function()
    if not (Nock.db and Nock.db.profile) then return end
    Nock.db.profile.practiceMetronome = not (profile("practiceMetronome", true) and true or false)
    PracticeView:PaintMet()
  end)

  -- Streak: the number right-aligned against a fixed caption, so a second digit
  -- grows leftwards into the header's slack instead of pushing the buttons.
  local streak = CreateFrame("Frame", nil, bar)
  streak:SetSize(STREAK_W, HEADER_H - 6)
  streak:SetPoint("RIGHT", met, "LEFT", -8, 0)
  local streakCap = streak:CreateFontString(nil, "OVERLAY")
  Skin.Font(streakCap, "mono", SUB_SIZE)
  streakCap:SetPoint("RIGHT", streak, "RIGHT", 0, -1)
  streakCap:SetText("STREAK")
  Skin.Text(streakCap, "ink3")
  -- ONE FontString for the number, milestones and all: the tiers are colour and
  -- shadow (see STREAK_HOT above), never a second layer.
  --
  -- The tier is re-painted from the header-font registry's own callback, not
  -- only from PaintStreak: SetFont clears a FontString's shadow, and the
  -- re-applies that matter here (a SharedMedia plugin registering "Numen" after
  -- us, PLAYER_ENTERING_WORLD) fire long after the last paint -- while the tier
  -- gate in PaintStreak means nothing will ask again until the number moves.
  local streakN = streak:CreateFontString(nil, "OVERLAY")
  streakN:SetPoint("RIGHT", streakCap, "LEFT", -5, 0)
  streakN:SetJustifyH("RIGHT"); streakN:SetWordWrap(false)
  Skin.Font(streakN, "display", Skin.SIZES.title)
  paintStreakTier(streakN)

  ------------------------------------------------------------------------
  -- The first-run hint bar, under the header and over the stage. It says the
  -- one thing the stage cannot say about itself -- which way the notes move and
  -- what the gold line is for -- and then goes away for good. Per character:
  -- the second hunter has a first run too.
  ------------------------------------------------------------------------
  local hintBar = CreateFrame("Frame", nil, f)
  hintBar:SetHeight(HINT_H)
  local hintBg = hintBar:CreateTexture(nil, "BACKGROUND")
  hintBg:SetAllPoints(hintBar)
  Skin.Paint(hintBg, "accent", 0.08)
  local hintRule = hintBar:CreateTexture(nil, "ARTWORK")
  hintRule:SetPoint("BOTTOMLEFT", hintBar, "BOTTOMLEFT", 0, 0)
  hintRule:SetPoint("BOTTOMRIGHT", hintBar, "BOTTOMRIGHT", 0, 0)
  hintRule:SetHeight(1)
  Skin.Paint(hintRule, "accent", 0.35)
  local hintTag = hintBar:CreateFontString(nil, "OVERLAY")
  Skin.Font(hintTag, "monoMedium", SUB_SIZE)
  hintTag:SetPoint("LEFT", hintBar, "LEFT", inset, 0)
  hintTag:SetText("FIRST RUN")
  Skin.Text(hintTag, "accent")
  local hintText = hintBar:CreateFontString(nil, "OVERLAY")
  Skin.Font(hintText, "ui", Skin.SIZES.small)
  hintText:SetPoint("LEFT", hintTag, "RIGHT", 8, 0)
  hintText:SetJustifyH("LEFT"); hintText:SetWordWrap(false)
  hintText:SetText(HINT_TEXT)
  Skin.Text(hintText, "ink2")
  -- ASCII: the display faces ship without the multiplication sign the mock uses.
  local hintX = CreateFrame("Button", nil, hintBar)
  hintX:SetSize(16, 16)
  hintX:SetPoint("RIGHT", hintBar, "RIGHT", -(inset - 4), 0)
  local hintXHL = hintX:CreateTexture(nil, "HIGHLIGHT")
  hintXHL:SetAllPoints(hintX)
  hintXHL:SetColorTexture(1, 1, 1, 0.10)
  local hintXFS = hintX:CreateFontString(nil, "OVERLAY")
  Skin.Font(hintXFS, "mono", SUB_SIZE)
  hintXFS:SetPoint("CENTER", hintX, "CENTER", 0, 0)
  hintXFS:SetText("X")
  Skin.Text(hintXFS, "ink3")
  hintX.tipTitle = "Dismiss"
  hintX.tipText = "Hide this hint for good on this character."
  hintX:SetScript("OnEnter", tipEnter)
  hintX:SetScript("OnLeave", tipLeave)
  hintX:SetScript("OnClick", function()
    local h = hints()
    if h then h.stage = true end
    PracticeView:Relayout()
  end)
  -- Anchored once the X exists, so the sentence is clipped by the dismiss button
  -- rather than drawn under it -- the line does not wrap, and a narrower panel
  -- (or a longer localised face) must lose its tail, not its X.
  hintText:SetPoint("RIGHT", hintX, "LEFT", -6, 0)
  hintBar:Hide()

  ------------------------------------------------------------------------
  -- Under the stage: the proc palette, one React slot per entry, desaturated
  -- while the proc is down, with a swipe that runs backwards for the remaining
  -- duration and forwards for a cooldown. Which tiles are SHOWN is the drill's
  -- call (ResolvePalette); the row is hidden outright when it allows none.
  ------------------------------------------------------------------------
  local palette = Palette.New(f, PAL_SIZE, PAL_GAP)
  local palRow = palette.frame
  palRow:SetSize(INNER_W, PAL_ROW_H)

  f.bar, f.grip, f.stateChip, f.keysChip = bar, grip, stateChip, keysChip
  f.scenBtn, f.scenName, f.scenSub, f.scenChev, f.ribbon = scenBtn, scenName, scenSub, scenChev, ribbon
  f.fight, f.review, f.lesson, f.leave, f.focus, f.logBtn = fight, review, lesson, leave, focus, logBtn
  f.expert = expert
  self._inset = inset
  f.met, f.metFill = met, metFill
  f.streakN, f.streak = streakN, streak
  f.hintBar = hintBar
  f.palRow, f.palette = palRow, palette
  f:Hide()
  self.frame = f
  self._paper = false
  self._palN = 0
  self._chipMode, self._chipSecs = nil, nil
  self._subNota, self._subLat = nil, nil
  self._streak, self._met = nil, nil
  self._streakTier = nil
  self._hadFight = false

  -- Toast: one line, re-anchored to the conveyor's hit line by the conveyor
  -- view (AnchorToast). We still own its text, colour and fade.
  local t = CreateFrame("Frame", "NockPracticeToast", UIParent)
  t:SetSize(200, 30)
  t:SetFrameStrata("HIGH")
  t:SetPoint("BOTTOM", Nock.parentFrame or UIParent, "TOP", 0, 8)
  local fs = t:CreateFontString(nil, "OVERLAY")
  fs:SetFont(Nock.UI.GetFont(), profile("practiceToastSize", 22), "THICKOUTLINE")
  fs:SetPoint("CENTER")
  t.text = fs
  t:Hide()
  self.toast = t
  self._toastVerdict = nil
end

function PracticeView:OnEnable()
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "Relayout")
  self:RegisterMessage("NOCK_PRACTICE_DOCK_CHANGED", "Relayout")
  -- No NOCK_LOCK_CHANGED: practice windows are tools and drag on the fight
  -- gate, not the global lock, so nothing in Relayout reads it.
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "Relayout")
  self:RegisterMessage("NOCK_WEAVEBIND_CHANGED", "Relayout")   -- the WEAVE KEY button follows the bind
  self:RegisterMessage("NOCK_PRACTICE_RESET_POS", "ResetPos")
  self:Relayout()
end

-- /nock practice reset: back to the default anchor, drop the saved position.
function PracticeView:ResetPos()
  local f = self.frame
  if not f then return end
  Nock.db.profile.practicePanelPos = nil
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
end

----------------------------------------------------------------------------
-- Relayout: everything that only changes on a message. Allocation here is
-- fine — this never runs from the tick.
----------------------------------------------------------------------------

-- Which palette tiles this drill lets you touch, seated left to right. A paper
-- drill pins its haste AND its Quick Shots roll, so nothing on the row would
-- answer a click: the row goes away rather than sitting there greyed — the
-- stage's PROCS lane is where a pinned drill's procs are read. A proc the
-- scenario HOLDS up for the whole fight is not yours to pop either. KC is an
-- indicator, so it rides along only when at least one real tile does.
function PracticeView:ResolvePalette(p)
  local n = self.frame.palette:Resolve(p, self._paper)
  self._palN = n
  return n
end

-- The ladder ribbon, off Practice:LadderItems(). Message-driven only: one
-- colour write per rung and one format on a scenario pick or a fight boundary, never
-- from the tick. No ladder module (or no rows) and the whole box goes away --
-- and the state chip closes the gap rather than sitting in a hole.
function PracticeView:PaintRibbon(p)
  local f = self.frame
  local rb = f.ribbon
  local rows = (p and p.LadderItems) and p:LadderItems() or nil
  local n = rows and #rows or 0
  f.stateChip:ClearAllPoints()
  -- Hosted, the ladder has its own rail page and the ribbon leaves the
  -- toolbar; the state chip takes the middle of the bar instead (user,
  -- 2026-08-26).
  if self._host then
    rb:Hide()
    -- Centred in the ROOM between the scenario block and the right cluster,
    -- not in the bar: a zero-height frame spanning that room is the anchor.
    local mid = f.mid
    if not mid then
      mid = CreateFrame("Frame", nil, f.bar)
      mid:SetHeight(1)
      mid:SetPoint("LEFT", f.scenBtn, "RIGHT", 0, 0)
      mid:SetPoint("RIGHT", f.streak, "LEFT", 0, 0)
      f.mid = mid
    end
    f.stateChip:SetPoint("CENTER", mid, "CENTER", 0, 0)
    return
  end
  if n == 0 then
    rb:Hide()
    f.stateChip:SetPoint("LEFT", f.scenBtn, "RIGHT", 8, 0)
    return
  end
  f.stateChip:SetPoint("LEFT", rb, "RIGHT", 8, 0)
  local cur, done = nil, 0
  for i = 1, RIB_DOTS do
    local t = rb.dots[i]
    local row = rows[i]
    if not row then
      t:Hide()
    else
      t:Show()
      local s = row.state
      if s == "done" then
        done = done + 1
        Skin.Paint(t, "accent", 1)
      elseif s == "cur" then
        cur = i
        Skin.Paint(t, "ink", 1)
      else
        Skin.Paint(t, "line", 1)
      end
    end
  end
  -- Every rung done leaves no `cur` row at all: the ribbon then reads n/n
  -- rather than falling back to the first rung.
  local at = cur or (done >= n and n) or (done + 1)
  if at > n then at = n end
  for i = 1, #RIB_GLOW do
    local g = rb.glow[i]
    if cur then
      local pad = RIB_GLOW[i][1]
      g:ClearAllPoints()
      g:SetSize(RIB_DOT + pad * 2, RIB_DOT + pad * 2)
      g:SetPoint("CENTER", rb.dots[cur], "CENTER", 0, 0)
      g:Show()
    else
      g:Hide()
    end
  end
  rb.text:SetText(("drill %d/%d"):format(at, n))
  rb:Show()
end

function PracticeView:Relayout()
  -- The panel takes the mouse only between fights (see OnInitialize).
  local mf = self._mouseFrames
  if mf then
    local on = Nock.state.sim.fightOn ~= true
    for i = 1, #mf do mf[i]:EnableMouse(on) end
  end
  local f = self.frame
  if not f then return end   -- OnInitialize failed: never cascade into the tick
  local st = Nock.state.sim
  if not st.active then
    if not self._host then f:Hide() end   -- hosted, the workbench shows and hides
    self.toast:Hide()
    self._hadFight = false
    return
  end
  f:Show()
  -- (the fight button's label is PaintStateChip's: it has to follow `pulled`,
  -- which turns over on a key press rather than on a relayout message. The
  -- chip gate is reset at the end of this function, so the next tick paints it.)
  local p = practice()

  -- The scenario name is the header's title now — the card is gone, and the
  -- name itself is the picker's button.
  local item = p and p.CurrentCatalogItem and p:CurrentCatalogItem() or nil
  -- ...unless a ladder drill is loaded, in which case the drill IS what you are
  -- running and its name is the one that means something ("Add the weave", not
  -- "5:5:1:1 3w"). The sub-line under it still states the notation and the
  -- latency, so nothing is lost by naming the drill here.
  local drill = (p and p.LadderDrillName) and p:LadderDrillName() or nil
  f.scenName:SetText(drill or (item and item.name) or profile("practiceScenario", "Clean French"))
  self:PaintRibbon(p)

  -- A paper drill pins its haste, so hand-popping a proc would fight the pin.
  -- Resolved here rather than in the tick — the answer walks the scenario
  -- catalog, and every path that can change it (scenario pick, fight
  -- start/stop) fires NOCK_PRACTICE_CHANGED.
  self._paper = (p and p.PaperDrill and p:PaperDrill()) or false
  local palN = self:ResolvePalette(p)

  -- The shot keys, as detection last left them. Message-driven like everything
  -- else here: DetectKeys runs on the paths that fire NOCK_PRACTICE_CHANGED.
  local keys = p and p.keys or nil
  local haveKey = false
  if keys then
    for i = 1, #SHOT_KEYS do
      local k = keys[SHOT_KEYS[i]]
      if k and k.key then
        haveKey = true
        break
      end
    end
  end
  if haveKey then f.keysChip:Hide() else f.keysChip:Show() end

  -- The Review button and Start's seat beside it: the review can be switched
  -- off (R8b), and this is the only place the row is laid out.
  self:PaintReview()
  -- The weave log's button, only on a paper that weaves (Practice:PaperWeaves).
  self._weaves = (p and p.PaperWeaves and p:PaperWeaves()) and true or false
  -- ...and the WEAVE KEY button, while Nock has no key to grade a weave on.
  -- ...whenever Grounded holds a bind (the import is always on offer --
  -- user, 2026-08-27), or a weave paper is armed with no key.
  local wk = (p and p.WeaveKeyState) and p:WeaveKeyState() or nil
  local need = wk and (wk.grounded or (not (wk.override and wk.enabled) and self._weaves)) and true or false
  self._needWeaveKey = need
  self._weaveKeyGrounded = need and wk.grounded or nil
  self:PaintLogSeat()

  -- The chips are tick-owned but their gates live here too: a fight boundary
  -- has to force one repaint.
  self._chipMode, self._chipSecs = nil, nil
  self._subNota, self._subLat = nil, nil
  self._streak, self._met = nil, nil
  self._streakTier = nil

  -- The first-run hint bar sits between the header and the stage, so the stage
  -- anchors to IT rather than to the bar while it is up. Same left/right insets
  -- as the bar, so the docked strip's own PAD still lines up under it.
  local hint = hints()
  local showHint = not (hint and hint.stage)
  -- Hosted, the stage runs the panel's whole width (no side inset): the
  -- anchor it hangs off has to span the panel, not the inset toolbar. A
  -- zero-height frame at the toolbar's foot does that.
  local head = f.bar
  if self._host then
    local seam = f.seam
    if not seam then
      seam = CreateFrame("Frame", nil, f)
      seam:SetHeight(1)
      f.seam = seam
    end
    seam:ClearAllPoints()
    seam:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEADER_H + 1)
    seam:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEADER_H + 1)
    head = seam
  end
  if showHint then
    f.hintBar:ClearAllPoints()
    f.hintBar:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -HINT_GAP)
    f.hintBar:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -HINT_GAP)
    f.hintBar:Show()
    head = f.hintBar
  else
    f.hintBar:Hide()
  end

  -- The conveyor strip: hosted under the header while docked, its own window
  -- otherwise. It reports the height the panel has to reserve for it.
  local cv = Nock:GetModule("PracticeConveyorView", true)
  local strip = cv and cv:Host(f, head, self._host ~= nil) or 0

  -- The palette hangs under whatever is above it: the stage while docked, the
  -- header (or the hint bar) when the stage is floating.
  local above = head
  if strip > 0 and cv then
    local cf = cv:GetFrame()
    if cf then above = cf end
  end
  f.palRow:ClearAllPoints()
  -- Under the flush stage the tiles take the toolbar's inset; under the bar
  -- (or the hint) they already have it.
  local palX = (self._host and above ~= f.bar and above ~= f.hintBar) and (self._inset or TOOL_INSET) or 0
  f.palRow:SetPoint("TOPLEFT", above, "BOTTOMLEFT", palX, -PAL_TOP_GAP)
  if palN > 0 then f.palRow:Show() else f.palRow:Hide() end

  f:SetHeight(HEADER_H
    + (showHint and (HINT_GAP + HINT_H) or 0)
    + strip
    + (palN > 0 and (PAL_TOP_GAP + PAL_ROW_H + (self._host and 6 or 0)) or 0)
    + PAD)
  -- The Focus head and the combat log's read the scenario name beside their chips.
  local fh = cv and cv.FocusHead and cv:FocusHead()
  if fh and fh.name then fh.name:SetText(f.scenName:GetText() or "") end
  local xh = self:ExpertHead()
  if xh and xh.name then xh.name:SetText(f.scenName:GetText() or "") end
  -- The workbench sizes itself to the panel it hosts.
  if self._host then Nock:SendMessage("NOCK_PRACTICE_LAYOUT") end
end

----------------------------------------------------------------------------
-- Tick
----------------------------------------------------------------------------

-- The proc palette, once per tick. Every texture/text mutation is diffed inside
-- PaintReactSlot, and the cooldown frame is touched only when its (start,
-- duration, direction) signature actually moves — SetCooldown restarts the
-- swipe, so calling it every tick would freeze it at full. The `item` tables
-- are built once in OnInitialize: nothing here allocates.
function PracticeView:PaintPalette(p, now)
  if (self._palN or 0) == 0 then return end
  self.frame.palette:Paint(p, now)
end

-- State chip: READY (green) before the first fight, ARMED (gold) once Start is
-- pressed and until the first key, FIGHT m:ss (red) from that press on, FIGHT
-- OVER (gold) after. Text and fill are written only when the mode or the whole
-- second moves. The fight BUTTON's label rides along on the same gate — Start /
-- Cancel / Stop — because `pulled` turns over on a key press, which fires no
-- NOCK_PRACTICE_CHANGED for Relayout to catch.
function PracticeView:PaintStateChip(st, now, p)
  local mode, secs
  -- Only a PULLED fight ever happened: an armed one that is cancelled before
  -- the first press leaves the chip on READY, not FIGHT OVER.
  if st.fightOn and st.pulled then self._hadFight = true end
  if st.fightOn and not st.pulled then
    -- Armed: the clock has not started, so there is no m:ss to paint yet.
    mode, secs = 4, 0
  elseif st.fightOn then
    mode = 2
    -- A CAPPED fight counts DOWN (R6c). A teaching drill is a timed attempt and
    -- "0:22 left" is the number that means something during one; elapsed time
    -- only tells you how long you have been at it. Chip text and nothing else --
    -- every other surface still reads the fight's own elapsed clock.
    local len = (p and p.FightLen) and p:FightLen() or nil
    if len and len > 0 then
      secs = math.ceil(len - (now - st.t0))
      if secs > len then secs = math.floor(len) end
    else
      secs = math.floor(now - st.t0)
    end
    if secs < 0 then secs = 0 end
  elseif p and p._replay then
    mode = 5
    secs = math.floor((p._replay.at - p._replay.t0) * 10 + 0.5)   -- tenths
  else
    mode = self._hadFight and 3 or 1
    secs = 0
  end
  if mode == self._chipMode and secs == self._chipSecs then return end
  local modeChanged = (mode ~= self._chipMode)
  self._chipMode, self._chipSecs = mode, secs
  local cv = self._cv or Nock:GetModule("PracticeConveyorView", true)
  local fh = cv and cv.FocusHead and cv:FocusHead()
  local xh = self:ExpertHead()
  if modeChanged then
    -- Nothing has been pressed yet, so there is no fight to stop — only one to
    -- call off.
    local label = mode == 4 and "Cancel" or (mode == 2 and "Stop" or "Start")
    Skin.SetButtonText(self.frame.fight, label, BTN_W)
    Skin.ButtonKind(self.frame.fight, mode == 2 and "danger" or "primary")
    if fh then Skin.SetButtonText(fh.stop, label:upper()) end
    if xh then
      Skin.SetButtonText(xh.stop, label:upper())
      Skin.ButtonKind(xh.stop, mode == 2 and "danger" or "primary")
    end
  end
  -- The same words on the panel's chip and on the Focus head's.
  local text, fill, ink
  if mode == 4 then
    text, fill, ink = "ARMED", "wait", "accentInk"
  elseif mode == 2 then
    text, fill, ink = ("FIGHT %d:%02d"):format(math.floor(secs / 60), secs % 60), "bad", "ink"
  elseif mode == 5 then
    text, fill, ink = ("REPLAY %d.%ds"):format(math.floor(secs / 10), secs % 10), "wait", "accentInk"
  elseif mode == 3 then
    text, fill, ink = "FIGHT OVER", "surface2", "ink2"
  else
    text, fill, ink = "READY", "accent", "accentInk"
  end
  setChip(self.frame.stateChip, text, fill, ink)
  if fh then setChip(fh.chip, text, fill, ink) end
  if xh then setChip(xh.chip, text, fill, ink) end
end

-- The combat log's head (Expert mode), painted here beside the panel's own
-- chip and the Focus head's, so the three never disagree.
function PracticeView:ExpertHead()
  local cl = Nock:GetModule("PracticeCombatLogView", true)
  return cl and cl.Head and cl:Head() or nil
end

-- The line under the scenario name: the drill's own facts. Rebuilt only when
-- one of its two parts moves.
function PracticeView:PaintSub(st, p)
  local cfg = p and p.cfg
  local lat = cfg and math.floor((cfg.latency or 0) * 1000 + 0.5) or nil
  local nota = st.notation or "-"
  if nota == self._subNota and lat == self._subLat then return end
  self._subNota, self._subLat = nota, lat
  if lat then
    self.frame.scenSub:SetText(("%s | lat %d ms"):format(nota, lat))
  else
    self.frame.scenSub:SetText(nota)
  end
end

-- The streak, off the stage's own live table (Practice:Lookahead publishes it,
-- the conveyor's tick fills it) — 0 between fights.
--
-- Which is why a FINISHED fight is left alone: View:Streak() drops to 0 the
-- moment `fightOn` goes false, and watching the number you just earned reset
-- itself to zero while the chip says FIGHT OVER is the opposite of the point.
-- The last painted value stands until Relayout clears the gate for the next
-- arm. `_hadFight` is the same "a fight actually happened" flag the state chip
-- runs on, so the two can never disagree about which reading is showing.
function PracticeView:PaintStreak(st)
  if st and not st.fightOn and self._hadFight then return end
  local cv = self._cv
  if not cv then
    -- Left nil on a miss, never false: the module may simply not be up yet, and
    -- a cached false would never look again.
    cv = Nock:GetModule("PracticeConveyorView", true)
    self._cv = cv
  end
  local n = 0
  if cv and cv.Streak then n = (cv:Streak()) or 0 end
  if n == self._streak then return end
  self._streak = n
  local fs = self.frame.streakN
  fs:SetText(("%d"):format(n))
  local fh = cv and cv.FocusHead and cv:FocusHead()
  if fh then fh.streak:SetText(("streak %d"):format(n)) end
  local xh = self:ExpertHead()
  if xh then xh.streak:SetText(("streak %d"):format(n)) end
  -- Milestones. The TIER carries every look the number can wear -- 0 dim,
  -- 1 gold, 2 good-green, 3 a brighter green over a coloured shadow -- so ONE
  -- gate covers all of it, and a streak climbing 6..7..8 writes the string and
  -- touches nothing else. (A tier that only counted the milestones would miss
  -- the drop from 3 back to 0: same tier, different colour.)
  local tier
  if n >= STREAK_GLOW then tier = 3
  elseif n >= STREAK_GREEN then tier = 2
  elseif n > 0 then tier = 1
  else tier = 0 end
  if tier == self._streakTier then return end
  self._streakTier = tier
  -- The colour and the halo, and the whole of it: no second FontString to fall
  -- out of line. Same call the font registry makes after a re-apply.
  paintStreakTier(fs)
end

-- The Review button, and the seat of the button beside it. The fight review is
-- off while the practice engine is tuned (R8b, `practiceReviewEnabled`), and a
-- button that answers "disabled" is worse than no button — so it leaves the row
-- entirely and Start closes the gap. A hidden frame keeps its geometry, which is
-- why Start is re-anchored rather than left pointing through it.
--
-- Message-driven (Relayout), not per tick: the flag is an Options checkbox, and
-- Options fires NOCK_VISUALS_CHANGED. Diffed, so the common relayout re-seats
-- nothing.
function PracticeView:PaintReview()
  local f = self.frame
  if not f then return end
  local on = profile("practiceReviewEnabled", false) and true or false
  if on == self._review then return end
  self._review = on
  f.lesson:ClearAllPoints()
  if on then
    f.review:Show()
    f.lesson:SetPoint("RIGHT", f.review, "LEFT", -6, 0)
  else
    f.review:Hide()
    f.lesson:SetPoint("RIGHT", f.expert or f.focus, "LEFT", -6, 0)
  end
end

-- The metronome box. Read from the profile every tick rather than only on the
-- click, so the Options checkbox and the header can never disagree — it is one
-- table lookup behind a boolean diff.
-- The Log button's state, from the setting (the Focus head writes it too).
function PracticeView:PaintLog()
  local f = self.frame
  if not (f and f.logBtn) then return end
  local on = profile("practiceWeaveLog", false) and true or false
  if on == self._logOn then return end
  self._logOn = on
  Skin.ButtonKind(f.logBtn, on and "primary" or "ghost")
end

-- The Log button is in the row only on a weave paper; the metronome box
-- re-anchors past it either way (a hidden frame keeps its geometry).
function PracticeView:PaintLogSeat()
  local f = self.frame
  if not (f and f.logBtn) then return end
  f.met:ClearAllPoints()
  local left = f.lesson
  if self._weaves then
    f.logBtn:Show()
    left = f.logBtn
  else
    f.logBtn:Hide()
  end
  -- The WEAVE KEY button sits past the log's seat, and the metronome past it.
  local wk = f.weaveKeyBtn
  if wk then
    if self._needWeaveKey then
      Skin.SetButtonText(wk, self._weaveKeyGrounded and "Import weave key" or "Set weave key")
      wk:ClearAllPoints()
      wk:SetPoint("RIGHT", left, "LEFT", -6, 0)
      wk:Show()
      left = wk
    else
      wk:Hide()
    end
  end
  f.met:SetPoint("RIGHT", left, "LEFT", -12, 0)
end

function PracticeView:PaintMet()
  local f = self.frame
  if not f then return end
  local on = profile("practiceMetronome", true) and true or false
  if on == self._met then return end
  self._met = on
  if on then f.metFill:Show() else f.metFill:Hide() end
end

function PracticeView:Refresh(state)
  local st = state.sim
  if not st.active or not self.frame then return end
  local now = GetTime()
  local p = practice()
  self:PaintStateChip(st, now, p)
  self:PaintSub(st, p)
  self:PaintStreak(st)
  self:PaintMet()
  self:PaintLog()
  self:PaintPalette(p, now)

  local v = st.lastVerdict
  if v and v ~= self._toastVerdict then
    self._toastVerdict = v
    if profile("practiceToast", true) then
      local col = COLOR[v.code] or { 1, 1, 1 }
      self.toast.text:SetText(v.text)
      self.toast.text:SetTextColor(col[1], col[2], col[3], 1)
      self.toast:SetAlpha(1)
      self.toast:Show()
      self._toastAt = now
    end
  end
  if self.toast:IsShown() then
    local dur = profile("practiceToastSec", C.PRACTICE.TOAST_SEC)
    local age = now - (self._toastAt or now)
    if age >= dur then self.toast:Hide()
    elseif age > dur * 0.6 then self.toast:SetAlpha(1 - (age - dur * 0.6) / (dur * 0.4)) end
  end
end
