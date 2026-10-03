-- Forever/SwingTimer.lua
-- Forever swing source: the native PLAYER_SWING event (plain numbers in combat)
-- drives state.ranged / state.melee; no combat log, no UnitRangedDamage polling.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local SwingTimer = Nock:NewModule("SwingTimer", "AceEvent-3.0")

local SAMPLE_MAX = 20

-- A Ranged PLAYER_SWING this soon after a melee hit is the client's own reset
-- of the ranged reload (Forever client bug: melee resets ranged; fix pending),
-- not a shot. Same grace as the weave engine's RESET_GRACE. Delete with the
-- rest of the reset handling once the client fix lands.
local RESET_GRACE = 0.1

local function swingType(name)
  local E = _G.Enum and _G.Enum.PlayerSwingType
  return E and E[name]
end

function SwingTimer:OnEnable()
  self._samples = {}
  self:RegisterEvent("PLAYER_SWING")
  self:RegisterEvent("START_AUTOREPEAT_SPELL")
  self:RegisterEvent("STOP_AUTOREPEAT_SPELL")
  -- Melee auto-attack on/off (despite the names these are the attack toggle,
  -- not combat state); the "not attacking" warning reads state.melee.attacking.
  self:RegisterEvent("PLAYER_ENTER_COMBAT")
  self:RegisterEvent("PLAYER_LEAVE_COMBAT")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
  self:RegisterEvent("CVAR_UPDATE")
  -- Probe instrumentation (wind-up question, 2026-09-23): the client's own
  -- movement edges, so each swing sample can say how long the player had
  -- stood still at the release. A wind-up shows as a floor on that number.
  self:RegisterEvent("PLAYER_STARTED_MOVING")
  self:RegisterEvent("PLAYER_STOPPED_MOVING")
  self._moving, self._movedAt, self._stoppedAt = false, nil, nil
  self:RefreshQueueWindow()
  -- The client's own ranged range check: off until asked for, then it
  -- signals PLAYER_SWING_RANGE_UPDATE on every edge (plain in combat).
  local ST, kind = _G.C_SwingTimer, swingType("Ranged")
  if ST and ST.EnableRangeCheck and kind ~= nil then
    ST.EnableRangeCheck(kind, true)
    self:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
  end
  self:RefreshTargetRange()
end

-- Direct read on target change; the event covers every edge after that.
-- SpellQueueWindow is milliseconds as a string ("400"); anything unreadable
-- falls back to the client default. Clamped to a second: a window longer
-- than that is a misconfiguration, not a mark to draw.
function SwingTimer.QueueWindowSeconds(raw)
  local ms = tonumber(raw)
  if not ms or ms < 0 then ms = 400 end
  if ms > 1000 then ms = 1000 end
  return ms / 1000
end

function SwingTimer:RefreshQueueWindow()
  local raw = _G.GetCVar and Nock.Flavor.Plain(_G.GetCVar("SpellQueueWindow")) or nil
  Nock.state.ranged.queueWindow = SwingTimer.QueueWindowSeconds(raw)
end

function SwingTimer:CVAR_UPDATE(event, name)
  if name == "SpellQueueWindow" then self:RefreshQueueWindow() end
end

function SwingTimer:RefreshTargetRange()
  local ST, kind = _G.C_SwingTimer, swingType("Ranged")
  local v = nil
  if ST and ST.IsTargetWithinSwingRange and kind ~= nil then
    v = Nock.Flavor.Plain(ST.IsTargetWithinSwingRange(kind))
    if type(v) ~= "boolean" then v = nil end
  end
  Nock.state.ranged.targetInRange = v
end

function SwingTimer:PLAYER_TARGET_CHANGED()
  self:RefreshTargetRange()
end

function SwingTimer:PLAYER_SWING_RANGE_UPDATE(event, kind, isInRange, checksRange)
  if kind ~= swingType("Ranged") then return end
  -- Seen once: the client's signal owns targetInRange from here on and the
  -- range finder's shoot probe stops writing it.
  Nock.state.ranged.swingRangeSignal = true
  if checksRange and type(isInRange) == "boolean" then
    Nock.state.ranged.targetInRange = isInRange
  else
    Nock.state.ranged.targetInRange = nil
  end
end

