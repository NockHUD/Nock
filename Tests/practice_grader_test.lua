-- Tests/practice_grader_test.lua
-- Standalone LuaJIT tests for Modules/PracticeGrader.lua's verdicts and scorecard.

local M = dofile("Core/PracticeModel.lua")
local G = dofile("Modules/PracticeGrader.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-3) end

local H = { ws = 3.0, rangedMul = 1.38, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0 }
local DMG = { a = 1000, s = 900, m = 950, A = 600, r = 500, w = 400 }
local function newG()
  return G.New({ model = M, h = H, notation = "1:1", damage = DMG, clipMin = 0.03, reaction = 0.15 })
end
-- THE PAPER IS THE SCOPE (R3a). Every fault that names a Multi or an Arcane —
-- STEADY_WONT_FIT's alternative, CATCH-UP MULTI MISSED, and the LATE that says
-- "a Multi fit here" — exists only on a paper that writes that symbol. `1:1` is
-- "as": Steady and nothing else. Fixtures that exercise those faults therefore
-- run on the French paper, which writes `m` and `A`; section 40 is the
-- counterpart that proves the same streams raise nothing on `1:1`.
local function newGm()
  return G.New({ model = M, h = H, notation = "5:5:1:1", damage = DMG, clipMin = 0.03, reaction = 0.15 })
end
local function ctx(ttw, opts)
  opts = opts or {}
  return { ttw = ttw, inWindup = opts.inWindup or false, cycle = 3.0 / 1.38,
           steadyCast = 1.5 / 1.38, multiCast = 0.5 / 1.38,
           msReady = opts.msReady ~= false, arcReady = opts.arcReady ~= false }
end
local function codes(g)
  local out = {}
  for i = 1, #g.verdicts do out[#out + 1] = g.verdicts[i].code end
  return table.concat(out, ",")
end

-- 1. A clean 1:1 fight: autos on time, steadies that fit -> GOOD only
local g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })
G.Feed(g, { t = 0.36, kind = "auto", delay = 0 })
G.Feed(g, { t = 1.087, kind = "cast", spell = "steady", t0 = 0, t1 = 1.087 })
G.Feed(g, { t = 1.5, kind = "free", ctx = ctx(0.3, { msReady = false, arcReady = false }) })  -- nothing fits: waiting is right
G.Feed(g, { t = 2.53, kind = "auto", delay = 0 })
G.Feed(g, { t = 2.6, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })
G.Feed(g, { t = 3.69, kind = "cast", spell = "steady", t0 = 2.6, t1 = 3.69 })
G.Feed(g, { t = 4.35, kind = "stop" })
local score = G.Finish(g)
ok(codes(g) == "GOOD,GOOD", "clean fight: GOOD,GOOD (" .. codes(g) .. ")")
ok(score.autos == 2 and score.gcds == 2, "counts")
ok(near(score.autoEff, 2 * (3.0 / 1.38) / 4.35), "auto efficiency")
ok(near(score.gcdEff, 2 * 1.5 / 4.35), "gcd efficiency")
ok(score.clips == 0 and score.early == 0 and score.lateMs == 0, "no faults")
ok(score.cyclesOnPaper and score.cyclesOnPaper.total >= 1, "cycles on paper counted ("
   .. tostring(score.cyclesOnPaper and score.cyclesOnPaper.ok) .. "/"
   .. tostring(score.cyclesOnPaper and score.cyclesOnPaper.total) .. ")")
ok(g.lastVerdict and g.lastVerdict.code == "GOOD", "lastVerdict set")

-- 2. CLIP from a delayed auto
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 2.6, kind = "auto", delay = 0.12, cause = "cast" })
G.Feed(g, { t = 3, kind = "stop" })
score = G.Finish(g)
ok(codes(g) == "CLIP" and g.verdicts[1].ms == 120, "CLIP +120 ms")
ok(score.clips == 1 and score.clipMs == 120, "clip counted")
ok(g.verdicts[1].text == "CLIP +120 ms", "clip toast text")

-- 3. A 20 ms delay is inside tolerance
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 2.6, kind = "auto", delay = 0.02, cause = "cast" })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "", "sub-threshold delay ignored")

-- 4. NOT_READY
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0.3, kind = "press", key = "arcane", result = "notready", ctx = ctx(1.5) })
G.Feed(g, { t = 3, kind = "stop" })
score = G.Finish(g)
ok(codes(g) == "", "early press is not a verdict (" .. codes(g) .. ")")
ok(score.early == 1, "early press counted")

-- 4b. ...but a notready tagged `mash` (same spell as the one that started the
--     running GCD) is not a fault at all: the counter stays at 0.
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0.3, kind = "press", key = "steady", result = "notready", mash = true, ctx = ctx(1.5) })
G.Feed(g, { t = 3, kind = "stop" })
score = G.Finish(g)
ok(codes(g) == "" and score.early == 0, "mashed notready is free (early " .. tostring(score.early) .. ")")

-- 5. LATE: free at 1.5 with a steady fitting (ttw 1.8), next press at 2.0
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.5, kind = "free", ctx = ctx(1.8) })
G.Feed(g, { t = 2.0, kind = "press", key = "steady", result = "ok", ctx = ctx(1.3) })
G.Feed(g, { t = 3, kind = "stop" })
score = G.Finish(g)
ok(codes(g) == "LATE" and g.verdicts[1].ms == 500, "LATE +500 ms (" .. codes(g) .. ")")
ok(score.lateMs == 500, "late ms summed")

-- 6. Not LATE when nothing fits at the free moment (ttw 0.2, multi on cd)
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.5, kind = "free", ctx = ctx(0.2, { msReady = false, arcReady = false }) })
G.Feed(g, { t = 2.2, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "GOOD", "waiting for the shot is not LATE")

-- 7. LATE measured from the auto when the free moment sat inside the wind-up
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 2.4, kind = "free", ctx = ctx(-0.2, { inWindup = true }) })
G.Feed(g, { t = 2.6, kind = "auto", delay = 0 })
G.Feed(g, { t = 2.7, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })
G.Feed(g, { t = 4, kind = "stop" })
G.Finish(g)
ok(codes(g) == "GOOD", "100 ms after the shot is on time")

-- 8. STEADY_WONT_FIT: steady pressed with ttw 0.8 < cast 1.087 while multi ready
-- (the French paper: the alternative the fault names has to be ON it — R3a)
g = newGm()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "press", key = "steady", result = "ok", ctx = ctx(0.8) })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "STEADY_WONT_FIT", "steady that cannot fit flagged")

-- 9. ...but not when it is queued inside the wind-up (free press); the verdict
--    is deferred until the queued cast actually fires.
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "press", key = "steady", result = "queued", ctx = ctx(-0.1, { inWindup = true }) })
ok(#g.verdicts == 0, "queued press: verdict deferred")
G.Feed(g, { t = 1.3, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8), queuedFrom = 1.0 })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "GOOD" and g.verdicts[1].t == 1.3 and g.verdicts[1].key == "steady", "GOOD emitted when the queued cast fires, with key")

-- 10. CATCHUP_MISSED: next-cycle gap after this steady is smaller than a multi
--     gap = (ttw - steadyCast) + cycle - 1.5 ; ttw 1.2 -> 0.113 + 2.174 - 1.5 = 0.787? too big.
--     ttw 1.1 -> 0.013 + 0.674 = 0.687 (>0.362). Use cycle override: ttw such that gap in (0.1, 0.362):
--     need ttw - 1.087 + 0.674 in (0.1, 0.362) -> ttw in (0.513, 0.775); pick 0.6 — but then steady
--     won't fit (0.6 < 1.087) and STEADY_WONT_FIT wins. So use a faster haste where steady fits:
local H2 = { ws = 3.0, rangedMul = 1.93, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0 }   -- Rapid Fire
g = G.New({ model = M, h = H2, notation = "5:5:1:1", damage = DMG, clipMin = 0.03, reaction = 0.15 })
local c2 = { ttw = 0.9, inWindup = false, cycle = 3.0 / 1.93, steadyCast = 1.5 / 1.93, multiCast = 0.5 / 1.93,
             msReady = true, arcReady = true }
-- gap = (0.9 - 0.777) + 1.554 - 1.5 = 0.177  -> in (0.1, 0.259): catch-up wanted
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "press", key = "steady", result = "ok", ctx = c2 })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "CATCHUP_MISSED", "catch-up multi missed (" .. codes(g) .. ")")

-- 11. A late wait followed by a press on cooldown: no verdict for the fumble,
--     and the LATE still lands on the real press that follows.
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.5, kind = "free", ctx = ctx(1.8) })
G.Feed(g, { t = 2.0, kind = "press", key = "multi", result = "cooldown", ctx = ctx(1.3) })
G.Feed(g, { t = 2.1, kind = "press", key = "steady", result = "ok", ctx = ctx(1.2) })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "LATE" and g.verdicts[1].ms == 600, "cooldown press is silent; LATE measured to the real press (" .. codes(g) .. ")")

-- 12. A late wait followed by NOT READY: NOT_READY wins, the free moment survives
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.5, kind = "free", ctx = ctx(1.8) })
G.Feed(g, { t = 2.0, kind = "press", key = "arcane", result = "notready", ctx = ctx(1.3) })
G.Feed(g, { t = 2.2, kind = "press", key = "steady", result = "ok", ctx = ctx(1.1) })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "LATE", "early press then late (" .. codes(g) .. ")")

-- 13. Multi on cooldown blocks CATCHUP_MISSED
g = G.New({ model = M, h = H2, notation = "1:1", damage = DMG, clipMin = 0.03, reaction = 0.15 })
local c3 = { ttw = 0.9, inWindup = false, cycle = 3.0 / 1.93, steadyCast = 1.5 / 1.93, multiCast = 0.5 / 1.93,
             msReady = false, arcReady = true }
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "press", key = "steady", result = "ok", ctx = c3 })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "GOOD", "no catch-up verdict without multi ready")

-- 14. Integration: a real engine fight piped through the grader. The two files
--     only ever meet through the event stream, so this is the one place the
--     event shapes the engine EMITS are checked against what the grader READS.
local E = dofile("Modules/PracticeEngine.lua")
local KNOWN = { GOOD = true, CLIP = true, LATE = true, NOT_READY = true,
                STEADY_WONT_FIT = true, CATCHUP_MISSED = true,
                WEAVE_MISSED = true, DEAD_ZONE = true, REARM = true, WEAVE_SLOW = true, WEAVE_OK = true,
                EARLY = true }
local CYCLE, WINDUP = 3.0 / 1.38, 0.5 / 1.38
local e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, queueWindow = 0.4 })
E.StartFight(e, 0)
E.Press(e, { "autoshot", "steady" }, 0)          -- pull: arm + Steady behind the shot
local function step(from, to)
  local t = from
  while t <= to + 1e-9 do E.Step(e, t); t = t + 0.01 end
end
-- A second Steady just after the second auto (the first is still queued behind
-- the opening wind-up, so the gcd is not free until well after it).
local secondPress = WINDUP + CYCLE + 0.07
step(0, secondPress)
E.Press(e, { "steady" }, secondPress)
step(secondPress, 6.0)
E.StopFight(e, 6.0)

g = newG()
for i = 1, e.n do G.Feed(g, e.events[i]) end
score = G.Finish(g)
ok(score.autos >= 2, "engine fight: at least two autos (" .. tostring(score.autos) .. ")")
ok(score.gcds == 2, "engine fight: two casts completed (" .. tostring(score.gcds) .. ")")
ok(score.clips == 0, "engine fight: no clips (" .. tostring(score.clips) .. ")")
local unknown = nil
for i = 1, #g.verdicts do
  if not KNOWN[g.verdicts[i].code] then unknown = g.verdicts[i].code end
end
ok(unknown == nil, "engine fight: every verdict code is known (" .. tostring(unknown) .. ")")
ok(#g.verdicts > 0, "engine fight: the grader produced verdicts")
ok(score.fightTime > 0 and score.autoEff > 0 and score.gcdEff > 0, "engine fight: scorecard populated")

-- 14. A replaced queued press emits nothing; the replacing press is graded on its fire
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "press", key = "steady", result = "queued", ctx = ctx(-0.1, { inWindup = true }) })
G.Feed(g, { t = 1.1, kind = "press", key = "steady", result = "replaced", ctx = ctx(-0.2, { inWindup = true }) })
G.Feed(g, { t = 1.1, kind = "press", key = "multi", result = "queued", ctx = ctx(-0.2, { inWindup = true }) })
G.Feed(g, { t = 1.3, kind = "press", key = "multi", result = "ok", ctx = ctx(1.8), queuedFrom = 1.1 })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "GOOD" and g.verdicts[1].key == "multi", "replaced steady silent, multi graded on fire (" .. codes(g) .. ")")

-- 15. CLIP verdicts carry key = auto
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 2.6, kind = "auto", delay = 0.12, cause = "cast" })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(g.verdicts[1].key == "auto", "clip verdict keyed auto")

-- 16. Live scorecard from counters, no paper, reusable out table
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })
G.Feed(g, { t = 0.36, kind = "auto", delay = 0 })
G.Feed(g, { t = 1.087, kind = "cast", spell = "steady", t0 = 0, t1 = 1.087 })
local live = {}
local same = G.Live(g, 2.174, live)
ok(same == live, "Live fills the caller's table")
ok(live.autos == 1 and live.gcds == 1, "live counts")
ok(near(live.autoEff, 1 * (3.0 / 1.38) / 2.174) and near(live.gcdEff, 1.5 / 2.174), "live efficiencies")
ok(live.clips == 0 and live.lateMs == 0 and live.early == 0, "live faults")

