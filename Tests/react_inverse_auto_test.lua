-- Tests/react_inverse_auto_test.lua
-- UI/Frame_ReactCluster.lua: reactDirAuto = "inverse" hangs the two auto-bar halves from the centre, drains them over the cooldown and regrows them in the wind-up colour.
-- Run from the repo root: luajit Tests/react_inverse_auto_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.GetTime = function() return 0 end
_G.UIParent = Stub.CreateFrame("Frame", "UIParent")
local profile = { reactWidth = 202, reactAutoH = 14, reactMeleeH = 8, reactRangeH = 14, reactManaH = 12, reactWeaveH = 18 }
local live, windup = true, 0.4
local Nock = {
  db = { profile = profile },
  Flavor = { forever = true, Plain = function(v) return v end },
  Constants = setmetatable({ FONT = { PATH = "f" }, DIM = {}, COLORS = {} }, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }),
  parentFrame = Stub.CreateFrame("Frame"),
  state = {},
  AutoSwingLive = function() return live end,
  AutoShotWindup = function() return windup end,
}
local modules = {}
function Nock:NewModule(name) local m = { name = name, RegisterEvent = function() end, RegisterMessage = function() end }; modules[name] = m; return m end
function Nock:GetModule(name) return modules[name] end
local libs = { ["AceAddon-3.0"] = { GetAddon = function() return Nock end } }
_G.LibStub = setmetatable({}, { __call = function(_, name, silent) local l = libs[name]; if not l and not silent then error("missing " .. name) end; return l end })
dofile("UI/Widgets.lua")
dofile("UI/ReactRangeLadder.lua")
dofile("UI/ReactWeaveStrip.lua")
dofile("UI/Frame_ReactCluster.lua")
modules.RangeFinder = { name = "RangeFinder" }
modules.WeaveHelper = { name = "WeaveHelper", Enabled = function() return false end }
local RC = modules.ReactCluster
RC:OnInitialize()

local function eq(c, ref) return c and c[1] == ref[1] and c[2] == ref[2] and c[3] == ref[3] end
local GOLD, RED = { 1.00, 0.84, 0.00, 1.00 }, { 0.85, 0.10, 0.10, 1.00 }
local auto = RC.auto
local state = { ranged = { swingStart = 10, swingDuration = 2.0, swingRemaining = 1.2, queueWindow = 0.4, autoDelay = 0 }, gcd = {} }

profile.reactDirAuto = "inverse"
RC:ApplyLayout()
local half = RC._halfW
ok(half and half > 0, "half width known after layout")
ok(auto.fillR:IsShown(), "inverse: both halves drawn")
ok(auto.fillL._point[1] == "BOTTOMRIGHT" and auto.fillL._point[3] == "BOTTOM"
   and auto.fillR._point[1] == "BOTTOMLEFT" and auto.fillR._point[3] == "BOTTOM",
   "inverse: the halves hang from the centre")

RC:RefreshAuto(state)
ok(math.abs(auto.fillL._w - 0.5 * half) <= 0.5 and auto.fillL._w == auto.fillR._w,
   "inverse: halfway through the cooldown = half extent")
ok(eq(auto.fillL._color, GOLD) and eq(auto.fillR._color, GOLD), "inverse: cooldown in the Auto Shot fill colour")
ok(auto.windupL:IsShown() == false and auto.windupR:IsShown() == false,
   "inverse: no wind-up / queue mark (it would sit on the centre)")

state.ranged.swingRemaining = 0.2
RC:RefreshAuto(state)
ok(math.abs(auto.fillL._w - 0.5 * half) <= 0.5, "inverse: halfway through the wind-up = half extent")
ok(eq(auto.fillL._color, RED) and eq(auto.fillR._color, RED), "inverse: wind-up in its own colour (default red)")

profile.reactColorAutoWindup = { 0.2, 0.4, 0.6, 1 }
RC:ApplyLayout()
RC:RefreshAuto(state)
ok(eq(auto.fillL._color, { 0.2, 0.4, 0.6 }), "inverse: the wind-up colour follows reactColorAutoWindup")
profile.reactColorAutoWindup = nil

state.ranged.swingRemaining = 0
RC:RefreshAuto(state)
ok(auto.fillL._w == half, "inverse: full at the release")

-- The Forever cycle log records converge/directional resets; a draining
-- inverse fill shrinks every pixel and must not flood it.
state.ranged.swingRemaining = 1.9
RC:RefreshAuto(state)
state.ranged.swingRemaining = 1.5
RC:RefreshAuto(state)
ok(RC._cycleLog == nil or #RC._cycleLog == 0, "inverse: the draining fill is not logged as a cycle reset")

live = false
RC:RefreshAuto(state)
ok(auto.fillL._w == 0.01 and auto.fillR._w == 0.01, "inverse: no live swing -> empty")
live = true

-- No wind-up to show (Forever today with the queue window at 0): plain drain.
windup = 0
state.ranged.swingRemaining = 0.5
RC:RefreshAuto(state)
ok(math.abs(auto.fillL._w - 0.25 * half) <= 0.5 and eq(auto.fillL._color, GOLD), "inverse without a wind-up: one draining phase")
windup = 0.4

-- Back to converge: edge anchors, fill colour and the mark return.
profile.reactDirAuto = "converge"
RC:ApplyLayout()
state.ranged.swingRemaining = 1.0
RC:RefreshAuto(state)
ok(auto.fillL._point[1] == "BOTTOMLEFT" and auto.fillL._point[3] == "BOTTOMLEFT"
   and auto.fillR._point[1] == "BOTTOMRIGHT" and auto.fillR._point[3] == "BOTTOMRIGHT",
   "converge again: halves back on the edges")
ok(eq(auto.fillL._color, GOLD), "converge again: fill colour restored")
ok(auto.windupL:IsShown() == true, "converge again: the queue mark is back")

print(("react_inverse_auto: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
