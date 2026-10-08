-- Tests/forever_eotb_pulse_test.lua
-- Forever/EotbPulse.lua: the Eyes of the Beast pulse timer. A pet under
-- Eyes of the Beast pulls on a fixed beat counted from the moment combat
-- starts; the module publishes state.eotbPulse (active, seconds to the next
-- pulse) for the pulse bar, and a resync restarts the beat from now.
-- Run from the repo root: luajit Tests/forever_eotb_pulse_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

local now = 100
_G.GetTime = function() return now end
local Nock = {
  Flavor = { forever = true, Plain = function(v) return v end },
  API = { SpellName = function(id) if id == 1002 then return "Eyes of the Beast" end return "spell" .. id end },
  db = { profile = {} },
  Constants = {},
}
local module
function Nock:NewModule(name)
  module = { name = name, events = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  return module
end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/Spells.lua")
dofile("Forever/EotbPulse.lua")
local M = module
ok(M and M.name == "EotbPulse", "registers as EotbPulse")
ok(Nock.Spells.EYES_OF_THE_BEAST == 1002, "Eyes of the Beast id in Spells")

-- Pure timing.
ok(near(M.Remaining(100, 100, 5.6), 5.6), "at the anchor: a whole period to go")
ok(near(M.Remaining(102, 100, 5.6), 3.6), "two seconds in: 3.6 to go")
ok(near(M.Remaining(105.6 + 1, 100, 5.6), 4.6), "past one pulse: counting to the next")

-- The module over state.
M:OnEnable()
local st = { player = { inCombat = false, casting = nil } }
local function fire(ev, ...) local h = M.events[ev]; M[type(h) == "string" and h or ev](M, ev, ...) end
local eotb = { isChannel = true, spellId = 1002, name = "Eyes of the Beast", startTime = 95, endTime = 155 }

M:Refresh(st)
ok(st.eotbPulse and st.eotbPulse.active == false and st.eotbPulse.period == 5.6, "idle: published inactive, default period 5.6")

st.player.casting = eotb
M:Refresh(st)
ok(st.eotbPulse.active == false, "channelling out of combat: inactive (the beat starts with combat)")

now = 100
st.player.inCombat = true
fire("PLAYER_REGEN_DISABLED")
now = 102
M:Refresh(st)
local e = st.eotbPulse
ok(e.active == true and near(e.remaining, 3.6), "in combat under EotB: 3.6 s to the next pulse")

-- Resync: the beat restarts from now.
now = 103
M:Resync()
now = 104
M:Refresh(st)
ok(near(st.eotbPulse.remaining, 4.6), "resync: counted from the click")

-- Another channel, a plain cast, nothing: inactive.
st.player.casting = { isChannel = true, spellId = 5384, name = "Feign Death", startTime = 100, endTime = 106 }
M:Refresh(st)
ok(st.eotbPulse.active == false, "another channel: inactive")
st.player.casting = { isChannel = false, spellId = 1002, name = "Eyes of the Beast", startTime = 100, endTime = 102 }
M:Refresh(st)
ok(st.eotbPulse.active == false, "not a channel: inactive")
-- A rank with its own id is matched by name.
st.player.casting = { isChannel = true, spellId = 777, name = "Eyes of the Beast", startTime = 100, endTime = 160 }
Nock.API.SpellName = function(id) if id == 1002 or id == 777 then return "Eyes of the Beast" end return "spell" .. id end
M:Refresh(st)
ok(st.eotbPulse.active == true, "another id under the same name: active")

-- Period from the profile, clamped.
Nock.db.profile.eotbPulsePeriod = 5.5
M:Refresh(st)
ok(st.eotbPulse.period == 5.5, "period from the profile")
Nock.db.profile.eotbPulsePeriod = 0.2
M:Refresh(st)
ok(st.eotbPulse.period == 1, "clamped at 1 s")
Nock.db.profile.eotbPulsePeriod = "junk"
M:Refresh(st)
ok(st.eotbPulse.period == 5.6, "junk: the default")
Nock.db.profile.eotbPulsePeriod = nil

-- Combat ends: the beat is gone until the next pull.
st.player.inCombat = false
fire("PLAYER_REGEN_ENABLED")
M:Refresh(st)
ok(st.eotbPulse.active == false and st.eotbPulse.remaining == nil, "combat over: inactive")
st.player.inCombat = true
M:Refresh(st)
ok(st.eotbPulse.active == false, "in combat again without a fresh start: inactive until REGEN_DISABLED")
now = 200
fire("PLAYER_REGEN_DISABLED")
now = 201
M:Refresh(st)
ok(st.eotbPulse.active == true and near(st.eotbPulse.remaining, 4.6), "a new pull starts a new beat")

-- The producer does not read the display settings (views decide).
Nock.db.profile.eotbPulseEnabled = false
M:Refresh(st)
ok(st.eotbPulse.active == true, "published whatever the on/off says")

print(("forever_eotb_pulse: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
