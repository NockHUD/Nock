-- Forever/ManaTick.lua
-- The Forever `ManaTick` module: mana is secret, so a power event is
-- classified by TIMING -- a spend when one of our own casts landed just
-- before it, a regen tick otherwise -- and fed to the pure engine.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ManaTick = Nock:NewModule("ManaTick", "AceEvent-3.0")

-- A power event this soon after an own cast is that cast's cost.
local SPEND_WINDOW = 0.25

function ManaTick:OnEnable()
  local E = Nock.ManaTickEngine
  local st = Nock.state.player.manaTick
  for k, v in pairs(E.New()) do
    if st[k] == nil then st[k] = v end
  end
  self._lastCastAt = nil
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "Reseed")
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  if not (Nock.RegisterUnitEvent and Nock.RegisterUnitEvent("UNIT_POWER_UPDATE",
       function(ev, unit, kind) ManaTick:OnPower(ev, unit, kind) end, "player")) then
    self:RegisterEvent("UNIT_POWER_UPDATE", "OnPower")
  end
end

function ManaTick:Reseed()
  local st = Nock.state.player.manaTick
  st.mode, st.start, st.expire, st.lastTick, st.fsrEnd = nil, 0, 0, nil, nil
  self._lastCastAt = nil
end

-- Every hunter spell but Auto Shot costs mana; the stamp marks the spend.
function ManaTick:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID)
  if unit ~= "player" then return end
  if spellID == Nock.Spells.AUTO_SHOT then return end
  self._lastCastAt = GetTime()
end

function ManaTick:OnPower(_, unit, kind)
  if unit ~= "player" then return end
  if kind and kind ~= "MANA" then return end
  local now = GetTime()
  local st = Nock.state.player
  local E = Nock.ManaTickEngine
  local castAt = self._lastCastAt
  if castAt and (now - castAt) <= SPEND_WINDOW then
    self._lastCastAt = nil
    E.OnSpend(st.manaTick, now, st.inCombat)
  else
    E.OnGain(st.manaTick, now, st.inCombat)
  end
end
