-- Tests/debuff_order_test.lua
-- Standalone LuaJIT tests for Modules/DebuffTracker.lua's ordering and the
-- (The engine caches its effective catalog until NOCK_VISUALS_CHANGED, which
-- every option setter sends; the direct profile edits below invalidate it by
-- hand the way that message would.)
-- tri-state enable map: profile.debuffTrackerOrder is user data mutated by
-- Up/Down executes (must survive permutations, stale keys, partial lists),
-- and a catalog entry marked defaultOff is OFF until the user turns it on
-- (nil = the entry's default, true = off, false = explicitly on).
-- Run from the repo root: luajit Tests/debuff_order_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local debuffs = {}   -- the target's debuffs: { name = ..., spellId = ... }
_G.UnitExists = function(u) return u == "target" end
_G.UnitDebuff = function(_, i)
  local d = debuffs[i]
  if not d then return nil end
  return d.name, "icon", 1, "Magic", 10, 100, "player", false, false, d.spellId
end
_G.GetSpellInfo = function(id) return "Spell " .. id, nil, "icon-" .. id end

local addon = { Constants = {}, state = {} }
local module
function addon:NewModule(name, ...)
  module = { name = name }
  return module
end
_G.LibStub = function(name, silent)
  if name == "AceAddon-3.0" then return { GetAddon = function() return addon end } end
  if silent then return nil end
  return {}
end

dofile("Core/Constants.lua")
dofile("Config/Defaults.lua")
addon.db = { profile = {} }
for k, v in pairs(addon.Defaults.profile) do addon.db.profile[k] = v end
addon.db.profile.debuffTrackerEnabled = true   -- ships OFF; the engine builds nothing while off
addon.db.profile.debuffTrackerDisabled = {}
addon.db.profile.debuffTrackerOrder = {}
addon.db.profile.debuffTrackerCustom = ""

-- The aura store (Core/AuraCache.lua) is what the modules read; headlessly
-- no UNIT_AURA fires, so every read invalidates first -- the mocks are the
-- truth on every call, as UnitBuff/UnitDebuff were before the store.
dofile("Core/AuraCache.lua")
do
  local AC = addon.AuraCache
  local inv = AC.Invalidate
  for _, k in ipairs({ "Rev", "ForEach", "BySpell", "ByName", "Count" }) do
    local f = AC[k]
    AC[k] = function(...) inv(); return f(...) end
  end
end

dofile("Modules/DebuffTracker.lua")
local DT = module
local C = addon.Constants

local function eq(got, want)
  if type(got) ~= "table" or #got ~= #want then return false end
  for i = 1, #want do if got[i] ~= want[i] then return false end end
  return true
end

local function keysOf(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.key end
  return out
end

local function catalogKeys()
  return keysOf(C.DEBUFF_CURATED)
end

--------------------------------------------------------------------------------
-- 1. The catalog carries Scorpid Sting and Insect Swarm, both default OFF.
--------------------------------------------------------------------------------
local byKey = {}
for _, e in ipairs(C.DEBUFF_CURATED) do byKey[e.key] = e end
ok(byKey.scorpid ~= nil, "catalog has scorpid")
ok(byKey.scorpid and byKey.scorpid.defaultOff == true, "scorpid ships OFF")
ok(byKey.scorpid and byKey.scorpid.names[1] == "Scorpid Sting", "scorpid matches by name")
ok(byKey.iswarm ~= nil, "catalog has iswarm (Insect Swarm)")
ok(byKey.iswarm and byKey.iswarm.defaultOff == true, "iswarm ships OFF")
ok(byKey.iswarm and byKey.iswarm.names[1] == "Insect Swarm", "iswarm matches by name")
local anyOtherOff = false
for _, e in ipairs(C.DEBUFF_CURATED) do
  if e.defaultOff and e.key ~= "scorpid" and e.key ~= "iswarm" then anyOtherOff = true end
end
ok(not anyOtherOff, "no other preset went default-off")

--------------------------------------------------------------------------------
-- 2. The pure resolver: stored order first, the rest appended in catalog order.
--------------------------------------------------------------------------------
local R = DT.ResolveOrder
ok(type(R) == "function", "DebuffTracker.ResolveOrder exists")
local elig = { "a", "b", "c", "d" }
ok(eq(R(nil, elig), elig), "nil stored -> eligible order")
ok(eq(R({}, elig), elig), "empty stored -> eligible order")
ok(eq(R({ "c", "a" }, elig), { "c", "a", "b", "d" }), "partial stored leads, rest appended")
ok(eq(R({ "d", "zzz", "d", "b" }, elig), { "d", "b", "a", "c" }), "stale + duplicate keys dropped")
ok(eq(R("junk", elig), elig), "non-table stored -> eligible order")

--------------------------------------------------------------------------------
-- 3. Enabled state is tri-state; the published list honours it and the order.
--------------------------------------------------------------------------------
DT:InvalidateCatalog(); DT:Refresh(addon.state)
local pub = keysOf(addon.state.debufftracker)
ok(#pub == #C.DEBUFF_CURATED - 2, "default: every preset but the two default-off ones is listed")
local hasScorpid = false
for _, k in ipairs(pub) do if k == "scorpid" then hasScorpid = true end end
ok(not hasScorpid, "scorpid not listed by default")

addon.db.profile.debuffTrackerDisabled.scorpid = false   -- explicitly ON
DT:InvalidateCatalog(); DT:Refresh(addon.state)
pub = keysOf(addon.state.debufftracker)
ok(pub[#pub] == "scorpid" or (function()
  for _, k in ipairs(pub) do if k == "scorpid" then return true end end
end)(), "scorpid = false (explicit on) -> listed")

addon.db.profile.debuffTrackerDisabled.hmark = true
DT:InvalidateCatalog(); DT:Refresh(addon.state)
pub = keysOf(addon.state.debufftracker)
ok(pub[1] ~= "hmark", "hmark = true -> not listed")
ok(DT.IsEntryEnabled("hmark") == false, "IsEntryEnabled(hmark) false")
ok(DT.IsEntryEnabled("scorpid") == true, "IsEntryEnabled(scorpid) true when explicitly on")
ok(DT.IsEntryEnabled("iswarm") == false, "IsEntryEnabled(iswarm) false by default")
ok(DT.IsEntryEnabled("jow") == true, "IsEntryEnabled(jow) true by default")
addon.db.profile.debuffTrackerDisabled = {}

-- Order: put ff first, custom entries ride along in the ordered list.
addon.db.profile.debuffTrackerOrder = { "ff", "creck" }
addon.db.profile.debuffTrackerCustom = "12345"
DT:InvalidateCatalog(); DT:Refresh(addon.state)
pub = keysOf(addon.state.debufftracker)
ok(pub[1] == "ff" and pub[2] == "creck", "stored order leads the published list")
ok(pub[#pub] == "custom:12345", "custom entry appended after the presets")
ok(eq(DT:GetOrderedKeys(), R({ "ff", "creck" }, (function()
  local k = catalogKeys(); k[#k + 1] = "custom:12345"; return k
end)())), "GetOrderedKeys = resolver over presets + customs (disabled ones included)")

-- A custom entry can be moved ahead of a preset.
addon.db.profile.debuffTrackerOrder = { "custom:12345" }
DT:InvalidateCatalog(); DT:Refresh(addon.state)
pub = keysOf(addon.state.debufftracker)
ok(pub[1] == "custom:12345", "a custom entry honours the stored order too")

--------------------------------------------------------------------------------
-- 4. Matching still works for the new entries.
--------------------------------------------------------------------------------
addon.db.profile.debuffTrackerOrder = {}
addon.db.profile.debuffTrackerCustom = ""
addon.db.profile.debuffTrackerDisabled = { scorpid = false, iswarm = false }
debuffs = { { name = "Scorpid Sting", spellId = 14277 }, { name = "Insect Swarm", spellId = 27013 } }
DT:InvalidateCatalog(); DT:Refresh(addon.state)
local present = {}
for _, e in ipairs(addon.state.debufftracker) do present[e.key] = e.present end
ok(present.scorpid == true, "Scorpid Sting on the target -> present")
ok(present.iswarm == true, "Insect Swarm on the target -> present")
ok(present.hmark == false, "Hunter's Mark absent -> missing")

ok(addon.Defaults.profile.debuffTrackerOrder ~= nil and #addon.Defaults.profile.debuffTrackerOrder == 0,
   "debuffTrackerOrder ships as an empty list")

print(("debuff_order_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
