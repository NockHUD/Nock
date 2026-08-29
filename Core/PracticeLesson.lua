-- Core/PracticeLesson.lua
-- Pure builder: a shot string + a haste handle -> the one cycle the lesson draws and the five lines that explain it (no WoW APIs).

local L = {}

--------------------------------------------------------------------------------
-- What this file is for
--
-- The lesson view shows ONE auto-to-auto cycle, twice, with a forecast tail --
-- the smallest unit that still contains everything a weaver has to get right:
-- the release, the cast that fits after it, the room left over, and the wind-up
-- that ends the cycle. Everything drawn and every sentence read comes out of
-- L.Build, which runs when the PLAN changes (a new notation, a new haste) and
-- never per tick: it is the only place in the feature that formats a string.
--
-- The cycle here is the WEAPON cycle (ws / rangedMul), not M.Layout's `dur` --
-- a layout's period is several autos long and carries the modelled delays of a
-- greedy scheduler on top. The bar is the beat, and the beat is one swing.
--------------------------------------------------------------------------------

-- Spell names, in the inline English the rest of the addon uses. The UI
-- overwrites these at enable with Nock.UI.PracticeNameFor(sym) so a non-English
-- client reads its own names; the pure file may not call a WoW API to find out.
L.NAMES = { a = "Auto Shot", s = "Steady Shot", m = "Multi-Shot", A = "Arcane Shot", r = "Raptor Strike" }

-- How late the worked CLIP example starts its Steady, past the deadline. It is
-- the whole point of the example that the number be a round, memorable one --
-- and the push it produces is exactly the same number, which is the lesson.
L.CLIP_LATE = 0.4

-- The narration is always five lines; a step index is a stable handle a fault
-- code can be mapped onto (L.StepFor) and a review can deep-link to.
L.STEPS = 5

-- Fault code -> the narration step that teaches the fix. Anything unlisted
-- lands on step 1: the beat is the thing every other step is built on, so it is
-- the right place to send someone whose problem we cannot name.
--
-- The keys are FAULT codes -- the ones PracticeGrader's ADVICE table names, the
-- only ones that can reach a review's fix card. `OFF` and `MISSED` are per-note
-- JUDGMENT grades, never codes, so entries for them were dead rows; a judgment
-- has no card and asks this map nothing.
L.STEP_FOR = {
  CLIP = 4,
  LATE = 5,
  WEAVE_MISSED = 3, WEAVE_SLOW = 3, DEAD_ZONE = 3, REARM = 3,
}

function L.StepFor(code)
  return (code and L.STEP_FOR[code]) or 1
end

--------------------------------------------------------------------------------
-- Pooled writers. Build is called on a plan change, so an allocation here would
-- be harmless -- but the view holds ONE `out` for the session and rebuilds it
-- whenever the notation or the haste moves, and a table that grows by five
-- entries per rebuild is a leak with a slow fuse. Every list is written in
-- place and its live length kept in an `n` field.
--------------------------------------------------------------------------------

local function seg(out, lane, kind, sym, t0, t1, text)
  local i = out.nSegs + 1
  out.nSegs = i
  local s = out.segs[i]
  if not s then s = {}; out.segs[i] = s end
  s.lane, s.kind, s.sym, s.t0, s.t1, s.text = lane, kind, sym, t0, t1, text
  return s
end

local function callout(out, at, lane, text, hot, kind)
  local i = out.nCallouts + 1
  out.nCallouts = i
  local c = out.callouts[i]
  if not c then c = {}; out.callouts[i] = c end
  c.at, c.lane, c.text, c.hot, c.kind = at, lane, text, hot or false, kind
  return c
end

local function clearRest(out)
  for i = out.nSegs + 1, #out.segs do
    local s = out.segs[i]
    s.lane, s.kind, s.sym, s.t0, s.t1, s.text = nil, nil, nil, nil, nil, nil
  end
  for i = out.nCallouts + 1, #out.callouts do
    local c = out.callouts[i]
    c.at, c.lane, c.text, c.hot = nil, nil, nil, nil
  end
  for i = out.nSteps + 1, #out.steps do out.steps[i] = false end
end

--------------------------------------------------------------------------------
-- The layout's first cycle, and its first weave slot.
--------------------------------------------------------------------------------

