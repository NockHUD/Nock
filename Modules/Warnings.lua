-- Modules/Warnings.lua
-- Produces prioritized warnings into state.warnings. The render layer (Frame_Warnings)
-- shows them as standalone icon-squares anchored to UIParent (top-of-screen alert area).
--
-- Each warning entry: { id, severity = "red"|"amber"|"blue", text, icon (texture file ID or path) }

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Warnings = Nock:NewModule("Warnings", "AceEvent-3.0")
local C = Nock.Constants

local SEVERITY_RANK = { red = 3, amber = 2, blue = 1 }

-- Cache flags written by handlers defined near the top of the file and read
-- by the checks near the bottom: declared HERE so both see the same local
-- (declared lower down, the handlers' writes went to globals and the caches
-- never invalidated -- caught by a bytecode GSET scan, 2026-08-30).
local _gateKnown = false     -- the shirt-gate direction is parsed (RebuildIdSets clears)
local _garmentDirty = true   -- the garment slot needs a re-read (equipment / item info)

local STEAM_TONK_ITEM        = C.STEAM_TONK_ITEM
local SATURATION_EWS         = 0.7

-- Feign Death resist state (shared upvalues). Declared here — above OnEnable /
-- OnCombatLog / checkFDResist, all of which reference them — so every reference
-- binds to these same locals. Declared lower down, the handlers defined earlier
-- would silently bind to globals instead (a `local` is only visible to code
-- lexically after it): the latch write and its reader would desync and the
-- warning would never fire. _fdResistUntil is the latch expiry; _playerGUID
-- caches the player GUID for the combat-log filter.
local _fdResistUntil
local _playerGUID

-- Plays the LSM sound named by a profile key. No-op when unset/"None"/missing LSM.
-- Warning cues always play on Master, matching the Options "Preview" buttons —
-- so what you audition is what you get in combat.
local function playWarnSound(profileKey)
  local p = Nock.db and Nock.db.profile
  local name = p and p[profileKey]
  if not name or name == "" or name == "None" then return end
  local LSM = LibStub("LibSharedMedia-3.0", true)
  if not LSM then return end
  local path = LSM:Fetch("sound", name)
  if path and PlaySoundFile then PlaySoundFile(path, "Master") end
end

local function threshold(key, fallback)
  local p = Nock.db and Nock.db.profile
  if p and p[key] ~= nil then return p[key] end
  return fallback
end

-- enabledKey returns the named flag from the profile (defaults to true so a
-- missing key keeps the warning visible — backwards compatible).
local function isEnabled(key)
  if not key then return true end
  local p = Nock.db and Nock.db.profile
  if not p then return true end
  local v = p[key]
  if v == nil then return true end
  return v and true or false
end

-- Cascade entries can declare either a single `id` or an `ids` array of variants
-- (warlock Healthstones have multiple IDs depending on the Improved Healthstone
-- talent rank of the conjurer).
local HEALTH_ITEMS = {
  -- Master Healthstone variants (Improved Healthstone 0/1/2 talent ranks) + older Major.
  { ids = { 22103, 22104, 22105, 9421 }, label = "Healthstone" },
  { id  = 33092,                           label = "Heal Inj" },        -- Healing Potion Injector
  { id  = 22829,                           label = "Healing Pot" },     -- Super Healing Potion
  { id  = 22797,                           label = "Nightmare Seed" },  -- Nightmare Seed
}

local MANA_ITEMS = {
  { id = 20520, label = "Dark Rune" },
  { id = 33093, label = "Mana Inj"  },  -- Mana Potion Injector
  { id = 22832, label = "Mana Pot"  },
}

-- Sapper Charge cascade: prefer Super Sapper Charge (23827), fall back to
-- Goblin Sapper Charge (10646). Mirrors the Cooldowns "Sapper" altItem slot.
local SAPPER_ITEMS = {
  { ids = C.SAPPER.ITEMS, label = "Sapper" },
}

-- Every cascade entry carries `ids` (pickCascade used to build a throwaway
-- { entry.id } per single-id entry on every refresh below the mana/HP threshold).
local function withIds(list)
  for _, e in ipairs(list) do if not e.ids then e.ids = { e.id } end end
  return list
end
withIds(HEALTH_ITEMS)
withIds(MANA_ITEMS)
withIds(SAPPER_ITEMS)

local mendPetName
local mendPetIcon
local bloodlustIcon
local wingClipName
local growlName
local primalInstinctName
local devilsaurIcon

-- Parsed { [id] = true } caches for the user-editable ID-list warnings
-- (wrong-trinket item IDs, Tranq-able enrage spell IDs). Rebuilt at OnEnable
-- and on NOCK_VISUALS_CHANGED so Options edits apply without /reload.
local badTrinketSet = {}
local enrageIdSet = {}

-- Parse a comma/newline-separated ID list (a profile string) into a
-- { [number] = true } lookup. Mirrors Helpers.lua waPrefixes() but tonumber's
-- each token so the per-tick checks are single O(1) table reads.
local function parseIdSet(raw)
  local out = {}
  if type(raw) == "string" then
    for token in raw:gmatch("[^,\n]+") do
      local n = tonumber(token:match("^%s*(.-)%s*$"))
      if n then out[n] = true end
    end
  end
  return out
end

-- { [useSpellId] = entry } map of utility-item-use-spells to their UTIL_ITEMS entry.
-- Built lazily and rebuilt on GET_ITEM_INFO_RECEIVED since GetItemSpell needs cached item info.
local utilLookup

local function spellIcon(id)
  if GetSpellInfo then
    local _, _, icon = GetSpellInfo(id)
    if icon then return icon end
  end
  return nil
end

local function itemIcon(id)
  if C_Item and C_Item.GetItemIconByID then
    local i = C_Item.GetItemIconByID(id)
    if i then return i end
  end
  if GetItemInfo then
    local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
    if icon then return icon end
  end
  return nil
end

local function getItemCount(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) end
  if GetItemCount then return GetItemCount(id) end
  return 0
end

-- Spell cooldown remaining (seconds). Same shape as getItemCdRemaining below,
-- but reads via C_Spell.GetSpellCooldown (on the Anniversary allowlist) with a
-- bare-global fallback for older builds. Treats anything ≤ GCD (1.5s) as 0 so
-- "off cooldown" gates aren't fooled by the global cooldown leaking through.
local function getSpellCdRemaining(id)
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(id)
    if info then
      start    = info.startTime or 0
      duration = info.duration  or 0
    end
  elseif GetSpellCooldown then
    start, duration = GetSpellCooldown(id)
  end
  if not start or start == 0 then return 0 end
  if not duration or duration <= 1.5 then return 0 end
  return math.max(0, start + duration - GetTime())
end

local function getItemCdRemaining(id)
  local start, duration
  if C_Container and C_Container.GetItemCooldown then
    start, duration = C_Container.GetItemCooldown(id)
  elseif GetItemCooldown then
    start, duration = GetItemCooldown(id)
  end
  if not start or start == 0 then return 0 end
  if not duration or duration <= 1.5 then return 0 end
  return math.max(0, start + duration - GetTime())
end

local function pickCascade(items)
  local chosenReady, firstOwned
  for _, entry in ipairs(items) do
    local ids = entry.ids
    for _, id in ipairs(ids) do
      if getItemCount(id) > 0 then
        if not firstOwned then firstOwned = id end
        if not chosenReady and getItemCdRemaining(id) <= 0 then
          chosenReady = id
        end
      end
    end
  end
  return chosenReady or firstOwned
end

-- Melee-range probe (mirrors Modules/RangeFinder.lua's isMeleeInRange; the
-- Wing Clip range works on any attackable unit). Module discipline: the tiny
-- probe is replicated rather than reaching into RangeFinder's internals.
local function isMeleeInRange(unit)
  if C_Spell and C_Spell.IsSpellInRange then
    return C_Spell.IsSpellInRange(C.SpellID.WING_CLIP, unit) and true or false
  end
  if IsSpellInRange and wingClipName then
    return IsSpellInRange(wingClipName, unit) == 1
  end
  return false
end

-- TBC Classic has no continuous unit-distance API. CheckInteractDistance only
-- exposes coarse bands; index 2 ("Trade", ~11.1 yd) is the fixed sapper
-- detection radius — it clears a Sapper Charge's blast with a little leeway.
-- Deliberately NOT user-configurable (only the unit count is). Unlike a spell
-- range probe, CheckInteractDistance is distance-only and works on hostile
-- mobs as well as friendly players, so one probe covers both.
local SAPPER_CI_INDEX = 2  -- CheckInteractDistance "Trade" band ≈ 11.1 yd

local function inSapperRange(unit)
  if CheckInteractDistance then
    return CheckInteractDistance(unit, SAPPER_CI_INDEX) and true or false
  end
  return isMeleeInRange(unit)  -- fallback only if CheckInteractDistance is nil
end

-- Robust raid detection: IsInRaid() is unreliable on this client (returns
-- false in a raid → the friendly count would fall back to party1-4 = just
-- your 5-man subgroup). Also accept GetNumRaidMembers() (mirrors DebuffTracker).
local function isInRaidGroup()
  if IsInRaid and IsInRaid() then return true end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return true end
  return false
end

-- Counts HOSTILE mobs within the sapper radius (see inSapperRange), walked
-- off the active enemy nameplate registry. Enemy nameplates must be on.
-- (Friendly group members are deliberately NOT counted — on a raid boss the
-- whole raid is in range, which would make the count meaningless.)
--
-- Throttled: an advisory warning doesn't need a 30Hz nameplate sweep, so the
-- result is cached and the real scan runs at most every SCAN_INTERVAL.
local SCAN_INTERVAL = 0.25
local _scanAt, _scanCount = 0, 0

local function scanNearbyMeleeUnits()
  local n = 0
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local plates = C_NamePlate.GetNamePlates()
    if plates then
      for _, plate in ipairs(plates) do
        local u = plate.namePlateUnitToken
                  or (plate.UnitFrame and plate.UnitFrame.unit)
        if u and UnitExists(u) and UnitCanAttack("player", u)
           and not UnitIsDead(u) and inSapperRange(u) then
          n = n + 1
        end
      end
    end
  end
  return n
end

local function countNearbyMeleeUnits()
  local now = GetTime()
  if now - _scanAt >= SCAN_INTERVAL then
    _scanAt    = now
    _scanCount = scanNearbyMeleeUnits()
  end
  return _scanCount
end

-- Pet buff scan by localized name, optionally also by raw spell ID (10th
-- UnitBuff return) — the ID path covers single-rank buffs like Primal
-- Instinct even if the name resolution came up empty at OnEnable.
-- Aura reads go through Core/AuraCache.lua (every read allocates ~1.9 KB on
-- this client; this file used to walk the pet, the player three times and
-- the target on every refresh).
local AC = Nock.AuraCache

-- Warning records are POOLED by id: a check returns the same table each
-- refresh with its fields rewritten (the view diffs by field, never by
-- identity), so a warning that stays up allocates nothing at 10 Hz. Fields
-- not passed are cleared -- `remaining` in particular must not linger.
local POOL = {}
local function warn(id, severity, icon, text, remaining)
  local w = POOL[id]
  if not w then w = { id = id }; POOL[id] = w end
  w.severity, w.icon, w.text, w.remaining = severity, icon, text, remaining
  return w
end

