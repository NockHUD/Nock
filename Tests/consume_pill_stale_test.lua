-- Tests/consume_pill_stale_test.lua
-- The eating / drinking records Modules/Auras.lua publishes for the pill
-- (state.player.eating / .drinking), driven through Core/AuraCache.lua's
-- incremental feed. Drink-walking (sit, sip a tick, run, repeat every two
-- seconds) applies and cancels the Drink aura over and over, often inside one
-- frame; the pill must follow every edge, and a record whose removal the
-- client never reported must fall away on its own once its channel would
-- have ended -- without waiting for the next aura event (2026-09-07 report:
-- a permanently stuck DRINKING pill).
-- Run from the repo root: luajit Tests/consume_pill_stale_test.lua

if jit and jit.off then jit.off() end

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local now = 1000
_G.GetTime = function() return now end
_G.UnitExists = function(unit) return unit == "player" end
_G.GetInventoryItemID = function() return nil end
_G.GetSpellInfo = function(id)
  if id == 430 then return "Drink" end
  if id == 433 then return "Food" end
  return "Spell " .. tostring(id)
end

-- A fake C_UnitAuras client (the same shape as Tests/aura_cache_test.lua).
local auras = { player = {}, pet = {}, target = {} }
local function aura(inst, name, id, dur, exp)
  return { auraInstanceID = inst, isHelpful = true, isHarmful = false, name = name,
           spellId = id, applications = 1, duration = dur, expirationTime = exp, icon = 1 }
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
  GetAuraDataByIndex = function(unit, i, filter) return sorted(unit, filter)[i] end,
  GetAuraDataByAuraInstanceID = function(unit, id) return auras[unit][id] end,
}

local Nock = { Constants = {}, modules = {} }
function Nock:NewModule(name)
  local m = { name = name }
  function m:RegisterMessage() end
  function m:RegisterEvent() end
  function m:SendMessage() end
  Nock.modules[name] = m
  return m
end
function Nock:SendMessage() end
_G.LibStub = setmetatable({}, { __call = function(_, lib, silent)
  if lib == "AceAddon-3.0" then return { GetAddon = function() return Nock end } end
  if silent then return nil end
  return {}
end })

dofile("Core/Constants.lua")
dofile("Config/Defaults.lua")
dofile("Core/State.lua")
dofile("Core/AuraCache.lua")
dofile("Modules/Auras.lua")
local AC    = Nock.AuraCache
local Auras = Nock.modules.Auras
local p     = Nock.state.player
Auras:OnEnable()

local function event(info) info.isFullUpdate = false; AC.OnUnitAura("player", info) end
local function drink(inst) return aura(inst, "Drink", 430, 30, now + 30) end

-- 1. A drink applied and cancelled in separate frames: the pill follows ------------
auras.player[1] = drink(1)
event({ addedAuras = { auras.player[1] } })
Auras:Refresh()
ok(p.drinking ~= nil and p.drinking.expirationTime == now + 30, "drink applied -> drinking record")
now = now + 1.5
auras.player[1] = nil
event({ removedAuraInstanceIDs = { 1 } })
Auras:Refresh()
ok(p.drinking == nil, "drink cancelled -> record gone")

-- 2. Drink-walking: ten cycles of sit / sip / run, every second cycle folded ---------
--    into one frame (added + removed in the same UNIT_AURA). Mid-cycle the
--    pill is up; after every cancel it is down; nothing lingers at the end.
local inst = 2
for cycle = 1, 10 do
  local a = drink(inst)
  if cycle % 2 == 0 then
    event({ addedAuras = { a }, removedAuraInstanceIDs = { inst } })
    Auras:Refresh()
    ok(p.drinking == nil, ("cycle %d (same frame): nothing left"):format(cycle))
  else
    auras.player[inst] = a
    event({ addedAuras = { a } })
    Auras:Refresh()
    ok(p.drinking ~= nil, ("cycle %d: DRINKING while sipping"):format(cycle))
    now = now + 1.5
    auras.player[inst] = nil
    event({ removedAuraInstanceIDs = { inst } })
    Auras:Refresh()
    ok(p.drinking == nil, ("cycle %d: gone on the run"):format(cycle))
  end
  now = now + 0.5
  inst = inst + 1
end
ok(AC.ByName("player", "Drink") == nil, "no Drink record survives the cycles")

-- 3. A missed removal: the record ends itself once the channel would have -----------
--    ended, with NO further aura event to move the cache revision.
local ghost = drink(50)
auras.player[50] = ghost
event({ addedAuras = { ghost } })
Auras:Refresh()
ok(p.drinking ~= nil, "ghost drink: DRINKING while its 30 s run")
now = now + 29
Auras:Refresh()
ok(p.drinking ~= nil, "ghost drink: still up a second before its expiry")
now = now + 1.1
Auras:Refresh()
ok(p.drinking == nil, "ghost drink: gone the tick after its expiry, no aura event needed")
-- and it stays gone on later ticks
now = now + 60
Auras:Refresh()
ok(p.drinking == nil, "ghost drink: stays gone")

-- 4. Same for the eating side --------------------------------------------------------
local ghostFood = aura(60, "Food", 433, 30, now + 30)
auras.player[60] = ghostFood
event({ addedAuras = { ghostFood } })
Auras:Refresh()
ok(p.eating ~= nil, "ghost food: EATING while its 30 s run")
now = now + 31
Auras:Refresh()
ok(p.eating == nil, "ghost food: gone after its expiry, no aura event needed")

print(("consume_pill_stale_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
