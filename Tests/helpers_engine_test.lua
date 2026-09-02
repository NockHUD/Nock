-- Tests/helpers_engine_test.lua
-- Drives the real Modules/Helpers.lua status pipeline under LuaJIT with the
-- WoW API stubbed: spell-ID matching, the expiring threshold, flask/elixir
-- exclusion, ask-friend labels, and the scroll both-required rule.
-- Run from the repo root: luajit Tests/helpers_engine_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- ---- WoW surface -----------------------------------------------------------
local now = 1000
local units = { player = true }          -- [unit] = exists
local buffs = { player = {}, pet = {} }  -- [unit] = array of {name, exp, spellId}
local bags  = {}                         -- [itemId] = count
local mhEnchant, mhExpMs = false, 0
local ohEnchant, ohExpMs = false, 0

_G.GetTime = function() return now end
_G.UnitExists = function(u) return units[u] or false end
_G.UnitIsDead = function() return false end
_G.UnitBuff = function(u, i)
  local b = buffs[u] and buffs[u][i]
  if not b then return nil end
  return b.name, nil, nil, nil, nil, b.exp, nil, nil, nil, b.spellId
end
_G.GetItemCount = function(id) return bags[id] or 0 end
_G.GetWeaponEnchantInfo = function()
  return mhEnchant, mhExpMs, nil, nil, ohEnchant, ohExpMs
end
_G.GetItemSpell = function(id) return "Use" .. tostring(id) end
-- Equipped weapons per slot (16 = main hand, 17 = off hand) and their weapon
-- subclass (7 = one-handed sword, 4 = one-handed mace, 13 = fist).
local equipped = {}                       -- [slot] = itemId
local weaponClass = {}                    -- [itemId] = subclassID
_G.GetInventoryItemID = function(_, slot) return equipped[slot] end
_G.GetItemInfoInstant = function(id)
  if not weaponClass[id] then return nil end
  return id, "Weapon", "x", "INVTYPE_WEAPON", 0, 2, weaponClass[id]
end
_G.GetItemInfo  = function(id) return "Item" .. tostring(id) end
_G.UnitCanAttack = function() return true end
_G.UnitClassification = function() return "worldboss" end
_G.UnitLevel = function() return -1 end
_G.UnitCreatureType = function() return "Demon" end
-- icon helpers resolve to nil in the harness (no GetItemInfo/GetSpellInfo)

-- ---- Ace surface -----------------------------------------------------------
local Nock = {}
local Helpers
_G.LibStub = function()
  return { GetAddon = function() return Nock end }
end
function Nock:NewModule(name)
  Helpers = { Print = function() end,
              RegisterEvent = function() end,
              RegisterMessage = function() end }
  return Helpers
end
Nock.Constants = {}
Nock.db = { profile = {} }
Nock.state = { helpers = {}, helpersHiddenByWA = false, helpersTestMode = false, helpersTestCreature = nil,
               player = { inCombat = false, canWeave = false, casting = nil,
                          tonk = { active = false } } }
Nock.IsInInstance = function() return true end
Nock.IsInRaidInstance = function() return true end

dofile("Core/ConsumeData.lua")
-- The aura store (Core/AuraCache.lua) is what the modules read; headlessly
-- no UNIT_AURA fires, so every read invalidates first -- the mocks are the
-- truth on every call, as UnitBuff/UnitDebuff were before the store.
dofile("Core/AuraCache.lua")
do
  local AC = Nock.AuraCache
  local inv = AC.Invalidate
  for _, k in ipairs({ "Rev", "ForEach", "BySpell", "ByName", "Count" }) do
    local f = AC[k]
    AC[k] = function(...) inv(); return f(...) end
  end
end

dofile("Modules/Helpers.lua")
local CD = Nock.ConsumeData

local function refresh()
  Helpers:Refresh(Nock.state)
  local out = {}
  for _, h in ipairs(Nock.state.helpers) do out[h.id] = h end
  return out
end

local function anyId(set)  -- deterministic: lowest id in the set
  local min
  for id in pairs(set) do if not min or id < min then min = id end end
  return min
end

