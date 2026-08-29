-- Tests/practice_queue_test.lua
-- Standalone LuaJIT tests: a press made in the free QUEUE WINDOW is judged on
-- the beat, the cycle boundary has ONE definition, and the paper's own auto
-- delay is never the player's clip.
--
-- THE QUEUE WINDOW IS FREE. A cast pressed inside the auto's wind-up (or inside
-- the client's queue window before the GCD ends) is not started by the player —
-- the client holds it and starts it the moment it may. Grading that START by
-- the clock is grading the CLIENT, and it produced the round-3 report: the same
-- on-the-beat press judged PERFECT, then GOOD, then LATE, then MISSED, cycling.
-- So a queued cast is graded on the PRESS instead: free is about who started it,
-- not about how far the client's hold pushed it. Same doctrine as the clip band
-- (project rule): warning inside the free window is the most annoying thing this
-- addon can do to a weaving hunter.
--
-- Run from the repo root: luajit Tests/practice_queue_test.lua

local E = dofile("Modules/PracticeEngine.lua")
local M = dofile("Core/PracticeModel.lua")
local TL = dofile("Core/PracticeTimeline.lua")
local G = dofile("Modules/PracticeGrader.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- The grade the judgment scale gives a delta, so the expectations below are
-- derived rather than copied (PracticeGrader's PERFECT_SEC / GOOD_SEC).
local function gradeOf(d)
  local ad = (d < 0) and -d or d
  if ad <= 0.08 then return "PERFECT" end
  if ad <= 0.25 then return "GOOD" end
  return "LATE"
end

--------------------------------------------------------------------------------
-- The harness: the real engine feeding the real grader, one press per release
-- at a fixed offset from it. `rm` is the ranged multiplier — 1.38 is the P1 BM
-- baseline (eWS 2.174) and 3.0/1.34 is what the `beat` drill's own lock= pins
-- (eWS 1.34), where the 1.5 s GCD is LONGER than the 1.34 s swing and the paper
-- therefore budgets an auto delay of its own every cycle.
--
-- G.Finish takes (g, events, n): handing it the stream is what runs the T.Cycles
-- branch, i.e. the figure the GRADE is actually made of. Passing anything else
-- silently falls back to the live counters and the test covers nothing.
--------------------------------------------------------------------------------
local WS = 3.0
local function newG(rm)
  local h = { ws = WS, rangedMul = rm, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0,
              castCorr = 1, multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 }
  -- The Steady-only paper is the teaching `drill 1:1` (the practice `1:1`
  -- writes a Multi once per cooldown since 2026-08-27, M.PaperString); these
  -- streams are Steadies alone.
  return G.New({ model = M, h = h, notation = "drill 1:1", clipMin = 0.03, reaction = 0.15,
                 timeline = TL }), h
end

local function run(lat, off, rm, seconds)
  local cfg = { ws = WS, baseRangedMul = rm, latency = lat, gcd = 1.5,
                queueWindow = 0.4, castCorr = 1, multiCd = 10,
                arcaneCdBase = 6, arcaneCdPerPt = 0.2, imprArcanePts = 0,
                armOnShot = true, mws = 3.7, baseMeleeMul = 1.0,
                quickShots = false, seed = 1, eventCap = 6000 }
  local e = E.New(cfg)
  local g = newG(rm)
  E.StartFight(e, 0)
  E.Press(e, { "autoshot" }, 0)
  local fed, t, dt = 0, 0, 0.001
  -- One press per release, at that release + off. A negative offset aims at the
  -- release still to come (`nextShotAt`); a non-negative one at the release that
  -- just went out (`lastShotAt`), since the grid has already re-based by then.
  -- `done` keys on the release itself, so no release is pressed for twice and
  -- none is skipped when the grid slides.
  local done = {}
  while t < (seconds or 12) do
    E.Step(e, t)
    local rel = (off < 0) and e.nextShotAt or e.lastShotAt
    if rel and rel > 0 and not done[rel] and t + 1e-9 >= rel + off then
      done[rel] = true
      E.Press(e, { "steady" }, t)
    end
    while fed < e.n do fed = fed + 1; G.Feed(g, e.events[fed]) end
    t = t + dt
  end
  E.Step(e, t)
  while fed < e.n do fed = fed + 1; G.Feed(g, e.events[fed]) end
  e.n = e.n + 1; e.events[e.n] = { t = t, kind = "stop" }
  G.Feed(g, e.events[e.n])
  local score = G.Finish(g, e.events, e.n)
  return e, g, score
end

local function tally(g)
  local n = { PERFECT = 0, GOOD = 0, LATE = 0, CLIP = 0, MISSED = 0, OFF = 0 }
  local faults = {}
  for i = 1, #g.verdicts do
    local v = g.verdicts[i]
    if v.kind == "judge" then n[v.grade] = (n[v.grade] or 0) + 1
    elseif v.code and v.code ~= "GOOD" then faults[#faults + 1] = v.code end
  end
  return n, table.concat(faults, ",")
end

local function autoDelay(e)
  local worst = 0
  for i = 1, e.n do
    local ev = e.events[i]
    if ev.kind == "auto" and (ev.delay or 0) > worst then worst = ev.delay end
  end
  return worst
end

--------------------------------------------------------------------------------
-- 1. THE PLAN'S OWN GATE. Presses at release -0.2 / -0.05 / +0.0 / +0.02, with
--    the latency both off and at a realistic 50 ms: none of them is a fault of
--    any kind, and each is graded on WHERE THE FINGER WAS — the press reaches
--    the engine at off + lat from the release, so that is the delta the note is
--    scored against whether the client queued the cast or not. Nothing here is
--    ever LATE, OFF or MISSED: the press was inside the free window every time.
--------------------------------------------------------------------------------
for _, rm in ipairs({ 1.38, WS / 1.34 }) do
  local label = ("eWS %.2f"):format(WS / rm)
  for _, lat in ipairs({ 0, 0.05 }) do
    for _, off in ipairs({ -0.2, -0.05, 0.0, 0.02 }) do
      local e, g, score = run(lat, off, rm)
      local n, faults = tally(g)
      local want = gradeOf(off + lat)
      local other = (want == "PERFECT") and "GOOD" or "PERFECT"
      local tag = ("%s lat %.0f ms off %+0.2f"):format(label, lat * 1000, off)
      ok(n[want] > 0, tag .. ": the on-beat presses are judged " .. want .. " (" .. n[want] .. ")")
      -- At the baseline the grid is steady, so the grade is exactly the one the
      -- offset earns. At GCD-bound haste the paper delays autos by its own
      -- design, so a press aimed at the PREDICTED release can land a little
      -- further from the one that actually went out — PERFECT and GOOD mix, and
      -- that is honest. Neither may ever reach LATE.
      if rm == 1.38 then
        ok(n[other] == 0, tag .. ": ...and only " .. want .. " (" .. other .. " " .. n[other] .. ")")
      else
        ok(n.PERFECT + n.GOOD == n[want] + n[other],
           tag .. ": ...and nothing worse than GOOD")
      end
      ok(n.LATE == 0, tag .. ": no LATE judgment (" .. n.LATE .. ")")
      ok(n.OFF == 0, tag .. ": no OFF judgment (" .. n.OFF .. ")")
      ok(faults == "", tag .. ": no fault at all (" .. faults .. ")")
      ok((score.clips or 0) == 0 and (score.clipMs or 0) == 0,
         tag .. ": no clip billed (" .. tostring(score.clips) .. "/" .. tostring(score.clipMs) .. ")")
    end
  end
end

--------------------------------------------------------------------------------
-- 2. THE HIGH-HASTE GUARD (the coordinator's ruling). At the `beat` drill's own
--    pinned haste the GCD is longer than the swing, so the PAPER itself delays
--    every auto — M.Layout's period for "as" is the 1.5 s GCD, not the 1.34 s
--    swing. A perfectly queued cast therefore clips by the layout's own design,
--    and the doctrine (paper-budgeted clips are not faults) has to cover the
--    WRAP delay as well as the ones written between two autos of the string.
--------------------------------------------------------------------------------
do
  local rm = WS / 1.34
  local e, g, score = run(0.05, -0.05, rm)
  local n, faults = tally(g)
  ok(autoDelay(e) > 0.05,
     "high haste: the stream really does carry a delayed auto (" .. ("%.3f"):format(autoDelay(e)) .. " s)")
  ok(n.CLIP == 0, "high haste: the layout's own clip is no CLIP judgment (" .. n.CLIP .. ")")
  ok(faults == "", "high haste: ...and no CLIP fault either (" .. faults .. ")")
  ok((score.clips or 0) == 0 and (score.clipMs or 0) == 0,
     "high haste: the scorecard bills none of it, so the beat rung stays passable")
  ok((score.cyclesOnPaper and score.cyclesOnPaper.total or 0) > 0, "high haste: cycles were counted")

  -- ...and the exemption is a BUDGET, not a blanket: a delay well past what the
  -- paper schedules is still the player's clip.
  local gg = newG(rm)
  G.Feed(gg, { t = 0, kind = "pull" })
  G.Feed(gg, { t = 1.5, kind = "auto", delay = 0.16, cause = "cast" })   -- exactly the budget
  local _, f1 = tally(gg)
  ok(f1 == "", "budget: the paper's own 160 ms is not a fault (" .. f1 .. ")")
  G.Feed(gg, { t = 3.0, kind = "auto", delay = 0.60, cause = "cast" })   -- 440 ms past it
  local _, f2 = tally(gg)
  ok(f2 == "CLIP", "budget: 440 ms past the budget still is (" .. f2 .. ")")

  -- The counterpart, so the exemption is not vacuous: at a haste where the
  -- paper schedules no delay at all, the same 160 ms IS the player's clip.
  local g2 = newG(1.38)
  G.Feed(g2, { t = 0, kind = "pull" })
  G.Feed(g2, { t = 2.174, kind = "auto", delay = 0.16, cause = "cast" })
  local _, f3 = tally(g2)
  ok(f3 == "CLIP", "budget: a paper that schedules no delay still faults 160 ms (" .. f3 .. ")")
end

--------------------------------------------------------------------------------
-- 3. WHO STARTED THE CAST. The queue exemption forgives the CLIENT's hold, not
--    the player's timing: a queued press that landed on the note is PERFECT
--    however far the GCD pushed the start, and a queued press that was itself a
--    third of a second off the note is still LATE. `deltaMs` always reports the
--    honest start-to-note distance, whichever way the grade went.
--------------------------------------------------------------------------------
do
  local cast = 1.5 / 1.38
  local R = 0.362                      -- the release, and the paper's Steady note
  local function fight(startAt, queuedFrom)
    local g = newG(1.38)
    local ev, n = {}, 0
    local function feed(e) n = n + 1; ev[n] = e; G.Feed(g, e) end
    feed({ t = 0, kind = "pull" })
    feed({ t = R, kind = "auto", delay = 0 })
    feed({ t = startAt + cast, kind = "cast", spell = "steady",
           t0 = startAt, t1 = startAt + cast, queuedFrom = queuedFrom })
    feed({ t = 4.0, kind = "stop" })
    G.Finish(g, ev, n)
    for i = 1, #g.verdicts do
      if g.verdicts[i].kind == "judge" then return g.verdicts[i] end
    end
  end
  -- The player started it themselves, half a second after the note.
  local v = fight(R + 0.5, nil)
  ok(v and v.grade == "LATE", "an unqueued Steady half a second late is still LATE ("
     .. tostring(v and v.grade) .. ")")
  ok(v and v.deltaMs == 500, "...with the real delta on it (" .. tostring(v and v.deltaMs) .. ")")

  -- The GCD-bound beat case: pressed ON the release, started 500 ms later
  -- because the client was still holding the GCD. Not the player's doing.
  local q = fight(R + 0.5, R)
  ok(q and q.grade == "PERFECT", "the same start, pressed on the beat, is PERFECT ("
     .. tostring(q and q.grade) .. ")")
  ok(q and q.deltaMs == 500, "...and still reports the honest start delta ("
     .. tostring(q and q.deltaMs) .. ")")

  -- ...but a fumble that happens to queue off an earlier GCD is not forgiven:
  -- the finger was 350 ms off the note, and that is what it is graded on.
  local fumble = fight(R + 0.5, R + 0.35)
  ok(fumble and fumble.grade == "LATE",
     "a queued press 350 ms off the note is still LATE (" .. tostring(fumble and fumble.grade) .. ")")
  local nudge = fight(R + 0.5, R + 0.12)
  ok(nudge and nudge.grade == "GOOD",
     "...and one 120 ms off is GOOD, not PERFECT (" .. tostring(nudge and nudge.grade) .. ")")
end

--------------------------------------------------------------------------------
-- 4. ONE CYCLE BOUNDARY. A cast that starts within a client frame of a release
--    belongs to the NEW cycle: it is the shot that release opened the door for.
--    The old 1e-9 epsilon made that a coin flip against float jitter and the
--    latency the press was shifted by — a hair early and the cast matched the
--    PREVIOUS cycle's note (a whole cycle away → LATE, or already consumed →
--    OFF). A press made well before the release still belongs where it landed.
--
--    And the JUDGMENTS and the SCORECARD have to fall the same way. The grade
--    is built on T.Cycles' own reading of the stream, so a boundary that is
--    33 ms wide here and exact there gives a row of green PERFECT pops over a
--    scorecard that says 4 of 6 cycles were on paper. `T.CYCLE_EPS` is the one
--    definition both read.
--------------------------------------------------------------------------------
do
  ok(TL.CYCLE_EPS ~= nil, "the timeline exports the cycle boundary")
  local cast = 1.5 / 1.38
  local cyc = 3.0 / 1.38
  local R1 = 0.362
  local function boundary(shift, nCycles)
    local g = newG(1.38)
    local ev, n = {}, 0
    local function feed(e) n = n + 1; ev[n] = e; G.Feed(g, e) end
    feed({ t = 0, kind = "pull" })
    for i = 1, nCycles do
      local rel = R1 + (i - 1) * cyc
      feed({ t = rel, kind = "auto", delay = 0 })
      -- Every cast starts `shift` before the release that opened its cycle.
      local t0 = rel - shift
      feed({ t = t0 + cast, kind = "cast", spell = "steady", t0 = t0, t1 = t0 + cast })
    end
    feed({ t = R1 + nCycles * cyc, kind = "auto", delay = 0 })   -- closes the last cycle
    feed({ t = R1 + nCycles * cyc + 0.1, kind = "stop" })
    local score = G.Finish(g, ev, n)
    local grades = {}
    for i = 1, #g.verdicts do
      local v = g.verdicts[i]
      if v.kind == "judge" then grades[v.grade] = (grades[v.grade] or 0) + 1 end
    end
    return grades, score
  end

  local gExact, sExact = boundary(0, 6)
  ok(gExact.PERFECT == 6, "on the release: 6 PERFECT (" .. tostring(gExact.PERFECT) .. ")")
  ok(sExact.cyclesOnPaper.ok == 6 and sExact.cyclesOnPaper.total == 6,
     "on the release: 6/6 cycles on paper (" .. sExact.cyclesOnPaper.ok .. "/"
     .. sExact.cyclesOnPaper.total .. ")")

  -- 4 ms early — inside the frame of doubt. This is the case that flapped: the
  -- judgments said 6/6 PERFECT while T.Cycles counted 4 of 6.
  local gHair, sHair = boundary(0.004, 6)
  ok(gHair.PERFECT == 6 and (gHair.OFF or 0) == 0 and (gHair.MISSED or 0) == 0,
     "4 ms early: still 6 PERFECT, nothing OFF or MISSED (" .. tostring(gHair.PERFECT) .. ")")
  ok(sHair.cyclesOnPaper.ok == 6 and sHair.cyclesOnPaper.total == 6,
     "4 ms early: the scorecard agrees — 6/6 (" .. sHair.cyclesOnPaper.ok .. "/"
     .. sHair.cyclesOnPaper.total .. ")")
  ok(sHair.grade == sExact.grade,
     "4 ms early: the same grade as landing exactly on the release ("
     .. tostring(sHair.grade) .. " vs " .. tostring(sExact.grade) .. ")")

  -- Half a second before the release is not jitter: those casts belong to the
  -- cycle they started in, and both halves say so.
  local gEarly, sEarly = boundary(0.5, 6)
  ok((gEarly.PERFECT or 0) == 0, "half a second early is not PERFECT")
  ok(sEarly.cyclesOnPaper.ok < 6,
     "half a second early: the scorecard drops cycles too (" .. sEarly.cyclesOnPaper.ok .. "/"
     .. sEarly.cyclesOnPaper.total .. ")")
end

--------------------------------------------------------------------------------
-- 5. THE MATCHER OWNS CYCLE MEMBERSHIP (R5a).
--
--    A queued Steady that lands on the beat is the way 1:1 is played, and the
--    row must say so: every cycle of the engine runs above is on paper, not
--    just every pop. That is the regression half.
--
--    The half that FAILED is the paper whose own cycle is wider than the
--    measured one. `fillCycle` seats a cycle's notes across the LAYOUT's window
--    while the row cuts cycles at the measured releases, and 3:7 2w at its own
--    pinned eWS schedules a 1.55 s cycle against a 0.9 s swing — so its weave
--    note sits a tenth of a second PAST the next release. Playing that note
--    dead-on used to read as an OFF press in the next cycle while the note
--    itself went MISSED in this one: `w s` in one row cell, an empty cell
--    beside it, under a row of PERFECT pops.
--------------------------------------------------------------------------------
-- PLAY THE PAPER EXACTLY. Builds a stream that hits every note of `notation` at
-- its own eWS dead-on, where the grader itself seats it: one auto every measured
-- cycle, one press per note, no jitter at all. Anything short of a clean sheet
-- on a stream like this is the grader disagreeing with itself.
--
-- Returns the grader, the scorecard, the stream, its length, the haste handle,
-- the note count, the measured cycle, the widest note offset seated in any
-- cycle, and whether the paper ever writes two different notes on one beat.
local NOTE_SYM = { s = true, m = true, A = true, r = true, w = true }
local function paperFight(notation, ews, cycles, rel0)
  local rm = WS / ews
  local h = { ws = WS, rangedMul = rm, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0,
              castCorr = 1, multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 }
  local lay = M.Layout(M.STRINGS[notation], h, 0)
  -- The layout's releases, and each cycle position's notes as offsets from the
  -- release that opens it -- the seating PracticeGrader's fillCycle does.
  local rel, nRel = {}, 0
  for i = 1, #lay.ev do
    local pe = lay.ev[i]
    if pe.sym == "a" then nRel = nRel + 1; rel[nRel] = pe.t0 + pe.dur end
  end
  local CYCLE = WS / rm
  local notes, widest, sameBeat = {}, 0, false
  for p = 0, nRel - 1 do
    local lo = rel[p + 1]
    local hi = (p + 1 < nRel) and rel[p + 2] or (rel[1] + lay.dur)
    local list = {}
    for i = 1, #lay.ev do
      local pe = lay.ev[i]
      if NOTE_SYM[pe.sym] then
        local pt = pe.t0
        if pt < rel[1] - 1e-9 then pt = pt + lay.dur end
        if pt >= lo - 1e-9 and pt < hi - 1e-9 then
          local off = pt - lo
          list[#list + 1] = { sym = pe.sym, off = off }
          if off > widest then widest = off end
        end
      end
    end
    notes[p] = list
  end

  local CASTT = { s = M.CastTime(1.5, rm, 1), m = M.CastTime(0.5, rm, 1), A = 0.1 }
  local SPELL = { s = "steady", m = "multi", A = "arcane" }
  -- meleeCycle = 0: this stream feeds autos exactly one weapon cycle apart and
  -- ignores the clip delays the weave papers budget, so its weaves can land
  -- closer than a 3.7 s swing allows. The grader would (rightly) retime them
  -- onto the swing's return; here the swing is declared unconstrained, because
  -- the point of this fixture is the seat-and-match arithmetic, not the melee.
  local g = G.New({ model = M, h = h, notation = notation, clipMin = 0.03,
                    reaction = 0.15, timeline = TL, meleeCycle = 0 })
  local ev, n = {}, 0
  local function feed(e) n = n + 1; ev[n] = e end
  local REL0, NC = rel0 or 0.2, cycles or 14
  feed({ t = 0, kind = "pull" })
  local plays, np = {}, 0
  for k = 0, NC do
    local t = REL0 + k * CYCLE
    feed({ t = t, kind = "auto", delay = 0 })
    if k < NC then
      for _, note in ipairs(notes[k % nRel]) do
        local pt = t + note.off
        np = np + 1
        if note.sym == "w" or note.sym == "r" then
          plays[np] = { t = pt, kind = "melee", hit = "r" }
        else
          local d = CASTT[note.sym]
          plays[np] = { t = pt + d, kind = "cast", spell = SPELL[note.sym], t0 = pt, t1 = pt + d }
        end
      end
    end
  end
  feed({ t = REL0 + NC * CYCLE + 0.1, kind = "stop" })
  -- One stream, in arrival order -- an auto ahead of anything that shares its
  -- moment, exactly as the engine emits them (the shot in phase 3, the melee in
  -- phase 3b).
  local all = {}
  for i = 1, n do all[#all + 1] = ev[i] end
  for i = 1, np do all[#all + 1] = plays[i] end
  for i = 1, #all do all[i]._ix = i end
  table.sort(all, function(a, b)
    local ta, tb = a.t or a.t0, b.t or b.t0
    if ta ~= tb then return ta < tb end
    local ka = (a.kind == "auto") and 0 or 1
    local kb = (b.kind == "auto") and 0 or 1
    if ka ~= kb then return ka < kb end
    return a._ix < b._ix
  end)
  -- Do two plays share a MOMENT? That is the pair the match map used to seat on
  -- one float key, and it is a property of the stream, not of one cycle: a
  -- weave hit and a cast press a period apart land on the same number just as
  -- readily as two notes on one beat.
  local seen = {}
  for i = 1, np do
    local pl = plays[i]
    local key = pl.t0 or pl.t
    if seen[key] then sameBeat = true end
    seen[key] = true
  end
  local nAll = #all
  for i = 1, nAll do G.Feed(g, all[i]) end
  local score = G.Finish(g, all, nAll)
  return g, score, all, nAll, h, np, CYCLE, widest, sameBeat
end

-- The judgment tally and the red-cell count for one such fight, in one call.
local function paperResult(notation, ews, cycles)
  local g, score, all, nAll, h, np, CYCLE, widest, sameBeat = paperFight(notation, ews, cycles)
  local jn = { PERFECT = 0, GOOD = 0, LATE = 0, CLIP = 0, MISSED = 0, OFF = 0 }
  for i = 1, #g.verdicts do
    local v = g.verdicts[i]
    if v.kind == "judge" then jn[v.grade] = (jn[v.grade] or 0) + 1 end
  end
  local cyc = TL.Cycles(all, nAll, score, h, M, nil)
  local red = 0
  for i = 1, cyc.n do
    if not (cyc[i].ok or cyc[i].partial) then red = red + 1 end
  end
  return { j = jn, score = score, red = red, notes = np, cyc = cyc, g = g,
           all = all, n = nAll, h = h, cycle = CYCLE, widest = widest, sameBeat = sameBeat }
end

-- Every note PERFECT, every cycle on paper, no red cell: the whole contract for
-- a fight played exactly as written.
local function okClean(tag, r)
  ok(r.j.PERFECT == r.notes, tag .. ": all " .. r.notes .. " notes PERFECT (" .. r.j.PERFECT .. ")")
  ok(r.j.MISSED == 0 and r.j.OFF == 0,
     tag .. ": nothing MISSED or OFF (" .. r.j.MISSED .. " / " .. r.j.OFF .. ")")
  local cp = r.score.cyclesOnPaper
  ok(cp.total > 0 and cp.ok == cp.total,
     tag .. ": every cycle on paper (" .. cp.ok .. "/" .. cp.total .. ")")
  ok(r.red == 0, tag .. ": no red ROTATION cell (" .. r.red .. ")")
end

do
  -- The regression half, on the engine's own stream: every Steady queued into
  -- the wind-up, every cycle on paper.
  for _, lat in ipairs({ 0, 0.05 }) do
    for _, off in ipairs({ -0.2, -0.05, 0.0 }) do
      local _, _, score = run(lat, off, 1.38)
      local cp = score.cyclesOnPaper
      ok(cp.total > 0 and cp.ok == cp.total,
         ("queued 1:1 (lat %.0f ms, off %+0.2f): every cycle on paper (%d/%d)")
         :format(lat * 1000, off, cp.ok, cp.total))
    end
  end

  -- The failing half. `3:7 2w` at eWS 0.90 (WEAVE_DRILL's own pin), played
  -- EXACTLY as the grader seats it: one note, one press, on the note.
  local r = paperResult("3:7 2w", 0.90)
  ok(r.widest > r.cycle,
     "3:7 2w really does seat a note past the next release (the case R5a is about)")
  okClean("3:7 2w", r)
  ok(r.score.grade == "A+", "3:7 2w: ...and the grade says so (" .. tostring(r.score.grade) .. ")")
  ok(r.score.match ~= nil, "the scorecard carries the match map")

  -- The other direction: an unmatched press keeps filing by the CLOCK. An extra
  -- Steady in a cycle whose paper has none is an OFF, and the row must show it
  -- where it was played.
  local h, all, nAll = r.h, r.all, r.n
  local CAST = M.CastTime(1.5, WS / 0.90, 1)
  local extraT = 0.2 + 2 * r.cycle + 0.3        -- cycle 3: the paper is empty there
  local extra = { t = extraT + CAST, kind = "cast", spell = "steady",
                  t0 = extraT, t1 = extraT + CAST }
  local g2 = G.New({ model = M, h = h, notation = "3:7 2w", clipMin = 0.03, meleeCycle = 0,
                     reaction = 0.15, timeline = TL })
  -- Spliced into the already-ordered stream rather than re-sorted: a second
  -- sort would be free to re-order the ties the first one settled.
  local all2, put = {}, false
  for i = 1, nAll do
    local e = all[i]
    if not put and (e.t or e.t0) > extra.t then all2[#all2 + 1] = extra; put = true end
    all2[#all2 + 1] = e
  end
  if not put then all2[#all2 + 1] = extra end
  for i = 1, #all2 do G.Feed(g2, all2[i]) end
  local score2 = G.Finish(g2, all2, #all2)
  local off2 = 0
  for i = 1, #g2.verdicts do
    local v = g2.verdicts[i]
    if v.kind == "judge" and v.grade == "OFF" then off2 = off2 + 1 end
  end
  ok(off2 == 1, "an extra Steady on an empty cycle is OFF (" .. off2 .. ")")
  local cyc2 = TL.Cycles(all2, #all2, score2, h, M, nil)
  ok(cyc2[3] and cyc2[3].played == "s" and cyc2[3].ok == false,
     "...and the row files it by the clock, in the cycle it was played in ("
     .. tostring(cyc2[3] and cyc2[3].played) .. ")")
end

--------------------------------------------------------------------------------
-- 6. TWO PLAYS, ONE MOMENT -- and a note seated past its own cycle.
--
--    (a) `5:5:1:1 3w` at eWS 1.65 writes a weave and a cast on the SAME beat
--        twice a period, so the melee hit and the cast's press land on the same
--        float. The match map was keyed by that float, so one play silently took
--        the other's seat: the row lost the weave in one cycle and gained it in
--        the next -- two red cells under 28 PERFECT pops. The key is the EVENT
--        table now, and there is exactly one of those per play.
--
--    (b) `5:5:1:1` at eWS 1.55 seats its Arcane at +1.967 in a 1.55 s cycle. The
--        cast that plays that note STARTS at it, which the sweep's cast-start
--        shortcut read as "past the cycle's end, nothing more is coming" -- so
--        the note went MISSED a moment before the press that took it dead-on
--        arrived, and the press came out OFF in the next cycle. A cycle with a
--        note past its own end waits for that note.
--------------------------------------------------------------------------------
do
  local a = paperResult("5:5:1:1 3w", 1.65)
  ok(a.sameBeat, "5:5:1:1 3w at eWS 1.65 really does land two plays on one moment")
  okClean("5:5:1:1 3w @ 1.65", a)

  local b = paperResult("5:5:1:1", 1.55)
  ok(b.widest > b.cycle, "5:5:1:1 at eWS 1.55 really does seat a note past its own cycle")
  okClean("5:5:1:1 @ 1.55", b)

  -- The map holds one entry per matched play, and two plays that share a moment
  -- hold two of them.
  local nb = 0
  for _ in pairs(b.score.match) do nb = nb + 1 end
  ok(nb == b.notes, "one match entry per matched play (" .. nb .. " of " .. b.notes .. ")")
  local na = 0
  for _ in pairs(a.score.match) do na = na + 1 end
  ok(na == a.notes, "...including the pairs that share a beat (" .. na .. " of " .. a.notes .. ")")
end

--------------------------------------------------------------------------------
-- 7. THE PULL TRANSITION (R7). The whole path the two round-7 screenshots came
--    off: arm `drill 1:1+mA` at its own pinned eWS 2.10, leave the panel sitting
--    on Start for two seconds, pull with a Steady, and read the conveyor's item
--    table the way the view builds it (T.Strip with the view's own opts shape).
--
--    ARMED the strip was right -- one cast per cycle, the Arcane in its slot.
--    The moment the fight pulled it grew a second box per cycle and a row of
--    tiny items each drawing three dots, and the beat at the cursor held a Multi
--    inside the Steady. Two roots, both here:
--
--    (R7b-i) every grid auto carried the label "grid" -- a debug word on a
--            0.35 s bar, which is an icon and room for "...".
--    (R7b-ii) the engine's NEXT bar was drawn whatever the paper said. Nock's
--            live rotation engine advised Multi (the paper writes an `m`, ten
--            seconds away, so Nock.PaperAllows passes it) while the paper's next
--            note was the Steady on this beat.
--
--    R7a -- "a played bar spanning back from the hit line at a fight age of
--    0.01 s" -- is the chip being read as hundredths: `FIGHT %d:%02d` says 0:01
--    at ONE SECOND, which is exactly when the pulling Steady resolves. Asserted
--    both ways below: nothing in the past at 0.01 s, and at 1.07 s exactly the
--    pulling cast, at its real width.
--------------------------------------------------------------------------------
do
  local NOTA = "drill 1:1+mA"
  local EWS = 2.10
  local RM = WS / EWS
  local CAST = M.CastTime(1.5, RM, 1)
  local h = { ws = WS, rangedMul = RM, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0,
              castCorr = 1, multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 }
  local e = E.New({ ws = WS, baseRangedMul = RM, latency = 0.005, gcd = 1.5,
                    queueWindow = 0.4, castCorr = 1, multiCd = 10,
                    arcaneCdBase = 6, arcaneCdPerPt = 0.2, imprArcanePts = 0,
                    armOnShot = true, mws = 3.7, baseMeleeMul = 1.0,
                    quickShots = false, seed = 1, eventCap = 6000 })
  local g = G.New({ model = M, h = h, notation = NOTA, clipMin = 0.03,
                    reaction = 0.15, timeline = TL })
  local T0, PULL = 1000, 1002
  E.StartFight(e, T0, 1)
  E.SetDistance(e, 7)
  local fed = 0
  local function feed() while fed < e.n do fed = fed + 1; G.Feed(g, e.events[fed]) end end
  local t = T0
  while t < PULL do E.SetNow(e, t); E.Step(e, t); feed(); t = t + 1 / 30 end
  E.Press(e, { "steady" }, PULL)

  -- The conveyor's own feed, in its own shape: Practice:Lookahead's live table
  -- and Frame_PracticeConveyor:Rebuild's opts. `advice` is what the live rotation
  -- engine is telling the HUD to press -- nil for none.
  local snap, live, out = {}, {}, nil
  local paper = { str = M.STRINGS[NOTA], h = h }
  -- The paper items are THE PLAN's (v3 P1), built the way Practice:PublishPlan
  -- builds it from this same engine and grader. `advice` -- what the live
  -- rotation engine used to tell the HUD -- no longer reaches the strip at all;
  -- the parameter stays so the fixture reads as the screenshots did.
  local PP = dofile("Core/PracticePlan.lua")
  local plan, src = PP.New(), { model = M, seat = G.SeatCycle, T = TL, castCorr = 1 }
  local function planFor(now, past, future)
    src.now, src.live, src.pulled, src.t0 = now, true, snap.pulled == true, snap.t0 or 0
    src.past, src.future = past, future
    src.cycle, src.windup = snap.cycle, snap.windup
    src.nextShotAt, src.lastShotAt, src.rangedMul = snap.nextShotAt, snap.lastShotAt, snap.rangedMul
    src.msReadyAt, src.arcReadyAt = snap.msReadyAt, snap.arcReadyAt
    -- The hand's clock, as Practice:PublishPlan hands it over: the running
    -- GCD and cast, a press the client is holding.
    src.gcdEnd = ((snap.gcdDur or 0) > 0) and ((snap.gcdStart or 0) + snap.gcdDur) or 0
    src.castEnd = (snap.cast and snap.cast.t1) or 0
    src.castSym = snap.cast and ({ steady = "s", multi = "m", arcane = "A" })[snap.cast.spell] or nil
    src.castStart = snap.cast and snap.cast.t0 or nil
    src.gcd = 1.5
    src.queuedSym = e.queued and ({ steady = "s", multi = "m", arcane = "A" })[e.queued.spell] or nil
    src.queuedAt = e.queued and e.queued.at or nil
    src.weaveAt, src.weaveRoom, src.weaveFits = snap.weaveAt, snap.weaveRoom, snap.weaveFits
    src.oppOpen, src.meleeReadyAt = e.oppOpen, snap.meleeReadyAt
    src.paperSyms = g.win and G.PaperSyms(g) or nil
    src.cur, src.pend, src.winAutos = g.cur, g.pend, (g.win and g.win.autos) or 0
    src.lay = G.Layout(g) or G.Layout(g, M.STRINGS[NOTA], RM)
    src.notation = NOTA
    -- A fresh plan per call: the sweep below jumps the clock around the
    -- period, and a plan's asks are sticky for a FIGHT (an ask is never
    -- retracted, a lost note stays lost) -- across a sweep they would pin
    -- every note to the first age that asked for it.
    plan = PP.New()
    return PP.Build(src, plan)
  end
  local function strip(now, advice)
    E.Snapshot(e, snap)
    live.now = now
    live.nextShotAt, live.cycle, live.windup = snap.nextShotAt, snap.cycle, snap.windup
    live.lastShotAt, live.rangedMul = snap.lastShotAt, snap.rangedMul
    live.winAutos = (g.win and g.win.autos) or 0
    live.meleeReadyAt, live.oppOpen = snap.meleeReadyAt, e.oppOpen
    live.weaveAt, live.weaveTtw, live.weaveFits = snap.weaveAt, snap.weaveRoom, snap.weaveFits
    live.procs, live.paperSyms = snap.procs, g.win and g.win.syms or nil
    live.plan = planFor(now, 3.09, 7.0)
    h.rangedMul = live.rangedMul
    out = TL.Strip(e.events, e.n, live, { past = 3.09, future = 7.0, windup = live.windup,
                                          verdicts = g.verdicts, model = M, paper = paper }, out)
    return out
  end

  -- Everything on one lane, in time order.
  local function lane(o, name, filter)
    local list = {}
    for i = 1, o.nItems do
      local it = o.items[i]
      if it.lane == name and (filter == nil or filter(it)) then list[#list + 1] = it end
    end
    table.sort(list, function(x, y) return x.t0 < y.t0 end)
    return list
  end
  local function isGrid(it)
    return it.key ~= nil and it.key >= TL.KEY.GRID and it.key < TL.KEY.MOVE
  end
  local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-6) end

  -- R7a, the age the report claims. Nothing has resolved yet, so the past lane
  -- is empty -- there is no two-second bar behind the cursor to find.
  E.SetNow(e, PULL + 0.01); E.Step(e, PULL + 0.01); feed()
  do
    local o = strip(PULL + 0.01, "m")
    local pastCasts = lane(o, "shots", function(it) return it.t1 <= o.t0 + 3.09 + 1e-9 and not it.future end)
    ok(#pastCasts == 0, "age 0.01: the past shots lane is empty (" .. #pastCasts .. " items)")
  end

  -- R7a, the age the CHIP was actually showing. The pulling Steady has resolved:
  -- exactly one played bar, and it is that cast at its real width.
  while t < PULL + 1.07 do E.SetNow(e, t); E.Step(e, t); feed(); t = t + 1 / 60 end
  local o = strip(t, "m")
  do
    local played = lane(o, "shots", function(it) return it.key ~= nil and it.key >= TL.KEY.PLAYED end)
    ok(#played == 1, "age 1.07: exactly one played bar (" .. #played .. ")")
    local b = played[1]
    ok(b and b.sym == "s" and near(b.t0, PULL + 0.005, 1e-6),
       "...the pulling Steady, starting at the press")
    ok(b and near(b.t1 - b.t0, CAST, 1e-6),
       ("...at its real width (%.3f s, want %.3f)"):format(b and (b.t1 - b.t0) or -1, CAST))
  end

  -- R7b-i: not one bar on the stage carries a word that cannot be drawn. The
  -- grid's wind-up bars are the whole population of that fault.
  do
    local labelled = lane(o, "shots", function(it) return isGrid(it) and it.label ~= nil end)
    ok(#labelled == 0, "no grid auto carries a label (" .. #labelled .. ")")
  end

  -- R7b-ii: ONE cast per cycle, and it is the paper's own. The engine is advising
  -- Multi, which the paper does write -- ten seconds away, not on this beat.
  local WANT = { "s", "A", "s", "s", "A", "m" }   -- drill 1:1+mA, the paper's order
  -- THE PAPER'S ORDER ON THE HAND'S CLOCK (Plan B round 2). The strip's
  -- future casts run in the paper's order; a Steady on the beat waits for
  -- its auto (queued into the wind-up), an instant is pressed the moment the
  -- hand is free -- it clips nothing, so the paper's "a A" is not a wait.
  -- So a weapon cycle may hold the paper's Steady AND the instant the paper
  -- put after the next auto; what may never happen is a cast out of order,
  -- or two Steadies in one cycle.
  local function cyclesHoldPaper(o2, tag)
    local grid = lane(o2, "shots", isGrid)
    local casts = lane(o2, "shots", function(it) return it.future and it.sym ~= "a" end)
    ok(#grid >= 3, tag .. ": the grid is on the lane (" .. #grid .. " autos)")
    local syms = {}
    for j = 1, #casts do syms[#syms + 1] = casts[j].sym end
    local phase = nil
    for p = 1, #WANT do
      local match = #syms > 0
      for j = 1, #syms do if syms[j] ~= WANT[((p + j - 2) % #WANT) + 1] then match = false; break end end
      if match then phase = p; break end
    end
    ok(phase ~= nil, tag .. ": the future casts run in the paper's order (" .. table.concat(syms, " ") .. ")")
    local checked = 0
    for i = 1, #grid do
      local rel, hi = grid[i].t1, grid[i].t1 + live.cycle
      local n = 0
      for j = 1, #casts do
        local c = casts[j]
        if c.sym == "s" and c.t0 >= rel - 1e-6 and c.t0 < hi - 1e-6 then n = n + 1 end
      end
      if hi <= o2.t1 then
        checked = checked + 1
        ok(n <= 1, ("%s: cycle %d holds at most one Steady (%d)"):format(tag, i, n))
      end
    end
    ok(checked >= 2, tag .. ": at least two whole cycles were checked (" .. checked .. ")")
  end
  cyclesHoldPaper(o, "engine advises Multi")
  do
    local mBars = lane(o, "shots", function(it) return it.sym == "m" end)
    ok(#mBars == 0, "the off-paper Multi bar is not drawn at all (" .. #mBars .. ")")
    local nextBars = lane(o, "shots", function(it) return it.label == "NEXT" end)
    ok(#nextBars == 1 and nextBars[1].sym == "s" and nextBars[1].key >= TL.KEY.PAPER,
       "NEXT is on the paper's own next note")
  end

  -- ...and the same whatever the live engine says: one cast per cycle, and the
  -- word on the paper's note -- there is no engine bar any more (v3 P1).
  cyclesHoldPaper(strip(t, nil), "no engine advice")
  do
    local o3 = strip(t, "s")
    cyclesHoldPaper(o3, "engine agrees")
    local nextBars = lane(o3, "shots", function(it) return it.label == "NEXT" end)
    ok(#nextBars == 1 and nextBars[1].key >= TL.KEY.PAPER,
       "...and NEXT is the paper's note even when the engine agrees with it")
  end

  -- THE SWEEP (R7 review). One visible NEXT at EVERY moment of the period, not
  -- just at the ages the fixtures happen to sample. The whole 12.6 s of
  -- `drill 1:1+mA` at 0.25 s steps, against all three states the live rotation
  -- engine can be in.
  --
  -- The second half of the claim lives in the view and cannot run here: a bar
  -- wearing NEXT can be as narrow as T.MIN_CAST_DRAW (the paper's next note is
  -- the Arcane for a third of this period, and the Multi for another sixth),
  -- which is why Frame_PracticeConveyor MEASURES the word and drops the ICON
  -- rather than the label when only one of the two fits. `narrow` below is the
  -- proof that those bars really do occur -- a fixed pixel gate on the text area
  -- lost the word on every one of them.
  local sweepMiss, narrow = 0, 0
  local ages = {}
  while t < PULL + 16 do
    E.SetNow(e, t); E.Step(e, t); feed()
    for _, adv in ipairs({ false, "m", "s", "A" }) do
      local o2 = strip(t, adv or nil)
      local words = lane(o2, "shots", function(it) return it.label == "NEXT" end)
      if #words ~= 1 then
        sweepMiss = sweepMiss + 1
        if #ages < 6 then ages[#ages + 1] = ("%.2f/%s:%d"):format(t - e.t0, tostring(adv), #words) end
      elseif near(words[1].t1 - words[1].t0, TL.MIN_CAST_DRAW, 1e-6) then
        narrow = narrow + 1
      end
    end
    t = t + 0.25
  end
  ok(sweepMiss == 0,
     "sweep: exactly one NEXT at every age of the period (" .. sweepMiss .. " misses: "
     .. table.concat(ages, " ") .. ")")
  ok(narrow > 0,
     "sweep: and the bar wearing it is sometimes only MIN_CAST_DRAW wide (" .. narrow .. ")")
end

print(("practice_queue: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
