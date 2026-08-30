-- Modules/DebuffTracker.lua
-- Tracks a configurable set of TARGET debuffs. Curated preset
-- (Constants.DEBUFF_CURATED) seeds the defaults; the user can disable preset
-- entries and add their own by spell ID OR name. Writes the full ordered list
-- (each flagged present/missing) into state.debufftracker; the grid view shows
-- present ones in colour and missing ones desaturated + the missing highlight.
-- Mirrors Modules/BuffTracker.lua (target debuffs instead of unit buffs).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local DebuffTracker = Nock:NewModule("DebuffTracker", "AceEvent-3.0")
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

-- Aura reads go through Core/AuraCache.lua (every read allocates ~1.9 KB on
-- this client, and a raid boss carries the whole raid's debuffs): the store's
-- lookups replace the walk. Preset entries match by name list (rank-agnostic);
-- custom numeric entries by spellId; custom text entries by name. Returns
-- found, icon, count, duration, exp -- values, not a table.
local AC = Nock.AuraCache

local function findDebuffForEntry(entry)
  if not AC then return false end
  local a
  if entry.matchSpellId then
    a = AC.BySpell("target", entry.matchSpellId)
  elseif entry.names then
    for _, want in ipairs(entry.names) do
      a = AC.ByName("target", want)
      if a then break end
    end
  end
  if not a or not a.isHarmful then return false end
  return true, a.icon, a.applications or 0, a.duration or 0, a.expirationTime or 0
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
local _defaultOff   -- key -> true, built once off the curated list
local function entryDefaultOff(key)
  if not _defaultOff then
    _defaultOff = {}
    for _, e in ipairs(C.DEBUFF_CURATED or {}) do
      if e.defaultOff == true then _defaultOff[e.key] = true end
    end
  end
  return _defaultOff[key] == true
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

-- Built once and dropped on NOCK_VISUALS_CHANGED (the only time the profile
-- keys it reads can move): it used to allocate six scratch lists and re-parse
-- the custom string ten times a second.
local _catalog

local function effectiveCatalog()
  if _catalog then return _catalog end
  local p = Nock.db and Nock.db.profile
  local byKey, keys = allEntries()
  local list = {}
  for _, k in ipairs(DebuffTracker.ResolveOrder(p and p.debuffTrackerOrder, keys)) do
    if not isDisabled(k) then list[#list + 1] = byKey[k] end
  end
  _catalog = list
  return list
end

function DebuffTracker:InvalidateCatalog()
  _catalog = nil
end

-- Slow lane (Core:Tick) — see BuffTracker.lua. Target debuff depth is maximal
-- on a raid boss (the whole raid stacking debuffs), so this scan was the most
-- framerate-sensitive of the set.
DebuffTracker.refreshInterval = 0.1

local function trackerEnabled()
  local p = Nock.db and Nock.db.profile
  return not (p and p.debuffTrackerEnabled == false)
end

function DebuffTracker:OnEnable()
  if self.RegisterMessage then
    self:RegisterMessage("NOCK_VISUALS_CHANGED", "InvalidateCatalog")
  end
end

-- Rows reused in place (dest[i] keeps its table; rows past the count are
-- dropped); off (the shipped default) nothing is scanned or built.
function DebuffTracker:Refresh(state)
  local dest = state.debufftracker or {}
  state.debufftracker = dest
  if not trackerEnabled() then
    for i = #dest, 1, -1 do dest[i] = nil end
    return
  end

  local n = 0
  for _, entry in ipairs(effectiveCatalog()) do
    local found, icon, count, duration, exp = findDebuffForEntry(entry)
    n = n + 1
    local r = dest[n]
    if not r then r = {}; dest[n] = r end
    r.key            = entry.key
    r.label          = entry.label or (entry.names and entry.names[1]) or entry.key
    r.icon           = (found and icon) or resolveIcon(entry)
    r.present        = found
    r.count          = found and count or 0
    r.duration       = found and duration or 0
    r.expirationTime = found and exp or 0
  end
  for i = #dest, n + 1, -1 do dest[i] = nil end
end
