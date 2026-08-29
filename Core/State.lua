-- Core/State.lua
-- Single source of truth for combat state. Read everywhere; only mutated by event handlers.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

Nock.state = {
  player = {
    inCombat = false,
    -- A REAL cast in progress: { name, spellId, icon, startTime, endTime,
    -- isChannel } or nil. If this is set, the player is locked out — that is the
    -- invariant every consumer depends on, so nothing that merely *looks* like a
    -- cast may be put here. Read it directly; there is no filtering helper to
    -- forget to call.
    casting  = nil,
    -- The Auto Shot wind-up, kept deliberately OUT of `casting`. It is drawn like
    -- a cast but is the opposite of a lockout: it is the window in which a press
    -- is queued for free (see Nock.ClipQueueEdge). It lived in `casting` until
    -- 2026-08-12 and cost us a user-visible bug — the shot bars clip their
    -- windows at the lockout front, so they blanked for the last stretch of every
    -- cycle. Separate fields make that unrepresentable rather than merely
    -- documented. Views merge the two via Nock.CastBarSource.
    autoShotCast = nil,
    aspect   = nil,  -- { name, spellId, icon, expirationTime, duration } or nil
    feign    = nil,  -- { icon, expirationTime, duration } while Feign Death buff is up, else nil
    dazed    = nil,  -- { name, spellId, icon, expirationTime, duration } while Dazed, else nil
    sated    = false,  -- Sated/Exhaustion (post-Bloodlust) debuff on the player (set by Auras; drives noRelease)
    inLust   = false,
    canWeave = false,  -- true if 2H equipped (no offhand weapon)
    -- Ranged-only haste procs that pick the weave AND turret rotation
    -- notations (set by Auras; consumed with inLust by Profiles'
    -- ResolveWeave/ResolveTurret). Both-haste magnitudes are read live from
    -- GetMeleeHaste in the tick.
    rapidFire  = false,  -- Rapid Fire active
    quickShots = false,  -- Improved Aspect of the Hawk proc active
    drums      = false,  -- Drums of Battle active
    manaPct  = 100,
    manaCur  = 0,
    manaMax  = 0,
    healthPct = 100,
    -- The Steam Tonk Controller transform. Written by Modules/Auras.lua
    -- UNCONDITIONALLY — whether to act on it is Modules/TonkGuard.lua's
    -- business, and gating a producer on a behaviour setting is how the
    -- auto-shot cast bar quietly broke the shot bars for half the users.
    -- `since` is the server's application time when the aura reports a
    -- duration; otherwise it is the detection time, which lags by up to Auras'
    -- SCAN_THROTTLE and therefore errs LATE — the safe direction, because
    -- cancelling early is what welds you in place.
    tonk = { active = false, since = nil, name = nil },
  },
  -- What ELSE is bound to the keys Nock claims for itself. Written by
  -- Modules/BindCheck.lua on binding/action-bar events, never per tick —
  -- resolving a binding costs several API calls. The entry always exists;
  -- `conflict` is nil when the key is free. Published unconditionally,
  -- including while the feature is disabled: the Settings note and the warning
  -- square decide for themselves what to show.
  --
  -- Only the weave key remains. The Steam Tonk had a hold key here until 1.0.19,
  -- when PetDismiss made an in-combat exit possible and the hold — a human
  -- finger standing in for a delay the client would not let us enforce — became
  -- pointless. The map is still a map: BindCheck's conflict resolution is
  -- written per-slot, not per-feature.
  binds = {
    -- { key, enabled, ownedByNock, conflict = { kind, action, label, empty, severe } or nil }
    weave = {},
  },
  ranged = {
    swingStart     = 0,     -- GetTime() of last Auto Shot fire
    swingDuration  = 3.0,   -- effective ranged swing time (haste-adjusted)
    swingRemaining = 0,     -- derived in tick: time until next shot
    -- Auto Shot wind-up (CLEU SPELL_CAST_START -> release). It is 0.5s at BASE
    -- weapon speed and scales with the same haste multiplier as the swing, so in
    -- absolute seconds it moves with every proc — dummy-verified at 0.365s on a
    -- 2.174 eWS and 0.259s under Rapid Fire at 1.553.
    --
    -- What's actually invariant is the RATIO windup/swingDuration (= 0.5 / base
    -- weapon speed): measured 0.1679 and 0.1668 in those two runs. So the ratio
    -- is what SwingTimer measures and the absolute value is derived from it each
    -- tick — that way a haste change is reflected instantly instead of waiting
    -- for the average to re-converge. Seed assumes the common 3.0 bow.
    windupRatio    = 0.5 / 3.0,
    windup         = 0.5,   -- derived in tick: windupRatio * swingDuration
    -- Correction factor between what `1.5 / (1 + GetRangedHaste()/100)` predicts
    -- for a Steady Shot cast and what the server actually reports. Measured from
    -- UnitCastingInfo on each Steady (SwingTimer:UpdateCastHasteCorr); 1.0 means
    -- the formula is exact. Kept as a correction rather than an absolute cast
    -- time for the same reason windupRatio is a ratio: it stays valid across
    -- haste changes, so a proc is reflected instantly instead of after the next
    -- Steady. Use Nock.RangedCastTime(base) rather than reading this directly.
    castHasteCorr  = 1.0,
    repeating      = false, -- auto-shot toggle state
    autoDelay      = 0,     -- seconds the last Auto Shot fired LATE vs one weapon-speed cycle (clamped ≥0)
  },
  melee = {
    swingStart     = 0,
    swingDuration  = 2.6,
    swingRemaining = 0,
  },
  network = {
    latencyMs = 0,
  },
  -- Global cooldown. Derived each tick in Core:Tick by probing Steady Shot's
  -- cooldown (it has no real CD, so any reading ≤ GCD_BASE+slop IS the GCD,
  -- haste-scaled). Single source of truth — the rotation row and the GCD bar
  -- both read this instead of re-probing.
  gcd = {
    start     = 0,
    duration  = 0,
    remaining = 0,
    active    = false,
  },
  cooldowns = {
    -- keyed by entry.key: { startTime, duration, remaining, ready, procActive, icon }
  },
  target = {
    exists      = false,
    alive       = false,
    friendly    = false,
    rangeZone   = nil,  -- LEGACY classification: "TOO_CLOSE" | "SWEET" | "TOO_FAR" | "OUT" | nil
    spellOut    = {},   -- [cooldown key] = true (out of range for that slot's spell) | false | nil (unknown / not a spell); RangeFinder, 10 Hz
                        -- (feeds RangeSounds/WeaveCoach/Rotation; unchanged semantics)
    inMelee     = false,
    meleeProximity = 0, -- LEGACY anchor value (P_* constants, instant), ~[-0.15..0.15]
    rangeState  = nil,  -- display state machine: "LONG"|"CLOSE"|"SWEET"|"MELEE" | nil
    rangeProg   = -1,   -- clamp-and-snap glide estimate, -1..+1, 0 = melee boundary
    rangeBracket = nil, -- finding-ladder bracket key (RangeEngine.BRACKETS) | nil
    rangeEstimateStale = false, -- RESYNC: estimate knowably degraded
    huntersMark = nil,  -- { name, spellId, icon, remaining, duration, fromPlayer,
                        --   sourceName } or nil. sourceName is the casting
                        --   hunter's display name, or nil when the client
                        --   won't name the caster -- which is "unknown", not
                        --   "nobody": the mark is up either way.
  },
  context = {
    moving       = false,
    conserveMana = false,
    controlLost  = false,
  },
  rotation = {
    profileName    = nil,  -- turret notation (eWS bracket), e.g. "1:1"
    weaveName      = nil,  -- weave notation (buff-based), e.g. "6:9:1:1 3w"
    notation       = nil,  -- the one auto-selected for display (weave when weaving, else turret)
    nextAction     = nil,  -- spellId of the ability that should be NEXT, or nil
    nextNextAction = nil,  -- one-GCD-ahead foresight
    drift          = 0,    -- seconds off ideal cadence
  },
  -- Hold-to-weave coach. keyHeld/keyHeldSince are written by WeaveBind's
  -- insecure click hook; stage is derived per tick by Modules/WeaveCoach.lua:
  -- "GO" (weave window open), "HOLD" (key down, melee hit not landed yet),
  -- "STRUCK" (hit landed, still too close to shoot — move out, KEEP holding),
  -- "RELEASE" (hit landed and Auto Shot is in range — release), nil = idle.
  -- holdTouchedMelee: diagnostic breadcrumb — true once the current weave
  -- hold has reached TRUE melee (Wing Clip) range; reset on each down-edge.
  weave = {
    keyHeld      = false,
    keyHeldSince = 0,
    stage        = nil,
    -- Auto Shot reactivation retry cost (the "retry grid" — see
    -- Nock.ReleaseCost below). Derived each tick from swingRemaining minus
    -- latency; published unconditionally so the release bar and the weavelog
    -- verifier can never disagree. 0 = a release right now is free.
    releaseCost   = 0,
    releaseFreeIn = 0,   -- seconds until releaseCost next hits zero
    -- Garment auto-flip (WeaveBind): true while an auto-unequip attempt is
    -- blocked (bags full / cursor busy) — read by Warnings so the red
    -- shirt-gate warning stays up instead of being suppressed.
    garmentFlipBlocked = false,
  },
  -- "Shot Bars" scrolling timeline (Fluffy-style). Written by ShotPredictor,
  -- read by the ShotBars view. Arrays are reused in place (no per-tick alloc):
  -- `n` fields track the live length; entries past it are stale and ignored.
  shotpredict = {
    active     = false,                -- rotationMode=="bars" AND a valid swing
    now        = 0,                    -- GetTime() the spans/sparks are anchored to (ShotBars renders against this)
    windowSec  = 3.4,                  -- lookahead horizon (profile.shotBarsWindow)
    profileName = "—",                 -- moved off the (hidden) swing bar (DISPLAY name — may be a user rename)
    rawNotation = nil,                 -- the built-in notation behind profileName (DisplayColor keys on this)
    nSparks    = 0,
    sparks     = {},                   -- absolute GetTime() Auto Shot fire times
    nClips     = 0,
    clips      = {},                   -- absolute clip breakpoints: last moment a Steady can still start (per cycle)
    windows    = {                     -- per ability: { n, [i]={s,e} } absolute spans
      steady = { n = 0 },
      -- The queue window: [wind-up start, shot]. Castable, but the press is held
      -- until the arrow is away rather than completing in time — a distinct
      -- colour so it can't be read as the plain Steady window next to it.
      queue  = { n = 0 },
      multi  = { n = 0 },
      arcane = { n = 0 },
      raptor = { n = 0 },
      weaveauto = { n = 0 },           -- melee-row weave window while Raptor is on CD (dim, auto-attack only)
      danger = { n = 0 },              -- ranged-row clip fill (last safe cast → shot)
      weaveclip = { n = 0 },           -- melee-row no-weave fill (mirror of danger)
    },
  },
  warnings = {
    -- ordered array, highest severity first
    -- entries: { id, severity = "red"|"amber"|"blue", text }
  },
  helpers = {
    -- ordered array of pre-pull / situational badges.
    -- entries: { id, status = "active"|"missing", icon, remaining }
  },
  -- A boss's single-target mark aimed at you — Teron Gorefiend's Shadow of
  -- Death, Archimonde's Air Burst. Deliberately NOT an entry in `warnings`
  -- above: it draws as its own centre banner (UI/Frame_BossBanner.lua), not as
  -- a 44px square in the alert row. Produced by Modules/BossMarkWatch.lua.
  bossMark = {
    active    = false,
    text      = "",
    remaining = 0,
    source    = nil,   -- "log" (the combat log named you) | "unit" (he is facing you)
    encounter = nil,   -- "teron" | "archimonde" — which row of ENCOUNTERS raised it
  },
  -- Dead (not yet released) with Sated/Exhaustion still on you — the raid
  -- burned Bloodlust this attempt. Draws as DO NOT RELEASE on the same centre
  -- banner as bossMark (UI/Frame_BossBanner.lua), bossMark taking priority.
  -- Produced by Modules/Warnings.lua on its slow lane.
  -- Anetheron's Sleep vs the Sulfuron Slammer: what the clickable button
  -- draws. Produced by Modules/SlammerWatch.lua off its pure engine
  -- (Modules/SlammerEngine.lua); UI/Frame_SlammerButton.lua reads it. `visible`
  -- is the watcher's wish — the button is secure, so the frame honours it only
  -- out of combat.
  slammer = {
    visible   = false,
    state     = "idle",  -- idle | wait | now | covered | slept | exposed
    label     = "",
    value     = nil,     -- seconds under the label, or nil
    remaining = 0,       -- to the window
    verdict   = nil,     -- "covered" | "exposed" from the last cast
    count     = 0,       -- Slammers in the bag
    bossSeen  = false,
  },
  noRelease = {
    active = false,
  },
  -- The Dimensional Ripper / Ultrasafe Transporter countdown: ALT F4 a second
  -- before the teleport cast ends and you keep the side effect without the
  -- trip. Produced by Modules/RipperWatch.lua off Modules/RipperEngine.lua;
  -- UI/Frame_RipperCountdown.lua draws it. Published unconditionally — the
  -- warning's enable flag is read by the view.
  ripper = {
    active    = false,
    label     = nil,     -- "9" .. "2", then "ALT F4"; nil while idle
    go        = false,   -- the label is ALT F4
    remaining = 0,       -- seconds to the deadline (cast end - lead)
    frac      = 0,       -- progress through the cast, 0..1
    itemId    = nil,     -- 30542 / 30544
    icon      = nil,
    preview   = false,   -- /nock ripper test
  },
  -- True when a WeakAura matching a configured name prefix is loaded — i.e.
  -- the user already runs a third-party consumes-reminder pack (event-driven,
  -- set by the Helpers module). Suppresses the Helpers panel to avoid overlap.
  helpersHiddenByWA = false,
  misdirection = {
    hunters = {
      -- [name] = { name, target, isActive, charges, cdRemaining, cdDuration,
      --            castTime } — charges = remaining MD charges (3→1) while
      -- active and the caster's buff reports a count, else nil.
    },
  },
  -- Click-to-Misdirect tank panel. Roster is event-driven (secure buttons can
  -- only be wired out of combat); `ready` is the per-tick MD-off-cooldown flag
  -- the view uses to dim rows. See Modules/MisdirectCast + UI/Frame_Misdirect.
  mdcast = {
    tanks = {},        -- ordered list of { name, unit, class }
    ready = true,
    cdRemaining = 0,   -- seconds left on the player's Misdirection CD (0 = ready)
  },
  bufftracker = {
    player = {},   -- ordered list of { name, icon, count, duration, expirationTime }
    pet    = {},
  },
  -- Ordered list of tracked TARGET debuffs (curated + custom), each with a
  -- present/missing flag. Written by DebuffTracker, read by its grid view.
  debufftracker = {},
  totems = {
    -- Core tracking (always shown, greyed when out of range): the air aura
    -- (Grace/Wrath/NR/Tranquil) and earth. windfury is an EXTRA slot rendered
    -- on top ONLY when the WF weapon enchant is actually on you (twisting).
    air      = {},    -- { present, expirationTime, duration, icon }
    earth    = {},
    windfury = {},
  },
  -- Published by Frame_InfoRow (event-driven) so other modules can read the
  -- true ammo reserve without recomputing it. total = quiver + regular bags +
  -- maker charges.
  ammo = {
    total     = 0,
    quiver    = 0,
    hasQuiver = false,
  },
  -- Written by the Durability engine (event-driven), read by the repair bar.
  repair = {
    pct    = 100,    -- equipped-gear durability %
    needed = false,  -- enabled AND in a city zone AND pct < threshold
  },
  -- Transient preview flags owned by the onboarding wizard (Modules/Onboarding).
  -- Never persisted, always wiped on wizard teardown. Modules read these to
  -- render sample content out of combat so a wizard page can show a real frame
  -- doing something instead of an empty one.
  demo = {
    hudForceShow   = false,  -- keep the HUD visible even with hideOoc set
    rotationSample = false,  -- light a next-action icon with no target
    debuffTracker  = false,  -- fill the target-debuff grid with samples
  },
  -- Practice mode (Modules/Practice.lua). `active` is THE gate every live
  -- producer checks before writing the fields the simulator owns — see the
  -- spec's producer-gate table. gcd/meleeHaste replace the API reads in
  -- Core:Tick while active. lastVerdict feeds the toast.
  sim = {
    active      = false,
    fightOn     = false,
    -- `fightOn` is true from the moment Start is pressed; `pulled` only once
    -- the player's first press has landed. Between the two the fight is ARMED:
    -- the clock has not started and `t0` is provisional.
    pulled      = false,
    t0          = 0,
    gcd         = { start = 0, duration = 0 },
    meleeHaste  = 0,
    notation    = nil,
    -- The symbols the CURRENT haste window's paper actually asks for, published
    -- by Practice:Step from the grader (a reused table, booleans keyed
    -- s/m/A/w/r). nil between fights = no paper = no scope. Read by the plan
    -- (its rows) and by the conveyor's weave-lane gate.
    paperSyms   = nil,
    -- The FIGHT's symbol set: the union of every window's paperSyms since the
    -- pull, seeded with the opening paper. The plan's rows read this one, so a
    -- window whose paper drops the instants (2:2 under Lust) does not take
    -- their rows off the stage and blink them back (user, 2026-08-27).
    rowSyms     = nil,
    -- THE ORACLE. The one answer to "what do I press next / when is the weave
    -- gap": a Nock.PracticePlan table owned by Modules/Practice.lua, built once
    -- per tick in Practice:Step BEFORE any module Refresh runs. The medallion,
    -- the rotation row, WeaveCoach's GO, the conveyor's NEXT and the coach line
    -- all READ it (Modules/Rotation.lua copies plan.nextSpellId in a sim fight).
    -- Nothing else computes it. nil until practice enables.
    plan        = nil,
    -- Seconds the conveyor shows either side of the hit line (its Layout
    -- writes them); the plan is built to reach them, profile values as floors.
    horizonPast   = nil,
    horizonFuture = nil,
    lastVerdict = nil,   -- { t, code, ms, text, key }  key: steady|multi|arcane|auto
  },
  -- Written by the ShoppingList engine on zone/bag events, read by its view.
  -- items[] reused in place; `n` = live length, entries past it are stale.
  -- Every catalog entry is listed (stocked ones carry done = true); nNeeded
  -- counts the ones still below threshold.
  shopping = {
    active  = false,  -- in a shopping zone AND feature enabled
    zone    = "",     -- the matched zone name (display)
    n       = 0,
    nNeeded = 0,
    items   = {},     -- [i] = { key, label, have, need, icon, done }
  },
}

