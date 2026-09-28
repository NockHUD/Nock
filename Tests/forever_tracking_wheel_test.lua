-- Tests/forever_tracking_wheel_test.lua
-- Forever/TrackingWheel.lua: the aspect ring's mechanism (Forever/AspectRing.lua
-- factory) with the eight Track spells; the key button, the snippet, the state.
-- Run from the repo root: luajit Tests/forever_tracking_wheel_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
_G.GetRangedHaste = function() return 0 end

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
_G.ClearOverrideBindings = function() end
local binds = {}
_G.SetOverrideBindingClick = function(owner, prio, key, name) binds.key, binds.prio, binds.name = key, prio, name end

local NAMES = {
  [1494] = "Track Beasts", [19883] = "Track Humanoids", [19884] = "Track Undead", [19878] = "Track Demons",
  [19879] = "Track Dragonkin", [19880] = "Track Elementals", [19882] = "Track Giants", [19885] = "Track Hidden",
  [13165] = "Aspect of the Hawk", [13163] = "Aspect of the Monkey", [5118] = "Aspect of the Cheetah",
  [13159] = "Aspect of the Pack", [13161] = "Aspect of the Beast", [20043] = "Aspect of the Wild",
}
local Nock = {
  Flavor = { forever = true, Plain = function(v) return v end }, Constants = {},
  API = { SpellName = function(id) return NAMES[id] end },
  db = { profile = {} },
}
local modules = {}
function Nock:NewModule(name) local m = { name = name, events = {}, msgs = {} }
  function m:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function m:RegisterMessage(mm, h) self.msgs[mm] = h or mm end
  function m:SendMessage() end
  modules[name] = m; return m end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/Spells.lua")
dofile("Forever/Spellbook.lua")
dofile("Forever/AspectRing.lua")
dofile("Forever/TrackingWheel.lua")

-- Eight slots: 45-degree wedges, Beasts up, clockwise.
local P = Nock.AspectRingPick
ok(P(0, 50, 14, 8) == 1, "straight up: slot 1 (Beasts)")
ok(P(50, 50, 14, 8) == 2, "up-right (45 deg): slot 2 (Humanoids)")
ok(P(50, 0, 14, 8) == 3 and P(0, -50, 14, 8) == 5 and P(-50, 0, 14, 8) == 7, "right 3, down 5, left 7")
ok(P(-50, 50, 14, 8) == 8, "up-left: slot 8 (Hidden)")
ok(P(19, 46, 14, 8) == 1 and P(21, 46, 14, 8) == 2, "the 1|2 boundary sits at 22.5 deg")
do
  local mismatch = 0
  for dx = -60, 60, 3 do for dy = -60, 60, 3 do
    if Nock.AspectRingPickDot(dx, dy, 14, 8) ~= P(dx, dy, 14, 8) then mismatch = mismatch + 1 end
  end end
  ok(mismatch == 0, "PickDot == Pick over the grid with eight slots")
end
local S = Nock.AspectRingShortNames({ "Track Beasts", "Track Humanoids", "Track Undead", "Track Demons", "Track Dragonkin", "Track Elementals", "Track Giants", "Track Hidden" }, 8)
ok(S[1] == "Beasts" and S[8] == "Hidden" and S[5] == "Dragonkin", "short names: 'Track ' dropped from all eight")
ok(Nock.TrackingWheelIdByKey().beasts == 1494 and Nock.TrackingWheelIdByKey().hidden == 19885, "key -> Track spell id")
ok(Nock.TrackingWheelScale({}) == 1 and Nock.TrackingWheelScale({ trackingWheelScale = 1.5 }) == 1.5 and Nock.TrackingWheelScale({ trackingWheelScale = 9 }) == 2, "size from trackingWheelScale, clamped")

