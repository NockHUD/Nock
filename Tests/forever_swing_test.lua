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
fire("PLAYER_SWING", 1.9, 1)
ok(st.ranged.swingDuration == 2.174 and st.melee.swingDuration == 2.6, "off-hand event ignored")

fire("START_AUTOREPEAT_SPELL")
ok(st.ranged.repeating == true, "auto-repeat on")
fire("STOP_AUTOREPEAT_SPELL")
ok(st.ranged.repeating == false, "auto-repeat off")

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
now = 201.0; fire("PLAYER_STOPPED_MOVING")
now = 201.45; fire("PLAYER_SWING", 1.9, 2)
S = module:Samples()
ok(S[#S].moving == false and math.abs(S[#S].stillFor - 0.45) < 1e-9, "shot after stopping carries the still time")

print(("forever_swing: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
