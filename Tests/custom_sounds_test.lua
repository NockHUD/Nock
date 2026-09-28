-- Tests/custom_sounds_test.lua
-- Forever/CustomSounds.lua: resolving what the user typed, validating a new entry, LSM registration, the Test play.
-- Run from the repo root: luajit Tests/custom_sounds_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = { db = { global = {} } }
local modules = {}
function Nock:NewModule(name)
  local m = {}
  modules[name] = m
  return m
end
local lsmStub
_G.LibStub = function(name)
  if name == "LibSharedMedia-3.0" then return lsmStub end
  return { GetAddon = function() return Nock end }
end
dofile("Forever/CustomSounds.lua")
local CS = Nock.CustomSounds
ok(type(CS) == "table" and type(CS.Resolve) == "function", "module loads")

-- 1. Resolve --------------------------------------------------------------------
local R = CS.Resolve
ok(R("ding.mp3") == "Interface\\AddOns\\NockSounds\\ding.mp3", "bare file -> the NockSounds folder")
ok(R("  ding.ogg  ") == "Interface\\AddOns\\NockSounds\\ding.ogg", "trimmed")
ok(R("alerts\\ding.mp3") == "Interface\\AddOns\\NockSounds\\alerts\\ding.mp3", "relative subfolder -> under NockSounds")
ok(R("alerts/ding.mp3") == "Interface\\AddOns\\NockSounds\\alerts\\ding.mp3", "forward slashes normalised")
ok(R("Interface/AddOns/Foo/x.ogg") == "Interface\\AddOns\\Foo\\x.ogg", "full path with forward slashes")
ok(R("INTERFACE\\ADDONS\\Foo\\X.MP3") == "INTERFACE\\ADDONS\\Foo\\X.MP3", "case-insensitive prefix and extension, case kept")
ok(R("C:\\Program Files (x86)\\World of Warcraft\\_classic_beta_\\Interface\\AddOns\\NockSounds\\ding.mp3")
   == "Interface\\AddOns\\NockSounds\\ding.mp3", "pasted absolute path cut at Interface\\")
ok(R("\"C:\\WoW\\_classic_beta_\\Interface\\AddOns\\NockSounds\\ding.mp3\"")
   == "Interface\\AddOns\\NockSounds\\ding.mp3", "Explorer 'Copy as path' quotes stripped")
ok(R("NockSounds\\ding.mp3") == "Interface\\AddOns\\NockSounds\\ding.mp3", "folder name typed too -> not doubled")
ok(R("addons/nocksounds/ding.mp3") == "Interface\\AddOns\\NockSounds\\ding.mp3", "AddOns\\NockSounds prefix typed -> not doubled")
ok(R("AddOns\\Foo\\ding.mp3") == "Interface\\AddOns\\Foo\\ding.mp3", "AddOns\\<other addon> -> that addon's folder")
ok(R("567458") == 567458, "digits -> FileDataID number")
ok(R(567458) == 567458, "a stored number passes through")
local v, m = R("0");                          ok(v == nil and m == CS.MSG.EMPTY, "0 is not a sound id")
v, m = R("");                                 ok(v == nil and m == CS.MSG.EMPTY, "empty rejected")
v, m = R(nil);                                ok(v == nil and m == CS.MSG.EMPTY, "nil rejected")
v, m = R("Interface\\Sounds\\ding.mp3");      ok(v == nil and m == CS.MSG.OUTSIDE, "Interface\\Sounds rejected (tested: never plays)")
v, m = R("C:\\Music\\ding.mp3");              ok(v == nil and m == CS.MSG.OUTSIDE, "drive path outside the game rejected")
v, m = R("\\ding.mp3");                       ok(v == nil and m == CS.MSG.OUTSIDE, "leading backslash rejected")
v, m = R("ding.wav");                         ok(v == nil and m == CS.MSG.FORMAT, ".wav rejected")
v, m = R("ding");                             ok(v == nil and m == CS.MSG.FORMAT, "no extension rejected")

