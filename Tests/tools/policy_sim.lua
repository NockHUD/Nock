-- Tests/tools/policy_sim.lua
-- A headless hand that plays WoWSims' ADAPTIVE hunter rotation (sim/hunter/
-- rotation.go, adaptiveRotation) on Nock's practice engine, for comparing its
-- mix and clips with the paper-true ghost (Tests/practice_gates_test.lua §36)
-- at the same haste. Not a test: prints a summary.
--   luajit Tests/tools/policy_sim.lua [ews] [seconds]
-- WoWSims' rule, per decision: for each option, expected damage = the option's
-- average hit minus the DPS of whatever it delays times the delay
-- (shoot: steadyDPS x GCD idle to the shot's release; a cast: shootDPS x the
-- auto's delay past its release). Best option wins; "shoot" waits for the
-- release and decides again. Damage units per hit from the user's WoWSims
-- Damage tab (2026-08-26): auto 1.00, Steady 1.00, Multi 1.11, Arcane 0.97.
local E = dofile("Modules/PracticeEngine.lua")
local M = dofile("Core/PracticeModel.lua")

local EWS = tonumber(arg and arg[1]) or 2.174
local SECS = tonumber(arg and arg[2]) or 180
local WS = 3.0
local RM = WS / EWS
local GCD, LAT = 1.5, 0.0
local U = { a = 1.00, s = 1.00, m = 1.11, A = 0.97 }

local cfg = { ws = WS, baseRangedMul = RM, latency = LAT, gcd = GCD,
              queueWindow = 0.4, castCorr = 1, multiCd = 10,
              arcaneCdBase = 6, arcaneCdPerPt = 0.2, imprArcanePts = 0,
              armOnShot = true, mws = 3.7, baseMeleeMul = 1.0,
              quickShots = false, seed = 1, eventCap = 20000 }
local e = E.New(cfg)
E.StartFight(e, 0)
E.SetDistance(e, 7)
E.Press(e, { "steady" }, 0)

local snap = {}
local t, dt = 0, 0.01
local waitUntil = nil
local stats = { a = 0, s = 0, m = 0, A = 0, clips = 0, clipSum = 0, clipMax = 0, idle = 0 }
local lastFree = 0
while t < SECS do
  E.SetNow(e, t); E.Step(e, t)
  E.Snapshot(e, snap)
  local gcdEnd = ((snap.gcdDur or 0) > 0) and ((snap.gcdStart or 0) + snap.gcdDur) or 0
  local castEnd = snap.cast and snap.cast.t1 or 0
  local free = (not snap.cast) and gcdEnd <= t + 1e-9 and (not e.queued)
  if free and (not waitUntil or t >= waitUntil) then
    waitUntil = nil
    -- WoWSims' `shootAt` is the wind-up START (RangedSwingAt); the shot is
    -- done a wind-up later. The engine's nextShotAt is the RELEASE.
    local windup = snap.windup or 0
    local shootAt = (snap.nextShotAt or t) - windup
    if shootAt < t then shootAt = t end
    local ews = snap.cycle or EWS
    local shootDPS, steadyDPS = U.a / ews, U.s / (GCD + LAT)
    local sCast = M.CastTime(1.5, snap.rangedMul or RM, 1)
    local mCast = M.CastTime(0.5, snap.rangedMul or RM, 1)
    local best, bestV = "shoot", U.a - steadyDPS * math.max(0, shootAt + windup - t)
    local v = U.s - shootDPS * math.max(0, t + sCast - shootAt)
    if v > bestV then best, bestV = "steady", v end
    if (snap.msReadyAt or 0) <= t then
      v = U.m - shootDPS * math.max(0, t + mCast - shootAt)
      if v > bestV then best, bestV = "multi", v end
    end
    if (snap.arcReadyAt or 0) <= t then
      v = U.A - shootDPS * math.max(0, t + LAT - shootAt)
      if v > bestV then best, bestV = "arcane", v end
    end
    if best == "shoot" then
      waitUntil = shootAt + windup + 0.001
    else
      E.Press(e, { best }, t)
    end
  end
  t = t + dt
end
for i = 1, e.n do
  local ev = e.events[i]
  if ev.kind == "auto" then
    stats.a = stats.a + 1
    if (ev.delay or 0) > 0.03 then
      stats.clips = stats.clips + 1; stats.clipSum = stats.clipSum + ev.delay
      if ev.delay > stats.clipMax then stats.clipMax = ev.delay end
    end
  elseif ev.kind == "cast" then
    local k = ({ steady = "s", multi = "m", arcane = "A" })[ev.spell]
    if k then stats[k] = stats[k] + 1 end
  end
end
local units = stats.a * U.a + stats.s * U.s + stats.m * U.m + stats.A * U.A
print(("ADAPTIVE eWS %.3f %ds: autos=%d steady=%d multi=%d arcane=%d casts/auto=%.2f | clips=%d total=%.2fs avg=%.0fms max=%.0fms | units=%.1f (%.3f/s)"):format(
  EWS, SECS, stats.a, stats.s, stats.m, stats.A, (stats.s + stats.m + stats.A) / math.max(1, stats.a),
  stats.clips, stats.clipSum, stats.clips > 0 and stats.clipSum / stats.clips * 1000 or 0, stats.clipMax * 1000, units, units / SECS))
