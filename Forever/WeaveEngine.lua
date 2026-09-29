-- Forever/WeaveEngine.lua
-- The Forever weave helper's engine, pure: the four-stage loop, learned leg times and a glide driven by movement-key intent.

-- Spec: docs/superpowers/specs/2026-09-28-forever-weave-helper-design.md
-- and the 2026-09-29 addendum (glide on key intent). Inputs are the
-- ladder's zone (MELEE / CLOSE = the dead zone / SWEET / LONG), the rest
-- band (inside item 9606 and able to shoot), the radial intent the helper
-- reads from the movement keys, the character's facing and the two
-- PLAYER_SWING kinds; nothing here reads speed, distance or a secret.

local E = {}

E.SLACK = 0.10           -- s of grace when deciding GO vs WAIT
E.SEED = 1.1             -- s, a leg before anything is learned (weaveLegSeed)
E.LEG_MIN, E.LEG_MAX = 0.3, 4.0
E.MOVE_FRACTION = 0.8    -- a sample counts when intent covered this much of its wall time
E.STALE_DWELL = 0.3      -- s the glide may push on a clamp edge before it is stale
E.LEG_TIMEOUT_MUL = 3    -- a leg this far past its estimate is abandoned
E.IDLE_TIMEOUT = 5       -- s a GO survives while the player moves without reaching the dead zone
E.GO_WINDOW = 0.75       -- default start window (weaveStartWindow): s after the shot in which
                         --   a GO is offered, directly or at the end of a WAIT (the hit resets
                         --   the ranged swing, so a late start throws the swing away)
E.WINDOW_MIN, E.WINDOW_MAX = 0.2, 3.0
E.START_SLACK = 1.0      -- a hunter already moving keeps the GO this much longer than the window
E.WAIT_MAX = E.GO_WINDOW
E.START_MAX = E.GO_WINDOW + E.START_SLACK
E.RESET_GRACE = 0.1      -- s after a melee hit in which a Ranged swing event is the client's own reset
E.MELEE_LATE = 0.5       -- s after a hit in which a MELEE reading is the finder catching up (worst case ~0.3), not a return
E.RELEASE_FLASH = 0.4    -- s the RELEASE stage stays up
E.FACE_DEG = 90          -- facing this far from the anchor: forward runs away from the target
E.SHOOT_FRAC = 0.55      -- seed: the shoot edge's spot between the rest edge (0) and melee (1)
E.FRAC_MIN, E.FRAC_MAX = 0, 0.9
E.DT_MAX = 2.0           -- s one tick may integrate (a loading screen is not a run)
E.EDGE_GAP = 0.05        -- of the dead zone the estimate stops short of either end until the ladder reports it

-- Pure: unsigned degrees between two facings (radians), 0..180.
local function turnDeg(a, b)
  local d = ((b - a) * 180 / math.pi) % 360
  if d > 180 then d = 360 - d end
  return d
end

local function clampLeg(v)
  if v < E.LEG_MIN then return E.LEG_MIN elseif v > E.LEG_MAX then return E.LEG_MAX end
  return v
end

local function clampFrac(v)
  if v < E.FRAC_MIN then return E.FRAC_MIN elseif v > E.FRAC_MAX then return E.FRAC_MAX end
  return v
end

