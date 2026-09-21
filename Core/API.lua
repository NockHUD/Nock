-- Core/API.lua
-- The one place Nock touches a WoW API whose name or shape differs between TBC
-- Anniversary and WoW Forever. Every resolver returns the classic LIST shape.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

local API = {}
local missing = {}
local function miss(name) missing[#missing + 1] = name end

local CS  = _G.C_Spell
local CUA = _G.C_UnitAuras
local CA  = _G.C_AddOns

-- Spell name / icon / info -------------------------------------------------
local cGetSpellInfo    = CS and CS.GetSpellInfo
local cGetSpellTexture = CS and CS.GetSpellTexture
local cGetSpellSubtext = CS and CS.GetSpellSubtext
local gGetSpellInfo    = _G.GetSpellInfo
local gGetSpellTexture = _G.GetSpellTexture

if cGetSpellInfo then
  function API.SpellInfo(id)
    local info = cGetSpellInfo(id)
    if type(info) == "table" then
      return info.name, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID or id
    end
    return nil
  end
elseif gGetSpellInfo then
  function API.SpellInfo(id)
    local name, _, icon, castTime, minRange, maxRange, spellID = gGetSpellInfo(id)
    if name then return name, icon, castTime, minRange, maxRange, spellID or id end
    return nil
  end
else
  miss("SpellInfo")
  function API.SpellInfo() return nil end
end

function API.SpellName(id)
  local name = API.SpellInfo(id)
  return name
end

if cGetSpellTexture then
  function API.SpellIcon(id) return cGetSpellTexture(id) end
elseif gGetSpellTexture then
  function API.SpellIcon(id) return gGetSpellTexture(id) end
else
  function API.SpellIcon(id)
    local _, icon = API.SpellInfo(id)
    return icon
  end
end

-- Rank text: load-bearing on Forever (Classic+ keeps spell ranks) and TBC.
if cGetSpellSubtext then
  function API.SpellRank(id) return cGetSpellSubtext(id) or "" end
elseif gGetSpellInfo then
  function API.SpellRank(id)
    local _, rank = gGetSpellInfo(id)
    return rank or ""
  end
else
  function API.SpellRank() return "" end
end

-- Cooldowns ----------------------------------------------------------------
-- Bare first on Anniversary (values, cheaper); C_Spell's table elsewhere. On
-- Forever the numbers are secret in combat: callers Plain() them before math.
local gGetSpellCooldown = _G.GetSpellCooldown
local cGetSpellCooldown = CS and CS.GetSpellCooldown
if gGetSpellCooldown then
  function API.SpellCooldown(id) return gGetSpellCooldown(id) end
elseif cGetSpellCooldown then
  function API.SpellCooldown(id)
    local info = cGetSpellCooldown(id)
    if type(info) == "table" then return info.startTime, info.duration, info.isEnabled end
    return nil
  end
else
  miss("SpellCooldown")
  function API.SpellCooldown() return nil end
end

local cGetSpellCooldownDuration = CS and CS.GetSpellCooldownDuration
if cGetSpellCooldownDuration then
  function API.SpellCooldownDuration(id) return cGetSpellCooldownDuration(id) end
else
  function API.SpellCooldownDuration() return nil end
end

-- AddOns -------------------------------------------------------------------
local cIsAddOnLoaded = CA and CA.IsAddOnLoaded
local gIsAddOnLoaded = _G.IsAddOnLoaded
if cIsAddOnLoaded then
  function API.IsAddOnLoaded(name) return cIsAddOnLoaded(name) and true or false end
elseif gIsAddOnLoaded then
  function API.IsAddOnLoaded(name) return gIsAddOnLoaded(name) and true or false end
else
  miss("IsAddOnLoaded")
  function API.IsAddOnLoaded() return false end
end

-- Auras --------------------------------------------------------------------
-- Same table shape as C_UnitAuras.GetAuraDataByIndex. On Forever this throws
-- in combat (devkit FOREVER.md section 5); AuraCache only calls it out of
-- combat or behind C_Secrets.ShouldAurasBeSecret().
-- Resolved per call, not at load: the aura globals are the one family the
-- headless tests swap at runtime, and the cost is two lookups per aura on a
-- throttled scan. Prefers C_UnitAuras, then UnitAura, then UnitBuff/UnitDebuff
-- by filter (the bare pair is what Anniversary shims).
if not ((CUA and CUA.GetAuraDataByIndex) or _G.UnitAura or _G.UnitBuff) then miss("AuraByIndex") end
function API.AuraByIndex(unit, i, filter)
  local C = _G.C_UnitAuras
  if C and C.GetAuraDataByIndex then return C.GetAuraDataByIndex(unit, i, filter) end
  local harmful = type(filter) == "string" and filter:find("HARMFUL") ~= nil
  local fn = harmful and (_G.UnitDebuff or _G.UnitAura) or (_G.UnitBuff or _G.UnitAura)
  if not fn then return nil end
  local name, icon, count, dispelName, duration, expirationTime, sourceUnit, isStealable,
        nameplateShowPersonal, spellId, canApplyAura, isBossAura, isFromPlayerOrPlayerPet = fn(unit, i, filter)
  if not name then return nil end
  return {
    name = name, icon = icon, applications = count, dispelName = dispelName,
    duration = duration, expirationTime = expirationTime, sourceUnit = sourceUnit,
    isStealable = isStealable, nameplateShowPersonal = nameplateShowPersonal, spellId = spellId,
    canApplyAura = canApplyAura, isBossAura = isBossAura, isFromPlayerOrPlayerPet = isFromPlayerOrPlayerPet,
    isHelpful = not harmful,
    isHarmful = harmful,
    auraInstanceID = nil,
  }
end

-- Items --------------------------------------------------------------------
-- Names and icons may be nil until the item data loads; callers already cope.
local CI = _G.C_Item
local cGetItemNameByID = CI and CI.GetItemNameByID
local cGetItemIconByID = CI and CI.GetItemIconByID
local cGetItemInfo     = CI and CI.GetItemInfo
local cGetItemCount    = CI and CI.GetItemCount
local gGetItemInfo     = _G.GetItemInfo
local gGetItemIcon     = _G.GetItemIcon
local gGetItemCount    = _G.GetItemCount

if cGetItemNameByID then
  function API.ItemName(id) return cGetItemNameByID(id) end
elseif gGetItemInfo then
  function API.ItemName(id) return (gGetItemInfo(id)) end
elseif cGetItemInfo then
  function API.ItemName(id) return (cGetItemInfo(id)) end
else
  miss("ItemName")
  function API.ItemName() return nil end
end

if cGetItemIconByID then
  function API.ItemIcon(id) return cGetItemIconByID(id) end
elseif gGetItemIcon then
  function API.ItemIcon(id) return gGetItemIcon(id) end
elseif gGetItemInfo then
  function API.ItemIcon(id) return (select(10, gGetItemInfo(id))) end
else
  miss("ItemIcon")
  function API.ItemIcon() return nil end
end

if gGetItemCount then
  function API.ItemCount(id, includeBank, includeUses) return gGetItemCount(id, includeBank, includeUses) end
elseif cGetItemCount then
  function API.ItemCount(id, includeBank, includeUses) return cGetItemCount(id, includeBank, includeUses) end
else
  miss("ItemCount")
  function API.ItemCount() return 0 end
end

-- Talents ------------------------------------------------------------------
-- The bare tab reader exists on Anniversary only; Forever runs on C_Traits and
-- has no spec signal yet (open question in the spec). nil means "no reading".
local gGetTalentTabInfo = _G.GetTalentTabInfo
function API.TalentTabInfo() return gGetTalentTabInfo end

function API.Missing()
  local out = {}
  for i = 1, #missing do out[i] = missing[i] end
  return out
end

Nock.API = API
