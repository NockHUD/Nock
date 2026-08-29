-- Core/PracticePlan.lua
-- The one answer to "what do I press next": Nock.state.sim.plan, built once per tick from the grader's cycles and the engine's grid.
--
-- Everything the practice surfaces show as ADVICE -- the medallion, the
-- rotation row, WeaveCoach's GO, the conveyor's NEXT, the coach line -- READS
-- this table. Nothing else computes it. Seated cycles come from the grader
-- (measured releases); the cycles ahead are seated on the engine's shot grid
-- with the grader's own routine (G.SeatCycle), so a projected note's key and
-- time are exactly what the grader will hold once that release lands.
--
-- Pure: no WoW API, no allocation after P.New. Modules/Practice.lua fills the
-- `src` table and calls P.Build from Practice:Step, BEFORE any module Refresh
-- runs, so no consumer can ever read a plan a tick old.
local P = {}

local PENDING, HIT, MISSED = "pending", "hit", "missed"
P.PENDING, P.HIT, P.MISSED = PENDING, HIT, MISSED
P.MAX_NOTES, P.MAX_AUTOS, P.MAX_CYCLES = 96, 16, 24
-- Which row a paper symbol lives on. `r` (a played Raptor) shares the weave row.
P.ROW = { s = "s", m = "m", A = "A", w = "w", r = "w" }
P.ROW_ORDER = { "auto", "s", "m", "A", "w", "cd" }
-- Base cast times for a note's drawn length. Arcane is an instant with a
-- minimum drawn width (T.MIN_CAST_DRAW owns the pixels; this is the time).
P.CAST_BASE = { s = 1.5, m = 0.5, A = 0 }
P.ARCANE_DUR = 0.15
-- A weave note is drawn as long as the weave TAKES -- the player's measured
-- footwork (src.weaveDur, the grader's legs) -- and never thinner than this:
-- a zero-width note has no room for a rectangle, an icon or the word NEXT.
P.WEAVE_DRAW_MIN = 0.5
-- How far ahead of the weave note Raptor becomes THE press when the player's
-- own step-in time is unknown (no grader). With one, GO leads by exactly that
-- measured step-in (`weave.moveAt`): start walking now, land the hit on the
-- note. Stepping in earlier lands in the dead zone; until then the weave is
-- "next-next" and the HUD asks for nothing.
P.WEAVE_LEAD = 0.5
-- How far a moved cast may run into the wind-up and still be asked for (a
-- clip that small costs less than holding the rotation a shot). See
-- retimeShots. Strict when the paper's instant can take the room instead.
P.FIT_SLACK = 0.15
-- How far past the release that closes its cycle a note may still be asked
-- for (a judgment's slack); pushed further it is lost, not carried. See
-- retimeShots.
P.HOLD_SLACK = 0.25
-- What a second of idle GCD costs against a second of delayed auto (the
-- idle-vs-clip choice in retimeShots): Steady 1.1 per 1.5 s GCD against
-- auto 1.0 per 1.93 s swing.
P.GCD_WORTH = 1.4
-- How far ahead (in cycles) an instant may be pulled forward from its paper
-- slot into room a cast cannot use. Unbounded, an Arcane three cycles out was
-- pulled the tick its slot crossed the view's horizon -- it popped into being
-- at the hit line (the Arcane's "random popping", 2026-08-25) -- and one
-- nine seconds out was pulled and pushed back as the chain shifted. Two
-- cycles is always inside the view (its floor is 4.5 s), so a pull is a
-- glide from where the note already stands.
P.PULL_REACH = 2
-- A hand's reaction. An ask within this much of now is the press being made:
-- it stays asked, and the note is not re-tested against the wind-up for it.
-- Without it a Steady that fit AT its slot no longer fit 40 ms later (the
-- ghost presses the tick after the ask), an Arcane was pulled in front and
-- every Steady behind it jumped a GCD -- the shift every 35 s (2026-08-25).
P.REACTION = 0.15
-- How far behind the hand's free moment a kept future ask may stand before it
-- is re-derived (the hand would idle that long). Within it the ask is kept for
-- stability (see retimeShots).
P.KEEP_SLACK = 0.5
-- WEAVE FIRST (user, 2026-08-26): a weave lands a step-in after the REAL
-- release of its cycle, and the cycle's shots follow its step-out. The seat
-- already carries a step-in off the paper's grid; it is re-floored only when
-- the real release stands more than this behind it (the auto waited on a
-- cast), never for the odd 50 ms between two step-in estimates.
P.WEAVE_FLOOR_SLACK = 0.1
-- ...and reaches a note this far behind the clock: on the tick the auto fires
-- the grader re-seats the weave on ITS grid (the paper's ideal release + a
-- step-in), which stands before the real release when a cast held the auto
-- -- a hit there is physically impossible, and left alone the note jumped
-- back 0.2 s (a flip) and every hit read LATE (2026-08-26).
P.WEAVE_FLOOR_PAST = 0.6
local EPS = 1e-9
-- Float slack between the engine's ready time and a note's own time, not a
-- grace: a cooldown that ends a millisecond after the slot is still up.
local CD_EPS = 1e-3

-- Scratch for rows() before the pull, when no symbol set has been published.
local has = { s = false, m = false, A = false, w = false, r = false }

local function spellFor(sym)
  -- The pure tests run without the addon table; a plan without spell ids is
  -- still a plan (nextSym/nextKey carry the answer).
  local N = rawget(_G, "Nock")
  local S = N and N.Constants and N.Constants.SpellID
  if not S then return nil end
  if sym == "s" then return S.STEADY_SHOT end
  if sym == "m" then return S.MULTI_SHOT end
  if sym == "A" then return S.ARCANE_SHOT end
  if sym == "w" or sym == "r" then return S.RAPTOR_STRIKE end
  return nil
end
P.SpellFor = spellFor

function P.New()
  local plan = { rev = 0, live = false, pulled = false, now = 0, t0 = 0, notation = nil,
                 n = 0, notes = {}, nextIdx = nil, nextKey = nil, nextSym = nil,
                 nextSpellId = nil, nextNextSpellId = nil,
                 nRows = 0, rows = {}, nAutos = 0, autos = {},
                 weave = { at = nil, room = 0, fits = false, openNow = false, noteAt = nil, moveAt = nil },
                 reason = nil }
  for i = 1, P.MAX_NOTES do
    plan.notes[i] = { key = nil, row = nil, sym = nil, t0 = 0, t1 = 0, cycle = 0, idx = 0,
                      playable = true, state = PENDING, grade = nil, raptor = false }
  end
  for i = 1, P.MAX_AUTOS do plan.autos[i] = { key = nil, windupAt = 0, releaseAt = 0, cycle = 0 } end
  -- Scratch record for projected cycles: the grader's own shape.
  plan._rec = { n = 0, nT0 = {}, nSym = {}, nKey = {}, nUsed = {}, nState = {}, nGrade = {}, nChained = {}, lastNote = nil }
  -- Scratch for retimeShots: the pending shot notes in time order, and which
  -- of them the walk has already placed.
  plan._ord, plan._used = {}, {}
  for i = 1, P.MAX_NOTES do plan._ord[i] = 0; plan._used[i] = false end
  -- The time this plan last ASKED for each note, by key (retimeShots' claim):
  -- what the hand was answering when it pressed.
  plan._askT = {}
  -- Notes this plan gave up on (retimeShots' hold limit), by key: sticky for
  -- the fight, so a note lost one tick is not asked for again the next.
  plan._lost = {}
  -- The release a held ask was held TO, by key: when that release moves
  -- earlier the ask follows it (a hold is pinned to a release, not a clock).
  plan._deferred = {}
  return plan
end

local function noteDur(sym, src)
  if sym == "A" then return P.ARCANE_DUR end
  local base = P.CAST_BASE[sym]
  if base then return (src.model or Nock.PracticeModel).CastTime(base, src.rangedMul or 1, src.castCorr or 1) end
  -- w: the weave itself, in / hit / out.
  local d = src.weaveDur or 0
  if d < P.WEAVE_DRAW_MIN then d = P.WEAVE_DRAW_MIN end
  return d
end

-- Can the sim press this note when it comes round? The engine owns Multi's and
-- Arcane's ready times; a WEAVE note needs the melee swing up by its time --
-- or by now, for a note whose time has passed: a `w` seated a second ago while
-- the swing is still recharging from the last hit is not the next press, and
-- it used to wear NEXT from the past.
local function playable(sym, t0, src)
  local ready
  if sym == "m" then ready = src.msReadyAt
  elseif sym == "A" then ready = src.arcReadyAt
  elseif sym == "w" then
    ready = src.meleeReadyAt
    if t0 < src.now then t0 = src.now end
  end
  if ready and ready > t0 + CD_EPS then return false end
  return true
end

-- THE HAND'S CLOCK. The paper seats every note on its ideal slot; the engine
-- takes a press only when no cast runs and the GCD (a flat 1.5 s for a TBC
-- hunter) is free. The two part company at every seam -- the opener's GCD runs
-- 0.2 s past the first auto; one late press pushes the next -- and a plan that
-- kept asking for the ideal slot asked for presses the engine dropped: the
-- demo ghost, pressing exactly when free, played 5:5:1:1 into a CLIP every
-- cycle (2026-08-25). So the pending shot notes are walked in time order with
-- a cursor that is when the hand is next free:
--   * a note before the cursor moves to it;
--   * a cast that would then run into its cycle's wind-up (or a press made
--     inside it) is held to the RELEASE, exactly as the client holds it -- and
--     when there was room before the wind-up, the paper's instant that fits
--     (a Multi whose cast fits, an Arcane) is pulled forward into it: the
--     grader's own STEADY WON'T FIT advice, now said before the press instead
--     of after;
--   * the cursor then moves past that press's GCD (or its cast, if longer).
-- Weave notes are off the GCD and are the swing chain's business (`put`).
-- Pre-pull there is no grid and nothing to hold: the paper stands as written.
-- The first release strictly after `t`, off the plan's OWN grid (plan.autos,
-- which delayGrid pushes behind the casts the plan asks for); the pure grid
-- past the last projected auto.
local function releaseAfter(plan, src, t)
  local autos = plan.autos
  for i = 1, plan.nAutos do
    local r = autos[i].releaseAt
    if r > t + EPS then return r end
  end
  local cycle, nsa = src.cycle or 0, src.nextShotAt or 0
  -- Past the last projected auto: whole cycles from it (pre-pull there is no
  -- nextShotAt at all; the seated grid is the only one).
  if plan.nAutos > 0 then nsa = autos[plan.nAutos].releaseAt end
  local rel = nsa + math.ceil((t - nsa) / cycle + EPS) * cycle
  if rel < nsa then rel = nsa end
  return rel
end

-- The paper's delay budget for the projected auto at `rel` (0 off the grid).
local function dlyAt(plan, rel)
  local autos = plan.autos
  for i = 1, plan.nAutos do
    if math.abs(autos[i].releaseAt - rel) < 0.05 then return autos[i].dly or 0 end
  end
  return 0
end

-- THE AUTOS WAIT BEHIND THE CASTS. The engine fires an auto only once the
-- cast that overran its wind-up has ended (release = cast end + wind-up),
-- and a clip-by-design paper does that on purpose every cycle -- so a
-- projected grid of next shot + n cycles sat 0.2-0.4 s early and every auto
-- marker jumped when the shot really went out (gate, 2026-08-25). Each
-- projected release is pushed behind any planned (or running) cast that
-- spans its wind-up, the releases after it chain from there, and the cycle
-- seated on it moves with it. Returns true when anything moved.
local function delayGrid(plan, src, placedOnly)
  local cycle, windup = src.cycle or 0, src.windup or 0
  if cycle <= 0 then return false end
  local notes, autos = plan.notes, plan.autos
  local changed = false
  local prev
  for i = 1, plan.nAutos do
    local a = autos[i]
    -- From the BASE grid each pass: a delay decided on the paper's slots
    -- (the Multi behind the wind-up) must come back when the walk moves that
    -- cast (the Multi held to the release), or the grid only ever grows.
    local rel = a.base or a.releaseAt
    if prev and rel < prev + cycle then rel = prev + cycle end
    local wu = rel - windup
    if src.castStart and src.castEnd and src.castStart < wu - EPS and src.castEnd > wu + EPS then
      rel = src.castEnd + windup; wu = rel - windup
    end
    for j = 1, plan.n do
      local nt = notes[j]
      if nt.state == PENDING and nt.playable and nt.row ~= "w" and nt.sym ~= "A" and (not placedOnly or nt.placed) then
        local c0 = nt.cast0 or nt.t0
        local c1 = c0 + (nt.t1 - nt.t0)
        if c0 < wu - EPS and c1 > wu + EPS then rel = c1 + windup; wu = rel - windup end
      end
    end
    local delta = rel - (a.base or a.releaseAt)
    if math.abs(rel - a.releaseAt) > EPS then
      if rawget(_G, "NOCK_PLAN_DBG") then
        print(("DELAY auto%d c%d %.3f -> %.3f (prev %s cast %s..%s)"):format(i, a.cycle, a.releaseAt - (plan.t0 or 0), rel - (plan.t0 or 0),
          prev and ("%.3f"):format(prev - (plan.t0 or 0)) or "-", src.castStart and ("%.3f"):format(src.castStart - (plan.t0 or 0)) or "-", src.castEnd and ("%.3f"):format(src.castEnd - (plan.t0 or 0)) or "-"))
      end
      a.releaseAt, a.windupAt = rel, rel - windup
      changed = true
      delta = rel - (a.seated or a.releaseAt)
      a.seated = rel
      -- The cycle this release opens moves with it: its paper slots, and
      -- every note still ON its slot (an asked-for time -- a hold or a
      -- pull-forward -- is a promise and stays).
      for j = 1, plan.n do
        local nt = notes[j]
        if nt.cycle == a.cycle and nt.row ~= "w" then
          local onSlot = math.abs(nt.t0 - nt.slot) < EPS
          nt.slot = nt.slot + delta
          if onSlot then
            local d = nt.t1 - nt.t0
            nt.t0 = nt.slot; nt.t1 = nt.slot + d
          end
        end
      end
    end
    prev = rel
  end
  -- ...and the release that CLOSES each cycle moved too: a note's hold limit
  -- (endAt) is the next cycle's release.
  if changed then
    for j = 1, plan.n do
      local nt = notes[j]
      if nt.endAt then
        for i = 1, plan.nAutos do
          if autos[i].cycle == nt.cycle + 1 then nt.endAt = autos[i].releaseAt; break end
        end
      end
    end
  end
  return changed
end

-- A WEAVE NEVER WALKS INSIDE A CAST. Moving cancels the cast, so every
-- pending weave note is placed after the cast in front of it -- the one
-- running now (src.castEnd) and any placed shot that starts before the hit
-- and runs past the walk's start -- a step-in later, then clear of the
-- wind-up (G.FitWeave); the weaves behind it keep one melee cycle apart.
-- The stage asked for the weave mid-Steady (user, 2026-08-26). Derived from
-- the placed shots every build, so it moves only when they do.
local function retimeWeaves(plan, src, now)
  if not plan.pulled then return end
  local stepIn = src.weaveStepIn or P.WEAVE_LEAD
  local N = rawget(_G, "Nock")
  local fit = src.fit or (N and N.PracticeGrader and N.PracticeGrader.FitWeave)
  local cycle, windup = src.cycle or 0, src.windup or 0
  local castEnd = (src.castSym and (src.castEnd or 0) > now) and src.castEnd or 0
  local lastHit = nil
  -- In time order.
  local ord = plan._wOrd
  if not ord then ord = {}; plan._wOrd = ord end
  local n = 0
  for i = 1, plan.n do
    local w = plan.notes[i]
    if w.sym == "w" and w.state == PENDING and not w.lost then n = n + 1; ord[n] = i end
  end
  for i = n + 1, #ord do ord[i] = nil end
  table.sort(ord, function(a, b) return plan.notes[a].t0 < plan.notes[b].t0 end)
  for k = 1, n do
    local w = plan.notes[ord[k]]
    -- A note already behind the clock is the grader's to sweep: dragging it
    -- behind the NEXT cast jumped it two seconds every period (2:2 1w).
    if w.t0 < now - EPS then
      -- ...but a note that was tight stays tight until it is swept (the
      -- ghost weaved on one that came back plain in the past, cancelling the
      -- next cycle's Steady).
      if plan._wTight and plan._wTight[w.key] then w.tight = true end
      if w.playable then lastHit = w.t0 end
    else
    -- The running cast counts only when it is IN FRONT of the weave.
    local busy = (castEnd > 0 and (src.castStart or 0) < w.t0 - EPS) and castEnd or 0
    for j = 1, plan.n do
      local o = plan.notes[j]
      if (o.sym == "s" or o.sym == "m") and not o.lost then
        -- The cast's REAL span: a queued press is drawn at the press and
        -- casts from the release (nt.cast0). Read at the press, the weave
        -- flipped between behind-the-Steady and not, every release.
        local c0 = o.cast0 or o.t0
        local c1 = c0 + (o.t1 - o.t0)
        if c0 < w.t0 - EPS and c1 > w.t0 - stepIn + EPS and c1 > busy then busy = c1 end
      end
    end
    local t0 = w.t0
    local seat0 = t0
    if busy > t0 - stepIn + EPS then t0 = busy + stepIn end
    -- No cast in front: not tight, whatever an earlier build found (the flag
    -- stuck by key and every later weave stayed tight -- the ghost skipped
    -- them all, 5:5:1:1 3w in-game 1/3, 2026-08-26).
    if busy <= 0 and plan._wTight then plan._wTight[w.key] = nil end
    -- The chain runs from the weaves the swing can make (put's own rule).
    if lastHit and t0 < lastHit + (src.meleeCycle or 0) - EPS then t0 = lastHit + (src.meleeCycle or 0) end
    -- Sticky, one way: a weave moved behind a cast stays there when that
    -- cast leaves the plan (behind the past horizon) and the seat it would
    -- snap back to is already PAST -- that snap was a blink and a MISSED. An
    -- earlier seat still ahead (the swing returning before the paper slot)
    -- is a real opportunity and is taken.
    local wmin = plan._wMin
    if not wmin then wmin = {}; plan._wMin = wmin end
    if wmin[w.key] and t0 < wmin[w.key] - EPS and t0 <= now + EPS then t0 = wmin[w.key] end
    if t0 > w.t0 + EPS then
      -- Does it still fit ITS cycle? A weave that does not is not pushed to
      -- the next one -- on a paper with a Steady in every cycle it never
      -- fits anywhere and wandered forward for ever (2:2 1w at a fast bow,
      -- the sweep 2026-08-26). It stays where the paper put it, UNPLAYABLE:
      -- dimmed on the stage, skipped by NEXT and the ghost, the coach's
      -- "too small for a full weave" (plan.reason = tight).
      if fit and cycle > 0 then
        local rel = releaseAfter(plan, src, t0 - cycle)
        if rel and rel > t0 then rel = rel - cycle end
        if rel and rel <= t0 then
          local fitted = fit(t0, rel, cycle, windup, src.weaveFit or src.weaveDur, stepIn)
          local wt = plan._wTight
          if not wt then wt = {}; plan._wTight = wt end
          if fitted > rel + cycle - EPS then
            -- TIGHT, still ASKED: the paper is the law and a human's legs
            -- may make it (a 0.72 s room behind a Steady at eWS 2.17 with
            -- a 0.4 s step-in is a knife-edge, not a wall) -- the player
            -- saw "missing weaves" on 5:5:1:1 3w when this made the note
            -- unplayable (2026-08-26). The ghost, whose legs are fixed,
            -- skips a tight note; the coach names it.
            w.tight = true
            wt[w.key] = true
            t0 = (w.t0 > busy + stepIn) and w.t0 or (busy + stepIn)
          else
            -- Room again (the cast in front ended sooner): playable after all.
            wt[w.key] = nil
            t0 = fitted
          end
        end
      end
      local dt = t0 - w.t0
      w.t0, w.t1 = t0, w.t1 + dt
    end
    if rawget(_G, "NOCK_PLAN_DBG") then
      print(("WEAVE %.2f k=%s seat=%.2f busy=%.2f castEnd=%.2f wmin=%s -> %.2f state=%s play=%s tight=%s"):format(
        now - (plan.t0 or 0), tostring(w.key), seat0 - plan.t0, busy > 0 and busy - plan.t0 or 0, castEnd > 0 and castEnd - plan.t0 or 0,
        wmin[w.key] and ("%.2f"):format(wmin[w.key] - plan.t0) or "-", w.t0 - plan.t0, tostring(w.state), tostring(w.playable), tostring(w.tight)))
    end
    wmin[w.key] = w.t0
    if w.playable then lastHit = w.t0 end
    end
  end
end

-- WEAVE FIRST, step 1: every pending weave still ahead lands on its cycle's
-- REAL release + step-in. Runs BEFORE the shot walk, so the walk keeps the
-- casts out of the weave where the weave will actually be (see startFor).
-- The grid runs from the next shot, so on the tick an auto fires its release
-- is not on it: the shot that just went out (src.lastShotAt) stands in.
local function floorWeaves(plan, src, now)
  if not plan.pulled then return end
  local cycle = src.cycle or 0
  if cycle <= 0 then return end
  local stepIn = src.weaveStepIn or P.WEAVE_LEAD
  local mc = src.meleeCycle or 0
  -- In time order, so the swing chain (retimeWeaves' own rule: a hit no
  -- earlier than one melee cycle after the hit before it) is applied HERE
  -- too -- applied only after the walk, it moved a weave under the Steady
  -- the walk had just placed clear of it (plan test 9).
  local ord = plan._wOrd
  if not ord then ord = {}; plan._wOrd = ord end
  local n = 0
  for i = 1, plan.n do
    local w = plan.notes[i]
    if w.sym == "w" and w.state == PENDING and not w.lost then n = n + 1; ord[n] = i end
  end
  for i = n + 1, #ord do ord[i] = nil end
  table.sort(ord, function(a, b) return plan.notes[a].t0 < plan.notes[b].t0 end)
  -- The floor needs the seat's own step-in (the grader's, src.weaveStepIn):
  -- with a default in its place the floor and the seat disagreed by their
  -- difference and every note moved (plan test 5).
  local canFloor = src.weaveStepIn ~= nil
  -- The running cast is fixed (in flight): a weave it stands in front of
  -- goes behind it here, so the walk and the chain see the hit where it
  -- will be (retimeWeaves used to do this after the walk, and the chained
  -- weave behind it landed under a Steady the walk had placed clear of it).
  local castEnd = (src.castSym and (src.castEnd or 0) > now) and src.castEnd or 0
  local lastHit
  for k = 1, n do
    local w = plan.notes[ord[k]]
    if w.t0 < now - P.WEAVE_FLOOR_PAST then
      if w.playable then lastHit = w.t0 end
    else
      local t0 = w.t0
      local relW = releaseAfter(plan, src, t0 - 0.6 * cycle)
      if not (relW and relW < t0 + 0.4 * cycle) then
        local last = src.lastShotAt or 0
        relW = (last > 0 and t0 - last < 0.6 * cycle and last < t0 + 0.4 * cycle) and last or nil
      end
      if canFloor and relW and t0 < relW + stepIn - P.WEAVE_FLOOR_SLACK then t0 = relW + stepIn end
      if castEnd > 0 and (src.castStart or 0) < t0 - EPS and castEnd > t0 - stepIn + EPS then t0 = castEnd + stepIn end
      if lastHit and mc > 0 and t0 < lastHit + mc - EPS then t0 = lastHit + mc end
      if t0 > w.t0 + EPS then
        local dt = t0 - w.t0
        w.t0, w.t1 = t0, w.t1 + dt
      end
      if w.playable then lastHit = w.t0 end
    end
  end
end

local function retimeShots(plan, src, now)
  local cycle, nsa = src.cycle or 0, src.nextShotAt or 0
  local pulled = plan.pulled and nsa > 0
  if not plan.live or cycle <= 0 then return end
  -- PRE-PULL TOO: the same chain from the pull press (the hand is free a GCD
  -- after it), on the seated grid -- so the notes stand where the pull will
  -- ask for them and nothing glides at the first press (the first Steady
  -- moved 0.2 s, seated a cast + wind-up out, asked a GCD out).
  if not pulled then
    if plan.nAutos == 0 then return end
    nsa = plan.autos[1].releaseAt
  end
  local gcd, windup = src.gcd or 1.5, src.windup or 0
  local free = pulled and (src.gcdEnd or 0) or (plan.t0 + gcd)
  if pulled and (src.castEnd or 0) > free then free = src.castEnd end
  local notes, ord, used = plan.notes, plan._ord, plan._used
  -- A RUNNING CAST CLAIMS ITS NOTE. The grader marks a note HIT when the cast
  -- ENDS; for the whole cast the note is still pending here, the GCD its press
  -- started is on the cursor, and the walk pushed that very note to the next
  -- release -- so the grader, matching by the plan's time when the cast ended,
  -- filed it against an older note, every Steady one note behind (gate trace,
  -- 2026-08-25: the flip `next=s@+9.23` / `next=s@+12.87`). The pending note
  -- of the cast's symbol nearest the moment it was pressed -- by the time the
  -- plan ASKED for it then (`_askT`) -- is in flight: frozen at that asked
  -- time, skipped by the walk, never NEXT.
  local askT = plan._askT
  -- ...and a QUEUED press likewise (the client holds it inside the wind-up,
  -- the cast starts at the release): the note is the press already made, at
  -- the press, and the hand's GCD runs from the release. Left pending, its
  -- ask crept with the clock until the cast began and the grader read the
  -- press as a third of a second early (LATE x6, gate 2026-08-26).
  local inflSym, inflAt, inflPress = nil, nil, nil
  if pulled and src.castSym and (src.castEnd or 0) > now then
    inflSym, inflAt = src.castSym, src.castStart or now
  elseif pulled and src.queuedSym then
    inflSym, inflAt, inflPress = src.queuedSym, src.queuedAt or now, src.queuedAt or now
    -- The queued cast starts at the release after its PRESS -- not the one
    -- after `now`: on the tick the release lands (nextShotAt == now, the
    -- snapshot a tick behind the cast start) that is already the NEXT
    -- release, and every shot note jumped a whole cycle for one tick (the
    -- weave papers' blink, 2026-08-26).
    local r = releaseAfter(plan, src, inflAt)
    if r < now - 0.25 then r = releaseAfter(plan, src, now) end
    local d = (inflSym == "A") and 0 or (inflSym == "m" and P.CAST_BASE.m or P.CAST_BASE.s)
    d = (src.model or Nock.PracticeModel).CastTime(d, src.rangedMul or 1, src.castCorr or 1)
    local busy = r + gcd
    if r + d > busy then busy = r + d end
    if busy > free then free = busy end
  end
  -- The hand is free no earlier than NOW. In-game a GCD that has run out
  -- reports gcdEnd 0, and a kept ask tested against THAT "free moment" was
  -- dropped as unreachable every tick the hand was idle -- the beat note
  -- snapped from its ask to the clock the moment the GCD ended (the user's
  -- shifting Steady, 2026-08-26).
  if free < now then free = now end
  if inflSym then
    local best, bestAbs
    for i = 1, plan.n do
      local nt = notes[i]
      if nt.state == PENDING and nt.playable and nt.sym == inflSym then
        local d = (askT[nt.key] or nt.t0) - inflAt
        if d < 0 then d = -d end
        if not bestAbs or d < bestAbs then best, bestAbs = nt, d end
      end
    end
    if best then
      best.inflight = true
      best.placed = true
      if inflPress then askT[best.key] = inflPress end
      local asked = askT[best.key]
      if asked then best.t1 = asked + (best.t1 - best.t0); best.t0 = asked end
    end
  end
  -- The grid behind what is already placed: the running cast, the note in
  -- flight. Every note the walk places below is added to it in turn.
  delayGrid(plan, src, true)
  local n = 0
  for i = 1, plan.n do
    local nt = notes[i]
    -- (never the opener, cycle 0: it is the pull press itself)
    if nt.state == PENDING and nt.playable and nt.row ~= "w" and not nt.inflight and nt.cycle ~= 0 then
      -- IN PAPER ORDER (the key is cycle, then seat), never by asked time:
      -- ordered by ask, a Steady whose stale hold sat later than the next
      -- cycle's Steady was overtaken by it, pushed a cycle and lost.
      n = n + 1
      local j = n
      while j > 1 and notes[ord[j - 1]].key > nt.key do ord[j] = ord[j - 1]; j = j - 1 end
      ord[j] = i
      used[n] = false
    end
  end
  -- THE PAPER IS THE LAW (Plan B, round 2, 2026-08-26). The walk places the
  -- paper's notes in the paper's order, each the moment the hand is free -- a
  -- beat note no earlier than its slot -- whether or not the cast fits before
  -- the wind-up. The paper wrote its sequence so that its casts overrun where
  -- they must and the autos wait behind them (M.Layout's own greedy rule);
  -- the plan's grid follows the same rule (delayGrid), so a clip the paper
  -- plays is a clip the plan shows. The one thing the client adds is the
  -- queue: a press inside the wind-up casts at the release (nt.cast0).
  --
  -- Testing every moved note for fit and idling, queueing or swapping it
  -- away (the first Plan B round) held the hand to ONE Steady per weapon
  -- cycle on a 7-GCD-per-5-auto paper: the paper's extra notes piled up two
  -- a period, the carried cycles grew to eight notes and the strip ran ten
  -- seconds behind the hand by the second minute.
  --
  -- An instant whose cooldown is not back by the time its turn comes is
  -- DEFERRED, not waited for: the notes after it chain on, and it is placed
  -- the moment it is ready -- before the next note whose turn that is. That is
  -- how the hand plays a Multi that the paper's cadence asks for a little too
  -- soon: the next Steady goes first.
  -- WEAVE FIRST (user, 2026-08-26). The release a weave lands on belongs to
  -- the weave: the auto has just gone out, the whole cycle is room, and the
  -- step-out leaves the hand at range with the instant (or the Steady) as
  -- the catch-up -- "weave -> Arcane is the fastest and cleanest weave we
  -- have". Read literally, `a s w` queued the Steady into the wind-up so it
  -- cast AT the release, the weave went behind it and landed tight, and the
  -- ghost skipped it every period on 5:5:1:1 3w while the Arcane took the
  -- room. So every shot note that would start inside a weave's reservation
  -- -- the release to the end of the step-out (`src.weaveDur`, the measured
  -- legs) -- starts at the end of it instead, and retimeWeaves floors the
  -- weave at that release + step-in (it used to sit on the paper's ideal
  -- release, 0.3 s before the real one).
  local wStepIn = src.weaveStepIn or P.WEAVE_LEAD
  local wres = src.weaveDur or src.weaveFit or 0.65
  if wres < wStepIn + 0.2 then wres = wStepIn + 0.2 end
  -- The end of the walk of any pending weave a cast [c0, c0+dur] would
  -- overlap (start inside it, or span its start); nil when none.
  -- (An instant goes out while moving, but it is a RANGED ability: the
  -- step-out has to be over first -- user, 2026-08-26. So every shot waits
  -- for the whole walk; "weave -> Arcane" is the Arcane the moment you are
  -- back at range.)
  local function weaveClear(c0, dur)
    local best
    for i = 1, plan.n do
      local w = notes[i]
      if w.sym == "w" and w.state == PENDING and not w.lost and w.playable then
        local ws, we = w.t0 - wStepIn, w.t0 - wStepIn + wres
        if c0 < we - EPS and c0 + dur > ws + EPS and (not best or we > best) then best = we end
      end
    end
    return best
  end
  local function startFor(nt)
    local start = free
    if start < now then start = now end       -- the hand presses no earlier than now
    if nt.sym == "m" and (src.msReadyAt or 0) > start then start = src.msReadyAt end
    if nt.sym == "A" and (src.arcReadyAt or 0) > start then start = src.arcReadyAt end
    -- A NOTE ON THE BEAT LETS ITS AUTO GO FIRST. The paper's string puts an
    -- `a` before it ("a s": the layout waits for the auto, winds up, releases,
    -- THEN casts), and that is what the gap in the paper means -- not the
    -- ideal clock it happened to fall on. So a beat note whose cast would
    -- push the auto ahead of it is queued into that auto's wind-up and
    -- casts at the release, as the paper plays it; one that fits before the
    -- wind-up is pressed when the hand is free (the auto is untouched either
    -- way, and earlier is better). Floored at the paper's SLOT instead, the
    -- note sat on an ideal release the real grid had left 0.4 s behind and
    -- jumped the moment the hand freed (in-game, 2026-08-26). Only the auto
    -- the paper put before it counts: a hand so late that this release has
    -- gone presses now.
    -- (P.NO_CLIP: the experiment's "never clip" hand -- every cast waits for
    -- the auto it would push, chained or not. Sim only; see the DPS note.)
    if not nt.chained or P.NO_CLIP then
      local dur = (nt.sym == "A") and 0 or (nt.t1 - nt.t0)
      local rel = releaseAfter(plan, src, start)
      local wu = rel - windup
      if dur > 0 and start < wu - EPS and start + dur > wu + EPS
         and (P.NO_CLIP or rel <= (nt.slot or start) + 0.5 * cycle + EPS) then
        start = wu
      end
    end
    -- WEAVE FIRST: a shot that would start on a release a weave takes -- the
    -- queued cast (cast0 = the release) or a press inside the step-out --
    -- follows the step-out.
    do
      local dur = (nt.sym == "A") and 0 or (nt.t1 - nt.t0)
      local rel = releaseAfter(plan, src, start)
      local wu = rel - windup
      local c0 = (start >= wu - EPS and start < rel - EPS) and rel or start
      local clear = weaveClear(c0, dur)
      if clear and clear > start then start = clear end
    end
    -- AN ASK IS NOT RETRACTED. A note held to the release snapped back to its
    -- paper slot the tick the release passed (it "fit now"), so the press made
    -- on the plan's word was graded against a slot 0.4 s older and the cycle
    -- swept it MISSED (gate, 2026-08-25). Once asked for at a time, a note is
    -- never asked for earlier.
    local asked = askT[nt.key]
    -- ...and only an ask whose moment has PASSED pins (a note must never
    -- jump back across the hit line); a future ask is re-derived every
    -- build -- pinned, a note asked for behind a Steady that was later
    -- lost kept the hand idle 1.5 s (gate, 2026-08-25).
    -- A FUTURE ask is kept while it is still a legal press -- reachable
    -- (not before the hand is free) and, tested below, still fitting where
    -- it stands; else re-derived. Re-deriving every future ask each build
    -- let a 0.3 s change up the chain (a press queued rather than made)
    -- flip an idle-or-clip call downstream and jump three notes a GCD.
    local future = asked and asked > now + P.REACTION + EPS
    if future and (asked < free - EPS or asked > free + P.KEEP_SLACK) then asked = nil; future = false end
    if asked and asked > start then start = asked end
    -- A past ask within a reaction HOLDS: the hand is pressing it. Floored
    -- at the clock it crept a tick a tick until the press landed, and every
    -- note behind it crept with it (and flipped its own idle-or-clip call).
    if asked and asked <= now + EPS and now - asked <= P.REACTION and free <= asked + EPS then start = asked end
    return start
  end
  local function placeNote(nt, start)
    local dur = (nt.sym == "A") and 0 or (nt.t1 - nt.t0)
    local rel = releaseAfter(plan, src, start)
    local wu = rel - windup
    local queued = (start >= wu - EPS and start < rel - EPS)
    nt.cast0 = queued and rel or nil
    nt.placed = true
    if rawget(_G, "NOCK_PLAN_DBG") then
      print(("WALK %.2f %s c%d slot=%.2f asked=%s start=%.2f free=%.2f chained=%s cast0=%s"):format(
        now - (plan.t0 or 0), nt.sym, nt.cycle, (nt.slot or 0) - (plan.t0 or 0), askT[nt.key] and ("%.2f"):format(askT[nt.key] - (plan.t0 or 0)) or "-",
        start - (plan.t0 or 0), free - (plan.t0 or 0), tostring(nt.chained),
        nt.cast0 and ("%.2f"):format(nt.cast0 - (plan.t0 or 0)) or "-"))
    end
    if math.abs(start - nt.t0) > EPS then
      nt.t1 = start + (nt.t1 - nt.t0)
      nt.t0 = start
    end
    -- The hand is busy from the CAST's start (a queued cast starts at the
    -- release) for the GCD or the cast, whichever is longer.
    local c0 = nt.cast0 or start
    if c0 < start then c0 = start end
    local busy = c0 + gcd
    if c0 + dur > busy then busy = c0 + dur end
    if busy > free then free = busy end
    delayGrid(plan, src, true)
  end
  local function readyAt(nt)
    if nt.sym == "m" then return src.msReadyAt or 0 end
    if nt.sym == "A" then return src.arcReadyAt or 0 end
    return 0
  end
  local deferred = plan._deferred
  local nd = 0
  local function flushDeferred(upTo)
    local i = 1
    while i <= nd do
      local nt = notes[deferred[i]]
      if readyAt(nt) <= upTo + EPS then
        for j = i, nd - 1 do deferred[j] = deferred[j + 1] end
        deferred[nd] = nil
        nd = nd - 1
        placeNote(nt, startFor(nt))
      else
        i = i + 1
      end
    end
  end
  for k = 1, n do
    if not used[k] then
      used[k] = true
      local nt = notes[ord[k]]
      local hand = free
      if hand < now then hand = now end
      if readyAt(nt) > hand + P.KEEP_SLACK + EPS then
        nd = nd + 1
        deferred[nd] = ord[k]
      else
        flushDeferred(startFor(nt))
        placeNote(nt, startFor(nt))
      end
    end
  end
  flushDeferred(math.huge)
end

-- THE SWING CHAINS. Every hit restarts the melee swing, so a weave note can sit
-- no earlier than one melee cycle after the weave before it -- the grader
-- applies that to the cycle it seats (G.RetimeWeaves, off the LAST REAL hit)
-- and the plan carries it on through the cycles it projects, off the hits it
-- is planning. Without it the next cycle's `w` drew 1.5 s after this one's on
-- a 3.7 s weapon (gate footage). `swingAt` is the running "swing back at".
local swingAt = 0

-- Append one note inside the window. Returns false when the plan is full.
local function put(plan, src, key, sym, t0, cycle, idx, state, grade, wt0, wt1, projected, releaseAt, endAt, chained)
  local weave = (sym == "w" or sym == "r")
  -- A projected note already played early on this plan's own word (the grader
  -- remembers it by key until its cycle is seated) is HIT, not asked for again.
  if projected and state == PENDING and src.prePlayed and src.prePlayed[key] then
    state = HIT
    local pg = src.prePlayed[key]
    if type(pg) == "string" then grade = pg end
  end
  if weave and projected then
    if t0 < swingAt - EPS then t0 = swingAt end
    -- ...and never inside the wind-up (G.FitWeave, the grader's own rule).
    local N = rawget(_G, "Nock")
    local fit = src.fit or (N and N.PracticeGrader and N.PracticeGrader.FitWeave)
    if fit then t0 = fit(t0, releaseAt, src.cycle, src.windup, src.weaveFit or src.weaveDur, src.weaveStepIn or P.WEAVE_LEAD) end
  end
  local pl = playable(sym, t0, src)
  -- A Multi or Arcane whose cooldown is back within a PERIOD of its slot is
  -- playable -- the walk defers it behind the notes after it and places it
  -- the moment it is ready (Plan B round 2). One further off is this
  -- period's instant lost to its cooldown: the next period's plays instead.
  -- Judged at its slot alone, a Multi 0.3 s ahead of its cooldown was
  -- unplayable and lost.
  if not pl and not weave and (sym == "m" or sym == "A") then
    local ready = (sym == "m") and src.msReadyAt or src.arcReadyAt
    local reach = (src.lay and src.lay.dur) or ((src.cycle or 0) * 2)
    if ready and reach > 0 and ready <= t0 + reach - CD_EPS then pl = true end
  end
  local lost = plan._lost[key] == true
  if lost then pl = false end
  -- Only a PLANNED hit advances the chain -- a pending note the swing can
  -- make. A note already HIT is in the engine's own swing return (the chain's
  -- starting point, off the real hit time): chaining from the NOTE's time put
  -- the next weave 0.4 s before the real swing when the hit was 0.4 s late --
  -- unplayable, NEXT fell through a cycle, and snapped back at the release.
  -- A seated note the swing cannot reach is not going to be played either.
  if weave and state == PENDING and pl then
    local after = t0 + (src.meleeCycle or 0)
    if after > swingAt then swingAt = after end
  end
  -- The window test is on the time the note is ASKED for (its paper slot, or
  -- the later time the last build asked -- retimeShots' sticky ask): a note
  -- held to the release fell out of the past window by its slot while still
  -- pending, the grader lost its plan time and swept it MISSED.
  -- Behind: out only when BOTH the slot and the asked time are past the edge.
  -- Ahead: by the slot alone -- a note asked for later than the horizon is
  -- still in the plan (it draws off the strip's right edge), or it left and
  -- came back with every push and the strip blinked (ghost gate, 2026-08-25).
  local asked = plan._askT[key]
  local shown = t0
  if asked and asked > shown then shown = asked end
  if shown < wt0 or t0 > wt1 then return true end
  local n = plan.n + 1
  if n > P.MAX_NOTES then return false end
  local nt = plan.notes[n]
  -- The paper's slot is kept apart; the note's own time is the later of the
  -- slot and the time this plan last ASKED for it (retimeShots' sticky ask),
  -- so a shot note never shows a time older than the one it was asked at --
  -- not even for the tick a walk skips it.
  local slot = t0
  if not weave and state ~= MISSED then
    -- Both ways: a hold (later) and a pull-forward (earlier) are promises
    -- alike -- an Arcane pulled into the room one tick and put back on its
    -- slot the next was the last blink (ghost gate, 2026-08-25). A HIT note
    -- keeps it too: an Arcane pulled two seconds forward and pressed there
    -- went back to its paper slot the tick after, a dim square two seconds
    -- ahead with its PERFECT riding it (blinks.mp4). Never a note the sim
    -- cannot press (its cooldown moved after the ask): pinned to a past ask
    -- it sat dim at the hit line and jumped seconds when the cooldown came
    -- back -- the Multi's jump at the minute mark.
    local asked = plan._askT[key]
    if asked and (state ~= PENDING or playable(sym, slot, src)) then t0 = asked end
  end
  nt.key, nt.row, nt.sym, nt.t0, nt.cycle, nt.idx = key, P.ROW[sym], sym, t0, cycle, idx
  nt.t1 = t0 + noteDur(sym, src)
  nt.state, nt.grade = state, grade
  nt.playable = pl
  nt.tight = nil            -- retimeWeaves decides, every build
  nt.inflight = false
  nt.cast0 = nil
  -- A note the plan gave up on (the hold limit): not asked for, not drawn --
  -- pinned under the live note that took its place it read as two Steadies
  -- stacked, which the game cannot do. The grader sweeps it MISSED.
  nt.lost = lost
  -- The PAPER's own slot and the release that closes the note's cycle: what a
  -- moved note is measured against (retimeShots).
  nt.slot = slot
  nt.endAt = endAt
  -- Chained on the GCD to the paper's previous shot (the hand times it), or
  -- on the beat (its slot is a floor). Off the layout, via the grader's seat.
  nt.chained = chained == true
  -- Set by the walk once the note's time is final: only placed notes delay
  -- the grid the notes after them are tested against (a cast must never fit
  -- a grid that already waits for it).
  nt.placed = false
  -- A weave is "hit with what is ready": Raptor when its cooldown is up by the
  -- hit, a white swing otherwise. The note after a white hit already sits on
  -- the NEW swing (RetimeWeaves), and wears Raptor if it is back by then.
  nt.raptor = (sym == "w" or sym == "r") and ((src.raptorReadyAt or 0) <= t0 + CD_EPS) or false
  plan.n = n
  return true
end

local function putCycle(plan, src, rec, cycleIx, wt0, wt1, projected, releaseAt, endAt)
  for i = 1, rec.n do
    local state = rec.nState[i] or (rec.nUsed[i] and HIT or PENDING)
    if not put(plan, src, rec.nKey[i], rec.nSym[i], rec.nT0[i], cycleIx, i, state, rec.nGrade[i], wt0, wt1, projected, releaseAt, endAt, rec.nChained and rec.nChained[i]) then
      return false
    end
  end
  return true
end

-- The rows this paper uses, in the stage's fixed order. From the FIGHT's
-- symbol set (`rowSyms`, the union over its windows) in a fight -- the
-- window's own set only when no union is published -- and from the layout's
-- own symbols before the pull. A row never leaves mid-fight.
local function rows(plan, src)
  local syms = src.rowSyms or src.paperSyms
  if not syms and src.lay then
    has.s, has.m, has.A, has.w, has.r = false, false, false, false, false
    local ev = src.lay.ev
    for i = 1, #ev do
      local sym = ev[i].sym
      if has[sym] ~= nil then has[sym] = true end
    end
    syms = has
  end
  local n = 1
  plan.rows[1] = "auto"
  if syms then
    if syms.s then n = n + 1; plan.rows[n] = "s" end
    if syms.m then n = n + 1; plan.rows[n] = "m" end
    if syms.A then n = n + 1; plan.rows[n] = "A" end
    if syms.w or syms.r then n = n + 1; plan.rows[n] = "w" end
  end
  -- One row for cooldown presses and proc spans, only when the fight has any
  -- to show (held procs, Quick Shots rolling, a scripted scenario).
  if src.hasCd then n = n + 1; plan.rows[n] = "cd" end
  for i = n + 1, #plan.rows do plan.rows[i] = nil end
  plan.nRows = n
end

function P.Build(src, plan)
  local prevKey, prevN, prevNotation, prevRows, prevReason =
    plan.nextKey, plan.n, plan.notation, plan.nRows, plan.reason
  local prevPulled = plan.pulled
  local now = src.now
  plan.now, plan.t0 = now, src.t0 or 0
  plan.live, plan.pulled, plan.notation = src.live == true, src.pulled == true, src.notation
  -- The pull moves every note from the provisional clock to the real one:
  -- what was asked for on the provisional clock must not pin a real note.
  if plan.pulled and not prevPulled then
    for k in pairs(plan._askT) do plan._askT[k] = nil end
    if plan._wMin then for k in pairs(plan._wMin) do plan._wMin[k] = nil end end
    if plan._wTight then for k in pairs(plan._wTight) do plan._wTight[k] = nil end end
    for k in pairs(plan._lost) do plan._lost[k] = nil end
  end
  plan.n, plan.nAutos = 0, 0
  plan.nextIdx, plan.nextKey, plan.nextSym, plan.nextSpellId, plan.nextNextSpellId = nil, nil, nil, nil, nil
  plan.reason = nil
  local wv = plan.weave
  wv.at, wv.room, wv.fits, wv.openNow = src.weaveAt, src.weaveRoom or 0, src.weaveFits == true, src.oppOpen == true
  if not plan.live then
    plan.nRows = 0
    plan.rows[1] = nil
    local askT, lost = plan._askT, plan._lost
    for k in pairs(askT) do askT[k] = nil end
    for k in pairs(lost) do lost[k] = nil end
    if prevN ~= 0 or prevKey ~= nil or prevRows ~= 0 or prevReason ~= nil then plan.rev = plan.rev + 1 end
    return plan
  end
  -- The plan reaches ONE CYCLE PAST the view's horizon. A projected cycle is
  -- seated on the grid's base release and its notes walked onto the hand's
  -- clock afterwards, so a note whose slot sits at the edge of the view came
  -- and went with every 0.3 s the casts ahead of it moved the grid -- the
  -- strip faded a Steady out and in again five seconds ahead of the hand
  -- (ghost, 2026-08-26). The view clips what it cannot show.
  local wt0, wt1 = now - (src.past or 2), now + (src.future or 4.5) + (src.cycle or 0)
  local lay, T = src.lay, src.T
  rows(plan, src)

  -- Seated cycles: the one on grace, then the open one (time order). The
  -- swing chain starts where the engine says the swing is back.
  swingAt = src.meleeReadyAt or 0
  local full = true
  -- The release that closes each seated cycle: the last one for the cycle on
  -- grace, the next one for the open cycle.
  if src.pend then full = putCycle(plan, src, src.pend, src.pend.ix, wt0, wt1, nil, nil, src.pend.t1 or src.lastShotAt) end
  -- (The open cycle's closing release is never behind the clock: between a
  -- cast's end and the shot it delayed, the engine's nextShotAt is stale --
  -- a Multi judged against that stale close read as unplayable for a tick,
  -- the next Steady took its GCD and the Multi was lost, every period.)
  local curEnd = (src.nextShotAt or 0) > 0 and src.nextShotAt or nil
  if curEnd and curEnd < now then curEnd = now end
  if full and src.cur then full = putCycle(plan, src, src.cur, src.cur.ix, wt0, wt1, nil, nil, curEnd) end

  -- Cycles ahead, on the engine's grid. Post-pull the open cycle sits on the
  -- LAST release, so the first projected one hangs on nextShotAt (k = 1) and is
  -- auto index winAutos inside the window. Pre-pull there is no grid: the paper
  -- is seated on the provisional t0 from its first auto (k = 0), one weapon
  -- cycle per cycle -- what the first release will be graded against.
  if full and lay and lay.autos and lay.autos > 0 then
    local rec = plan._rec
    local cycle = src.cycle or 0
    if cycle <= 0 then cycle = lay.dur / lay.autos end
    local windup = src.windup or 0
    local pulled = plan.pulled and (src.nextShotAt or 0) > 0
    local baseIx = src.cur and src.cur.ix or 0
    -- PRE-PULL, THE FIRST RELEASE IS A CAST AWAY. The pull press starts the
    -- paper's first shot, and the auto only winds up once that cast is done:
    -- the engine's first release lands cast + wind-up after the pull (1.29 s
    -- for a Steady at eWS 1.93). Seated ON the pull, the whole strip glided
    -- 1.3 s to the right at the first press (blinks.mp4).
    local pullOff = windup
    if not pulled and lay.ev then
      local first
      for i = 1, #lay.ev do
        local sym = lay.ev[i].sym
        if sym == "s" or sym == "m" then first = sym; pullOff = noteDur(sym, src) + windup; break
        elseif sym == "A" or sym == "w" or sym == "r" then first = sym; break end
      end
      -- THE OPENER IS A NOTE OF ITS OWN: the pull press, at the hit line, keyed
      -- to cycle 0 -- the grader judges it against no cycle, and cycle 1's own
      -- first shot sits a cast and a wind-up later. Seating cycle 1's note ON
      -- the pull made the same key jump 1.3 s at the first press.
      if first == "s" or first == "m" then
        put(plan, src, (T and T.NoteKey(0, 1) or 0), first, plan.t0, 0, 1, PENDING, nil, wt0, wt1, false, nil, nil)
      end
    end
    -- ...and after the pull, for as long as the opener's cast runs: the same
    -- key at the real press. Dropped at the press, the bar at the hit line
    -- vanished and the played cast popped in a second later, a second behind
    -- the line -- the last blink (2026-08-25). The in-flight claim below
    -- takes it (it is the pending note nearest the running cast), so the
    -- walk never asks for it, and the played item replaces it at cast end.
    if pulled and src.castSym and src.castStart and (src.castEnd or 0) > now
       and src.castStart <= plan.t0 + 0.1 then
      put(plan, src, (T and T.NoteKey(0, 1) or 0), src.castSym, src.castStart, 0, 1, PENDING, nil, wt0, wt1, false, nil, nil)
    end
    local k = pulled and 1 or 0
    local kMax = k + P.MAX_CYCLES
    local seat = src.seat or Nock.PracticeGrader.SeatCycle
    while k < kMax do
      local releaseAt, absAuto
      if pulled then
        releaseAt = src.nextShotAt + (k - 1) * cycle
        absAuto = (src.winAutos or 0) - 1 + k
      else
        releaseAt = plan.t0 + pullOff + k * cycle
        absAuto = k
      end
      if releaseAt - windup > wt1 then break end
      -- The cycle index the grader WILL give this cycle: pre-pull the first
      -- release seats cycle 1, so k = 0 is cycle 1 -- the same keys, so the
      -- pull moves nothing.
      local cycleIx = pulled and (baseIx + k) or (k + 1)
      local na = plan.nAutos + 1
      if na <= P.MAX_AUTOS then
        local a = plan.autos[na]
        a.key = (T and T.KEY.GRID or 0) + cycleIx
        a.windupAt, a.releaseAt, a.cycle = releaseAt - windup, releaseAt, cycleIx
        a.base, a.seated = releaseAt, releaseAt
        -- The delay the PAPER budgets for this auto (the layout's own clip
        -- at this cycle position, G's `releases`): the walk may run a cast
        -- that far into the wind-up as the paper's own play.
        a.dly = (lay.dly and lay.dly[absAuto % lay.autos + 1]) or 0
        plan.nAutos = na
      end
      seat(lay, absAuto, releaseAt, rec, T, cycleIx)
      -- ...its weaves chained on the swing (see `put`): the same rule the
      -- grader applies when it seats the cycle for real, carried forward.
      if not putCycle(plan, src, rec, cycleIx, wt0, wt1, true, releaseAt, releaseAt + cycle) then break end
      k = k + 1
    end
  end

  -- The shots, on the hand's clock (see retimeShots): a note the engine cannot
  -- take at its slot is asked for when it can be.
  -- THE GRID FIRST. The paper's own slots already say where the autos wait
  -- (a Multi ending past the wind-up holds the release behind it): delayed
  -- from the slots, the grid IS the paper's, and the walk then finds every
  -- note fits where the paper put it. Walked against the pure grid first, the
  -- opener's 0.2 s spill read as a Multi that "would not fit", the plan
  -- swapped and held, the ask stuck, and the fight ran a cycle behind the
  -- paper for good. Then the shots, then the grid once more behind whatever
  -- the walk moved, and the shots again on it.
  floorWeaves(plan, src, now)
  retimeShots(plan, src, now)
  retimeWeaves(plan, src, now)

  -- NEXT: the earliest pending, playable note -- and the one after it. Notes are
  -- appended cycle by cycle and time-ordered inside a cycle, but a wide paper
  -- can seat a note past the next release, so the scan is by time, not index.
  local best, bestT, second, secondT
  for i = 1, plan.n do
    local nt = plan.notes[i]
    if nt.state == PENDING and nt.playable and not nt.inflight then
      if not best or nt.t0 < bestT then
        second, secondT, best, bestT = best, bestT, i, nt.t0
      elseif not second or nt.t0 < secondT then
        second, secondT = i, nt.t0
      end
    end
  end
  if best then
    local nt = plan.notes[best]
    plan.nextIdx, plan.nextKey, plan.nextSym = best, nt.key, nt.sym
    -- The HUD's spell only once the fight is on: armed, the strip says what to
    -- pull with and the medallion stays as blank as it is with no target.
    if plan.pulled then
      plan.nextSpellId = spellFor(nt.sym)
      plan.nextNextSpellId = second and spellFor(plan.notes[second].sym) or nil
      -- (a `w` here is re-decided below, once the weave window is known)
    end
  end

  -- ONE weave answer. The window is the cycle room around the paper's next
  -- playable `w` note -- the release that opened its cycle (or the melee swing
  -- coming up, whichever is later) until the next wind-up -- so the band and
  -- the note can never disagree. The engine's own walk (E.WeaveWindow, in
  -- src.weaveAt) is the fallback for a paper with no playable weave in reach.
  -- `moveAt` is when to START WALKING: the note (or the window, if the note
  -- sits before it can open) less this player's measured step-in.
  local stepIn = src.weaveStepIn or P.WEAVE_LEAD
  local wNote
  for i = 1, plan.n do
    local nt = plan.notes[i]
    if nt.sym == "w" and nt.state == PENDING and nt.playable and (not wNote or nt.t0 < wNote.t0) then wNote = nt end
  end
  local cycle, windup = src.cycle or 0, src.windup or 0
  if wNote and plan.pulled and (src.nextShotAt or 0) > 0 and cycle > 0 then
    local t0 = wNote.t0
    -- The grid release at or before the note: nextShotAt is a release, every
    -- release is a whole cycle from it.
    local rel = src.nextShotAt + math.floor((t0 - src.nextShotAt) / cycle + EPS) * cycle
    local ws = rel + cycle - windup
    local open = rel
    if (src.meleeReadyAt or 0) > open then open = src.meleeReadyAt end
    local room = ws - open
    if room > 0 then
      wv.at, wv.room = open, room
      wv.fits = room >= (src.weaveDur or 0)
      -- (The note itself is seated a step-in after the release at the
      -- earliest -- G.FitWeave's floor, shared by the grader's seating and
      -- the projection in `put` -- so the walk starts at the release, never
      -- before it: the dead zone the stage used to draw.)
      local hitAt = (t0 > open) and t0 or open
      wv.noteAt, wv.moveAt = t0, hitAt - stepIn
    else
      wv.noteAt, wv.moveAt = t0, t0 - stepIn
    end
  elseif wv.at then
    wv.noteAt, wv.moveAt = nil, wv.at - stepIn
  else
    wv.noteAt, wv.moveAt = nil, nil
  end
  -- Raptor is THE press from the moment to start walking, not before.
  if best and plan.pulled and plan.notes[best].sym == "w" then
    local moveAt = wv.moveAt or ((wv.at or plan.notes[best].t0) - P.WEAVE_LEAD)
    if now >= moveAt then
      plan.nextSpellId = spellFor("w")
      plan.nextNextSpellId = second and spellFor(plan.notes[second].sym) or nil
    else
      plan.nextSpellId = nil
      plan.nextNextSpellId = spellFor("w")
    end
  end

  -- The coach's one word.
  local syms = src.paperSyms
  if not plan.pulled then plan.reason = "pull"
  elseif wv.at and wv.fits == false and (syms == nil or syms.w or syms.r) then plan.reason = "tight"
  elseif best then plan.reason = "beat" end

  -- What this build asked for, by key, for the next build's in-flight claim.
  local askT = plan._askT
  for i = 1, plan.n do
    local nt = plan.notes[i]
    askT[nt.key] = nt.t0
  end

  if plan.nextKey ~= prevKey or plan.n ~= prevN or plan.notation ~= prevNotation
     or plan.nRows ~= prevRows or plan.reason ~= prevReason then
    plan.rev = plan.rev + 1
  end
  return plan
end

if Nock then Nock.PracticePlan = P end
return P