function E.New(legIn, legOut, seed, shootFrac)
  seed = clampLeg(tonumber(seed) or E.SEED)
  return {
    stage = nil, stageAt = 0, zone = nil, rest = true, moving = false,
    legIn = legIn and clampLeg(legIn) or seed,
    legOut = legOut and clampLeg(legOut) or seed,
    learnedIn = legIn ~= nil, learnedOut = legOut ~= nil,
    sampleIn = nil, sampleOut = nil, learnedAt = nil,
    shootFrac = shootFrac and clampFrac(shootFrac) or clampFrac(E.SHOOT_FRAC),
    learnedFrac = shootFrac ~= nil, sampleFrac = nil,
    pos = 0,                  -- position estimate: 0 rest edge, shootFrac shoot edge, 1 melee
    posKnown = false,         -- an edge, a hit or a stop at rest has pinned pos since the target came
    outMap = false,           -- the strip draws the dead zone alone (hit = full, shoot edge = empty)
    leg = nil,                -- { kind, armAt, t0, net, netAtShoot, fromRest, remaining }
    radial = 0, face = 1, anchor = nil, lastNow = nil,
    pinnedFor = 0, stale = false, overshot = false,
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

-- A leg is armed at an edge or a hit (armAt, for the abandon rule); its
-- clock starts on the first tick with intent (t0, for the sample). netAtShoot
-- is the net time at the shoot edge: 0 for a leg that starts there, nil
-- until a rest-band start crosses it. Allocated on the edge, never on the tick.
local function startLeg(st, kind, now, fromRest, netAtShoot)
  st.leg = {
    kind = kind, armAt = now, t0 = nil, net = 0, netAtShoot = netAtShoot,
    fromRest = fromRest == true, remaining = 0,
  }
  st.pending, st.waitFor, st.goAt = false, nil, nil
  st.outMap = kind == "out"
end

local function learnIn(st, sample)
  sample = clampLeg(sample)
  st.legIn = st.learnedIn and clampLeg(0.5 * st.legIn + 0.5 * sample) or sample
  st.learnedIn, st.sampleIn = true, sample
end

local function learnOut(st, sample)
  sample = clampLeg(sample)
  st.legOut = st.learnedOut and clampLeg(0.5 * st.legOut + 0.5 * sample) or sample
  st.learnedOut, st.sampleOut = true, sample
end

-- The in leg ends at melee (the zone or the hit). A leg that began at the
-- rest edge samples its whole net intent time (the start is exact, and the
-- hunter stands at the end whether the hit or the late MELEE report ends
-- it) and where the shoot edge sat. One that began at the shoot edge (a
-- late report) samples the dead zone crossing scaled to the full span, and
-- only when the MELEE report ends it too: the same lag on both ends
-- cancels, the exact hit against a late start does not.
local function finishIn(st, now, byZone)
  local leg = st.leg
  st.leg = nil
  if not leg or leg.kind ~= "in" or leg.t0 == nil then return end
  local wall, net, atShoot = now - leg.t0, leg.net, leg.netAtShoot
  if wall <= 0 or net <= 0 or net < E.MOVE_FRACTION * wall then return end
  if leg.fromRest then
    learnIn(st, net)
  else
    if not byZone then return end
    local span = net - (atShoot or 0)
    if span <= 0 then return end
    learnIn(st, span / (1 - st.shootFrac))
  end
  if leg.fromRest and atShoot ~= nil and atShoot > 0 then
    local frac = clampFrac(atShoot / net)
    st.shootFrac = st.learnedFrac and clampFrac(0.5 * st.shootFrac + 0.5 * frac) or frac
    st.learnedFrac, st.sampleFrac = true, frac
  end
  st.learnedAt = now
end

-- The out leg ends at the shoot edge: its sample is the net intent time
-- from the hit spot (wherever inside reach that was; with the weave key
-- usually deep) to the shoot edge, scaled to the full span. The finder's
-- lag on the SWEET report is in it; the drain from the hit reads smooth
-- and lands on RELEASE (user 2026-09-30).
local function finishOut(st, now)
  local leg = st.leg
  st.leg = nil
  if not leg or leg.kind ~= "out" or leg.t0 == nil then return end
  local wall, net = now - leg.t0, -leg.net
  if wall <= 0 or net <= 0 or net < E.MOVE_FRACTION * wall then return end
  learnOut(st, net / (1 - st.shootFrac))
  st.learnedAt = now
end

-- pos and the running leg's net move by dt of intent rin (the target's
-- frame) up to now; a leg's clock opens at the start of its first slice.
local function integrate(st, dt, rin, now)
  if dt <= 0 or rin == 0 then return end
  local dur = (rin > 0) and st.legIn or st.legOut
  st.pos = st.pos + dt * rin / dur
  local leg = st.leg
  if leg then
    if leg.t0 == nil then leg.t0 = now - dt end
    leg.net = leg.net + dt * rin
  end
end

local function idle(st, now)
  st.leg, st.pending, st.waitFor, st.releaseAt, st.goAt = nil, false, nil, nil, nil
  setStage(st, nil, now)
end

function E.AutoFired(st, now)
  st.pending, st.goAt = true, nil
end

-- A Ranged PLAYER_SWING: the shot left, or, right after a melee hit, the
-- client's own reset of the ranged swing (Forever: melee resets it). A shot
-- proves the character faced the target: the facing anchor.
function E.RangedSwing(st, now, facing)
  if st.hitAt and not st.rangedSeen and now - st.hitAt <= E.RESET_GRACE then
    st.rangedSeen, st.clientResets = true, true
    return false
  end
  local s, z = st.stage, st.zone
  if s == "STRIKE" or s == "OUT" or z == "MELEE" or z == "CLOSE" then
    if st.hitAt and not st.rangedSeen then st.rangedSeen, st.clientResets = true, true end
    return false
  end
  if type(facing) == "number" then st.anchor = facing end
  E.AutoFired(st, now)
  return true