-- The ONE reading of the "Hide out of combat" switch (General -> Visibility).
-- Pure: profile + flags in, verdict out, so the three consumers agree and
-- the rule is testable (Tests/hide_ooc_test.lua).
--
-- HideOocApplies: the HUD itself goes when out of combat — unless the HUD is
-- unlocked (must stay grabbable), the wizard is previewing it, or PRACTICE is
-- on (the practice engine drives the HUD out of combat by design).
function Nock.HideOocApplies(p, inCombat, state)
  if not (p and p.hideOoc) then return false end
  if inCombat then return false end
  if p.locked == false then return false end
  if state and state.demo and state.demo.hudForceShow then return false end
  if state and state.sim and state.sim.active then return false end
  return true
end

-- RestedHideApplies: the same switch also puts the buff tracker and the
-- Misdirection panel away while RESTED (an inn, a city) — not out of combat:
-- both are wanted between pulls, and the MD panel anchors secure buttons, so
-- it could never be re-shown at a pull anyway. `resting` is IsResting().
function Nock.RestedHideApplies(p, resting, state)
  if not (p and p.hideOoc) then return false end
  if not resting then return false end
  if p.locked == false then return false end
  if state and state.demo and state.demo.hudForceShow then return false end
  return true
end

-- Haste-adjusted cast time for a ranged shot, given its base cast in seconds
-- (Steady 1.5, Multi 0.5). THE single source for ability cast times — clip
-- ticks, the rotation engine and the shot bars must all go through here.
--
-- Derived from the measured wind-up, not from a haste formula. Ranged cast times
-- are divided by the SAME multiplier that scales the swing — dummy-measured, the
-- server reports Steady at 1.09s on a 2.174 eWS, and 1.5/1.09 = 1.376 = the
-- swing's own 3.0/2.174. The wind-up is already that multiplier expressed in
-- seconds (windup == AUTO_SHOT_CAST / hasteMul), so it doubles as the yardstick:
--
--   castTime = baseCast * windup / AUTO_SHOT_CAST
--
-- which needs no haste API and no quiver assumption at all. Both of those had
-- burned us: GetRangedHaste is quiver-blind, and whether to reinstate a `* 1.15`
-- on top of it is exactly the guess this replaces. (For the record the quiver
-- DOES shorten ranged casts — an earlier comment here claimed otherwise.)
--
-- castHasteCorr is the measured residual on top, and should sit near 1.0; it
-- exists so a discrepancy shows up as a number instead of a wrong bar.
function Nock.RangedCastTime(baseCast)
  local st = Nock.state
  local corr = st.ranged.castHasteCorr
  if not corr or corr <= 0 then corr = 1 end
  local ref = (Nock.Constants and Nock.Constants.AUTO_SHOT_CAST) or 0.5
  local w = st.ranged.windup
  if w and w > 0 and ref > 0 then
    return baseCast * (w / ref) * corr
  end
  -- Pre-first-shot fallback only.
  local h = (GetRangedHaste and GetRangedHaste() or 0) / 100
  return baseCast * corr / (1 + h)
