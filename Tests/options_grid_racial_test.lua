-- Tests/options_grid_racial_test.lua
-- The React cooldown grid's settings list on Forever: racials the character
-- does not have (and untracked name-only racials) are hidden, Up/Down skip
-- hidden neighbours, the pair entry names both spells. TBC lists every key.
-- Run from the repo root: luajit Tests/options_grid_racial_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

-- A night elf: Elune + Meld known, Percep tracked but not known, Stone
-- untracked (the spellbook never named it).
local ENTRIES = {
  Arc      = { key = "Arc", type = "spell", id = 3044, label = "Arcane Shot" },
  AimMulti = { key = "AimMulti", type = "spell", ids = { 2643, 19434 }, label = "Multi + Aimed" },
  Elune    = { key = "Elune", type = "spell", id = 1259799, label = "Elune's Light", racial = true },
  Percep   = { key = "Percep", type = "spell", id = 20600, label = "Perception", racial = true },
  Meld     = { key = "Meld", type = "spell", id = 20580, label = "Shadowmeld", racial = true },
}
local AVAILABLE = { Percep = false }
local CD = {
  GetEntry = function(_, k) return ENTRIES[k] end,
  GetTracked = function() local t = {}; for _, e in pairs(ENTRIES) do t[#t + 1] = e end; return t end,
  IsEntryAvailable = function(_, k) if AVAILABLE[k] == nil then return true end return AVAILABLE[k] end,
  GetOrderedGridKeys = function() return {} end,
}
local h = dofile("Tests/lib/options_harness.lua")
local Nock, _, opts = h({
  catalogs = { Cooldowns = CD, Warnings = { Catalog = {} }, Helpers = { Catalog = {} } },
  profile = { hudMode = "react", reactCdRows = { { "Arc", "Percep", "Stone", "Elune", "Meld", "AimMulti" } } },
})

local function findGrid(node)
  if type(node) ~= "table" or type(node.args) ~= "table" then return nil end
  if node.args.rcd_reset then return node.args end
  for _, v in pairs(node.args) do
    local hit = findGrid(v)
    if hit then return hit end
  end
end
local g = findGrid(opts)
ok(g ~= nil, "found the React grid list")

local function hidden(k) local n = g["rcd_en_1_" .. k]; return n and type(n.hidden) == "function" and n.hidden() == true end
local function rowKeys() return Nock.db.profile.reactCdRows[1] end

-- TBC: every key listed.
ok(not hidden(2) and not hidden(3), "TBC: nothing hidden")

Nock.Flavor.forever = true
ok(hidden(2), "Forever: Perception (not known) hidden")
ok(hidden(3), "Forever: Stone (untracked) hidden")
ok(not hidden(1) and not hidden(4) and not hidden(5) and not hidden(6), "Forever: Arc, Elune, Meld, the pair shown")

-- Up on Elune (4) skips the hidden 3 and 2: it swaps with Arc (1).
g.rcd_up_1_4.func()
local r = rowKeys()
ok(r[1] == "Elune" and r[4] == "Arc" and r[2] == "Percep" and r[3] == "Stone", "Up skips hidden neighbours")

-- Rebuilt list: Elune first -> its Up disabled; the pair last -> its Down disabled.
g = findGrid(opts)
ok(g.rcd_up_1_1.disabled() == true, "first visible: Up disabled")
ok(g.rcd_dn_1_6.disabled() == true, "last visible: Down disabled")
-- Down on Arc (now 4) skips nothing hidden after it: swaps with Meld (5).
g.rcd_dn_1_4.func()
r = rowKeys()
ok(r[4] == "Meld" and r[5] == "Arc", "Down swaps with the next visible")

-- The Add dropdown leaves unavailable racials out.
g = findGrid(opts)
Nock.db.profile.reactCdRows = { {} }
Nock:RebuildOptionsArgs()
g = findGrid(opts)
local vals = g.rcd_add_1.values()
ok(vals.Elune and vals.Arc and not vals.Percep, "Add: Perception left out on Forever")

-- The pair names both spells.
ok(vals.AimMulti and vals.AimMulti:find("2643 + 19434", 1, true) and not vals.AimMulti:find("nil", 1, true), "pair label: both ids, no nil")

-- The add form offers Spell only on Forever (custom items are not tracked there).
ok(g.addType and g.addType.values().item == nil and g.addType.get() == "spell", "Forever: add form is spell-only")
Nock.Flavor.forever = false
ok(g.addType.values().item == "Item", "TBC: add form keeps Item")

-- The Add button is never disabled; with no id it adds nothing.
do
  local printed = 0
  Nock.Print = function() printed = printed + 1 end
  ok(g.addBtn and g.addBtn.disabled == nil, "Add entry is never disabled")
  g.addId.set(nil, "")
  g.addBtn.func()
  ok(printed == 1 and (Nock.db.profile.cooldownCustom == nil or #Nock.db.profile.cooldownCustom == 0), "no id: a hint, nothing added")
  g.addId.set(nil, "1543")
  g.addBtn.func()
  ok(Nock.db.profile.cooldownCustom and #Nock.db.profile.cooldownCustom == 1 and Nock.db.profile.cooldownCustom[1].id == 1543, "with an id: added")
end

-- After an add (or a reorder) the page is laid out again: the row titles
-- stay visible, and the rows sit in their own card after the Grid card
-- instead of jumping above every card (2026-09-24).
do
  g = findGrid(opts)
  local function visible(k) local n = g[k]; return n and not (n.hidden == true or (type(n.hidden) == "function" and n.hidden())) end
  ok(g.rowsCard and g.rowsCard.type == "header", "rows card header present")
  ok(visible("rcd_row1"), "row title visible after the add")
  ok(g.rcd_row1.order > g.gridCard.order and g.rcd_row1.order > g.rowsCard.order, "rows sit in their card, below the Grid card")
  ok(g.customEntriesCard and visible("rcust_1") and g.rcust_1.order > g.customEntriesCard.order, "custom entry listed in its card")
  Nock.db.profile.reactCdRows = { { "Arc", "Elune" } }
  Nock:RebuildOptionsArgs(); g = findGrid(opts)
  g.rcd_dn_1_1.func(); g = findGrid(opts)
  ok(visible("rcd_row1") and g.rcd_row1.order > g.rowsCard.order, "a reorder keeps the layout")
end

print(("options_grid_racial: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
