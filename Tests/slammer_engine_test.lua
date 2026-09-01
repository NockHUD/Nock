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
-- 1. Defaults: the observed numbers and the Slammer's own
--------------------------------------------------------------------------------
-- 20 s after each Sleep is the observed timing (videos + logs, 2026-09-01);
-- 16 s from engage stays; the aura (50986) is 6 s with a self-damage tick
-- every 3 s, so 2 s is the margin the user asked for. Sleep is INSTANT —
-- there is no cast-time knob any more.
ok(near(E.DEFAULT.window, 20),     "window after a cast is 20 s")
ok(near(E.DEFAULT.firstWindow, 16), "window after engage is 16 s")
ok(near(E.DEFAULT.leeway, 1),      "the prompt opens 1 s early (leeway)")
ok(near(E.DEFAULT.margin, 2),      "cover margin is 2 s")
ok(near(E.DEFAULT.buffDur, 6),     "the Slammer buff lasts 6 s")
ok(near(E.DEFAULT.sleepDur, 10),   "Sleep lasts 10 s")
ok(E.DEFAULT.castTime == nil and E.DEFAULT.castGrace == nil,
   "Sleep is instant: no cast-time knobs")

local st = E.New()
ok(near(st.cfg.window, 20) and st.count == 0, "New() takes the defaults")
st = E.New({ window = 19.5, margin = 3 })
ok(near(st.cfg.window, 19.5) and near(st.cfg.margin, 3) and near(st.cfg.firstWindow, 16),
   "a partial config keeps the defaults it does not name")
E.Configure(st, { window = 12 })
ok(near(st.cfg.window, 12) and near(st.cfg.margin, 3),
   "Configure changes one knob without touching the others")
E.Configure(st, { leeway = 0 })
E.Engage(st, 200)
ok(near(st.windowAt, 216), "leeway 0: the prompt opens exactly at the window")

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
ok(d.state == "wait" and d.label == E.LABEL.wait and near(d.value, 11),
   "wait counts down to the prompt (16 s from engage minus the 1 s leeway)")
ok(near(d.remaining, 11), "remaining mirrors the countdown")

ok(E.State(st, 114.9) == "wait", "still waiting a hair before the prompt")
ok(E.State(st, 115) == "now", "the prompt opens at engage + 16 - leeway")
d = describe(st, 120)
ok(d.label == E.LABEL.now and d.value == nil, "in the window: CLICK NOW (the WA's own prompt), no number")
ok(E.LABEL.now == "CLICK NOW", "the window is THE prompt: Sleep is instant, there is no cast bar to react to")
ok(E.State(st, 150) == "now", "the window stays open however long the boss waits")

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
ok(near(st.windowAt, 37), "the cast restarts the window: 20 s minus the 1 s leeway")
E.SetBuff(st, nil)
ok(E.State(st, 22.5) == "wait", "after the buff: waiting on the next window")

-- Exposed: buff under the margin.
E.SetBuff(st, 39.5)        -- 1.5 s left at the cast
v = E.CastSucceeded(st, 38)
ok(v == "exposed", "cast with 1.5 s of buff left (margin 2): exposed")
d = describe(st, 38)
ok(d.alert == true and d.state == "exposed" and d.label == E.LABEL.exposed, "exposed flashes and sounds")
ok(E.State(st, 39.9) == "exposed", "the flash holds 2 s")
ok(E.State(st, 40.1) == "wait", "then the countdown is back")
d = describe(st, 40.1)
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
ok(d.label == E.LABEL.noStock and near(d.value, 10), "no stock: NO SLAMMER over the countdown")
d = describe(st, 20)
ok(d.state == "now" and d.label == E.LABEL.noStock, "no stock in the window: NO SLAMMER, not CLICK NOW")
E.SetCount(st, 1)
ok(describe(st, 20).label == E.LABEL.now, "one in the bag: CLICK NOW")
E.CastSucceeded(st, 25)
E.Slept(st, 25)
E.SetCount(st, 0)
ok(describe(st, 26).label == E.LABEL.slept, "slept reads SLEPT whatever the stock")

