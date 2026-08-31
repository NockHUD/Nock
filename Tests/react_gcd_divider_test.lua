-- Tests/react_gcd_divider_test.lua
-- Standalone LuaJIT tests for the two pure helpers behind the React auto bar's
-- GCD divider: Nock.UI.ReactGcdFrac (state.gcd -> 0..1 progress, or nil when no
-- GCD is running) and Nock.UI.ReactAxisPoint (progress -> anchor edge + signed
-- offset, per fill direction). ReactAxisPoint is the SINGLE projection used by
-- both the clip/wind-up marks and the GCD divider -- the clip-threshold lesson
-- is that this formula drifts the moment it is written twice.
-- Run from the repo root: luajit Tests/react_gcd_divider_test.lua
-- (Harness cloned from react_order_test.lua.)

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = {
  db = { profile = {} },
  Constants = setmetatable({}, {
    __index = function(t, k)
      local v = {}
      rawset(t, k, v)
      return v
    end,
  }),
}

local libs = { ["AceAddon-3.0"] = { GetAddon = function() return Nock end } }
_G.LibStub = setmetatable({}, {
  __call = function(_, name, silent)
    local lib = libs[name]
    if not lib and not silent then error("harness: missing lib " .. name) end
    return lib
  end,
})
_G.CreateFrame = function()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end

dofile("UI/Widgets.lua")

local frac  = Nock.UI.ReactGcdFrac
local point = Nock.UI.ReactAxisPoint
ok(type(frac) == "function",  "Nock.UI.ReactGcdFrac exists")
ok(type(point) == "function", "Nock.UI.ReactAxisPoint exists")

local function near(a, b) return a and math.abs(a - b) < 1e-6 end

