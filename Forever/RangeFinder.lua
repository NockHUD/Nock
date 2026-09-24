-- Forever/RangeFinder.lua
-- The Forever range finder: reads the range checks that stay plain in combat and publishes the ladder segment and zone.

-- Checks (probe 2026-09-24): Wing Clip = melee reach; items 8149 (~7 yd,
-- melee fallback), 10645 (~20), 13289 (~25), 7734 (~30), 18904 (~35), 4945
-- (~40); CheckInteractDistance 4 (~28); Auto Shot = can shoot. The segment
-- logic lives in Forever/RangeLadder.lua; this file only reads and publishes.
-- IsSpellInRange on Raptor Strike answers true everywhere here and the
-- C_SwingTimer range signal never fires, so neither is used.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local RangeFinder = Nock:NewModule("RangeFinder", "AceEvent-3.0")

RangeFinder.refreshInterval = 0.1

local WING_CLIP = 2974
-- item checks by reading-table field (Forever/RangeLadder.lua Resolve)
local ITEMS = { i8149 = 8149, i10645 = 10645, i13289 = 13289, i7734 = 7734, i18904 = 18904, i4945 = 4945 }
local R = {}          -- one set of readings, reused every refresh

-- Pure. The zone from the three first-generation probes (melee, can shoot,
-- ~10 yd), with rangeProg in -1..1: MELEE 0.5, dead zone CLOSE 0, SWEET
-- -0.5, too far LONG -1. Superseded on Forever by Nock.RangeLadder.Zone;
-- kept as the documented mapping those values come from.
function Nock.RangeFinderClassify(melee, ranged, mid, exists, alive, friendly)
  if not exists or not alive or friendly then return nil, -1 end
  if melee == true then return "MELEE", 0.5 end
  if ranged == true then return "SWEET", -0.5 end
  if mid == true then return "CLOSE", 0 end
  return "LONG", -1
end

local function plainBool(v)
  v = Nock.Flavor.Plain(v)
  if type(v) == "boolean" then return v end
  if v == 1 then return true elseif v == 0 then return false end
  return nil
end

local function shootProbe()
  local CS = _G.C_Spell
  if not (CS and CS.IsSpellInRange) then return nil end
  return plainBool(CS.IsSpellInRange(Nock.Spells.AUTO_SHOT, "target"))
end

-- Pure. One grid tile's out-of-range answer (state.target.spellOut[key]):
-- true out, false in, nil unknown (a self-cast, a spell the client will not
-- answer for; the tile stays untinted). A melee tile (Raptor Strike) follows
-- the melee probe: IsSpellInRange on a melee spell says true everywhere here.
function Nock.ForeverSlotOut(isMelee, apiIn, meleeIn)
  if isMelee then
    if meleeIn == nil then return nil end
    return not meleeIn
  end
  if apiIn == nil then return nil end
  return not apiIn
end

-- A tile's spell by NAME first: ranks are separate spells on Forever, and the
-- name asks about the highest rank the character knows; the id is the
-- fallback.
local function spellInRange(id)
  local CS = _G.C_Spell
  if not (CS and CS.IsSpellInRange) then return nil end
  local API = Nock.API
  local n = Nock.Flavor.Plain(API and API.SpellName and API.SpellName(id))
  local v
  if type(n) == "string" then v = plainBool(CS.IsSpellInRange(n, "target")) end
  if v == nil then v = plainBool(CS.IsSpellInRange(id, "target")) end
  return v
end

local function scanSpellOut(so, meleeIn)
  for key, s in pairs(Nock.state.cooldowns) do
    local id = s.spellId
    local v = nil
    if id and not s.melee then v = spellInRange(id) end
    so[key] = Nock.ForeverSlotOut(s.melee, v, meleeIn)
  end
end

local function wipeSpellOut(so)
  for k in pairs(so) do so[k] = nil end
end

local function itemIn(id)
  local CI = _G.C_Item
  if CI and CI.IsItemInRange then return plainBool(CI.IsItemInRange(id, "target")) end
  return nil
end

local function readLadder(r)
  for field, id in pairs(ITEMS) do r[field] = itemIn(id) end
  local CID = _G.CheckInteractDistance
  r.cid4 = CID and plainBool(CID("target", 4)) or nil
  r.wingClip = spellInRange(WING_CLIP)
  r.shoot = shootProbe()
end

-- The segment list follows Auto Shot's reported range (Hawk Eye adds 2/4/6
-- yd). Rebuilt on spell and talent changes; ladderRev moves only when the
-- list actually changed.
function RangeFinder:RebuildLayout()
  local minR, maxR
  local CS = _G.C_Spell
  if CS and CS.GetSpellInfo then
    local okc, info = pcall(CS.GetSpellInfo, Nock.Spells.AUTO_SHOT)
    if okc and type(info) == "table" then
      minR, maxR = Nock.Flavor.Plain(info.minRange), Nock.Flavor.Plain(info.maxRange)
    end
  end
  -- reactRangeStyle: "compact" (default, five segments) or "detailed"
  local prof = Nock.db and Nock.db.profile
  local compact = not (prof and prof.reactRangeStyle == "detailed")
  local layout = Nock.RangeLadder.Layout(minR, maxR, compact)
  if not self._layout or self._layout.id ~= layout.id then
    self._layout = layout
    self._layoutRev = (self._layoutRev or 0) + 1
  end
