-- Tests/forever_manatick_test.lua
-- Forever/ManaTick.lua: a power event within the spend window after an own
-- cast is a spend, any other is a regen tick; Auto Shot never marks a spend.
-- Run from the repo root: luajit Tests/forever_manatick_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local now = 100
_G.GetTime = function() return now end
_G.GetRangedHaste = function() return 0 end
local Nock = { Flavor = { forever = true, Plain = function(v) return v end }, Constants = {}, Spells = { AUTO_SHOT = 75 } }
local module
function Nock:NewModule(name) module = { name = name, events = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  return module end
function Nock:GetModule() return nil end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
Nock.ManaTickEngine = dofile("Modules/ManaTickEngine.lua")
dofile("Forever/ManaTick.lua")
local M = module
ok(M and M.name == "ManaTick", "module ManaTick")
M:OnEnable()
local st = Nock.state.player
local mt = st.manaTick
local function fire(ev, ...) local h = M.events[ev]; M[type(h) == "string" and h or ev](M, ev, ...) end
ok(M.events["UNIT_POWER_UPDATE"] and M.events["UNIT_SPELLCAST_SUCCEEDED"], "events registered (no unit-event helper in the stub)")

-- Out of combat: a spend right after a cast opens the five-second window.
st.inCombat = false
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 1978)
now = 100.1
fire("UNIT_POWER_UPDATE", "player", "MANA")
ok(mt.mode == "fsr" and mt.start == 100.1, "power event 0.1 s after a cast is a spend (fsr bar)")
-- A later power event with no cast is a regen tick.
now = 106
fire("UNIT_POWER_UPDATE", "player", "MANA")
ok(mt.lastTick == 106 and mt.mode == "tick", "power event without a recent cast is a gain (tick bar)")
-- Auto Shot never marks a spend.
now = 110
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 75)
now = 110.1
fire("UNIT_POWER_UPDATE", "player", "MANA")
ok(mt.lastTick == 110.1, "Auto Shot is not a spend marker")
-- The window is consumed by one event.
now = 120
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 3044)
now = 120.05
fire("UNIT_POWER_UPDATE", "player", "MANA")
now = 120.1
fire("UNIT_POWER_UPDATE", "player", "MANA")
ok(mt.lastTick == 120.1, "second event after the same cast is a gain")
-- Other power types and other units are ignored.
now = 130
fire("UNIT_POWER_UPDATE", "player", "RAGE"); fire("UNIT_POWER_UPDATE", "target", "MANA")
ok(mt.lastTick == 120.1, "rage and other units ignored")
-- In combat a spend with no live bar seeds a tick bar to the next tick.
st.inCombat = true
mt.mode, mt.expire = nil, 0
now = 200
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 3044)
now = 200.1
fire("UNIT_POWER_UPDATE", "player", "MANA")
ok(mt.mode == "tick" and mt.start == 200.1, "in-combat spend seeds a tick bar")
-- Reseed clears.
fire("PLAYER_ENTERING_WORLD")
ok(mt.mode == nil and mt.lastTick == nil, "reseed clears the phase and bar")
print(("forever_manatick: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
