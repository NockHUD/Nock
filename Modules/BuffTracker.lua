-- Modules/BuffTracker.lua
-- Configurable raid-buff checklist for hunter + pet. A built-in preset
-- (PlayerCatalog / PetCatalog) seeds the defaults; the user can disable
-- individual preset entries and add their own spell IDs via the settings UI.
-- Effective list = (enabled preset entries) + (custom spell-ID entries).
-- Writes active/missing + remaining time into state.bufftracker.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local BuffTracker = Nock:NewModule("BuffTracker", "AceEvent-3.0")

local function spellIcon(id)
  if GetSpellInfo then
    local _, _, icon = GetSpellInfo(id)
    if icon then return icon end
  end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  return nil
end

local function spellName(id)
  if GetSpellInfo then
    local n = GetSpellInfo(id)
    if n then return n end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id)
    if i then return i.name end
  end
  return nil
end

-- Aura reads go through Core/AuraCache.lua (every read allocates ~1.9 KB on
-- this client): the store's lookups replace the per-unit index this module
-- used to build with its own walk. "First applied wins" is the store's rule.
local AC = Nock.AuraCache

-- The first buff matching the entry + whether to use that buff's own icon.
-- Name-matched preset entries keep falling back to the catalog's resolved
-- icon (rank-agnostic), exactly as before; spellId matches use the live icon.
local function matchRecord(unit, entry)
  if not AC then return nil, false end
  if entry.matchSpellIds then
    for _, want in ipairs(entry.matchSpellIds) do
      local a = AC.BySpell(unit, want)
      if a and not a.isHarmful then return a, true end
    end
  elseif entry.matchSpellId then
    local a = AC.BySpell(unit, entry.matchSpellId)
    if a and not a.isHarmful then return a, true end
  elseif entry.names then
    for _, want in ipairs(entry.names) do
      local a = AC.ByName(unit, want)
      if a and not a.isHarmful then return a, false end
    end
  end
  return nil, false
end

-- Returns found, icon, count, duration, exp -- values, not a table (a table
-- per present buff per refresh was ~15 of them ten times a second).
local function findBuffForEntry(unit, entry)
  local a, useIcon = matchRecord(unit, entry)
  if not a then return false end
  return true, useIcon and a.icon or nil, a.applications or 0, a.duration or 0, a.expirationTime or 0
end

local function isParseMode()
  local p = Nock.db and Nock.db.profile
  return p and (p.parseMode ~= false)
end

-- Lazy icon resolution (GetSpellInfo may not be cached right at login).
local function resolveIcon(entry)
  if entry._iconResolved then return entry._iconResolved end
  for _, id in ipairs(entry.spellIds or {}) do
    local icon = spellIcon(id)
    if icon then entry._iconResolved = icon; return icon end
  end
  entry._iconResolved = entry.fallbackIcon
  return entry._iconResolved
end

