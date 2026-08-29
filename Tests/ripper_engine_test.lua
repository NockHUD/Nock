-- Tests/ripper_engine_test.lua
-- Standalone LuaJIT tests for the pure Dimensional Ripper / Ultrasafe
-- Transporter countdown engine: the deadline is the cast's end minus the lead,
-- the numerals count whole seconds to it (9 .. 1), and from the deadline on it
-- reads ALT F4 -- not a second early: the user's first real try failed on that.
-- Run from the repo root: luajit Tests/ripper_engine_test.lua

local E = dofile("Modules/RipperEngine.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 1e-6) end

--------------------------------------------------------------------------------
-- 1. Defaults
--------------------------------------------------------------------------------
ok(near(E.DEFAULT.lead, 1.0), "the default lead is 1 s before the cast ends")
ok(E.LABEL.go == "ALT F4",     "the go label is ALT F4")

--------------------------------------------------------------------------------
-- 2. Begin: a 10 s cast at t=100 has its deadline at 109 (lead 1)
--------------------------------------------------------------------------------
local st = E.New()
ok(E.Active(st) == false, "a fresh engine is idle")
E.Begin(st, 100, 110, 1.0)
ok(E.Active(st) == true,         "Begin arms the countdown")
ok(near(st.deadline, 109),       "deadline = end - lead")
ok(near(st.startTime, 100) and near(st.endTime, 110), "the cast's span is kept")

--------------------------------------------------------------------------------
-- 3. Describe: whole seconds to the deadline down to 1, ALT F4 from the
--    deadline on, still ALT F4 past it while the cast runs.
--------------------------------------------------------------------------------
local out = {}
local function d(now) E.Describe(st, now, out); return out end

ok(d(100).label == "9" and d(100).go == false,  "at the cast's start: 9")
ok(d(100.5).label == "9",                       "half a second in: still 9 (ceil)")
ok(d(101).label == "8",                         "one second in: 8")
ok(d(106.2).label == "3",                       "2.8 s to go: 3")
ok(d(107).label == "2",                         "2 s to go: 2")
ok(d(107.9).label == "2",                       "1.1 s to go: 2")
ok(d(108).label == "1" and d(108).go == false,  "1 s to go: 1 -- not ALT F4 yet")
ok(d(108.7).label == "1",                       "the last second: still 1")
ok(d(109).label == "ALT F4" and d(109).go == true, "on the deadline: ALT F4")
ok(d(109.2).label == "ALT F4",                  "just past it: ALT F4")
ok(d(109.9).label == "ALT F4",                  "past the deadline, cast still up: ALT F4")
ok(near(d(105).remaining, 4),                   "remaining is the time to the deadline")
ok(near(d(109.5).remaining, 0),                 "remaining floors at 0")
ok(near(d(105).frac, 0.5),                      "frac is progress through the cast (5 of 10 s)")

--------------------------------------------------------------------------------
-- 4. The go edge fires once: TakeGo hands the flip out one time
--------------------------------------------------------------------------------
st = E.New()
E.Begin(st, 100, 110, 1.0)
d(108.5)
ok(E.TakeGo(st) == false,  "no go before the deadline")
d(109.05)
ok(E.TakeGo(st) == true,   "the flip is handed out once")
d(109.5)
ok(E.TakeGo(st) == false,  "and not again")

--------------------------------------------------------------------------------
-- 5. End clears; a lead longer than the cast still starts at ALT F4 rather
--    than a negative count; Describe on an idle engine says nothing.
--------------------------------------------------------------------------------
E.End(st)
ok(E.Active(st) == false, "End disarms")
ok(d(100).label == nil,   "an idle engine has no label")

st = E.New()
E.Begin(st, 100, 101.5, 3)
ok(near(st.deadline, 100), "a lead past the start clamps the deadline to the start")
ok(d(100).label == "ALT F4", "and the countdown opens on ALT F4")

st = E.New()
E.Begin(st, 100, 110, 2.5)
ok(near(st.deadline, 107.5) and d(100).label == "8" and d(106.4).label == "2" and d(106.6).label == "1"
   and d(107.5).label == "ALT F4", "a 2.5 s lead: 8 at the start, 1 at 106.5, ALT F4 from 107.5")

--------------------------------------------------------------------------------
-- 6. A cast delayed (pushback) moves the deadline with it
--------------------------------------------------------------------------------
st = E.New()
E.Begin(st, 100, 110, 1)
E.Retime(st, 100, 111)
ok(near(st.deadline, 110) and d(108).label == "2" and d(109.5).label == "1" and d(110).label == "ALT F4",
   "Retime moves the deadline and the count")

print(string.format("ripper_engine_test: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
