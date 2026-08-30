-- Tests/perf_churn_test.lua
-- Standalone LuaJIT tests for the raid-memory batch (2026-08-30): the
-- producers that filled the addon's memory figure between GC cycles in a
-- 25-man are measured for ALLOCATION, not just behaviour. With the collector
-- stopped, collectgarbage("count") across N calls is exactly what those calls
-- allocated; a scan that reuses its records reads ~0 KB.
-- Run from the repo root: luajit Tests/perf_churn_test.lua

-- LuaJIT's trace objects are GC-allocated and would read as "garbage" here.
if jit and jit.off then jit.off() end

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- KB allocated by fn() over n calls, collector stopped for the measurement.
local function kbFor(n, fn)
  collectgarbage("collect")
  collectgarbage("stop")
  local a = collectgarbage("count")
  for _ = 1, n do fn() end
  local b = collectgarbage("count")
  collectgarbage("restart")
  return b - a
end

--------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------
local Nock = { Constants = {}, state = {}, modules = {} }
function Nock:NewModule(name)
  local m = { name = name }
  function m:RegisterEvent() end
  function m:RegisterMessage() end
  function m:SendMessage() end
  function m:GetName() return name end
  Nock.modules[name] = m
  return m
end
function Nock:GetModule(name) return Nock.modules[name] end
function Nock:SendMessage() end
function Nock:Print() end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
_G.GetTime = function() return 1000 end
_G.GetSpellInfo = function(id) return "Spell " .. id, nil, "icon-" .. id end
_G.C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. id } end,
               GetSpellTexture = function() return "icon" end }
_G.GetSpellCooldown = function() return 0, 0 end
_G.GetItemInfo = function() return nil end
_G.GetItemCount = function() return 0 end
_G.GetInventoryItemCooldown = function() return 0, 0 end
_G.GetInventoryItemID = function() return 1 end
_G.GetTalentTabInfo = function() return nil end
_G.UnitRace = function() return "Orc", "Orc" end
_G.UnitName = function() return "Tester" end
_G.UnitExists = function() return true end
_G.UnitIsDead = function() return false end
_G.IsUsableSpell = function() return true, false end
_G.GetInventoryItemLink = function() return nil end
_G.GetWeaponEnchantInfo = function() return false end
_G.UnitCreatureType = function() return "Humanoid" end
_G.IsInInstance = function() return true, "raid" end

