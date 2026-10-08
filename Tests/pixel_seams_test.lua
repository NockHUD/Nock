-- Tests/pixel_seams_test.lua
-- Nock.UI.SeamPx / EvenPx / SeamSplit / PixelInset (UI/Widgets.lua): shared 1px seams laid out in whole device pixels.
-- Run from the repo root: luajit Tests/pixel_seams_test.lua
--
-- The bug these guard: tiles and bars overlapped by 1 UNIT with each edge
-- rounded on its own, so at UI scales off 1 px/unit the overlap came out 0-3
-- px. Sibling frames draw layer by layer, so an overlap of 2 hid both borders
-- and ate a pixel of the tile ("the bottom row clips the top row").

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
local UI = Nock.UI

-- Pixels per unit seen in the wild (UI scale x screen height / 768):
-- 1440p at 0.5333 (1.0), 1080p at 0.64 / 0.71 / 1.0, 1440p at 0.64 / 0.8 /
-- 1.0, 4K at 0.8, and the reporter's measured 1.335.
local SCALES = { 1.0, 0.9, 0.998, 1.40625, 1.2, 1.5, 1.875, 2.25, 1.335 }

-- 1. SeamPx: whole pixels, at least 1, identity at 1 px/unit
ok(UI.SeamPx(32, 1) == 32, "SeamPx at 1 px/unit is the unit count")
ok(UI.SeamPx(32, 1.335) == 43, "SeamPx rounds to the nearest pixel (32 u at 1.335 = 43 px)")
ok(UI.SeamPx(0.2, 1) == 1, "SeamPx floors at one pixel")
ok(UI.SeamPx(32, nil) == 32, "SeamPx without a scale = 1 px/unit")

-- 2. EvenPx: rounds an odd count up
ok(UI.EvenPx(220, 1) == 220, "EvenPx keeps an even count")
ok(UI.EvenPx(220, 1.335) % 2 == 0 and UI.EvenPx(220, 1.335) >= UI.SeamPx(220, 1.335), "EvenPx rounds an odd count up")

-- 3. SeamSplit: n tiles span exactly [0, total), neighbours overlap by exactly
--    one pixel, widths differ by at most one
local allGood = true
for total = 20, 700, 7 do
  for n = 1, 10 do
    local minW, maxW = math.huge, 0
    local prevR
    for i = 1, n do
      local l, w = UI.SeamSplit(total, n, i)
      if l ~= math.floor(l) or w ~= math.floor(w) then allGood = false end
      if i == 1 and l ~= 0 then allGood = false end
      if i == n and l + w ~= total then allGood = false end
      if prevR and prevR - l ~= 1 then allGood = false end
      prevR = l + w
      if w < minW then minW = w end
      if w > maxW then maxW = w end
    end
    if maxW - minW > 1 then allGood = false end
  end
end
ok(allGood, "SeamSplit: whole pixels, exact outer edges, 1 px overlaps, widths within 1 px")

