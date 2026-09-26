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
  function f:SetAllPoints(r) self.allPoints = r end
  if name then frames[name] = f; _G[name] = f end
  return f
end
_G.CreateFrame = newFrame
local combat = false
_G.InCombatLockdown = function() return combat end
local cursorX, cursorY = 500, 400
_G.GetCursorPosition = function() return cursorX, cursorY end
_G.UIParent = { GetEffectiveScale = function() return 1 end, GetWidth = function() return 1000 end, GetHeight = function() return 800 end }
local wraps = {}
_G.SecureHandlerWrapScript = function(frame, script, header, pre)
  if _G.InCombatLockdown() then error("ADDON_ACTION_BLOCKED WrapScript") end
  wraps[#wraps + 1] = { frame = frame, script = script, header = header, pre = pre }
end
_G.SecureHandlerSetFrameRef = function(frame, label, ref) frame.attrs["frameref-" .. label] = ref end

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

-- The dial layout: a profile list of keys, cleaned on read.
local O = Nock.AspectRingOrder
local function j(t) return table.concat(t, ",") end
ok(j(O(nil)) == "hawk,monkey,wild,cheetah,pack,beast", "no stored layout: the default")
ok(j(O({ "cheetah", "monkey", "wild", "hawk", "pack", "beast" })) == "cheetah,monkey,wild,hawk,pack,beast", "a valid layout is kept")
ok(j(O({ "cheetah", "cheetah", "bogus", 7 })) == "cheetah,hawk,monkey,wild,pack,beast", "duplicates and junk dropped, the missing appended in default order")
ok(j(O("hawk")) == "hawk,monkey,wild,cheetah,pack,beast", "a non-table: the default")
local def = O(nil); def[1] = "pack"
ok(O(nil)[1] == "hawk", "the default is never handed out mutable")
local Sw = Nock.AspectRingSwap
ok(j(Sw(O(nil), 1, "cheetah")) == "cheetah,monkey,wild,hawk,pack,beast", "Cheetah picked for Up: Hawk swaps down")
ok(j(Sw(O(nil), 2, "monkey")) == "hawk,monkey,wild,cheetah,pack,beast", "picking the aspect already there: unchanged")
ok(j(Sw(O(nil), 3, "bogus")) == "hawk,monkey,wild,cheetah,pack,beast", "an unknown aspect: unchanged")

-- Key binding calls, recorded.
local binds = {}
_G.ClearOverrideBindings = function(owner) binds.cleared = (binds.cleared or 0) + 1; binds.key = nil end
_G.SetOverrideBindingClick = function(owner, prio, key, name) binds.key, binds.prio, binds.name = key, prio, name end
Nock.db = { profile = {} }

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

-- The snippet's pick equals AspectRingPick (dot product, no atan2).
do
  local mismatch = 0
  for dx = -60, 60, 3 do
    for dy = -60, 60, 3 do
      if Nock.AspectRingPickDot(dx, dy, 14) ~= Nock.AspectRingPick(dx, dy, 14) then mismatch = mismatch + 1 end
    end
  end
  ok(mismatch == 0, "PickDot == Pick over a 41x41 grid of flicks")
end

-- Armed out of combat: both edges, a full-screen header, the wrapped OnClick,
-- the frame ref to the drawn ring, and the attributes the snippet reads.
ok(#wraps == 1 and wraps[1].frame == b and wraps[1].script == "OnClick", "the key's OnClick is wrapped")
local header = wraps[1].header
ok(header and header.allPoints == UIParent and frames.NockAspectRingScreen == header, "header covers the screen")
ok(b.attrs.aspect1 == "Aspect of the Hawk" and b.attrs.aspect4 == "Aspect of the Cheetah" and b.attrs.aspect3 == nil, "learned names per slot")
ok(b.attrs.dead == 14 and b.attrs.scale == 1 and b.attrs.sw == 1000 and b.attrs.sh == 800, "cancel radius, size and screen in UI units")

-- Run the REAL snippet text against fake secure handles.
local snippet = assert(loadstring("local self, button, down, control = ...\n" .. wraps[1].pre))
local mouse = { x = 0.5, y = 0.5 }
local control = { GetMousePosition = function() return mouse.x, mouse.y end }
local layer = { shown = false }
function layer:ClearAllPoints() self.point = nil end
function layer:SetPoint(p, rel, rp, x, y) self.point = { p, rel, rp, x, y } end
function layer:Show() self.shown = true end
function layer:Hide() self.shown = false end
local handle = { a = {} }
function handle:GetAttribute(k) if self.a[k] ~= nil then return self.a[k] end return b.attrs[k] end
function handle:SetAttribute(k, v) self.a[k] = v end
function handle:GetFrameRef(k) return k == "layer" and layer or nil end
local function press(x0, y0, x1, y1)
  handle.a = {}
  mouse.x, mouse.y = x0, y0
  local r1 = snippet(handle, "LeftButton", true, control)
  local shownOnDown = layer.shown
  mouse.x, mouse.y = x1, y1
  local r2 = snippet(handle, "LeftButton", false, control)
  return r1, r2, shownOnDown
end
-- flick up 60 UI units (60/800 of the screen height): Hawk
local r1, r2, shown = press(0.5, 0.5, 0.5, 0.5 + 60 / 800)
ok(r1 == false and shown == true and layer.point[4] == 500 and layer.point[5] == 400, "down: nothing cast, the ring shown at the cursor")
ok(r2 == nil and handle.a.type == "macro" and handle.a.macrotext == "/cast !Aspect of the Hawk" and handle.a.useOnKeyDown == false and layer.shown == false,
   "flick up + release: Hawk on the release, ring hidden")
r1, r2 = press(0.5, 0.5, 0.5, 0.5 - 60 / 800)
ok(handle.a.macrotext == "/cast !Aspect of the Cheetah", "flick down: Cheetah")
r1, r2 = press(0.5, 0.5, 0.5 + 5 / 1000, 0.5 + 5 / 800)
ok(r2 == false and handle.a.type == nil and layer.shown == false, "release in the cancel circle: nothing (a tap cancels, in combat too)")
r1, r2 = press(0.5, 0.5, 0.5 - 50 / 1000, 0.5 - 25 / 800)
ok(r2 == false and handle.a.type == nil, "flick to an unlearned slot (Pack): nothing")
handle.a = {}
mouse.x, mouse.y = 0.5, 0.6
ok(snippet(handle, "LeftButton", false, control) == false and handle.a.type == nil, "an up with no down before it: nothing")

-- PreClick only draws: down opens, up closes; never an attribute, so it is
-- safe in combat.
local pre = b.scripts.PreClick
combat = true
cursorX, cursorY = 500, 400
pre(b, "LeftButton", true)
ok(st.open == true and st.cx == 500 and st.cy == 400, "in combat: down opens the drawn ring (state only)")
cursorX, cursorY = 500, 460
A:Refresh(Nock.state)
ok(st.hover == 1, "hover follows the cursor while open")
pre(b, "LeftButton", false)
ok(st.open == false, "up closes it")
combat = false

-- The screen size follows the live UIParent (a login capture can predate
-- the UI scale): a tick out of combat re-pushes a mismatch, not in combat.
do
  local w0 = UIParent.GetWidth
  UIParent.GetWidth = function() return 2560 end
  UIParent.GetHeight = function() return 1440 end
  combat = true
  A:Refresh(Nock.state)
  ok(b.attrs.sw == 1000, "in combat: the stored size waits")
  combat = false
  A:Refresh(Nock.state)
  ok(b.attrs.sw == 2560 and b.attrs.sh == 1440, "out of combat: the live screen size is re-pushed")
  UIParent.GetWidth = w0
  UIParent.GetHeight = function() return 800 end
  A:Refresh(Nock.state)
end

-- Ring size moves the cancel circle and the draw scale, out of combat.
Nock.db.profile.aspectRingScale = 2
A:OnConfig()
ok(b.attrs.dead == 28 and b.attrs.scale == 2, "size: the snippet's cancel radius and scale follow")
Nock.db.profile.aspectRingScale = nil
A:OnConfig()

-- Changes in combat wait for its end.
learned = { ["Aspect of the Monkey"] = 13163 }
combat = true
A:UpdateKnown()
ok(b.attrs.aspect1 == "Aspect of the Hawk", "a spellbook change in combat: the button keeps its names for now")
combat = false
A:PLAYER_REGEN_ENABLED()
ok(b.attrs.aspect1 == nil and b.attrs.aspect2 == "Aspect of the Monkey", "and lands when combat ends")

-- The dial layout from the profile: the snippet's slot names follow it.
Nock.ForeverSpellbookNames = function() return { ["Aspect of the Hawk"] = 1, ["Aspect of the Cheetah"] = 2 } end
A:UpdateKnown()
Nock.db.profile.aspectRingOrder = { "cheetah", "monkey", "wild", "hawk", "pack", "beast" }
local revBefore = st.knownRev
A:OnConfig()
ok(st.order[1] == "cheetah" and st.known[1] == "Aspect of the Cheetah" and st.short[1] == "Cheetah", "slots follow the layout")
ok(st.knownRev > revBefore and b.attrs.aspect1 == "Aspect of the Cheetah" and b.attrs.aspect4 == "Aspect of the Hawk", "the button's names follow the layout")
ok(A.msgs.NOCK_ASPECT_RING_CONFIG == "OnConfig" and A.msgs.NOCK_VISUALS_CHANGED == "OnConfig", "settings and profile switches reach the ring")
ok(A.msgs.NOCK_ASPECT_RING_CLOSE == "Close", "slot clicks close the ring by message")

-- Spellbook API missing: cannot tell, every slot offered.
Nock.ForeverSpellbookNames = function() return nil end
Nock.db.profile.aspectRingOrder = nil
A:OnConfig()
ok(st.known[3] == "Aspect of the Wild" and b.attrs.aspect5 == "Aspect of the Pack", "no spellbook API: all six offered")

-- The key from Nock's settings: a priority override on the key button.
Nock.db.profile.aspectRingKey = "SHIFT-Q"
A:OnConfig()
ok(binds.key == "SHIFT-Q" and binds.prio == true and binds.name == "NockAspectRingButton", "key bound to the ring button, priority")
Nock.db.profile.aspectRingKey = ""
A:OnConfig()
ok(binds.key == nil and binds.cleared >= 1, "cleared key: the override goes")
combat = true
Nock.db.profile.aspectRingKey = "F"
A:OnConfig()
ok(binds.key == nil, "in combat the binding waits")
combat = false
A:PLAYER_REGEN_ENABLED()
ok(binds.key == "F", "and lands when combat ends")
Nock.db.profile.aspectRingKey = nil
A:OnConfig()

-- /reload inside combat: nothing secure is built or written until it ends.
frames.NockAspectRingButton = nil; _G.NockAspectRingButton = nil
A._armed = nil
local wrapsBefore = #wraps
combat = true
_G.ClearOverrideBindings = function() error("ADDON_ACTION_BLOCKED ClearOverrideBindings") end
A:OnEnable()   -- would raise ADDON_ACTION_BLOCKED from the mocks on any secure call
local b2 = frames.NockAspectRingButton
ok(b2 and next(b2.attrs) == nil and #wraps == wrapsBefore, "enabled in combat: no attribute, no wrap")
combat = false
_G.ClearOverrideBindings = function() end
A:PLAYER_REGEN_ENABLED()
ok(b2.attrs.useOnKeyDown == false and #wraps == wrapsBefore + 1 and b2.attrs.aspect1 ~= nil, "armed once combat ends")

print(("forever_aspect_ring: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
