-- Tests/forever_range_cues_test.lua
-- Forever/RangeCues.lua: spoken range cues on zone changes, settled, each
-- with its own switch and sound under one master switch.
-- Run from the repo root: luajit Tests/forever_range_cues_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local now = 100
_G.GetTime = function() return now end
local played = {}
_G.PlaySoundFile = function(path, channel) played[#played + 1] = { path, channel } end
local Nock = { db = { profile = {
  soundCuesEnabled = true,
  cueDeadZoneEnabled = true, cueDeadZoneSound = "Nock Dead Zone",
  cueMeleeEnabled = false, cueMeleeSound = "Nock Melee",
  cueInRangeEnabled = false, cueInRangeSound = "Nock In Range",
  cueOutOfRangeEnabled = false, cueOutOfRangeSound = "Nock Out of Range",
} } }
local module
function Nock:NewModule(name) module = { name = name }; return module end
_G.LibStub = function(lib, silent)
  if lib == "LibSharedMedia-3.0" then return { Fetch = function(_, kind, name) return "path:" .. name end } end
  return { GetAddon = function() return Nock end }
end
dofile("Forever/RangeCues.lua")
local R = module
local p = Nock.db.profile
ok(R and R.name == "RangeCues" and R.refreshInterval == nil, "module RangeCues on the fast lane (every frame)")

-- Pick: pure.
local P = R.Pick
ok(P("SWEET", "CLOSE", p) == R.CUES.CLOSE, "walking into the dead zone: the dead-zone cue (on by default)")
ok(P("SWEET", "MELEE", p) == nil, "melee cue off by default")
p.cueMeleeEnabled = true
ok(P("SWEET", "MELEE", p) == R.CUES.MELEE, "melee cue when switched on")
ok(P(nil, "SWEET", p) == nil, "a target appearing is not a range change")
ok(P("SWEET", nil, p) == nil, "losing the target is silent")
ok(P("CLOSE", "CLOSE", p) == nil, "no change, no cue")
p.cueDeadZoneSound = "None"
ok(P("SWEET", "CLOSE", p) == nil, "a cue set to None is silent")
p.cueDeadZoneSound = "Nock Dead Zone"
p.soundCuesEnabled = false
ok(P("SWEET", "CLOSE", p) == nil, "master switch off: silent")
p.soundCuesEnabled = true

-- Refresh: settle, then play through LSM on the dead-zone channel.
R:OnEnable()
local st = { target = { rangeState = "SWEET" } }
R:Refresh(st); now = 100.2; R:Refresh(st)
ok(#played == 0, "the first settled zone plays nothing")
st.target.rangeState = "CLOSE"
now = 100.3; R:Refresh(st)
ok(#played == 0, "a fresh candidate waits for the settle")
now = 100.35; R:Refresh(st)
ok(#played == 0, "50 ms in: still waiting")
now = 100.4; R:Refresh(st)
ok(#played == 1 and played[1][1] == "path:Nock Dead Zone" and played[1][2] == "Master", "settled: the dead-zone clip on Master")
now = 100.6; R:Refresh(st)
ok(#played == 1, "holding the zone plays nothing more")
-- a flicker shorter than the settle is ignored
st.target.rangeState = "SWEET"; now = 100.7; R:Refresh(st)
st.target.rangeState = "CLOSE"; now = 100.74; R:Refresh(st)
now = 101; R:Refresh(st)
ok(#played == 1, "a flicker out and back within the settle is silent")
-- melee, on, through the configured channel
p.deadZoneSoundChannel = "SFX"
st.target.rangeState = "MELEE"; now = 102; R:Refresh(st); now = 102.2; R:Refresh(st)
ok(#played == 2 and played[2][1] == "path:Nock Melee" and played[2][2] == "SFX", "melee cue on the chosen channel")
-- Quiet guards: no two cues within 1.5 s, the same zone not within the
-- repeat quiet time (4 s by default, cueRepeatSeconds).
local Q = R.Quiet
ok(Q("CLOSE", 10, 9.0, {}, 4) == true, "1.0 s after any cue: quiet")
ok(Q("CLOSE", 10, 8.0, {}, 4) == false, "2.0 s after another cue: free")
ok(Q("CLOSE", 10, 0, { CLOSE = 7 }, 4) == true, "the same zone 3 s ago: quiet")
ok(Q("CLOSE", 10, 0, { CLOSE = 5 }, 4) == false, "the same zone 5 s ago: free")
ok(Q("MELEE", 10, 0, { CLOSE = 9 }, 4) == false, "a different zone is not held by the dead zone's repeat")
-- live: dancing on the dead-zone edge every second speaks once
p.cueInRangeEnabled = true
st.target.rangeState = "CLOSE"; now = 110; R:Refresh(st); now = 110.2; R:Refresh(st)
ok(#played == 3 and played[3][1] == "path:Nock Dead Zone", "into the dead zone: cue")
st.target.rangeState = "SWEET"; now = 111; R:Refresh(st); now = 111.2; R:Refresh(st)
ok(#played == 3, "back out 1 s later: the any-cue gap holds (1.5 s)")
st.target.rangeState = "CLOSE"; now = 112; R:Refresh(st); now = 112.2; R:Refresh(st)
ok(#played == 3, "in again 2 s later: the dead zone's own repeat gap holds (4 s)")
st.target.rangeState = "SWEET"; now = 113; R:Refresh(st); now = 113.2; R:Refresh(st)
ok(#played == 4 and played[4][1] == "path:Nock In Range", "out again 3 s after the last cue: in-range speaks (its own zone is fresh)")
st.target.rangeState = "CLOSE"; now = 115; R:Refresh(st); now = 115.2; R:Refresh(st)
ok(#played == 5, "dead zone again 5 s after its last: speaks")
p.cueInRangeEnabled = false

-- target lost, then a new target in range: silent both times
st.target.rangeState = nil; now = 103; R:Refresh(st); now = 103.2; R:Refresh(st)
st.target.rangeState = "SWEET"; now = 104; R:Refresh(st); now = 104.2; R:Refresh(st)
ok(#played == 5, "target loss and a new target are silent")

print(("forever_range_cues: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
