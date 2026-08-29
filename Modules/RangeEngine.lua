-- Modules/RangeEngine.lua
-- Pure clamp-and-snap weave glide engine + finding-ladder bracket resolver
-- (no WoW APIs — testable under standalone LuaJIT via Tests/).
--
local Engine = {}

-- WA constants, verbatim. Tune only with in-game evidence.
Engine.SWEET_I   = 3.6 / 8.5  -- prog width of the SWEET band
Engine.SCALE     = 8.5        -- yards represented by one unit of prog
Engine.DIR_SPLIT = 4.5        -- yd/s; > = closing, <= = retreating
Engine.PERFECT_AT = -0.1      -- SWEET prog above this = PERFECT sliver

-- RESYNC tuning (Nock addition; dwell is the clamp-era replacement for the
-- old escaped-the-band test, which the clamp makes impossible).
Engine.RESYNC_DWELL  = 0.6    -- s pinned at a clamp edge while moving
Engine.STILL_S       = 0.25   -- s standing still ends a worn resync
Engine.TARGET_MOVING = 0.1    -- yd/s target speed that degrades the estimate
Engine.PLAYER_MOVING = 0.5    -- yd/s player speed considered "moving"

-- Mid-band pin values while degraded, so glide always resumes from a sane
-- estimate — never from drift garbage.
Engine.SEED = { LONG = -1, CLOSE = -0.71, SWEET = -0.212, MELEE = 0.1 }

-- In-place re-init: callable from per-tick paths (clearTarget runs every
-- tick while targetless) without allocating.
function Engine.Reset(s)
  s.state, s.prog, s.lastSpeed = "LONG", -1, 0
  s.resync, s.worn, s.pinned, s.still = false, false, 0, 0
end

function Engine.New()
  local s = {}
  Engine.Reset(s)
  return s
end

-- WA priority: outside ~10yd -> LONG; Wing Clip wins over the 7yd ring.
function Engine.Classify(close, sweet, melee)
  if not close then return "LONG" end
  if melee then return "MELEE" end
  if sweet then return "SWEET" end
  return "CLOSE"
end

-- Snap value for a state transition (epsilon-exact, WA verbatim).
local function snapFor(old, new)
  if new == "MELEE" then return 0.0 end
  if old == "MELEE" then return -0.0001 end          -- exit melee -> PERFECT sliver
  if new == "SWEET" then return -Engine.SWEET_I end  -- from either side
  if new == "CLOSE" then
    if old == "SWEET" then return -Engine.SWEET_I end
    return -0.9999                                   -- LONG -> CLOSE
  end
  return -1                                          -- -> LONG
end

-- One tick. Probe args are plain booleans (post-grace, nil-as-false like the
-- WA); speeds in yd/s; dt in seconds. Mutates s; allocates nothing.
function Engine.Step(s, close, sweet, melee, speed, targetSpeed, dt)
  local newState = Engine.Classify(close, sweet, melee)
  if newState ~= s.state then
    s.prog = snapFor(s.state, newState)
    s.state = newState
    s.resync, s.worn, s.pinned, s.still = false, false, 0, 0
  end

  -- Trapezoidal integration, WA verbatim.
  local dir = (speed > Engine.DIR_SPLIT) and 1 or -1
  s.prog = s.prog + ((s.lastSpeed + speed) / 2 / Engine.SCALE) * dt * dir
  s.lastSpeed = speed

  -- Clamp to the probe-proven band.
  local st = s.state
  if st == "LONG" then
    -- Finding mode owns everything beyond the ring; the glide is parked.
    s.prog = -1
    s.resync, s.worn, s.pinned, s.still = false, false, 0, 0
    return
  end
  local lo, hi
  if st == "CLOSE" then lo, hi = -0.9999, -Engine.SWEET_I
  elseif st == "SWEET" then lo, hi = -Engine.SWEET_I, -0.0001
  else lo, hi = 0, 1 end
  local clamped = false
  if s.prog < lo then s.prog, clamped = lo, true
  elseif s.prog > hi then s.prog, clamped = hi, true end

  -- RESYNC: worn latches when the integral rides a clamp edge while the
  -- player moves (tangential strafe — radial weave jitter never dwells).
  local moving = speed > Engine.PLAYER_MOVING
  if clamped and moving then
    s.pinned = s.pinned + dt
    if s.pinned > Engine.RESYNC_DWELL then s.worn = true end
  else
    s.pinned = 0
  end

  local tgtMoving = targetSpeed > Engine.TARGET_MOVING
  if s.worn or tgtMoving then
    s.prog = Engine.SEED[st]
    if not moving then
      -- You can't be strafing at zero speed: trust the seed after a beat.
      s.still = s.still + dt
      if s.still > Engine.STILL_S then s.worn = false end
    else
      s.still = 0
    end
  else
    s.still = 0
  end
  s.resync = s.worn or tgtMoving
end

-- ---------------------------------------------------------------------------
-- Zoomed glide fill (experimental, idea by Erda): a centered viewport crop of
-- the original (prog+1)/2 mapping. `zoom` is the magnification factor (>= 1;
-- nil = ZOOM_DEFAULT): the visible window is prog in [-1/zoom, 1/zoom],
-- stretched across the full bar — equivalently, (1 - 1/zoom)/2 of the fill is
-- shaven off EACH side (25% per side at 2x). Same layout, same centered
-- melee-boundary tick; every movement just reads `zoom` times bigger.
-- Outside the window the fill pegs empty/full (the shaven "dead space").
-- ---------------------------------------------------------------------------

Engine.ZOOM_DEFAULT = 2

