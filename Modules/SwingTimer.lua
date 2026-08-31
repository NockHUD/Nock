-- Modules/SwingTimer.lua
-- Tracks Auto Shot fires (ranged) and player melee swings; updates Nock.state.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local SwingTimer = Nock:NewModule("SwingTimer", "AceEvent-3.0")
local C = Nock.Constants

local STEADY_BASE_CAST = 1.5

local function autoShotName()
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(C.SpellID.AUTO_SHOT)
    if info and info.name then return info.name end
  end
  if GetSpellInfo then
    local n = GetSpellInfo(C.SpellID.AUTO_SHOT)
    if n then return n end
  end
  return "Auto Shot"
end

function SwingTimer:OnEnable()
  self.playerGUID = UnitGUID("player")
  self.autoShotName = autoShotName()
  self:RegisterEvent("PLAYER_LOGIN")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  self:RegisterEvent("UNIT_SPELLCAST_START")
  self:RegisterEvent("START_AUTOREPEAT_SPELL")
  self:RegisterEvent("STOP_AUTOREPEAT_SPELL")
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  self:RegisterEvent("UNIT_RANGED_ATTACK_POWER")
  self:RegisterEvent("UNIT_ATTACK_SPEED")
  self:RegisterEvent("UNIT_INVENTORY_CHANGED")
  self:RefreshSwingDurations()
end

function SwingTimer:PLAYER_LOGIN()
  self.playerGUID = UnitGUID("player")
  self.autoShotName = autoShotName()
  self:RefreshSwingDurations()
end

function SwingTimer:PLAYER_ENTERING_WORLD()
  self.playerGUID = self.playerGUID or UnitGUID("player")
  -- A loading screen can eat STOP_AUTOREPEAT_SPELL; a stranded `repeating`
  -- lies to every consumer (release bar arm chip reads it as "AUTO ON").
  Nock.state.ranged.repeating = false
  Nock.state.ranged.autoDelay = 0
  self._lastAutoShot = nil
  self:RefreshSwingDurations()
end

-- /nock swinglog — dummy-session evidence for the swing model (locked shot vs
-- rescale-remainder): every Auto Shot wind-up start / release / fail and every
-- ranged-speed edge, timestamped, with where the bar stood (elapsed/duration).
-- First call arms, second dumps into the copybox (project rule) and disarms.
-- Cheap when off: one nil check per event.
local SWINGLOG_MAX = 300

function SwingTimer:SwingLogToggle()
  if self._swingLog then
    local L = self._swingLog
    self._swingLog = nil
    if Nock.UI and Nock.UI.ShowCopyBox then
      Nock.UI.ShowCopyBox(table.concat(L, "\n"))
    end
  else
    self._swingLog = { ("swinglog armed  sd=%.3f  (time%% = bar fill at the event)")
      :format(UnitRangedDamage("player") or 0) }
    self._swingLogT0 = GetTime()
    Nock:Print("Swing log armed — /nock swinglog again to dump it.")
  end
end

