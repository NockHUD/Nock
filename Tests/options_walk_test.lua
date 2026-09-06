-- Tests/options_walk_test.lua
-- The walker over the real options table: nav, pages, tabs, cards, rows, info tables, ordering, width flow.
local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock, W, registered = dofile("Tests/lib/options_harness.lua")()
ok(W ~= nil, "Nock.OptionsWalk exists")

-- 1. The table through the registry, exactly the call the window makes.
local root = W.Root("Nock")
ok(root == registered, "Root() returns the registered table via GetOptionsTable('Nock','dialog','NockSettings-1.0')")

-- 2. Nav: general first, four families, then System with experimental + profiles.
local nav = W.Nav(root, "Nock")
ok(#nav.groups == 6, "nav has 6 groups (general, 4 families, system)")
ok(nav.groups[1].head == nil and nav.groups[1].pages[1].key == "general", "general is the headless first row")
ok(nav.groups[2].head == "HUD & Bars" and #nav.groups[2].pages == 3 and nav.groups[2].pages[1].key == "classic", "hud family lists classic/react/fluffy")
ok(nav.groups[6].head == "System" and nav.groups[6].pages[1].key == "experimental" and nav.groups[6].pages[2].key == "profiles", "system holds experimental + profiles")
ok(nav.groups[2].pages[1].name == "Classic HUD", "page name strips the (active) badge and colour codes")
ok(nav.groups[2].pages[1].count > 100, "page count = leaf controls under the page")
ok(nav.groups[2].pages[1].path[1] == "hud" and nav.groups[2].pages[1].path[2] == "classic", "page path is the args chain")

-- 3. Page → tabs (depth 3 = non-inline groups; Overview holds loose leaves).
local classic = nav.groups[2].pages[1]
local page = W.Page(classic.node, classic.path, "Nock")
local names = {}
for i, t in ipairs(page.tabs) do names[i] = t.name end
ok(page.tabs[1].name == "Overview" and page.tabs[1].virtual == false, "classic landing (intro + HUD look) is the Overview tab")
ok(table.concat(names, "|"):find("Layout|Shot Bars|Swing Bars", 1, true) ~= nil, "classic tabs follow order: Layout, Shot Bars, Swing Bars, ...")
local general = W.Page(nav.groups[1].pages[1].node, nav.groups[1].pages[1].path, "Nock")
ok(general.tabs[1].name == "Overview" and #general.tabs >= 5, "general: Overview + HUD look/Visibility/Cast bar/Media/Setup Check")
local single = W.Page(root.args.utilities.args.mailbox, { "utilities", "mailbox" }, "Nock")
ok(#single.tabs == 1 and single.tabs[1].virtual == true and single.tabs[1].name == "Mailbox", "a page with no sub-groups has one virtual tab named after it")

-- 4. Tab → cards → lines → rows.
local shot
for _, t in ipairs(page.tabs) do if t.key == "rotation" then shot = t end end
local cards = W.Cards(shot, "Nock")
ok(#cards >= 5 and cards[1].name == "Shot Bars", "loose rows of a tab become a leading card named after the tab")
local found = false
for _, c in ipairs(cards) do if c.name == "Shot timing bars" then found = c end end
ok(found and #found.lines > 10, "inline group 'Shot timing bars' is a card with its rows")
local row = found.lines[1].rows[1]
ok(row.info[#row.info] == row.key and row.info[1] == "hud" and row.info.appName == "Nock" and row.info.options == root and row.info.type == row.type, "row.info is the AceConfig info table (path keys, appName, options, type)")
ok(row.name and row.type and row.isControl ~= nil, "row carries name/type/isControl")

-- 5. Catalog cards: Warnings › Pet › test1 (enabled + info), severity from the catalog.
local alerts = nav.groups[3]
local warnPage = W.Page(alerts.pages[1].node, alerts.pages[1].path, "Nock")
local pet
for _, t in ipairs(warnPage.tabs) do if t.key == "cat_pet" then pet = t end end
ok(pet ~= nil, "warnings has a Pet tab")
local pcards = W.Cards(pet, "Nock")
ok(#pcards == 1 and pcards[1].catalog and pcards[1].catalog.itemKey == "test1", "per-warning inline group is a catalog card keyed by the catalog key")
ok(pcards[1].catalog.severity == "red", "catalog card carries the catalog's severity")
ok(pcards[1].catalog.enabled.type == "toggle" and pcards[1].catalog.info.type == "description", "catalog card exposes the enabled toggle and info description")
local knobs = 0
for _, ln in ipairs(pcards[1].lines) do knobs = knobs + #ln.rows end
ok(knobs == 1 and pcards[1].lines[1].rows[1].type == "range", "catalog card lines hold only the knobs (threshold), not enabled/info")

-- 6. Ordering = AceConfigDialog's comparator.
local function o(order, name, key) return { order = order, name = name, key = key } end
local list = { o(nil, "b", "b"), o(-1, "neg", "neg"), o(2.5, "x", "x"), o(2.5, "a", "a"), o(1, "first", "first"), o(100, "A", "A") }
table.sort(list, W.Compare)
local ks = {}
for i, e in ipairs(list) do ks[i] = e.key end
ok(table.concat(ks, ",") == "first,a,x,A,b,neg", "order asc, default 100, tie on upper-cased name then key, negatives last: " .. table.concat(ks, ","))

-- 7. Width flow: 170 per unit, half = 85, full/nil-width description = own line.
local fx = { type = "group", name = "fx", args = {
  a = { type = "execute", name = "Up", order = 1, width = 0.4 },
  b = { type = "execute", name = "Down", order = 2, width = 0.4 },
  c = { type = "toggle", name = "T", order = 3, width = "full" },
  d = { type = "description", name = "D", order = 4 },
  e = { type = "execute", name = "Half", order = 5, width = "half" },
  f = { type = "execute", name = "One", order = 6, width = 1.2 },
} }
local fcards = W.Cards({ key = "fx", name = "fx", node = fx, path = { "fx" }, virtual = true }, "Nock")
local L = fcards[1].lines
ok(#L == 4, "flow: [Up,Down] [T] [D] [Half,One] -> 4 lines, got " .. #L)
ok(#L[1].rows == 2 and L[1].cluster == true, "0.4 + 0.4 share a clustered line")
ok(#L[2].rows == 1 and L[2].rows[1].width == "fill" and L[2].cluster == false, "'full' is its own line")
ok(L[3].rows[1].width == "fill", "a description without width fills its line")
ok(L[4].rows[1].unit == 85 and L[4].rows[2].unit == 204, "half = 85 px, 1.2 = 204 px")

-- 8. hidden / disabled: functions evaluated with info; hidden rows absent; hidden groups absent from tabs.
local calls = 0
local hx = { type = "group", name = "hx", args = {
  shown = { type = "toggle", name = "S", order = 1, get = function() return true end, set = function() end },
  gone = { type = "toggle", name = "G", order = 2, hidden = function(info) calls = calls + 1; return info[#info] == "gone" end, get = function() end, set = function() end },
  dis = { type = "toggle", name = "Dis", order = 3, disabled = function() return true end, get = function() end, set = function() end },
  hid = { type = "group", name = "HG", order = 4, hidden = true, args = { x = { type = "toggle", name = "x", order = 1 } } },
} }
local hcards = W.Cards({ key = "hx", name = "hx", node = hx, path = { "hx" }, virtual = true }, "Nock")
local hrows = {}
for _, ln in ipairs(hcards[1].lines) do for _, r in ipairs(ln.rows) do hrows[#hrows + 1] = r end end
ok(#hrows == 2 and hrows[1].key == "shown" and hrows[2].key == "dis" and hrows[2].disabled == true, "hidden row dropped, disabled evaluated, hidden group not a card")
ok(calls == 1, "hidden(info) called once per walk with the row's info")
local hpage = W.Page(hx, { "hx" }, "Nock")
ok(#hpage.tabs == 1, "hidden sub-group is not a tab")

-- 9. Errors are rows, not throws.
local ex = { type = "group", name = "ex", args = {
  boom = { type = "toggle", name = function() error("kaboom") end, order = 1, get = function() error("no") end, set = function() end },
  fine = { type = "toggle", name = "Fine", order = 2, get = function() return false end, set = function() end },
} }
local ecards = W.Cards({ key = "ex", name = "ex", node = ex, path = { "ex" }, virtual = true }, "Nock")
local erows = {}
for _, ln in ipairs(ecards[1].lines) do for _, r in ipairs(ln.rows) do erows[#erows + 1] = r end end
ok(#erows == 2 and erows[1].err ~= nil and erows[1].name:find("kaboom", 1, true) and erows[2].name == "Fine", "a throwing name() yields an error row and the sibling still renders")
local gok, gv = W.Get(erows[1])
ok(gok == false and type(gv) == "string", "Get() on a throwing getter returns false, message")

-- 10. get/set through info, colour 4-tuple, select values/sorting, sentinel, profiles handler strings.
Nock.db.profile.shotBarsLookahead = nil
local look
for _, ln in ipairs(found.lines) do for _, r in ipairs(ln.rows) do if r.type == "range" and r.name:find("Lookahead", 1, true) then look = r end end end
ok(look ~= nil, "found the Lookahead range row")
if look then
  ok(select(1, W.Set(look, 4)) == true, "Set(range) ok")
  local sok, v = W.Get(look)
  ok(sok and v == 4, "Get(range) reads back 4")
end
local colorRow
for _, ln in ipairs(found.lines) do for _, r in ipairs(ln.rows) do if r.type == "color" and not colorRow then colorRow = r end end end
if colorRow then
  W.Set(colorRow, 0.1, 0.2, 0.3, 0.4)
  local cok, r, g, b, a = W.Get(colorRow)
  ok(cok and math.abs(r - 0.1) < 1e-6 and math.abs(b - 0.3) < 1e-6 and (a == 0.4 or a == 1), "colour get returns up to 4 values")
end
local media = W.Page(nav.groups[1].pages[1].node, nav.groups[1].pages[1].path, "Nock")
local mediaTab
for _, t in ipairs(media.tabs) do if t.name == "Media" then mediaTab = t end end
local texRow
for _, c in ipairs(W.Cards(mediaTab, "Nock")) do for _, ln in ipairs(c.lines) do for _, r in ipairs(ln.rows) do if r.type == "select" and r.key == "barTexture" then texRow = r end end end end
ok(texRow ~= nil, "found the bar texture select")
if texRow then
  local keys, labels = W.Values(texRow)
  ok(#keys == #labels and #keys >= 2 and labels[1] == keys[1], "media select values: key == label, LSM names listed")
end
local castTex
for _, c in ipairs(W.Cards((function() for _, t in ipairs(page.tabs) do if t.key == "castBar" then return t end end end)(), "Nock")) do
  for _, ln in ipairs(c.lines) do for _, r in ipairs(ln.rows) do if r.type == "select" and r.key == "castBarTexture" then castTex = r end end end
end
if castTex then
  local keys = W.Values(castTex)
  ok(keys[1] == "Inherit (global)", "sentinel row is pinned first")
end
local profiles = nav.groups[6].pages[2]
local ppage = W.Page(profiles.node, profiles.path, "Nock")
local prow, crow
for _, c in ipairs(W.Cards(ppage.tabs[1], "Nock")) do for _, ln in ipairs(c.lines) do for _, r in ipairs(ln.rows) do
  if r.key == "choose" then prow = r end
  if r.key == "copyfrom" then crow = r end
end end end
ok(prow and select(2, W.Get(prow)) == "Default", "handler string get resolves handler:GetCurrentProfile()")
ok(prow and prow.info.arg == "common" and prow.info.handler ~= nil, "info.arg and info.handler are populated under a handler group")
ok(crow and crow.disabled == true, "disabled = 'HasNoProfiles' resolves through the handler")
ok(crow and crow.noGet == true, "get = false marks the row noGet")
local pk = W.Values(prow)
ok(pk[1] == "Default", "values = 'ListProfiles' resolves through the handler")

-- 11. Census: every leaf in the table is reached exactly once through Nav→Page→Cards.
local function isHidden(v) local h = v.hidden; if type(h) == "function" then local okh, r = pcall(h); return okh and r == true end; return h == true end
-- headers are card boundaries in the walker (no row), so neither side counts them
local function census(node) local n = 0 for _, v in pairs(node.args or {}) do if type(v) == "table" and v.type and not isHidden(v) then if v.type == "group" then n = n + census(v) elseif v.type ~= "header" then n = n + 1 end end end return n end
local total = 0
for _, g in ipairs(nav.groups) do for _, p in ipairs(g.pages) do
  local pg = W.Page(p.node, p.path, "Nock")
  for _, t in ipairs(pg.tabs) do for _, c in ipairs(W.Cards(t, "Nock")) do
    if c.catalog then total = total + 2 end
    for _, ln in ipairs(c.lines) do for _, r in ipairs(ln.rows) do if r.key ~= "__desc" and r.type ~= "header" then total = total + 1 end end end
    for _, r in ipairs(c.claimed or {}) do if r.key ~= "__desc" and r.type ~= "header" then total = total + 1 end end
  end end
end end
local expect = census(root) - census(root.args.hud) + census(root.args.hud.args.classic) + census(root.args.hud.args.react) + census(root.args.hud.args.fluffy)
-- family-level leaves are not pages: hud's intro + hudMode already left with census(hud);
-- the alerts/trackers/utilities intros still need subtracting.
expect = expect - 3
ok(total == expect, ("census: walker reached %d rows, table holds %d"):format(total, expect))

-- 12. Simple / Advanced: advanced rows, headers and groups fold away in Simple; RowAt resolves a path.
local ax = { type = "group", name = "ax", args = {
  intro = { type = "description", name = "intro", order = 1 },
  a = { type = "toggle", name = "a", order = 2, get = function() return true end, set = function() end },
  b = { type = "range", name = "b", order = 3, min = 0, max = 1, advanced = true, get = function() return 0 end, set = function() end },
  h = { type = "header", name = "Colours", order = 4, advanced = true },
  c = { type = "color", name = "c", order = 5, get = function() return 1, 1, 1 end, set = function() end },
  g = { type = "group", name = "g", inline = true, order = 6, advanced = true, args = {
    d = { type = "toggle", name = "d", order = 1, get = function() return true end, set = function() end } } },
} }
local axTab = { key = "ax", name = "ax", node = ax, path = { "ax" }, virtual = true }
W.SetMode("advanced")
local acards, adrop = W.Cards(axTab, "Nock")
local function controls(cards) local n = 0 for _, c in ipairs(cards) do for _, ln in ipairs(c.lines) do for _, r in ipairs(ln.rows) do if r.isControl then n = n + 1 end end end end return n end
ok(controls(acards) == 4 and adrop == 0, "advanced mode keeps every control")
local rowB, rowC
for _, c in ipairs(acards) do for _, ln in ipairs(c.lines) do for _, r in ipairs(ln.rows) do if r.key == "b" then rowB = r end if r.key == "c" then rowC = r end end end end
ok(rowB and rowB.advanced == true, "row.advanced from the node")
ok(rowC and rowC.advanced == true, "row.advanced from the preceding advanced header")
W.SetMode("simple")
local scards, sdrop = W.Cards(axTab, "Nock")
ok(controls(scards) == 1 and sdrop == 3, ("simple mode keeps a only (%d kept, %d dropped)"):format(controls(scards), sdrop))
ok(W.Count(ax) == 1, "Count honours the mode")
W.SetMode("advanced")
ok(W.Count(ax) == 4, "Count back to 4 in advanced")
-- a page whose only tab is all-advanced
local allAdv = { type = "group", name = "p", args = { t = { type = "group", name = "t", advanced = true, args = {
  x = { type = "toggle", name = "x", get = function() return true end, set = function() end } } } } }
W.SetMode("simple")
local ap = W.Page(allAdv, { "p" }, "Nock")
ok(#ap.tabs == 0 and ap.allAdvanced == true and ap.dropped == 1, "all-advanced page reports allAdvanced + dropped")
W.SetMode("advanced")
ok(#W.Page(allAdv, { "p" }, "Nock").tabs == 1, "the same page has its tab back in advanced")
-- RowAt
local rr = W.RowAt(root, "hud.classic.swingBars.showAutoShotBar", "Nock")
ok(rr and rr.key == "showAutoShotBar" and rr.type == "toggle", "RowAt resolves a dotted path to a row")
local okg, gv = W.Get(rr)
ok(okg and gv == true, "RowAt row reads through get")
ok(W.RowAt(root, "hud.classic.nope", "Nock") == nil, "RowAt returns nil for a missing path")

-- 13. Header-driven cards: a flat tab splits at its headers; the intro leads the first card; icon/desc ride along.
local hx2 = { type = "group", name = "Swing", args = {
  intro = { type = "description", name = "intro text", order = 1 },
  h1 = { type = "header", name = "Auto Shot bar", order = 2, icon = { spell = 75 }, desc = "The tall ranged bar." },
  a = { type = "toggle", name = "a", order = 3, get = function() return true end, set = function() end },
  h2 = { type = "header", name = "Track", order = 4, advanced = true },
  b = { type = "color", name = "b", order = 5, get = function() return 1, 1, 1 end, set = function() end },
} }
W.SetMode("advanced")
local hcards2 = W.Cards({ key = "hx2", name = "Swing", node = hx2, path = { "hx2" }, virtual = true }, "Nock")
ok(#hcards2 == 2 and hcards2[1].name == "Auto Shot bar" and hcards2[2].name == "Track", "flat tab splits into one card per header")
ok(hcards2[1].icon and hcards2[1].icon.spell == 75 and hcards2[1].desc == "The tall ranged bar.", "header icon + desc ride on the card")
ok(hcards2[1].lines[1].rows[1].key == "__desc" and hcards2[1].lines[2].rows[1].key == "intro", "the card's one-liner leads, then the intro")
W.SetMode("simple")
local hs = W.Cards({ key = "hx2", name = "Swing", node = hx2, path = { "hx2" }, virtual = true }, "Nock")
ok(#hs == 1 and hs[1].name == "Auto Shot bar", "an advanced header's card folds away in Simple")
W.SetMode("advanced")

-- 14. Card layouts: actions, table, background block, entries (sections + bar order), items merge, chips.
do
  local function tg(n) return { type = "toggle", name = n, width = 1.4, get = function() return true end, set = function() end } end
  local function ex(n, w) return { type = "execute", name = n, width = w or 0.4, func = function() end } end
  local function rg(n) return { type = "range", name = n, min = 0, max = 10, get = function() return 1 end, set = function() end } end
  local function co(n) return { type = "color", name = n, get = function() return 1, 1, 1 end, set = function() end } end
  local gx = { type = "group", name = "Grid", args = {
    hdr = { type = "header", name = "Entries", order = 1 },
    reset = ex("Reset order", 0.6), row1 = { type = "description", name = "Row 1 — Rotation", order = 3 },
    en1 = tg("KC"), up1 = ex("Up"), dn1 = ex("Down"), rm1 = ex("X"),
    en2 = tg("MS"), up2 = ex("Up"), dn2 = ex("Down"), rm2 = ex("X"),
    add1 = { type = "select", name = "Add to this row", values = { a = "a" }, get = function() end, set = function() end },
    row2 = { type = "description", name = "Row 2 — Utility", order = 20 },
    en3 = tg("FD"), up3 = ex("Up"), dn3 = ex("Down"), rm3 = ex("X"),
  } }
  local o = 2
  for _, k in ipairs({ "reset", "row1", "en1", "up1", "dn1", "rm1", "en2", "up2", "dn2", "rm2", "add1", "row2", "en3", "up3", "dn3", "rm3" }) do gx.args[k].order = o; o = o + 1 end
  W.SetMeta(gx.args.hdr, "actions", { "reset" })
  local cards = W.Cards({ key = "gx", name = "Grid", node = gx, path = { "gx" }, virtual = true }, "Nock")
  local c = cards[1]
  ok(c and c.actionRows and c.actionRows[1].key == "reset", "header action row claimed from the flow")
  ok(c.entries and #c.entries == 2 and c.entries[1].sub == "Row 1" and c.entries[1].name == "Rotation", "entries split at Row N descriptions")
  ok(#c.entries[1].entries == 2 and #c.entries[1].entries[1].buttons == 3 and c.entries[1].add and c.entries[1].add.key == "add1", "section holds its entries, buttons and Add select")
  local flowN = 0
  for _, ln in ipairs(c.lines) do flowN = flowN + #ln.rows end
  ok(flowN == 0, ("no claimed row leaks into the flow (%d)"):format(flowN))
  -- bar order + table + background block
  local bx = { type = "group", name = "Bars", args = {
    h = { type = "header", name = "Track", order = 1 },
    aBgColor = co("Background color"), aBgOpacity = rg("Background opacity"), aBorder = { type = "select", name = "Border style", values = { x = "x" }, get = function() end, set = function() end }, aBorderSize = rg("Border thickness"), aBorderColor = co("Border color"), aBorderOpacity = rg("Border opacity"),
    l1 = { type = "description", name = "1. Auto Shot bar", width = 1.4 }, u1 = ex("Up"), d1 = ex("Down"),
    l2 = { type = "description", name = "2. Melee bar", width = 1.4 }, u2 = ex("Up"), d2 = ex("Down"),
    sColor = co("Steady tick"), sWidth = rg("Steady tick width"),
  } }
  o = 2
  for _, k in ipairs({ "aBgColor", "aBgOpacity", "aBorder", "aBorderSize", "aBorderColor", "aBorderOpacity", "l1", "u1", "d1", "l2", "u2", "d2", "sColor", "sWidth" }) do bx.args[k].order = o; o = o + 1 end
  local bc = W.Cards({ key = "bx", name = "Bars", node = bx, path = { "bx" }, virtual = true }, "Nock")[1]
  ok(bc.bgBlock and #bc.bgBlock.bg == 2 and #bc.bgBlock.border == 4, "background block recognised (2 + 4 rows)")
  ok(bc.entries and #bc.entries == 1 and bc.entries[1].implicit and #bc.entries[1].entries == 2 and #bc.entries[1].entries[1].buttons == 2, "bar order = implicit section of numbered entries")
  W.SetMeta(bx.args.h, "table", { cols = { { "Colour" }, { "Width" } }, rows = { { "Steady tick", { Colour = "sColor", Width = "sWidth" } } } })
  bc = W.Cards({ key = "bx", name = "Bars", node = bx, path = { "bx" }, virtual = true }, "Nock")[1]
  ok(bc.tableRows and bc.tableRows.one and bc.tableRows.rows[1].cells[1][1].key == "sColor" and bc.tableRows.rows[1].cells[2][1].key == "sWidth", "table cells resolve explicit keys")
  -- wildcard table lines: the PvP page's incoming-CC spell table, one line per
  -- pvpCcItem_<id>_lbl node in builder order (built-ins first, then your own)
  do
    Nock.db.profile.pvpCcCustom = { { spell = "Hex", sound = "Horn", enabled = true } }
    if Nock.RebuildOptionsArgs then Nock:RebuildOptionsArgs() end
    local pvpPage = W.Page(root.args.pvp.args.pvpMode, { "pvp", "pvpMode" }, "Nock")
    local ccCard
    for _, tab in ipairs(pvpPage.tabs or { pvpPage }) do
      for _, c in ipairs(W.Cards(tab, "Nock")) do if c.name == "Incoming CC" then ccCard = c end end
    end
    local t = ccCard and ccCard.tableRows
    ok(t and #t.rows == #Nock.Constants.PVP_CC_CASTS + 1, "wildcard table: one line per built-in CC spell plus the custom one")
    ok(t and t.rows[1].label == "Fear" and t.rows[#t.rows].label == "Hex", "wildcard table: builder order, custom last")
    ok(t and t.rows[1].icon ~= nil and t.rows[1].cells[1][1].key == "pvpCcItem_fear_sound" and t.rows[1].cells[3][1].key == "pvpCcItem_fear_on" and #t.rows[1].cells[4] == 0, "wildcard table: icon, suffix cells, no remove on a built-in")
    ok(t and t.rows[#t.rows].cells[4][1] and t.rows[#t.rows].cells[4][1].key == "pvpCcItem_c1_rm", "wildcard table: the custom line has its remove button")
    ok(ccCard.formRows and #ccCard.formRows == 3, "the add line is a form: spell, sound, Add")
    Nock.db.profile.pvpCcCustom = {}
    if Nock.RebuildOptionsArgs then Nock:RebuildOptionsArgs() end
  end
  ok(bc.bgBlock == nil, "a table card leaves the background block alone (rows flow instead)")
  -- items merge
  local sx = { type = "group", name = "Shop", args = {
    curated = { type = "header", name = "Curated items", order = 1 },
    restore = ex("Restore curated defaults", 1),
    shop_a = { type = "group", name = "Arrows", order = 3, args = { on = tg("Track"), thr = rg("Keep at least") } },
    shop_b = { type = "group", name = "Haste Potion", order = 4, args = { on = tg("Track"), thr = rg("Keep at least") } },
    other = { type = "header", name = "Other", order = 5 }, thing = tg("Thing"),
  } }
  sx.args.restore.order = 2; sx.args.thing.order = 6
  local sc = W.Cards({ key = "sx", name = "Shop", node = sx, path = { "sx" }, virtual = true }, "Nock")
  local host
  for _, cc in ipairs(sc) do if cc.itemRows then host = cc end end
  ok(host and #host.itemRows == 2 and host.itemRows[2].name == "Haste Potion" and host.actionRows and host.actionRows[1].key == "restore", "curated item cards fold into the Curated items host with Restore in the head")
  ok(#sc == 2, ("two cards remain after the merge (%d)"):format(#sc))
  -- chips
  local cx = { type = "group", name = "C", args = { names = { type = "input", name = "Recipients", multiline = true, get = function() return "" end, set = function() end } } }
  W.SetMeta(cx.args.names, "chips", true)
  local ccard = W.Cards({ key = "cx", name = "C", node = cx, path = { "cx" }, virtual = true }, "Nock")[1]
  ok(ccard.lines[1].rows[1].chips == true, "an input tagged chips carries the flag on its row")
end

-- Legend painters are exported without AceGUI present (UI/AceGUI_BarLegends.lua).
_G.CreateFrame = dofile("Tests/lib/frame_stub.lua").CreateFrame
_G.UIParent = _G.CreateFrame("Frame", "UIParent")
dofile("UI/AceGUI_BarLegends.lua")
ok(type(Nock.UI.PaintShotBarsLegend) == "function" and type(Nock.UI.PaintReactLegend) == "function", "legend painters exported without AceGUI")
local lf = _G.CreateFrame("Frame"); lf:SetWidth(600)
local lh = Nock.UI.PaintShotBarsLegend(lf)
ok(type(lh) == "number" and lh > 40 and lf._legends and lf._legends.shot ~= nil, "shot-bars painter measures a height and keeps its parts on the frame: " .. tostring(lh))
Nock.UI.PaintReactLegend(lf)
ok(lf._legends.react ~= nil and lf._legends.shot ~= nil, "both legends can share one pooled frame, parts kept apart")
local rf = _G.CreateFrame("Frame"); rf:SetWidth(600)
ok(Nock.UI.PaintReactLegend(rf) > 40, "react painter measures a height")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
