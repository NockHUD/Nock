-- Tests/turret_resolver_test.lua
-- Standalone LuaJIT tests for the proc-aware turret rotation resolver.
-- The turret label used to be a raw live-eWS bracket lookup, which is blind to
-- the 12s Quick Shots proc: at base eWS 2.174 the proc only reaches 1.89 —
-- still above the 1.83 "5:5:1:1" edge — so the label never showed "5:6:1:1"
-- (the rotationtools "Long French", THE Hawk-proc rotation). ResolveTurret
-- divides the known ranged/lust proc multipliers back out to find the STATIC
-- tier, then overlays the rotationtools proc ladder on French territory.
-- Run from the repo root: luajit Tests/turret_resolver_test.lua

local addon = {}
_G.LibStub = function() return { GetAddon = function() return addon end } end

dofile("Rotations/Profiles.lua")
local P = addon.Profiles

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- The user's dummy-measured gear: 3.0 bow, 20% haste, 15% quiver.
local BASE = 2.174
local QS, RF, LUST = 1.15, 1.40, 1.30

local function turret(ews, p, meleeHaste)
  return (P:ResolveTurret(ews, p, meleeHaste))
end

--------------------------------------------------------------------------------
-- 1. Guards and the no-proc identity
--------------------------------------------------------------------------------
ok(turret(nil, {}) == nil,  "nil eWS resolves to nil")
ok(turret(0, {})   == nil,  "zero eWS resolves to nil")
ok(turret(-1, {})  == nil,  "negative eWS resolves to nil")
ok(turret(BASE, nil) == "5:5:1:1", "nil player state falls back to the eWS bracket")

-- With no ranged proc active the resolver must be bit-identical to the old
-- raw bracket lookup, across every tier and its boundaries.
for _, ews in ipairs({ 2.4, 1.9, 1.84, 1.83, 1.7, 1.64, 1.63, 1.4, 1.25,
                       1.24, 1.1, 1.06, 0.9, 0.85, 0.7, 0.69, 0.5 }) do
  local old = P:ResolveByEWS(ews)
  ok(turret(ews, {}) == old,
     ("no procs: %.2f matches ResolveByEWS (%s)"):format(ews, tostring(old)))
end

-- Second return is the bracket entry, same shape as ResolveByEWS.
local name, entry = P:ResolveTurret(BASE, {})
ok(type(entry) == "table" and entry.name == name, "returns (name, bracket entry)")

--------------------------------------------------------------------------------
-- 2. The reported bug: Quick Shots must show Long French
--------------------------------------------------------------------------------
-- Live eWS during the proc on the user's gear: 2.174 / 1.15 = 1.89 — the old
-- lookup kept saying "5:5:1:1" because 1.89 > 1.83.
ok(turret(BASE / QS, { quickShots = true }) == "5:6:1:1",
   "QS proc at base 2.174 shows 5:6:1:1 (was stuck on 5:5:1:1)")

-- Slower gear where the old lookup flipped by ACCIDENT (live 1.65 lands in the
-- 1.63-1.83 bracket): now it flips by design, same answer.
ok(turret(1.90 / QS, { quickShots = true }) == "5:6:1:1",
   "QS proc at base 1.90 also shows 5:6:1:1")

--------------------------------------------------------------------------------
-- 3. The Rapid Fire ladder (rotationtools: Skipping = RF+Hawk or RF+Lust)
--------------------------------------------------------------------------------
ok(turret(BASE / (QS * RF), { quickShots = true, rapidFire = true }) == "5:9:1:1",
   "RF + QS shows 5:9:1:1")
ok(turret(BASE / (RF * LUST), { rapidFire = true, inLust = true }) == "5:9:1:1",
   "RF + Bloodlust shows 5:9:1:1")
ok(turret(2.4 / (RF * LUST), { rapidFire = true, inLust = true }) == "5:9:1:1",
   "RF + Bloodlust on a slower bow shows 5:9:1:1")

-- RF alone has no dedicated rotationtools pattern in French territory — the
-- live bracket answers, exactly as before this change.
ok(turret(BASE / RF, { rapidFire = true }) == P:ResolveByEWS(BASE / RF),
   "RF alone falls back to the live-eWS bracket")

--------------------------------------------------------------------------------
-- 4. The everything-stacked case
--------------------------------------------------------------------------------
ok(turret(BASE / (QS * RF * LUST),
          { quickShots = true, rapidFire = true, inLust = true }) == "2:5",
   "QS + RF + Bloodlust shows 2:5")
ok(turret(BASE / (QS * RF), { quickShots = true, rapidFire = true, drums = true })
   == "2:5", "QS + RF + Drums shows 2:5")
ok(turret(BASE / (QS * RF), { quickShots = true, rapidFire = true }, 30) == "2:5",
   "QS + RF + heavy both-haste (DST/pot via meleeHaste) shows 2:5")
ok(turret(BASE / (QS * RF), { quickShots = true, rapidFire = true }, 10) == "5:9:1:1",
   "QS + RF with only mild melee haste stays 5:9:1:1")

--------------------------------------------------------------------------------
-- 5. Outside French territory the ladder does not apply
--------------------------------------------------------------------------------
-- Static 1.70 gear sits in the 5:6:1:1 tier already; a QS proc there is
-- answered by the live bracket (1.478 -> "1:1"), not by the ladder.
ok(turret(1.70 / QS, { quickShots = true }) == P:ResolveByEWS(1.70 / QS),
   "QS on fast static gear (base 1.70) uses the live bracket")
ok(turret(1.70 / QS, { quickShots = true }) == "1:1",
   "  ... which is 1:1 at live 1.48")

