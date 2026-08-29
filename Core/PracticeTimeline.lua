-- Core/PracticeTimeline.lua
-- Pure builder: engine events + scorecard windows -> timeline lanes and verdict marks (no WoW APIs).

local T = {}

T.COLORS = {
  a = { 0.85, 0.85, 0.85 }, s = { 0.35, 0.65, 1.0 }, m = { 1.0, 0.6, 0.2 }, A = { 0.8, 0.4, 1.0 },
  r = { 1.0, 0.3, 0.3 }, w = { 0.9, 0.9, 0.9 }, g = { 0.4, 0.4, 0.4 },
  QS = { 0.3, 1.0, 0.4 }, RF = { 1.0, 0.85, 0.2 }, Lust = { 1.0, 0.3, 0.3 }, Drums = { 0.7, 0.5, 0.3 },
  DST = { 0.5, 0.8, 1.0 }, Pot = { 0.9, 0.4, 0.9 }, KC = { 1.0, 0.5, 0.1 },
  good = { 0.3, 1.0, 0.3 }, warn = { 1.0, 0.8, 0.2 }, bad = { 1.0, 0.3, 0.3 },
  wait = { 0.85, 0.72, 0.4 },   -- an auto the paper's own cast held back (a planned clip)
  move = { 0.55, 0.75, 0.85 },  -- a stretch the feet moved (the combat log's MOVE row)
}
-- The engine's range zones as the one word the MOVE row writes at a change.
T.ZONE_LABEL = { SWEET = "melee", DEEP = "melee", WEAVE = "ring", FAR = "far", GAP = "gap", OUT = "out" }
-- THE STAGE'S STYLE LEVERS (P3 polish). One definition, read by three places:
-- the conveyor (UI/Frame_PracticeConveyor.lua ApplyStyle), Options (the Stage
-- style block) and `/nock practice style`. `lever` is the slash word, `key` the
-- profile key, `values` the allowed set with the default FIRST. Every lever is a
-- visual decision only.
T.STYLE_LEVERS = {
  { lever = "note",   key = "practiceStyleNote",        name = "Note body",
    values = { "glass", "solid", "outline" },
    desc = "glass: tinted fill, coloured edge, the icon carries it. solid: the P3 block. outline: hollow until it is next." },
  { lever = "next",   key = "practiceStyleNext",        name = "Next press",
    values = { "both", "bright", "chip", "word" },
    desc = "both: the next note brightens, the rest dim, a NEXT chip with the key sits above it. bright / chip: one of the two. word: the P3 word inside the note." },
  { lever = "move",   key = "practiceStyleMove",        name = "Move-in",
    values = { "ramp", "solid", "edge" },
    desc = "The step-in ahead of a weave. ramp: a gradient rising to the hit. solid: the P3 band. edge: a single leave mark." },
  { lever = "hit",    key = "practiceStyleHit",         name = "Hit line",
    values = { "column", "line" },
    desc = "column: a soft NOW column with the line. line: the line and its glow (P3)." },
  { lever = "past",   key = "practiceStylePast",        name = "Played notes",
    values = { "fade", "keep" },
    desc = "fade: a played note dims behind the hit line, the pop is the verdict. keep: it stays bright." },
  { lever = "lanes",  key = "practiceStyleLanes",       name = "Lanes",
    values = { "zebra", "lines", "none" },
    desc = "zebra: alternating row tints. lines: a hairline under each row. none." },
  { lever = "tick",   key = "practiceStyleAutoTick",    name = "Release tick",
    values = { "hairline", "notch", "bar" },
    desc = "The auto release on its row. hairline: 1 px. notch: a short mark. bar: the P3 full-height bar." },
  { lever = "windup", key = "practiceStyleWindup",      name = "Wind-up wash",
    values = { "faint", "normal", "strong", "off" },
    desc = "How loud the wind-up band is on the auto row." },
  { lever = "scope",  key = "practiceStyleWindupScope", name = "Wind-up reaches",
    values = { "auto", "cast", "all" },
    desc = "auto: the auto row only. cast: down through the shot rows (do not be casting here). all: every row." },
}
T.STYLE_BY_LEVER = {}
for _, L in ipairs(T.STYLE_LEVERS) do
  T.STYLE_BY_LEVER[L.lever] = L
  L.allowed = {}
  for _, v in ipairs(L.values) do L.allowed[v] = true end
end
T.SEVERITY = { GOOD = "good", WEAVE_OK = "good", REARM_PLANNED = "wait", LATE = "warn", REARM = "warn", WEAVE_SLOW = "warn", EARLY = "warn",
               CLIP = "bad", STEADY_WONT_FIT = "bad", CATCHUP_MISSED = "bad", WEAVE_MISSED = "bad", DEAD_ZONE = "bad" }
local SYM = { steady = "s", multi = "m", arcane = "A" }

--------------------------------------------------------------------------------
-- JUDGMENT POPS
--
-- A `judge` verdict (PracticeGrader) is one paper NOTE's grade. It never reaches
-- the mark row or the fault list; it surfaces as a POP -- a word that rises off
-- the note's frame and fades. T.Strip collects the live ones into `out.pops`.
--------------------------------------------------------------------------------

-- How long a pop lives. The view's rise-and-fade runs over exactly this, so the
-- two must not drift: the animation's progress is (now - pop.t) / T.POP_LIFE.
T.POP_LIFE = 1.1
local POP_LIFE = T.POP_LIFE

-- The word per grade, as a CONSTANT string: a pop's text is read several times
-- a second and only CLIP carries a number (cached on the verdict, see popText).
T.JUDGE_TEXT = { PERFECT = "PERFECT", GOOD = "GOOD", LATE = "LATE", MISSED = "MISSED", OFF = "OFF" }
-- Colour band per grade, in T.SEVERITY's own vocabulary (T.COLORS.good/warn/bad),
-- so a view colours a pop and a mark through one table. LATE is the only amber
-- one: the press landed, just not on the beat. CLIP cost a shot, MISSED lost the
-- note outright and OFF played something the paper never asked for.
T.JUDGE_SEV = { PERFECT = "good", GOOD = "good", LATE = "warn", CLIP = "bad", MISSED = "bad", OFF = "bad" }

-- The pop's text. Constant for every grade but CLIP, whose ms is per-verdict:
-- formatted ONCE and kept on the verdict itself (`_text`), because a pop is
-- rebuilt on every tick it is alive for and a per-tick format is a per-tick
-- allocation. An unknown grade falls back to its own name -- still a constant
-- string, since it came off the verdict.
local function popText(v)
  local s = T.JUDGE_TEXT[v.grade]
  if s then return s end
  if v.grade ~= "CLIP" then return v.grade or "?" end
  s = v._text
  if not s then
    s = "CLIP +" .. math.floor((v.deltaMs or 0) + 0.5) .. " ms"
    v._text = s
  end
  return s
end

-- The narrowest a CAST may be DRAWN. An Arcane Shot is instant and a Multi at
-- speed is a quarter-second, so at any readable scale their true spans came out
-- one or two pixels wide -- an icon-less sliver you cannot see, let alone click.
-- Only the drawn `t1` moves: the event's own times are never touched, so nothing
-- that grades, anchors or projects off them shifts by a millisecond.
T.MIN_CAST_DRAW = 0.35
local MIN_CAST_DRAW = T.MIN_CAST_DRAW
local function castT1(t0, t1)
  local floor = t0 + MIN_CAST_DRAW
  if not t1 or t1 < floor then return floor end
  return t1
end
-- Which layout symbols the floor applies to: the things you CAST. An `a` is the
-- wind-up (its `t1` is the release, and at speed the whole span is under 0.35 s
-- -- widening it would move the shot), and `r`/`w` are weave slots, not presses.
local CAST_SYM = { s = true, m = true, A = true }

local function push(lane, t0, t1, sym, label, color)
  lane[#lane + 1] = { t0 = t0, t1 = t1, sym = sym, label = label, color = color or sym }
end

--------------------------------------------------------------------------------
-- THE PAPER IS THE SCOPE, on the WEAVE lane (Round 4).
--
-- The engine's melee half keeps running on a turret drill -- the swing is real,
-- the opportunity window really does open -- and the strip drew all of it: the
-- green gap band, the swing-ready tick, the Raptor-ready mark. On a 1:1 or
-- 5:5:1:1 paper that is a lane full of instructions for a shot the rotation
-- never asks for, which is the same nag D1 took out of the faults, the metronome
-- and the WEAVES tile. It belongs at the PURE layer, not in a view: two views
-- draw these items and the rule is one rule.
--
-- What is gated is the PLAN. Facts are not: a melee hit the player actually
-- landed stays on the lane whatever the paper says (an off-paper Raptor is a
-- thing that happened, and the grader already calls it OFF).
--
-- `paperSyms` is the grader's own per-notation symbol set, published by
-- Practice:Lookahead onto the live snapshot -- the very table Nock.PaperAllows
-- gates on. Absent (a live game, a test with no paper) everything is allowed:
-- outside a practice fight there is no paper to be off.
local function paperWeaves(live)
  local ps = live and live.paperSyms
  if ps == nil then return true end
  return (ps.w or ps.r) and true or false
end

--------------------------------------------------------------------------------
-- THE BAND FOLLOWS WHAT IS ACHIEVABLE (R5c).
--
-- The green gap band is the room you have for a weave. It used to be `now` to
-- the wind-up, drawn only while the engine's `oppOpen` flag was true — a test
-- made at `now`, which is the wrong shape for something drawn ahead of the
-- cursor. It told you nothing about the NEXT window, and after one slow weave
-- (`legsNeeded` is the player's own measured footwork, fed back) the flag could
-- stop going true altogether while the paper went on writing a `w` every few
-- cycles: a lane of instructions with no window to serve them.
--
-- So the band takes the engine's own answer to "when next, and how much room"
-- (E.WeaveWindow, published as `weaveAt`/`weaveTtw`), which may open in the
-- FUTURE — that is the whole point. The old now-anchored pair is the fallback
-- for a snapshot that carries no window (a test, an older glue).
--
-- The paper's `w` note keeps its own slot either way: where the two disagree
-- the band is the one telling the truth about the swing, and the grader is free
-- to fault the slot that could not be served.
--
-- The third return is TIGHT: the engine had no window a whole weave fits in and
-- answered with the roomiest one there is. A band drawn the same as a real gap
-- would be an invitation to a weave that cannot land, so it is drawn thinner
-- and dimmer and the coach says so outright.
local function weaveBand(live, now)
  local at, room = live.weaveAt, live.weaveTtw
  if at and room and room > 0 then return at, room, (live.weaveFits == false) end
  if live.oppOpen and live.ttw and live.ttw > 0 then return now, live.ttw, false end
  return nil
end

-- events[1..n] from the engine, score from PracticeGrader.Finish (windows +
-- verdicts), h the model handle, opts.windup (seconds at base haste; the paper
-- lane is re-seated per window with that window's rangedMul). Returns a fresh
-- table; once per fight (and at most a few Hz in live mode).
function T.Build(events, n, score, h, opts, verdicts)
  opts = opts or {}
  local tl = { lanes = { paper = {}, auto = {}, cast = {}, melee = {}, procs = {}, move = {} }, marks = {}, zones = {} }
  local t0, t1 = nil, nil
  local procStart = {}
  for i = 1, n do
    local ev = events[i]
    if ev.kind == "pull" then t0 = ev.t
    elseif ev.kind == "stop" or ev.kind == "end" then t1 = t1 or ev.t
    elseif ev.kind == "auto" then
      -- The wind-up the shot actually made when the event carries it (a shot
      -- held by range or a cast wound up later than one grid length before
      -- its release); the flat windup only for streams without it.
      push(tl.lanes.auto, ev.windupAt or (ev.t - (opts.windup or 0)), ev.t, "a", (ev.delay and ev.delay > 0.03) and ("+" .. math.floor(ev.delay * 1000 + 0.5) .. " ms") or nil,
           (ev.clip == "fault") and "bad" or "a")
    elseif ev.kind == "cast" and not ev.cancelled then
      local sym = SYM[ev.spell] or "s"
      push(tl.lanes.cast, ev.t0, castT1(ev.t0, ev.t1), sym, nil, sym)
    elseif ev.kind == "cast" and ev.cancelled then
      push(tl.lanes.cast, ev.t0, castT1(ev.t0, ev.t1), SYM[ev.spell] or "s", "cancelled", "g")
    elseif ev.kind == "melee" then
      push(tl.lanes.melee, ev.t - 0.2, ev.t, ev.hit, (ev.hit == "r") and "Raptor" or nil, ev.hit)
    elseif ev.kind == "kc" then
      push(tl.lanes.melee, ev.t - 0.1, ev.t + 0.1, "KC", "KC", "KC")
    elseif ev.kind == "proc" then
      if ev.on then procStart[ev.name] = ev.t
      else
        push(tl.lanes.procs, procStart[ev.name] or ev.t, ev.t, ev.name, ev.name, ev.name)
        procStart[ev.name] = nil
      end
    elseif ev.kind == "cd" and ev.used then
      push(tl.lanes.procs, ev.t - 0.1, ev.t + 0.1, ev.key, ev.key, (ev.key == "RF" and "RF") or (ev.key == "Drums" and "Drums") or (ev.key == "Pot" and "Pot") or "g")
    -- The feet: a stretch of movement (real, or a key-only footwork leg) on
    -- the MOVE lane, and every range change as a zone mark on it.
    elseif ev.kind == "move" then
      push(tl.lanes.move, ev.t0, ev.t1, "mv", ev.key and "step" or nil, "move")
    elseif ev.kind == "range" and ev.zone then
      tl.zones[#tl.zones + 1] = { t = ev.t, zone = ev.zone, label = T.ZONE_LABEL[ev.zone] or ev.zone, inMelee = ev.inMelee }
    end
  end
  -- The fight's ORIGIN, or nothing. A stream with no `pull` in it has no zero to
  -- count from, and the old `or 0` turned that into one: every relative stamp
  -- built off it then rendered the raw GetTime() clock (305232320.92 s in the
  -- review's issue list). The first event is a fair origin; a literal zero is
  -- not, so `tl.t0` stays nil and the views draw an em dash instead.
  t0 = t0 or (events[1] and (events[1].t or events[1].t0))
  t1 = t1 or (n > 0 and (events[n].t or events[n].t1)) or t0
  for name, s in pairs(procStart) do push(tl.lanes.procs, s, t1, name, name, name) end
  tl.t0, tl.t1 = t0, t1
  -- Paper lane: the ideal stream per haste window, re-seated at each window's
  -- start with that window's haste (PracticeModel.Layout at rangedMul).
  local model = opts.model
  if model and score and score.windows then
    for _, w in ipairs(score.windows) do
      local hw = {}
      for k, v in pairs(h) do hw[k] = v end
      hw.rangedMul = w.rangedMul
      local str = (model.PaperString and model.PaperString(w.notation, hw)) or model.STRINGS[w.notation] or "as"
      local lay = model.Layout(str, hw, 0)
      local wt1 = w.t1 or t1
      local cycleStart = w.t0
      while cycleStart < wt1 and lay.dur > 0 do
        for _, pe in ipairs(lay.ev) do
          if pe.sym ~= "g" and cycleStart + pe.t0 < wt1 then
            local pt0 = cycleStart + pe.t0
            local pt1 = pt0 + pe.dur
            if CAST_SYM[pe.sym] then pt1 = castT1(pt0, pt1) end
            push(tl.lanes.paper, pt0, pt1, pe.sym, nil, pe.sym)
          end
        end
        cycleStart = cycleStart + lay.dur
      end
    end
  end
  -- Verdict marks: on the lane of the thing judged, carrying the analysis
  -- fields (did / expected / cost); the expected item becomes a ghost.
  local LANE = { auto = "auto", steady = "cast", multi = "cast", arcane = "cast", weave = "melee", cd = "procs" }
  tl.ghosts = {}
  for _, v in ipairs(verdicts or (score and score.verdicts) or {}) do
    -- A `judge` verdict is one paper NOTE's grade, not a fault: it belongs to
    -- the conveyor's pops and the streak, never to the mark row or the fault
    -- list (a clean fight would otherwise list one "issue" per note played).
    local good = (v.kind == "judge") or (v.code == "GOOD" or v.code == "WEAVE_OK")
    if not good or (opts.okMarks and v.kind ~= "judge") then
      tl.marks[#tl.marks + 1] = { t = v.t, lane = LANE[v.key or "auto"] or "auto", code = v.code,
                                  text = v.text, severity = T.SEVERITY[v.code] or "warn",
                                  did = v.did, expected = v.expected, cost = v.cost }
      if v.ghost and v.ghost.sym then
        -- The shot that SHOULD have been there is usually an instant or a
        -- 0.15 s stub, so it gets the same minimum drawn span a real cast does.
        tl.ghosts[#tl.ghosts + 1] = { lane = v.ghost.lane, t0 = v.ghost.t0, t1 = castT1(v.ghost.t0, v.ghost.t1),
                                      sym = v.ghost.sym, label = "expected", color = "good" }
      end
    end
  end
  -- Live lookahead: dashed items ahead of `now` on every lane, straight from
  -- engine state handed in as opts.live = { now, nextShotAt, cycle, windup,
  --   nextCast = {sym, t0, t1}|nil, meleeReadyAt, oppOpen, ttw,
  --   weaveAt, weaveTtw (the next ACHIEVABLE weave window; see weaveBand),
  --   procs = {name = untilT}, cdReady = {key = t} }, reaching opts.look seconds.
  tl.ahead = {}
  local L = opts.live
  -- The stretch of movement still open at `now` (the snapshot's movingSince):
  -- drawn to the cursor so the MOVE row never waits for the feet to stop.
  if L and L.movingSince and L.now and L.now > L.movingSince then
    push(tl.lanes.move, L.movingSince, L.now, "mv", nil, "move")
    tl.lanes.move[#tl.lanes.move].open = true
  end
  if L and (opts.look or 0) > 0 then
    local horizon = L.now + opts.look
    local shot = L.nextShotAt
    while shot and shot > 0 and shot <= horizon do
      if shot > L.now then tl.ahead[#tl.ahead + 1] = { lane = "auto", t0 = shot - L.windup, t1 = shot, sym = "a", label = "grid", color = "a" } end
      shot = shot + L.cycle
    end
    if L.nextCast and L.nextCast.t0 <= horizon then
      tl.ahead[#tl.ahead + 1] = { lane = "cast", t0 = L.nextCast.t0, t1 = castT1(L.nextCast.t0, L.nextCast.t1),
                                  sym = L.nextCast.sym, label = "NEXT", color = L.nextCast.sym }
    end
    -- The melee lane's PLANNED items only when the paper asks for melee at all.
    local weaves = paperWeaves(L)
    if weaves and L.meleeReadyAt and L.meleeReadyAt > L.now and L.meleeReadyAt <= horizon then
      tl.ahead[#tl.ahead + 1] = { lane = "melee", t0 = L.meleeReadyAt - 0.08, t1 = L.meleeReadyAt + 0.08, label = "swing ready", color = "w" }
    end
    -- `thin`: a window is not an event, and drawn at full lane height with an
    -- outline it read as a huge box swallowing the lane it sits in. Half height,
    -- along the bottom of the lane, no outline -- see T.Strip's band below.
    -- Culled at the horizon like every other item on this list: a window that
    -- opens minutes out (a dead pet, a long recharge) is not a lookahead.
    local bAt, bRoom, bTight = weaveBand(L, L.now)
    if weaves and bAt and bAt <= horizon then
      tl.ahead[#tl.ahead + 1] = { lane = "melee", t0 = bAt, t1 = bAt + bRoom, label = "weave window",
                                  color = "good", band = true, thin = true, tight = bTight }
    end
    for name, untilT in pairs(L.procs or {}) do
      if untilT > L.now then tl.ahead[#tl.ahead + 1] = { lane = "procs", t0 = L.now, t1 = math.min(untilT, horizon), sym = name, label = ("%.1f s left"):format(untilT - L.now), color = name } end
    end
    for key, readyT in pairs(L.cdReady or {}) do
      -- Raptor's own ready mark is a weave-lane plan like the rest of them.
      if readyT > L.now and readyT <= horizon and (weaves or key ~= "Raptor") then
        tl.ahead[#tl.ahead + 1] = { lane = (key == "Raptor") and "melee" or "procs", t0 = readyT - 0.08, t1 = readyT + 0.08, label = key .. " ready", color = T.COLORS[key] and key or "g" }
      end
    end
  end
  return tl
end

--------------------------------------------------------------------------------
-- Shared between the forecast (T.Strip) and the review row (T.Cycles): how a
-- layout splits into auto-to-auto cycles. Both need the same split for the same
-- reason -- a rotation's period is N autos long, not one -- so it lives here,
-- above the first of them, rather than being derived twice.
--------------------------------------------------------------------------------

-- Which symbols are ROTATION content: the things you press BETWEEN two autos.
-- `g` is the layout's own GCD bookkeeping and `a` is the cycle boundary itself,
-- so neither ever appears inside a cycle's string.
local CYCLE_SYM = { s = true, m = true, A = true, r = true, w = true }

-- The paper's cycles for one layout: `rel[j]` is auto j's RELEASE (the cycle
-- boundary), and for each auto j the symbols whose layout start falls in
-- [release j, release j+1) — the tail after the last auto wraps back into the
-- last cycle, since the layout repeats. Built once per layout and cached with
-- it.
local function paperCycles(lay)
  local rel, nRel = {}, 0
  local ev = lay.ev
  for i = 1, #ev do
    local pe = ev[i]
    if pe.sym == "a" then nRel = nRel + 1; rel[nRel] = pe.t0 + pe.dur end
  end
  local strs, syms, counts = {}, {}, {}
  for j = 1, nRel do
    local lo = rel[j]
    local hi = (j < nRel) and rel[j + 1] or (rel[1] + lay.dur)
    local arr, cnt = {}, 0
    for i = 1, #ev do
      local pe = ev[i]
      if CYCLE_SYM[pe.sym] then
        local t = pe.t0
        if t < rel[1] - 1e-9 then t = t + lay.dur end
        if t >= lo - 1e-9 and t < hi - 1e-9 then cnt = cnt + 1; arr[cnt] = pe.sym end
      end
    end
    strs[j], syms[j], counts[j] = table.concat(arr, " ", 1, cnt), arr, cnt
  end
  return nRel, strs, syms, counts, rel
end

-- T.Strip: pure conveyor builder for the live practice strip. Same event
-- kinds and lane/severity rules as T.Build, but flattened to 3 conveyor
-- lanes (shots/weave/procs) inside a moving window around `live.now`, and
-- written into a caller-owned, reused `out` table (no allocation once the
-- item/mark counts stop growing). opts = { past, future, windup, verdicts,
-- okMarks, model = Nock.PracticeModel, paper = { str, h } (the current haste
-- window's paper rotation -- its generation keys the shot grid) }; live = { now,
-- nextShotAt, cycle, windup, meleeReadyAt, oppOpen, ttw,
-- weaveAt, weaveTtw (the weave window -- see weaveBand), weaveMoveAt (the
-- start of the "move in" ramp in front of it),
-- lastShotAt, rangedMul,
-- plan = Nock.state.sim.plan (Core/PracticePlan.lua -- THE paper notes, one
-- NEXT, per-note playability; the strip draws them and decides nothing),
-- paperSyms = the window's own symbol set (nil outside a practice fight; see
-- paperWeaves -- it gates everything the WEAVE lane PLANS),
-- procs = {name = untilT}, cdReady = {key = t},
-- hold = {name = true} (procs the drill holds up for the whole fight) }.
-- Every item ahead of the cursor also carries an integer `key` (see T.KEY) that
-- identifies THE SAME forecast item across rebuilds, so a view can glide a moved
-- item instead of redrawing it; played items carry none.
local STRIP_LANE = { auto = "shots", steady = "shots", multi = "shots", arcane = "shots", weave = "weave", cd = "procs" }
-- THE ROWS (v3 P3). One row per ability on the stage: the auto grid, each cast,
-- the weave, and the cooldowns/procs. Every strip item and mark carries one;
-- the plan says which rows a paper uses (plan.rows) and the view builds them.
T.ROW_ORDER = { "auto", "s", "m", "A", "w", "cd" }
T.ROW_OF_SYM = { a = "auto", s = "s", m = "m", A = "A", w = "w", r = "w",
                 KC = "cd", QS = "cd", RF = "cd", Lust = "cd", Drums = "cd", DST = "cd", Pot = "cd", Raptor = "w" }
local ROW_OF_SYM = T.ROW_OF_SYM
local STRIP_ROW = { auto = "auto", steady = "s", multi = "m", arcane = "A", weave = "w" }
-- Where a projected PAPER symbol goes on the conveyor. Two symbols have no lane
-- here: `g` (the GCD filler) is bookkeeping inside the layout rather than
-- something you press, and `a` belongs to the ENGINE -- the measured shot grid
-- is the truth for the shots lane, so the paper contributes only the casts and
-- weave slots that go between the grid's autos.
local PAPER_LANE = { s = "shots", m = "shots", A = "shots", r = "weave", w = "weave" }
-- ...and which lane a PLAN row lives on (Core/PracticePlan.lua P.ROW).
local ROW_LANE = { s = "shots", m = "shots", A = "shots", w = "weave" }
-- A projected item at EXACTLY `now` is still ahead of you: the opening Steady
-- of a frozen pre-pull strip sits on the anchor to the last bit, and a strict
-- `t0 > now` dropped it — the strip said Multi while the panel said "pull:
-- Steady". Float arithmetic on a shifted layout offset lands either side of the
-- anchor, so the test needs a hair of slack, not exact equality.
local NOW_EPS = 1e-6


-- Stable conveyor identities. Every item the strip projects AHEAD of the cursor
-- carries one, so a view can tell "the same forecast item, moved" from "a brand
-- new item" across two rebuilds and glide the first rather than re-drawing it.
-- Past items carry none: they never move, and a key would only make them fade
-- in again at every rebuild.
--
-- The ranges are disjoint by construction: paper slots grow from the window's
-- first auto in steps of the layout's own event count (a few dozen per period,
-- so tens of thousands of periods before they could reach GRID), and everything
-- else sits at a fixed id above 1e6.
T.KEY = {
  PAPER_SLOTS = 32,       -- key stride per CYCLE: PAPER + cycle * PAPER_SLOTS + note index
  -- The shot grid: + the auto's CYCLE INDEX (the plan's autos, v3 P2).
  GRID     = 1000000,
  MOVE     = 2999999,     -- the "move in" ramp in front of the weave window
  BAND     = 3000000,     -- the weave window
  PROC     = 3000001,     -- + PROC_IX[name]
  PROC_LAST= 3099999,
  CD       = 3100000,     -- + PROC_IX[key]
  SWING    = 3200000,     -- the melee swing-ready tick
  -- The paper's own block sits above all of those and grows upwards: one
  -- PAPER_SLOTS-wide slice per CYCLE INDEX (T.NoteKey).
  PAPER    = 4000000,
  -- Played items (the event stream behind the cursor): + the event's index.
  -- A fight caps its stream at eventCap (thousands), never a million.
  PLAYED   = 5000000,
}

-- THE paper key scheme, in one place. Two producers write these keys -- the
-- grader's per-note judgments (PracticeGrader, at seat) and the plan's
-- projection (Core/PracticePlan.lua, for the cycles ahead) -- and the view
-- matches one against the other to find the frame a note or a judgment
-- belongs to, so the arithmetic may exist exactly once.
--
-- A note's identity is WHICH CYCLE (the grader's own cycle index, which the
-- plan counts forward from) and WHICH NOTE of it, in seat order (the k-th
-- note the cycle holds). Nothing about haste or layout slot: a haste window
-- re-lays AND re-phases the paper, which MOVES notes and can change what the
-- k-th note is -- the view glides it and swaps its icon in place. It never
-- re-keys. (It used to carry a plan generation and a layout slot, and every
-- haste window re-faded the whole strip from zero.)
function T.NoteKey(cycleIx, i)
  return T.KEY.PAPER + (cycleIx or 0) * T.KEY.PAPER_SLOTS + i
end

-- `pairs` order over live.procs / live.cdReady is not stable, so a span's key
-- cannot be its iteration index. A fixed small integer per name is. A name that
-- is not on the list gets NO key: sharing one slot between two unknown procs
-- would hand them each other's seat, which is worse than not gliding them.
local PROC_IX = { RF = 1, QS = 2, Lust = 3, Drums = 4, DST = 5, Pot = 6, KC = 7, Raptor = 8 }
local function procKey(base, name)
  local ix = PROC_IX[name]
  return ix and (base + ix) or nil
end

-- Two things T.Strip reaches for that are often nil, and `x or {}` allocates a
-- table on every single rebuild.
local EMPTY = {}

-- "<key> ready" is a string built per rebuild on the tick path. Built once per
-- key instead: the key set is tiny and closed in practice, so an unseen name
-- costs exactly one string, once.
local READY_LABEL = {}
local function readyLabel(key)
  local s = READY_LABEL[key]
  if not s then s = key .. " ready"; READY_LABEL[key] = s end
  return s
end

-- Module-scope (not a per-call closure) so T.Strip allocates nothing once
-- out.items has grown to its steady-state size: increments out.nItems and
-- writes/clears every field of out.items[out.nItems] in place. `future` is
-- computed by the caller (t0 > live.now) since this function has no access
-- to `now` on its own. `key` is nil for anything already played.
local function addItem(out, wt0, wt1, lane, t0, t1, sym, color, future, band, label, key, thin, tight, oncd, row)
  if t1 < wt0 or t0 > wt1 then return end
  local i = out.nItems + 1
  out.nItems = i
  local it = out.items[i]
  if not it then it = {}; out.items[i] = it end
  it.lane, it.t0, it.t1, it.sym, it.color, it.future, it.band, it.label = lane, t0, t1, sym, color, future, band, label
  it.key, it.thin, it.tight, it.oncd = key, thin, tight, oncd
  it.row = row or ROW_OF_SYM[sym] or (lane == "weave" and "w") or (lane == "procs" and "cd") or "auto"
end

-- The PAPER layout, cached on `out` and rebuilt only when the notation or the
-- haste changes (the layout is the expensive part; the projection that walks it
-- allocates nothing). Refreshed BEFORE anything writes a key, because its
-- generation keys the shot GRID as well as the projection -- see T.KEY.
-- Returns the cache, or nil when there is no paper to project.
function T.Strip(events, n, live, opts, out)
  opts = opts or {}
  out = out or { items = {}, nItems = 0, marks = {}, nMarks = 0 }
  out.items = out.items or {}
  out.marks = out.marks or {}
  out.nItems = 0
  out.nMarks = 0

  local now = live.now
  local past = opts.past or 2
  local future = opts.future or 4.5
  local wt0, wt1 = now - past, now + future
  out.t0, out.t1 = wt0, wt1

  -- Scan cursor: events are time-ordered and `now` is monotonic within a
  -- fight, so once an event is more than 60 s (a Lust-covering margin, since
  -- a proc span's start must stay visible until the span itself ages out of
  -- the window) behind the window start it can never matter again -- advance
  -- past it for good. Never move backwards except on a stream change.
  --
  -- THREE signals say the stream changed, and all three are needed. `now` is
  -- GetTime() in-game, so it is monotonic ACROSS fights too: the rewind test
  -- alone never fires there, and a fresh (shorter) event table from the next
  -- fight would then be scanned from a cursor pointing past its end -- the
  -- past lane silently blank after any fight longer than ~62 s.
  --   1. now < _lastNow      -- an explicit rewind (tests, a re-seeded clock)
  --   2. n < _lastN          -- a shorter table than last call: a new stream
  --   3. events[_scanFrom-1] -- the last event we skipped is AHEAD of `now`,
  --                             which no genuinely-skipped event can be
  out._scanFrom = out._scanFrom or 1
  local skipped = (out._scanFrom > 1) and events[out._scanFrom - 1] or nil
  local skippedT = skipped and (skipped.t or skipped.t1) or nil
  -- Held separately because the pops cursor below needs the same signal, and
  -- `out._lastNow` is overwritten two lines down.
  local rewound = (out._lastNow ~= nil and now < out._lastNow) or false
  if rewound
    or (n < (out._lastN or 0))
    or (skippedT and skippedT > now) then
    out._scanFrom = 1
  end
  out._lastNow, out._lastN = now, n
  local scanLimit = wt0 - 60
  while events[out._scanFrom] do
    local et = events[out._scanFrom].t or events[out._scanFrom].t1
    if et and et < scanLimit then
      out._scanFrom = out._scanFrom + 1
    else
      break
    end
  end

  -- Past: replay only events that already happened (primary time <= now);
  -- an unclosed proc span is closed at `now`, mirroring T.Build's end-of-
  -- window close but anchored to the live cursor instead of the fight end.
  -- `_procStart` lives on `out` (not a fresh local table) and is cleared in
  -- place each call so no new table is allocated in steady state.
  local windup = opts.windup or 0
  out._procStart = out._procStart or {}
  local procStart = out._procStart
  for k in pairs(procStart) do procStart[k] = nil end

  for i = out._scanFrom, n do
    local ev = events[i]
    local kind = ev.kind
    -- Every played item is keyed by its event (v3 P2): the view binds a frame
    -- to it once and never fades it in again at a rebuild.
    local pk = T.KEY.PLAYED + i
    if kind == "auto" and ev.t <= now then
      local t0 = ev.t - windup
      local delay = ev.delay
      -- A delayed auto shows its WAIT: the item runs from the moment the auto
      -- was due (release less wind-up less delay) to the release, with the
      -- delay as its tag. Red only for a clip the grader FAULTED (ev.clip,
      -- PracticeGrader's auto branch); a planned one -- the paper's own cast
      -- held it back -- is amber (`wait`), so a paper that clips by design
      -- reads as intended and never as a mistake (user, 2026-08-26).
      if delay and delay > 0.03 then
        addItem(out, wt0, wt1, "shots", t0 - delay, ev.t, "a", (ev.clip == "fault") and "bad" or "wait", t0 > now, nil, "+" .. math.floor(delay * 1000 + 0.5), pk)
      else
        addItem(out, wt0, wt1, "shots", t0, ev.t, "a", "a", t0 > now, nil, nil, pk)
      end
    elseif kind == "cast" and ev.t0 <= now then
      local sym = SYM[ev.spell] or "s"
      if ev.cancelled then
        addItem(out, wt0, wt1, "shots", ev.t0, castT1(ev.t0, ev.t1), sym, "g", ev.t0 > now, nil, "cancelled", pk)
      else
        addItem(out, wt0, wt1, "shots", ev.t0, castT1(ev.t0, ev.t1), sym, sym, ev.t0 > now, nil, nil, pk)
      end
    elseif kind == "melee" and ev.t <= now then
      -- Drawn MIN_CAST_DRAW wide, ending on the hit: a 0.2 s box at any sane
      -- px/s is too narrow to carry its icon, and the icon is what says white
      -- swing vs Raptor.
      local t0 = ev.t - MIN_CAST_DRAW
      addItem(out, wt0, wt1, "weave", t0, ev.t, ev.hit, ev.hit, t0 > now, nil, (ev.hit == "r") and "Raptor" or nil, pk)
    elseif kind == "kc" and ev.t <= now then
      local t0 = ev.t - 0.1
      addItem(out, wt0, wt1, "weave", t0, ev.t + 0.1, "KC", "KC", t0 > now, nil, "KC", pk)
    elseif kind == "proc" then
      if ev.on and ev.t <= now then
        procStart[ev.name] = ev.t
      elseif not ev.on and ev.t <= now then
        local s = procStart[ev.name] or ev.t
        addItem(out, wt0, wt1, "procs", s, math.min(ev.t, now), ev.name, ev.name, s > now, nil, ev.name, pk)
        procStart[ev.name] = nil
      end
    elseif kind == "cd" and ev.used and ev.t <= now then
      local t0 = ev.t - 0.1
      addItem(out, wt0, wt1, "procs", t0, ev.t + 0.1, ev.key, ev.key, t0 > now, nil, ev.key, pk)
    end
  end
  -- An unclosed span is closed at the cursor -- UNLESS the live snapshot still
  -- reports that proc, in which case the future pass below draws the whole
  -- thing as ONE solid span running from here to its expiry. Two items (a past
  -- one ending at `now` and a remainder starting there) drew the same proc
  -- twice, stacked its icon and split a single continuous buff in half.
  local liveProcs = live.procs
  for name, s in pairs(procStart) do
    local untilT = liveProcs and liveProcs[name]
    if not (untilT and untilT > now) then
      -- Keyed like its live twin below (the two are mutually exclusive): its
      -- right edge is the cursor, so it is redrawn at every rebuild and would
      -- otherwise fade in again each time.
      addItem(out, wt0, wt1, "procs", s, now, name, name, s > now, nil, name,
              procKey(T.KEY.PROC, name))
    end
  end

  -- Autos released since this haste window opened. Two things need it: the
  -- forecast's position in the rotation, and the ABSOLUTE index that keys the
  -- grid's own shots (so the shot at `nextShotAt` keeps its identity when it
  -- releases and the next one takes its place).

  -- The paper layout for this haste, refreshed before a single key is written:
  -- its generation keys the grid below as well as the projection further down.
  -- THE GRID IS THE PLAN'S (v3 P2): one item per auto ahead, wind-up to
  -- release, keyed by cycle index -- a clip delay or a haste change moves an
  -- auto, it never re-keys it. Past autos are drawn from the event stream.
  local horizon = wt1
  local plan = live.plan
  if plan and plan.live then
    for i = 1, plan.nAutos do
      local a = plan.autos[i]
      if a.releaseAt > now then
        addItem(out, wt0, wt1, "shots", a.windupAt, a.releaseAt, "a", "a", a.windupAt > now, nil, nil, a.key)
      end
    end
  end
  -- THE PLAN OWNS THE PAPER (v3 P1). Every paper note on the strip is a note of
  -- Nock.state.sim.plan (Core/PracticePlan.lua): seated on the grader's measured
  -- cycles, projected ahead on the grid, one NEXT chosen there and nowhere else.
  -- A hit note behind the cursor is not re-drawn -- the event stream already
  -- draws the cast that took it -- but a PENDING note stays on the strip past
  -- its time, wearing NEXT, until the grader sweeps it: that is the note the
  -- medallion is still asking for. An unplayable note (cooldown) keeps its slot,
  -- dimmed (`oncd`). With no plan in hand (a fixture) nothing is projected.
  if plan and plan.live then
    local nextIdx = plan.nextIdx
    for i = 1, plan.n do
      local nt = plan.notes[i]
      local lane = ROW_LANE[nt.row]
      if lane and not nt.lost and (nt.state == "pending" or nt.t0 > now - NOW_EPS) then
        local t1 = nt.t1
        if lane == "shots" then t1 = castT1(nt.t0, t1)
        elseif t1 < nt.t0 + MIN_CAST_DRAW then t1 = nt.t0 + MIN_CAST_DRAW end
        -- On the lane a weave note is drawn as the hit it will be: `r` (Raptor,
        -- its icon and colour) when the plan says the cooldown is up by then,
        -- `w` (the white swing) otherwise.
        local sym = nt.sym
        if sym == "w" or sym == "r" then sym = nt.raptor and "r" or "w" end
        addItem(out, wt0, wt1, lane, nt.t0, t1, sym, sym, nt.t0 > now, nil,
                (i == nextIdx) and "NEXT" or nil, nt.key, nil, nil, not nt.playable, nt.row)
      end
    end
  end
  -- Does this window's paper ask for melee at all? Everything the WEAVE lane
  -- PLANS hangs off the answer (see paperWeaves above): the swing-ready tick
  -- here, the gap band below, and Raptor's ready mark at the bottom. The
  -- projection's own `r`/`w` notes need no gate -- a paper with no weave slot
  -- has none to project.
  local weaves = paperWeaves(live)
  -- With a plan in hand the band already says when the swing is up and the
  -- note says where the hit goes: the two ready ticks on this lane (swing,
  -- Raptor) only add glyphs to read (v3 P1 gate footage). They stay for a
  -- fixture without a plan.
  local ticks = not (plan and plan.live)
  if weaves and ticks and live.meleeReadyAt and live.meleeReadyAt > now and live.meleeReadyAt <= horizon then
    local t0 = live.meleeReadyAt - 0.08
    addItem(out, wt0, wt1, "weave", t0, live.meleeReadyAt + 0.08, nil, "w", t0 > now, nil, "swing ready", T.KEY.SWING)
  end
  -- The weave band is the room you have RIGHT NOW: `now` to the moment the
  -- wind-up wants to start. Both edges are meaningful and both are drawn.
  --
  -- It used to run from a second BEHIND the window so its re-seated left edge
  -- could not be seen stuttering — but a bar that starts off screen and is
  -- painted at full lane height is not a window any more, it is a box over the
  -- whole WEAVE lane (Round 3's "huge weave box"). It is `thin` instead: half
  -- the lane, along the bottom, no outline. Nothing visibly moves, because its
  -- left edge rides the cursor — and the view exempts it from the glide (see
  -- `noEase`), so the deadline on the right stays honest.
  local bAt, bRoom, bTight = weaveBand(live, now)
  if weaves and bAt then
    addItem(out, wt0, wt1, "weave", bAt, bAt + bRoom, nil, "good", bAt > now, true, nil, T.KEY.BAND,
            true, bTight)
    -- MOVE IN: the ramp in front of the window, as long as this player's own
    -- step-in (plan.weave.moveAt, Core/PracticePlan.lua). Start walking anywhere
    -- in it and the hit lands in the window -- the weave's queue band, the
    -- same idea as the auto-shot bar's.
    local mAt = live.weaveMoveAt
    if mAt and mAt < bAt then
      addItem(out, wt0, wt1, "weave", mAt, bAt, nil, "warn", mAt > now, true, nil, T.KEY.MOVE, true, nil)
    end
  end
  -- A HELD proc (a paper drill's `hold=`) is parked at now + 1e9 by the
  -- engine, so its remaining time is not a number anyone wants to read. Draw
  -- it to the horizon and label it for what it is.
  --
  -- A running proc is ONE solid span (the past pass above yields it to this
  -- one), drawn from where it actually STARTED -- or from just behind the
  -- window when that is older -- across `now` to its expiry. Never from `now`:
  -- an absolute bar scrolls, a now-anchored one re-seats itself every rebuild
  -- and stutters. It carries no text either: the palette tile shows the
  -- remaining time, and a number here changed 6 times a second and read as
  -- flicker.
  local hold = live.hold
  for name, untilT in pairs(live.procs or EMPTY) do
    if untilT > now then
      local t0 = wt0 - 1
      local onT = procStart[name]
      if onT and onT > t0 then t0 = onT end
      local pk = procKey(T.KEY.PROC, name)
      if hold and hold[name] then
        addItem(out, wt0, wt1, "procs", t0, horizon, name, name, false, nil, "held", pk)
      else
        addItem(out, wt0, wt1, "procs", t0, math.min(untilT, horizon), name, name, false, nil, nil, pk)
      end
    end
  end
  for key, readyT in pairs(live.cdReady or EMPTY) do
    if readyT > now and readyT <= horizon and (key ~= "Raptor" or (weaves and ticks)) then
      local lane = (key == "Raptor") and "weave" or "procs"
      -- A "ready from here" marker, wide enough to carry the ability's icon
      -- (a 0.16 s box drew as a bare orange square -- gate footage).
      addItem(out, wt0, wt1, lane, readyT, readyT + MIN_CAST_DRAW, key, (T.COLORS[key] and key) or "g", readyT > now, nil,
              readyLabel(key), procKey(T.KEY.CD, key))
    end
  end

  for i = out.nItems + 1, #out.items do
    local it = out.items[i]
    it.lane, it.t0, it.t1, it.sym, it.color, it.band, it.label, it.future = nil, nil, nil, nil, nil, nil, nil, nil
    it.key, it.thin, it.tight = nil, nil, nil
  end

  -- Marks: verdicts inside [now - past, now] only (marks are historical --
  -- they never look ahead of the live cursor), same lane mapping and GOOD/
  -- WEAVE_OK suppression as T.Build.
  for _, v in ipairs(opts.verdicts or EMPTY) do
    if v.t >= wt0 and v.t <= now then
      -- Judgments are pops, not marks (see T.Build).
      local good = (v.kind == "judge") or (v.code == "GOOD" or v.code == "WEAVE_OK")
      if not good or (opts.okMarks and v.kind ~= "judge") then
        local m = out.nMarks + 1
        out.nMarks = m
        local mk = out.marks[m]
        if not mk then mk = {}; out.marks[m] = mk end
        mk.t, mk.lane, mk.code, mk.text = v.t, STRIP_LANE[v.key or "auto"] or "shots", v.code, v.text
        mk.row = STRIP_ROW[v.key or "auto"] or "auto"
        mk.severity = T.SEVERITY[v.code] or "warn"
        mk.did, mk.expected, mk.cost = v.did, v.expected, v.cost
      end
    end
  end
  for i = out.nMarks + 1, #out.marks do
    local mk = out.marks[i]
    mk.t, mk.lane, mk.code, mk.text, mk.severity, mk.did, mk.expected, mk.cost = nil, nil, nil, nil, nil, nil, nil, nil
    mk.row = nil
  end

  -- Pops: the `judge` verdicts graded within the last POP_LIFE seconds, in the
  -- order they were graded. `key` is the paper note's conveyor key (T.NoteKey) —
  -- the SAME integer the forecast gave that item — so the view anchors the pop
  -- on the note's own frame; a note with no key (an OFF press, or a grader with
  -- no timeline in reach) simply pops at the hit line.
  --
  -- Scanned from a cursor like the event scan above, and for the same reason:
  -- `now` is monotonic within a fight, so a verdict already older than POP_LIFE
  -- can never pop again. The list is only APPROXIMATELY time-ordered (a MISSED
  -- is stamped at its cycle's end but pushed a cycle later), which costs nothing
  -- here: the cursor stops at the first entry still young enough to matter, so
  -- an out-of-order entry behind it is never skipped.
  local verdicts = opts.verdicts
  out.pops = out.pops or {}
  local pops = out.pops
  local np = 0
  if verdicts then
    local nv = #verdicts
    -- A new fight is a new verdict TABLE (the grader is rebuilt per fight), and
    -- a shorter list or a rewound clock says the same thing. Any of the three
    -- puts the cursor back at the front.
    if out._popsV ~= verdicts or rewound or nv < (out._popN or 0) then
      out._popFrom, out._popsV = 1, verdicts
    end
    out._popN = nv
    local from = out._popFrom or 1
    while from <= nv do
      local v = verdicts[from]
      if v and v.t and (now - v.t) > POP_LIFE then from = from + 1 else break end
    end
    out._popFrom = from
    for i = from, nv do
      local v = verdicts[i]
      if v.kind == "judge" then
        local age = now - (v.t or 0)
        if age >= 0 and age <= POP_LIFE then
          np = np + 1
          local p = pops[np]
          if not p then p = {}; pops[np] = p end
          local note = v.note
          p.key = note and note.key or nil
          -- `t` is when the note was GRADED (the pop's own clock) and `t0` when
          -- the paper wanted it. Both are needed: a judgment is pushed inline at
          -- the press, so by the time it pops the note's frame may already have
          -- passed the hit line and been recycled — `t0` is the anchor that
          -- survives that, and the coach line reads `deltaMs` rather than
          -- parsing it back out of the text.
          p.t, p.grade = v.t, v.grade
          p.t0 = note and note.t0 or nil
          p.deltaMs = v.deltaMs
          p.sym = note and note.sym or nil
          p.text, p.sev = popText(v), T.JUDGE_SEV[v.grade] or "warn"
        end
      end
    end
  else
    out._popFrom, out._popsV, out._popN = 1, nil, 0
  end
  out.popsN = np
  for i = np + 1, #pops do
    local p = pops[i]
    p.key, p.t, p.t0, p.grade, p.sym, p.text, p.sev, p.deltaMs = nil, nil, nil, nil, nil, nil, nil, nil
  end

  return out
end

--------------------------------------------------------------------------------
-- T.Cycles: the review's paper-vs-played row. One entry per auto-to-auto cycle
-- (cycle k runs from auto release k to auto release k+1; the last, open cycle
-- ends at the fight's last event), each carrying what the PAPER rotation puts
-- in that cycle position and what was actually PLAYED there.
--
-- Pure: engine events + the scorecard's haste windows in, a caller-owned `out`
-- (pooled cycle tables, `out.n` entries valid). Strings are joined only when a
-- cycle's content changes, so a repeat call on an unchanged fight allocates
-- nothing.
--
-- Grading starts at the FIRST auto release: anything pressed before it (the
-- opener's pre-pull Steady, most obviously) belongs to no cycle and is not
-- judged here. The trailing cycle is usually still open — it ends at the
-- fight's last event, which mid-fight is often the auto that opened it — so it
-- carries `partial = true` and must never be painted as a mismatch.
--------------------------------------------------------------------------------

-- A weave is a weave. The paper counts a weave SLOT and M.STRINGS only ever
-- writes it as `w`, while a played Raptor arrives as `r`: compared literally,
-- every single weave cycle of a weaving drill would light up red. The strings
-- stay faithful to what each side actually did (`r` still reads as a Raptor in
-- the tooltip); only the ok/mismatch test normalises — and only in that ONE
-- direction. A Raptor filling a weave SLOT is the weave the paper asked for;
-- a Raptor where the paper wanted a Steady is not, and used to be forgiven by
-- normalising both sides.
local function sameSlot(pa, pl)
  return pa == pl or (pa == "w" and pl == "r")
end

-- One cached layout per (notation string, haste, weapon speed, cast residual) —
-- the same key T.Strip's forecast uses, for the same reason: those four are
-- every input the layout's shape depends on. Held on `out` as a short list
-- (a fight has a handful of haste windows), scanned by field so no string key
-- is built per call.
local function layoutFor(out, model, h, w)
  if not (model and w) then return nil end
  local cache = out._lay
  if not cache then cache = {}; out._lay = cache end
  local nota = w.notation
  local mul = w.rangedMul or h.rangedMul or 1
  -- Keyed on the notation, not the string: the string is resolved at the
  -- window's haste on a miss only (M.PaperString allocates a layout).
  for i = 1, #cache do
    local c = cache[i]
    if c.nota == nota and c.mul == mul and c.ws == h.ws and c.cc == h.castCorr then return c end
  end
  local hw = {}
  for k, v in pairs(h) do hw[k] = v end
  hw.rangedMul = mul
  local str = (model.PaperString and model.PaperString(nota, hw)) or model.STRINGS[nota] or "as"
  local lay = model.Layout(str, hw, 0)
  local nRel, strs, syms, counts, rel = paperCycles(lay)
  -- The wind-up this layout was built with: its first auto's own duration. Read
  -- off the layout rather than recomputed from the haste, so a replay's paper
  -- and its played autos are seated against the same number.
  local wu = 0
  for i = 1, #lay.ev do
    local pe = lay.ev[i]
    if pe.sym == "a" then wu = pe.dur; break end
  end
  -- `ev` and `rel` are what T.Replay needs to seat one cycle's notes at their
  -- own times; T.Cycles itself only ever compares the joined strings.
  local c = { nota = nota, str = str, mul = mul, ws = h.ws, cc = h.castCorr,
              autos = nRel, dur = lay.dur, paper = strs, pSyms = syms, pN = counts,
              ev = lay.ev, rel = rel, wu = wu }
  cache[#cache + 1] = c
  return c
end

-- Largest i with autoT[i] <= t, or 0 when t precedes the first auto. Binary
-- search rather than a two-pointer walk: a cast event carries t0 but is pushed
-- at its END, so the stream is not strictly ordered by the time being placed.
--
-- A cast the layout puts exactly ON a release belongs to the cycle that release
-- OPENS, and a played one landing there (the press that goes out with the shot)
-- must fall the same way, not one cycle back — with ONE frame of doubt around
-- the boundary, since the engine starts a queued cast at the release itself and
-- a hair of float either way is not a rotation decision. T.CYCLE_EPS is that
-- one definition: PracticeGrader's own cycleFor/sweepDue read it, so a note's
-- JUDGMENT and its cycle's ON-PAPER verdict can never land on opposite sides of
-- a release (they did: 6/6 PERFECT pops over a scorecard that said 4/6).
T.CYCLE_EPS = 0.033
local CYCLE_EPS = T.CYCLE_EPS

local function cycleAt(autoT, na, t)
  if na == 0 or t < autoT[1] - CYCLE_EPS then return 0 end
  local lo, hi = 1, na
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if autoT[mid] <= t + CYCLE_EPS then lo = mid else hi = mid - 1 end
  end
  return lo
end

-- WHICH CYCLE A PLAY BELONGS TO. `match` is PracticeGrader's map (the play's
-- own EVENT -> the cycle whose NOTE it took), handed over on the scorecard; the
-- clock is the answer only for a play that matched no note at all.
--
-- The matcher owns this because the paper's own cycle can be WIDER than the
-- measured one — a notation whose period is longer than its autos need seats a
-- note past the next release — and filing that note's play by the clock put it
-- one cycle on from the note it took: an empty cell beside a doubled one, with
-- every judgment green. See PracticeGrader's matchNote.
--
-- The key is the EVENT and never its time: a weave hit and a cast press really
-- do share a moment on a paper that writes both on one beat, and a float key
-- gave them each other's seat.
local function fileAt(match, ev, autoT, na, t)
  local k = match and match[ev]
  if k then
    if k < 1 then return 0 end
    return (k <= na) and k or 0
  end
  return cycleAt(autoT, na, t)
end

local function blankCycle(c)
  c.t0, c.t1, c.paper, c.played, c.ok, c.partial = nil, nil, nil, nil, nil, nil
  c.pSyms, c.pN, c.sN = nil, 0, 0
  c.wi, c.wk = nil, nil
  c._nSyms = -1      -- force the string rebuild if this slot comes back
end

function T.Cycles(events, n, score, h, model, out)
  out = out or {}
  out.n = 0
  h = h or {}
  -- No scorecard windows means no paper to compare against, and a row of
  -- all-red cycles is a lie rather than a finding: draw nothing.
  local windows = score and score.windows
  if not (events and n and n > 0 and windows and #windows > 0) then
    for i = 1, #out do blankCycle(out[i]) end
    return out
  end

  -- 1. The cycle boundaries: every auto RELEASE, plus the fight's end for the
  --    last, still-open cycle.
  local autoT = out._autoT
  if not autoT then autoT = {}; out._autoT = autoT end
  local na, tEnd = 0, nil
  for i = 1, n do
    local ev = events[i]
    local kind = ev.kind
    if kind == "auto" then
      na = na + 1
      autoT[na] = ev.t
    elseif (kind == "stop" or kind == "end") and not tEnd then
      tEnd = ev.t
    end
  end
  if not tEnd then
    local last = events[n]
    tEnd = last and (last.t or last.t1) or (na > 0 and autoT[na]) or 0
  end
  for i = 1, na do
    local c = out[i]
    if not c then c = { syms = {}, sN = 0, _buf = {}, _bufT = {}, _nb = 0, _nSyms = -1 }; out[i] = c end
    c.t0 = autoT[i]
    local t1 = (i < na) and autoT[i + 1] or tEnd
    if t1 < c.t0 then t1 = c.t0 end
    c.t1 = t1
    c._nb = 0
  end
  for i = na + 1, #out do blankCycle(out[i]) end
  out.n = na
  if na == 0 then return out end

  -- 2. What was PLAYED: the same event kinds the strip draws — cast starts
  --    (a cancelled cast never became a shot and is not one) and melee weaves.
  --    Filed by the matcher where it matched (see fileAt), by the clock where
  --    it did not.
  local match = score.match
  for i = 1, n do
    local ev = events[i]
    local kind = ev.kind
    local sym, t
    if kind == "cast" and not ev.cancelled then
      sym, t = SYM[ev.spell] or "s", ev.t0
    elseif kind == "melee" then
      sym, t = ev.hit, ev.t
    end
    if sym and t and CYCLE_SYM[sym] then
      local k = fileAt(match, ev, autoT, na, t)
      if k > 0 then
        -- Inserted by the play's OWN moment, not by the order the event reached
        -- the stream: a cast is pushed at its END, so a Steady begun before a
        -- weave and finished after it used to read `w s` against a paper that
        -- says `s w`. And a matched play may now land here from outside this
        -- cycle's span, which appending would put in the wrong seat outright.
        local c = out[k]
        local b, buf, bufT = c._nb + 1, c._buf, c._bufT
        c._nb = b
        local j = b
        while j > 1 and bufT[j - 1] > t do
          buf[j], bufT[j] = buf[j - 1], bufT[j - 1]
          j = j - 1
        end
        buf[j], bufT[j] = sym, t
      end
    end
  end

  -- 3. What the PAPER wanted there: the haste window this cycle falls in gives
  --    the notation, and the cycle's position inside that window (modulo the
  --    layout's auto count) gives which of the layout's cycles to compare
  --    against.
  local nw = #windows
  local wi, wk, lay = 0, 0, nil
  for i = 1, na do
    local c = out[i]
    while wi < nw and (windows[wi + 1].t0 or math.huge) <= c.t0 + 1e-9 do
      wi, wk, lay = wi + 1, 0, nil
    end
    if wi == 0 and nw > 0 then wi, wk, lay = 1, 0, nil end
    if lay == nil and wi > 0 then lay = layoutFor(out, model, h, windows[wi]) end
    local pStr, pArr, pN = "", nil, 0
    if lay and lay.autos > 0 then
      local j = (wk % lay.autos) + 1
      pStr, pArr, pN = lay.paper[j], lay.pSyms[j], lay.pN[j]
    end
    c.paper, c.pSyms, c.pN = pStr, pArr, pN
    -- Where this cycle sits: which haste window (index into score.windows) and
    -- its 0-based position INSIDE that window. T.Replay needs both to seat the
    -- window's layout on the cycle, and recomputing them there would be a second
    -- copy of the window walk above — which is exactly how the two would drift.
    c.wi, c.wk = wi, wk
    -- The trailing cycle is open: it ends at the fight's last event, which
    -- mid-fight is often the auto that opened it (t1 == t0). Compared as a whole
    -- cycle it is a non-empty paper against an empty played side -- red, every
    -- single time. Flagged instead, and neither the row nor the report line
    -- treats it as a verdict.
    if i == na then
      local cycLen = (lay and lay.autos and lay.autos > 0) and (lay.dur / lay.autos)
                     or ((h.ws or 0) / (h.rangedMul or 1))
      c.partial = (cycLen > 0) and ((c.t1 - c.t0) < 0.9 * cycLen) or false
    else
      c.partial = false
    end
    wk = wk + 1

    -- The joined string only when the content moved: a review rebuild on an
    -- unchanged fight must not allocate a string per cycle.
    local nb, buf, syms = c._nb, c._buf, c.syms
    local changed = (c._nSyms ~= nb)
    if not changed then
      for j = 1, nb do
        if syms[j] ~= buf[j] then changed = true; break end
      end
    end
    if changed then
      for j = 1, nb do syms[j] = buf[j] end
      c._nSyms, c.sN = nb, nb
      c.played = table.concat(buf, " ", 1, nb)
    end

    local okC = (pN == nb)
    if okC then
      for j = 1, nb do
        if not sameSlot(pArr[j], syms[j]) then okC = false; break end
      end
    end
    c.ok = okC
  end
  return out
end

--------------------------------------------------------------------------------
-- T.Replay: ONE cycle, drawn twice — what the paper wanted (ghosts) against
-- what was played — for the review's fix cards. Pure, and written into a
-- caller-owned `out` (pooled items, `out.nItems` entries valid), so a card that
-- rebuilds allocates nothing.
--
--   T.Replay(events, n, score, h, model, cycleIndex, out)
--
-- `cycleIndex` is a T.Cycles index, which is the grader's cycle number too: the
-- boundaries come from T.Cycles itself (held on `out._cyc`), so "cycle 7" means
-- one thing across the analysis, the review row and this. Every item's time is
-- RELATIVE to the cycle's start; `out.t0` is that start on the fight clock and
-- `out.cycle` the cycle's own length.
--
--   out.items[i] = { lane, t0, t1, sym, ghost, label }
--
-- `lane` is the conveyor's ("shots" / "weave"), `ghost` marks the paper's copy,
-- and `label` carries the one number a card must show: the clipped auto's delay.
--------------------------------------------------------------------------------

-- "+N ms" for a clipped auto, cached on the EVENT: an event's delay never
-- changes, and a card redrawn on the tick must not build a string per rebuild.
local function delayLabel(ev)
  local s = ev._msLabel
  if not s then
    s = "+" .. math.floor((ev.delay or 0) * 1000 + 0.5) .. " ms"
    ev._msLabel = s
  end
  return s
end

local function addReplay(out, lane, t0, t1, sym, ghost, label)
  local i = out.nItems + 1
  out.nItems = i
  local it = out.items[i]
  if not it then it = {}; out.items[i] = it end
  it.lane, it.t0, it.t1, it.sym, it.ghost, it.label = lane, t0, t1, sym, ghost, label
end

-- Does this play belong on THIS card? The same question T.Cycles' `fileAt`
-- answers, asked of one cycle: the matcher's map wins where it has an entry, so
-- the strip carries the very presses the card's `played` caption names, and the
-- clock decides for a play that matched nothing. A matched play seated past the
-- cycle's own end is drawn past the strip's right edge; the card clips it,
-- which is honest — that is where the press was made.
local function belongs(match, ev, t, t0, t1, ix)
  local k = match and match[ev]
  if k then return k == ix end
  return t >= t0 - 1e-9 and t < t1 - 1e-9
end

local function clearReplay(out)
  for i = out.nItems + 1, #out.items do
    local it = out.items[i]
    it.lane, it.t0, it.t1, it.sym, it.ghost, it.label = nil, nil, nil, nil, nil, nil
  end
  return out
end

function T.Replay(events, n, score, h, model, cycleIndex, out)
  out = out or { items = {}, nItems = 0 }
  out.items = out.items or {}
  out.nItems = 0
  h = h or {}
  out.t0, out.t1, out.cycle, out.index = nil, nil, 0, nil
  out.paper, out.played, out.ok, out.partial = nil, nil, nil, nil

  local cyc = T.Cycles(events, n, score, h, model, out._cyc)
  out._cyc = cyc
  out.nCycles = cyc.n
  local c = (cycleIndex and cycleIndex >= 1 and cycleIndex <= cyc.n) and cyc[cycleIndex] or nil
  if not c or not c.t0 then return clearReplay(out) end

  local t0, t1 = c.t0, c.t1
  out.t0, out.t1, out.cycle, out.index = t0, t1, t1 - t0, cycleIndex
  out.paper, out.played, out.ok, out.partial = c.paper, c.played, c.ok, c.partial

  -- 1. The PAPER's notes for this cycle position, seated on the release that
  --    opened it: the layout is written with its first auto STARTING at 0 while
  --    a cycle starts at a RELEASE, so a note's offset is its distance from the
  --    release of the layout auto this cycle belongs to. Same alignment T.Strip's
  --    forecast and the grader's own notes use.
  local windows = score and score.windows
  local w = (c.wi and c.wi > 0 and windows) and windows[c.wi] or nil
  local lay = w and layoutFor(cyc, model, h, w) or nil
  local windup = (lay and lay.wu) or (0.5 / (h.rangedMul or 1))
  if lay and lay.autos > 0 and lay.rel and lay.ev and lay.dur > 0 then
    local rel, ev, dur, autos = lay.rel, lay.ev, lay.dur, lay.autos
    local phase = (c.wk or 0) % autos
    local lo = rel[phase + 1]
    local hi = (phase + 1 < autos) and rel[phase + 2] or (rel[1] + dur)
    for i = 1, #ev do
      local pe = ev[i]
      local lane = PAPER_LANE[pe.sym]
      if lane and CYCLE_SYM[pe.sym] then
        -- The tail after the last auto wraps into the last cycle (paperCycles').
        local pt = pe.t0
        if pt < rel[1] - 1e-9 then pt = pt + dur end
        if pt >= lo - 1e-9 and pt < hi - 1e-9 then
          local g0 = pt - lo
          local g1 = g0 + pe.dur
          if CAST_SYM[pe.sym] then g1 = castT1(g0, g1) end
          addReplay(out, lane, g0, g1, pe.sym, true, nil)
        end
      end
    end
  end

  -- 2. What was PLAYED there. Each thing belongs to the cycle by the SAME moment
  --    T.Cycles counts it by — a cast by its press (`t0`), a weave by its hit —
  --    so a card and its `played` caption place the same press in the same cycle.
  --    A weave's drawn span still starts 0.2 s before the hit (the lunge, as
  --    every other view draws it), which can put its left edge a shade before 0;
  --    that is honest, and the card clips it.
  --
  --    Two things are drawn that the caption does NOT list. A CANCELLED cast
  --    never became a shot, so `played` leaves it out — but a card that showed
  --    nothing where the player pressed and let go would be hiding the very
  --    thing being explained, so it is drawn, labelled `cancelled` (the same
  --    call T.Build and T.Strip make). And the auto, below.
  --
  --    The auto is the exception, because neither string counts it: it belongs
  --    to the cycle whose WIND-UP it occupies. That is what puts the auto a late
  --    cast clipped — the one that CLOSES the cycle — on the card, and leaves the
  --    one that opened it to the cycle before. It carries the clip tag.
  local match = score and score.match
  for i = 1, n do
    local ev = events[i]
    local kind = ev.kind
    if kind == "auto" then
      local s = ev.t - windup
      if s >= t0 - 1e-9 and s < t1 - 1e-9 then
        addReplay(out, "shots", s - t0, ev.t - t0, "a", false,
                  ((ev.delay or 0) > 0.03) and delayLabel(ev) or nil)
      end
    elseif kind == "cast" then
      if belongs(match, ev, ev.t0, t0, t1, cycleIndex) then
        addReplay(out, "shots", ev.t0 - t0, castT1(ev.t0, ev.t1) - t0, SYM[ev.spell] or "s", false,
                  ev.cancelled and "cancelled" or nil)
      end
    elseif kind == "melee" then
      if belongs(match, ev, ev.t, t0, t1, cycleIndex) then
        addReplay(out, "weave", ev.t - 0.2 - t0, ev.t - t0, ev.hit, false, (ev.hit == "r") and "Raptor" or nil)
      end
    elseif kind == "kc" then
      if ev.t >= t0 - 1e-9 and ev.t < t1 - 1e-9 then
        addReplay(out, "weave", ev.t - 0.1 - t0, ev.t + 0.1 - t0, "KC", false, "KC")
      end
    end
  end

  return clearReplay(out)
end

local Nock = rawget(_G, "Nock")
if Nock then Nock.PracticeTimeline = T end
return T