local function resetWorld()
  buffs.player, buffs.pet, bags = {}, {}, {}
  units.pet, mhEnchant, mhExpMs = nil, false, 0
  ohEnchant, ohExpMs = false, 0
  Nock.db.profile = {}
  units.target = nil
  Nock.state.player.casting = nil
  Nock.state.helpersTestMode = false
  Nock.state.helpersTestCreature = nil
  equipped[16], equipped[17] = nil, nil
end

-- 1. Bare player: consumable helpers all "missing", ask-friend labels (empty bags).
resetWorld()
local h = refresh()
ok(h.food and h.food.status == "missing", "food missing on bare player")
ok(h.food and h.food.label == "NO FOOD", "food NO FOOD with empty bags")
ok(h.battleElixir and h.guardianElixir, "both elixir slots nag")
-- Bare player is committed to neither flask nor elixirs, so the flask nags too.
ok(h.flask ~= nil and h.flask.status == "missing", "flask missing on bare player")

-- 2. Spell-ID matching: scroll auras named "Agility"/"Strength" (the old
--    name matcher could never hit these).
resetWorld()
Nock.db.profile.parseMode = true
buffs.player = {
  { name = "Agility",  exp = now + 1200, spellId = 33077 },
  { name = "Strength", exp = now + 1200, spellId = 33082 },
}
h = refresh()
ok(h.scrollPlayer == nil, "both scrolls up -> scroll helper satisfied (invisible)")

-- 3. One scroll missing -> nags.
buffs.player = { { name = "Agility", exp = now + 1200, spellId = 33077 } }
h = refresh()
ok(h.scrollPlayer and h.scrollPlayer.status == "missing", "one scroll -> missing")

-- 4. Both up but sooner one under threshold -> expiring with countdown.
buffs.player = {
  { name = "Agility",  exp = now + 100,  spellId = 33077 },
  { name = "Strength", exp = now + 1200, spellId = 33082 },
}
h = refresh()
ok(h.scrollPlayer and h.scrollPlayer.status == "expiring", "scroll expiring under threshold")
ok(h.scrollPlayer and h.scrollPlayer.remaining
   and math.abs(h.scrollPlayer.remaining - 100) < 1,
   "expiring remaining = sooner scroll")

-- 5. Expiring threshold (default 180 s): buff at 179s left -> expiring; at 181s -> invisible.
resetWorld()
local beId = anyId(CD.battleElixir.buffs)
buffs.player = { { name = "x", exp = now + 179, spellId = beId } }
h = refresh()
ok(h.battleElixir and h.battleElixir.status == "expiring", "179s left -> expiring")
buffs.player = { { name = "x", exp = now + 181, spellId = beId } }
h = refresh()
ok(h.battleElixir == nil, "181s left -> not surfaced")

-- 6. Threshold 0 disables expiring.
Nock.db.profile.helpersExpiringThreshold = 0
buffs.player = { { name = "x", exp = now + 10, spellId = beId } }
h = refresh()
ok(h.battleElixir == nil, "threshold 0 -> active never surfaces")
Nock.db.profile.helpersExpiringThreshold = nil

-- 7. Flask covers both elixir slots; flask helper hides when committed to elixirs.
resetWorld()
local flaskId = anyId(CD.flask.buffs)
buffs.player = { { name = "Flask", exp = now + 3600, spellId = flaskId } }
h = refresh()
ok(h.battleElixir == nil and h.guardianElixir == nil, "flask covers both elixir slots")
resetWorld()
bags[22831] = 1  -- battle elixir in bags = committed to elixirs
h = refresh()
ok(h.flask == nil, "elixir in bags -> flask nag hidden")
ok(h.battleElixir and h.battleElixir.label ~= "NO ELIXIR",
   "battle elixir keeps its own label with elixir in bags")

-- 8. Expiring keeps the plain label even with empty bags (you HAVE the buff).
resetWorld()
buffs.player = { { name = "x", exp = now + 100, spellId = beId } }
h = refresh()
ok(h.battleElixir and h.battleElixir.status == "expiring"
   and h.battleElixir.label ~= "NO ELIXIR",
   "expiring never shows the NO-X label")

