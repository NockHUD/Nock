-- Tests/forever_swing_test.lua
-- Forever/SwingTimer.lua: PLAYER_SWING drives state.ranged / state.melee, the
-- auto-repeat events drive `repeating`, and the tick's swingRemaining math
-- keeps working. Run from the repo root: luajit Tests/forever_swing_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local now = 100
_G.GetTime = function() return now end
_G.GetRangedHaste = function() return 0 end
_G.UnitAffectingCombat = function() return true end
_G.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }

local Nock = { Flavor = { forever = true, Plain = function(v) return v end }, Constants = { SpellID = {} } }
local module
function Nock:NewModule(name) module = { name = name, events = {} }
  function module:RegisterEvent(ev, handler) self.events[ev] = handler or ev end
  function module:UnregisterEvent(ev) self.events[ev] = nil end
  return module end
function Nock:GetModule(name) return module end
_G.LibStub = function() return { GetAddon = function() return Nock end } end

dofile("Core/State.lua")
dofile("Forever/Spells.lua")
dofile("Forever/SwingTimer.lua")

ok(Nock.Spells and Nock.Spells.AUTO_SHOT == 75 and Nock.Spells.GCD_PROBE == 1978, "Forever spell table")
ok(module and module.name == "SwingTimer", "module is named SwingTimer")
module:OnEnable()
ok(module.events["PLAYER_SWING"] and module.events["START_AUTOREPEAT_SPELL"] and module.events["STOP_AUTOREPEAT_SPELL"], "events registered")

local st = Nock.state
local function fire(ev, ...)
  local h = module.events[ev]
  if type(h) == "string" then module[h](module, ev, ...) else module[ev](module, ev, ...) end
end

fire("PLAYER_SWING", 2.174, 2)
ok(st.ranged.swingStart == 100 and st.ranged.swingDuration == 2.174, "ranged swing anchored at the event")
fire("PLAYER_SWING", 2.6, 0)
ok(st.melee.swingStart == 100 and st.melee.swingDuration == 2.6, "main-hand swing anchored")
ok(st.ranged.swingDuration == 2.174, "melee event leaves ranged alone")
now = 100.4
fire("PLAYER_SWING", 1.9, 1)
ok(st.ranged.swingDuration == 2.174 and st.melee.swingDuration == 2.6 and st.melee.swingStart == 100, "off-hand event leaves the main hand and ranged alone")
ok(st.melee.offStart == 100.4 and st.melee.offDuration == 1.9, "off-hand swing anchored in its own fields")
now = 100

fire("START_AUTOREPEAT_SPELL")
ok(st.ranged.repeating == true, "auto-repeat on")
fire("STOP_AUTOREPEAT_SPELL")
ok(st.ranged.repeating == false, "auto-repeat off")

-- Melee auto-attack: the client's toggle events (not combat state).
ok(module.events["PLAYER_ENTER_COMBAT"] and module.events["PLAYER_LEAVE_COMBAT"], "melee toggle events registered")
fire("PLAYER_ENTER_COMBAT")
ok(st.melee.attacking == true, "melee auto-attack on")
fire("PLAYER_LEAVE_COMBAT")
ok(st.melee.attacking == false, "melee auto-attack off")
fire("PLAYER_ENTER_COMBAT")
fire("PLAYER_ENTERING_WORLD")
ok(st.melee.attacking == false, "a loading screen clears a stranded toggle")

-- A haste change mid-swing arrives as the NEXT swing's duration; nothing to reanchor.
now = 102.174
fire("PLAYER_SWING", 1.553, 2)
ok(st.ranged.swingStart == 102.174 and st.ranged.swingDuration == 1.553, "next swing carries the new duration")

