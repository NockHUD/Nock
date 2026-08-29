-- UI/Frame_PracticeConveyor.lua
-- The live practice stage: one row per ability flowing right to left past a fixed hit line, its look driven by the style levers (T.STYLE_LEVERS), hosted in the practice panel or undocked.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("PracticeConveyorView", "AceEvent-3.0")
local C = Nock.Constants
local Transport = Nock.UI.PracticeTransport

local PAD = C.DIM.OUTER_PAD
-- The practice shell's skin (UI/Skin.lua): the stage's chrome -- row labels,
-- axis, coach row, the Focus head, the hit line -- paints through it. The
-- notes' own labels and the pops keep the HUD font: outlined text on a moving
-- bar is what reads there.
local Skin = Nock.Skin
-- ONE ROW PER ABILITY (v3 P3). The rows a fight shows come from the plan
-- (plan.rows: the paper's abilities, plus `cd` when the fight has cooldowns or
-- procs); the view builds them on a rebuild where the list changed. Until a
-- plan says otherwise the stage shows these.
local DEFAULT_ROWS = { "auto", "s", "w" }
local MAX_ROWS = 6
local ROW_NAME = { auto = "Auto", s = "Steady", m = "Multi", A = "Arcane", w = "Weave", cd = "CDs" }
local ROW_ICON = { auto = "a", s = "s", m = "m", A = "A", w = "r", cd = "KC" }
local ROW_NEEDS_KEY = { auto = true, s = true, m = true, A = true, w = true }
local NO_KEY = "NO KEY"
-- The conveyor IS the stage: one fixed height, docked and undocked, with the
-- three lanes spread over whatever is left of it after the toast band, the pop
-- headroom and the second-tick axis. A lane's height is therefore DERIVED
-- (self._laneH, in View:Measure) rather than a constant -- only its floor is,
-- so a very large toast font grows the host instead of squeezing the bars.
--
-- STAGE_H is the mock's 190 px of STAGE, and the coach row sits UNDER it: the
-- host is 190 + 34 = 224. The panel never hardcodes either number -- it reads
-- whatever View:Host returns (UI/Frame_Practice.lua's Relayout), so the two
-- follow this file.
local STAGE_H = 190
local COACH_H = 34            -- the coach sentence + the metronome dots
-- FOCUS (shell step 3): the stage alone on the HUD during a fight, with a
-- one-line head over the lanes -- state chip, scenario, streak, STOP and the
-- way back to the workbench. HEAD_H is that line; it is part of the stage's
-- height only while Focus is on (View:Measure).
local HEAD_H = 26
-- THE REPLAY TRANSPORT: over the coach row while a stopped fight is scrubbed
-- (Practice:ReplayAt). Buttons are TR_BTN square with a pixel icon; the track
-- is TR_TRACK_H tall for the mouse, drawn as a TR_LINE line with the played
-- part in the accent, clip markers on it, and a handle that drags.
local TR_BTN, TR_ICON_GAP = 22, 2
local TR_TRACK_H, TR_LINE, TR_HANDLE_W, TR_HANDLE_H, TR_MARK_W = 16, 3, 6, 12, 2
local TR_TIME_W = 96
local MARK_ROW, BAR_H = 6, 18 -- the mark gutter floor, and the bar itself
local LANE_MIN_H = MARK_ROW + BAR_H + 2
local AXIS_H = 18             -- the relative second-tick labels under the lanes
-- Headroom above the SHOTS lane for a judgment pop to rise into: a pop is
-- anchored on its note's bar top and rises POP_RISE while it fades out, so the
-- word's own top reaches about POP_RISE + its font size above that bar. The
-- last stretch of that is spent at an alpha near zero, which is why the band
-- does not have to cover the whole travel.
local POP_ROOM = 24
-- A reserved band above the lanes, for nothing but the verdict toast. Without
-- it the toast is drawn over the SHOTS lane it is a verdict ON, and neither the
-- word nor the bar under it can be read.
--
-- Its height follows the toast's own font size, which is a setting: at the
-- default 22 a fixed 14 px band overhung the lanes by the better part of 8 px,
-- which is the very thing the band exists to prevent. Measured with the host
-- height (View:Measure), never per tick.
local TOAST_GUTTER_MIN = 14
-- How far under its anchor the docked strip seats itself. Defined ONCE here:
-- the panel used to keep its own copy of this number to size itself with, and
-- two constants for one gap is one drift away from a seam. Host() hands back
-- the gap AND the height, so the panel never has to know it at all.
local DOCK_GAP = 6
local LABEL_W = 96            -- row-label gutter: icon + name + key (and the undocked drag handle)
local LABEL_INSET = 8         -- the row icon's inset from the gutter's edge
local LABEL_H = 30            -- the row label's frame: name over key beside the icon
local MIN_LANE_W = 120
-- The undocked stage is width-draggable from its right edge: SIZER_W is the
-- mouse strip, MIN_W/MAX_W the clamp. Height is not in it at all -- the stage is
-- STAGE_H whichever way it is hosted, and a taller one would only stretch three
-- lanes that already have their air.
local SIZER_W, MIN_W, MAX_W = 8, 480, 1600
local ICON_MIN = 18           -- an item narrower than this gets no icon
-- A LABEL IS MEASURED, NEVER GUESSED (R7b + its review). The gate used to be a
-- pixel constant on the BAR width, which was wrong twice over. Too generous
-- first: a 0.35 s wind-up bar (about 31 px at the default px/s) cleared a 30 px
-- bar test with 11 px of text area behind an 18 px icon, and the client drew
-- three dots -- a row of tiny boxes each carrying an ellipsis, which reads as a
-- second press per cycle. Then too mean, when the same 30 px was moved onto the
-- text area: the paper's next note is an Arcane or a Multi for a third of the
-- `drill 1:1+mA` period, and the word NEXT -- which fits those bars easily once
-- the icon is out of the way -- vanished from the stage for seconds at a time.
--
-- So the FontString is asked. SetWidth(0) unconstrains it, SetText fills it, and
-- GetStringWidth is the honest answer for this player's LibSharedMedia face at
-- this size. Once per item per REBUILD (a few Hz, a few dozen items), never per
-- tick.
--
-- ...and the word NEXT outranks its own icon: a bar too narrow to hold both
-- drops the ICON and keeps the word. Every other label yields to the icon --
-- "Raptor", "swing ready", a proc name are all captions on a picture that
-- already says what it is, while NEXT is the one piece of advice on the stage.
local NEXT_LABEL = "NEXT"
-- ...and the icon outranks the word after all (user, 2026-08-24: "consistency
-- is king with icons"). The icon is the note's identity, the word a hint: on a
-- narrow bar the word shrinks -- NEXT, NXT, N -- and only then goes.
local NEXT_SHORT = { "NEXT", "NXT", "N" }
-- THE STAGE'S STYLE (P3 polish). The levers are defined once, in
-- Core/PracticeTimeline.lua (T.STYLE_LEVERS); ApplyStyle reads the profile into
-- this table, and PaintItem reads it per item. Defaults here are the shipped
-- ones, so a fixture without a profile paints the shipped look.
local STYLE = { note = "glass", next = "both", move = "ramp", hit = "column", past = "fade",
                lanes = "zebra", tick = "hairline", windup = "faint", scope = "auto" }
View.STYLE = STYLE
-- Glass: the tint the fill carries, the coloured edge, the white top highlight.
local GLASS_FILL, GLASS_EDGE, GLASS_HI = 0.28, 0.9, 0.35
-- What a played note settles to behind the hit line (style `past` = fade), and
-- what every pending note but the next settles to (style `next` = both/bright).
local PAST_ALPHA, DIM_ALPHA = 0.4, 0.6
-- The auto row: the wind-up wash by strength, the release tick's width by kind.
local WINDUP_ALPHA = { faint = 0.10, normal = 0.18, strong = 0.30, off = 0 }
local TICK_W = { hairline = 1, notch = 2, bar = 3 }
-- The move-in ramp's two ends (style `move` = ramp), and the flat fallback for a
-- client without a texture gradient.
local RAMP_A0, RAMP_A1, RAMP_FLAT = 0.04, 0.75, 0.30
-- The NOW column (style `hit` = column): width and wash.
local HIT_COL_W, HIT_COL_A = 16, 0.08
-- Lane furniture (style `lanes`).
local ZEBRA_A, LANE_LINE_A = 0.05, 0.12
-- The NEXT chip: the word and the key, on a light tile above the next note.
local CHIP_SIZE, CHIP_PAD, CHIP_H = 9, 5, 12
local CHIP_NEXT = { 0.91, 0.89, 0.83 }
local CHIP_MOVE = { 0.88, 0.48, 0.18 }
local MARK_HIT, MARK_SIZE = 12, 6
local HEAD_TRI = 8
local LABEL_SIZE = 9
-- Rebuild cadence. REBUILD_SEC is the idle floor (nothing changed, but the
-- lookahead has drifted) -- and the slow floor is the only clock-driven
-- rebuild there is (v3 P2):
-- items entering the far edge of the window get drawn, and with every item
-- keyed by identity it moves nothing at all. The drift rebuild for now-anchored
-- items is gone -- the band and the ramp are absolute moments off the plan.
local REBUILD_SEC = 0.5
-- How long a residual re-seat takes to glide, and how far a jump may be before
-- it is snapped instead (a re-plan is not a move -- gliding a forecast across
-- half the strip reads as the strip itself sliding).
local EASE_SEC, EASE_MAX = 0.15, 1.5
local ARROW_TEX = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local ARROW_DOWN = -math.pi / 2   -- the art points RIGHT at rest
local GOLD = { 1, 0.82, 0.2 }
-- The hit line, the NOW column, the future tint and the metronome's beat wear
-- the shell's accent (the palette page: "#abd473 for the hit line"); the
-- metronome's OFF dot is the shell's line colour on the black stage.
local ACCENT = Skin.COLORS.accent
local INK = Skin.COLORS.ink
-- The hit line's glow: three additive slabs of falling width and rising
-- intensity, centred on the line. Nock ships no art and the client's own soft
-- radial textures are not something this file can verify from here, so the
-- falloff is faked out of the flat texture every other Nock indicator uses --
-- built ONCE and re-seated only by Layout, so it costs nothing per tick.
-- { width, alpha }, widest first.
local HIT_GLOW = { { 20, 0.05 }, { 11, 0.07 }, { 5, 0.10 } }
-- The coach row's severity wash, keyed by T.JUDGE_SEV's own vocabulary. The
-- mock fades these to the panel colour across the row; a flat tint at the same
-- alpha says the same thing without a gradient the client may not have, and it
-- is one SetColorTexture on a change rather than a texture per stop.
local COACH_WASH = {
  good = { Skin.COLORS.good[1], Skin.COLORS.good[2], Skin.COLORS.good[3], 0.10 },
  warn = { Skin.COLORS.wait[1], Skin.COLORS.wait[2], Skin.COLORS.wait[3], 0.10 },
  bad  = { Skin.COLORS.bad[1],  Skin.COLORS.bad[2],  Skin.COLORS.bad[3],  0.12 },
}
-- No fight: the lanes and the hit line stay, and this says what to do about it.
-- ASCII only -- the display faces have holes in their punctuation.
local EMPTY_TEXT = "Press Start - or open the Lesson first"

-- Judgment pops. POP_RISE is the travel; the life itself is T.POP_LIFE, so the
-- word and the data behind it cannot drift (see Core/PracticeTimeline.lua).
-- POP_HOLD is the fraction of that life spent at full alpha before the fade.
local POP_SIZE, POP_RISE, POP_HOLD = 20, 14, 0.72
-- ...but only the SHOTS lane gets the full 20. A pop rises off its own note, and
-- only the top lane has the reserved band (POP_ROOM) to rise INTO -- a WEAVE or
-- PROCS verdict rises into the lane above it, where 20 px of outlined display
-- face covers the bar it is standing on. 16 clears the same distance without
-- swallowing its neighbour.
local POP_SIZE_LOW = 16
-- Every grade but GOOD wears its severity colour straight off T.COLORS. GOOD is
-- a LIGHTER good: it has to read as "landed, but not on the beat" beside a
-- PERFECT rather than as the same word twice.
local GOOD_LIGHT = { 0.62, 0.88, 0.68 }
-- Which lane a judged note belongs to. The paper only ever writes `w`; a played
-- Raptor arrives as `r` (PracticeGrader's noteTakes normalises in that one
-- direction), and an OFF press carries whatever was played.

-- THE PRESS FLASH (R6b). A judgment is emitted when the cast RESOLVES, which on
-- a Steady is the better part of a second after the key went down -- so the
-- stage said nothing at all at the moment the player was asking "did that
-- land?". The press itself gets an answer of its own: the paper note nearest the
-- hit line on the lane the press belongs to lights up for FLASH_LIFE and decays.
--
-- It is deliberately WORDLESS and colourless. It says "the addon heard you, and
-- this is the note you were reaching for" -- never how good the press was. A
-- provisional grade that the resolution then contradicts is the one thing this
-- must not do, so the pop text stays exactly where it is.
--
-- An additive white wash over the note's own bar: the icon and the label read
-- straight through it, which a solid overlay would not allow.
local FLASH_LIFE, FLASH_ALPHA, FLASH_PAD = 0.25, 0.5, 2

-- The metronome: four dots at the right of the coach row. Dot 1 is the beat
-- (an auto release), dot 3 the weave gap opening. A flash decays over
-- MET_FLASH from the central tick, exactly like the pops.
local MET_DOTS, MET_DOT, MET_GAP, MET_FLASH = 4, 8, 4, 0.12
local MET_OFF = Skin.COLORS.line
local MET_TICK = INK
local MET_WEAVE = ACCENT
-- Sound. Nock ships no audio and the Anniversary client's own .ogg paths are
-- not something this file can verify from here, so the two cues come from
-- SOUNDKIT -- audibly distinct from each other, and Classic-era built-ins
-- (BossMarkWatch leans on the same table). Each carries its raw id as well:
-- SOUNDKIT itself is not verified here either, and PlaySound takes the number
-- directly. pcall'd on top of that, because a client that has neither must
-- cost a silent metronome rather than an error inside the tick.
local MET_SOUND = {
  tick = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 },
  gap  = { "IG_MAINMENU_OPTION_CHECKBOX_OFF", 857 },
}

-- Coach sentences that never take a number. Held as constants so the common
-- case sets no text at all: the line only changes when the judgment behind it
-- does, and an unchanged sentence never reaches SetText (see View:SetCoach).
local COACH_IDLE = "Press Start."
local COACH_PULL = "Pull with Steady."
-- ...and, on a paper that costs by design, what it costs (M.PaperNoteText).
local COACH_PULL_NOTE = "Pull with Steady. This paper %s - that is the paper, not you."
local COACH_PULL_NOKEY = "Pull with Steady. No weave key - every weave note will be MISSED (Keys page)."
local COACH_BEAT = "On the beat."
local COACH_LATE = "Queued into the wind-up: free, but the streak resets."
local COACH_WEAVE_MISS = "Weave missed - start walking while the cast bar finishes."
local COACH_MISS_ANY = "Missed a note - it was due at the beat."
local COACH_OFF_ANY = "That press is not on the paper here."
-- The gap the engine found is the roomiest there is and a whole weave does not
-- go in it (E.WeaveWindow's `fits`): the paper asks for one, the swing and the
-- grid between them cannot serve it, and skipping it is the play. ASCII only --
-- the user's chosen LibSharedMedia font may have no dash but a hyphen.
local COACH_WEAVE_TIGHT = "The gap is too small for a full weave - skip this one."
-- Built once, on first use: it names a spell, and a spell name is localised.
local coachBeatWeave
local PROC_NAMES = { "RF", "QS", "Lust", "Drums", "DST", "Pot" }
local DESATURATED = { w = true }  -- the auto-attack weave is Raptor's icon, greyed
-- A paper note the sim says is still on cooldown when it comes round (R8a,
-- `it.oncd`). It keeps its slot -- the paper is the plan and the grader grades
-- it honestly -- but it is not a press: the cd tint is the strip's own dim grey
-- (TL.COLORS.g, what a cancelled cast already wears), the icon is desaturated
-- with it, and the whole bar sits at a third alpha so the playable notes either
-- side of it are the ones the eye lands on.
local ONCD_ALPHA = 0.35
local ONCD_COLOR = "g"
local EMPTY = {}

local TL                      -- Nock.PracticeTimeline, resolved on enable

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function practice() return Nock:GetModule("Practice", true) end

-- The saved undocked width, clamped to the drag's own bounds and to the floor
-- the lanes need. One definition: OnInitialize, ApplyDock and the drag all read
-- it, and a saved value from a wider screen must not survive as a 2000 px strip.
function View:UndockedWidth()
  local w = profile("practiceConveyorW", 960)
  if type(w) ~= "number" then w = 960 end
  local floorW = MIN_LANE_W + LABEL_W + PAD * 2
  if floorW < MIN_W then floorW = MIN_W end
  if w < floorW then w = floorW elseif w > MAX_W then w = MAX_W end
  return w
end

-- The toast band, the pop headroom, the lane height they leave over and the
-- height the panel has to reserve for us. Read once per dock/settings change
-- into self._toastGutter / _topPad / _lanesTop / _laneH / _markRow / _lanesH /
-- _stripH / _hostH; nothing here is per tick.
--
-- The stage is STAGE_H tall whichever way it is hosted and the coach row hangs
-- under it, so the host is STAGE_H + COACH_H. The lanes take the slack inside
-- the stage: they are what "the conveyor is the stage" actually buys. Only when
-- the toast font is large enough to push a lane under its floor does the stage
-- grow past STAGE_H instead.
function View:Measure()
  local size = profile("practiceToastSize", 22)
  if type(size) ~= "number" or size < 1 then size = 22 end
  local gutter = size + 2
  if gutter < TOAST_GUTTER_MIN then gutter = TOAST_GUTTER_MIN end
  self._toastGutter = gutter
  -- Focus: the head line sits over the toast band; `quiet focus` drops the
  -- coach row (pops only, for the "fully lock in" case).
  self._headH = self._focus and HEAD_H or 0
  self._coachH = (self._focus and profile("practiceQuietFocus", false)) and 0 or COACH_H
  self._topPad = self._headH + 2 + gutter
  self._lanesTop = self._topPad + POP_ROOM
  local avail = STAGE_H - self._lanesTop - AXIS_H - 2
  local nRows = self._nRows or #DEFAULT_ROWS
  local laneH = math.floor(avail / nRows)
  if laneH < LANE_MIN_H then laneH = LANE_MIN_H end
  self._laneH = laneH
  -- The bar sits in the middle of its lane, so the mark gutter above it grows
  -- with the lane rather than leaving all the air under the bars.
  local mark = math.floor((laneH - BAR_H) / 2)
  self._markRow = mark > MARK_ROW and mark or MARK_ROW
  self._lanesH = laneH * nRows
  self._stripH = self._lanesH + AXIS_H
  local stage = self._lanesTop + self._stripH + 2
  if stage < STAGE_H + self._headH then stage = STAGE_H + self._headH end
  self._hostH = stage + self._coachH
end

-- Nothing pressed yet this fight: the moment of the pull, or nil once the
-- player has touched a key. The strip is a still picture of the plan until
-- then — there is no elapsed fight to scroll through, and a `now` that keeps
-- moving would drift the forecast away from the pull it is anchored to.
local function prePullNow(p)
  -- `/nock practice freeze`: the strip's clock held where it was, for a
  -- screenshot. The engine runs on; the strip catches up on unfreeze.
  if p and p._freezeAt then return p._freezeAt end
  local e = p and p.engine
  -- The replay: the strip's clock is the scrub position.
  if p and p._replay and e and not e.fightOn then return p._replay.at end
  if not (e and e.fightOn) then return nil end
  -- The engine's own answer: armed since Start, pulled by the first press.
  -- Its t0 is the provisional one until then, which is exactly the still the
  -- strip should hold. The press counters below stay as a belt: they close the
  -- hold on the same press, one tick earlier than the engine's own flags could
  -- be republished through the snapshot.
  if e.pulled then return nil end
  if (e.nPress or 0) > 0 or e.repeating then return nil end
  local t0 = e.t0
  return (t0 and t0 > 0) and t0 or nil
end

----------------------------------------------------------------------------
-- Pools. Everything drawn comes from one; nothing is created per rebuild once
-- the counts stop growing, and nothing at all is created per tick.
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

local function poolFontString(pool, parent, size, role)
  local n = pool.n + 1
  pool.n = n
  local fs = pool[n]
  if not fs then
    fs = parent:CreateFontString(nil, "OVERLAY")
    if role then Skin.Font(fs, role, size)
    else fs:SetFont(Nock.UI.GetFont(), size, "OUTLINE") end
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    pool[n] = fs
    pool.max = n
  end
  fs:ClearAllPoints()
  fs:Show()
  return fs
end

-- One pooled FRAME per drawn item, owning its own fill, four 1 px edges, icon
-- and label. Seven loose textures on the content frame could not be moved as a
-- unit: a re-seat is now one SetPoint and a fade-in one SetAlpha, which is what
-- makes the glide affordable on the tick path.
-- Create one more item frame at the end of the pool (never handed out here:
-- poolTake binds frames to KEYS, see below).
local function poolItemNew(pool, parent)
  local n = pool.max + 1
  local f = pool[n]
  if not f then
    f = CreateFrame("Frame", nil, parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 1)
    f:SetSize(2, BAR_H)
    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints(f)
    f.fill = fill
    -- Four 1 px edges. The mock draws these dashed; a real dash costs a texture
    -- per segment per item, so the hollow outline carries the same meaning
    -- ("this has not happened yet") at a fixed four textures. Anchored once --
    -- only their length changes with the item.
    local e = {}
    for i = 1, 4 do e[i] = f:CreateTexture(nil, "OVERLAY") end
    e[1]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    e[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    e[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    e[3]:SetSize(1, BAR_H)
    e[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    e[4]:SetSize(1, BAR_H)
    f.edges = e
    local icon = f:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    icon:SetSize(BAR_H - 2, BAR_H - 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Nock.UI.GetFont(), LABEL_SIZE, "OUTLINE")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(1, 1, 1, 0.9)
    f.label = fs
    -- The press flash. Additive and a hair wider than the bar, so it reads as
    -- the note brightening rather than as something drawn on top of it. Anchored
    -- once; only its alpha ever moves, and only while a flash is live.
    local fl = f:CreateTexture(nil, "OVERLAY")
    fl:SetPoint("TOPLEFT", f, "TOPLEFT", -FLASH_PAD, FLASH_PAD)
    fl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", FLASH_PAD, -FLASH_PAD)
    fl:SetColorTexture(1, 1, 1, 1)
    fl:SetBlendMode("ADD")
    fl:Hide()
    f.flash = fl
    -- The wind-up column (style `scope` = cast/all): the auto item's wash
    -- carried on down through the rows below it. Anchored to the item's top
    -- left so it scrolls and glides with it; only its height is a style.
    local col = f:CreateTexture(nil, "BACKGROUND")
    col:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    col:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    col:Hide()
    f.column = col
    pool[n] = f
    pool.max = n
  end
  return f
end

-- FRAMES ARE BOUND TO KEYS (v3 P2). A frame keeps drawing the item with its key
-- across rebuilds -- so a re-plan that moves a note glides the SAME frame, and
-- text and icon are painted only when they change. `serial` is the rebuild
-- that is claiming frames: a frame the last rebuild did not claim, and that is
-- not mid-fade, is free. Returns the frame and whether it already held the key.
local function poolTake(pool, parent, key, serial)
  local byKey = pool.byKey
  if not byKey then byKey = {}; pool.byKey = byKey end
  local f = byKey[key]
  if f then
    pool.n = pool.n + 1
    f.seen = serial
    return f, true
  end
  for i = 1, pool.max do
    local g = pool[i]
    if g.key == nil or (g.seen ~= serial and not g.fading) then
      if g.key ~= nil then byKey[g.key] = nil end
      g.key, g.seen = key, serial
      byKey[key] = g
      pool.n = pool.n + 1
      return g, false
    end
  end
  local g = poolItemNew(pool, parent)
  g.key, g.seen = key, serial
  byKey[key] = g
  pool.n = pool.n + 1
  return g, false
end

-- The weave band and a running proc span are anchored to the CURSOR, not to an
-- absolute moment: their edges are MEANT to be re-seated at every rebuild. They
-- are keyed all the same (so they never fade in again -- the video's "band pops
-- in and out"), but they must not glide: easing them would drag the one edge
-- that IS absolute, the band's deadline and the proc's expiry, behind by up to
-- the whole ease.
local function noEase(key)
  return key >= TL.KEY.MOVE and key <= TL.KEY.PROC_LAST
end

-- Marks: an invisible button per verdict, carrying the tooltip.
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
    -- Above the item frames (parent + 1), or a verdict arrow drawn over one
    -- would lose its own mouse to the bar underneath it.
    b:SetFrameLevel(parent:GetFrameLevel() + 3)
    b:SetSize(MARK_HIT, MARK_HIT)
    b:EnableMouse(true)
    local t = b:CreateTexture(nil, "OVERLAY")
    t:SetTexture(ARROW_TEX)
    t:SetRotation(ARROW_DOWN)
    t:SetSize(MARK_SIZE, MARK_SIZE)
    t:SetPoint("TOP", b, "TOP", 0, 0)
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
-- Build
----------------------------------------------------------------------------

function View:OnInitialize()
  self._padX = PAD
  self:Measure()
  local f = CreateFrame("Frame", "NockPracticeConveyor", UIParent, "BackdropTemplate")
  f:SetSize(self:UndockedWidth(), self._hostH)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  -- Esc in Focus (UISpecialFrames, joined by SetFocus) hides the frame behind
  -- our back: during a fight that is Stop, and either way it is the way back to
  -- the workbench. Our own hides set _hiding first.
  f:SetScript("OnHide", function()
    local hiding = View._hiding
    View._hiding = false
    if hiding or not View._focus then return end
    local p = practice()
    if p and Nock.state.sim.fightOn and p.StopFight then p:StopFight() end
    Nock:SendMessage("NOCK_PRACTICE_FOCUS", false)
  end)

  -- The lane-label gutter doubles as the drag handle: undocked, the strip is a
  -- tool window and moves whenever no fight runs (the practice-window rule,
  -- not the global lock). Docked, its mouse is off so the panel keeps its own.
  local gutter = CreateFrame("Frame", nil, f)
  gutter:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -self._lanesTop)
  gutter:SetSize(LABEL_W, self._stripH)
  gutter:EnableMouse(false)
  gutter:RegisterForDrag("LeftButton")
  gutter:SetScript("OnDragStart", function()
    if Nock.state.sim.fightOn then return end
    if profile("practiceConveyorDocked", true) then return end
    f:StartMoving()
  end)
  gutter:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    Nock.db.profile.practiceConveyorPos = { point = point, relPoint = relPoint, x = x, y = y }
  end)

  -- The right-edge width grip. A plain mouse strip rather than SetResizable /
  -- StartSizing: the client's resize-bounds setter has moved namespace at least
  -- once (SetMinResize -> SetResizeBounds) and this file cannot verify which one
  -- the Anniversary build ships, whereas GetCursorPosition + SetWidth are on the
  -- allowlist. The drag itself is stepped from the CENTRAL tick (View:DragSize),
  -- never from an OnUpdate of its own.
  local sizer = CreateFrame("Frame", nil, f)
  sizer:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  sizer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  sizer:SetWidth(SIZER_W)
  sizer:SetFrameLevel(f:GetFrameLevel() + 20)
  sizer:EnableMouse(false)
  local sizerHL = sizer:CreateTexture(nil, "HIGHLIGHT")
  sizerHL:SetAllPoints(sizer)
  sizerHL:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
  sizer:SetScript("OnMouseDown", function() View:StartSize() end)
  sizer:SetScript("OnMouseUp", function() View:StopSize() end)

  -- The row labels: icon, name and the bound key, one frame per possible row,
  -- anchored in LayoutRows (the row height is derived and moves with the row
  -- count and the toast font) and painted in PaintRowLabels.
  local rowLabels = {}
  for i = 1, MAX_ROWS do
    local rf = CreateFrame("Frame", nil, gutter)
    -- Taller than the bar: the name and the key stack beside the icon, and
    -- two lines of text do not fit in 22 px (they overlapped, 2026-08-26).
    -- LayoutRows centres the frame on the bar.
    rf:SetSize(LABEL_W - 4, LABEL_H)
    local icon = rf:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", rf, "LEFT", LABEL_INSET, 0)
    icon:SetSize(BAR_H - 2, BAR_H - 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local name = rf:CreateFontString(nil, "OVERLAY")
    Skin.Font(name, "uiMedium", Skin.SIZES.body)
    name:SetPoint("TOPLEFT", rf, "TOPLEFT", LABEL_INSET + BAR_H - 2 + 6, -1)
    name:SetWidth(LABEL_W - LABEL_INSET - BAR_H - 8)
    name:SetJustifyH("LEFT"); name:SetWordWrap(false)
    Skin.Text(name, "ink2")
    local key = rf:CreateFontString(nil, "OVERLAY")
    Skin.Font(key, "mono", Skin.SIZES.key)
    key:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    key:SetWidth(LABEL_W - LABEL_INSET - BAR_H - 8)
    key:SetJustifyH("LEFT"); key:SetWordWrap(false)
    Skin.Text(key, "ink3")
    rf.icon, rf.name, rf.key = icon, name, key
    rf:Hide()
    rowLabels[i] = rf
  end
  self.rowLabels = rowLabels
  self._rows, self._rowIndex, self._nRows = {}, {}, nil
  for i = 1, #DEFAULT_ROWS do self._rows[i] = DEFAULT_ROWS[i]; self._rowIndex[DEFAULT_ROWS[i]] = i end
  self._nRows = #DEFAULT_ROWS

  -- The moving half: `content` carries every item and mark and is slid by ONE
  -- SetPoint per tick; `viewport` clips it.
  local viewport = CreateFrame("Frame", nil, f)
  viewport:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + LABEL_W, -self._lanesTop)
  viewport:SetSize(MIN_LANE_W, self._lanesH)
  if viewport.SetClipsChildren then viewport:SetClipsChildren(true) end
  -- Replay scrub: the wheel over the stage moves the replay clock (see
  -- Practice:ReplayStep) -- 0.25 s a notch, Shift 2 s, Ctrl 0.05 s, Alt the
  -- next/previous clipped auto.
  if viewport.EnableMouseWheel then
    viewport:EnableMouseWheel(true)
    viewport:SetScript("OnMouseWheel", function(_, delta)
      local p = practice()
      if not (p and p._replay) then return end
      local dir = (delta > 0) and 1 or -1
      if IsAltKeyDown and IsAltKeyDown() then p:ReplayStep(dir, "clip")
      elseif IsShiftKeyDown and IsShiftKeyDown() then p:ReplayStep(dir, "sec", 2)
      elseif IsControlKeyDown and IsControlKeyDown() then p:ReplayStep(dir, "sec", 0.05)
      else p:ReplayStep(dir, "sec", 0.25) end
    end)
  end
  local content = CreateFrame("Frame", nil, viewport)
  content:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, 0)
  content:SetSize(MIN_LANE_W, self._lanesH)

  -- The still half: hit line, its triangle, the past/future tints and the
  -- relative second ticks. All of it is pinned to the frame, not to time, so
  -- none of it is touched by a rebuild — only by a resize.
  local overlay = CreateFrame("Frame", nil, f)
  overlay:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, 0)
  overlay:SetSize(MIN_LANE_W, self._stripH)
  overlay:SetFrameLevel(viewport:GetFrameLevel() + 6)

  -- Lane furniture (style `lanes`): one texture per possible row, across the
  -- gutter AND the lanes so a row reads as one thing. Seated in LayoutRows.
  local laneBg = {}
  for i = 1, MAX_ROWS do
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(1, 1, 1, ZEBRA_A)
    t:Hide()
    laneBg[i] = t
  end
  self.laneBg = laneBg

  local pastTint = overlay:CreateTexture(nil, "BACKGROUND")
  pastTint:SetColorTexture(0, 0, 0, 0.22)
  local futureTint = overlay:CreateTexture(nil, "BACKGROUND")
  futureTint:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.04)
  -- The line's glow sits UNDER it (ARTWORK against the line's OVERLAY) and over
  -- the two tints (BACKGROUND). Built once and never touched again except by a
  -- resize: it is a property of the stage, not of anything happening on it.
  local hitGlow = {}
  for i = 1, #HIT_GLOW do
    local t = overlay:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], HIT_GLOW[i][2])
    t:SetBlendMode("ADD")
    hitGlow[i] = t
  end
  -- The NOW column (style `hit` = column): a soft wash either side of the line,
  -- instead of the glow. Seated in Layout, shown by ApplyStyle.
  local hitCol = overlay:CreateTexture(nil, "ARTWORK")
  hitCol:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], HIT_COL_A)
  hitCol:Hide()
  local hit = overlay:CreateTexture(nil, "OVERLAY")
  hit:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.95)
  local head = overlay:CreateTexture(nil, "OVERLAY")
  head:SetTexture(ARROW_TEX)
  head:SetRotation(ARROW_DOWN)
  head:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
  head:SetSize(HEAD_TRI, HEAD_TRI)

  -- Empty state: the lanes are still there and so is the plan, but nothing is
  -- running against them. Centred over the lanes (seated in Layout, which is
  -- where the lane block's size is known), hidden the moment a fight arms.
  local empty = overlay:CreateFontString(nil, "OVERLAY")
  Skin.Font(empty, "ui", Skin.SIZES.body)
  empty:SetJustifyH("CENTER")
  empty:SetWordWrap(false)
  empty:SetText(EMPTY_TEXT)
  Skin.Text(empty, "ink3")
  empty:Hide()

  -- The coach row: one sentence, and the metronome at its right edge. Hung off
  -- the frame's BOTTOM, so whatever slack the derived lane height leaves sits
  -- between the axis and the coach rather than under the row.
  local coach = CreateFrame("Frame", nil, f)
  coach:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  coach:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  coach:SetHeight(COACH_H)

  -- The severity wash: one texture under the whole row, tinted by the grade of
  -- the judgment the sentence is about. Transparent until there is one.
  local coachBg = coach:CreateTexture(nil, "BACKGROUND")
  coachBg:SetAllPoints(coach)
  coachBg:SetColorTexture(1, 1, 1, 0)
  -- The rule over the row: the stage above, the coach under it.
  local coachRule = Skin.Rule(coach, "lineSoft")
  coachRule:SetPoint("TOPLEFT", coach, "TOPLEFT", 0, 0)
  coachRule:SetPoint("TOPRIGHT", coach, "TOPRIGHT", 0, 0)
  coachRule:SetHeight(1)

  local coachKey = coach:CreateFontString(nil, "OVERLAY")
  self.coachKey = coachKey
  Skin.Font(coachKey, "monoMedium", Skin.SIZES.key)
  coachKey:SetPoint("LEFT", coach, "LEFT", LABEL_INSET + PAD, 0)
  -- The paper-note icon (a planned clip's clock, a tight weave's triangle),
  -- shown with the ARMED line on a paper that costs by design.
  local coachIco = coach:CreateTexture(nil, "OVERLAY")
  coachIco:SetPoint("LEFT", coachKey, "RIGHT", 8, 0)
  Skin.Icon(coachIco, "warn", "wait")
  Skin.IconSize(coachIco)
  coachIco:Hide()
  self.coachIco = coachIco
  coachKey:SetJustifyH("LEFT")
  coachKey:SetText("COACH")
  Skin.Text(coachKey, "ink3")

  local metW = MET_DOTS * MET_DOT + (MET_DOTS - 1) * MET_GAP
  local coachLine = coach:CreateFontString(nil, "OVERLAY")
  Skin.Font(coachLine, "ui", Skin.SIZES.body)
  coachLine:SetPoint("LEFT", coachKey, "RIGHT", 10, 0)
  self._coachLineX = 10
  coachLine:SetPoint("RIGHT", coach, "RIGHT", -(metW + 14 + PAD), 0)
  coachLine:SetJustifyH("LEFT")
  coachLine:SetWordWrap(false)
  Skin.Text(coachLine, "ink2")

  local met = {}
  for i = 1, MET_DOTS do
    local t = coach:CreateTexture(nil, "OVERLAY")
    t:SetSize(MET_DOT, MET_DOT)
    t:SetPoint("RIGHT", coach, "RIGHT", -((MET_DOTS - i) * (MET_DOT + MET_GAP)) - PAD, 0)
    t:SetColorTexture(MET_OFF[1], MET_OFF[2], MET_OFF[3], 1)
    met[i] = t
  end

  -- THE FOCUS HEAD (shell step 3): one line over the lanes while the stage is
  -- alone on the HUD -- state chip, scenario, streak, STOP, and the way back.
  -- Built here, PAINTED by the practice panel (UI/Frame_Practice.lua writes
  -- the chip, the name and the streak into it beside its own), shown by
  -- ApplyDock only in Focus. The head drags the stage between fights; during
  -- one its mouse is off (a weave key is usually a mouse button), the two
  -- buttons keep theirs.
  local fh = CreateFrame("Frame", nil, f)
  fh:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  fh:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  fh:SetHeight(HEAD_H)
  Skin.Surface(fh, "surface2")
  local fhRule = Skin.Rule(fh, "lineSoft")
  fhRule:SetPoint("BOTTOMLEFT", fh, "BOTTOMLEFT", 0, 0)
  fhRule:SetPoint("BOTTOMRIGHT", fh, "BOTTOMRIGHT", 0, 0)
  fhRule:SetHeight(1)
  fh:EnableMouse(false)
  fh:RegisterForDrag("LeftButton")
  fh:SetScript("OnDragStart", function()
    if Nock.state.sim.fightOn then return end
    f:StartMoving()
  end)
  fh:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    Nock.db.profile.practiceConveyorPos = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  local fhChip = Skin.Chip(fh)
  fhChip:SetPoint("LEFT", fh, "LEFT", LABEL_INSET, 0)
  local fhName = fh:CreateFontString(nil, "OVERLAY")
  Skin.Font(fhName, "ui", Skin.SIZES.body)
  fhName:SetPoint("LEFT", fhChip, "RIGHT", 10, 0)
  fhName:SetJustifyH("LEFT"); fhName:SetWordWrap(false)
  Skin.Text(fhName, "ink2")
  local fhStreak = fh:CreateFontString(nil, "OVERLAY")
  Skin.Font(fhStreak, "monoMedium", Skin.SIZES.mono)
  fhStreak:SetPoint("LEFT", fhName, "RIGHT", 14, 0)
  fhStreak:SetJustifyH("LEFT"); fhStreak:SetWordWrap(false)
  Skin.Text(fhStreak, "ink")
  local fhBack = Skin.Button(fh, "WORKBENCH", "ghost", nil, HEAD_H - 6)
  Skin.Font(fhBack.text, "monoMedium", Skin.SIZES.key)
  Skin.SetButtonText(fhBack, "WORKBENCH")
  fhBack:SetPoint("RIGHT", fh, "RIGHT", -LABEL_INSET, 0)
  fhBack.tipTitle = "Back to the workbench"
  fhBack.tipText = "The fight keeps running. Esc during a fight stops it."
  fhBack:SetScript("OnClick", function() Nock:SendMessage("NOCK_PRACTICE_FOCUS", false) end)
  -- LOG: the weave log panel beside the stage (practiceWeaveLog), lit while on.
  local fhLog = Skin.Button(fh, "LOG", "ghost", nil, HEAD_H - 6)
  Skin.Font(fhLog.text, "monoMedium", Skin.SIZES.key)
  Skin.SetButtonText(fhLog, "LOG")
  fhLog:SetPoint("RIGHT", fhBack, "LEFT", -6, 0)
  fhLog.tipTitle = "Weave log"
  fhLog.tipText = "One row per weave: the hit, the legs, the re-arm cost, the verdict."
  fhLog:SetScript("OnClick", function()
    if not (Nock.db and Nock.db.profile) then return end
    Nock.db.profile.practiceWeaveLog = not (Nock.db.profile.practiceWeaveLog == true)
    View:PaintLogButton()
    local wl = Nock:GetModule("PracticeWeaveLogView", true)
    if wl and wl.Apply then wl:Apply() end
  end)
  fh.log = fhLog
  local fhStop = Skin.Button(fh, "STOP", "danger", nil, HEAD_H - 6)
  Skin.Font(fhStop.text, "monoMedium", Skin.SIZES.key)
  Skin.SetButtonText(fhStop, "STOP")
  fhStop:SetPoint("RIGHT", fhLog, "LEFT", -6, 0)
  fhStop:SetScript("OnClick", function()
    local p = practice()
    if not p then return end
    if Nock.state.sim.fightOn then p:StopFight() else p:StartFight() end
  end)
  fh.chip, fh.name, fh.streak, fh.stop, fh.back = fhChip, fhName, fhStreak, fhStop, fhBack
  fh:Hide()
  self.focusHead = fh

  -- The replay transport (UI/PracticeTransport.lua, shared with the expert
  -- combat log), in the coach row's place -- a level above it, with its own
  -- fill, so the sentence and the metronome are covered while a stopped
  -- fight is being scrubbed. Ticked and painted from Refresh.
  local tr = Transport.New(f, COACH_H, LABEL_INSET + PAD)
  tr:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  tr:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  tr:SetFrameLevel(coach:GetFrameLevel() + 2)
  self.transport = tr

  -- The NEXT chip (style `next` = both/chip): one tile with the word and the
  -- key, hung off the next note's own frame so it scrolls and glides with it.
  -- On the content, a level above the items.
  local chip = CreateFrame("Frame", nil, content)
  chip:SetFrameLevel(content:GetFrameLevel() + 3)
  chip:SetSize(30, CHIP_H)
  local chipBg = chip:CreateTexture(nil, "BACKGROUND")
  chipBg:SetAllPoints(chip)
  chipBg:SetColorTexture(CHIP_NEXT[1], CHIP_NEXT[2], CHIP_NEXT[3], 0.95)
  local chipText = chip:CreateFontString(nil, "OVERLAY")
  Skin.Font(chipText, "monoMedium", CHIP_SIZE)
  chipText:SetPoint("LEFT", chip, "LEFT", CHIP_PAD, 0)
  chipText:SetJustifyH("LEFT")
  chipText:SetWordWrap(false)
  chipText:SetTextColor(0.04, 0.05, 0.06, 1)
  chip.bg, chip.text = chipBg, chipText
  chip:Hide()
  self.chip = chip
  self.hitCol = hitCol

  self.frame, self.gutter, self.viewport, self.content = f, gutter, viewport, content
  self.overlay, self.hit, self.head = overlay, hit, head
  self.sizer, self.hitGlow, self.empty = sizer, hitGlow, empty
  self.pastTint, self.futureTint = pastTint, futureTint
  self.coach, self.coachBg, self.coachLine, self.met = coach, coachBg, coachLine, met
  -- Metronome flash state, allocated once: when each dot was lit, and with
  -- which colour table (a reference to one of the constants above).
  self._metAt, self._metCol = {}, {}
  for i = 1, MET_DOTS do self._metAt[i] = 0 end
  self.pools = { item = newPool(), tick = newPool(), tickLabel = newPool(),
                 mark = newPool(), pop = newPool() }
  -- Every per-rebuild table, allocated once here.
  self._out = { items = {}, nItems = 0, marks = {}, nMarks = 0 }
  -- key -> the absolute t0 each keyed item is being DRAWN at, captured off the
  -- frames the last rebuild left behind. Wiped and refilled per rebuild; integer
  -- keys and number values, so it stops allocating once it has been round the
  -- lanes once.
  self._live = {}
  self._opts = {}
  -- The paper handle T.Strip projects the forecast from, and the haste table it
  -- reads: both filled in place per rebuild, never re-allocated.
  self._laneW, self._hitX, self._pps = MIN_LANE_W, 0, 90
  self._t0, self._builtAt = 0, 0
  self._blanked = false
  self._weaveNext, self._weaveTight = false, false
  self._washSev = nil
  self._emptyOn = false
  self._sizeFrom = nil
  self:SetCoach(COACH_IDLE)
  f:Hide()
end

----------------------------------------------------------------------------
-- Width. The docked stage is exactly as wide as the panel; the undocked one is
-- whatever the player has dragged its right edge to, and the visible TIME
-- window follows from that at a constant px/s (View:Layout).
----------------------------------------------------------------------------

-- Re-anchor to the current top-left before a right-edge drag, so the width grows
-- rightwards instead of splitting either side of a CENTER anchor (which is the
-- undocked default). Persisted on mouse-up like any other move.
function View:StartSize()
  local f = self.frame
  if not f then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if self._docked then return end
  -- The same gate the move-drag runs on: practice windows are tools, and a
  -- fight is the one time their geometry is not the player's to touch.
  if Nock.state and Nock.state.sim and Nock.state.sim.fightOn then return end
  local scale = f:GetEffectiveScale() or 1
  if scale <= 0 then scale = 1 end
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  end
  self._sizeFrom = (GetCursorPosition()) / scale
  self._sizeW = f:GetWidth() or MIN_W
end

function View:StopSize()
  local f = self.frame
  if not (f and self._sizeFrom) then return end
  self._sizeFrom, self._sizeW = nil, nil
  -- The window just grew, but the forecast in it was built for the old one, and
  -- the idle rebuild floor is half a second: the new lane would sit empty for
  -- that long, which reads as the drag having broken the strip. Age the build
  -- out and the very next tick refills to the wider horizon. Before the db
  -- guard: the refill is not conditional on being able to SAVE the width.
  self._builtAt = 0
  if not (Nock.db and Nock.db.profile) then return end
  -- ...but a drag that ended because the strip DOCKED must not save anything:
  -- the width and the anchor are the panel's from that moment, and writing them
  -- into the undocked keys would hand the next undock the panel's geometry.
  if self._docked then return end
  Nock.db.profile.practiceConveyorW = math.floor((f:GetWidth() or MIN_W) + 0.5)
  local point, _, relPoint, x, y = f:GetPoint()
  Nock.db.profile.practiceConveyorPos = { point = point, relPoint = relPoint, x = x, y = y }
end

-- One step of the drag, from the central tick. Gated on `_sizeFrom` being set,
-- so the tick pays a single nil test the rest of the time. The mouse-button
-- test is the belt for a release that landed somewhere our OnMouseUp never saw.
function View:DragSize()
  local f = self.frame
  if not f then return end
  -- Docked mid-drag (the Options toggle, the grip's right-click, a profile
  -- swap): the width is the panel's from that moment on, and a live drag would
  -- fight ApplyDock for it every tick. Finish the drag instead of steering it.
  if self._docked then return self:StopSize() end
  if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return self:StopSize() end
  local scale = f:GetEffectiveScale() or 1
  if scale <= 0 then scale = 1 end
  local w = self._sizeW + ((GetCursorPosition()) / scale - self._sizeFrom)
  local floorW = MIN_LANE_W + LABEL_W + PAD * 2
  if floorW < MIN_W then floorW = MIN_W end
  if w < floorW then w = floorW elseif w > MAX_W then w = MAX_W end
  local cur = f:GetWidth() or 0
  if w > cur - 1 and w < cur + 1 then return end
  f:SetWidth(w)
  self:Layout()
end

function View:OnEnable()
  TL = Nock.PracticeTimeline
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "OnPracticeChanged")
  self:RegisterMessage("NOCK_PRACTICE_RESET_POS", "ResetPos")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyDock")
  self:ApplyDock()
