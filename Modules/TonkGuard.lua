-- Modules/TonkGuard.lua
-- Steps you back out of the Steam Tonk Controller transform a settling interval
-- after it lands -- in combat or out. Using the tonk and cancelling it in the
-- same macro frame welds the client (the cancel is sent before the cast is even
-- transmitted), so the shipped advice is to /use it alone and let this do the
-- exit.
--
-- THE EXIT IS `PetDismiss()`, AND THAT IS THE WHOLE TRICK.
-- Credit: Big Chungus, in the Classic Hunter Discord.
--
-- The tonk is a CHARM, not a buff you wear and not a vehicle: you are driving a
-- charmed creature, which is why Call Pet refuses with "You already control a
-- charmed creature" while transformed. Dismiss the creature and the transform
-- goes with it. Pet control carries no combat protection, where every
-- aura-cancel API on this client is protected and raises ADDON_ACTION_BLOCKED.
--
-- We had all of that written down on 2026-08-13 and still spent the day
-- attacking the AURA -- CancelSpellByName, CancelUnitBuff, CancelPlayerBuff,
-- CancelShapeshiftForm, VehicleExit, secure snippets -- never once calling a pet
-- function, and then declared in-combat cancellation impossible on the strength
-- of it. The true statement "no addon can cancel an aura in combat" had been
-- quietly promoted into the false one "no addon can exit the tonk in combat".
--
-- Detection is not ours: Modules/Auras.lua publishes state.player.tonk from the
-- player buff scan it already runs and broadcasts NOCK_TONK_CHANGED on the
-- edge. This module only decides (via the pure Modules/TonkEngine.lua) and
-- acts. Idle cost is zero: no OnUpdate, no standing timers, one subscription.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local TonkGuard = Nock:NewModule("TonkGuard", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
local C = Nock.Constants
local E = Nock.TonkEngine

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile
  if p and p[key] ~= nil then return p[key] end
  return fallback
end

local function delaySec()
  return Nock.TonkCancelDelay()
end

local function inCombat()
  if UnitAffectingCombat then return UnitAffectingCombat("player") and true or false end
  if InCombatLockdown then return InCombatLockdown() and true or false end
  return false
end

-- ---------------------------------------------------------------------------
-- Diagnostics. /nock tonkdebug, off by default and free when off: a flag, an
-- early return, and no registered events.
--
-- Kept in the shipped addon deliberately, and kept SMALL. "I got welded" is the
-- one report this feature will ever generate, and it is untriageable from
-- behaviour alone -- the two numbers that decide it, how long the aura had been
-- up and how many dismisses went out, are both invisible from the outside. The
-- trace narrates every path INCLUDING the early returns, because a debug mode
-- that goes quiet when it declines to act is worse than none.
--
-- ADDON_ACTION_BLOCKED is hooked only while tracing, and only because the
-- in-game gate for the PetDismiss switch needs to distinguish "the dismiss was
-- refused" from "the dismiss ran and the server ignored it". Behaviour alone
-- cannot tell those apart, and guessing is how the aura-cancel dead end lasted
-- a full day.
-- ---------------------------------------------------------------------------
local function trace(self, fmt, ...)
  if not self._trace then return end
  self:Print("|cff909090[tonk]|r " .. fmt:format(...))
end

function TonkGuard:SetTrace(on)
  self._trace = on and true or false
  -- pcall'd: AceEvent hard-errors on an event this client does not know, and a
  -- diagnostic toggle must never be able to take the addon down. BLOCKED is
  -- confirmed present here; FORBIDDEN is along for the ride.
  for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    if self._trace then
      pcall(self.RegisterEvent, self, ev, "OnActionBlocked")
    else
      pcall(self.UnregisterEvent, self, ev)
    end
  end
  return self._trace
end

function TonkGuard:OnActionBlocked(event, addon, func)
  trace(self, "|cffff4040%s|r: %s / %s", tostring(event), tostring(addon), tostring(func))
end

-- Returns the path taken, or nil. A path name is NOT a promise the call had any
-- effect -- pcall succeeding only means it did not error.
--
-- PetDismiss goes first and is the only path tried in combat. The aura-cancel
-- family stays as an out-of-combat fallback: it is verified to work there, and
-- verified blocked in combat, where attempting it would only taint.
--
-- The gate on tonk.active is not defensive tidiness, it is the entire safety
-- argument: PetDismiss with no transform up dismisses the player's REAL pet,
-- which is the exact loss this feature exists to prevent. Every caller re-reads
-- state before calling, and so does this.
local function cancelTonk(name)
  if not Nock.state.player.tonk.active then return nil end
  if PetDismiss then
    if pcall(PetDismiss) then return "PetDismiss" end
  end
  if inCombat() then return nil end
  if name and CancelSpellByName then
    if pcall(CancelSpellByName, name) then return "CancelSpellByName" end
  end
  if CancelUnitBuff and UnitBuff then
    local i = 1
    while true do
      local n, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
      if not n then break end
      if spellId == C.SpellID.STEAM_TONK or (name and n == name) then
        pcall(CancelUnitBuff, "player", i)
        return "CancelUnitBuff#" .. i
      end
      i = i + 1
    end
  end
  return nil
end

function TonkGuard:OnEnable()
  self:RegisterMessage("NOCK_TONK_CHANGED", "OnTonkChanged")
  -- Backstop only, now that the guard runs in combat too: a transform taken
  -- during a fight is already handled where it happens. This still catches the
  -- case where the addon loaded, or the setting was turned on, mid-transform.
  self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
  self._canCancel = (PetDismiss ~= nil) or (CancelSpellByName ~= nil) or (CancelUnitBuff ~= nil)
end

function TonkGuard:OnRegenEnabled()
  if Nock.state.player.tonk.active then self:Arm() end
end

function TonkGuard:OnTonkChanged(_, active)
  trace(self, "aura edge: %s", active and "APPEARED" or "gone")
  if active then self:Arm() else self:Disarm() end
end

-- Offset from the current transform's anchor, for the trace.
function TonkGuard:Offset()
  if not self._anchor then return "idle" end
  return ("+%.3fs"):format(GetTime() - self._anchor)
end

-- Rising edge. Schedules the first attempt for the remainder of the delay; the
-- engine clamps that at zero, so re-arming after a /reload mid-transform fires
-- at once instead of scheduling a negative timer.
function TonkGuard:Arm()
  if not profile("tonkAutoCancel", true) then
    trace(self, "auto-cancel is OFF -- not arming (Settings > Utilities > Steam Tonk)")
    return
  end
  if not self._canCancel then
    if not self._noApiWarned then
      self._noApiWarned = true
      self:Print("this client provides no way to dismiss the tonk, so the Steam Tonk guard cannot run. Step out of it yourself.")
    end
    return
  end
  if self._fireTimer or self._sweep then
    trace(self, "already armed -- leaving the existing timer alone")
    return
  end
  local t = Nock.state.player.tonk
  local now  = GetTime()
  local wait = E.WaitFor(t.since, now, delaySec())
  -- Stash the anchor: Auras clears t.since on the falling edge, and the trace
  -- still wants to report the exit offset against it.
  self._anchor, self._cancels = t.since, 0
  trace(self, "armed: anchor %.3fs in the past, waiting %.3fs (delay %.2fs, combat=%s)",
        t.since and (now - t.since) or -1, wait, delaySec(), tostring(inCombat()))
  self._fireTimer = self:ScheduleTimer("Fire", wait)
end

-- Every dismiss attempt goes through here so the trace can count them.
function TonkGuard:Cancel()
  local t = Nock.state.player.tonk
  self._cancels   = (self._cancels or 0) + 1
  self._lastTryAt = GetTime()
  local done = cancelTonk(t.name)
  trace(self, "dismiss #%d at %s via %s (combat=%s)",
        self._cancels, self:Offset(), tostring(done), tostring(inCombat()))
  return done
end

function TonkGuard:Fire()
  self._fireTimer = nil
  self._fired, self._firedAt = true, GetTime()
  self:Cancel()
  if not self._sweep then
    self._sweep = self:ScheduleRepeatingTimer("Sweep", E.SWEEP_INTERVAL)
  end
end

-- The retry loop. The reference WeakAura latches after one attempt and leaves
-- you welded if it no-ops; we keep trying until the transform is genuinely gone
-- or the cap expires. The "disarm" branch is a backstop for a missed edge
-- message.
function TonkGuard:Sweep()
  local t = Nock.state.player.tonk
  local step = E.Step(t.active, t.since, GetTime(), delaySec(),
                      self._fired, self._firedAt, self._lastTryAt)
  if step == "disarm" then
    self:Disarm()
  elseif step == "giveup" then
    self:GiveUp()
  elseif step == "retry" or step == "fire" then
    self:Cancel()
  end
end

-- Idempotent; safe from any path, including from inside the sweep callback.
-- The one-time notice is emitted HERE, on the falling edge, and only when we
-- actually fired -- so it can never claim an exit that did not happen.
function TonkGuard:Disarm()
  local fired = self._fired
  if fired then
    trace(self, "gone at %s after %d dismiss call(s) (combat=%s)",
          self:Offset(), self._cancels or 0, tostring(inCombat()))
  end
  if self._fireTimer then self:CancelTimer(self._fireTimer, true); self._fireTimer = nil end
  if self._sweep    then self:CancelTimer(self._sweep, true);      self._sweep = nil end
  self._fired, self._firedAt, self._lastTryAt = false, nil, nil
  self._anchor, self._cancels = nil, nil
  if fired and Nock.db and Nock.db.char and not Nock.db.char.tonkNoticeShown then
    Nock.db.char.tonkNoticeShown = true
    self:Print(("stepped you out of the Steam Tonk %.2fs after it landed -- that is what prevents the movement bug. Settings > Utilities > Steam Tonk turns it off if you would rather drive the tonk."):format(delaySec()))
  end
end

-- Clearing _fired first suppresses the success notice: we are giving up
-- precisely because the dismiss did NOT take, and claiming it would be a lie.
function TonkGuard:GiveUp()
  trace(self, "gave up at +%.3fs from anchor after %d dismiss call(s) -- still in the tonk",
        self._anchor and (GetTime() - self._anchor) or -1, self._cancels or 0)
  self._fired = false
  self:Disarm()
  if not self._gaveUpThisSession then
    self._gaveUpThisSession = true
    self:Print("could not get you out of the Steam Tonk. Try /nock tonk, or right-click the buff to cancel it yourself.")
  end
end

-- /nock tonk. The manual unstick: dismiss now with no delay and keep retrying.
-- Deliberately works even with tonkAutoCancel off, because someone who has
-- turned the guard off is exactly the person who may need to be let out.
function TonkGuard:PanicCancel()
  local t = Nock.state.player.tonk
  if not t.active then
    self:Print("you are not in a Steam Tonk.")
    return
  end
  if self._fireTimer then self:CancelTimer(self._fireTimer, true); self._fireTimer = nil end
  self._fired, self._firedAt = true, GetTime()
  self._gaveUpThisSession = nil     -- an explicit ask deserves a fresh verdict
  self._anchor  = self._anchor or t.since or GetTime()
  self._cancels = self._cancels or 0
  self:Cancel()
  if not self._sweep then
    self._sweep = self:ScheduleRepeatingTimer("Sweep", E.SWEEP_INTERVAL)
  end
end