-- Fires when a swing happens; `duration` is the time until the next one at
-- the current speed (Blizzard_SwingTimer resets its bar the same way).
function SwingTimer:PLAYER_STARTED_MOVING()
  self._moving, self._movedAt = true, GetTime()
end

function SwingTimer:PLAYER_STOPPED_MOVING()
  self._moving, self._stoppedAt = false, GetTime()
end

-- Auto Shot delay (the "clip timer" readout): how much later than the bar's
-- own due time this shot fired, clamped >= 0, in state.ranged.autoDelay. The
-- same number Modules/SwingTimer.lua writes on TBC, measured here against
-- state.ranged.swingStart + swingDuration (the bar as drawn), so a reload the
-- weave helper re-anchored on a melee hit counts from the hit, not from the
-- previous shot. Out of combat the readout rests at 0; the first shot of a
-- fight only seeds the baseline. Reads the state BEFORE the shot overwrites it.
function SwingTimer:UpdateAutoDelay(now)
  local r = Nock.state.ranged
  if not Nock.state.player.inCombat then
    self._lastShotAt = nil
    r.autoDelay = 0
    return
  end
  if not self._lastShotAt or r.swingStart <= 0 or r.swingDuration <= 0 then
    self._lastShotAt = now
    r.autoDelay = 0
    return
  end
  r.autoDelay = math.max(0, now - (r.swingStart + r.swingDuration))
  self._lastShotAt = now
end

function SwingTimer:PLAYER_SWING(event, duration, kind)
  local now = GetTime()
  local S = self._samples
  local stillFor = (not self._moving and self._stoppedAt) and (now - self._stoppedAt) or nil
  S[#S + 1] = { t = now, swingType = kind, duration = duration, moving = self._moving == true, stillFor = stillFor }
  if #S > SAMPLE_MAX then table.remove(S, 1) end
  if type(duration) ~= "number" or duration <= 0 then return end
  if kind == swingType("Ranged") then
    local r = Nock.state.ranged
    local isReset = self._lastHitAt ~= nil and (now - self._lastHitAt) <= RESET_GRACE
    if not isReset then self:UpdateAutoDelay(now) end
    r.swingStart = now
    r.swingDuration = duration
  elseif kind == swingType("MainHand") then
    local m = Nock.state.melee
    m.swingStart = now
    m.swingDuration = duration
    self._lastHitAt = now
  elseif kind == swingType("OffHand") then
    local m = Nock.state.melee
    m.offStart = now
    m.offDuration = duration
    self._lastHitAt = now
  end
end

-- Dual wield (hunters from level 20): the client's own answer, re-read on
-- login and every gear change. Anything but a plain true reads as one weapon.
function SwingTimer:RefreshDualWield()
  local v
  if _G.IsDualWielding then
    v = Nock.Flavor.Plain(_G.IsDualWielding())
  elseif _G.C_PaperDollInfo and _G.C_PaperDollInfo.OffhandHasWeapon then
    v = Nock.Flavor.Plain(_G.C_PaperDollInfo.OffhandHasWeapon())
  end
  local m = Nock.state.melee
  m.dualWield = v == true
  if not m.dualWield then m.offStart, m.offRemaining = 0, 0 end
end

function SwingTimer:PLAYER_EQUIPMENT_CHANGED()
  self:RefreshDualWield()
end

function SwingTimer:START_AUTOREPEAT_SPELL()
  Nock.state.ranged.repeating = true
end

function SwingTimer:STOP_AUTOREPEAT_SPELL()
  Nock.state.ranged.repeating = false
end

function SwingTimer:PLAYER_ENTER_COMBAT()
  Nock.state.melee.attacking = true
end

function SwingTimer:PLAYER_LEAVE_COMBAT()
  Nock.state.melee.attacking = false
end

function SwingTimer:PLAYER_ENTERING_WORLD()
  -- A loading screen can eat STOP_AUTOREPEAT_SPELL; a stranded `repeating`
  -- would keep the auto bar full (see Nock.AutoSwingLive).
  Nock.state.ranged.repeating = false
  Nock.state.ranged.autoDelay = 0
  self._lastShotAt, self._lastHitAt = nil, nil
  Nock.state.melee.attacking = false
  self:RefreshDualWield()
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
