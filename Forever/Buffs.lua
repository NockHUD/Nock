-- Forever/Buffs.lua
-- Own-cast buffs for the React buff row: a cast stamps the buff with its
-- learned duration while auras are secret; out of combat the aura cache is
-- the truth (it learns the duration and corrects the expiry both ways).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local BuffLedger = Nock:NewModule("BuffLedger", "AceEvent-3.0")

BuffLedger.refreshInterval = 0.1

local function remembered()
  local db = Nock.db and Nock.db.char
  if not db then return nil end
  db.foreverBuffLearned = db.foreverBuffLearned or {}
  return db.foreverBuffLearned
end

local function baseSpell(id)
  local CS = _G.C_Spell
  if CS and CS.GetBaseSpell then
    local okc, base = pcall(CS.GetBaseSpell, id)
    if okc and type(base) == "number" and base > 0 then return base end
  end
  return id
end

-- Blizzard's pet happiness faces (PetPaperDollFrame art), one atlas cell per
-- state; the tables are kept so the slot painter can diff them by identity.
local HAPPINESS_TEX = [[Interface\PetPaperDollFrame\UI-PetHappiness]]
local HAPPINESS_COORD = {
  [1] = { 0.375,  0.5625, 0, 0.359375 },  -- Unhappy
  [2] = { 0.1875, 0.375,  0, 0.359375 },  -- Content
}
local PLAYER_ONLY = { "player" }

function BuffLedger:OnEnable()
  self._track, self._order = {}, {}
  local mem = remembered()
  for i, b in ipairs(Nock.Spells.BUFFS) do
    local dur = (mem and mem[b.id]) or b.dur
    self._track[b.id] = { key = b.key, dur = dur, exp = 0, icon = Nock.API.SpellIcon(b.id),
                          units = b.units or PLAYER_ONLY, aura = b.aura or b.id }
    self._order[i] = b.id
  end
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

-- The pet face: in combat only (out of combat the pet frame says it), while
-- the pet is out and not Happy. C_PetInfo.GetPetHappiness is plain on
-- Forever (probed 2026-09-23); a secret answer draws nothing.
function BuffLedger:PetFace(state)
  if not (state.player and state.player.inCombat) then return nil end
  local P = Nock.Flavor.Plain
  if P(_G.UnitExists and UnitExists("pet")) ~= true then return nil end
  local PI = _G.C_PetInfo
  if not (PI and PI.GetPetHappiness) then return nil end
  local h = P(PI.GetPetHappiness())
  if type(h) ~= "number" then return nil end
  return HAPPINESS_COORD[h]
end

-- A cast starts the buff from its learned duration; without one there is
-- nothing to show until the cache has read the aura once out of combat.
function BuffLedger:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID)
  if unit ~= "player" or type(spellID) ~= "number" then return end
  local t = self._track[baseSpell(spellID)]
  if not t then return end
  if t.dur then t.exp = GetTime() + t.dur end
end

local function learn(self, id, t, duration)
  if type(duration) ~= "number" or duration <= 0 then return end
  t.dur = duration
  local mem = remembered()
  if mem then mem[id] = duration end
end

function BuffLedger:Refresh(state)
  local now = GetTime()
  if not Nock.Restricted("auras") then
    local AC = Nock.AuraCache
    if AC then
      for _, id in ipairs(self._order) do
        local t = self._track[id]
        local a
        for _, unit in ipairs(t.units) do
          a = AC.BySpell(unit, t.aura)
          if a then break end
        end
        if a then
          learn(self, id, t, a.duration)
          t.exp = a.expirationTime or 0
          -- No expiry = a permanent buff (Shadowmeld): shown while the cache
          -- says it is up, without a countdown.
          t.permanent = (t.exp == 0)
        else
          t.exp, t.permanent = 0, false
        end
      end
    end
  else
    -- Permanent buffs break on the first action of a fight and cannot be
    -- re-read while auras are secret: drop them, keep the timed ones.
    for _, id in ipairs(self._order) do self._track[id].permanent = false end
  end
  -- Publish: live entries, soonest first (permanent ones last), entry tables
  -- reused (no allocation per refresh on the slow lane).
  local lb = state.ledgerBuffs
  local n = 0
  for _, id in ipairs(self._order) do
    local t = self._track[id]
    if t.permanent then
      n = n + 1
      local e = lb[n]
      if not e then e = {}; lb[n] = e end
      e.icon, e.exp, e.dur, e.coords = t.icon, 0, 0, nil
    elseif t.exp > now then
      n = n + 1
      local e = lb[n]
      if not e then e = {}; lb[n] = e end
      e.icon, e.exp, e.dur, e.coords = t.icon, t.exp, t.dur or 0, nil
      -- insertion sort on exp: walk the new entry down past later expiries
      -- (permanent entries, exp 0, are skipped so they stay at the end)
      local j = n
      while j > 1 and lb[j - 1].exp > lb[j].exp and lb[j - 1].exp > 0 do
        lb[j], lb[j - 1] = lb[j - 1], lb[j]
        j = j - 1
      end
    end
  end
  local face = self:PetFace(state)
  if face then
    n = n + 1
    local e = lb[n]
    if not e then e = {}; lb[n] = e end
    e.icon, e.exp, e.dur, e.coords = HAPPINESS_TEX, 0, 0, face
  end
  lb.n = n
end
