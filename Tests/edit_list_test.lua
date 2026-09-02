-- Tests/edit_list_test.lua
-- Standalone LuaJIT tests for the edit-mode element list (UI/EditMode.lua,
-- pure parts): which registered frames get a row, their order, the selected
-- flag, and that the chrome (bar, list) never lists itself. Run from the repo
-- root: luajit Tests/edit_list_test.lua

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

local Nock = { Constants = {}, modules = {} }
function Nock:NewModule(name)
  local m = { name = name }
  function m:RegisterMessage() end
  function m:RegisterEvent() end
  function m:ScheduleRepeatingTimer() end
  function m:CancelTimer() end
  Nock.modules[name] = m
  return m
end
function Nock:GetModule(name) return Nock.modules[name] end
local locked = false
function Nock.IsLocked() return locked end
Nock.db = { profile = {} }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/Constants.lua")
Nock.UI = { ApplyBackdrop = function() end, GetFont = function() return "font" end }
dofile("UI/EditMode.lua")

local function frame(shown)
  local f = Stub.CreateFrame("Frame")
  if shown then f:Show() else f:Hide() end
  return f
end

local shownA, shownB, hidden, gated, chrome = frame(true), frame(true), frame(false), frame(true), frame(true)
local entries = {
  { frame = shownB, spec = { label = "Medallion" } },
  { frame = hidden, spec = { label = "Cast Bar" } },
  { frame = shownA, spec = { label = "buff row" } },
  { frame = gated,  spec = { label = "Steady row", active = function() return false end } },
  { frame = chrome, spec = { label = "Edit panel", chrome = true } },
  { frame = frame(true), spec = { label = "HUD box", active = function() return true end } },
}

--------------------------------------------------------------------------------
-- 1. Only shown, gate-passing, non-chrome entries; sorted by label, case-blind
--------------------------------------------------------------------------------
local rows = Nock.UI.EditListRows(entries, nil)
ok(#rows == 3, "three rows listed")
ok(rows[1].label == "buff row" and rows[2].label == "HUD box" and rows[3].label == "Medallion", "sorted by label, case-insensitive")
for i = 1, #rows do ok(rows[i].selected == false, "nothing selected -> row " .. i .. " unselected") end

--------------------------------------------------------------------------------
-- 2. The selected frame's row is flagged, no other
--------------------------------------------------------------------------------
rows = Nock.UI.EditListRows(entries, shownB)
local nSel = 0
for i = 1, #rows do if rows[i].selected then nSel = nSel + 1; ok(rows[i].frame == shownB, "selected row is the selected frame") end end
ok(nSel == 1, "exactly one selected row")

--------------------------------------------------------------------------------
-- 3. A selection that is hidden or chrome yields no selected row
--------------------------------------------------------------------------------
rows = Nock.UI.EditListRows(entries, hidden)
nSel = 0
for i = 1, #rows do if rows[i].selected then nSel = nSel + 1 end end
ok(nSel == 0, "hidden selection is not a row")

--------------------------------------------------------------------------------
-- 4. A fresh table every call (callers may keep the previous one)
--------------------------------------------------------------------------------
local a = Nock.UI.EditListRows(entries, nil)
local b = Nock.UI.EditListRows(entries, nil)
ok(a ~= b, "fresh table per call")

--------------------------------------------------------------------------------
-- 5. Empty registry -> empty list
--------------------------------------------------------------------------------
ok(#Nock.UI.EditListRows({}, nil) == 0, "empty registry lists nothing")

print(("edit_list_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
