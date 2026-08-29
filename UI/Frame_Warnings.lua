-- UI/Frame_Warnings.lua
-- Renders state.warnings as small icon-squares centered horizontally at 25% screen height.
-- Each active warning is one square. Red severity gets the buttonOverlay alert glow.
-- This frame is anchored to UIParent (NOT the HUD), so warnings stay visible in your
-- top-center field of view independent of where the HUD is positioned.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local WarningsView = Nock:NewModule("WarningsView")
local C = Nock.Constants
local LSM = LibStub("LibSharedMedia-3.0", true)

local SEVERITY_GLOW = {
  red   = { 1.00, 0.10, 0.10, 1 },
  amber = { 1.00, 0.65, 0.10, 1 },
  blue  = { 0.30, 0.60, 1.00, 1 },
}

local SEVERITY_BORDER = {
  red   = C.COLORS.WARN_RED,
  amber = C.COLORS.WARN_AMBER,
  blue  = C.COLORS.WARN_BLUE,
}

function WarningsView:OnInitialize()
  local size = C.DIM.WARN_ICON_SIZE
  local maxSlots = C.WARNING_SLOTS

  local container = CreateFrame("Frame", "NockWarnings", UIParent)
  container:SetSize(maxSlots * size + (maxSlots - 1) * C.DIM.WARN_ICON_GAP, size + 18)
  container:SetFrameStrata("HIGH")

  local screenH = UIParent:GetHeight() or 768
  container:SetPoint("CENTER", UIParent, "TOP", 0, -screenH * C.DIM.WARN_TOP_FRACTION)

  self.squares = {}
  for i = 1, maxSlots do
    local sq = Nock.UI.CreateIconSlot(container, "NockWarnSlot" .. i, size)
    sq.cdText:SetFont(Nock.UI.GetFont(), 14, "THICKOUTLINE")

    local label = sq:CreateFontString(nil, "OVERLAY")
    label:SetFont(Nock.UI.GetFont(), 12, "THICKOUTLINE")
    label:SetPoint("TOP", sq, "BOTTOM", 0, -6)
    label:SetTextColor(1, 1, 1, 1)
    sq.label = label

    sq._lastIcon = nil
    sq._lastText = ""
    sq._lastSeverity = nil
    sq._lastBorderSize = nil
    sq._lastDurText = ""
    sq._glowing = false
    sq:Hide()
    self.squares[i] = sq
  end

  self.frame = container

  if not Nock.isHunter then
    container:Hide()
  end
end

local function setGlow(sq, severity)
  local color = severity and SEVERITY_GLOW[severity]
  if severity == "red" then
    if not sq._glowing then
      Nock.UI.SetIconAlertGlow(sq, true, color)
      sq._glowing = true
    end
  else
    if sq._glowing then
      Nock.UI.SetIconAlertGlow(sq, false)
      sq._glowing = false
    end
  end
end

local function formatDur(seconds)
  if not seconds or seconds <= 0 then return "" end
  if seconds < 10 then return ("%.1f"):format(seconds) end
  if seconds < 60 then return ("%d"):format(math.ceil(seconds)) end
  if seconds < 600 then
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds - m * 60)
    return ("%d:%02d"):format(m, s)
  end
  return ("%dm"):format(math.floor(seconds / 60))
end

function WarningsView:Refresh(state)
  -- Global disable: hide the whole panel + stop any active alert glows.
  if Nock.db and Nock.db.profile and Nock.db.profile.showWarnings == false then
    if not self._hidden then
      for _, sq in ipairs(self.squares) do
        if sq._glowing then
          Nock.UI.SetIconAlertGlow(sq, false)
          sq._glowing = false
        end
        sq:Hide()
      end
      self.frame:Hide()
      self._hidden = true
    end
    return
  end
  if self._hidden then
    self.frame:Show()
    self._hidden = nil
  end

  local list = state.warnings
  local p = Nock.db and Nock.db.profile or {}
  local size = p.warningIconSize or C.DIM.WARN_ICON_SIZE
  local borderSize = p.warningBorderSize or 3
  local labelOffset = p.warningLabelOffset or 10
  local labelSize = p.warningLabelSize or 12
  local labelStyle = p.warningLabelStyle or "THICKOUTLINE"
  local labelUpper = p.warningLabelUpper
  local labelFontName = p.warningLabelFont
  local labelFontPath = (LSM and labelFontName and LSM:Fetch("font", labelFontName)) or Nock.UI.GetFont()
  local gap = C.DIM.WARN_ICON_GAP
  local durFontSize = math.max(12, math.floor(size * 0.32))

  local n = math.min(#list, C.WARNING_SLOTS)
  local totalWidth = n * size + math.max(0, n - 1) * gap
  local startX = -totalWidth / 2 + size / 2

  for i = 1, C.WARNING_SLOTS do
    local sq = self.squares[i]
    local w = list[i]
    if i <= n and w then
      sq:SetSize(size, size)
      sq:ClearAllPoints()
      sq:SetPoint("CENTER", self.frame, "TOP", startX + (i - 1) * (size + gap), -size / 2)

      if borderSize ~= sq._lastBorderSize then
        Nock.UI.SetGlowBorderSize(sq, borderSize)
        sq._lastBorderSize = borderSize
        sq._lastSeverity = nil  -- SetBackdrop reset color; re-apply below
      end

      if labelOffset ~= sq._lastLabelOffset then
        sq.label:ClearAllPoints()
        sq.label:SetPoint("TOP", sq, "BOTTOM", 0, -labelOffset)
        sq._lastLabelOffset = labelOffset
      end
      if labelFontPath ~= sq._lastLabelFont
        or labelSize ~= sq._lastLabelSize
        or labelStyle ~= sq._lastLabelStyle
      then
        sq.label:SetFont(labelFontPath, labelSize, labelStyle)
        sq._lastLabelFont = labelFontPath
        sq._lastLabelSize = labelSize
        sq._lastLabelStyle = labelStyle
      end

      if w.icon and w.icon ~= sq._lastIcon then
        sq.icon:SetTexture(w.icon)
        sq._lastIcon = w.icon
      end
      local displayText = (labelUpper and w.text) and w.text:upper() or w.text
      if displayText ~= sq._lastText then
        sq.label:SetText(displayText)
        sq._lastText = displayText
      end
      if w.severity ~= sq._lastSeverity then
        Nock.UI.SetIconHighlight(sq, SEVERITY_BORDER[w.severity])
        sq._lastSeverity = w.severity
      end
      setGlow(sq, w.severity)

      local durText = formatDur(w.remaining)
      if durText ~= sq._lastDurText then
        sq.cdText:SetText(durText)
        sq._lastDurText = durText
      end
      if sq.cdText:GetFont() and durFontSize ~= sq._lastDurFontSize then
        sq.cdText:SetFont(Nock.UI.GetFont(), durFontSize, "THICKOUTLINE")
        sq._lastDurFontSize = durFontSize
      end

      if not sq:IsShown() then sq:Show() end
    else
      if sq._glowing then
        Nock.UI.SetIconAlertGlow(sq, false)
        sq._glowing = false
      end
      if sq:IsShown() then sq:Hide() end
    end
  end
end
