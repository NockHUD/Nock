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

--------------------------------------------------------------------------------
-- 5. The weave regression (1.1.5 report: "the cast bar doesn't show after
--    weaves"). A movement-cancel's CLEU SPELL_CAST_FAILED can land in the SAME
--    FRAME, BEFORE UnitCastingInfo drops the cast — the swallow guard then
--    keeps a dead record in state.player.casting, and CastBarSource lets it
--    mask the Auto Shot wind-up for its remaining time + 0.5s. The event may
--    be swallowed on its own frame, but the next tick's Refresh must notice
--    the cast is gone and take the bar down.
--------------------------------------------------------------------------------
now = 600
castingInfo = { name = "Steady Shot", spellId = STEADY, startMs = 600000, endMs = 601500 }
cleu("SPELL_CAST_START", STEADY)
now = 600.4
cleu("SPELL_CAST_FAILED", STEADY)    -- step-in cancel; client state not yet updated
ok(state.player.casting ~= nil, "same-frame cancel: the event itself is swallowed")
castingInfo = nil                    -- ...and one frame later the client agrees it's gone
now = 600.43
CB:Refresh(state)
ok(state.player.casting == nil,
   "a swallowed genuine cancel is cleared on the next tick (weave regression)")

-- The spam press survives the recheck: the cast is still live next tick.
now = 700
castingInfo = { name = "Steady Shot", spellId = STEADY, startMs = 700000, endMs = 701500 }
cleu("SPELL_CAST_START", STEADY)
now = 700.5
cleu("SPELL_CAST_FAILED", STEADY)    -- failed re-press; cast keeps running
now = 700.53
CB:Refresh(state)
ok(state.player.casting ~= nil and state.player.casting.spellId == STEADY,
   "a spam press still keeps the bar through the next-tick recheck")
castingInfo = nil
cleu("SPELL_CAST_FAILED", STEADY)

-- Same race on the mount (UNIT_SPELLCAST) path.
now = 800
castingInfo = { name = "Swift Tiger", spellId = MOUNT, startMs = 800000, endMs = 803000 }
CB:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player")
now = 800.4
CB:UNIT_SPELLCAST_INTERRUPTED("UNIT_SPELLCAST_INTERRUPTED", "player")
castingInfo = nil
now = 800.43
CB:Refresh(state)
ok(state.player.casting == nil,
   "a swallowed mount cancel is cleared on the next tick")

--------------------------------------------------------------------------------
-- 6. Wind-up span floor (the "insta 100% into fade" weave report). A weave
--    re-arm is held to the client's grid tick, so its CAST_START(75) fires
--    with the predicted release (swingStart + swingDuration) only a few ms
--    ahead — the release-anchored record then spans ~0 and the bar is born
--    full. The wind-up always runs its full haste-scaled length from its
--    start, so the record must span at least ~the measured wind-up.
--------------------------------------------------------------------------------
local AUTO = addon.Constants.SpellID.AUTO_SHOT
now = 900
state.ranged.swingStart = 900.05 - 2.174   -- predicted release 50ms ahead
state.ranged.swingDuration = 2.174
state.ranged.windup = 0.365
cleu("SPELL_CAST_START", AUTO)
local a = state.player.autoShotCast
ok(a ~= nil, "wind-up CAST_START raises the wind-up record")
ok(a and (a.endTime - a.startTime) > 0.3,
   "a razor-thin release anchor still spans the measured wind-up (weave re-arm)")

-- An on-time wind-up keeps the release anchor's precision.
now = 910
state.ranged.swingStart = 910.360 - 2.174  -- release 360ms ahead == the wind-up
cleu("SPELL_CAST_START", AUTO)
a = state.player.autoShotCast
ok(a and math.abs(a.endTime - 910.360) < 1e-6,
   "an on-time wind-up still anchors to the predicted release")

-- The Refresh re-pin must not shrink a healthy bar into the floor either.
now = 910.1
state.ranged.swingStart = 910.15 - 2.174   -- grid drifted: release now 50ms ahead
CB:Refresh(state)
a = state.player.autoShotCast
ok(a and (a.endTime - a.startTime) > 0.3,
   "the per-tick re-pin refuses a release that would shrink the bar below the wind-up")
state.player.autoShotCast = nil
state.ranged.swingStart, state.ranged.swingDuration, state.ranged.windup = 0, 0, 0

--------------------------------------------------------------------------------
-- 7. Wind-up spam (the "mash !Auto Shot after a weave" report). A re-press of
--    !Auto Shot landing inside the wind-up logs SPELL_CAST_FAILED(75) for the
--    failed ATTEMPT while the real wind-up keeps running — and there is no
--    UnitCastingInfo to disambiguate (it returns nil for Auto Shot), so FAILED
--    must not clear the record at all. SUCCESS (the release) clears; a wind-up
--    whose release never comes is Refresh's stale cleanup (endTime + 0.5).
--------------------------------------------------------------------------------
now = 1000
state.ranged.swingStart = 1000.360 - 2.174   -- release 360ms ahead
state.ranged.swingDuration = 2.174
state.ranged.windup = 0.365
cleu("SPELL_CAST_START", AUTO)
ok(state.player.autoShotCast ~= nil, "wind-up raised for the spam section")

now = 1000.1
cleu("SPELL_CAST_FAILED", AUTO)      -- mashed !Auto Shot: failed re-press
ok(state.player.autoShotCast ~= nil,
   "FAILED(75) from a mashed re-press keeps the wind-up bar")

now = 1000.2
cleu("SPELL_CAST_FAILED", AUTO)      -- and again
ok(state.player.autoShotCast ~= nil,
   "repeated FAILED(75) still keeps the wind-up bar")

cleu("SPELL_CAST_SUCCESS", AUTO)     -- the arrow leaves
ok(state.player.autoShotCast == nil, "SUCCESS(75) clears the wind-up")

-- A genuinely cancelled wind-up (no SUCCESS ever) is torn down by the stale
-- cleanup once its predicted release is 0.5s past.
now = 1010
state.ranged.swingStart = 1010.360 - 2.174
cleu("SPELL_CAST_START", AUTO)
ok(state.player.autoShotCast ~= nil, "wind-up raised for the stale section")
cleu("SPELL_CAST_FAILED", AUTO)      -- a cancel that happens to log FAILED
now = 1011.0                          -- release + 0.5s gone by
CB:Refresh(state)
ok(state.player.autoShotCast == nil,
   "a wind-up with no release is cleared by the stale cleanup")
state.ranged.swingStart, state.ranged.swingDuration, state.ranged.windup = 0, 0, 0

print(string.format("castbar_spam_test: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