-- 9. Combat / WA-suppression / out-of-instance gates keep the list empty.
resetWorld()
Nock.state.player.inCombat = true
h = refresh()
ok(next(h) == nil, "in combat -> empty list")
Nock.state.player.inCombat = false
Nock.state.helpersHiddenByWA = true
h = refresh()
ok(next(h) == nil, "WA suppression -> empty list")
Nock.state.helpersHiddenByWA = false
Nock.IsInInstance = function() return false end
h = refresh()
ok(next(h) == nil, "outside instance -> empty list")
Nock.IsInInstance = function() return true end

-- 10. Pet food (Kibler): hidden without a pet; missing with pet + no buff.
resetWorld()
h = refresh()
ok(h.kibler == nil, "no pet -> kibler hidden")
units.pet = true
h = refresh()
ok(h.kibler and h.kibler.status == "missing", "pet without buff -> kibler missing")
buffs.pet = { { name = "Well Fed", exp = now + 600, spellId = anyId(CD.kibler.buffs) } }
h = refresh()
ok(h.kibler == nil, "pet buff by spell id -> satisfied")

-- 11. Food matches by spell ID...
resetWorld()
buffs.player = { { name = "Well Fed", exp = now + 1800, spellId = anyId(CD.food.buffs) } }
h = refresh()
ok(h.food == nil, "known food spell id -> satisfied")

-- ...and falls back to the aura NAME for foods not in the ID list, so an
-- unlisted food can never nag someone who is demonstrably fed. This fallback
-- is food-only by design.
resetWorld()
buffs.player = { { name = "Well Fed", exp = now + 1800, spellId = 999999 } }
h = refresh()
ok(h.food == nil, "unknown food spell id but 'Well Fed' name -> satisfied")
ok(CD.food.buffNames and CD.food.buffNames["Well Fed"], "food declares the name fallback")
for _, k in ipairs({ "flask", "battleElixir", "guardianElixir",
                     "scrollAgility", "scrollStrength", "kibler" }) do
  ok(CD[k].buffNames == nil, k .. " has NO name fallback (ID matching only)")
end

-- 12. Pet food and player food share the aura name "Well Fed", so a fed pet
--     must not satisfy the player's food helper and vice versa.
resetWorld()
units.pet = true
buffs.pet = { { name = "Well Fed", exp = now + 1800, spellId = anyId(CD.kibler.buffs) } }
h = refresh()
ok(h.kibler == nil, "pet food satisfied by its own spell id")
ok(h.food and h.food.status == "missing", "fed pet does NOT satisfy player food")

-- 14. Scroll sub-state: which scroll is missing, on which unit.
resetWorld()
Nock.db.profile.parseMode = true
units.pet = true
bags[27498], bags[27503] = 5, 5
h = refresh()
ok(h.scrollPlayer and h.scrollPlayer.sub == "agi" and h.scrollPlayer.label == "AGI",
   "both scrolls missing -> AGI first")
ok(h.scrollPlayer and h.scrollPlayer.unit == "player", "player scroll row tagged player")
ok(h.scrollPlayer and h.scrollPlayer.applyItem == 27498, "player AGI row applies Agility V")
ok(h.scrollPlayer and h.scrollPlayer.applyKind == "item", "player scroll is a plain item use")
ok(h.scrollPet and h.scrollPet.unit == "pet", "pet scroll row tagged pet")
ok(h.scrollPet and h.scrollPet.applyKind == "pet", "pet scroll uses the pet-target macro")
buffs.player = { { name = "Agility", exp = now + 1200, spellId = 33077 } }
h = refresh()
ok(h.scrollPlayer and h.scrollPlayer.sub == "str" and h.scrollPlayer.label == "STR"
   and h.scrollPlayer.applyItem == 27503, "agi up -> STR row applies Strength V")
buffs.player = {
  { name = "Agility",  exp = now + 100,  spellId = 33077 },
  { name = "Strength", exp = now + 1200, spellId = 33082 },
}
h = refresh()
-- Both up: the sooner scroll is the sub, so the badge names the one to
-- reapply and a click uses exactly that scroll.
ok(h.scrollPlayer and h.scrollPlayer.sub == "agi" and h.scrollPlayer.label == "AGI"
   and h.scrollPlayer.phase == "expiring", "both up, expiring -> names the sooner (AGI)")
