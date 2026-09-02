-- Modules/Auras.lua
-- Tracks player auras (aspect, lust) and target debuffs (Hunter's Mark), plus
-- weapon-config (canWeave). Mutates Nock.state.player.aspect / inLust / canWeave
-- and Nock.state.target.huntersMark. Foundation for the rotation engine and warnings.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Auras = Nock:NewModule("Auras", "AceEvent-3.0")
local C = Nock.Constants

-- Scans run on the tick's slow lane (Core:Tick, refreshInterval) off a dirty
-- flag UNIT_AURA sets: the same 10 Hz cadence the old ScheduleTimer gave,
-- without a closure + AceTimer object per throttle window. In a 25-man the
-- player's and the boss's UNIT_AURA saturate that window for the whole fight.
Auras.refreshInterval = 0.1

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

-- Every aura read goes through Core/AuraCache.lua: on this client each read
-- allocates ~1.9 KB whatever the function, so nothing here walks a unit --
-- the store is fed incrementally by UNIT_AURA and this module reads it when
-- its revision moves.
local AC = Nock.AuraCache

-- The published aura records are REUSED across scans (one table each for the
-- aspect, Feign Death, Dazed and Hunter's Mark) and only their fields change;
-- a scan that finds nothing publishes nil. Consumers read fields, never
-- identity, and Core:Tick already writes mark.remaining in place.
local ASPECT_T, FEIGN_T, DAZED_T, MARK_T = {}, {}, {}, {}
local EATING_T, DRINKING_T = {}, {}

function Auras:OnEnable()
  self.huntersMarkName = spellNameOf(C.SpellID.HUNTERS_MARK) or "Hunter's Mark"
  self.dazedName       = spellNameOf(C.SpellID.DAZED) or "Dazed"
  self.satedName       = spellNameOf(C.SpellID.SATED) or "Sated"
  self.exhaustionName  = spellNameOf(C.SpellID.EXHAUSTION) or "Exhaustion"
  self.foodName        = spellNameOf(C.SpellID.FOOD) or "Food"
  self.drinkName       = spellNameOf(C.SpellID.DRINK) or "Drink"
  self:BuildAspectNameMap()
  self:ResolveTonkName()

  self:RegisterEvent("PLAYER_LOGIN")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  -- No UNIT_AURA here: the aura cache listens; Refresh reads its revision.
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
  self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

  self:UpdateCanWeave()
  self:ScanAll()
end

function Auras:PLAYER_LOGIN()
  self.huntersMarkName = spellNameOf(C.SpellID.HUNTERS_MARK) or self.huntersMarkName
  self.dazedName       = spellNameOf(C.SpellID.DAZED) or self.dazedName
  self.foodName        = spellNameOf(C.SpellID.FOOD) or self.foodName
  self.drinkName       = spellNameOf(C.SpellID.DRINK) or self.drinkName
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

-- Slow lane: a scan only when the cache's revision moved for the player or
-- the target; a clean tick is two integer compares.
function Auras:Refresh()
  if not AC then return end
  local rp, rt = AC.Rev("player"), AC.Rev("target")
  if rp == self._revPlayer and rt == self._revTarget then return end
  self._revPlayer, self._revTarget = rp, rt
  self:ScanAll()
end

function Auras:ScanAll()
  local prof = Nock._prof
  local t0, k0
  if prof then t0, k0 = prof:Mark() end
  self:ScanPlayer()
  self:ScanTarget()
  if prof then prof:Done("Auras.scan", t0, k0) end
end

-- Scan scratch: the buff/debuff callbacks below are module-level functions
-- (not closures made per scan) and read/write these.
local sc_nameMap, sc_tonkName
local sc_aspect, sc_inLust, sc_feign, sc_rapidFire, sc_quickShots, sc_drums, sc_tonk, sc_tonkSince
local sc_foodName, sc_drinkName, sc_eating, sc_drinking
local sc_dazedName, sc_satedName, sc_exhaustionName, sc_dazed, sc_sated
local sc_markName, sc_mark

local function onPlayerBuff(name, spellId, icon, expirationTime, duration)
  local key = sc_nameMap and name and sc_nameMap[name]
  if key then
    local a = ASPECT_T
    a.name = name
    a.spellId = spellId            -- the active aura's actual (any-rank) ID
    a.aspectKey = key              -- stable key: "hawk"/"viper"/etc.
    a.icon = icon
    a.expirationTime = expirationTime
    a.duration = duration
    sc_aspect = a
  end
  if spellId and LUST_IDS[spellId] then
    sc_inLust = true
  end
  -- Feign Death is a single-rank spell in TBC, so match the buff by raw id.
  -- CastBar renders this as a right-to-left depleting bar; clears the instant
  -- the buff drops (you stand up early) since the next scan leaves feign nil.
  if spellId == C.SpellID.FEIGN_DEATH then
    local f = FEIGN_T
    f.icon, f.expirationTime, f.duration = icon, expirationTime, duration
    sc_feign = f
  end
  if     spellId == C.SpellID.RAPID_FIRE      then sc_rapidFire  = true
  elseif spellId == C.SpellID.QUICK_SHOTS     then sc_quickShots = true
  elseif spellId == C.SpellID.DRUMS_OF_BATTLE then sc_drums      = true end
  -- Eating / drinking: the generic Food / Drink auras, matched by their
  -- localized names (each food applies its own spell ID, the name is the one
  -- stable handle). Drives the centre-screen pill (UI/Frame_ConsumeBanner.lua).
  if name == sc_foodName then
    local e = EATING_T
    e.icon, e.expirationTime, e.duration, e.spellId = icon, expirationTime, duration, spellId
    sc_eating = e
  elseif name == sc_drinkName then
    local d = DRINKING_T
    d.icon, d.expirationTime, d.duration = icon, expirationTime, duration
    sc_drinking = d
  end
  if spellId == C.SpellID.STEAM_TONK or (sc_tonkName and name == sc_tonkName) then
    sc_tonk = true
    -- expirationTime - duration is the server's own application time, exact
    -- where the detection time lags by up to the scan cadence. A transform that
    -- reports no duration leaves this nil and the caller stamps GetTime().
    if duration and duration > 0 and expirationTime and expirationTime > 0 then
      sc_tonkSince = expirationTime - duration
    end
  end
end

-- Player DEBUFFS. iterateDebuffs was written for the target but takes the unit,
-- so "player" needs no new iterator. Dazed is matched by localized name, not by
-- ID: several mob abilities apply a "Dazed" aura under different spell IDs, and
-- C.SpellID.DAZED exists only to resolve that name.
--
-- All player-debuff consumers collect inside THIS pass — don't add another
-- scan. Sated/Exhaustion (the post-Bloodlust lockout, both faction variants)
-- is matched by ID first with a name fallback; it drives the DO NOT RELEASE
-- banner (Modules/Warnings.lua reads state.player.sated).
local function onPlayerDebuff(name, spellId, icon, expirationTime, duration)
  if name == sc_dazedName then
    local d = DAZED_T
    d.name, d.spellId, d.icon, d.expirationTime, d.duration = name, spellId, icon, expirationTime, duration
    sc_dazed = d
  end
  if spellId == C.SpellID.SATED or spellId == C.SpellID.EXHAUSTION
     or name == sc_satedName or name == sc_exhaustionName then
    sc_sated = true
  end
end

-- One pass over the player's store: helpful records to the buff collector,
-- harmful ones to the debuff collector.
local function onPlayerAura(a)
  if a.isHarmful then
    onPlayerDebuff(a.name, a.spellId, a.icon, a.expirationTime, a.duration)
  else
    onPlayerBuff(a.name, a.spellId, a.icon, a.expirationTime, a.duration)
  end
end

function Auras:ScanPlayer()
  sc_aspect, sc_inLust, sc_feign = nil, false, nil
  -- Ranged-only haste procs that select the weave rotation notation (both-haste
  -- sources are read from GetMeleeHaste in the tick, not here).
  sc_rapidFire, sc_quickShots, sc_drums = false, false, false
  sc_tonk, sc_tonkSince = false, nil
  sc_nameMap = self.aspectKeyByName
  sc_tonkName = self.tonkName
  sc_dazed, sc_sated = nil, nil
  sc_eating, sc_drinking = nil, nil
  sc_foodName, sc_drinkName = self.foodName, self.drinkName
  sc_dazedName = self.dazedName
  sc_satedName, sc_exhaustionName = self.satedName, self.exhaustionName
  if AC then AC.ForEach("player", onPlayerAura) end

  local aspect, feign, dazed, sated = sc_aspect, sc_feign, sc_dazed, sc_sated
  local inLust, rapidFire, quickShots, drums = sc_inLust, sc_rapidFire, sc_quickShots, sc_drums
  local tonk, tonkSince, tonkName = sc_tonk, sc_tonkSince, sc_tonkName

  local p = Nock.state.player
  p.aspect     = aspect
  p.feign      = feign
  p.dazed      = dazed
  p.sated      = sated or false
  p.eating     = sc_eating
  p.drinking   = sc_drinking
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

local function onTargetDebuff(a)
  if a.isHarmful and a.name == sc_markName then
    local name, spellId, icon, expirationTime, duration, source =
      a.name, a.spellId, a.icon, a.expirationTime, a.duration, a.sourceUnit
    local m = MARK_T
    m.name           = name
    m.spellId        = spellId
    m.icon           = icon
    m.expirationTime = expirationTime or 0
    m.duration       = duration or 0
    m.remaining      = 0  -- derived in central tick
    m.fromPlayer     = source == "player"
    m.sourceName     = casterName(source)
    sc_mark = m
  end
end

function Auras:ScanTarget()
  sc_mark = nil
  if AC and UnitExists("target") then
    sc_markName = self.huntersMarkName
    AC.ForEach("target", onTargetDebuff)
  end
  Nock.state.target.huntersMark = sc_mark
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

--------------------------------------------------------------------------------
-- /nock auraprobe -- what an aura read costs on this client, and what
-- UNIT_AURA carries. The answer decides the aura cache's design (2026-08-30:
-- a UnitBuff call measured ~1.9 KB of garbage in the rest place, so every
-- 40-slot walk is ~80 KB and the raid figure is the walks, not the API).
-- Diagnostic only; the result opens in the copybox (project rule).
--------------------------------------------------------------------------------
local function bytesPer(fn, n)
  if not fn then return nil end
  local ok = pcall(fn)
  if not ok then return "error" end
  collectgarbage("collect")
  collectgarbage("stop")
  local a = collectgarbage("count")
  local okLoop = pcall(function() for _ = 1, n do fn() end end)
  local b = collectgarbage("count")
  collectgarbage("restart")   -- always: a stopped collector would balloon the session
  if not okLoop then return "error" end
  return ("%.0f B"):format((b - a) * 1024 / n)
end

local function countAuras(unit, fn)
  local n = 0
  while fn(unit, n + 1) do n = n + 1 end
  return n
end

function Auras:Probe()
  local L = {}
  local function add(fmt, ...) L[#L + 1] = fmt:format(...) end
  local CU = C_UnitAuras
  add("== Nock aura probe (%s) ==", date and date("%H:%M:%S") or "")
  add("player buffs %d, debuffs %d; target %s (%d debuffs); pet %s (%d buffs)",
    UnitBuff and countAuras("player", UnitBuff) or -1,
    UnitDebuff and countAuras("player", UnitDebuff) or -1,
    UnitExists("target") and "yes" or "no",
    (UnitExists("target") and UnitDebuff) and countAuras("target", UnitDebuff) or 0,
    UnitExists("pet") and "yes" or "no",
    (UnitExists("pet") and UnitBuff) and countAuras("pet", UnitBuff) or 0)
  add("-- API presence")
  local names = { "GetAuraDataByIndex", "GetBuffDataByIndex", "GetDebuffDataByIndex",
    "GetAuraDataByAuraInstanceID", "GetPlayerAuraBySpellID", "GetAuraDataBySpellName",
    "GetAuraSlots", "GetAuraDataBySlot", "GetUnitAuraBySpellID", "GetCooldownAuraBySpellID" }
  for _, n in ipairs(names) do
    add("  C_UnitAuras.%-28s %s", n, (CU and CU[n]) and "yes" or "no")
  end
  add("  UnitAuraSlots %s   UnitAuraBySlot %s   AuraUtil.ForEachAura %s   AuraUtil.FindAuraByName %s",
    UnitAuraSlots and "yes" or "no", UnitAuraBySlot and "yes" or "no",
    (AuraUtil and AuraUtil.ForEachAura) and "yes" or "no",
    (AuraUtil and AuraUtil.FindAuraByName) and "yes" or "no")
  add("-- bytes of garbage per call (slot 1 of the player, 500 calls, collector stopped)")
  add("  UnitBuff(player,1)                      %s", tostring(bytesPer(UnitBuff and function() return UnitBuff("player", 1) end, 500)))
  add("  UnitAura(player,1)                      %s", tostring(bytesPer(UnitAura and function() return UnitAura("player", 1) end, 500)))
  add("  C_UnitAuras.GetBuffDataByIndex(player,1) %s", tostring(bytesPer(CU and CU.GetBuffDataByIndex and function() return CU.GetBuffDataByIndex("player", 1) end, 500)))
  add("  C_UnitAuras.GetAuraDataByIndex(player,1) %s", tostring(bytesPer(CU and CU.GetAuraDataByIndex and function() return CU.GetAuraDataByIndex("player", 1, "HELPFUL") end, 500)))
  local aspectId = C.SpellID.ASPECT_HAWK
  add("  C_UnitAuras.GetPlayerAuraBySpellID(Hawk)  %s", tostring(bytesPer(CU and CU.GetPlayerAuraBySpellID and function() return CU.GetPlayerAuraBySpellID(aspectId) end, 500)))
  add("  UnitBuff(player,99) (empty slot)        %s", tostring(bytesPer(UnitBuff and function() return UnitBuff("player", 99) end, 500)))
  add("  UnitIsUnit(player,player) (control)     %s", tostring(bytesPer(UnitIsUnit and function() return UnitIsUnit("player", "player") end, 500)))
  if CU and CU.GetBuffDataByIndex then
    local d = CU.GetBuffDataByIndex("player", 1)
    if type(d) == "table" then
      local keys = {}
      for k, v in pairs(d) do keys[#keys + 1] = k .. "=" .. type(v) end
      table.sort(keys)
      add("-- AuraData fields (%d): %s", #keys, table.concat(keys, " "))
    end
  end

  -- 5 s of UNIT_AURA for the player / pet / target: the argument shape decides
  -- whether an incremental cache (changed auras only) is possible.
  add("-- UNIT_AURA for 5 s (listening now: apply / let a buff tick / change target)")
  local f = CreateFrame("Frame")
  local seen, first = 0, GetTime()
  f:SetScript("OnEvent", function(_, _, unit, info)
    seen = seen + 1
    if seen > 25 then return end
    if unit ~= "player" and unit ~= "pet" and unit ~= "target" then return end
    if type(info) == "table" then
      add("  +%.2fs %-6s updateInfo: isFullUpdate=%s added=%d updated=%d removed=%d",
        GetTime() - first, unit, tostring(info.isFullUpdate),
        info.addedAuras and #info.addedAuras or 0,
        info.updatedAuraInstanceIDs and #info.updatedAuraInstanceIDs or 0,
        info.removedAuraInstanceIDs and #info.removedAuraInstanceIDs or 0)
      local a = info.addedAuras and info.addedAuras[1]
      if a then
        add("       added[1]: name=%s spellId=%s instance=%s", tostring(a.name), tostring(a.spellId), tostring(a.auraInstanceID))
      end
    else
      add("  +%.2fs %-6s no updateInfo (arg 2 is %s)", GetTime() - first, unit, type(info))
    end
  end)
  f:RegisterEvent("UNIT_AURA")
  Nock:Print("aura probe: listening to UNIT_AURA for 5 s -- apply a buff, then the copybox opens.")
  C_Timer.After(5, function()
    f:UnregisterAllEvents()
    add("  %d UNIT_AURA events in 5 s (all units; first 25 on player/pet/target listed)", seen)
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(table.concat(L, "\n"))
    else for _, l in ipairs(L) do Nock:Print(l) end end
  end)
end
