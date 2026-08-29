-- Tests/spec_row_known_test.lua
-- Standalone LuaJIT tests for the Spec cooldown row's known-test
-- (Modules/Cooldowns.lua): the row resolves BM/MM/SV to Bestial Wrath /
-- Silencing Shot / Readiness by the most-pointed talent tab, and is dropped
-- from the Classic grid (and reported unavailable to the React rows) when the
-- character does not actually know that spell — a BM hunter used to see a
-- Readiness square, ready, for a spell they never had.
-- Run from the repo root: luajit Tests/spec_row_known_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local tabs  = { 41, 20, 0 }        -- points per talent tab (BM / MM / SV)
local known = { [19574] = true }   -- spells the character knows
_G.GetTalentTabInfo = function(i) return "tab", nil, nil, nil, tabs[i] end
_G.IsSpellKnown = function(id) return known[id] == true end
_G.GetSpellInfo = function(id) return "Spell " .. id, nil, "icon-" .. id end
_G.GetTime = function() return 1000 end
_G.UnitExists = function() return false end
_G.GetInventoryItemTexture = function() return nil end

local addon = { Constants = {}, state = {} }
local module
local sent = {}
function addon:NewModule(name, ...)
  module = { name = name }
  function module:RegisterEvent() end
  function module:RegisterMessage() end
  function module:SendMessage(msg) sent[#sent + 1] = msg end
  function module:ScheduleRepeatingTimer() end
  return module
end
function addon:SendMessage(msg) sent[#sent + 1] = msg end
_G.LibStub = function(name, silent)
  if name == "AceAddon-3.0" then return { GetAddon = function() return addon end } end
  if silent then return nil end
  return {}
end

dofile("Core/Constants.lua")
dofile("Config/Defaults.lua")
dofile("Core/State.lua")
addon.db = { profile = {} }
for k, v in pairs(addon.Defaults.profile) do addon.db.profile[k] = v end

dofile("Modules/Cooldowns.lua")
local CD = module
local C = addon.Constants

local function gridHas(key)
  for _, e in ipairs(CD:GetGridEntries()) do if e.key == key then return true end end
  return false
end

--------------------------------------------------------------------------------
-- 1. BM with Bestial Wrath known: the Spec row is in the grid.
--------------------------------------------------------------------------------
CD:UpdateSpecKnown()
ok(CD:IsEntryAvailable("Spec") == true, "BM + BW known -> Spec available")
ok(gridHas("Spec"), "Spec row in the Classic grid")

--------------------------------------------------------------------------------
-- 2. Respec to SV without Readiness: the row leaves, and the views are told.
--------------------------------------------------------------------------------
tabs = { 0, 20, 41 }
local before = #sent
CD:UpdateSpecKnown()
ok(CD:IsEntryAvailable("Spec") == false, "SV without Readiness -> Spec unavailable")
ok(not gridHas("Spec"), "Spec row dropped from the grid")
ok(#sent > before and sent[#sent] == "NOCK_VISUALS_CHANGED", "a change sends NOCK_VISUALS_CHANGED (grid rebuild)")

-- No change -> no message (the Classic grid must not rebuild on every event).
before = #sent
CD:UpdateSpecKnown()
ok(#sent == before, "unchanged known-state sends nothing")

--------------------------------------------------------------------------------
-- 3. Learn Readiness: back in.
--------------------------------------------------------------------------------
known[23989] = true
CD:UpdateSpecKnown()
ok(CD:IsEntryAvailable("Spec") == true, "SV + Readiness known -> available again")
ok(gridHas("Spec"), "Spec row back in the grid")

--------------------------------------------------------------------------------
-- 4. Other entries are never touched; the options order list still has Spec.
--------------------------------------------------------------------------------
known[23989] = nil
CD:UpdateSpecKnown()
ok(CD:IsEntryAvailable("RapidFire") == true, "a plain spell entry is always available")
ok(CD:IsEntryAvailable("nonsense") == true, "an unknown key is not vetoed")
local listed = false
for _, k in ipairs(CD:GetOrderedGridKeys()) do if k == "Spec" then listed = true end end
ok(listed, "the Options order list keeps the Spec row even while unavailable")

--------------------------------------------------------------------------------
-- 5. Client without a known-API: never hide (can't tell).
--------------------------------------------------------------------------------
_G.IsSpellKnown = nil
_G.IsPlayerSpell = nil
CD:UpdateSpecKnown()
ok(CD:IsEntryAvailable("Spec") == true, "no IsSpellKnown/IsPlayerSpell -> shown")

-- IsPlayerSpell alone is honoured.
_G.IsPlayerSpell = function(id) return id == 23989 end
CD:UpdateSpecKnown()
ok(CD:IsEntryAvailable("Spec") == true, "IsPlayerSpell fallback works")
_G.IsPlayerSpell = function() return false end
CD:UpdateSpecKnown()
ok(CD:IsEntryAvailable("Spec") == false, "IsPlayerSpell false -> hidden")

print(("spec_row_known_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