-- Refresh's helpers, module-level (they were two closures per refresh).
local _list
local function add(w)
  if w then _list[#_list + 1] = w end
end
local function bySeverity(a, b)
  return (SEVERITY_RANK[a.severity] or 0) > (SEVERITY_RANK[b.severity] or 0)
end

local function petHasAura(name, id)
  if not AC or not UnitExists("pet") or not (name or id) then return false end
  if id and AC.BySpell("pet", id) then return true end
  return name and AC.ByName("pet", name) ~= nil or false
end

local function checkSteamTonk(state)
  if not isEnabled("warnSteamTonkEnabled") then return nil end
  if not UnitExists("pet") or UnitIsDead("pet") then return nil end
  local hp = UnitHealth("pet") or 0
  local hpMax = UnitHealthMax("pet") or 0
  if hpMax <= 0 then return nil end
  local pct = (hp / hpMax) * 100
  if pct >= threshold("steamTonkThreshold", 20) then return nil end
  if getItemCount(STEAM_TONK_ITEM) <= 0 then return nil end
  if getItemCdRemaining(STEAM_TONK_ITEM) > 0 then return nil end
  return warn("steamtonk", "red", itemIcon(STEAM_TONK_ITEM), "Steam Tonk", nil)
end

-- A raid boss: an attackable, alive target that is classified "worldboss" or
-- is "boss level" (UnitLevel == -1, the ?? skull). Covers TBC raid bosses
-- without hardcoding encounter IDs.
local function isBossTarget()
  if not (UnitExists and UnitExists("target")) then return false end
  if UnitCanAttack and not UnitCanAttack("player", "target") then return false end
  if UnitIsDead and UnitIsDead("target") then return false end
  if UnitClassification and UnitClassification("target") == "worldboss" then return true end
  if UnitLevel and UnitLevel("target") == -1 then return true end
  return false
end

local function checkSapperAoe(state)
  if not isEnabled("warnSapperAoeEnabled") then return nil end

  -- Final gate: raid only, on a boss, with enough hostile mobs clustered.
  if not isInRaidGroup() then return nil end
  if not isBossTarget() then return nil end

  local need = threshold("sapperMobCountThreshold", 3)
  if countNearbyMeleeUnits() < need then return nil end

  -- Only nag when a Sapper is actually throwable (owned AND off cooldown).
  -- pickCascade prefers a ready charge; re-checking the CD rejects the
  -- owned-but-on-cooldown fallback case.
  local chosenId = pickCascade(SAPPER_ITEMS)
  if not chosenId then return nil end
  if getItemCdRemaining(chosenId) > 0 then return nil end

  return warn("sapperAoe", "amber", itemIcon(chosenId) or 0, "Sapper", nil)
end

local function checkMendPet(state)
  if not isEnabled("warnMendPetEnabled") then return nil end
  if not UnitExists("pet") or UnitIsDead("pet") then return nil end
  local hp = UnitHealth("pet") or 0
  local hpMax = UnitHealthMax("pet") or 0
  if hpMax <= 0 then return nil end
  local pct = (hp / hpMax) * 100
  if pct >= threshold("mendPetThreshold", 50) then return nil end
  if petHasAura(mendPetName) then return nil end
  return warn("mendpet", pct < threshold("steamTonkThreshold", 20) and "red" or "amber", mendPetIcon or 132179, ("Pet %d%%"):format(pct), nil)
end

-- Devilsaur Tooth (item 19992): on use, the pet's next attack is a guaranteed
-- crit — the Primal Instinct buff sits on the pet until a crit consumes it.
-- Nags while a boss is targeted and that crit isn't loaded. Deliberately
-- ignores the trinket's 2-min cooldown: the warning means "the guaranteed
-- crit isn't up", actionable or not. Opt-in (default off).
local function checkDevilsaurTooth(state)
  if not isEnabled("warnDevilsaurEnabled") then return nil end
  if not UnitExists("pet") or UnitIsDead("pet") then return nil end
  if not isBossTarget() then return nil end
  if not GetInventoryItemID then return nil end
  local t1 = GetInventoryItemID("player", 13)
  local t2 = GetInventoryItemID("player", 14)
  if t1 ~= C.DEVILSAUR_TOOTH_ITEM and t2 ~= C.DEVILSAUR_TOOTH_ITEM then return nil end
  if petHasAura(primalInstinctName, C.SpellID.PRIMAL_INSTINCT) then return nil end
  -- Latched, not resolved at OnEnable: item info may not be cached at login.
  devilsaurIcon = devilsaurIcon or itemIcon(C.DEVILSAUR_TOOTH_ITEM)
  return warn("devilsaur", "amber", devilsaurIcon or 134071, "Devilsaur Tooth", nil)
end

-- Quiver almost empty. Reads the arrows physically in the quiver/ammo pouch
-- (state.ammo.quiver, published event-driven by UI/Frame_InfoRow.lua whether
-- or not the info row is shown) -- NOT state.ammo.total, which adds regular
-- bags and maker charges: a stack in the backpack does not feed the bow until
-- you move it. No quiver equipped -> nothing to say. No combat gate: running
-- dry mid-fight is exactly when the square earns its place.
local function checkQuiverLow(state)
  if not isEnabled("warnQuiverEnabled") then return nil end
  local a = state.ammo
  if not a or not a.hasQuiver then return nil end
  local n = a.quiver or 0
  if n >= threshold("quiverArrowThreshold", 400) then return nil end
  local icon = GetInventoryItemTexture and GetInventoryItemTexture("player", 0)
  return warn("quiver", "red", icon or "Interface\\Icons\\INV_Misc_Quiver_05", ("%d"):format(n), nil)
end

-- DO NOT RELEASE (the wipe-with-lust banner). Dead but not yet released, with
-- the Sated/Exhaustion debuff still on you. Publishes state.noRelease for the
-- shared centre banner (UI/Frame_BossBanner.lua) rather than adding a warning
-- square — a corpse-screen decision needs banner-sized text. The debuff
-- itself is detected by Modules/Auras.lua's player-debuff pass (the only
-- debuff scan, per its own mandate) and read here off state.player.sated.
local function updateNoRelease(state)
  local nr = state.noRelease
  if Warnings._noReleaseDemoUntil and Warnings._noReleaseDemoUntil > GetTime() then
    nr.active = true
    return
  end
  Warnings._noReleaseDemoUntil = nil
  if not isEnabled("warnNoReleaseEnabled") then nr.active = false return end
  if not (UnitIsDead and UnitIsDead("player")) then nr.active = false return end
  if UnitIsGhost and UnitIsGhost("player") then nr.active = false return end
  nr.active = state.player.sated or false
end

-- Unspent pet training points. A downtime nudge (suppressed in combat) to go
-- spend training points — e.g. after an untrain or on a freshly-levelled pet.
-- GetPetTrainingPoints() returns (total, spent) in TBC; unspent = total - spent.
-- Feature-detected: if the modernized client ever nils the API, this no-ops.
local function checkPetTraining(state)
  if not isEnabled("warnPetTrainingEnabled") then return nil end
  if state.player.inCombat then return nil end
  if not UnitExists("pet") or UnitIsDead("pet") then return nil end
  if not GetPetTrainingPoints then return nil end
  local total, spent = GetPetTrainingPoints()
  if type(total) ~= "number" or type(spent) ~= "number" then return nil end
  local unspent = total - spent
  if unspent <= threshold("petTrainingPointThreshold", 10) then return nil end
  return warn("pettraining", "amber", spellIcon(5149) or 132172, ("%d TP"):format(unspent), nil)   -- 5149 = Beast Training
end

local function checkMana(state)
  if not isEnabled("warnManaEnabled") then return nil end
  local pct = state.player.manaPct or 100
  if pct >= threshold("manaSuggestThreshold", 50) then return nil end

  local panicking = pct < threshold("manaPanicThreshold", 25)
  -- Real casts only; the Auto Shot wind-up is not a lockout, and suppressing the
  -- suggestion during it would silence it for most of every cycle.
  if not panicking and state.player.casting then return nil end

  -- aspectKey matches across all Viper ranks (set in Auras.lua via name lookup).
  local viperActive = state.player.aspect and state.player.aspect.aspectKey == "viper"

  local chosenId = pickCascade(MANA_ITEMS)
  local iconTex
  if chosenId then
    iconTex = itemIcon(chosenId) or 0
  elseif not viperActive then
    iconTex = spellIcon(C.SpellID.ASPECT_VIPER)
  else
    return nil
  end

  return warn("mana", panicking and "red" or "blue", iconTex, ("Mana %d%%"):format(pct), nil)
end

-- Remaining Bloodlust/Heroism duration on the player, 0 if not present. Declared
-- above checkLustCds because that caller references it — a `local function` is
-- only in scope for code lexically after it, so a later declaration would read
-- as a nil global here.
local function lustRemaining()
  if not AC then return 0 end
  local a = AC.BySpell("player", C.SpellID.BLOODLUST) or AC.BySpell("player", C.SpellID.HEROISM)
  if not a then return 0 end
  return math.max(0, (a.expirationTime or 0) - GetTime())
end

