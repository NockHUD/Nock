-- Tests/practice_replay_test.lua
-- Standalone LuaJIT tests for the two halves of Core/PracticeTimeline.lua that
-- serve the practice REVIEW and the conveyor's judgments: T.Strip's `pops`
-- (one per graded paper note, alive 1.1 s) and T.Replay (one cycle's paper
-- ghosts against what was played). Lives apart from practice_timeline_test.lua
-- because that file is at LuaJIT's 200-local ceiling.
-- Run from the repo root: luajit Tests/practice_replay_test.lua

local M = dofile("Core/PracticeModel.lua")
local T = dofile("Core/PracticeTimeline.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return a ~= nil and b ~= nil and math.abs(a - b) <= (tol or 1e-3) end

local h = { ws = 3.0, rangedMul = 1.38, mws = 3.7, meleeMul = 1, castCorr = 1,
            imprArcanePts = 0, multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 }
local CYCLE = 3.0 / 1.38            -- one auto-to-auto cycle at this haste
local WINDUP = 0.5 / 1.38           -- the wind-up the model lays autos out with
local STEADY = 1.5 / 1.38

--------------------------------------------------------------------------------
-- 1. T.Strip pops: the judgment stream, windowed to the last T.POP_LIFE seconds.
--------------------------------------------------------------------------------
do
  ok(T.POP_LIFE == 1.1, "T.POP_LIFE is 1.1 s")

  -- Index 2 is a FAULT verdict, not a judgment: it belongs to the mark row and
  -- must never reach the pops.
  local V = {
    { kind = "judge", t = 9.6, grade = "PERFECT", deltaMs = 20,
      note = { t0 = 9.6, sym = "s", key = 4000101 } },
    { t = 9.7, code = "CLIP", text = "CLIP +120 ms", key = "auto" },
    { kind = "judge", t = 9.9, grade = "CLIP", deltaMs = 120,
      note = { t0 = 9.8, sym = "s", key = 4000102 } },
    { kind = "judge", t = 10.0, grade = "MISSED",
      note = { t0 = 9.95, sym = "w", key = 4000103 } },
  }
  local opts = { past = 2, future = 4.5, windup = WINDUP, verdicts = V }
  local out = T.Strip({}, 0, { now = 10 }, opts, nil)

  ok(out.popsN == 3, "three judgments inside the window pop (got " .. tostring(out.popsN) .. ")")
  local p1, p2, p3 = out.pops[1], out.pops[2], out.pops[3]
  ok(p1.text == "PERFECT" and p1.sev == "good" and p1.key == 4000101 and near(p1.t, 9.6),
     "pop 1: PERFECT / good / the note's key / the judgment's time")
  ok(p1.grade == "PERFECT" and p1.sym == "s", "pop 1 also carries the grade and the note's symbol")
  ok(p2.text == "CLIP +120 ms" and p2.sev == "bad" and p2.key == 4000102,
     "pop 2: the CLIP text carries its ms (got " .. tostring(p2.text) .. ")")
  ok(p3.text == "MISSED" and p3.sev == "bad" and p3.key == 4000103, "pop 3: MISSED / bad")

  -- `t` is when the note was graded, `t0` when the paper wanted it: a judgment
  -- is pushed inline at the press, so the note's frame may be past the hit line
  -- by the time its pop is drawn and `t0` is the anchor that survives that.
  ok(near(p1.t0, 9.6) and near(p2.t0, 9.8) and near(p3.t0, 9.95),
     "every pop carries the NOTE's time as well as the grading time")
  ok(p1.deltaMs == 20 and p2.deltaMs == 120, "...and the delta, without reparsing the text")
  ok(p3.deltaMs == nil, "...which a MISSED simply has none of")
  ok(out.nMarks == 1 and out.marks[1].code == "CLIP",
     "...while the fault verdict is a MARK and the judgments are not")

  -- The CLIP text is formatted once and kept on the verdict: a pop is rebuilt
  -- on every tick it is alive for, and a per-tick format is a per-tick string.
  local clipText = p2.text
  ok(rawequal(V[3]._text, clipText), "the CLIP text is cached on the verdict")
  out = T.Strip({}, 0, { now = 10 }, opts, out)
  ok(rawequal(out.pops[2].text, clipText), "a rebuild reuses the same CLIP string object")
  ok(rawequal(out.pops[1].text, T.JUDGE_TEXT.PERFECT), "...and a constant grade is the shared constant")

  -- Ageing out, one at a time.
  out = T.Strip({}, 0, { now = 10.8 }, opts, out)
  ok(out.popsN == 2 and out.pops[1].grade == "CLIP",
     "0.8 s on: the oldest judgment has aged out (got " .. tostring(out.popsN) .. ")")
  out = T.Strip({}, 0, { now = 11.5 }, opts, out)
  ok(out.popsN == 0, "1.5 s on: every judgment has aged out")
  ok(out.pops[1].text == nil and out.pops[1].key == nil and out.pops[1].t0 == nil
     and out.pops[1].deltaMs == nil, "...and the stale pop slots are cleared")

  -- The cursor only ever moves forward, and past everything that can never pop
  -- again -- the fault verdict included.
  ok(out._popFrom == #V + 1, "the scan cursor has advanced past the whole list (at "
     .. tostring(out._popFrom) .. ")")

  -- A new fight is a new verdict TABLE: the cursor goes back to the front even
  -- though `now` (GetTime) kept running.
  local V2 = { { kind = "judge", t = 11.4, grade = "LATE", deltaMs = 400,
                 note = { t0 = 11.0, sym = "m", key = 4000201 } } }
  local out2 = T.Strip({}, 0, { now = 11.5 }, { past = 2, future = 4.5, verdicts = V2 }, out)
  ok(out2._popFrom == 1 and out2.popsN == 1, "a fresh verdict table resets the cursor")
  ok(out2.pops[1].text == "LATE" and out2.pops[1].sev == "warn", "LATE pops amber, not red")

  -- A rewound clock (a test harness, a re-seeded stream) resets it too, and a
  -- judgment stamped AHEAD of the cursor never pops.
  local out3 = T.Strip({}, 0, { now = 9.7 }, opts, out2)
  ok(out3._popFrom == 1, "a rewind resets the cursor")
  ok(out3.popsN == 1 and out3.pops[1].grade == "PERFECT",
     "...and only the judgment already graded pops (got " .. tostring(out3.popsN) .. ")")

  -- No verdicts at all: no pops, no crash.
  local outNone = T.Strip({}, 0, { now = 12 }, { past = 2, future = 4.5 }, nil)
  ok(outNone.popsN == 0 and #outNone.pops == 0, "no verdicts -> no pops")

  -- Steady state costs nothing: the pop tables are pooled and the only string
  -- that varies is cached on its verdict.
  local allocOut = T.Strip({}, 0, { now = 10 }, opts, nil)
  local popRef = allocOut.pops[1]
  allocOut = T.Strip({}, 0, { now = 10 }, opts, allocOut)
  ok(allocOut.pops[1] == popRef, "repeat call reuses the pop tables by identity")
  if jit then jit.off() end
  collectgarbage()
  local kb0 = collectgarbage("count")
  for _ = 1, 100 do
    allocOut = T.Strip({}, 0, { now = 10 }, opts, allocOut)
  end
  collectgarbage()
  local kb1 = collectgarbage("count")
  if jit then jit.on() end
  ok(kb1 - kb0 < 2, "100 steady-state popping T.Strip calls retain < 2 KB after GC (grew "
     .. string.format("%.2f", kb1 - kb0) .. " KB)")
end

--------------------------------------------------------------------------------
-- 2. T.Replay: ONE cycle, paper against played.
--
-- The fixture is a 1:1 stream (an auto every cycle, a Steady straight after it)
-- where cycle 3's Steady is pressed 0.9 s late and the auto that CLOSES cycle 3
-- is pushed 120 ms behind it -- the clip that late Steady caused.
--------------------------------------------------------------------------------
local LATE, DELAY = 0.9, 0.12
local rEvents, autoT = { { kind = "pull", t = 0 } }, {}
for k = 0, 5 do
  local t = k * CYCLE + ((k >= 3) and DELAY or 0)
  autoT[k + 1] = t
  rEvents[#rEvents + 1] = { kind = "auto", t = t, delay = (k == 3) and DELAY or 0, cause = "cast" }
  local ct0 = t + 0.05 + ((k == 2) and LATE or 0)
  rEvents[#rEvents + 1] = { kind = "cast", spell = "steady", t0 = ct0, t1 = ct0 + STEADY }
  -- An instant in cycle 5, to pin the minimum drawn span.
  if k == 4 then
    rEvents[#rEvents + 1] = { kind = "cast", spell = "arcane", t0 = t + 1.4, t1 = t + 1.5 }
  end
end
rEvents[#rEvents + 1] = { kind = "stop", t = 5 * CYCLE + DELAY + 1.6 }
local nR = #rEvents
local rScore = { windows = { { t0 = 0, t1 = 20, rangedMul = 1.38, notation = "drill 1:1" } } }   -- Steady-only (the practice 1:1 writes a Multi)

-- Where the paper puts its Steady inside a cycle, straight off the layout: the
-- note's own time less the release that opens the cycle it falls in.
local lay1 = M.Layout(M.STRINGS["drill 1:1"], h, 0)
local rel1, sPaper = nil, nil
for _, pe in ipairs(lay1.ev) do
  if pe.sym == "a" and not rel1 then rel1 = pe.t0 + pe.dur end
  if pe.sym == "s" and not sPaper then sPaper = pe.t0 end
end
local sOffset = sPaper - rel1

local rep = T.Replay(rEvents, nR, rScore, h, M, 3, nil)
ok(rep.nCycles == 6, "the fixture has 6 cycles (got " .. tostring(rep.nCycles) .. ")")
ok(rep.index == 3 and near(rep.t0, 2 * CYCLE), "cycle 3 starts at the third auto")
ok(near(rep.cycle, CYCLE + DELAY),
   "...and runs a cycle plus the clip that pushed its closing auto (got " .. tostring(rep.cycle) .. ")")
ok(rep.paper == "s" and rep.played == "s" and rep.ok == true,
   "the T.Cycles caption comes through (paper " .. tostring(rep.paper) .. " / played " .. tostring(rep.played) .. ")")

local ghosts, played, autos = {}, {}, {}
for i = 1, rep.nItems do
  local it = rep.items[i]
  if it.ghost then ghosts[#ghosts + 1] = it
  elseif it.sym == "a" then autos[#autos + 1] = it
  else played[#played + 1] = it end
end
ok(#ghosts == 1 and ghosts[1].sym == "s" and ghosts[1].lane == "shots",
   "one paper ghost: the Steady (got " .. #ghosts .. ")")
ok(near(ghosts[1].t0, sOffset) and near(sOffset, 0),
   "...at its paper offset, relative to the cycle start (" .. string.format("%.3f", ghosts[1].t0 or -1) .. ")")
ok(near(ghosts[1].t1 - ghosts[1].t0, STEADY), "...spanning a Steady cast")

ok(#played == 1 and played[1].sym == "s" and played[1].ghost == false,
   "one played cast: the Steady (got " .. #played .. ")")
ok(near(played[1].t0, 0.05 + LATE),
   "...at the moment it was actually pressed (" .. string.format("%.3f", played[1].t0 or -1) .. ")")

ok(#autos == 1, "one auto on the card: the one this cycle's wind-up belongs to (got " .. #autos .. ")")
ok(autos[1].label == "+120 ms", "...tagged with the delay it was clipped by (got "
   .. tostring(autos[1].label) .. ")")
ok(near(autos[1].t1, CYCLE + DELAY) and near(autos[1].t0, CYCLE + DELAY - WINDUP),
   "...drawn from its wind-up to its release")

-- The auto that OPENED the cycle wound up in the cycle before it, and cycle 2
-- is where its tag would be if it had one.
local rep2 = T.Replay(rEvents, nR, rScore, h, M, 2, rep)
local openAuto = nil
for i = 1, rep2.nItems do
  local it = rep2.items[i]
  if not it.ghost and it.sym == "a" then openAuto = it end
end
ok(openAuto ~= nil and near(openAuto.t1, CYCLE), "cycle 2's own closing auto is cycle 3's opener")
ok(openAuto ~= nil and openAuto.label == nil, "...and it went out clean, so it carries no tag")

-- MIN_CAST_DRAW: an Arcane Shot is instant, and a one-pixel sliver is not a
-- thing you can read on a card.
local rep5 = T.Replay(rEvents, nR, rScore, h, M, 5, rep)
local arc = nil
for i = 1, rep5.nItems do
  local it = rep5.items[i]
  if not it.ghost and it.sym == "A" then arc = it end
end
ok(arc ~= nil and near(arc.t1 - arc.t0, T.MIN_CAST_DRAW),
   "an instant is drawn at MIN_CAST_DRAW (got " .. tostring(arc and (arc.t1 - arc.t0)) .. ")")

-- Out of range, and no cycle at all.
local repNone = T.Replay(rEvents, nR, rScore, h, M, 99, rep)
ok(repNone.nItems == 0 and repNone.cycle == 0 and repNone.t0 == nil, "an out-of-range cycle replays nothing")
ok(repNone.items[1].sym == nil and repNone.items[1].t0 == nil, "...and the stale item slots are cleared")
local repEmpty = T.Replay({}, 0, nil, h, M, 1, nil)
ok(repEmpty.nItems == 0 and repEmpty.nCycles == 0, "no events, no windows: nothing, and no crash")

--------------------------------------------------------------------------------
-- 3. A weave cycle: the paper's `w` slot and the Raptor that filled it.
--------------------------------------------------------------------------------
do
  local WEAVE = "3:7 2w"
  local wStr = M.STRINGS[WEAVE]
  local wLay = M.Layout(wStr, h, 0)
  local evs, PERIODS = { { kind = "pull", t = 0 } }, 3
  for k = 0, PERIODS - 1 do
    local base = k * wLay.dur
    for _, pe in ipairs(wLay.ev) do
      if pe.sym == "a" then
        evs[#evs + 1] = { kind = "auto", t = base + pe.t0 + pe.dur, delay = 0 }
      elseif pe.sym == "s" then
        evs[#evs + 1] = { kind = "cast", spell = "steady", t0 = base + pe.t0, t1 = base + pe.t0 + pe.dur }
      elseif pe.sym == "w" or pe.sym == "r" then
        evs[#evs + 1] = { kind = "melee", t = base + pe.t0, hit = "r" }
      end
    end
  end
  evs[#evs + 1] = { kind = "stop", t = PERIODS * wLay.dur + 2 }
  local nW = #evs
  local wScore = { windows = { { t0 = 0, t1 = PERIODS * wLay.dur + 2, rangedMul = 1.38, notation = WEAVE } } }

  -- The first cycle whose paper asks for a weave.
  local cyc = T.Cycles(evs, nW, wScore, h, M, nil)
  local k = nil
  for i = 1, cyc.n - 1 do
    if k == nil and cyc[i].paper:find("w", 1, true) then k = i end
  end
  ok(k ~= nil, "fixture: some cycle of 3:7 2w carries a weave slot")

  local rw = T.Replay(evs, nW, wScore, h, M, k, nil)
  local gw, pr = nil, nil
  for i = 1, rw.nItems do
    local it = rw.items[i]
    if it.ghost and it.sym == "w" then gw = it end
    if not it.ghost and it.sym == "r" then pr = it end
  end
  ok(gw ~= nil and gw.lane == "weave", "the weave cycle ghosts a `w` on the weave lane")
  ok(pr ~= nil and pr.lane == "weave" and pr.label == "Raptor",
     "...and the Raptor that filled it is played on the same lane")
  ok(gw and pr and near(pr.t1, gw.t0),
     "...landing exactly on the slot (hit " .. string.format("%.3f", pr and pr.t1 or -1)
     .. " vs slot " .. string.format("%.3f", gw and gw.t0 or -1) .. ")")
  ok(rw.paper:find("w", 1, true) ~= nil and rw.played:find("r", 1, true) ~= nil,
     "the caption reads paper w / played r")

  -- Pooling and steady state: a card that rebuilds allocates nothing.
  local first, last = rw.items[1], rw.items[rw.nItems]
  local lenBefore, cycRef = #rw.items, rw._cyc
  rw = T.Replay(evs, nW, wScore, h, M, k, rw)
  ok(rw.items[1] == first and rw.items[rw.nItems] == last, "repeat call reuses the item tables by identity")
  ok(#rw.items == lenBefore and rw._cyc == cycRef, "...and neither the pool nor the cycle handle is rebuilt")
  if jit then jit.off() end
  collectgarbage()
  local kb0 = collectgarbage("count")
  for _ = 1, 100 do
    rw = T.Replay(evs, nW, wScore, h, M, k, rw)
  end
  collectgarbage()
  local kb1 = collectgarbage("count")
  if jit then jit.on() end
  ok(kb1 - kb0 < 2, "100 steady-state T.Replay calls retain < 2 KB after GC (grew "
     .. string.format("%.2f", kb1 - kb0) .. " KB)")
end

--------------------------------------------------------------------------------
-- 4. Against the REAL grader: a judgment is pushed inline at the press, so
-- every cast judgment of a clean 1:1 fight pops inside the cycle the note
-- belongs to — while a pop only lives T.POP_LIFE (1.1 s), which is shorter than
-- a cycle. The two windows have to line up or a clean fight pops nothing.
--------------------------------------------------------------------------------
do
  local G = dofile("Modules/PracticeGrader.lua")
  local g = G.New({ model = M, h = h, notation = "drill 1:1", clipMin = 0.03, reaction = 0.15,
                    timeline = T })
  local CASTS = 6
  G.Feed(g, { t = 0, kind = "pull" })
  for k = 0, CASTS - 1 do
    local rel = WINDUP + k * CYCLE          -- the paper puts the Steady ON the release
    G.Feed(g, { t = rel, kind = "auto", delay = 0 })
    G.Feed(g, { t = rel + STEADY, kind = "cast", spell = "steady", t0 = rel, t1 = rel + STEADY })
  end
  G.Feed(g, { t = WINDUP + CASTS * CYCLE, kind = "stop" })

  ok(g.judge.perfect == CASTS, "the clean stream grades " .. CASTS .. " PERFECT notes (got "
     .. tostring(g.judge.perfect) .. ")")
  ok(g.judge.missed == 0 and g.judge.off == 0, "...and nothing missed or off paper")

  local popOut, judged, inCycle, popped, keyed = nil, 0, true, true, true
  for i = 1, #g.verdicts do
    local v = g.verdicts[i]
    if v.kind == "judge" then
      judged = judged + 1
      local nt = v.note and v.note.t0
      if not (nt and v.t >= nt - 1e-9 and (v.t - nt) <= CYCLE + 1e-9) then inCycle = false end
      if not (v.note and v.note.key) then keyed = false end
      -- The strip as the view drives it: one `out`, `now` walking forward.
      popOut = T.Strip({}, 0, { now = v.t }, { past = 2, future = 4.5, verdicts = g.verdicts }, popOut)
      local found = false
      for p = 1, popOut.popsN do
        local pp = popOut.pops[p]
        if near(pp.t, v.t) and near(pp.t0, nt) and pp.key == v.note.key then found = true end
      end
      if not found then popped = false end
    end
  end
  ok(judged == CASTS, "one judgment per cast (got " .. judged .. ")")
  ok(inCycle, "every cast judgment is graded inside the cycle its note belongs to")
  ok(popped, "...and pops at the moment it is graded, note time and key intact")
  ok(keyed, "...with a note key, so the pop has a frame to sit on")
end

--------------------------------------------------------------------------------
-- 5. A cancelled cast: T.Cycles leaves it out of `played` (it never became a
-- shot), and the card draws it anyway — a card that showed nothing where the
-- player pressed and let go would hide the thing it exists to explain.
--------------------------------------------------------------------------------
do
  local evs = { { kind = "pull", t = 0 } }
  for k = 0, 2 do
    local t = k * CYCLE
    evs[#evs + 1] = { kind = "auto", t = t, delay = 0 }
    evs[#evs + 1] = { kind = "cast", spell = "steady", t0 = t + 0.05, t1 = t + 0.05 + STEADY }
  end
  evs[#evs + 1] = { kind = "cast", spell = "multi", t0 = CYCLE + 1.5, t1 = CYCLE + 1.8, cancelled = true }
  evs[#evs + 1] = { kind = "stop", t = 3 * CYCLE }
  local rc = T.Replay(evs, #evs, rScore, h, M, 2, nil)
  local cancelled = nil
  for i = 1, rc.nItems do
    local it = rc.items[i]
    if it.label == "cancelled" then cancelled = it end
  end
  ok(cancelled ~= nil and cancelled.sym == "m" and cancelled.ghost == false,
     "the cancelled Multi is drawn on the card, labelled")
  ok(rc.played == "s", "...while the caption still reads just the Steady (got "
     .. tostring(rc.played) .. ")")
end

print(("practice_replay: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
