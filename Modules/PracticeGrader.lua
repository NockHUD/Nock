-- Modules/PracticeGrader.lua
-- Grades a practice fight from the engine's event stream into per-press verdicts and an end-of-fight scorecard.

local G = {}

local SYM = { steady = "s", multi = "m", arcane = "A" }

-- Which layout symbols are NOTES: the things you press between two autos. Same
-- set as PracticeTimeline's CYCLE_SYM and for the same reason — `g` is the
-- layout's own GCD bookkeeping and `a` is the cycle boundary itself.
local NOTE_SYM = { s = true, m = true, A = true, r = true, w = true }

-- Per-note state on a cycle record (nState[i]) and the grade it earned
-- (nGrade[i]). What the plan (Core/PracticePlan.lua) reads, so the stage never
-- has to join nUsed against the verdict list.
local PENDING, HIT, MISSED = "pending", "hit", "missed"
G.PENDING, G.HIT, G.MISSED = PENDING, HIT, MISSED

-- The judgment bands (plan 2026-08-23 "weave practice v2", Vocabulary).
-- |press - note| within PERFECT_SEC is PERFECT, within GOOD_SEC is GOOD, and
-- anything further off the slot in EITHER direction is LATE: the paper's order
-- is what a cycle is graded on, and a press that early only pushes the rest of
-- the cycle back.
local PERFECT_SEC, GOOD_SEC = 0.08, 0.25
local EPS = 1e-9

-- One counter per judgment, in the order the review reads them.
local JUDGE_FIELD = { PERFECT = "perfect", GOOD = "good", LATE = "late",
                      CLIP = "clip", MISSED = "missed", OFF = "off" }

-- Advice per fault code, for the end-of-fight analysis. A code that has no
-- entry here is not a fault (GOOD, WEAVE_OK) and never reaches the list.
-- Exported (G.ADVICE, below the table) so a test can assert the reverse
-- direction: every code that can reach an analysis row has a Summary family.
local ADVICE = {
  STEADY_WONT_FIT = "when the Steady does not fit before the wind-up, take the Multi or Arcane that does, and Steady after the shot",
  LATE = "press the next shot the moment the GCD frees — mash it",
  CLIP = "no cast may run past the wind-up moment",
  REARM = "release the weave key when the auto bar is full, not before",
  WEAVE_MISSED = "when the melee swing is ready and the auto is far enough away, go in",
  DEAD_ZONE = "step out before the wind-up wants to start",
  WEAVE_SLOW = "shorter legs: tap, do not walk",
  CATCHUP_MISSED = "a catch-up Multi beats a Steady that leaves a gap",
  EARLY = "hold cooldowns for the anchor",
}
G.ADVICE = ADVICE

-- Every SECOND an advice string names is an offset from the fight's origin, at
-- one decimal. The raw event clock is GetTime() — "the wind-up at 305232320.92
-- s" is what the review used to print, and even a sim-relative reading is the
-- wrong zero once the fight has one. A stream that carried no `pull` has no
-- origin at all, so it draws the em dash the rest of the scorecard draws.
local NONE_MARK = "\226\128\148"
local function relSec(g, t)
  if not t or not g.t0 then return NONE_MARK end
  return ("%.1f s"):format(t - g.t0)
end

