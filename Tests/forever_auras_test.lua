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
-- 10. eating / drinking: the Food (433) / Drink (430) auras by name, out of
-- combat, as the records the pill (UI/Frame_ConsumeBanner.lua) reads.
now = 1000
cache = { ["playerspell433"] = { spellId = 33004, icon = 7, expirationTime = 1020, duration = 30 },
          ["playerspell430"] = { spellId = 27089, icon = 8, expirationTime = 1015, duration = 30 } }
A:Refresh()
ok(p.eating and p.eating.spellId == 33004 and p.eating.icon == 7 and p.eating.expirationTime == 1020 and p.eating.duration == 30, "eating from the Food aura")
ok(p.drinking and p.drinking.icon == 8 and p.drinking.expirationTime == 1015, "drinking from the Drink aura")
now = 1016
A:Refresh()
ok(p.eating and p.drinking == nil, "an expired Drink record is not drinking")
secretAuras = true
A:Refresh()
ok(p.eating == nil and p.drinking == nil, "both clear while auras are secret")
secretAuras = false
cache = {}
A:Refresh()
ok(p.eating == nil and p.drinking == nil, "none without the auras")
-- The client has not resolved the names yet: the English fallbacks.
Nock.API.SpellName = function() return nil end
cache = { ["playerFood"] = { spellId = 1, icon = 9, expirationTime = 1030, duration = 30 } }
A:Refresh()
ok(p.eating and p.eating.icon == 9, "Food by the fallback name")
-- 11. /cancelaura in combat: no cast, no aura read -- the cancel hook clears
-- the aspect when the cancelled name is the one up, and nothing else.
Nock.API.SpellName = function(id) return "spell" .. (rankOf[id] or id) end
secretAuras = true
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 13165)
A.OnCancel("spell13163")
ok(p.aspect and p.aspect.spellId == 13165, "cancelling another aspect leaves Hawk up")
A.OnCancel(nil)
A.OnCancel("")
ok(p.aspect and p.aspect.spellId == 13165, "an empty cancel is ignored")
A.OnCancel("  SPELL13165(Rank 3) ")
ok(p.aspect == nil, "cancelling Hawk by name clears it (rank and case ignored)")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 13165)
A.OnCancel(14318)
ok(p.aspect == nil, "a cancel by a rank's spell id clears it too")
A.OnCancel("spell13165")
ok(p.aspect == nil, "a cancel with no aspect up is harmless")
-- 12. right-click on the buff bar in combat: CancelUnitBuff(player, index)
-- is matched through the button holding that index.
local function btn(index, inst, icon)
  return { buttonInfo = { index = index, auraInstanceID = inst },
           Icon = { GetTexture = function() return icon end } }
