-- Modules/CastBar.lua
-- Tracks player casts and channels via CLEU + UNIT_SPELLCAST_CHANNEL_* events.
-- CLEU is the canonical source: UnitCastingInfo returns nil for ranged shots like
-- Multi-Shot on this build, but COMBAT_LOG_EVENT_UNFILTERED reliably fires
-- SPELL_CAST_START for them. UnitCastingInfo is still consulted first for casts where
-- it works (Steady Shot, regular casts) because its endTime is server-authoritative.
--
-- Publishes TWO fields, deliberately: state.player.casting for real casts (which
-- always mean "locked out") and state.player.autoShotCast for the Auto Shot
-- wind-up (which means the opposite — a press there is queued for free). Both are
-- written unconditionally; whether either is *shown* is the views' decision, via
-- Nock.CastBarSource. See Core/State.lua for why the split exists.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local CastBar = Nock:NewModule("CastBar", "AceEvent-3.0", "AceConsole-3.0")

local info = {
  name = nil, spellId = nil, icon = nil,
  startTime = 0, endTime = 0, isChannel = false,
}

-- Dedicated table for the Feign Death bar so a feign in progress never clobbers
-- (or is clobbered by) a real cast's `info`. Rendered as a channel so the bar
-- depletes right-to-left over the remaining feign duration. `kickAt`/`_auraSeen`
-- gate the immediate-kickstart grace (see COMBAT_LOG + Refresh below).
local fdInfo = {
  name = nil, spellId = nil, icon = nil,
  startTime = 0, endTime = 0, isChannel = true, fd = true,
  kickAt = 0, _auraSeen = false,
}

-- Dedicated table for the UNIT_SPELLCAST_START path: mounts, Hearthstone, First
-- Aid, professions — casts the combat log never logs, so CLEU (this module's
-- canonical trigger) has no event for them at all.
--
-- Separate from `info` for exactly the reason fdInfo is separate: identity IS the
-- guard. The STOP/INTERRUPTED handlers clear the bar only when
-- state.player.casting is *this table*, so they cannot truncate a CLEU-driven
-- cast (Multi-Shot, where UnitCastingInfo returns nil) or the Feign Death bar, no
-- matter what the client decides to fire. That turns "beware STOP clearing a real
-- cast early" from something to test into something that can't happen.
local unitInfo = {
  name = nil, spellId = nil, icon = nil,
  startTime = 0, endTime = 0, isChannel = false,
}

-- Opt-in: `== true`, not `~= false`. The CLEU path is the primary product and is
-- known-good; this second path is off until it has real mileage.
local function unitCastPathEnabled()
  local p = Nock.db and Nock.db.profile
  return p and p.castBarNonCombatCasts == true
end

-- Dedicated table for the Auto Shot wind-up, published to
-- state.player.autoShotCast rather than state.player.casting. It is drawn like a
-- cast but is NOT a lockout — it is the free queue window — and keeping the two
-- apart is what stops a consumer treating it as one. See Core/State.lua.
--
-- Published unconditionally: whether it is *shown* is each view's decision, made
-- via Nock.CastBarSource. A display setting must not decide what exists in state.
local autoInfo = {
  name = nil, spellId = nil, icon = nil,
  startTime = 0, endTime = 0, isChannel = false, auto = true,
}

local function feignName()
  if GetSpellInfo then
    local n = GetSpellInfo(Nock.Constants.SpellID.FEIGN_DEATH)
    if n then return n end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(Nock.Constants.SpellID.FEIGN_DEATH)
    if i and i.name then return i.name end
  end
  return "Feign Death"
end

-- `wantSpellId` (optional): the spell the caller is trying to raise a bar for.
-- UnitCastingInfo reports whatever is in flight RIGHT NOW, which is not
-- necessarily the spell whose CLEU SPELL_CAST_START just arrived — Auto Shot's
-- wind-up starts while a Steady Shot is still casting, and without this guard
-- the Auto Shot bar would silently inherit Steady's start/end times. Callers
-- with no id yet (the UNIT_SPELLCAST_START path) pass nil and check afterwards.
local function applyFromUnitCastingInfo(out, wantSpellId)
  local name, _, texture, startTime, endTime, _, _, _, spellId = UnitCastingInfo("player")
  if not name then return false end
  if wantSpellId and spellId ~= wantSpellId then return false end
  out.name = name
  out.spellId = spellId
  out.icon = texture
  out.startTime = startTime / 1000
  out.endTime = endTime / 1000
  out.isChannel = false
  return true
end