end

function View:GetFrame() return self.frame end
function View:FocusHead() return self.focusHead end

-- The LOG button's state, from the setting (Options writes it too).
function View:PaintLogButton()
  local fh = self.focusHead
  if not (fh and fh.log) then return end
  local on = profile("practiceWeaveLog", false) and true or false
  local p = practice()
  local weaves = (p and p.PaperWeaves and p:PaperWeaves()) and true or false
  if weaves then fh.log:Show() else fh.log:Hide() end
  fh.stop:ClearAllPoints()
  fh.stop:SetPoint("RIGHT", weaves and fh.log or fh.back, "LEFT", -6, 0)
  if on == self._logOn then return end
  self._logOn = on
  Skin.ButtonKind(fh.log, on and "primary" or "ghost")
end
function View:IsFocus() return self._focus and true or false end

-- Hide the frame ourselves (never Esc): OnHide reads the flag.
function View:HideFrame()
  local f = self.frame
  if f and f:IsShown() then self._hiding = true; f:Hide() end
end

-- FOCUS: the stage alone on the HUD -- undocked whatever the dock setting
-- says (the setting is untouched: Focus is a mode, not a preference), with the
-- head line over the lanes, at its own saved spot and width. Esc joins the
-- frame to UISpecialFrames for as long as it lasts.
function View:SetFocus(on)
  on = on and true or false
  if on == (self._focus or false) then return end
  self._focus = on
  if on then
    if UISpecialFrames then
      local found = false
      for i = 1, #UISpecialFrames do if UISpecialFrames[i] == "NockPracticeConveyor" then found = true end end
      if not found then tinsert(UISpecialFrames, "NockPracticeConveyor") end
    end
  elseif UISpecialFrames then
    for i = #UISpecialFrames, 1, -1 do
      if UISpecialFrames[i] == "NockPracticeConveyor" then table.remove(UISpecialFrames, i) end
    end
  end
  self:ApplyDock()
