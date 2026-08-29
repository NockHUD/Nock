-- Rotations/Profiles.lua
-- eWS-bracket → rotation profile mapping. Each entry's lower bound is exclusive:
-- profile matches when UnitRangedDamage("player") > lo. Iterated top-down,
-- so the first matching bracket wins. Bottom profile (lo = 0) is the fallback.
--
-- weights are per-spellId score overrides applied by the rotation engine.
-- Empty for substep 2; populated in substep 3 when the engine wires up.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

-- Turret notations, named for the same two reasons as WEAVE below: one
-- definition site per string, and ResolveTurret's proc ladder needs to name
-- specific rotations rather than re-derive them from brackets.
-- rotationtools nicknames: FRENCH "French", LONG_FRENCH "Long French" (the
-- Hawk-proc rotation), SKIPPING "Skipping" (RF+Hawk / RF+Lust).
local TURRET = {
  FRENCH      = "5:5:1:1",
  LONG_FRENCH = "5:6:1:1",
  ONE_ONE     = "1:1",
  SKIPPING    = "5:9:1:1",
  TWO_THREE   = "2:3",
  ONE_TWO     = "1:2",
  SKIP_ALL    = "2:5",
}

local list = {
  { name = TURRET.FRENCH,      lo = 1.83, weights = {} },
  { name = TURRET.LONG_FRENCH, lo = 1.63, weights = {} },
  { name = TURRET.ONE_ONE,     lo = 1.24, weights = {} },
  { name = TURRET.SKIPPING,    lo = 1.06, weights = {} },
  { name = TURRET.TWO_THREE,   lo = 0.85, weights = {} },
  { name = TURRET.ONE_TWO,     lo = 0.69, weights = {} },
  { name = TURRET.SKIP_ALL,    lo = 0,    weights = {} },
}

-- weaveList is populated below, once the weave notations are declared.
Nock.Profiles = {
  list = list,
}

