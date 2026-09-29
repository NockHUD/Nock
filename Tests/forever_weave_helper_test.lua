-- Tests/forever_weave_helper_test.lua
-- Forever/WeaveHelper.lua: events and the tick into the engine, flat fields
-- on state.weave, the ranged re-anchor, learned legs saved per character.
-- Run from the repo root: luajit Tests/forever_weave_helper_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

local now = 100
_G.GetTime = function() return now end
_G.IsPlayerMoving = function() return false end
_G.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
local Nock = {
  db = { profile = { weaveHelperEnabled = true, weaveLegSeed = 1.1 }, char = {} },
  Flavor = { forever = true, Plain = function(v) return v end },
  state = {
    target = { exists = true, alive = true, friendly = false, rangeState = "SWEET" },
    melee = { swingStart = 0, swingDuration = 2.0, swingRemaining = 0 },
    ranged = { swingStart = 0, swingDuration = 2.6, swingRemaining = 5, queueWindow = 0.4 },
    weave = { legProg = 0, legRemaining = 0, legStale = false, legIn = 0, legOut = 0, glide = 0 },
    cooldowns = {},
  },
}
local modules = {}
function Nock:NewModule(name) local m = { name = name, RegisterEvent = function() end }; modules[name] = m; return m end
function Nock:GetModule(name) return modules[name] end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/WeaveEngine.lua")
dofile("Forever/WeaveHelper.lua")
local H = modules.WeaveHelper
ok(H and H.refreshInterval == nil, "module WeaveHelper on the fast lane")
H:OnEnable()
local st = Nock.state
local w = st.weave

-- Idle, then an auto fires (Ranged PLAYER_SWING) with the melee swing ready: GO.
H:Refresh(st)
ok(w.stage == nil and near(w.glide, 0) and near(w.legIn, 1.1), "idle: no stage, seed published")
H:PLAYER_SWING("PLAYER_SWING", 2.6, 2)
st.melee.swingStart, st.melee.swingRemaining = 99, 0.4
H:Refresh(st)
ok(w.stage == "GO" and w.waitFor == nil, "Ranged swing = a shot: GO")

-- Movement events, the DEAD edge, the leg fields.
H:PLAYER_STARTED_MOVING()
st.target.rangeState = "CLOSE"; now = 100.2; H:Refresh(st)
ok(w.stage == "IN" and w.legKind == "in" and near(w.legRemaining, 1.1), "DEAD edge while moving: IN with the leg")
now = 100.75; H:Refresh(st)
ok(near(w.legProg, 0.55 / 1.1) and near(w.glide, 0.55 / 1.1), "glide runs on the leg")
H:PLAYER_STOPPED_MOVING(); now = 101.5; H:Refresh(st)
ok(near(w.glide, 0.55 / 1.1), "stopped: the glide holds")
H:PLAYER_STARTED_MOVING()

-- The melee hit: OUT, and the ranged swing re-anchored on the hit when no Ranged event follows.
now = 101.9; st.ranged.swingStart = 100
H:PLAYER_SWING("PLAYER_SWING", 2.0, 0)
H:Refresh(st)
ok(w.stage == "OUT" and w.legKind == "out", "MainHand swing: OUT")
ok(near(st.ranged.swingStart, 100), "inside the grace: the ranged swing is not touched yet")
now = 102.05; H:Refresh(st)
ok(near(st.ranged.swingStart, 101.9), "past the grace, no Ranged event: swingStart re-anchored on the hit")
now = 102.5; H:Refresh(st)
ok(near(st.ranged.swingStart, 101.9), "and not again")

-- Learned legs are saved per character on the edge that learned them.
st.target.rangeState = "SWEET"; now = 102.9; st.ranged.swingRemaining = 0.2; H:Refresh(st)
ok(w.stage == "RELEASE", "back in range inside the queue window: RELEASE")
ok(Nock.db.char.weaveLegs and near(Nock.db.char.weaveLegs.legOut, 1.0) and near(Nock.db.char.weaveLegs.legIn, 1.1),
   "the out leg (1.0 s) saved; the in leg (0.95 s moving of 1.7) rejected, record carries the seed")

