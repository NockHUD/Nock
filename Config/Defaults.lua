-- Config/Defaults.lua
-- Centralized AceDB profile defaults. All tunable values live in Nock.db.profile.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

local C = Nock.Constants  -- Core/Constants.lua loads first (see Nock.toc)

Nock.Defaults = {
  profile = {
    position         = { point = "CENTER", relPoint = "CENTER", x = 0, y = -150 },
    -- One global lock for every movable Nock frame (HUD, medallion, misdirect
    -- panel, buff/debuff trackers, shopping list, free-layout rows). The setup
    -- wizard unlocks while it is open and locks again on close.
    locked           = true,
    -- Edit-mode grid (/nock unlock): the raster overlay and its control panel.
    editGridShow     = true,        -- draw the grid while unlocked
    editGridSize     = 16,          -- raster in screen units (4..64, step 2)
    editGridSnap     = "off",       -- "off" | "release" (snap when the drag ends) | "drag" (ghost outline while dragging, snap on release)
    editSnapBy       = "nearest",   -- "nearest" (edge or centre, per axis) | "corner" (top-left)
    editPanelPos     = false,       -- false = top centre; else { point, relPoint, x, y } (UIParent-relative)
    -- LibDBIcon's own table for the minimap button (hide, minimapPos, ...).
    minimap          = { hide = false },
    -- Master switch for the HUD frame itself (swing bars, shot display, cooldown
    -- grid, range finder, mana, info row, and the pet/repair panels glued to it).
    -- Off leaves everything parented to UIParent running — warnings, trackers,
    -- helpers, shopping, mailbox — for someone who wants Nock's alerts without a
    -- bar cluster on screen.
    hudEnabled       = true,
    scale            = 1.0,
    opacity          = 1.0,
    opacityOoc       = 1.0,
    hideOoc          = false,
    showAutoShotCast = false,
    -- Show mounts and other non-combat casts on the cast bar. Off by default: the
    -- cast bar is driven by CLEU (the only reliable source for ranged shots like
    -- Multi-Shot), which never logs a mount summon — so this adds a second,
    -- UNIT_SPELLCAST_START-driven path just for the casts CLEU misses. Opt-in
    -- until it's had real-world mileage. See Modules/CastBar.lua.
    castBarNonCombatCasts = false,
    -- Hide the default Blizzard player cast bar (Nock's bar replaces it).
    hideBlizzardCastBar = false,

    -- Performance (see Modules/Profiler.lua).
    --   perfTickHz         0 = tick every rendered frame (default). >0 throttles the
    --                      central tick, but that also throttles bar animation and
    --                      reads as stutter — prefer perfThrottleScans instead.
    --   perfThrottleScans  ON by default: modules declaring `refreshInterval` (the
    --                      aura-scanning engines + slow-changing panels) refresh at
    --                      ~10 Hz instead of per frame. Measured ~57% of addon CPU
    --                      was per-frame aura scans in Warnings/TotemTracker/
    --                      PetStatusView. Set false to A/B against the old behavior.
    perfTickHz            = 0,
    perfThrottleScans     = true,
    profilerOverlayShown  = false,
    profilerOverlayPos    = nil,   -- { point, relPoint, x, y }; set when the overlay is dragged

    -- HUD backdrop box. Off (or opacity 0) removes the solid black background +
    -- border entirely so it stops blocking vision. Only takes effect while the
    -- HUD is locked (an unlocked HUD always shows a grabbable box for dragging).
    backgroundEnabled = true,
    backgroundColor   = { 0.0, 0.0, 0.0 },  -- RGB; alpha comes from backgroundOpacity
    backgroundOpacity = 0.85,               -- 0 = fully transparent (same as off)
    -- HUD border styling (mirrors the icon-border resolver, HUD-frame only).
    hudBorder         = "None",             -- LSM "border" name; "None" = 1px solid line
    hudBorderSize     = 12,                 -- edge size (px); only used when hudBorder ~= "None"
    hudBorderColor    = { 0.0, 0.0, 0.0 },  -- border tint (separate from the fill color)
    hudBorderOpacity  = 1.0,                -- border alpha; 0 = invisible border

    -- Independent per-row scale, multiplies on top of the global `scale`. 1.0 =
    -- unchanged. Applied via Frame:SetScale in HUD:LayoutChildren; the HUD box
    -- widens to contain the widest scaled row (never shrinks below HUD_WIDTH).
    rotationScale    = 1.0,   -- 6-icon helper row
    shotBarsScale    = 1.0,   -- scrolling shot-timing timeline (stacks with shotBarsHeight)
    swingScale       = 1.0,   -- ranged + melee swing bars
    rangeFinderScale = 1.0,   -- proximity bar
    infoRowScale     = 1.0,   -- speed / ammo strip
    totemScale       = 1.0,   -- totem-range side panel (glued to the HUD right edge)

    -- Layout. rowAlign = horizontal alignment of every grid row ("center" |
    -- "left"). freeLayout = drag each row anywhere (positions saved per-element
    -- in elementPositions, keyed by module name) instead of the cascading grid.
    -- Classic look only — resolved via Nock.FreeLayoutActive, which reads it as
    -- false while hudMode == "react" (React always grids).
    rowAlign         = "center",
    freeLayout       = false,
    -- Cast bar free position, honored in free layout only. false = welded to
    -- the HUD box's top edge (the default look, and the whole story in grid
    -- mode). A table breaks the weld and floats it at HUD_WIDTH.
    castBarPosition  = false,
    elementPositions = {},    -- [moduleName] = { point, relPoint, x, y }

    -- Per-row visibility. When false the row is hidden and the HUD's height
    -- recalculates (other rows pack up). Frames keep ticking in the background.
    showCooldowns    = true,
    showInfoRow      = true,
    showBuffRow      = true,   -- the React proc row floating above the Classic HUD (reactBuffRows is the React-side switch)
    buffRowScale     = 1.0,    -- its Classic scale (React: reactScale)
    classicBuffRowPos = false, -- false = welded above the classic cast bar; else { point, relPoint, x, y } HUD-relative (drag / nudge pad)
    showManaBar      = true,   -- thin player-mana bar directly above the range finder
    showRangeFinder  = true,   -- melee-proximity bar; off hides the bar (range logic keeps running for the weave helper)
    showCastBar      = true,   -- spell cast-bar panel floating above the HUD (off = never shown, even mid-cast)
    showPetStatus    = true,   -- pet happiness / Mend / Feed panel glued to the HUD's left edge

    -- Cooldown grid (now fully configurable). Defaults reproduce the original
    -- 2x7 grid exactly. The engine always tracks the full built-in catalog +
    -- every custom entry; the grid renders the enabled, ordered subset capped
    -- to cooldownCols * cooldownRows.
    --   cooldownOrder    : ordered array of entry keys (catalog + custom). When
    --                      a key is absent it falls back to catalog order, so
    --                      an empty default = the stock order.
    --   cooldownDisabled : ["<key>"] = true → hidden from the grid (still
    --                      tracked by the engine so dependents keep working).
    --   cooldownCustom   : array of { key, type="spell"|"item", id, procBuff,
    --                      label } user-added entries.
    cooldownCols     = 7,
    cooldownRows     = 2,
    cooldownOrder    = {},
    cooldownDisabled = {},
    cooldownCustom   = {},
    -- Active-state highlight (a proc up / a consumable's buff running) on the
    -- classic grid squares. Per HUD family on purpose — React and Fluffy
    -- carry their own reactActive*/fluffyActive* set (user, 2026-08-31).
    cooldownActiveStyle = "border",              -- "border" | "glow" | "none"
    cooldownActiveColor = { 0.00, 0.90, 0.90, 1.00 }, -- the border's color (PROC_GLOW cyan)
    cooldownActiveSize  = 3,                     -- border thickness, px
    cooldownActiveFit   = "overflow",            -- "overflow" (outside the tile) | "contained"

    -- Global on/off for whole subsystems (peers of showCooldowns). All
    -- default true so existing setups are unchanged. When false the panel is
    -- hidden AND its engine stops scanning (no wasted work).
    showWarnings     = true,
    showHelpers      = true,
    showRotation     = true,   -- whole rotation display: 6-icon helper row + Shot Bars

    -- LSM media (resolved at runtime). Names match LibSharedMedia entries; if a
    -- name isn't registered, the code falls back to the built-in Blizzard texture.
    -- "Nock Clean" is OUR texture (Media/NockClean.tga), registered by
    -- UI/Widgets.lua — so the shipped look is the same for every user instead of
    -- depending on which media addons they happen to have. Deliberately not a
    -- borrowed name like "Clean" (that one comes from WeakAuras): LSM:Fetch
    -- silently falls back to Blizzard for a name nobody registered, so a borrowed
    -- default would quietly give non-WeakAuras users a different-looking HUD.
    barTexture       = "Nock Clean",
    fontFace         = "Friz Quadrata TT",
    iconBorder       = "None",   -- LSM border name; "None" = 1px solid line
    iconBorderSize   = 8,        -- only used when iconBorder ~= "None"
    warningIconSize    = 44,
    warningBorderSize  = 3,
    warningLabelOffset = 10,
    warningLabelFont   = "Friz Quadrata TT",
    warningLabelSize   = 12,
    warningLabelStyle  = "THICKOUTLINE",
    warningLabelUpper  = false,

    -- Warning thresholds (percent values).
    hpThreshold           = 15,
    steamTonkThreshold    = 20,
    mendPetThreshold      = 50,
    manaSuggestThreshold  = 50,
    manaPanicThreshold    = 25,
    sapperMobCountThreshold = 3,      -- nearby units before the Sapper warning fires (radius fixed ~11 yd, not configurable)
    petTrainingPointThreshold = 10,   -- warn when the pet has more than this many UNSPENT training points (count, not %)
    quiverArrowThreshold  = 400,      -- warn (red) when the ammo IN THE QUIVER drops below this (count, not %; regular-bag stacks don't count)

    -- Per-warning enable flags. Defaults all true so existing setups behave
    -- the same; the settings UI exposes each as a toggle. (weaponStoneEnabled
    -- pre-dates this scheme and keeps its original key for compatibility.)
    warnHealthEnabled    = true,
    warnSteamTonkEnabled = true,
    warnMendPetEnabled   = true,
    warnManaEnabled      = true,
    warnLustCdsEnabled   = true,
    warnLustCdsVoice     = false,  -- speak "Trinket 2" via TTS when the first on-use trinket is popped during Lust (opt-in)
    warnDrumsEnabled     = true,
    warnUtilitiesEnabled = true,
    warnPetAttackEnabled = true,
    warnPetAttackVoice   = false,  -- speak "Pet idle" via TTS every 5s during a boss encounter (opt-in)
    warnPetPassiveEnabled = true,   -- nag when pet is on Aggressive/Defensive (should be Passive)
    warnPetGrowlEnabled  = true,    -- nag when pet Growl is set to autocast (should be off)
    warnPetTrainingEnabled = true,  -- nag (out of combat) when the pet has unspent training points to spend
    -- Nag (out of combat) when a Nock keybind has taken over a key that was
    -- already doing something. Nock's binds are priority overrides, so they win
    -- silently — see Modules/BindCheck.lua.
    warnBindConflictEnabled = true,
    -- Pet-training helper: the per-raid checklist panel beside the Beast Training window.
    petTrainerHelperEnabled = true, -- show the checklist when Beast Training opens
    petTrainerPreset        = "ssc",-- last-selected raid preset (tk/ssc/bt/hy/sw)
    petTrainerListFilter    = true, -- shrink Blizzard's Beast Training list to the preset's to-dos
    -- Steam Tonk guard. The transform is dismissed automatically a settling
    -- interval after it lands, in combat or out, which is what lets the old
    -- same-frame /cancelaura macro be retired. Ships ON: the bug it prevents can
    -- cost a raid attempt, and the one-time chat notice explains itself the
    -- first time it ever fires. C.TONK_CANCEL_DELAY is the single source for
    -- the interval.
    tonkAutoCancel  = true,
    tonkCancelDelay = C.TONK_CANCEL_DELAY,
    -- The countdown dial: the tonk icon with a radial sweep running down to the
    -- moment the guard steps you out. Purely informational — the guard does the
    -- work whether or not this is shown.
    tonkDialEnabled  = true,
    tonkDialSize     = 72,      -- square edge in px; drag the grip to resize
    tonkDialPosition = false,   -- false = below centre screen
    -- Raid-instance gates for the two "wrong setup" nags. false = warn everywhere
    -- (the original behavior). Growl autocast and a mount trinket are perfectly
    -- reasonable choices while questing — these let you keep the nag for raids
    -- only, where they actually cost you. Instance-based (IsInInstance == "raid"),
    -- so an open-world raid group does NOT count.
    warnPetGrowlRaidOnly     = false,
    warnWrongTrinketEnabled = true, -- nag when a "bad trinket" (riding crop, carrot, etc.) is equipped
    warnWrongTrinketRaidOnly = false,
    -- Comma/newline separated EXTRA item IDs the wrong-trinket warning flags,
    -- unioned with the built-in PvP insignia/medallion family
    -- (C.WRONG_TRINKET_IDS — every class/faction variant, so it can't go
    -- stale in an edited profile string). Seed covers the universal
    -- mount-speed trinkets plus Devilsaur Tooth (pop it pre-pull for the pet
    -- crit, then swap a real trinket in — still wearing it on a boss is the
    -- same mistake as the Crop; delist it here if you deliberately keep it
    -- on). Add other leveling junk via the Options panel. NOTE: AceDB never
    -- re-delivers a changed default to an edited profile string — profiles
    -- that touched this box before 19992 joined the seed keep their list.
    warnWrongTrinketIds  = "25653, 11122, 19992",  -- Riding Crop, Carrot on a Stick, Devilsaur Tooth
    -- Shirt-gated weave/consume macros ([noequipped:Shirt] lines): warn when
    -- targeting a raid boss with the shirt still equipped (gated lines dead).
    warnShirtGateEnabled = true,
    warnAspectEnabled    = true,    -- nag when in combat with any aspect other than Hawk (or none)
    warnAspectRaidOnly   = false,   -- opt-in: suppress the aspect nag outside raid instances
    warnDazedEnabled     = true,    -- alert when Dazed in combat (slowed + can't cast)
    -- LSM "sound" name played once per Daze; "None" = silent (the default — the
    -- square shows regardless, and an unbidden sound after an update is hostile).
    -- Pick one via the Options dropdown; the Preview button auditions it.
    warnDazedSound       = "None",
    warnTargetFrenzyEnabled = true,  -- remind to Tranq Shot when target has a frenzy/enrage
    -- Comma/newline separated SPELL IDs the Tranq-Shot warning matches (locale-
    -- proof fast-path). Anything not listed still triggers via the "Frenzy"/
    -- "Enrage" name fallback, which is the real workhorse — per-mob TBC IDs are
    -- mostly not web-verifiable, so this seed is deliberately small + confirmed:
    --   8269  generic "Enrage" (+60% atk spd, many TBC trash/bosses, Enrage type)
    --   33958 generic "Frenzy" (+100% atk spd, many TBC mobs, Enrage type)
    --   43139 Halazzi "Frenzy" (Zul'Aman, Enrage type)
    --   41254 Essence of Suffering "Frenzy" (Reliquary of Souls, Black Temple)
    -- All four verified self-cast Enrage-dispel-type buffs on Wowhead TBC. Add
    -- more per-encounter IDs via /dump on the target's buff, then the Options box.
    warnTargetFrenzyIds  = "8269, 33958, 43139, 41254",
    -- Sapper-on-packs warning. Hard-gated in code to: in a raid + boss target
    -- + >= sapperMobCountThreshold hostile mobs in ~11 yd (see Warnings.lua).
    warnSapperAoeEnabled = true,
    -- Devilsaur Tooth reminder: boss targeted, pet alive, tooth equipped, and
    -- the pet's guaranteed crit (Primal Instinct) not loaded. Opt-in — only
    -- worth a square to hunters actually carrying the tooth.
    warnDevilsaurEnabled = false,
    warnQuiverEnabled    = true,      -- quiver/ammo pouch almost empty (state.ammo.quiver < quiverArrowThreshold)
    warnFDResistEnabled  = true,
    warnFDResistTimeout  = 5,         -- seconds the resist warning stays visible
    warnFDResistSound    = "None",    -- LSM "sound" name; "None" = silent

    -- A boss's single-target mark aimed at you: Teron Gorefiend's Shadow of
    -- Death, Archimonde's Air Burst. Unlike every other cue in this file the
    -- default is NOT silent: the whole warning is worth about 1.5 seconds of
    -- reaction time, and a square you have to notice is no use. "Air Horn" is
    -- the DBM/BigWigs library name — Nock ships no audio, so on an install
    -- without one of those the cue falls back to the client's raid-warning
    -- sound (Modules/BossMarkWatch.lua). "None" silences it.
    --
    -- The two encounters share the banner, its position and the cue; the only
    -- per-boss settings are these on/off switches, so someone who raids one and
    -- not the other can silence the half they never see.
    warnBossMarkEnabled     = true,
    warnBossMarkTeron       = true,
    warnBossMarkArchimonde  = true,
    warnBossMarkSound       = "Air Horn",
    bossBannerSize          = 96,      -- icon edge in px; the text scales with it
    bossBannerPosition      = false,   -- false = above centre screen
    -- DO NOT RELEASE: dead (not yet released) with the Sated/Exhaustion
    -- debuff still on you — the raid burned Bloodlust/Heroism this attempt.
    -- Shares the boss banner (position/size). Ships ON: it can only ever
    -- appear while you lie dead after a lusted attempt, exactly when you
    -- need it.
    warnNoReleaseEnabled    = true,

    -- Anetheron's Sleep (Mount Hyjal): a CLICKABLE button that drinks a
    -- Sulfuron Slammer, whose self-damage tick wakes you. It counts down to
    -- the earliest next Sleep (16.5s after the last cast — the reference WA's
    -- number; BigWigs says 19.5-45s), reads CLICK NOW while the window is
    -- open and the buff is not, and judges every cast: buff up for at least
    -- the margin = quiet, under it or absent = EXPOSED and the horn. The horn
    -- fires on THAT verdict only — never on the window opening (user,
    -- 2026-08-27). Same audible default and library fallback as the boss
    -- mark. The button is secure, so it shows when Anetheron is seen out of
    -- combat and hides when he dies (Modules/SlammerWatch.lua). Ships OFF
    -- until it has been through a real Anetheron (user, 2026-08-27).
    warnSlammerEnabled      = false,
    slammerWindow           = 16.5,    -- s after a Sleep until the next can come
    slammerCoverMargin      = 2,       -- buff seconds left at the cast's END that still count as covered (slider 1.3-3)
    slammerButtonSize       = 46,      -- icon edge in px; the label scales with it
    warnSlammerSound        = "Air Horn",
    -- The softer second cue when a window OPENS - the reference WA's Glass
    -- (registered by WeakAuras); the client's ready-check chime when no
    -- library has it. Never on the re-drink prompt inside the window.
    warnSlammerWindowSound  = "Glass",
    slammerButtonPosition   = false,   -- false = right of centre screen
    -- The Dimensional Ripper / Ultrasafe Transporter countdown: big centre
    -- text counting the whole seconds down to (cast end - lead) and reading
    -- ALT F4 for the last second. Ships ON: it only ever triggers on those two
    -- trinkets' casts, which nobody uses by accident (user, 2026-08-27).
    warnRipperEnabled       = true,
    ripperLead              = 1.0,     -- s before the cast's end to close the client
    ripperTextSize          = 72,      -- the numeral's font size in px
    warnRipperSound         = "None",  -- optional cue at the flip to ALT F4
    ripperCountdownPosition = false,   -- false = centre screen

    -- Black Temple: the Medallion of Karabor teleports you to the raid and is
    -- easy to forget around your neck once inside — a stat-less SR neck for
    -- the whole run. Stands down around Mother Shahraz (the one fight where
    -- its Shadow Resistance is right) and returns when she dies.
    warnKaraborNeckEnabled  = true,

    -- Helpers panel (consumables row below the warnings).
    parseMode                    = true,   -- master toggle for parse-tier helpers (scrolls)
    -- Seconds left at which an ACTIVE buff starts nagging with a countdown
    -- ("expiring"); 0 turns the early warning off entirely.
    helpersExpiringThreshold     = 300,
    -- Panel placement + look. `false` means the legacy computed spot (centred
    -- below the warnings row); a table once the panel has been dragged.
    helpersPosition              = false,
    helpersIconSize              = 40,
    helpersIconGap               = 10,
    helpersScale                 = 1.0,
    -- Background block defaults reproduce the pre-styling look: no visible box.
    helpersBgColor               = { 0.0, 0.0, 0.0 },
    helpersBgOpacity             = 0,
    helpersBorder                = "None",
    helpersBorderSize            = 12,
    helpersBorderColor           = { 0.0, 0.0, 0.0 },
    helpersBorderOpacity         = 0,
    -- Auto-hide the Helpers panel when a WeakAura whose name starts with any
    -- of these (comma/newline separated, case-sensitive) prefixes is loaded —
    -- that pack already covers the same ground. Blank disables the WA gate.
    -- These strings are MATCH DATA, not a credit line: they have to equal the
    -- display names the third-party pack actually uses or the gate never fires.
    helpersHideWA                = "Fojji - [T4], Fojji - [T5], Fojji - [T6], Fojji - [T7]",

    -- Misdirection tracker (party/raid hunters' MD cooldowns).
    misdirectEnabled  = false,
    misdirectWidth    = 200,
    misdirectPosition = { point = "CENTER", relPoint = "CENTER", x = 250, y = 0 },
    mdShowHeader      = true,   -- the MISDIRECTION title; off gives its height back to the panel
    -- Panel background alpha. 0.85 = the shared C.COLORS.BG look (unchanged
    -- default); 0 makes the black panel disappear behind the rows.
    mdBackgroundOpacity = 0.85,
    -- Rest of the per-panel Background styling block (see panelStyleArgs in
    -- Config/Options.lua). Defaults reproduce the old hardcoded look: black
    -- fill, 1px solid black border.
    mdBgColor           = { 0.0, 0.0, 0.0 },
    mdBorder            = "None",   -- LSM "border" name; "None" = 1px solid line
    mdBorderSize        = 12,
    mdBorderColor       = { 0.0, 0.0, 0.0 },
    mdBorderOpacity     = 1.0,

    -- Click-to-Misdirect tank section (bottom of the shared Misdirection panel):
    -- one secure clickable row per group member assigned the Tank role; clicking
    -- casts Misdirection on them. Off by default. Panel chrome (width/position)
    -- is shared with the tracker via the misdirect* keys above; locking is the
    -- global `locked` key.
    mdCastEnabled  = false,
    mdCastAnnounce = true,   -- raid/party ping on click
    mdCastTooltip  = false,  -- show a hover tooltip on tank buttons (opt-in)
    mdCastTankList = "",     -- optional manual tank names (comma/newline) when roles aren't assigned
    mdCastDebug    = false,  -- print the attempted macro on each row click (troubleshooting)

    -- EXPERIMENTAL (Experimental tab) — sapper column in the Misdirection panel
    -- plus the MD + Sapper raid announce (Modules/SapperTracker). Your own
    -- square is read from the item; everyone else's is combat-log evidence, so
    -- a square only lights up once you've seen that person use one.
    mdSapperEnabled       = false,
    mdSapperAnnounce      = true,
    mdSapperAnnounceScope = "all",  -- "all" = every tracked hunter | "self" = only your own openers

    -- Buff tracker grids (player + pet). OmniCC-friendly.
    buffTrackerEnabled        = false,
    buffTrackerCols           = 5,
    buffTrackerIconSize       = 24,
    buffTrackerPlayerEnabled  = true,
    buffTrackerPlayerPosition = { point = "CENTER", relPoint = "CENTER", x = -100, y = 100 },
    buffTrackerPetEnabled     = true,
    buffTrackerPetPosition    = { point = "CENTER", relPoint = "CENTER", x =  100, y = 100 },
    -- Per-entry disable map ("player:<key>" / "pet:<key>" = true) + custom
    -- spell-ID strings (whitespace/comma/newline separated).
    buffTrackerDisabled       = {},
    buffTrackerCustomPlayer   = "",
    buffTrackerCustomPet      = "",
    -- Background styling block, applied to BOTH grids (player + pet).
    -- Defaults = the old hardcoded shared look (C.COLORS.BG + 1px black).
    buffTrackerBgColor        = { 0.0, 0.0, 0.0 },
    buffTrackerBgOpacity      = 0.85,
    buffTrackerBorder         = "None",
    buffTrackerBorderSize     = 12,
    buffTrackerBorderColor    = { 0.0, 0.0, 0.0 },
    buffTrackerBorderOpacity  = 1.0,

    -- Debuff tracker (bare draggable icon grid of target debuffs). Off by
    -- default; when enabled it only shows in a raid (and with a target).
    debuffTrackerEnabled  = false,
    debuffTrackerRaidOnly = true,
    debuffTrackerPosition = { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 },
    debuffTrackerCols     = 8,
    debuffTrackerIconSize = 26,
    debuffTrackerDisabled = {},   -- ["<key>"] = true disables an entry, false forces one ON (presets marked defaultOff are OFF until then)
    debuffTrackerOrder    = {},   -- key list; leads the display order, anything missing follows in catalog order (Up/Down in Options)
    debuffTrackerCustom   = "",   -- extra debuffs: spell IDs or names, one per line/comma
    -- Background styling block. Defaults keep the grid's bare look: fully
    -- transparent fill AND border (icons only) until the user styles it.
    debuffTrackerBgColor        = { 0.0, 0.0, 0.0 },
    debuffTrackerBgOpacity      = 0,
    debuffTrackerBorder         = "None",
    debuffTrackerBorderSize     = 12,
    debuffTrackerBorderColor    = { 0.0, 0.0, 0.0 },
    debuffTrackerBorderOpacity  = 0,

    -- Totem-range panel (HUD-glued, right edge — mirror of pet status).
    totemTrackerEnabled = true,
    totemForceShaman    = true,   -- testing: always show. Later → real shaman-in-group gate.

    -- Shopping List (floating panel, only while in a configured city zone —
    -- lists curated/custom consumables below their restock threshold).
    shoppingEnabled   = true,
    shoppingPosition  = { point = "CENTER", relPoint = "CENTER", x = -250, y = 0 },
    shoppingWidth     = 210,
    shoppingShowCompleted = false,  -- the panel's top-left toggle: list stocked items too (green count)
    -- Comma/newline-separated zone names (matched vs GetRealZoneText, case-
    -- insensitive). Seeded from Constants.SHOPPING_ZONES_DEFAULT; edit freely.
    shoppingZones     = "Shattrath City, Stormwind City, Ironforge, Darnassus, The Exodar, Orgrimmar, Thunder Bluff, Undercity, Silvermoon City",
    -- Per-curated-entry maps, keyed by Constants.SHOPPING_CURATED[].key:
    shoppingDisabled  = {},   -- ["<key>"] = true  → hide that curated item
    shoppingThreshold = {},   -- ["<key>"] = number → override default threshold
    -- Free-form extra items, one per line: "itemID:threshold[:label]".
    shoppingCustom    = "",
    -- Background styling block. Defaults reproduce the old hardcoded look
    -- (black at 0.78 with a 1px black border).
    shoppingBgColor        = { 0.0, 0.0, 0.0 },
    shoppingBgOpacity      = 0.78,
    shoppingBorder         = "None",
    shoppingBorderSize     = 12,
    shoppingBorderColor    = { 0.0, 0.0, 0.0 },
    shoppingBorderOpacity  = 1.0,

    -- Repair reminder: a red durability bar glued under the HUD, shown only in
    -- the shopping zones (above) when equipped durability drops below the %.
    repairWarnEnabled = true,
    repairWarnPct     = 90,
    helperFoodEnabled            = true,
    helperFlaskEnabled           = true,
    helperBattleElixirEnabled    = true,
    helperGuardianElixirEnabled  = true,
    helperStoneEnabled           = true,
    helperKiblerEnabled          = true,
    helperScrollPlayerEnabled    = true,
    helperScrollPetEnabled       = true,
    helperDemonslayerEnabled     = true,
    helperConsecratedEnabled     = true,

    -- Weapon stones warning (sharpening / weightstone on main-hand).
    weaponStoneEnabled       = true,
    weaponStoneCombatOnly    = false, -- if true, only warn while in combat
    weaponStoneExpiringSec   = 120,   -- blue "expiring" warning fires below this many seconds (countdown shown on icon)

    -- Mana bar (thin row above the range finder). manaBarText: what the
    -- centered label shows — "none" | "percent" | "value" | "both".
    manaBarHeight = 14,
    manaBarColor  = { 0.20, 0.40, 0.95, 1.00 },
    manaBarText   = "percent",

    -- Dead-zone audio cues. Distinct sound when you enter / leave the dead zone
    -- (rangeZone "TOO_CLOSE"). Fires on any real zone transition, including a
    -- tank repositioning the boss; target loss stays silent. "None" = silent.
    deadZoneEnterEnabled = true,
    deadZoneEnterSound   = "None",  -- LSM "sound" name
    deadZoneExitEnabled  = true,
    deadZoneExitSound    = "None",  -- LSM "sound" name
    deadZoneSoundChannel = "Master", -- PlaySoundFile channel: Master/SFX/Music/Ambience/Dialog

    -- Range Finder bar height in px (default matches C.DIM.RANGE_SQUARE_H).
    rangeFinderHeight = 16,

    -- Range Finder bar colors (RGBA, 0..1). The bar fills toward melee and
    -- recolors by state: Out (finding fill + CLOSE 7-10yd), Close-to-perfect
    -- (SWEET weave ring), Perfect (PERFECT sliver at the melee edge), and
    -- rangeInColor = the DEADZONE fill (in melee, can't shoot) — red.
    rangeOutColor     = { 1.00, 0.35, 0.54, 1.00 },
    rangeInColor      = { 0.68, 0.18, 0.20, 1.00 },
    rangePerfectColor = { 0.10, 0.65, 0.20, 0.65 },
    rangeCloseColor   = { 0.55, 0.95, 0.45, 0.45 },
    -- Finding style beyond the ~10yd weave zone (spec 2026-08-06): "drain" =
    -- fill shows distance remaining to the weave zone; "block" = solid
    -- color-coded bracket block (reference Range Check WA look).
    rangeFinderFindingStyle = "drain",
    -- Zoomed weave bar (Experimental tab, idea by Erda): centered viewport
    -- crop of the glide view; tick stays centered, movement reads
    -- rangeZoomLevel times bigger (2x = the outer 25% per side shaven off).
    rangeZoomedGlide = false,
    rangeZoomLevel = 2,
    rangeInRedMigrated = false,  -- one-time deadzone-red default migration latch

    -- Rotation tunables.
    rotationHelperEnabled = true,   -- master toggle: when false, no next-action glow fires (row stays visible for CD swipes)
    -- Swing-timer bar direction. Two axes: drain (show remaining) vs fill (show
    -- elapsed), and which edge the fill hugs. The label is the moving-edge sweep:
    --   "rtl"      drain, left-anchored  → edge sweeps right→left (original)
    --   "drainltr" drain, right-anchored → edge sweeps left→right
    --   "ltr"      fill,  left-anchored  → edge sweeps left→right
    --   "fillrtl"  fill,  right-anchored → edge sweeps right→left
    -- Consumed live in Frame_SwingTimers (fillMode()).
    swingFillDirection    = "rtl",  -- "rtl" | "drainltr" | "ltr" | "fillrtl"
    -- Per-bar direction overrides. "inherit" (the default) falls back to
    -- swingFillDirection above — so all three bars keep moving together until you
    -- deliberately split one, and an upgrading profile behaves exactly as before.
    -- Same four modes as the global, plus "inherit".
    swingFillDirectionRanged = "inherit",  -- "inherit" | "rtl" | "drainltr" | "ltr" | "fillrtl"
    swingFillDirectionMelee  = "inherit",
    swingFillDirectionGcd    = "inherit",
    -- Thin global-cooldown sweep above the auto-shot bar. Follows the swing-bar
    -- fill direction unless overridden above. Height in px (a few px reads best).
    showGcdBar            = true,
    gcdBarHeight          = 4,
    gcdBarColor           = { 0.65, 0.45, 1.00, 1.00 },  -- light purple
    -- Per-bar swing customization. Each of the two swing bars (auto-shot/ranged
    -- and melee) can be hidden, drop its icon (the bar then stretches full
    -- width), get a custom height, and use its own LSM texture ("" = inherit the
    -- global barTexture). Defaults reproduce the original look exactly.
    showAutoShotBar    = true,
    autoShotShowIcon   = true,
    autoShotBarRotationText = true,   -- rotation notation ("1:1" / weave) centred on the Auto Shot bar
    autoShotBarHeight  = 20,   -- px, range 8..40 (matches C.DIM.RANGED_BAR_H)
    autoShotBarTexture = "",   -- "" = inherit global barTexture
    autoShotBarColor   = { 1.00, 0.84, 0.00, 1.00 },  -- gold (matches C.COLORS.RANGED_SWING)
    showMeleeBar       = true,
    meleeShowIcon      = true,
    meleeBarHeight     = 8,    -- px, range 4..40 (matches C.DIM.MELEE_BAR_H)
    meleeBarTexture    = "",   -- "" = inherit global barTexture
    meleeBarColor      = { 1.00, 1.00, 1.00, 1.00 },  -- white (matches C.COLORS.MELEE_SWING)
    -- Clip-zone tick colors on the Auto Shot bar. Defaults reproduce the
    -- original semantics: red = Steady would clip, orange = Multi would clip,
    -- neutral grey = wind-up commit landmark.
    clipTickSteadyColor = { 1.00, 0.10, 0.10, 1.00 },
    clipTickMultiColor  = { 1.00, 0.65, 0.10, 1.00 },
    clipTickWindupColor = { 0.85, 0.85, 0.85, 0.80 },
    -- Tick widths in DEVICE pixels (real screen pixels, not logical units --
    -- see Nock.UI.DeviceWidth). 1 = a true hairline at any UI scale. The React
    -- auto bar carries its own reactTick*Width keys (own skin channel).
    clipTickSteadyWidth = 1,
    clipTickMultiWidth  = 1,
    clipTickWindupWidth = 1,
    -- Classic cast bar styling (Classic HUD → Cast Bar). Defaults reproduce
    -- the original look exactly.
    castBarHeight   = 22,   -- px (matches C.DIM.CAST_BAR_H)
    castBarTexture  = "",   -- "" = inherit global barTexture
    castBarShowIcon = true,
    castBarColor    = { 0.40, 0.70, 1.00, 1.00 },  -- light blue (matches C.COLORS.CAST_BAR)
    castBarPadding  = 4,    -- panel inset around icon + bar (matches C.DIM.OUTER_PAD)
    -- Cast bar panel Background block (same shape as the floating panels).
    castBarBgColor        = { 0.0, 0.0, 0.0 },
    castBarBgOpacity      = 0.85,
    castBarBorder         = "None",
    castBarBorderSize     = 12,
    castBarBorderColor    = { 0.0, 0.0, 0.0 },
    castBarBorderOpacity  = 1.0,

    -- Per-bar TRACK styling (Classic HUD). The track is the 1px-backdrop frame
    -- behind each bar's fill -- what shows through wherever the fill hasn't
    -- reached. Was hardcoded black (C.COLORS.BG / C.COLORS.BORDER); these keys
    -- reproduce that exactly, so an untouched profile is pixel-identical.
    -- Rendered by UI/Widgets.lua's ApplyBarStyle; options block is
    -- Config/Options.lua's barStyleArgs. NOTE the castBarTrack* prefix is
    -- distinct from castBar* above: that one skins the PANEL around the bar,
    -- this one skins the bar itself.
    castBarTrackBgColor        = { 0.0, 0.0, 0.0 },
    castBarTrackBgOpacity      = 0.85,
    castBarTrackBorderColor    = { 0.0, 0.0, 0.0 },
    castBarTrackBorderOpacity  = 1.0,
    autoShotTrackBgColor       = { 0.0, 0.0, 0.0 },
    autoShotTrackBgOpacity     = 0.85,
    autoShotTrackBorderColor   = { 0.0, 0.0, 0.0 },
    autoShotTrackBorderOpacity = 1.0,
    meleeTrackBgColor          = { 0.0, 0.0, 0.0 },
    meleeTrackBgOpacity        = 0.85,
    meleeTrackBorderColor      = { 0.0, 0.0, 0.0 },
    meleeTrackBorderOpacity    = 1.0,
    gcdTrackBgColor            = { 0.0, 0.0, 0.0 },
    gcdTrackBgOpacity          = 0.85,
    gcdTrackBorderColor        = { 0.0, 0.0, 0.0 },
    gcdTrackBorderOpacity      = 1.0,
    manaTrackBgColor           = { 0.0, 0.0, 0.0 },
    manaTrackBgOpacity         = 0.85,
    manaTrackBorderColor       = { 0.0, 0.0, 0.0 },
    manaTrackBorderOpacity     = 1.0,
    rangeTrackBgColor          = { 0.0, 0.0, 0.0 },
    rangeTrackBgOpacity        = 0.85,
    rangeTrackBorderColor      = { 0.0, 0.0, 0.0 },
    rangeTrackBorderOpacity    = 1.0,
    shotBarsTrackBgColor       = { 0.0, 0.0, 0.0 },
    shotBarsTrackBgOpacity     = 0.85,
    shotBarsTrackBorderColor   = { 0.0, 0.0, 0.0 },
    shotBarsTrackBorderOpacity = 1.0,
    -- Experimental: how late each Auto Shot fires vs one weapon-speed cycle
    -- (extracted from the "TBC Hunter UI by React" WA). Shown in seconds (+0.45),
    -- color-coded, on the right edge of the Auto Shot bar. Off by default.
    autoShotDelayEnabled = false,
    rotQuiverEquipped     = true,   -- assume +15% ranged-AS quiver/ammo pouch when computing clip windows
    -- No clipSafetyMargin key: the clip ticks are cast + measured wind-up +
    -- latency and nothing else. Retired in 1.0.19; Core.lua clears the stored
    -- value from existing profiles.
    showWindupMark        = true,   -- neutral mark on both auto-shot bars at swingRemaining == AUTO_SHOT_CAST (the commit point)
    rotRaptorWeaveHeadroom = 1.0,   -- seconds of swing headroom required before suggesting Raptor
    rotWeaveProxMin        = -0.10, -- proximity-bar lower bound where the weave helper fires (matches CLOSE band)
    rotWeaveProxMax        =  0.00, -- proximity-bar upper bound where the weave helper fires (threshold)

    -- Next-action highlight effect on the rotation row.
    -- "none" | "static" | "pixelGlow" | "buttonGlow" | "autoCastGlow"
    rotNextEffect          = "pixelGlow",
    rotNextColor           = { 0.00, 1.00, 0.40, 1.00 },

    -- Rotation display mode. "helper" = today's 6-icon next-action row +
    -- swing bar. "bars" = Fluffy-style scrolling shot-timing bars that take
    -- the top slot and hide BOTH the helper icons and the whole swing row.
    rotationMode       = "bars",          -- "helper" | "bars"
    -- HUD look. "classic" = the existing row stack. "react" = fixed-skin
    -- replica of the React hunter WA: converge-to-center auto bar, melee bar,
    -- slide range finder, thin mana bar and a 3-row cooldown grid, replacing
    -- the classic rows entirely (side panels/warnings/helpers unaffected).
    -- The React frames ignore barTexture/LSM; everything configurable lives
    -- on the React HUD options tab (the react* keys below). Toggle with
    -- /nock react.
    hudMode              = "classic",   -- "classic" | "react" | "fluffy"
    reactWidth           = 240,         -- React cluster/grid width in px (160..280)
    reactScale           = 1.0,         -- shared per-row scale for both React rows
    reactCooldownDisabled = {},         -- ["<key>"] = true → hide that React grid slot
    reactShowDelay       = false,       -- show the +x.xx late-shot readout on the React auto bar
    reactShowBrackets    = false,       -- show the eWS bracket marks on the React auto bar
    -- React buff row (UI/Frame_ReactBuffs.lua): the WA pack's Important +
    -- Dynamic-utility icon sections unified into ONE row centered above the
    -- HUD. While React mode is on it REPLACES the BuffTracker + TotemTracker
    -- panels (engines keep running; the Windfury slot reads state.totems).
    reactBuffRows        = true,
    -- React element visibility (React HUD tab). These REPLACE the classic
    -- show* flags for the React frames — showAutoShotBar/showMeleeBar/
    -- showRangeFinder/showManaBar/showCastBar/showCooldowns no longer affect
    -- React mode (see CHANGELOG).
    reactShowAutoBar     = true,        -- converge Auto Shot bar
    reactShowMeleeBar    = true,        -- melee swing bar
    reactShowRangeBar    = true,        -- slide range finder
    reactShowManaBar     = true,        -- thin mana bar
    reactManaText        = "percent",   -- mana bar center text: "none" | "percent" | "value" | "both"
    -- Top-to-bottom bar order. false = built-in {"auto","melee","range","mana"};
    -- materialized to an array by the first Up/Down on the React HUD tab and
    -- sanitized through Nock.UI.ResolveReactBarOrder on every read.
    reactBarOrder        = false,
    reactShowCastBar     = true,        -- glued cast bar
    -- React-only: the 0.5s Auto Shot wind-up on the cast bar. Classic keeps the
    -- separate opt-in showAutoShotCast (off above) — its swing timer covers it.
    reactShowAutoShotCast = true,
    reactShowGrid        = true,        -- 3-row cooldown grid
    reactShowNotation    = true,        -- rotation notation on the auto bar's right edge
    -- React cooldown grid.
    reactConsumablesAlways = false,     -- row 3: always show slots (ignore the whenActive auto-hide)
    -- Reference-WA extras (React HUD -> Cooldowns). All off by default (user, 2026-08-29).
    reactKcProcGlow        = false,     -- KC slot: Blizzard action-button overlay glow while the proc is up (else the static border)
    kcActionBarGlow        = false,     -- glow the real action-bar button(s) holding Kill Command while the proc is up (any HUD mode)
    reactRangeTint         = "off",     -- React grid slots whose spell is out of range: "off" | "red" | "grey"
    reactTileDim           = false,     -- a tile on cooldown or not usable: desaturated at 60% (the WA's condition 1)
    reactManaTint          = false,     -- a tile whose spell lacks mana: blue + desaturated (the WA's condition 4)
    -- Active-state highlight on the React grid (KC keeps its own
    -- reactKcProcGlow override above; these style every other lit tile).
    reactActiveStyle       = "border",  -- "border" | "glow" | "none"
    reactActiveColor       = { 0.00, 0.90, 0.90, 1.00 },
    reactActiveSize        = 3,
    reactActiveFit         = "overflow", -- "overflow" | "contained"
    -- false = the built-in REACT_CD_ROWS layout; a table of 3 key arrays
    -- ({ {row1 keys}, {row2}, {row3} }) once the user edits the rows on the
    -- React HUD tab. Row heights/styles stay fixed; only membership + order
    -- are custom. Any catalog key (incl. trackedOnly and cooldownCustom
    -- entries) is valid.
    reactCdRows            = false,
    -- React buff row extras.
    reactBuffPositional  = true,        -- in-combat LotP / Grace-of-Air RANGE/MISSING labels
    -- Pet Frenzy on the proc row: "up" = present-only; "boss" = on a boss
    -- target (in combat, pet alive, Frenzy talented) the slot is always there,
    -- bright while up and greyed MISSING once it has been down 2 s; "missing"
    -- = that alert mode in every fight.
    reactBuffFrenzyMode  = "boss",
    -- Free position for the buff row ({ point, relPoint, x, y } CLUSTER-relative,
    -- reactAspectIconPos convention -- a moved row still follows the HUD and
    -- inherits reactScale); false = the default weld above the cluster. Written
    -- by drag / nudge pad in /nock unlock; the pad's reset re-welds.
    reactBuffRowPos      = false,
    reactBuffDisabled    = {},          -- ["mendPet"|"feedPet"|"intimidation"|"lotp"|"feign"|"misdirect"|"grace"|"windfury"|"frenzy"|"movein"] = true → hide
    reactBuffCustom      = {},          -- extra proc buff spellIDs (array), exact-ID matched like IMPORTANT_IDS
    -- React corner status icons (UI/Frame_ReactCorners.lua): the reference
    -- WeakAura's aspect (top-left) and Hunter's Mark (top-right) flanking the
    -- cluster. Off by default — the Aspect warning already covers the first
    -- and says it louder; these exist for WA parity.
    reactShowAspectIcon  = false,
    reactShowMarkIcon    = false,
    reactCornerIconSize  = 42,          -- edge length px, both icons
    reactCornerIconX     = 30,          -- gap from the cluster's side edge (mirrored)
    reactCornerIconY     = 50,          -- gap from the cluster's top edge to the icon's bottom
    -- Per-icon free positions ({ point, relPoint, x, y } CLUSTER-relative, so
    -- a moved icon still follows the HUD and inherits reactScale); false = the
    -- mirrored corner weld above. Written by drag / nudge pad in /nock unlock;
    -- the pad's reset re-welds (medallionPos convention).
    reactAspectIconPos   = false,
    reactMarkIconPos     = false,
    -- React fill directions. Auto bar's reference look is the two halves
    -- converging on the shot moment; ltr/rtl swap it for a single fill.
    reactDirAuto         = "converge",  -- "converge" | "ltr" | "rtl"
    reactDirMelee        = "ltr",       -- "ltr" | "rtl"
    -- React skin overrides (React HUD tab → Skin). Defaults = the reference
    -- WA look; "Reset skin" writes these values back. Colors positional
    -- {r,g,b,a} (getColor/setColor convention).
    -- React-scoped media. "" = the reference skin (flat WHITE8X8 fills, Friz
    -- Quadrata text); an LSM name restyles the React bars/cast bar/slot texts
    -- WITHOUT touching the classic HUD's barTexture/fontFace. reactFont, when
    -- set, also overrides the CD grid's text (which otherwise follows the
    -- global fontFace).
    reactBarTexture      = "",
    reactFont            = "",
    -- Base React text size (reference 9 = no change). Applied as a delta so
    -- proportions hold: small labels stay 2 under, slot text keeps tracking
    -- the icon edge, grid text shifts off its own overlay size.
    reactFontSize        = 9,
    reactAutoH           = 14,          -- auto bar height px
    reactMeleeH          = 12,          -- melee bar height px
    reactRangeH          = 12,          -- range bar height px
    reactManaH           = 12,          -- mana bar height px
    reactCastH           = 16,          -- cast bar height px (also the icon box edge)
    reactColorAutoFill      = { 1.00, 0.84, 0.00, 1.00 },  -- gold converge halves
    reactColorMeleeReady    = { 0.15, 0.68, 0.38, 1.00 },  -- Raptor ready (green)
    reactColorMeleeAuto     = { 0.55, 0.75, 1.00, 1.00 },  -- auto-only weave (light blue)
    reactColorManaFill      = { 0.20, 0.55, 1.00, 1.00 },
    reactColorCastFill      = { 0.40, 0.70, 1.00, 1.00 },
    reactColorRangeDeadzone = { 0.68, 0.18, 0.20, 1.00 },  -- MELEE band (red)
    reactColorRangeSweet    = { 0.85, 0.66, 0.00, 1.00 },
    reactColorRangePerfect  = { 0.17, 0.78, 0.11, 1.00 },  -- past PERFECT_AT (green)
    reactColorRangeClose    = { 0.00, 0.83, 0.75, 1.00 },  -- CLOSE + finding drain fill
    reactColorRangeResync   = { 1.00, 0.58, 0.10, 1.00 },
    reactRangeDividerWidth  = 1,                            -- range bar centre divider width px
    reactColorRangeDivider  = { 1.00, 1.00, 1.00, 0.90 },   -- range bar centre divider (melee boundary)
    -- React Auto Shot bar marks. Defaults reproduce the reference constants in
    -- Frame_ReactCluster exactly, so exposing them changes nothing until you
    -- touch one. Deliberately NOT the classic clipTick*Color keys: React runs
    -- its own skin channel, so the two HUDs can be styled apart.
    reactColorTickSteady    = { 1.00, 0.10, 0.10, 1.00 },  -- Steady clip threshold
    reactColorTickMulti     = { 1.00, 0.65, 0.10, 1.00 },  -- Multi/instant clip threshold
    reactColorTickWindup    = { 0.85, 0.85, 0.85, 0.80 },  -- wind-up commit landmark
    reactColorBracket       = { 1.00, 1.00, 1.00, 0.35 },  -- eWS profile-bound marks
    -- Widths are DEVICE pixels (real screen pixels), converted through the
    -- bar's effective scale. 1 = a true hairline at any UI scale.
    reactTickSteadyWidth    = 1,
    reactTickMultiWidth     = 1,
    reactTickWindupWidth    = 1,
    reactBracketWidth       = 1,
    -- GCD divider on the React Auto Shot bar. The only MOVING mark on that bar:
    -- it runs the GCD's own progress across the bar the way the gold fill runs
    -- the swing, following reactDirAuto (converge = one line in from each edge,
    -- ltr/rtl = a single line from the fill's origin edge). Off by default —
    -- a line sweeping the swing bar is a real change to how the HUD reads.
    reactShowGcdDivider     = false,
    reactGcdDividerWidth    = 1,                            -- GCD divider width, device px
    reactColorGcdDivider    = { 0.62, 0.35, 0.98, 1.00 },   -- GCD divider (purple)
    -- FluffyHUD (hudMode = "fluffy", UI/Frame_FluffyCluster.lua): the third
    -- look — a compact cluster of thin flat bars: a transient cast bar
    -- welded above (hidden while nothing casts), the React-style converge
    -- Auto Shot bar with breakpoint ticks, the fluffy shot windows as two
    -- rows (ranged + melee), the range finder, and an optional cooldown
    -- icon row welded below (grows downward).
    -- Same skin channel idea as React: a fixed reference skin (the FLUFFY
    -- table in the frame file), every color/height overridable here, media
    -- via its own two keys; the classic LSM registries do not apply. The
    -- classic show*/shotBars*/rotationMode keys are ignored in this mode —
    -- element visibility lives on the fluffyShow* keys. Toggle: /nock fluffy.
    fluffyWidth          = 320,         -- cluster/grid width in px (wider than React by design)
    fluffyScale          = 1.0,         -- shared per-row scale (cluster + CD row)
    fluffyCastH          = 14,          -- transient cast bar height px
    fluffySwingH         = 12,          -- Auto Shot bar height px
    fluffyRangedH        = 18,          -- ranged shot-window lane height px
    fluffyMeleeH         = 8,           -- melee weave lane height px
    fluffyRangeH         = 12,          -- range finder height px
    fluffyShotWindow     = 6.0,         -- shot-lane lookahead seconds
    fluffyShowCast       = true,        -- the transient cast bar above the cluster
    fluffyShowAutoShotCast = true,      -- wind-up drawn as a cast (render-edge gate)
    fluffyShowSwing      = true,
    fluffyShowRanged     = true,
    fluffyShowMelee      = true,
    fluffyShowRange      = true,        -- bottom of the stack, above the CD row
    fluffyShowGrid       = false,       -- the 6-icon cooldown grid row (opt-in)
    -- Auto Shot bar extras (FluffyHUD → Auto Shot Bar; React's exact set).
    -- The wind-up commit mark follows the shared showWindupMark key.
    fluffyShowNotation   = true,        -- rotation notation on the bar's right edge
    fluffyShowClipTicks  = true,        -- the vertical Steady/Multi clip tick pairs
    fluffyShowDelay      = false,       -- the +x.xx late-shot readout (opt-in)
    fluffyShowBrackets   = false,       -- eWS rotation-bracket marks (opt-in)
    fluffyShowGcdDivider = false,       -- moving GCD divider (opt-in)
    fluffyDirAuto        = "converge",  -- "converge" | "ltr" | "rtl"
    fluffyBuffRows       = true,        -- the procs row (ReactBuffs' fluffy host)
    fluffyBuffRowPos     = false,       -- false = weld above the cluster; else saved point
    fluffyCdKeys         = false,       -- false = seeded row {KC,Arc,MS,Raptor,Spec,RF}
    fluffyCooldownDisabled = {},        -- ["<key>"] = true → hide that CD slot
    -- Active-state highlight on the Fluffy CD row (per HUD; the shared
    -- reactKcProcGlow still overrides the KC tile to the overlay glow).
    fluffyActiveStyle    = "border",    -- "border" | "glow" | "none"
    fluffyActiveColor    = { 0.00, 0.90, 0.90, 1.00 },
    fluffyActiveSize     = 3,
    fluffyActiveFit      = "overflow",  -- "overflow" | "contained"
    fluffyBarTexture     = "",          -- "" = reference flat fill
    fluffyFont           = "",          -- "" = reference font
    fluffyFontSize       = 9,
    -- Colors default to the reference constants exactly (FLUFFY table in
    -- Frame_FluffyCluster), so exposing them changes nothing until touched.
    -- The lane palette mirrors shotBarsColor*, the rest React's channel.
    fluffyColorCastFill   = { 0.40, 0.70, 1.00, 1.00 },
    fluffyColorSwingFill  = { 1.00, 0.84, 0.00, 1.00 },
    fluffyColorTickSteady = { 1.00, 0.10, 0.10, 1.00 },
    fluffyColorTickMulti  = { 1.00, 0.65, 0.10, 1.00 },
    fluffyColorTickWindup = { 0.85, 0.85, 0.85, 0.80 },
    fluffyColorGcdDivider = { 0.62, 0.35, 0.98, 1.00 },     -- moving GCD divider (purple)
    fluffyColorBracket    = { 1.00, 1.00, 1.00, 0.35 },     -- eWS bracket marks
    fluffyColorSteady     = { 0.988, 0.596, 0.012, 0.85 },  -- safe Steady window (orange)
    fluffyColorQueue      = { 0.988, 0.596, 0.012, 0.38 },  -- wind-up queue window (dim)
    fluffyColorQueueLive  = { 0.20, 0.90, 0.35, 0.90 },     -- queue open NOW (green)
    fluffyColorMulti      = { 0.012, 0.525, 0.996, 0.85 },  -- Multi in the clip zone (blue)
    fluffyColorArcane     = { 0.686, 0.478, 0.773, 0.85 },  -- Arcane (purple)
    fluffyColorDanger     = { 0.851, 0.118, 0.118, 0.50 },  -- clip band (red)
    fluffyColorRaptor     = { 0.153, 0.682, 0.376, 0.85 },  -- Raptor-ready weave (green)
    fluffyColorWeaveAuto  = { 1.00, 1.00, 1.00, 0.70 },     -- auto-only weave (white)
    fluffyColorSpark      = { 1.00, 1.00, 1.00, 1.00 },     -- Auto Shot spark
    fluffyColorRangeDeadzone = { 0.68, 0.18, 0.20, 1.00 },  -- MELEE band (red)
    fluffyColorRangeSweet    = { 0.85, 0.66, 0.00, 1.00 },
    fluffyColorRangePerfect  = { 0.17, 0.78, 0.11, 1.00 },  -- past PERFECT_AT (green)
    fluffyColorRangeClose    = { 0.00, 0.83, 0.75, 1.00 },
    fluffyColorRangeResync   = { 1.00, 0.58, 0.10, 1.00 },
    -- Weave rotation notation: when ON, the rotation label auto-switches to the
    -- weave pattern (e.g. "6:9:1:1 3w") while you're in weaving range with a 2H,
    -- and back to the turret pattern at range. OFF = turret notation always.
    weaveNotationEnabled = false,
    -- Per-notation display-name overrides, keyed by the BUILT-IN notation string
    -- ("1:1", "6:9:1:1 3w", ...). Blank/absent = show the built-in. Display-only:
    -- state.rotation keeps the real notation, so the engine and /nock's debug
    -- dump are unaffected. AceDB deep-copies table defaults per profile, so a
    -- profile reset restores {} rather than sharing this one.
    rotationLabels     = {},
    -- Per-notation label colors ({r,g,b,a}, same BUILT-IN-notation keying as
    -- rotationLabels). Absent = each render site's own default color. Applied
    -- at the React notation, classic Auto Shot bar and Shot Bars labels via
    -- Profiles:DisplayColor.
    rotationLabelColors = {},
    shotBarsWindow     = 6.0,             -- lookahead seconds
    shotBarsRotationText = true,          -- rotation notation label on the Shot Bars (far-right)
    shotBarsHeight     = 28,              -- row height in px
    -- Melee/weave strip height INSIDE that row (simplified bar only). The pixels
    -- come out of the ranged lane, so shotBarsHeight — and therefore the HUD grid
    -- row and everything below it — never moves. 4 = the old fixed strip.
    -- Legacy Shot Bars split the two lanes proportionally and ignore this.
    shotBarsMeleeHeight = 4,
    shotBarsReverse    = false,           -- false = time flows right→left (now/fire at LEFT, default); true = left→right (now/fire at RIGHT)
    shotBarsShowMulti  = true,
    shotBarsShowArcane = true,
    -- Melee weave lane (Fluffy's bottom row): the green window where you can
    -- step in for a Raptor / auto-attack and still be back before the shot.
    -- (Key name kept for profile compatibility; it now gates the melee row.)
    shotBarsShowRaptor = true,
    -- Unified-UI toggle: in "bars" mode, also keep the 6-icon next-action
    -- helper row (above the bars) instead of replacing it. Off = bars replace
    -- the helper (original behaviour).
    shotBarsShowHelper = false,
    shotBarsColorSteady = { 0.988, 0.596, 0.012, 0.85 },  -- orange
    shotBarsColorMulti  = { 0.012, 0.525, 0.996, 0.85 },  -- blue
    shotBarsColorArcane = { 0.686, 0.478, 0.773, 0.85 },  -- purple
    shotBarsColorRaptor = { 0.153, 0.682, 0.376, 0.85 },  -- green: Raptor-ready weave
    shotBarsColorWeaveAuto = { 1.00, 1.00, 1.00, 0.70 },  -- white: auto-attack-only weave (Raptor on CD)
    shotBarsColorDanger = { 0.851, 0.118, 0.118, 0.50 },  -- red: the clip band
    -- Dim Steady orange: the queue window right before the shot. Same action as
    -- the bright orange, different mechanism — the press is held and comes out
    -- after the arrow — so it reads as "Steady, softer" rather than a new colour.
    shotBarsColorQueue  = { 0.988, 0.596, 0.012, 0.38 },
    -- ...and green the moment the wind-up actually starts, i.e. while the queue
    -- window is LIVE. That is the whole point of the lane: a press right now is
    -- free. Brighter than the melee lane's Raptor green so the two don't read as
    -- the same signal in different rows.
    shotBarsColorQueueLive = { 0.20, 0.90, 0.35, 0.90 },
    shotBarsColorSpark  = { 1.00,  1.00,  1.00,  1.00 },  -- white

    -- EXPERIMENTAL — "V3" next-action display (feature-flagged, all off by
    -- default; toggle both at once with /nock v3). Picked from the design-bench
    -- mockups: the medallion owns WHAT to press, the simplified bar owns WHEN.
    medallionEnabled   = false,  -- big center-screen next-action icon: spell to press,
                                 -- native cooldown swipe for GCD/cast lockout, glow at
                                 -- the press moment, red HOLD state during the clip zone
    medallionSize      = 64,     -- medallion icon size in px
    medallionRing      = true,   -- countdown ring around the icon (drains to empty at the
                                 -- press moment; red = time until the auto fires in HOLD)
    -- Countdown-dial (ring) colors. Defaults reproduce the previously hardcoded
    -- look; customizable in the Experimental tab.
    medallionRingColorPress = { 1, 1, 1, 0.85 },       -- lockout / "press soon" swipe (white)
    medallionRingColorHold  = { 0.85, 0.12, 0.12, 0.9 }, -- HOLD (Auto Shot wind-up) swipe (red)
    medallionRingTrackColor = { 1, 1, 1, 0.08 },       -- static background ring (faint white)
    medallionPos       = false,  -- saved drag position { point, relPoint, x, y }; false = default (screen center, below character)
    shotBarsSimplified = true,   -- BASELINE since 1.0.14: tall ranged lane, GCD/cast shade
                                 -- sweeping from the fire edge, hard clip-breakpoint tick,
                                 -- melee lane squeezed to a 4px timeline strip, notation
                                 -- text dropped. false = the legacy multi-lane bar
                                 -- (Rotation tab → "Use legacy Shot Bars").
    -- EXPERIMENTAL — Release bar (UI/Frame_ReleaseBar.lua): the Aerthax retry
    -- grid drawn live under the HUD (both looks) while the weave key is held.
    -- Cost math is Nock.ReleaseCost in Core/State.lua; the model is unverified
    -- on Anniversary, so everything ships off and behind the Experimental tab.
    releaseBarEnabled = false,
    -- ON for the trial period: show whenever an Auto Shot swing is tracked,
    -- not only during weave holds — the M1 verification needs eyes on the bar
    -- through whole dummy sessions. Off = the intended hold-only behavior.
    releaseBarAlways  = true,
    releaseBarHeight  = 14,    -- px
    releaseBarLabels  = true,  -- the +0.32s cost readout on the right edge
    releaseBarNotches = true,  -- green hairlines at the free notches
    -- Weave Bind (Modules/WeaveBind.lua): hold-to-melee-weave override keybind.
    -- Experimental, off by default. The macro bodies are user-editable copies
    -- of the Constants defaults ("Restore default macros" writes them back).
    weaveBindEnabled   = false,
    weaveBindKey       = "",
    weaveBindMacroDown = C.WEAVE_BIND_MACRO_DOWN,
    weaveBindMacroUp   = C.WEAVE_BIND_MACRO_UP,
    -- Garment gate autopilot: when the weave macros gate lines on a
    -- Shirt/Tabard conditional, put the garment into its boss state on
    -- targeting a raid boss out of combat (OFF for [noequipped:...] lines,
    -- ON for [equipped:...] lines), and — separately toggleable — restore
    -- the everyday state once no living boss is targeted.
    weaveBindGarmentAutoFlip    = false,
    weaveBindGarmentAutoReequip = true,
    -- Weave-coach outcome sound cues (Modules/WeaveCoach.lua): hit landed
    -- ("start moving out") and clear-to-release. LSM "sound" names; "None" =
    -- silent. Played on the dead-zone sound channel (deadZoneSoundChannel).
    -- Withdrawn from the GUI (their options carry `hidden`), so the master flag
    -- ships OFF and MigrateProfile turns it off once for existing profiles —
    -- otherwise anyone who had picked a sound would be stuck with it. The sound
    -- names are kept so re-exposing the section restores their choices.
    weaveCoachSoundsEnabled = false,
    weaveCoachStruckSound   = "None",
    weaveCoachReleaseSound  = "None",
    weaveCoachSoundsRetired = false,  -- one-time latch for the disable-on-upgrade migration
    -- Mailbox module (Modules/Mailbox.lua): snowball mail logistics.
    mailboxEnabled   = true,
    mailboxKeepCount = 0,   -- snowballs kept in bags on a send run (whole stacks, rounded up)
    -- Practice mode (Utilities -> Practice; /nock practice).
    practiceQueueWindow   = 0.4,
    practiceReactionMs    = 150,
    practiceLatencyMs     = nil,    -- nil = your live latency
    practiceToast         = true,
    practiceToastSec      = 0.8,
    practiceToastSize     = 22,
    -- manual overrides: steady/multi/arcane/rf/spec/t1/t2/drums/pot = "KEY"
    practiceKeys          = {},
    -- Practice-only proc keys (the Keys page / Options -> Practice -> Keys):
    -- Lust / Drums / Pot / DST / RF / QS -> a key that pops the proc on the sim.
    practiceProcKeys      = {},
    practicePanelPos      = nil,
    -- Weave drill. "move" reads your real footwork by speed alone (run =
    -- closing, backpedal = retreating, standing holds); "key" lets the engine
    -- step in and out for you.
    practiceFootwork      = "move",
    practiceStepTime      = 0.3,    -- key footwork: seconds per leg
    practiceStartDistance = 7,      -- yards to the virtual target at the pull
    practiceRearmPulse    = nil,    -- nil = Constants.RETRY_PULSE (the live retry grid)
    practiceRearmWindupAfterReady = true,
    practiceMeleeRetryPulse = 0.5,  -- server melee re-check after stepping in
    practiceLegMaxSec     = 0.4,    -- a weave leg slower than this is WEAVE SLOW
    -- Procs, scenarios and the opener drill (phase 5). practiceScenario names
    -- a built-in (Modules/PracticeEngine.lua E.SCENARIOS) or one of the user's
    -- own lines in practiceScenarioText; the seed makes a fight repeatable.
    practiceQuickShots    = true,
    practiceSeed          = 1,
    practiceScenario      = "Clean French",   -- built-in or user scenario name
    practiceScenarioOpen  = "turret",         -- Scenarios page: the one display group that is open (accordion)
    practiceScenarioText  = "",               -- user scenarios, one per line (DSL)
    practiceOpenerAnchor  = "pull",           -- pull | lust | drums | pot | rf
    practiceOpenerGcds    = 2,
    practiceOpenerSteadySec = 0.5,
    practiceOpenerCds     = { RF = true, Spec = true, T1 = true, T2 = true, Drums = true, Pot = true },
    -- The fight review as a whole, OFF while the practice engine is being
    -- tuned (R8b, user's call): a review is a verdict on a fight, and a verdict
    -- from an engine still under the knife teaches the wrong lesson. Off hides
    -- the header's Review button and stops the window opening itself when a
    -- fight ends; every other way in still answers, and `/nock practice report`
    -- (the copybox) is untouched. All the review code stays put — this is a
    -- switch, not a removal, and the Options toggle turns it back on.
    practiceReviewEnabled = false,
    -- Review window (UI): pixels per second and lane width. Live following is
    -- the conveyor's job — the review is the post-fight read.
    practiceTimelinePps   = 80,
    practiceTimelineOkMarks = false,   -- also mark GOOD / WEAVE checkmarks
    practiceTimelinePos   = nil,
    -- Conveyor strip (UI): the live three-lane view that flows past a fixed hit
    -- line. `Hit` is where that line sits as a fraction of the lane width, so
    -- `Past`/`Future` are MINIMUM seconds of history/lookahead either side of
    -- it: the window the stage actually shows is whatever its width buys at
    -- `Pps`, which is why dragging the undocked stage wider shows more seconds
    -- rather than stretching the notes.
    practiceConveyorPps    = 90,
    practiceConveyorPast   = 2,
    practiceConveyorFuture = 4.5,
    practiceConveyorHit    = 0.30,
    practiceConveyorDocked = true,     -- lives in the practice panel until undocked
    practiceConveyorPos    = nil,
    -- Undocked stage width, in UI units. Its own key rather than the review
    -- window's `practiceTimelineWidth`: the two windows are different shapes
    -- with different jobs, and the stage's is drag-set from its right edge
    -- (clamped 480-1600) rather than typed into Options. Docked, the panel's
    -- own width wins and this is not read at all.
    practiceConveyorW      = 960,
    -- The stage's metronome: four dots at the right of the coach line, flashing
    -- gold on each auto release and green when the weave gap opens, each with a
    -- short cue. Off turns the whole thing off, dots included — it is one
    -- instrument. Never sounds while a fight is armed but not yet pulled.
    practiceMetronome      = true,
    -- Focus (shell step 3): the stage alone on the HUD, when pulled out by
    -- hand (the Focus button, the keybind); Start can go there by itself.
    -- `quiet focus` drops its coach line there (pops only).
    practiceFocusOnStart   = false,
    practiceQuietFocus     = false,
    -- The weave log beside the stage in Focus: one row per weave (icon,
    -- legs, re-arm, verdict). Off by default; its own saved spot.
    practiceWeaveLog       = false,           -- the weave log panel IN PRACTICE (the toolbar's Log button)
    weaveLogPanel          = false,           -- the weave log panel in REAL fights (/nock weavelog panel, Options -> Weave Bind)
    practiceWeaveLogPos    = nil,
    -- Expert mode's combat log (the timeline of what you did): its own saved
    -- spot. The mode itself is not a setting -- the toolbar's Expert button,
    -- the keybind, `/nock practice expert`.
    practiceCombatLogPos   = nil,
    -- The stage's palette (Practice -> Conveyor & review -> Colours): every
    -- lane item colour, applied into Nock.PracticeTimeline.COLORS by
    -- Practice:ApplyColors. Defaults are the shipped palette.
    -- Auto is the metronome, not a press: grey, so the gold stays for the hit
    -- line and the verdicts (P3 polish, the Conveyor Skins pick).
    practiceColorAuto   = { 0.55, 0.57, 0.60 },
    practiceColorSteady = { 0.35, 0.65, 1.00 },
    practiceColorMulti  = { 1.00, 0.60, 0.20 },
    practiceColorArcane = { 0.80, 0.40, 1.00 },
    practiceColorRaptor = { 1.00, 0.30, 0.30 },
    practiceColorWhite  = { 0.90, 0.90, 0.90 },
    practiceColorQS     = { 0.30, 1.00, 0.40 },
    practiceColorRF     = { 1.00, 0.85, 0.20 },
    practiceColorLust   = { 1.00, 0.30, 0.30 },
    practiceColorDrums  = { 0.70, 0.50, 0.30 },
    practiceColorDST    = { 0.50, 0.80, 1.00 },
    practiceColorPot    = { 0.90, 0.40, 0.90 },
    practiceColorKC     = { 1.00, 0.50, 0.10 },
    practiceColorWindow = { 0.30, 1.00, 0.30 },
    practiceColorWarn   = { 1.00, 0.80, 0.20 },
    practiceColorBad    = { 1.00, 0.30, 0.30 },
    -- The stage's STYLE (Practice -> Conveyor & review -> Stage style), the
    -- levers picked in the Conveyor Skins explorer (2026-08-25). Every one is a
    -- visual decision only; the plan behind the stage is untouched by any of
    -- them. Read by UI/Frame_PracticeConveyor.lua's ApplyStyle; also set from
    -- `/nock practice style <lever> <value>`.
    practiceStyleNote        = "glass",     -- glass | solid | outline
    practiceStyleNext        = "both",      -- both (bright + chip) | bright | chip | word
    practiceStyleMove        = "ramp",      -- ramp | solid | edge
    practiceStyleHit         = "column",    -- column | line
    practiceStylePast        = "fade",      -- fade | keep
    practiceStyleLanes       = "zebra",     -- zebra | lines | none
    practiceStyleAutoTick    = "hairline",  -- hairline | notch | bar
    practiceStyleWindup      = "faint",     -- faint | normal | strong | off
    practiceStyleWindupScope = "auto",      -- auto | cast | all
    -- Scenario picker window (/nock practice scenarios): position only; the
    -- pick itself is practiceScenario above.
    practiceScenariosPos   = nil,
    -- Lesson window (/nock practice lesson, the header's Lesson button, the
    -- review's "Open lesson step N"): position only — everything it draws is
    -- derived from the current plan.
    practiceLessonPos      = nil,
    -- Drill ladder progress (the lesson window's side panel). `done` is a set
    -- of drill ids (Modules/PracticeLadder.lua), `current` the one the ladder
    -- is pointing at, and `loaded` (no default — absent means none) the drill
    -- the scenario pick currently belongs to, so a /reload keeps counting the
    -- passes of the drill you are in the middle of. Per character, like every
    -- other practice key.
    practiceLadder         = { done = {}, current = "beat" },
    -- First-run hint bars, one key per window: absent/false = the bar is still
    -- showing, true = the player has dismissed it for good. A set rather than a
    -- flag per window so a new window costs a key, not a default. Per character,
    -- like every other practice key -- the second hunter is a first run too.
    practiceHints          = {},
    -- Practice window scale. Every size in the five practice windows is a UI
    -- unit at the frame's own scale. 100 % (user, 2026-08-27); the slider
    -- reaches 300 % for big screens, and the workbench caps itself to fit
    -- the screen. Applied by Nock.UI.RegisterPracticeScale /
    -- ApplyPracticeScale (UI/Widgets.lua) with SetScale on the top-level
    -- frame only; children inherit.
    practiceScale          = 1.0,
    -- EARLY is the OPENER verdict: a cooldown fired before its anchor. It is
    -- not the "pressed too early" counter — a press made before a shot is
    -- ready is a scorecard number (NOT_READY), never a verdict, so that one
    -- has no row here.
    practiceVerdicts      = { CLIP = true, LATE = true,
                              STEADY_WONT_FIT = true, CATCHUP_MISSED = true, GOOD = true,
                              WEAVE_MISSED = true, DEAD_ZONE = true, REARM = true,
                              WEAVE_SLOW = true, WEAVE_OK = true, EARLY = true },
  },

  -- Per-character runtime memos (survive /reload mid-cycle).
  char = {
    -- Garment autopilot memo: false, or { itemID, link, slot, garment, dir }
    -- for a gate garment Nock changed and may still need to restore. dir is
    -- the arming direction: "off" = Nock removed it ([noequipped:...]
    -- macros), "on" = Nock equipped it ([equipped:...] macros).
    garmentFlip = false,
    -- Last mailbox send recipient chosen on this character (session prefill).
    mailboxLastRecipient = "",
    -- True while the setup wizard is open (it unlocks every frame). If a
    -- /reload or logout kills the wizard before Teardown can relock, the
    -- next login sees this and restores the locked state.
    wizardLockPending = false,
  },

  -- Account-wide caches. Weapon/ammo tooltip parsing is expensive, so the
  -- result is cached by itemID forever (mirrors Fluffy's FluffyDBPC cache).
  global = {
    itemCache = {
      ranged = {},  -- [itemID] = { dmgMin, dmgMax, speed }
      ammo   = {},  -- [itemID] = dps
    },
    -- Mailbox send recipients (ordered, original casing). Account-wide on
    -- purpose: the hunter and the banker alt share one list.
    mailboxRecipients = {},
    -- First-run onboarding latch. false until the wizard has auto-opened once,
    -- then { seenVersion = "x.y.z" }. Account-wide so a second hunter doesn't
    -- get the wizard again. Clear it to replay the first-run experience.
    onboarding = false,
  },
}

function Nock:GetDefaultPosition()
  return { point = "CENTER", relPoint = "CENTER", x = 0, y = -150 }
end