--------------------------------------------------------------------------------
-- ReactGcdFrac: nil means "draw nothing". Anything that isn't a live GCD with a
-- positive duration must take that path -- a divide by a zero duration would
-- otherwise put the divider at inf/nan, and a stale gcd table (Core zeroes it
-- when the reading isn't a GCD) must not leave a line parked on the bar.
--------------------------------------------------------------------------------
ok(frac(nil) == nil, "nil gcd state -> nil")
ok(frac({}) == nil, "empty gcd table -> nil")
ok(frac({ active = false, duration = 1.5, remaining = 0.5 }) == nil,
   "inactive gcd -> nil even with a live-looking duration")
ok(frac({ active = true, duration = 0, remaining = 0 }) == nil,
   "zero duration -> nil (no divide by zero)")
ok(frac({ active = true, duration = -1, remaining = 0.5 }) == nil,
   "negative duration -> nil")

--------------------------------------------------------------------------------
-- Live GCD: progress runs 0 at the press to 1 at expiry, matching the gold
-- fill's p01 convention (0 at swing start, 1 at the shot). So the divider
-- starts at the OUTER edge and closes on the centre.
--------------------------------------------------------------------------------
ok(near(frac({ active = true, duration = 1.5, remaining = 1.5 }), 0),
   "just pressed -> 0 (divider at the outer edge)")
ok(near(frac({ active = true, duration = 1.5, remaining = 0.75 }), 0.5),
   "half elapsed -> 0.5")
ok(near(frac({ active = true, duration = 1.5, remaining = 0 }), 1),
   "expired -> 1 (divider at the centre)")
ok(near(frac({ active = true, duration = 1.0, remaining = 0.9 }), 0.1),
   "haste-scaled duration is honored, not a hardcoded 1.5")

-- Clamped both ways: remaining is derived from GetTime() against a server
-- timestamp, so it can land just outside the window on either side.
ok(near(frac({ active = true, duration = 1.5, remaining = 2.0 }), 0),
   "remaining > duration clamps to 0")
ok(near(frac({ active = true, duration = 1.5, remaining = -0.2 }), 1),
   "negative remaining clamps to 1")

--------------------------------------------------------------------------------
-- ReactAxisPoint: converge. Mirrored pair -- the caller anchors the second
-- texture at "RIGHT" with the negated offset, so `mirrored` is true and the
-- offset is measured from the LEFT edge across the HALF width.
--------------------------------------------------------------------------------
local HALF, INNER = 100, 200

local edge, x, mirrored = point(0, "converge", HALF, INNER)
ok(edge == "LEFT" and near(x, 1) and mirrored == true,
   "converge at 0: 1px inside the LEFT edge, mirrored")
edge, x, mirrored = point(0.5, "converge", HALF, INNER)
ok(edge == "LEFT" and near(x, 51) and mirrored == true,
   "converge at 0.5: half the half-width in")
edge, x, mirrored = point(1, "converge", HALF, INNER)
ok(edge == "LEFT" and near(x, 101) and mirrored == true,
   "converge at 1: the halves meet at the centre")

--------------------------------------------------------------------------------
-- ReactAxisPoint: directional. One mark only (mirrored false), projected across
-- the FULL inner width from the fill's own origin edge -- rtl returns a
-- negative offset because it anchors on RIGHT and grows leftward.
--------------------------------------------------------------------------------
edge, x, mirrored = point(0, "ltr", HALF, INNER)
ok(edge == "LEFT" and near(x, 1) and mirrored == false,
   "ltr at 0: 1px inside the LEFT edge, single mark")
edge, x, mirrored = point(0.5, "ltr", HALF, INNER)
ok(edge == "LEFT" and near(x, 101) and mirrored == false,
   "ltr at 0.5: half the FULL inner width (not the half-width)")
edge, x, mirrored = point(1, "ltr", HALF, INNER)
ok(edge == "LEFT" and near(x, 201) and mirrored == false, "ltr at 1: far edge")

edge, x, mirrored = point(0, "rtl", HALF, INNER)
ok(edge == "RIGHT" and near(x, -1) and mirrored == false,
   "rtl at 0: 1px inside the RIGHT edge, negative offset")
edge, x, mirrored = point(0.5, "rtl", HALF, INNER)
ok(edge == "RIGHT" and near(x, -101) and mirrored == false, "rtl at 0.5: mirrored of ltr")
edge, x, mirrored = point(1, "rtl", HALF, INNER)
ok(edge == "RIGHT" and near(x, -201) and mirrored == false, "rtl at 1: far edge")

--------------------------------------------------------------------------------
-- Damaged input. An unknown/absent direction falls back to converge, which is
-- the reference look and the profile default -- never to nothing.
--------------------------------------------------------------------------------
edge, x, mirrored = point(0.5, nil, HALF, INNER)
ok(edge == "LEFT" and near(x, 51) and mirrored == true, "nil direction -> converge")
edge, x, mirrored = point(0.5, "sideways", HALF, INNER)
ok(edge == "LEFT" and near(x, 51) and mirrored == true, "unknown direction -> converge")

-- Fractions outside 0..1 are clamped here too: ReactAxisPoint is shared with the
-- clip marks, whose callers clamp a threshold longer than the cycle to the
-- cycle. A mark off the end of the bar reads as "no risk", which is a lie.
edge, x = point(-1, "converge", HALF, INNER)
ok(near(x, 1), "fraction below 0 clamps to the origin edge")
edge, x = point(2, "converge", HALF, INNER)
ok(near(x, 101), "fraction above 1 clamps to the centre")

-- Zero-width bar (pre-layout / hidden): must not error, and collapses to the
-- 1px inset rather than producing nan.
edge, x = point(0.5, "converge", 0, 0)
ok(near(x, 1), "zero half-width still yields the 1px inset")

--------------------------------------------------------------------------------
-- Device-pixel snapping. Widths mean DEVICE pixels and are converted through
-- the physical pixels-per-unit (PixelScale = effectiveScale x physH/768 --
-- the probe-proven client conversion); positions are snapped so the quad's
-- edges land on device boundaries instead of smearing across two columns at
-- half brightness. The S below is an opaque conversion factor to the pure
-- math -- the assertions are round-trip properties, not monitor claims.
--------------------------------------------------------------------------------
local dw   = Nock.UI.DeviceWidth
local snap = Nock.UI.PixelSnapCenter
ok(type(dw) == "function",   "Nock.UI.DeviceWidth exists")
ok(type(snap) == "function", "Nock.UI.PixelSnapCenter exists")

local S = 0.5333333  -- the reported UI scale

-- N device px -> N/scale logical units.
ok(near(dw(1, 1), 1), "at scale 1, 1 device px is 1 logical px")
ok(near(dw(2, 1), 2), "at scale 1, 2 device px is 2 logical px")
ok(math.abs(dw(1, S) - 1.875) < 0.001, "at scale 0.5333, 1 device px is ~1.875 logical")
ok(math.abs(dw(2, S) - 3.750) < 0.001, "at scale 0.5333, 2 device px is ~3.75 logical")
-- Round-trip: whatever we hand SetWidth must come back as exactly N device px.
for _, n in ipairs({ 1, 2, 3, 8 }) do
  ok(math.abs(dw(n, S) * S - n) < 1e-9, "device width round-trips at n=" .. n)
end
-- Degenerate scale must not divide by zero or produce nan.
ok(near(dw(2, 0), 2), "zero scale falls back to logical units")
ok(near(dw(2, nil), 2), "nil scale falls back to logical units")
ok(dw(0, S) > 0, "a zero width still yields something drawable")

-- Snapping. An EVEN device width wants its centre on a device boundary; an ODD
-- one wants it on a half-pixel, so the quad covers whole columns either way.
-- Verified by checking the resulting EDGES are integers in device space.
local function edgesWhole(x, scale, n)
  local left  = x * scale - n / 2
  local right = x * scale + n / 2
  return math.abs(left - math.floor(left + 0.5)) < 1e-9
     and math.abs(right - math.floor(right + 0.5)) < 1e-9
end
for _, n in ipairs({ 1, 2, 3, 4 }) do
  for _, raw in ipairs({ 0, 0.3, 7.77, 37.333, 91.8312, 108.5 }) do
    local x = snap(raw, S, n)
    ok(edgesWhole(x, S, n),
       string.format("snap(%.4f, 0.5333, %d): edges land on device pixels", raw, n))
  end
end
-- Snapping moves a coordinate by less than one device pixel -- it must not
-- relocate a mark, only sharpen it.
for _, raw in ipairs({ 0.3, 7.77, 37.333, 91.8312 }) do
  ok(math.abs(snap(raw, S, 2) - raw) * S <= 0.5 + 1e-9,
     string.format("snap(%.4f) moves less than half a device pixel", raw))
end
-- No scale, no snapping: the value passes through untouched.
ok(near(snap(37.333, nil, 2), 37.333), "nil scale leaves the coordinate alone")
ok(near(snap(37.333, 0, 2), 37.333), "zero scale leaves the coordinate alone")

--------------------------------------------------------------------------------
-- ReactAxisPoint with snapping: same projection, then snapped. Without the
-- optional scale it must behave EXACTLY as before (every assertion above the
-- snapping section still passes, which is the real guard).
--------------------------------------------------------------------------------
local e2, x2 = point(0.5, "converge", HALF, INNER, S, 2)
ok(edgesWhole(x2, S, 2) and e2 == "LEFT",
   "converge + scale: the placed mark lands on device pixels")
local e3, x3, m3 = point(0.5, "rtl", HALF, INNER, S, 1)
ok(e3 == "RIGHT" and m3 == false and edgesWhole(-x3, S, 1),
   "rtl + scale: negative offset still lands on device pixels")
local _, xUn = point(0.5, "converge", HALF, INNER)
ok(near(xUn, 51), "omitting the scale keeps the old unsnapped behaviour")

--------------------------------------------------------------------------------
-- Absolute snapping. The pixel grid lives in SCREEN space: the bar's own edges
-- sit at arbitrary sub-pixel positions, and the left and right edges carry
-- DIFFERENT fractional phases, so an offset snapped relative to an unsnapped
-- edge still rasterises 1px on one side and 2px on the other (the mirrored
-- mark report, 2026-08-31). Passing the edge's physical position (originPx /
-- leftPx / rightPx) makes the quad's ABSOLUTE edges land on whole pixels.
--------------------------------------------------------------------------------
local function absEdgesWhole(off, scale, n, originPx)
  local c = off * scale + originPx
  local left, right = c - n / 2, c + n / 2
  return math.abs(left - math.floor(left + 0.5)) < 1e-9
     and math.abs(right - math.floor(right + 0.5)) < 1e-9