function Engine.ZoomFill(prog, zoom)
  zoom = zoom or Engine.ZOOM_DEFAULT
  local f = zoom * (prog + 1) / 2 - (zoom - 1) / 2
  if f < 0 then return 0 elseif f > 1 then return 1 end
  return f
end

-- ---------------------------------------------------------------------------
-- Finding ladder: bracket resolver ported from the reference Range Check WA
-- (Kruffz, same wago export). Item yard values are the WA's comments — they
-- conflict with older Nock notes, so they are SEEDS until the in-game
-- calibration session (/nock range) signs them off (spec, "Calibration gate").
-- ---------------------------------------------------------------------------

-- Drain fill: fraction of distance remaining to the ~10yd handoff, from the
-- bracket midpoint over the 10..41 (Hawk Eye 3 max) domain.
local function fillFor(lo, hi)
  local f = ((lo + hi) / 2 - 10) / 31
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return f
end

-- Block-style colors, borrowed from the WA's color codes (not user-tunable).
local TEAL   = { 0.11, 0.70, 0.67, 1 }
local BLUE   = { 0.07, 0.50, 0.73, 1 }
local INDIGO = { 0.38, 0.40, 0.80, 1 }
local PURPLE = { 0.74, 0.28, 0.75, 1 }
local RED    = { 0.86, 0.31, 0.26, 1 }
local RED2   = { 1.00, 0.31, 0.26, 1 }

local function bracket(lo, hi, color)
  return { label = ("%d-%d YD"):format(lo, hi), fill = fillFor(lo, hi), block = color }
end

Engine.BRACKETS = {
  ["10_15"] = bracket(10, 15, TEAL),
  ["15_17"] = bracket(15, 17, TEAL),
  ["15_19"] = bracket(15, 19, TEAL),
  ["15_20"] = bracket(15, 20, TEAL),
  ["17_20"] = bracket(17, 20, TEAL),
  ["19_20"] = bracket(19, 20, TEAL),
  ["20_21"] = bracket(20, 21, BLUE),
  ["20_25"] = bracket(20, 25, BLUE),
  ["21_25"] = bracket(21, 25, BLUE),
  ["25_30"] = bracket(25, 30, BLUE),
  ["30_35"] = bracket(30, 35, INDIGO),
  ["35_37"] = bracket(35, 37, PURPLE),
  ["35_39"] = bracket(35, 39, PURPLE),
  ["35_40"] = bracket(35, 40, PURPLE),
  ["40_41"] = bracket(40, 41, PURPLE),
  ["OOR"]    = { label = "OUT OF RANGE",    fill = 1, block = RED  },
  ["HM_OOR"] = { label = "HM OUT OF RANGE", fill = 1, block = RED2 },
}

-- r: reusable table of probe booleans (nil-as-false, WA-style):
--   i13289 (~25yd) i33069 (~15) i10645 (~20) i18904 (~35) i7734 (~30)
--   i4945 (~40) autoShot scatter hm
-- hawkEye: talent rank 0-3. scatterKnown/hmKnown: spell availability.
-- Only called in finding mode (the ~10yd close probe already false).
function Engine.ResolveBracket(r, hawkEye, scatterKnown, hmKnown)
  if r.i13289 then                       -- inside ~25yd
    if not scatterKnown then
      if r.i33069 then return "10_15" end
      if r.i10645 then return "15_20" end
      return "20_25"
    end
    if hawkEye == 3 then                 -- Scatter reaches 21yd
      if r.i10645 then
        if r.i33069 then return "10_15" end
        return "15_20"
      end
      if r.scatter then return "20_21" end
      return "21_25"
    elseif hawkEye == 2 then             -- Scatter 19yd
      if r.scatter then
        if r.i33069 then return "10_15" end
        return "15_19"
      end
      if r.i10645 then return "19_20" end
      return "20_25"
    elseif hawkEye == 1 then             -- Scatter 17yd
      if r.scatter then
        if r.i33069 then return "10_15" end
        return "15_17"
      end
      if r.i10645 then return "17_20" end
      return "20_25"
    else                                 -- rank 0: Scatter 15yd
      if r.scatter then return "10_15" end
      if r.i10645 then return "15_20" end
      return "20_25"
    end
  end
  if r.i18904 then                       -- inside ~35yd
    if r.i7734 then return "25_30" end
    return "30_35"
  end
  if r.autoShot then                     -- shootable beyond 35: Hawk Eye edge
    if hawkEye == 3 then
      if r.i4945 then return "35_40" end
      return "40_41"
    elseif hawkEye == 2 then
      return "35_39"
    elseif hawkEye == 1 then
      return "35_37"
    end
    return "30_35"  -- rank 0: Auto Shot max IS 35; momentary probe disagreement
  end
  if hmKnown and r.hm == false then return "HM_OOR" end
  return "OOR"
end

local Nock = rawget(_G, "Nock")
if Nock then Nock.RangeEngine = Engine end
-- Per-slot out-of-range for the React grid's tint. `apiIn` is IsSpellInRange
-- as a tri-state (true / false / nil unknown); `meleeIn` is the Wing Clip
-- probe the same way. A next-melee ability (`isMelee`: Raptor Strike) answers
-- IsSpellInRange "in range" from 30 yd on this client, so it follows the
-- melee probe instead. Returns true (out), false (in) or nil (unknown).
function Engine.SlotOut(isMelee, apiIn, meleeIn)
  if isMelee then
    if meleeIn == nil then return nil end
    return not meleeIn
  end
  if apiIn == nil then return nil end
  return not apiIn
end

return Engine
