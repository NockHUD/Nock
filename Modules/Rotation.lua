-- Modules/Rotation.lua
-- Priority engine: scores each rotation ability against current state and writes the
-- highest-scoring spellId to state.rotation.nextAction. Runs every tick via the
-- module Refresh loop. Logic per the diziet559 rotation guide + the inspiration WA:
--   - Steady Shot is the filler
--   - Multi-Shot / Arcane Shot substitute for Steady when Steady would clip auto-shot
--   - Raptor Strike weaves when in SWEET zone AND 2H equipped AND auto-shot has headroom
--   - Cast-time abilities are disqualified when moving or out of player control

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Rotation = Nock:NewModule("Rotation")
local C = Nock.Constants

local STEADY = C.SpellID.STEADY_SHOT
local MULTI  = C.SpellID.MULTI_SHOT
local ARCANE = C.SpellID.ARCANE_SHOT
local RAPTOR = C.SpellID.RAPTOR_STRIKE

local STEADY_BASE_CAST = 1.5
local MULTI_CAST = 0.5

local function tune(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function steadyCastTime()
  return Nock.RangedCastTime(STEADY_BASE_CAST)
end

-- Base cooldowns for the foresight projection (TBC ranks; the live values come
-- from state.cooldowns, these only seed "we just pressed it" simulations).
local MULTI_CD  = 10
local ARCANE_CD = 6
local RAPTOR_CD = 6

-- Raptor/weave is only suggested when the melee swing timer will be ready by
-- the time a step-in lands (~half a second of travel). See scoreRaptor.
local MELEE_READY_LEAD = 0.5

local function trackedCdRemaining(state, key)
  -- Foresight override: while `state._cdOverride` is set (see computeNextNext),
  -- projected values shadow the live cooldown table.
  local o = state._cdOverride
  if o and o[key] ~= nil then return o[key] end
  local cd = state.cooldowns and state.cooldowns[key]
  return (cd and cd.remaining) or 0
end

-- Direct API query for abilities not in TRACKED_COOLDOWNS (e.g., Raptor Strike).
-- Filters out GCD reads (duration <= 1.5s) so only the spell's real cooldown counts.
-- A state with `_raptorCdOverride` set takes precedence — used for foresight
-- simulation where we want to pretend Raptor is on CD without touching the API.
local function spellCdRemaining(spellID, state)
  if state and spellID == RAPTOR and state._raptorCdOverride ~= nil then
    return state._raptorCdOverride
  end
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(spellID)
    if info then start, duration = info.startTime, info.duration end
  elseif GetSpellCooldown then
    start, duration = GetSpellCooldown(spellID)
  end
  if not start or start == 0 then return 0 end
  if not duration or duration <= 1.5 then return 0 end
  return math.max(0, start + duration - GetTime())
end

-- The clip risk is a BAND, not a tail. Above the band the cast finishes before
-- the wind-up; below it the press is simply queued and comes out after the arrow,
-- which costs nothing. Only in between does the cast end up in flight across the
-- wind-up and push the shot back. Both edges are dummy-verified — see
-- Nock.ClipQueueEdge in Core/State.lua.
--
--   rem >= ClipThreshold(baseCast)   safe: cast completes in time
--   rem <  ClipThreshold(baseCast)   CLIP
--   rem <= ClipQueueEdge()           safe again: the press queues
--
-- `baseCast` is the UNMODIFIED cast (Steady 1.5, Multi 0.5); haste comes from the
-- shared helpers, which the swing-bar ticks also use, so the engine's verdict can
-- never disagree with what's drawn. Taking a base cast rather than a finished one
-- also fixed Multi: it was passed a flat 0.5 and never haste-adjusted at all.
local function wouldClip(baseCast, state)
  local rem = state.ranged.swingRemaining
  if rem <= 0 then return false end
  if rem <= Nock.ClipQueueEdge() then return false end
  return Nock.ClipThreshold(baseCast) > rem
end

local function scoreSteady(state)
  if state.context.controlLost then return -1 end
  if state.context.moving then return -1 end
  if wouldClip(STEADY_BASE_CAST, state) then return -1 end
  return 50
end

local function scoreMulti(state)
  if state.context.controlLost then return -1 end
  if state.context.moving then return -1 end
  if trackedCdRemaining(state, "MS") > 0 then return -1 end
  if wouldClip(MULTI_CAST, state) then return -1 end
  if wouldClip(STEADY_BASE_CAST, state) then return 70 end
  return 55
end

local function scoreArcane(state)
  if state.context.controlLost then return -1 end
  if trackedCdRemaining(state, "Arc") > 0 then return -1 end
  if state.context.conserveMana then return 20 end
  -- Per the diziet559 rotation guide, Arcane Shot is a clip-zone substitute,
  -- not a default filler. Only fire it when Steady Shot would clip Auto Shot;
  -- otherwise let Steady (or Multi-Shot on CD) take the slot.
  if wouldClip(STEADY_BASE_CAST, state) then return 65 end
  return -1
end

local function scoreRaptor(state)
  if state.context.controlLost then return -1 end
  -- Suggest Raptor whenever the player is in melee OR sitting in the green
  -- weave bands (CLOSE / PERFECT) on the proximity bar — i.e., one short step
  -- away from melee. Band bounds and swing headroom are tunable.
  local t = state.target
  local prox = t.meleeProximity or -1
  local proxMin = tune("rotWeaveProxMin", -0.10)
  local proxMax = tune("rotWeaveProxMax",  0.00)
  local headroom = tune("rotRaptorWeaveHeadroom", 1.0)
  local inWeaveBand = prox >= proxMin and prox <= proxMax
  if not (t.inMelee or inWeaveBand) then return -1 end
  if not state.player.canWeave then return -1 end
  if state.ranged.swingRemaining <= headroom then return -1 end
  if spellCdRemaining(RAPTOR, state) > 0 then return -1 end
  -- A weave can only land once the MELEE swing timer has recharged —
  -- ShotPredictor's weave lane hides for the same reason, and without this
  -- gate the engine (and the weave coach's GO) says "step in" right after a
  -- weave when no hit can connect. The small lead covers the step-in time.
  if (state.melee.swingRemaining or 0) > MELEE_READY_LEAD then return -1 end
  return 80
end

local SCORERS = {
  [STEADY] = scoreSteady,
  [MULTI]  = scoreMulti,
  [ARCANE] = scoreArcane,
  [RAPTOR] = scoreRaptor,
}

-- Per-bracket score bias from Rotations/Profiles.lua. Only applied when the
-- structural scorer returned a positive (i.e. eligible) score, so weights can
-- fine-tune among eligible candidates but never override clip/GCD/CD gates.
local function profileBias(state, spellId)
  local profile = state.rotation and state.rotation.profile
  if not profile or not profile.weights then return 0 end
  return profile.weights[spellId] or 0
end

local function pickBest(state)
  local bestId, bestScore = nil, 0
  for id, scorer in pairs(SCORERS) do
    local s = scorer(state)
    if s > 0 then s = s + profileBias(state, id) end
    if s > bestScore then
      bestId, bestScore = id, s
    end
  end
  return bestId
end

-- One-press foresight: what should follow `firstId`? Projects the state to the
-- moment the player is free again (cast + GCD past), starts firstId's own
-- cooldown, and re-scores. State fields are shadowed (overrides) or saved and
-- restored in place — no allocation, and modules later in the tick see the
-- real values.
local cdOverride = {}  -- reused scratch, keys "MS"/"Arc"

local function computeNextNext(state, firstId)
  if not firstId then return nil end

  -- Lead time until the next press is possible.
  local lead
  if firstId == STEADY then
    lead = math.max(steadyCastTime(), C.GCD_BASE or 1.5)
  elseif firstId == RAPTOR then
    lead = 0.5  -- on-next-swing, not GCD-bound; brief step-in allowance
  else
    lead = C.GCD_BASE or 1.5
  end

  local r = state.ranged
  local savedSwing = r.swingRemaining
  local sd = (r.swingDuration and r.swingDuration > 0) and r.swingDuration or 3.0
  local sr = savedSwing - lead
  while sr < 0 do sr = sr + sd end  -- autos keep firing while we're busy
  r.swingRemaining = sr

  cdOverride.MS  = math.max(0, trackedCdRemaining(state, "MS")  - lead)
  cdOverride.Arc = math.max(0, trackedCdRemaining(state, "Arc") - lead)
  if firstId == MULTI  then cdOverride.MS  = math.max(cdOverride.MS,  MULTI_CD  - lead) end
  if firstId == ARCANE then cdOverride.Arc = math.max(cdOverride.Arc, ARCANE_CD - lead) end

  local savedRaptor = state._raptorCdOverride
  local rap = math.max(0, spellCdRemaining(RAPTOR, state) - lead)
  if firstId == RAPTOR then rap = math.max(rap, RAPTOR_CD - lead) end

  state._cdOverride = cdOverride
  state._raptorCdOverride = rap
  local nextNext = pickBest(state)
  if not nextNext then
    -- The projected moment lands in the clip zone (nothing castable). The real
    -- next press comes just after the shot fires — re-score on a fresh cycle.
    r.swingRemaining = sd
    nextNext = pickBest(state)
  end
  state._cdOverride = nil
  state._raptorCdOverride = savedRaptor
  r.swingRemaining = savedSwing

  return nextNext
end

function Rotation:Refresh(state)
  -- Master toggle: when the helper is disabled the row stays visible for CD
  -- swipes / aspect / Hunter's Mark, but no slot is marked as the next action.
  -- Practice mode is exempt: its NOW/NEXT slots ARE the drill's guide, so the
  -- toggle must not blank them (the panel would just show two empty squares).
  if not (state.sim.active or tune("rotationHelperEnabled", true)) then
    state.rotation.nextAction     = nil
    state.rotation.nextNextAction = nil
    return
  end

  -- THE PAPER IS THE SCOPE, AND THE PLAN IS THE PAPER. In a practice fight the
  -- one oracle (Core/PracticePlan.lua, built in Practice:Step earlier this same
  -- tick) has already named the press; the scorers below know the sim's swing
  -- and cooldowns but not the drill, and they used to be filtered here through
  -- Nock.PaperAllows -- one of five places that decided "next". Copied, not
  -- scored: the medallion, the rotation row and WeaveCoach's GO all read these
  -- two fields, so this is the whole reason every practice surface agrees.
  --
  -- Practice ON with no fight running is live scoring as before: there is no
  -- paper to be in scope of.
  local plan = state.sim.active and state.sim.plan or nil
  if plan and plan.live then
    state.rotation.nextAction     = plan.nextSpellId
    state.rotation.nextNextAction = plan.nextNextSpellId
    return
  end
  local bestId = pickBest(state)
  local nextId = computeNextNext(state, bestId)
  state.rotation.nextAction = bestId
  state.rotation.nextNextAction = nextId
end