-- 17. Mashing ONE key for 20 s must never raise `early` (the whole point of
--     "mashing a key is never a fault"). Engine -> grader, both at the static
--     1.38 haste and under Rapid Fire's 1.93, where the gap between the cast's
--     end and the queue window opening is widest in cycle terms.
local function mashFight(rangedMul)
  local eng = E.New({ ws = 3.0, baseRangedMul = rangedMul, latency = 0, queueWindow = 0.4 })
  E.StartFight(eng, 0)
  E.Press(eng, { "autoshot", "steady" }, 0)
  local t, nextPress = 0, 0.05
  while t <= 20 + 1e-9 do
    if t >= nextPress - 1e-9 then
      E.Press(eng, { "steady" }, t)
      nextPress = nextPress + 0.05
    end
    E.Step(eng, t)
    t = t + 0.01
  end
  E.StopFight(eng, 20)
  local gg = G.New({ model = M, notation = "1:1", damage = DMG, clipMin = 0.03, reaction = 0.15,
                     h = { ws = 3.0, rangedMul = rangedMul, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0 } })
  for i = 1, eng.n do G.Feed(gg, eng.events[i]) end
  return G.Finish(gg), eng
end
local mashScore, mashEngine = mashFight(1.38)
ok(mashEngine.dropped == 0, "20 s mash: no events dropped (" .. tostring(mashEngine.dropped) .. ")")
ok(mashScore.gcds > 5, "20 s mash: the spam really did cast (" .. tostring(mashScore.gcds) .. " casts)")
ok(mashScore.early == 0, "20 s Steady mash at 1.38: early stays 0 (" .. tostring(mashScore.early) .. ")")
mashScore = mashFight(1.93)
ok(mashScore.early == 0, "20 s Steady mash at 1.93: early stays 0 (" .. tostring(mashScore.early) .. ")")

-- 17. A clean weave: WEAVE_OK with the legs in the text, weave counted
local HW = { ws = 3.0, rangedMul = 1.38, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0 }
local function newGW()
  return G.New({ model = M, h = HW, notation = "5:5:1:1 3w", damage = DMG, clipMin = 0.03, reaction = 0.15,
                 oppMin = 0.4, rearmMin = 0.05, legMax = 0.4 })
end
g = newGW()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "weave", edge = "down" })
G.Feed(g, { t = 1.2, kind = "melee", hit = "r" })
G.Feed(g, { t = 1.5, kind = "weave", edge = "up", cost = 0 })
G.Feed(g, { t = 1.5, kind = "weave", edge = "done",
            legs = { stepIn = 0.2, dwell = 0, stepOut = 0.3, total = 0.5, budget = 1.2, backIn = false, backOut = false, hit = "r" } })
G.Feed(g, { t = 3, kind = "stop" })
score = G.Finish(g)
ok(codes(g) == "WEAVE_OK", "clean weave (" .. codes(g) .. ")")
ok(g.verdicts[1].text == "WEAVE OK in 0.2 · out 0.3" and g.verdicts[1].key == "weave", "weave ok text")
ok(score.weavesTaken == 1 and score.meleeHits == 1 and near(score.weaveEff, 3.7 / 3), "weave counts + eff")

-- 18. Slow leg names the leg; total over budget too
g = newGW()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "weave", edge = "down" })
G.Feed(g, { t = 1.6, kind = "melee", hit = "w" })
G.Feed(g, { t = 1.9, kind = "weave", edge = "up", cost = 0 })
G.Feed(g, { t = 1.9, kind = "weave", edge = "done",
            legs = { stepIn = 0.6, dwell = 0, stepOut = 0.3, total = 0.9, budget = 1.2, backIn = false, backOut = false, hit = "w" } })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "WEAVE_SLOW" and g.verdicts[1].text == "WEAVE SLOW — in +0.2 s", "slow step-in named (" .. tostring(g.verdicts[1] and g.verdicts[1].text) .. ")")
g = newGW()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "weave", edge = "down" })
G.Feed(g, { t = 1.3, kind = "melee", hit = "w" })
G.Feed(g, { t = 1.6, kind = "weave", edge = "up", cost = 0 })
G.Feed(g, { t = 1.6, kind = "weave", edge = "done",
            legs = { stepIn = 0.3, dwell = 0, stepOut = 0.3, total = 0.6, budget = 0.5, backIn = false, backOut = true, hit = "w" } })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "WEAVE_SLOW" and g.verdicts[1].text == "WEAVE SLOW — total +0.1 s", "over budget names total")

-- 19. Re-arm cost: REARM, and the pushed auto is NOT also a CLIP
g = newGW()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "weave", edge = "down" })
G.Feed(g, { t = 1.2, kind = "melee", hit = "r" })
G.Feed(g, { t = 1.5, kind = "weave", edge = "up", cost = 0.2 })
G.Feed(g, { t = 1.5, kind = "weave", edge = "done",
            legs = { stepIn = 0.2, dwell = 0, stepOut = 0.3, total = 0.5, budget = 1.2, backIn = false, backOut = false, hit = "r" } })
G.Feed(g, { t = 2.7, kind = "auto", delay = 0.2, cause = "rearm" })
G.Feed(g, { t = 3, kind = "stop" })
score = G.Finish(g)
ok(codes(g) == "REARM", "re-arm graded once (" .. codes(g) .. ")")
ok(g.verdicts[1].ms == 200 and g.verdicts[1].text == "RE-ARM +200 ms", "rearm text")
ok(score.rearmMs == 200 and score.clips == 0, "rearm ms counted, not a clip")

-- 20. WEAVE_MISSED: an opportunity >= 0.4 s with no weave-down inside it
g = newGW()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0.36, kind = "opp", open = true, ttw = 1.8 })
G.Feed(g, { t = 1.47, kind = "opp", open = false, ttw = 0.7 })
G.Feed(g, { t = 3, kind = "stop" })
score = G.Finish(g)
ok(codes(g) == "WEAVE_MISSED" and score.weavesMissed == 1, "missed opportunity (" .. codes(g) .. ")")
g = newGW()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0.36, kind = "opp", open = true, ttw = 1.8 })
G.Feed(g, { t = 0.6, kind = "weave", edge = "down" })
G.Feed(g, { t = 1.47, kind = "opp", open = false, ttw = 0.7 })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "", "opportunity taken (" .. codes(g) .. ")")
g = newGW()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0.36, kind = "opp", open = true, ttw = 1.8 })
G.Feed(g, { t = 0.6, kind = "opp", open = false, ttw = 1.5 })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "", "a window under 0.4 s is not a miss")

-- 21. DEAD_ZONE verdict
g = newGW()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "weave", edge = "down" })
G.Feed(g, { t = 1.9, kind = "deadzone" })
G.Feed(g, { t = 3, kind = "stop" })
G.Finish(g)
ok(codes(g) == "DEAD_ZONE" and g.verdicts[1].text == "DEAD ZONE — step out", "dead zone")

-- 22. LegsNeeded: seed, then the mean of completed weaves; legs stats at Finish
g = newGW()
ok(near(G.LegsNeeded(g), 0.7), "seed legsNeeded")
G.Feed(g, { t = 0, kind = "pull" })
for i = 1, 3 do
  G.Feed(g, { t = i, kind = "weave", edge = "down" })
  G.Feed(g, { t = i + 0.2, kind = "melee", hit = "w" })
  G.Feed(g, { t = i + 0.5, kind = "weave", edge = "up", cost = 0 })
  G.Feed(g, { t = i + 0.5, kind = "weave", edge = "done",
              legs = { stepIn = 0.1 * i, dwell = 0, stepOut = 0.2, total = 0.1 * i + 0.2, budget = 1.0, backIn = (i == 2), backOut = false, hit = "w" } })
end
ok(near(G.LegsNeeded(g), (0.3 + 0.4 + 0.5) / 3), "mean of completed weaves (" .. tostring(G.LegsNeeded(g)) .. ")")
G.Feed(g, { t = 5, kind = "stop" })
score = G.Finish(g)
ok(near(score.legs.stepIn.med, 0.2) and near(score.legs.stepIn.worst, 0.3), "stepIn median/worst")
ok(near(score.legs.total.med, 0.4) and near(score.legs.inBudgetPct, 1.0), "total median, all in budget")
ok(near(score.legs.backpedalPct.stepIn, 1 / 3) and score.legs.backpedalPct.stepOut == 0, "backpedal shares")

-- 24. Haste windows: one per haste state, expected vs played notation
g = G.New({ model = M, h = H, notation = "1:1", damage = DMG,
            notationFor = function(rm) return (rm > 1.5) and "5:5:1:1" or "1:1" end })
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0.36, kind = "auto", delay = 0 })
G.Feed(g, { t = 1.1, kind = "cast", spell = "steady", t0 = 0, t1 = 1.1 })
G.Feed(g, { t = 2.0, kind = "haste", rangedMul = 1.38 * 1.4, meleeMul = 1, qs = false, rf = true, lust = false, drums = false })
G.Feed(g, { t = 2.2, kind = "auto", delay = 0 })
G.Feed(g, { t = 3.0, kind = "cast", spell = "multi", t0 = 2.5, t1 = 3.0 })
G.Feed(g, { t = 3.8, kind = "auto", delay = 0 })
G.Feed(g, { t = 4.0, kind = "stop" })
score = G.Finish(g)
ok(#score.windows == 2 and score.windows[1].notation == "1:1" and score.windows[2].notation == "5:5:1:1", "two windows with their expected notations")
ok(score.windows[1].played == "1:1" and score.windows[2].played == "0:2:1:0", "played notation from the cast mix (" .. tostring(score.windows[2].played) .. ")")
ok(score.windows[1].t1 == 2.0 and score.windows[2].t1 == 4.0 and score.windows[2].autos == 2, "window bounds and counts")
ok(score.windows[2].flags.rf == true and near(score.windows[2].rangedMul, 1.38 * 1.4), "window carries the haste state")

-- 25. Opener: pull anchor — RF within 2 GCDs ok; anchor lust — RF before Lust is EARLY
g = G.New({ model = M, h = H, notation = "1:1", damage = DMG,
            opener = { anchor = "pull", gcds = 2, steadySec = 0.5, cds = { RF = true, Pot = true } } })
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0.3, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })
G.Feed(g, { t = 0.36, kind = "auto", delay = 0 })
G.Feed(g, { t = 1.0, kind = "cd", key = "RF", used = true })
G.Feed(g, { t = 1.39, kind = "cast", spell = "steady", t0 = 0.3, t1 = 1.39 })
G.Feed(g, { t = 5.0, kind = "cd", key = "Pot", used = true })
G.Feed(g, { t = 6.0, kind = "stop" })
score = G.Finish(g)
ok(score.opener.steadyOk and score.opener.cds.RF.ok and not score.opener.cds.Pot.ok and not score.opener.ok, "pull anchor: RF in time, Pot late, opener not ok")
ok(near(score.opener.firstAuto, 0.36) and near(score.opener.firstSteady, 0.3), "opener records the first auto and steady")
g = G.New({ model = M, h = H, notation = "1:1", damage = DMG,
            opener = { anchor = "lust", gcds = 2, steadySec = 0.5, cds = { RF = true } } })
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 2.0, kind = "cd", key = "RF", used = true })
G.Feed(g, { t = 8.0, kind = "proc", name = "Lust", on = true })
G.Feed(g, { t = 9.0, kind = "stop" })
score = G.Finish(g)
ok(codes(g):find("EARLY") and score.opener.cds.RF.early and not score.opener.cds.RF.ok and score.opener.anchorT == 8.0, "lust anchor: RF before Lust is EARLY (" .. codes(g) .. ")")

-- 26. KC counts
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1, kind = "kcwin" }); G.Feed(g, { t = 1.2, kind = "kc", used = true }); G.Feed(g, { t = 7, kind = "kcwin" })
G.Feed(g, { t = 8, kind = "end" })
score = G.Finish(g)
ok(score.kc.windows == 2 and score.kc.used == 1 and near(score.fightTime, 8), "KC windows/used; end event closes the fight")
local live = {}
G.Live(g, 8, live)
ok(live.kcWindows == 2 and live.kcUsed == 1 and live.notation == "1:1", "live KC counts + current notation")

-- 26b. The teardown `stop` that follows a scheduled `end` a frame later must
--      not stretch the fight: the first close wins.
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 8, kind = "end" })
G.Feed(g, { t = 8.03, kind = "stop" })
score = G.Finish(g)
ok(near(score.fightTime, 8), "a stop after end keeps the end's fight time (" .. tostring(score.fightTime) .. ")")
ok(score.windows and score.windows[1] and near(score.windows[1].t1, 8), "and the open haste window closes at the end too")

-- 27. Analysis fields: did/expected/cost on every fault; the clip's cost lands
--     on the decision that caused it, and that decision is the top fix.
g = newGm()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "press", key = "steady", result = "ok", ctx = ctx(0.8) })  -- multi fits, steady does not
G.Feed(g, { t = 2.0, kind = "auto", delay = 0.5, cause = "cast" })                     -- the clip it caused
G.Feed(g, { t = 3.0, kind = "free", ctx = ctx(1.8) })
G.Feed(g, { t = 3.2, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })  -- LATE +200 ms
G.Feed(g, { t = 5.0, kind = "stop" })
score = G.Finish(g)
ok(codes(g) == "STEADY_WONT_FIT,CLIP,LATE", "analysis fight verdicts (" .. codes(g) .. ")")
local allFilled = true
for i = 1, #g.verdicts do
  local v = g.verdicts[i]
  -- Judgments (kind = "judge") are per-note grades, not faults: they carry a
  -- note and a delta instead of did/expected/cost, and never reach this list's
  -- consumers (the fault rows and the report).
  if v.kind ~= "judge"
    and (type(v.did) ~= "string" or type(v.expected) ~= "string" or type(v.cost) ~= "string") then allFilled = false end
end
ok(allFilled, "every fault verdict carries did/expected/cost strings")
ok(g.verdicts[1].cost == "+500 ms auto" and g.verdicts[1].ghost and g.verdicts[1].ghost.sym == "m",
   "won't-fit cost carries the clip ms, ghost is the Multi (" .. tostring(g.verdicts[1].cost) .. ")")
ok(g.verdicts[3].ghost and g.verdicts[3].ghost.sym == "s" and g.verdicts[3].ghost.t0 == 3.0, "late ghost is the shot that fit, at the free moment")
ok(score.analysis[1] and score.analysis[1].code == "STEADY_WONT_FIT" and type(score.analysis[1].advice) == "string",
   "the top row is the decision, not the clip (" .. tostring(score.analysis[1] and score.analysis[1].code) .. ")")
