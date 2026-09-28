-- Forever/Tracking.lua
-- The hunter's tracking as state: which Track spell is on, which one the target's creature type wants, Improved Tracking's rank; published to state.tracking for the warning and the wheel.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Tracking = Nock:NewModule("Tracking", "AceEvent-3.0")

Tracking.refreshInterval = 0.2

local function P(v) return Nock.Flavor.Plain(v) end

-- Improved Tracking is read out of combat at most this often and held
-- through a fight (talents only change out of combat).
local RANK_RECHECK = 5

-- Pure. The Track spell a creature type wants, or nil. `typeName` is what
-- UnitCreatureType says (localized); `typeNames` the client's own list
-- ([creature type id] = localized name, from C_CreatureInfo) that turns it
-- into an id. Without the list the English names serve.
function Nock.TrackingForCreatureType(typeName, typeNames)
  if type(typeName) ~= "string" or typeName == "" then return nil end
  local S = Nock.Spells
  local typeId
  if type(typeNames) == "table" then
    for id, name in pairs(typeNames) do
      if name == typeName then typeId = id; break end
    end
  else
    typeId = S.CREATURE_TYPE_EN[typeName]
  end
  return typeId and S.TRACK_BY_CREATURE_TYPE[typeId] or nil
end

-- Track spell name -> base id, learned from the client's names once.
local NAME_TO_ID
local function nameToId()
  if NAME_TO_ID then return NAME_TO_ID end
  local out, complete = {}, true
  for id in pairs(Nock.Spells.TRACKING) do
    local n = Nock.API and Nock.API.SpellName and P(Nock.API.SpellName(id))
    if type(n) == "string" then out[n] = id else complete = false end
  end
  if complete then NAME_TO_ID = out end
  return out
end

-- Pure. The Track spell that is on, from the minimap tracking list (entries
-- { name, active, spellID }): by spell id when the client fills it, by name
-- otherwise. nil when none of the hunter's Track spells is on.
function Nock.TrackingActive(list)
  if type(list) ~= "table" then return nil end
  local T = Nock.Spells.TRACKING
  local byName
  for _, e in ipairs(list) do
    if e.active == true then
      if e.spellID and T[e.spellID] then return e.spellID end
      if type(e.name) == "string" then
        byName = byName or nameToId()
        local id = byName[e.name]
        if id then return id end
      end
    end
  end
  return nil
end

-- The live reads, replaceable for the tests. Every one secret-guarded.
local LIST = {}
Tracking.Reads = {
  -- The minimap tracking list (25 entries on Forever, probed 2026-09-28: the
  -- Track spells carry their spellID and `active` plain; the filters carry
  -- none). The Mainline shape is one table per entry; the older shape
  -- returns the fields, so both are read.
  trackingList = function()
    local MM = _G.C_Minimap
    if not (MM and MM.GetNumTrackingTypes and MM.GetTrackingInfo) then return nil end
    local okn, n = pcall(MM.GetNumTrackingTypes)
    n = okn and P(n)
    if type(n) ~= "number" then return nil end
    for i = #LIST, 1, -1 do LIST[i] = nil end
    for i = 1, n do
      local okc, a, _, c, _, _, f = pcall(MM.GetTrackingInfo, i)
      if okc then
        local e
        if type(a) == "table" then
          e = { name = P(a.name), active = P(a.active) == true, spellID = P(a.spellID) }
        elseif a ~= nil then
          e = { name = P(a), active = P(c) == true, spellID = P(f) }
        end
        if e then LIST[#LIST + 1] = e end
      end
    end
    return LIST
  end,
  creatureType = function()
    if not (_G.UnitExists and UnitExists("target")) then return nil end
    return P(_G.UnitCreatureType and UnitCreatureType("target"))
  end,
  -- [creature type id] = localized name, or nil without the API.
  creatureTypeNames = function()
    local CI = _G.C_CreatureInfo
    if not (CI and CI.GetCreatureTypeIDs and CI.GetCreatureTypeInfo) then return nil end
    local oki, ids = pcall(CI.GetCreatureTypeIDs)
    if not (oki and type(ids) == "table") then return nil end
    local out = {}
    for _, id in ipairs(ids) do
      local okc, info = pcall(CI.GetCreatureTypeInfo, id)
      local name = okc and type(info) == "table" and P(info.name)
      if type(name) == "string" then out[id] = name end
    end
    return next(out) and out or nil
  end,
  traitRank = function(id, name) return Nock.Traits and Nock.Traits.LiveRank(id, name) or nil end,
  spellbook = function() return Nock.ForeverSpellbookNames and Nock.ForeverSpellbookNames() or nil end,
  inCombat = function() return _G.InCombatLockdown and InCombatLockdown() or false end,
}

function Tracking:OnEnable()
  self:RegisterEvent("MINIMAP_UPDATE_TRACKING")
  self:RegisterEvent("SPELLS_CHANGED")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:PLAYER_ENTERING_WORLD()
end

function Tracking:PLAYER_ENTERING_WORLD()
  self._typeNames = nil
  self._rankAt = nil
  self:MINIMAP_UPDATE_TRACKING()
  self:SPELLS_CHANGED()
end

function Tracking:MINIMAP_UPDATE_TRACKING()
  local st = Nock.state.tracking
  st.activeId = Nock.TrackingActive(self.Reads.trackingList())
end

-- Learned Track spells by NAME (ranks are separate spells on Forever, and
-- the tracking spells have one). Without the spellbook API every one counts.
function Tracking:SPELLS_CHANGED()
  local st = Nock.state.tracking
  local names = self.Reads.spellbook()
  local changed = false
  for id in pairs(Nock.Spells.TRACKING) do
    local n = Nock.API and Nock.API.SpellName and P(Nock.API.SpellName(id))
    local known = nil
    if names == nil or (type(n) == "string" and names[n]) then known = true end
    if st.known[id] ~= known then st.known[id] = known; changed = true end
  end
  if changed then st.knownRev = st.knownRev + 1 end
  -- A spellbook change may be a respec: the talent is re-read.
  if Nock.Traits then Nock.Traits.Reset() end
  self._rankAt = nil
end

function Tracking:Refresh(state)
  local st = state.tracking
  local now = GetTime()
  -- The talent, out of combat, held through a fight.
  if not self.Reads.inCombat() and (not self._rankAt or now - self._rankAt >= RANK_RECHECK) then
    self._rankAt = now
    local S = Nock.Spells
    local r = self.Reads.traitRank(S.IMPROVED_TRACKING, S.IMPROVED_TRACKING_NAME)
    st.rank = type(r) == "number" and r or nil
    -- Testing without the talent (`/nock probe tracking any`, until /reload).
    if self.ignoreTalent then st.rank = 1 end
  end
  -- The target's creature type and the Track spell it wants.
  local typeName = self.Reads.creatureType()
  if typeName ~= st.targetTypeName then
    st.targetTypeName = typeName
    if typeName and self._typeNames == nil then self._typeNames = self.Reads.creatureTypeNames() or false end
    st.targetTrackId = Nock.TrackingForCreatureType(typeName, self._typeNames or nil)
  end
  st.wrong = st.targetTrackId ~= nil and st.known[st.targetTrackId] == true and st.activeId ~= st.targetTrackId
end
