-- Forever/SwingTimer.lua
-- Forever swing source: the native PLAYER_SWING event (plain numbers in combat)
-- drives state.ranged / state.melee; no combat log, no UnitRangedDamage polling.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local SwingTimer = Nock:NewModule("SwingTimer", "AceEvent-3.0")

local SAMPLE_MAX = 20

local function swingType(name)
  local E = _G.Enum and _G.Enum.PlayerSwingType
  return E and E[name]
end

function SwingTimer:OnEnable()
  self._samples = {}
  self:RegisterEvent("PLAYER_SWING")
  self:RegisterEvent("START_AUTOREPEAT_SPELL")
  self:RegisterEvent("STOP_AUTOREPEAT_SPELL")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

-- Fires when a swing happens; `duration` is the time until the next one at
-- the current speed (Blizzard_SwingTimer resets its bar the same way).
function SwingTimer:PLAYER_SWING(event, duration, kind)
  local now = GetTime()
  local S = self._samples
  S[#S + 1] = { t = now, swingType = kind, duration = duration }
  if #S > SAMPLE_MAX then table.remove(S, 1) end
  if type(duration) ~= "number" or duration <= 0 then return end
  if kind == swingType("Ranged") then
    local r = Nock.state.ranged
    r.swingStart = now
    r.swingDuration = duration
  elseif kind == swingType("MainHand") then
    local m = Nock.state.melee
    m.swingStart = now
    m.swingDuration = duration
  end
end

function SwingTimer:START_AUTOREPEAT_SPELL()
  Nock.state.ranged.repeating = true
end

function SwingTimer:STOP_AUTOREPEAT_SPELL()
  Nock.state.ranged.repeating = false
end

function SwingTimer:PLAYER_ENTERING_WORLD()
  -- A loading screen can eat STOP_AUTOREPEAT_SPELL; a stranded `repeating`
  -- would keep the auto bar full (see Nock.AutoSwingLive).
  Nock.state.ranged.repeating = false
  Nock.state.ranged.autoDelay = 0
end

-- The tick calls this on the TBC module after a speed poll; on Forever the
-- duration arrives with each swing and UnitRangedDamage is secret in combat.
function SwingTimer:RefreshSwingDurations() end

-- Last SAMPLE_MAX raw payloads, oldest first (for /nock probe).
function SwingTimer:Samples()
  local out = {}
  for i = 1, #self._samples do out[i] = self._samples[i] end
  return out
end
