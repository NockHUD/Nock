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
  FEIGN_DEATH = 5384,   -- icon only (the wizard's No HUD card); the cooldown is the FD row below
  -- Aspects by base id (vanilla ids; Forever/Auras.lua). A cast or aura of
  -- a higher rank resolves to the base id by name.
  ASPECT_HAWK = 13165,  -- the corner icon's "no aspect" face
  -- Pet Growl (rank 1): its localized name finds the pet-bar slot.
  GROWL = 2649,
  -- The generic eating / drinking auras (vanilla ids, name source only: every
  -- food applies its own id under one of these names). Forever/Auras.lua
  -- falls back to "Food" / "Drink" while the client has not resolved them.
  FOOD  = 433,
  DRINK = 430,
  ASPECTS = {
    [13163] = "monkey", [13165] = "hawk", [5118] = "cheetah",
    [13159] = "pack",   [13161] = "beast", [20043] = "wild",
  },
  -- Aspect ring (Forever/AspectRing.lua): slot order clockwise from straight
  -- up. Hawk and Cheetah on the vertical, the two swapped to most.
  ASPECT_RING = { "hawk", "monkey", "wild", "cheetah", "pack", "beast" },
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
  -- Lone Wolf (Marksmanship talent, new on Forever: more damage while no pet
  -- is active; the forever-hunter wiki). Spell id read from the talent tree
  -- with `/nock probe talents` (2026-09-26: node 105007, tree 1091). The
  -- no-pet warning stands down while it is talented (Forever/Warnings.lua).
  LONE_WOLF = 415370,
  -- Tracking (vanilla ids; Forever/Tracking.lua). Track spells by base id,
  -- and the wheel's slot order clockwise from straight up.
  TRACKING = {
    [1494]  = "beasts",     [19883] = "humanoids", [19884] = "undead",  [19878] = "demons",
    [19879] = "dragonkin",  [19880] = "elementals", [19882] = "giants", [19885] = "hidden",
  },
  TRACKING_RING = { "beasts", "humanoids", "undead", "demons", "dragonkin", "elementals", "giants", "hidden" },
  -- Creature type id (the client's CreatureType table: Beast 1, Dragonkin 2,
  -- Demon 3, Elemental 4, Giant 5, Undead 6, Humanoid 7; Critter 8,
  -- Mechanical 9, Not specified 10 and the rest have no Track spell) -> the
  -- Track spell that covers it.
  TRACK_BY_CREATURE_TYPE = { [1] = 1494, [2] = 19879, [3] = 19878, [4] = 19880, [5] = 19882, [6] = 19884, [7] = 19883 },
  -- English creature type names -> id: the fallback while the client offers
  -- no C_CreatureInfo list to learn the localized names from.
  CREATURE_TYPE_EN = { Beast = 1, Dragonkin = 2, Demon = 3, Elemental = 4, Giant = 5, Undead = 6, Humanoid = 7 },
  -- Improved Tracking (Survival talent: more damage to the creature types you
  -- track): spell id from the trait tree (`/nock probe tracking`, 2026-09-28).
  -- The name is the fallback lookup should the id ever miss.
  IMPROVED_TRACKING = 24293,
  IMPROVED_TRACKING_NAME = "Improved Tracking",
}
Nock.Spells = Spells

