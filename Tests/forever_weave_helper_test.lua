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
_G.IsKeyDown = nil                      -- no key API: moving reads as forward (the fallback)
_G.GetBindingKey = function() return nil end
_G.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
local Nock = {
  db = { profile = { weaveHelperEnabled = true, weaveLegSeed = 1.1 }, char = {} },
  Flavor = { forever = true, Plain = function(v) return v end },
  state = {
    target = { exists = true, alive = true, friendly = false, rangeState = "SWEET", ladderRest = nil },
    melee = { swingStart = 0, swingDuration = 2.0, swingRemaining = 0 },
    ranged = { swingStart = 0, swingDuration = 2.6, swingRemaining = 5, queueWindow = 0.4 },
    weave = { legProg = 0, legRemaining = 0, legStale = false, legIn = 0, legOut = 0, glide = 0, radial = 0, face = 1, overshot = false },
    cooldowns = {},
  },
}
local modules = {}
local sent = {}
function Nock:NewModule(name) local m = { name = name, RegisterEvent = function() end, SendMessage = function(_, msg, ...) sent[#sent + 1] = { msg, ... } end }; modules[name] = m; return m end
function Nock:GetModule(name) return modules[name] end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/WeaveEngine.lua")
-- The cases up to the intent block predate the rest band: with the shoot
-- edge at 0 the old geometry (DEAD edge = 0, melee = 1) holds.
Nock.WeaveEngine.SHOOT_FRAC = 0
Nock.WeaveEngine.EDGE_GAP = 0
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
-- the way out is backpedalled: S down (a bound backward key)
_G.GetBindingKey = function(action) if action == "MOVEBACKWARD" then return "S" end end
_G.IsKeyDown = function(key) return key == "S" end
H:RebuildKeys()
H:Refresh(st)
ok(w.stage == "OUT" and w.legKind == "out", "MainHand swing: OUT")
local TT = H:Transitions()
ok(TT[#TT].from == "IN" and TT[#TT].to == "OUT" and near(TT[#TT].t, 101.9), "the hit's own stage change is logged from the event")
ok(sent[#sent][1] == "NOCK_WEAVE_STAGE" and sent[#sent][2] == "OUT" and sent[#sent][3] == "IN", "and announced")
ok(near(st.ranged.swingStart, 100), "inside the grace: the ranged swing is not touched yet")
now = 102.05; H:Refresh(st)
ok(near(st.ranged.swingStart, 101.9), "past the grace, no Ranged event: swingStart re-anchored on the hit")
now = 102.5; H:Refresh(st)
ok(near(st.ranged.swingStart, 101.9), "and not again")

-- Learned legs are saved per character on the edge that learned them.
st.target.rangeState = "SWEET"; now = 102.9; st.ranged.swingRemaining = 0.2; H:Refresh(st)
ok(w.stage == "RELEASE", "back in range inside the queue window: RELEASE")
ok(Nock.db.char.weaveLegs and near(Nock.db.char.weaveLegs.legOutBack, 1.0) and near(Nock.db.char.weaveLegs.legIn, 1.1),
   "the backpedal out leg (1.0 s) saved; the in leg (0.95 s moving of 1.7) rejected, record carries the seed")

-- The client resetting the swing itself: a Ranged event inside the grace is not a shot.
now = 104; st.target.rangeState = "MELEE"; H:Refresh(st)
H:PLAYER_SWING("PLAYER_SWING", 2.0, 0); st.ranged.swingStart = 104
H:PLAYER_SWING("PLAYER_SWING", 2.6, 2)
now = 104.3; H:Refresh(st)
ok(near(st.ranged.swingStart, 104) and H.st.clientResets == true, "client reset seen: nothing re-anchored")

_G.GetBindingKey = function() return nil end; _G.IsKeyDown = nil; H:RebuildKeys()

-- Target change and leaving combat drop everything; the legs stay.
H:PLAYER_TARGET_CHANGED(); H:PLAYER_STOPPED_MOVING()
H:Refresh(st)
ok(w.stage == nil and w.legKind == nil and near(w.legOutBack, 1.0), "PLAYER_TARGET_CHANGED: idle, legs kept")
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
ok(w.stage == "IN", "fresh shot, moving toward: the run-in")
now = 152; H:Refresh(st)
ok(w.stage == nil, "the same swing 2 s old and range never left: over although still moving")
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

-- The facing reaches the engine: after a shot anchored it, a 180 turns
-- forward into away; the words follow, the leg keeps its kind.
local facingNow = 0
_G.GetPlayerFacing = function() return facingNow end
H:ResetLegs()
st.target.rangeState = "SWEET"; st.ranged.swingStart = 0; st.melee.swingStart = 0
H:PLAYER_STOPPED_MOVING(); now = 200; H:Refresh(st)
st.ranged.swingStart = 200; H:PLAYER_SWING("PLAYER_SWING", 2.6, 2)
ok(near(H.st.anchor, 0), "a shot anchors the facing")
H:PLAYER_STARTED_MOVING(); st.target.rangeState = "CLOSE"; now = 201; H:Refresh(st)
ok(w.stage == "IN" and w.legKind == "in" and w.face == 1, "running in on facing 0")
now = 201.5; H:Refresh(st)
facingNow = math.pi; H:Refresh(st)
ok(w.stage == "OUT" and w.legKind == "in" and w.face == -1 and near(w.glide, 0.5 / 1.1), "turned round: forward is now away, BACK OUT, the leg keeps its kind")
now = 202.6; H:Refresh(st)
ok(near(w.glide, 0), "and the glide is back at the shoot edge")
_G.GetPlayerFacing = nil
H:ResetLegs(); H:PLAYER_STOPPED_MOVING()

-- Every stage change is announced (the cue sounds ride on it), nothing else is.
local n0 = #sent
H:ResetLegs(); H:PLAYER_STOPPED_MOVING()
st.target.rangeState = "SWEET"; st.ranged.swingStart = 0; st.melee.swingStart = 0; now = 300; H:Refresh(st)
H:PLAYER_STARTED_MOVING(); st.target.rangeState = "CLOSE"; now = 301; H:Refresh(st)
ok(#sent == n0 + 1 and sent[#sent][1] == "NOCK_WEAVE_STAGE" and sent[#sent][2] == "IN" and sent[#sent][3] == nil, "IN announced with the previous stage")
now = 301.2; H:Refresh(st)
ok(#sent == n0 + 1, "no change, no message")
st.target.rangeState = "MELEE"; now = 302.2; H:Refresh(st)
ok(sent[#sent][2] == "STRIKE" and sent[#sent][3] == "IN", "STRIKE announced")

-- ---------------------------------------------------------------------------
-- Intent from the keys (2026-09-29 addendum).
-- ---------------------------------------------------------------------------
local R = H.Radial
local function lat(k, moving) local _, l = R(k, moving); return l end
ok(R({ fwd = true }, true) == 1 and R({ back = true }, true) == -1, "W = 1, S = -1")
ok(R({ fwd = true, back = true }, true) == 0, "W+S = 0 although the client says moving")
ok(lat({ strafeR = true }, true) == 1 and lat({ strafeL = true }, true) == -1, "strafe keys: sideways right 1, left -1")
ok(lat({ turnR = true, rmb = true }, true) == 1 and lat({ turnL = true, rmb = true }, true) == -1, "a turn key under the right button: a strafe")
ok(R({ turnR = true, rmb = true }, true) == 0, "and no forward share")
ok(R({ turnR = true }, false) == 0 and lat({ turnR = true }, true) == 0, "a turn alone: nothing")
ok(R({ lmb = true, rmb = true }, true) == 1 and R({ steer = true }, true) == 1, "both mouse buttons, or move-and-steer: forward")
local a, l = R({ fwd = true, strafeR = true }, true)
ok(near(a, 0.707) and near(l, 0.707), "diagonal: both shares scaled")
a, l = R({ back = true, turnL = true, rmb = true }, true)
ok(near(a, -0.707) and near(l, -0.707), "S + RMB+A: back-left diagonal")
ok(R({}, true) == 1 and R({}, false) == 0, "moving with no key down = autorun forward; standing = 0")
ok(R({ turnR = true }, true) == 0, "moving with only a turn key (mouse steering) is not autorun")
ok(R({ fwd = true }, false) == 0 and R({ back = true }, false) == 0, "a key held while not moving (rooted, typing in chat): 0")

-- Reading the keys: the bound keys per action, the mouse buttons, nil-safe.
local down = {}
_G.IsKeyDown = function(k) return down[k] == true end
_G.GetBindingKey = function(action)
  if action == "MOVEFORWARD" then return "W", "UP" end
  if action == "MOVEBACKWARD" then return "S" end
  if action == "TURNLEFT" then return "A" end
  if action == "TURNRIGHT" then return "D" end
  if action == "STRAFERIGHT" then return "E" end
  return nil
end
H:RebuildKeys()
local k = {}
down.UP = true
H:ReadKeys(k)
ok(k.fwd == true and k.back == false and k.turnL == false and k.lmb == false, "UP (second forward key) reads as forward")
down.UP, down.A, down.RightButton = nil, true, true
H:ReadKeys(k)
ok(k.fwd == false and k.turnL == true and k.rmb == true and H.Radial(k, true) == 0 and lat(k, true) == -1, "A under the right button: a strafe left")
down.A, down.RightButton, down.D = nil, true, true
H:ReadKeys(k)
ok(k.turnR == true and lat(k, true) == 1, "D under the right button: a strafe right")
down.D, down.RightButton, down.E = nil, nil, true
H:ReadKeys(k)
ok(k.strafeR == true and lat(k, true) == 1, "a strafe key: sideways right")
down.E = nil
_G.IsKeyDown = nil
H:ReadKeys(k)
ok(k.fwd == false and k.turnL == false and k.rmb == false and H.Radial(k, true) == 1, "no IsKeyDown: moving reads as forward")
_G.IsKeyDown = function(key) if key == "UP" then error("boom") end return down[key] == true end
down.W = true
H:ReadKeys(k)
ok(k.fwd == true, "a key the client throws on reads as up, the rest still read")
down.W = nil
_G.GetBindingKey = function(action) if action == "MOVEFORWARD" then return "SHIFT-W" end end
H:RebuildKeys()
down.W = true
H:ReadKeys(k)
ok(k.fwd == true, "a chord binding reads its base key")
down.W = nil
_G.GetBindingKey = function(action)
  if action == "MOVEFORWARD" then return "W", "UP" end
  if action == "MOVEBACKWARD" then return "S" end
  if action == "TURNLEFT" then return "A" end
  if action == "TURNRIGHT" then return "D" end
  return nil
end
H:RebuildKeys()
_G.IsKeyDown = function(k) return down[k] == true end

-- The tick hands the engine the radial, the facing and the rest band; Publish carries them.
Nock.WeaveEngine.SHOOT_FRAC = 0.55; H:ResetLegs()   -- the real geometry from here
H:PLAYER_TARGET_CHANGED(); H:PLAYER_STOPPED_MOVING(); Nock.db.profile.weaveHelperEnabled = true
_G.GetPlayerFacing = function() return 1.5 end
now = 500; st.target.rangeState = "SWEET"; st.target.ladderRest = true; st.ranged.swingStart = 500; st.melee.swingRemaining = 0
H:Refresh(st)   -- at range first: a Ranged swing from an unknown zone is a shot, from MELEE it is a reset
H:PLAYER_SWING("PLAYER_SWING", 2.6, 2)
ok(near(H.st.anchor, 1.5), "a shot anchors the facing")
H:Refresh(st)
ok(w.stage == "GO", "GO")
down.W = true; down.A, down.RightButton = nil, nil; H:PLAYER_STARTED_MOVING()
now = 500.2; H:Refresh(st)
ok(w.stage == "IN" and w.radial == 1 and w.lateral == 0 and w.face == 1 and w.legKind == "in", "W under GO: IN, radial, lateral and face published")
now = 500.4; H:Refresh(st)
ok(near(w.glide, 0.4 / w.legIn), "the glide ran 0.4 s of intent (the first slice counts from the tick before the key)")
down.W, down.S = true, true
now = 500.8; H:Refresh(st)
ok(near(w.glide, 0.4 / w.legIn), "W+S: frozen")
down.W, down.S = nil, nil; H:PLAYER_STOPPED_MOVING()
st.target.ladderRest = false
now = 501.0; H:Refresh(st)
ok(w.overshot == false and near(w.glide, 0), "leaving the band while standing: pos 0, no overshoot")
st.target.ladderRest = true; _G.GetPlayerFacing = nil

-- Legs are saved as a v2 record with the fraction; an old record is ignored.
H.st.legIn, H.st.legOut, H.st.legOutBack, H.st.shootFrac = 0.9, 1.2, 1.9, 0.5
H.st.learnedIn, H.st.learnedOut, H.st.learnedOutBack, H.st.learnedFrac = true, true, true, true
H:SaveLegs()
local rec = Nock.db.char.weaveLegs
ok(rec.v == 2 and near(rec.legIn, 0.9) and near(rec.legOut, 1.2) and near(rec.legOutBack, 1.9) and near(rec.shootFrac, 0.5), "SaveLegs: v2 record with the fraction and the backpedal leg")
H:OnEnable()
ok(near(H.st.legIn, 0.9) and near(H.st.legOutBack, 1.9) and H.st.learnedOutBack == true and near(H.st.shootFrac, 0.5) and H.st.learnedFrac == true, "OnEnable reads a v2 record")
Nock.db.char.weaveLegs.legOutBack = nil
H:OnEnable()
ok(near(H.st.legOutBack, 1.2) and H.st.learnedOutBack == false, "a v2 record without the backpedal leg: seeded from the out leg")
Nock.db.char.weaveLegs = { legIn = 0.6, legOut = 0.6 }
H:OnEnable()
ok(H.st.learnedIn == false and near(H.st.legIn, 1.1) and H.st.learnedFrac == false, "old record ignored: seed")

print(("forever_weave_helper: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
