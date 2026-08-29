-- UI/Frame_PracticeLesson.lua
-- The lesson: one cycle drawn twice with its callouts, five narration steps and a slow-motion cursor. The workbench's Lesson PAGE (shell step 4); a floating window with the drill ladder beside it only without one.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("PracticeLessonView", "AceEvent-3.0")
local C = Nock.Constants
local Skin = Nock.Skin

local PAD = C.DIM.OUTER_PAD
local HEADER_FONT = "Numen"
-- The page: the toolbar's inset, the room over the headline.
local MARGIN = 8
local TOP_PAD = 10
local PAGE_HEAD_H = 28
-- The page's bar spans the paper's WHOLE PERIOD (the floating window keeps
-- the two-cycle bar): the caption under it names what the period holds.
local PER_CAP_H = 18
local PER_NOTE_H = Skin.BANNER_H + 4   -- the "costs by design" banner under the caption
-- The seconds axis under the page's bar (a 2:5 at a fast bow is mostly empty
-- cycles, and without a scale the gaps read as a bug -- user, 2026-08-26),
-- and how far the paper's pinned eWS may sit from the player's own before the
-- caption says so.
local AXIS_H = 16
local EWS_FAR = 0.25
local AUTO_ONLY_MIN_W = 56    -- a cast-less cycle wide enough to say so

----------------------------------------------------------------------------
-- Geometry. The window is fixed: everything it draws is derived from ONE
-- cycle, so there is nothing for a width setting to reveal.
----------------------------------------------------------------------------
local WIDTH      = 720
local SIDE_W     = 250        -- the ladder panel, flush to the right edge
local TITLE_H    = 26
local GAP        = 6
local MAIN_W     = WIDTH - SIDE_W - GAP - PAD          -- 460

local HEAD_H     = 22         -- "The auto shot is the clock..."
local CO_ROW     = 15         -- one callout row
local CO_TOP     = CO_ROW * 3 + 2  -- three rows above the bar
local CO_BOT     = CO_ROW * 2 + 2
local LANE_H     = 30
local LANES      = { "shots", "weave", "clip" }
local LANE_ROW   = { shots = 0, weave = 1, clip = 2 }
local BAR_H      = LANE_H * 3 + 4
local LABEL_W    = 50         -- the lane captions, left of the plot
local PLOT_PAD   = 8
local SEG_H      = 18
local ICON_W     = 14         -- the spell icon inside a plate (period bar)
local TICK_W     = 3          -- the release tick's drawn width
local MIN_SEG_W  = 2
local STEP_H     = 38
local NARR_GAP   = 8
local NARR_H     = STEP_H * 5
-- THE DROP (user, 2026-08-27, off the "Weave Drop" concept): under the bar
-- the page splits 70/30 -- the narration left, a falling-notes lane right.
-- Columns are the paper's abilities, notes fall toward a row of keycaps that
-- are the real binds (Practice:RowKey); casts are tall, instants short, a
-- weave an amber run-up, the auto column carries each release tick over its
-- wind-up band. Shares the Play slowly clock: y(t) is the bar's x(t) upright.
local SPLIT_GAP  = 12
local DROP_FRAC  = 0.30
local DROP_PAD   = 6
local DROP_KEY_H = 26         -- the keycap row
local DROP_LOOK  = 4.0        -- seconds of lookahead above the strike line
local DROP_PAST  = 0.6        -- seconds kept below it
local DROP_NEAR  = 0.6        -- the keycap borders in the ability's colour this close
local DROP_LIT   = 0.15       -- ...and lights for this long after the press moment

local SIDE_HEAD_H = 20
-- Round 5b: eleven rungs on three tracks (TURRET / WEAVE / MASTERY). The rows
-- lost six pixels each to pay for the three section headers; the window pays
-- the rest in height.
local LADDER_ROWS = 11
local LADDER_SECTIONS = 3     -- the header pool: one per track, and no track may add a fourth
local LADDER_H    = 32
local SECTION_H   = 15
local LADDER_TOP  = SIDE_HEAD_H + 6
local LADDER_BODY = LADDER_ROWS * LADDER_H + LADDER_SECTIONS * SECTION_H
local DRILL_BTN_H = 26

-- The main column and the side column are independent heights; the window is
-- the taller of the two, so neither can be clipped by the other's growth.
local SIDE_H = LADDER_TOP + LADDER_BODY + 10 + DRILL_BTN_H + 6
local MAIN_COL_H = HEAD_H + 4 + CO_TOP + BAR_H + CO_BOT + NARR_GAP + NARR_H
local MAIN_H = (SIDE_H > MAIN_COL_H) and SIDE_H or MAIN_COL_H
local FRAME_H = PAD + TITLE_H + GAP + MAIN_H + PAD

