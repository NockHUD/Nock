-- Modules/TotemTracker.lua
-- Feeds the HUD-right totem-range panel:
--   • generic Air + Earth totem range (= do we currently have any air/earth
--     totem buff — totem auras only apply while you're in the totem's radius)
--   • whether a shaman is in the group (for later gating; force flag overrides)
-- Writes into state.totems.{air,earth}. (Pet status is handled separately by
-- Frame_PetStatus on the HUD's left edge — not duplicated here.)

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local TotemTracker = Nock:NewModule("TotemTracker", "AceEvent-3.0")
local C = Nock.Constants

-- Generic totem buff-name lists. Any match → that element's slot is "in range".
local AIR_TOTEM_BUFFS = {
  ["Grace of Air"]        = true,
  ["Windfury Totem"]      = true,
  ["Wrath of Air Totem"]  = true,
  ["Nature Resistance"]   = true,
  ["Tranquil Air"]        = true,
}
local EARTH_TOTEM_BUFFS = {
  ["Strength of Earth"]   = true,
  ["Stoneskin"]           = true,
  ["Tremor"]              = true,  -- Tremor Totem (if it surfaces as a buff name)
}

-- Localized name / icon (Anniversary may expose bare or C_Spell.* — mirror
-- RangeFinder's dual lookup).
local function spellName(id)
  if GetSpellInfo then local n = GetSpellInfo(id); if n then return n end end
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id); if i then return i.name end
  end
  return nil
end
local function spellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then
    local t = C_Spell.GetSpellTexture(id); if t then return t end
  end
  if GetSpellTexture then local t = GetSpellTexture(id); if t then return t end end
  if GetSpellInfo then local _, _, ic = GetSpellInfo(id); if ic then return ic end end
  return nil
end

-- Windfury Totem is a temporary MAIN-HAND weapon enchant in TBC, NOT a player
-- aura, so it never appears in UnitBuff. GetWeaponEnchantInfo's 4th return is
-- the temp-enchant ID; matching it against the known Windfury-Totem rank IDs
-- (Constants.WF_ENCHANT_IDS) is locale-proof and unambiguous — every other
-- temp enchant (sharpening stone / oil / poison) has a distinct ID, so no
-- false positives, and no tooltip scan is needed. Approach verified against
-- the "WF Now! v2" WeakAura. Still throttled: a weapon enchant changes rarely.
local WF_ENCHANT_IDS = C.WF_ENCHANT_IDS
local wfIcon, graceIcon
local _wfAt, _wfExp, _wfDur, _wfIcn = 0

local function computeWindfury(now)
  if not GetWeaponEnchantInfo then return nil end
  local hasMH, mhExpireMs, _, mhEnchantID = GetWeaponEnchantInfo()
  if not hasMH then return nil end
  if not (mhEnchantID and WF_ENCHANT_IDS[mhEnchantID]) then return nil end
  local rem = (mhExpireMs or 0) / 1000
  return now + rem, rem, wfIcon
end

local function windfuryInfo()
  local now = GetTime()
  if now - _wfAt >= 0.5 then
    _wfAt = now
    _wfExp, _wfDur, _wfIcn = computeWindfury(now)
  end
  if _wfExp == nil then return nil end
  return _wfExp, _wfDur, _wfIcn
end

-- Returns expirationTime/duration/icon of the first buff whose name is in
-- `set` (so the slot can show the actual active totem's icon).
local function unitBuffFromSet(unit, set)
  if not (UnitExists and UnitExists(unit) and UnitBuff) then return nil end
  for i = 1, 40 do
    local n, icon, _, _, duration, expirationTime = UnitBuff(unit, i)
    if not n then return nil end
    if set[n] then return expirationTime or 0, duration or 0, icon end
  end
  return nil
end

local function scanShaman(self)
  local function isSham(unit)
    if not (UnitExists and UnitExists(unit)) then return false end
    local _, eng = UnitClass(unit)
    return eng == "SHAMAN"
  end
  for i = 1, 4  do if isSham("party" .. i) then self._hasShaman = true; return end end
  for i = 1, 40 do if isSham("raid"  .. i) then self._hasShaman = true; return end end
  self._hasShaman = false
end

function TotemTracker:OnEnable()
  self._hasShaman = false
  -- Resolve Windfury's icon once (shown when the enchant is on the weapon).
  -- Strength of Earth's localized name is added to the earth set so that
  -- detection stays locale-safe (not reliant on a hardcoded English string).
  wfIcon = spellIcon(C.SpellID.WINDFURY_TOTEM)
  graceIcon = spellIcon(C.SpellID.GRACE_OF_AIR)
  local soe = spellName(C.SpellID.STRENGTH_OF_EARTH)
  if soe then EARTH_TOTEM_BUFFS[soe] = true end
  scanShaman(self)
  self:RegisterEvent("GROUP_ROSTER_UPDATE",   "OnRosterUpdate")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnRosterUpdate")
  self:RegisterEvent("PLAYER_LOGIN",          "OnRosterUpdate")
end

function TotemTracker:OnRosterUpdate()
  scanShaman(self)
end

function TotemTracker:HasShaman()
  if self._sim then return true end   -- sim forces the panel on for testing
  return self._hasShaman and true or false
end

-- Test simulation: pretend a twisting shaman is up so the twist render +
-- timers can be verified without one. WF gets a rolling 10s swipe (mimics the
-- enchant being re-applied every totem pulse); Grace + Earth are steady.
function TotemTracker:ToggleSim()
  self._sim = not self._sim
  return self._sim
end

local function setSlot(t, present, exp, dur, icon)
  t.present = present and true or false
  t.expirationTime = exp or 0
  t.duration = dur or 0
  t.icon = icon
end

-- Slow lane (Core:Tick): this Refresh does two full 40-slot UnitBuff scans of
-- the player plus a weapon-enchant read. Totem/enchant state changes on a
-- multi-second pulse, so scanning it per frame was pure waste. The view renders
-- from state.totems every frame regardless, so the panel stays smooth.
TotemTracker.refreshInterval = 0.1

function TotemTracker:Refresh(state)
  state.totems = state.totems or {}
  state.totems.air      = state.totems.air      or {}
  state.totems.earth    = state.totems.earth    or {}
  state.totems.windfury = state.totems.windfury or {}
  local air, earth, windfury = state.totems.air, state.totems.earth, state.totems.windfury

  if self._sim then
    local now = GetTime()
    local cyc = 10
    local rem = cyc - (now % cyc)                  -- rolling 0..10s like a re-pulsing WF enchant
    setSlot(windfury, true, now + rem, cyc, wfIcon) -- WF extra slot (animated swipe), on top
    setSlot(air,   true, 0, 0, graceIcon)          -- Grace of Air (core air slot, steady)
    setSlot(earth, true, 0, 0, nil)                -- Strength of Earth (steady; view default icon)
    return
  end

  -- Core tracking: the air AURA (Grace/Wrath/NR/Tranquil) and earth. Both are
  -- always-present slots (greyed when out of range). Windfury is a temporary
  -- weapon enchant, NOT an aura, so it's a separate EXTRA slot the view only
  -- renders when actually on you (twisting) — see Frame_TotemTracker.
  local aaExp,    aaDur,    aaIcn    = unitBuffFromSet("player", AIR_TOTEM_BUFFS)
  local earthExp, earthDur, earthIcn = unitBuffFromSet("player", EARTH_TOTEM_BUFFS)
  local wfExp,    wfDur,    wfIcn    = windfuryInfo()

  setSlot(air,      aaExp    ~= nil, aaExp,    aaDur,    aaIcn)
  setSlot(earth,    earthExp ~= nil, earthExp, earthDur, earthIcn)
  setSlot(windfury, wfExp    ~= nil, wfExp,    wfDur,    wfIcn)
end
