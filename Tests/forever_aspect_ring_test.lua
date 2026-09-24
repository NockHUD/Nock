-- Tests/forever_aspect_ring_test.lua
-- Forever/AspectRing.lua: the pure ring helpers and the key button's decisions.
-- Run from the repo root: luajit Tests/forever_aspect_ring_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
_G.GetRangedHaste = function() return 0 end

-- Minimal frame mock: records attributes, scripts, shown state.
local frames = {}
local function newFrame(kind, name)
  local f = { attrs = {}, scripts = {}, shown = true, kind = kind, name = name }
  function f:SetAttribute(k, v) if _G.InCombatLockdown() then error("ADDON_ACTION_BLOCKED SetAttribute " .. k) end self.attrs[k] = v end
  function f:GetAttribute(k) return self.attrs[k] end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:RegisterForClicks(...) if _G.InCombatLockdown() then error("ADDON_ACTION_BLOCKED RegisterForClicks") end self.clicks = { ... } end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:IsShown() return self.shown end
  if name then frames[name] = f; _G[name] = f end
  return f
end
_G.CreateFrame = newFrame
local combat = false
_G.InCombatLockdown = function() return combat end
local cursorX, cursorY = 500, 400
_G.GetCursorPosition = function() return cursorX, cursorY end
_G.UIParent = { GetEffectiveScale = function() return 1 end }

