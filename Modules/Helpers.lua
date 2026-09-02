-- Modules/Helpers.lua
-- Pre-pull consumable + situational helper checks. Writes to state.helpers as
-- an ordered array of { id, status, icon, remaining, label }. The view
-- (Frame_Helpers) consumes the list and renders one badge per entry.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Helpers = Nock:NewModule("Helpers", "AceEvent-3.0")
local C = Nock.Constants

-- Every ID lives in Core/ConsumeData.lua, which the .toc loads first.
local CD = Nock.ConsumeData

local function spellIcon(id)
  if not id then return nil end
  if GetSpellInfo then
    local _, _, icon = GetSpellInfo(id)
    if icon then return icon end
  end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  return nil
end

local function itemIcon(id)
  if not id then return nil end
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

local function isEnabled(key)
  if not key then return true end
  local p = Nock.db and Nock.db.profile
  if not p then return true end
  local v = p[key]
  if v == nil then return true end
  return v and true or false
end

-- Buff matching is by spell ID against Core/ConsumeData.lua sets. Aura names
-- are display-only here, and they lied to us historically: a Scroll of
-- Agility's aura is named just "Agility", which name matching never caught.
--
-- `cat.buffNames` is an opt-in safety net that only the food category sets —
-- see the comment there for why that one case earns it.
-- Aura reads go through Core/AuraCache.lua (every read allocates ~1.9 KB on
-- this client; this panel used to walk the player and the pet ~12 times per
-- refresh). One pass over the store with a module-level callback.
local AC = Nock.AuraCache
local sc_set, sc_names, sc_exp
local function onAura(a)
  if sc_exp or a.isHarmful then return end
  local spellId, name = a.spellId, a.name
  if (spellId and sc_set and sc_set[spellId]) or (sc_names and name and sc_names[name]) then
    sc_exp = a.expirationTime or 0
  end
end

local function findUnitBuffIn(unit, cat)
  if not (AC and cat and UnitExists and UnitExists(unit)) then return nil end
  local set, names = cat.buffs, cat.buffNames
  if not (set or names) then return nil end
  sc_set, sc_names, sc_exp = set, names, nil
  AC.ForEach(unit, onAura)
  return sc_exp
end

local function playerBuffExp(catKey)
  return findUnitBuffIn("player", CD[catKey])
end

-- Seconds under which an ACTIVE buff surfaces as "expiring" (0 disables).
local function expiringThreshold()
  local p = Nock.db and Nock.db.profile
  local v = p and p.helpersExpiringThreshold
  if v == nil then v = 180 end
  return v
end

-- Shared active/missing shape: an expiration in the future is "active", and
-- the caller decides whether its remaining time is short enough to surface.
local function statusFromExp(exp)
  if exp and exp > GetTime() then
    return "active", math.max(0, exp - GetTime())
  end
  return "missing"
end

local function hasAnyItem(itemSet)
  if not itemSet or not GetItemCount then return false end
  for id in pairs(itemSet) do
    if (GetItemCount(id) or 0) > 0 then return true end
  end
  return false
end

-- Which scroll is missing, if any. Both missing reads as Agility first (the
-- bigger hunter stat); both up returns the sooner expiry. The third value is
-- the sub-state the row publishes ("agi" / "str"), nil once both are up.
local function scrollState(unit)
  local a = findUnitBuffIn(unit, CD.scrollAgility)
  local s = findUnitBuffIn(unit, CD.scrollStrength)
  if not a then return "missing", nil, "agi" end
  if not s then return "missing", nil, "str" end
  return statusFromExp(math.min(a, s))
end

local function isParseMode()
  local p = Nock.db and Nock.db.profile
  if not p then return true end
  return p.parseMode ~= false
end

