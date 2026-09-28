-- Tests/forever_camera_view_test.lua
-- Forever/CameraSetupView.lua pure helpers: the track marker position, the
-- turn texts per offset and the signed degree text.
-- Run from the repo root: luajit Tests/forever_camera_view_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end

local Nock = { Constants = { FONT = { PATH = "f" } }, UI = {}, Skin = { FONTS = { monoMedium = "m" } } }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/CameraSetupView.lua")
local V = Nock.CameraSetupView
ok(type(V) == "table" and type(V.Render) == "function", "view exported")

ok(near(V.MarkerX(0, 330), 165), "zero offset sits at the centre")
ok(near(V.MarkerX(-180, 330), 0) and near(V.MarkerX(180, 330), 330), "the ends map to the track ends")
ok(near(V.MarkerX(-400, 330), 0), "clamped below -180")
ok(near(V.MarkerX(nil, 330), 165), "nil offset reads as centre")

local pill, state, hint = V.TurnTexts(-14, false)
ok(pill == "Almost, tap slower" and state == "almost" and hint == "Tap Turn Right.", "near band, negative: turn right")
pill, state, hint = V.TurnTexts(42, false)
ok(pill == "Keep tapping" and state == "42 deg to go" and hint == "Tap Turn Left.", "far, positive: turn left with the count")
pill, state, hint = V.TurnTexts(0.4, true)
ok(pill == "Sweet spot: release LMB" and state == "done", "in the band")
pill, state = V.TurnTexts(nil, false)
ok(pill == "Waiting for step 1" and state == "?", "no baseline yet")

ok(V.OffText(0.4) == "+0.4 deg" and V.OffText(-12) == "-12.0 deg" and V.OffText(nil) == "--", "signed degree text")

print(("forever_camera_view: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