-- Slow motion: the bar plays at a quarter of real time, over two cycles (the
-- page's period bar: over the whole period).
local PLAY_DIV  = 4
local PLAY_HOLD = 1.0         -- the lit step stays up this long after the end
-- The press cues while it plays, the stage's own (UI/Frame_PracticeConveyor):
-- the NEXT plate bright with a white edge and a `NEXT <key>` chip over it,
-- the plates behind the cursor faded, the rest dimmed, and a white flash on
-- a plate as the cursor reaches it.
local PAST_ALPHA, DIM_ALPHA = 0.4, 0.6
local FLASH_LIFE, FLASH_ALPHA = 0.3, 0.5
local CHIP_SIZE, CHIP_PAD_X, CHIP_ROW_H = 9, 5, 12
local ROW_OF_SYM = { s = "s", m = "m", A = "A", w = "w", r = "w" }

-- Type scale (D2b): the window title 15, body and narration 14, the small
-- captions -- lane names, callouts, segment labels, the ladder's sub lines -- 11.
local TITLE_SIZE = 15
local TEXT_SIZE  = 14
local SMALL_SIZE = 11
local CHIP_H     = 18
local CHIP_PAD   = 14

-- The skin's tokens (UI/Skin.lua): the accent where the mock had gold.
local GOLD      = Skin.COLORS.accent
local GOLD_2    = Skin.COLORS.accent
local GOOD      = Skin.COLORS.good
local INK       = Skin.COLORS.ink
local INK_DIM   = Skin.COLORS.ink2
local INK_FAINT = Skin.COLORS.ink3
local GROUND    = { 0, 0, 0, 1 }
local BORDER    = { Skin.COLORS.line[1], Skin.COLORS.line[2], Skin.COLORS.line[3], 1 }
local CHIP_BG   = { 0.09, 0.10, 0.13, 0.9 }
local SIDE_BG   = { 0.07, 0.07, 0.09, 0.9 }
local STEP_BG   = { Skin.COLORS.surface2[1], Skin.COLORS.surface2[2], Skin.COLORS.surface2[3], 1 }
local GRID      = { Skin.COLORS.line[1], Skin.COLORS.line[2], Skin.COLORS.line[3], 1 }

local T                       -- Nock.PracticeTimeline (the colour table)
local L                       -- Nock.PracticeLesson

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function practice() return Nock:GetModule("Practice", true) end
local function workbench() return Nock:GetModule("PracticeWorkbench", true) end

-- A segment's colour, in T.COLORS' own vocabulary so the lesson and the
-- conveyor never drift apart on what a Steady looks like.
local function segColor(s)
  local k = s.kind
  if k == "gap" then return T.COLORS.good end
  if k == "clip" then return T.COLORS.bad end
  if k == "windup" then return T.COLORS.g end
  return T.COLORS[s.sym] or T.COLORS.a
end

----------------------------------------------------------------------------
-- Pools. The bar is repainted on a PLAN change and on nothing else -- the
-- cursor moves by re-anchoring one texture -- so nothing here runs per tick.
----------------------------------------------------------------------------

local function newPool() return { n = 0, max = 0 } end
local function poolReset(p) p.n = 0 end
local function poolHideRest(p) for i = p.n + 1, p.max do p[i]:Hide() end end

local function poolTexture(pool, parent, layer)
  local n = pool.n + 1
  pool.n = n
  local t = pool[n]
  if not t then
    t = parent:CreateTexture(nil, layer or "ARTWORK")
    pool[n] = t
    pool.max = n
  end
  t:ClearAllPoints()
  t:SetAlpha(1)
  t:Show()
  return t
end

local function poolText(pool, parent, size)
  local n = pool.n + 1
  pool.n = n
  local fs = pool[n]
  if not fs then
    fs = parent:CreateFontString(nil, "OVERLAY")
    Skin.Font(fs, "ui", size or TEXT_SIZE)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    pool[n] = fs
    pool.max = n
  end
  fs:ClearAllPoints()
  fs:SetAlpha(1)
  fs:Show()
  return fs
end

----------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------

local function makeChip(parent)
  return Skin.Chip(parent)
end

-- ONE load path for the ladder, whichever surface asked: the `Drill this`
-- button under the rows, and (Round 4) a click on a row itself. `id` nil means
-- "the rung the ladder is pointing at", which is what the button has always
-- meant.
local function loadDrill(id)
  if id == nil then
    local items = View._ladder
    local pick = nil
    for i = 1, (items and #items or 0) do
      if items[i].state == "cur" then pick = items[i]; break end
    end
    if not pick then pick = items and items[1] end
    if not pick then return end
    id = pick.id or pick.name
  end
  Nock:SendMessage("NOCK_PRACTICE_LADDER_DRILL", id)
end

local function ladderDrill()
  loadDrill(nil)
end

-- ONE OnClick for all six rows, not a closure per rebuild: SetLadder runs on
-- every practice message, and a fresh function per row per repaint is garbage
-- for nothing. The row carries its own `id` in a field instead.
local function ladderRowClick(row)
  if row and row.id then loadDrill(row.id) end
end

function View:OnInitialize()
  local wb = workbench()
  local host = wb and wb.PageFrame and wb:PageFrame() or nil
  self._host = host
  if host then return self:InitPage(wb, host) end
  local f = CreateFrame("Frame", "NockPracticeLesson", UIParent, "BackdropTemplate")
  f:SetSize(WIDTH, FRAME_H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  Nock.UI.RegisterPanelBackground(f)
  -- The practice scale (Options -> Practice), top-level frame only.
  Nock.UI.RegisterPracticeScale(f)
  local pos = profile("practiceLessonPos", nil)
  if pos then f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
  else f:SetPoint("CENTER", UIParent, "CENTER", 0, 60) end

  ------------------------------------------------------------------------
  -- Title bar. Practice windows are tools: they drag whenever no fight runs,
  -- regardless of the global lock, and never during one (the scenarios
  -- window's rule, and the reason Nock.IsLocked is not consulted here).
  ------------------------------------------------------------------------
  -- Hoisted out of the title bar's own scripts: any child that takes the mouse
  -- SWALLOWS the drag that would otherwise reach the window, so every one of
  -- them carries these two (the review window's grade tile does the same).
  local function dragStart()
    if Nock.state.sim.fightOn then return end
    f:StartMoving()
  end
  local function dragStop()
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    Nock.db.profile.practiceLessonPos = { point = point, relPoint = relPoint, x = x, y = y }
  end

  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD)
  bar:SetHeight(TITLE_H)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", dragStart)
  bar:SetScript("OnDragStop", dragStop)

  for i = 1, 3 do
    local t = bar:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(0.5, 0.5, 0.54, 0.7)
    t:SetSize(1, 12)
    t:SetPoint("LEFT", bar, "LEFT", (i - 1) * 3, 0)
  end

  local title = bar:CreateFontString(nil, "OVERLAY")
  title:SetPoint("LEFT", bar, "LEFT", 16, 0)
  -- Font before text: SetText on a FontString with no font raises "Font not set".
  Nock.UI.RegisterHeaderFontString(title, HEADER_FONT, TITLE_SIZE, "OUTLINE")
  title:SetText("LESSON")
  title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

  local chip = makeChip(bar)
  chip:SetPoint("LEFT", title, "RIGHT", 10, 0)

  local close = Nock.UI.CloseButton(bar, 26, function() View:Toggle(false) end)
  close:SetPoint("RIGHT", bar, "RIGHT", 0, 0)

  local play = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
  play:SetSize(104, 22)
  play:SetPoint("RIGHT", close, "LEFT", -4, 0)
  play:SetText("Play slowly")
  play:SetScript("OnClick", function() View:TogglePlay() end)

  ------------------------------------------------------------------------
  -- Main column: headline, the bar with its callout bands, the narration.
  ------------------------------------------------------------------------
  local mainTop = PAD + TITLE_H + GAP

  local head = f:CreateFontString(nil, "OVERLAY")
  head:SetFont(Nock.UI.GetFont(), TEXT_SIZE + 2, "OUTLINE")
  head:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -mainTop)
  head:SetWidth(MAIN_W)
  head:SetJustifyH("LEFT")
  head:SetWordWrap(false)
  head:SetTextColor(INK[1], INK[2], INK[3])
  head:SetText("The auto shot is the clock. Everything else fits around it.")

  local barF = CreateFrame("Frame", nil, f, "BackdropTemplate")
  barF:SetSize(MAIN_W, BAR_H)
  barF:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(mainTop + HEAD_H + 4 + CO_TOP))
  Nock.UI.ApplyBackdrop(barF, GROUND, BORDER)

  -- Lane captions. Fixed: the three lanes never change.
  for i = 1, #LANES do
    local fs = barF:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Nock.UI.GetFont(), SMALL_SIZE, "OUTLINE")
    fs:SetPoint("TOPLEFT", barF, "TOPLEFT", 6, -(2 + (i - 1) * LANE_H + 4))
    fs:SetText(LANES[i]:upper())
    fs:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
  end

  -- The cursor. One texture, re-anchored from Refresh while playing.
  local cursor = barF:CreateTexture(nil, "OVERLAY")
  cursor:SetColorTexture(GOLD_2[1], GOLD_2[2], GOLD_2[3], 1)
  -- Sized once, anchored by its TOPLEFT only: the play loop then moves it with
  -- ONE SetPoint per tick instead of two.
  cursor:SetSize(2, BAR_H - 4)
  cursor:SetPoint("TOPLEFT", barF, "TOPLEFT", 0, -2)
  cursor:Hide()

  -- Narration: five rows, built once. Each is a filled plate (hidden until the
  -- row is lit), a number and a wrapping sentence.
  local narrTop = mainTop + HEAD_H + 4 + CO_TOP + BAR_H + CO_BOT + NARR_GAP
  local steps = {}
  for i = 1, 5 do
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(MAIN_W, STEP_H - 2)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(narrTop + (i - 1) * STEP_H))
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(STEP_BG[1], STEP_BG[2], STEP_BG[3], 1)
    bg:Hide()
    local num = row:CreateFontString(nil, "OVERLAY")
    num:SetPoint("TOPLEFT", row, "TOPLEFT", 5, -2)
    Nock.UI.RegisterHeaderFontString(num, HEADER_FONT, TEXT_SIZE + 1, "OUTLINE")
    num:SetText(tostring(i))
    num:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
    local txt = row:CreateFontString(nil, "OVERLAY")
    txt:SetFont(Nock.UI.GetFont(), TEXT_SIZE, "OUTLINE")
    txt:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -2)
    txt:SetWidth(MAIN_W - 32)
    txt:SetJustifyH("LEFT")
    txt:SetWordWrap(true)
    txt:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])
    row.bg, row.num, row.text = bg, num, txt
    steps[i] = row
  end

  ------------------------------------------------------------------------
  -- Side column: the drill ladder. Task 6 fills it; until then it carries the
  -- six drills the plan names, with no progress claimed.
  ------------------------------------------------------------------------
  local side = CreateFrame("Frame", nil, f, "BackdropTemplate")
  side:SetPoint("TOPLEFT", f, "TOPLEFT", WIDTH - SIDE_W, -(PAD + TITLE_H + GAP))
  side:SetSize(SIDE_W - PAD, MAIN_H)
  Nock.UI.ApplyBackdrop(side, SIDE_BG, BORDER)

  local sideHead = side:CreateFontString(nil, "OVERLAY")
  sideHead:SetPoint("TOPLEFT", side, "TOPLEFT", 9, -6)
  Nock.UI.RegisterHeaderFontString(sideHead, HEADER_FONT, TEXT_SIZE - 1, "OUTLINE")
  -- The rungs are never locked (user, 2026-08-24): every row loads on a click,
  -- and the header says so, because a dark dot on a quiet row read as "locked".
  sideHead:SetText("DRILL LADDER - click a rung to load it")
  sideHead:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

  -- The track headers (TURRET / WEAVE / MASTERY). Pooled and positioned by
  -- SetLadder, because which row a track starts on is DATA -- the view is told
  -- by `item.section` and never works it out for itself.
  local sections = {}
  for i = 1, LADDER_SECTIONS do
    local fs = side:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Nock.UI.GetFont(), SMALL_SIZE, "OUTLINE")
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    fs:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
    fs:Hide()
    sections[i] = fs
  end

  local rows = {}
  for i = 1, LADDER_ROWS do
    -- A Button, not a Frame: clicking a rung loads that drill, down the same
    -- path `Drill this` takes (Round 4). The HIGHLIGHT layer is the client's
    -- own hover -- no OnEnter/OnLeave bookkeeping, and it costs nothing when
    -- the pointer is elsewhere.
    local row = CreateFrame("Button", nil, side, "BackdropTemplate")
    row:SetSize(SIDE_W - PAD - 12, LADDER_H - 2)
    -- Y is SetLadder's: a row's offset depends on how many track headers sit
    -- above it, which only the data knows.
    row:SetPoint("TOPLEFT", side, "TOPLEFT", 6, -LADDER_TOP)
    Nock.UI.ApplyBackdrop(row, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)
    row:SetScript("OnClick", ladderRowClick)
    -- A Button takes the mouse, and six of them across the side panel is most
    -- of the window's right-hand column: without these the ladder eats the drag
    -- and the window can only be moved by its title bar.
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", dragStart)
    row:SetScript("OnDragStop", dragStop)
    local dot = row:CreateTexture(nil, "ARTWORK")
    dot:SetSize(10, 10)
    dot:SetPoint("LEFT", row, "LEFT", 6, 0)
    local name = row:CreateFontString(nil, "OVERLAY")
    name:SetFont(Nock.UI.GetFont(), TEXT_SIZE - 1, "OUTLINE")
    name:SetPoint("TOPLEFT", row, "TOPLEFT", 22, -4)
    name:SetJustifyH("LEFT"); name:SetWordWrap(false)
    local sub = row:CreateFontString(nil, "OVERLAY")
    sub:SetFont(Nock.UI.GetFont(), SMALL_SIZE, "OUTLINE")
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    sub:SetJustifyH("LEFT"); sub:SetWordWrap(false)
    sub:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
    local pass = row:CreateFontString(nil, "OVERLAY")
    pass:SetFont(Nock.UI.GetFont(), SMALL_SIZE, "OUTLINE")
    pass:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    pass:SetJustifyH("RIGHT"); pass:SetWordWrap(false)
    pass:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
    -- The name has to yield to the pass text, or a long drill name walks under it.
    name:SetPoint("RIGHT", pass, "LEFT", -4, 0)
    sub:SetPoint("RIGHT", pass, "LEFT", -4, 0)
    row.dot, row.name, row.sub, row.pass = dot, name, sub, pass
    rows[i] = row
  end

  local drill = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
  drill:SetSize(SIDE_W - PAD - 12, DRILL_BTN_H)
  drill:SetPoint("TOPLEFT", side, "TOPLEFT", 6, -(LADDER_TOP + LADDER_BODY + 6))
  drill:SetText("Drill this")
  drill:SetScript("OnClick", ladderDrill)

  self.frame, self.bar, self.chip, self.barF, self.cursor = f, bar, chip, barF, cursor
  self.playBtn, self.stepRows, self.ladderRows = play, steps, rows
  self.ladderSections, self.ladderSide = sections, side
  self.segTex, self.segText, self.segIcon = newPool(), newPool(), newPool()
  self.coText, self.coLead = newPool(), newPool()
  self._plotX = LABEL_W
  self._plotW = MAIN_W - LABEL_W - PLOT_PAD
  self._lit = 0
  self._playing = false
  self:SetLadder(nil)
  f:Hide()
