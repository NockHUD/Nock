-- Tests/karabor_neck_test.lua
-- Black Temple "Karabor neck still on" warning (Modules/Warnings.lua): the
-- Medallion of Karabor (32649) / Blessed Medallion of Karabor (32757)
-- teleports you TO the raid and is easy to forget around your neck once
-- inside. Warns while worn in BT — except around Mother Shahraz (NPC 22947),
-- where the neck's Shadow Resistance is exactly right: a sighting stands the
-- warning down, her death brings it back (take it off again).
-- Run from the repo root: luajit Tests/karabor_neck_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

--------------------------------------------------------------------------------
-- Minimal WoW surface (every check in Warnings.lua guards its globals).
--------------------------------------------------------------------------------
local now = 1000
_G.GetTime = function() return now end
_G.UnitBuff = function() return nil end
_G.UnitDebuff = function() return nil end

-- Instance: settable per scenario.
local instance = { name = "Black Temple", itype = "raid", mapId = 564 }
_G.GetInstanceInfo = function()
  return instance.name, instance.itype, 0, "", 25, 0, false, instance.mapId
end

-- Equipment: neck slot 2.
local neckId = nil
_G.GetInventoryItemID = function(unit, slot)
  if unit == "player" and slot == 2 then return neckId end
  return nil
end
_G.GetInventoryItemTexture = function(unit, slot)
  if unit == "player" and slot == 2 and neckId then return "tex-neck" end
  return nil
end

-- Units: token -> { guid, dead }. Mother Shahraz GUID carries NPC id 22947.
local units = {}
local MOTHER_GUID = "Creature-0-1465-564-1234-22947-000012345F"
_G.UnitExists = function(u) return units[u] ~= nil end
_G.UnitGUID = function(u) return units[u] and units[u].guid end
_G.UnitIsDead = function(u) return units[u] and units[u].dead or false end
local plates = {}
_G.C_NamePlate = { GetNamePlates = function() return plates end }

local addon = { Constants = {}, state = {} }
function addon.IsInRaidInstance() return instance.itype == "raid" end
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
for k, v in pairs(addon.Defaults.profile) do addon.db.profile[k] = v end

dofile("Modules/Warnings.lua")
local Warnings = module
local C = addon.Constants

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

-- Step the clock past every throttle (instance recheck, mother sweep).
local function step(dt) now = now + (dt or 6) end

local function refresh()
  step()
  local s = newState()
  Warnings:Refresh(s)
  return find(s.warnings, "karaborNeck")
end

--------------------------------------------------------------------------------
-- 1. Constants + ship defaults.
--------------------------------------------------------------------------------
ok(C.NpcID.MOTHER_SHAHRAZ == 22947, "Mother Shahraz NPC id in Constants")
ok(C.KARABOR_NECK_ITEMS and C.KARABOR_NECK_ITEMS[32649] and C.KARABOR_NECK_ITEMS[32757],
   "both neck item ids in Constants")
ok(C.BLACK_TEMPLE_MAP_ID == 564, "BT instance map id in Constants")
ok(addon.Defaults.profile.warnKaraborNeckEnabled == true, "warnKaraborNeckEnabled ships ON")

--------------------------------------------------------------------------------
-- 2. Fires RED in BT with either neck worn, with the worn item's texture.
--------------------------------------------------------------------------------
neckId = 32649
local w = refresh()
ok(w ~= nil, "base neck worn in BT warns")
ok(w and w.severity == "red", "warning is red")
ok(w and w.icon == "tex-neck", "icon is the worn neck's texture")

neckId = 32757
ok(refresh() ~= nil, "blessed neck worn in BT warns")

--------------------------------------------------------------------------------
-- 3. Silent outside BT, with no neck, with another neck, and when disabled.
--------------------------------------------------------------------------------
instance = { name = "Serpentshrine Cavern", itype = "raid", mapId = 548 }
ok(refresh() == nil, "another raid -> no warning")
instance = { name = "Black Temple", itype = "raid", mapId = 564 }

neckId = nil
ok(refresh() == nil, "no neck -> no warning")
neckId = 30017   -- Telonicus's Pendant
ok(refresh() == nil, "a normal neck -> no warning")
neckId = 32757

addon.db.profile.warnKaraborNeckEnabled = false
ok(refresh() == nil, "disabled -> no warning")
addon.db.profile.warnKaraborNeckEnabled = true

--------------------------------------------------------------------------------
-- 4. Mother Shahraz in view suppresses; the sighting lingers; it comes back.
--------------------------------------------------------------------------------
units.target = { guid = MOTHER_GUID }
ok(refresh() == nil, "Mother targeted -> warning stands down")

units.target = nil
ok(refresh() == nil, "sighting lingers past a blinked nameplate (within linger)")

step(60)
ok(refresh() ~= nil, "sighting expired -> warning returns")

-- A nameplate sighting counts too.
plates = { { namePlateUnitToken = "nameplate1" } }
units.nameplate1 = { guid = MOTHER_GUID }
ok(refresh() == nil, "Mother on a nameplate -> warning stands down")
plates = {}
units.nameplate1 = nil
step(60)

--------------------------------------------------------------------------------
-- 5. Mother dead: the warning is back at once (take the neck off again).
--------------------------------------------------------------------------------
units.target = { guid = MOTHER_GUID }
ok(refresh() == nil, "alive again -> down")
units.target.dead = true
ok(refresh() ~= nil, "Mother dead -> warning back immediately (no linger)")
units.target = nil
ok(refresh() ~= nil, "stays back after her corpse is gone")

--------------------------------------------------------------------------------
-- 6. The catalog advertises the warning to the settings UI.
--------------------------------------------------------------------------------
local entry
for _, e in ipairs(Warnings.Catalog) do if e.key == "karaborNeck" then entry = e end end
ok(entry ~= nil, "catalog entry exists")
ok(entry and entry.enabledKey == "warnKaraborNeckEnabled", "catalog wires the enable flag")
ok(entry and entry.category == "gear", "catalog category is gear")

print(string.format("karabor_neck_test: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