-- 4. The React grid at every scale: rows and tiles laid out with the helpers
--    overlap by exactly one device pixel (the old 1-unit maths gave 0-3).
local function gridSeams(ds)
  local wPx = UI.EvenPx(220, ds)
  local bad = {}
  -- stretch row (6 tiles) and fixed row (6 tiles of 32 x 24 units)
  local r1h, r2h = UI.SeamPx(32, ds), UI.SeamPx(24, ds)
  local r2y = r1h - 1
  if r1h - r2y ~= 1 then bad[#bad + 1] = "rows" end
  local prev
  for i = 1, 6 do
    local l, w = UI.SeamSplit(wPx, 6, i)
    if prev and prev - l ~= 1 then bad[#bad + 1] = "stretch col " .. i end
    prev = l + w
  end
  local t = UI.SeamPx(32, ds)
  local x0 = math.floor((wPx - (6 * t - 5)) / 2)
  prev = nil
  for i = 1, 6 do
    local l = x0 + (i - 1) * (t - 1)
    if prev and prev - l ~= 1 then bad[#bad + 1] = "fixed col " .. i end
    prev = l + t
  end
  return bad
end
for _, ds in ipairs(SCALES) do
  local bad = gridSeams(ds)
  ok(#bad == 0, ("grid seams are 1 px at %.3f px/unit (%s)"):format(ds, table.concat(bad, ", ")))
end

-- 5. The reporter's case reproduced with the OLD maths: a 2 px row overlap
local function oldRowOverlap(ds)
  local function r(v) return math.floor(v * ds + 0.5) end
  return r(32) - r(31)
end
ok(oldRowOverlap(1.335) == 2, "old 1-unit seam overlapped 2 px at 1.335 px/unit (the report)")

-- 6. PixelInset: one device pixel in, and re-fit with the backdrop on a
--    scale change
local function region()
  local r = { pts = {} }
  function r:ClearAllPoints() self.pts = {} end
  function r:SetPoint(p, rel, rp, x, y) self.pts[p] = { x = x, y = y } end
  return r
end
local slot = { _scale = 2, _bg = { 0, 0, 0, 1 }, _border = { 0, 0, 0, 1 } }
function slot:GetEffectiveScale() return self._scale end
function slot:SetBackdrop(t) self._bd = t end
function slot:SetBackdropColor(...) self._bg = { ... } end
function slot:SetBackdropBorderColor(...) self._border = { ... } end
function slot:GetBackdropColor() return unpack(self._bg) end
function slot:GetBackdropBorderColor() return unpack(self._border) end
local icon = region()
UI.ApplyBackdrop(slot, { 0.1, 0.1, 0.1, 1 }, { 0, 0, 0, 1 })
UI.PixelInset(icon, slot)
ok(near(icon.pts.TOPLEFT.x, 0.5) and near(icon.pts.TOPLEFT.y, -0.5)
   and near(icon.pts.BOTTOMRIGHT.x, -0.5) and near(icon.pts.BOTTOMRIGHT.y, 0.5),
   "PixelInset insets by one device pixel (0.5 units at 2 px/unit)")
ok(near(slot._bd.edgeSize, icon.pts.TOPLEFT.x), "inset equals the backdrop edge")
slot._scale = 1
UI.RefreshPixelBackdrops()
ok(near(icon.pts.TOPLEFT.x, 1) and near(slot._bd.edgeSize, 1), "a scale change re-fits the inset with the edge")

-- 7. LayoutIconBarRow / IconBarFillWidth (the React cast bar and the EotB
--    pulse row stacked on it): every seam one device pixel at any scale, the
--    height whole pixels, and a full fill meets the right border exactly.
local function frame(scale)
  local f = region()
  function f:GetEffectiveScale() return scale end
  function f:SetHeight(h) self.h = h end
  function f:SetSize(w, h) self.w, self.h = w, h end
  return f
end
for _, ds in ipairs(SCALES) do
  local below = frame(ds)
  local r = { panel = frame(ds), iconF = frame(ds), icon = region(), bar = frame(ds), fill = region(), lag = region() }
  local e, dev = UI.LayoutIconBarRow(r, below, 16)
  local px = function(v) return v * ds end
  local whole = function(v) return math.abs(px(v) - math.floor(px(v) + 0.5)) < 1e-6 end
  local good = near(e, 1 / ds) and dev == ds
    and near(r.panel.pts.BOTTOMLEFT.y, -e) and near(r.panel.pts.BOTTOMRIGHT.y, -e)
    and whole(r.panel.h) and near(r.iconF.w, r.panel.h) and near(r.iconF.h, r.panel.h)
    and near(r.bar.pts.TOPLEFT.x, -e)
    and near(r.icon.pts.TOPLEFT.x, e) and near(r.icon.pts.BOTTOMRIGHT.x, -e)
    and near(r.fill.pts.TOPLEFT.x, e) and near(r.fill.pts.BOTTOMLEFT.y, e)
    and near(r.lag.pts.TOPRIGHT.x, -e)
  ok(good, ("icon-bar row: one-pixel seams and whole-pixel height at %.3f px/unit"):format(ds))
  -- A bar 200 device px wide: the full fill is the 198 px between the borders.
  local barW = 200 / ds
  local full = UI.IconBarFillWidth(barW, 1, e, dev)
  ok(math.abs(px(full) - 198) < 1e-6, ("full fill meets the right border at %.3f px/unit"):format(ds))
  local half = UI.IconBarFillWidth(barW, 0.5, e, dev)
  ok(whole(half) and math.abs(px(half) - 99) < 1e-6, ("half fill on a whole pixel at %.3f px/unit"):format(ds))
end
ok(UI.IconBarFillWidth(100, 0, 1, 1) == 0.01 and UI.IconBarFillWidth(100, 2, 1, 1) == 98, "fill clamps to empty and full")

print(("pixel_seams_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
