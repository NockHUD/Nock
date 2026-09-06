-- Modules/WeaveSounds.lua
-- Weave outcome cues from the combat log: a Raptor Strike that lands, and a Windfury proc (extra attacks).
--
-- Both are your own events only (sourceGUID = player), each behind its own
-- switch with a LibSharedMedia sound (Alerts -> Sounds -> Weaving), played on
-- the dead-zone output channel. The spell names are resolved from IDs once,
-- so the match is locale-proof; a client that cannot resolve the Windfury
-- attack name falls back to "any extra attacks of yours" (a hunter has no
-- other source of them).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local WeaveSounds = Nock:NewModule("WeaveSounds", "AceEvent-3.0")
local C = Nock.Constants

local function profile()
  return Nock.db and Nock.db.profile or nil
end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    if type(info) == "table" then return info.name end
    return info
  end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- Pure: which cue (if any) a combat-log packet earns. `names` is the resolved
-- { raptor = "...", windfury = "..." } (either may be nil).
function WeaveSounds.Classify(sub, sourceGUID, playerGUID, spellId, name, names)
  if sourceGUID ~= playerGUID then return nil end
  if sub == "SPELL_DAMAGE" then
    if (names.raptor and name == names.raptor) or spellId == C.SpellID.RAPTOR_STRIKE then return "raptor" end
    return nil
  end
  if sub == "SPELL_EXTRA_ATTACKS" then
    if not names.windfury then return "windfury" end
    if name == names.windfury or spellId == C.SpellID.WINDFURY_ATTACK then return "windfury" end
  end
  return nil
end

local function play(p, key)
  local soundName = p[key]
  if not soundName or soundName == "" or soundName == "None" then return end
  local LSM = LibStub("LibSharedMedia-3.0", true)
  if not LSM then return end
  local path = LSM:Fetch("sound", soundName)
  if path and PlaySoundFile then PlaySoundFile(path, p.deadZoneSoundChannel or "Master") end
end

function WeaveSounds:COMBAT_LOG_EVENT_UNFILTERED()
  local p = profile()
  if not p or not (p.weaveRaptorHitEnabled or p.weaveWfProcEnabled) then return end
  if not CombatLogGetCurrentEventInfo then return end
  local _, sub, _, sourceGUID, _, _, _, _, _, _, _, spellId, name = CombatLogGetCurrentEventInfo()
  if sub ~= "SPELL_DAMAGE" and sub ~= "SPELL_EXTRA_ATTACKS" then return end
  local cue = WeaveSounds.Classify(sub, sourceGUID, self._playerGUID, spellId, name, self._names)
  if cue == "raptor" and p.weaveRaptorHitEnabled then play(p, "weaveRaptorHitSound")
  elseif cue == "windfury" and p.weaveWfProcEnabled then play(p, "weaveWfProcSound") end
end

function WeaveSounds:PLAYER_LOGIN()
  self._playerGUID = UnitGUID and UnitGUID("player") or self._playerGUID
  self._names = { raptor = spellName(C.SpellID.RAPTOR_STRIKE), windfury = spellName(C.SpellID.WINDFURY_ATTACK) }
end

function WeaveSounds:OnEnable()
  self._names = self._names or {}
  self:RegisterEvent("PLAYER_LOGIN")
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  self:PLAYER_LOGIN()
end