end

-- The judgment streak, for the header strip. Practice:Lookahead publishes both
-- numbers and the tick fills this view's own `live` table with them, so the
-- header can read them from here whether the stage is docked or floating —
-- without a second Lookahead call, and without reaching into the grader.
-- Returns 0, 0 before the first fight.
function View:Streak()
  -- `_live` is only refilled while a fight runs, so it goes stale the moment
  -- one ends: no fight, no streak.
  if not (Nock.state and Nock.state.sim and Nock.state.sim.fightOn) then return 0, 0 end
  local live = self._live
  return (live and live.streak) or 0, (live and live.bestStreak) or 0
end

-- The strip is only ever as interesting as the drill: practice off, no lanes.
function View:OnPracticeChanged()
  local f = self.frame
  if not f then return end
  self:ApplyDock()
  if not Nock.state.sim.active then
    self:Blank()
    self:HideFrame()
  end
end

function View:ResetPos()
  local f = self.frame
  if not f then return end
  Nock.db.profile.practiceConveyorPos = nil
  self:ApplyDock()
end

----------------------------------------------------------------------------
-- Docking. The panel owns the docked geometry (it calls Host from Relayout);
-- undocked, the strip is a plain tool window of its own.
----------------------------------------------------------------------------

-- Called by UI/Frame_Practice.lua from its Relayout. Returns the height the
-- panel must reserve below its last row — 0 when the strip is elsewhere.
-- `flush`: the panel is hosted in the workbench, and the stage sits edge to
-- edge under its toolbar with no gap and no side inset (the rows run the
-- whole width, as the "Workbench States" page draws them).
function View:Host(panel, anchor, flush)
  if not self.frame then return 0 end
  self._host, self._anchor, self._flush = panel, anchor, flush and true or false
  self:ApplyDock()
  -- The gap is ours (ApplyDock seats the strip with it), so the height the
  -- panel reserves has to include it: gap + host, never just the host.
  return self._docked and (self:DockGap() + self._hostH) or 0