end

-- The clip deadline, as a `swingRemaining` value: start a shot with this much
-- of the swing left and it is the last moment it can still complete without
-- delaying the next Auto Shot.
--
--   cast + windup + latency
--
-- There is deliberately no user-tunable safety margin on top. It existed, and
-- every non-zero value it could hold moved the tick away from the measured
-- truth — the wind-up term below is read from the player's own shots, so the
-- baseline is already the real edge.
--
-- The `windup` term is the one everything used to be missing. A cast does not
-- have to finish before the arrow leaves — it has to finish before the WIND-UP
-- starts, because you cannot begin a wind-up while casting, so any overlap
-- pushes the shot back by that much. Omitting it made every tick roughly one
-- wind-up too permissive.
--
-- THE single definition. The rotation engine, both swing bars' ticks and the
-- shot bars all resolve through here so they can never disagree about what
-- "safe" means. `baseCast` is the UNMODIFIED cast (Steady 1.5, Multi 0.5) —
-- haste is applied inside.
function Nock.ClipThreshold(baseCast)
  local st = Nock.state
  local latency = (st.network.latencyMs or 0) / 1000
  return Nock.RangedCastTime(baseCast) + (st.ranged.windup or 0) + latency
end

-- LOWER edge of the clip band. Press with less than this much swing left and the
-- client holds the request until the arrow is away, so the cast begins at the top
-- of the next cycle and costs nothing.
--
-- This is why the danger is a BAND and not a tail. Dummy-verified both ways:
--   * presses inside the wind-up came back with the cast starting at
--     rem == swingDuration (queued) and no delay;
--   * casts genuinely in flight across the wind-up delayed the shot by the
--     overlap (predicted 1.136 / 1.056, measured 1.055 / 1.069).
--
-- Deliberately NOT `windup + latency`, which is the true edge from the client's
-- side (a press at windup+latency still reaches the server inside the window).
-- The plain wind-up is the conservative choice: it warns slightly early rather
-- than promising a queue that might not land.
function Nock.ClipQueueEdge()
  return Nock.state.ranged.windup or 0