ok(score.topFix == nil, "topFix is gone: the review reads analysis, and one list beats a list plus a duplicate")
ok(#score.analysis == 2 and score.analysis[1].ms == 500 and score.analysis[2].code == "LATE" and score.analysis[2].ms == 200,
   "the attributed clip is not double-counted (" .. tostring(#score.analysis) .. " rows)")

-- 28. A won't-fit whose shot went out CLEAN owns no clip: it is closed at that
--     auto, and an unrelated clip later stays its own fault.
g = newGm()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "press", key = "steady", result = "ok", ctx = ctx(0.8) })
G.Feed(g, { t = 2.0, kind = "auto", delay = 0 })                       -- clean: nothing to attribute
G.Feed(g, { t = 4.6, kind = "auto", delay = 0.3, cause = "cast" })     -- an unrelated clip much later
G.Feed(g, { t = 6.0, kind = "stop" })
score = G.Finish(g)
ok(g.verdicts[1].cost == "no clip (shot went out)" and g.verdicts[1].ms == 0,
   "clean shot closes the won't-fit (" .. tostring(g.verdicts[1].cost) .. ")")
ok(g.verdicts[2].code == "CLIP" and g.verdicts[2].attributed == nil, "the later clip is not attributed")
-- The French paper budgets a delay of its own at that cycle position, so the
-- fault is the EXCESS over it (~249 of the 300 ms), not the whole delay.
ok(#score.analysis == 2 and score.analysis[1].code == "CLIP"
   and score.analysis[1].ms > 200 and score.analysis[1].ms <= 300,
   "the unattributed clip still stands as its own fault (" .. tostring(score.analysis[1].code)
   .. " " .. tostring(score.analysis[1].ms) .. ")")

-- 29. Two won't-fits back to back: the first is closed, only the second takes
--     the clip that follows it.
g = newGm()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 1.0, kind = "press", key = "steady", result = "ok", ctx = ctx(0.8) })
G.Feed(g, { t = 1.5, kind = "press", key = "steady", result = "ok", ctx = ctx(0.8) })
G.Feed(g, { t = 2.0, kind = "auto", delay = 0.4, cause = "cast" })
G.Feed(g, { t = 4.0, kind = "stop" })
G.Finish(g)
ok(g.verdicts[1].cost == "no clip (shot went out)" and g.verdicts[2].cost == "+400 ms auto" and g.verdicts[3].attributed,
   "consecutive won't-fits: only the second owns the clip (" .. tostring(g.verdicts[1].cost) .. ")")

-- 30. WindowsSoFar: the live timeline needs the open haste window closed at
--     `now`, and the real end must still win when the fight actually stops.
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 3, kind = "haste", rangedMul = 1.93, qs = false, rf = true, lust = false, drums = false })
local wins = G.WindowsSoFar(g, 5)
ok(wins == g.windows and #wins == 2, "WindowsSoFar hands back the windows array itself")
ok(wins[1].t1 == 3 and wins[2].t1 == 5, "WindowsSoFar closes the open window at now")
ok(G.WindowsSoFar(g, 6)[2].t1 == 6, "a later call moves the open window's end forward")
G.Feed(g, { t = 7, kind = "stop" })
score = G.Finish(g)
ok(score.windows[2].t1 == 7, "Finish still sets the real end (" .. tostring(score.windows[2].t1) .. ")")
ok(score.windows[1].t1 == 3, "the window that was already closed is untouched")

-- 31. Grade: the cycles-on-paper bands, and the clip cap
ok(G.Grade(0.96) == "A+", "0.96 is A+ (" .. G.Grade(0.96) .. ")")
ok(G.Grade(0.92) == "A", "0.92 is A (" .. G.Grade(0.92) .. ")")
ok(G.Grade(0.86) == "B+", "0.86 is B+ (" .. G.Grade(0.86) .. ")")
ok(G.Grade(0.80) == "B", "0.80 is B (" .. G.Grade(0.80) .. ")")
ok(G.Grade(0.65) == "C", "0.65 is C (" .. G.Grade(0.65) .. ")")
ok(G.Grade(0.5) == "D" and G.Grade(0) == "D", "under 60 % is D")
ok(G.Grade(0.95) == "A+" and G.Grade(0.90) == "A" and G.Grade(0.85) == "B+"
   and G.Grade(0.75) == "B" and G.Grade(0.60) == "C", "each band opens at its floor")
ok(G.Grade(nil) == "D", "no number grades D")
-- Three clips or more caps at B, whatever the cycles say; two do not.
ok(G.Grade(1.0, 3) == "B" and G.Grade(0.96, 4) == "B" and G.Grade(0.86, 9) == "B",
   "three clips cap the grade at B (" .. G.Grade(1.0, 3) .. ")")
ok(G.Grade(1.0, 2) == "A+", "two clips do not cap (" .. G.Grade(1.0, 2) .. ")")
ok(G.Grade(0.65, 5) == "C" and G.Grade(0.2, 5) == "D", "the cap never RAISES a grade")
-- ...and Finish carries it on the scorecard.
g = newG()
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0.36, kind = "auto", delay = 0 })
G.Feed(g, { t = 4.35, kind = "stop" })
score = G.Finish(g)
local cp = score.cyclesOnPaper
ok(score.grade == G.Grade(cp.total > 0 and cp.ok / cp.total or 0, score.clips),
   "Finish sets score.grade from cycles on paper (" .. tostring(score.grade) .. ")")
ok(score.dmgPct == nil and score.dmgPaper == nil and score.dmgBasis == nil and G.DMG_BASIS == nil,
   "the vs-paper damage family is gone from the scorecard")

-- 32. The grader's origin is the PULL event, never the moment Start was
--     pressed: an engine that sat armed for 30 s hands it a stream that opens
--     at the first press, and the fight it grades is only what came after.
local eLate = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, queueWindow = 0.4 })
E.StartFight(eLate, 0)
E.SetDistance(eLate, 7)
for t = 0, 30, 0.1 do E.Step(eLate, t) end
E.Press(eLate, { "autoshot", "steady" }, 30)
for t = 30, 40, 0.01 do E.Step(eLate, t) end
E.StopFight(eLate, 40)
local gLate = newG()
for i = 1, eLate.n do G.Feed(gLate, eLate.events[i]) end
ok(eLate.events[1].kind == "pull" and eLate.events[1].t == 30, "the armed stretch leaves no events before the pull")
ok(gLate.t0 == 30, "the grader's t0 is the pull (" .. tostring(gLate.t0) .. ")")
local scoreLate = G.Finish(gLate)
ok(near(scoreLate.fightTime, 10), "the graded fight is 10 s long, not 40 (" .. tostring(scoreLate.fightTime) .. ")")
ok(scoreLate.windows[1].t0 == 30, "the first haste window opens at the pull")

-- 33. The opener's Steady window starts at the first SHOT press, not at the
--     pull. Opening on a start-attack key ("/cast !Auto Shot", "/startattack")
--     is a real press — it is what pulls — but it is not a shot, and grading
--     the Steady against it failed the arm-then-cast opener every time.
local opOpts = { anchor = "pull", gcds = 2, steadySec = 0.5, cds = {} }
local function openerG(opts)
  return G.New({ model = M, h = H, notation = "1:1", damage = DMG, opener = opts })
end
g = openerG(opOpts)
G.Feed(g, { t = 0, kind = "pull" })                       -- the start-attack press
G.Feed(g, { t = 0.36, kind = "auto", delay = 0 })
G.Feed(g, { t = 1.2, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })
G.Feed(g, { t = 2.29, kind = "cast", spell = "steady", t0 = 1.2, t1 = 2.29 })
G.Feed(g, { t = 4.0, kind = "stop" })
score = G.Finish(g)
ok(score.opener.steadyOk and score.opener.ok,
   "start-attack pull: the Steady is graded from the first shot press, not the pull")
ok(near(score.opener.firstSteady, 1.2),
   "...and the scorecard still reports it from the fight's own zero")

-- A Steady pull is unchanged: the first shot press IS the pull.
g = openerG(opOpts)
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })
G.Feed(g, { t = 1.09, kind = "cast", spell = "steady", t0 = 0, t1 = 1.09 })
G.Feed(g, { t = 4.0, kind = "stop" })
score = G.Finish(g)
ok(score.opener.steadyOk and score.opener.ok, "a Steady pull still passes")

-- ...and a Steady that is genuinely late after the opening MULTI still fails:
-- the window moved, it did not go away.
g = openerG(opOpts)
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0, kind = "press", key = "multi", result = "ok", ctx = ctx(1.8) })
G.Feed(g, { t = 0.4, kind = "cast", spell = "multi", t0 = 0, t1 = 0.4 })
G.Feed(g, { t = 3.0, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })
G.Feed(g, { t = 4.09, kind = "cast", spell = "steady", t0 = 3.0, t1 = 4.09 })
G.Feed(g, { t = 5.0, kind = "stop" })
score = G.Finish(g)
ok(not score.opener.steadyOk and not score.opener.ok, "a Steady three seconds late still fails")

-- The COOLDOWN anchor stays on the pull: a trinket popped WITH the start-attack
-- key is on time, and would read as EARLY against a shot-press anchor.
g = openerG({ anchor = "pull", gcds = 2, steadySec = 0.5, cds = { RF = true } })
G.Feed(g, { t = 0, kind = "pull" })
G.Feed(g, { t = 0.05, kind = "cd", key = "RF", used = true })
G.Feed(g, { t = 1.2, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })
G.Feed(g, { t = 2.29, kind = "cast", spell = "steady", t0 = 1.2, t1 = 2.29 })
G.Feed(g, { t = 4.0, kind = "stop" })
score = G.Finish(g)
ok(score.opener.cds.RF.ok and not score.opener.cds.RF.early and score.opener.ok,
   "a cooldown pressed with the start-attack key is on time, not early")
ok(not codes(g):find("EARLY"), "...and no EARLY verdict is raised for it (" .. codes(g) .. ")")

-- End to end through the real engine: "/cast !Auto-Shot" + "/startattack",
-- then Steady.
local eArm = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, queueWindow = 0.4 })
E.StartFight(eArm, 0)
E.SetDistance(eArm, 7)
E.Press(eArm, { "autoshot", "startattack" }, 0)
for t = 0, 1.2, 0.01 do E.Step(eArm, t) end
E.Press(eArm, { "steady", "autoshot" }, 1.2)
for t = 1.2, 8, 0.01 do E.Step(eArm, t) end
E.StopFight(eArm, 8)
local gArm = openerG(opOpts)
for i = 1, eArm.n do G.Feed(gArm, eArm.events[i]) end
local armScore = G.Finish(gArm)
ok(gArm.t0 == 0 and gArm.firstShotPressT ~= nil and gArm.firstShotPressT > 0.5,
   "engine: the pull is the start-attack press and the first shot press comes later ("
   .. tostring(gArm.firstShotPressT) .. ")")
ok(armScore.opener.steadyOk and armScore.opener.ok,
   "engine: an arm-then-Steady opener grades ok")

-- A stream with NO `pull` in it has no origin, and the scorecard says so rather
-- than measuring from a literal zero: every field counted from the origin came
-- back as the raw GetTime() clock ("Opener: Steady 305232320.92s"). The
-- efficiencies go with them -- a rate over an unmeasurable span is not a number
-- either. With a pull the very same stream reads as small relative seconds.
do
local CLOCK = 305232320.92
local function feedFight(withPull)
  local gg = G.New({ model = M, h = H, notation = "1:1", damage = DMG, clipMin = 0.03, reaction = 0.15 })
  if withPull then G.Feed(gg, { t = CLOCK, kind = "pull" }) end
  G.Feed(gg, { t = CLOCK + 0.36, kind = "auto", delay = 0 })
  G.Feed(gg, { t = CLOCK + 1.09, kind = "cast", spell = "steady", t0 = CLOCK + 0.3, t1 = CLOCK + 1.09 })
  G.Feed(gg, { t = CLOCK + 8, kind = "stop" })
  return G.Finish(gg)
end
local noPull = feedFight(false)
ok(noPull.opener.firstSteady == nil and noPull.opener.firstAuto == nil,
   "no pull: the opener's offsets are nil, never the absolute clock (got "
   .. tostring(noPull.opener.firstSteady) .. ")")
ok(noPull.t0 == nil and noPull.fightTime == nil, "no pull: no origin and no fight time")
ok(noPull.autoEff == nil and noPull.gcdEff == nil and noPull.weaveEff == nil,
   "no pull: the efficiencies are nil too")
local withPull = feedFight(true)
ok(near(withPull.opener.firstAuto, 0.36) and near(withPull.opener.firstSteady, 0.3),
   "with a pull the same stream reads as small relative seconds")
ok(withPull.t0 == CLOCK and near(withPull.fightTime, 8), "...off the pull's own origin")
ok(withPull.autoEff and withPull.autoEff > 0, "...and the efficiencies are real numbers")
end

