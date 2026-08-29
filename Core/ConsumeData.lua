-- Core/ConsumeData.lua
-- Consumable ID data for the Helpers panel: per category, the buff spell IDs
-- (all ranks) that satisfy it and the item IDs that can refresh it. Pure data —
-- Modules/Helpers.lua owns all matching logic. IDs cross-checked against
-- Wowhead TBC (https://www.wowhead.com/tbc/).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

Nock.ConsumeData = {
  food = {
    -- Every food's aura is named "Well Fed"; only the spell ID says WHICH
    -- food. These are the ones a hunter would actually eat, verified against
    -- Wowhead TBC.
    buffs = {
      [33259] = true, -- +40 Attack Power, +20 Spirit  (Ravager Dog)
      [43764] = true, -- +20 Hit Rating, +20 Spirit    (Spicy Hot Talbuk)
      [33261] = true, -- +20 Agility, +20 Spirit       (Warp Burger)
      [33256] = true, -- +20 Strength, +20 Spirit      (Roasted Clefthoof)
      [33257] = true, -- +30 Stamina, +20 Spirit       (Spicy Crawdad / Fisherman's Feast)
      [33254] = true, -- +20 Stamina, +20 Spirit       (Buzzard Bites)
      [35272] = true, -- +20 Stamina, +20 Spirit       (Mok'Nathal Shortribs)
      [33265] = true, -- +8 mp5, +20 Stamina           (Blackened Sporefish)
      [33263] = true, -- +23 Spell Damage, +20 Spirit  (caster food)
      [33268] = true, -- +44 Healing, +20 Spirit       (healer food)
    },
    -- Deliberate exception to the everything-by-ID rule. TBC has dozens of
    -- Well Fed spells and this helper only asks "have you eaten?", so an ID we
    -- failed to list would nag forever at someone who IS fed — the worst thing
    -- a reminder can do. The aura name is one stable string, so it is a safe
    -- net under the ID list. (Deliberately NOT applied to any other category:
    -- elixir and scroll aura names are exactly what broke before.)
    buffNames = {
      ["Well Fed"] = true,
    },
    items = {
      [27655] = true, -- Ravager Dog        (+40 AP)  — the hunter food
      [33872] = true, -- Spicy Hot Talbuk   (+20 Hit)
      [27659] = true, -- Warp Burger        (+20 Agi)
      [27664] = true, -- Grilled Mudfish    (+20 Agi)
      [27658] = true, -- Roasted Clefthoof  (+20 Str)
      [27651] = true, -- Buzzard Bites      (+20 Stam)
      [27667] = true, -- Spicy Crawdad      (+30 Stam)
      [33052] = true, -- Fisherman's Feast  (+30 Stam)
      [31672] = true, -- Mok'Nathal Shortribs (+20 Stam)
    },
  },

  -- NOTE: the "Shattrath Flask of ..." items are deliberately NOT here. Despite
  -- the name they count as a battle AND a guardian elixir (and only activate in
  -- TK/SSC/Hyjal/BT/Sunwell), so they live in both elixir sets below. Filing
  -- them here would make the flask helper claim you're flasked while both
  -- elixir helpers still nagged.
  flask = {
    buffs = {
      -- Aura names drop the "Flask of" prefix for the three vanilla ones —
      -- another reason this is all spell-ID matched.
      [17626] = true, -- Flask of the Titans
      [17627] = true, -- Distilled Wisdom
      [17628] = true, -- Supreme Power
      [17629] = true, -- Chromatic Resistance
      [28518] = true, -- Flask of Fortification
      [28519] = true, -- Flask of Mighty Restoration
      [28520] = true, -- Flask of Relentless Assault (+120 melee/ranged AP)
      [28521] = true, -- Flask of Blinding Light
      [28540] = true, -- Flask of Pure Death
      [42735] = true, -- Chromatic Wonder
    },
    items = {
      [13510] = true, -- Flask of the Titans
      [13511] = true, -- Flask of Distilled Wisdom
      [13512] = true, -- Flask of Supreme Power
      [13513] = true, -- Flask of Chromatic Resistance
      [22851] = true, -- Flask of Fortification
      [22853] = true, -- Flask of Mighty Restoration
      [22854] = true, -- Flask of Relentless Assault
      [22861] = true, -- Flask of Blinding Light
      [22866] = true, -- Flask of Pure Death
      [33208] = true, -- Flask of Chromatic Wonder
      [32596] = true, -- Unstable Flask of the Elder
      [32597] = true, -- Unstable Flask of the Soldier
      [32598] = true, -- Unstable Flask of the Beast
      [32599] = true, -- Unstable Flask of the Bandit
      [32600] = true, -- Unstable Flask of the Physician
      [32601] = true, -- Unstable Flask of the Sorcerer
    },
  },

  -- Aura names are the SHORT forms ("Major Strength", "Agility", "Greater
  -- Armor"), not the item names — which is exactly why none of this is matched
  -- by name. The IDs below are the AURA spells, not the items' use spells.
  battleElixir = {
    buffs = {
      [28490] = true, -- Major Strength (Elixir of Major Strength)
      [28491] = true, -- Healing Power
      [28493] = true, -- Major Frost Power
      [28497] = true, -- Major Agility (+35 Agi, +20 crit)
      [28501] = true, -- Major Firepower
      [28503] = true, -- Major Shadow Power
      [33720] = true, -- Onslaught Elixir (+60 melee/ranged AP)
      [33721] = true, -- Adept's Elixir
      [33726] = true, -- Elixir of Mastery
      [38954] = true, -- Fel Strength Elixir
      [45373] = true, -- Bloodberry (Sunwell Plateau only)
      [3164]  = true, -- Strength (Elixir of Ogre's Strength)
      [7844]  = true, -- Fire Power
      [11328] = true, -- Agility
      [11334] = true, -- Greater Agility
      [11390] = true, -- Arcane Elixir
      [11405] = true, -- Elixir of the Giants
      [11406] = true, -- Elixir of Demonslaying
      [11474] = true, -- Shadow Power
      [17038] = true, -- Winterfall Firewater (+35 AP)
      [17538] = true, -- Elixir of the Mongoose (+25 Agi, +28 crit)
      [17539] = true, -- Greater Arcane Elixir
      [21920] = true, -- Frost Power
      [26276] = true, -- Greater Firepower
      -- "Shattrath Flask of ..." — a battle AND guardian elixir despite the name.
      [41608] = true, -- Relentless Assault of Shattrath
      [41609] = true, -- Fortification of Shattrath
      [41610] = true, -- Mighty Restoration of Shattrath
      [41611] = true, -- Supreme Power of Shattrath
      [46837] = true, -- Pure Death of Shattrath
      [46840] = true, -- Blinding Light of Shattrath
    },
    items = {
      [22831] = true, -- Elixir of Major Agility
      [28103] = true, -- Adept's Elixir
      [22824] = true, -- Elixir of Major Strength
      [22825] = true, -- Elixir of Healing Power
      [22827] = true, -- Elixir of Major Frost Power
      [22833] = true, -- Elixir of Major Firepower (a BATTLE elixir, not guardian)
      [28102] = true, -- Onslaught Elixir
      [31679] = true, -- Fel Strength Elixir
      [34537] = true, -- Bloodberry Elixir
      [13452] = true, -- Elixir of the Mongoose
      [9187]  = true, -- Elixir of Greater Agility
      [9206]  = true, -- Elixir of Giants
      [9155]  = true, -- Arcane Elixir
      [13454] = true, -- Greater Arcane Elixir
      [9264]  = true, -- Elixir of Shadow Power
      [13453] = true, -- Elixir of Brute Force
      [21546] = true, -- Elixir of Greater Firepower
      [12820] = true, -- Winterfall Firewater
      [9224]  = true, -- Elixir of Demonslaying
      -- Shattrath flasks fill this slot too (see the buffs note above).
      [32898] = true, -- Shattrath Flask of Fortification
      [32899] = true, -- Shattrath Flask of Mighty Restoration
      [32900] = true, -- Shattrath Flask of Supreme Power
      [32901] = true, -- Shattrath Flask of Relentless Assault
      [35716] = true, -- Shattrath Flask of Pure Death
      [35717] = true, -- Shattrath Flask of Blinding Light
    },
  },

  guardianElixir = {
    buffs = {
      [28502] = true, -- Major Armor (Elixir of Major Defense)
      [28509] = true, -- Greater Mana Regeneration (Elixir of Major Mageblood)
      [28514] = true, -- Empowerment
      [39625] = true, -- Elixir of Major Fortitude
      [39626] = true, -- Earthen Elixir
      [39627] = true, -- Elixir of Draenic Wisdom
      [39628] = true, -- Elixir of Ironskin
      -- Gift of Arthas: 11371 is the PLAYER's buff. 11374 is the disease this
      -- procs onto whoever strikes you — matching that would never fire here
      -- and would false-positive on mobs.
      [11371] = true, -- Gift of Arthas (+10 shadow resist)
      [3593]  = true, -- Elixir of Fortitude
      [11348] = true, -- Greater Armor (Elixir of Superior Defense)
      -- Zanza buffs are Guardian-slot in TBC (they were Battle in vanilla).
      [24382] = true, -- Spirit of Zanza
      [24383] = true, -- Swiftness of Zanza
      [24417] = true, -- Sheen of Zanza
      -- "Shattrath Flask of ..." fills this slot as well as the battle slot.
      [41608] = true, -- Relentless Assault of Shattrath
      [41609] = true, -- Fortification of Shattrath
      [41610] = true, -- Mighty Restoration of Shattrath
      [41611] = true, -- Supreme Power of Shattrath
      [46837] = true, -- Pure Death of Shattrath
      [46840] = true, -- Blinding Light of Shattrath
    },
    items = {
      [22840] = true, -- Elixir of Major Mageblood
      [22834] = true, -- Elixir of Major Defense
      [32062] = true, -- Elixir of Major Fortitude
      [32067] = true, -- Elixir of Draenic Wisdom
      [32068] = true, -- Elixir of Ironskin
      [32063] = true, -- Earthen Elixir
      [22848] = true, -- Elixir of Empowerment
      [20007] = true, -- Mageblood Potion
      [3825]  = true, -- Elixir of Fortitude
      [13445] = true, -- Elixir of Superior Defense
      [3389]  = true, -- Elixir of Defense
      [8951]  = true, -- Elixir of Greater Defense
      [20004] = true, -- Major Troll's Blood Potion
      [20081] = true, -- Swiftness of Zanza
      [9088]  = true, -- Gift of Arthas
      [32898] = true, -- Shattrath Flask of Fortification
      [32899] = true, -- Shattrath Flask of Mighty Restoration
      [32900] = true, -- Shattrath Flask of Supreme Power
      [32901] = true, -- Shattrath Flask of Relentless Assault
      [35716] = true, -- Shattrath Flask of Pure Death
      [35717] = true, -- Shattrath Flask of Blinding Light
    },
  },

  scrollAgility = {
    buffs = {
      [8115]  = true, -- Agility I  (Scroll of Agility)
      [8116]  = true, -- Agility II
      [8117]  = true, -- Agility III
      [12174] = true, -- Agility IV
      [33077] = true, -- Agility V (confirmed: wowhead tbc spell 33077, +20 Agi 30m)
    },
    -- Rank I has NO numeral in its item name (literally "Scroll of Agility").
    items = {
      [3012]  = true, -- Scroll of Agility      (+5 Agi)
      [1477]  = true, -- Scroll of Agility II   (+9 Agi)
      [4425]  = true, -- Scroll of Agility III  (+13 Agi)
      [10309] = true, -- Scroll of Agility IV   (+17 Agi)
      [27498] = true, -- Scroll of Agility V    (+20 Agi)
    },
  },

  scrollStrength = {
    buffs = {
      [8118]  = true, -- Strength I (Scroll of Strength)
      [8119]  = true, -- Strength II
      [8120]  = true, -- Strength III
      [12179] = true, -- Strength IV
      [33082] = true, -- Strength V
    },
    items = {
      [954]   = true, -- Scroll of Strength     (+5 Str)
      [2289]  = true, -- Scroll of Strength II  (+9 Str)
      [4426]  = true, -- Scroll of Strength III (+13 Str)
      [10310] = true, -- Scroll of Strength IV  (+17 Str)
      [27503] = true, -- Scroll of Strength V   (+20 Str)
    },
  },

  -- Pet food. The pet's aura is ALSO named "Well Fed", same string as player
  -- food — one more reason nothing here is matched by name.
  kibler = {
    buffs = {
      [43771] = true, -- Kibler's Bits    (pet: +20 Strength, +20 Spirit, 30 min)
      [33272] = true, -- Sporeling Snack  (pet: +20 Stamina, +20 Spirit, 30 min)
    },
    items = {
      [33874] = true, -- Kibler's Bits
      [27656] = true, -- Sporeling Snack
    },
  },

  demonslayer = {
    buffs = {
      [11406] = true, -- Elixir of Demonslaying
    },
    items = {
      [9224]  = true, -- Elixir of Demonslaying
    },
  },

  -- Temp weapon enchants are read via GetWeaponEnchantInfo, not auras — items
  -- only. Both stones (sharp weapons) and weightstones (blunt) belong here: a
  -- weaving hunter's main hand can be either, and the API can't tell us which
  -- enchant is applied anyway.
  sharpeningStone = {
    items = {
      [23529] = true, -- Adamantite Sharpening Stone (+12 dmg, +14 crit — sharp)
      [28421] = true, -- Adamantite Weightstone      (+12 dmg, +14 crit — blunt)
      [23528] = true, -- Fel Sharpening Stone        (+12 dmg — sharp)
      [28420] = true, -- Fel Weightstone             (+12 dmg — blunt)
      [18262] = true, -- Elemental Sharpening Stone  (+28 crit rating; tooltip
                      --   says "melee weapon", not "sharp weapon")
      [12404] = true, -- Dense Sharpening Stone      (+8 dmg — sharp)
      [12643] = true, -- Dense Weightstone           (+8 dmg — blunt)
    },
  },

  -- 23122 is the Consecrated Sharpening Stone (+100 AP vs Undead). It used to
  -- be filed as "Fel Sharpening Stone" in the regular stone list while the
  -- Undead helper looked for 12404 (which is the plain Dense stone) — the two
  -- were swapped, so the Undead reminder keyed off the wrong item entirely.
  consecratedStone = {
    items = {
      [23122] = true, -- Consecrated Sharpening Stone (+100 AP vs Undead)
    },
  },
}
