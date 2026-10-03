-- Tests/inverse_auto_bar_test.lua
-- The "inverse" Auto Shot bar mode (reactDirAuto / fluffyDirAuto): a centred fill that drains to the middle over the cooldown, then regrows in the wind-up colour until the release.
-- Run from the repo root: luajit Tests/inverse_auto_bar_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.UIParent = Stub.CreateFrame("Frame")
_G.GetTime = function() return 1000 end
_G.unpack = unpack or table.unpack
_G.GetRangedHaste = function() return 0 end

local Nock = { Constants = {}, state = {}, modules = {} }
function Nock:NewModule(name)
  local m = { name = name }
  function m:RegisterMessage() end
  function m:RegisterEvent() end
  Nock.modules[name] = m
  return m
end
_G.LibStub = setmetatable({}, { __call = function(_, lib, silent)
  if lib == "AceAddon-3.0" then return { GetAddon = function() return Nock end } end
  if silent then return nil end
  return {}
end })

dofile("Core/Constants.lua")
dofile("Config/Defaults.lua")
dofile("Core/State.lua")
dofile("UI/Widgets.lua")

--------------------------------------------------------------------------------
-- §1 Nock.AutoShotWindup: THE wind-up the views draw. TBC reads the measured
-- state.ranged.windup. Forever has no wind-up feed yet, so the spell-queue
-- window stands in until state.ranged.windupMeasured says there is one.
--------------------------------------------------------------------------------
local W = Nock.AutoShotWindup
ok(type(W) == "function", "Nock.AutoShotWindup exists")
if W then
  local r = Nock.state.ranged
  r.windup, r.queueWindow, r.windupMeasured = 0.365, 0.25, false
  Nock.Flavor = nil
  ok(near(W(), 0.365), "TBC: the measured wind-up")
  r.windup = nil
  ok(near(W(), Nock.Constants.AUTO_SHOT_CAST), "TBC: cold-start seed when nothing is derived yet")
  r.windup = 0.365
  Nock.Flavor = { forever = true }
  ok(near(W(), 0.25), "Forever, no wind-up feed: the spell-queue window stands in")
  r.queueWindow = nil
  ok(W() == 0, "Forever, no feed and no queue window: 0")
  r.queueWindow = 0.25
  r.windupMeasured = true
  ok(near(W(), 0.365), "Forever with a wind-up feed: the wind-up itself")
  r.windupMeasured = false
  Nock.Flavor = nil
end
ok(Nock.state.ranged.windupMeasured == false or Nock.state.ranged.windupMeasured == nil,
   "state.ranged.windupMeasured starts off")

--------------------------------------------------------------------------------
-- §2 Nock.UI.InverseAutoPhase(remaining, duration, windup) -> frac, isWindup.
-- frac is the fill's extent as a fraction of the HALF width.
--------------------------------------------------------------------------------
local phase = Nock.UI.InverseAutoPhase
ok(type(phase) == "function", "Nock.UI.InverseAutoPhase exists")
if phase then
  local f, w = phase(2.0, 2.0, 0.4)
  ok(near(f, 1) and w == false, "just fired: full, cooldown colour")
  f, w = phase(1.2, 2.0, 0.4)
  ok(near(f, 0.5) and w == false, "halfway through the cooldown: half extent")
  f, w = phase(0.4 + 1e-9, 2.0, 0.4)
  ok(f < 1e-6 and w == false, "cooldown ends empty at the wind-up edge")
  f, w = phase(0.4, 2.0, 0.4)
  ok(near(f, 0) and w == true, "wind-up starts empty")
  f, w = phase(0.2, 2.0, 0.4)
  ok(near(f, 0.5) and w == true, "halfway through the wind-up: half extent, wind-up colour")
  f, w = phase(0, 2.0, 0.4)
  ok(near(f, 1) and w == true, "release: full in the wind-up colour")
  f, w = phase(-0.1, 2.0, 0.4)
  ok(near(f, 1) and w == true, "held shot (overrun): stays full")
  f, w = phase(2.5, 2.0, 0.4)
  ok(near(f, 1) and w == false, "remaining > duration clamps to full")
  -- No wind-up to show: one phase, drains to empty at the release.
  f, w = phase(1.0, 2.0, 0)
  ok(near(f, 0.5) and w == false, "no wind-up: plain drain")
  f, w = phase(0, 2.0, 0)
  ok(near(f, 0) and w == false, "no wind-up: empty at the release, never the wind-up colour")
  f, w = phase(1.0, 2.0, nil)
  ok(near(f, 0.5) and w == false, "nil wind-up reads as none")
  -- A wind-up as long as the cycle (or longer) is all wind-up.
  f, w = phase(1.0, 2.0, 3.0)
  ok(near(f, 0.5) and w == true, "wind-up >= duration clamps to the cycle")
  -- Nothing to draw.
  f, w = phase(1.0, 0, 0.4)
  ok(f == 0 and w == false, "zero duration -> empty")
  f, w = phase(nil, nil, nil)
  ok(f == 0 and w == false, "nil input -> empty")