end

function RangeFinder:OnEnable()
  self._settle = {}
  -- IsItemInRange answers only for items the client has loaded: ask for the
  -- ladder's six up front so a cold cache after login does not blank it.
  local CI = _G.C_Item
  if CI and CI.RequestLoadItemDataByID then
    for _, id in pairs(ITEMS) do pcall(CI.RequestLoadItemDataByID, id) end
  end
  self:RebuildLayout()
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
  self:RegisterEvent("SPELLS_CHANGED", "RebuildLayout")
  -- the Range Finder style setting (compact / detailed) arrives here
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "RebuildLayout")
  -- Talent events differ between clients; an unknown one must not stop the module.
  pcall(self.RegisterEvent, self, "CHARACTER_POINTS_CHANGED", "RebuildLayout")
  pcall(self.RegisterEvent, self, "PLAYER_TALENT_UPDATE", "RebuildLayout")
end

-- PLAYER_TARGET_CHANGED fires synchronously inside the client's own
-- TurnOrActionStop (right-click targeting). A range probe from inside that
-- call was ADDON_ACTION_BLOCKED in prod (2026-09-23); the friendly-target
-- gate in Refresh is the likelier cause, but the handler still only brings the
-- tick's next refresh forward so no probe ever runs inside the client's call.
function RangeFinder:PLAYER_TARGET_CHANGED()
  self._nextRefresh = nil
  -- the new target's segment publishes at once, not after the settle
  if self._settle then self._settle.key = nil end
end

function RangeFinder:Refresh(state)
  local t = state.target
  local exists = plainBool(UnitExists and UnitExists("target")) == true
  local alive = exists and plainBool(UnitIsDeadOrGhost and UnitIsDeadOrGhost("target")) == false
  local attackable = exists and plainBool(UnitCanAttack and UnitCanAttack("player", "target"))
  -- A secret answer on attackability is treated as "not attackable": no zone
  -- rather than a wrong one.
  local friendly = attackable ~= true
  t.exists, t.alive, t.friendly = exists, alive, friendly
  -- Probe live hostile targets only. In combat the client protects
  -- IsItemInRange and CheckInteractDistance on a unit you cannot attack
  -- (ADDON_ACTION_BLOCKED from the plain tick, 2026-09-24; LibRangeCheck gates
  -- on the same InCombatLockdown() and not UnitCanAttack test), and a
  -- friendly or dead target gets no zone anyway.
  local live = alive and not friendly
  if not self._layout then self:RebuildLayout() end
  t.ladderLayout, t.ladderRev = self._layout, self._layoutRev
  local key, shoot = nil, false
  if live then
    readLadder(R)
    key, shoot = Nock.RangeLadder.Resolve(R, self._layout)
  end
  self._settle = self._settle or {}
  key, shoot = Nock.RangeLadder.Settle(self._settle, key, shoot, GetTime())
  t.ladderKey, t.ladderShoot = key, shoot
  local zone, prog = Nock.RangeLadder.Zone(key, shoot)
  t.rangeState, t.rangeProg = zone, prog
  t.rangeBracket, t.rangeEstimateStale = nil, false
  t.inMelee = zone == "MELEE"
  if zone == "MELEE" then t.rangeZone = "TOO_CLOSE"
  elseif zone == "SWEET" then t.rangeZone = "SWEET"
  elseif zone == "CLOSE" or zone == "LONG" then t.rangeZone = "OUT"
  else t.rangeZone = nil end
  -- Per-tile range for the grid's out-of-range tint, under the same gate;
  -- a melee tile follows the melee reading the ladder used.
  if t.spellOut then
    if live then
      local meleeIn = R.wingClip
      if meleeIn == nil then meleeIn = R.i8149 end
      scanSpellOut(t.spellOut, meleeIn)
    else
      wipeSpellOut(t.spellOut)
    end
  end
  -- Hunter's Mark castable from here (the corner icon's range tint), by name
  -- so the highest known rank answers.
  local hmIn = nil
  if live then hmIn = spellInRange(Nock.Spells.HUNTERS_MARK) end
  if hmIn == nil then t.markOut = nil else t.markOut = not hmIn end
  -- The auto bar's "can a shot fire" gate (Nock.AutoSwingLive): the raw
  -- Auto Shot reading, unsettled (the bar should blank the moment a shot
  -- cannot fire); nil while there is no live hostile target.
  if not state.ranged.swingRangeSignal then
    if live then state.ranged.targetInRange = R.shoot else state.ranged.targetInRange = nil end
  end
end