end

-- Should the auto-swing views (React auto bar, release bar always-mode) render?
-- THE single definition — the gate was inlined in both views and both had the
-- same hole: out of combat, a stranded `repeating` (the weave key's !Auto Shot
-- re-arm landing around a kill, with no shot ever firing after) kept an expired
-- swing "live" and pinned the bar at 100% until the next real Auto Shot.
--
-- A swing in flight always draws — weaving can drop `repeating` mid-cycle, so
-- the flag must never blank a running swing. With the swing EXPIRED, in combat
-- the bar only stays full while auto is still armed (`repeating`): that full
-- bar means "held shot — fires the moment you can shoot", true while moving or
-- out of line of sight, but a lie once auto-repeat is cancelled. Stepping into
-- melee cancels it (verified in-game: the shot needs a fresh !Auto Shot press
-- plus its wind-up before anything fires), so disarmed+expired renders blank
-- until START_AUTOREPEAT_SPELL re-arms. Out of combat an expired swing never
-- draws, whatever `repeating` claims (the stranded-flag bug above).
function Nock.AutoSwingLive()
  local st = Nock.state
  local r = st.ranged
  if r.swingDuration <= 0 or r.swingStart <= 0 then return false end
  if r.swingRemaining > 0 then return true end
  -- A practice fight is combat for this purpose: its held shot (a clipped
  -- auto waiting on a cast) must stay full exactly as a live one does.
  local fighting = st.player.inCombat or (st.sim and (st.sim.fightOn or st.sim.replaying))
  return (fighting and r.repeating) and true or false