local Nock = {
  Flavor = { forever = true, Plain = function(v) return v end }, Constants = {},
  API = { SpellName = function(id) return ({ [13165] = "Aspect of the Hawk", [13163] = "Aspect of the Monkey", [5118] = "Aspect of the Cheetah",
                                             [13159] = "Aspect of the Pack", [13161] = "Aspect of the Beast", [20043] = "Aspect of the Wild" })[id] end },
}
local module
function Nock:NewModule(name) module = { name = name, events = {}, msgs = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function module:RegisterMessage(m, h) self.msgs[m] = h or m end
  function module:SendMessage() end
  return module end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/Spells.lua")
dofile("Forever/Spellbook.lua")
dofile("Forever/AspectRing.lua")

-- Pure helpers.
local P = Nock.AspectRingPick
ok(P(0, 50, 14) == 1, "straight up: slot 1 (Hawk)")
ok(P(0, -50, 14) == 4, "straight down: slot 4 (Cheetah)")
ok(P(43, 25, 14) == 2, "up-right (60 deg): slot 2 (Monkey)")
ok(P(43, -25, 14) == 3, "down-right (120 deg): slot 3 (Wild)")
ok(P(-43, -25, 14) == 5, "down-left (240 deg): slot 5 (Pack)")
ok(P(-43, 25, 14) == 6, "up-left (300 deg): slot 6 (Beast)")
ok(P(24, 42, 14) == 1 and P(26, 42, 14) == 2, "the 1|2 boundary sits at 30 deg")
ok(P(-24, 42, 14) == 1 and P(-26, 42, 14) == 6, "the 6|1 boundary sits at -30 deg (wraps)")
ok(P(5, 5, 14) == nil and P(0, 13.9, 14) == nil and P(0, 14, 14) == 1, "inside the cancel circle: nil; its edge picks")
ok(P(nil, 3, 14) == nil, "a missing coordinate: nil")
local x, y = Nock.AspectRingSlotOffset(1, 45)
ok(math.abs(x) < 1e-9 and math.abs(y - 45) < 1e-9, "slot 1 sits straight up")
x, y = Nock.AspectRingSlotOffset(4, 45)
ok(math.abs(x) < 1e-9 and math.abs(y + 45) < 1e-9, "slot 4 sits straight down")
x, y = Nock.AspectRingSlotOffset(2, 45)
ok(x > 0 and y > 0, "slot 2 sits up-right (clockwise)")
ok(Nock.AspectRingMacro("Aspect of the Hawk") == "/cast !Aspect of the Hawk", "macro never toggles off")
ok(Nock.AspectRingMacro(nil) == nil, "no name: no macro")
local byKey = Nock.AspectRingIdByKey()
ok(byKey.hawk == 13165 and byKey.cheetah == 5118 and byKey.wild == 20043, "key -> base id")
local R = Nock.Spells.ASPECT_RING
ok(#R == 6 and R[1] == "hawk" and R[4] == "cheetah", "slot order: Hawk up, Cheetah down")
local st = Nock.state.aspectRing
ok(st and st.open == false and type(st.known) == "table" and st.knownRev == 0, "state slot")
-- Short names: the prefix every aspect shares, cut at a word, is dropped
-- (locale-agnostic: no English in the code).
local S = Nock.AspectRingShortNames({ "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Wild" })
ok(S[1] == "Hawk" and S[2] == "Monkey" and S[3] == "Wild", "English: 'Aspect of the ' dropped")
S = Nock.AspectRingShortNames({ "Aspekt des Falken", "Aspekt des Affen", "Aspekt der Wildnis" })
ok(S[1] == "des Falken" and S[3] == "der Wildnis", "German: cut back to the word boundary")
S = Nock.AspectRingShortNames({ "Aspect of the Hawk", nil, "Aspect of the Pack" })
ok(S[1] == "Hawk" and S[2] == nil and S[3] == "Pack", "a missing name stays missing")
S = Nock.AspectRingShortNames({ "Aspect of the Hawk" })
ok(S[1] == "Aspect of the Hawk", "one name alone: no prefix to learn, the full name")

-- The module.
local A = module
ok(A and A.name == "AspectRing" and A.refreshInterval == nil, "module AspectRing on the fast lane (it tracks the cursor)")
local learned = { ["Aspect of the Hawk"] = 14318, ["Aspect of the Cheetah"] = 5118, ["Aspect of the Monkey"] = 13163 }
Nock.ForeverSpellbookNames = function() return learned end
A:OnEnable()
local b = frames.NockAspectRingButton
ok(b and b.clicks[1] == "AnyDown" and b.clicks[2] == "AnyUp", "key button takes both edges")
ok(b.attrs.useOnKeyDown == false and b.attrs.type == nil, "ring mode: casts on release, nothing armed")
ok(st.known[1] == "Aspect of the Hawk" and st.known[4] == "Aspect of the Cheetah" and st.known[2] == "Aspect of the Monkey"
   and st.known[3] == nil and st.known[5] == nil and st.known[6] == nil, "known by spellbook name (rank 2 Hawk counts)")
ok(st.short[1] == "Hawk" and st.short[4] == "Cheetah" and st.short[3] == "Wild", "short names for every slot, learned or not")
local rev0 = st.knownRev
ok(rev0 >= 1, "knownRev moved on the first resolve")
A:UpdateKnown()
ok(st.knownRev == rev0, "unchanged spellbook keeps the rev")
dofile("Core/Bindings.lua")
ok(_G["BINDING_NAME_CLICK NockAspectRingButton:LeftButton"] == "Aspect ring (hold)" and _G.BINDING_HEADER_NOCK == "Nock"
   and _G.BINDING_NAME_NOCK_PRACTICE_STARTSTOP ~= nil, "binding labels (Forever)")
Nock.Flavor.forever = false
dofile("Core/Bindings.lua")
ok(_G["BINDING_NAME_CLICK NockAspectRingButton:LeftButton"] == "Aspect ring (WoW Forever)", "binding label on TBC says Forever only")
Nock.Flavor.forever = true

local pre = b.scripts.PreClick
-- Key down: ring opens at the cursor, nothing armed.
cursorX, cursorY = 500, 400
pre(b, "LeftButton", true)
ok(st.open == true and st.cx == 500 and st.cy == 400 and st.hover == nil and b.attrs.type == nil, "down: ring at the cursor, nothing armed")
-- Flick down, release: Cheetah.
cursorX, cursorY = 502, 340
pre(b, "LeftButton", false)
ok(b.attrs.type == "macro" and b.attrs.macrotext == "/cast !Aspect of the Cheetah" and st.open == false, "flick down + release: Cheetah armed for the release click, ring closed")
-- Down again clears the previous arm.
cursorX, cursorY = 500, 400
pre(b, "LeftButton", true)
ok(b.attrs.type == nil and st.open, "down clears the last cast")
-- Release in the centre: nothing.
cursorX, cursorY = 503, 404
pre(b, "LeftButton", false)
ok(b.attrs.type == nil and st.open == false, "release in the cancel circle: nothing")
-- Unlearned slot: nothing.
pre(b, "LeftButton", true)
cursorX, cursorY = 460, 380   -- down-left: Pack, not learned
A:Refresh(Nock.state)
ok(st.hover == nil, "an unlearned slot never highlights")
pre(b, "LeftButton", false)
ok(b.attrs.type == nil, "release on an unlearned slot: nothing")
-- Hover follows the tick while open.
cursorX, cursorY = 500, 400
pre(b, "LeftButton", true)
cursorX, cursorY = 500, 460
A:Refresh(Nock.state)
ok(st.hover == 1, "tick: flick up highlights Hawk")
-- Down twice (the up never arrived): re-opens cleanly at the new cursor.
cursorX, cursorY = 700, 300
pre(b, "LeftButton", true)
ok(st.open and st.cx == 700 and st.cy == 300 and st.hover == nil and b.attrs.type == nil, "a second down re-opens at the new cursor")
-- A slot click closes through the message.
ok(A.msgs.NOCK_ASPECT_RING_CLOSE == "Close", "slot clicks close the ring by message")
A:Close()
ok(st.open == false and st.hover == nil, "close")

-- Combat: Hawk on the key, ring closed, PreClick inert.
pre(b, "LeftButton", true)
A:PLAYER_REGEN_DISABLED()
combat = true
ok(st.open == false and b.attrs.type == "macro" and b.attrs.macrotext == "/cast !Aspect of the Hawk" and b.attrs.useOnKeyDown == nil,
   "combat start: ring closed, Hawk armed, the client's key-down option decides the edge")
pre(b, "LeftButton", true); pre(b, "LeftButton", false)
ok(st.open == false and b.attrs.macrotext == "/cast !Aspect of the Hawk", "in combat the key never opens the ring or re-arms")
combat = false
A:PLAYER_REGEN_ENABLED()
ok(b.attrs.type == nil and b.attrs.useOnKeyDown == false, "combat end: back to ring mode")

-- Hawk not learned: the combat key casts nothing.
learned = { ["Aspect of the Monkey"] = 13163 }
A:UpdateKnown()
ok(st.known[1] == nil and st.knownRev == rev0 + 1, "spellbook change: Hawk gone, rev moved")
A:PLAYER_REGEN_DISABLED()
ok(b.attrs.type == nil, "no Hawk learned: combat key stays empty")
A:PLAYER_REGEN_ENABLED()

-- Spellbook API missing: cannot tell, every slot offered.
Nock.ForeverSpellbookNames = function() return nil end
A:UpdateKnown()
ok(st.known[3] == "Aspect of the Wild" and st.known[5] == "Aspect of the Pack", "no spellbook API: all six offered")

-- /reload inside combat: enable touches no attribute until combat ends.
frames.NockAspectRingButton = nil; _G.NockAspectRingButton = nil
combat = true
A:OnEnable()   -- would raise ADDON_ACTION_BLOCKED from the mock on any SetAttribute
local b2 = frames.NockAspectRingButton
ok(b2 and next(b2.attrs) == nil, "enabled in combat: no attribute touched")
combat = false
A:PLAYER_REGEN_ENABLED()
ok(b2.attrs.useOnKeyDown == false, "armed for the ring once combat ends")

print(("forever_aspect_ring: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
