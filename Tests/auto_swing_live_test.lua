-- Tests/auto_swing_live_test.lua
-- Standalone LuaJIT tests for Nock.AutoSwingLive in Core/State.lua: the shared
-- "should the auto-swing views render?" gate used by the React auto bar and the
-- release bar's always-mode. Exists because the stale-`repeating` leg of the old
-- inline gate pinned both views at 100% after a fight ended with auto toggled.
-- Run from the repo root: luajit Tests/auto_swing_live_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- Minimal WoW/Ace surface, same as clip_threshold_test.
local Nock = {}
_G.GetRangedHaste = function() return 0 end
_G.LibStub = function() return { GetAddon = function() return Nock end } end

dofile("Core/State.lua")

ok(type(Nock.AutoSwingLive) == "function", "AutoSwingLive exists")
if type(Nock.AutoSwingLive) ~= "function" then
  print(("auto_swing_live: %d passed, %d failed"):format(pass, fail))
  os.exit(1)
end

local st = Nock.state

local function set(swingStart, swingDuration, swingRemaining, inCombat, repeating)
  st.ranged.swingStart     = swingStart
  st.ranged.swingDuration  = swingDuration
  st.ranged.swingRemaining = swingRemaining
  st.ranged.repeating      = repeating
  st.player.inCombat       = inCombat
end

-- 1. Never fired a shot: nothing to draw, whatever the flags claim.
set(0, 3.0, 0, true, true)
ok(not Nock.AutoSwingLive(), "no swing tracked: not live even in combat")

-- 2. In combat a swing in flight always draws — weaving can drop `repeating`
--    mid-cycle, so the flag must not be able to blank a running swing.
set(100, 3.0, 1.2, true, false)
ok(Nock.AutoSwingLive(), "in combat, swing in flight: live")

-- 3. In combat, swing expired, auto still ARMED (moving, no line of sight,
--    held shot): the full bar is the message — auto fires the moment you can
--    shoot. Live.
set(100, 3.0, 0, true, true)
ok(Nock.AutoSwingLive(), "in combat, expired, auto armed: live (held shot)")

-- 3b. In combat, swing expired, auto DISARMED: stepping into melee cancels
--     auto-repeat (dummy-verified — the shot needs a fresh !Auto Shot press
--     plus its wind-up before anything fires). A full bar here is a lie;
--     blank until the re-arm lands (START_AUTOREPEAT_SPELL).
set(100, 3.0, 0, true, false)
ok(not Nock.AutoSwingLive(), "in combat, expired, auto disarmed: NOT live")

-- 4. Out of combat a swing still in flight finishes drawing its cycle.
set(100, 3.0, 0.8, false, false)
ok(Nock.AutoSwingLive(), "out of combat, swing in flight: live")

-- 5. THE bug this gate exists to kill: fight over, swing expired, but
--    `repeating` got stranded true (weave key re-armed !Auto Shot around the
--    kill). The old inline gate stayed live here and pinned the bar at 100%.
set(100, 3.0, 0, false, true)
ok(not Nock.AutoSwingLive(), "out of combat, expired, repeating stranded: NOT live")

-- 6. Plain idle after a fight.
set(100, 3.0, 0, false, false)
ok(not Nock.AutoSwingLive(), "out of combat, expired, idle: not live")

-- 7. No usable duration: never live (avoids a 0-division downstream).
set(100, 0, 0, true, true)
ok(not Nock.AutoSwingLive(), "zero swingDuration: not live")

-- Practice fight = combat for the held-shot rule: an expired, armed swing
-- stays full out of real combat while a drill runs (a clipped auto waiting on
-- a cast), and blanks again once the drill stops.
st.sim = st.sim or {}
set(100, 3.0, 0, false, true)
st.sim.fightOn = true
ok(Nock.AutoSwingLive(), "practice fight: expired + armed stays live (held shot)")
st.sim.fightOn = false
ok(not Nock.AutoSwingLive(), "no fight, no combat: expired swing not live")

print(("auto_swing_live: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