end

-- THE PAGE. The main column alone, the page's whole width: a headline row
-- (the sentence, the notation chip, Play slowly), the bar with its callout
-- bands, the five narration rows. The ladder has its own page.
function View:InitPage(wb, host)
  local f = CreateFrame("Frame", "NockPracticeLesson", host)
  f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
  f:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
  local mainW = ((wb.PageWidth and wb:PageWidth()) or 960) - MARGIN * 2
  self._mainW = mainW

  local head = f:CreateFontString(nil, "OVERLAY")
  Skin.Font(head, "display", Skin.SIZES.h2)
  head:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN, -TOP_PAD)
  head:SetJustifyH("LEFT")
  head:SetWordWrap(false)
  Skin.Text(head, "ink")
  head:SetText("The auto shot is the clock. Everything else fits around it.")

  local chip = makeChip(f)
  chip:SetPoint("LEFT", head, "RIGHT", 12, -1)

  local play = Skin.Button(f, "Play slowly", "ghost", 104)
  play:SetPoint("TOPRIGHT", f, "TOPRIGHT", -MARGIN, -(TOP_PAD + 2))
  play:SetScript("OnClick", function() View:TogglePlay(PLAY_DIV) end)
  -- ...and at the real tempo (user, 2026-08-27): the bar and the drop both
  -- walk at 1x, the way the rotation actually plays.
  local playFast = Skin.Button(f, "Play", "ghost", 64)
  playFast:SetPoint("RIGHT", play, "LEFT", -8, 0)
  playFast:SetScript("OnClick", function() View:TogglePlay(1) end)
  self.playFastBtn = playFast

  -- The ghost hunter (Practice:ToggleDemo): a ghost that presses the plan's
  -- notes on the stage above, so the lesson can be watched played. Lesson
  -- page only. Lit (primary) while it runs; the pixel skull is its mark.
  local ghost = Skin.Button(f, "Ghost hunter", "ghost", 126)
  ghost:SetPoint("RIGHT", playFast, "LEFT", -8, 0)
  local ghostIco = ghost:CreateTexture(nil, "ARTWORK")
  ghostIco:SetPoint("LEFT", ghost, "LEFT", 6, 0)
  Skin.Icon(ghostIco, "ghost", "ink2")
  Skin.IconSize(ghostIco)
  ghost.text:ClearAllPoints()
  ghost.text:SetPoint("LEFT", ghostIco, "RIGHT", 6, 0)
  ghost.ico = ghostIco
  ghost:SetScript("OnClick", function()
    -- PERFECT, not the default human ghost: a lesson shows the ideal (the
    -- human one jitters and skips a note in twenty -- user, 2026-08-26).
    local p = practice()
    if p and p.ToggleDemo then
      if p._demo then View:StopGhost() else View:StartGhost() end
    end
    View:PaintGhost()
  end)
  self.ghostBtn = ghost

  local barTop = TOP_PAD + PAGE_HEAD_H + 4 + CO_TOP
  local barF = CreateFrame("Frame", nil, f)
  barF:SetSize(mainW, BAR_H)
  barF:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN, -barTop)
  Skin.Surface(barF, "ground", "line")

  for i = 1, #LANES do
    local fs = barF:CreateFontString(nil, "OVERLAY")
    Skin.Font(fs, "monoMedium", Skin.SIZES.key)
    fs:SetPoint("TOPLEFT", barF, "TOPLEFT", 8, -(2 + (i - 1) * LANE_H + 6))
    fs:SetText(LANES[i]:upper())
    Skin.Text(fs, "ink3")
  end

  local cursor = barF:CreateTexture(nil, "OVERLAY")
  Skin.Paint(cursor, "accent", 1)
  cursor:SetSize(2, BAR_H - 4)
  cursor:SetPoint("TOPLEFT", barF, "TOPLEFT", 0, -2)
  cursor:Hide()

  -- The seconds axis under the bar's callout band, then the caption: what
  -- the whole period holds.
  local axisTop = barTop + BAR_H + CO_BOT
  self._axisTop = axisTop
  self.axisTex, self.axisText = newPool(), newPool()
  local capTop = axisTop + AXIS_H
  local perCap = f:CreateFontString(nil, "OVERLAY")
  Skin.Font(perCap, "monoMedium", Skin.SIZES.small)
  perCap:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN + 2, -capTop)
  perCap:SetWidth(mainW)
  perCap:SetJustifyH("LEFT")
  perCap:SetWordWrap(false)
  Skin.Text(perCap, "ink3")
  self.perCap = perCap
  -- ...and under it a banner: what the paper costs by design (M.PaperNotes).
  local perNote = Skin.Banner(f, "wait")
  perNote:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN, -(capTop + PER_CAP_H + 2))
  perNote:SetPoint("TOPRIGHT", f, "TOPRIGHT", -MARGIN, -(capTop + PER_CAP_H + 2))
  self.perNote = perNote

  local narrTop = capTop + PER_CAP_H + PER_NOTE_H + NARR_GAP
  local dropW = math.floor(mainW * DROP_FRAC)
  local leftW = mainW - dropW - SPLIT_GAP
  self._leftW, self._dropW = leftW, dropW
  local steps = {}
  for i = 1, 5 do
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(leftW, STEP_H - 2)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN, -(narrTop + (i - 1) * STEP_H))
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(STEP_BG[1], STEP_BG[2], STEP_BG[3], 1)
    bg:Hide()
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bar:SetWidth(2)
    Skin.Paint(bar, "accent", 1)
    bar:Hide()
    local num = row:CreateFontString(nil, "OVERLAY")
    Skin.Font(num, "display", Skin.SIZES.title)
    num:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -4)
    num:SetText(tostring(i))
    Skin.Text(num, "ink3")
    local txt = row:CreateFontString(nil, "OVERLAY")
    Skin.Font(txt, "ui", 13)
    txt:SetPoint("TOPLEFT", row, "TOPLEFT", 34, -4)
    txt:SetWidth(leftW - 44)
    txt:SetJustifyH("LEFT")
    txt:SetWordWrap(true)
    Skin.Text(txt, "ink2")
    row.bg, row.bar, row.num, row.text = bg, bar, num, txt
    steps[i] = row
  end

  -- The drop, right of the narration, the narration's height.
  local dropF = CreateFrame("Frame", nil, f)
  dropF:SetSize(dropW, NARR_H - 2)
  dropF:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN + leftW + SPLIT_GAP, -narrTop)
  Skin.Surface(dropF, "ground", "line")
  local lanes = CreateFrame("Frame", nil, dropF)
  lanes:SetPoint("TOPLEFT", dropF, "TOPLEFT", 1, -1)
  lanes:SetPoint("BOTTOMRIGHT", dropF, "BOTTOMRIGHT", -1, DROP_KEY_H + 8)
  if lanes.SetClipsChildren then lanes:SetClipsChildren(true) end
  dropF.lanes = lanes
  -- The strike line is placed by PaintDrop at the clock's own y: drawn at
  -- the lanes' foot it sat DROP_PAST below the moment the keycap lit, and
  -- the light read as early (user, 2026-08-27).
  local strike = lanes:CreateTexture(nil, "OVERLAY")
  Skin.Paint(strike, "ink", 0.5)
  strike:SetHeight(2)
  dropF.strike = strike
  local caps = {}
  for i = 1, 5 do
    local cap = CreateFrame("Frame", nil, dropF)
    cap:SetHeight(DROP_KEY_H - 4)
    Skin.Surface(cap, "surface2", "line")
    local key = cap:CreateFontString(nil, "OVERLAY")
    Skin.Font(key, "monoMedium", Skin.SIZES.body)
    key:SetPoint("CENTER", cap, "CENTER", 0, 0)
    key:SetJustifyH("CENTER")
    key:SetWordWrap(false)
    Skin.Text(key, "ink")
    cap.key = key
    cap:Hide()
    caps[i] = cap
  end
  dropF.caps = caps
  local dedge = {}
  for i = 1, 4 do
    local t = lanes:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 1, 1, 0.95)
    t:Hide()
    dedge[i] = t
  end
  dropF.edge = dedge
  self.dropF = dropF
  self.dropTex, self.dropText, self.dropLane = newPool(), newPool(), newPool()

  -- The NEXT chip (a light tile, dark mono text), the white edge and the
  -- flash: one of each, seated on whichever plate is next while playing.
  local nchip = CreateFrame("Frame", nil, barF)
  nchip:SetFrameLevel(barF:GetFrameLevel() + 3)
  nchip:SetSize(30, CHIP_ROW_H)
  local nchipBg = nchip:CreateTexture(nil, "BACKGROUND")
  nchipBg:SetAllPoints(nchip)
  nchipBg:SetColorTexture(0.91, 0.89, 0.83, 0.95)
  local nchipText = nchip:CreateFontString(nil, "OVERLAY")
  Skin.Font(nchipText, "monoMedium", CHIP_SIZE)
  nchipText:SetPoint("LEFT", nchip, "LEFT", CHIP_PAD_X, 0)
  nchipText:SetJustifyH("LEFT"); nchipText:SetWordWrap(false)
  nchipText:SetTextColor(0.04, 0.05, 0.06, 1)
  nchip.text = nchipText
  nchip:Hide()
  local edge = {}
  for i = 1, 4 do
    local t = barF:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 1, 1, 0.95)
    t:Hide()
    edge[i] = t
  end
  local flash = barF:CreateTexture(nil, "OVERLAY")
  flash:SetColorTexture(1, 1, 1, FLASH_ALPHA)
  flash:SetBlendMode("ADD")
  flash:Hide()
  self.nextChip, self.nextEdge, self.flash = nchip, edge, flash
  self._plates, self._nPlates = {}, 0

  self.frame, self.chip, self.barF, self.cursor = f, chip, barF, cursor
  self.playBtn, self.stepRows = play, steps
  self.segTex, self.segText, self.segIcon = newPool(), newPool(), newPool()
  self.coText, self.coLead = newPool(), newPool()
  self._plotX = LABEL_W + 12
  self._plotW = mainW - self._plotX - PLOT_PAD
  self._lit = 0
  self._playing = false
  self._pageH = narrTop + NARR_H + PAD
  f:SetHeight(self._pageH)
  if wb.RegisterPage then wb:RegisterPage("lesson", f, self) end
  f:Hide()
