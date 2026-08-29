-- Modules/RipperWatch.lua
-- Watches the player's own casts for the Dimensional Ripper - Area 52 (item
-- 30542) and the Ultrasafe Transporter: Toshley's Station (item 30544), drives
-- the pure engine (Modules/RipperEngine.lua) and publishes state.ripper for
-- the centre-screen countdown (UI/Frame_RipperCountdown.lua).
--
-- The trick (user, 2026-08-27): both trinkets are a long teleport cast with a
-- side effect, some of them beneficial. Closing the client (ALT F4) about a
-- second BEFORE the cast ends keeps the side effect and skips the trip. Nock
-- only counts — it never closes anything.
--
-- The match is by the item's own use effect (GetItemSpell — name or id, the
-- Sulfuron Slammer's pattern), with the Wowhead spell ids as fallbacks for a
-- cold item cache. The cast's span is UnitCastingInfo's, so the deadline is
-- the server's end minus the lead, whatever haste or pushback did to it.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local RipperWatch = Nock:NewModule("RipperWatch", "AceEvent-3.0", "AceConsole-3.0")
local C = Nock.Constants
local E = Nock.RipperEngine

local FALLBACK_SPELLS = {
  [C.RIPPER_ITEMS[1]] = C.SpellID.RIPPER_AREA52,
  [C.RIPPER_ITEMS[2]] = C.SpellID.TRANSPORTER_TOSHLEY,
}

local _preview           -- /nock ripper test: { itemId } while a fake cast runs
local _itemSpell = {}    -- itemId -> { name, id } once the item cache answers

-- Master gate: the warnings system, then this warning.
local function enabled()
  local p = Nock.db and Nock.db.profile
  if not p then return false end
  if p.showWarnings == false then return false end
  return p.warnRipperEnabled ~= false
end

local function lead()
  local p = Nock.db and Nock.db.profile
  local v = p and tonumber(p.ripperLead)
  return v or E.DEFAULT.lead
end

-- Same media-library rule as the Slammer's cues: a configured sound resolves
-- through LSM; "None" (the default here) is a mute; a pick that no library
-- has falls back to the raid-warning kit so the choice is never silent.
local KIT_IDS = { RAID_WARNING = 8959 }
local function playCue()
  local p = Nock.db and Nock.db.profile
  local name = p and p.warnRipperSound
  if not name or name == "" or name == "None" then return end
  local LSM = LibStub("LibSharedMedia-3.0", true)
  local path = LSM and LSM:Fetch("sound", name, true) or nil
  if path and PlaySoundFile then
    PlaySoundFile(path, "Master")
    return
  end
  local kit = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or KIT_IDS.RAID_WARNING
  if PlaySound and kit then PlaySound(kit, "Master") end
end

-- The item's use effect, lazily: the item cache is routinely cold at load and
-- a nil simply means "ask again next cast".
local function itemSpell(itemId)
  local s = _itemSpell[itemId]
  if s then return s.name, s.id end
  local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
  if not fn then return nil end
  local ok, name, id = pcall(fn, itemId)
  if ok and name then
    _itemSpell[itemId] = { name = name, id = tonumber(id) }
    return name, tonumber(id)
  end
  return nil
end

-- Which of the two trinkets a cast belongs to, or nil.
local function itemOf(spellId, spellName)
  for i = 1, #C.RIPPER_ITEMS do
    local itemId = C.RIPPER_ITEMS[i]
    if spellId and spellId == FALLBACK_SPELLS[itemId] then return itemId end
    local name, id = itemSpell(itemId)
    if id and spellId == id then return itemId end
    if name and spellName == name then return itemId end
  end
  return nil
end

local function itemIcon(itemId)
  if C_Item and C_Item.GetItemIconByID then
    local i = C_Item.GetItemIconByID(itemId)
    if i then return i end
  end
  if GetItemInfo then
    local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
    if icon then return icon end
  end
  return nil
end

function RipperWatch:OnInitialize()
  self.st = E.New()
end

function RipperWatch:OnEnable()
  self:RegisterEvent("UNIT_SPELLCAST_START",       "OnCastStart")
  self:RegisterEvent("UNIT_SPELLCAST_DELAYED",     "OnCastDelayed")
  self:RegisterEvent("UNIT_SPELLCAST_STOP",        "OnCastEnd")
  self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnCastEnd")
  self:RegisterEvent("UNIT_SPELLCAST_FAILED",      "OnCastEnd")
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED",   "OnCastEnd")
  self:RegisterEvent("PLAYER_ENTERING_WORLD",      "OnEnteringWorld")
end

-- What is in flight right now, if it is one of ours: itemId, start, end (s).
local function currentCast()
  if not UnitCastingInfo then return nil end
  local name, _, _, startTime, endTime, _, _, _, spellId = UnitCastingInfo("player")
  if not name then return nil end
  local itemId = itemOf(spellId, name)
  if not itemId then return nil end
  return itemId, startTime / 1000, endTime / 1000