-- The client resetting the swing itself: a Ranged event inside the grace is not a shot.
now = 104; st.target.rangeState = "MELEE"; H:Refresh(st)
H:PLAYER_SWING("PLAYER_SWING", 2.0, 0); st.ranged.swingStart = 104
H:PLAYER_SWING("PLAYER_SWING", 2.6, 2)
now = 104.3; H:Refresh(st)
ok(near(st.ranged.swingStart, 104) and H.st.clientResets == true, "client reset seen: nothing re-anchored")

-- Target change and leaving combat drop everything; the legs stay.
H:PLAYER_TARGET_CHANGED()
H:Refresh(st)
ok(w.stage == nil and w.legKind == nil and near(w.legOut, 1.0), "PLAYER_TARGET_CHANGED: idle, legs kept")
-- (SwingTimer writes ranged.swingStart on the same event; the fixture does it by hand)
now = 105; st.target.rangeState = "SWEET"; st.melee.swingRemaining = 0; H:Refresh(st)   -- back at range first
st.ranged.swingStart = 105; H:PLAYER_SWING("PLAYER_SWING", 2.6, 2); H:Refresh(st)
ok(w.stage == "GO", "a new GO on the next shot")
H:PLAYER_REGEN_ENABLED(); H:Refresh(st)
ok(w.stage == nil, "leaving combat: idle")

-- Disabled in the settings: the stage clears at once and nothing runs.
now = 106; st.ranged.swingStart = 106; H:PLAYER_SWING("PLAYER_SWING", 2.6, 2); H:Refresh(st)
ok(w.stage == "GO", "enabled: GO")
Nock.db.profile.weaveHelperEnabled = false
H:Refresh(st)
ok(w.stage == nil and w.legKind == nil, "disabled clears the stage")
ok(H.Enabled({}) == true and H.Enabled({ weaveHelperEnabled = false }) == false, "Enabled: unset = on")
Nock.db.profile.weaveHelperEnabled = true

-- ResetLegs: the seed again, the character record gone.
H:ResetLegs()
H:Refresh(st)
ok(Nock.db.char.weaveLegs == nil and near(w.legIn, 1.1) and near(w.legOut, 1.1), "ResetLegs: seed, record cleared")

-- The swing's age gates the cue: a shot 2 s ago offers nothing, moving or not.
H:PLAYER_TARGET_CHANGED(); now = 150; st.ranged.swingStart = 150; H:PLAYER_SWING("PLAYER_SWING", 2.6, 2); H:PLAYER_STARTED_MOVING()
now = 150.5; H:Refresh(st)
ok(w.stage == "GO", "fresh shot, moving: GO")
now = 152; H:Refresh(st)
ok(w.stage == nil, "the same swing 2 s old: no GO although still moving")
H:PLAYER_STOPPED_MOVING()

-- A dead or friendly target reads as no zone.
st.target.alive = false; H:PLAYER_SWING("PLAYER_SWING", 2.6, 2); H:Refresh(st)
ok(w.stage == nil, "dead target: idle")
st.target.alive = true

-- Spec §6 probe 3: the MainHand swing-range signal is counted, never used.
ok(H.mhRangeEvents == 0, "MainHand range events counted from zero")
H:PLAYER_SWING_RANGE_UPDATE("PLAYER_SWING_RANGE_UPDATE", 0, true, true)
ok(H.mhRangeEvents == 1, "a MainHand edge counts")
H:PLAYER_SWING_RANGE_UPDATE("PLAYER_SWING_RANGE_UPDATE", 2, true, true)
ok(H.mhRangeEvents == 1, "a Ranged edge does not")

-- Review fixes (2026-09-28). The seed slider moves every leg that is not
-- learned yet, at once; a learned leg keeps its measurement.
Nock.db.profile.weaveLegSeed = 1.5
H:ApplySeed(); H:Refresh(st)
ok(near(w.legIn, 1.5) and near(w.legOut, 1.5), "ApplySeed: both unlearned legs follow the slider")
H.st.legOut, H.st.learnedOut = 0.9, true
Nock.db.profile.weaveLegSeed = 2.0
H:ApplySeed(); H:Refresh(st)
ok(near(w.legIn, 2.0) and near(w.legOut, 0.9), "ApplySeed: a learned leg is left alone")
Nock.db.profile.weaveLegSeed = 1.1
H:ResetLegs()

