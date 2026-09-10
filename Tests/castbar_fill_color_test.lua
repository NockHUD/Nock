-- Tests/castbar_fill_color_test.lua
-- The cast bars on all three HUDs colour the Auto Shot wind-up apart from a
-- real cast: Nock.CastFillKind tells the two records apart, Nock.CastFillColor
-- picks the profile colour for that kind, and each HUD ships an *AutoShot*
-- colour key defaulting to its cast colour (so nothing changes until set).
-- Run from the repo root: luajit Tests/castbar_fill_color_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

_G.GetTime = function() return 1000 end
_G.unpack = unpack or table.unpack
local Nock = { Constants = {}, state = {}, modules = {} }
function Nock:NewModule(name)
  local m = { name = name }
  function m:RegisterMessage() end
  function m:RegisterEvent() end
  function m:SendMessage() end
  Nock.modules[name] = m
  return m
end
function Nock:GetModule(name) return Nock.modules[name] end
_G.LibStub = setmetatable({}, { __call = function(_, lib, silent)
  if lib == "AceAddon-3.0" then return { GetAddon = function() return Nock end } end
  if silent then return nil end
  return {}
end })

dofile("Core/Constants.lua")
dofile("Config/Defaults.lua")
dofile("Core/State.lua")

local D = Nock.Defaults.profile
local function eqColor(a, b)
  return type(a) == "table" and type(b) == "table"
     and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

-- §1 Kind of record.
ok(Nock.CastFillKind(nil) == nil, "nil record -> nil kind")
ok(Nock.CastFillKind({ auto = true }) == "auto", "wind-up record -> auto")
ok(Nock.CastFillKind({ name = "Steady Shot" }) == "cast", "cast record -> cast")
ok(Nock.CastFillKind({ isChannel = true }) == "cast", "channel record -> cast")

-- §2 Colour pick: kind selects the key; a missing/malformed key falls back to
-- the reference; the auto key never leaks into a cast and vice versa.
local ref = { 0.1, 0.2, 0.3, 1 }
local p = {
  castBarColor         = { 1, 0, 0, 1 },
  castBarAutoShotColor = { 0, 1, 0, 0.5 },
}
ok(eqColor(Nock.CastFillColor(p, "cast", "castBarColor", "castBarAutoShotColor", ref), p.castBarColor),
   "cast kind reads the cast key")
ok(eqColor(Nock.CastFillColor(p, "auto", "castBarColor", "castBarAutoShotColor", ref), p.castBarAutoShotColor),
   "auto kind reads the auto key")
ok(Nock.CastFillColor({}, "auto", "castBarColor", "castBarAutoShotColor", ref) == ref,
   "missing auto key -> reference")
ok(Nock.CastFillColor({ castBarAutoShotColor = "red" }, "auto", "castBarColor", "castBarAutoShotColor", ref) == ref,
   "malformed colour -> reference")
ok(Nock.CastFillColor({}, nil, "castBarColor", "castBarAutoShotColor", ref) == ref,
   "no kind -> reference")

-- §3 Defaults: one auto colour per HUD, equal to that HUD's cast colour.
ok(eqColor(D.castBarAutoShotColor, D.castBarColor), "classic default auto colour == cast colour")
ok(eqColor(D.reactColorAutoShotFill, D.reactColorCastFill), "react default auto colour == cast colour")
ok(eqColor(D.fluffyColorAutoShotFill, D.fluffyColorCastFill), "fluffy default auto colour == cast colour")
ok(D.castBarAutoShotColor ~= D.castBarColor and D.reactColorAutoShotFill ~= D.reactColorCastFill
   and D.fluffyColorAutoShotFill ~= D.fluffyColorCastFill,
   "defaults are separate tables (a shared table would alias the two colours)")

print(("castbar_fill_color_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
