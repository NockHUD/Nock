-- Tests/forever_castbar_test.lua
-- Forever/CastBar.lua: player casts and channels -> state.player.casting from
-- UnitCastingInfo/UnitChannelInfo; STOP/INTERRUPTED clear; Auto Shot never
-- enters. Run from the repo root: luajit Tests/forever_castbar_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local now = 100
_G.GetTime = function() return now end
_G.GetRangedHaste = function() return 0 end
local casting, channel
_G.UnitCastingInfo = function(u) if u == "player" and casting then return unpack(casting) end end
_G.UnitChannelInfo = function(u) if u == "player" and channel then return unpack(channel) end end

local Nock = { Flavor = { forever = true, Plain = function(v) return v end }, Spells = { AUTO_SHOT = 75 } }
local module
function Nock:NewModule(name) module = { name = name, events = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  return module end
function Nock:GetModule() return nil end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/CastBar.lua")

ok(module and module.name == "CastBar", "module CastBar")
module:OnEnable()
local st = Nock.state.player
local function fire(ev, unit, ...) local h = module.events[ev]; if not h then return end; module[type(h) == "string" and h or ev](module, ev, unit, ...) end

-- Aimed Shot 2 s cast: name, text, texture, startMs, endMs, isTradeSkill, castID, notInterruptible, spellId
casting = { "Aimed Shot", "", 135130, 100000, 102000, false, "cast-1", false, 19434 }
fire("UNIT_SPELLCAST_START", "player", "cast-1", 19434)
ok(st.casting and st.casting.spellId == 19434 and st.casting.name == "Aimed Shot", "cast published")
ok(st.casting.startTime == 100 and st.casting.endTime == 102 and st.casting.isChannel == false, "ms converted to seconds")
ok(st.casting.icon == 135130, "icon published")

-- Delayed: end moves.
casting[5] = 102500
fire("UNIT_SPELLCAST_DELAYED", "player", "cast-1", 19434)
ok(st.casting.endTime == 102.5, "delay updates endTime")

-- Stop clears.
casting = nil
fire("UNIT_SPELLCAST_STOP", "player", "cast-1", 19434)
ok(st.casting == nil, "stop clears")

-- Other units ignored.
casting = { "Fireball", "", 1, 100000, 103000, false, "c2", false, 133 }
fire("UNIT_SPELLCAST_START", "target", "c2", 133)
ok(st.casting == nil, "target casts ignored")

-- Auto Shot never enters casting even if the client reports it.
casting = { "Auto Shot", "", 132222, 100000, 100500, false, "c3", false, 75 }
fire("UNIT_SPELLCAST_START", "player", "c3", 75)
ok(st.casting == nil and st.autoShotCast == nil, "Auto Shot excluded")

-- Channel: name, text, texture, startMs, endMs, isTradeSkill, notInterruptible, spellId
casting = nil
channel = { "Eagle Eye", "", 132172, 200000, 260000, false, false, 6197 }
now = 200
fire("UNIT_SPELLCAST_CHANNEL_START", "player", "c4", 6197)
ok(st.casting and st.casting.isChannel == true and st.casting.endTime == 260, "channel published")
channel[5] = 255000
fire("UNIT_SPELLCAST_CHANNEL_UPDATE", "player", "c4", 6197)
ok(st.casting.endTime == 255, "channel update moves endTime")
channel = nil
fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "c4", 6197)
ok(st.casting == nil, "channel stop clears")

-- Interrupted clears too.
casting = { "Aimed Shot", "", 135130, 300000, 302000, false, "c5", false, 19434 }
fire("UNIT_SPELLCAST_START", "player", "c5", 19434)
casting = nil
fire("UNIT_SPELLCAST_INTERRUPTED", "player", "c5", 19434)
ok(st.casting == nil, "interrupted clears")

