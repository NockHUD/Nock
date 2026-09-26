-- Forever/CastBar.lua
-- The Forever `CastBar` module: own casts and channels are plain on Forever,
-- so state.player.casting comes straight from UnitCastingInfo/UnitChannelInfo.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local CastBar = Nock:NewModule("CastBar", "AceEvent-3.0")

-- One record, reused: consumers compare identity (Nock.CastBarSource), and a
-- fresh table per event would be a per-cast allocation for nothing.
local rec = { name = nil, spellId = nil, icon = nil, startTime = 0, endTime = 0, isChannel = false }

-- castGUID of a cast raised from spell data (see publishFromSpell), else nil.
local fallbackGUID

local function publishCast()
  local name, _, icon, startMs, endMs, _, _, _, spellId = UnitCastingInfo("player")
  if not name or spellId == Nock.Spells.AUTO_SHOT then return false end
  rec.name, rec.spellId, rec.icon = name, spellId, icon
  rec.startTime, rec.endTime, rec.isChannel = (startMs or 0) / 1000, (endMs or 0) / 1000, false
  fallbackGUID = nil
  Nock.state.player.casting = rec
  return true
end

-- Ranged shots with a cast (Multi-Shot) never enter UnitCastingInfo and fire
-- no UNIT_SPELLCAST_START here (probed 2026-09-24: only SUCCEEDED), so the bar
-- is raised on the press (SENT) and runs the spell's own cast time.
local function publishFromSpell(castGUID, spellID)
  local P = Nock.Flavor and Nock.Flavor.Plain or function(v) return v end
  spellID = P(spellID)
  if not spellID or spellID == Nock.Spells.AUTO_SHOT or not (Nock.API and Nock.API.SpellInfo) then return false end
  local name, icon, castTime = Nock.API.SpellInfo(spellID)
  castTime = P(castTime)
  if type(castTime) ~= "number" or castTime <= 0 then return false end
  local now = GetTime()
  rec.name, rec.spellId, rec.icon = name, spellID, icon
  rec.startTime, rec.endTime, rec.isChannel = now, now + castTime / 1000, false
  fallbackGUID = castGUID or true
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
  self:RegisterEvent("UNIT_SPELLCAST_SENT", "OnCastSent")
  self:RegisterEvent("UNIT_SPELLCAST_FAILED", "OnCastFailed")
  self:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET", "OnCastFailed")
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnCastFailed")
  -- Hide Blizzard's cast bar (hideBlizzardCastBar, shared with TBC).
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyBlizzardCastBarVisibility")
  self:ApplyBlizzardCastBarVisibility()
end

function CastBar:ApplyBlizzardCastBarVisibility()
  local p = Nock.db and Nock.db.profile
  if not Nock.UI.SetBlizzardCastBarHidden(p and p.hideBlizzardCastBar == true) then
    Nock:Print("Couldn't re-enable the Blizzard cast bar live — /reload to restore it.")
  end
end

-- A spell-data bar has no client record and no STOP of its own. Its own
-- SUCCEEDED is the release (probed 2026-09-24: SENT -> SUCCEEDED 0.503 s for
-- Multi-Shot) and ends it; the timer is the backstop for a lost event.
local function expireLater(guid, delay)
  if not (C_Timer and C_Timer.After) then return end
  C_Timer.After(delay, function()
    if fallbackGUID == guid and Nock.state.player.casting == rec and GetTime() >= rec.endTime then
      fallbackGUID = nil
      clear()
    end
  end)
end

function CastBar:OnCastSent(event, unit, target, castGUID, spellID)
  if unit ~= "player" then return end
  if UnitCastingInfo("player") or UnitChannelInfo("player") then return end
  -- Instants raise nothing and must not end a bar already running.
  if publishFromSpell(castGUID, spellID) then
    expireLater(fallbackGUID, rec.endTime - rec.startTime + 0.05)
  end
end

-- FAILED / FAILED_QUIET / SUCCEEDED of the spell-data cast: the bar is done.
function CastBar:OnCastFailed(event, unit, castGUID)
  if unit ~= "player" or not fallbackGUID then return end
  if fallbackGUID ~= true and castGUID ~= fallbackGUID then return end
  fallbackGUID = nil
  clear()
end

function CastBar:OnCastStart(event, unit, castGUID, spellID)
  if unit ~= "player" then return end
  if publishCast() then return end
  -- DELAYED on a spell-data bar has nothing to resync from: keep it.
  if event == "UNIT_SPELLCAST_DELAYED" and fallbackGUID and Nock.state.player.casting == rec then return end
  if not publishFromSpell(castGUID, spellID) then clear() end
end

function CastBar:OnChannelStart(event, unit)
  if unit ~= "player" then return end
  if not publishChannel() then clear() end
end

function CastBar:OnCastEnd(event, unit, castGUID)
  if unit ~= "player" then return end
  -- A STOP for a failed re-press can arrive while the real cast still runs:
  -- keep the record while the client still reports a cast or channel.
  if UnitCastingInfo("player") or UnitChannelInfo("player") then return end
  -- A spell-data bar has no client record to consult: only its own cast ends it.
  if fallbackGUID and fallbackGUID ~= true and castGUID and castGUID ~= fallbackGUID then return end
  fallbackGUID = nil
  clear()
end
