-- Tests/practice_plan_test.lua
-- The plan builder (Core/PracticePlan.lua): one answer to "what do I press next", from seated cycles + the grid.
package.path = "./?.lua;" .. package.path
local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

Nock = { modules = {} }
function Nock:NewModule(name) local m = { name = name }; Nock.modules[name] = m; return m end
function Nock:GetModule(name) return Nock.modules[name] end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
_G.GetTime = function() return 1000 end
_G.UnitRangedDamage = function() return 2.174 end
_G.UnitAttackSpeed = function() return 3.7 end
_G.C_Spell = { GetSpellInfo = function() return {} end,
               GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
               GetSpellTexture = function() return "" end }
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end

dofile("Core/Constants.lua")
dofile("Core/State.lua")
dofile("Core/PracticeModel.lua")
dofile("Core/PracticeTimeline.lua")
dofile("Core/PracticePlan.lua")
dofile("Modules/PracticeGrader.lua")

local C = Nock.Constants
local M, T, P, G = Nock.PracticeModel, Nock.PracticeTimeline, Nock.PracticePlan, Nock.PracticeGrader
local h = { ws = 3.0, rangedMul = 1.38, castCorr = 1, mws = 3.7, meleeMul = 1, imprArcanePts = 0 }
local CYCLE = 3.0 / 1.38          -- 2.174
local WINDUP = 0.5 / 1.38

local function newSrc()
  return { past = 2, future = 4.5, cycle = CYCLE, windup = WINDUP, rangedMul = 1.38, castCorr = 1,
           msReadyAt = 0, arcReadyAt = 0, weaveAt = nil, weaveRoom = 0, weaveFits = false,
           oppOpen = false, meleeReadyAt = 0, meleeCycle = 3.7, T = T, nextShotAt = 0, lastShotAt = 0, winAutos = 0 }
end
local function newG(nota)
  return G.New{ model = M, h = h, notation = nota, timeline = T, clipMin = 0.03, reaction = 0.15 }
end
-- Pull at t, first release one cycle later; returns the grader and its open cycle.
local function pulled(nota, t)
  local g = newG(nota)
  G.Feed(g, { kind = "pull", t = t })
  G.Feed(g, { kind = "auto", t = t + CYCLE, delay = 0 })
  return g, g.cur
end
local function seat(src, g, t)
  src.live, src.pulled, src.t0 = true, true, t
  src.lay, src.cur, src.pend, src.winAutos = G.Layout(g), g.cur, g.pend, g.win.autos
  src.lastShotAt, src.nextShotAt = t + CYCLE, t + 2 * CYCLE
end

-- 1. Pre-pull: the drill's paper seated on the provisional t0; NEXT is the first
--    note; the HUD gets no spell.
do
  local g = newG("1:1")
  local src = newSrc()
  src.now, src.live, src.pulled, src.t0 = 1000, true, false, 1000
  src.lay = G.Layout(g, M.STRINGS["1:1"], 1.38)
  src.notation = "1:1"
  local plan = P.New()
  P.Build(src, plan)
  ok(plan.n > 0, "1: pre-pull plan has notes")
  ok(plan.nextIdx == 1 and plan.notes[1].sym == "s", "1: pre-pull NEXT is the first Steady")
  ok(plan.nextSpellId == nil, "1: pre-pull: no spell for the HUD")
  ok(plan.reason == "pull", "1: pre-pull reason is pull")
  ok(plan.notes[1].t0 >= 1000, "1: pre-pull notes sit on or after the provisional t0")
  -- The first release is a Steady cast and a wind-up after the pull, where
  -- the engine puts it (the paper opens with `a s`: the press starts the cast).
  local firstRel = 1000 + M.CastTime(1.5, 1.38, 1) + WINDUP
  ok(plan.nAutos > 0 and math.abs(plan.autos[1].releaseAt - firstRel) < 1e-6,
     "1: the grid's first release is a cast and a wind-up after the pull (" .. tostring(plan.autos[1].releaseAt - 1000) .. ")")
  local rev = plan.rev
  P.Build(src, plan)
  ok(plan.rev == rev, "1: rebuilding an unchanged plan keeps rev")
end

