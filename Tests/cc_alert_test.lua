-- Tests/cc_alert_test.lua
-- Modules/CCAlert.lua: your own spell list, the match (built-in switches, ids, names, customs), the
-- watched units, the cue chain, and the event flow (aimed at you, hostile, dedupe, stop, PvP off).
-- Run from the repo root: luajit Tests/cc_alert_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = { state = { player = { pvp = true }, ccAlert = nil }, db = { profile = {} } }
local CC
function Nock:NewModule()
  CC = {}
  function CC:RegisterEvent() end
  function CC:RegisterMessage() end
  return CC
end
_G.LibStub = function(name, silent)
  if name == "AceAddon-3.0" then return { GetAddon = function() return Nock end } end
  return nil
end
dofile("Core/Constants.lua")
local C = Nock.Constants
ok(type(C.PVP_CC_CASTS) == "table" and #C.PVP_CC_CASTS >= 5, "built-in CC cast list exists")

local names = { [5782] = "Fear", [118] = "Polymorph", [6358] = "Seduction", [605] = "Mind Control", [339] = "Entangling Roots" }
_G.GetSpellInfo = function(id) return names[id] end
dofile("Modules/CCAlert.lua")
ok(type(CC.CustomEntries) == "function" and type(CC.Match) == "function", "module loads")

-- CustomEntries
local cs = CC.CustomEntries({ { spell = "Hex", sound = "Horn" }, { spell = 12345 }, { spell = "Cyclone", enabled = false }, { spell = "" } })
ok(#cs == 2, "custom: a switched-off line and an empty one are left out")
ok(cs[1].name == "Hex" and cs[1].sound == "Horn", "custom: name + its sound")
ok(cs[2].id == 12345 and cs[2].sound == nil, "custom: a numeric spell id, no sound of its own")
ok(#CC.CustomEntries(nil) == 0 and #CC.CustomEntries("") == 0, "custom: nothing stored")

-- Match
local builtins = CC:Builtins()
ok(#builtins == #C.PVP_CC_CASTS and builtins[1].name == "Fear", "built-ins resolved by spell id -> name")
local p = {}
ok(CC.Match(p, "Fear", 5782, builtins, {}) ~= nil and CC.Match(p, "Fear", 5782, builtins, {}).key == "fear", "match: Fear by name")
ok(CC.Match(p, "Polymorph: Pig", 28272, builtins, {}) ~= nil, "match: a Polymorph variant by id")
ok(CC.Match(p, "Frostbolt", 116, builtins, {}) == nil, "match: a nuke is not CC")
ok(CC.Match({ pvpCc_fear = false }, "Fear", 5782, builtins, {}) == nil, "match: built-in switched off")
local custom = CC.CustomEntries({ { spell = "Hex", sound = "Horn" } })
ok(CC.Match(p, "Hex", 1, builtins, custom) ~= nil and CC.Match(p, "Hex", 1, builtins, custom).sound == "Horn", "match: a custom by name carries its sound")

-- units
ok(CC.UnitWatched("target") and CC.UnitWatched("focus") and CC.UnitWatched("arena3") and CC.UnitWatched("nameplate17"), "watched: target/focus/arena/nameplate")
ok(not CC.UnitWatched("player") and not CC.UnitWatched("party1") and not CC.UnitWatched("pet"), "watched: not you, your party or your pet")

-- cue chain
local log = {}
local env = {
  lsmPath = function(n) return n == "Horn" and "snd/horn.ogg" or nil end,
  playFile = function(path) log[#log + 1] = "file:" .. path end,
}
ok(CC.PlayCue({ pvpCc_fear_sound = "Horn" }, { key = "fear" }, env) == "file" and log[1] == "file:snd/horn.ogg", "cue: a built-in's own sound")
ok(CC.PlayCue({}, { sound = "Horn" }, env) == "file" and #log == 2, "cue: a custom line's own sound")
ok(CC.PlayCue({}, { sound = "None" }, env) == nil and #log == 2, "cue: an entry's None is silent")
ok(CC.PlayCue({}, { key = "fear" }, env) == nil and #log == 2, "cue: the stock Phone without WeakAuras -> silent, no stand-in")
ok(CC.PlayCue({}, { sound = "Missing" }, env) == nil, "cue: an unknown pick stays silent")

-- event flow
local played = 0
_G.PlaySoundFile = function() played = played + 1 end
local units = {}
_G.UnitCanAttack = function(_, u) return units[u] and units[u].hostile end
_G.UnitIsUnit = function(a, b) local u = a:gsub("target$", ""); return units[u] and units[u].aimedAtYou and b == "player" end
_G.UnitGUID = function(u) return units[u] and units[u].guid end
_G.UnitCastingInfo = function(u)
  local c = units[u] and units[u].cast
  if not c then return nil end
  return c.name, c.name, "icon", 1000, 2500, false, "cast-1", false, c.id
end
Nock.db.profile = { pvpCcEnabled = true, pvpCcOnlyAtYou = true, pvpCc_fear_sound = "Horn", pvpCcCustom = {} }
_G.LibStub = function(name, silent)
  if name == "AceAddon-3.0" then return { GetAddon = function() return Nock end } end
  if name == "LibSharedMedia-3.0" then return { Fetch = function(_, _, n) return n == "Horn" and "snd/horn.ogg" or nil end } end
  return nil
end

units.target = { hostile = true, aimedAtYou = true, guid = "LOCK", cast = { name = "Fear", id = 5782 } }
CC:OnCastStart("UNIT_SPELLCAST_START", "target")
ok(Nock.state.ccAlert and Nock.state.ccAlert.short == "Fear" and Nock.state.ccAlert.endTime == 2.5, "flow: a Fear at you -> the alert with the cast end")
ok(played == 1, "flow: one cue")
units.nameplate3 = units.target
CC:OnCastStart("UNIT_SPELLCAST_START", "nameplate3")
ok(played == 1, "flow: the same cast seen on the nameplate does not cue again")
CC:OnCastEnd("UNIT_SPELLCAST_INTERRUPTED", "nameplate3")
ok(Nock.state.ccAlert == nil, "flow: the caster's stop clears the alert")

units.target = { hostile = true, aimedAtYou = false, guid = "LOCK2", cast = { name = "Fear", id = 5782 } }
CC:OnCastStart("UNIT_SPELLCAST_START", "target")
ok(Nock.state.ccAlert == nil and played == 1, "flow: a Fear at someone else is ignored")
Nock.db.profile.pvpCcOnlyAtYou = false
CC:OnCastStart("UNIT_SPELLCAST_START", "target")
ok(Nock.state.ccAlert ~= nil and played == 2, "flow: with only-at-you off it counts")
Nock.state.ccAlert = nil

units.target = { hostile = false, aimedAtYou = true, guid = "FRIEND", cast = { name = "Fear", id = 5782 } }
CC:OnCastStart("UNIT_SPELLCAST_START", "target")
ok(Nock.state.ccAlert == nil, "flow: a friendly caster is ignored")

units.target = { hostile = true, aimedAtYou = true, guid = "LOCK3", cast = { name = "Fear", id = 5782 } }
Nock.state.player.pvp = false
CC:OnCastStart("UNIT_SPELLCAST_START", "target")
ok(Nock.state.ccAlert == nil, "flow: outside PvP mode nothing fires")
Nock.state.player.pvp = true
Nock.db.profile.pvpCcEnabled = false
CC:OnCastStart("UNIT_SPELLCAST_START", "target")
ok(Nock.state.ccAlert == nil, "flow: switched off nothing fires")
Nock.db.profile.pvpCcEnabled = true
Nock.db.profile.pvpCcCustom = { { spell = "Frostbolt", sound = "Horn", enabled = true } }
CC:InvalidateCatalog()
units.target = { hostile = true, aimedAtYou = true, guid = "MAGE", cast = { name = "Frostbolt", id = 116 } }
CC:OnCastStart("UNIT_SPELLCAST_START", "target")
ok(Nock.state.ccAlert ~= nil and Nock.state.ccAlert.short == "Frostbolt", "flow: a custom line fires by name")
CC:OnPvPChanged(nil, false)
ok(Nock.state.ccAlert == nil, "flow: leaving PvP mode clears it")

print(("cc_alert_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