-- The module: the aspect ring's shape under its own names.
local W = modules.TrackingWheel
ok(W and W.refreshInterval == nil, "module TrackingWheel on the fast lane")
local A = modules.AspectRing
ok(A and A ~= W, "the aspect ring is its own instance still")
local st = Nock.state.trackingWheel
ok(st and st.open == false and type(st.known) == "table" and st.knownRev == 0, "state slot trackingWheel")
local learned = { ["Track Beasts"] = 1, ["Track Humanoids"] = 1, ["Track Hidden"] = 1 }
Nock.ForeverSpellbookNames = function() return learned end
W:OnEnable()
local b = frames.NockTrackingWheelButton
ok(b and b.clicks[1] == "AnyDown" and b.clicks[2] == "AnyUp" and b.attrs.useOnKeyDown == false, "key button NockTrackingWheelButton, both edges, casts on release")
ok(st.known[1] == "Track Beasts" and st.known[2] == "Track Humanoids" and st.known[8] == "Track Hidden" and st.known[3] == nil, "known by spellbook name")
ok(st.short[3] == "Undead" and st.order[1] == "beasts" and st.order[8] == "hidden", "short names and the fixed order")
ok(#wraps == 1 and wraps[1].frame == b and frames.NockTrackingWheelScreen == wraps[1].header, "its own wrapped OnClick and screen header")
ok(b.attrs.track1 == "Track Beasts" and b.attrs.track8 == "Track Hidden" and b.attrs.track3 == nil and b.attrs.aspect1 == nil, "slot names under the track prefix")
ok(b.attrs["frameref-layer"] == nil or b.attrs["frameref-layer"] == _G.NockTrackingWheelLayer, "layer ref is the wheel's own layer")

-- The real snippet against fake handles.
local snippet = assert(loadstring("local self, button, down, control = ...\n" .. wraps[1].pre))
local mouse = { x = 0.5, y = 0.5 }
local control = { GetMousePosition = function() return mouse.x, mouse.y end }
local layer = { shown = false }
function layer:ClearAllPoints() end
function layer:SetPoint() end
function layer:Show() self.shown = true end
function layer:Hide() self.shown = false end
local handle = { a = {} }
function handle:GetAttribute(k) if self.a[k] ~= nil then return self.a[k] end return b.attrs[k] end
function handle:SetAttribute(k, v) self.a[k] = v end
function handle:GetFrameRef(k) return k == "layer" and layer or nil end
local function press(x0, y0, x1, y1)
  handle.a = {}
  mouse.x, mouse.y = x0, y0
  snippet(handle, "LeftButton", true, control)
  mouse.x, mouse.y = x1, y1
  return snippet(handle, "LeftButton", false, control)
end
press(0.5, 0.5, 0.5, 0.5 + 60 / 800)
ok(handle.a.type == "macro" and handle.a.macrotext == "/cast !Track Beasts", "flick up: Track Beasts")
press(0.5, 0.5, 0.5 + 42 / 1000, 0.5 + 42 / 800)
ok(handle.a.macrotext == "/cast !Track Humanoids", "flick up-right: Track Humanoids")
press(0.5, 0.5, 0.5 - 42 / 1000, 0.5 + 42 / 800)
ok(handle.a.macrotext == "/cast !Track Hidden", "flick up-left: Track Hidden")
local r = press(0.5, 0.5, 0.5 + 60 / 1000, 0.5)
ok(r == false and handle.a.type == nil, "flick right (Undead, unlearned): nothing")

-- Key, size, messages.
Nock.db.profile.trackingWheelKey = "SHIFT-T"
W:OnConfig()
ok(binds.key == "SHIFT-T" and binds.name == "NockTrackingWheelButton", "key bound to the wheel button")
Nock.db.profile.trackingWheelKey = nil
Nock.db.profile.trackingWheelScale = 1.5
W:OnConfig()
ok(b.attrs.dead == 21 and b.attrs.scale == 1.5, "size: the snippet's cancel radius and scale follow")
Nock.db.profile.trackingWheelScale = nil
W:OnConfig()
ok(W.msgs.NOCK_TRACKING_WHEEL_CONFIG == "OnConfig" and W.msgs.NOCK_TRACKING_WHEEL_CLOSE == "Close" and W.msgs.NOCK_VISUALS_CHANGED == "OnConfig", "its own messages")
-- Hover while open, in combat too.
combat = true
b.scripts.PreClick(b, "LeftButton", true)
cursorX, cursorY = 550, 450
W:Refresh(Nock.state)
ok(st.open and st.hover == 2, "open in combat: hover follows the cursor (up-right = Humanoids)")
cursorX, cursorY = 560, 400
W:Refresh(Nock.state)
ok(st.hover == nil, "an unlearned slot (Undead) is no slot")
b.scripts.PreClick(b, "LeftButton", false)
ok(st.open == false, "up closes")
combat = false
ok(Nock.state.aspectRing.open == false, "the aspect ring's state untouched")

dofile("Core/Bindings.lua")
ok(_G["BINDING_NAME_CLICK NockTrackingWheelButton:LeftButton"] == "Tracking wheel (hold)", "binding label (Forever)")
Nock.Flavor.forever = false
dofile("Core/Bindings.lua")
ok(_G["BINDING_NAME_CLICK NockTrackingWheelButton:LeftButton"] == "Tracking wheel (WoW Forever)", "binding label on TBC says Forever only")
Nock.Flavor.forever = true

print(("forever_tracking_wheel: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
