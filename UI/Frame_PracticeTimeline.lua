-- UI/Frame_PracticeTimeline.lua
-- The fight review, read as a lesson: headline, three stats, up to three fix cards with a cycle replay, and the old lanes folded away under Details.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("PracticeTimelineView", "AceEvent-3.0")
local C = Nock.Constants
local Skin = Nock.Skin

local PAD = C.DIM.OUTER_PAD
local ROW_GAP = 8
local TITLE_H = 26
-- Type scale (D2b): the window title 15, body and narration 14, the small
-- captions 11. The lanes under Details keep their own smaller scale — they are
-- a chart to check the reading against, not the reading.
local TITLE_SIZE = 15
local BODY_SIZE = 14
local SMALL_SIZE = 11
-- The headline: the grade at 44 pt beside the two lines that say what it means.
local HEADLINE_H = 72
local GRADE_W = 74
local GRADE_SIZE, HEAD_SIZE, SUB_SIZE = 44, 20, BODY_SIZE
-- Three stat tiles: a severity rail, the value, then what it is.
local STAT_H = 52
local STAT_RAIL_H = 3
local STAT_VALUE_SIZE = 22
local NSTATS, STAT_GAP = 3, 8
-- A fix card: the sentence on the left, a replay of the cycle on the right.
-- The height is the LONGEST advice string's stack, not the average one's:
-- pad 12 + eyebrow 13 + 4 + three title lines at 17 pt (61) + gap 6 + three
-- body lines at 14 pt (51) + 4 + button 22 + pad 12. ADVICE.STEADY_WONT_FIT is
-- 109 characters and does wrap to three lines over the 352 px text column.
local CARD_H, CARD_GAP, CARD_PAD = 186, 8, 12
local CARD_TITLE_SIZE = 17
local CARD_RULE_W = 4                    -- the severity rail down the left edge
local MAX_CARDS = 3
local REPLAY_MIN_W, REPLAY_MAX_W = 200, 360
local REPLAY_LABEL_W = 42
local REPLAY_LANE_H = 22
local REPLAY_LANE_Y = { -38, -92 }       -- PAPER, YOU
local CARD_BTN_H = 22
local SECT_H = 20                        -- a collapsible section's header button
local EMPTY_H = 40                       -- the "no fight yet" line, on its own
local LANE_H, BAR_H = 18, 14
local LANES = { "paper", "auto", "cast", "melee", "procs" }
local LANE_INDEX = { paper = 1, auto = 2, cast = 3, melee = 4, procs = 5 }
local LABEL_W = 42
local AXIS_H = 14
local LANE_AREA_H = #LANES * LANE_H + AXIS_H
local ROT_H = 15
local ROT_BODY_H = ROT_H + 2
local SLIDER_H = 10
local META_H = 24                        -- the two folded-away detail lines
local ROW_H = 14
local MAX_ROWS = 8           -- fault rows in the viewport; the list scrolls past that
local MAX_POOL_ROWS = 200    -- fault rows the pool ever builds; the rest are counted
local ISSUE_SLIDER_W = 8     -- the slim slider beside the fault rows
local WHEEL_ROWS = 3         -- rows per wheel notch in the fault list
local ICON_MIN = 18          -- an item narrower than this gets no icon
local MARK_HIT, MARK_SIZE = 10, 6
local CHIP_H = 18
local CHIP_PAD = 14          -- horizontal padding inside a chip
local CHIP_MIN_W = 44        -- a chip never shrinks past this, however tight the bar
local COPY_W, CLOSE_W, BTN_GAP = 100, 26, 4
-- Only the visible stretch is drawn: a five-minute fight is 24 000 px of lane
-- and would otherwise cost a texture per event on every rebuild.
local CULL_PAD = 80          -- px drawn outside the viewport
local REPAINT_AT = 40        -- px of scroll before the culled paint is redone

-- The skin's tokens (UI/Skin.lua): the accent where the mock had gold, the
-- surfaces a few points over black.
local function tok(name, a) local c = Skin.COLORS[name]; return { c[1], c[2], c[3], a } end
local GOLD        = tok("accent")
local GOOD        = tok("good")
local WARN        = tok("wait")
local BAD         = tok("bad")
local INK         = tok("ink")
local INK_DIM     = tok("ink2")
local INK_FAINT   = tok("ink3")
local CHIP_INK    = tok("accentInk")       -- text on a FILLED chip
local BORDER      = tok("line", 1)
local CHIP_BG     = tok("ground", 1)
local CHIP_BORDER = tok("line", 1)
local TILE_BG     = tok("surface2", 1)
local CARD_BG     = tok("surface2", 1)
local STRIP_BG    = tok("ground", 1)
local NONE_MARK   = "\226\128\148"          -- em dash
local MID_DOT     = " \194\183 "

-- Severity chips in the fault rows: a filled plate rather than coloured text,
-- so a row scans as bad/warn/good before it is read.
local SEV = {
  bad  = { bg = { 0.23, 0.11, 0.11, 1 }, ink = BAD },
  warn = { bg = { 0.23, 0.20, 0.10, 1 }, ink = WARN },
  good = { bg = { 0.11, 0.20, 0.14, 1 }, ink = GOOD },
}

-- Stat-tile value colours, by index. 4 is the neutral one — every tile reads
-- neutral when the number behind it has no threshold, or no fight yet.
local STAT_COLOR = { GOOD, WARN, BAD, INK }
-- The tile's top rail takes the same index. A neutral tile gets the panel's own
-- rule colour rather than ink: a rail is a severity mark, and "no threshold"
-- must not read as a verdict.
local RAIL_NEUTRAL = { 0.30, 0.33, 0.40 }
local STAT_RAIL = { GOOD, WARN, BAD, RAIL_NEUTRAL }

local TL                      -- Nock.PracticeTimeline, resolved on enable
local GR                      -- Nock.PracticeGrader
local LADDER                  -- Nock.PracticeLadder
local LESSON                  -- Nock.PracticeLesson

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function practice() return Nock:GetModule("Practice", true) end
local function workbench() return Nock:GetModule("PracticeWorkbench", true) end
local reviewOn   -- defined with the show/hide code below

-- Icon per lane symbol: Nock.UI.PracticeIconFor (UI/Widgets.lua), shared with
-- the conveyor strip and cached there for the session.
local DESATURATED = { w = true }   -- the auto-attack weave is Raptor's icon, greyed

----------------------------------------------------------------------------
-- Pools. Every drawn thing comes from one; nothing is created per paint after
-- the first fight of a session.
----------------------------------------------------------------------------

local function newPool() return { n = 0, max = 0 } end

local function poolReset(pool) pool.n = 0 end

local function poolHideRest(pool)
  for i = pool.n + 1, pool.max do pool[i]:Hide() end
end

local function poolTexture(pool, parent, layer)
  local n = pool.n + 1
  pool.n = n
  local t = pool[n]
  if not t then
    t = parent:CreateTexture(nil, layer)
    pool[n] = t
    pool.max = n
  end
  t:ClearAllPoints()
  t:SetTexture(nil)
  t:SetDesaturated(false)
  t:SetTexCoord(0, 1, 0, 1)
  t:Show()
  return t
end

local function poolFontString(pool, parent, size)
  local n = pool.n + 1
  pool.n = n
  local fs = pool[n]
  if not fs then
    fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Nock.UI.GetFont(), size, "OUTLINE")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    pool[n] = fs
    pool.max = n
  end
  fs:ClearAllPoints()
  fs:Show()
  return fs
end

----------------------------------------------------------------------------
-- Marks: an invisible button per verdict, carrying the tooltip.
----------------------------------------------------------------------------

local function markEnter(btn)
  local mk = btn.mark
  if not mk then return end
  GameTooltip:SetOwner(btn, "ANCHOR_TOP")
  GameTooltip:AddLine(mk.text or mk.code or "", 1, 1, 1)
  if mk.did then GameTooltip:AddLine("You did: " .. mk.did, 1, 0.7, 0.7, true) end
  if mk.expected then GameTooltip:AddLine("Expected: " .. mk.expected, 0.74, 0.94, 0.78, true) end
  if mk.cost then GameTooltip:AddLine("Cost: " .. tostring(mk.cost), 1, 0.85, 0.4, true) end
  GameTooltip:Show()
end

local function markLeave() GameTooltip:Hide() end

local function poolMark(pool, parent)
  local n = pool.n + 1
  pool.n = n
  local b = pool[n]
  if not b then
    b = CreateFrame("Button", nil, parent)
    b:SetSize(MARK_HIT, MARK_HIT)
    b:EnableMouse(true)
    local t = b:CreateTexture(nil, "OVERLAY")
    t:SetSize(MARK_SIZE, MARK_SIZE)
    t:SetPoint("CENTER")
    b.tex = t
    b:SetScript("OnEnter", markEnter)
    b:SetScript("OnLeave", markLeave)
    pool[n] = b
    pool.max = n
  end
  b:ClearAllPoints()
  b:Show()
  return b
end

----------------------------------------------------------------------------
-- The ROTATION row: one cell per auto-to-auto cycle, showing the paper's casts
-- for that cycle position when they were played and what was played instead
-- when they were not. The hover reads the cycle off the frame — the scripts are
-- set once, at creation, so a rebuild creates no closures.
----------------------------------------------------------------------------

local function rotEnter(fr)
  local c = fr.cycle
  if not c then return end
  GameTooltip:SetOwner(fr, "ANCHOR_TOP")
  GameTooltip:AddLine("paper: " .. ((c.paper ~= "" and c.paper) or NONE_MARK), 0.74, 0.94, 0.78)
  GameTooltip:AddLine("you: " .. ((c.played ~= "" and c.played) or NONE_MARK), 1, 1, 1)
  if c.partial then GameTooltip:AddLine("cycle still open — not graded", 0.61, 0.59, 0.54) end
  GameTooltip:Show()
end

local function rotLeave() GameTooltip:Hide() end