end

function View:OnPageShow()
  self:Rebuild(true)
  self:PaintGhost()
end

-- The ghost hunter is a PREVIEW (the Style page's pattern): ToggleDemo arms
-- a fight for it, and the second click ends that fight with the ghost -- the
-- stage kept running after the ghost stopped ("the timeline keeps moving",
-- user, 2026-08-27). `_previewFight` makes StopFight take the cancelled path
-- (no score, no ladder pass, no replay, no review). Leaving the page does
-- the same. A fight the player is running is left alone.
function View:StartGhost()
  local p = practice()
  if not (p and p.ToggleDemo) or p._demo then return end
  local ran = Nock.state.sim.fightOn
  p:ToggleDemo("perfect")
  if not ran and Nock.state.sim.fightOn then
    self._preview = true
    p._previewFight = true
  end
end

function View:StopGhost()
  local p = practice()
  if not p then return end
  if p._demo and p.ToggleDemo then p:ToggleDemo() end
  if self._preview and Nock.state.sim.fightOn and p.StopFight then
    p._previewFight = true
    p:StopFight()
  end
  self._preview = nil
end

function View:OnPageHide()
  if self._preview then self:StopGhost() end
end

-- The ghost hunter button's state: lit while the demo runs.
function View:PaintGhost()
  local b = self.ghostBtn
  if not b then return end
  local p = practice()
  local on = p and p._demo and true or false
  if on == self._ghostOn then return end
  self._ghostOn = on
  Skin.ButtonKind(b, on and "primary" or "ghost")
  Skin.Icon(b.ico, "ghost", on and "accentInk" or "ink2")
  Skin.IconSize(b.ico)
end

function View:PageHeight() return self._pageH or 200 end

function View:OnEnable()
  T = Nock.PracticeTimeline
  L = Nock.PracticeLesson
  self:RegisterMessage("NOCK_PRACTICE_LESSON_TOGGLE", "OnToggleMessage")
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "OnPracticeChanged")
  self:RegisterMessage("NOCK_PRACTICE_RESET_POS", "ResetPos")
end

function View:ResetPos()
  local f = self.frame
  if not f or self._host then return end
  Nock.db.profile.practiceLessonPos = nil
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
end

-- The toggle message (the slash, the toolbar's Lesson button): in the
-- workbench it is "go to the Lesson page" and never a close.
function View:OnToggleMessage()
  if self._host then return self:Toggle(true) end
  self:Toggle(not self.frame:IsShown())
end

function View:Toggle(show)
  if self._host then
    local wb = workbench()
    if not wb then return end
    if show then
      if wb.Open then wb:Open() end
      wb:Select("lesson")
    else
      self:StopPlay()
      wb:Select("stage")
    end
    return
  end
  if show then
    self:Rebuild(true)
    self.frame:Show()
  else
    self:StopPlay()
    self.frame:Hide()
  end
end

-- The plan may have moved under us (a new scenario pick, a haste window, the
-- fight starting). Only a change of STRING or of haste is a new lesson.
function View:OnPracticeChanged()
  if not (self.frame and self.frame:IsShown()) then return end
  self:Rebuild(false)
  self:PaintGhost()
end

----------------------------------------------------------------------------
-- Build. The only place that formats a string or moves a texture, and it runs
-- on a plan change -- never from the tick.
----------------------------------------------------------------------------

-- Localised spell names into the pure file, which may not call a WoW API for
-- them. Refreshed at every rebuild: GetSpellInfo can still be cold at login,
-- and the lesson would otherwise keep the English fallback for the session.
function View:RefreshNames()
  if not L then return end
  local N = L.NAMES
  for _, sym in ipairs({ "a", "s", "m", "A", "r" }) do
    local n = Nock.UI.PracticeNameFor(sym)
    if n then N[sym] = n end
  end
end

function View:Rebuild(force)
  local p = practice()
  if not (p and L and T and p.LessonPlan) then return end
  local str, h, notation = p:LessonPlan()
  if not (str and h) then return end
  local mul = h.rangedMul
  -- The NOTATION is part of the gate, not just the string it resolves to: an
  -- unknown notation falls back to "1:1"'s string, so two different rotations
  -- can arrive with the same `str` and the chip would keep the outgoing name.
  if not force and str == self._str and mul == self._mul and notation == self._notation then return end
  self._str, self._mul, self._notation = str, mul, notation
  self:RefreshNames()
  self.plan = L.Build(str, h, Nock.PracticeModel, self.plan)

  -- The notation chip. ASCII throughout: the header faces ship with holes in
  -- their punctuation and this string is read at a glance, not parsed.
  local ews = (h.ws or 3) / (mul or 1)
  Skin.SetChip(self.chip, ("%s - eWS %.2f"):format(notation or "?", ews))

  local pl = self.plan
  for i = 1, 5 do
    self.stepRows[i].text:SetText(pl.steps[i] or "")
  end
  self:PaintBar()
  if self.perCap then
    local pl2 = self.plan
    -- ...and, when the paper is pinned far from this bow, say so: the gaps on
    -- the bar are the haste's, not the player's.
    local note = ""
    local live = p._liveEws
    if live and ews and math.abs(ews - live) > EWS_FAR then
      note = (ews < live) and (" - pinned at eWS %.2f, a faster bow than yours (%.2f): more room between casts than you will see"):format(ews, live)
                          or (" - pinned at eWS %.2f, a slower bow than yours (%.2f): less room than you will see"):format(ews, live)
    end
    self.perCap:SetText((pl2 and pl2.periodText) and ("%s - %s%s"):format(notation or "?", pl2.periodText, note) or "")
    if self.perNote then
      local tag, text = nil, nil
      if p.PaperNotes then tag, text = p:PaperNotes() end
      Skin.SetBanner(self.perNote, tag and Skin.NOTE_ICON[tag] or "warn", text)
    end
  end
  self:LightStep(self._lit or 0)
end

-- t -> x inside the plot, in the bar frame's own coordinates.
function View:X(t)
  return self._plotX + t * (self._pps or 0)
end

-- `icon`: the period bar's mode -- a cast plate is at least the icon's width,
-- carries the spell's icon at its left, and its text only when the text FITS
-- beside the icon; nothing is ever printed past a plate's edge (the two-cycle
-- bar prints a label that does not fit to the right of its plate, which at
-- five cycles per bar wrote every name over its neighbour -- user, 2026-08-26).
function View:PaintSeg(s, off, withText, alpha, icon)
  local row = LANE_ROW[s.lane] or 0
  local y = -(2 + row * LANE_H + (LANE_H - SEG_H) / 2)
  local x0 = self:X(s.t0 + off)
  local w = (s.t1 - s.t0) * self._pps
  if s.kind == "release" then w = TICK_W end
  if w < MIN_SEG_W then w = MIN_SEG_W end
  local withIcon = icon and (s.kind == "cast" or s.kind == "clip" or s.kind == "gap") and s.sym
  local isGap = withIcon and s.kind == "gap"
  if withIcon and w < ICON_W + 4 then w = ICON_W + 4 end
  local right = self._plotX + self._plotW
  if x0 >= right then return end
  if x0 + w > right then w = right - x0 end
  local col = segColor(s)
  local t = poolTexture(self.segTex, self.barF, "ARTWORK")
  t:SetColorTexture(col[1], col[2], col[3], alpha or 1)
  t:SetSize(w, SEG_H)
  t:SetPoint("TOPLEFT", self.barF, "TOPLEFT", x0, y)
  -- A press plate on the period bar: remembered for the play cues.
  if icon and (s.kind == "cast" or s.kind == "gap") then
    local n = self._nPlates + 1
    self._nPlates = n
    local pl = self._plates[n]
    if not pl then pl = {}; self._plates[n] = pl end
    pl.t0, pl.tex, pl.sym, pl.x, pl.y, pl.w, pl.col, pl.state = s.t0 + off, t, s.sym, x0, y, w, col, nil
  end
  local textX = x0 + 4
  if withIcon then
    -- The gap's picture is the hit (Raptor Strike); a step-in boot beside it
    -- was tried and cluttered (user, 2026-08-26).
    local tex = Nock.UI.PracticeIconFor and Nock.UI.PracticeIconFor(isGap and "r" or s.sym)
    if tex then
      local ic = poolTexture(self.segIcon, self.barF, "OVERLAY")
      ic:SetTexture(tex)
      ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      ic:SetSize(ICON_W, ICON_W)
      ic:SetPoint("LEFT", self.barF, "TOPLEFT", x0 + 2, y - SEG_H / 2)
      textX = x0 + ICON_W + 5
    end
  end
  if not (withText and s.text) then return end
  local fs = poolText(self.segText, self.barF, SMALL_SIZE)
  fs:SetText(s.text)
  local tw = fs:GetStringWidth() or 0
  if icon then
    -- Inside or not at all.
    if textX - x0 + tw + 3 <= w then
      fs:SetTextColor(0.06, 0.06, 0.07)
      fs:SetPoint("LEFT", self.barF, "TOPLEFT", textX, y - SEG_H / 2)
    else
      fs:Hide()
      self.segText.n = self.segText.n - 1
    end
    return
  end
  if tw + 6 <= w then
    -- Inside the plate: dark ink on a bright fill, the way the mock reads.
    fs:SetTextColor(0.06, 0.06, 0.07)
    fs:SetPoint("LEFT", self.barF, "TOPLEFT", x0 + 4, y - SEG_H / 2)
  elseif x0 + w + 4 + tw < right then
    fs:SetTextColor(col[1], col[2], col[3])
    fs:SetPoint("LEFT", self.barF, "TOPLEFT", x0 + w + 4, y - SEG_H / 2)
  else
    fs:Hide()
    self.segText.n = self.segText.n - 1
  end