end

-- A MainHand PLAYER_SWING. The hit proves arrival (the finder settles
-- 0.15 s) and the facing, so an in leg finishes here and pos pins to 1.
function E.MeleeHit(st, now, facing)
  st.hitAt, st.rangedSeen, st.reanchored = now, false, false
  if type(facing) == "number" then st.anchor = facing end
  st.pos, st.posKnown, st.lastNow = 1, true, now   -- the estimate is the truth at the hit; the clock restarts here
  local s = st.stage
  if s == "STRIKE" or s == "IN" or s == "GO" or s == "WAIT" then
    if st.leg and st.leg.kind == "in" then finishIn(st, now) end
    startLeg(st, "out", now, false, nil)
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
  st.hitAt, st.anchor, st.zone, st.rest = nil, nil, nil, nil
  st.pos, st.posKnown, st.glide, st.pinnedFor, st.stale, st.overshot, st.outMap = 0, false, 0, 0, false, false, false
end

-- The client's moving flag (PLAYER_STARTED/STOPPED_MOVING) at its own time:
-- a stop closes the clock there with the intent last read (the keys were
-- held until about then), a start opens it there; between ticks the flag
-- also keeps a GO alive. The glide itself runs on intent.
function E.SetMoving(st, moving, now)
  moving = moving == true
  if moving == st.moving then return end
  st.moving = moving
  if st.lastNow == nil or now == nil then return end
  local dt = now - st.lastNow
  if dt < 0 then dt = 0 elseif dt > E.DT_MAX then dt = E.DT_MAX end
  if not moving then integrate(st, dt, st.radial * st.face, now) end
  st.lastNow = now
end