end

function View:DockGap() return self._flush and 0 or DOCK_GAP end

function View:IsDocked() return self._docked and true or false end

function View:ApplyDock()
  local f = self.frame
  if not f then return end
  -- The style levers can have changed under us too (Options and the slash
  -- both land on NOCK_VISUALS_CHANGED): re-read them before Layout seats the
  -- furniture and before the next rebuild paints.
  self:ApplyStyle()
  -- A width drag in flight is over: this function is about to write the width
  -- and the anchor itself, from the dock state rather than from the cursor, and
  -- a live drag would overwrite it again on the next tick. Dropped rather than
  -- finished -- StopSize would persist a width that is no longer the player's
  -- pick.
  self._sizeFrom, self._sizeW = nil, nil
  -- The toast font size can have changed under us (NOCK_VISUALS_CHANGED lands
  -- here): re-measure the band and re-seat the two frames hung off it before
  -- anything reads the new height.
  self:Measure()
  -- Focus overrides the dock setting without writing it; hosted flush in the
  -- workbench, the stage has no side inset at all.
  local docked = profile("practiceConveyorDocked", true) and true or false
  if self._focus then docked = false end
  local host, anchor = self._host, self._anchor
  -- The panel has not hosted us yet (first Relayout still to come): float
  -- rather than parent to nothing.
  if docked and not host then docked = false end
  local padX = (docked and self._flush) and 0 or PAD
  self._padX = padX
  self.gutter:ClearAllPoints()
  self.gutter:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -self._lanesTop)
  self.gutter:SetSize(LABEL_W, self._stripH)
  self.viewport:ClearAllPoints()
  self.viewport:SetPoint("TOPLEFT", f, "TOPLEFT", padX + LABEL_W, -self._lanesTop)
  f:ClearAllPoints()
  f:SetBackdrop(nil)
  local fh = self.focusHead
  if docked then
    f:SetParent(host)
    f:SetFrameStrata(host:GetFrameStrata())
    f:SetToplevel(false)
    Skin.Surface(f, "ground", nil, 0)   -- the panel's own surface shows through
    if anchor then f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -self:DockGap())
    else f:SetPoint("TOPLEFT", host, "TOPLEFT", padX, -padX) end
    local w = (host:GetWidth() or 0) - padX * 2
    if w < MIN_LANE_W + LABEL_W then w = MIN_LANE_W + LABEL_W end
    f:SetWidth(w)
    self.gutter:EnableMouse(false)
    self.sizer:EnableMouse(false)
    if fh then fh:Hide(); fh:EnableMouse(false) end
  else
    f:SetParent(UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    Skin.Surface(f, "surface", "line")
    local pos = profile("practiceConveyorPos", nil)
    if pos then f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    -- Default: ABOVE the HUD centre. The review window's own default is
    -- (0, -120), and the two used to open on top of each other.
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, 340) end
    f:SetWidth(self:UndockedWidth())
    -- A mouse-enabled frame under the pointer SWALLOWS mouse buttons -- and a
    -- weave key is usually one (MOUSE4/5). The drag handle takes the mouse only
    -- while no fight runs (it never drags during one anyway).
    local fighting = Nock.state.sim.fightOn == true
    self.gutter:EnableMouse(not fighting)
    self.sizer:EnableMouse(not fighting)
    if fh then
      if self._focus then fh:Show(); self:PaintLogButton() else fh:Hide() end
      fh:EnableMouse(self._focus and not fighting)
    end
  end
  if self.coach then
    if self._coachH > 0 then self.coach:Show() else self.coach:Hide() end
  end
  -- The practice scale. Docked we are a CHILD of the panel and already carry
  -- its scale, so ours must stay 1 or the stage is scaled twice; floating we
  -- are our own top-level window and take the slider's value like the rest.
  f:SetScale(docked and 1 or Nock.UI.PracticeScale())
  f:SetHeight(self._hostH)
  self._docked = docked
  self:Layout()
end

-- The panel's Undock/Dock button.
function View:ToggleDock()
  Nock.db.profile.practiceConveyorDocked = not (profile("practiceConveyorDocked", true) and true or false)
  self:ApplyDock()
  -- The panel has to re-measure: docked, the strip is part of its height. Its
  -- OWN message, not NOCK_PRACTICE_CHANGED — a dock flip changes nothing about
  -- the drill, and the broad message rebuilds the picker and every other
  -- listener for a change none of them can see.
  Nock:SendMessage("NOCK_PRACTICE_DOCK_CHANGED")
end

----------------------------------------------------------------------------
-- Layout: everything that depends on width / pps / the window seconds, and on
-- nothing else. Called on a dock change, never from the tick.
----------------------------------------------------------------------------

function View:Layout()
  local f = self.frame
  if not f then return end
  local padX = self._padX or PAD
  local laneW = (f:GetWidth() or 0) - padX * 2 - LABEL_W
  if laneW < MIN_LANE_W then laneW = MIN_LANE_W end
  local pps = profile("practiceConveyorPps", 90)
  if pps < 20 then pps = 20 elseif pps > 400 then pps = 400 end
  local past = profile("practiceConveyorPast", 2)
  local future = profile("practiceConveyorFuture", 4.5)
  local hitFrac = profile("practiceConveyorHit", 0.30)
  if hitFrac < 0.05 then hitFrac = 0.05 elseif hitFrac > 0.95 then hitFrac = 0.95 end
  local hitX = math.floor(laneW * hitFrac + 0.5)
  -- THE WINDOW IS THE WIDTH. px/s is constant, so the seconds either side of the
  -- hit line are whatever the lane's pixels buy -- drag the undocked stage wider
  -- and you see MORE TIME, not stretched notes. The two settings survive as
  -- FLOORS: they still guarantee a lookahead on a narrow strip, and a lane wide
  -- enough to beat them takes over. Without this the forecast stopped at 4.5 s
  -- and the extra width was empty lane.
  local geomPast = hitX / pps
  local geomFuture = (laneW - hitX) / pps
  if geomPast > past then past = geomPast end
  if geomFuture > future then future = geomFuture end

  local lanesH, laneH, markRow = self._lanesH, self._laneH, self._markRow
  self._laneW, self._pps, self._past, self._future, self._hitX = laneW, pps, past, future, hitX
  -- What the strip can show, for the oracle: the plan is built to reach this
  -- far (Practice:PublishPlan; the profile values are its floors).
  local sim = Nock.state.sim
  sim.horizonPast, sim.horizonFuture = past, future
  self.viewport:SetSize(laneW, lanesH)
  self.overlay:SetSize(laneW, self._stripH)
  -- Slack either side: an item straddling the window edge is drawn whole and
  -- clipped by the viewport, not truncated by the content frame.
  self.content:SetSize((past + future) * pps + laneW * 2, lanesH)

  self:LayoutRows()

  self.pastTint:ClearAllPoints()
  self.pastTint:SetSize(math.max(1, hitX), lanesH)
  self.pastTint:SetPoint("TOPLEFT", self.overlay, "TOPLEFT", 0, 0)
  self.futureTint:ClearAllPoints()
  self.futureTint:SetSize(math.max(1, laneW - hitX), lanesH)
  self.futureTint:SetPoint("TOPLEFT", self.overlay, "TOPLEFT", hitX, 0)
  for i = 1, #HIT_GLOW do
    local t = self.hitGlow[i]
    local gw = HIT_GLOW[i][1]
    t:ClearAllPoints()
    t:SetSize(gw, lanesH)
    t:SetPoint("TOPLEFT", self.overlay, "TOPLEFT", hitX - gw / 2, 0)
  end
  if self.hitCol then
    self.hitCol:ClearAllPoints()
    self.hitCol:SetSize(HIT_COL_W, lanesH)
    self.hitCol:SetPoint("TOPLEFT", self.overlay, "TOPLEFT", hitX - HIT_COL_W / 2, 0)
  end
  self:ApplyHitStyle()
  self.hit:ClearAllPoints()
  self.hit:SetSize(2, lanesH)
  self.hit:SetPoint("TOPLEFT", self.overlay, "TOPLEFT", hitX - 1, 0)
  self.head:ClearAllPoints()
  self.head:SetPoint("TOP", self.overlay, "TOPLEFT", hitX, 1)
  if self.empty then
    self.empty:ClearAllPoints()
    self.empty:SetPoint("CENTER", self.overlay, "TOPLEFT", laneW / 2, -lanesH / 2)
  end

  -- Relative second ticks. They mark distance from the hit line, not absolute
  -- fight time, so their pixels never move and their labels never change.
  local pools = self.pools
  poolReset(pools.tick); poolReset(pools.tickLabel)
  local first, last = -math.floor(past), math.floor(future)
  for k = first, last do
    if k ~= 0 then
      local x = hitX + k * pps
      if x >= 0 and x <= laneW then
        local line = poolTexture(pools.tick, self.overlay, "BACKGROUND")
        line:SetColorTexture(1, 1, 1, 0.07)
        line:SetSize(1, lanesH)
        line:SetPoint("TOPLEFT", self.overlay, "TOPLEFT", x, 0)
        local fs = poolFontString(pools.tickLabel, self.overlay, LABEL_SIZE, "mono")
        fs:SetWidth(30)
        fs:SetPoint("TOPLEFT", self.overlay, "TOPLEFT", x + 2, -lanesH - 3)
        fs:SetText(("%+ds"):format(k))
        Skin.Text(fs, "ink3")
      end
    end
  end
  poolHideRest(pools.tick); poolHideRest(pools.tickLabel)

  self:AnchorToast()
