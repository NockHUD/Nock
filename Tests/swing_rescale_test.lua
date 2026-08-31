-- Tests/swing_rescale_test.lua
-- Standalone LuaJIT tests for the mid-cycle speed-change model in Core/State.lua.
--
-- Nock.ReanchorSwingStart: the client does NOT rescale the in-flight ranged
-- swing when attack speed changes — the shot already scheduled fires on its old
-- timing, and the new speed applies from the NEXT shot (dummy-observed: a DST
-- fall-off mid-cycle released the shot ~10% of a bar early against the
-- rescale-remainder model; the "mixed" wind-up sample of 2026-08-12 is likewise
-- exactly old-windup/new-speed). So a speed change shifts swingStart to
-- PRESERVE the release: start + newDur == the release the client scheduled.
--
-- Nock.AutoShotCastEnd: the wind-up bar re-anchoring guard (unchanged).
-- Run from the repo root: luajit Tests/swing_rescale_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-9) end

local Nock = {}
_G.GetRangedHaste = function() return 0 end
_G.LibStub = function() return { GetAddon = function() return Nock end } end

dofile("Core/State.lua")
Nock.Constants = { AUTO_SHOT_CAST = 0.5 }

-- ---------------------------------------------------------------------------
-- 1. Identity cases — nothing to re-anchor, input unchanged.
ok(Nock.ReanchorSwingStart(100, 3.0, 3.0, 101) == 100, "reanchor: same duration is a no-op")
ok(Nock.ReanchorSwingStart(0,   3.0, 2.0, 101) == 0,   "reanchor: no swing tracked is a no-op")
ok(Nock.ReanchorSwingStart(nil, 3.0, 2.0, 101) == nil, "reanchor: nil start passes through")
ok(Nock.ReanchorSwingStart(100, 0,   2.0, 101) == 100, "reanchor: zero old duration is a no-op")
ok(Nock.ReanchorSwingStart(100, 3.0, 0,   101) == 100, "reanchor: zero new duration is a no-op")

-- 2. Release already passed (delayed shot waiting on a cast): leave it alone.
ok(Nock.ReanchorSwingStart(100, 2.0, 1.5, 102.5) == 100, "reanchor: past release untouched")

-- 3. Haste GAINED mid-cycle (Lust/proc pops): the pre-wind-up part is locked,
--    the wind-up runs at the NEW speed (swinglog round 2: RF at 23.7% gave a
--    2.080 gap = 2.174 - windup@old + windup@new; twice, 9ms off). ratio =
--    windup/duration (0.5/baseSpeed). start=100, old=3.0, ratio=1/6:
--    release 103, wind-up start 102.5 (locked), new release 102.5 + 2/6.
do
  local s = Nock.ReanchorSwingStart(100, 3.0, 2.0, 102, 1 / 6)
  ok(near(s + 2.0, 102.5 + 2 / 6, 1e-9), "reanchor: gain locks to the wind-up start")
  local l = Nock.ReanchorSwingStart(100, 3.0, 2.0, 102)
  ok(near(l + 2.0, 103), "reanchor: nil ratio degrades to pure locked")
end

-- 4. Haste LOST mid-cycle (DST/proc expires): same rule the other way — the
--    wind-up stretches to the new speed (edge BEFORE the wind-up start —
--    101.5 here; on or past it the shot is locked, see 5b). start=100,
--    old=2.0, ratio=0.25: release 102, wind-up start 101.5, new release
--    101.5 + 0.75 = 102.25.
do
  local s = Nock.ReanchorSwingStart(100, 2.0, 3.0, 101.4, 0.25)
  ok(near(s + 3.0, 102.25), "reanchor: loss stretches only the wind-up")
end

-- 5. Exactly at a release (remaining == old duration): the new cycle runs at
--    the new speed from ITS start — identity. This is the
--    UNIT_SPELLCAST_SUCCEEDED → RefreshSwingDurations call path.
ok(near(Nock.ReanchorSwingStart(100, 3.0, 2.0, 100), 100), "reanchor: fresh release is a no-op")

-- 5b. An edge landing once the wind-up has BEGUN leaves the shot fully locked
--     (swinglog round 3: DST at 99.9%% of a cycle released on the old schedule
--     to 2ms — the wind-up commits to the speed it started with).
--     start=100, old=3.0, ratio=1/6: release 103, wind-up starts 102.5; an
--     edge at now=102.6 keeps the release at 103 exactly.
do
  local s = Nock.ReanchorSwingStart(100, 3.0, 2.0, 102.6, 1 / 6)
  ok(near(s + 2.0, 103), "reanchor: edge inside the wind-up is pure locked")
end

-- 6. The shifted start may land in the future when haste is gained late in the
--    cycle (release − newDur > now); the fill math clamps its own progress, so
--    the helper must NOT clamp — clamping would move the release.
do
  local s = Nock.ReanchorSwingStart(100, 3.0, 1.0, 100.5)   -- release 103, new start 102
  ok(near(s + 1.0, 103), "reanchor: release preserved even when start > now")
end

-- 7. Chained procs: each step preserves the wind-up start, so two changes
--    end where one straight old->new change would (windup start 102.5 fixed).
do
  local s1 = Nock.ReanchorSwingStart(100, 3.0, 2.4, 101, 1 / 6)
  local s2 = Nock.ReanchorSwingStart(s1, 2.4, 2.0, 101.5, 1 / 6)
  ok(near(s2 + 2.0, 102.5 + 2 / 6, 1e-9), "reanchor: chained procs keep the wind-up start")
end

-- ---------------------------------------------------------------------------
-- 8. AutoShotCastEnd: unchanged guard semantics.
ok(Nock.AutoShotCastEnd(103, 102.6, 102.9, 102.7) == 102.9, "bar end: adopts an earlier live release")
ok(Nock.AutoShotCastEnd(102.9, 102.6, 103.2, 102.7) == 103.2, "bar end: adopts a later live release")
ok(Nock.AutoShotCastEnd(103, 102.6, 102.65, 102.7) == 103, "bar end: past release rejected (delayed shot)")
ok(Nock.AutoShotCastEnd(103, 102.6, 102.5, 102.7) == 103,  "bar end: release before the bar start rejected")
ok(Nock.AutoShotCastEnd(103, 102.6, nil, 102.7) == 103,    "bar end: nil release keeps current")
ok(Nock.AutoShotCastEnd(103, 102.6, 103, 102.7) == 103,    "bar end: unchanged release keeps current")

print(string.format("swing_rescale_test: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
