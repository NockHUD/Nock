-- Tests/forever_auras_test.lua
-- Forever/Auras.lua: aspect and Hunter's Mark from own casts while auras are
-- secret, from the aura cache while they are not (the cache wins both ways).
-- Run from the repo root: luajit Tests/forever_auras_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local now = 100
_G.GetTime = function() return now end
_G.GetRangedHaste = function() return 0 end
local secretAuras = false
local cache, reads = {}, 0
local Nock = {
  Flavor = { forever = true, Plain = function(v) return v end }, Constants = {},
  API = { SpellName = function(id) return "spell" .. id end, SpellIcon = function(id) return 1000 + id end },
  AuraCache = { BySpell = function(unit, id) reads = reads + 1; return cache[unit .. id] end,
                ByName = function(unit, n) reads = reads + 1; return cache[unit .. n] end },
  Restricted = function(kind) return secretAuras end,
}
local module
function Nock:NewModule(name) module = { name = name, events = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  return module end
function Nock:GetModule() return nil end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/Spells.lua")
dofile("Forever/Auras.lua")
local A = module
ok(A and A.name == "Auras" and A.refreshInterval == 0.1, "module Auras on the slow lane")
A:OnEnable()
local p, t = Nock.state.player, Nock.state.target
local function fire(ev, ...) local h = A.events[ev]; A[type(h) == "string" and h or ev](A, ev, ...) end
ok(p.canWeave == true and p.rapidFire == false and p.feign == nil, "TBC-only player fields settled")

-- 1. out of combat, cache has Hawk on the player -> aspect from the cache
cache["player13165"] = { spellId = 13165 }
A:Refresh()
ok(p.aspect and p.aspect.spellId == 13165 and p.aspect.icon == 1000 + 13165, "aspect from the cache")
-- 2. target has the mark
cache["target1130"] = { spellId = 1130, duration = 120, expirationTime = 200 }
A:Refresh()
ok(t.huntersMark and t.huntersMark.expirationTime == 200 and t.huntersMark.duration == 120 and t.huntersMark.remaining == 100, "mark from the cache with remaining")
-- 3. combat: casts drive the corners
secretAuras = true
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 13163)
ok(p.aspect.spellId == 13163, "Monkey cast replaces the aspect")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 13165)
ok(p.aspect.spellId == 13165 and p.aspect.name == "spell13165", "Hawk cast replaces it again")
-- 4. mark cast at 300 -> 420
now = 300
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 1130)
ok(t.huntersMark.expirationTime == 420 and t.huntersMark.duration == 120 and t.huntersMark.fromPlayer == true, "mark from the cast")
-- 5. target change clears
fire("PLAYER_TARGET_CHANGED")
ok(t.huntersMark == nil, "target change clears the mark")
-- 6. combat refresh never touches the cache
local r0 = reads
A:Refresh()
ok(reads == r0, "no cache read while auras are secret")
-- 7. ignored casts
fire("UNIT_SPELLCAST_SUCCEEDED", "target", "g", 13163)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 75)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 999999)
ok(p.aspect.spellId == 13165 and t.huntersMark == nil, "other units, Auto Shot, unknown spells ignored")
-- 8. out of combat with an empty cache: truth wins
secretAuras = false
cache = {}
A:Refresh()
ok(p.aspect == nil and t.huntersMark == nil, "empty cache clears both")
-- 9. ranks are separate spells on Forever: a higher rank's cast and aura
-- carry their own ids and are matched by name (Hawk r2 14318, HM r2 14323).
local rankOf = { [14318] = 13165, [14323] = 1130 }
Nock.API.SpellName = function(id) return "spell" .. (rankOf[id] or id) end
secretAuras = true
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 14318)
ok(p.aspect and p.aspect.spellId == 13165 and p.aspect.icon == 1000 + 13165, "Hawk rank 2 cast -> the Hawk aspect")
now = 500
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 14323)
ok(t.huntersMark and t.huntersMark.expirationTime == 620, "Hunter's Mark rank 2 cast -> the mark")
secretAuras = false
cache = { ["playerspell13165"] = { spellId = 14318 }, ["targetspell1130"] = { spellId = 14323, duration = 120, expirationTime = 610 } }
A:Refresh()
ok(p.aspect and p.aspect.spellId == 13165, "Hawk rank 2 aura found by name out of combat")
ok(t.huntersMark and t.huntersMark.expirationTime == 610, "Hunter's Mark rank 2 aura found by name")
print(("forever_auras: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
