-- Forever/CastBar.lua
-- The Forever `CastBar` module: own casts and channels are plain on Forever,
-- so state.player.casting comes straight from UnitCastingInfo/UnitChannelInfo;
-- the Auto Shot wind-up (spell 75) goes to state.player.autoShotCast.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local CastBar = Nock:NewModule("CastBar", "AceEvent-3.0")

-- One record, reused: consumers compare identity (Nock.CastBarSource), and a
-- fresh table per event would be a per-cast allocation for nothing.
local rec = { name = nil, spellId = nil, icon = nil, startTime = 0, endTime = 0, isChannel = false }

-- castGUID of a cast raised from spell data (see publishFromSpell), else nil.
local fallbackGUID

-- The Auto Shot wind-up, kept OUT of `casting` (project rule: that field means
-- "the player cannot act", and the wind-up is the opposite, the free queue
-- window). Views merge the two through Nock.CastBarSource. One record, reused.
local autoRec = { name = nil, spellId = nil, icon = nil, startTime = 0, endTime = 0, isChannel = false, auto = true }
-- true while a client cast edge (publishAutoShot) owns the record; the model
-- in Refresh stays out of its way. Never seen on build 70425, kept for a
-- later one. Declared HERE, above every writer (project rule: a local
-- declared below its writer makes the write a global).
local eventActive = false

local function isAutoShot(spellID)
  local P = Nock.Flavor and Nock.Flavor.Plain or function(v) return v end
  return P(spellID) == Nock.Spells.AUTO_SHOT
end

-- The client's own window when UnitCastingInfo reports the wind-up, else the
-- predicted release (Nock.AutoShotWindupEnd: the one definition, shared with
-- the TBC module, with its stale-grid floor).
local function publishAutoShot()
  local now = GetTime()
  local name, _, icon, startMs, endMs, _, _, _, spellId = UnitCastingInfo("player")
  local P = Nock.Flavor and Nock.Flavor.Plain or function(v) return v end
  startMs, endMs, spellId = P(startMs), P(endMs), P(spellId)
  local fromClient = name and spellId == Nock.Spells.AUTO_SHOT
                     and type(startMs) == "number" and type(endMs) == "number" and endMs > startMs
  if fromClient then
    autoRec.name, autoRec.icon = name, icon
    autoRec.startTime, autoRec.endTime = startMs / 1000, endMs / 1000
  else
    local sName, sIcon
    if Nock.API and Nock.API.SpellInfo then sName, sIcon = Nock.API.SpellInfo(Nock.Spells.AUTO_SHOT) end
    autoRec.name, autoRec.icon = P(sName) or "Auto Shot", sIcon
    local r = Nock.state.ranged
    local release = (r.swingStart > 0 and r.swingDuration > 0) and (r.swingStart + r.swingDuration) or nil
    local w = Nock.AutoShotWindup and Nock.AutoShotWindup() or 0
    if not w or w <= 0 then w = 0.5 end
    autoRec.startTime, autoRec.endTime = now, Nock.AutoShotWindupEnd(release, now, w)
  end
  autoRec.spellId = Nock.Spells.AUTO_SHOT
  eventActive = true
  Nock.state.player.autoShotCast = autoRec
end

local function clearAutoShot()
  eventActive = false
  if Nock.state.player.autoShotCast == autoRec then Nock.state.player.autoShotCast = nil end
end

-- The MODELLED wind-up (the client raises no event for it; the stop-gated
-- reads in Forever/SwingTimer measure W). Standing still it runs from
-- (due - W) to the due mark; after a stop made inside that window, or past
-- the due mark, it runs from the stop for W (the bow cannot wind up on the
-- move, so nothing is drawn while moving). Published only once W is
-- measured, only while the auto swing is live, and dropped half a second
-- past its end when the shot has not come (a delayed shot, a dead-zone
-- target). Writes rec.startTime / rec.endTime; returns whether to show.
function CastBar.ModelWindup(state, now, rec)
  local r = state.ranged
  if not r.windupMeasured then return false end
  local W = r.windup
  if not W or W <= 0 then return false end
  if state.context.moving then return false end
  if not Nock.AutoSwingLive() then return false end
  local due = r.swingStart + r.swingDuration
  local start = due - W
  local stoppedAt = state.context.stoppedAt
  if stoppedAt and stoppedAt > start and stoppedAt >= r.swingStart then start = stoppedAt end
  if now < start then return false end
  local endT = start + W
  if now > endT + 0.5 then return false end
  rec.startTime, rec.endTime = start, endT
  return true
