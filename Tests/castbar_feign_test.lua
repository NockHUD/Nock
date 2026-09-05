-- Tests/castbar_feign_test.lua
-- The Feign Death bar must come down when the feign ends, whatever the aura
-- scan says. Report (2026-09-02): after a feign the 6-minute bar stayed up and
-- every later cast / auto fell back to it (state.player.feign went stale, and
-- the projection re-lodged fdInfo every tick); a mount pressed right after a
-- quick feign never got a bar (the FD record in `casting` refused the
-- UNIT_SPELLCAST_START). Three independent end signals now: the combat log's
-- SPELL_AURA_REMOVED, the aura record vanishing after it was seen, and the
-- client's UnitIsFeignDeath flag dropping after it was seen -- plus the cap.
-- Run from the repo root: luajit Tests/castbar_feign_test.lua

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

local castingInfo = nil
_G.UnitCastingInfo = function()
  if not castingInfo then return nil end
  return castingInfo.name, nil, "tex", castingInfo.startMs, castingInfo.endMs,
         nil, nil, nil, castingInfo.spellId
end

local feignFlag = nil   -- nil = API absent; true/false = UnitIsFeignDeath("player")
_G.UnitIsFeignDeath = function() return feignFlag end

local cleuArgs
_G.CombatLogGetCurrentEventInfo = function()
  return cleuArgs[1], cleuArgs[2], cleuArgs[3], cleuArgs[4], nil, nil, nil,
         cleuArgs[8], nil, nil, nil, cleuArgs[12], cleuArgs[13]
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
local C = addon.Constants
local FD, MOUNT, STEADY = C.SpellID.FEIGN_DEATH, 24252, C.SpellID.STEADY_SHOT
local FD_DUR = C.FEIGN_DEATH_DURATION

local function cleu(subEvent, spellId, dest)
  cleuArgs = { 0, subEvent, false, "player-guid", [8] = dest or "player-guid",
               [12] = spellId, [13] = "Spell " .. spellId }
  CB:COMBAT_LOG_EVENT_UNFILTERED()
end
local function feignBarUp()
  local c = state.player.casting
  return c ~= nil and c.fd == true
end
-- What Auras publishes after a scan that found the feign buff.
local function auraUp(appliedAt)
  state.player.feign = { icon = "fd", expirationTime = appliedAt + FD_DUR, duration = FD_DUR }
end

--------------------------------------------------------------------------------
-- 1. The kickstart: SUCCESS raises a provisional bar, the aura scan refines it.
--------------------------------------------------------------------------------
now = 100
cleu("SPELL_CAST_SUCCESS", FD)
ok(feignBarUp(), "FD SUCCESS raises the feign bar")
ok(state.player.casting.isChannel, "feign bar is drawn as a channel")
ok(state.player.casting.endTime == 100 + FD_DUR, "provisional bar runs to the FD cap")

now = 100.1
auraUp(100)
CB:Refresh(state)
ok(feignBarUp() and state.player.casting.endTime == 100 + FD_DUR, "aura timing adopted once scanned")

--------------------------------------------------------------------------------
-- 2. THE REPORT: stand up (SPELL_AURA_REMOVED) while the aura scan still
--    publishes the feign record. The bar must come down and STAY down.
--------------------------------------------------------------------------------
now = 103
cleu("SPELL_AURA_REMOVED", FD)
CB:Refresh(state)
ok(not feignBarUp(), "SPELL_AURA_REMOVED takes the feign bar down")
ok(state.player.casting == nil, "nothing left in casting after the feign")

now = 104
CB:Refresh(state)     -- state.player.feign is STILL the stale record
ok(state.player.casting == nil, "a stale feign record does not re-lodge the bar next tick")

-- A real cast afterwards ends cleanly -- no fallback to the feign bar.
now = 105
castingInfo = { name = "Steady Shot", spellId = STEADY, startMs = 105000, endMs = 106500 }
cleu("SPELL_CAST_START", STEADY)
ok(state.player.casting and state.player.casting.spellId == STEADY, "Steady raises its bar after the feign")
now = 106.5
castingInfo = nil
cleu("SPELL_CAST_SUCCESS", STEADY)
CB:Refresh(state)
ok(state.player.casting == nil, "after Steady lands the stale feign record still does not come back")

-- A genuine re-feign later still works (the stale record is not a lockout).
now = 140
cleu("SPELL_CAST_SUCCESS", FD)
ok(feignBarUp(), "a later FD raises the bar again")
now = 140.1
auraUp(140)
CB:Refresh(state)
ok(feignBarUp() and state.player.casting.endTime == 140 + FD_DUR, "the fresh aura record is adopted")
now = 141
cleu("SPELL_AURA_REMOVED", FD)
state.player.feign = nil
CB:Refresh(state)
ok(state.player.casting == nil, "and comes down again")