end

-- One callout: the text on a free row of its band, and a 1 px leader from that
-- row down (or up) to the bar's edge. Rows are first-fit, so two callouts a
-- tenth of a second apart never print on top of each other.
function View:PaintCallout(c, rowsUsed, nRows)
  local x = self:X(c.at)
  local fs = poolText(self.coText, self.barF, SMALL_SIZE)
  fs:SetText(c.text)
  local col = c.hot and GOLD_2 or INK_DIM
  fs:SetTextColor(col[1], col[2], col[3])
  local tw = (fs:GetStringWidth() or 0) + 6
  local row = nRows
  for r = 1, nRows do
    if (rowsUsed[r] or -1) <= x then row = r; break end
  end
  rowsUsed[row] = x + tw
  local top = (c.lane == "top")
  local dy = row * CO_ROW
  local right = self._plotX + self._plotW
  local anchorX = x + 4
  if anchorX + tw > right then anchorX = right - tw end
  if anchorX < 2 then anchorX = 2 end
  if top then
    fs:SetPoint("BOTTOMLEFT", self.barF, "TOPLEFT", anchorX, dy - CO_ROW + 2)
  else
    fs:SetPoint("TOPLEFT", self.barF, "BOTTOMLEFT", anchorX, -(dy - CO_ROW + 2))
  end
  local lead = poolTexture(self.coLead, self.barF, "ARTWORK")
  local lc = c.hot and GOLD or GRID
  lead:SetColorTexture(lc[1], lc[2], lc[3], 1)
  lead:SetSize(1, dy)
  if top then
    lead:SetPoint("BOTTOMLEFT", self.barF, "TOPLEFT", x, 0)
  else
    lead:SetPoint("TOPLEFT", self.barF, "BOTTOMLEFT", x, 0)
  end
end

function View:PaintBar()
  poolReset(self.segTex); poolReset(self.segText); poolReset(self.segIcon)
  poolReset(self.coText); poolReset(self.coLead)
  local pl = self.plan
  if not (pl and pl.cycle and pl.cycle > 0) then
    poolHideRest(self.segTex); poolHideRest(self.segText); poolHideRest(self.segIcon)
    poolHideRest(self.coText); poolHideRest(self.coLead)
    return
  end

  -- The page draws the paper's WHOLE PERIOD (a 5:5:1:1 is five autos, and
  -- its first cycle alone looks like 1:1 -- user, 2026-08-26); the floating
  -- window keeps two cycles plus the third's first cast.
  if self._host and pl.nPSegs and pl.nPSegs > 0 and pl.periodDur and pl.periodDur > 0 then
    return self:PaintPeriodBar()
  end
  local tail = (pl.forecast and pl.forecast.t1) or (0.3 * pl.cycle)
  self._span = 2 * pl.cycle + tail
  self._pps = self._plotW / self._span

  -- Cycle boundaries.
  for k = 0, 2 do
    local t = poolTexture(self.segTex, self.barF, "BACKGROUND")
    t:SetColorTexture(GRID[1], GRID[2], GRID[3], 1)
    t:SetSize(1, BAR_H - 4)
    t:SetPoint("TOPLEFT", self.barF, "TOPLEFT", self:X(k * pl.cycle), -2)
  end

  -- Two whole cycles. The CLIP lane is a worked example, not part of the
  -- rhythm: it is drawn once, under the first cycle it belongs to.
  for k = 0, 1 do
    for i = 1, pl.nSegs do
      local s = pl.segs[i]
      if not (k == 1 and s.lane == "clip") then
        self:PaintSeg(s, k * pl.cycle, k == 0, 1)
      end
    end
  end
  -- The pushed release the worked clip produces, in the CLIP lane under it.
  if pl.clip and pl.clip.release then
    local ghost = self._clipGhost
    if not ghost then ghost = { lane = "clip", kind = "release", sym = "a" }; self._clipGhost = ghost end
    ghost.t0, ghost.t1 = pl.clip.release, pl.clip.release
    self:PaintSeg(ghost, 0, false, 0.75)
  end
  -- The forecast tail: dimmed, so it reads as "and it keeps going".
  if pl.forecast then
    local f = self._fcSeg
    if not f then f = { lane = "shots", kind = "cast" }; self._fcSeg = f end
    f.sym, f.t0, f.t1 = pl.forecast.sym, pl.forecast.t0, pl.forecast.t1
    local r = self._fcRel
    if not r then r = { lane = "shots", kind = "release", sym = "a" }; self._fcRel = r end
    r.t0, r.t1 = 0, 0
    self:PaintSeg(r, 2 * pl.cycle, false, 0.45)
    self:PaintSeg(f, 2 * pl.cycle, false, 0.45)
  end

  -- Callouts, first-fit into their band's rows.
  local topRows, botRows = self._topRows, self._botRows
  if not topRows then topRows = {}; self._topRows = topRows end
  if not botRows then botRows = {}; self._botRows = botRows end
  for i = 1, 3 do topRows[i] = -1 end
  for i = 1, 2 do botRows[i] = -1 end
  for i = 1, pl.nCallouts do
    local c = pl.callouts[i]
    if c.lane == "top" then self:PaintCallout(c, topRows, 3)
    else self:PaintCallout(c, botRows, 2) end
  end

  poolHideRest(self.segTex); poolHideRest(self.segText); poolHideRest(self.segIcon)
  poolHideRest(self.coText); poolHideRest(self.coLead)
end

