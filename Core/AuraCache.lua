-- Core/AuraCache.lua
-- The one aura store for the player, the pet and the target: every module
-- that used to walk UnitBuff/UnitDebuff reads it instead.
--
-- Why (2026-08-30): on this client every aura READ allocates ~1.9 KB, whatever
-- the function (UnitBuff, UnitAura, C_UnitAuras.*), and an empty slot costs
-- nothing -- so a walk costs n x 1.9 KB, and a dozen modules walking 30 buffs
-- and 40 boss debuffs ten times a second was the "Nock uses 100 MB in Black
-- Temple" report. UNIT_AURA here is INCREMENTAL (updateInfo: addedAuras carry
-- complete AuraData, updated/removed carry instance ids), so the store pays
-- 1.9 KB per aura that CHANGES: the added records are kept as they arrive
-- (already allocated by the event), an updated one is re-read once, a removed
-- one is dropped. A full rebuild (target switch, pet swap, isFullUpdate) is
-- lazy -- the first reader after the change pays for it.
--
-- Records are the client's AuraData tables (name, icon, applications, duration,
-- expirationTime, sourceUnit, spellId, isHelpful, isHarmful, auraInstanceID,
-- points ...). Without C_UnitAuras (older client, headless tests) the fallback
-- builds records of the same shape from UnitBuff/UnitDebuff on a dirty flag.
--
-- API (all take a unit token "player" | "pet" | "target"):
--   AuraCache.Rev(unit)          -> integer; moves whenever the unit's auras change
--   AuraCache.ForEach(unit, fn)  -> fn(record) per aura, any order, no allocation
--   AuraCache.BySpell(unit, id)  -> record or nil (the earliest applied wins)
--   AuraCache.ByName(unit, name) -> record or nil
--   AuraCache.Count(unit)        -> number of auras
--   AuraCache.Invalidate(unit)   -> force a rebuild (nil = every unit)

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local AC = {}
Nock.AuraCache = AC

local UNITS = { "player", "pet", "target" }
local stores = {}

local function newStore(unit)
  return { unit = unit, byInstance = {}, bySpell = {}, byName = {}, rev = 0, n = 0, dirty = true }
end
for _, u in ipairs(UNITS) do stores[u] = newStore(u) end

local function wipe(t) for k in pairs(t) do t[k] = nil end end
local FILTERS = { "HELPFUL", "HARMFUL" }

-- The lookups, rebuilt in place from the records. "First applied wins" for a
-- duplicate name/spell: the lowest instance id, which is what a UnitBuff walk
-- in slot order returned.
local function reindex(st)
  wipe(st.bySpell)
  wipe(st.byName)
  local n = 0
  for _, a in pairs(st.byInstance) do
    n = n + 1
    local id, name, inst = a.spellId, a.name, a.auraInstanceID or 0
    if id then
      local cur = st.bySpell[id]
      if not cur or inst < (cur.auraInstanceID or 0) then st.bySpell[id] = a end
    end
    if name then
      local cur = st.byName[name]
      if not cur or inst < (cur.auraInstanceID or 0) then st.byName[name] = a end
    end
  end
  st.n = n
  st.rev = st.rev + 1
end

-- Fallback record from the value-returning API (same field names as AuraData).
local function record(inst, helpful, name, icon, count, _, duration, expirationTime, source, _, _, spellId)
  return {
    auraInstanceID = inst, name = name, icon = icon, applications = count or 0,
    duration = duration or 0, expirationTime = expirationTime or 0, sourceUnit = source,
    spellId = spellId, isHelpful = helpful, isHarmful = not helpful,
  }
end

local function rebuild(st)
  local unit = st.unit
  wipe(st.byInstance)
  st.dirty = false
  -- The player always exists; the pet and the target only sometimes.
  if unit ~= "player" and not (UnitExists and UnitExists(unit)) then reindex(st); return end
  local CU = C_UnitAuras
  if CU and CU.GetAuraDataByIndex then
    for _, filter in ipairs(FILTERS) do
      local i = 1
      while true do
        local a = CU.GetAuraDataByIndex(unit, i, filter)
        if not a then break end
        st.byInstance[a.auraInstanceID or (filter .. i)] = a
        i = i + 1
      end
    end
  else
    if UnitBuff then
      local i = 1
      while true do
        local name = UnitBuff(unit, i)
        if not name then break end
        st.byInstance[i] = record(i, true, UnitBuff(unit, i))
        i = i + 1
      end
    end
    if UnitDebuff then
      local i = 1
      while true do
        local name = UnitDebuff(unit, i)
        if not name then break end
        st.byInstance[100000 + i] = record(100000 + i, false, UnitDebuff(unit, i))
        i = i + 1
      end
    end
  end
  reindex(st)
