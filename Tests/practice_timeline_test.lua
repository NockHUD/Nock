-- Tests/practice_timeline_test.lua
-- Standalone LuaJIT tests for Core/PracticeTimeline.lua: engine events + scorecard
-- windows -> timeline lanes, verdict marks, ghosts and live lookahead.
-- Run from the repo root: luajit Tests/practice_timeline_test.lua

local M = dofile("Core/PracticeModel.lua")
local T = dofile("Core/PracticeTimeline.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-3) end

-- A shot-grid auto, by its KEY rather than by a display string. It used to carry
-- the label "grid" and these tests read that back; the label is gone (R7b -- a
-- 0.35 s wind-up bar has room for three dots and nothing else, so every auto of
-- the grid drew "..."), and the key block is what identifies it anyway.
local function isGrid(it)
  local k = it.key
  return k ~= nil and k >= T.KEY.GRID and k < T.KEY.MOVE
end

-- Shared fixture: pull 0, auto 0.36, cast steady 0->1.09, proc RF on 2 / off 17,
-- cd RF used 2, melee r 5, kc 5.2, stop 20.
local events = {
  { kind = "pull", t = 0 },
  { kind = "auto", t = 0.36, delay = 0 },
  { kind = "cast", spell = "steady", t0 = 0, t1 = 1.09 },
  { kind = "proc", t = 2, name = "RF", on = true },
  { kind = "cd", t = 2, key = "RF", used = true },
  { kind = "melee", t = 5, hit = "r" },
  { kind = "kc", t = 5.2, used = true },
  { kind = "proc", t = 17, name = "RF", on = false },
  { kind = "stop", t = 20 },
}
local n = #events

local score = {
  windows = {
    { t0 = 0, t1 = 2, rangedMul = 1.38, notation = "drill 1:1" },   -- Steady-only (the practice 1:1 writes a Multi)
    { t0 = 2, t1 = 20, rangedMul = 1.932, notation = "5:5:1:1" },
  },
  verdicts = {
    { t = 0.36, code = "CLIP", text = "CLIP +100 ms", key = "auto" },
    { t = 3, code = "STEADY_WONT_FIT", text = "x", key = "steady", did = "d", expected = "e", cost = "c",
      ghost = { lane = "cast", sym = "m", t0 = 3, t1 = 3.26 } },
    { t = 5, code = "GOOD", text = "ok", key = "auto" },
  },
}

local h = { ws = 3.0, rangedMul = 1.38, mws = 3.7, meleeMul = 1 }

-- 1. Post-fight build (default opts: okMarks not set)
local opts = { model = M, windup = 0.36 }
local tl = T.Build(events, n, score, h, opts)

ok(tl.t0 == 0, "tl.t0 == 0")
ok(tl.t1 == 20, "tl.t1 == 20")

ok(#tl.lanes.auto == 1, "auto lane has 1 item")
ok(tl.lanes.auto[1].color == "a", "auto lane item color a (no clip delay)")

ok(#tl.lanes.cast == 1, "cast lane has 1 item")
ok(tl.lanes.cast[1].sym == "s", "cast lane item sym s")

ok(#tl.lanes.procs == 2, "procs lane has 2 items (RF span + RF cd tick)")
local rfSpan, rfTick = nil, nil
for _, it in ipairs(tl.lanes.procs) do
  if it.sym == "RF" and near(it.t0, 2) and near(it.t1, 17) then rfSpan = it end
  if it.sym == "RF" and near(it.t0, 1.9) and near(it.t1, 2.1) then rfTick = it end
end
ok(rfSpan ~= nil, "procs lane has RF span 2..17")
ok(rfTick ~= nil, "procs lane has RF cd tick ~2")

ok(#tl.lanes.melee == 2, "melee lane has 2 items (r + KC)")
local haveR, haveKC = false, false
for _, it in ipairs(tl.lanes.melee) do
  if it.sym == "r" then haveR = true end
  if it.sym == "KC" then haveKC = true end
end
ok(haveR, "melee lane has r item")
ok(haveKC, "melee lane has KC item")

ok(#tl.lanes.paper > 0, "paper lane non-empty")
ok(tl.lanes.paper[1].sym == "a" and near(tl.lanes.paper[1].t0, 0), "paper lane first item a at t0=0")
local haveFastA = false
for _, it in ipairs(tl.lanes.paper) do
  if it.sym == "a" and it.t0 >= 2 - 1e-6 and near(it.t1 - it.t0, 0.5 / 1.932, 1e-3) then haveFastA = true end
end
ok(haveFastA, "paper lane second window uses the faster cycle (a item dur ~= 0.5/1.932)")

ok(#tl.marks == 2, "2 marks by default (GOOD verdict dropped)")
ok(tl.marks[1].lane == "auto" and tl.marks[1].code == "CLIP" and tl.marks[1].severity == "bad",
   "first mark: lane auto, severity bad")
ok(tl.marks[2].lane == "cast" and tl.marks[2].code == "STEADY_WONT_FIT" and tl.marks[2].severity == "bad",
   "second mark: lane cast, severity bad")
ok(tl.marks[2].did == "d" and tl.marks[2].expected == "e" and tl.marks[2].cost == "c",
   "second mark: did/expected/cost copied through")

ok(#tl.ghosts == 1, "1 ghost")
ok(tl.ghosts[1].lane == "cast" and tl.ghosts[1].sym == "m", "ghost on lane cast, sym m")

-- 2. okMarks: GOOD verdict now included
local opts2 = { model = M, windup = 0.36, okMarks = true }
local tl2 = T.Build(events, n, score, h, opts2)
ok(#tl2.marks == 3, "okMarks=true includes the GOOD verdict")

-- 3. No opts.live -> tl.ahead stays empty
local tlNoLive = T.Build(events, n, score, h, { model = M, windup = 0.36 })
ok(#tlNoLive.ahead == 0, "no opts.live -> tl.ahead empty")

-- 4. Live lookahead build
local opts3 = {
  live = {
    now = 10, nextShotAt = 10.5, cycle = 1.55, windup = 0.26,
    nextCast = { sym = "s", t0 = 10.6, t1 = 11.4 },
    meleeReadyAt = 12, oppOpen = true, ttw = 1.2,
    procs = { RF = 17 }, cdReady = { KC = 11, Raptor = 13 },
  },
  look = 6,
}
local tl3 = T.Build(events, n, score, h, opts3)

local autoAhead, castAhead, meleeAhead, procsAhead = {}, {}, {}, {}
for _, it in ipairs(tl3.ahead) do
  if it.lane == "auto" then autoAhead[#autoAhead + 1] = it
  elseif it.lane == "cast" then castAhead[#castAhead + 1] = it
  elseif it.lane == "melee" then meleeAhead[#meleeAhead + 1] = it
  elseif it.lane == "procs" then procsAhead[#procsAhead + 1] = it end
end

-- NOTE: with cycle=1.55, now=10, look=6 (horizon=16), the grid actually walks
-- 10.5, 12.05, 13.6, 15.15 (15.15 <= 16) -- 4 items, not the 3 the brief's
-- prose lists. Asserting the code's real, correct-per-Step-1 output.
ok(#autoAhead == 4, "4 auto ahead items on the shot grid")
local wantAutoT1 = { 10.5, 12.05, 13.6, 15.15 }
for i, t in ipairs(wantAutoT1) do
  ok(autoAhead[i] and near(autoAhead[i].t1, t), "auto ahead #" .. i .. " at " .. t)
end

ok(#castAhead == 1, "1 cast ahead item")
ok(castAhead[1] and castAhead[1].label == "NEXT" and castAhead[1].sym == "s"
   and near(castAhead[1].t0, 10.6) and near(castAhead[1].t1, 11.4), "cast NEXT ahead item")

ok(#meleeAhead == 3, "3 melee ahead items")
local haveSwingReady, haveBand, haveRaptorReady = false, false, false
for _, it in ipairs(meleeAhead) do
  if it.label == "swing ready" and near(it.t0, 11.92) and near(it.t1, 12.08) then haveSwingReady = true end
  if it.band and near(it.t0, 10) and near(it.t1, 11.2) and it.thin == true then haveBand = true end
  if it.label == "Raptor ready" and near(it.t0, 12.92) and near(it.t1, 13.08) then haveRaptorReady = true end
end
ok(haveSwingReady, "melee ahead: swing ready at 12")
ok(haveBand, "melee ahead: weave-window band 10..11.2, thin (half lane, no outline)")
ok(haveRaptorReady, "melee ahead: Raptor ready at 13")

ok(#procsAhead == 2, "2 procs ahead items")
local haveRFspan, haveKCready = false, false
for _, it in ipairs(procsAhead) do
  if it.sym == "RF" and near(it.t0, 10) and near(it.t1, 16) then haveRFspan = true end
  if it.label == "KC ready" and near(it.t0, 10.92) and near(it.t1, 11.08) then haveKCready = true end
end
ok(haveRFspan, "procs ahead: RF span 10..16 clipped to horizon")
ok(haveKCready, "procs ahead: KC ready at 11")

-- 5. T.Strip: pure conveyor builder around a live cursor.
-- 20 s event stream; note the WEAVE_OK verdict is placed at t=9 (inside the
-- marks window [now-past, now] = [8,10]) rather than the brief's t=5 example,
-- since t=5 falls outside that window regardless of okMarks and could never
-- demonstrate the "excluded / then included" behavior the brief describes.
local stripEvents = {
  { kind = "pull", t = 0 },
  { kind = "auto", t = 0.36, delay = 0 },
  { kind = "cast", spell = "steady", t0 = 0, t1 = 1.09 },
  { kind = "proc", t = 2, name = "RF", on = true },
  { kind = "cd", t = 2, key = "RF", used = true },
  { kind = "melee", t = 5, hit = "r" },
  { kind = "kc", t = 5.2 },
  { kind = "auto", t = 9.5, delay = 0.1, clip = "fault" },   -- the grader's verdict rides the event
  { kind = "cast", spell = "multi", t0 = 9.6, t1 = 9.96 },
  { kind = "proc", t = 17, name = "RF", on = false },
  { kind = "stop", t = 20 },
}
local nStrip = #stripEvents

-- The grid is the plan's (v3 P2): three autos ahead, keyed by cycle.
local stripPlan = dofile("Core/PracticePlan.lua").New()
stripPlan.live, stripPlan.pulled, stripPlan.now, stripPlan.t0 = true, true, 10, 0
do
  local shots = { 10.5, 12.05, 13.6 }
  for i = 1, 3 do
    local a = stripPlan.autos[i]
    a.key, a.windupAt, a.releaseAt, a.cycle = T.KEY.GRID + i, shots[i] - 0.26, shots[i], i
  end
  stripPlan.nAutos = 3
end
local stripLive = {
  now = 10, nextShotAt = 10.5, cycle = 1.55, windup = 0.26, plan = stripPlan,
  meleeReadyAt = 12, oppOpen = true, ttw = 1.2,
  procs = { RF = 17 }, cdReady = { KC = 11, Raptor = 13 },
}
local stripOpts = {
  past = 2, future = 4.5, windup = 0.36,
  verdicts = {
    { t = 9.5, code = "CLIP", text = "CLIP +100 ms", key = "auto", did = "d", expected = "e", cost = "c" },
    { t = 9, code = "WEAVE_OK", text = "ok", key = "weave" },
  },
}

local out = { items = {}, nItems = 0, marks = {}, nMarks = 0 }
out = T.Strip(stripEvents, nStrip, stripLive, stripOpts, out)

ok(near(out.t0, 8), "strip window t0 == 8")
ok(near(out.t1, 14.5), "strip window t1 == 14.5")

local function findItem(lane, pred)
  for i = 1, out.nItems do
    local it = out.items[i]
    if it.lane == lane and pred(it) then return it end
  end
  return nil
end

ok(findItem("shots", function(it) return near(it.t0, 0) and near(it.t1, 0.36) end) == nil,
   "0.36 auto not in items (outside window)")
ok(findItem("weave", function(it) return near(it.t0, 4.8) and near(it.t1, 5.0) end) == nil,
   "5.0 melee not in items (outside window)")

-- A proc the live snapshot still reports is ONE span across the cursor, not a
-- past bar ending at `now` plus a remainder starting there.
local rfItems = 0
for i = 1, out.nItems do
  local it = out.items[i]
  if it.lane == "procs" and it.sym == "RF" and it.t1 > it.t0 + 0.5 then rfItems = rfItems + 1 end
end
ok(rfItems == 1, "the running RF proc is exactly one span (got " .. rfItems .. ")")

-- A delayed auto's item runs from the moment it was DUE (release - wind-up -
-- delay) to the release: the wait is on the strip, tagged with the delay.
local clippedAuto = findItem("shots", function(it) return near(it.t0, 9.04) and near(it.t1, 9.5) end)
ok(clippedAuto ~= nil and clippedAuto.color == "bad" and clippedAuto.label == "+100",
   "9.5 auto: spans its wait, color bad, label +100")

local multiCast = findItem("shots", function(it) return near(it.t0, 9.6) and near(it.t1, 9.96) end)
ok(multiCast ~= nil and multiCast.sym == "m", "multi cast present on shots, sym m")

local gridAutos = {}
for i = 1, out.nItems do
  local it = out.items[i]
  if it.lane == "shots" and isGrid(it) then gridAutos[#gridAutos + 1] = it end
end
ok(#gridAutos == 3, "3 future grid autos")
local wantGrid = { 10.5, 12.05, 13.6 }
for i, t in ipairs(wantGrid) do
  local found = false
  for _, it in ipairs(gridAutos) do
    if near(it.t1, t) and it.future == true then found = true end
  end
  ok(found, "grid auto at " .. t .. " present and future")
end

local nextCastItem = findItem("shots", function(it) return it.label == "NEXT" end)
ok(nextCastItem == nil, "no engine NEXT bar: the plan owns NEXT (v3 P1)")

local swingReady = findItem("weave", function(it) return it.label == "swing ready" end)
ok(swingReady == nil, "with a plan the swing-ready tick is not drawn (the band says it)")

-- The band is the room you have RIGHT NOW: `now` to the wind-up, drawn thin
-- (half the lane, along its bottom, no outline) so it reads as a window rather
-- than as a box over the whole WEAVE lane.
local band = findItem("weave", function(it) return it.band == true end)
ok(band ~= nil and near(band.t0, 10) and near(band.t1, 11.2), "one band item 10..11.2 (t0 == now)")
ok(band ~= nil and band.thin == true, "...and it is thin")

-- THE BAND FOLLOWS WHAT IS ACHIEVABLE (R5c). Where the snapshot carries the
-- engine's own answer to "when next, and how much room" the band IS that
-- window, opening in the future if that is when the swing is up. The
-- now-anchored pair above is only the fallback for a snapshot without one.
do
  local wl = {}
  for k, v in pairs(stripLive) do wl[k] = v end
  wl.weaveAt, wl.weaveTtw = 10.9, 0.6
  local wo = T.Strip(stripEvents, nStrip, wl, stripOpts, nil)
  local wb = nil
  for i = 1, wo.nItems do
    local it = wo.items[i]
    if it.band and it.lane == "weave" then wb = it end
  end
  ok(wb ~= nil and near(wb.t0, 10.9) and near(wb.t1, 11.5),
     "the band is the engine's next achievable window, not `now` ("
     .. tostring(wb and wb.t0) .. ".." .. tostring(wb and wb.t1) .. ")")
  ok(wb ~= nil and wb.future == true, "...and a window that has not opened yet is future")
  ok(wb ~= nil and wb.key == T.KEY.BAND, "...and it keeps the band's own key")

  -- ...even with the opportunity flag shut, which is the case that went silent:
  -- one slow weave puts `legsNeeded` past every gap and the flag stops going
  -- true, while the paper keeps writing weaves.
  wl.oppOpen, wl.ttw = false, 0
  local so = T.Strip(stripEvents, nStrip, wl, stripOpts, nil)
  local sb = nil
  for i = 1, so.nItems do
    local it = so.items[i]
    if it.band and it.lane == "weave" then sb = it end
  end
  ok(sb ~= nil and near(sb.t0, 10.9), "with the opportunity flag shut the band still shows the room")
  ok(sb ~= nil and not sb.tight, "...and it is not flagged tight while a weave still fits")

  -- A window the engine could only answer with the ROOMIEST gap there is, since
  -- none holds a whole weave: the band says so, and the view draws it as a
  -- hairline rather than as an invitation.
  wl.weaveFits = false
  local to = T.Strip(stripEvents, nStrip, wl, stripOpts, nil)
  local tb = nil
  for i = 1, to.nItems do
    local it = to.items[i]
    if it.band and it.lane == "weave" then tb = it end
  end
  ok(tb ~= nil and tb.tight == true, "a window too small for a whole weave is flagged tight")
  ok(tb ~= nil and tb.thin == true, "...and is still a thin window, not an event")
end

-- ...and the running proc is drawn from max(its start, wt0 - 1) -- here the
-- window edge, since RF came up at t=2, long before it -- and carries no text.
local rfFuture = nil
for i = 1, out.nItems do
  local it = out.items[i]
  if it.lane == "procs" and it.sym == "RF" and near(it.t0, 7) and near(it.t1, 14.5) then rfFuture = it end
end
ok(rfFuture ~= nil and rfFuture.label == nil,
   "one RF future span 7..14.5 (t0 == wt0 - 1) with no text label")
ok(rfFuture ~= nil and rfFuture.row == "cd", "a proc span lives on the cd row")
ok(rfFuture ~= nil and rfFuture.t0 < 10 and rfFuture.t1 > 10 and not rfFuture.future,
   "...and it is a solid span straddling `now`")

local kcReady = findItem("procs", function(it) return it.label == "KC ready" end)
ok(kcReady ~= nil and near(kcReady.t0, 11) and near(kcReady.t1, 11 + T.MIN_CAST_DRAW) and kcReady.sym == "KC",
   "KC ready marker on procs from 11, icon-wide, carrying its icon")

local raptorReady = findItem("weave", function(it) return it.label == "Raptor ready" end)
ok(raptorReady == nil, "with a plan the Raptor-ready tick is not drawn either")

ok(out.nItems == 8, "8 items total (2 past + 6 future; the running RF proc is a single span; no engine bar, no ready ticks)")

-- Played items are keyed by their event (v3 P2), and keep the key across rebuilds.
local playedKeys, playedN = {}, 0
for i = 1, out.nItems do
  local it = out.items[i]
  if not it.future and it.key and it.key >= T.KEY.PLAYED then playedN = playedN + 1; playedKeys[it.key] = true end
end
ok(playedN == 2, "played items are keyed by event index (" .. playedN .. ")")
do
  local again = T.Strip(stripEvents, nStrip, stripLive, stripOpts, out)
  local same = true
  for i = 1, again.nItems do
    local it = again.items[i]
    if not it.future and it.key and it.key >= T.KEY.PLAYED and not playedKeys[it.key] then same = false end
  end
  ok(same, "a rebuild keeps every played item's key")
end

ok(out.nMarks == 1, "1 mark by default (WEAVE_OK excluded)")
ok(out.marks[1].code == "CLIP" and out.marks[1].lane == "shots" and out.marks[1].severity == "bad"
   and out.marks[1].did == "d", "CLIP mark: lane shots, severity bad, did d")

local outOk = { items = {}, nItems = 0, marks = {}, nMarks = 0 }
outOk = T.Strip(stripEvents, nStrip, stripLive, { past = 2, future = 4.5, windup = 0.36,
  verdicts = stripOpts.verdicts, okMarks = true }, outOk)
ok(outOk.nMarks == 2, "okMarks=true includes the WEAVE_OK mark")

-- Repeat call: same table reused, no new items/marks tables allocated.
local item1Ref, itemLastRef = out.items[1], out.items[out.nItems]
local marksLen1 = #out.items
out = T.Strip(stripEvents, nStrip, stripLive, stripOpts, out)
ok(out.items[1] == item1Ref, "repeat call reuses out.items[1] identity")
ok(out.items[out.nItems] == itemLastRef, "repeat call reuses last item identity")
ok(#out.items == marksLen1, "repeat call does not grow out.items")
ok(out.nItems == 8, "repeat call yields the same item count")

-- No allocation after warm-up: out._procStart is the same table across
-- calls (not a fresh local {} per call), and 100 steady-state calls grow
-- LuaJIT's heap by less than 2 KB (collectgarbage("count") is in KB).
local procStartRef = out._procStart
out = T.Strip(stripEvents, nStrip, stripLive, stripOpts, out)
ok(out._procStart == procStartRef, "repeat call reuses out._procStart identity")

-- collectgarbage() sweeps on both sides so transient per-call garbage (the
-- "+100"/"7.0 s left" label strings, same as any dynamic-label code would
-- produce) is excluded; only retained (structural) growth counts. jit.off()
-- for the measurement itself: LuaJIT's trace compiler allocates its own
-- one-time-ish metadata (traces/snapshots) as this loop goes hot, which
-- collectgarbage("count") also reports and which is unrelated to whether
-- T.Strip's own tables grow -- confirmed by measuring the same loop with
-- jit.off() (0.00 KB) vs jit left on (~2.4 KB of pure JIT trace noise even
-- after thousands of warm-up calls).
if jit then jit.off() end
collectgarbage()
local kbBefore = collectgarbage("count")
for _ = 1, 100 do
  out = T.Strip(stripEvents, nStrip, stripLive, stripOpts, out)
end
collectgarbage()
local kbAfter = collectgarbage("count")
if jit then jit.on() end
ok(kbAfter - kbBefore < 2, "100 steady-state T.Strip calls retain < 2 KB after GC (grew "
   .. string.format("%.2f", kbAfter - kbBefore) .. " KB)")

-- Cursor jump: with only `now` known (no fresh live-prediction fields), the
-- 20 s event stream is entirely in the past relative to the new window
-- [98, 104.5], so nothing overlaps -- and stale item[1] must be cleared.
local stripLiveLate = { now = 100 }
out = T.Strip(stripEvents, nStrip, stripLiveLate, stripOpts, out)
ok(out.nItems == 0, "cursor jump to now=100 -> 0 items")
ok(out.items[1].lane == nil, "stale item[1].lane cleared after cursor jump")

-- 6. T.Strip scan-cursor (out._scanFrom): bounded rescan cost across a long
-- fight, without changing results. 1000 events, alternating "auto" (only
-- `.t`) and "cast" (only `.t0`/`.t1`, exercising the `ev.t or ev.t1`
-- nil-safe fallback) 1 s apart.
local function buildLongStream(nEvents)
  local evs = {}
  for i = 0, nEvents - 1 do
    if i % 10 == 0 then
      evs[#evs + 1] = { kind = "cast", spell = "steady", t0 = i, t1 = i + 1.5 }
    else
      evs[#evs + 1] = { kind = "auto", t = i, delay = 0 }
    end
  end
  return evs, #evs
end

local function snapshotItems(out)
  local snap = {}
  for i = 1, out.nItems do
    local it = out.items[i]
    snap[i] = { lane = it.lane, t0 = it.t0, t1 = it.t1, sym = it.sym, color = it.color,
                future = it.future, band = it.band, label = it.label }
  end
  return snap
end

local function snapshotsEqual(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    for k, v in pairs(a[i]) do
      if a[i][k] ~= b[i][k] then return false end
    end
  end
  return true
end

local longEvents, nLong = buildLongStream(1000)

local longOut = { items = {}, nItems = 0, marks = {}, nMarks = 0 }
longOut = T.Strip(longEvents, nLong, { now = 500 }, {}, longOut)
local scanFromAfter500 = longOut._scanFrom
ok(scanFromAfter500 ~= nil and scanFromAfter500 > 1, "scanFrom advanced past the early events by now=500")

local fresh500 = { items = {}, nItems = 0, marks = {}, nMarks = 0 }
fresh500 = T.Strip(longEvents, nLong, { now = 500 }, {}, fresh500)
ok(snapshotsEqual(snapshotItems(longOut), snapshotItems(fresh500)), "now=500 items match a fresh out")

longOut = T.Strip(longEvents, nLong, { now = 900 }, {}, longOut)
ok(longOut._scanFrom > scanFromAfter500, "scanFrom advanced further by now=900")

local fresh900 = { items = {}, nItems = 0, marks = {}, nMarks = 0 }
fresh900 = T.Strip(longEvents, nLong, { now = 900 }, {}, fresh900)
ok(snapshotsEqual(snapshotItems(longOut), snapshotItems(fresh900)), "now=900 items match a fresh out")

-- Rewind: now < _lastNow (a new fight) resets scanFrom back to 1.
longOut = T.Strip(longEvents, nLong, { now = 10 }, {}, longOut)
ok(longOut._scanFrom == 1, "rewind to now=10 after now=900 resets scanFrom to 1")

local fresh10 = { items = {}, nItems = 0, marks = {}, nMarks = 0 }
fresh10 = T.Strip(longEvents, nLong, { now = 10 }, {}, fresh10)
ok(snapshotsEqual(snapshotItems(longOut), snapshotItems(fresh10)), "now=10 after rewind matches a fresh out")

-- 7. Stream change with a MONOTONIC clock (the in-game case). GetTime() never
-- goes backwards between fights, so the `now < _lastNow` rewind never fires
-- there: a fresh, shorter event table must be detected on its own. Before the
-- fix the cursor stayed parked past the new table's end and the past lane went
-- blank for the whole next fight.
local function evsOverSeconds(secs)
  local evs = {}
  for i = 0, secs - 1 do evs[#evs + 1] = { kind = "auto", t = i, delay = 0 } end
  return evs, #evs
end

local longFight, nLongFight = evsOverSeconds(120)
local reuse = { items = {}, nItems = 0, marks = {}, nMarks = 0 }
reuse = T.Strip(longFight, nLongFight, { now = 120 }, {}, reuse)
ok(reuse._scanFrom > 1, "long fight at now=120 advanced the scan cursor (got " .. tostring(reuse._scanFrom) .. ")")

-- The next fight: a brand-new, 20-event table, and `now` still climbing.
local nextFight, nNextFight = {}, 0
for i = 0, 19 do nextFight[i + 1] = { kind = "auto", t = 128 + i * 0.1, delay = 0 } end
nNextFight = #nextFight

reuse = T.Strip(nextFight, nNextFight, { now = 130 }, {}, reuse)
local freshNext = { items = {}, nItems = 0, marks = {}, nMarks = 0 }
freshNext = T.Strip(nextFight, nNextFight, { now = 130 }, {}, freshNext)
ok(reuse._scanFrom == 1, "new (shorter) stream rewinds the cursor to 1")
ok(reuse.nItems == freshNext.nItems,
   "new stream at now=130 yields a fresh out's item count (reused " .. reuse.nItems
   .. " vs fresh " .. freshNext.nItems .. ")")
ok(freshNext.nItems > 0, "the new stream actually has items in the window (sanity)")
ok(snapshotsEqual(snapshotItems(reuse), snapshotItems(freshNext)), "new stream items match a fresh out")

-- The third signal: same event COUNT, but every event ahead of `now` (a new
-- fight whose stream happens to be the same length). The skipped-event probe
-- catches what the n-shrink test cannot.
local sameLen = {}
for i = 1, nLongFight do sameLen[i] = { kind = "auto", t = 200 + i * 0.1, delay = 0 } end
local reuse2 = { items = {}, nItems = 0, marks = {}, nMarks = 0 }
reuse2 = T.Strip(longFight, nLongFight, { now = 120 }, {}, reuse2)
ok(reuse2._scanFrom > 1, "same-length case: cursor advanced on the first stream")
reuse2 = T.Strip(sameLen, nLongFight, { now = 201 }, {}, reuse2)
local fresh2 = { items = {}, nItems = 0, marks = {}, nMarks = 0 }
fresh2 = T.Strip(sameLen, nLongFight, { now = 201 }, {}, fresh2)
ok(reuse2._scanFrom == 1, "same-length replacement stream rewinds the cursor to 1")
ok(snapshotsEqual(snapshotItems(reuse2), snapshotItems(fresh2)), "same-length replacement matches a fresh out")

-- 8. Held procs (a paper drill's hold=): the engine parks them at now + 1e9,
-- so the strip must label the span rather than print a remaining time.
local holdLive = {
  now = 10, procs = { RF = 10 + 1e9 }, hold = { RF = true },
}
local holdOut = T.Strip({}, 0, holdLive, { past = 2, future = 4.5 }, nil)
local heldSpan = nil
for i = 1, holdOut.nItems do
  local it = holdOut.items[i]
  if it.lane == "procs" and it.sym == "RF" then heldSpan = it end
end
ok(heldSpan ~= nil, "held RF span present")
ok(heldSpan and heldSpan.label == "held", "held RF span is labelled 'held' (got "
   .. tostring(heldSpan and heldSpan.label) .. ")")
ok(heldSpan and near(heldSpan.t1, 14.5), "held RF span runs to the horizon, not to the sentinel")

-- ...and without hold=, the same proc still reads as a countdown.
local noHoldOut = T.Strip({}, 0, { now = 10, procs = { RF = 17 } }, { past = 2, future = 4.5 }, nil)
local cdSpan = nil
for i = 1, noHoldOut.nItems do
  local it = noHoldOut.items[i]
  if it.lane == "procs" and it.sym == "RF" then cdSpan = it end
end
ok(cdSpan ~= nil and cdSpan.label == nil, "un-held RF span carries no text label")
ok(cdSpan and near(cdSpan.t0, 7) and near(cdSpan.t1, 14.5),
   "un-held RF span spans wt0 - 1 .. min(untilT, horizon)")

--------------------------------------------------------------------------------
-- 10. T.Cycles: the review's paper-vs-played row. One entry per auto-to-auto
-- cycle, carrying what the window's paper rotation puts in that cycle position
-- against what was actually pressed inside it.
--------------------------------------------------------------------------------
local cycH = { ws = 3.0, rangedMul = 1.38, mws = 3.7, meleeMul = 1, castCorr = 1,
               imprArcanePts = 0, multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 }
local CYCLE = 3.0 / 1.38          -- one auto-to-auto cycle at this haste
local WINDUP = 0.5 / 1.38

-- A clean 1:1 stream: an auto every cycle with a Steady straight after it.
local function frenchStream(nCycles, swap)
  local evs = { { kind = "pull", t = 0 } }
  for k = 0, nCycles - 1 do
    local t = k * CYCLE
    evs[#evs + 1] = { kind = "auto", t = t, delay = 0 }
    local spell = (swap and swap[k + 1]) or "steady"
    evs[#evs + 1] = { kind = "cast", spell = spell, t0 = t + 0.05, t1 = t + 0.05 + 1.5 / 1.38 }
  end
  evs[#evs + 1] = { kind = "stop", t = (nCycles - 1) * CYCLE + 1.6 }
  return evs, #evs
end

local cleanEvents, nClean = frenchStream(6)
local cleanScore = { windows = { { t0 = 0, t1 = 20, rangedMul = 1.38, notation = "drill 1:1" } } }
local cyc = T.Cycles(cleanEvents, nClean, cleanScore, cycH, M, nil)

ok(cyc.n == 6, "clean stream: one cycle per auto (got " .. tostring(cyc.n) .. ")")
local allOk, allPaper = true, true
for i = 1, cyc.n do
  if not cyc[i].ok then allOk = false end
  if cyc[i].paper ~= "s" or cyc[i].played ~= "s" then allPaper = false end
end
ok(allOk, "clean stream: every cycle ok")
ok(allPaper, "clean stream: every cycle reads paper s / played s")
ok(near(cyc[1].t0, 0) and near(cyc[1].t1, CYCLE), "cycle 1 spans auto 1 -> auto 2")
ok(near(cyc[6].t0, 5 * CYCLE) and near(cyc[6].t1, 5 * CYCLE + 1.6),
   "the open last cycle ends at the last event time")

-- One cycle with a Multi where the paper wants a Steady.
local mixEvents, nMix = frenchStream(6, { [3] = "multi" })
local cyc2 = T.Cycles(mixEvents, nMix, cleanScore, cycH, M, nil)
ok(cyc2.n == 6, "mixed stream: 6 cycles")
ok(cyc2[3].ok == false and cyc2[3].paper == "s" and cyc2[3].played == "m",
   "the Multi cycle: paper s / played m / not ok")
local othersOk = true
for i = 1, cyc2.n do
  if i ~= 3 and not cyc2[i].ok then othersOk = false end
end
ok(othersOk, "...and every other cycle is still ok")

-- A cancelled cast never became a shot: it is not what you played.
local cancelEvents, nCancel = frenchStream(3)
cancelEvents[#cancelEvents + 1] = { kind = "cast", spell = "multi", t0 = 0.9, t1 = 1.2, cancelled = true }
local cyc3 = T.Cycles(cancelEvents, nCancel + 1, cleanScore, cycH, M, nil)
ok(cyc3[1].played == "s" and cyc3[1].ok, "a cancelled cast is not counted as played")

-- A weave notation: the paper's `w` slot is filled by a Raptor (`r`), and the
-- two are the same weave — the strings stay faithful, the verdict does not.
local WEAVE_NOTATION = "3:7 2w"
local weaveStr = M.STRINGS[WEAVE_NOTATION]
ok(weaveStr == "awasaawasaas", "fixture: 3:7 2w is awasaawasaas")
local wLay = M.Layout(weaveStr, cycH, 0)
-- Play the layout back exactly, three periods of it, with every `w` slot taken
-- as a Raptor. Autos are the cycle boundaries; casts/weaves land on their own
-- layout offsets.
local weaveEvents, nWeave = { { kind = "pull", t = 0 } }, 0
local PERIODS = 3
for k = 0, PERIODS - 1 do
  local base = k * wLay.dur
  for _, pe in ipairs(wLay.ev) do
    if pe.sym == "a" then
      weaveEvents[#weaveEvents + 1] = { kind = "auto", t = base + pe.t0 + pe.dur, delay = 0 }
    elseif pe.sym == "s" then
      weaveEvents[#weaveEvents + 1] = { kind = "cast", spell = "steady", t0 = base + pe.t0, t1 = base + pe.t0 + pe.dur }
    elseif pe.sym == "w" or pe.sym == "r" then
      weaveEvents[#weaveEvents + 1] = { kind = "melee", t = base + pe.t0, hit = "r" }
    end
  end
end
weaveEvents[#weaveEvents + 1] = { kind = "stop", t = PERIODS * wLay.dur + 2 }
nWeave = #weaveEvents
local weaveScore = { windows = { { t0 = 0, t1 = PERIODS * wLay.dur + 2, rangedMul = 1.38, notation = WEAVE_NOTATION } } }
local cyc4 = T.Cycles(weaveEvents, nWeave, weaveScore, cycH, M, nil)
local wAutos = 0
for _, pe in ipairs(wLay.ev) do if pe.sym == "a" then wAutos = wAutos + 1 end end
ok(cyc4.n == wAutos * PERIODS, "weave stream: one cycle per layout auto, per period (got "
   .. tostring(cyc4.n) .. " want " .. tostring(wAutos * PERIODS) .. ")")
local weaveAllOk, weaveCycle = true, nil
for i = 1, cyc4.n do
  if not cyc4[i].ok then weaveAllOk = false end
  if weaveCycle == nil and cyc4[i].paper:find("w", 1, true) then weaveCycle = cyc4[i] end
end
ok(weaveAllOk, "weave stream played back off the paper: every cycle ok")
ok(weaveCycle ~= nil, "at least one cycle carries a weave slot")
ok(weaveCycle and weaveCycle.played:find("r", 1, true) ~= nil,
   "...and the played side reads it as the Raptor it was")
ok(weaveCycle and weaveCycle.ok, "...while a Raptor in a `w` slot still counts as the weave")

-- A weave the paper never asked for is a mismatch all the same.
local strayEvents, nStray = frenchStream(4)
strayEvents[#strayEvents + 1] = { kind = "melee", t = CYCLE + 0.4, hit = "r" }
local cyc5 = T.Cycles(strayEvents, nStray + 1, cleanScore, cycH, M, nil)
ok(cyc5[2].ok == false and cyc5[2].played == "s r", "an unasked-for weave shows as s r and is not ok")

-- The trailing cycle is OPEN. Mid-fight it ends at the auto that opened it, so
-- a non-empty paper against a still-empty played side made it red every single
-- time the review was opened. It is flagged instead.
do
  local openEvents = { { kind = "pull", t = 0 } }
  for k = 0, 3 do
    local t = k * CYCLE
    openEvents[#openEvents + 1] = { kind = "auto", t = t, delay = 0 }
    if k < 3 then
      openEvents[#openEvents + 1] = { kind = "cast", spell = "steady", t0 = t + 0.05, t1 = t + 1.14 }
    end
  end
  local cycOpen = T.Cycles(openEvents, #openEvents, cleanScore, cycH, M, nil)
  ok(cycOpen.n == 4, "open stream: 4 cycles (got " .. tostring(cycOpen.n) .. ")")
  ok(cycOpen[4].partial == true, "the trailing cycle, ended by its own auto, is partial")
  ok(cycOpen[3].partial == false, "...and the cycle before it is not")
  ok(cycOpen[4].ok == false, "the trailing cycle still reports the raw comparison")

  -- A trailing cycle that actually ran its length is a real cycle.
  local fullEnd = {}
  for i = 1, nClean do fullEnd[i] = cleanEvents[i] end
  fullEnd[nClean] = { kind = "stop", t = 6 * CYCLE }
  local cycFull = T.Cycles(fullEnd, nClean, cleanScore, cycH, M, nil)
  ok(cycFull[6].partial == false, "a trailing cycle that ran its full length is not partial")
  ok(cycFull[1].partial == false and cycFull[5].partial == false, "...and no interior cycle ever is")
end

-- r -> w forgives a weave SLOT, and only that: a Raptor where the paper wanted
-- a Steady is still a mismatch.
do
  local swapEvents = { { kind = "pull", t = 0 } }
  for k = 0, 3 do
    local t = k * CYCLE
    swapEvents[#swapEvents + 1] = { kind = "auto", t = t, delay = 0 }
    if k == 1 then swapEvents[#swapEvents + 1] = { kind = "melee", t = t + 0.05, hit = "r" }
    else swapEvents[#swapEvents + 1] = { kind = "cast", spell = "steady", t0 = t + 0.05, t1 = t + 1.14 } end
  end
  swapEvents[#swapEvents + 1] = { kind = "stop", t = 4 * CYCLE }
  local cycSwap = T.Cycles(swapEvents, #swapEvents, cleanScore, cycH, M, nil)
  ok(cycSwap[2].played == "r" and cycSwap[2].ok == false,
     "a Raptor where the paper wanted a Steady is a mismatch")
  ok(cycSwap[1].ok and cycSwap[3].ok, "...and the Steady cycles around it are fine")
end

-- Two haste windows: each cycle is graded against the notation of the window
-- it falls in, and the position restarts at the window's first cycle.
local twoWinScore = { windows = {
  { t0 = 0, t1 = 3 * CYCLE, rangedMul = 1.38, notation = "drill 1:1" },
  { t0 = 3 * CYCLE, t1 = 20, rangedMul = 1.38, notation = "1:2" },
} }
local cyc6 = T.Cycles(cleanEvents, nClean, twoWinScore, cycH, M, nil)
ok(cyc6[1].paper == "s" and cyc6[2].paper == "s", "window 1 (1:1) wants a Steady every cycle")
ok(cyc6[4].paper == "s" and cyc6[5].paper == "" and cyc6[6].paper == "s",
   "window 2 (1:2) alternates Steady / nothing from its own first cycle")
ok(cyc6[5].ok == false and cyc6[5].played == "s", "the empty 1:2 cycle flags the extra Steady")

-- THE MATCHER OWNS CYCLE MEMBERSHIP (R5a). `score.match` is PracticeGrader's
-- map — the moment a play was made against the index of the cycle whose NOTE it
-- took — and it wins over the clock. It is how the row and the judgments agree
-- on a paper whose own cycle is wider than the measured one, where a note is
-- seated past the next release.
do
  -- Keyed by the play's own EVENT, never by its time: two plays can share a
  -- moment (a paper that writes a weave and a cast on one beat), and a float
  -- key gave them each other's seat.
  local thirdCast = nil
  for i = 1, nClean do
    local e = cleanEvents[i]
    if e.kind == "cast" and near(e.t0, 2 * CYCLE + 0.05) then thirdCast = e end
  end
  ok(thirdCast ~= nil, "the third cycle's cast is in the clean stream")
  local matchScore = { windows = cleanScore.windows, match = { [thirdCast] = 2 } }
  local cycM = T.Cycles(cleanEvents, nClean, matchScore, cycH, M, nil)
  ok(cycM[2].played == "s s", "a matched play files into its NOTE's cycle, not the clock's ("
     .. tostring(cycM[2].played) .. ")")
  ok(cycM[3].played == "", "...and it leaves the cycle it fell in by the clock")
  -- No entry, no change: an unmatched play is still filed by the clock.
  local cycN = T.Cycles(cleanEvents, nClean, { windows = cleanScore.windows, match = {} }, cycH, M, nil)
  ok(cycN[3].played == "s", "an unmatched play keeps filing by the clock")
end

-- A cycle's played string is in the order the presses were MADE. A cast is
-- pushed at its end, so a Steady begun before a weave and finished after it
-- reached the stream behind the melee — and the row read `w s` against a paper
-- that says `s w`.
do
  local evs = {
    { kind = "pull", t = 0 },
    { kind = "auto", t = 0, delay = 0 },
    { kind = "melee", t = 0.6, hit = "r" },
    { kind = "cast", spell = "steady", t0 = 0.2, t1 = 1.3, t = 1.3 },
    { kind = "auto", t = CYCLE, delay = 0 },
    { kind = "stop", t = CYCLE + 0.1 },
  }
  local ordered = T.Cycles(evs, #evs, cleanScore, cycH, M, nil)
  ok(ordered[1].played == "s r", "the played string follows the presses, not the stream ("
     .. tostring(ordered[1].played) .. ")")
end

-- Pooling: the same `out` is reused by identity and never grows, and a repeat
-- call on an unchanged fight rebuilds no strings.
local pooled = T.Cycles(cleanEvents, nClean, cleanScore, cycH, M, nil)
local c1Ref, cLastRef = pooled[1], pooled[pooled.n]
local playedRef = pooled[1].played
local lenBefore = #pooled
pooled = T.Cycles(cleanEvents, nClean, cleanScore, cycH, M, pooled)
ok(pooled[1] == c1Ref and pooled[pooled.n] == cLastRef, "repeat call reuses the cycle tables by identity")
ok(#pooled == lenBefore, "repeat call does not grow the pool")
ok(rawequal(pooled[1].played, playedRef), "repeat call reuses the joined string (no rebuild)")
local layRef = pooled._lay and pooled._lay[1]
pooled = T.Cycles(cleanEvents, nClean, cleanScore, cycH, M, pooled)
ok(pooled._lay[1] == layRef and #pooled._lay == 1, "the layout cache is reused by identity")

-- A shorter fight leaves no stale cycles behind `out.n`.
local shortEvents, nShort = frenchStream(2)
pooled = T.Cycles(shortEvents, nShort, cleanScore, cycH, M, pooled)
ok(pooled.n == 2, "a shorter stream reports 2 cycles")
ok(pooled[3].t0 == nil and pooled[3].paper == nil, "stale cycle 3 is cleared")

if jit then jit.off() end
collectgarbage()
local cKbBefore = collectgarbage("count")
for _ = 1, 100 do
  pooled = T.Cycles(cleanEvents, nClean, cleanScore, cycH, M, pooled)
end
collectgarbage()
local cKbAfter = collectgarbage("count")
if jit then jit.on() end
ok(cKbAfter - cKbBefore < 2, "100 steady-state T.Cycles calls retain < 2 KB after GC (grew "
   .. string.format("%.2f", cKbAfter - cKbBefore) .. " KB)")

-- No events, no windows: no cycles, and no crash.
local emptyCyc = T.Cycles({}, 0, nil, cycH, M, nil)
ok(emptyCyc.n == 0, "an empty stream yields no cycles")
-- No scorecard windows means no paper to compare against. A row of all-red
-- cycles would be a lie, not a finding: no cycles at all, so the row draws
-- nothing.
local noWin = T.Cycles(cleanEvents, nClean, nil, cycH, M, nil)
ok(noWin.n == 0, "with no scorecard windows there are no cycles at all")
local emptyWin = T.Cycles(cleanEvents, nClean, { windows = {} }, cycH, M, nil)
ok(emptyWin.n == 0, "...and an empty window list is the same")

--------------------------------------------------------------------------------
-- 11. Instants get a minimum DRAWN span. An Arcane Shot is instant and a Multi
-- at speed is a quarter-second: at any readable scale their true spans came out
-- one or two pixels wide. Only the drawn `t1` moves -- the event's own times are
-- never touched.
--------------------------------------------------------------------------------
ok(T.MIN_CAST_DRAW == 0.35, "MIN_CAST_DRAW is 0.35 s")
do
local arc = {
  { kind = "pull", t = 0 },
  { kind = "cast", spell = "arcane", t0 = 1, t1 = 1 },
  { kind = "cast", spell = "steady", t0 = 2, t1 = 3.09 },
  { kind = "stop", t = 5 },
}
local atl = T.Build(arc, #arc, nil, h, { model = M, windup = 0.36 })
local arcIt, steadyIt = nil, nil
for _, it in ipairs(atl.lanes.cast) do
  if it.sym == "A" then arcIt = it elseif it.sym == "s" then steadyIt = it end
end
ok(arcIt ~= nil and near(arcIt.t0, 1) and near(arcIt.t1 - arcIt.t0, 0.35),
   "T.Build: an instant Arcane is drawn 0.35 s wide")
ok(steadyIt ~= nil and near(steadyIt.t1, 3.09), "...and a real cast keeps its own length")

-- Same in the strip, for a past cast...
local sOut = T.Strip(arc, #arc, { now = 2 }, { past = 3, future = 3 }, nil)
local sArc = nil
for i = 1, sOut.nItems do
  local it = sOut.items[i]
  if it.sym == "A" then sArc = it end
end
ok(sArc ~= nil and near(sArc.t1 - sArc.t0, 0.35), "T.Strip: a played Arcane is drawn 0.35 s wide")


-- A verdict's GHOST is the shot that should have been there, and it is usually
-- an instant or a 0.15 s stub: same floor.
local ghostTl = T.Build(arc, #arc, nil, h, { model = M, windup = 0.36 }, {
  { t = 1, code = "STEADY_WONT_FIT", key = "steady", text = "x",
    ghost = { lane = "cast", sym = "A", t0 = 1, t1 = 1.15 } },
})
ok(ghostTl.ghosts[1] ~= nil and near(ghostTl.ghosts[1].t1 - ghostTl.ghosts[1].t0, 0.35),
   "a ghost narrower than the floor is widened to it")
end

-- The review's PAPER lane gets the floor too: the model draws an Arcane at
-- 0.10 s, which is a sliver of nothing at review scale. The lane's autos and
-- weave slots do NOT -- an `a`'s t1 IS the release (and at speed the whole
-- wind-up is under the floor), and a weave slot is not a press.
do
local pScore = { windows = { { t0 = 0, t1 = 12, rangedMul = 1.932, notation = "5:5:1:1" } } }
local pTl = T.Build({ { kind = "pull", t = 0 }, { kind = "stop", t = 12 } }, 2, pScore, h,
                    { model = M, windup = 0.26 })
local pArc, pAuto = nil, nil
for _, it in ipairs(pTl.lanes.paper) do
  if it.sym == "A" and pArc == nil then pArc = it end
  if it.sym == "a" and pAuto == nil then pAuto = it end
end
ok(pArc ~= nil and near(pArc.t1 - pArc.t0, 0.35),
   "paper lane: an Arcane is drawn 0.35 s wide (was 0.10 -- invisible)")
ok(pAuto ~= nil and pAuto.t1 - pAuto.t0 < 0.35,
   "...and the lane's autos keep their own wind-up, floor or no floor ("
   .. string.format("%.3f", pAuto and (pAuto.t1 - pAuto.t0) or -1) .. ")")
end

--------------------------------------------------------------------------------
-- 12. A stream with no `pull` has no ORIGIN. `tl.t0` falls back to the first
-- event, never to a literal 0: with `or 0` every relative stamp built off it
-- rendered the raw GetTime() clock (the review's "305232320.92").
--------------------------------------------------------------------------------
do
local orphan = {
  { kind = "auto", t = 305232320.92, delay = 0 },
  { kind = "stop", t = 305232330.92 },
}
local otl = T.Build(orphan, #orphan, nil, h, { model = M, windup = 0.36 })
ok(otl.t0 == 305232320.92, "no pull: tl.t0 is the first event, not 0")
ok(near(otl.t1 - otl.t0, 10), "...and the fight still reads as 10 s long")
local none = T.Build({}, 0, nil, h, { model = M })
ok(none.t0 == nil, "an EMPTY stream has no origin at all: tl.t0 is nil, never 0")
end

--------------------------------------------------------------------------------
-- 15. THE STRIP DRAWS THE PLAN (v3 P1). Every paper item is a note of
-- state.sim.plan (Core/PracticePlan.lua): one NEXT, chosen there; no engine
-- bar; an unplayable note dimmed (`oncd`); a pending note past its time still
-- on the strip wearing NEXT; a hit note behind the cursor not re-drawn (the
-- event stream draws the cast that took it).
do
  local P = dofile("Core/PracticePlan.lua")
  local plan = P.New()
  plan.live, plan.pulled, plan.now, plan.n = true, true, 100, 4
  local function note(i, key, sym, t0, t1, state, playable)
    local nt = plan.notes[i]
    nt.key, nt.row, nt.sym, nt.t0, nt.t1, nt.state, nt.playable, nt.cycle, nt.idx =
      key, P.ROW[sym], sym, t0, t1, state, playable, 1, i
  end
  note(1, T.KEY.PAPER + 1, "s", 99.5, 100.6, P.HIT, true)       -- played, in the past
  note(2, T.KEY.PAPER + 2, "m", 101.0, 101.4, P.PENDING, false) -- on cooldown
  note(3, T.KEY.PAPER + 3, "s", 102.0, 103.1, P.PENDING, true)
  note(4, T.KEY.PAPER + 4, "w", 103.6, 103.6, P.PENDING, true)
  plan.notes[4].raptor = true
  plan.nextIdx, plan.nextKey = 3, T.KEY.PAPER + 3
  local live = { now = 100, plan = plan, nextShotAt = 102.2, cycle = 2.174, windup = 0.36, lastShotAt = 100.0,
                 procs = {}, paperSyms = { s = true, m = true, w = true },
                 weaveAt = 102.2, weaveTtw = 1.5, weaveFits = true, weaveMoveAt = 101.8,
                 meleeReadyAt = 102.2, cdReady = { Raptor = 103.0 } }
  local out = T.Strip({}, 0, live, { past = 2, future = 4.5 }, nil)
  local seen, nextCount, oncd = {}, 0, false
  for i = 1, out.nItems do
    local it = out.items[i]
    if it.key then seen[it.key] = it end
    if it.label == "NEXT" then nextCount = nextCount + 1 end
    if it.key == T.KEY.PAPER + 2 and it.oncd then oncd = true end
  end
  ok(seen[T.KEY.PAPER + 2] ~= nil and seen[T.KEY.PAPER + 3] ~= nil, "15: pending plan notes are drawn")
  ok(seen[T.KEY.PAPER + 1] == nil, "15: a hit note in the past is not re-drawn as paper")
  ok(nextCount == 1 and seen[T.KEY.PAPER + 3] and seen[T.KEY.PAPER + 3].label == "NEXT", "15: exactly one NEXT, on plan.nextIdx")
  ok(oncd, "15: an unplayable note is flagged oncd (dimmed)")
  ok(seen[T.KEY.PAPER + 3].lane == "shots", "15: s note on the shots lane")
  ok(T.NoteKey(3, 2) == T.KEY.PAPER + 3 * T.KEY.PAPER_SLOTS + 2, "15: NoteKey is cycle * slots + index")
  -- The grid is the plan's autos, keyed by cycle (v3 P2).
  plan.nAutos = 2
  plan.autos[1].key, plan.autos[1].windupAt, plan.autos[1].releaseAt, plan.autos[1].cycle = T.KEY.GRID + 2, 101.84, 102.2, 2
  plan.autos[2].key, plan.autos[2].windupAt, plan.autos[2].releaseAt, plan.autos[2].cycle = T.KEY.GRID + 3, 104.01, 104.374, 3
  local out3 = T.Strip({}, 0, live, { past = 2, future = 4.5 }, nil)
  local gridKeys, gridN = {}, 0
  for i = 1, out3.nItems do
    local it = out3.items[i]
    if it.key and it.key >= T.KEY.GRID and it.key < T.KEY.MOVE then gridN = gridN + 1; gridKeys[it.key] = it end
  end
  ok(gridN == 2 and gridKeys[T.KEY.GRID + 2] ~= nil and gridKeys[T.KEY.GRID + 3] ~= nil, "15: the grid is the plan's autos, keyed by cycle (" .. gridN .. ")")
  ok(gridKeys[T.KEY.GRID + 2] and gridKeys[T.KEY.GRID + 2].row == "auto", "15: grid autos on the auto row")
  ok(gridKeys[T.KEY.GRID + 2] and math.abs(gridKeys[T.KEY.GRID + 2].t0 - 101.84) < 1e-9
     and math.abs(gridKeys[T.KEY.GRID + 2].t1 - 102.2) < 1e-9, "15: a grid auto spans wind-up to release")
  ok(out3._paper == nil, "15: no paper layout cache on the strip")
  plan.nAutos = 0
  ok(seen[T.KEY.PAPER + 4] ~= nil and seen[T.KEY.PAPER + 4].lane == "weave", "15: w note on the weave lane")
  ok(seen[T.KEY.PAPER + 4] and seen[T.KEY.PAPER + 4].sym == "r", "15: a Raptor-ready weave note is drawn as r")
  plan.notes[4].raptor = false
  local out2 = T.Strip({}, 0, live, { past = 2, future = 4.5 }, nil)
  local wSym
  for i = 1, out2.nItems do if out2.items[i].key == T.KEY.PAPER + 4 then wSym = out2.items[i].sym end end
  ok(wSym == "w", "15: a weave note with Raptor on cooldown is drawn as the white swing")
  ok(seen[T.KEY.PAPER + 4] and seen[T.KEY.PAPER + 4].t1 - seen[T.KEY.PAPER + 4].t0 >= T.MIN_CAST_DRAW - 1e-9,
     "15: a weave note is never drawn thinner than MIN_CAST_DRAW")
  ok(seen[T.KEY.PAPER + 3].future == true, "15: a note ahead of the cursor is future")
  -- Rows (v3 P3): every item names the row it lives on.
  local rowsOk = true
  for i = 1, out.nItems do if out.items[i].row == nil then rowsOk = false end end
  ok(rowsOk, "15: every strip item carries a row")
  ok(seen[T.KEY.PAPER + 3].row == "s" and seen[T.KEY.PAPER + 2].row == "m" and seen[T.KEY.PAPER + 4].row == "w",
     "15: cast notes on their own rows, the weave note on w")
  ok(seen[T.KEY.BAND] and seen[T.KEY.BAND].row == "w" and seen[T.KEY.MOVE] and seen[T.KEY.MOVE].row == "w", "15: band and ramp on the weave row")
  local mv, bd = seen[T.KEY.MOVE], seen[T.KEY.BAND]
  ok(bd ~= nil and bd.lane == "weave" and math.abs(bd.t0 - 102.2) < 1e-9, "15: the weave band is on the lane")
  ok(mv ~= nil and mv.lane == "weave" and math.abs(mv.t0 - 101.8) < 1e-9 and math.abs(mv.t1 - 102.2) < 1e-9 and mv.thin,
     "15: the move-in ramp runs from moveAt to the band")
  local ticks = 0
  for i = 1, out.nItems do
    local it = out.items[i]
    if it.lane == "weave" and (it.label == "swing ready" or it.label == "Raptor ready") then ticks = ticks + 1 end
  end
  ok(ticks == 0, "15: with a plan the weave lane carries no ready ticks (" .. ticks .. ")")
  -- A pending note whose time has passed is still drawn (it is still NEXT).
  live.now = 102.4
  out = T.Strip({}, 0, live, { past = 2, future = 4.5 }, out)
  local still = false
  for i = 1, out.nItems do
    local it = out.items[i]
    if it.key == T.KEY.PAPER + 3 and it.label == "NEXT" and it.future == false then still = true end
  end
  ok(still, "15: a pending note inside grace stays on the strip wearing NEXT, no longer future")
  -- No plan (a fixture without one): no paper items at all, and no error.
  local bare = T.Strip({}, 0, { now = 100, nextShotAt = 102.2, cycle = 2.174, windup = 0.36, procs = {} },
                       { past = 2, future = 4.5 }, nil)
  local paperItems = 0
  for i = 1, bare.nItems do if (bare.items[i].key or 0) >= T.KEY.PAPER then paperItems = paperItems + 1 end end
  ok(paperItems == 0, "15: without a plan the strip projects nothing of its own")
end

-- THE MOVE LANE (the expert combat log, 2026-08-27): move spans, zone marks,
-- the open stretch off the live snapshot, and an auto drawn from its own
-- wind-up when the event carries one.
do
  local evs = {
    { kind = "pull", t = 0 },
    { kind = "range", t = 0, zone = "FAR", inMelee = false },
    { kind = "auto", t = 0.36, delay = 0, windupAt = 0.05 },
    { kind = "move", t = 1.0, t0 = 0.6, t1 = 1.0 },
    { kind = "range", t = 1.0, zone = "SWEET", inMelee = true },
    { kind = "melee", t = 1.1, hit = "r" },
    { kind = "move", t = 1.6, t0 = 1.2, t1 = 1.6, key = true },
    { kind = "range", t = 1.6, zone = "WEAVE", inMelee = false },
    { kind = "auto", t = 2.5, delay = 0 },
    { kind = "stop", t = 3 },
  }
  local tlm = T.Build(evs, #evs, nil, h, { windup = 0.36 })
  ok(#tlm.lanes.move == 2 and near(tlm.lanes.move[1].t0, 0.6) and near(tlm.lanes.move[1].t1, 1.0) and tlm.lanes.move[1].color == "move",
     "move: every move event is a span on the MOVE lane")
  ok(tlm.lanes.move[2].label == "step" and tlm.lanes.move[1].label == nil, "...a key-only leg says so, real feet carry no label")
  ok(#tlm.zones == 3 and tlm.zones[2].label == "melee" and tlm.zones[3].label == "ring" and tlm.zones[1].label == "far",
     "every range change is a zone mark with its one word")
  ok(near(tlm.lanes.auto[1].t0, 0.05) and near(tlm.lanes.auto[2].t0, 2.5 - 0.36), "an auto is drawn from its own wind-up when the event has one, else a flat windup back")
  local tlo = T.Build(evs, #evs, nil, h, { windup = 0.36, live = { now = 2.9, movingSince = 2.7 } })
  ok(#tlo.lanes.move == 3 and near(tlo.lanes.move[3].t0, 2.7) and near(tlo.lanes.move[3].t1, 2.9) and tlo.lanes.move[3].open == true,
     "the stretch still open at now is drawn to the cursor off the snapshot")
end

print(("practice_timeline: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