end
secretAuras = false
cache = { ["player13165"] = { spellId = 13165, auraInstanceID = 89, icon = 136076 } }
A:Refresh()
ok(p.aspect and p.aspect.auraInstanceID == 89 and p.aspect.auraIcon == 136076, "out of combat the aspect keeps its instance id and icon")
secretAuras = true
local frames = { btn(1, 50, 111), btn(2, 89, 136076) }
A.OnCancelBuff("player", 1, "HELPFUL", frames)
ok(p.aspect ~= nil, "cancelling another buff leaves the aspect")
A.OnCancelBuff("target", 2, "HELPFUL", frames)
A.OnCancelBuff("player", 2, "HARMFUL", frames)
A.OnCancelBuff("player", 2, "HELPFUL", nil)
ok(p.aspect ~= nil, "another unit, a debuff, or no buff frame is ignored")
A.OnCancelBuff("player", 2, "HELPFUL", { btn(2, 90, 136076) })
ok(p.aspect ~= nil, "a different instance with the same icon is not the aspect")
A.OnCancelBuff("player", 2, "HELPFUL", frames)
ok(p.aspect == nil, "right-click on the aspect's button clears it")
-- Cast in combat: no instance id known, matched by icon.
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 13165)
ok(p.aspect and p.aspect.auraInstanceID == nil, "a cast aspect has no instance id")
A.OnCancelBuff("player", 3, "HELPFUL", { btn(3, 120, 111) })
ok(p.aspect ~= nil, "another icon is not the aspect")
A.OnCancelBuff("player", 3, "HELPFUL", { btn(3, 121, 1000 + 13165) })
ok(p.aspect == nil, "a cast aspect is matched by its icon")
-- 13. Trueshot Aura (1299346), a 30-minute self buff on Forever: on/off and
-- its expiry from the cache out of combat (by id, else by name); in combat a
-- cast starts the timer (the duration last read, else 30 min), a /cancelaura
-- takes it down and the timer running out takes it down. The right-click on
-- the buff bar names no buff in combat (probe 2026-10-09: the button's aura
-- id and icon are secret), so it is not read. The talent is read out of
-- combat only, then held.
local TSA = 1299346
local rank = 1
A.TrueshotRank = function() return rank end
secretAuras = false
cache = {}
now = 2000
A:Refresh()
ok(p.trueshotTalented == true and p.trueshot == false and p.trueshotExpires == nil, "talented, no aura: off")
cache = { ["player" .. TSA] = { spellId = TSA, auraInstanceID = 300, icon = 132329, expirationTime = 2900, duration = 1800 } }
A:Refresh()
ok(p.trueshot == true and p.trueshotExpires == 2900, "aura by id: on, with its expiry")
cache = { ["playerspell" .. TSA] = { spellId = 77777, expirationTime = 3000, duration = 1800 } }
A:Refresh()
ok(p.trueshot == true and p.trueshotExpires == 3000, "aura by name: on")
cache = { ["player" .. TSA] = { spellId = TSA, expirationTime = 0, duration = 0 } }
A:Refresh()
ok(p.trueshot == true and p.trueshotExpires == nil, "no duration on the aura: on, no expiry")
cache = {}
A:Refresh()
ok(p.trueshot == false and p.trueshotExpires == nil, "aura gone out of combat: off")
-- In combat: the cast starts the timer at the duration last read (1800).
secretAuras = true
now = 3100
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", TSA)
ok(p.trueshot == true and p.trueshotExpires == 3100 + 1800, "cast in combat: on, timed at the duration last read")
ok(p.aspect == nil or p.aspect.spellId ~= TSA, "the cast is not taken for an aspect")
A.OnCancel("spell" .. TSA)
ok(p.trueshot == false and p.trueshotExpires == nil, "/cancelaura Trueshot in combat: off")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", TSA)
now = 3100 + 1799
A:Refresh()
ok(p.trueshot == true, "a second before the timer runs out: still on")
now = 3100 + 1800
A:Refresh()
ok(p.trueshot == false and p.trueshotExpires == nil, "the timer runs out in combat: off")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 13165)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", TSA)
A.OnCancelBuff("player", 5, "HELPFUL", { btn(5, 302, 1000 + 13165) })
ok(p.trueshot == true and p.aspect == nil, "cancelling the aspect leaves Trueshot up")
rank = 0
A:Refresh()
ok(p.trueshotTalented == true, "talent is held while auras are secret")
secretAuras = false
now = 6000
A:Refresh()
ok(p.trueshotTalented == false, "untalented out of combat: re-read")
rank = nil
now = 6010
A:Refresh()
ok(p.trueshotTalented == nil, "no talent API: unknown")
-- Never read a duration: a cast in combat falls back to 30 minutes.
dofile("Forever/Auras.lua")
A = module
A:OnEnable()
A.TrueshotRank = function() return 1 end
p = Nock.state.player
secretAuras = true
now = 7000
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", TSA)
ok(p.trueshotExpires == 7000 + 1800, "no duration ever read: 30 minutes")
print(("forever_auras: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
