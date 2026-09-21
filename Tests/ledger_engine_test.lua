-- Tests/ledger_engine_test.lua
-- Forever/LedgerEngine.lua: own cast stamps + learned cooldowns -> plain
-- remaining/ready, shared groups, snapshot seeds and out-of-combat reconcile.
-- Run from the repo root: luajit Tests/ledger_engine_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

local Nock = {}
_G.LibStub = function() return { GetAddon = function() return Nock end } end
local E = dofile("Forever/LedgerEngine.lua")
ok(E == Nock.LedgerEngine, "engine exported on the addon and returned")

local s = E.New()
local AIMED, MULTI, RAPTOR = 19434, 2643, 2973

-- Nothing known: ready, zeros.
local st, du, rem, ready = E.Cooldown(s, RAPTOR, 100)
ok(st == 0 and du == 0 and rem == 0 and ready == true, "unknown spell is ready with zeros")
ok(E.Known(s, RAPTOR) == false, "Known false before Learn")

-- A cast with no learned duration stamps nothing usable (still ready).
E.OnCast(s, RAPTOR, 100)
st, du, rem, ready = E.Cooldown(s, RAPTOR, 101)
ok(ready == true and du == 0, "cast without a learned cooldown stays ready")

-- Learn 6s, cast at 100: at 103 remaining 3, at 106 ready.
E.Learn(s, RAPTOR, 6)
ok(E.Known(s, RAPTOR) == true, "Known after Learn")
E.OnCast(s, RAPTOR, 100)
st, du, rem, ready = E.Cooldown(s, RAPTOR, 103)
ok(st == 100 and du == 6 and near(rem, 3) and ready == false, "remaining from stamp + learned duration")
st, du, rem, ready = E.Cooldown(s, RAPTOR, 106)
ok(near(rem, 0) and ready == true, "ready at start + duration")

-- Learn ignores junk and replaces.
E.Learn(s, RAPTOR, nil); E.Learn(s, RAPTOR, 0); E.Learn(s, RAPTOR, -1)
local _, du2 = E.Cooldown(s, RAPTOR, 103)
ok(du2 == 6, "Learn ignores nil/zero/negative")
E.Learn(s, RAPTOR, 5)
ok(s.learned[RAPTOR] == 5, "Learn replaces with the newer reading (future casts)")
local _, du3 = E.Cooldown(s, RAPTOR, 103)
ok(du3 == 6, "a running entry keeps the duration it started with")

-- Shared group: Aimed and Multi share 6s; casting one starts both.
E.Learn(s, AIMED, 6); E.Learn(s, MULTI, 6)
E.Link(s, { AIMED, MULTI })
E.OnCast(s, MULTI, 200)
local sa, da, ra, rda = E.Cooldown(s, AIMED, 202)
local sm, dm, rm, rdm = E.Cooldown(s, MULTI, 202)
ok(sa == 200 and near(ra, 4) and rda == false, "Aimed on cooldown from a Multi cast")
ok(sm == 200 and near(rm, 4) and rdm == false, "Multi on cooldown from its own cast")

-- Seed from a plain API reading (snapshot): later end wins.
E.Seed(s, RAPTOR, 300, 5)              -- ends 305
E.OnCast(s, RAPTOR, 302)               -- ends 307: the cast is later, keeps it
local sr = E.Cooldown(s, RAPTOR, 303)
ok(sr == 302, "a later cast stamp beats an older seed")
E.Seed(s, RAPTOR, 310, 5)              -- ends 315: later than 307
sr = E.Cooldown(s, RAPTOR, 311)
ok(sr == 310, "a later seed beats an older stamp")
E.Seed(s, RAPTOR, 0, 0)                -- "not on cooldown" reading does NOT clear (callers only seed positives)
sr = E.Cooldown(s, RAPTOR, 311)
ok(sr == 310, "a zero seed is ignored")

-- Reconcile (out of combat truth): replaces, and start == 0 clears.
E.Reconcile(s, RAPTOR, 320, 5)
local s5, d5 = E.Cooldown(s, RAPTOR, 321)
ok(s5 == 320 and d5 == 5, "Reconcile replaces the entry")
E.Reconcile(s, RAPTOR, 0, 0)
local s6, d6, r6, rd6 = E.Cooldown(s, RAPTOR, 321)
ok(s6 == 0 and rd6 == true, "Reconcile with start 0 clears the entry")
ok(E.Known(s, RAPTOR) == true, "Reconcile keeps the learned duration")

-- Group reconcile applies to every member.
E.Reconcile(s, AIMED, 400, 6)
local sm2 = E.Cooldown(s, MULTI, 401)
ok(sm2 == 400, "Reconcile on one member updates the group")

print(("ledger_engine: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