end

--------------------------------------------------------------------------------
-- The rotation NAME the HUD shows — the auto-shot bar's label, the React
-- cluster's, and (the one that matters) the paper Modules/ShotPredictor.lua
-- lays the shot bars out from.
--
-- THE PAPER IS THE SCOPE here too. Core's tick resolves the live turret/weave
-- ladders off `state.ranged.swingDuration` and the range band, and in a practice
-- fight every one of those inputs is the SIM's: a `1:1` paper drill pinned to
-- eWS 1.34 read back as `1:1` while it stood at range and flipped to the WEAVE
-- rotation the moment the drill walked into melee — so the HUD named, and the
-- shot bars drew, a rotation the fight was not being graded against. The drill's
-- own notation (`state.sim.notation`, the grader's open haste window) wins for
-- as long as practice owns the HUD.
--
-- Pure: no globals beyond `state`. Covered in Tests/practice_gates_test.lua.
--------------------------------------------------------------------------------
function Nock.HudNotation(state, turretName, weaveName, weaveEnabled, proxMin)
  local sim = state.sim
  if sim and sim.active and sim.notation then return sim.notation end
  if not (weaveEnabled and weaveName and state.player.canWeave) then return turretName end
  local t = state.target
  local band = proxMin
  if band == nil then band = -0.10 end
  -- In/near melee on a real target. rangeZone is nil (no valid target) or
  -- "OUT" (at range) → turret; meleeProximity is only trustworthy otherwise
  -- (it's hard-set to 0 when there's no target).
  local inWeaveRange = t.inMelee
    or (t.rangeZone ~= nil and t.rangeZone ~= "OUT" and (t.meleeProximity or -1) >= band)
  if inWeaveRange then return weaveName end
  return turretName
end

-- Auto Shot reactivation retry cost (the "retry grid"). After a weave the
-- release macro runs /cast !Auto Shot; while the swing is still recharging the
-- client re-checks on a ~RETRY_PULSE cadence anchored at the press, and the
-- shot fires at the first check AFTER swing-ready. So releasing with `rem`
-- seconds of swing left costs
--
--   pulse * ceil(rem / pulse) - rem
--
-- a sawtooth over the press moment: zero everywhere past ready AND at exact
-- pulse multiples before it (a check lands ON ready — the free notches), rising
-- to just under one pulse right before each notch. Unverified on Anniversary —
-- the weavelog predicted/measured lines are the in-game gate; the release bar
-- ships as an experiment until they agree.
--
-- THE single definition: the release bar and the weavelog verifier both resolve
-- through here so the bar can never promise a cost the log doesn't measure.
-- Pure on purpose (rem in, cost out — latency handling is the caller's) so it
-- runs under the standalone test harness. `pulse` overrides the constant, for
-- tests and for a corrected measured value.
function Nock.ReleaseCost(rem, pulse)
  if not rem or rem <= 0 then return 0 end
  pulse = pulse or (Nock.Constants and Nock.Constants.RETRY_PULSE) or 0.5
  -- The epsilon absorbs floating drift: a rem that is "one pulse" only up to
  -- binary error must read as a free notch, not as a near-full-pulse cost.
  local cost = pulse * math.ceil(rem / pulse - 1e-6) - rem
  if cost < 0 then return 0 end
  return cost
end

-- Seconds until the cost next hits zero: ready itself inside the last tooth,
-- otherwise the upcoming free notch. Same pulse/epsilon conventions as above.
function Nock.ReleaseFreeIn(rem, pulse)
  if not rem or rem <= 0 then return 0 end
  pulse = pulse or (Nock.Constants and Nock.Constants.RETRY_PULSE) or 0.5
  local phase = rem % pulse
  if phase >= pulse - 1e-6 then return 0 end   -- standing on a notch (mod drift)
  return phase
end

-- What a cast bar should draw, or nil for nothing. A real cast (or the Feign
-- Death bar, which Modules/CastBar projects into the same field) always wins; the
-- Auto Shot wind-up is shown only when the calling view's own setting allows it.
--
-- `showAutoShot` is passed in rather than read here because the two cast bars
-- have separate toggles — and, more importantly, because that setting must never
-- reach anything but rendering. Deciding visibility at the producer is what let a
-- cosmetic option change engine state; the gate lives here, at the render edge,
-- so it structurally cannot.
function Nock.CastBarSource(showAutoShot)
  local p = Nock.state.player
  if p.casting then return p.casting end
  if showAutoShot and p.autoShotCast then return p.autoShotCast end
  return nil
end

-- Whether free placement governs layout right now. THE single gate every
-- consumer of profile.freeLayout resolves through (HUD layout/background/drag
-- state, the free-row nudge gates, the totem tracker's unglue, the cast bar's
-- free position). freeLayout is a Classic-look setting: the React look always
-- grids — its cluster and grid rows share a -1px seam that free placement would
-- tear into two UIParent-anchored pieces — so a flag left on from a Classic
-- session is ignored while hudMode == "react", not consumed. The saved
-- elementPositions survive untouched for when the user switches back.
function Nock.FreeLayoutActive()
  local p = Nock.db and Nock.db.profile
  if not p then return false end
  if (p.hudMode or "classic") == "react" then return false end
  return p.freeLayout == true
end

-- Settling delay the Steam Tonk guard waits out before stepping the player back
-- out of the transform, floored at C.TONK_CANCEL_MIN.
--
-- THE single definition: TonkGuard (which acts on it) and Frame_TonkDial (which
-- draws the sweep down to it) both resolve through here, so the dial can never
-- promise a moment the guard doesn't act on. The floor is enforced HERE as well
-- as in the slider and MigrateProfile because those two only cover values the
-- user can reach through the GUI -- a hand-edited SavedVariables, or a profile
-- imported from an install that never ran the migration, still lands here.
function Nock.TonkCancelDelay()
  local C = Nock.Constants
  local p = Nock.db and Nock.db.profile
  local v = tonumber(p and p.tonkCancelDelay) or C.TONK_CANCEL_DELAY
  if v < C.TONK_CANCEL_MIN then return C.TONK_CANCEL_MIN end
  return v
end
