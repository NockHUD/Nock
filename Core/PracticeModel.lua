-- Core/PracticeModel.lua
-- The paper rotation: diziet559/rotationtools' shot-string layout in pure Lua (no WoW APIs).

local M = {}

M.GCD = 1.5

-- Notation: a = auto shot, s = Steady, m = Multi, A = Arcane, r = Raptor,
-- w = melee white hit. A string is walked left to right; each ability waits
-- for its own cooldown, then occupies its duration (rotationtools.py
-- add_rotation). The three efficiencies are the ones printed under every
-- diagram on the rotationtools page.
--
-- Notation (the keys Rotations/Profiles.lua uses) -> canonical string, from
-- standard_rotations.py. The test asserts Shorthand(str) == key for each.
M.CANONICAL = {
  ["1:1"]         = "as",
  ["1:2"]         = "asa",
  ["2:3"]         = "asaas",
  ["2:5"]         = "asaaasa",
  ["5:5:1:1"]     = "asmasasAasas",
  ["5:6:1:1"]     = "asAamasasasas",
  ["5:9:1:1"]     = "asasasaAaasasama",
  ["5:5:1:1 3w"]  = "asmawsaswasAaws",
  ["2:2 1w"]      = "asasw",
  ["6:9:1:1 3w"]  = "asamwasasawsasasawAa",
  ["6:11:1:1 3w"] = "asawsasamawasasaAawasa",
  ["3:7 2w"]      = "awasaawasaas",
}