local function poolRotCell(pool, parent)
  local n = pool.n + 1
  pool.n = n
  local fr = pool[n]
  if not fr then
    fr = CreateFrame("Frame", nil, parent)
    fr:SetHeight(ROT_H - 2)
    fr:EnableMouse(true)
    local fs = fr:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY - 2, "OUTLINE")
    fs:SetPoint("LEFT", fr, "LEFT", 2, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fr.text = fs
    fr:SetScript("OnEnter", rotEnter)
    fr:SetScript("OnLeave", rotLeave)
    pool[n] = fr
    pool.max = n
  end
  fr:ClearAllPoints()
  fr:Show()
  return fr
end

----------------------------------------------------------------------------
-- Small parts of the visual system: chips (a bordered pill with centred text,
-- auto-width) and stat tiles (large value / uppercase label). Both are
-- change-gated: a repaint with the same numbers writes nothing.
----------------------------------------------------------------------------

local function makeChip(parent, size, align)
  local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  c:SetHeight(CHIP_H)
  c:SetWidth(CHIP_MIN_W)
  Nock.UI.ApplyBackdrop(c, CHIP_BG, CHIP_BORDER)
  local fs = c:CreateFontString(nil, "OVERLAY")
  fs:SetFont(Nock.UI.GetFont(), size or SMALL_SIZE, "OUTLINE")
  if align == "LEFT" then
    fs:SetPoint("LEFT", c, "LEFT", CHIP_PAD / 2, 0)
    fs:SetJustifyH("LEFT")
  else
    fs:SetPoint("CENTER", c, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
  end
  fs:SetWordWrap(false)
  c.text = fs
  c._t, c._fill, c._max = nil, nil, nil
  return c
end

-- `maxW` is the room this chip has before it would reach whatever sits to its
-- right: the width is clamped into it and the string truncates rather than
-- sliding under the title bar's buttons on a narrow window.
local function setChip(chip, text, fill, ink, maxW)
  if chip._t == text and chip._fill == fill and chip._max == maxW then return end
  chip._t, chip._fill, chip._max = text, fill, maxW
  chip.text:SetWidth(0)
  chip.text:SetText(text)
  local w = (chip.text:GetStringWidth() or CHIP_MIN_W) + CHIP_PAD
  if maxW and w > maxW then w = maxW end
  if w < CHIP_MIN_W then w = CHIP_MIN_W end
  chip:SetWidth(w)
  chip.text:SetWidth(w - CHIP_PAD)
  if fill then
    chip:SetBackdropColor(fill[1], fill[2], fill[3], 1)
    chip:SetBackdropBorderColor(fill[1], fill[2], fill[3], 1)
  else
    chip:SetBackdropColor(CHIP_BG[1], CHIP_BG[2], CHIP_BG[3], CHIP_BG[4])
    chip:SetBackdropBorderColor(CHIP_BORDER[1], CHIP_BORDER[2], CHIP_BORDER[3], 1)
  end
  local col = ink or INK_DIM
  chip.text:SetTextColor(col[1], col[2], col[3])
end

-- A fault row's verdict chip: the severity plate, sized to its text and capped
-- at the column width so a long verdict cannot push the row apart.
local function setSevChip(chip, text, sev, maxW)
  if chip._t == text and chip._sev == sev then return end
  chip._t, chip._sev = text, sev
  local s = SEV[sev or "warn"] or SEV.warn
  chip.text:SetText(text)
  local w = (chip.text:GetStringWidth() or 20) + 10
  if w > maxW then w = maxW end
  chip:SetWidth(math.max(20, w))
  chip:SetBackdropColor(s.bg[1], s.bg[2], s.bg[3], s.bg[4])
  chip:SetBackdropBorderColor(s.ink[1], s.ink[2], s.ink[3], 0.45)
  chip.text:SetTextColor(s.ink[1], s.ink[2], s.ink[3])
end

-- A stat tile: the number, then what it is. Three of them and no more — the six
-- that used to sit here were a dashboard, and a dashboard is not a lesson.
local function makeStat(parent)
  local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  t:SetSize(80, STAT_H)
  Nock.UI.ApplyBackdrop(t, TILE_BG, BORDER)
  -- The severity rail across the top: the tile's verdict, readable before the
  -- number is. Colour follows the value's own colour index, so the two can
  -- never disagree.
  local rail = t:CreateTexture(nil, "OVERLAY")
  rail:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
  rail:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
  rail:SetHeight(STAT_RAIL_H)
  rail:SetColorTexture(RAIL_NEUTRAL[1], RAIL_NEUTRAL[2], RAIL_NEUTRAL[3], 1)
  local v = t:CreateFontString(nil, "OVERLAY")
  v:SetFont(Nock.UI.GetFont(), STAT_VALUE_SIZE, "OUTLINE")
  v:SetPoint("TOPLEFT", t, "TOPLEFT", 8, -(STAT_RAIL_H + 5))
  v:SetJustifyH("LEFT"); v:SetWordWrap(false)
  local k = t:CreateFontString(nil, "OVERLAY")
  k:SetFont(Nock.UI.GetFont(), SMALL_SIZE, "OUTLINE")
  k:SetPoint("TOPLEFT", t, "TOPLEFT", 8, -(STAT_H - 16))
  k:SetJustifyH("LEFT"); k:SetWordWrap(false)
  k:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])
  t.value, t.label, t.rail = v, k, rail
  t._vk, t._lk, t._c = nil, nil, nil
  return t
end

-- Change-gated tile writes. `vk` / `lk` are the NUMBERS the text is made from:
-- string.format only runs when one of them actually moves.
local function statValue(tile, vk, colIdx, fmt, a, b)
  if tile._vk == vk and tile._c == colIdx then return end
  tile._vk, tile._c = vk, colIdx
  tile.value:SetText(fmt:format(a, b))
  local col = STAT_COLOR[colIdx] or INK
  tile.value:SetTextColor(col[1], col[2], col[3])
  local rc = STAT_RAIL[colIdx] or RAIL_NEUTRAL
  tile.rail:SetColorTexture(rc[1], rc[2], rc[3], 1)
end

local function statLabel(tile, lk, fmt, a, b)
  if tile._lk == lk then return end
  tile._lk = lk
  tile.label:SetText(fmt:format(a, b))
end

-- Every tile back to an em dash: no fight, or one whose numbers do not exist yet.
local function blankTiles(stats)
  for i = 1, #stats do
    statValue(stats[i], "-", 4, "%s", NONE_MARK)
    statLabel(stats[i], "-", "%s", "")
  end
end

-- m:ss, for the title bar's chip.
local function clockText(sec)
  local s = math.floor((sec or 0) + 0.5)
  if s < 0 then s = 0 end
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

----------------------------------------------------------------------------
-- Fix cards
----------------------------------------------------------------------------

-- Both card buttons read what they act on off the button itself: the scripts
-- are installed once, at creation, so a rebuild creates no closures.
local function cardDrillClick(btn)
  local p = practice()
  if p and btn.drill then p:LoadDrill(btn.drill) end
end

local function cardLessonClick(btn)
  local p = practice()
  if p and p.PushLadder then p:PushLadder() end
  local v = Nock:GetModule("PracticeLessonView", true)
  if v and v.ShowStep then v:ShowStep(btn.step or 1) end
end

local function makeCard(parent)
  local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  c:SetHeight(CARD_H)
  Nock.UI.ApplyBackdrop(c, CARD_BG, BORDER)
  -- The left rule carries the severity: red for a cost in autos, amber for the
  -- rest, the same reading the fault rows' chips give.
  local rule = c:CreateTexture(nil, "OVERLAY")
  rule:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
  rule:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, 0)
  rule:SetWidth(CARD_RULE_W)
  rule:SetColorTexture(BAD[1], BAD[2], BAD[3], 1)

  local eyebrow = c:CreateFontString(nil, "OVERLAY")
  eyebrow:SetFont(Nock.UI.GetFont(), SMALL_SIZE, "OUTLINE")
  eyebrow:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD + CARD_RULE_W, -CARD_PAD)
  eyebrow:SetJustifyH("LEFT"); eyebrow:SetWordWrap(false)
  eyebrow:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])

  -- Both texts WRAP: the advice is a sentence, not a label. The title grows
  -- down from the eyebrow and the sentence grows UP off the buttons, so a long
  -- one eats the gap between them rather than sliding under the row of doors.
  local title = c:CreateFontString(nil, "OVERLAY")
  title:SetFont(Nock.UI.GetFont(), CARD_TITLE_SIZE, "OUTLINE")
  title:SetPoint("TOPLEFT", eyebrow, "BOTTOMLEFT", 0, -4)
  title:SetJustifyH("LEFT"); title:SetWordWrap(true)
  -- The belt to CARD_H's braces: the card is sized for three title lines, so a
  -- fourth (a longer advice string added later, or a wide LSM font) truncates
  -- rather than growing down into the body. Guarded: the method is not on the
  -- Anniversary API allowlist and a missing one must degrade, not throw.
  if title.SetMaxLines then title:SetMaxLines(3) end
  title:SetTextColor(INK[1], INK[2], INK[3])

  local body = c:CreateFontString(nil, "OVERLAY")
  body:SetFont(Nock.UI.GetFont(), BODY_SIZE, "OUTLINE")
  body:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", CARD_PAD + CARD_RULE_W, CARD_PAD + CARD_BTN_H + 4)
  body:SetJustifyH("LEFT"); body:SetWordWrap(true)
  body:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])

  local drill = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
  drill:SetHeight(CARD_BTN_H)
  drill:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", CARD_PAD + CARD_RULE_W, CARD_PAD - 2)
  drill:SetScript("OnClick", cardDrillClick)

  local lesson = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
  lesson:SetHeight(CARD_BTN_H)
  lesson:SetPoint("LEFT", drill, "RIGHT", 4, 0)
  lesson:SetScript("OnClick", cardLessonClick)

  -- The replay strip: PAPER over YOU, one cycle wide.
  local strip = CreateFrame("Frame", nil, c, "BackdropTemplate")
  strip:SetPoint("TOPRIGHT", c, "TOPRIGHT", -CARD_PAD, -CARD_PAD)
  strip:SetHeight(CARD_H - CARD_PAD * 2)
  Nock.UI.ApplyBackdrop(strip, STRIP_BG, BORDER)
  local paperLab = strip:CreateFontString(nil, "OVERLAY")
  paperLab:SetFont(Nock.UI.GetFont(), SMALL_SIZE, "OUTLINE")
  paperLab:SetPoint("TOPLEFT", strip, "TOPLEFT", 5, REPLAY_LANE_Y[1] - 5)
  paperLab:SetText("PAPER")
  paperLab:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
  local youLab = strip:CreateFontString(nil, "OVERLAY")
  youLab:SetFont(Nock.UI.GetFont(), SMALL_SIZE, "OUTLINE")
  youLab:SetPoint("TOPLEFT", strip, "TOPLEFT", 5, REPLAY_LANE_Y[2] - 5)
  youLab:SetText("YOU")
  youLab:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])
  local cap = strip:CreateFontString(nil, "OVERLAY")
  cap:SetFont(Nock.UI.GetFont(), SMALL_SIZE, "OUTLINE")
  cap:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -5, 4)
  cap:SetJustifyH("RIGHT"); cap:SetWordWrap(false)
  cap:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])

  c.rule, c.eyebrow, c.title, c.body = rule, eyebrow, title, body
  c.drill, c.lesson, c.strip, c.cap = drill, lesson, strip, cap
  c.pools = { bar = newPool(), edge = newPool(), label = newPool() }
  c.replay = {}                       -- ONE T.Replay out per card slot, reused
  c._eb, c._ti, c._bo, c._cap, c._sev = nil, nil, nil, nil, nil
  c:Hide()
  return c
end

-- A button that says what it does, sized to its own text.
local function setCardButton(btn, text)
  if btn._t ~= text then
    btn._t = text
    btn:SetText(text)
    local fs = btn:GetFontString()
    local w = (fs and fs:GetStringWidth() or 60) + 18
    btn:SetWidth(w)
  end
  btn:Show()
end