-- `extra` carries the timeline's analysis fields: what the player DID, what was
-- EXPECTED instead, what it COST, and an optional GHOST bar (the shot that
-- should have been there). Absent fields stay nil — never invent a number.
local function verdict(g, t, code, ms, text, key, extra)
  -- `cycle` is the auto-to-auto cycle the fault happened in (1-based from the
  -- first auto release, the same index T.Cycles uses), so the review can offer
  -- a replay of the cycle that earned each fix. 0 means "before the first auto".
  local v = { t = t, code = code, ms = ms, text = text, key = key, cycle = g.cycleIx }
  if extra then
    v.did, v.expected, v.cost, v.ghost = extra.did, extra.expected, extra.cost, extra.ghost
  end
  g.verdicts[#g.verdicts + 1] = v
  g.lastVerdict = v
  return v
end

-- A STEADY WON'T FIT waits for the clip it predicted, to take that clip's cost
-- as its own. When the shot goes out clean instead — or another won't-fit press
-- arrives first — the prediction cost no auto: close the pending verdict here
-- rather than let it claim an unrelated later clip.
local NO_CLIP = "no clip (shot went out)"
local function closeWontFit(g)
  if g.lastWontFit then
    g.lastWontFit.cost = NO_CLIP
    g.lastWontFit = nil
  end
end

-- One scorecard window per haste state (spec: "the haste-adaptation grade").
local function openWindow(g, t, rangedMul, flags)
  local w = g.win
  if w then w.t1 = t end
  w = { t0 = t, t1 = nil, rangedMul = rangedMul, flags = flags,
        notation = g.notationFor(rangedMul, flags), autos = 0, gcds = 0, clips = 0,
        s = 0, m = 0, A = 0, w = 0 }
  g.windows[#g.windows + 1] = w
  g.win = w
end

--------------------------------------------------------------------------------
-- THE PAPER IS THE SCOPE
--
-- Which symbols the notation being graded actually contains. A drill whose
-- paper has no `w` is not a weave fight however the weave key is bound: the
-- ENGINE keeps swinging and keeps opening opportunity windows (the mechanics
-- are real, and the melee grid the views draw is honest), but nothing here
-- faults them or counts them — and Practice:Lookahead drops the live rotation
-- engine's advice for any symbol the paper never asks for, so a 1:1 drill can
-- no longer be told to Arcane.
--
-- Cached per notation string for the session: one five-field table per string
-- in M.STRINGS (the canonical rotations plus the ladder's teaching papers),
-- built the first time a window asks. The tick reads it
-- back with two lookups and allocates nothing.
--------------------------------------------------------------------------------
local SYMS_NONE = { s = false, m = false, A = false, w = false, r = false }
local symsCache = {}

function G.Syms(model, notation)
  if not (model and notation) then return SYMS_NONE end
  local t = symsCache[notation]
  if not t then
    -- An unknown notation falls back to "as" exactly as layoutFor does, so the
    -- symbol set and the notes can never disagree about what the paper is.
    local str = model.STRINGS[notation] or "as"
    t = { s = false, m = false, A = false, w = false, r = false }
    for i = 1, #str do
      local c = str:sub(i, i)
      if t[c] ~= nil then t[c] = true end
    end
    -- A basic paper carries a Multi in practice at every haste (M.PaperString).
    if model.MULTI_BASIC and model.MULTI_BASIC[notation] then t.m = true end
    symsCache[notation] = t
  end
  return t
end

-- The set for the window being graded right now — the fight's opening notation
-- until the first window opens. Handed back by reference: the views READ it.
function G.PaperSyms(g)
  if not g then return SYMS_NONE end
  return G.Syms(g.model, (g.win and g.win.notation) or g.notation)
end

-- Does the paper ask for melee at all? The one gate on every weave fault and
-- on the weave counters. `r` as well as `w`: M.Layout treats both as weave
-- slots and M.Shorthand counts them together.
local function paperWeaves(g)
  local s = G.PaperSyms(g)
  return s.w or s.r
end

--------------------------------------------------------------------------------
-- PAPER NOTES AND JUDGMENTS
--
-- The paper rotation laid out per haste window, split into auto-to-auto cycles,
-- and one verdict per NOTE: PERFECT / GOOD / LATE / CLIP / MISSED / OFF. These
-- verdicts carry `kind = "judge"` and no `code`, which is what keeps them out of
-- the fault list and the timeline's marks (see PracticeTimeline) — they are the
-- stream the conveyor's pops and the streak read, nothing else.
--------------------------------------------------------------------------------

-- PracticeTimeline, for the shared note-key scheme. Resolved lazily (the two
-- files are pure and are dofile'd in either order by the tests), and optional:
-- with no timeline in reach the notes simply carry no key, and every judgment
-- still lands.
local function timeline(g)
  local T = g.timeline
  if T == nil then
    local N = rawget(_G, "Nock")
    T = (N and N.PracticeTimeline) or false
    g.timeline = T
  end
  return T or nil
end

-- Each auto RELEASE of a layout — the cycle boundaries, as paperCycles reads
-- them in PracticeTimeline — and, beside each, THE DELAY THE PAPER ITSELF
-- BUDGETS for that auto.
--
-- M.Layout is a greedy scheduler: it lets a cast run past the moment the next
-- wind-up could start and books the overlap in `delays` (5:5:1:1 at eWS 2.174
-- budgets ~0.25 s of it per five-auto period). So a hunter who plays the
-- notation exactly still releases some autos late, by the paper's own design.
-- Those are not faults, and grading them as clips made the paper fail itself
-- every cycle — which the 3-clip cap then held at B by construction.
--
-- READ THE BUDGET OFF THE RELEASE GRID, NOT OFF `delays`. `lay.delays` only
-- records the slips M.Layout writes BETWEEN two autos of the string, and it
-- never records the WRAP — the gap from the period's last release back to the
-- first of the next one. That gap carries a budget whenever the layout's period
-- is longer than its autos need, which is the whole story at GCD-bound haste:
-- "as" (1:1) at eWS 1.34 has a period of 1.5 s (the GCD) against a 1.34 s
-- swing, so the paper itself delays EVERY auto by 160 ms — and, with a
-- single-auto string, `delays` is empty and the grader billed all of it to the
-- player. The 1:1 rung was unpassable by construction.
--
-- The gap before release k, minus the swing the grid would have kept on its
-- own, IS the delay the paper schedules for it; for interior autos this is
-- identical to the `delays` entry it replaces (M.Layout's own arithmetic), and
-- for k = 1 it closes the wrap.
local function releases(lay, rel, dly, cycle)
  local n, ev = 0, lay.ev
  for i = 1, #ev do
    local pe = ev[i]
    if pe.sym == "a" then
      n = n + 1
      rel[n] = pe.t0 + pe.dur
    end
  end
  for k = 1, n do
    local prev = (k > 1) and rel[k - 1] or (rel[n] - lay.dur)
    local d = (rel[k] - prev) - (cycle or 0)
    dly[k] = (d > 0) and d or 0
  end
  return n
end

-- The paper laid out for the CURRENT haste window, cached with exactly the key
-- T.Strip's forecast caches it under (the notation string and the haste
-- multiplier; weapon speed and the cast residual are fixed for a fight here).
--
-- THE KEY MAPPING, stated once. `gen` bumps only when that key CHANGES, which
-- `strOverride` is a SHOT STRING (M.STRINGS[notation]), not a notation name;
-- with `mulOverride` it lays out a paper before any haste window exists (the
-- armed strip, via G.Layout) -- the open window wins whenever there is one.
local function layoutFor(g, strOverride, mulOverride)
  local w = g.win
  if not g.model then return nil end
  if not (w or strOverride) then return nil end
  local nota = w and w.notation or nil
  local ovr = (not w) and strOverride or nil
  local mul = (w and w.rangedMul) or mulOverride or g.h.rangedMul or 1
  local ws, cc = g.h.ws, g.h.castCorr
  local c = g.lay
  if not c then c = { rel = {}, dly = {} }; g.lay = c end
  -- The cache key is every input the layout's SHAPE depends on: the window's
  -- notation (or the armed override string), the haste, the weapon, the cast
  -- residual. The string itself is resolved inside the miss -- a basic
  -- paper's Multi cadence is a function of the haste (M.PaperString) -- so
  -- the hit path allocates nothing.
  if c.nota ~= nota or c.ovr ~= ovr or c.mul ~= mul or c.ws ~= ws or c.cc ~= cc then
    local hw = {}
    for k, v in pairs(g.h) do hw[k] = v end
    hw.rangedMul = mul
    local str = (nota and g.model.PaperString and g.model.PaperString(nota, hw))
      or (nota and g.model.STRINGS[nota]) or ovr or "as"
    local lay = g.model.Layout(str, hw, 0)
    local T = timeline(g)
    c.nota, c.ovr, c.str, c.mul, c.ws, c.cc = nota, ovr, str, mul, ws, cc
    c.ev, c.dur = lay.ev, lay.dur
    -- CHAINED OR ON THE BEAT. A shot note that follows the paper's previous
    -- shot by no more than a GCD is chained: the paper means "as soon as the
    -- hand is free", and the plan asks for it then. One further apart sits on
    -- the beat by design (the teaching drills' one press per cycle, 1:1's
    -- Steady on the release): its slot is a floor. Wraps round the period.
    local shots, GCD_CHAIN = {}, (g.model.GCD or 1.5) + 0.12
    for i = 1, #lay.ev do
      local pe = lay.ev[i]
      if pe.sym == "s" or pe.sym == "m" or pe.sym == "A" then shots[#shots + 1] = pe end
    end
    for i = 1, #shots do
      local prev = (i > 1) and shots[i - 1].t0 or (shots[#shots].t0 - lay.dur)
      shots[i].chained = (shots[i].t0 - prev) <= GCD_CHAIN
    end
    -- The swing the grid keeps on its own at this window's haste — what the
    -- paper's own release gaps are measured against (see `releases`).
    c.autos = releases(lay, c.rel, c.dly, (ws or 3.0) / mul)
  end
  if not (c.autos and c.autos > 0 and c.dur and c.dur > 0) then return nil end
  return c
end

-- The cached layout for the open window -- or, before the pull, for an explicit
-- shot string at an explicit haste. What the plan builder seats the cycles
-- ahead on.
function G.Layout(g, str, mul) return layoutFor(g, str, mul) end

-- The delay the PAPER budgets for the auto that just released, in seconds.
--
-- `w.autos` has already counted that auto (the `auto` branch bumps the window
-- before the clip test), so its 0-based index inside the haste window is
-- `w.autos - 1` — the very index fillCycle seats the cycle's notes on. Using
-- the same mapping is the point: the fault and the judgments are then talking
-- about one cycle position, not two.
local function paperDelay(g)
  local w = g.win
  local lay = layoutFor(g)
  if not (w and lay and lay.autos and lay.autos > 0) then return 0 end
  local absAuto = (w.autos or 1) - 1
  if absAuto < 0 then absAuto = 0 end
  return lay.dly[absAuto % lay.autos + 1] or 0
end

-- Slack on top of that budget. The layout is MODELLED and the stream is
-- MEASURED; 50 ms between the two is drift, not a clip.
local PAPER_DELAY_EPS = 0.05

local function newCycle()
  return { ix = 0, t0 = 0, t1 = nil, sweepAt = nil, n = 0, off = 0, closed = true, partial = false,
           hasPaper = false, lastNote = nil, nT0 = {}, nSym = {}, nKey = {}, nUsed = {},
           nState = {}, nGrade = {}, nChained = {} }
end

-- Seat one cycle's paper notes on the release that opened it. The layout is
-- written with its first auto STARTING at 0 while a cycle starts at a RELEASE,
-- so the layout is shifted until the auto this cycle belongs to releases on the
-- measured one -- the reason a note's time is honest even when the modelled
-- period drifts from the grid.
--
-- SHARED with the plan builder (Core/PracticePlan.lua), which seats the cycles
-- AHEAD of the open one on the engine's grid with this same routine, so a
-- projected note's key and time are exactly what this grader will hold once
-- that release lands. `absAuto` is the 0-based auto index inside the haste
-- window; `rec` must carry n, nT0, nSym, nKey, nUsed, nState, nGrade, lastNote.
function G.SeatCycle(lay, absAuto, releaseAt, rec, T, cycleIx)
  if absAuto < 0 then absAuto = 0 end
  local autos, rel, ev, dur = lay.autos, lay.rel, lay.ev, lay.dur
  local phase = absAuto % autos
  local period = (absAuto - phase) / autos
  local lo = rel[phase + 1]
  local hi = (phase + 1 < autos) and rel[phase + 2] or (rel[1] + dur)
  local shift = releaseAt - lo
  rec.n, rec.lastNote = 0, nil
  for i = 1, #ev do
    local pe = ev[i]
    if NOTE_SYM[pe.sym] then
      -- The tail after the last auto wraps into the last cycle (paperCycles'
      -- rule).
      local pt = pe.t0
      if pt < rel[1] - EPS then pt = pt + dur end
      if pt >= lo - EPS and pt < hi - EPS then
        local k = rec.n + 1
        rec.n = k
        local nt = shift + pt
        rec.nT0[k], rec.nSym[k], rec.nUsed[k] = nt, pe.sym, false
        rec.nState[k], rec.nGrade[k] = PENDING, nil
        if rec.nChained then rec.nChained[k] = pe.chained or false end
        -- Keyed by the note's ORDER in its cycle (k), not its layout slot: a
        -- haste window re-phases the paper, and cycle N's first note must stay
        -- cycle N's first note -- the view swaps its icon in place instead of
        -- fading a new one in.
        rec.nKey[k] = T and T.NoteKey(cycleIx, k) or nil
        -- THE LAST MOMENT THIS CYCLE CAN STILL BE PLAYED. The layout's cycle
        -- window is `hi - lo` wide and the MEASURED one is a weapon cycle: on a
        -- paper whose period is longer than its autos need (3:7 2w budgets a
        -- 1.55 s cycle against a 0.9 s swing) a note is seated PAST the next
        -- release. The sweep has to wait for it, or the note it seated there is
        -- MISSED before the hand that plays it dead-on ever arrives.
        if not rec.lastNote or nt > rec.lastNote then rec.lastNote = nt end
      end
    end
  end
  return rec
end

local function fillCycle(g, c, t)
  g.cycleIx = g.cycleIx + 1
  c.ix, c.t0, c.t1, c.sweepAt = g.cycleIx, t, nil, nil
  c.n, c.off, c.closed, c.partial, c.hasPaper = 0, 0, false, false, false
  if c.nCarried then for k in pairs(c.nCarried) do c.nCarried[k] = nil end end
  c.lastNote = nil
  local w = g.win
  local lay = layoutFor(g)
  if not (w and lay) then return c end
  -- `w.autos` has already counted the release that opened this cycle.
  c.hasPaper = true
  G.SeatCycle(lay, (w.autos or 1) - 1, t, c, timeline(g), c.ix)
  -- A note of this cycle already played early on the plan's word (planPrePlay)
  -- is HIT from the start, wearing the grade its press earned.
  local pre = g.prePlayed
  if pre then
    for i = 1, c.n do
      local k = c.nKey[i]
      local grade = k and pre[k]
      if grade then
        c.nUsed[i], c.nState[i] = true, HIT
        c.nGrade[i] = (type(grade) == "string") and grade or "GOOD"
        pre[k] = nil
      end
    end
  end
  -- (a fixture may hand meleeCycle = 0: "no swing constraint on this stream")
  if g.meleeCycle > 0 then
    -- THE SWING CHAINS, here exactly as in the plan (Core/PracticePlan.lua
    -- `put`): from the last REAL hit, and from any weave note already seated
    -- and still waiting to be played -- the paper wants that hit, so the swing
    -- is spoken for one melee cycle after it. Without the second half two
    -- consecutive cycles seated their `w` on the SAME swing return (a 2.17 s
    -- cycle on a 3.7 s weapon), the plan had chained the second one a swing
    -- later, and the note jumped when its cycle opened.
    local from = g.lastMeleeT
    local prev = g.pend
    if prev and prev ~= c then
      for i = 1, prev.n do
        local sym = prev.nSym[i]
        if (sym == "w" or sym == "r") and prev.nState[i] == PENDING then
          local t0 = prev.nT0[i]
          if not from or t0 > from then from = t0 end
        end
      end
    end
    if from then G.RetimeWeaves(c, from + g.meleeCycle) end
    local cycle, windup = G.RangedGrid(g)
    G.FitWeaves(c, c.t0, cycle, windup, G.LegsNeeded(g), nil, G.StepIn(g))
  end
  return c
end

-- A WEAVE NOTE IS SEATED WHERE THE SWING CAN MAKE IT. The paper writes the
-- weave at its slot assuming the melee swing is up; when the last hit landed
-- late the swing is still recharging there, and grading the note at the paper's
-- slot punished the same lateness twice -- and drew the note a whole ramp
-- before the window it could land in. So a `w` note whose slot precedes the
-- swing's return is moved onto it, once, at seat time: the grader, the plan,
-- the move-in ramp and the band then all hold ONE time for it. Shared with the
-- plan builder for the cycles it projects ahead (Core/PracticePlan.lua).
-- WHERE A WEAVE CAN START, given the ranged grid: never inside the wind-up. A
-- weave that cannot finish (legs) before the wind-up of its own cycle wants to
-- start would clip the auto -- so it goes after the NEXT release instead. The
-- swing rule (RetimeWeaves) pushed a note onto the swing's return, which on a
-- 3.6 s swing under a 3.7 s auto drifts a little later every hit until it lands
-- in the wind-up: the grader then budgeted the weave a NEGATIVE leg time and
-- called it DEAD ZONE (practice report, 2026-08-24). Shared with the plan.
-- ...AND THE NOTE IS THE HIT, one step-in after the release at the earliest
-- (`stepIn`, this player's measured leg). The paper writes the weave AT the
-- release; graded there, a hunter who steps in the moment the arrow leaves
-- -- the only honest time -- is LATE by the walk on every weave, and the
-- stage drew the move-in ramp BEFORE the release, which is the dead zone
-- (user, 2026-08-26: "the auto goes out when you are supposed to move in").
function G.FitWeave(t0, rel, cycle, windup, legs, stepIn)
  if not (rel and cycle and cycle > 0) then return t0 end
  local si = (stepIn and stepIn > 0) and stepIn or 0
  -- The cycle the note LANDS in, not only the one that seated it: a note
  -- chained on the swing two cycles ahead was tested against its own
  -- cycle's wind-up and could sit inside a later one (plan test 5).
  for _ = 1, 8 do
    -- (k may be negative: a note chained into the room of an earlier cycle
    -- -- the swing returns there and the wind-up is clear -- follows THAT
    -- release, not its own cycle's.)
    local k = math.floor((t0 - rel) / cycle + EPS)
    local r = rel + k * cycle
    if t0 < r + si - EPS then t0 = r + si end
    local ws = r + cycle - (windup or 0)
    if t0 + (legs or 0) <= ws + EPS then return t0 end
    -- Never earlier: past the next release, a step-in after it.
    t0 = r + cycle + si
  end
  return t0
end

-- Apply FitWeave to a record's PENDING weave notes after `afterT` (its own
-- release for a freshly seated cycle). `rel` is the release that opened it.
function G.FitWeaves(rec, rel, cycle, windup, legs, afterT, stepIn)
  for i = 1, rec.n do
    local sym = rec.nSym[i]
    if (sym == "w" or sym == "r") and (rec.nState[i] == nil or rec.nState[i] == PENDING)
       and (afterT == nil or rec.nT0[i] > afterT) then
      local t = G.FitWeave(rec.nT0[i], rel, cycle, windup, legs, stepIn)
      if t > rec.nT0[i] then
        rec.nT0[i] = t
        if not rec.lastNote or t > rec.lastNote then rec.lastNote = t end
      end
    end
  end
  return rec
end

-- The ranged grid as the grader knows it: the cycle and the wind-up at the
-- open window's haste.
function G.RangedGrid(g)
  local mul = (g.win and g.win.rangedMul) or g.h.rangedMul or 1
  local cycle = (g.h.ws or 3.0) / mul
  local windup = (g.model and g.model.CastTime) and g.model.CastTime(0.5, mul) or (0.5 / mul)
  return cycle, windup
end

-- Only PENDING notes move, and only those AFTER `afterT` when given: a hit
-- re-seats the weave that follows it, never the one it took, and never an
-- unplayed note behind it (that one is the sweep's, and moving it forward
-- would seat two notes on one swing).
function G.RetimeWeaves(rec, meleeReadyAt, afterT)
  if not (meleeReadyAt and meleeReadyAt > 0) then return rec end
  for i = 1, rec.n do
    local sym = rec.nSym[i]
    if (sym == "w" or sym == "r") and (rec.nState[i] == nil or rec.nState[i] == PENDING)
       and rec.nT0[i] < meleeReadyAt - EPS and (afterT == nil or rec.nT0[i] > afterT) then
      rec.nT0[i] = meleeReadyAt
      if not rec.lastNote or meleeReadyAt > rec.lastNote then rec.lastNote = meleeReadyAt end
    end
  end
  return rec
end

-- One judgment. `t` is the moment it is PUSHED — what the conveyor ages its
-- pops by — while the note's own time stays on `note.t0`; the two differ by a
-- cast (a cast is judged when its event arrives) or by the sweep's grace (a
-- MISSED is judged when nothing can play the note any more).
--
-- `note` is a fresh little table because the cycle records are pooled and
-- refilled two cycles later, while a verdict lives for the fight.
-- `g.lastVerdict` is deliberately NOT moved: that field drives the panel's
-- fault toast, and a toast per note played is not a fault report.
local function pushJudge(g, t, grade, deltaMs, cycle, nT0, nSym, nKey, rec, i)
  if rec and i then rec.nGrade[i] = grade end
  local v = { kind = "judge", t = t, grade = grade, deltaMs = deltaMs, cycle = cycle,
              note = { t0 = nT0, sym = nSym, key = nKey } }
  g.verdicts[#g.verdicts + 1] = v
  local f = JUDGE_FIELD[grade]
  if f then g.judge[f] = g.judge[f] + 1 end
  if grade == "PERFECT" or grade == "GOOD" then
    g.streak = g.streak + 1
    if g.streak > g.bestStreak then g.bestStreak = g.streak end
  else
    g.streak = 0
  end
  return v
end

-- A weave is a weave: the paper only ever writes the slot as `w`, and a played
-- Raptor arrives as `r`. Normalised in that ONE direction, exactly as
-- T.Cycles' sameSlot does — an `r` where the paper wanted a Steady is not a
-- weave taken.
local function noteTakes(noteSym, played)
  return noteSym == played or (noteSym == "w" and played == "r")
end

-- THE RELEASE BELONGS TO THE CYCLE IT OPENS. A cast that starts within a client
-- frame of a release is the shot that release opened the door for, and it takes
-- the NEW cycle's note. The boundary used to be exact (1e-9), which made it a
-- coin flip: the engine starts a queued cast at the release itself, and a hair
-- of float — or a press the latency shifted by a millisecond — dropped it into
-- the cycle behind, where the note it wanted was either a whole cycle away
-- (LATE) or already consumed (OFF), while the new cycle's went MISSED.
--
-- One 30 Hz frame is the width of the doubt; half a second is not, and still
-- belongs to the cycle it was started in.
--
-- THE ONE DEFINITION IS `T.CYCLE_EPS` (Core/PracticeTimeline.lua's `cycleAt`),
-- because the scorecard's own "cycles on paper" figure is rebuilt by T.Cycles
-- from the same stream: two epsilons meant a cast 4 ms early could be judged
-- PERFECT six times out of six while T.Cycles counted 4 of 6 cycles on paper —
-- a C grade under a row of green pops. The literal here is the fallback for a
-- grader built without a timeline handle (a bare unit test).
local CYCLE_EPS_FALLBACK = 0.033
local function cycleEps(g)
  local T = timeline(g)
  return (T and T.CYCLE_EPS) or CYCLE_EPS_FALLBACK
end

-- The cycle a played symbol belongs to: the open one, or the one still waiting
-- to close behind it (a cast event arrives at its END, so a cast that started
-- late in a cycle reaches the grader after the release that ended it). Nil
-- before the first auto release — the opener's pre-pull Steady belongs to no
-- cycle and is not judged, the same rule T.Cycles grades by.
local function cycleFor(g, t)
  local eps = cycleEps(g)
  local c = g.cur
  if c and t >= c.t0 - eps then return c end
  c = g.pend
  if c and t >= c.t0 - eps then return c end
  return nil
end

-- THE PLAN'S TIME FOR A NOTE (P3 polish). The plan (Core/PracticePlan.lua)
-- mints the same key the grader seats, and may ask for the note LATER than its
-- paper slot -- held to the release when the cast would not fit, pushed past a
-- GCD that was still running. A press is judged against the moment the oracle
-- asked for it, never against a slot the oracle itself said was unplayable:
-- the ghost hunter, pressing exactly on the plan's word, was scored MISSED on
-- every held note and OFF on every note the plan pulled forward. No plan (a
-- bare fixture) means the paper slot.
local function planTime(g, key, fallback)
  local plan = g.plan
  if not (plan and plan.live and key) then return fallback end
  local notes = plan.notes
  for i = 1, plan.n do
    local nt = notes[i]
    if nt.key == key then
      -- A note the plan gave up on (a Steady superseded by the next cycle's)
      -- has no plan time: it is swept like any unplayed note.
      if nt.lost then return fallback end
      return nt.t0
    end
  end
  return fallback
end

-- The latest plan time among a cycle's unplayed notes -- the last moment the
-- plan still asks for one of them -- or nil without a plan (sweepDue).
local function planLast(g, c)
  local plan = g.plan
  if not (plan and plan.live) then return nil end
  local last
  for i = 1, c.n do
    if not c.nUsed[i] then
      local t = planTime(g, c.nKey[i], nil)
      if t and (not last or t > last) then last = t end
    end
  end
  return last
end

-- Nearest UNCONSUMED note of the same symbol class inside one cycle, by the
-- plan's time for it. Returns index, signed delta, |delta|.
local function nearestNote(g, c, t, sym)
  local best, bestAbs, bestD
  for i = 1, c.n do
    if not c.nUsed[i] and noteTakes(c.nSym[i], sym) then
      local d = t - planTime(g, c.nKey[i], c.nT0[i])
      local ad = (d < 0) and -d or d
      if not bestAbs or ad < bestAbs then best, bestAbs, bestD = i, ad, d end
    end
  end
  return best, bestD, bestAbs
end

-- A note of a cycle NOT SEATED YET, pressed early on the plan's word: the plan
-- pulls the paper's instant forward into room a Steady cannot use, so the press
-- lands a cycle or two before the note's own cycle opens. It is remembered by
-- key (g.prePlayed); when its cycle is seated the note is HIT from the start
-- (fillCycle), so it is neither an OFF press now nor a MISSED note later.
local PREPLAY_SEC = 0.6
local function planPrePlay(g, t, sym)
  local plan = g.plan
  if not (plan and plan.live and g.prePlayed) then return nil end
  local cur, pend = g.cur, g.pend
  local best, bestAbs, bestD
  for i = 1, plan.n do
    local nt = plan.notes[i]
    if nt.state == PENDING and noteTakes(nt.sym, sym) and not g.prePlayed[nt.key] then
      local seated = (cur and nt.cycle == cur.ix) or (pend and nt.cycle == pend.ix)
      if not seated then
        local d = t - nt.t0
        local ad = (d < 0) and -d or d
        if ad <= PREPLAY_SEC and (not bestAbs or ad < bestAbs) then best, bestAbs, bestD = nt, ad, d end
      end
    end
  end
  if not best then return nil end
  g.prePlayed[best.key] = true
  return best.key, bestD, best.t0, best.sym, best.cycle
end

-- THE MATCHER OWNS CYCLE MEMBERSHIP (R5a).
--
-- A play belongs to the cycle of the NOTE it took, not to the cycle the clock
-- drops it in. The two are usually the same thing and were assumed to be, but
-- they part company whenever the paper's own cycle is WIDER than the measured
-- one: `fillCycle` seats a cycle's notes across the layout's window (3:7 2w
-- schedules a 1.55 s cycle against a 0.9 s swing), so a note can sit past the
-- next release. Filing by the clock alone then read the hand that played that
-- note dead-on as an OFF press in the next cycle while the note itself went
-- MISSED in this one — two red cells on the review's ROTATION row (`w s` beside
-- an empty one) under a row of PERFECT pops.
--
-- So the search reaches into the cycle still waiting on its grace when the open
-- one has nothing of that class left. Order matters and is deliberate: the open
-- cycle is asked FIRST, so a press that lands squarely in it can never be
-- stolen by an older orphan note; only when the paper has nothing there does an
-- unconsumed note behind it become the honest answer.
--
-- Returns the cycle THE NOTE LIVES IN, the note index and the signed delta;
-- index nil means no note of that class was left anywhere in reach — a real OFF
-- press, and one that keeps filing by the clock (see `T.Cycles`' match map).
local function matchNote(g, t, sym)
  local c = cycleFor(g, t)
  -- No paper for this cycle at all (a stream with no haste window behind it):
  -- nothing to judge against, so nothing is judged. A cycle whose paper is
  -- simply EMPTY is a different thing — a press there is a real OFF.
  if not (c and c.hasPaper) then return nil end
  local best, bestD, bestAbs = nearestNote(g, c, t, sym)
  local prev = (c ~= g.pend) and g.pend or nil
  if prev and prev.hasPaper and not prev.closed then
    local pBest, pD, pAbs = nearestNote(g, prev, t, sym)
    -- With a plan in hand the nearer note by the PLAN's time wins wherever it
    -- lives: a Steady held to the release sits, by the plan, exactly where the
    -- new cycle's own Steady sits by the paper, and the press at the release
    -- is the held one's. Without a plan the open cycle keeps its priority.
    if pBest and (not best or (g.plan and pAbs < bestAbs)) then
      prev.nUsed[pBest], prev.nState[pBest] = true, HIT
      return prev, pBest, pD
    end
  end
  if best then
    c.nUsed[best], c.nState[best] = true, HIT
    return c, best, bestD
  end
  local preKey, preD, preT0, preSym, preCycle = planPrePlay(g, t, sym)
  if preKey then return c, nil, preD, preKey, preT0, preSym, preCycle end
  c.off = c.off + 1
  return c, nil, nil
end

local function gradeFor(d)
  local ad = (d < 0) and -d or d
  if ad <= PERFECT_SEC then return "PERFECT" end
  if ad <= GOOD_SEC then return "GOOD" end
  return "LATE"
end

-- A cast's grade is known the moment its event arrives — the match is against
-- the note, and the note is not going anywhere — so it is pushed INLINE and the
-- conveyor pops it while the note is still on screen. It used to be held back
-- until the next auto, on the chance that this cast had clipped the shot: that
-- put every cast judgment a cycle behind the `t` it carried, which is longer
-- than the pops live (T.POP_LIFE), so the stage popped nothing at all.
--
-- The clip is not lost by that. It arrives at the release, as a SECOND judgment
-- on the same note — a CLIP pop where the note is, at the moment the shot went
-- out late — and the counters are re-cast so the note is still counted once.
-- Only a cast that MATCHED a note is upgraded: a cast the paper had no note for
-- stays OFF (the extra press is the lesson, and its clip is already a CLIP
-- fault of its own with no note for a pop to sit on).
local function clipJudge(g, t, clipMs)
  local v = g.lastCastV
  if not (v and g.lastCastMatched) then return end
  local f = JUDGE_FIELD[v.grade]
  if f then g.judge[f] = g.judge[f] - 1 end     -- the note is one note, not two
  -- pushJudge resets the streak below. `bestStreak` keeps whatever that inline
  -- good already earned: the run really did reach that length on screen, and
  -- rolling it back would silently rewrite a number the header had shown.
  local note = v.note
  pushJudge(g, t, "CLIP", clipMs, v.cycle, note.t0, note.sym, note.key, g.lastCastRec, g.lastCastIdx)
end

-- Closing a cycle is the sweep: every note nobody played is MISSED, and the
-- cycle counts as ON PAPER when it lost no note and gained no extra press.
-- A partial trailing cycle (the fight stopped inside it) judges nothing — it
-- would report a rotation the player was never given time to finish.
--
-- `at` is the moment the sweep FIRES, and it is what the verdict is stamped
-- with. The cycle's own end is up to a grace (a whole Steady cast) earlier, and
-- a judgment stamped there is born older than the conveyor's pops live
-- (T.POP_LIFE) — the stage would never show a missed note at all. The note's own
-- time is where it always was, on `note.t0`.
local function closeCycle(g, c, at)
  if not c or c.closed then return end
  c.closed = true
  if c.partial then return end
  local t = at or c.t1 or c.t0
  local missed = 0
  local carried = c.nCarried
  for i = 1, c.n do
    if not c.nUsed[i] and not (carried and carried[i]) then
      missed = missed + 1
      c.nState[i] = MISSED
      pushJudge(g, t, "MISSED", nil, c.ix, c.nT0[i], c.nSym[i], c.nKey[i], c, i)
    end
  end
  if c.hasPaper then
    g.cyclesTotal = g.cyclesTotal + 1
    if missed == 0 and c.off == 0 then g.cyclesOk = g.cyclesOk + 1 end
  end
end

-- Sweeping returns the record to the one-slot pool: at most three cycle tables
-- exist for a whole fight (the open one, the one on grace, and the spare).
local function sweep(g, c, at, why)
  if g.onSweep then g.onSweep(c, at, why) end   -- a test's ear; nil in the addon
  closeCycle(g, c, at)
  g.spare = c
end

-- HOW LONG A CLOSED CYCLE WAITS FOR ITS SWEEP. A cycle ENDS at its own release
-- and nothing about it changes afterwards — except that a cast which started
-- inside it arrives at its END, i.e. after that release, and must still be able
-- to take its note. One Steady cast is the longest that can be: a cast started
-- at the very last instant of the cycle arrives one steady cast later, and
-- nothing started earlier can arrive later than that (casts do not overlap, so
-- they arrive in the order they started).
local STEADY_BASE = 1.5   -- PracticeModel.Abilities' `s`, before haste
local function graceFor(g)
  local mul = (g.win and g.win.rangedMul) or g.h.rangedMul or 1
  if g.model and g.model.CastTime then return g.model.CastTime(STEADY_BASE, mul, g.h.castCorr) end
  return STEADY_BASE / mul
end

-- ...and the two moments that end the wait early or at all: a CAST that started
-- at or after the closed cycle's end proves no earlier cast is still in flight
-- (see above), and any event past the grace says the same by the clock. The
-- next release and G.Finish are the backstops.
--
-- `t` is what the DECISION is made on and `at` is when the sweep actually
-- happens — they differ for a cast, which decides on its start but arrives at
-- its end, and it is the arrival that the verdict is stamped with. Stamping the
-- start would hand the pop a verdict already a whole cast old.
local function sweepDue(g, t, castStart, at)
  local c = g.pend
  if not c or not t then return end
  local t1 = c.t1 or c.t0
  -- ...measured from the last moment the cycle can still be played, which is
  -- its own end OR the last note it seated, whichever is later (see fillCycle).
  local eps = cycleEps(g)
  local orphan = c.lastNote and c.lastNote > t1
  local due = orphan and c.lastNote or t1
  -- ...or the latest moment THE PLAN still asks for one of its unplayed notes
  -- (a Steady held to the release, a Multi pushed past a GCD): the cycle stays
  -- open for that press, with a judgment's worth of slack (GOOD_SEC) rather
  -- than a frame -- the press that takes a held note is a hand's, not a queue's.
  local held = planLast(g, c)
  if held and held > due - eps then
    orphan, due = true, held
    eps = GOOD_SEC
  end
  -- THE CAST-START SHORTCUT, and the one case it must not take. Normally a cast
  -- that starts within a frame of the closed cycle's end is the NEXT cycle's,
  -- so nothing of this one is still coming and it can be swept at once.
  --
  -- Not when the cycle seated a note PAST its own end (5:5:1:1 at eWS 1.55 puts
  -- its Arcane at +1.967 in a 1.55 s cycle). The cast that plays that very note
  -- starts AT it, which the shortcut read as "past the end, sweep" — so the
  -- note was MISSED a moment before the press that took it dead-on arrived, and
  -- the press itself came out OFF in the next cycle. An orphan note holds the
  -- cycle open until its own moment has actually gone by.
  local shortcut
  if orphan then shortcut = castStart and t > due + eps
  else shortcut = castStart and t >= due - eps end
  if shortcut or t > (c.sweepAt or due) + EPS then
    g.pend = nil
    sweep(g, c, at or t, shortcut and "cast-start" or "clock")
  end
end

-- An auto release: it ends the open cycle, parks it for its grace, and opens
-- the next one. Matched judgments are never delayed by any of this; only the
-- MISSED sweep waits, and only for as long as a cast can still be in flight.
-- A NOTE THE PLAN STILL ASKS FOR OUTLIVES ITS CYCLE. The grader keeps two
-- cycles (the open one and the one on grace); a release sweeps the older.
-- The plan, chaining on the hand's clock, can ask for a note AFTER the
-- release that closes its cycle (an instant pulled in front of a Steady at a
-- period boundary puts the Steady 0.7 s past it): swept MISSED at the
-- release, the press made on the plan's word a moment later took the NEXT
-- cycle's note, and every Steady ran one cycle behind -- a MISSED pop on
-- every auto (gate, 2026-08-25). Such a note is carried into the cycle that
-- is closing now, key and all, and is neither missed nor played until it is.
local function carryOver(g, from, to, t)
  if not (from and to and g.plan and g.plan.live) then return end
  for i = 1, from.n do
    if not from.nUsed[i] then
      local at = planTime(g, from.nKey[i], nil)
      local nt = g.plan and g.plan.notes
      local lost = false
      if nt then for j = 1, g.plan.n do if nt[j].key == from.nKey[i] then lost = nt[j].lost == true; break end end end
      -- ...or the note a queued press is waiting to cast: pressed inside the
      -- wind-up, its cast begins at this very release and reaches the grader
      -- a cast later; swept here it went MISSED and the cast took the next
      -- cycle's note (gate, 2026-08-26).
      local q = g.queuedPress
      local queued = q and at and noteTakes(from.nSym[i], q.sym) and math.abs(at - q.t) <= GOOD_SEC
      if at and (at > t - GOOD_SEC or queued) and not lost then
        local k = to.n + 1
        to.n = k
        to.nT0[k], to.nSym[k], to.nKey[k], to.nUsed[k] = from.nT0[i], from.nSym[i], from.nKey[i], false
        to.nState[k], to.nGrade[k] = PENDING, nil
        if to.nChained then to.nChained[k] = from.nChained and from.nChained[i] or false end
        from.nCarried = from.nCarried or {}
        from.nCarried[i] = true
      end
    end
  end
end

local function onRelease(g, t)
  local cur = g.cur
  if cur then
    cur.t1 = t
    local last = t
    if cur.lastNote and cur.lastNote > last then last = cur.lastNote end
    -- A note the plan holds past the release (to the release itself, or past
    -- a GCD) is pressed by a hand AFTER that moment: its cast then arrives
    -- later than the grace allows for, so the grace runs from the hold plus a
    -- judgment's slack (GOOD_SEC), else the sweep MISSED the note a frame
    -- before the cast that took it dead-on came in.
    local held = planLast(g, cur)
    if held and held + GOOD_SEC > last then last = held + GOOD_SEC end
    cur.sweepAt = last + graceFor(g)
  end
  local waiting = g.pend
  if waiting then
    carryOver(g, waiting, cur, t)
    g.pend = nil
    sweep(g, waiting, t, "release")
  end
  g.pend = cur
  local spare = g.spare
  g.spare = nil
  g.cur = fillCycle(g, spare or newCycle(), t)
end

function G.New(opts)
  local h = opts.h or {}
  local g = {
    model = opts.model, h = opts.h, notation = opts.notation or "1:1",
    clipMin = opts.clipMin or 0.03, reaction = opts.reaction or 0.15,
    oppMin = opts.oppMin or 0.4, rearmMin = opts.rearmMin or 0.05, legMax = opts.legMax or 0.4,
    legsSeed = opts.legsSeed or 0.7,
    meleeCycle = opts.meleeCycle or ((h.mws or 3.7) / (h.meleeMul or 1)),
    verdicts = {}, lastVerdict = nil,
    -- The oracle (Nock.state.sim.plan, by reference; Modules/Practice.lua sets
    -- it) and the notes played early on its word, by key (planPrePlay).
    plan = nil, prePlayed = {},
    -- PracticeTimeline, for the shared note keys. `false` means "looked for it
    -- and it is not here"; nil means "not looked yet" (see `timeline`).
    timeline = opts.timeline,
    t0 = nil, tEnd = nil,
    -- Per-note judgments: the running streak, the best one, one counter per
    -- grade, and the cycles that came out exactly on paper.
    streak = 0, bestStreak = 0,
    judge = { perfect = 0, good = 0, late = 0, clip = 0, missed = 0, off = 0 },
    -- cyclesOk/cyclesTotal are the LIVE approximation (see G.Live): they count
    -- a cycle by its symbols, not by their order. The scorecard's own figure is
    -- rebuilt from T.Cycles at the stop.
    cyclesOk = 0, cyclesTotal = 0, cycleIx = 0,
    cur = nil, pend = nil, spare = nil, lay = nil,
    -- THE MATCH MAP: the play's own EVENT -> the index of the cycle whose NOTE
    -- it took. One number per matched press, written where the match is made
    -- and read once per fight by T.Cycles (G.Finish hands it over on the
    -- scorecard), so the row, the report and the replay file that press exactly
    -- where the judgment did. Unmatched plays never appear in it and keep
    -- filing by the clock. See matchNote.
    --
    -- KEYED BY THE EVENT TABLE, not by the moment. Two plays really do share a
    -- moment — a paper that writes a weave and a cast on the same beat lands
    -- the melee hit and the cast's press on the same float (5:5:1:1 3w at eWS
    -- 1.65 does it twice a period) — and a time key let one silently overwrite
    -- the other: the row lost the weave and gained it in the next cycle, two
    -- red cells under 28 PERFECT pops. An event table is the play itself, and
    -- there is exactly one of it.
    matchCycle = {},
    lastCastV = nil, lastCastMatched = false,   -- the cast a clip would belong to
    lastCastRec = nil, lastCastIdx = nil,       -- ...and the note record it took
    lastMeleeT = nil,                           -- the last melee hit: the swing recharges from it
    autos = 0, gcds = 0, clips = 0, clipMs = 0, early = 0, lateMs = 0,
    weavesTaken = 0, weavesMissed = 0, rearmMs = 0, meleeHits = 0,
    oppT = nil, oppHadDown = false,     -- open opportunity window, and whether it saw a weave-down
    holdOpen = false,                   -- currently inside a weave hold (down..up)
    holdRearmed = false,                -- this hold's release cost a RE-ARM verdict (no checkmark for it)
    -- Preallocated leg stores, filled by index as weaves complete (nLegs is the count).
    legIn = {}, legDwell = {}, legOut = {}, legTot = {}, legBudgetOk = {}, backIn = {}, backOut = {}, nLegs = 0,
    ring = {}, ringN = 0, RING = 8,     -- ring buffer of the last RING completed weaves' totals
    freeT = nil,        -- time the player became free (pending LATE check)
    freeCtx = nil,      -- the engine's own ctx table for that free moment (no copy)
    freeDeferred = false,
    freeTtw = nil,      -- overrides freeCtx.ttw once a deferred free resolves at the shot
    pendCode = nil, pendText = nil, pendKey = nil, pendExtra = nil,  -- deferred decision for the queued press
    -- Haste windows: one per haste state, plus the opener/cooldown/KC ledgers.
    windows = {}, win = nil, kcWindows = 0, kcUsed = 0, cdsUsed = {},
    anchorT = nil, firstAutoT = nil, firstSteadyT = nil, multiT = nil, gcdN = 0,
    -- The first press of a SHOT (steady/multi/arcane), whatever came of it.
    -- The opener's Steady window is measured from here, not from the pull: see
    -- G.Finish.
    firstShotPressT = nil,
    lastWontFit = nil,  -- the STEADY WON'T FIT still waiting for the clip it caused
  }
  g.notationFor = opts.notationFor or function() return g.notation end
  g.opener = opts.opener or { anchor = "pull", gcds = 2, steadySec = 0.5, cds = {} }
  return g
end

-- THE PAPER IS THE SCOPE, again (D1's ruling (b), applied to the SHOT half).
-- `fits`/`firstFit` ask what could have gone out in the gap the player left,
-- and they used to ask the ENGINE alone: Multi off cooldown, Arcane off
-- cooldown. On a `1:1` drill that is a rotation the paper has no slot for, so a
-- 1:1 fight faulted a LATE every cycle for the Multi it "should" have squeezed
-- in. `syms` is the window's own symbol set (G.PaperSyms); nil means no paper
-- at all, and then everything the engine allows still counts.
local function paperHas(syms, sym)
  if not syms then return true end
  return syms[sym] and true or false
end

-- ttwOverride, when present, means the wind-up has resolved (the shot fired):
-- treat the moment as no longer inside the wind-up regardless of ctx.inWindup.
local function fits(ctx, ttwOverride, syms)
  local inWindup = ctx.inWindup and not ttwOverride
  local ttw = ttwOverride or ctx.ttw
  if inWindup then return true end              -- a queued press is never late
  if paperHas(syms, "s") and ctx.steadyCast <= ttw then return true end
  if paperHas(syms, "m") and ctx.msReady and ctx.multiCast <= ttw then return true end
  if paperHas(syms, "A") and ctx.arcReady then return true end
  return false
end

-- The first shot that fits, in the order `fits` tests them. Returns name, sym,
-- duration — or nil when only the wind-up made the moment "fit".
local ARCANE_DUR = 0.15
local function firstFit(ctx, ttwOverride, syms)
  local ttw = ttwOverride or ctx.ttw
  if paperHas(syms, "s") and ctx.steadyCast <= ttw then return "Steady Shot", "s", ctx.steadyCast end
  if paperHas(syms, "m") and ctx.msReady and ctx.multiCast <= ttw then return "Multi-Shot", "m", ctx.multiCast end
  if paperHas(syms, "A") and ctx.arcReady then return "Arcane Shot", "A", ARCANE_DUR end
  return nil
end

-- The decision a press represents, judged from the numbers the player had.
-- Returns code, text, extra. Pure of side effects.
local function decide(g, ev)
  local c = ev.ctx
  -- The paper decides which alternatives exist at all: a drill whose notation
  -- never writes an `m` has no catch-up Multi to miss, and being told about one
  -- is the same nag D1 took off the weave lane.
  local syms = G.PaperSyms(g)
  local msPaper  = paperHas(syms, "m") and c.msReady
  local arcPaper = paperHas(syms, "A") and c.arcReady
  if ev.key == "steady" and not c.inWindup then
    if c.steadyCast > c.ttw and (msPaper or arcPaper) then
      local expected, ghost
      if msPaper and c.multiCast <= c.ttw then
        expected = ("Multi-Shot (%.1f s) fits — Steady after the auto"):format(c.multiCast)
        ghost = { lane = "cast", sym = "m", t0 = ev.t, t1 = ev.t + c.multiCast }
      elseif arcPaper then
        expected = "Arcane Shot (instant) — Steady after the auto"
        ghost = { lane = "cast", sym = "A", t0 = ev.t, t1 = ev.t + ARCANE_DUR }
      else
        expected = "wait for the auto, then Steady"    -- nothing fits: no ghost
      end
      return "STEADY_WONT_FIT", "STEADY WON'T FIT", {
        did = ("Steady Shot (%.1f s) with %.1f s to the wind-up"):format(c.steadyCast, c.ttw),
        expected = expected, ghost = ghost,
        cost = "clip pending",                         -- replaced by the clip that follows
      }
    end
    -- wowsims catch-up rule: the gap left in the next cycle after this Steady.
    local gap = (c.ttw - c.steadyCast) + c.cycle - g.model.GCD
    if msPaper and gap > 0.1 and gap < c.multiCast then
      return "CATCHUP_MISSED", "CATCH-UP MULTI MISSED", {
        did = "Steady Shot; a catch-up Multi fit",
        expected = "Multi-Shot now, Steady next cycle",
        ghost = { lane = "cast", sym = "m", t0 = ev.t, t1 = ev.t + c.multiCast },
        cost = "-1 Multi this cycle",
      }
    end
  end
  return "GOOD", "GOOD"
end

local function gradePress(g, ev)
  local r = ev.result
  if r == "notready" then
    -- `mash` means the press was of the very spell that started the running
    -- GCD — the player is holding one key down, which is how the client is
    -- meant to be played. Only a DIFFERENT key pressed too early is a fumble.
    if not ev.mash then g.early = g.early + 1 end   -- a fumble, not a verdict
    return
  end
  if r == "replaced" then
    g.pendCode, g.pendExtra = nil, nil         -- the queued press never fires
    return
  end
  if r ~= "ok" and r ~= "queued" then return end  -- moving/cooldown: silent

  if ev.queuedFrom then
    -- The queued press fires now: emit the decision made at press time.
    if g.pendCode then
      local v = verdict(g, ev.t, g.pendCode, 0, g.pendText, g.pendKey, g.pendExtra)
      if g.pendCode == "STEADY_WONT_FIT" then closeWontFit(g); g.lastWontFit = v end
      g.pendCode, g.pendExtra = nil, nil
    end
    return
  end

  -- LATE: gap between becoming free and this (real) press, when something fit.
  if g.freeT and not g.freeDeferred then
    local freeT = g.freeT
    local gap = ev.t - freeT
    local syms = G.PaperSyms(g)
    local fitsFree = fits(g.freeCtx, g.freeTtw, syms)
    g.freeT = nil
    -- ...unless THE PLAN asked for the wait: an idle GCD is only LATE when the
    -- oracle had a press due (g.askedAt, the plan's next-note time as it stood
    -- before this press; Modules/Practice.lua). The plan holds a cast to the
    -- release when pulling an instant forward would cost the next Steady, and
    -- this rule -- press-local, "an Arcane fit" -- faulted exactly that wait.
    local asked = g.askedAt
    local waited = asked ~= nil and asked > freeT + g.reaction
    if gap > g.reaction and fitsFree and not waited then
      local ms = math.floor(gap * 1000 + 0.5)
      g.lateMs = g.lateMs + ms
      local name, sym, dur = firstFit(g.freeCtx, g.freeTtw, syms)
      verdict(g, ev.t, "LATE", ms, ("LATE +%d ms"):format(ms), ev.key, {
        did = ("GCD free for %d ms"):format(ms),
        expected = name and ("%s at %s (it fit)"):format(name, relSec(g, freeT)) or nil,
        ghost = name and { lane = "cast", sym = sym, t0 = freeT, t1 = freeT + dur } or nil,
        cost = ("+%d ms idle"):format(ms),
      })
      return
    end
  end

  -- A press made on the plan's word (within a reaction of the moment the
  -- oracle asked for it) is the plan's decision: it is not second-guessed by
  -- the press-local rules below (STEADY WON'T FIT, CATCH-UP), which know the
  -- room to the wind-up but not the paper's budget or the cost of idling.
  local code, text, extra
  if g.askedAt and ev.t >= g.askedAt - g.reaction and ev.t <= g.askedAt + g.reaction then
    code, text = "GOOD", "GOOD"
  else
    code, text, extra = decide(g, ev)
  end
  if r == "queued" then
    g.pendCode, g.pendText, g.pendKey, g.pendExtra = code, text, ev.key, extra  -- emitted on the fire
  else
    local v = verdict(g, ev.t, code, 0, text, ev.key, extra)
    if code == "STEADY_WONT_FIT" then closeWontFit(g); g.lastWontFit = v end
  end
end

function G.Feed(g, ev)
  local k = ev.kind
  -- The closed cycle waiting on its grace is swept as soon as the clock says
  -- nothing can still play its notes. A cast event is safe to test by its END:
  -- the grace IS a steady cast, the longest there is, so any cast that started
  -- inside that cycle arrives before the deadline. (The cast branch sweeps on
  -- the tighter start-time rule as well.)
  if g.pend then sweepDue(g, ev.t or ev.t0, false) end
  if k == "pull" then
    g.t0 = ev.t
    openWindow(g, ev.t, g.h.rangedMul, { qs = false, rf = false, lust = false, drums = false })
    g.anchorT = (g.opener.anchor == "pull") and ev.t or nil
  elseif k == "stop" then
    -- A scheduled `end` already closed the fight; the `stop` that follows it a
    -- frame later is the teardown, not a longer fight. First close wins.
    if not g.tEnd then
      g.tEnd = ev.t
      if g.win then g.win.t1 = ev.t end
    end
  elseif k == "end" then
    g.tEnd = ev.t
    if g.win then g.win.t1 = ev.t end
  elseif k == "haste" then
    openWindow(g, ev.t, ev.rangedMul, { qs = ev.qs, rf = ev.rf, lust = ev.lust, drums = ev.drums })
  elseif k == "proc" then
    if ev.on then
      local a = g.opener.anchor
      if not g.anchorT and ((a == "lust" and ev.name == "Lust") or (a == "drums" and ev.name == "Drums")
          or (a == "pot" and ev.name == "Pot") or (a == "rf" and ev.name == "RF")) then
        g.anchorT = ev.t
      end
    end
  elseif k == "cd" then
    if ev.used then
      local a = g.opener.anchor
      if not g.anchorT and ((a == "drums" and ev.key == "Drums") or (a == "pot" and ev.key == "Pot")
          or (a == "rf" and ev.key == "RF")) then
        g.anchorT = ev.t   -- the anchor IS this press
      end
      if not g.cdsUsed[ev.key] then
        g.cdsUsed[ev.key] = ev.t
        if g.opener.cds[ev.key] and not g.anchorT then
          verdict(g, ev.t, "EARLY", 0, ("EARLY %s — before %s"):format(ev.key, a), "cd", {
            did = ("%s before %s"):format(ev.key, a),
            expected = ("%s within %d GCDs after %s"):format(ev.key, g.opener.gcds, a),
            cost = "cooldown outside the haste window",
          })
        end
      end
    end
  elseif k == "kcwin" then
    g.kcWindows = g.kcWindows + 1
  elseif k == "kc" then
    g.kcUsed = g.kcUsed + 1
  elseif k == "auto" then
    g.autos = g.autos + 1
    g.firstAutoT = g.firstAutoT or ev.t
    if g.win then g.win.autos = g.win.autos + 1 end
    if g.freeDeferred then
      -- The honest clock starts at the shot: the wind-up has resolved.
      g.freeT = ev.t
      g.freeTtw = g.freeCtx.cycle - 0.5 / g.h.rangedMul
      g.freeDeferred = false
    end
    local clipMs = nil
    -- ONLY THE EXCESS OVER THE PAPER'S OWN BUDGET IS THE PLAYER'S. A clip the
    -- layout schedules for this cycle position is the rotation working as
    -- written (see `releases`), so it earns no fault and no CLIP judgment — the
    -- cast that "caused" it keeps its PERFECT/GOOD. The auto's own `+N ms` tag
    -- on the timeline stays either way: the shot really did go out that late.
    local budget = paperDelay(g)
    local excess = (ev.delay or 0) - budget
    -- The floor: `clipMin` for a paper that budgets nothing (a 1:1 cycle has no
    -- scheduled overlap at all), the modelling slack once there is a budget to
    -- drift against.
    local tol = g.clipMin
    if budget > 0 and PAPER_DELAY_EPS > tol then tol = PAPER_DELAY_EPS end
    -- ...AND A CLIP THE PLAN CHOSE IS THE PLAN'S (policy 2, 2026-08-25). When
    -- the cast behind this auto was pressed on the oracle's word (matched to a
    -- note at the plan's time, PERFECT or GOOD), the overrun was the plan's
    -- own call -- clipping once to re-phase the grid beats idling a GCD every
    -- cycle -- so it earns no fault and no CLIP judgment; it is counted apart
    -- (clipsPlanned / clipPlannedMs) so the report can still say it happened.
    local planned = false
    if g.plan and g.lastCastMatched and g.lastCastV
       and (g.lastCastV.grade == "PERFECT" or g.lastCastV.grade == "GOOD") then
      planned = true
    end
    -- The auto event carries the verdict for the stage: "fault" paints it
    -- red; "planned" (the plan's own call: a Steady queued into the wind-up
    -- and the auto straight behind it) and the paper's budgeted overrun do
    -- not -- every delayed auto used to be red (user, 2026-08-25).
    if excess > tol and ev.cause == "cast" and planned then
      local ms = math.floor(excess * 1000 + 0.5)
      g.clipsPlanned = (g.clipsPlanned or 0) + 1
      g.clipPlannedMs = (g.clipPlannedMs or 0) + ms
      ev.clip = "planned"
      closeWontFit(g)
    elseif excess > tol and ev.cause == "cast" then
      local ms = math.floor(excess * 1000 + 0.5)
      clipMs = ms
      ev.clip = "fault"
      g.clips = g.clips + 1
      g.clipMs = g.clipMs + ms
      if g.win then g.win.clips = g.win.clips + 1 end
      local v = verdict(g, ev.t, "CLIP", ms, ("CLIP +%d ms"):format(ms), "auto", {
        did = ("auto released %d ms late behind the cast"):format(ms),
        expected = ("the wind-up at %s"):format(relSec(g, ev.t - excess - 0.5 / g.h.rangedMul)),
        cost = ("+%d ms auto"):format(ms),
      })
      -- The decision that caused this clip owns its cost: the analysis then
      -- ranks the cause, not the symptom, and the ms is counted once.
      if g.lastWontFit then
        g.lastWontFit.cost = ("+%d ms auto"):format(ms)
        g.lastWontFit.ms = ms
        v.attributed = true
        g.lastWontFit = nil
      end
    else
      closeWontFit(g)   -- the shot went out clean: the prediction cost nothing
    end
    -- The shot is out, so the cast behind it now knows whether it clipped — a
    -- second judgment on that note, here, where the clip actually happened.
    -- After it, no earlier cast can clip anything.
    if clipMs then clipJudge(g, ev.t, clipMs) end
    g.lastCastV, g.lastCastMatched, g.lastCastRec, g.lastCastIdx = nil, false, nil, nil
    onRelease(g, ev.t)
  elseif k == "cast" then
    if not ev.cancelled then
      g.gcds = g.gcds + 1
      g.gcdN = g.gcds
      local sym = SYM[ev.spell]
      if ev.spell == "steady" then g.firstSteadyT = g.firstSteadyT or ev.t0 end
      if ev.spell == "multi" and not g.multiT then g.multiT = ev.t0 end
      local w = g.win
      if w then
        w.gcds = w.gcds + 1
        if sym and w[sym] then w[sym] = w[sym] + 1 end
      end
      -- The note is matched from the cast's START (ev.t0) — the moment the
      -- player pressed it — while the judgment is pushed now, at the event.
      -- A cast that started at or after the previous cycle's end also proves
      -- nothing of that cycle is still in flight: sweep it first, so its MISSED
      -- reaches the stream ahead of this cycle's grade.
      if sym then
        -- By the PRESS, not the cast's start: a press queued inside the
        -- wind-up starts its cast exactly at the release, which read as "a
        -- cast of the next cycle, sweep the old one" -- the note it was
        -- pressed for went MISSED and the cast took the next cycle's, LATE
        -- (gate, 2026-08-26).
        local pressT = ev.queuedFrom or ev.t0
        if ev.queuedFrom then g.queuedPress = nil end
        sweepDue(g, pressT, true, ev.t)
        -- (The cycle is the cast's, as before -- a queued press starts its
        -- cast at the release that opens the next cycle, whose note it took
        -- in the paper's own terms; the nearer note by the plan's time wins
        -- across the two cycles either way. Only the sweep is by the press.)
        local c, i, d, preKey, preT0, preSym, preCycle = matchNote(g, ev.t0, sym)
        if c then
          g.lastCastMatched = (i ~= nil) or (preKey ~= nil)
          -- THE QUEUE WINDOW IS FREE — SO GRADE THE PRESS, NOT THE START.
          -- `queuedFrom` means the player pressed inside the wind-up (or inside
          -- the client's queue window) and the CLIENT chose where the cast
          -- began: at the top of the next cycle, or the instant the GCD let go.
          -- Grading that start on the clock grades the client — at GCD-bound
          -- haste (1:1 at eWS 1.34, where the 1.5 s GCD outruns the 1.34 s
          -- swing) the same on-beat press walked PERFECT -> GOOD -> LATE ->
          -- MISSED and back round.
          --
          -- But "free" is about WHO started it, not about how far it drifted:
          -- the ruling is that a queued press which starts ON THE BEAT is
          -- PERFECT, and a press is on the beat when the FINGER was. So the
          -- delta a queued cast is graded on is the press against the note,
          -- while `deltaMs` keeps reporting the honest start-to-note distance.
          -- A 350 ms fumble that happens to queue off an earlier GCD is still
          -- 350 ms late; only the client's own hold is forgiven.
          local grade, dJudge = "OFF", d
          if i then
            if ev.queuedFrom then dJudge = ev.queuedFrom - planTime(g, c.nKey[i], c.nT0[i]) end
            grade = gradeFor(dJudge)
            g.matchCycle[ev] = c.ix          -- the note's cycle owns this press
          elseif preKey then
            -- A note of a cycle not seated yet, played early on the plan's
            -- word (planPrePlay): graded against the plan's time, and its grade
            -- kept by key for the cycle that will seat it.
            if ev.queuedFrom then dJudge = ev.queuedFrom - preT0 end
            grade = gradeFor(dJudge)
            g.prePlayed[preKey] = grade
            if preCycle then g.matchCycle[ev] = preCycle end   -- filed in the note's own cycle
          end
          g.lastCastRec, g.lastCastIdx = i and c or nil, i
          local matched = (i ~= nil) or (preKey ~= nil)
          g.lastCastV = pushJudge(g, ev.t, grade,
                                  matched and math.floor(d * 1000 + 0.5) or nil, c.ix,
                                  i and c.nT0[i] or preT0 or ev.t0, i and c.nSym[i] or preSym or sym,
                                  i and c.nKey[i] or preKey, i and c or nil, i)
        else
          g.lastCastV, g.lastCastMatched, g.lastCastRec, g.lastCastIdx = nil, false, nil, nil
        end
      end
    end
  elseif k == "free" then
    g.freeT = ev.t
    g.freeCtx = ev.ctx
    g.freeTtw = nil
    -- Free inside the wind-up: defer until the shot resolves it (see "auto" above).
    g.freeDeferred = ev.ctx.inWindup and true or false
  elseif k == "press" then
    -- A press the client is HOLDING (queued inside the wind-up): its cast
    -- starts at the release, after the sweep that release runs, so the note
    -- it was pressed for must not be swept meanwhile (carryOver).
    if ev.result == "queued" and SYM[ev.key] then g.queuedPress = { sym = SYM[ev.key], t = ev.t }
    elseif ev.result == "replaced" then g.queuedPress = nil end
    -- Every press of a shot counts here, whatever the engine made of it
    -- (queued, moving, not ready): it is the moment the player asked for the
    -- opener's first shot, which is what the Steady window is measured from.
    if SYM[ev.key] and not g.firstShotPressT then g.firstShotPressT = ev.t end
    gradePress(g, ev)
  elseif k == "weave" then
    if ev.edge == "down" then
      g.holdOpen = true
      g.holdRearmed = false
      g.holdDownT = ev.t
      -- The plan's hit this walk was made for, read NOW: by the key-up the
      -- grader's own re-seat (the paper's ideal grid) may have moved the note
      -- 0.2 s off the real release, and the planned re-arm read as a fault
      -- on every weave after the first delayed auto (2026-08-26).
      g.holdNoteT = nil
      if g.plan and g.plan.live then
        local best
        for i = 1, g.plan.n do
          local nt = g.plan.notes[i]
          if nt.sym == "w" and not nt.lost and nt.t0 >= ev.t - 0.3 then
            local d = nt.t0 - ev.t
            if not best or d < best then best = d; g.holdNoteT = nt.t0 end
          end
        end
      end
      if g.oppT then g.oppHadDown = true end
    elseif ev.edge == "up" then
      g.holdOpen = false
      if (ev.cost or 0) > g.rearmMin then
        local ms = math.floor(ev.cost * 1000 + 0.5)
        g.holdRearmed = true
        -- The paper is the scope: with no weave slot on it, the release is
        -- neither faulted nor billed.
        if paperWeaves(g) then
          g.rearmMs = g.rearmMs + ms
          -- THE PAPER'S RE-ARM (weave first, 2026-08-26). When the hit landed
          -- where the plan asked for it, the notch it cost is the paper's own:
          -- `a w s` at eWS 2.174 is 0.65 s of walk + 1.09 s of Steady + 0.36 s
          -- of wind-up against a 2.17 s cycle, and the client's 0.5 s retry
          -- pulse cannot land in the 0.07 s left -- ~0.2 s an auto whichever
          -- way the key-up is timed. Billed and shown (the log's re-arm
          -- column), counted apart (rearmPlanned), no fault -- the same rule
          -- as a clip the plan chose. A hit off the plan's note keeps the fault.
          local planned = false
          if g.holdNoteT and g.lastMeleeT and g.holdDownT and g.lastMeleeT >= g.holdDownT
             and math.abs(g.lastMeleeT - g.holdNoteT) <= g.reaction + 0.1 then
            planned = true
          end
          if planned then
            g.rearmPlanned = (g.rearmPlanned or 0) + 1
            g.rearmPlannedMs = (g.rearmPlannedMs or 0) + ms
            verdict(g, ev.t, "REARM_PLANNED", ms, ("RE-ARM +%d ms (the paper's)"):format(ms), "weave", {
              did = ("released on the plan's hit; the swing was still recharging (+%d ms)"):format(ms),
              expected = "nothing else -- this paper's weave cannot land on a free notch",
              cost = ("+%d ms auto"):format(ms),
            })
          else
            verdict(g, ev.t, "REARM", ms, ("RE-ARM +%d ms"):format(ms), "weave", {
              did = ("released with the swing still recharging (+%d ms)"):format(ms),
              expected = "release when the auto bar is full (or at the next retry notch)",
              cost = ("+%d ms auto"):format(ms),
            })
          end
        end
      end
    elseif ev.edge == "done" then
      local L = ev.legs
      if L.hit then
        -- The legs themselves are measured whatever the paper says: they feed
        -- G.LegsNeeded, which is what sizes the engine's opportunity windows.
        -- Only the COUNTER and the verdicts below are the paper's business.
        local onPaper = paperWeaves(g)
        if onPaper then g.weavesTaken = g.weavesTaken + 1 end
        g.nLegs = g.nLegs + 1
        local n = g.nLegs
        g.legIn[n], g.legDwell[n], g.legOut[n], g.legTot[n] = L.stepIn, L.dwell, L.stepOut, L.total
        g.legBudgetOk[n] = (L.total <= L.budget)   -- math.huge budget (no grid yet) is always met
        g.backIn[n], g.backOut[n] = L.backIn and true or false, L.backOut and true or false
        g.ringN = g.ringN + 1
        g.ring[(g.ringN - 1) % g.RING + 1] = L.total
        local slow, over, slowVal, slowMax = nil, 0, nil, nil
        if L.stepIn and L.stepIn > g.legMax then slow, over, slowVal, slowMax = "in", L.stepIn - g.legMax, L.stepIn, g.legMax end
        if L.stepOut and L.stepOut > g.legMax and (L.stepOut - g.legMax) > over then slow, over, slowVal, slowMax = "out", L.stepOut - g.legMax, L.stepOut, g.legMax end
        if L.dwell and L.dwell > g.legMax and (L.dwell - g.legMax) > over then slow, over, slowVal, slowMax = "dwell", L.dwell - g.legMax, L.dwell, g.legMax end
        if L.total > L.budget and (L.total - L.budget) > over then slow, over, slowVal, slowMax = "total", L.total - L.budget, L.total, L.budget end
        if onPaper and slow then
          local ms = math.floor(over * 1000 + 0.5)
          verdict(g, ev.t, "WEAVE_SLOW", ms, ("WEAVE SLOW — %s +%.1f s"):format(slow, over), "weave", {
            did = ("%s leg %.1f s"):format(slow, slowVal),
            expected = ("under %.1f s"):format(slowMax),
            cost = ("+%d ms"):format(ms),
          })
        elseif onPaper and not g.holdRearmed then
          -- "OK", not a check mark: this text is drawn in the user's chosen
          -- LibSharedMedia font, and most of them (Numen among them) have no
          -- U+2713 — the review painted an empty box. ASCII always renders.
          verdict(g, ev.t, "WEAVE_OK", 0, ("WEAVE OK in %.1f \194\183 out %.1f"):format(L.stepIn or 0, L.stepOut or 0), "weave")
        end
      end
    end
  elseif k == "melee" then
    g.meleeHits = g.meleeHits + 1
    g.lastMeleeT = ev.t
    -- THE SWING IS KNOWN NOW. A seated weave note ahead of this hit was
    -- chained off the NOTE this hit took; the swing actually returns from the
    -- HIT. Ten milliseconds late and the next note sat ten milliseconds before
    -- the swing -- unplayable, NEXT hopped two seconds on, then hopped back
    -- when its cycle re-seated off the real hit (plan trace, 2026-08-24). So
    -- the seated notes follow the engine's swing the moment it is known.
    if g.meleeCycle > 0 then
      local readyAt = ev.t + g.meleeCycle
      local cycle, windup = G.RangedGrid(g)
      local legs = G.LegsNeeded(g)
      local stepIn = G.StepIn(g)
      if g.cur then
        G.RetimeWeaves(g.cur, readyAt, ev.t)
        G.FitWeaves(g.cur, g.cur.t0, cycle, windup, legs, ev.t, stepIn)
      end
      if g.pend then
        G.RetimeWeaves(g.pend, readyAt, ev.t)
        G.FitWeaves(g.pend, g.pend.t0, cycle, windup, legs, ev.t, stepIn)
      end
    end
    if g.win then g.win.w = g.win.w + 1 end
    -- A melee hit is judged where it lands: nothing about it can clip a shot,
    -- so it never waits on the next auto the way a cast does.
    local c, i, d = matchNote(g, ev.t, ev.hit)
    if c then
      if i then
        g.matchCycle[ev] = c.ix            -- the note's cycle owns this hit
        pushJudge(g, ev.t, gradeFor(d), math.floor(d * 1000 + 0.5), c.ix, c.nT0[i], c.nSym[i], c.nKey[i])
      else
        pushJudge(g, ev.t, "OFF", nil, c.ix, ev.t, ev.hit, nil)
      end
    end
  elseif k == "opp" then
    if ev.open then
      g.oppT, g.oppHadDown = ev.t, g.holdOpen
    elseif g.oppT then
      -- The window itself is the engine's business and it keeps opening one.
      -- Missing it is only a fault where the paper asked for the hit.
      if not g.oppHadDown and (ev.t - g.oppT) >= g.oppMin and paperWeaves(g) then
        g.weavesMissed = g.weavesMissed + 1
        verdict(g, ev.t, "WEAVE_MISSED", 0, "WEAVE MISSED", "weave", {
          did = "stayed at range with the melee swing ready",
          expected = ("weave: in, hit, out before %s"):format(relSec(g, ev.t)),
          ghost = { lane = "melee", sym = "r", t0 = g.oppT + 0.3, t1 = g.oppT + 0.45 },
          cost = "-1 melee hit",
        })
      end
      g.oppT = nil
    end
  elseif k == "deadzone" then
    -- Standing in melee still delays the shot — the engine says so and the
    -- clip that follows is graded — but on a paper with no weave slot there is
    -- no weaving to coach, so the dead-zone nag stays quiet.
    if paperWeaves(g) then
      verdict(g, ev.t, "DEAD_ZONE", 0, "DEAD ZONE — step out", "weave", {
        did = "still in melee when the wind-up wanted to start",
        expected = "be out and shooting by then",
        cost = "auto delayed",
      })
    end
  end
end

-- Seconds a full weave takes this player: mean of the last RING completed
-- weaves, or the seed. The glue feeds it back to the engine's opportunity
-- windows (E.SetLegsNeeded) so WEAVE MISSED is honest about real footwork.
-- How long this player takes to STEP IN -- the mean of the measured step-in
-- legs, or the seed's own share of a whole weave before any weave has been
-- made. The plan's "move in" lead (Core/PracticePlan.lua): GO means start
-- walking now so the hit lands on the note.
G.STEP_IN_SEED = 0.35
function G.StepIn(g)
  local n = g.nLegs or 0
  if n == 0 then return G.STEP_IN_SEED end
  local sum, cnt = 0, 0
  local from = (n > g.RING) and (n - g.RING + 1) or 1
  for i = from, n do
    local v = g.legIn[i]
    if v and v > 0 then sum, cnt = sum + v, cnt + 1 end
  end
  if cnt == 0 then return G.STEP_IN_SEED end
  return sum / cnt
end

function G.LegsNeeded(g)
  if g.ringN == 0 then return g.legsSeed end
  local n = (g.ringN < g.RING) and g.ringN or g.RING
  local s = 0
  for i = 1, n do s = s + g.ring[i] end
  return s / n
end

-- Live numbers for the panel: counters only (no paper layout, no allocation).
function G.Live(g, now, out)
  -- No `pull` yet (the fight is ARMED): there is no clock to read, so the panel
  -- gets nil rather than a duration measured from an origin that does not exist.
  local ft = g.t0 and (now - g.t0) or nil
  out.fightTime = (ft and ft > 0) and ft or nil
  if not ft or ft <= 0 then ft = 1e-9 end
  local cycle = g.h.ws / g.h.rangedMul
  out.autos, out.gcds = g.autos, g.gcds
  out.autoEff = g.autos * cycle / ft
  out.gcdEff  = g.gcds * g.model.GCD / ft
  out.clips, out.clipMs, out.lateMs, out.early = g.clips, g.clipMs, g.lateMs, g.early
  out.clipsPlanned, out.clipPlannedMs = g.clipsPlanned or 0, g.clipPlannedMs or 0
  out.rearmPlanned, out.rearmPlannedMs = g.rearmPlanned or 0, g.rearmPlannedMs or 0
  out.weavesTaken, out.weavesMissed, out.rearmMs, out.meleeHits = g.weavesTaken, g.weavesMissed, g.rearmMs, g.meleeHits
  out.weaveEff = g.meleeHits * g.meleeCycle / ft
  out.kcWindows, out.kcUsed = g.kcWindows, g.kcUsed
  -- The judgment stream's live numbers. `judge` is handed over by reference on
  -- purpose: it is the grader's own counter table, read and never written by
  -- the views, and copying six fields per tick is six fields per tick.
  out.streak, out.bestStreak, out.judge = g.streak, g.bestStreak, g.judge
  -- APPROX, and named so. The live counter judges a cycle by the symbols it
  -- gained and lost, not by their order — good enough for a header that moves
  -- every two seconds, but not the scorecard's figure (G.Finish rebuilds that
  -- from T.Cycles, which is order-aware).
  out.cyclesOkApprox, out.cyclesTotalApprox = g.cyclesOk, g.cyclesTotal
  out.notation = g.win and g.win.notation or g.notation
  return out
end

-- The haste windows as they stand mid-fight, for the live timeline's paper
-- lane: the open window has no end yet, so it is closed at `now` in place.
-- Allocation-free (the array itself is handed back). The real end still wins:
-- the `stop`/`end` event re-sets t1 before Finish ever reads it.
function G.WindowsSoFar(g, now)
  local w = g.win
  if w then w.t1 = now end
  return g.windows
end

-- Letter grade for the share of CYCLES ON PAPER — the fraction of auto-to-auto
-- cycles in which every note the paper asked for was played and nothing extra
-- was. Pure, and the review window's headline.
--
-- It replaced a damage-vs-paper percentage, which graded a rotation by an
-- estimated number nobody could act on ("102 % of paper" — do what, next time?).
-- A cycle either came out on paper or it did not, and the fix for one that did
-- not is a note you can see.
--
-- Clips are capped separately: three or more of them is a rhythm problem no
-- cycle count should be able to grade above B.
local BANDS = {
  { min = 0.95, letter = "A+" },
  { min = 0.90, letter = "A" },
  { min = 0.85, letter = "B+" },
  { min = 0.75, letter = "B" },
  { min = 0.60, letter = "C" },
}
local CLIP_CAP, CAPPED = 3, { ["A+"] = "B", ["A"] = "B", ["B+"] = "B" }
function G.Grade(pct, clips)
  pct = tonumber(pct) or 0
  local letter = "D"
  for i = 1, #BANDS do
    if pct >= BANDS[i].min then letter = BANDS[i].letter; break end
  end
  if (tonumber(clips) or 0) >= CLIP_CAP then letter = CAPPED[letter] or letter end
  return letter
end

-- End-of-fight fault roll-up: one row per fault code, worst first, capped at
-- the TOP THREE — the review shows three fix cards and a list nobody reads to
-- the end is not a lesson. Each row carries the `cycle` of its first occurrence
-- so the card can replay it. A judgment (kind = "judge") has no `code` and
-- therefore never reaches a row. Pure, and allocation-heavy on purpose — Finish
-- only runs once per fight.
local TOP_FIXES = 3
function G.Analysis(g)
  local byCode, out = {}, {}
  for i = 1, #g.verdicts do
    local v = g.verdicts[i]
    local adv = ADVICE[v.code]
    if adv and not v.attributed then
      local row = byCode[v.code]
      if not row then
        row = { code = v.code, n = 0, ms = 0, advice = adv, cycle = v.cycle }
        byCode[v.code] = row
        out[#out + 1] = row
      end
      row.n = row.n + 1
      row.ms = row.ms + (v.ms or 0)
    end
  end
  table.sort(out, function(a, b)
    if a.ms ~= b.ms then return a.ms > b.ms end
    if a.n ~= b.n then return a.n > b.n end
    return a.code < b.code            -- total order: LuaJIT's sort is unstable
  end)
  for i = #out, TOP_FIXES + 1, -1 do out[i] = nil end
  return out
end

--------------------------------------------------------------------------------
-- THE ONE-SENTENCE READ, for the review's headline. Pure.
--
-- It is keyed on the FAMILY a fight's faults belong to, not on the single worst
-- row: three weave faults of 40 ms each are a weave problem, and a headline that
-- named the 120 ms clip above them would send the player to the wrong drill. The
-- families are summed over G.Analysis' rows (cost first, count as the tiebreak,
-- FAMILY_ORDER last so the answer is total) and the biggest one wins.
--
-- The sentence names the family and one number. It never repeats the headline's
-- own figure (cycles on paper) — that line is right above it.
--------------------------------------------------------------------------------

local FAMILY = {
  CLIP = "clips",
  -- Shot CHOICE and idle GCD: the notes are off the paper, not off the beat.
  STEADY_WONT_FIT = "paper", CATCHUP_MISSED = "paper", LATE = "paper",
  WEAVE_MISSED = "weave", WEAVE_SLOW = "weave", DEAD_ZONE = "weave", REARM = "weave", REARM_PLANNED = "weave",
  EARLY = "opener",
}
local FAMILY_ORDER = { "clips", "weave", "paper", "opener" }
G.SUMMARY_FAMILY = FAMILY
G.SUMMARY = {
  clean  = "No faults - drill passed.",
  clips  = "Your notes are there. The beat is what slips: %d cast%s ran into the wind-up, for %d ms of auto.",
  weave  = "Your beat is solid. The weave is what slips: %d late or missed step-in%s.",
  paper  = "The beat holds. What slips is the note on top of it: %d note%s off the paper.",
  opener = "The fight itself is clean. The opener is what slips: %d cooldown%s fired before the anchor.",
}

local function plural(n) return (n == 1) and "" or "s" end

-- Returns the sentence, the family it was keyed on, and that family's count and
-- cost — the last two so a caller can colour the line without re-deriving them.
function G.Summary(score)
  local a = score and score.analysis
  if not (a and a[1]) then return G.SUMMARY.clean, "clean", 0, 0 end
  local ms, n = {}, {}
  for i = 1, #a do
    local fam = FAMILY[a[i].code]
    if fam then
      ms[fam] = (ms[fam] or 0) + (a[i].ms or 0)
      n[fam] = (n[fam] or 0) + (a[i].n or 0)
    end
  end
  local best, bestMs, bestN = nil, -1, -1
  for i = 1, #FAMILY_ORDER do
    local fam = FAMILY_ORDER[i]
    local fms, fn = ms[fam], n[fam]
    if fn and (fms > bestMs or (fms == bestMs and fn > bestN)) then
      best, bestMs, bestN = fam, fms, fn
    end
  end
  if not best then return G.SUMMARY.clean, "clean", 0, 0 end
  if best == "clips" then
    return G.SUMMARY.clips:format(bestN, plural(bestN), bestMs), best, bestN, bestMs
  end
  return G.SUMMARY[best]:format(bestN, plural(bestN)), best, bestN, bestMs
end

-- Median/worst/count over a preallocated array's first n entries (nil-skipped).
-- Allocation-heavy (a copy + a sort) — fine here, Finish only runs once per fight.
local function stats(arr, n)
  local vals = {}
  for i = 1, n do
    local v = arr[i]
    if v then vals[#vals + 1] = v end
  end
  if #vals == 0 then return { med = 0, worst = 0 } end
  table.sort(vals)
  local nv = #vals
  local med
  if nv % 2 == 1 then
    med = vals[(nv + 1) / 2]
  else
    med = (vals[nv / 2] + vals[nv / 2 + 1]) / 2
  end
  return { med = med, worst = vals[nv] }
end

-- End of fight. A press still sitting in the queue at the stop (g.pendCode)
-- deliberately yields no verdict: its cast never happened, so grading the
-- decision would score a shot the player never took.
--
-- `events`/`n` are the engine's own stream, handed to T.Cycles for the
-- scorecard's cycles-on-paper figure. OMITTING THEM (or having no timeline)
-- falls back to the running counter, which is order-blind: it tallies a cycle's
-- symbols, so a Multi played where the Steady goes still passes it.
function G.Finish(g, events, n)
  -- The ORIGIN, or nothing at all. `g.t0` is written by the `pull` event and by
  -- nothing else, so a stream that never carried one has no zero to count from —
  -- and the old `g.t0 or 0` made every offset below a raw GetTime() reading
  -- (the review's "Steady 305232320.92s"). Every field measured FROM the origin
  -- is nil in that case, and the report and the review draw an em dash.
  local t0 = g.t0
  local t1 = g.tEnd or t0
  local fightTime = (t0 and t1) and (t1 - t0) or nil
  if fightTime and fightTime <= 0 then fightTime = nil end
  -- The efficiency denominator. Rates over an unmeasurable span are not numbers
  -- either: they go out nil beside the clock they were derived from.
  local span = fightTime
  local cycle = g.h.ws / g.h.rangedMul

  -- The judgment stream is closed before anything reads it: the cycle still on
  -- its grace is swept, and the trailing cycle is swept only if it ran long
  -- enough to be judged at all (the same 0.9-of-a-cycle test T.Cycles' `partial`
  -- uses — a fight stopped mid-cycle must not report the rest of that cycle as
  -- missed).
  -- The stop is the sweep moment for whatever is still open at it.
  local sweepT = g.tEnd or (g.cur and g.cur.t1) or (g.cur and g.cur.t0)
  if g.pend then
    local c = g.pend
    g.pend = nil
    sweep(g, c, sweepT)
  end
  local last = g.cur
  if last and not last.closed then
    last.t1 = g.tEnd or last.t1 or last.t0
    local lay = g.lay
    local cycLen = (lay and lay.autos and lay.autos > 0) and (lay.dur / lay.autos)
                   or (g.h.ws / ((g.win and g.win.rangedMul) or g.h.rangedMul or 1))
    last.partial = (cycLen > 0) and ((last.t1 - last.t0) < 0.9 * cycLen) or false
    closeCycle(g, last, sweepT or last.t1)
  end

  -- Per haste window: bounds, efficiencies and the shot mix actually played.
  for i = 1, #g.windows do
    local w = g.windows[i]
    w.t1 = w.t1 or t1 or w.t0
    local len = w.t1 - w.t0
    if len <= 0 then len = 1e-9 end
    w.len = len
    local cyc = g.h.ws / w.rangedMul
    w.autoEff = w.autos * cyc / len
    w.gcdEff  = w.gcds * g.model.GCD / len
    local str = string.rep("a", w.autos) .. string.rep("s", w.s) .. string.rep("m", w.m)
      .. string.rep("A", w.A) .. string.rep("w", w.w)
    w.played = (w.autos + w.gcds > 0) and g.model.Shorthand(str) or "—"
  end

  local op = g.opener
  local gcdWindow = op.gcds * g.model.GCD
  -- Where the opener's Steady window starts. NOT the pull: a hunter who opens
  -- on a start-attack key ("/cast !Auto Shot", "/startattack") makes a real
  -- press — it is what starts the fight — but that press is not a shot, and
  -- measuring the Steady against it failed the opener for the arm-then-cast
  -- opener every single time. The first SHOT press is the honest zero; with a
  -- Steady or Multi pull it IS the pull (one latency later), so nothing about
  -- the shot openers changes.
  --
  -- The COOLDOWN anchor (g.anchorT) deliberately stays on the pull: a trinket
  -- popped together with the start-attack key is on time, and moving that
  -- anchor forward would call it EARLY.
  local openerT = g.firstShotPressT or t0
  local opener = {
    anchor = op.anchor, anchorT = g.anchorT,
    firstAuto = (t0 and g.firstAutoT) and (g.firstAutoT - t0) or nil,
    firstSteady = (t0 and g.firstSteadyT) and (g.firstSteadyT - t0) or nil,
    -- steadyOk / multiOnPull are DIFFERENCES between two measured moments, so
    -- they survive a missing origin as long as the moment they measure against
    -- exists (openerT is the first shot press; multi is judged from the pull).
    steadyOk = g.firstSteadyT ~= nil and openerT ~= nil and (g.firstSteadyT - openerT) <= op.steadySec,
    multiOnPull = g.multiT ~= nil and t0 ~= nil and (g.multiT - t0) <= 3 * g.model.GCD,
    cds = {}, ok = true,
  }
  for key, wanted in pairs(op.cds) do
    if wanted then
      local at = g.cdsUsed[key]
      local okCd = at ~= nil and g.anchorT ~= nil and at >= g.anchorT and (at - g.anchorT) <= gcdWindow
      opener.cds[key] = { t = (t0 and at) and (at - t0) or nil, ok = okCd,
                          early = (at ~= nil and g.anchorT ~= nil and at < g.anchorT) }
      if not okCd then opener.ok = false end
    end
  end
  if not opener.steadyOk then opener.ok = false end

  -- CYCLES ON PAPER, the figure the grade is made of. It is T.Cycles' reading —
  -- the same one the review's rotation row draws — because "on paper" means the
  -- cycle was played in the paper's ORDER, and the running counter the live
  -- header uses only knows the symbols (an m/s swap passes it and must not pass
  -- here). One pure call, once per fight.
  local ok, total = g.cyclesOk, g.cyclesTotal
  local T = timeline(g)
  if T and T.Cycles and events and n and n > 0 then
    g._cycOut = g._cycOut or {}
    g._cycScore = g._cycScore or {}
    g._cycScore.windows = g.windows
    -- The same map the returned scorecard carries, so the figure the GRADE is
    -- built on and the row the review draws are one reading, not two.
    g._cycScore.match = g.matchCycle
    local cyc = T.Cycles(events, n, g._cycScore, g.h, g.model, g._cycOut)
    ok, total = 0, 0
    for i = 1, (cyc.n or 0) do
      local c = cyc[i]
      if not c.partial then
        total = total + 1
        if c.ok then ok = ok + 1 end
      end
    end
  end
  local onPaper = (total > 0) and (ok / total) or 0
  local analysis = G.Analysis(g)
  -- `nLegs`, not `n`: this used to shadow G.Finish's own `n` (the event count).
  local nLegs = g.nLegs
  local okCount, backInCount, backOutCount = 0, 0, 0
  for i = 1, nLegs do
    if g.legBudgetOk[i] then okCount = okCount + 1 end
    if g.backIn[i] then backInCount = backInCount + 1 end
    if g.backOut[i] then backOutCount = backOutCount + 1 end
  end
  -- Did this fight's paper EVER ask for melee? The honest signal for the
  -- review's WEAVES tile: `0/0 windows` also happens to a weave fight that
  -- never got an opening, and those two want different words.
  local paperWeave = false
  if #g.windows > 0 then
    for i = 1, #g.windows do
      local s = G.Syms(g.model, g.windows[i].notation)
      if s.w or s.r then paperWeave = true break end
    end
  else
    local s = G.Syms(g.model, g.notation)
    paperWeave = (s.w or s.r) and true or false
  end
  local legs = {
    stepIn = stats(g.legIn, nLegs), dwell = stats(g.legDwell, nLegs),
    stepOut = stats(g.legOut, nLegs), total = stats(g.legTot, nLegs),
    inBudgetPct = (nLegs > 0) and (okCount / nLegs) or 0,
    backpedalPct = { stepIn = (nLegs > 0) and (backInCount / nLegs) or 0,
                     stepOut = (nLegs > 0) and (backOutCount / nLegs) or 0 },
  }
  return {
    -- The origin itself, so the report's relative stamps come off the fight the
    -- score belongs to rather than off whatever state.sim.t0 happens to hold.
    t0 = t0, tEnd = g.tEnd,
    fightTime = fightTime, autos = g.autos, gcds = g.gcds,
    autoEff = span and (g.autos * cycle / span) or nil,
    gcdEff  = span and (g.gcds * g.model.GCD / span) or nil,
    clips = g.clips, clipMs = g.clipMs, early = g.early, lateMs = g.lateMs,
    -- What the fight is GRADED on: cycles that came out exactly on paper, the
    -- per-note judgment counts, and the best run of them.
    cyclesOnPaper = { ok = ok, total = total },
    -- Which cycle each matched press belongs to (see G.New's matchCycle). Every
    -- consumer of T.Cycles — the review's row, the report line, the fix cards'
    -- replay — reads it off the scorecard it is already holding, which is what
    -- makes them agree with the judgments by construction rather than by care.
    match = g.matchCycle,
    judge = g.judge, streak = g.streak, bestStreak = g.bestStreak,
    grade = G.Grade(onPaper, g.clips),
    weavesTaken = g.weavesTaken, weavesMissed = g.weavesMissed, rearmMs = g.rearmMs, meleeHits = g.meleeHits,
    -- Whether the weave numbers above mean anything at all (see paperWeave).
    paperWeave = paperWeave,
    weaveEff = span and (g.meleeHits * g.meleeCycle / span) or nil,
    legs = legs,
    windows = g.windows,
    kc = { windows = g.kcWindows, used = g.kcUsed },
    opener = opener,
    -- `analysis` is the whole surface: the review draws a card per row and
    -- the report a line per row. `topFix = analysis[1]` was the old single-fix
    -- box's field and has had no consumer since; it is gone rather than left to
    -- rot beside the list it duplicated.
    analysis = analysis,
  }
end

local Nock = rawget(_G, "Nock")
if Nock then Nock.PracticeGrader = G end
return G
