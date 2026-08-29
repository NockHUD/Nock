-- Tests/practice_engine_test.lua
-- Standalone LuaJIT tests for Modules/PracticeEngine.lua: the simulated hunter
-- (swing grid, presses, GCD, spell queue, clip band, macro parsing).
-- Run from the repo root: luajit Tests/practice_engine_test.lua

local E = dofile("Modules/PracticeEngine.lua")

-- Re-arm cost: the one definition lives in Core/State.lua; load it the way
-- clip_threshold_test does and inject it into the engine.
do
  local NockStub = {}
  _G.GetRangedHaste = function() return 0 end
  _G.LibStub = function() return { GetAddon = function() return NockStub end } end
  dofile("Core/State.lua")
  _G.RELEASE_COST = NockStub.ReleaseCost
end

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-3) end

-- Drive the engine at a fixed tick until `untilT`, inclusive.
local function run(e, fromT, untilT, dt)
  local t = fromT
  while t <= untilT + 1e-9 do
    E.Step(e, t)
    t = t + (dt or 0.01)
  end
end
local function kinds(e, kind)
  local out = {}
  for i = 1, e.n do
    if e.events[i].kind == kind then out[#out + 1] = e.events[i] end
  end
  return out
end
local function procOnCount(e, name, on)
  local n = 0
  for _, p in ipairs(kinds(e, "proc")) do if p.name == name and p.on == on then n = n + 1 end end
  return n
end

-- quickShots = false on every base config below: these are the pre-proc grid
-- tests (swing/press/GCD/queue/clip timing) and must not have a Quick Shots
-- proc silently changing rangedMul mid-run. Proc/haste behaviour has its own
-- configs (HP) and Quick Shots its own seeded fights, further down.
local H = { ws = 3.0, baseRangedMul = 1.38, latency = 0, queueWindow = 0.4, quickShots = false }
local CYCLE, WINDUP = 3.0 / 1.38, 0.5 / 1.38

-- 1. Start + arm: first auto lands one wind-up after the arming press, then
--    every cycle; the grid is release-to-release (Nock dummy measurement).
local e = E.New(H)
E.StartFight(e, 100)
E.Press(e, { "autoshot" }, 100)
run(e, 100, 100 + WINDUP + 3 * CYCLE + 0.1)
local autos = kinds(e, "auto")
ok(#autos == 4, "four autos in a wind-up + three cycles (" .. #autos .. ")")
ok(near(autos[1].t, 100 + WINDUP), "first auto at t0 + windup")
ok(near(autos[2].t - autos[1].t, CYCLE), "release-to-release = cycle")
ok(autos[1].delay == 0 and autos[2].delay == 0, "no delay on a clean grid")
ok(e.events[1].kind == "pull" and e.events[1].t == 100, "pull event first")

-- 2. Not armed: nothing fires
e = E.New(H)
E.StartFight(e, 0)
run(e, 0, 10)
ok(#kinds(e, "auto") == 0, "no autos while disarmed")

-- 3. Snapshot publishes the grid
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 1.0)
local s = {}
E.Snapshot(e, s)
ok(near(s.cycle, CYCLE) and near(s.windup, WINDUP), "snapshot cycle/windup")
ok(s.repeating == true, "snapshot repeating")
ok(near(s.nextShotAt, WINDUP + CYCLE), "snapshot next shot on the grid")
ok(s.cast == nil and s.gcdDur == 0, "snapshot idle gcd/cast")

-- 4. Stop ends the stream
E.StopFight(e, 2.0)
ok(e.events[e.n].kind == "stop", "stop event last")
run(e, 2.0, 10)
ok(e.events[e.n].kind == "stop", "nothing after stop")

-- 5. The pull macro "/cast Steady Shot" + "/cast !Auto Shot": the cast starts
--    on the press, the grid forms behind it (first shot = cast end + wind-up,
--    no clip), then release-to-release.
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "steady", "autoshot" }, 0)
run(e, 0, 2 * CYCLE + 0.1)
local presses = kinds(e, "press")
ok(presses[1].result == "ok" and presses[1].key == "steady", "first press ok")
local casts = kinds(e, "cast")
ok(#casts == 1 and casts[1].spell == "steady" and near(casts[1].t1 - casts[1].t0, 1.5 / 1.38),
   "steady cast = 1.5/haste")
