-- Modules/PracticeEngine.lua
-- The simulated hunter behind practice mode: pure (no WoW APIs), time-driven.

local E = {}

E.DEFAULTS = {
  ws = 3.0,              -- ranged weapon tooltip speed
  baseRangedMul = 1.38,  -- static ranged haste (quiver x Serpent's Swiftness)
  latency = 0,           -- seconds a press takes to reach the server
  queueWindow = 0.4,     -- spell-queue tolerance (wowsims MaxSpellQueueWindow)
  gcd = 1.5,             -- fixed for hunters (wowsims IgnoreHaste)
  imprArcanePts = 0,
  castCorr = 1,          -- measured residual on cast times (Nock.RangedCastTime)
  multiCd = 10,          -- Constants.PRACTICE.MULTI_CD
  arcaneCdBase = 6,      -- Constants.PRACTICE.ARCANE_CD_BASE
  arcaneCdPerPt = 0.2,   -- Constants.PRACTICE.ARCANE_CD_PER_PT
  armOnShot = true,      -- a Steady/Multi/Arcane press also arms auto-repeat
  eventCap = 2000,
  mws = 3.7,             -- melee weapon tooltip speed
  baseMeleeMul = 1.0,    -- static melee haste
  meleeRange = 5,        -- yards: in melee (Wing Clip reach)
  shootMin = 5,          -- yards: Auto Shot minimum (= meleeRange: no unshootable sliver outside melee)
  shootMax = 35,         -- yards: Auto Shot maximum (past it the shoot probe fails: OUT)
  weaveRing = 7,         -- yards: one step from melee (IsItemInRange 8149)
  startDistance = 7,     -- yards to the virtual target at the pull
  raptorCd = 6,
  meleeRetryPulse = 0.5, -- server melee re-check after entering melee (Snowball bypasses)
  footwork = "move",     -- "move" (caller feeds Reckon) | "key" (engine synthesises)
  stepTime = 0.3,        -- key-only footwork: seconds to step in/out
  dirSplit = 4.5,        -- yd/s: above = running (closing), below = backpedal (fallback when run speed unknown)
  dirFrac = 0.82,        -- run/backpedal split as a fraction of the CURRENT run speed (backpedal is 4.5/7 = 0.64 of it)
  stillSpeed = 0.5,      -- yd/s: below = standing
  rearmPulse = 0.5,      -- client re-check cadence for !Auto Shot (Nock.RETRY_PULSE)
  rearmWindupAfterReady = true,
  releaseCost = nil,     -- injected: Nock.ReleaseCost(rem, pulse). Nil = free re-arm
  legsNeeded = 0.7,      -- seconds a full weave takes (wowsims 0.1 + 0.1 move + 0.5 re-check)

  -- Phase 4: procs, haste and cooldowns (spec "Rules"/"Haste"; wowsims numbers)
  quickShots = true,     -- roll Quick Shots on every auto
  qsChance = 0.10, qsDur = 12, qsMul = 1.15,
  rfDur = 15, rfMul = 1.4,
  lustDur = 40, lustMul = 1.3,
  drumsDur = 30, drumsRating = 80,
  dstDur = 10, dstRating = 325,
  potDur = 15, potRating = 400,
  ratingPer100 = 1577,   -- haste rating for +100% (15.77 per 1%)
  seed = 1,              -- RNG seed (Quick Shots, crits); fights are repeatable
  cooldowns = { RF = 300, Spec = 120, T1 = 120, T2 = 120, Drums = 120, Pot = 120, KC = 5 },
  critRanged = 0, critMelee = 0, kcWindow = 5,   -- crit chance opens the Kill Command window
}

local CAST_BASE = { steady = 1.5, multi = 0.5, arcane = 0 }
local CD_KEY    = { multi = "MS", arcane = "Arc" }
local PROC_DUR_KEY = { QS = "qsDur", RF = "rfDur", Lust = "lustDur", Drums = "drumsDur", DST = "dstDur", Pot = "potDur" }
local CD_ACTION    = { rf = "RF", spec = "Spec", t1 = "T1", t2 = "T2", drums = "Drums", pot = "Pot" }
local PROC_ORDER   = { "QS", "RF", "Lust", "Drums", "DST", "Pot" }

-- Cast time for a spell: the haste multiplier plus the measured residual the
-- live cast bar uses (Nock.RangedCastTime). Never applied to the wind-up.
local function castTimeOf(e, spell)
  return CAST_BASE[spell] * e.cfg.castCorr / e.rangedMul
end

-- Cooldown a cooldown key gets when it is used. Key-aware so Arcane never
-- inherits Multi's 10s (it used to, on the cast-completion path).
local function cdFor(e, key)
  if key == "MS" then return e.cfg.multiCd end
  return e.cfg.arcaneCdBase - e.cfg.arcaneCdPerPt * e.cfg.imprArcanePts
end

-- Seeded Park-Miller minimal-standard LCG: stays exact in a double (unlike the
-- glibc-style constants this replaced, which overflow 2^53 and quantize most
-- draws). The same seed replays the same fight, so a scenario drill is
-- repeatable and tests are deterministic. Returns (0,1); seed must be non-zero.
-- Defined above E.Reset: Reset burns the generator in immediately after
-- seeding it, before anything else can call rng().
local function rng(e)
  e.rngState = (e.rngState * 16807) % 2147483647
  return e.rngState / 2147483647
end

function E.New(cfg)
  local e = { cfg = {} }
  for k, v in pairs(E.DEFAULTS) do e.cfg[k] = v end
  for k, v in pairs(cfg or {}) do e.cfg[k] = v end
  e.events = {}
  -- The caller's own auto-stop for the fight, overriding the scenario's own
  -- len= when set (E.LoadScenario's third argument): the drill ladder caps a
  -- teaching drill at 60 s without editing the catalog row behind it, which the
  -- picker shares (R6c). Here and not in Reset, for the same reason `scenario`
  -- is not in Reset: it is armed BEFORE StartFight, and StartFight resets.
  e.len = nil
  E.Reset(e)
  return e
end

function E.Reset(e)
  local c = e.cfg
  e.t, e.fightOn, e.t0 = 0, false, 0
  -- Two-stage start. StartFight only ARMS: the clock, the scenario script and
  -- every window the grader opens hang off the PULL, which is the player's
  -- first press. Between the two the engine is awake (range and footwork are
  -- tracked so the drill knows where you stand) but nothing runs and nothing
  -- is emitted — a fight that is never pulled leaves an empty event stream.
  e.armed, e.pulled = false, false
  e.rangedMul = c.baseRangedMul
  e.cycle  = c.ws / e.rangedMul
  e.windup = 0.5 / e.rangedMul
  e.moving = false
  e.movingSince = nil                     -- the open MOVE span (the combat log)
  e.repeating, e.nextShotAt, e.windupAt = false, 0, nil
  e.windupShotAt = nil                    -- the shot this wind-up already owns
  e.gridShotAt = 0                        -- the grid a re-arm is measured against
  e.lastShotAt, e.lastAutoDelay = 0, 0
  e.gcdStart, e.gcdEnd = 0, 0
  e.gcdSpell = nil
  e.cast, e.castEndAt = nil, 0
  e.queued = nil
  e.pending, e.nPending = {}, 0
  -- How many inputs the player has made this fight. `nPending` drains, so it
  -- cannot answer "has anything been pressed yet" — the question the views ask
  -- to know whether the fight has actually begun (the pre-pull hold).
  e.nPress = 0
  -- ...and how many of those inputs came from the WEAVE key. E.Weave bumps both
  -- counters (on each edge), so a reader comparing the two deltas can tell a
  -- weave edge from an ability press without being told which — which is how the
  -- conveyor picks the lane its press flash belongs on (R6b).
  e.nWeave = 0
  e.cdReady = { MS = 0, Arc = 0 }
  for k in pairs(c.cooldowns) do e.cdReady[k] = 0 end
  e.procs = { QS = 0, RF = 0, Lust = 0, Drums = 0, DST = 0, Pot = 0 }   -- until-times, 0 = off
  e.rngState = (c.seed and c.seed > 0) and c.seed or 1
  for _ = 1, 16 do rng(e) end   -- small seeds start near zero; burn in the stream
  e.n, e.dropped = 0, 0
  e.wasBusy = false
  e.dist, e.speed = c.startDistance, 0
  e.inMelee, e.canShoot, e.nearRing, e.zone = false, true, true, nil
  e.meleeMul = c.baseMeleeMul
  e.meleeCycle = c.mws / e.meleeMul
  e.meleeReadyAt, e.meleeOn = 0, false
  e.raptorQueued, e.raptorReadyAt = false, 0
  e.meleeRecheckAt, e.enteredMeleeAt, e.leftMeleeAt = 0, nil, nil
  e.weaveDownAt, e.poked = nil, false
  e.pendingMove, e.nPendingMove = {}, 0   -- key-only footwork
  e.legs = nil                            -- per-hold footwork legs (one table per weave)
  e.oppOpen, e.deadzoned = false, false
  e.rearmCost, e.rearmCause = 0, nil
  e.legsNeeded = c.legsNeeded
  e.scriptI, e.ended = 1, false
  e.kcUntil = 0
  for i = #e.events, 1, -1 do e.events[i] = nil end
end

local function emit(e, ev)
  if e.n >= e.cfg.eventCap then e.dropped = e.dropped + 1 return end
  e.n = e.n + 1
  e.events[e.n] = ev
end

local function procOn(e, name) return e.procs[name] > 0 end

-- Is the fight actually under way? An ARMED fight is on but not pulled, and
-- nothing may reach the event stream before the `pull` that dates it — the
-- review, the grader's first window and every relative stamp read event 1 as
-- the origin.
local function running(e) return e.fightOn and e.pulled end

-- Haste from the procs that are up. A change never moves a ranged shot already
-- on the grid (nextShotAt untouched; the new cycle applies from the next
-- fire), rescales the melee swing in flight proportionally (wowsims), and
-- leaves a cast in flight at its length. Emits a haste event on change.
-- `force` publishes the event even when nothing moved: the pull needs it after
-- replaying procs that were popped while the fight was only armed, whose own
-- effect on the multiplier had already been applied (silently) back then.
local function recomputeHaste(e, at, force)
  local c = e.cfg
  local rating = (procOn(e, "Drums") and c.drumsRating or 0)
    + (procOn(e, "DST") and c.dstRating or 0)
    + (procOn(e, "Pot") and c.potRating or 0)
  local ratingMul = 1 + rating / c.ratingPer100
  local rm = c.baseRangedMul
    * (procOn(e, "QS") and c.qsMul or 1)
    * (procOn(e, "RF") and c.rfMul or 1)
    * (procOn(e, "Lust") and c.lustMul or 1)
    * ratingMul
  local mm = c.baseMeleeMul * (procOn(e, "Lust") and c.lustMul or 1) * ratingMul
  local same = math.abs(rm - e.rangedMul) < 1e-9 and math.abs(mm - e.meleeMul) < 1e-9
  if same and not force then return end
  -- Only a real change rescales the swing in flight: a forced re-publish must
  -- not push meleeReadyAt around by a multiplier of one.
  if not same and e.meleeReadyAt > at then
    e.meleeReadyAt = at + (e.meleeReadyAt - at) * (e.meleeMul / mm)
  end
  e.rangedMul, e.meleeMul = rm, mm
  e.cycle, e.windup = c.ws / rm, 0.5 / rm
  e.meleeCycle = c.mws / mm
  if running(e) then
    emit(e, { t = at, kind = "haste", rangedMul = rm, meleeMul = mm,
              qs = procOn(e, "QS"), rf = procOn(e, "RF"), lust = procOn(e, "Lust"), drums = procOn(e, "Drums") })
  end
end

-- A crit opens (or extends) the Kill Command window (wowsims
-- killCommandEnabledUntil). Rolled per hit on the seeded RNG.
local function rollCrit(e, at, chance)
  if chance <= 0 or rng(e) >= chance then return end
  local wasOpen = e.kcUntil > at
  e.kcUntil = at + e.cfg.kcWindow
  if not wasOpen then emit(e, { t = at, kind = "kcwin" }) end
end

-- Turn a proc on (for `dur` seconds from `at`, refreshing) or off. Public:
-- panel buttons and scenario scripts call it; Quick Shots and the cooldown
-- actions call it from inside.
function E.Proc(e, name, on, at, dur)
  local c = e.cfg
  local was = procOn(e, name)
  if on then
    local d = dur or c[PROC_DUR_KEY[name]] or 10
    e.procs[name] = at + d
  else
    e.procs[name] = 0
  end
  if was ~= on and running(e) then emit(e, { t = at, kind = "proc", name = name, on = on }) end
  recomputeHaste(e, at)
end

-- Hold a proc up for the rest of the fight by hand (the palette's second
-- click, 2026-08-27), or let it go: on = the proc is parked past the horizon
-- and phase 0b's expiry sweep skips it (the same shape as a scenario's
-- `hold=`); off = the hold and the proc both end now.
function E.Hold(e, name, on, at)
  if e.procs[name] == nil then return end
  if on then
    e.hold = e.hold or {}
    e.hold[name] = true
    E.Proc(e, name, true, at, 1e9)
  else
    if e.hold then e.hold[name] = nil end
    E.Proc(e, name, false, at)
  end
end

-- ARM the fight. Nothing is emitted and no clock starts: `t0` is provisional
-- (the views freeze their strip on it) until the first press pulls. Pressing
-- Start and then reading the panel for ten seconds must not cost you ten
-- seconds of fight — the drill begins when you do.
function E.StartFight(e, t, seed)
  E.Reset(e)
  if seed and seed > 0 then
    e.rngState = seed
    for _ = 1, 16 do rng(e) end   -- small seeds start near zero; burn in the stream
  end
  e.fightOn, e.armed, e.pulled = true, true, false
  e.t0, e.t = t, t
end

-- The PULL: the first press of the fight, whatever it was. Everything the
-- fight is measured from is stamped here — `t0` (so the scenario script and
-- `len` count from the press), the `pull` event the review and the grader take
-- as their origin, the held procs and the range zone the drill opened in.
-- Emitted before the press itself, which its caller applies afterwards.
local function pull(e, t)
  e.armed, e.pulled = false, true
  e.t0, e.t = t, t
  emit(e, { t = t, kind = "pull" })
  -- A proc popped on the panel while the fight was only ARMED (the palette's
  -- buttons are gated on fightOn, which is true from Start) already changed
  -- e.procs and the haste with it — but its events were swallowed, because
  -- nothing may reach the stream before the pull that dates it. Replay them
  -- here, or the grader's first window opens at BASE haste and grades a Rapid
  -- Fire pull against the unhasted rotation.
  local carried = false
  for i = 1, #PROC_ORDER do
    local name = PROC_ORDER[i]
    local untilT = e.procs[name]
    if untilT > 0 then
      carried = true
      if untilT > t then
        emit(e, { t = t, kind = "proc", name = name, on = true })
      else
        -- Popped while armed and already run out by the pull: as far as this
        -- fight is concerned it never happened, so clear it silently. Phase 0b
        -- never ran (Step returns early while armed) and would otherwise expire
        -- it at its own moment — which is BEFORE the pull, out of order.
        e.procs[name] = 0
      end
    end
  end
  -- Held procs (scenario `hold=`) go up right after the pull, never to expire
  -- (phase 0b skips names in e.hold): the "locked drill" shape — the grader's
  -- first window opens at the pull, and the haste event re-opens it at once.
  -- A held proc the player had already popped is on the stream from the walk
  -- above, and E.Proc's own `was ~= on` gate keeps it from going out twice.
  if e.hold then
    for i = 1, #PROC_ORDER do
      local name = PROC_ORDER[i]
      if e.hold[name] then E.Proc(e, name, true, t, 1e9) end
    end
  end
  -- The haste those replayed procs are worth. Forced: the multiplier was
  -- updated when they were popped, so there is nothing left for recomputeHaste
  -- to notice on its own. (A held proc that genuinely changed it has already
  -- emitted its own through E.Proc.)
  if carried then recomputeHaste(e, t, true) end
  -- Where you were standing when you pulled. SetDistance tracked the zone
  -- while armed but held its event back (it would have preceded the pull), so
  -- the stream still opens with a range the review can lay a lane against.
  if e.zone then
    emit(e, { t = t, kind = "range", zone = e.zone, inMelee = e.inMelee })
  end
end

function E.StopFight(e, t)
  if not e.fightOn then return end
  e.fightOn = false
  -- Armed but never pulled: there was no fight. Cancelled, not stopped — no
  -- `stop` event, so the stream stays empty and nothing downstream grades it.
  if e.armed then
    e.armed = false
    return
  end
  -- A stretch of movement still open at the stop is closed here, so the log
  -- never draws a span that runs past the fight.
  if e.movingSince then
    emit(e, { t = t, kind = "move", t0 = e.movingSince, t1 = t })
    e.movingSince = nil
  end
  emit(e, { t = t, kind = "stop" })
end

-- The feet. Besides gating a cast, every stretch of movement is filed as a
-- `move` span when it ENDS (like weave/done: one event per stretch, t0..t1),
-- and the open one rides the snapshot as `movingSince` -- the expert combat
-- log's MOVE row. Real feet only: key-only footwork files its synthesised
-- steps from Step's phase 0, where the leg's own clock is exact.
function E.SetMoving(e, moving)
  moving = moving and true or false
  if moving == e.moving then return end
  e.moving = moving
  if e.cfg.footwork == "key" then return end
  if moving then
    e.movingSince = e.t
  elseif e.movingSince then
    if running(e) then emit(e, { t = e.t, kind = "move", t0 = e.movingSince, t1 = e.t }) end
    e.movingSince = nil
  end
end

-- Fire the shot the grid has already earned, at its own instant. Called from
-- the tick AND from every path that disarms auto-repeat (a step into melee,
-- /startattack) so the arrow is away before the cancel lands: a shot whose
-- moment passed before the edge the tick only noticed later is never erased.
-- Out of range nothing fires — the grid keeps running underneath.
local function fireDue(e, upTo)
  if not (e.repeating and e.windupAt and e.canShoot) then return end
  -- The moment stamped when the wind-up started: a haste change landing INSIDE
  -- the wind-up rewrites e.windup for the NEXT cycle, but never moves a shot
  -- already on the grid (the published bar shows the stamped moment too).
  local shotAt = e.windupShotAt or (e.windupAt + e.windup)
  if upTo < shotAt then return end
  -- Measured against the grid this shot belongs to, which a re-arm never
  -- moves: what the weave cost, whether from the retry grid, a fresh wind-up
  -- after a held shot, or waiting to be back in range.
  -- No grid yet (first arm of the fight): nothing to be late against.
  local delay = (e.gridShotAt > 0) and (shotAt - e.gridShotAt) or 0
  if delay < 0 then delay = 0 end
  emit(e, { t = shotAt, kind = "auto", delay = delay, windupAt = e.windupAt,
            cause = (delay > 0) and (e.rearmCause or "cast") or nil })
  rollCrit(e, shotAt, e.cfg.critRanged)
  e.rearmCause = nil
  e.lastShotAt, e.lastAutoDelay = shotAt, delay
  e.nextShotAt = shotAt + e.cycle
  e.gridShotAt = e.nextShotAt
  e.windupAt, e.windupShotAt = nil, nil
  if e.cfg.quickShots and rng(e) < e.cfg.qsChance then E.Proc(e, "QS", true, shotAt) end
end

-- Was the hunter in melee at client time tm? The engine keeps the LAST melee
-- interval (enteredMeleeAt .. leftMeleeAt, open while inMelee). Presses reach
-- the server cfg.latency late, and so does the position the server judges
-- them against — a hit is checked at its server moment MINUS latency, so a
-- fast weave-on-the-way-out (poke, Raptor, backpedal out inside the latency)
-- connects exactly as it does live, instead of finding the hunter already gone.
local function inMeleeAt(e, tm)
  local a = e.enteredMeleeAt
  if not a or tm < a then return false end
  if e.inMelee then return true end
  return e.leftMeleeAt ~= nil and tm <= e.leftMeleeAt
end

-- Land the melee hit the swing has already earned, at its own instant. Same
-- reason as fireDue: the up edge's /stopattack must not cancel a hit whose
-- moment had already passed. Raptor replaces the white hit when queued and off
-- cooldown; either way the swing consumes the queue.
local function meleeDue(e, upTo)
  if not e.meleeOn then return end
  local lat = e.cfg.latency or 0
  local at = e.meleeReadyAt
  if e.meleeRecheckAt > at then at = e.meleeRecheckAt end
  if e.enteredMeleeAt and e.enteredMeleeAt + lat > at then at = e.enteredMeleeAt + lat end
  if upTo < at then return end
  if not inMeleeAt(e, at - lat) then return end
  local hit = "w"
  if e.raptorQueued and e.raptorReadyAt <= at then
    hit = "r"
    e.raptorReadyAt = at + e.cfg.raptorCd
  end
  e.raptorQueued = false
  emit(e, { t = at, kind = "melee", hit = hit })
  rollCrit(e, at, e.cfg.critMelee)
  if e.legs and not e.legs.hitAt then e.legs.hitAt, e.legs.hit = at, hit end
  e.meleeReadyAt = at + e.meleeCycle
  e.meleeRecheckAt = at + e.cfg.meleeRetryPulse   -- next white hit waits for the pulse again
end

-- The weave is over once you can shoot again (or at release if you never
-- left the shooting ring). Legs are seconds; nil = that leg never happened.
-- Written into the hold's own table, which is what the event carries.
local function finishLegs(e, at)
  local L = e.legs
  if not L or L.done then return end
  L.done = true
  L.outAt = L.outAt or at
  L.stepIn  = L.inAt  and (L.inAt - L.downAt) or nil
  L.dwell   = (L.inAt and L.hitAt) and (L.hitAt - L.inAt) or nil
  L.stepOut = (L.hitAt and L.outAt) and (L.outAt - L.hitAt) or nil
  L.total   = L.outAt - L.downAt
  emit(e, { t = at, kind = "weave", edge = "done", legs = L })
  -- Reported and released: the event owns that table now, so nothing this hold
  -- does afterwards (backing off to hold range, the next hit) can rewrite it.
  -- A new down edge builds a fresh one.
  e.legs = nil
end

-- The grader's running estimate of what a full weave costs, in seconds. Drives
-- the opportunity window: no point starting one that cannot finish in time.
function E.SetLegsNeeded(e, s)
  e.legsNeeded = s
end

-- RangeFinder:Refresh's zone ladder, on yards instead of probes. Fine-grained
-- codes; the glue maps them to the legacy TOO_CLOSE/SWEET/TOO_FAR/OUT names and
-- the P_* anchors it exports.
local function zoneOf(inMelee, canShoot, nearRing)
  if inMelee and canShoot then return "SWEET" end
  if inMelee then return "DEEP" end
  if canShoot and nearRing then return "WEAVE" end
  if canShoot then return "FAR" end
  if nearRing then return "GAP" end
  return "OUT"
end

function E.SetSpeed(e, yps)
  e.speed = yps or 0
end

-- Speed-only footwork: no target position, no facing — the same speed-sign
-- dead reckoning the live glide uses. Running (above dirSplit) closes,
-- backpedalling retreats, standing holds — nothing moves you but your keys,
-- so the bar stops the instant you do. Finding the pixel is yours: creep
-- until the thumb sits on the melee divider, then a tap is in and a tap is
-- out. (A settle that eased you onto a pixel when you stopped was tried and
-- dropped: it read as the bar drifting after the step-out, and it undid
-- short taps.)
-- `runSpeed` is GetUnitSpeed's second return: the split between running and
-- backpedalling scales with it, so a speed bonus (boots, Cheetah, Pathfinding)
-- cannot push a backpedal over a fixed 4.5 yd/s and read as closing.
function E.Reckon(e, speed, dt, runSpeed)
  local c = e.cfg
  if runSpeed and runSpeed > 0 then e.dirSplit = runSpeed * c.dirFrac else e.dirSplit = c.dirSplit end
  E.SetSpeed(e, speed)
  local d = e.dist
  if speed > c.stillSpeed then
    local dir = (speed > e.dirSplit) and -1 or 1
    d = d + dir * speed * (dt or 0)
    if d < 0.5 then d = 0.5 end
    if d > 40 then d = 40 end
  end
  E.SetDistance(e, d)
end

-- Advance the engine's clock WITHOUT stepping it. SetDistance stamps its edges
-- (enteredMeleeAt, the leg times) with e.t, so a caller that samples footwork
-- before Step would otherwise date this frame's melee entry to the previous
-- tick. Call it first, then SetDistance, then Step.
function E.SetNow(e, t)
  e.t = t
end

-- Distance to the virtual target. Recomputes the zone; the melee rising edge
-- only PAUSES the ranged auto (too close to shoot: the wind-up aborts, the
-- auto stays armed and resumes when back in range — only /startattack
-- switches the auto to melee; user-verified, an earlier "stepping in kills
-- !Auto Shot" rule blanked the bar and the weave lane on every creep-in)
-- and starts the server's melee re-check clock.
function E.SetDistance(e, d)
  e.dist = d
  local c = e.cfg
  local inMelee  = d <= c.meleeRange
  local canShoot = d >= c.shootMin and d <= c.shootMax
  local nearRing = d <= c.weaveRing
  local zone = zoneOf(inMelee, canShoot, nearRing)
  local L = e.legs
  -- Backpedal: moving, but slower than a run. Read BEFORE the leg stamps below,
  -- so "not yet in melee" describes the leg this move belongs to — and never on
  -- a hold already reported, whose table the `done` event now owns.
  if L and not L.done and e.speed > c.stillSpeed and e.speed <= (e.dirSplit or c.dirSplit) then
    if not L.inAt then L.backIn = true
    elseif L.hitAt then L.backOut = true end
  end
  if inMelee and not e.inMelee then
    fireDue(e, e.t)          -- a shot already earned is away before the cancel
    -- The server learns of the step-in cfg.latency later; its re-check pulse
    -- (or the poke's immediate check) runs from that moment.
    local lat = c.latency or 0
    e.enteredMeleeAt, e.leftMeleeAt = e.t, nil
    e.meleeRecheckAt = e.poked and (e.t + lat) or (e.t + lat + c.meleeRetryPulse)
    e.windupAt, e.windupShotAt, e.rearmCause = nil, nil, nil
    if L and not L.inAt then L.inAt = e.t end
  elseif e.inMelee and not inMelee then
    e.leftMeleeAt = e.t
    e.deadzoned = false
  end
  if canShoot and not e.canShoot then
    -- Back in range. The grid kept recharging while you could not shoot, so a
    -- wind-up whose moment has already passed starts fresh from here — the
    -- held-shot rule again, with the range to blame for the delay.
    if e.repeating and not e.windupAt and (e.nextShotAt - e.windup) < e.t then
      e.nextShotAt = e.t + e.windup
      e.rearmCause = "range"
    end
    if L and not L.done then
      if L.hitAt and not L.outAt then L.outAt = e.t end
      -- Released already? The weave ends here, at the moment shooting came
      -- back — with or without a hit (a hitless hold is still a weave).
      if e.weaveDownAt == nil then finishLegs(e, e.t) end
    end
  end
  e.inMelee, e.canShoot, e.nearRing = inMelee, canShoot, nearRing
  if zone ~= e.zone then
    e.zone = zone
    -- Armed but not pulled: the zone is recorded, the event deferred — pull()
    -- emits the zone you actually opened in, after the `pull` itself.
    if running(e) then emit(e, { t = e.t, kind = "range", zone = zone, inMelee = inMelee }) end
  end
end

-- Start the wind-up if the grid says it is due and nothing blocks it. Exact
-- moment: the grid's wind-up start, pushed to the end of a cast that was in
-- flight (the clip). Called from Step() and from arm() so a press that arms
-- auto starts winding up inside that same press — a Steady on the same macro
-- line then queues behind the shot instead of clipping it.
local function tryWindup(e, at)
  if e.windupAt or e.cast or not e.repeating or not e.canShoot then return end
  local want = e.nextShotAt - e.windup
  local start = (e.castEndAt > want) and e.castEndAt or want
  if at >= start then e.windupAt, e.windupShotAt = start, start + e.windup end
end

-- Arm auto-repeat. If the grid's wind-up moment is already past, a fresh
-- wind-up starts now (spec: re-arm rule, "rearmWindupAfterReady"); a cast in
-- flight pushes the first shot behind its end instead of being clipped by it.
local function arm(e, at, rearm)
  if e.repeating then return end
  e.repeating = true
  e.meleeOn = false                         -- "!Auto Shot" switches the auto to ranged
  local base = at
  if e.cast and e.cast.t1 > base then base = e.cast.t1 end
  local want = e.nextShotAt - e.windup
  e.rearmCost = 0
  if want < base then
    -- Swing ready (or a cast in the way): a fresh wind-up from here — what the
    -- client appears to do. `rearmWindupAfterReady` is the calibration knob for
    -- the other reading: with it off the held shot is already wound up and goes
    -- out at the release itself (windupAt back-dated so fireDue emits at base).
    -- Either way the delay is measured against the grid this shot left.
    if rearm then e.rearmCause = "rearm" end
    if rearm and not e.cfg.rearmWindupAfterReady then
      e.nextShotAt = base
      e.windupAt, e.windupShotAt = base - e.windup, base
    else
      e.nextShotAt = base + e.windup
    end
  elseif rearm and e.cfg.releaseCost then
    -- Still recharging: the client re-checks on the retry pulse from the
    -- press, so the shot slips to the first check after ready.
    local rem = e.nextShotAt - at
    local cost = e.cfg.releaseCost(rem, e.cfg.rearmPulse)
    if cost > 0 then
      e.rearmCost = cost
      e.rearmCause = "rearm"
      e.nextShotAt = e.nextShotAt + cost
    end
  end
  -- A re-arm never moves the grid it left: the delay it reports is the time
  -- lost against that grid. Any other arm (the pull) IS the new grid.
  if not rearm then e.gridShotAt = e.nextShotAt end
  tryWindup(e, at)
end

-- Context snapshot attached to press/free events so the grader can judge a
-- decision with the numbers the player had at that moment.
local function ctx(e, at)
  -- NO GRID, NO DEADLINE. `nextShotAt` is 0 until the first arm, and the pull is
  -- exactly that moment: `apply` runs the cast BEFORE the "/cast !Auto Shot" that
  -- forms the grid, so the opener's own press was measured against a wind-up that
  -- does not exist and came out at minus the whole clock. The grader read that as
  -- "a Steady that will not fit before the wind-up" and billed the first press of
  -- every single fight a red STEADY WON'T FIT. Same idiom as the weave budget in
  -- Step's phase 1: no grid means nothing to be late against.
  local ttw = (e.nextShotAt > 0) and ((e.nextShotAt - e.windup) - at) or math.huge
  return {
    ttw = ttw,                                     -- time to wind-up start (<0 = running)
    inWindup = e.windupAt ~= nil,
    cycle = e.cycle,
    steadyCast = castTimeOf(e, "steady"),
    multiCast  = castTimeOf(e, "multi"),
    msReady  = e.cdReady.MS  <= at,
    arcReady = e.cdReady.Arc <= at,
  }
end

local function busyUntil(e)
  local b = e.gcdEnd
  if e.cast and e.cast.t1 > b then b = e.cast.t1 end
  return b
end

-- `queuedFrom` is the moment the player actually PRESSED, when the client held
-- the cast and started it here instead (the wind-up, or the queue window before
-- the GCD ends). It rides all the way out on the `cast` event: the grader has
-- to know who chose the start — the queue window is free, so a cast the CLIENT
-- started on the player's behalf is on the beat by definition.
local function startCast(e, spell, at, queuedFrom)
  local castTime = castTimeOf(e, spell)
  e.gcdStart, e.gcdEnd = at, at + e.cfg.gcd
  -- Who owns the running GCD. Mashing THAT spell is how the client is meant to
  -- be played, so a press of it in the gap between the cast ending and the
  -- queue window opening is tagged `mash` and costs the player nothing.
  e.gcdSpell = spell
  if castTime > 0 then
    e.cast = { spell = spell, t0 = at, t1 = at + castTime, queuedFrom = queuedFrom }
  else
    -- An instant blocks nothing: castEndAt is the clip rule for CASTS and
    -- stays where it was, so the wind-up is never pushed by an Arcane.
    emit(e, { t = at, kind = "cast", spell = spell, t0 = at, t1 = at, queuedFrom = queuedFrom })
    rollCrit(e, at, e.cfg.critRanged)
    local key = CD_KEY[spell]
    if key then e.cdReady[key] = at + cdFor(e, key) end
  end
end

local function tryCast(e, spell, at)
  local c = ctx(e, at)
  if (spell == "steady" or spell == "multi") and e.moving then
    emit(e, { t = at, kind = "press", key = spell, result = "moving", ctx = c })
    return
  end
  local key = CD_KEY[spell]
  if key and e.cdReady[key] > at then
    emit(e, { t = at, kind = "press", key = spell, result = "cooldown", ctx = c })
    return
  end
  -- Mashing the spell that is already casting or queued is how the client is
  -- meant to be played (the queue guarantees the cast). Not a press at all.
  -- The cast half must also check currency (t1 > at): Step() applies pending
  -- presses (phase 1) before it clears a completed cast (phase 2), so a
  -- same-spell press landing in the same Step as that cast's completion would
  -- otherwise see the stale e.cast and be swallowed instead of graded.
  if (e.cast and e.cast.spell == spell and e.cast.t1 > at) or (e.queued and e.queued.spell == spell) then
    return
  end
  local busy = busyUntil(e)
  if e.windupAt and castTimeOf(e, spell) > 0 then
    -- Inside the wind-up the client holds a CAST until the arrow is away:
    -- queued, free (Nock.ClipQueueEdge). An instant fires regardless of the
    -- timer and leaves the shot alone (user-verified: Arcane always fires).
    local shotAt = e.windupShotAt or (e.windupAt + e.windup)
    if shotAt > busy then busy = shotAt end
  end
  if busy > at then
    if e.windupAt or (busy - at) <= e.cfg.queueWindow then
      if e.queued then
        emit(e, { t = at, kind = "press", key = e.queued.spell, result = "replaced", ctx = c })
      end
      e.queued = { spell = spell, at = at }
      emit(e, { t = at, kind = "press", key = spell, result = "queued", ctx = c })
    else
      emit(e, { t = at, kind = "press", key = spell, result = "notready", ctx = c,
                mash = (e.gcdSpell == spell) })
    end
    return
  end
  emit(e, { t = at, kind = "press", key = spell, result = "ok", ctx = c })
  startCast(e, spell, at)
end

local EMPTY_ACTIONS = {}
local function apply(e, actions, at, edge)
  actions = actions or EMPTY_ACTIONS
  for i = 1, #actions do
    local a = actions[i]
    if a == "autoshot" then
      -- "/cast !Auto Shot" on the weave key's up edge is the re-arm: it pays
      -- the retry grid when the swing is still recharging.
      arm(e, at, edge == "up")
    elseif a == "stopcasting" then
      if e.cast then
        emit(e, { t = at, kind = "cast", spell = e.cast.spell, t0 = e.cast.t0, t1 = at, cancelled = true })
        e.cast, e.castEndAt = nil, at
      end
    elseif a == "raptor" then
      e.raptorQueued = true
    elseif a == "startattack" then
      -- Range-aware, as live (a "/startattack + Arcane Shot" macro keeps the
      -- autos going at range): inside melee reach it starts the MELEE auto —
      -- the weave's mode switch, swinging at once since the server checks
      -- range as it starts attacking (the re-check pulse only applies when
      -- the attack was started from outside and the hunter walked in). At
      -- range it starts Auto Shot, an arm that never re-bases a running grid.
      if inMeleeAt(e, at - (e.cfg.latency or 0)) then
        e.meleeOn = true
        fireDue(e, at)                            -- an earned shot is away first
        e.repeating, e.windupAt, e.windupShotAt = false, nil, nil  -- the auto is melee now
        e.rearmCause = nil
        e.meleeRecheckAt = at
      elseif e.weaveDownAt then
        -- Held key, still outside: melee attack started from range — it lands
        -- after the re-check pulse once the hunter steps in.
        e.meleeOn = true
        fireDue(e, at)
        e.repeating, e.windupAt, e.windupShotAt = false, nil, nil
        e.rearmCause = nil
      else
        arm(e, at, true)
      end
    elseif a == "stopattack" then
      e.meleeOn, e.raptorQueued = false, false
    elseif a == "snowball" then
      e.poked = true
      -- Poke while already in (as the server sees it): re-check now.
      if inMeleeAt(e, at - (e.cfg.latency or 0)) then e.meleeRecheckAt = at end
    elseif a == "killcommand" then
      -- Instant, off the GCD, only inside a crit window and off cooldown,
      -- and never while a cast or the wind-up runs. Otherwise silent: mashing
      -- the Steady macro is the technique, never a fault.
      if e.kcUntil > at and e.cdReady.KC <= at and not e.cast and not e.windupAt then
        e.cdReady.KC = at + e.cfg.cooldowns.KC
        emit(e, { t = at, kind = "kc", used = true })
      end
    elseif CD_ACTION[a] then
      -- Off-GCD cooldown presses. Haste from RF/Drums/Pot; Spec (Bestial
      -- Wrath) and trinkets are cooldown events only (their stats vary).
      local key = CD_ACTION[a]
      if e.cdReady[key] <= at then
        e.cdReady[key] = at + e.cfg.cooldowns[key]
        emit(e, { t = at, kind = "cd", key = key, used = true })
        if a == "rf" then E.Proc(e, "RF", true, at)
        elseif a == "drums" then E.Proc(e, "Drums", true, at)
        elseif a == "pot" then E.Proc(e, "Pot", true, at) end
      else
        emit(e, { t = at, kind = "cd", key = key, used = false })
      end
    elseif CAST_BASE[a] then
      -- Cast first, then arm: "/cast Steady Shot" above "/cast !Auto Shot"
      -- starts the cast and the grid forms behind it (no clip on the pull).
      tryCast(e, a, at)
      -- A shot press starts the auto only when NO auto-attack is running (the
      -- pull). With the melee auto on (a weave hold) it does not switch the
      -- auto back to ranged — only "/cast !Auto Shot" does — so spamming
      -- Arcane mid-hold never re-bases the grid.
      if e.cfg.armOnShot and not e.meleeOn then arm(e, at) end
    end
  end
end

-- Presses are delayed by latency and applied inside Step() in order.
function E.Press(e, actions, t)
  if not e.fightOn then return end
  if e.armed then pull(e, t) end
  e.nPress = e.nPress + 1
  e.nPending = e.nPending + 1
  e.pending[e.nPending] = { at = t + e.cfg.latency, actions = actions }
end

-- The hold-to-weave key. Edges carry the macro body's actions (down or up);
-- the same latency as a press applies. With key-only footwork the engine also
-- walks the hunter in and out for the player (cfg.stepTime per leg).
function E.Weave(e, down, actions, t)
  if not e.fightOn then return end
  if e.armed then pull(e, t) end
  local at = t + e.cfg.latency
  e.nPress = e.nPress + 1
  e.nWeave = (e.nWeave or 0) + 1
  e.nPending = e.nPending + 1
  e.pending[e.nPending] = { at = at, actions = actions, edge = down and "down" or "up" }
  if e.cfg.footwork == "key" then
    e.nPendingMove = e.nPendingMove + 1
    e.pendingMove[e.nPendingMove] = { at = at + e.cfg.stepTime,
                                      dist = down and (e.cfg.meleeRange - 1) or e.cfg.startDistance }
  end
end

-- Time is absolute seconds on the caller's clock. Every timer is an exact
-- moment, never "this tick": a cast that ends at t1 starts the wind-up at t1
-- even when Step() only notices a frame later.
function E.Step(e, t)
  e.t = t
  if not e.fightOn then return end

  -- 0. Key-only footwork: the synthesised step lands on its own clock, so the
  --    leg stamps are exact rather than "whenever the tick noticed".
  local i = 1
  while i <= e.nPendingMove do
    local m = e.pendingMove[i]
    if m.at <= t then
      e.t = m.at
      E.SetDistance(e, m.dist)
      -- The synthesised leg, filed as the MOVE span it stands for.
      if running(e) then emit(e, { t = m.at, kind = "move", t0 = m.at - e.cfg.stepTime, t1 = m.at, key = true }) end
      e.t = t
      table.remove(e.pendingMove, i)
      e.nPendingMove = e.nPendingMove - 1
    else
      i = i + 1
    end
  end

  -- 0a. Armed, not pulled: the fight has no clock yet. Range and footwork are
  --     tracked (phase 0 above, and the caller's SetDistance), and nothing
  --     else runs — no autos, no scenario script, no auto-stop, and not one
  --     RNG draw, so the seeded fight still replays identically however long
  --     you leave the panel sitting on Start.
  if e.armed then return end

  -- 0b. Procs expire at their own instant, earliest first. A fixed-order,
  --     repeated min-scan (six entries, no allocation) instead of pairs():
  --     pairs() has no defined order, so two procs expiring in the same tick
  --     could otherwise emit out of chronological order.
  while true do
    local best, bestAt
    for j = 1, #PROC_ORDER do
      local name = PROC_ORDER[j]
      local untilT = e.procs[name]
      if untilT > 0 and untilT <= t and not (e.hold and e.hold[name]) and (not best or untilT < bestAt) then
        best, bestAt = name, untilT
      end
    end
    if not best then break end
    E.Proc(e, best, false, bestAt)
  end

  -- 0c. Scenario script: procs at their scripted moments; the fight ends at len.
  --     A scripted event past len still fires — `end` is a signal the glue
  --     acts on (report, stop the fight), not a hard stop on playback.
  local sc = e.scenario
  if sc then
    while sc.events[e.scriptI] and e.t0 + sc.events[e.scriptI].t <= t do
      local ev = sc.events[e.scriptI]
      E.Proc(e, ev.proc, true, e.t0 + ev.t)
      e.scriptI = e.scriptI + 1
    end
  end
  -- The auto-stop, OUTSIDE the scenario block: a fight can be capped by its
  -- caller (a ladder drill's own len) with no script behind it at all. e.len
  -- wins where both exist -- it is the more specific statement, made per fight.
  local lim = e.len or (sc and sc.len)
  if lim and not e.ended and t - e.t0 >= lim then
    e.ended = true
    emit(e, { t = e.t0 + lim, kind = "end" })
  end

  -- 1. Presses whose latency has elapsed.
  i = 1
  while i <= e.nPending do
    local p = e.pending[i]
    if p.at <= t then
      if p.edge == "down" then
        -- A hold that never closed (released out of range, no shot regained)
        -- is closed by its successor rather than left dangling.
        if e.legs and not e.legs.done then finishLegs(e, p.at) end
        e.weaveDownAt, e.poked, e.rearmCost = p.at, false, 0
        -- Budget = time until the auto's wind-up wants to start. No grid yet
        -- (a hold before the first auto) means no budget to overrun.
        local budget = (e.nextShotAt > 0) and ((e.nextShotAt - e.windup) - p.at) or math.huge
        e.legs = { downAt = p.at, budget = budget, backIn = false, backOut = false }
        -- Already inside (weave on the way out): the step-in leg is zero and
        -- the dwell runs from the key.
        if e.inMelee then e.legs.inAt = p.at end
        emit(e, { t = p.at, kind = "weave", edge = "down" })
      elseif p.edge == "up" then
        meleeDue(e, p.at)      -- a hit already earned lands before /stopattack
      end
      apply(e, p.actions, p.at, p.edge)
      if p.edge == "up" then
        emit(e, { t = p.at, kind = "weave", edge = "up", cost = e.rearmCost })
        e.weaveDownAt = nil
        local L = e.legs
        if L and not L.done and e.canShoot then finishLegs(e, p.at) end
      end
      table.remove(e.pending, i)
      e.nPending = e.nPending - 1
    else
      i = i + 1
    end
  end

  -- 2. Cast completion.
  if e.cast and t >= e.cast.t1 then
    local c = e.cast
    emit(e, { t = c.t1, kind = "cast", spell = c.spell, t0 = c.t0, t1 = c.t1,
              queuedFrom = c.queuedFrom })
    rollCrit(e, c.t1, e.cfg.critRanged)
    local key = CD_KEY[c.spell]
    if key then e.cdReady[key] = c.t1 + cdFor(e, key) end
    e.cast, e.castEndAt = nil, c.t1
  end

  -- 3. The wind-up and the shot. The wind-up wants to start at grid - windup;
  --    a cast in flight pushes it to the cast's end (the clip).
  if e.repeating then
    tryWindup(e, t)
    fireDue(e, t)
  end

  -- 3b. Melee. A hit lands when melee auto is on, you were in melee as the
  --     server saw it (client position, latency ago), the swing timer is ready
  --     and the server has re-checked (the pulse after stepping in, or at once
  --     if the hold carried the Snowball poke). Raptor replaces the white hit
  --     when queued and off cooldown. Exact moment: the latest of the clocks.
  meleeDue(e, t)

  -- 3c. Weave opportunity: melee swing ready, nothing casting, and the auto
  --     far enough away for a full weave (legsNeeded). Being in melee does NOT
  --     close it — stepping in before the key is the weave-on-the-way-out
  --     style, and the window closing on the step would grade every such
  --     weave as missed. The key (down edge) or the hit consuming the swing
  --     closes it. Edge events only; the grader times the window.
  local ttw = (e.nextShotAt - e.windup) - t
  local open = e.cast == nil and e.meleeReadyAt <= t and ttw >= e.legsNeeded
    and e.weaveDownAt == nil
  if open ~= e.oppOpen then
    e.oppOpen = open
    local at = t
    if open and e.lastShotAt > 0 and e.meleeReadyAt <= e.lastShotAt and t - e.lastShotAt < 0.05 then at = e.lastShotAt end
    if not open and e.meleeReadyAt <= t then
      local closeAt = (e.nextShotAt - e.windup) - e.legsNeeded
      if closeAt < t and closeAt > t - 0.05 then at = closeAt end
    end
    emit(e, { t = at, kind = "opp", open = open, ttw = ttw })
  end
  -- Dead zone: still in melee when the auto's wind-up wanted to start — from
  --     here every moment inside costs ranged time. (Not "once a Steady no
  --     longer fits": the way-out weave is made exactly in that gap.)
  if e.inMelee and not e.deadzoned and ttw <= 0 and e.nextShotAt > 0 then
    e.deadzoned = true
    emit(e, { t = e.nextShotAt - e.windup, kind = "deadzone" })
  end

  -- 4. The queued press fires the moment everything is free.
  if e.queued then
    local at = busyUntil(e)
    if e.queued.at > at then at = e.queued.at end
    if e.lastShotAt > at and e.queued.at < e.lastShotAt then at = e.lastShotAt end
    if t >= at and not e.cast and not e.windupAt then
      local q = e.queued
      e.queued = nil
      emit(e, { t = at, kind = "press", key = q.spell, result = "ok", ctx = ctx(e, at), queuedFrom = q.at })
      startCast(e, q.spell, at, q.at)
    end
  end

  -- 5. The GCD's owner is forgotten once it has run out. Cleared at the END of
  --    the step so a press applied in phase 1 (whose `at` may be earlier than
  --    `t`) still sees the spell that owned the GCD at its own moment.
  if t >= e.gcdEnd then e.gcdSpell = nil end

  -- 6. Busy -> free edge, for the grader's LATE verdict.
  local busy = e.cast ~= nil or t < e.gcdEnd
  if e.wasBusy and not busy then
    local freeAt = busyUntil(e)
    emit(e, { t = freeAt, kind = "free", ctx = ctx(e, freeAt) })
  end
  e.wasBusy = busy
end

-- WHEN NEXT, AND HOW MUCH ROOM (R5c). `oppOpen` answers "may I go RIGHT NOW",
-- which is the wrong question for anything drawn ahead of the cursor: the views
-- want the next window a weave can actually be made in, and they want it before
-- it opens. Same three ingredients the opportunity test uses — the melee swing
-- being up, nothing casting, and room before a wind-up — walked FORWARD over
-- the shot grid instead of tested at one moment.
--
-- The fallback is the point of the loop. `legsNeeded` is the player's own
-- measured footwork fed back from the grader, and at a fast weapon speed one
-- slow weave can put it past every gap the rotation has (eWS 0.90 leaves 0.75 s
-- between a release and the next wind-up; a 1.06 s weave fits in none of them).
-- The opportunity flag then never goes true again, which drew nothing at all
-- while the paper went on writing a `w` every 3.7 s. So when no cycle can hold
-- a whole weave, this answers with the ROOMIEST window there is: still the
-- engine's truth, and a window the player can see is too tight rather than a
-- lane that has gone quiet.
--
-- Returns openAt, room, fits — or nil before there is a grid to hang any of it
-- on. `fits` is false for exactly that fallback: the window is the roomiest
-- there is and a whole weave does not go in it, which the views must be able to
-- say out loud rather than draw as an invitation.
-- Pure: reads the engine, writes nothing, allocates nothing.
local WEAVE_LOOKAHEAD = 8
function E.WeaveWindow(e, at)
  local cyc, wu = e.cycle, e.windup
  if not (e.nextShotAt and e.nextShotAt > 0 and cyc and cyc > 0) then return nil end
  at = at or e.t
  local ready = at
  if e.meleeReadyAt > ready then ready = e.meleeReadyAt end
  -- A cast in flight closes the window as surely as a recharging swing does
  -- (the opportunity test spells it `e.cast == nil`): you cannot walk out of a
  -- Steady, and stepping in cancels it.
  if e.cast and e.cast.t1 > ready then ready = e.cast.t1 end
  local need = e.legsNeeded or 0
  local ws = e.nextShotAt - wu
  local best, bestRoom
  for _ = 1, WEAVE_LOOKAHEAD do
    -- The release that opened the cycle this wind-up closes: the earliest a
    -- weave in it can start.
    local rel = ws + wu - cyc
    local open = (ready > rel) and ready or rel
    local room = ws - open
    if room > 0 then
      if not bestRoom or room > bestRoom then best, bestRoom = open, room end
      if room >= need then return open, room, true end
    end
    ws = ws + cyc
  end
  if not best then return nil end
  return best, bestRoom, false
end

function E.Snapshot(e, out)
  -- Has the fight actually begun? The panel's chip (ARMED vs FIGHT m:ss), the
  -- conveyor's pre-pull freeze and the review all hang off this rather than off
  -- fightOn, which is true from the moment Start is pressed.
  out.armed       = e.armed
  out.pulled      = e.pulled
  out.t0          = e.t0
  out.rangedMul   = e.rangedMul
  out.cycle       = e.cycle
  out.windup      = e.windup
  out.repeating   = e.repeating
  -- The GRID, never the pushed shot: during a clip the live bar fills to the
  -- grid and sits full ("held shot") until the late shot fires and re-anchors
  -- it. Reporting castEnd + windup here re-anchored the bar the moment the
  -- clipping cast began — a visible jump back of the whole overlap. (The bar
  -- stays drawn while full because Nock.AutoSwingLive treats a practice fight
  -- as combat.) The wind-up's own timing still goes out via windupAt.
  out.nextShotAt  = e.nextShotAt
  out.windupAt    = e.windupAt
  -- The moment this wind-up will fire at, stamped when it started: a haste
  -- change mid-wind-up rewrites out.windup for the next cycle, so the cast
  -- bar's end must come from here, not from windupAt + windup.
  out.windupShotAt = e.windupShotAt
  out.lastAutoDelay = e.lastAutoDelay
  -- The last shot that actually went out: the anchor the conveyor projects the
  -- paper rotation forward from.
  out.lastShotAt  = e.lastShotAt
  out.gcdStart    = e.gcdStart
  out.gcdDur      = (e.t < e.gcdEnd) and e.cfg.gcd or 0
  out.cast        = e.cast
  out.msReadyAt   = e.cdReady.MS
  out.arcReadyAt  = e.cdReady.Arc
  out.meleeCycle, out.meleeReadyAt, out.meleeOn = e.meleeCycle, e.meleeReadyAt, e.meleeOn
  -- The next window a weave can actually be made in, its room, and whether a
  -- whole weave fits in it (E.WeaveWindow): what the conveyor's gap band and the
  -- metronome's gap tick are drawn from.
  out.weaveAt, out.weaveRoom, out.weaveFits = E.WeaveWindow(e, e.t)
  out.raptorReadyAt, out.raptorQueued = e.raptorReadyAt, e.raptorQueued
  out.zone, out.inMelee, out.canShoot, out.dist = e.zone, e.inMelee, e.canShoot, e.dist
  out.weaveDownAt = e.weaveDownAt
  out.movingSince = e.movingSince
  out.meleeMul    = e.meleeMul
  out.procs       = e.procs
  out.cdReady     = e.cdReady
  out.quickShotsOn = e.cfg.quickShots
  out.kcReadyAt, out.kcUntil = e.cdReady.KC, e.kcUntil
  return out
end

-- Macro body -> sim actions. One action per /cast, /use or /castsequence line
-- (first step), plus /stopcasting. Conditionals in brackets are stripped;
-- phase 3 replaces that with WeaveBind's garment resolver. Lines naming
-- nothing the sim knows land in `unknown` so the panel can show them.
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

function E.ParseMacro(body, names, out, unknown)
  for line in (body or ""):gmatch("[^\r\n]+") do
    line = trim(line)
    local cmd, rest = line:match("^(/%a+)%s*(.*)$")
    if cmd then
      cmd = cmd:lower()
      if cmd == "/stopcasting" then
        out[#out + 1] = "stopcasting"
      elseif cmd == "/startattack" then
        out[#out + 1] = "startattack"
      elseif cmd == "/stopattack" then
        out[#out + 1] = "stopattack"
      elseif cmd == "/cast" or cmd == "/use" or cmd == "/castsequence" then
        rest = rest:gsub("%b[]", "")           -- drop every [conditional]
        rest = rest:gsub("%b()", "")           -- and every (Rank N) qualifier
        if cmd == "/castsequence" then
          rest = rest:gsub("^%s*reset=%S+", "")
          rest = rest:match("^[^,]*") or rest   -- first step
        end
        rest = trim(rest):gsub("^!", ""):lower()
        if cmd == "/use" and (rest == "13" or rest == "14") then
          out[#out + 1] = (rest == "13") and "t1" or "t2"
          rest = ""
        end
        -- "!Auto-Shot" is the same press as "!Auto Shot": a hyphen where the
        -- client's own name has a space is the commonest hand-typed spelling,
        -- and it must not cost the slot its key. The fallback can only ever
        -- reach a name the caller already listed, and the exact form wins
        -- first, so a genuinely hyphenated name (Multi-Shot) is unaffected.
        local action = names[rest] or names[(rest:gsub("%-", " "))]
        if action then
          out[#out + 1] = action
        elseif rest ~= "" then
          unknown[#unknown + 1] = line
        end
      end
    end
  end
  return out
end

-- A typed key -> the exact form GetBindingKey returns, so a hand-entered
-- override can be compared with (and bound like) a detected one. Pure, so it
-- lives here rather than in Modules/Practice.lua (which delegates to it):
--   * "+" separators become "-", surrounding space goes, everything uppercases
--   * modifiers are re-ordered into the client's canonical ALT-CTRL-SHIFT-<key>
--     ("SHIFT-CTRL-F" is what a user types; "CTRL-SHIFT-F" is what the client
--     stores, and a mismatch silently binds nothing)
--   * "MOUSE4"/"MOUSE5" become "BUTTON4"/"BUTTON5", the client's own spelling
function E.NormalizeKey(s)
  s = (s or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%+", "-"):upper()
  if s == "" then return s end
  local alt, ctrl, shift = false, false, false
  local key = s
  while true do
    local mod, rest = key:match("^(%a+)%-(.+)$")
    if mod == "ALT" then alt, key = true, rest
    elseif mod == "CTRL" then ctrl, key = true, rest
    elseif mod == "SHIFT" then shift, key = true, rest
    else break end
  end
  key = key:gsub("^MOUSE(%d)$", "BUTTON%1")
  return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. key
end

-- Scenario DSL (spec "Scenarios"), one per line:
--   Name: rf@5 lust@20 drums@20 dst@30 pot@21 qs@5 ews=2.17 lock=5:5:1:1 len=90 qs=off kc=on
-- -> { name, events = { {t=5, proc="RF"}, ... } (sorted), ews, lock, len, qs, kc }
-- `qs=off` disables the Quick Shots roll; `lock=<notation>` pins the eWS to
-- that notation (the glue resolves the bracket middle) and implies qs=off.
-- `kc=on` keeps the crit roll (Kill Command windows) on a locked paper, which
-- otherwise rolls none (Practice:StartFight).
local PROC_TOKEN = { rf = "RF", lust = "Lust", drums = "Drums", dst = "DST", pot = "Pot", qs = "QS" }
function E.ParseScenario(text)
  local list, errors = {}, {}
  for line in (text or ""):gmatch("[^\r\n]+") do
    line = trim(line)
    if line ~= "" and not line:match("^#") then
      local name, body = line:match("^([^:]+):%s*(.*)$")
      if not name then
        errors[#errors + 1] = "missing ':' in: " .. line
      else
        local sc = { name = trim(name), events = {}, len = 60, qs = true }
        for tok in body:gmatch("%S+") do
          local proc, at = tok:match("^(%a+)@([%d%.]+)$")
          local key, val = tok:match("^(%a+)=(%S+)$")
          if proc and PROC_TOKEN[proc:lower()] then
            -- The token pattern accepts any run of digits and dots, so "rf@1.2.3"
            -- and "rf@." reach here with a nil time. Dropping the event keeps the
            -- sort (and every `e.t0 + ev.t` in Step) off a nil.
            local tv = tonumber(at)
            if tv then
              sc.events[#sc.events + 1] = { t = tv, proc = PROC_TOKEN[proc:lower()] }
            else
              errors[#errors + 1] = "bad time in '" .. tok .. "' in: " .. sc.name
            end
          elseif key == "ews" then sc.ews = tonumber(val)
          elseif key == "lock" then sc.lock = val; sc.qs = false
          elseif key == "kc" then sc.kc = (val == "on")
          elseif key == "len" then
            -- 0 means "never auto-stop" (Free play): no `end` event, ever.
            -- Not the `a and nil or b` idiom: with a nil "then" branch it
            -- falls through to the "else" every time.
            local lv = tonumber(val)
            if lv == 0 then sc.len = nil
            elseif lv then sc.len = lv
            else sc.len = 60 end
          elseif key == "qs" then sc.qs = (val:lower() ~= "off")
          elseif key == "hold" then
            sc.hold = {}
            for name in val:gmatch("[^,]+") do
              local p = PROC_TOKEN[name:lower()]
              if p then sc.hold[p] = true
              else errors[#errors + 1] = "unknown proc '" .. name .. "' in hold= of: " .. sc.name end
            end
          else errors[#errors + 1] = "unknown token '" .. tok .. "' in: " .. sc.name end
        end
        table.sort(sc.events, function(a, b) return a.t < b.t end)
        list[#list + 1] = sc
      end
    end
  end
  return list, errors
end

E.SCENARIOS = E.ParseScenario(table.concat({
  -- len=0 parses to len=nil: the French drill is a rotation to settle into, not
  -- a minute-long clip, so it runs until you stop it.
  "Clean French: len=0",
  "Rapid Fire at 5 s: rf@5",
  "RF + Quick Shots: rf@5 qs@5",
  "Lust + RF + Drums: lust@20 rf@21 drums@20",
  "Raid pull: lust@8 len=60",
}, "\n"))

-- Arm a scenario for the next fight. Events fire at t0 + t inside Step.
--
-- `len` is an optional per-fight auto-stop that overrides the scenario's own,
-- for a caller that owns the length without owning the scenario: a ladder drill
-- caps its attempt at 60 s while the catalog row it loads -- shared with the
-- picker, where the same rotation is meant to run until you stop it -- keeps no
-- len= at all.
function E.LoadScenario(e, sc, len)
  e.scenario = sc
  e.len = len
  -- The SCENARIO's holds (`hold=`), read-only: the palette hides those tiles.
  -- `e.hold` is the fight's own working set -- the scenario's copied in, plus
  -- whatever the player holds by hand (E.Hold) -- and never the scenario's
  -- table itself, which a hand-made hold would otherwise write into.
  e.scHold = sc and sc.hold or nil
  if e.scHold then
    local h = {}
    for k, v in pairs(e.scHold) do h[k] = v end
    e.hold = h
  else
    e.hold = nil
  end
  e.cfg.quickShots = (sc == nil) or (sc.qs ~= false)
end

local Nock = rawget(_G, "Nock")
if Nock then Nock.PracticeEngine = E end
return E
