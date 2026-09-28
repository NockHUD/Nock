-- Tests/cooldown_picker_test.lua
-- Core/CooldownPicker.lua: tray items, flyout groups, name-or-ID resolve, meta lines.
-- Run from the repo root: luajit Tests/cooldown_picker_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local Nock = {}
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/CooldownEditor.lua")
dofile("Core/CooldownPicker.lua")
local P = Nock.CooldownPicker

local entries = {
  { key = "Arc", id = 3044, cat = "Class", cd = 6, lv = 6 },
  { key = "RF", id = 3045, cat = "Class", cd = 300, lv = 26 },
  { key = "Volley", id = 1510, name = "Volley", cat = "Class", cd = 60, lv = 40 },
  { key = "BW", id = 19574, name = "Bestial Wrath", cat = "Talent", cd = 120, talent = true },
  { key = "Zerk", name = "Berserking", cat = "Racial", cd = 180, racial = true },
  { key = "Elune", name = "Elune's Light", cat = "Racial", cd = 180, racial = true },
}
local NAMES = { Arc = "Arcane Shot", RF = "Rapid Fire", Volley = "Volley", BW = "Bestial Wrath", Zerk = "Berserking", Elune = "Elune's Light" }
local known = { Arc = true, RF = true, Volley = false, BW = false, Zerk = true }
local ctx = {
  entries = entries,
  rows = { { "Arc" }, {} },
  known = function(k) return known[k] end,
  available = function(k) return k ~= "Elune" end,
  recent = { 781, 3045 },
  nameOf = function(x) if type(x) == "table" then return NAMES[x.key] end; return ({ [781] = "Disengage", [3045] = "Rapid Fire" })[x] end,
  byId = function(id) if id == 3045 then return "RF" end end,
}

local all = P.TrayItems(ctx, "All", "")
local keys = {}
for _, it in ipairs(all) do keys[#keys + 1] = it.key end
ok(table.concat(keys, ",") == "Arc,RF,Volley,BW,Zerk", "All: catalog order, other-race racials hidden")
ok(all[1].placedRow == 1 and all[2].placedRow == nil, "placed row reported")
ok(#P.TrayItems(ctx, "Talent", "") == 1, "Talent tab")
ok(#P.TrayItems(ctx, "All", "rap") == 1 and P.TrayItems(ctx, "All", "rap")[1].key == "RF", "query filters by name, case-insensitive")
local rec = P.TrayItems(ctx, "Recent", "")
ok(#rec == 2 and rec[1].id == 781 and rec[1].key == nil and rec[2].key == "RF", "Recent: non-catalog by id, catalog by key")

local g = P.FlyoutGroups(ctx, "")
ok(g[1].title == "Suggested: you have these" and #g[1].items == 2, "Suggested = known, available, not placed (RF, Zerk)")
ok(g[2].title == "Recently cast" and g[2].items[1].id == 781, "Recently cast group")
ok(g[3].title == "Catalog" and #g[3].items == 2, "Catalog = the rest not placed (Volley, BW)")
ctx.recent = {}
ok(#P.FlyoutGroups(ctx, "") == 2, "empty groups are dropped")

local names = { ["Arcane Shot"] = 3044, ["Disengage"] = 781 }
ok(P.Resolve("3044", names, ctx).key == "Arc", "digits -> catalog key by id (entry.id)")
ok(P.Resolve("781", names, ctx).id == 781, "digits outside the catalog -> id")
ok(P.Resolve("disengage", names, ctx).id == 781, "a spellbook name, case-insensitive")
ok(P.Resolve("arcane shot", names, ctx).key == "Arc", "a spellbook name of a catalog spell -> its key")
ok(P.Resolve("nonsense", names, ctx) == nil, "unresolved -> nil")
ok(P.Resolve("", names, ctx) == nil, "empty -> nil")
ok(P.Resolve("-5", names, ctx) == nil, "-5 is treated as a name, not an id, and doesn't resolve")
ok(P.Resolve("1e3", names, ctx) == nil, "1e3 is treated as a name, not an id, and doesn't resolve")

ok(P.Meta({ cd = 300, lv = 26, known = false }) == "CD 5m · Lv 26", "meta: untrained")
ok(P.Meta({ cd = 120, talent = true, known = false }) == "CD 2m · talent", "meta: talent")
ok(P.Meta({ cd = 180, cat = "Racial", known = true }) == "CD 3m · your racial", "meta: racial")
ok(P.Meta({ cd = 6, known = true }) == "CD 6s", "meta: known class spell")
ok(P.Meta({ id = 781 }) == "cast recently", "meta: recent")
ok(P.Meta({ custom = true }) == "custom", "meta: custom")

-- Custom spells
ok(P.TABS[1] == "All" and P.TABS[2] == "Class" and P.TABS[3] == "Talent" and P.TABS[4] == "Racial"
   and P.TABS[5] == "Custom" and P.TABS[6] == "Recent", "TABS order")

ctx.customs = {
  { key = "Cust1", id = 9001, name = "Custom One" },
  { key = "Cust2", id = 9002, name = "Custom Two" },
}
local allWithCustoms = P.TrayItems(ctx, "All", "")
local akeys = {}
for _, it in ipairs(allWithCustoms) do akeys[#akeys + 1] = it.key end
ok(table.concat(akeys, ",") == "Arc,RF,Volley,BW,Zerk,Cust1,Cust2", "All: customs appended after the catalog")

local customTab = P.TrayItems(ctx, "Custom", "")
local ckeys = {}
for _, it in ipairs(customTab) do ckeys[#ckeys + 1] = it.key end
ok(table.concat(ckeys, ",") == "Cust1,Cust2", "Custom tab lists only customs")
ok(customTab[1].cat == "Custom" and customTab[1].custom == true and customTab[1].known == true, "custom item shape")
ok(customTab[1].placedRow == nil, "an unplaced custom reports no placedRow")

ctx.rows = { { "Arc", "Cust1" }, {} }
local customTab2 = P.TrayItems(ctx, "Custom", "")
ok(customTab2[1].placedRow == 1 and customTab2[2].placedRow == nil, "custom items report placedRow")

ok(P.Resolve("9001", names, ctx).key == "Cust1", "digits matching an existing custom's id resolve to its key")
ok(P.Resolve("9999", names, ctx).id == 9999, "digits matching neither catalog nor custom -> id")

print(("cooldown_picker: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
