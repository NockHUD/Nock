-- Tests/weave_sounds_test.lua
-- Modules/WeaveSounds.lua: a Raptor Strike that lands and a Windfury proc (extra attacks) earn their cue; only
-- your own events, only when switched on, misses are silent, the Windfury name falls back to "any extra attacks".
-- Run from the repo root: luajit Tests/weave_sounds_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local played = {}
_G.PlaySoundFile = function(path, ch) played[#played + 1] = { path = path, ch = ch } end
_G.UnitGUID = function() return "ME" end
local names = { [2973] = "Raptor Strike", [25504] = "Windfury Attack" }
_G.GetSpellInfo = function(id) return names[id] end
local ev
_G.CombatLogGetCurrentEventInfo = function()
  return 0, ev.sub, false, ev.src, "x", 0, 0, "T", "t", 0, 0, ev.id, ev.name, 1
end

local Nock = { db = { profile = {} }, Constants = { SpellID = { RAPTOR_STRIKE = 2973, WINDFURY_ATTACK = 25504 } } }
local WS
function Nock:NewModule()
  WS = {}
  function WS:RegisterEvent() end
  return WS
end
local libs = { ["AceAddon-3.0"] = { GetAddon = function() return Nock end },
               ["LibSharedMedia-3.0"] = { Fetch = function(_, _, n) return "snd/" .. n .. ".ogg" end } }
_G.LibStub = function(name) return libs[name] end
dofile("Modules/WeaveSounds.lua")
ok(type(WS.Classify) == "function", "module loads")
WS:OnEnable()

local function fire(sub, src, id, name)
  ev = { sub = sub, src = src, id = id, name = name }
  WS:COMBAT_LOG_EVENT_UNFILTERED()
end
local function reset(p) played = {}; Nock.db.profile = p or {} end

-- classify (pure)
local N = { raptor = "Raptor Strike", windfury = "Windfury Attack" }
ok(WS.Classify("SPELL_DAMAGE", "ME", "ME", 2973, "Raptor Strike", N) == "raptor", "classify: own Raptor hit")
ok(WS.Classify("SPELL_MISSED", "ME", "ME", 2973, "Raptor Strike", N) == nil, "classify: a miss is not a hit")
ok(WS.Classify("SPELL_DAMAGE", "OTHER", "ME", 2973, "Raptor Strike", N) == nil, "classify: someone else's Raptor")
ok(WS.Classify("SPELL_EXTRA_ATTACKS", "ME", "ME", 25504, "Windfury Attack", N) == "windfury", "classify: own Windfury proc")
ok(WS.Classify("SPELL_EXTRA_ATTACKS", "ME", "ME", 1, "Thrash", N) == nil, "classify: other extra attacks with the name known")
ok(WS.Classify("SPELL_EXTRA_ATTACKS", "ME", "ME", 1, "Whatever", { raptor = "Raptor Strike" }) == "windfury", "classify: name unresolved -> any extra attacks of yours")
ok(WS.Classify("SPELL_DAMAGE", "ME", "ME", 75, "Auto Shot", N) == nil, "classify: a shot is not a weave")

-- the switches and the sounds
reset()
fire("SPELL_DAMAGE", "ME", 2973, "Raptor Strike")
ok(#played == 0, "off by default: silent")
reset({ weaveRaptorHitEnabled = true, weaveRaptorHitSound = "Ping", deadZoneSoundChannel = "SFX" })
fire("SPELL_DAMAGE", "ME", 2973, "Raptor Strike")
ok(#played == 1 and played[1].path == "snd/Ping.ogg" and played[1].ch == "SFX", "raptor hit -> the picked sound on the dead-zone channel")
fire("SPELL_EXTRA_ATTACKS", "ME", 25504, "Windfury Attack")
ok(#played == 1, "windfury switch off -> no cue")
reset({ weaveWfProcEnabled = true, weaveWfProcSound = "Horn" })
fire("SPELL_EXTRA_ATTACKS", "ME", 25504, "Windfury Attack")
ok(#played == 1 and played[1].path == "snd/Horn.ogg" and played[1].ch == "Master", "windfury proc -> its sound, Master by default")
reset({ weaveWfProcEnabled = true, weaveWfProcSound = "None" })
fire("SPELL_EXTRA_ATTACKS", "ME", 25504, "Windfury Attack")
ok(#played == 0, "sound None -> silent")

print(("weave_sounds_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
