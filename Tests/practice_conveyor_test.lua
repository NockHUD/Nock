-- Tests/practice_conveyor_test.lua
-- Headless conveyor: loads the real UI/Frame_PracticeConveyor.lua under a frame stub and asserts note identity across rebuilds.
package.path = "./?.lua;./Tests/?.lua;" .. package.path
local pass, fail = 0, 0
local function ok(cond, name) if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end end
local Stub = dofile("Tests/lib/frame_stub.lua")

-- The addon table and the libraries the file asks for at load.
Nock = { modules = {}, db = { profile = {} } }
function Nock:NewModule(name)
  local m = { name = name, RegisterMessage = function() end, SendMessage = function() end,
              RegisterEvent = function() end, ScheduleTimer = function() end, CancelTimer = function() end,
              Print = function() end }
  Nock.modules[name] = m
  return m
end
function Nock:GetModule(name) return Nock.modules[name] end
function Nock:SendMessage() end
_G.LibStub = setmetatable({}, { __call = function(_, lib)
  return { GetAddon = function() return Nock end, NewAddon = function() return Nock end,
           Fetch = function() return "font" end }
end })
_G.CreateFrame = Stub.CreateFrame
_G.UIParent = Stub.CreateFrame("Frame", "UIParent")
_G.GameTooltip = Stub.CreateFrame("Frame", "GameTooltip")
local NOW = 1000
_G.GetTime = function() return NOW end
_G.InCombatLockdown = function() return false end
_G.IsMouseButtonDown = function() return false end
_G.GetCursorPosition = function() return 0, 0 end
_G.PlaySound = function() end
_G.SOUNDKIT = {}
_G.UnitRangedDamage = function() return 2.174 end
_G.UnitAttackSpeed = function() return 3.7 end
_G.C_Spell = { GetSpellInfo = function() return {} end,
               GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
               GetSpellTexture = function() return "" end }

_G.UISpecialFrames = {}
_G.tinsert = table.insert

dofile("Core/Constants.lua")
dofile("Core/State.lua")
dofile("Core/PracticeModel.lua")
dofile("Core/PracticeTimeline.lua")
dofile("Core/PracticePlan.lua")
dofile("Modules/PracticeGrader.lua")
dofile("UI/IconAtlas.lua")
dofile("UI/Skin.lua")
Nock.UI = { GetFont = function() return "font" end, ApplyPanelBackground = function() end,
            PracticeScale = function() return 1 end, RegisterPracticeScale = function() end,
            ApplyBackdrop = function() end, RegisterPanelBackground = function() end,
            PracticeIconFor = function(sym) return "icon:" .. tostring(sym) end,
            PracticeNameFor = function(sym) return tostring(sym) end }

local T, P = Nock.PracticeTimeline, Nock.PracticePlan
local st = Nock.state
st.sim.active, st.sim.fightOn, st.sim.pulled, st.sim.t0 = true, true, true, NOW
local plan = P.New()
st.sim.plan = plan

-- The practice module the view talks to, in the shape it reads.
local events, nEvents = {}, 0
local live = { procs = {}, cdReady = {}, plan = plan, paperSyms = { s = true } }
local prac = Nock:NewModule("Practice")
prac.engine = { n = 0, fightOn = true, pulled = true, nPress = 0, nWeave = 0, repeating = true, t0 = NOW }
prac.grader = { verdicts = {}, win = { notation = "1:1" } }
function prac:ConveyorData() return events, nEvents, self.grader.verdicts end
function prac:Lookahead(out) for k, v in pairs(live) do out[k] = v end; out.now = NOW; return out end
function prac:FightPaper() return "1:1", 1.38 end
function prac:TraceLine() end
function prac:RowKey(row) if row == "s" then return "2" elseif row == "w" then return "MB4" end; return nil end
local idleRows = { "auto", "s", "m", "A" }
function prac:IdleRows(out) for i = 1, #idleRows do out[i] = idleRows[i] end; for i = #idleRows + 1, #out do out[i] = nil end; return #idleRows end

