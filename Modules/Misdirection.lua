-- Modules/Misdirection.lua
-- Tracks Misdirection (spell 34477, 30s effect window, 120s CD) across every
-- hunter in your party/raid. Writes state.misdirection.hunters keyed by
-- hunter name; the view (Frame_Misdirect) reads that and renders one row per
-- hunter ordered by cast recency.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Misdirection = Nock:NewModule("Misdirection", "AceEvent-3.0")
local C = Nock.Constants

local MD_SPELL_ID    = C.SpellID.MISDIRECTION
local MD_EFFECT_SEC  = C.MD_EFFECT_SEC   -- threat-redirect window
local MD_CD_SEC      = C.MD_CD_SEC       -- ability cooldown

-- Scan party/raid (plus self) for hunters. Brute-forces the unit IDs because
-- UnitExists is cheap and GroupSize APIs vary between Classic / TBC / WotLK.
local function scanHunters(self)
  local hunters = {}
  local function add(unit)
    if not (UnitExists and UnitExists(unit)) then return end
    local _, eng = UnitClass(unit)
    if eng ~= "HUNTER" then return end
    local name = UnitName(unit)
    if not name then return end
    -- party*/raid* sometimes return "Name-Realm"; UnitName always strips that.
    if not hunters[name] then
      hunters[name] = { unit = unit, guid = UnitGUID and UnitGUID(unit) or nil }
    end
  end

  add("player")
  for i = 1, 4 do add("party" .. i) end
  for i = 1, 40 do add("raid" .. i) end

  self._roster = hunters
end

local function findHunterByGUID(self, guid)
  if not guid then return nil end
  for name, info in pairs(self._roster) do
    if info.guid == guid then return name end
  end
  return nil
end

-- Returns the remaining charge count while the Misdirection buff is still on
-- the caster (UnitBuff's 3rd return, 3→1 as shots consume it — the same
-- stack-count convention BuffTracker reads), or nil once it has faded. When
-- all 3 charges are consumed the buff fades, so nil is our signal that the
-- active window ended early. A present buff that reports no count (0) still
-- means active — some auras are count-shy — the view just renders no number.
local function casterMDCharges(unit)
  if not (UnitExists and UnitExists(unit) and UnitBuff) then return nil end
  for i = 1, 40 do
    local name, _, count, _, _, _, _, _, _, spellId = UnitBuff(unit, i)
    if not name then return nil end
    if spellId == MD_SPELL_ID or name == "Misdirection" then
      return count or 0
    end
  end
  return nil
end

function Misdirection:OnEnable()
  self._roster  = {}   -- [name] = { unit, guid }
  self._md      = {}   -- [name] = { castTime, target, activeUntil, cdEnd }

  scanHunters(self)

  self:RegisterEvent("GROUP_ROSTER_UPDATE",        "OnRosterUpdate")
  self:RegisterEvent("PLAYER_ENTERING_WORLD",      "OnRosterUpdate")
  self:RegisterEvent("PLAYER_LOGIN",               "OnRosterUpdate")
  self:RegisterEvent("UNIT_PET",                   "OnRosterUpdate")  -- catches some roster transitions
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED","OnCombatLog")
end

function Misdirection:OnRosterUpdate()
  scanHunters(self)
end

function Misdirection:OnCombatLog()
  if not CombatLogGetCurrentEventInfo then return end

  -- Filter early: subevent + spellId. CLEU fires very often.
  local _, subevent, _, sourceGUID, _, _, _, destGUID, destName, _, _, spellId
        = CombatLogGetCurrentEventInfo()
  if subevent ~= "SPELL_CAST_SUCCESS" then return end
  if spellId ~= MD_SPELL_ID then return end

  local name = findHunterByGUID(self, sourceGUID)
  if not name then return end   -- caster isn't a tracked hunter

  local now = GetTime()
  self._md[name] = {
    castTime    = now,
    target      = destName,
    activeUntil = now + MD_EFFECT_SEC,
    cdEnd       = now + MD_CD_SEC,
  }
end

-- Refresh: rewrite state.misdirection.hunters from the cached roster + the
-- per-hunter cast log. Called by the central refresh loop.
--
-- Publishes UNCONDITIONALLY: the panel's own toggle belongs to the view, and
-- gating the producer on it used to mean the MD + Sapper announce
-- (Modules/SapperTracker) went silent for anyone who had the tracker section
-- switched off. Rows are updated in place — this runs on the central tick and
-- must not hand the GC a table per hunter per pass.
Misdirection.refreshInterval = 0.1   -- slow lane: a 30s window, not per-frame data

function Misdirection:Refresh(state)
  state.misdirection = state.misdirection or { hunters = {} }
  local list = state.misdirection.hunters

  -- Drop rows for hunters who are no longer in the group.
  for name in pairs(list) do
    if not self._roster[name] then list[name] = nil end
  end

  local now = GetTime()
  for name, info in pairs(self._roster) do
    local cast = self._md[name]
    local entry = list[name]
    if not entry then entry = {}; list[name] = entry end
    entry.name        = name
    entry.target      = nil
    entry.isActive    = false
    entry.charges     = nil
    entry.cdRemaining = 0
    entry.cdDuration  = MD_CD_SEC
    entry.castTime    = 0
    if cast then
      if now < cast.cdEnd then
        entry.cdRemaining = cast.cdEnd - now
        entry.castTime    = cast.castTime
        -- Carry the target through the whole CD window — view shows "Name ->
        -- Target" both during the active 30s and the trailing CD phase, so
        -- you can still see who someone last MD'd until they're ready again.
        entry.target      = cast.target
        if now < cast.activeUntil then
          -- Within the 30s effect window — but also verify the buff is still
          -- on the caster. When all 3 charges are consumed the buff fades
          -- early, which should flip the row into the regular CD-ticking
          -- (grey) phase even before activeUntil elapses.
          local charges = casterMDCharges(info.unit)
          if charges then
            entry.isActive = true
            if charges > 0 then entry.charges = charges end
          else
            -- Buff gone → charges consumed; collapse the active window so
            -- future ticks skip this branch entirely.
            cast.activeUntil = now
          end
        end
      else
        -- CD expired; drop cast record so future Refresh cycles skip it.
        self._md[name] = nil
      end
    end
  end
end
