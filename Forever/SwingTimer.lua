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
    end
    self._switchOn = nil
    r.swingStart = now
    r.swingDuration = duration
    self:ApplyWindupEstimate(duration)   -- rtt / reload follows the reload
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
  if d > 0 then ratio = pub + rttNow(true) / d end
  if ratio > 0.9 then ratio = 0.9 end
  r.windupRatio, r.windupMeasured = ratio, true
  r.windupSource = (#R > 0) and "switch-on" or "seed"
  r.stopByRatio = #S > 0 and SwingTimer.UpperMedian(S) or nil
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

function SwingTimer:PLAYER_EQUIPMENT_CHANGED()
  self:RefreshDualWield()
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
  Nock.state.ranged.repeating = false
  self._switchOn = nil
  pushAutoRow(self, "AUTO_OFF", GetTime())
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
  self._windupStart, self._windupSd, self._windupEndAt, self._windupFromCast = nil, nil, nil, false
  self._lastCastAt, self._lastInterruptAt = nil, nil
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