--------------------------------------------------------------------------------
-- 6b. Sleep is instant: the cast machinery is gone
--------------------------------------------------------------------------------
-- Videos + logs (2026-09-01): there is NO cast timer. The window is the only
-- prompt; every Sleep arrives as a bare SPELL_CAST_SUCCESS.
ok(E.CastStart == nil, "no CastStart — Sleep never has a cast bar")
ok(E.LABEL.casting == nil, "no casting label")
st = E.New()
E.Engage(st, 0)
d = describe(st, 20)
ok(d.castFrac == nil and d.castLeft == nil, "Describe never fills a cast bar")

--------------------------------------------------------------------------------
-- 6b2. The wait bar: the 20 s timer, visible while the window is closed
--------------------------------------------------------------------------------
st = E.New()
E.SetCount(st, 2)
E.Engage(st, 0)
d = describe(st, 4)
ok(near(d.waitFrac, 4 / 15), "waiting after engage: the bar fills over the first wait (16 s - leeway)")
d = describe(st, 20)
ok(d.waitFrac == nil, "window open: no wait bar")
E.CastSucceeded(st, 100)
d = describe(st, 110)
ok(d.state == "wait" and near(d.waitFrac, 10 / 19), "after a Sleep: the bar fills over the wait (20 s - leeway)")
-- The timer starts at the CAST, so the bar runs through slept / the flash /
-- covered too — the state on the face never hides the clock underneath
-- (user, 2026-09-01: the new bar must reappear the moment a cast lands).
d = describe(st, 100.5)
ok(d.state == "exposed" and near(d.waitFrac, 0.5 / 19), "the exposed flash still shows the fresh bar")
E.Slept(st, 112)
d = describe(st, 113)
ok(d.state == "slept" and near(d.waitFrac, 13 / 19), "slept: the bar keeps filling underneath")
E.Woke(st)
E.SetBuff(st, 119)
ok(describe(st, 114).waitFrac ~= nil, "an early drink during the wait leaves the bar up (wait outranks the buff)")
E.Reset(st)
ok(describe(st, 130).waitFrac == nil, "idle: no wait bar")

--------------------------------------------------------------------------------
-- 6c. The horn: every exposed landing owes it (the only moment there is)
--------------------------------------------------------------------------------
st = E.New()
E.SetCount(st, 3)
E.Engage(st, 0)
E.SetBuff(st, nil)
E.CastSucceeded(st, 20)
ok(E.TakeAlert(st) == true, "exposed landing: the horn is owed")
ok(E.TakeAlert(st) == false, "and taken once")
E.SetBuff(st, 48)
E.CastSucceeded(st, 42)
ok(E.TakeAlert(st) == false, "covered landing: quiet")

--------------------------------------------------------------------------------
-- 6d. The window-open chime: once per window
--------------------------------------------------------------------------------
st = E.New()
E.SetCount(st, 3)
E.Engage(st, 0)
ok(E.TakeWindowAlert(st, 10) == false, "no chime while waiting")
ok(E.TakeWindowAlert(st, 14.9) == false, "not before the prompt either")
ok(E.TakeWindowAlert(st, 15) == true, "the chime when the prompt opens (16 s - leeway)")
ok(E.TakeWindowAlert(st, 17) == false, "once")
E.SetBuff(st, 23)
E.SetBuff(st, nil)
ok(E.TakeWindowAlert(st, 24) == false, "the re-drink prompt inside the window is silent")
E.CastSucceeded(st, 30)
ok(E.TakeWindowAlert(st, 45) == false, "the next window is not open yet")
ok(E.TakeWindowAlert(st, 49) == true, "and chimes when it is (20 s - leeway after the cast)")
E.CastSucceeded(st, 55)
E.Slept(st, 55, 80)
ok(E.TakeWindowAlert(st, 75) == false, "a window opening while you are asleep is silent")
ok(E.TakeWindowAlert(st, 81) == false, "and does not chime late either")

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
ok(near(st.windowAt, 125), "a second engage (a new pull) restarts the first window (16 s - leeway)")
ok(E.Active(st) == true, "Active while a window is scheduled")
E.Reset(st)
ok(E.Active(st) == false, "not after a reset")

-- Describe never allocates: the same table comes back.
local t1 = {}
ok(E.Describe(st, 0, t1) == t1, "Describe fills and returns the caller's table")

print(("slammer_engine_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
