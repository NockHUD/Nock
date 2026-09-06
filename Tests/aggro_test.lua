-- Tests/aggro_test.lua
-- Modules/AggroWarning.lua: the aggro rule (threat status 2/3, the group gate, the switch) and the cue chain
-- (WeakAuras clip if it plays -> speech -> the picked sound -> the raid-warning kit), plus publish-once.
-- Run from the repo root: luajit Tests/aggro_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local now = 100
_G.GetTime = function() return now end
local threat, grouped = 0, false
_G.UnitThreatSituation = function() return threat end
_G.IsInRaid = function() return false end
_G.IsInGroup = function() return grouped end

local Nock = { state = {}, db = { profile = {} } }
local Aggro
function Nock:NewModule()
  Aggro = {}
  function Aggro:RegisterEvent() end
  function Aggro:RegisterMessage() end
  return Aggro
end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Modules/AggroWarning.lua")
ok(type(Aggro.Evaluate) == "function" and type(Aggro.PlayCue) == "function", "module loads")

-- 1. the rule ----------------------------------------------------------------
local E = Aggro.Evaluate
ok(E({}, 3, false) == true, "status 3 (tanking securely) -> aggro")
ok(E({}, 2, false) == true, "status 2 (tanking insecurely) -> aggro")
ok(E({}, 1, false) == false, "status 1 (high threat, not tanking) -> no")
ok(E({}, 0, false) == false and E({}, nil, false) == false, "no threat -> no")
ok(E({ aggroEnabled = false }, 3, true) == false, "switch off -> no")
ok(E({ aggroGroupOnly = true }, 3, false) == false, "group only + solo -> no")
ok(E({ aggroGroupOnly = true }, 3, true) == true, "group only + grouped -> aggro")
ok(E(nil, 3, true) == false, "no profile -> no")

-- 2. the cue chain -------------------------------------------------------------
local log
local function env(fileOk, speakOk, lsm)
  log = {}
  return {
    playFile = function(path) log[#log + 1] = "file:" .. tostring(path); return fileOk[path] == true end,
    speak = function(text) log[#log + 1] = "speak:" .. text; return speakOk end,
    lsmPath = function(name) return lsm and lsm[name] or nil end,
    playKit = function() log[#log + 1] = "kit" end,
  }
end
local WA = "Interface\\AddOns\\WeakAuras\\PowerAurasMedia\\Sounds\\aggro.ogg"
local base = { aggroSoundFile = WA, aggroSound = "Ping", aggroSpeechText = "Aggro" }
ok(Aggro.PlayCue(base, env({ [WA] = true }, true, { Ping = "p.ogg" })) == "file", "auto: the WeakAuras clip wins when it plays")
ok(Aggro.PlayCue(base, env({}, true, { Ping = "p.ogg" })) == "speech" and log[2] == "speak:Aggro", "auto: no clip -> speech says the text")
ok(Aggro.PlayCue(base, env({ ["p.ogg"] = true }, false, { Ping = "p.ogg" })) == "sound", "auto: no clip, no speech -> the picked sound")
ok(Aggro.PlayCue(base, env({}, false, {})) == "kit" and log[#log] == "kit", "auto: nothing else -> raid-warning kit")
ok(Aggro.PlayCue({ aggroSoundMode = "none" }, env({ [WA] = true }, true, {})) == nil and #log == 0, "none: silent")
ok(Aggro.PlayCue({ aggroSoundMode = "speech", aggroSoundFile = WA }, env({ [WA] = true }, true, {})) == "speech", "speech mode skips the clip")
ok(Aggro.PlayCue({ aggroSoundMode = "speech" }, env({}, false, {})) == nil, "speech mode with no TTS stays silent (no kit)")
ok(Aggro.PlayCue({ aggroSoundMode = "sound", aggroSound = "Ping" }, env({ ["p.ogg"] = true }, true, { Ping = "p.ogg" })) == "sound", "sound mode plays the pick only")
ok(Aggro.PlayCue({ aggroSoundMode = "sound", aggroSound = "None" }, env({}, true, {})) == nil, "sound mode with None is silent")
ok(Aggro.PlayCue({ aggroSoundMode = "file", aggroSoundFile = WA }, env({}, true, {})) == nil, "file mode with a missing file is silent")

-- 3. publish once per pull of aggro ------------------------------------------------
local cues = 0
local realPlay = Aggro.PlayCue
Aggro.PlayCue = function() cues = cues + 1; return "test" end
Nock.db.profile = {}
threat = 3
Aggro:UNIT_THREAT_SITUATION_UPDATE(nil, "player")
ok(Nock.state.aggro and Nock.state.aggro.active == true and cues == 1, "threat 3 -> active, one cue")
Aggro:UNIT_THREAT_SITUATION_UPDATE(nil, "player")
ok(cues == 1, "a repeat update while still tanking does not re-cue")
Aggro:UNIT_THREAT_SITUATION_UPDATE(nil, "target")
ok(cues == 1, "another unit's update is ignored")
threat = 1
Aggro:UNIT_THREAT_SITUATION_UPDATE(nil, "player")
ok(Nock.state.aggro.active == false, "dropping to status 1 clears")
threat = 2
Aggro:UNIT_THREAT_SITUATION_UPDATE(nil, "player")
ok(Nock.state.aggro.active == true and cues == 2, "regaining aggro cues again")
Aggro:PLAYER_REGEN_ENABLED()
ok(Nock.state.aggro.active == false, "leaving combat clears")
Aggro.PlayCue = realPlay

print(("aggro_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
