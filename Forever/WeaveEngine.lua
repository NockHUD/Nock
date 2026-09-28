-- Forever/WeaveEngine.lua
-- The Forever weave helper's engine, pure: the four-stage loop, learned leg times and the time-domain glide.

-- Spec: docs/superpowers/specs/2026-09-28-forever-weave-helper-design.md.
-- Inputs are the ladder's zone (Forever/RangeFinder.lua: MELEE / CLOSE = the
-- dead zone / SWEET / LONG), the two PLAYER_SWING kinds and whether the
-- player moves; nothing here reads speed, distance or a secret.

local E = {}

E.SLACK = 0.10           -- s of grace when deciding GO vs WAIT
E.SEED = 1.1             -- s, a leg before anything is learned (weaveLegSeed)
E.LEG_MIN, E.LEG_MAX = 0.3, 4.0
E.MOVE_FRACTION = 0.8    -- a sample counts when the player moved this much of it
E.STALE_MUL = 1.3        -- a leg this far past its estimate, still moving, is stale
E.LEG_TIMEOUT_MUL = 3    -- a leg this far past its estimate is abandoned
E.IDLE_TIMEOUT = 5       -- s a GO survives while the player moves without reaching the dead zone
E.GO_WINDOW = 0.75       -- default start window (weaveStartWindow): s after the shot in which
                         --   a GO is offered, directly or at the end of a WAIT (the hit resets
                         --   the ranged swing, so a late start throws the swing away)
E.WINDOW_MIN, E.WINDOW_MAX = 0.2, 3.0
E.START_SLACK = 1.0      -- a hunter already moving keeps the GO this much longer than the window
-- Kept for the tests and the docs: with the default window, WAIT_MAX = the
-- window and START_MAX = window + START_SLACK (1.75 s).
E.WAIT_MAX = E.GO_WINDOW
E.START_MAX = E.GO_WINDOW + E.START_SLACK
E.RESET_GRACE = 0.1      -- s after a melee hit in which a Ranged swing event is the client's own reset
E.RELEASE_FLASH = 0.4    -- s the RELEASE stage stays up

local function clampLeg(v)
  if v < E.LEG_MIN then return E.LEG_MIN elseif v > E.LEG_MAX then return E.LEG_MAX end
  return v
end

function E.New(legIn, legOut, seed)
  seed = clampLeg(tonumber(seed) or E.SEED)
  return {
    stage = nil, stageAt = 0, zone = nil, moving = false,
    legIn = legIn and clampLeg(legIn) or seed,
    legOut = legOut and clampLeg(legOut) or seed,
    learnedIn = legIn ~= nil, learnedOut = legOut ~= nil,
    sampleIn = nil, sampleOut = nil, learnedAt = nil,
    leg = nil,                -- { kind, t0, dur, moved, running, resumeAt, prog, stale, remaining }
    pending = false,          -- an auto fired: a GO or a WAIT is owed
    goAt = nil,               -- when the GO window opened
    goWindow = E.GO_WINDOW,   -- the start window (E.SetWindow)
    waitFor = nil, glide = 0, releaseAt = nil,
    hitAt = nil, rangedSeen = true, reanchored = true, clientResets = false,
  }
end

-- The start window, clamped; nil = the default. Returns st.
function E.SetWindow(st, w)
  w = tonumber(w) or E.GO_WINDOW
  if w < E.WINDOW_MIN then w = E.WINDOW_MIN elseif w > E.WINDOW_MAX then w = E.WINDOW_MAX end
  st.goWindow = w
  return st
end

local function setStage(st, stage, now)
  if st.stage ~= stage then st.stage, st.stageAt = stage, now end
end

local function elapsedOf(leg, now)
  local e = leg.moved
  if leg.running then e = e + (now - leg.resumeAt) end
  return e
end

-- A leg table is allocated on a zone edge, never on the tick.
local function startLeg(st, kind, now, moving)
  st.leg = {
    kind = kind, t0 = now, dur = (kind == "in") and st.legIn or st.legOut,
    moved = 0, running = moving == true, resumeAt = now, prog = 0, stale = false, remaining = 0,
  }
  st.pending, st.waitFor, st.goAt = false, nil, nil
end

-- The leg ends at an edge: learn it when the player moved for most of it.
local function finishLeg(st, now)
  local leg = st.leg
  if not leg then return end
  local moved, total = elapsedOf(leg, now), now - leg.t0
  st.leg = nil
  if total <= 0 or moved < E.MOVE_FRACTION * total then return end
  local sample = clampLeg(moved)
  if leg.kind == "in" then
    st.legIn = st.learnedIn and clampLeg(0.5 * st.legIn + 0.5 * sample) or sample
    st.learnedIn, st.sampleIn = true, sample
  else
    st.legOut = st.learnedOut and clampLeg(0.5 * st.legOut + 0.5 * sample) or sample
    st.learnedOut, st.sampleOut = true, sample
  end
  st.learnedAt = now
