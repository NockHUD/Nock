-- Tests/cooldown_tiles_test.lua
-- UI/Frame_CooldownTiles.lua: every grid row keeps a "+" even when the view collapsed it.
-- Run from the repo root: luajit Tests/cooldown_tiles_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local Nock = { UI = {} }
_G.LibStub = function(name)
  if name == "AceEvent-3.0" then return { Embed = function() end } end
  return { GetAddon = function() return Nock end }
end
dofile("UI/Frame_CooldownTiles.lua")
local T = Nock.CooldownTiles

local geom = { { index = 1, y = 0, h = 32 }, { index = 2, y = 31, h = 24 } }
local s = T.PlusSlots(geom, 2)
ok(#s == 2 and s[1].row == 1 and s[1].y == 0 and s[2].row == 2 and s[2].y == 31, "both rows present")

s = T.PlusSlots({ { index = 1, y = 0, h = 32 } }, 2)
ok(#s == 2 and s[2].row == 2 and s[2].y == 36 and s[2].h == 24, "an emptied row 2 gets a + below row 1")

s = T.PlusSlots({}, 2)
ok(#s == 2 and s[1].y == 0 and s[2].y == 32, "an empty grid still offers both rows")

print(("cooldown_tiles: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
