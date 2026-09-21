-- Tests/forever_buffs_test.lua
-- Forever/Buffs.lua: own casts stamp buffs from seeded/learned durations,
-- the cache learns and corrects out of combat, entries expire and sort.
-- Run from the repo root: luajit Tests/forever_buffs_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local now = 100
_G.GetTime = function() return now end
_G.GetRangedHaste = function() return 0 end
local secretAuras = false
local cache, reads = {}, 0
local Nock = {
  Flavor = { forever = true, Plain = function(v) return v end }, Constants = {},
  API = { SpellIcon = function(id) return 1000 + id end, SpellName = function(id) return "s" .. id end },
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
print(("forever_buffs: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
