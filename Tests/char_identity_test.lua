-- Tests/char_identity_test.lua
-- Standalone LuaJIT tests for Core/CharIdentity.lua, replayed across simulated
-- launches on the real bundled AceDB. Only the SavedVariables table survives a
-- launch. The other AceDB versions are that same source with its minor bumped
-- and its character key swapped for the form that version builds on Forever.
-- Run from the repo root: luajit Tests/char_identity_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local LIBS = "Libs/"
local REALM = "CAMWOW EU4 Realm 2 PvP"
local GUID = "Player-93-0ABC"

local function readFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local ACEDB_SOURCE = readFile(LIBS .. "AceDB-3.0/AceDB-3.0.lua")

local function plainReplace(s, from, to)
  local i, j = s:find(from, 1, true)
  assert(i, "AceDB source no longer contains: " .. from)
  return s:sub(1, i - 1) .. to .. s:sub(j + 1)
end

-- nil keyExpr = the bundled library as shipped.
local function acedbVariant(minor, keyExpr)
  local s = ACEDB_SOURCE
  if keyExpr then
    s = plainReplace(s, '"AceDB-3.0", 33', '"AceDB-3.0", ' .. minor)
    s = plainReplace(s, 'local charKey = UnitName("player") .. " - " .. realmKey', "local charKey = " .. keyExpr)
  end
  return s
end

local SRC = {
  ["33"] = acedbVariant(33),
  ["36"] = acedbVariant(36, '(UnitName("player")) .. " - PvP"'),
  ["39"] = acedbVariant(39, '(UnitName("player")) .. " " .. select(2, UnitName("player"))'),
}

local function run(env, source, name)
  local chunk = assert(loadstring(source, "=" .. name))
  setfenv(chunk, env)
  chunk("Nock", {})
end