local function applyManual(out, spellId, spellName)
  local name, _, icon, castTime
  if GetSpellInfo then
    name, _, icon, castTime = GetSpellInfo(spellId)
  end

  local now = GetTime()
  local endTime
  if spellId == Nock.Constants.SpellID.AUTO_SHOT then
    -- Anchor to WHEN THE ARROW LEAVES, not to a modelled wind-up length.
    --
    -- The wind-up is not the flat 0.5s the spell data reports: measurement puts
    -- it at 0.5 scaled by the full ranged-attack-speed multiplier (0.37s at eWS
    -- 2.174, 0.23s at eWS 1.350 under Rapid Fire + Quick Shots). A formula could
    -- get there, but only with a hardcoded quiver term GetRangedHaste is blind
    -- to — so don't model it at all.
    --
    -- The swing timer already knows the answer: this wind-up ends at the next
    -- shot, and release-to-release equals UnitRangedDamage to within ~50ms
    -- (measured). So predict the release and let the bar run to it — the bar
    -- reaches 0.0 as the arrow leaves, which is the timing the player wants.
    local r = Nock.state.ranged
    if r.swingStart > 0 and r.swingDuration > 0 then
      endTime = r.swingStart + r.swingDuration
    end
    -- Cold start (first shot of a session, or a delayed shot whose predicted
    -- release has already passed): fall back to the measured wind-up.
    if not endTime or endTime <= now then
      endTime = now + (r.windup or Nock.Constants.AUTO_SHOT_CAST)
    end
  else
    if not castTime or castTime <= 0 then return false end
    -- No quiver term: the quiver speeds up the auto-shot SWING (already captured
    -- by UnitRangedDamage) and does nothing to a spell's cast time. Deliberately
    -- NOT Nock.RangedCastTime — that carries a correction measured from Steady
    -- Shot, which has no business being applied to a trap or a bandage. This is
    -- a display fallback for spells UnitCastingInfo won't report at all.
    local rangedHaste = GetRangedHaste and GetRangedHaste() or 0
    endTime = now + (castTime / 1000) / (1 + rangedHaste / 100)
  end
  if endTime <= now then return false end

  out.name = name or spellName or "?"
  out.spellId = spellId
  out.icon = icon
  out.startTime = now
  out.endTime = endTime
  out.isChannel = false
  return true
end

function CastBar:OnEnable()
  self.playerGUID = UnitGUID("player")
  self:RegisterEvent("PLAYER_LOGIN")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  self:RegisterEvent("UNIT_SPELLCAST_DELAYED")
  -- Registered unconditionally rather than toggled with the option: the handlers
  -- already no-op on the flag (and bail on unit ~= "player" first), so there's no
  -- cost worth a register/unregister dance on every profile switch.
  self:RegisterEvent("UNIT_SPELLCAST_START")
  self:RegisterEvent("UNIT_SPELLCAST_STOP")
  self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
  self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
  self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
  self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyBlizzardCastBarVisibility")
  self:ApplyBlizzardCastBarVisibility()
end

