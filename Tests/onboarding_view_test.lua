-- Tests/onboarding_view_test.lua
-- The wizard window's remembered position: a saved anchor is reused only while
-- it still lands on screen; anything else falls back to the docked default.
-- Run from the repo root: luajit Tests/onboarding_view_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.UIParent = Stub.CreateFrame("Frame")
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.unpack = unpack or table.unpack
_G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
local Nock = {
  Constants = { COLORS = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }), FONT = { PATH = "" } },
  UI = { ApplyBackdrop = function() end, GetFont = function() return "" end, RegisterHeaderFontString = function() end },
  db = { char = {}, profile = {} }, modules = {},
}
function Nock:NewModule(name) local m = { name = name }; function m:RegisterMessage() end; self.modules[name] = m; return m end
function Nock:GetModule(name) return self.modules[name] end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("UI/Frame_Onboarding.lua")
local View = Nock.modules.OnboardingView

ok(View.PositionValid(nil, 1920, 1080) == false, "no saved position: default")
ok(View.PositionValid(false, 1920, 1080) == false, "false: default")
ok(View.PositionValid({ point = "RIGHT", relPoint = "RIGHT", x = -24, y = 0 }, 1920, 1080) == true, "docked default is valid")
ok(View.PositionValid({ point = "CENTER", relPoint = "CENTER", x = 0, y = 170 }, 1920, 1080) == true, "old centre spot is valid")
ok(View.PositionValid({ point = "CENTER", relPoint = "CENTER", x = 3000, y = 0 }, 1920, 1080) == false, "off the right edge: default")
ok(View.PositionValid({ point = "CENTER", relPoint = "CENTER", x = 0, y = -2000 }, 1920, 1080) == false, "off the bottom: default")
ok(View.PositionValid({ point = "TOPLEFT" }, 1920, 1080) == false, "missing numbers: default")

print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
