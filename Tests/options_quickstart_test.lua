-- Tests/options_quickstart_test.lua
-- Quickstarts > Weaving on a Forever-built options tree: the page, its copied rows, the walker's quick cards and the recipes.
-- Run from the repo root: luajit Tests/options_quickstart_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local h = dofile("Tests/lib/options_harness.lua")
local Nock, W = h()
Nock.Flavor.forever = true
dofile("Config/OptionsForever.lua")
dofile("Forever/Spells.lua")
function Nock:NewModule() return { RegisterEvent = function() end, RegisterMessage = function() end } end
dofile("Forever/AspectRing.lua")
dofile("Forever/TrackingWheel.lua")
dofile("Core/WeaveMacro.lua")
dofile("Forever/WeaveKey.lua")
dofile("Forever/Quickstart.lua")
local Q = Nock.Quickstart
-- The harness builds a TBC tree; build again as Forever so the Forever-only
-- tabs (Sounds > Weaving) exist.
Nock.db.profile.hudMode = "react"
Nock:RegisterOptions()
local opts = Nock.optionsTable
local F = Nock.OptionsForever

local function nodeAt(root, path)
  local n = root
  for seg in path:gmatch("[^%.]+") do n = n.args and n.args[seg]; if type(n) ~= "table" then return nil end end
  return n
end
local function count(n) local c = 0; for _, v in pairs(n.args or {}) do if type(v) == "table" then c = c + 1 + count(v) end end; return c end

-- The family and the page.
local fam = nodeAt(opts, "quickstarts")
ok(fam and fam.type == "group" and fam.name == "Quickstarts", "quickstarts family")
ok(fam and fam.order > nodeAt(opts, "alerts").order and fam.order < nodeAt(opts, "utilities").order, "ordered between Alerts and Utilities")
local page = nodeAt(opts, "quickstarts.weaving")
ok(page and page.type == "group" and page.name == "Weaving", "weaving page")

-- One inline group per card, in order; every listed option is copied in.
for i, card in ipairs(Q.WEAVE) do
  local g = nodeAt(opts, "quickstarts.weaving.quick_" .. card.key)
  ok(g and g.type == "group" and g.inline == true and g.name == card.name and g.order == 10 * i, "card group: " .. card.key)
  ok(g and g.args.info and g.args.info.type == "description" and type(g.args.info.name) == "function", "status line on " .. card.key)
  if card.master then
    ok(nodeAt(opts, card.master) ~= nil, "master path resolves: " .. card.master)
    ok(g and g.args.enabled and g.args.enabled.type == "toggle", "master copied as `enabled` on " .. card.key)
  else
    ok(g and g.args.enabled == nil, "no master on " .. card.key)
  end
  for _, spec in ipairs(card.rows) do
    local src, leaf = nodeAt(opts, spec[1]), spec[1]:match("([^%.]+)$")
    ok(src ~= nil, "row path resolves: " .. spec[1])
    local c = g and g.args[leaf]
    ok(c ~= nil and c ~= src and c.type == (src and src.type), "row copied, not shared: " .. spec[1])
  end
end

-- One source of truth: a copy and its home row move the same profile key.
local p = Nock.db.profile
local home = nodeAt(opts, "hud.react.tabSize.reactShowWeaveStrip")
local copy = nodeAt(opts, "quickstarts.weaving.quick_hud.reactShowWeaveStrip")
copy.set(nil, false)
ok(p.reactShowWeaveStrip == false and home.get() == false, "copy writes, home reads")
home.set(nil, true)
ok(copy.get() == true, "home writes, copy reads")

-- Review focus 4: the master sits under the key `enabled`; read and written
-- through the walker (which passes info), it must still move the home key.
do
  local row = W.RowAt(opts, "quickstarts.weaving.quick_hud.enabled", "Nock")
  ok(row ~= nil, "master row resolves through the walker")
  W.Set(row, false)
  ok(p.weaveHelperEnabled == false and p.enabled == nil, "master writes weaveHelperEnabled, not a key called enabled")
  local okv, v = W.Get(row)
  ok(okv and v == false, "master reads it back")
  W.Set(row, true)
  ok(p.weaveHelperEnabled == true, "and on again")
  local krow = W.RowAt(opts, "quickstarts.weaving.quick_key.enabled", "Nock")
  W.Set(krow, true)
  ok(p.weaveKeyEnabled == true and p.enabled == nil, "weave key master writes weaveKeyEnabled")
  W.Set(krow, false)
end

-- Walker tags travel with the copy; the key bodies are Advanced here.
ok(W.IsAdvanced(nodeAt(opts, "hud.react.tabSize.weaveLegSeed")) and W.IsAdvanced(nodeAt(opts, "quickstarts.weaving.quick_hud.weaveLegSeed")), "Advanced tag copied with the row")
ok(not W.IsAdvanced(nodeAt(opts, "quickstarts.weaving.quick_hud.reactShowWeaveStrip")), "a Simple row stays Simple")
ok(W.IsAdvanced(nodeAt(opts, "quickstarts.weaving.quick_key.weaveKeyMacroUp")) and not W.IsAdvanced(nodeAt(opts, "utilities.weaveKey.weaveKeyMacroUp")), "key bodies Advanced on this page only")

