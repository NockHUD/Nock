-- Tests/buff_row_classic_test.lua
-- Standalone LuaJIT tests for the proc row's two hosts (UI/Frame_ReactBuffs.lua):
-- ONE module whose frame is the cluster's welded row in React and the HUD
-- frame's welded row in Classic (above the classic cast bar, behind
-- showBuffRow, under buffRowScale) — floating and freely movable in both.
-- Checks the mode gate, the host swap (parent, scale, weld vs free position),
-- the per-mode position stores for drag and the nudge pad, the lock rule, and
-- that the same scan paints in both modes.
-- Run from the repo root: luajit Tests/buff_row_classic_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.UIParent = Stub.CreateFrame("Frame")
_G.GetTime = function() return 1000 end
_G.unpack = unpack or table.unpack

local playerBuffs = {}
_G.UnitExists = function() return false end
_G.UnitBuff = function(unit, i)
  local b = (unit == "player" and playerBuffs or {})[i]
  if not b then return nil end
  return b.name, b.icon or ("icon-" .. b.name), 1, "Magic", 10, 1010, "player", false, false, b.id
end
_G.GetSpellInfo = function(id) return "Spell " .. id, nil, "icon-" .. id end
_G.GetNumRaidMembers = function() return 0 end
_G.GetNumPartyMembers = function() return 0 end

local Nock = { Constants = {}, state = {}, modules = {} }
function Nock:NewModule(name)
  local m = { name = name }
  function m:RegisterMessage() end
  function m:RegisterEvent() end
  function m:SendMessage() end
  Nock.modules[name] = m
  return m
end
function Nock:GetModule(name) return Nock.modules[name] end
local locked = true
function Nock.IsLocked() return locked end
_G.LibStub = setmetatable({}, { __call = function(_, lib, silent)
  if lib == "AceAddon-3.0" then return { GetAddon = function() return Nock end } end
  if silent then return nil end
  return {}
end })

dofile("Core/Constants.lua")
dofile("Config/Defaults.lua")
dofile("Core/State.lua")
local C = Nock.Constants
Nock.db = { profile = {} }
for k, v in pairs(Nock.Defaults.profile) do Nock.db.profile[k] = v end
local p = Nock.db.profile
p.reactBuffDisabled = {}