end

-- The verdict toast rides the hit line: the call it is judging happened there.
-- Only the anchor moves — PracticeView still owns the text, colour and fade.
--
-- INSIDE the strip, in the reserved band above the lanes: hung off the frame's
-- own top edge it landed on the panel's scenario row, which reads as a caption
-- for the scenario card rather than a verdict on the shot that just went out —
-- and hung off the lanes' top it covered the SHOTS bar instead.
--
-- The toast frame is sized to the band so its centred text sits in the middle
-- of it: the font size is a setting, and a bigger one then grows symmetrically
-- into the panel gap above rather than downwards over the lanes.
function View:AnchorToast()
  local pv = Nock:GetModule("PracticeView", true)
  local t = pv and pv.toast
  if not (t and self.frame) then return end
  t:SetParent(self.frame)
  t:SetHeight(self._toastGutter or TOAST_GUTTER_MIN)
  t:ClearAllPoints()
  t:SetPoint("TOP", self.frame, "TOPLEFT", (self._padX or PAD) + LABEL_W + (self._hitX or 0), -((self._headH or 0) + 2))
end

----------------------------------------------------------------------------
-- Painting
----------------------------------------------------------------------------

-- Which word this item wears. There is only one word -- NEXT -- and the PLAN
-- (Core/PracticePlan.lua) put it on exactly one note; T.Strip copies it onto
-- that item. No debounce: the plan changes its mind only on an event (a press,
-- a release, a verdict), never at a rebuild of its own.
function View:LabelFor(it)
  -- The word NEXT lives in the note only for style `next` = word; the other
  -- three styles say it with brightness and/or the chip above the note.
  if it.label == NEXT_LABEL and STYLE.next ~= "word" then return nil end
  return it.label
end

----------------------------------------------------------------------------
-- Style (P3 polish). The levers live in the profile (T.STYLE_LEVERS defines
-- them); this reads them into STYLE and makes every frame repaint on the next
-- rebuild WITHOUT losing its key -- a style change is a repaint, never a
-- re-seat, so nothing fades in again.
----------------------------------------------------------------------------

function View:ApplyStyle()
  local levers = TL and TL.STYLE_LEVERS
  if not levers then return end
  local changed = false
  for i = 1, #levers do
    local L = levers[i]
    local v = profile(L.key, L.values[1])
    if not L.allowed[v] then v = L.values[1] end
    if STYLE[L.lever] ~= v then STYLE[L.lever] = v; changed = true end
  end
  if not changed then return end
  local pool = self.pools and self.pools.item
  if pool then
    for i = 1, pool.max do
      local f = pool[i]
      -- Every paint cache but the seat: the frame keeps its key, its place and
      -- its glide, and PaintItem finds nothing it drew before matches.
      f.w, f.fillA, f.edgeA, f.labelText, f.hiA, f.ew, f.tickW, f.colH, f.ramp = nil, nil, nil, nil, nil, nil, nil, nil, nil
    end
  end
  self:ApplyHitStyle()
  self:LayoutRows()
  -- A rebuild on the next tick, whatever the plan's revision says.
  self._lastRev = nil
end

-- The hit line's furniture: the NOW column (style column) or the glow (line).
function View:ApplyHitStyle()
  local col = (STYLE.hit == "column")
  if self.hitCol then
    if col then self.hitCol:Show() else self.hitCol:Hide() end
  end
  if self.hitGlow then
    for i = 1, #self.hitGlow do
      if col then self.hitGlow[i]:Hide() else self.hitGlow[i]:Show() end
    end
  end
end

-- How far the auto row's wind-up wash reaches down from the bar's top (style
-- `scope`): to the bottom of the last shot row (cast), or of the last row
-- (all). 0 when there is nothing below the auto row to reach.
local CAST_ROWS = { "s", "m", "A" }
function View:ColumnHeight(scope)
  local last = 0
  if scope == "all" then
    last = self._nRows or 0
  elseif scope == "cast" then
    local idx = self._rowIndex
    for k = 1, #CAST_ROWS do
      local i = idx[CAST_ROWS[k]]
      if i and i > last then last = i end
    end
  end
  local auto = self._rowIndex.auto or 1
  if last <= auto then return 0 end
  return (last - auto + 1) * self._laneH - self._markRow
end

-- The NEXT chip. Rides the next note's frame (anchored to it, so it scrolls and
-- glides with it); the word is NEXT, or MOVE once the step-in for a weave has
-- opened; the key is the row's bound key. Text, colour and anchor are all
-- change-gated, and the chip hides when no note is next.
function View:PaintChip(now)
  local chip = self.chip
  if not chip then return end
  local st = STYLE.next
  local f, it = self._nextFrame, self._nextIt
  if not (f and it and (st == "both" or st == "chip")) then
    if self._chipFrame then chip:Hide(); self._chipFrame, self._chipText = nil, nil end
    return
  end
  local live = self._live
  local moving = (it.row == "w") and live and live.weaveMoveAt and live.now and live.now >= live.weaveMoveAt
  local p = practice()
  local key = (p and p.RowKey) and p:RowKey(it.row) or nil
  local text = (moving and "MOVE" or "NEXT") .. (key and (" " .. key) or "")
  if text ~= self._chipText then
    self._chipText = text
    chip.text:SetText(text)
    chip:SetWidth((chip.text:GetStringWidth() or 20) + CHIP_PAD * 2)
    local c = moving and CHIP_MOVE or CHIP_NEXT
    chip.bg:SetColorTexture(c[1], c[2], c[3], 0.95)
  end
  if f ~= self._chipFrame then
    self._chipFrame = f
    chip:ClearAllPoints()
    chip:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 1)
    chip:Show()
  end
end

function View:PaintItem(it, now, serial)
  local lane = self._rowIndex[it.row]
  if not lane then return end
  local pps = self._pps
  local w = (it.t1 - it.t0) * pps
  if w < 2 then w = 2 end
  local y = -((lane - 1) * self._laneH) - self._markRow
  local col = TL.COLORS[it.oncd and ONCD_COLOR or it.color] or TL.COLORS.g
  local r, g, b = col[1], col[2], col[3]
  local key = it.key or -(self.pools.item.n + 1)
  local f, known = poolTake(self.pools.item, self.content, key, serial)
  -- A `thin` item is a WINDOW, not something you press: it takes half the lane
  -- and sits along the bottom of it, under the bars, so the lane still reads as
  -- a row of events with a floor rather than as one big box. (The weave band at
  -- full height WAS the box — see T.Strip.)
  -- ...and a TIGHT window is thinner again and dimmer below: the engine found
  -- no gap a whole weave fits in and answered with the roomiest one there is
  -- (E.WeaveWindow). Drawn like a real gap it would be an invitation to a weave
  -- that cannot land, so it reads as a hairline instead — and the coach says so
  -- in words.
  -- WHAT KIND OF THING THIS IS decides how it is painted (P3 polish). Four
  -- classes: the auto row's grid (a wash with a release tick), the move-in ramp
  -- ahead of a weave, a window (the weave band), and everything you press or
  -- pressed -- a note. Each reads its own style lever(s).
  local isAuto = (it.row == "auto") and it.sym == "a"
  local isMove = (key == TL.KEY.MOVE)
  local isBand = it.band and not isMove
  local isNext = (it.label == NEXT_LABEL)
  local played = (it.key ~= nil) and it.key >= TL.KEY.PLAYED
  local isNote = not (isAuto or isMove or isBand)
  local ramp = isMove and STYLE.move == "ramp"
  local barH = BAR_H
  -- A `thin` item is a WINDOW, not something you press: it takes half the lane
  -- and sits along the bottom of it, under the bars. (The weave band at full
  -- height WAS the box -- see T.Strip.) A tight window is thinner again. The
  -- ramp is the exception: a gradient needs its height to read as one.
  if it.thin and not ramp then
    barH = math.floor(BAR_H / (it.tight and 3 or 2))
    if barH < 2 then barH = 2 end
    y = y - (BAR_H - barH)     -- along the BOTTOM of the lane
  end
  -- Fill and edge alphas, the top highlight (glass), the edge colour (white for
  -- the next note when it is brightened), the tick width and the column height
  -- (the auto row), all by class and style.
  local fillA, edgeA, hiA, ew, tickW, colH = 0, nil, nil, false, nil, 0
  local bright = isNote and isNext and (STYLE.next == "both" or STYLE.next == "bright")
  if isMove then
    if ramp then fillA = RAMP_A1
    elseif STYLE.move == "edge" then fillA, tickW = 0.05, 3
    else fillA = (it.tight and 0.12 or 0.20) end
  elseif isBand then
    fillA = (it.tight and 0.12 or 0.20)
  elseif isAuto then
    fillA = WINDUP_ALPHA[STYLE.windup] or WINDUP_ALPHA.faint
    -- A delayed auto keeps its fault colour, and says so.
    if it.color == "bad" then fillA = 0.45 end
    tickW = TICK_W[STYLE.tick] or 1
    if STYLE.scope ~= "auto" and fillA > 0 then colH = self:ColumnHeight(STYLE.scope) end
  else
    local ns = STYLE.note
    if ns == "solid" or (ns == "outline" and (isNext or played)) then fillA = 0.9
    elseif ns == "outline" then fillA, edgeA = 0.06, GLASS_EDGE
    else fillA, edgeA, hiA = GLASS_FILL, GLASS_EDGE, GLASS_HI end
    if bright then
      fillA = fillA + 0.15
      if fillA > 1 then fillA = 1 end
      edgeA, ew = 1, true
    end
  end

  -- PAINT ONLY WHAT CHANGED. The frame remembers the shape, colours, icon and
  -- word it last drew; a rebuild that moves nothing costs no SetText, no
  -- GetStringWidth, no texture set -- which, with every item keyed, is most of
  -- them.
  local wPx = math.floor(w * 4 + 0.5) / 4
  local shape = (f.w ~= wPx) or (f.barH ~= barH)
  if shape then
    f:SetSize(w, barH)
    f.w, f.barH = wPx, barH
  end
  local e = f.edges
  local colour = (f.r ~= r) or (f.g ~= g) or (f.b ~= b) or (f.fillA ~= fillA) or (f.edgeA ~= edgeA)
    or (f.hiA ~= hiA) or (f.ew ~= ew) or (f.tickW ~= tickW) or (f.colH ~= colH) or (f.ramp ~= ramp)
  if colour or shape then
    local fill = f.fill
    -- The ramp is a gradient across the fill, transparent at the leave point
    -- and amber at the hit. SetGradient takes ColorMixins on this client;
    -- guarded, with the older signature and a flat wash as the fallbacks. A
    -- frame that last drew a ramp is flattened again before it draws anything
    -- else: the gradient is a vertex tint and outlives SetColorTexture.
    if ramp or f.ramp then
      local a0, a1 = ramp and RAMP_A0 or 1, ramp and RAMP_A1 or 1
      local c0r, c0g, c0b = ramp and r or 1, ramp and g or 1, ramp and b or 1
      if fill.SetGradient and CreateColor then
        fill:SetColorTexture(1, 1, 1, 1)
        fill:SetGradient("HORIZONTAL", CreateColor(c0r, c0g, c0b, a0), CreateColor(c0r, c0g, c0b, a1))
        if not ramp then fill:SetColorTexture(r, g, b, fillA) end
      elseif fill.SetGradientAlpha then
        fill:SetColorTexture(1, 1, 1, 1)
        fill:SetGradientAlpha("HORIZONTAL", c0r, c0g, c0b, a0, c0r, c0g, c0b, a1)
        if not ramp then fill:SetColorTexture(r, g, b, fillA) end
      else
        fill:SetColorTexture(r, g, b, ramp and RAMP_FLAT or fillA)
      end
    else
      fill:SetColorTexture(r, g, b, fillA)
    end
    -- Edges: the outline (glass / outline / the brightened next note, white),
    -- or nothing. The top edge doubles as the glass highlight.
    if edgeA then
      e[1]:SetSize(w, 1)
      e[2]:SetSize(w, 1)
      e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); e[3]:SetSize(1, barH)
      e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); e[4]:SetSize(1, barH)
      local er, eg, eb = r, g, b
      if ew then er, eg, eb = 1, 1, 1 end
      for i = 1, 4 do
        e[i]:SetColorTexture(er, eg, eb, edgeA)
        e[i]:Show()
      end
      if hiA and not ew then e[1]:SetColorTexture(1, 1, 1, hiA) end
    elseif tickW then
      -- The auto row's release tick on the right edge (or the move-in's leave
      -- mark on the left): one edge, sized by style. A notch is short.
      for i = 1, 4 do e[i]:Hide() end
      local t = isMove and e[3] or e[4]
      t:ClearAllPoints()
      if STYLE.tick == "notch" and isAuto then
        t:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        t:SetSize(tickW, math.floor(barH / 2))
      elseif isMove then
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        t:SetSize(tickW, barH)
      else
        t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        t:SetSize(tickW, barH)
      end
      t:SetColorTexture(r, g, b, isMove and 0.9 or 0.85)
      t:Show()
    else
      for i = 1, 4 do e[i]:Hide() end
    end
    -- The wind-up column below the auto row (style `scope`).
    local col = f.column
    if col then
      if colH and colH > 0 then
        col:SetHeight(colH)
        col:SetColorTexture(r, g, b, fillA * 0.6)
        col:Show()
      else
        col:Hide()
      end
    end
    f.r, f.g, f.b, f.fillA, f.edgeA = r, g, b, fillA, edgeA
    f.hiA, f.ew, f.tickW, f.colH, f.ramp = hiA, ew, tickW, colH, ramp
  end

  -- The auto row keeps its icon whatever the bar's width: on a fast bow the
  -- wind-up is under ICON_MIN px and every auto lost its picture (2:5 at a
  -- 1.0 s cycle, 2026-08-26). A slight overhang beats a missing identity.
  local tex = ((w >= ICON_MIN or it.row == "auto") and it.sym) and Nock.UI.PracticeIconFor(it.sym) or nil
  local off = tex and (BAR_H + 1) or 2
  local label = self:LabelFor(it)
  if shape or label ~= f.labelText or tex ~= f.tex then
    -- The word, measured against the room the icon leaves it. The icon keeps
    -- its room; NEXT shortens to fit beside it (NEXT_SHORT) before it is dropped.
    local fs = f.label
    if label then
      local textW = w - off - 1
      fs:SetWidth(0)
      fs:SetText(label)
      local strW = fs:GetStringWidth() or 0
      if strW > textW and label == NEXT_LABEL then
        for i = 2, #NEXT_SHORT do
          fs:SetText(NEXT_SHORT[i])
          strW = fs:GetStringWidth() or 0
          if strW <= textW then break end
        end
      end
      if strW <= textW then
        fs:SetWidth(textW)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", f, "TOPLEFT", off, -barH / 2)
        fs:Show()
      else
        fs:Hide()
      end
    else
      fs:Hide()
    end
    if tex then
      f.icon:SetTexture(tex)
      f.icon:Show()
    else
      f.icon:Hide()
    end
    f.labelText, f.tex = label, tex
  end
  local desat = (it.oncd or DESATURATED[it.sym]) and true or false
  if tex and desat ~= f.desat then
    f.icon:SetDesaturated(desat)
    f.desat = desat
  end

  -- Where it was being drawn a moment ago, against where it belongs now. A key
  -- the last rebuild did not have is a genuinely new item and fades in; one it
  -- did have glides the difference, which with the forecast anchored on the next
  -- release is usually zero and costs nothing at all.
  --
  -- ...and how bright it settles: full, or ONCD_ALPHA for a note that cannot be
  -- pressed when it arrives. The fade-in runs to that target rather than to 1,
  -- so a dimmed note never flashes bright on the rebuild it appears in.
  -- ...or PAST_ALPHA for a played item behind the hit line (style `past` =
  -- fade), or DIM_ALPHA for every pending note that is not the next one (style
  -- `next` = both/bright): the one you press next is the one thing at full
  -- brightness. The fade-in runs to that target rather than to 1, so a dimmed
  -- note never flashes bright on the rebuild it appears in.
  local aTo = 1
  if it.oncd then aTo = ONCD_ALPHA
  elseif played and STYLE.past == "fade" then aTo = PAST_ALPHA
  elseif isNote and not isNext and not played and key >= TL.KEY.PAPER
         and (STYLE.next == "both" or STYLE.next == "bright") then aTo = DIM_ALPHA end
  local d = 0
  if known then
    -- Where it is being drawn RIGHT NOW (mid-glide included: Ease keeps
    -- drawnT0 current), against where it belongs. An interrupted glide resumes
    -- from where it is; a jump past EASE_MAX is a re-plan and snaps.
    local drawn = f.drawnT0 or f.trueT0 or it.t0
    if not noEase(key) then
      d = drawn - it.t0
      if d > EASE_MAX or d < -EASE_MAX then d = 0 end
    end
    local cur = f:GetAlpha()
    local refade = false
    if f.fading then
      -- A fade already running towards this brightness carries on; one
      -- running towards another (a frame on its way OUT that is wanted again,
      -- a note whose playability flipped) restarts from where it is.
      refade = (f.aTo ~= aTo)
    elseif cur ~= aTo then
      refade = true
    end
    if refade then f.aFrom, f.fading, f.tStart = cur, true, now end
  else
    f.aFrom, f.fading, f.tStart = 0, true, now
    f:SetAlpha(0)
  end
  local moved = (d ~= 0) or (f.trueT0 ~= it.t0) or (f.y ~= y) or (f.seatT0 ~= self._t0)
  f.trueT0, f.y, f.aTo = it.t0, y, aTo
  f.dFrom = d
  if d ~= 0 then f.tStart = now end
  f.easing = (d ~= 0)
  f.drawnT0 = it.t0 + d
  if moved then
    f:SetPoint("TOPLEFT", self.content, "TOPLEFT", (it.t0 + d - self._t0) * pps, y)
    f.seatT0 = self._t0
  end
  if not f.shown then f:Show(); f.shown = true end
  if isNext and isNote then self._nextFrame, self._nextIt = f, it end
