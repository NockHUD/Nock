-- UI/Frame_EotbPulse.lua
-- The Eyes of the Beast pulse bar: a HUD row stacked on the React cast bar, seconds to the pet's next pull pulse; right-click resyncs.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("EotbPulseView", "AceEvent-3.0")
local C = Nock.Constants

-- Part of the HUD (user, 2026-10-08): parented to the React cluster and
-- stacked on the cast bar exactly as the cast bar is stacked on the cluster
-- -- one layout, Nock.UI.LayoutIconBarRow, in whole device pixels: same
-- height, same width, same icon column, sharing its 1 px top border --
-- so it moves and scales with the HUD and has no position of its own. With
-- the cast bar switched off it takes the cast bar's place. It shows in
-- combat while Eyes of the Beast is channelled (state.eotbPulse,
-- Forever/EotbPulse.lua), and as a preview while the HUD is unlocked.
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local REACT = {
  CAST_H = 16,   -- Frame_ReactCastBar's default height
  FONT   = 9,
  BAR_BG = { 0.08, 0.08, 0.08, 0.90 },
  BORDER = { 0.00, 0.00, 0.00, 1.00 },
  FILL   = { 0.41, 0.69, 0.29, 1.00 },   -- the WeakAura's green
  TEXT   = { 1.00, 1.00, 1.00, 1.00 },
}
local EOTB_ICON = 132150

local function profile() return (Nock.db and Nock.db.profile) or {} end

-- The cast bar's height (reactCastH, Frame_ReactCastBar's rule): this row
-- matches it.
function View.RowHeight(p)
  local h = tonumber(p and p.reactCastH)
  if not h or h <= 0 then h = REACT.CAST_H end
  return h
end

local function resync()
  local m = Nock:GetModule("EotbPulse", true)
  if m and m.Resync then m:Resync() end
end

function View:OnInitialize()
  local cluster = Nock:GetModule("ReactCluster", true)
  local parent = (cluster and cluster.frame) or Nock.parentFrame
  local panel = CreateFrame("Frame", "NockEotbPulsePanel", parent)
  panel:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then resync() end
  end)
  panel:Hide()

  local iconF = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  Nock.UI.ApplyBackdrop(iconF, REACT.BAR_BG, REACT.BORDER)
  local icon = iconF:CreateTexture(nil, "ARTWORK")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:SetTexture(EOTB_ICON)

  local bar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  Nock.UI.ApplyBackdrop(bar, REACT.BAR_BG, REACT.BORDER)

  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetTexture(WHITE8X8)
  fill:SetVertexColor(REACT.FILL[1], REACT.FILL[2], REACT.FILL[3], REACT.FILL[4])
  fill:SetWidth(0.01)
  bar.fill = fill

  local nameText = bar:CreateFontString(nil, "OVERLAY")
  nameText:SetFont(C.FONT.PATH, REACT.FONT, "OUTLINE")
  nameText:SetPoint("LEFT", bar, "LEFT", 3, 0)
  nameText:SetTextColor(unpack(REACT.TEXT))
  nameText:SetText("Pulse")
  bar.nameText = nameText

  local timeText = bar:CreateFontString(nil, "OVERLAY")
  timeText:SetFont(C.FONT.PATH, REACT.FONT, "OUTLINE")
  timeText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
  timeText:SetTextColor(unpack(REACT.TEXT))
  bar.timeText = timeText

  self.frame, self.bar, self.iconF, self.icon, self.parent = panel, bar, iconF, icon, parent
  self:ApplyLayout()
  self:ApplyLock()
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyLayout")
  self:RegisterMessage("NOCK_PIXEL_GRID_CHANGED", "ApplyLayout")   -- device-pixel seams
  self:RegisterMessage("NOCK_LOCK_CHANGED", "ApplyLock")
end

-- Height, anchor and media, re-read on every visuals change and pixel-grid
-- move: stacked on the cast bar (its top border shared), or straight on the
-- cluster when the cast bar is switched off.
function View:ApplyLayout()
  local p = profile()
  local cb = Nock:GetModule("ReactCastBar", true)
  local below = (p.reactShowCastBar ~= false and cb and cb.frame) or self.parent
  self._edge, self._dev = Nock.UI.LayoutIconBarRow(
    { panel = self.frame, iconF = self.iconF, icon = self.icon, bar = self.bar, fill = self.bar.fill },
    below, View.RowHeight(p))
  -- React media, the cast bar's rules.
  self.bar.fill:SetTexture(Nock.UI.GetReactBarTexture() or WHITE8X8)
  local font = Nock.UI.GetReactFont() or C.FONT.PATH
  local size = math.max(6, REACT.FONT + Nock.UI.GetReactFontDelta())
  local style = Nock.UI.GetReactFontStyle()
  Nock.UI.SafeSetFont(self.bar.nameText, font, size, style)
  Nock.UI.SafeSetFont(self.bar.timeText, font, size, style)
  Nock.UI.ApplyReactTextShadow(self.bar.nameText)
  Nock.UI.ApplyReactTextShadow(self.bar.timeText)
  self._lastFill, self._lastDecis = nil, nil
end

-- Locked, the row takes a right-click (resync); unlocked, clicks go through
-- to the HUD so it can be dragged as one piece.
function View:ApplyLock()
  self.frame:EnableMouse(Nock.IsLocked and Nock.IsLocked() or false)
end

function View:Refresh(state)
  local panel = self.frame
  if not panel then return end
  local p = profile()
  if not Nock.isHunter or Nock.WizardHides("eotbPulse") or p.eotbPulseEnabled ~= true or not Nock.HudIsReact() then
    if panel:IsShown() then panel:Hide() end
    return
  end
  local e = state.eotbPulse
  local rem, per
  if e and e.active and e.remaining then
    rem, per = e.remaining, e.period
  elseif Nock.EditPreview("eotbPulse") then
    -- Edit preview: a beat running on the clock (never real).
    per = (e and e.period) or 5.6
    rem = per - (GetTime() % per)
  else
    if panel:IsShown() then panel:Hide() end
    return
  end
  if not panel:IsShown() then panel:Show() end
  local w = Nock.UI.IconBarFillWidth(self.bar:GetWidth() or 2, rem / per, self._edge or 1, self._dev)
  if w ~= self._lastFill then
    self.bar.fill:SetWidth(w)
    self._lastFill = w
  end
  local decis = math.floor(rem * 10 + 0.5)
  if decis ~= self._lastDecis then
    self.bar.timeText:SetText(string.format("%.1f", decis / 10))
    self._lastDecis = decis
  end
end
