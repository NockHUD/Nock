-- Tests/shopping_list_test.lua
-- Standalone LuaJIT tests for the shopping-list ENGINE (Modules/ShoppingList.lua):
-- every catalog entry is published with a `done` flag (the view's show-stocked
-- toggle filters), nNeeded counts the short ones, and the mana-potion banner
-- sums Super Mana Potion + Injector + Fel Mana Potion.
-- Run from the repo root: luajit Tests/shopping_list_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local counts = {}
_G.C_Item = {
  GetItemCount = function(id) return counts[id] or 0 end,
  GetItemIconByID = function(id) return "icon-" .. id end,
}
_G.GetItemCount = function(id, _, charges) return counts[id] or 0 end
_G.GetItemInfo = function(id) return "Item " .. id end
_G.GetRealZoneText = function() return "Shattrath City" end

local addon = { Constants = {}, state = {} }
local module
function addon:NewModule(name, ...)
  module = { name = name }
  function module:RegisterEvent() end
  function module:RegisterMessage() end
  function module:SendMessage() end
  return module
end
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
addon.state.ammo = { total = 9000, quiver = 9000, hasQuiver = true }

dofile("Modules/ShoppingList.lua")
local SL = module
ok(type(SL.Recompute) == "function", "engine loaded")

local function byKey(key)
  local sp = addon.state.shopping
  for i = 1, sp.n do if sp.items[i].key == key then return sp.items[i] end end
  return nil
end

--------------------------------------------------------------------------------
-- 1. Everything is listed; stocked rows are flagged done; nNeeded counts short.
--------------------------------------------------------------------------------
SL:Recompute()
local sp = addon.state.shopping
local curated = #addon.Constants.SHOPPING_CURATED
ok(sp.n == curated, ("every curated entry is published (%d)"):format(curated))
local arrows = byKey("arrows")
ok(arrows and arrows.done == true, "arrows at 9000 of 5000 -> done")
local haste = byKey("hastepot")
ok(haste and haste.done == false, "0 haste potions -> not done")
local needed = 0
for i = 1, sp.n do if not sp.items[i].done then needed = needed + 1 end end
ok(sp.nNeeded == needed and sp.nNeeded == curated - 1, "nNeeded = all but the arrows")

--------------------------------------------------------------------------------
-- 2. The mana banner sums Super Mana Potion, the Injector and Fel Mana Potion.
--------------------------------------------------------------------------------
counts[22832] = 5     -- Super Mana Potion
counts[33093] = 5     -- Mana Potion Injector (charges)
counts[31677] = 10    -- Fel Mana Potion
SL:Recompute()
local mana = byKey("manapot")
ok(mana ~= nil, "manapot row present")
ok(mana and mana.have == 20, "have = 5 + 5 + 10 fel = 20 (got " .. tostring(mana and mana.have) .. ")")
ok(mana and mana.done == true, "20 of 20 -> done")
ok(mana and mana.label:lower():find("fel") ~= nil, "label mentions fel")

counts[31677] = 0
SL:Recompute()
mana = byKey("manapot")
ok(mana and mana.have == 10 and mana.done == false, "without fel: 10 of 20 -> not done")

--------------------------------------------------------------------------------
-- 3. Disabled entries are still dropped from the catalog (not merely done).
--------------------------------------------------------------------------------
addon.db.profile.shoppingDisabled = { hastepot = true }
SL:OnConfigChanged()
ok(byKey("hastepot") == nil, "a disabled entry is not published at all")
ok(addon.state.shopping.n == curated - 1, "n shrinks by the disabled entry")

--------------------------------------------------------------------------------
-- 4. Ship default for the view's toggle.
--------------------------------------------------------------------------------
ok(addon.Defaults.profile.shoppingShowCompleted == false, "shoppingShowCompleted ships OFF")

print(("shopping_list_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