buffs.player = {
  { name = "Agility",  exp = now + 1200, spellId = 33077 },
  { name = "Strength", exp = now + 100,  spellId = 33082 },
}
h = refresh()
ok(h.scrollPlayer and h.scrollPlayer.sub == "str" and h.scrollPlayer.applyItem == 27503,
   "both up, Strength sooner -> STR row, click applies Strength")
ok(h.flask and h.flask.unit == nil, "flask has no unit tag")
ok(h.kibler and h.kibler.unit == "pet" and h.kibler.applyKind == "pet", "pet food is pet-targeted")

-- 15. PickApplyItem: prefer order, fallback, nil.
resetWorld()
ok(Helpers.PickApplyItem(CD.food) == nil, "nothing in bags -> nil")
bags[27651] = 1                                   -- Buzzard Bites (not preferred)
ok(Helpers.PickApplyItem(CD.food) == 27651, "only a fallback food -> fallback")
bags[27659] = 1                                   -- Warp Burger (prefer[3])
ok(Helpers.PickApplyItem(CD.food) == 27659, "preferred beats fallback")
bags[27655] = 1                                   -- Ravager Dog (prefer[1])
ok(Helpers.PickApplyItem(CD.food) == 27655, "prefer order wins")

-- 16. Rows: applyItem / applyName / NO-X label / click toggle.
resetWorld()
bags[22854] = 1
h = refresh()
ok(h.flask and h.flask.applyItem == 22854 and h.flask.applyName == "Item22854",
   "flask row carries the item it would use")
ok(h.flask and h.flask.label == "FLASK", "flask label upper-case short label")
ok(h.sharpeningStone and h.sharpeningStone.applyKind == "weapon", "stone is a weapon apply")
ok(h.sharpeningStone and h.sharpeningStone.label == "NO STONE"
   and h.sharpeningStone.applyItem == nil,
   "no stone in bags -> NO STONE, not clickable")
Nock.db.profile.helpersClickToApply = false
h = refresh()
ok(h.flask and h.flask.applyItem == nil and h.flask.label == "FLASK",
   "click toggle off -> no apply item, label unchanged")
Nock.db.profile.helpersClickToApply = nil

-- 17. Phases: eating and applying.
resetWorld()
bags[27655] = 1
buffs.player = { { name = "Food", exp = now + 20, spellId = 43180 } }
h = refresh()
-- Eating stays clickable: the channel may be mage food (no Well Fed), and
-- a click on the real food replaces it.
ok(h.food and h.food.phase == "eating" and h.food.label == "EATING"
   and h.food.applyItem == 27655, "eating channel -> EATING, still clickable")
bags[27655] = nil
h = refresh()
ok(h.food and h.food.phase == "eating" and h.food.applyItem == nil,
   "eating with no food in bags -> EATING, not clickable")
resetWorld()
bags[23529] = 1
Nock.state.player.casting = { name = "Use23529" }
h = refresh()
ok(h.sharpeningStone and h.sharpeningStone.phase == "applying"
   and h.sharpeningStone.label == "APPLYING" and h.sharpeningStone.applyItem == nil,
   "casting the stone's use spell -> APPLYING")
Nock.state.player.casting = nil

-- 18. Test gate bypasses the instance and raid gates.
resetWorld()
Nock.db.profile.parseMode = true
Nock.IsInInstance = function() return false end
Nock.IsInRaidInstance = function() return false end
h = refresh()
ok(next(h) == nil, "gates closed, no test mode -> empty")
Nock.state.helpersTestMode = true
h = refresh()
ok(h.food and h.scrollPlayer, "test mode -> rows surface, scrolls included")
Nock.state.helpersTestMode = false
Nock.IsInInstance = function() return true end
Nock.IsInRaidInstance = function() return true end

