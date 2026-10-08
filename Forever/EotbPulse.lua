-- Forever/EotbPulse.lua
-- The Eyes of the Beast pulse timer: a beat counted from the pull, published as state.eotbPulse for the pulse bar.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Pulse = Nock:NewModule("EotbPulse", "AceEvent-3.0")

-- A pet under Eyes of the Beast pulls nearby mobs on a fixed beat counted
-- from the moment combat starts; players put it at 5.5-5.6 s (the "EotB Pet
-- Combat Pulse" WeakAura by Rubot, wago f_y-jlrhK), so the period is a
-- setting. The beat is anchored on PLAYER_REGEN_DISABLED and restarted by a
-- resync (right-click on the bar, /nock pulse). Own channels are plain on
-- Forever (Forever/CastBar.lua), so "under EotB" is the cast record.
Pulse.PERIOD_DEFAULT = 5.6
Pulse.PERIOD_MIN, Pulse.PERIOD_MAX = 1, 10

-- Seconds from `now` to the next pulse of the beat started at `anchor`.
function Pulse.Remaining(now, anchor, period)
  return period - ((now - anchor) % period)
end

local function period()
  local p = Nock.db and Nock.db.profile
  local v = tonumber(p and p.eotbPulsePeriod)
  if not v then return Pulse.PERIOD_DEFAULT end
  return math.max(Pulse.PERIOD_MIN, math.min(Pulse.PERIOD_MAX, v))
end

local function isEotb(c)
  if not (c and c.isChannel) then return false end
  local id = Nock.Spells.EYES_OF_THE_BEAST
  if c.spellId == id then return true end
  local n = Nock.Flavor.Plain(Nock.API.SpellName(id))
  return type(n) == "string" and c.name == n
end

local anchor

function Pulse:OnEnable()
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Pulse:PLAYER_REGEN_DISABLED() anchor = GetTime() end
function Pulse:PLAYER_REGEN_ENABLED() anchor = nil end

-- Restart the beat from now: the pet's pulse drifted from the pull.
function Pulse:Resync()
  anchor = GetTime()
end

function Pulse:Command()
  self:Resync()
  Nock:Print("Eyes of the Beast pulse resynced.")
end

-- Derived every tick: active and the seconds to the next pulse. Published
-- whatever the display settings say.
function Pulse:Refresh(state)
  local e = state.eotbPulse
  if not e then e = {}; state.eotbPulse = e end
  e.period = period()
  local pl = state.player
  local c = pl and pl.casting
  e.active = anchor ~= nil and pl ~= nil and pl.inCombat == true and isEotb(c)
  e.remaining = e.active and Pulse.Remaining(GetTime(), anchor, e.period) or nil
end