end

local function idle(st, now)
  st.leg, st.pending, st.waitFor, st.releaseAt, st.goAt = nil, false, nil, nil, nil
  setStage(st, nil, now)
end

function E.AutoFired(st, now)
  st.pending, st.goAt = true, nil
end

-- A Ranged PLAYER_SWING: the shot left, or, right after a melee hit, the
-- client's own reset of the ranged swing (Forever: melee resets it).
function E.RangedSwing(st, now)
  if st.hitAt and not st.rangedSeen and now - st.hitAt <= E.RESET_GRACE then
    st.rangedSeen, st.clientResets = true, true
    return false
  end
  -- No shot leaves from melee or the dead zone: a Ranged event while the
  -- stage is STRIKE or OUT is the client's reset however late it arrives
  -- (a late one would otherwise owe a phantom GO after the RELEASE).
  local s, z = st.stage, st.zone
  if s == "STRIKE" or s == "OUT" or z == "MELEE" or z == "CLOSE" then
    if st.hitAt and not st.rangedSeen then st.rangedSeen, st.clientResets = true, true end
    return false
  end
  E.AutoFired(st, now)
  return true
end

-- A MainHand PLAYER_SWING. The hit proves arrival even when the zone still
-- reads DEAD (the finder settles 0.15 s), so an in leg finishes here.
function E.MeleeHit(st, now, moving)
  st.hitAt, st.rangedSeen, st.reanchored = now, false, false
  local s = st.stage
  if s == "STRIKE" or s == "IN" or s == "GO" or s == "WAIT" then
    if st.leg and st.leg.kind == "in" then finishLeg(st, now) end
    startLeg(st, "out", now, moving)
    setStage(st, "OUT", now)
  end
end

-- The hit time to re-anchor the ranged swing on, once, when the client sent
-- no Ranged event of its own inside the grace.
function E.ReanchorDue(st, now)
  if st.hitAt and not st.rangedSeen and not st.reanchored and not st.clientResets
     and now - st.hitAt >= E.RESET_GRACE then
    st.reanchored = true
    return st.hitAt
  end
  return nil
end

function E.TargetChanged(st, now)
  idle(st, now)
  st.hitAt = nil
end

-- A movement edge at its own time (PLAYER_STARTED/STOPPED_MOVING are plain
-- on Forever): the leg clock closes when the player stopped, not at the next
-- tick. Step repeats the same bookkeeping for a caller that only polls.
function E.SetMoving(st, moving, now)
  moving = moving == true
  st.moving = moving
  local leg = st.leg
  if not leg then return end
  if moving and not leg.running then
    leg.running, leg.resumeAt = true, now
  elseif not moving and leg.running then
    leg.moved, leg.running = leg.moved + (now - leg.resumeAt), false
  end
end