local function newEnv(opts)
  opts = opts or {}
  local env = setmetatable({}, { __index = _G })
  env._G = env
  local frames = {}
  env.GetRealmName = function() return opts.realm or REALM end
  env.UnitName = function() return opts.first or "Yaxal", "Forever" end
  env.UnitGUID = function() return opts.guid or GUID end
  env.UnitClass = function() return "Hunter", "HUNTER" end
  env.UnitRace = function() return "Human", "Human" end
  env.UnitFactionGroup = function() return "Alliance" end
  env.GetLocale = function() return "enUS" end
  env.GetCurrentRegion = function() return 3 end
  env.GetCurrentRegionName = function() return "EU" end
  env.geterrorhandler = function() return function(e) error(e, 0) end end
  env.securecallfunction = function(f, ...) return f(...) end
  env.CreateFrame = function()
    local f = {}
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:SetScript(_, fn) self.onEvent = fn end
    frames[#frames + 1] = f
    return f
  end
  env.logout = function()
    for _, f in ipairs(frames) do
      if f.onEvent then f.onEvent(f, "PLAYER_LOGOUT") end
    end
  end
  return env
end

local DEFAULTS = {
  profile = { color = "default" },
  char = { memo = false, list = {} },
  global = {},
}

local function identOf(opts)
  opts = opts or {}
  return {
    guid = opts.guid or GUID,
    first = opts.first or "Yaxal",
    realm = opts.realm or REALM,
    scanAliases = opts.scanAliases ~= false,
  }
end

-- One launch. order lists the AceDB versions as they load; "new" is the moment
-- Nock opens its database. Returns what a player would see.
local function launch(sv, order, action, opts)
  opts = opts or {}
  local env = newEnv(opts)
  run(env, readFile(LIBS .. "LibStub/LibStub.lua"), "LibStub")
  run(env, readFile(LIBS .. "CallbackHandler-1.0/CallbackHandler-1.0.lua"), "CallbackHandler")
  local nock = {}
  env.LibStub:NewLibrary("AceAddon-3.0", 1).GetAddon = function() return nock end
  run(env, readFile("Core/CharIdentity.lua"), "CharIdentity")
  local CI = nock.CharIdentity
  local db, restored
  for _, step in ipairs(order) do
    if step == "new" then
      db = env.LibStub("AceDB-3.0"):New(sv, DEFAULTS, true)
      if not opts.deferred then restored = CI.Adopt(db, identOf(opts)) end
    else
      run(env, SRC[step], "AceDB" .. step)
    end
  end
  if opts.deferred then
    db.char.early = true
    restored = CI.Adopt(db, nil)
    ok(CI.adopted ~= true, "no identity yet: not adopted")
    restored = CI.Adopt(db, identOf(opts))
  end
  if action then action(db) end
  local seen = { profile = db:GetCurrentProfile(), color = db.profile.color, memo = db.char.memo,
                 list = db.char.list, restored = restored, CI = CI, db = db }
  env.logout()
  return seen
end

local function choose(db, name)
  db:SetProfile(name)
  db.profile.color = "mine"
  db.char.memo = "kept"
end

--------------------------------------------------------------------------------
-- A chosen profile and the character's data survive every load order
--------------------------------------------------------------------------------
local ORDERS = {
  ["33 only"]                 = { "33", "new" },
  ["36 after Nock (RXP)"]     = { "33", "new", "36" },
  ["39 after Nock"]           = { "33", "new", "39" },
  ["36 before Nock"]          = { "36", "33", "new" },
  ["39 before Nock"]          = { "39", "33", "new" },
  ["36 before, 39 after"]     = { "36", "33", "new", "39" },
}
for label, order in pairs(ORDERS) do
  local sv = {}
  launch(sv, order, function(db) choose(db, "Imported") end)
  local second = launch(sv, order)
  ok(second.profile == "Imported", label .. ": selection survives the next launch")
  ok(second.color == "mine", label .. ": profile values are the chosen ones")
  ok(second.memo == "kept", label .. ": db.char survives the next launch")
  local third = launch(sv, order)
  ok(third.profile == "Imported", label .. ": selection survives a third launch")
  ok(second.restored == nil, label .. ": no restore notice on a normal launch")
end

--------------------------------------------------------------------------------
-- What changes between two launches no longer matters
--------------------------------------------------------------------------------
do
  local sv = {}
  launch(sv, ORDERS["33 only"], function(db) choose(db, "Imported") end)
  local s = launch(sv, ORDERS["36 before Nock"])
  ok(s.profile == "Imported" and s.memo == "kept", "an addon with a newer AceDB appears before Nock")
  s = launch(sv, ORDERS["39 before Nock"])
  ok(s.profile == "Imported" and s.memo == "kept", "the load order changes again")
  s = launch(sv, ORDERS["33 only"], nil, { realm = "CAMWOW EU4 Realm 3 PvP" })
  ok(s.profile == "Imported" and s.memo == "kept", "the realm name changes")
end

--------------------------------------------------------------------------------
-- An imported profile takes the same route as a manual switch
--------------------------------------------------------------------------------
do
  local sv = {}
  local order = ORDERS["36 after Nock (RXP)"]
  launch(sv, order, function(db)
    db.char.lastOwnProfile = db:GetCurrentProfile()
    db:SetProfile("Imported")
    db.profile.color = "imported"
  end)
  local s = launch(sv, order)
  ok(s.profile == "Imported" and s.color == "imported", "an import sticks")
  ok(s.db.char.lastOwnProfile == "Default", "the way back after an import survives")
end

--------------------------------------------------------------------------------
-- Migration: a file written before the fix
--------------------------------------------------------------------------------
local function oldFile(keys, profiles, char)
  local sv = { profileKeys = keys, profiles = {}, char = char or {} }
  for _, name in ipairs(profiles) do sv.profiles[name] = { color = name } end
  return sv
end

do -- the split: the real selection is under the key the next library wrote
  local sv = oldFile({ ["Yaxal - " .. REALM] = "Default", ["Yaxal - PvP"] = "YaxalForever" },
                     { "Default", "YaxalForever" })
  local s = launch(sv, ORDERS["36 after Nock (RXP)"])
  ok(s.profile == "YaxalForever" and s.color == "YaxalForever", "migration: the stranded selection comes back")
  ok(s.restored == "YaxalForever", "migration: the restore is reported")
  s = launch(sv, ORDERS["36 after Nock (RXP)"])
  ok(s.profile == "YaxalForever" and s.restored == nil, "migration: reported once")
end

do -- a split left by the release's first-name change or a rename
  local sv = oldFile({ ["Yaxal Forever - Classic Beta PvP"] = "Old" }, { "Default", "Old" })
  ok(launch(sv, ORDERS["33 only"]).profile == "Old", "migration: an old key form is found")
end

do -- the current key already names a profile: that is what the player sees today
  local sv = oldFile({ ["Yaxal - " .. REALM] = "Live", ["Yaxal - PvP"] = "Stale" }, { "Default", "Live", "Stale" })
  local s = launch(sv, ORDERS["33 only"])
  ok(s.profile == "Live" and s.restored == nil, "migration: a working named profile is left alone")
end

do -- several candidates: the ruleset key is the one a newer library wrote
  local sv = oldFile({ ["Yaxal - " .. REALM] = "Default", ["Yaxal - Classic Beta PvP"] = "Older",
                       ["Yaxal - PvP"] = "Newer" }, { "Default", "Older", "Newer" })
  ok(launch(sv, ORDERS["33 only"]).profile == "Newer", "migration: the ruleset key wins")
end

do -- nothing to restore
  local sv = oldFile({ ["Yaxal - " .. REALM] = "Default" }, { "Default" })
  local s = launch(sv, ORDERS["33 only"])
  ok(s.profile == "Default" and s.restored == nil, "migration: Default stays Default")
  sv = {}
  s = launch(sv, ORDERS["33 only"])
  ok(s.profile == "Default" and s.restored == nil, "a fresh install starts on Default")
end

do -- an entry pointing at a profile that no longer exists
  local sv = oldFile({ ["Yaxal - " .. REALM] = "Default", ["Yaxal - PvP"] = "Gone" }, { "Default" })
  ok(launch(sv, ORDERS["33 only"]).profile == "Default", "migration: a deleted profile is not restored")
end

do -- other characters' entries are not this character's
  local sv = oldFile({ ["Yaxal - " .. REALM] = "Default", ["Yax - PvP"] = "Theirs",
                       ["Unknown - Classic Beta PvP"] = "Junk" }, { "Default", "Theirs", "Junk" })
  ok(launch(sv, ORDERS["33 only"]).profile == "Default", "migration: another name or Unknown is never adopted")
end

do -- it runs once: choosing Default afterwards is respected
  local sv = oldFile({ ["Yaxal - " .. REALM] = "Default", ["Yaxal - PvP"] = "YaxalForever" },
                     { "Default", "YaxalForever" })
  local order = ORDERS["33 only"]
  launch(sv, order, function(db) db:SetProfile("Default") end)
  local s = launch(sv, order)
  ok(s.profile == "Default" and s.restored == nil, "migration: a later choice of Default sticks")
end

do -- a profile deleted after migration falls back quietly
  local sv = {}
  local order = ORDERS["33 only"]
  launch(sv, order, function(db) choose(db, "Temp"); db:SetProfile("Default") end)
  launch(sv, order, function(db) db:SetProfile("Temp") end)
  sv.profiles.Temp = nil
  sv.profileKeys["Yaxal - " .. REALM] = "Default"
  ok(launch(sv, order).profile == "Default", "a stored selection whose profile is gone falls back")
end

--------------------------------------------------------------------------------
-- Migration: db.char
--------------------------------------------------------------------------------
do
  local sv = oldFile({ ["Yaxal - " .. REALM] = "Default" }, { "Default" }, {
    ["Yaxal - " .. REALM] = { memo = "current", onlyCurrent = 1 },
    ["Yaxal - PvP"] = { memo = "alias", onlyAlias = 2 },
    ["Yax - PvP"] = { onlyOther = 3 },
    ["Unknown - Classic Beta PvP"] = { onlyUnknown = 4 },
  })
  local s = launch(sv, ORDERS["33 only"])
  ok(s.memo == "current", "char migration: the key in use wins")
  ok(s.db.char.onlyCurrent == 1 and s.db.char.onlyAlias == 2, "char migration: fields merge from aliases")
  ok(s.db.char.onlyOther == nil and s.db.char.onlyUnknown == nil, "char migration: others are left out")
  ok(sv.char["Yax - PvP"].onlyOther == 3, "char migration: other entries stay on file")
  s = launch(sv, ORDERS["36 before Nock"])
  ok(s.memo == "current" and s.db.char.onlyAlias == 2, "char migration: stable under another key form")
end

do -- defaults still work on the moved section, and aren't written to the file
  local sv = {}
  local s = launch(sv, ORDERS["33 only"], function(db) db.char.memo = "x" end)
  ok(type(s.list) == "table", "char defaults are delivered on the new key")
  ok(sv.char[GUID].memo == "x", "char data lives under the GUID")
  ok(sv.char[GUID].list == nil, "logout strips char defaults on the new key")
end

--------------------------------------------------------------------------------
-- The identity arriving late (Unknown at load)
--------------------------------------------------------------------------------
do
  local sv = oldFile({ ["Unknown - " .. REALM] = "Default", ["Yaxal - PvP"] = "Named" }, { "Default", "Named" },
                     { ["Yaxal - PvP"] = { memo = "alias" } })
  local s = launch(sv, ORDERS["33 only"], nil, { deferred = true })
  ok(s.profile == "Named" and s.color == "Named", "late identity: the profile is restored")
  ok(s.memo == "alias", "late identity: db.char moves after it was already read")
  ok(type(s.list) == "table", "late identity: char defaults are delivered again")
  ok(s.db.profile.color == "Named", "late identity: profile defaults stay intact")
end

--------------------------------------------------------------------------------
-- Flavours without surnames: another realm's namesake is someone else
--------------------------------------------------------------------------------
do
  local key = "Yaxal - Spineshatter"
  local sv = oldFile({ [key] = "Default", ["Yaxal - Other"] = "Theirs" }, { "Default", "Theirs" },
                     { [key] = { memo = "mine" }, ["Yaxal - Other"] = { memo = "theirs", onlyTheirs = 1 } })
  local s = launch(sv, ORDERS["33 only"], nil, { realm = "Spineshatter", scanAliases = false })
  ok(s.profile == "Default", "no alias scan: a namesake's profile is not adopted")
  ok(s.memo == "mine" and s.db.char.onlyTheirs == nil, "no alias scan: only this realm's char data moves")

  sv = oldFile({ [key] = "Named" }, { "Default", "Named" })
  s = launch(sv, ORDERS["33 only"], nil, { realm = "Spineshatter", scanAliases = false })
  ok(s.profile == "Named", "no alias scan: the current selection carries over")
end

--------------------------------------------------------------------------------
-- Two characters keep separate selections
--------------------------------------------------------------------------------
do
  local sv = {}
  local order = ORDERS["33 only"]
  launch(sv, order, function(db) choose(db, "Main") end)
  launch(sv, order, function(db) db:SetProfile("Alt") end, { guid = "Player-93-0DEF" })
  ok(launch(sv, order).profile == "Main", "characters with one first name: the main keeps its profile")
  ok(launch(sv, order, nil, { guid = "Player-93-0DEF" }).profile == "Alt", "characters with one first name: the alt too")
end

--------------------------------------------------------------------------------
-- Reading the identity from the client
--------------------------------------------------------------------------------
do
  local function read(guid, first, secret)
    local env = newEnv()
    env.UnitGUID = function() return guid end
    env.UnitName = function() return first, "Forever" end
    env.UNKNOWNOBJECT = "Unknown"
    if secret then env.issecretvalue = function(v) return v == secret end end
    run(env, readFile(LIBS .. "LibStub/LibStub.lua"), "LibStub")
    local nock = { Flavor = { forever = true } }
    env.LibStub:NewLibrary("AceAddon-3.0", 1).GetAddon = function() return nock end
    run(env, readFile("Core/CharIdentity.lua"), "CharIdentity")
    return nock.CharIdentity.ReadIdent()
  end
  local id = read(GUID, "Yaxal")
  ok(id and id.guid == GUID and id.first == "Yaxal" and id.realm == REALM and id.scanAliases == true, "ident: all fields")
  ok(read(nil, "Yaxal") == nil, "ident: no GUID yet")
  ok(read(GUID, nil) == nil, "ident: no name yet")
  ok(read(GUID, "Unknown") == nil, "ident: Unknown is not a name")
  ok(read(GUID, "Yaxal", GUID) == nil, "ident: a secret GUID is not usable")
end

print(("char_identity_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
