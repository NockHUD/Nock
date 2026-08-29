-- Modules/Auras.lua
-- Tracks player auras (aspect, lust) and target debuffs (Hunter's Mark), plus
-- weapon-config (canWeave). Mutates Nock.state.player.aspect / inLust / canWeave
-- and Nock.state.target.huntersMark. Foundation for the rotation engine and warnings.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Auras = Nock:NewModule("Auras", "AceEvent-3.0", "AceTimer-3.0")
local C = Nock.Constants

local SCAN_THROTTLE = 0.1

-- Aspect resolution: match by LOCALIZED name (rank-independent), not spell ID.
-- The IDs in C.SpellID.ASPECT_* are max-rank; a leveling hunter on rank 1-6
-- has a different spell ID per rank but the SAME localized aura name. We use
-- the max-rank IDs only to resolve the localized name via GetSpellInfo (same
-- rank-independent-name convention as HUNTERS_MARK above) and key everything
-- off a stable internal aspectKey string. The aspect table also carries the
-- active aura's actual spellId so existing icon/UI consumers keep working.
local ASPECT_KEY_BY_ID = {
  [C.SpellID.ASPECT_HAWK]    = "hawk",
  [C.SpellID.ASPECT_MONKEY]  = "monkey",
  [C.SpellID.ASPECT_CHEETAH] = "cheetah",
  [C.SpellID.ASPECT_PACK]    = "pack",
  [C.SpellID.ASPECT_WILD]    = "wild",
  [C.SpellID.ASPECT_VIPER]   = "viper",
  [C.SpellID.ASPECT_BEAST]   = "beast",
}

local LUST_IDS = {
  [C.SpellID.BLOODLUST] = true,
  [C.SpellID.HEROISM]   = true,
}

local function spellNameOf(spellID)
  if GetSpellInfo then
    local n = GetSpellInfo(spellID)
    if n then return n end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(spellID)
    if i and i.name then return i.name end
  end
  return nil
end

-- The tonk's aura name, taken from the ITEM so it is localized and rank-proof.
-- Both API forms are feature-detected: this client has moved much of the item
-- API into C_Item, and the bare global is not guaranteed.
local function itemSpellName(itemID)
  if C_Item and C_Item.GetItemSpell then
    local okc, n = pcall(C_Item.GetItemSpell, itemID)
    if okc and n then return n end
  end
  if GetItemSpell then
    local okg, n = pcall(GetItemSpell, itemID)
    if okg and n then return n end
  end
  return nil
end

local function iterateBuffs(unit, callback)
  if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
    local i = 1
    while true do
      local data = C_UnitAuras.GetBuffDataByIndex(unit, i)
      if not data then break end
      callback(data.name, data.spellId, data.icon, data.expirationTime, data.duration)
      i = i + 1
    end
    return
  end
  if UnitBuff then
    local i = 1
    while true do
      local name, icon, _, _, duration, expirationTime, _, _, _, spellId = UnitBuff(unit, i)
      if not name then break end
      callback(name, spellId, icon, expirationTime, duration)
      i = i + 1
    end
  end
end

local function iterateDebuffs(unit, callback)
  if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
    local i = 1
    while true do
      local data = C_UnitAuras.GetDebuffDataByIndex(unit, i)
      if not data then break end
      callback(data.name, data.spellId, data.icon, data.expirationTime, data.duration, data.sourceUnit)
      i = i + 1
    end
    return
  end
  if UnitDebuff then
    local i = 1
    while true do
      local name, icon, _, _, duration, expirationTime, source, _, _, spellId = UnitDebuff(unit, i)
      if not name then break end
      callback(name, spellId, icon, expirationTime, duration, source)
      i = i + 1
    end
  end
end

function Auras:OnEnable()
  self.huntersMarkName = spellNameOf(C.SpellID.HUNTERS_MARK) or "Hunter's Mark"
  self.dazedName       = spellNameOf(C.SpellID.DAZED) or "Dazed"
  self.satedName       = spellNameOf(C.SpellID.SATED) or "Sated"
  self.exhaustionName  = spellNameOf(C.SpellID.EXHAUSTION) or "Exhaustion"
  self:BuildAspectNameMap()
  self:ResolveTonkName()

  self:RegisterEvent("PLAYER_LOGIN")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("UNIT_AURA")
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
  self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

  self:UpdateCanWeave()
  self:ScanAll()
end

function Auras:PLAYER_LOGIN()
  self.huntersMarkName = spellNameOf(C.SpellID.HUNTERS_MARK) or self.huntersMarkName
  self.dazedName       = spellNameOf(C.SpellID.DAZED) or self.dazedName
  self:BuildAspectNameMap()
  self:ResolveTonkName()
  self:UpdateCanWeave()
  self:ScanAll()
end

-- Build (or rebuild) the localized-name → aspect-key map. Called at OnEnable
-- and again at PLAYER_LOGIN in case the spell database wasn't fully populated
-- at addon load (mirrors how huntersMarkName is refreshed on login).
function Auras:BuildAspectNameMap()
  local m = {}
  for id, key in pairs(ASPECT_KEY_BY_ID) do
    local n = spellNameOf(id)
    if n then m[n] = key end
  end
  self.aspectKeyByName = m
end

-- Resolved at OnEnable AND again at PLAYER_LOGIN: the item cache is routinely
-- cold at addon load, exactly like huntersMarkName and the aspect name map.
-- Falls back to the spell ID's own name if the item is unknown to the client.
function Auras:ResolveTonkName()
  local n = itemSpellName(C.STEAM_TONK_ITEM) or spellNameOf(C.SpellID.STEAM_TONK)
  if n then self.tonkName = n end
end

function Auras:PLAYER_ENTERING_WORLD()
  self:UpdateCanWeave()
  self:ScanAll()
end

function Auras:PLAYER_TARGET_CHANGED()
  self:ScanTarget()
end

function Auras:PLAYER_EQUIPMENT_CHANGED()
  self:UpdateCanWeave()
end

function Auras:UNIT_AURA(event, unit)
  if unit ~= "player" and unit ~= "target" then return end
  if self._scanScheduled then return end
  self._scanScheduled = true
  self:ScheduleTimer(function()
    self._scanScheduled = false
    self:ScanAll()
  end, SCAN_THROTTLE)
end

function Auras:ScanAll()
  self:ScanPlayer()
  self:ScanTarget()
end

function Auras:ScanPlayer()
  local aspect, inLust, feign = nil, false, nil
  -- Ranged-only haste procs that select the weave rotation notation (both-haste
  -- sources are read from GetMeleeHaste in the tick, not here).
  local rapidFire, quickShots, drums = false, false, false
  local tonk, tonkSince = false, nil
  local nameMap = self.aspectKeyByName
  local tonkName = self.tonkName
  iterateBuffs("player", function(name, spellId, icon, expirationTime, duration)
    local key = nameMap and name and nameMap[name]
    if key then
      aspect = {
        name = name,
        spellId = spellId,          -- the active aura's actual (any-rank) ID
        aspectKey = key,            -- stable key: "hawk"/"viper"/etc.
        icon = icon,
        expirationTime = expirationTime,
        duration = duration,
      }
    end
    if spellId and LUST_IDS[spellId] then
      inLust = true
    end
    -- Feign Death is a single-rank spell in TBC, so match the buff by raw id.
    -- CastBar renders this as a right-to-left depleting bar; clears the instant
    -- the buff drops (you stand up early) since the next scan leaves feign nil.
    if spellId == C.SpellID.FEIGN_DEATH then
      feign = { icon = icon, expirationTime = expirationTime, duration = duration }
    end
    if     spellId == C.SpellID.RAPID_FIRE      then rapidFire  = true
    elseif spellId == C.SpellID.QUICK_SHOTS     then quickShots = true
    elseif spellId == C.SpellID.DRUMS_OF_BATTLE then drums      = true end
    if spellId == C.SpellID.STEAM_TONK or (tonkName and name == tonkName) then
      tonk = true
      -- expirationTime - duration is the server's own application time, exact
      -- where the detection time lags by up to SCAN_THROTTLE. A transform that
      -- reports no duration leaves this nil and the caller stamps GetTime().
      if duration and duration > 0 and expirationTime and expirationTime > 0 then
        tonkSince = expirationTime - duration
      end
    end
  end)

  -- Player DEBUFFS. iterateDebuffs was written for the target but takes the unit,
  -- so "player" needs no new iterator. Dazed is matched by localized name, not by
  -- ID: several mob abilities apply a "Dazed" aura under different spell IDs, and
  -- C.SpellID.DAZED exists only to resolve that name.
  --
  -- All player-debuff consumers collect inside THIS pass — don't add another
  -- scan. Sated/Exhaustion (the post-Bloodlust lockout, both faction variants)
  -- is matched by ID first with a name fallback; it drives the DO NOT RELEASE
  -- banner (Modules/Warnings.lua reads state.player.sated).
  local dazed, sated
  local dazedName = self.dazedName
  local satedName, exhaustionName = self.satedName, self.exhaustionName
  iterateDebuffs("player", function(name, spellId, icon, expirationTime, duration)
    if name == dazedName then
      dazed = {
        name = name,
        spellId = spellId,
        icon = icon,
        expirationTime = expirationTime,
        duration = duration,
      }
    end
    if spellId == C.SpellID.SATED or spellId == C.SpellID.EXHAUSTION
       or name == satedName or name == exhaustionName then
      sated = true
    end
  end)

  local p = Nock.state.player
  p.aspect     = aspect
  p.feign      = feign
  p.dazed      = dazed
  p.sated      = sated or false
  -- The haste procs are simulated in practice mode (Modules/Practice.lua).
  if not Nock.state.sim.active then
    p.inLust     = inLust
    p.rapidFire  = rapidFire
    p.quickShots = quickShots
    p.drums      = drums
  end

  -- Edge-only publication: the message costs nothing while nothing changes, and
  -- `since` is stamped once on the rising edge so it cannot drift between scans.
  local t = p.tonk
  local was = t.active
  t.active = tonk
  if tonk then
    t.name = tonkName
    if not was then t.since = tonkSince or GetTime() end
  else
    t.since, t.name = nil, nil
  end
  if tonk ~= was then
    Nock:SendMessage("NOCK_TONK_CHANGED", tonk)
  end
end

-- Who cast the mark, as a display name, or nil when the client won't say.
--
-- The caster comes back as a UNIT TOKEN ("player", "raid7", "party2"), and only
-- when that unit is one the client is currently tracking -- a hunter outside
-- your group, or one who has gone out of range, returns no token at all. So nil
-- here means "unknown", never "nobody": views must fall back to showing nothing
-- rather than to claiming the mark is unowned.
--
-- UnitName's second return is the realm; dropped, since a raid is same-realm on
-- this client and a realm suffix would blow out a 42px icon caption.
local function casterName(source)
  if not (source and UnitName) then return nil end
  local n = UnitName(source)
  if n and n ~= "" and n ~= UNKNOWNOBJECT then return n end
  return nil
end

function Auras:ScanTarget()
  local mark
  if UnitExists("target") then
    iterateDebuffs("target", function(name, spellId, icon, expirationTime, duration, source)
      if name == self.huntersMarkName then
        mark = {
          name           = name,
          spellId        = spellId,
          icon           = icon,
          expirationTime = expirationTime or 0,
          duration       = duration or 0,
          remaining      = 0,  -- derived in central tick
          fromPlayer     = source == "player",
          sourceName     = casterName(source),
        }
      end
    end)
  end
  Nock.state.target.huntersMark = mark
end

function Auras:UpdateCanWeave()
  local canWeave
  if IsDualWielding then
    canWeave = not IsDualWielding()
  else
    canWeave = not GetInventoryItemID("player", 17)
  end
  Nock.state.player.canWeave = canWeave and true or false
end
