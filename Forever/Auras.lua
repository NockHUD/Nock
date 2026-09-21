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
  local id = baseSpell(spellID)
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
  local found
  for id in pairs(Nock.Spells.ASPECTS) do
    if AC.BySpell("player", id) then found = id; break end
  end
  setAspect(found)
  local m = AC.BySpell("target", Nock.Spells.HUNTERS_MARK)
  if m then setMark(m.expirationTime or 0, m.duration or 0) else setMark(nil) end
end