-- The period on the bar: every auto (dim wind-up, tick), every cast with its
-- name where it fits, the instants, the weaves on the WEAVE lane, the paper's
-- own waits as amber marks; the callouts and the worked clip on the first
-- cycle. Times are the layout's, re-based on the first release (the bar's 0).
function View:PaintPeriodBar()
  local pl = self.plan
  local rel = pl.periodRel or 0
  self._nPlates = 0
  self._nextK = nil
  self._span = pl.periodDur
  self._pps = self._plotW / self._span
  local right = self._plotX + self._plotW
  local waitCol = T.COLORS.wait
  -- Faint second lines through the bar, for the axis under it.
  for k = 1, math.floor(self._span) do
    local g = poolTexture(self.segTex, self.barF, "BACKGROUND")
    g:SetColorTexture(1, 1, 1, 0.05)
    g:SetSize(1, BAR_H - 4)
    g:SetPoint("TOPLEFT", self.barF, "TOPLEFT", self:X(k), -2)
  end
  local rels = self._rels
  if not rels then rels = {}; self._rels = rels end
  local nRels = 0
  for i = 1, pl.nPSegs do
    local s = pl.pSegs[i]
    local t0, t1 = s.t0 - rel, s.t1 - rel
    if t1 > 1e-9 and t0 < self._span - 1e-9 then
      if t0 < 0 then t0 = 0 end
      if s.kind == "release" then
        -- A cycle boundary and the tick itself.
        local g = poolTexture(self.segTex, self.barF, "BACKGROUND")
        g:SetColorTexture(GRID[1], GRID[2], GRID[3], 1)
        g:SetSize(1, BAR_H - 4)
        g:SetPoint("TOPLEFT", self.barF, "TOPLEFT", self:X(t0), -2)
        local r = self._pRel
        if not r then r = { lane = "shots", kind = "release", sym = "a" }; self._pRel = r end
        r.t0, r.t1 = t0, t0
        self:PaintSeg(r, 0, false, 1)
        nRels = nRels + 1
        rels[nRels] = t0
      elseif s.kind == "wait" then
        -- The paper's own wait: an amber plate the height of the lane, the
        -- milliseconds inside it when they fit, nothing otherwise (the caption
        -- under the bar sums them).
        local x0 = self:X(t0)
        local w = (t1 - t0) * self._pps
        if x0 + w > right then w = right - x0 end
        if w < MIN_SEG_W then w = MIN_SEG_W end
        local t = poolTexture(self.segTex, self.barF, "ARTWORK")
        t:SetColorTexture(waitCol[1], waitCol[2], waitCol[3], 0.55)
        t:SetSize(w, SEG_H)
        t:SetPoint("TOPLEFT", self.barF, "TOPLEFT", x0, -(2 + (LANE_H - SEG_H) / 2))
        local fs = poolText(self.segText, self.barF, SMALL_SIZE - 2)
        fs:SetText(s.text or "")
        if (fs:GetStringWidth() or 0) + 4 <= w then
          fs:SetTextColor(0.06, 0.06, 0.07)
          fs:SetPoint("LEFT", self.barF, "TOPLEFT", x0 + 2, -(2 + LANE_H / 2))
        else
          fs:Hide()
          self.segText.n = self.segText.n - 1
        end
      else
        local d = self._pSeg
        if not d then d = {}; self._pSeg = d end
        d.lane, d.kind, d.sym, d.t0, d.t1 = s.lane, s.kind, s.sym, t0, t1
        if s.kind == "cast" or s.kind == "gap" then
          -- The icon says which; the seconds are the label.
          d.text = ("%.2f"):format(s.t1 - s.t0)
        elseif s.kind == "windup" then
          d.text = nil
        else
          d.text = s.text
        end
        self:PaintSeg(d, 0, true, s.kind == "windup" and 0.6 or 1, true)
      end
    end
  end
  -- A cycle with nothing to press in it says so, faintly, when it is wide
  -- enough: on a fast bow most cycles are auto-only and the empty lane read
  -- as a hole.
  for k = 1, nRels do
    local a, b = rels[k], rels[k + 1] or self._span
    local hasPress = false
    for i = 1, self._nPlates do
      local p = self._plates[i]
      if p.t0 >= a - 1e-6 and p.t0 < b - 1e-6 then hasPress = true; break end
    end
    local w = (b - a) * self._pps
    if not hasPress and w >= AUTO_ONLY_MIN_W then
      local fs = poolText(self.segText, self.barF, SMALL_SIZE - 1)
      fs:SetText("auto only")
      Skin.Text(fs, "ink3")
      fs:SetPoint("CENTER", self.barF, "TOPLEFT", self:X((a + b) / 2), -(2 + LANE_H / 2))
    end
  end
  -- The seconds axis under the bar.
  if self.axisTex then
    poolReset(self.axisTex); poolReset(self.axisText)
    local f = self.frame
    local baseX = MARGIN
    for k = 0, math.floor(self._span) do
      local x = baseX + self:X(k)
      local t = poolTexture(self.axisTex, f, "ARTWORK")
      Skin.Paint(t, "line", 1)
      t:SetSize(1, 5)
      t:SetPoint("TOPLEFT", f, "TOPLEFT", x, -self._axisTop)
      local fs = poolText(self.axisText, f, SMALL_SIZE - 2)
      fs:SetText(("%ds"):format(k))
      Skin.Text(fs, "ink3")
      fs:SetPoint("TOPLEFT", f, "TOPLEFT", x + 3, -(self._axisTop + 3))
    end
    poolHideRest(self.axisTex); poolHideRest(self.axisText)
  end
  -- The worked clip, on the first cycle.
  if pl.clip then
    local c = self._pClip
    if not c then c = { lane = "clip", kind = "clip", sym = "s" }; self._pClip = c end
    c.t0, c.t1 = pl.clip.t0, pl.clip.t1
    c.text = ("late +%.1f s"):format(L.CLIP_LATE)
    self:PaintSeg(c, 0, true, 1, true)
    if pl.clip.release then
      local ghost = self._clipGhost
      if not ghost then ghost = { lane = "clip", kind = "release", sym = "a" }; self._clipGhost = ghost end
      ghost.t0, ghost.t1 = pl.clip.release, pl.clip.release
      self:PaintSeg(ghost, 0, false, 0.75)
    end
  end
  local topRows, botRows = self._topRows, self._botRows
  if not topRows then topRows = {}; self._topRows = topRows end
  if not botRows then botRows = {}; self._botRows = botRows end
  for i = 1, 3 do topRows[i] = -1 end
  for i = 1, 2 do botRows[i] = -1 end
  for i = 1, pl.nCallouts do
    local c = pl.callouts[i]
    -- "next release" is a tick on this bar, not a callout.
    if c.kind ~= "next" then
      if c.lane == "top" then self:PaintCallout(c, topRows, 3)
      else self:PaintCallout(c, botRows, 2) end
    end
  end
  poolHideRest(self.segTex); poolHideRest(self.segText); poolHideRest(self.segIcon)
  poolHideRest(self.coText); poolHideRest(self.coLead)
  self:PaintCues(self._playing and self._playT or nil)
  self:PaintDrop(self._playing and self._playT or nil)
end

-- The play cues on the period bar's plates, for the cursor at `t` (nil: not
-- playing -- every plate plain, chip and edge away). Change-gated on which
-- plate is next; the flash is EaseFlash's.
function View:PaintCues(t)
  local n = self._nPlates or 0
  if n == 0 or not self.nextChip then return end
  local k = nil
  if t then
    for i = 1, n do
      if self._plates[i].t0 >= t - 1e-6 then k = i; break end
    end
    if not k then k = n + 1 end
  end
  if k == self._nextK then return end
  -- The plate the cursor just reached flashes.
  if t and self._nextK and k > self._nextK and k - 1 >= 1 and k - 1 <= n then
    local p = self._plates[k - 1]
    self.flash:ClearAllPoints()
    self.flash:SetSize(p.w + 4, SEG_H + 4)
    self.flash:SetPoint("TOPLEFT", self.barF, "TOPLEFT", p.x - 2, p.y + 2)
    self.flash:SetAlpha(1)
    self.flash:Show()
    self._flashAt = GetTime()
  end
  self._nextK = k
  for i = 1, n do
    local p = self._plates[i]
    local a
    if not k then a = 1
    elseif i < k then a = PAST_ALPHA
    elseif i == k then a = 1
    else a = DIM_ALPHA end
    p.tex:SetColorTexture(p.col[1], p.col[2], p.col[3], a)
  end
  local chip, edge = self.nextChip, self.nextEdge
  if k and k <= n then
    local p = self._plates[k]
    local key = nil
    local pr = practice()
    if pr and pr.RowKey then key = pr:RowKey(ROW_OF_SYM[p.sym] or p.sym) end
    chip.text:SetText(key and ("NEXT " .. key) or "NEXT")
    chip:SetWidth((chip.text:GetStringWidth() or 20) + CHIP_PAD_X * 2)
    chip:ClearAllPoints()
    chip:SetPoint("BOTTOMLEFT", self.barF, "TOPLEFT", p.x, p.y + 2)
    chip:Show()
    local x, y, w = p.x, p.y, p.w
    edge[1]:ClearAllPoints(); edge[1]:SetSize(w, 1); edge[1]:SetPoint("TOPLEFT", self.barF, "TOPLEFT", x, y)
    edge[2]:ClearAllPoints(); edge[2]:SetSize(w, 1); edge[2]:SetPoint("TOPLEFT", self.barF, "TOPLEFT", x, y - SEG_H + 1)
    edge[3]:ClearAllPoints(); edge[3]:SetSize(1, SEG_H); edge[3]:SetPoint("TOPLEFT", self.barF, "TOPLEFT", x, y)
    edge[4]:ClearAllPoints(); edge[4]:SetSize(1, SEG_H); edge[4]:SetPoint("TOPLEFT", self.barF, "TOPLEFT", x + w - 1, y)
    for i = 1, 4 do edge[i]:Show() end
  else
    chip:Hide()
    for i = 1, 4 do edge[i]:Hide() end
  end
end

function View:EaseFlash(now)
  local f = self.flash
  if not (f and self._flashAt) then return end
  local p = (now - self._flashAt) / FLASH_LIFE
  if p >= 1 then
    f:Hide()
    self._flashAt = nil
  else
    f:SetAlpha(1 - p)
  end
end

----------------------------------------------------------------------------
-- Narration lighting
----------------------------------------------------------------------------

function View:LightStep(n)
  self._lit = n or 0
  for i = 1, 5 do
    local row = self.stepRows[i]
    local on = (i == n)
    if on then
      row.bg:Show()
      if row.bar then row.bar:Show() end
      row.num:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
      row.text:SetTextColor(INK[1], INK[2], INK[3])
    else
      row.bg:Hide()
      if row.bar then row.bar:Hide() end
      row.num:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
      row.text:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])
    end
  end