end

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
  Nock.state.player.autoShotCast = nil
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
function CastBar:OnCastFailed(event, unit, castGUID, spellID)
  if unit ~= "player" then return end
  -- The wind-up: SUCCEEDED(75) is the release and clears it. FAILED(75) is
  -- NOT trusted (a refused re-press of !Auto Shot inside the wind-up logs one
  -- while the real wind-up keeps running); a cancelled wind-up is torn down by
  -- Refresh's stale net or by its STOP/INTERRUPTED.
  if isAutoShot(spellID) then
    if event == "UNIT_SPELLCAST_SUCCEEDED" then clearAutoShot() end
    return
  end
  if not fallbackGUID then return end
  if fallbackGUID ~= true and castGUID ~= fallbackGUID then return end
  fallbackGUID = nil
  clear()
end

function CastBar:OnCastStart(event, unit, castGUID, spellID)
  if unit ~= "player" then return end
  if isAutoShot(spellID) then publishAutoShot(); return end
  if publishCast() then return end
  -- DELAYED on a spell-data bar has nothing to resync from: keep it.
  if event == "UNIT_SPELLCAST_DELAYED" and fallbackGUID and Nock.state.player.casting == rec then return end
  if not publishFromSpell(castGUID, spellID) then clear() end
end

function CastBar:OnChannelStart(event, unit)
  if unit ~= "player" then return end
  if not publishChannel() then clear() end
end

function CastBar:OnCastEnd(event, unit, castGUID, spellID)
  if unit ~= "player" then return end
  if isAutoShot(spellID) then clearAutoShot(); return end
  -- A STOP for a failed re-press can arrive while the real cast still runs:
  -- keep the record while the client still reports a cast or channel.
  if UnitCastingInfo("player") or UnitChannelInfo("player") then return end
  -- A spell-data bar has no client record to consult: only its own cast ends it.
  if fallbackGUID and fallbackGUID ~= true and castGUID and castGUID ~= fallbackGUID then return end
  fallbackGUID = nil
  clear()
end

-- Central tick. An event-owned record gets the TBC safety net: pinned to the
-- live release while the grid moves under it (Nock.AutoShotCastEnd, the
-- shared definition) and dropped once well past its end. Otherwise the
-- modelled wind-up is published and withdrawn from here, every frame.
function CastBar:Refresh(state)
  local now = GetTime()
  local a = state.player.autoShotCast
  if eventActive then
    if a ~= autoRec then eventActive = false return end
    local r = state.ranged
    if r.swingStart > 0 and r.swingDuration > 0 then
      a.endTime = Nock.AutoShotCastEnd(a.endTime, a.startTime, r.swingStart + r.swingDuration, now, r.windup)
    end
    if now > a.endTime + 0.5 then clearAutoShot() end
    return
  end
  if a ~= nil and a ~= autoRec then return end   -- another producer (the practice sim) owns the field
  if CastBar.ModelWindup(state, now, autoRec) then
    if a ~= autoRec then
      local P = Nock.Flavor and Nock.Flavor.Plain or function(v) return v end
      local sName, sIcon
      if Nock.API and Nock.API.SpellInfo then sName, sIcon = Nock.API.SpellInfo(Nock.Spells.AUTO_SHOT) end
      autoRec.name, autoRec.icon, autoRec.spellId = P(sName) or "Auto Shot", sIcon, Nock.Spells.AUTO_SHOT
      state.player.autoShotCast = autoRec
    end
  elseif a == autoRec then
    state.player.autoShotCast = nil
  end
end
