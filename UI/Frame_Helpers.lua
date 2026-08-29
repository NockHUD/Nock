-- UI/Frame_Helpers.lua
-- Floating badge row for the Helpers reminders. Renders state.helpers
-- left-to-right: missing = desaturated icon + grey border, expiring = full
-- colour + amber border + countdown. Movable while unlocked (with a preview
-- row, since the panel is hidden outside instances and in combat), styled via
-- the helpers* Background keys.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local HelpersView = Nock:NewModule("HelpersView", "AceEvent-3.0")
local C = Nock.Constants

local LABEL_GAP        = 4
local LABEL_FONT_SIZE  = 12
local LABEL_FONT_NAME  = "Numen"   -- LSM "font" entry; falls back if unregistered
local LABEL_STYLE      = "THICKOUTLINE"
local MAX_SLOTS        = 12
local PAD              = 6         -- panel padding around the badge row
local TOP_FRACTION     = C.DIM.WARN_TOP_FRACTION or 0.25  -- warnings live at 25%
-- 50px below the warnings row's centre, which itself sits at top * frac.
local Y_OFFSET_BELOW_WARN = C.DIM.WARN_ICON_SIZE + 50

local STATUS_BORDER = {
  expiring = { 1.00, 0.70, 0.00, 1.00 },   -- amber: up, but refresh it soon
  missing  = { 0.40, 0.40, 0.40, 1.00 },   -- grey: not up at all
}
local MISSING_ALPHA = 0.7

local function profileNum(key, fallback)
  local p = Nock.db and Nock.db.profile
  local v = p and p[key]
  return type(v) == "number" and v or fallback
end

local function iconSize() return profileNum("helpersIconSize", 40) end
local function iconGap()  return profileNum("helpersIconGap", 10) end

local function formatDur(seconds)
  if not seconds or seconds <= 0 then return "" end
  if seconds < 10 then return ("%.1f"):format(seconds) end
  if seconds < 60 then return ("%d"):format(math.ceil(seconds)) end
  if seconds < 3600 then
    local m = math.floor(seconds / 60)
    return ("%dm"):format(m)
  end
  return ("%dh"):format(math.floor(seconds / 3600))
end

function HelpersView:OnInitialize()
  local panel = CreateFrame("Frame", "NockHelpers", UIParent, "BackdropTemplate")
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(f) f:StartMoving() end)
  panel:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    Nock.db.profile.helpersPosition = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  Nock.UI.RegisterNudgeable(panel, {
    label   = "Helpers",
    get     = function()
      local p = Nock.db.profile.helpersPosition
      return type(p) == "table" and p or nil
    end,
    set     = function(pos)
      Nock.db.profile.helpersPosition = pos
      HelpersView:ApplyPosition()
    end,
    -- `false` is the "never dragged" sentinel, which ApplyPosition reads as
    -- the computed spot below the warnings — that IS the panel's default.
    default = function()
      Nock.db.profile.helpersPosition = false
      HelpersView:ApplyPosition()
      return nil
    end,
  })
  panel:SetFrameStrata("HIGH")
  panel:Hide()
  self.frame = panel

  self.slots = {}
  for i = 1, MAX_SLOTS do
    local slot = Nock.UI.CreateIconSlot(panel, "NockHelperSlot" .. i, iconSize())
    slot.cdText:SetText("")

    -- Short label below the icon ("Food", "Flask", "Battle", ...). Uses the
    -- "Numen" LSM font with a thick outline. Anchored with TOPLEFT+TOPRIGHT
    -- spanning the slot's full width (plus a small overflow each side) so
    -- "CENTER" justification reliably centres the text on the icon column
    -- regardless of glyph width / outline padding.
    local label = slot:CreateFontString(nil, "OVERLAY")
    -- Re-applies if "Numen" registers after us (SharedMedia plugin cold-load).
    Nock.UI.RegisterHeaderFontString(label, LABEL_FONT_NAME, LABEL_FONT_SIZE, LABEL_STYLE)
    label:SetPoint("TOPLEFT",  slot, "BOTTOMLEFT",  -8, -LABEL_GAP)
    label:SetPoint("TOPRIGHT", slot, "BOTTOMRIGHT",  8, -LABEL_GAP)
    label:SetHeight(LABEL_FONT_SIZE + 4)
    label:SetJustifyH("CENTER")
    label:SetJustifyV("TOP")
    label:SetTextColor(1, 1, 1, 1)
    slot.label = label

    slot:Hide()
    slot._lastIcon   = nil
    slot._lastText   = ""
    slot._lastLabel  = nil
    slot._lastStatus = nil
    self.slots[i] = slot
  end

  self:ApplyMetrics()
  self:ApplyPosition()
  self:ApplyLock()

  self:RegisterMessage("NOCK_VISUALS_CHANGED",        "OnVisualsChanged")
  self:RegisterMessage("NOCK_LOCK_CHANGED",           "ApplyLock")
  self:RegisterMessage("NOCK_HELPERS_POSITION_RESET", "ApplyPosition")
  self:RegisterMessage("NOCK_POSITION_RESET",         "ApplyPosition")  -- profile switch

  if not Nock.isHunter then panel:Hide() end
end

-- Slot sizes + panel scale from the profile. Re-run on NOCK_VISUALS_CHANGED.
function HelpersView:ApplyMetrics()
  local size = iconSize()
  for _, slot in ipairs(self.slots) do
    slot:SetSize(size, size)
  end
  self.frame:SetScale(profileNum("helpersScale", 1.0))
end

