-- Forever/CastBar.lua
-- The Forever `CastBar` module: own casts and channels are plain on Forever,
-- so state.player.casting comes straight from UnitCastingInfo/UnitChannelInfo.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local CastBar = Nock:NewModule("CastBar", "AceEvent-3.0")

-- One record, reused: consumers compare identity (Nock.CastBarSource), and a
-- fresh table per event would be a per-cast allocation for nothing.
local rec = { name = nil, spellId = nil, icon = nil, startTime = 0, endTime = 0, isChannel = false }

local function publishCast()
  local name, _, icon, startMs, endMs, _, _, _, spellId = UnitCastingInfo("player")
  if not name or spellId == Nock.Spells.AUTO_SHOT then return false end
  rec.name, rec.spellId, rec.icon = name, spellId, icon
  rec.startTime, rec.endTime, rec.isChannel = (startMs or 0) / 1000, (endMs or 0) / 1000, false
  Nock.state.player.casting = rec
  return true
end

local function publishChannel()
  local name, _, icon, startMs, endMs, _, _, spellId = UnitChannelInfo("player")
  if not name then return false end
  rec.name, rec.spellId, rec.icon = name, spellId, icon
  rec.startTime, rec.endTime, rec.isChannel = (startMs or 0) / 1000, (endMs or 0) / 1000, true
  Nock.state.player.casting = rec
  return true
end

local function clear()
  if Nock.state.player.casting == rec then Nock.state.player.casting = nil end
end

function CastBar:OnEnable()
  Nock.state.player.autoShotCast = nil   -- no wind-up feed on Forever
  self:RegisterEvent("UNIT_SPELLCAST_START", "OnCastStart")
  self:RegisterEvent("UNIT_SPELLCAST_DELAYED", "OnCastStart")
  self:RegisterEvent("UNIT_SPELLCAST_STOP", "OnCastEnd")
  self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnCastEnd")
  self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "OnChannelStart")
  self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "OnChannelStart")
  self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnCastEnd")
end

function CastBar:OnCastStart(event, unit)
  if unit ~= "player" then return end
  if not publishCast() then clear() end
end

function CastBar:OnChannelStart(event, unit)
  if unit ~= "player" then return end
  if not publishChannel() then clear() end
end

function CastBar:OnCastEnd(event, unit)
  if unit ~= "player" then return end
  -- A STOP for a failed re-press can arrive while the real cast still runs:
  -- keep the record while the client still reports a cast or channel.
  if UnitCastingInfo("player") or UnitChannelInfo("player") then return end
  clear()
end
