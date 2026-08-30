-- Tests/aura_cache_test.lua
-- Standalone LuaJIT tests for Core/AuraCache.lua: the incremental UNIT_AURA
-- feed (added / updated / removed / full update), the lazy rebuild, the
-- value-API fallback, the lookups and the rev counter.
-- Run from the repo root: luajit Tests/aura_cache_test.lua

if jit and jit.off then jit.off() end

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = {}
_G.LibStub = function() return { GetAddon = function() return Nock end } end
_G.UnitExists = function() return true end

-- A fake C_UnitAuras client: auras per unit keyed by instance id.
local auras = { player = {}, pet = {}, target = {} }
local reads = 0
local function aura(inst, helpful, name, id, count, dur, exp, src)
  return { auraInstanceID = inst, isHelpful = helpful, isHarmful = not helpful, name = name,
           spellId = id, applications = count or 1, duration = dur or 30, expirationTime = exp or 1030,
           sourceUnit = src, icon = 1, points = {} }
end
local function sorted(unit, filter)
  local out = {}
  for _, a in pairs(auras[unit]) do
    if (filter == "HELPFUL" and a.isHelpful) or (filter == "HARMFUL" and a.isHarmful) then out[#out + 1] = a end
  end
  table.sort(out, function(x, y) return x.auraInstanceID < y.auraInstanceID end)
  return out
end
_G.C_UnitAuras = {
  GetAuraDataByIndex = function(unit, i, filter)
    reads = reads + 1
    local a = sorted(unit, filter)[i]
    if not a then return nil end
    local c = {}; for k, v in pairs(a) do c[k] = v end   -- the client hands out a fresh table
    return c
  end,
  GetAuraDataByAuraInstanceID = function(unit, id)
    reads = reads + 1
    local a = auras[unit][id]
    if not a then return nil end
    local c = {}; for k, v in pairs(a) do c[k] = v end
    return c
  end,
}

dofile("Core/AuraCache.lua")
local AC = Nock.AuraCache
ok(AC.IsIncremental() == true, "incremental client detected")

-- 1. Lazy full rebuild on first read --------------------------------------------
auras.player[1] = aura(1, true, "Aspect of the Hawk", 27044)
auras.player[2] = aura(2, true, "Rapid Fire", 3045)
auras.player[3] = aura(3, false, "Dazed", 1604)
reads = 0
ok(AC.Count("player") == 3, "first read rebuilds: 3 auras")
ok(reads == 5, ("rebuild reads n+2 slots (got %d)"):format(reads))   -- 2 helpful + 1 harmful + 2 terminators
local r0 = AC.Rev("player")
ok(AC.BySpell("player", 3045).name == "Rapid Fire", "BySpell")
ok(AC.ByName("player", "Dazed").isHarmful == true, "ByName keeps the harmful flag")
reads = 0
AC.Count("player"); AC.Rev("player"); AC.ForEach("player", function() end)
ok(reads == 0, "clean reads cost no API calls")
ok(AC.Rev("player") == r0, "rev stable while nothing changes")

-- 2. Incremental: added (kept as the record), removed, updated ------------------
local added = aura(4, true, "Bloodlust", 2825)
auras.player[4] = added
reads = 0
AC.OnUnitAura("player", { isFullUpdate = false, addedAuras = { added } })
ok(reads == 0, "an added aura costs no read: the event's table is the record")
ok(AC.BySpell("player", 2825) == added, "the added record is the event's own table")
ok(AC.Rev("player") == r0 + 1, "rev moved on add")
auras.player[2] = nil
AC.OnUnitAura("player", { isFullUpdate = false, removedAuraInstanceIDs = { 2 } })
ok(AC.BySpell("player", 3045) == nil and AC.Count("player") == 3, "removed aura gone")
auras.player[1].applications = 5
reads = 0
AC.OnUnitAura("player", { isFullUpdate = false, updatedAuraInstanceIDs = { 1 } })
ok(reads == 1, "an updated aura is re-read once")
ok(AC.BySpell("player", 27044).applications == 5, "updated record replaced")
AC.OnUnitAura("player", { isFullUpdate = false, removedAuraInstanceIDs = { 99 } })
local r1 = AC.Rev("player")
AC.OnUnitAura("player", { isFullUpdate = false })
ok(AC.Rev("player") == r1, "an empty update does not move rev")

-- 3. Full update flag / invalidate -> dirty, rebuilt on next read ----------------
auras.player[7] = aura(7, true, "Ferocious Inspiration", 34456)
AC.OnUnitAura("player", { isFullUpdate = true })
reads = 0
ok(AC.BySpell("player", 34456) ~= nil, "isFullUpdate -> rebuilt on read")
ok(reads > 0, "the rebuild read the client")
-- incremental info while dirty is dropped, the rebuild has the truth
AC.Invalidate("player")
auras.player[8] = aura(8, true, "Nazgrel's Fervor", 39913)
AC.OnUnitAura("player", { isFullUpdate = false, addedAuras = { auras.player[8] } })
ok(AC.BySpell("player", 39913) ~= nil, "add while dirty: the rebuild still finds it")

-- 4. Duplicate names: earliest applied wins -------------------------------------
auras.target[5] = aura(5, false, "Hunter's Mark", 14325, 1, 120, 1120, "raid7")
auras.target[3] = aura(3, false, "Hunter's Mark", 14325, 1, 120, 1120, "player")
AC.Invalidate("target")
ok(AC.ByName("target", "Hunter's Mark").sourceUnit == "player", "lowest instance id wins for a duplicate name")

-- 5. ForEach sees every record, no allocation --------------------------------------
local n = 0
AC.ForEach("target", function(a) n = n + 1 end)
ok(n == 2, "ForEach visits both")
collectgarbage("collect"); collectgarbage("stop")
local a0 = collectgarbage("count")
for _ = 1, 500 do AC.ForEach("player", function(a) end); AC.BySpell("player", 27044); AC.Rev("target") end
local kb = collectgarbage("count") - a0
collectgarbage("restart")
ok(kb < 40, ("500 rounds of reads allocate < 40 KB (got %.1f; the closure per round is the test's)"):format(kb))

-- 6. Fallback: no C_UnitAuras -> UnitBuff/UnitDebuff records, dirty-flag driven ----
_G.C_UnitAuras = nil
_G.UnitBuff = function(unit, i)
  if unit == "pet" and i == 1 then return "Mend Pet", 2, 1, "Magic", 15, 1015, "player", false, false, 27046 end
  return nil
end
_G.UnitDebuff = function() return nil end
ok(AC.IsIncremental() == false, "fallback detected")
AC.Invalidate("pet")
local m = AC.ByName("pet", "Mend Pet")
ok(m and m.spellId == 27046 and m.isHelpful == true and m.applications == 1 and m.expirationTime == 1015, "fallback record has the AuraData shape")
AC.OnUnitAura("pet", nil)
_G.UnitBuff = function() return nil end
ok(AC.ByName("pet", "Mend Pet") == nil, "fallback: UNIT_AURA without updateInfo dirties -> rebuilt")

print(("aura_cache_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
