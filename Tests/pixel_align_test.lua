-- Tests/pixel_align_test.lua
-- Nock.UI.PixelAlignOffsets / SetPointSnapped / DeviceRound (UI/Widgets.lua):
-- anchoring a frame so its anchored edges land on whole device pixels, in
-- absolute screen space (the eWS-mark approach, applied to whole frames).
-- Run from the repo root: luajit Tests/pixel_align_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b) return math.abs((a or 0) - (b or 0)) < 1e-6 end

local Nock = {
  db = { profile = {} },
  Constants = setmetatable({}, {
    __index = function(t, k) local v = {}; rawset(t, k, v); return v end,
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

ok(type(Nock.UI.PixelAlignOffsets) == "function", "PixelAlignOffsets exists")
ok(type(Nock.UI.SetPointSnapped) == "function", "SetPointSnapped exists")
ok(type(Nock.UI.DeviceRound) == "function", "DeviceRound exists")

-- A fake frame whose edges follow its single anchor. Scale 1, no
-- GetPhysicalScreenSize in the harness -> 1 unit = 1 device pixel.
local function fake(scale, w, h)
  local f = { _points = {}, _sets = 0, _scale = scale or 1, _w = w or 100, _h = h or 40 }
  function f:GetEffectiveScale() return self._scale end
  function f:ClearAllPoints() self._points = {} end
  function f:SetPoint(point, rel, relPoint, x, y)
    self._points[#self._points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    self._sets = self._sets + 1
    -- the anchor lands the named edge at (x, y) in screen units, rest follows
    local px, py = x, y
    if point:find("LEFT") then self._left = px
    elseif point:find("RIGHT") then self._left = px - self._w
    else self._left = px - self._w / 2 end
    if point:find("TOP") then self._top = py
    elseif point:find("BOTTOM") then self._top = py + self._h
    else self._top = py + self._h / 2 end
  end
  function f:GetLeft() return self._left end
  function f:GetRight() return self._left + self._w end
  function f:GetTop() return self._top end
  function f:GetBottom() return self._top - self._h end
  return f
end

-- 1. an anchor already on the grid: no correction, one SetPoint
local f = fake(1)
Nock.UI.SetPointSnapped(f, "TOPLEFT", nil, "TOPLEFT", 10, -20)
ok(f._sets == 1 and #f._points == 1, "on-grid anchor is not re-set")
ok(near(f:GetTop(), -20) and near(f:GetLeft(), 10), "on-grid anchor untouched")

-- 2. the half-pixel case from the Forever gate (top at 500.5): re-set once,
--    top lands on a whole pixel
f = fake(1)
Nock.UI.SetPointSnapped(f, "TOP", nil, "BOTTOM", 0.25, 500.5)
ok(f._sets == 2 and #f._points == 1, "off-grid anchor is re-set once, single point kept")
ok(near(f:GetTop(), math.floor(f:GetTop() + 0.5)), "TOP edge lands on a whole pixel")
ok(near(f:GetLeft() + f._w / 2, math.floor(f:GetLeft() + f._w / 2 + 0.5)), "centre-x snapped through the LEFT edge when the width is whole")

-- 3. BOTTOM-anchored frames snap their BOTTOM edge (the HUD box, its rows)
f = fake(1, 100, 40.25)
Nock.UI.SetPointSnapped(f, "BOTTOM", nil, "BOTTOM", 0, 100.3)
ok(near(f:GetBottom(), 100), "BOTTOM edge snapped to the nearest pixel")
ok(near(f:GetTop(), 140.25), "the anchored edge is the one snapped, not the far one")

-- 4. a scaled frame: the correction is expressed in the frame's own units
f = fake(2)   -- 1 unit = 2 device px
Nock.UI.SetPointSnapped(f, "TOPLEFT", nil, "TOPLEFT", 10.3, -20.1)
ok(near(f:GetLeft() * 2, math.floor(f:GetLeft() * 2 + 0.5)), "scaled: left edge on a device pixel")
ok(near(f:GetTop() * 2, math.floor(f:GetTop() * 2 + 0.5)), "scaled: top edge on a device pixel")
ok(math.abs(f:GetLeft() - 10.3) < 0.5, "scaled: moved by less than one unit")

-- 5. a frame without geometry (pre-layout / headless) is left alone
local dx, dy = Nock.UI.PixelAlignOffsets({ GetEffectiveScale = function() return 1 end }, "TOPLEFT")
ok(dx == 0 and dy == 0, "no edges -> zero correction")
dx, dy = Nock.UI.PixelAlignOffsets(fake(1), "TOPLEFT")
ok(dx == 0 and dy == 0, "no anchor yet -> zero correction")

-- 6. DeviceRound: a length in units rounded to whole device pixels
ok(near(Nock.UI.DeviceRound(10.3, 1), 10), "DeviceRound at scale 1")
ok(near(Nock.UI.DeviceRound(10.3, 2), 10.5), "DeviceRound at scale 2 (21 px)")
ok(near(Nock.UI.DeviceRound(10.3, nil), 10.3), "DeviceRound without a scale is identity")
ok(near(Nock.UI.DeviceRound(0.2, 1), 0), "DeviceRound rounds a sub-pixel offset to zero")
ok(near(Nock.UI.DeviceRound(0, 2), 0), "DeviceRound keeps zero")

-- 7. backdrops are sized in device pixels and re-fit when the grid moves
local bd = { _scale = 2, _bg = {}, _border = {} }
function bd:GetEffectiveScale() return self._scale end
function bd:SetBackdrop(t) self._bd = t end
function bd:SetBackdropColor(...) self._bg = { ... } end
function bd:SetBackdropBorderColor(...) self._border = { ... } end
function bd:GetBackdropColor() return unpack(self._bg) end
function bd:GetBackdropBorderColor() return unpack(self._border) end
Nock.UI.ApplyBackdrop(bd, { 0.1, 0.2, 0.3, 0.9 }, { 0, 0, 0, 1 })
ok(near(bd._bd.edgeSize, 0.5) and near(bd._bd.insets.left, 0.5), "edge is one device pixel (0.5 units at scale 2)")
ok(Nock.UI.PixelBackdrop(bd) == bd._bd, "one shared table per edge size")
bd:SetBackdropBorderColor(1, 0, 0, 1)   -- a later restyle
bd._scale = 1
Nock.UI.RefreshPixelBackdrops()
ok(near(bd._bd.edgeSize, 1), "refresh re-fits the edge after a scale change")
ok(bd._border[1] == 1 and bd._border[2] == 0, "refresh keeps the CURRENT border colour")
ok(near(bd._bg[1], 0.1) and near(bd._bg[4], 0.9), "refresh keeps the background colour")
local before = bd._bd
Nock.UI.RefreshPixelBackdrops()
ok(bd._bd == before, "no change -> no re-apply")

print(("pixel_align_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