-- 33. Advice times are FIGHT-RELATIVE, at one decimal, and carry no glyph the
--     review's font may not have. The strings are read beside a timeline whose
--     zero is the pull, so an absolute GetTime() stamp ("the wind-up at
--     305232320.92 s") was unreadable; a stream with no pull has no origin and
--     draws the em dash the rest of the scorecard draws.
do
local CLOCK2 = 305232320.92
-- A WEAVE notation, because one of the three advice strings under test belongs
-- to WEAVE_MISSED and the paper is the scope: on a paper with no `w` the
-- grader no longer raises it at all (section 36).
local function adviceFight(withPull)
  -- ...and a paper that writes `m`/`A` as well, since STEADY_WONT_FIT names the
  -- Multi it would have taken (R3a: the paper is the scope for that half too).
  -- `6:9:1:1 3w` rather than the French weave string because this fixture reads
  -- the CLIP's advice back verbatim: the French weave period budgets ~0.49 s of
  -- delay on its first auto (R3b's wrap budget), which would eat the 0.5 s this
  -- stream clips by, while 6:9:1:1 3w budgets nothing at this haste.
  local gg = G.New({ model = M, h = H, notation = "6:9:1:1 3w", damage = DMG, clipMin = 0.03,
                     reaction = 0.15, oppMin = 0.4, legMax = 0.4 })
  if withPull then G.Feed(gg, { t = CLOCK2, kind = "pull" }) end
  G.Feed(gg, { t = CLOCK2 + 1.0, kind = "press", key = "steady", result = "ok", ctx = ctx(0.8) })
  G.Feed(gg, { t = CLOCK2 + 2.0, kind = "auto", delay = 0.5, cause = "cast" })
  G.Feed(gg, { t = CLOCK2 + 3.0, kind = "free", ctx = ctx(1.8) })
  G.Feed(gg, { t = CLOCK2 + 3.2, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })
  G.Feed(gg, { t = CLOCK2 + 4.0, kind = "opp", open = true })
  G.Feed(gg, { t = CLOCK2 + 5.0, kind = "opp", open = false })
  G.Feed(gg, { t = CLOCK2 + 6.0, kind = "stop" })
  G.Finish(gg)
  return gg
end
local function byCode(gg, code)
  for i = 1, #gg.verdicts do
    if gg.verdicts[i].code == code then return gg.verdicts[i] end
  end
end
local ga = adviceFight(true)
local vClip, vLate, vMiss = byCode(ga, "CLIP"), byCode(ga, "LATE"), byCode(ga, "WEAVE_MISSED")
ok(vClip and vLate and vMiss, "advice fight produced CLIP, LATE and WEAVE_MISSED")
-- 2.0 - 0.5 - 0.5/1.38 = 1.1377 -> one decimal, relative to the pull.
ok(vClip.expected == "the wind-up at 1.1 s", "clip names the wind-up relative to the pull (" .. tostring(vClip.expected) .. ")")
ok(vLate.expected == "Steady Shot at 3.0 s (it fit)", "late names the free moment relative to the pull (" .. tostring(vLate.expected) .. ")")
ok(vMiss.expected == "weave: in, hit, out before 5.0 s", "weave-missed deadline is relative too (" .. tostring(vMiss.expected) .. ")")
ok(not vClip.expected:find("305232", 1, true) and not vLate.expected:find("305232", 1, true),
   "no advice string leaks the absolute clock")
-- Durations in the same strings are one decimal as well.
local vFit = byCode(ga, "STEADY_WONT_FIT")
ok(vFit and vFit.did == "Steady Shot (1.1 s) with 0.8 s to the wind-up",
   "won't-fit durations are one decimal (" .. tostring(vFit and vFit.did) .. ")")
ok(vFit.expected == "Multi-Shot (0.4 s) fits — Steady after the auto",
   "so is the ghost's cast time (" .. tostring(vFit.expected) .. ")")
-- No origin: a dash, never a number measured from a zero that does not exist.
local gn = adviceFight(false)
local nClip, nLate, nMiss = byCode(gn, "CLIP"), byCode(gn, "LATE"), byCode(gn, "WEAVE_MISSED")
ok(nClip.expected == "the wind-up at \226\128\148", "no pull: the clip's stamp is an em dash (" .. tostring(nClip.expected) .. ")")
ok(nLate.expected == "Steady Shot at \226\128\148 (it fit)", "no pull: so is the late one")
ok(nMiss.expected == "weave: in, hit, out before \226\128\148", "no pull: and the weave deadline")
-- U+2713 / U+2715 / U+2717 all start "\226\156": no verdict string may carry one,
-- because they are drawn in the user's LibSharedMedia font and most faces
-- (Numen included) have no glyph for them — the review painted empty boxes.
local gw = newGW()
G.Feed(gw, { t = 0, kind = "pull" })
G.Feed(gw, { t = 1.0, kind = "weave", edge = "down" })
G.Feed(gw, { t = 1.2, kind = "melee", hit = "r" })
G.Feed(gw, { t = 1.5, kind = "weave", edge = "up", cost = 0 })
G.Feed(gw, { t = 1.5, kind = "weave", edge = "done",
             legs = { stepIn = 0.2, dwell = 0, stepOut = 0.3, total = 0.5, budget = 1.2, backIn = false, backOut = false, hit = "r" } })
G.Feed(gw, { t = 3, kind = "stop" })
G.Finish(gw)
local clean = true
local function scan(gg)
  for i = 1, #gg.verdicts do
    local v = gg.verdicts[i]
    for _, s in ipairs({ v.text, v.did, v.expected, v.cost }) do
      if type(s) == "string" and s:find("\226\156", 1, true) then clean = false end
    end
  end
end
scan(ga); scan(gn); scan(gw)
ok(clean, "no verdict string carries a check/cross/multiplication-X glyph")
end

-- 34. PER-NOTE JUDGMENTS. The paper is laid out per haste window and split into
--     auto-to-auto cycles; every cast start and melee hit is matched against the
--     nearest unconsumed note of its own symbol class inside its cycle, and what
--     is left over at the cycle's close is MISSED (a note nobody played) or OFF
--     (a press the paper had no note for).
do
local TL = dofile("Core/PracticeTimeline.lua")
local HJ = { ws = 3.0, rangedMul = 1.38, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0 }
local FRENCH = "5:5:1:1"          -- the French family, and the practice default
local SPELL = { s = "steady", m = "multi", A = "arcane" }

local function judgeG(nota)
  return G.New({ model = M, h = HJ, notation = nota, damage = DMG, clipMin = 0.03,
                 reaction = 0.15, timeline = TL })
end

-- The IDEAL stream for a notation, built from the very layout the grader lays
-- its paper out from: autos at their releases, casts at their layout starts,
-- melee at their weave slots. Every delta is therefore exactly zero unless the
-- caller's `tweak` moves something. Returned in emission order (a cast is
-- emitted at its END, which is what puts it behind the auto that released
-- during it — the ordering the grader has to survive).
local function paperStream(nota, periods, tweak)
  local lay = M.Layout(M.STRINGS[nota], HJ, 0)
  local evs = {}
  for p = 0, periods - 1 do
    for i = 1, #lay.ev do
      local pe = lay.ev[i]
      local t0 = p * lay.dur + pe.t0
      if pe.sym == "a" then
        evs[#evs + 1] = { t = t0 + pe.dur, kind = "auto", delay = 0, _sym = "a", _p = p, _i = i }
      elseif SPELL[pe.sym] then
        evs[#evs + 1] = { t = t0 + pe.dur, kind = "cast", spell = SPELL[pe.sym], t0 = t0,
                          t1 = t0 + pe.dur, _sym = pe.sym, _p = p, _i = i }
      elseif pe.sym == "w" or pe.sym == "r" then
        evs[#evs + 1] = { t = t0, kind = "melee", hit = "r", _sym = pe.sym, _p = p, _i = i }
      end
    end
  end
  if tweak then evs = tweak(evs, lay) or evs end
  table.sort(evs, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.kind < b.kind end)
  local out = { { t = 0, kind = "pull" } }
  for i = 1, #evs do out[#out + 1] = evs[i] end
  out[#out + 1] = { t = periods * lay.dur, kind = "stop" }
  return out, lay
end

-- The stream goes into Finish as well as through Feed: that is how the
-- scorecard's cycles on paper are built (T.Cycles, order-aware).
local function feedAll(gg, evs)
  for i = 1, #evs do G.Feed(gg, evs[i]) end
  return G.Finish(gg, evs, #evs)
end

-- Every judgment of a grade, and the judgments in order.
local function judgments(gg)
  local out = {}
  for i = 1, #gg.verdicts do
    local v = gg.verdicts[i]
    if v.kind == "judge" then out[#out + 1] = v end
  end
  return out
end
local function grades(gg)
  local out = {}
  for _, v in ipairs(judgments(gg)) do out[#out + 1] = v.grade end
  return table.concat(out, ",")
end
local function counts(gg)
  local j = gg.judge
  return ("P%d G%d L%d C%d M%d O%d"):format(j.perfect, j.good, j.late, j.clip, j.missed, j.off)
end

-- (a) A clean French stream: every note PERFECT, and the streak is the run.
local gj = judgeG(FRENCH)
local evs = paperStream(FRENCH, 3)
local sj = feedAll(gj, evs)
local nJ = #judgments(gj)
ok(nJ > 0 and gj.judge.perfect == nJ, "clean French: every note PERFECT ("
   .. counts(gj) .. " over " .. tostring(nJ) .. " notes)")
ok(gj.streak == nJ and gj.bestStreak == nJ, "clean French: the streak is the whole run ("
   .. tostring(gj.streak) .. ")")
ok(sj.bestStreak == nJ and sj.judge == gj.judge, "the scorecard carries the streak and the counts")
ok(sj.cyclesOnPaper.total > 0 and sj.cyclesOnPaper.ok == sj.cyclesOnPaper.total,
   "clean French: every judged cycle is on paper (" .. sj.cyclesOnPaper.ok .. "/"
   .. sj.cyclesOnPaper.total .. ")")
ok(sj.grade == "A+", "clean French grades A+ (" .. tostring(sj.grade) .. ")")

-- ...and the notes carry the conveyor's own keys, so a view can find the frame
-- a judgment belongs to. Same scheme, one function: T.NoteKey.
local first = judgments(gj)[1]
local layF = M.Layout(M.STRINGS[FRENCH], HJ, 0)
ok(first.note and first.note.key == TL.NoteKey(first.cycle, 1),
   "the first note carries the paper key of its cycle and seat order (" .. tostring(first.note.key) .. ")")
local seen, dup = {}, false
for _, v in ipairs(judgments(gj)) do
  if v.note.key then
    if seen[v.note.key] then dup = true end
    seen[v.note.key] = true
  end
end
ok(not dup, "no two notes of a fight share a key")

-- (b) One Steady 0.2 s late is still GOOD; 0.5 s late is LATE and kills the streak.
local function shiftNth(sym, nth, by)
  return function(evs2)
    local seen2 = 0
    for i = 1, #evs2 do
      local e2 = evs2[i]
      if e2._sym == sym then
        seen2 = seen2 + 1
        if seen2 == nth then e2.t0 = e2.t0 + by; e2.t1 = e2.t1 + by; e2.t = e2.t + by end
      end
    end
  end
end
local gGood = judgeG(FRENCH)
feedAll(gGood, (paperStream(FRENCH, 3, shiftNth("s", 3, 0.2))))
ok(gGood.judge.good == 1 and gGood.judge.late == 0, "a Steady 0.2 s late is GOOD (" .. counts(gGood) .. ")")
ok(gGood.streak > 0 and gGood.bestStreak == #judgments(gGood),
   "...and GOOD keeps the streak running (" .. tostring(gGood.streak) .. ")")
local gLate = judgeG(FRENCH)
feedAll(gLate, (paperStream(FRENCH, 3, shiftNth("s", 3, 0.5))))
ok(gLate.judge.late == 1 and gLate.judge.good == 0, "a Steady 0.5 s late is LATE (" .. counts(gLate) .. ")")
local cur, best = 0, 0
for _, v in ipairs(judgments(gLate)) do
  if v.grade == "PERFECT" or v.grade == "GOOD" then cur = cur + 1; if cur > best then best = cur end
  else cur = 0 end
end
ok(gLate.streak == cur and gLate.bestStreak == best and best < #judgments(gLate),
   "...and it resets the streak (" .. tostring(gLate.streak) .. " now, best " .. tostring(gLate.bestStreak) .. ")")

-- (c) A Multi where the paper says Steady: OFF for the press, MISSED for the note.
local gOff = judgeG("1:1")
feedAll(gOff, (paperStream("1:1", 3, function(evs2)
  for i = 1, #evs2 do
    if evs2[i]._sym == "s" and evs2[i]._p == 1 then evs2[i].spell = "multi" end
  end
end)))
ok(gOff.judge.off == 1 and gOff.judge.missed == 1,
   "a Multi on a Steady note is OFF plus MISSED (" .. counts(gOff) .. ")")
local offV, missV
for _, v in ipairs(judgments(gOff)) do
  if v.grade == "OFF" then offV = v elseif v.grade == "MISSED" then missV = v end
end
ok(offV and offV.note.sym == "m" and offV.note.key == nil,
   "the OFF verdict carries the press, and no paper key (there is no note)")
ok(missV and missV.note.sym == "s" and missV.note.key ~= nil and missV.cycle == offV.cycle,
   "the MISSED verdict carries the paper note, its key and the same cycle")

-- (d) A weave that never happened: MISSED on the `w` note, and only there.
local WEAVE = "2:2 1w"
local gW = judgeG(WEAVE)
feedAll(gW, (paperStream(WEAVE, 3, function(evs2)
  for i = #evs2, 1, -1 do
    if evs2[i].kind == "melee" and evs2[i]._p == 1 then table.remove(evs2, i) end
  end
end)))
ok(gW.judge.missed == 1 and gW.judge.off == 0, "a dropped weave is one MISSED (" .. counts(gW) .. ")")
local wMiss
for _, v in ipairs(judgments(gW)) do if v.grade == "MISSED" then wMiss = v end end
ok(wMiss and wMiss.note.sym == "w", "and it is the `w` note that is missed (" .. tostring(wMiss and wMiss.note.sym) .. ")")
-- A played Raptor takes a `w` slot (the paper only ever writes `w`), which is
-- why every OTHER weave cycle judged clean.
ok(gW.judge.perfect > 0, "a Raptor fills the paper's weave slot")

-- (e) A clip attaches to the note the cast was played on — no separate PERFECT
--     beside it, and the clip's own ms rides the judgment.
local gC = judgeG("1:1")
feedAll(gC, (paperStream("1:1", 3, function(evs2)
  local nAuto = 0
  for i = 1, #evs2 do
    if evs2[i].kind == "auto" then
      nAuto = nAuto + 1
      if nAuto == 2 then evs2[i].delay = 0.12; evs2[i].cause = "cast"; evs2[i].t = evs2[i].t + 0.12 end
    end
  end
end)))
ok(gC.judge.clip == 1, "the clipped cast is judged CLIP, once (" .. counts(gC) .. ")")
local clipV
for _, v in ipairs(judgments(gC)) do if v.grade == "CLIP" then clipV = v end end
ok(clipV and clipV.deltaMs == 120 and clipV.note.sym == "s" and clipV.note.key ~= nil,
   "the CLIP judgment carries the clip's ms and the note it belongs to (" .. tostring(clipV and clipV.deltaMs) .. ")")

-- (f) cyclesOnPaper agrees with T.Cycles, the review row's own reading of the
--     same stream: same boundaries, same paper, same trailing-cycle rule.
local function cyclesAgree(nota, tweak)
  local gg = judgeG(nota)
  local stream = paperStream(nota, 3, tweak)
  local sc = feedAll(gg, stream)
  local cyc = TL.Cycles(stream, #stream, sc, HJ, M, {})
  local okC, total = 0, 0
  for i = 1, cyc.n do
    if not cyc[i].partial then
      total = total + 1
      if cyc[i].ok then okC = okC + 1 end
    end
  end
  return sc.cyclesOnPaper, okC, total
end
local cp, tOk, tTot = cyclesAgree(FRENCH)
ok(cp.ok == tOk and cp.total == tTot, "clean: cyclesOnPaper == T.Cycles ("
   .. cp.ok .. "/" .. cp.total .. " vs " .. tOk .. "/" .. tTot .. ")")
cp, tOk, tTot = cyclesAgree("1:1", function(evs2)
  for i = 1, #evs2 do
    if evs2[i]._sym == "s" and evs2[i]._p == 1 then evs2[i].spell = "multi" end
  end
end)
ok(cp.ok == tOk and cp.total == tTot and cp.ok < cp.total,
   "one wrong shot: cyclesOnPaper == T.Cycles (" .. cp.ok .. "/" .. cp.total
   .. " vs " .. tOk .. "/" .. tTot .. ")")

-- (g) Judgments are NOT faults: they never reach the analysis rows or the
--     timeline's marks, even with okMarks on.
local gm = judgeG("1:1")
local sm = feedAll(gm, (paperStream("1:1", 3, function(evs2)
  for i = 1, #evs2 do
    if evs2[i]._sym == "s" and evs2[i]._p == 1 then evs2[i].spell = "multi" end
  end
end)))
ok(#sm.analysis == 0 and gm.judge.off == 1,
   "a wrong shot is a judgment, not a fault row (" .. tostring(#sm.analysis) .. " rows)")
local tl = TL.Build({}, 0, sm, HJ, { okMarks = true }, gm.verdicts)
local judgeMark = false
for _, mk in ipairs(tl.marks) do
  if mk.code == nil or mk.code == "MISSED" or mk.code == "OFF" then judgeMark = true end
end
ok(not judgeMark, "no judgment reaches the timeline's marks (" .. tostring(#tl.marks) .. " marks)")

-- (h) Live: the panel reads the streak and the counters off the same numbers.
local liveJ = {}
G.Live(gj, 10, liveJ)
ok(liveJ.streak == gj.streak and liveJ.bestStreak == gj.bestStreak and liveJ.judge == gj.judge,
   "Live exposes the streak and the judgment counters")
ok(liveJ.cyclesOkApprox == gj.cyclesOk and liveJ.cyclesTotalApprox == gj.cyclesTotal,
   "Live exposes the running (symbol-only) cycle count, named as the approximation it is")

-- (i) The top fixes are capped at three and name the cycle they first happened in.
local gA = newG()
G.Feed(gA, { t = 0, kind = "pull" })
G.Feed(gA, { t = 0.36, kind = "auto", delay = 0 })
G.Feed(gA, { t = 1.0, kind = "press", key = "steady", result = "ok", ctx = ctx(0.8) })
G.Feed(gA, { t = 2.6, kind = "auto", delay = 0.5, cause = "cast" })
G.Feed(gA, { t = 3.0, kind = "free", ctx = ctx(1.8) })
G.Feed(gA, { t = 3.4, kind = "press", key = "steady", result = "ok", ctx = ctx(1.8) })
G.Feed(gA, { t = 4.8, kind = "deadzone" })
G.Feed(gA, { t = 5.0, kind = "opp", open = true })
G.Feed(gA, { t = 6.0, kind = "opp", open = false })
G.Feed(gA, { t = 7.0, kind = "stop" })
local sA = G.Finish(gA)
ok(#sA.analysis <= 3, "the analysis is the top three fixes (" .. tostring(#sA.analysis) .. ")")
ok(sA.analysis[1].cycle ~= nil and sA.analysis[1].cycle >= 0,
   "each fix names the cycle it first happened in (" .. tostring(sA.analysis[1].cycle) .. ")")

-- (j) A stream with no haste window behind it has no paper: nothing is judged,
--     rather than every press reading as OFF against an empty rotation.
local gNo = judgeG("1:1")
G.Feed(gNo, { t = 0.36, kind = "auto", delay = 0 })
G.Feed(gNo, { t = 1.45, kind = "cast", spell = "steady", t0 = 0.36, t1 = 1.45 })
G.Feed(gNo, { t = 4.0, kind = "stop" })
local sNo = G.Finish(gNo)
ok(#judgments(gNo) == 0 and sNo.cyclesOnPaper.total == 0,
   "no pull, no paper, no judgments (" .. tostring(#judgments(gNo)) .. ")")

-- (k) Through the REAL engine, which is where the two files' event shapes have
--     to agree: a 15 s Steady mash pushes casts past the autos that released
--     during them (the ordering the cycle lag exists for), clips three shots and
--     double-presses three cycles — and the grader's cycles on paper are exactly
--     the review row's (T.Cycles) reading of the same stream, haste windows and
--     all.
local eng = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, queueWindow = 0.4 })
E.StartFight(eng, 0)
E.Press(eng, { "autoshot", "steady" }, 0)
local tt, nextP = 0, 0.05
while tt <= 15 + 1e-9 do
  if tt >= nextP - 1e-9 then E.Press(eng, { "steady" }, tt); nextP = nextP + 0.05 end
  E.Step(eng, tt)
  tt = tt + 0.01
end
E.StopFight(eng, 15)
local gE = judgeG("1:1")
for i = 1, eng.n do G.Feed(gE, eng.events[i]) end
local sE = G.Finish(gE, eng.events, eng.n)
local cycE = TL.Cycles(eng.events, eng.n, sE, HJ, M, {})
local eOk, eTot = 0, 0
for i = 1, cycE.n do
  if not cycE[i].partial then
    eTot = eTot + 1
    if cycE[i].ok then eOk = eOk + 1 end
  end
end
ok(sE.cyclesOnPaper.ok == eOk and sE.cyclesOnPaper.total == eTot and eTot > 0,
   "engine mash: cyclesOnPaper == T.Cycles (" .. sE.cyclesOnPaper.ok .. "/" .. sE.cyclesOnPaper.total
   .. " vs " .. eOk .. "/" .. eTot .. ")")
-- A MASH IS NOT ON THE BEAT, and the queue exemption does not pretend it is.
-- The client ignores a repeat press of the spell it already has queued, so the
-- press a queued cast is graded on is the FIRST of that episode — which a mash
-- makes the instant the previous cast frees the GCD, a long way from the note
-- the paper wrote. Extra presses are OFF, the notes themselves are off-beat,
-- and no streak survives: exactly the reading the three clips and T.Cycles'
-- own count above give this stream.
ok(#judgments(gE) >= eTot and gE.judge.off > 0 and gE.judge.late > 0,
   "engine mash: the extra presses are OFF and the notes are off the beat (" .. counts(gE) .. ")")
ok(sE.bestStreak >= 0 and sE.bestStreak <= #judgments(gE), "engine mash: a real best streak ("
   .. tostring(sE.bestStreak) .. ")")
-- Every judged note that HAS a paper note carries a key, in the paper block,
-- keyed by its cycle (a haste window change moves notes, never re-keys them).
local keyed, cycles = 0, {}
for _, v in ipairs(judgments(gE)) do
  if v.grade ~= "OFF" then
    keyed = keyed + (v.note.key and 1 or 0)
    if v.note.key then cycles[math.floor((v.note.key - TL.KEY.PAPER) / TL.KEY.PAPER_SLOTS)] = true end
  end
end
ok(keyed == #judgments(gE) - gE.judge.off, "every note judgment carries its paper key")
ok(next(cycles) ~= nil, "and those keys sit in the paper block (cycle " .. tostring(next(cycles)) .. ")")

-- (l) THE KEYS ACTUALLY MEET. Not "the grader's key equals T.NoteKey(1, ...)" --
--     that only proves the grader agrees with itself. The conveyor is built the
--     way the view builds it (one `out` kept across fights, opts.paper from the
--     grader's current window, live from the engine's snapshot) and asked which
--     paper items it drew; every judged note inside the strip's window must be
--     one of them. The shared `out` is the point: the view's cache lives for the
--     session while the grader is new every pull, which is exactly what the two
--     private generation counters used to disagree about.
local convOut = nil
local snapE, liveE, phE, paperE, optsE = {}, {}, {}, {}, {}
-- The paper items the strip draws are THE PLAN's (v3 P1): built here the way
-- Practice:PublishPlan builds it, from the same grader and snapshot.
local PP = dofile("Core/PracticePlan.lua")
local planE, srcE = PP.New(), { model = M, seat = G.SeatCycle, T = TL, castCorr = 1 }
local function planFor(gg, sn, now, past, future)
  srcE.now, srcE.live, srcE.pulled, srcE.t0 = now, true, sn.pulled == true, sn.t0 or 0
  srcE.past, srcE.future = past, future
  srcE.cycle, srcE.windup = sn.cycle, sn.windup
  srcE.nextShotAt, srcE.lastShotAt, srcE.rangedMul = sn.nextShotAt, sn.lastShotAt, sn.rangedMul
  srcE.msReadyAt, srcE.arcReadyAt = sn.msReadyAt, sn.arcReadyAt
  srcE.weaveAt, srcE.weaveRoom, srcE.weaveFits = sn.weaveAt, sn.weaveRoom, sn.weaveFits
  srcE.oppOpen, srcE.meleeReadyAt = false, sn.meleeReadyAt
  srcE.paperSyms = gg.win and G.PaperSyms(gg) or nil
  srcE.cur, srcE.pend, srcE.winAutos = gg.cur, gg.pend, (gg.win and gg.win.autos) or 0
  srcE.lay = G.Layout(gg)
  srcE.notation = gg.win and gg.win.notation or nil
  return PP.Build(srcE, planE)
end
local function fightWithStrip(seconds, at)
  local en = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, queueWindow = 0.4 })
  E.StartFight(en, 0)
  E.Press(en, { "autoshot", "steady" }, 0)
  local gg = judgeG("1:1")
  local fed, strip = 0, nil
  local t2, nextPress2 = 0, 0.05
  while t2 <= seconds + 1e-9 do
    if t2 >= nextPress2 - 1e-9 then E.Press(en, { "steady" }, t2); nextPress2 = nextPress2 + 0.05 end
    E.Step(en, t2)
    while fed < en.n do fed = fed + 1; G.Feed(gg, en.events[fed]) end
    if math.abs(t2 - at) < 1e-9 then
      E.Snapshot(en, snapE)
      for k2, v2 in pairs(HJ) do phE[k2] = v2 end
      phE.rangedMul = snapE.rangedMul
      paperE.str = M.STRINGS[(gg.win and gg.win.notation) or "1:1"] or "as"
      paperE.h = phE
      optsE.past, optsE.future, optsE.windup = 2, 4.5, snapE.windup
      optsE.model, optsE.paper = M, paperE
      liveE.now, liveE.cycle, liveE.windup = t2, snapE.cycle, snapE.windup
      liveE.nextShotAt, liveE.lastShotAt = snapE.nextShotAt, snapE.lastShotAt
      liveE.rangedMul = snapE.rangedMul
      liveE.winAutos = (gg.win and gg.win.autos) or 0
      liveE.plan = planFor(gg, snapE, t2, 2, 4.5)
      convOut = TL.Strip(en.events, en.n, liveE, optsE, convOut)
      local keys2 = {}
      for i = 1, convOut.nItems do
        local it = convOut.items[i]
        if it.key and it.key >= TL.KEY.PAPER then keys2[it.key] = true end
      end
      strip = { now = t2, t1 = convOut.t1, keys = keys2 }
    end
    t2 = t2 + 0.01
  end
  E.StopFight(en, seconds)
  while fed < en.n do fed = fed + 1; G.Feed(gg, en.events[fed]) end
  G.Finish(gg, en.events, en.n)
  local hit, miss = 0, 0
  for _, v in ipairs(judgments(gg)) do
    if v.note.key and v.note.t0 > strip.now and v.note.t0 <= strip.t1 then
      if strip.keys[v.note.key] then hit = hit + 1 else miss = miss + 1 end
    end
  end
  return hit, miss
end
local h1, m1 = fightWithStrip(12, 8.0)
ok(h1 > 0 and m1 == 0, "fight 1: every judged note ahead of the cursor is one the conveyor drew ("
   .. h1 .. " hit, " .. m1 .. " missed)")
local h2, m2 = fightWithStrip(12, 8.0)
ok(h2 > 0 and m2 == 0, "fight 2 on the SAME conveyor: still every one (" .. h2 .. " hit, " .. m2 .. " missed)")
local h3, m3 = fightWithStrip(20, 14.0)
ok(h3 > 0 and m3 == 0, "fight 3, later in the fight: agreed (" .. h3 .. " hit, " .. m3 .. " missed)")

-- (m) ON PAPER MEANS IN PAPER ORDER. A Multi where the Steady goes and a Steady
--     where the Multi goes loses no note and gains no press, so the running
--     counter (a symbol tally) calls the cycle clean -- and it is not. The
--     scorecard's figure is T.Cycles', which reads the order.
local gSwap = judgeG(FRENCH)
local swapStream = paperStream(FRENCH, 3, function(evs2)
  local sEv, mEv
  for i = 1, #evs2 do
    local e2 = evs2[i]
    if e2._p == 0 and e2.kind == "cast" then
      if e2._sym == "s" and not sEv then sEv = e2 elseif e2._sym == "m" and not mEv then mEv = e2 end
    end
  end
  sEv.spell, mEv.spell = "multi", "steady"
end)
local sSwap = feedAll(gSwap, swapStream)
local swapCyc = TL.Cycles(swapStream, #swapStream, sSwap, HJ, M, {})
local sOk, sTot = 0, 0
for i = 1, swapCyc.n do
  if not swapCyc[i].partial then
    sTot = sTot + 1
    if swapCyc[i].ok then sOk = sOk + 1 end
  end
end
ok(gSwap.judge.missed == 0 and gSwap.judge.off == 0,
   "the swap loses no note and gains no press (" .. counts(gSwap) .. ")")
ok(sSwap.cyclesOnPaper.ok == sOk and sSwap.cyclesOnPaper.total == sTot,
   "the scorecard's cycles on paper are T.Cycles' (" .. sSwap.cyclesOnPaper.ok .. "/"
   .. sSwap.cyclesOnPaper.total .. " vs " .. sOk .. "/" .. sTot .. ")")
ok(sSwap.cyclesOnPaper.ok < gSwap.cyclesOk,
   "...and stricter than the running tally, which the swap passes ("
   .. sSwap.cyclesOnPaper.ok .. " vs " .. gSwap.cyclesOk .. ")")

-- (n) WHEN a judgment reaches the stream, not only what it says. The conveyor
--     pops what is at most T.POP_LIFE old, so a judgment that arrives a cycle
--     after the moment it carries is a judgment nobody ever sees.
local STEADY_CAST = M.CastTime(1.5, HJ.rangedMul, HJ.castCorr)
local gT = judgeG("1:1")
local tStream = paperStream("1:1", 3)
-- Fed one event at a time, so the stream POSITION of each judgment is known.
local pushedAt, autoIx = {}, {}
for i = 1, #tStream do
  local before = #gT.verdicts
  G.Feed(gT, tStream[i])
  for j = before + 1, #gT.verdicts do pushedAt[gT.verdicts[j]] = i end
  if tStream[i].kind == "auto" then autoIx[#autoIx + 1] = i end
end
G.Finish(gT, tStream, #tStream)
local worst, worstG = 0, nil
for _, v in ipairs(judgments(gT)) do
  local lag = v.t - v.note.t0
  if lag > worst then worst, worstG = lag, v.grade end
end
ok(worst <= STEADY_CAST + 0.05, "a played note is judged within one cast of the press ("
   .. ("%.3f"):format(worst) .. " s, " .. tostring(worstG) .. ")")
local firstPerfect
for _, v in ipairs(judgments(gT)) do
  if v.grade == "PERFECT" and not firstPerfect then firstPerfect = v end
end
ok(firstPerfect and pushedAt[firstPerfect] < autoIx[2],
   "the first PERFECT is in the stream before the next auto event (at " ..
   tostring(firstPerfect and pushedAt[firstPerfect]) .. ", auto 2 at " .. tostring(autoIx[2]) .. ")")

-- ...and a MISSED lands within the grace of the cycle it belongs to, ahead of
-- the next cycle's own grade rather than a cycle later.
local gM = judgeG("1:1")
local mStream = paperStream("1:1", 4, function(evs2)
  for i = #evs2, 1, -1 do
    if evs2[i].kind == "cast" and evs2[i]._p == 1 then table.remove(evs2, i) end
  end
end)
local mPushed, mRel, mAutoIx = {}, {}, {}
for i = 1, #mStream do
  local before = #gM.verdicts
  G.Feed(gM, mStream[i])
  for j = before + 1, #gM.verdicts do mPushed[gM.verdicts[j]] = i end
  if mStream[i].kind == "auto" then mRel[#mRel + 1] = mStream[i].t; mAutoIx[#mAutoIx + 1] = i end
end
G.Finish(gM, mStream, #mStream)
local missV, nextV
for _, v in ipairs(judgments(gM)) do
  if v.grade == "MISSED" and not missV then missV = v
  elseif missV and not nextV and v.grade ~= "MISSED" then nextV = v end
end
-- Ahead of the next cycle's grade in the stream, and pushed no later than the
-- event that carries it -- which is the cast whose START proved cycle 2 was
-- over, an event BEFORE the release that opens cycle 4. (Waiting for that
-- release is what the old one-cycle lag did.)
ok(missV and nextV and mPushed[missV] <= mPushed[nextV] and mPushed[missV] < mAutoIx[4],
   "the MISSED reaches the stream before the next cycle's grade and before the next release (at "
   .. tostring(missV and mPushed[missV]) .. ", release 4 at " .. tostring(mAutoIx[4]) .. ")")
ok(missV and (missV.t - mRel[3]) <= STEADY_CAST + 0.05,
   "...within a cast of the cycle's own end (" .. ("%.3f"):format(missV and (missV.t - mRel[3]) or -1) .. " s)")
ok(missV and missV.cycle == 2, "...and it names the cycle it was missed in (" .. tostring(missV and missV.cycle) .. ")")

-- (o) ...and it is stamped with the moment it ENTERS the stream, not with the
--     cycle end it belongs to. The two are a grace apart (a whole Steady cast),
--     and the conveyor ages a pop by `now - v.t`: a MISSED stamped at the cycle
--     end is born older than T.POP_LIFE and never appears on the stage at all.
--     Fed on a 30 Hz clock, the way the central tick feeds it in game.
local TICK, POP_LIFE = 1 / 30, TL.POP_LIFE
local gTick = judgeG("1:1")
local tickStream = paperStream("1:1", 4, function(evs2)
  for i = #evs2, 1, -1 do
    if evs2[i].kind == "cast" and evs2[i]._p == 1 then table.remove(evs2, i) end
  end
end)
local bornAt, fedIx = {}, 0
local clock = 0
while fedIx < #tickStream do
  while fedIx < #tickStream and (tickStream[fedIx + 1].t or 0) <= clock + 1e-9 do
    fedIx = fedIx + 1
    local before = #gTick.verdicts
    G.Feed(gTick, tickStream[fedIx])
    for j = before + 1, #gTick.verdicts do bornAt[gTick.verdicts[j]] = clock end
  end
  clock = clock + TICK
end
G.Finish(gTick, tickStream, #tickStream)
local tickMiss, worstAge, worstStamp = nil, 0, 0
for _, v in ipairs(judgments(gTick)) do
  local born = bornAt[v]
  if born then
    local age = born - v.t                 -- how old the pop is the moment it exists
    if age > worstAge then worstAge = age end
    local off = math.abs(born - v.t)       -- ...and how far the stamp is from that moment
    if off > worstStamp then worstStamp = off end
    if v.grade == "MISSED" and not tickMiss then tickMiss = v end
  end
end
ok(tickMiss ~= nil, "30 Hz: the dropped Steady is still MISSED")
ok(worstStamp <= TICK + 1e-6, "30 Hz: every judgment is stamped with the moment it enters the stream ("
   .. ("%.4f"):format(worstStamp) .. " s off, one tick is " .. ("%.4f"):format(TICK) .. ")")
ok(worstAge < POP_LIFE, "30 Hz: and is younger than a pop's life when it is pushed ("
   .. ("%.3f"):format(worstAge) .. " s of " .. POP_LIFE .. ")")
-- The cycle end it belongs to is a whole grace behind that: the stamp the MISSED
-- used to carry would have been born dead.
ok(tickMiss and (bornAt[tickMiss] - (tickMiss.note.t0)) > POP_LIFE,
   "...while its NOTE's own time is older than a pop's life, which is why the two are separate fields ("
   .. ("%.3f"):format(tickMiss and (bornAt[tickMiss] - tickMiss.note.t0) or -1) .. " s)")
end

-- ---------------------------------------------------------------------------
-- G.Summary: one sentence, keyed on the FAMILY the fight's faults belong to.
-- Task 7 (review reads as a lesson). Kept in a do..end block: this file is near
-- LuaJIT's 200-local ceiling.
-- ---------------------------------------------------------------------------
do
local function score(rows)
  return { analysis = rows, cyclesOnPaper = { ok = 18, total = 22 }, clips = 0 }
end

-- Clean: no analysis rows at all.
local text, fam = G.Summary(score({}))
ok(text == G.SUMMARY.clean, "Summary: a clean fight says the drill passed")
ok(fam == "clean", "Summary: ...and names the clean family")
ok(G.Summary(nil) == G.SUMMARY.clean, "Summary: no scorecard reads clean rather than erroring")
ok(G.Summary({}) == G.SUMMARY.clean, "Summary: a scorecard with no analysis reads clean")

-- Clip-dominant: the ms wins, and the sentence carries the count and the cost.
local clipT, clipFam, clipN, clipMs = G.Summary(score({
  { code = "CLIP", n = 2, ms = 827, advice = "no cast may run past the wind-up moment", cycle = 7 },
  { code = "WEAVE_MISSED", n = 1, ms = 0, advice = "when the melee swing is ready", cycle = 9 },
}))
ok(clipFam == "clips", "Summary: a fight whose cost is clips is keyed on the clip family")
ok(clipN == 2 and clipMs == 827, "Summary: ...and reports that family's own count and cost")
ok(clipT == G.SUMMARY.clips:format(2, "s", 827), "Summary: the clip sentence is the clip template, filled")
ok(clipT:find("827", 1, true) ~= nil and clipT:find(" 2 cast", 1, true) ~= nil,
   "Summary: the clip sentence names both numbers")
ok(G.Summary(score({ { code = "CLIP", n = 1, ms = 400, cycle = 3 } })):find("1 cast ", 1, true) ~= nil,
   "Summary: one clip is singular")

-- Weave-dominant: three weave rows of 0 ms outrank a single 0 ms clip by count,
-- and a weave family that costs more ms wins outright.
local wT, wFam, wN = G.Summary(score({
  { code = "WEAVE_SLOW", n = 2, ms = 300, advice = "shorter legs", cycle = 4 },
  { code = "WEAVE_MISSED", n = 3, ms = 0, advice = "go in", cycle = 9 },
  { code = "CLIP", n = 1, ms = 120, advice = "no cast", cycle = 2 },
}))
ok(wFam == "weave", "Summary: the weave family is summed across its codes and wins on the total")
ok(wN == 5, "Summary: ...counting every weave row (2 + 3)")
ok(wT == G.SUMMARY.weave:format(5, "s"), "Summary: the weave sentence is the weave template, filled")

-- A family with no milliseconds at all still wins when it is the only one.
local mT, mFam = G.Summary(score({ { code = "WEAVE_MISSED", n = 1, ms = 0, cycle = 6 } }))
ok(mFam == "weave" and mT == G.SUMMARY.weave:format(1, ""),
   "Summary: a 0 ms family is still the answer when it is the only fault, and reads singular")

-- Paper (shot choice / idle GCD) and opener each have their own template.
local pT, pFam = G.Summary(score({ { code = "LATE", n = 4, ms = 900, cycle = 1 } }))
ok(pFam == "paper", "Summary: LATE is a paper fault, not a clip")
ok(pT == G.SUMMARY.paper:format(4, "s"), "Summary: the paper sentence is the paper template, filled")
ok(pT:find("4 notes off the paper", 1, true) ~= nil,
   "Summary: ...and it PLURALISES cleanly, no 'presss' (" .. pT .. ")")
local p1T, p1Fam = G.Summary(score({ { code = "STEADY_WONT_FIT", n = 1, ms = 200, cycle = 1 } }))
ok(p1Fam == "paper", "Summary: so is a Steady that would not fit")
ok(p1T:find("1 note off the paper", 1, true) ~= nil,
   "Summary: one of them is singular (" .. p1T .. ")")

-- Every SENTENCE renders as real English, whichever family and either number.
local badPlural = nil
for fam in pairs(G.SUMMARY) do
  if fam ~= "clean" then
    for _, cnt in ipairs({ 1, 4 }) do
      local text
      if fam == "clips" then text = G.SUMMARY[fam]:format(cnt, (cnt == 1) and "" or "s", 300)
      else text = G.SUMMARY[fam]:format(cnt, (cnt == 1) and "" or "s") end
      if text:find("%%") or text:find("sss") or text:find("presss") then badPlural = fam .. ": " .. text end
    end
  end
end
ok(badPlural == nil, "Summary: no template leaves a stray placeholder or a triple s (" .. tostring(badPlural) .. ")")
local oT, oFam = G.Summary(score({ { code = "EARLY", n = 1, ms = 0, cycle = 0 } }))
ok(oFam == "opener" and oT == G.SUMMARY.opener:format(1, ""),
   "Summary: an EARLY cooldown is the opener's own sentence")

-- Every template a code maps to exists, and every family in the table has one.
local missing = nil
for code, fam in pairs(G.SUMMARY_FAMILY) do
  if not G.SUMMARY[fam] then missing = code .. "->" .. fam end
end
ok(missing == nil, "Summary: every mapped family has a template (" .. tostring(missing) .. ")")

-- ...and the REVERSE, which is the one that rots: every code with ADVICE can
-- reach an analysis row, and a row whose code has no family would make a fight
-- full of that fault read "No faults - drill passed".
ok(type(G.ADVICE) == "table", "Summary: the advice table is exported for the coverage guard")
local unfamilied = nil
for code in pairs(G.ADVICE or {}) do
  if not G.SUMMARY_FAMILY[code] then unfamilied = code end
end
ok(unfamilied == nil, "Summary: every ADVICE code has a family, so no fault can render as clean ("
   .. tostring(unfamilied) .. ")")
-- And one live proof of the same, through G.Analysis: a scorecard built from
-- ONE row per advised code never comes back clean.
local cleanish = nil
for code, adv in pairs(G.ADVICE or {}) do
  local t, fam = G.Summary(score({ { code = code, n = 1, ms = 50, advice = adv, cycle = 1 } }))
  if fam == "clean" or t == G.SUMMARY.clean then cleanish = code end
end
ok(cleanish == nil, "Summary: no single advised fault reads as a clean fight (" .. tostring(cleanish) .. ")")

-- A real fight: the grader's own analysis, straight into Summary.
local gs = newG()
G.Feed(gs, { t = 0, kind = "pull" })
G.Feed(gs, { t = 0.36, kind = "auto", delay = 0 })
G.Feed(gs, { t = 2.53, kind = "auto", delay = 0.4, cause = "cast" })
G.Feed(gs, { t = 4.7, kind = "auto", delay = 0.3, cause = "cast" })
G.Feed(gs, { t = 6, kind = "stop" })
local fin = G.Finish(gs, {}, 0)
local rT, rFam = G.Summary(fin)
ok(rFam == "clips", "Summary: a fight with two clipped autos reads as a clip fight")
ok(rT == G.SUMMARY.clips:format(2, "s", 700), "Summary: ...with the clip ms the scorecard counted")
end

--------------------------------------------------------------------------------
-- 35. A CLIP THE PAPER ITSELF SCHEDULES IS NOT A FAULT.
--
-- M.Layout is a greedy scheduler: it lets a cast run past the moment the next
-- wind-up could start and books the overlap in `delays`. 5:5:1:1 at eWS 2.174
-- budgets ~0.25 s of it across a five-auto period, so a hunter playing the
-- notation EXACTLY still releases three of its five autos late. Grading those
-- as clips made the paper fail itself every period, and the 3-clip cap then
-- held every multi-auto notation at B by construction.
--------------------------------------------------------------------------------
do
local TL = dofile("Core/PracticeTimeline.lua")
local HP = { ws = 3.0, rangedMul = 1.38, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0 }
local FRENCH = "5:5:1:1"
local SPELL = { s = "steady", m = "multi", A = "arcane" }

-- The paper's own delay per auto, the way the scheduler books it: a `delays`
-- entry ENDS where its auto's wind-up begins.
local function paperDelays(lay)
  local out, di = {}, 1
  for i = 1, #lay.ev do
    local pe = lay.ev[i]
    if pe.sym == "a" then
      local d = lay.delays[di]
      if d and math.abs(d.t0 + d.dur - pe.t0) < 1e-6 then
        out[#out + 1] = d.dur; di = di + 1
      else
        out[#out + 1] = 0
      end
    end
  end
  return out
end

local lay = M.Layout(M.STRINGS[FRENCH], HP, 0)
local dly = paperDelays(lay)
local budgeted, budgetSum = 0, 0
for i = 1, #dly do
  budgetSum = budgetSum + dly[i]
  if dly[i] > 0.03 then budgeted = budgeted + 1 end
end
ok(#dly == 5 and budgeted == 3, "fixture: 5:5:1:1 at eWS 2.174 budgets a delay on 3 of its 5 autos ("
   .. budgeted .. ")")
ok(near(budgetSum, lay.delay), "fixture: the per-auto budgets sum to the layout's own `delay`")
ok(near(dly[5], 0.1522, 1e-3), "fixture: the fifth auto carries the big one (" .. tostring(dly[5]) .. ")")

-- The layout played EXACTLY: casts at the layout's own starts, autos at the
-- layout's own releases, each carrying the delay the paper booked for it (and
-- `cause = "cast"`, because a scheduled clip IS a cast clip). `late` moves one
-- cast, and the auto behind it, by the same amount -- a press that slipped.
local function exactStream(periods, late)
  local evs = {}
  for p = 0, periods - 1 do
    local ai = 0
    for i = 1, #lay.ev do
      local pe = lay.ev[i]
      local t0 = p * lay.dur + pe.t0
      if pe.sym == "a" then
        ai = ai + 1
        local extra = (late and p == 0 and ai == late.auto) and late.by or 0
        evs[#evs + 1] = { t = t0 + pe.dur + extra, kind = "auto",
                          delay = dly[ai] + extra, cause = "cast" }
      elseif SPELL[pe.sym] then
        local shift = (late and p == 0 and i == late.ev) and late.by or 0
        evs[#evs + 1] = { t = t0 + shift + pe.dur, kind = "cast", spell = SPELL[pe.sym],
                          t0 = t0 + shift, t1 = t0 + shift + pe.dur }
      end
    end
  end
  table.sort(evs, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.kind < b.kind end)
  local out = { { t = 0, kind = "pull" } }
  for i = 1, #evs do out[#out + 1] = evs[i] end
  out[#out + 1] = { t = periods * lay.dur + 1, kind = "stop" }
  return out
end

local function run(evs)
  local gg = G.New({ model = M, h = HP, notation = FRENCH, damage = DMG, clipMin = 0.03,
                     reaction = 0.15, timeline = TL })
  for i = 1, #evs do G.Feed(gg, evs[i]) end
  return gg, G.Finish(gg, evs, #evs)
end

local gP, sP = run(exactStream(3))
ok(sP.clips == 0 and sP.clipMs == 0, "the paper played exactly raises no clip fault ("
   .. sP.clips .. " clips, " .. sP.clipMs .. " ms)")
ok(gP.judge.clip == 0, "...and no CLIP judgment either (" .. gP.judge.clip .. ")")
local nClipCode = 0
for i = 1, #gP.verdicts do if gP.verdicts[i].code == "CLIP" then nClipCode = nClipCode + 1 end end
ok(nClipCode == 0, "...so no fix card is offered for it (" .. nClipCode .. " CLIP verdicts)")
ok(sP.grade == "A+", "...and the paper grades A+, uncapped (" .. tostring(sP.grade) .. ")")

-- ...but a Steady 0.3 s past its own slot still clips, for the EXCESS over the
-- budget and nothing more. Event 16 is the fifth cycle's Steady, the one the
-- paper already lets run 0.152 s into the wind-up.
local LATE = 0.3
local gL, sL = run(exactStream(1, { ev = 16, auto = 5, by = LATE }))
ok(sL.clips == 1, "a Steady 0.3 s past its slot clips once (" .. sL.clips .. ")")
local cv
for i = 1, #gL.verdicts do if gL.verdicts[i].code == "CLIP" then cv = gL.verdicts[i] end end
ok(cv and cv.ms == 300, "...for the excess over the paper's budget, not the whole 452 ms delay ("
   .. tostring(cv and cv.ms) .. ")")
ok(sL.clipMs == 300, "...and the scorecard counts that excess (" .. sL.clipMs .. ")")
ok(gL.judge.clip == 1, "...and the note the cast was played on is judged CLIP (" .. gL.judge.clip .. ")")
end

-- 36. THE PAPER IS THE SCOPE. A drill whose notation has no `w` is not a weave
--     fight however the weave key is bound: the same stream that raises
--     WEAVE_MISSED / WEAVE_SLOW / DEAD_ZONE / REARM on a weave paper raises
--     none of them here, and counts no weave windows — while the mechanics the
--     engine drives (melee hits, leg measurements, the opportunity window
--     itself) keep running underneath.
do
-- The symbol sets themselves, cached per notation string.
local s11 = G.Syms(M, "1:1")
ok(s11.s and s11.m and not s11.A and not s11.w, "Syms: 1:1 is Steady and Multi (the basic papers' practice rule), no Arcane, no weave")
ok(G.Syms(M, "drill 1:1").s and not G.Syms(M, "drill 1:1").m, "Syms: the teaching 1:1 stays Steady only")
local sw3 = G.Syms(M, "5:5:1:1 3w")
ok(sw3.s and sw3.m and sw3.A and sw3.w, "Syms: 5:5:1:1 3w carries all four")
ok(G.Syms(M, "5:5:1:1").w == false, "Syms: the turret paper has no weave slot")
ok(G.Syms(M, "1:1") == s11, "Syms: the set is cached per notation, not rebuilt")
ok(G.Syms(M, "no such notation").s == true and G.Syms(M, "no such notation").w == false,
   "Syms: an unknown notation falls back to `as`, exactly as layoutFor does")

-- The same weave stream, told twice: once on a 1:1 paper, once on a weave one.
local function weaveStream(notation, notationFor)
  local gg = G.New({ model = M, h = H, notation = notation, notationFor = notationFor,
                     damage = DMG, clipMin = 0.03, reaction = 0.15,
                     oppMin = 0.4, rearmMin = 0.05, legMax = 0.4 })
  G.Feed(gg, { t = 0, kind = "pull" })
  -- An opportunity window nobody went for.
  G.Feed(gg, { t = 0.4, kind = "opp", open = true, ttw = 1.8 })
  G.Feed(gg, { t = 1.5, kind = "opp", open = false, ttw = 0.7 })
  -- ...then a weave with a slow leg and a release that costs a re-arm.
  G.Feed(gg, { t = 2.0, kind = "weave", edge = "down" })
  G.Feed(gg, { t = 2.6, kind = "melee", hit = "w" })
  G.Feed(gg, { t = 2.9, kind = "weave", edge = "up", cost = 0.2 })
  G.Feed(gg, { t = 2.9, kind = "weave", edge = "done",
               legs = { stepIn = 0.6, dwell = 0, stepOut = 0.3, total = 0.9,
                        budget = 1.2, backIn = false, backOut = false, hit = "w" } })
  G.Feed(gg, { t = 3.4, kind = "deadzone" })
  G.Feed(gg, { t = 5.0, kind = "stop" })
  return gg, G.Finish(gg)
end

local gWeave, sWeave = weaveStream("5:5:1:1 3w")
ok(codes(gWeave):find("WEAVE_MISSED", 1, true) and codes(gWeave):find("WEAVE_SLOW", 1, true)
   and codes(gWeave):find("REARM", 1, true) and codes(gWeave):find("DEAD_ZONE", 1, true),
   "weave paper: all four weave faults still raised (" .. codes(gWeave) .. ")")
ok(sWeave.weavesTaken == 1 and sWeave.weavesMissed == 1, "weave paper: the windows are counted")
ok(sWeave.paperWeave == true, "weave paper: the scorecard says the paper had a weave")

local gBeat, sBeat = weaveStream("1:1")
ok(codes(gBeat) == "", "1:1 paper: not one weave fault (" .. codes(gBeat) .. ")")
ok(sBeat.weavesTaken == 0 and sBeat.weavesMissed == 0, "1:1 paper: no weave windows counted")
ok(sBeat.rearmMs == 0, "1:1 paper: and no re-arm milliseconds billed")
ok(sBeat.paperWeave == false, "1:1 paper: the scorecard says the paper never asked for melee")
-- The mechanics underneath are untouched: the hit landed, the legs were
-- measured, and G.LegsNeeded has moved off its seed for the engine's windows.
ok(sBeat.meleeHits == 1, "1:1 paper: the melee hit still happened")
ok(gBeat.nLegs == 1 and near(G.LegsNeeded(gBeat), 0.9), "1:1 paper: the legs still feed LegsNeeded ("
   .. tostring(G.LegsNeeded(gBeat)) .. ")")

-- A rhythm drill: the notation changes with the haste window, and the gate
-- follows the WINDOW, not the fight's opening paper.
local function byHaste(rm) return (rm > 1.5) and "5:5:1:1 3w" or "1:1" end
local gR = G.New({ model = M, h = H, notation = "1:1", notationFor = byHaste,
                   damage = DMG, clipMin = 0.03, reaction = 0.15,
                   oppMin = 0.4, rearmMin = 0.05, legMax = 0.4 })
G.Feed(gR, { t = 0, kind = "pull" })
ok(G.PaperSyms(gR).w == false, "rhythm: the base window is the turret paper")
G.Feed(gR, { t = 0.4, kind = "opp", open = true, ttw = 1.8 })
G.Feed(gR, { t = 1.5, kind = "opp", open = false, ttw = 0.7 })
ok(codes(gR) == "", "rhythm: the miss inside the base window is not a fault")
G.Feed(gR, { t = 2.0, kind = "haste", rangedMul = 1.93, rf = true })
ok(G.PaperSyms(gR).w == true, "rhythm: Rapid Fire opens a weave window")
G.Feed(gR, { t = 2.4, kind = "opp", open = true, ttw = 1.8 })
G.Feed(gR, { t = 3.5, kind = "opp", open = false, ttw = 0.7 })
ok(codes(gR) == "WEAVE_MISSED", "rhythm: the same miss inside it IS (" .. codes(gR) .. ")")
G.Feed(gR, { t = 5.0, kind = "stop" })
local sR = G.Finish(gR)
ok(sR.paperWeave == true and sR.weavesMissed == 1,
   "rhythm: one window's `w` is enough for the scorecard's weave tile")
end

-- 40. THE PAPER IS THE SCOPE, the SHOT half (R3a). D1 took the weave nags off a
-- paper with no `w`; the same rule was never applied to the shot alternatives,
-- so a `1:1` drill — "as", one Steady per auto and nothing else — was told every
-- cycle that a catch-up Multi fit, that a Steady "won't fit" because an Arcane
-- was up, and that it was LATE for a Multi the paper never asks for. The engine
-- keeps running Multi/Arcane cooldowns; only the verdicts are the paper's
-- business. Every leg has its French counterpart above, so none of this is
-- vacuous — the same streams DO fault on a paper that writes `m`/`A`.
-- (2026-08-27: the practice `1:1` writes a Multi once per cooldown — M.PaperString
-- — so the Steady-only paper here is the teaching `drill 1:1`.)
do
  local function newG1() return G.New({ model = M, h = H, notation = "drill 1:1", damage = DMG, clipMin = 0.03, reaction = 0.15 }) end
  -- STEADY WON'T FIT: ttw 0.8 < a 1.087 s Steady, Multi and Arcane both ready.
  local g1 = newG1()
  G.Feed(g1, { t = 0, kind = "pull" })
  G.Feed(g1, { t = 1.0, kind = "press", key = "steady", result = "ok", ctx = ctx(0.8) })
  G.Feed(g1, { t = 3, kind = "stop" })
  G.Finish(g1)
  ok(codes(g1) == "GOOD", "1:1 paper: no STEADY WON'T FIT — there is no Multi to take instead ("
     .. codes(g1) .. ")")

  -- CATCH-UP MULTI MISSED: the exact fixture of section 9, on the 1:1 paper.
  local H3 = { ws = 3.0, rangedMul = 1.93, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0 }
  local g2 = G.New({ model = M, h = H3, notation = "drill 1:1", damage = DMG, clipMin = 0.03, reaction = 0.15 })
  local c3 = { ttw = 0.9, inWindup = false, cycle = 3.0 / 1.93, steadyCast = 1.5 / 1.93,
               multiCast = 0.5 / 1.93, msReady = true, arcReady = true }
  G.Feed(g2, { t = 0, kind = "pull" })
  G.Feed(g2, { t = 1.0, kind = "press", key = "steady", result = "ok", ctx = c3 })
  G.Feed(g2, { t = 3, kind = "stop" })
  G.Finish(g2)
  ok(codes(g2) == "GOOD", "1:1 paper: no CATCH-UP MULTI MISSED (" .. codes(g2) .. ")")

  -- LATE: free with 0.9 s to the wind-up. A Steady does not fit in it, a Multi
  -- does — so on the French paper this is LATE and on the 1:1 paper it is not a
  -- fault at all: there was nothing on paper to press.
  local function lateFight(gg)
    G.Feed(gg, { t = 0, kind = "pull" })
    G.Feed(gg, { t = 3.0, kind = "free", ctx = ctx(0.9) })
    G.Feed(gg, { t = 3.4, kind = "press", key = "steady", result = "ok", ctx = ctx(0.9) })
    G.Feed(gg, { t = 6.0, kind = "stop" })
    return G.Finish(gg)
  end
  local gF = newGm()
  local sF = lateFight(gF)
  ok(codes(gF):find("LATE", 1, true) ~= nil and sF.lateMs > 0,
     "French paper: the same gap IS late, and billed (" .. codes(gF) .. ")")
  local gO = newG1()
  local sO = lateFight(gO)
  ok(codes(gO):find("LATE", 1, true) == nil and sO.lateMs == 0,
     "1:1 paper: nothing on paper fit, so the gap is not a fault (" .. codes(gO) .. ")")

  -- ...and the paper follows the WINDOW, not the fight's opening notation: a
  -- Rapid Fire window on a rhythm drill re-opens the Multi verdicts.
  local gW = G.New({ model = M, h = H, notation = "drill 1:1", damage = DMG, clipMin = 0.03, reaction = 0.15 })
  G.Feed(gW, { t = 0, kind = "pull" })
  G.Feed(gW, { t = 1.0, kind = "press", key = "steady", result = "ok", ctx = ctx(0.8) })
  ok(codes(gW) == "GOOD", "window paper: 1:1 window, no won't-fit")
  G.Feed(gW, { t = 2.0, kind = "haste", rangedMul = 1.38, qs = true })
  gW.win.notation = "5:5:1:1"          -- what notationFor answers for that window
  G.Feed(gW, { t = 3.0, kind = "press", key = "steady", result = "ok", ctx = ctx(0.8) })
  ok(codes(gW) == "GOOD,STEADY_WONT_FIT",
     "window paper: the French window raises it again (" .. codes(gW) .. ")")
  G.Feed(gW, { t = 6.0, kind = "stop" })
  G.Finish(gW)
end

-- 41. PER-NOTE STATE AND THE SHARED SEATING ROUTINE (v3 P1). The plan builder
-- (Core/PracticePlan.lua) reads nState/nGrade straight off a cycle record and
-- seats the cycles ahead with G.SeatCycle -- the same routine fillCycle uses --
-- so a projected note's key and time are exactly what the grader will hold.
do
  local T = dofile("Core/PracticeTimeline.lua")
  local function newGT(nota)
    return G.New({ model = M, h = H, notation = nota or "1:1", damage = DMG, clipMin = 0.03,
                   reaction = 0.15, timeline = T })
  end
  local CYC = 3.0 / 1.38
  local g = newGT()
  G.Feed(g, { t = 0, kind = "pull" })
  G.Feed(g, { t = 0.36, kind = "auto", delay = 0 })
  local c = g.cur
  ok(c and c.n >= 1, "41: seated cycle has notes")
  ok(c.nState[1] == G.PENDING, "41: a seated note starts pending")
  ok(c.nGrade[1] == nil, "41: a seated note has no grade")
  ok(c.nKey[1] ~= nil, "41: seated notes carry keys with a timeline in reach")

  local lay = G.Layout(g)
  ok(lay ~= nil and lay.autos and lay.autos > 0, "41: G.Layout returns the window layout")
  local rec = { n = 0, nT0 = {}, nSym = {}, nKey = {}, nUsed = {}, nState = {}, nGrade = {} }
  G.SeatCycle(lay, (g.win.autos or 1) - 1, 0.36, rec, T, c.ix)
  ok(rec.n == c.n, "41: SeatCycle seats the same count as fillCycle")
  local same = rec.n == c.n
  for i = 1, c.n do
    if rec.nKey[i] ~= c.nKey[i] or math.abs(rec.nT0[i] - c.nT0[i]) > 1e-9 or rec.nSym[i] ~= c.nSym[i]
       or rec.nState[i] ~= G.PENDING then same = false end
  end
  ok(same, "41: SeatCycle seats the same keys, times and symbols as fillCycle")
  ok(c.nKey[1] == T.KEY.PAPER + c.ix * T.KEY.PAPER_SLOTS + 1, "41: a note key is cycle * slots + index")
  ok(T.PaperGen == nil and T.NoteSlots == nil, "41: the generation registry is gone")

  -- A matched cast flips its note to hit, with its grade.
  local sT0 = c.nT0[1]
  G.Feed(g, { t = sT0 + 1.107, kind = "cast", spell = "steady", t0 = sT0 + 0.02, t1 = sT0 + 1.107 })
  ok(c.nState[1] == G.HIT, "41: matched note is hit")
  ok(c.nGrade[1] == "PERFECT", "41: matched note carries its grade (" .. tostring(c.nGrade[1]) .. ")")

  -- Pre-pull layout: no window yet, an explicit shot string and haste.
  local g2 = newGT()
  ok(G.Layout(g2, M.STRINGS["1:1"], 1.38) ~= nil, "41: G.Layout lays out an explicit paper before the pull")
  ok(G.Layout(g2) == nil, "41: ...and nothing without a window or a string")

  ok(G.PaperNextSym == nil, "41: G.PaperNextSym removed")

  -- A weave note is seated where the swing can make it: a hit late in the
  -- previous cycle pushes the next cycle's `w` onto the swing's return.
  local gw = G.New({ model = M, h = H, notation = "drill 1w", damage = DMG, clipMin = 0.03,
                     reaction = 0.15, timeline = T })
  local MC = 3.7 / 1.0
  G.Feed(gw, { t = 0, kind = "pull" })
  G.Feed(gw, { t = 0.36, kind = "auto", delay = 0 })
  local w1 = gw.cur.nT0[1]
  G.Feed(gw, { t = w1 + 1.0, kind = "melee", hit = "w" })   -- a second late
  G.Feed(gw, { t = 0.36 + CYC, kind = "auto", delay = 0 })
  local c2 = gw.cur
  ok(c2.nSym[1] == "w" and math.abs(c2.nT0[1] - (w1 + 1.0 + MC)) < 1e-9,
     ("41: a w note is retimed onto the swing's return (%.3f vs %.3f)"):format(c2.nT0[1], w1 + 1.0 + MC))
  ok(c2.lastNote and c2.lastNote >= c2.nT0[1], "41: ...and the cycle waits for it")

  -- ...and the chain runs through a note still WAITING to be played: with no
  -- hit at all, the second cycle's `w` sits one melee cycle after the first's
  -- (the plan projects it there; the grader must seat it there too).
  local gc = G.New({ model = M, h = H, notation = "drill 1w", damage = DMG, clipMin = 0.03,
                     reaction = 0.15, timeline = T })
  G.Feed(gc, { t = 0, kind = "pull" })
  G.Feed(gc, { t = 0.36, kind = "auto", delay = 0 })
  local wA = gc.cur.nT0[1]
  G.Feed(gc, { t = 0.36 + CYC, kind = "auto", delay = 0 })
  local wB = gc.cur.nT0[1]
  -- ...onto the swing after it, then fitted clear of the wind-up (G.FitWeave).
  local rc, rw = G.RangedGrid(gc)
  local wantB = G.FitWeave(wA + MC, gc.cur.t0, rc, rw, G.LegsNeeded(gc), G.StepIn(gc))
  ok(gc.cur.nSym[1] == "w" and math.abs(wB - wantB) < 1e-9,
     ("41: an unplayed weave note chains the next cycle's onto the swing after it (%.3f vs %.3f)"):format(wB, wantB))
  ok(wantB >= wA + MC - 1e-9, "41: ...never earlier than the swing")
  -- ...and when the hit lands 10 ms late, the seated note ahead follows the
  -- REAL swing (the hit), not the note the hit took.
  G.Feed(gc, { t = wA + 0.01, kind = "melee", hit = "w" })
  local wantC = G.FitWeave(wA + 0.01 + MC, gc.cur.t0, rc, rw, G.LegsNeeded(gc), G.StepIn(gc))
  ok(math.abs(gc.cur.nT0[1] - wantC) < 1e-9,
     ("41: a late hit re-seats the next weave onto the real swing return (%.3f vs %.3f)"):format(gc.cur.nT0[1], wantC))
  ok(wantC >= wA + 0.01 + MC - 1e-9, "41: ...never before that swing")
  ok(gc.pend.nState[1] == G.HIT and math.abs(gc.pend.nT0[1] - wA) < 1e-9, "41: ...and never the note it took")

  -- A weave that cannot finish before its cycle's wind-up goes after the NEXT
  -- release, never into the wind-up (a negative leg budget, DEAD ZONE).
  local rel, cyc, wu = 100, 2.174, 0.362
  ok(G.FitWeave(100.5, rel, cyc, wu, 0.3) == 100.5, "41: a weave with room stays put")
  ok(math.abs(G.FitWeave(101.7, rel, cyc, wu, 0.3) - (rel + cyc)) < 1e-9,
     "41: a weave that would run into the wind-up moves to the next release")

  -- A note nobody played goes missed at the sweep.
  local g3 = newGT()
  G.Feed(g3, { t = 0, kind = "pull" })
  G.Feed(g3, { t = 0.36, kind = "auto", delay = 0 })
  local c3 = g3.cur
  local key1 = c3.nKey[1]
  G.Feed(g3, { t = 0.36 + CYC, kind = "auto", delay = 0 })          -- cycle 1 parks on its grace
  -- The sweep fires on any event past sweepAt (t1 + one Steady cast). A third
  -- release would ALSO sweep it, but then refills the pooled record as cycle 3.
  G.Feed(g3, { t = 0.36 + CYC + 2.0, kind = "free", ctx = ctx(1.0, { msReady = false, arcReady = false }) })
  local lastV = g3.verdicts[#g3.verdicts]
  ok(lastV and lastV.kind == "judge" and lastV.grade == "MISSED" and lastV.note.key == key1,
     "41: the sweep pushed MISSED for that note")
  ok(c3.nState[1] == G.MISSED and c3.nGrade[1] == "MISSED",
     "41: unplayed note is missed after the sweep (" .. tostring(c3.nState[1]) .. "/" .. tostring(c3.nGrade[1]) .. ")")
end

-- 42. THE GRADER JUDGES AGAINST THE PLAN'S TIME (P3 polish). The plan may hold
--     a note to the release or pull a later cycle's instant forward; a press on
--     the plan's word is that note's, PERFECT, never OFF now or MISSED later.
do
  local T = dofile("Core/PracticeTimeline.lua")
  local g = G.New({ model = M, h = H, notation = "5:5:1:1", damage = DMG, clipMin = 0.03, reaction = 0.15, timeline = T })
  local CY = 3.0 / 1.38
  G.Feed(g, { t = 0, kind = "pull" })
  G.Feed(g, { t = 0.36, kind = "auto", delay = 0 })
  local c1 = g.cur
  ok(c1 and c1.n == 2 and c1.nSym[1] == "s" and c1.nSym[2] == "m" and c1.nKey[1] ~= nil, "42: cycle 1 seats s, m with keys")
  local aKey = T.NoteKey(c1.ix + 2, 2)               -- cycle 3's second note is the paper's A
  -- The plan: cycle 1's Steady held to the next release, its Multi after that
  -- GCD, and cycle 3's Arcane pulled into cycle 1's idle room at 1.2.
  local plan = { live = true, n = 3, notes = {
    { key = c1.nKey[1], sym = "s", cycle = c1.ix, t0 = 0.36 + CY, state = "pending" },
    { key = c1.nKey[2], sym = "m", cycle = c1.ix, t0 = 0.36 + CY + 1.5, state = "pending" },
    { key = aKey, sym = "A", cycle = c1.ix + 2, t0 = 1.2, state = "pending" } } }
  g.plan = plan
  G.Feed(g, { t = 1.2, kind = "cast", spell = "arcane", t0 = 1.2, t1 = 1.2 })
  local v = g.verdicts[#g.verdicts]
  ok(v and v.kind == "judge" and v.grade == "PERFECT" and v.note.key == aKey,
     "42: an Arcane pressed early on the plan's word takes the projected note, PERFECT (" .. tostring(v and v.grade) .. ")")
  ok(c1.off == 0 and g.judge.off == 0, "42: ...and is not an OFF press")
  -- The Steady pressed at the release takes cycle 1's HELD note, not cycle 2's.
  G.Feed(g, { t = 0.36 + CY, kind = "auto", delay = 0 })
  local c2 = g.cur
  plan.n = 4
  plan.notes[4] = { key = c2.nKey[1], sym = "s", cycle = c2.ix, t0 = 0.36 + CY + 1.5, state = "pending" }
  local pressT = 0.36 + CY + 0.01
  G.Feed(g, { t = pressT + 1.087, kind = "cast", spell = "steady", t0 = pressT, t1 = pressT + 1.087 })
  v = g.verdicts[#g.verdicts]
  ok(v.note.key == c1.nKey[1] and v.grade == "PERFECT",
     "42: the Steady at the release takes the held note, PERFECT (" .. tostring(v.note.key == c1.nKey[1]) .. "/" .. tostring(v.grade) .. ")")
  ok(c2.nUsed[1] ~= true, "42: ...and the next cycle's own Steady is still waiting")
  -- Cycle 3 opens: its Arcane is seated HIT (pre-played), never MISSED.
  G.Feed(g, { t = 0.36 + 2 * CY, kind = "auto", delay = 0 })
  local c3 = g.cur
  ok(c3.nKey[2] == aKey and c3.nUsed[2] == true and c3.nState[2] == "hit" and c3.nGrade[2] == "PERFECT",
     "42: the pre-played Arcane is seated HIT with its grade (" .. tostring(c3.nState[2]) .. "/" .. tostring(c3.nGrade[2]) .. ")")
  ok(g.prePlayed[aKey] == nil, "42: ...and the pre-play mark is consumed")
end

print(("practice_grader: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
