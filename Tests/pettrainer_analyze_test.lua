-- Tests/pettrainer_analyze_test.lua
-- Standalone Lua 5.1 test for PetTrainer.AnalyzeBuild / GetTodoCraftIndices.
-- Run from repo root: luajit Tests/pettrainer_analyze_test.lua

-- Minimal environment so Modules/PetTrainer.lua loads outside WoW. The file
-- only touches LibStub at load time; frames/db are created lazily later.
local module = {}
local addon = { NewModule = function() return module end }
LibStub = function() return { GetAddon = function() return addon end } end

assert(loadfile("Modules/PetTrainer.lua"))()

local function craft(name, sub, ctype, tp)
  return { name = name, sub = sub, ctype = ctype, tp = tp }
end

local crafts = {
  craft("Bite", "Rank 8", "used", 25),            -- 1
  craft("Bite", "Rank 9", "available", 29),       -- 2
  craft("Growl", "Rank 8", "used", 0),            -- 3
  craft("Great Stamina", "Rank 4", "used", 25),   -- 4
  craft("Great Stamina", "Rank 5", "available", 50), -- 5
  craft("Natural Armor", "Rank 2", "used", 5),    -- 6
  craft("Cobra Reflexes", nil, "used", 15),       -- 7
}
local build = {
  ["Bite"] = 9, ["Growl"] = 8, ["Great Stamina"] = 5,
  ["Natural Armor"] = 1, ["Cobra Reflexes"] = 1, ["Avoidance"] = 2,
}

-- AnalyzeBuild: statuses, selection targets, icon indices
local items = module.AnalyzeBuild(crafts, build)
local byName = {}
for _, it in ipairs(items) do byName[it.name] = it end

assert(byName["Bite"].status == "todo", "Bite should be todo")
assert(byName["Bite"].selIdx == 2 and byName["Bite"].selRank == 9 and byName["Bite"].selTP == 29)
assert(byName["Bite"].current == 8 and byName["Bite"].iconIdx == 1)
assert(byName["Growl"].status == "done")
assert(byName["Great Stamina"].status == "todo" and byName["Great Stamina"].selIdx == 5)
assert(byName["Natural Armor"].status == "over", "rank 2 trained, target 1")
assert(byName["Cobra Reflexes"].status == "done", "nil sub means rank 1")
assert(byName["Avoidance"].status == "missing")

-- GetTodoCraftIndices: live-API path with mocked globals + real SSC preset
GetNumCrafts = function() return #crafts end
GetCraftInfo = function(i)
  local c = crafts[i]
  return c.name, c.sub, c.ctype, nil, nil, c.tp
end
module.active = "ssc"
local todos, over = module.GetTodoCraftIndices(module)
-- SSC targets in mock list: Bite 9 -> todo idx 2, Great Stamina 5 -> todo idx 5,
-- Natural Armor target 2 == current 2 -> done, Growl/Cobra done, rest missing.
assert(#todos == 2, "expected 2 todos, got " .. #todos)
assert(todos[1].craftIndex == 2 and todos[2].craftIndex == 5, "todos sorted by craft index")
assert(over == 0)

print("OK - pettrainer_analyze_test")