----------------------------------------------------------------------------
-- Collapsible sections: a header button that shows/hides one body frame. The
-- open state is a session's, not the profile's — a fold is a reading choice
-- made about THIS fight.
----------------------------------------------------------------------------

local function sectionClick(btn)
  local v = View
  v[btn.stateKey] = not v[btn.stateKey]
  v:PaintSections()
  v:Layout()
end

local function makeSection(parent, stateKey)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(SECT_H)
  b.stateKey = stateKey
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)
  local fs = b:CreateFontString(nil, "OVERLAY")
  fs:SetFont(Nock.UI.GetFont(), BODY_SIZE - 1, "OUTLINE")
  fs:SetPoint("LEFT", b, "LEFT", 2, 0)
  fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
  fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  b.text = fs
  b._t = nil
  b:SetScript("OnClick", sectionClick)
  return b
end

-- ASCII only: the header's fold marker is drawn in the user's LibSharedMedia
-- font, and most of them have no triangle glyph at all.
local function setSection(btn, open, fmt, a, b)
  local key = (open and "1" or "0") .. tostring(a) .. "/" .. tostring(b)
  if btn._t == key then return end
  btn._t = key
  btn.text:SetText((open and "[-] " or "[+] ") .. fmt:format(a, b))
end

----------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------

local function rowClick(btn)
  local v = View
  local mk = btn.mark
  if not (mk and v._pps) then return end
  v:SetScroll((mk.t - v._t0) * v._pps - v._laneW / 3)
end

-- The fault list's wheel and slider. File-locals so the scripts are installed
-- once and allocate nothing per notch.
local function issueWheel(_, delta)
  View:ApplyIssueScroll((View._issueScroll or 0) - delta * WHEEL_ROWS * ROW_H)
end

local function issueSliderChanged(_, value)
  if View._issueSyncing then return end
  View:ApplyIssueScroll(value)
end

function View:OnInitialize()
  -- The workbench's Review PAGE when there is one (shell step 4): the same
  -- rows, in the room under the panel, at the page's width; no title-bar
  -- chrome of its own. A floating window without a workbench.
  local wb = Nock:GetModule("PracticeWorkbench", true)
  local host = wb and wb.PageFrame and wb:PageFrame() or nil
  self._host = host
  local f
  if host then
    f = CreateFrame("Frame", "NockPracticeTimeline", host)
    f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    f:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    f:SetHeight(240)
  else
    f = CreateFrame("Frame", "NockPracticeTimeline", UIParent, "BackdropTemplate")
    f:SetSize(profile("practiceTimelineWidth", 720), 240)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
  end
  -- Practice windows are tools, not HUD chrome: draggable whenever no fight
  -- runs, regardless of the global lock — locked only while a fight is on.
  -- (Hosted, nothing drags: the workbench owns the position.)
  local function dragStart()
    if host or Nock.state.sim.fightOn then return end
    f:StartMoving()
  end
  local function dragStop()
    if host then return end
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    Nock.db.profile.practiceTimelinePos = { point = point, relPoint = relPoint, x = x, y = y }
  end
  if not host then
    f:SetScript("OnDragStart", dragStart)
    f:SetScript("OnDragStop", dragStop)
    Nock.UI.RegisterPanelBackground(f)
    -- The practice scale (Options -> Practice), top-level frame only.
    Nock.UI.RegisterPracticeScale(f)
    local pos = profile("practiceTimelinePos", nil)
    if pos then f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, -120) end
  end

  ------------------------------------------------------------------------
  -- Row 1: title bar. The bar itself is the drag handle (same gate).
  ------------------------------------------------------------------------
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD)
  bar:SetHeight(TITLE_H)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", dragStart)
  bar:SetScript("OnDragStop", dragStop)

  -- Grip: three short vertical rules, the mock's drag affordance (floating).
  if not host then
    for i = 1, 3 do
      local t = bar:CreateTexture(nil, "ARTWORK")
      t:SetColorTexture(0.5, 0.5, 0.54, 0.7)
      t:SetSize(1, 12)
      t:SetPoint("LEFT", bar, "LEFT", (i - 1) * 3, 0)
    end
  end

  local title = bar:CreateFontString(nil, "OVERLAY")
  if host then
    Skin.Font(title, "display", Skin.SIZES.h2)
    title:SetPoint("LEFT", bar, "LEFT", 0, 0)
    Skin.Text(title, "ink")
  else
    title:SetFont(Nock.UI.GetFont(), TITLE_SIZE, "OUTLINE")
    title:SetPoint("LEFT", bar, "LEFT", 16, 0)
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  end
  title:SetText("FIGHT REVIEW")

  -- Buttons, right to left. Children of the bar, so they take the mouse before
  -- the bar's own drag does — and built before the chips, which are clamped to
  -- the room left over beside them. Hosted, the workbench has the close: a
  -- zero-width stand-in keeps the anchors.
  local close
  if host then
    close = CreateFrame("Frame", nil, bar)
    close:SetSize(1, 1)
  else
    close = Nock.UI.CloseButton(bar, CLOSE_W, function() View:Toggle(false) end)
  end
  close:SetPoint("RIGHT", bar, "RIGHT", 0, 0)

  local scenChip = makeChip(bar)
  scenChip:SetPoint("LEFT", title, "RIGHT", 8, 0)
  local infoChip = makeChip(bar, nil, "LEFT")
  infoChip:SetPoint("LEFT", scenChip, "RIGHT", 6, 0)

  local copy
  if host then
    copy = Skin.Button(bar, "Copy report", "ghost", COPY_W)
  else
    copy = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    copy:SetSize(COPY_W, 22)
    copy:SetText("Copy report")
  end
  copy:SetPoint("RIGHT", close, "LEFT", host and 0 or -BTN_GAP, 0)
  copy:SetScript("OnClick", function()
    local p = practice()
    if not p then return end
    local text = p:BuildReport()
    if text then Nock.UI.ShowCopyBox(text) else p:Print("Practice: no fight to report yet.") end
  end)

  ------------------------------------------------------------------------
  -- Row 2: the headline — the grade, what it is made of, and the sentence.
  ------------------------------------------------------------------------
  local headline = CreateFrame("Frame", nil, f)
  headline:SetHeight(HEADLINE_H)

  local grade = headline:CreateFontString(nil, "OVERLAY")
  grade:SetFont(Nock.UI.GetFont(), GRADE_SIZE, "OUTLINE")
  grade:SetPoint("TOPLEFT", headline, "TOPLEFT", 0, -2)
  grade:SetWidth(GRADE_W)
  grade:SetJustifyH("LEFT"); grade:SetWordWrap(false)
  grade:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  -- The grade is the one number a drill is judged by, so the block explains
  -- itself on hover: what a cycle ON PAPER is, and what the letter needs.
  -- EnableMouse on a child swallows the drag that would otherwise reach the
  -- window, so it carries the same two handlers the title bar does.
  local gradeHit = CreateFrame("Frame", nil, headline)
  gradeHit:SetPoint("TOPLEFT", headline, "TOPLEFT", 0, 0)
  gradeHit:SetSize(GRADE_W, HEADLINE_H)
  gradeHit:EnableMouse(true)
  gradeHit:RegisterForDrag("LeftButton")
  gradeHit:SetScript("OnDragStart", dragStart)
  gradeHit:SetScript("OnDragStop", dragStop)
  gradeHit:SetScript("OnEnter", function(self)
    if not self._pct then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(("Cycles on paper: %d of %d (%d %%)"):format(self._ok or 0, self._total or 0, self._pct), 1, 1, 1)
    GameTooltip:AddLine("A cycle runs from one auto release to the next. It is ON PAPER when its"
      .. " notes were played in paper order — the same shots and weaves, in the same sequence,"
      .. " nothing missing and nothing extra. The paper is rebuilt for each haste window, at"
      .. " that window's own notation and haste.", 0.74, 0.94, 0.78, true)
    GameTooltip:AddLine(("A+ 95 %%, A 90 %%, B+ 85 %%, B 75 %%, C 60 %%, else D. Three clips or more"
      .. " caps the grade at B. Best streak this fight: %d notes."):format(self._streak or 0), 0.61, 0.59, 0.54, true)
    GameTooltip:Show()
  end)
  gradeHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local headText = headline:CreateFontString(nil, "OVERLAY")
  headText:SetFont(Nock.UI.GetFont(), HEAD_SIZE, "OUTLINE")
  headText:SetPoint("TOPLEFT", headline, "TOPLEFT", GRADE_W + 8, -4)
  headText:SetJustifyH("LEFT"); headText:SetWordWrap(false)
  headText:SetTextColor(INK[1], INK[2], INK[3])

  local subText = headline:CreateFontString(nil, "OVERLAY")
  subText:SetFont(Nock.UI.GetFont(), SUB_SIZE, "OUTLINE")
  subText:SetPoint("TOPLEFT", headText, "BOTTOMLEFT", 0, -4)
  subText:SetJustifyH("LEFT"); subText:SetWordWrap(true)
  subText:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])

  headline.grade, headline.hit, headline.head, headline.sub = grade, gradeHit, headText, subText
  headline._gk, headline._hk, headline._sk = nil, nil, nil

  -- The empty state. Before the FIRST fight of a session there is no grade to
  -- dash out and no stats to blank — a grid of em dashes reads as a broken
  -- window, so the whole headline stands down and one centred line takes its
  -- place. After a fight has been reviewed the headline comes back for good:
  -- from then on a blank means "that drill is over", which is a different thing.
  local empty = f:CreateFontString(nil, "OVERLAY")
  empty:SetFont(Nock.UI.GetFont(), BODY_SIZE, "OUTLINE")
  empty:SetJustifyH("CENTER"); empty:SetJustifyV("MIDDLE")
  empty:SetWordWrap(true)
  empty:SetHeight(EMPTY_H)
  -- A width before the first ApplyWidth, or the centring has nothing to centre in.
  empty:SetWidth((f:GetWidth() or 400) - PAD * 2)
  empty:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])
  empty:SetText("No fight yet - your last drill's review lands here.")
  empty:Hide()
  f.empty = empty

  ------------------------------------------------------------------------
  -- Row 3: three stat tiles.
  ------------------------------------------------------------------------
  local statsRow = CreateFrame("Frame", nil, f)
  statsRow:SetHeight(STAT_H)
  local stats = {}
  for i = 1, NSTATS do stats[i] = makeStat(statsRow) end

  ------------------------------------------------------------------------
  -- Row 4: up to three fix cards.
  ------------------------------------------------------------------------
  local cards = {}
  for i = 1, MAX_CARDS do cards[i] = makeCard(f) end

  ------------------------------------------------------------------------
  -- Row 5: Rotation — the cycle cells, on their own scroll frame so they can
  -- fold away without the lanes. Both scroll frames run off ONE offset.
  ------------------------------------------------------------------------
  local rotHeader = makeSection(f, "_openRot")
  local rotBody = CreateFrame("Frame", nil, f)
  rotBody:SetHeight(ROT_BODY_H)
  local rotScroll = CreateFrame("ScrollFrame", nil, rotBody)
  rotScroll:SetPoint("TOPLEFT", rotBody, "TOPLEFT", LABEL_W, 0)
  rotScroll:SetSize(200, ROT_H)
  local rotContent = CreateFrame("Frame", nil, rotScroll)
  rotContent:SetSize(200, ROT_H)
  rotScroll:SetScrollChild(rotContent)
  local rotLabel = rotBody:CreateFontString(nil, "OVERLAY")
  rotLabel:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY - 2, "OUTLINE")
  rotLabel:SetPoint("TOPLEFT", rotBody, "TOPLEFT", 0, -1)
  rotLabel:SetWidth(LABEL_W - 2)
  rotLabel:SetJustifyH("LEFT")
  rotLabel:SetText("cycles")
  rotLabel:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])

  ------------------------------------------------------------------------
  -- Row 6: Details — the lanes, the slider, the two meta lines and the fault
  -- list. Everything here is a child of one body frame, so the fold is one
  -- Show/Hide.
  ------------------------------------------------------------------------
  local detHeader = makeSection(f, "_openDetails")
  local detBody = CreateFrame("Frame", nil, f)

  local laneLabels = {}
  for i = 1, #LANES do
    local fs = detBody:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY - 2, "OUTLINE")
    fs:SetPoint("TOPLEFT", detBody, "TOPLEFT", 0, -((i - 1) * LANE_H + 2))
    fs:SetWidth(LABEL_W - 2)
    fs:SetJustifyH("LEFT")
    fs:SetText(LANES[i])
    fs:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])
    laneLabels[i] = fs
  end

  local scroll = CreateFrame("ScrollFrame", "NockPracticeTimelineScroll", detBody)
  scroll:SetPoint("TOPLEFT", detBody, "TOPLEFT", LABEL_W, 0)
  scroll:SetSize(200, LANE_AREA_H)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, delta)
    local step = (IsShiftKeyDown() and 10 or 2) * (View._pps or 80)
    View:SetScroll((View._scroll or 0) - delta * step)
  end)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(200, LANE_AREA_H)
  scroll:SetScrollChild(content)

  local slider = CreateFrame("Slider", nil, detBody)
  slider:SetOrientation("HORIZONTAL")
  slider:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -2)
  slider:SetSize(200, SLIDER_H)
  slider:SetMinMaxValues(0, 1)
  slider:SetValue(0)
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.06)
  local thumb = slider:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(0.75, 0.75, 0.75, 0.8)
  thumb:SetSize(24, SLIDER_H)
  slider:SetThumbTexture(thumb)
  slider:SetScript("OnValueChanged", function(_, value)
    if View._syncing then return end
    View:SetScroll(value)
  end)

  -- The numbers the six tiles used to carry, as two folded-away lines.
  local meta = detBody:CreateFontString(nil, "OVERLAY")
  meta:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY - 1, "OUTLINE")
  meta:SetPoint("TOPLEFT", detBody, "TOPLEFT", 0, -(LANE_AREA_H + 2 + SLIDER_H + 3))
  meta:SetJustifyH("LEFT"); meta:SetWordWrap(false)
  meta:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])
  local windowsLine = detBody:CreateFontString(nil, "OVERLAY")
  windowsLine:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY - 1, "OUTLINE")
  windowsLine:SetPoint("TOPLEFT", meta, "BOTTOMLEFT", 0, -2)
  windowsLine:SetJustifyH("LEFT"); windowsLine:SetWordWrap(false)
  windowsLine:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])

  -- The fault list is a viewport MAX_ROWS tall over a pool that grows to the
  -- fight's whole issue count: everything is reachable, nothing is truncated.
  local issueScroll = CreateFrame("ScrollFrame", nil, detBody)
  issueScroll:SetPoint("TOPLEFT", detBody, "TOPLEFT", 0, -(LANE_AREA_H + 2 + SLIDER_H + 3 + META_H))
  issueScroll:SetSize(200, MAX_ROWS * ROW_H)
  issueScroll:SetClipsChildren(true)
  issueScroll:EnableMouseWheel(true)
  issueScroll:SetScript("OnMouseWheel", issueWheel)
  local issueContent = CreateFrame("Frame", nil, issueScroll)
  issueContent:SetSize(200, MAX_ROWS * ROW_H)
  issueScroll:SetScrollChild(issueContent)

  -- Same styling as the timeline's horizontal slider, stood on end.
  local issueSlider = CreateFrame("Slider", nil, detBody)
  issueSlider:SetOrientation("VERTICAL")
  issueSlider:SetPoint("TOPLEFT", issueScroll, "TOPRIGHT", 2, 0)
  issueSlider:SetSize(ISSUE_SLIDER_W, MAX_ROWS * ROW_H)
  issueSlider:SetMinMaxValues(0, 1)
  issueSlider:SetValue(0)
  local iTrack = issueSlider:CreateTexture(nil, "BACKGROUND")
  iTrack:SetAllPoints()
  iTrack:SetColorTexture(1, 1, 1, 0.06)
  local iThumb = issueSlider:CreateTexture(nil, "OVERLAY")
  iThumb:SetColorTexture(0.75, 0.75, 0.75, 0.8)
  iThumb:SetSize(ISSUE_SLIDER_W, 24)
  issueSlider:SetThumbTexture(iThumb)
  issueSlider:SetScript("OnValueChanged", issueSliderChanged)
  -- The slider takes the wheel too: it sits right against the list, and a notch
  -- rolled a couple of pixels off the rows' right edge should not do nothing.
  issueSlider:EnableMouseWheel(true)
  issueSlider:SetScript("OnMouseWheel", issueWheel)
  issueSlider:Hide()

  f.title, f.scenChip, f.infoChip, f.copy, f.close = title, scenChip, infoChip, copy, close
  f.headline, f.statsRow, f.stats, f.cards = headline, statsRow, stats, cards
  f.rotHeader, f.rotBody, f.detHeader, f.detBody = rotHeader, rotBody, detHeader, detBody
  f.laneLabels, f.meta, f.windowsLine, f.rows = laneLabels, meta, windowsLine, {}

  self.frame, self.scroll, self.content = f, scroll, content
  self.rotScroll, self.rotContent = rotScroll, rotContent
  self.slider = slider
  self.issueScroll, self.issueContent, self.issueSlider = issueScroll, issueContent, issueSlider
  self.pools = {
    grid = newPool(), bar = newPool(), edge = newPool(), icon = newPool(),
    label = newPool(), axis = newPool(), mark = newPool(), rot = newPool(),
  }
  -- Every per-rebuild table, allocated once here.
  self._liveCounters = {}
  self._opts = {}
  self._scroll, self._pps, self._t0 = 0, 80, 0
  self._laneW, self._contentW = 200, 200
  -- Nothing below the headline exists until a fight has been graded, and the
  -- headline itself stands down until the session's first one has been.
  self._nCards, self._final = 0, false
  self._everFinal, self._showEmpty = false, true
  statsRow:Hide(); rotHeader:Hide(); rotBody:Hide(); detHeader:Hide(); detBody:Hide()
  -- Session fold state: the rotation is the thing a review is read for, the
  -- lanes are what it is checked against.
  self._openRot, self._openDetails = true, false
  -- The fault count the list was last laid out at: a rebuild that produces the
  -- same count keeps the reader's scroll (see LayoutIssues).
  self._issueCount = 0
  -- Fault-row column geometry, computed once per width and reused by every row
  -- the pool grows later.
  self._rowCols = { w = {}, x = {}, chipX = 0 }
  self._rowW = 200
  self._issueScroll, self._issueViewH, self._issueTotalH = 0, 0, 0
  if host and wb.RegisterPage then wb:RegisterPage("review", f, self) end
  f:Hide()
