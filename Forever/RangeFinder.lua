-- Forever/RangeFinder.lua
-- Four zones on the checks that stay PLAIN in combat on this client (probes
-- 2026-09-22): IsItemInRange(8149) ~7 yd for melee, C_Spell.IsSpellInRange
-- (Auto Shot) for "can shoot", CheckInteractDistance(3) ~10 yd to split the
-- dead zone from too far. IsSpellInRange on a melee spell answers true
-- everywhere here and the C_SwingTimer range signal never fires, so neither
-- is used.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local RangeFinder = Nock:NewModule("RangeFinder", "AceEvent-3.0")

RangeFinder.refreshInterval = 0.1

local MELEE_ITEM = 8149      -- Voodoo Charm: ~7 yd, combat-reach aware (TBC finder's "near" probe)
local MID_INDEX  = 3         -- CheckInteractDistance index 3: ~10 yd

-- Pure. Drives the React range bar's existing modes with rangeProg in -1..1
-- ((prog + 1) / 2 is the fill): MELEE 0.5, dead zone CLOSE 0, SWEET -0.5,
-- too far LONG -1 (drawn dim and empty, no finding ladder on Forever).
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

local function meleeProbe()
  local CI = _G.C_Item
  if CI and CI.IsItemInRange then return plainBool(CI.IsItemInRange(MELEE_ITEM, "target")) end
  return nil
end

local function shootProbe()
  local CS = _G.C_Spell
  if not (CS and CS.IsSpellInRange) then return nil end
  return plainBool(CS.IsSpellInRange(Nock.Spells.AUTO_SHOT, "target"))
end

local function midProbe()
  if not _G.CheckInteractDistance then return nil end
  return plainBool(CheckInteractDistance("target", MID_INDEX))
end

function RangeFinder:OnEnable()
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
end

-- PLAYER_TARGET_CHANGED fires synchronously inside the client's own
-- TurnOrActionStop (right-click targeting). A range probe made from inside
-- that call is ADDON_ACTION_BLOCKED (IsItemInRange is AllowedWhenUntainted;
-- seen in prod 2026-09-23), while the same probe from the tick is fine. So
-- the handler only brings the tick's next refresh forward: one frame later,
-- outside the protected call, the finder re-reads the new target.
function RangeFinder:PLAYER_TARGET_CHANGED()
  self._nextRefresh = nil
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
  local melee, ranged, mid = nil, nil, nil
  if exists then melee, ranged, mid = meleeProbe(), shootProbe(), midProbe() end
  local zone, prog = Nock.RangeFinderClassify(melee, ranged, mid, exists, alive, friendly)
  t.rangeState, t.rangeProg = zone, prog
  t.rangeBracket, t.rangeEstimateStale = nil, false
  t.inMelee = zone == "MELEE"
  if zone == "MELEE" then t.rangeZone = "TOO_CLOSE"
  elseif zone == "SWEET" then t.rangeZone = "SWEET"
  elseif zone == "CLOSE" or zone == "LONG" then t.rangeZone = "OUT"
  else t.rangeZone = nil end
  -- The auto bar's "can a shot fire" gate (Nock.AutoSwingLive): the swing
  -- timer's own range signal never arrives on this client, so the shoot
  -- probe feeds it instead (nil while there is no live hostile target).
  if not state.ranged.swingRangeSignal then
    if zone ~= nil then state.ranged.targetInRange = ranged else state.ranged.targetInRange = nil end
  end
end
