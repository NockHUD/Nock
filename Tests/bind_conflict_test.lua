-- Tests/bind_conflict_test.lua
-- Standalone LuaJIT tests for Modules/BindCheck.lua — what ELSE is bound to the
-- weave key, the one key Nock claims.
-- Run from the repo root: luajit Tests/bind_conflict_test.lua
--
-- The feature claims its key with SetOverrideBindingClick(..., priority=true),
-- so Nock always WINS the key and the user's own action on it goes quiet with no
-- symptom. The Steam Tonk hold key was the second claimant until 1.0.19; when it
-- was retired the nock-vs-nock self-conflict case went with it, so cases 3 and 9
-- below moved onto the weave slot or were dropped outright. This module is the producer that notices; the Settings note and the
-- HUD warning square are its two consumers.
--
-- The WoW surface is stubbed below. `equipped`-style fixtures model the three
-- ways a key can be spoken for on this client: a Blizzard bar binding
-- (ACTIONBUTTON2), a bar addon's CLICK binding (Dominos is installed on this
-- client and registers "CLICK DominosActionButton4:HOTKEY"), and an ordinary
-- named binding (TOGGLEWORLDMAP).

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function has(s, sub, name)
  ok(type(s) == "string" and s:find(sub, 1, true) ~= nil,
     name .. (type(s) == "string" and ("  (got: " .. s .. ")") or "  (not a string)"))
end

--------------------------------------------------------------------------------
-- Fixtures the stubs read
--------------------------------------------------------------------------------
local bindings   = {}   -- [key] = binding action string (the BASE binding set)
local overrides  = {}   -- [key] = effective action incl. overrides
local slots      = {}   -- [actionSlot] = { type=, id=, text= } or nil for empty
local frames     = {}   -- [frameName] = fake frame with .action
local page       = 1

local Nock = { state = {}, db = { profile = {} } }
local BindCheck

function Nock:NewModule()
  BindCheck = {}
  function BindCheck:RegisterEvent() end
  function BindCheck:RegisterMessage() end
  function BindCheck:ScheduleTimer(fn) if type(fn) == "function" then fn() end end
  function BindCheck:CancelTimer() end
  function BindCheck:Print() end
  return BindCheck
end
function Nock:Print() end

_G.LibStub = function() return { GetAddon = function() return Nock end } end

-- GetBindingAction(key [, checkOverride]). The second argument is NOT verified
-- to exist on this client, so the module must never depend on it: a client that
-- ignores it just returns the base action, which must not read as "someone else
-- stole the key".
_G.GetBindingAction = function(key, checkOverride)
  if checkOverride then return overrides[key] or bindings[key] or "" end
  return bindings[key] or ""
end
_G.GetActionBarPage = function() return page end
_G.HasAction        = function(slot) return slots[slot] ~= nil end
_G.GetActionInfo    = function(slot)
  local s = slots[slot]
  if not s then return nil end
  return s.type, s.id, s.sub
end
_G.GetActionText    = function(slot) return slots[slot] and slots[slot].text end
_G.GetSpellInfo     = function(id) return "Spell" .. id, nil, "icon" end
_G.GetItemInfo      = function(id) return "Item" .. id end
_G.InCombatLockdown = function() return false end

_G.BINDING_NAME_TOGGLEWORLDMAP = "Toggle World Map"

-- Frame lookups go through _G, so the fake frames live there too.
setmetatable(_G, { __index = function(_, k) return frames[k] end })

dofile("Core/State.lua")
dofile("Modules/BindCheck.lua")

local function reset()
  bindings, overrides, slots, frames, page = {}, {}, {}, {}, 1
  Nock.db.profile = {
    weaveBindEnabled = true, weaveBindKey = "",
  }
end

local function weave() return Nock.state.binds.weave end

--------------------------------------------------------------------------------
-- 1. Nothing set, nothing bound: no conflict, and the state slot still exists.
--------------------------------------------------------------------------------
reset()
BindCheck:Recompute()
ok(weave() ~= nil, "state.binds has a slot per feature")
-- The warning square is one short line, so it names the FEATURE and the KEY
-- rather than the displaced action. Both come from here so the square, the
-- Settings page title and /nock binds all say the same words.
ok(weave().label == "Weave Bind", "the feature's own name is published for views")
ok(weave().conflict == nil, "no key set means no conflict")