-- isInInstance     — true inside any instanced content (5-man dungeons + raids).
--                    Gates the entire helpers panel: outside instances we don't
--                    bug the player about consumables.
-- isInRaidInstance — true only inside a raid (10/25-man). Further gates the
--                    scroll helpers — outside raids, parse-tier scrolls are overkill.
--
-- Both delegate to Core, which owns the one IsInInstance() call shape now that
-- Warnings needs the same probe for its per-warning "raid only" toggles. Kept as
-- locals rather than inlining Nock.* at the call sites below: same names, same
-- semantics, no churn.
--
-- `/nock helpers test` (state.helpersTestMode, session-only) opens both gates
-- so the row can be exercised on a dummy out in the world.
local function isInInstance()
  if Nock.state.helpersTestMode then return true end
  return Nock.IsInInstance()
end
local function isInRaidInstance()
  if Nock.state.helpersTestMode then return true end
  return Nock.IsInRaidInstance()
end

local function petAliveAndExists()
  if not (UnitExists and UnitExists("pet")) then return false end
  if UnitIsDead and UnitIsDead("pet") then return false end
  return true
end

-- Temp enchants on both hands. GetWeaponEnchantInfo returns hasMH, mhExpMs,
-- mhCharges, mhEnchantId, hasOH, ohExpMs, ohCharges, ohEnchantId.
local function handStoneInfo()
  if not GetWeaponEnchantInfo then return false, 0, false, 0 end
  local hasMH, mhMs, _, _, hasOH, ohMs = GetWeaponEnchantInfo()
  return hasMH and true or false, (mhMs or 0) / 1000,
         hasOH and true or false, (ohMs or 0) / 1000
end

-- True when the player is wielding a 2H (no offhand weapon equipped).
local function wieldingTwoHand()
  local p = Nock.state and Nock.state.player
  return p and p.canWeave or false
end

-- Which hand is missing its stone: main hand first, then the off hand while
-- dual wielding. Both up returns the sooner expiry. Same three-value shape
-- as scrollState, so the row publishes "mh" / "oh" as its sub-state.
local function stoneState()
  local hasMH, mhLeft, hasOH, ohLeft = handStoneInfo()
  local dual = not wieldingTwoHand()
  if not hasMH then return "missing", nil, "mh" end
  if dual and not hasOH then return "missing", nil, "oh" end
  local left = mhLeft
  if dual and hasOH then left = math.min(mhLeft, ohLeft) end
  return "active", left > 0 and left or nil
end

local function isBossTarget()
  if not (UnitExists and UnitExists("target")) then return false end
  if Nock.state.helpersTestCreature then return true end
  if UnitIsDead and UnitIsDead("target") then return false end
  if UnitCanAttack and not UnitCanAttack("player", "target") then return false end
  if UnitClassification and UnitClassification("target") == "worldboss" then return true end
  if UnitLevel and UnitLevel("target") == -1 then return true end
  return false
end

local function targetCreatureType()
  if not UnitExists or not UnitExists("target") then return nil end
  if Nock.state.helpersTestCreature then return Nock.state.helpersTestCreature end
  if not UnitCreatureType then return nil end
  return UnitCreatureType("target")
end

-- Pure: the item a click would use for a ConsumeData category. Preferred
-- order first, then any listed item in bags (lowest ID, so it is stable).
-- `kind` (stones only) narrows the pick to items whose cat.kind matches, so
-- a mace is offered a weightstone and a sword a sharpening stone; nil means
-- any item of the category.
function Helpers.PickApplyItem(cat, kind)
  if not (cat and GetItemCount) then return nil end
  -- No closure here: this runs on the refresh lane, which must not allocate.
  local kinds = kind and cat.kind or nil
  local prefer = cat.prefer
  if prefer then
    for i = 1, #prefer do
      local id = prefer[i]
      if (not kinds or kinds[id] == kind) and (GetItemCount(id) or 0) > 0 then return id end
    end
  end
  local best
  for id in pairs(cat.items or {}) do
    if (not kinds or kinds[id] == kind) and (GetItemCount(id) or 0) > 0
       and (not best or id < best) then
      best = id
    end
  end
  return best