end

-- The review's "Open lesson step N": open on the step that explains the fix.
function View:ShowStep(n)
  if self._host then
    self:Toggle(true)
  else
    self:Rebuild(true)
    self.frame:Show()
  end
  self:StopPlay()
  if n and n >= 1 and n <= 5 then self:LightStep(n) end
end

----------------------------------------------------------------------------
-- Play slowly. A gold cursor walked across two cycles at a quarter speed by
-- the central tick -- there is no OnUpdate here, and Refresh returns on its
-- first line whenever nothing is playing.
----------------------------------------------------------------------------

-- `div` slows the clock (PLAY_DIV for Play slowly, 1 for Play). A click while
-- playing stops; a click on the OTHER tempo restarts at that tempo.
function View:TogglePlay(div)
  div = div or PLAY_DIV
  if self._playing then
    local same = (self._playDiv or PLAY_DIV) == div
    self:StopPlay()
    if same then return end
  end
  self:StartPlay(div)
end

function View:StartPlay(div)
  local pl = self.plan
  if not (pl and pl.cycle and pl.cycle > 0) then return end
  self._playDiv = div or PLAY_DIV
  self._playing = true
  self._playT0 = GetTime()
  -- The page's bar is the whole period: the cursor walks all of it.
  local span = (self._host and pl.periodDur and pl.periodDur > 0) and pl.periodDur or (2 * pl.cycle)
  self._playSpan = span
  self._playEnd = span * self._playDiv
  self._playT = 0
  self.cursor:Show()
  local b = (self._playDiv == 1 and self.playFastBtn) or self.playBtn
  self._playBtnLit = b
  if self._host then
    Skin.SetButtonText(b, "Stop", b == self.playFastBtn and 64 or 104)
    Skin.ButtonKind(b, "primary")
  else self.playBtn:SetText("Stop") end
end

function View:StopPlay()
  if not self._playing then return end
  self._playing = false
  self._playT = nil
  self.cursor:Hide()
  if self._host then
    local b = self._playBtnLit or self.playBtn
    if b == self.playFastBtn then Skin.SetButtonText(b, "Play", 64) else Skin.SetButtonText(b, "Play slowly", 104) end
    Skin.ButtonKind(b, "ghost")
    self._playBtnLit = nil
  else self.playBtn:SetText("Play slowly") end
  self:LightStep(0)
  if self.nextChip then self:PaintCues(nil) end
  if self.flash then self.flash:Hide(); self._flashAt = nil end
  self:PaintDrop(nil)
end

-- The columns the paper needs: the auto, then each ability it has, in the
-- stage's order. Filled into self._dropCols; returns the count.
local DROP_ORDER = { "a", "s", "m", "A", "w" }
function View:DropColumns()
  local pl = self.plan
  local cols = self._dropCols
  if not cols then cols = {}; self._dropCols = cols end
  local has = { a = true }
  for i = 1, (pl and pl.nPSegs or 0) do
    local s = pl.pSegs[i]
    if s and (s.kind == "cast" or s.kind == "gap") then has[s.sym] = true end
  end
  local n = 0
  for i = 1, #DROP_ORDER do
    if has[DROP_ORDER[i]] then n = n + 1; cols[n] = DROP_ORDER[i] end
  end
  for i = n + 1, #cols do cols[i] = nil end
  return n
end

-- The drop at clock `t` (seconds from the first release, the bar's own
-- origin; nil = the page at rest, the period's start). Everything pooled and
-- repainted per call: a few dozen textures at 30 Hz while playing.
function View:PaintDrop(t)
  local d = self.dropF
  local pl = self.plan
  if not (d and pl and pl.nPSegs and pl.nPSegs > 0 and pl.periodDur) then
    if d then d:Hide() end
    return
  end
  d:Show()
  local rest = (t == nil)
  t = t or 0
  local n = self:DropColumns()
  local cols = self._dropCols
  local lanes = d.lanes
  local W = d:GetWidth() - 2 - DROP_PAD * 2
  local colW = W / n
  local laneH = lanes:GetHeight()
  local strikeY = laneH - 2                      -- from the lanes' top, downward
  local pps = (laneH - 6) / (DROP_LOOK + DROP_PAST)
  local strikeTop = strikeY - DROP_PAST * pps    -- the strike line's y, from the top
  local function Y(tt) return strikeTop - (tt - t) * pps end
  local function X(i) return DROP_PAD + (i - 1) * colW end
  d.strike:ClearAllPoints()
  d.strike:SetPoint("TOPLEFT", lanes, "TOPLEFT", 0, -(strikeTop - 1))
  d.strike:SetPoint("TOPRIGHT", lanes, "TOPRIGHT", 0, -(strikeTop - 1))
  local colOf = {}
  for i = 1, n do colOf[cols[i]] = i end
  poolReset(self.dropTex); poolReset(self.dropText); poolReset(self.dropLane)
  -- Lanes and the seconds ruler.
  local p = practice()
  local nextSeg, nextT
  local rel = pl.periodRel or 0
  for i = 1, n do
    local lane = poolTexture(self.dropLane, lanes, "BACKGROUND")
    lane:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.035 or 0.02)
    lane:SetSize(colW - 2, laneH)
    lane:SetPoint("TOPLEFT", lanes, "TOPLEFT", X(i) + 1, 0)
  end
  for k = 1, math.floor(DROP_LOOK) do
    local y = Y(t + k)
    if y > 0 then
      local g = poolTexture(self.dropLane, lanes, "BACKGROUND")
      g:SetColorTexture(1, 1, 1, 0.07)
      g:SetSize(W, 1)
      g:SetPoint("TOPLEFT", lanes, "TOPLEFT", DROP_PAD, -y)
      local fs = poolText(self.dropText, lanes, SMALL_SIZE - 2)
      fs:SetText(("+%ds"):format(k))
      Skin.Text(fs, "ink3")
      fs:SetPoint("BOTTOMRIGHT", lanes, "TOPRIGHT", -DROP_PAD - 2, -y + 1)
    end
  end
  -- The notes. Times re-based on the first release, like the bar.
  local strike = strikeTop
  local waitCol = T.COLORS.wait
  for i = 1, pl.nPSegs do
    local s = pl.pSegs[i]
    if s then
      local t0, t1 = s.t0 - rel, s.t1 - rel
      if t1 >= t - DROP_PAST and t0 <= t + DROP_LOOK + 0.5 then
        local ci = colOf[s.sym == "r" and "w" or s.sym]
        if ci then
          local x = X(ci) + 3
          local w = colW - 6
          local past = t0 < t - 1e-6
          local col = T.COLORS[s.sym] or T.COLORS.a
          if s.kind == "windup" then
            local tex = poolTexture(self.dropTex, lanes, "ARTWORK")
            tex:SetColorTexture(col[1], col[2], col[3], past and 0.10 or 0.22)
            tex:SetSize(w, math.max(1, (t1 - t0) * pps))
            tex:SetPoint("TOPLEFT", lanes, "TOPLEFT", x, -Y(t1))
          elseif s.kind == "release" then
            local tex = poolTexture(self.dropTex, lanes, "ARTWORK")
            tex:SetColorTexture(col[1], col[2], col[3], past and 0.4 or 1)
            tex:SetSize(w, 3)
            tex:SetPoint("TOPLEFT", lanes, "TOPLEFT", x, -(Y(t0) - 1))
          elseif s.kind == "wait" then
            local tex = poolTexture(self.dropTex, lanes, "ARTWORK")
            tex:SetColorTexture(waitCol[1], waitCol[2], waitCol[3], past and 0.3 or 0.6)
            tex:SetSize(w, math.max(2, (t1 - t0) * pps))
            tex:SetPoint("TOPLEFT", lanes, "TOPLEFT", x, -Y(t1))
          elseif s.kind == "cast" or s.kind == "gap" then
            -- The block: bottom edge = the press (the hit for a weave), top
            -- edge = free again. An instant is a short block.
            local h = (t1 - t0) * pps
            if h < 12 then h = 12 end
            local tex = poolTexture(self.dropTex, lanes, "ARTWORK")
            if s.kind == "gap" then
              local mv = T.COLORS.wait
              tex:SetColorTexture(mv[1], mv[2], mv[3], past and 0.25 or 0.55)
            else
              tex:SetColorTexture(col[1], col[2], col[3], past and 0.35 or 0.9)
            end
            tex:SetSize(w, h)
            tex:SetPoint("TOPLEFT", lanes, "TOPLEFT", x, -(Y(t0) - h))
            -- The press edge, dark, so the block reads bottom-up.
            local ed = poolTexture(self.dropTex, lanes, "OVERLAY")
            ed:SetColorTexture(0, 0, 0, 0.6)
            ed:SetSize(w, 2)
            ed:SetPoint("TOPLEFT", lanes, "TOPLEFT", x, -(Y(t0) - 2))
            -- The key inside, when the block is tall enough.
            if h >= 16 then
              local fs = poolText(self.dropText, lanes, SMALL_SIZE - 1)
              local key = (s.kind == "gap") and (p and p.RowKey and p:RowKey("w")) or (p and p.RowKey and p:RowKey(s.sym))
              fs:SetText(key or (s.kind == "gap" and "weave" or (s.text or s.sym)))
              fs:SetTextColor(0.04, 0.05, 0.06, past and 0.6 or 1)
              fs:SetPoint("BOTTOM", lanes, "TOPLEFT", x + w / 2, -(Y(t0) - 3))
            end
            if not rest and not past and (not nextT or t0 < nextT) then nextSeg, nextT = s, t0 end
          end
        end
      end
    end
  end
  poolHideRest(self.dropTex); poolHideRest(self.dropText); poolHideRest(self.dropLane)
  -- The white edge on the next note while playing.
  local e = d.edge
  if nextSeg then
    local ci = colOf[nextSeg.sym == "r" and "w" or nextSeg.sym]
    local t0, t1 = nextSeg.t0 - rel, nextSeg.t1 - rel
    local h = math.max(12, (t1 - t0) * pps)
    local x, w = X(ci) + 1, colW - 2
    local top = Y(t0) - h - 2
    e[1]:SetSize(w, 1); e[1]:SetPoint("TOPLEFT", lanes, "TOPLEFT", x, -top)
    e[2]:SetSize(w, 1); e[2]:SetPoint("TOPLEFT", lanes, "TOPLEFT", x, -(top + h + 4))
    e[3]:SetSize(1, h + 5); e[3]:SetPoint("TOPLEFT", lanes, "TOPLEFT", x, -top)
    e[4]:SetSize(1, h + 5); e[4]:SetPoint("TOPLEFT", lanes, "TOPLEFT", x + w - 1, -top)
    for i = 1, 4 do e[i]:Show() end
  else
    for i = 1, 4 do e[i]:Hide() end
  end
  self._dropNext = nextSeg
  -- The keycaps: the real binds. Near its note the cap's line takes the
  -- ability's colour; for a beat after the press moment it lights.
  local caps = d.caps
  for i = 1, 5 do
    local cap = caps[i]
    if i <= n then
      local sym = cols[i]
      cap:ClearAllPoints()
      cap:SetWidth(colW - 4)
      cap:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 1 + X(i) + 2, 3)
      local key
      if sym == "a" then key = "auto"
      elseif p and p.RowKey then key = p:RowKey(sym == "r" and "w" or sym) end
      if sym ~= "a" and not key then
        cap.key:SetText("no key"); Skin.Text(cap.key, "bad")
      else
        cap.key:SetText(key); Skin.Text(cap.key, sym == "a" and "ink3" or "ink")
      end
      local near = nextSeg and (colOf[nextSeg.sym == "r" and "w" or nextSeg.sym] == i) and (nextT - t) <= DROP_NEAR
      local lit = false
      if not rest then
        -- Lit: a press moment of this column within DROP_LIT behind the clock.
        for j = 1, pl.nPSegs do
          local s = pl.pSegs[j]
          if s and (s.kind == "cast" or s.kind == "gap") and colOf[s.sym == "r" and "w" or s.sym] == i then
            local dt = t - (s.t0 - rel)
            if dt >= 0 and dt <= DROP_LIT then lit = true; break end
          end
        end
      end
      if lit then Skin.Surface(cap, "ink", "ink"); Skin.Text(cap.key, "ground")
      elseif near then
        local c = T.COLORS[sym] or T.COLORS.a
        Skin.Surface(cap, "raised", "line")
        if cap.skinLine then for _, ln in pairs(cap.skinLine) do ln:SetColorTexture(c[1], c[2], c[3], 1) end end
      else Skin.Surface(cap, "surface2", "line") end
      cap:Show()
    else
      cap:Hide()
    end
  end