--------------------------------------------------------------------------------
-- 3. The other end signals still work on their own.
--------------------------------------------------------------------------------
-- 3a. Aura seen, then gone (no SPELL_AURA_REMOVED delivered).
now = 200
cleu("SPELL_CAST_SUCCESS", FD)
now = 200.1
auraUp(200)
CB:Refresh(state)
ok(feignBarUp(), "3a: bar up with the aura")
now = 202
state.player.feign = nil
CB:Refresh(state)
ok(state.player.casting == nil, "3a: aura seen then gone clears the bar without a REMOVED")

-- 3b. The client's feign flag drops after it was seen (aura record stale, no REMOVED).
now = 300
feignFlag = true
cleu("SPELL_CAST_SUCCESS", FD)
now = 300.1
auraUp(300)
CB:Refresh(state)
ok(feignBarUp(), "3b: bar up while UnitIsFeignDeath is true")
now = 302
feignFlag = false
CB:Refresh(state)
ok(state.player.casting == nil, "3b: UnitIsFeignDeath dropping clears the bar despite a stale aura record")
now = 303
CB:Refresh(state)
ok(state.player.casting == nil, "3b: and the stale record does not re-lodge it")

-- 3c. A flag API that never reports true must not tear the bar down by itself.
now = 400
feignFlag = false
state.player.feign = nil
cleu("SPELL_CAST_SUCCESS", FD)
now = 400.1
auraUp(400)
CB:Refresh(state)
now = 405
CB:Refresh(state)
ok(feignBarUp(), "3c: a flag that was never seen true is not an end signal")
now = 406
cleu("SPELL_AURA_REMOVED", FD)
state.player.feign = nil
CB:Refresh(state)
ok(state.player.casting == nil, "3c: cleanup")
feignFlag = nil

-- 3d. The hard cap.
now = 500
cleu("SPELL_CAST_SUCCESS", FD)
now = 500 + FD_DUR + 0.1
CB:Refresh(state)
ok(state.player.casting == nil, "3d: the bar never outlives the FD cap")

--------------------------------------------------------------------------------
-- 4. THE MOUNT REPORT: quick feign to drop aggro, then a mount before the
--    stand-up's REMOVED is delivered. The mount is a real cast (it is what
--    breaks the feign), so it displaces the feign record.
--------------------------------------------------------------------------------
now = 600
state.player.feign = nil
cleu("SPELL_CAST_SUCCESS", FD)
ok(feignBarUp(), "4: feign bar up")
now = 600.2
castingInfo = { name = "Swift Tiger", spellId = MOUNT, startMs = 600200, endMs = 603200 }
CB:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player")
ok(state.player.casting and state.player.casting.spellId == MOUNT, "4: the mount displaces the feign record")
cleu("SPELL_AURA_REMOVED", FD)      -- the stand-up lands a moment later
CB:Refresh(state)
ok(state.player.casting and state.player.casting.spellId == MOUNT, "4: the late REMOVED leaves the mount bar alone")
now = 603.3
castingInfo = nil
CB:UNIT_SPELLCAST_STOP("UNIT_SPELLCAST_STOP", "player")
CB:Refresh(state)
ok(state.player.casting == nil, "4: after the mount nothing falls back to the feign bar")

-- Same with a combat cast that breaks the feign (Steady already displaced via
-- CLEU; check the mount path is not the only one).
now = 700
cleu("SPELL_CAST_SUCCESS", FD)
now = 700.2
castingInfo = { name = "Steady Shot", spellId = STEADY, startMs = 700200, endMs = 701700 }
cleu("SPELL_CAST_START", STEADY)
ok(state.player.casting and state.player.casting.spellId == STEADY, "4: a CLEU cast displaces the feign record")
cleu("SPELL_AURA_REMOVED", FD)
now = 701.7
castingInfo = nil
cleu("SPELL_CAST_SUCCESS", STEADY)
CB:Refresh(state)
ok(state.player.casting == nil, "4: no feign fallback after the Steady")

--------------------------------------------------------------------------------
-- 5. Reload mid-feign: no combat-log edge ever seen, the aura record is fresh
--    (applied after the last removal we know of) -- the bar shows.
--------------------------------------------------------------------------------
now = 800
auraUp(799)
CB:Refresh(state)
ok(feignBarUp(), "5: a fresh feign record with no CLEU edge still shows the bar")
now = 801
state.player.feign = nil
CB:Refresh(state)
ok(state.player.casting == nil, "5: and clears when the record goes")