function Nock.Profiles:ResolveByEWS(ews)
  if not ews or ews <= 0 then return nil, nil end
  for _, p in ipairs(self.list) do
    if ews > p.lo then return p.name, p end
  end
  local last = self.list[#self.list]
  return last.name, last
end

-- Known TRANSIENT haste multipliers, divided back out of the live eWS to
-- recover the static tier. Quick Shots +15% ranged AS (12s proc), Rapid Fire
-- +40% ranged AS (15s CD use), Bloodlust/Heroism +30% all haste (40s). All
-- three are exact tooltip values; rating-based procs (DST, Drums, Haste
-- Potion) have no fixed multiplier and are instead read as evidence from
-- meleeHaste, mirroring ResolveWeave's MODERATE_MELEE_HASTE trick below.
local QUICK_SHOTS_MUL = 1.15
local RAPID_FIRE_MUL  = 1.40
local LUST_MUL        = 1.30

-- meleeHaste (%) high enough to prove a heavy BOTH-haste stack (DST ~20 /
-- Haste Potion ~25 / Abacus ~16) on top of QS+RF — the "everything at once"
-- 2:5 trigger. Approximate + easy to tune in-game, like MODERATE_MELEE_HASTE.
local TURRET_EXTREME_MELEE_HASTE = 25

local function findByName(l, name)
  for i = 1, #l do
    if l[i].name == name then return l[i].name, l[i] end
  end
end

-- Proc-aware turret resolver. The bracket table alone is blind to SHORT procs:
-- at base eWS 2.174 a Quick Shots proc only reaches 1.89 — still above the
-- 1.83 French edge — so the label never flipped to Long French; on slightly
-- slower gear it flipped by accident instead. So: divide the known proc
-- multipliers back OUT of the live eWS to find the STATIC tier, and when that
-- tier is French (the no-static-haste top bracket), answer from the
-- rotationtools proc ladder:
--   5:6:1:1 (Long French) — Hawk proc
--   5:9:1:1 (Skipping)    — Rapid Fire + Hawk proc, or Rapid Fire + Bloodlust
--   2:5                   — Hawk + RF + a heavy both-haste stack on top
-- Faster STATIC tiers keep the live-bracket answer (their rotations are about
-- raw swing/GCD alignment, which the live eWS states exactly), and so does a
-- proc-less tick — bit-identical to ResolveByEWS then. Pure; LuaJIT-tested in
-- Tests/turret_resolver_test.lua.
function Nock.Profiles:ResolveTurret(ews, p, meleeHaste)
  if not ews or ews <= 0 then return nil, nil end
  local qs = p and p.quickShots
  local rf = p and p.rapidFire
  if not (qs or rf) then return self:ResolveByEWS(ews) end
  local base = ews
    * (qs and QUICK_SHOTS_MUL or 1)
    * (rf and RAPID_FIRE_MUL or 1)
    * ((p.inLust and LUST_MUL) or 1)
  local baseName = self:ResolveByEWS(base)
  if baseName == TURRET.FRENCH then
    local heavyStack = p.inLust or p.drums
      or (meleeHaste and meleeHaste >= TURRET_EXTREME_MELEE_HASTE)
    if qs and rf and heavyStack then return findByName(self.list, TURRET.SKIP_ALL) end
    if rf and (qs or p.inLust)  then return findByName(self.list, TURRET.SKIPPING) end
    if qs                       then return findByName(self.list, TURRET.LONG_FRENCH) end
    -- Rapid Fire alone has no dedicated rotationtools pattern here — fall
    -- through to the live bracket like every other unlisted combination.
  end
  return self:ResolveByEWS(ews)
end

-- WEAVE notation. Unlike the turret table this can't be a pure eWS bracket:
-- weaving is a 2-D problem (ranged AND melee haste), because RANGED-ONLY procs
-- (Rapid Fire, imp Aspect of the Hawk / Quick Shots) speed up autos but not
-- melee, while BOTH-haste sources (Bloodlust, DST, Abacus, Haste Potion, Drums)
-- speed up both. So we branch on the two ranged-only procs explicitly and read
-- the both-haste magnitude from meleeHaste (GetMeleeHaste %, gear + buffs).
-- Conditions transcribed from diziet559/rotationtools (see PLAN):
--   3:7 2w      — max haste (eWS < 0.94)
--   6:11:1:1 3w — Rapid Fire + imp Aspect + Drums
--   6:9:1:1 3w  — Rapid Fire (± imp Aspect)
--   2:2 1w      — one moderate haste source (imp Aspect, or ≥ ~one buff of melee haste)
--   5:5:1:1 3w  — "French": no haste effect (Drums-only stays here)
-- MODERATE_MELEE_HASTE is the % of melee haste that counts as a real buff —
-- above Drums-only (~5%), catching DST(~20)/Abacus(~16)/Haste Pot(~25)/Bloodlust
-- (~30). Approximate + easy to tune; verified in-game.
local MODERATE_MELEE_HASTE = 12

-- The weave notations, named rather than left as inline literals in ResolveWeave.
-- Two reasons: each string now has exactly ONE definition site, and the Options
-- panel needs to enumerate every notation to build its rename inputs — which it
-- can't do against literals buried in a function body.
local WEAVE = {
  MAXHASTE       = "3:7 2w",
  RF_IAOTH_DRUMS = "6:11:1:1 3w",
  RF             = "6:9:1:1 3w",
  MODERATE       = "2:2 1w",
  FRENCH         = "5:5:1:1 3w",
}

-- Ordered for display, matching the branch order in ResolveWeave below.
-- NOTE "5:5:1:1 3w" (weave) and "5:5:1:1" (turret) are DIFFERENT notations and
-- therefore different rename keys — don't collapse them.
Nock.Profiles.weaveList = {
  WEAVE.MAXHASTE,
  WEAVE.RF_IAOTH_DRUMS,
  WEAVE.RF,
  WEAVE.MODERATE,
  WEAVE.FRENCH,
}

function Nock.Profiles:ResolveWeave(ews, p, meleeHaste)
  if not ews or ews <= 0 or not p then return nil end
  if ews < 0.94 then return WEAVE.MAXHASTE end
  if p.rapidFire then
    if p.quickShots and p.drums then return WEAVE.RF_IAOTH_DRUMS end
    return WEAVE.RF
  end
  if p.quickShots or (meleeHaste and meleeHaste >= MODERATE_MELEE_HASTE) then
    return WEAVE.MODERATE
  end
  return WEAVE.FRENCH
end

-- Built-in notation → the user's display name for it. Blank/absent = show the
-- built-in string unchanged.
--
-- Called only from the two RENDER sites. state.rotation.* deliberately keeps the
-- real notation: the engine reasons about it, and /nock's debug dump reports it,
-- so remapping at the source would make the dump print a nickname instead of the
-- actual eWS bracket — exactly backwards for debugging.
function Nock.Profiles:DisplayName(notation)
  if not notation then return nil end
  local p = Nock.db and Nock.db.profile
  local map = p and p.rotationLabels
  local custom = map and map[notation]
  if custom and custom ~= "" then return custom end
  return notation
end

-- DisplayName's color companion: the user's color for a notation
-- (rotationLabelColors, keyed by the BUILT-IN notation like the rename map),
-- or nil for the render site's own default. Returns r,g,b,a NUMBERS rather
-- than the stored table so call sites can diff/apply without holding a
-- reference into the profile. LuaJIT-tested in Tests/profiles_display_test.lua.
function Nock.Profiles:DisplayColor(notation)
  if not notation then return nil end
  local p = Nock.db and Nock.db.profile
  local map = p and p.rotationLabelColors
  local c = map and map[notation]
  if type(c) == "table" and c[1] then
    return c[1], c[2], c[3], c[4] or 1
  end
  return nil
end
