-- Tests/forever_weave_probe_test.lua
-- Forever/Probe.lua WeaveReport: the four spec questions answered from the
-- helper's state, the swing samples and the cast ring. Pure.
-- Run from the repo root: luajit Tests/forever_weave_probe_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

_G.GetTime = function() return 500 end
local Nock = { Flavor = { forever = true, toc = 16001, Plain = function(v) return v end }, API = { Missing = function() return {} end }, UI = {} }
local module
function Nock:NewModule(name) module = { name = name, events = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  return module end
function Nock:GetModule() return nil end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/Probe.lua")
local P = Nock.ForeverProbe
ok(type(P.WeaveReport) == "function", "Probe.WeaveReport exists")

local text = P.WeaveReport({
  stage = "OUT", legIn = 1.05, legOut = 0.98, learnedIn = true, learnedOut = false, moving = true,
  playerMovingPlain = true, mhRangeEvents = 3, raptorId = 2973,
  swings = {
    { t = 10.00, swingType = 0, duration = 2.0 },
    { t = 10.05, swingType = 2, duration = 2.6 },   -- a Ranged event 50 ms after the hit = the client's reset
    { t = 14.00, swingType = 0, duration = 2.0 },
  },
  casts = { { t = 9.98, ev = "UNIT_SPELLCAST_SUCCEEDED", spellID = 2973 }, { t = 13.0, ev = "UNIT_SPELLCAST_SENT", spellID = 2973 } },
  helper = { { t = 10.00, kind = "MainHand", stage = "OUT", legIn = 1.05 }, { t = 10.05, kind = "Ranged", shot = false, stage = "OUT" } },
  transitions = { { t = 9.00, from = nil, to = "GO", zone = "SWEET", age = 0.05, melee = 0, raptor = 0, moving = false, radial = 1, face = -1 } },
})
ok(text:find("stage transitions (what the decision saw):", 1, true) and text:find("9.00  nil -> GO  zone SWEET  age 0.05  melee 0.00  raptor 0.00  moving false  radial 1.00  face -1", 1, true), "transitions printed with their inputs")
ok(text:find("helper events (how the engine classed them):", 1, true) and text:find("10.05  Ranged  reset  stage OUT", 1, true) and text:find("10.00  MainHand  stage OUT  legIn 1.05", 1, true), "the helper's own ring: each event with its verdict and stage")
ok(text:find("stage: OUT", 1, true) and text:find("legIn 1.05 (learned)", 1, true) and text:find("legOut 0.98 (seed)", 1, true), "header: stage and the legs")
ok(text:find("IsPlayerMoving plain in combat: true", 1, true), "question 4: IsPlayerMoving")
ok(text:find("MainHand PLAYER_SWING_RANGE_UPDATE events: 3", 1, true), "question 3: the melee edge signal count")
ok(text:find("Ranged event 0.050 s after a MainHand hit: client reset", 1, true), "question 1: a Ranged swing right after a hit is called out")
ok(text:find("no Ranged event within 0.1 s of the hit at 14.00", 1, true), "question 1: a hit without one is called out too")
ok(text:find("Raptor Strike SUCCEEDED 0.02 s before the hit at 10.00", 1, true), "question 2: Raptor cast vs the next hit")
ok(not text:find("before the hit at 14.00", 1, true), "question 2: a SENT (not SUCCEEDED) cast is not paired")

-- /nock probe keys: one column per bound movement key, unbound actions kept as a "-" column, mouse last.
local cols = P.KeysColumns(function(action)
  if action == "MOVEFORWARD" then return "W", "UP" end
  if action == "MOVEBACKWARD" then return "S" end
  return nil
end)
ok(#cols == 2 + 1 + 6 + 2, "keys probe: two forward keys, one backward, six unbound actions, two mouse buttons")
ok(cols[1].key == "W" and cols[2].key == "UP" and cols[3].key == "S" and cols[4].key == nil and cols[4].action == "STRAFELEFT", "keys probe: columns in binding order")
ok(cols[#cols].key == "RightButton" and cols[#cols].action == "mouse", "keys probe: mouse buttons close the list")

print(("forever_weave_probe: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
