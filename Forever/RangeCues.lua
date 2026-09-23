-- Forever/RangeCues.lua
-- Spoken range cues on WoW Forever: one short clip when the target's range
-- zone changes (Forever/RangeFinder.lua publishes MELEE / CLOSE (the dead
-- zone) / SWEET / LONG). Four cues, each its own switch and LSM sound; the
-- dead zone is on by default, the rest off; one master switch over all of
-- them. A zone has to hold a short settle before it counts, so a flicker
-- on a range edge stays silent. Losing the target is silent too.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local RangeCues = Nock:NewModule("RangeCues")

-- 80 ms: long enough to swallow a one-tick flicker on a range edge (the
-- finder runs at 10 Hz), short enough that a spoken cue lands on the step.
local SETTLE = 0.08
local NONE = {}
-- Two guards against a mob (or you) dancing on a range edge: no two cues
-- within ANY_GAP of each other (the clips are about a second long), and the
-- same zone's cue not again within the profile's repeat quiet time.
local ANY_GAP = 1.5
RangeCues.REPEAT_DEFAULT = 4

-- zone -> the profile keys of its cue
RangeCues.CUES = {
  MELEE = { enabled = "cueMeleeEnabled",      sound = "cueMeleeSound",      gate = "cueMeleeGate" },
  CLOSE = { enabled = "cueDeadZoneEnabled",   sound = "cueDeadZoneSound",   gate = "cueDeadZoneGate" },
  SWEET = { enabled = "cueInRangeEnabled",    sound = "cueInRangeSound",    gate = "cueInRangeGate" },
  LONG  = { enabled = "cueOutOfRangeEnabled", sound = "cueOutOfRangeSound", gate = "cueOutOfRangeGate" },
}

-- Each cue's gate: where it may play. A ladder over the group context:
-- "solo" always, "party" only grouped (party or raid), "raid" only in a
-- raid. Unset or unknown reads as "solo".
local GATE_RANK = { solo = 0, party = 1, raid = 2 }
RangeCues.GATES = { "solo", "party", "raid" }

function RangeCues.GateAllows(gate, ctx)
  local need = GATE_RANK[gate] or 0
  return (GATE_RANK[ctx] or 0) >= need
end

-- The live group context: the Mainline pair, then the Classic counts (the
-- pair has lied on Anniversary; both are cheap and plain).
function RangeCues.GroupContext()
  if (_G.IsInRaid and IsInRaid()) or (_G.GetNumRaidMembers and _G.GetNumRaidMembers() > 0) then return "raid" end
  if (_G.IsInGroup and IsInGroup()) or (_G.GetNumPartyMembers and _G.GetNumPartyMembers() > 0) then return "party" end
  return "solo"
end

-- Pure: which cue (profile keys) a zone change plays, or nil.
--   prev, cur   the settled zones (nil = no live hostile target)
--   p           the profile
--   ctx         the group context ("solo" / "party" / "raid"; nil = solo)
function RangeCues.Pick(prev, cur, p, ctx)
  if not p or p.soundCuesEnabled == false then return nil end
  if cur == nil or cur == prev then return nil end
  -- a target appearing is not a range change: nothing on nil -> zone
  if prev == nil then return nil end
  local cue = RangeCues.CUES[cur]
  if not cue then return nil end
  if p[cue.enabled] == false then return nil end
  if not RangeCues.GateAllows(p[cue.gate], ctx or "solo") then return nil end
  local name = p[cue.sound]
  if not name or name == "" or name == "None" then return nil end
  return cue
end

local function play(p, cue)
  local LSM = LibStub("LibSharedMedia-3.0", true)
  if not LSM then return end
  local path = LSM:Fetch("sound", p[cue.sound])
  if path and _G.PlaySoundFile then PlaySoundFile(path, p.deadZoneSoundChannel or "Master") end
end

function RangeCues:OnEnable()
  self._zone, self._cand, self._candSince = nil, NONE, 0
  self._lastAny, self._lastZone = -1e9, {}
end

-- Pure: may zone `cur` speak at `now`, given the last cue time and the
-- per-zone last times? Returns true and records nothing; the caller stamps.
function RangeCues.Quiet(cur, now, lastAny, lastZone, repeatGap)
  if now - lastAny < ANY_GAP then return true end
  local lz = lastZone[cur]
  if lz and now - lz < (repeatGap or RangeCues.REPEAT_DEFAULT) then return true end
  return false
end

-- Every frame, not the 10 Hz lane: one comparison per tick, and the cue is
-- late enough already behind the finder's own lane plus the settle.

function RangeCues:Refresh(state)
  local p = Nock.db and Nock.db.profile
  if not p then return end
  local cur = state.target and state.target.rangeState or nil
  local now = GetTime()
  if cur == self._zone then
    self._cand = NONE
    return
  end
  if cur ~= self._cand then
    self._cand, self._candSince = cur, now
    return
  end
  if now - self._candSince < SETTLE then return end
  local prev = self._zone
  self._zone, self._cand = cur, NONE
  local cue = RangeCues.Pick(prev, cur, p, RangeCues.GroupContext())
  if not cue then return end
  local gap = tonumber(p.cueRepeatSeconds) or RangeCues.REPEAT_DEFAULT
  if RangeCues.Quiet(cur, now, self._lastAny, self._lastZone, gap) then return end
  self._lastAny, self._lastZone[cur] = now, now
  play(p, cue)
end