-- The release of the layout's first auto: the layout is written with that auto
-- STARTING at 0, and every time this file publishes is measured from the moment
-- the arrow leaves -- which is the moment the player sees and hears.
local function firstRelease(lay)
  local ev = lay.ev
  for i = 1, #ev do
    if ev[i].sym == "a" then return ev[i].t0 + ev[i].dur end
  end
  return 0
end

-- The first `w` slot, expressed against the release of the cycle IT falls in --
-- not against the layout's first release. A weaving layout puts its weaves
-- wherever the melee swing happens to be ready, so the first one is usually two
-- or three autos in; measured from the layout's own origin it would land off
-- the single cycle this view draws. Its offset inside its own cycle is the
-- thing that generalises, and the thing a player can act on.
local function firstWeave(lay)
  local ev = lay.ev
  local rel = nil
  for i = 1, #ev do
    local e = ev[i]
    if e.sym == "a" then
      rel = e.t0 + e.dur
    elseif (e.sym == "w" or e.sym == "r") and rel then
      return e.t0 - rel, e.t0 - rel + e.dur
    end
  end
  return nil
end

-- The first cast that FITS, expressed against the release of the cycle IT falls
-- in -- the same reasoning as firstWeave, and for the same reason. A layout does
-- not have to put a cast in its FIRST cycle at all: `3:7 2w` (awasaawasaas)
-- opens with a bare auto and a weave, so a scan anchored on the layout's own
-- origin finds nothing before the deadline and the lesson drew a SHOTS lane
-- with only a release on it. Returns sym, offset, duration.
local function firstCastAnyCycle(lay, deadline, cycle)
  local ev = lay.ev
  local rel = nil
  for i = 1, #ev do
    local e = ev[i]
    local sym = e.sym
    if sym == "a" then
      rel = e.t0 + e.dur
    elseif (sym == "s" or sym == "m" or sym == "A") and rel then
      local t0 = e.t0 - rel
      if t0 >= -1e-9 and t0 <= deadline + 1e-9 and t0 < cycle then
        return sym, t0, e.dur
      end
    end
  end
  return nil
end