-- 19. Dual wield (harness canWeave = false): the stone badge covers BOTH
--     hands, main hand first, and says which via unit + applySlot.
resetWorld()
bags[23529] = 1
h = refresh()
ok(h.sharpeningStone and h.sharpeningStone.sub == "mh" and h.sharpeningStone.unit == "mh"
   and h.sharpeningStone.applySlot == 16 and h.sharpeningStone.label == "STONE"
   and h.sharpeningStone.applyItem == 23529,
   "no stones -> main hand first, slot 16, clickable")
mhEnchant, mhExpMs = true, 1500 * 1000
h = refresh()
ok(h.sharpeningStone and h.sharpeningStone.sub == "oh" and h.sharpeningStone.unit == "oh"
   and h.sharpeningStone.applySlot == 17, "MH stoned -> off hand, slot 17")
ohEnchant, ohExpMs = true, 100 * 1000
h = refresh()
ok(h.sharpeningStone and h.sharpeningStone.status == "expiring" and h.sharpeningStone.sub == "oh"
   and h.sharpeningStone.applySlot == 17
   and math.abs(h.sharpeningStone.remaining - 100) < 1, "both stoned -> sooner (OH) counts down, click restones it")
ohEnchant, ohExpMs = true, 1500 * 1000
h = refresh()
ok(h.sharpeningStone == nil, "both stoned, both long -> invisible")
-- 2H (canWeave = true): the stone badge stays hidden, as before.
Nock.state.player.canWeave = true
mhEnchant = false
h = refresh()
ok(h.sharpeningStone == nil, "2H -> stone badge hidden")
Nock.state.player.canWeave = false

-- 20. Per-hand stone kind: a blade gets a sharpening stone, a mace a
--     weightstone, and a hand with no matching stone in bags reads NO STONE.
resetWorld()
equipped[16], equipped[17] = 1001, 1002
weaponClass[1001], weaponClass[1002] = 7, 4      -- sword, mace
bags[23529], bags[28421] = 1, 1                   -- Adamantite sharpening + weightstone
h = refresh()
ok(h.sharpeningStone and h.sharpeningStone.sub == "mh"
   and h.sharpeningStone.applyItem == 23529, "sword main hand -> sharpening stone")
mhEnchant, mhExpMs = true, 1500 * 1000
h = refresh()
ok(h.sharpeningStone and h.sharpeningStone.sub == "oh"
   and h.sharpeningStone.applyItem == 28421, "mace off hand -> weightstone")
bags[28421] = 0
h = refresh()
ok(h.sharpeningStone and h.sharpeningStone.sub == "oh"
   and h.sharpeningStone.applyItem == nil and h.sharpeningStone.label == "NO STONE",
   "mace off hand, only sharpening stones in bags -> NO STONE")
-- Unknown weapon (no item info yet): any stone in bags is offered.
equipped[17] = 1003
h = refresh()
ok(h.sharpeningStone and h.sharpeningStone.applyItem == 23529,
   "unknown off hand -> any stone in bags")
ok(Helpers.PickApplyItem(CD.sharpeningStone, "blunt") == nil, "PickApplyItem filters by kind")
ok(Helpers.PickApplyItem(CD.sharpeningStone, "sharp") == 23529, "PickApplyItem keeps matching kind")
mhEnchant = false

-- 21. Test creature: any target reads as a boss of that type.
resetWorld()
units.target = true
_G.UnitCreatureType = function() return "Beast" end
bags[9224] = 1
h = refresh()
ok(h.demonslayer == nil, "beast target -> no demonslayer badge")
Nock.state.helpersTestCreature = "Demon"
h = refresh()
ok(h.demonslayer and h.demonslayer.status == "missing" and h.demonslayer.applyItem == 9224,
   "test creature Demon -> demonslayer badge, clickable")
_G.UnitCreatureType = function() return "Demon" end
Nock.state.helpersTestCreature = nil

-- 22. Demonslaying caps its own expiring window at 60 s: a fresh 5-minute
--     elixir must not read as expiring, the last minute must.
resetWorld()
units.target = true
Nock.state.helpersTestCreature = "Demon"
bags[9224] = 1
buffs.player = { { name = "Demonslaying", exp = now + 200, spellId = 11406 } }
h = refresh()
ok(h.demonslayer == nil, "demonslaying with 200s left -> not surfaced")
buffs.player = { { name = "Demonslaying", exp = now + 50, spellId = 11406 } }
h = refresh()
ok(h.demonslayer and h.demonslayer.status == "expiring", "demonslaying with 50s left -> expiring")
Nock.db.profile.helpersExpiringThreshold = 0
h = refresh()
ok(h.demonslayer == nil, "global threshold 0 still disables the capped window")
Nock.db.profile.helpersExpiringThreshold = nil
Nock.state.helpersTestCreature = nil

