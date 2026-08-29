-- Modules/BuffTracker.lua
-- Configurable raid-buff checklist for hunter + pet. A built-in preset
-- (PlayerCatalog / PetCatalog) seeds the defaults; the user can disable
-- individual preset entries and add their own spell IDs via the settings UI.
-- Effective list = (enabled preset entries) + (custom spell-ID entries).
-- Writes active/missing + remaining time into state.bufftracker.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local BuffTracker = Nock:NewModule("BuffTracker")

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

-- One indexed pass over a unit's buffs, shared by every catalog entry below.
-- Each entry used to run its own full UnitBuff walk, so a 10-entry catalog
-- against a raid-buffed player cost ~300 UnitBuff calls per unit per refresh —
-- and scan depth grows with the raid's buff stack, which is why it detonated on
-- a boss pull. Scratch indices are module-level and cleared in place, never
-- reallocated (they hold buff indices, not tables).
local _idxByName, _idxBySpell = {}, {}

local function scanUnitBuffs(unit)
  for k in pairs(_idxByName)  do _idxByName[k]  = nil end
  for k in pairs(_idxBySpell) do _idxBySpell[k] = nil end
  if not (UnitExists and UnitExists(unit) and UnitBuff) then return end
  for i = 1, 40 do
    local name, _, _, _, _, _, _, _, _, spellId = UnitBuff(unit, i)
    if not name then break end
    -- First occurrence wins, matching the old first-match-in-scan-order result.
    if _idxByName[name] == nil then _idxByName[name] = i end
    if spellId and _idxBySpell[spellId] == nil then _idxBySpell[spellId] = i end
  end
end

-- Index of the first buff matching the entry + whether to use that buff's own
-- icon. Name-matched preset entries keep falling back to the catalog's resolved
-- icon (rank-agnostic), exactly as before; spellId matches use the live icon.
local function matchIndex(entry)
  if entry.matchSpellIds then
    for _, want in ipairs(entry.matchSpellIds) do
      local i = _idxBySpell[want]
      if i then return i, true end
    end
  elseif entry.matchSpellId then
    local i = _idxBySpell[entry.matchSpellId]
    if i then return i, true end
  elseif entry.names then
    for _, want in ipairs(entry.names) do
      local i = _idxByName[want]
      if i then return i, false end
    end
  end
  return nil, false
end

-- Returns { icon, count, duration, exp } or nil — same shape as before.
-- Requires scanUnitBuffs(unit) to have run for this unit first.
local function findBuffForEntry(unit, entry)
  local idx, useIcon = matchIndex(entry)
  if not idx then return nil end
  local _, icon, count, _, duration, expirationTime = UnitBuff(unit, idx)
  return {
    icon           = useIcon and icon or nil,
    count          = count or 0,
    duration       = duration or 0,
    expirationTime = expirationTime or 0,
  }
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

local function effectiveCatalog(which, catalog)
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
  return list
end

local function buildList(which, catalog, unit, dest, allowParse)
  for k in pairs(dest) do dest[k] = nil end
  scanUnitBuffs(unit)   -- one pass; every entry below matches against the index
  for _, entry in ipairs(effectiveCatalog(which, catalog)) do
    if entry.parseOnly and not allowParse then
      -- skip parse-only entry when parse mode is off
    else
      local info = findBuffForEntry(unit, entry)
      dest[#dest + 1] = {
        key            = entry.key,
        label          = entry.label or entry.key,
        selfApplied    = entry.selfApplied and true or false,
        icon           = (info and info.icon) or resolveIcon(entry),
        present        = info ~= nil,
        count          = info and info.count or 0,
        duration       = info and info.duration or 0,
        expirationTime = info and info.expirationTime or 0,
      }
    end
  end
end

-- Slow lane (Core:Tick): the rebuild below is O(entries x buff-depth) and ran
-- every tick. A buff checklist never needs to change faster than ~10 Hz, and
-- the view diffs against state.bufftracker, so nothing flickers.
BuffTracker.refreshInterval = 0.1

function BuffTracker:Refresh(state)
  state.bufftracker = state.bufftracker or { player = {}, pet = {} }
  local parse = isParseMode()
  buildList("player", BuffTracker.PlayerCatalog, "player", state.bufftracker.player, parse)
  buildList("pet",    BuffTracker.PetCatalog,    "pet",    state.bufftracker.pet,    parse)
end
