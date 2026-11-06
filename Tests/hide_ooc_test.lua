-- Tests/hide_ooc_test.lua
-- Standalone LuaJIT tests for the two readings of "Hide out of combat"
-- (Core/State.lua): Nock.HideOocApplies (the HUD, out of combat, yielding to
-- an unlocked HUD, the wizard preview and practice mode) and
-- Nock.RestedHideApplies (buff tracker + MD panel, while rested).
-- Run from the repo root: luajit Tests/hide_ooc_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local addon = { Constants = {} }
_G.LibStub = function(name) return { GetAddon = function() return addon end } end
dofile("Core/Constants.lua")
dofile("Core/State.lua")

local H, R = addon.HideOocApplies, addon.RestedHideApplies
ok(type(H) == "function" and type(R) == "function", "both predicates exist")

local function st(demo, sim) return { demo = { hudForceShow = demo }, sim = { active = sim } } end

-- HUD -------------------------------------------------------------------------
ok(H({ hideOoc = true,  locked = true }, false, st(false, false)) == true,  "hideOoc + ooc + locked -> hide")
ok(H({ hideOoc = false, locked = true }, false, st(false, false)) == false, "switch off -> show")
ok(H({ hideOoc = true,  locked = true }, true,  st(false, false)) == false, "in combat -> show")
ok(H({ hideOoc = true,  locked = false }, false, st(false, false)) == false, "unlocked -> show (must stay grabbable)")
ok(H({ hideOoc = true,  locked = true }, false, st(true, false)) == false,  "wizard preview -> show")
ok(H({ hideOoc = true,  locked = true }, false, st(false, true)) == false,  "practice on -> show (user, 2026-08-27)")
ok(H({ hideOoc = true }, false, st(false, false)) == true, "locked absent (default true) -> hide")
ok(H({ hideOoc = true, locked = true }, false, nil) == true, "no state -> the switch alone decides")
ok(H(nil, false, nil) == false, "no profile -> show")

-- Idle swing bars -------------------------------------------------------------
do
  local S = addon.SwingBarsHidden
  ok(type(S) == "function", "the idle swing bar reading exists")
  local function live(t)
    t = t or {}
    return {
      player = { inCombat = t.inCombat == true },
      ranged = { repeating = t.repeating == true, swingStart = t.autoStart or 0, swingRemaining = t.autoRem or 0 },
      melee  = { attacking = t.attacking == true, swingRemaining = t.meleeRem or 0 },
      demo   = { hudForceShow = t.demo == true },
      sim    = { active = t.sim == true },
    }
  end
  local on = { hideIdleSwingBars = true }
  local a, m = S(on, live())
  ok(a == false and m == false, "TBC: the switch is ignored, even if set in the profile")
  addon.Flavor = { forever = false }
  a, m = S(on, live())
  ok(a == false and m == false, "TBC flavor flag: still ignored")
  addon.Flavor = { forever = true }
  a, m = S(on, live())
  ok(a == true and m == true, "idle out of combat: both hide")
  a, m = S({ hideIdleSwingBars = false }, live())
  ok(a == false and m == false, "switch off: both show")
  a, m = S({}, live())
  ok(a == false and m == false, "switch unset: both show")
  a, m = S(on, live({ inCombat = true }))
  ok(a == false and m == false, "in combat: both show")
  a, m = S(on, live({ repeating = true }))
  ok(a == false and m == true, "Auto Shot switched on before the pull: only its bar shows")
  a, m = S(on, live({ autoStart = 50, autoRem = 1.2 }))
  ok(a == false and m == true, "a reload still running after combat: only its bar shows")
  a, m = S(on, live({ autoStart = 50, autoRem = 0 }))
  ok(a == true, "a finished reload with Auto Shot off hides")
  a, m = S(on, live({ attacking = true }))
  ok(a == true and m == false, "melee switched on: only its bar shows")
  a, m = S(on, live({ meleeRem = 0.8 }))
  ok(a == true and m == false, "a melee swing still running: only its bar shows")
  a, m = S({ hideIdleSwingBars = true, locked = false }, live())
  ok(a == false and m == false, "unlocked: both show (must stay placeable)")
  a, m = S(on, live({ demo = true }))
  ok(a == false and m == false, "wizard preview: both show")
  a, m = S(on, live({ sim = true }))
  ok(a == false and m == false, "practice on: both show")
  a, m = S(nil, live())
  ok(a == false and m == false, "no profile: both show")

  local D = addon.SetIdleHidden
  local calls = {}
  local region = { SetAlpha = function(_, v) calls[#calls + 1] = v end }
  D(region, true); D(region, true)
  ok(#calls == 1 and calls[1] == 0, "hidden: alpha 0, written once")
  D(region, false); D(region, false)
  ok(#calls == 2 and calls[2] == 1, "shown again: alpha 1, written once")
  D(nil, true)
  ok(#calls == 2, "a region that does not exist is skipped")
end

-- Rested ----------------------------------------------------------------------
ok(R({ hideOoc = true,  locked = true }, true,  st(false, false)) == true,  "hideOoc + rested + locked -> hide")
ok(R({ hideOoc = true,  locked = true }, false, st(false, false)) == false, "not rested -> show (out of combat is not enough)")
ok(R({ hideOoc = false, locked = true }, true,  st(false, false)) == false, "switch off -> show")
ok(R({ hideOoc = true,  locked = false }, true, st(false, false)) == false, "unlocked -> show")
ok(R({ hideOoc = true,  locked = true }, true,  st(true, false)) == false,  "wizard preview -> show")
ok(R({ hideOoc = true,  locked = true }, true,  st(false, true)) == true,   "practice does not keep the rested panels up")
ok(R({ hideOoc = true,  locked = true }, nil,   nil) == false, "IsResting absent (nil) -> show")

print(("hide_ooc_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