-- Fix rows show only while their rule holds; the macros card hides in key mode.
local hudFix = nodeAt(opts, "quickstarts.weaving.quick_hud.hudEnabled")
p.hudEnabled = true
ok(hudFix.hidden() == true, "HUD switch hidden while the HUD shows")
p.hudEnabled = false
ok(hudFix.hidden() == false, "HUD switch offered while the HUD is hidden")
p.hudEnabled = nil
local cueFix = nodeAt(opts, "quickstarts.weaving.quick_sounds.soundCuesEnabled")
p.soundCuesEnabled = false
ok(cueFix.hidden() == false, "range-cue master offered while it is off")
p.soundCuesEnabled = true
ok(cueFix.hidden() == true, "and hidden while it is on")
local macros = nodeAt(opts, "quickstarts.weaving.quick_macros")
p.weaveKeyEnabled = true
ok(macros.hidden() == true, "macros card hidden in key mode")
p.weaveKeyEnabled = false
ok(macros.hidden() == false, "macros card shown in macro mode")

-- The status line is the card's live state.
p.weaveHelperEnabled = false
Q.Invalidate()
ok(nodeAt(opts, "quickstarts.weaving.quick_hud.info").name():find("helper is off"), "info line follows the status")
p.weaveHelperEnabled = true
Q.Invalidate()

-- Review focus 5: a rebuild re-applies; the tree keeps its size and the
-- fresh copies still drive the profile.
local before = count(opts)
F.Apply(opts)
ok(count(opts) == before, "second Apply keeps the tree's size")
nodeAt(opts, "quickstarts.weaving.quick_hud.reactShowWeaveStrip").set(nil, false)
ok(p.reactShowWeaveStrip == false, "copies after a rebuild still write the profile")
p.reactShowWeaveStrip = true

