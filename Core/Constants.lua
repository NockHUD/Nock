-- Core/Constants.lua
-- Shared visual + numeric constants: colors, dimensions, fonts, slot counts.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

-- Sapper Charge cascade, hoisted out of the table literal so the tracked-cooldown
-- slot below and Modules/Warnings.lua + Modules/SapperTracker.lua can all share
-- one list instead of keeping three copies of the same two IDs. Super Sapper
-- Charge (23827) is preferred; Goblin Sapper Charge (10646) is the fallback.
local SAPPER_ITEMS = { 23827, 10646 }

Nock.Constants = {
  COLORS = {
    BG             = {0.00, 0.00, 0.00, 0.85},
    BG_LOCKED      = {0.00, 0.00, 0.00, 0.85},
    BORDER         = {0.00, 0.00, 0.00, 1.00},
    BORDER_UNLOCK  = {0.20, 0.80, 0.40, 1.00},
    CAST_BAR       = {0.40, 0.70, 1.00, 1.00},
    RANGED_SWING   = {1.00, 0.84, 0.00, 1.00},
    MELEE_SWING    = {1.00, 1.00, 1.00, 1.00},  -- white
    GCD            = {0.65, 0.45, 1.00, 1.00},  -- light purple GCD sweep (distinct from cast-bar blue)
    NEXT_HIGHLIGHT = {0.00, 1.00, 0.40, 1.00},
    PROC_GLOW      = {0.00, 0.90, 0.90, 1.00},
    READY          = {1.00, 1.00, 1.00, 1.00},
    ON_COOLDOWN    = {0.40, 0.40, 0.40, 1.00},
    WARN_RED       = {0.90, 0.20, 0.20, 1.00},
    WARN_AMBER     = {1.00, 0.65, 0.00, 1.00},
    WARN_BLUE      = {0.30, 0.60, 1.00, 1.00},
    ZONE_INACTIVE_BG     = {0.18, 0.18, 0.18, 0.85},
    ZONE_INACTIVE_BORDER = {0.30, 0.30, 0.30, 1.00},
    ZONE_ACTIVE_BG       = {0.20, 0.80, 0.30, 0.85},
    ZONE_ACTIVE_BORDER   = {0.30, 1.00, 0.40, 1.00},
    TEXT           = {1.00, 1.00, 1.00, 1.00},
    TEXT_DIM       = {0.70, 0.70, 0.70, 1.00},
    MANA           = {0.20, 0.40, 0.95, 1.00},  -- mana-bar fill fallback
  },
  DIM = {
    HUD_WIDTH       = 280,
    HUD_HEIGHT      = 220,  -- height auto-snaps via HUD:LayoutChildren; this is a fallback only.

    -- Layout grid. Uniform 4px to keep everything on a tight grid like the
    -- reference WA. OUTER_PAD = edge gutter, ROW_GAP = between sections,
    -- INNER_GAP = within a section (icon-to-icon, bar-to-bar). PAD = legacy alias.
    OUTER_PAD       = 4,
    ROW_GAP         = 4,
    INNER_GAP       = 4,
    PAD             = 4,

    -- Rotation row: 6 icons at 42px fills inner width exactly (6*42 + 5*4 = 272).
    -- Cooldown rows: 7 icons at 35px is just under inner width (7*35 + 6*4 = 269),
    -- centered. Smaller than rotation icons so 7 fit per row.
    ROTATION_ICON   = 42,
    COOLDOWN_ICON   = 35,

    CAST_BAR_H      = 22,
    RANGED_BAR_H    = 20,   -- doubled to fit the rotation/step indicator inside
    MELEE_BAR_H     = 8,
    GCD_BAR_H       = 4,    -- thin global-cooldown sweep sitting just above the auto-shot bar (profile.gcdBarHeight overrides)
    GCD_BAR_GAP     = 2,    -- tight gap between the GCD bar and the auto-shot bar so they read as attached
    MANA_BAR_H      = 14,    -- mana bar (sits directly above the range finder)
    RANGE_SQUARE_H  = 16,    -- range finder bar height
    INFO_ROW_H      = 16,    -- bottom-most slim row: speed left, arrows right
    PET_PANEL_ICON  = 30,    -- icon size in the pet-status side panel (slightly smaller than cooldown grid)
    STEP_INDICATOR_W = 44,
    SHOT_BARS_H     = 28,    -- "Shot Bars" scrolling timeline row (Fluffy-style)
    SHOT_BARS_MELEE_H = 4,   -- melee/weave strip inside the Shot Bars row (profile.shotBarsMeleeHeight overrides)
    SHOPPING_ROW_H  = 18,    -- one missing-item row in the shopping-list panel
    REPAIR_BAR_H    = 14,    -- "needs repair" strip glued under the HUD bottom
    WARN_ROW_H      = 16,
    WARN_ICON_SIZE  = 44,
    WARN_ICON_GAP   = 8,
    WARN_TOP_FRACTION = 0.25,
    ROW_SPACING     = 4,
  },
  FONT = {
    PATH         = "Fonts\\FRIZQT__.TTF",
    SIZE_OVERLAY = 10,
    SIZE_WARNING = 11,
  },
  ROTATION_SLOTS = 6,
  -- Default cooldown-grid shape. The grid is now profile-driven
  -- (profile.cooldownCols / cooldownRows / cooldownOrder / cooldownDisabled /
  -- cooldownCustom); these are only the out-of-the-box defaults so a fresh
  -- profile reproduces the original 2x7 grid exactly. COOLDOWN_ROW_SIZES is
  -- kept for back-compat callers but is no longer authoritative.
  COOLDOWN_SLOTS = 14,
  COOLDOWN_COLS  = 7,
  COOLDOWN_ROWS  = 2,
  COOLDOWN_ROW_SIZES = { 7, 7 },
  RANGE_ZONES    = { "TOO_CLOSE", "SWEET", "TOO_FAR", "OUT" },
  WARNING_SLOTS  = 12,

  SpellID = {
    AUTO_SHOT     = 75,
    WING_CLIP     = 2974,
    RAPID_FIRE    = 3045,
    BESTIAL_WRATH = 19574,
    READINESS     = 23989,
    KILL_COMMAND  = 34026,
    KILL_COMMAND_PROC = 34027,  -- the "Kill Command" buff a ranged crit puts on the hunter
    TRANQ_SHOT    = 19801,
    MISDIRECTION  = 34477,
    FEIGN_DEATH   = 5384,

    -- Teron Gorefiend (Black Temple) casts this on a random raid member every
    -- 30-35s: 1.5s cast, 55s debuff, then you die and become a ghost. Feign
    -- Death DURING the cast makes it fail outright, which is why Nock warns on
    -- the cast rather than on the debuff. Wowhead TBC spell=40251.
    SHADOW_OF_DEATH = 40251,

    -- Archimonde (Mount Hyjal) casts this on a random raid member: 1.7s cast,
    -- 3000 nature damage plus a knockback in a 13yd radius. The knockback is
    -- what kills — Feign Death saves you from the landing. Same reason as
    -- above, Nock warns on the cast. Wowhead TBC spell=32014.
    AIR_BURST = 32014,

    -- Anetheron (Mount Hyjal) casts this every 19.5-45s: instant, puts three
    -- random raid members to sleep for 10s, breaks on damage. A Sulfuron
    -- Slammer's self-damage tick is the hunter's way out — see
    -- Modules/SlammerEngine.lua. Wowhead TBC spell=31298.
    SLEEP_ANETHERON = 31298,
    -- The Sulfuron Slammer's aura: 6s, 4 fire damage to yourself every 3s.
    -- Wowhead TBC spell=50986.
    SULFURON_SLAMMER = 50986,
    -- The two engineering teleporter trinkets' use-effect casts, as fallbacks
    -- for when the item's own use effect (GetItemSpell) is not cached yet.
    -- Wowhead TBC: item=30542 -> spell=36890, item=30544 -> spell=36941.
    RIPPER_AREA52        = 36890,
    TRANSPORTER_TOSHLEY  = 36941,
    -- Engineering specialization passives, for the ripper card's per-spec
    -- debuff-reset advice. Wowhead TBC spell=20219 / spell=20222.
    GNOMISH_ENGINEER     = 20219,
    GOBLIN_ENGINEER      = 20222,

    -- Beast Training (the craft-frame "profession"). Used ONLY to resolve the
    -- LOCALIZED name via GetSpellInfo as a fallback pet-training check when
    -- CraftIsPetTraining() is absent — never compared raw.
    BEAST_TRAINING = 5149,

    -- Pet Growl (rank 1; base name/icon are rank-independent). Used only to
    -- resolve the LOCALIZED name/icon via GetSpellInfo and to match the Growl
    -- slot on the pet action bar — never compared raw.
    GROWL         = 2649,

    -- Dazed — the movement slow you get hit with from behind while moving; it
    -- also locks you out of casting. Used ONLY to resolve the LOCALIZED name via
    -- GetSpellInfo: several mob abilities apply an aura named "Dazed" under
    -- different spell IDs, so the scan matches by name and never compares this
    -- ID raw (same convention as GROWL / the aspects).
    DAZED         = 1604,

    -- Steam Tonk Controller's transform aura. Used to resolve the LOCALIZED
    -- aura name and as a secondary ID match in the player buff scan; the
    -- primary match is by name, resolved from the item at runtime.
    STEAM_TONK    = 45440,

    -- Devilsaur Tooth's pet buff: the pet's next attack that can crit, will.
    -- No duration — it sits on the pet until a crit consumes it. Used ONLY to
    -- resolve the LOCALIZED name via GetSpellInfo for the pet buff scan —
    -- never compared raw. Wowhead TBC spell=24353.
    PRIMAL_INSTINCT = 24353,

    -- Rotation abilities (TBC max ranks)
    STEADY_SHOT   = 34120,
    MULTI_SHOT    = 27021,
    ARCANE_SHOT   = 27019,
    RAPTOR_STRIKE = 27014,
    ATTACK        = 6603,     -- melee auto-attack: the white hit's icon on the practice stage

    -- Aspects (TBC max ranks)
    ASPECT_HAWK    = 27044,
    ASPECT_MONKEY  = 13163,
    ASPECT_CHEETAH = 5118,
    ASPECT_PACK    = 13159,
    ASPECT_WILD    = 27045,
    ASPECT_VIPER   = 34074,
    ASPECT_BEAST   = 13161,

    -- Lust + group haste
    BLOODLUST       = 2825,
    HEROISM         = 32182,
    DRUMS_OF_BATTLE = 35476,

    -- The 10-minute "already lusted" debuffs Bloodlust/Heroism leave behind
    -- (Horde/Alliance variants). Detected by Modules/Auras.lua's player
    -- debuff pass (ID first, localized-name fallback) into
    -- state.player.sated; they drive the DO NOT RELEASE banner after a wipe.
    -- Wowhead TBC spell=57724 / spell=57723.
    SATED      = 57724,
    EXHAUSTION = 57723,

    -- RANGED-ONLY haste procs used to pick the weave AND turret rotation
    -- notations. These speed up auto shots but not melee, so they don't show
    -- in GetMeleeHaste() and must be detected explicitly. (Rating-based
    -- both-haste sources like DST/Abacus/Haste Potion are caught via the
    -- melee-haste value; Bloodlust/Heroism additionally publish the exact
    -- state.player.inLust flag, which the turret resolver divides back out.)
    -- QUICK_SHOTS = Improved Aspect of the Hawk proc (+15% ranged AS, 12s).
    QUICK_SHOTS = 6150,

    -- Hunter's Mark (max rank; scan by name to catch all ranks)
    HUNTERS_MARK = 27322,
    SCATTER_SHOT = 19503,  -- range probe for the React range-check overlay (talent-stretched by Hawk Eye)

    -- Shaman totems tracked by the totem panel. IDs used only to resolve the
    -- LOCALIZED name/icon via GetSpellInfo (rank-independent base name), never
    -- compared raw. Windfury Totem in TBC is a temporary MAIN-HAND WEAPON
    -- enchant on party members (not a player aura) — detected via the
    -- enchant ID (4th return of GetWeaponEnchantInfo), see WF_ENCHANT_IDS.
    WINDFURY_TOTEM    = 8512,
    STRENGTH_OF_EARTH = 31634,
    -- Grace of Air Totem (rank 1; base name/icon are rank-independent). Used
    -- only to resolve the air-aura icon for the twist slot + the test sim;
    -- real detection is name-based via AIR_TOTEM_BUFFS["Grace of Air"].
    GRACE_OF_AIR      = 8835,
  },

  -- Built-in "wrong trinket" family: every TBC-era PvP escape trinket, both
  -- factions, all class variants. The wrong-trinket warning UNIONS this set
  -- with the user's editable CSV (profile.warnWrongTrinketIds) in
  -- Warnings:RebuildIdSets — shipping it as a built-in instead of a default
  -- string means users who edited their CSV still get the family (AceDB never
  -- re-delivers a changed default to an edited field). Item IDs probed off
  -- Wowhead TBC's XML endpoint 2026-08-18; the interleaved non-trinket IDs
  -- (18835-18844 weapons etc.) are deliberately absent. Guarded by
  -- Tests/wrong_trinket_ids_test.lua.
  WRONG_TRINKET_IDS = {
    -- Insignia of the Horde (classic per-class versions)
    [18834] = true, [18845] = true, [18846] = true, [18849] = true,
    [18850] = true, [18851] = true, [18852] = true, [18853] = true,
    -- Insignia of the Alliance (classic per-class versions)
    [18854] = true, [18856] = true, [18857] = true, [18858] = true,
    [18859] = true, [18862] = true, [18863] = true, [18864] = true,
    -- Medallion of the Alliance (TBC per-class + generic 37864)
    [28234] = true, [28235] = true, [28236] = true, [28237] = true,
    [28238] = true, [37864] = true,
    -- Medallion of the Horde (TBC per-class + generic 37865)
    [28239] = true, [28240] = true, [28241] = true, [28242] = true,
    [28243] = true, [37865] = true,
  },

  -- Creature IDs, parsed out of a unit's GUID (field 6 of
  -- "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>"). Used to confirm
  -- that a nameplate or target unit really is the boss before trusting what it
  -- is looking at.
  NpcID = {
    TERON_GOREFIEND = 22871,   -- Black Temple. Wowhead TBC npc=22871.
    ARCHIMONDE      = 17968,   -- Mount Hyjal. Wowhead TBC npc=17968.
    ANETHERON       = 17808,   -- Mount Hyjal. Wowhead TBC npc=17808.
    MOTHER_SHAHRAZ  = 22947,   -- Black Temple. Wowhead TBC npc=22947.
  },

  -- The Black Temple quest neck: Medallion of Karabor (32649) and its upgrade
  -- Blessed Medallion of Karabor (32757). Worn, it teleports you to the raid
  -- entrance — and then it is easy to forget around your neck. Warnings'
  -- karaborNeck check flags either while inside BT (map id 564), except at
  -- Mother Shahraz, where its Shadow Resistance is the point.
  KARABOR_NECK_ITEMS  = { [32649] = true, [32757] = true },
  BLACK_TEMPLE_MAP_ID = 564,

  -- Windfury Totem temp-enchant IDs by rank (Ranks 1-5), as returned in the
  -- 4th value of GetWeaponEnchantInfo() when the totem buffs your main hand.
  -- Matching the enchant ID is locale-proof and unambiguous (every sharpening
  -- stone / oil / poison has its own distinct ID, so no false positives) —
  -- strictly better than scanning the weapon tooltip for the localized name.
  -- Sourced from the "WF Now! v2" WeakAura's verified enchant-ID map.
  WF_ENCHANT_IDS = { [563] = true, [564] = true, [1783] = true, [2638] = true, [2639] = true },

  -- Drums "players in range" badge (top-left of the Drums cooldown icon).
  -- Auto-detects which drum is in play: if the greater-drums item is in bags
  -- → 40 yd scan (UnitInRange), otherwise Drums of Battle → ~8 yd (no exact
  -- native probe; nearest band is CheckInteractDistance idx 3 ≈ 10 yd).
  DRUMS = {
    BATTLE_ITEM  = 29529,    -- Drums of Battle (Leatherworking), ~8 yd
    GREATER_ITEM = 185848,   -- "greater drums", ~40 yd
    GREATER_BUFF = 351355,   -- greater-drums effect/buff id (reference)
  },

  -- Weave Bind (Modules/WeaveBind.lua) default press/release macro bodies.
  -- The profile carries user-editable copies; these are the shipped defaults
  -- and the source for the "Restore default macros" button. English names by
  -- macro convention — this is plain user-editable macro text, not module
  -- logic (SpellID.RAPTOR_STRIKE above is the ID-based reference). Firing on
  -- both key edges is handled by the secure button's useOnKeyDown attribute
  -- (see WeaveBind.lua header) — no /console CVar lines needed here.
  --
  -- "Weave on the way out" bodies (competitive-weaver practice, after the
  -- Grounded preset the user verified in-game):
  --   /use Snowball          — first press line (kept in the shipped default
  --                            after in-game testing). Instant, off-GCD poke;
  --                            forces the server to re-evaluate the attack
  --                            state immediately instead of waiting for its
  --                            ~0.5s melee-retry pulse (the "luck regime"
  --                            /nock weavelog full exposed).
  --   /click MovePadBackward — OPTIONAL pair the user may add to BOTH bodies,
  --                            no longer shipped in the defaults: MovePad
  --                            buttons are toggling CheckButtons (verified in
  --                            Blizzard_MovePad source), so the press-edge
  --                            click STARTS backpedaling and the release-edge
  --                            click STOPS it — you back out for exactly the
  --                            hold duration. When a macro references it,
  --                            WeaveBind loads the pad on demand, hints if
  --                            it's missing, and watchdogs a stuck toggle
  --                            (lost release edge = infinite backpedal).
  --   [target=pettarget]     — NOT [@pettarget]: @unit conditionals silently
  --                            fail in secure macrotext on this client.
  -- Release re-arms the ranged auto explicitly: /startattack on the press edge
  -- switches the auto-attack state from Auto Shot to melee, and only
  -- "/cast !Auto Shot" switches it back ("!" = turn on, never toggle off).
  WEAVE_BIND_MACRO_DOWN = "/use Snowball\n/stopcasting\n/cast Raptor Strike\n/startattack",
  WEAVE_BIND_MACRO_UP   = "/cast [target=pettarget,exists] Kill Command\n/cast !Auto Shot",
  -- The optional auto-backpedal pair described above. Appended to BOTH bodies
  -- (press starts backing out, release stops it) by the onboarding wizard's
  -- "Clever" macro choice; kept here so no module hardcodes the macro text.
  WEAVE_BIND_MOVEPAD_LINE = "/click MovePadBackward",
  -- The off-GCD poke, as its own line: the setup wizard's extras page and the
  -- options builder add and remove it, and Core/WeaveMacro.lua reads the item
  -- name back out of it rather than spelling "Snowball" a second time.
  WEAVE_BIND_SNOWBALL_LINE = "/use Snowball",
  -- Snowball (item 17202): consumed if the user adds /use Snowball to their
  -- press macro; weavelog's DOWN line then reports the remaining count so
  -- running dry is visible in the log.
  SNOWBALL_ITEM = 17202,

  -- Mailbox module (Modules/Mailbox.lua): snowball mail logistics. One mail
  -- operation in flight at a time, gated on C_Mail.IsCommandPending().
  MAIL_ATTACH_MAX       = 12,    -- fallback when ATTACHMENTS_MAX_SEND is absent
  MAIL_STEP_SETTLE      = 0.3,   -- pause between server ops (Postal's safe rate)
  MAIL_OP_TIMEOUT       = 10,    -- seconds without server confirm -> abort run
  MAIL_EXPIRY_WARN_DAYS = 5,     -- report turns red below this many days left

  -- React-mode buff rows (UI/Frame_ReactBuffs.lua): ports of the reference
  -- WA pack's "Important Buffs" and "Dynamic utility buffs" icon sections.
  REACT_BUFFS = {
    -- "Important" row (haste/burst procs): player buffs matched by EXACT
    -- spell ID — the reference WA's lists, verbatim.
    IMPORTANT_IDS = {
      [2825]  = true, [32182] = true,   -- Bloodlust / Heroism
      [35476] = true,                   -- Drums of Battle
      [3045]  = true,                   -- Rapid Fire
      [6150]  = true,                   -- Quick Shots (Improved Hawk proc)
      [34692] = true,                   -- The Beast Within
      [28507] = true,                   -- Haste Potion
      -- burst racial buffs
      [20572] = true,                   -- Blood Fury
      [20554] = true,                   -- Berserking
      [20594] = true,                   -- Stoneform
      [20580] = true,                   -- Shadowmeld
      -- trinket use/proc buffs (reference WA list)
      [35166] = true, [33649] = true, [33807] = true, [33667] = true,
      [34775] = true, [42084] = true, [40477] = true, [40487] = true,
      [43716] = true, [45040] = true,
      [37482] = true,                   -- "4P T3.5" set proc (reference list)
    },
    -- Utility-row auras matched by LOCALIZED NAME (rank-independent, Nock
    -- convention) — the ids below only resolve the name/icon via
    -- GetSpellInfo, never compared raw. Feign Death / Misdirection /
    -- Grace of Air resolve from SpellID above.
    MEND_PET          = 27046,
    FEED_PET          = 1539,   -- "Feed Pet Effect"
    INTIMIDATION_BUFF = 24394,  -- the pet's stun buff (same name as the talent)
    FRENZY            = 19615,  -- the pet's Frenzy proc ("Frenzy Effect", 8 s; matched by name AND this id)
    FRENZY_TALENT     = 19621,  -- Frenzy talent rank 1 (BM tab) — name resolution for the talented check only
    LOTP              = 24932,  -- Leader of the Pack aura
    LOTP_IMP          = 34299,  -- Improved LotP heal proc (counts as present)
  },

  TICK_HZ          = 30,
  AUTO_SHOT_CAST   = 0.5,
  -- The client's re-check cadence after /cast !Auto Shot while the swing is
  -- still recharging (Aerthax, Classic Hunter Discord 2022-04-11): the shot
  -- fires at the first press-anchored check AFTER swing-ready, so a release
  -- costs 0..RETRY_PULSE seconds depending on phase. Seed value — the weavelog
  -- predicted/measured lines exist to correct it if Anniversary's pulse
  -- differs. Consumed only through Nock.ReleaseCost/ReleaseFreeIn.
  RETRY_PULSE      = 0.5,
  GCD_BASE         = 1.5,

  -- Practice mode (Modules/Practice*.lua). Sources in the spec's Sim model table.
  PRACTICE = {
    QUEUE_WINDOW = 0.4,   -- spell-queue tolerance (wowsims MaxSpellQueueWindow)
    REACTION     = 0.15,  -- seconds of idle GCD before LATE
    CLIP_MIN     = 0.03,  -- auto delay that counts as a clip (SwingTimer's clean-cycle bound)
    TOAST_SEC    = 0.8,
    START_DISTANCE = 7,   -- yards to the virtual target at the pull (wowsims default)
    -- Ability cooldowns the sim models. The pure files (PracticeEngine,
    -- PracticeModel) never read Nock.Constants — these are passed in via cfg/h.
    MULTI_CD        = 10,   -- Multi-Shot, seconds
    ARCANE_CD_BASE  = 6,    -- Arcane Shot, seconds before Improved Arcane Shot
    ARCANE_CD_PER_PT = 0.2, -- seconds shaved per Improved Arcane Shot point
    RAPTOR_CD       = 6,    -- Raptor Strike, seconds
    -- Weave drill (phase 3). Distances are yards on the sim's virtual target.
    MELEE_RETRY_PULSE = 0.5,  -- server melee re-check after stepping in (a Snowball poke bypasses it)
    LEG_MAX      = 0.4,   -- seconds a single weave leg may take before WEAVE SLOW
    STEP_TIME    = 0.3,   -- key-only footwork: seconds the engine takes to step in/out
    OPP_MIN      = 0.4,   -- weave window must stay open this long before a miss counts
    REARM_MIN    = 0.05,  -- re-arm cost below this is noise, not a REARM verdict
    -- Phase 5: the cooldowns the sim models as off-GCD presses, in seconds, and
    -- the Kill Command crit window. Same reason as the block above — the pure
    -- files never read Nock.Constants, so these travel in cfg.cooldowns.
    KC_WINDOW    = 5,     -- seconds a crit keeps Kill Command usable
    KC_CD        = 5,     -- Kill Command's own cooldown
    RF_CD        = 300,   -- Rapid Fire
    SPEC_CD      = 120,   -- spec cooldown (BM: Bestial Wrath)
    TRINKET_CD   = 120,   -- either on-use trinket slot
    DRUMS_CD     = 120,   -- Drums of Battle
    POT_CD       = 120,   -- Haste Potion
    -- Haste Potion, the item behind the sim's `pot` action and the live grid's
    -- Haste slot (TRACKED_COOLDOWNS key "Haste").
    HASTE_POT_ITEM = 22838,
    -- Dragonspine Trophy, the item behind the sim's `DST` proc: its own icon
    -- on the stage (it wore the Quick Shots one, user 2026-08-27).
    DST_ITEM = 28830,
    MELEE_RANGE  = 5,     -- in melee (Wing Clip reach)
    SHOOT_MIN    = 5,     -- Auto Shot minimum range = melee reach: no dead sliver between them (a
                          -- 5.01 floor left a 0.01yd GAP the bar painted PERFECT where a wind-up stuck forever)
    SHOOT_MAX    = 35,    -- Auto Shot maximum range (past it the shoot probe fails: OUT)
    WEAVE_RING   = 7,     -- one step from melee (IsItemInRange 8149)
  },

  -- Steam Tonk Controller. The item is the source of truth for the transform
  -- aura's localized name (resolved via GetItemSpell in Modules/Auras.lua);
  -- Modules/Warnings.lua and the tracked-cooldown tables reference the same ID.
  STEAM_TONK_ITEM  = 22728,
  -- Sulfuron Slammer (Midsummer vendor drink, stacks of 10): the item the
  -- Anetheron button drinks. Wowhead TBC item=38466.
  SULFURON_SLAMMER_ITEM = 38466,
  -- Anetheron's ENCOUNTER_START id (BigWigs / DBM agree on 619).
  ANETHERON_ENCOUNTER   = 619,
  -- The two engineering teleporter trinkets whose long cast rolls a side
  -- effect: Dimensional Ripper - Area 52 and Ultrasafe Transporter: Toshley's
  -- Station. Closing the client a second before the cast ends keeps the side
  -- effect and skips the trip (Modules/RipperWatch.lua). Wowhead TBC
  -- item=30542 / item=30544.
  RIPPER_ITEMS = { 30542, 30544 },

  -- Gnomish World Enlarger: BoP, gnomish-engineering-only craft — owning one
  -- is proof of the specialization whatever the spell APIs say. Wowhead TBC
  -- item=18660.
  WORLD_ENLARGER_ITEM = 18660,

  -- Devilsaur Tooth (hunter quest trinket, The Green Drake). Use: loads a
  -- guaranteed crit onto the pet (SpellID.PRIMAL_INSTINCT). 2-min cooldown.
  DEVILSAUR_TOOTH_ITEM = 19992,

  -- Sapper Charges (engineering explosives). Both charges share ONE 5-minute
  -- Explosives cooldown, so a Super use blocks a Goblin use and vice versa.
  -- SPELL_IDS is a cold-start fallback for combat-log matching only: the real
  -- match set is resolved at runtime from GetItemSpell(ITEMS) so it stays
  -- correct if this client logs a different one of the four DB entries.
  SAPPER = {
    ITEMS     = SAPPER_ITEMS,
    CD        = 300,
    SPELL_IDS = { 30486, 30560, 13241, 12760 },
  },

  -- Misdirection's threat-redirect window. Modules/Misdirection stamps casts
  -- with it; Modules/SapperTracker decides from it whether a sapper landed
  -- inside somebody's MD. One definition so the two can't drift.
  MD_EFFECT_SEC = 30,
  MD_CD_SEC     = 120,

  -- Settling interval before the Steam Tonk transform is cancelled, and the
  -- hard floor under it. 0.40s is what the community WeakAura this is modelled
  -- on has run, but 0.40 is a gamble: it sits close enough to the transform
  -- landing that a bad frame or a latency spike re-welds the player, and a weld
  -- costs a raid attempt. 0.50 is the shipped default AND the minimum the
  -- slider will accept -- there is no upside to shaving 100ms off an escape
  -- hatch. Config/Defaults.lua seeds from DELAY, Core:MigrateProfile raises
  -- stored values below MIN, and Nock.TonkCancelDelay() is the runtime read.
  TONK_CANCEL_DELAY = 0.50,
  TONK_CANCEL_MIN   = 0.50,

  LATENCY_POLL_SEC = 5,
  -- TBC Feign Death feign state lasts up to 6 min. Used as the cast-bar
  -- countdown fallback when the aura returns no duration (and for the
  -- immediate kickstart before the first UNIT_AURA refines the real timer).
  FEIGN_DEATH_DURATION = 360,

  -- Flat (non-weapon, non-AP) damage component per ability, TBC max rank.
  -- Per-rank flat bonus damage, from Wowhead's TBC database (the same table
  -- Fluffy Hunter Bars uses). These feed the
  -- Shot Bars DPS-equilibrium clip math (ShotPredictor). Absolute accuracy
  -- barely moves the equilibrium boundary (it depends on dps *ratios*), so
  -- these are the TBC top-rank tooltip flats and are intentionally tunable.
  ABILITY_FLAT = {
    STEADY = 150,  -- Steady Shot (Rank highest, 34120) flat add
    MULTI  = 205,  -- Multi-Shot   (Rank 7, 27021) flat add
    ARCANE = 273,  -- Arcane Shot  (Rank 9, 27019) flat add
    RAPTOR = 156,  -- Raptor Strike (Rank 8, 27014) flat add
  },

  -- Built-in cooldown catalog ("the 14 out of the box"). This is now just the
  -- seed list: the engine tracks ALL of these (plus user-added custom entries)
  -- so dependent systems never break, while the grid renders the user's
  -- enabled + ordered subset (profile.cooldownOrder / cooldownDisabled), capped
  -- to profile.cooldownCols * cooldownRows. Entries flagged `trackedOnly` are
  -- never grid-eligible — they exist purely for the rotation/clip engines and
  -- must keep their keys (MS, Arc). Likewise the engine always tracks the
  -- catalog so RF/Haste/T1/T2 (lust-CD warning) and Drums (range badge) work
  -- even if the user hides them.
  TRACKED_COOLDOWNS = {
    { key = "Drums", type = "item",      id = 29529, useCharges = true, label = "Drums" },  -- Drums of Battle (4 charges per item)
    { key = "Tonk",  type = "item",      id = 22728, useCharges = true, label = "Tonk"  },  -- Steam Tonk Controller
    { key = "Conc",  type = "spell",     id = 27634,            label = "Conc"  },  -- Concussive Shot
    { key = "Viper", type = "spell",     id = 27018,            label = "Viper" },  -- Viper Sting
    -- Spec slot: BM=Bestial Wrath, MM=Silencing Shot, SV=Readiness
    { key = "Spec",  type = "specSpell",
      bySpec = { [1] = 19574, [2] = 34490, [3] = 23989 },       label = "Spec"  },
    { key = "RF",    type = "spell",     id = 3045,             label = "RF"    },  -- Rapid Fire
    { key = "T1",    type = "inventory", slot = 13,             label = "T1"    },  -- top trinket
    -- Sapper slot: prefers Super Sapper Charge (23827), falls back to Goblin
    -- Sapper Charge (10646). Greys out when none in bags.
    { key = "Sapper", type = "altItem",  ids = SAPPER_ITEMS,     label = "Sap"   },
    { key = "Intim",  type = "spell",    id = 19577,            label = "Intim" },  -- Intimidation (BM)
    { key = "Trap",   type = "spell",    id = 14311,            label = "Trap"  },  -- Freezing Trap
    { key = "FD",     type = "spell",    id = 5384,             label = "FD"    },  -- Feign Death
    { key = "Flare",  type = "spell",    id = 1543,             label = "Flare" },  -- Flare
    { key = "Haste",  type = "item",     id = 22838,            label = "Hst"   },  -- Haste Potion
    { key = "T2",     type = "inventory", slot = 14,            label = "T2"    },  -- bottom trinket

    -- Tracked-only (never grid-eligible) — rotation/clip engines read these.
    { key = "MS",    type = "spell",     id = 27021,            label = "MS",   trackedOnly = true },
    { key = "Arc",   type = "spell",     id = 27019,            label = "Arc",  trackedOnly = true },

    -- Tracked-only entries for the React grid (REACT_CD_ROWS below). MUST stay
    -- trackedOnly: anything grid-eligible here would appear in every existing
    -- user's CLASSIC grid (gridEligibleCatalog injects the whole catalog).
    -- ManaPot = Super Mana Potion (same ID as the SHOPPING_CURATED "manapot"
    -- entry); no lasting buff, so CD display only. Racial resolves the
    -- player's race at scan time via byRace (hunter-usable TBC variants:
    -- Blood Fury AP 20572, Berserking mana-class 20554, Arcane Torrent mana
    -- 28730, Gift of the Naaru 28880, War Stomp 20549, Stoneform 20594,
    -- Shadowmeld 20580).
    { key = "KC",      type = "spell", id = 34026, label = "KC",     trackedOnly = true, usable = true, needsPet = true },  -- Kill Command: procActive = the spell is USABLE and off cooldown (the reference WA's rule; the proc aura is not visible to UnitBuff on this client)
    { key = "Raptor",  type = "spell", id = 27014, label = "Raptor", trackedOnly = true, melee = true },  -- Raptor Strike (React melee-bar color + grid; melee: range tint follows the Wing Clip probe)
    { key = "MD",      type = "spell", id = 34477, label = "MD",     trackedOnly = true },  -- Misdirection
    { key = "ManaPot", type = "item",  id = 22832, label = "Mana",   trackedOnly = true },  -- Super Mana Potion
    { key = "Racial",  type = "raceSpell", label = "Racial", trackedOnly = true,
      byRace = { Orc = 20572, Troll = 20554, Tauren = 20549, BloodElf = 28730,
                 Dwarf = 20594, NightElf = 20580, Draenei = 28880 } },

    -- Extra consumable options for the (editable) React grid rows — offered
    -- in the row Add dropdowns, not placed by default. trackedOnly for the
    -- same reason as above. altItem slots show the first owned variant.
    -- Rune: Dark Rune and Demonic Rune share their cooldown, so one slot
    -- covers both. Healthstone: Master ranks (Improved Healthstone 2/1/0) +
    -- older Major. Grenade: Adamantite -> Thorium (engineering throwables).
    { key = "Rune",        type = "altItem", ids = { 20520, 12662 },
      label = "Rune",        trackedOnly = true },
    { key = "Healthstone", type = "altItem", ids = { 22105, 22104, 22103, 9421 },
      label = "Healthstone", trackedOnly = true },
    { key = "Grenade",     type = "altItem", ids = { 23737, 15993 },
      label = "Grenade",     trackedOnly = true },
  },

  -- React-mode cooldown grid shape (UI/Frame_ReactCooldowns.lua). Static rows,
  -- not width-derived columns: row 1 = large rotation abilities, row 2 =
  -- throughput/utility CDs, row 3 = consumables — whenActive rows only show a
  -- slot while it's mid-cooldown or its buff is up (idle potions stay hidden).
  -- `h` is the tile height; `stretch` rows divide the full React width across
  -- their slots (wider-than-tall tiles, vertically cropped = the reference's
  -- zoomed look); non-stretch rows use fixed `w`x`h` tiles, centered.
  -- Dimensions pixel-measured off the reference: row 1 ≈ 40x32 full-width,
  -- rows 2/3 ≈ 32x24 centered.
  -- Keys resolve through Cooldowns:GetEntry (catalog incl. trackedOnly). Users
  -- hide individual slots via profile.reactCooldownDisabled.
  REACT_CD_ROWS = {
    { h = 32, stretch = true, keys = { "KC", "Arc", "MS", "Raptor", "Spec", "RF" } },
    { h = 24, w = 32, keys = { "Conc", "Intim", "Trap", "MD", "FD", "Racial" } },
    { h = 24, w = 32, keys = { "Haste", "ManaPot" }, whenActive = true },
  },

  -- FluffyHUD's single cooldown icon row (UI/Frame_FluffyCooldowns.lua,
  -- fluffyShowGrid, ships OFF). Seed deliberately DIFFERS from the React
  -- row 1: Arcane/Multi are already drawn as windows in the fluffy shot
  -- lanes, so their tiles would be noise — the trinket slots take their
  -- exact positions (credit: TeamSpeakUser). Membership is fully editable via the
  -- row editor on FluffyHUD → Cooldown Row (profile.fluffyCdKeys, a flat key
  -- list; false = this seed) plus per-key fluffyCooldownDisabled.
  FLUFFY_CD_KEYS = { "KC", "T1", "T2", "Raptor", "Spec", "RF" },

  -- Projectile-maker items (arrow + bullet equivalents). The info row sums,
  -- per maker, GetItemCount(id,false,true) * multiplier and adds it to the
  -- ammo count. GetItemCount's "include charges" mode returns the true total
  -- remaining charges on this client (verified via /nock arrows), so
  -- multiplier is arrows-PER-CHARGE. (Bag stackCount can't be used: a charged
  -- item's slot stackCount is 1 here, not its charge count.)
  --   20475 — Adamantite Arrow Maker, 5 charges per item, 200 arrows per charge
  --   34504 — Adamantite Shell Machine, 5 charges per item, 200 bullets per charge
  -- (Constant name kept as ARROW_MAKERS for stability with the existing reader;
  -- the table contents are bow/gun agnostic.)
  ARROW_MAKERS = {
    { id = 20475, multiplier = 200 },  -- Adamantite Arrow Maker → 200 Adamantite Stingers
    { id = 34504, multiplier = 200 },  -- Adamantite Shell Machine → 200 Adamantite Shells per charge
  },

  -- Shopping List. When the player's current zone (GetRealZoneText) matches one
  -- of these, the floating shopping panel lists curated/custom consumables that
  -- are below their restock threshold. Zone names are localized client-side;
  -- this default is enUS — non-enUS users edit the zone list in options.
  SHOPPING_ZONES_DEFAULT = "Shattrath City, Stormwind City, Ironforge, Darnassus, The Exodar, Orgrimmar, Thunder Bluff, Undercity, Silvermoon City",

  -- Curated restock catalog. `key` is the stable id used in the per-entry
  -- enable/threshold profile maps (shoppingDisabled / shoppingThreshold).
  -- `label` is a fallback only (resolved live via GetItemInfo for single-id
  -- entries; used verbatim for multi-id banners). `threshold` = default
  -- minimum; below it the item is "missing".
  --   • id  = nil + key "arrows" → synthetic: reads state.ammo.total
  --     (quiver + bags + maker charges) instead of GetItemCount.
  --   • ids  = { ... } → a "banner": GetItemCount summed across all listed
  --     item IDs counts toward one threshold (e.g. potion + its injector).
  --   • charges = true → count remaining CHARGES (GetItemCount include-charges)
  --     instead of item qty, for charged items like Drums of Battle. Works
  --     with id or ids; set threshold in charges accordingly.
  --   • id   = single itemID otherwise.
  -- Seeded from real hunter use.
  SHOPPING_CURATED = {
    { key = "arrows",    id = nil,   label = "Arrows / ammo (total)",     threshold = 5000 },
    { key = "hastepot",  id = 22838, label = "Haste Potion",              threshold = 15 },
    { key = "healpot",   ids = { 22829, 33092 }, label = "Healing potion (incl. injector)", threshold = 5 },
    { key = "manapot",   ids = { 22832, 33093, 31677 }, label = "Mana potion (incl. injector / fel)", threshold = 20 },
    { key = "scrollagi", ids = { 27498, 10309 }, label = "Scroll of Agility (IV/V)",  threshold = 10 },
    { key = "scrollstr", ids = { 27503, 10310 }, label = "Scroll of Strength (IV/V)", threshold = 10 },
    { key = "petfood",   id = 33874, label = "Kibler's Bits (pet food)",  threshold = 20 },
    { key = "elixiragi", id = 22831, label = "Elixir of Major Agility",   threshold = 20 },
    { key = "elixirmb",  id = 22840, label = "Elixir of Major Mageblood", threshold = 20 },
    { key = "drums",     id = 29529, charges = true, label = "Drums of Battle (charges)", threshold = 50 },
    { key = "tonk",      id = 22728, charges = true, label = "Steam Tonk Controller (charges)", threshold = 35 },
    { key = "bandage",   id = 21991, label = "Heavy Netherweave Bandage", threshold = 10 },
    { key = "darkrune",  ids = { 20520, 12662 }, label = "Dark / Demonic Rune",            threshold = 20 },
    { key = "sapper",    ids = { 23827, 10646 }, label = "Sapper Charge (Super/Goblin)",   threshold = 10 },
    -- Anetheron's Sleep breaker (Modules/SlammerEngine.lua); a Midsummer vendor
    -- drink in stacks of 10, and a Hyjal night burns one per Sleep window.
    { key = "slammer",   id = 38466, label = "Sulfuron Slammer (Anetheron)",    threshold = 20 },
  },

  -- Debuff tracker preset (target debuffs a hunter cares about). Same entry
  -- shape as the BuffTracker catalog: matched by `names` (rank-agnostic);
  -- `spellIds` only feed icon resolution; `fallbackIcon` if uncached. Users
  -- can disable entries or add their own by spell ID OR name in options.
  DEBUFF_CURATED = {
    { key = "hmark",   label = "Hunter's Mark",        names = { "Hunter's Mark" },
      spellIds = { 1130, 14323, 14324, 14325 }, fallbackIcon = "Interface\\Icons\\Ability_Hunter_SniperShot" },
    { key = "jow",     label = "Judgement of Wisdom",  names = { "Judgement of Wisdom" },
      spellIds = { 20354, 20355, 27164 },       fallbackIcon = "Interface\\Icons\\Spell_Holy_RighteousnessAura" },
    { key = "ew",      label = "Expose Weakness",      names = { "Expose Weakness" },
      spellIds = { 34501 },                     fallbackIcon = "Interface\\Icons\\Ability_Rogue_FindWeakness" },
    -- Sunder Armor and Expose Armor share the target's armor-reduction slot
    -- (mutually exclusive in TBC) — one combined entry, present if EITHER is up.
    { key = "armorshred", label = "Sunder / Expose Armor", names = { "Sunder Armor", "Expose Armor" },
      spellIds = { 7386, 8647 },                fallbackIcon = "Interface\\Icons\\Ability_Warrior_Sunder" },
    { key = "ff",      label = "Faerie Fire",          names = { "Faerie Fire", "Faerie Fire (Feral)" },
      spellIds = { 770, 16857 },                fallbackIcon = "Interface\\Icons\\Spell_Nature_FaerieFire" },
    { key = "creck",   label = "Curse of Recklessness", names = { "Curse of Recklessness" },
      spellIds = { 704, 7658, 7659, 11717, 27226 }, fallbackIcon = "Interface\\Icons\\Spell_Shadow_UnholyStrength" },
    { key = "bfrenzy", label = "Blood Frenzy",         names = { "Blood Frenzy" },
      spellIds = { 29859, 30069 },              fallbackIcon = "Interface\\Icons\\Ability_Druid_Bloodfrenzy" },
    -- The two melee-hit-reduction (tank mitigation) debuffs. `defaultOff`:
    -- listed in Options, OFF until switched on — most hunters track the DPS
    -- set above and nothing else (Modules/DebuffTracker.lua reads the flag).
    { key = "scorpid", label = "Scorpid Sting",        names = { "Scorpid Sting" },
      spellIds = { 3043, 14275, 14276, 14277 }, fallbackIcon = "Interface\\Icons\\Ability_Hunter_CriticalShot",
      defaultOff = true },
    { key = "iswarm",  label = "Insect Swarm",         names = { "Insect Swarm" },
      spellIds = { 5570, 24974, 24975, 24976, 24977, 27013 }, fallbackIcon = "Interface\\Icons\\Spell_Nature_InsectSwarm",
      defaultOff = true },
  },

  -- itemID → buff spellID, for proc-glow detection on item/inventory slots.
  -- (Cooldown grid slots only fire procActive when the matching buff is up.)
  -- Trinket entries are matched dynamically: GetInventoryItemID gives the
  -- equipped trinket's itemID, which we then look up here.
  ITEM_PROC_BUFFS = {
    -- Hunter trinkets (TBC)
    [28288] = 33807,  -- Abacus of Violent Odds      → Quickened Spirit (+haste, 20s)
    [28830] = 34774,  -- Dragonspine Trophy          → Haste            (+haste, 10s proc)
    [28034] = 33649,  -- Hourglass of the Unraveller → Rage of the Unraveller (+AP on crit, 10s)
    [29383] = 35166,  -- Bloodlust Brooch            → Lust for Battle  (+AP, 20s)
    [29387] = 35167,  -- Berserker's Call            → Call of the Berserker (+AP, 20s)
    [30627] = 37722,  -- Tsunami Talisman            → Focused          (+AP on crit, 10s)
    [30446] = 37670,  -- Bandit's Insignia           → Bandit's Insignia (+AP proc)
    [32505] = 40475,  -- Madness of the Betrayer     → Madness of the Betrayer (+ArP)
    [34427] = 45355,  -- Blackened Naaru Sliver      → Battle Trance (+AP per stack, up to 10, 20s)
    [17774] = 21956,  -- Slayer's Crest (legacy AQ)  → Crest of the Slayer (+AP, 20s)
    -- Consumables / utility items
    [22838] = 28507,  -- Haste Potion       → Haste (+401 haste rating, 15s)
    [29529] = 35476,  -- Drums of Battle    → Drums of Battle (+81 haste rating, 30s)
  },

  -- Utility items shown in the separate utility tracker row. Each entry must have id.
  -- Items not in inventory at runtime are hidden from the row.
  UTIL_ITEMS = {
    { key = "gnomCloak",   id = 4397,  label = "Cloak"     },  -- Gnomish Cloaking Device
    { key = "parachute",   id = 12438, label = "Parachute" },  -- Parachute Cloak
    { key = "carrot",      id = 11122, label = "Carrot"    },  -- Carrot on a Stick
    { key = "ridingCrop",  id = 25653, label = "Crop"      },  -- Riding Crop
    { key = "invPot",      id = 9172,  label = "InvPot"    },  -- Invisibility Potion
    { key = "skull",       id = 5510,  label = "Skull"     },  -- Skull of Impending Doom
    { key = "chicken",     id = 10725, label = "Chicken"   },  -- Gnomish Battle Chicken
    { key = "rocketLite",  id = 23824, label = "RocketL"   },  -- Rocket Boots Xtreme Lite
    { key = "stopwatch",   id = 2820,  label = "Stopwatch" },  -- Nifty Stopwatch
    { key = "goblinBoots", id = 7740,  label = "GobBoots"  },  -- Goblin Rocket Boots
    { key = "gnomishBoots",id = 7741,  label = "GnomBoots" },  -- Gnomish Rocket Boots
    { key = "swiftBoots",  id = 7676,  label = "Swift"     },  -- Swift Boots
    { key = "hastePot",    id = 22838, label = "Haste Pot" },  -- Haste Potion (buff detection)
  },
}
