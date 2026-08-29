-- Modules/RangeSounds.lua
-- Plays a configurable sound when entering / leaving the dead zone (rangeZone
-- "TOO_CLOSE"). Pure consumer of state.target.rangeZone — no events; runs off
-- the central tick. Transitions fire on any real zone change (including a tank
-- repositioning the boss); target loss (zone -> nil) is suppressed.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local RangeSounds = Nock:NewModule("RangeSounds")

local DEAD = "TOO_CLOSE"
-- Sentinel for "no pending candidate". Distinct from every real zone value
-- INCLUDING nil, so a target-loss tick (zone -> nil) is settled like any other
-- transition instead of slipping through the nil == nil comparison.
local NONE = {}
-- A new zone must hold for this long before it counts as a real transition.
-- The melee/shoot probes can flip for a single tick right at the boundary;
-- requiring a short settle filters that flicker while still catching deliberate
-- steps (which persist well beyond it). It does NOT gate the sound itself, so
-- every committed transition — including a quick weave step in then back out —
-- fires its cue. ~0.12s is imperceptible as audio latency and clears 1-3 ticks
-- of flicker at any tick rate.
local SETTLE = 0.12

local function playSound(profileKey)
  local p = Nock.db and Nock.db.profile
  local name = p and p[profileKey]
  if not name or name == "" or name == "None" then return end
  local LSM = LibStub("LibSharedMedia-3.0", true)
  if not LSM then return end
  local path = LSM:Fetch("sound", name)
  if path and PlaySoundFile then PlaySoundFile(path, p.deadZoneSoundChannel or "Master") end
end

function RangeSounds:OnEnable()
  self._zone      = nil   -- last committed (settled) zone
  self._cand      = NONE  -- candidate zone awaiting settle (NONE = none pending)
  self._candSince = 0
end

function RangeSounds:Refresh(state)
  local p = Nock.db and Nock.db.profile
  if not p then return end

  local cur = state.target.rangeZone
  local now = GetTime()

  -- Already settled on this zone → cancel any pending candidate and wait.
  if cur == self._zone then
    self._cand = NONE
    return
  end
  -- New candidate → (re)start its settle clock. A flicker back to the committed
  -- zone next tick lands in the branch above and cancels it (no false edge).
  if cur ~= self._cand then
    self._cand      = cur
    self._candSince = now
    return
  end
  -- Candidate hasn't held long enough yet.
  if now - self._candSince < SETTLE then return end

  -- Commit the candidate and fire the edge cue.
  local prev = self._zone
  self._zone = cur
  self._cand = NONE

  if cur == DEAD and prev ~= DEAD then
    if p.deadZoneEnterEnabled ~= false then playSound("deadZoneEnterSound") end
  elseif prev == DEAD and cur ~= nil and cur ~= DEAD then
    -- Left for another live zone. cur ~= nil suppresses target death / deselect,
    -- which isn't a positioning move.
    if p.deadZoneExitEnabled ~= false then playSound("deadZoneExitSound") end
  end
end