end

function View:Paint(out, now)
  local pools = self.pools
  local serial = (self._serial or 0) + 1
  self._serial = serial
  pools.item.n = 0
  poolReset(pools.mark)

  -- CLAIM BEFORE PAINTING. Frames are handed out in item order, and a frame is
  -- free when the rebuild claiming frames has not claimed it -- so without this
  -- pass a NEW key painted early in the list (a played cast is drawn before the
  -- grid) took the first idle-looking frame in the pool, which was an auto's or
  -- a note's the strip still held: that item then fell off its frame and faded
  -- in again on a new one every time something was played. Stamp every frame
  -- whose key this rebuild holds first; only the rest are free.
  local byKey = pools.item.byKey
  if byKey then
    for i = 1, out.nItems or 0 do
      local k = out.items[i].key
      local f = k and byKey[k]
      if f then f.seen = serial end
    end
  end
  self._nextFrame, self._nextIt = nil, nil
  for i = 1, out.nItems or 0 do self:PaintItem(out.items[i], now, serial) end
  self:PaintChip(now)

  -- A frame whose key the strip no longer holds fades out where it stands;
  -- one whose fade finished is released (its key is free again).
  local pool = pools.item
  for i = 1, pool.max do
    local f = pool[i]
    if f.key and f.seen ~= serial then
      if f.fading and f.aTo == 0 and now - (f.tStart or now) >= EASE_SEC then
        if pool.byKey then pool.byKey[f.key] = nil end
        f.key, f.fading, f.easing = nil, false, false
        f.drawnT0, f.trueT0 = nil, nil
        if f.shown then f:Hide(); f.shown = false end
      elseif not (f.fading and f.aTo == 0) then
        f.aFrom, f.aTo, f.fading, f.easing, f.dFrom, f.tStart = f:GetAlpha(), 0, true, false, 0, now
      end
    end
  end

  local pps, t0, content, laneH = self._pps, self._t0, self.content, self._laneH
  for i = 1, out.nMarks or 0 do
    local mk = out.marks[i]
    local lane = self._rowIndex[mk.row] or 1
    local col = TL.COLORS[mk.severity or "warn"] or TL.COLORS.warn
    local b = poolMark(pools.mark, content)
    b:SetPoint("TOPLEFT", content, "TOPLEFT",
      (mk.t - t0) * pps - MARK_HIT / 2, -((lane - 1) * laneH))
    b.tex:SetVertexColor(col[1], col[2], col[3], 1)
    b.mark = mk
  end

  poolHideRest(pools.mark)
  -- Pops last: they read the item frames this pass just seated, to find the
  -- note each judgment belongs to.
  self:PaintPops(out)
end

----------------------------------------------------------------------------
-- Judgment pops. One word per graded paper note, riding the note it judges and
-- rising off it as it fades. The data is T.Strip's `out.pops`; the animation is
-- the central tick's, over exactly T.POP_LIFE so the two cannot drift.
----------------------------------------------------------------------------

-- The colour a grade wears. GOOD is the only one that is not a straight
-- severity colour: PERFECT and GOOD are both `good` in T.JUDGE_SEV, and two
-- identical greens would say the same thing twice.
local function judgeColor(grade, sev)
  if grade == "GOOD" then return GOOD_LIGHT end
  return TL.COLORS[sev or "warn"] or TL.COLORS.warn
end

-- Where the note this judgment belongs to is being DRAWN, so the pop sits on
-- it rather than at the moment the paper wanted it. A linear scan of the item
-- pool: there are a handful of live pops against a few dozen items, and it runs
-- once per rebuild, never per tick.
function View:PopAnchor(key)
  if not key then return nil end
  local byKey = self.pools.item.byKey
  local f = byKey and byKey[key]
  if f and f.seen == self._serial then return f.trueT0 end
  return nil
end

-- One pooled FontString per live pop, keyed by the pop's own note key. Text and
-- colour are written only when the slot's contents actually change; the seat
-- and the alpha are EasePops', which Refresh runs on every tick INCLUDING the
-- one that rebuilt -- so this never places anything itself.
function View:PaintPops(out)
  local pools = self.pools
  poolReset(pools.pop)
  for i = 1, out.popsN or 0 do
    local p = out.pops[i]
    local fs = poolFontString(pools.pop, self.overlay, POP_SIZE)
    if fs.popText ~= p.text then
      fs.popText = p.text
      fs:SetText(p.text)
    end
    if fs.popGrade ~= p.grade then
      fs.popGrade = p.grade
      local col = judgeColor(p.grade, p.sev)
      fs:SetTextColor(col[1], col[2], col[3], 1)
    end
    fs.popT = p.t
    -- The note's frame if it is still on screen, else the moment the paper
    -- wanted the note, else the press itself (an OFF has no note at all).
    fs.popAt = self:PopAnchor(p.key) or p.t0 or p.t
    local lane = self._rowIndex[TL.ROW_OF_SYM[p.sym or ""] or "auto"] or 1
    fs.popLane = lane
    -- The pool hands slots back in whatever size they last wore, so the size is
    -- diffed like the text and the colour are: only a slot that has changed
    -- lanes since its last use pays for a SetFont.
    local size = (lane == 1) and POP_SIZE or POP_SIZE_LOW
    if fs.popSize ~= size then
      fs.popSize = size
      fs:SetFont(Nock.UI.GetFont(), size, "OUTLINE")
    end
  end
  poolHideRest(pools.pop)
end

-- Rise and fade, from the central tick. `at` is the clock the strip is drawn
-- against (frozen pre-pull), so a pop scrolls left with its note; `now` is the
-- real one, because the animation is an animation.
function View:EasePops(now, at)
  local pool = self.pools.pop
  local n = pool.n
  if n == 0 then return end
  local life = TL.POP_LIFE
  local pps, hitX, laneW = self._pps, self._hitX, self._laneW
  local overlay, laneH, markRow = self.overlay, self._laneH, self._markRow
  for i = 1, n do
    local fs = pool[i]
    local age = now - (fs.popT or now)
    local p = age / life
    if p < 0 then p = 0 end
    -- The pops hang off the OVERLAY, which is what lets them rise clear of the
    -- lanes -- and the overlay does not clip, so a pop whose note has scrolled
    -- out of the window has to take itself off screen. Both edges: the word is
    -- drawn to the RIGHT of its seat, so a seat within a few pixels of the
    -- right edge spills out of the strip just as surely as one off the left.
    local x = hitX + (fs.popAt - at) * pps
    if p >= 1 or x < -8 or x > laneW - 8 then
      if fs:IsShown() then fs:Hide() end
    else
      local a = 1
      if p > POP_HOLD then a = (1 - p) / (1 - POP_HOLD) end
      fs:SetAlpha(a)
      fs:ClearAllPoints()
      fs:SetPoint("BOTTOMLEFT", overlay, "TOPLEFT", x + 3,
        -((fs.popLane - 1) * laneH) - markRow + p * POP_RISE)
      if not fs:IsShown() then fs:Show() end
    end
  end
end

----------------------------------------------------------------------------
-- The coach line. One sentence, replaced only when the judgment behind it
-- changes -- so the common tick sets no text and formats no string.
----------------------------------------------------------------------------

function View:SetCoach(text)
  if text == self._coachText then return end
  self._coachText = text
  if self.coachLine then self.coachLine:SetText(text) end
end

-- The row's tint, in T.JUDGE_SEV's vocabulary ("good"/"warn"/"bad", or nil for
-- no judgment at all). Change-gated the same way the sentence is: the tick that
-- does not change the advice does not touch the texture either.
function View:SetWash(sev)
  if sev == self._washSev then return end
  self._washSev = sev
  local bg = self.coachBg
  if not bg then return end
  local c = sev and COACH_WASH[sev]
  if c then bg:SetColorTexture(c[1], c[2], c[3], c[4])
  else bg:SetColorTexture(1, 1, 1, 0) end
end

-- The deadline the CLIP sentence quotes: the last moment a Steady may START and
-- still finish before the next wind-up begins, measured from the release that
-- opens the cycle. One cycle, less the wind-up, less the cast itself.
function View:CastDeadline(live)
  local cycle, windup = live.cycle, live.windup
  if not (cycle and windup and cycle > 0) then return nil end
  local M = Nock.PracticeModel
  if not (M and M.CastTime) then return nil end
  local p = practice()
  local cfg = p and p.cfg
  local cast = M.CastTime(1.5, live.rangedMul or (cfg and cfg.baseRangedMul) or 1,
                          cfg and cfg.castCorr)
  local dl = cycle - windup - cast
  if dl <= 0 then return nil end
  return dl
end

-- "On the beat", with the weave tail when the paper's next note is a weave.
-- Built once: it names a spell, and a spell name is localised.
local function beatWeaveLine()
  if coachBeatWeave then return coachBeatWeave end
  local name = Nock.UI.PracticeNameFor("s")
  coachBeatWeave = name and ("On the beat. Weave gap opens after this " .. name .. ".")
                        or "On the beat. Weave gap opens after this cast."
  return coachBeatWeave
end

