-- Tests/forever_range_test.lua
-- Forever/RangeFinder.lua: the range checks that stay plain in combat feed
-- the ladder (Forever/RangeLadder.lua); the finder publishes the segment and
-- the zone the rest of the HUD reads. Run from the repo root: luajit Tests/forever_range_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
_G.GetRangedHaste = function() return 0 end
local now = 100
_G.GetTime = function() return now end
local shoot, wing, mid10 = nil, nil, nil
local items = {}          -- [itemID] = true/false/nil
_G.C_Spell = { IsSpellInRange = function(id) if id == 75 then return shoot end if id == 2974 then return wing end return true end,  -- other melee spells answer true everywhere (measured)
               GetSpellInfo = function(id) if id == 75 then return { minRange = 8, maxRange = 35 } end end }
local itemCalls = 0
_G.C_Item = { IsItemInRange = function(id) itemCalls = itemCalls + 1; return items[id] end }
_G.CheckInteractDistance = function(unit, idx) if idx == 3 then return mid10 end if idx == 4 then return items.cid4 end end
local exists, dead, canAttack = true, false, true
_G.UnitExists = function() return exists end
_G.UnitIsDeadOrGhost = function() return dead end
_G.UnitCanAttack = function() return canAttack end
local Nock = { Flavor = { forever = true, Plain = function(v) if v == "SECRET" then return nil end return v end }, Constants = {} }
local module
function Nock:NewModule(name) module = { name = name, events = {}, msgs = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function module:RegisterMessage(m, h) self.msgs[m] = h or m end
  return module end
function Nock:GetModule() return nil end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/Spells.lua")
dofile("Forever/RangeLadder.lua")
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

local requested = {}
_G.C_Item.RequestLoadItemDataByID = function(id) requested[id] = true end
RF:OnEnable()
ok(requested[8149] and requested[10645] and requested[13289] and requested[7734] and requested[18904] and requested[4945],
   "the ladder's items are requested from the client at enable (cold item cache)")
local st = Nock.state
local t = st.target
-- Readings for a spot: sets every probe; `settle` refreshes twice 0.2 s
-- apart so a changed segment is past the 0.15 s settle.
local function at(w, s, i10645, i13289, cid4, i7734, i18904, i4945)
  wing, shoot = w, s
  items[8149] = w
  items[10645], items[13289], items.cid4, items[7734], items[18904], items[4945] = i10645, i13289, cid4, i7734, i18904, i4945
end
local function settle() RF:Refresh(st); now = now + 0.2; RF:Refresh(st) end

-- In melee.
at(true, false, true, true, true, true, true, true); settle()
ok(t.ladderLayout and t.ladderLayout.id == "8-35c" and t.ladderRev >= 1, "compact layout (the default) built from Auto Shot's 8-35")
Nock.db = { profile = { reactRangeStyle = "detailed" } }
local rev0 = t.ladderRev
ok(RF.msgs and RF.msgs["NOCK_VISUALS_CHANGED"] == "RebuildLayout", "a style change rebuilds the layout")
RF:RebuildLayout(); RF:Refresh(st)
ok(t.ladderLayout.id == "8-35" and t.ladderRev == rev0 + 1, "detailed style: 9-segment layout, rev moved")
Nock.db = nil
ok(t.ladderKey == "MELEE" and t.rangeState == "MELEE" and t.inMelee == true and t.rangeZone == "TOO_CLOSE", "published MELEE")
ok(st.ranged.targetInRange == false, "auto bar gate: cannot shoot in melee")
-- Dead zone past CheckInteractDistance 3 (the grey-bar bug, probe 2026-09-24).
at(false, false, true, true, true, true, true, true); mid10 = false; settle()
ok(t.ladderKey == "DEAD" and t.rangeState == "CLOSE" and t.rangeZone == "OUT", "dead zone beyond ~10 yd is still the dead zone")
-- 25-28, shooting.
at(false, true, false, false, true, true, true, true); settle()
ok(t.ladderKey == "25_28" and t.ladderShoot == true and t.rangeState == "SWEET" and t.rangeZone == "SWEET", "published 25-28, can shoot")
ok(st.ranged.targetInRange == true, "auto bar gate: can shoot")
-- 35-40, cannot shoot.
at(false, false, false, false, false, false, false, true); settle()
ok(t.ladderKey == "35_40" and t.ladderShoot == false and t.rangeState == "LONG" and t.rangeProg == -1, "far and unshootable: LONG")
-- Out of range.
at(false, false, false, false, false, false, false, false); settle()
ok(t.ladderKey == "OOR" and t.rangeState == "LONG", "out of range")
-- A 0.1 s blip does not reach the state.
at(false, true, true, true, true, true, true, true); settle()
ok(t.ladderKey == "8_20", "8-20")
shoot = false; RF:Refresh(st); now = now + 0.1; shoot = true; RF:Refresh(st)
ok(t.ladderKey == "8_20" and t.rangeState == "SWEET", "a 0.1 s Auto Shot blip is swallowed")
-- Target change resets the settle: the new target's segment shows at once.
RF:PLAYER_TARGET_CHANGED()
at(true, false, true, true, true, true, true, true); RF:Refresh(st)
ok(t.ladderKey == "MELEE", "target change resets the settle")
-- No target clears, gate goes unknown.
exists = false
RF:Refresh(st)
ok(t.exists == false and t.ladderKey == nil and t.rangeState == nil and st.ranged.targetInRange == nil, "no target clears and the gate is unknown")
-- Once the client's own swing-range signal has been seen, the finder stops writing the gate.
exists = true; at(false, true, false, true, true, true, true, true)
st.ranged.swingRangeSignal = true; st.ranged.targetInRange = false
RF:Refresh(st)
ok(st.ranged.targetInRange == false, "swing-range signal owns the gate once seen")
-- A secret boolean from UnitCanAttack never reaches a truth test.
st.ranged.swingRangeSignal = false; canAttack = "SECRET"
RF:Refresh(st)
ok(t.rangeState == nil and t.ladderKey == nil, "secret attackability -> no zone (safe)")
-- A friendly or dead target is never probed.
canAttack = false; itemCalls = 0
RF:Refresh(st)
ok(itemCalls == 0 and t.rangeState == nil, "friendly target: no item probe, no zone")
canAttack, dead = true, true
RF:Refresh(st)
ok(itemCalls == 0 and t.rangeState == nil, "dead target: no item probe, no zone")
dead = false
RF:Refresh(st)
ok(itemCalls > 0, "live hostile target is probed")
-- Wing Clip not learned: item 8149 decides melee.
at(nil, false, true, true, true, true, true, true); items[8149] = true; RF:PLAYER_TARGET_CHANGED(); RF:Refresh(st)
ok(t.ladderKey == "MELEE", "Wing Clip unknown: 8149 makes melee")
-- Hawk Eye 3: Auto Shot reports 41 yd; the layout gains 40-41 and moves ladderRev.
local rev = t.ladderRev
_G.C_Spell.GetSpellInfo = function(id) if id == 75 then return { minRange = 8, maxRange = 41 } end end
RF:RebuildLayout(); RF:Refresh(st)
ok(t.ladderLayout.has4041 == true and t.ladderRev == rev + 1, "talent change rebuilds the layout")
RF:RebuildLayout(); RF:Refresh(st)
ok(t.ladderRev == rev + 1, "an unchanged layout keeps its rev")
ok(RF.events["SPELLS_CHANGED"] == "RebuildLayout", "spell changes rebuild the layout")

-- PLAYER_TARGET_CHANGED fires INSIDE the client's own TurnOrActionStop call
-- (right-click targeting); a range probe made there is ADDON_ACTION_BLOCKED
-- (seen 2026-09-23). The handler only asks the tick for the next refresh.
RF._nextRefresh = 999
local before = itemCalls
RF:PLAYER_TARGET_CHANGED()
ok(itemCalls == before, "target change makes no range probe of its own")
ok(RF._nextRefresh == nil, "target change brings the next tick refresh forward")

-- Per-tile range for the grid's grey tint (state.target.spellOut).
local SO = Nock.ForeverSlotOut
ok(SO(false, true, nil) == false and SO(false, false, nil) == true and SO(false, nil, true) == nil, "ranged tile follows the API; unknown stays nil")
ok(SO(true, true, false) == true and SO(true, true, true) == false and SO(true, true, nil) == nil, "melee tile follows the melee probe, not the API")
do
  local arcIn = true
  _G.C_Spell.IsSpellInRange = function(q) if q == 75 then return shoot end if q == 2974 then return wing end if q == "Arcane Shot" then return arcIn end if q == 5384 then return nil end return true end
  Nock.API = { SpellName = function(id) return ({ [3044] = "Arcane Shot" })[id] end }
  st.cooldowns.Arc = { spellId = 3044 }
  st.cooldowns.Raptor = { spellId = 2973, melee = true }
  st.cooldowns.FD = { spellId = 5384 }
  exists, dead, canAttack = true, false, true
  at(false, true, true, true, true, true, true, true)
  RF:Refresh(st)
  ok(t.spellOut.Arc == false and t.spellOut.Raptor == true and t.spellOut.FD == nil, "at range: Arc in (by name), Raptor out (melee probe), FD unknown")
  arcIn = false; wing = true
  RF:Refresh(st)
  ok(t.spellOut.Arc == true and t.spellOut.Raptor == false, "in melee: Arc greyed, Raptor lit")
  canAttack = false
  RF:Refresh(st)
  ok(next(t.spellOut) == nil, "friendly target: no per-tile probe, tints cleared")
  canAttack = true
end
-- Hunter's Mark cast range for the corner icon (state.target.markOut).
do
  local hmIn = true
  _G.C_Spell.IsSpellInRange = function(q) if q == 75 then return shoot end if q == 2974 then return wing end if q == "Hunter's Mark" or q == 1130 then return hmIn end return true end
  Nock.API = { SpellName = function(id) return ({ [1130] = "Hunter's Mark" })[id] end }
  RF:Refresh(st)
  ok(t.markOut == false, "in mark range: markOut false (asked by name)")
  hmIn = false; RF:Refresh(st)
  ok(t.markOut == true, "out of mark range: markOut true")
  hmIn = nil; RF:Refresh(st)
  ok(t.markOut == nil, "no answer: unknown")
  hmIn = false; canAttack = false; RF:Refresh(st)
  ok(t.markOut == nil, "friendly target: unknown, no probe")
  canAttack = true
end
print(("forever_range: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
