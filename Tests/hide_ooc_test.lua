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
