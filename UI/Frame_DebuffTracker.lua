-- UI/Frame_DebuffTracker.lua
-- Bare, draggable target-debuff grid. No header, no padding — just an icon
-- grid whose cells overlap by 1px so their black borders merge into single
-- shared grid lines (Bartender-style rows/cols, sized via cols + icon size).
-- Present debuffs show in colour with a cooldown swipe + stack count; missing
-- ones are desaturated + run the shared "missing" highlight. Mirrors
-- UI/Frame_BuffTracker.lua, trimmed for one panel of target debuffs.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local DebuffTrackerView = Nock:NewModule("DebuffTrackerView", "AceEvent-3.0")
local C = Nock.Constants

local MAX_SLOTS    = 40
local CELL_OVERLAP = 1   -- merge adjacent 1px borders into one shared line
local SOLID_TEX    = "Interface\\Buttons\\WHITE8X8"

local function profileGet(key, fallback)
  local p = Nock.db and Nock.db.profile
  if p and p[key] ~= nil then return p[key] end
  return fallback
end

local function isEnabled()  return profileGet("debuffTrackerEnabled", true) and true or false end
local function isRaidOnly() return profileGet("debuffTrackerRaidOnly", false) and true or false end
local function isLocked()   return Nock.IsLocked() end
local function cols()       return profileGet("debuffTrackerCols", 8) end
local function iconSize()   return profileGet("debuffTrackerIconSize", 26) end
local function position()
  return profileGet("debuffTrackerPosition", { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 })
end

-- Show now during testing; later the raid gate (debuffTrackerRaidOnly default
-- true) restricts it to actual raids.
local function inRaid()
  if IsInRaid and IsInRaid() then return true end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return true end
  return false
end

-- Click a MISSING debuff icon → ping RAID chat (raid only). Throttled per
-- debuff so a double-click can't spam. Not in a raid → quiet local note so the
-- click isn't a silent no-op.
local _lastAnnounce = {}
local function announceMissingDebuff(label)
  if not label then return end
  if not inRaid() then
    Nock:Print(("%s is missing — raid announce only (you're not in a raid)."):format(label))
    return
  end
  local now = GetTime()
  if _lastAnnounce[label] and (now - _lastAnnounce[label]) < 3 then return end
  _lastAnnounce[label] = now
  local tgt = (UnitName and UnitName("target")) or "the boss"
  if SendChatMessage then
    SendChatMessage(("%s is MISSING on %s - please apply."):format(label, tgt), "RAID")
  end
end

-- Shared "pay attention" visual (same as BuffTracker missing buffs).
local function setMissingHighlight(slot, on)
  Nock.UI.SetIconNextHighlight(slot, on, nil, 1)
end

