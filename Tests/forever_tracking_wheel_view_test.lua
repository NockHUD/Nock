-- Tests/forever_tracking_wheel_view_test.lua
-- UI/Frame_TrackingWheel.lua: the wheel layer and its eight secure slots (the
-- aspect ring view factory under the wheel's names and 45-degree wedge).
-- Run from the repo root: luajit Tests/forever_tracking_wheel_view_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
_G.GetRangedHaste = function() return 0 end
_G.GetTime = function() return 100 end
local combat = false
_G.InCombatLockdown = function() return combat end
local frames = {}
local function newFrame(kind, name, parent, template)
  local f = { attrs = {}, scripts = {}, shown = true, kind = kind, name = name, template = template, mouse = nil }
  local function guard(what) if combat and template == "SecureActionButtonTemplate" then error("ADDON_ACTION_BLOCKED " .. what) end end
  function f:SetAttribute(k, v) guard("SetAttribute"); self.attrs[k] = v end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:RegisterForClicks(...) guard("RegisterForClicks"); self.clicks = { ... } end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:IsShown() return self.shown end
  function f:EnableMouse(v) guard("EnableMouse"); self.mouse = v end
  function f:SetSize(w, h) if template == "SecureActionButtonTemplate" then guard("SetSize") end self.w, self.h = w, h end
  function f:SetFrameStrata(s) self.strata = s end
  function f:SetFrameLevel() end
  function f:ClearAllPoints() self.point = nil end
  function f:SetPoint(...) if template == "SecureActionButtonTemplate" then guard("SetPoint") end self.point = { ... } end
  function f:SetAllPoints() self.allPoints = true end
  function f:SetScale(s) self.scale = s end
  function f:SetBackdropBorderColor(r, g, b, a) self.border = { r, g, b, a } end
  function f:CreateTexture(_, layerName)
    local t = { layer = layerName, shown = true }
    function t:SetTexture(p) self.path = p end
    function t:SetSize(w, h) self.w, self.h = w, h end
    function t:SetPoint(...) self.point = { ... } end
    function t:SetAllPoints() end
    function t:SetColorTexture() end
    function t:SetRotation(r) self.rot = r end
    function t:SetVertexColor(r, g, b, a) self.vc = { r, g, b, a } end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    return t
  end
  function f:CreateFontString()
    local s = {}
    function s:SetPoint(...) self.point = { ... } end
    function s:SetText(v) self.text = v end
    function s:SetJustifyH() end
    return s
  end
  if name then frames[name] = f; _G[name] = f end
  return f
end
_G.CreateFrame = newFrame
_G.UIParent = newFrame("Frame", "UIParent")

local painted = {}
local Nock = {
  Flavor = { forever = true, Plain = function(v) return v end },
  Constants = { COLORS = { PROC_GLOW = { 1, 0.8, 0, 1 } } },
  API = { SpellIcon = function(id) return 1000 + id end, SpellName = function(id) return "n" .. id end },
  db = { profile = {} },
  UI = {
    CreateReactSlot = function(parent, name, size) local s = newFrame("Frame", name, parent); s.icon = {}; return s end,
    PaintReactSlot = function(slot, item) painted[slot] = { icon = item.icon, desat = item.desat } end,
    SetIconInsetGlow = function(slot, color) slot.inset = color end,
    ApplyReactTextLook = function(fs) fs.reactLook = true end,
  },
}
local modules = {}
function Nock:NewModule(name) local m = { name = name, events = {}, sent = {}, msgs = {} }
  function m:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function m:SendMessage(mm) self.sent[#self.sent + 1] = mm end
  function m:RegisterMessage(mm, h) self.msgs[mm] = h end
  modules[name] = m; return m end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/Spells.lua")
dofile("Forever/AspectRing.lua")
dofile("Forever/TrackingWheel.lua")
dofile("UI/Frame_AspectRing.lua")
dofile("UI/Frame_TrackingWheel.lua")
local V = modules.TrackingWheelView
ok(V and V.name == "TrackingWheelView" and modules.AspectRingView and modules.AspectRingView ~= V, "module TrackingWheelView beside the aspect view")
combat = true
local okInit, errInit = pcall(V.OnInitialize, V)
ok(okInit, "initialize under the lockdown touches no protected frame: " .. tostring(errInit))
combat = false
local layer = frames.NockTrackingWheelLayer
ok(layer and layer.shown == false and layer.strata == "DIALOG", "layer NockTrackingWheelLayer: hidden, high strata")
local s1, s5, s8 = frames.NockTrackingWheelSlot1, frames.NockTrackingWheelSlot5, frames.NockTrackingWheelSlot8
ok(s1 and s5 and s8 and frames.NockTrackingWheelSlot9 == nil and s1.template == "SecureActionButtonTemplate", "eight secure slots")
ok(V.disc.path == "Interface\\AddOns\\Nock\\Media\\AspectRingDisc.tga", "the same disc")
ok(V.wedge.path == "Interface\\AddOns\\Nock\\Media\\TrackingWheelWedge.tga" and V.wedge.shown == false, "a 45-degree wedge of its own, hidden until a pick")

local st = Nock.state.trackingWheel
st.known[1], st.known[2], st.known[5] = "Track Beasts", "Track Humanoids", "Track Dragonkin"
st.short = { "Beasts", "Humanoids", "Undead", "Demons", "Dragonkin", "Elementals", "Giants", "Hidden" }
st.order = { "beasts", "humanoids", "undead", "demons", "dragonkin", "elementals", "giants", "hidden" }
st.knownRev = 1
Nock.state.tracking.activeId = 19883
st.open, st.cx, st.cy = true, 500, 400
V:Refresh(Nock.state)
ok(s1.clicks and s1.clicks[1] == "AnyUp", "the first out-of-combat refresh sets the slots up")
ok(s1.point[4] == 0 and s1.point[5] == 45 and s5.point[5] == -45 and math.abs(s5.point[4]) < 1e-9, "slot 1 up, slot 5 down at radius 45")
ok(math.abs(frames.NockTrackingWheelSlot3.point[4] - 45) < 1e-9 and math.abs(frames.NockTrackingWheelSlot3.point[5]) < 1e-9, "slot 3 right")
ok(s1.attrs.macrotext == "/cast !Track Beasts" and s1.mouse == true, "learned slot casts its tracking")
ok(frames.NockTrackingWheelSlot3.attrs.type == nil and frames.NockTrackingWheelSlot3.mouse == false, "unlearned slot: no cast")
ok(painted[s1.tile].icon == 1000 + 1494 and painted[s5.tile].icon == 1000 + 19879, "slot icons: Track Beasts, Track Dragonkin")
ok(frames.NockTrackingWheelSlot2.tile.inset ~= nil and s1.tile.inset == nil, "the tracking that is on (Humanoids) carries the glow")
st.hover = 5
V:Refresh(Nock.state)
ok(V.wedge.shown and math.abs(V.wedge.rot - (-math.pi)) < 1e-9 and V.name.text == "Dragonkin", "wedge at slot 5 (down): -180 deg, name Dragonkin")
st.hover = 2
V:Refresh(Nock.state)
ok(math.abs(V.wedge.rot - (-math.pi / 4)) < 1e-9 and V.name.text == "Humanoids", "slot 2: -45 deg")
s5.scripts.PostClick(s5, "LeftButton", false)
ok(V.sent[#V.sent] == "NOCK_TRACKING_WHEEL_CLOSE", "slot click closes the wheel by its own message")
Nock.db.profile.trackingWheelScale = 1.5
V:Refresh(Nock.state)
ok(layer.scale == 1.5, "size from trackingWheelScale")
Nock.db.profile.trackingWheelScale = nil
modules.AspectRingView:OnInitialize()
ok(frames.NockAspectRingLayer and frames.NockAspectRingLayer ~= layer and frames.NockAspectRingSlot6 and frames.NockAspectRingSlot7 == nil, "the aspect ring keeps its own layer and six slots")
print(("forever_tracking_wheel_view: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