-- Built-in preset for the hunter.
BuffTracker.PlayerCatalog = {
  { key = "fort",       label = "Fortitude",      names = { "Power Word: Fortitude", "Prayer of Fortitude" },
    spellIds = { 25389, 48162 }, fallbackIcon = "Interface\\Icons\\Spell_Holy_WordFortitude" },
  { key = "wild",       label = "Mark of the Wild", names = { "Mark of the Wild", "Gift of the Wild" },
    spellIds = { 26990, 26991 }, fallbackIcon = "Interface\\Icons\\Spell_Nature_Regeneration" },
  { key = "kings",      label = "Kings",          names = { "Blessing of Kings", "Greater Blessing of Kings" },
    spellIds = { 20217, 25898 }, fallbackIcon = "Interface\\Icons\\Spell_Magic_MageArmor" },
  { key = "might",      label = "Might",          names = { "Blessing of Might", "Greater Blessing of Might" },
    spellIds = { 25291, 25782 }, fallbackIcon = "Interface\\Icons\\Spell_Holy_FistOfJustice" },
  { key = "salv",       label = "Salvation",      names = { "Blessing of Salvation", "Greater Blessing of Salvation" },
    spellIds = { 1038, 25895 },  fallbackIcon = "Interface\\Icons\\Spell_Holy_SealOfSalvation" },
  { key = "shout",      label = "Battle Shout",   names = { "Battle Shout" },
    spellIds = { 25289 },        fallbackIcon = "Interface\\Icons\\Ability_Warrior_RallyingCry" },
  { key = "intel",      label = "Intellect",      names = { "Arcane Intellect", "Arcane Brilliance" },
    spellIds = { 27126, 23028 }, fallbackIcon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
  { key = "shadowprot", label = "Shadow Prot.",   names = { "Shadow Protection", "Prayer of Shadow Protection" },
    spellIds = { 25433, 39374 }, fallbackIcon = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
  -- (Trueshot Aura intentionally not tracked.)
  { key = "scrollAgi",  label = "Scroll: Agi",    parseOnly = true, selfApplied = true,
    matchSpellIds = { 33077, 12174 }, spellIds = { 33077, 12174 },
    fallbackIcon = "Interface\\Icons\\INV_Scroll_03" },
  { key = "scrollStr",  label = "Scroll: Str",    parseOnly = true, selfApplied = true,
    matchSpellIds = { 33082, 12179 }, spellIds = { 33082, 12179 },
    fallbackIcon = "Interface\\Icons\\INV_Scroll_05" },
}

-- Pet preset. Scroll entries only count when Parse Mode is on.
BuffTracker.PetCatalog = {
  { key = "fort",       label = "Fortitude",      names = { "Power Word: Fortitude", "Prayer of Fortitude" },
    spellIds = { 25389, 48162 }, fallbackIcon = "Interface\\Icons\\Spell_Holy_WordFortitude" },
  { key = "wild",       label = "Mark of the Wild", names = { "Mark of the Wild", "Gift of the Wild" },
    spellIds = { 26990, 26991 }, fallbackIcon = "Interface\\Icons\\Spell_Nature_Regeneration" },
  { key = "kings",      label = "Kings",          names = { "Blessing of Kings", "Greater Blessing of Kings" },
    spellIds = { 20217, 25898 }, fallbackIcon = "Interface\\Icons\\Spell_Magic_MageArmor" },
  { key = "might",      label = "Might",          names = { "Blessing of Might", "Greater Blessing of Might" },
    spellIds = { 25291, 25782 }, fallbackIcon = "Interface\\Icons\\Spell_Holy_FistOfJustice" },
  { key = "shout",      label = "Battle Shout",   names = { "Battle Shout" },
    spellIds = { 25289 },        fallbackIcon = "Interface\\Icons\\Ability_Warrior_RallyingCry" },
  { key = "shadowprot", label = "Shadow Prot.",   names = { "Shadow Protection", "Prayer of Shadow Protection" },
    spellIds = { 25433, 39374 }, fallbackIcon = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
  { key = "kibler",     label = "Kibler's Bits",  matchSpellId = 43771, selfApplied = true,
    spellIds = { 43771 },        fallbackIcon = "Interface\\Icons\\INV_Misc_Food_103_BoneSoup" },
  { key = "scrollAgi",  label = "Scroll: Agi",    parseOnly = true, selfApplied = true,
    matchSpellIds = { 33077, 12174 }, spellIds = { 33077, 12174 },
    fallbackIcon = "Interface\\Icons\\INV_Scroll_03" },
  { key = "scrollStr",  label = "Scroll: Str",    parseOnly = true, selfApplied = true,
    matchSpellIds = { 33082, 12179 }, spellIds = { 33082, 12179 },
    fallbackIcon = "Interface\\Icons\\INV_Scroll_05" },
}

-- profile.buffTrackerDisabled is keyed "player:<key>" / "pet:<key>".
local function isDisabled(which, key)
  local p = Nock.db and Nock.db.profile
  local t = p and p.buffTrackerDisabled
  return t and t[which .. ":" .. key] == true
end

-- Parse a custom spell-ID string ("123\n456, 789") into tracker entries.
local function parseCustom(str)
  local out = {}
  if not str or str == "" then return out end
  for token in tostring(str):gmatch("[^%s,;\r\n]+") do
    local id = tonumber(token)
    if id then
      out[#out + 1] = {
        key          = "custom" .. id,
        matchSpellId = id,
        fallbackIcon = spellIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark",
        spellIds     = { id },
      }
    end
  end
  return out
end

-- The effective catalog only changes with the profile (an entry toggled, a
-- custom id typed), so it is built once per side and dropped on
-- NOCK_VISUALS_CHANGED -- not rebuilt (two lists, the custom parse and a
-- GetSpellInfo per custom id) ten times a second.
local _catalog = {}

local function effectiveCatalog(which, catalog)
  local cached = _catalog[which]
  if cached then return cached end
  local p = Nock.db and Nock.db.profile
  local list = {}
  for _, entry in ipairs(catalog) do
    if not isDisabled(which, entry.key) then
      list[#list + 1] = entry
    end
  end
  local customStr = p and p["buffTrackerCustom" .. (which == "player" and "Player" or "Pet")]
  for _, e in ipairs(parseCustom(customStr)) do
    list[#list + 1] = e
  end
  _catalog[which] = list
  return list
end

function BuffTracker:InvalidateCatalog()
  _catalog.player, _catalog.pet = nil, nil
end

-- The published rows are reused in place: dest[i] keeps its table across
-- refreshes and only the fields are rewritten; rows past the new count are
-- dropped. The view reads fields, never identity.
local function buildList(which, catalog, unit, dest, allowParse)
  local n = 0
  if not (UnitExists and UnitExists(unit)) then
    for i = #dest, 1, -1 do dest[i] = nil end
    return
  end
  for _, entry in ipairs(effectiveCatalog(which, catalog)) do
    if entry.parseOnly and not allowParse then
      -- skip parse-only entry when parse mode is off
    else
      local found, icon, count, duration, exp = findBuffForEntry(unit, entry)
      n = n + 1
      local r = dest[n]
      if not r then r = {}; dest[n] = r end
      r.key            = entry.key
      r.label          = entry.label or entry.key
      r.selfApplied    = entry.selfApplied and true or false
      r.icon           = icon or resolveIcon(entry)
      r.present        = found
      r.count          = found and count or 0
      r.duration       = found and duration or 0
      r.expirationTime = found and exp or 0
    end
  end
  for i = #dest, n + 1, -1 do dest[i] = nil end
end

-- Slow lane (Core:Tick): the rebuild below is O(entries x buff-depth) and ran
-- every tick. A buff checklist never needs to change faster than ~10 Hz, and
-- the view diffs against state.bufftracker, so nothing flickers.
BuffTracker.refreshInterval = 0.1

local function trackerEnabled()
  local p = Nock.db and Nock.db.profile
  return not (p and p.buffTrackerEnabled == false)
end

function BuffTracker:OnEnable()
  if self.RegisterMessage then
    self:RegisterMessage("NOCK_VISUALS_CHANGED", "InvalidateCatalog")
  end
end

function BuffTracker:Refresh(state)
  state.bufftracker = state.bufftracker or { player = {}, pet = {} }
  local bt = state.bufftracker
  -- Off (the shipped default): nothing is scanned or built. The view hides on
  -- the flag and on an empty list alike.
  if not trackerEnabled() then
    if bt.player[1] then for i = #bt.player, 1, -1 do bt.player[i] = nil end end
    if bt.pet[1]    then for i = #bt.pet,    1, -1 do bt.pet[i]    = nil end end
    return
  end
  local parse = isParseMode()
  buildList("player", BuffTracker.PlayerCatalog, "player", bt.player, parse)
  buildList("pet",    BuffTracker.PetCatalog,    "pet",    bt.pet,    parse)
end
