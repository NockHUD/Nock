-- Tests/forever_buffs_test.lua
-- Forever/Buffs.lua: own casts stamp buffs from seeded/learned durations,
-- the cache learns and corrects out of combat, entries expire and sort.
-- Run from the repo root: luajit Tests/forever_buffs_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local now = 100
_G.GetTime = function() return now end
_G.GetRangedHaste = function() return 0 end
local petExists, happiness = true, 3
_G.UnitExists = function(u) return u == "pet" and petExists or false end
_G.C_PetInfo = { GetPetHappiness = function() return happiness, 125, 20 end }
local secretAuras = false
local cache, reads = {}, 0
local Nock = {
  Flavor = { forever = true, Plain = function(v) return v end }, Constants = {},
  API = { SpellIcon = function(id) return 1000 + id end, SpellName = function(id) return ({ [136] = "Mend Pet", [3111] = "Mend Pet" })[id] or ("s" .. id) end },
  AuraCache = { BySpell = function(unit, id) reads = reads + 1; return cache[unit .. id] end },
  Restricted = function() return secretAuras end,
  db = { char = {} },
}
local module
function Nock:NewModule(name) module = { name = name, events = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  return module end
function Nock:GetModule() return nil end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/Spells.lua")
dofile("Forever/Buffs.lua")
local B = module
-- The shipped catalog holds only what the client's aura container cannot
-- draw: buffs living on the pet. The engine tests below run on a fuller
-- list so seeds, learning, permanents and procs stay covered.
local shipped = {}
for _, b in ipairs(Nock.Spells.BUFFS) do shipped[#shipped + 1] = b.id end
table.sort(shipped)
ok(table.concat(shipped, ",") == "136,6991", "shipped ledger list = Mend Pet + Feed Pet only, got " .. table.concat(shipped, ","))
Nock.Spells.BUFFS = {
  { id = 3045,    key = "RF",    dur = 15 },
  { id = 1259799, key = "Elune", dur = nil },
  { id = 20580,   key = "Meld",  dur = nil },
  { id = 136,  key = "Mend", dur = nil, units = { "pet" } },
  { id = 6991, key = "Feed", dur = nil, units = { "pet", "player" }, aura = 1539 },
  { id = 6150, key = "Quick", dur = nil },
}
ok(B and B.name == "BuffLedger" and B.refreshInterval == 0.1, "module BuffLedger on the slow lane")
B:OnEnable()
local st = Nock.state
local lb = st.ledgerBuffs
local function fire(ev, ...) local h = B.events[ev]; B[type(h) == "string" and h or ev](B, ev, ...) end

-- Combat: Rapid Fire cast with the seed (15 s).
secretAuras = true
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 3045)
B:Refresh(st)
ok(lb.n == 1 and lb[1].icon == 1000 + 3045 and lb[1].exp == 115 and lb[1].dur == 15, "RF published from the seed")
-- A buff with no seed publishes nothing until learned.
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 1259799)
B:Refresh(st)
ok(lb.n == 1, "unseeded buff not published")
-- No cache reads in combat.
local r0 = reads
B:Refresh(st)
ok(reads == r0, "no cache read while auras are secret")
-- Expiry.
now = 116
B:Refresh(st)
ok(lb.n == 0, "expired entry removed")

-- Out of combat: the cache is the truth and teaches the duration.
secretAuras = false
now = 120
cache["player3045"] = { duration = 20, expirationTime = 130 }
cache["player1259799"] = { duration = 8, expirationTime = 125 }
B:Refresh(st)
ok(lb.n == 2 and lb[1].exp == 125 and lb[2].exp == 130, "two entries, soonest first")
ok(Nock.db.char.foreverBuffLearned[3045] == 20 and Nock.db.char.foreverBuffLearned[1259799] == 8, "durations remembered")
-- Cache says RF is gone -> entry removed.
cache["player3045"] = nil
B:Refresh(st)
ok(lb.n == 1 and lb[1].exp == 125, "absent from the cache -> removed")
-- Back in combat, the learned Elune duration now stamps.
secretAuras = true
now = 200
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 1259799)
B:Refresh(st)
ok(lb.n == 1 and lb[1].exp == 208 and lb[1].dur == 8, "learned duration used for the next cast")
-- Permanent buff (Shadowmeld, no expiry): shown from the cache without a
-- countdown, after timed entries; dropped once auras are secret.
secretAuras = false
now = 300
cache["player20580"] = { duration = 0, expirationTime = 0 }
cache["player1259799"] = { duration = 8, expirationTime = 305 }
B:Refresh(st)
ok(lb.n == 2 and lb[1].exp == 305 and lb[2].icon == 1000 + 20580 and lb[2].exp == 0, "permanent buff published last, no countdown")
secretAuras = true
B:Refresh(st)
ok(lb.n == 1 and lb[1].exp == 305, "permanent buff dropped when auras go secret")
secretAuras = true

