-- Tests/practice_lesson_test.lua
-- Standalone LuaJIT tests for Core/PracticeLesson.lua: the one-cycle numbers the
-- lesson bar draws, the five narration lines, the fault-code -> step map, and
-- the reuse contract on `out`.
-- Run from the repo root: luajit Tests/practice_lesson_test.lua

local M = dofile("Core/PracticeModel.lua")
local L = dofile("Core/PracticeLesson.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 1e-3) end

-- The P1 BM baseline the whole practice suite uses: a 3.0 bow at quiver x
-- Serpent's Swiftness (1.38), i.e. eWS 2.174.
local function handle()
  return { ws = 3.0, rangedMul = 1.38, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0,
           multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 }
end

--------------------------------------------------------------------------------
-- 1. 5:5:1:1 3w at eWS 2.174 -- the fixture the plan names.
--------------------------------------------------------------------------------
do
  local h = handle()
  local str = M.STRINGS["5:5:1:1 3w"]
  local out = L.Build(str, h, M)

  ok(near(out.cycle, 3.0 / 1.38), "cycle is the weapon cycle, not the layout period")
  ok(near(out.cycle, 2.1739), "cycle 2.174")
  ok(near(out.windup, 0.5 / 1.38) and near(out.windup, 0.3623), "windup 0.362")
  ok(near(out.steadyCast, 1.5 / 1.38) and near(out.steadyCast, 1.0870), "steadyCast 1.087")
  ok(near(out.deadline, out.cycle - out.windup - out.steadyCast), "deadline is cycle - windup - steadyCast")
  ok(near(out.deadline, 0.7246), "deadline 0.725")
  ok(out.str == str, "the string is published back")
  ok(out.autos == 5 and out.multis == 1 and out.weaves == 3, "counts off the layout")

  -- The gap comes STRAIGHT off the layout: the first `w` slot, measured from
  -- the release of the cycle it falls in. rotationtools puts the French
  -- rotation's first weave on the release itself.
  local lay = M.Layout(str, h, 0)
  local rel, gt0, gt1 = nil, nil, nil
  for i = 1, #lay.ev do
    local e = lay.ev[i]
    if e.sym == "a" then rel = e.t0 + e.dur
    elseif e.sym == "w" and rel and not gt0 then gt0, gt1 = e.t0 - rel, e.t0 - rel + e.dur end
  end
  ok(out.gap ~= nil, "a weaving string has a gap")
  ok(near(out.gap.t0, gt0) and near(out.gap.t1, gt1), "gap is the layout's first w slot")
  ok(near(out.gap.t0, 0) and near(out.gap.t1, 0.4), "French 3w weaves on the release, 0.4 s wide")

  -- The worked clip: 0.4 s late off the deadline pushes the release 0.4 s.
  ok(near(out.clip.t0, out.deadline + 0.4), "clip example starts 0.4 s past the deadline")
  ok(near(out.clip.t1, out.clip.t0 + out.steadyCast), "clip example runs a full Steady")
  ok(near(out.clip.push, 0.4) and near(out.clip.release, out.cycle + 0.4),
     "a Steady 0.4 s late pushes the release exactly 0.4 s")

  -- Segments: the release tick, the casts that fit before the deadline, the
  -- wind-up at the end of the cycle, the gap band, the clip.
  local kinds, byKind = {}, {}
  for i = 1, out.nSegs do
    local s = out.segs[i]
    kinds[#kinds + 1] = s.kind
    byKind[s.kind] = byKind[s.kind] or s
  end
  ok(byKind.release and byKind.release.t0 == 0 and byKind.release.t1 == 0, "release tick at 0")
  ok(byKind.windup and near(byKind.windup.t0, out.cycle - out.windup) and near(byKind.windup.t1, out.cycle),
     "wind-up occupies [cycle - windup, cycle]")
  ok(byKind.gap and near(byKind.gap.t0, out.gap.t0), "gap band drawn at the gap")
  ok(byKind.clip and near(byKind.clip.t0, out.clip.t0), "clip lane drawn at the clip")
  local nCast = 0
  for i = 1, out.nSegs do
    local s = out.segs[i]
    if s.kind == "cast" then
      nCast = nCast + 1
      ok(s.t0 <= out.deadline + 1e-9, "every drawn cast starts at or before the deadline")
    end
  end
  ok(nCast == 1, "the French cycle draws its one Steady (the Multi starts past the deadline)")
  ok(byKind.cast.sym == "s" and near(byKind.cast.t0, 0) and near(byKind.cast.t1, out.steadyCast),
     "the Steady runs from the release for its whole cast")
  ok(out.forecast and out.forecast.sym == "s" and near(out.forecast.t1, out.steadyCast),
     "forecast tail is the next cycle's first cast")

  -- Lanes are the bar's three rows and nothing else.
  for i = 1, out.nSegs do
    local ln = out.segs[i].lane
    ok(ln == "shots" or ln == "weave" or ln == "clip", "seg lane " .. tostring(ln) .. " is one of the three")
  end

  -- Callouts: five of them for a weaving string, both hot ones marked.
  ok(out.nCallouts == 5, "five callouts on a weaving string")
  local hot, texts = 0, {}
  for i = 1, out.nCallouts do
    local c = out.callouts[i]
    texts[#texts + 1] = c.text
    if c.hot then hot = hot + 1 end
    ok(c.lane == "top" or c.lane == "bot", "callout lane is top/bot")
    ok(c.at >= 0 and c.at <= out.cycle + 1e-9, "callout sits inside the cycle")
  end
  ok(hot == 2, "the wind-up and the weave gap are the hot callouts")
  local all = table.concat(texts, " | ")
  ok(all:find("wind%-up starts at 1%.8 s"), "wind-up callout carries 1.8 s")
  ok(all:find("must START before 0%.7 s"), "deadline callout carries 0.7 s")
  ok(all:find("weave gap 0%.4 s"), "weave callout carries the gap width")
  ok(all:find("next release"), "the next release is called out")

  -- Narration.
  ok(out.nSteps == 5, "five narration steps")
  for i = 1, 5 do ok(type(out.steps[i]) == "string" and #out.steps[i] > 20, "step " .. i .. " is a sentence") end
  ok(out.steps[1]:find("2%.17 s"), "step 1 quotes the cycle to two decimals")
  ok(out.steps[2]:find("1%.09 s") and out.steps[2]:find("0%.7 s"), "step 2 quotes the cast and the slack")
  ok(out.steps[3]:find("weave gap"), "step 3 is the weave step on a weaving string")
  ok(out.steps[4]:find("1%.8 s"), "step 4 quotes the wind-up start")

  -- ASCII only: the display faces ship with holes in their punctuation.
  for i = 1, 5 do ok(not out.steps[i]:find("[\128-\255]"), "step " .. i .. " is ASCII") end
  for i = 1, out.nCallouts do ok(not out.callouts[i].text:find("[\128-\255]"), "callout " .. i .. " is ASCII") end

  -- Cursor marks: one per step, inside the cycle, strictly ascending.
  ok(#out.marks >= 5, "five cursor marks")
  local mono = true
  for i = 2, 5 do if not (out.marks[i] > out.marks[i - 1]) then mono = false end end
  ok(mono, "cursor marks are strictly ascending even when the gap opens on the release")
  ok(out.marks[1] == 0 and out.marks[5] < out.cycle, "marks span the cycle")
  ok(near(out.marks[4], out.cycle - out.windup), "step 4 lights at the wind-up")
end

--------------------------------------------------------------------------------
-- 2. Turret families: no gap, and step 3 is the Multi line -- or, with no Multi
--    in the string at all, neither.
--------------------------------------------------------------------------------
do
  local h = handle()
  local out = L.Build(M.STRINGS["1:1"], h, M)
  ok(out.gap == nil, "1:1 has no weave gap")
  ok(out.nCallouts == 4, "no weave callout without a weave")
  ok(not out.steps[3]:find("weave"), "1:1 step 3 is not the weave step")
  ok(not out.steps[3]:find("Multi"), "1:1 step 3 mentions no Multi -- the string has none")
  ok(near(out.cycle, 2.1739) and near(out.deadline, 0.7246), "1:1 shares the beat and the deadline")
  -- The bar still draws: release, one Steady, the wind-up, the clip.
  local n = 0
  for i = 1, out.nSegs do if out.segs[i].kind == "cast" then n = n + 1 end end
  ok(n == 1, "1:1 draws one cast")

  local turret = L.Build(M.STRINGS["5:5:1:1"], handle(), M)
  ok(turret.gap == nil, "5:5:1:1 is a turret: no gap")
  ok(turret.steps[3]:find("Multi%-Shot takes"), "turret step 3 is the Multi step")
  ok(turret.steps[3]:find("once every 5 cycles"), "5 autos, 1 Multi -> once every 5 cycles")
  ok(turret.steps[3]:find("0%.4 s"), "Multi cast quoted to one decimal")
  -- R4c: the turret papers all carry an Arcane as well as a Multi, and it is a
  -- different note -- instant, so it costs a GCD and nothing else.
  ok(turret.arcanes == 1, "5:5:1:1 has one Arcane in its period")
  ok(turret.steps[3]:find("Arcane Shot is instant"), "R4c: turret step 3 covers the Arcane too")
  ok(turret.steps[3]:find("Arcane Shot is instant %- free filler on the GCD, once every 5 cycles%."),
     "R4c: ...as queued filler, with its own cycle count to one decimal-free integer")
  -- Still five lines: L.STEP_FOR indexes them and the view has five rows.
  ok(turret.nSteps == 5 and turret.steps[6] == nil, "R4c: the narration is still five steps")

  -- A turret with no Arcane at all keeps the Multi sentence alone. There is no
  -- such notation in M.STRINGS (that IS the R4c finding), so it is asserted
  -- against a hand-written string rather than a shipped one.
  local mOnly = L.Build("asmasas", handle(), M)
  ok(mOnly.arcanes == 0 and mOnly.steps[3]:find("Multi%-Shot takes")
     and not mOnly.steps[3]:find("Arcane"),
     "R4c: an m-without-A string gets the Multi sentence and nothing else")
  -- ...and the mirror: an A-without-m string gets the Arcane sentence alone,
  -- where before it fell through to the "nothing else fits" line.
  local aOnly = L.Build("asAasas", handle(), M)
  ok(aOnly.multis == 0 and aOnly.arcanes == 1
     and aOnly.steps[3]:find("Arcane Shot is instant") and not aOnly.steps[3]:find("Multi"),
     "R4c: an A-without-m string gets the Arcane sentence alone")

  -- No CANONICAL notation has an `m` without an `A`: the finding the old rung's
  -- rename rested on, asserted rather than remembered. The Round 5b teaching
  -- papers are the deliberate exception -- `drill 1:1+m` exists precisely to be
  -- the m-without-A rung the shipped rotations could not supply.
  local bad = {}
  for notation, str in pairs(M.CANONICAL) do
    if str:find("m") and not str:find("A") then bad[#bad + 1] = notation end
  end
  ok(#bad == 0, "R4c: no canonical notation has a Multi without an Arcane ("
     .. table.concat(bad, ",") .. ")")
  ok(M.TEACHING["drill 1:1+m"]:find("m") and not M.TEACHING["drill 1:1+m"]:find("A"),
     "R5b: the teaching ladder supplies the Multi-without-Arcane rung instead")
end

--------------------------------------------------------------------------------
-- 2c. R5b teaching papers: the narration families they need, each built at the
--     paper's OWN pinned eWS (M.TEACHING_EWS) -- the haste the string was
--     written for, which is the only haste it teaches anything at.
--------------------------------------------------------------------------------
do
  local function teach(key)
    local h = handle()
    h.rangedMul = 3.0 / M.TEACHING_EWS[key]
    return L.Build(M.TEACHING[key], h, M), h
  end

  -- The turret rungs keep the Steady family: same three sentences, one more
  -- ability each rung.
  local beat = teach("drill 1:1")
  ok(near(beat.cycle, 2.10), "drill 1:1 draws the 2.10 s beat (" .. tostring(beat.cycle) .. ")")
  ok(beat.cycle > 1.5, "R5b addendum: the beat rung's cycle exceeds the GCD")
  ok(beat.gap == nil and beat.multis == 0 and beat.arcanes == 0, "drill 1:1 is bare")
  ok(beat.leadSym == "s", "drill 1:1 leads on the Steady")
  ok(beat.steps[2]:find("Steady Shot takes 1%.05 s"), "drill 1:1 step 2 is the Steady deadline")
  ok(near(beat.deadline, 0.70), "drill 1:1 deadline 0.70 (" .. tostring(beat.deadline) .. ")")

  local multi = teach("drill 1:1+m")
  ok(multi.multis == 1 and multi.arcanes == 0 and multi.autos == 5, "drill 1:1+m: 5 autos, one Multi")
  ok(multi.steps[3]:find("once every 5 cycles") and not multi.steps[3]:find("Arcane"),
     "drill 1:1+m step 3 is the Multi sentence alone")

  local arc = teach("drill 1:1+mA")
  ok(arc.multis == 1 and arc.arcanes == 2 and arc.autos == 6, "drill 1:1+mA: 6 autos, one Multi, two Arcanes")
  ok(arc.steps[3]:find("Multi%-Shot takes") and arc.steps[3]:find("Arcane Shot is instant"),
     "drill 1:1+mA step 3 covers both")
  ok(arc.steps[3]:find("once every 6 cycles") and arc.steps[3]:find("once every 3 cycles"),
     "...at their own cadences: Multi every 6, Arcane every 3")

  -- The castless weave paper: the beat and the gap, and no Steady sentence at
  -- all. This is the family that did not exist before R5b.
  local wb = teach("drill 1w")
  ok(near(wb.cycle, 3.70), "drill 1w draws the 3.70 s beat (" .. tostring(wb.cycle) .. ")")
  ok(wb.gap ~= nil and wb.weaves == 1, "drill 1w has a weave gap")
  ok(wb.leadSym == nil, "drill 1w casts nothing")
  ok(not wb.steps[2]:find("Steady"), "drill 1w step 2 does not talk about a Steady")
  ok(wb.steps[2]:find("nothing to cast") and wb.steps[2]:find("3%.70 s"),
     "drill 1w step 2 gives the cycle to your feet, to two decimals")
  ok(wb.steps[3]:find("weave gap"), "drill 1w step 3 is still the gap")
  ok(not wb.steps[5]:find("Steady"), "drill 1w step 5 is not the queue-a-Steady line")
  ok(wb.steps[5]:find("outside melee"), "...it is the step-out deadline")
  ok(wb.nCallouts == 4, "drill 1w: no deadline callout for a cast it does not have")
  local hasDeadline = false
  for i = 1, wb.nCallouts do
    if wb.callouts[i].text:find("must START") then hasDeadline = true end
  end
  ok(not hasDeadline, "...and no 'must START before' line either")

  -- The Arcane-on-the-way-out paper: a cast, but not a Steady. The deadline
  -- sentence follows the cast the paper actually asks for.
  local wo = teach("drill 1w+A")
  ok(wo.arcanes == 1 and wo.weaves == 2 and wo.autos == 2, "drill 1w+A: 2 autos, 2 weaves, one Arcane")
  ok(wo.leadSym == "A", "drill 1w+A leads on the Arcane")
  ok(wo.steps[2]:find("^Arcane Shot takes"), "drill 1w+A step 2 is about the Arcane")
  ok(not wo.steps[2]:find("Steady"), "...and never mentions a Steady the paper has none of")
  ok(wo.steps[5]:find("Pressing Arcane Shot during the wind%-up"), "drill 1w+A step 5 queues the Arcane")
  ok(wo.gap ~= nil and wo.steps[3]:find("weave gap"), "drill 1w+A keeps the gap sentence")

  -- Steady into the weave: the Steady family and the gap family together, on
  -- rung 6's own period (the track is cumulative -- the Arcane is still there).
  local ws = teach("drill 1w+s")
  ok(ws.weaves == 2 and ws.autos == 2 and ws.arcanes == 1,
     "drill 1w+s: two autos, two weaves, the Arcane rung 6 taught, and the new Steady")
  ok(ws.leadSym == "s" and ws.steps[2]:find("Steady Shot takes"),
     "drill 1w+s step 2 is the Steady -- the lead cast moved back to it")
  ok(ws.gap ~= nil and ws.steps[3]:find("weave gap"), "drill 1w+s step 3 is the gap")
  ok(ws.gap.t0 > 0, "...and the gap opens AFTER the Steady, not on the release ("
     .. ("%.2f"):format(ws.gap.t0) .. ")")
  ok(near(ws.gap.t0, ws.steadyCast, 1e-6),
     "...precisely: the Steady runs from the release and the weave starts where it ends")

  -- Every one of them: five ASCII sentences, five ascending marks, callouts
  -- inside the cycle. The contract the view is built on does not bend for a
  -- teaching paper.
  for key in pairs(M.TEACHING) do
    local out = teach(key)
    ok(out.nSteps == 5, key .. ": five narration steps")
    for i = 1, 5 do
      ok(type(out.steps[i]) == "string" and #out.steps[i] > 20, key .. " step " .. i .. " is a sentence")
      ok(not out.steps[i]:find("[\128-\255]"), key .. " step " .. i .. " is ASCII")
    end
    for i = 1, out.nCallouts do
      ok(not out.callouts[i].text:find("[\128-\255]"), key .. " callout " .. i .. " is ASCII")
      ok(out.callouts[i].at >= -1e-9 and out.callouts[i].at <= out.cycle + 1e-9,
         key .. " callout " .. i .. " sits inside the cycle")
    end
    local mono = true
    for i = 2, 5 do if not (out.marks[i] > out.marks[i - 1]) then mono = false end end
    ok(mono, key .. ": cursor marks ascend")
  end
end

--------------------------------------------------------------------------------
-- 2b. The max-haste weave, 3:7 2w at eWS 0.90 (Practice.lua's own pin). Its
--     string is `awasaawasaas`: the first cycle carries NOTHING but the auto
--     and a weave, so a cast scan anchored on the layout's origin came up
--     empty and the SHOTS lane drew a release, a wind-up and no note at all.
--     The lesson takes the first cast that fits in ANY cycle instead.
--------------------------------------------------------------------------------
do
  local h = handle()
  h.rangedMul = 3.0 / 0.90                      -- eWS 0.90 on the same 3.0 bow
  local out = L.Build(M.STRINGS["3:7 2w"], h, M)
  ok(near(out.cycle, 0.90), "3:7 2w draws the 0.90 s beat (" .. tostring(out.cycle) .. ")")
  local casts, steady = 0, nil
  for i = 1, out.nSegs do
    local s = out.segs[i]
    if s.kind == "cast" then casts = casts + 1; steady = steady or s end
  end
  ok(casts >= 1, "3:7 2w draws a cast on the SHOTS lane (" .. casts .. ")")
  ok(steady and steady.sym == "s", "...and it is the Steady (" .. tostring(steady and steady.sym) .. ")")
  ok(steady and steady.t0 >= -1e-9 and steady.t0 <= out.deadline + 1e-9,
     "...seated inside its own cycle, at or before the deadline (" .. tostring(steady and steady.t0) .. ")")
  ok(out.forecast ~= nil and out.forecast.sym == "s", "...and the dashed forecast tail is that cast")

  -- The first-cycle scan still wins where it finds something: the fixtures
  -- above are untouched by the fallback.
  local french = L.Build(M.STRINGS["5:5:1:1 3w"], handle(), M)
  local fc = 0
  for i = 1, french.nSegs do if french.segs[i].kind == "cast" then fc = fc + 1 end end
  ok(fc == 1 and french.forecast and near(french.forecast.t0, 0),
     "5:5:1:1 3w still draws its own first-cycle Steady on the release")
end

--------------------------------------------------------------------------------
-- 3. StepFor: the fault-code map.
--------------------------------------------------------------------------------
do
  ok(L.StepFor("CLIP") == 4, "CLIP -> 4")
  ok(L.StepFor("LATE") == 5, "LATE -> 5")
  ok(L.StepFor("WEAVE_MISSED") == 3, "WEAVE_MISSED -> 3")
  ok(L.StepFor("WEAVE_SLOW") == 3, "WEAVE_SLOW -> 3")
  ok(L.StepFor("DEAD_ZONE") == 3, "DEAD_ZONE -> 3")
  ok(L.StepFor("REARM") == 3, "REARM -> 3")
  ok(L.StepFor("STEADY_WONT_FIT") == 1, "an unmapped code falls back to the beat")
  ok(L.StepFor(nil) == 1, "nil code -> 1")
  ok(L.StepFor("GOOD") == 1, "a clean verdict -> 1")
  -- OFF and MISSED are per-note JUDGMENT grades, not fault codes: no fix card
  -- can carry them, so mapping them to a step was a row nothing read.
  ok(L.StepFor("OFF") == 1 and L.StepFor("MISSED") == 1,
     "a judgment grade is not a fault code and falls back to the beat")
  -- ...and every key that IS in the map is a code an analysis row can carry.
  local ADVICE = dofile("Modules/PracticeGrader.lua").ADVICE
  for code in pairs(L.STEP_FOR) do
    ok(ADVICE[code] ~= nil, code .. " is a real fault code (PracticeGrader.ADVICE)")
  end
end

--------------------------------------------------------------------------------
-- 4. Reuse: 100 rebuilds of the same plan grow nothing.
--------------------------------------------------------------------------------
do
  local out = {}
  local h = handle()
  L.Build(M.STRINGS["5:5:1:1 3w"], h, M, out)
  local segs, calls, marks = #out.segs, #out.callouts, #out.marks
  local segT, callT, gapT, clipT = out.segs[1], out.callouts[1], out.gap, out.clip
  for _ = 1, 100 do L.Build(M.STRINGS["5:5:1:1 3w"], h, M, out) end
  ok(#out.segs == segs, "seg pool does not grow over 100 rebuilds")
  ok(#out.callouts == calls, "callout pool does not grow over 100 rebuilds")
  ok(#out.marks == marks, "mark list does not grow")
  ok(out.segs[1] == segT and out.callouts[1] == callT, "pooled tables are written in place")
  ok(out.gap == gapT and out.clip == clipT, "gap and clip tables are reused")
  ok(out.nSegs == segs and out.nCallouts == calls, "counts are stable")

  -- A plan change shrinks the live counts but never the pool, and the tail is
  -- blanked so a stale weave band cannot be drawn by a view walking #segs.
  L.Build(M.STRINGS["1:1"], h, M, out)
  ok(#out.segs == segs, "pool survives a shorter plan")
  ok(out.nSegs < segs, "the live count shrinks")
  ok(out.segs[segs].lane == nil, "the tail is blanked")
  ok(out.gap == nil, "the gap is dropped for a turret")

  -- ...and back again reuses the same tables.
  L.Build(M.STRINGS["5:5:1:1 3w"], h, M, out)
  ok(out.gap == gapT, "the gap table comes back rather than being re-made")
  ok(out.nSegs == segs, "the weaving plan fills the pool again")
end

--------------------------------------------------------------------------------
-- 5. Haste moves every number together (Rapid Fire: 1.38 x 1.4).
--------------------------------------------------------------------------------
do
  local h = handle()
  h.rangedMul = 1.38 * 1.4
  local out = L.Build(M.STRINGS["5:5:1:1 3w"], h, M)
  ok(near(out.cycle, 3.0 / h.rangedMul), "cycle follows haste")
  ok(near(out.windup, 0.5 / h.rangedMul), "the wind-up is haste-scaled, not a fixed 0.5 s")
  ok(near(out.steadyCast, 1.5 / h.rangedMul), "the cast is haste-scaled")
  ok(near(out.deadline, out.cycle - out.windup - out.steadyCast), "deadline holds under haste")
  ok(out.deadline > 0, "a Steady still fits at RF haste")

  -- castCorr scales the cast but never the wind-up (PracticeModel's own rule),
  -- so it moves the deadline.
  local h2 = handle()
  h2.castCorr = 1.05
  local o2 = L.Build(M.STRINGS["1:1"], h2, M)
  ok(near(o2.steadyCast, 1.05 * 1.5 / 1.38), "castCorr lengthens the cast")
  ok(near(o2.windup, 0.5 / 1.38), "castCorr leaves the wind-up alone")
  ok(o2.deadline < 0.7246, "a longer cast eats the slack")
end

--------------------------------------------------------------------------------
-- 6. Degenerate input never throws and never leaves half a plan behind.
--------------------------------------------------------------------------------
do
  local out = L.Build(M.STRINGS["5:5:1:1 3w"], handle(), M)
  L.Build(nil, handle(), M, out)
  ok(out.cycle == nil and out.gap == nil and out.nSegs == 0, "no string -> a blank plan")
  ok(out.nCallouts == 0 and out.nSteps == 0, "and no narration")
  ok(out.segs[1].lane == nil, "the pool is blanked, not left stale")
end

print(("practice_lesson: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