-- The walker: a sidebar family, and one quick card per checklist group.
do
  local nav = W.Nav(opts, "Nock")
  local heads, fam = {}, nil
  for _, g in ipairs(nav.groups) do
    heads[#heads + 1] = g.head or "-"
    if g.head == "Quickstarts" then fam = g end
  end
  ok(table.concat(heads, ",") == "-,HUD & Bars,Alerts,Quickstarts,Utilities,System", "sidebar order, got " .. table.concat(heads, ","))
  ok(fam and #fam.pages == 1 and fam.pages[1].key == "weaving" and fam.pages[1].name == "Weaving", "one page: Weaving")
  local pg = fam.pages[1]
  local function cards(mode)
    W.SetMode(mode)
    local page = W.Page(pg.node, pg.path, "Nock")
    ok(page.tabs and #page.tabs == 1 and page.tabs[1].virtual == true, mode .. ": one virtual tab")
    local cs = W.Cards(page.tabs[1], "Nock")
    W.SetMode("advanced")
    return cs
  end
  local function hasRow(card, key)
    for _, ln in ipairs(card.lines) do for _, r in ipairs(ln.rows) do if r.key == key then return true end end end
    return false
  end
  p.weaveKeyEnabled, p.hudEnabled, p.soundCuesEnabled = false, true, true
  local cs = cards("advanced")
  local ks = {}
  for i, c in ipairs(cs) do ks[i] = c.key end
  ok(table.concat(ks, ",") == "quick_hud,quick_camera,quick_key,quick_macros,quick_sounds", "five cards in order, got " .. table.concat(ks, ","))
  for _, c in ipairs(cs) do
    ok(c.catalog and c.catalog.kind == "quick" and c.catalog.info ~= nil, "quick catalog card: " .. c.key)
    ok(c.catalog and c.catalog.entry == Q.Card(c.catalog.itemKey), "entry is the engine's card: " .. c.key)
    ok(not hasRow(c, "info") and not hasRow(c, "enabled"), "info and master stay out of the body: " .. c.key)
  end
  ok(cs[1].catalog.enabled ~= nil and cs[2].catalog.enabled ~= nil and cs[3].catalog.enabled ~= nil, "hud, camera and key carry a master")
  ok(cs[4].catalog.enabled == nil and cs[5].catalog.enabled == nil, "macros and sounds do not, and are still cards")
  ok(hasRow(cs[1], "reactShowWeaveStrip") and hasRow(cs[1], "weaveLegSeed") and not hasRow(cs[1], "hudEnabled"), "hud card body: rows in, hidden fix row out")
  ok(hasRow(cs[4], "cameraFlipMacros"), "macros card carries Show macros")
  -- Simple keeps every card and drops the Advanced rows.
  local simple = cards("simple")
  ok(#simple == 5, "simple: all five cards survive")
  ok(hasRow(simple[1], "reactShowWeaveStrip") and not hasRow(simple[1], "weaveLegSeed"), "simple: Advanced rows leave the hud card")
  ok(not hasRow(simple[3], "weaveKeyMacroUp") and hasRow(simple[3], "weaveKey"), "simple: key bodies leave, the key stays")
  -- Key mode: the macros card goes.
  p.weaveKeyEnabled = true
  ok(#cards("advanced") == 4, "key mode: four cards")
  p.weaveKeyEnabled = false
  -- A hidden HUD brings its switch into the hud card.
  p.hudEnabled = false
  ok(hasRow(cards("advanced")[1], "hudEnabled"), "HUD hidden: its switch is on the card")
  p.hudEnabled = nil
  -- Search finds a copied row on both of its pages.
  local res = W.Search(W.Index(nav, "Nock"), "turn back when in range")
  ok((res.counts.weaving or 0) >= 1 and (res.counts.cameraFlip or 0) >= 1, "search hits the quickstart and the home page")
end

-- The recipes: three presets on the page's own rows.
do
  local P = Nock.Presets
  local list = P.ForPage("quickstarts.weaving")
  ok(list and #list == 3 and list[1].key == "turret" and list[2].key == "macros" and list[3].key == "key", "three recipes: turret, macros, key")
  ok(P.Label("quickstarts.weaving") == "HOW YOU WEAVE" and P.Label("alerts.warnings") == "PRESETS", "the strip's label per page")
  for _, pr in ipairs(list or {}) do ok(type(pr.icon) == "function", pr.key .. " tile wears a spell icon") end
  ok(Nock.Spells.ASPECT_CHEETAH == 5118, "One key's icon: Aspect of the Cheetah (the key runs you)")
  for _, pr in ipairs(list or {}) do
    ok(#pr.name <= 14 and #pr.summary <= 90 and #pr.set > 0, pr.key .. ": name, summary and a set")
    for _, e in ipairs(pr.set) do
      ok(e[1]:sub(1, 19) == "quickstarts.weaving", pr.key .. " stays on its page: " .. e[1])
      local row = W.RowAt(opts, e[1], "Nock")
      ok(row ~= nil and row.type == "toggle" and type(e[2]) == "boolean", pr.key .. " path is a toggle: " .. e[1])
    end
  end
  local turret, macros, key = list[1], list[2], list[3]
  p.weaveHelperEnabled, p.weaveKeyEnabled, p.cameraFlipEnabled, p.qolHideErrors = false, false, false, false
  p.reactShowMeleeBar, p.reactMeleeStageCue, p.reactShowWeaveStrip = false, false, false
  ok(P.Matches(turret, opts, "Nock") and not P.Matches(macros, opts, "Nock") and not P.Matches(key, opts, "Nock"), "all off reads as Turret")
  P.Apply(key, opts, "Nock")
  ok(p.weaveHelperEnabled == true and p.reactShowMeleeBar == true and p.reactMeleeStageCue == true and p.reactShowWeaveStrip == true, "One key: helper and its three HUD rows on")
  ok(p.weaveKeyEnabled == true and p.cameraFlipEnabled == true and p.qolHideErrors == true, "One key: key, camera flip and hidden errors on")
  ok(P.Matches(key, opts, "Nock") and not P.Matches(macros, opts, "Nock") and not P.Matches(turret, opts, "Nock"), "reads as One key only")
  P.Apply(macros, opts, "Nock")
  ok(p.weaveKeyEnabled == false and p.weaveHelperEnabled == true and p.cameraFlipEnabled == true, "Macros: key off, helper on, camera flip left alone")
  ok(P.Matches(macros, opts, "Nock") and not P.Matches(key, opts, "Nock"), "reads as Macros")
  P.Apply(turret, opts, "Nock")
  ok(p.weaveHelperEnabled == false and p.weaveKeyEnabled == false and p.cameraFlipEnabled == false, "Turret: helper, key and flip off")
  ok(p.reactShowMeleeBar == true and p.qolHideErrors == true, "Turret leaves the melee bar and error text as they were")
  -- A mixed state ticks no tile.
  p.weaveHelperEnabled, p.weaveKeyEnabled, p.cameraFlipEnabled = true, true, false
  ok(not P.Matches(turret, opts, "Nock") and not P.Matches(macros, opts, "Nock") and not P.Matches(key, opts, "Nock"), "key on without the flip matches no recipe")
  -- Not offered on TBC.
  Nock.Flavor.forever = false
  ok(P.ForPage("quickstarts.weaving") == nil, "no recipes on TBC")
  Nock.Flavor.forever = true
  p.weaveHelperEnabled, p.weaveKeyEnabled, p.cameraFlipEnabled = true, false, false
end

-- Only the Forever toc loads the engine.
local function readAll(path) local f = io.open(path, "rb"); local s = f:read("*a"); f:close(); return s end
ok(readAll("Nock_Camelot.toc"):find("Forever\\Quickstart.lua", 1, true) ~= nil, "Camelot toc lists Forever\\Quickstart.lua")
ok(readAll("Nock.toc"):find("Quickstart", 1, true) == nil and readAll("Nock_TBC.toc"):find("Quickstart", 1, true) == nil, "TBC tocs do not")

print(("options_quickstart: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