Nock.db.profile.weaveBindKey = "V"
BindCheck:Recompute()
ok(weave().conflict == nil, "a key nothing else is bound to is free")
ok(weave().key == "V", "the resolved key is published")

--------------------------------------------------------------------------------
-- 2. A Blizzard action-bar binding, resolved through the bar frame, naming the
--    spell that is actually in the slot. This is the case the user hit.
--------------------------------------------------------------------------------
reset()
Nock.db.profile.weaveBindKey = "4"
bindings["4"] = "ACTIONBUTTON2"
frames["ActionButton2"] = { action = 2 }
slots[2] = { type = "spell", id = 27021 }
BindCheck:Recompute()
ok(weave().conflict ~= nil,               "a bound action-bar key is a conflict")
ok(weave().conflict.kind == "action",     "classified as an action-bar conflict")
ok(weave().conflict.label == "Spell27021", "names the spell in the slot")
has(BindCheck:Note("weave"), "Spell27021", "the Settings note names the spell")
ok(BindCheck:ShouldWarn("weave") == true, "a slot with a real spell in it does warrant a warning")

--------------------------------------------------------------------------------
-- 3. No bar frame to read (a bar addon replaced Blizzard's): fall back to the
--    arithmetic slot map. MULTIACTIONBAR1BUTTON3 is Bottom Left slot 63.
--------------------------------------------------------------------------------
reset()
Nock.db.profile.weaveBindKey = "SHIFT-E"
bindings["SHIFT-E"] = "MULTIACTIONBAR1BUTTON3"
slots[63] = { type = "macro", id = 7, text = "Trap Weave" }
BindCheck:Recompute()
ok(weave().conflict.kind == "action", "resolves without a frame, via the slot map")
ok(weave().conflict.label == "Trap Weave", "names the macro by its macro name")

--------------------------------------------------------------------------------
-- 4. ACTIONBUTTON1-12 follow the current bar page when no frame is available.
--------------------------------------------------------------------------------
reset()
page = 2
Nock.db.profile.weaveBindKey = "1"
bindings["1"] = "ACTIONBUTTON1"
slots[13] = { type = "item", id = 22838 }
BindCheck:Recompute()
ok(weave().conflict.label == "Item22838", "page 2 shifts ACTIONBUTTON1 to slot 13")

--------------------------------------------------------------------------------
-- 5. A bar addon's CLICK binding (Dominos): resolve the frame it clicks and read
--    the action slot off it.
--------------------------------------------------------------------------------
reset()
Nock.db.profile.weaveBindKey = "BUTTON4"
bindings["BUTTON4"] = "CLICK DominosActionButton4:HOTKEY"
frames["DominosActionButton4"] = { action = 40 }
slots[40] = { type = "spell", id = 34026 }
BindCheck:Recompute()
ok(weave().conflict.kind == "action",      "a CLICK binding to a bar button is an action conflict")
ok(weave().conflict.label == "Spell34026", "names the spell behind the addon's button")

-- Dominos' cast-on-press helper is a child button that inherits its parent's
-- action ("useparent-action"), so the slot lives on the PARENT frame.
reset()
Nock.db.profile.weaveBindKey = "BUTTON4"
bindings["BUTTON4"] = "CLICK DominosActionButton4Hotkey:HOTKEY"
frames["DominosActionButton4"] = { action = 41 }
frames["DominosActionButton4Hotkey"] = { parent = frames["DominosActionButton4"] }
frames["DominosActionButton4Hotkey"].GetParent = function(self) return self.parent end
slots[41] = { type = "spell", id = 1978 }
BindCheck:Recompute()
ok(weave().conflict.label == "Spell1978", "falls through to the parent frame's action")

--------------------------------------------------------------------------------
-- 6. A CLICK binding we cannot resolve at all still reports the frame, rather
--    than pretending the key is free.
--------------------------------------------------------------------------------
reset()
Nock.db.profile.weaveBindKey = "F"
bindings["F"] = "CLICK SomeMysteryButton:LeftButton"
BindCheck:Recompute()
ok(weave().conflict.kind == "click", "an unresolvable CLICK binding is still a conflict")
has(weave().conflict.label, "SomeMysteryButton", "names the button it clicks")

--------------------------------------------------------------------------------
-- 7. An ordinary named binding, localized through BINDING_NAME_*.
--------------------------------------------------------------------------------
reset()
Nock.db.profile.weaveBindKey = "M"
bindings["M"] = "TOGGLEWORLDMAP"
BindCheck:Recompute()
ok(weave().conflict.kind == "binding",           "a named binding is a conflict")
ok(weave().conflict.label == "Toggle World Map", "uses the localized binding name")

-- Unknown token: fall back to the raw action rather than showing nothing.
reset()
Nock.db.profile.weaveBindKey = "M"
bindings["M"] = "SOMEADDON_DO_THING"
BindCheck:Recompute()
ok(weave().conflict.label == "SOMEADDON_DO_THING", "unknown binding shows its raw name")

--------------------------------------------------------------------------------
-- 8. A bound-but-EMPTY action slot. Still reported (the binding is real), but
--    said honestly so the user can judge it as harmless.
--------------------------------------------------------------------------------
reset()
Nock.db.profile.weaveBindKey = "6"
bindings["6"] = "ACTIONBUTTON6"
frames["ActionButton6"] = { action = 6 }   -- slots[6] left nil: empty slot
BindCheck:Recompute()
ok(weave().conflict.kind == "action", "an empty but bound bar slot is still reported")
ok(weave().conflict.empty == true,    "flagged as empty")
has(BindCheck:Note("weave"), "empty",  "the note says the slot is empty")
-- ...but it must NOT raise a warning square. Confirmed in-game 2026-08-13: a
-- Dominos button with nothing on it produced a nag for a key that cost nothing.
ok(BindCheck:ShouldWarn("weave") == false, "an empty slot never warrants a warning")

--------------------------------------------------------------------------------
-- 9. RETIRED with the Steam Tonk hold key in 1.0.19. It covered two Nock
--    features claiming the SAME key, where whichever applied last owned it and
--    the other silently died. With one claimant left that cannot happen, so the
--    branch was removed from BindCheck rather than left as untestable code.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 10. The producer publishes unconditionally. Gating state on the feature's own
--     enable flag would make a display decision at the producer, which is the
--     mistake the project rules call out; the warning view does that gating instead.
--------------------------------------------------------------------------------
reset()
Nock.db.profile.weaveBindEnabled = false
Nock.db.profile.weaveBindKey = "4"
bindings["4"] = "TOGGLEWORLDMAP"
BindCheck:Recompute()
ok(weave().conflict ~= nil,     "conflict is computed even while the feature is off")
ok(weave().enabled == false,    "the enable flag is published for views to gate on")

--------------------------------------------------------------------------------
-- 11. Positive confirmation only: if the client honours the checkOverride
--     argument we can prove Nock currently owns the key. If it does not, we must
--     stay silent rather than claim Nock has lost the key.
--------------------------------------------------------------------------------
reset()
Nock.db.profile.weaveBindKey = "4"
bindings["4"]  = "ACTIONBUTTON2"
overrides["4"] = "CLICK NockWeaveBindButton:LeftButton"
frames["ActionButton2"] = { action = 2 }
slots[2] = { type = "spell", id = 27021 }
BindCheck:Recompute()
ok(weave().ownedByNock == true, "Nock's own override is recognised as ours")

reset()   -- no override table entry = a client that ignores the second argument
Nock.db.profile.weaveBindKey = "4"
bindings["4"] = "ACTIONBUTTON2"
frames["ActionButton2"] = { action = 2 }
slots[2] = { type = "spell", id = 27021 }
BindCheck:Recompute()
ok(weave().ownedByNock == false, "no false ownership claim when checkOverride is ignored")

--------------------------------------------------------------------------------
print(("bind_conflict_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