-- Disabled: a hit landing while off must not re-anchor the swing once the
-- helper is switched back on.
Nock.db.profile.weaveHelperEnabled = false
now = 200; H:Refresh(st)
H:PLAYER_SWING("PLAYER_SWING", 2.0, 0); st.ranged.swingStart = 199
now = 200.5; H:Refresh(st)
Nock.db.profile.weaveHelperEnabled = true
now = 201; H:Refresh(st)
ok(near(st.ranged.swingStart, 199), "a hit while disabled never re-anchors after re-enable")

-- Raptor's cooldown (the ledger's remaining seconds) feeds the GO decision.
H:PLAYER_TARGET_CHANGED(); H:Refresh(st)
st.cooldowns.Raptor = { ready = false, remaining = 1.9, startTime = 100, duration = 6 }
now = 250; st.ranged.swingStart = 250; st.target.rangeState = "SWEET"; st.melee.swingRemaining = 0
H:PLAYER_SWING("PLAYER_SWING", 2.6, 2); H:Refresh(st)
ok(w.stage == "WAIT" and near(w.waitFor, 1.9 - 1.2), "Raptor 1.9 s out: WAIT for the cooldown")
st.cooldowns.Raptor.remaining, st.cooldowns.Raptor.ready = 0, true
now = 250.2; H:Refresh(st)
ok(w.stage == "GO", "Raptor ready: GO")
st.cooldowns.Raptor = nil

-- The helper's own sample ring says how the engine classed each event.
H:PLAYER_TARGET_CHANGED(); H:Refresh(st)
now = 300; H:PLAYER_SWING("PLAYER_SWING", 2.6, 2)
local S = H:Samples()
ok(#S >= 1 and S[#S].kind == "Ranged" and S[#S].shot == true and near(S[#S].t, 300), "Samples: the last Ranged event, classed as a shot")

-- Transition log: every stage change with the inputs the decision saw, for
-- `/nock probe weave` (a GO nobody can reproduce needs its evidence).
H:PLAYER_TARGET_CHANGED(); now = 400; st.target.rangeState = "SWEET"; st.ranged.swingStart = 400
st.cooldowns.Raptor = { ready = false, remaining = 1.5, startTime = 395, duration = 6 }
H:Refresh(st)
H:PLAYER_SWING("PLAYER_SWING", 2.6, 2); now = 400.1; H:Refresh(st)
local T = H:Transitions()
local last = T[#T]
ok(last and last.to == "WAIT" and last.from == nil and near(last.t, 400.1) and last.zone == "SWEET"
   and near(last.raptor, 1.5) and near(last.melee, 0) and near(last.age, 0.1) and last.moving == false,
   "a transition records stage from/to, zone, Raptor and melee readiness, swing age and movement")
st.cooldowns.Raptor.remaining = 0.2; now = 400.4; H:Refresh(st)
ok(H:Transitions()[#H:Transitions()].to == "GO", "WAIT -> GO logged")
st.cooldowns.Raptor = nil

-- The start window follows the profile (weaveStartWindow) on enable, on
-- ApplyWindow (the slider) and across a ResetLegs.
Nock.db.profile.weaveStartWindow = 1.2
H:ApplyWindow()
ok(near(H.st.goWindow, 1.2), "ApplyWindow reads the profile")
H:ResetLegs()
ok(near(H.st.goWindow, 1.2), "ResetLegs keeps the window")
Nock.db.profile.weaveStartWindow = nil
H:ApplyWindow()
ok(near(H.st.goWindow, 0.75), "unset: the default 0.75")

-- The facing reaches the engine: a 180 while running in flips the leg.
local facingNow = 0
_G.GetPlayerFacing = function() return facingNow end
H:ResetLegs()
st.target.rangeState = "SWEET"; st.ranged.swingStart = 0; st.melee.swingStart = 0
H:PLAYER_STOPPED_MOVING(); now = 200; H:Refresh(st)
H:PLAYER_STARTED_MOVING(); st.target.rangeState = "CLOSE"; now = 201; H:Refresh(st)
ok(w.stage == "IN" and w.legKind == "in", "running in on facing 0")
now = 201.5; H:Refresh(st)
facingNow = math.pi; H:Refresh(st)
ok(w.stage == "OUT" and w.legKind == "out" and near(w.glide, 0.5 / 1.1), "turned round: the helper hands the facing on, the leg flips")
now = 202.6; H:Refresh(st)
ok(near(w.glide, 0), "and the glide is back at the ranged end")
_G.GetPlayerFacing = nil
H:ResetLegs(); H:PLAYER_STOPPED_MOVING()

print(("forever_weave_helper: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