end

function View:Refresh()
  if not self._playing then return end
  local f = self.frame
  if not (f and f:IsShown()) then self:StopPlay() return end
  local pl = self.plan
  if not (pl and pl.cycle and pl.cycle > 0 and pl.marks) then self:StopPlay() return end
  local now = GetTime()
  local el = now - self._playT0
  if el > self._playEnd + PLAY_HOLD then self:StopPlay() return end
  local t = el / (self._playDiv or PLAY_DIV)
  local span = self._playSpan or (2 * pl.cycle)
  if t > span then t = span end
  self._playT = t
  self.cursor:SetPoint("TOPLEFT", self.barF, "TOPLEFT", self:X(t), -2)
  if self.nextChip then
    self:PaintCues(t)
    self:EaseFlash(now)
  end
  self:PaintDrop(t)
  -- Which step the cursor has reached, inside whichever of the two cycles it
  -- is walking: the marks are one cycle's worth and the lesson repeats.
  local ct = t % pl.cycle
  local marks, k = pl.marks, 1
  for i = 1, 5 do
    if marks[i] and ct >= marks[i] then k = i end
  end
  if k ~= self._lit then self:LightStep(k) end
end

----------------------------------------------------------------------------
-- The ladder. Task 6 owns the contents; this owns the drawing.
----------------------------------------------------------------------------

-- Placeholder rows: the ten drills the ladder names, with NO progress
-- claimed -- a dot marked done here would be a lie until the ladder module
-- exists. Same shape Ladder.Items publishes, `section` marker included.
local PLACEHOLDER = {
  { id = "beat",       section = "TURRET",  name = "Hold the beat",      sub = "1:1 - no weave",           pass = "0 clips + 90% / 16", state = "cur" },
  { id = "multi",      name = "Add Multi",       sub = "1:1 + Multi",              pass = "90% cycles / 16",    state = "todo" },
  { id = "arcane",     name = "Add Arcane",      sub = "+ Arcane filler",          pass = "90% cycles / 16",    state = "todo" },
  { id = "french",     name = "Full turret",     sub = "turret notation",          pass = "90% cycles / 16",    state = "todo" },
  { id = "weave-beat", section = "WEAVE",   name = "Weave the beat",     sub = "in, hit, out",             pass = "4/5 weaves + 85%",   state = "todo" },
  { id = "weave-out",  name = "Weave + Arcane",  sub = "+ Arcane on the way out",  pass = "4/5 weaves + 85%",   state = "todo" },
  { id = "weave-shot", name = "Weave + Steady",  sub = "+ Steady before the gap",  pass = "4/5 weaves + 85%",   state = "todo" },
  { id = "weave-full", name = "Full weave",      sub = "weave notation",           pass = "4/5 weaves + 85%",   state = "todo" },
  { id = "rhythm",     section = "MASTERY", name = "Rhythm changes",     sub = "Hawk - Rapid Fire",        pass = "85% + 2 windows",    state = "todo" },
  { id = "opener",     name = "Opener + cooldowns", sub = "pull - lust - drums",   pass = "opener OK",          state = "todo" },
}

-- Every rung is OPEN: the ladder is a status board, not a gate. An unplayed
-- rung's dot is a plain grey (it used to be near-black, which read as locked)
-- and its pass column leads with the word.
local DOT = {
  done = GOOD,
  cur  = GOLD,
  todo = { 0.55, 0.57, 0.62 },
}
local STATUS_WORD = { done = "done", cur = "now", todo = "open" }
local INK_OPEN = { 0.62, 0.60, 0.56 }

function View:SetLadder(items)
  self._ladder = items or PLACEHOLDER
  local rows = self.ladderRows
  if not rows then return end
  local sections, side = self.ladderSections, self.ladderSide
  if not (sections and side) then return end
  -- Walk the rows top to bottom, dropping a track header wherever the data
  -- carries one and pushing everything below it down. The view is told where
  -- the tracks begin; it never works it out from the ids.
  local y, nSec = LADDER_TOP, 0
  for i = 1, LADDER_ROWS do
    local row = rows[i]
    local it = self._ladder[i]
    if not it then
      row.id = nil
      row:Hide()
    else
      if it.section and nSec < LADDER_SECTIONS then
        nSec = nSec + 1
        local fs = sections[nSec]
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -(y + 2))
        fs:SetText(it.section)
        fs:Show()
        y = y + SECTION_H
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", side, "TOPLEFT", 6, -y)
      y = y + LADDER_H
      row:Show()
      -- Which drill this row LOADS, on the row itself: the OnClick is shared
      -- (ladderRowClick) so the id may not live in a closure.
      row.id = it.id or it.name
      local st = it.state or "todo"
      local d = DOT[st] or DOT.todo
      row.dot:SetColorTexture(d[1], d[2], d[3], 1)
      row.name:SetText(it.name or "")
      row.name:SetTextColor(INK[1], INK[2], INK[3])
      row.sub:SetText(it.sub or "")
      -- The status word leads the pass column: open / now / done. A rung that
      -- has been passed says so in the same green its dot carries; the rung
      -- you are ON is a gold wash, not a plate.
      local word = STATUS_WORD[st] or STATUS_WORD.todo
      local pass = it.pass
      if pass and pass ~= "" and pass ~= "-" then
        row.pass:SetText(word .. " 9483 " .. pass)
      else
        row.pass:SetText(word)
      end
      if st == "done" then
        row.pass:SetTextColor(GOOD[1], GOOD[2], GOOD[3])
      elseif st == "cur" then
        row.pass:SetTextColor(GOLD_2[1], GOLD_2[2], GOLD_2[3])
      else
        row.pass:SetTextColor(INK_OPEN[1], INK_OPEN[2], INK_OPEN[3])
      end
      if st == "cur" then
        row:SetBackdropColor(GOLD[1], GOLD[2], GOLD[3], 0.10)
        row:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.7)
      else
        row:SetBackdropColor(0, 0, 0, 0)
        row:SetBackdropBorderColor(0, 0, 0, 0)
      end
    end
  end
  -- A shorter ladder (or the placeholder) leaves headers over: a stale WEAVE
  -- floating on an empty row is worse than no header at all.
  for i = nSec + 1, LADDER_SECTIONS do sections[i]:Hide() end
end