end

-- The workbench's page contract.
-- The PAGE is read on purpose: it shows the review whatever the flag says
-- (the flag gates the window opening ITSELF when a fight ends). With it off
-- the page said "no fight yet" after a thirty-second drill (user, 2026-08-26).
function View:OnPageShow()
  self:Rebuild()
end
function View:PageHeight() return self._pageH or 240 end

----------------------------------------------------------------------------
-- Fault rows: created on demand, never destroyed, laid out from _rowCols.
----------------------------------------------------------------------------

function View:LayoutIssueRow(b)
  local rc = self._rowCols
  b:SetWidth(self._rowW)
  for j = 1, 4 do
    local fs = b.cols[j]
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", b, "LEFT", rc.x[j], 0)
    fs:SetWidth(rc.w[j])
  end
  b.chip:ClearAllPoints()
  b.chip:SetPoint("LEFT", b, "LEFT", rc.chipX, 0)
end

-- Row i of the pool, built the first time a fight has that many issues. Only
-- ever called from a rebuild — never from the tick.
function View:IssueRow(i)
  local rows = self.frame.rows
  local b = rows[i]
  if b then return b end
  b = CreateFrame("Button", nil, self.issueContent)
  b:SetHeight(ROW_H)
  if i == 1 then b:SetPoint("TOPLEFT", self.issueContent, "TOPLEFT", 0, 0)
  else b:SetPoint("TOPLEFT", self:IssueRow(i - 1), "BOTTOMLEFT", 0, 0) end
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  b.cols = {}
  for j = 1, 4 do
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY - 2, "OUTLINE")
    fs:SetPoint("LEFT", b, "LEFT", 0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    b.cols[j] = fs
  end
  -- The verdict column is a severity chip, one per row and reused: mouse
  -- stays off it so the row underneath keeps the click that jumps the lanes.
  local chip = CreateFrame("Frame", nil, b, "BackdropTemplate")
  chip:SetHeight(ROW_H - 2)
  chip:EnableMouse(false)
  Nock.UI.ApplyBackdrop(chip, SEV.warn.bg, CHIP_BORDER)
  local ct = chip:CreateFontString(nil, "OVERLAY")
  ct:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY - 2, "OUTLINE")
  ct:SetPoint("CENTER", chip, "CENTER", 0, 0)
  ct:SetWordWrap(false)
  chip.text = ct
  chip._t, chip._sev = nil, nil
  b.chip = chip
  b:SetScript("OnClick", rowClick)
  b:Hide()
  rows[i] = b
  self:LayoutIssueRow(b)
  return b
end

function View:OnEnable()
  TL = Nock.PracticeTimeline
  GR = Nock.PracticeGrader
  LADDER = Nock.PracticeLadder
  LESSON = Nock.PracticeLesson
  self:RegisterMessage("NOCK_PRACTICE_TIMELINE_TOGGLE", "OnToggleMessage")
  self:RegisterMessage("NOCK_PRACTICE_FIGHT_DONE", "OnFightDone")
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "OnPracticeChanged")
  self:RegisterMessage("NOCK_PRACTICE_RESET_POS", "ResetPos")
end

-- /nock practice reset: back to the default anchor, drop the saved position.
function View:ResetPos()
  local f = self.frame
  if not f or self._host then return end
  Nock.db.profile.practiceTimelinePos = nil
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
end

----------------------------------------------------------------------------
-- Show / hide
----------------------------------------------------------------------------

