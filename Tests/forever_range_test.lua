-- Tests/forever_range_test.lua
-- Forever/RangeFinder.lua: four zones from the checks that stay plain in
-- combat (item 7 yd, Auto Shot usable, interact 10 yd), no ladder, no glide.
-- Run from the repo root: luajit Tests/forever_range_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
_G.GetTime = function() return 100 end
_G.GetRangedHaste = function() return 0 end
local shoot, item7, mid10 = nil, nil, nil
_G.C_Spell = { IsSpellInRange = function(id) if id == 75 then return shoot end return true end }  -- melee spells answer true everywhere (measured)
_G.C_Item = { IsItemInRange = function(id) if id == 8149 then return item7 end end }
_G.CheckInteractDistance = function(unit, idx) if idx == 3 then return mid10 end end
local exists, dead, canAttack = true, false, true
_G.UnitExists = function() return exists end
_G.UnitIsDeadOrGhost = function() return dead end
_G.UnitCanAttack = function() return canAttack end
local Nock = { Flavor = { forever = true, Plain = function(v) if v == "SECRET" then return nil end return v end }, Constants = {} }
local module
function Nock:NewModule(name) module = { name = name, events = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  return module end
function Nock:GetModule() return nil end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/Spells.lua")
dofile("Forever/RangeFinder.lua")
local RF = module
ok(RF and RF.name == "RangeFinder" and RF.refreshInterval == 0.1, "module RangeFinder on the slow lane")
local C = Nock.RangeFinderClassify
ok(select(1, C(true, false, true, true, true, false)) == "MELEE", "melee wins")
ok(select(1, C(false, true, true, true, true, false)) == "SWEET", "can shoot -> SWEET")
ok(select(1, C(false, false, true, true, true, false)) == "CLOSE", "cannot shoot, within 10 yd -> dead zone (CLOSE)")
ok(select(1, C(false, false, false, true, true, false)) == "LONG", "cannot shoot, beyond 10 yd -> far (LONG)")
ok(C(false, true, true, false, true, false) == nil, "no target -> nil")
ok(C(false, true, true, true, false, false) == nil, "dead target -> nil")
ok(C(false, true, true, true, true, true) == nil, "friendly -> nil")
local _, prog = C(true, false, true, true, true, false); ok(prog == 0.5, "melee prog 0.5")
_, prog = C(false, true, true, true, true, false); ok(prog == -0.5, "sweet prog -0.5")
_, prog = C(false, false, true, true, true, false); ok(prog == 0, "dead zone prog 0")
_, prog = C(false, false, false, true, true, false); ok(prog == -1, "far prog -1")

RF:OnEnable()
local st = Nock.state
local t = st.target
-- Measured 2026-09-22 in melee: item true, shoot false, mid true.
item7, shoot, mid10 = true, false, true
RF:Refresh(st)
ok(t.rangeState == "MELEE" and t.inMelee == true and t.rangeZone == "TOO_CLOSE", "published MELEE")
ok(st.ranged.targetInRange == false, "auto bar gate: cannot shoot in melee")
-- At range: item false, shoot true, mid false.
item7, shoot, mid10 = false, true, false
RF:Refresh(st)
ok(t.rangeState == "SWEET" and t.inMelee == false and t.rangeZone == "SWEET", "published SWEET")
ok(st.ranged.targetInRange == true, "auto bar gate: can shoot")
-- Dead zone: item false, shoot false, mid true.
item7, shoot, mid10 = false, false, true
RF:Refresh(st)
ok(t.rangeState == "CLOSE" and t.rangeZone == "OUT", "published dead zone")
-- Far: all false.
item7, shoot, mid10 = false, false, false
RF:Refresh(st)
ok(t.rangeState == "LONG" and t.rangeProg == -1 and t.rangeZone == "OUT", "published far")
-- No target clears, gate goes unknown.
exists = false
RF:Refresh(st)
ok(t.exists == false and t.rangeState == nil and st.ranged.targetInRange == nil, "no target clears and the gate is unknown")
-- Once the client's own swing-range signal has been seen, the finder stops writing the gate.
exists = true; item7, shoot, mid10 = false, true, false
st.ranged.swingRangeSignal = true; st.ranged.targetInRange = false
RF:Refresh(st)
ok(st.ranged.targetInRange == false, "swing-range signal owns the gate once seen")
-- A secret boolean from UnitCanAttack never reaches a truth test.
st.ranged.swingRangeSignal = false; canAttack = "SECRET"
RF:Refresh(st)
ok(t.rangeState == nil, "secret attackability -> no zone (safe)")
print(("forever_range: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