--------------------------------------------------------------------------------
-- TEACHING strings (Round 5b). The canonical strings above are what
-- rotationtools would have you play; these are what a drill ladder hands a
-- player who has never woven, each one the previous rung plus exactly ONE more
-- ability. They are NOT rotationtools rotations and must never be resolved
-- from a bracket -- the only way to reach one is to load its drill.
--
-- KEY SCHEME: "drill <base beat>[+<the symbols this rung adds>]", in the
-- model's own notation letters. `drill 1:1` is the bare turret beat; `drill
-- 1:1+m` adds the Multi; `drill 1w` is the bare weave beat; `drill 1w+s` adds
-- the Steady. The key is what the header chip, the report and the grader's
-- window all print, so it has to read as a name rather than as a shorthand --
-- M.Shorthand deliberately does NOT round-trip these.
--
-- Each string is written FOR one effective weapon speed, and the pin travels
-- with it (TEACHING_EWS): a teaching string played at some other haste is not
-- the same lesson. Two rules decide every pin, both asserted in
-- Tests/practice_model_test.lua:
--   * the cycle must EXCEED the 1.5 s GCD, or the paper's own period is
--     GCD-bound and drifts off the swing by construction (the 1.34 s pin the
--     beat rung used to inherit from the 1:1 bracket reddened one cycle in
--     nine and no amount of playing could fix it);
--   * every cast must finish before the wind-up of its own cycle, and the
--     layout's period must come back within one wind-up of a whole number of
--     cycles, so the paper loops instead of walking.
--------------------------------------------------------------------------------
M.TEACHING = {
  -- TURRET, all at one tempo: same beat, one more button each rung.
  ["drill 1:1"]    = "as",
  ["drill 1:1+m"]  = "asasasasam",     -- Multi every 5th cycle (10.5 s >= its 10 s cd)
  ["drill 1:1+mA"] = "asaAasasaAam",   -- + Arcane every 3rd (6.3 s >= its 6 s cd)
  -- WEAVE, all at one (slow) tempo, because the melee swing sets the floor: a
  -- weave per cycle needs a cycle at least as long as the two-hander.
  ["drill 1w"]     = "aw",
  ["drill 1w+A"]   = "awAaw",          -- Arcane on the way out, every other cycle
  -- Rung 7 is rung 6 PLUS the Steady, not the Steady instead of the Arcane:
  -- the track is cumulative or it is not a ladder. Same two-cycle period as
  -- `drill 1w+A`, with a Steady added to each of them.
  ["drill 1w+s"]   = "aswAasw",
}

M.TEACHING_EWS = {
  ["drill 1:1"]    = 2.10,
  ["drill 1:1+m"]  = 2.10,
  ["drill 1:1+mA"] = 2.10,
  ["drill 1w"]     = 3.70,
  ["drill 1w+A"]   = 3.70,
  ["drill 1w+s"]   = 3.70,
}

-- One table for every consumer: the grader, the timeline and the conveyor all
-- look a window's notation up here and neither knows nor cares which half it
-- came from.
M.STRINGS = {}
for k, v in pairs(M.CANONICAL) do M.STRINGS[k] = v end
for k, v in pairs(M.TEACHING) do M.STRINGS[k] = v end

--------------------------------------------------------------------------------
-- THE BASIC PAPERS CARRY A MULTI IN PRACTICE (user, 2026-08-27, on the
-- opener drill: under Lust + Drums with Rapid Fire down the resolver lands on
-- 1:1 and the paper asked for nothing but Steadies). rotationtools, on the
-- basic rotations: "All basic rotations use only steady shot for illustration
-- purposes, but in practice should use multi shot instead of a steady shot
-- whenever it is off CD to slightly improve dps." Arcane is not part of the
-- rule (no GCD room for it at that haste). So M.CANONICAL keeps the
-- illustration and M.PaperString lays the practice paper AT A HASTE: the
-- base period repeated the first whole number of times that covers Multi's
-- cooldown, the last Steady of them the Multi -- every other notation is its
-- own string. Without a haste the illustration is returned; an unknown
-- notation is nil, like M.STRINGS. Allocates (a Layout): never per tick.
--------------------------------------------------------------------------------
M.MULTI_BASIC = { ["1:1"] = true, ["1:2"] = true, ["2:3"] = true, ["2:5"] = true }

function M.PaperString(notation, h)
  local base = notation and M.STRINGS[notation]
  if not (base and h and M.MULTI_BASIC[notation]) then return base end
  local dur = M.Layout(base, h, 0).dur
  local cd = h.multiCd or 10
  local n = (dur and dur > 0) and math.ceil(cd / dur - 1e-9) or 1
  if n < 1 then n = 1 end
  local s = string.rep(base, n)
  local last = s:match(".*()s")
  if not last then return s end
  return s:sub(1, last - 1) .. "m" .. s:sub(last + 1)
end

local function count(s, ch)
  local n = 0
  for i = 1, #s do
    if s:sub(i, i) == ch then n = n + 1 end
  end
  return n
end

-- rotationtools.py shorthand(): "steadies:autos[:multis:arcanes][ weaves w]".
function M.Shorthand(s)
  local autos, steadies = count(s, "a"), count(s, "s")
  local multis, arcanes = count(s, "m"), count(s, "A")
  local weaves = count(s, "w") + count(s, "r")
  local out = steadies .. ":" .. autos
  if multis > 0 or arcanes > 0 then
    out = out .. ":" .. multis .. ":" .. arcanes
  end
  if weaves > 0 then
    out = out .. " " .. weaves .. "w"
  end
  return out
end

-- castCorr is the measured residual on top of the haste multiplier (see
-- Nock.RangedCastTime); it applies to CASTS only, never to the wind-up.
function M.CastTime(base, rangedMul, castCorr)
  return base * (castCorr or 1) / rangedMul
end

-- THE PAPER'S WEAVE: how long a weave takes on paper (rotationtools' 0.4 s:
-- in, the hit, out). The plan fits a weave note into a cycle by THIS -- the
-- paper is the law -- while the grader judges the player's real legs. Fitting
-- by the measured legs (a 0.7-0.9 s seed before any weave has landed) never
-- fit a 2:2 1w's weave behind its Steady, and the note wandered forward
-- cycle after cycle (the sweep, 2026-08-26).
M.WEAVE_DUR = 0.4

-- abilities.py create() + change_haste(), with TBC cooldowns. dur = time the
-- ability occupies, cd = time after it before the same ability is available,
-- gcd = whether it spends the global cooldown. Cooldown numbers arrive on `h`
-- (Constants.PRACTICE in the addon) so this file stays free of Nock.Constants.
function M.Abilities(h)
  local rm, mm = h.rangedMul, h.meleeMul or 1
  local cc = h.castCorr or 1
  local windup = M.CastTime(0.5, rm)
  local arcCd = (h.arcaneCdBase or 6) - (h.arcaneCdPerPt or 0.2) * (h.imprArcanePts or 0)
  return {
    a = { dur = windup,             cd = h.ws / rm - windup,      gcd = false },
    s = { dur = M.CastTime(1.5, rm, cc), cd = nil,                gcd = true },
    m = { dur = M.CastTime(0.5, rm, cc), cd = h.multiCd or 10,    gcd = true },
    A = { dur = 0.1,                cd = arcCd,                   gcd = true },
    r = { dur = M.WEAVE_DUR,        cd = 6 - M.WEAVE_DUR,         gcd = false },
    w = { dur = M.WEAVE_DUR,        cd = (h.mws or 3.7) / mm - M.WEAVE_DUR, gcd = false },
    g = { dur = M.GCD,              cd = M.GCD,                   gcd = false },
  }
end

local ORDER = { "a", "g", "A", "m", "r", "w" }   -- ABILITIES_WITH_CD (+ s has none)

-- rotationtools.py add_rotation() + calc_dur() + complete_fig()'s efficiencies.
-- Returns a fresh result table; intended for per-fight work, not per tick.
function M.Layout(str, h, t0)
  t0 = t0 or 0
  local ab = M.Abilities(h)
  local avail, first, counts = {}, {}, {}
  for sym in pairs(ab) do avail[sym], first[sym], counts[sym] = 0, -1e-10, 0 end
  local t = 0
  local ev, delays = {}, {}
  local totalDelay = 0

  local function add(sym, advance)
    local a = ab[sym]
    if a.cd ~= nil and avail[sym] > t then t = avail[sym] end
    ev[#ev + 1] = { sym = sym, t0 = t0 + t, dur = a.dur }
    if advance then t = t + a.dur end
    -- Mirrors rotationtools.py's Ability.use() and calc_dur() quirk: reassign
    -- first_usage while negative, then add 1.5 if it's still negative at the end.
    if first[sym] < 0 then first[sym] = t - a.dur end
    if a.cd ~= nil then avail[sym] = t + a.cd end
    counts[sym] = counts[sym] + 1
  end

  for i = 1, #str do
    local c = str:sub(i, i)
    if c == "a" then
      local d = t - avail.a
      if d > 1e-6 then
        delays[#delays + 1] = { t0 = t0 + avail.a, dur = d }
        totalDelay = totalDelay + d
      end
      add("a", true)
    elseif c == "s" or c == "m" or c == "A" then
      add("g", false)
      add(c, true)
    elseif c == "r" or c == "w" then
      add(c, true)
    end
  end

  if first.g < 0 then first.g = first.g + M.GCD end  -- calc_dur()'s gcd fix-up
  local dur = t
  for _, sym in ipairs(ORDER) do
    if counts[sym] > 0 then
      local v = math.max(avail[sym], t) - first[sym]
      if v > dur then dur = v end
    end
  end

  local weaves = counts.r + counts.w
  local r = {
    ev = ev, delays = delays, dur = dur, delay = totalDelay, counts = counts,
    gcdEff  = counts.g * M.GCD / dur,
    autoEff = counts.a * (ab.a.dur + ab.a.cd) / dur,
    weaveEff = (weaves > 0) and (weaves * (ab.w.cd + ab.w.dur) / dur) or nil,
  }
  return r
end

--------------------------------------------------------------------------------
-- The drill's range bar, from the distance it knows. The live RangeEngine is
-- a dead-reckoning ESTIMATOR (speed integrated on a fixed yard scale, snapped
-- at every probe flip); in the drill the distance is the truth, so the bar is
-- a piecewise-linear map of it that keeps the engine's state names and its
-- values at every border — continuous, so the thumb never jumps:
--   LONG   d > 10            -> -1          (the finding ladder's territory)
--   CLOSE  10 >= d > ring    -> -0.9999 .. -SWEET_I
--   SWEET  ring >= d > melee -> -SWEET_I .. -0.0001   (PERFECT above -0.1)
--   MELEE  d <= melee        ->  0 .. 1   (1 at 0.5 yd, the reckoning floor)
-- `RE` is Modules/RangeEngine.lua (for SWEET_I); no engine instance needed.
--------------------------------------------------------------------------------
local function lerp(a, b, f) return a + (b - a) * f end
function M.RangeProg(RE, dist, inMelee, weaveRing, meleeRange)
  local sweetI = RE.SWEET_I
  if inMelee then
    local f = (meleeRange - dist) / (meleeRange - 0.5)
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    return "MELEE", f
  end
  if dist <= weaveRing then
    local f = (weaveRing - dist) / (weaveRing - meleeRange)
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    return "SWEET", lerp(-sweetI, -0.0001, f)
  end
  if dist <= 10 then
    local f = (10 - dist) / (10 - weaveRing)
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    return "CLOSE", lerp(-0.9999, -sweetI, f)
  end
  return "LONG", -1
end

-- Beyond ~10yd the live bar shows the finding ladder, resolved from item
-- range probes. The drill has no items to probe but knows the distance, so it
-- fills the same probe table from yards (the item reach values are the WA's
-- own — RangeEngine's ResolveBracket comments) and resolves the bracket the
-- live scan would. `r` is a reusable table (no per-tick allocation); `hawkEye`
-- and `scatterKnown` come from the live RangeFinder's CompileLadder so the
-- drill's ladder has the same rungs as the real one.
M.LADDER_YARDS = { i33069 = 15, i10645 = 20, i13289 = 25, i7734 = 30, i18904 = 35, i4945 = 40 }
M.SCATTER_YARDS = { [0] = 15, 17, 19, 21 }
M.HM_YARDS = 100
function M.LadderBracket(RE, r, dist, shootMax, hawkEye, scatterKnown, hmKnown)
  for key, yd in pairs(M.LADDER_YARDS) do r[key] = dist <= yd end
  r.autoShot = dist <= shootMax
  r.scatter  = scatterKnown and dist <= (M.SCATTER_YARDS[hawkEye or 0] or 15) or false
  r.hm       = hmKnown and (dist <= M.HM_YARDS) or nil
  return RE.ResolveBracket(r, hawkEye or 0, scatterKnown, hmKnown)
end

--------------------------------------------------------------------------------
-- WHAT A PAPER COSTS BY DESIGN. Some rotations clip on purpose (5:5:1:1 at
-- its floor holds the auto behind a Steady on four cycles in five) and some
-- ask for a weave in room a hunter's legs can barely make (the weave behind
-- the Steady on 5:5:1:1 3w at eWS 2.17 has 0.74 s). A player who does not
-- know that blames their hands; the ghost skips those weaves. So the paper
-- says so up front (user, 2026-08-26): the Scenarios card, the Lesson's
-- caption and the coach's ARMED line all read this.
--   str     the shot string (M.STRINGS[notation])
--   h       the model handle (ws, rangedMul, mws, ...)
--   stepIn  one leg of the weave, seconds (the grader's seed 0.35 by default)
-- Returns { clipMs, clipAutos, autos, periodDur, tightWeaves, weaves,
--           tightRoom (the smallest room of a tight weave), weaveNeed }
-- or nil for no string.
--------------------------------------------------------------------------------
M.TIGHT_MARGIN = 0.1        -- a weave with less than this to spare is tight

function M.PaperNotes(str, h, stepIn)
  if not (str and h) then return nil end
  stepIn = stepIn or 0.35
  local lay = M.Layout(str, h, 0)
  local ab = M.Abilities(h)
  local windup = ab.a.dur
  local out = {
    clipMs = math.floor((lay.delay or 0) * 1000 + 0.5),
    clipAutos = #(lay.delays or {}),
    autos = lay.counts.a or 0,
    periodDur = lay.dur,
    weaves = (lay.counts.w or 0) + (lay.counts.r or 0),
    tightWeaves = 0,
    tightRoom = nil,
    weaveNeed = stepIn * 2,
  }
  -- Every weave's room: from its slot to the next auto's wind-up start.
  local ev = lay.ev
  for i = 1, #ev do
    local e = ev[i]
    if e.sym == "w" or e.sym == "r" then
      local nextAuto
      for j = i + 1, #ev do
        if ev[j].sym == "a" then nextAuto = ev[j]; break end
      end
      local ws = nextAuto and nextAuto.t0 or (e.t0 + lay.dur)
      local room = ws - e.t0
      if room < out.weaveNeed + M.TIGHT_MARGIN then
        out.tightWeaves = out.tightWeaves + 1
        if not out.tightRoom or room < out.tightRoom then out.tightRoom = room end
      end
    end
  end
  return out
end

-- The notes as short sentences (ASCII). `tag` is the two-word chip, `text`
-- the explanation; nil, nil when the paper costs nothing by design.
function M.PaperNoteText(n)
  if not n then return nil, nil end
  local parts = {}
  local tag
  if n.clipMs > 20 then
    tag = "clips by design"
    parts[#parts + 1] = ("This paper clips on purpose: the auto waits %d ms per period behind its casts (%d of %d autos late). A planned wait is amber on the stage and is not your fault."):format(
      n.clipMs, n.clipAutos, n.autos)
  end
  if n.tightWeaves > 0 then
    tag = tag or "tight weave"
    parts[#parts + 1] = ("%s of its %d weaves %s a knife-edge: %.2f s of room for a step in and out of %.2f s. The ghost skips it; you may try."):format(
      n.tightWeaves == 1 and "One" or tostring(n.tightWeaves), n.weaves, n.tightWeaves == 1 and "is" or "are", n.tightRoom or 0, n.weaveNeed)
  end
  if not tag then return nil, nil end
  return tag, table.concat(parts, " ")
end

local Nock = rawget(_G, "Nock")
if Nock then Nock.PracticeModel = M end
return M
