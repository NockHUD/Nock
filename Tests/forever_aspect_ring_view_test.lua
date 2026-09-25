-- Tests/forever_aspect_ring_view_test.lua
-- UI/Frame_AspectRing.lua: the ring layer and its six secure slot buttons.
-- Run from the repo root: luajit Tests/forever_aspect_ring_view_test.lua
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
    self.textures = self.textures or {}
    self.textures[#self.textures + 1] = t
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
local module
function Nock:NewModule(name) module = { name = name, events = {}, sent = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function module:SendMessage(m) self.sent[#self.sent + 1] = m end
  function module:RegisterMessage(m, h) self.msgs = self.msgs or {}; self.msgs[m] = h end
  return module end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/Spells.lua")
dofile("Forever/AspectRing.lua")   -- the pure helpers (its module is replaced by the view below)
module = nil
dofile("UI/Frame_AspectRing.lua")
local V = module
ok(V and V.name == "AspectRingView", "module AspectRingView")
-- /reload inside combat: the view initializes under the lockdown; the mock
-- errors on any secure call, so nothing protected may be touched here.
combat = true
local okInit, errInit = pcall(V.OnInitialize, V)
ok(okInit, "initialize under the lockdown touches no protected frame: " .. tostring(errInit))
combat = false
local layer = frames.NockAspectRingLayer
ok(layer and layer.shown == false and layer.strata == "DIALOG", "layer: hidden, high strata")
local s1, s4 = frames.NockAspectRingSlot1, frames.NockAspectRingSlot4
ok(s1 and s4 and s1.template == "SecureActionButtonTemplate" and s1.clicks == nil, "six secure slots, set up later (out of combat)")
-- Style B: the disc (with its centre cap, radius 17 > the cancel radius 14,
-- so everything that looks like cancel is cancel), the pointer wedge, the name.
ok(V.disc and V.disc.path == "Interface\\AddOns\\Nock\\Media\\AspectRingDisc.tga" and V.disc.w == 150 and V.disc.layer == "BACKGROUND", "disc: 150, behind everything")
ok(V.wedge and V.wedge.path == "Interface\\AddOns\\Nock\\Media\\AspectRingWedge.tga" and V.wedge.w == 150 and V.wedge.shown == false, "wedge: hidden until a pick")
ok(V.name and V.name.reactLook and V.name.point[1] == "TOP" and V.name.point[5] == -80, "name under the ring in the React text look")
V.name.reactLook = nil
V.msgs.NOCK_VISUALS_CHANGED()
ok(V.name.reactLook == true, "a React font change re-applies the name's look")
-- The tile hangs off one point so the hover scale grows it.
ok(s1.tile.allPoints ~= true and s1.tile.point and s1.tile.point[1] == "CENTER", "tile anchored at its centre, not all points")

local st = Nock.state.aspectRing
st.known[1], st.known[4] = "Aspect of the Hawk", "Aspect of the Cheetah"
st.short = { "Hawk", "Monkey", "Wild", "Cheetah", "Pack", "Beast" }
st.order = Nock.AspectRingOrder(nil)   -- the module publishes the layout before any open
st.knownRev = 1
Nock.state.player.aspect = { spellId = 13165 }
-- Open.
st.open, st.cx, st.cy = true, 500, 400
V:Refresh(Nock.state)
ok(layer.shown and layer.point[4] == 500 and layer.point[5] == 400, "open: layer shown at the ring centre")
ok(layer.scale == 1, "open: 100% by default")
ok(s1.clicks and s1.clicks[1] == "AnyUp" and s1.attrs.useOnKeyDown == false, "first open sets the slots up: mouse-up clicks")
ok(s1.point[4] == 0 and s1.point[5] == 45 and s4.point[5] == -45, "slot 1 up, slot 4 down at radius 45")
ok(s1.attrs.type == "macro" and s1.attrs.macrotext == "/cast !Aspect of the Hawk" and s1.mouse == true, "learned slot: casts its aspect on click")
ok(frames.NockAspectRingSlot2.attrs.type == nil and frames.NockAspectRingSlot2.mouse == false, "unlearned slot: no cast, no mouse")
ok(painted[s1.tile].icon == 1000 + 13165 and painted[s1.tile].desat == false, "learned: full-colour icon")
ok(painted[frames.NockAspectRingSlot2.tile].icon == nil, "unlearned: empty socket")
ok(s1.tile.inset ~= nil and s4.tile.inset == nil, "the active aspect (Hawk) carries the inset glow")
-- Hover.
st.hover = 4
V:Refresh(Nock.state)
ok(s4.tile.scale and math.abs(s4.tile.scale - 1.12) < 1e-9 and s4.tile.border[1] == 1, "hovered slot: scaled 1.12, lit border")
ok((s1.tile.scale or 1) == 1, "others: normal size")
ok(V.wedge.shown and math.abs(V.wedge.rot - (-math.pi)) < 1e-9, "wedge points at slot 4 (straight down): rotated -180 deg")
ok(V.wedge.vc and V.wedge.vc[1] == 1 and math.abs(V.wedge.vc[4] - 0.22) < 1e-9, "wedge tinted with the active colour at 22%")
ok(V.name.text == "Cheetah", "name of the pick under the ring")
st.hover = 2
V:Refresh(Nock.state)
ok(math.abs(V.wedge.rot - (-math.pi / 3)) < 1e-9 and V.name.text == "Monkey", "pick moves: wedge turns clockwise, name follows")
st.hover = nil
V:Refresh(Nock.state)
ok(V.wedge.shown == false and V.name.text == "", "no pick (centre): no wedge, no name")
st.hover = 4
V:Refresh(Nock.state)
-- Slot click closes the ring by message.
s4.scripts.PostClick(s4, "LeftButton", false)
ok(V.sent[#V.sent] == "NOCK_ASPECT_RING_CLOSE", "slot click asks the module to close")
-- Close.
st.open, st.hover = false, nil
V:Refresh(Nock.state)
-- Ring size: the layer scales and still centres on the cursor.
Nock.db.profile.aspectRingScale = 1.5
st.open = true
V:Refresh(Nock.state)
ok(layer.scale == 1.5 and math.abs(layer.point[4] - 500 / 1.5) < 1e-9 and math.abs(layer.point[5] - 400 / 1.5) < 1e-9,
   "150%: layer scaled, anchor divided so the centre stays on the cursor")
Nock.db.profile.aspectRingScale = nil
st.open, st.hover = false, nil
V:Refresh(Nock.state)
ok(layer.shown == false, "closed: layer hidden")
-- Spellbook change while closed: attributes re-applied on the next open.
st.known[3] = "Aspect of the Wild"; st.knownRev = 2
st.open = true
V:Refresh(Nock.state)
ok(frames.NockAspectRingSlot3.attrs.macrotext == "/cast !Aspect of the Wild", "newly learned aspect casts from its slot")
-- A rearranged dial: slot 1 paints the aspect the layout puts there.
st.order = { "cheetah", "monkey", "wild", "hawk", "pack", "beast" }
st.known[1], st.known[4] = "Aspect of the Cheetah", "Aspect of the Hawk"; st.knownRev = 5
V:Refresh(Nock.state)
ok(painted[s1.tile].icon == 1000 + 5118 and s1.attrs.macrotext == "/cast !Aspect of the Cheetah", "slot 1 shows and casts Cheetah")
ok(s4.tile.inset ~= nil and s1.tile.inset == nil, "the active glow follows Hawk to its new slot")

-- Combat starts with the ring open: hidden before the lockdown, never touched after.
V:PLAYER_REGEN_DISABLED()
ok(layer.shown == false, "combat start hides the ring")
combat = true
st.known[5] = "Aspect of the Pack"; st.knownRev = 3
V:Refresh(Nock.state)   -- the mock errors on any secure call in combat
ok(frames.NockAspectRingSlot5.attrs.type == nil, "in combat: no attribute touched")
print(("forever_aspect_ring_view: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
