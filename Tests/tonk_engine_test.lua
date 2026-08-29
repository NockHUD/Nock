-- Tests/tonk_engine_test.lua
-- Standalone LuaJIT tests for the pure Steam Tonk guard decision engine.
-- Run from the repo root: luajit Tests/tonk_engine_test.lua

local E = dofile("Modules/TonkEngine.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-9) end

local DELAY = 0.40

-- 1. Constants are the spec's values. These are load-bearing: 0.1 is how often
--    the sweep looks, 1.0 the grace before a SECOND cancel is allowed, 4.0 the
--    give-up cap. RETRY_AFTER must stay comfortably above the measured exit
--    transition (0.176s in-game on 2026-08-12) or we re-weld the player.
ok(near(E.SWEEP_INTERVAL, 0.1), "SWEEP_INTERVAL is 0.1")
ok(near(E.RETRY_AFTER, 1.0),    "RETRY_AFTER is 1.0")
ok(near(E.GIVE_UP_AFTER, 4.0),  "GIVE_UP_AFTER is 4.0")
ok(E.RETRY_AFTER > 0.176 * 3,   "RETRY_AFTER clears the measured exit transition with margin")
ok(E.GIVE_UP_AFTER > E.RETRY_AFTER, "the cap outlasts at least one retry")

-- 2. No tonk means nothing to do, whatever the other arguments say.
ok(E.Step(false, nil, 100, DELAY, false, nil) == "disarm", "inactive -> disarm")
ok(E.Step(false, 99, 100, DELAY, true, 99.5)  == "disarm", "inactive mid-sweep -> disarm")

-- 3. Before the delay elapses we wait. Cancelling early is the bug this whole
--    feature exists to avoid, so this is the important direction.
ok(E.Step(true, 100, 100,      DELAY, false, nil) == "wait", "just landed -> wait")
ok(E.Step(true, 100, 100.39,   DELAY, false, nil) == "wait", "one frame short -> wait")

-- 4. At and past the boundary, fire.
ok(E.Step(true, 100, 100.40,   DELAY, false, nil) == "fire", "exactly at the delay -> fire")
ok(E.Step(true, 100, 100.41,   DELAY, false, nil) == "fire", "past the delay -> fire")
ok(E.Step(true, 100, 500,      DELAY, false, nil) == "fire", "long past -> fire")

-- 5. No anchor means we do NOT know when the transform landed, so we must not
--    fire. Erring late is free; erring early welds the player.
ok(E.Step(true, nil, 100, DELAY, false, nil) == "wait", "no anchor -> wait, never fire")

-- 6. Once fired we do NOT immediately re-cancel. A cancel the server has
--    accepted still takes a beat to show up as the aura leaving, and firing a
--    second cancel into that exit transition welds the player — the very bug
--    this feature exists to prevent. Measured in-game 2026-08-12: cancel #1 at
--    +0.400, cancel #2 at +0.501, aura gone at +0.576, player welded. The
--    reference WeakAura's single-attempt latch turns out to be load-bearing.
ok(E.Step(true, 100, 100.5, DELAY, true, 100.4, 100.4) == "wait", "0.1s after firing -> wait, not retry")
ok(E.Step(true, 100, 100.6, DELAY, true, 100.4, 100.4) == "wait", "mid exit transition -> wait")
ok(E.Step(true, 100, 101.3, DELAY, true, 100.4, 100.4) == "wait", "0.9s after firing -> still wait")

-- 7. Past the grace the cancel demonstrably did not take, so try again. This is
--    the safety net the WeakAura lacks: a no-op cancel there leaves you welded
--    with no recourse at all.
ok(E.Step(true, 100, 101.4, DELAY, true, 100.4, 100.4) == "retry", "a grace period after firing -> retry")

-- 8. Retry cadence runs from the LAST attempt; the give-up cap runs from the
--    FIRST. Measuring the cap from the last attempt would push it out forever.
ok(E.Step(true, 100, 101.5, DELAY, true, 100.4, 101.4) == "wait",  "just after a retry -> wait again")
ok(E.Step(true, 100, 102.4, DELAY, true, 100.4, 101.4) == "retry", "a grace period after the retry -> retry")

-- 9. Past the cap, stop hammering and hand it back to the user. Give-up
--    outranks a retry that is also due.
ok(E.Step(true, 100, 104.4, DELAY, true, 100.4, 103.4) == "giveup", "at the cap -> giveup")
ok(E.Step(true, 100, 999,   DELAY, true, 100.4, 998)   == "giveup", "far past the cap -> giveup")
ok(E.Step(true, 100, 104.4, DELAY, true, 100.4, 100.4) == "giveup", "cap outranks a due retry")

-- 10. A fired flag with no stamps cannot age out. Wait rather than retry: an
--     unprompted second cancel is the dangerous direction, never the safe one.
ok(E.Step(true, 100, 999, DELAY, true, nil, nil) == "wait", "fired with no stamp -> wait")

-- 11. lastTryAt missing but firedAt present falls back to firedAt, so the first
--     retry still lands a grace period after the first attempt.
ok(E.Step(true, 100, 100.5, DELAY, true, 100.4, nil) == "wait",  "no lastTryAt: still inside the grace")
ok(E.Step(true, 100, 101.4, DELAY, true, 100.4, nil) == "retry", "no lastTryAt: retry falls back to firedAt")

-- 9. WaitFor: the remaining slice of the delay.
ok(near(E.WaitFor(100, 100,    DELAY), 0.40), "WaitFor: fresh aura waits the full delay")
ok(near(E.WaitFor(100, 100.15, DELAY), 0.25), "WaitFor: partially elapsed")

-- 10. Clamped at zero. A /reload mid-transform re-arms with the anchor already
--     well in the past; that must fire immediately, not schedule a negative
--     timer (AceTimer would treat it as a tiny delay, but the intent must be
--     explicit).
ok(near(E.WaitFor(100, 100.40, DELAY), 0), "WaitFor: exactly elapsed clamps to 0")
ok(near(E.WaitFor(100, 600,    DELAY), 0), "WaitFor: long elapsed clamps to 0")
ok(E.WaitFor(100, 600, DELAY) >= 0,        "WaitFor: never negative")

-- 11. No anchor waits the FULL delay from now, matching Step's refusal to fire
--     without one. Both err late.
ok(near(E.WaitFor(nil, 100, DELAY), DELAY), "WaitFor: no anchor waits the full delay")

print(("tonk_engine: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
