-- Tests/tracker_timer_text_test.lua
-- The buff and debuff trackers' timer digits (UI/Frame_BuffTracker.lua,
-- UI/Frame_DebuffTracker.lua) under the frame stub. Without a cooldown-text
-- addon each present, timed aura paints its own seconds in the slot's cdText;
-- with OmniCC (or tullaCC / ncCooldown) loaded the slot keeps quiet and leaves
-- the Cooldown frame to it. Regression: without OmniCC nothing wrote the text
-- at all (2026-09-07 report), and the debuff grid had no gate either way.
-- Run from the repo root: luajit Tests/tracker_timer_text_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.UIParent = Stub.CreateFrame("Frame")
_G.unpack = unpack or table.unpack
local now = 1000
_G.GetTime = function() return now end
_G.UnitExists = function(unit) return unit == "target" end   -- no pet, a target
_G.IsResting = function() return false end
_G.GetNumRaidMembers = function() return 0 end
_G.GetNumPartyMembers = function() return 0 end
local loaded = {}
_G.C_AddOns = { IsAddOnLoaded = function(name) return loaded[name] or false end }

local Nock = { Constants = {}, state = {}, modules = {} }
function Nock:NewModule(name)
  local m = { name = name }
  function m:RegisterMessage() end
  function m:RegisterEvent() end
  function m:SendMessage() end
  Nock.modules[name] = m
  return m
end
function Nock.IsLocked() return true end
function Nock:Print() end
_G.LibStub = setmetatable({}, { __call = function(_, lib, silent)
  if lib == "AceAddon-3.0" then return { GetAddon = function() return Nock end } end
  if silent then return nil end
  return {}
end })

dofile("Core/Constants.lua")
dofile("Config/Defaults.lua")
dofile("Core/State.lua")
Nock.db = { profile = {} }
for k, v in pairs(Nock.Defaults.profile) do Nock.db.profile[k] = v end
-- Both grids ship off; the test wants them drawing.
Nock.db.profile.buffTrackerEnabled    = true
Nock.db.profile.debuffTrackerEnabled  = true
Nock.db.profile.debuffTrackerRaidOnly = false

Nock.UI = {
  CreateIconSlot = function(parent, name)
    local s = Stub.CreateFrame("Button", name, parent)
    s.icon      = Stub.CreateFrame("Texture", nil, s)
    s.cooldown  = Stub.CreateFrame("Cooldown", nil, s)
    s.cdText    = Stub.CreateFrame("FontString", nil, s)
    s.countText = Stub.CreateFrame("FontString", nil, s)
    return s
  end,
  ApplyUserPanelStyle      = function() end,
  RegisterHeaderFontString = function() end,
  RegisterNudgeable        = function() end,
  SetIconNextHighlight     = function() end,
}

local state = Nock.state
state.demo = state.demo or {}

local function fresh()
  dofile("UI/Frame_BuffTracker.lua")
  dofile("UI/Frame_DebuffTracker.lua")
  local BT, DT = Nock.modules.BuffTrackerView, Nock.modules.DebuffTrackerView
  BT:OnInitialize(); DT:OnInitialize()
  BT:ApplyExternalCdAddon(); DT:ApplyExternalCdAddon()
  return BT, DT
end

local function buff(present, exp, dur)
  return { present = present, icon = "icon", label = "Aspect of the Hawk", key = "hawk",
           duration = dur or 30, expirationTime = exp or 0, count = 1, selfApplied = false }
end
local function debuff(present, exp, dur)
  return { present = present, icon = "icon", label = "Scorpid Sting", key = "scorpid",
           duration = dur or 20, expirationTime = exp or 0, count = 1 }
end

-- 1. No cooldown-text addon: the slot paints its own seconds -------------------
local BT, DT = fresh()
state.bufftracker   = { player = { buff(true, now + 25), buff(false, 0, 0) }, pet = {} }
state.debufftracker = { debuff(true, now + 12) }
BT:Refresh(state); DT:Refresh(state)
local s1, s2 = BT.playerSlots[1], BT.playerSlots[2]
ok(s1.cdText:IsShown(), "buff: cdText shown without OmniCC")
ok(s1.cdText:GetText() == "25", "buff: 25 s left reads 25 (got '" .. s1.cdText:GetText() .. "')")
ok(s1.cooldown.noCooldownCount == true, "buff: the Cooldown frame is marked ours")
ok(s2.cdText:GetText() == "", "buff: a missing buff has no digits")
local d1 = DT.slots[1]
ok(d1.cdText:IsShown(), "debuff: cdText shown without OmniCC")
ok(d1.cdText:GetText() == "12", "debuff: 12 s left reads 12 (got '" .. d1.cdText:GetText() .. "')")
ok(d1.cooldown.noCooldownCount == true, "debuff: the Cooldown frame is marked ours")

-- the digits follow the clock, tenths under ten seconds, minutes past 90 s
now = now + 20
BT:Refresh(state); DT:Refresh(state)
ok(s1.cdText:GetText() == "5.0", "buff: 5 s left reads 5.0 (got '" .. s1.cdText:GetText() .. "')")
ok(d1.cdText:GetText() == "", "debuff: expired -> no digits (got '" .. d1.cdText:GetText() .. "')")
state.bufftracker.player[1] = buff(true, now + 1800, 3600)
BT:Refresh(state)
ok(s1.cdText:GetText() == "30m", "buff: half an hour reads 30m (got '" .. s1.cdText:GetText() .. "')")
-- a permanent aura (duration 0) never shows digits
state.bufftracker.player[1] = buff(true, 0, 0)
BT:Refresh(state)
ok(s1.cdText:GetText() == "", "buff: a permanent aura has no digits")
-- the buff drops: the digits go with it
state.bufftracker.player[1] = buff(false, 0, 0)
BT:Refresh(state)
ok(s1.cdText:GetText() == "", "buff: dropped -> no digits")

-- 2. OmniCC loaded: the slot is quiet and the Cooldown frame is left to it --------
loaded.OmniCC = true
now = 1000
BT, DT = fresh()
state.bufftracker   = { player = { buff(true, now + 25) }, pet = {} }
state.debufftracker = { debuff(true, now + 12) }
BT:Refresh(state); DT:Refresh(state)
s1, d1 = BT.playerSlots[1], DT.slots[1]
ok(not s1.cdText:IsShown(), "buff: cdText hidden with OmniCC")
ok(s1.cdText:GetText() == "", "buff: no digits of ours with OmniCC (got '" .. s1.cdText:GetText() .. "')")
ok(s1.cooldown.noCooldownCount == nil, "buff: OmniCC may paint the Cooldown frame")
ok(not d1.cdText:IsShown(), "debuff: cdText hidden with OmniCC")
ok(d1.cdText:GetText() == "", "debuff: no digits of ours with OmniCC (got '" .. d1.cdText:GetText() .. "')")
ok(d1.cooldown.noCooldownCount == nil, "debuff: OmniCC may paint the Cooldown frame")

-- 3. The other two known cooldown-text addons gate the same way ------------------
loaded.OmniCC = nil
for _, name in ipairs({ "tullaCC", "ncCooldown" }) do
  loaded[name] = true
  BT, DT = fresh()
  BT:Refresh(state); DT:Refresh(state)
  ok(not BT.playerSlots[1].cdText:IsShown() and not DT.slots[1].cdText:IsShown(), name .. " gates both grids")
  loaded[name] = nil
end

print(("tracker_timer_text_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
