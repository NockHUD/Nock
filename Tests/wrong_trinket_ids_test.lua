-- Tests/wrong_trinket_ids_test.lua
-- Data guard for the built-in PvP-trinket family (C.WRONG_TRINKET_IDS): the
-- wrong-trinket warning unions this set with the user's CSV, so a typo here
-- silently un-fixes the "PvP trinket never warns" bug. IDs were probed off
-- Wowhead TBC's XML endpoint on 2026-08-18 — this test pins that snapshot.
-- Run from the repo root: luajit Tests/wrong_trinket_ids_test.lua

-- Minimal stubs so Core/Constants.lua loads standalone (same trick as
-- options_tree_test.lua): LibStub -> addon table it can hang Constants on.
local addon = {}
_G.LibStub = function() return { GetAddon = function() return addon end } end

dofile("Core/Constants.lua")
local C = addon.Constants

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local T = C.WRONG_TRINKET_IDS
ok(type(T) == "table", "C.WRONG_TRINKET_IDS exists")

-- Every entry is a numeric item ID mapping to true (parseIdSet-compatible).
local n = 0
for id, v in pairs(T or {}) do
  ok(type(id) == "number" and v == true, "entry is [number]=true: " .. tostring(id))
  n = n + 1
end

-- Wowhead-verified family, 2026-08-18.
local insigniaHorde    = { 18834, 18845, 18846, 18849, 18850, 18851, 18852, 18853 }
local insigniaAlliance = { 18854, 18856, 18857, 18858, 18859, 18862, 18863, 18864 }
local medallionAlly    = { 28234, 28235, 28236, 28237, 28238, 37864 }
local medallionHorde   = { 28239, 28240, 28241, 28242, 28243, 37865 }

local function allIn(list, label)
  for i = 1, #list do
    ok(T[list[i]] == true, label .. " " .. list[i] .. " is in the set")
  end
end
allIn(insigniaHorde,    "Insignia of the Horde")
allIn(insigniaAlliance, "Insignia of the Alliance")
allIn(medallionAlly,    "Medallion of the Alliance")
allIn(medallionHorde,   "Medallion of the Horde")

ok(n == 28, "the set is exactly the 28-item family (got " .. n .. ")")

-- IDs that LOOK like family members but are other items entirely — the probe
-- turned these up interleaved in the same ranges. They must never sneak in.
-- 18847/18855/18860 are Grand Marshal's/High Warlord's weapons; 18861 is
-- Flamewaker Legplates; 25653/11122 (Riding Crop, Carrot) and 19992
-- (Devilsaur Tooth) stay in the user CSV default, not the built-in family —
-- a tooth-weaving hunter must be able to delist it from the Options box.
for _, id in ipairs({ 18847, 18855, 18860, 18861, 25653, 11122, 19992 }) do
  ok(T[id] == nil, "non-family id " .. id .. " is NOT in the set")
end

-- The user-editable CSV seed (Config/Defaults.lua). The tooth is a leveling
-- trinket: pop it pre-pull for the pet crit, then swap a real trinket in —
-- still wearing it on a boss is the same class of mistake as the Riding Crop.
dofile("Config/Defaults.lua")
local csv = addon.Defaults and addon.Defaults.profile
            and addon.Defaults.profile.warnWrongTrinketIds or ""
for _, id in ipairs({ "25653", "11122", "19992" }) do
  ok(csv:match("%f[%d]" .. id .. "%f[%D]") ~= nil, "CSV default lists " .. id)
end

print(string.format("wrong_trinket_ids: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
