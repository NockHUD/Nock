-- Modules/Durability.lua
-- Repair reminder. Computes equipped-gear durability % on durability/equipment
-- events and flags state.repair.needed when it's below the threshold AND the
-- player is in a configured shopping zone (reuses the shoppingZones list so it
-- follows whatever cities you set). Event-driven: no :Refresh, so the central
-- tick skips it entirely.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Durability = Nock:NewModule("Durability", "AceEvent-3.0")
local C = Nock.Constants

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile
  if p and p[key] ~= nil then return p[key] end
  return fallback
end

local function trim(s) return (s or ""):gsub("^%s*(.-)%s*$", "%1") end

-- Same zone list as the shopping list (single source for "city zones").
local function inCityZone()
  local zone
  if GetRealZoneText then zone = GetRealZoneText() end
  if (not zone or zone == "") and GetZoneText then zone = GetZoneText() end
  if not zone or zone == "" then return false end
  zone = zone:lower()
  local list = profile("shoppingZones", C.SHOPPING_ZONES_DEFAULT)
  for token in tostring(list or ""):gmatch("[^,\r\n]+") do
    if trim(token):lower() == zone then return true end
  end
  return false
end

-- Average equipped durability across the gear slots that have it (1..18;
-- non-durability slots return nil and are skipped).
local function equippedDurabilityPct()
  if not GetInventoryItemDurability then return 100 end
  local cur, max = 0, 0
  for slot = 1, 18 do
    local c, m = GetInventoryItemDurability(slot)
    if c and m and m > 0 then
      cur = cur + c
      max = max + m
    end
  end
  if max <= 0 then return 100 end
  return cur / max * 100
end

function Durability:Recompute()
  local r = Nock.state.repair
  r.pct = equippedDurabilityPct()
  local enabled = profile("repairWarnEnabled", true) ~= false
  local thr     = tonumber(profile("repairWarnPct", 90)) or 90
  r.needed = enabled and inCityZone() and r.pct < thr
end

function Durability:OnEnable()
  self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", "Recompute")
  self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED",    "Recompute")
  self:RegisterEvent("PLAYER_ENTERING_WORLD",       "Recompute")
  self:RegisterEvent("ZONE_CHANGED_NEW_AREA",       "Recompute")
  self:RegisterEvent("ZONE_CHANGED",                "Recompute")
  self:RegisterMessage("NOCK_VISUALS_CHANGED",      "Recompute")
  self:Recompute()
end
