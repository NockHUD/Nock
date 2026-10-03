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
        -- `index` is the client's own row: what C_Minimap.SetTracking takes.
        if type(a) == "table" then
          e = { name = P(a.name), active = P(a.active) == true, spellID = P(a.spellID), index = i }
        elseif a ~= nil then
          e = { name = P(a), active = P(c) == true, spellID = P(f), index = i }
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
  -- The creature type name RAW: inside an instance it is a secret (probed
  -- 2026-09-30, out of combat too), which the track-mark FontStrings render
  -- and nothing compares.
  creatureTypeRaw = function()
    if not (_G.UnitExists and UnitExists("target") and _G.UnitCreatureType) then return nil end
    return (UnitCreatureType("target"))
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
  -- A moment the auto-switch must not cast in: mid-cast, stealthed or
  -- Shadowmelded (the cast would break it), dead, on a flight path.
  busy = function(state)
    if state.player and state.player.casting then return true end
    if _G.IsStealthed and P(IsStealthed()) == true then return true end
    if _G.UnitIsDeadOrGhost and P(UnitIsDeadOrGhost("player")) == true then return true end
    if _G.UnitOnTaxi and P(UnitOnTaxi("player")) == true then return true end
    return false
  end,
  -- The minimap menu's own call: not protected, so plain Lua may switch the
  -- tracking (the client casts the Track spell). `index` is the list row.
  setTracking = function(index)
    local MM = _G.C_Minimap
    if not (MM and MM.SetTracking) then return false end
    return (pcall(MM.SetTracking, index, true))
  end,
}

-- Seconds a new target must hold before the auto-switch casts: tabbing
-- through a pack never fires a cast per mob.
Tracking.AUTO_SETTLE = 0.3

-- Pure. The Track spell an armed auto-switch should cast: the one the target
-- wants, with points in Improved Tracking (the only reason tracking is
-- damage), on a live hostile target, when it is learned and not on (`wrong`).
function Nock.TrackingAutoPick(rank, hostile, wrong, need)
  if type(rank) ~= "number" or rank <= 0 then return nil end
  if hostile ~= true or wrong ~= true then return nil end
  return need
end

function Tracking:OnEnable()
  self:RegisterEvent("MINIMAP_UPDATE_TRACKING")
  self:RegisterEvent("SPELLS_CHANGED")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:PLAYER_ENTERING_WORLD()
end

-- Plain even where the target itself is secret: the track-mark flare holds
-- its grace from this stamp. A new target also arms ONE auto-switch.
function Tracking:PLAYER_TARGET_CHANGED()
  local now = GetTime()
  Nock.state.tracking.targetSince = now
  self._autoArmed, self._autoSince = true, now
end

-- Combat held the switch back (every switch is a cast): its end arms one for
-- the target you are left with.
function Tracking:PLAYER_REGEN_ENABLED()
  self._autoArmed, self._autoSince = true, GetTime()
end

-- The auto-switch (profile.trackingAutoSwitch): one switch per arming, so a
-- tracking picked by hand afterwards stays until the next target. Combat and
-- a busy moment keep it armed; everything else spends it, switch or not.
-- Inside an instance the target's type is a secret: `wrong` is never true
-- there and nothing is sent.
function Tracking:AutoSwitch(state, now)
  local p = Nock.db and Nock.db.profile
  if not (p and p.trackingAutoSwitch == true) then self._autoArmed = nil; return end
  if now - (self._autoSince or 0) < Tracking.AUTO_SETTLE then return end
  if self.Reads.inCombat() or self.Reads.busy(state) then return end
  self._autoArmed = nil
  local st, t = state.tracking, state.target
  local hostile = t and t.exists == true and t.alive == true and t.friendly == false
  local id = Nock.TrackingAutoPick(st.rank, hostile, st.wrong, st.targetTrackId)
  if not id then return end
  local list = self.Reads.trackingList()
  if type(list) ~= "table" then return end
  for _, e in ipairs(list) do
    if e.spellID == id and e.index then
      -- kept for `/nock probe tracking`: what was sent and whether the call ran
      self._autoLastId, self._autoLastIndex, self._autoLastAt = id, e.index, now
      self._autoLastOk = self.Reads.setTracking(e.index)
      return
    end
  end
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
  if self._autoArmed then self:AutoSwitch(state, now) end
end
