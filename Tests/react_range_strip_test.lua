-- Tests/react_range_strip_test.lua
-- Nock.UI.ReactRangeStripLook (UI/Widgets.lua): the two-segment position strip under the React range bar
-- reads the probes (in melee / can shoot) the finder still knows during RESYNC; dark without a target.
-- Run from the repo root: luajit Tests/react_range_strip_test.lua
-- (Harness cloned from react_gcd_divider_test.lua.)

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

local look = Nock.UI.ReactRangeStripLook
ok(type(look) == "function", "Nock.UI.ReactRangeStripLook exists")

local function t(exists, zone, inMelee, stale)
  return { exists = exists, alive = exists, friendly = false, rangeState = exists and "SWEET" or nil, rangeZone = zone, inMelee = inMelee, rangeEstimateStale = stale }
end

-- no target: both segments dark, nothing lit
local l = look(t(false))
ok(l.melee == "off" and l.ranged == "off", "no target -> both off")
l = look({ exists = true, alive = true, friendly = true, rangeState = "SWEET", rangeZone = "SWEET", inMelee = true })
ok(l.melee == "off" and l.ranged == "off", "friendly target -> both off")

-- the four readings
l = look(t(true, "TOO_CLOSE", true))
ok(l.melee == "melee" and l.ranged == "off", "in melee, no shot -> melee lit only")
l = look(t(true, "SWEET", true))
ok(l.melee == "melee" and l.ranged == "ranged", "weave ring (melee + shoot) -> both lit")
l = look(t(true, "TOO_FAR", false))
ok(l.melee == "off" and l.ranged == "ranged", "ranged -> ranged lit only")
l = look(t(true, "TOO_CLOSE", false))
ok(l.melee == "dead" and l.ranged == "off", "dead gap (near, no melee, no shot) -> melee segment dead red")
l = look(t(true, "OUT", false))
ok(l.melee == "off" and l.ranged == "off", "out of range -> both off")

-- RESYNC does not change the reading: the probes are live
l = look(t(true, "TOO_FAR", false, true))
ok(l.ranged == "ranged", "resync + can shoot -> ranged still lit")
l = look(t(true, "TOO_CLOSE", true, true))
ok(l.melee == "melee", "resync + in melee -> melee still lit")

print(("react_range_strip_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
