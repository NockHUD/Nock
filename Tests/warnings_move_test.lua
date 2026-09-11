-- Tests/warnings_move_test.lua
-- The warning row is a nudgeable, draggable panel like the boss banner:
-- registered with edit mode under "Warnings", movable, its position saved in
-- warningsPosition (false = the stock 25%-down-from-top spot), and held
-- visible by an edit overlay while unlocked so an empty row can be found and
-- dragged. Report (2026-09-10): /nock unlock did nothing for the warnings.
-- Run from the repo root: luajit Tests/warnings_move_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.UIParent = Stub.CreateFrame("Frame")
_G.InCombatLockdown = function() return false end
_G.unpack = unpack or table.unpack

local Nock = { Constants = {}, modules = {}, isHunter = true }
function Nock:NewModule(name)
  local m = { name = name, _msgs = {} }
  function m:RegisterMessage(msg, handler) self._msgs[msg] = handler end
  function m:RegisterEvent() end
  function m:SendMessage() end
  Nock.modules[name] = m
  return m
end
function Nock:GetModule(name) return Nock.modules[name] end
function Nock:SendMessage() end
local locked = true
function Nock.IsLocked() return locked end
-- The guided-wizard readings fall back to the plain lock here (Core/State.lua is not loaded).
function Nock.IsLockedFor() return Nock.IsLocked() end
function Nock.EditPreview() return not Nock.IsLocked() end
function Nock.WizardHides() return false end
Nock.db = { profile = { warningsPosition = false } }
_G.LibStub = setmetatable({}, { __call = function(_, lib, silent)
  if lib == "AceAddon-3.0" then return { GetAddon = function() return Nock end } end
  if silent then return nil end
  return {}
end })
dofile("Core/Constants.lua")
Nock.UI = {
  ApplyBackdrop = function() end,
  GetFont = function() return "font" end,
  CreateIconSlot = function(parent, name, size)
    local sq = Stub.CreateFrame("Frame", name, parent)
    sq.icon = sq:CreateTexture()
    sq.cdText = sq:CreateFontString()
    return sq
  end,
  SetGlowBorderSize = function() end,
  SetIconHighlight = function() end,
  SetIconAlertGlow = function() end,
}
dofile("UI/EditMode.lua")
dofile("UI/Frame_Warnings.lua")
local View = Nock.modules.WarningsView
View:OnInitialize()
local f = View.frame

-- §1 Registered with edit mode.
local reg = Nock.UI.GetNudgeables()
local entry
for i = 1, #reg do if reg[i].frame == f then entry = reg[i] end end
ok(entry ~= nil, "warnings frame registered as a nudgeable")
ok(entry and entry.spec.label == "Warnings", "nudgeable label is Warnings")
ok(entry and entry.spec.get() == false, "spec.get reads warningsPosition")
ok(entry and entry.spec.default() == false, "spec.default is the stock spot (false)")
ok(View._msgs["NOCK_LOCK_CHANGED"] ~= nil, "listens for lock changes")

-- §2 Stock position: centred on the top edge, WARN_TOP_FRACTION down.
local pt, rel, rp, x, y = f:GetPoint()
ok(pt == "CENTER" and rel == UIParent and rp == "TOP" and x == 0 and y < 0,
   ("stock anchor CENTER->TOP (%s %s %s)"):format(tostring(pt), tostring(rp), tostring(y)))

-- §3 A saved position is applied through spec.set and re-read by ApplyPosition.
if entry then
  entry.spec.set({ point = "TOPLEFT", relPoint = "TOPLEFT", x = 40, y = -60 })
end
pt, rel, rp, x, y = f:GetPoint()
ok(pt == "TOPLEFT" and rp == "TOPLEFT" and x == 40 and y == -60, "spec.set moves the frame")
ok(type(Nock.db.profile.warningsPosition) == "table"
   and Nock.db.profile.warningsPosition.x == 40, "spec.set saves warningsPosition")
Nock.db.profile.warningsPosition = false
if View.ApplyPosition then View:ApplyPosition() end
pt = f:GetPoint()
ok(pt == "CENTER", "false -> back to the stock spot")

-- §4 Unlocked: the edit overlay shows (so an empty row is visible and
-- grabbable); locked hides it again.
ok(f._editBG ~= nil, "edit overlay exists")
ok(f._editBG and not f._editBG:IsShown(), "locked: overlay hidden")
locked = false
if View.ApplyLock then View:ApplyLock() end
ok(f._editBG and f._editBG:IsShown(), "unlocked: overlay shown")
locked = true
if View.ApplyLock then View:ApplyLock() end
ok(f._editBG and not f._editBG:IsShown(), "relocked: overlay hidden")

-- §5 The overlay's drag stop writes the live point into the profile.
local stop = f._editBG and f._editBG:GetScript("OnDragStop")
ok(type(stop) == "function", "overlay owns the drag stop")
f:SetPoint("BOTTOM", UIParent, "BOTTOM", 5, 300)
if stop then stop(f._editBG) end
local wp = Nock.db.profile.warningsPosition
ok(type(wp) == "table" and wp.point == "BOTTOM" and wp.x == 5 and wp.y == 300,
   "drag stop saves the new position")

print(("warnings_move_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
