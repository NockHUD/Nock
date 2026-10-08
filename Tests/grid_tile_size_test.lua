-- Tests/grid_tile_size_test.lua
-- The cooldown grids' tile size (UI/Frame_ReactCooldowns.lua RowsGeometry,
-- UI/Frame_FluffyCooldowns.lua): per-row height and tile width from the
-- profile, the top row filling the HUD width unless told otherwise, a fixed
-- width that would spill past the HUD falling back to filling it, and no
-- setting at all giving today's layout.
-- Run from the repo root: luajit Tests/grid_tile_size_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local p = { reactWidth = 220 }
local mod = {
  GetEntry = function(_, key) return { key = key } end,
  IsEntryAvailable = function() return true end,
}
local Nock = {
  Constants = { REACT_CD_ROWS = {
    { h = 32, stretch = true, keys = { "A", "B", "C", "D" } },
    { h = 24, w = 32, keys = { "E", "F" } },
    { h = 24, w = 32, keys = { "G" } },
  } },
  db = { profile = p },
  UI = {
    PixelScale = function() return 1 end,
    SeamPx = function(v) return math.floor(v + 0.5) end,
    EvenPx = function(v) return 2 * math.floor(v / 2 + 0.5) end,
  },
}
local views = {}
function Nock:NewModule(name) local v = { name = name }; views[name] = v; return v end
function Nock:GetModule(name) if name == "Cooldowns" then return mod end end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("UI/Frame_ReactCooldowns.lua")
local R = views.ReactCooldownsView
R.frame = {}

-- No settings: today's layout, untouched.
local rows, w, h = R:RowsGeometry()
ok(#rows == 3 and w == 220, "three rows over the React width")
ok(rows[1].stretch == true and rows[1].h == 32 and math.abs(rows[1].w - (220 + 3) / 4) < 1e-9, "top row: 32 high, filling the width")
ok(rows[2].stretch == false and rows[2].h == 24 and rows[2].w == 32, "second row: 32 x 24 tiles")
ok(rows[3].h == 24 and rows[3].w == 32, "third row (TBC): the small-row size")
ok(h == 32 + 24 + 24 - 2, "height: the rows, sharing their seams")

-- Heights.
p.gridRow1Height, p.gridRow2Height = 40, 30
rows, w, h = R:RowsGeometry()
ok(rows[1].h == 40 and rows[2].h == 30 and rows[3].h == 30, "row heights from the profile; the small-row height covers every row after the first")
ok(rows[2].y == 39 and h == 40 + 30 + 30 - 2, "rows stack on the new heights")
ok(R:ContentHeight() == h, "ContentHeight follows (the HUD lays out on it)")

-- Top row at a fixed tile width.
p.gridRow1Fill, p.gridRow1Width = false, 44
rows = R:RowsGeometry()
ok(rows[1].stretch == false and rows[1].w == 44, "top row: fixed 44-wide tiles, centred")
p.gridRow1Width = nil
rows = R:RowsGeometry()
ok(rows[1].w == 52, "top row fixed with no width set: 1.3 x its height")
-- Too wide for the HUD: 4 x 80 - 3 = 317 > 220, so it fills instead.
p.gridRow1Width = 80
rows = R:RowsGeometry()
ok(rows[1].stretch == true and math.abs(rows[1].w - (220 + 3) / 4) < 1e-9, "a width that would spill past the HUD fills it instead")
p.gridRow1Fill, p.gridRow1Width = nil, nil

-- Small rows' tile width; the fill switch only touches the top row.
p.gridRow2Width = 40
p.gridRow1Fill = true
rows = R:RowsGeometry()
ok(rows[2].w == 40 and rows[3].w == 40 and rows[2].stretch == false, "small-row tile width from the profile")
-- Widths are capped at 96; on a 150-wide HUD two 96s (191) spill, so they fill.
p.gridRow2Width, p.reactWidth = 500, 150
rows = R:RowsGeometry()
ok(rows[2].stretch == true and math.abs(rows[2].w - (150 + 1) / 2) < 1e-9, "small row too wide: fills the HUD width")
p.gridRow2Width, p.reactWidth = nil, 220

-- Out-of-range values are clamped, junk is ignored.
p.gridRow1Height, p.gridRow2Height = 4, "junk"
rows = R:RowsGeometry()
ok(rows[1].h == 16 and rows[2].h == 24, "a height under the floor is clamped; junk falls back to the default")
p.gridRow1Height, p.gridRow2Height = 500, nil
rows = R:RowsGeometry()
ok(rows[1].h == 64, "a height over the ceiling is clamped")
p.gridRow1Height = nil

-- FluffyHUD's single row: its own height key, always filling.
dofile("UI/Frame_FluffyCooldowns.lua")
local F = views.FluffyCooldownsView
F.frame = {}
p.fluffyWidth, p.fluffyCdKeys = 320, { "A", "B" }
rows, w, h = F:RowsGeometry()
ok(rows[1].h == 32 and h == 32, "Fluffy row: 32 high by default")
p.fluffyGridHeight = 26
rows, w, h = F:RowsGeometry()
ok(rows[1].h == 26 and h == 26 and math.abs(rows[1].w - (320 + 1) / 2) < 1e-9, "Fluffy row height from the profile, still filling")
p.fluffyGridHeight = 1
rows = F:RowsGeometry()
ok(rows[1].h == 16, "Fluffy height clamped too")

print(("grid_tile_size: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
