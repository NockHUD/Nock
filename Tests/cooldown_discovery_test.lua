-- Tests/cooldown_discovery_test.lua
-- Forever/CooldownDiscovery.lua: scan rows -> catalog entries (filter, rank merge, key preservation, links).
-- Run from the repo root: luajit Tests/cooldown_discovery_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local Nock = { Flavor = { Plain = function(v) return v end }, API = { SpellName = function() return nil end } }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/CooldownDiscovery.lua")
local D = Nock.CooldownDiscovery

-- level-20 probe (2026-09-27), trimmed: id, name, src, line, passive, baseMs, rank, max
local function R(id, name, src, line, passive, baseMs, rank, max)
  return { id = id, name = name, src = src, line = line, passive = passive, baseMs = baseMs, rank = rank, max = max,
           talent = (src == "talent") or nil }
end
local rows = {
  R(1259799, "Elune's Light", "book", 1, false, 180000), R(20580, "Shadowmeld", "book", 1, false, 10000),
  R(2764, "Throw", "book", 1, false, 0), R(6603, "Attack", "book", 1, false, 0),
  R(5118, "Aspect of the Cheetah", "book", 2, false, 0), R(1513, "Scare Beast", "book", 2, false, 30000),
  R(781, "Disengage", "book", 3, false, 5000), R(1499, "Freezing Trap", "book", 3, false, 30000),
  R(13795, "Immolation Trap", "book", 3, false, 30000), R(1495, "Mongoose Bite", "book", 3, false, 5000),
  R(2973, "Raptor Strike", "book", 3, false, 6000), R(14260, "Raptor Strike", "book", 3, false, 6000),
  R(14261, "Raptor Strike", "book", 3, false, 6000),
  R(19434, "Aimed Shot", "book", 4, false, 6000), R(2643, "Multi-Shot", "book", 4, false, 6000),
  R(3044, "Arcane Shot", "book", 4, false, 6000), R(14281, "Arcane Shot", "book", 4, false, 6000),
  R(75, "Auto Shot", "book", 4, false, 0), R(5116, "Concussive Shot", "book", 4, false, 12000),
  R(1978, "Serpent Sting", "book", 4, false, 0),
  R(19574, "Bestial Wrath", "talent", nil, false, 120000, 0, 1), R(1293241, "Summon Hawk", "talent", nil, false, 6000, 0, 1),
  R(1317257, "Strider Kick", "talent", nil, false, 8000, 0, 1), R(1310533, "Lacerating Strikes", "talent", nil, true, 0, 0, 1),
  R(1310687, "Sniper Shot", "talent", nil, false, 15000, 0, 1), R(1299346, "Trueshot Aura", "talent", nil, false, 0, 0, 1),
  R(415370, "Lone Wolf", "talent", nil, true, 0, 0, 1),
  -- A spell the client has no info for (Nock.API.SpellName came back nil):
  -- Build must drop the row, not crash trying to key a group table with it.
  R(1234567, nil, "talent", nil, false, 9000, 0, 1),
}
local static = {
  { key = "Raptor", id = 2973, name = "Raptor Strike", cat = "Class", row = 1 },
  { key = "Arc", id = 3044, name = "Arcane Shot", cat = "Class", row = 1, shared = "arcaneHawk" },
  { key = "AimMulti", ids = { 2643, 19434 }, names = { "Multi-Shot", "Aimed Shot" }, cat = "Class", row = 1, shared = "aimedMulti" },
  { key = "Hawk", id = 1293241, name = "Summon Hawk", talent = true, cat = "Talent", row = 1, shared = "arcaneHawk" },
  { key = "Multi", id = 2643, name = "Multi-Shot", cat = "Class", row = 1, shared = "aimedMulti" },
  { key = "Aimed", id = 19434, name = "Aimed Shot", cat = "Class", row = 1, shared = "aimedMulti" },
  { key = "RF", id = 3045, name = "Rapid Fire", lv = 26, cat = "Class", row = 1 },
  { key = "BW", id = 19574, name = "Bestial Wrath", talent = true, cat = "Talent", row = 2 },
  { key = "Sniper", id = 1310687, name = "Sniper Shot", talent = true, cat = "Talent", row = 2 },
  { key = "Elune", id = 1259799, name = "Elune's Light", racial = true, cat = "Racial", row = 1 },
  { key = "Stone", name = "Stoneform", racial = true, cat = "Racial", row = 1 },
}
local list = D.Build(rows, static)
local by = {}
for i, e in ipairs(list) do by[e.key] = e; e._i = i end