-- Hide/restore the default Blizzard player cast bar (shared setting "Hide
-- Blizzard's cast bar"). Hiding is the standard UnregisterAllEvents + Hide.
-- Restoring re-runs the frame's own OnLoad to get its events back; the
-- Anniversary client is modernized, so both the frame and its OnLoad are
-- resolved defensively (retail 10.0 renamed CastingBarFrame to
-- PlayerCastingBarFrame and moved OnLoad onto the mixin). If neither restore
-- path exists the events stay dropped until /reload — say so in chat rather
-- than leave the bar silently dead.
function CastBar:ApplyBlizzardCastBarVisibility()
  local frame = _G.PlayerCastingBarFrame or _G.CastingBarFrame
  if not frame then return end
  local p = Nock.db and Nock.db.profile
  if p and p.hideBlizzardCastBar == true then
    if not self._blizzBarHidden then
      self._blizzBarHidden = true
      frame:UnregisterAllEvents()
      frame:Hide()
    end
  elseif self._blizzBarHidden then
    -- Only restore what we hid this session; never poke the frame otherwise.
    self._blizzBarHidden = nil
    local restored = false
    if type(_G.CastingBarFrame_OnLoad) == "function" then
      -- Classic-era args, matching CastingBarFrame.xml's player bar OnLoad.
      restored = pcall(_G.CastingBarFrame_OnLoad, frame, "player", true, false)
    elseif type(frame.OnLoad) == "function" then
      restored = pcall(frame.OnLoad, frame)
    end
    -- No Show() here: the bar shows itself on the next cast. Forcing it now
    -- would flash an empty bar with nothing driving its fade-out.
    if not restored then
      self:Print("Couldn't re-enable the Blizzard cast bar live — /reload to restore it.")
    end
  end
end

function CastBar:PLAYER_LOGIN()
  self.playerGUID = UnitGUID("player")
end

function CastBar:PLAYER_ENTERING_WORLD()
  self.playerGUID = self.playerGUID or UnitGUID("player")
end

function CastBar:COMBAT_LOG_EVENT_UNFILTERED()
  if Nock.state.sim.active then return end   -- practice mode owns the cast
  local _, subEvent, _, sourceGUID, _, _, _, _, _, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
  if sourceGUID ~= self.playerGUID then return end

  if subEvent == "SPELL_CAST_START" then
    -- The wind-up goes to its own field, so it can neither clobber a real cast
    -- in flight nor be mistaken for one. No visibility check here — that is the
    -- views' business (Nock.CastBarSource).
    if spellId == Nock.Constants.SpellID.AUTO_SHOT then
      if applyManual(autoInfo, spellId, spellName) then
        autoInfo.auto = true
        Nock.state.player.autoShotCast = autoInfo
      end
      return
    end
    -- Prefer UnitCastingInfo's server-authoritative timing when available.
    if applyFromUnitCastingInfo(info, spellId) or applyManual(info, spellId, spellName) then
      Nock.state.player.casting = info
    end
  elseif subEvent == "SPELL_CAST_SUCCESS" or subEvent == "SPELL_CAST_FAILED" then
    if spellId == Nock.Constants.SpellID.AUTO_SHOT then
      Nock.state.player.autoShotCast = nil
      return
    end
    -- Feign Death is instant, so it never fires SPELL_CAST_START. On success,
    -- show the feign bar immediately (a provisional channel capped at the FD
    -- max duration); Refresh() then hands off to the real aura timing once the
    -- next UNIT_AURA scan populates state.player.feign.
    if subEvent == "SPELL_CAST_SUCCESS" and spellId == Nock.Constants.SpellID.FEIGN_DEATH then
      local now = GetTime()
      local icon
      if GetSpellInfo then local _, _, ic = GetSpellInfo(spellId); icon = ic end
      fdInfo.name      = feignName()
      fdInfo.spellId   = spellId
      fdInfo.icon      = icon or fdInfo.icon
      fdInfo.startTime = now
      fdInfo.endTime   = now + Nock.Constants.FEIGN_DEATH_DURATION
      fdInfo.isChannel = true
      fdInfo.fd        = true
      fdInfo.kickAt    = now
      fdInfo._auraSeen = false
      Nock.state.player.casting = fdInfo
      return
    end
    local c = Nock.state.player.casting
    if c and not c.isChannel and c.spellId == spellId then
      Nock.state.player.casting = nil
    end
  end
end

-- Secondary cast trigger for the casts CLEU never logs (mounts et al). Everything
-- combat-relevant still arrives via COMBAT_LOG_EVENT_UNFILTERED above; this only
-- fills the gap.
function CastBar:UNIT_SPELLCAST_START(event, unit)
  if Nock.state.sim.active then return end   -- practice mode owns the cast
  if unit ~= "player" then return end
  if not unitCastPathEnabled() then return end
  -- Never clobber a cast the CLEU or Feign Death path already owns. Combat casts
  -- are the primary product and their timing is already correct; for a spell where
  -- both paths fire (Steady Shot), whichever arrives first wins and the other is
  -- a no-op — so the rendered result is identical to today either way.
  if Nock.state.player.casting then return end
  if not applyFromUnitCastingInfo(unitInfo) then return end
  -- Auto Shot must never reach `casting` — that field means "locked out", and the
  -- wind-up is the opposite. UnitCastingInfo is not believed to return spell 75
  -- on this client at all, but enabling the non-combat path must not be able to
  -- smuggle it in. Checked against unitInfo.spellId rather than this event's
  -- args, whose signature varies by client version.
  if unitInfo.spellId == Nock.Constants.SpellID.AUTO_SHOT then return end
  Nock.state.player.casting = unitInfo
end

-- Identity guard: only ever clears a bar THIS path raised. Deliberately NOT gated
-- on unitCastPathEnabled() — if the option is switched off mid-cast, the bar this
-- path already put up must still come down.
function CastBar:UNIT_SPELLCAST_STOP(event, unit)
  if Nock.state.sim.active then return end   -- practice mode owns the cast
  if unit ~= "player" then return end
  if Nock.state.player.casting ~= unitInfo then return end
  Nock.state.player.casting = nil
end

-- Same handling: a mount cancelled by movement fires INTERRUPTED, not STOP.
-- (Assigned after the definition above, not before — it's a value, not a forward
-- declaration.)
CastBar.UNIT_SPELLCAST_INTERRUPTED = CastBar.UNIT_SPELLCAST_STOP

function CastBar:UNIT_SPELLCAST_DELAYED(event, unit)
  if Nock.state.sim.active then return end   -- practice mode owns the cast
  if unit ~= "player" then return end
  local c = Nock.state.player.casting
  if not c or c.isChannel then return end
  local name, _, _, startTime, endTime = UnitCastingInfo("player")
  if name then
    c.startTime = startTime / 1000
    c.endTime = endTime / 1000
  end
end

function CastBar:UNIT_SPELLCAST_CHANNEL_START(event, unit)
  if Nock.state.sim.active then return end   -- practice mode owns the cast
  if unit ~= "player" then return end
  local name, _, texture, startTime, endTime, _, _, spellId = UnitChannelInfo("player")
  if not name then return end
  info.name = name
  info.spellId = spellId
  info.icon = texture
  info.startTime = startTime / 1000
  info.endTime = endTime / 1000
  info.isChannel = true
  Nock.state.player.casting = info
end

function CastBar:UNIT_SPELLCAST_CHANNEL_UPDATE(event, unit)
  if Nock.state.sim.active then return end   -- practice mode owns the cast
  if unit ~= "player" then return end
  local c = Nock.state.player.casting
  if not c or not c.isChannel then return end
  local name, _, _, startTime, endTime = UnitChannelInfo("player")
  if name then
    c.startTime = startTime / 1000
    c.endTime = endTime / 1000
  end
end

function CastBar:UNIT_SPELLCAST_CHANNEL_STOP(event, unit)
  if Nock.state.sim.active then return end   -- practice mode owns the cast
  if unit ~= "player" then return end
  if Nock.state.player.casting and Nock.state.player.casting.isChannel then
    Nock.state.player.casting = nil
  end
end

function CastBar:Refresh(state)
  local now = GetTime()
  local c = state.player.casting

  -- Stale non-channel cast cleanup (real casts only).
  if c and not c.isChannel and now > c.endTime + 0.5 then
    state.player.casting = nil
    c = nil
  end

  -- Same safety net for the wind-up. Its normal teardown is the CLEU
  -- SPELL_CAST_SUCCESS for spell 75 (confirmed to fire on this client), but a
  -- cancelled shot — stepping out of range, losing the target — has no such
  -- event, and a stuck bar would sit there claiming a shot is imminent.
  local a = state.player.autoShotCast
  if a and now > a.endTime + 0.5 then
    state.player.autoShotCast = nil
  end

  -- A real (non-FD) cast always wins; never let the feign bar override it.
  if c and not c.fd then return end

  -- Practice mode owns state.player.casting while it is active; the stale-cast
  -- cleanup above still runs, but the feign projection below must never lodge
  -- fdInfo into the field the simulator is publishing into.
  if Nock.state.sim.active then return end

  -- Feign Death bar: project state.player.feign into the cast bar as a channel
  -- so it depletes right-to-left. The live aura's expirationTime drives the
  -- true remaining time; the bar clears the moment the buff drops (stand up).
  local feign = state.player.feign
  if feign then
    local dur = (feign.duration and feign.duration > 0) and feign.duration
                or Nock.Constants.FEIGN_DEATH_DURATION
    local exp = (feign.expirationTime and feign.expirationTime > 0) and feign.expirationTime
                or (now + dur)
    if not fdInfo.name then fdInfo.name = feignName() end
    fdInfo.spellId   = Nock.Constants.SpellID.FEIGN_DEATH
    fdInfo.icon      = feign.icon or fdInfo.icon
    fdInfo.startTime = exp - dur
    fdInfo.endTime   = exp
    fdInfo.isChannel = true
    fdInfo.fd        = true
    fdInfo._auraSeen = true
    state.player.casting = fdInfo
  elseif c and c.fd then
    -- No feign aura present. Clear once the aura has been seen and dropped
    -- (stood up), once the kickstart grace lapses with no aura ever appearing
    -- (e.g. the cast was resisted), or at the hard FD-duration cap.
    if fdInfo._auraSeen or now > fdInfo.kickAt + 0.6 or now > fdInfo.endTime then
      state.player.casting = nil
    end
  end
end
