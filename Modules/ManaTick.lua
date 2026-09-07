-- Modules/ManaTick.lua
-- Mana regen tick / five-second rule producer. Feeds UNIT_POWER_UPDATE and the
-- player's ENERGIZE / DRAIN combat-log events to Modules/ManaTickEngine.lua and
-- writes the result straight into state.player.manaTick (the engine state IS
-- the state table -- no copy). The central tick derives active/progress/frac
-- from it every frame; the three mana bars read those. Nothing here looks at
-- a display setting: the spark is each HUD's own opt-in.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ManaTick = Nock:NewModule("ManaTick", "AceEvent-3.0")

local MANA = 0   -- Enum.PowerType.Mana

local GAIN_EVENTS = {
  SPELL_ENERGIZE = true, SPELL_PERIODIC_ENERGIZE = true,
}
local DRAIN_EVENTS = {
  SPELL_DRAIN = true, SPELL_LEECH = true,
  SPELL_PERIODIC_DRAIN = true, SPELL_PERIODIC_LEECH = true,
}

function ManaTick:OnEnable()
  local E = Nock.ManaTickEngine
  local st = Nock.state.player.manaTick
  -- Seed the engine's private fields onto the shared table (State.lua only
  -- declares the published ones).
  for k, v in pairs(E.New()) do
    if st[k] == nil then st[k] = v end
  end
  self.playerGUID = UnitGUID("player")
  self:RegisterEvent("PLAYER_LOGIN")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "Reseed")
  if not (Nock.RegisterUnitEvent and Nock.RegisterUnitEvent("UNIT_POWER_UPDATE",
       function(ev, unit, kind) ManaTick:OnPower(ev, unit, kind) end, "player")) then
    self:RegisterEvent("UNIT_POWER_UPDATE", "OnPower")
  end
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

function ManaTick:PLAYER_LOGIN()
  self.playerGUID = UnitGUID("player")
  self:Reseed()
end

-- A loading screen can swallow power updates: forget the last reading so the
-- first update after it is a seed, not a phantom spend/gain.
function ManaTick:Reseed()
  self.playerGUID = self.playerGUID or UnitGUID("player")
  Nock.state.player.manaTick.lastMana = nil
end

function ManaTick:OnPower(_, unit, kind)
  if unit ~= "player" then return end
  if kind and kind ~= "MANA" then return end
  local st = Nock.state.player
  Nock.ManaTickEngine.OnPower(st.manaTick, GetTime(),
    UnitPower("player", MANA) or 0, UnitPowerMax("player", MANA) or 0,
    st.inCombat)
end

-- No power-type filter on purpose: a hunter has one power, so every self
-- energize/drain is mana. (The reference WA read the power type at argument
-- 17, which is right for ENERGIZE but is the extra-amount slot for DRAIN --
-- it matched by accident. Nothing here to get wrong.)
function ManaTick:COMBAT_LOG_EVENT_UNFILTERED()
  local _, subevent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
  if destGUID ~= self.playerGUID then return end
  if GAIN_EVENTS[subevent] then
    Nock.ManaTickEngine.OnEnergize(Nock.state.player.manaTick, GetTime())
  elseif DRAIN_EVENTS[subevent] then
    Nock.ManaTickEngine.OnDrain(Nock.state.player.manaTick, GetTime())
  end
end