--------------------------------------------------------------------------------
-- L.Build(str, h, model, out)
--
--   str    a shot string (model.STRINGS[notation])
--   h      the model handle: ws, rangedMul, castCorr, mws, meleeMul, ...
--   model  Nock.PracticeModel
--   out    a caller-owned table, reused across rebuilds (optional)
--
-- Returns `out`, filled. See the field list in the header comment above.
--------------------------------------------------------------------------------
function L.Build(str, h, model, out)
  out = out or {}
  out.segs = out.segs or {}
  out.callouts = out.callouts or {}
  out.steps = out.steps or {}
  out.nSegs, out.nCallouts, out.nSteps = 0, 0, 0
  if not (str and h and model) then
    clearRest(out)
    out.cycle, out.windup, out.steadyCast, out.deadline = nil, nil, nil, nil
    out.gap, out.forecast, out.str = nil, nil, nil
    if out.clip then out.clip.t0, out.clip.t1, out.clip.push, out.clip.release = nil, nil, nil, nil end
    out.autos, out.multis, out.weaves = 0, 0, 0
    out.nPSegs, out.periodDur, out.periodText, out.periodRel = 0, nil, nil, nil
    return out
  end

  local N = L.NAMES
  local ab = model.Abilities(h)
  local cycle = ab.a.dur + ab.a.cd          -- ws / rangedMul, the beat
  local windup = ab.a.dur                   -- haste-scaled: 0.5 / rangedMul
  local steadyCast = ab.s.dur               -- 1.5 * castCorr / rangedMul
  -- THE deadline: the last moment a Steady may START and still be out of the
  -- way when the bow begins winding up. Relative to the release, like
  -- everything else here.
  local deadline = cycle - windup - steadyCast

  out.str = str
  out.cycle, out.windup, out.steadyCast, out.deadline = cycle, windup, steadyCast, deadline

  local lay = model.Layout(str, h, 0)
  local rel1 = firstRelease(lay)
  local counts = lay.counts
  local autos, multis = counts.a or 0, counts.m or 0
  -- The Arcane is its own note. Every turret notation that carries a Multi
  -- carries one too (5:5:1:1, 5:6:1:1, 5:9:1:1 -- there is no `m`-without-`A`
  -- string in M.STRINGS), and it behaves differently enough to need its own
  -- sentence: it is instant, so it costs a GCD and nothing else.
  local arcanes = counts.A or 0
  local weaves = (counts.w or 0) + (counts.r or 0)
  out.autos, out.multis, out.arcanes, out.weaves = autos, multis, arcanes, weaves

  ------------------------------------------------------------------------
  -- The LEAD cast: the longest-lived thing the paper asks you to cast, and
  -- therefore the one the deadline sentence is about. It used to be Steady,
  -- full stop -- which was true of every canonical notation and false of half
  -- the Round 5b teaching papers: `drill 1w+A` casts nothing but an Arcane,
  -- and `drill 1w` casts nothing at all. A lesson that quoted a Steady
  -- deadline on a paper with no Steady in it was teaching the wrong cycle.
  ------------------------------------------------------------------------
  local leadSym, leadDur
  if (counts.s or 0) > 0 then leadSym, leadDur = "s", ab.s.dur
  elseif multis > 0 then leadSym, leadDur = "m", ab.m.dur
  elseif arcanes > 0 then leadSym, leadDur = "A", ab.A.dur end
  local leadName = leadSym and (N[leadSym] or leadSym) or nil
  -- The lead's own deadline. `out.deadline` stays the STEADY deadline: it is
  -- what the worked clip below is measured from, and the clip lane teaches the
  -- rule with the longest cast there is whether or not this paper carries one.
  local leadDeadline = leadDur and (cycle - windup - leadDur) or nil
  out.leadSym = leadSym

  ------------------------------------------------------------------------
  -- The weave gap.
  ------------------------------------------------------------------------
  local gt0, gt1 = nil, nil
  if weaves > 0 then gt0, gt1 = firstWeave(lay) end
  -- The table is kept on `out` even for a turret and only the PUBLIC `gap`
  -- field is cleared: a view swapping between a weaving and a turret drill --
  -- every second click of the ladder -- would otherwise churn a table per swap
  -- for the whole session.
  local g = out._gap
  if not g then g = {}; out._gap = g end
  if gt0 then
    g.t0, g.t1 = gt0, gt1
    out.gap = g
  else
    g.t0, g.t1 = nil, nil
    out.gap = nil
  end

  ------------------------------------------------------------------------
  -- The worked clip: a Steady started CLIP_LATE past the deadline still fits
  -- its whole cast in, but the wind-up cannot start until it ends -- so the
  -- release slides by exactly the amount the press was late.
  ------------------------------------------------------------------------
  local clip = out.clip
  if not clip then clip = {}; out.clip = clip end
  clip.t0 = deadline + L.CLIP_LATE
  clip.t1 = clip.t0 + steadyCast
  clip.push = L.CLIP_LATE
  clip.release = cycle + L.CLIP_LATE

  ------------------------------------------------------------------------
  -- Segments, one cycle's worth, relative to the release.
  --
  -- The casts are the layout's own, taken from the first cycle and kept only
  -- while they START at or before the deadline. That is not a cosmetic filter:
  -- a cast beginning after it runs into the wind-up, which is the clip the
  -- CLIP lane below draws. The clean cycle is the cycle without one.
  ------------------------------------------------------------------------
  seg(out, "shots", "release", "a", 0, 0)
  local ev = lay.ev
  local firstCast = nil
  for i = 1, #ev do
    local e = ev[i]
    local sym = e.sym
    if sym == "s" or sym == "m" or sym == "A" then
      local t0 = e.t0 - rel1
      if t0 >= -1e-9 and t0 <= deadline + 1e-9 and t0 < cycle then
        local name = N[sym] or sym
        local s = seg(out, "shots", "cast", sym, t0, t0 + e.dur,
                      ("%s %.2f"):format(name, e.dur))
        if not firstCast then firstCast = s end
      end
    end
  end
  -- Nothing in the FIRST cycle: fall back to the first cast that fits in any
  -- cycle, drawn at its offset inside that cycle. One cycle is one cycle
  -- wherever the layout keeps it, and a lesson whose SHOTS lane holds only the
  -- release teaches nothing.
  if not firstCast then
    local sym, t0, dur = firstCastAnyCycle(lay, deadline, cycle)
    if sym then
      firstCast = seg(out, "shots", "cast", sym, t0, t0 + dur,
                      ("%s %.2f"):format(N[sym] or sym, dur))
    end
  end
  seg(out, "shots", "windup", "a", cycle - windup, cycle, "wind-up")
  if gt0 then seg(out, "weave", "gap", "w", gt0, gt1, "gap") end
  seg(out, "clip", "clip", "s", clip.t0, clip.t1,
      ("late %s -> +%.1f s"):format(N.s or "Steady", L.CLIP_LATE))

  -- The dashed tail: the third cycle's first cast, so the bar ends on "and
  -- again" rather than on an edge. A cycle with nothing in it before the
  -- deadline (there is no such notation today, but a hand-written string could
  -- do it) simply has no tail.
  if firstCast then
    local fc = out.forecast
    if not fc then fc = {}; out.forecast = fc end
    fc.sym, fc.t0, fc.t1 = firstCast.sym, firstCast.t0, firstCast.t1
  else
    out.forecast = nil
  end

  ------------------------------------------------------------------------
  -- Callouts, in the order the spec names them (the view places them by `at`,
  -- so the order here is only the order they are numbered in).
  ------------------------------------------------------------------------
  callout(out, 0, "top", "auto release - the clock ticks", false, "release")
  callout(out, cycle - windup, "top",
          ("wind-up starts at %.1f s - a cast still running here clips"):format(cycle - windup), true, "windup")
  if leadSym then
    callout(out, leadDeadline, "bot",
            ("%s %.2f s - must START before %.1f s"):format(leadName, leadDur, leadDeadline), false, "lead")
  end
  if gt0 then
    callout(out, gt0, "bot",
            ("weave gap %.1f s - step in, %s, step out"):format(gt1 - gt0, N.r or "Raptor Strike"), true, "gap")
  end
  callout(out, cycle, "top", "next release", false, "next")

  ------------------------------------------------------------------------
  -- Narration. Five lines, always -- step 3 is the one that changes family.
  ------------------------------------------------------------------------
  local steps = out.steps
  steps[1] = ("Your bow fires every %.2f s. That release is the beat - nothing you press moves it, except a clip."):format(cycle)
  if leadSym then
    steps[2] = ("%s takes %.2f s. Start it right after the release and it is done with %.1f s to spare."):format(
      leadName, leadDur, leadDeadline)
  else
    -- A castless weave paper (`drill 1w`): the whole cycle is footwork, and
    -- saying so is the lesson rather than a hole in it.
    steps[2] = ("There is nothing to cast in this cycle. All %.2f s between the releases belong to your feet."):format(cycle)
  end
  if gt0 then
    steps[3] = ("That spare time is the weave gap: step in, %s lands, step out. The swing timer must be ready."):format(N.r or "Raptor Strike")
  elseif multis > 0 or arcanes > 0 then
    -- A turret rotation has no weave to spend the room on; what it does with
    -- the room is fit a Multi-Shot in, once every N cycles -- and, on every
    -- turret notation that has one, an Arcane Shot as queued filler. Two
    -- sentences in one step rather than a sixth step: the narration is five
    -- lines by contract (L.STEPS, L.STEP_FOR, the view's five rows).
    local s3 = nil
    if multis > 0 then
      local every = math.floor(autos / multis + 0.5)
      if every < 1 then every = 1 end
      s3 = ("%s takes %.1f s - it fits where %s does, once every %d cycles."):format(
        N.m or "Multi-Shot", ab.m.dur, N.s or "Steady", every)
    end
    if arcanes > 0 then
      local everyA = math.floor(autos / arcanes + 0.5)
      if everyA < 1 then everyA = 1 end
      local a = ("%s is instant - free filler on the GCD, once every %d cycles."):format(
        N.A or "Arcane Shot", everyA)
      s3 = s3 and (s3 .. " " .. a) or a
    end
    steps[3] = s3
  else
    steps[3] = ("Nothing else fits between the beats: one %s per release is the whole cycle."):format(N.s or "Steady")
  end
  steps[4] = ("At %.1f s the bow starts its wind-up. A cast still running now pushes the release back - that is a clip."):format(cycle - windup)
  if leadSym then
    steps[5] = ("Pressing %s during the wind-up is free: it queues and starts on the next beat. Late is fine, early is the sin."):format(leadName)
  else
    -- Nothing queues on a castless paper, so the last line is the other half
    -- of the same rule: the shot needs you back out of melee to fire at all.
    steps[5] = ("Be back outside melee before %.1f s: the bow will not fire from inside it, and a shot it cannot take is a beat lost."):format(cycle - windup)
  end
  out.nSteps = L.STEPS

  ------------------------------------------------------------------------
  -- Cursor marks: where "Play slowly" moves from one step to the next. They
  -- are the callouts' own moments where that works -- but a weave gap can open
  -- ON the release (a 3-weave French does exactly that), which would put step 3
  -- ahead of step 2, so the list is forced monotone. A cursor that lights the
  -- steps out of order is a worse lie than one that lights them a tenth late.
  ------------------------------------------------------------------------
  local marks = out.marks
  if not marks then marks = {}; out.marks = marks end
  marks[1] = 0
  marks[2] = 0.1 * cycle
  marks[3] = gt0 or steadyCast
  marks[4] = cycle - windup
  marks[5] = cycle - windup * 0.5
  local eps = 0.01 * cycle
  local cap = cycle - 1e-6
  for i = 2, L.STEPS do
    local floorT = marks[i - 1] + eps
    if marks[i] < floorT then marks[i] = floorT end
    if marks[i] > cap then marks[i] = cap end
  end

  ------------------------------------------------------------------------
  -- THE WHOLE ROTATION (the Lesson page's second strip). One cycle is the
  -- teaching unit above; this is the paper's whole period laid out once --
  -- every auto with its wind-up, every cast, the instants, the weaves and the
  -- layout's own waits -- so a 5:5:1:1 reads as 5:5:1:1 and not as the 1:1
  -- its first cycle looks like (user, 2026-08-26). Times from the layout's
  -- own origin (the first auto's wind-up starts at 0).
  ------------------------------------------------------------------------
  out.pSegs = out.pSegs or {}
  out.nPSegs = 0
  local function pseg(lane, kind, sym, t0, t1, text)
    local i = out.nPSegs + 1
    out.nPSegs = i
    local s = out.pSegs[i]
    if not s then s = {}; out.pSegs[i] = s end
    s.lane, s.kind, s.sym, s.t0, s.t1, s.text = lane, kind, sym, t0, t1, text
    return s
  end
  for i = 1, #ev do
    local e = ev[i]
    local sym = e.sym
    if sym == "a" then
      pseg("shots", "windup", "a", e.t0, e.t0 + e.dur, nil)
      pseg("shots", "release", "a", e.t0 + e.dur, e.t0 + e.dur, nil)
    elseif sym == "s" or sym == "m" or sym == "A" then
      pseg("shots", "cast", sym, e.t0, e.t0 + e.dur, N[sym] or sym)
    elseif sym == "w" or sym == "r" then
      pseg("weave", "gap", "w", e.t0, e.t0 + e.dur, "weave")
    end
  end
  local delays = lay.delays or {}
  for i = 1, #delays do
    local d = delays[i]
    pseg("shots", "wait", "a", d.t0, d.t0 + d.dur, ("+%d"):format(math.floor(d.dur * 1000 + 0.5)))
  end
  for i = out.nPSegs + 1, #out.pSegs do out.pSegs[i] = false end
  out.periodDur = lay.dur
  out.periodRel = rel1          -- the first release, the bar's own origin
  local parts = {}
  parts[#parts + 1] = ("%d %s"):format(autos, autos == 1 and "auto" or "autos")
  if (counts.s or 0) > 0 then parts[#parts + 1] = ("%d %s"):format(counts.s, N.s or "Steady") end
  if multis > 0 then parts[#parts + 1] = ("%d %s"):format(multis, N.m or "Multi") end
  if arcanes > 0 then parts[#parts + 1] = ("%d %s"):format(arcanes, N.A or "Arcane") end
  if weaves > 0 then parts[#parts + 1] = ("%d %s"):format(weaves, weaves == 1 and "weave" or "weaves") end
  local totalDelay = lay.delay or 0
  out.periodText = ("%s - %.1f s per period%s"):format(table.concat(parts, ", "), lay.dur,
    totalDelay > 0.005 and (" - the paper waits %d ms of auto"):format(math.floor(totalDelay * 1000 + 0.5)) or "")

  clearRest(out)
  return out
end

local Nock = rawget(_G, "Nock")
if Nock then Nock.PracticeLesson = L end
return L
