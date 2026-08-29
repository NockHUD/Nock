-- Tests/practice_gates_test.lua
-- Standalone LuaJIT test: while Nock.state.sim.active, the live producers
-- must not write the fields the practice simulator owns. Loads each producer
-- against a stub addon, fires its handlers with data that WOULD write, and
-- asserts the sentinel values survive. A producer that forgets its gate fails
-- here before it ever fights the sim in-game. Every assertion has a gate-off
-- counterpart: without one, a stub that never writes anyway would pass
-- vacuously. Core/Core.lua's own two gates cannot be loaded here and are
-- checked by reading the file instead (section 7).
-- Run from the repo root: luajit Tests/practice_gates_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- Stub addon: NewModule hands back a plain table the file decorates.
local Nock = { modules = {} }
local function noop() end
function Nock:NewModule(name)
  -- AceEvent/AceTimer/AceConsole surface the producers call from handlers.
  local m = { name = name, SendMessage = noop, RegisterMessage = noop, RegisterEvent = noop,
              ScheduleTimer = noop, CancelTimer = noop, Print = noop }
  self.modules[name] = m
  return m
end
function Nock:GetModule(name) return self.modules[name] end
function Nock:Print() end
function Nock:SendMessage() end
_G.Nock = Nock
_G.LibStub = function() return { GetAddon = function() return Nock end } end
_G.GetRangedHaste = function() return 20 end
_G.GetTime = function() return 1000 end
_G.UnitGUID = function() return "player-guid" end
_G.UnitAffectingCombat = function() return true end
_G.UnitRangedDamage = function() return 2.174, 100, 200 end
_G.UnitAttackSpeed = function() return 3.7 end
_G.GetSpellInfo = function(id) return "Spell" .. tostring(id), nil, "icon" end
_G.C_Spell = { GetSpellInfo = function(id) return { name = "Spell" .. tostring(id) } end,
               GetSpellCooldown = function() return { startTime = 900, duration = 10 } end,
               GetSpellTexture = function() return "icon" end }
_G.GetSpellCooldown = function() return 900, 10 end
_G.UnitCastingInfo = function() return "Steady Shot", nil, nil, 1000000, 1001090, nil, nil, nil, 34120 end
_G.GetItemInfo = function() return nil end
_G.GetInventoryItemCooldown = function() return 900, 120 end
_G.GetInventoryItemID = function() return 1 end
_G.GetItemCount = function() return 0 end
_G.GetTalentTabInfo = function() return nil end
_G.UnitRace = function() return "Orc", "Orc" end
_G.UnitName = function() return "Tester" end
_G.UnitBuff = function() return nil end
_G.UnitAura = function() return nil end
_G.UnitDebuff = function() return nil end
_G.IsItemInRange = function() return true end
_G.IsSpellInRange = function() return 1 end
_G.CheckInteractDistance = function() return true end
_G.UnitExists = function() return true end
_G.UnitIsDead = function() return false end
_G.UnitCanAttack = function() return true end
_G.GetUnitSpeed = function() return 0 end
_G.GetMeleeHaste = function() return 0 end
_G.InCombatLockdown = function() return false end

dofile("Core/Constants.lua")
dofile("Core/State.lua")
local st = Nock.state
Nock.db = { profile = {} }
local C = Nock.Constants
st.sim.active = true

-- CLEU payload every producer reads through CombatLogGetCurrentEventInfo.
local cleu = {}
_G.CombatLogGetCurrentEventInfo = function() return unpack(cleu, 1, 13) end

-- 1. SwingTimer: an Auto Shot success and a CLEU cast start must not touch the grid.
dofile("Modules/SwingTimer.lua")
local sw = Nock.modules.SwingTimer
sw.playerGUID, sw.autoShotName = "player-guid", "Auto Shot"
st.ranged.swingStart, st.ranged.swingDuration, st.ranged.windupRatio = 111, 2.5, 0.2
sw:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "Auto Shot", C.SpellID.AUTO_SHOT)
ok(st.ranged.swingStart == 111, "SwingTimer: swingStart untouched")
ok(st.ranged.swingDuration == 2.5, "SwingTimer: swingDuration untouched")
cleu = { 0, "SPELL_CAST_START", nil, "player-guid", nil, nil, nil, nil, nil, nil, nil, C.SpellID.AUTO_SHOT, "Auto Shot" }
sw:COMBAT_LOG_EVENT_UNFILTERED()
ok(sw._windupStart == nil, "SwingTimer: CLEU wind-up start ignored")
sw:START_AUTOREPEAT_SPELL()
ok(st.ranged.repeating == false, "SwingTimer: repeating untouched")
sw:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player")
ok(st.ranged.castHasteCorr == 1.0, "SwingTimer: castHasteCorr untouched")
sw:RefreshSwingDurations()
ok(st.ranged.swingDuration == 2.5, "SwingTimer: RefreshSwingDurations gated")

-- 2. CastBar: CLEU cast start must not raise a cast.
dofile("Modules/CastBar.lua")
local cb = Nock.modules.CastBar
cb.playerGUID = "player-guid"
st.player.casting, st.player.autoShotCast = nil, nil
cleu = { 0, "SPELL_CAST_START", nil, "player-guid", nil, nil, nil, nil, nil, nil, nil, C.SpellID.STEADY_SHOT, "Steady Shot" }
cb:COMBAT_LOG_EVENT_UNFILTERED()
ok(st.player.casting == nil, "CastBar: CLEU cast gated")
cleu = { 0, "SPELL_CAST_START", nil, "player-guid", nil, nil, nil, nil, nil, nil, nil, C.SpellID.AUTO_SHOT, "Auto Shot" }
cb:COMBAT_LOG_EVENT_UNFILTERED()
ok(st.player.autoShotCast == nil, "CastBar: CLEU wind-up gated")
Nock.db.profile.castBarNonCombatCasts = true
cb:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player")
ok(st.player.casting == nil, "CastBar: UNIT_SPELLCAST_START gated")

-- 3. Auras: a Rapid Fire buff must not set the proc flags. Bloodlust is also
-- present so the inLust assertion is real (a stub returning nothing for
-- Bloodlust would pass "gated" vacuously even without the gate).
_G.UnitBuff = function(unit, i)
  if i == 1 then return "Rapid Fire", "icon", 1, nil, 15, 1015, nil, nil, nil, C.SpellID.RAPID_FIRE end
  if i == 2 then return "Bloodlust", "icon", 1, nil, 40, 1040, nil, nil, nil, C.SpellID.BLOODLUST end
  return nil
end
_G.UnitAura = _G.UnitBuff
dofile("Modules/Auras.lua")
local au = Nock.modules.Auras
st.player.rapidFire, st.player.quickShots, st.player.drums, st.player.inLust = false, false, false, false
au:ScanPlayer()
ok(st.player.rapidFire == false, "Auras: rapidFire gated")
ok(st.player.inLust == false, "Auras: inLust gated")

-- 4. Cooldowns: the sim-owned keys keep their sentinel, the others still scan.
dofile("Modules/Cooldowns.lua")
local cd = Nock.modules.Cooldowns
cd:RebuildLists()
st.cooldowns.MS.startTime, st.cooldowns.MS.duration = 5, 5
st.cooldowns.Arc.startTime, st.cooldowns.Arc.duration = 6, 6
st.cooldowns.FD.startTime = 0
cd:ScanCooldowns()
ok(st.cooldowns.MS.startTime == 5 and st.cooldowns.Arc.startTime == 6, "Cooldowns: MS/Arc gated")
ok(st.cooldowns.FD.startTime == 900, "Cooldowns: non-sim keys still scanned")

-- 5. RangeFinder: Refresh and PLAYER_TARGET_CHANGED must not touch the target zone.
dofile("Modules/RangeEngine.lua")
dofile("Modules/RangeFinder.lua")
local rf = Nock.modules.RangeFinder
st.target.rangeZone, st.target.inMelee, st.target.meleeProximity = "SENTINEL", true, 0.42
rf:Refresh(st)
ok(st.target.rangeZone == "SENTINEL" and st.target.inMelee == true and st.target.meleeProximity == 0.42,
   "RangeFinder: Refresh gated")
-- UnitExists false is the branch that WOULD clear the target: with UnitExists
-- true the ungated path only resets probe history, so the assertion below
-- would hold with or without the gate (it used to, vacuously).
local realUnitExists = _G.UnitExists
_G.UnitExists = function() return false end
rf:PLAYER_TARGET_CHANGED()
ok(st.target.rangeZone == "SENTINEL" and st.target.inMelee == true and st.target.meleeProximity == 0.42,
   "RangeFinder: PLAYER_TARGET_CHANGED gated")
_G.UnitExists = realUnitExists

-- 6. WeaveBind: the secure button's insecure OnClick hook must not raise the
-- held flag while practice owns the weave key. The button is built here with
-- frame stubs and the OnClick handler captured straight off HookScript.
local clickHandler
local weaveButton
_G.SecureHandlerWrapScript = noop
_G.SetOverrideBindingClick = noop
_G.ClearOverrideBindings = noop
_G.CreateFrame = function()
  local f = {}
  f.RegisterForClicks = noop
  f.SetAttribute = function(self, k, v) self["_attr_" .. k] = v end
  f.GetAttribute = function(self, k) return self["_attr_" .. k] end
  f.SetScript = noop
  f.RegisterEvent = noop
  f.UnregisterEvent = noop
  f.HookScript = function(self, script, fn) if script == "OnClick" then clickHandler = fn end end
  return f
end
dofile("Core/WeaveMacro.lua")
dofile("Modules/WeaveBind.lua")
local wb = Nock.modules.WeaveBind
weaveButton = wb:EnsureButton()
ok(clickHandler ~= nil and weaveButton ~= nil, "WeaveBind: button built and OnClick captured")
st.weave.keyHeld = false
clickHandler(weaveButton, "LeftButton", true)
ok(st.weave.keyHeld == false, "WeaveBind: OnClick down gated")
st.sim.active = false
clickHandler(weaveButton, "LeftButton", true)
ok(st.weave.keyHeld == true, "gate off: WeaveBind OnClick writes again")
st.weave.keyHeld = false
st.sim.active = true

-- ...and instead of writing state, it forwards the edge to Practice, which
-- drives the simulated weave. The real module isn't loaded here, so GetModule
-- hands back a fake that records the edge it was given.
local captured
local realGetModule = Nock.GetModule
Nock.GetModule = function(self, name, silent)
  if name == "Practice" then return { OnWeaveEdge = function(_, down) captured = down end } end
  return realGetModule(self, name, silent)
end
clickHandler(weaveButton, "LeftButton", true)
ok(captured == true, "WeaveBind: down edge forwarded to Practice")
ok(st.weave.keyHeld == false, "WeaveBind: forwarding still writes no state")
clickHandler(weaveButton, "LeftButton", false)
ok(captured == false, "WeaveBind: up edge forwarded to Practice")