local painted = {}
local nudgeSpec
Nock.UI = {
  CreateReactSlot = function(parent, name) return Stub.CreateFrame("Frame", name, parent) end,
  PaintReactSlot  = function(slot, item) painted[#painted + 1] = item.icon end,
  ApplyBackdrop   = function() end,
  RegisterNudgeable = function(frame, spec) nudgeSpec = spec end,
  SetReactSlotSize = function() end,
}
-- The HUD frame (Classic host) and the cluster (React host).
local hudFrame = Stub.CreateFrame("Frame", "NockHUD", UIParent)
hudFrame:SetWidth(280)
Nock.parentFrame = hudFrame
local cluster = Nock:NewModule("ReactCluster")
cluster.frame = Stub.CreateFrame("Frame", "NockReactCluster", hudFrame)
cluster.frame:SetWidth(240)

-- The aura store (Core/AuraCache.lua) is what the modules read; headlessly
-- no UNIT_AURA fires, so every read invalidates first -- the mocks are the
-- truth on every call, as UnitBuff/UnitDebuff were before the store.
dofile("Core/AuraCache.lua")
do
  local AC = Nock.AuraCache
  local inv = AC.Invalidate
  for _, k in ipairs({ "Rev", "ForEach", "BySpell", "ByName", "Count" }) do
    local f = AC[k]
    AC[k] = function(...) inv(); return f(...) end
  end
end

dofile("UI/Frame_ReactBuffs.lua")
local RB = Nock.modules.ReactBuffs
local panel

-- The stub keeps only the LAST SetPoint; record every call instead.
local points = {}
local function trackPoints(f)
  f.SetPoint = function(self, pt, rel, rp, x, y)
    points[#points + 1] = { pt = pt, rel = rel, rp = rp, x = x, y = y }
    return self
  end
  f.ClearAllPoints = function(self) points = {}; return self end
  f.SetScale = function(self, s) self._scale = s; return self end
  f.GetScale = function(self) return self._scale or 1 end
end

local function refresh()
  for i = #painted, 1, -1 do painted[i] = nil end
  RB:Refresh(Nock.state)
  return painted
end

--------------------------------------------------------------------------------
-- 1. Defaults and the mode gate.
--------------------------------------------------------------------------------
ok(Nock.Defaults.profile.showBuffRow == true, "showBuffRow ships ON")
ok(Nock.Defaults.profile.buffRowScale == 1.0, "buffRowScale ships at 1.0")
ok(Nock.Defaults.profile.classicBuffRowPos == false, "classicBuffRowPos ships welded (false)")
p.hudMode = "react"
RB:OnInitialize()
RB:OnEnable()
panel = RB.frame
trackPoints(panel)
ok(RB:IsClassicHost() == false, "react mode -> not the classic host")
ok(RB:IsEnabled() == true, "react: enabled by reactBuffRows")
p.reactBuffRows = false
ok(RB:IsEnabled() == false, "react: reactBuffRows=false disables")
ok(p.showBuffRow == true, "... without touching showBuffRow")
p.reactBuffRows = true
p.hudMode = "classic"
ok(RB:IsClassicHost() == true, "classic mode -> the classic host")
ok(RB:IsEnabled() == true, "classic: enabled by showBuffRow")
p.showBuffRow = false
ok(RB:IsEnabled() == false, "classic: showBuffRow=false disables")
p.showBuffRow = true
ok(RB:PosKey() == "classicBuffRowPos", "classic position key")
p.hudMode = "react"
ok(RB:PosKey() == "reactBuffRowPos", "react position key")

--------------------------------------------------------------------------------
-- 2. Host swap: parent, scale, the weld above each mode's cast bar.
--------------------------------------------------------------------------------
p.hudMode = "react"
RB:ApplyLayout()
ok(panel:GetParent() == cluster.frame, "react: the row is the cluster's child")
ok(#points == 2 and points[1].rel == cluster.frame and points[1].rp == "TOPLEFT" and points[2].rp == "TOPRIGHT",
   "react: welded across the cluster's top edge")
ok(points[1].y == math.max(20, (p.reactCastH or 16) + 4), "react: lifted clear of the React cast bar")
ok(panel:GetScale() == 1, "react: scale 1 (the React scale is the cluster's)")

p.hudMode = "classic"
p.castBarHeight, p.castBarPadding = 22, 4
RB:ApplyLayout()
ok(panel:GetParent() == hudFrame, "classic: the row is the HUD frame's child (outside the box, above it)")
ok(#points == 2 and points[1].rel == hudFrame and points[1].rp == "TOPLEFT" and points[2].rp == "TOPRIGHT",
   "classic: welded across the HUD's top edge")
ok(points[1].y == (22 + 2 * 4) - 1 + 4, "classic: lifted clear of the classic cast bar (+4 px)")
ok(RB:ClassicLift() == 33, "ClassicLift = castBarHeight + 2*padding - 1 + 4")
p.castBarHeight = 30
RB:ApplyLayout()
ok(points[1].y == (30 + 8) - 1 + 4, "a taller cast bar lifts the row further")
p.castBarHeight = 22

-- Scale: the weld's offsets are read in the child's space (/ s).
p.buffRowScale = 2
RB:ApplyLayout()
ok(panel:GetScale() == 2, "classic: buffRowScale applied to the row")
ok(points[1].y == 33 / 2, "classic: weld lift divided by the scale")
p.buffRowScale = 1

-- A saved classic position: one point against the HUD, the HUD's width.
p.classicBuffRowPos = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 10, y = -40 }
RB:ApplyLayout()
ok(#points == 1 and points[1].rel == hudFrame and points[1].x == 10 and points[1].y == -40,
   "classic: a saved position anchors one point to the HUD")
ok(panel:GetWidth() == 280, "classic: free position takes the HUD's width")
p.classicBuffRowPos = false

-- Back to React: re-parented, and the React store is untouched.
p.hudMode = "react"
RB:ApplyLayout()
ok(panel:GetParent() == cluster.frame, "back to react: re-parented to the cluster")
ok(p.reactBuffRowPos == false, "react store untouched by the classic round trip")
ok(panel:GetScale() == 1, "back to react: scale reset to 1")

--------------------------------------------------------------------------------
-- 3. The same scan paints in Classic.
--------------------------------------------------------------------------------
p.hudMode = "classic"
RB:ApplyLayout()
playerBuffs = { { name = "Proc2825", id = 2825, icon = "proc-2825" } }
refresh()
ok(#painted == 1 and painted[1] == "proc-2825", "classic: a proc paints (" .. #painted .. ")")
ok(panel:IsShown(), "classic: the frame is shown while enabled")
p.showBuffRow = false
refresh()
ok(#painted == 0 and not panel:IsShown(), "classic: showBuffRow=false hides and paints nothing")
p.showBuffRow = true
playerBuffs = {}

--------------------------------------------------------------------------------
-- 4. Drag and nudge stores per mode; the lock rule.
--------------------------------------------------------------------------------
local dragStop = panel:GetScript("OnDragStop")
ok(type(dragStop) == "function", "the row wires its own drag stop")
panel.GetLeft = function() return 100 end
panel.GetBottom = function() return 200 end
hudFrame.GetLeft = function() return 40 end
hudFrame.GetBottom = function() return 150 end
cluster.frame.GetLeft = function() return 60 end
cluster.frame.GetBottom = function() return 170 end

p.hudMode = "classic"
dragStop(panel)
ok(type(p.classicBuffRowPos) == "table" and p.classicBuffRowPos.x == 60 and p.classicBuffRowPos.y == 50,
   "classic drag writes the HUD-relative classicBuffRowPos")
ok(p.reactBuffRowPos == false, "... and not reactBuffRowPos")

p.hudMode = "react"
dragStop(panel)
ok(type(p.reactBuffRowPos) == "table" and p.reactBuffRowPos.x == 40 and p.reactBuffRowPos.y == 30,
   "react drag writes the cluster-relative reactBuffRowPos")
ok(p.classicBuffRowPos.x == 60, "... and leaves the classic store alone")

-- With a scaled classic row the host edge is brought into the row's space.
p.hudMode = "classic"
p.buffRowScale = 2
panel.GetEffectiveScale = function() return 2 end
hudFrame.GetEffectiveScale = function() return 1 end
dragStop(panel)
ok(p.classicBuffRowPos.x == 100 - 40 * 0.5 and p.classicBuffRowPos.y == 200 - 150 * 0.5,
   "classic drag under scale 2 converts the host edge into the row's space")
p.buffRowScale = 1
panel.GetEffectiveScale = nil
hudFrame.GetEffectiveScale = nil

-- Nudge pad: one spec, the key follows the host.
ok(nudgeSpec ~= nil, "one nudge spec registered")
p.hudMode = "classic"
ok(nudgeSpec.get() == p.classicBuffRowPos, "classic pad reads classicBuffRowPos")
ok(nudgeSpec.active() == true, "classic pad active while the row is on")
p.showBuffRow = false
ok(nudgeSpec.active() == false, "classic pad inactive while the row is off")
p.showBuffRow = true
nudgeSpec.set({ point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 5, y = 6 })
ok(p.classicBuffRowPos.x == 5 and #points == 1 and points[1].x == 5, "classic pad set writes the store and re-anchors")
ok(nudgeSpec.default() == false, "classic pad reset re-welds (false)")
p.hudMode = "react"
ok(nudgeSpec.get() == p.reactBuffRowPos, "react pad reads reactBuffRowPos")
ok(nudgeSpec.default() == false, "react pad reset re-welds (false)")

-- Lock: grabbable when unlocked in either mode (a floating row, like React's).
panel.EnableMouse = function(self, on) self._mouse = on and true or false end
locked = false
p.hudMode = "react"
RB:ApplyLock()
ok(panel._mouse == true, "react unlocked -> grabbable")
p.hudMode = "classic"
RB:ApplyLock()
ok(panel._mouse == true, "classic unlocked -> grabbable")
locked = true
RB:ApplyLock()
ok(panel._mouse == false, "locked -> never")

print(("buff_row_classic_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