-- The sentence for ONE judgment. Called only when the latest pop changes, so
-- the formats here are per judgment, never per tick.
function View:CoachFor(p, live)
  local grade, sym = p.grade, p.sym
  if grade == "CLIP" then
    local name = Nock.UI.PracticeNameFor(sym) or "that cast"
    local ms = math.floor((p.deltaMs or 0) + 0.5)
    local dl = self:CastDeadline(live)
    if dl then
      return ("That %s ran %d ms into the wind-up - press it before %.1f s next cycle.")
             :format(name, ms, dl)
    end
    return ("That %s ran %d ms into the wind-up."):format(name, ms)
  end
  if grade == "MISSED" then
    if sym == "w" or sym == "r" then return COACH_WEAVE_MISS end
    local name = Nock.UI.PracticeNameFor(sym)
    if not name then return COACH_MISS_ANY end
    return ("Missed the %s - it was due at the beat."):format(name)
  end
  if grade == "LATE" then return COACH_LATE end
  if grade == "OFF" then
    local name = Nock.UI.PracticeNameFor(sym)
    if not name then return COACH_OFF_ANY end
    return ("That %s is not on the paper here."):format(name)
  end
  if self._weaveNext then
    -- ...and when the window that weave would go in cannot hold one, say THAT
    -- instead of pointing at a gap the player cannot make.
    if self._weaveTight then return COACH_WEAVE_TIGHT end
    return beatWeaveLine()
  end
  return COACH_BEAT
end