end

-- Weapon subclass IDs (GetItemInfoInstant's 7th return, class 2 = Weapon).
-- Blunt takes a weightstone, everything else edged takes a sharpening stone.
-- Fist weapons (13) are filed under sharp pending an in-game check.
local BLUNT_SUBCLASS = { [4] = true, [5] = true, [10] = true }   -- 1H mace, 2H mace, staff
local SHARP_SUBCLASS = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true,
                         [13] = true, [15] = true }              -- axes, polearm, swords, fist, dagger

-- "sharp" / "blunt" for the weapon in an inventory slot, nil when unknown
-- (empty slot, or the item is not cached yet — then any stone is offered).
local function weaponKind(slot)
  if not GetInventoryItemID then return nil end
  local id = GetInventoryItemID("player", slot)
  if not id then return nil end
  if GetItemInfoInstant then
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(id)
    if classID == 2 and subclassID then
      if BLUNT_SUBCLASS[subclassID] then return "blunt" end
      if SHARP_SUBCLASS[subclassID] then return "sharp" end
    end
    return nil
  end
  if GetItemInfo then
    local _, _, _, _, _, _, subType = GetItemInfo(id)
    if type(subType) == "string" then
      if subType:find("Mace") or subType:find("Staff") then return "blunt" end
      return "sharp"
    end
  end
  return nil
end

-- The eating channel is an aura named "Food" on every food; a name is fine
-- here because a miss only delays the EATING look, it never nags.
local function isEating()
  local rec = AC and AC.ByName and AC.ByName("player", "Food")
  return rec and (rec.expirationTime or 0) > GetTime() or false
end

-- Applying = our real cast (state.player.casting, the lockout reading) is the
-- item's own use spell. Instant consumables never enter this phase.
local function isApplying(itemId)
  local cast = Nock.state.player.casting
  if not (cast and cast.name and itemId and GetItemSpell) then return false end
  return cast.name == GetItemSpell(itemId)
end

local function clickToApplyEnabled()
  local p = Nock.db and Nock.db.profile
  return not (p and p.helpersClickToApply == false)
end