for _, k in ipairs({ "s2764", "s6603", "s5118", "s75", "s1978", "s1310533", "s1299346", "s415370" }) do
  ok(by[k] == nil, "dropped (no cooldown, or passive): " .. k)
end
ok(by.s13795 and by.s13795.cd == 30 and by.s13795.cat == "Class" and not by.s13795.racial, "Immolation Trap discovered, 30 s seed")
ok(by.s1317257 and by.s1317257.cat == "Talent" and by.s1317257.talent == true and by.s1317257.cd == 8, "Strider Kick is a talent entry")
ok(by.s20580 and by.s20580.cat == "Racial" and by.s20580.racial == true, "a General-tab active with a cooldown is Racial")
ok(by.s1234567 == nil, "a row with no usable name is dropped, not crashed")
ok(by.Raptor and by.Raptor.cd == 6 and by.Raptor.discovered and by.s14260 == nil, "Raptor ranks merge into the static key")
ok(by.AimMulti and by.AimMulti.cd == 6 and by.s19434 == nil and by.s2643 == nil, "the pair keeps its key; neither half is its own entry")
ok(by.Sniper and by.Sniper.cd == 15 and by.s1310687 == nil, "a static Forever entry keeps its key")
ok(by.Elune and by.Elune.cd == 180, "racial seed from the client")
-- A client group can match SEVERAL static entries: the "Summon Hawk" group
-- discovers the Hawk entry (its own tile, never a new s<id>); the "Multi-Shot"
-- and "Aimed Shot" groups each discover BOTH the AimMulti pair AND their own
-- single entry -- nothing takes over another tile.
ok(by.Hawk and by.Hawk.cd == 6 and by.Hawk.discovered == true, "Summon Hawk is discovered as its own entry, cd 6")
ok(by.s1293241 == nil, "Summon Hawk is never a new s<id> entry")
ok(by.Multi and by.Multi.cd == 6 and by.Multi.discovered == true, "the Multi-Shot group also discovers the Multi single entry")
ok(by.Aimed and by.Aimed.cd == 6 and by.Aimed.discovered == true, "the Aimed Shot group also discovers the Aimed single entry")
ok(by.Arc.linked == nil and by.Hawk.linked == nil, "no linked field anywhere")
ok(by.RF and not by.RF.discovered and by.RF.lv == 26, "an untrained baseline spell stays, undiscovered")
ok(by.Stone and not by.Stone.discovered, "another race's racial stays")
ok(by.Raptor._i < by.s13795._i and by.Stone._i < by.s13795._i, "statics come first, new entries after")
ok(static[1].cd == nil and static[2].cd == nil, "Build never mutates the overlay")

-- Signature has no link part: an identical rebuild is stable, and it carries
-- nothing but "key=cd" pairs (a Hawk rank flip lives in Cooldowns.lua's own
-- known map now, not here).
local l2 = D.Build(rows, static)
ok(D.Signature(list) == D.Signature(l2), "signature is stable across an identical rebuild")
ok(not D.Signature(list):find(".", 1, true), "the signature carries no link part")

local api = {
  book = function() return { { id = 19574, name = "Bestial Wrath", src = "book:Beast", line = 2, passive = false },
                             { id = 8888, name = nil, src = "book:Beast", line = 2, passive = false } } end,
  talents = function() return { { id = 19574, name = "Bestial Wrath", src = "talent", rank = 1, max = 1 },
                                { id = 415370, name = "Lone Wolf", src = "talent", rank = 0, max = 1 },
                                { id = 9999, name = nil, src = "talent", rank = 1, max = 1 } } end,
  passive = function(id) return id == 415370 end,
  baseCd = function(id) if id == 19574 then return 120000, 0 end return 0, 0 end,
}
local rr = D.Rows(api)
ok(#rr == 2 and rr[1].talent == true and rr[1].baseMs == 120000 and rr[1].line == 2, "a book+talent spell is one row")
ok(rr[2].passive == true and rr[2].rank == 0 and rr[2].talent == true, "passive fallback, rank and talent carried")
for _, r in ipairs(rr) do
  ok(r.id ~= 8888 and r.id ~= 9999, "a book or talent row with no usable name is not built: " .. r.id)
end

print(("cooldown_discovery: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
