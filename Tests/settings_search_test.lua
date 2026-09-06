-- Tests/settings_search_test.lua
-- W.Index / W.Search (Core/OptionsWalk.lua): every control row of every page is findable by name, one-liner, card, tab or page, in any mode.
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local catalogs = dofile("Tests/lib/catalog_scan.lua")
local Nock, W, root = dofile("Tests/lib/options_harness.lua")({ catalogs = catalogs })
local nav = W.Nav(root, "Nock")

W.SetMode("simple")
local index = W.Index(nav, "Nock")
ok(#index > 500, "index covers the tree: " .. #index)
ok(W.Simple(), "indexing leaves the mode as it found it")
local adv = 0
for _, e in ipairs(index) do if e.row.advanced then adv = adv + 1 end end
ok(adv > 50, "advanced rows are indexed even in Simple mode: " .. adv)
for _, e in ipairs(index) do
  if e.row.type == "description" or e.row.type == "header" then ok(false, "descriptions/headers are not indexed: " .. tostring(e.row.key)) break end
end

local res = W.Search(index, "clip")
ok(res.total >= 10, "clip finds the clip rows: " .. res.total)
ok((res.counts.classic or 0) >= 3, "per-page match counts: classic " .. tostring(res.counts.classic))
ok(res.hits[1].crumb:find("Classic HUD", 1, true) ~= nil, "results start on the first page in nav order; crumb carries page › tab: " .. tostring(res.hits[1].crumb))
ok(res.hits[1].pageKey and res.hits[1].tabKey and res.hits[1].cardKey, "a hit names its page, tab and card")

local none = W.Search(index, "zzqx")
ok(none.total == 0 and next(none.counts) == nil, "no match -> empty")
ok(W.Search(index, "c").total == 0, "one character does not search")
ok(W.Search(index, "  CLIP ").total == res.total, "case-insensitive, trimmed")

-- a table cell (claimed by a layout) is still findable
local cell = W.Search(index, "track background")
ok(cell.total >= 4, "rows claimed by a table layout are indexed: " .. cell.total)
-- a warning's master switch is findable by the warning's name
local dz = W.Search(index, "dazed")
ok(dz.total >= 1, "a warning is found by its title: " .. dz.total)

print(("settings_search_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
