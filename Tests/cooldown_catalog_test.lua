-- Tests/cooldown_catalog_test.lua
-- Forever/CooldownCatalog.lua: catalog shape, pack integrity, racial expansion, "Everything I know".
-- Run from the repo root: luajit Tests/cooldown_catalog_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = { Flavor = { forever = true }, Constants = { TRACKED_COOLDOWNS = {}, REACT_CD_ROWS = {} } }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/Spells.lua")
dofile("Forever/CooldownCatalog.lua")
local Cat = Nock.CooldownCatalog

-- shape
local seen = {}
for _, e in ipairs(Cat.Entries()) do
  ok(type(e.key) == "string" and not seen[e.key], "unique key " .. tostring(e.key))
  seen[e.key] = true
  ok(e.cat == "Class" or e.cat == "Talent" or e.cat == "Racial", e.key .. " has a category")
  ok(e.row == 1 or e.row == 2, e.key .. " has a row hint")
  ok((e.cat == "Racial") == (e.racial == true), e.key .. " racial flag matches its category")
  ok(e.cat ~= "Pet", e.key .. " is not a pet ability (out of scope)")
end
for _, k in ipairs({ "Raptor", "Arc", "AimMulti", "Conc", "RF", "FD", "Elune", "Meld", "Zerk" }) do
  ok(seen[k], "existing key kept: " .. k)
end
for _, k in ipairs({ "Mongoose", "Disengage", "FrzTrap", "Scare", "Flare", "Tranq",
                     "BW", "Intim", "Scatter", "Deter", "Counter", "Sniper", "Strider", "ImmoTrap", "FrostTrap", "ExploTrap", "Viper" }) do
  ok(seen[k], "new key present: " .. k)
  ok(Cat.Entry(k).name ~= nil, k .. " carries a spellbook name")
end
ok(Cat.Entry("BW").talent == true and Cat.Entry("BW").cat == "Talent", "Bestial Wrath is a talent")
for _, e in ipairs(Cat.Entries()) do
  ok(e.cd == nil, e.key .. " has no seed cd (discovered from client)")
end
ok(Cat.Entry("Arc").shared == "arcaneHawk", "Arc shares the arcaneHawk cooldown group")
for _, k in ipairs({ "Hawk", "Hydra", "Multi", "Aimed" }) do
  ok(Cat.Entry(k) ~= nil, "shared-group entry present: " .. k)
end
ok(Cat.Entry("Hawk").shared == "arcaneHawk" and Cat.Entry("Hydra").shared == "arcaneHawk",
   "Hawk and Hydra share the arcaneHawk cooldown group")
do
  local ah = Cat.Entry("ArcHawk")
  ok(ah and ah.shared == "arcaneHawk" and ah.ids and ah.ids[1] == 3044 and ah.ids[2] == 1293241,
     "the combined Arcane + Hawk tile covers both spells on the arcaneHawk cooldown")
  ok(ah and ah.texture == "Interface\\AddOns\\Nock\\Media\\ArcaneHawk", "the combined tile draws its own art, like Multi + Aimed")
  ok(ah and ah.names and ah.names[1] == "Arcane Shot" and ah.names[2] == "Summon Hawk", "the pair matches both spells by name")
end
ok(Cat.Entry("Multi").shared == "aimedMulti" and Cat.Entry("Aimed").shared == "aimedMulti",
   "Multi and Aimed share the aimedMulti cooldown group")
for _, pk in ipairs(Cat.PACKS) do
  if pk.rows then
    for r = 1, 2 do
      for _, k in ipairs(pk.rows[r]) do
        ok(k ~= "Volley" and k ~= "Wyvern", pk.id .. " row " .. r .. " does not reference removed " .. k)
      end
    end
  end
end

-- the copy into Constants keeps the new fields
local C = Nock.Constants
local cBW
for _, e in ipairs(C.TRACKED_COOLDOWNS) do if e.key == "BW" then cBW = e end end
ok(cBW and cBW.cat == "Talent" and cBW.talent == true and cBW.row == 2, "TRACKED_COOLDOWNS copy keeps cat/talent/row")

-- packs
for _, pk in ipairs(Cat.PACKS) do
  if pk.rows then
    for r = 1, 2 do
      for _, k in ipairs(pk.rows[r]) do
        ok(k == "@racials" or Cat.IsCatalogKey(k), pk.id .. " row " .. r .. " key in catalog: " .. k)
      end
    end
  end
end
-- Sting tiles (2026-09-30): the three stings carry `debuff` (their timer is
-- the sting on the target) and each has its rank list; Serpent is on the
-- default grid and in the Leveling pack.
for _, k in ipairs({ "Serpent", "Scorpid", "Viper" }) do
  local e = Cat.Entry(k)
  ok(e and e.debuff == true and e.name ~= nil, k .. " is a sting tile")
  local ranks = Nock.Spells.STING_RANKS[k]
  ok(ranks and ranks[1] == e.id, k .. " has its rank list, rank 1 first")
