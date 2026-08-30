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

_G.GetTime = function() return now end
_G.UnitExists = function(u) return units[u] or false end
_G.UnitIsDead = function() return false end
_G.UnitBuff = function(u, i)
  local b = buffs[u] and buffs[u][i]
  if not b then return nil end
  return b.name, nil, nil, nil, nil, b.exp, nil, nil, nil, b.spellId
end
_G.GetItemCount = function(id) return bags[id] or 0 end
_G.GetWeaponEnchantInfo = function() return mhEnchant, mhExpMs end
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
Nock.state = { helpers = {}, helpersHiddenByWA = false,
               player = { inCombat = false, canWeave = false,
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
  Nock.db.profile = {}
  units.target = nil
end

-- 1. Bare player: consumable helpers all "missing", ask-friend labels (empty bags).
resetWorld()
local h = refresh()
ok(h.food and h.food.status == "missing", "food missing on bare player")
ok(h.food and h.food.label == "ask friend?", "food ask-friend with empty bags")
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

-- 5. Expiring threshold: buff at 299s left -> expiring; at 301s -> invisible.
resetWorld()
local beId = anyId(CD.battleElixir.buffs)
buffs.player = { { name = "x", exp = now + 299, spellId = beId } }
h = refresh()
ok(h.battleElixir and h.battleElixir.status == "expiring", "299s left -> expiring")
buffs.player = { { name = "x", exp = now + 301, spellId = beId } }
h = refresh()
ok(h.battleElixir == nil, "301s left -> not surfaced")

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
ok(h.battleElixir and h.battleElixir.label ~= "ask friend?",
   "battle elixir keeps its own label with elixir in bags")

-- 8. Expiring keeps the plain label even with empty bags (you HAVE the buff).
resetWorld()
buffs.player = { { name = "x", exp = now + 100, spellId = beId } }
h = refresh()
ok(h.battleElixir and h.battleElixir.status == "expiring"
   and h.battleElixir.label ~= "ask friend?",
   "expiring never shows ask-friend")

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

-- 13. DebugDump returns a report string and never throws.
resetWorld()
bags[27659] = 5
buffs.player = { { name = "Agility", exp = now + 100, spellId = 33077 } }
local okCall, dump = pcall(function() return Helpers:DebugDump() end)
ok(okCall and type(dump) == "string" and dump:find("food", 1, true),
   "DebugDump produces a report")
ok(okCall and dump:find("27659 x5", 1, true), "DebugDump reports bag contents")
ok(okCall and dump:find("33077", 1, true), "DebugDump reports the matched scroll buff")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
