-- Tests/practice_ladder_test.lua
-- Standalone LuaJIT tests for Modules/PracticeLadder.lua: the eleven pass
-- conditions against score fixtures, the two-track section layout, the progress
-- transitions, the migration off the old six-rung ladder, the row shapes and
-- their reuse, the fault-code map, and that every drill's spec resolves to
-- something the catalog/DSL can actually load.
-- Run from the repo root: luajit Tests/practice_ladder_test.lua

local Ladder = dofile("Modules/PracticeLadder.lua")
local E = dofile("Modules/PracticeEngine.lua")
local M = dofile("Core/PracticeModel.lua")
-- The fault codes an analysis row can carry, so the drill map can be checked
-- against the only keys that will ever be looked up in it.
local ADVICE = dofile("Modules/PracticeGrader.lua").ADVICE

-- Real notations, from the real bracket tables: Rotations/Profiles.lua only
-- needs a stub addon and LibStub to load.
local Profiles
do
  local NockStub = {}
  _G.LibStub = function() return { GetAddon = function() return NockStub end } end
  dofile("Rotations/Profiles.lua")
  Profiles = NockStub.Profiles
end

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- A finished scorecard, in the shape G.Finish returns. Only the fields the
-- ladder reads are filled; everything else is deliberately absent, which is
-- also the "partial scorecard" case.
local function score(t)
  t = t or {}
  local windows = {}
  for i = 1, (t.windows or 0) do windows[i] = { notation = "5:5:1:1" } end
  return {
    clips = t.clips or 0,
    cyclesOnPaper = { ok = t.ok or 0, total = t.total or 0 },
    weavesTaken = t.taken or 0, weavesMissed = t.missed or 0,
    windows = windows,
    opener = { ok = t.openerOk or false },
  }
end

local function passes(id, s) return Ladder.ById(id).pass.fn(s) and true or false end

local ORDER = "beat,multi,arcane,french,weave-beat,weave-out,weave-shot,weave-full,rhythm,opener"
local TURRET_RUNGS = { "beat", "multi", "arcane", "french" }
local WEAVE_RUNGS  = { "weave-beat", "weave-out", "weave-shot", "weave-full" }