-- THE REVIEW IS OFF WHILE THE ENGINE IS TUNED (R8b). One profile flag, read
-- here rather than cached: it is a checkbox in Options and a fight is not a
-- tick path. Every code path into the window goes through this, so nothing
-- opens it while the flag is down -- and the flag alone brings it all back.
function reviewOn()
  local p = Nock.db and Nock.db.profile
  return (p and p.practiceReviewEnabled) == true
end
-- ASCII only: the user's chosen LibSharedMedia font may have no dash.
local REVIEW_OFF_MSG =
  "Practice review is disabled while the engine is tuned - /nock practice report still works."

function View:OnToggleMessage()
  -- Hosted, the page opens on request whatever the flag says (a page reached
  -- by hand is deliberate); floating, the flag still gates the window.
  -- Asked for by name -- the slash command, or a button that has not noticed
  -- the flag. One line back, rather than a window that does not open. (The
  -- page too: with the flag down the rail does not offer it -- user, 2026-08-26.)
  if not reviewOn() then return Nock:Print(REVIEW_OFF_MSG) end
  if self._host then return self:Toggle(true) end
  self:Toggle(not self.frame:IsShown())
end

function View:Toggle(show)
  -- The last gate, so no future caller can open it behind the flag's back.
  -- Closing is always allowed. (Hosted: the page, on request.)
  if show and not reviewOn() then return end
  if self._host then
    local wb = workbench()
    if not wb then return end
    if show then
      if wb.Open then wb:Open() end
      wb:Select("review")
    else
      wb:Select("stage")
    end
    return
  end
  if show then
    self.frame:Show()
    self:Rebuild()
  else
    self.frame:Hide()
  end
end

-- The fight ended: open the window on the finished timeline, from the pull.
function View:OnFightDone()
  -- Off: the fight ends and nothing opens. Not even a rebuild -- with the flag
  -- down the window cannot be up in the first place.
  if not reviewOn() then
    if self.frame:IsShown() then self.frame:Hide() end
    return
  end
  self._scroll = 0
  -- Still in real combat: the fight ended because the auto-stop fired on a
  -- stray mob, and a window popping open over the fight is the last thing the
  -- player needs. Rebuild it if it is already up; otherwise leave it closed.
  local st = Nock.state
  local inCombat = st and st.player and st.player.inCombat
  if self._host then
    -- Stop returns to the window on Review (the "Workbench States" page).
    if not inCombat then self:Toggle(true) end
    if self.frame:IsShown() then self:Rebuild() end
    return
  end
  if not inCombat then self.frame:Show() end
  if not self.frame:IsShown() then return end
  self:Rebuild()
end

-- Practice itself changed under us: a pull, a stop, a proc, or the whole drill
-- ending. With the drill off there is nothing to draw — leave no lanes and no
-- analysis from a fight that is over.
function View:OnPracticeChanged()
  if not self.frame:IsShown() then return end
  if not Nock.state.sim.active then
    self.tl = nil
    self.cycles = nil
    self:Blank()
    self:PaintTitle()
    self:Layout()
  else
    self:Rebuild()
  end
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------

-- Fault row columns: t · verdict · you did · expected · cost. Kept on the view
-- (`_rowCols`) so a row the pool grows later lays itself out the same way, and
-- computed on EVERY ApplyWidth — before the width early-return — so the table
-- is never half-built when LayoutIssueRow reads it.
function View:ComputeRowCols(rowW)
  local tw, vw, cw, gap = 40, 116, 74, 4
  local rest = rowW - tw - vw - cw - gap * 4
  if rest < 80 then rest = 80 end
  local dw = math.floor(rest * 0.45)
  local ew = rest - dw
  local rc = self._rowCols
  rc.w[1], rc.w[2], rc.w[3], rc.w[4] = tw, dw, ew, cw
  rc.x[1] = 0
  rc.x[2] = tw + gap + vw + gap
  rc.x[3] = rc.x[2] + dw + gap
  rc.x[4] = rc.x[3] + ew + gap
  rc.chipX = tw + gap
  self._chipMaxW = vw
end

-- The window's own width, applied before a paint so a changed setting takes
-- effect on the next rebuild. The blocks are only re-laid when the width moved.
function View:ApplyWidth()
  -- Hosted, the width is the page's; the setting is the floating window's.
  local w = self._host and (self._host:GetWidth() or 960) or profile("practiceTimelineWidth", 600)
  if w < 240 then w = 240 end
  local laneW = w - PAD * 2 - LABEL_W
  if laneW < 100 then laneW = 100 end
  if not self._host then self.frame:SetWidth(w) end
  self.scroll:SetSize(laneW, LANE_AREA_H)
  self.rotScroll:SetSize(laneW, ROT_H)
  self.slider:SetWidth(laneW)
  self._laneW, self._innerW = laneW, w - PAD * 2
  -- The fault rows leave the slider's lane free whether or not it is shown, so
  -- the columns don't reflow when a fight crosses MAX_ROWS issues.
  local rowW = self._innerW - ISSUE_SLIDER_W - 2
  if rowW < 100 then rowW = 100 end
  self._rowW = rowW
  self.issueScroll:SetWidth(rowW)
  self.issueContent:SetWidth(rowW)
  self:ComputeRowCols(rowW)
  if self._appliedW == w then return end
  self._appliedW = w
  local iw = self._innerW
  local f = self.frame
  -- Title-bar room for the two chips: the bar minus the title, the buttons and
  -- the four gaps between them. Both chips are clamped into it (PaintTitle), so
  -- a 400 px window truncates their text instead of running it under the
  -- buttons, which are anchored to the bar's right edge.
  self._chipRoom = iw - 16 - (f.title:GetStringWidth() or 90) - 8 - 6
    - (COPY_W + CLOSE_W + BTN_GAP) - 6
  f.headline:SetWidth(iw)
  f.headline.head:SetWidth(iw - GRADE_W - 8)
  f.headline.sub:SetWidth(iw - GRADE_W - 8)
  f.empty:SetWidth(iw)
  f.statsRow:SetWidth(iw)
  f.rotHeader:SetWidth(iw)
  f.rotBody:SetWidth(iw)
  f.detHeader:SetWidth(iw)
  f.detBody:SetWidth(iw)
  f.meta:SetWidth(iw)
  f.windowsLine:SetWidth(iw)
  local statW = math.floor((iw - STAT_GAP * (NSTATS - 1)) / NSTATS)
  if statW < 60 then statW = 60 end
  for i = 1, NSTATS do
    local t = f.stats[i]
    t:SetSize(statW, STAT_H)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", f.statsRow, "TOPLEFT", (i - 1) * (statW + STAT_GAP), 0)
  end
  -- A card is the sentence plus a replay strip: the strip takes its share of
  -- the width and the text takes the rest, with the text winning when the
  -- window is narrow (a fix you cannot read is not a fix).
  local rw = math.floor(iw * 0.45)
  if rw > REPLAY_MAX_W then rw = REPLAY_MAX_W end
  if rw < REPLAY_MIN_W then rw = REPLAY_MIN_W end
  local leftW = iw - rw - CARD_PAD * 3 - CARD_RULE_W
  if leftW < 140 then
    leftW = 140
    rw = iw - leftW - CARD_PAD * 3 - CARD_RULE_W
    if rw < 60 then rw = 60 end
  end
  self._replayW, self._cardLeftW = rw, leftW
  for i = 1, MAX_CARDS do
    local c = f.cards[i]
    c:SetWidth(iw)
    c.strip:SetWidth(rw)
    c.eyebrow:SetWidth(leftW)
    c.title:SetWidth(leftW)
    c.body:SetWidth(leftW)
  end
  -- The columns themselves are already computed (ComputeRowCols, above the
  -- early-return); only the existing rows need re-laying to the new width.
  local rows = f.rows
  for i = 1, #rows do self:LayoutIssueRow(rows[i]) end
end

-- One rebuild, in whichever of the two shapes the drill is actually in:
--   * mid   — a fight runs: the headline alone, on the grader's live counters.
--             Percentages and fault lists mid-fight are a distraction; the
--             streak is the only number that should move while you play.
--   * final — no fight: the grade, the three stats, the fix cards and the two
--             folded sections.
function View:Rebuild()
  local p, T = practice(), TL
  if not (p and T) then return end
  self:ApplyWidth()
  local fightOn = Nock.state.sim.fightOn and true or false
  local events, n, score, h, verdicts = p:TimelineData()
  -- An EMPTY stream is nothing to review, fight running or not: a cancelled
  -- (armed, never pulled) fight, or one still ARMED with the window opened on
  -- top of it. There is no `pull` to date it, so T.Build would fall back to
  -- t0 = 0 and lay the PREVIOUS fight's scorecard against seven-digit GetTime
  -- stamps. Nothing happened: blank it, exactly as before the first fight.
  if not (events and h) or n == 0 then
    self.tl = nil
    self.cycles = nil
    self:Blank()
    self:PaintTitle()
    self:Layout()
    return
  end
  if fightOn then
    -- Mid-fight: no lanes, no cards, no scorecard. The one live reading is the
    -- grader's own approximate cycle count and the streak.
    self.tl = nil
    self.cycles = nil
    self:HideFinal()
    -- A fight is running: the live headline IS the content, empty state or not.
    self._showEmpty = false
    self:PaintHeadlineLive(p)
    self:PaintTitle()
    self:Layout()
    return
  end
  local opts = self._opts
  opts.model = Nock.PracticeModel
  opts.windup = 0.5 / (h.rangedMul or 1)
  opts.okMarks = profile("practiceTimelineOkMarks", false) and true or false
  local tl = T.Build(events, n, score, h, opts, verdicts)
  self.tl = tl
  -- The rotation row: pooled on the view, so a rebuild reuses last fight's
  -- cycle tables and only re-joins the strings that actually moved.
  self._cycles = T.Cycles(events, n, score, h, opts.model, self._cycles)
  self.cycles = self._cycles
  self:Paint(tl)
  self:PaintHeadline(score)
  self:PaintStats(score)
  self:PaintFixes(score, events, n, h, opts.model)
  self:PaintAnalysis(tl, score)
  self:PaintMeta(p, score)
  self:PaintSections()
  self:PaintTitle()
  self._final = true
  self._everFinal, self._showEmpty = true, false
  self:Layout()
end

-- Everything below the headline, out of the way: the mid-fight shape and the
-- first half of a blank.
function View:HideFinal()
  local f = self.frame
  f.statsRow:Hide()
  for i = 1, MAX_CARDS do f.cards[i]:Hide() end
  f.rotHeader:Hide(); f.rotBody:Hide()
  f.detHeader:Hide(); f.detBody:Hide()
  self._nCards, self._final = 0, false
end

function View:Blank()
  local pools = self.pools
  for _, pool in pairs(pools) do
    poolReset(pool)
    poolHideRest(pool)
  end
  local rows = self.frame.rows
  for i = 1, #rows do rows[i]:Hide() end
  self:LayoutIssues(0)
  self:HideFinal()
  self:BlankHeadline()
  blankTiles(self.frame.stats)
  self._showEmpty = not self._everFinal