-- Each catalog entry's check() returns a status string, optional remaining
-- seconds and (scroll rows only) the missing scroll's sub-state.
-- "active"  → the buff is up; Refresh surfaces it only inside the expiring band
-- "missing" → greyed badge (always surfaces)
-- "hidden"  → don't render at all
--
-- `data` names the Core/ConsumeData.lua category the entry matches against
-- and whose `prefer` / `items` lists drive the bag scan and the click.
-- `shortLabel` is the band text inside the icon, `noLabel` replaces it when
-- nothing usable is in bags, `unit` adds the YOU / PET tag, `applyKind` says
-- how the click layer uses the item (plain, on the pet, on the main hand).
Helpers.Catalog = {
  {
    key           = "food",
    data          = "food",
    shortLabel    = "FOOD",
    noLabel       = "NO FOOD",
    applyKind     = "item",
    phases        = true,   -- the eating channel shows as EATING
    itemIds       = CD.food.items,
    name          = "Food buff",
    enabledKey    = "helperFoodEnabled",
    iconFn        = function() return itemIcon(27655) or itemIcon(27659) or 132922 end,  -- Ravager Dog
    description   = "Tracks the 'Well Fed' food buff on the player. Best hunter options: Ravager Dog (+40 AP), Spicy Hot Talbuk (+20 hit), Warp Burger / Grilled Mudfish (+20 agi).",
    logic         = "Matched by buff spell ID against the hunter food list, with the aura name 'Well Fed' as a fallback so an unlisted food can't nag you forever. Missing when nothing is up; shows a countdown once it drops under the expiring threshold. Reads NO FOOD when you have none in your bags, EATING while the channel runs.",
    check         = function() return statusFromExp(playerBuffExp("food")) end,
  },
  {
    key           = "flask",
    data          = "flask",
    shortLabel    = "FLASK",
    noLabel       = "NO FLASK",
    applyKind     = "item",
    itemIds       = CD.flask.items,
    name          = "Flask",
    enabledKey    = "helperFlaskEnabled",
    iconFn        = function() return itemIcon(22854) or 134087 end,  -- Flask of Relentless Assault
    description   = "Tracks any flask buff on the player (by spell ID).",
    logic         = "Hidden entirely if you've committed to elixirs (elixir buff up OR an elixir in bags) — a flask would conflict. Otherwise missing/expiring like the rest. Reads NO FLASK when nothing's up and no flask is in bags.",
    check         = function()
      -- Player has committed to elixirs (active buff OR elixir in bags) —
      -- a flask would conflict, so don't nag about it.
      if playerBuffExp("battleElixir") or playerBuffExp("guardianElixir") then return "hidden" end
      if hasAnyItem(CD.battleElixir.items) or hasAnyItem(CD.guardianElixir.items) then
        return "hidden"
      end
      return statusFromExp(playerBuffExp("flask"))
    end,
  },
  {
    key           = "battleElixir",
    data          = "battleElixir",
    shortLabel    = "BATTLE",
    noLabel       = "NO ELIXIR",
    applyKind     = "item",
    itemIds       = CD.battleElixir.items,
    name          = "Battle elixir",
    enabledKey    = "helperBattleElixirEnabled",
    iconFn        = function() return itemIcon(22831) or 134169 end,  -- Elixir of Major Agility
    description   = "Tracks a battle elixir (by spell ID, all ranks).",
    logic         = "A flask consumes both elixir slots, so an active flask counts as covered. Missing/expiring otherwise. Reads NO ELIXIR when no battle elixir is in your bags.",
    check         = function()
      -- Flasks consume both battle + guardian slots — having one up counts.
      local flaskExp = playerBuffExp("flask")
      if flaskExp then return statusFromExp(flaskExp) end
      return statusFromExp(playerBuffExp("battleElixir"))
    end,
  },
  {
    key           = "guardianElixir",
    data          = "guardianElixir",
    shortLabel    = "GUARD",
    noLabel       = "NO ELIXIR",
    applyKind     = "item",
    itemIds       = CD.guardianElixir.items,
    name          = "Guardian elixir",
    enabledKey    = "helperGuardianElixirEnabled",
    iconFn        = function() return itemIcon(22840) or itemIcon(20007) or 134849 end,
    description   = "Tracks a guardian elixir (by spell ID, all ranks).",
    logic         = "A flask consumes both elixir slots, so an active flask counts as covered. Missing/expiring otherwise. Reads NO ELIXIR when no guardian elixir is in your bags.",
    check         = function()
      local flaskExp = playerBuffExp("flask")
      if flaskExp then return statusFromExp(flaskExp) end
      return statusFromExp(playerBuffExp("guardianElixir"))
    end,
  },
  {
    key           = "sharpeningStone",
    data          = "sharpeningStone",
    subData       = { mh = "sharpeningStone", oh = "sharpeningStone" },
    subLabel      = { mh = "STONE", oh = "STONE" },
    subUnit       = { mh = "mh", oh = "oh" },
    subSlot       = { mh = 16, oh = 17 },
    subKind       = function(sub) return weaponKind(sub == "oh" and 17 or 16) end,
    shortLabel    = "STONE",
    noLabel       = "NO STONE",
    applyKind     = "weapon",
    itemIds       = CD.sharpeningStone.items,
    name          = "Weapon stones",
    enabledKey    = "helperStoneEnabled",
    iconFn        = function() return itemIcon(23529) or 135243 end,
    description   = "Temporary weapon enhancement (sharpening / weightstone) on both hands of a dual wielder. Skipped on 2H weapons (a weaver's main hand carries Windfury).",
    logic         = "Visible only while dual wielding. The badge names the hand that is missing its stone (MAIN first, then OFF) and a click applies the stone to exactly that hand — a sharpening stone on a blade, a weightstone on a mace; once both are stoned the sooner expiry drives the expiring countdown. Reads NO STONE when no stone of the right kind is in your bags.",
    check         = function()
      if wieldingTwoHand() then return "hidden" end
      return stoneState()
    end,
  },
  {
    key           = "kibler",
    data          = "kibler",
    shortLabel    = "PET FOOD",
    noLabel       = "NO FOOD",
    applyKind     = "pet",
    unit          = "pet",
    itemIds       = CD.kibler.items,
    name          = "Pet food",
    enabledKey    = "helperKiblerEnabled",
    iconFn        = function() return itemIcon(33874) or 134059 end,
    description   = "Pet food buff — Kibler's Bits (+20 Strength) or Sporeling Snack (+20 Stamina).",
    logic         = "Matched by spell ID on the pet. The pet's aura is named 'Well Fed' just like your own food, so only the ID tells them apart. Hidden when no pet is summoned or the pet is dead. Reads NO FOOD (with the PET tag) when no pet food is in your bags.",
    check         = function()
      if not petAliveAndExists() then return "hidden" end
      return statusFromExp(findUnitBuffIn("pet", CD.kibler))
    end,
  },
  {
    key           = "scrollPlayer",
    data          = "scrollAgility",
    subData       = { agi = "scrollAgility", str = "scrollStrength" },
    subLabel      = { agi = "AGI", str = "STR" },
    shortLabel    = "SCROLLS",
    noLabel       = "NO SCROLL",
    applyKind     = "item",
    unit          = "player",
    itemIds       = CD.scrollAgility.items,
    name          = "Scrolls on you (parse)",
    enabledKey    = "helperScrollPlayerEnabled",
    iconFn        = function(sub)
      if sub == "str" then return itemIcon(27503) or itemIcon(10310) or 134941 end
      return itemIcon(27498) or itemIcon(10309) or 134941
    end,
    description   = "Parse-mode helper: Scroll of Agility + Scroll of Strength on the player (matched by spell ID — the scroll auras are named just 'Agility' / 'Strength'). The badge carries a YOU tag.",
    logic         = "Visible only when Parse Mode is enabled AND you're inside a raid instance (10/25-man). The badge names the scroll that is missing (AGI first, then STR) and a click applies exactly that one; once both are up the sooner expiry drives the expiring countdown as SCROLLS. Reads NO SCROLL when the missing scroll isn't in bags.",
    check         = function()
      if not isParseMode() then return "hidden" end
      if not isInRaidInstance() then return "hidden" end
      return scrollState("player")
    end,
  },
  {
    key           = "scrollPet",
    data          = "scrollAgility",
    subData       = { agi = "scrollAgility", str = "scrollStrength" },
    subLabel      = { agi = "AGI", str = "STR" },
    shortLabel    = "SCROLLS",
    noLabel       = "NO SCROLL",
    applyKind     = "pet",
    unit          = "pet",
    itemIds       = CD.scrollStrength.items,
    name          = "Scrolls on pet (parse)",
    enabledKey    = "helperScrollPetEnabled",
    iconFn        = function(sub)
      if sub == "str" then return itemIcon(27503) or itemIcon(10310) or 134941 end
      return itemIcon(27498) or itemIcon(10309) or 134941
    end,
    description   = "Parse-mode helper: Scroll of Agility + Scroll of Strength on the pet (matched by spell ID). The badge carries a PET tag.",
    logic         = "Visible only when Parse Mode is enabled, you're in a raid instance (10/25-man), AND a pet is summoned/alive. The badge names the scroll that is missing on the pet (AGI first, then STR) and a click applies exactly that one to the pet; once both are up the sooner expiry drives the expiring countdown as SCROLLS.",
    check         = function()
      if not isParseMode() then return "hidden" end
      if not isInRaidInstance() then return "hidden" end
      if not petAliveAndExists() then return "hidden" end
      return scrollState("pet")
    end,
  },
  {
    key         = "demonslayer",
    data        = "demonslayer",
    shortLabel  = "DEMON",
    applyKind   = "item",
    -- A 5-minute elixir sits inside the default 5-minute expiring window
    -- from the moment it is drunk; cap its own warning at the last minute.
    expiringThreshold = 60,
    name        = "Elixir of Demonslaying",
    enabledKey  = "helperDemonslayerEnabled",
    iconFn      = function() return itemIcon(9224) or 134194 end,
    description = "Conditional reminder vs Demon-type bosses. Adds +265 damage vs Demons for 5 min.",
    logic       = "Visible only when:\n• Target is a Demon-type creature\n• Target is a boss-class mob (worldboss / skull-level)\n• The elixir is in your bags\n\nMatched by spell ID. Missing like the rest; the expiring countdown only starts in the last 60 seconds (the elixir lasts 5 minutes, so the global window would show it from the first sip). Hidden in any other context.",
    check       = function()
      if targetCreatureType() ~= "Demon" then return "hidden" end
      if not isBossTarget() then return "hidden" end
      -- Only nag if the player actually has the elixir to use.
      if not hasAnyItem(CD.demonslayer.items) then return "hidden" end
      return statusFromExp(playerBuffExp("demonslayer"))
    end,
  },
  {
    key         = "consecratedStone",
    data        = "consecratedStone",
    subData     = { mh = "consecratedStone", oh = "consecratedStone" },
    subLabel    = { mh = "HOLY", oh = "HOLY" },
    subUnit     = { mh = "mh", oh = "oh" },
    subSlot     = { mh = 16, oh = 17 },
    subKind     = function(sub) return weaponKind(sub == "oh" and 17 or 16) end,
    shortLabel  = "HOLY",
    applyKind   = "weapon",
    name        = "Consecrated stone (Undead)",
    enabledKey  = "helperConsecratedEnabled",
    iconFn      = function() return itemIcon(23122) or 135253 end,
    description = "Conditional reminder vs Undead bosses to apply a Consecrated Sharpening Stone.",
    logic       = "Visible only when:\n• Target is an Undead creature\n• Target is a boss-class mob\n• You are dual wielding\n• A consecrated stone is in your bags\n\nActive when ANY temp enchant is present on the hand (we can't read the specific stone's enchant ID); the badge names the bare hand (MAIN, then OFF) and a click applies to it. Won't catch having a regular sharpening stone on instead of a consecrated one.",
    check       = function()
      if targetCreatureType() ~= "Undead" then return "hidden" end
      if not isBossTarget() then return "hidden" end
      if wieldingTwoHand() then return "hidden" end
      -- Only nag if a consecrated stone is in bags (we can't read the active
      -- stone's enchant ID, so this is the best we can do).
      if not hasAnyItem(CD.consecratedStone.items) then return "hidden" end
      return stoneState()
    end,
  },
}

local function isAddOnLoaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
  if IsAddOnLoaded then return IsAddOnLoaded(name) end
  return false
end

-- Comma/newline separated, trimmed, non-empty prefixes from profile.helpersHideWA.
local function waPrefixes()
  local out = {}
  local raw = Nock.db and Nock.db.profile and Nock.db.profile.helpersHideWA
  if type(raw) ~= "string" then return out end
  for token in raw:gmatch("[^,\n]+") do
    local p = token:match("^%s*(.-)%s*$")
    if p ~= "" then out[#out + 1] = p end
  end
  return out
end

-- True iff WeakAuras is loaded AND it holds an aura whose name starts with any
-- configured prefix (i.e. the user already runs a third-party consumes-reminder
-- pack). Event-driven only (see OnEnable) — WeakAurasSaved.displays can be
-- huge, never scan per tick.
local function detectHelperWA()
  local prefixes = waPrefixes()
  if #prefixes == 0 then return false end
  if not isAddOnLoaded("WeakAuras") then return false end
  local saved = _G.WeakAurasSaved
  local displays = saved and saved.displays
  if type(displays) ~= "table" then return false end
  for id in pairs(displays) do
    if type(id) == "string" then
      for _, pref in ipairs(prefixes) do
        if id:sub(1, #pref) == pref then return true end
      end
    end
  end
  return false
end

-- Slow lane (Core:Tick): the check battery below is ~12 full UnitBuff walks
-- plus bag counts and item-icon lookups, and it ran every rendered frame in
-- every trash gap of a raid. A pre-pull badge appearing 100 ms later is
-- invisible; the view diffs against state.helpers regardless.
Helpers.refreshInterval = 0.1

-- The published rows are reused in place (a fresh 5-field table per badge
-- per refresh was the other half of the cost). The view reads fields only.
local ROWS = {}

function Helpers:Refresh(state)
  local list = state.helpers
  for i = #list, 1, -1 do list[i] = nil end

  -- Hidden when: globally disabled, a configured third-party consumes WA is
  -- loaded, or in combat (this is a pre-pull panel — no nagging mid-fight).
  -- The list stays empty so the view hides itself too.
  local p = Nock.db and Nock.db.profile
  if (p and p.showHelpers == false)
     or Nock.state.helpersHiddenByWA
     or Nock.state.player.inCombat then
    return
  end

  -- Helpers panel is instanced-content-only — out in the world we don't nag
  -- about food/flask/etc. Leave the list empty so the view hides itself.
  if not isInInstance() then return end

  local threshold = expiringThreshold()
  local click = clickToApplyEnabled()

  for _, entry in ipairs(Helpers.Catalog) do
    if isEnabled(entry.enabledKey) then
      local status, remaining, sub = entry.check()
      -- Surfacing rule: "missing" always; "active" only once it's about to run
      -- out (the expiring band). Fully-covered buffs stay invisible by design —
      -- no need to nag when there's nothing to do. "hidden" never surfaces.
      -- An entry may cap its own window below the global one (a short buff
      -- would otherwise be "expiring" from the first second); 0 still
      -- disables the early warning everywhere.
      local th = threshold
      if entry.expiringThreshold and entry.expiringThreshold < th then th = entry.expiringThreshold end
      local surface = nil
      if status == "missing" then
        surface = "missing"
      elseif status == "active" and remaining
         and th > 0 and remaining < th then
        surface = "expiring"
      end
      if surface then
        -- Bag category: the missing scroll's for scroll rows, else the entry's.
        local cat = entry.subData and sub and CD[entry.subData[sub]]
          or (entry.data and CD[entry.data]) or nil
        local kind = entry.subKind and sub and entry.subKind(sub) or nil
        local inBags = cat and Helpers.PickApplyItem(cat, kind) or nil

        -- The band text: the short label, or the missing scroll's; NO-X when
        -- there is nothing in bags (only for MISSING — if it's merely expiring
        -- you already own the buff, and the nag is "refresh it", not "go get
        -- one"); EATING / APPLYING while the consumable is on its way.
        local label = entry.subLabel and sub and entry.subLabel[sub] or entry.shortLabel
        local phase = surface
        local applyItem = nil
        if surface == "missing" then
          if entry.phases and isEating() then
            phase, label = "eating", "EATING"
          elseif inBags and isApplying(inBags) then
            phase, label = "applying", "APPLYING"
          elseif not inBags then
            label = entry.noLabel or label
          elseif click then
            applyItem = inBags
          end
        end

        local n = #list + 1
        local r = ROWS[n]
        if not r then r = {}; ROWS[n] = r end
        r.id        = entry.key
        r.status    = surface
        r.phase     = phase
        r.icon      = entry.iconFn and entry.iconFn(sub) or nil
        r.remaining = remaining
        r.label     = label
        r.unit      = entry.subUnit and sub and entry.subUnit[sub] or entry.unit
        r.sub       = sub
        r.applyItem = applyItem
        r.applyKind = entry.applyKind or "item"
        r.applySlot = entry.subSlot and sub and entry.subSlot[sub]
          or (entry.applyKind == "weapon" and 16) or nil
        r.applyName = applyItem and GetItemInfo and GetItemInfo(applyItem) or nil
        list[n] = r
      end
    end
  end
end

-- One-shot diagnostic for `/nock helpers`: per catalog entry, every gate's
-- verdict, the raw check() result, the matched buff, and the bag scan. This is
-- the in-game tool for verifying the Core/ConsumeData.lua ID lists.
function Helpers:DebugDump()
  local lines = {}
  local p = Nock.db and Nock.db.profile
  lines[#lines + 1] = ("Nock /nock helpers  (t=%.0f)"):format(GetTime())
  lines[#lines + 1] = ("  panel gates: showHelpers=%s  hiddenByWA=%s  inCombat=%s  inInstance=%s  inRaid=%s  testMode=%s  parseMode=%s  threshold=%ss  click=%s")
    :format(tostring(not (p and p.showHelpers == false)),
            tostring(Nock.state.helpersHiddenByWA),
            tostring(Nock.state.player.inCombat),
            tostring(isInInstance()), tostring(isInRaidInstance()),
            tostring(Nock.state.helpersTestMode) .. (Nock.state.helpersTestCreature and ("/" .. Nock.state.helpersTestCreature) or ""),
            tostring(isParseMode()), tostring(expiringThreshold()),
            tostring(clickToApplyEnabled()))
  for _, entry in ipairs(Helpers.Catalog) do
    local status, remaining, sub = entry.check()
    local cat = entry.subData and sub and CD[entry.subData[sub]]
      or (entry.data and CD[entry.data]) or nil
    local kind = entry.subKind and sub and entry.subKind(sub) or nil
    local apply = cat and Helpers.PickApplyItem(cat, kind) or nil
    lines[#lines + 1] = ("  [%s] enabled=%s  check=%s%s%s%s  apply=%s (%s)")
      :format(entry.key, tostring(isEnabled(entry.enabledKey)), tostring(status),
              remaining and (("  remaining=%.0fs"):format(remaining)) or "",
              sub and ("  sub=" .. sub) or "",
              kind and ("  weapon=" .. kind) or "",
              apply and tostring(apply) or "none", entry.applyKind or "item")
    -- Which tracked buff spell IDs are actually on the unit right now.
    local data = entry.data and CD[entry.data]
    local set = data and data.buffs
    if set and UnitBuff then
      local unit = (entry.key == "kibler" or entry.key == "scrollPet") and "pet" or "player"
      for i = 1, 40 do
        local name, _, _, _, _, exp, _, _, _, spellId = UnitBuff(unit, i)
        if not name then break end
        if spellId and set[spellId] then
          lines[#lines + 1] = ("      matched buff: %s (%d) exp in %.0fs")
            :format(name, spellId, math.max(0, (exp or 0) - GetTime()))
        end
      end
    end
    if entry.itemIds then
      local found = {}
      for id in pairs(entry.itemIds) do
        local c = GetItemCount and GetItemCount(id) or 0
        if c > 0 then found[#found + 1] = ("%d x%d"):format(id, c) end
      end
      lines[#lines + 1] = "      bags: " .. (#found > 0 and table.concat(found, ", ") or "none")
    end
  end
  return table.concat(lines, "\n")
end

-- Third-party WA suppression is recomputed only on these events (never per
-- tick): entering world / login (covers WeakAuras loading after Nock and
-- /reload) and any settings change (the helpersHideWA field firing
-- NOCK_VISUALS_CHANGED).
function Helpers:OnEnable()
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "RecheckWA")
  self:RegisterEvent("PLAYER_LOGIN",          "RecheckWA")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "RecheckWA")
  self:RecheckWA()
end

function Helpers:RecheckWA()
  Nock.state.helpersHiddenByWA = detectHelperWA()
end