dofile("UI/PracticeTransport.lua")   -- after the Nock.UI stub: the transport registers on it
dofile("UI/Frame_PracticeConveyor.lua")
local View = Nock.modules.PracticeConveyorView
View:OnInitialize()
View:OnEnable()

-- One 1:1 plan: three cycles of Steady on the grid, keys by cycle.
local CYCLE, WINDUP = 2.174, 0.362
local function setPlan(t0Rel, mul)
  plan.live, plan.pulled, plan.now, plan.t0, plan.rev = true, true, NOW, NOW, plan.rev + 1
  plan.n, plan.nAutos = 0, 0
  for c = 1, 3 do
    local rel = NOW + t0Rel + (c - 1) * CYCLE * (mul or 1)
    plan.nAutos = plan.nAutos + 1
    local a = plan.autos[plan.nAutos]
    a.key, a.windupAt, a.releaseAt, a.cycle = T.KEY.GRID + c, rel - WINDUP, rel, c
    plan.n = plan.n + 1
    local nt = plan.notes[plan.n]
    nt.key, nt.row, nt.sym, nt.t0, nt.t1, nt.cycle, nt.idx = T.NoteKey(c, 1), "s", "s", rel + 0.05, rel + 1.1, c, 1
    nt.state, nt.playable, nt.grade, nt.raptor = P.PENDING, true, nil, false
  end
  plan.nextIdx, plan.nextKey, plan.nextSym = 1, plan.notes[1].key, "s"
  plan.rows[1], plan.rows[2], plan.nRows = "auto", "s", 2
  plan.weave.at, plan.weave.moveAt = nil, nil
end

-- Frames by key, straight off the pool.
local function framesByKey()
  local pool = View.pools.item
  local m, n = {}, 0
  for i = 1, pool.max do
    local f = pool[i]
    if f.key and f:IsShown() then m[f.key] = f; n = n + 1 end
  end
  return m, n
end

local function tick(dt)
  NOW = NOW + dt
  live.now = NOW
  plan.now = NOW
  View:Refresh(st)
end

-- 1. Two rebuilds of the same plan: every key keeps its frame, nothing fades or glides.
do
  setPlan(0.5)
  View:Refresh(st)
  local a, na = framesByKey()
  local fA = a[T.NoteKey(1, 1)]
  ok(na >= 6 and fA ~= nil, "1: the plan's notes and autos are on screen (" .. na .. ")")
  for _ = 1, 4 do tick(0.05) end        -- the fade-in runs its course (EASE_SEC)
  tick(0.4)                             -- past the 0.5 s floor: a rebuild
  local b = framesByKey()
  ok(b[T.NoteKey(1, 1)] == fA, "1: the same key is drawn by the same frame")
  ok(not fA.easing and not fA.fading and fA:GetAlpha() == 1, "1: ...and it neither glided nor faded")
end

-- 2. A haste change moves every note but re-creates none.
do
  local before, nb = framesByKey()
  setPlan(0.5, 0.8)                     -- notes move earlier
  View:Refresh(st)
  local after, na = framesByKey()
  local kept, moved = 0, 0
  for k, f in pairs(after) do
    if before[k] == f then kept = kept + 1 end
    if f.easing then moved = moved + 1 end
  end
  ok(kept == na and na == nb, ("2: every frame kept its key across a haste change (%d/%d)"):format(kept, na))
  ok(moved > 0, "2: ...and the moved notes glide")
  local faded = nil
  for k, f in pairs(after) do if f:GetAlpha() == 0 then faded = k end end
  ok(faded == nil, "2: ...and none re-fades from zero (key " .. tostring(faded) .. ")")
  for _ = 1, 4 do tick(0.05) end        -- the glides run their course
end

