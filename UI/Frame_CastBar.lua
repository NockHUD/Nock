-- UI/Frame_CastBar.lua
-- Renders whatever Nock.CastBarSource picks: a real cast or channel, else the
-- Auto Shot wind-up if this HUD's toggle allows it. Visible only while one exists.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local CastBarView = Nock:NewModule("CastBarView", "AceEvent-3.0")
local C = Nock.Constants

function CastBarView:OnInitialize()
  local parent = Nock.parentFrame
  local OUTER  = C.DIM.OUTER_PAD
  local INNER  = C.DIM.INNER_GAP
  -- Panel taller than the bar by OUTER_PAD top + bottom — icon and bar both
  -- get the standard grid inset on all sides; INNER_GAP separates them.
  local panelH   = C.DIM.CAST_BAR_H + 2 * OUTER
  local iconSize = C.DIM.CAST_BAR_H

  -- Container panel — same backdrop/border style as the HUD.
  local panel = CreateFrame("Frame", "NockCastBarPanel", parent, "BackdropTemplate")
  panel:SetHeight(panelH)
  panel:ClearAllPoints()
  -- y = -1 so the cast-bar panel's bottom border overlaps the HUD's top
  -- border by 1px. Result: a single seamless 1px line between them, no gap.
  panel:SetPoint("BOTTOMLEFT",  parent, "TOPLEFT",  0, -1)
  panel:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, -1)
  panel:Hide()

  -- Square spell icon inset by OUTER_PAD on top / bottom / left.
  local icon = panel:CreateTexture(nil, "ARTWORK")
  icon:SetSize(iconSize, iconSize)
  icon:SetPoint("TOPLEFT", panel, "TOPLEFT", OUTER, -OUTER)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  -- Cast bar inset by OUTER_PAD on top / bottom / right; INNER_GAP between it
  -- and the icon. Same spacing rules as any row inside the HUD.
  local barWidth = C.DIM.HUD_WIDTH - 2 * OUTER - iconSize - INNER
  local f = Nock.UI.CreateBar(panel, "NockCastBar", barWidth, C.DIM.CAST_BAR_H, C.COLORS.CAST_BAR, "castBarTexture", "castBarTrack")
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT",  panel, "TOPLEFT",   OUTER + iconSize + INNER, -OUTER)
  f:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -OUTER,                    -OUTER)

  self.frame = panel
  self.bar = f
  self.icon = icon
  self._lastText = ""
  self._lastIcon = nil

  -- Free placement (free layout only). The panel is welded to the HUD box's top
  -- edge by TWO points, which is what makes it stretch to the box width and read
  -- as one piece with it. That weld is the default and stays the whole story in
  -- grid mode; in free layout a saved castBarPosition breaks it and the panel
  -- floats on its own at a fixed width.
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    Nock.db.profile.castBarPosition = CastBarView:CaptureFreePos()
    CastBarView:ApplyPosition()
  end)
  panel:EnableMouse(false)

  local editBG = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  editBG:SetAllPoints(panel)
  editBG:SetFrameLevel(math.max(0, panel:GetFrameLevel() - 1))
  Nock.UI.ApplyBackdrop(editBG)
  editBG:SetBackdropColor(0, 0, 0, 0.25)
  editBG:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  editBG:Hide()
  self.editBG = editBG

  Nock.UI.RegisterNudgeable(panel, {
    label   = "Cast Bar",
    active  = function() return Nock.FreeLayoutActive() end,
    get     = function() return Nock.db.profile.castBarPosition end,
    set     = function(pos)
      Nock.db.profile.castBarPosition = pos
      CastBarView:ApplyPosition()
    end,
    -- false re-welds it to the box: that IS the cast bar's default position.
    default = function() return false end,
    -- The weld anchors to the HUD frame, so GetPoint() would hand back
    -- {BOTTOMLEFT -> parent TOPLEFT}, and re-anchoring those numbers to UIParent
    -- would fling the bar to the bottom-left of the screen. Seed from screen
    -- coordinates instead, the same way HUD's captureFreePos seeds a free row.
    capture = function() return CastBarView:CaptureFreePos() end,
  })

  self:ApplyStyle()
  self:ApplyPosition()
  self:ApplyLock()
  self:RegisterMessage("NOCK_LOCK_CHANGED",   "ApplyLock")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "OnVisualsChanged")
  self:RegisterMessage("NOCK_POSITION_RESET", "ApplyPosition")   -- profile switch
end

-- Profile-driven styling (Classic HUD → Cast Bar): bar height (panel and icon
-- track it), icon toggle (off stretches the bar full width), fill color,
-- padding, and the panel's Background block (castBar* keys via
-- ApplyUserPanelStyle). The texture rides the castBarTexture key through
-- CreateBar/RefreshMedia.
function CastBarView:ApplyStyle()
  local p = (Nock.db and Nock.db.profile) or {}
  local pad   = p.castBarPadding or C.DIM.OUTER_PAD
  local INNER = C.DIM.INNER_GAP
  local h = p.castBarHeight or C.DIM.CAST_BAR_H
  local showIcon = p.castBarShowIcon ~= false

  Nock.UI.ApplyUserPanelStyle(self.frame, "castBar")

  self.frame:SetHeight(h + 2 * pad)
  self.bar:SetHeight(h)
  self.icon:SetSize(h, h)
  self.icon:ClearAllPoints()
  self.icon:SetPoint("TOPLEFT", self.frame, "TOPLEFT", pad, -pad)
  if showIcon then self.icon:Show() else self.icon:Hide() end

  local left = pad + (showIcon and (h + INNER) or 0)
  self.bar:ClearAllPoints()
  self.bar:SetPoint("TOPLEFT",  self.frame, "TOPLEFT",   left, -pad)
  self.bar:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -pad,  -pad)
  -- SetBarFill scales against this cached width, so it must track the anchors.
  self.bar.maxWidth = C.DIM.HUD_WIDTH - pad - left - 2

  local c = p.castBarColor or C.COLORS.CAST_BAR
  self.bar.fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