end

-- The headline with no fight behind it: an em dash rather than the last drill's
-- grade, which would otherwise survive the practice mode being switched off.
function View:BlankHeadline()
  local hl = self.frame.headline
  hl.hit._pct = nil
  if hl._gk ~= "-" then
    hl._gk = "-"
    hl.grade:SetText(NONE_MARK)
  end
  if hl._hk ~= "-" then
    hl._hk = "-"
    hl.head:SetText("no fight yet")
  end
  if hl._sk ~= "-" then
    hl._sk = "-"
    hl.sub:SetText("Pull a practice fight and this reads back what happened.")
  end
end

----------------------------------------------------------------------------
-- Painting
----------------------------------------------------------------------------

local function severityColor(sev)
  local c = TL and TL.COLORS
  if not c then return 1, 1, 1 end
  local col = c[sev or "warn"] or c.warn
  return col[1], col[2], col[3]
end

-- One lane item. style: "solid" (played), "ghost" (expected) or "band" (a
-- window rather than an event). A `thin` item (the weave window) takes half the
-- lane along its BOTTOM and never draws an outline: at full height with edges it
-- read as a box swallowing the lane rather than as the room it describes.
function View:PaintItem(it, laneIdx, style)
  local x = (it.t0 - self._t0) * self._pps
  local w = (it.t1 - it.t0) * self._pps
  if w < 2 then w = 2 end
  if x + w < self._visX0 or x > self._visX1 then return end
  local pools, content = self.pools, self.content
  local col = (TL.COLORS[it.color] or TL.COLORS.g)
  local r, g, b = col[1], col[2], col[3]
  local y = -((laneIdx - 1) * LANE_H) - 2
  local barH = BAR_H
  if it.thin then
    barH = math.floor(BAR_H / 2)
    y = y - (BAR_H - barH)
    style = "band"                -- thin implies no outline, whatever was asked
  end
  if style == "ghost" then
    -- Four 1 px edges: hollow reads as "this is not what happened".
    local top = poolTexture(pools.edge, content, "OVERLAY")
    top:SetColorTexture(r, g, b, 0.85)
    top:SetSize(w, 1)
    top:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
    local bot = poolTexture(pools.edge, content, "OVERLAY")
    bot:SetColorTexture(r, g, b, 0.85)
    bot:SetSize(w, 1)
    bot:SetPoint("TOPLEFT", content, "TOPLEFT", x, y - BAR_H + 1)
    local left = poolTexture(pools.edge, content, "OVERLAY")
    left:SetColorTexture(r, g, b, 0.85)
    left:SetSize(1, BAR_H)
    left:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
    local right = poolTexture(pools.edge, content, "OVERLAY")
    right:SetColorTexture(r, g, b, 0.85)
    right:SetSize(1, BAR_H)
    right:SetPoint("TOPLEFT", content, "TOPLEFT", x + w - 1, y)
    local fill = poolTexture(pools.bar, content, "ARTWORK")
    fill:SetColorTexture(r, g, b, 0.12)
    fill:SetSize(w, BAR_H)
    fill:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
  else
    local fill = poolTexture(pools.bar, content, "ARTWORK")
    fill:SetColorTexture(r, g, b, (style == "band") and 0.25 or 0.9)
    fill:SetSize(w, barH)
    fill:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
  end
  local off = 2
  if w >= ICON_MIN and it.sym then
    local tex = Nock.UI.PracticeIconFor(it.sym)
    if tex then
      local icon = poolTexture(pools.icon, content, "OVERLAY")
      icon:SetTexture(tex)
      icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      icon:SetDesaturated(DESATURATED[it.sym] and true or false)
      icon:SetSize(BAR_H - 2, BAR_H - 2)
      icon:SetPoint("TOPLEFT", content, "TOPLEFT", x + 1, y - 1)
      off = BAR_H + 1
    end
  end
  if it.label and w >= 30 then
    local fs = poolFontString(pools.label, content, C.FONT.SIZE_OVERLAY - 2)
    fs:SetWidth(math.max(10, w - off - 1))
    fs:SetPoint("LEFT", content, "TOPLEFT", x + off, y - barH / 2)
    fs:SetText(it.label)
    fs:SetTextColor(1, 1, 1, 0.9)
  end
end

function View:Paint(tl)
  local pools = self.pools
  for _, pool in pairs(pools) do poolReset(pool) end

  local pps = profile("practiceTimelinePps", 80)
  if pps < 10 then pps = 10 elseif pps > 400 then pps = 400 end
  local t0 = tl.t0 or 0
  local t1 = tl.t1 or t0
  local span = t1 - t0
  if span < 1 then span = 1 end
  local contentW = span * pps
  local laneW = self._laneW
  if contentW < laneW then contentW = laneW end
  self._t0, self._pps, self._contentW = t0, pps, contentW
  self.content:SetSize(contentW, LANE_AREA_H)
  self.rotContent:SetSize(contentW, ROT_H)

  self:ApplyScroll(self._scroll or 0)
  self._paintScroll = self._scroll
  self._visX0, self._visX1 = self._scroll - CULL_PAD, self._scroll + laneW + CULL_PAD

  -- Second grid + a label every 5 s, fight-relative.
  local content = self.content
  local step = (span > 150) and 5 or 1
  local first = math.floor(self._visX0 / (step * pps))
  if first < 0 then first = 0 end
  local last = math.ceil(self._visX1 / (step * pps))
  for k = first, last do
    local sec = k * step
    local gx = sec * pps
    if gx >= 0 and gx <= contentW then
      local line = poolTexture(pools.grid, content, "BACKGROUND")
      line:SetColorTexture(1, 1, 1, (sec % 5 == 0) and 0.10 or 0.045)
      line:SetSize(1, #LANES * LANE_H)
      line:SetPoint("TOPLEFT", content, "TOPLEFT", gx, 0)
      if sec % 5 == 0 then
        local fs = poolFontString(pools.axis, content, C.FONT.SIZE_OVERLAY - 2)
        fs:SetWidth(40)
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", gx + 2, -(#LANES * LANE_H) - 1)
        fs:SetText(sec .. "s")
        fs:SetTextColor(0.6, 0.6, 0.6)
      end
    end
  end

  -- The ROTATION row: the paper's casts for each cycle when they were played,
  -- what was played instead when they were not. A cycle the paper leaves empty
  -- and the player left empty too draws nothing at all.
  --
  -- The trailing cycle is normally still OPEN (T.Cycles flags it `partial`): a
  -- full cycle's worth of paper against however much of it you had time to play
  -- is not a mistake, so it is drawn in the dim ink and never in red.
  local cycles = self.cycles
  local rotContent = self.rotContent
  if cycles then
    for i = 1, cycles.n do
      local cy = cycles[i]
      local x = (cy.t0 - t0) * pps
      local w = (cy.t1 - cy.t0) * pps
      if w < 2 then w = 2 end
      if x + w >= self._visX0 and x <= self._visX1 then
        local neutral = cy.ok or cy.partial
        local text = neutral and cy.paper or cy.played
        if text == "" and not neutral then text = NONE_MARK end
        if text ~= "" then
          local cell = poolRotCell(pools.rot, rotContent)
          cell:SetWidth(w)
          cell:SetPoint("TOPLEFT", rotContent, "TOPLEFT", x, -1)
          cell.cycle = cy
          cell.text:SetWidth(math.max(6, w - 4))
          cell.text:SetText(text)
          if cy.ok then cell.text:SetTextColor(INK[1], INK[2], INK[3])
          elseif cy.partial then cell.text:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])
          else cell.text:SetTextColor(BAD[1], BAD[2], BAD[3]) end
        end
      end
    end
  end

  for i = 1, #LANES do
    local items = tl.lanes[LANES[i]]
    if items then
      for j = 1, #items do self:PaintItem(items[j], i, "solid") end
    end
  end
  local ghosts = tl.ghosts
  if ghosts then
    for i = 1, #ghosts do
      local gh = ghosts[i]
      self:PaintItem(gh, LANE_INDEX[gh.lane] or 3, "ghost")
    end
  end

  local marks = tl.marks
  if marks then
    for i = 1, #marks do
      local mk = marks[i]
      local mx = (mk.t - t0) * pps
      if mx >= self._visX0 and mx <= self._visX1 then
        local laneIdx = LANE_INDEX[mk.lane] or 2
        local btn = poolMark(pools.mark, content)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", mx - MARK_HIT / 2, -((laneIdx - 1) * LANE_H) + 3)
        btn.tex:SetColorTexture(severityColor(mk.severity))
        btn.mark = mk
      end
    end
  end

  for _, pool in pairs(pools) do poolHideRest(pool) end
end

-- Title bar: the gold chip names what this fight WAS (the drill, or the
-- scenario when no drill is loaded), and the info chip is the clock and the
-- cycle count. Everything else about the setup lives in Details.
function View:PaintTitle()
  local f = self.frame
  local p = practice()
  local active = Nock.state.sim.active and true or false
  local room = self._chipRoom or (CHIP_MIN_W * 2)
  if room < CHIP_MIN_W then
    f.scenChip:Hide()
    f.infoChip:Hide()
    return
  end
  f.infoChip:Show()
  -- Practice off: the gold chip must not go on naming a fight whose grade the
  -- headline has already blanked. It goes away entirely and the info chip says
  -- how to come back.
  local scen = active and p and p._fightScenario or nil
  local drill = (active and p and p.LadderDrillName) and p:LadderDrillName() or nil
  local scenW = 0
  if scen or drill then
    setChip(f.scenChip, (drill or scen):upper(), GOLD, CHIP_INK, math.floor(room * 0.55))
    f.scenChip:Show()
    scenW = f.scenChip:GetWidth()
  elseif active then
    setChip(f.scenChip, "NO FIGHT YET", GOLD, CHIP_INK, math.floor(room * 0.55))
    f.scenChip:Show()
    scenW = f.scenChip:GetWidth()
  else
    f.scenChip:Hide()
  end
  -- Whatever the scenario chip did not use is the info chip's; the info chip is
  -- the one that truncates, since its numbers are the least load-bearing.
  local infoMax = room - scenW
  if infoMax < CHIP_MIN_W then infoMax = CHIP_MIN_W end
  if active and p then
    local s = (not Nock.state.sim.fightOn) and p.lastScore or nil
    local sec, cyc
    if s then
      sec = s.fightTime
      local cp = s.cyclesOnPaper
      cyc = (self.cycles and self.cycles.n) or (cp and cp.total) or 0
    else
      local live = p:LiveScore(self._liveCounters)
      sec = live and live.fightTime or nil
      cyc = live and (live.cyclesTotalApprox or 0) or 0
    end
    if sec then
      setChip(f.infoChip, ("%s \194\183 %d cycles"):format(clockText(sec), cyc), nil, INK_DIM, infoMax)
    else
      setChip(f.infoChip, "no fight timed yet", nil, INK_DIM, infoMax)
    end
  else
    setChip(f.infoChip, "practice is off \226\128\148 /nock practice to start", nil, INK_DIM, infoMax)
  end
  -- The scenario chip is the info chip's left anchor: with it hidden the info
  -- chip re-anchors to the title so the bar keeps its left-to-right reading.
  local anchor = active and "chip" or "title"
  if self._infoAnchor ~= anchor then
    self._infoAnchor = anchor
    f.infoChip:ClearAllPoints()
    if anchor == "chip" then f.infoChip:SetPoint("LEFT", f.scenChip, "RIGHT", 6, 0)
    else f.infoChip:SetPoint("LEFT", f.title, "RIGHT", 8, 0) end
  end
