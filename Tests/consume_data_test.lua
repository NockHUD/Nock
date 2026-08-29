-- Tests/consume_data_test.lua
-- Structural test for Core/ConsumeData.lua: every category present, sets are
-- [number]=true maps, and the in-game-confirmed scroll IDs are in place.
-- Run from the repo root: luajit Tests/consume_data_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = {}
_G.LibStub = function() return { GetAddon = function() return Nock end } end

dofile("Core/ConsumeData.lua")
local CD = Nock.ConsumeData
ok(type(CD) == "table", "ConsumeData table exists")

local WITH_BUFFS = { "flask", "battleElixir", "guardianElixir",
                     "scrollAgility", "scrollStrength", "kibler", "demonslayer" }
local ITEMS_ONLY = { "sharpeningStone", "consecratedStone" }

local function checkSet(t, label)
  ok(type(t) == "table", label .. " is a table")
  local n = 0
  for k, v in pairs(t or {}) do
    n = n + 1
    ok(type(k) == "number", label .. " key " .. tostring(k) .. " is a number")
    ok(v == true, label .. "[" .. tostring(k) .. "] == true")
  end
  return n
end

for _, key in ipairs(WITH_BUFFS) do
  local cat = CD[key]
  ok(cat ~= nil, "category " .. key)
  ok(checkSet(cat and cat.buffs, key .. ".buffs") > 0, key .. ".buffs non-empty")
  ok(checkSet(cat and cat.items, key .. ".items") > 0, key .. ".items non-empty")
end
for _, key in ipairs(ITEMS_ONLY) do
  local cat = CD[key]
  ok(cat ~= nil, "category " .. key)
  ok(cat and cat.buffs == nil, key .. " has no buffs set (temp enchant)")
  ok(checkSet(cat and cat.items, key .. ".items") > 0, key .. ".items non-empty")
end
-- food: items now, buffs filled by the Wowhead pass (Task 2 flips this assert).
ok(CD.food and checkSet(CD.food.items, "food.items") > 0, "food.items non-empty")
ok(CD.food and type(CD.food.buffs) == "table", "food.buffs table present")

-- In-game-confirmed scroll spell IDs (the bug this rework fixes: scroll auras
-- are named just "Agility"/"Strength", so name matching never hit).
for _, id in ipairs({ 8115, 8116, 8117, 12174, 33077 }) do
  ok(CD.scrollAgility.buffs[id], "scrollAgility.buffs has " .. id)
end
for _, id in ipairs({ 8118, 8119, 8120, 12179, 33082 }) do
  ok(CD.scrollStrength.buffs[id], "scrollStrength.buffs has " .. id)
end

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