-- raptorReadyIn: seconds until Raptor Strike is off cooldown (0 = ready or
-- unknown); it must be castable on arrival like the white swing.
-- rangedElapsed: seconds since the last shot (the swing's age); a start is
-- only offered while it is young (START_MAX).
function E.Step(st, now, zone, moving, meleeReadyIn, rangedRemaining, queueWindow, raptorReadyIn, rangedElapsed)
  E.SetMoving(st, moving, now)
  moving = st.moving
  local leg = st.leg
  local prev = st.zone
  st.zone = zone
  if zone == nil or zone == "LONG" then
    idle(st, now)
    st.glide = 0
    return
  end
  local s = st.stage
  if zone ~= prev then
    if leg and leg.kind == "in" then
      if zone == "MELEE" then finishLeg(st, now); setStage(st, "STRIKE", now)
      elseif zone == "SWEET" then idle(st, now) end
    elseif leg and leg.kind == "out" then
      if zone == "SWEET" then
        finishLeg(st, now)
        if rangedRemaining ~= nil and queueWindow ~= nil and rangedRemaining <= queueWindow then
          st.releaseAt = now
          setStage(st, "RELEASE", now)
        else
          setStage(st, nil, now)
        end
      elseif zone == "MELEE" then
        st.leg = nil
        setStage(st, "STRIKE", now)
      end
    elseif s == "GO" or s == "WAIT" then
      if zone == "CLOSE" then startLeg(st, "in", now, moving); setStage(st, "IN", now)
      elseif zone == "MELEE" then st.pending, st.waitFor = false, nil; setStage(st, "STRIKE", now) end
    elseif s == "STRIKE" then
      if zone == "CLOSE" then startLeg(st, "out", now, moving); setStage(st, "OUT", now)
      elseif zone == "SWEET" then setStage(st, nil, now) end
    elseif s == nil and zone == "CLOSE" and moving then
      -- An uncued crossing (the hunter weaves without a GO): the leg still
      -- runs, so the glide moves, the crossing is learned and the words
      -- follow from here. A mob walking into a standing hunter starts nothing.
      if prev == "SWEET" then startLeg(st, "in", now, moving); setStage(st, "IN", now)
      elseif prev == "MELEE" then startLeg(st, "out", now, moving); setStage(st, "OUT", now) end
    end
  end
  s = st.stage
  local window = st.goWindow or E.GO_WINDOW
  local startMax = window + E.START_SLACK
  -- A pending shot expires with the swing's age, in any zone: an old one must
  -- not turn into a GO the moment Raptor's cooldown drops under the cap.
  if st.pending and (rangedElapsed or 0) > startMax and s ~= "GO" and s ~= "WAIT" then
    st.pending = false
  end
  -- An owed GO or WAIT, decided every tick so a WAIT counts down into GO.
  -- Both the white swing and Raptor's cooldown must be ready on arrival; a
  -- wait longer than WAIT_MAX is not worth the swing the hit will reset.
  if st.pending and zone == "SWEET" and (s == nil or s == "GO" or s == "WAIT") then
    local need = meleeReadyIn or 0
    if (raptorReadyIn or 0) > need then need = raptorReadyIn end
    local wait = need - (st.legIn + E.SLACK)
    if wait > window then
      st.pending, st.waitFor = false, nil
      setStage(st, nil, now)
    elseif wait > 0 then
      st.waitFor, st.goAt = wait, nil
      setStage(st, "WAIT", now)
    else
      st.waitFor = nil
      st.goAt = st.goAt or now
      setStage(st, "GO", now)
    end
    s = st.stage
  end
  -- GO is a window: past it a hunter still standing keeps the swing and
  -- waits for the next shot; one already moving keeps the cue a while. And
  -- nothing is offered once the swing is old: the next shot is close.
  if (s == "GO" or s == "WAIT") and (rangedElapsed or 0) > startMax then
    idle(st, now)
    s = nil
  elseif s == "GO" and st.goAt then
    local open = now - st.goAt
    if open > window and (not moving or open > E.IDLE_TIMEOUT) then
      idle(st, now)
      s = nil
    end
  end
  if s == "RELEASE" and now - (st.releaseAt or now) >= E.RELEASE_FLASH then
    st.releaseAt = nil
    setStage(st, nil, now)
  end
  -- The glide: elapsed moving time over the learned leg, clamped, snapped by
  -- the edges above; 0 = the ranged end, 1 = the melee end.
  leg = st.leg
  if leg then
    local e = elapsedOf(leg, now)
    -- Abandoned past 3x its estimate of moving time, or on the wall clock
    -- (a stun, a knockback, standing in melee after the hit): a paused leg
    -- must not keep the cue marching and the range warning silent.
    local limit = leg.dur * E.LEG_TIMEOUT_MUL
    if limit < E.IDLE_TIMEOUT then limit = E.IDLE_TIMEOUT end
    if e > leg.dur * E.LEG_TIMEOUT_MUL or now - leg.t0 > limit then
      idle(st, now)
      st.glide = (zone == "MELEE") and 1 or 0
      return
    end
    local p = e / leg.dur
    if p > 1 then p = 1 end
    leg.prog = (leg.kind == "in") and p or (1 - p)
    leg.stale = moving and e > leg.dur * E.STALE_MUL
    leg.remaining = leg.dur - e
    if leg.remaining < 0 then leg.remaining = 0 end
    st.glide = leg.prog
  else
    st.glide = (zone == "MELEE") and 1 or 0
  end
end

-- Flat fields on state.weave (Core/State.lua declares them); no allocation.
function E.Publish(st, w)
  local leg = st.leg
  w.stage = st.stage
  w.legKind = leg and leg.kind or nil
  w.legProg = leg and leg.prog or 0
  w.legRemaining = leg and leg.remaining or 0
  w.legStale = (leg and leg.stale) and true or false
  w.legIn, w.legOut = st.legIn, st.legOut
  w.waitFor = st.waitFor
  w.glide = st.glide
  w.releaseAt = st.releaseAt
end

local LibStub = _G.LibStub
local Nock = LibStub and LibStub("AceAddon-3.0", true) and LibStub("AceAddon-3.0"):GetAddon("Nock", true)
if Nock then Nock.WeaveEngine = E end
return E
