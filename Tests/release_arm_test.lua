-- Tests/release_arm_test.lua
-- Standalone LuaJIT tests for the release bar's arm-status classifier
-- (UI/Frame_ReleaseBar.lua): the chip that answers "did my !Auto Shot press
-- actually register?". Pure given four booleans, so it runs outside WoW.
-- Run from the repo root: luajit Tests/release_arm_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- Minimal surface: the frame file only DEFINES functions at load; frames are
-- built in OnInitialize, which the harness never calls. NewModule hands back a
-- plain table the file decorates — that's our handle.
local mod = {}
local Nock = {
  Constants = { RETRY_PULSE = 0.5, FONT = { SIZE_OVERLAY = 10 } },
  NewModule = function() return mod end,
}
_G.LibStub = function() return { GetAddon = function() return Nock end } end

dofile("UI/Frame_ReleaseBar.lua")

local S = mod.ArmStatus
ok(type(S) == "function", "ArmStatus exists")

-- (windup, repeating, keyHeld, inCombat)
-- 1. The wind-up outranks everything: the shot is committed, nothing can
--    clip it — the strongest possible "your press worked".
ok(S(true,  true,  false, true)  == "firing", "wind-up -> firing")
ok(S(true,  false, true,  true)  == "firing", "wind-up outranks a dead toggle mid-hold")

-- 2. Auto-repeat on = the press registered with the client.
ok(S(false, true,  false, true)  == "armed", "repeating -> armed")
ok(S(false, true,  true,  true)  == "armed", "still armed while the key is held")
ok(S(false, true,  false, false) == "armed", "armed reads out of combat too")

-- 3. Toggle off while the weave key is held is EXPECTED (/startattack switched
--    you to melee) — neutral, not a warning.
ok(S(false, false, true,  true)  == "melee", "off during a hold -> melee, not a warning")

-- 4. Toggle off, key up, in combat: the re-arm press did NOT register — the
--    one state that costs a whole swing cycle. Loud.
ok(S(false, false, false, true)  == "off", "off in combat with no hold -> OFF warning")

-- 5. Out of combat a dead toggle is just standing around, not an emergency.
ok(S(false, false, false, false) == nil, "off out of combat -> no chip")

print(("release_arm: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
