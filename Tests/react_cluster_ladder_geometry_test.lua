-- Tests/react_cluster_ladder_geometry_test.lua
-- UI/Frame_ReactCluster.lua Geometry: on Forever the range row is the ladder
-- (bar + optional yard scale) and the position strip is gone; TBC unchanged.

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local profile = {}
local mod
local Nock = {
  db = { profile = profile },
  Constants = setmetatable({}, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }),
  UI = {
    ResolveReactBarOrder = function() return { "auto", "melee", "range", "mana" } end,
    RangeLadder = {},
    SWING_CLOSE = { ease = 0.06, hold = 0.04, catch = 0.30 },
  },
}
function Nock:NewModule() mod = {}; function mod:RegisterMessage() end; return mod end
function Nock:GetModule() return {} end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("UI/Frame_ReactCluster.lua")
local G = mod.Geometry

-- Forever, scale on (default).
Nock.Flavor = { forever = true }
local fake = { ladder = {} }
local g = G(fake)
ok(g.showLadder == true and g.showStrip == false and g.showRange == false, "forever: ladder shown, strip and fill bar not")
ok(g.hLadder == 12, "forever: the ladder is the range row's height, labels inside it, got " .. tostring(g.hLadder))
local withLabels = g.total
profile.reactRangeLabels = false
g = G(fake)
ok(g.hLadder == 12 and g.total == withLabels, "labels off: same height (nothing hangs under the bar)")
profile.reactRangeLabels = nil
-- Range bar switched off: no ladder, no height.
profile.reactShowRangeBar = false
g = G(fake)
ok(g.showLadder == false and (g.hLadder or 0) == 0, "range bar off: no ladder")
profile.reactShowRangeBar = nil

-- TBC: no ladder; the strip is still opt-in under the fill bar.
Nock.Flavor = nil
g = G({})
ok(not g.showLadder and g.showRange == true and g.showStrip == false, "tbc: fill bar, no strip by default, no ladder")
profile.reactRangeStrip = true
g = G({})
ok(g.showStrip == true and not g.showLadder, "tbc: opt-in strip still works")
profile.reactRangeStrip = nil

print(("react_cluster_ladder_geometry: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