end

-- The headline of a FINISHED fight: the grade, the cycles it is made of, and
-- the one sentence that says what to work on (PracticeGrader.Summary).
function View:PaintHeadline(s)
  local hl = self.frame.headline
  if not s then self:BlankHeadline() return end
  local cp = s.cyclesOnPaper
  local cok, ctot = cp and cp.ok or 0, cp and cp.total or 0
  local hit = hl.hit
  hit._pct = ctot > 0 and math.floor(cok / ctot * 100 + 0.5) or nil
  hit._ok, hit._total, hit._streak = cok, ctot, s.bestStreak or 0
  local g = s.grade or "?"
  if hl._gk ~= g then
    hl._gk = g
    hl.grade:SetText(g)
  end
  local hk = cok * 10000 + ctot
  if hl._hk ~= hk then
    hl._hk = hk
    hl.head:SetText(("%d of %d cycles on paper"):format(cok, ctot))
  end
  local sentence = (GR and GR.Summary) and GR.Summary(s) or ""
  if hl._sk ~= sentence then
    hl._sk = sentence
    hl.sub:SetText(sentence)
  end
end

-- Mid-fight: the approximate cycle count and the streak, and nothing that
-- would invite reading a percentage while playing.
function View:PaintHeadlineLive(p)
  local hl = self.frame.headline
  hl.hit._pct = nil
  if hl._gk ~= "-" then
    hl._gk = "-"
    hl.grade:SetText(NONE_MARK)
  end
  local live = p:LiveScore(self._liveCounters)
  local cok = live and (live.cyclesOkApprox or 0) or 0
  local ctot = live and (live.cyclesTotalApprox or 0) or 0
  local hk = cok * 10000 + ctot
  if hl._hk ~= hk then
    hl._hk = hk
    hl.head:SetText(("%d of %d cycles so far"):format(cok, ctot))
  end
  local streak = live and (live.streak or 0) or 0
  local best = live and (live.bestStreak or 0) or 0
  local sk = streak * 10000 + best
  if hl._sk ~= sk then
    hl._sk = sk
    hl.sub:SetText(("Streak %d \194\183 best %d. The review fills in when the fight stops."):format(streak, best))
  end
end

-- Three numbers: what it cost, what it missed, what it strung together.
function View:PaintStats(s)
  local st = self.frame.stats
  self.frame.statsRow:Show()
  if not s then blankTiles(st) return end
  local clips, clipMs = s.clips or 0, s.clipMs or 0
  statValue(st[1], clips, (clips == 0) and 1 or 3, "%d", clips)
  statLabel(st[1], clipMs, "CLIPS \194\183 +%d ms", clipMs)
  -- The paper is the scope: a fight whose notation never held a `w` was never
  -- asked for a melee hit, so the tile says so with an em dash instead of
  -- reporting 0/0 as if the weaves had been dropped.
  if s.paperWeave == false then
    statValue(st[2], "none", 4, "%s", NONE_MARK)
    statLabel(st[2], "wnone", "%s", "NO WEAVE ON PAPER")
  else
    local taken, missed = s.weavesTaken or 0, s.weavesMissed or 0
    local windows = taken + missed
    local wCol = 4
    if windows > 0 then wCol = (missed == 0) and 1 or ((missed <= 1) and 2 or 3) end
    statValue(st[2], taken * 1000 + windows, wCol, "%d/%d", taken, windows)
    statLabel(st[2], "w", "%s", "WEAVES HIT")
  end
  local streak = s.bestStreak or 0
  statValue(st[3], streak, (streak > 0) and 1 or 4, "%d", streak)
  statLabel(st[3], "b", "%s", "BEST STREAK")
end

----------------------------------------------------------------------------
-- Fix cards: one per analysis row, each with a replay of the cycle it first
-- happened in.
----------------------------------------------------------------------------

-- The advice is written as a lowercase clause (it reads as the second half of
-- "the fix is ..."), and a card's title is a headline: it starts with a capital.
local function sentenceCase(s)
  if not s or s == "" then return "" end
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- The did/expected pair belongs to the VERDICT, not to the analysis row, so the
-- card takes the first verdict of that code which carries one. A linear scan
-- per card, at rebuild time only.
local function firstVerdict(marks, code)
  for i = 1, (marks and #marks or 0) do
    local mk = marks[i]
    if mk.code == code and mk.did then return mk end
  end
  return nil
end

-- One replay strip. Ghost items go on the PAPER lane, played ones on YOU, and
-- everything is scaled into the cycle's own duration.
function View:PaintReplay(card, rp)
  local pools = card.pools
  for _, pool in pairs(pools) do poolReset(pool) end
  local strip = card.strip
  local availW = (self._replayW or REPLAY_MIN_W) - REPLAY_LABEL_W - 6
  if availW < 20 then availW = 20 end
  local dur = (rp and rp.cycle and rp.cycle > 0) and rp.cycle or 0
  if dur > 0 then
    for i = 1, rp.nItems do
      local it = rp.items[i]
      local a, b = it.t0, it.t1
      if a < 0 then a = 0 end
      if b > dur then b = dur end
      if b > a then
        local x = REPLAY_LABEL_W + (a / dur) * availW
        local w = ((b - a) / dur) * availW
        if w < 2 then w = 2 end
        local laneIdx = it.ghost and 1 or 2
        local y = REPLAY_LANE_Y[laneIdx]
        local col = (TL.COLORS[it.sym] or TL.COLORS.g)
        local r, g, bl = col[1], col[2], col[3]
        if it.ghost then
          -- A 1 px hollow box in the dim ink: the paper, not what happened.
          local top = poolTexture(pools.edge, strip, "OVERLAY")
          top:SetColorTexture(r, g, bl, 0.5)
          top:SetSize(w, 1)
          top:SetPoint("TOPLEFT", strip, "TOPLEFT", x, y)
          local bot = poolTexture(pools.edge, strip, "OVERLAY")
          bot:SetColorTexture(r, g, bl, 0.5)
          bot:SetSize(w, 1)
          bot:SetPoint("TOPLEFT", strip, "TOPLEFT", x, y - REPLAY_LANE_H + 1)
          local left = poolTexture(pools.edge, strip, "OVERLAY")
          left:SetColorTexture(r, g, bl, 0.5)
          left:SetSize(1, REPLAY_LANE_H)
          left:SetPoint("TOPLEFT", strip, "TOPLEFT", x, y)
          local right = poolTexture(pools.edge, strip, "OVERLAY")
          right:SetColorTexture(r, g, bl, 0.5)
          right:SetSize(1, REPLAY_LANE_H)
          right:SetPoint("TOPLEFT", strip, "TOPLEFT", x + w - 1, y)
        else
          local fill = poolTexture(pools.bar, strip, "ARTWORK")
          fill:SetColorTexture(r, g, bl, 0.85)
          fill:SetSize(w, REPLAY_LANE_H)
          fill:SetPoint("TOPLEFT", strip, "TOPLEFT", x, y)
        end
        if it.label and w >= 24 then
          local fs = poolFontString(pools.label, strip, SMALL_SIZE - 1)
          fs:SetWidth(math.max(10, w - 2))
          fs:SetPoint("LEFT", strip, "TOPLEFT", x + 2, y - REPLAY_LANE_H / 2)
          fs:SetText(it.label)
          fs:SetTextColor(1, 1, 1, 0.9)
        end
      end
    end
  end
  for _, pool in pairs(pools) do poolHideRest(pool) end
  local cap
  if dur > 0 then cap = ("cycle %d \194\183 %.2f s"):format(rp.index or 0, dur)
  else cap = "no replay for this cycle" end
  if card._cap ~= cap then
    card._cap = cap
    card.cap:SetText(cap)
  end
end

function View:PaintFixes(score, events, n, h, model)
  local f = self.frame
  local analysis = score and score.analysis
  local marks = self.tl and self.tl.marks
  local shown = 0
  for i = 1, MAX_CARDS do
    local row = analysis and analysis[i]
    local card = f.cards[i]
    if not row then
      card:Hide()
    else
      shown = shown + 1
      local sev = (TL.SEVERITY and TL.SEVERITY[row.code]) or "warn"
      if card._sev ~= sev then
        card._sev = sev
        local col = (sev == "bad") and BAD or WARN
        card.rule:SetColorTexture(col[1], col[2], col[3], 1)
      end
      -- The eyebrow: which fix, what it cost, and the cycle the card replays.
      -- A fault with no milliseconds behind it (a missed weave) is counted, not
      -- priced — "cost 0 ms" reads as free, and it is not.
      local eb
      if (row.ms or 0) > 0 then
        eb = ("FIX %d \194\183 cost %d ms"):format(i, row.ms)
      else
        eb = ("FIX %d \194\183 %d time%s"):format(i, row.n or 0, ((row.n or 0) == 1) and "" or "s")
      end
      -- Cycle 0 is the grader's "before the first auto" (an EARLY cooldown, an
      -- opener fault). There is no cycle to name and none to replay, so the
      -- clause is left off rather than printed as the "cycle 0" nobody can find.
      local cyc = row.cycle or 0
      if cyc > 0 then eb = eb .. (" \194\183 cycle %d"):format(cyc) end
      if card._eb ~= eb then
        card._eb = eb
        card.eyebrow:SetText(eb)
      end
      local ti = sentenceCase(row.advice or row.code or "")
      if card._ti ~= ti then
        card._ti = ti
        card.title:SetText(ti)
      end
      -- The sentence: what you did and what the paper wanted instead, off the
      -- first verdict of this code that carried the pair.
      local v = firstVerdict(marks, row.code)
      local body
      if v then
        body = ("You: %s. Instead: %s."):format(v.did, v.expected or "the paper's own note")
      else
        body = row.code and ("Seen %d time%s this fight."):format(row.n or 0, ((row.n or 0) == 1) and "" or "s") or ""
      end
      if card._bo ~= body then
        card._bo = body
        card.body:SetText(body)
      end
      -- The two doors out of the card: the drill that trains it and the lesson
      -- step that explains it.
      local drillId = LADDER and LADDER.DrillFor and LADDER.DrillFor(row.code) or nil
      local drill = drillId and LADDER.ById and LADDER.ById(drillId) or nil
      if drill then
        card.drill.drill = drillId
        setCardButton(card.drill, "Drill: " .. drill.name)
      else
        card.drill.drill = nil
        card.drill:Hide()
      end
      local step = (LESSON and LESSON.StepFor) and LESSON.StepFor(row.code) or 1
      card.lesson.step = step
      setCardButton(card.lesson, "Lesson step " .. step)
      -- The lesson button anchors to whichever of the two is actually there.
      local anchor = drill and "drill" or "card"
      if card._btnAnchor ~= anchor then
        card._btnAnchor = anchor
        card.lesson:ClearAllPoints()
        if drill then card.lesson:SetPoint("LEFT", card.drill, "RIGHT", 4, 0)
        else card.lesson:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", CARD_PAD + CARD_RULE_W, CARD_PAD - 2) end
      end
      -- ONE `out` per card slot, reused for the life of the session.
      local rp = TL.Replay(events, n, score, h, model, row.cycle, card.replay)
      card.replay = rp
      self:PaintReplay(card, rp)
      card:Show()
    end
  end
  self._nCards = shown
