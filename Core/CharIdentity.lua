-- Core/CharIdentity.lua
-- Keeps a character's profile selection and db.char under its GUID, not AceDB's character key.

-- AceDB builds its key once per library file and has changed the form twice
-- (33 "First - Realm", 36 "First - PvP", 39 "First Last" on Forever). Another
-- addon's newer copy replaces our db's methods when it loads, so SetProfile
-- then writes under a key the next load doesn't read: the profile looks reset
-- on every launch. sv.profileByGuid and sv.char[guid] depend on none of that.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local CI = {}
Nock.CharIdentity = CI

local DEFAULT_PROFILE = "Default"
local UNKNOWN_PREFIX = "Unknown"
local RULESET = { PvP = true, PvE = true, RP = true, Hardcore = true }

-- What the client says this character is, or nil while it can't say yet.
function CI.ReadIdent()
  local guid, first = UnitGUID("player"), (UnitName("player"))
  local isSecret = _G.issecretvalue
  if isSecret and (isSecret(guid) or isSecret(first)) then return nil end
  if type(guid) ~= "string" or guid == "" then return nil end
  if type(first) ~= "string" or first == "" then return nil end
  if first == UNKNOWN_PREFIX or first == _G.UNKNOWNOBJECT then return nil end
  return {
    guid = guid,
    first = first,
    realm = GetRealmName(),
    scanAliases = (Nock.Flavor and Nock.Flavor.forever) and true or false,
  }
end

local function isUnknownKey(key)
  return key:sub(1, #UNKNOWN_PREFIX) == UNKNOWN_PREFIX
end

-- Forever: any key form of this first name. Elsewhere a name is only unique per
-- realm, so a namesake on another realm is someone else.
local function isAlias(key, ident)
  if isUnknownKey(key) then return false end
  if not ident.scanAliases then return key == ident.first .. " - " .. tostring(ident.realm) end
  return key == ident.first or key:sub(1, #ident.first + 1) == ident.first .. " "
end

-- A ruleset key is the one a newer library wrote, so it holds the latest real
-- choice; then the realmless form; then old realm keys.
local function aliasRank(key)
  local suffix = key:match(" %- (%a+)$")
  if suffix and RULESET[suffix] then return 1 end
  if not key:find(" - ", 1, true) then return 2 end
  return 3
end

local function aliasesOf(sv, ident, ownKey)
  local seen, list = {}, {}
  local function collect(tbl)
    if type(tbl) ~= "table" then return end
    for key in pairs(tbl) do
      if type(key) == "string" and not seen[key] and key ~= ownKey and isAlias(key, ident) then
        seen[key] = true
        list[#list + 1] = key
      end
    end
  end
  collect(sv.profileKeys)
  collect(sv.char)
  table.sort(list, function(a, b)
    local ra, rb = aliasRank(a), aliasRank(b)
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  return list
end

local function profileExists(sv, name)
  return name == DEFAULT_PROFILE or (type(sv.profiles) == "table" and sv.profiles[name] ~= nil)
end

-- First run for this character. A named profile on the current key is what the
-- player sees today, so it stays; only a Default looks for a stranded choice.
-- Returns the profile, plus its name again when that restored something.
local function firstProfile(db, aliases)
  local sv, current = db.sv, db.keys.profile
  if current ~= DEFAULT_PROFILE then return current, nil end
  for _, key in ipairs(aliases) do
    local name = type(sv.profileKeys) == "table" and sv.profileKeys[key]
    if type(name) == "string" and name ~= DEFAULT_PROFILE and profileExists(sv, name) then
      return name, name
    end
  end
  return current, nil
end

-- First run for this character: its fields from the key in use, then whatever
-- only the older keys hold. The old entries stay on file.
local function mergeCharData(sv, ownKey, aliases)
  local merged = {}
  local function take(key)
    local src = type(sv.char) == "table" and sv.char[key]
    if type(src) ~= "table" then return end
    for k, v in pairs(src) do
      if merged[k] == nil then merged[k] = v end
    end
  end
  if not isUnknownKey(ownKey) then take(ownKey) end
  for _, key in ipairs(aliases) do take(key) end
  return merged
end

-- Point db.char at the GUID. AceDB creates the section lazily from db.keys, so
-- defaults and logout cleanup carry on working. A section already read this
-- session gets its defaults taken off first, so a default can't pass for saved
-- data in the merge, and handed back after.
local function moveCharSection(db, guid, ownKey, aliases)
  local sv = db.sv
  local defaults = db.defaults
  local live = rawget(db, "char") ~= nil
  if live then db:RegisterDefaults(nil) end
  if type(sv.char) ~= "table" or sv.char[guid] == nil then
    local merged = mergeCharData(sv, ownKey, aliases)
    if next(merged) ~= nil then
      if type(sv.char) ~= "table" then sv.char = {} end
      sv.char[guid] = merged
    end
  end
  rawset(db, "char", nil)
  db.keys.char = guid
  if live then db:RegisterDefaults(defaults) end
end

-- Call right after AceDB:New, and again at login if the identity wasn't ready.
-- Returns the profile's name when a first run restored one, for the notice.
function CI.Adopt(db, ident)
  if CI.adopted or not ident then return nil end
  CI.adopted = true

  local sv, guid = db.sv, ident.guid
  if type(sv.profileByGuid) ~= "table" then sv.profileByGuid = {} end
  local book = sv.profileByGuid

  local ownKey = db.keys.char
  local want, restored = book[guid], nil
  local aliases = aliasesOf(sv, ident, ownKey)
  if want == nil then
    want, restored = firstProfile(db, aliases)
  elseif not profileExists(sv, want) then
    want = db.keys.profile
  end

  moveCharSection(db, guid, ownKey, aliases)

  if want ~= db.keys.profile then db:SetProfile(want) end
  book[guid] = want

  db.RegisterCallback(CI, "OnProfileChanged", function(_, _, name)
    book[guid] = name
  end)
  return restored
end
