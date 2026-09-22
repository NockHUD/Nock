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
ok(#W.Catalog == 5 and W.Catalog[1].key == "ammo" and W.Catalog[2].key == "petDead" and W.Catalog[3].key == "petMissing" and W.Catalog[4].key == "petUnhappy", "five catalog entries")
for _, e in ipairs(W.Catalog) do
  ok(e.category and e.name and e.severity and e.enabledKey and e.iconFn and e.description and e.logic, "catalog entry complete: " .. e.key)
  ok(type(e.iconFn()) == "number", "catalog icon resolves: " .. e.key)
end

local C = W.Checks
local base = { ammoId = 2515, ammoCount = 716, ammoIcon = 5, petExists = true, petDead = false, happiness = 3, callPetKnown = true, inCombat = true }
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

-- Call Pet knowledge falls back to the level.
_G.C_SpellBook = nil
_G.UnitLevel = function() return 9 end
ok(W:CallPetKnown() == false, "level 9 without the spellbook API: unknown")
_G.UnitLevel = function() return 10 end
ok(W:CallPetKnown() == true, "level 10: known")

print(("forever_warnings: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
