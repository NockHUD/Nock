-- Modules/PracticeLadder.lua
-- The drill ladder: ten drills on three tracks, each with a pass condition read off a finished scorecard.

-- Pure. No WoW API, no Nock globals at load — the glue in Modules/Practice.lua
-- hands it a scorecard and a progress table, and Tests/practice_ladder_test.lua
-- exercises the lot under standalone LuaJIT.
--
-- A drill is:
--   id      the key stored in the profile (`practiceLadder.done` / `.current`)
--   section which track it belongs to: TURRET / WEAVE / MASTERY
--   name    the ladder row's title
--   sub     the row's second line — what the drill is, in four words
--   pass    { text = the row's pass column, fn = function(score) -> boolean }
--   build   function(ctx) -> a spec the glue can LOAD, one of three shapes
--           plus a `len` (seconds) the glue caps the fight at:
--            { scenario = <a catalog row's name> }              — a row the catalog owns
--            { scenario = <name>, line = <a DSL line> }         — a scripted drill
--            { scenario = <name>, paper = { notation = <key> } } — a teaching paper
--          `scenario` is always the name the picker would set. `line` is
--          written in the scenario DSL (E.ParseScenario) so the palette, the
--          hold rules and the auto-stop behave exactly as they do for any other
--          scenario. `paper` names a M.TEACHING notation the DSL cannot state
--          (it has no notation= token); the glue builds the pinned paper row
--          from it, taking the haste from M.TEACHING_EWS.
--          `ctx` carries the character's own notations: { turret, weave }.
--          `spec.len` is the drill's own auto-stop, in seconds, and it OVERRIDES
--          whatever the scenario behind it says (a catalog paper row has no
--          len= at all, on purpose: picked by hand it is meant to run until you
--          stop it). The glue applies it to the ENGINE, never to the catalog
--          row, so the same scenario picked from the picker is untouched.
--
-- Round 5b: 1:1 straight to 5:5:1:1 was too big a step, so the ladder grew two
-- INCREMENTAL tracks — turret and weave — each ending on the character's own
-- rotation, with mastery after them. Each rung is the one under it plus exactly
-- one ability (Core/PracticeModel.lua's M.TEACHING).
local Ladder = {}

-- The empty ladder context, for a caller with none: `build` only ever reads
-- ctx.turret / ctx.weave and falls back on its own when they are missing.
local EMPTY_CTX = {}

-- 16 cycles is "long enough that it was not luck" — about 34 s at the turret
-- rungs' 2.10 s pin. A weave cycle is pinned to 3.70 s, so the same wall-clock
-- honesty costs half as many of them.
local MIN_CYCLES = 16
local MIN_WEAVE_CYCLES = 8

----------------------------------------------------------------------------
-- Score readers. Every one of them survives a nil/partial scorecard: a fight
-- that was cancelled hands back nothing, and a drill must never pass on it.
----------------------------------------------------------------------------

-- ok, total cycles on paper (the partial trailing cycle is already excluded by
-- G.Finish, so these are whole cycles).
local function cycles(s)
  local cp = s and s.cyclesOnPaper
  if not cp then return 0, 0 end
  return cp.ok or 0, cp.total or 0
end

-- The fraction of cycles that came out on paper, and the count it is over.
-- 0 cycles reads as 0 %, never as 100 %.
local function onPaper(s)
  local ok, total = cycles(s)
  if total <= 0 then return 0, 0 end
  return ok / total, total
end

-- Weaves hit over weave WINDOWS (the openings the grader counted), not over
-- presses: a window you never went for is a miss.
local function weaveHit(s)
  local taken = (s and s.weavesTaken) or 0
  local windows = taken + ((s and s.weavesMissed) or 0)
  if windows <= 0 then return 0, 0 end
  return taken / windows, windows
end

local function hasteWindows(s)
  local w = s and s.windows
  return w and #w or 0
end

----------------------------------------------------------------------------
-- The scenarios the drills load. Names are the catalog's own — a paper drill
-- is named for its rotation (Rotations/Profiles.lua), a script for its line.
----------------------------------------------------------------------------

local OPENER_SCRIPT = "Lust + RF + Drums"      -- E.SCENARIOS built-in

-- The six teaching papers, by the M.TEACHING key that IS their scenario name.
-- The ladder names them and nothing else: the pinned haste travels with the
-- string (M.TEACHING_EWS), so a rung cannot drift from the paper it teaches.
local T_BEAT   = "drill 1:1"
local T_MULTI  = "drill 1:1+m"
local T_ARCANE = "drill 1:1+mA"
local W_BEAT   = "drill 1w"
local W_OUT    = "drill 1w+A"
local W_SHOT   = "drill 1w+s"

-- The one drill the catalog does not already own: the weave rotation with the
-- haste actually MOVING under it. Quick Shots at 5 s and Rapid Fire at 15 s
-- open two more haste windows inside 45 s, which is the thing being drilled —
-- so no lock=/ews= pin here, on purpose. The name is the scenario's name.
local RHYTHM_NAME = "Rhythm changes"
local RHYTHM_LEN  = 45
local RHYTHM_LINE = ("%s: qs@5 rf@15 len=%d"):format(RHYTHM_NAME, RHYTHM_LEN)

-- ROUND 6c: A TEACHING DRILL IS A TIMED ATTEMPT. Every rung is capped so the
-- review lands while the attempt is still fresh in the fingers -- an uncapped
-- drill ran until the player remembered to press Stop, by which point the fault
-- being drilled was four minutes back. `rhythm` keeps the 45 s its own script
-- states (two haste windows is the whole drill and they are scheduled inside
-- it). Free play left the ladder on 2026-08-27 (user): a rung that never
-- passes is not a rung, and the Scenarios page already offers it.
--
-- 60 s is comfortably more than double every pass minimum at every rung's own
-- pin -- the tightest is `french` at 5:5:1:1, whose 1.93 pin yields ~28 whole
-- cycles against a 16-cycle floor, and the weave rungs' 3.70 pin yields ~16
-- against 8 cycles / 5 windows. Measured off M.Layout at each pin; see the
-- round-6 report.
local DRILL_LEN = 60

local function pick(scenario, line, len)
  return { scenario = scenario, line = line, len = len }
end

-- A teaching paper: the notation key is also the catalog row's name, exactly
-- as it is for every other paper drill in the catalog.
local function paper(notation, len)
  return { scenario = notation, paper = { notation = notation }, len = len }
end

----------------------------------------------------------------------------
-- The pass conditions, one function per FAMILY rather than one per rung: the
-- three turret teaching rungs and the full turret ask for the same thing, and
-- so do the four weave rungs.
----------------------------------------------------------------------------

-- Turret: nine cycles in ten on paper, over enough of them to mean it.
local TURRET_TEXT = "90% cycles / 16"
local function turretPass(s)
  local pct, total = onPaper(s)
  return total >= MIN_CYCLES and pct >= 0.90
end

-- The first rung keeps its own identity on top of that: not one Steady may run
-- into the wind-up. It is the only rung where a clip is fatal, because holding
-- the beat is the only thing it asks.
local BEAT_TEXT = "0 clips + 90% / 16"
local function beatPass(s)
  return turretPass(s) and ((s and s.clips) or 0) == 0
end

-- Weave: a weave out of four windows in five AND the shots behind them still
-- on paper. A weave taken out of every window is worth nothing if the rotation
-- fell apart around it.
--
-- The window count is its own floor, not a by-product of the cycle count: a
-- short low-density fight can open two windows, take both, and read 5/5 on a
-- ratio that proves nothing. Five is the fewest that makes the 4/5 mean what
-- it says — one miss.
local MIN_WEAVE_WINDOWS = 5
local WEAVE_TEXT = "4/5 weaves + 85%"
local function weavePass(s)
  local hit, windows = weaveHit(s)
  if windows < MIN_WEAVE_WINDOWS or hit < 0.8 then return false end
  local pct, total = onPaper(s)
  return total >= MIN_WEAVE_CYCLES and pct >= 0.85
end

----------------------------------------------------------------------------
-- The ten drills, in ladder order: TURRET, then WEAVE, then MASTERY.
----------------------------------------------------------------------------

local TURRET, WEAVE, MASTERY = "TURRET", "WEAVE", "MASTERY"
Ladder.SECTIONS = { TURRET, WEAVE, MASTERY }

Ladder.DRILLS = {
  {
    id = "beat", section = TURRET, name = "Hold the beat", sub = "1:1 - one Steady per auto",
    pass = { text = BEAT_TEXT, fn = beatPass },
    build = function() return paper(T_BEAT, DRILL_LEN) end,
  },
  {
    id = "multi", section = TURRET, name = "Add Multi", sub = "1:1 + Multi every 5th",
    pass = { text = TURRET_TEXT, fn = turretPass },
    build = function() return paper(T_MULTI, DRILL_LEN) end,
  },
  {
    id = "arcane", section = TURRET, name = "Add Arcane", sub = "1:1 + Multi + Arcane every 3rd",
    pass = { text = TURRET_TEXT, fn = turretPass },
    build = function() return paper(T_ARCANE, DRILL_LEN) end,
  },
  {
    -- The character's OWN turret rotation, at the haste its bracket names --
    -- what the three rungs under it were building up to. This is the rung the
    -- old ladder called "multi" / "Add Multi & Arcane".
    -- (The sub is filled in by Practice:LadderItems with the bracket's own
    -- notation and "your haste": the rung under it is the same exercise at a
    -- pinned haste and an even instant cadence -- user, 2026-08-26.)
    id = "french", section = TURRET, name = "Full turret", sub = "your rotation at your haste",
    pass = { text = TURRET_TEXT, fn = turretPass },
    build = function(ctx) return pick((ctx and ctx.turret) or T_BEAT, nil, DRILL_LEN) end,
  },
  {
    id = "weave-beat", section = WEAVE, name = "Weave the beat", sub = "in, hit, out",
    pass = { text = WEAVE_TEXT, fn = weavePass },
    build = function() return paper(W_BEAT, DRILL_LEN) end,
  },
  {
    id = "weave-out", section = WEAVE, name = "Weave + Arcane", sub = "+ Arcane on the way out",
    pass = { text = WEAVE_TEXT, fn = weavePass },
    build = function() return paper(W_OUT, DRILL_LEN) end,
  },
  {
    id = "weave-shot", section = WEAVE, name = "Weave + Steady", sub = "+ Steady before the gap",
    pass = { text = WEAVE_TEXT, fn = weavePass },
    build = function() return paper(W_SHOT, DRILL_LEN) end,
  },
  {
    -- The rung the old ladder called "weave" / "Add the weave".
    id = "weave-full", section = WEAVE, name = "Full weave", sub = "weave notation",
    pass = { text = WEAVE_TEXT, fn = weavePass },
    build = function(ctx) return pick((ctx and ctx.weave) or W_BEAT, nil, DRILL_LEN) end,
  },
  {
    id = "rhythm", section = MASTERY, name = "Rhythm changes", sub = "Hawk - Rapid Fire",
    pass = {
      text = "85% + 2 windows",
      -- Two windows is the point of the drill: holding the rotation together
      -- through ONE haste is not a rhythm change.
      fn = function(s)
        local pct, total = onPaper(s)
        return total > 0 and pct >= 0.85 and hasteWindows(s) >= 2
      end,
    },
    build = function() return pick(RHYTHM_NAME, RHYTHM_LINE, RHYTHM_LEN) end,
  },
  {
    id = "opener", section = MASTERY, name = "Opener + cooldowns", sub = "pull - lust - drums",
    pass = {
      text = "opener OK",
      -- G.Finish's own verdict: the Steady inside its window and every listed
      -- cooldown inside the anchor's GCDs.
      fn = function(s) return (s and s.opener and s.opener.ok) and true or false end,
    },
    build = function() return pick(OPENER_SCRIPT, nil, DRILL_LEN) end,
  },
}

Ladder.FIRST = Ladder.DRILLS[1].id
Ladder.LAST = Ladder.DRILLS[#Ladder.DRILLS].id

local BY_ID = {}
for i = 1, #Ladder.DRILLS do BY_ID[Ladder.DRILLS[i].id] = Ladder.DRILLS[i] end

function Ladder.ById(id) return id and BY_ID[id] or nil end

-- The auto-stop the drill asks for, in seconds, or nil for an endless one.
-- Read off `build` rather than declared a second time: a rung whose
-- cap disagreed with the scenario it loads is exactly the drift the spec shape
-- exists to prevent. Called once per pull, never per tick.
function Ladder.LenFor(id, ctx)
  local d = Ladder.ById(id)
  if not d then return nil end
  local spec = d.build(ctx or EMPTY_CTX)
  return spec and spec.len or nil
end

----------------------------------------------------------------------------
-- Fault code -> the drill that trains it. The review's fix cards (Task 7) read
-- this; it lives here so there is one mapping and not two.
--
-- A code with no entry gets no drill button rather than a wrong one.
--
-- The keys are FAULT codes -- the ones PracticeGrader's ADVICE table names, the
-- only ones that can reach a review's fix card. `OFF` and `MISSED` are per-note
-- JUDGMENT grades, never codes, so entries for them were dead rows; a judgment
-- has no card and asks this map nothing. Round 5b asked for "a cast the paper
-- wanted and did not get -> multi/arcane"; the codes that actually SAY that are
-- CATCHUP_MISSED (you took the Steady where the Multi was the shot) and
-- STEADY_WONT_FIT (the Steady does not fit, take the Multi or Arcane that
-- does). Both were unmapped before, because until now no rung taught them.
----------------------------------------------------------------------------

Ladder.DRILL_FOR = {
  CLIP = "beat", LATE = "beat",
  CATCHUP_MISSED = "multi", STEADY_WONT_FIT = "arcane",
  -- The footwork faults land on the bare weave beat: getting in and back out
  -- is the whole of that rung. The re-arm is the one that only bites once
  -- there is a cast next to the weave, so it lands on the rung that has one.
  WEAVE_MISSED = "weave-beat", WEAVE_SLOW = "weave-beat", DEAD_ZONE = "weave-beat",
  REARM = "weave-shot",
  -- The opener's own code (G.Feed's `cd` branch): a cooldown popped before the
  -- anchor.
  EARLY = "opener",
}

function Ladder.DrillFor(code)
  return code and Ladder.DRILL_FOR[code] or nil
end

----------------------------------------------------------------------------
-- Progress. `state` is the profile's own table:
--   { done = {}, current = <id>, loaded = <id|nil>, v = <schema version> }
----------------------------------------------------------------------------

-- Round 5b split the six-rung ladder into eleven. Two old ids have to be
-- carried across, and one of them CHANGED MEANING, so the map cannot be
-- applied blind -- hence the version stamp.
--
--   old `beat`  -> new `beat`     (same rung: 1:1, no weave)
--   old `multi` -> `multi`, `arcane`, `french`
--   old `weave` -> `weave-beat`, `weave-out`, `weave-shot`, `weave-full`
--
-- The fan-out is the honest direction: old `multi` WAS the full turret
-- notation, and someone who held 5:5:1:1 together for twenty cycles has
-- already done everything the two teaching rungs under it ask for. Marking
-- them done costs that player nothing; making them re-earn a rung they have
-- demonstrably passed is the rudeness. `weave` is the same argument.
--
-- Without the stamp this would be wrong in the other direction: a player who
-- passes the NEW `multi` (1:1 + Multi) would have `arcane` and `french` handed
-- to them on the next login, because the map cannot tell an old key from a new
-- one by name alone.
--
-- V3 (2026-08-27): `free` left the ladder. The stamp keeps the v2 fan-out from
-- running a second time on a v2 state (a new-meaning `multi` would hand
-- `arcane` and `french` over); the generic sweep below drops the stale id and
-- a `current` that pointed at it moves to the first rung left to do.
Ladder.VERSION = 3

local MIGRATE_V2 = {
  multi = { "multi", "arcane", "french" },
  weave = { "weave-beat", "weave-out", "weave-shot", "weave-full" },
}

-- Never throws on old data: a `done` table full of ids no drill answers to, a
-- `current` that was renamed away, a state with no `done` at all.
function Ladder.Migrate(state)
  if not state then return nil end
  if state.v == Ladder.VERSION then return state end
  local done = state.done
  if done then
    if (state.v or 0) < 2 then
      for old, list in pairs(MIGRATE_V2) do
        if done[old] then
          for i = 1, #list do done[list[i]] = true end
        end
      end
    end
    -- An id no rung answers to any more is dropped rather than kept as a
    -- silent passenger: NextTodo walks the DRILLS list, so a stale key can
    -- never be read again, and leaving it would only make a later migration
    -- ambiguous.
    for k in pairs(done) do
      if not BY_ID[k] then done[k] = nil end
    end
  else
    state.done = {}
  end
  if state.current == nil or not BY_ID[state.current] then
    state.current = Ladder.NextTodo(state) or Ladder.LAST
  end
  if state.loaded ~= nil and not BY_ID[state.loaded] then state.loaded = nil end
  state.v = Ladder.VERSION
  return state
end

-- The first drill that is not done yet, in ladder order. nil when every one of
-- them is: the ladder then rests on its last rung (Evaluate keeps `current`).
function Ladder.NextTodo(state)
  local done = state and state.done
  for i = 1, #Ladder.DRILLS do
    local id = Ladder.DRILLS[i].id
    if not (done and done[id]) then return id end
  end
  return nil
end

-- One finished fight against one drill's pass condition. `id` is the drill the
-- fight actually RAN (the glue remembers it at load); it defaults to the
-- current one. Returns true when the drill was just passed.
--
-- The advance is guarded on `id == state.current`: replaying an earlier drill
-- must not drag the ladder backwards, and passing a drill the player jumped
-- ahead to must not skip the ones under it.
function Ladder.Evaluate(state, score, id)
  if not state then return false end
  if state.done == nil then state.done = {} end
  if state.current == nil then state.current = Ladder.FIRST end
  local drillId = id or state.current
  local d = Ladder.ById(drillId)
  if not (d and d.pass and d.pass.fn) then return false end
  if not d.pass.fn(score) then return false end
  local already = state.done[drillId] and true or false
  state.done[drillId] = true
  if drillId == state.current then
    state.current = Ladder.NextTodo(state) or state.current
  end
  return not already
end

-- Wipe the progress back to the first drill, and let go of the loaded one — a
-- reset that left the header still naming a drill would be claiming progress it
-- had just thrown away. The table itself is kept: it is the profile's, and
-- other references (the panel's) point at it.
function Ladder.Reset(state)
  if not state then return end
  local done = state.done
  if done then
    for k in pairs(done) do done[k] = nil end
  else
    state.done = {}
  end
  state.current, state.loaded = Ladder.FIRST, nil
  -- A wiped ladder is already in the current schema: stamping it here keeps
  -- Migrate from walking an empty table on every login for the rest of time.
  state.v = Ladder.VERSION
  return state
end

----------------------------------------------------------------------------
-- The rows the lesson window's side panel draws (View:SetLadder). One reused
-- array of eleven reused rows: the ladder is repainted on every practice
-- message, and eleven fresh tables a message is eleven tables of garbage for
-- nothing.
--
-- `row.section` carries the track's title on the FIRST row of each track and
-- nil on every other, so the view can draw a header without knowing what a
-- track is or how many there are — it walks the rows and draws a header
-- wherever it finds one.
----------------------------------------------------------------------------

local ITEMS = {}

function Ladder.Items(state, out)
  out = out or ITEMS
  local done = state and state.done
  local current = (state and state.current) or Ladder.FIRST
  local lastSection = nil
  for i = 1, #Ladder.DRILLS do
    local d = Ladder.DRILLS[i]
    local row = out[i]
    if not row then row = {}; out[i] = row end
    row.id, row.name, row.sub = d.id, d.name, d.sub
    if d.section ~= lastSection then row.section = d.section else row.section = nil end
    lastSection = d.section
    row.pass = d.pass and d.pass.text or ""
    if done and done[d.id] then row.state = "done"
    elseif d.id == current then row.state = "cur"
    else row.state = "todo" end
  end
  for i = #out, #Ladder.DRILLS + 1, -1 do out[i] = nil end
  return out
end

local Nock = rawget(_G, "Nock")
if Nock then Nock.PracticeLadder = Ladder end
return Ladder
