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
-- THE BAND (2026-10-18 design): a fixed share of the reload, published from
-- switch-on reads, seeded until one exists, moved only in steps. No other
-- feed moves it; their rows stay for the probe.
do
  _G.UnitCastingInfo = function(u)
    if u == "player" and _G.__autoCast then return unpack(_G.__autoCast) end
  end
  st.player.inCombat = true
  st.network = st.network or {}
  st.network.latencyMs = 110
  fire("PLAYER_ENTERING_WORLD")
  ok(st.ranged.windupMeasured == true and st.ranged.windupSource == "seed", "Forever starts on the seed share: measured, source seed")
  ok(module.events["UNIT_SPELLCAST_START"] and module.events["UNIT_SPELLCAST_STOP"]
     and module.events["UNIT_SPELLCAST_SUCCEEDED"] and module.events["UNIT_SPELLCAST_INTERRUPTED"], "cast events registered")
  now = 400
  fire("PLAYER_SWING", 2.232, 2)
  ok(math.abs(st.ranged.windupRatio - (0.24 + 0.11 / 2.232)) < 1e-6, "ratio = seed server share + rtt / reload")
  st.ranged.windup = st.ranged.windupRatio * st.ranged.swingDuration   -- what the tick does
  ok(math.abs(Nock.AutoShotWindup() - st.ranged.windup) < 1e-9, "views read the share; the queue window never stands in")
  local band = st.ranged.windupRatio

  -- Cast-edge and release feeds (never seen on this client): tagged rows, band untouched.
  now = 401.65
  _G.__autoCast = { "Auto Shot", "", 132369, 401650, 402000, false, "cast-a", false, 75 }
  fire("UNIT_SPELLCAST_START", "player", "cast-a", 75)
  now = 402.0
  _G.__autoCast = nil
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 75)
  fire("UNIT_SPELLCAST_STOP", "player", "cast-a", 75)
  fire("PLAYER_SWING", 2.232, 2)
  local W = module:WindupSamples()
  ok(W[1].ev == "UNIT_SPELLCAST_START" and W[1].sampled == "cast" and W[1].castStart == 401.65 and W[1].castEnd == 402.0, "a client cast window is a tagged row with its times")
  ok(math.abs(st.ranged.windupRatio - band) < 1e-9, "...and does not move the band")
  now = 403.65
  fire("UNIT_SPELLCAST_START", "player", "cast-b", 75)
  now = 404.0
  fire("PLAYER_SWING", 2.232, 2)
  W = module:WindupSamples()
  local lastRel
  for i = 1, #W do if W[i].ev == "RELEASE" then lastRel = W[i] end end
  ok(lastRel and lastRel.sampled == "release" and math.abs(lastRel.measured - 0.35) < 1e-9, "a release read is a tagged row")
  ok(math.abs(st.ranged.windupRatio - band) < 1e-9, "...and does not move the band either")
  _G.UnitCastingInfo = nil
end

