-- Modules/SapperTracker.lua
-- EXPERIMENTAL. Tracks Sapper Charge use across the group and announces the
-- MD + Sapper opener. Writes state.sapper.byName keyed by short name; the
-- Misdirection panel (UI/Frame_Misdirect) draws one sapper square per tank and
-- per hunter row from it.
--
-- What we can and cannot know: your OWN sapper is read from the item itself
-- (GetItemCount + GetItemCooldown), so it is exact. Everybody else's is
-- combat-log evidence only — someone who saps outside your CLEU range, or
-- before you zoned in, reads as ready until you actually see them use one.
-- A name with no entry at all means "no evidence they're an engineer"; the
-- view draws that as a dimmed placeholder.

local Nock   = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Sapper = Nock:NewModule("SapperTracker", "AceEvent-3.0")
local C      = Nock.Constants

local SAPPER   = C.SAPPER
local CD_SEC   = SAPPER.CD          -- 300s, shared by Goblin and Super
local MD_SEC   = C.MD_EFFECT_SEC    -- the window an MD opener has to land in

-- One use produces a cast plus a fistful of damage rows (including the one
-- that hurts the user). Anything inside this window is the same explosion.
local USE_DEDUPE = 5

-- Mashing a tracker row's "next up" button shouldn't repeat the call-out.
local NEXTUP_DEDUPE = 3

-- Cold-start only: the item cache answers GetItemSpell/GetItemInfo within a
-- second or two of login and the real match set takes over from there.
local FALLBACK_ICON = "Interface\\Icons\\Spell_Fire_SelfDestruct"

-- ---------------------------------------------------------------------------
-- Profile accessors
-- ---------------------------------------------------------------------------
local function profile()
  return Nock.db and Nock.db.profile or nil
end

local function isEnabled()
  local p = profile()
  if not p then return false end
  return p.mdSapperEnabled == true      -- experimental, opt-in
end

local function announceOn()
  local p = profile()
  if not p then return false end
  return p.mdSapperAnnounce ~= false
end

local function selfOnly()
  local p = profile()
  return p and p.mdSapperAnnounceScope == "self"
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- Combat-log names arrive as "Name-Realm" cross-realm; every roster key here
-- (and in Modules/Misdirection) is the short name.
local function shortName(name)
  if not name then return nil end
  return (name:gsub("%-.*$", ""))
end

local function groupChannel()
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
  if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
  return nil
end

-- Rewrite an entry in place — Refresh runs on the central tick, so it must not
-- hand the garbage collector a fresh table per person per pass.
local function setEntry(list, name, cdRemaining)
  local e = list[name]
  if not e then e = {}; list[name] = e end
  e.name        = name
  e.known       = true
  e.cdRemaining = cdRemaining
  e.cdDuration  = CD_SEC
  return e
end

-- ---------------------------------------------------------------------------
-- Item resolution. The match set is built from the items themselves so it is
-- locale-correct and immune to which of the catalog's spell IDs this client
-- actually logs; SAPPER.SPELL_IDS is only the seed.
-- ---------------------------------------------------------------------------
function Sapper:ResolveItems()
  local resolved = true
  for i = 1, #SAPPER.ITEMS do
    local itemID = SAPPER.ITEMS[i]

    if GetItemSpell then
      local sName, sID = GetItemSpell(itemID)
      if sID   then self._spellIds[sID] = true end
      if sName then self._spellNames[sName] = true end
    end

    local iName = GetItemInfo and GetItemInfo(itemID) or nil
    if iName then
      self._spellNames[iName] = true
      -- Texture is the 10th return; pulled with select rather than eight
      -- throwaway locals (and never the global `_`).
      self._icons[itemID] = select(10, GetItemInfo(itemID)) or self._icons[itemID]
    else
      resolved = false      -- item not in the client cache yet; try again later
    end
  end
  self._resolved = resolved
end

