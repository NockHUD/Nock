-- Tests/forever_pet_abilities_test.lua
-- Forever/PetAbilities.lua: the pet catalog (ranks collapsed by name, no-cooldown abilities out),
-- the summoned pet's known names, and the pet bar slot match.
-- Run from the repo root: luajit Tests/forever_pet_abilities_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local PA = dofile("Forever/PetAbilities.lua")

-- The probe's numbers (2026-10-09): Bite ranks 10 s, Claw none, Dash 30 s,
-- Prowl 10 s, Swipe 5 s, Growl 5 s (spellbook only).
local NAMES = { [17253] = "Bite", [17256] = "Bite", [17261] = "Bite", [16827] = "Claw", [16829] = "Claw",
  [23099] = "Dash", [23110] = "Dash", [24450] = "Prowl", [1264494] = "Swipe", [1264502] = "Swipe",
  [14917] = "Growl", [999] = "Mystery" }
local CD = { Bite = 10000, Claw = 0, Dash = 30000, Prowl = 10000, Swipe = 5000, Growl = 5000 }
local api = {
  nameOf = function(id) return NAMES[id] end,
  baseCd = function(id) return CD[NAMES[id]] end,   -- Mystery: nil (cannot say)
}
local cat = { name = "FroggoSmoll", petAbilities = { 17256, 17253, 17261, 16827, 16829, 23099, 23110, 24450 } }
local bear = { name = "Bear", petAbilities = { 17253, 1264494, 1264502, 23099 } }
local book = { { id = 17256, name = "Bite" }, { id = 16829, name = "Claw" }, { id = 14917, name = "Growl" } }

local list = PA.Catalog({ cat, bear }, book, "FroggoSmoll", api)
local by = {}
for _, e in ipairs(list) do by[e.name] = e end
ok(#list == 6 and list[1].name == "Bite" and list[2].name == "Claw" and list[#list].name == "Swipe", "sorted by name, every ability offered")
ok(by.Claw and by.Claw.cd == nil and by.Claw.key == "p16827", "a no-cooldown ability (Claw) is offered with no cooldown")
ok(by.Bite.key == "p17253" and #by.Bite.ids == 3 and by.Bite.ids[1] == 17253 and by.Bite.ids[3] == 17261,
  "ranks collapse into one entry keyed by the lowest id, ids ascending")
ok(by.Bite.cd == 10 and by.Dash.cd == 30 and by.Swipe.cd == 5, "cooldown in seconds")
ok(#by.Bite.pets == 2 and by.Bite.pets[1] == "FroggoSmoll" and by.Bite.pets[2] == "Bear", "which pets have it")
ok(#by.Swipe.pets == 1 and by.Swipe.pets[1] == "Bear", "a family ability names its pet only")
ok(by.Growl and by.Growl.key == "p14917" and by.Growl.pets[1] == "FroggoSmoll", "spellbook-only ability (Growl) listed for the summoned pet")
local withMystery = PA.Catalog({ { name = "X", petAbilities = { 999 } } }, nil, nil, api)
ok(#withMystery == 1 and withMystery[1].cd == nil, "an unknown base cooldown is kept (cannot say)")
ok(#PA.Catalog(nil, nil, nil, api) == 0, "no pets: empty")
ok(#PA.Catalog({ { name = "X", petAbilities = { 12345 } } }, nil, nil, api) == 0, "an unnamed spell is skipped")

local known = PA.KnownNames(book)
ok(known.Bite and known.Claw and known.Growl and not known.Dash, "known names from the spellbook")
ok(PA.Signature(known) == PA.Signature({ Growl = true, Claw = true, Bite = true }), "signature ignores order")
ok(PA.Signature(known) ~= PA.Signature({ Bite = true }), "signature changes with the set")
ok(PA.Signature({}) == "", "empty set")

local bar = { [4] = { id = 14917, name = "Growl" }, [5] = { id = 17256, name = "Bite" }, [6] = { id = 16829, name = "Claw" } }
ok(PA.BarSlot(bar, by.Bite.ids, "Bite") == 5, "bar slot by rank id")
local slot, id = PA.BarSlot(bar, { 17253 }, "Bite")
ok(slot == 5 and id == 17256, "a rank the record never saw matches on the name, returning the learned id")
ok(PA.BarSlot(bar, by.Dash.ids, "Dash") == nil, "not on the bar")
ok(PA.BarSlot(nil, by.Dash.ids, "Dash") == nil, "no bar")

print(("forever_pet_abilities: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