-- Stop-gated reads: rows and the stop-by edge; the band stays the share.
do
  fire("PLAYER_ENTERING_WORLD")
  st.player.inCombat = true
  st.network.latencyMs = 60
  now = 500
  fire("PLAYER_SWING", 2.0, 2)          -- due at 502.0
  local band = st.ranged.windupRatio
  ok(math.abs(band - (0.24 + 0.06 / 2.0)) < 1e-6, "the rtt part follows the reload and the ping (quantised)")
  now = 501.0; fire("PLAYER_STARTED_MOVING")
  now = 502.3; fire("PLAYER_STOPPED_MOVING")   -- bar full since 502.0
  now = 502.3 + 0.41                              -- shot 0.41 s after the stop
  fire("PLAYER_SWING", 2.0, 2)
  local W = module:WindupSamples()
  local last = W[#W]
  ok(last.ev == "STOP->SHOT" and math.abs(last.raw - 0.41) < 1e-9 and math.abs(last.lessRtt - 0.35) < 1e-9 and last.sampled == "stop",
     "a stop-gated shot is a tagged row with raw, the rtt-corrected value and the source")
  ok(math.abs(last.late - 0.71) < 1e-9, "...and how late the shot was")
  ok(math.abs(st.ranged.stopByRatio - 0.205) < 1e-9, "stop-by = the one read")
  ok(math.abs(st.ranged.windupRatio - band) < 1e-9 and st.ranged.windupSource == "seed", "the band does not move on a stop read")

  now = 503.5; fire("PLAYER_STARTED_MOVING")
  now = 504.41; fire("PLAYER_STOPPED_MOVING")   -- due is 504.71: 0.3 s left
  now = 504.71 + 0.5; fire("PLAYER_SWING", 2.0, 2)   -- 0.5 late = 0.8 after the stop
  ok(math.abs(st.ranged.stopByRatio - 0.4) < 1e-9, "stop-by edge = upper median of {0.205, 0.4}")
  W = module:WindupSamples()
  ok(W[#W].ev == "STOP->SHOT" and math.abs(W[#W].late - 0.5) < 1e-9 and W[#W].sampled == "stop", "the row carries the lateness")

  -- A stop while the bar was still running with the shot ON TIME: no read.
  local n0 = #module:WindupSamples()
  now = 505.8; fire("PLAYER_STARTED_MOVING")
  now = 506.2; fire("PLAYER_STOPPED_MOVING")   -- due is 507.21
  now = 507.21; fire("PLAYER_SWING", 2.0, 2)
  ok(#module:WindupSamples() == n0, "a stop with the shot on time leaves no stop row")
  -- An old stop (before the previous shot) is spent, even on a late shot.
  now = 509.6; fire("PLAYER_SWING", 2.0, 2)   -- 0.39 late, no stop since the last shot
  ok(#module:WindupSamples() == n0, "a late shot without a fresh stop: no stop read")
  -- A cast edge after the stop may have pushed the shot: not read.
  now = 510.0; fire("PLAYER_STARTED_MOVING")
  now = 511.3; fire("PLAYER_STOPPED_MOVING")   -- due 511.6
  now = 511.4; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "ms", 2643)
  now = 512.1; fire("PLAYER_SWING", 2.0, 2)    -- 0.5 late
  ok(#module:WindupSamples() == n0, "a cast after the stop disqualifies the read")
  -- An immediate shot after the stop reads under the floor: the row is kept, unsampled.
  now = 513.0; fire("PLAYER_STARTED_MOVING")
  now = 514.3; fire("PLAYER_STOPPED_MOVING")   -- due 514.1
  now = 514.33; fire("PLAYER_SWING", 2.0, 2)   -- 0.03 after the stop
  W = module:WindupSamples()
  ok(W[#W].ev == "STOP->SHOT" and W[#W].sampled == nil, "an immediate shot after the stop is a kept, unsampled row")

  -- The first shot on a new mob (target changed, auto re-armed while the
  -- bar still ran) is neither a stop read nor a switch-on read.
  local ratio2 = st.ranged.windupRatio
  now = 520.0; fire("PLAYER_SWING", 2.0, 2)
  now = 520.8; fire("PLAYER_TARGET_CHANGED")
  now = 520.85; fire("START_AUTOREPEAT_SPELL")
  now = 520.9; fire("PLAYER_STARTED_MOVING")
  now = 522.6; fire("PLAYER_STOPPED_MOVING")   -- due was 522.0
  now = 523.59; fire("PLAYER_SWING", 2.0, 2)   -- 0.99 after the stop
  W = module:WindupSamples()
  ok(st.ranged.windupRatio == ratio2, "first shot on a new target: the band stays")
  ok(W[#W].ev == "ON->SHOT" and W[#W].sampled == nil and W[#W].idle == false, "...its ON->SHOT row says the bar was running")
  ok(W[#W - 1].ev == "AUTO_ON", "...after the AUTO_ON row")
  -- ...and the next stop-gated shot on that target reads normally.
  now = 524.0; fire("PLAYER_STARTED_MOVING")
  now = 525.3; fire("PLAYER_STOPPED_MOVING")   -- due 525.59
  now = 526.1; fire("PLAYER_SWING", 2.0, 2)    -- 0.51 late, 0.8 after the stop
  W = module:WindupSamples()
  ok(W[#W].ev == "STOP->SHOT" and W[#W].sampled == "stop", "the second shot on the target reads normally")

  -- Moves inside a running swing and INTERRUPTED(75): probe rows, paired,
  -- once per burst; the band is not theirs to move.
  do
    local n3, band = #module:WindupSamples(), st.ranged.windupRatio
    now = 530.0; fire("PLAYER_SWING", 2.0, 2)
    st.ranged.swingRemaining = 0.5
    now = 531.5; fire("PLAYER_STARTED_MOVING")
    local W3 = module:WindupSamples()
    ok(#W3 == n3 + 1 and W3[#W3].ev == "MOVE" and math.abs(W3[#W3].swingRemaining - 0.5) < 1e-9, "move inside the swing: a MOVE row with the remaining time")
    ok(math.abs((W3[#W3].swingDuration or 0) - 2.0) < 1e-9, "...and the reload it was made in (the haste question)")
    now = 531.71
    fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-75-a", 75)
    fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-75-a", 75)
    fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-75-a", 75)
    W3 = module:WindupSamples()
    ok(#W3 == n3 + 2 and W3[#W3].ev == "UNIT_SPELLCAST_INTERRUPTED", "three INTERRUPTED(75) in one frame are one row")
    ok(W3[#W3].sampled == "interrupt" and math.abs(W3[#W3].pairedMoveRem - 0.5) < 1e-9 and math.abs(W3[#W3].lag - 0.21) < 1e-9,
       "the interrupt is paired with its move")
    ok(math.abs(st.ranged.windupRatio - band) < 1e-9 and st.ranged.windupSource == "seed", "an interrupt read does not move the band")
    now = 531.8; fire("PLAYER_STOPPED_MOVING")
    -- A fresh press since the last shot: the interrupted wind-up is not the bar's.
    now = 552.0; fire("PLAYER_SWING", 2.0, 2)
    now = 552.5; fire("PLAYER_TARGET_CHANGED")
    st.ranged.swingRemaining = 1.5
    now = 552.7; fire("PLAYER_STARTED_MOVING")
    now = 552.9; fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-75-f", 75)
    W3 = module:WindupSamples()
    ok(W3[#W3].ev == "UNIT_SPELLCAST_INTERRUPTED" and W3[#W3].sampled == nil and W3[#W3].freshPress, "an interrupt after a target change is tagged, not sampled")
    now = 553.0; fire("PLAYER_STOPPED_MOVING")
    -- A move with no interrupt within the window pairs with nothing.
    now = 556.0; fire("PLAYER_SWING", 2.0, 2)
    st.ranged.swingRemaining = 0.9
    now = 557.1; fire("PLAYER_STARTED_MOVING")
    now = 557.7; fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-75-e", 75)   -- 0.6 s later: not this move's
    W3 = module:WindupSamples()
    ok(W3[#W3].sampled == nil and W3[#W3].pairedMoveRem == nil, "an interrupt outside the pairing window is not paired")
    now = 557.8; fire("PLAYER_STOPPED_MOVING")
  end

  -- The auto-repeat toggles are ring rows (the switch-on question).
  do
    local n = #module:WindupSamples()
    now = 570.0; fire("START_AUTOREPEAT_SPELL")
    now = 571.0; fire("STOP_AUTOREPEAT_SPELL")
    local W = module:WindupSamples()
    ok(#W == n + 2 and W[#W - 1].ev == "AUTO_ON" and W[#W].ev == "AUTO_OFF" and W[#W - 1].t == 570.0, "START/STOP_AUTOREPEAT_SPELL leave AUTO_ON / AUTO_OFF rows")
  end

  -- THE SWITCH-ON FEED. Idle bar, press, still, the shot 0.655 s later at a
  -- 2.232 s reload with rtt 0.110: server share (0.655 - 0.11) / 2.232.
  do
    Nock.db = { char = {} }
    st.network.latencyMs = 110
    now = 600.0; fire("PLAYER_SWING", 2.232, 2)   -- a shot long ago
    now = 610.0; fire("STOP_AUTOREPEAT_SPELL")
    now = 620.0; fire("START_AUTOREPEAT_SPELL")   -- bar idle since 602.232
    now = 620.655; fire("PLAYER_SWING", 2.232, 2)
    local W = module:WindupSamples()
    local share1 = (0.655 - 0.11) / 2.232
    ok(W[#W].ev == "ON->SHOT" and W[#W].sampled == "switch-on" and math.abs(W[#W].share - share1) < 1e-9, "an idle switch-on reads the wind-up as a server share")
    ok(st.ranged.windupSource == "switch-on", "source: switch-on")
    ok(math.abs(st.ranged.windupRatio - (0.24 + 0.11 / 2.232)) < 1e-6, "one read inside the step leaves the published share on the seed")
    ok(type(Nock.db.char.foreverWindupShares) == "table" and #Nock.db.char.foreverWindupShares.any == 1, "the read is saved under the weapon key")
    -- Reads well off the seed: the median crosses the step and the share moves ONCE.
    for i = 1, 3 do
      now = 700 + i * 20; fire("STOP_AUTOREPEAT_SPELL")
      now = 710 + i * 20; fire("START_AUTOREPEAT_SPELL")
      now = 710 + i * 20 + 0.80; fire("PLAYER_SWING", 2.232, 2)   -- share (0.80 - 0.11) / 2.232
    end
    local share2 = (0.80 - 0.11) / 2.232
    ok(math.abs(st.ranged.windupRatio - (share2 + 0.11 / 2.232)) < 1e-6, "the median moved past the step: the share steps to it")
    local pub = module:WindupShare()
    ok(math.abs(pub - share2) < 1e-9, "WindupShare reports the published server share")
    -- A read that leaves the median where it is leaves the band alone.
    now = 800; fire("STOP_AUTOREPEAT_SPELL")
    now = 810; fire("START_AUTOREPEAT_SPELL")
    now = 810.7; fire("PLAYER_SWING", 2.232, 2)   -- share 0.264: median of 5 stays 0.309
    ok(math.abs(st.ranged.windupRatio - (share2 + 0.11 / 2.232)) < 1e-6, "a read inside the step: no move")
    -- Disqualifiers leave a tagged, unsampled row.
    local function pressAndShoot(t, between, shotAt)
      now = t; fire("STOP_AUTOREPEAT_SPELL")
      now = t + 5; fire("START_AUTOREPEAT_SPELL")
      if between then between(t + 5) end
      now = shotAt or (t + 5.655); fire("PLAYER_SWING", 2.232, 2)
      local W = module:WindupSamples()
      return W[#W]
    end
    local nReads = #module._onReads
    local row = pressAndShoot(900, function(t0) now = t0 + 0.2; fire("PLAYER_STARTED_MOVING"); now = t0 + 0.3; fire("PLAYER_STOPPED_MOVING") end)
    ok(row.ev == "ON->SHOT" and row.sampled == nil and row.moved == true, "a move between press and shot: not a read")
    row = pressAndShoot(920, function(t0) now = t0 + 0.2; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "ms", 2643) end)
    ok(row.sampled == nil and row.cast == true, "a cast between press and shot: not a read")
    st.ranged.targetInRange = false
    row = pressAndShoot(940)
    ok(row.sampled == nil and row.inRange == false, "target out of range at the press: not a read")
    st.ranged.targetInRange = nil
    row = pressAndShoot(960, nil, 960 + 5 + 1.5)
    ok(row.sampled == nil and math.abs(row.read - 1.5) < 1e-9, "a shot 1.5 s after the press was waiting for more than a wind-up: not a read")
    ok(#module._onReads == nReads, "none of them entered the ring")
    -- Persistence: the ring comes back per weapon; the old key is dropped.
    local savedReads = #module._onReads
    module._onReads, module._shareServer, module._onMedian = {}, nil, nil
    Nock.db.char.foreverWindupReads = { stops = { 0.3 }, interrupts = { 0.4 } }
    module:RestoreWindupReads()
    ok(#module._onReads == savedReads and st.ranged.windupSource == "switch-on" and math.abs(module:WindupShare() - share2) < 1e-9, "RestoreWindupReads brings the weapon's reads and share back")
    ok(Nock.db.char.foreverWindupReads == nil, "the pre-2026-10-18 reads key is dropped")
    -- A new ranged weapon starts its own reads (seed until its first pull).
    _G.GetInventoryItemID = function(unit, slot) return (unit == "player" and slot == 18) and 1234 or nil end
    fire("PLAYER_EQUIPMENT_CHANGED")
    ok(module._onKey == "1234" and #module._onReads == 0 and st.ranged.windupSource == "seed", "a new ranged weapon: own key, no reads, seed share")
    _G.GetInventoryItemID = nil
    fire("PLAYER_EQUIPMENT_CHANGED")
    ok(module._onKey == "any" and #module._onReads == savedReads, "back on the old weapon: its reads return")
    -- Reset: both rings, the save and back to the seed.
    module:ResetWindupReads()
    ok(#module._onReads == 0 and next(Nock.db.char.foreverWindupShares) == nil and st.ranged.windupSource == "seed"
       and st.ranged.windupMeasured == true and st.ranged.stopByRatio == nil, "ResetWindupReads: rings cleared, save cleared, seed share, still measured")
    Nock.db = nil
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