end
for _, o in ipairs({ 0.37, 12.5, 991.13 }) do
  for _, n in ipairs({ 1, 2, 3 }) do
    local x = snap(7.77, S, n, o)
    ok(absEdgesWhole(x, S, n, o),
       string.format("snap with origin %.2f, n=%d: absolute edges land on pixels", o, n))
    ok(math.abs(x - 7.77) * S <= 0.5 + 1e-9,
       string.format("origin %.2f, n=%d: still moves less than half a device px", o, n))
  end
end

-- Mirrored converge with two different edge phases: BOTH halves land on the
-- grid, each measured against its own edge. The right half is applied as
-- SetPoint("CENTER", bar, "RIGHT", -xR), i.e. its centre is rightPx - xR*S.
local LPX, RPX = 100.37, 100.37 + 191.62
local e4, x4, m4, xR4 = point(0.5, "converge", HALF, INNER, S, 2, LPX, RPX)
ok(e4 == "LEFT" and m4 == true, "converge with phases still mirrors")
ok(absEdgesWhole(x4, S, 2, LPX),  "left half lands on the grid against the left edge")
ok(absEdgesWhole(-xR4, S, 2, RPX), "right half lands on the grid against the right edge")
-- Without phases the 4th return equals the shared offset (old callers safe).
local _, x5, _, xR5 = point(0.5, "converge", HALF, INNER, S, 2)
ok(near(x5, xR5), "phase-less converge keeps one shared offset")
-- rtl with a right phase: the negative offset lands on the grid absolutely.
local e6, x6 = point(0.5, "rtl", HALF, INNER, S, 1, LPX, RPX)
ok(e6 == "RIGHT" and absEdgesWhole(x6, S, 1, RPX),
   "rtl with phase: absolute snap against the right edge")
