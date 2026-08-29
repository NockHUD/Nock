-- Tests/practice_model_test.lua
-- Standalone LuaJIT tests for Core/PracticeModel.lua: the diziet shot-string
-- model (notation map, shorthand, layout, efficiencies).
-- Run from the repo root: luajit Tests/practice_model_test.lua

local M = dofile("Core/PracticeModel.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-3) end

-- 1. Shorthand reproduces diziet's shorthand()
ok(M.Shorthand("as") == "1:1", "shorthand 1:1")
ok(M.Shorthand("asa") == "1:2", "shorthand 1:2")
ok(M.Shorthand("asmasasAasas") == "5:5:1:1", "shorthand French")
ok(M.Shorthand("asmawsaswasAaws") == "5:5:1:1 3w", "shorthand French weaving")
ok(M.Shorthand("awasaawasaas") == "3:7 2w", "shorthand 3:7 2w")

-- 2. Every canonical string round-trips to its key
local n = 0
for notation, str in pairs(M.CANONICAL) do
  n = n + 1
  ok(M.Shorthand(str) == notation, "round-trip " .. notation)
  ok(str:sub(1, 1) == "a", notation .. " starts with an auto")
end
ok(n == 12, "12 canonical strings")

-- 2b. The teaching strings (Round 5b) live in the same lookup but are NOT
--     rotationtools rotations: they are keyed by a teaching name and must never
--     round-trip, or a bracket resolution could land on one by accident.
do
  local t = 0
  for key, str in pairs(M.TEACHING) do
    t = t + 1
    ok(M.CANONICAL[key] == nil, key .. " does not shadow a canonical notation")
    ok(M.STRINGS[key] == str, key .. " is reachable through M.STRINGS")
    ok(str:sub(1, 1) == "a", key .. " starts with an auto")
    ok(key:sub(1, 6) == "drill ", key .. " follows the 'drill <beat>[+syms]' key scheme")
    ok(M.Shorthand(str) ~= key, key .. " is a teaching name, not a shorthand")
    ok(type(M.TEACHING_EWS[key]) == "number", key .. " pins an eWS")
  end
  ok(t == 6, "six teaching strings")
  for key in pairs(M.TEACHING_EWS) do
    ok(M.TEACHING[key] ~= nil, "TEACHING_EWS row " .. key .. " has a string")
  end
  -- Nothing was lost in the merge.
  local all = 0
  for _ in pairs(M.STRINGS) do all = all + 1 end
  ok(all == 18, "M.STRINGS carries all 12 canonical + 6 teaching strings")
end

--------------------------------------------------------------------------------
-- 2c. R5b feasibility: every teaching string, laid out at its OWN pinned eWS,
--     must schedule. Three rules:
--       * the cycle EXCEEDS the 1.5 s GCD -- otherwise the paper's own period
--         is GCD-bound and walks off the swing by construction (the beat rung's
--         old 1.34 s pin lost a whole cycle every nine);
--       * every non-auto note finishes before the wind-up of its own cycle, so
--         nothing on the paper is a clip;
--       * the layout period comes back within one wind-up of a whole number of
--         cycles, and the greedy scheduler never had to delay an auto;
--       * every note lands within ONE MEASURED CYCLE of its own release. The
--         grader's matcher reaches exactly one cycle back (`g.pend`), so a note
--         seated further out than that is MISSED + OFF on flawless play -- the
--         class the R5a/R5c sweep found at low eWS (`2:5` pinned at 0.10 seats
--         its Steady TWELVE cycles out and grades C perfectly played). A
--         teaching paper may never be in it.
--------------------------------------------------------------------------------
do
  local function teachingHandle(ews, mws, pts)
    return { ws = 3.0, rangedMul = 3.0 / ews, mws = mws or 3.7, meleeMul = 1.0,
             imprArcanePts = pts or 0, castCorr = 1,
             multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 }
  end

  local function feasible(key, mws, pts)
    local str = M.TEACHING[key]
    local ews = M.TEACHING_EWS[key]
    local h = teachingHandle(ews, mws, pts)
    local ab = M.Abilities(h)
    local lay = M.Layout(str, h, 0)
    local cycle, windup = ab.a.dur + ab.a.cd, ab.a.dur
    local label = ("%s @ eWS %.2f"):format(key, ews)
    ok(cycle > M.GCD, label .. ": cycle " .. ("%.3f"):format(cycle) .. " exceeds the 1.5 s GCD")
    ok(lay.delay <= 1e-6, label .. ": the scheduler never delays an auto")
    local wrap = lay.dur - lay.counts.a * cycle
    ok(wrap >= -1e-6 and wrap <= windup + 1e-6,
       label .. ": period wraps within one wind-up (" .. ("%+.3f"):format(wrap) .. ")")
    local rel, bad, worst = nil, 0, 0
    for i = 1, #lay.ev do
      local e = lay.ev[i]
      if e.sym == "a" then rel = e.t0 + e.dur
      elseif e.sym ~= "g" and rel then
        if e.t0 + e.dur > rel + (cycle - windup) + 1e-9 then bad = bad + 1 end
        local out = (e.t0 - rel) / cycle
        if out > worst then worst = out end
      end
    end
    ok(bad == 0, label .. ": every note lands before its cycle's wind-up (" .. bad .. " late)")
    ok(worst <= 1.0 + 1e-9, label .. ": every note is within one measured cycle of its release ("
       .. ("%.3f"):format(worst) .. " cycles out)")
    return cycle, windup, ab.s.dur, lay.dur, lay.counts.a, wrap, worst
  end

  for key in pairs(M.TEACHING) do feasible(key) end

  -- The melee swing is the CHARACTER's, not the drill's: a weave paper has to
  -- hold at the slowest two-hander in the game as well as at a fast one.
  feasible("drill 1w", 3.0)
  feasible("drill 1w", 3.8)
  feasible("drill 1w+A", 3.8)
  feasible("drill 1w+s", 3.8)
  -- ...and Improved Arcane Shot shortens a cooldown, which can only ever make
  -- the Arcane easier to place. The pins are written for 0 points, the worst
  -- case; 5 points must not break them either.
  feasible("drill 1:1+mA", 3.7, 5)
  feasible("drill 1w+A", 3.7, 5)

  -- The numbers the ladder's pins were chosen for, stated rather than implied.
  local cycle, windup, steady, dur, autos = feasible("drill 1:1")
  ok(near(cycle, 2.10) and near(windup, 0.35) and near(steady, 1.05) and autos == 1 and near(dur, 2.10),
     "drill 1:1: 2.100 cycle, 0.350 wind-up, 1.050 Steady, one cycle per period")
  cycle, windup, steady, dur, autos = feasible("drill 1:1+m")
  ok(autos == 5 and near(dur, 10.50), "drill 1:1+m: Multi every 5th cycle, 10.500 s period")
  cycle, windup, steady, dur, autos = feasible("drill 1:1+mA")
  ok(autos == 6 and near(dur, 12.60), "drill 1:1+mA: 6 cycles, 12.600 s period")
  cycle, windup, steady, dur, autos = feasible("drill 1w")
  ok(near(cycle, 3.70) and autos == 1 and near(dur, 3.70), "drill 1w: one 3.700 s cycle, one weave")
  cycle, windup, steady, dur, autos = feasible("drill 1w+A")
  ok(autos == 2 and near(dur, 7.40), "drill 1w+A: Arcane every other cycle, 7.400 s period")
  cycle, windup, steady, dur, autos = feasible("drill 1w+s")
  ok(autos == 2 and near(dur, 7.450), "drill 1w+s: rung 6's two-cycle period with a Steady added to each")
  -- The track is CUMULATIVE: rung 7 is rung 6 plus the Steady, not the Steady
  -- instead of the Arcane. Asserted on the strings so a future edit that quietly
  -- drops an ability fails here rather than in a player's ladder.
  local function counts(key)
    local c = {}
    for i = 1, #M.TEACHING[key] do
      local ch = M.TEACHING[key]:sub(i, i)
      c[ch] = (c[ch] or 0) + 1
    end
    return c
  end
  local c6, c7 = counts("drill 1w+A"), counts("drill 1w+s")
  ok(c7.a == c6.a and c7.w == c6.w and c7.A == c6.A and (c7.s or 0) == 2 and (c6.s or 0) == 0,
     "drill 1w+s keeps every note drill 1w+A had and adds the Steady")
  local c4, c5 = counts("drill 1w"), counts("drill 1w+A")
  ok(c5.a == 2 * c4.a and c5.w == 2 * c4.w and c5.A == 1 and (c4.A or 0) == 0,
     "drill 1w+A keeps the weave beat and adds the Arcane")
  local t1, t2, t3 = counts("drill 1:1"), counts("drill 1:1+m"), counts("drill 1:1+mA")
  ok((t1.m or 0) == 0 and t2.m == 1 and (t2.A or 0) == 0 and t3.m == 1 and t3.A == 2,
     "the turret track adds the Multi, then the Arcane")
end

-- 3. Abilities at the P1 BM baseline (3.0 bow, quiver x SS = 1.38)
local h = { ws = 3.0, rangedMul = 1.38, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0 }
local ab = M.Abilities(h)
ok(near(ab.a.dur, 0.5 / 1.38), "auto wind-up = 0.5/haste")
ok(near(ab.a.dur + ab.a.cd, 3.0 / 1.38), "auto cycle = ws/haste")
ok(near(ab.s.dur, 1.5 / 1.38), "steady cast = 1.5/haste")
ok(ab.m.dur == 0.5 / 1.38 and ab.m.cd == 10, "multi cast + 10s cd")
ok(ab.A.dur == 0.1 and ab.A.cd == 6, "arcane instant, 6s cd")
ok(M.Abilities({ ws = 3, rangedMul = 1, mws = 3.7, meleeMul = 1, imprArcanePts = 2 }).A.cd == 5.6,
   "imp arcane shortens the cd 0.2/pt")
ok(near(ab.w.dur + ab.w.cd, 3.7), "white hit cycle = melee speed")

-- 3b. Cooldown numbers arrive on h (Constants.PRACTICE), and castCorr scales
--     the casts but never the wind-up.
local hc = { ws = 3.0, rangedMul = 1.38, mws = 3.7, meleeMul = 1.0, imprArcanePts = 3,
             multiCd = 8, arcaneCdBase = 5, arcaneCdPerPt = 0.5, castCorr = 1.1 }
local abc = M.Abilities(hc)
ok(abc.m.cd == 8, "multi cd from h.multiCd")
ok(near(abc.A.cd, 5 - 0.5 * 3), "arcane cd from h.arcaneCdBase/PerPt")
ok(near(abc.s.dur, 1.1 * 1.5 / 1.38), "steady cast scales by castCorr")
ok(near(abc.m.dur, 1.1 * 0.5 / 1.38), "multi cast scales by castCorr")
ok(near(abc.a.dur, 0.5 / 1.38), "the wind-up is NOT a cast: no castCorr")
ok(near(M.CastTime(1.5, 1.38), 1.5 / 1.38), "CastTime defaults castCorr to 1")

-- 4. 1:1 at 1.38: one cycle long, auto efficiency 100 %, gcd eff 1.5/cycle
local r = M.Layout("as", h, 0)
ok(near(r.dur, 3.0 / 1.38), "1:1 cycle = one swing")
ok(near(r.autoEff, 1.0), "1:1 auto eff 100%")
ok(near(r.gcdEff, 1.5 / (3.0 / 1.38)), "1:1 gcd eff")
ok(r.delay == 0 and #r.delays == 0, "1:1 no delay")
ok(r.ev[1].sym == "a" and r.ev[1].t0 == 0, "first event is the auto at t0")
ok(r.ev[2].sym == "g" and near(r.ev[2].t0, 0.5 / 1.38), "gcd starts when the wind-up ends")
ok(r.ev[3].sym == "s" and near(r.ev[3].t0, 0.5 / 1.38), "steady starts with the gcd")

-- 5. 1:2 at 1.38 is exactly two swings with no delay
r = M.Layout("asa", h, 0)
ok(near(r.dur, 2 * 3.0 / 1.38), "1:2 = two swings")
ok(near(r.autoEff, 1.0), "1:2 auto eff 100%")
ok(r.counts.a == 2 and r.counts.s == 1, "counts")

-- 6. A second Steady before the auto delays it (no haste: 3.0 cycle, 1.5 cast)
local h0 = { ws = 3.0, rangedMul = 1.0, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0 }
r = M.Layout("assa", h0, 0)
ok(#r.delays == 1 and near(r.delays[1].t0, 3.0) and near(r.delays[1].dur, 0.5),
   "second steady pushes the auto by 0.5s")
ok(near(r.delay, 0.5), "total delay 0.5")
ok(near(r.dur, 6.5), "cycle 6.5")
ok(near(r.autoEff, 6.0 / 6.5), "auto eff 6/6.5")
ok(near(r.gcdEff, 3.0 / 6.5), "gcd eff 3/6.5")

-- 7. t0 offsets every event
r = M.Layout("as", h, 100)
ok(r.ev[1].t0 == 100, "layout anchored at t0")

-- 8. Weaving efficiency exists only with weaves
ok(M.Layout("as", h, 0).weaveEff == nil, "no weaveEff without weaves")
r = M.Layout("asasw", h, 0)
ok(r.weaveEff and r.weaveEff > 0 and r.weaveEff <= 1.0001, "2:2 1w weaveEff in (0,1]")

-- 9. A cooldown longer than the swing bounds the cycle (multi's 10s cd)
r = M.Layout("am", h0, 0)
ok(near(r.dur, 10.5), "multi cooldown bottlenecks the cycle (" .. tostring(r.dur) .. ")")

--------------------------------------------------------------------------------
-- Range bar from distance: continuous across every border, so no jumps.
--------------------------------------------------------------------------------
local RE = dofile("Modules/RangeEngine.lua")
local SI = RE.SWEET_I
local st, pr = M.RangeProg(RE, 12, false, 7, 5)
ok(st == "LONG" and pr == -1, "RangeProg: beyond 10yd is LONG/-1")
st, pr = M.RangeProg(RE, 10, false, 7, 5)
ok(st == "CLOSE" and near(pr, -0.9999), "RangeProg: 10yd is the bottom of CLOSE")
st, pr = M.RangeProg(RE, 7.0001, false, 7, 5)
ok(st == "CLOSE" and near(pr, -SI, 1e-3), "RangeProg: just outside the ring is the top of CLOSE")
st, pr = M.RangeProg(RE, 7, false, 7, 5)
ok(st == "SWEET" and near(pr, -SI), "RangeProg: the ring is the bottom of SWEET (continuous with CLOSE)")
st, pr = M.RangeProg(RE, 6, false, 7, 5)
ok(st == "SWEET" and near(pr, (-SI - 0.0001) / 2), "RangeProg: mid-ring is mid-SWEET")
st, pr = M.RangeProg(RE, 5.4, false, 7, 5)
ok(st == "SWEET" and pr > RE.PERFECT_AT, "RangeProg: 5.4yd (inside the last half-yard) reads PERFECT (" .. tostring(pr) .. ")")
st, pr = M.RangeProg(RE, 5.0001, false, 7, 5)
ok(st == "SWEET" and near(pr, -0.0001, 1e-3), "RangeProg: just outside melee is the top of SWEET")
st, pr = M.RangeProg(RE, 5, true, 7, 5)
ok(st == "MELEE" and pr == 0, "RangeProg: melee edge is 0 (continuous with SWEET)")
st, pr = M.RangeProg(RE, 2.75, true, 7, 5)
ok(st == "MELEE" and near(pr, 0.5), "RangeProg: half-way into melee is 0.5")
st, pr = M.RangeProg(RE, 0.5, true, 7, 5)
ok(st == "MELEE" and pr == 1, "RangeProg: the reckoning floor is 1")
-- Monotone: walking in never moves the thumb backward.
local last, mono = -2, true
for d = 1200, 5, -1 do
  local dd = d / 100
  local _, p = M.RangeProg(RE, dd, dd <= 5, 7, 5)
  if p < last - 1e-9 then mono = false end
  last = p
end
ok(mono, "RangeProg: monotone from 12yd to 0.05yd")

-- Finding ladder from yards: the rungs the live scan resolves on a dummy.
local lr = {}
ok(M.LadderBracket(RE, lr, 12, 35, 0, false, false) == "10_15", "LadderBracket: 12yd -> 10_15")
ok(M.LadderBracket(RE, lr, 18, 35, 0, false, false) == "15_20", "LadderBracket: 18yd -> 15_20")
ok(M.LadderBracket(RE, lr, 23, 35, 0, false, false) == "20_25", "LadderBracket: 23yd -> 20_25")
ok(M.LadderBracket(RE, lr, 28, 35, 0, false, false) == "25_30", "LadderBracket: 28yd -> 25_30")
ok(M.LadderBracket(RE, lr, 33, 35, 0, false, false) == "30_35", "LadderBracket: 33yd -> 30_35")
ok(M.LadderBracket(RE, lr, 36, 35, 0, false, false) == "OOR", "LadderBracket: 36yd at rank 0 -> OUT OF RANGE")
ok(M.LadderBracket(RE, lr, 36, 41, 3, true, false) == "35_40", "LadderBracket: 36yd at Hawk Eye 3 -> 35_40")
ok(M.LadderBracket(RE, lr, 20.5, 35, 3, true, false) == "20_21", "LadderBracket: Scatter rung at rank 3")
ok(M.LadderBracket(RE, lr, 36, 35, 0, false, true) == "OOR", "LadderBracket: HM still in range past Auto Shot -> OOR, not HM_OOR")
ok(lr.i13289 == false and lr.i4945 == true, "LadderBracket: fills the reusable probe table in place (36yd: 25 false, 40 true)")


-- PaperNotes: what a paper costs by design at a haste.
do
  local function hh(ews) return { ws = 3.0, rangedMul = 3.0 / ews, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0, castCorr = 1,
    multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 } end
  local n = M.PaperNotes(M.STRINGS["5:5:1:1"], hh(1.93), 0.35)
  ok(n and n.clipMs > 500 and n.clipAutos >= 3, "PaperNotes: 5:5:1:1 at its floor clips by design")
  local tag, text = M.PaperNoteText(n)
  ok(tag == "clips by design" and text:find("clips on purpose", 1, true) ~= nil, "...named as such")
  local w = M.PaperNotes(M.STRINGS["5:5:1:1 3w"], hh(2.174), 0.35)
  ok(w and w.tightWeaves >= 1 and w.weaves == 3, "PaperNotes: 5:5:1:1 3w at 2.17 has a tight weave")
  local c = M.PaperNotes(M.STRINGS["1:1"], hh(2.174), 0.35)
  local ctag = M.PaperNoteText(c)
  ok(c and c.clipMs == 0 and c.tightWeaves == 0 and ctag == nil, "PaperNotes: 1:1 costs nothing by design")
end

-- N. THE BASIC PAPERS CARRY A MULTI IN PRACTICE. rotationtools: "All basic
-- rotations use only steady shot for illustration purposes, but in practice
-- should use multi shot instead of a steady shot whenever it is off CD".
-- M.PaperString lays the paper at a haste: the first whole number of cycles
-- that covers Multi's cooldown, the last Steady of them a Multi.
do
  local hB = { ws = 3.0, rangedMul = 3.0 / 1.59, mws = 3.7, meleeMul = 1, imprArcanePts = 0, castCorr = 1,
               multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 }
  local p11 = M.PaperString("1:1", hB)
  ok(p11 and p11:sub(-1) == "m" and select(2, p11:gsub("m", "")) == 1 and p11:sub(1, 2) == "as",
     "PaperString 1:1: one Multi per period, in the last Steady's slot (" .. tostring(p11) .. ")")
  local lay11 = M.Layout(p11, hB, 0)
  ok(lay11.dur >= 10 - 1e-6 and lay11.dur < 10 + 1.59 + 1e-6,
     ("...the period is the first whole number of cycles that covers Multi's cooldown (%.2f s)"):format(lay11.dur))
  ok((lay11.delay or 0) < 1e-6, "...and it costs no auto: the Multi fits where the Steady did")
  ok(M.PaperString("5:5:1:1", hB) == M.STRINGS["5:5:1:1"], "PaperString: a French paper is its canonical string")
  ok(M.PaperString("drill 1:1", hB) == "as", "PaperString: a teaching paper is its own string (the ladder's beat rung stays Steady-only)")
  ok(M.PaperString("1:1") == "as", "PaperString without a haste is the illustration")
  ok(M.PaperString("no such", hB) == nil, "PaperString: an unknown notation is nil, like STRINGS")
  for _, k in ipairs({ "1:2", "2:3", "2:5" }) do
    local s = M.PaperString(k, hB)
    ok(s and s:find("m", 1, true) ~= nil and M.Layout(s, hB, 0).dur >= 10 - 1e-6,
       "PaperString " .. k .. " carries a Multi over a period >= its cooldown (" .. tostring(s) .. ")")
  end
end

print(("practice_model: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