local function isSapperSpell(self, spellId, spellName)
  if spellId and self._spellIds[spellId] then return true end
  -- Name comparison is exact on purpose: the sapper's use effect carries the
  -- item's own name in every locale, and lowercasing here would allocate a
  -- string on every damage event in the log.
  if spellName and self._spellNames[spellName] then return true end
  return false
end

-- Cooldown remaining, whether one is in the bags, and the icon of the charge
-- we'd actually reach for (Super first). Your own row only.
function Sapper:OwnItemState(now)
  local remaining, has, icon = 0, false, nil
  for i = 1, #SAPPER.ITEMS do
    local itemID = SAPPER.ITEMS[i]
    local count = GetItemCount and GetItemCount(itemID) or 0
    if count and count > 0 then
      has = true
      if not icon then icon = self._icons[itemID] end
      if GetItemCooldown then
        local start, duration = GetItemCooldown(itemID)
        if start and start > 0 and duration and duration > 0 then
          local rem = (start + duration) - now
          if rem > remaining then remaining = rem end
        end
      end
    end
  end
  return remaining, has, icon
end

-- ---------------------------------------------------------------------------
-- Roster. Only group members are recorded — the combat log is full of people
-- we will never draw a row for.
-- ---------------------------------------------------------------------------
local function scanRoster(self)
  local roster = self._roster
  for k in pairs(roster) do roster[k] = nil end

  local function add(unit)
    if not (UnitExists and UnitExists(unit)) then return end
    local n = UnitName and UnitName(unit)
    if n then roster[shortName(n)] = true end
  end

  add("player")
  for i = 1, 4  do add("party" .. i) end
  for i = 1, 40 do add("raid"  .. i) end

  -- Forget people who left, so a long session doesn't accumulate strangers.
  -- Skipped when the scan came up empty (pre-login), which would wipe the lot.
  if next(roster) then
    for name in pairs(self._used) do
      if not roster[name] then self._used[name] = nil end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
function Sapper:OnEnable()
  self._roster     = {}   -- [shortName] = true
  self._used       = {}   -- [shortName] = { at, cdEnd }
  self._lastNextUp = {}   -- [shortName] = GetTime of the last call-out
  self._spellIds   = {}
  self._spellNames = {}
  self._icons      = {}
  self._resolved   = false
  self._playerName = shortName(UnitName and UnitName("player"))

  for i = 1, #SAPPER.SPELL_IDS do self._spellIds[SAPPER.SPELL_IDS[i]] = true end
  self:ResolveItems()
  scanRoster(self)

  self:RegisterEvent("GROUP_ROSTER_UPDATE",        "OnRosterUpdate")
  self:RegisterEvent("PLAYER_ENTERING_WORLD",      "OnRosterUpdate")
  self:RegisterEvent("PLAYER_LOGIN",               "OnRosterUpdate")
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED","OnCombatLog")
  -- Per-hunter "next up" button on the tracker rows (UI/Frame_Misdirect).
  self:RegisterMessage("NOCK_MD_NEXTUP",           "OnNextUp")
end

function Sapper:OnRosterUpdate()
  self._playerName = self._playerName or shortName(UnitName and UnitName("player"))
  scanRoster(self)
end

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------
function Sapper:OnCombatLog()
  if not isEnabled() then return end
  if not CombatLogGetCurrentEventInfo then return end

  -- Filter early: subevent, then the spell. CLEU fires hundreds of times a
  -- second in a raid and everything below this is off the hot path.
  local _, subevent, _, sourceGUID, sourceName, _, _, destGUID, _, _, _, spellId, spellName
        = CombatLogGetCurrentEventInfo()
  if subevent ~= "SPELL_CAST_SUCCESS" and subevent ~= "SPELL_DAMAGE" then return end
  if not isSapperSpell(self, spellId, spellName) then return end
  -- SPELL_DAMAGE is only a backstop for a client that doesn't log the cast, so
  -- take just the blast that hits its own user: damage dealt to a third party
  -- says nothing about who pulled the pin.
  if subevent == "SPELL_DAMAGE" and sourceGUID ~= destGUID then return end

  local name = shortName(sourceName)
  if not name or not self._roster[name] then return end

  local now = GetTime()
  local rec = self._used[name]
  if rec and (now - rec.at) < USE_DEDUPE then return end   -- same explosion
  if not rec then rec = {}; self._used[name] = rec end
  rec.at    = now
  rec.cdEnd = now + CD_SEC

  self:MaybeAnnounce(name, now)
