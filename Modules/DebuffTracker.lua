-- Modules/DebuffTracker.lua
-- Tracks a configurable set of TARGET debuffs. Curated preset
-- (Constants.DEBUFF_CURATED) seeds the defaults; the user can disable preset
-- entries and add their own by spell ID OR name. Writes the full ordered list
-- (each flagged present/missing) into state.debufftracker; the grid view shows
-- present ones in colour and missing ones desaturated + the missing highlight.
-- Mirrors Modules/BuffTracker.lua (target debuffs instead of unit buffs).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local DebuffTracker = Nock:NewModule("DebuffTracker")
local C = Nock.Constants

DebuffTracker.Catalog = C.DEBUFF_CURATED  -- exposed for the options injector

local function spellIcon(id)
  if GetSpellInfo then
    local _, _, icon = GetSpellInfo(id)
    if icon then return icon end
  end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  return nil
end

-- Scan target debuffs. Preset entries match by name list (rank-agnostic);
-- custom numeric entries match by spellId; custom text entries by name.
local function findDebuffForEntry(entry)
  if not (UnitExists and UnitExists("target") and UnitDebuff) then return nil end
  for i = 1, 40 do
    local name, icon, count, _, duration, expirationTime, _, _, _, spellId = UnitDebuff("target", i)
    if not name then return nil end
    if entry.matchSpellId then
      if spellId == entry.matchSpellId then
        return { icon = icon, count = count or 0, duration = duration or 0, expirationTime = expirationTime or 0 }
      end
    elseif entry.names then
      for _, want in ipairs(entry.names) do
        if name == want then
          return { icon = icon, count = count or 0, duration = duration or 0, expirationTime = expirationTime or 0 }
        end
      end
    end
  end
  return nil
end

-- Lazy icon resolution (GetSpellInfo may not be cached right at login).
local function resolveIcon(entry)
  if entry._iconResolved then return entry._iconResolved end
  for _, id in ipairs(entry.spellIds or {}) do
    local icon = spellIcon(id)
    if icon then entry._iconResolved = icon; return icon end
  end
  entry._iconResolved = entry.fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
  return entry._iconResolved
end

-- Enabled state is tri-state in profile.debuffTrackerDisabled: true = off,
-- false = explicitly on, nil = the entry's own default (OFF for a preset
-- marked `defaultOff`, ON otherwise). "Restore preset defaults" wipes the map,
-- which puts a default-off preset back OFF — the only way an opt-in entry
-- stays opt-in across a reset. Custom entries have no default-off.
local function entryDefaultOff(key)
  for _, e in ipairs(C.DEBUFF_CURATED or {}) do
    if e.key == key then return e.defaultOff == true end
  end
  return false
end

function DebuffTracker.IsEntryEnabled(key)
  local p = Nock.db and Nock.db.profile
  local t = p and p.debuffTrackerDisabled
  local v = t and t[key]
  if v == true then return false end
  if v == false then return true end
  return not entryDefaultOff(key)
end

local function isDisabled(key) return not DebuffTracker.IsEntryEnabled(key) end

-- Pure: the stored order (profile.debuffTrackerOrder) first — unknown and
-- duplicate keys dropped — then every eligible key not yet placed, in the
-- order given. Same contract as Cooldowns:GetOrderedGridKeys.
function DebuffTracker.ResolveOrder(stored, eligible)
  local set, ordered, seen = {}, {}, {}
  for _, k in ipairs(eligible) do set[k] = true end
  if type(stored) == "table" then
    for _, k in ipairs(stored) do
      if set[k] and not seen[k] then ordered[#ordered + 1] = k; seen[k] = true end
    end
  end
  for _, k in ipairs(eligible) do
    if not seen[k] then ordered[#ordered + 1] = k; seen[k] = true end
  end
  return ordered
end

-- Custom entries: split on comma / newline only (names may contain spaces).
-- A numeric token → match by spellId; anything else → match by exact name.
local function parseCustom(str)
  local out = {}
  if not str or str == "" then return out end
  for token in tostring(str):gmatch("[^,\r\n]+") do
    local t = token:gsub("^%s*(.-)%s*$", "%1")
    if t ~= "" then
      local id = tonumber(t)
      if id then
        out[#out + 1] = {
          key = "custom:" .. id, label = "Spell " .. id,
          matchSpellId = id, spellIds = { id },
          fallbackIcon = spellIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark",
        }
      else
        out[#out + 1] = {
          key = "custom:" .. t, label = t, names = { t },
          fallbackIcon = "Interface\\Icons\\INV_Misc_QuestionMark",
        }
      end
    end
  end
  return out
end

-- Every entry the tracker knows (presets + customs), keyed, in catalog order.
local function allEntries()
  local p = Nock.db and Nock.db.profile
  local byKey, keys = {}, {}
  for _, entry in ipairs(C.DEBUFF_CURATED or {}) do
    byKey[entry.key] = entry; keys[#keys + 1] = entry.key
  end
  for _, e in ipairs(parseCustom(p and p.debuffTrackerCustom)) do
    if not byKey[e.key] then byKey[e.key] = e; keys[#keys + 1] = e.key end
  end
  return byKey, keys
end

-- The full ordered key list, DISABLED keys included (the options page lists
-- everything and moves them); the engine filters below.
function DebuffTracker:GetOrderedKeys()
  local p = Nock.db and Nock.db.profile
  local _, keys = allEntries()
  return DebuffTracker.ResolveOrder(p and p.debuffTrackerOrder, keys)
end

-- Label for a key the way the options page names it (custom keys are self-describing).
function DebuffTracker:Describe(key)
  local byKey = allEntries()
  local e = byKey[key]
  return e and (e.label or (e.names and e.names[1])) or key
end

local function effectiveCatalog()
  local p = Nock.db and Nock.db.profile
  local byKey, keys = allEntries()
  local list = {}
  for _, k in ipairs(DebuffTracker.ResolveOrder(p and p.debuffTrackerOrder, keys)) do
    if not isDisabled(k) then list[#list + 1] = byKey[k] end
  end
  return list
end

-- Slow lane (Core:Tick) — see BuffTracker.lua. Target debuff depth is maximal
-- on a raid boss (the whole raid stacking debuffs), so this scan was the most
-- framerate-sensitive of the set.
DebuffTracker.refreshInterval = 0.1

function DebuffTracker:Refresh(state)
  local dest = state.debufftracker or {}
  state.debufftracker = dest
  for k in pairs(dest) do dest[k] = nil end

  for _, entry in ipairs(effectiveCatalog()) do
    local info = findDebuffForEntry(entry)
    dest[#dest + 1] = {
      key            = entry.key,
      label          = entry.label or (entry.names and entry.names[1]) or entry.key,
      icon           = (info and info.icon) or resolveIcon(entry),
      present        = info ~= nil,
      count          = info and info.count or 0,
      duration       = info and info.duration or 0,
      expirationTime = info and info.expirationTime or 0,
    }
  end
end