-- 2. Pulled: seated cycle from the grader; NEXT = earliest pending playable note;
--    a note inside grace stays NEXT; a hit note is not.
do
  local g, c = pulled("1:1", 100)
  local src = newSrc()
  seat(src, g, 100)
  src.notation = "1:1"
  local plan = P.New()
  src.now = 100 + CYCLE + 0.1
  P.Build(src, plan)
  ok(plan.nextKey == c.nKey[1], "2: NEXT is the seated cycle's first note")
  ok(plan.nextSpellId == C.SpellID.STEADY_SHOT, "2: NEXT spell is Steady")
  ok(plan.notes[plan.nextIdx].cycle == c.ix, "2: NEXT carries its cycle index")
  ok(plan.reason == "beat", "2: reason is beat")
  src.now = c.nT0[1] + 0.4
  P.Build(src, plan)
  ok(plan.nextKey == c.nKey[1], "2: a pending note inside grace stays NEXT")
  G.Feed(g, { kind = "cast", spell = "steady", t0 = c.nT0[1], t1 = c.nT0[1] + 1.087, t = c.nT0[1] + 1.087 })
  src.now = c.nT0[1] + 1.1
  P.Build(src, plan)
  local i = plan.nextIdx
  ok(i and plan.notes[i].state == P.PENDING and plan.notes[i].cycle == c.ix + 1,
     "2: after the hit, NEXT is the next cycle's note")
  local hitSeen = false
  for j = 1, plan.n do if plan.notes[j].key == c.nKey[1] and plan.notes[j].state == P.HIT and plan.notes[j].grade == "PERFECT" then hitSeen = true end end
  ok(hitSeen, "2: the hit note is in the plan with its grade")
  ok(plan.rev > 0, "2: rev moved with the NEXT change")
end

-- 3. Projected keys equal what the grader seats when that release lands.
do
  local g = pulled("5:5:1:1", 100)
  local src = newSrc()
  seat(src, g, 100)
  -- Nothing has slipped: the clock stands ON the open cycle's first slot. (A
  -- clock past it is a late press, and the hand's clock then honestly moves
  -- everything behind it by the slip -- see section 8.)
  src.now = 100 + CYCLE
  src.notation = "5:5:1:1"; src.future = 10
  local plan = P.New()
  P.Build(src, plan)
  local want, wantN = {}, 0
  for i = 1, plan.n do
    local nt = plan.notes[i]
    if nt.cycle == g.cur.ix + 1 then wantN = wantN + 1; want[wantN] = { key = nt.key, t0 = nt.t0, sym = nt.sym } end
  end
  ok(wantN > 0, "3: a future cycle was projected")
  -- The release lands where the plan predicted it (behind the paper's own
  -- Multi overrun -- the plan delays its grid behind the casts it asks for).
  local predicted = plan.autos[1].releaseAt
  ok(predicted > 100 + 2 * CYCLE - 1e-6, "3: the plan's first projected release is on or behind the pure grid (" .. tostring(predicted - 100 - 2 * CYCLE) .. ")")
  G.Feed(g, { kind = "auto", t = predicted, delay = predicted - (100 + 2 * CYCLE) })
  local c = g.cur
  -- Keys and symbols: the plan's TIMES are its asks (the hand's clock: a
  -- note is asked for when the hand is free, not at its paper slot), so
  -- only the identity is the grader's to confirm.
  local same = (c.n == wantN)
  for i = 1, wantN do
    if not same then break end
    if c.nKey[i] ~= want[i].key or c.nSym[i] ~= want[i].sym then same = false end
  end
  ok(same, ("3: projected keys/symbols equal the grader's seated ones (%d vs %d)"):format(wantN, c.n))
  -- Keys survive a haste change: the same cycle's notes keep their keys when
  -- the window's haste (and so its layout) changes.
  local keysA = {}
  for i = 1, plan.n do keysA[plan.notes[i].key] = true end
  -- A haste WINDOW change: the grader opens a new window, lays the paper out
  -- again at the new haste. Under the old scheme that was a new generation and
  -- every key changed.
  G.Feed(g, { kind = "haste", t = src.now, rangedMul = 1.38 * 1.4, meleeMul = 1, qs = true, rf = false, lust = false, drums = false })
  src.lay, src.cur, src.pend, src.winAutos = G.Layout(g), g.cur, g.pend, g.win.autos
  src.rangedMul = 1.38 * 1.4
  P.Build(src, plan)
  -- The new window re-phases the paper, so a cycle may gain or lose a note
  -- (those keys come and go); every note that IS there is keyed by its cycle
  -- and seat order alone, and most keys survive.
  local kept, total, pure = 0, 0, true
  for i = 1, plan.n do
    local nt = plan.notes[i]
    total = total + 1
    if keysA[nt.key] then kept = kept + 1 end
    if nt.key ~= T.NoteKey(nt.cycle, nt.idx) then pure = false end
  end
  ok(pure, "3: after a haste change every key is NoteKey(cycle, order)")
  ok(total > 0 and kept * 2 >= total, ("3: a haste change keeps most note keys (%d/%d)"):format(kept, total))
  src.rangedMul = 1.38