-- zone: the ladder's; rest: inside item 9606 and able to shoot (nil = not
-- known = inside); radial: the movement keys' intent in the character's
-- frame, -1..1; facing: radians (GetPlayerFacing) or nil; meleeReadyIn /
-- raptorReadyIn: seconds until the white swing / Raptor are ready;
-- rangedElapsed: the ranged swing's age.
function E.Step(st, now, zone, rest, radial, facing, meleeReadyIn, rangedRemaining, queueWindow, raptorReadyIn, rangedElapsed)
  local dt = st.lastNow and (now - st.lastNow) or 0
  if dt < 0 then dt = 0 elseif dt > E.DT_MAX then dt = E.DT_MAX end
  st.lastNow = now
  radial = tonumber(radial) or 0
  local face = 1
  if type(facing) == "number" and st.anchor ~= nil and turnDeg(st.anchor, facing) > E.FACE_DEG then face = -1 end
  st.radial, st.face = radial, face
  local rin = radial * face      -- intent in the target's frame: + toward, - away
  local prev, prevRest = st.zone, st.rest
  rest = rest ~= false
  st.zone, st.rest = zone, rest
  if zone == nil or zone == "LONG" then
    idle(st, now)
    st.pos, st.posKnown, st.glide, st.pinnedFor, st.stale, st.overshot, st.outMap = 0, false, 0, 0, false, false, false
    return
  end
  -- This tick's slice of movement first, so an edge reached now finishes
  -- its leg with the whole run and a snap overrides the estimate.
  integrate(st, dt, rin, now)
  local s = st.stage
  if zone ~= prev then
    st.pinnedFor, st.overshot = 0, false
    -- a crossing pins the estimate; the first reading of a target does not
    -- (unless it is melee), so a retarget mid-band learns nothing as "rest"
    if prev ~= nil or zone == "MELEE" then st.posKnown = true end
    local leg = st.leg
    if leg and leg.kind == "in" then
      if zone == "MELEE" then finishIn(st, now, true); setStage(st, "STRIKE", now)
      elseif zone == "CLOSE" then
        -- the shoot edge, from the rest band
        if leg.netAtShoot == nil then leg.netAtShoot = leg.net end
        st.pos = st.shootFrac
      elseif zone == "SWEET" then idle(st, now); st.pos = st.shootFrac end
    elseif leg and leg.kind == "out" then
      if zone == "SWEET" then
        st.pos = st.shootFrac
        finishOut(st, now)
        if rangedRemaining ~= nil and queueWindow ~= nil and rangedRemaining <= queueWindow then
          st.releaseAt = now
          setStage(st, "RELEASE", now)
        else
          setStage(st, nil, now)
        end
      elseif zone == "MELEE" and leg.net < 0 and not (st.hitAt and now - st.hitAt <= E.MELEE_LATE) then
        -- an out leg that had backed out, back in melee: the hunter turned
        -- round. Right after the hit it is the finder catching up (its settle).
        st.leg = nil; setStage(st, "STRIKE", now)
      end
    elseif s == "GO" or s == "WAIT" then
      if zone == "CLOSE" then
        startLeg(st, "in", now, false, 0); st.leg.t0 = now; st.pos = st.shootFrac
        setStage(st, "IN", now)
      elseif zone == "MELEE" then st.pending, st.waitFor = false, nil; setStage(st, "STRIKE", now) end
    elseif s == "STRIKE" then
      if zone == "CLOSE" then startLeg(st, "out", now, false, nil); setStage(st, "OUT", now)
      elseif zone == "SWEET" then st.pos = st.shootFrac; setStage(st, nil, now) end
    elseif s == nil and zone == "CLOSE" then
      -- An uncued crossing: the intent says which way; a mob walking into a
      -- standing hunter starts nothing.
      if prev == "SWEET" and rin > 0 then
        startLeg(st, "in", now, false, 0); st.leg.t0 = now; st.pos = st.shootFrac
        setStage(st, "IN", now)
      elseif prev == "MELEE" and rin < 0 then
        startLeg(st, "out", now, false, nil); st.leg.t0 = now
        setStage(st, "OUT", now)
      end
    end
    local out = st.leg and st.leg.kind == "out" and st.leg.t0 ~= nil
    if zone == "MELEE" and not out then st.pos = 1
    elseif zone == "SWEET" and prev == "CLOSE" then st.pos = st.shootFrac end
  elseif zone == "SWEET" and rest ~= prevRest then
    -- The rest band's outer edge (item 9606), crossed either way; backing
    -- out over it is the overshoot (a mob walking off is not).
    st.pos, st.pinnedFor, st.posKnown = 0, 0, true
    st.overshot = (not rest) and rin < 0
  end
  s = st.stage
  local window = st.goWindow or E.GO_WINDOW
  local startMax = window + E.START_SLACK
  -- A pending shot expires with the swing's age, in any zone: an old one must
  -- not turn into a GO the moment Raptor's cooldown drops under the cap.
  if st.pending and (rangedElapsed or 0) > startMax and s ~= "GO" and s ~= "WAIT" then
    st.pending = false
  end
  -- An owed GO or WAIT, decided every tick so a WAIT counts down into GO,
  -- offered from the rest band only. Both the white swing and Raptor's
  -- cooldown must be ready on arrival; a wait longer than the window is not
  -- worth the swing the hit will reset.
  if st.pending and zone == "SWEET" and rest and (s == nil or s == "GO" or s == "WAIT") then
    local need = meleeReadyIn or 0
    if (raptorReadyIn or 0) > need then need = raptorReadyIn end
    -- the arrival from where the hunter stands (the whole leg when unknown)
    local arrive = st.posKnown and (1 - st.pos) * st.legIn or st.legIn
    local wait = need - (arrive + E.SLACK)
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
  local moving = st.moving or rin ~= 0
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
  -- The run from the rest spot: intent toward the target under a GO or WAIT
  -- starts the in leg at once, so the glide draws the first step.
  if (s == "GO" or s == "WAIT") and zone == "SWEET" and rin > 0 and not st.leg then
    startLeg(st, "in", now, st.posKnown and (st.pos - dt * rin / st.legIn) <= 0.001, nil)
    st.leg.t0, st.leg.net = now - dt, dt * rin      -- this tick's slice was the first step
    setStage(st, "IN", now)
    s = "IN"
  end
  -- A rest-band run-in that never reached the shoot edge is over when the
  -- next shot is due, like the GO it grew from.
  if st.leg and st.leg.kind == "in" and st.leg.netAtShoot == nil and (rangedElapsed or 0) > startMax then
    idle(st, now)
    s = nil
  end
  -- The glide: pos integrates the intent over the leg it is running on,
  -- clamped to the zone's band. An out leg drains from the hit spot while
  -- the ladder still reads MELEE (the learned out time covers the stretch
  -- inside reach); a running in leg in the rest band may reach the shoot
  -- edge before the crossing is reported.
  local leg = st.leg
  local lo, hi
  local gap = E.EDGE_GAP * (1 - st.shootFrac)
  if zone == "MELEE" then
    lo, hi = (leg and leg.kind == "out") and (st.shootFrac + gap) or 1, 1
  elseif zone == "CLOSE" then
    -- a hair short of both ends: the finder's settle reports the crossing
    -- a little after the estimate gets there, and a full bar under a DEAD
    -- ZONE label read wrong (user 2026-09-30); the edge snaps the rest
    lo, hi = st.shootFrac + gap, 1 - gap
  elseif rest then
    lo, hi = 0, st.shootFrac
  else
    lo, hi = 0, 0
  end
  -- Where the hunter stands at rest IS the rest edge: a stop in the band
  -- with no leg running settles the estimate to 0 (the way out ends where
  -- the key is let go, not where the last run-in began).
  if zone == "SWEET" and rest and not leg and rin == 0 and not st.moving then st.pos, st.posKnown = 0, true end
  local clamped = false
  if st.pos < lo then st.pos, clamped = lo, true elseif st.pos > hi then st.pos, clamped = hi, true end
  -- Stale: a leg pushing on the edge the finder has not reported it past
  -- (an in leg at the top of its band, an out leg at the bottom); pushing
  -- into melee at STRIKE or after the hit is not.
  local pushing = clamped and leg ~= nil
    and ((leg.kind == "in" and rin > 0 and st.pos >= hi and zone ~= "MELEE")
      or (leg.kind == "out" and rin < 0 and st.pos <= lo and zone == "CLOSE"))
  if pushing then st.pinnedFor = st.pinnedFor + dt else st.pinnedFor = 0 end
  st.stale = st.pinnedFor > E.STALE_DWELL
  -- The words follow the intent: a hunter backing out of a run-in reads
  -- BACK OUT; the leg keeps its kind for the sample. Forward at the melee
  -- end after the hit (the key still held) is not a run-in.
  if leg and (s == "IN" or s == "OUT") then
    if rin > 0 and not (leg.kind == "out" and st.pos >= 1) then setStage(st, "IN", now)
    elseif rin < 0 then setStage(st, "OUT", now) end
  end
  -- Abandoned past 3x its estimate of intent, or on the wall clock (a
  -- stun, a knockback, standing in melee after the hit): the words go, the
  -- position estimate stays.
  if leg then
    local dur = (leg.kind == "in") and st.legIn or st.legOut
    local limit = dur * E.LEG_TIMEOUT_MUL
    if limit < E.IDLE_TIMEOUT then limit = E.IDLE_TIMEOUT end
    if math.abs(leg.net) > dur * E.LEG_TIMEOUT_MUL or now - leg.armAt > limit then
      idle(st, now)
      leg = nil
    end
  end
  if leg then
    -- to melee for an in leg; to the shoot edge, where OUT ends, for an out leg
    leg.remaining = (leg.kind == "in") and (1 - st.pos) * st.legIn or (st.pos - st.shootFrac) * st.legOut
    if leg.remaining < 0 then leg.remaining = 0 end
  end
  -- The strip: the way in rises over the whole span from the first step;
  -- the way out drains the dead zone alone, so RELEASE lands on empty (the
  -- rest band is never drawn through on the way out; recordings 2026-09-30).
  -- The map switches back when the next in leg starts.
  if st.outMap then
    local span = 1 - st.shootFrac
    st.glide = (span > 0) and (st.pos - st.shootFrac) / span or 0
    if st.glide < 0 then st.glide = 0 end
  else
    st.glide = st.pos
  end
end

-- Flat fields on state.weave (Core/State.lua declares them); no allocation.
function E.Publish(st, w)
  local leg = st.leg
  w.stage = st.stage
  w.legKind = leg and leg.kind or nil
  w.legProg = leg and st.pos or 0
  w.legRemaining = leg and leg.remaining or 0
  w.legStale = st.stale
  w.legIn, w.legOut = st.legIn, st.legOut
  w.waitFor = st.waitFor
  w.glide = st.glide
  w.releaseAt = st.releaseAt
  w.radial, w.face, w.overshot = st.radial, st.face, st.overshot
end

local LibStub = _G.LibStub
local Nock = LibStub and LibStub("AceAddon-3.0", true) and LibStub("AceAddon-3.0"):GetAddon("Nock", true)
if Nock then Nock.WeaveEngine = E end
return E
