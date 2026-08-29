-- Modules/Cooldowns.lua
-- Tracks configured cooldowns (spells, items, inventory, alt-items, spec-aware spells)
-- and proc auras → mutates Nock.state.cooldowns.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Cooldowns = Nock:NewModule("Cooldowns", "AceEvent-3.0", "AceTimer-3.0")
local C = Nock.Constants

local AURA_THROTTLE = 0.1
local GCD_TOLERANCE = 1.5

-- IsUsableSpell for the entries whose "proc" IS usability (Kill Command:
-- the reference WA glows it on spellUsable AND not onCooldown; the proc aura
-- never shows up in UnitBuff on this client, 2026-08-29 trace).
-- -> usable, noMana (both booleans; nil, nil when the client cannot say)
local function spellUsable(spellID)
  if C_Spell and C_Spell.IsSpellUsable then
    local usable, noMana = C_Spell.IsSpellUsable(spellID)
    return usable and true or false, noMana and true or false
  end
  if IsUsableSpell then
    local usable, noMana = IsUsableSpell(spellID)
    return usable and true or false, noMana and true or false
  end
  return nil, nil
end

-- The one writer of procActive: flips the flag and announces the edge, so
-- both the React grid and ActionGlow read one truth (NOCK_PROC_ACTIVE).
local function setProc(entry, s, active)
  active = active and true or false
  if s.procActive ~= active then
    s.procActive = active
    Nock:SendMessage("NOCK_PROC_ACTIVE", entry.key, active)
  end
end

local function getSpellCD(spellID)
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(spellID)
    if info then return info.startTime, info.duration end
  end
  if GetSpellCooldown then return GetSpellCooldown(spellID) end
  return 0, 0
end

local function getItemCD(itemID)
  if C_Container and C_Container.GetItemCooldown then return C_Container.GetItemCooldown(itemID) end
  if C_Item and C_Item.GetItemCooldown then return C_Item.GetItemCooldown(itemID) end
  if GetItemCooldown then return GetItemCooldown(itemID) end
  return 0, 0
end

local function getItemCount(itemID)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID) end
  if GetItemCount then return GetItemCount(itemID) end
  return 0
end

-- Sum of charges across all instances of itemID (e.g. 2× Drums of Battle with
-- 4 charges each = 8). Falls back to a plain item count if the API doesn't
-- support the includeCharges flag.
local function getItemChargeCount(itemID)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID, false, true) or 0 end
  if GetItemCount then return GetItemCount(itemID, false, true) or 0 end
  return 0
end

local function getSpellIcon(spellID)
  if not spellID then return nil end
  if GetSpellInfo then
    local _, _, icon = GetSpellInfo(spellID)
    if icon then return icon end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(spellID)
    if i and i.iconID then return i.iconID end
  end
  if C_Spell and C_Spell.GetSpellTexture then
    local t = C_Spell.GetSpellTexture(spellID)
    if t then return t end
  end
  if GetSpellTexture then return GetSpellTexture(spellID) end
  return nil
end

local function getItemIcon(itemID)
  if not itemID then return nil end
  if GetItemInfo then
    local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
    if icon then return icon end
  end
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
  return nil
end