end

-- The two Details lines: the rates and the opener on one, the haste windows on
-- the other. Built once per rebuild, never on the tick.
function View:PaintMeta(p, s)
  local f = self.frame
  local cfg = p and p.cfg
  local autoPct = s and s.autoEff and math.floor(s.autoEff * 100 + 0.5) or nil
  local gcdPct = s and s.gcdEff and math.floor(s.gcdEff * 100 + 0.5) or nil
  local kc = s and s.kc
  local op = s and s.opener
  local meta = ("auto eff %s%sgcd eff %s%sKC %d/%d%sopener %s (%s)%seWS %.2f%slat %d ms"):format(
    autoPct and (autoPct .. "%") or NONE_MARK, MID_DOT,
    gcdPct and (gcdPct .. "%") or NONE_MARK, MID_DOT,
    kc and kc.used or 0, kc and kc.windows or 0, MID_DOT,
    op and (op.ok and "OK" or "MISS") or NONE_MARK, op and op.anchor or "-", MID_DOT,
    cfg and (cfg.ws / cfg.baseRangedMul) or 0, MID_DOT,
    cfg and (cfg.latency or 0) * 1000 or 0)
  if f._meta ~= meta then
    f._meta = meta
    f.meta:SetText(meta)
  end
  local wins = s and s.windows
  local text
  if wins and #wins > 0 and s.t0 then
    local parts = {}
    for i = 1, #wins do
      if i > 6 then parts[#parts + 1] = "..." break end
      local w = wins[i]
      parts[#parts + 1] = ("%s %.0f-%.0f s"):format(w.notation or "?", (w.t0 or s.t0) - s.t0, (w.t1 or s.t0) - s.t0)
    end
    text = "windows: " .. table.concat(parts, ", ")
  else
    text = "windows: " .. NONE_MARK
  end
  if f._winText ~= text then
    f._winText = text
    f.windowsLine:SetText(text)
  end
end

-- The two section headers and their bodies' visibility. The bodies are painted
-- whether or not they are open — a fold is a reading choice, not a rebuild.
function View:PaintSections()
  local f = self.frame
  local nCyc = (self.cycles and self.cycles.n) or 0
  local nFaults = self._issueCount or 0
  setSection(f.rotHeader, self._openRot, "Rotation \194\183 %d cycles", nCyc, "")
  setSection(f.detHeader, self._openDetails, "Details \194\183 timeline, %d fault%s, opener, haste windows",
             nFaults, (nFaults == 1) and "" or "s")
  f.rotHeader:Show()
  f.detHeader:Show()
  if self._openRot then f.rotBody:Show() else f.rotBody:Hide() end
  if self._openDetails then f.detBody:Show() else f.detBody:Hide() end
end

-- The fault list, inside Details. Click a row to jump the lanes to it.
function View:PaintAnalysis(tl, score)
  local f = self.frame
  local rows = f.rows
  -- Every fault gets a row: the pool grows here, at rebuild time -- but only
  -- to MAX_POOL_ROWS of them. A long, badly played fight faults hundreds of
  -- times, and each row is six frames to build, lay out and re-lay on every
  -- width change, for a list nobody scrolls to the end of. Past the cap the
  -- viewport keeps the FIRST MAX_POOL_ROWS (the fight in the order it
  -- happened) and a tail row counts the rest; `Copy report` is uncapped and
  -- still carries every one of them.
  local shown, faults = 0, 0
  local marks = tl and tl.marks
  for i = 1, (marks and #marks or 0) do
    local mk = marks[i]
    if mk.severity ~= "good" then
      faults = faults + 1
      if faults <= MAX_POOL_ROWS then
        shown = shown + 1
        local b = self:IssueRow(shown)
        b.mark = mk
        -- Fight-relative, or nothing. With no `pull` in the stream tl.t0 is nil
        -- and the only number available is the raw GetTime() clock: an em dash
        -- says "this fight has no zero" where 305232320.92 said nothing at all.
        b.cols[1]:SetText(tl.t0 and ("%.2f"):format(mk.t - tl.t0) or NONE_MARK)
        b.cols[1]:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])
        setSevChip(b.chip, mk.text or mk.code or "", mk.severity, self._chipMaxW or 116)
        -- The row under the tail row's seat may have been the counter last
        -- rebuild, which hides the chip: a fault always shows its own.
        b.chip:Show()
        b.cols[2]:SetText(mk.did or "")
        b.cols[2]:SetTextColor(1, 0.7, 0.7)
        b.cols[3]:SetText(mk.expected or "")
        b.cols[3]:SetTextColor(0.74, 0.94, 0.78)
        b.cols[4]:SetText(mk.cost and tostring(mk.cost) or "")
        b.cols[4]:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        b:Show()
      end
    end
  end
  if faults > MAX_POOL_ROWS then
    shown = shown + 1
    local b = self:IssueRow(shown)
    b.mark = nil                    -- a count, not a verdict: nothing to jump to
    b.chip:Hide()
    b.cols[1]:SetText("")
    b.cols[2]:SetText(("\226\128\166 %d more in the report"):format(faults - MAX_POOL_ROWS))
    b.cols[2]:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])
    b.cols[3]:SetText("")
    b.cols[4]:SetText("")
    b:Show()
  end
  for i = shown + 1, #rows do rows[i]:Hide() end
  self:LayoutIssues(shown)
end

-- The fault viewport: MAX_ROWS tall at most, over a child as tall as the list.
-- A rebuild that produced the SAME number of faults is the same list re-painted
-- (the mid-fight repaint of a stretch already graded), so the reader keeps their
-- place; any change of length is a different list and lands back at the top.
function View:LayoutIssues(shown)
  local vis = shown
  if vis > MAX_ROWS then vis = MAX_ROWS end
  local viewH = vis * ROW_H
  self._issueViewH = viewH
  self._issueTotalH = shown * ROW_H
  local scroll, slider = self.issueScroll, self.issueSlider
  if vis > 0 then
    scroll:SetHeight(viewH)
    self.issueContent:SetHeight(shown * ROW_H)
    slider:SetHeight(viewH)
    scroll:Show()
  else
    scroll:Hide()
  end
  local same = (self._issueCount == shown)
  self._issueCount = shown
  self:ApplyIssueScroll(same and (self._issueScroll or 0) or 0)
end

-- Vertical scroll of the fault list. A WoW vertical slider has its minimum at
-- the top, so the value IS the scroll offset — no inversion needed.
function View:ApplyIssueScroll(y)
  local maxY = self._issueTotalH - self._issueViewH
  if maxY < 0 then maxY = 0 end
  if y < 0 then y = 0 elseif y > maxY then y = maxY end
  self._issueScroll = y
  self.issueScroll:SetVerticalScroll(y)
  self._issueSyncing = true
  self.issueSlider:SetMinMaxValues(0, maxY > 0 and maxY or 1)
  self.issueSlider:SetValue(y)
  self._issueSyncing = false
  if maxY > 0 then self.issueSlider:Show() else self.issueSlider:Hide() end
end

----------------------------------------------------------------------------
-- Layout: every block is placed from a running offset, so a folded section
-- simply does not advance it.
----------------------------------------------------------------------------

function View:Place(fr, y)
  fr:ClearAllPoints()
  fr:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD, -y)
  fr:Show()
end

function View:Layout()
  local f = self.frame
  local y = PAD + TITLE_H + ROW_GAP
  -- Before the session's first finished fight the headline stands down and one
  -- centred line says so. `Place` works on a FontString too: it anchors and
  -- shows, and the line is centred inside the window's own inner width.
  if self._showEmpty then
    f.headline:Hide()
    self:Place(f.empty, y)
    self:SetFrameHeight(y + EMPTY_H + PAD)
    return
  end
  f.empty:Hide()
  self:Place(f.headline, y)
  y = y + HEADLINE_H
  -- The final shape only: mid-fight and blank stop at the headline.
  if self._final then
    y = y + ROW_GAP
    self:Place(f.statsRow, y)
    y = y + STAT_H
    for i = 1, self._nCards do
      y = y + CARD_GAP
      self:Place(f.cards[i], y)
      y = y + CARD_H
    end
    y = y + ROW_GAP
    self:Place(f.rotHeader, y)
    y = y + SECT_H
    if self._openRot then
      self:Place(f.rotBody, y)
      y = y + ROT_BODY_H
    end
    y = y + 2
    self:Place(f.detHeader, y)
    y = y + SECT_H
    if self._openDetails then
      self:Place(f.detBody, y)
      local h = LANE_AREA_H + 2 + SLIDER_H + 3 + META_H + self._issueViewH
      f.detBody:SetHeight(h)
      y = y + h
    end
  end
  self:SetFrameHeight(y + PAD)
end

-- The frame's height, and -- hosted -- the workbench's: the window follows
-- the page. Change-gated so a rebuild that keeps the shape sends nothing.
function View:SetFrameHeight(h)
  self.frame:SetHeight(h)
  if h == self._pageH then return end
  self._pageH = h
  if self._host and self.frame:IsShown() then Nock:SendMessage("NOCK_PRACTICE_LAYOUT") end
end

----------------------------------------------------------------------------
-- Scrolling
----------------------------------------------------------------------------

function View:ApplyScroll(x)
  local maxX = (self._contentW or 0) - (self._laneW or 1)
  if maxX < 0 then maxX = 0 end
  if x < 0 then x = 0 elseif x > maxX then x = maxX end
  self._scroll = x
  self.scroll:SetHorizontalScroll(x)
  -- The rotation row lives on its own scroll frame (it folds separately) but
  -- shares this offset: the two must never disagree about where 12 s is.
  self.rotScroll:SetHorizontalScroll(x)
  self._syncing = true
  self.slider:SetMinMaxValues(0, maxX > 0 and maxX or 1)
  self.slider:SetValue(x)
  self._syncing = false
  if maxX > 0 then self.slider:Show() else self.slider:Hide() end
end

function View:SetScroll(x)
  self:ApplyScroll(x)
  -- Only the visible stretch is drawn, so a scroll far enough to expose new
  -- ground has to repaint. The pad makes small nudges free.
  if self.tl and math.abs(self._scroll - (self._paintScroll or 0)) > REPAINT_AT then
    self:Paint(self.tl)
  end
end
