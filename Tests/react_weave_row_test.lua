-- Tests/react_weave_row_test.lua
-- UI/Frame_ReactCluster.lua on Forever: the weave strip row's geometry (its
-- height, its place under the melee bar, gone with the helper off) and the
-- refresh dispatch. Headless under the frame stub.
-- Run from the repo root: luajit Tests/react_weave_row_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.GetTime = function() return 0 end
_G.UIParent = Stub.CreateFrame("Frame", "UIParent")
local profile = { reactWidth = 220, reactAutoH = 14, reactMeleeH = 8, reactRangeH = 14, reactManaH = 12, reactWeaveH = 18 }
local Nock = {
  db = { profile = profile },
  Flavor = { forever = true, Plain = function(v) return v end },
  Constants = setmetatable({ FONT = { PATH = "f" }, DIM = {}, COLORS = {} }, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }),
  parentFrame = Stub.CreateFrame("Frame"),
  state = {},
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
modules.RangeFinder = { name = "RangeFinder" }   -- the range row needs its module on Forever
modules.WeaveHelper = { name = "WeaveHelper", Enabled = function(p) return not (p and p.weaveHelperEnabled == false) end }
local RC = modules.ReactCluster
RC:OnInitialize()
ok(RC.weave ~= nil, "the strip exists on Forever")

local g = RC:Geometry()
ok(g.showWeave == true and g.hWeave == 18, "weave row shown at reactWeaveH")
ok(g.yWeave == g.yMelee + g.hMelee - 1, "the weave row sits right under the melee bar (shared seam)")
ok(g.yLadder == g.yWeave + g.hWeave - 1, "the ladder follows the weave row")
ok(g.total == 14 + 8 + 18 + 14 + 12 - 4, "total height counts the five rows and four seams")

profile.weaveHelperEnabled = false
g = RC:Geometry()
ok(g.showWeave == false and g.yLadder == g.yMelee + g.hMelee - 1 and g.total == 14 + 8 + 14 + 12 - 3, "helper off hides the row and the stack closes up")
profile.weaveHelperEnabled = nil

profile.reactShowWeaveStrip = false
g = RC:Geometry()
ok(g.showWeave == false, "the strip's own switch hides the row too")
profile.reactShowWeaveStrip = nil

profile.reactBarOrder = { "weave", "auto", "melee", "range", "mana" }
g = RC:Geometry()
ok(g.yWeave == 0 and g.yAuto == 18 - 1, "the order editor can move the row")
profile.reactBarOrder = nil

-- Refresh dispatch: RefreshWeave runs when the row is shown. The other
-- refreshers are stubbed: this test owns the dispatch, not their painting.
RC:ApplyLayout()
RC.frame:Show()   -- the HUD shows the container once it is placed; headless, do it here
local calls = 0
RC.RefreshWeave = function() calls = calls + 1 end
RC.RefreshAuto, RC.RefreshMelee, RC.RefreshRange, RC.RefreshStrip, RC.RefreshLadder, RC.RefreshMana =
  function() end, function() end, function() end, function() end, function() end, function() end
local blank = { target = {}, weave = {}, ranged = {}, melee = { swingStart = 0, swingRemaining = 0, swingDuration = 0 }, cooldowns = {}, player = {} }
RC:Refresh(blank)
ok(calls == 1, "Refresh dispatches to RefreshWeave")
RC.weave:Hide()
RC:Refresh(blank)
ok(calls == 1, "a hidden row is not refreshed")

print(("react_weave_row: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