-- Bloodlust alone (no ranged proc) keeps today's live-bracket behavior.
ok(turret(BASE / LUST, { inLust = true }) == P:ResolveByEWS(BASE / LUST),
   "Bloodlust alone keeps the live-bracket answer")

--------------------------------------------------------------------------------
-- 6. Survival: the Short French rotation (rotationtools' SV graph)
--------------------------------------------------------------------------------
-- "This only ever appears for survival hunters without the 20% haste out of
-- the BM talent tree." Without Serpent's Swiftness the quiver is the whole
-- static haste: 2.9 bow / 1.15 = 2.52 (the rotationtools SV gear), 3.0 bow
-- = 2.61, and the slowest a real bow gets is 2.7 / 1.15 = 2.35.
local SV29, SV30, SV27 = 2.9 / 1.15, 3.0 / 1.15, 2.7 / 1.15
local function sv(ews, p, mh) return (P:ResolveTurret(ews, p, mh, "SV")) end

-- The row exists, sits on top, and only a non-BM spec can reach it.
ok(P.list[1].name == "5:4:1:1" and P.list[1].noBmHaste == true, "5:4:1:1 is the top row, tagged noBmHaste")
ok(P:ResolveByEWS(SV29) == "5:5:1:1",        "bracket with no spec (not read yet) never answers 5:4:1:1")
ok(P:ResolveByEWS(SV29, "BM") == "5:5:1:1",  "bracket for BM never answers 5:4:1:1")
ok(P:ResolveByEWS(SV29, "SV") == "5:4:1:1",  "bracket for SV answers 5:4:1:1 at 2.52")
ok(P:ResolveByEWS(SV29, "MM") == "5:4:1:1",  "MM lacks Serpent's Swiftness too: 5:4:1:1")
ok(P:ResolveByEWS(2.5, "BM") == "5:5:1:1",   "a quiverless BM at 2.5 stays on 5:5:1:1 (reference: a Survival rotation)")
ok(turret(2.5, {}) == "5:5:1:1",             "  ... and so does ResolveTurret with the spec unread")

-- Nothing up: Short French on every real bow. Drums alone (~5%) do not move it.
ok(sv(SV29, {}) == "5:4:1:1", "SV, no procs, 2.9 bow: 5:4:1:1")
ok(sv(SV30, {}) == "5:4:1:1", "SV, no procs, 3.0 bow: 5:4:1:1")
ok(sv(SV27, {}) == "5:4:1:1", "SV, no procs, 2.7 bow: 5:4:1:1")
ok(sv(SV30 / 1.05, { drums = true }, 5) == "5:4:1:1", "SV + Drums only stays 5:4:1:1")

-- "The standard rotation for BM hunters and survival hunter with improved
-- Aspect of the Hawk or DST procs active" -> 5:5:1:1, never Long French.
ok(sv(SV29 / QS, { quickShots = true }) == "5:5:1:1", "SV + Hawk proc (2.19): 5:5:1:1, not 5:6:1:1")
ok(sv(SV30 / QS, { quickShots = true }) == "5:5:1:1", "SV + Hawk proc on a 3.0 bow (2.27, above the edge): still 5:5:1:1")
ok(sv(SV30 / 1.206, {}, 20) == "5:5:1:1",             "SV + DST proc (both-haste 20%): 5:5:1:1")
ok(sv(SV29 / 1.25, {}, 25) == "5:5:1:1",              "SV + Haste Potion: 5:5:1:1")

-- Everything else is the live bracket: Rapid Fire + Hawk is 1:1 on the SV
-- graph, Skipping needs Lust on top, and Lust alone is French territory.
ok(sv(SV29 / RF, { rapidFire = true }) == P:ResolveByEWS(SV29 / RF, "SV"), "SV + RF: live bracket")
ok(sv(SV29 / (RF * QS), { rapidFire = true, quickShots = true }) == "1:1", "SV + RF + Hawk: 1:1 (not Skipping)")
ok(sv(SV29 / (RF * LUST), { rapidFire = true, inLust = true }) == "1:1",   "SV + RF + Lust: 1:1")
ok(sv(SV29 / (RF * QS * LUST), { rapidFire = true, quickShots = true, inLust = true }) == "5:9:1:1",
   "SV + RF + Hawk + Lust: 5:9:1:1")
ok(sv(SV29 / LUST, { inLust = true }, 30) == "5:5:1:1",        "SV + Lust alone: 5:5:1:1 (bracket)")
ok(sv(SV29 / (LUST * QS), { quickShots = true, inLust = true }, 30) == "5:6:1:1",
   "SV + Lust + Hawk: live bracket (1.68 -> 5:6:1:1), the Hawk rung does not apply under Lust")
ok(sv(SV29 / (LUST * 1.2), { inLust = true }, 50) == "1:1",    "SV + Lust + DST: live bracket (1.6 -> 1:1)")

-- Static-haste gear that already sits in French territory is not Short French
-- and its Hawk proc goes to the live bracket, like a BM's fast tier does.
ok(sv(2.0, {}) == "5:5:1:1",                                   "SV with static haste (2.0): 5:5:1:1")
ok(sv(2.0 / QS, { quickShots = true }) == "5:6:1:1",           "  ... and a Hawk proc there is the live bracket (1.74)")

-- The BM path is untouched by the new argument.
ok(P:ResolveTurret(BASE / QS, { quickShots = true }, 0, "BM") == "5:6:1:1", "BM + Hawk still shows 5:6:1:1")
ok(P:ResolveTurret(BASE / QS, { quickShots = true }, 0, nil) == "5:6:1:1",  "spec unread + Hawk still shows 5:6:1:1")

print(string.format("turret_resolver: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
