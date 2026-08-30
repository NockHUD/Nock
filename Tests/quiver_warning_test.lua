-- Tests/quiver_warning_test.lua
-- Standalone LuaJIT tests for the "quiver almost empty" warning in
-- Modules/Warnings.lua: reads state.ammo.quiver (the arrows physically in the
-- quiver/pouch, published by UI/Frame_InfoRow.lua), never state.ammo.total.
-- Run from the repo root: luajit Tests/quiver_warning_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

--------------------------------------------------------------------------------
-- Minimal WoW surface. Every check in Warnings.lua guards its globals with
-- `if X then`, so only what the quiver check touches is stubbed.
--------------------------------------------------------------------------------
local now = 1000
_G.GetTime = function() return now end
_G.UnitExists = function() return false end
_G.UnitBuff = function() return nil end
_G.UnitDebuff = function() return nil end
_G.GetInventoryItemTexture = function(unit, slot)
  if unit == "player" and slot == 0 then return "tex-arrows" end
  return nil
end

local addon = { Constants = {}, state = {} }
function addon.IsInRaidInstance() return false end
local module
function addon:NewModule(name, ...)
  module = { name = name }
  function module:RegisterEvent() end
  function module:UnregisterEvent() end
  function module:RegisterMessage() end
  function module:SendMessage() end
  function module:ScheduleTimer() end
  return module
end
_G.LibStub = function(name, silent)
  if name == "AceAddon-3.0" then return { GetAddon = function() return addon end } end
  if silent then return nil end
  return {}
end

dofile("Core/Constants.lua")
dofile("Config/Defaults.lua")
addon.db = { profile = {} }
-- Seed the profile from the shipped defaults so isEnabled/threshold read the
-- real ship values.
for k, v in pairs(addon.Defaults.profile) do addon.db.profile[k] = v end

dofile("Modules/Warnings.lua")
local Warnings = module
ok(type(Warnings.Refresh) == "function", "Warnings module loaded")

local function newState()
  return {
    warnings = {},
    noRelease = {},
    player = { healthPct = 100, inCombat = false },
    target = {},
    ammo = { total = 0, quiver = 0, hasQuiver = false },
    demo = {},
  }
end

local function find(list, id)
  for _, w in ipairs(list) do if w.id == id then return w end end
  return nil
end

--------------------------------------------------------------------------------
-- 1. Ship defaults: enabled, threshold 400.
--------------------------------------------------------------------------------
ok(addon.Defaults.profile.warnQuiverEnabled == true, "warnQuiverEnabled ships ON")
ok(addon.Defaults.profile.quiverArrowThreshold == 400, "quiverArrowThreshold ships at 400")

--------------------------------------------------------------------------------
-- 2. Fires RED below the threshold, quiver-only, with the count as text.
--------------------------------------------------------------------------------
local s = newState()
s.ammo.hasQuiver, s.ammo.quiver, s.ammo.total = true, 399, 5000
Warnings:Refresh(s)
local w = find(s.warnings, "quiver")
ok(w ~= nil, "399 in the quiver warns (total 5000 is irrelevant)")
ok(w and w.severity == "red", "quiver warning is red")
ok(w and w.text == "399", "text is the quiver count")
ok(w and w.icon == "tex-arrows", "icon is the equipped ammo's texture")

--------------------------------------------------------------------------------
-- 3. Silent at and above the threshold.
--------------------------------------------------------------------------------
s = newState()
s.ammo.hasQuiver, s.ammo.quiver = true, 400
Warnings:Refresh(s)
ok(find(s.warnings, "quiver") == nil, "exactly 400 does not warn")

--------------------------------------------------------------------------------
-- 4. No quiver equipped: nothing, however few arrows are in the bags.
--------------------------------------------------------------------------------
s = newState()
s.ammo.hasQuiver, s.ammo.quiver, s.ammo.total = false, 0, 12
Warnings:Refresh(s)
ok(find(s.warnings, "quiver") == nil, "no quiver -> no warning")

--------------------------------------------------------------------------------
-- 5. The toggle and the threshold slider are honoured.
--------------------------------------------------------------------------------
s = newState()
s.ammo.hasQuiver, s.ammo.quiver = true, 10
addon.db.profile.warnQuiverEnabled = false
Warnings:Refresh(s)
ok(find(s.warnings, "quiver") == nil, "disabled -> no warning")
addon.db.profile.warnQuiverEnabled = true

addon.db.profile.quiverArrowThreshold = 1000
s = newState()
s.ammo.hasQuiver, s.ammo.quiver = true, 800
Warnings:Refresh(s)
ok(find(s.warnings, "quiver") ~= nil, "raised threshold: 800 warns")
addon.db.profile.quiverArrowThreshold = 400

--------------------------------------------------------------------------------
-- 6. state.ammo absent (Frame_InfoRow not loaded yet): no error, no warning.
--------------------------------------------------------------------------------
s = newState()
s.ammo = nil
local okCall = pcall(Warnings.Refresh, Warnings, s)
ok(okCall, "missing state.ammo does not throw")
ok(find(s.warnings, "quiver") == nil, "missing state.ammo -> no warning")

--------------------------------------------------------------------------------
-- 7. Icon fallback when the ammo slot has no texture; catalog entry exists.
--------------------------------------------------------------------------------
_G.GetInventoryItemTexture = function() return nil end
s = newState()
s.ammo.hasQuiver, s.ammo.quiver = true, 1
Warnings:Refresh(s)
w = find(s.warnings, "quiver")
ok(w and w.icon ~= nil, "icon never nil (fallback quiver icon)")

local cat
for _, c in ipairs(Warnings.Catalog) do if c.key == "quiver" then cat = c end end
ok(cat ~= nil, "catalog has a quiver entry")
ok(cat and cat.category == "gear", "quiver entry files under gear")
ok(cat and cat.enabledKey == "warnQuiverEnabled", "catalog enabledKey matches the profile flag")
ok(cat and cat.thresholds and cat.thresholds[1] and cat.thresholds[1].key == "quiverArrowThreshold",
   "catalog exposes the threshold slider")
ok(cat and cat.iconFn and cat.iconFn() ~= nil, "catalog iconFn never nil")

--------------------------------------------------------------------------------
-- 8. Warnings.GateDirs: the shirt-gate direction parser, pure (cached by the
--    module; it used to concat + lower + gsub both macro bodies per refresh).
--------------------------------------------------------------------------------
local G = Warnings.GateDirs
local sd, td = G("/use [noequipped:Shirt] Snowball\n/startattack", "/startattack [equipped:Shirt]")
ok(sd == "off" and td == nil, "GateDirs: [noequipped:Shirt] -> shirt off, no tabard")
sd, td = G("/use [equipped:Tabard] Snowball", "")
ok(sd == nil and td == "on", "GateDirs: [equipped:Tabard] -> tabard on")
sd, td = G("/use [noequipped: tabard] Snowball", "/cast [equipped:shirt] Raptor Strike")
ok(sd == "on" and td == "off", "GateDirs: mixed garments, case and spacing tolerant")
sd, td = G(nil, nil)
ok(sd == nil and td == nil, "GateDirs: no bodies -> no gate")

print(("quiver_warning_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