-- Tracked cooldowns, keyed by the rank-1 (base) spell id. A cast's
-- UNIT_SPELLCAST_SUCCEEDED carries the rank's own id; Forever/Cooldowns.lua
-- maps it to the base id (C_Spell.GetBaseSpell) before it touches the ledger.
-- `shared` names a shared-cooldown group: every member is its OWN catalog
-- entry and its own tile, all timed by one cooldown (Engine.Link in
-- Forever/Cooldowns.lua). Two groups exist: `arcaneHawk` (Arcane Shot, Summon
-- Hawk, Hydra Shot) and `aimedMulti` (Multi-Shot, Aimed Shot, plus the
-- AimMulti pair tile below, kept as an extra placeable option). Nothing takes
-- over another tile; the user places whichever member(s) they want.
-- A `pair` entry is ONE tile for two spells that share a cooldown (Multi on
-- the left half, Aimed on the right): `ids` in that draw order, the second
-- id is the one the range tint follows. A `texture` gives the tile its own
-- art instead: one icon, no halves, no seam.
-- Cooldowns are discovered from the client (Forever/CooldownDiscovery.lua) and
-- remembered per character (Forever/Cooldowns.lua); `lv` marks spells not
-- trained by level 20, used only for hint text.
Spells.TRACKED = {
  { key = "Raptor",   id = 2973,  name = "Raptor Strike", label = "Raptor", melee = true, cat = "Class", row = 1 },                    -- Raptor Strike (range = the melee probe)
  { key = "Arc",      id = 3044,  name = "Arcane Shot", label = "Arc", cat = "Class", row = 1, shared = "arcaneHawk" },  -- Arcane Shot; shares the arcaneHawk cooldown group with Summon Hawk and Hydra Shot
  { key = "AimMulti", ids = { 2643, 19434 }, names = { "Multi-Shot", "Aimed Shot" }, label = "Multi + Aimed", shared = "aimedMulti", cat = "Class", row = 1, -- one shared cooldown
    texture = "Interface\\AddOns\\Nock\\Media\\MultiAimed" },             -- its own art (Media/MultiAimed.tga), not a split tile
  { key = "Hawk",  id = 1293241, name = "Summon Hawk", label = "Hawk",  talent = true, cat = "Talent", row = 1, shared = "arcaneHawk" },  -- BM talent; shares the cooldown with Arcane Shot and Hydra Shot
  { key = "Hydra", id = 1293020, name = "Hydra Shot",  label = "Hydra", lv = 60, cat = "Class", row = 1, shared = "arcaneHawk" },   -- Forever id (user, 2026-09-28); shares the cooldown with Arcane Shot and Summon Hawk
  { key = "ArcHawk", ids = { 3044, 1293241 }, names = { "Arcane Shot", "Summon Hawk" }, label = "Arcane + Hawk", cat = "Class", row = 1, shared = "arcaneHawk",
    texture = "Interface\\AddOns\\Nock\\Media\\ArcaneHawk" }, -- one tile on the shared cooldown with its own art (Media/ArcaneHawk.tga); listed after the singles so their own casts keep resolving to them
  { key = "Multi", id = 2643,  name = "Multi-Shot", label = "Multi", cat = "Class", row = 1, shared = "aimedMulti" },   -- shares the cooldown with Aimed Shot and the AimMulti pair tile
  { key = "Aimed", id = 19434, name = "Aimed Shot", label = "Aimed", cat = "Class", row = 1, shared = "aimedMulti" },   -- shares the cooldown with Multi-Shot and the AimMulti pair tile
  { key = "Conc",     id = 5116,  name = "Concussive Shot", label = "Conc", cat = "Class", row = 2 },                                 -- Concussive Shot
  { key = "RF",       id = 3045,  name = "Rapid Fire", label = "RF",     lv = 26, cat = "Class", row = 1 },                                -- Rapid Fire
  { key = "FD",       id = 5384,  name = "Feign Death", label = "FD",     lv = 30, cat = "Class", row = 2 },                                 -- Feign Death
  -- Catalog additions (cooldown grid picker, 2026-09-27). Keyed by ID and name for
  -- locale-safe matching; lv marks spells not trained by level 20.
  { key = "Mongoose",  id = 1495,  name = "Mongoose Bite",      label = "Mongoose", cat = "Class",  row = 2, melee = true },
  { key = "Disengage", id = 781,   name = "Disengage",          label = "Diseng",   cat = "Class",  row = 2, melee = true },
  { key = "FrzTrap",   id = 1499,  name = "Freezing Trap",      label = "Trap",     cat = "Class",  row = 2 },
  { key = "Scare",     id = 1513,  name = "Scare Beast",        label = "Scare",    cat = "Class",  row = 2 },
  { key = "Flare",     id = 1543,  name = "Flare",              label = "Flare",    lv = 32, cat = "Class",  row = 2 },
  { key = "Tranq",     id = 19801, name = "Tranquilizing Shot", label = "Tranq",    lv = 60, cat = "Class",  row = 2 },
  { key = "BW",        id = 19574, name = "Bestial Wrath",      label = "BW",       talent = true, cat = "Talent", row = 2 },
  { key = "Intim",     id = 19577, name = "Intimidation",       label = "Intim",    talent = true, cat = "Talent", row = 2 },
  { key = "Scatter",   id = 19503, name = "Scatter Shot",       label = "Scatter",  talent = true, cat = "Talent", row = 2 },
  { key = "Deter",     id = 19263, name = "Deterrence",         label = "Deter",    talent = true, cat = "Talent", row = 2 },
  { key = "Counter",   id = 19306, name = "Counterattack",      label = "Counter",  talent = true, cat = "Talent", row = 2, melee = true },
  { key = "Sniper",    id = 1310687, name = "Sniper Shot",     label = "Sniper",  talent = true, cat = "Talent", row = 2 },               -- MM talent (Forever)
  { key = "Strider",   id = 1317257, name = "Strider Kick",    label = "Strider", talent = true, cat = "Talent", row = 2, melee = true }, -- SV talent (Forever)
  { key = "ImmoTrap",  id = 13795,   name = "Immolation Trap", label = "Immo",    cat = "Class", row = 2 },
  { key = "FrostTrap", id = 13809,   name = "Frost Trap",      label = "Frost",   lv = 28, cat = "Class", row = 2 },
  { key = "ExploTrap", id = 13813,   name = "Explosive Trap",  label = "Explo",   lv = 34, cat = "Class", row = 2 },
  { key = "Viper",     id = 3034,    name = "Viper Sting",     label = "Viper",   lv = 36, cat = "Class", row = 2 },
  -- Racials of the races that can be hunters on Forever (human, dwarf,
  -- night elf, orc, tauren, troll; the Skyborne actives are glides and
  -- regen buffs, not combat cooldowns). Forever reworked the racial kits
  -- (every race: two actives, two passives) and gave reworked ones NEW
  -- spell ids (Elune's Light is 1259799), so a racial is keyed by its
  -- NAME and resolved from the character's spellbook at login
  -- (Forever/Cooldowns.lua UpdateKnown); an id here is only a known one.
  -- `racial` marks the tile as gated on the spellbook: it shows only
  -- while the character HAS the spell, so a human never sees the night
  -- elf pair (2026-09-23). The class spells above always show, learned
  -- or not, so a level-1 grid keeps its shape (user, 2026-09-23).
  -- `buff` seeds the length of the racial's own buff: the tile lights and
  -- counts it down while it is up, and the aura read out of combat teaches
  -- the real length. `untilBroken` is a buff with no expiry (Shadowmeld: up
  -- until the hunter moves or acts). A racial with neither still lights
  -- while the aura cache finds a buff of its name out of combat.
  { key = "Elune",    id = 1259799, name = "Elune's Light",   label = "Elune",  buff = 15, racial = true, cat = "Racial", row = 1 }, -- night elf (Forever): +10% crit 15 s
  { key = "Meld",     id = 20580,   name = "Shadowmeld",      label = "Meld",   untilBroken = true, racial = true, cat = "Racial", row = 1 },  -- night elf: 10 s from the break
  { key = "Stone",    name = "Stoneform",       label = "Stone",  buff = 8, racial = true, cat = "Racial", row = 1 },     -- dwarf
  { key = "Percep",   id = 20600,   name = "Perception",      label = "Percep", buff = 20, racial = true, cat = "Racial", row = 1 }, -- human (level-1 dump 2026-09-23)
  { key = "WillSurv", id = 1259718, name = "Will to Survive", label = "Will",   racial = true, cat = "Racial", row = 1 }, -- human (Forever): removes stuns
  { key = "Fury",     name = "Blood Fury",      label = "Fury",   buff = 15, racial = true, cat = "Racial", row = 1 },    -- orc: +10% AP/SP 15 s
  { key = "Shatter",  name = "Shatter Curse",   label = "Shatter", buff = 8, racial = true, cat = "Racial", row = 1 },    -- orc (Forever): curse immunity 8 s
  { key = "Stomp",    name = "War Stomp",       label = "Stomp",  racial = true, cat = "Racial", row = 1 },               -- tauren
  { key = "Zerk",     name = "Berserking",      label = "Zerk",   buff = 10, racial = true, cat = "Racial", row = 1 },    -- troll: +10% haste 10 s
  { key = "FastRegen", name = "Fast Regeneration", label = "Regen", racial = true, cat = "Racial", row = 1 },             -- troll (Forever): 50% health
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
  { h = 32, stretch = true, keys = { "Arc", "AimMulti", "Raptor", "RF", "Elune", "Meld", "Stone", "Percep", "WillSurv", "Fury", "Shatter", "Stomp", "Zerk", "FastRegen" } },
  { h = 24, w = 32,          keys = { "Conc", "FD" } },
}

-- On Forever the shared constants point at the Forever catalog, so the React
-- grid view and the options tree list Forever entries without a change.
if Nock.Flavor and Nock.Flavor.forever then
  local C = Nock.Constants
  local tracked = {}
  for i, e in ipairs(Spells.TRACKED) do
    local t = { type = "spell" }
    for k, v in pairs(e) do t[k] = v end
    tracked[i] = t
  end
  C.TRACKED_COOLDOWNS = tracked
  C.REACT_CD_ROWS = Spells.ROWS
end