-- Other units and unknown spells ignored.
fire("UNIT_SPELLCAST_SUCCEEDED", "target", "g", 3045)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 42)
B:Refresh(st)
ok(lb.n == 1, "ignored casts")

-- A proc (Quick Shots, no cast to stamp): shown from the cache out of
-- combat (dummies are not combat on Forever), nothing in combat until the
-- aura-container row exists.
secretAuras = false
now = 350
cache["player6150"] = { duration = 12, expirationTime = 360 }
B:Refresh(st)
local quick
for i = 1, lb.n do if lb[i].icon == 1000 + 6150 then quick = lb[i] end end
ok(quick and quick.exp == 360 and quick.dur == 12, "Quick Shots published from the cache out of combat")
cache["player6150"] = nil
secretAuras = true
now = 355
B:Refresh(st)
quick = nil
for i = 1, lb.n do if lb[i].icon == 1000 + 6150 then quick = lb[i] end end
ok(quick and quick.exp == 360, "a proc seen before combat keeps counting down into it")
now = 365
B:Refresh(st)
quick = nil
for i = 1, lb.n do if lb[i].icon == 1000 + 6150 then quick = lb[i] end end
ok(quick == nil, "no cast, no stamp: a proc that fires in combat is not shown")

-- Pet buffs: Mend Pet and Feed Pet are cast on the player but live on the
-- pet, so they are learned from the pet's auras (Feed Pet's buff is a
-- different spell from the cast).
secretAuras = false
now = 400
cache["pet136"] = { duration = 15, expirationTime = 412 }
cache["pet1539"] = { duration = 20, expirationTime = 418 }
B:Refresh(st)
local seen = {}
for i = 1, lb.n do seen[lb[i].icon] = lb[i] end
ok(seen[1000 + 136] and seen[1000 + 136].exp == 412 and seen[1000 + 6991] and seen[1000 + 6991].exp == 418, "Mend and Feed published from the pet's auras")
ok(Nock.db.char.foreverBuffLearned[136] == 15 and Nock.db.char.foreverBuffLearned[6991] == 20, "pet buff durations remembered under the cast id")
cache["pet136"], cache["pet1539"] = nil, nil
secretAuras = true
now = 500
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 136)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 6991)
B:Refresh(st)
seen = {}
for i = 1, lb.n do seen[lb[i].icon] = lb[i] end
ok(seen[1000 + 136] and seen[1000 + 136].exp == 515 and seen[1000 + 6991] and seen[1000 + 6991].exp == 520, "in combat the casts stamp the learned durations")

-- A higher rank resolves by name (ranks are separate spells on Forever).
secretAuras = true
now = 550
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 3111)
B:Refresh(st)
seen = {}
for i = 1, lb.n do seen[lb[i].icon] = lb[i] end
ok(seen[1000 + 136] and seen[1000 + 136].exp == 565, "Mend Pet rank 2 stamps the Mend entry by name")

-- Pet happiness: a face tile in combat only, only while the pet is not
-- Happy, read live (plain on Forever), never with a countdown.
now = 600
st.player.inCombat = true
happiness = 3
B:Refresh(st)
local function faceEntry() for i = 1, lb.n do if lb[i].coords then return lb[i] end end return nil end
ok(faceEntry() == nil, "happy pet -> no face")
happiness = 2
B:Refresh(st)
local f = faceEntry()
ok(f and f.exp == 0 and f.dur == 0 and f.coords[1] == 0.1875, "content pet -> the Content face, no countdown")
happiness = 1
B:Refresh(st)
f = faceEntry()
ok(f and f.coords[1] == 0.375, "unhappy pet -> the Unhappy face")
st.player.inCombat = false
B:Refresh(st)
ok(faceEntry() == nil, "out of combat -> no face")
st.player.inCombat = true
petExists = false
B:Refresh(st)
ok(faceEntry() == nil, "no pet -> no face")
petExists = true
Nock.Flavor.Plain = function(v) return nil end
B:Refresh(st)
ok(faceEntry() == nil, "secret happiness -> no face")
Nock.Flavor.Plain = function(v) return v end
happiness = 3
B:Refresh(st)
for i = 1, lb.n do ok(lb[i].coords == nil, "a reused entry carries no stale coords") end
print(("forever_buffs: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