-- Zero/negative durations are ignored (Blizzard's own frame does the same).
fire("PLAYER_SWING", 0, 2)
ok(st.ranged.swingDuration == 1.553, "zero duration ignored")

-- Samples ring for the probe.
local s = module:Samples()
ok(#s >= 4 and s[#s].duration == 0 and s[#s - 1].swingType == 2, "samples keep the raw payloads in order")

-- RefreshSwingDurations exists for the tick's call shape and never touches secrets.
_G.UnitRangedDamage = function() error("must not be called on Forever") end
module:RefreshSwingDurations()
ok(true, "RefreshSwingDurations is a no-op")

-- Range check: enabled at OnEnable, published from the event, nil without a check.
local enabled = {}
_G.C_SwingTimer = { EnableRangeCheck = function(kind, on) enabled[kind] = on end,
                    IsTargetWithinSwingRange = function() return true end }
module:OnEnable()
ok(enabled[2] == true, "ranged range check enabled")
ok(st.ranged.targetInRange == true, "direct read at enable")
fire("PLAYER_SWING_RANGE_UPDATE", 2, false, true)
ok(st.ranged.targetInRange == false, "out of range published")
ok(Nock.AutoSwingLive() == false, "auto bar not live while the target is out of range")
fire("PLAYER_SWING_RANGE_UPDATE", 0, true, true)
ok(st.ranged.targetInRange == false, "main-hand range event ignored")
fire("PLAYER_SWING_RANGE_UPDATE", 2, true, false)
ok(st.ranged.targetInRange == nil, "no check -> nil")
_G.C_SwingTimer.IsTargetWithinSwingRange = function() return nil end
fire("PLAYER_TARGET_CHANGED")
ok(st.ranged.targetInRange == nil, "no target -> nil")

-- Entering world clears a stranded auto-repeat.
st.ranged.repeating = true
fire("PLAYER_ENTERING_WORLD")
ok(st.ranged.repeating == false and st.ranged.autoDelay == 0, "entering world resets repeating/autoDelay")

-- Spell-queue window: the cvar in ms -> state.ranged.queueWindow in seconds.
local Q = module.QueueWindowSeconds
ok(Q("400") == 0.4, "400 ms -> 0.4 s")
ok(Q("150") == 0.15, "150 ms -> 0.15 s")
ok(Q(nil) == 0.4 and Q("junk") == 0.4, "unreadable -> client default 0.4")
ok(Q("5000") == 1.0, "clamped to one second")
ok(Q("-3") == 0.4, "negative -> default")
_G.GetCVar = function(name) return name == "SpellQueueWindow" and "250" or nil end
module:RefreshQueueWindow()
ok(st.ranged.queueWindow == 0.25, "RefreshQueueWindow reads the cvar")
_G.GetCVar = function(name) return name == "SpellQueueWindow" and "300" or nil end
fire("CVAR_UPDATE", "SomethingElse")
ok(st.ranged.queueWindow == 0.25, "another cvar leaves the window alone")
fire("CVAR_UPDATE", "SpellQueueWindow")
ok(st.ranged.queueWindow == 0.3, "CVAR_UPDATE(SpellQueueWindow) re-reads")

-- Movement stamps on the swing samples (wind-up probe, 2026-09-23): each
-- ranged sample carries how long the player had stood still at the release,
-- and whether a move was in progress.
ok(module.events["PLAYER_STARTED_MOVING"] and module.events["PLAYER_STOPPED_MOVING"], "movement events registered")
now = 200
fire("PLAYER_SWING", 1.9, 2)
local S = module:Samples()
ok(S[#S].stillFor == nil and S[#S].moving == false, "never moved -> no stillFor, not moving")
now = 200.5; fire("PLAYER_STARTED_MOVING")
now = 200.9; fire("PLAYER_SWING", 1.9, 2)
S = module:Samples()
ok(S[#S].moving == true and S[#S].stillFor == nil, "shot while moving is stamped moving")
ok(math.abs(S[#S].movingFor - 0.4) < 1e-9, "...and with how long the move had been going")
now = 201.0; fire("PLAYER_STOPPED_MOVING")
now = 201.45; fire("PLAYER_SWING", 1.9, 2)
S = module:Samples()
ok(S[#S].moving == false and math.abs(S[#S].stillFor - 0.45) < 1e-9, "shot after stopping carries the still time")
ok(st.context.moving == false and st.context.stoppedAt == 201.0 and st.context.movingSince == 200.5, "movement edges published on state.context (the tick's speed read is secret in combat)")
now = 201.6; fire("PLAYER_STARTED_MOVING")
ok(st.context.moving == true and st.context.movingSince == 201.6, "moving again: flag and stamp")
now = 201.7; fire("PLAYER_STOPPED_MOVING")

-- Dual wield: the client's own answer, read on login and every gear change.
do
  local dw = false
  _G.IsDualWielding = function() return dw end
  ok(module.events["PLAYER_EQUIPMENT_CHANGED"] ~= nil, "equipment changes registered")
  fire("PLAYER_ENTERING_WORLD")
  ok(st.melee.dualWield == false, "one weapon: not dual wielding")
  dw = true
  fire("PLAYER_EQUIPMENT_CHANGED", 17, false)
  ok(st.melee.dualWield == true, "off-hand weapon equipped: dual wielding")
  _G.IsDualWielding = nil
  _G.C_PaperDollInfo = { OffhandHasWeapon = function() return true end }
  fire("PLAYER_EQUIPMENT_CHANGED", 17, false)
  ok(st.melee.dualWield == true, "falls back to OffhandHasWeapon")
  _G.C_PaperDollInfo = { OffhandHasWeapon = function() return "secret" end }
  fire("PLAYER_EQUIPMENT_CHANGED", 17, false)
  ok(st.melee.dualWield == false, "a non-boolean answer reads as one weapon")
  _G.C_PaperDollInfo = nil
end

-- Auto Shot delay readout (the "clip timer"): how much later than one reload
-- after the previous shot this one fired, written to state.ranged.autoDelay.
do
  st.player.inCombat = true
  fire("PLAYER_ENTERING_WORLD")
  now = 300
  fire("PLAYER_SWING", 2.0, 2)
  ok(st.ranged.autoDelay == 0, "first shot of a fight seeds the baseline: 0")
  now = 302.0
  fire("PLAYER_SWING", 2.0, 2)
  ok(st.ranged.autoDelay == 0, "shot on time -> 0")
  now = 304.3
  fire("PLAYER_SWING", 2.0, 2)
  ok(math.abs(st.ranged.autoDelay - 0.3) < 1e-9, "shot 0.3 s late -> +0.30")
  now = 306.0
  fire("PLAYER_SWING", 1.5, 2)
  ok(st.ranged.autoDelay == 0, "an early shot (haste proc) clamps to 0")

  -- Measured against the bar, not the previous shot: a melee hit that
  -- re-anchors the swing (Forever client bug, fix pending) moves the baseline.
  now = 306.5
  fire("PLAYER_SWING", 2.6, 0)
  st.ranged.swingStart = 306.5            -- what the weave helper does on the hit
  now = 308.0
  fire("PLAYER_SWING", 1.5, 2)
  ok(st.ranged.autoDelay == 0, "shot one reload after the re-anchored start -> 0")

  -- The client's own reset event (a Ranged swing inside 0.1 s of a melee hit)
  -- is not a shot: it must neither measure nor seed a delay.
  now = 309.5
  fire("PLAYER_SWING", 1.5, 2)
  ok(st.ranged.autoDelay == 0, "on-time shot before the reset case")
  now = 310.0
  fire("PLAYER_SWING", 2.6, 0)
  now = 310.05
  fire("PLAYER_SWING", 1.5, 2)
  ok(st.ranged.autoDelay == 0 and st.ranged.swingStart == 310.05, "reset event re-anchors but reads as no delay")
  now = 311.95
  fire("PLAYER_SWING", 1.5, 2)
  ok(math.abs(st.ranged.autoDelay - 0.4) < 1e-9, "next real shot measures from the reset: +0.40")

  -- Out of combat the readout rests at 0 and the next fight seeds afresh.
  st.player.inCombat = false
  now = 320
  fire("PLAYER_SWING", 1.5, 2)
  ok(st.ranged.autoDelay == 0, "out of combat -> 0")
  st.player.inCombat = true
  now = 330
  fire("PLAYER_SWING", 1.5, 2)
  ok(st.ranged.autoDelay == 0, "first shot of the next fight seeds again")
  now = 332.0
  fire("PLAYER_SWING", 1.5, 2)
  ok(math.abs(st.ranged.autoDelay - 0.5) < 1e-9, "then measures: +0.50")
end

-- Auto Shot wind-up (Forever client, 2026-10): the client now runs a cast
-- before the arrow leaves. UNIT_SPELLCAST_START(75) opens it, the ranged
-- PLAYER_SWING is the release; the ratio wind-up/duration is what the TBC
-- side measures too, and one accepted sample flips windupMeasured.
do
  _G.UnitCastingInfo = function(u)
    if u == "player" and _G.__autoCast then return unpack(_G.__autoCast) end
  end
  st.player.inCombat = true
  fire("PLAYER_ENTERING_WORLD")
  ok(st.ranged.windupMeasured == false, "wind-up starts unmeasured")
  ok(module.events["UNIT_SPELLCAST_START"] and module.events["UNIT_SPELLCAST_STOP"]
     and module.events["UNIT_SPELLCAST_SUCCEEDED"] and module.events["UNIT_SPELLCAST_INTERRUPTED"], "cast events registered")
  st.ranged.windupRatio = 0.5 / 3.0
  now = 400
  fire("PLAYER_SWING", 2.0, 2)                 -- seed: the shot before
  now = 401.65
  _G.__autoCast = { "Auto Shot", "", 132369, 401650, 402000, false, "cast-a", false, 75 }
  fire("UNIT_SPELLCAST_START", "player", "cast-a", 75)
  ok(st.ranged.windupMeasured == true, "the client's own cast window samples at START")
  ok(math.abs(st.ranged.windupRatio - 0.35 / 2.0) < 1e-9, "first sample replaces the seed: 0.35 / 2.0")
  now = 402.0
  _G.__autoCast = nil
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 75)
  fire("UNIT_SPELLCAST_STOP", "player", "cast-a", 75)
  fire("PLAYER_SWING", 2.0, 2)
  ok(math.abs(st.ranged.windupRatio - 0.175) < 1e-9, "the release of a cast-sampled shot is not a second sample")
  st.ranged.windup = st.ranged.windupRatio * st.ranged.swingDuration   -- what the tick does
  ok(math.abs(Nock.AutoShotWindup() - 0.35) < 1e-9, "views read the measured wind-up, not the queue window")

  -- A second clean sample averages in.
  now = 403.65
  fire("UNIT_SPELLCAST_START", "player", "cast-b", 75)
  now = 404.0
  fire("PLAYER_SWING", 2.0, 2)
  ok(math.abs(st.ranged.windupRatio - 0.175) < 1e-9, "a matching sample leaves the ratio put")

  -- A late shot is a clipped cycle: its wind-up read is inflated and rejected.
  now = 405.65
  fire("UNIT_SPELLCAST_START", "player", "cast-c", 75)
  now = 406.3
  fire("PLAYER_SWING", 2.0, 2)
  ok(math.abs(st.ranged.autoDelay - 0.3) < 1e-9, "late shot measured as delay")
  ok(math.abs(st.ranged.windupRatio - 0.175) < 1e-9, "late shot does not move the ratio")

  -- A speed change between start and release mixes two speeds: rejected.
  now = 407.95
  fire("UNIT_SPELLCAST_START", "player", "cast-d", 75)
  now = 408.3
  fire("PLAYER_SWING", 1.5, 2)
  ok(math.abs(st.ranged.windupRatio - 0.175) < 1e-9, "a shot carrying a new duration is not sampled")

  -- STOP / INTERRUPTED on 75 cancel the pending start.
  now = 409.5
  fire("UNIT_SPELLCAST_START", "player", "cast-e", 75)
  fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-e", 75)
  now = 409.8
  fire("PLAYER_SWING", 1.5, 2)
  ok(math.abs(st.ranged.windupRatio - 0.175) < 1e-9, "a cancelled wind-up is not sampled")

  -- A FAILED(75) is a refused re-press, not the end of the wind-up (TBC rule).
  now = 411.0
  fire("UNIT_SPELLCAST_START", "player", "cast-f", 75)
  fire("UNIT_SPELLCAST_FAILED", "player", "cast-g", 75)
  now = 411.3
  fire("PLAYER_SWING", 1.5, 2)
  ok(math.abs(st.ranged.windupRatio - (0.175 + (0.2 - 0.175) * 0.5)) < 1e-9, "FAILED leaves the start standing; sample averaged (0.3/1.5)")

  -- Other spells never touch it.
  now = 412.5
  fire("UNIT_SPELLCAST_START", "player", "cast-h", 56641)
  now = 412.8
  fire("PLAYER_SWING", 1.5, 2)
  local r0 = st.ranged.windupRatio
  ok(math.abs(r0 - 0.1875) < 1e-9, "another spell's START is not a wind-up")

  -- A start coincident with the swing (the client firing PLAYER_SWING at the
  -- wind-up start) is under the floor: rejected, and the probe shows it.
  now = 414.3
  fire("UNIT_SPELLCAST_START", "player", "cast-i", 75)
  fire("PLAYER_SWING", 1.5, 2)
  ok(st.ranged.windupRatio == r0, "a zero-length read is rejected")

  -- Wind-up samples ring for the probe: every 75 edge with the client's own cast times.
  local W = module:WindupSamples()
  ok(#W > 0 and W[1].ev == "UNIT_SPELLCAST_START" and W[1].t == 401.65, "samples keep the START edges")
  ok(W[1].castStart == 401.65 and W[1].castEnd == 402.0, "UnitCastingInfo's own window is kept with the START")
  local lastRel
  for i = 1, #W do if W[i].ev == "RELEASE" then lastRel = W[i] end end
  ok(lastRel and lastRel.measured ~= nil, "releases carry the measured wind-up")
  _G.UnitCastingInfo = nil
end

-- The stop-gated read (build 70425: no cast edge at all). A stop with the bar
-- already full -> the shot one wind-up (less the round trip) later.
do
  fire("PLAYER_ENTERING_WORLD")
  st.player.inCombat = true
  st.network = st.network or {}
  st.network.latencyMs = 60
  st.ranged.windupMeasured, st.ranged.windupRatio = false, 0.5 / 3.0
  now = 500
  fire("PLAYER_SWING", 2.0, 2)          -- due at 502.0
  now = 501.0; fire("PLAYER_STARTED_MOVING")
  now = 502.3; fire("PLAYER_STOPPED_MOVING")   -- bar full since 502.0
  now = 502.3 + 0.41                              -- shot 0.41 s after the stop
  fire("PLAYER_SWING", 2.0, 2)
  ok(st.ranged.windupMeasured == true, "a stop-gated shot samples the wind-up")
  ok(math.abs(st.ranged.windupRatio - 0.41 / 2.0) < 1e-9, "the RAW read is the bar's number: 0.41 / 2.0")
  local W = module:WindupSamples()
  local last = W[#W]
  ok(last.ev == "STOP->SHOT" and math.abs(last.raw - 0.41) < 1e-9 and math.abs(last.lessRtt - 0.35) < 1e-9 and last.sampled == "stop",
     "sample carries raw, the rtt-corrected value and the source")
  ok(math.abs(last.late - 0.71) < 1e-9, "...and how late the shot was")

  ok(st.ranged.windupSource == "stop" and math.abs(st.ranged.stopByRatio - 0.205) < 1e-9, "source is the stop feed; stop-by = the one read")

  -- The dummy-run case: a stop BEFORE the due time, inside the wind-up, with
  -- the shot pushed late. The shot fires at stop + W: W is read from the stop.
  -- Two reads -> the band keeps the SHORTEST (tick-aligned) and the stop-by
  -- edge the upper median (the longer one).
  now = 503.5; fire("PLAYER_STARTED_MOVING")
  now = 504.41; fire("PLAYER_STOPPED_MOVING")   -- due is 504.71: 0.3 s left
  now = 504.71 + 0.5; fire("PLAYER_SWING", 2.0, 2)   -- 0.5 late = 0.8 after the stop
  ok(math.abs(st.ranged.windupRatio - 0.205) < 1e-9, "a late shot after a stop inside the wind-up is a read; band = min of {0.205, 0.4}")
  ok(math.abs(st.ranged.stopByRatio - 0.4) < 1e-9, "stop-by edge = upper median of {0.205, 0.4}")
  W = module:WindupSamples()
  ok(W[#W].ev == "STOP->SHOT" and math.abs(W[#W].late - 0.5) < 1e-9 and W[#W].sampled == "stop", "the row carries the lateness")

  -- A stop while the bar was still running with the shot ON TIME: the stop
  -- did not gate it, no read.
  local n0 = #module:WindupSamples()
  local ratio0 = st.ranged.windupRatio
  now = 505.8; fire("PLAYER_STARTED_MOVING")
  now = 506.2; fire("PLAYER_STOPPED_MOVING")   -- due is 507.21
  now = 507.21; fire("PLAYER_SWING", 2.0, 2)
  ok(st.ranged.windupRatio == ratio0, "a stop with the shot on time is not a sample")
  ok(#module:WindupSamples() == n0, "...and leaves no stop row")

  -- An old stop (before the previous shot) is spent, even on a late shot.
  now = 509.6; fire("PLAYER_SWING", 2.0, 2)   -- 0.39 late, no stop since the last shot
  ok(st.ranged.windupRatio == ratio0 and #module:WindupSamples() == n0, "a late shot without a fresh stop: no stop read")

  -- A cast edge after the stop may have pushed the shot: not read.
  now = 510.0; fire("PLAYER_STARTED_MOVING")
  now = 511.3; fire("PLAYER_STOPPED_MOVING")   -- due 511.6
  now = 511.4; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "ms", 2643)
  now = 512.1; fire("PLAYER_SWING", 2.0, 2)    -- 0.5 late
  ok(st.ranged.windupRatio == ratio0 and #module:WindupSamples() == n0, "a cast after the stop disqualifies the read")

  -- A stop with the bar full but the shot coming at once (no wind-up on this
  -- server) reads under the floor and is dropped: the model stays unmeasured.
  st.ranged.windupMeasured = false
  now = 513.0; fire("PLAYER_STARTED_MOVING")
  now = 514.3; fire("PLAYER_STOPPED_MOVING")   -- due 514.1
  now = 514.33; fire("PLAYER_SWING", 2.0, 2)   -- 0.23 late (the run), 0.03 after the stop
  ok(st.ranged.windupMeasured == false, "an immediate shot after the stop is no wind-up")
  W = module:WindupSamples()
  ok(W[#W].ev == "STOP->SHOT" and W[#W].sampled == nil, "...but the row is kept for the probe")

  -- The first shot on a new mob (after a kill: target changed and auto
  -- re-armed since the previous shot) waits for the pull as well: not read.
  st.ranged.windupMeasured = true
  local n2, ratio2 = #module:WindupSamples(), st.ranged.windupRatio
  now = 520.0; fire("PLAYER_SWING", 2.0, 2)
  now = 520.8; fire("PLAYER_TARGET_CHANGED")
  now = 520.85; fire("START_AUTOREPEAT_SPELL")
  now = 520.9; fire("PLAYER_STARTED_MOVING")
  now = 522.6; fire("PLAYER_STOPPED_MOVING")   -- due was 522.0
  now = 523.59; fire("PLAYER_SWING", 2.0, 2)   -- 0.99 after the stop
  ok(st.ranged.windupRatio == ratio2 and #module:WindupSamples() == n2, "first shot on a new target is not a read")
  -- ...and the next stop-gated shot on that target is.
  now = 524.0; fire("PLAYER_STARTED_MOVING")
  now = 525.3; fire("PLAYER_STOPPED_MOVING")   -- due 525.59
  now = 526.1; fire("PLAYER_SWING", 2.0, 2)    -- 0.51 late, 0.8 after the stop
  ok(#module:WindupSamples() == n2 + 1 and module:WindupSamples()[n2 + 1].sampled == "stop", "the second shot on the target reads normally")

  -- A move inside a running swing is a ring row with the bar's remaining time;
  -- an INTERRUPTED(75) is recorded once per burst (the client sends three).
  do
    local n3 = #module:WindupSamples()
    now = 530.0; fire("PLAYER_SWING", 2.0, 2)
    st.ranged.swingRemaining = 0.5
    now = 531.5; fire("PLAYER_STARTED_MOVING")
    local W3 = module:WindupSamples()
    ok(#W3 == n3 + 1 and W3[#W3].ev == "MOVE" and math.abs(W3[#W3].swingRemaining - 0.5) < 1e-9, "move inside the swing: a MOVE row with the remaining time")
    now = 531.71                                            -- the interrupt lands ~0.21 s after the move
    fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-75-a", 75)
    fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-75-a", 75)
    fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-75-a", 75)
    W3 = module:WindupSamples()
    ok(#W3 == n3 + 2 and W3[#W3].ev == "UNIT_SPELLCAST_INTERRUPTED", "three INTERRUPTED(75) in one frame are one row")
    ok(W3[#W3].sampled == "interrupt" and math.abs(W3[#W3].pairedMoveRem - 0.5) < 1e-9 and math.abs(W3[#W3].lag - 0.21) < 1e-9,
       "the interrupt is paired with its move: the wind-up was running 0.5 s before the shot")
    ok(st.ranged.windupSource == "interrupt" and math.abs(st.ranged.windupRatio - (0.25 + 0.02)) < 1e-9,
       "the band is now the interrupt edge: 0.5 / 2.0 plus the margin")
    -- A later interrupt further from the shot grows the edge; a nearer one does not shrink it.
    now = 531.8; fire("PLAYER_STOPPED_MOVING")
    now = 540.0; fire("PLAYER_SWING", 2.0, 2)
    st.ranged.swingRemaining = 0.3
    now = 541.7; fire("PLAYER_STARTED_MOVING")
    now = 541.9; fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-75-c", 75)
    ok(math.abs(st.ranged.windupRatio - 0.27) < 1e-9, "a nearer interrupt leaves the edge")
    now = 542.0; fire("PLAYER_STOPPED_MOVING")
    now = 542.7; fire("PLAYER_SWING", 2.0, 2)             -- 0.7 late, 0.7 after the stop
    W3 = module:WindupSamples()
    ok(W3[#W3].ev == "STOP->SHOT" and W3[#W3].restart == true and W3[#W3].sampled == "stop", "a stop-gated shot after an interrupt is a RESTART read (stop-by only)")
    ok(st.ranged.windupSource == "interrupt" and math.abs(st.ranged.windupRatio - 0.27) < 1e-9, "...and the band stays the interrupt edge")
    now = 544.0; fire("PLAYER_SWING", 2.0, 2)
    st.ranged.swingRemaining = 0.6
    now = 545.4; fire("PLAYER_STARTED_MOVING")
    now = 545.6; fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-75-d", 75)
    ok(math.abs(st.ranged.windupRatio - (0.3 + 0.02)) < 1e-9, "an interrupt further from the shot grows the edge")
    -- A move with no interrupt within the window pairs with nothing.
    now = 545.7; fire("PLAYER_STOPPED_MOVING")
    now = 548.0; fire("PLAYER_SWING", 2.0, 2)
    st.ranged.swingRemaining = 0.9
    now = 549.1; fire("PLAYER_STARTED_MOVING")
    now = 549.7; fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-75-e", 75)   -- 0.6 s later: not this move's
    ok(math.abs(st.ranged.windupRatio - 0.32) < 1e-9, "an interrupt outside the pairing window is not a read")
    now = 549.8; fire("PLAYER_STOPPED_MOVING")
  end

  -- Reads persist per character and come back measured on the next login.
  do
    local savedS, savedI = module._stopRatios, module._interruptRatios
    ok(Nock.db == nil, "test harness has no db (saves are no-ops without one)")
    Nock.db = { char = {} }
    module:SaveWindupReads()
    local sv = Nock.db.char.foreverWindupReads
    ok(#sv.stops == #savedS and sv.stops[1] == savedS[1] and #sv.interrupts == #savedI and sv.interrupts[#savedI] == savedI[#savedI], "SaveWindupReads writes both rings to db.char")
    st.ranged.windupMeasured, st.ranged.windupRatio, st.ranged.windupSource = false, 0.5 / 3.0, nil
    module._stopRatios, module._interruptRatios = {}, {}
    module:RestoreWindupReads()
    ok(st.ranged.windupMeasured == true and st.ranged.windupSource == "interrupt" and math.abs(st.ranged.windupRatio - 0.32) < 1e-9, "RestoreWindupReads: the interrupt edge comes back")
    Nock.db.char.foreverWindupReads = { 0.3, "junk", 5, 0.4 }     -- the first, flat shape: stop reads
    module._stopRatios, module._interruptRatios = {}, {}
    module:RestoreWindupReads()
    ok(#module._stopRatios == 2 and st.ranged.windupSource == "stop" and st.ranged.windupRatio == 0.3 and st.ranged.stopByRatio == 0.4, "a flat saved list restores as stop reads, junk dropped")
    Nock.db.char.foreverWindupReads = {}
    st.ranged.windupMeasured = false
    module._stopRatios, module._interruptRatios = {}, {}
    module:RestoreWindupReads()
    ok(st.ranged.windupMeasured == false, "nothing saved: stays unmeasured")
    module._stopRatios, module._interruptRatios = { 0.4 }, { 0.3 }; st.ranged.windupMeasured = true
    module:ResetWindupReads()
    ok(#module._stopRatios == 0 and #module._interruptRatios == 0 and next(Nock.db.char.foreverWindupReads) == nil
       and st.ranged.windupMeasured == false and st.ranged.windupSource == nil and st.ranged.stopByRatio == nil
       and math.abs(st.ranged.windupRatio - 0.5 / 3.0) < 1e-9, "ResetWindupReads clears both rings, the save and the flags")
    Nock.db = nil
    module._stopRatios, module._interruptRatios = savedS, savedI
    module:ApplyWindupEstimate()
  end

  -- The median: a wild read does not move the estimate the way an average would.
  local UM = module.UpperMedian
  ok(UM({ 0.3 }) == 0.3 and UM({ 0.3, 0.5 }) == 0.5 and UM({ 0.5, 0.3, 0.4 }) == 0.4, "upper median: single, even (higher middle), odd")
  ok(UM({ 0.31, 0.34, 0.30, 0.45 }) == 0.34, "one outlier among four leaves the middle")

  -- The dead-zone spam and the shot's own SUCCEEDED stay out of the feed ring.
  local n1 = #module:WindupSamples()
  fire("UNIT_SPELLCAST_FAILED", "player", "x", 75)
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 75)
  ok(#module:WindupSamples() == n1, "FAILED/SUCCEEDED(75) are not ring rows")
end

print(("forever_swing: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
