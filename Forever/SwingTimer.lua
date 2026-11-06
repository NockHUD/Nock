-- Forever/SwingTimer.lua
-- Forever swing source: the native PLAYER_SWING event (plain numbers in combat)
-- drives state.ranged / state.melee; no combat log, no UnitRangedDamage polling.
-- Also the Auto Shot wind-up feed: the client's own cast edges for spell 75.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local SwingTimer = Nock:NewModule("SwingTimer", "AceEvent-3.0")

local SAMPLE_MAX = 200   -- one dummy session's worth (the one-session probe, 2026-10-18)

-- A Ranged PLAYER_SWING this soon after a melee hit is the client's own reset
-- of the ranged reload (Forever client bug: melee resets ranged; fix pending),
-- not a shot. Same grace as the weave engine's RESET_GRACE. Delete with the
-- rest of the reset handling once the client fix lands.
local RESET_GRACE = 0.1

-- Auto Shot wind-up (client build of 2026-10: a cast runs before the arrow
-- leaves, like TBC). What is kept is the RATIO wind-up/swingDuration, the same
-- haste-invariant number Modules/SwingTimer.lua measures on TBC, so the tick
-- derives seconds from it and a haste change is reflected at once. Two feeds,
-- one sample per shot: the client's own cast window from UnitCastingInfo at
-- UNIT_SPELLCAST_START(75) when it reports one (authoritative, and clean even
-- on a clipped shot, since the wind-up runs its full length from wherever it
-- starts), else START -> the ranged PLAYER_SWING, filtered like TBC (a late
-- shot inflates the read; a speed change mid-wind-up mixes two speeds). The
-- first accepted sample flips state.ranged.windupMeasured and the views stop
-- standing the queue window in for it (Nock.AutoShotWindup).
local WINDUP_MIN, WINDUP_MAX = 0.05, 1.0
local WINDUP_MAX_DELAY = 0.03   -- seconds of shot lateness that still counts as a clean cycle
local WINDUP_END_GRACE = 0.05   -- a STOP this close before the swing is the normal end, not a cancel
local WINDUP_RING      = 200    -- probe ring: one dummy session (2026-10-18)
-- Third feed (the one that actually has data on build 70425, probe
-- 2026-10-16: the client raises NO cast edge for Auto Shot, UnitCastingInfo
-- is nil, SUCCEEDED(75) lands in the frame of PLAYER_SWING): the shot cannot
-- wind up on the move. Dummy run of 2026-10-16 at eWS 2.232: stops made with
-- 0.3-0.5 s left on the bar pushed the shot 0.4-0.5 s late, and at each late
-- shot the player had stood still 0.70-1.10 s. So the shot fires at
--   max(due, stop + W)
-- and every LATE shot whose last movement edge was a stop reads W as
-- (shot - stop). Standing still, release-to-release stays one cycle: the
-- wind-up sits inside it (TBC model). Second dummy run (rtt 0.106): raw
-- 0.69 / 0.75 / 0.78 / 1.00 s, i.e. ~0.6-0.7 s of server time, so neither
-- the 0.5 s of the patch note nor haste-scaled down (0.5 / 1.25 would be
-- 0.40). The RAW read is what the bar needs: the key release reaches the
-- server half a round trip late and the shot comes back half a round trip
-- late, and the bar is anchored on the shot's arrival, so in bar time the
-- stop must come (W_server + rtt) = raw before the due mark. The reads
-- jitter (server tick) and the odd one is wild (a FAILED_QUIET on the auto
-- shot at the stop read 1.0), so the estimate is the upper median of the
-- last few, not an average. A cast edge after the stop could itself have
-- delayed the shot: such a shot is not read. Nor is the first shot of a
-- sequence: after a kill the player walks to the next mob, stops, and the
-- first shot there waits for the pull as well as the wind-up (reported
-- 2026-10-16: the mark went "ultrawide" after the second mob). A target
-- change or an auto-repeat start since the previous shot disqualifies it.
-- Fourth dump (2026-10-16): the client DOES raise UNIT_SPELLCAST_INTERRUPTED
-- for spell 75, with a cast GUID, when a move begins while the wind-up runs
-- (no START, no UnitCastingInfo, SUCCEEDED at the shot). So a move is the
-- probe of where the wind-up begins: one that interrupts found it running,
-- one that does not found it not yet begun. And a restart after an
-- interrupt costs more than a start after a continuous move (raw 0.84-1.07
-- against 0.69-0.78), so such reads are kept out of the median: the band
-- is about where to be still, not about the penalty for breaking it.
-- Fifth dump (2026-10-16): the interrupt lands ~0.21 s after the move (a
-- round trip and the server's turn), and with that lag allowed for the
-- moves at 0.37-0.52 s before the shot ALL interrupted while every move at
-- 0.64 s or earlier was free: the wind-up begins ~0.55-0.6 s before the
-- shot in bar time (the 0.5 s of the patch note plus latency). The stop
-- reads are another thing: 0.68-1.07 s raw, restart or not, as if the
-- server only picks the wind-up up on a tick after a stop. It is a retry
-- rhythm: the server retries a held shot every 0.5 s (UNIT_SPELLCAST_FAILED_QUIET
-- on 75, no SENT of its own), and the shot comes retry + wind-up later
-- (probe 2026-10-18: four tries 0.526 s apart, the shot 0.959 s after the
-- last). The band was the interrupt edge
-- as a running max until 2026-10-18; it crept with every read. Now:
-- THE BAND (2026-10-18 design, from the one-session probe on build 70450):
-- the wind-up SCALES with the reload (interrupt edge 0.63-0.67 s at a 2.232 s
-- reload, 0.44-0.60 s under Rapid Fire at 1.595 s; switch-on waits 0.66 /
-- 0.65 and 0.51 / 0.47 s), so the band is a fixed SHARE of the bar:
--   windupRatio = shareServer + rtt / reload
-- shareServer is the haste-invariant part (the server's wind-up over the
-- reload, 0.5 / weapon speed if the patch note holds), rtt the round trip
-- (quantised to RTT_STEP). The share comes from the SWITCH-ON read: !Auto
-- Shot pressed on an idle bar, standing still, the first shot one wind-up
-- later -- clean, unambiguous, and every pull in real play is one. It is
-- published as the upper median of the last ON_READS reads, per character
-- and per ranged weapon, and the published value only moves when the
-- median is more than ON_STEP away from it: a step on a new weapon or a real
-- change, never a creep (the earlier running max crept with every read and
-- the mark drifted, user 2026-10-18). Until a read exists the seed stands
-- in. The interrupt pairing and the stop reads stay as probe evidence and
-- the stop-by edge; neither moves the band any more.
local ON_READS   = 7
local ON_STEP    = 0.03
local ON_MIN, ON_MAX = 0.2, 1.0    -- seconds press -> shot that can be a wind-up
local SHARE_MAX  = 0.6
local SEED_SHARE_SERVER = 0.24     -- (0.655 - 0.110) / 2.232, the 2026-10-18 session
local RTT_STEP   = 0.01            -- the published rtt part moves in these steps (sub-pixel on the bar)
local STOP_LATE_MIN    = 0.05   -- a shot this much past its due time was pushed by something
local STOP_RAW_MAX     = 2.0    -- a stop further back than this before the shot was not what gated it
local STOP_READS       = 7      -- the stop-read window
local INTERRUPT_READS  = 10     -- the interrupt-edge window
local MOVE_PAIR_WINDOW = 0.4    -- an INTERRUPTED(75) this soon after a move start belongs to it
-- An interrupt is a read only when the wind-up it ended is the bar's own: a
-- fresh !Auto Shot press (new target, or auto re-armed since the last shot)
-- winds up from the press while the bar still runs the previous cycle, so a
-- nudge right after it paired with a large remaining time, and the band
-- being a max made that one read a permanent too-early mark (reported
-- 2026-10-18, mark at ~30% of the bar). The stop path had both guards; this
-- one now has them too, plus a ceiling: no wind-up runs a full second
-- (WINDUP_MAX) before the shot, and in ratio form 0.5 is a second at a
-- two-second cycle, past any ranged weapon outside a haste burst. Saved
-- reads from before the rule pass the same ceiling on restore.
local INTERRUPT_RATIO_MAX = 0.5

-- THE HELD SHOT and what feeds it (2026-11-01, taken over from
-- WeaponSwingTimer-SixxFix `forever` 1.60.2 and AppelSwingsForever 1.7.4).
-- The fill holds at the wind-up line while a shot cannot start and runs one
-- wind-up from the moment it can (Nock.AutoShotHoldStep); nothing predicted.
-- A press is told apart from the server's own retry by its SENT cast GUID:
-- a press that fails fails in the same frame, so one with no FAILED_QUIET
-- PRESS_OK after its SENT went through and starts the wind-up there.
local PRESS_OK    = 0.1
local PRESS_KEEP  = 5      -- own presses remembered this long
local PRESS_NEAR  = 0.05   -- a server failure this close to a press is the press's own
local AUTO_RETRY  = 0.5    -- the server retries a held shot this often
-- A jump in place fires no PLAYER_STARTED_MOVING: the air time is read from
-- JumpOrAscendStart and IsFalling, which is only asked after JUMP_GRACE (the
-- jump's first frame can still read the ground) and given up after AIR_MAX.
local JUMP_GRACE, AIR_MAX = 0.1, 3
-- Quick Shots (+30 % ranged speed, 12 s; Appel's measurement). Auras are
-- secret in combat, but UNIT_AURA still fires, and a player aura event in
-- the frame of a ranged swing is a proc or a refresh. The reload part of a
-- reload runs at the haste the shot reported; its wind-up at the haste when
-- the wind-up begins. So a fresh proc shortens this reload's wind-up (the
-- bar's end moves ~0.1 s sooner) and an expiry before a wind-up begins
-- lengthens it. A reported reload already QS_ALREADY faster than the last
-- carries the proc; an aura event within QS_END_SLOP of the expiry is the
-- expiry's own.
local QS_HASTE, QS_DURATION, QS_END_SLOP, QS_ALREADY = 1.3, 12, 0.15, 1.15
-- Parry haste on the player's own main hand: a parry with more than 60 % of
-- the swing left takes 40 % off; with 20-60 % left it leaves 20 %; under 20 %
-- nothing. Read from UNIT_COMBAT, which arrives after the parry itself (Appel
-- measured ~0.47 s on mobs): the 40 % cut is exact whenever it applies, the
-- 20 % floor lands that much late.
local PARRY_CUT, PARRY_FLOOR = 0.4, 0.2
local SLOT_MH, SLOT_OH, SLOT_RANGED = 16, 17, 18
local jumpHooked = false   -- hooksecurefunc cannot be undone: one hook per session

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
  -- Auto Shot wind-up edges (spell 75 only; everything else is dropped on entry).
  self._windups, self._stopRatios, self._interruptRatios = {}, {}, {}
  self._onReads, self._onKey, self._switchOn, self._shareServer, self._onMedian = {}, nil, nil, nil, nil
  self._onKey = SwingTimer.WeaponKey()
  self:RestoreWindupReads()
  self:ApplyWindupEstimate()
  self._windupStart, self._windupSd, self._windupEndAt, self._windupFromCast = nil, nil, nil, false
  self:RegisterEvent("UNIT_SPELLCAST_START", "OnAutoShotEdge")
  self:RegisterEvent("UNIT_SPELLCAST_STOP", "OnAutoShotEdge")
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnAutoShotEdge")
  self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnAutoShotEdge")
  self:RegisterEvent("UNIT_SPELLCAST_FAILED", "OnAutoShotEdge")
  -- The held shot's feeds: own presses (SENT), the server's retries and
  -- failed presses (FAILED_QUIET), jumps.
  self._hold, self._presses, self._pending = {}, {}, {}
  self:RegisterEvent("UNIT_SPELLCAST_SENT", "OnAutoShotSent")
  self:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET", "OnAutoShotFailedQuiet")
  if not jumpHooked and type(_G.JumpOrAscendStart) == "function" and _G.hooksecurefunc then
    jumpHooked = true
    hooksecurefunc("JumpOrAscendStart", function() SwingTimer:OnJump() end)
  end
  -- Player-only unit events (parry haste, Quick Shots) on a frame of their
  -- own: AceEvent would hand this module every unit's UNIT_AURA.
  if _G.CreateFrame and not self._unitFrame then
    local f = CreateFrame("Frame")
    f:RegisterUnitEvent("UNIT_COMBAT", "player")
    f:RegisterUnitEvent("UNIT_AURA", "player")
    f:SetScript("OnEvent", function(_, ev, ...)
      if ev == "UNIT_COMBAT" then SwingTimer:OnPlayerCombat(...) else SwingTimer:OnPlayerAura() end
    end)
    self._unitFrame = f
  end
  -- Each weapon's printed speed, for the swap estimate (read before the swap).
  self._heldSpeed = {}
  self:RefreshHeldSpeeds()
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
  self._targetChangedAt = GetTime()
  self._switchOn = nil       -- the first shot now goes to another target: no switch-on read
  self:RefreshTargetRange()
end

function SwingTimer:PLAYER_SWING_RANGE_UPDATE(event, kind, isInRange, checksRange)
  self:PushRangeRow(kind, isInRange, checksRange)
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
  local now = GetTime()
  self._moving, self._movedAt = true, now
  local c = Nock.state.context
  c.moving, c.movingSince = true, now
  if self._switchOn then self._switchOn.moved = true end
  self:FeignGetUp(now)
  -- A move inside a running swing is a probe of the wind-up's start (see
  -- the INTERRUPTED note above); the ring pairs it with any interrupt.
  local r = Nock.state.ranged
  if r.swingStart > 0 and r.swingRemaining > 0 and self._windups then
    local W = self._windups
    -- The reload the move was made in: the probe groups moves by it to
    -- tell a fixed-seconds wind-up from one that scales with haste.
    W[#W + 1] = { t = now, ev = "MOVE", swingRemaining = r.swingRemaining, swingDuration = r.swingDuration }
    if #W > WINDUP_RING then table.remove(W, 1) end
    self._lastMoveAt, self._lastMoveRem = now, r.swingRemaining
  else
    self._lastMoveAt, self._lastMoveRem = nil, nil
  end
end

function SwingTimer:PLAYER_STOPPED_MOVING()
  local now = GetTime()
  self._moving, self._stoppedAt = false, now
  local c = Nock.state.context
  c.moving, c.stoppedAt = false, now
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

function SwingTimer:PLAYER_SWING(event, duration, kind, ...)
  local now = GetTime()
  local S = self._samples
  local stillFor = (not self._moving and self._stoppedAt) and (now - self._stoppedAt) or nil
  -- ...and, for a shot made on the move, how long the move had been going:
  -- whether the wind-up tolerates movement once begun is read from these.
  local movingFor = (self._moving and self._movedAt) and (now - self._movedAt) or nil
  -- Any payload beyond (duration, kind) is kept for the probe: a changed
  -- client may hand the wind-up over here.
  local extra = select("#", ...) > 0 and { ... } or nil
  S[#S + 1] = { t = now, swingType = kind, duration = duration, moving = self._moving == true, stillFor = stillFor,
                movingFor = movingFor, extra = extra }
  if #S > SAMPLE_MAX then table.remove(S, 1) end
  if type(duration) ~= "number" or duration <= 0 then return end
  if kind == swingType("Ranged") then
    local r = Nock.state.ranged
    local isReset = self._lastHitAt ~= nil and (now - self._lastHitAt) <= RESET_GRACE
    if not isReset then
      self:UpdateWindupFromSwitchOn(now, duration)   -- the band's feed; reads the state BEFORE this shot moves it
      self:UpdateWindupFromStop(now, duration)
      self:UpdateAutoDelay(now)
      self:UpdateWindupAtRelease(now, duration)
      self:CheckShotModels(now)
    end
    self._switchOn = nil
    self._feignAt = nil
    local prevRaw = self._rawDur
    r.swingStart = now
    r.swingDuration = duration
    self._rawDur, self._prevRawDur, self._qsMul, self._shotAt = duration, prevRaw, 1, now
    self._shotWasReset = isReset
    -- A Quick Shots expiry before this reload's wind-up begins: the reload
    -- was reported hasted, the wind-up runs without it.
    local qe = self._qsEndAt
    if qe and qe > now and qe < now + duration - (r.windup or 0) then self._qsMul = 1 / QS_HASTE end
    -- A melee reset of the reload is not a shot: no proc on its frame.
    if self._auraAt == now and not isReset then self:QuickShotsOnShot(now, prevRaw) end
    self:ApplyQuickShots()   -- the bar's end and the band (rtt / reload follows the reload)
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

-- A cast-edge or release read (feeds never seen on this client): the row is
-- tagged when the ratio is plausible, and that is all -- the band is the
-- switch-on share (see THE BAND above).
local function acceptWindupRatio(ratio)
  return ratio > 0.01 and ratio < 1
end

local function pushWindup(self, sample)
  local W = self._windups
  W[#W + 1] = sample
  if #W > WINDUP_RING then table.remove(W, 1) end
end

-- A range edge, for the probe: with the game's auto-switch option on, these
-- are what the client swaps the attack on.
function SwingTimer:PushRangeRow(kind, isInRange, checksRange)
  if not self._windups then return end
  pushWindup(self, { t = GetTime(), ev = "RANGE", kind = kind, inRange = isInRange, checks = checksRange,
                     swingRemaining = Nock.state.ranged.swingRemaining })
end

-- The client's cast edges for Auto Shot (spell 75). START opens a wind-up
-- and, when UnitCastingInfo reports the cast, samples it on the spot. STOP
-- and INTERRUPTED stamp the end (a STOP at the release is normal; one well
-- before the swing is a cancel and the release read is dropped). SUCCEEDED
-- is recorded for the probe; FAILED too, and it never ends anything: a
-- refused re-press of !Auto Shot inside the wind-up logs a FAILED while the
-- real wind-up keeps running (the TBC rule).
function SwingTimer:OnAutoShotEdge(event, unit, castGUID, spellID)
  if unit ~= "player" then return end
  local P = Nock.Flavor.Plain
  if P(spellID) ~= Nock.Spells.AUTO_SHOT then
    -- Another spell's START or release: a shot after it may have been pushed
    -- by the cast rather than by a stop (UpdateWindupFromStop).
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED" then
      self._lastCastAt = GetTime()
      if self._switchOn then self._switchOn.cast = true end
      -- Feign Death: getting up (a move or a jump) restarts the reload; a
      -- cast after it gets up without one (both reference addons agree).
      if event == "UNIT_SPELLCAST_SUCCEEDED" and P(spellID) == Nock.Spells.FEIGN_DEATH then
        self._feignAt = self._lastCastAt
      else
        self._feignAt = nil
      end
    end
    return
  end
  -- SUCCEEDED(75) is the shot (PLAYER_SWING has it) and FAILED(75) is the
  -- dead-zone spam: both stay out of the ring, which they flooded.
  if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED" then return end
  local now = GetTime()
  local sample = { t = now, ev = event, swingRemaining = Nock.state.ranged.swingRemaining }
  if event == "UNIT_SPELLCAST_START" then
    local r = Nock.state.ranged
    self._windupStart, self._windupSd, self._windupEndAt, self._windupFromCast = now, r.swingDuration, nil, false
    if _G.UnitCastingInfo then
      local _, _, _, startMs, endMs, _, _, _, id = UnitCastingInfo("player")
      startMs, endMs = P(startMs), P(endMs)
      if type(startMs) == "number" and type(endMs) == "number" and endMs > startMs then
        sample.castStart, sample.castEnd, sample.castId = startMs / 1000, endMs / 1000, P(id)
        local w = (endMs - startMs) / 1000
        if w >= WINDUP_MIN and w <= WINDUP_MAX and r.swingDuration > 0 then
          sample.sampled = acceptWindupRatio(w / r.swingDuration) and "cast" or nil
          self._windupFromCast = sample.sampled ~= nil
        end
      end
    end
  elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
    if self._windupStart then self._windupEndAt = now end
    if event == "UNIT_SPELLCAST_INTERRUPTED" then
      -- The client sends it three times per interrupt: one row, one stamp.
      if self._lastInterruptAt == now then return end
      self._lastInterruptAt = now
      -- Paired with the move that caused it: the wind-up was running when
      -- that move began, so its remaining time is a point inside the band.
      local r = Nock.state.ranged
      if self._lastMoveAt and now - self._lastMoveAt <= MOVE_PAIR_WINDOW and self._lastMoveRem and r.swingDuration > 0 then
        local ratio = self._lastMoveRem / r.swingDuration
        sample.pairedMoveRem, sample.lag, sample.swingDuration = self._lastMoveRem, now - self._lastMoveAt, r.swingDuration
        -- Not the bar's wind-up: a press since the last shot started its own.
        local prevShot = r.swingStart
        local fresh = (self._targetChangedAt and self._targetChangedAt >= prevShot)
                   or (self._autoStartAt and self._autoStartAt >= prevShot)
        if fresh then sample.freshPress = true end
        if not fresh and self._lastMoveRem <= WINDUP_MAX
           and ratio > 0.01 and ratio < INTERRUPT_RATIO_MAX then
          local R = self._interruptRatios
          R[#R + 1] = ratio
          if #R > INTERRUPT_READS then table.remove(R, 1) end
          sample.sampled = "interrupt"      -- probe evidence; the band is the switch-on share
        end
        self._lastMoveAt, self._lastMoveRem = nil, nil
      end
    end
  end
  pushWindup(self, sample)
end

-- The release side of the wind-up: the ranged PLAYER_SWING. `duration` is the
-- cycle the client reports with this shot; a change against the one the
-- wind-up began under means two speeds were mixed and the read is dropped.
function SwingTimer:UpdateWindupAtRelease(now, duration)
  local start = self._windupStart
  if not start then return end
  local startSd, endAt, fromCast = self._windupSd, self._windupEndAt, self._windupFromCast
  self._windupStart, self._windupSd, self._windupEndAt, self._windupFromCast = nil, nil, nil, false
  local measured = now - start
  local sample = { t = now, ev = "RELEASE", measured = measured, startSd = startSd, duration = duration,
                   autoDelay = Nock.state.ranged.autoDelay, fromCast = fromCast }
  pushWindup(self, sample)
  if fromCast then return end                                      -- one sample per shot
  if endAt and now - endAt > WINDUP_END_GRACE then return end      -- cancelled wind-up
  if measured < WINDUP_MIN or measured > WINDUP_MAX then return end
  if (Nock.state.ranged.autoDelay or 0) > WINDUP_MAX_DELAY then return end
  if startSd and duration and math.abs(startSd - duration) > 0.005 then return end
  if not duration or duration <= 0 then return end
  sample.sampled = acceptWindupRatio(measured / duration) and "release" or nil
end

-- The stop-gated read: the player stopped moving at or after the shot was
-- due, and this shot is the first since. Its distance from the stop, less the
-- round trip, is the wind-up. A stop made while the bar was still running
-- did not gate the shot and says nothing. Not sampled when a cast edge is
-- already feeding the wind-up (one sample per shot).
function SwingTimer:UpdateWindupFromStop(now, duration)
  if self._windupStart then return end
  local r = Nock.state.ranged
  local stoppedAt = (not self._moving) and self._stoppedAt or nil
  if not stoppedAt or r.swingStart <= 0 or r.swingDuration <= 0 then return end
  local prevShot = r.swingStart                                          -- the previous ranged PLAYER_SWING
  if stoppedAt < prevShot then return end                                -- an old stop, already spent
  if self._targetChangedAt and self._targetChangedAt >= prevShot then return end   -- new target: first shot waits for the pull too
  if self._autoStartAt and self._autoStartAt >= prevShot then return end          -- auto re-armed: same
  local due = r.swingStart + r.swingDuration
  local late = now - due
  if late < STOP_LATE_MIN then return end                                -- on time: the stop did not gate it
  if self._lastCastAt and self._lastCastAt >= stoppedAt then return end  -- a cast after the stop may have pushed it
  local lat = ((Nock.state.network and Nock.state.network.latencyMs) or 0) / 1000
  local raw = now - stoppedAt
  if raw > STOP_RAW_MAX then return end                                  -- a stop that old did not gate this shot
  local restart = self._lastInterruptAt ~= nil and self._lastInterruptAt >= prevShot
  local sample = { t = now, ev = "STOP->SHOT", stoppedAt = stoppedAt, due = due, late = late, raw = raw, latency = lat,
                   lessRtt = raw - lat, measured = raw, duration = duration, restart = restart }
  pushWindup(self, sample)
  if raw < WINDUP_MIN or raw > WINDUP_MAX then return end
  if type(duration) ~= "number" or duration <= 0 then return end
  if math.abs(r.swingDuration - duration) > 0.005 then return end   -- speed changed across the wait
  local ratio = raw / duration
  if ratio <= 0.01 or ratio >= 1 then return end
  local R = self._stopRatios
  R[#R + 1] = ratio
  if #R > STOP_READS then table.remove(R, 1) end
  sample.sampled = "stop"
  self:ApplyWindupEstimate()   -- the stop-by edge; the band itself does not move
end

-- The switch-on read (the band's feed): !Auto Shot pressed on an idle bar,
-- the player still and casting nothing until the shot, the target in range
-- at the press. press -> shot is the wind-up in bar time; less the round
-- trip, over the reload, it is the server's share.
function SwingTimer:UpdateWindupFromSwitchOn(now, duration)
  local so = self._switchOn
  self._switchOn = nil
  if not so then return end
  local read = now - so.t
  local sample = { t = now, ev = "ON->SHOT", read = read, duration = duration, rtt = so.rtt, idle = so.idle,
                   moving = so.moving, moved = so.moved, cast = so.cast, inRange = so.inRange }
  pushWindup(self, sample)
  if not so.idle or so.moving or so.moved or so.cast or so.inRange == false then return end
  if read < ON_MIN or read > ON_MAX then return end
  if type(duration) ~= "number" or duration <= 0 then return end
  local share = (read - (so.rtt or 0)) / duration
  if share <= 0.02 or share >= SHARE_MAX then return end
  local R = self._onReads
  R[#R + 1] = share
  if #R > ON_READS then table.remove(R, 1) end
  sample.sampled, sample.share = "switch-on", share
  self._onMedian = nil
  self:SaveWindupReads()
end

-- The equipped ranged weapon's item id as a string, or "any": the share is
-- per weapon (0.5 / its speed), so a swap starts its own reads.
function SwingTimer.WeaponKey()
  local id = _G.GetInventoryItemID and _G.GetInventoryItemID("player", 18)
  id = Nock.Flavor.Plain(id)
  return (type(id) == "number" and id > 0) and tostring(id) or "any"
end

local function rttNow(quantised)
  local n = Nock.state.network
  local rtt = ((n and n.latencyMs) or 0) / 1000
  if quantised then return math.floor(rtt / RTT_STEP + 0.5) * RTT_STEP end
  return rtt
end

-- The published band (see THE BAND above). `duration` is the reload the
-- rtt part is spread over (the shot's, else the state's). The median is
-- cached until a read changes the ring; the published server share moves
-- only by a step of more than ON_STEP.
function SwingTimer:ApplyWindupEstimate(duration)
  local r = Nock.state.ranged
  local R, S = self._onReads or {}, self._stopRatios or {}
  if #R > 0 and self._onMedian == nil then self._onMedian = SwingTimer.UpperMedian(R) end
  local med, pub = self._onMedian, self._shareServer
  if med and (not pub or math.abs(med - pub) > ON_STEP) then pub = med end
  if not pub then pub = SEED_SHARE_SERVER end
  self._shareServer = pub
  local d = tonumber(duration) or r.swingDuration or 0
  local ratio = pub
  -- The server's part runs on the reload the shot reported (raw), at the
  -- haste the wind-up begins under (Quick Shots, see ApplyQuickShots).
  local raw, mul = self._rawDur or d, self._qsMul or 1
  if d > 0 and raw > 0 and mul > 0 then ratio = (pub * raw / mul + rttNow(true)) / d end
  if ratio > 0.9 then ratio = 0.9 end
  r.windupRatio, r.windupMeasured = ratio, true
  r.windupSource = (#R > 0) and "switch-on" or "seed"
  r.stopByRatio = #S > 0 and SwingTimer.UpperMedian(S) or nil
end

-- Quick Shots on a shot's frame (UNIT_AURA and PLAYER_SWING, either order).
-- A refresh while the buff is up, or the expiry's own aura event, starts
-- nothing; a reload reported already QS_ALREADY faster than the last one
-- carries the proc in its own number.
function SwingTimer:QuickShotsOnShot(now, prevRaw)
  local qe = self._qsEndAt
  if qe and math.abs(now - qe) <= QS_END_SLOP then return end
  local up = qe and now < qe
  self._qsEndAt = now + QS_DURATION
  if up then return end
  local raw = self._rawDur
  if prevRaw and raw and raw < prevRaw / QS_ALREADY then return end
  self._qsMul = QS_HASTE
  pushWindup(self, { t = now, ev = "QS_PROC", swingRemaining = Nock.state.ranged.swingRemaining })
end

-- This reload's bar end from the reported reload and the Quick Shots shift
-- of its wind-up part (the server's share; the round trip does not scale).
function SwingTimer:ApplyQuickShots()
  local r = Nock.state.ranged
  local raw, mul = self._rawDur, self._qsMul or 1
  if raw and raw > 0 and mul > 0 then
    local pure = (self._shareServer or SEED_SHARE_SERVER) * raw
    r.swingDuration = raw + pure / mul - pure
  end
  self:ApplyWindupEstimate(r.swingDuration)
end

function SwingTimer:OnPlayerAura()
  local now = GetTime()
  self._auraAt = now
  if self._shotAt == now and not self._shotWasReset and (self._qsMul or 1) == 1 then
    self:QuickShotsOnShot(now, self._prevRawDur)
    if self._qsMul ~= 1 then self:ApplyQuickShots() end
  end
end

-- Parry haste (see PARRY_CUT above). The cut moves the swing's start, so the
-- views read it as the same swing re-anchored, not as a new one.
function SwingTimer:OnPlayerCombat(unit, action)
  if Nock.Flavor.Plain(action) ~= "PARRY" then return end
  local m = Nock.state.melee
  local D = m.swingDuration
  if m.swingStart <= 0 or not D or D <= 0 then return end
  local now = GetTime()
  local rem = m.swingStart + D - now
  local cut
  if rem > (1 - PARRY_CUT) * D then cut = PARRY_CUT * D
  elseif rem > PARRY_FLOOR * D then cut = rem - PARRY_FLOOR * D end
  if not cut then return end
  m.swingStart = m.swingStart - cut
  m.swingRemaining = math.max(0, m.swingStart + D - now)
  pushWindup(self, { t = now, ev = "PARRY", swingRemaining = rem, cut = cut, swingDuration = D })
end

-- Getting up from Feign Death (a move or a jump after a feign, no cast in
-- between) restarts the ranged reload at its last length. Whether the client
-- raises a PLAYER_SWING of its own for it is not known yet: the FD_GETUP row
-- and the next shot's FD_CHECK row in the probe answer that.
function SwingTimer:FeignGetUp(now)
  if not self._feignAt then return end
  self._feignAt = nil
  local r = Nock.state.ranged
  if r.swingStart <= 0 or r.swingDuration <= 0 then return end
  r.swingStart = now
  r.swingRemaining = r.swingDuration
  self._fdRestartAt = now
  pushWindup(self, { t = now, ev = "FD_GETUP", swingRemaining = r.swingDuration, swingDuration = r.swingDuration })
end

function SwingTimer:OnJump()
  local now, c = GetTime(), Nock.state.context
  c.airborne, c.airborneAt = true, now
  if self._switchOn then self._switchOn.moved = true end
  self:FeignGetUp(now)
  local r = Nock.state.ranged
  if r.swingStart > 0 and self._windups then
    pushWindup(self, { t = now, ev = "JUMP", swingRemaining = r.swingRemaining, swingDuration = r.swingDuration })
  end
end

-- A !Auto Shot press: remembered by cast GUID (a later FAILED_QUIET with it
-- is the press's own failure), and pending while auto is already on, until
-- PRESS_OK says whether it went through.
function SwingTimer:OnAutoShotSent(event, unit, target, castGUID, spellID)
  if unit ~= "player" then return end
  local P = Nock.Flavor.Plain
  if P(spellID) ~= Nock.Spells.AUTO_SHOT then return end
  local now = GetTime()
  self._lastPressAt = now
  local guid = P(castGUID)
  if type(guid) ~= "string" then return end
  for id, at in pairs(self._presses) do
    if now - at > PRESS_KEEP then self._presses[id] = nil end
  end
  self._presses[guid] = now
  if Nock.state.ranged.repeating then self._pending[guid] = now end
end

-- A FAILED_QUIET on Auto Shot: a press's own failure (its GUID was SENT), or
-- the server's retry of a held shot. Sent twice: read once. One in the frame
-- of the switch-off is the switch-off (STOP_AUTOREPEAT_SPELL undoes it when it
-- comes second); one at a press is the press's; a retry that still lands
-- before the reload's end changes nothing. A counted retry predicts the shot
-- AUTO_RETRY + wind-up later -- published for the probe (RETRY_CHECK compares
-- it with the shot), drawn by nothing until the logs confirm the phase.
function SwingTimer:OnAutoShotFailedQuiet(event, unit, castGUID, spellID)
  if unit ~= "player" then return end
  local P = Nock.Flavor.Plain
  if P(spellID) ~= Nock.Spells.AUTO_SHOT then return end
  local now = GetTime()
  local guid = P(castGUID)
  if type(guid) ~= "string" then guid = nil end
  if now == self._fqAt and guid == self._fqGuid then return end
  self._fqAt, self._fqGuid = now, guid
  local r = Nock.state.ranged
  if guid and self._presses[guid] then
    self._pending[guid] = nil
    pushWindup(self, { t = now, ev = "PRESS_FAILED", swingRemaining = r.swingRemaining })
    return
  end
  if self._autoOffAt == now or not r.repeating or r.swingStart <= 0 then return end
  if self._lastPressAt and math.abs(now - self._lastPressAt) <= PRESS_NEAR then return end
  local shot = now + AUTO_RETRY + (r.windup or 0)
  if shot <= r.swingStart + r.swingDuration then return end
  r.retryAt, r.retryShotAt = now, shot
  pushWindup(self, { t = now, ev = "RETRY", swingRemaining = r.swingRemaining, predicted = shot })
end

-- At a ranged shot: how the retry model and a Feign Death restart did.
function SwingTimer:CheckShotModels(now)
  local r = Nock.state.ranged
  if r.retryShotAt then
    pushWindup(self, { t = now, ev = "RETRY_CHECK", err = now - r.retryShotAt, retryAt = r.retryAt })
    r.retryAt, r.retryShotAt = nil, nil
  end
  if self._fdRestartAt then
    pushWindup(self, { t = now, ev = "FD_CHECK", gap = now - self._fdRestartAt, swingDuration = r.swingDuration })
    self._fdRestartAt = nil
  end
end

-- Whether a shot can start its wind-up now, from what the client says
-- (WeaponSwingTimer's CanBeginAutoVisual): auto on, standing on the ground,
-- no cast in flight, the target in range, there and alive. Unknown is no
-- evidence against.
function SwingTimer:HoldReady()
  local st = Nock.state
  local r, c = st.ranged, st.context
  if not r.repeating or c.moving or c.airborne then return false end
  if r.targetInRange == false or st.player.casting then return false end
  local P = Nock.Flavor.Plain
  if _G.UnitExists and P(UnitExists("target")) == false then return false end
  if _G.UnitIsDeadOrGhost and P(UnitIsDeadOrGhost("target")) == true then return false end
  return true
end

-- The tick's part (Core calls it after the wind-up seconds are derived):
-- landing after a jump, presses that went through, the held fill.
function SwingTimer:TickHold(now)
  local st = Nock.state
  local r, c = st.ranged, st.context
  if c.airborne and c.airborneAt and now - c.airborneAt >= JUMP_GRACE then
    local f = nil
    if _G.IsFalling then f = Nock.Flavor.Plain(IsFalling()) end
    if f == false or (f ~= true and now - c.airborneAt > AIR_MAX) then
      c.airborne = false
      if not self._moving then c.stoppedAt, self._stoppedAt = now, now end
    end
  end
  if next(self._pending) then
    local through
    for guid, at in pairs(self._pending) do
      if now - at >= PRESS_OK then
        self._pending[guid] = nil
        if not through or at > through then through = at end
      end
    end
    if through and r.repeating and not c.moving and not c.airborne then
      r.pressThroughAt = through
      pushWindup(self, { t = now, ev = "PRESS_THROUGH", pressAt = through, swingRemaining = r.swingRemaining })
    end
  end
  -- A press that went through is the client's own word that the shot
  -- started: for one wind-up after it, it outweighs a readiness read that
  -- has not caught up (a range edge not reported yet). Never on the move.
  local ready = self:HoldReady()
  local pa = r.pressThroughAt
  if not ready and pa and not (c.moving or c.airborne) and now - pa <= (r.windup or 0) + PRESS_OK then ready = true end
  local rem, held, eta = Nock.AutoShotHoldStep(self._hold, r.swingStart, r.swingDuration, r.windup, now,
                                               ready, pa, rttNow() / 2)
  if r.swingStart <= 0 then rem = r.swingRemaining end
  r.displayRemaining, r.held, r.shotEta = rem, held, eta
end

-- A weapon's printed speed from its tooltip (the right-hand "Speed N.NN"),
-- or nil. C_TooltipInfo: the hidden GameTooltip scan is refused here.
function SwingTimer.ItemSpeed(slot)
  local TI = _G.C_TooltipInfo
  if not (TI and TI.GetInventoryItem) then return nil end
  local okCall, data = pcall(TI.GetInventoryItem, "player", slot)
  if not okCall or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  for _, line in ipairs(data.lines) do
    local txt = Nock.Flavor.Plain(line.rightText)
    local num = type(txt) == "string" and txt:match("(%d+[%.,]%d+)") or nil
    local sp = num and tonumber((num:gsub(",", ".")))
    if sp and sp > 0 then return sp end
  end
  return nil
end

function SwingTimer:RefreshHeldSpeeds()
  local H = self._heldSpeed
  H[SLOT_MH], H[SLOT_OH], H[SLOT_RANGED] =
    SwingTimer.ItemSpeed(SLOT_MH), SwingTimer.ItemSpeed(SLOT_OH), SwingTimer.ItemSpeed(SLOT_RANGED)
end

-- A swap restarts the swapped weapon's swing (a melee hand restarts both
-- melee bars) at the new weapon's printed speed times the haste the old one
-- ran at. With no estimate the bar goes idle until its next PLAYER_SWING.
-- Only a live bar restarts (running, or held in combat).
local function restart(dur, now, est)
  if est and est > 0 then return now, est end
  return 0, dur
end

function SwingTimer:OnWeaponSwap(slot, now)
  local H = self._heldSpeed
  local old, new = H[slot], SwingTimer.ItemSpeed(slot)
  H[slot] = new
  local fighting = Nock.state.player.inCombat
  local function est(dur) return (old and old > 0 and new and dur and dur > 0) and new * dur / old or nil end
  if slot == SLOT_RANGED then
    local r = Nock.state.ranged
    if r.swingStart <= 0 or not (now < r.swingStart + r.swingDuration or fighting) then return end
    r.swingStart, r.swingDuration = restart(r.swingDuration, now, est(self._rawDur or r.swingDuration))
    r.swingRemaining = r.swingStart > 0 and r.swingDuration or 0
    self._rawDur, self._qsMul = r.swingDuration, 1
    self:ApplyWindupEstimate(r.swingDuration)
    pushWindup(self, { t = now, ev = "SWAP", swingDuration = r.swingDuration, idle = r.swingStart <= 0 })
  elseif slot == SLOT_MH or slot == SLOT_OH then
    local m = Nock.state.melee
    if m.swingStart > 0 and (now < m.swingStart + m.swingDuration or fighting) then
      local e = slot == SLOT_MH and est(m.swingDuration) or m.swingDuration
      m.swingStart, m.swingDuration = restart(m.swingDuration, now, e)
      m.swingRemaining = m.swingStart > 0 and m.swingDuration or 0
    end
    if m.dualWield and m.offStart > 0 and (now < m.offStart + m.offDuration or fighting) then
      local e = slot == SLOT_OH and est(m.offDuration) or m.offDuration
      m.offStart, m.offDuration = restart(m.offDuration, now, e)
      m.offRemaining = m.offStart > 0 and m.offDuration or 0
    end
  end
end

-- The published server share and the reads behind it (for the probe).
function SwingTimer:WindupShare()
  return self._shareServer, self._onReads or {}, self._onKey
end

-- The switch-on reads outlive the session, per character and per ranged
-- weapon (db.char.foreverWindupShares[weaponKey]), so a login starts on the
-- weapon's own share. Stop and interrupt reads are session evidence only.
function SwingTimer:SaveWindupReads()
  local c = Nock.db and Nock.db.char
  if not c then return end
  local list = {}
  for i = 1, #self._onReads do list[i] = self._onReads[i] end
  if type(c.foreverWindupShares) ~= "table" then c.foreverWindupShares = {} end
  c.foreverWindupShares[self._onKey or "any"] = list
end

-- `/nock probe windup reset`: forget every read (this session's and the
-- saved ones, every weapon) and go back to the seed share.
function SwingTimer:ResetWindupReads()
  self._stopRatios, self._interruptRatios, self._onReads = {}, {}, {}
  self._shareServer, self._onMedian = nil, nil
  local c = Nock.db and Nock.db.char
  if c then c.foreverWindupShares, c.foreverWindupReads = {}, nil end
  self:ApplyWindupEstimate()
end

local function cleanRatios(list, max, ceiling)
  local R = {}
  if type(list) ~= "table" then return R end
  for i = 1, #list do
    local v = list[i]
    if type(v) == "number" and v > 0.01 and v < (ceiling or 1) then R[#R + 1] = v end
  end
  while #R > max do table.remove(R, 1) end
  return R
end

function SwingTimer:RestoreWindupReads()
  local c = Nock.db and Nock.db.char
  if not c then return end
  -- The pre-2026-10-18 shape (stop and interrupt ratios) fed a band that
  -- crept; it is dropped, not converted.
  if c.foreverWindupReads ~= nil then c.foreverWindupReads = nil end
  local saved = c.foreverWindupShares
  local list = type(saved) == "table" and saved[self._onKey or "any"] or nil
  self._onReads = cleanRatios(list, ON_READS, SHARE_MAX)
  self._onMedian = nil
  self:ApplyWindupEstimate()
end

-- The upper median of a list of numbers (the higher middle for an even
-- count: a slightly longer wind-up is the safe side for a stop-by mark).
function SwingTimer.UpperMedian(list)
  local s = {}
  for i = 1, #list do s[i] = list[i] end
  table.sort(s)
  return s[math.floor(#s / 2) + 1]
end

-- Last WINDUP_RING wind-up edges, oldest first (for /nock probe windup).
function SwingTimer:WindupSamples()
  local out = {}
  local W = self._windups or {}
  for i = 1, #W do out[i] = W[i] end
  return out
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

function SwingTimer:PLAYER_EQUIPMENT_CHANGED(event, slot)
  self:RefreshDualWield()
  slot = Nock.Flavor.Plain(slot)
  if slot == SLOT_RANGED or slot == SLOT_MH or slot == SLOT_OH then self:OnWeaponSwap(slot, GetTime()) end
  local k = SwingTimer.WeaponKey()
  if k ~= self._onKey then
    self._onKey, self._shareServer, self._onMedian = k, nil, nil
    self._onReads = {}
    self:RestoreWindupReads()
  end
end

-- Both toggles are probe rows (the switch-on question: how long from a
-- press on an idle bar to the first shot).
local function pushAutoRow(self, ev, now)
  if not self._windups then return end
  local r, n = Nock.state.ranged, Nock.state.network
  pushWindup(self, { t = now, ev = ev, swingRemaining = r.swingRemaining, swingDuration = r.swingDuration,
                     latency = ((n and n.latencyMs) or 0) / 1000 })
end

function SwingTimer:START_AUTOREPEAT_SPELL()
  local now, r = GetTime(), Nock.state.ranged
  r.repeating = true
  self._autoStartAt = now
  -- A pending switch-on read: idle bar, still, in range (UpdateWindupFromSwitchOn).
  local idle = r.swingStart <= 0 or r.swingDuration <= 0 or now >= r.swingStart + r.swingDuration
  self._switchOn = { t = now, idle = idle, moving = self._moving == true, inRange = r.targetInRange,
                     rtt = rttNow(), moved = false, cast = false }
  pushAutoRow(self, "AUTO_ON", now)
end

function SwingTimer:STOP_AUTOREPEAT_SPELL()
  local r, now = Nock.state.ranged, GetTime()
  r.repeating = false
  self._switchOn = nil
  -- A FAILED_QUIET in this frame was the switch-off, not a retry.
  self._autoOffAt = now
  if r.retryAt == now then r.retryAt, r.retryShotAt = nil, nil end
  if self._pending then for k in pairs(self._pending) do self._pending[k] = nil end end
  pushAutoRow(self, "AUTO_OFF", GetTime())
end

function SwingTimer:PLAYER_ENTER_COMBAT()
  Nock.state.melee.attacking = true
  pushAutoRow(self, "MELEE_ON", GetTime())
end

function SwingTimer:PLAYER_LEAVE_COMBAT()
  Nock.state.melee.attacking = false
  pushAutoRow(self, "MELEE_OFF", GetTime())
end

function SwingTimer:PLAYER_ENTERING_WORLD()
  -- A loading screen can eat STOP_AUTOREPEAT_SPELL; a stranded `repeating`
  -- would keep the auto bar full (see Nock.AutoSwingLive).
  Nock.state.ranged.repeating = false
  Nock.state.ranged.autoDelay = 0
  self._lastShotAt, self._lastHitAt = nil, nil
  self._windupStart, self._windupSd, self._windupEndAt, self._windupFromCast = nil, nil, nil, false
  self._lastCastAt, self._lastInterruptAt = nil, nil
  self._feignAt, self._fdRestartAt = nil, nil
  local r, c = Nock.state.ranged, Nock.state.context
  r.retryAt, r.retryShotAt, r.pressThroughAt, r.held = nil, nil, nil, false
  c.airborne, c.airborneAt = false, nil
  if self._pending then for k in pairs(self._pending) do self._pending[k] = nil end end
  if self._heldSpeed then self:RefreshHeldSpeeds() end
  -- the median window survives a loading screen: the wind-up is the server's, not the zone's
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
