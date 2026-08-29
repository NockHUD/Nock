-- Modules/MisdirectCast.lua
-- Owns the tank roster for the click-to-Misdirect panel. A group member counts
-- as a tank when they hold the raid's Main-Tank assignment
-- (GetPartyAssignment("MAINTANK", unit)) OR carry the TANK role
-- (UnitGroupRolesAssigned(unit) == "TANK"), or when their name is in the manual
-- fallback list. Roster changes are pushed to the view via NOCK_MDCAST_ROSTER;
-- the view wires the secure buttons (only legal out of combat). Also exposes
-- state.mdcast.ready (MD off cooldown) for the per-tick cosmetic dimming.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local MisdirectCast = Nock:NewModule("MisdirectCast", "AceEvent-3.0")
local C = Nock.Constants

local MD_SPELL_ID = C.SpellID.MISDIRECTION   -- 34477

local function isEnabled()
  local p = Nock.db and Nock.db.profile
  if not p then return true end
  return p.mdCastEnabled ~= false
end

-- Parse the manual tank list into a lookup set keyed by lowercased name. Same
-- comma/newline, case-insensitive style as helpersHideWA.
local function manualSet()
  local out = {}
  local p = Nock.db and Nock.db.profile
  local raw = p and p.mdCastTankList
  if not raw or raw == "" then return out end
  for token in tostring(raw):gmatch("[^,\n]+") do
    local name = token:gsub("^%s+", ""):gsub("%s+$", "")
    if name ~= "" then out[name:lower()] = true end
  end
  return out
end

local function isTankRole(unit)
  -- Raid's explicitly-assigned Main Tank (raid frame -> "Set Main Tank"). More
  -- reliable than the role flag, which raiders often carry without tanking.
  if GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then return true end
  return UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) == "TANK"
end

-- Scan player + party1-4 + raid1-40 for tanks. Brute-forces unit IDs (cheap;
-- UnitExists guards) exactly like the MD tracker's hunter scan. Result is an
-- ORDERED list so the view's row order is stable across rescans.
local function scanTanks(self)
  local tanks, seen = {}, {}
  local manual = manualSet()

  local function add(unit)
    if not (UnitExists and UnitExists(unit)) then return end
    -- You can't Misdirection yourself, so never list the player as a tank
    -- target (even if self-assigned the Tank role or in the manual list).
    if UnitIsUnit and UnitIsUnit(unit, "player") then return end
    local short = UnitName and UnitName(unit)
    if not short then return end
    local include = isTankRole(unit) or manual[short:lower()]
    if not include then return end
    -- Full name (with realm when cross-realm) is what the macro's @target needs.
    local full = (GetUnitName and GetUnitName(unit, true)) or short
    if seen[full] then return end
    seen[full] = true
    local _, class = UnitClass(unit)
    tanks[#tanks + 1] = { name = full, unit = unit, class = class }
  end

  add("player")
  for i = 1, 4  do add("party" .. i) end
  for i = 1, 40 do add("raid"  .. i) end

  self._tanks = tanks
end

function MisdirectCast:OnEnable()
  self._tanks = {}
  scanTanks(self)

  self:RegisterEvent("GROUP_ROSTER_UPDATE",   "OnRosterUpdate")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnRosterUpdate")
  self:RegisterEvent("PLAYER_LOGIN",          "OnRosterUpdate")
  self:RegisterEvent("UNIT_PET",              "OnRosterUpdate")
  -- Fires whenever anyone's assigned role changes — this is what makes tanks
  -- appear/disappear live (out of combat) as roles are set.
  self:RegisterEvent("PLAYER_ROLES_ASSIGNED", "OnRosterUpdate")
  -- Manual-list edits from the options panel.
  self:RegisterMessage("NOCK_MDCAST_RESCAN",  "OnRosterUpdate")

  self:Broadcast()
end

function MisdirectCast:OnRosterUpdate()
  scanTanks(self)
  self:Broadcast()
end

function MisdirectCast:Broadcast()
  self:SendMessage("NOCK_MDCAST_ROSTER", self._tanks)
end

-- Refresh: only the cheap per-tick cosmetic flag. The roster itself is pushed
-- by events (above), never wired here — secure buttons can't change in combat.
function MisdirectCast:Refresh(state)
  state.mdcast = state.mdcast or { tanks = {}, ready = true }
  state.mdcast.tanks = self._tanks

  local remaining = 0
  if isEnabled() and C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(MD_SPELL_ID)
    if info and info.startTime and info.startTime > 0 and (info.duration or 0) > 1.5 then
      remaining = (info.startTime + info.duration) - GetTime()
      if remaining < 0 then remaining = 0 end
    end
  end
  state.mdcast.ready = (remaining <= 0)
  state.mdcast.cdRemaining = remaining
end
