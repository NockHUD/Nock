-- Modules/AggroWarning.lua
-- You have aggro: publishes state.aggro from the threat-situation event and plays the cue once per pull of aggro.
--
-- The cue chain (user, 2026-09-11): WeakAuras' Power Auras "aggro" voice
-- clip if that file plays on this machine, else the game's text-to-speech,
-- else the LibSharedMedia sound picked in the settings, else the raid-warning
-- kit. Nothing is bundled: the clip is Power Auras media without a stated
-- licence, so Nock only points at a file the user installed themselves.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Aggro = Nock:NewModule("AggroWarning", "AceEvent-3.0")

local function profile()
  return Nock.db and Nock.db.profile or nil
end

local function inGroup()
  if IsInRaid and IsInRaid() then return true end
  if IsInGroup and IsInGroup() then return true end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return true end
  if GetNumPartyMembers and GetNumPartyMembers() > 0 then return true end
  return false
end

-- ---------------------------------------------------------------------------
-- The rule. `status` is UnitThreatSituation("player"): nil/0 no threat, 1
-- higher threat than the tank but not tanking, 2 tanking insecurely, 3
-- tanking securely. Aggro = 2 or 3 (WeakAuras' "aggro" reading). Pure.
-- ---------------------------------------------------------------------------
function Aggro.Evaluate(p, status, grouped, pvp)
  if not p or p.aggroEnabled == false then return false end
  if pvp and p.pvpNoAggro == true then return false end   -- PvP mode: threat is a creature thing
  if p.aggroGroupOnly and not grouped then return false end
  return (tonumber(status) or 0) >= 2
end

-- ---------------------------------------------------------------------------
-- The cue chain. `env` lets the test stand in for the client: playFile(path)
-- -> boolean, speak(text) -> boolean, lsmPath(name) -> path|nil,
-- playKit(id). Returns which tier sounded: "file" | "speech" | "sound" |
-- "kit" | nil.
-- ---------------------------------------------------------------------------
local function realEnv()
  return {
    playFile = function(path, channel)
      if not (path and path ~= "" and PlaySoundFile) then return false end
      local ok, willPlay = pcall(PlaySoundFile, path, channel or "Master")
      return ok and willPlay and true or false
    end,
    speak = function(text)
      if not (C_VoiceChat and C_VoiceChat.SpeakText) then return false end
      local voiceID
      if C_VoiceChat.GetTtsVoices then
        local voices = C_VoiceChat.GetTtsVoices()
        if voices and voices[1] then voiceID = voices[1].voiceID end
      end
      local dest = (Enum and Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback) or 1
      local ok = pcall(C_VoiceChat.SpeakText, voiceID or 0, text, dest, 0, 100)
      return ok and true or false
    end,
    lsmPath = function(name)
      if not name or name == "" or name == "None" then return nil end
      local lsm = LibStub("LibSharedMedia-3.0", true)
      return lsm and lsm:Fetch("sound", name) or nil
    end,
    playKit = function()
      if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master") end
    end,
  }
end

function Aggro.PlayCue(p, env)
  if not p then return nil end
  env = env or realEnv()
  local mode = p.aggroSoundMode or "auto"
  if mode == "none" then return nil end
  local channel = p.aggroSoundChannel or "Master"
  if mode == "auto" or mode == "file" then
    if env.playFile(p.aggroSoundFile, channel) then return "file" end
    if mode == "file" then return nil end
  end
  if mode == "auto" or mode == "speech" then
    if env.speak(p.aggroSpeechText or "Aggro") then return "speech" end
    if mode == "speech" then return nil end
  end
  local path = env.lsmPath(p.aggroSound)
  if path and env.playFile(path, channel) then return "sound" end
  if mode == "sound" then return nil end
  env.playKit()
  return "kit"
end

-- ---------------------------------------------------------------------------
-- State: the event writes state.aggro; the flash view reads it on the tick.
-- ---------------------------------------------------------------------------
local function publish(self, active, status)
  local st = Nock.state
  if not st then return end
  st.aggro = st.aggro or { active = false, status = 0, since = 0 }
  local was = st.aggro.active
  st.aggro.active, st.aggro.status = active, status or 0
  if active and not was then
    st.aggro.since = GetTime()
    Aggro.PlayCue(profile())
  end
end

function Aggro:Reevaluate()
  local status = UnitThreatSituation and UnitThreatSituation("player") or 0
  local st = Nock.state and Nock.state.player
  publish(self, Aggro.Evaluate(profile(), status, inGroup(), st ~= nil and st.pvp == true), status)
end

function Aggro:UNIT_THREAT_SITUATION_UPDATE(_, unit)
  if unit ~= "player" then return end
  self:Reevaluate()
end

function Aggro:PLAYER_REGEN_ENABLED()
  -- leaving combat ends every threat situation
  publish(self, false, 0)
end

function Aggro:OnEnable()
  self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "Reevaluate")
end
