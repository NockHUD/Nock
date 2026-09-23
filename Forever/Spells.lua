-- Forever/Spells.lua
-- Spell IDs Nock uses on WoW Forever, the tracked-cooldown catalog and the
-- cooldown-row layout. Vanilla IDs carry over (Raptor Strike 2973 measured
-- 2026-09-21); every entry below is confirmed against `/nock probe spells`
-- before it ships, and the Forever-only spells are added from that dump.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

local Spells = {
  AUTO_SHOT = 75,
  ATTACK    = 6603,    -- melee Attack (the IsCurrentSpell probe for the auto-attack toggle)
  RAPTOR_STRIKE = 2973, -- rank 1; the melee range probe (IsSpellInRange)
  HUNTERS_MARK = 1130,  -- rank 1 (ranks map to it through C_Spell.GetBaseSpell)
  HUNTERS_MARK_DURATION = 120,
  -- Aspects by base id (vanilla ids; Forever/Auras.lua). A cast of any rank
  -- resolves to the base id before the lookup.
  ASPECTS = {
    [13163] = "monkey", [13165] = "hawk", [5118] = "cheetah",
    [13159] = "pack",   [13161] = "beast", [20043] = "wild",
  },
  -- GCD probe: an instant on the GCD with no cooldown of its own (Serpent
  -- Sting rank 1). Blizzard's whitelisted GCD spell 61304 returns no cooldown
  -- data on this client, so it is not usable here.
  GCD_PROBE = 1978,
  -- Pet spells (level-10 dump, 2026-09-23). Call Pet shows as "Call <family>"
  -- (883 is vanilla's Call Pet id).
  PET = {
    MEND_PET = 136, FEED_PET = 6991, FEED_PET_EFFECT = 1539,
    REVIVE_PET = 982, DISMISS_PET = 2641, CALL_PET = 883, TAME_BEAST = 1515,
  },
}
Nock.Spells = Spells

-- Tracked cooldowns, keyed by the rank-1 (base) spell id. A cast's
-- UNIT_SPELLCAST_SUCCEEDED carries the rank's own id; Forever/Cooldowns.lua
-- maps it to the base id (C_Spell.GetBaseSpell) before it touches the ledger.
-- `shared` names a shared-cooldown group (Aimed/Multi, 6 s on Forever).
-- A `pair` entry is ONE tile for two spells that share a cooldown (Multi on
-- the left half, Aimed on the right): `ids` in that draw order, the second
-- id is the one the range tint follows.
-- `cd` is the seed cooldown in seconds so the first fight of a session has a
-- countdown before the client has been read once; the live reading replaces
-- it and is remembered per character (Forever/Cooldowns.lua).
Spells.TRACKED = {
  { key = "Raptor",   id = 2973,  label = "Raptor", cd = 6 },                                  -- Raptor Strike
  { key = "Arc",      id = 3044,  label = "Arc",    cd = 6 },                                  -- Arcane Shot
  { key = "AimMulti", ids = { 2643, 19434 }, label = "Multi + Aimed", shared = "aimedMulti", cd = 6 }, -- one shared cooldown
  { key = "Conc",     id = 5116,  label = "Conc",   cd = 12 },                                 -- Concussive Shot
  { key = "RF",       id = 3045,  label = "RF",     cd = 300 },                                -- Rapid Fire
  { key = "FD",       id = 5384,  label = "FD",     cd = 30 },                                 -- Feign Death
  { key = "Elune",    id = 1259799, label = "Elune" },                                         -- Elune's Light (Forever racial; cooldown unmeasured)
  { key = "Meld",     id = 20580, label = "Meld",   cd = 120 },                                -- Shadowmeld
}

-- Ledger buffs for the React buff row (Forever/Buffs.lua): base id, key and
-- a seed duration; the aura's real duration is learned out of combat and
-- remembered per character. Since 2026-09-23 the player's OWN short buffs
-- (Rapid Fire, Quick Shots and every other proc) are drawn by the client's
-- aura container (Forever/AuraRow.lua) with their true countdowns, so this
-- list holds only what the container cannot reach: buffs living on the pet.
-- `units` lists where the buff lands (default the player); `aura` is the
-- buff's own spell id when it differs from the cast's.
Spells.BUFFS = {
  -- Pet upkeep, cast by you, living on the pet: learned from the pet's auras
  -- out of combat, stamped from the cast in combat (spec: pet health is a
  -- sink, pet auras are never read while secret).
  { id = 136,  key = "Mend", dur = nil, units = { "pet" } },                 -- Mend Pet
  { id = 6991, key = "Feed", dur = nil, units = { "pet", "player" }, aura = 1539 }, -- Feed Pet -> Feed Pet Effect
}

-- Cooldown-row layout (same shape as Constants.REACT_CD_ROWS).
Spells.ROWS = {
  { h = 32, stretch = true, keys = { "Arc", "AimMulti", "Raptor", "RF", "Elune", "Meld" } },
  { h = 24, w = 32,          keys = { "Conc", "FD" } },
}

-- On Forever the shared constants point at the Forever catalog, so the React
-- grid view and the options tree list Forever entries without a change.
if Nock.Flavor and Nock.Flavor.forever then
  local C = Nock.Constants
  local tracked = {}
  for i, e in ipairs(Spells.TRACKED) do
    tracked[i] = { key = e.key, type = "spell", id = e.id, ids = e.ids, label = e.label, shared = e.shared, cd = e.cd }
  end
  C.TRACKED_COOLDOWNS = tracked
  C.REACT_CD_ROWS = Spells.ROWS
end