-- 3. A key that leaves the plan fades out; a new key fades in.
do
  local gone = T.NoteKey(3, 1)
  plan.n = plan.n - 1                    -- drop the third cycle's note
  plan.rev = plan.rev + 1
  View:Refresh(st)
  local m = framesByKey()
  ok(m[gone] ~= nil and m[gone].fading and m[gone].aTo == 0, "3: a gone key fades out")
  for _ = 1, 4 do tick(0.05) end         -- ...and is released once faded
  m = framesByKey()
  ok(m[gone] == nil, "3: ...and its frame is released once the fade has run")
  setPlan(0.5, 0.8)                      -- back, as a new key
  View:Refresh(st)
  m = framesByKey()
  -- ...to its resting brightness: not the next note, so the dim (style next = both).
  ok(m[gone] ~= nil and m[gone].fading and m[gone].aTo == 0.6 and m[gone].aFrom == 0, "3: a returning key fades in")
  for _ = 1, 4 do tick(0.05) end
end

-- 4. Text is not repainted when it did not change.
do
  View:Refresh(st)
  local n0 = Stub.counters.SetText
  tick(0.6)
  ok(Stub.counters.SetText == n0, "4: an unchanged strip sets no text (" .. (Stub.counters.SetText - n0) .. ")")
end

-- 5. No drift rebuild: with nothing changed, the strip is rebuilt no more than once per REBUILD_SEC.
do
  local builds = 0
  local orig = View.Rebuild
  View.Rebuild = function(self, ...) builds = builds + 1; return orig(self, ...) end
  for _ = 1, 30 do tick(0.01) end
  View.Rebuild = orig
  ok(builds <= 1, "5: 0.3 s of nothing happening rebuilds at most once (" .. builds .. ")")
end

-- 6. One row per ability: the rows are the plan's, labelled with icon and key.
do
  setPlan(0.5)                          -- rows: auto, s
  View:Refresh(st)
  local L = View.rowLabels
  ok(View._nRows == 2 and View._rows[1] == "auto" and View._rows[2] == "s", "6: a 1:1 plan shows two rows")
  ok(L[1]:IsShown() and L[2]:IsShown() and not L[3]:IsShown(), "6: two row labels shown, the rest hidden")
  ok(L[1].name:GetText() == "Auto" and L[2].name:GetText() == "Steady", "6: rows are named")
  ok(L[2].key:GetText() == "2" and L[1].key:GetText() == "NO KEY", "6: the bound key sits in the row label; NO KEY when unbound")
  local m = framesByKey()
  local fAuto, fS = m[T.KEY.GRID + 1], m[T.NoteKey(1, 1)]
  ok(fAuto and fS and fAuto.y ~= fS.y, "6: an auto and a Steady sit on different rows")
  -- Five rows: the paper uses every ability.
  plan.rows[1], plan.rows[2], plan.rows[3], plan.rows[4], plan.rows[5], plan.nRows = "auto", "s", "m", "A", "w", 5
  plan.rev = plan.rev + 1
  View:Refresh(st)
  ok(View._nRows == 5 and L[5]:IsShown() and L[5].name:GetText() == "Weave" and L[5].key:GetText() == "MB4",
     "6: a full paper shows five rows, the weave row with its key")
  -- A cooldown item the plan did not list adds the cd row.
  live.procs.RF = NOW + 8
  plan.rev = plan.rev + 1
  View:Refresh(st)
  ok(View._nRows == 6 and View._rows[6] == "cd" and L[6].name:GetText() == "CDs", "6: a proc on the strip adds the cd row")
  live.procs.RF = nil
  -- Unchanged rows: no label text is set again.
  plan.rev = plan.rev + 1
  View:Refresh(st)
  local n0 = Stub.counters.SetText
  plan.rev = plan.rev + 1
  View:Refresh(st)
  ok(Stub.counters.SetText == n0, "6: unchanged rows set no label text (" .. (Stub.counters.SetText - n0) .. ")")
  setPlan(0.5)
  View:Refresh(st)
  ok(View._nRows == 2 and not L[3]:IsShown(), "6: back to two rows, the others hidden")
end