local function checkLustCds(state)
  if not isEnabled("warnLustCdsEnabled") then return nil end
  if not state.player.inLust then return nil end
  if (state.ranged.swingDuration or 0) > 0 and state.ranged.swingDuration < SATURATION_EWS then
    return nil
  end

  local actions = {}
  local rf = state.cooldowns and state.cooldowns.RF
  local haste = state.cooldowns and state.cooldowns.Haste
  local t1 = state.cooldowns and state.cooldowns.T1
  local t2 = state.cooldowns and state.cooldowns.T2
  if rf and rf.ready and not rf.procActive then
    actions[#actions + 1] = "RF"
  end
  if haste and haste.ready then
    actions[#actions + 1] = "Haste"
  end
  -- Trinket slots are gated on `.onUse`, not on being equipped: a passive proc
  -- trinket (Dragonspine Trophy, Tsunami Talisman) has no Use effect, so it
  -- reports ready forever and can never be popped. Naming it here is advice the
  -- user cannot act on. Resolved in Modules/Cooldowns.lua.
  if t1 and t1.ready and t1.onUse then
    actions[#actions + 1] = "T1"
  end
  if t2 and t2.ready and t2.onUse then
    actions[#actions + 1] = "T2"
  end

  if #actions == 0 then return nil end
  local rem = lustRemaining()
  return warn("lustcds", "amber", bloodlustIcon or spellIcon(C.SpellID.BLOODLUST), "Pop " .. table.concat(actions, "+"), rem > 0 and rem or nil)
end

function Warnings:OnEnable()
  mendPetName = (GetSpellInfo and GetSpellInfo(27046)) or "Mend Pet"
  mendPetIcon = spellIcon(27046)
  bloodlustIcon = spellIcon(C.SpellID.BLOODLUST)
  wingClipName = (GetSpellInfo and GetSpellInfo(C.SpellID.WING_CLIP)) or "Wing Clip"
  growlName = (GetSpellInfo and GetSpellInfo(C.SpellID.GROWL)) or "Growl"
  primalInstinctName = (GetSpellInfo and GetSpellInfo(C.SpellID.PRIMAL_INSTINCT)) or "Primal Instinct"
  self:RebuildUtilLookup()
  self:RebuildIdSets()
  self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "InvalidateGarment")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "ResetKaraborNeck")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "RebuildIdSets")
  -- The weave-key dialog and the Grounded import rewrite the macro bodies
  -- without an Options round-trip: the cached gate direction follows them.
  self:RegisterMessage("NOCK_WEAVEBIND_CHANGED", "RebuildIdSets")

  -- Combat log listener for Feign Death resist detection.
  _playerGUID = UnitGUID and UnitGUID("player")
  self:RegisterEvent("PLAYER_LOGIN",                 "CachePlayerGUID")
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED",  "OnCombatLog")
end

-- Rebuild the parsed ID-set caches from their profile strings. Called at
-- OnEnable and on every NOCK_VISUALS_CHANGED so Options edits to either list
-- apply immediately without a /reload.
function Warnings:RebuildIdSets()
  local p = Nock.db and Nock.db.profile
  badTrinketSet = parseIdSet(p and p.warnWrongTrinketIds)
  -- Union in the built-in PvP-trinket family (C.WRONG_TRINKET_IDS). It lives
  -- in Constants rather than the default CSV because AceDB never re-delivers
  -- a changed default to a field the user has edited — the shipped list would
  -- otherwise stay frozen at whatever it said when they first touched it.
  for id in pairs(C.WRONG_TRINKET_IDS) do badTrinketSet[id] = true end
  enrageIdSet   = parseIdSet(p and p.warnTargetFrenzyIds)
  _gateKnown = false   -- the shirt-gate direction re-reads the macro bodies
end

function Warnings:CachePlayerGUID()
  _playerGUID = UnitGUID and UnitGUID("player")
end

function Warnings:OnCombatLog()
  if not CombatLogGetCurrentEventInfo then return end
  -- Filter early: subevent + sourceGUID + spellId. CLEU fires hundreds of
  -- times per second in combat, so cheap rejects come first.
  local _, subevent, _, sourceGUID, _, _, _, _, _, _, _, spellId = CombatLogGetCurrentEventInfo()
  if subevent ~= "SPELL_MISSED" then return end
  if sourceGUID ~= _playerGUID then return end
  if spellId ~= C.SpellID.FEIGN_DEATH then return end
  if not isEnabled("warnFDResistEnabled") then return end

  -- Latch (or re-latch) the warning for the configured duration, then play the
  -- chosen LSM sound. Multiple enemies resisting within the same FD cast will
  -- restart the timer rather than stack.
  local timeout = threshold("warnFDResistTimeout", 5)
  _fdResistUntil = GetTime() + (timeout > 0 and timeout or 5)
  playWarnSound("warnFDResistSound")
end

function Warnings:GET_ITEM_INFO_RECEIVED()
  self:RebuildUtilLookup()
  _garmentDirty = true   -- a garment's INVTYPE may only now be readable
end

function Warnings:RebuildUtilLookup()
  utilLookup = {}
  if not GetItemSpell then return end
  for _, entry in ipairs(C.UTIL_ITEMS or {}) do
    local _, useSpellId = GetItemSpell(entry.id)
    if useSpellId then
      utilLookup[useSpellId] = entry
    end
  end
end

local function collectUtilities(list)
  if not isEnabled("warnUtilitiesEnabled") then return end
  if not utilLookup or not AC then return end
  local now = GetTime()
  -- The lookup is a handful of use-effect ids: ask the store for each.
  for spellId, entry in pairs(utilLookup) do
    local a = AC.BySpell("player", spellId)
    if a and not a.isHarmful then
      local expirationTime, icon = a.expirationTime, a.icon
      local remaining = expirationTime and math.max(0, expirationTime - now) or 0
      list[#list + 1] = warn("util_" .. entry.key, "blue", icon or 0, entry.label, remaining > 0 and remaining or nil)
    end
  end
end

local function checkHealth(state)
  if not isEnabled("warnHealthEnabled") then return nil end
  local pct = state.player.healthPct or 100
  if pct >= threshold("hpThreshold", 15) then return nil end

  local chosenId = pickCascade(HEALTH_ITEMS)
  if not chosenId then return nil end

  return warn("health", "red", itemIcon(chosenId) or 0, ("HP %d%%"):format(pct), nil)
end

-- (checkWeaponStone retired — superseded by the sharpening-stone Helper.)

-- Feign Death resist: a SPELL_MISSED combat-log event with the player as
-- caster and spell 5384 (Feign Death) means at least one enemy resisted, so
-- combat doesn't drop. The warning latches on for warnFDResistTimeout seconds
-- after the most recent resist, and plays a LSM sound (configurable) on each.
-- (The _fdResistUntil / _playerGUID state and playWarnSound live near the
-- top of the file so the event handlers above bind to the same upvalues.)
local function checkFDResist(state)
  if not isEnabled("warnFDResistEnabled") then return nil end
  if not _fdResistUntil then return nil end
  local now = GetTime()
  if now >= _fdResistUntil then
    _fdResistUntil = nil
    return nil
  end
  return warn("fdResist", "red", spellIcon(C.SpellID.FEIGN_DEATH) or 132293, "FD Resisted!", math.max(0, _fdResistUntil - now))
end

-- Pet aggression stance. GetPetActionInfo's mode buttons carry STABLE token
-- names (PET_MODE_*) — locale-independent (the UI localizes via _G[name]) —
-- plus an isActive flag. Classic/TBC signature: name, texture, isToken,
-- isActive, ... Returns the current mode token ("aggressive"/"defensive"/
-- "assist"/"passive") or nil.
local PET_MODE_TOKEN = {
  PET_MODE_AGGRESSIVE = "aggressive",
  PET_MODE_DEFENSIVE  = "defensive",
  PET_MODE_ASSIST     = "assist",
  PET_MODE_PASSIVE    = "passive",
}
local function petModeInfo()
  if not GetPetActionInfo then return nil end
  local n = NUM_PET_ACTION_SLOTS or 10
  for i = 1, n do
    local name, _, _, isActive = GetPetActionInfo(i)
    local mode = name and PET_MODE_TOKEN[name]
    if mode and isActive then return mode end
  end
  return nil
end

local function checkPetPassive(state)
  if not isEnabled("warnPetPassiveEnabled") then return nil end
  if not UnitExists("pet") then return nil end
  if UnitIsDead and UnitIsDead("pet") then return nil end
  local mode = petModeInfo()
  -- Only the modes the user asked about — Assist is often intentional, and
  -- Passive / unknown means there's nothing to fix.
  if mode ~= "aggressive" and mode ~= "defensive" then return nil end
  -- Static icon: pet-bar mode-button textures aren't reliable icon sources
  -- here, so reuse the proven pet icon (same as the catalog entry).
  return warn("petPassive", "amber", spellIcon(27046) or 132179, "Pet " .. mode, nil)
end

-- Growl autocast. Unlike the mode buttons (stable PET_MODE_* tokens), Growl is
-- a real pet spell on the action bar, so its slot carries the LOCALIZED spell
-- name (matched against cached growlName) plus the autoCastEnabled flag — the
-- 6th return in this client's name, texture, isToken, isActive, autoCastAllowed,
-- autoCastEnabled signature (same shape petModeInfo relies on for isActive @4).
local function petGrowlAutocastOn()
  if not GetPetActionInfo or not growlName then return false end
  local n = NUM_PET_ACTION_SLOTS or 10
  for i = 1, n do
    local name, _, _, _, _, autoCastEnabled = GetPetActionInfo(i)
    if name == growlName then
      return autoCastEnabled and true or false
    end
  end
  return false
end

-- Optional "only inside a raid instance" gate for the setup-nag warnings. Reads
-- the profile key RAW rather than going through isEnabled(): that helper defaults
-- a missing key to true (back-compat for enable flags), which is exactly backwards
-- for an opt-in gate — an upgrading profile would silently start suppressing.
local function raidGateBlocks(key)
  local p = Nock.db and Nock.db.profile
  if not (p and p[key]) then return false end
  return not Nock.IsInRaidInstance()
end

local function checkPetGrowl(state)
  if not isEnabled("warnPetGrowlEnabled") then return nil end
  if raidGateBlocks("warnPetGrowlRaidOnly") then return nil end
  if not UnitExists("pet") then return nil end
  if UnitIsDead and UnitIsDead("pet") then return nil end
  if not petGrowlAutocastOn() then return nil end
  return warn("petGrowl", "amber", spellIcon(C.SpellID.GROWL) or 132270, "Pet Growl", nil)
end

-- A Nock keybind has taken over a key that was already doing something. The
-- resolution lives in Modules/BindCheck.lua (state.binds); this only decides
-- whether to draw it.
--
-- Out of combat only, deliberately. It is a configuration problem, not a combat
-- one: it cannot be fixed mid-fight (binding APIs are locked in combat) and it
-- never clears on its own, so leaving it in the alert stack would park a
-- permanent square next to the warnings that actually want a reaction.
-- File-local, not built per call: this runs on the 10Hz warning lane.
local BIND_SLOTS = { "weave" }
local bindCheck   -- resolved once, lazily: modules are enabled after this file loads

local function checkBindConflict(state)
  if not isEnabled("warnBindConflictEnabled") then return nil end
  if state.player.inCombat then return nil end
  local binds = state.binds
  if not binds then return nil end
  bindCheck = bindCheck or Nock:GetModule("BindCheck", true)
  if not bindCheck then return nil end
  for i = 1, #BIND_SLOTS do
    local which = BIND_SLOTS[i]
    local s = binds[which]
    -- BindCheck:ShouldWarn owns the "is this worth a square?" rule — the feature
    -- has to be enabled (a disabled one never claims its key) and something has
    -- to actually be lost (a bound-but-empty bar slot is not).
    if bindCheck:ShouldWarn(which) then
      local c = s.conflict
      return {
        id       = "bindConflict",
        severity = "amber",
        -- Name the FEATURE and the KEY, not the thing being displaced: the
        -- square is one short line, and "which Nock key, and which key is it"
        -- is the half you cannot work out from anything else. The displaced
        -- action is already the icon, and Settings (whose page title is exactly
        -- this label) plus /nock binds carry the full sentence.
        text     = (s.label or "Nock") .. ": " .. (s.key or "?"),
        -- The icon of whatever is being suppressed, when we could resolve it —
        -- that is the fastest way to recognise what stopped working.
        icon     = (c.slot and GetActionTexture and GetActionTexture(c.slot))
                   or spellIcon(C.SpellID.RAPTOR_STRIKE) or 132223,
      }
    end
  end
  return nil
end

-- Idiot check: warn if a trinket on the user's bad list is equipped (Riding
-- Crop, Carrot, PvP insignias, etc.). The list is profile-editable; the per-
-- tick cost is two GetInventoryItemID calls + two set lookups, so no event
-- subscription is needed beyond the parser rebuild on NOCK_VISUALS_CHANGED.
local function checkWrongTrinket(state)
  if not isEnabled("warnWrongTrinketEnabled") then return nil end
  if raidGateBlocks("warnWrongTrinketRaidOnly") then return nil end
  if not GetInventoryItemID then return nil end
  if not next(badTrinketSet) then return nil end
  local t1 = GetInventoryItemID("player", 13)
  local t2 = GetInventoryItemID("player", 14)
  local badId = (t1 and badTrinketSet[t1] and t1) or (t2 and badTrinketSet[t2] and t2)
  if not badId then return nil end
  return warn("wrongTrinket", "amber", itemIcon(badId) or 134486, "Bad trinket", nil)
end

-- Shirt-gate check: the user's weave/consume macros carry [noequipped:Shirt]
-- conditionals — shirt ON disables the Snowball/consume lines (trash, farm;
-- saves consumables), shirt OFF enables them (boss fights). The classic
-- mistake is pulling a raid boss with the shirt still equipped, silently
-- disarming every gated macro line; this is that pre-pull check. Red on
-- purpose: it only shows in the narrow raid+boss-target window, and missing
-- it costs the whole fight's snowball weaves.
-- Cosmetic gate garments (mirrors WeaveBind): Shirt (body, slot 4) and
-- Tabard (slot 19). The slot constants are honest on this client — the
-- original "slot 4 reads empty" report turned out to be no shirt being worn
-- at all; the user's toggle garment is a tabard.
local GARMENT_SLOT = { shirt = INVSLOT_BODY or 4, tabard = INVSLOT_TABARD or 19 }
local GARMENT_LOC  = { shirt = "INVTYPE_BODY",    tabard = "INVTYPE_TABARD" }

-- Where the garment sits, cached: the answer moves with the equipment
-- (PLAYER_EQUIPMENT_CHANGED) or when an item's info arrives, not per refresh
-- -- and the miss path is a 24-slot GetInventoryItemLink + GetItemInfo sweep,
-- which ran ten times a second for every boss fight with the shirt correctly
-- off. `false` caches "not equipped".
local _garmentSlot = {}

local function garmentSlotIfEquipped(g)
  if not GetInventoryItemLink then return nil end
  if _garmentDirty then
    _garmentSlot.shirt, _garmentSlot.tabard = nil, nil
    _garmentDirty = false
  end
  local hit = _garmentSlot[g]
  if hit ~= nil then return hit or nil end
  local found = false
  local slot = GARMENT_SLOT[g]
  if slot and GetInventoryItemLink("player", slot) then
    found = slot
  else
    for s = 0, 23 do
      local link = GetInventoryItemLink("player", s)
      if link and GetItemInfo and select(9, GetItemInfo(link)) == GARMENT_LOC[g] then
        found = s
        break
      end
    end
  end
  _garmentSlot[g] = found
  return found or nil
end

function Warnings:InvalidateGarment()
  _garmentDirty = true
end

-- Gate direction per garment off the two macro bodies (mirrors WeaveBind's
-- gateGarment): "off" = [noequipped:...] lines, armed with the garment
-- REMOVED (the shipped convention); "on" = [equipped:...] lines, armed with
-- it WORN; nil = no conditional on that garment. Pure; the result is cached
-- (RebuildIdSets) because the bodies only change through Options / the
-- weave-key dialog, and computing it was a concat + lower + gsub of both
-- bodies plus a closure and four pattern strings per refresh.
function Warnings.GateDirs(down, up)
  local mac = ((down or "") .. "\n" .. (up or "")):lower()
  -- Stripping "noequipped" first leaves only the positive form findable.
  local plain = mac:gsub("noequipped", "")
  local function gateDir(g)
    if mac:find("noequipped:%s*" .. g) then return "off" end
    if plain:find("equipped:%s*" .. g) then return "on" end
    return nil
  end
  return gateDir("shirt"), gateDir("tabard")
end

local _gateShirt, _gateTabard

local function gateDirs()
  if not _gateKnown then
    local p2 = Nock.db and Nock.db.profile
    _gateShirt, _gateTabard = Warnings.GateDirs(p2 and p2.weaveBindMacroDown, p2 and p2.weaveBindMacroUp)
    _gateKnown = true
  end
  return _gateShirt, _gateTabard
end

local function checkShirtGate(state)
  if not isEnabled("warnShirtGateEnabled") then return nil end
  if not Nock.IsInRaidInstance() then return nil end
  if not isBossTarget() then return nil end
  -- Warn about whichever garment(s) the weave macros actually gate on
  -- ([no]equipped:Shirt / :Tabard). With no garment conditional stored, the
  -- classic shirt check applies.
  local p2 = Nock.db and Nock.db.profile
  local shirtDir, tabardDir = gateDirs()
  -- WeaveBind's garment autopilot owns the out-of-combat case when a real
  -- conditional is stored; the warning survives for in-combat (equipment is
  -- locked, the autopilot can't act) and for attempts that were blocked
  -- (bags full / cursor busy — flag on state). The default-shirt fallback
  -- below (no conditional stored) is exactly what the autopilot won't touch,
  -- so it must keep warning too.
  if (shirtDir or tabardDir)
     and p2 and p2.weaveBindEnabled and p2.weaveBindGarmentAutoFlip
     and not (InCombatLockdown and InCombatLockdown())
     and not (Nock.state and Nock.state.weave and Nock.state.weave.garmentFlipBlocked) then
    return nil
  end
  if not (shirtDir or tabardDir) then shirtDir = "off" end
  local FALLBACK_ICON = "Interface\\Icons\\INV_Shirt_White_01"
  local label, icon
  -- "off" direction: the garment must be OFF at a boss — warn while it's
  -- still worn (showing the worn item's own texture: the thing to remove).
  -- "on" direction: it must be ON — warn while it's missing. Path fallback
  -- because Frame_Warnings only SetTextures non-nil icons (same reasoning as
  -- DAZED_FALLBACK_ICON).
  if shirtDir then
    local s = garmentSlotIfEquipped("shirt")
    if shirtDir == "off" and s then
      label = "Shirt on!"
      icon  = (GetInventoryItemTexture and GetInventoryItemTexture("player", s)) or FALLBACK_ICON
    elseif shirtDir == "on" and not s then
      label = "Shirt off!"
      icon  = FALLBACK_ICON
    end
  end
  if not label and tabardDir then
    local s = garmentSlotIfEquipped("tabard")
    if tabardDir == "off" and s then
      label = "Tabard on!"
      icon  = (GetInventoryItemTexture and GetInventoryItemTexture("player", s)) or FALLBACK_ICON
    elseif tabardDir == "on" and not s then
      label = "Tabard off!"
      icon  = FALLBACK_ICON
    end
  end
  if not label then return nil end
  return warn("shirtGate", "red", icon, label, nil)
end

-- Black Temple: the Medallion of Karabor (32649 / Blessed 32757) teleports
-- you TO the raid and is easy to forget around your neck once inside — a
-- stat-less Shadow Resistance neck for the whole run. One exception: Mother
-- Shahraz is the fight where that SR is exactly right, so the warning stands
-- down while she is in view (target / mouseover / focus / boss frames /
-- nameplates, NPC 22947) — approaching her room wearing the neck is correct —
-- and comes back the moment she is dead (take it off again) or is left
-- behind. All scans are gated behind "in BT and wearing the neck", so this
-- costs nothing anywhere else.
local KARABOR_LINGER = 25    -- s a sighting keeps the warning down (plates blink)
local BT_RECHECK     = 5     -- s between GetInstanceInfo reads
local MOTHER_SCAN    = 0.25  -- s between unit sweeps (the sapper scan's cadence)
local _btAt, _inBT = 0, false
local _motherScanAt, _motherSeenAt, _motherDead = 0, nil, false

-- Field 6 of a creature GUID is the NPC id (see BossMarkWatch.lua).
local function npcIdOf(guid)
  if not guid then return nil end
  local id = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  return id and tonumber(id) or nil
end

local MOTHER_TOKENS = { "target", "mouseover", "focus", "boss1", "boss2", "boss3", "boss4" }

-- A unit that is her: alive refreshes the sighting (and clears the death
-- latch — a reset after a wipe brings her back alive); dead latches.
local function noteMotherUnit(u, now)
  if not (UnitExists and UnitExists(u)) then return end
  if npcIdOf(UnitGUID and UnitGUID(u)) ~= C.NpcID.MOTHER_SHAHRAZ then return end
  if UnitIsDead and UnitIsDead(u) then
    _motherDead = true
  else
    _motherSeenAt, _motherDead = now, false
  end
end

local function scanMother(now)
  if now - _motherScanAt < MOTHER_SCAN then return end
  _motherScanAt = now
  for i = 1, #MOTHER_TOKENS do noteMotherUnit(MOTHER_TOKENS[i], now) end
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local plates = C_NamePlate.GetNamePlates()
    if plates then
      for _, plate in ipairs(plates) do
        local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if u then noteMotherUnit(u, now) end
      end
    end
  end
end

-- Zone edge: re-read the instance at once and forget the Mother latches (a
-- fresh entry starts clean; her death last reset must not suppress-or-not
-- this one).
function Warnings:ResetKaraborNeck()
  _btAt, _motherSeenAt, _motherDead = 0, nil, false
end

local function checkKaraborNeck(state)
  if not isEnabled("warnKaraborNeckEnabled") then return nil end
  if not GetInventoryItemID then return nil end
  local now = GetTime()
  if now >= _btAt then
    _btAt = now + BT_RECHECK
    _inBT = false
    if GetInstanceInfo then
      local name, itype, _, _, _, _, _, mapId = GetInstanceInfo()
      -- Map id first (locale-proof); the enUS name as a fallback in case this
      -- client's GetInstanceInfo predates the instanceMapID return.
      _inBT = mapId == C.BLACK_TEMPLE_MAP_ID
              or (mapId == nil and itype == "raid" and name == "Black Temple")
    end
  end
  if not _inBT then return nil end
  local neck = GetInventoryItemID("player", INVSLOT_NECK or 2)
  if not (neck and C.KARABOR_NECK_ITEMS[neck]) then return nil end
  scanMother(now)
  if not _motherDead and _motherSeenAt and now - _motherSeenAt < KARABOR_LINGER then
    return nil
  end
  -- The worn medallion's own texture — the thing to swap out; the blessed
  -- medallion's icon (highest id) when the slot read has nothing.
  local icon = (GetInventoryItemTexture and GetInventoryItemTexture("player", INVSLOT_NECK or 2))
               or itemIcon(32757)
               or "Interface\\Icons\\INV_Jewelry_Necklace_15"
  return warn("karaborNeck", "red", icon, "Karabor neck!", nil)
end

-- Idiot check: in combat with anything other than Aspect of the Hawk up.
-- Combat-gated on purpose — Cheetah/Pack out of combat is just travel, and a
-- Viper top-up between pulls is normal. Viper is deliberately NOT exempt in
-- combat: it's a large DPS loss, and forgetting to swap back out of it is
-- exactly the mistake this catches.
--
-- Matches on state.player.aspect.aspectKey, the stable key Auras.lua derives via
-- a localized-NAME lookup — so every rank of every aspect resolves, not just the
-- max ranks in Constants.
local function checkAspect(state)
  if not isEnabled("warnAspectEnabled") then return nil end
  if raidGateBlocks("warnAspectRaidOnly") then return nil end
  if not state.player.inCombat then return nil end
  local a = state.player.aspect
  if a and a.aspectKey == "hawk" then return nil end
  return {
    id       = "aspect",
    severity = "amber",
    -- Text stays short and generic; the icon carries the "which aspect" detail.
    -- Interpolating a.name would overflow the square on longer locales
    -- ("Aspekt des Falken") — every other warning text is ~12 chars or less.
    text     = a and "Aspect" or "No Aspect",
    -- The OFFENDING aspect's own icon, so it reads at a glance as "that's Viper".
    -- Hawk's icon when there's no aspect at all — i.e. what you should press.
    -- 136116 is the same "no aspect" placeholder the rotation row falls back to
    -- (Frame_Rotation.lua). The fallback isn't cosmetic: Frame_Warnings only
    -- calls SetTexture when w.icon is non-nil, so a nil here would leave the
    -- square showing whatever warning previously occupied that slot.
    icon     = (a and a.icon) or spellIcon(C.SpellID.ASPECT_HAWK) or 136116,
  }
end

-- Dazed in combat: you're slowed and locked out of casting, and the fix (turn to
-- face, or stop moving) is time-critical — hence the optional audio cue.
--
-- _dazedActive edge-triggers that cue. Refresh runs at 10 Hz, so without the latch
-- the sound would machine-gun for the whole debuff. Mirrors the _petIdleSpokeAt
-- precedent below, but one-shot rather than re-firing on an interval.
--
-- Refresh also clears it on the two paths that skip checkDazed entirely (warnings
-- globally hidden, demo mode) — otherwise a Daze that starts before one of those
-- and drops during it would leave the latch stranded at true, silently swallowing
-- the NEXT Daze's cue. Erring toward one redundant cue on resume beats a missed one.
local _dazedActive = false

-- Last-resort icon for the Daze square. Only reachable if BOTH the live aura's
-- own icon and the spell lookup come back nil — but the fallback isn't optional:
-- Frame_Warnings only calls SetTexture when w.icon is non-nil, so returning nil
-- would leave the square showing whatever warning previously held that slot.
-- A path rather than a fileID because this one has to be certain (the warning
-- shape accepts either), and a question mark is the honest answer when we
-- genuinely couldn't resolve the icon.
local DAZED_FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function checkDazed(state)
  -- The latch resets on EVERY exit path, not just "debuff gone". If it only reset
  -- there, disabling the warning (or leaving combat) mid-Daze would strand it at
  -- true and silently swallow the next cue. Same reasoning as the repeated
  -- _petIdleSpokeAt = 0 resets in maybeSpeakPetIdle.
  if not isEnabled("warnDazedEnabled") then _dazedActive = false; return nil end
  if not state.player.inCombat then _dazedActive = false; return nil end
  local d = state.player.dazed
  if not d then _dazedActive = false; return nil end

  if not _dazedActive then
    _dazedActive = true
    playWarnSound("warnDazedSound")
  end
  return warn("dazed", "amber", d.icon or spellIcon(C.SpellID.DAZED) or DAZED_FALLBACK_ICON, "Dazed", nil)
end

-- Raw "pet is sitting idle in combat" condition, shared by the visual warning
-- and the spoken-alert option below.
local function petIsIdle(state)
  if not state.player.inCombat then return false end
  if not UnitExists("pet") then return false end
  if UnitIsDead and UnitIsDead("pet") then return false end
  -- Pet has a target → it's already attacking (or about to). Nothing to nag.
  if UnitExists("pettarget") then return false end
  return true
end

local function checkPetNotAttacking(state)
  if not isEnabled("warnPetAttackEnabled") then return nil end
  if not petIsIdle(state) then return nil end
  return warn("petAttack", "amber", spellIcon(C.SpellID.KILL_COMMAND) or 132152, "Pet idle", nil)
end

-- "Boss encounter" detection. Prefers the real signals when the client exposes
-- them (IsEncounterInProgress / boss1-5 unit frames on the modernized
-- Anniversary client); otherwise falls back to the ??-level / worldboss target
-- heuristic already used by the Sapper warning. All probes are nil-guarded.
local function inBossEncounter()
  if IsEncounterInProgress and IsEncounterInProgress() then return true end
  if UnitExists then
    for i = 1, 5 do
      if UnitExists("boss" .. i) then return true end
    end
  end
  return isBossTarget()
end

-- Speak a line via the game's built-in text-to-speech — the SAME public API
-- WeakAuras' "Text to Speech" action uses. Nil-guarded so it's a no-op on
-- clients without TTS (or with no voices installed). Uses the first available
-- voice at normal rate / full volume.
local function speakTts(text)
  if not (C_VoiceChat and C_VoiceChat.SpeakText) then return end
  local voiceID
  if C_VoiceChat.GetTtsVoices then
    local voices = C_VoiceChat.GetTtsVoices()
    if voices and voices[1] then voiceID = voices[1].voiceID end
  end
  local dest = (Enum and Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback) or 1
  pcall(C_VoiceChat.SpeakText, voiceID or 0, text, dest, 0, 100)
end

-- Spoken "Pet idle" alert (opt-in, default off). While the pet is idle in a
-- boss encounter, say the line on entry and then re-say it every interval until
-- the pet engages or the encounter ends. Resetting the stamp when the condition
-- clears makes the next idle speak immediately.
local PET_IDLE_VOICE_INTERVAL = 5
local _petIdleSpokeAt = 0

local function maybeSpeakPetIdle(state)
  -- Gated on the warning being enabled (the UI greys the voice toggle when it
  -- isn't) + the opt-in voice flag, then the same idle condition + boss gate.
  if not isEnabled("warnPetAttackEnabled") then _petIdleSpokeAt = 0; return end
  local p = Nock.db and Nock.db.profile
  if not (p and p.warnPetAttackVoice) then _petIdleSpokeAt = 0; return end
  if not petIsIdle(state) or not inBossEncounter() then _petIdleSpokeAt = 0; return end

  local now = GetTime()
  if now - _petIdleSpokeAt < PET_IDLE_VOICE_INTERVAL then return end
  _petIdleSpokeAt = now
  speakTts("Pet idle")
end

-- Spoken trinket-chain cue during Bloodlust/Heroism (opt-in, default off).
-- The flow it supports: Lust lands, you pop your burst CDs; the moment the
-- FIRST on-use trinket goes on cooldown, the OTHER one — if it's also on-use
-- and ready — is called out by voice ("Trinket 2", or "Trinket 1" when you
-- popped slot 2 first) so both land back-to-back inside the haste window.
-- Edge-triggered on the ready→on-cooldown transition, once per Lust window;
-- everything resets when Lust drops so the next Lust cues again. Only active
-- when BOTH trinket slots hold on-use trinkets — there is no second trinket to
-- chain into if one of them is a passive proc (same `.onUse` signal
-- checkLustCds keys on, resolved in Modules/Cooldowns.lua).
local _lustPrevT1Ready, _lustPrevT2Ready = nil, nil
local _lustTrinketSpoke = false

local function maybeSpeakLustTrinket(state)
  local p = Nock.db and Nock.db.profile
  local t1 = state.cooldowns and state.cooldowns.T1
  local t2 = state.cooldowns and state.cooldowns.T2
  local r1 = (t1 and t1.ready) and true or false
  local r2 = (t2 and t2.ready) and true or false
  local active = isEnabled("warnLustCdsEnabled")
    and p and p.warnLustCdsVoice
    and state.player.inLust
    and t1 and t1.onUse and t2 and t2.onUse
  if not active then
    -- Latch re-arms outside Lust (or with the toggle off); the ready
    -- trackers still update below so the first in-Lust tick has real edges.
    _lustTrinketSpoke = false
  elseif not _lustTrinketSpoke then
    if _lustPrevT1Ready and not r1 and r2 then
      _lustTrinketSpoke = true
      speakTts("Trinket 2")
    elseif _lustPrevT2Ready and not r2 and r1 then
      _lustTrinketSpoke = true
      speakTts("Trinket 1")
    end
  end
  _lustPrevT1Ready, _lustPrevT2Ready = r1, r2
end

-- Enrage / frenzy buffs Tranq Shot can dispel are matched against enrageIdSet,
-- a user-editable list (profile.warnTargetFrenzyIds, parsed in RebuildIdSets).
-- ID matching is locale-proof with zero false positives; the seed list lives
-- in Config/Defaults.lua. Anything not in the list still triggers via the
-- localized-name fallback below.

-- Case-sensitive substring tokens for the localized-name fallback. "Frenzy"
-- doesn't substring-match "Frenzied" (different ending), so no false-positive
-- on Druid Frenzied Regeneration. enUS-only; other locales rely on the ID
-- table above.
local FRENZY_NAME_TOKENS = { "Frenzy", "Enrage" }

-- The target's enrage: by id set, then by name token (module-level callback
-- over the aura store; the first hit wins).
local _frenzyHit, _frenzyName, _frenzyIcon, _frenzySpell
local function onTargetAuraFrenzy(a)
  if _frenzyHit or a.isHarmful then return end
  local name, spellId = a.name, a.spellId
  local hit = spellId and enrageIdSet[spellId] or false
  if not hit and name then
    for _, token in ipairs(FRENZY_NAME_TOKENS) do
      if name:find(token, 1, true) then hit = true; break end
    end
  end
  if hit then
    _frenzyHit, _frenzyName, _frenzyIcon, _frenzySpell = true, name, a.icon, spellId
  end
end

local function checkTargetFrenzy(state)
  if not isEnabled("warnTargetFrenzyEnabled") then return nil end
  if not UnitExists("target") then return nil end
  if UnitIsDead and UnitIsDead("target") then return nil end
  if UnitCanAttack and not UnitCanAttack("player", "target") then return nil end
  -- Don't nag when Tranq is unavailable — keeps the alert actionable.
  if getSpellCdRemaining(C.SpellID.TRANQ_SHOT) > 0 then return nil end
  if not AC then return nil end
  _frenzyHit = nil
  AC.ForEach("target", onTargetAuraFrenzy)
  if _frenzyHit then
    return warn("targetFrenzy", "amber", _frenzyIcon or spellIcon(C.SpellID.TRANQ_SHOT) or 132294, "Tranq!", nil)
  end
  return nil
end

local function checkDrums(state)
  if not isEnabled("warnDrumsEnabled") then return nil end
  if not AC then return nil end
  local now = GetTime()
  local a = AC.BySpell("player", C.SpellID.DRUMS_OF_BATTLE)
  if a then
    local expirationTime, icon = a.expirationTime, a.icon
    local rem = expirationTime and math.max(0, expirationTime - now) or 0
    return warn("drums", "blue", icon, "Drums", rem > 0 and rem or nil)
  end
  return nil
end

-- Demo mode: replace real checks with three sample entries (one of each
-- severity) for the duration. Lets the user tune appearance settings without
-- waiting for the real conditions to trigger.
local DEMO_DURATION = 10
function Warnings:RunDemo(seconds)
  self._demoUntil = GetTime() + (seconds or DEMO_DURATION)
end

-- End a demo early. The onboarding wizard arms a long demo on its warnings
-- page and cancels it the moment the page is left, so the samples never
-- outlive the step that explains them.
function Warnings:StopDemo()
  self._demoUntil = nil
  self._noReleaseDemoUntil = nil
end

local function buildDemoList()
  return {
    { id = "demo_red",   severity = "red",
      text = "Demo Red",   icon = spellIcon(C.SpellID.RAPID_FIRE)    or 132208,
      remaining = 8 },
    { id = "demo_amber", severity = "amber",
      text = "Demo Amber", icon = spellIcon(C.SpellID.BESTIAL_WRATH) or 132127,
      remaining = nil },
    { id = "demo_blue",  severity = "blue",
      text = "Demo Blue",  icon = bloodlustIcon or spellIcon(C.SpellID.BLOODLUST) or 136012,
      remaining = 125 },
  }
end

-- Slow lane (Core:Tick): the check battery below does up to four full aura
-- scans, a table.sort, and a fresh table + formatted string per firing warning,
-- every tick. A warning appearing 100ms later is imperceptible, and the view
-- renders state.warnings every frame regardless.
Warnings.refreshInterval = 0.1

function Warnings:Refresh(state)
  local list = state.warnings
  for i = #list, 1, -1 do list[i] = nil end

  -- Global disable: leave the list empty and skip all checks (FD combat-log
  -- listener stays registered but is cheap; the per-tick scans don't run).
  if Nock.db and Nock.db.profile and Nock.db.profile.showWarnings == false then
    _dazedActive = false
    state.noRelease.active = false
    return
  end

  -- Before the demo early-return: the DO NOT RELEASE banner must keep
  -- tracking reality (and clearing) even while a warning demo plays.
  updateNoRelease(state)

  if self._demoUntil and self._demoUntil > GetTime() then
    for _, w in ipairs(buildDemoList()) do list[#list + 1] = w end
    _dazedActive = false
    return
  end
  self._demoUntil = nil

  _list = list

  add(checkHealth(state))
  add(checkFDResist(state))
  add(checkSteamTonk(state))
  add(checkMendPet(state))
  add(checkDevilsaurTooth(state))
  add(checkPetNotAttacking(state))
  maybeSpeakPetIdle(state)
  add(checkPetPassive(state))
  add(checkPetGrowl(state))
  add(checkPetTraining(state))
  add(checkWrongTrinket(state))
  add(checkBindConflict(state))
  add(checkShirtGate(state))
  add(checkKaraborNeck(state))
  add(checkQuiverLow(state))
  add(checkAspect(state))
  add(checkDazed(state))
  add(checkTargetFrenzy(state))
  add(checkSapperAoe(state))
  add(checkMana(state))
  add(checkLustCds(state))
  maybeSpeakLustTrinket(state)
  add(checkDrums(state))
  -- Weapon stone moved into the Helpers panel (see Modules/Helpers.lua).
  collectUtilities(list)

  table.sort(list, bySeverity)
end

-- /nock norelease and the Options preview button — hold the DO NOT RELEASE
-- banner open for a few seconds so it can be seen and placed (it is otherwise
-- only ever up while you lie dead). Says why when it can't and returns false:
-- a preview that silently does nothing reads as a broken feature (same
-- convention as BossMarkWatch:Preview).
function Warnings:RunNoReleaseDemo(seconds)
  local p = Nock.db and Nock.db.profile
  if p and p.showWarnings == false then
    Nock:Print("Warnings are switched off entirely — turn on 'Enable warnings' to see this.")
    return false
  end
  if not isEnabled("warnNoReleaseEnabled") then
    Nock:Print("The DO NOT RELEASE alert is switched off — turn it on under Warnings.")
    return false
  end
  self._noReleaseDemoUntil = GetTime() + (tonumber(seconds) or 5)
  return true
end

-- Public catalog read by the settings UI. Each entry advertises the warning's
-- name, description, chain-logic explanation, tunable thresholds, and the
-- enable-flag profile key. Icons are resolved lazily (item/spell info may not
-- be cached at file-load time).
Warnings.Catalog = {
  {
    key         = "health",
    category    = "you",
    name        = "Low Health",
    severity    = "red",
    enabledKey  = "warnHealthEnabled",
    iconFn      = function() return itemIcon(22829) or 133643 end,  -- Super Healing Potion
    description = "Suggests popping a healing item when your HP gets dangerously low.",
    logic       = "Fires when:\n• HP < threshold\n• A healing item is in your bag\n\nThe slot's icon shows whichever item is ready first, in priority order: Master Healthstone → Healing Injector → Super Healing Potion → Nightmare Seed.",
    thresholds  = {
      { key = "hpThreshold", label = "HP threshold (%)", min = 5, max = 50, step = 1 },
    },
  },
  {
    key         = "steamTonk",
    category    = "pet",
    name        = "Steam Tonk (pet death-save)",
    severity    = "red",
    enabledKey  = "warnSteamTonkEnabled",
    iconFn      = function() return itemIcon(STEAM_TONK_ITEM) or 134071 end,
    description = "Urgent reminder to pop the Steam Tonk Controller when your pet is about to die.",
    logic       = "Fires when:\n• Pet is alive and pet HP < threshold\n• Steam Tonk Controller (22728) is in your bag\n• Steam Tonk isn't on cooldown\n\nUsing the tonk dismisses your pet — you'll need to re-summon at full HP via Call Pet after.",
    thresholds  = {
      { key = "steamTonkThreshold", label = "Pet HP threshold (%)", min = 5, max = 50, step = 1 },
    },
  },
  {
    key         = "mendPet",
    category    = "pet",
    name        = "Mend Pet",
    severity    = "amber",
    enabledKey  = "warnMendPetEnabled",
    iconFn      = function() return spellIcon(27046) or 132179 end,
    description = "Reminds you to cast Mend Pet when your pet is hurt.",
    logic       = "Fires when:\n• Pet is alive and pet HP < threshold\n• Mend Pet isn't already on the pet\n\nUpgrades to red severity once pet HP also drops below the Steam Tonk threshold.",
    thresholds  = {
      { key = "mendPetThreshold", label = "Pet HP threshold (%)", min = 20, max = 90, step = 5 },
    },
  },
  {
    key         = "devilsaur",
    category    = "gear",
    name        = "Devilsaur Tooth (pet crit not loaded)",
    severity    = "amber",
    enabledKey  = "warnDevilsaurEnabled",
    iconFn      = function() return itemIcon(C.DEVILSAUR_TOOTH_ITEM) or 134071 end,
    description = "For Devilsaur Tooth carriers: reminds you to pop the trinket when a boss is targeted and your pet's guaranteed crit (Primal Instinct) isn't loaded. Off by default.",
    logic       = "Fires when ALL of:\n• Your target is a boss (??-level or worldboss classification)\n• Your pet is alive\n• Devilsaur Tooth (19992) is equipped in a trinket slot\n• The pet does not have the Primal Instinct buff\n\nPrimal Instinct has no duration — it sits on the pet until its next crit consumes it, so this clears the moment you pop the tooth and returns once the crit lands.\n\nDeliberately ignores the trinket's 2-minute cooldown: the warning means the guaranteed crit isn't loaded, whether or not you can re-pop yet.\n\nOpt-in (off by default) — only useful if you actually carry the tooth.",
    thresholds  = {},
  },
  {
    key         = "petTraining",
    category    = "pet",
    name        = "Pet unspent training points",
    severity    = "amber",
    enabledKey  = "warnPetTrainingEnabled",
    iconFn      = function() return spellIcon(5149) or 132172 end,  -- Beast Training
    description = "Reminds you to spend your pet's training points — e.g. after an untrain or on a freshly-levelled pet.",
    logic       = "Fires when:\n• You are out of combat\n• Pet is alive\n• Unspent training points (GetPetTrainingPoints: total − spent) exceed the threshold\n\nCast Beast Training to spend them. Clears automatically once you're at or below the threshold.",
    thresholds  = {
      { key = "petTrainingPointThreshold", label = "Unspent points threshold", min = 0, max = 100, step = 5 },
    },
  },
  {
    key         = "petAttack",
    category    = "pet",
    name        = "Pet not attacking",
    severity    = "amber",
    enabledKey  = "warnPetAttackEnabled",
    iconFn      = function() return spellIcon(C.SpellID.KILL_COMMAND) or 132152 end,
    description = "Nags you when you're in combat and your pet is sitting idle (no target).",
    logic       = "Fires when:\n• You are in combat\n• Pet is alive\n• Pet has no current target (UnitExists(\"pettarget\") is false)\n\nUse /petattack or the Attack pet command to send your pet at your current target.\n\n|cff909090Speak aloud:|r when enabled, says \"Pet idle\" via the game's text-to-speech every 5 seconds while the pet is idle during a boss encounter (off by default).",
    thresholds  = {},
    extraToggles = {
      { key = "warnPetAttackVoice",
        label = "Speak \"Pet idle\" aloud during boss fights (every 5s)" },
    },
  },
  {
    key         = "petPassive",
    category    = "pet",
    name        = "Pet not on Passive",
    severity    = "amber",
    enabledKey  = "warnPetPassiveEnabled",
    iconFn      = function() return spellIcon(27046) or 132179 end,
    description = "Warns when your pet is set to Aggressive or Defensive — put it on Passive so it doesn't break CC or pull packs.",
    logic       = "Fires when:\n• Pet is alive\n• Pet stance is Aggressive OR Defensive\n\nReads the pet's current mode from the pet action bar (PET_MODE_* tokens, locale-independent). Assist and Passive do not warn (Assist is often intentional). Not gated on combat — wrong stance matters most before a pull.",
    thresholds  = {},
  },
  {
    key         = "petGrowl",
    category    = "pet",
    name        = "Pet Growl autocast on",
    severity    = "amber",
    enabledKey  = "warnPetGrowlEnabled",
    iconFn      = function() return spellIcon(C.SpellID.GROWL) or 132270 end,
    description = "Warns when your pet's Growl is set to autocast — turn it off so the pet doesn't taunt mobs off the tank or rip threat.",
    logic       = "Fires when:\n• Pet is alive\n• Growl is on the pet action bar with autocast enabled\n• (if 'Only inside a raid instance' is on) you are in a raid instance\n\nMatches the Growl slot by its localized name and reads the slot's autocast flag. Not gated on combat — Growl autocast matters most before a pull.\n\nThe raid gate is instance-based: it checks you're physically inside a raid, so an open-world raid group does not count. Handy if you want Growl on while questing but never in a raid.",
    thresholds  = {},
    extraToggles = {
      { key = "warnPetGrowlRaidOnly", label = "Only inside a raid instance" },
    },
  },
  {
    key         = "wrongTrinket",
    category    = "gear",
    name        = "Wrong trinket equipped",
    severity    = "amber",
    enabledKey  = "warnWrongTrinketEnabled",
    iconFn      = function() return itemIcon(25653) or itemIcon(11122) or 134486 end,
    description = "Idiot check: nags when a trinket from the bad-trinket list is equipped (mount-speed trinkets, PvP insignias/medallions, leveling junk that shouldn't be in a raid set).",
    logic       = "Fires when:\n• An item ID in the bad-trinket set is equipped in trinket slot 1 (slot 13) or trinket slot 2 (slot 14)\n• (if 'Only inside a raid instance' is on) you are in a raid instance\n\nThe set is every PvP escape trinket (Insignia and Medallion of the Alliance/Horde, all class versions — built in) plus your own comma/newline-separated item IDs below. Edits take effect immediately — no /reload required. The editable list seeds with Riding Crop, Carrot on a Stick and Devilsaur Tooth (pop the tooth pre-pull, then swap a real trinket in — delist it below if you deliberately keep it equipped).\n\nThe raid gate is instance-based: it checks you're physically inside a raid, so an open-world raid group does not count. Handy if you keep a Riding Crop on while questing but never want it in a raid.",
    thresholds  = {},
    extraToggles = {
      { key = "warnWrongTrinketRaidOnly", label = "Only inside a raid instance" },
    },
    inputs = {
      { key = "warnWrongTrinketIds",
        label = "Extra bad trinket item IDs",
        desc  = "Comma/newline-separated item IDs to flag when equipped, on top of the built-in PvP insignia/medallion family. Ships with 25653, 11122, 19992 (Riding Crop, Carrot on a Stick, Devilsaur Tooth). Find IDs on Wowhead (the URL ends with the ID).",
        multiline = 3 },
    },
  },
  {
    key         = "bindConflict",
    category    = "gear",
    name        = "Nock keybind took over a key",
    severity    = "amber",
    enabledKey  = "warnBindConflictEnabled",
    iconFn      = function() return spellIcon(C.SpellID.RAPTOR_STRIKE) or 132223 end,
    description = "Tells you when the Weave Bind key has claimed a key that was already doing something — an action-bar button, another addon's button, or a normal game binding.",
    logic       = "Fires (out of combat only) when:\n• The Weave Bind key is enabled and set\n• Something else is already bound to that key\n• That something actually does anything — a key bound to an |cffffd200empty|r action-bar slot costs you nothing, so it never raises the square (Settings still reports it)\n\nThe Nock key is a |cffffd200priority override|r: Nock always wins it, so whatever was on it goes quiet for as long as the feature is enabled — and comes straight back when you disable it or clear the key. Nock never edits your bindings; this only reports.\n\nThe square shows the icon of the action being suppressed and names it (the spell, the macro, or the binding).\n\nOut of combat only: bindings are locked during a fight, so there is nothing you could do about it mid-pull.\n\nSettings → Utilities → Weave Bind shows the same detail live under the key picker.",
    thresholds  = {},
  },
  {
    key         = "shirtGate",
    category    = "gear",
    name        = "Shirt/Tabard wrong for boss (weave gate)",
    severity    = "red",
    enabledKey  = "warnShirtGateEnabled",
    iconFn      = function()
      return (GetInventoryItemTexture and GetInventoryItemTexture("player", INVSLOT_BODY or 4))
             or (GetInventoryItemTexture and GetInventoryItemTexture("player", INVSLOT_TABARD or 19))
             or "Interface\\Icons\\INV_Shirt_White_01"
    end,
    description = "For garment-gated weave macros: reminds you when the gate Shirt/Tabard is in the wrong state as you target a raid boss — still on for [noequipped:...] lines, still off for [equipped:...] lines — so the Snowball/consume lines actually fire.",
    logic       = "Fires when ALL of:\n• You are inside a raid instance\n• Your target is a boss (??-level or worldboss classification)\n• The gate garment is in its everyday state instead of its boss state — whichever of Shirt/Tabard your Weave Bind macros carry a conditional for (plain shirt-still-on check when they carry none)\n\nBoth conditional directions are understood: /use [noequipped:Tabard] Snowball lines need the tabard OFF on bosses (warns 'Tabard on!'), /use [equipped:Tabard] ... lines need it ON (warns 'Tabard off!'). Either way, pulling in the wrong state silently disarms every gated line.\n\nWith 'Set your shirt/tabard for bosses automatically' enabled this warning steps back out of combat — Nock changes the garment itself — and only fires in combat (gear is locked then) or when the automatic change was blocked (bags full).\n\nFor the still-on case the square shows the worn garment's own icon — the exact thing to remove.",
    thresholds  = {},
  },
  {
    key         = "karaborNeck",
    category    = "gear",
    name        = "Karabor neck still on (Black Temple)",
    severity    = "red",
    enabledKey  = "warnKaraborNeckEnabled",
    iconFn      = function() return itemIcon(32757) or "Interface\\Icons\\INV_Jewelry_Necklace_15" end,
    description = "For Medallion of Karabor carriers: the neck teleports you TO Black Temple, and forgetting it on once inside costs you a real neck's stats for the whole run. Warns while it is worn in BT — except around Mother Shahraz, the one fight where its Shadow Resistance is exactly what you want.",
    logic       = "Fires when ALL of:\n• You are inside Black Temple\n• The Medallion of Karabor (32649) or Blessed Medallion of Karabor (32757) is in your neck slot\n• Mother Shahraz is not around\n\n|cffffd200The Mother Shahraz exception:|r seeing her — targeted, moused over, focused, on a boss frame or a nameplate — stands the warning down, and the sighting lingers half a minute so a blinking nameplate doesn't flicker it. Walking up to her room with the neck already on is the correct play, so the approach stays quiet. The moment she is dead the warning is back: time to put the real neck on again.\n\nThe square shows the worn medallion's own icon — the thing to swap out.\n\nOutside Black Temple this check costs nothing and never fires.",
    thresholds  = {},
  },
  {
    key         = "quiver",
    category    = "gear",
    name        = "Quiver almost empty",
    severity    = "red",
    enabledKey  = "warnQuiverEnabled",
    iconFn      = function()
      return (GetInventoryItemTexture and GetInventoryItemTexture("player", 0))
             or "Interface\\Icons\\INV_Misc_Quiver_05"
    end,
    description = "Counts only the arrows (or bullets) physically in your quiver or ammo pouch — the ones your bow can actually fire. A stack sitting in the backpack does not count until you move it over.",
    logic       = "Fires when:\n• A quiver or ammo pouch is equipped\n• The ammo inside it is below the threshold\n\nIn and out of combat — running dry mid-fight is when it matters. This is a different number from the info row's arrow counter and the shopping list's ammo total, which add the ammo in your regular bags and the charges on your arrow makers.\n\nThe square shows your equipped ammo's icon with the count left in the quiver.",
    thresholds  = {
      { key = "quiverArrowThreshold", label = "Arrows left in the quiver", min = 50, max = 2000, step = 50 },
    },
  },
  {
    key         = "aspect",
    category    = "you",
    name        = "Wrong aspect (not Hawk)",
    severity    = "amber",
    enabledKey  = "warnAspectEnabled",
    iconFn      = function() return spellIcon(C.SpellID.ASPECT_HAWK) or 136116 end,
    description = "Idiot check: nags when you're in combat with anything other than Aspect of the Hawk up — or with no aspect at all.",
    logic       = "Fires when:\n• You are in combat\n• Your active aspect is not Aspect of the Hawk (any rank), OR you have no aspect at all\n• (if 'Only inside a raid instance' is on) you are in a raid instance\n\nThe square shows your CURRENT aspect's icon, so you can see at a glance what you're actually in; with no aspect up it shows the Hawk icon instead — i.e. the button to press.\n\nAspect of the Viper is NOT exempt. It's a large DPS loss in combat, and forgetting to swap back out of it is exactly the mistake this catches.\n\nCombat-gated: out of combat this never fires, so Cheetah/Pack while travelling and a Viper top-up between pulls stay silent.\n\nAspects are matched by localized name via a stable internal key, so every rank resolves — not just the max ranks.\n\nThe raid gate is instance-based: it checks you're physically inside a raid, so an open-world raid group does not count — and battlegrounds and arenas never count. Handy if Cheetah/Beast in combat is fine while questing or in PvP but never in a raid.",
    thresholds  = {},
    extraToggles = {
      { key = "warnAspectRaidOnly", label = "Only inside a raid instance" },
    },
  },
  {
    key         = "dazed",
    category    = "you",
    name        = "Dazed",
    severity    = "amber",
    enabledKey  = "warnDazedEnabled",
    iconFn      = function() return spellIcon(C.SpellID.DAZED) or DAZED_FALLBACK_ICON end,
    description = "Alerts when you're Dazed in combat — you're slowed and locked out of casting until it falls off. Optional sound cue.",
    logic       = "Fires when:\n• You are in combat\n• You have the Dazed debuff\n\nDaze comes from being struck from behind while moving; the fix is to stop moving or turn to face, so the cue is worth hearing rather than spotting.\n\nThe sound plays ONCE per Daze (edge-triggered), not repeatedly while it's on you. It re-arms as soon as the debuff drops, so a fresh Daze cues again immediately.\n\nMatched by the localized aura name — several mob abilities apply a 'Dazed' aura under different spell IDs, so a name match catches all of them.",
    thresholds  = {},
    mediaSelectors = {
      { key = "warnDazedSound", label = "Sound on Daze", mediaType = "sound" },
    },
  },
  {
    key         = "targetFrenzy",
    category    = "combat",
    name        = "Target Frenzy / Enrage (Tranq Shot)",
    severity    = "amber",
    enabledKey  = "warnTargetFrenzyEnabled",
    iconFn      = function() return spellIcon(C.SpellID.TRANQ_SHOT) or 132294 end,
    description = "Reminds you to Tranq Shot when the current target has an enrage buff.",
    logic       = "Fires when ALL of:\n• Target exists, is alive, and is attackable\n• Tranq Shot is off cooldown\n• Target has a buff matching either the enrage spell-ID list below OR a localized name containing 'Frenzy' / 'Enrage' (case-sensitive substring; enUS-only fallback)\n\nThe ID list is locale-proof with zero false positives; the name fallback covers unknown encounters but may flag any non-Tranqable buff whose name happens to contain those words.",
    thresholds  = {},
    inputs = {
      { key = "warnTargetFrenzyIds",
        label = "Enrage spell IDs",
        desc  = "Comma/newline-separated spell IDs to flag (locale-proof). Anything not listed still triggers via the 'Frenzy'/'Enrage' name match. Find IDs on Wowhead (the URL ends with the ID).",
        multiline = 3 },
    },
  },
  {
    key         = "sapperAoe",
    category    = "combat",
    name        = "Sapper on packs (AoE)",
    severity    = "amber",
    enabledKey  = "warnSapperAoeEnabled",
    iconFn      = function() return itemIcon(23827) or itemIcon(10646) end,
    description = "Suggests throwing a Sapper Charge when a boss pull has several adds bunched within its blast radius.",
    logic       = "Fires when ALL of:\n• You are in a raid\n• Your target is a boss (??-level or worldboss classification)\n• At least the configured number of hostile mobs are within ~11 yd of you (counted from active enemy nameplates — these must be on)\n• A Sapper Charge (Super 23827 → Goblin 10646) is in your bags and off cooldown\n\nThe detection radius is fixed (~11 yd). Friendly players are not counted.",
    thresholds  = {
      { key = "sapperMobCountThreshold", label = "Min hostile mobs in range", min = 2, max = 10, step = 1 },
    },
  },
  {
    key         = "fdResist",
    category    = "you",
    name        = "Feign Death resist",
    severity    = "red",
    enabledKey  = "warnFDResistEnabled",
    iconFn      = function() return spellIcon(C.SpellID.FEIGN_DEATH) or 132293 end,
    description = "Flashes red when your Feign Death is resisted (meaning combat doesn't drop). Optionally plays a sound.",
    logic       = "Fires when:\n• A SPELL_MISSED combat-log event is detected\n• Source is you, spell is Feign Death (5384)\n\nStays visible for the configured duration after the resist; later resists within the window restart the timer.",
    thresholds  = {
      { key = "warnFDResistTimeout", label = "Warning duration (s)", min = 1, max = 15, step = 1 },
    },
    mediaSelectors = {
      { key = "warnFDResistSound", label = "Sound on resist", mediaType = "sound" },
    },
  },
  {
    key         = "bossMark",
    category    = "boss",
    name        = "Boss mark — Feign Death now",
    severity    = "red",
    enabledKey  = "warnBossMarkEnabled",
    iconFn      = function() return spellIcon(C.SpellID.FEIGN_DEATH) or 132293 end,
    description = "Shouts FEIGN DEATH NOW across the middle of the screen when a boss aims its single-target mark at you, in the second or so you still have to answer it.\n\n|cffffd200Teron Gorefiend — Shadow of Death|r (Black Temple). Feign Death during the 1.5s cast makes it fail outright: you never get the debuff, and he doesn't try again for ~30 seconds.\n\n|cffffd200Archimonde — Air Burst|r (Mount Hyjal). The 1.7s cast ends in a knockback, and the fall is what kills you. Feign Death saves the landing.",
    logic       = "For each encounter, fires when EITHER of:\n• The combat log's SPELL_CAST_START for that spell — Shadow of Death (40251), Air Burst (32014) — names YOU as the destination. The certain path.\n• The boss's own unit target is you. The fallback, in case this client's combat log carries no destination for that cast. The boss is confirmed by NPC id (Teron 22871, Archimonde 17968) out of a nameplate or your target, so nothing else can raise it.\n\nA cast the log says is aimed at SOMEONE ELSE suppresses the fallback for the length of that cast — otherwise any glance in your direction during another player's mark would warn.\n\n|cffffd200The fallback is gated differently per boss, on purpose:|r\n• |cff909090Teron|r stands still and marks one person, so his target is evidence on its own. His check is NOT tied to the cast event — gating it there would make it useless in exactly the case it exists for.\n• |cff909090Archimonde|r is tanked, and fear and doomfires move his target all fight. His check only counts while an Air Burst is actually in flight; outside one, \"he is looking at me\" means nothing.\n\nThis alert does NOT use the warning squares: it draws its own large banner (drag it while frames are unlocked, where it holds itself open so it can be placed). Both bosses share that one banner, its position and the cue — the cue is the only one in Nock that defaults to audible.\n\n|cff909090Feign Death on cooldown:|r the banner reads MARKED - NO FD or AIR BURST - NO FD instead, so it never tells you to press something you can't.\n\n|cff909090/nock bossmark|r prints what the last cast of each spell actually carried and what the unit lookup can see; |cff909090/nock bossmark test|r previews the banner and the sound.",
    extraToggles = {
      { key = "warnBossMarkTeron",      label = "Teron Gorefiend — Shadow of Death" },
      { key = "warnBossMarkArchimonde", label = "Archimonde — Air Burst" },
    },
    thresholds  = {
      { key = "bossBannerSize", label = "Banner icon size (px)", min = 48, max = 200, step = 4 },
    },
    mediaSelectors = {
      { key = "warnBossMarkSound", label = "Sound when marked", mediaType = "sound" },
    },
  },
  {
    key         = "noRelease",
    category    = "boss",
    name        = "DO NOT RELEASE (Sated after a wipe)",
    severity    = "red",
    enabledKey  = "warnNoReleaseEnabled",
    iconFn      = function() return spellIcon(C.SpellID.SATED) or 136090 end,
    description = "Shouts DO NOT RELEASE across the middle of the screen while you lie dead with the Sated/Exhaustion debuff still on you — the raid burned Bloodlust/Heroism this attempt.",
    logic       = "Fires when ALL of:\n• You are dead and have NOT yet released your spirit\n• The Sated (Bloodlust) or Exhaustion (Heroism) debuff is on you\n\nClears the moment you release, are resurrected, or the debuff runs out.\n\nThis alert does NOT use the warning squares: it draws on the same centre banner as the boss-mark warning, sharing its position. The size slider below is that shared banner's size — the same key the boss-mark section exposes. Like that banner, it obeys the master 'Enable warnings' switch.\n\n|cff909090/nock norelease|r previews the banner for 5 seconds so you can see (and place) it without wiping.",
    thresholds  = {
      -- The SHARED banner size (same profile key as the bossMark entry's
      -- slider): each copy is gated on its own warning's enable flag, so the
      -- size stays reachable for someone running only one of the two.
      { key = "bossBannerSize", label = "Banner icon size (px)", min = 48, max = 200, step = 4 },
    },
  },
  {
    key         = "slammer",
    category    = "boss",
    name        = "Anetheron — Sulfuron Slammer button",
    severity    = "red",
    enabledKey  = "warnSlammerEnabled",
    iconFn      = function() return itemIcon(C.SULFURON_SLAMMER_ITEM) or 135453 end,
    description = "|cffff4040EXPERIMENTAL - off by default until it has seen a real Anetheron.|r\n\nA CLICKABLE button for Anetheron (Mount Hyjal): clicking it drinks a Sulfuron Slammer, whose fire-breath tick on yourself breaks his Sleep. It counts down to the earliest next Sleep, reads CLICK NOW while the window is open and the buff is not, shows the buff's remaining seconds while you are covered, and judges every Sleep that goes out.",
    logic       = "Sleep is instant — no cast bar, ever — so the window is the whole prompt. It opens 20 s after each Sleep (16 s after the pull) and stays open until the next one — BigWigs times them 19.5–45 s apart. The prompt fires a configurable leeway EARLY (1 s by default): an early drink costs nothing, a late one gets you slept. While the window is closed a thin bar under the icon fills toward the opening, red for the last seconds. Inside it:\n• No buff → |cffff4040CLICK NOW|r. The buff lasts 6 s, so it prompts again each time it runs out.\n• Buff up → COVERED with its seconds left.\n\nWhen a Sleep goes out (combat log, spell 31298):\n• Buff up for at least the margin → quiet.\n• Buff under the margin, or absent → |cffff4040EXPOSED|r for 2 s. The horn plays on that verdict, but by then it is too late to act, so it ships silent — the soft sound at each window opening is the actionable cue. If it landed on you the button reads SLEPT until the tick (or 10 s) ends it.\n\n|cffffd200Where it shows:|r the button is a secure frame, which the client will not let an addon show or hide in combat. It is up while Anetheron is in view — targeted, moused over, on a nameplate or as boss1 (the waves drop combat between them and he stands alone, so target him before the pull) — and while a fight with him runs, but only with Sulfuron Slammers in your bags (Midsummer vendor drink, stacks of 10 — the shopping list tracks them): a button you cannot click is noise. It goes when he is out of view, dies, or you leave. Unlock frames to place it; it holds itself open there, reading |cff909090NO SLAMMER|r in red when your bags are empty.\n\n|cff909090Remove the drunk effect:|r the Slammer is a drink, and the client's blur stays for minutes. The checkbox IS the |cff909090ffxGlow|r console variable: ticked sets it to 0 (no blur), unticked sets it back to 1. It reads the live value, so it shows ticked if you already run ffxGlow 0.\n\n|cff909090/nock slammer|r dumps what the watcher sees; |cff909090/nock slammer test|r holds the button open with a short first window (a real button — clicking it drinks), |cff909090/nock slammer cast|r fakes a Sleep for the verdict and the horn, |cff909090/nock slammer off|r ends the preview.",
    thresholds  = {
      { key = "slammerWindow",      label = "Window after a Sleep (s)",     min = 10, max = 30, step = 0.5 },
      { key = "slammerLeeway",      label = "Prompt this early before the window (s)", min = 0, max = 5, step = 0.5 },
      { key = "slammerCoverMargin", label = "Buff left at the Sleep that still counts as covered (s)", min = 1.3, max = 3, step = 0.1 },
      { key = "slammerButtonSize",  label = "Button size (px)",             min = 32, max = 96, step = 2 },
    },
    extraToggles = {
      -- The checkbox IS the CVar (user, 2026-08-29: a hard flip, no restore):
      -- read live, written on click, never in the profile.
      { key = "slammerNoDrunk", label = "Remove the drunk effect (ffxGlow 0)",
        get = function() return GetCVar and GetCVar("ffxGlow") == "0" end,
        set = function(v) if SetCVar then SetCVar("ffxGlow", v and "0" or "1") end end },
    },
    mediaSelectors = {
      { key = "warnSlammerSound",       label = "Sound when caught exposed (off by default — too late to act on)", mediaType = "sound" },
      { key = "warnSlammerWindowSound", label = "Sound when the window opens (soft)", mediaType = "sound" },
    },
  },
  {
    key         = "ripper",
    category    = "you",
    name        = "Ripper / Transporter — ALT F4 countdown",
    severity    = "red",
    enabledKey  = "warnRipperEnabled",
    iconFn      = function() return itemIcon(C.RIPPER_ITEMS[1]) or 134376 end,
    description = "Big centre-screen countdown while you cast the Dimensional Ripper - Area 52 or the Ultrasafe Transporter: Toshley's Station: the whole seconds down to a moment just before the cast ends, then |cffff4040ALT F4|r. Close the client right there and you keep the trinket's side effect (a bigger character is a real help in a raid) without the trip.",
    logic       = "Fires when a cast of either trinket starts (the item's own use effect, read off the item).\n\n• Counts the whole seconds (9 … 1) down to |cffffd200cast end − lead|r (the slider below, 1 s by default).\n• At that moment the text flips to |cffff4040ALT F4|r and stays until the cast ends or is cancelled.\n\nThe countdown is text only — Nock never closes the client for you. Unlock frames to place it; it holds itself open there.\n\n|cff909090/nock ripper test|r runs a fake 10 s cast (|cff909090/nock ripper test 5|r for 5 s), |cff909090/nock ripper off|r ends it, |cff909090/nock ripper|r dumps what the watcher resolved.",
    thresholds  = {
      { key = "ripperLead",     label = "Lead before the cast ends (s)", min = 0.5, max = 3, step = 0.1 },
      { key = "ripperTextSize", label = "Text size (px)",                min = 32, max = 160, step = 4 },
    },
    mediaSelectors = {
      { key = "warnRipperSound", label = "Sound at ALT F4", mediaType = "sound" },
    },
  },
  {
    key         = "mana",
    category    = "you",
    name        = "Low Mana",
    severity    = "blue",
    enabledKey  = "warnManaEnabled",
    iconFn      = function() return spellIcon(C.SpellID.ASPECT_VIPER) or 132160 end,
    description = "Suggests a mana item, or swapping to Aspect of the Viper, when mana runs low.",
    logic       = "Fires when:\n• Mana < suggest threshold → blue\n• Mana < panic threshold → red (ignores mid-cast suppression)\n• Otherwise: while mid-cast, suppressed until panicking\n\nIcon shows the first ready mana item: Dark Rune → Mana Injector → Super Mana Potion. If no item is owned and you aren't already in Viper, the icon shows Aspect of the Viper as a fallback.",
    thresholds  = {
      { key = "manaSuggestThreshold", label = "Suggest threshold (%)", min = 30, max = 80, step = 5 },
      { key = "manaPanicThreshold",   label = "Panic threshold (%)",    min = 5,  max = 40, step = 5 },
    },
  },
  {
    key         = "lustCds",
    name        = "Burst CDs in Lust",
    severity    = "amber",
    enabledKey  = "warnLustCdsEnabled",
    iconFn      = function() return bloodlustIcon or spellIcon(C.SpellID.BLOODLUST) or 136012 end,
    description = "Reminds you to pop Rapid Fire + trinkets + Haste Potion while Bloodlust/Heroism is up.",
    logic       = ("Fires when:\n• Bloodlust or Heroism is active on you\n• Your effective ranged speed (eWS) ≥ %.2fs — i.e. you haven't already saturated on haste\n\nText lists any of these abilities/items that are ready: Rapid Fire, Haste Potion, Trinket 1, Trinket 2.\n\nA trinket slot is only listed when the equipped trinket has a |cffffd200Use:|r effect. Passive proc trinkets (Dragonspine Trophy, Tsunami Talisman) are never named — there is nothing to press.\n\n|cff909090Speak aloud:|r when enabled, chains your on-use trinkets by voice during Lust — the moment the first trinket goes on cooldown, the other one is called out (\"Trinket 2\", or \"Trinket 1\" if you popped slot 2 first) via the game's text-to-speech. Only applies while BOTH equipped trinkets have an on-use effect; once per Lust window (off by default)."):format(SATURATION_EWS),
    thresholds  = {},
    extraToggles = {
      { key = "warnLustCdsVoice",
        label = "Speak the second trinket aloud when the first is popped during Lust" },
    },
  },
  {
    key         = "drums",
    name        = "Drums of Battle (info)",
    severity    = "blue",
    enabledKey  = "warnDrumsEnabled",
    iconFn      = function() return itemIcon(29529) or 134372 end,
    description = "Informational badge showing the remaining time on your Drums of Battle buff.",
    logic       = "Fires whenever the Drums of Battle buff (spell 35476) is active on you, with a live countdown.",
    thresholds  = {},
  },
  -- Weapon stone moved to the Helpers panel (Modules/Helpers.lua / Helpers tab).
  -- The profile keys weaponStoneEnabled / weaponStoneCombatOnly / weaponStoneExpiringSec
  -- remain for backwards compatibility but no longer drive UI.
  {
    key         = "utilities",
    name        = "Utility item buffs (info)",
    severity    = "blue",
    enabledKey  = "warnUtilitiesEnabled",
    iconFn      = function() return itemIcon(4397) or 132180 end,  -- Gnomish Cloaking Device
    description = "One blue badge per active buff from any item listed in Constants.UTIL_ITEMS (Cloaking Device, Parachute, etc.).",
    logic       = "Fires whenever you have an active buff matching one of the utility items. Each active buff gets its own square with the item's label and remaining time.",
    thresholds  = {},
  },
}
