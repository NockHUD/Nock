-- Tests/forever_mirror_timers_test.lua
-- Forever/MirrorTimers.lua: the breath / fatigue / Feign Death timers
-- (MIRROR_TIMER_*) published as a cast-bar record, and the cast bar's source
-- pick (a real cast wins, the timer only behind the toggle).
-- Run from the repo root: luajit Tests/forever_mirror_timers_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local now = 100
_G.GetTime = function() return now end
local progress = {}                  -- [timer] = value in ms
local info = {}                      -- [index] = { timer, value, max, scale, paused, label }
_G.GetMirrorTimerProgress = function(t) return progress[t] or 0 end
_G.GetMirrorTimerInfo = function(i) local r = info[i]; if not r then return "UNKNOWN", 0, 0, 0, 0, "" end; return unpack(r) end
_G.MIRRORTIMER_NUMTIMERS = 3

local Nock = { Flavor = { forever = true, Plain = function(v) return v end }, db = { profile = {} },
               state = { player = {} }, UI = {} }
local hidden
function Nock.UI.SetBlizzardMirrorTimersHidden(h) hidden = h; return true end
local module
function Nock:NewModule(name)
  module = { name = name, events = {}, msgs = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function module:RegisterMessage(m, h) self.msgs[m] = h or m end
  return module
end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/MirrorTimers.lua")
local MT = Nock.MirrorTimers
ok(MT and module.name == "MirrorTimers", "module MirrorTimers registered as Nock.MirrorTimers")
local function fire(ev, ...) local h = module.events[ev]; module[type(h) == "string" and h or ev](module, ev, ...) end

-- Record: the fill is value / max; the time is what is left at the rate.
do
  local r = {}
  MT.Record(r, "BREATH", 30000, 60000, -1, 100)
  ok(r.isChannel == true and r.endTime == 130 and r.startTime == 70, "draining breath: 30 s left of 60")
  ok(r.mirror == "BREATH" and type(r.color) == "table" and r.name == "Breath", "breath: its kind, colour and name")
  MT.Record(r, "EXHAUSTION", 10000, 60000, -1, 100)
  ok(r.name == "Fatigue", "exhaustion reads as Fatigue")
  MT.Record(r, "BREATH", 30000, 60000, 0, 100)
  ok(r.endTime == 130 and r.startTime == 70, "paused (scale 0): frozen at the same fill")
  MT.Record(r, "BREATH", 30000, 60000, 10, 100)
  ok(math.abs(r.endTime - 103) < 1e-9 and math.abs((r.endTime - r.startTime) - 6) < 1e-9, "refilling breath: the fill follows value / max at its rate")
end

-- Source: a real cast always wins; the timer only with the toggle on.
do
  local cast, mirror = { name = "Steady Shot" }, { name = "Breath" }
  ok(MT.Source({}, cast, mirror) == cast, "a cast wins")
  ok(MT.Source({}, nil, mirror) == nil, "toggle off: no timer on the bar")
  ok(MT.Source({ reactCastMirrorTimers = true }, nil, mirror) == mirror, "toggle on, no cast: the timer")
  ok(MT.Source({ reactCastMirrorTimers = true }, cast, mirror) == cast, "toggle on, casting: the cast")
end

-- Events: START publishes, the tick follows the client's progress, STOP clears.
do
  local p = Nock.db.profile
  module:OnEnable()
  ok(Nock.state.player.mirrorTimer == nil and hidden == false, "nothing running; Blizzard's bars kept (toggle off)")
  progress.BREATH = 60000
  fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0, "Breath")
  local r = Nock.state.player.mirrorTimer
  ok(r and r.mirror == "BREATH" and r.endTime == 160, "START publishes the timer (producer: toggle off too)")
  now = 110; progress.BREATH = 50000
  module:Refresh(Nock.state)
  ok(r.endTime == 160 and Nock.state.player.mirrorTimer == r, "the tick follows the client's value")
  -- a second timer: the one running out first is shown
  progress.EXHAUSTION = 20000
  fire("MIRROR_TIMER_START", "EXHAUSTION", 20000, 60000, -1, 0, "Fatigue")
  module:Refresh(Nock.state)
  ok(Nock.state.player.mirrorTimer.mirror == "EXHAUSTION", "two timers: the one closer to empty")
  fire("MIRROR_TIMER_STOP", "EXHAUSTION")
  module:Refresh(Nock.state)
  ok(Nock.state.player.mirrorTimer.mirror == "BREATH", "its STOP falls back to breath")
  fire("MIRROR_TIMER_STOP", "BREATH")
  module:Refresh(Nock.state)
  ok(Nock.state.player.mirrorTimer == nil, "all stopped: nothing published")
  -- the toggle hides Blizzard's bars
  p.reactCastMirrorTimers = true
  module:ApplyBlizzard()
  ok(hidden == true, "toggle on: Blizzard's timer bars hidden")
  p.reactShowCastBar = false
  module:ApplyBlizzard()
  ok(hidden == false, "Nock's cast bar off: Blizzard's bars stay")
  p.reactShowCastBar, p.reactCastMirrorTimers = nil, nil
  -- a timer already running at login (a /reload under water)
  info[1] = { "BREATH", 40000, 60000, -1, 0, "Breath" }
  progress.BREATH = 40000
  module:OnEnable()
  ok(Nock.state.player.mirrorTimer and Nock.state.player.mirrorTimer.mirror == "BREATH", "a timer already running is picked up at enable")
end

print(("forever_mirror_timers: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