end

--------------------------------------------------------------------------------
-- §3 Nock.UI.AutoAxisFrac(dir, sd, T, windup): the fraction to hand
-- ReactAxisPoint for a threshold T seconds before the release. Inverse puts
-- it where the draining edge is at remaining == T; a threshold inside the
-- wind-up has no place on that axis (nil).
--------------------------------------------------------------------------------
local axis = Nock.UI.AutoAxisFrac
ok(type(axis) == "function", "Nock.UI.AutoAxisFrac exists")
if axis then
  ok(near(axis("converge", 2.0, 0.5, 0.4), 0.75), "converge: (sd - T) / sd")
  ok(near(axis("ltr", 2.0, 0.5, 0.4), 0.75), "ltr: (sd - T) / sd")
  ok(near(axis(nil, 2.0, 0.5, 0.4), 0.75), "nil direction: the converge reading")
  -- inverse: extent at rem == T is (T - w) / (sd - w); measured from the outer
  -- edge that is 1 - extent = (sd - T) / (sd - w).
  ok(near(axis("inverse", 2.0, 1.2, 0.4), 0.5), "inverse: where the draining edge is at T")
  ok(near(axis("inverse", 2.0, 2.0, 0.4), 0), "inverse: T == sd sits on the outer edge")
  ok(axis("inverse", 2.0, 0.4, 0.4) == nil, "inverse: the wind-up edge itself has no mark (centre)")
  ok(axis("inverse", 2.0, 0.2, 0.4) == nil, "inverse: a threshold inside the wind-up has no mark")
  ok(near(axis("inverse", 2.0, 1.0, 0), 0.5), "inverse without a wind-up: plain (sd - T) / sd")
  ok(axis("inverse", 0, 0.5, 0.4) == nil, "zero duration -> nil")
  ok(axis("converge", 0, 0.5, 0.4) == nil, "zero duration -> nil (converge)")
end

-- The projection itself: inverse marks are a mirrored pair like converge's.
do
  local e1, x1, m1, r1 = Nock.UI.ReactAxisPoint(0.5, "converge", 100, 200)
  local e2, x2, m2, r2 = Nock.UI.ReactAxisPoint(0.5, "inverse", 100, 200)
  ok(e1 == e2 and x1 == x2 and m2 == true and r1 == r2, "ReactAxisPoint: inverse projects as a mirrored pair")
end

--------------------------------------------------------------------------------
-- §4 Nock.UI.PaintInverseAuto: both halves at frac of the half width, colour
-- by phase, touched only when the pixel width or the phase changes.
--------------------------------------------------------------------------------
local paint = Nock.UI.PaintInverseAuto
ok(type(paint) == "function", "Nock.UI.PaintInverseAuto exists")
if paint then
  local fillL, fillR = Stub.CreateFrame("Texture"), Stub.CreateFrame("Texture")
  local cache = {}
  local cool, wind = { 1, 0.84, 0, 1 }, { 0.85, 0.10, 0.10, 1 }
  paint(fillL, fillR, cache, 0.5, false, 100, 1, cool, wind)
  ok(fillL._w == 50 and fillR._w == 50, "both halves at frac of the half width")
  ok(fillL._color and fillL._color[2] == 0.84 and fillR._color[2] == 0.84, "cooldown phase: the cooldown colour")
  paint(fillL, fillR, cache, 0.504, false, 100, 1, cool, wind)
  ok(fillL._w == 50, "widths are whole device pixels")
  paint(fillL, fillR, cache, 0.25, true, 100, 1, cool, wind)
  ok(fillL._w == 25 and fillR._w == 25, "wind-up phase width")
  ok(fillL._color[1] == 0.85 and fillR._color[2] == 0.10, "wind-up phase: the wind-up colour")
  paint(fillL, fillR, cache, 0, false, 100, 1, cool, wind)
  ok(fillL._w == 0.01, "empty: the 0.01 floor (a zero width lets the texture size itself)")
  -- Diffed: an untouched frame costs no widget calls.
  local calls = 0
  local realW, realC = fillL.SetWidth, fillL.SetVertexColor
  fillL.SetWidth = function(...) calls = calls + 1; return realW(...) end
  fillL.SetVertexColor = function(...) calls = calls + 1; return realC(...) end
  paint(fillL, fillR, cache, 0, false, 100, 1, cool, wind)
  ok(calls == 0, "same width and phase: nothing re-set")
  -- A wiped cache (ApplyLayout) repaints.
  cache.w, cache.windup = nil, nil
  paint(fillL, fillR, cache, 0, false, 100, 1, cool, wind)
  ok(calls == 2, "wiped cache: width and colour re-applied")
end

print(("inverse_auto_bar: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