end

local function ensure(unit)
  local st = stores[unit]
  if not st then return nil end
  if st.dirty then rebuild(st) end
  return st
end

-- Incremental feed. Without updateInfo (or with a full update flagged) the
-- store goes dirty and the next reader rebuilds it. Incremental info that
-- arrives while a rebuild is pending is dropped: the rebuild reads the truth.
function AC.OnUnitAura(unit, info)
  local st = stores[unit]
  if not st then return end
  local CU = C_UnitAuras
  if type(info) ~= "table" or info.isFullUpdate or not (CU and CU.GetAuraDataByAuraInstanceID) then
    st.dirty = true
    return
  end
  if st.dirty then return end
  local byInstance, changed = st.byInstance, false
  local removed = info.removedAuraInstanceIDs
  if removed then
    for i = 1, #removed do
      local id = removed[i]
      if byInstance[id] then byInstance[id] = nil; changed = true end
    end
  end
  local added = info.addedAuras
  if added then
    for i = 1, #added do
      local a = added[i]
      if a and a.auraInstanceID then byInstance[a.auraInstanceID] = a; changed = true end
    end
  end
  local updated = info.updatedAuraInstanceIDs
  if updated then
    for i = 1, #updated do
      local id = updated[i]
      local a = CU.GetAuraDataByAuraInstanceID(unit, id)
      byInstance[id] = a or nil
      changed = true
    end
  end
  if changed then reindex(st) end
end

function AC.Invalidate(unit)
  if unit then
    local st = stores[unit]
    if st then st.dirty = true end
  else
    for _, st in pairs(stores) do st.dirty = true end
  end
end

function AC.Rev(unit)
  local st = ensure(unit)
  return st and st.rev or 0
end

function AC.Count(unit)
  local st = ensure(unit)
  return st and st.n or 0
end

function AC.ForEach(unit, fn)
  local st = ensure(unit)
  if not st then return end
  for _, a in pairs(st.byInstance) do fn(a) end
end

function AC.BySpell(unit, spellId)
  local st = ensure(unit)
  return st and spellId and st.bySpell[spellId] or nil
end

function AC.ByName(unit, name)
  local st = ensure(unit)
  return st and name and st.byName[name] or nil
end

-- True when the client feeds the store incrementally (the cheap path).
function AC.IsIncremental()
  return (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) and true or false
end

-- Events: unit-filtered UNIT_AURA for the three units, and the edges that
-- replace a unit wholesale. Bare frames; nothing here runs per frame.
if CreateFrame then
  local function onEvent(_, event, unit, info)
    if event == "UNIT_AURA" then
      AC.OnUnitAura(unit, info)
    elseif event == "PLAYER_TARGET_CHANGED" then
      AC.Invalidate("target")
    elseif event == "UNIT_PET" then
      if unit == "player" then AC.Invalidate("pet") end
    else
      AC.Invalidate()
    end
  end
  local f = CreateFrame("Frame")
  f:SetScript("OnEvent", onEvent)
  if f.RegisterUnitEvent then
    f:RegisterUnitEvent("UNIT_AURA", "player", "pet")
    local g = CreateFrame("Frame")
    g:SetScript("OnEvent", onEvent)
    g:RegisterUnitEvent("UNIT_AURA", "target")
    local h = CreateFrame("Frame")
    h:SetScript("OnEvent", onEvent)
    h:RegisterUnitEvent("UNIT_PET", "player")
  else
    f:RegisterEvent("UNIT_AURA")
    f:RegisterEvent("UNIT_PET")
  end
  f:RegisterEvent("PLAYER_TARGET_CHANGED")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
end