-- 6. A REMOVED for someone else's aura (dest ~= player) is ignored.
now = 900
cleu("SPELL_CAST_SUCCESS", FD)
cleu("SPELL_AURA_REMOVED", FD, "pet-guid")
CB:Refresh(state)
ok(feignBarUp(), "6: a REMOVED on another unit does not end the feign bar")
cleu("SPELL_AURA_REMOVED", FD)
CB:Refresh(state)
ok(state.player.casting == nil, "6: cleanup")

--------------------------------------------------------------------------------
-- 7. THE GHOST FEIGN (1.1.8 report): a feign broken in the same instant it
--    lands -- an FD+trap macro, or a queued ability right behind a plain FD.
--    Nobody ever sees the player down: no aura record, no feign flag, and the
--    combat log's REMOVED is missing or lands before the SUCCESS. None of the
--    "seen, then gone" signals can arm, and the bar sat on the 6-minute cap
--    (the Classic shot bars clipped at that lockout and went black). A feign
--    with no evidence at all after the grace never happened -- end it.
--------------------------------------------------------------------------------
local TRAP = 13809   -- Frost Trap; any instant fired right behind the feign
local function tickTo(t1, t2)
  for t = t1, t2 + 1e-9, 0.05 do now = t; CB:Refresh(state) end
end

-- 7a. SUCCESS, APPLIED, trap SUCCESS; no REMOVED ever; nothing seen.
now = 1000
feignFlag = false
state.player.feign = nil
state.player.casting = nil
cleu("SPELL_CAST_SUCCESS", FD)
cleu("SPELL_AURA_APPLIED", FD)
cleu("SPELL_CAST_SUCCESS", TRAP)
tickTo(1000.05, 1000.5)
ok(feignBarUp(), "7a: inside the grace the provisional bar is still up")
tickTo(1000.55, 1005)
ok(state.player.casting == nil, "7a: FD+trap with no evidence of a feign ends at the grace, not the cap")

-- 7b. The edges in the other order: APPLIED, REMOVED, then the SUCCESS.
now = 1100
cleu("SPELL_AURA_APPLIED", FD)
cleu("SPELL_AURA_REMOVED", FD)
cleu("SPELL_CAST_SUCCESS", FD)
cleu("SPELL_CAST_SUCCESS", TRAP)
tickTo(1100.05, 1105)
ok(state.player.casting == nil, "7b: a REMOVED before the SUCCESS still does not leave a ghost feign")

-- 7c. Plain FD with a queued Steady Shot behind it: the cast displaces the
--     feign record; no REMOVED; the ghost must not come back when it lands.
now = 1200
cleu("SPELL_CAST_SUCCESS", FD)
ok(feignBarUp(), "7c: feign bar up")
now = 1200.05
castingInfo = { name = "Steady Shot", spellId = STEADY, startMs = 1200050, endMs = 1201550 }
cleu("SPELL_CAST_START", STEADY)
ok(state.player.casting and state.player.casting.spellId == STEADY, "7c: the queued Steady displaces the feign record")
tickTo(1200.1, 1201.5)
ok(state.player.casting and state.player.casting.spellId == STEADY, "7c: the Steady bar is left alone")
now = 1201.55
castingInfo = nil
cleu("SPELL_CAST_SUCCESS", STEADY)
tickTo(1201.6, 1206)
ok(state.player.casting == nil, "7c: after the Steady the ghost feign does not re-lodge")

-- 7d. The grace never cuts a real feign: the flag is up on the first tick even
--     when the aura scan is late, and the bar outlives the grace.
now = 1300
feignFlag = true
cleu("SPELL_CAST_SUCCESS", FD)
tickTo(1300.05, 1301)
ok(feignBarUp(), "7d: a feign the client's flag confirms outlives the grace without an aura record")
now = 1301.1
auraUp(1300)
CB:Refresh(state)
ok(feignBarUp() and state.player.casting.endTime == 1300 + FD_DUR, "7d: the late aura record is adopted")
now = 1302
feignFlag = false
cleu("SPELL_AURA_REMOVED", FD)
state.player.feign = nil
CB:Refresh(state)
ok(state.player.casting == nil, "7d: cleanup")
feignFlag = nil

-- 7e. Same with the aura record alone (flag API absent), arriving inside the grace.
now = 1400
state.player.feign = nil
cleu("SPELL_CAST_SUCCESS", FD)
now = 1400.3
auraUp(1400)
CB:Refresh(state)
tickTo(1400.35, 1402)
ok(feignBarUp(), "7e: a feign the aura scan saw inside the grace stays up")
now = 1403
cleu("SPELL_AURA_REMOVED", FD)
state.player.feign = nil
CB:Refresh(state)
ok(state.player.casting == nil, "7e: cleanup")

print(string.format("castbar_feign_test: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