autos = kinds(e, "auto")
ok(#autos == 2 and autos[1].delay == 0 and autos[2].delay == 0, "pull steady does not clip")
ok(near(autos[1].t, 1.5 / 1.38 + WINDUP), "first shot = cast end + wind-up")
ok(near(autos[2].t - autos[1].t, CYCLE), "then on the grid")

-- 5b. The other order, "/cast !Auto Shot" first: the wind-up starts inside the
--     press, so the Steady queues behind the first shot — also no clip.
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot", "steady" }, 0)
run(e, 0, 2 * CYCLE + 0.1)
presses = kinds(e, "press")
ok(presses[1].result == "queued" and presses[1].ctx.inWindup, "steady queues behind the opening wind-up")
casts = kinds(e, "cast")
ok(near(casts[1].t0, WINDUP), "queued steady starts at the first shot")
autos = kinds(e, "auto")
ok(#autos == 2 and autos[2].delay == 0, "no clip either way")

-- 6. GCD: with the Steady running from WINDUP (gcd ends WINDUP + 1.5), a press
--    at 0.6 has > 1.2s of gcd left — NOT READY.
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot", "steady" }, 0)
E.Press(e, { "arcane" }, 0.6)
run(e, 0, 0.7)
presses = kinds(e, "press")
ok(presses[3].result == "notready", "press deep inside the gcd is not ready (" .. tostring(presses[3].result) .. ")")

-- 7. Spell queue: a press within 0.4s of the gcd end (gcd ends WINDUP + 1.5)
--    is queued and starts exactly when the gcd ends.
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot", "steady" }, 0)
local gcdEnd = WINDUP + 1.5
E.Press(e, { "arcane" }, gcdEnd - 0.3)
run(e, 0, gcdEnd + 0.1)
presses = kinds(e, "press")
-- presses: [1] steady queued, [2] steady ok (queued fire), [3] arcane queued, [4] arcane ok
ok(presses[3].result == "queued", "press 0.3s before gcd end is queued")
ok(presses[4].result == "ok" and near(presses[4].t, gcdEnd) and near(presses[4].queuedFrom, gcdEnd - 0.3),
   "queued arcane fires at gcd end")
casts = kinds(e, "cast")
ok(#casts == 2 and casts[2].spell == "arcane" and casts[2].t0 == casts[2].t1, "arcane is instant")

-- 8. Cooldowns: Multi 10s (from cast end), Arcane 6s; a press on cd is refused
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot", "multi" }, 0)        -- multi queues behind the opening wind-up
run(e, 0, 2.0)
E.Press(e, { "multi" }, 2.0)
run(e, 2.0, 2.1)
presses = kinds(e, "press")
ok(presses[3].result == "cooldown", "multi on cooldown refused")
s = {}; E.Snapshot(e, s)
ok(near(s.msReadyAt, WINDUP + 0.5 / 1.38 + 10), "multi cd runs from cast end")

-- 9. Moving: Steady/Multi refused, Arcane allowed
e = E.New(H)
E.StartFight(e, 0)
E.SetMoving(e, true)
E.Press(e, { "autoshot", "steady" }, 0)
E.Press(e, { "arcane" }, WINDUP + 0.1)       -- after the opening shot, gcd free
run(e, 0, WINDUP + 0.2)
presses = kinds(e, "press")
ok(presses[1].result == "moving", "steady while moving refused")
ok(presses[2].result == "ok", "arcane while moving ok")

-- 10. Latency delays the effect, not the press
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0.1 })
E.StartFight(e, 0)
E.Press(e, { "autoshot", "steady" }, 0)
run(e, 0, 0.2)
presses = kinds(e, "press")
ok(near(presses[1].t, 0.1), "press lands one latency later")

-- 11. /stopcasting cancels the cast, gcd stays
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot", "steady" }, 0)
E.Press(e, { "stopcasting" }, 0.5)
run(e, 0, 0.6)
casts = kinds(e, "cast")
ok(#casts == 1 and casts[1].cancelled and near(casts[1].t1, 0.5), "stopcasting cancels")
s = {}; E.Snapshot(e, s)
ok(s.cast == nil and s.gcdDur == 1.5, "cast gone, gcd still running")

-- 12. free event marks the busy->free edge with context
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot", "steady" }, 0)
run(e, 0, 2.0)
local frees = kinds(e, "free")
ok(#frees == 1 and near(frees[1].t, WINDUP + 1.5) and frees[1].ctx.msReady == true, "free at gcd end")

-- 13. CLIP: a Steady started too late runs across the wind-up; the shot is
--     pushed by exactly the overlap and the grid re-anchors on the late shot.
--     Grid: shot at WINDUP, next wind-up starts at WINDUP + CYCLE - WINDUP =
--     CYCLE. Press Steady at CYCLE - 0.5 => cast ends CYCLE - 0.5 + 1.087.
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot" }, 0)
local pressAt = CYCLE - 0.5
E.Press(e, { "steady" }, pressAt)
run(e, 0, 2 * CYCLE + 1)
autos = kinds(e, "auto")
local castEnd = pressAt + 1.5 / 1.38
local expectedDelay = castEnd - CYCLE
ok(#autos >= 2 and near(autos[2].delay, expectedDelay), "shot delayed by the cast overlap")
ok(near(autos[2].t, castEnd + WINDUP), "shot fires one wind-up after the cast ends")
ok(autos[2].cause == "cast", "delay attributed to the cast")
ok(near(autos[3].t - autos[2].t, CYCLE), "grid re-anchors on the late release")

-- 14. Queue edge: a press INSIDE the wind-up is held and starts at the shot,
--     for free (Nock.ClipQueueEdge).
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot" }, 0)
local windupStart = CYCLE            -- second wind-up begins here
E.Press(e, { "steady" }, windupStart + 0.1)
run(e, 0, CYCLE + 2)
presses = kinds(e, "press")
ok(presses[1].result == "queued" and presses[1].ctx.inWindup, "press inside wind-up queues")
autos = kinds(e, "auto")
ok(autos[2].delay == 0, "queued press costs nothing")
casts = kinds(e, "cast")
ok(near(casts[1].t0, windupStart + WINDUP), "queued cast starts at the shot")

-- 15. A Steady that fits exactly (press at wind-up start - cast) does not clip
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot" }, 0)
E.Press(e, { "steady" }, CYCLE - 1.5 / 1.38)
run(e, 0, CYCLE + 1)
autos = kinds(e, "auto")
ok(autos[2].delay < 1e-6, "a cast ending at wind-up start is free")

-- 16. Macro parser: /cast, /use, !Auto Shot, /stopcasting, brackets stripped,
--     unknown lines reported.
local NAMES = { ["steady shot"] = "steady", ["multi-shot"] = "multi",
                ["arcane shot"] = "arcane", ["auto shot"] = "autoshot" }
local out, unk = {}, {}
E.ParseMacro("/stopcasting\n/cast [nochanneling] Steady Shot\n/cast !Auto Shot\n/use Haste Potion", NAMES, out, unk)
ok(#out == 3 and out[1] == "stopcasting" and out[2] == "steady" and out[3] == "autoshot", "parsed in order")
ok(#unk == 1 and unk[1] == "/use Haste Potion", "unknown line reported")
out, unk = {}, {}
E.ParseMacro("#showtooltip\n/cast Multi-Shot", NAMES, out, unk)
ok(#out == 1 and out[1] == "multi" and #unk == 0, "#showtooltip ignored, multi parsed")
out, unk = {}, {}
E.ParseMacro("/castsequence reset=10 Multi-Shot, Steady Shot", NAMES, out, unk)
ok(#out == 1 and out[1] == "multi", "castsequence: first step only")

-- 16b. Rank-qualified names: "(Rank 4)" is stripped like a [conditional].
out, unk = {}, {}
E.ParseMacro("/cast Steady Shot(Rank 4)\n/cast [nomod] Multi-Shot (Rank 3)\n/cast !Auto Shot", NAMES, out, unk)
ok(#out == 3 and out[1] == "steady" and out[2] == "multi" and out[3] == "autoshot",
   "rank qualifiers stripped (" .. table.concat(out, ",") .. ")")
ok(#unk == 0, "no rank-qualified line reported as unknown")

-- 16c. "!Auto-Shot": a hyphen where the client's name has a space is the
-- commonest hand-typed spelling of the start-attack macro. It must resolve to
-- the same action, or the slot silently loses its key. The exact form still
-- wins first, so a genuinely hyphenated name is untouched.
out, unk = {}, {}
E.ParseMacro("/cast !Auto-Shot\n/startattack", NAMES, out, unk)
ok(table.concat(out, ",") == "autoshot,startattack",
   "hyphenated !Auto-Shot parses as autoshot (" .. table.concat(out, ",") .. ")")
ok(#unk == 0, "hyphenated auto shot is not reported as unknown")
out, unk = {}, {}
E.ParseMacro("/cast Multi-Shot", NAMES, out, unk)
ok(#out == 1 and out[1] == "multi", "an exactly hyphenated name still matches itself")

-- 17. A second queued press replaces the first and says so
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot", "steady", "multi" }, 0)
run(e, 0, WINDUP + 0.1)
presses = kinds(e, "press")
-- [1] steady queued, [2] steady replaced, [3] multi queued, [4] multi ok (fires at the shot)
ok(presses[2].result == "replaced" and presses[2].key == "steady", "replaced steady is logged")
ok(presses[4].key == "multi" and presses[4].result == "ok", "multi fires at the shot")
casts = kinds(e, "cast")
ok(#casts == 0 or casts[1].spell ~= "steady", "the replaced steady never casts")

-- 18. castCorr: the measured residual Nock.RangedCastTime applies to the live
--     cast bar scales the simulated cast too (and the ctx the grader reads).
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, castCorr = 1.1 })
E.StartFight(e, 0)
E.Press(e, { "steady" }, 0)
run(e, 0, 2.0)
casts = kinds(e, "cast")
ok(#casts == 1 and near(casts[1].t1 - casts[1].t0, 1.1 * 1.5 / 1.38),
   "steady cast scales by castCorr (" .. tostring(casts[1] and (casts[1].t1 - casts[1].t0)) .. ")")
presses = kinds(e, "press")
ok(near(presses[1].ctx.steadyCast, 1.1 * 1.5 / 1.38), "ctx steadyCast carries castCorr")
ok(near(presses[1].ctx.multiCast, 1.1 * 0.5 / 1.38), "ctx multiCast carries castCorr")

-- 19. Cooldowns come from cfg, and Arcane never inherits Multi's length.
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0,
            multiCd = 8, arcaneCdBase = 6, arcaneCdPerPt = 0.2, imprArcanePts = 2 })
E.StartFight(e, 0)
E.Press(e, { "multi" }, 0)
run(e, 0, 1.0)
s = {}; E.Snapshot(e, s)
ok(near(s.msReadyAt, 0.5 / 1.38 + 8), "multi cd comes from cfg.multiCd (" .. tostring(s.msReadyAt) .. ")")
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0,
            arcaneCdBase = 6, arcaneCdPerPt = 0.2, imprArcanePts = 2 })
E.StartFight(e, 0)
E.Press(e, { "arcane" }, 0)
run(e, 0, 0.1)
s = {}; E.Snapshot(e, s)
ok(near(s.arcReadyAt, 5.6), "arcane cd = base - perPt * points (" .. tostring(s.arcReadyAt) .. ")")

-- 18. Mash: repeated presses of the spell in flight / already queued are
--     silent — the spell queue already guarantees the cast.
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot", "steady" }, 0)      -- steady queues behind the wind-up
E.Press(e, { "steady" }, 0.1)                -- mash while queued
E.Press(e, { "steady" }, 0.2)
run(e, 0, WINDUP + 0.5)                      -- steady now casting
E.Press(e, { "steady" }, WINDUP + 0.5)       -- mash while in flight
run(e, WINDUP + 0.5, WINDUP + 0.6)
presses = kinds(e, "press")
-- [1] steady queued, [2] steady ok (queued fire) — nothing else
ok(#presses == 2, "mashed steady emits nothing (" .. #presses .. " presses)")
ok(presses[1].result == "queued" and presses[2].result == "ok" and presses[2].queuedFrom == 0, "only the real press and its fire")

-- 19. A DIFFERENT spell pressed early is still logged (not ready), and a
--     different spell inside the queue window still replaces the queued one.
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot", "steady" }, 0)
E.Press(e, { "arcane" }, 0.6)                -- gcd ends WINDUP+1.5: > 0.4s away
run(e, 0, 0.7)
presses = kinds(e, "press")
ok(presses[3] and presses[3].key == "arcane" and presses[3].result == "notready", "different spell early is logged")
ok(not presses[3].mash, "a different spell early is not a mash")

-- 20. Regression: a same-spell mash landing in the same Step() call as the
--     PREVIOUS cast's completion must not see a stale e.cast and be
--     swallowed. Step() applies pending presses (phase 1) before it clears a
--     completed cast (phase 2), so the guard must check currency (t1 > at),
--     not just spell identity. Steady queued behind the opening wind-up
--     fires and casts (ends at WINDUP + 1.5/1.38); a second steady pressed
--     0.003s after that cast ends is only 0.41s ahead of the still-running
--     GCD — outside the 0.4s queue window, so once graded normally it reads
--     "notready", same as any other early press of a spell not already in
--     flight — but it MUST be a real, graded press, not silently eaten.
--     The final Step() is called at the exact collision instant (not marched
--     in from a coarse dt) so phase 1 (apply the press) and phase 2 (clear
--     the completed cast) are forced into the very same call regardless of
--     tick granularity — the scenario the stale-cast bug depends on.
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot", "steady" }, 0)
local firstCastEnd = WINDUP + 1.5 / 1.38
local mashAt = firstCastEnd + 0.003
E.Press(e, { "steady" }, mashAt)
run(e, 0, firstCastEnd - 0.01, 0.05)   -- everything short of the cast completing
E.Step(e, mashAt)                      -- collision: press applies + stale cast clears together
run(e, mashAt, mashAt + 0.5, 0.05)
presses = kinds(e, "press")
-- [1] steady queued, [2] steady ok (queued fire), [3] steady mash — graded, not eaten
ok(#presses == 3, "post-cast mash is graded, not swallowed (" .. #presses .. " presses)")
ok(presses[3] and presses[3].key == "steady" and presses[3].result == "notready",
   "stale-cast mash reads as a genuine early press (" .. tostring(presses[3] and presses[3].result) .. ")")
-- ...and it is TAGGED as a mash: the spell that started the running GCD is the
-- spell being pressed, so the grader must not bill it as an early press.
ok(presses[3] and presses[3].mash == true,
   "same-spell press in the post-cast gap is tagged mash (" .. tostring(presses[3] and presses[3].mash) .. ")")

-- 21. NormalizeKey (pure): canonical ALT-CTRL-SHIFT order, MOUSEn -> BUTTONn.
ok(E.NormalizeKey("shift+2") == "SHIFT-2", "normalize: shift+2 (" .. tostring(E.NormalizeKey("shift+2")) .. ")")
ok(E.NormalizeKey("ctrl-shift-f") == "CTRL-SHIFT-F", "normalize: ctrl-shift-f (" .. tostring(E.NormalizeKey("ctrl-shift-f")) .. ")")
ok(E.NormalizeKey("SHIFT-CTRL-F") == "CTRL-SHIFT-F", "normalize: typed order reordered (" .. tostring(E.NormalizeKey("SHIFT-CTRL-F")) .. ")")
ok(E.NormalizeKey("mouse5") == "BUTTON5", "normalize: mouse5 -> BUTTON5 (" .. tostring(E.NormalizeKey("mouse5")) .. ")")
ok(E.NormalizeKey("numpad1") == "NUMPAD1", "normalize: numpad1 untouched (" .. tostring(E.NormalizeKey("numpad1")) .. ")")
ok(E.NormalizeKey("") == "", "normalize: empty stays empty")

-- 22. Snapshot during a clipping cast: nextShotAt reports the GRID (the bar
--     fills and sits full as a held shot, like live), never the pushed shot —
--     re-anchoring at the cast's start jumped the bar back by the overlap.
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot" }, 0)
local pressAt22 = CYCLE - 0.5
E.Press(e, { "steady" }, pressAt22)
run(e, 0, CYCLE - 0.1, 0.01)           -- cast in flight, wind-up blocked
s = {}; E.Snapshot(e, s)
local pushedShot = (pressAt22 + 1.5 / 1.38) + WINDUP
ok(near(s.nextShotAt, WINDUP + CYCLE), "snapshot keeps the grid during a clip (" .. tostring(s.nextShotAt) .. ")")
run(e, CYCLE - 0.1, pushedShot - 0.1, 0.01)  -- cast over, wind-up started late, shot not yet out
s = {}; E.Snapshot(e, s)
ok(near(s.nextShotAt, WINDUP + CYCLE) and s.windupAt ~= nil, "still the grid while the late wind-up runs (" .. tostring(s.windupAt) .. ")")
run(e, pushedShot - 0.1, pushedShot + 0.5, 0.01)
autos = kinds(e, "auto")
ok(#autos >= 2 and near(autos[2].t, pushedShot), "the actual auto event is the pushed shot")
s = {}; E.Snapshot(e, s)
ok(near(s.nextShotAt, pushedShot + CYCLE), "after the late shot the grid re-anchors on it")

-- 22b. No cast in flight: snapshot still equals the plain grid time.
e = E.New(H)
E.StartFight(e, 0)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 0.2)                         -- before the first shot fires
s = {}; E.Snapshot(e, s)
ok(near(s.nextShotAt, WINDUP), "snapshot equals the grid with no blocking cast (" .. tostring(s.nextShotAt) .. ")")

-- 23. Zones follow RangeFinder's definitions as the distance changes
local HW = { ws = 3.0, baseRangedMul = 1.38, latency = 0, mws = 3.7, baseMeleeMul = 1.0, quickShots = false }
e = E.New(HW)
E.StartFight(e, 0)
-- StartFight only ARMS; range events are held back until the pull, so press
-- something first. "stopattack" pulls without arming the auto, which keeps this
-- test on zones alone.
E.Press(e, { "stopattack" }, 0)
E.SetDistance(e, 7)    -- start: on the ring, can shoot
run(e, 0, 0.01)
ok(e.zone == "WEAVE" and e.canShoot and e.nearRing and not e.inMelee, "7 yd = WEAVE (shoot + near ring)")
E.SetDistance(e, 9);  run(e, 0.01, 0.02)
ok(e.zone == "FAR", "9 yd = FAR")
-- OUT is "cannot shoot AND not near the ring" (RangeFinder's ladder), so it
-- needs a distance past Auto Shot's maximum: 20 yd is still a shot, i.e. FAR.
E.SetDistance(e, 40); run(e, 0.02, 0.03)
ok(e.zone == "OUT", "40 yd = OUT")
E.SetDistance(e, 4);  run(e, 0.03, 0.04)
ok(e.zone == "DEEP" and e.inMelee and not e.canShoot, "4 yd = DEEP (in melee, cannot shoot)")
local ranges = kinds(e, "range")
ok(#ranges == 4 and ranges[4].zone == "DEEP" and ranges[4].inMelee == true, "range events on change only")

-- 23b. Speed-only reckoning: your keys and nothing else move you
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.SetNow(e, 0.1);  E.Reckon(e, 7.0, 0.1)       -- run for 0.1 s: 0.7 yd closer
ok(near(e.dist, 6.3), "Reckon: running closes at speed (" .. tostring(e.dist) .. ")")
E.SetNow(e, 0.4);  E.Reckon(e, 0, 0.3)         -- stop: nothing moves
ok(near(e.dist, 6.3), "Reckon: standing holds the distance exactly (no settle)")
E.SetNow(e, 0.6);  E.Reckon(e, 7.0, 0.2)       -- creep to the divider: 1.4 yd -> 4.9, melee
ok(e.inMelee and near(e.dist, 4.9), "Reckon: a forward step into 5 yd is melee")
E.SetNow(e, 0.7);  E.Reckon(e, 4.5, 0.04)      -- one backpedal tick: 0.18 yd -> 5.08, out
ok(not e.inMelee and near(e.dist, 5.08) and e.canShoot, "Reckon: one backpedal tick leaves melee")
E.SetNow(e, 1.0);  E.Reckon(e, 0, 0.3)
ok(near(e.dist, 5.08), "Reckon: stopping just outside melee stays there (the bar does not drift)")
E.SetNow(e, 1.5);  E.Reckon(e, 4.5, 0.5)       -- backpedal 2.25 yd -> 7.33: out of the ring
ok(not e.nearRing and near(e.dist, 7.33), "Reckon: backpedalling out of the ring")
E.SetNow(e, 2.0);  E.Reckon(e, 0.3, 0.4)       -- a crawl below stillSpeed counts as standing
ok(near(e.dist, 7.33), "Reckon: below stillSpeed is standing")
E.SetNow(e, 3.0);  E.Reckon(e, 7.0, 1.0)       -- floor at 0.5 yd
ok(near(e.dist, 0.5), "Reckon: the closing floor is 0.5 yd")
-- A speed bonus: run 7.56, backpedal 4.86. Against the fixed 4.5 split the
-- backpedal would read as running; against the run speed it retreats.
E.SetNow(e, 4.0);  E.Reckon(e, 4.86, 0.5, 7.56)
ok(near(e.dist, 0.5 + 4.86 * 0.5) and near(e.dirSplit, 7.56 * 0.82), "Reckon: a boosted backpedal retreats (split scales with run speed)")
E.SetNow(e, 4.5);  E.Reckon(e, 7.56, 0.1, 7.56)
ok(near(e.dist, 0.5 + 4.86 * 0.5 - 0.756), "Reckon: a boosted run closes")

-- Dead zone never fires before the first auto is armed (no grid yet).
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 4); run(e, 0, 1.0)
ok(#kinds(e, "deadzone") == 0, "no dead zone before the first auto exists")

-- 23c. Weave on the way out, under latency: the server judges the press
--      against the position it had when the press was made. Enter melee, poke
--      + Raptor + /startattack, and be backpedalled out before the press even
--      reaches the server — the Raptor still connects, at the press's server
--      moment. Without the poke the re-check pulse finds nobody (luck regime).
local HL = { ws = 3.0, baseRangedMul = 1.38, latency = 0.1, mws = 3.7, baseMeleeMul = 1.0, quickShots = false }
e = E.New(HL)
E.StartFight(e, 0)
E.SetDistance(e, 5.4)
run(e, 0, 1.0)
E.SetNow(e, 1.0);  E.SetDistance(e, 4.7)                 -- tap in
E.Weave(e, true, { "snowball", "stopcasting", "raptor", "startattack" }, 1.05)
E.SetNow(e, 1.12); E.SetDistance(e, 5.15)                -- backpedalled out before 1.15
run(e, 1.12, 1.5)
local hits = kinds(e, "melee")
ok(#hits == 1 and hits[1].hit == "r" and near(hits[1].t, 1.15),
   "weave on the way out: Raptor lands at the press's server moment (" .. tostring(hits[1] and hits[1].t) .. ")")
ok(e.legs and e.legs.hitAt and near(e.legs.hitAt, 1.15), "weave on the way out: the leg records the hit")
E.Weave(e, false, { "killcommand", "autoshot" }, 1.3)
run(e, 1.5, 2.0)
ok(#kinds(e, "melee") == 1, "weave on the way out: one hit, not two")

-- Attack started from OUTSIDE, then walked in and straight out, no poke: the
-- server's re-check pulse finds nobody (the luck regime).
e = E.New(HL)
E.StartFight(e, 0)
E.SetDistance(e, 5.4)
run(e, 0, 0.9)
E.Weave(e, true, { "stopcasting", "raptor", "startattack" }, 0.85)   -- key outside, no poke
run(e, 0.9, 1.0)
E.SetNow(e, 1.0);  E.SetDistance(e, 4.7)                 -- step in
E.SetNow(e, 1.12); E.SetDistance(e, 5.15)                -- and out before the pulse
run(e, 1.12, 2.5)
ok(#kinds(e, "melee") == 0, "attack from outside, in and out before the pulse: nothing lands")

-- Same start, but staying in: the hit lands at entry + latency + pulse.
e = E.New(HL)
E.StartFight(e, 0)
E.SetDistance(e, 5.4)
run(e, 0, 0.9)
E.Weave(e, true, { "stopcasting", "raptor", "startattack" }, 0.85)
run(e, 0.9, 1.0)
E.SetNow(e, 1.0);  E.SetDistance(e, 4.7)
run(e, 1.0, 2.0)
hits = kinds(e, "melee")
ok(#hits == 1 and near(hits[1].t, 1.6), "attack from outside, staying in: hit at entry + latency + pulse (" .. tostring(hits[1] and hits[1].t) .. ")")

-- 23d. No poke, but the attack is started from INSIDE melee: swings at once.
--      (Started from outside and walked in: waits for the re-check pulse.)
e = E.New(HL)
E.StartFight(e, 0)
E.SetDistance(e, 5.4)
run(e, 0, 1.0)
E.SetNow(e, 1.0);  E.SetDistance(e, 4.7)                 -- step in
E.Weave(e, true, { "stopcasting", "raptor", "startattack" }, 1.1)   -- key inside, no poke
E.SetNow(e, 1.2);  E.SetDistance(e, 5.2)                 -- out before the pulse would run
run(e, 1.2, 2.0)
hits = kinds(e, "melee")
ok(#hits == 1 and hits[1].hit == "r" and near(hits[1].t, 1.2),
   "startattack inside melee swings at once, no poke needed (" .. tostring(hits[1] and hits[1].t) .. ")")

-- First auto of the fight is not late against a grid that did not exist.
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Weave(e, true, { "stopcasting", "raptor", "startattack" }, 0.5)
E.Weave(e, false, { "autoshot" }, 0.9)
run(e, 0, 2.0)
local firstAuto = kinds(e, "auto")[1]
ok(firstAuto and firstAuto.delay == 0, "first arm of the fight: delay 0 (" .. tostring(firstAuto and firstAuto.delay) .. ")")

-- 23e. Arcane fires regardless of the auto timer and never moves it
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)                 -- shot at WINDUP, next at WINDUP + CYCLE
run(e, 0, WINDUP - 0.1)
E.Press(e, { "arcane" }, WINDUP - 0.1)        -- inside the wind-up, GCD free
run(e, WINDUP - 0.1, WINDUP + 0.2)
local pr = kinds(e, "press")
ok(pr[#pr].key == "arcane" and pr[#pr].result == "ok" and near(pr[#pr].t, WINDUP - 0.1), "arcane inside the wind-up fires at once (" .. tostring(pr[#pr].result) .. ")")
local au = kinds(e, "auto")
ok(#au == 1 and near(au[1].t, WINDUP) and au[1].delay == 0, "the shot is untouched by the instant")
run(e, WINDUP + 0.2, WINDUP + CYCLE + 0.1)
au = kinds(e, "auto")
ok(#au == 2 and near(au[2].t, WINDUP + CYCLE), "next shot on the grid (" .. tostring(au[2] and au[2].t) .. ")")

-- Arcane spammed during a weave hold must not re-arm or re-base the auto.
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 1.0)
local gridBefore = e.nextShotAt
E.Weave(e, true, { "snowball", "raptor", "startattack" }, 1.0)
run(e, 1.0, 1.1)
E.Press(e, { "arcane" }, 1.1)
run(e, 1.1, 1.3)
ok(e.repeating == false and e.nextShotAt == gridBefore and e.gridShotAt == gridBefore, "arcane mid-hold leaves the auto off and the grid where it was")
E.Weave(e, false, { "autoshot" }, 1.3)
run(e, 1.3, 1.4)
ok(e.repeating == true and e.meleeOn == false, "!Auto Shot re-arms and switches the melee auto off")

-- 23f. No unshootable sliver outside melee: one backpedal tick out of melee
--      can shoot again, and a wind-up never sticks in a 5.00..5.01 gap.
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 1.0)
E.SetNow(e, 1.0); E.SetDistance(e, 5.005)
ok(e.canShoot and not e.inMelee and e.zone ~= "GAP", "5.005 yd is shootable (zone " .. tostring(e.zone) .. ")")
run(e, 1.0, CYCLE + 1.0)
ok(#kinds(e, "auto") == 2, "the auto keeps firing from 5.005 yd")

-- A hold before the first auto has no budget to overrun.
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 4)
E.Weave(e, true, { "snowball", "raptor", "startattack" }, 0.2)
E.SetNow(e, 0.4); E.SetDistance(e, 6)
E.Weave(e, false, { "autoshot" }, 0.5)
run(e, 0, 1.0)
we = kinds(e, "weave")
local dn = we[#we]
ok(dn.edge == "done" and dn.legs.budget == math.huge and dn.legs.total <= dn.legs.budget, "no grid: budget is unbounded, never slow by total")

-- 23g. /startattack is range-aware: at range it is an Auto Shot arm that never
--      re-bases a running grid; inside melee it is the weave's melee switch.
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "startattack", "arcane" }, 0.1)   -- the user's Arcane macro, on the pull
run(e, 0, 1.0)
ok(e.repeating == true and e.meleeOn == false, "/startattack at range arms Auto Shot")
local g1 = e.nextShotAt
for t = 1.0, 1.4, 0.1 do E.Press(e, { "startattack", "arcane" }, t) end
run(e, 1.0, 1.5)
ok(e.repeating == true and e.meleeOn == false and e.nextShotAt == g1, "spamming it at range leaves the grid alone")
E.SetNow(e, 1.5); E.SetDistance(e, 4.8)
E.Press(e, { "startattack", "arcane" }, 1.55)    -- pressed inside melee: melee auto
run(e, 1.5, 1.6)
ok(e.meleeOn == true and e.repeating == false, "/startattack inside melee switches to the melee auto")

-- 24. Entering melee only pauses the ranged auto: it stays armed, no shot
--     lands while too close, and it resumes (late, cause "range") once back out
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 1.0)
E.SetNow(e, 1.0); E.SetDistance(e, 4)
run(e, 1.0, CYCLE + 1.0)
ok(e.repeating == true, "stepping in leaves the auto armed")
ok(#kinds(e, "auto") == 1, "no shot while too close")
E.SetNow(e, CYCLE + 1.0); E.SetDistance(e, 7)
run(e, CYCLE + 1.0, CYCLE + 2.0)
au = kinds(e, "auto")
ok(#au == 2 and au[2].cause == "range" and near(au[2].t, CYCLE + 1.0 + WINDUP), "back out: the auto resumes with a fresh wind-up, cause range (" .. tostring(au[2] and au[2].t) .. ")")

-- 25. Weave down with the shipped macro: Raptor queued, melee auto on, no hit
--     until in melee AND the re-check pulse has elapsed (no poke)
local DOWN = { "stopcasting", "raptor", "startattack" }
local UP   = { "stopattack", "autoshot" }
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 0.5)
E.Weave(e, true, DOWN, 0.5)
run(e, 0.5, 0.6)
ok(e.meleeOn and e.raptorQueued and not e.repeating, "down: melee on, raptor queued, auto off")
E.SetDistance(e, 4)          -- step in at 0.6
run(e, 0.6, 0.9)
ok(#kinds(e, "melee") == 0, "no hit before the 0.5 s re-check")
run(e, 0.9, 1.2)
local hits = kinds(e, "melee")
ok(#hits == 1 and hits[1].hit == "r" and near(hits[1].t, 1.1), "Raptor lands at the re-check (0.6 + 0.5)")
ok(near(e.raptorReadyAt, 1.1 + 6), "raptor cooldown 6 s from the hit")
ok(near(e.meleeReadyAt, 1.1 + 3.7), "melee swing timer reset by the hit")
ok(not e.raptorQueued, "raptor consumed")

-- 26. The Snowball poke on the down line makes the hit land the instant you are in melee
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 0.5)
E.Weave(e, true, { "snowball", "stopcasting", "raptor", "startattack" }, 0.5)
run(e, 0.5, 0.6)
E.SetDistance(e, 4)
run(e, 0.6, 0.65)
hits = kinds(e, "melee")
ok(#hits == 1 and near(hits[1].t, 0.6), "poked: hit at the step-in (" .. tostring(hits[1] and hits[1].t) .. ")")

-- 27. A second hold while Raptor is on cooldown lands a white hit, and only
--     once the melee swing timer is ready
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 4)
E.Weave(e, true, { "snowball", "raptor", "startattack" }, 0)
run(e, 0, 0.1)
ok(kinds(e, "melee")[1].hit == "r", "first hit raptor")
E.Weave(e, false, UP, 0.2); run(e, 0.2, 0.3)
E.Weave(e, true, { "snowball", "raptor", "startattack" }, 0.4)
run(e, 0.4, 3.6)
ok(#kinds(e, "melee") == 1, "no second hit before the melee timer (3.7 s)")
run(e, 3.6, 3.8)
hits = kinds(e, "melee")
ok(#hits == 2 and hits[2].hit == "w" and near(hits[2].t, 3.7), "white hit when the timer is ready, raptor still on cd")
ok(not e.raptorQueued, "the swing consumed the queued raptor even on cooldown")

-- 28. Weave edges are logged and the key-held state tracks the hold
e = E.New(HW)
E.StartFight(e, 0)
E.Weave(e, true, DOWN, 1.0); run(e, 1.0, 1.1)
ok(e.weaveDownAt == 1.0, "weaveDownAt stamped")
E.Weave(e, false, UP, 1.5); run(e, 1.5, 1.6)
ok(e.weaveDownAt == nil, "released")
ok(not e.raptorQueued, "stopattack drops the queued raptor")
local we = kinds(e, "weave")
-- The hold never left the shooting ring, so the "done" edge fires at the
-- release with a hitless legs table (nil = that leg never happened).
ok(#we == 3 and we[1].edge == "down" and we[2].edge == "up" and we[3].edge == "done" and we[3].legs.hit == nil,
   "weave edge events")

-- 29. ParseMacro learns /startattack, /stopattack and the weave names
local WNAMES = { ["steady shot"] = "steady", ["raptor strike"] = "raptor", ["snowball"] = "snowball",
                 ["kill command"] = "killcommand", ["auto shot"] = "autoshot" }
out, unk = {}, {}
E.ParseMacro("/use Snowball\n/stopcasting\n/cast Raptor Strike\n/startattack", WNAMES, out, unk)
ok(table.concat(out, ",") == "snowball,stopcasting,raptor,startattack", "down body parsed (" .. table.concat(out, ",") .. ")")
out, unk = {}, {}
E.ParseMacro("/cast [target=pettarget,exists] Kill Command\n/cast !Auto Shot\n/stopattack", WNAMES, out, unk)
ok(table.concat(out, ",") == "killcommand,autoshot,stopattack", "up body parsed (" .. table.concat(out, ",") .. ")")

-- 30. Re-arm with the swing ready: a fresh wind-up starts at the release
local HR = { ws = 3.0, baseRangedMul = 1.38, latency = 0, mws = 3.7, releaseCost = RELEASE_COST, rearmPulse = 0.5, quickShots = false }
e = E.New(HR)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 0.5)
E.Weave(e, true, { "snowball", "raptor", "startattack" }, 0.5)   -- auto off
E.SetDistance(e, 4); run(e, 0.5, 0.7)
E.SetDistance(e, 7); run(e, 0.7, CYCLE + 1.0)                     -- grid shot time long past
E.Weave(e, false, { "stopattack", "autoshot" }, CYCLE + 1.0)
run(e, CYCLE + 1.0, CYCLE + 1.0 + WINDUP + 0.05)
autos = kinds(e, "auto")
ok(#autos == 2 and near(autos[2].t, CYCLE + 1.0 + WINDUP) and autos[2].cause == "rearm", "held shot: fresh wind-up from the release")
we = kinds(e, "weave")
ok(we[2].edge == "up" and near(we[2].cost, 0), "re-arm after ready is free")

-- 30b. The same release with rearmWindupAfterReady OFF: the held shot needs no
--      fresh wind-up, so it fires AT the release. The option is a calibration
--      knob (/nock weavelog), so both readings of the client must be modelled.
local HRF = { ws = 3.0, baseRangedMul = 1.38, latency = 0, mws = 3.7, releaseCost = RELEASE_COST,
              rearmPulse = 0.5, rearmWindupAfterReady = false, quickShots = false }
local relOff = CYCLE + 1.0
e = E.New(HRF)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 0.5)
E.Weave(e, true, { "snowball", "raptor", "startattack" }, 0.5)
E.SetDistance(e, 4); run(e, 0.5, 0.7)
E.SetDistance(e, 7); run(e, 0.7, relOff)
E.Weave(e, false, { "stopattack", "autoshot" }, relOff)
run(e, relOff, relOff + WINDUP + 0.05)
autos = kinds(e, "auto")
ok(#autos == 2 and near(autos[2].t, relOff) and autos[2].cause == "rearm",
   "flag off: the held shot fires at the release (" .. tostring(autos[2] and autos[2].t) .. ")")
ok(near(autos[2].delay, relOff - (WINDUP + CYCLE)), "flag off: delay measured against the grid it left")

-- 31. Re-arm while the swing is still recharging pays the retry grid
e = E.New(HR)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 0.5)
E.Weave(e, true, { "snowball", "raptor", "startattack" }, 0.5)
E.SetDistance(e, 4); run(e, 0.5, 0.7)
E.SetDistance(e, 7); run(e, 0.7, 1.0)
local gridShot = WINDUP + CYCLE
local relAt = gridShot - 0.8                        -- 0.8 s before ready: cost = 1.0 - 0.8 = 0.2
E.Weave(e, false, { "stopattack", "autoshot" }, relAt)
run(e, relAt, gridShot + 0.5)
we = kinds(e, "weave")
ok(near(we[2].cost, RELEASE_COST(0.8, 0.5)), "cost from Nock.ReleaseCost (" .. tostring(we[2].cost) .. ")")
autos = kinds(e, "auto")
ok(#autos == 2 and near(autos[2].t, gridShot + RELEASE_COST(0.8, 0.5)) and autos[2].cause == "rearm",
   "shot pushed by the retry cost")

-- 32. Footwork legs on the done event, with the budget from the down moment
e = E.New(HR)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 0.5)
E.Weave(e, true, { "snowball", "raptor", "startattack" }, 0.5)
run(e, 0.5, 0.7)
E.SetSpeed(e, 7); E.SetDistance(e, 4)    -- e.t is 0.7: in at 0.7, hit at 0.7 (poked)
run(e, 0.7, 1.0)
E.SetSpeed(e, 3); E.SetDistance(e, 6)    -- e.t is 1.0: backpedal out at 1.0
run(e, 1.0, 1.05)
E.Weave(e, false, { "stopattack", "autoshot" }, 1.1); run(e, 1.1, 1.2)
we = kinds(e, "weave")
local done = we[3]
ok(done and done.edge == "done" and done.legs, "done event with legs")
ok(near(done.legs.stepIn, 0.2) and near(done.legs.dwell, 0) and near(done.legs.stepOut, 0.3) and near(done.legs.total, 0.5),
   ("legs in %.2f dwell %.2f out %.2f total %.2f"):format(done.legs.stepIn or -1, done.legs.dwell or -1, done.legs.stepOut or -1, done.legs.total or -1))
ok(near(done.legs.budget, (WINDUP + CYCLE - WINDUP) - 0.5), "budget = ttw at the down")
ok(done.legs.backIn == false and done.legs.backOut == true and done.legs.hit == "r", "backpedal flags and hit")
-- Backing off to hold range after the weave must not touch what was reported.
E.SetSpeed(e, 3); E.SetDistance(e, 9); run(e, 1.2, 1.3)
ok(done.legs.backOut == true and e.legs == nil, "reported legs released (e.legs " .. tostring(e.legs) .. ")")

-- 33. Opportunity windows open when the melee swing is ready and the auto is far enough away
e = E.New(HR)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.SetLegsNeeded(e, 0.7)
E.Press(e, { "autoshot" }, 0)          -- shot at WINDUP; next wind-up at CYCLE
run(e, 0, CYCLE - 0.5)
local opps = kinds(e, "opp")
ok(#opps >= 2 and opps[1].open == true and near(opps[1].t, WINDUP), "opportunity opens after the shot")
ok(opps[2].open == false and near(opps[2].t, CYCLE - 0.7), "closes legsNeeded before the wind-up")

-- 33b. Stepping in does not close the window (weave on the way out: step, then key)
e = E.New(HR)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.SetLegsNeeded(e, 0.7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, WINDUP + 0.3)
E.SetNow(e, WINDUP + 0.3); E.SetDistance(e, 4); run(e, WINDUP + 0.3, WINDUP + 0.4)
opps = kinds(e, "opp")
ok(#opps == 1 and opps[1].open == true, "stepping in leaves the window open (" .. #opps .. ")")
E.Weave(e, true, { "snowball", "raptor", "startattack" }, WINDUP + 0.4); run(e, WINDUP + 0.4, WINDUP + 0.5)
opps = kinds(e, "opp")
ok(#opps == 2 and opps[2].open == false and near(opps[2].t, WINDUP + 0.4), "the key closes it: taken")
ok(#kinds(e, "melee") == 1 and e.legs and near(e.legs.inAt, WINDUP + 0.4), "hit lands; step-in leg is zero (already inside at the key)")

-- 34. Dead zone: still in melee when the auto's wind-up wanted to start
e = E.New(HR)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 0.5)
E.Weave(e, true, { "snowball", "raptor", "startattack" }, 0.5)
E.SetDistance(e, 4); run(e, 0.5, CYCLE + 0.2)      -- linger in melee past the wind-up moment
local dz = kinds(e, "deadzone")
ok(#dz == 1 and near(dz[1].t, CYCLE), "deadzone once, at the wind-up moment (" .. tostring(dz[1] and dz[1].t) .. ")")
-- A weave made in the last Steady-less gap and out before the wind-up is not a dead zone.
e = E.New(HR)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, CYCLE - 0.6)
E.SetNow(e, CYCLE - 0.6); E.SetDistance(e, 4)
E.Weave(e, true, { "snowball", "raptor", "startattack" }, CYCLE - 0.6)
run(e, CYCLE - 0.6, CYCLE - 0.4)
E.SetNow(e, CYCLE - 0.4); E.SetDistance(e, 6)
E.Weave(e, false, { "autoshot" }, CYCLE - 0.3)
run(e, CYCLE - 0.4, CYCLE + 0.5)
ok(#kinds(e, "deadzone") == 0, "in and out before the wind-up: no dead zone")

-- 35. Key-only footwork synthesises the steps
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, footwork = "key", stepTime = 0.3, releaseCost = RELEASE_COST })
E.StartFight(e, 0)
E.Weave(e, true, { "snowball", "raptor", "startattack" }, 0); run(e, 0, 0.29)
ok(not e.inMelee, "not yet in")
run(e, 0.29, 0.31)
ok(e.inMelee, "in after stepTime")
E.Weave(e, false, { "stopattack", "autoshot" }, 0.5); run(e, 0.5, 0.81)
ok(not e.inMelee and e.canShoot, "out after stepTime")

-- 36. A shot whose moment has already passed is fired before either disarm
--     path runs — the step into melee and /startattack both used to erase it.
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, WINDUP + 0.01, 0.033)
E.SetDistance(e, 4)                        -- step in, stamped at the last tick
run(e, WINDUP + 0.01, WINDUP + 0.1, 0.033)
autos = kinds(e, "auto")
ok(#autos == 1 and near(autos[1].t, WINDUP), "step-in does not erase the earned shot")

-- 36b. The discriminating half: the edge is applied (phase 1) at a moment PAST
--      the shot, before the tick that would have fired it (phase 3).
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 0.33, 0.033)                     -- the tick has not reached the shot
E.Weave(e, true, { "startattack" }, WINDUP + 0.0005)
E.Step(e, 0.363)                           -- edge and shot collide in one Step
autos = kinds(e, "auto")
ok(#autos == 1 and near(autos[1].t, WINDUP), "startattack does not erase the earned shot")
ok(e.repeating == false and e.meleeOn, "auto-repeat still cancelled by the same edge")

-- 36c. Key-only footwork walks the hunter in on its own clock (phase 0), which
--      is where a step-in genuinely lands after a shot came due: the shot must
--      still be away before the step cancels auto-repeat.
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, footwork = "key", stepTime = 0.3 })
E.StartFight(e, 0)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 2.4, 0.033)                                          -- second wind-up running
E.Weave(e, true, { "raptor" }, WINDUP + CYCLE - 0.3 + 0.0005)  -- no /startattack: auto stays on
E.Step(e, 2.45)                                                -- the down edge lands
E.Step(e, WINDUP + CYCLE + 0.01)                               -- step-in and shot collide
autos = kinds(e, "auto")
ok(#autos == 2 and near(autos[2].t, WINDUP + CYCLE) and e.inMelee,
   "the synthesised step-in does not erase the shot")

-- 37. Out of range nothing fires and the swing keeps recharging; back in range
--     the held shot starts a fresh wind-up, with the range to blame.
e = E.New(HR)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 0.5)
E.Weave(e, true, { "snowball", "raptor", "startattack" }, 0.5)
E.SetDistance(e, 4); run(e, 0.5, 2.6)
E.Weave(e, false, { "stopattack", "autoshot" }, 2.6)   -- re-armed, still in melee
run(e, 2.6, 3.2)
ok(#kinds(e, "auto") == 1, "no shot while out of shooting range")
E.SetDistance(e, 7)
run(e, 3.2, 3.2 + WINDUP + 0.05)
autos = kinds(e, "auto")
ok(#autos == 2 and near(autos[2].t, 3.2 + WINDUP) and autos[2].cause == "range",
   "back in range: fresh wind-up from the step-out (" .. tostring(autos[2] and autos[2].cause) .. ")")

-- 38. Released before the hit: the weave still closes when shooting comes back
e = E.New(HR)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 0.5)
E.Weave(e, true, { "raptor", "startattack" }, 0.5)     -- no poke: no hit for 0.5 s
run(e, 0.5, 0.6)
E.SetDistance(e, 4); run(e, 0.6, 0.8)
E.Weave(e, false, { "stopattack", "autoshot" }, 0.8); run(e, 0.8, 0.9)
E.SetDistance(e, 7); run(e, 0.9, 1.0)
we = kinds(e, "weave")
ok(#we == 3 and we[3].edge == "done" and we[3].legs.hit == nil, "done fires without a hit")
ok(near(we[3].legs.stepIn, 0.1) and we[3].legs.dwell == nil and we[3].legs.stepOut == nil
   and near(we[3].legs.total, 0.4), "hitless legs (in/dwell/out/total)")

-- 39. A melee hit due before the release lands before /stopattack cancels it
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 4)
E.Weave(e, true, { "snowball", "raptor", "startattack" }, 0)
run(e, 0, 0.1)                             -- raptor at 0; swing ready again at 3.7
E.Weave(e, false, UP, 0.2); run(e, 0.2, 0.3)
E.Weave(e, true, { "snowball", "startattack" }, 0.4)
run(e, 0.4, 3.69, 0.033)                   -- the tick has not reached the swing
E.Weave(e, false, UP, 3.701)
E.Step(e, 3.706)                           -- release and swing collide in one Step
hits = kinds(e, "melee")
ok(#hits == 2 and hits[2].hit == "w" and near(hits[2].t, 3.7), "hit due before the release still lands")

-- 40. A finished weave's legs are frozen. The done event carries the hold's own
--     table, so a later backpedal — normal play: backing off to hold range once
--     the key is released — must not rewrite a flag inside an emitted event.
--     The hold never left the ring here, so its legs report no backpedal at all.
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Weave(e, true, DOWN, 1.0); run(e, 1.0, 1.1)
E.Weave(e, false, UP, 1.5); run(e, 1.5, 1.6)
we = kinds(e, "weave")
local frozen = we[3]
ok(frozen and frozen.edge == "done" and frozen.legs.backIn == false and frozen.legs.backOut == false,
   "done reported no backpedal")
E.SetSpeed(e, 3); E.SetDistance(e, 6)      -- backing off, after the weave closed
run(e, 1.6, 1.7)
ok(frozen.legs.backIn == false and frozen.legs.backOut == false, "the emitted legs stay frozen")
ok(e.legs == nil, "the hold's legs are released once reported")

-- 41. SetNow advances the clock without stepping, so a caller that samples
--     footwork BEFORE Step (Modules/Practice.lua does) stamps the melee entry
--     with this frame's time rather than the previous tick's.
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
run(e, 0, 1.0)
ok(near(e.t, 1.0), "clock sits on the last Step")
E.SetDistance(e, 3)                        -- stepping in WITHOUT SetNow first
ok(near(e.enteredMeleeAt, 1.0), "without SetNow the entry is dated to the last Step")
e = E.New(HW)
E.StartFight(e, 0)
E.SetDistance(e, 7)
run(e, 0, 1.0)
E.SetNow(e, 1.03)                          -- the tick that is about to run
E.SetDistance(e, 3)
ok(near(e.enteredMeleeAt, 1.03), "SetNow dates the entry to the current tick")
ok(near(e.t, 1.03), "SetNow moved the clock")

-- 36. Procs: haste stacks multiplicatively, the in-flight shot keeps its grid,
--     the melee swing rescales, RF/Drums/Pot presses proc and cool down.
local HP = { ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false, mws = 3.7 }
e = E.New(HP)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 1.0)
local gridBefore = e.nextShotAt
E.Proc(e, "RF", true, 1.0)
ok(near(e.rangedMul, 1.38 * 1.4) and near(e.cycle, 3.0 / (1.38 * 1.4)), "RF: x1.4 ranged")
ok(e.nextShotAt == gridBefore, "a haste change never moves the shot on the grid")
E.Proc(e, "Lust", true, 1.0)
ok(near(e.rangedMul, 1.38 * 1.4 * 1.3) and near(e.meleeMul, 1.3), "Lust: x1.3 both")
E.Proc(e, "Drums", true, 1.0)
ok(near(e.rangedMul, 1.38 * 1.4 * 1.3 * (1 + 80 / 1577))
   and near(e.meleeMul, 1.3 * (1 + 80 / 1577)), "Drums: +80 rating on both")
local hastes = kinds(e, "haste")
ok(#hastes == 3 and hastes[3].rf and hastes[3].lust and hastes[3].drums and not hastes[3].qs, "haste events carry the proc flags")
ok(#kinds(e, "proc") == 3 and kinds(e, "proc")[1].name == "RF" and kinds(e, "proc")[1].on == true, "proc events")
-- expiry at the exact moment
run(e, 1.0, 16.1)
ok(e.procs.RF == 0 and procOnCount(e, "RF", false) == 1, "RF expires after rfDur")
ok(near(kinds(e, "proc")[4].t, 16.0), "expiry stamped at the proc's own end, not the tick")
-- melee swing rescales with melee haste
e = E.New(HP)
E.StartFight(e, 0)
e.meleeReadyAt = 3.0
E.Proc(e, "Lust", true, 1.0)
ok(near(e.meleeReadyAt, 1.0 + 2.0 / 1.3), "melee swing in flight rescales proportionally")
-- cooldown presses
e = E.New(HP)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "rf" }, 0.5); E.Press(e, { "pot" }, 0.6); E.Press(e, { "t1" }, 0.7); E.Press(e, { "rf" }, 0.8)
run(e, 0, 1.0)
local cds = kinds(e, "cd")
ok(#cds == 4 and cds[1].key == "RF" and cds[1].used and cds[2].key == "Pot" and cds[3].key == "T1" and cds[4].used == false, "cd events; a second RF on cooldown is used=false")
ok(e.procs.RF > 0 and e.procs.Pot > 0 and near(e.cdReady.RF, 300.5), "RF and Pot proc; RF cools down 300 s")

-- 36b. After the fight stops, E.Proc still mutates state but emits nothing:
--      the haste event is gated on e.fightOn exactly like the proc event.
e = E.New(HP)
E.StartFight(e, 0)
E.StopFight(e, 0.5)
local nBefore, rmBefore = e.n, e.rangedMul
E.Proc(e, "RF", true, 0.5)
ok(near(e.rangedMul, rmBefore * 1.4) and e.n == nBefore,
   "E.Proc after StopFight changes rangedMul but appends no event")

-- 37. Quick Shots: seeded roll per auto; same seed, same fight
local function qsTimes(seed)
  local ee = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = true, seed = seed })
  E.StartFight(ee, 0); E.SetDistance(ee, 7); E.Press(ee, { "autoshot" }, 0)
  run(ee, 0, 200)
  local out = {}
  for _, p in ipairs(kinds(ee, "proc")) do if p.name == "QS" and p.on then out[#out + 1] = p.t end end
  return out, #kinds(ee, "auto")
end
local a1, n1 = qsTimes(7)
local a2 = qsTimes(7)
local a3 = qsTimes(10)
ok(#a1 > 0 and #a1 == #a2 and a1[1] == a2[1], "same seed -> same Quick Shots (" .. #a1 .. " procs in " .. n1 .. " autos)")
ok(#a1 ~= #a3 or a1[1] ~= a3[1], "different seed -> different fight")
ok(#a1 > n1 * 0.03 and #a1 < n1 * 0.25, "proc rate in the 10% ballpark (" .. #a1 .. "/" .. n1 .. ")")
-- Burn-in: Park-Miller's first raw draw off a small seed starts near zero
-- (seed 1 -> ~8e-6), which would proc Quick Shots on every fight's first
-- auto. E.Reset burns 16 draws in after seeding, so seed 1's first roll
-- against a real auto is no longer degenerate.
local a4 = qsTimes(1)
ok(#a4 == 0 or a4[1] > WINDUP + 0.01, "burned-in RNG: seed 1 does not proc QS on the first auto")

-- 38. ParseMacro: /use 13 and /use 14 are the trinket slots
local acts, unk = {}, {}
E.ParseMacro("/use 13\n/use 14\n/cast Rapid Fire", { ["rapid fire"] = "rf" }, acts, unk)
ok(acts[1] == "t1" and acts[2] == "t2" and acts[3] == "rf" and #unk == 0, "trinket slots and Rapid Fire parse")

-- 39. Scenario DSL and playback
local scs, errs = E.ParseScenario("Raid pull: lust@8 len=30\nBad line\nLocked: lock=5:5:1:1 ews=2.17 rf@3 foo=1")
ok(#scs == 2 and #errs == 2, "two scenarios, two errors (" .. #errs .. ")")
ok(scs[1].name == "Raid pull" and scs[1].events[1].proc == "Lust" and scs[1].events[1].t == 8 and scs[1].len == 30 and scs[1].qs == true, "raid pull parsed")
ok(scs[2].lock == "5:5:1:1" and scs[2].qs == false and near(scs[2].ews, 2.17) and scs[2].events[1].proc == "RF", "lock implies qs off")
ok(#E.SCENARIOS == 5 and E.SCENARIOS[5].name == "Raid pull" and #E.SCENARIOS[1].events == 0, "built-ins")
-- Ruling 2026-08-24: Clean French is a rotation to settle into, so its len=0
-- parses to nil and it runs until Stop; the scripted pull still ends itself.
ok(E.SCENARIOS[1].name == "Clean French" and E.SCENARIOS[1].len == nil, "Clean French never auto-stops")
ok(E.SCENARIOS[5].len == 60, "...while a script with an explicit len= still does")
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false })
E.LoadScenario(e, scs[1])
ok(e.cfg.quickShots == true, "LoadScenario keeps QS on for an unlocked scenario")
e.cfg.quickShots = false   -- this segment checks Lust timing, not QS; keep QS out of the way
E.StartFight(e, 100)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 100)
run(e, 100, 131, 0.05)
local procs = kinds(e, "proc")
ok(procs[1] and procs[1].name == "Lust" and near(procs[1].t, 108), "Lust lands at t0 + 8 exactly (" .. tostring(procs[1] and procs[1].t) .. ")")
local ends = kinds(e, "end")
ok(#ends == 1 and near(ends[1].t, 130) and e.ended, "end event once at t0 + len")
E.LoadScenario(e, scs[2])
ok(e.cfg.quickShots == false, "a locked scenario turns the QS roll off")
E.LoadScenario(e, nil)
ok(e.cfg.quickShots == true, "unloading a locked scenario (nil) restores QS")

-- 39b. ParseScenario: valid proc tokens sort by time; comments/blank lines skip
local rfLust = E.ParseScenario("X: rf@10 lust@2")
ok(#rfLust == 1 and rfLust[1].events[1].proc == "Lust" and rfLust[1].events[1].t == 2,
   "events sort by time regardless of token order")
local commented, cErrs = E.ParseScenario("# comment\n\nY: rf@1")
ok(#commented == 1 and commented[1].name == "Y" and #cErrs == 0, "comment and blank line are skipped, one scenario left")

-- 39c. ParseScenario: a proc token whose time is not a number is reported, not
--      stored — a nil `t` used to blow up the sort and then every Step().
local badT, bErrs = E.ParseScenario("X: rf@1.2.3 lust@8")
ok(#badT == 1 and #badT[1].events == 1 and badT[1].events[1].proc == "Lust" and badT[1].events[1].t == 8,
   "a malformed proc time drops the event, the good one survives")
ok(#bErrs == 1 and bErrs[1]:find("rf@1.2.3", 1, true) ~= nil, "the malformed token is reported")
ok(#(select(2, E.ParseScenario("X: rf@."))) == 1, "a bare dot is a bad time too")

-- 39d. Held procs (hold=) and open-ended scenarios (len=0): the "locked
--      drill" shape for Free play. A held proc never expires (phase 0b
--      skips names in e.hold); the pull turns it on right after itself.
local heldScs, heldErrs = E.ParseScenario("Held: hold=rf,qs")
ok(#heldErrs == 0 and heldScs[1].hold.RF == true and heldScs[1].hold.QS == true and heldScs[1].hold.Lust == nil,
   "hold=rf,qs parses to sc.hold = { RF = true, QS = true }")
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false })
E.LoadScenario(e, heldScs[1])
E.StartFight(e, 0)
E.Press(e, { "autoshot" }, 0)   -- the pull: held procs go up right after it
run(e, 0, 100, 1)
ok(e.procs.RF > 0, "a held RF is still up 100 s into the fight")
ok(procOnCount(e, "RF", true) == 1 and procOnCount(e, "RF", false) == 0,
   "exactly one proc(RF, on) in the log, never an off")
local pullI, hasteI
for i = 1, e.n do
  if e.events[i].kind == "pull" and not pullI then pullI = i end
  if e.events[i].kind == "haste" and not hasteI then hasteI = i end
end
ok(pullI and hasteI and hasteI > pullI, "the first haste event comes after the pull event")

local zeroScs, zeroErrs = E.ParseScenario("Endless: len=0")
ok(#zeroErrs == 0 and zeroScs[1].len == nil, "len=0 parses to sc.len == nil")
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false })
E.LoadScenario(e, zeroScs[1])
E.StartFight(e, 0)
E.Press(e, { "autoshot" }, 0)   -- pull, or the fight's clock never starts
run(e, 0, 200, 1)
ok(#kinds(e, "end") == 0, "len=0 never emits an end event, even 200 s in")

local badHold, badHoldErrs = E.ParseScenario("Bad: hold=foo")
ok(#badHoldErrs == 1 and badHoldErrs[1]:find("foo", 1, true) ~= nil, "hold=foo reports one error naming foo")

-- 40. Kill Command: a crit opens a 5 s window; KC lands once per window/cd,
--     never during a cast or wind-up; no crit chance -> never.
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false, critRanged = 1.0 })
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, WINDUP + 0.05)
ok(#kinds(e, "kcwin") == 1 and e.kcUntil > WINDUP, "a (certain) crit on the first auto opens the window")
E.Press(e, { "killcommand" }, WINDUP + 0.1)
run(e, WINDUP + 0.05, WINDUP + 0.2)
ok(#kinds(e, "kc") == 1, "KC lands inside the window")
E.Press(e, { "killcommand" }, WINDUP + 0.3)
run(e, WINDUP + 0.2, WINDUP + 0.4)
ok(#kinds(e, "kc") == 1, "KC on cooldown is silently ignored")
E.Press(e, { "steady", "killcommand" }, WINDUP + 5.2)   -- the Steady macro, new window from the 2nd/3rd auto
run(e, WINDUP + 0.4, WINDUP + 5.3)
ok(#kinds(e, "kc") == 1 and e.cast ~= nil, "KC pressed with the Steady does not fire during the cast")
run(e, WINDUP + 5.3, WINDUP + 6.4)
E.Press(e, { "killcommand" }, WINDUP + 6.5)      -- inside the 5th auto's wind-up
run(e, WINDUP + 6.4, WINDUP + 6.7)
ok(#kinds(e, "kc") == 1, "KC pressed inside the wind-up is dropped, not queued")
run(e, WINDUP + 6.7, WINDUP + 7.1)                -- the shot is away at ~7.01
E.Press(e, { "killcommand" }, WINDUP + 7.15)     -- free instant, window still open (every auto crits), cd long over
run(e, WINDUP + 7.1, WINDUP + 7.3)
ok(#kinds(e, "kc") == 2, "the press after the shot lands it")
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false, critRanged = 0 })
E.StartFight(e, 0); E.SetDistance(e, 7); E.Press(e, { "autoshot" }, 0); run(e, 0, 10)
E.Press(e, { "killcommand" }, 10); run(e, 10, 10.1)
ok(#kinds(e, "kcwin") == 0 and #kinds(e, "kc") == 0, "no crits, no window, no KC")

-- 41. A haste change INSIDE the wind-up never moves the shot it is already
--     winding up: the arrow leaves at the moment stamped when the wind-up
--     started, and only the NEXT cycle runs at the new speed.
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false, critRanged = 0 })
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "autoshot" }, 0)
run(e, 0, 0.1)
ok(e.windupAt ~= nil and near(e.windupShotAt, WINDUP), "the wind-up stamps its shot moment")
E.Proc(e, "RF", true, 0.1)                      -- Rapid Fire mid-wind-up
ok(e.windup < WINDUP and near(e.windupShotAt, WINDUP), "RF shortens the wind-up but not this shot")
run(e, 0.1, 0.6)
local autos41 = kinds(e, "auto")
ok(#autos41 == 1 and near(autos41[1].t, WINDUP),
   "the shot on the grid fires at its original moment (" .. tostring(autos41[1] and autos41[1].t) .. ")")
local RF_CYCLE = 3.0 / (1.38 * 1.4)
run(e, 0.6, WINDUP + RF_CYCLE + 0.1)
autos41 = kinds(e, "auto")
ok(#autos41 == 2 and near(autos41[2].t, WINDUP + RF_CYCLE, 0.02),
   "the next cycle runs at the hasted speed (" .. tostring(autos41[2] and autos41[2].t) .. ")")

-- 42. The press counter. The views' pre-pull hold turns on this and nothing
--     else: `nPending` drains as inputs are applied, so it cannot answer
--     "has anything been pressed yet".
e = E.New(H)
ok(e.nPress == 0, "a fresh engine has no presses")
E.StartFight(e, 0)
ok(e.nPress == 0, "arming is not a press")
E.Press(e, { "autoshot" }, 0)
ok(e.nPress == 1, "a press counts")
E.Weave(e, true, { "raptor" }, 0.5)
ok(e.nPress == 2, "the weave key counts too")
run(e, 0, 3)
ok(e.nPress == 2, "applying a press does not un-count it")
E.StartFight(e, 10)
ok(e.nPress == 0, "a new fight starts from zero")

-- 43. The fight starts at the FIRST PRESS. StartFight only ARMS: no events, no
--     clock, no autos, no script. The first press pulls, and everything the
--     fight is measured from is stamped there.
local scPull = E.ParseScenario("Pull: rf@2 len=10")[1]
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false })
E.LoadScenario(e, scPull)
E.StartFight(e, 100)
E.SetDistance(e, 7)
run(e, 100, 103)
ok(e.n == 0, "an armed fight emits nothing (" .. e.n .. " events)")
ok(e.fightOn == true and e.armed == true and e.pulled == false, "armed: the fight is on but not pulled")
ok(#kinds(e, "auto") == 0 and e.lastShotAt == 0, "no autos while armed")
local sArm = {}
E.Snapshot(e, sArm)
ok(sArm.armed == true and sArm.pulled == false, "the snapshot reports armed / not pulled")
E.Press(e, { "steady" }, 103)
ok(e.pulled == true and e.armed == false and near(e.t0, 103), "the first press pulls; t0 moves to it")
ok(e.events[1] and e.events[1].kind == "pull" and near(e.events[1].t, 103), "the pull event is first, at the press")
ok(e.events[2] and e.events[2].kind == "range" and e.events[2].zone == "WEAVE",
   "the zone you pulled in follows the pull")
run(e, 103, 103.1)
ok(e.events[3] and e.events[3].kind == "press" and e.events[3].key == "steady" and near(e.events[3].t, 103),
   "the press itself comes after the pull")
run(e, 103.1, 114)
local rfOn
for _, p in ipairs(kinds(e, "proc")) do if p.name == "RF" and p.on then rfOn = p.t end end
ok(rfOn and near(rfOn, 105), "a scripted rf@2 fires 2 s after the PULL, not after Start (" .. tostring(rfOn) .. ")")
local ends43 = kinds(e, "end")
ok(#ends43 == 1 and near(ends43[1].t, 113), "len=10 ends 10 s after the pull (" .. tostring(ends43[1] and ends43[1].t) .. ")")

-- Held procs wait for the pull too, and land immediately after it.
local heldSc43 = E.ParseScenario("Held2: hold=rf")[1]
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false })
E.LoadScenario(e, heldSc43)
E.StartFight(e, 0)
run(e, 0, 4)
ok(e.n == 0 and e.procs.RF == 0, "a held proc waits for the pull")
E.Press(e, { "steady" }, 4)
ok(e.events[1].kind == "pull" and e.events[2] and e.events[2].kind == "proc"
   and e.events[2].name == "RF" and e.events[2].on == true and near(e.events[2].t, 4),
   "the held proc event sits right after the pull")

-- An armed fight that is stopped was cancelled: no `stop`, no stream at all.
e = E.New(H)
E.StartFight(e, 0)
E.SetDistance(e, 7)
run(e, 0, 5)
E.StopFight(e, 5)
ok(e.n == 0 and e.fightOn == false, "stopping an armed fight emits nothing and leaves it off")
ok(e.armed == false and e.pulled == false, "a cancelled fight is neither armed nor pulled")
E.Reset(e)
ok(e.armed == false and e.pulled == false, "Reset clears armed/pulled")

-- A proc popped on the PANEL while the fight is only armed still counts: the
-- palette's buttons are live from Start, so the mutation happened but its
-- events were swallowed. The pull replays them, haste and all, or the grader's
-- first window would open at base haste.
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false })
E.StartFight(e, 0)
E.Proc(e, "RF", true, 1)            -- panel button, fight armed but not pulled
ok(e.n == 0, "a proc popped while armed emits nothing")
ok(near(e.rangedMul, 1.38 * 1.4), "...but it does change the haste")
E.Press(e, { "steady" }, 2)
ok(e.events[1] and e.events[1].kind == "pull" and near(e.events[1].t, 2), "pull first")
ok(e.events[2] and e.events[2].kind == "proc" and e.events[2].name == "RF" and e.events[2].on == true
   and near(e.events[2].t, 2), "the armed-time proc is replayed at the pull")
ok(e.events[3] and e.events[3].kind == "haste" and near(e.events[3].rangedMul, 1.38 * 1.4)
   and e.events[3].rf == true, "and the haste it is worth follows it")
run(e, 2, 2.1)
ok(e.events[4] and e.events[4].kind == "press" and e.events[4].key == "steady", "then the press")
ok(e.n == 4, "nothing else (" .. e.n .. " events)")

-- ...and one that had already run out by the pull is cleared silently: phase 0b
-- never ran while armed, so it would otherwise expire at a moment BEFORE the
-- pull and put the stream out of order.
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false })
E.StartFight(e, 0)
E.Proc(e, "QS", true, 0)            -- 12 s of Quick Shots, popped at 0
E.Press(e, { "steady" }, 30)
ok(e.procs.QS == 0 and near(e.rangedMul, 1.38), "an expired armed-time proc is gone by the pull")
local qsSeen = false
for i = 1, e.n do if e.events[i].kind == "proc" then qsSeen = true end end
ok(not qsSeen, "no proc event for it, on or off")
run(e, 30, 31)
local ordered, firstBad = true, nil
for i = 2, e.n do
  if e.events[i].t < e.events[i - 1].t - 1e-9 then ordered, firstBad = false, firstBad or i end
end
ok(ordered, "the stream stays in chronological order (first break at " .. tostring(firstBad) .. ")")

-- The seeded fight replays identically however long the panel sits on Start:
-- an armed Step draws no random numbers.
e = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = true, seed = 3 })
E.StartFight(e, 0, 3)
local rngArmed = e.rngState
E.SetDistance(e, 7)
run(e, 0, 20)
ok(e.rngState == rngArmed, "an armed fight draws no random numbers")

--------------------------------------------------------------------------------
-- THE WEAVE WINDOW FOLLOWS WHAT IS ACHIEVABLE (R5c).
--
-- `oppOpen` is a test made at `now`, and everything the strip drew about weaving
-- hung off it: the green gap band and the metronome's gap tick existed only
-- while it was true. It is the wrong shape for a forecast, and at speed it is
-- barely a shape at all — at eWS 0.90 the room in a cycle is 0.75 s against a
-- 0.70 s `legsNeeded`, so the flag is true for a twentieth of a second per
-- cycle. Worse, `legsNeeded` is the player's own measured footwork fed back:
-- ONE weave measured at 1.06 s puts it past every gap in the rotation and the
-- flag never goes true again — no band, no tick, silence, while the paper keeps
-- writing a `w` every 3.7 s.
--
-- E.WeaveWindow answers the question the views actually ask: WHEN NEXT, and how
-- much room. It walks the shot grid forward from the moment the swing is up (or
-- the cast in flight ends) and returns the first cycle with room for a full
-- weave — or, when the player's own legs no longer fit anywhere, the roomiest
-- window there is, which is the honest answer and not silence.
--------------------------------------------------------------------------------
do
  local RM = 3.0 / 0.90                        -- the 3:7 2w drill's own pin
  local WCFG = { ws = 3.0, baseRangedMul = RM, latency = 0.05, mws = 3.7,
                 baseMeleeMul = 1.0, quickShots = false, footwork = "key",
                 startDistance = 7, stepTime = 0.3, legsNeeded = 0.7 }
  local CYC, WU = 3.0 / RM, 0.5 / RM
  local DOWN = { "stopcasting", "raptor", "startattack" }

  local we = E.New(WCFG)
  E.StartFight(we, 0)
  E.Press(we, { "autoshot" }, 0)
  run(we, 0, 0.5)
  local at, room, fits = E.WeaveWindow(we, we.t)
  ok(at ~= nil and room ~= nil, "the engine answers when a weave is next possible")
  ok(fits == true, "...and says a whole weave fits in it")
  ok(at and at >= we.t - 1e-9, "...at a moment that has not already gone (" .. tostring(at) .. ")")
  ok(room and near(room, CYC - WU, 0.06),
     "...with the room a whole cycle leaves (" .. tostring(room) .. " vs "
     .. tostring(CYC - WU) .. ")")

  -- The swing still recharging: the window is the one that opens when it is up,
  -- not `now`, and not a paper slot the swing cannot serve.
  we.meleeReadyAt = we.t + 2.0
  local at2, room2 = E.WeaveWindow(we, we.t)
  ok(at2 and at2 >= we.t + 2.0 - 1e-9,
     "a recharging swing pushes the window to the moment it is up (" .. tostring(at2) .. ")")
  ok(room2 and room2 > 0, "...and the window still has room in it")

  -- THE FAILING CASE. One slow weave puts legsNeeded past every gap the
  -- rotation has. The opportunity flag never goes true again — and the window
  -- must still say where the room is.
  we.meleeReadyAt = 0
  E.SetLegsNeeded(we, 1.06)
  run(we, we.t, we.t + 3)
  local shut = we.oppOpen
  local at3, room3, fits3 = E.WeaveWindow(we, we.t)
  ok(not shut, "with legs past every gap the opportunity flag is shut")
  ok(at3 ~= nil and room3 and room3 > 0,
     "...but the weave window still names the roomiest moment there is ("
     .. tostring(at3) .. " / " .. tostring(room3) .. ")")
  -- ...and says so, so the band can be drawn as a hairline and the coach can
  -- tell the player to skip it rather than pointing at a gap they cannot make.
  ok(fits3 == false, "...and reports that a whole weave does NOT fit in it")
  -- ...and it is a moment a weave really can be made at: press the key inside
  -- the window and the hit lands.
  local before = #kinds(we, "melee")
  E.Weave(we, true, DOWN, at3)
  run(we, at3, at3 + 1.4)
  E.Weave(we, false, { "autoshot" }, at3 + 1.0)
  run(we, at3 + 1.0, at3 + 2.0)
  ok(#kinds(we, "melee") > before,
     "a weave made inside the window connects (" .. (#kinds(we, "melee") - before) .. " hit)")

  -- A clean fight keeps the window on the beat: the swing is long ready, so the
  -- window opens at the release the paper writes its `w` on.
  local ce = E.New(WCFG)
  E.StartFight(ce, 0)
  E.Press(ce, { "autoshot" }, 0)
  run(ce, 0, 3)
  local cAt, cRoom = E.WeaveWindow(ce, ce.t)
  local off = cAt and ((cAt - ce.lastShotAt) % ce.cycle) or nil
  ok(cAt and (near(off, 0, 0.02) or near(off, ce.cycle, 0.02)),
     "a clean weave keeps the window ON THE BEAT — a release of the grid, which is where "
     .. "the paper writes its `w` (" .. tostring(cAt) .. ", off-beat by " .. tostring(off) .. ")")
  ok(cRoom and near(cRoom, CYC - WU, 0.02),
     "...with the whole gap to play in (" .. tostring(cRoom) .. ")")

  -- The snapshot carries it, which is how the conveyor's band and the
  -- metronome's gap tick get at it.
  local s = {}
  E.Snapshot(ce, s)
  ok(s.weaveAt ~= nil and s.weaveRoom ~= nil, "the snapshot publishes the weave window")
  ok(s.weaveFits == true, "...and whether a whole weave fits in it")
end

-- R6b: the two press counters. The conveyor's press flash has to know which
-- LANE a press belongs on, and the only thing that tells it apart is which of
-- the two entry points was called. E.Weave bumps BOTH counters on every edge, so
-- `nPress` moving further than `nWeave` is an ability press and the remainder is
-- weave footwork -- no third field, and no reading of the pending queue, which
-- has usually drained by the time a view looks.
do
  local HP = { ws = 3.0, baseRangedMul = 1.38, latency = 0, mws = 3.7, baseMeleeMul = 1.0, quickShots = false }
  local ep = E.New(HP)
  ok(ep.nPress == 0 and ep.nWeave == 0, "R6b: a fresh engine has both counters at zero")
  E.StartFight(ep, 0)
  E.Press(ep, { "steady" }, 0.1)
  ok(ep.nPress == 1 and ep.nWeave == 0, "R6b: an ability press moves nPress only")
  E.Weave(ep, true, { "stopcasting", "raptor", "startattack" }, 0.5)
  ok(ep.nPress == 2 and ep.nWeave == 1, "R6b: a weave DOWN edge moves both")
  E.Weave(ep, false, { "autoshot" }, 0.9)
  ok(ep.nPress == 3 and ep.nWeave == 2, "R6b: ...and so does the UP edge")
  E.Press(ep, { "arcane" }, 1.0)
  ok(ep.nPress - ep.nWeave == 2, "R6b: the difference is the ability presses (" ..
     tostring(ep.nPress - ep.nWeave) .. ")")
  E.StartFight(ep, 10)
  ok(ep.nPress == 0 and ep.nWeave == 0, "R6b: a new fight resets both")
end

--------------------------------------------------------------------------------
-- R7: THE OPENER HAS NO DEADLINE TO MISS.
--
-- `apply` runs the cast BEFORE the "/cast !Auto Shot" that forms the grid, so at
-- the pull `nextShotAt` is still 0 and the press's ctx measured its time-to-
-- wind-up against it: minus the whole clock. The grader read that as "a Steady
-- that cannot fit before the wind-up" and billed the first press of every fight
-- a red STEADY WON'T FIT (visible as a fault mark on the conveyor's past lane in
-- the round-7 screenshot). No grid means no wind-up to be late against.
--------------------------------------------------------------------------------
do
  local OP = { ws = 3.0, baseRangedMul = 3.0 / 2.10, latency = 0, mws = 3.7,
               baseMeleeMul = 1.0, quickShots = false, armOnShot = true }
  local eo = E.New(OP)
  E.StartFight(eo, 1000)
  E.Press(eo, { "steady" }, 1002)
  E.Step(eo, 1002.01)
  local pull, later
  for i = 1, eo.n do
    local ev = eo.events[i]
    if ev.kind == "press" and ev.ctx then pull = pull or ev.ctx end
  end
  ok(pull ~= nil, "the pull emits a press with a ctx")
  ok(pull and pull.ttw == math.huge,
     "the opener's ctx carries no wind-up deadline (" .. tostring(pull and pull.ttw) .. ")")
  ok(pull and pull.steadyCast <= pull.ttw, "...so the opening Steady fits, by construction")
  -- ...and the moment the grid exists the number is real again.
  E.Step(eo, 1004.0)
  E.Press(eo, { "steady" }, 1004.0)
  E.Step(eo, 1004.02)
  for i = 1, eo.n do
    local ev = eo.events[i]
    if ev.kind == "press" and ev.ctx and (ev.t or 0) >= 1004 then later = ev.ctx end
  end
  ok(later ~= nil and later.ttw < math.huge and near(later.ttw, (eo.nextShotAt - eo.windup) - 1004.0, 0.05),
     "a press with a grid under it measures the real time to the wind-up")
end

-- MOVE spans (the expert combat log, 2026-08-27): every stretch the feet
-- moved is one `move` event with t0..t1, filed when it ends; the open one is
-- on the snapshot; the stop closes it; key-only footwork files each
-- synthesised leg.
do
  local em = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false })
  E.StartFight(em, 0)
  E.SetDistance(em, 20)
  E.Press(em, { "autoshot" }, 0)
  run(em, 0, 1.0)
  E.SetNow(em, 1.0); E.SetMoving(em, true)
  run(em, 1.0, 1.5)
  local snap = E.Snapshot(em, {})
  ok(near(snap.movingSince or -1, 1.0), "moving: the open span's start rides the snapshot")
  ok(#kinds(em, "move") == 0, "...and nothing is filed while the feet still move")
  E.SetNow(em, 1.5); E.SetMoving(em, false)
  local mv = kinds(em, "move")
  ok(#mv == 1 and near(mv[1].t0, 1.0) and near(mv[1].t1, 1.5) and not mv[1].key, "the stretch is filed as one move span when it ends")
  ok(E.Snapshot(em, {}).movingSince == nil, "...and the snapshot's open span is gone")
  E.SetMoving(em, false)
  ok(#kinds(em, "move") == 1, "a repeated 'not moving' files nothing")
  E.SetNow(em, 2.0); E.SetMoving(em, true)
  E.StopFight(em, 2.4)
  mv = kinds(em, "move")
  ok(#mv == 2 and near(mv[2].t0, 2.0) and near(mv[2].t1, 2.4) and em.events[em.n].kind == "stop", "the stop closes an open stretch before the stop event")
  -- Key-only footwork: each synthesised leg is a move span, real feet ignored.
  local ek = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, footwork = "key", stepTime = 0.3, releaseCost = RELEASE_COST, quickShots = false })
  E.StartFight(ek, 0)
  E.Weave(ek, true, { "snowball", "raptor", "startattack" }, 0); run(ek, 0, 0.35)
  E.SetNow(ek, 0.2); E.SetMoving(ek, true); E.SetNow(ek, 0.25); E.SetMoving(ek, false)
  mv = kinds(ek, "move")
  ok(#mv == 1 and mv[1].key == true and near(mv[1].t0, 0) and near(mv[1].t1, 0.3), "key footwork: the step in is a move span of stepTime, and the real feet file nothing")
  E.Weave(ek, false, { "stopattack", "autoshot" }, 0.5); run(ek, 0.5, 0.85)
  mv = kinds(ek, "move")
  ok(#mv == 2 and near(mv[2].t0, 0.5) and near(mv[2].t1, 0.8), "...and the step out is the second")
end

-- E.Hold (the palette's second click, 2026-08-27): a proc held by hand is up
-- for the rest of the fight, the scenario's own hold table is never written.
do
  local sc = { hold = { RF = true }, events = {} }
  local eh = E.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0, quickShots = false, lustDur = 4 })
  E.LoadScenario(eh, sc)
  ok(eh.scHold == sc.hold and eh.hold ~= sc.hold and eh.hold.RF == true, "the scenario's holds are copied into the fight's own set")
  E.StartFight(eh, 0)
  E.SetDistance(eh, 20)
  E.Press(eh, { "autoshot" }, 0)
  run(eh, 0, 1)
  E.Hold(eh, "Lust", true, 1)
  ok(eh.hold.Lust == true and sc.hold.Lust == nil and eh.procs.Lust > 1e8, "a hand-made hold parks the proc past the horizon and leaves the scenario alone")
  run(eh, 1, 8)
  ok(eh.procs.Lust > 8, "...and the expiry sweep skips it past its own duration")
  E.Hold(eh, "Lust", false, 8)
  ok(eh.hold.Lust == nil and eh.procs.Lust == 0, "letting go ends the hold and the proc")
  local offs = 0
  for _, pe in ipairs(kinds(eh, "proc")) do if pe.name == "Lust" and pe.on == false then offs = offs + 1 end end
  ok(offs == 1, "...with one proc-off on the stream")
end

print(("practice_engine: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
