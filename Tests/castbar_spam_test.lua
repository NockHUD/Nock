-- Tests/castbar_spam_test.lua
-- Spamming a cast's button must not hide its bar. A failed re-press of the
-- spell already being cast fires its own SPELL_CAST_FAILED (CLEU) and/or
-- UNIT_SPELLCAST_STOP for the failed ATTEMPT while the first cast keeps
-- running; the clear paths must ask the client whether the cast is still in
-- flight before taking the bar down (seen live: mount bar gone on the second
-- press). Run from the repo root: luajit Tests/castbar_spam_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local now = 100
_G.GetTime = function() return now end
_G.UnitGUID = function() return "player-guid" end
_G.GetSpellInfo = function(id) return "Spell " .. id, nil, "icon-" .. id, 1500 end
_G.GetRangedHaste = function() return 0 end
_G.UnitChannelInfo = function() return nil end

-- The live cast as the client reports it. nil = nothing casting.
local castingInfo = nil
_G.UnitCastingInfo = function()
  if not castingInfo then return nil end
  return castingInfo.name, nil, "tex", castingInfo.startMs, castingInfo.endMs,
         nil, nil, nil, castingInfo.spellId
end

local cleuArgs
_G.CombatLogGetCurrentEventInfo = function()
  return cleuArgs[1], cleuArgs[2], cleuArgs[3], cleuArgs[4], nil, nil, nil,
         nil, nil, nil, nil, cleuArgs[12], cleuArgs[13]
end

local addon = { Constants = {}, state = {} }
local module
function addon:NewModule(name, ...)
  module = { name = name }
  function module:RegisterEvent() end
  function module:RegisterMessage() end
  function module:Print() end
  return module
end
_G.LibStub = function(name, silent)
  if name == "AceAddon-3.0" then return { GetAddon = function() return addon end } end
  if silent then return nil end
  return {}
end

dofile("Core/Constants.lua")
dofile("Config/Defaults.lua")
dofile("Core/State.lua")
addon.db = { profile = {} }
for k, v in pairs(addon.Defaults.profile) do addon.db.profile[k] = v end
addon.db.profile.castBarNonCombatCasts = true

dofile("Modules/CastBar.lua")
local CB = module
CB.playerGUID = "player-guid"

local state = addon.state
local MOUNT, STEADY = 24252, addon.Constants.SpellID.STEADY_SHOT

local function cleu(subEvent, spellId)
  cleuArgs = { 0, subEvent, false, "player-guid", [12] = spellId, [13] = "Spell " .. spellId }
  CB:COMBAT_LOG_EVENT_UNFILTERED()
end

--------------------------------------------------------------------------------
-- 1. Mount spam (UNIT_SPELLCAST path): a STOP for the failed second press
--    while the cast is still in flight must not clear the bar.
--------------------------------------------------------------------------------
now = 100
castingInfo = { name = "Swift Tiger", spellId = MOUNT, startMs = 100000, endMs = 103000 }
CB:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player")
ok(state.player.casting and state.player.casting.spellId == MOUNT, "mount cast raises the bar")

now = 101
CB:UNIT_SPELLCAST_STOP("UNIT_SPELLCAST_STOP", "player")
ok(state.player.casting and state.player.casting.spellId == MOUNT,
   "spurious STOP (failed re-press) keeps the bar while the cast is live")

CB:UNIT_SPELLCAST_INTERRUPTED("UNIT_SPELLCAST_INTERRUPTED", "player")
ok(state.player.casting and state.player.casting.spellId == MOUNT,
   "spurious INTERRUPTED keeps the bar while the cast is live")

-- The cast is genuinely gone (completed or cancelled): STOP clears.
castingInfo = nil
CB:UNIT_SPELLCAST_STOP("UNIT_SPELLCAST_STOP", "player")
ok(state.player.casting == nil, "STOP with no live cast clears the bar")

--------------------------------------------------------------------------------
-- 2. CLEU spam (Steady Shot): SPELL_CAST_FAILED for the same spellId while the
--    cast is still in flight must not clear the bar.
--------------------------------------------------------------------------------
now = 200
castingInfo = { name = "Steady Shot", spellId = STEADY, startMs = 200000, endMs = 201500 }
cleu("SPELL_CAST_START", STEADY)
ok(state.player.casting and state.player.casting.spellId == STEADY, "Steady cast raises the bar")

now = 200.5
cleu("SPELL_CAST_FAILED", STEADY)
ok(state.player.casting and state.player.casting.spellId == STEADY,
   "spurious SPELL_CAST_FAILED (spam) keeps the bar while the cast is live")

-- Genuine failure (moved: the client has already dropped the cast).
castingInfo = nil
cleu("SPELL_CAST_FAILED", STEADY)
ok(state.player.casting == nil, "SPELL_CAST_FAILED with no live cast clears the bar")

-- SUCCESS always clears, live cast or not (it landed).
now = 300
castingInfo = { name = "Steady Shot", spellId = STEADY, startMs = 300000, endMs = 301500 }
cleu("SPELL_CAST_START", STEADY)
cleu("SPELL_CAST_SUCCESS", STEADY)
ok(state.player.casting == nil, "SPELL_CAST_SUCCESS clears even while UnitCastingInfo lags")

--------------------------------------------------------------------------------
-- 3. Keeping the bar resyncs its timing to the client's (server-authoritative;
--    a pushback between press and spurious event is picked up for free).
--------------------------------------------------------------------------------
now = 400
castingInfo = { name = "Steady Shot", spellId = STEADY, startMs = 400000, endMs = 401500 }
cleu("SPELL_CAST_START", STEADY)
castingInfo.endMs = 401900   -- pushback
now = 400.5
cleu("SPELL_CAST_FAILED", STEADY)
local c = state.player.casting
ok(c and math.abs(c.endTime - 401.9) < 1e-6, "kept bar resyncs endTime from UnitCastingInfo")
castingInfo = nil
cleu("SPELL_CAST_FAILED", STEADY)

--------------------------------------------------------------------------------
-- 4. A FAILED for a DIFFERENT spell never touches the running cast.
--------------------------------------------------------------------------------
now = 500
castingInfo = { name = "Steady Shot", spellId = STEADY, startMs = 500000, endMs = 501500 }
cleu("SPELL_CAST_START", STEADY)
cleu("SPELL_CAST_FAILED", 1978)  -- Serpent Sting pressed too early
ok(state.player.casting and state.player.casting.spellId == STEADY,
   "FAILED for another spell leaves the bar alone")

print(string.format("castbar_spam_test: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
