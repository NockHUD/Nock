-- Tests/edit_tags_test.lua
-- Standalone LuaJIT tests for the edit-mode NAME TAGS (UI/EditMode.lua):
-- while unlocked every registered nudgeable frame wears a tag with its
-- spec.label, parented to the frame (follows drags / show-hide for free),
-- at spec.tagPoint (default TOPLEFT); locked hides them all.
-- Run from the repo root: luajit Tests/edit_tags_test.lua

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
local EditMode
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
local locked = true
function Nock.IsLocked() return locked end
Nock.db = { profile = {} }
_G.LibStub = function(name)
  return { GetAddon = function() return Nock end }
end
dofile("Core/Constants.lua")
Nock.UI = {
  ApplyBackdrop = function() end,
  GetFont = function() return "font" end,
}
dofile("UI/EditMode.lua")
EditMode = Nock.modules.EditMode

-- Two frames with specs; one carries a tagPoint.
local a = Stub.CreateFrame("Frame", "A", UIParent)
local b = Stub.CreateFrame("Frame", "B", UIParent)
Nock.UI.RegisterNudgeable(a, { label = "Cast Bar", get = function() end, set = function() end })
Nock.UI.RegisterNudgeable(b, { label = "HUD box", tagPoint = "TOPRIGHT", get = function() end, set = function() end })

local reg = Nock.UI.GetNudgeables()
ok(#reg == 2, "two entries registered")

-- Locked: no tags built, nothing shown.
EditMode:RefreshPads()
ok(reg[1].tag == nil and reg[2].tag == nil, "locked: no tag is even built")
ok(Nock.UI.TagVisible(true) == false and Nock.UI.TagVisible(false) == true, "TagVisible is 'not locked'")

-- Unlock: a tag per frame, child of the frame, right text, right corner.
locked = false
EditMode:RefreshPads()
local ta, tb = reg[1].tag, reg[2].tag
ok(ta and tb, "unlocked: both tags built")
ok(ta and ta:GetParent() == a and tb:GetParent() == b, "tags are children of their frames")
ok(ta and ta:IsShown() and tb:IsShown(), "tags shown")
ok(ta and ta.text:GetText() == "Cast Bar", "tag text = spec.label")
ok(tb and tb.text:GetText() == "HUD box", "second tag text")
local pt = ta and select(1, ta:GetPoint())
ok(pt == "TOPLEFT", "default corner TOPLEFT (" .. tostring(pt) .. ")")
local ptb, relb, rpb, xb = tb:GetPoint()
ok(ptb == "TOPRIGHT" and relb == b and rpb == "TOPRIGHT" and xb == -1, "spec.tagPoint honoured, inset inward")
ok(ta:GetWidth() > 0 and ta:GetHeight() > 0, "tag sized to its text")

-- A label change re-texts; a second refresh does not re-anchor needlessly.
reg[1].spec.label = "Buff Row"
local before = Stub.counters.SetPoint
EditMode:RefreshPads()
ok(ta.text:GetText() == "Buff Row", "label change reaches the tag")
ok(Stub.counters.SetPoint == before, "unchanged corner -> no re-anchor")

-- Lock again: hidden, not destroyed (reused next time).
locked = true
EditMode:RefreshPads()
ok(not ta:IsShown() and not tb:IsShown(), "locked: tags hidden")
ok(reg[1].tag == ta, "tag kept for reuse")
locked = false
EditMode:RefreshPads()
ok(ta:IsShown() and reg[1].tag == ta, "unlocked again: the same tag shows")

-- A frame registered while unlocked gets its tag on the next refresh.
local c = Stub.CreateFrame("Frame", "C", UIParent)
Nock.UI.RegisterNudgeable(c, { label = "Late", get = function() end, set = function() end })
EditMode:RefreshPads()
ok(reg[3].tag and reg[3].tag:IsShown() and reg[3].tag.text:GetText() == "Late", "late registration tagged")

print(("edit_tags_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
