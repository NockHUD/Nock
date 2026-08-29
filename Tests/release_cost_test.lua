-- Tests/release_cost_test.lua
-- Standalone LuaJIT tests for the Auto Shot reactivation retry math in
-- Core/State.lua: Nock.ReleaseCost and Nock.ReleaseFreeIn. The claim under
-- test (Aerthax, Classic Hunter Discord 2022): after /cast !Auto Shot the
-- client re-checks on a ~0.5s pulse anchored at the press, so the shot fires
-- at the first check AFTER swing-ready — a sawtooth cost over press time,
-- zero at exact pulse multiples before ready and everywhere after it.
-- Run from the repo root: luajit Tests/release_cost_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-6) end

-- Minimal surface: State.lua needs the addon table, the haste global and the
-- one constant. Same harness shape as clip_threshold_test.lua.
local Nock = {}
_G.GetRangedHaste = function() return 0 end
_G.LibStub = function() return { GetAddon = function() return Nock end } end

dofile("Core/State.lua")

Nock.Constants = { AUTO_SHOT_CAST = 0.5, RETRY_PULSE = 0.5 }

-- 1. The free zone: at or past swing-ready the first check succeeds at once.
ok(near(Nock.ReleaseCost(0), 0),     "cost: zero at ready")
ok(near(Nock.ReleaseCost(-0.3), 0),  "cost: zero past ready")
ok(near(Nock.ReleaseCost(nil), 0),   "cost: nil remaining treated as free")

-- 2. The last tooth: pressing inside the final pulse before ready delays the
--    shot to the first check after ready. rem = time before ready; the check
--    lands at press + 0.5, i.e. 0.5 - rem late.
ok(near(Nock.ReleaseCost(0.1),  0.4),  "cost: 0.1s early -> 0.4s late")
ok(near(Nock.ReleaseCost(0.2),  0.3),  "cost: 0.2s early -> 0.3s late")
ok(near(Nock.ReleaseCost(0.45), 0.05), "cost: 0.45s early -> 0.05s late")

-- 3. Free notches: at exact pulse multiples before ready a check lands ON
--    ready. These are Aerthax's "you could theoretically do it earlier".
ok(near(Nock.ReleaseCost(0.5), 0),  "notch: one pulse early is free")
ok(near(Nock.ReleaseCost(1.0), 0),  "notch: two pulses early is free")
ok(near(Nock.ReleaseCost(1.5), 0),  "notch: three pulses early is free")

-- 4. The sawtooth repeats every pulse going left.
ok(near(Nock.ReleaseCost(0.75), 0.25), "sawtooth: mid second tooth")
ok(near(Nock.ReleaseCost(1.3),  0.2),  "sawtooth: third tooth")
ok(near(Nock.ReleaseCost(0.3), Nock.ReleaseCost(0.8)),
   "sawtooth: same phase, same cost, one pulse apart")

-- 5. Cost is bounded by the pulse: never negative, never a full pulse.
for _, rem in ipairs({ 0.01, 0.25, 0.49, 0.51, 0.99, 1.01, 2.37 }) do
  local c = Nock.ReleaseCost(rem)
  ok(c >= 0 and c < 0.5, ("cost bounded at rem=%.2f"):format(rem))
end

-- 6. Explicit pulse override (M1 may correct the measured pulse).
ok(near(Nock.ReleaseCost(0.3, 1.0), 0.7), "pulse override: 1.0s pulse")
ok(near(Nock.ReleaseCost(2.0, 1.0), 0),   "pulse override: notch at a multiple")

-- 7. ReleaseFreeIn: seconds until the cost next hits zero (the upcoming notch,
--    or ready itself inside the last tooth).
ok(near(Nock.ReleaseFreeIn(0), 0),     "freeIn: zero at ready")
ok(near(Nock.ReleaseFreeIn(-1), 0),    "freeIn: zero past ready")
ok(near(Nock.ReleaseFreeIn(nil), 0),   "freeIn: nil treated as free now")
ok(near(Nock.ReleaseFreeIn(0.3), 0.3), "freeIn: last tooth waits for ready")
ok(near(Nock.ReleaseFreeIn(0.75), 0.25), "freeIn: second tooth waits for the notch")
ok(near(Nock.ReleaseFreeIn(1.0), 0),   "freeIn: standing on a notch")

-- 8. The two agree: cost is zero exactly when freeIn is zero.
for _, rem in ipairs({ -0.2, 0, 0.2, 0.5, 0.7, 1.0, 1.2 }) do
  local czero = near(Nock.ReleaseCost(rem), 0, 1e-6)
  local fzero = near(Nock.ReleaseFreeIn(rem), 0, 1e-6)
  ok(czero == fzero, ("cost/freeIn agree at rem=%.1f"):format(rem))
end

-- 9. Float robustness: a rem that is "one pulse" only up to floating error
--    must still read as a notch, not as a near-full-pulse cost.
local drifty = 0.1 + 0.2 + 0.2   -- 0.5 with binary drift
ok(Nock.ReleaseCost(drifty) < 0.01, "notch survives floating-point drift")

print(("release_cost: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