function SwingTimer:SwingLogAdd(fmt, ...)
  local L = self._swingLog
  if not L or #L >= SWINGLOG_MAX then return end
  local now = GetTime()
  local r = Nock.state.ranged
  local pct = 0
  if r.swingStart > 0 and r.swingDuration > 0 then
    pct = (now - r.swingStart) / r.swingDuration * 100
  end
  L[#L + 1] = ("%+9.3f %6.1f%%  "):format(now - (self._swingLogT0 or now), pct) .. fmt:format(...)
end

function SwingTimer:RefreshSwingDurations()
  if Nock.state.sim.active then return end   -- practice mode owns the swing
  local rangedSpeed = UnitRangedDamage("player")
  if rangedSpeed and rangedSpeed > 0 then
    local r = Nock.state.ranged
    if self._swingLog and r.swingDuration > 0 and r.swingDuration ~= rangedSpeed then
      self:SwingLogAdd("SPEED %.3f -> %.3f", r.swingDuration, rangedSpeed)
    end
    -- A speed change never moves the pre-wind-up part of the shot in flight —
    -- only the wind-up runs at the new speed; the rest applies from the next
    -- shot (swinglog-evidenced; see Nock.ReanchorSwingStart). Shifting
    -- swingStart keeps start + duration == the true release for every
    -- consumer. Melee is deliberately left alone — its swingStart doubles as
    -- the last-hit timestamp.
    r.swingStart = Nock.ReanchorSwingStart(r.swingStart, r.swingDuration, rangedSpeed,
                                           GetTime(), r.windupRatio)
    r.swingDuration = rangedSpeed
  end
  local meleeSpeed = UnitAttackSpeed("player")
  if meleeSpeed and meleeSpeed > 0 then
    Nock.state.melee.swingDuration = meleeSpeed
  end
end

function SwingTimer:UNIT_RANGED_ATTACK_POWER(event, unit)
  if unit and unit ~= "player" then return end
  self:RefreshSwingDurations()
end

function SwingTimer:UNIT_ATTACK_SPEED(event, unit)
  if unit and unit ~= "player" then return end
  self:RefreshSwingDurations()
end

function SwingTimer:UNIT_INVENTORY_CHANGED(event, unit)
  if unit and unit ~= "player" then return end
  self:RefreshSwingDurations()
end

function SwingTimer:UNIT_SPELLCAST_SUCCEEDED(event, unit, arg1, arg2)
  if Nock.state.sim.active then return end   -- practice mode owns the swing
  if unit ~= "player" then return end
  local isAuto = false
  if type(arg2) == "number" and arg2 == C.SpellID.AUTO_SHOT then
    isAuto = true
  elseif type(arg1) == "string" and arg1 == self.autoShotName then
    isAuto = true
  end
  if isAuto then
    local now = GetTime()
    if self._swingLog then
      local prev = self._lastAutoShot
      self:SwingLogAdd("RELEASE  gap=%.3f", prev and (now - prev) or 0)
    end
    self:UpdateAutoDelay(now)
    self:UpdateWindup(now)
    Nock.state.ranged.swingStart = now
    self:RefreshSwingDurations()
  end
end

-- Auto Shot wind-up, measured per shot as (release - CLEU cast start).
--
-- It is NOT the fixed 0.5s the spell data reports: 0.5s is the value at BASE
-- weapon speed, and the real wind-up scales with the same haste multiplier as
-- the swing. Dummy-verified — 0.365s at eWS 2.174 (3.0 bow, 20% haste, 15%
-- quiver = 1.38x) and 0.265s under Rapid Fire at eWS 1.553 (1.93x), both
-- matching 0.5/hasteMul to within 10ms. Measuring beats modelling it: no base
-- weapon speed to look up, and no hardcoded quiver term to get wrong.
--
-- What's measured is the RATIO windup/swingDuration, not the absolute seconds:
-- the ratio is 0.5/baseWeaponSpeed and so is haste-invariant, which means one
-- clean sample at any haste is valid at every other haste. Core's tick turns it
-- back into seconds. See Core/State.lua for the numbers behind this.
--
-- Delayed cycles are REJECTED, not averaged in. When a shot is clipped the
-- wind-up starts on time but the release slips, so the measurement comes back
-- inflated — dummy run B showed 0.364 on a cycle that ran 0.072s late, against
-- ~0.21 on its clean neighbours. autoDelay (set just above, in UpdateAutoDelay)
-- is exactly that lateness, so it is the filter.
local WINDUP_MIN, WINDUP_MAX = 0.05, 1.0
local WINDUP_MAX_DELAY = 0.03   -- seconds of shot lateness that still counts as a clean cycle
local WINDUP_ALPHA     = 0.5    -- clean samples only, so it can converge fast

function SwingTimer:UpdateWindup(now)
  local start = self._windupStart
  local startSd = self._windupSd
  self._windupStart, self._windupSd = nil, nil
  if not start then return end

  local measured = now - start
  if measured < WINDUP_MIN or measured > WINDUP_MAX then return end
  if (Nock.state.ranged.autoDelay or 0) > WINDUP_MAX_DELAY then return end

  local sd = UnitRangedDamage("player") or Nock.state.ranged.swingDuration
  if not sd or sd <= 0 then return end
  -- Reject the shot a haste proc lands on: its wind-up began at the old speed
  -- and ended at the new one, so measured/sd mixes the two. Dummy run showed
  -- such a sample reading 0.2177 against ~0.169 on both sides of it.
  if startSd and math.abs(startSd - sd) > 0.005 then return end
  local ratio = measured / sd
  -- A wind-up longer than the swing itself, or vanishingly short, is a bad read.
  if ratio <= 0.01 or ratio >= 1 then return end

  local cur = Nock.state.ranged.windupRatio
  if not cur or cur <= 0 then
    Nock.state.ranged.windupRatio = ratio
  else
    Nock.state.ranged.windupRatio = cur + (ratio - cur) * WINDUP_ALPHA
  end
end

-- Steady Shot's real cast time, straight from the server. UnitCastingInfo works
-- for Steady (unlike Auto Shot, where it returns nil), so there is no reason for
-- the clip model to compute a cast time it can simply be told.
--
-- What's stored is the RESIDUAL against `1.5 / (1 + GetRangedHaste()/100)`, not
-- the absolute seconds — a residual stays valid when haste changes, so a proc is
-- reflected immediately rather than after the next Steady lands. See
-- Nock.RangedCastTime in Core/State.lua.
local CORR_MIN, CORR_MAX, CORR_ALPHA = 0.5, 1.5, 0.5

function SwingTimer:UNIT_SPELLCAST_START(event, unit)
  if Nock.state.sim.active then return end   -- practice mode owns the swing
  if unit ~= "player" then return end
  local name, _, _, startTime, endTime, _, _, _, spellId = UnitCastingInfo("player")
  if not name or spellId ~= C.SpellID.STEADY_SHOT then return end
  local measured = (endTime - startTime) / 1000
  if measured <= 0 then return end

  -- Predict with the same wind-up yardstick Nock.RangedCastTime uses, minus the
  -- correction itself, so a healthy model converges this to 1.0.
  local ref = C.AUTO_SHOT_CAST or 0.5
  local w = Nock.state.ranged.windup
  local predicted
  if w and w > 0 and ref > 0 then
    predicted = STEADY_BASE_CAST * (w / ref)
  else
    predicted = STEADY_BASE_CAST / (1 + ((GetRangedHaste and GetRangedHaste() or 0) / 100))
  end
  if predicted <= 0 then return end
  local corr = measured / predicted
  -- Out of range means something other than haste is in play (pushback is
  -- applied later via UNIT_SPELLCAST_DELAYED, so it shouldn't land here, but
  -- don't let a surprise poison the model either).
  if corr < CORR_MIN or corr > CORR_MAX then return end

  local cur = Nock.state.ranged.castHasteCorr
  if not cur or cur <= 0 then
    Nock.state.ranged.castHasteCorr = corr
  else
    Nock.state.ranged.castHasteCorr = cur + (corr - cur) * CORR_ALPHA
  end
end

-- Auto Shot delay: how much later than one full weapon-speed cycle the shot
-- actually fired (clamped >= 0), written to state.ranged.autoDelay in seconds.
-- Mirrors the React TBC Hunter WA: reset out of combat, and the first shot of a
-- combat just seeds the baseline (reports 0). Cheap — fires only on real shots.
function SwingTimer:UpdateAutoDelay(now)
  if not UnitAffectingCombat("player") then
    self._lastAutoShot = nil
    Nock.state.ranged.autoDelay = 0
  end
  if not self._lastAutoShot then
    self._lastAutoShot = now
    Nock.state.ranged.autoDelay = 0
    return
  end
  local elapsed = now - self._lastAutoShot
  local speed = UnitRangedDamage("player") or Nock.state.ranged.swingDuration
  Nock.state.ranged.autoDelay = math.max(0, elapsed - speed)
  self._lastAutoShot = now
end

function SwingTimer:START_AUTOREPEAT_SPELL()
  if Nock.state.sim.active then return end   -- practice mode owns the swing
  Nock.state.ranged.repeating = true
end

function SwingTimer:STOP_AUTOREPEAT_SPELL()
  if Nock.state.sim.active then return end   -- practice mode owns the swing
  Nock.state.ranged.repeating = false
end

-- "On next melee swing" abilities that consume + reset the melee swing timer
-- without firing a SWING_* event. All ranks of Raptor Strike + Mongoose Bite.
local NEXT_SWING_SPELLS = {
  -- Raptor Strike ranks (vanilla → TBC max)
  [2973]  = true, [14260] = true, [14261] = true, [14262] = true,
  [14263] = true, [14264] = true, [14265] = true, [14266] = true,
  [27014] = true,
  -- Mongoose Bite ranks
  [1495]  = true, [14269] = true, [14270] = true, [14271] = true, [36916] = true,
}

function SwingTimer:COMBAT_LOG_EVENT_UNFILTERED()
  if Nock.state.sim.active then return end   -- practice mode owns the swing
  local _, subevent, _, sourceGUID, _, _, _, _, _, _, _, spellId = CombatLogGetCurrentEventInfo()
  if sourceGUID ~= self.playerGUID then return end

  -- Wind-up start. CLEU is the only source — UnitCastingInfo returns nil for
  -- Auto Shot on this client (dummy-verified) — and it is delivered in the same
  -- frame as the immediate cast events, so the timestamp is trustworthy.
  if self._swingLog and spellId == C.SpellID.AUTO_SHOT
     and (subevent == "SPELL_CAST_START" or subevent == "SPELL_CAST_SUCCESS"
          or subevent == "SPELL_CAST_FAILED") then
    self:SwingLogAdd("%s  sd=%.3f", subevent, UnitRangedDamage("player") or 0)
  end

  if subevent == "SPELL_CAST_START" and spellId == C.SpellID.AUTO_SHOT then
    self._windupStart = GetTime()
    self._windupSd    = UnitRangedDamage("player")
  end

  if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
    Nock.state.melee.swingStart = GetTime()
    self:RefreshSwingDurations()
  elseif (subevent == "SPELL_DAMAGE" or subevent == "SPELL_MISSED")
         and NEXT_SWING_SPELLS[spellId] then
    -- Raptor / Mongoose: hit replaces the auto-attack swing — reset timer.
    Nock.state.melee.swingStart = GetTime()
    self:RefreshSwingDurations()
  end
end
