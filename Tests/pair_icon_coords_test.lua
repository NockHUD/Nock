-- Tests/pair_icon_coords_test.lua
-- Nock.UI.PairIconCoords: the crop for each half of a glued pair tile shows
-- the middle of its icon at the half's aspect ratio (pure; Widgets.lua).
-- Run from the repo root: luajit Tests/pair_icon_coords_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

-- Same headless surface as Tests/active_glow_test.lua: Widgets.lua only needs
-- the addon table, LibStub's AceAddon and a frame that can register events.
local Nock = {
  db = { profile = {} },
  Constants = setmetatable({}, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }),
}
local libs = { ["AceAddon-3.0"] = { GetAddon = function() return Nock end } }
_G.LibStub = setmetatable({}, { __call = function(_, name, silent)
  local lib = libs[name]
  if not lib and not silent then error("harness: missing lib " .. name) end
  return lib
end })
_G.CreateFrame = function()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
dofile("UI/Widgets.lua")

local P = Nock.UI.PairIconCoords
ok(type(P) == "function", "PairIconCoords exists")

-- Square halves (tile 64x32): full 0.42 crop both ways.
local l, r = P(64, 32)
ok(near(l[1], 0.08) and near(l[2], 0.92) and near(l[3], 0.08) and near(l[4], 0.92), "square half: standard crop")
ok(near(r[1], l[1]) and near(r[4], l[4]), "both halves use the same crop")

-- Wide halves (tile 96x32, half 48x32): full width, vertical span shrinks by 32/48.
l = P(96, 32)
ok(near(l[1], 0.08) and near(l[2], 0.92), "wide half: full horizontal crop")
ok(near(l[3], 0.5 - 0.42 * (32 / 48)) and near(l[4], 0.5 + 0.42 * (32 / 48)), "wide half: vertical span by aspect")

-- Tall halves (tile 32x32, half 16x32): full height, horizontal span shrinks by 16/32.
l = P(32, 32)
ok(near(l[3], 0.08) and near(l[4], 0.92), "tall half: full vertical crop")
ok(near(l[1], 0.5 - 0.21) and near(l[2], 0.5 + 0.21), "tall half: horizontal span by aspect")

print(("pair_icon_coords: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
