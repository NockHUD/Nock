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

-- prefer: ordered "use this first" lists for Click2Apply. Every entry must be
-- an item the category already scans for, and the list must not repeat itself.
local WITH_PREFER = { "food", "flask", "battleElixir", "guardianElixir",
                      "scrollAgility", "scrollStrength", "kibler", "demonslayer",
                      "sharpeningStone", "consecratedStone" }
for _, k in ipairs(WITH_PREFER) do
  local cat = CD[k]
  ok(type(cat.prefer) == "table" and #cat.prefer >= 1, k .. ".prefer is a non-empty array")
  local seen = {}
  for i, id in ipairs(cat.prefer or {}) do
    ok(cat.items[id] == true, k .. ".prefer[" .. i .. "]=" .. tostring(id) .. " is in items")
    ok(not seen[id], k .. ".prefer has no duplicate " .. tostring(id))
    seen[id] = true
  end
end
ok(CD.scrollAgility.prefer[1] == 27498, "scrollAgility prefers rank V")
ok(CD.scrollStrength.prefer[1] == 27503, "scrollStrength prefers rank V")
ok(CD.food.prefer[1] == 27655, "food prefers Ravager Dog")

-- kind: every stone is tagged sharp or blunt, and only stones carry a kind.
for _, k in ipairs({ "sharpeningStone", "consecratedStone" }) do
  local cat = CD[k]
  ok(type(cat.kind) == "table", k .. ".kind is a table")
  for id in pairs(cat.items) do
    ok(cat.kind[id] == "sharp" or cat.kind[id] == "blunt", k .. ".kind[" .. id .. "] tagged")
  end
  for id in pairs(cat.kind or {}) do
    ok(cat.items[id] == true, k .. ".kind[" .. id .. "] is an item of the category")
  end
end
ok(CD.sharpeningStone.kind[28421] == "blunt", "Adamantite Weightstone is blunt")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