end

-- ---------------------------------------------------------------------------
-- Announce. A sapper thrown inside somebody's own Misdirection window is the
-- opener worth calling out — the blast's threat lands on their MD target.
-- Reads the MD cast from state rather than the live buff: the buff scan is
-- blind to a hunter standing outside aura range, the recorded cast is not.
-- ---------------------------------------------------------------------------
function Sapper:MaybeAnnounce(name, now)
  if not announceOn() then return end
  local isSelf = (name == self._playerName)
  if selfOnly() and not isSelf then return end

  local hunters = Nock.state and Nock.state.misdirection and Nock.state.misdirection.hunters
  local md = hunters and hunters[name]
  if not (md and md.target) then return end
  local castTime = md.castTime or 0
  if castTime <= 0 or (now - castTime) > MD_SEC then return end

  local msg
  if isSelf then
    msg = ("Sapper + MD -> %s"):format(shortName(md.target))
  else
    msg = ("%s: Sapper + MD -> %s"):format(name, shortName(md.target))
  end

  local ch = groupChannel()
  if ch and SendChatMessage then
    SendChatMessage(msg, ch)
  else
    Nock:Print(msg)
  end
end

-- ---------------------------------------------------------------------------
-- "Next up in the rotation" call-out, fired by the per-hunter button on each
-- tracker row. Unlike the automatic MD + Sapper line this is a deliberate
-- press, so it ignores the announce toggle and only swallows a repeat press on
-- the same hunter; naming somebody else goes out immediately.
-- ---------------------------------------------------------------------------
function Sapper:OnNextUp(_, name)
  name = shortName(name)
  if not name or name == "" then return end

  local now = GetTime()
  local last = self._lastNextUp[name]
  if last and (now - last) < NEXTUP_DEDUPE then return end
  self._lastNextUp[name] = now

  local msg = ("Next up in MD + Sapper Rotation: %s"):format(name)
  local ch = groupChannel()
  if ch and SendChatMessage then
    SendChatMessage(msg, ch)
  else
    Nock:Print(msg)
  end
end

-- ---------------------------------------------------------------------------
-- Central-tick publish. Slow lane: a 5-minute cooldown does not need 30Hz.
-- ---------------------------------------------------------------------------
Sapper.refreshInterval = 0.25

function Sapper:Refresh(state)
  state.sapper = state.sapper or { byName = {} }
  local list = state.sapper.byName

  if not isEnabled() then
    for k in pairs(list) do list[k] = nil end
    return
  end

  if not self._resolved then self:ResolveItems() end

  local now = GetTime()
  for name, rec in pairs(self._used) do
    local rem = rec.cdEnd - now
    if rem < 0 then rem = 0 end
    setEntry(list, name, rem)
  end

  -- Your own row: the item is the truth. Carrying one is enough to light the
  -- slot up, and the longer of (item cooldown, last observed use) wins so the
  -- countdown survives spending your last charge.
  local me = self._playerName
  if me then
    local itemRem, has, icon = self:OwnItemState(now)
    state.sapper.icon = icon
      or self._icons[SAPPER.ITEMS[1]] or self._icons[SAPPER.ITEMS[2]] or FALLBACK_ICON
    local own = list[me]
    if has or own then
      local rem = own and own.cdRemaining or 0
      if itemRem > rem then rem = itemRem end
      setEntry(list, me, rem)
    end
  else
    state.sapper.icon = state.sapper.icon or FALLBACK_ICON
  end
end