-- The line's whole gate: a fight that has not started, one that has not been
-- pulled, and otherwise the newest pop -- identified by the moment it was
-- graded, which is unique per judgment. A judgment that has aged off the stage
-- leaves its sentence standing: the advice outlives the word.
-- The ARMED line: the pull, and what the paper costs by design when it does
-- (Practice:Lookahead publishes the fight's tag as live.paperNote) -- on the
-- amber wash, with the note's icon before the words.
local function pullLine(live)
  local tag = live and live.paperNote
  if tag == "no weave key" then return COACH_PULL_NOKEY end
  if tag then return COACH_PULL_NOTE:format(tag) end
  return COACH_PULL
end

function View:SetCoachNote(tag)
  local ico = self.coachIco
  if not ico then return end
  if tag == self._coachNote then return end
  self._coachNote = tag
  if tag then
    Skin.Icon(ico, Skin.NOTE_ICON[tag] or "warn", "wait")
    Skin.IconSize(ico)
    ico:Show()
    self.coachLine:ClearAllPoints()
    self.coachLine:SetPoint("LEFT", ico, "RIGHT", 8, 0)
  else
    ico:Hide()
    self.coachLine:ClearAllPoints()
    self.coachLine:SetPoint("LEFT", self.coachKey, "RIGHT", self._coachLineX or 10, 0)
  end
  local metW = MET_DOTS * MET_DOT + (MET_DOTS - 1) * MET_GAP
  self.coachLine:SetPoint("RIGHT", self.coach, "RIGHT", -(metW + 14 + PAD), 0)
end

function View:Coach(live, frozen)
  if not (frozen or (live and live.plan and live.plan.reason == "pull")) then self:SetCoachNote(nil) end
  if not live then
    self._coachT = nil
    self:SetWash(nil)
    return self:SetCoach(COACH_IDLE)
  end
  if frozen or (live.plan and live.plan.reason == "pull") then
    self._coachT = nil
    self:SetWash(nil)
    self:SetCoachNote(live and live.paperNote or nil)
    if live and live.paperNote then self:SetWash("warn") end
    return self:SetCoach(pullLine(live))
  end
  -- The NEWEST pop by its own clock, not the last one in the list: the list is
  -- only approximately time-ordered (a MISSED is stamped at its cycle's end and
  -- pushed a cycle later), and the sentence has to be the latest ADVICE. One
  -- pass over a handful of entries, no allocation.
  local out = self._out
  local p, best = nil, nil
  for i = 1, (out and out.popsN or 0) do
    local q = out.pops[i]
    local t = q.t
    if t and (best == nil or t > best) then p, best = q, t end
  end
  if p and p.t ~= self._coachT then
    self._coachT = p.t
    -- The wash is the SENTENCE's severity, not the stage's: it changes with the
    -- advice and outlives the pop that earned it, exactly like the line does.
    self:SetWash(p.sev)
    return self:SetCoach(self:CoachFor(p, live))
  end
  -- Armed, or pulled but not yet judged: the opener is the only advice there is.
  if self._coachT == nil then
    self:SetWash(nil)
    self:SetCoachNote(live and live.paperNote or nil)
    if live and live.paperNote then self:SetWash("warn") end
    return self:SetCoach(pullLine(live))
  end
end

----------------------------------------------------------------------------
-- The metronome: four dots, the beat on dot 1 and the weave gap on dot 3.
----------------------------------------------------------------------------

local function metSound(which)
  local e = MET_SOUND[which]
  if not (e and PlaySound) then return end
  local kit = SOUNDKIT and SOUNDKIT[e[1]] or e[2]
  if not kit then return end
  pcall(PlaySound, kit, "Master")
end

function View:Flash(i, col, sound, now)
  local t = self.met and self.met[i]
  if not t then return end
  self._metAt[i], self._metCol[i] = now, col
  t:SetColorTexture(col[1], col[2], col[3], 1)
  if sound then metSound(sound) end
end

-- The decay, from the tick. At most two dots are ever lit, and only for
-- MET_FLASH, so this loop does nothing at all most of the time.
function View:EaseMet(now)
  local at, met = self._metAt, self.met
  if not (at and met) then return end
  for i = 1, MET_DOTS do
    local t0 = at[i]
    if t0 > 0 then
      local p = (now - t0) / MET_FLASH
      if p >= 1 then
        at[i] = 0
        met[i]:SetColorTexture(MET_OFF[1], MET_OFF[2], MET_OFF[3], 1)
      else
        local c = self._metCol[i] or MET_OFF
        met[i]:SetColorTexture(c[1] + (MET_OFF[1] - c[1]) * p,
                               c[2] + (MET_OFF[2] - c[2]) * p,
                               c[3] + (MET_OFF[3] - c[3]) * p, 1)
      end
    end
  end
end

-- The two beats, as edges on what Lookahead already publishes.
--
--   the beat   `lastShotAt` MOVING. That is the measured release the whole
--              strip is anchored to -- not a prediction that can slip, and not
--              `nextShotAt` passing `now`, which fires again every time the
--              forecast is re-seated across the cursor.
--   the gap    `oppOpen` going true. The engine's own flag, and the honest
--              one: it is `no cast running AND the melee swing is up AND there
--              is room to walk in and back out` (PracticeEngine), which is
--              what "the weave gap opens" means. The meleeReadyAt/ttw pair is
--              the fallback for a snapshot that carries no flag, and it is
--              only the first two thirds of that test.
--
-- Both prime silently: the first observation of a fight sets the edge without
-- flashing, so a stale release from the previous fight cannot open this one.
function View:Metronome(live, now, frozen)
  local on = (not frozen) and profile("practiceMetronome", true) and true or false
  local shot = live.lastShotAt
  if shot and shot > 0 and shot ~= self._metShot then
    if on and self._metShot ~= nil then self:Flash(1, MET_TICK, "tick", now) end
    self._metShot = shot
  end
  -- The gap tick is a WEAVE nag, so the paper decides whether it exists at all
  -- (Practice:Lookahead publishes the window's symbol set): on a 1:1 drill the
  -- engine still opens the window — the swing is real — and the dot stays dark.
  -- The edge is tracked either way, so a notation that gains a `w` mid-fight
  -- starts ticking on the NEXT opening rather than on the one already open.
  local ps = live.paperSyms
  local gapOn = on and ps ~= nil and (ps.w or ps.r) and true or false
  -- The gap tick fires on the band's own window opening (R5c), not on the
  -- engine's `oppOpen` flag: that flag is the FAULT gate ("may I go right now"),
  -- and it is sized by the player's measured footwork — one slow weave can put
  -- that past every gap the rotation has, after which the flag never goes true
  -- again and the dot went dark for the rest of the fight while the paper kept
  -- asking for weaves. `weaveAt` is the engine's answer to when a weave is next
  -- possible; the flag, and then the meleeReadyAt/ttw pair, are the fallbacks
  -- for a snapshot that carries no window.
  local open = live.weaveAt
  if open ~= nil then
    open = open <= live.now + 1e-6
  else
    open = live.oppOpen
    if open == nil then
      open = (live.meleeReadyAt ~= nil and live.meleeReadyAt <= live.now
              and (live.ttw or 0) > 0)
    end
  end
  open = open and true or false
  if open ~= self._metGap then
    if gapOn and open and self._metGap ~= nil then self:Flash(3, MET_WEAVE, "gap", now) end
    self._metGap = open
  end
end

----------------------------------------------------------------------------
-- The press flash: instant, wordless feedback at the moment the key goes down.
----------------------------------------------------------------------------

-- The note this press was reaching for: the one whose start is nearest the hit
-- line on the given lane. Everything eligible here is AHEAD of the cursor --
-- T.Strip only keys future items, and a paper note is dropped from the
-- projection the moment it is behind `now` -- so in practice this picks the
-- soonest one, and the distance test only decides between two that are both
-- ahead.
--
-- Only paper notes (key >= T.KEY.PAPER) are eligible -- they are the plan's
-- notes, and since v3 P1 there is no engine bar standing in for one. Nothing
-- else is a note you press: not the grid's autos, not the weave band, not a
-- proc span.
--
-- One pass over the strip that is already built, once per press.
function View:NoteNear(weave, at)
  local out = self._out
  if not out then return nil end
  local best, bestD
  for i = 1, out.nItems or 0 do
    local it = out.items[i]
    local key = it.key
    -- ...and never a note on cooldown: the press that just went out cannot have
    -- been that one, so brightening it would answer the wrong note (R8a).
    local row = it.row
    local onRow = weave and (row == "w") or (not weave and (row == "s" or row == "m" or row == "A"))
    if key and key >= TL.KEY.PAPER and key < TL.KEY.PLAYED and onRow and not it.oncd then
      local d = it.t0 - at
      if d < 0 then d = -d end
      if bestD == nil or d < bestD then best, bestD = key, d end
    end
  end
  return best
end

-- Two counters, one edge each. `nPress` counts every input; `nWeave` counts the
-- weave key's own edges and bumps `nPress` with them, so `nPress` moving FURTHER
-- than `nWeave` is an ability press and the difference is a weave edge. Both
-- prime silently, exactly as the metronome's do: the first observation of a
-- fight only records where the counters stand.
function View:PressEdge(p, now, at)
  local e = p and p.engine
  if not e then return end
  local nP, nW = e.nPress or 0, e.nWeave or 0
  local lP, lW = self._lastPress, self._lastWeave
  self._lastPress, self._lastWeave = nP, nW
  if lP == nil then return end
  local dP, dW = nP - lP, nW - lW
  if dP <= 0 then return end
  -- An ability press wins the flash over a weave edge landing in the same tick:
  -- the SHOTS lane is where the note it was aimed at lives, and two flashes at
  -- once would only say "something happened" twice.
  local key = self:NoteNear(dP <= dW, at)
  if not key then return end
  self._flashKey, self._flashAt = key, now
end

-- The decay, from the central tick. Costs a nil test while nothing is flashing;
-- one pass over the item pool for the quarter second after a press, which is the
-- only way to find the frame a key is sitting on after the strip has moved.
function View:EaseFlash(now)
  local key = self._flashKey
  if key == nil then return end
  local p = (now - (self._flashAt or now)) / FLASH_LIFE
  if p < 0 then p = 0 end
  local done = (p >= 1)
  local a = done and 0 or (FLASH_ALPHA * (1 - p))
  local pool = self.pools.item
  for i = 1, pool.max do
    local f = pool[i]
    local fl = f.flash
    if fl then
      if not done and f.key == key and f:IsShown() then
        fl:SetAlpha(a)
        if not f.flashOn then f.flashOn = true; fl:Show() end
      elseif f.flashOn then
        f.flashOn = false
        fl:Hide()
      end
    end
  end
  if done then self._flashKey = nil end
end

-- Release every frame from its key and hide it: between fights (Blank). The
-- next rebuild treats every item as new and fades it in. Never at the pull any
-- more (v3 P2): the armed strip already holds the drill's paper under the same
-- keys the fight will seat, so the first press moves items, it does not
-- re-create them.
function View:DropGlide()
  local pool = self.pools and self.pools.item
  if not pool then return end
  for i = 1, pool.max do
    local f = pool[i]
    f.key, f.easing, f.fading, f.drawnT0, f.trueT0, f.seatT0 = nil, false, false, nil, nil, nil
    f.labelText, f.tex, f.w, f.barH, f.fillA, f.edgeA, f.r, f.g, f.b, f.desat = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    f.hiA, f.ew, f.tickW, f.colH, f.ramp = nil, nil, nil, nil, nil
    if f.shown then f:Hide(); f.shown = false end
  end
  local byKey = pool.byKey
  if byKey then for k in pairs(byKey) do byKey[k] = nil end end
  self._t0 = 0
  self._nextFrame = nil
  if self.chip then self.chip:Hide(); self._chipFrame, self._chipText = nil, nil end
end

function View:Blank()
  local pools = self.pools
  poolReset(pools.mark); poolReset(pools.pop)
  poolHideRest(pools.mark); poolHideRest(pools.pop)
  self:DropGlide()
  pools.item.n = 0
  self._lastN, self._lastV, self._lastProcSig = nil, nil, nil
  self._lastRev = nil
  self._builtAt = 0
  -- The stage's own three: the pops are gone with the pool above, the coach
  -- line goes back to its state sentence and the metronome forgets both edges
  -- so the next fight primes them again instead of flashing on its first tick.
  self._coachT, self._weaveNext, self._weaveTight = nil, false, false
  self:SetCoach(COACH_IDLE)
  self:SetWash(nil)
  self._metShot, self._metGap = nil, nil
  -- The press flash goes home with them: a new fight is a new engine with its
  -- counters back at zero, and a delta taken across that boundary is negative.
  -- nil re-primes the edge, so the first press of the next fight only records.
  self._lastPress, self._lastWeave, self._flashKey = nil, nil, nil
  local ipool = pools.item
  for i = 1, ipool.max do
    local f = ipool[i]
    if f.flashOn then f.flashOn = false; f.flash:Hide() end
  end
  local at, met = self._metAt, self.met
  if at and met then
    for i = 1, MET_DOTS do
      at[i] = 0
      met[i]:SetColorTexture(MET_OFF[1], MET_OFF[2], MET_OFF[3], 1)
    end
  end
  -- The pop cursor goes home with the scan cursor below: a new fight is a new
  -- verdict table, and a cursor left past its end pops nothing at all.
  local o = self._out
  if o then o._popFrom, o._popsV, o._popN, o.popsN = 1, nil, 0, 0 end
  -- Blank() is what runs BETWEEN fights, so it is also where T.Strip's scan
  -- cursor goes home: the next fight hands it a brand-new (shorter) event
  -- table while GetTime() keeps climbing, and a cursor left pointing past
  -- that table's end would blank the past lane for the whole fight.
  local out = self._out
  if out then out._scanFrom, out._lastNow, out._lastN = 1, nil, 0 end
end

----------------------------------------------------------------------------
-- Tick
----------------------------------------------------------------------------

-- Everything that would make the drawn window WRONG rather than merely older:
-- a new event, a new verdict, a proc coming up or dropping, the rotation's next
-- press moving, and the drift floors.
function View:NeedsRebuild(live, now)
  local p = practice()
  local e = p and p.engine
  local n = (e and e.n) or 0
  local g = p and p.grader
  local nv = (g and g.verdicts and #g.verdicts) or 0
  local sig = 0
  local procs = live.procs
  if procs then
    for i = 1, #PROC_NAMES do
      local t = procs[PROC_NAMES[i]]
      if t then sig = sig + t end
    end
  end
  -- The plan's revision moves on an event (press, release, verdict, haste,
  -- notation, a NEXT change) and never on the clock, so it is the one signal
  -- for "the advice changed" (Core/PracticePlan.lua). The slow floor only
  -- lets items enter at the far edge.
  local plan = live.plan
  local rev = plan and plan.rev or 0
  local age = now - (self._builtAt or 0)
  -- A replay scrub is a new moment: the stream up to it and the frame it
  -- draws from both change with it.
  local rp = p and p._replay
  local rrev = rp and rp.rev or 0
  if rrev ~= self._lastReplayRev then self._lastReplayRev = rrev; age = REBUILD_SEC end
  if n ~= self._lastN or nv ~= self._lastV or sig ~= self._lastProcSig
     or rev ~= self._lastRev or age >= REBUILD_SEC then
    self._lastN, self._lastV, self._lastProcSig, self._lastRev = n, nv, sig, rev
    return true
  end
  return false
end

-- Is the plan's NEXT note a weave? For the coach line's "On the beat." tail --
-- read once per rebuild off the plan, never by walking the strip.
function View:ResolveWeaveNext()
  local plan = self._live and self._live.plan
  local i = plan and plan.nextIdx
  self._weaveNext = (i ~= nil and plan.notes[i].row == "w") or false
end

-- Is the window that weave would go in too small to hold one? The plan's own
-- word for it (Core/PracticePlan.lua `reason`).
function View:ResolveWeaveTight(live)
  local plan = live.plan
  self._weaveTight = (plan and plan.reason == "tight") or false
end

-- The row list for this rebuild: the plan's, plus `cd` when the strip holds a
-- cooldown/proc item the plan did not list. Returns true when it changed --
-- the caller then re-measures the stage (the row height is avail / rows).
local wantRows = {}
function View:SetRows(list, n)
  local rows = self._rows
  local same = (n == self._nRows)
  if same then
    for i = 1, n do if rows[i] ~= list[i] then same = false; break end end
  end
  if same then return false end
  local index = self._rowIndex
  for k in pairs(index) do index[k] = nil end
  for i = 1, n do rows[i] = list[i]; index[list[i]] = i end
  for i = n + 1, #rows do rows[i] = nil end
  self._nRows = n
  return true
end

-- SetRows, then re-measure the stage when the list changed (the row height is
-- avail / rows) and re-dock when its height moved.
function View:ApplyRows(list, n)
  if not self:SetRows(list, n) then return end
  local hostH = self._hostH
  self:Measure()
  self:Layout()
  if self._hostH ~= hostH then
    self.frame:SetHeight(self._hostH)
    Nock:SendMessage("NOCK_PRACTICE_DOCK_CHANGED")
  end
end

-- No fight: the rows of the PICKED scenario, so the stage says what a drill
-- asks for before Start (Practice:IdleRows), keys included.
function View:IdleRows()
  local p = practice()
  if not (p and p.IdleRows) then return end
  local n = p:IdleRows(wantRows)
  if n > 0 then self:ApplyRows(wantRows, n) end
  self:PaintRowLabels()
end

-- Anchor the row labels down the gutter at the current row height; hide the
-- rest. Called from Layout and after a row change.
function View:LayoutRows()
  local laneH, markRow = self._laneH, self._markRow
  local labels = self.rowLabels
  if not labels then return end
  self.gutter:SetSize(LABEL_W, self._stripH)
  local bg, lanes = self.laneBg, STYLE.lanes
  local rowW = LABEL_W + (self._laneW or MIN_LANE_W)
  local padX = self._padX or PAD
  for i = 1, MAX_ROWS do
    local rf = labels[i]
    if i <= (self._nRows or 0) then
      rf:ClearAllPoints()
      rf:SetPoint("TOPLEFT", self.gutter, "TOPLEFT", 0, -((i - 1) * laneH) - markRow + 2 + (LABEL_H - BAR_H - 4) / 2)
      rf:Show()
      -- The lane furniture, across gutter and lanes. Zebra tints every second
      -- row; lines draws a hairline under each; none hides the lot.
      local t = bg and bg[i]
      if t then
        if lanes == "zebra" and i % 2 == 0 then
          t:ClearAllPoints()
          t:SetSize(rowW, laneH)
          t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", padX, -self._lanesTop - (i - 1) * laneH)
          t:SetColorTexture(1, 1, 1, ZEBRA_A)
          t:Show()
        elseif lanes == "lines" then
          t:ClearAllPoints()
          t:SetSize(rowW, 1)
          t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", padX, -self._lanesTop - i * laneH + 1)
          t:SetColorTexture(1, 1, 1, LANE_LINE_A)
          t:Show()
        else
          t:Hide()
        end
      end
    else
      rf:Hide()
      if bg and bg[i] then bg[i]:Hide() end
    end
  end
end

-- Icon, name and key per row -- change-gated per FontString.
function View:PaintRowLabels()
  local labels = self.rowLabels
  if not labels then return end
  local p = practice()
  for i = 1, (self._nRows or 0) do
    local row = self._rows[i]
    local rf = labels[i]
    if rf.row ~= row then
      rf.row = row
      rf.icon:SetTexture(Nock.UI.PracticeIconFor(ROW_ICON[row]))
      rf.name:SetText(ROW_NAME[row] or row)
    end
    local key = (p and p.RowKey) and p:RowKey(row) or nil
    local text = key or (ROW_NEEDS_KEY[row] and NO_KEY) or ""
    if rf.keyText ~= text then
      rf.keyText = text
      rf.key:SetText(text)
      if key then Skin.Text(rf.key, "ink3") else Skin.Text(rf.key, "bad") end
    end
  end
end

function View:Rebuild(live, now, at)
  local p = practice()
  local events, n, verdicts = p:ConveyorData()
  local opts = self._opts
  opts.past, opts.future = self._past, self._future
  opts.windup = live.windup or 0
  opts.verdicts = verdicts or EMPTY
  opts.okMarks = profile("practiceTimelineOkMarks", false) and true or false
  local out = TL.Strip(events or EMPTY, n or 0, live, opts, self._out)
  -- The rows this rebuild draws: the plan's, plus `cd` when the strip holds a
  -- cooldown/proc item the plan did not list (a cooldown pressed by hand).
  local plan = live.plan
  local nRows = 0
  if plan and plan.live and plan.nRows > 0 then
    for i = 1, plan.nRows do nRows = nRows + 1; wantRows[nRows] = plan.rows[i] end
  else
    for i = 1, #DEFAULT_ROWS do nRows = nRows + 1; wantRows[nRows] = DEFAULT_ROWS[i] end
  end
  local hasCd = false
  for i = 1, nRows do if wantRows[i] == "cd" then hasCd = true end end
  if not hasCd then
    for i = 1, out.nItems or 0 do
      if out.items[i].row == "cd" then nRows = nRows + 1; wantRows[nRows] = "cd"; break end
    end
  end
  if nRows > MAX_ROWS then nRows = MAX_ROWS end
  self:ApplyRows(wantRows, nRows)
  self:PaintRowLabels()
  -- The content's own origin: fixed for the fight (DropGlide zeroes it), so a
  -- frame's seat is an absolute position and a rebuild that moves nothing
  -- touches no SetPoint. The scroll is the content frame's, per tick.
  if not self._t0 or self._t0 == 0 then self._t0 = live.now end
  self._builtAt = live.now
  self:ResolveWeaveNext()
  self:ResolveWeaveTight(live)
  self:Paint(out, now)
  local p = practice()
  if p and p._planTrace then self:TraceStrip(out, live) end
end

-- The diagnostic twin of Practice:TracePlan: what this rebuild put on the
-- WEAVE lane, into the same change-driven ring (`/nock practice plandump`).
function View:TraceStrip(out, live)
  local p = practice()
  local t0 = Nock.state.sim.t0 or 0
  local parts = {}
  for i = 1, out.nItems or 0 do
    local it = out.items[i]
    if it.row == "w" then
      local kind = "played"
      if it.key then
        if it.key >= TL.KEY.PAPER then kind = "note"
        elseif it.key == TL.KEY.BAND then kind = "band"
        elseif it.key == TL.KEY.MOVE then kind = "move"
        else kind = "k" .. it.key end
      end
      parts[#parts + 1] = ("%s%s@%+.2f..%+.2f%s%s%s"):format(kind,
        it.sym and ("[" .. it.sym .. "]") or "", it.t0 - t0, it.t1 - t0,
        it.label and (" " .. it.label) or "", it.oncd and " DIM" or "", it.future and "" or " past")
    end
  end
  p:TraceLine("STRIP", ("n=%d | %s"):format(#parts, table.concat(parts, "  ")))
end

-- The residual glide, and the only per-item work on the tick path. Only items
-- whose seat actually moved (or that have just appeared) are touched, and only
-- for EASE_SEC: with the forecast anchored on the grid's next release most
-- rebuilds move nothing at all and this loop does nothing.
function View:Ease(now)
  local pool = self.pools.item
  local pps, t0, content = self._pps, self._t0, self.content
  for i = 1, pool.max do
    local f = pool[i]
    if f.key and (f.easing or f.fading) then
      local p = (now - (f.tStart or now)) / EASE_SEC
      if p < 0 then p = 0 end
      if p >= 1 then
        if f.easing then
          f.easing, f.dFrom, f.drawnT0 = false, 0, f.trueT0
          f:SetPoint("TOPLEFT", content, "TOPLEFT", (f.trueT0 - t0) * pps, f.y)
          f.seatT0 = t0
        end
        if f.fading then
          f.fading = false
          f:SetAlpha(f.aTo or 1)
          if f.aTo == 0 and f.shown then f:Hide(); f.shown = false end
        end
      else
        if f.easing then
          f.drawnT0 = f.trueT0 + f.dFrom * (1 - p)
          f:SetPoint("TOPLEFT", content, "TOPLEFT", (f.drawnT0 - t0) * pps, f.y)
        end
        if f.fading then
          local a0 = f.aFrom or 0
          f:SetAlpha(a0 + ((f.aTo or 1) - a0) * p)
        end
      end
    end
  end
end

-- The empty-state line. Change-gated: Refresh calls it on every tick, and a
-- Show/Hide on a FontString that is already in that state is not free.
function View:ShowEmpty(on)
  on = on and true or false
  if on == self._emptyOn then return end
  self._emptyOn = on
  if self.empty then
    if on then self.empty:Show() else self.empty:Hide() end
  end
end

function View:Refresh(state)
  local f = self.frame
  if not (f and TL) then return end
  if not state.sim.active then
    self:HideFrame()
    return
  end
  if not f:IsShown() then f:Show() end
  -- A width drag in progress: one step per tick, and nothing else this frame is
  -- cheaper than it. Gated on the flag, so the idle cost is a nil test.
  if self._sizeFrom then self:DragSize() end
  local now = GetTime()
  local p = practice()
  -- The replay transport moves the clock BEFORE the lookahead reads it: a
  -- drag on the track, or play running at 1x.
  if self.transport then self.transport:Tick(p, now) end
  local live = p and p:Lookahead(self._live)
  if not live then
    -- No fight: lanes, hit line and ticks stay, the conveyor itself is empty --
    -- and the empty state says what to do about it.
    if not self._blanked then
      self:Blank()
      self._blanked = true
    end
    self:ShowEmpty(true)
    self:IdleRows()
    self:EaseMet(now)
    self:PaintTransport(p, now)
    return
  end
  self._blanked = false
  self:ShowEmpty(false)
  -- (`weaveAt` / `weaveTtw` / `weaveFits` all arrive on `live` from
  -- Practice:Lookahead, off one E.Snapshot call. The view asked the engine for
  -- the third itself while Lookahead did not carry it, which meant two
  -- WeaveWindow calls at two moments and a strip holding one answer from each.)
  --
  -- Pre-pull hold: the clock is frozen at the pull for BOTH halves of the view
  -- (the rebuild's horizon and the scroll offset), so the strip stands still
  -- showing the casts the paper plans from here until the first press moves it.
  local frozen = prePullNow(p)
  if frozen then live.now = frozen end
  -- The pre-pull freeze lifting (or coming back) swaps the clock the whole view
  -- is drawn against, from the provisional t0 to the real one: every keyed item
  -- moves with it at a single rebuild. That is a re-plan, not a move -- a press
  -- made within EASE_MAX of Start glided the entire forecast across the strip --
  -- so the glide state goes home at the transition, in both directions.
  local at = frozen or now
  if self:NeedsRebuild(live, at) then self:Rebuild(live, now, at) end
  -- The one moving part of the whole view -- plus, for the 0.15 s after a
  -- rebuild that actually moved something, the items still gliding into place.
  -- The glide runs on the REAL clock even while the strip's own is frozen: it
  -- is an animation, not a position on the timeline.
  self.content:SetPoint("TOPLEFT", self.viewport, "TOPLEFT",
    self._hitX - (at - self._t0) * self._pps, 0)
  self:Ease(now)
  -- The stage's own three, all of them tick-driven and none of them allocating:
  -- the pops rise and fade, the coach line changes only when its judgment does,
  -- and the metronome fires on an edge and decays.
  self:EasePops(now, at)
  -- The press flash is picked AFTER the rebuild -- the press is already on the
  -- stream, so the strip this reads is the one that has it -- and eased with the
  -- rest. `at` is the strip's own clock (frozen pre-pull), because the note it
  -- looks for is a position on the timeline.
  self:PressEdge(p, now, at)
  self:EaseFlash(now)
  self:Metronome(live, now, frozen)
  self:EaseMet(now)
  self:Coach(live, frozen)
  self:PaintTransport(p, now)
end

----------------------------------------------------------------------------
-- The replay transport.
----------------------------------------------------------------------------

function View:PaintTransport(p, now)
  if self.transport then self.transport:Paint(p, now) end
end