-- Every aura read costs ~1.9 KB in-game, so the count of slot reads IS the
-- cost. The mocks count them; no C_UnitAuras here (the store's fallback path).
local reads = 0

-- A raid-buffed hunter (30 buffs incl. an aspect, Rapid Fire, Bloodlust) and
-- a boss with 35 debuffs incl. Hunter's Mark from the player.
local buffs, debuffs = {}, {}
for i = 1, 30 do buffs[i] = { name = "Buff " .. i, id = 50000 + i } end
_G.UnitBuff = function(unit, i)
  reads = reads + 1
  local b = buffs[i]
  if not b then return nil end
  return b.name, "icon", 1, "Magic", 30, 1030, unit, false, false, b.id
end
for i = 1, 35 do debuffs[i] = { name = "Debuff " .. i, id = 60000 + i } end
_G.UnitDebuff = function(unit, i)
  reads = reads + 1
  local d = debuffs[i]
  if not d then return nil end
  return d.name, "icon", 1, "Magic", 30, 1030, "player", false, false, d.id
end
_G.UnitAura = _G.UnitBuff

dofile("Core/Constants.lua")
dofile("Config/Defaults.lua")
dofile("Core/State.lua")
dofile("Core/AuraCache.lua")
local AC = Nock.AuraCache
local C = Nock.Constants
local st = Nock.state
Nock.db = { profile = {} }
for k, v in pairs(Nock.Defaults.profile) do Nock.db.profile[k] = v end

--------------------------------------------------------------------------------
-- 1. Auras: records reused, UnitBuff preferred, ~0 KB per scan
--------------------------------------------------------------------------------
dofile("Modules/Auras.lua")
local au = Nock.modules.Auras
au.aspectKeyByName = { ["Aspect of the Hawk"] = "hawk" }
au.huntersMarkName = "Hunter's Mark"
au.dazedName, au.satedName, au.exhaustionName = "Dazed", "Sated", "Exhaustion"
buffs[3] = { name = "Aspect of the Hawk", id = C.SpellID.ASPECT_HAWK }
buffs[7] = { name = "Rapid Fire", id = C.SpellID.RAPID_FIRE }
debuffs[20] = { name = "Hunter's Mark", id = C.SpellID.HUNTERS_MARK }

au:ScanAll()
ok(st.player.aspect and st.player.aspect.aspectKey == "hawk", "Auras: aspect found")
ok(st.player.rapidFire == true, "Auras: Rapid Fire flag")
ok(st.target.huntersMark and st.target.huntersMark.fromPlayer == true, "Auras: Hunter's Mark found, from player")
local aspect1, mark1 = st.player.aspect, st.target.huntersMark
au:ScanAll()
ok(st.player.aspect == aspect1, "Auras: the aspect record is reused across scans")
ok(st.target.huntersMark == mark1, "Auras: the mark record is reused across scans")
reads = 0
local kb = kbFor(200, function() au:ScanAll() end)
ok(kb < 2, ("Auras: 200 scans allocate < 2 KB (got %.2f)"):format(kb))
ok(reads == 0, ("Auras: 200 scans read no aura slot (got %d)"):format(reads))
debuffs[20] = { name = "Debuff 20", id = 60020 }
AC.Invalidate("target"); au:ScanAll()
ok(st.target.huntersMark == nil, "Auras: mark gone -> nil published")
buffs[3] = { name = "Buff 3", id = 50003 }
AC.Invalidate("player"); au:ScanAll()
ok(st.player.aspect == nil, "Auras: aspect gone -> nil published")
buffs[3] = { name = "Aspect of the Hawk", id = C.SpellID.ASPECT_HAWK }
debuffs[20] = { name = "Hunter's Mark", id = C.SpellID.HUNTERS_MARK }
AC.Invalidate()

-- The store's revision: a clean tick does nothing, an aura event on the
-- player or the target rescans on the next slow-lane tick.
au:Refresh()
st.player.aspect = nil
au:Refresh()
ok(st.player.aspect == nil, "Auras: a clean tick does not rescan")
AC.OnUnitAura("raid7", nil)
au:Refresh()
ok(st.player.aspect == nil, "Auras: another unit's UNIT_AURA does not move the store")
AC.OnUnitAura("player", nil)
au:Refresh()
ok(st.player.aspect ~= nil, "Auras: the player's UNIT_AURA -> the next slow-lane tick scans")
ok(au.refreshInterval == 0.1, "Auras: on the slow lane")

--------------------------------------------------------------------------------
-- 2. Cooldowns: no per-buff tables, UnitBuff preferred, dirty-flagged
--------------------------------------------------------------------------------
dofile("Modules/Cooldowns.lua")
local cd = Nock.modules.Cooldowns
cd:RebuildLists()
cd:Refresh()   -- the first read
cd:ScanAuras()
ok(st.cooldowns.RF.procActive == true, "Cooldowns: Rapid Fire buff -> RF procActive")
ok(st.cooldowns.RF.buffDuration == 30 and st.cooldowns.RF.buffStartTime == 1000, "Cooldowns: RF buff timing from the flat maps")
kb = kbFor(200, function() cd:ScanAuras() end)
ok(kb < 2, ("Cooldowns: 200 aura scans allocate < 2 KB (got %.2f)"):format(kb))
kb = kbFor(200, function() cd:ScanCooldowns() end)
ok(kb < 2, ("Cooldowns: 200 cooldown scans allocate < 2 KB (got %.2f)"):format(kb))
ok(cd.refreshInterval == 0.1, "Cooldowns: on the slow lane")
buffs[7] = { name = "Buff 7", id = 50007 }
cd:Refresh()
ok(st.cooldowns.RF.procActive == true, "Cooldowns: clean tick -> no rescan")
AC.OnUnitAura("player", nil)
cd:Refresh()
ok(st.cooldowns.RF.procActive == false, "Cooldowns: player UNIT_AURA -> the next tick rescans")

--------------------------------------------------------------------------------
-- 3. Buff/DebuffTracker: off = nothing built; on = rows reused, ~0 KB
--------------------------------------------------------------------------------
dofile("Modules/BuffTracker.lua")
dofile("Modules/DebuffTracker.lua")
local bt, dt = Nock.modules.BuffTracker, Nock.modules.DebuffTracker
Nock.db.profile.buffTrackerEnabled = false
Nock.db.profile.debuffTrackerEnabled = false
bt:Refresh(st); dt:Refresh(st)
ok(#st.bufftracker.player == 0 and #st.bufftracker.pet == 0, "BuffTracker off -> empty lists")
ok(#st.debufftracker == 0, "DebuffTracker off -> empty list")
kb = kbFor(200, function() bt:Refresh(st); dt:Refresh(st) end)
ok(kb < 1, ("trackers off: 200 refreshes allocate < 1 KB (got %.2f)"):format(kb))

Nock.db.profile.buffTrackerEnabled = true
Nock.db.profile.debuffTrackerEnabled = true
Nock.db.profile.debuffTrackerDisabled = { scorpid = false, iswarm = false }
debuffs[5] = { name = "Scorpid Sting", id = 3043 }
AC.Invalidate("target")
bt:InvalidateCatalog(); dt:InvalidateCatalog()
bt:Refresh(st); dt:Refresh(st)
ok(#st.bufftracker.player > 0, "BuffTracker on -> rows")
ok(#st.debufftracker > 0, "DebuffTracker on -> rows")
local present = {}
for _, r in ipairs(st.debufftracker) do present[r.key] = r.present end
ok(present.scorpid == true, "DebuffTracker: Scorpid Sting present via the shared index")
local row1, drow1 = st.bufftracker.player[1], st.debufftracker[1]
bt:Refresh(st); dt:Refresh(st)
ok(st.bufftracker.player[1] == row1, "BuffTracker: rows reused")
ok(st.debufftracker[1] == drow1, "DebuffTracker: rows reused")
reads = 0
kb = kbFor(200, function() bt:Refresh(st); dt:Refresh(st) end)
ok(kb < 2, ("trackers on: 200 refreshes allocate < 2 KB (got %.2f)"):format(kb))
ok(reads == 0, ("trackers on: 200 refreshes read no aura slot (got %d)"):format(reads))
-- The catalog follows the profile through the invalidation the option
-- setters broadcast (NOCK_VISUALS_CHANGED).
Nock.db.profile.debuffTrackerDisabled.scorpid = true
dt:InvalidateCatalog(); dt:Refresh(st)
present = {}
for _, r in ipairs(st.debufftracker) do present[r.key] = true end
ok(present.scorpid == nil, "DebuffTracker: a disabled entry leaves after invalidation")

--------------------------------------------------------------------------------
-- 4. Helpers: slow lane, rows reused
--------------------------------------------------------------------------------
Nock.IsInInstance = function() return true end
Nock.IsInRaidInstance = function() return true end
dofile("Core/ConsumeData.lua")
dofile("Modules/Helpers.lua")
local hp = Nock.modules.Helpers
st.helpers = st.helpers or {}
st.player.inCombat = false
hp:Refresh(st)
ok(hp.refreshInterval == 0.1, "Helpers: on the slow lane")
ok(#st.helpers > 0, "Helpers: badges surface in an instance out of combat")
local h1 = st.helpers[1]
hp:Refresh(st)
ok(st.helpers[1] == h1, "Helpers: rows reused")
reads = 0
kb = kbFor(200, function() hp:Refresh(st) end)
ok(kb < 2, ("Helpers: 200 refreshes allocate < 2 KB (got %.2f)"):format(kb))
ok(reads == 0, ("Helpers: 200 refreshes read no aura slot (got %d)"):format(reads))

print(("perf_churn_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