end

function RipperWatch:Begin(itemId, startTime, endTime)
  E.Begin(self.st, startTime, endTime, lead())
  local r = Nock.state.ripper
  r.itemId = itemId
  r.icon   = itemIcon(itemId)
end

function RipperWatch:Clear()
  E.End(self.st)
  local r = Nock.state.ripper
  r.itemId, r.icon = nil, nil
end

function RipperWatch:OnCastStart(event, unit)
  if unit ~= "player" then return end
  if _preview then return end
  local itemId, s, e = currentCast()
  if not itemId then return end
  self:Begin(itemId, s, e)
end

function RipperWatch:OnCastDelayed(event, unit)
  if unit ~= "player" or _preview then return end
  if not E.Active(self.st) then return end
  local itemId, s, e = currentCast()
  if itemId then E.Retime(self.st, s, e) end
end

-- STOP / INTERRUPTED / FAILED / SUCCEEDED all land here. The event's spell
-- args vary by client, so the question is asked of UnitCastingInfo instead:
-- if our cast is no longer the one in flight, it is over.
function RipperWatch:OnCastEnd(event, unit)
  if unit ~= "player" or _preview then return end
  if not E.Active(self.st) then return end
  if currentCast() then return end
  self:Clear()
end

function RipperWatch:OnEnteringWorld()
  -- A loading screen mid-cast (the teleport landing) ends everything.
  if _preview then _preview = nil end
  self:Clear()
  self:Publish(GetTime())
end

-- Publish the countdown every rendered frame: the view reads state.ripper
-- and the numerals change once a second, so this is one Describe per tick.
function RipperWatch:Publish(now)
  local r = Nock.state.ripper
  local st = self.st
  if not E.Active(st) then
    if r.active then
      r.active, r.label, r.go, r.remaining, r.frac, r.preview = false, nil, false, 0, 0, false
    end
    return
  end
  -- A preview's fake cast ends on its own clock.
  if _preview and now >= st.endTime then
    self:Preview(false)
    return
  end
  E.Describe(st, now, r)
  r.active  = true
  r.preview = _preview ~= nil
  if E.TakeGo(st) and enabled() then playCue() end
end

function RipperWatch:Refresh(state)
  self:Publish(GetTime())
end

-- /nock ripper test [secs]: a fake cast for placing the text and hearing the
-- cue. Off ends it early.
function RipperWatch:Preview(on, secs)
  local p = Nock.db and Nock.db.profile
  if on then
    if p and p.showWarnings == false then
      self:Print("Warnings are switched off entirely — turn on 'Enable warnings' to see this.")
      return
    end
    if p and p.warnRipperEnabled == false then
      self:Print("The Ripper countdown is switched off — turn it on under Warnings → You.")
      return
    end
    local dur = tonumber(secs) or 10
    if dur < 2 then dur = 2 elseif dur > 60 then dur = 60 end
    local now = GetTime()
    _preview = { itemId = C.RIPPER_ITEMS[1] }
    self:Begin(C.RIPPER_ITEMS[1], now, now + dur)
    self:Print(("Ripper preview: a %g s cast, ALT F4 at %g s. /nock ripper off ends it."):format(dur, dur - lead()))
  else
    _preview = nil
    self:Clear()
    self:Publish(GetTime())
  end
end

-- /nock ripper: what the watcher resolved, in a copybox (the in-game gate).
function RipperWatch:Dump()
  local lines = { "Nock ripper countdown" }
  lines[#lines + 1] = ("enabled: %s  lead: %g s  sound: %s"):format(
    tostring(enabled()), lead(), tostring(Nock.db and Nock.db.profile and Nock.db.profile.warnRipperSound))
  for i = 1, #C.RIPPER_ITEMS do
    local itemId = C.RIPPER_ITEMS[i]
    local name, id = itemSpell(itemId)
    local iname = GetItemInfo and GetItemInfo(itemId) or nil
    lines[#lines + 1] = ("item %d (%s): use effect %s / %s, fallback spell %d, owned %s"):format(
      itemId, tostring(iname), tostring(name), tostring(id), FALLBACK_SPELLS[itemId],
      tostring(GetItemCount and GetItemCount(itemId) or "?"))
  end
  local r = Nock.state.ripper
  lines[#lines + 1] = ("active: %s  label: %s  remaining: %.2f  preview: %s"):format(
    tostring(r.active), tostring(r.label), r.remaining or 0, tostring(r.preview))
  if UnitCastingInfo then
    local name, _, _, s, e, _, _, _, spellId = UnitCastingInfo("player")
    lines[#lines + 1] = name and ("casting now: %s (%s) %.2f -> %.2f"):format(name, tostring(spellId), s / 1000, e / 1000)
                        or "casting now: nothing"
  end
  local text = table.concat(lines, "\n")
  if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else self:Print(text) end
end