-- The client's on-use-spell lookup, or nil if this client has neither form.
-- C_Item first per the Anniversary namespace migration; the bare global is the
-- fallback (mirrors Modules/Auras.lua's spellNameOf).
local function itemSpellFn()
  if C_Item and C_Item.GetItemSpell then return C_Item.GetItemSpell end
  if GetItemSpell then return GetItemSpell end
  return nil
end

-- Is this tracker something the player can actually press?
--
-- Only trinket (inventory) slots can answer no: the slot tracks whatever is
-- equipped, and a passive proc trinket — Dragonspine Trophy, Tsunami Talisman —
-- has no Use effect at all. It still reports no cooldown (so `ready` is true
-- forever) and still has an inventory texture (so `.icon` is set), which is why
-- neither of those can stand in for "poppable". GetItemSpell returns the item's
-- ON-USE spell only, so it is the honest signal.
--
-- Fails toward true: an absent or erroring API means we cannot tell, and
-- wrongly hiding a real "Pop T1" reminder is worse than the nag. Item info may
-- also be uncached at login — GET_ITEM_INFO_RECEIVED re-runs RefreshIcons, so
-- that resolves itself.
local function resolveOnUse(entry)
  if entry.type ~= "inventory" then return true end
  local fn = itemSpellFn()
  if not fn then return true end
  local itemID = GetInventoryItemID and GetInventoryItemID("player", entry.slot)
  if not itemID then return false end
  local called, name, spellID = pcall(fn, itemID)
  if not called then return true end
  return (name ~= nil) or (spellID ~= nil)
end

local function getActiveSpec()
  local best, idx = 0, 1
  for i = 1, 3 do
    if GetTalentTabInfo then
      local _, _, _, _, pts = GetTalentTabInfo(i)
      if pts and pts > best then best, idx = pts, i end
    end
  end
  return idx
end

local function resolveSpecSpell(entry)
  return entry.bySpec[getActiveSpec()]
end

-- Does the character actually KNOW the spell the Spec row resolves to? The
-- row picks BW / Silencing Shot / Readiness by the most-pointed tab, but a
-- 41-point talent is not implied by the tab — a 40/21/0 hunter has no
-- Readiness and used to see one, ready, anyway (user, 2026-08-27). On a
-- client with neither known-API the answer is "can't tell": keep showing.
local function specSpellKnown(entry)
  local id = resolveSpecSpell(entry)
  if not id then return false end
  if IsSpellKnown then return IsSpellKnown(id) == true end
  if IsPlayerSpell then return IsPlayerSpell(id) == true end
  return true
end

-- Recomputed on the talent/spellbook events (and login); a change sends
-- NOCK_VISUALS_CHANGED so both grids rebuild — the Classic grid only ever
-- rebuilds on that message, so a respec used to leave it stale too.
function Cooldowns:UpdateSpecKnown()
  local known = {}
  for _, e in ipairs(C.TRACKED_COOLDOWNS) do
    if e.type == "specSpell" then known[e.key] = specSpellKnown(e) end
  end
  local changed = false
  local old = self._specKnown
  if not old then
    changed = true
  else
    for k, v in pairs(known) do if old[k] ~= v then changed = true end end
    for k in pairs(old) do if known[k] == nil then changed = true end end
  end
  self._specKnown = known
  if changed and old then Nock:SendMessage("NOCK_VISUALS_CHANGED") end
end

-- False only for a Spec row whose resolved spell the character does not know;
-- every other key (and any key before the first UpdateSpecKnown) is available.
-- Both grids' geometry read this next to cooldownDisabled.
function Cooldowns:IsEntryAvailable(key)
  local known = self._specKnown
  if not known then return true end
  local v = known[key]
  if v == nil then return true end
  return v
end

-- Race-resolved spell (the "Racial" React-grid entry). Keyed by the
-- non-localized race token (select(2, UnitRace)) so it works on any locale.
local function resolveRaceSpell(entry)
  local _, raceToken = UnitRace("player")
  return raceToken and entry.byRace[raceToken] or nil
end

local function resolveAlt(altIds, now)
  for _, id in ipairs(altIds) do
    if getItemCount(id) > 0 then
      local s, d = getItemCD(id)
      if (not s or s == 0) or (s + d - now <= 0) then
        return id, 0, 0
      end
    end
  end
  local bestId, bestStart, bestDuration, bestRem = nil, 0, 0, math.huge
  for _, id in ipairs(altIds) do
    if getItemCount(id) > 0 then
      local s, d = getItemCD(id)
      if s and s > 0 and d > 0 then
        local rem = math.max(0, s + d - now)
        if rem < bestRem then
          bestId, bestStart, bestDuration, bestRem = id, s, d, rem
        end
      end
    end
  end
  if bestId then return bestId, bestStart, bestDuration end
  return altIds[1], 0, 0
end

local function firstOwnedItem(ids)
  if not ids then return nil end
  for _, id in ipairs(ids) do
    if getItemCount(id) > 0 then return id end
  end
  return nil
end

local function resolveIcon(entry)
  if entry.type == "spell" then return getSpellIcon(entry.id) end
  if entry.type == "item" then return getItemIcon(entry.id) end
  if entry.type == "inventory" then return GetInventoryItemTexture("player", entry.slot) end
  if entry.type == "specSpell" then
    local id = resolveSpecSpell(entry)
    return id and getSpellIcon(id) or nil
  end
  if entry.type == "raceSpell" then
    local id = resolveRaceSpell(entry)
    return id and getSpellIcon(id) or nil
  end
  if entry.type == "altItem" then
    local id = firstOwnedItem(entry.ids) or entry.ids[1]
    return getItemIcon(id)
  end
  return nil
end

local function iterateBuffs(unit, callback)
  if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
    local i = 1
    while true do
      local data = C_UnitAuras.GetBuffDataByIndex(unit, i)
      if not data then break end
      callback(data.name, data.spellId, data.expirationTime, data.duration, data.icon)
      i = i + 1
    end
    return
  end
  if UnitBuff then
    local i = 1
    while true do
      local name, icon, _, _, duration, expirationTime, _, _, _, spellId = UnitBuff(unit, i)
      if not name then break end
      callback(name, spellId, expirationTime, duration, icon)
      i = i + 1
    end
  end
end

----------------------------------------------------------------------------
-- Shared list builder. The grid is profile-configurable, but several systems
-- (rotation/clip → MS,Arc; lust-CD warning → RF,Haste,T1,T2; Drums range
-- badge) read fixed keys, so the ENGINE always tracks the full built-in
-- catalog PLUS every custom entry regardless of grid config. Only the VIEW
-- filters/reorders/caps. Engine, view and options all go through these methods
-- so they can never disagree.
----------------------------------------------------------------------------

local function profile()
  return Nock.db and Nock.db.profile or {}
end

-- Stable key for a saved custom record. Options stores `key`; derive a
-- deterministic fallback for any legacy/hand-rolled record.
local function customKey(e)
  if type(e.key) == "string" and e.key ~= "" then return e.key end
  return "c_" .. tostring(e.type or "spell") .. "_" .. tostring(e.id or "0")
end

-- A saved custom record → a normalized tracker entry (same shape the engine's
-- scan paths expect), or nil if it isn't a usable spell/item id.
local function normalizeCustom(e)
  local id = tonumber(e.id)
  local t  = e.type
  if not id or (t ~= "spell" and t ~= "item") then return nil end
  return {
    key      = customKey(e),
    type     = t,
    id       = id,
    procBuff = tonumber(e.procBuff),
    label    = (e.label and e.label ~= "" and e.label) or (t == "item" and ("Item " .. id) or ("Spell " .. id)),
    custom   = true,
  }
end

local function gridEligibleCatalog()
  local out = {}
  for _, e in ipairs(C.TRACKED_COOLDOWNS) do
    if not e.trackedOnly then out[#out + 1] = e end
  end
  return out
end

local function ensureStateSlot(key)
  if not Nock.state.cooldowns[key] then
    Nock.state.cooldowns[key] = {
      startTime = 0, duration = 0, remaining = 0,
      ready = true, procActive = false, icon = nil, onUse = true,
    }
  end
end

-- (Re)build the cached tracked list + key→entry map and make sure a state
-- slot exists for every tracked key. Cheap; called on enable and whenever the
-- config changes (NOCK_VISUALS_CHANGED, fired by the options setters).
function Cooldowns:RebuildLists()
  local tracked, byKey = {}, {}
  for _, e in ipairs(C.TRACKED_COOLDOWNS) do
    tracked[#tracked + 1] = e
    byKey[e.key] = e
  end
  for _, rec in ipairs(profile().cooldownCustom or {}) do
    local e = normalizeCustom(rec)
    if e and not byKey[e.key] then
      tracked[#tracked + 1] = e
      byKey[e.key] = e
    end
  end
  for _, e in ipairs(tracked) do ensureStateSlot(e.key) end
  self._tracked      = tracked
  self._entryByKey   = byKey
end

function Cooldowns:GetTracked()
  if not self._tracked then self:RebuildLists() end
  return self._tracked
end

function Cooldowns:GetEntry(key)
  if not self._entryByKey then self:RebuildLists() end
  return self._entryByKey[key]
end

-- Full reconciled order of every grid-eligible key (catalog non-trackedOnly +
-- custom). Honors profile.cooldownOrder first, then appends anything missing
-- in catalog/custom order, so new entries and stale keys are handled cleanly.
-- Includes DISABLED keys (the options list shows everything); the view filters.
function Cooldowns:GetOrderedGridKeys()
  local elig, set = {}, {}
  for _, e in ipairs(gridEligibleCatalog()) do elig[#elig + 1] = e.key; set[e.key] = true end
  for _, rec in ipairs(profile().cooldownCustom or {}) do
    local k = customKey(rec)
    if not set[k] then elig[#elig + 1] = k; set[k] = true end
  end
  local ordered, seen = {}, {}
  for _, k in ipairs(profile().cooldownOrder or {}) do
    if set[k] and not seen[k] then ordered[#ordered + 1] = k; seen[k] = true end
  end
  for _, k in ipairs(elig) do
    if not seen[k] then ordered[#ordered + 1] = k; seen[k] = true end
  end
  return ordered
end

function Cooldowns:GetDims()
  local p = profile()
  local cols = math.max(1, math.floor(tonumber(p.cooldownCols) or C.COOLDOWN_COLS))
  local rows = math.max(1, math.floor(tonumber(p.cooldownRows) or C.COOLDOWN_ROWS))
  return cols, rows
end

-- Icon edge length so the grid spans EXACTLY the HUD inner width (the same
-- width the mana / range bars use) for the configured column count — that's
-- what makes the grid pixel-align with those bars and keeps extra columns
-- inside the grid instead of overflowing. Capped at the 7-column baseline so
-- few columns don't balloon into giant icons (then the row is just centered).
function Cooldowns:GetIconSize()
  local cols   = (self:GetDims())
  local gap    = C.DIM.INNER_GAP
  local innerW = C.DIM.HUD_WIDTH - 2 * C.DIM.OUTER_PAD
  local baseline = (innerW - (C.COOLDOWN_COLS - 1) * gap) / C.COOLDOWN_COLS
  local fit      = (innerW - (cols - 1) * gap) / cols
  return math.min(baseline, fit)
end

-- Total grid width for the current cols (== innerW once cols >= the 7-col
-- baseline, narrower & centered below that).
function Cooldowns:GetGridWidth()
  local cols = (self:GetDims())
  local icon = self:GetIconSize()
  return cols * icon + (cols - 1) * C.DIM.INNER_GAP
end

-- Ordered, enabled entry tables to render, capped at cols*rows. Anything past
-- the cap stays tracked but isn't drawn.
function Cooldowns:GetGridEntries()
  if not self._entryByKey then self:RebuildLists() end
  local disabled = profile().cooldownDisabled or {}
  local cols, rows = self:GetDims()
  local cap = cols * rows
  local out = {}
  for _, k in ipairs(self:GetOrderedGridKeys()) do
    if not disabled[k] and self:IsEntryAvailable(k) then
      local e = self._entryByKey[k]
      if e then
        out[#out + 1] = e
        if #out >= cap then break end
      end
    end
  end
  return out
end

function Cooldowns:OnConfigChanged()
  self:RebuildLists()
  self:RefreshIcons()
  self:ScanCooldowns()
  self:ScanAuras()
end

function Cooldowns:OnEnable()
  self:RebuildLists()

  self:RegisterMessage("NOCK_VISUALS_CHANGED", "OnConfigChanged")
  self:RegisterEvent("PLAYER_LOGIN")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  pcall(self.RegisterEvent, self, "SPELL_UPDATE_USABLE", "ScanUsable")
  pcall(self.RegisterEvent, self, "UNIT_PET")
  pcall(self.RegisterEvent, self, "UNIT_HEALTH")
  self:RegisterEvent("BAG_UPDATE_COOLDOWN")
  self:RegisterEvent("BAG_UPDATE_DELAYED")
  self:RegisterEvent("UNIT_AURA")
  self:RegisterEvent("PLAYER_TALENT_UPDATE")
  self:RegisterEvent("CHARACTER_POINTS_CHANGED")
  self:RegisterEvent("SPELLS_CHANGED")
  self:RegisterEvent("GET_ITEM_INFO_RECEIVED")

  self:RefreshIcons()
  self:ScanCooldowns()
  self:ScanAuras()
end

function Cooldowns:PLAYER_LOGIN()
  self:UpdateSpecKnown()
  self:RefreshIcons()
  self:ScanCooldowns()
  self:ScanAuras()
end

function Cooldowns:PLAYER_ENTERING_WORLD()
  -- The spellbook is not always populated at PLAYER_LOGIN; re-check here.
  self:UpdateSpecKnown()
  self:RefreshIcons()
end

function Cooldowns:SPELLS_CHANGED()
  self:UpdateSpecKnown()
end

function Cooldowns:PLAYER_EQUIPMENT_CHANGED()
  self:RefreshIcons()
end

function Cooldowns:PLAYER_TALENT_UPDATE()
  self:UpdateSpecKnown()
  self:RefreshIcons()
  self:ScanCooldowns()
  self:ScanAuras()
end

function Cooldowns:CHARACTER_POINTS_CHANGED()
  self:UpdateSpecKnown()
  self:RefreshIcons()
  self:ScanCooldowns()
  self:ScanAuras()
end

function Cooldowns:GET_ITEM_INFO_RECEIVED()
  self:RefreshIcons()
end

function Cooldowns:SPELL_UPDATE_COOLDOWN()
  self:ScanCooldowns()
end

function Cooldowns:BAG_UPDATE_COOLDOWN()
  self:ScanCooldowns()
end

function Cooldowns:BAG_UPDATE_DELAYED()
  -- Inventory contents changed — re-resolve icons (sapper picked up / used up)
  -- and re-scan counts.
  self:RefreshIcons()
  self:ScanCooldowns()
end

function Cooldowns:UNIT_AURA(event, unit)
  if unit ~= "player" then return end
  if self._auraScheduled then return end
  self._auraScheduled = true
  self:ScheduleTimer(function()
    self._auraScheduled = false
    self:ScanAuras()
  end, AURA_THROTTLE)
end

-- Re-resolve the per-slot facts that only change when gear/bags/talents do:
-- the icon, and whether the slot is actually pressable (see resolveOnUse).
-- Hooked to PLAYER_EQUIPMENT_CHANGED / BAG_UPDATE_DELAYED / GET_ITEM_INFO_RECEIVED,
-- never to the tick.
function Cooldowns:RefreshIcons()
  for _, entry in ipairs(self:GetTracked()) do
    local s = Nock.state.cooldowns[entry.key]
    if s then
      s.icon  = resolveIcon(entry)
      s.onUse = resolveOnUse(entry)
    end
  end
end

-- /nock trinkets — what the T1/T2 slots resolve to, and why. The on-use test
-- rests on GetItemSpell returning nothing for a passive proc trinket; this
-- prints the raw answer so that can be confirmed on the live client rather
-- than inferred from whether a warning showed up.
function Cooldowns:DumpTrinkets()
  local fn = itemSpellFn()
  Nock:Print(("Trinkets: GetItemSpell = %s"):format(
    (C_Item and C_Item.GetItemSpell) and "C_Item.GetItemSpell"
      or (GetItemSpell and "bare GetItemSpell" or "MISSING (all slots assumed on-use)")))
  for _, key in ipairs({ "T1", "T2" }) do
    local entry  = self:GetEntry(key)
    local slotID = entry and entry.slot
    local itemID = slotID and GetInventoryItemID and GetInventoryItemID("player", slotID)
    local s      = Nock.state.cooldowns[key]
    local spellName, spellID
    if fn and itemID then
      local called, n, id = pcall(fn, itemID)
      if called then spellName, spellID = n, id end
    end
    Nock:Print(("  %s (slot %s): item=%s %s | use-spell=%s(%s) | onUse=%s ready=%s"):format(
      key, tostring(slotID), tostring(itemID),
      itemID and (GetItemInfo and select(1, GetItemInfo(itemID)) or "?") or "(empty)",
      tostring(spellName), tostring(spellID),
      tostring(s and s.onUse), tostring(s and s.ready)))
  end
end

-- Cooldowns the practice simulator drives itself while state.sim.active. Only
-- keys the sim actually writes belong here — yielding one it never publishes
-- would just freeze a stale bar. Phase 5 added the off-GCD cooldown presses the
-- opener is graded on (the sim's `Pot` is the live grid's Haste slot) and the
-- Kill Command window, whose glow rides on cds.KC.procActive.
local SIM_OWNED = { MS = true, Arc = true, Raptor = true,
                    RF = true, Spec = true, T1 = true, T2 = true,
                    Drums = true, Haste = true, KC = true }

function Cooldowns:ScanCooldowns()
  local now = GetTime()
  for _, entry in ipairs(self:GetTracked()) do
    local s = Nock.state.cooldowns[entry.key]
    if not (Nock.state.sim.active and SIM_OWNED[entry.key]) then
      local start, duration = 0, 0
      s.spellId = nil   -- the spell behind the slot, for the React grid's range tint (nil = item / unresolved)
      s.melee   = entry.melee or nil   -- next-melee ability: the tint follows the melee probe, not IsSpellInRange
      if entry.type == "spell" then
        start, duration = getSpellCD(entry.id)
        s.spellId = entry.id
        s.count = nil
      elseif entry.type == "item" then
        start, duration = getItemCD(entry.id)
        s.count = entry.useCharges and getItemChargeCount(entry.id) or getItemCount(entry.id)
      elseif entry.type == "inventory" then
        start, duration = GetInventoryItemCooldown("player", entry.slot)
        s.count = nil
      elseif entry.type == "specSpell" then
        local id = resolveSpecSpell(entry)
        if id then
          s.icon = getSpellIcon(id)
          s.spellId = id
          start, duration = getSpellCD(id)
        else
          s.icon = nil
        end
        s.count = nil
      elseif entry.type == "raceSpell" then
        local id = resolveRaceSpell(entry)
        if id then
          s.icon = getSpellIcon(id)
          s.spellId = id
          start, duration = getSpellCD(id)
        else
          s.icon = nil
        end
        s.count = nil
      elseif entry.type == "altItem" then
        local id
        id, start, duration = resolveAlt(entry.ids, now)
        s.icon  = getItemIcon(id)
        s.count = id and getItemCount(id) or nil
      end
      if start and start > 0 and duration and duration > GCD_TOLERANCE then
        s.startTime = start
        s.duration = duration
      else
        s.startTime = 0
        s.duration = 0
      end
    end
  end
  self:ScanUsable()
end

local function buffForItemId(itemId)
  if not itemId then return nil end
  local map = C.ITEM_PROC_BUFFS
  return map and map[itemId] or nil
end

function Cooldowns:ScanAuras()
  local active = self._activeBuffs or {}
  local data   = self._buffData    or {}
  for k in pairs(active) do active[k] = nil end
  for k in pairs(data)   do data[k]   = nil end
  iterateBuffs("player", function(_, spellId, expirationTime, duration, icon)
    if spellId then
      active[spellId] = true
      data[spellId] = { expirationTime = expirationTime, duration = duration, icon = icon }
    end
  end)
  self._activeBuffs = active
  self._buffData    = data

  for _, entry in ipairs(self:GetTracked()) do
    local s = Nock.state.cooldowns[entry.key]
    if not (Nock.state.sim.active and SIM_OWNED[entry.key]) then
      if entry.usable then
        -- Usability-driven (Kill Command): ScanUsable owns procActive.
        s.buffIcon, s.buffDuration, s.buffStartTime = nil, 0, 0
      else
      -- An explicit procBuff (custom entries) always wins: it lets the user
      -- glow a slot off any aura, not just the ITEM_PROC_BUFFS map.
      local buffId = entry.procBuff
      if not buffId then
        if entry.type == "spell" then
          buffId = entry.id
        elseif entry.type == "specSpell" then
          buffId = resolveSpecSpell(entry)
        elseif entry.type == "raceSpell" then
          buffId = resolveRaceSpell(entry)
        elseif entry.type == "inventory" then
          local equipped = GetInventoryItemID and GetInventoryItemID("player", entry.slot) or nil
          buffId = buffForItemId(equipped)
        elseif entry.type == "item" then
          buffId = buffForItemId(entry.id)
        end
      end

      local isActive = buffId and (active[buffId] == true)
      setProc(entry, s, isActive)

      if isActive and data[buffId] then
        local d = data[buffId]
        s.buffIcon     = d.icon
        s.buffDuration = d.duration or 0
        s.buffStartTime = (d.expirationTime and d.duration and d.duration > 0)
                           and (d.expirationTime - d.duration) or 0
      else
        s.buffIcon      = nil
        s.buffDuration  = 0
        s.buffStartTime = 0
      end
      end
    end
  end
end

-- procActive for the usability-driven entries: usable AND off cooldown
-- (Nock.ActionGlowEngine.UsableProc). Runs on SPELL_UPDATE_USABLE -- the
-- event the client fires when a spell's usability flips, i.e. at the proc
-- and at its expiry -- and after every cooldown scan.
-- A live pet: Kill Command reads USABLE with no pet out on this client, so
-- pet-bound entries (catalog needsPet) are gated on this as well -- the
-- reference WA's pet-health trigger.
local function petAlive()
  if not UnitExists then return nil end   -- headless: unknown, no gate
  if not UnitExists("pet") then return false end
  if UnitIsDeadOrGhost then return not UnitIsDeadOrGhost("pet") end
  return not UnitIsDead("pet")
end

-- Also publishes s.usable / s.noMana for EVERY spell tile (the React grid's
-- dim-while-unavailable and no-mana tints, the reference WA's conditions 1
-- and 4); nil on item tiles and when the client cannot say. A needsPet entry
-- is not usable without a live pet, whatever the client says.
function Cooldowns:ScanUsable()
  local now = GetTime()
  local pet = petAlive()
  for _, entry in ipairs(self:GetTracked()) do
    local s = Nock.state.cooldowns[entry.key]
    local id = s.spellId
    if id then
      s.usable, s.noMana = spellUsable(id)
      if entry.needsPet and pet == false then s.usable = false end
    else
      s.usable, s.noMana = nil, nil
    end
    if entry.usable and not (Nock.state.sim.active and SIM_OWNED[entry.key]) then
      local onCd = (s.duration or 0) > 0 and (s.startTime + s.duration) > now
      local E = Nock.ActionGlowEngine
      local u = s.usable or false
      local petOk = (entry.needsPet and pet ~= nil) and pet or nil
      setProc(entry, s, E and E.UsableProc(u, onCd, petOk) or (u and not onCd))
    end
  end
end

-- The pet's presence and life flip usability without SPELL_UPDATE_USABLE.
function Cooldowns:UNIT_PET(_, unit)
  if unit == "player" then self:ScanUsable() end
end

function Cooldowns:UNIT_HEALTH(_, unit)
  if unit ~= "pet" then return end
  local dead = not petAlive()
  if dead ~= self._petDead then
    self._petDead = dead
    self:ScanUsable()
  end
end
