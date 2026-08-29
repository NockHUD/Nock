-- Tests/slammer_engine_test.lua
-- Standalone LuaJIT tests for the pure Sulfuron Slammer engine: when the
-- window opens, what the button says in each state, and the on-cast coverage
-- verdict that is the only thing allowed to sound the horn.
-- Run from the repo root: luajit Tests/slammer_engine_test.lua

local E = dofile("Modules/SlammerEngine.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 1e-6) end

local out = {}
local function describe(st, now)
  E.Describe(st, now, out)
  return out
end

--------------------------------------------------------------------------------
-- 1. Defaults: the WA's numbers and the Slammer's own
--------------------------------------------------------------------------------
-- 16 s from engage / 16.5 s after each Sleep is the reference WA's timing
-- (BigWigs times the cast 19.5-45 s apart); the aura (50986) is 6 s with a
-- self-damage tick every 3 s, so 2 s is the margin the user asked for.
ok(near(E.DEFAULT.window, 16.5),   "window after a cast is 16.5 s")
ok(near(E.DEFAULT.firstWindow, 16), "window after engage is 16 s")
ok(near(E.DEFAULT.margin, 2),      "cover margin is 2 s")
ok(near(E.DEFAULT.buffDur, 6),     "the Slammer buff lasts 6 s")
ok(near(E.DEFAULT.sleepDur, 10),   "Sleep lasts 10 s")

local st = E.New()
ok(near(st.cfg.window, 16.5) and st.count == 0, "New() takes the defaults")
st = E.New({ window = 19.5, margin = 3 })
ok(near(st.cfg.window, 19.5) and near(st.cfg.margin, 3) and near(st.cfg.firstWindow, 16),
   "a partial config keeps the defaults it does not name")
E.Configure(st, { window = 12 })
ok(near(st.cfg.window, 12) and near(st.cfg.margin, 3),
   "Configure changes one knob without touching the others")

--------------------------------------------------------------------------------
-- 2. Idle -> wait -> now, and the labels
--------------------------------------------------------------------------------
st = E.New()
E.SetCount(st, 5)
ok(E.State(st, 100) == "idle", "no engage yet: idle")
local d = describe(st, 100)
ok(d.label == E.LABEL.idle and d.value == nil and d.count == 5, "idle reads SLAMMER with no number")

E.Engage(st, 100)
ok(E.State(st, 100) == "wait", "engage starts the first window")
d = describe(st, 104)
ok(d.state == "wait" and d.label == E.LABEL.wait and near(d.value, 12), "wait counts down to the window (16 s from engage)")
ok(near(d.remaining, 12), "remaining mirrors the countdown")

ok(E.State(st, 115.9) == "wait", "still waiting a hair before the window")
ok(E.State(st, 116) == "now", "the window opens at engage + 16")
d = describe(st, 120)
ok(d.label == E.LABEL.now and d.value == nil, "in the window: CLICK NOW (the WA's own prompt), no number")
ok(E.LABEL.now == "CLICK NOW", "the window is a real prompt: Sleep may have no cast bar (the WA never used one)")
ok(E.State(st, 150) == "now", "the window stays open however long the boss holds the cast")

--------------------------------------------------------------------------------
-- 3. Covered: the buff inside the window, and the re-drink prompt
--------------------------------------------------------------------------------
E.SetBuff(st, 126)          -- drank at 120: 6 s buff
ok(E.State(st, 121) == "covered", "buff up inside the window: covered")
d = describe(st, 121)
ok(d.label == E.LABEL.covered and near(d.value, 5), "covered shows the buff's remaining seconds")
ok(E.State(st, 126) == "now", "the buff runs out with no cast yet: CLICK NOW again")
E.SetBuff(st, nil)
ok(E.State(st, 126.5) == "now", "and cleared explicitly it is the same answer")

-- A buff drunk EARLY does not hide the countdown: the window is the thing to
-- watch, and a 6 s buff drunk at 10 s of wait is gone before it matters.
local early = E.New()
E.Engage(early, 0)
E.SetBuff(early, 8)
ok(E.State(early, 3) == "wait", "a buff during the wait leaves the countdown up")
ok(E.State(early, 16) == "now", "and is gone by the time the window opens")

--------------------------------------------------------------------------------
-- 4. The cast verdict: covered is quiet, exposed sounds
--------------------------------------------------------------------------------
st = E.New()
E.SetCount(st, 5)
E.Engage(st, 0)
-- Covered: buff has plenty left.
E.SetBuff(st, 22)          -- drank at 16, buff to 22
local v = E.CastSucceeded(st, 18)
ok(v == "covered", "cast with 4 s of buff left: covered")
d = describe(st, 18)
ok(d.alert == false, "covered does not sound")
ok(d.state == "castOk" and d.label == E.LABEL.castOk and near(d.value, 4),
   "a covered cast is still announced: SLEEP - COVERED with the buff's seconds")
ok(E.State(st, 20.5) == "covered", "then the button stays covered until the tick wakes you")
ok(near(st.windowAt, 34.5), "the cast restarts the window at 16.5 s")
E.SetBuff(st, nil)
ok(E.State(st, 22.5) == "wait", "after the buff: waiting on the next window")

-- Exposed: buff under the margin.
E.SetBuff(st, 36)          -- 1.5 s left at the cast
v = E.CastSucceeded(st, 34.5)
ok(v == "exposed", "cast with 1.5 s of buff left (margin 2): exposed")
d = describe(st, 34.5)
ok(d.alert == true and d.state == "exposed" and d.label == E.LABEL.exposed, "exposed flashes and sounds")
ok(E.State(st, 36.4) == "exposed", "the flash holds 2 s")
ok(E.State(st, 36.6) == "wait", "then the countdown is back")
d = describe(st, 36.6)
ok(d.alert == false, "the horn is a one-shot: the next describe is quiet")

-- Exposed: no buff at all.
v = E.CastSucceeded(st, 60)
ok(v == "exposed" and describe(st, 60).alert == true, "cast with no buff: exposed, horn")

-- Exactly the margin counts as covered.
E.SetBuff(st, 82)
ok(E.CastSucceeded(st, 80) == "covered", "buff remaining == margin is covered")
ok(st.verdict == "covered", "the verdict is kept for the frame's colour")

--------------------------------------------------------------------------------
-- 5. Slept beats everything, and the wake clears it
--------------------------------------------------------------------------------
st = E.New()
E.Engage(st, 0)
E.CastSucceeded(st, 20)              -- exposed
E.Slept(st, 20)                      -- and it landed on me
ok(E.State(st, 20.5) == "slept", "Sleep on me: slept outranks the exposed flash")
d = describe(st, 22)
ok(d.label == E.LABEL.slept and near(d.value, 8) and d.verdict == "exposed",
   "slept counts the sleep down (10 s) and carries the verdict")
E.Woke(st)
ok(E.State(st, 23) == "wait", "woken: back to the countdown")

-- Covered and slept anyway (the tick is still coming): slept, verdict covered.
E.SetBuff(st, 45)
E.CastSucceeded(st, 40)
E.Slept(st, 40, 50)
d = describe(st, 41)
ok(d.state == "slept" and d.verdict == "covered" and near(d.value, 9),
   "slept while covered says so and takes the aura's own expiry")
ok(E.State(st, 50.1) == "wait", "an unwoken sleep expires on its own")

--------------------------------------------------------------------------------
-- 6. No Slammer in the bag
--------------------------------------------------------------------------------
st = E.New()
E.Engage(st, 0)
d = describe(st, 5)
ok(d.label == E.LABEL.noStock and near(d.value, 11), "no stock: NO SLAMMER over the countdown")
d = describe(st, 20)
ok(d.state == "now" and d.label == E.LABEL.noStock, "no stock in the window: NO SLAMMER, not CLICK NOW")
E.SetCount(st, 1)
ok(describe(st, 20).label == E.LABEL.now, "one in the bag: CLICK NOW")
E.CastSucceeded(st, 25)
E.Slept(st, 25)
E.SetCount(st, 0)
ok(describe(st, 26).label == E.LABEL.slept, "slept reads SLEPT whatever the stock")

--------------------------------------------------------------------------------
-- 6b. A cast bar, if this client gives Sleep one
--------------------------------------------------------------------------------
st = E.New()
E.SetCount(st, 2)
E.Engage(st, 0)
E.CastStart(st, 20, 1.5)
d = describe(st, 20.5)
ok(d.state == "casting" and d.label == E.LABEL.casting and d.value == nil, "cast start: CLICK NOW")
ok(near(d.castFrac, 1/3) and near(d.castLeft, 1), "the border bar reads the cast's own length")
E.SetBuff(st, 27)
d = describe(st, 21)
ok(d.state == "casting" and d.label == E.LABEL.covered and near(d.value, 6),
   "drinking during the cast: still the cast state (the bar runs on), but COVERED")
ok(near(d.castFrac, 2/3), "and the bar keeps going")
E.CastSucceeded(st, 21.5)
ok(E.State(st, 21.6) == "castOk", "the success ends it with the verdict flash")
ok(describe(st, 21.6).castFrac == nil, "no bar outside a cast")
E.CastStart(st, 40)                  -- no duration: the configured 2 s
ok(E.State(st, 42.4) == "casting", "an orphaned cast start holds castTime + castGrace (2.5 s)")
ok(E.State(st, 42.6) == "now", "then falls away (the window from the 21.5 s cast is open by now)")
E.SetCount(st, 0)
E.SetBuff(st, nil)
E.CastStart(st, 50)
ok(describe(st, 50.5).label == E.LABEL.noStock, "a cast with nothing to drink reads NO SLAMMER")

-- Covered is judged at the cast's END: a buff that runs out under the cast
-- is a click, not a green border.
E.SetCount(st, 2)
E.SetBuff(st, 61)                    -- 1 s of buff left at 60
E.CastStart(st, 60, 1.3)             -- lands at 61.3
d = describe(st, 60)
ok(d.state == "casting" and d.label == E.LABEL.casting and d.value == nil,
   "buff up but gone before the cast lands: CLICK NOW, not COVERED")
E.SetBuff(st, 63.3)                  -- exactly the margin past the end
ok(describe(st, 60.2).label == E.LABEL.covered, "buff outlasting the end by the margin: COVERED")
E.SetBuff(st, 63.2)
ok(describe(st, 60.2).label == E.LABEL.casting, "a hair under the margin at the end: still the click")

--------------------------------------------------------------------------------
-- 6c. The horn is at the cast's START when you are not covered for its end
--------------------------------------------------------------------------------
st = E.New()
E.SetCount(st, 3)
E.Engage(st, 0)
ok(E.CastStart(st, 20, 1.5) == "exposed", "no buff at the cast start: exposed")
ok(E.TakeAlert(st) == true, "the horn is owed at the START")
ok(E.TakeAlert(st) == false, "and taken once")
E.CastSucceeded(st, 21.5)            -- still no buff: slept
ok(E.TakeAlert(st) == false, "the landing does not sound again - too late to act on")
ok(E.State(st, 21.6) == "exposed", "the flash still says EXPOSED")

E.SetBuff(st, 50)
ok(E.CastStart(st, 40, 1.5) == "covered", "buff outlasting the end: covered at the start")
ok(E.TakeAlert(st) == false, "no horn")
E.SetBuff(st, 41.6)                  -- lost most of it
E.CastSucceeded(st, 41.5)
ok(E.TakeAlert(st) == false, "a cast judged covered at its start is quiet at the landing too")

-- Drinking during the cast answers the horn: the border goes green, the verdict is covered.
E.SetBuff(st, nil)
E.CastStart(st, 60, 2)
ok(E.TakeAlert(st) == true, "horn at 60")
E.SetBuff(st, 67)                    -- drank at 61
ok(describe(st, 61).label == E.LABEL.covered, "drank in time: COVERED under the bar")
ok(E.CastSucceeded(st, 62) == "covered" and E.TakeAlert(st) == false, "and the landing is quiet")

-- An instant Sleep (no start ever seen) sounds at the landing, the only chance it has.
E.SetBuff(st, nil)
E.CastSucceeded(st, 80)
ok(E.TakeAlert(st) == true, "instant Sleep, exposed: the horn at the landing")
E.SetBuff(st, 90)
E.CastSucceeded(st, 85)
ok(E.TakeAlert(st) == false, "instant Sleep, covered: quiet")

--------------------------------------------------------------------------------
-- 6d. The window-open chime: once per window
--------------------------------------------------------------------------------
st = E.New()
E.SetCount(st, 3)
E.Engage(st, 0)
ok(E.TakeWindowAlert(st, 10) == false, "no chime while waiting")
ok(E.TakeWindowAlert(st, 16) == true, "the chime when the window opens")
ok(E.TakeWindowAlert(st, 17) == false, "once")
E.SetBuff(st, 23)
E.SetBuff(st, nil)
ok(E.TakeWindowAlert(st, 24) == false, "the re-drink prompt inside the window is silent")
E.CastSucceeded(st, 30)
ok(E.TakeWindowAlert(st, 40) == false, "the next window is not open yet")
ok(E.TakeWindowAlert(st, 46.5) == true, "and chimes when it is")
E.CastSucceeded(st, 50)
E.Slept(st, 50, 70)
ok(E.TakeWindowAlert(st, 66.5) == false, "a window opening while you are asleep is silent")
ok(E.TakeWindowAlert(st, 71) == false, "and does not chime late either")

--------------------------------------------------------------------------------
-- 7. Reset and re-engage
--------------------------------------------------------------------------------
st = E.New()
E.SetCount(st, 3)
E.Engage(st, 0)
E.SetBuff(st, 20)
E.CastSucceeded(st, 18)
E.Slept(st, 18)
E.Reset(st)
ok(E.State(st, 19) == "idle" and st.count == 3, "Reset drops the fight, keeps the stock count")
ok(st.verdict == nil and st.windowAt == nil, "and the verdict")
E.Engage(st, 100)
E.Engage(st, 110)
ok(near(st.windowAt, 126), "a second engage (a new pull) restarts the first window")
ok(E.Active(st) == true, "Active while a window is scheduled")
E.Reset(st)
ok(E.Active(st) == false, "not after a reset")

-- Describe never allocates: the same table comes back.
local t1 = {}
ok(E.Describe(st, 0, t1) == t1, "Describe fills and returns the caller's table")

print(("slammer_engine_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