-- Screen-space position, matching HUD.lua's captureFreePos so a freed cast bar
-- and a freed row are stored the same way.
function CastBarView:CaptureFreePos()
  local p = self.frame
  if not p:GetLeft() then return nil end
  return { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT",
           x = p:GetLeft(), y = p:GetBottom() }
end

local EDIT_TEXT = "Cast Bar"
local EDIT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Editing = unlocked, in free placement. The only window where the cast bar's
-- own position means anything, and the only time it is held open while idle.
local function isEditing()
  if not Nock.FreeLayoutActive() then return false end
  return not Nock.IsLocked()
end

local function freePos()
  if not Nock.FreeLayoutActive() then return nil end
  local p = Nock.db and Nock.db.profile
  local pos = p and p.castBarPosition
  if type(pos) == "table" and pos.point then return pos end
  return nil
end

function CastBarView:ApplyPosition()
  local panel = self.frame
  local pos   = freePos()
  panel:ClearAllPoints()
  if pos then
    -- Free: one point, anchored to UIParent, explicit width (the two-point weld
    -- was what sized it before). Still parented to the HUD frame, so it keeps
    -- inheriting scale and hide-out-of-combat, exactly like a free row.
    panel:SetWidth(C.DIM.HUD_WIDTH)
    panel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
  else
    -- Welded: two points to the HUD box's top edge, y = -1 so the borders
    -- overlap into a single seamless line.
    local parent = Nock.parentFrame
    panel:SetPoint("BOTTOMLEFT",  parent, "TOPLEFT",  0, -1)
    panel:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, -1)
  end
end

-- Draggable and selectable only where free placement means anything: unlocked,
-- in free layout. Grid mode leaves it inert and welded.
function CastBarView:ApplyLock()
  -- Mouse only; the edit border rides on the panel's visibility, which Refresh
  -- owns (it reopens the panel while editing and closes it again after).
  self.frame:EnableMouse(isEditing())
end

function CastBarView:OnVisualsChanged()
  -- Toggling free layout off re-welds it; toggling on restores any saved spot.
  self:ApplyStyle()
  self:ApplyPosition()
  self:ApplyLock()
end

function CastBarView:Refresh(state)
  -- React mode has its own glued cast bar (UI/Frame_ReactCastBar.lua).
  local p = Nock.db and Nock.db.profile
  if p and p.hudMode == "react" then
    if self.frame:IsShown() then self.frame:Hide() end
    return
  end
  -- Master visibility gate (Layout → Cast bar). Off = stay hidden even mid-cast.
  if p and p.showCastBar == false then
    if self.frame:IsShown() then self.frame:Hide() end
    return
  end

  -- Editing preview. The panel is normally shown only mid-cast, so while idle
  -- there would be nothing to click, drag or nudge — and a pad claimed during a
  -- cast would vanish the instant it ended. Hold it open with placeholder
  -- content for as long as the HUD is unlocked in free placement. Deliberately
  -- BELOW the react and showCastBar gates: a cast bar you have switched off
  -- stays off, since there is nothing to position.
  if isEditing() then
    if not self.frame:IsShown() then self.frame:Show() end
    self.editBG:Show()
    if self._lastIcon ~= EDIT_ICON then
      self.icon:SetTexture(EDIT_ICON)
      self._lastIcon = EDIT_ICON
    end
    Nock.UI.SetBarFill(self.bar, 0.6)
    if self._lastText ~= EDIT_TEXT then
      self.bar.text:SetText(EDIT_TEXT)
      self._lastText = EDIT_TEXT
    end
    return
  end
  self.editBG:Hide()

  -- Visibility of the Auto Shot wind-up is decided HERE, at the render edge —
  -- the producer publishes it unconditionally so a display setting can never
  -- change engine state. On the classic HUD it is opt-in (the swing timer's
  -- wind-up mark already covers it), toggled by /nock autoshot.
  local c = Nock.CastBarSource(p and p.showAutoShotCast)
  if not c then
    if self.frame:IsShown() then self.frame:Hide() end
    return
  end

  if not self.frame:IsShown() then self.frame:Show() end

  if c.icon and c.icon ~= self._lastIcon then
    self.icon:SetTexture(c.icon)
    self._lastIcon = c.icon
  end

  local total = c.endTime - c.startTime
  if total <= 0 then return end

  local now = GetTime()
  local elapsed = now - c.startTime
  local progress
  if c.isChannel then
    progress = math.max(0, 1 - (elapsed / total))
  else
    progress = math.max(0, math.min(1, elapsed / total))
  end
  Nock.UI.SetBarFill(self.bar, progress)

  local remaining = math.max(0, c.endTime - now)
  local txt = ("%s  %.1fs"):format(c.name or "?", remaining)
  if txt ~= self._lastText then
    self.bar.text:SetText(txt)
    self._lastText = txt
  end
end