end

-- 4. A note the sim cannot press when it comes round is not playable and not NEXT.
do
  local g = pulled("5:5:1:1", 100)
  local src = newSrc()
  seat(src, g, 100)
  src.now = 100 + CYCLE + 0.05
  src.notation = "5:5:1:1"; src.future = 10
  src.msReadyAt = 1e9      -- Multi never ready
  local plan = P.New()
  P.Build(src, plan)
  local sawM, anyMPlayable = false, false
  for i = 1, plan.n do
    local nt = plan.notes[i]
    if nt.sym == "m" then sawM = true; if nt.playable then anyMPlayable = true end end
  end
  ok(sawM, "4: the paper's Multi notes are still in the plan")
  ok(not anyMPlayable, "4: a Multi on cooldown past its slot is not playable")
  ok(plan.notes[plan.nextIdx].sym ~= "m", "4: NEXT skips the unplayable Multi")
end

-- 5. Weave: the w note is NEXT; Raptor is the spell only inside WEAVE_LEAD of the window.
do
  -- "drill 1w" is `aw`: the weave is the cycle's only note.
  local g = pulled("drill 1w", 100)
  local src = newSrc()
  seat(src, g, 100)
  src.notation = "drill 1w"; src.future = 10
  src.paperSyms = { w = true }
  local plan = P.New()
  src.now = 100 + CYCLE + 0.05
  P.Build(src, plan)
  local wIdx
  for i = 1, plan.n do if plan.notes[i].sym == "w" and plan.notes[i].state == P.PENDING then wIdx = wIdx or i end end
  ok(wIdx ~= nil, "5: the paper's w note is in the plan")
  local wT0 = plan.notes[wIdx].t0
  ok(plan.notes[wIdx].t1 - wT0 >= P.WEAVE_DRAW_MIN, "5: a weave note has a drawn length")
  -- `aw` at a 2.174 s cycle on a 3.7 s weapon: consecutive weave notes chain
  -- on the swing, never closer than one melee cycle.
  local prevW, chained = nil, true
  for i = 1, plan.n do
    local nt = plan.notes[i]
    if nt.sym == "w" then
      if prevW and nt.t0 - prevW < 3.7 - 1e-9 then chained = false end
      prevW = nt.t0
    end
  end
  ok(chained, "5: projected weave notes sit at least one melee cycle apart")
  -- ...and none of them inside a wind-up: every projected weave starts at
  -- least `legs` before its cycle's next wind-up.
  local clear = true
  for i = 1, plan.n do
    local nt = plan.notes[i]
    if nt.sym == "w" and nt.cycle > g.cur.ix then
      local rel = src.nextShotAt + math.floor((nt.t0 - src.nextShotAt) / CYCLE + 1e-9) * CYCLE
      local ws = rel + CYCLE - WINDUP
      if nt.t0 + (src.weaveDur or 0) > ws + 1e-9 then clear = false end
    end
  end
  ok(clear, "5: no projected weave note starts inside a wind-up")
  -- A LATE hit: the note it took is hit, the engine's swing returns from the
  -- hit. The next projected weave sits on that return, playable -- never on
  -- note + cycle, which would be before the swing and unplayable.
  do
    local g2, c2 = pulled("drill 1w", 300)
    local s2 = newSrc()
    seat(s2, g2, 300)
    s2.notation = "drill 1w"; s2.future = 10
    s2.paperSyms = { w = true }
    local nT = c2.nT0[1]
    G.Feed(g2, { kind = "melee", hit = "w", t = nT + 0.4 })      -- 0.4 s late
    s2.meleeReadyAt = nT + 0.4 + 3.7                                -- the engine's swing return
    s2.now = nT + 0.9
    local p2 = P.New()
    P.Build(s2, p2)
    local nxt = p2.nextIdx and p2.notes[p2.nextIdx]
    ok(nxt and nxt.sym == "w" and nxt.playable and nxt.t0 >= s2.meleeReadyAt - 1e-9,
       ("5: after a late hit NEXT is a playable weave on the real swing return (%.3f vs %.3f)"):format(nxt and nxt.t0 or -1, s2.meleeReadyAt))
    local dim = false
    for i = 1, p2.n do if p2.notes[i].sym == "w" and p2.notes[i].state == P.PENDING and not p2.notes[i].playable then dim = true end end
    ok(not dim, "5: ...and no pending weave note is left unplayable in front of it")
  end
  ok(plan.notes[wIdx].raptor == true, "5: Raptor ready (0) by the hit: the note is a Raptor")
  src.raptorReadyAt = wT0 + 2.0
  P.Build(src, plan)
  ok(plan.notes[wIdx].raptor == false, "5: Raptor on cooldown past the hit: the note is a white swing")
  src.raptorReadyAt = 0
  src.weaveDur = 0.9
  P.Build(src, plan)
  ok(math.abs(plan.notes[wIdx].t1 - wT0 - 0.9) < 1e-9, "5: ...the player's measured weave when longer")
  -- The engine's own walk would put the window elsewhere; the plan anchors on
  -- the paper's note and the engine's answer is only the fallback.
  src.weaveAt, src.weaveRoom, src.weaveFits = wT0 - 1.5, 0.3, false
  src.weaveStepIn = 0.4
  src.now = wT0 - 2.0
  P.Build(src, plan)
  ok(plan.notes[plan.nextIdx].sym == "w", "5: the w note is NEXT")
  ok(plan.weave.noteAt == wT0, ("5: the weave window is anchored on the paper's note (%s vs %s)"):format(tostring(plan.weave.noteAt and plan.weave.noteAt - 100), tostring(wT0 - 100)))
  ok(plan.weave.at <= wT0 and plan.weave.at + plan.weave.room > wT0, "5: ...and the note sits inside it")
  ok(plan.weave.fits == true, "5: a whole cycle of room fits a weave")
  ok(math.abs(plan.weave.moveAt - (wT0 - 0.4)) < 1e-9, "5: moveAt is the note less the measured step-in")
  ok(plan.nextSpellId == nil and plan.nextNextSpellId == C.SpellID.RAPTOR_STRIKE, "5: Raptor is NEXT-NEXT until moveAt")
  src.now = wT0 - 0.3
  P.Build(src, plan)
  ok(plan.nextSpellId == C.SpellID.RAPTOR_STRIKE, "5: Raptor is the spell from moveAt on")
  ok(plan.reason == "beat", "5: an achievable weave is on the beat, whatever the engine's fallback said")
  -- The melee swing not up by the note: a PROJECTED w note moves onto the
  -- swing's return (the seated one is the grader's, retimed at its seat).
  -- (the seated one is the grader's, retimed at its own seat; here the swing
  -- returns after the NEXT cycle's paper slot, so that projected note moves)
  local readyAt = wT0 + CYCLE + 0.5
  src.meleeReadyAt = readyAt
  P.Build(src, plan)
  local moved = false
  for i = 1, plan.n do
    local nt = plan.notes[i]
    if nt.sym == "w" and nt.cycle == g.cur.ix + 1 and math.abs(nt.t0 - readyAt) < 1e-9 and nt.playable then moved = true end
  end
  ok(moved, "5: a projected w note before the swing's return is retimed onto it")
  local nxt = plan.nextIdx and plan.notes[plan.nextIdx]
  ok(nxt and nxt.sym == "w" and math.abs(nxt.t0 - readyAt) < 1e-9, "5: ...and NEXT is that retimed note")
  ok(plan.weave.noteAt == nxt.t0 and plan.weave.at <= nxt.t0, "5: ...with the window anchored on it")
  src.meleeReadyAt = 0
end

-- 6. Rows follow the paper's symbols, in fixed order.
do
  local src = newSrc()
  local plan = P.New()
  src.now, src.live, src.pulled, src.t0 = 1000, true, false, 1000
  local g = newG("1:1")
  src.lay = G.Layout(g, M.STRINGS["1:1"], 1.38); src.notation = "1:1"
  P.Build(src, plan)
  ok(plan.nRows == 2 and plan.rows[1] == "auto" and plan.rows[2] == "s", "6: pre-pull 1:1 rows = auto, s (from the layout)")
  src.paperSyms = { s = true }
  P.Build(src, plan)
  ok(plan.nRows == 2 and plan.rows[1] == "auto" and plan.rows[2] == "s", "6: 1:1 rows = auto, s")
  src.paperSyms = { s = true, m = true, A = true, w = true }
  P.Build(src, plan)
  ok(plan.nRows == 5 and plan.rows[5] == "w" and plan.rows[6] == nil, "6: full paper rows = auto, s, m, A, w")
  src.hasCd = true
  P.Build(src, plan)
  ok(plan.nRows == 6 and plan.rows[6] == "cd", "6: a fight with cooldowns adds the cd row last")
  src.hasCd = false
  -- THE ROWS ARE THE FIGHT'S, not the window's (user, 2026-08-27: on the
  -- opener drill the m/A rows left during the 2:2 window and blinked back --
  -- "blinking lanes is BAD for UX"). `rowSyms` is the union over the fight's
  -- windows; the window's own `paperSyms` still scopes the advice.
  src.paperSyms = { s = true }
  src.rowSyms = { s = true, m = true, A = true, w = true }
  P.Build(src, plan)
  ok(plan.nRows == 5 and plan.rows[3] == "m" and plan.rows[4] == "A" and plan.rows[5] == "w",
     "6: rowSyms (the fight's union) keeps m/A/w on a window whose paper has none")
  src.rowSyms = nil
end

-- 8. The hand's clock: a note the engine cannot take at its slot is asked for
--    when it can be; a cast that would run into the wind-up waits for the
--    release, and the paper's instant that fits is pulled forward into the room.
do
  local STEADY = M.CastTime(1.5, 1.38, 1)          -- 1.087
  -- (a) The GCD still running past the slot moves the note to the GCD's end.
  local g, c = pulled("1:1", 100)
  local src = newSrc()
  seat(src, g, 100)
  src.notation = "1:1"
  local slot = c.nT0[1]
  src.now = slot
  src.gcdEnd, src.castEnd, src.gcd = slot + 0.3, 0, 1.5
  local plan = P.New()
  P.Build(src, plan)
  local nt = plan.notes[plan.nextIdx]
  ok(nt.key == c.nKey[1], "8a: NEXT is still the seated Steady")
  ok(math.abs(nt.t0 - (slot + 0.3)) < 1e-6 and math.abs(nt.t1 - nt.t0 - STEADY) < 1e-6,
     "8a: ...moved to the GCD's end, its length kept (" .. tostring(nt.t0 - slot) .. ")")
  -- The projected cycle behind it is chained off that press, not the ideal slot.
  local later
  for i = 1, plan.n do local x = plan.notes[i]; if x.sym == "s" and x.cycle == c.ix + 1 then later = x end end
  ok(later and later.t0 >= slot + 0.3 + 1.5 - 1e-6, "8a: the next cycle's Steady sits past that press's GCD")
  -- (b) THE PAPER IS THE LAW (Plan B round 2). A Steady that cannot finish
  --     before the wind-up is pressed the moment the hand is free all the
  --     same: the paper wrote its overruns, the auto waits behind the cast
  --     (delayGrid) and the clip is the plan's, not the player's. Never
  --     idled, never held to the release.
  local wu = src.nextShotAt - WINDUP
  src.gcdEnd = wu - 0.15
  src.now = wu - 0.15
  plan = P.New()
  P.Build(src, plan)
  nt = plan.notes[plan.nextIdx]
  ok(nt.key == c.nKey[1] and math.abs(nt.t0 - (wu - 0.15)) < 1e-6 and not nt.cast0,
     "8b: a Steady that overruns the wind-up is pressed now, the auto waits (" .. tostring(nt.t0 - (wu - 0.15)) .. "/" .. tostring(nt.cast0) .. ")")
  local a1 = plan.autos[1]
  ok(a1 and math.abs(a1.releaseAt - (wu - 0.15 + (nt.t1 - nt.t0) + WINDUP)) < 1e-6,
     "8b: ...and the projected release moves to cast end + wind-up (" .. tostring(a1 and a1.releaseAt - src.nextShotAt) .. ")")
  src.gcdEnd = wu - 0.5
  src.now = wu - 0.5
  plan = P.New()
  P.Build(src, plan)
  nt = plan.notes[plan.nextIdx]
  ok(nt.key == c.nKey[1] and math.abs(nt.t0 - (wu - 0.5)) < 1e-6,
     "8b: ...with 0.5 s of room, the same (" .. tostring(nt.t0 - (wu - 0.5)) .. ")")
  -- (c) The paper's ORDER is kept: with a Multi ready and on the paper after
  --     the Steady, the Steady is NEXT now and the Multi follows its GCD --
  --     no instant is pulled in front of a cast that overruns.
  g, c = pulled("5:5:1:1", 200)
  src = newSrc()
  seat(src, g, 200)
  src.notation = "5:5:1:1"; src.future = 10
  wu = src.nextShotAt - WINDUP
  src.now = wu - 0.5
  src.gcdEnd, src.castEnd, src.gcd = wu - 0.5, 0, 1.5
  src.msReadyAt, src.arcReadyAt = 0, 0
  plan = P.New()
  P.Build(src, plan)
  nt = plan.notes[plan.nextIdx]
  ok(nt.key == c.nKey[1] and nt.sym == "s" and math.abs(nt.t0 - (wu - 0.5)) < 1e-6, "8c: the paper's Steady is NEXT, now (" .. tostring(nt.sym) .. ")")
  ok(plan.nextSpellId == C.SpellID.STEADY_SHOT, "8c: ...and the HUD's spell is Steady")
  local mn
  for i = 1, plan.n do local x = plan.notes[i]; if x.sym == "m" and x.state == P.PENDING and x.playable then mn = mn or x end end
  ok(mn and math.abs(mn.t0 - (wu - 0.5 + 1.5)) < 1e-6, "8c: the Multi follows the Steady's GCD (" .. tostring(mn and mn.t0 - (wu - 0.5 + 1.5)) .. ")")
  -- (f) An instant whose cooldown is not back when its turn comes is
  --     DEFERRED, not waited for: the Steadies after it chain on, and it is
  --     placed the moment it is ready, ahead of the next note.
  src.now = wu - 0.5
  src.gcdEnd = wu - 0.5
  src.msReadyAt = wu - 0.5 + 2.8                   -- back 0.2 s before the third GCD frees
  plan = P.New()                                   -- a fresh plan: no ask carried over from (c)
  P.Build(src, plan)
  local ss, mn2 = {}, nil
  for i = 1, plan.n do
    local x = plan.notes[i]
    if x.state == P.PENDING and x.playable then
      if x.sym == "s" then ss[#ss + 1] = x.t0 elseif x.sym == "m" then mn2 = mn2 or x end
    end
  end
  table.sort(ss)
  ok(#ss >= 2 and math.abs(ss[1] - (wu - 0.5)) < 1e-6 and math.abs(ss[2] - (wu - 0.5 + 1.5)) < 1e-6,
     "8f: the Steadies chain past a Multi still on cooldown (" .. tostring(ss[1] and ss[1] - (wu - 0.5)) .. "/" .. tostring(ss[2] and ss[2] - (wu - 0.5 + 1.5)) .. ")")
  ok(mn2 and math.abs(mn2.t0 - (wu - 0.5 + 3.0)) < 1e-6, "8f: ...and the Multi is placed the moment the hand is free after it is ready (" .. tostring(mn2 and mn2.t0 - (wu - 0.5 + 3.0)) .. ")")
  ok(#ss >= 3 and math.abs(ss[3] - (wu - 0.5 + 4.5)) < 1e-6, "8f: ...ahead of the next Steady (" .. tostring(ss[3] and ss[3] - (wu - 0.5 + 4.5)) .. ")")
  -- (d) Inside the wind-up a cast is asked for NOW -- the client queues it
  --     and the cast starts at the release (the queue window is free).
  src.now = wu + 0.1
  src.gcdEnd = 0
  src.msReadyAt = 1e9                              -- no Multi in reach
  plan = P.New()                                   -- a fresh plan: no ask carried over
  P.Build(src, plan)
  nt = plan.notes[plan.nextIdx]
  ok(nt.sym == "s" and math.abs(nt.t0 - src.now) < 1e-6 and nt.cast0 and math.abs(nt.cast0 - src.nextShotAt) < 1e-6,
     "8d: a press inside the wind-up is asked now and casts at the release (" .. tostring(nt.t0 - src.now) .. "/" .. tostring(nt.cast0 and nt.cast0 - src.nextShotAt) .. ")")
  -- (e) Pre-pull nothing moves: there is no grid to hold anything to.
  local g0 = newG("1:1")
  local s0 = newSrc()
  s0.now, s0.live, s0.pulled, s0.t0 = 1000, true, false, 1000
  s0.lay = G.Layout(g0, M.STRINGS["1:1"], 1.38)
  s0.notation = "1:1"
  s0.gcdEnd = 1e9
  local p0 = P.New()
  P.Build(s0, p0)
  ok(p0.notes[1].t0 < 1e8, "8e: pre-pull the paper stands as written")
end

-- 7. Not live: the plan is empty and says so.
do
  local src = newSrc(); src.now, src.live = 1000, false
  local plan = P.New(); P.Build(src, plan)
  ok(plan.n == 0 and plan.nextIdx == nil and plan.nextSpellId == nil and plan.live == false and plan.nRows == 0,
     "7: no fight: empty plan")
end

-- 9. A weave never walks inside a cast: with the Steady of `aswAasw` running
--    (or planned) in front of the weave, the walk starts at the cast's end and
--    the note follows the hit.
do
  local g = pulled("drill 1w+s", 100)
  local src = newSrc()
  seat(src, g, 100)
  src.notation = "drill 1w+s"; src.future = 10
  src.weaveStepIn = 0.4
  src.now = 100 + CYCLE + 0.05
  -- A Steady running now, right off the release, for 1.09 s.
  src.castSym, src.castStart, src.castEnd = "s", 100 + CYCLE + 0.02, 100 + CYCLE + 1.11
  local plan = P.New()
  P.Build(src, plan)
  -- Behind a 1.09 s Steady there is no room for a 0.4 s step in and out
  -- before the wind-up: the weave is TIGHT -- unplayable, left where the
  -- paper put it (never pushed to another cycle, which on a paper with a
  -- Steady in every cycle wanders for ever), and not the plan's weave.
  -- (The grader's own seat may already have carried it past the release
  -- -- G.FitWeave with the measured legs -- or the plan marks it tight; in
  -- neither case is a PLAYABLE weave asked for inside the cast.)
  local insideCast, wandered = false, false
  for i = 1, plan.n do
    local w = plan.notes[i]
    if w.sym == "w" and w.state == P.PENDING then
      if w.playable and not w.tight and w.t0 - 0.4 < src.castEnd - 1e-9 then insideCast = true end
      if w.cycle == g.cur.ix and w.t0 > 100 + 3 * CYCLE then wandered = true end
    end
  end
  ok(not insideCast, "9: no playable weave is asked for inside the running cast")
  ok(not wandered, "9: ...and a weave that cannot fit does not wander cycles ahead")
  -- No PLAYABLE pending weave note anywhere in the plan walks inside a cast.
  local clean = true
  for i = 1, plan.n do
    local w = plan.notes[i]
    if w.sym == "w" and w.state == P.PENDING and w.playable and not w.tight then
      for j = 1, plan.n do
        local o = plan.notes[j]
        if (o.sym == "s" or o.sym == "m") and not o.lost then
          local c0 = o.cast0 or o.t0
          local c1 = c0 + (o.t1 - o.t0)
          if c0 < w.t0 - 1e-9 and c1 > w.t0 - 0.4 + 1e-9 then
            clean = false
            if os.getenv("NOCK_DBG") then print(("9: weave k=%s t0=%.2f inside %s c%d [%.2f..%.2f] cast0=%s inflight=%s chained=%s"):format(tostring(w.key), w.t0 - 100, o.sym, o.cycle, c0 - 100, c1 - 100, tostring(o.cast0 and o.cast0 - 100), tostring(o.inflight), tostring(o.chained))) end
          end
        end
      end
    end
  end
  ok(clean, "9: no playable projected weave walks inside a planned cast")
  -- With room behind the cast (a shorter one) the weave is placed behind it.
  src.castEnd = 100 + CYCLE + 0.5
  P.Build(src, plan)
  local wv = plan.weave
  ok(wv.moveAt ~= nil and wv.moveAt >= src.castEnd - 1e-9, ("9: with room, the walk starts after the running cast (%.3f vs cast end %.3f)"):format(wv.moveAt or -1, src.castEnd))
  ok(wv.noteAt ~= nil and math.abs(wv.noteAt - (wv.moveAt + 0.4)) < 1e-9, "9: ...and the note is the hit, a step-in later")
end

print(("practice_plan: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
