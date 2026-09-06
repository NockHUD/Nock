-- Tests/keycapture_test.lua
-- KeyCapture.Format produces AceGUI's binding strings.
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
_G.LibStub = setmetatable({}, { __call = function() return { GetAddon = function() return _G.NockStub end } end })
_G.NockStub = { UI = {} }
dofile("UI/KeyCapture.lua")
local F = _G.NockStub.UI.KeyCapture.Format
ok(F("F", false, false, false) == "F", "plain key")
ok(F("F", true, true, true) == "ALT-CTRL-SHIFT-F", "modifier order ALT-CTRL-SHIFT")
ok(F("2", true, false, false) == "SHIFT-2", "shift-2")
ok(F("MiddleButton") == "BUTTON3" and F("Button4") == "BUTTON4" and F("Button5") == "BUTTON5", "mouse buttons")
ok(F("MOUSEWHEELUP", false, true, false) == "CTRL-MOUSEWHEELUP", "mouse wheel with modifier")
ok(F("ESCAPE") == "", "escape clears")
ok(F("LSHIFT") == nil and F("RCTRL") == nil and F("LALT") == nil, "bare modifiers are not bindings")
ok(F("UNKNOWN") == "UNKNOWN", "unknown keys pass through")
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