end
do
  local n = 0
  for k in pairs(Nock.Spells.STING_RANKS) do n = n + 1; ok(Cat.Entry(k) ~= nil, "rank list belongs to a catalog key: " .. k) end
  ok(n == 3, "three stings (no Wyvern Sting on Forever)")
  for _, e in ipairs(Cat.Entries()) do
    ok((e.debuff == true) == (Nock.Spells.STING_RANKS[e.key] ~= nil or e.stings ~= nil), e.key .. ": debuff flag matches the rank lists")
  end
  -- The unified tile: one tile for whichever sting is up, Serpent Sting's
  -- tile while idle, the default in place of three single tiles.
  local u = Cat.Entry("Sting")
  ok(u and u.debuff == true and u.id == Cat.Entry("Serpent").id and u.title == "Sting (any)", "the unified tile: Serpent Sting's id, its own title")
  ok(u.stings and #u.stings == 3, "it covers the three stings")
  for _, k in ipairs(u.stings) do
    ok(Nock.Spells.STING_RANKS[k] ~= nil and Cat.Entry(k).under == "Sting", k .. " is covered by the unified tile")
  end
  ok(Cat.ById(1978) == "Serpent", "Serpent Sting's id still resolves to its own tile (the first single entry keeps an id)")
  ok(Cat.ById(19434) == "Aimed" and Cat.ById(3044) == "Arc", "and a single still beats a pair listed before it")
  local function has(list, key) for _, k in ipairs(list) do if k == key then return true end end return false end
  ok(has(Nock.Spells.ROWS[1].keys, "Sting") and not has(Nock.Spells.ROWS[1].keys, "Serpent"), "the unified tile is on the default grid's first row")
  ok(has(Cat.PackRows("leveling")[1], "Sting"), "and in the Leveling pack")
  local all = Cat.PackRows("all", function(k) return k == "Sting" or k == "Serpent" or k == "Viper" or k == "FD" end)
  ok(has(all[1], "Sting") and not has(all[1], "Serpent") and not has(all[2], "Viper"), "all: the unified tile stands for the single stings")
  all = Cat.PackRows("all", function(k) return k == "Serpent" end)
  ok(has(all[1], "Serpent"), "all: a single sting stays when the unified tile is not known")
end
local rows = Cat.PackRows("leveling")
ok(rows and #rows == 2, "PackRows returns two rows")
local hasZerk, hasToken = false, false
for _, k in ipairs(rows[1]) do if k == "Zerk" then hasZerk = true end; if k == "@racials" then hasToken = true end end
ok(hasZerk and not hasToken, "@racials expands to the racial keys")
local again = Cat.PackRows("leveling")
again[1][1] = "changed"
ok(Cat.PackRows("leveling")[1][1] ~= "changed", "PackRows returns a fresh copy")
ok(Cat.PackRows("nope") == nil, "unknown pack id -> nil")

-- everything I know
local all = Cat.PackRows("all", function(k) return k == "Arc" or k == "FD" or k == "Zerk" end)
ok(#all[1] == 2 and all[1][1] == "Arc" and all[1][2] == "Zerk", "all: known row-1 entries in catalog order")
ok(#all[2] == 1 and all[2][1] == "FD", "all: known row-2 entries")

-- "all" collapses a shared-cooldown group to its first known member (catalog
-- order) so Everything I know never stacks AimMulti+Multi+Aimed or Arc+Hawk.
local function countIn(list, key)
  local n = 0
  for _, k in ipairs(list) do if k == key then n = n + 1 end end
  return n
end
local allShared = Cat.PackRows("all", function(k)
  return k == "Arc" or k == "Hawk" or k == "AimMulti" or k == "Multi" or k == "Aimed"
end)
ok(countIn(allShared[1], "Arc") == 1 and countIn(allShared[1], "Hawk") == 0,
   "all: only Arc (first in catalog order) survives the arcaneHawk group")
ok(countIn(allShared[1], "AimMulti") == 1 and countIn(allShared[1], "Multi") == 0 and countIn(allShared[1], "Aimed") == 0,
   "all: only AimMulti (first in catalog order) survives the aimedMulti group")

ok(Cat.ById(3044) == "Arc", "ById finds a catalog key by spell id")
-- A shared id resolves to the single spell's own entry, whichever side of
-- the pair tile it is listed on (AimMulti comes before Multi/Aimed, ArcHawk
-- after Arc/Hawk).
ok(Cat.ById(19434) == "Aimed", "ById resolves a shared id to the single entry, not the pair")
ok(Cat.ById(2643) == "Multi", "ById resolves the other half the same way")
ok(Cat.ById(1293241) == "Hawk", "a pair listed after its singles does not steal their ids")
ok(Cat.Entry("Hydra").id == 1293020 and Cat.ById(1293020) == "Hydra", "Hydra Shot carries its Forever id")

print(("cooldown_catalog: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
