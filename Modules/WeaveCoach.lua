-- Modules/WeaveCoach.lua
-- Derives the hold-to-weave cycle stage onto state.weave.stage and plays
-- outcome sound cues; pure tick consumer of signals other modules publish.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local WeaveCoach = Nock:NewModule("WeaveCoach")
local C = Nock.Constants

-- Sentinel for "no pending candidate" (same trick as RangeSounds): distinct
-- from every real stage INCLUDING nil, so a nil raw stage settles like any
-- other transition instead of slipping through nil == nil.
local NONE = {}
-- A new stage must hold this long before it commits. STRUCK/RELEASE depend on
-- the range zone, and the melee/shoot probes can flip for a tick right at a
-- boundary — settling filters that flicker out of the display while staying
-- imperceptible as latency.
local SETTLE = 0.12
-- The RELEASE sound cue runs on the RAW stage with its own, shorter settle
-- (~2 ticks — still filters one-tick probe flicker). It must NOT ride the
-- display commit above: the commit path can skip stages entirely when the hit
-- lands inside the display settle window (press → hit in <SETTLE goes
-- GO→RELEASE with no committed HOLD/STRUCK), and its extra latency loses the
-- race against the player releasing on what the zone bar already shows.
local RELEASE_CUE_SETTLE = 0.06

local function playCue(profileKey)
  local p = Nock.db and Nock.db.profile
  if not p or p.weaveCoachSoundsEnabled == false then return end
  local name = p[profileKey]
  if not name or name == "" or name == "None" then return end
  local LSM = LibStub("LibSharedMedia-3.0", true)
  if not LSM then return end
  local path = LSM:Fetch("sound", name)
  if path and PlaySoundFile then PlaySoundFile(path, p.deadZoneSoundChannel or "Master") end
end

function WeaveCoach:OnEnable()
  self._stage = nil   -- last committed (settled) stage
  self._cand = NONE   -- candidate stage awaiting settle
  self._candSince = 0
  self._cuedLanded = false   -- hit-landed cue already played for this hold
  self._cuedRelease = false  -- release cue already played for this hold
  self._relSince = nil       -- when the raw stage last became RELEASE
end

-- Stage semantics (happy path only, rendered by Frame_RangeFinder):
--   GO      — weave window open. Proxied by state.rotation.nextAction being
--             Raptor Strike, which already folds Raptor CD + ranged-swing
--             headroom + weave proximity band + canWeave (Rotation.scoreRaptor)
--             — so GO needs the rotation helper enabled (default on).
--   HOLD    — weave key held (WeaveBind writes state.weave.keyHeld), the
--             queued melee hit hasn't landed yet.
--   STRUCK  — a melee hit landed during this hold (Raptor replaces the swing
--             when queued; SwingTimer stamps state.melee.swingStart for both)
--             but Auto Shot can't fire from here (zone TOO_CLOSE/OUT): move
--             back out and KEEP HOLDING — releasing now runs !Auto Shot at a
--             spot where it fails ("target too close") and you stand idle.
--   RELEASE — hit landed and the shoot probe passes (zone SWEET/TOO_FAR):
--             release now, the release macro's !Auto Shot will stick.
--   nil     — anything else: feature off, no valid target, cycle complete.
function WeaveCoach:Refresh(state)
  local w = state.weave
  local t = state.target
  -- Diagnostic breadcrumbs (read by /nock weavelog's UP line): whether this
  -- hold ever reached TRUE melee (Wing Clip) range, and for how long in
  -- total. A grazing pass shows a tiny in-melee time — the client probe
  -- flickers in-range at the edge while the server never agrees long enough
  -- to swing. Reset on each down-edge by WeaveBind's click hook.
  local nowT = GetTime()
  if w.keyHeld and t.inMelee then
    w.holdTouchedMelee = true
    w.holdMeleeSec = (w.holdMeleeSec or 0)
      + (self._lastCoachT and (nowT - self._lastCoachT) or 0)
  end
  self._lastCoachT = nowT
  local raw
  local landed = false
  if Nock.db.profile.weaveBindEnabled == true
     and t.exists and t.alive and not t.friendly
     and state.player.canWeave then
    if w.keyHeld then
      landed = w.keyHeldSince > 0
        and (state.melee.swingStart or 0) >= w.keyHeldSince
      if landed then
        local zone = t.rangeZone
        raw = (zone == "SWEET" or zone == "TOO_FAR") and "RELEASE" or "STRUCK"
      else
        raw = "HOLD"
      end
    elseif state.rotation.nextAction == C.SpellID.RAPTOR_STRIKE then
      raw = "GO"
    end
  end

  -- "Hit landed" cue fires on the RAW landed edge, once per hold. The swing
  -- stamp is a clean CLEU edge; the STRUCK/RELEASE fork below depends on the
  -- flappy, settle-delayed range zone — binding this cue there swallowed it
  -- whenever the hit and the release fell inside the settle window (the
  -- common rhythm on white-hit weaves).
  if landed then
    if not self._cuedLanded then
      self._cuedLanded = true
      playCue("weaveCoachStruckSound")
    end
  else
    self._cuedLanded = false
  end

  -- Release cue: raw RELEASE sustained for RELEASE_CUE_SETTLE, once per hold.
  -- On a big-hitbox boss where the hit lands already inside the shoot ring,
  -- this fires right on the heels of the hit-landed cue: "hit" then "clear"
  -- (user-confirmed choice: keep both).
  if raw == "RELEASE" then
    if not self._relSince then self._relSince = GetTime() end
    if not self._cuedRelease and GetTime() - self._relSince >= RELEASE_CUE_SETTLE then
      self._cuedRelease = true
      playCue("weaveCoachReleaseSound")
    end
  else
    self._relSince = nil
  end
  if not w.keyHeld then
    self._cuedRelease = false
  end

  -- Settle-and-commit for the DISPLAYED stage (RangeSounds discipline).
  if raw == self._stage then
    self._cand = NONE
  elseif raw ~= self._cand then
    self._cand = raw
    self._candSince = GetTime()
  elseif GetTime() - self._candSince >= SETTLE then
    self._stage = raw
    self._cand = NONE
    -- A genuinely committed return to the dead zone re-arms the release cue,
    -- so a real back-in → back-out within one hold cues again — while raw
    -- boundary hover (which never survives the display settle) does not.
    if raw == "STRUCK" then
      self._cuedRelease = false
    end
  end
  w.stage = self._stage
end