-- Always a thin 1px black border regardless of the global LSM iconBorder.
local function applyMinimalBorder(slot)
  slot:SetBackdrop({
    bgFile   = SOLID_TEX,
    edgeFile = SOLID_TEX,
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  slot:SetBackdropColor(0, 0, 0, 0.85)
  slot:SetBackdropBorderColor(0, 0, 0, 1)
  if slot.icon then
    slot.icon:ClearAllPoints()
    slot.icon:SetPoint("TOPLEFT",     slot, "TOPLEFT",      1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1,  1)
  end
end

function DebuffTrackerView:OnInitialize()
  local panel = CreateFrame("Frame", "NockDebuffs", UIParent, "BackdropTemplate")
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    Nock.db.profile.debuffTrackerPosition = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  Nock.UI.RegisterNudgeable(panel, {
    label   = "Debuff Tracker",
    get     = function() return Nock.db.profile.debuffTrackerPosition end,
    set     = function(pos)
      Nock.db.profile.debuffTrackerPosition = pos
      DebuffTrackerView:ApplyPosition()
    end,
    default = function() return Nock.Defaults.profile.debuffTrackerPosition end,
  })
  -- Backdrop DEFAULTS to invisible when locked ("just icons") — the Background
  -- styling block (debuffTracker* keys) can turn it on. When unlocked a
  -- coloured outline always appears so the otherwise-bare grid can be found
  -- and dragged.
  Nock.UI.ApplyUserPanelStyle(panel, "debuffTracker")
  panel:Hide()

  local slots = {}
  for i = 1, MAX_SLOTS do
    local slot = Nock.UI.CreateIconSlot(panel, "NockDebuffSlot" .. i, iconSize())
    applyMinimalBorder(slot)
    slot:Hide()
    slot._lastIcon    = nil
    slot._lastCdStart = 0
    slot._lastCdDur   = 0
    slot._lastCount   = ""
    slot._lastPresent = nil
    slot._present     = false
    slot._label       = nil
    -- Mouse is enabled only while LOCKED (see ApplyLock) so dragging the grid
    -- still works when unlocked. Click a MISSING icon → raid announce.
    slot:SetScript("OnMouseUp", function(s, button)
      if button ~= "LeftButton" then return end
      if s._present then return end       -- it's up; nothing to announce
      announceMissingDebuff(s._label)
    end)
    slots[i] = slot
  end

  self.panel = panel
  self.slots = slots

  self:ApplyPosition()
  self:ApplyLock()

  self:RegisterMessage("NOCK_VISUALS_CHANGED",        "OnVisualsChanged")
  self:RegisterMessage("NOCK_LOCK_CHANGED",           "ApplyLock")
  self:RegisterMessage("NOCK_DEBUFFTRACKER_POSRESET", "ApplyPosition")
  self:RegisterMessage("NOCK_POSITION_RESET",         "ApplyPosition")  -- profile switch
end

function DebuffTrackerView:ApplyPosition()
  local p = position()
  self.panel:ClearAllPoints()
  self.panel:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
end

function DebuffTrackerView:ApplyLock()
  local locked = isLocked()
  -- Panel mouse drives dragging (unlocked only); slot mouse drives the
  -- click-to-announce (locked only) so the two never fight.
  self.panel:EnableMouse(not locked)
  if self.slots then
    for _, s in ipairs(self.slots) do s:EnableMouse(locked) end
  end
  self:ApplyStyle()
end

-- User Background block (debuffTracker* keys — default fully transparent);
-- the green unlock border wins while the grid is draggable.
function DebuffTrackerView:ApplyStyle()
  Nock.UI.ApplyUserPanelStyle(self.panel, "debuffTracker")
  if not isLocked() then
    self.panel:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  end
end

function DebuffTrackerView:OnVisualsChanged()
  local sz = iconSize()
  for _, slot in ipairs(self.slots) do
    slot:SetSize(sz, sz)
    applyMinimalBorder(slot)
  end
  self:ApplyLock()
end

-- Slow lane (Core:Tick): a target-debuff icon grid — nothing animates, the
-- icons only change as debuffs land or drop. Matches DebuffTracker's engine
-- cadence, same as the BuffTracker pair.
DebuffTrackerView.refreshInterval = 0.1

function DebuffTrackerView:Refresh(state)
  -- demo: the onboarding wizard previews this grid with no target and outside a
  -- raid. The engine already emits the full catalog (every entry missing), so
  -- only the context gates need lifting — the icons render desaturated, which
  -- is exactly what "nothing applied yet" looks like in play.
  local demo      = state.demo.debuffTracker
  local hasTarget = UnitExists and UnitExists("target")
  local gated = not isEnabled()
             or (not hasTarget and not demo)
             or (isRaidOnly() and not inRaid() and not demo)
  local list  = state.debufftracker or {}
  if gated or #list == 0 then
    if self.panel:IsShown() then
      for _, s in ipairs(self.slots) do
        if s:IsShown() then
          setMissingHighlight(s, false)
          s._lastPresent = nil   -- force full re-eval (desat + glow) on re-show
          s:Hide()
        end
      end
      self.panel:Hide()
    end
    return
  end

  local colCount = math.max(1, cols())
  local sz       = iconSize()
  local n        = math.min(#list, MAX_SLOTS)
  local rows     = math.ceil(n / colCount)
  local stride   = sz - CELL_OVERLAP

  self.panel:SetSize(
    colCount * sz - (colCount - 1) * CELL_OVERLAP,
    rows * sz - (rows - 1) * CELL_OVERLAP
  )

  local now = GetTime()
  for i = 1, MAX_SLOTS do
    local slot = self.slots[i]
    local d    = list[i]
    if i <= n and d then
      local col = (i - 1) % colCount
      local row = math.floor((i - 1) / colCount)
      slot:ClearAllPoints()
      slot:SetPoint("TOPLEFT", self.panel, "TOPLEFT", col * stride, -(row * stride))

      -- Live values for the click-to-announce handler (not diff-guarded).
      slot._present = d.present
      slot._label   = d.label

      if d.icon and d.icon ~= slot._lastIcon then
        slot.icon:SetTexture(d.icon)
        slot._lastIcon    = d.icon
        slot._lastPresent = nil   -- texture swap drops desat; force re-apply
      end

      if d.present ~= slot._lastPresent then
        if d.present then
          slot.icon:SetVertexColor(1, 1, 1, 1)
          if slot.icon.SetDesaturated then slot.icon:SetDesaturated(false) end
          setMissingHighlight(slot, false)
        else
          slot.icon:SetVertexColor(0.55, 0.55, 0.55, 1)
          if slot.icon.SetDesaturated then slot.icon:SetDesaturated(true) end
          setMissingHighlight(slot, true)
        end
        slot._lastPresent = d.present
      end

      if d.present and d.duration > 0 and d.expirationTime > now then
        local start = d.expirationTime - d.duration
        if start ~= slot._lastCdStart or d.duration ~= slot._lastCdDur then
          slot.cooldown:SetCooldown(start, d.duration)
          slot._lastCdStart = start
          slot._lastCdDur   = d.duration
        end
      elseif (slot._lastCdStart or 0) ~= 0 then
        slot.cooldown:Clear()
        slot._lastCdStart = 0
        slot._lastCdDur   = 0
      end

      local countTxt = (d.count and d.count > 1) and tostring(d.count) or ""
      if countTxt ~= slot._lastCount then
        slot.countText:SetText(countTxt)
        slot._lastCount = countTxt
      end

      if not slot:IsShown() then slot:Show() end
    else
      if slot:IsShown() then
        setMissingHighlight(slot, false)
        slot._lastPresent = nil
        slot:Hide()
      end
    end
  end

  if not self.panel:IsShown() then self.panel:Show() end
end
