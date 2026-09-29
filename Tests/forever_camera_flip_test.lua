-- Tests/forever_camera_flip_test.lua
-- Forever/CameraFlip.lua: FacingDelta wraps and signs correctly, and
-- CameraReport renders API presence, trials with the degrees turned and the
-- blocked calls that landed inside a trial's window. Pure.
-- Run from the repo root: luajit Tests/forever_camera_flip_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end

_G.GetTime = function() return 500 end
local Nock = { Flavor = { forever = true, toc = 16001, Plain = function(v) return v end }, API = { Missing = function() return {} end }, UI = {} }
local module
function Nock:NewModule(name) module = { name = name, events = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  return module end
function Nock:GetModule() return nil end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/CameraFlip.lua")
local P = Nock.CameraFlip
P:OnEnable()

ok(module.events.ADDON_ACTION_BLOCKED == "OnBlocked" and module.events.ADDON_ACTION_FORBIDDEN == "OnBlocked", "blocked events registered")

-- FacingDelta: radians in, signed degrees out, shortest way round.
ok(near(P.FacingDelta(0, math.pi), 180), "half turn = 180")
ok(near(P.FacingDelta(0.1, 0.1 - math.pi / 2), -90), "quarter turn right = -90")
ok(near(P.FacingDelta(6.2, 0.1), (0.1 - 6.2 + 2 * math.pi) * 180 / math.pi), "wrap across 2pi stays small")
ok(P.FacingDelta(nil, 1) == nil and P.FacingDelta(1, "x") == nil, "nil for a missing facing")

local text = P.CameraReport({
  apis = { { "SetView", true }, { "FlipCameraYaw", false } },
  cvars = { { "cameraViewBlendStyle", "1" } },
  restrictions = { { "Combat", "Active" } },
  facing = 1.5, moving = true, mouselooking = false, combat = true, flipped = true, armed = false, delay = 0.1,
  trials = {
    { t = 10.0, kind = "view", combat = true, f0 = 0, f1 = math.pi, f2 = math.pi, t1 = 10.016, t2 = 10.033,
      ml0 = false, ml1 = true, ml2 = false, errs = {} },
    { t = 20.0, kind = "face", combat = false, f0 = math.pi, f1 = nil, f2 = nil, errs = { "SetView: boom" } },
  },
  blocked = { { t = 10.02, ev = "ADDON_ACTION_BLOCKED", who = "Nock", fn = "MouselookStart()" }, { t = 15, ev = "ADDON_ACTION_FORBIDDEN", who = "Nock", fn = "Other()" } },
})
ok(text:find("apis: SetView  FlipCameraYaw=MISSING", 1, true), "api presence line")
ok(text:find("cameraViewBlendStyle=1", 1, true), "cvar line")
ok(text:find("Combat=Active", 1, true), "restriction line")
ok(text:find("flipped: true  armed: false  delay: 0.1  back: 0", 1, true), "latch line")
ok(type(_G.NockCamFlip) == "function" and type(_G.NockCamFace) == "function", "macro globals exported")
ok(text:find("steps 180.0 0.0  turned 180.0  ms 16 33  ml false true false  zoom ? ? ?", 1, true), "trial steps, total, frame times, mouselook flags, zoom")
ok(text:find("blocked MouselookStart()", 1, true), "blocked call inside the trial window listed on the trial")
ok(not text:find("blocked MouselookStart(),Other", 1, true), "a blocked call outside the window is not on the trial")
ok(text:find("steps ? ?  turned ?  ms ? ?", 1, true) and text:find("errs SetView: boom  blocked none", 1, true), "trial without a facing shows ? and its error")
ok(text:find("15.00  ADDON_ACTION_FORBIDDEN  Nock  Other()", 1, true), "blocked ring listed in full")

-- Setup assistant: distance from baseline + 180, and the frame's text per step.
local off, good = P.CameraSetupCheck(0, math.pi)
ok(near(off, 0) and good, "exactly opposite = sweet")
off, good = P.CameraSetupCheck(0, math.pi + math.rad(1.5))
ok(near(off, 1.5) and good, "1.5 deg past is inside the tolerance")
off, good = P.CameraSetupCheck(0, math.pi - math.rad(5))
ok(near(off, -5) and not good, "5 deg short is outside and signed")
off, good = P.CameraSetupCheck(6.0, 6.0 + math.pi - 2 * math.pi)
ok(near(off, 0) and good, "wraps across 2pi")
off, good = P.CameraSetupCheck(1, 1)
ok(near(off, -180) or near(off, 180), "same facing is 180 off")
ok(select(2, P.CameraSetupCheck(nil, 1)) == false, "no baseline is never sweet")

-- Enable and gate: off unless set, raid by default, the range cues' ladder.
ok(P.Enabled({ cameraFlipEnabled = true }) and not P.Enabled({}) and not P.Enabled(nil), "enabled only when set")
ok(not P.Allowed({ cameraFlipEnabled = false, cameraFlipGate = "solo" }, "raid"), "off never allows")
local function stubCues(t) Nock.GetModule = function(_, name) if name == "RangeCues" then return t end end end
stubCues({ GateAllows = function(gate, ctx) return gate == "solo" or (gate == "party" and ctx ~= "solo") or ctx == "raid" end })
ok(P.Allowed({ cameraFlipEnabled = true }, "raid") and not P.Allowed({ cameraFlipEnabled = true }, "party"), "default gate is raid")
ok(P.Allowed({ cameraFlipEnabled = true, cameraFlipGate = "solo" }, "solo"), "solo gate allows everywhere")
ok(P.Allowed({ cameraFlipEnabled = true, cameraFlipGate = "party" }, "party") and not P.Allowed({ cameraFlipEnabled = true, cameraFlipGate = "party" }, "solo"), "party gate")
stubCues(nil)
ok(P.Allowed({ cameraFlipEnabled = true, cameraFlipGate = "solo" }, "raid") and not P.Allowed({ cameraFlipEnabled = true }, "raid"), "without the cues module only solo passes")

-- The automatic return (user 2026-09-29): due on the first false -> true
-- edge of the settled shoot probe after a turn away, switch on by default.
local A = { armed = false }
local on = { cameraFlipEnabled = true }
ok(not P.AutoFaceStep(A, on, false, true, false), "no turn outstanding: nothing")
ok(not P.AutoFaceStep(A, on, true, true, false), "turned away with the probe still true: not yet (no edge)")
ok(not P.AutoFaceStep(A, on, true, false, true) and A.armed, "probe false: armed")
ok(not P.AutoFaceStep(A, on, true, nil, true), "probe unknown: waits")
-- A turn under a held W runs the character back in: wait for the stop.
ok(not P.AutoFaceStep(A, on, true, true, true) and A.armed, "probe true but still running: holds, stays armed")
ok(not P.AutoFaceStep(A, on, true, true, nil) and A.armed, "movement unknown: holds")
ok(P.AutoFaceStep(A, on, true, true, false) and not A.armed, "stopped in range: the return is due once")
ok(not P.AutoFaceStep(A, on, true, true, false), "and not again")
P.AutoFaceStep(A, on, true, false, true)
ok(not P.AutoFaceStep(A, { cameraFlipEnabled = true, cameraFlipAutoFace = false }, true, true, false), "switch off: never")
ok(not P.AutoFaceStep(A, nil, true, true, false), "no profile: never")
P.AutoFaceStep(A, on, false, false, false)
ok(not A.armed, "the arm clears when the turn is over")

-- Through Refresh: the tick hands state.target.ladderShoot in; the return
-- runs the turn once and clears the latch.
local turns = {}
P.CameraTurn = function(self, back) turns[#turns + 1] = back end
Nock.db = { profile = { cameraFlipEnabled = true } }
P._cameraFlipped = true
local movingNow = true
_G.IsPlayerMoving = function() return movingNow end
local state = { target = { ladderShoot = false } }
P:Refresh(state)
state.target.ladderShoot = true
P:Refresh(state)
ok(#turns == 0 and P._cameraFlipped == true, "Refresh: back in range but still running: no return yet")
movingNow = false
P:Refresh(state)
ok(#turns == 1 and turns[1] == true and P._cameraFlipped == false, "Refresh: stopped in range after a turn away, one return")
P:Refresh(state)
ok(#turns == 1, "no second return")
P:Refresh(nil)
ok(#turns == 1, "a tick without state is harmless")
Nock.db = nil

-- The armed turn fires on Raptor's own success or a MainHand hit, inside a
-- window of one melee swing plus slack (a stale white swing landing on
-- arrival used to strand the turn past the fixed 1.5 s).
ok(near(P.ArmWindow(1.6), 2.1) and near(P.ArmWindow(0.5), 1.5) and near(P.ArmWindow(nil), 1.5) and near(P.ArmWindow(0), 1.5), "arm window = swing + 0.5, floor 1.5")
ok(P.CastFires("player", "Raptor Strike", "Raptor Strike") and not P.CastFires("target", "Raptor Strike", "Raptor Strike")
   and not P.CastFires("player", "Auto Shot", "Raptor Strike") and not P.CastFires("player", nil, "Raptor Strike"), "fires on the player's Raptor by name only")
-- Through the handler: a rank other than rank 1 carries the same name.
Nock.Spells = { RAPTOR_STRIKE = 2973 }
Nock.API = { SpellName = function(id) return (id == 2973 or id == 14260) and "Raptor Strike" or "Other" end }
Nock.state = { melee = { swingDuration = 1.6 } }
_G.UnitCanAttack = function() return true end
Nock.db = { profile = { cameraFlipEnabled = true, cameraFlipGate = "solo" } }
turns = {}
P._cameraFlipped, P._cameraNext = false, 0
P:CamFlipRequest()
ok(P._cameraArm and near(P._cameraArm - 500, 2.1), "armed for swing + slack")
ok(module.events.UNIT_SPELLCAST_SUCCEEDED == "OnCameraCast" and module.events.PLAYER_SWING == "OnCameraSwing", "listens for the cast and the swing")
P:OnCameraCast("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 14260)
ok(#turns == 1 and turns[1] == false and P._cameraArm == nil, "Raptor rank 2 success fires the turn away")
P._cameraFlipped = false
P:CamFlipRequest()
P:OnCameraCast("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 75)
ok(#turns == 1 and P._cameraArm ~= nil, "another spell leaves the arm alone")
_G.GetTime = function() return 503 end
P:OnCameraCast("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2973)
ok(#turns == 1 and P._cameraArm == nil, "past the window: expired, no turn")
_G.GetTime = function() return 500 end
Nock.db = nil

print(("forever_camera_flip: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