--------------------------------------------------------------------------------
-- 1. The ladder itself: ten rungs on three tracks.
--------------------------------------------------------------------------------
do
  ok(#Ladder.DRILLS == 10, "ten drills")
  local ids = {}
  for i = 1, #Ladder.DRILLS do ids[i] = Ladder.DRILLS[i].id end
  ok(table.concat(ids, ",") == ORDER, "ladder order (" .. table.concat(ids, ",") .. ")")
  ok(Ladder.FIRST == "beat", "the ladder starts at beat")

  -- The sections are contiguous and in the declared order: the lesson panel
  -- draws one header per run of rows, so a track that came apart would draw
  -- its header twice.
  local seen, seq = {}, {}
  local last = nil
  for i = 1, #Ladder.DRILLS do
    local s = Ladder.DRILLS[i].section
    ok(type(s) == "string" and #s > 0, ids[i] .. " names a section")
    if s ~= last then
      ok(not seen[s], "section " .. tostring(s) .. " is contiguous")
      seen[s] = true
      seq[#seq + 1] = s
      last = s
    end
  end
  ok(table.concat(seq, ",") == "TURRET,WEAVE,MASTERY", "three tracks in order")
  ok(table.concat(Ladder.SECTIONS, ",") == "TURRET,WEAVE,MASTERY", "SECTIONS lists them")

  for i = 1, #Ladder.DRILLS do
    local d = Ladder.DRILLS[i]
    ok(type(d.name) == "string" and #d.name > 0, d.id .. " has a name")
    ok(type(d.sub) == "string" and #d.sub > 0, d.id .. " has a sub")
    ok(type(d.pass.text) == "string" and #d.pass.text > 0, d.id .. " has pass text")
    ok(type(d.pass.fn) == "function" and type(d.build) == "function", d.id .. " has fn + build")
    ok(not d.pass.fn(nil), d.id .. " never passes on a nil scorecard")
    ok(Ladder.ById(d.id) == d, d.id .. " resolves by id")
  end
  ok(Ladder.ById("nope") == nil and Ladder.ById(nil) == nil, "an unknown id resolves to nil")
end

--------------------------------------------------------------------------------
-- 2. beat: 0 clips AND >= 90 % cycles on paper over >= 16.
--------------------------------------------------------------------------------
do
  ok(passes("beat", score{ clips = 0, ok = 16, total = 16 }), "beat: clean over 16 cycles")
  ok(not passes("beat", score{ clips = 1, ok = 16, total = 16 }), "beat: one clip fails")
  ok(not passes("beat", score{ clips = 0, ok = 15, total = 15 }), "beat: 15 cycles is short")
  ok(not passes("beat", score{ clips = 0, ok = 12, total = 16 }),
     "beat: clean but 75 % on paper fails -- the beat is a paper rung too")
  ok(passes("beat", score{ clips = 0, ok = 18, total = 20 }), "beat: 18/20 is exactly 90 %")
  ok(not passes("beat", score{ clips = 0, total = 0 }), "beat: no cycles never passes")
end

--------------------------------------------------------------------------------
-- 3. The turret rungs: >= 90 % cycles on paper over >= 16. Same condition on
--    all four, which is the point -- the paper changes, the standard does not.
--------------------------------------------------------------------------------
do
  for _, id in ipairs(TURRET_RUNGS) do
    if id ~= "beat" then
      ok(passes(id, score{ ok = 18, total = 20 }), id .. ": 18/20 is exactly 90 %")
      ok(not passes(id, score{ ok = 17, total = 20 }), id .. ": 17/20 is 85 %")
      ok(not passes(id, score{ ok = 15, total = 15 }), id .. ": perfect but 15 cycles")
      ok(passes(id, score{ ok = 27, total = 30 }), id .. ": 27/30 over a longer fight")
      ok(not passes(id, score{ total = 0 }), id .. ": no cycles is 0 %, not 100 %")
      -- A clip is not fatal above the first rung: a 90 % paper with one clip
      -- in it is a pass, because the rung is about the extra button.
      ok(passes(id, score{ ok = 18, total = 20, clips = 2 }), id .. ": clips do not fail it")
    end
    ok(Ladder.ById(id).section == "TURRET", id .. " is on the turret track")
  end
end

--------------------------------------------------------------------------------
-- 4. The weave rungs: weaves hit >= 4/5 of the windows AND >= 85 % cycles over
--    >= 8 (a weave cycle is pinned twice as long as a turret one).
--------------------------------------------------------------------------------
do
  for _, id in ipairs(WEAVE_RUNGS) do
    ok(passes(id, score{ taken = 4, missed = 1, ok = 17, total = 20 }),
       id .. ": 4/5 windows and 85 % cycles")
    ok(not passes(id, score{ taken = 3, missed = 2, ok = 20, total = 20 }),
       id .. ": 3/5 windows fails whatever the cycles say")
    ok(not passes(id, score{ taken = 5, missed = 0, ok = 16, total = 20 }),
       id .. ": every window taken but 80 % cycles fails")
    ok(not passes(id, score{ taken = 0, missed = 0, ok = 20, total = 20 }),
       id .. ": a fight with no weave window at all never passes")
    ok(passes(id, score{ taken = 8, missed = 2, ok = 8, total = 8 }),
       id .. ": 8/10 windows is exactly 4/5, over the 8-cycle floor")
    ok(not passes(id, score{ taken = 8, missed = 2, ok = 7, total = 7 }),
       id .. ": 7 cycles is short")
    -- The WINDOW count is its own floor. A short low-density fight that opens
    -- two windows and takes both reads 5/5 on a ratio that proves nothing.
    ok(not passes(id, score{ taken = 2, missed = 0, ok = 20, total = 20 }),
       id .. ": 2/2 windows is not evidence -- five is the floor")
    ok(not passes(id, score{ taken = 4, missed = 0, ok = 20, total = 20 }),
       id .. ": 4/4 windows is still one short of the floor")
    ok(passes(id, score{ taken = 4, missed = 1, ok = 20, total = 20 }),
       id .. ": five windows with one missed is the tightest pass there is")
    ok(Ladder.ById(id).section == "WEAVE", id .. " is on the weave track")
  end
end

--------------------------------------------------------------------------------
-- 5. rhythm: >= 85 % cycles with >= 2 haste windows.
--------------------------------------------------------------------------------
do
  ok(passes("rhythm", score{ ok = 17, total = 20, windows = 2 }), "rhythm: 85 % over two windows")
  ok(not passes("rhythm", score{ ok = 20, total = 20, windows = 1 }),
     "rhythm: one haste window is not a rhythm change")
  ok(not passes("rhythm", score{ ok = 16, total = 20, windows = 3 }), "rhythm: 80 % fails")
  ok(passes("rhythm", score{ ok = 9, total = 10, windows = 4 }), "rhythm: short but clean")
  ok(not passes("rhythm", score{ total = 0, windows = 3 }), "rhythm: no cycles never passes")
end

--------------------------------------------------------------------------------
-- 6. opener: G.Finish's own verdict. free: never.
--------------------------------------------------------------------------------
do
  ok(passes("opener", score{ openerOk = true }), "opener: opener.ok")
  ok(not passes("opener", score{ openerOk = false }), "opener: not ok")
  ok(not passes("opener", { clips = 0 }), "opener: a scorecard with no opener block")

  ok(Ladder.ById("free") == nil and #Ladder.DRILLS == 10 and Ladder.LAST == "opener",
     "free play is not a rung (user, 2026-08-27): ten rungs, the opener is the last")
  for _, id in ipairs({ "rhythm", "opener" }) do
    ok(Ladder.ById(id).section == "MASTERY", id .. " is on the mastery track")
  end
end

--------------------------------------------------------------------------------
-- 7. Evaluate: marks done, advances current, never walks backwards -- across
--    all ten rungs.
--------------------------------------------------------------------------------
do
  local st = { done = {}, current = "beat", v = Ladder.VERSION }
  ok(not Ladder.Evaluate(st, score{ clips = 2, ok = 20, total = 20 }, "beat"), "a failed attempt is not a pass")
  ok(st.current == "beat" and not st.done.beat, "...and the ladder does not move")

  local clean = score{ clips = 0, ok = 20, total = 20 }
  ok(Ladder.Evaluate(st, clean, "beat"), "beat passes")
  ok(st.done.beat == true, "beat is marked done")
  ok(st.current == "multi", "current advances to multi")

  -- Passing beat again is not a NEW pass, and must not push the ladder on.
  ok(not Ladder.Evaluate(st, clean, "beat"), "a re-run of a done drill is not a new pass")
  ok(st.current == "multi", "and the ladder stays where it was")

  -- A drill the player jumped ahead to is marked, but the ladder still points
  -- at the first thing they have not done.
  ok(Ladder.Evaluate(st, score{ openerOk = true }, "opener"), "opener passes out of order")
  ok(st.done.opener == true and st.current == "multi", "out-of-order pass does not skip multi")

  -- Walk the whole ladder in order and check every hand-off.
  local st2 = { done = {}, current = "beat", v = Ladder.VERSION }
  local turret = score{ clips = 0, ok = 20, total = 20 }
  local weave = score{ taken = 9, missed = 1, ok = 19, total = 20 }
  local expect = { "multi", "arcane", "french", "weave-beat", "weave-out", "weave-shot",
                   "weave-full", "rhythm", "opener", "opener" }
  for i = 1, #expect do
    local from = st2.current
    local s = turret
    if from:sub(1, 5) == "weave" then s = weave
    elseif from == "rhythm" then s = score{ ok = 19, total = 20, windows = 3 }
    elseif from == "opener" then s = score{ openerOk = true } end
    ok(Ladder.Evaluate(st2, s, from), from .. " passes")
    ok(st2.current == expect[i], from .. " hands off to " .. expect[i]
       .. " (got " .. tostring(st2.current) .. ")")
  end

  -- No id: the current drill is the one under test.
  local st3 = { done = {}, current = "beat", v = Ladder.VERSION }
  ok(Ladder.Evaluate(st3, score{ clips = 0, ok = 22, total = 22 }), "Evaluate defaults to the current drill")
  ok(st3.current == "multi", "and advances it")

  -- Every rung passed: nothing is left to do and the ladder rests on the last.
  ok(Ladder.NextTodo(st2) == nil and st2.current == "opener" and st2.done.opener == true,
     "every rung passed: nothing left, the ladder rests on the last rung")
  -- A v2 state that stood on `free` (or had it done) migrates without the v2
  -- fan-out running again on a new-meaning `multi`.
  local st5 = { done = { multi = true, free = true }, current = "free", v = 2 }
  Ladder.Migrate(st5)
  ok(st5.v == Ladder.VERSION and st5.done.free == nil and st5.done.arcane == nil and st5.current == "beat",
     "v2 -> v3: free dropped, the fan-out not re-run, current moves to the first rung left")
  local st6 = { done = {}, current = "free", v = 2 }
  for i = 1, #Ladder.DRILLS do st6.done[Ladder.DRILLS[i].id] = true end
  Ladder.Migrate(st6)
  ok(st6.current == "opener", "v2 -> v3: with everything done the ladder rests on the last rung")

  -- A missing/blank state is filled in rather than thrown on.
  local st4 = {}
  ok(not Ladder.Evaluate(st4, score{}), "a blank state does not throw")
  ok(st4.current == "beat" and type(st4.done) == "table", "...it is seeded instead")
  ok(Ladder.Evaluate(nil, score{}) == false, "no state at all is a no-op")
end

--------------------------------------------------------------------------------
-- 8. Reset.
--------------------------------------------------------------------------------
do
  local done = { beat = true, multi = true }
  local st = { done = done, current = "arcane", loaded = "arcane", v = Ladder.VERSION }
  Ladder.Reset(st)
  ok(st.current == "beat", "reset points at the first drill")
  ok(st.loaded == nil, "reset lets go of the loaded drill too")
  ok(next(st.done) == nil, "reset clears every mark")
  ok(st.done == done, "and keeps the profile's own table")
  ok(st.v == Ladder.VERSION, "a wiped ladder is stamped current, not left to be re-migrated")
end

--------------------------------------------------------------------------------
-- 9. Migration off the six-rung ladder. Old ids: beat, multi, weave, rhythm,
--    opener, free -- and `multi` MEANT the full turret notation, which is now
--    `french`, while a rung called `multi` still exists and means something
--    easier. That collision is what the version stamp exists for.
--------------------------------------------------------------------------------
do
  -- Someone who had passed the old beat + multi has, by construction, passed
  -- the two teaching rungs under the full turret as well.
  local st = { done = { beat = true, multi = true }, current = "weave", loaded = "weave" }
  Ladder.Migrate(st)
  ok(st.done.beat and st.done.multi and st.done.arcane and st.done.french,
     "old multi fans out over the turret track")
  ok(st.current == "weave-beat", "current lands on the first weave rung (" .. tostring(st.current) .. ")")
  ok(st.loaded == nil, "a loaded id no rung answers to is let go of")
  ok(st.v == Ladder.VERSION, "the state is stamped")

  -- ...and the old weave rung fans out over the whole weave track.
  local st2 = { done = { beat = true, multi = true, weave = true }, current = "rhythm" }
  Ladder.Migrate(st2)
  for _, id in ipairs(WEAVE_RUNGS) do ok(st2.done[id] == true, "old weave -> " .. id) end
  ok(st2.done.weave == nil, "the retired id is dropped, not kept as a passenger")
  ok(st2.current == "rhythm", "a current that still names a rung is left alone")

  -- The collision the stamp protects against: a NEW multi pass must not hand
  -- out arcane and french on the next login.
  local st3 = { done = { beat = true, multi = true }, current = "arcane", v = Ladder.VERSION }
  Ladder.Migrate(st3)
  ok(st3.done.arcane == nil and st3.done.french == nil,
     "a state already on the current schema is never re-migrated")
  ok(st3.current == "arcane", "...and keeps its rung")

  -- Migration runs exactly once even on old data: the second call is a no-op.
  local st4 = { done = { multi = true } }
  Ladder.Migrate(st4)
  st4.done.arcane, st4.done.french = nil, nil
  Ladder.Migrate(st4)
  ok(st4.done.arcane == nil, "the stamp survives, so the fan-out does not repeat")

  -- Junk of every shape, and none of it throws.
  ok(Ladder.Migrate(nil) == nil, "no state migrates to nothing")
  local st5 = {}
  Ladder.Migrate(st5)
  ok(type(st5.done) == "table" and st5.current == "beat", "a bare table is seeded")
  local st6 = { done = { ["a rung that never was"] = true }, current = "nonsense", loaded = "junk" }
  Ladder.Migrate(st6)
  ok(next(st6.done) == nil and st6.current == "beat" and st6.loaded == nil,
     "unknown ids are swept and the ladder points at the first rung")
  -- A fresh profile (Config/Defaults.lua's own shape) survives it untouched.
  local st7 = { done = {}, current = "beat" }
  Ladder.Migrate(st7)
  ok(st7.current == "beat" and next(st7.done) == nil and st7.v == Ladder.VERSION,
     "a fresh profile migrates to itself")
end

--------------------------------------------------------------------------------
-- 10. Items: shape, section headers, state and reuse.
--------------------------------------------------------------------------------
do
  local st = { done = { beat = true }, current = "multi", v = Ladder.VERSION }
  local items = Ladder.Items(st)
  ok(#items == 10, "ten rows")
  ok(items[1].state == "done" and items[2].state == "cur" and items[3].state == "todo",
     "done / cur / todo")
  ok(items[1].id == "beat" and items[10].id == "opener", "rows carry their id")
  ok(items[2].pass == Ladder.ById("multi").pass.text,
     "the row's pass column is the pass TEXT, not the function")

  -- The section marker sits on the FIRST row of each track and nowhere else,
  -- so a dumb view can draw a header wherever it finds one.
  local heads = {}
  for i = 1, #items do
    if items[i].section then heads[#heads + 1] = i .. ":" .. items[i].section end
  end
  ok(table.concat(heads, " ") == "1:TURRET 5:WEAVE 9:MASTERY",
     "one section marker per track, on its first row (" .. table.concat(heads, " ") .. ")")

  for i = 1, 10 do
    ok(type(items[i].name) == "string" and type(items[i].sub) == "string"
       and type(items[i].pass) == "string" and type(items[i].state) == "string",
       "row " .. i .. " is all strings")
  end

  -- The reuse contract: one array, ten rows, no garbage per repaint.
  local row1 = items[1]
  local again = Ladder.Items(st)
  ok(again == items, "the array is reused")
  ok(again[1] == row1, "and so are the rows")

  st.done.multi, st.current = true, "arcane"
  Ladder.Items(st)
  ok(items[2].state == "done" and items[3].state == "cur", "the same rows are repainted in place")
  -- ...and a repaint does not leave a stale section marker on a middle row.
  local heads2 = 0
  for i = 1, #items do if items[i].section then heads2 = heads2 + 1 end end
  ok(heads2 == 3, "still three section markers after a repaint")

  -- An explicit out table is honoured (and the caller's is what comes back).
  local mine = {}
  ok(Ladder.Items(st, mine) == mine and #mine == 10, "Items writes into the caller's table")
end

--------------------------------------------------------------------------------
-- 11. DrillFor: the fault-code map Task 7's fix cards read.
--------------------------------------------------------------------------------
do
  ok(Ladder.DrillFor("CLIP") == "beat" and Ladder.DrillFor("LATE") == "beat", "CLIP/LATE -> beat")
  ok(Ladder.DrillFor("WEAVE_MISSED") == "weave-beat" and Ladder.DrillFor("WEAVE_SLOW") == "weave-beat",
     "WEAVE_* -> weave-beat")
  ok(Ladder.DrillFor("DEAD_ZONE") == "weave-beat", "DEAD_ZONE -> weave-beat")
  ok(Ladder.DrillFor("REARM") == "weave-shot", "REARM -> the rung with a cast beside the weave")
  ok(Ladder.DrillFor("EARLY") == "opener", "the opener's EARLY -> opener")
  -- R5b: the two codes that say "the paper wanted a cast you did not make".
  ok(Ladder.DrillFor("CATCHUP_MISSED") == "multi", "CATCHUP_MISSED -> multi")
  ok(Ladder.DrillFor("STEADY_WONT_FIT") == "arcane", "STEADY_WONT_FIT -> arcane")
  -- OFF and MISSED are per-note JUDGMENT grades, not fault codes: they never
  -- reach an analysis row, so a drill keyed on them was a row nothing read.
  ok(Ladder.DrillFor("OFF") == nil and Ladder.DrillFor("MISSED") == nil,
     "a judgment grade is not a fault code and gets no drill")
  ok(Ladder.DrillFor("GOOD") == nil and Ladder.DrillFor(nil) == nil, "unknown / nil -> nil")
  for code, id in pairs(Ladder.DRILL_FOR) do
    ok(Ladder.ById(id) ~= nil, code .. " maps to a real drill")
    ok(ADVICE[code] ~= nil, code .. " is a real fault code (PracticeGrader.ADVICE)")
  end
end

--------------------------------------------------------------------------------
-- 12. The specs: real notations in, something loadable out.
--------------------------------------------------------------------------------
do
  local ews = 2.174                       -- the P1 BM baseline: 3.0 bow x 1.38
  local ctx = { turret = Profiles:ResolveByEWS(ews),
                weave = Profiles:ResolveWeave(ews, {}, 0) }
  ok(ctx.turret == "5:5:1:1", "the stub profile resolves the French turret")
  ok(ctx.weave == "5:5:1:1 3w", "...and the French weave")

  ok(Ladder.ById("french").build(ctx).scenario == ctx.turret, "french loads the turret notation")
  ok(Ladder.ById("weave-full").build(ctx).scenario == ctx.weave, "weave-full loads the weave notation")
  ok(Ladder.ById("opener").build(ctx).scenario == "Lust + RF + Drums", "opener loads the built-in script")

  -- A faster character gets a faster rotation, without the ladder knowing how.
  local fast = { turret = Profiles:ResolveByEWS(1.1), weave = Profiles:ResolveWeave(1.1, {}, 0) }
  ok(Ladder.ById("french").build(fast).scenario == "5:9:1:1", "french follows the character's bracket")

  -- The six teaching rungs name a paper, and every one of them is a string the
  -- model actually carries WITH a pinned haste -- the glue builds the catalog
  -- row straight off those two facts, so a rung naming a string the model does
  -- not have would silently drop out of the picker.
  local papers = 0
  for i = 1, #Ladder.DRILLS do
    local spec = Ladder.DRILLS[i].build(ctx)
    ok(type(spec) == "table" and type(spec.scenario) == "string" and #spec.scenario > 0,
       Ladder.DRILLS[i].id .. " names a scenario")
    if spec.paper then
      papers = papers + 1
      local nota = spec.paper.notation
      ok(nota == spec.scenario, Ladder.DRILLS[i].id .. ": the paper's notation IS its scenario name")
      ok(M.TEACHING[nota] ~= nil, nota .. " is a teaching string")
      ok(M.STRINGS[nota] ~= nil, nota .. " is reachable through M.STRINGS")
      ok(type(M.TEACHING_EWS[nota]) == "number" and M.TEACHING_EWS[nota] > 0, nota .. " pins an eWS")
      ok(spec.line == nil, Ladder.DRILLS[i].id .. " is a paper, not a script")
    end
    if spec.line then
      local list, errors = E.ParseScenario(spec.line)
      ok(#errors == 0, Ladder.DRILLS[i].id .. "'s line parses with no complaint")
      ok(#list == 1, Ladder.DRILLS[i].id .. "'s line is exactly one scenario")
      ok(list[1].name == spec.scenario, Ladder.DRILLS[i].id .. "'s line names the scenario it loads")
    end
  end
  ok(papers == 6, "six teaching papers on the ladder")
  -- Every teaching string the model ships is claimed by a rung: an orphan would
  -- be a paper nothing can load.
  local claimed = {}
  for i = 1, #Ladder.DRILLS do
    local spec = Ladder.DRILLS[i].build(ctx)
    if spec.paper then claimed[spec.paper.notation] = true end
  end
  for key in pairs(M.TEACHING) do ok(claimed[key], key .. " is loadable from a rung") end

  -- rhythm is the one with a line: Hawk at 5 s, Rapid Fire at 15 s, 45 s long.
  local spec = Ladder.ById("rhythm").build(ctx)
  local sc = E.ParseScenario(spec.line)[1]
  ok(sc.len == 45, "rhythm runs 45 s")
  ok(#sc.events == 2, "rhythm scripts two procs")
  ok(sc.events[1].t == 5 and sc.events[1].proc == "QS", "Hawk (Quick Shots) at 5 s")
  ok(sc.events[2].t == 15 and sc.events[2].proc == "RF", "Rapid Fire at 15 s")
  -- No pin: the haste has to MOVE, which is the whole drill.
  ok(sc.ews == nil and sc.lock == nil, "rhythm pins neither eWS nor notation")
  ok(sc.hold == nil, "and holds nothing up")

  local lines = 0
  for i = 1, #Ladder.DRILLS do
    if Ladder.DRILLS[i].build(ctx).line then lines = lines + 1 end
  end
  ok(lines == 1, "only rhythm needs a scenario of its own")
end

-- R6c: EVERY TEACHING DRILL IS A TIMED ATTEMPT. 60 s on every rung so the
-- review lands while the attempt is still in the fingers; `rhythm` keeps the
-- 45 s its own script schedules two haste windows inside; `free` stays endless,
-- because free play has no attempt to end.
do
  local ctx = { turret = "5:5:1:1", weave = "5:5:1:1 3w" }
  local WANT = {
    beat = 60, multi = 60, arcane = 60, french = 60,
    ["weave-beat"] = 60, ["weave-out"] = 60, ["weave-shot"] = 60, ["weave-full"] = 60,
    rhythm = 45, opener = 60, free = nil,
  }
  local seen = 0
  for i = 1, #Ladder.DRILLS do
    local d = Ladder.DRILLS[i]
    local got = d.build(ctx).len
    ok(got == WANT[d.id], ("%s caps at %s"):format(d.id, tostring(WANT[d.id])) ..
       " (" .. tostring(got) .. ")")
    ok(Ladder.LenFor(d.id, ctx) == got, d.id .. ": LenFor reads the spec's own cap")
    seen = seen + 1
  end
  ok(seen == 10, "every rung was checked (" .. seen .. ")")
  ok(Ladder.LenFor("no such rung", ctx) == nil, "an unknown rung caps nothing")
  ok(Ladder.LenFor("beat") == 60, "LenFor survives a caller with no ladder context")

  -- The cap and the scenario behind it must agree where the scenario states one:
  -- rhythm is the only rung with a len= of its own, and a drill whose cap
  -- disagreed with its own script would end the fight twice over.
  local spec = Ladder.ById("rhythm").build(ctx)
  ok(E.ParseScenario(spec.line)[1].len == spec.len,
     "rhythm's cap is the len= its own line states")

  -- Reachability, at each rung's own pin: 60 s has to leave the pass minimums
  -- comfortably in reach or the cap has quietly made the ladder unpassable.
  -- Cycles per second is the layout's period over its auto count.
  local function cyclesIn(str, ews, secs)
    local lay = M.Layout(str, { ws = 3.0, rangedMul = 3.0 / ews, mws = 3.7, meleeMul = 1.0,
      imprArcanePts = 0, castCorr = 1.0, multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 }, 0)
    local autos, weaves = 0, 0
    for i = 1, #lay.ev do
      local s = lay.ev[i].sym
      if s == "a" then autos = autos + 1 end
      if s == "w" or s == "r" then weaves = weaves + 1 end
    end
    return secs / (lay.dur / autos), secs / lay.dur * weaves
  end
  for _, nota in ipairs({ "drill 1:1", "drill 1:1+m", "drill 1:1+mA" }) do
    local c = cyclesIn(M.STRINGS[nota], M.TEACHING_EWS[nota], 60)
    ok(c >= 16 * 1.5, ("%s: 60 s reaches %.1f cycles, 1.5x the 16-cycle floor"):format(nota, c))
  end
  for _, nota in ipairs({ "drill 1w", "drill 1w+A", "drill 1w+s" }) do
    local c, w = cyclesIn(M.STRINGS[nota], M.TEACHING_EWS[nota], 60)
    ok(c >= 8 * 1.5, ("%s: 60 s reaches %.1f cycles, 1.5x the 8-cycle floor"):format(nota, c))
    ok(w >= 5 * 1.5, ("%s: ...and %.1f weave slots, 1.5x the 5-window floor"):format(nota, w))
  end
  -- The two ctx-driven rungs run the CHARACTER's rotation, so the floor has to
  -- hold at every pin the bracket tables can hand them. LOCK_PIN's two
  -- exceptions live in Modules/Practice.lua; the rest is lo + 0.1.
  local LOCK_PIN = { ["1:1"] = 1.60, ["2:5"] = 0.65 }
  for i = 1, #Profiles.list do
    local row = Profiles.list[i]
    local ews = LOCK_PIN[row.name] or (row.lo + 0.1)
    local c = cyclesIn(M.STRINGS[row.name], ews, 60)
    ok(c >= 16 * 1.5, ("french @ %s (eWS %.2f): %.1f cycles in 60 s"):format(row.name, ews, c))
  end
end

print(("practice_ladder: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