-- 7. Before a fight the rows are the picked scenario's, keys included.
do
  local keepLive = live
  st.sim.fightOn = false
  prac.Lookahead = function() return nil end
  View:Refresh(st)
  local L = View.rowLabels
  ok(View._nRows == 4 and View._rows[4] == "A" and L[4]:IsShown() and L[4].name:GetText() == "Arcane",
     "7: idle, the stage shows the picked paper's rows")
  ok(L[2].key:GetText() == "2", "7: ...with the bound keys")
  idleRows = { "auto", "w" }
  View:Refresh(st)
  ok(View._nRows == 2 and View._rows[2] == "w" and not L[3]:IsShown(), "7: a new pick re-rows the stage at once")
  st.sim.fightOn = true
  prac.Lookahead = function(_, out) for k, v in pairs(keepLive) do out[k] = v end; out.now = NOW; return out end
end

-- 8. The stage's style (P3 polish): the shipped look, then a lever change repaints without re-keying.
do
  setPlan(0.5)
  View:Refresh(st)
  for _ = 1, 4 do tick(0.05) end
  local m = framesByKey()
  local fNext, fLater, fAuto = m[T.NoteKey(1, 1)], m[T.NoteKey(2, 1)], m[T.KEY.GRID + 1]
  ok(fNext and fLater and fAuto, "8: next note, a later note and an auto are on screen")
  -- Glass: a tinted fill and a coloured edge on every note; the next one wears a white edge at full alpha.
  ok(fLater.fillA == 0.28 and fLater.edgeA == 0.9 and fLater.hiA == 0.35 and not fLater.ew, "8: a pending note is glass (tint, edge, highlight)")
  ok(fNext.ew == true and fNext.edgeA == 1 and fNext.fillA > fLater.fillA, "8: the next note is brightened with a white edge")
  ok(fNext.aTo == 1 and fLater.aTo == 0.6, "8: ...and every other pending note settles dimmed")
  ok(fNext.labelText == nil, "8: the word NEXT is not in the note (the chip says it)")
  -- The chip rides the next note's frame and names its key.
  local chip = View.chip
  ok(chip:IsShown() and View._chipFrame == fNext, "8: the NEXT chip is anchored to the next note's frame")
  ok(chip.text:GetText() == "NEXT 2", "8: ...and reads the word and the bound key (" .. tostring(chip.text:GetText()) .. ")")
  -- The auto row: a faint wash, a 1 px release hairline, no column.
  ok(fAuto.fillA == 0.10 and fAuto.tickW == 1 and fAuto.edgeA == nil and (fAuto.colH or 0) == 0, "8: an auto is a faint wash with a hairline tick")
  ok(fAuto.edges[4]:IsShown() and fAuto.edges[1]:IsShown() == false, "8: ...only the right edge is drawn")
  -- A played cast behind the hit line fades.
  nEvents = 1
  events[1] = { kind = "cast", spell = "steady", t0 = NOW - 1.5, t1 = NOW - 0.2 }
  plan.rev = plan.rev + 1
  View:Refresh(st)
  m = framesByKey()
  local fPlayed = m[T.KEY.PLAYED + 1]
  ok(fPlayed and fPlayed.aTo == 0.4, "8: a played note settles at the past alpha")
  -- ...and it took a FREE frame: the auto and the notes the strip still holds
  -- keep theirs (a new key painted first used to steal the first idle-looking
  -- frame in the pool, and the auto fell off its frame every time a cast landed).
  ok(fAuto.key == T.KEY.GRID + 1 and fNext.key == T.NoteKey(1, 1) and fPlayed ~= fAuto and fPlayed ~= fNext,
     "8: a new played item never steals a frame the strip still holds")
  nEvents = 0; events[1] = nil
  -- Furniture: zebra on the second row, the NOW column shown, the glow hidden.
  ok(View.laneBg[2]:IsShown() and not View.laneBg[1]:IsShown(), "8: zebra tints every second row")
  ok(View.hitCol:IsShown() and not View.hitGlow[1]:IsShown(), "8: the NOW column replaces the glow")
  -- A lever change: the same frames repaint, none re-keys or fades in again.
  Nock.db.profile.practiceStyleNote = "solid"
  Nock.db.profile.practiceStyleNext = "word"
  Nock.db.profile.practiceStyleHit = "line"
  Nock.db.profile.practiceStyleLanes = "none"
  Nock.db.profile.practiceStyleAutoTick = "bar"
  Nock.db.profile.practiceStyleWindupScope = "all"
  View:ApplyDock()
  View:Refresh(st)
  local m2 = framesByKey()
  ok(m2[T.NoteKey(1, 1)] == fNext and m2[T.NoteKey(2, 1)] == fLater and m2[T.KEY.GRID + 1] == fAuto, "8: a style change keeps every frame on its key")
  ok(fLater.aTo == 1 and fLater.aFrom == 0.6 and fLater.fillA == 0.9 and fLater.edgeA == nil, "8: ...and repaints it solid, easing from dimmed to full rather than from zero")
  for _ = 1, 4 do tick(0.05) end
  ok(not fLater.fading and fLater:GetAlpha() == 1, "8: ...and it settles at full")
  ok(fNext.labelText == "NEXT" and not chip:IsShown(), "8: the word is back in the note and the chip is gone")
  ok(fAuto.tickW == 3 and (fAuto.colH or 0) > 0 and fAuto.column:IsShown(), "8: the auto tick is a bar and the wind-up reaches every row")
  ok(not View.hitCol:IsShown() and View.hitGlow[1]:IsShown() and not View.laneBg[2]:IsShown(), "8: line + glow, no lanes")
  -- Back to the shipped look.
  Nock.db.profile.practiceStyleNote, Nock.db.profile.practiceStyleNext, Nock.db.profile.practiceStyleHit = nil, nil, nil
  Nock.db.profile.practiceStyleLanes, Nock.db.profile.practiceStyleAutoTick, Nock.db.profile.practiceStyleWindupScope = nil, nil, nil
  View:ApplyDock()
  View:Refresh(st)
  ok(fLater.fillA == 0.28 and chip:IsShown(), "8: reset restores glass and the chip")
  -- The move-in ramp: a gradient item ahead of a weave note, its own height.
  plan.rows[1], plan.rows[2], plan.rows[3], plan.nRows = "auto", "s", "w", 3
  plan.n = plan.n + 1
  local wn = plan.notes[plan.n]
  wn.key, wn.row, wn.sym, wn.t0, wn.t1, wn.cycle, wn.idx = T.NoteKey(1, 2), "w", "w", NOW + 1.6, NOW + 1.7, 1, 2
  wn.state, wn.playable, wn.grade, wn.raptor = P.PENDING, true, nil, false
  live.weaveAt, live.weaveTtw, live.weaveFits, live.weaveMoveAt = NOW + 1.6, 0.3, true, NOW + 1.25
  live.paperSyms = { s = true, w = true }
  live.meleeReadyAt = NOW + 1.6
  plan.rev = plan.rev + 1
  View:Refresh(st)
  m = framesByKey()
  local fMove = m[T.KEY.MOVE]
  ok(fMove and fMove.ramp == true and fMove.barH == 18, "8: the move-in is a full-height ramp")
  -- The chip says MOVE once the step-in has opened for a weave that is next.
  plan.nextIdx, plan.nextKey, plan.nextSym = plan.n, wn.key, "w"
  plan.notes[1].state = P.HIT
  live.weaveMoveAt = NOW - 0.1
  plan.rev = plan.rev + 1
  View:Refresh(st)
  ok(chip.text:GetText() == "MOVE MB4" and View._chipFrame == framesByKey()[wn.key], "8: the chip reads MOVE + the weave key at the step-in (" .. tostring(chip.text:GetText()) .. ")")
  plan.notes[1].state = P.PENDING
  plan.n = plan.n - 1
  plan.rows[3], plan.nRows = nil, 2
  live.weaveAt, live.weaveTtw, live.weaveFits, live.weaveMoveAt = nil, nil, nil, nil
  live.paperSyms = { s = true }
  live.meleeReadyAt = nil
end

print(("practice_conveyor: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
