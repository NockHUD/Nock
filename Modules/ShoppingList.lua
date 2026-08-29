-- Modules/ShoppingList.lua
-- Restock helper. While the player is in a configured city zone, builds an
-- ordered list of curated/custom consumables that are below their threshold
-- into state.shopping. Event-driven (zone + bag), never per-tick: it defines
-- no :Refresh, so the central tick skips it entirely (zero cost outside use).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ShoppingList = Nock:NewModule("ShoppingList", "AceEvent-3.0")
local C = Nock.Constants

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile
  if p and p[key] ~= nil then return p[key] end
  return fallback
end

local function isEnabled() return profile("shoppingEnabled", true) ~= false end

local function trim(s) return (s or ""):gsub("^%s*(.-)%s*$", "%1") end

-- "Shattrath City, Orgrimmar" → { ["shattrath city"]=true, ["orgrimmar"]=true }
local function parseZones(str)
  local set = {}
  for token in tostring(str or ""):gmatch("[^,\r\n]+") do
    local z = trim(token):lower()
    if z ~= "" then set[z] = true end
  end
  return set
end

-- Free-form lines "itemID:threshold[:label]" → { {id, threshold, label}, ... }
local function parseCustom(str)
  local list = {}
  for line in tostring(str or ""):gmatch("[^,\r\n]+") do
    local body = trim(line)
    if body ~= "" then
      local idStr, rest = body:match("^(%d+)%s*:?%s*(.*)$")
      local id = tonumber(idStr)
      if id then
        local thrStr, label = rest:match("^(%d+)%s*:?%s*(.*)$")
        local thr = tonumber(thrStr) or 1
        list[#list + 1] = {
          id        = id,
          threshold = thr,
          label     = (label and label ~= "" and label) or nil,
          key       = "custom:" .. id,
        }
      end
    end
  end
  return list
end

local function currentZone()
  if GetRealZoneText then local z = GetRealZoneText(); if z and z ~= "" then return z end end
  if GetZoneText     then local z = GetZoneText();     if z and z ~= "" then return z end end
  return nil
end

local function itemCount(id)
  if not id then return 0 end
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
  if GetItemCount then return GetItemCount(id) or 0 end
  return 0
end

-- Total remaining CHARGES across all of `id` (for charged items like Drums of
-- Battle). On this client a charged item's bag stackCount is 1, not its
-- charges; GetItemCount(id,false,true) returns the true total charge count.
local function itemCharges(id)
  if not id then return 0 end
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, false, true) or 0 end
  if GetItemCount then return GetItemCount(id, false, true) or 0 end
  return 0
end

local function itemIcon(id)
  if not id then return "Interface\\Icons\\INV_Misc_Quiver_05" end
  if C_Item and C_Item.GetItemIconByID then
    local i = C_Item.GetItemIconByID(id); if i then return i end
  end
  if GetItemInfo then
    local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
    if icon then return icon end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function itemName(id, fallback)
  if id and GetItemInfo then
    local n = GetItemInfo(id)
    if n then return n end
  end
  return fallback or ("item " .. tostring(id))
end

-- Merged working catalog: curated (minus disabled, threshold overrides) + the
-- synthetic arrows entry + parsed custom lines. Rebuilt only on config change.
function ShoppingList:RebuildCatalog()
  local cat = {}
  local disabled  = profile("shoppingDisabled", nil)  or {}
  local overrides = profile("shoppingThreshold", nil) or {}
  for _, e in ipairs(C.SHOPPING_CURATED or {}) do
    if not disabled[e.key] then
      cat[#cat + 1] = {
        key       = e.key,
        id        = e.id,
        ids       = e.ids,     -- multi-item "banner" (summed); e.g. potion + injector
        charges   = e.charges, -- count remaining charges, not item qty (Drums)
        isArrows  = (e.key == "arrows"),
        label     = e.label,
        threshold = tonumber(overrides[e.key]) or e.threshold or 1,
      }
    end
  end
  for _, e in ipairs(parseCustom(profile("shoppingCustom", ""))) do
    cat[#cat + 1] = {
      key = e.key, id = e.id, isArrows = false,
      label = e.label, threshold = e.threshold,
    }
  end
  self._catalog = cat
  self._zoneSet = parseZones(profile("shoppingZones", C.SHOPPING_ZONES_DEFAULT))
  self._dirty   = false
end

function ShoppingList:Recompute()
  if self._dirty or not self._catalog then self:RebuildCatalog() end

  local sp = Nock.state.shopping
  sp.n = 0
  sp.nNeeded = 0

  if not isEnabled() then sp.active = false; return end

  -- `active` (auto-show) is gated on the zone, but the missing list itself is
  -- built everywhere so `/nock shopping` can show it on demand anywhere.
  local zone = currentZone()
  local matched = zone and self._zoneSet[zone:lower()] and zone or nil
  sp.active = matched ~= nil
  sp.zone   = matched or zone or ""

  -- Every catalog entry is published, stocked ones flagged `done`, so the view
  -- can show the whole list on request (the "show stocked" toggle). `nNeeded`
  -- is what the old `n` was: the count still below threshold.
  local items = sp.items
  local n, nNeeded = 0, 0
  for _, e in ipairs(self._catalog) do
    local have, label, icon
    if e.isArrows then
      have  = (Nock.state.ammo and Nock.state.ammo.total) or 0
      label = e.label
      icon  = "Interface\\Icons\\INV_Misc_Quiver_05"
    elseif e.ids then
      have = 0
      for _, id in ipairs(e.ids) do
        have = have + (e.charges and itemCharges(id) or itemCount(id))
      end
      label = e.label                       -- multi-item banner: use the label
      icon  = itemIcon(e.ids[1])
    else
      have  = e.charges and itemCharges(e.id) or itemCount(e.id)
      label = itemName(e.id, e.label)
      icon  = itemIcon(e.id)
    end
    local done = have >= e.threshold
    if not done then nNeeded = nNeeded + 1 end
    n = n + 1
    local row = items[n]
    if not row then row = {}; items[n] = row end
    row.key   = e.key
    row.label = label
    row.have  = have
    row.need  = e.threshold
    row.icon  = icon
    row.done  = done
  end
  sp.n = n
  sp.nNeeded = nNeeded
end

function ShoppingList:OnConfigChanged()
  self._dirty = true
  self:Recompute()
end

function ShoppingList:OnEnable()
  self._dirty = true
  self:RegisterEvent("PLAYER_ENTERING_WORLD",     "Recompute")
  self:RegisterEvent("ZONE_CHANGED_NEW_AREA",     "Recompute")
  self:RegisterEvent("ZONE_CHANGED",              "Recompute")
  self:RegisterEvent("BAG_UPDATE_DELAYED",        "Recompute")
  self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED",  "Recompute")
  self:RegisterMessage("NOCK_VISUALS_CHANGED",    "OnConfigChanged")
  self:Recompute()
end