function HelpersView:ApplyPosition()
  local pos = Nock.db and Nock.db.profile and Nock.db.profile.helpersPosition
  self.frame:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    self.frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    -- Never dragged: the legacy computed spot, centred below the warnings row.
    local screenH = UIParent:GetHeight() or 768
    self.frame:SetPoint("CENTER", UIParent, "TOP", 0,
      -screenH * TOP_FRACTION - Y_OFFSET_BELOW_WARN)
  end
end

function HelpersView:ApplyLock()
  local locked = Nock.IsLocked()
  self.frame:EnableMouse(not locked)
  self:ApplyStyle()
end

-- User Background block (helpers* keys); the green unlock border wins while
-- the panel is draggable so it stays findable.
function HelpersView:ApplyStyle()
  Nock.UI.ApplyUserPanelStyle(self.frame, "helpers")
  if not Nock.IsLocked() then
    self.frame:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  end
end

function HelpersView:OnVisualsChanged()
  self:ApplyMetrics()
  self:ApplyStyle()
  -- Slot geometry may have moved; force every slot to repaint next tick.
  for _, slot in ipairs(self.slots) do slot._lastStatus = nil end
end

-- While unlocked the panel must be visible ANYWHERE — it is hidden outside
-- instances and in combat, so there would otherwise be no moment in which it
-- could be dragged (the transient-frame rule). The preview substitutes the
-- first few catalog entries as sample badges, one of them expiring so both
-- looks are visible while styling.
local previewList
local function getPreviewList()
  -- Only cache once every icon resolved: item icons come back nil until the
  -- client has the item cached, and a preview built during that window would
  -- otherwise keep its blank icons for the rest of the session.
  if previewList then return previewList end
  local out, complete = {}, true
  local mod = Nock:GetModule("Helpers", true)
  local catalog = mod and mod.Catalog or {}
  for i = 1, math.min(4, #catalog) do
    local cat = catalog[i]
    local icon = cat.iconFn and cat.iconFn() or nil
    if not icon then complete = false end
    out[i] = {
      id        = "preview_" .. cat.key,
      status    = (i == 2) and "expiring" or "missing",
      icon      = icon,
      remaining = (i == 2) and 90 or nil,
      label     = cat.shortLabel,
    }
  end
  if complete and #out > 0 then previewList = out end
  return out
end

function HelpersView:Refresh(state)
  local unlocked = not Nock.IsLocked()
  local list = state.helpers
  if unlocked and #list == 0 then list = getPreviewList() end

  -- Hide the whole panel when globally disabled, a third-party consumes WA is
  -- loaded, or the player is in combat (pre-pull panel only) — unless we're
  -- unlocked, in which case it stays up to be positioned.
  local p = Nock.db and Nock.db.profile
  local suppressed = (p and p.showHelpers == false)
    or Nock.state.helpersHiddenByWA
    or Nock.state.player.inCombat
  if suppressed and not unlocked then
    if self.frame:IsShown() then
      for _, slot in ipairs(self.slots) do slot:Hide() end
      self.frame:Hide()
    end
    return
  end

  local n = math.min(#list, MAX_SLOTS)
  if n == 0 then
    if self.frame:IsShown() then self.frame:Hide() end
    return
  end

  local size, gap = iconSize(), iconGap()
  local rowWidth = n * size + math.max(0, n - 1) * gap
  self.frame:SetSize(rowWidth + 2 * PAD,
    size + LABEL_GAP + LABEL_FONT_SIZE + 4 + 2 * PAD)

  for i = 1, MAX_SLOTS do
    local slot = self.slots[i]
    local h = list[i]
    if i <= n and h then
      -- Anchor each slot from the panel's TOPLEFT so the labels below share a
      -- baseline across every visible slot.
      slot:ClearAllPoints()
      slot:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
        PAD + (i - 1) * (size + gap), -PAD)

      if h.icon and h.icon ~= slot._lastIcon then
        slot.icon:SetTexture(h.icon)
        slot._lastIcon = h.icon
        -- Some clients reset vertex / desaturation when the texture changes,
        -- so force the status branch below to re-apply by clearing the cache.
        slot._lastStatus = nil
      end

      if h.status ~= slot._lastStatus then
        if h.status == "expiring" then
          -- The buff IS up — full colour, amber border, countdown running.
          slot.icon:SetVertexColor(1, 1, 1, 1)
          if slot.icon.SetDesaturated then slot.icon:SetDesaturated(false) end
          slot:SetAlpha(1)
          slot:SetBackdropBorderColor(unpack(STATUS_BORDER.expiring))
        else
          -- True desaturation (greyscale) plus a slight dim. Just vertex colour
          -- alone leaves the icon visibly tinted; SetDesaturated converts to
          -- pure luminance for the "I need to apply this" look.
          slot.icon:SetVertexColor(0.65, 0.65, 0.65, 1)
          if slot.icon.SetDesaturated then slot.icon:SetDesaturated(true) end
          slot:SetAlpha(MISSING_ALPHA)
          slot:SetBackdropBorderColor(unpack(STATUS_BORDER.missing))
        end
        slot._lastStatus = h.status
      end

      local txt = formatDur(h.remaining)
      if txt ~= slot._lastText then
        slot.cdText:SetText(txt)
        slot._lastText = txt
      end

      if h.label ~= slot._lastLabel then
        slot.label:SetText(h.label or "")
        slot._lastLabel = h.label
      end

      if not slot:IsShown() then slot:Show() end
    else
      if slot:IsShown() then slot:Hide() end
    end
  end

  if not self.frame:IsShown() then self.frame:Show() end
end
