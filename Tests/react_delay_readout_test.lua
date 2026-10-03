-- Tests/react_delay_readout_test.lua
-- The Auto Shot delay readout's own look on Forever (Bars -> Delay readout):
-- Nock.UI.DelayTextLayout (anchor, offsets, font, size, outline) and the
-- profile-driven tier colours in Nock.UI.DelaySeverityColor, applied by the
-- React cluster's ApplyLayout. Run from the repo root: luajit Tests/react_delay_readout_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.GetTime = function() return 0 end
_G.UIParent = Stub.CreateFrame("Frame", "UIParent")
local profile = { reactWidth = 202, reactAutoH = 14, reactMeleeH = 8, reactRangeH = 14, reactManaH = 12, reactWeaveH = 18 }
local Nock = {
  db = { profile = profile },
  Flavor = { forever = false, Plain = function(v) return v end },
  Constants = setmetatable({ FONT = { PATH = "ref.ttf" }, DIM = {}, COLORS = {} }, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }),
  parentFrame = Stub.CreateFrame("Frame"),
  state = {},
  AutoSwingLive = function() return true end,
  AutoShotWindup = function() return 0.4 end,
}
local modules = {}
function Nock:NewModule(name) local m = { name = name, RegisterEvent = function() end, RegisterMessage = function() end }; modules[name] = m; return m end
function Nock:GetModule(name) return modules[name] end
local fonts = { ["Nock Digits"] = "Media/digits.ttf" }
local LSM = setmetatable({ Fetch = function(_, kind, name) return kind == "font" and fonts[name] or nil end },
  { __index = function() return function() end end })
local libs = { ["AceAddon-3.0"] = { GetAddon = function() return Nock end }, ["LibSharedMedia-3.0"] = LSM }
_G.LibStub = setmetatable({}, { __call = function(_, name, silent) local l = libs[name]; if not l and not silent then error("missing " .. name) end; return l end })
dofile("UI/Widgets.lua")
dofile("UI/ReactRangeLadder.lua")
dofile("UI/ReactWeaveStrip.lua")
dofile("UI/Frame_ReactCluster.lua")
modules.RangeFinder = { name = "RangeFinder" }
modules.WeaveHelper = { name = "WeaveHelper", Enabled = function() return false end }

-- DelayTextLayout: the pure read of the profile.
local L = Nock.UI.DelayTextLayout
ok(type(L) == "function", "DelayTextLayout exists")
do
  local anchor, x, y, font, size, flags = L({})
  ok(anchor == "CENTER" and x == 0 and y == 0, "defaults: centred, no nudge")
  ok(font == nil, "defaults: no own font (the React font stands)")
  ok(size == 8 and flags == "OUTLINE", "defaults: 8 px, plain outline")
end
do
  local anchor, x, y, font, size, flags = L({ reactDelayAnchor = "LEFT", reactDelayOffsetX = 12, reactDelayOffsetY = -5,
    reactDelayFont = "Nock Digits", reactDelayFontSize = 14, reactDelayFontThick = true })
  ok(anchor == "LEFT" and x == 12 and y == -5, "anchor and offsets read")
  ok(font == "Media/digits.ttf", "a named LSM font resolves to its path")
  ok(size == 14 and flags == "THICKOUTLINE", "size and thick outline read")
end
do
  local anchor, _, _, font, size = L({ reactDelayAnchor = "TOP", reactDelayFont = "Unknown Face", reactDelayFontSize = 3 })
  ok(anchor == "CENTER", "an anchor off the list falls back to CENTER")
  ok(font == nil, "an unregistered font name falls back to nil")
  ok(size == 6, "size clamps to 6")
  ok(select(5, L({ reactDelayFontSize = 99 })) == 40, "size clamps to 40")
  ok(select(5, L({ reactDelayFontSize = "junk" })) == 8, "a non-number size reads as the default")
  local _, x, y = L({ reactDelayOffsetX = "a", reactDelayOffsetY = nil })
  ok(x == 0 and y == 0, "non-number offsets read as 0")
end