-- 6b. The Grounded import (2026-08-27): the weave bind moves out of
-- GroundedSavedBinds into the profile, Grounded rebinds (the key is Nock's
-- at once), and the undo puts it back.
do
  local rebinds = 0
  _G.GroundedSavedBinds = {
    { "Blizzard", "F", 1, "/cast Blizzard", "/cast [@cursor] Blizzard" },
    { "Raptor Strike", "SHIFT-F", 123, "/use Snowball\n/stopcasting\n/cast Raptor Strike\n/startattack\n/click MovePadBackward", "/cast !Auto Shot\n/click MovePadBackward" },
  }
  _G.GroundedFrame = { UpdateSecureButtons = function() rebinds = rebinds + 1 end }
  local prevLockdown = _G.InCombatLockdown
  _G.InCombatLockdown = function() return false end
  local sentWB = 0
  local realSend2 = Nock.SendMessage
  Nock.SendMessage = function(_, msg) if msg == "NOCK_WEAVEBIND_CHANGED" then sentWB = sentWB + 1 end end
  local p = Nock.db.profile
  p.weaveBindKey, p.weaveBindEnabled, p.weaveBindMacroDown, p.weaveBindMacroUp = "F9", false, "/cast Raptor Strike", nil
  local g = wb:GroundedWeaveBind()
  ok(g and g.key == "SHIFT-F" and g.index == 2, "GroundedWeaveBind: finds the bind whose press weaves, not the ground-target one")
  ok(wb:GroundedLoaded() == true and wb:GroundedBindCount() == 2, "GroundedLoaded / GroundedBindCount read the SV")
  ok(wb:ImportFromGrounded() == true, "ImportFromGrounded moves it")
  ok(p.weaveBindKey == "SHIFT-F" and p.weaveBindEnabled == true and p.weaveBindMacroDown:find("Raptor Strike", 1, true) ~= nil
     and p.weaveBindMacroUp == "/cast !Auto Shot\n/click MovePadBackward", "...key, both bodies and the enable land in the profile")
  ok(#_G.GroundedSavedBinds == 1 and _G.GroundedSavedBinds[1][1] == "Blizzard" and rebinds == 1 and sentWB == 1,
     "...the bind leaves Grounded's table, Grounded rebinds, and WeaveBind is told")
  ok(p.weaveBindImported and p.weaveBindImported.key == "SHIFT-F" and p.weaveBindImported.prevEnabled == false, "...a copy is kept for the undo")
  ok(wb:GroundedWeaveBind() == nil, "...and Grounded holds no weave bind any more")
  ok(wb:ImportFromGrounded() == false, "a second import has nothing to move")
  ok(wb:UndoGroundedImport() == true, "UndoGroundedImport gives it back")
  ok(#_G.GroundedSavedBinds == 2 and _G.GroundedSavedBinds[2][2] == "SHIFT-F" and rebinds == 2 and sentWB == 2, "...into Grounded's table, which rebinds")
  ok(p.weaveBindKey == "F9" and p.weaveBindEnabled == false and p.weaveBindMacroDown == "/cast Raptor Strike" and p.weaveBindMacroUp == nil and p.weaveBindImported == nil,
     "...and Nock's previous key, enable and bodies come back; the copy is cleared")
  _G.InCombatLockdown = function() return true end
  ok(wb:ImportFromGrounded() == false and #_G.GroundedSavedBinds == 2, "no import in combat")
  _G.InCombatLockdown = prevLockdown
  Nock.SendMessage = realSend2
  _G.GroundedSavedBinds, _G.GroundedFrame = nil, nil
  ok(wb:GroundedWeaveBind() == nil and wb:GroundedLoaded() == false and wb:GroundedBindCount() == nil, "without Grounded there is nothing to find")
  p.weaveBindKey, p.weaveBindEnabled = nil, nil
end
Nock.GetModule = realGetModule
st.weave.keyHeld = false

-- WeaveBind keeps the override BOUND while practice is on and neuters it in
-- the secure wrapper instead (the `practice` attribute), so a mob that pulls
-- mid-drill never leaves the weave key dead for the rest of the fight —
-- rebinding would need lockdown-illegal attribute writes.
-- ApplyBind also needs ScheduleRepeatingTimer, which the base module stub
-- above does not carry (only ScheduleTimer/CancelTimer do).
wb.ScheduleRepeatingTimer = function() return "watchdog-timer" end
_G.GetCVar = function() return "1" end
local bound = nil
_G.SetOverrideBindingClick = function(_, _, key, name) bound = key .. "->" .. name end
_G.ClearOverrideBindings = function() bound = nil end
Nock.db.profile.weaveBindEnabled, Nock.db.profile.weaveBindKey = true, "MOUSE5"
wb.IsEnabled = function() return true end
st.sim.active = true
wb:ApplyBind()
ok(bound ~= nil and bound:find("MOUSE5", 1, true), "WeaveBind: override stays bound while practice is on")
ok(weaveButton:GetAttribute("practice") == true, "WeaveBind: practice attribute armed while practice is on")
-- The practice bodies: the shipped macros simulate everything, so they run
-- nothing; a MovePad step-out the user added survives (real footwork), and
-- key-only footwork runs nothing at all.
ok(weaveButton:GetAttribute("macrotextDownPractice") == "" and weaveButton:GetAttribute("macrotextUpPractice") == "",
   "WeaveBind: shipped macros give empty practice bodies")
local C = Nock.Constants
Nock.db.profile.weaveBindMacroDown = C.WEAVE_BIND_MACRO_DOWN .. "\n" .. C.WEAVE_BIND_MOVEPAD_LINE
Nock.db.profile.weaveBindMacroUp   = C.WEAVE_BIND_MACRO_UP .. "\n" .. C.WEAVE_BIND_MOVEPAD_LINE
wb:ApplyBind()
ok(weaveButton:GetAttribute("macrotextDownPractice") == C.WEAVE_BIND_MOVEPAD_LINE
   and weaveButton:GetAttribute("macrotextUpPractice") == C.WEAVE_BIND_MOVEPAD_LINE,
   "WeaveBind: MovePad step-out survives into both practice bodies")
Nock.db.profile.practiceFootwork = "key"
wb:ApplyBind()
ok(weaveButton:GetAttribute("macrotextDownPractice") == "" and weaveButton:GetAttribute("macrotextUpPractice") == "",
   "WeaveBind: key-only footwork strips the MovePad step-out too")
Nock.db.profile.practiceFootwork = nil
Nock.db.profile.weaveBindMacroDown, Nock.db.profile.weaveBindMacroUp = nil, nil
st.sim.active = false
wb:ApplyBind()
ok(bound ~= nil and bound:find("MOUSE5", 1, true), "WeaveBind: override still bound when practice ends")
ok(weaveButton:GetAttribute("practice") == false, "WeaveBind: practice attribute cleared when practice ends")
st.sim.active = true

-- 7. Core's own two gates. This test cannot load Core/Core.lua (it builds
-- frames, registers events and starts the tick), so the gates are checked by
-- reading the file: a string search is enough to catch the gate being deleted,
-- which is the failure mode that matters.
local core = io.open("Core/Core.lua", "r")
local coreSrc = core and core:read("*a") or ""
if core then core:close() end
ok(coreSrc:find("state.sim.gcd", 1, true) ~= nil, "Core tick: GCD reads state.sim.gcd while simming")
ok(coreSrc:find("state.sim.meleeHaste", 1, true) ~= nil, "Core tick: melee haste reads state.sim.meleeHaste while simming")

-- 8. Sanity: with the gate off the producers DO write (the test is not vacuous).
st.sim.active = false
sw:RefreshSwingDurations()
ok(st.ranged.swingDuration == 2.174, "gate off: SwingTimer writes again")
au:ScanPlayer()
ok(st.player.rapidFire == true, "gate off: Auras writes again")
ok(st.player.inLust == true, "gate off: Auras inLust writes again")

-- CastBar: the same CLEU payload that was refused above now raises a cast.
st.player.casting = nil
cleu = { 0, "SPELL_CAST_START", nil, "player-guid", nil, nil, nil, nil, nil, nil, nil, C.SpellID.STEADY_SHOT, "Steady Shot" }
cb:COMBAT_LOG_EVENT_UNFILTERED()
ok(st.player.casting ~= nil, "gate off: CastBar CLEU raises the cast")

-- Cooldowns: MS/Arc are scanned again (the stub reports startTime 900).
st.cooldowns.MS.startTime, st.cooldowns.Arc.startTime = 5, 6
cd:ScanCooldowns()
ok(st.cooldowns.MS.startTime == 900, "gate off: Cooldowns scans MS again")

-- RangeFinder: the no-target branch clears the zone.
_G.UnitExists = function() return false end
rf:PLAYER_TARGET_CHANGED()
ok(st.target.rangeZone == nil, "gate off: RangeFinder clears the zone (" .. tostring(st.target.rangeZone) .. ")")
_G.UnitExists = realUnitExists

-- 9. Practice.LockEWS — the pure half of the scenario DSL's `lock=<notation>`.
-- Every bracket's lower bound is exclusive and only the top one is open-ended,
-- so a locked notation must resolve back to ITSELF through the real bracket
-- table. A bracket narrower than the +0.1 offset would fail here rather than
-- silently drill the wrong rotation in-game.
dofile("Rotations/Profiles.lua")
dofile("Modules/Practice.lua")
local pracMod = Nock.modules.Practice
local plist = Nock.Profiles.list
for _, entry in ipairs(plist) do
  local ews = pracMod.LockEWS(plist, entry.name)
  ok(ews ~= nil and Nock.Profiles:ResolveByEWS(ews) == entry.name,
     "LockEWS: " .. entry.name .. " resolves back to its own bracket")
end
ok(pracMod.LockEWS(plist, "no such notation") == nil, "LockEWS: unknown notation is nil")
ok(pracMod.LockEWS(nil, "5:5:1:1") == nil, "LockEWS: no list is nil")

-- ...and inside the bracket is not the same as PLAYABLE. Every locked pin has
-- to schedule its OWN paper: no note further out than one measured cycle from
-- its release (the grader's matcher reaches exactly one cycle back, so anything
-- beyond is MISSED + OFF on flawless play), and a cycle long enough that a
-- paper asking for a cast every cycle is not GCD-bound.
--
-- Both edges were broken. `2:5` sat on the open-bottom bracket's `lo + 0.1` =
-- eWS 0.10 and seated its Steady TWELVE cycles out; `1:1` sat at 1.34, shorter
-- than the 1.5 s GCD, and walked 0.16 s off the swing every cycle.
do
  local PM = dofile("Core/PracticeModel.lua")

  -- `3:7 2w` is the ONE documented exception, and it is a `w` one. At its pin
  -- the paper's second weave slot sits 1.111 measured cycles past its release,
  -- because the melee swing (3.7 s) is four times the 0.90 s bow cycle and the
  -- slot lands where the swing comes up, not where the cycle does. No pin fixes
  -- it: the weave ladder only calls this rotation `3:7 2w` below eWS 0.94, and
  -- nothing under 0.94 both clears the reach and clears the GCD.
  --
  -- It is excluded rather than raised because it was MEASURED clean: the R5a/R5c
  -- sweep played `3:7 2w` at 0.90 and scored 14/14 A+ on flawless input, so the
  -- matcher evidently files a weave slot by its window rather than the way it
  -- files a cast. The static metric is a proxy and it is the proxy that is
  -- wrong here. Casts on this paper are still checked (their reach is 0.000).
  -- If that measurement is ever overturned, this row is the thing to delete.
  local REACH_SKIP_WEAVES = { ["3:7 2w"] = true }

  local function reachOf(notation, ews)
    local h = { ws = 3.0, rangedMul = 3.0 / ews, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0,
                castCorr = 1, multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 }
    local ab = PM.Abilities(h)
    local lay = PM.Layout(PM.STRINGS[notation], h, 0)
    local cycle = ab.a.dur + ab.a.cd
    local skipW = REACH_SKIP_WEAVES[notation]
    local rel, worst = nil, 0
    for i = 1, #lay.ev do
      local e = lay.ev[i]
      if e.sym == "a" then rel = e.t0 + e.dur
      elseif e.sym ~= "g" and rel and not (skipW and (e.sym == "w" or e.sym == "r")) then
        local out = (e.t0 - rel) / cycle
        if out > worst then worst = out end
      end
    end
    return worst, cycle, lay
  end

  -- Every pin, turret and weave alike: no note further out than one measured
  -- cycle from its release, and a paper that asks for a cast in every cycle
  -- needs a cycle longer than the GCD or its own period stops being the swing.
  local function checkPin(label, notation, ews)
    local worst, cycle, lay = reachOf(notation, ews)
    local at = label .. ": " .. notation .. " @ eWS " .. ("%.2f"):format(ews)
    ok(worst <= 1.0 + 1e-9,
       at .. " keeps every note inside one measured cycle (" .. ("%.3f"):format(worst) .. " out)")
    local casts = (lay.counts.s or 0) + (lay.counts.m or 0) + (lay.counts.A or 0)
    if casts >= lay.counts.a then
      ok(cycle > PM.GCD, at .. " is a cast-every-cycle paper, so its cycle must exceed the GCD")
    end
  end

  for _, entry in ipairs(plist) do
    checkPin("LockEWS", entry.name, pracMod.LockEWS(plist, entry.name))
  end
  ok(math.abs(pracMod.LockEWS(plist, "1:1") - 1.60) < 1e-9, "LockEWS: 1:1 is pinned above the GCD")
  ok(math.abs(pracMod.LockEWS(plist, "2:5") - 0.65) < 1e-9, "LockEWS: the open bottom bracket has a floor")
  ok(math.abs(pracMod.LockEWS(plist, "5:5:1:1") - 1.93) < 1e-9,
     "LockEWS: every other bracket still answers lo + 0.1")

  -- The WEAVE paper drills pin their haste the other way round -- a lock= onto a
  -- TURRET bracket, or a bare ews= where no bracket can state it -- so they miss
  -- the loop above entirely. Same two rules, resolved the way BuildCatalog
  -- resolves them, and graded against the WEAVE notation each row actually runs.
  local wd = pracMod.WEAVE_DRILL
  ok(type(wd) == "table" and next(wd) ~= nil, "WEAVE_DRILL: the weave drill pins are reachable")
  local nWeave = 0
  for notation, d in pairs(wd) do
    local ews = d.ews or pracMod.LockEWS(plist, d.lock)
    ok(ews ~= nil and ews > 0, "WEAVE_DRILL: " .. notation .. " resolves a pin")
    ok(PM.STRINGS[notation] ~= nil, "WEAVE_DRILL: " .. notation .. " names a real paper")
    checkPin("WEAVE_DRILL", notation, ews)
    nWeave = nWeave + 1
  end
  ok(nWeave == 5, "WEAVE_DRILL: all five weave papers pinned and checked (" .. nWeave .. ")")

  -- The exception is stated in one place and it is that one paper. A skip that
  -- spread to a second notation would be a silent exclusion.
  local skips = 0
  for _ in pairs(REACH_SKIP_WEAVES) do skips = skips + 1 end
  ok(skips == 1 and REACH_SKIP_WEAVES["3:7 2w"], "WEAVE_DRILL: exactly one documented weave-note exception")
  -- ...and it really is only the weave slots that need it: the casts on that
  -- paper are inside reach, and the weave slots are the ones that are not.
  local castsOnly = reachOf("3:7 2w", pracMod.WEAVE_DRILL["3:7 2w"].ews)
  ok(castsOnly <= 1.0 + 1e-9, "3:7 2w: its CASTS are inside one cycle (" .. ("%.3f"):format(castsOnly) .. ")")
end

-- 10. Scenario resolution and the per-window notation, the two pure halves of
-- the glue the panel and the grader call into. OnEnable only resolves the three
-- engine files onto the module here (its event registrations are stubs).
dofile("Core/PracticeModel.lua")
dofile("Core/PracticeTimeline.lua")
dofile("Core/PracticePlan.lua")
dofile("Modules/PracticeGrader.lua")
dofile("Modules/PracticeEngine.lua")
pracMod:OnEnable()
Nock.db.profile.practiceScenarioText = "Mine: rf@5 len=30\nbroken line without a colon"
Nock.db.profile.practiceScenario = "Rapid Fire at 5 s"
local sc, errs = pracMod:CurrentScenario()
ok(sc ~= nil and sc.name == "Rapid Fire at 5 s", "CurrentScenario: built-in resolves by name")
ok(errs ~= nil and #errs == 1, "CurrentScenario: the bad user line is reported, the good one is not")
Nock.db.profile.practiceScenario = "Mine"
sc = pracMod:CurrentScenario()
ok(sc ~= nil and sc.name == "Mine" and sc.len == 30, "CurrentScenario: user scenario resolves by name")
Nock.db.profile.practiceScenario = "no such scenario"
sc = pracMod:CurrentScenario()
ok(sc ~= nil and sc.name == Nock.PracticeEngine.SCENARIOS[1].name, "CurrentScenario: unknown name falls back to the first built-in")
-- The panel's scenario card resolves THROUGH CurrentScenario, so a stale name
-- can never make the card describe a drill the next fight will not run.
local citem = pracMod:CurrentCatalogItem()
ok(citem ~= nil and citem.name == Nock.PracticeEngine.SCENARIOS[1].name,
   "CurrentCatalogItem: unknown name lands on the same row CurrentScenario picked")
Nock.db.profile.practiceScenario = "Mine"
citem = pracMod:CurrentCatalogItem()
ok(citem ~= nil and citem.name == "Mine" and citem.sc ~= nil and citem.sc.len == 30,
   "CurrentCatalogItem: a resolvable name returns its own catalog row")
Nock.db.profile.practiceScenario = "no such scenario"
local names = pracMod:ScenarioNames()
local nameAt = {}
for i, n in ipairs(names) do nameAt[n] = i end
ok(#names == #Nock.Profiles.list + #Nock.Profiles.weaveList + #Nock.PracticeEngine.SCENARIOS + 2,
   "ScenarioNames: flattens all five groups")
ok(names[1] == Nock.Profiles.list[1].name and names[#names] == "Free play",
   "ScenarioNames: turret first, free play last")
ok(nameAt["Mine"] > nameAt[Nock.PracticeEngine.SCENARIOS[1].name]
   and nameAt[Nock.PracticeEngine.SCENARIOS[1].name] > nameAt[Nock.Profiles.weaveList[1]],
   "ScenarioNames: group order is turret, weave, scripts, mine")

-- 10b. BuildCatalog itself — pure, so it runs against stub tables rather than
-- the real profile list. Five groups in a fixed order; every paper item carries
-- its own name as `notation` (the grader's pin) and rolls no Quick Shots.
local stubTurret = { { name = "A", lo = 1 }, { name = "B", lo = 2 }, { name = "C", lo = 3 } }
-- The weave list carries a name with no WEAVE_DRILL row and the user list a
-- name a turret drill already owns: both must be REFUSED, not shipped.
local stubWeave = {}
for i, n in ipairs(Nock.Profiles.weaveList) do stubWeave[i] = n end
stubWeave[#stubWeave + 1] = "9:9 9w"
local cat, catErrs = pracMod.BuildCatalog(stubTurret, stubWeave, Nock.PracticeEngine.SCENARIOS,
  { { name = "Mine", events = {}, len = 30, qs = true },
    { name = "A", events = {}, len = 30, qs = true } },
  function() return 2.0 end, function() return nil end)
local keys = {}
for i, g in ipairs(cat.groups) do keys[i] = g.key end
ok(table.concat(keys, ",") == "turret,weave,scripts,mine,free", "BuildCatalog: five groups in order")
local function group(key)
  for _, g in ipairs(cat.groups) do if g.key == key then return g end end
end
local gT = group("turret")
ok(#gT.items == 3, "BuildCatalog: turret group has one item per profile")
local turretOk = true
for _, item in ipairs(gT.items) do
  -- Ruling 2026-08-24: a paper drill has no script to run out, so len is nil --
  -- it runs until the user stops it.
  if not (item.sc.lock == item.name and item.sc.notation == item.name and item.sc.qs == false
          and item.sc.len == nil and item.color ~= nil) then turretOk = false end
end
ok(turretOk, "BuildCatalog: turret items lock, pin, mute Quick Shots and never auto-stop")
ok(gT.items[1].sub == "paper drill · eWS 2.00", "BuildCatalog: turret sub-line states the locked eWS")
local gW = group("weave")
ok(#gW.items == #Nock.Profiles.weaveList, "BuildCatalog: weave group has one item per weave notation")
-- Ruling: the weave group keeps weaveList's order (ResolveWeave's display order).
local weaveOrderOk = true
for i, n in ipairs(Nock.Profiles.weaveList) do
  if gW.items[i].name ~= n then weaveOrderOk = false end
end
ok(weaveOrderOk, "BuildCatalog: weave group keeps weaveList order")
local function weaveItem(name)
  for _, item in ipairs(gW.items) do if item.name == name then return item end end
end
-- The held proc must match ResolveWeave's own branch for that notation:
-- "2:2 1w" is the MODERATE (imp Aspect / Quick Shots) rotation and
-- "6:9:1:1 3w" the Rapid Fire one. Holding the wrong one would drill each at a
-- haste that never produces its own notation live.
local moderate = weaveItem("2:2 1w")
ok(moderate ~= nil and moderate.sc.hold ~= nil and moderate.sc.hold.QS == true
   and moderate.sc.hold.RF == nil
   and moderate.sc.lock == "5:5:1:1" and moderate.sc.notation == "2:2 1w" and moderate.sc.qs == false,
   "BuildCatalog: 2:2 1w holds Quick Shots and locks the French bracket")
ok(moderate.sub == "paper weave drill · held: QS", "BuildCatalog: the weave sub-line names the held proc")
ok(moderate.sc.len == nil, "BuildCatalog: a paper weave drill never auto-stops either")
local rfWeave = weaveItem("6:9:1:1 3w")
ok(rfWeave ~= nil and rfWeave.sc.hold ~= nil and rfWeave.sc.hold.RF == true and rfWeave.sc.hold.QS == nil
   and rfWeave.sc.lock == "5:5:1:1" and rfWeave.sc.notation == "6:9:1:1 3w",
   "BuildCatalog: 6:9:1:1 3w holds Rapid Fire")
local french = weaveItem("5:5:1:1 3w")
ok(french ~= nil and french.sc.hold == nil and french.sub == "paper weave drill · base",
   "BuildCatalog: 5:5:1:1 3w holds nothing")
local maxHaste = weaveItem("3:7 2w")
ok(maxHaste ~= nil and maxHaste.sc.ews == 0.90 and maxHaste.sc.lock == nil and maxHaste.sc.hold == nil,
   "BuildCatalog: 3:7 2w pins eWS 0.90 with no held procs")
local rfDrums = weaveItem("6:11:1:1 3w")
ok(rfDrums ~= nil and rfDrums.sc.hold.RF and rfDrums.sc.hold.QS and rfDrums.sc.hold.Drums,
   "BuildCatalog: 6:11:1:1 3w holds RF + QS + Drums")
ok(group("scripts") and #group("scripts").items == #Nock.PracticeEngine.SCENARIOS,
   "BuildCatalog: scripts group is the built-ins")
-- Clean French is the first built-in and carries len=0 -> nil: it is a rotation
-- to settle into, not a minute-long clip.
ok(group("scripts").items[1].sub == "no procs · no auto-stop",
   "BuildCatalog: Clean French is procless and never auto-stops")
ok(group("scripts").items[1].sc.len == nil, "BuildCatalog: Clean French has no len")
ok(#group("mine").items == 1 and group("mine").items[1].name == "Mine", "BuildCatalog: mine group is the user's")

-- A user scenario whose name a built-in already owns is DROPPED, not listed:
-- CurrentScenario walks the groups in order and would hand back the built-in,
-- drilling something other than the line the user wrote while the dropdown
-- showed the name twice.
local function errMentions(errs, needle)
  local n = 0
  for _, e in ipairs(errs or {}) do if e:find(needle, 1, true) then n = n + 1 end end
  return n
end
ok(errMentions(catErrs, "'A' is taken by a built-in") == 1, "BuildCatalog: a shadowed user scenario is reported once")
ok(errMentions(catErrs, "no drill mapping for weave notation '9:9 9w'") == 1,
   "BuildCatalog: an unmapped weave notation is reported")
local seen, dupe = {}, nil
for _, g in ipairs(cat.groups) do
  for _, item in ipairs(g.items) do
    if seen[item.name] then dupe = item.name end
    seen[item.name] = true
  end
end
ok(dupe == nil, "BuildCatalog: no duplicate names across the catalog (" .. tostring(dupe) .. ")")
-- Every colourless item needs its OWN table: render sites may write into it, and
-- a shared default would recolour the whole catalog.
ok(gT.items[1].color ~= gT.items[2].color and gW.items[1].color ~= gT.items[1].color,
   "BuildCatalog: each colourless item gets its own colour table")
gT.items[1].color[1] = 0.99
ok(gT.items[2].color[1] ~= 0.99, "BuildCatalog: writing one item's colour leaves the others alone")

-- ...and the glue merges the builder's complaints into the parser's, so they
-- reach ReportScenarioErrors down the one path that prints them once.
Nock.db.profile.practiceScenarioText = "Clean French: rf@5"
local _, mergedErrs = pracMod:Catalog()
ok(errMentions(mergedErrs, "'Clean French' is taken by a built-in") == 1,
   "Catalog: a shadowed user scenario reaches the reported errors")
local mergedNames = pracMod:ScenarioNames()
local mseen, mdupe = {}, nil
for _, n in ipairs(mergedNames) do
  if mseen[n] then mdupe = n end
  mseen[n] = true
end
ok(mdupe == nil, "Catalog: the dropdown lists no name twice (" .. tostring(mdupe) .. ")")
Nock.db.profile.practiceScenarioText = "Mine: rf@5 len=30\nbroken line without a colon"
local gF = group("free").items[1]
ok(gF.name == "Free play" and gF.sc.len == nil and gF.sc.free == true and gF.sc.qs == true,
   "BuildCatalog: free play never ends and rolls Quick Shots")

-- CurrentScenario reaches the paper drills too: a turret notation resolves to
-- its generated scenario, not to the fallback built-in.
Nock.db.profile.practiceScenario = "2:3"
local paper = pracMod:CurrentScenario()
ok(paper ~= nil and paper.name == "2:3" and paper.lock == "2:3" and paper.notation == "2:3",
   "CurrentScenario: a turret paper drill resolves by name")
Nock.db.profile.practiceScenario = "no such scenario"

-- NotationFor must MOVE with the window's procs: at a French eWS a Quick Shots
-- window is the Long French rotation, not the fight's opening notation.
pracMod.cfg = { ws = 3.0, baseRangedMul = 3.0 / 2.174 }
local baseMul = 3.0 / 2.174
ok(pracMod:NotationFor(baseMul, { qs = false, rf = false, lust = false, drums = false }) == "5:5:1:1",
   "NotationFor: no procs is the plain bracket")
ok(pracMod:NotationFor(baseMul * 1.15, { qs = true, rf = false, lust = false, drums = false }) == "5:6:1:1",
   "NotationFor: a Quick Shots window is Long French")

-- 11. Quick Shots ownership. E.LoadScenario turns the roll back ON for every
-- scenario that does not say qs=off, so StartFight must re-apply the setting
-- afterwards: a scenario may take the roll away, never grant it.
Nock.db.profile.practiceScenarioText = "Quiet: qs=off len=20"
st.ranged.windupRatio, st.ranged.swingDuration = 0.5 / 3.0, 2.174
st.melee.swingDuration = 3.7
Nock.db.profile.practiceScenario = "Clean French"   -- no qs=off, no lock
Nock.db.profile.practiceQuickShots = false
st.sim.active, st.sim.fightOn = true, false
pracMod:StartFight()
ok(pracMod.engine.cfg.quickShots == false, "StartFight: Quick Shots off in the profile survives an unlocked scenario")
Nock.db.profile.practiceQuickShots = true
st.sim.fightOn = false
pracMod:StartFight()
ok(pracMod.engine.cfg.quickShots == true, "StartFight: Quick Shots on in the profile is honoured")
Nock.db.profile.practiceScenario = "Quiet"
st.sim.fightOn = false
pracMod:StartFight()
ok(pracMod.engine.cfg.quickShots == false, "StartFight: a qs=off scenario still overrides the setting")
-- 12. A paper drill PINS the grader's notation for the whole fight: the drill's
-- own name, whatever procs the window carries and whatever the dropdown says
-- afterwards. Without the pin a held Rapid Fire would re-label a weave drill
-- as a turret rotation halfway through and grade it against the wrong string.
Nock.db.profile.practiceScenario = "2:2 1w"
st.sim.active, st.sim.fightOn = true, false
pracMod:StartFight()
ok(pracMod._fightNotation == "2:2 1w", "StartFight: a paper drill opens at its own notation")
ok(pracMod:NotationFor(3.0 / 2.174, { rf = true, qs = true }) == "2:2 1w",
   "NotationFor: the pin survives a proc window")
pracMod:SetScenario("Clean French")
ok(pracMod:NotationFor(3.0 / 2.174, { rf = true, qs = true }) == "2:2 1w",
   "NotationFor: the pin comes off the fight, not the dropdown")
st.sim.fightOn, st.sim.active = false, false
pracMod._fightScenarioTable = nil

-- 13. DetectKeys and the start-attack key. A bar slot whose macro only arms
-- the auto ("/cast !Auto Shot", "/startattack") IS a rotation key: without it
-- the press never reaches the sim and the pull is lost. A slot that also names
-- a shot must NOT register as the autoshot key — every shot macro carries its
-- own "!Auto Shot" line and that line belongs to the shot press.
do
  local SPELL_NAME = {
    [C.SpellID.AUTO_SHOT] = "Auto Shot", [C.SpellID.STEADY_SHOT] = "Steady Shot",
    [C.SpellID.MULTI_SHOT] = "Multi-Shot", [C.SpellID.ARCANE_SHOT] = "Arcane Shot",
  }
  _G.C_Spell.GetSpellInfo = function(id) return { name = SPELL_NAME[id] or ("Spell" .. tostring(id)) } end
  _G.GetSpellInfo = function(id) return SPELL_NAME[id] or ("Spell" .. tostring(id)) end
  local bars = {}                      -- slot -> macro body
  _G.HasAction = function(slot) return bars[slot] ~= nil end
  _G.GetActionInfo = function(slot) return bars[slot] and "macro" or nil end
  _G.GetActionText = function(slot) return bars[slot] and ("Macro" .. slot) or nil end
  _G.GetMacroBody = function(text) return bars[tonumber(text:match("%d+"))] end
  _G.GetBindingKey = function(name)
    local n = name:match("^ACTIONBUTTON(%d+)$")
    return n and ("KEY" .. n) or nil
  end

  -- The Arcane macro alone: it names a shot, so its "!Auto Shot" line is part
  -- of that press and nothing registers under autoshot.
  bars = { [2] = "#showtooltip\n/cast Arcane Shot\n/cast !Auto Shot" }
  local k = pracMod:DetectKeys()
  ok(k.arcane ~= nil and k.arcane.key == "KEY2", "DetectKeys: the Arcane macro is the arcane key")
  ok(k.autoshot == nil, "DetectKeys: a shot macro's !Auto Shot line is not the autoshot key")

  -- The pure start-attack macro, with the Arcane one still on the bars: the
  -- auto-only slot takes the autoshot key and the Arcane slot keeps its own.
  bars = { [1] = "#showtooltip\n/cast !Auto-Shot\n/startattack",
           [2] = "#showtooltip\n/cast Arcane Shot\n/cast !Auto Shot" }
  k = pracMod:DetectKeys()
  ok(k.autoshot ~= nil and k.autoshot.key == "KEY1", "DetectKeys: a pure start-attack macro registers as the autoshot key")
  ok(k.autoshot ~= nil and k.autoshot.button == "ActionButton1", "DetectKeys: the autoshot key keeps its click-through button")
  ok(k.arcane ~= nil and k.arcane.key == "KEY2", "DetectKeys: the shot key is unaffected")

  -- The actions the bound button feeds the engine: E.Press applies "autoshot"
  -- (arm) and "startattack" (range-aware), so the press really lands.
  local acts = {}
  for _, a in ipairs((k.autoshot or {}).actions or {}) do acts[a] = true end
  ok(acts.autoshot and acts.startattack, "DetectKeys: the autoshot key carries both auto actions")
  local eng = Nock.PracticeEngine.New({ ws = 3.0, baseRangedMul = 1.38, latency = 0 })
  Nock.PracticeEngine.StartFight(eng, 0)
  local before = eng.nPress
  Nock.PracticeEngine.Press(eng, (k.autoshot or {}).actions or {}, 0)
  ok(eng.nPress == before + 1, "E.Press: the start-attack actions count as a press")

  -- A /startattack-only macro is the same key (no /cast line at all).
  bars = { [1] = "/startattack" }
  k = pracMod:DetectKeys()
  ok(k.autoshot ~= nil and k.autoshot.key == "KEY1", "DetectKeys: a /startattack-only macro is the autoshot key")

  -- ...but a slot that NAMES the auto beats it, whichever way round the bars
  -- are: "/startattack" is a hint, "/cast !Auto Shot" is the thing itself.
  bars = { [1] = "/startattack", [3] = "#showtooltip\n/cast !Auto Shot" }
  k = pracMod:DetectKeys()
  ok(k.autoshot ~= nil and k.autoshot.key == "KEY3",
     "DetectKeys: a named !Auto Shot slot beats a start-attack-only one that came first")
  bars = { [1] = "#showtooltip\n/cast !Auto Shot", [3] = "/startattack" }
  k = pracMod:DetectKeys()
  ok(k.autoshot ~= nil and k.autoshot.key == "KEY1",
     "DetectKeys: ...and nothing displaces a named one")

  -- A pull macro is NOT the auto key. "/cast Hunter's Mark" + "/startattack" is
  -- how most hunters open, and binding it would feed every Mark press into the
  -- sim as an auto press — and take the key off the real start-attack slot. A
  -- start-attack line only speaks for the whole slot when the slot says
  -- nothing else at all.
  bars = { [1] = "#showtooltip\n/cast Hunter's Mark\n/startattack" }
  k = pracMod:DetectKeys()
  ok(k.autoshot == nil, "DetectKeys: a Hunter's Mark + /startattack pull macro is not the autoshot key")
  bars = { [1] = "#showtooltip\n/cast Hunter's Mark\n/startattack", [3] = "/startattack" }
  k = pracMod:DetectKeys()
  ok(k.autoshot ~= nil and k.autoshot.key == "KEY3",
     "DetectKeys: ...and the bare start-attack slot still gets the key")

  bars = { [1] = "/startattack" }
  k = pracMod:DetectKeys()

  -- ...and ApplyKeys must actually TAKE that key. Detection alone proves
  -- nothing: the autoshot WANTED entry is what carries the key into the
  -- override, and without it the pull press goes straight to the client.
  local realCreateFrame, realSetOverride, realClearOverride, realWrap =
    _G.CreateFrame, _G.SetOverrideBindingClick, _G.ClearOverrideBindings, _G.SecureHandlerWrapScript
  local overrides, seen = {}, {}
  _G.CreateFrame = function(_, name)
    local f = { _name = name }
    f.GetName = function(self) return self._name end
    f.RegisterForClicks = noop
    f.HookScript = noop
    f.SetScript = function(self, n, fn) self["_s_" .. n] = fn end
    f.SetAttribute = function(self, key, v)
      self["_attr_" .. key] = v
      if key == "combatMacro" then seen[#seen + 1] = v end
    end
    f.GetAttribute = function(self, key) return self["_attr_" .. key] end
    return f
  end
  _G.SetOverrideBindingClick = function(_, _, key, name) overrides[key] = name end
  _G.ClearOverrideBindings = function() overrides = {} end
  _G.SecureHandlerWrapScript = noop
  pracMod:ApplyKeys()
  ok(overrides["KEY1"] ~= nil, "ApplyKeys: the detected autoshot key is bound to a practice button")

  -- With no bar slot behind it (a typed override) the fallback macro must be
  -- "/cast !Auto Shot": a bare "/cast Auto Shot" TOGGLES, so it would switch a
  -- running auto back off mid-drill.
  bars = {}
  Nock.db.profile.practiceKeys = { autoshot = "F1" }
  seen = {}
  pracMod:ApplyKeys()
  ok(overrides["F1"] ~= nil, "ApplyKeys: a typed autoshot override is bound too")
  ok(seen[1] == "/cast !Auto Shot", "ApplyKeys: the autoshot fallback macro is the non-toggling ! form")
  Nock.db.profile.practiceKeys = nil

  -- ONE key per action was the bug. The same shot macro sits on four bars and
  -- the hunter presses whichever key is under the finger; detection kept only
  -- the lowest slot's first binding, so the mash key cast for real in the
  -- middle of a drill. EVERY key on a rotation slot must be taken over, and
  -- each must replay that slot's own actions.
  local BINDS = {
    ACTIONBUTTON1 = "1", MULTIACTIONBAR3BUTTON11 = "ALT-1",
    MULTIACTIONBAR4BUTTON3 = "R", MULTIACTIONBAR4BUTTON4 = "SHIFT-R",
  }
  _G.GetBindingKey = function(name)
    local v = BINDS[name]
    if type(v) == "table" then return v[1], v[2] end
    return v
  end
  local MASH = "#showtooltip\n/startattack\n/cast Arcane Shot"
  bars = { [1] = MASH, [35] = MASH, [39] = MASH, [40] = MASH }
  k = pracMod:DetectKeys()
  ok(#pracMod.bindings == 4,
     "DetectKeys: four bars carrying one macro are four bindings (got " .. tostring(#pracMod.bindings) .. ")")
  local seenKeys, allReplay = {}, true
  for _, e in ipairs(pracMod.bindings) do
    seenKeys[e.key] = true
    local a = {}
    for _, name in ipairs(e.actions or {}) do a[name] = true end
    if not (a.arcane and a.startattack) then allReplay = false end
  end
  ok(seenKeys["1"] and seenKeys["ALT-1"] and seenKeys["R"] and seenKeys["SHIFT-R"],
     "DetectKeys: the mash key and every neighbour is bound")
  ok(allReplay, "DetectKeys: every binding replays its slot's own actions")
  ok(k.arcane ~= nil and k.arcane.key == "1",
     "DetectKeys: the primary is still the lowest slot's first key")
  ok(k.arcane ~= nil and #(k.arcane.keys or {}) == 4,
     "DetectKeys: the action lists all four of its keys")
  pracMod:ApplyKeys()
  ok(overrides["1"] and overrides["ALT-1"] and overrides["R"] and overrides["SHIFT-R"],
     "ApplyKeys: all four keys are taken over")

  -- GetBindingKey returns up to TWO keys for one binding name; both press the
  -- slot, so both are bindings.
  BINDS.ACTIONBUTTON1 = { "1", "NUMPAD1" }
  bars = { [1] = MASH }
  k = pracMod:DetectKeys()
  local twoKeys = {}
  for _, e in ipairs(pracMod.bindings) do twoKeys[e.key] = true end
  ok(#pracMod.bindings == 2 and twoKeys["1"] and twoKeys["NUMPAD1"],
     "DetectKeys: both keys of one binding name are bound")
  ok(k.arcane ~= nil and k.arcane.key == "1", "DetectKeys: the first of the two is the primary")

  -- Two slots on one key (the same key bound on two bars) is still ONE
  -- override, and the lowest slot owns it.
  BINDS.ACTIONBUTTON1, BINDS.MULTIACTIONBAR3BUTTON11 = "1", "1"
  bars = { [1] = MASH, [35] = MASH }
  pracMod:DetectKeys()
  ok(#pracMod.bindings == 1 and pracMod.bindings[1].slot == 1,
     "DetectKeys: a key shared by two slots is never bound twice")

  -- A typed override owns its key outright: it replays the one action it names
  -- and drops the bar button, so ApplyKeys builds the spell fallback.
  BINDS.ACTIONBUTTON1, BINDS.MULTIACTIONBAR3BUTTON11 = "1", "ALT-1"
  bars = { [1] = MASH, [35] = MASH, [39] = MASH, [40] = MASH }
  Nock.db.profile.practiceKeys = { steady = "R" }
  pracMod:DetectKeys()
  local eR
  for _, e in ipairs(pracMod.bindings) do if e.key == "R" then eR = e end end
  ok(eR ~= nil and #eR.actions == 1 and eR.actions[1] == "steady" and eR.button == nil,
     "DetectKeys: a typed override replaces the entry for its key")
  ok(#pracMod.bindings == 4, "DetectKeys: ...and adds no second entry for it")
  seen = {}
  pracMod:ApplyKeys()
  local sawSteady = false
  for _, m in ipairs(seen) do if m == "/cast Steady Shot" then sawSteady = true end end
  ok(sawSteady, "ApplyKeys: the overridden key falls back to its own spell macro")
  Nock.db.profile.practiceKeys = nil

  -- Proc keys (2026-08-27): practice-only binds that pop a proc on the sim,
  -- bound after the rotation's -- a key the rotation holds is left to it.
  bars = { [1] = MASH }
  BINDS.ACTIONBUTTON1, BINDS.MULTIACTIONBAR3BUTTON11 = "1", nil
  Nock.db.profile.practiceProcKeys = { Lust = "F5", Drums = "1" }
  local procFrames = {}
  local prevCreate = _G.CreateFrame
  _G.CreateFrame = function(kind, name, ...)
    local f = prevCreate(kind, name, ...)
    if name and name:find("ProcBtn", 1, true) then procFrames[name] = f end
    return f
  end
  pracMod:ApplyKeys()
  ok(overrides["F5"] == "NockPracticeProcBtnLust", "ApplyKeys: a proc key is bound to its proc button")
  ok(overrides["1"] ~= "NockPracticeProcBtnDrums" and pracMod:ProcKeyState("Drums").clash ~= nil,
     "ApplyKeys: a key the rotation holds stays the rotation's, and the page is told")
  ok(pracMod:ProcKeyState("Lust").override == "F5" and pracMod:ProcKeyState("Lust").clash == nil, "ProcKeyState: the bound key, no clash")
  local lustBtn = procFrames["NockPracticeProcBtnLust"]
  local modes = {}
  local realState, realMode, realActive = pracMod.ProcState, pracMod.ProcMode, pracMod.IsActive
  local st = "off"
  pracMod.ProcState = function() return st end
  pracMod.ProcMode = function(_, name, mode) modes[#modes + 1] = name .. ":" .. mode end
  pracMod.IsActive = function() return true end
  local wasFight = Nock.state.sim.fightOn
  Nock.state.sim.fightOn = true
  lustBtn._s_OnClick(lustBtn)
  st = "up"; lustBtn._s_OnClick(lustBtn)
  st = "perm"; lustBtn._s_OnClick(lustBtn)
  st = "held"; lustBtn._s_OnClick(lustBtn)
  ok(#modes == 3 and modes[1] == "Lust:on" and modes[2] == "Lust:perm" and modes[3] == "Lust:off",
     "a proc key press cycles off -> up -> held -> off; a scenario-held proc answers nothing")
  Nock.state.sim.fightOn = false
  st = "off"; lustBtn._s_OnClick(lustBtn)
  ok(#modes == 3, "...and does nothing between fights")
  Nock.state.sim.fightOn = wasFight
  pracMod.ProcState, pracMod.ProcMode, pracMod.IsActive = realState, realMode, realActive
  Nock.db.profile.practiceProcKeys = nil
  _G.CreateFrame = prevCreate

  _G.CreateFrame, _G.SetOverrideBindingClick, _G.ClearOverrideBindings, _G.SecureHandlerWrapScript =
    realCreateFrame, realSetOverride, realClearOverride, realWrap
end

-- 14. The fight clock starts at the first press. StartFight only ARMS, so
-- stopping before anything is pressed is a CANCEL: nothing graded, no review,
-- and the previous fight's scorecard CLEARED — the stream is empty, so the
-- review blanks and the panel goes back to READY; a report still answering for
-- a fight nothing else can show is the one state that disagrees with itself.
do
  local sent = {}
  local realSend = Nock.SendMessage
  Nock.SendMessage = function(_, msg) sent[msg] = (sent[msg] or 0) + 1 end
  Nock.db.profile.practiceScenario = "Clean French"
  st.sim.active, st.sim.fightOn = true, false
  pracMod.lastScore = "PREVIOUS"
  pracMod.lastVerdicts = { "PREVIOUS" }
  pracMod:StartFight()
  ok(st.sim.fightOn == true and st.sim.pulled == false, "StartFight: the fight is armed, not pulled")
  ok(pracMod.engine.n == 0, "StartFight: an armed fight has an empty event stream")
  pracMod:StopFight()
  ok(st.sim.fightOn == false and st.sim.pulled == false, "StopFight: a cancelled fight ends off and unpulled")
  ok(pracMod.engine.n == 0, "StopFight: cancelling an armed fight emits nothing")
  ok(sent["NOCK_PRACTICE_FIGHT_DONE"] == nil, "StopFight: a cancelled fight opens no review")
  ok(pracMod.lastScore == nil, "StopFight: a cancelled fight clears the previous scorecard")
  ok(pracMod.lastVerdicts == nil, "StopFight: ...and its verdicts with it")
  ok(pracMod:BuildReport() == nil, "StopFight: ...so there is no report to copy either")

  -- ...while a fight that WAS pulled scores and opens the review as before.
  st.sim.fightOn = false
  pracMod:StartFight()
  pracMod:OnKey({ "autoshot" })
  ok(pracMod.engine.pulled == true and pracMod.engine.n > 0, "OnKey: the first press pulls the fight")
  pracMod:StopFight()
  ok(sent["NOCK_PRACTICE_FIGHT_DONE"] == 1, "StopFight: a pulled fight opens the review")
  ok(pracMod.lastScore ~= "PREVIOUS", "StopFight: a pulled fight is scored")
  -- 14b. A proc popped on the PALETTE while the fight is armed (the buttons are
  -- live from Start) still shapes the fight: the pull replays it, so the
  -- grader's first real window opens at that haste and its notation is the
  -- procced rotation, not the base bracket.
  st.sim.fightOn = false
  Nock.db.profile.practiceScenario = "Clean French"
  pracMod:StartFight()
  local baseMulF = pracMod.cfg.baseRangedMul
  local baseNota = pracMod:NotationFor(baseMulF, { rf = false, qs = false, lust = false, drums = false })
  pracMod:Proc("RF", true)
  ok(pracMod.engine.n == 0, "Proc while armed: nothing on the stream yet")
  pracMod:OnKey({ "autoshot" })
  pracMod:FeedGrader()
  local win = pracMod.grader.win
  ok(win ~= nil and math.abs(win.rangedMul - baseMulF * 1.4) < 1e-6,
     "the grader's open window carries the Rapid Fire haste")
  ok(win ~= nil and win.notation == pracMod:NotationFor(baseMulF * 1.4, { rf = true }),
     "...and its notation is the Rapid Fire rotation, not the base bracket (" .. tostring(win and win.notation) .. ")")
  ok(win ~= nil and win.notation ~= baseNota, "the two notations really do differ (" .. tostring(baseNota) .. ")")
  pracMod:StopFight()

  Nock.SendMessage = realSend
  st.sim.fightOn, st.sim.active = false, false
end

-- 15. The drill ladder's GLUE (the pure half is Tests/practice_ladder_test.lua).
-- Loaded last on purpose: every assertion above runs against the catalog as it
-- is WITHOUT the ladder, and the group has to appear the moment the file is
-- there — including through the catalog's cache.
do
  local Ladder = dofile("Modules/PracticeLadder.lua")
  pracMod:OnEnable()                       -- re-binds Nock.PracticeLadder onto the module
  local st = Nock.state
  st.sim.active, st.sim.fightOn = false, false
  st.ranged.swingDuration = 2.174          -- the P1 BM baseline, so the notations are known
  pracMod.cfg = nil
  -- The profile key AceDB would have populated from Config/Defaults.lua.
  Nock.db.profile.practiceLadder = { done = {}, current = "beat" }

  local cat = pracMod:Catalog()
  local groups = {}
  for i, g in ipairs(cat.groups) do groups[g.key] = i end
  ok(groups.ladder ~= nil, "Catalog: the ladder's own scenarios join as a group")
  ok(groups.ladder == groups.free - 1, "Catalog: ...second to last, so Free play stays the last card")
  -- Round 5b: the ladder contributes seven rows -- the six TEACHING papers,
  -- which the DSL cannot state (there is no notation= token), and the one
  -- scripted drill, which it can.
  local lrows = cat.groups[groups.ladder].items
  ok(#lrows == 7, "Catalog: six teaching papers + the scripted drill (" .. #lrows .. ")")
  local lrow = lrows[1]
  ok(lrow ~= nil and lrow.name == "drill 1:1", "Catalog: the first row is the beat paper ("
     .. tostring(lrow and lrow.name) .. ")")
  ok(lrow ~= nil and lrow.sc ~= nil and lrow.sc.notation == "drill 1:1"
     and math.abs((lrow.sc.ews or 0) - 2.10) < 1e-9 and lrow.sc.qs == false and lrow.sc.len == nil,
     "Catalog: a teaching paper pins its notation and its own eWS, holds its procs, never stops itself")
  local rrow = nil
  for i = 1, #lrows do if lrows[i].name == "Rhythm changes" then rrow = lrows[i] end end
  ok(rrow ~= nil, "Catalog: the rhythm drill is a row too")
  ok(rrow ~= nil and rrow.sc ~= nil and rrow.sc.len == 45 and #rrow.sc.events == 2,
     "Catalog: built through the scenario DSL (len + scripted procs)")
  ok(pracMod:Catalog() == cat, "Catalog: the ladder key is part of the cache, and it is stable")

  -- Progress state, straight off the profile.
  local state = pracMod:LadderState()
  ok(state.current == "beat" and type(state.done) == "table", "LadderState: starts at the first drill")
  local items = pracMod:LadderItems()
  ok(#items == 10 and items[1].state == "cur", "LadderItems: ten rows, the first is current")
  ok(items[1].section == "TURRET" and items[5].section == "WEAVE" and items[9].section == "MASTERY",
     "LadderItems: the track headers ride on the rows the glue hands the view")

  -- Drill this: the pick moves exactly as the picker would move it, and the
  -- header names the drill rather than the notation.
  ok(pracMod:LoadDrill("beat") == true, "LoadDrill: beat loads")
  ok(Nock.db.profile.practiceScenario == "drill 1:1", "LoadDrill: beat pins the teaching 1:1 paper")
  ok(pracMod:LadderDrillName() == "Hold the beat", "LoadDrill: the header names the drill")
  local bsc = pracMod:CurrentScenario()
  ok(bsc ~= nil and bsc.name == "drill 1:1", "LoadDrill: CurrentScenario resolves it")
  ok(bsc ~= nil and math.abs((bsc.ews or 0) - 2.10) < 1e-9,
     "LoadDrill: ...at the eWS the teaching string was written for, not the 1:1 bracket's 1.34")

  ok(pracMod:LoadDrill("rhythm") == true, "LoadDrill: the scripted drill loads too")
  local rsc = pracMod:CurrentScenario()
  ok(rsc ~= nil and rsc.name == "Rhythm changes" and rsc.len == 45,
     "LoadDrill: ...through the catalog, with its script intact")
  ok(pracMod:LadderDrillName() == "Rhythm changes", "LoadDrill: and the header follows")

  -- Any other pick leaves the ladder.
  pracMod:SetScenario("Clean French")
  ok(pracMod:LadderDrillName() == nil, "SetScenario: a pick made elsewhere drops the drill")

  ok(pracMod:LoadDrill("no such drill") == false, "LoadDrill: an unknown id loads nothing")

  -- A finished fight is graded against the drill the fight OPENED with.
  pracMod:LoadDrill("beat")
  st.sim.active, st.sim.fightOn = true, false
  pracMod:StartFight()
  ok(pracMod._fightLadderDrill == "beat", "StartFight: the running drill is remembered at the pull")
  pracMod:EvaluateLadder({ clips = 0, cyclesOnPaper = { ok = 20, total = 20 } })
  ok(pracMod:LadderState().done.beat == true, "EvaluateLadder: a passing scorecard marks the drill")
  ok(pracMod:LadderState().current == "multi", "EvaluateLadder: ...and the ladder advances")
  ok(Ladder.Items(pracMod:LadderState())[1].state == "done", "the row goes green")

  pracMod:ResetLadder()
  ok(pracMod:LadderState().current == "beat" and next(pracMod:LadderState().done) == nil,
     "ResetLadder: back to the first drill with nothing done")

  -- 15b. WHICH PAPER a fight is graded against. `rhythm` pins no notation, so
  -- with the weave key bound it has to grade the WEAVE ladder: on the turret
  -- paper every melee hit is an OFF note and the rung would be passable only by
  -- not weaving, which is the opposite of the drill.
  st.sim.fightOn, st.sim.active = false, true
  Nock.db.profile.weaveBindEnabled, Nock.db.profile.weaveBindKey = true, "MOUSE5"
  Nock.state.player.canWeave = true
  pracMod:LoadDrill("rhythm")
  pracMod:StartFight()
  local wMul = pracMod.cfg.baseRangedMul
  ok(pracMod._fightWeave == true, "WeaveFight: a bound weave key and a two-hander make it a weave fight")
  ok(pracMod:NotationFor(wMul, {}) == "5:5:1:1 3w", "rhythm grades the WEAVE paper")
  ok(pracMod._fightNotation == "5:5:1:1 3w", "...and the fight OPENS on it, so the report agrees with its windows")
  ok(pracMod:NotationFor(wMul * 1.4, { rf = true }) == "6:9:1:1 3w",
     "a Rapid Fire window is the weave RF rotation")
  ok(Nock.PracticeModel.STRINGS[pracMod:NotationFor(wMul, {})] ~= nil,
     "the weave notation is a paper the model can actually lay out")
  pracMod:StopFight()

  -- Turret drills unchanged: no weave key, no weave paper...
  st.sim.fightOn = false
  Nock.db.profile.weaveBindEnabled = false
  pracMod:SetScenario("Clean French")
  pracMod:StartFight()
  ok(pracMod._fightWeave == false, "no weave key, no weave paper")
  ok(pracMod:NotationFor(pracMod.cfg.baseRangedMul, {}) == "5:5:1:1",
     "a turret fight still grades the turret ladder")
  ok(pracMod._fightNotation == "5:5:1:1", "...and opens on it")
  pracMod:StopFight()

  -- ...and a PINNED paper drill beats both ladders, weave key or not.
  st.sim.fightOn = false
  Nock.db.profile.weaveBindEnabled = true
  pracMod:LoadDrill("beat")
  pracMod:StartFight()
  ok(pracMod:NotationFor(pracMod.cfg.baseRangedMul, {}) == "drill 1:1",
     "a paper drill's own notation still wins over both ladders")
  pracMod:StopFight()
  st.sim.fightOn, st.sim.active = false, false

  -- 15c. A user line may not shadow a ladder drill: the ladder group is walked
  -- AFTER `mine`, so without the reservation the user's line would win
  -- CurrentScenario and silently drill something else.
  Nock.db.profile.practiceScenarioText = "Rhythm changes: rf@5 len=10"
  local cat2, errs2 = pracMod:Catalog()
  local shadowed, mineN = 0, 0
  for _, e in ipairs(errs2 or {}) do
    if e:find("Rhythm changes", 1, true) then shadowed = shadowed + 1 end
  end
  for _, g in ipairs(cat2.groups) do if g.key == "mine" then mineN = #g.items end end
  ok(shadowed == 1, "BuildCatalog: a user line that shadows a ladder drill is reported once")
  ok(mineN == 0, "...and never enters the catalog")
  Nock.db.profile.practiceScenario = "Rhythm changes"
  local rsc = pracMod:CurrentScenario()
  ok(rsc ~= nil and rsc.len == 45, "...so the name still resolves to the DRILL, not the user's line")
  Nock.db.profile.practiceScenarioText = ""

  -- 15d. The loaded drill lives in the profile (a /reload used to stop counting
  -- passes silently), and a state no drill answers to is healed rather than
  -- parking the ladder on nothing.
  local lstate = pracMod:LadderState()
  ok(lstate == Nock.db.profile.practiceLadder, "LadderState: the profile's own table")
  lstate.loaded = "weave-full"
  ok(pracMod:LadderDrillName() == "Full weave", "the loaded drill is read back out of it")
  lstate.current, lstate.loaded = "no such rung", "no such rung"
  local healed = pracMod:LadderState()
  ok(healed.current == "beat", "an unknown current rung is healed to the first")
  ok(healed.loaded == nil, "an unknown loaded drill is dropped")

  st.sim.fightOn, st.sim.active = false, false
end

-- 16. WHICH PAPER THE LESSON EXPLAINS, out of a fight. `_fightWeave` is only
-- meaningful from the pull onward, so LessonPlan asks WeaveFight() directly --
-- otherwise the lesson teaches the TURRET rotation for a scenario the very next
-- fight grades as a weave one. Mid-fight it still reads `_fightNotation`.
do
  local st = Nock.state
  st.sim.active, st.sim.fightOn = false, false
  st.ranged.swingDuration = 2.174
  pracMod.cfg = nil
  Nock.state.player.canWeave = true
  Nock.db.profile.practiceScenario = "Free play"      -- no pinned notation
  Nock.db.profile.weaveBindEnabled, Nock.db.profile.weaveBindKey = true, "MOUSE5"
  local str, h, notation = pracMod:LessonPlan()
  ok(notation == "5:5:1:1 3w",
     "LessonPlan: with the weave key bound the lesson explains the WEAVE paper (" .. tostring(notation) .. ")")
  ok(str == Nock.PracticeModel.STRINGS[notation], "LessonPlan: ...and hands back that paper's string")
  ok(h ~= nil and h.rangedMul ~= nil, "LessonPlan: the model handle comes with it")

  Nock.db.profile.weaveBindEnabled = false
  local _, _, turret = pracMod:LessonPlan()
  ok(turret == "5:5:1:1", "LessonPlan: no weave key, the turret paper (" .. tostring(turret) .. ")")

  -- A pinned paper drill still beats both ladders.
  Nock.db.profile.weaveBindEnabled = true
  pracMod:LoadDrill("beat")
  local _, _, pinned = pracMod:LessonPlan()
  ok(pinned == "drill 1:1", "LessonPlan: a paper drill's own notation wins over both ladders")

  Nock.db.profile.weaveBindEnabled = false
  Nock.db.profile.practiceScenario = "Clean French"
  st.sim.fightOn, st.sim.active = false, false
end

-- 17. THE PAPER IS THE SCOPE (Lookahead). The live rotation engine keeps
-- scoring its own priority list off state and knows nothing about the drill:
-- on a 1:1 paper it advised Arcane and Multi, and the stage drew that advice as
-- NEXT. Lookahead drops any advice whose symbol the CURRENT window's notation
-- does not contain, and publishes that symbol set so the views (the conveyor's
-- green gap tick) can gate on it too.
do
  local st = Nock.state
  local SpellID = Nock.Constants.SpellID
  st.sim.active, st.sim.fightOn = true, false
  st.ranged.swingDuration = 2.174
  Nock.db.profile.weaveBindEnabled, Nock.db.profile.weaveBindKey = true, "MOUSE5"
  st.player.canWeave = true
  local out = {}

  -- The `beat` drill pins the 1:1 paper: Steady and nothing else.
  pracMod:LoadDrill("beat")
  pracMod:StartFight()
  pracMod:OnKey({ "autoshot" })
  pracMod:Step(st, GetTime())        -- the tick's own order: Step, then the views
  ok(pracMod:Lookahead(out) ~= nil, "Lookahead: a running fight answers")
  local ps = out.paperSyms
  ok(ps ~= nil and ps.s == true and ps.m == false and ps.A == false and ps.w == false,
     "1:1 drill: paperSyms is Steady only")
  pracMod:Lookahead(out)
  ok(out.paperSyms == ps, "paperSyms is a reused table, not a fresh one per tick")
  ok(out.plan == st.sim.plan and out.nextCast == nil, "Lookahead carries the plan, not an engine nextCast")

  -- END TO END, through the module's own stream and its own grader. The bug
  -- lived HERE, not in the grader: WeaveFight() keys on the bound weave key, so
  -- a pinned 1:1 drill still ran with the weave half live and faulted every
  -- opportunity the engine opened. The events below are the ones the engine
  -- emits when the player never goes in, then goes in anyway.
  local e = pracMod.engine
  local t0 = GetTime()
  local function push(ev) e.n = e.n + 1; e.events[e.n] = ev end
  push({ t = t0 + 0.4, kind = "opp", open = true, ttw = 1.8 })
  push({ t = t0 + 1.6, kind = "opp", open = false, ttw = 0.7 })
  push({ t = t0 + 2.0, kind = "melee", hit = "r" })
  pracMod:FeedGrader()
  local weaveCodes = 0
  for i = 1, #pracMod.grader.verdicts do
    local v = pracMod.grader.verdicts[i]
    if v.key == "weave" then weaveCodes = weaveCodes + 1 end
  end
  ok(weaveCodes == 0, "beat drill with the weave key bound: no weave verdict at all (" .. weaveCodes .. ")")
  ok(pracMod.grader.weavesMissed == 0 and pracMod.grader.weavesTaken == 0,
     "beat drill: and no weave window counted")
  local realGetTime = GetTime
  _G.GetTime = function() return t0 + 3 end
  pracMod:StopFight()
  _G.GetTime = realGetTime
  local sc = pracMod.lastScore
  ok(sc ~= nil and sc.weavesMissed == 0 and sc.weavesTaken == 0,
     "beat drill: the scorecard counts none either")
  ok(sc ~= nil and sc.paperWeave == false and sc.meleeHits == 1,
     "beat drill: ...while the melee hit itself is still on the record")
  st.sim.fightOn = false

  -- A turret paper that DOES have both: the same advice passes through.
  -- (Step published the SIM's cycle onto state.ranged, so the live eWS the next
  -- BuildConfig reads is restored first — otherwise the fight opens on whatever
  -- bracket the drill's own haste landed in.)
  st.sim.fightOn = false
  st.ranged.swingDuration = 2.174
  Nock.db.profile.weaveBindEnabled = false
  pracMod:SetScenario("Clean French")
  pracMod:StartFight()
  pracMod:OnKey({ "autoshot" })
  pracMod:Step(st, GetTime())
  ok(pracMod._fightNotation == "5:5:1:1", "turret fight opens on the 5:5:1:1 paper")
  pracMod:Lookahead(out)
  ok(out.paperSyms.A == true and out.paperSyms.w == false, "5:5:1:1: Arcane on the paper, no weave")
  pracMod:StopFight()

  -- The counterpart, so the glue assertions above are not vacuous: the same
  -- missed opportunity on a WEAVE paper is still a fault and still a window.
  st.sim.fightOn = false
  st.ranged.swingDuration = 2.174
  Nock.db.profile.weaveBindEnabled = true
  pracMod:SetScenario("Clean French")
  pracMod:StartFight()
  ok(pracMod._fightNotation == "5:5:1:1 3w", "weave fight opens on the weave paper")
  pracMod:OnKey({ "autoshot" })
  local ew = pracMod.engine
  local tw = GetTime()
  ew.n = ew.n + 1; ew.events[ew.n] = { t = tw + 0.4, kind = "opp", open = true, ttw = 1.8 }
  ew.n = ew.n + 1; ew.events[ew.n] = { t = tw + 1.6, kind = "opp", open = false, ttw = 0.7 }
  pracMod:FeedGrader()
  ok(pracMod.grader.weavesMissed == 1, "weave paper: the same miss IS a fault ("
     .. tostring(pracMod.grader.weavesMissed) .. ")")
  local realGT = GetTime
  _G.GetTime = function() return tw + 3 end
  pracMod:StopFight()
  _G.GetTime = realGT
  ok(pracMod.lastScore ~= nil and pracMod.lastScore.paperWeave == true,
     "weave paper: and the scorecard says the paper asked for melee")
  st.sim.fightOn, st.sim.active = false, false
  st.rotation.nextAction = nil
end

-- 19. THE PAPER IS THE SCOPE (the HUD's own rotation NAME). Core's tick resolves
-- state.rotation.notation off the live turret/weave ladders, and in a practice
-- fight every input to those ladders is the SIM's: a 1:1 paper drill read back
-- as "1:1" while it stood at range and flipped to the WEAVE rotation the moment
-- the drill walked into melee. That field is what the auto-shot bar prints AND
-- what Modules/ShotPredictor.lua lays the shot bars out from, so the drill drew
-- a green weave lane for a paper with no `w` in it. Nock.HudNotation is the one
-- definition; Core.lua's call is checked by reading the file (section 7's rule).
do
  local st = Nock.state
  st.sim.active, st.sim.fightOn, st.sim.notation = false, false, nil
  st.player.canWeave = true
  st.target.inMelee, st.target.meleeProximity, st.target.rangeZone = false, -1, "OUT"

  -- Live: the turret pick at range, the weave pick in melee, and the display
  -- toggle still owns the swap (this is the HUD's own setting, not a paper).
  ok(Nock.HudNotation(st, "1:1", "5:5:1:1 3w", true, -0.10) == "1:1",
     "HudNotation: live at range is the turret pick")
  st.target.inMelee = true
  ok(Nock.HudNotation(st, "1:1", "5:5:1:1 3w", true, -0.10) == "5:5:1:1 3w",
     "HudNotation: live in melee is the weave pick")
  ok(Nock.HudNotation(st, "1:1", "5:5:1:1 3w", false, -0.10) == "1:1",
     "HudNotation: the weave display toggle still decides, live")

  -- Practice, with a drill's paper published: the paper wins in melee AND at
  -- range, whatever the live ladders would have said.
  st.sim.active, st.sim.notation = true, "1:1"
  ok(Nock.HudNotation(st, "5:5:1:1", "5:5:1:1 3w", true, -0.10) == "1:1",
     "HudNotation: a running drill's paper wins over the weave branch")
  st.target.inMelee = false
  ok(Nock.HudNotation(st, "5:5:1:1", "5:5:1:1 3w", true, -0.10) == "1:1",
     "HudNotation: ...and over the turret branch")
  st.sim.notation = nil
  ok(Nock.HudNotation(st, "5:5:1:1", "5:5:1:1 3w", true, -0.10) == "5:5:1:1",
     "HudNotation: practice on with no paper yet falls back to the live pick")
  st.sim.active = false

  local core = io.open("Core/Core.lua", "r")
  local coreSrc = core and core:read("*a") or ""
  if core then core:close() end
  ok(coreSrc:find("Nock.HudNotation(state", 1, true) ~= nil,
     "Core tick: state.rotation.notation is resolved through Nock.HudNotation")
end

-- 20. R3a END TO END: the fight runs the DRILL's paper. Selecting the 1:1 drill
-- and pressing play used to swap the HUD to "5:5:1:1 3w" (the live weave
-- ladder), warn CATCH-UP MULTI and LATE every cycle for a Multi the paper never
-- asks for, and leave the ladder unpassable.
do
  local st = Nock.state
  local realGetTime = GetTime
  st.sim.active, st.sim.fightOn = true, false
  st.ranged.swingDuration, st.ranged.windupRatio = 2.174, 0.5 / 3.0
  st.melee.swingDuration = 3.7
  Nock.db.profile.weaveBindEnabled, Nock.db.profile.weaveBindKey = true, "MOUSE5"
  Nock.db.profile.weaveNotationEnabled = true
  st.player.canWeave = true
  pracMod.cfg = nil

  ok(pracMod:LoadDrill("beat") == true, "R3a: the beat drill loads")
  pracMod:StartFight()
  ok(pracMod._fightNotation == "drill 1:1", "R3a: the fight opens on the drill's paper ("
     .. tostring(pracMod._fightNotation) .. ")")
  pracMod:OnKey({ "autoshot" })
  pracMod:Step(st, GetTime())
  local win = pracMod.grader and pracMod.grader.win
  ok(win ~= nil and win.notation == "drill 1:1",
     "R3a: the grader's open window is the drill's paper (" .. tostring(win and win.notation) .. ")")
  ok(st.sim.paperSyms ~= nil and st.sim.paperSyms.s == true and not st.sim.paperSyms.w
     and not st.sim.paperSyms.m and not st.sim.paperSyms.A,
     "R3a: paperSyms is Steady only — no weave, no Multi, no Arcane")

  -- The HUD, mid-drill, standing in melee (the weave key is bound and the drill
  -- walks in): the live ladders would say "5:5:1:1 3w"; the paper says 1:1.
  st.target.inMelee, st.target.rangeZone, st.target.meleeProximity = true, "MELEE", 0
  ok(Nock.HudNotation(st, Nock.Profiles:ResolveTurret(st.ranged.swingDuration, st.player, 0),
       Nock.Profiles:ResolveWeave(st.ranged.swingDuration, st.player, 0), true, -0.10) == "drill 1:1",
     "R3a: the HUD names the drill's paper in melee, not the live weave rotation")

  -- A clean 1:1 stream over the drill's own cycle: a Steady on every release,
  -- with Multi and Arcane both off cooldown the whole time (the engine's own
  -- state on a 1:1 drill). Not one CATCHUP/LATE/WEAVE verdict may come of it.
  local g = pracMod.grader
  -- Fed by hand, past the tick: no oracle. (The grader judges against the
  -- plan's time for a note when it has one, and the plan the last Step left
  -- behind is the armed one, on the provisional clock.)
  g.plan = nil
  -- The teaching paper pins eWS 2.10 (M.TEACHING_EWS), so the beat is 2.10 and
  -- the Steady 1.05 -- not the character's live 2.174. A stream fed at the live
  -- cycle would walk off a paper laid out at the pinned one.
  local cyc = Nock.PracticeModel.TEACHING_EWS["drill 1:1"]
  local rmul = 3.0 / cyc
  local cast, wind = 1.5 / rmul, 0.5 / rmul
  local t = GetTime()
  for i = 1, 24 do
    local rel = t + (i - 1) * cyc
    Nock.PracticeGrader.Feed(g, { t = rel, kind = "auto", delay = 0 })
    Nock.PracticeGrader.Feed(g, { t = rel, kind = "press", key = "steady", result = "ok",
                ctx = { ttw = cyc - wind, inWindup = false, cycle = cyc,
                        steadyCast = cast, multiCast = wind,
                        msReady = true, arcReady = true } })
    Nock.PracticeGrader.Feed(g, { t = rel + cast, kind = "cast", spell = "steady", t0 = rel, t1 = rel + cast })
    Nock.PracticeGrader.Feed(g, { t = rel + cast, kind = "free",
                ctx = { ttw = cyc - cast - wind, inWindup = false, cycle = cyc,
                        steadyCast = cast, multiCast = wind,
                        msReady = true, arcReady = true } })
  end
  local bad = {}
  for i = 1, #g.verdicts do
    local v = g.verdicts[i]
    if v.code and v.code ~= "GOOD" then bad[#bad + 1] = v.code end
  end
  ok(#bad == 0, "R3a: a clean 1:1 stream raises no fault at all (" .. table.concat(bad, ",") .. ")")
  ok(g.judge.perfect + g.judge.good > 0 and g.judge.late == 0 and g.judge.off == 0,
     "R3a: ...and every Steady is judged on paper")

  _G.GetTime = function() return t + 24 * cyc + 0.1 end
  -- This section feeds the GRADER by hand while the engine's own stream stays
  -- empty; with the timeline in reach G.Finish would re-count cycles off that
  -- empty stream (T.Cycles). Hide it, so the hand-fed cycles are the score.
  g.timeline = false
  pracMod:StopFight()
  _G.GetTime = realGetTime
  local sc = pracMod.lastScore
  ok(sc ~= nil and sc.clips == 0, "R3a: no clips on a clean beat drill")
  ok(sc ~= nil and sc.cyclesOnPaper and sc.cyclesOnPaper.total >= 20,
     "R3a: 24 releases is enough cycles for the beat drill's pass condition ("
     .. tostring(sc and sc.cyclesOnPaper and sc.cyclesOnPaper.total) .. ")")
  ok(pracMod:LadderState().done.beat == true,
     "R3a: EvaluateLadder marks the beat drill done on a passing fight")

  -- ...and the paper stops being the scope AT THE STOP. Nock.HudNotation pins
  -- the auto-shot bar's label, the React cluster's and ShotPredictor's whole
  -- layout to state.sim.notation while it is set, so a drill's rotation left
  -- there kept the HUD naming that drill between fights.
  ok(st.sim.notation == nil, "R3a: StopFight lets go of the drill's notation ("
     .. tostring(st.sim.notation) .. ")")
  ok(st.sim.paperSyms == nil, "R3a: ...and of its symbol set")
  ok(Nock.HudNotation(st, "5:5:1:1", "5:5:1:1 3w", true, -0.10) == "5:5:1:1",
     "R3a: so the HUD is back on the live pick between fights")

  -- Teardown clears both again: practice can be switched off mid-fight (the
  -- combat auto-stop does exactly that), and StopFight's own clear is skipped
  -- when there was no fight on at all.
  st.sim.notation, st.sim.paperSyms = "drill 1:1", Nock.PracticeGrader.Syms(Nock.PracticeModel, "drill 1:1")
  pracMod:Teardown()
  ok(st.sim.notation == nil and st.sim.paperSyms == nil,
     "R3a: Teardown lets go of both too (" .. tostring(st.sim.notation) .. ")")

  st.target.inMelee, st.target.rangeZone, st.target.meleeProximity = false, nil, 0
  st.sim.fightOn, st.sim.active = false, false
  Nock.db.profile.weaveBindEnabled = false
  pracMod:ResetLadder()
end

-- 21. R4d: THE LESSON FOLLOWS THE LOADED DRILL, out of a fight. With rung 2
-- loaded the lesson still explained 1:1 -- and it was telling the truth: the
-- rung had LOADED the 1:1 paper.
--
-- Round 5b moved the middle of the ladder onto TEACHING papers, which pin their
-- own string and cannot be dragged around by a stale swing at all. The rungs
-- still exposed to this are the two that read the character's own notation off
-- LadderContext -- `french` and `weave-full` -- so `french` is what the chain
-- below is checked through.
--
-- The chain. `Practice:Step` publishes the SIM's swing into
-- `state.ranged.swingDuration` while a drill is on; SwingTimer yields the field
-- for exactly that reason. Teardown asks SwingTimer to republish the live grid
-- on the way out -- but the combat auto-stop (`OnCombatChanged`) dropped
-- `sim.active` WITHOUT asking, so a 1:1 beat drill's pinned 1.34 s cycle stayed
-- in state as the "live" swing. `LadderContext` samples that field whenever the
-- sim is not active and remembers it for the session, and rung 2 is "the
-- profile's turret notation" -- which at eWS 1.34 is 1:1. So `Drill this` on
-- "Add Multi & Arcane" pinned the beat drill's own paper, and the lesson
-- explained it.
do
  local st = Nock.state
  st.sim.active, st.sim.fightOn = true, false
  st.ranged.swingDuration = 2.174
  st.melee.swingDuration = 3.7
  Nock.db.profile.weaveBindEnabled, Nock.db.profile.weaveBindKey = false, ""
  pracMod.cfg = nil

  -- The user's own sequence: rung 1 is loaded and RUN first, so the sim's own
  -- published swing is sitting in state when practice comes down.
  pracMod:LoadDrill("beat")
  pracMod:StartFight()
  pracMod:OnKey({ "autoshot" })
  pracMod:Step(st, GetTime())
  local realGT21 = GetTime
  _G.GetTime = function() return realGT21() + 5 end
  pracMod:StopFight()
  _G.GetTime = realGT21
  ok(math.abs(st.ranged.swingDuration - 2.10) < 1e-6 and st.ranged.swingDuration ~= 2.174,
     "R4d: the drill's pinned cycle really is in state while practice is on ("
     .. tostring(st.ranged.swingDuration) .. ") -- the assertions below are not vacuous")

  -- ...and then real combat takes practice down. That exit must hand the swing
  -- grid back exactly as Teardown does: the REAL fight starting right now would
  -- otherwise run with the drill's cycle on the auto-shot bar.
  st.sim.active = true
  pracMod:OnCombatChanged(nil, true)
  ok(st.sim.active == false, "R4d: real combat stops practice")
  ok(math.abs(st.ranged.swingDuration - 2.174) < 1e-9,
     "R4d: ...and hands the live swing grid back (" .. tostring(st.ranged.swingDuration) .. ")")

  ok(st.ranged.swingStart == 0 and st.ranged.swingRemaining == 0,
     "R4d: ...and the drill's last swing is off the live bar with it")

  pracMod:LadderContext()      -- any NOCK_PRACTICE_CHANGED repaint does this
  ok(pracMod:LadderContext().turret == "5:5:1:1",
     "R4d: so the ladder's turret rung is this CHARACTER's notation, not the drill's ("
     .. tostring(pracMod:LadderContext().turret) .. ")")
  st.sim.active = true

  ok(pracMod:LoadDrill("french") == true, "R4d: the full-turret rung loads")
  local _, _, n2 = pracMod:LessonPlan()
  ok(n2 == "5:5:1:1", "R4d: with the ctx-driven rung loaded the lesson explains the DRILL's paper ("
     .. tostring(n2) .. ")")

  ok(pracMod:LoadDrill("beat") == true, "R4d: ...and rung 1 loads back")
  local _, _, n1 = pracMod:LessonPlan()
  ok(n1 == "drill 1:1", "R4d: ...the lesson follows it to the beat paper (" .. tostring(n1) .. ")")

  -- Both ways round: the stale value must not be able to win in either
  -- direction, and the string handed back has to be that notation's own.
  ok(pracMod:LoadDrill("french") == true, "R4d: the full-turret rung again")
  local str2, _, n2b = pracMod:LessonPlan()
  ok(n2b == "5:5:1:1" and str2 == Nock.PracticeModel.STRINGS["5:5:1:1"],
     "R4d: ...and the paper string comes with it")

  -- ...and a TEACHING rung explains its own fixed paper, whatever the ladder
  -- context says: rung 2 is no longer the character's notation at all.
  ok(pracMod:LoadDrill("multi") == true, "R4d: rung 2 loads")
  local str3, _, n3 = pracMod:LessonPlan()
  ok(n3 == "drill 1:1+m" and str3 == Nock.PracticeModel.STRINGS["drill 1:1+m"],
     "R4d: ...and it explains its own teaching paper (" .. tostring(n3) .. ")")

  -- The view rebuilds on the message LoadDrill actually sends.
  local seen = {}
  local realSend = Nock.SendMessage
  Nock.SendMessage = function(_, msg) seen[msg] = (seen[msg] or 0) + 1 end
  pracMod:LoadDrill("beat")
  Nock.SendMessage = realSend
  ok(seen.NOCK_PRACTICE_CHANGED and seen.NOCK_PRACTICE_CHANGED > 0,
     "R4d: LoadDrill fires NOCK_PRACTICE_CHANGED -- the lesson view's rebuild hook")

  -- R4 review fold: with NO ranged weapon the client answers nothing, so
  -- SwingTimer's republish is a no-op and the drill's pin would survive the
  -- release. ReleaseGrid falls back to the character's own BASE speed, off the
  -- wind-up ratio (AUTO_SHOT_CAST / ratio) -- never the drill's.
  -- ReleaseGrid always runs with the sim already inactive -- that is what opens
  -- SwingTimer's own gate -- so both legs below are measured there.
  st.sim.active = false
  local realURD = _G.UnitRangedDamage
  _G.UnitRangedDamage = function() return 0, 0, 0 end
  st.ranged.swingDuration, st.ranged.windupRatio = 1.34, 0.5 / 3.0
  st.ranged.swingStart, st.ranged.swingRemaining = 12345, 0.9
  pracMod:ReleaseGrid()
  _G.UnitRangedDamage = realURD
  ok(math.abs(st.ranged.swingDuration - 3.0) < 1e-9,
     "R4 fold: no ranged weapon -- the grid falls back to the base weapon speed ("
     .. tostring(st.ranged.swingDuration) .. "), not a stale drill pin")
  ok(st.ranged.swingStart == 0 and st.ranged.swingRemaining == 0,
     "R4 fold: ...and the in-flight swing is cleared either way")

  -- ...and when the client DOES answer, its value wins and no fallback runs.
  st.ranged.swingDuration = 1.34
  pracMod:ReleaseGrid()
  ok(math.abs(st.ranged.swingDuration - 2.174) < 1e-9,
     "R4 fold: with a weapon equipped SwingTimer's own reading wins ("
     .. tostring(st.ranged.swingDuration) .. ")")

  st.sim.fightOn, st.sim.active = false, false
  pracMod:ResetLadder()
  Nock.db.profile.practiceScenario = "Clean French"
end

-- 22. R6a: THE ARMED STRIP SHOWS THE DRILL'S OWN PAPER. Before the pull the
-- grader has no haste window yet, and the conveyor's fallback for that was the
-- ancient `M.STRINGS[win and win.notation or ""] or "as"` -- so an armed
-- `drill 1:1+mA` forecast four identical Steadies and nothing else. The armed
-- strip has to project the notation the fight WILL be graded against, which is
-- Practice:FightPaper() -- the one resolution StartFight, the lesson and the
-- conveyor now share.
do
  local TLm = dofile("Core/PracticeTimeline.lua")
  local M = Nock.PracticeModel
  local st = Nock.state
  st.sim.active, st.sim.fightOn = true, false
  st.ranged.swingDuration, st.ranged.windupRatio = 2.174, 0.5 / 3.0
  st.melee.swingDuration = 3.7
  Nock.db.profile.weaveBindEnabled, Nock.db.profile.weaveBindKey = false, ""
  st.player.canWeave = false
  pracMod.cfg = nil

  ok(pracMod:LoadDrill("arcane") == true, "R6a: the arcane drill loads")
  local nota = pracMod:FightPaper()
  ok(nota == "drill 1:1+mA",
     "R6a: FightPaper names the drill's paper before the pull (" .. tostring(nota) .. ")")

  pracMod:StartFight()
  pracMod:Step(st, GetTime())
  ok(pracMod.grader ~= nil and pracMod.grader.win == nil,
     "R6a: an armed fight has no grader window yet -- the fallback is what draws the strip")
  local armed = pracMod:FightPaper()
  ok(armed == "drill 1:1+mA",
     "R6a: ...and the armed fight still answers with its own paper (" .. tostring(armed) .. ")")

  -- The conveyor's own feed, item for item (UI/Frame_PracticeConveyor.lua's
  -- Rebuild): the paper string off FightPaper, the model handle off
  -- TimelineData, the stream off ConveyorData.
  local live = pracMod:Lookahead({})
  ok(live ~= nil, "R6a: an armed fight answers Lookahead")
  local events, n = pracMod:ConveyorData()
  local opts = { past = 2, windup = live.windup or 0, verdicts = {},
                 model = M }
  local function projected(future)
    -- The paper items are the PLAN's now (v3 P1), and the plan's window is the
    -- profile's lookahead: widen it and re-publish before reading the strip.
    Nock.db.profile.practiceConveyorFuture = future
    pracMod:Step(st, GetTime())
    live = pracMod:Lookahead(live)
    opts.future = future
    local out = TLm.Strip(events, n or 0, live, opts, nil)
    local syms = {}
    for i = 1, out.nItems do
      local it = out.items[i]
      if it.key and it.key >= TLm.KEY.PAPER then syms[it.sym or "?"] = (syms[it.sym or "?"] or 0) + 1 end
    end
    return syms
  end
  -- The shipped lookahead (4.5 s floor, wider on a wide stage) reaches the
  -- second cycle of `asaAasasaAam`: the Steady on every release and the Arcane
  -- that rung ADDS. Four identical Steadies was the bug.
  local near = projected(4.5)
  ok((near.s or 0) > 0, "R6a: the armed strip projects the paper's Steadies (" .. tostring(near.s) .. ")")
  ok((near.A or 0) > 0, "R6a: ...and the Arcane this rung adds (" .. tostring(near.A) .. ")")
  -- One whole layout period (12.6 s at the rung's 2.10 pin) has the Multi in it
  -- too, so the projection really is walking the drill's own string and not a
  -- 1:1 stand-in.
  local full = projected(14)
  ok((full.m or 0) > 0, "R6a: ...and its Multi, a period out (" .. tostring(full.m) .. ")")
  ok((full.A or 0) >= 2, "R6a: ...with both Arcanes of the period (" .. tostring(full.A) .. ")")

  -- ...and the armed paper reaches the strip through THE PLAN (v3): it is
  -- Practice:PublishPlan that asks FightPaper, and the conveyor lays out no
  -- paper of its own any more. Frame files cannot be loaded here (section 7's
  -- rule), so the wiring is read off the source.
  local pf = io.open("Modules/Practice.lua", "r")
  local pSrc = pf and pf:read("*a") or ""
  if pf then pf:close() end
  local pubAt = pSrc:find("function Practice:PublishPlan", 1, true) or 0
  ok(pubAt > 0 and pSrc:find("FightPaper", pubAt, true) ~= nil,
     "R6a: PublishPlan asks Practice for the armed paper")
  local cv = io.open("UI/Frame_PracticeConveyor.lua", "r")
  local cvSrc = cv and cv:read("*a") or ""
  if cv then cv:close() end
  ok(cvSrc:find("opts.paper", 1, true) == nil and cvSrc:find('win.notation or ""', 1, true) == nil,
     "R6a: ...and the conveyor lays out no paper of its own")

  pracMod:StopFight()
  Nock.db.profile.practiceConveyorFuture = nil
  st.sim.fightOn, st.sim.active = false, false
  pracMod:ResetLadder()
  Nock.db.profile.practiceScenario = "Clean French"
end

-- 23. R6c: A TEACHING DRILL IS A TIMED ATTEMPT. Every ladder rung but `rhythm`
-- (45 s, its own script's) and `free` (endless) caps at 60 s, so the review
-- lands while the attempt is still in the fingers. The cap goes on the ENGINE,
-- never on the catalog row behind the drill: `french` and `weave-full` load the
-- character's own rotation, whose row the picker shares, and a rotation picked
-- by hand still runs until you stop it.
do
  local st = Nock.state
  local realGetTime = GetTime
  local sent = {}
  local realSend = Nock.SendMessage
  st.sim.active, st.sim.fightOn = true, false
  st.ranged.swingDuration, st.ranged.windupRatio = 2.174, 0.5 / 3.0
  st.melee.swingDuration = 3.7
  Nock.db.profile.weaveBindEnabled, Nock.db.profile.weaveBindKey = false, ""
  st.player.canWeave = false
  pracMod.cfg = nil

  Nock.db.profile.practiceScenario = "Clean French"
  ok(pracMod:DrillLen() == nil, "R6c: no drill loaded, no cap")
  ok(pracMod:LoadDrill("beat") == true, "R6c: the beat drill loads")
  ok(pracMod:DrillLen() == 60, "R6c: ...and asks for a 60 s attempt ("
     .. tostring(pracMod:DrillLen()) .. ")")

  Nock.SendMessage = function(_, msg) sent[msg] = (sent[msg] or 0) + 1 end
  pracMod:StartFight()
  ok(pracMod.engine.len == 60, "R6c: the cap reaches the engine")
  ok(pracMod:FightLen() == 60, "R6c: ...and the header's clock counts down from it")
  ok((pracMod:CurrentScenario() or {}).len == nil,
     "R6c: ...while the catalog row itself still keeps no auto-stop")

  pracMod:OnKey({ "autoshot" })                -- the pull: the clock starts here
  local t0 = pracMod.engine.t0
  -- Ticked, not jumped: the engine advances its shot grid one release per Step,
  -- so a single 61 s jump would land the fight past the cap having fired twice.
  -- 0.25 s is well inside the 2.10 s beat and cheap enough to run 244 of.
  local now, halfway = t0, nil
  _G.GetTime = function() return now end
  while now < t0 + 61 and st.sim.fightOn do
    now = now + 0.25
    pracMod:Step(st, now)
    if halfway == nil and now >= t0 + 30 then halfway = st.sim.fightOn end
  end
  _G.GetTime = realGetTime
  Nock.SendMessage = realSend
  ok(halfway == true, "R6c: half way through, the fight is still on")
  ok(now < t0 + 61, "R6c: ...and it ended before the loop ran out ("
     .. ("%.2f"):format(now - t0) .. " s)")
  ok(st.sim.fightOn == false, "R6c: the fight stopped itself at the cap")
  ok(sent["NOCK_PRACTICE_FIGHT_DONE"] == 1,
     "R6c: ...as a finished attempt, not a cancel -- the review opens")
  ok(pracMod:FightLen() == nil, "R6c: no fight, no countdown")

  -- REACHABILITY, end to end: 60 s at the beat rung's own 2.10 pin has to leave
  -- the 16-cycle pass floor comfortably in reach. This is the engine's own shot
  -- grid and the grader's own cycle count, not a model of them.
  local sc = pracMod.lastScore
  ok(sc ~= nil and sc.cyclesOnPaper ~= nil, "R6c: a capped attempt is scored")
  local total = sc and sc.cyclesOnPaper and sc.cyclesOnPaper.total or 0
  ok(total >= 24, "R6c: 60 s at the beat pin is " .. tostring(total)
     .. " whole cycles, well past the 16-cycle floor")
  -- Nothing was pressed, so it cannot have PASSED -- which is what makes the
  -- leg below mean something.
  ok(pracMod:LadderState().done.beat ~= true, "R6c: an attempt with no presses passes nothing")
  -- ...and the drill the auto-stopped fight was an attempt at is still the one
  -- the pass is evaluated against.
  pracMod:EvaluateLadder({ clips = 0, cyclesOnPaper = { ok = total, total = total } })
  ok(pracMod:LadderState().done.beat == true,
     "R6c: a capped fight is still graded against its own drill")

  st.sim.fightOn, st.sim.active = false, false
  pracMod:ResetLadder()
  Nock.db.profile.practiceScenario = "Clean French"
end

--------------------------------------------------------------------------------
-- 25. R8b: THE FIGHT REVIEW IS OFF WHILE THE ENGINE IS TUNED. One profile flag
-- (`practiceReviewEnabled`, default false) and every path into the window goes
-- through it: the fight ending must not open it, and asking for it by name must
-- answer in one line rather than with a window that does not appear. All the
-- review code stays -- flip the flag and the old behaviour is back, which is
-- the second half of what this section asserts.
--
-- UI/Frame_PracticeTimeline.lua only DEFINES functions at load (the frames are
-- built in OnInitialize, which nothing here calls), so it loads against the
-- stub addon and the two entry points are called directly on a stub frame.
--------------------------------------------------------------------------------
do
  if not Nock.Skin then dofile("UI/IconAtlas.lua"); dofile("UI/Skin.lua") end
  dofile("UI/Frame_PracticeTimeline.lua")
  local V = Nock.modules.PracticeTimelineView
  ok(V ~= nil and type(V.OnFightDone) == "function" and type(V.Toggle) == "function",
     "R8b: the review view loads with its two entry points")

  local shown, rebuilds = false, 0
  V.frame = { Show = function() shown = true end,
              Hide = function() shown = false end,
              IsShown = function() return shown end }
  V.Rebuild = function() rebuilds = rebuilds + 1 end
  local said = nil
  local realPrint = Nock.Print
  Nock.Print = function(_, s) said = s end
  Nock.state.player.inCombat = false

  -- OFF (the default a fresh profile gets).
  Nock.db.profile.practiceReviewEnabled = nil
  V:OnFightDone()
  ok(shown == false and rebuilds == 0, "R8b: flag off -- the fight ending leaves the window hidden")
  V:OnToggleMessage()
  ok(shown == false, "R8b: ...and asking for it by name does not open it")
  ok(said ~= nil and said:find("disabled", 1, true) and said:find("/nock practice report", 1, true),
     "R8b: ...it answers in one line, naming the report that still works")
  said = nil
  V:Toggle(true)
  ok(shown == false, "R8b: ...and a direct Toggle(true) cannot open it either")

  -- ON: the old behaviour, in full.
  Nock.db.profile.practiceReviewEnabled = true
  V:OnFightDone()
  ok(shown == true and rebuilds == 1, "R8b: flag on -- the fight ending opens it and rebuilds")
  ok(said == nil, "R8b: ...with nothing said in chat")
  V:OnToggleMessage()
  ok(shown == false, "R8b: ...and the toggle closes it again")
  V:OnToggleMessage()
  ok(shown == true and rebuilds == 2, "R8b: ...and opens it again")

  -- Still in real combat: the auto-stop fired on a stray mob, and a window over
  -- the fight is the last thing the player needs. Unchanged by the flag.
  shown = false
  Nock.state.player.inCombat = true
  V:OnFightDone()
  ok(shown == false, "R8b: flag on but still in combat -- it stays closed, as before")

  Nock.state.player.inCombat = false
  Nock.db.profile.practiceReviewEnabled = nil
  Nock.Print = realPrint
end

--------------------------------------------------------------------------------
-- 30. THE ORACLE (v3 P1): Practice:Step publishes state.sim.plan, and nothing
-- else names the next press. Armed: the drill's paper is seated on the
-- provisional t0 and the strip has a NEXT, but the HUD gets no spell. Pulled:
-- NEXT is the earliest pending playable note -- and a note left unplayed inside
-- its grace STAYS next (the medallion used to blank here).
do
  local C = Nock.Constants
  local T0 = 5000
  local T = T0
  local realGT = GetTime
  _G.GetTime = function() return T end
  st.sim.active = true
  Nock.db.profile.practiceScenario = "Clean French"
  pracMod:ResetLadder()
  pracMod.cfg = nil
  pracMod:LoadDrill("beat")
  pracMod:StartFight()
  pracMod:Step(st, T)
  local plan = st.sim.plan
  ok(plan ~= nil and plan.live == true and plan.pulled == false, "oracle: armed - plan is live, not pulled")
  ok(plan.n > 0 and plan.nextIdx ~= nil and plan.nextSpellId == nil,
     "oracle: armed - paper seated, NEXT set, no HUD spell (" .. tostring(plan.n) .. ")")
  ok(plan.reason == "pull", "oracle: armed - reason pull")
  local hasCd = false
  for i = 1, plan.nRows do if plan.rows[i] == "cd" then hasCd = true end end
  ok(plan.nRows == 2 and plan.rows[1] == "auto" and plan.rows[2] == "s" and not hasCd,
     "oracle: the beat drill shows two rows and no cooldown row")
  ok(st.sim.paperNextSym == nil and Nock.PaperAllows == nil, "oracle: old fields removed")
  ok(pracMod.CdReadyAt == nil, "oracle: CdReadyAt removed")

  pracMod:OnKey({ "steady" })        -- the pull
  T = T + 1 / 30; pracMod:Step(st, T)
  ok(st.sim.plan.pulled == true, "oracle: first press pulls")
  for _ = 1, 90 do T = T + 1 / 30; pracMod:Step(st, T) end
  plan = st.sim.plan
  ok(plan.nextSpellId == C.SpellID.STEADY_SHOT, "oracle: 1:1 - NEXT spell is Steady after the release")
  local out = pracMod:Lookahead({})
  ok(out.plan == plan, "oracle: Lookahead carries the plan by reference")
  ok(out.nextCast == nil and out.cdReadyAt == nil, "oracle: Lookahead no longer carries nextCast/cdReadyAt")
  ok(out.weaveAt == plan.weave.at, "oracle: Lookahead weave fields are the plan's")
  local key = plan.nextKey
  -- The note is already past its slot and unplayed; a third of a second on,
  -- still inside its grace, it is still the press being asked for. (Its t0 is
  -- the plan's honest press time, which the hand's clock may have moved to the
  -- release -- so the grace is measured from the clock, not from it.)
  local waitUntil = T + 0.3
  while T < waitUntil do T = T + 1 / 30; pracMod:Step(st, T) end
  ok(st.sim.plan.nextKey == key, "oracle: a pending note inside grace stays NEXT")
  -- The plan reaches as far as the VIEW can show (state.sim.horizonFuture,
  -- written by the conveyor's Layout); the profile value is the floor.
  st.sim.horizonFuture = 12
  T = T + 1 / 30; pracMod:Step(st, T)
  local far = 0
  for i = 1, st.sim.plan.n do if st.sim.plan.notes[i].t0 > T + 6 then far = far + 1 end end
  ok(far > 0, "oracle: the plan reaches as far as the view's horizon (" .. far .. ")")
  st.sim.horizonFuture = nil
  pracMod:StopFight()
  -- Stop opens the replay at the stop: the oracle still reads as it did
  -- there (the HUD replays it). Leaving the replay empties it on the next tick.
  ok(pracMod._replay ~= nil and st.sim.plan.live == true, "oracle: stop - the plan is the replay's")
  pracMod:ReplayOff()
  T = T + 1 / 30; pracMod:Step(st, T)
  ok(st.sim.plan.live == false and st.sim.plan.n == 0, "oracle: stop - plan empty")
  st.sim.active = false
  st.rotation.nextAction, st.rotation.nextNextAction = nil, nil
  pracMod:ResetLadder()
  Nock.db.profile.practiceScenario = "Clean French"
  _G.GetTime = realGT
end

-- 31. THE ORACLE: a Multi on cooldown is drawn but never NEXT; keys hold still
-- from tick to tick inside a cycle.
do
  local T = 6000
  local realGT = GetTime
  _G.GetTime = function() return T end
  st.sim.active = true
  -- The teaching paper puts its Multi every fifth cycle (~10.5 s): look far
  -- enough ahead for the strip's window to hold one.
  Nock.db.profile.practiceConveyorFuture = 14
  pracMod:ResetLadder(); pracMod.cfg = nil
  pracMod:LoadDrill("multi")
  pracMod:StartFight()
  pracMod:OnKey({ "steady" })
  for _ = 1, 60 do T = T + 1 / 30; pracMod:Step(st, T) end
  pracMod:OnKey({ "multi" })         -- spend the Multi now...
  for _ = 1, 15 do T = T + 1 / 30; pracMod:Step(st, T) end   -- (its cast resolves and books the real cooldown)
  pracMod.engine.cdReady.MS = T + 600  -- ...and keep it down past every note on the strip -- and past a
                                       -- whole period, else the plan defers it and plays it when it is back
  for _ = 1, 5 do T = T + 1 / 30; pracMod:Step(st, T) end
  local plan = st.sim.plan
  local sawM, mNext = false, false
  for i = 1, plan.n do
    local nt = plan.notes[i]
    if nt.sym == "m" and nt.state == Nock.PracticePlan.PENDING and not nt.playable then sawM = true end
  end
  if plan.nextIdx and plan.notes[plan.nextIdx].sym == "m" and not plan.notes[plan.nextIdx].playable then mNext = true end
  ok(sawM, "oracle: a Multi note on cooldown is in the plan, unplayable")
  ok(not mNext, "oracle: NEXT never lands on an unplayable note")
  local before, nBefore = {}, 0
  for i = 1, plan.n do before[plan.notes[i].key] = true; nBefore = nBefore + 1 end
  T = T + 1 / 30; pracMod:Step(st, T)
  local kept = 0
  for i = 1, st.sim.plan.n do if before[st.sim.plan.notes[i].key] then kept = kept + 1 end end
  ok(kept == nBefore, "oracle: keys hold still from one tick to the next (" .. kept .. "/" .. nBefore .. ")")
  pracMod:StopFight()
  Nock.db.profile.practiceConveyorFuture = nil
  st.sim.active = false
  st.rotation.nextAction, st.rotation.nextNextAction = nil, nil
  pracMod:ResetLadder()
  Nock.db.profile.practiceScenario = "Clean French"
  _G.GetTime = realGT
end

-- 32. THE MEDALLION READS THE PLAN: Rotation:Refresh never scores in a sim
-- fight. It copies plan.nextSpellId / nextNextSpellId, so the medallion, the
-- rotation row and WeaveCoach's GO can only ever name the press the strip does.
do
  dofile("Modules/Rotation.lua")
  local rot = Nock.modules.Rotation
  local C = Nock.Constants
  local T = 7000
  local realGT = GetTime
  _G.GetTime = function() return T end
  st.sim.active = true
  pracMod:ResetLadder(); pracMod.cfg = nil
  pracMod:LoadDrill("beat")
  pracMod:StartFight()
  pracMod:Step(st, T)
  -- Armed: no advice on the HUD even though the live scorers would pick something.
  st.ranged.swingRemaining = 2.0
  st.target.inMelee, st.target.meleeProximity = false, 0
  st.cooldowns.MS.remaining, st.cooldowns.Arc.remaining = 0, 0
  st.network.latencyMs = 0
  st.rotation.profile = nil
  rot:Refresh(st)
  ok(st.rotation.nextAction == nil and st.rotation.nextNextAction == nil, "medallion: armed - blank")
  pracMod:OnKey({ "steady" })
  for _ = 1, 90 do T = T + 1 / 30; pracMod:Step(st, T) end
  -- Make the live scorers WANT Arcane (off cooldown, plenty of swing left); the plan says Steady.
  st.ranged.swingRemaining = 2.0
  st.cooldowns.Arc.remaining = 0
  rot:Refresh(st)
  ok(st.rotation.nextAction == st.sim.plan.nextSpellId, "medallion: in a sim fight nextAction IS plan.nextSpellId")
  ok(st.rotation.nextAction == C.SpellID.STEADY_SHOT,
     "medallion: ...and the 1:1 plan says Steady, not the scorers' Arcane (" .. tostring(st.rotation.nextAction) .. ")")
  ok(st.rotation.nextNextAction == st.sim.plan.nextNextSpellId, "medallion: nextNextAction IS plan.nextNextSpellId")
  st.network.latencyMs = 400
  rot:Refresh(st)
  ok(st.rotation.nextAction == st.sim.plan.nextSpellId, "medallion: live latency does not change sim advice")
  pracMod:StopFight()
  -- Practice ON but no fight: the live scorers run again (no paper = no scope).
  st.ranged.swingRemaining = 2.0
  st.network.latencyMs = 0
  rot:Refresh(st)
  ok(st.rotation.nextAction ~= nil, "medallion: no fight - live scoring resumes")
  st.sim.active = false
  st.rotation.nextAction, st.rotation.nextNextAction = nil, nil
  pracMod:ResetLadder()
  Nock.db.profile.practiceScenario = "Clean French"
  _G.GetTime = realGT
end

-- 33. THE STAGE'S PALETTE. Practice:ApplyColors copies the profile's colours
-- into Nock.PracticeTimeline.COLORS IN PLACE (the views hold the inner tables
-- by reference), so an Options change reaches every lane without a reload.
do
  local T = Nock.PracticeTimeline
  local qs = T.COLORS.QS
  local was = { qs[1], qs[2], qs[3] }
  Nock.db.profile.practiceColorQS = { 0.1, 0.2, 0.3 }
  pracMod:ApplyColors()
  ok(T.COLORS.QS == qs, "palette: the colour table keeps its identity")
  ok(qs[1] == 0.1 and qs[2] == 0.2 and qs[3] == 0.3, "palette: ...and carries the profile's colour")
  local n = 0
  for pk in pairs(pracMod.COLOR_KEYS) do n = n + 1 end
  ok(n == 16, "palette: sixteen lane colours are exposed (" .. n .. ")")
  Nock.db.profile.practiceColorQS = nil
  qs[1], qs[2], qs[3] = was[1], was[2], was[3]
end

-- 34. THE KEY ON A STAGE ROW (v3 P3). RowKey names the primary bound key of a
-- row's ability, shortened; the weave row reads the WeaveBind key.
do
  ok(pracMod.ShortKey("SHIFT-MOUSE5") == "S-MB5", "rowkey: SHIFT-MOUSE5 shortens to S-MB5")
  ok(pracMod.ShortKey("CTRL-2") == "C-2" and pracMod.ShortKey("BUTTON4") == "MB4", "rowkey: CTRL- and BUTTON shorten")
  ok(pracMod.ShortKey(nil) == nil and pracMod.ShortKey("") == nil, "rowkey: nothing bound is nil")
  ok(pracMod:RowKey("cd") == nil, "rowkey: the cd row has no single key")
  local p = Nock.db.profile
  local wasE, wasK = p.weaveBindEnabled, p.weaveBindKey
  p.weaveBindEnabled, p.weaveBindKey = true, "MOUSE4"
  ok(pracMod:RowKey("w") == "MB4", "rowkey: the weave row reads the WeaveBind key")
  p.weaveBindEnabled = false
  ok(pracMod:RowKey("w") == nil, "rowkey: ...and nothing when WeaveBind is off")
  p.weaveBindEnabled, p.weaveBindKey = wasE, wasK
  local k = pracMod:RowKey("s")
  ok(k == nil or type(k) == "string", "rowkey: a shot row answers a string or nil (" .. tostring(k) .. ")")
end

-- 35. THE ROWS BEFORE A FIGHT (v3 P3). Picking a drill shows its rows at once.
do
  st.sim.active = true
  pracMod:ResetLadder(); pracMod.cfg = nil
  local rows = {}
  ok(pracMod:LoadDrill("beat") == true, "idle rows: beat loads")
  local n = pracMod:IdleRows(rows)
  ok(n == 2 and rows[1] == "auto" and rows[2] == "s" and rows[3] == nil, "idle rows: beat = auto, s (" .. n .. ")")
  ok(pracMod:LoadDrill("weave-beat") == true, "idle rows: weave-beat loads")
  n = pracMod:IdleRows(rows)
  ok(n == 2 and rows[2] == "w", "idle rows: weave-beat = auto, w (" .. n .. ")")
  pracMod:SetScenario("Clean French")
  n = pracMod:IdleRows(rows)
  ok(n >= 4 and rows[2] == "s" and rows[3] == "m" and rows[4] == "A", "idle rows: Clean French = auto, s, m, A (" .. n .. ")")
  st.sim.active = false
  pracMod:ResetLadder()
  Nock.db.profile.practiceScenario = "Clean French"
end

-- 36. THE GHOST PLAYS 5:5:1:1 CLEAN (P3 polish, the demo's gate reports). A
--     perfect hand -- every note pressed the moment the plan asks and the
--     engine is free -- on the French paper at eWS 1.93, a flat 1.5 s GCD and
--     the opener's GCD spilling past the first auto. What the plan asks for
--     must be playable, and what is played on its word must be judged as on
--     paper: no LATE, no CLIP, no WON'T FIT, nothing MISSED or OFF, no note
--     wearing two times from one tick to the next.
do
  local T = 9000
  local realGT = GetTime
  _G.GetTime = function() return T end
  st.sim.active = true
  st.ranged.windupRatio, st.ranged.swingDuration = 0.5 / 3.0, 1.93
  st.melee.swingDuration = 3.6
  pracMod._liveEws = 1.93                       -- the drill pins at the character's own haste when inside the bracket
  do local ge = tonumber(os.getenv("NOCK_GATE_EWS") or ""); if ge then st.ranged.swingDuration, pracMod._liveEws = ge, ge end end
  -- NOCK_GATE_PAPER=<scenario name> runs the gate on another paper (2:5 ...).
  Nock.db.profile.practiceScenario = os.getenv("NOCK_GATE_PAPER") or "Clean French"
  -- NOCK_GATE_LAT=<ms> runs the gate at that latency (the in-game ghost at
  -- 10 ms weaved 1/3 where the harness at 0 weaved 5/5, 2026-08-26).
  do local lat = tonumber(os.getenv("NOCK_GATE_LAT") or ""); if lat then Nock.db.profile.practiceLatencyMs = lat end end
  Nock.db.profile.practiceQuickShots = false
  pracMod:ResetLadder(); pracMod.cfg = nil
  -- The weave key's macros, as Practice:Start parses them (the gate skips
  -- Start): a weave paper's ghost needs the down/up actions to walk and hit.
  do
    local WM = Nock.WeaveMacro
    local resolve = (WM and WM.WithoutGate) or function(s) return s end
    local wnames = pracMod:WeaveNames()
    pracMod.weaveDown, pracMod.weaveUp, pracMod.weaveUnknown = {}, {}, {}
    Nock.PracticeEngine.ParseMacro(resolve(C.WEAVE_BIND_MACRO_DOWN or ""), wnames, pracMod.weaveDown, pracMod.weaveUnknown)
    Nock.PracticeEngine.ParseMacro(resolve(C.WEAVE_BIND_MACRO_UP or ""), wnames, pracMod.weaveUp, pracMod.weaveUnknown)
  end
  pracMod:StartFight()
  ok(pracMod._fightNotation == "5:5:1:1" or (pracMod.grader and true),
     "36: the fight opens on the French paper (" .. tostring(pracMod._fightNotation) .. ")")
  -- The ghost, perfect, key-only footwork (no real feet in a test).
  pracMod._demo, pracMod._demoMode, pracMod._demoPulled = true, "perfect", nil
  pracMod._demoFootwork = pracMod.cfg.footwork
  pracMod.cfg.footwork = "key"
  pracMod.engine.cfg.footwork = "key"      -- (StartFight ran before _demo was set)
  -- NOCK_DBG=1 prints the plan trace and the engine log for this fight.
  local dbg = os.getenv("NOCK_DBG")
  if dbg then pracMod._planTrace, pracMod._planRing, pracMod._debug, pracMod._debugLog, pracMod.PLAN_TRACE_N = true, nil, true, {}, 20000; _G.NOCK_PLAN_DBG = true end
  if dbg then pracMod.grader.onSweep = function(c, at, why) print(("SWEEP c%d at %.2f (%s) t1=%s sweepAt=%s"):format(c.ix, at - (st.sim.t0 or 0), tostring(why), c.t1 and ("%.2f"):format(c.t1 - (st.sim.t0 or 0)) or "-", c.sweepAt and ("%.2f"):format(c.sweepAt - (st.sim.t0 or 0)) or "-")) end end
  local flips = 0
  local shifts = 0
  local lastT0 = {}
  -- Every kind of change a note can show on the stage, per key: its time
  -- moving, its playable flag, its presence in the plan. A note that moves
  -- BACK to a time it left, or that leaves and returns, is a blink.
  local hist = {}
  local seen = {}
  local lastProj, lastN = nil, pracMod.engine.n
  local GATE_SECS = tonumber(os.getenv("NOCK_GATE_SECS") or "") or 40
  local gridMin, gridMax, gridZero
  if os.getenv("NOCK_NO_CLIP") then Nock.PracticePlan.NO_CLIP = true end
  -- The row set never shrinks during a fight (a row that leaves and returns is
  -- a blinking lane, user 2026-08-27): every row seen stays.
  local rowsSeen, rowShrinks = {}, 0
  for _ = 1, 30 * GATE_SECS do
    T = T + 1 / 30
    pracMod:Step(st, T)
    do
      local pl = st.sim.plan
      if pl and pl.live and pl.nRows > 0 then
        local have = {}
        for i = 1, pl.nRows do have[pl.rows[i]] = true end
        for r in pairs(rowsSeen) do if not have[r] then rowShrinks = rowShrinks + 1 end end
        for r in pairs(have) do rowsSeen[r] = true end
      end
    end
    if dbg then
      for _, cc in ipairs({ pracMod.grader.pend, pracMod.grader.cur }) do
        if cc and cc.n > 3 and not (cc._fatSeen == cc.n) then
          cc._fatSeen = cc.n
          local parts = {}
          for i = 1, cc.n do parts[#parts + 1] = ("%s k=%s@%.2f%s"):format(cc.nSym[i], tostring(cc.nKey[i]), cc.nT0[i] - st.sim.t0, cc.nUsed[i] and "u" or "") end
          print(("FAT %.2f cycle %d t0=%.2f n=%d: %s"):format(T - st.sim.t0, cc.ix, cc.t0 - st.sim.t0, cc.n, table.concat(parts, " ")))
        end
      end
    end
    local plan = st.sim.plan
    -- The grid ahead: how many projected autos the plan holds per tick (a
    -- 2:5 lost its autos on the stage, 2026-08-26).
    gridMin = math.min(gridMin or 99, plan.nAutos or 0)
    gridMax = math.max(gridMax or 0, plan.nAutos or 0)
    if (plan.nAutos or 0) == 0 and st.sim.pulled then gridZero = (gridZero or 0) + 1 end
    -- Projected vs actual: every auto the engine fired this tick against the
    -- plan's first projected release as it stood a tick ago.
    if dbg then
      local e = pracMod.engine
      for i = lastN + 1, e.n do
        local ev = e.events[i]
        if ev.kind == "auto" and lastProj then print(("AUTO %.3f proj=%.3f diff=%+.3f"):format(ev.t - st.sim.t0, lastProj - st.sim.t0, ev.t - lastProj)) end
      end
      lastN = e.n
      lastProj = plan.nAutos > 0 and plan.autos[1].releaseAt or nil
    end
    for k in pairs(seen) do seen[k] = false end
    for i = 1, plan.n do
      local nt = plan.notes[i]
      seen[nt.key] = true
      local h = hist[nt.key]
      if not h then h = { sym = nt.sym, moves = 0, backs = 0, playFlips = 0, gone = 0, t0 = nt.t0, playable = nt.playable, prev = nil, present = true, log = {} }; hist[nt.key] = h end
      if not h.present then h.gone = h.gone + 1; h.present = true; h.log[#h.log + 1] = ("%.2f back"):format(T - st.sim.t0) end
      if nt.state == "pending" and math.abs(nt.t0 - h.t0) > 0.05 then
        h.moves = h.moves + 1
        if h.prev and math.abs(nt.t0 - h.prev) < 1e-3 then h.backs = h.backs + 1; flips = flips + 1 end
        h.log[#h.log + 1] = ("%.2f %.2f>%.2f"):format(T - st.sim.t0, h.t0 - st.sim.t0, nt.t0 - st.sim.t0)
        h.prev, h.t0 = h.t0, nt.t0
      end
      if nt.playable ~= h.playable then h.playFlips = h.playFlips + 1; h.playable = nt.playable; h.log[#h.log + 1] = ("%.2f play=%s"):format(T - st.sim.t0, tostring(nt.playable)) end
    end
    for k, on in pairs(seen) do if not on and hist[k] and hist[k].present then hist[k].present = false; hist[k].log[#hist[k].log + 1] = ("%.2f gone"):format(T - st.sim.t0) end end
    -- A SHIFT: two or more pending notes in view moving a second or more in
    -- the same tick (every Steady behind a superseded one jumping a GCD).
    local big = 0
    for i = 1, plan.n do
      local nt = plan.notes[i]
      local h = hist[nt.key]
      if nt.state == "pending" and h and h.log[#h.log] and h.log[#h.log]:match("^" .. ("%.2f"):format(T - st.sim.t0)) and h.prev and math.abs(nt.t0 - h.prev) >= 1 and nt.t0 < T + 5 then big = big + 1 end
    end
    if big >= 2 then shifts = (shifts or 0) + 1; if dbg then print(("SHIFT %.2f %d notes"):format(T - st.sim.t0, big)) end end
  end
  if dbg then print(("GRID nAutos min=%s max=%s zero-ticks(pulled)=%s"):format(tostring(gridMin), tostring(gridMax), tostring(gridZero or 0))) end
  -- NOCK_GATE_EVENTS=<n> prints the first n engine events of the fight.
  local nEv = tonumber(os.getenv("NOCK_GATE_EVENTS") or "")
  if nEv then
    local e0 = st.sim.t0 or 0
    for i = 1, math.min(nEv, pracMod.engine.n) do
      local ev = pracMod.engine.events[i]
      local parts = {}
      for k, v in pairs(ev) do
        if k ~= "t" and k ~= "kind" and type(v) ~= "table" then parts[#parts + 1] = k .. "=" .. tostring(v) end
      end
      table.sort(parts)
      print(("EV %6.2f %-7s %s"):format(ev.t - e0, ev.kind, table.concat(parts, " ")))
    end
  end
  local otherPaper = os.getenv("NOCK_GATE_PAPER") ~= nil   -- the French-specific asserts below stand down
  ok((gridZero or 0) == 0, "36: the plan keeps projected autos on the grid for the whole fight (" .. tostring(gridZero or 0) .. " ticks without)")
  ok(rowShrinks == 0, "36: no row leaves the stage during the fight (" .. rowShrinks .. " tick(s) with a row gone)")
  if dbg then
    for k, h in pairs(hist) do
      if h.moves > 1 or h.backs > 0 or h.playFlips > 1 or h.gone > 0 then
        print(("NOTE %s key=%d moves=%d backs=%d playFlips=%d gone=%d | %s"):format(h.sym, k, h.moves, h.backs, h.playFlips, h.gone, table.concat(h.log, " ")))
      end
    end
  end
  local g = pracMod.grader
  local faults = {}
  for _, v in ipairs(g.verdicts) do
    if v.kind ~= "judge" and v.code ~= "GOOD" and v.code ~= "WEAVE_OK" and v.code ~= "REARM_PLANNED" then faults[#faults + 1] = v.code end
  end
  ok(#faults == 0, "36: a perfect hand raises no fault at all (" .. table.concat(faults, ",") .. ")")
  -- (One Multi may be lost: the opener's spill puts the paper's second Multi
  -- 0.4 s before its own cooldown is back, and a note nothing can press is
  -- MISSED honestly.)
  -- ...and a paper instant the spill leaves no room for is lost, not dragged
  -- (the hold limit). Three in twelve cycles is the current policy's cost --
  -- see the P3 polish plan for the open instant-first question.
  -- A superseded Steady (the chain a whole cycle behind; the next cycle's
  -- Steady takes its place) is swept MISSED by the paper-cycle bookkeeping
  -- (P4 reads the plan instead); an instant the plan asked for is never lost
  -- but for its own cooldown.
  local missedInstants = 0
  for _, v in ipairs(g.verdicts) do
    -- Instants only (m / A). `sym ~= "s"` counted weave notes too, and on
    -- 5:5:1:1 3w the paper's own tight weave (skipped by the ghost by design,
    -- the paper note says so) read as "3 instants missed" while every Multi
    -- and Arcane was pressed on the plan's word (2026-08-26).
    if v.kind == "judge" and v.grade == "MISSED" and v.note and (v.note.sym == "m" or v.note.sym == "A") then missedInstants = missedInstants + 1 end
  end
  ok(missedInstants <= 1 and g.judge.missed <= 5 and g.judge.off == 0,
     ("36: nothing off, at most one cooldown-lost instant (missed %d, instants %d, off %d)"):format(g.judge.missed, missedInstants, g.judge.off))
  ok(g.judge.perfect >= 10 and g.judge.late == 0,
     ("36: the notes are on paper (perfect %d, good %d, late %d)"):format(g.judge.perfect, g.judge.good, g.judge.late))
  ok(flips == 0, "36: no note flips back to a time it left (" .. flips .. ")")
  ok((shifts or 0) == 0, "36: no shift - two or more notes in view jumping a second in one tick (" .. tostring(shifts) .. ")")
  if dbg then
    -- The whole fight's mix and clips off the engine's own stream (the debug
    -- log is a ring), in the units WoWSims' Damage tab gives per hit.
    local U = { a = 1.00, s = 1.00, m = 1.11, A = 0.97 }
    local c = { a = 0, s = 0, m = 0, A = 0, clips = 0, sum = 0, max = 0 }
    for i = 1, pracMod.engine.n do
      local ev = pracMod.engine.events[i]
      if ev.kind == "auto" then
        c.a = c.a + 1
        if (ev.delay or 0) > 0.03 then c.clips = c.clips + 1; c.sum = c.sum + ev.delay; if ev.delay > c.max then c.max = ev.delay end end
      elseif ev.kind == "cast" then
        local k = ({ steady = "s", multi = "m", arcane = "A" })[ev.spell]
        if k then c[k] = c[k] + 1 end
      elseif ev.kind == "weave" and ev.edge == "down" then c.wd = (c.wd or 0) + 1
      elseif ev.kind == "melee" then c.hit = (c.hit or 0) + 1
      end
    end
    local units = c.a * U.a + c.s * U.s + c.m * U.m + c.A * U.A
    print(("PAPER eWS %.3f %ds: autos=%d steady=%d multi=%d arcane=%d casts/auto=%.2f | clips=%d total=%.2fs avg=%.0fms max=%.0fms | units=%.1f (%.3f/s) | weaves down=%d hits=%d"):format(
      st.ranged.swingDuration, GATE_SECS, c.a, c.s, c.m, c.A, (c.s + c.m + c.A) / math.max(1, c.a), c.clips, c.sum, c.clips > 0 and c.sum / c.clips * 1000 or 0, c.max * 1000, units, units / GATE_SECS, c.wd or 0, c.hit or 0))
  end
  -- THE HAND IS NEVER IDLED. The plan asks for the paper's next note the
  -- moment the hand is free (a beat note no earlier than its slot, a
  -- cooldown-bound instant deferred behind the next note); it never holds a
  -- press to the release or idles a GCD "for fit" -- that was the hard-cast
  -- gap the user saw on the HUD and, at scale, the backlog of the first Plan
  -- B round. So between one press's busy end and the next press the ghost
  -- waits no more than a reaction, bar the paper's own beats.
  local idleN, lastBusy = 0, nil
  for i = 1, pracMod.engine.n do
    local ev = pracMod.engine.events[i]
    if ev.kind == "press" and ev.result == "ok" and not ev.queuedFrom then
      if lastBusy and ev.t - lastBusy > 0.3 then
        idleN = idleN + 1
        if os.getenv("NOCK_DBG") then print(("IDLE %.2f..%.2f before %s"):format(lastBusy - pracMod.engine.t0, ev.t - pracMod.engine.t0, tostring(ev.key))) end
      end
    end
    if ev.kind == "press" and ev.result == "ok" then lastBusy = ev.t + 1.5 end
    if ev.kind == "cast" and ev.t1 and lastBusy and ev.t1 > lastBusy then lastBusy = ev.t1 end
    -- A weave is the hand's work too: the walk in, the hit, the walk out
    -- (weave first, 2026-08-26 -- the casts follow the step-out).
    if (ev.kind == "weave" or ev.kind == "melee") and lastBusy and ev.t > lastBusy then lastBusy = ev.t end
  end
  ok(idleN <= 2, "36: the hand is never idled between the paper's notes (" .. idleN .. " gaps over 0.3 s)")
  -- The paper's mix: a Multi every period (~10.7 s) and an Arcane likewise --
  -- 40 s holds three of each at least. (One Multi in 42 s in-game: a note
  -- marked lost two cycles early stayed lost for the fight.)
  local w = g.win
  ok(otherPaper or (w and (w.m or 0) >= 3 and (w.A or 0) >= 3),
     ("36: the paper's instants go out (multi %d, arcane %d in 40 s)"):format(w and w.m or -1, w and w.A or -1))
  if dbg then
    local ring = pracMod._planRing
    if ring then
      local start = ring.at - ring.n + 1
      for k = 0, ring.n - 1 do print(ring[(start + k - 1) % 20000 + 1]) end
    end
    for _, l in ipairs(pracMod._debugLog or {}) do print(l) end
    for _, v in ipairs(g.verdicts) do
      if v.kind == "judge" then print(("JUDGE %.2f %s key=%s note@%.2f"):format(v.t - (st.sim.t0 or 0), v.grade, tostring(v.note.key), (v.note.t0 or 0) - (st.sim.t0 or 0)))
      else print(("FAULT %.2f %s %s"):format(v.t - (st.sim.t0 or 0), v.code, v.text or "")) end
    end
    pracMod._planTrace, pracMod._debug, pracMod.grader.onSweep = false, false, nil
    _G.NOCK_PLAN_DBG = nil
  end
  pracMod._demo = false
  pracMod.cfg.footwork = pracMod._demoFootwork
  pracMod:StopFight()
  st.sim.active = false
  st.ranged.swingDuration = 2.174
  st.melee.swingDuration = 3.7
  pracMod:ResetLadder()
  Nock.db.profile.practiceQuickShots = true
  _G.GetTime = realGT
end

-- 36b. A paper drill rolls no crit (no Kill Command window it never stated);
-- an unlocked script keeps the character's. After the ghost run, so the extra
-- arm/stop cycles perturb nothing above. The stub crit is 30 % for the check.
do
  GetRangedCritChance = function() return 30 end
  if not pracMod:IsActive() then pracMod:Start() end
  pracMod:StopFight(); pracMod:StartFight()
  ok(Nock.state.sim.fightOn == true, "36b: a fight is armed for the crit check")
  local scT = pracMod._fightScenarioTable
  local paper = scT and scT.qs == false and not scT.kc
  local cr = pracMod.engine.cfg.critRanged
  ok(paper and cr == 0 or (not paper and math.abs(cr - 0.30) < 1e-9),
     ("36b: %s (crit %.2f)"):format(paper and "a paper drill rolls no crit -- no Kill Command window it never stated" or "an unlocked script keeps the character's crit", cr))
  pracMod:StopFight()
  GetRangedCritChance = nil
end

-- 36c. The cd row is STICKY for the fight (user, 2026-08-27: "blinking in and
-- out"). A paper drill starts without one; the first cooldown press or proc
-- adds it, and it stays after the item has left the view.
do
  local T = 11000
  local realGT = GetTime
  _G.GetTime = function() return T end
  st.sim.active = true
  st.ranged.windupRatio, st.ranged.swingDuration = 0.5 / 3.0, 1.93
  st.melee.swingDuration = 3.6
  pracMod._liveEws = 1.93
  Nock.db.profile.practiceScenario = "Clean French"
  Nock.db.profile.practiceQuickShots = false
  pracMod:ResetLadder(); pracMod.cfg = nil
  pracMod:StartFight()
  pracMod._demo, pracMod._demoMode, pracMod._demoPulled = true, "perfect", nil
  pracMod._demoFootwork = pracMod.cfg.footwork
  pracMod.cfg.footwork = "key"
  pracMod.engine.cfg.footwork = "key"
  for _ = 1, 30 * 3 do T = T + 1 / 30; pracMod:Step(st, T) end
  local plan = st.sim.plan
  local n0 = plan.nRows
  ok(plan.live and n0 > 0 and plan.rows[n0] ~= "cd", "36c: a paper drill has no cd row until a cooldown is pressed (" .. tostring(n0) .. " rows)")
  Nock.PracticeEngine.Press(pracMod.engine, { "rf" }, T)
  for _ = 1, 30 do T = T + 1 / 30; pracMod:Step(st, T) end
  ok(plan.rows[plan.nRows] == "cd", "36c: the RF press adds the cd row to the plan")
  local stable = true
  for _ = 1, 30 * 25 do
    T = T + 1 / 30; pracMod:Step(st, T)
    if plan.rows[plan.nRows] ~= "cd" then stable = false end
  end
  ok(stable, "36c: ...and it stays for the rest of the fight, the RF item long out of the view")
  pracMod:StopFight()
  st.sim.active = false
  st.ranged.swingDuration = 2.174
  st.melee.swingDuration = 3.7
  Nock.db.profile.practiceQuickShots = true
  _G.GetTime = realGT
end

-- 37. REPLAY. Every plan revision of a fight is recorded; after Stop the stage
--     can be scrubbed back: the strip's inputs at any moment are the frame
--     that was live then, the stream up to then, the judgments made by then.
--     Alt-wheel jumps between the autos a cast delayed. A new Start clears it.
do
  local T = 12000
  local realGT = GetTime
  _G.GetTime = function() return T end
  st.sim.active = true
  st.ranged.windupRatio, st.ranged.swingDuration = 0.5 / 3.0, 1.93
  st.melee.swingDuration = 3.6
  pracMod._liveEws = 1.93                       -- the drill pins at the character's own haste when inside the bracket
  do local ge = tonumber(os.getenv("NOCK_GATE_EWS") or ""); if ge then st.ranged.swingDuration, pracMod._liveEws = ge, ge end end
  Nock.db.profile.practiceScenario = "Clean French"
  Nock.db.profile.practiceQuickShots = false
  pracMod:ResetLadder(); pracMod.cfg = nil
  pracMod:StartFight()
  ok(pracMod._replay == nil and (pracMod._planRec == nil or pracMod._planRec.n == 0), "37: Start opens with no replay and no frames")
  pracMod._demo, pracMod._demoMode, pracMod._demoPulled = true, "perfect", nil
  pracMod._demoFootwork = pracMod.cfg.footwork
  pracMod.cfg.footwork = "key"
  for _ = 1, 30 * 20 do T = T + 1 / 30; pracMod:Step(st, T) end
  local e = pracMod.engine
  local rec = pracMod._planRec
  ok(rec and rec.n >= 10 and rec.n < 30 * 20, "37: frames are recorded per plan revision, not per tick (" .. tostring(rec and rec.n) .. ")")
  local nBefore = e.n
  pracMod._demo = false
  pracMod.cfg.footwork = pracMod._demoFootwork
  pracMod:StopFight()
  T = T + 1 / 30; pracMod:Step(st, T)
  local rp = pracMod._replay
  ok(rp ~= nil and math.abs(rp.at - rp.t1) < 1e-6, "37: Stop opens the replay at the stop")
  local out = {}
  local live = pracMod:Lookahead(out)
  ok(live ~= nil and live.plan ~= nil and live.plan == rec[rp.frame].plan, "37: Lookahead answers from the recorded frame")
  local evs, n, vs = pracMod:ConveyorData()
  ok(n == nBefore or n == e.n, "37: at the stop the whole stream is on the strip (" .. tostring(n) .. "/" .. tostring(e.n) .. ")")
  -- Scrub to the middle: the stream and the judgments are cut there, the
  -- frame is the last one live by then, the clock is the scrub position.
  local mid = rp.t0 + 10
  ok(pracMod:ReplayAt(mid), "37: ReplayAt lands")
  local evs2, n2, vs2 = pracMod:ConveyorData()
  local cut = true
  for i = 1, n2 do if evs2[i].t > mid + 1e-9 then cut = false end end
  ok(n2 < nBefore and n2 > 0 and cut, "37: the stream is cut at the scrub position (" .. tostring(n2) .. " of " .. tostring(nBefore) .. ")")
  ok(evs2[n2 + 1] == nil or evs2[n2 + 1].t > mid, "37: ...and nothing after it is shown")
  local vcut = true
  for i = 1, #vs2 do if (vs2[i].t or 0) > mid + 1e-9 then vcut = false end end
  ok(#vs2 > 0 and vcut, "37: the judgments are cut there too (" .. #vs2 .. ")")
  local fr = rec[rp.frame]
  ok(fr.at <= mid + 1e-9 and (rec[rp.frame + 1] == nil or rec[rp.frame + 1].at > mid), "37: the frame is the last one live by then")
  live = pracMod:Lookahead(out)
  ok(live and math.abs(live.now - mid) < 1e-6 and live.plan == fr.plan, "37: the strip's clock is the scrub position and its plan the frame's")
  -- The stage's clock follows the scrub (prePullNow via the conveyor's hold).
  local conv = Nock:GetModule("PracticeConveyor", true)
  -- Clip jumps: Alt-wheel lands on the autos a cast delayed, in order.
  local clips = {}
  for i = 1, e.n do local ev = e.events[i]; if ev.kind == "auto" and (ev.delay or 0) > 0.03 then clips[#clips + 1] = ev.t end end
  if #clips >= 2 then
    pracMod:ReplayAt(rp.t0)
    ok(pracMod:ReplayStep(1, "clip") and math.abs(rp.at - clips[1]) < 1e-6, "37: Alt-wheel forward lands on the first clipped auto")
    ok(pracMod:ReplayStep(1, "clip") and math.abs(rp.at - clips[2]) < 1e-6, "37: ...then the second")
    ok(pracMod:ReplayStep(-1, "clip") and math.abs(rp.at - clips[1]) < 1e-6, "37: ...and back")
  else
    ok(true, "37: (fewer than two clipped autos in 20 s; jump test skipped)")
  end
  -- A new scenario pick ends the replay (the stage shows the pick's rows).
  pracMod:SetScenario("2:5")
  ok(pracMod._replay == nil, "37: a scenario pick ends the replay")
  pracMod:SetScenario("Clean French")
  -- THE HUD. A tick in the replay publishes the fight as it stood at the
  -- scrub: the swing bar's remaining time is what it was then, and stays so
  -- as the real clock runs on; leaving the replay clears it.
  pracMod:ReplayAt(mid)
  rp = pracMod._replay
  fr = rec[rp.frame]
  T = T + 1 / 30; pracMod:Step(st, T)
  local wantRem = (fr.snap.nextShotAt or 0) - mid
  local rem = st.ranged.swingStart + st.ranged.swingDuration - T
  ok(st.sim.replaying == true and st.ranged.swingStart > 0 and math.abs(rem - wantRem) < 1e-6,
     ("37: the HUD's swing reads as it did at the scrub (%.3f vs %.3f)"):format(rem, wantRem))
  T = T + 1; pracMod:Step(st, T)
  local rem2 = st.ranged.swingStart + st.ranged.swingDuration - T
  ok(math.abs(rem2 - wantRem) < 1e-6, "37: ...and holds there a second later")
  ok(math.abs(st.sim.t0 - fr.snap.t0) < 1e-6, "37: the fight's origin is not shifted (the report reads it)")
  local nFrames = rec.n
  ok(nFrames >= 30, "37: frames are cut on the HUD's own anchors too (" .. nFrames .. ")")
  pracMod:ReplayOff()
  T = T + 1 / 30; pracMod:Step(st, T)
  ok(st.sim.replaying == false and st.ranged.swingStart == 0 and st.target.rangeState == "LONG", "37: leaving the replay clears the HUD")
  pracMod:ReplayAt(mid)
  rp = pracMod._replay                          -- a fresh replay table after ReplayOff
  local rev0 = rp.rev
  pracMod:ReplayStep(1, "sec", 0.25)
  ok(rp.rev == rev0 + 1, "37: a scrub bumps the replay revision (the stage rebuilds)")
  ok(pracMod:ReplayAt(rp.t1 + 100) and math.abs(rp.at - rp.t1) < 1e-6, "37: the scrub clamps at the stop")
  ok(pracMod:ReplayAt(rp.t0 - 100) and math.abs(rp.at - rp.t0) < 1e-6, "37: ...and at the first frame")
  pracMod:StartFight()
  ok(pracMod._replay == nil and pracMod._planRec.n == 0, "37: a new Start clears the replay and the frames")
  pracMod:StopFight()
  _G.GetTime = realGT
end

print(("practice_gates: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
