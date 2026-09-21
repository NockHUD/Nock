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

function BuffLedger:OnEnable()
  self._track, self._order = {}, {}
  local mem = remembered()
  for i, b in ipairs(Nock.Spells.BUFFS) do
    local dur = (mem and mem[b.id]) or b.dur
    self._track[b.id] = { key = b.key, dur = dur, exp = 0, icon = Nock.API.SpellIcon(b.id) }
    self._order[i] = b.id
  end
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
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
        local a = AC.BySpell("player", id)
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
      e.icon, e.exp, e.dur = t.icon, 0, 0
    elseif t.exp > now then
      n = n + 1
      local e = lb[n]
      if not e then e = {}; lb[n] = e end
      e.icon, e.exp, e.dur = t.icon, t.exp, t.dur or 0
      -- insertion sort on exp: walk the new entry down past later expiries
      -- (permanent entries, exp 0, are skipped so they stay at the end)
      local j = n
      while j > 1 and lb[j - 1].exp > lb[j].exp and lb[j - 1].exp > 0 do
        lb[j], lb[j - 1] = lb[j - 1], lb[j]
        j = j - 1
      end
    end
  end
  lb.n = n
end