-- 2. Validate -------------------------------------------------------------------
local list = { { name = "Ding", source = "ding.mp3" } }
ok(CS.Validate("Horn", "horn.ogg", list) == "Interface\\AddOns\\NockSounds\\horn.ogg", "a new name + good file validates to the path")
v, m = CS.Validate("  ding ", "x.mp3", list); ok(v == nil and m == CS.MSG.DUP_NAME, "duplicate name, other case and spaces")
v, m = CS.Validate("", "x.mp3", list);        ok(v == nil and m == CS.MSG.NO_NAME, "empty name")
v, m = CS.Validate(string.rep("a", 33), "x.mp3", list); ok(v == nil and m == CS.MSG.LONG_NAME, "33-char name")
ok(CS.Validate(string.rep("a", 32), "x.mp3", list) ~= nil, "32-char name ok")
v, m = CS.Validate("Horn", "horn.wav", list); ok(v == nil and m == CS.MSG.FORMAT, "bad file reported after a good name")
-- removed-then-re-added in one session: LSM still holds the old value
local held = { ["Custom: Horn"] = "Interface\\AddOns\\NockSounds\\old.mp3" }
local lsm = { Fetch = function(_, t, k, noDefault) return t == "sound" and held[k] or nil end }
v, m = CS.Validate("Horn", "horn.ogg", list, lsm); ok(v == nil and m == CS.MSG.STALE, "name still registered with another sound -> STALE")
ok(CS.Validate("Horn", "old.mp3", list, lsm) ~= nil, "same name, same sound as registered -> fine")

-- 3. RegisterAll ----------------------------------------------------------------
local reg = {}
local mock = { Register = function(_, t, k, d) if reg[k] ~= nil then return false end; reg[k] = d; return true end }
local n = CS.RegisterAll({
  { name = "Ding", source = "ding.mp3" },
  { name = "Game", source = "567458" },
  "not a table",
  { name = "", source = "x.mp3" },
  { name = "Bad", source = "x.wav" },
  { source = "noname.mp3" },
}, mock)
ok(n == 2, "two valid entries registered, got " .. tostring(n))
ok(reg["Custom: Ding"] == "Interface\\AddOns\\NockSounds\\ding.mp3", "registered under the Custom: prefix")
ok(reg["Custom: Game"] == 567458, "FileDataID registered as a number")
ok(reg["Custom: Bad"] == nil, "invalid entry skipped")
ok(CS.RegisterAll(nil, mock) == 0 and CS.RegisterAll({ { name = "X", source = "x.mp3" } }, nil) == 0, "nil list / no LSM -> 0, no error")

-- 4. Test -----------------------------------------------------------------------
local played
local function play(willPlay) return function(v2, ch) played = { v2, ch }; return willPlay end end
local good, msg = CS.Test("ding.mp3", "SFX", play(true))
ok(good == true and msg == nil and played[1] == "Interface\\AddOns\\NockSounds\\ding.mp3" and played[2] == "SFX", "Test plays the resolved path on the channel")
good, msg = CS.Test("ding.mp3", nil, play(false)); ok(good == false and msg == CS.MSG.NOT_FOUND and played[2] == "Master", "willPlay false -> NOT_FOUND; channel defaults to Master")
good, msg = CS.Test("ding.mp3", "Master", play(nil)); ok(good == true, "willPlay nil is not treated as missing")
good, msg = CS.Test("ding.mp3", "Master", function() error("boom") end); ok(good == false and msg == CS.MSG.NOT_FOUND, "a throwing play -> NOT_FOUND")
played = nil
good, msg = CS.Test("ding.wav", "Master", play(true)); ok(good == false and msg == CS.MSG.FORMAT and played == nil, "unresolvable source never plays")
ok(CS.MSG.NOT_FOUND:find("restart", 1, true) ~= nil, "not-found message tells the user to restart")

-- 5. load-time registration ------------------------------------------------------
local M = modules["CustomSounds"]
ok(M and type(M.OnInitialize) == "function", "CustomSounds module with OnInitialize")
if M and M.OnInitialize then
  reg = {}
  lsmStub = mock
  Nock.db.global.customSounds = { { name = "Ding", source = "ding.mp3" }, 42, { name = "Bad", source = "C:\\x.mp3" } }
  local okInit = pcall(M.OnInitialize, M)
  ok(okInit and reg["Custom: Ding"] == "Interface\\AddOns\\NockSounds\\ding.mp3", "OnInitialize registers the saved list")
  ok(reg["Custom: Bad"] == nil, "corrupted / invalid saved entries skipped without error")
  Nock.db.global.customSounds = nil
  ok(pcall(M.OnInitialize, M), "no saved list -> no error")
  lsmStub = nil
  Nock.db.global.customSounds = { { name = "X", source = "x.mp3" } }
  ok(pcall(M.OnInitialize, M), "no LSM -> no error")
end

print(("custom_sounds_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
