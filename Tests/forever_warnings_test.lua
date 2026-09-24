-- Tests/forever_warnings_test.lua
-- Forever/Warnings.lua: the Forever warnings module (ammo low, pet dead,
-- no pet in combat, pet unhappy) over plain reads, publishing the same
-- records the alert squares frame draws.
-- Run from the repo root: luajit Tests/forever_warnings_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local now = 100
_G.GetTime = function() return now end
local Nock = {
  Flavor = { forever = true, Plain = function(v) if v == "SECRET" then return nil end return v end },
  API = { SpellIcon = function(id) return 1000 + id end },
  db = { profile = {} },
  Constants = {},
}
local module
function Nock:NewModule(name) module = { name = name }; return module end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/Spells.lua")
dofile("Forever/Warnings.lua")
local W = module
ok(W and W.name == "Warnings" and W.refreshInterval == 0.1, "registers as Warnings on the slow lane")
ok(#W.Catalog == 9 and W.Catalog[9].key == "petGrowl" and W.Catalog[6].key == "notAttacking" and W.Catalog[7].key == "notInRange" and W.Catalog[7].category == "combat" and W.Catalog[8].key == "petAttack" and W.Catalog[8].category == "pet" and W.Catalog[1].key == "ammo" and W.Catalog[2].key == "petDead" and W.Catalog[3].key == "petMissing" and W.Catalog[4].key == "petUnhappy", "eight catalog entries")
for _, e in ipairs(W.Catalog) do
  ok(e.category and e.name and e.severity and e.enabledKey and e.iconFn and e.description and e.logic, "catalog entry complete: " .. e.key)
  ok(type(e.iconFn()) == "number", "catalog icon resolves: " .. e.key)
end

local C = W.Checks
local base = { ammoId = 2515, ammoCount = 716, ammoIcon = 5, petExists = true, petDead = false, happiness = 3, callPetKnown = true, inCombat = true,
               rangedOn = true, meleeOn = false, targetHostile = true, now = 100, zone = "SWEET", petTarget = true }
local function with(t) local r = {}; for k, v in pairs(base) do r[k] = v end; for k, v in pairs(t) do r[k] = v end; return r end

-- ammo
ok(C.ammo(base) == nil, "716 arrows: quiet")
local a = C.ammo(with({ ammoCount = 120 }))
ok(a and a.id == "ammo" and a.severity == "red" and a.text == "120" and a.icon == 5, "120 arrows: red with the count")
ok(C.ammo(with({ ammoId = nil, ammoCount = nil })) == nil, "empty ammo slot: quiet (no ammo class to warn about)")
Nock.db.profile.quiverArrowThreshold = 100
ok(C.ammo(with({ ammoCount = 120 })) == nil, "threshold honoured")
Nock.db.profile.quiverArrowThreshold = nil
Nock.db.profile.warnQuiverEnabled = false
ok(C.ammo(with({ ammoCount = 10 })) == nil, "disabled: quiet")
Nock.db.profile.warnQuiverEnabled = nil

-- pet dead
ok(C.petDead(base) == nil, "live pet: quiet")
local d = C.petDead(with({ petDead = true }))
ok(d and d.severity == "red" and d.icon == 1000 + 982, "dead pet: red with Revive Pet")
ok(C.petDead(with({ petExists = false, petDead = false })) == nil, "no pet: not dead")

-- pet missing
ok(C.petMissing(base) == nil, "pet out: quiet")
local m = C.petMissing(with({ petExists = false }))
ok(m and m.severity == "amber" and m.icon == 1000 + 883, "no pet in combat: amber with Call Pet")
ok(C.petMissing(with({ petExists = false, inCombat = false })) == nil, "no pet out of combat: quiet")
ok(C.petMissing(with({ petExists = false, callPetKnown = false })) == nil, "Call Pet unknown: quiet")

-- pet unhappy
ok(C.petUnhappy(base) == nil, "happy: quiet")
ok(C.petUnhappy(with({ happiness = 2 })) == nil, "content: quiet (the buff row's face covers it)")
local u = C.petUnhappy(with({ happiness = 1 }))
ok(u and u.severity == "amber" and u.icon == 1000 + 6991, "unhappy: amber with Feed Pet")
ok(C.petUnhappy(with({ happiness = 1, petDead = true })) == nil, "dead pet: the dead warning owns it")

-- Live reads, secret-guarded.
local ammoId, ammoCount, exists, dead, happy = 2515, 300, true, false, 1
_G.GetInventoryItemID = function() return ammoId end
_G.GetInventoryItemCount = function() return ammoCount end
_G.GetInventoryItemTexture = function() return 7 end
_G.UnitExists = function() return exists end
_G.UnitIsDead = function() return dead end
_G.C_PetInfo = { GetPetHappiness = function() return happy, 125, 20 end }
_G.C_SpellBook = { IsSpellKnown = function(id) return id == 883 end }
local state = { warnings = {}, player = { inCombat = true } }
W:Refresh(state)
ok(#state.warnings == 2 and state.warnings[1].id == "ammo" and state.warnings[2].id == "petUnhappy", "refresh publishes red before amber")
ammoCount = "SECRET"
W:Refresh(state)
ok(#state.warnings == 1 and state.warnings[1].id == "petUnhappy", "a secret ammo count is a nil read: quiet")
ammoCount = 300; exists = false; happy = nil
W:Refresh(state)
ok(#state.warnings == 2 and state.warnings[2].id == "petMissing", "no pet in combat: missing, not unhappy")
Nock.db.profile.showWarnings = false
W:Refresh(state)
ok(#state.warnings == 0, "master switch off: nothing")
Nock.db.profile.showWarnings = nil

-- Demo.
W:RunDemo(10)
W:Refresh(state)
ok(#state.warnings == 3 and state.warnings[1].id == "demo_red", "demo: the three samples")
now = 111
W:Refresh(state)
ok(#state.warnings == 2 and state.warnings[1].id == "ammo", "demo over: the live list")

-- Pet HP: secret on Forever at all times, so the square's alpha is a curve
-- the CLIENT evaluates (1 below the threshold, 0 above); Nock passes the
-- secret straight to the widget and never looks at it.
local curves = {}
_G.Enum = { LuaCurveType = { Step = 1, Linear = 0 } }
_G.C_CurveUtil = { CreateCurve = function()
  local c = { points = {} }
  function c:AddPoint(x, y) self.points[#self.points + 1] = { x, y } end
  function c:SetType(t) self.kind = t end
  curves[#curves + 1] = c
  return c
end }
local SECRET_ALPHA = { secret = true }
local hpCalls = 0
_G.UnitHealthPercent = function(unit, predicted, curve) hpCalls = hpCalls + 1; return SECRET_ALPHA end
exists, dead = true, false
Nock.db.profile.mendPetThreshold = 40
local alpha = W:PetHpAlpha()
ok(alpha == SECRET_ALPHA and hpCalls == 1, "the client's evaluation is handed back untouched")
ok(#curves == 1 and curves[1].kind == 1 and curves[1].points[1][1] == 0 and curves[1].points[1][2] == 1 and curves[1].points[2][1] == 0.4 and curves[1].points[2][2] == 0, "a step curve: 1 below 40%, 0 from there")
W:PetHpAlpha()
ok(#curves == 1, "the curve is built once per threshold")
Nock.db.profile.mendPetThreshold = 30
W:PetHpAlpha()
ok(#curves == 2 and curves[2].points[2][1] == 0.3, "a new threshold builds a new curve")
exists = false
ok(W:PetHpAlpha() == 0, "no pet: plain 0")
exists, dead = true, true
ok(W:PetHpAlpha() == 0, "dead pet: plain 0 (the dead warning owns it)")
dead = false
Nock.db.profile.warnPetLowHpEnabled = false
ok(W:PetHpAlpha() == 0, "disabled: plain 0")
Nock.db.profile.warnPetLowHpEnabled = nil
ok(W.Catalog[5] and W.Catalog[5].key == "petLowHp" and W.Catalog[5].thresholds[1].key == "mendPetThreshold", "catalog: pet HP entry with the TBC threshold key")

-- Not attacking: in combat with a live hostile target and neither auto-attack
-- on, after a grace so a retarget or a melee swap never blinks it.
ok(C.notAttacking(base) == nil, "Auto Shot on: quiet")
ok(C.notAttacking(with({ rangedOn = false, meleeOn = true })) == nil, "melee auto-attack on: quiet")
ok(C.notAttacking(with({ rangedOn = false, now = 100 })) == nil, "both off: quiet inside the grace")
ok(C.notAttacking(with({ rangedOn = false, now = 101.4 })) == nil, "1.4 s: still inside the grace")
local na = C.notAttacking(with({ rangedOn = false, now = 101.6 }))
ok(na and na.id == "notAttacking" and na.severity == "red" and na.text == "ATTACK" and na.icon == 1000 + 75, "1.6 s: red ATTACK with the Auto Shot icon")
ok(C.notAttacking(with({ rangedOn = true, now = 101.7 })) == nil, "Auto Shot back on: clears at once")
ok(C.notAttacking(with({ rangedOn = false, now = 200 })) == nil, "off again: the grace restarts")
ok(C.notAttacking(with({ rangedOn = false, now = 201.4 })) == nil and C.notAttacking(with({ rangedOn = false, now = 201.6 })) ~= nil, "and fires after it")
ok(C.notAttacking(with({ rangedOn = false, targetHostile = false, now = 300 })) == nil and C.notAttacking(with({ rangedOn = false, targetHostile = false, now = 310 })) == nil, "no live hostile target: quiet, no grace running")
ok(C.notAttacking(with({ rangedOn = false, inCombat = false, now = 320 })) == nil and C.notAttacking(with({ rangedOn = false, inCombat = false, now = 330 })) == nil, "out of combat: quiet")
Nock.db.profile.warnNotAttackingEnabled = false
ok(C.notAttacking(with({ rangedOn = false, now = 400 })) == nil and C.notAttacking(with({ rangedOn = false, now = 410 })) == nil, "disabled: quiet")
Nock.db.profile.warnNotAttackingEnabled = nil
ok(W.Catalog[6].enabledKey == "warnNotAttackingEnabled" and W.Catalog[6].iconFn() == 1000 + 75, "catalog: the toggle key and the Auto Shot icon")

-- Not in range: the zone the range finder publishes against the attack in
-- use. Ranged (Auto Shot on): the dead zone and out of range. Melee only:
-- the dead zone. Neither on: quiet (the not-attacking square owns that).
ok(C.notInRange(base) == nil, "shooting in the sweet spot: quiet")
ok(C.notInRange(with({ zone = "CLOSE", now = 100 })) == nil, "dead zone: quiet inside the grace")
local nr = C.notInRange(with({ zone = "CLOSE", now = 101.1 }))
ok(nr and nr.id == "notInRange" and nr.severity == "amber" and nr.text == "DEAD ZONE" and nr.icon == 1000 + 75, "dead zone past the grace: amber DEAD ZONE")
ok(C.notInRange(with({ zone = "LONG", now = 101.2 })).text == "RANGE", "out of range while shooting: RANGE, the grace carries over")
ok(C.notInRange(with({ zone = "SWEET", now = 101.3 })) == nil, "back in range: clears at once")
ok(C.notInRange(with({ zone = "MELEE", now = 110 })) == nil and C.notInRange(with({ zone = "MELEE", now = 120 })) == nil, "shooting in melee reach: quiet (the client refuses the shot, the auto bar shows it)")
local m = { rangedOn = false, meleeOn = true }
local function melee(t) for k, v in pairs(m) do t[k] = v end; return with(t) end
ok(C.notInRange(melee({ zone = "LONG", now = 200 })) == nil and C.notInRange(melee({ zone = "LONG", now = 210 })) == nil, "meleeing out of range: quiet")
ok(C.notInRange(melee({ zone = "MELEE", now = 220 })) == nil, "meleeing in reach: quiet")
ok(C.notInRange(melee({ zone = "CLOSE", now = 230 })) == nil and C.notInRange(melee({ zone = "CLOSE", now = 231.1 })).text == "DEAD ZONE", "meleeing in the dead zone: DEAD ZONE after the grace")
ok(C.notInRange(with({ rangedOn = true, meleeOn = true, zone = "MELEE", now = 240 })) == nil and C.notInRange(with({ rangedOn = true, meleeOn = true, zone = "MELEE", now = 250 })) == nil, "both on in melee reach: the swing lands, quiet")
ok(C.notInRange(with({ rangedOn = false, meleeOn = false, zone = "LONG", now = 300 })) == nil and C.notInRange(with({ rangedOn = false, meleeOn = false, zone = "LONG", now = 310 })) == nil, "neither auto-attack on: quiet")
ok(C.notInRange(with({ zone = nil, now = 320 })) == nil and C.notInRange(with({ zone = nil, now = 330 })) == nil, "no zone: quiet")
ok(C.notInRange(with({ zone = "LONG", inCombat = false, now = 340 })) == nil and C.notInRange(with({ zone = "LONG", inCombat = false, now = 350 })) == nil, "out of combat: quiet")
Nock.db.profile.warnNotInRangeEnabled = false
ok(C.notInRange(with({ zone = "LONG", now = 400 })) == nil and C.notInRange(with({ zone = "LONG", now = 410 })) == nil, "disabled: quiet")
Nock.db.profile.warnNotInRangeEnabled = nil

-- Pet not attacking: in combat with a living pet that has no target, past
-- a grace (the order lands a beat after the pull). Same key as TBC.
ok(C.petAttack(base) == nil, "pet on a target: quiet")
ok(C.petAttack(with({ petTarget = false, now = 100 })) == nil, "pet idle: quiet inside the grace")
local pi = C.petAttack(with({ petTarget = false, now = 101.6 }))
ok(pi and pi.id == "petAttack" and pi.severity == "amber" and pi.text == "PET IDLE" and type(pi.icon) == "number", "pet idle past the grace: amber PET IDLE")
ok(C.petAttack(with({ petTarget = true, now = 101.7 })) == nil, "pet sent in: clears at once")
ok(C.petAttack(with({ petTarget = nil, now = 200 })) == nil and C.petAttack(with({ petTarget = nil, now = 210 })) == nil, "a secret answer: quiet")
ok(C.petAttack(with({ petTarget = false, petExists = false, now = 220 })) == nil and C.petAttack(with({ petTarget = false, petExists = false, now = 230 })) == nil, "no pet: quiet (the no-pet square owns it)")
ok(C.petAttack(with({ petTarget = false, petDead = true, now = 240 })) == nil and C.petAttack(with({ petTarget = false, petDead = true, now = 250 })) == nil, "dead pet: quiet")
ok(C.petAttack(with({ petTarget = false, inCombat = false, now = 260 })) == nil and C.petAttack(with({ petTarget = false, inCombat = false, now = 270 })) == nil, "out of combat: quiet")
Nock.db.profile.warnPetAttackEnabled = false
ok(C.petAttack(with({ petTarget = false, now = 300 })) == nil and C.petAttack(with({ petTarget = false, now = 310 })) == nil, "disabled: quiet")
Nock.db.profile.warnPetAttackEnabled = nil
ok(W.Catalog[8].enabledKey == "warnPetAttackEnabled", "catalog: TBC's toggle key")

-- The live reads carry both auto-attack toggles and the target from state.
do
  local st = { player = { inCombat = true }, ranged = { repeating = true }, melee = { attacking = false },
               target = { exists = true, alive = true, friendly = false } }
  st.target.rangeState = "CLOSE"
  local r = W:Reads(st)
  ok(r.rangedOn == true and r.meleeOn == false and r.targetHostile == true and r.now == now and r.zone == "CLOSE", "reads: toggles, a live hostile target and its zone")
  st.target.friendly = true
  ok(W:Reads(st).targetHostile == false, "reads: a friendly target is not hostile")
  st.target.friendly, st.target.alive = false, false
  ok(W:Reads(st).targetHostile == false, "reads: a dead target is not hostile")
  -- The pet's target: a plain false must survive the read (it is the idle case).
  local saved = _G.UnitExists
  _G.UnitExists = function(u) if u == "pet" then return true end return false end
  ok(W:Reads(st).petTarget == false, "reads: pet without a target reads false, not nil")
  _G.UnitExists = function(u) if u == "pet" then return true end return "SECRET" end
  ok(W:Reads(st).petTarget == nil, "reads: a secret pet target reads nil")
  _G.UnitExists = function(u) return true end
  ok(W:Reads(st).petTarget == true, "reads: pet on a target reads true")
  _G.UnitExists = saved
end

-- Pet Growl on autocast: dungeon or raid only, by Growl's name.
ok(C.petGrowl(with({ inInstance = true, growlAutocast = false })) == nil, "Growl off: quiet")
local g = C.petGrowl(with({ inInstance = true, growlAutocast = true }))
ok(g and g.id == "petGrowl" and g.severity == "amber" and g.text == "GROWL" and g.icon == 1000 + 2649, "Growl on in an instance: amber GROWL")
ok(C.petGrowl(with({ inInstance = false, growlAutocast = true })) == nil, "open world: quiet")
ok(C.petGrowl(with({ inInstance = true, growlAutocast = true, inCombat = false })) ~= nil, "out of combat too (before the pull)")
ok(C.petGrowl(with({ inInstance = true, growlAutocast = true, petDead = true })) == nil, "dead pet: quiet")
ok(C.petGrowl(with({ inInstance = true, growlAutocast = nil })) == nil, "unknown: quiet")
Nock.db.profile.warnPetGrowlEnabled = false
ok(C.petGrowl(with({ inInstance = true, growlAutocast = true })) == nil, "disabled: quiet")
Nock.db.profile.warnPetGrowlEnabled = nil
do
  local kind, slots = "party", {}
  _G.IsInInstance = function() return true, kind end
  Nock.API.SpellName = function(id) if id == 2649 then return "Growl" end end
  _G.GetPetActionInfo = function(i) local s = slots[i]; if s then return s[1], 1, false, false, true, s[2] end end
  slots[4] = { "Growl", true }
  ok(W:InInstance() == true and W:GrowlAutocast() == true, "reads: dungeon, Growl slot autocast on")
  kind = "raid"; ok(W:InInstance() == true, "reads: raid counts")
  kind = "none"; ok(W:InInstance() == false, "reads: open world does not")
  kind = "pvp";  ok(W:InInstance() == false, "reads: a battleground does not")
  slots[4] = { "Growl", false }
  ok(W:GrowlAutocast() == false, "reads: autocast off")
  slots[4] = { "Growl", "SECRET" }
  ok(W:GrowlAutocast() == nil, "reads: a secret flag is unknown")
  slots[4] = nil
  ok(W:GrowlAutocast() == nil, "reads: no Growl on the bar")
  _G.IsInInstance, _G.GetPetActionInfo, Nock.API.SpellName = nil, nil, nil
end

-- Call Pet knowledge falls back to the level.
_G.C_SpellBook = nil
_G.UnitLevel = function() return 9 end
ok(W:CallPetKnown() == false, "level 9 without the spellbook API: unknown")
_G.UnitLevel = function() return 10 end
ok(W:CallPetKnown() == true, "level 10: known")

print(("forever_warnings: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