-- DelaySeverityColor: the four tiers, reference colours with no profile.
local Cfn = Nock.UI.DelaySeverityColor
local function near(a, b) return math.abs(a - b) < 1e-6 end
do
  local r, g, b = Cfn(0.0, {})
  ok(near(r, 0) and near(g, 1) and near(b, 0.596), "0.00 -> reference green")
  r, g, b = Cfn(0.10, {})
  ok(near(r, 1) and near(g, 0.957) and near(b, 0.408), "0.10 -> reference yellow")
  r, g, b = Cfn(0.25, {})
  ok(near(r, 1) and near(g, 0.702) and near(b, 0), "0.25 -> reference orange")
  r, g, b = Cfn(0.50, {})
  ok(near(r, 0.769) and near(g, 0.118) and near(b, 0.227), "0.50 -> reference red")
  r, g, b = Cfn(0.0)
  ok(near(r, 0) and near(g, 1) and near(b, 0.596), "no profile argument reads Nock.db.profile")
end
do
  local p = { reactColorDelayGood = { 0.1, 0.2, 0.3, 1 }, reactColorDelayLow = { 0.4, 0.5, 0.6, 1 },
              reactColorDelayMid = { 0.7, 0.8, 0.9, 1 }, reactColorDelayHigh = { 1, 0, 1, 1 } }
  local r, g, b = Cfn(0.05, p)
  ok(near(r, 0.1) and near(g, 0.2) and near(b, 0.3), "good tier from the profile")
  r, g, b = Cfn(0.12, p)
  ok(near(r, 0.4) and near(g, 0.5) and near(b, 0.6), "low tier from the profile")
  r, g, b = Cfn(0.3, p)
  ok(near(r, 0.7) and near(g, 0.8) and near(b, 0.9), "mid tier from the profile")
  r, g, b = Cfn(0.9, p)
  ok(near(r, 1) and near(g, 0) and near(b, 1), "high tier from the profile")
  r, g, b = Cfn(0.9, { reactColorDelayHigh = "junk" })
  ok(near(r, 0.769), "a broken colour entry falls back to the reference")
end

-- The React cluster: on TBC the readout keeps the skin's centred look; on
-- Forever ApplyLayout places and fonts it from the profile.
local RC = modules.ReactCluster
RC:OnInitialize()
local dt = RC.auto.delayText
local fontCalls = {}
local realSafe = Nock.UI.SafeSetFont
Nock.UI.SafeSetFont = function(fs, path, size, flags)
  if fs == dt then fontCalls[#fontCalls + 1] = { path, size, flags } end
  return realSafe(fs, path, size, flags)
end
profile.reactDelayAnchor, profile.reactDelayOffsetX, profile.reactDelayOffsetY = "RIGHT", -8, 3
profile.reactDelayFont, profile.reactDelayFontSize, profile.reactDelayFontThick = "Nock Digits", 13, true
RC:ApplyLayout()
local p1, _, p3, x, y = dt:GetPoint()
ok(p1 == "CENTER" and p3 == "CENTER" and x == 0 and y == 0, "TBC: the readout stays centred on the bar")
local last = fontCalls[#fontCalls]
ok(last == nil or last[2] ~= 13, "TBC: the readout's own size is not applied")

Nock.Flavor.forever = true
fontCalls = {}
RC:ApplyLayout()
local rel
p1, rel, p3, x, y = dt:GetPoint()
ok(p1 == "RIGHT" and rel == RC.auto and p3 == "RIGHT" and x == -8 and y == 3, "Forever: anchored RIGHT of the auto bar with the nudges")
last = fontCalls[#fontCalls]
ok(last and last[1] == "Media/digits.ttf" and last[2] == 13 and last[3] == "THICKOUTLINE", "Forever: own font, size and thick outline applied last")

profile.reactDelayFont = ""
profile.reactFont = nil
fontCalls = {}
RC:ApplyLayout()
last = fontCalls[#fontCalls]
ok(last and last[1] == "ref.ttf" and last[2] == 13, "Forever: no own font -> the React font (reference path here)")

-- The tick colours the number from the profile tiers.
profile.reactShowDelay = true
profile.reactColorDelayMid = { 0.7, 0.8, 0.9, 1 }
RC:ApplyLayout()
local colored
dt.SetTextColor = function(self, r, g, b) colored = { r, g, b } end
RC:RefreshAuto({ ranged = { swingStart = 10, swingDuration = 2.0, swingRemaining = 1.2, queueWindow = 0.4, autoDelay = 0.3 }, gcd = {} })
ok(colored and near(colored[1], 0.7) and near(colored[2], 0.8) and near(colored[3], 0.9), "Refresh paints the mid tier from the profile")

print(("react_delay_readout: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
