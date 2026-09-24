-- Forever/Auras.lua
-- The Forever `Auras` module: aspect and Hunter's Mark from own casts while
-- auras are secret, from the aura cache (the truth) while they are not.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Auras = Nock:NewModule("Auras", "AceEvent-3.0")

Auras.refreshInterval = 0.1

local aspectRec = { name = nil, spellId = nil, icon = nil, expirationTime = 0, duration = 0 }
local markRec = { name = nil, spellId = nil, icon = nil, expirationTime = 0, duration = 0,
                  remaining = 0, fromPlayer = true, sourceName = nil }

local function baseSpell(id)
  local CS = _G.C_Spell
  if CS and CS.GetBaseSpell then
    local okc, base = pcall(CS.GetBaseSpell, id)
    if okc and type(base) == "number" and base > 0 then return base end
  end
  return id
end

-- Ranks are separate spells on Forever and GetBaseSpell does not link them
-- (Cooldowns ruling, 2026-09-23), so a rank's cast and aura are matched by
-- NAME to the base id. The map fills lazily: a name the client has not
-- resolved yet is asked for again on the next lookup.
local byName, byNameDone = {}, false
local function nameMap()
  if byNameDone then return byName end
  local S, API = Nock.Spells, Nock.API
  local done = true
  local function add(id)
    local n = Nock.Flavor.Plain(API.SpellName(id))
    if type(n) == "string" then byName[n] = id else done = false end
  end
  for id in pairs(S.ASPECTS) do add(id) end
  add(S.HUNTERS_MARK)
  byNameDone = done
  return byName
end

-- A cast's spell id -> the tracked base id (an aspect or the mark), or nil.
local function resolve(spellID)
  local id = baseSpell(spellID)
  local S = Nock.Spells
  if S.ASPECTS[id] or id == S.HUNTERS_MARK then return id end
  local n = Nock.Flavor.Plain(Nock.API.SpellName(spellID))
  return type(n) == "string" and nameMap()[n] or nil
end

local function setAspect(id)
  local p = Nock.state.player
  if not id then p.aspect = nil; return end
  aspectRec.name, aspectRec.spellId, aspectRec.icon = Nock.API.SpellName(id), id, Nock.API.SpellIcon(id)
  p.aspect = aspectRec
end

local function setMark(expirationTime, duration)
  local t = Nock.state.target
  if not expirationTime then t.huntersMark = nil; return end
  local id = Nock.Spells.HUNTERS_MARK
  markRec.name, markRec.spellId, markRec.icon = Nock.API.SpellName(id), id, Nock.API.SpellIcon(id)
  markRec.expirationTime, markRec.duration = expirationTime, duration
  markRec.remaining = math.max(0, expirationTime - GetTime())
  t.huntersMark = markRec
end

function Auras:OnEnable()
  local p = Nock.state.player
  p.feign, p.dazed, p.eating, p.drinking = nil, nil, nil, nil
  p.sated, p.inLust, p.rapidFire, p.quickShots, p.drums = false, false, false, false, false
  p.canWeave = true
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
end

function Auras:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID)
  if unit ~= "player" or type(spellID) ~= "number" then return end
  local id = resolve(spellID)
  if not id then return end
  local S = Nock.Spells
  if S.ASPECTS[id] then
    setAspect(id)
  elseif id == S.HUNTERS_MARK then
    setMark(GetTime() + S.HUNTERS_MARK_DURATION, S.HUNTERS_MARK_DURATION)
  end
end

-- The mark is per target; a new target has none until it is cast (or read).
function Auras:PLAYER_TARGET_CHANGED()
  setMark(nil)
end

-- Out of combat the cache is the truth and overrides the ledger both ways.
function Auras:Refresh()
  if Nock.Restricted("auras") then return end
  local AC = Nock.AuraCache
  if not AC then return end
  local S = Nock.Spells
  local found
  for id in pairs(S.ASPECTS) do
    if AC.BySpell("player", id) then found = id; break end
  end
  -- A higher rank's aura carries its own id: find it by name.
  if not found then
    for n, id in pairs(nameMap()) do
      if id ~= S.HUNTERS_MARK and AC.ByName("player", n) then found = id; break end
    end
  end
  setAspect(found)
  local m = AC.BySpell("target", S.HUNTERS_MARK)
  if not m then
    local hmName = Nock.Flavor.Plain(Nock.API.SpellName(S.HUNTERS_MARK))
    if type(hmName) == "string" then m = AC.ByName("target", hmName) end
  end
  if m then setMark(m.expirationTime or 0, m.duration or 0) else setMark(nil) end
end