-- Multi-Shot: START fires but UnitCastingInfo reports nothing (ranged shots
-- never enter it) -> the bar is raised from the spell's own cast time.
Nock.API = { SpellInfo = function(id)
  if id == 2643 then return "Multi-Shot", 132330, 500 end
  if id == 999 then return "Instant", 1, 0 end
end }
casting = nil
now = 400
fire("UNIT_SPELLCAST_START", "player", "ms-1", 2643)
ok(st.casting and st.casting.spellId == 2643 and st.casting.name == "Multi-Shot", "Multi-Shot published without UnitCastingInfo")
ok(st.casting and st.casting.startTime == 400 and st.casting.endTime == 400.5, "Multi-Shot spans its cast time")
ok(st.casting and st.casting.icon == 132330, "Multi-Shot icon")

-- A STOP for some other cast (a failed re-press) must not end it early...
fire("UNIT_SPELLCAST_STOP", "player", "other", 2643)
ok(st.casting and st.casting.spellId == 2643, "foreign STOP keeps the fallback bar")
-- ...its own STOP does.
fire("UNIT_SPELLCAST_STOP", "player", "ms-1", 2643)
ok(st.casting == nil, "own STOP clears the fallback bar")

-- Interrupt of the fallback cast clears too.
fire("UNIT_SPELLCAST_START", "player", "ms-2", 2643)
fire("UNIT_SPELLCAST_INTERRUPTED", "player", "ms-2", 2643)
ok(st.casting == nil, "interrupt clears the fallback bar")

-- A zero cast time never raises a bar.
fire("UNIT_SPELLCAST_START", "player", "i-1", 999)
ok(st.casting == nil, "instant spell raises no bar")

-- The Forever reality (probed): Multi-Shot fires SENT on the press and then
-- only SUCCEEDED -- no START, no STOP. The bar starts on SENT and expires.
local timers = {}
_G.C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }
local function runTimers()
  for i = #timers, 1, -1 do
    if now >= timers[i].at then local t = table.remove(timers, i); t.fn() end
  end
end
now = 500
fire("UNIT_SPELLCAST_SENT", "player", "", "ms-3", 2643)
ok(st.casting and st.casting.spellId == 2643 and st.casting.endTime == 500.5, "SENT raises the Multi-Shot bar")
fire("UNIT_SPELLCAST_SENT", "player", "", "i-2", 999)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "i-2", 999)
ok(st.casting and st.casting.spellId == 2643, "an instant's SENT/SUCCEEDED leave the bar alone")
now = 500.3; runTimers()
ok(st.casting and st.casting.spellId == 2643, "bar still up mid-cast")
now = 500.503
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "ms-3", 2643)
ok(st.casting == nil, "own SUCCEEDED (the release) ends the bar")

-- Backstop: a lost SUCCEEDED still expires the bar.
now = 550
fire("UNIT_SPELLCAST_SENT", "player", "", "ms-6", 2643)
now = 550.6; runTimers()
ok(st.casting == nil, "bar expires at its end without SUCCEEDED")

-- A failed press (out of range) drops its bar at once.
now = 600
fire("UNIT_SPELLCAST_SENT", "player", "", "ms-4", 2643)
fire("UNIT_SPELLCAST_FAILED", "player", "other", 2643)
ok(st.casting and st.casting.spellId == 2643, "foreign FAILED keeps the bar")
fire("UNIT_SPELLCAST_FAILED_QUIET", "player", "ms-4", 2643)
ok(st.casting == nil, "own FAILED clears the bar")

-- A real cast's START takes the bar over from a SENT-raised one.
now = 700
fire("UNIT_SPELLCAST_SENT", "player", "", "ms-5", 2643)
casting = { "Aimed Shot", "", 135130, 700000, 702000, false, "a-1", false, 19434 }
fire("UNIT_SPELLCAST_START", "player", "a-1", 19434)
ok(st.casting and st.casting.spellId == 19434, "real cast takes over")
now = 701; runTimers()
ok(st.casting and st.casting.spellId == 19434, "stale expiry leaves the real cast alone")

print(("forever_castbar: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