-- 13. DebugDump returns a report string and never throws.
resetWorld()
bags[27659] = 5
buffs.player = { { name = "Agility", exp = now + 100, spellId = 33077 } }
local okCall, dump = pcall(function() return Helpers:DebugDump() end)
ok(okCall and type(dump) == "string" and dump:find("food", 1, true),
   "DebugDump produces a report")
ok(okCall and dump:find("27659 x5", 1, true), "DebugDump reports bag contents")
ok(okCall and dump:find("33077", 1, true), "DebugDump reports the matched scroll buff")

-- 14a. An EXPIRING buff is clickable when the refill is in bags: the
-- countdown badge is a "reapply now" cue, not a cooldown.
resetWorld()
Nock.db.profile.parseMode = true
bags[27498] = 1
buffs.player = {
  { name = "Agility",  exp = now + 100,  spellId = 33077 },
  { name = "Strength", exp = now + 1200, spellId = 33082 },
}
h = refresh()
ok(h.scrollPlayer and h.scrollPlayer.status == "expiring"
   and h.scrollPlayer.applyItem == 27498, "expiring scroll with a scroll in bags -> clickable")
bags[27498] = nil
h = refresh()
ok(h.scrollPlayer and h.scrollPlayer.status == "expiring"
   and h.scrollPlayer.applyItem == nil and h.scrollPlayer.label == "AGI",
   "expiring scroll with none in bags -> not clickable, label unchanged")
Nock.db.profile.helpersClickToApply = false
bags[27498] = 1
h = refresh()
ok(h.scrollPlayer and h.scrollPlayer.applyItem == nil, "expiring + click toggle off -> not clickable")
Nock.db.profile.helpersClickToApply = nil

-- 14b. The item's own cooldown (which is also where the GCD shows for an
-- item that triggers one) rides on the row so the badge can sweep it.
resetWorld()
bags[27498] = 1
buffs.player = { { name = "Strength", exp = now + 1200, spellId = 33082 } }
_G.GetItemCooldown = function(id) if id == 27498 then return 900, 1.5, 1 end return 0, 0, 1 end
h = refresh()
ok(h.scrollPlayer and h.scrollPlayer.cdStart == 900 and h.scrollPlayer.cdDuration == 1.5,
   "item cooldown published on the row")
_G.GetItemCooldown = function() return 0, 0, 1 end
h = refresh()
ok(h.scrollPlayer and h.scrollPlayer.cdStart == 0 and h.scrollPlayer.cdDuration == 0,
   "no cooldown -> zeros")
_G.GetItemCooldown = nil
h = refresh()
ok(h.scrollPlayer and h.scrollPlayer.cdStart == 0 and h.scrollPlayer.cdDuration == 0,
   "no cooldown API -> zeros")

-- 14. ClickMacro: every click helper is a self-targeted macro. A plain
-- consumable (scroll, food) must go to the player, never the current
-- target; pet food to the pet; a stone to the named hand.
ok(Helpers.ClickMacro("item", 27659) == "/use [target=player] item:27659",
   "ClickMacro item -> player-targeted /use")
ok(Helpers.ClickMacro("pet", 27661) == "/use [target=pet] item:27661",
   "ClickMacro pet -> pet-targeted /use")
ok(Helpers.ClickMacro("weapon", 23529, 17) == "/use item:23529\n/use 17",
   "ClickMacro weapon -> stone on the given slot")
ok(Helpers.ClickMacro("weapon", 23529) == "/use item:23529\n/use 16",
   "ClickMacro weapon defaults to the main hand")
ok(Helpers.ClickMacro(nil, 27659) == "/use [target=player] item:27659",
   "ClickMacro unknown kind falls back to the player")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
