-- Tests/edit_grid_test.lua
-- Standalone LuaJIT tests for the edit-mode grid (UI/EditMode.lua, pure parts):
-- the grid lines a screen gets, the snap delta a dragged frame gets on release
-- (nearest edge-or-centre per axis, or the top-left corner), and the nudge
-- step while snapping. Run from the repo root: luajit Tests/edit_grid_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b) return a and b and math.abs(a - b) < 1e-6 end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.UIParent = Stub.CreateFrame("Frame")
_G.InCombatLockdown = function() return false end
_G.unpack = unpack or table.unpack

local Nock = { Constants = {}, modules = {} }
function Nock:NewModule(name)
  local m = { name = name }
  function m:RegisterMessage() end
  function m:RegisterEvent() end
  function m:ScheduleRepeatingTimer() end
  function m:CancelTimer() end
  Nock.modules[name] = m
  return m
end
function Nock:GetModule(name) return Nock.modules[name] end
function Nock.IsLocked() return true end
Nock.db = { profile = {} }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/Constants.lua")
Nock.UI = { ApplyBackdrop = function() end, GetFont = function() return "font" end }
dofile("UI/EditMode.lua")

--------------------------------------------------------------------------------
-- 1. GridLines: lines every `raster` from the centre outward, centre included
--------------------------------------------------------------------------------
local G = Nock.UI.GridLines
ok(type(G) == "function", "GridLines exists")
local xs, ys = G(100, 60, 20)
-- width 100, centre 50: 50, 30, 10, 70, 90 -> sorted 10 30 50 70 90
ok(#xs == 5 and xs[1] == 10 and xs[3] == 50 and xs[5] == 90, "x lines every 20 from the centre, edges excluded")
ok(#ys == 3 and ys[1] == 10 and ys[2] == 30 and ys[3] == 50, "y lines: 10 30 50 for a 60-high screen")
local xs2 = G(100, 60, 16)
ok(xs2[#xs2] < 100 and xs2[1] > 0, "lines stay inside the screen for a raster that does not divide it")
local has50 = false
for _, x in ipairs(xs2) do if x == 50 then has50 = true end end
ok(has50, "the centre line is always one of them")
local xs3 = G(100, 60, 0)
ok(#xs3 == 0, "raster 0: no lines, no infinite loop")

--------------------------------------------------------------------------------
-- 2. SnapDelta: how far a frame's rect (UIParent units) moves onto the grid
--------------------------------------------------------------------------------
local S = Nock.UI.SnapDelta
ok(type(S) == "function", "SnapDelta exists")
local origin = { x = 50, y = 50 }   -- screen centre for a 100x100 screen
-- Frame 21..41 wide, 33..63 tall, raster 10: left 21 -> 20 (d -1), centre 31 -> 30 (-1),
-- right 41 -> 40 (-1): all tie; nearest picks the first candidate, left -> -1.
local dx, dy = S({ left = 21, right = 41, top = 63, bottom = 33 }, 10, origin, "nearest")
ok(near(dx, -1), "nearest: x moves the tied edge onto the line (" .. tostring(dx) .. ")")
-- vertical: top 63 -> 60 (-3), centre 48 -> 50 (+2), bottom 33 -> 30 (-3): centre wins.
ok(near(dy, 2), "nearest: y picks the centre, the closest of the three (" .. tostring(dy) .. ")")

-- Corner mode: only left/top count.
dx, dy = S({ left = 21, right = 41, top = 63, bottom = 33 }, 10, origin, "corner")
ok(near(dx, -1) and near(dy, -3), "corner: left -> 20 and top -> 60")

-- A frame already on the grid moves nowhere.
dx, dy = S({ left = 20, right = 40, top = 60, bottom = 30 }, 10, origin, "nearest")
ok(near(dx, 0) and near(dy, 0), "already aligned: zero delta")

-- The grid is anchored on the origin, not on 0: origin 55 shifts the lines by 5.
dx = S({ left = 20, right = 40, top = 60, bottom = 30 }, 10, { x = 55, y = 55 }, "corner")
ok(near(dx, 5) or near(dx, -5), "origin offset shifts the lines (" .. tostring(dx) .. ")")

-- Raster 0 / nil rect: no move.
dx, dy = S({ left = 21, right = 41, top = 63, bottom = 33 }, 0, origin, "nearest")
ok(dx == 0 and dy == 0, "raster 0: no snap")
dx, dy = S(nil, 10, origin, "nearest")
ok(dx == 0 and dy == 0, "no rect: no snap")

--------------------------------------------------------------------------------
-- 3. Snap settings resolution and the nudge step under snap
--------------------------------------------------------------------------------
local R = Nock.UI.EditSnapMode
ok(R({}) == "off", "snap mode defaults off")
ok(R({ editGridSnap = "release" }) == "release" and R({ editGridSnap = "drag" }) == "drag", "release / drag pass through")
ok(R({ editGridSnap = "banana" }) == "off", "unknown value reads as off")
ok(R({ editGridSnap = true }) == "release", "a legacy boolean true reads as release")

local N = Nock.UI.EditNudgeStep
ok(N({ editGridSnap = "off", editGridSize = 16 }, false) == 1, "no snap: one unit")
ok(N({ editGridSnap = "off", editGridSize = 16 }, true) == 10, "no snap, shift: ten")
ok(N({ editGridSnap = "release", editGridSize = 16 }, false) == 16, "snap: one raster")
ok(N({ editGridSnap = "release", editGridSize = 16 }, true) == 160, "snap, shift: ten rasters")
ok(N({ editGridSnap = "release" }, false) == 1, "snap with no size stored: falls back to one unit")

print(("edit_grid: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
