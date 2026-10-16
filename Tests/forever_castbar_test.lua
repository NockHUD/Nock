-- Tests/forever_castbar_test.lua
-- Forever/CastBar.lua: player casts and channels -> state.player.casting from
-- UnitCastingInfo/UnitChannelInfo; STOP/INTERRUPTED clear; Auto Shot goes to
-- state.player.autoShotCast (the wind-up), never into casting.
-- Run from the repo root: luajit Tests/forever_castbar_test.lua

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

local hideCalls = {}
local Nock = { Flavor = { forever = true, Plain = function(v) return v end }, Spells = { AUTO_SHOT = 75 },
               db = { profile = { hideBlizzardCastBar = true } },
               UI = { SetBlizzardCastBarHidden = function(h) hideCalls[#hideCalls + 1] = h; return true end } }
local module
function Nock:NewModule(name) module = { name = name, events = {}, msgs = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function module:RegisterMessage(m, h) self.msgs[m] = h or m end
  return module end
function Nock:GetModule() return nil end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/CastBar.lua")

ok(module and module.name == "CastBar", "module CastBar")
module:OnEnable()
-- Hide Blizzard's cast bar on Forever too (the shared hideBlizzardCastBar).
ok(hideCalls[1] == true, "enable: Blizzard's bar hidden when the setting is on")
ok(module.msgs.NOCK_VISUALS_CHANGED == "ApplyBlizzardCastBarVisibility", "a settings change re-applies it")
Nock.db.profile.hideBlizzardCastBar = false
module:ApplyBlizzardCastBarVisibility()
ok(hideCalls[2] == false, "setting off: restored")
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

-- Auto Shot never enters casting even if the client reports it: the wind-up
-- (client build of 2026-10) is its own record, drawn as the free queue window.
casting = { "Auto Shot", "", 132222, 100000, 100500, false, "c3", false, 75 }
fire("UNIT_SPELLCAST_START", "player", "c3", 75)
ok(st.casting == nil, "Auto Shot never enters casting")
ok(st.autoShotCast and st.autoShotCast.auto == true and st.autoShotCast.spellId == 75, "the wind-up record is published")
ok(st.autoShotCast.startTime == 100 and st.autoShotCast.endTime == 100.5, "the client's own window is used when it reports one")
ok(st.autoShotCast.name == "Auto Shot" and st.autoShotCast.icon == 132222, "name and icon from the client")
casting = nil
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c3", 75)
ok(st.autoShotCast == nil, "SUCCEEDED(75) is the release: cleared")

-- Without a client window the end is the predicted release (Nock.AutoShotWindupEnd).
Nock.state.ranged.swingStart, Nock.state.ranged.swingDuration = 98.4, 2.0
Nock.state.ranged.windup, Nock.state.ranged.windupMeasured = 0.4, true
now = 100.0
fire("UNIT_SPELLCAST_START", "player", "c3b", 75)
ok(st.autoShotCast and math.abs(st.autoShotCast.endTime - 100.4) < 1e-9, "no client window: ends at the predicted release")
fire("UNIT_SPELLCAST_STOP", "player", "c3b", 75)
ok(st.autoShotCast == nil, "STOP(75) clears")
fire("UNIT_SPELLCAST_START", "player", "c3c", 75)
fire("UNIT_SPELLCAST_FAILED", "player", "c3d", 75)
ok(st.autoShotCast ~= nil, "FAILED(75) is a refused re-press: the wind-up stands")
fire("UNIT_SPELLCAST_INTERRUPTED", "player", "c3c", 75)
ok(st.autoShotCast == nil, "INTERRUPTED(75) clears")

-- Refresh: the stale net (a cancelled shot with no event) and the live-release pin.
now = 100.0
fire("UNIT_SPELLCAST_START", "player", "c3e", 75)
ok(st.autoShotCast ~= nil, "wind-up up")
module:Refresh(Nock.state)
ok(st.autoShotCast ~= nil, "fresh: kept")
Nock.state.ranged.swingStart = 98.6     -- the grid moved under the bar
module:Refresh(Nock.state)
ok(math.abs(st.autoShotCast.endTime - 100.6) < 1e-9, "pinned to the live release")
now = 101.2
module:Refresh(Nock.state)
ok(st.autoShotCast == nil, "stale past end + 0.5: dropped")
Nock.state.ranged.swingStart, Nock.state.ranged.swingDuration = 0, 3.0
now = 100

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
  if id == 75 then return "Auto Shot", 132222, 0 end
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

-- The MODELLED wind-up (no client event on build 70425): from the stop-gated
-- measurement, standing still it runs (due - W) -> due; after a stop inside
-- that window it runs stop -> stop + W; nothing while moving, nothing until
-- W is measured, nothing once the swing is not live.
do
  casting, channel = nil, nil
  local S = Nock.state
  local r, c = S.ranged, S.context
  S.player.inCombat = true
  S.player.casting, S.player.autoShotCast = nil, nil
  r.swingStart, r.swingDuration, r.repeating, r.targetInRange = 200, 2.0, true, nil
  r.windup, r.windupMeasured = 0.75, true
  c.moving, c.stoppedAt = false, nil
  local function tick(t) now = t; r.swingRemaining = math.max(0, r.swingStart + r.swingDuration - t); module:Refresh(S) end

  tick(200.5)
  ok(st.autoShotCast == nil, "model: early in the cycle nothing is drawn")
  tick(201.3)
  ok(st.autoShotCast and st.autoShotCast.auto == true and st.autoShotCast.spellId == 75, "model: inside the last W the wind-up is published")
  ok(math.abs(st.autoShotCast.startTime - 201.25) < 1e-9 and math.abs(st.autoShotCast.endTime - 202.0) < 1e-9, "model: standing still it runs due - W -> due")
  ok(st.autoShotCast.name == "Auto Shot" and st.autoShotCast.icon == 132222, "model: name and icon from spell data")
  ok(st.casting == nil, "model: never enters casting")

  -- Moving inside the window: withdrawn.
  c.moving = true
  tick(201.5)
  ok(st.autoShotCast == nil, "model: nothing while moving")
  -- Stopped past the due mark: runs from the stop for W.
  c.moving, c.stoppedAt = false, 202.3
  tick(202.4)
  ok(st.autoShotCast and math.abs(st.autoShotCast.startTime - 202.3) < 1e-9 and math.abs(st.autoShotCast.endTime - 203.05) < 1e-9, "model: after a late stop it runs stop -> stop + W")
  -- The shot: the next cycle begins, the record goes.
  r.swingStart = 203.05
  tick(203.06)
  ok(st.autoShotCast == nil, "model: the shot ends it")
  -- A stop from BEFORE this cycle's shot does not move the start.
  c.stoppedAt = 202.3
  tick(204.4)
  ok(st.autoShotCast and math.abs(st.autoShotCast.startTime - 204.3) < 1e-9, "model: an old stop is ignored")
  -- Stale: half a second past the end with no shot, withdrawn.
  tick(205.6)
  ok(st.autoShotCast == nil, "model: dropped half a second past its end")
  -- Not live (swing expired, auto off, out of combat): nothing. A swing still
  -- in flight is live whatever the flags (Nock.AutoSwingLive).
  r.swingStart = 300; r.repeating = false; S.player.inCombat = false
  tick(302.3)
  ok(st.autoShotCast == nil, "model: expired swing, auto off, out of combat -> nothing")
  S.player.inCombat = true; r.repeating = true
  tick(302.3)
  ok(st.autoShotCast ~= nil and math.abs(st.autoShotCast.endTime - 302.0) < 1e-9, "model: held shot in combat -> the wind-up stays drawn to its end")
  -- Unmeasured W: nothing (the queue window is not a wind-up).
  r.windupMeasured = false
  tick(301.6)
  ok(st.autoShotCast == nil, "model: nothing until W is measured")
  r.windupMeasured = true
  -- Another producer owning the field is left alone.
  local other = { name = "sim" }
  st.autoShotCast = other
  tick(301.7)
  ok(st.autoShotCast == other, "model: never overwrites another producer's record")
  st.autoShotCast = nil
  -- A real cast event record takes precedence and gets the TBC safety net.
  r.swingStart, r.swingDuration = 400, 2.0
  tick(400.1)
  fire("UNIT_SPELLCAST_START", "player", "ev", 75)
  ok(st.autoShotCast and math.abs(st.autoShotCast.endTime - 402.0) < 1e-9, "event record: ends at the predicted release")
  tick(400.2)
  ok(st.autoShotCast and st.autoShotCast.startTime == 400.1, "event record: the model does not replace it")
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "ev", 75)
  ok(st.autoShotCast == nil, "event record: cleared on the release")
  tick(401.3)
  ok(st.autoShotCast and math.abs(st.autoShotCast.startTime - 401.25) < 1e-9, "...and the model resumes")
end

print(("forever_castbar: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