-- ltr with a left phase.
local e7, x7 = point(0.5, "ltr", HALF, INNER, S, 2, LPX, RPX)
ok(e7 == "LEFT" and absEdgesWhole(x7, S, 2, LPX),
   "ltr with phase: absolute snap against the left edge")

--------------------------------------------------------------------------------
-- PixelScale = effectiveScale x physicalHeight/768 (probe-proven client
-- conversion, see Skin.PixelsPerUnit). Headless without GetPhysicalScreenSize
-- it falls back to the bare effective scale.
--------------------------------------------------------------------------------
local fakeFrame = { GetEffectiveScale = function() return 0.5333333 end }
ok(math.abs(Nock.UI.PixelScale(fakeFrame) - 0.5333333) < 1e-6,
   "no physical-size API: bare effective scale")
_G.GetPhysicalScreenSize = function() return 2560, 1440 end
ok(math.abs(Nock.UI.PixelScale(fakeFrame) - 1.0) < 1e-3,
   "1440p at the 768-line default scale: one unit is one physical pixel")
_G.GetPhysicalScreenSize = function() return 1920, 1080 end
ok(math.abs(Nock.UI.PixelScale(fakeFrame) - 0.75) < 1e-3,
   "1080p at the same scale: 0.75 physical px per unit")
_G.GetPhysicalScreenSize = nil

print(string.format("react_gcd_divider: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
