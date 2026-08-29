-- Tests/action_glow_engine_test.lua
-- Standalone LuaJIT tests for the pure action-bar glow engine: which action
-- slots hold Kill Command, which bar buttons drive those slots, and the
-- start/stop diff that turns a proc edge into glow calls.
-- Run from the repo root: luajit Tests/action_glow_engine_test.lua

local E = dofile("Modules/ActionGlowEngine.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

local KC = 34026

--------------------------------------------------------------------------------
-- 1. SlotsFor: scan action slots for the spell (direct or through a macro)
--------------------------------------------------------------------------------
local bar = {
  [3]  = { "spell", KC },
  [7]  = { "spell", 27014 },        -- Raptor Strike: not ours
  [14] = { "macro", 5 },            -- macro 5 casts Kill Command
  [15] = { "macro", 6 },            -- macro 6 casts something else
  [72] = { "spell", KC },           -- KC on a second bar too
  [121] = { "spell", KC },          -- past the last slot: never scanned
}
local function getActionInfo(slot)
  local a = bar[slot]
  if not a then return nil end
  return a[1], a[2]
end
local function macroSpell(macroId)
  if macroId == 5 then return KC end
  return nil
end

local slots = E.SlotsFor(getActionInfo, { [KC] = true }, macroSpell)
ok(slots[3] and slots[72] and slots[14], "direct KC slots and the KC macro slot are found")
ok(not slots[7] and not slots[15], "other spells and other macros are skipped")
ok(not slots[121], "scan stops at slot 120")
ok(count(slots) == 3, "exactly three slots")

local none = E.SlotsFor(function() return nil end, { [KC] = true }, nil)
ok(count(none) == 0, "an empty bar yields no slots")

-- No macroSpell resolver (client without GetMacroSpell): macros are ignored.
local noMacro = E.SlotsFor(getActionInfo, { [KC] = true }, nil)
ok(noMacro[3] and not noMacro[14], "macros are skipped when macro spells cannot be read")

--------------------------------------------------------------------------------
-- 2. FrameSlot: the action slot a bar button drives, whatever bar addon
--------------------------------------------------------------------------------
ok(E.FrameSlot({ action = 3 }) == 3,                     "Blizzard/Dominos: .action")
ok(E.FrameSlot({ action = "72" }) == 72,                 ".action as a string still reads")
ok(E.FrameSlot({ _state_action = 14 }) == 14,            "LibActionButton (Bartender/ElvUI): _state_action")
ok(E.FrameSlot({ GetAttribute = function(_, k) return k == "action" and 5 or nil end }) == 5,
   "secure attribute 'action' as the last resort")
ok(E.FrameSlot({}) == nil,                               "a frame with no slot answers nil")
ok(E.FrameSlot({ action = 0 }) == nil,                   "slot 0 is not a slot")

--------------------------------------------------------------------------------
-- 3. ButtonsFor: the frames to glow for a slot set, deduplicated
--------------------------------------------------------------------------------
local fA, fB, fC, fD = { action = 3 }, { action = 72 }, { action = 9 }, { _state_action = 3 }
local frames = E.ButtonsFor(slots, { fA, fB, fC, fD, fA })
ok(frames[fA] and frames[fB] and frames[fD], "every button driving a KC slot is picked")
ok(not frames[fC], "a button on another slot is not")
ok(count(frames) == 3, "a frame listed twice is picked once")

--------------------------------------------------------------------------------
-- 4. CandidateNames: every bar family we know, no duplicates
--------------------------------------------------------------------------------
local names = E.CandidateNames()
local seen, dup = {}, false
for _, n in ipairs(names) do if seen[n] then dup = true end; seen[n] = true end
ok(not dup, "candidate names are unique")
ok(seen["ActionButton1"] and seen["MultiBarBottomLeftButton12"], "Blizzard bars")
ok(seen["DominosActionButton1"] and seen["DominosActionButton120"], "Dominos 1..120")
ok(seen["BT4Button1"] and seen["BT4Button120"], "Bartender4 1..120")
ok(seen["ElvUI_Bar1Button1"] and seen["ElvUI_Bar10Button12"], "ElvUI bars 1..10 x 12")

--------------------------------------------------------------------------------
-- 5. Diff: proc edges become start/stop lists; unchanged frames are untouched
--------------------------------------------------------------------------------
local was  = { [fA] = true, [fB] = true }
local want = { [fB] = true, [fD] = true }
local start, stop = E.Diff(was, want)
ok(#start == 1 and start[1] == fD, "a newly wanted frame starts")
ok(#stop == 1 and stop[1] == fA,   "a no-longer wanted frame stops")

local s2, p2 = E.Diff(want, want)
ok(#s2 == 0 and #p2 == 0, "same set: nothing to do")

local s3, p3 = E.Diff(want, {})
ok(#s3 == 0 and #p3 == 2, "proc over: every glowing frame stops")

--------------------------------------------------------------------------------
-- 6. Wanted: the glow set is the buttons only while enabled AND the proc is up
--------------------------------------------------------------------------------
ok(count(E.Wanted(true,  true,  frames)) == 3, "enabled + proc: the buttons")
ok(count(E.Wanted(true,  false, frames)) == 0, "enabled, no proc: nothing")
ok(count(E.Wanted(false, true,  frames)) == 0, "disabled: nothing even during the proc")

--------------------------------------------------------------------------------
-- 7. UsableProc: the WA's rule -- usable and not on cooldown
--------------------------------------------------------------------------------
ok(E.UsableProc(true,  false) == true,  "usable, off cooldown: proc")
ok(E.UsableProc(true,  true)  == false, "usable but on cooldown: no proc")
ok(E.UsableProc(false, false) == false, "not usable: no proc")
ok(E.UsableProc(nil,   nil)   == false, "unknown: no proc (never nil)")
ok(E.UsableProc(true,  false, true)  == true,  "usable, off cooldown, pet alive: proc")
ok(E.UsableProc(true,  false, false) == false, "usable but no pet / pet dead: no proc (KC reads usable without a pet)")
ok(E.UsableProc(true,  false, nil)   == true,  "no pet requirement: as before")

print(("action_glow_engine: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
