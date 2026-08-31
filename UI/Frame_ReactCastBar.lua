-- UI/Frame_ReactCastBar.lua
-- React-mode cast bar: glued above the HUD (no layout shift), flat fixed skin.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ReactCastBar = Nock:NewModule("ReactCastBar", "AceEvent-3.0")
local C = Nock.Constants

-- Reference React skin (see Frame_ReactCluster.lua for the convention).
-- Height + fill color can be overridden from the React HUD tab.
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local REACT = {
  CAST_H    = 16,   -- measured 12 + 4px, per in-game tuning
  FONT      = 9,
  BAR_BG    = { 0.08, 0.08, 0.08, 0.90 },
  BORDER    = { 0.00, 0.00, 0.00, 1.00 },
  CAST_FILL = { 0.40, 0.70, 1.00, 1.00 },
  TEXT      = { 1.00, 1.00, 1.00, 1.00 },
}

function ReactCastBar:OnInitialize()
  -- Glued directly onto the React cluster: parented + corner-anchored to it,
  -- so the cast bar matches reactWidth/reactScale, follows free-layout drags,
  -- and vanishes with the cluster in classic mode. The 1px overlap shares a
  -- border seam with the auto bar below (clamped, reference look).
  local cluster = Nock:GetModule("ReactCluster", true)
  local parent  = (cluster and cluster.frame) or Nock.parentFrame
  local panel = CreateFrame("Frame", "NockReactCastPanel", parent)
  panel:SetHeight(REACT.CAST_H)
  panel:SetPoint("BOTTOMLEFT",  parent, "TOPLEFT",  0, -1)
  panel:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, -1)
  panel:Hide()

  -- Square icon box left, bar to its right, sharing their 1px borders.
  local iconF = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  iconF:SetSize(REACT.CAST_H, REACT.CAST_H)
  iconF:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  Nock.UI.ApplyBackdrop(iconF, REACT.BAR_BG, REACT.BORDER)
  local icon = iconF:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", iconF, "TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", iconF, "BOTTOMRIGHT", -1, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local bar = CreateFrame("Frame", "NockReactCastBar", panel, "BackdropTemplate")
  bar:SetPoint("TOPLEFT", iconF, "TOPRIGHT", -1, 0)
  bar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  Nock.UI.ApplyBackdrop(bar, REACT.BAR_BG, REACT.BORDER)

  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetTexture(WHITE8X8)
  fill:SetVertexColor(unpack(REACT.CAST_FILL))
  fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
  fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
  fill:SetWidth(0.01)
  bar.fill = fill

  -- Name left, remaining seconds right — separate strings, separate diffs.
  local nameText = bar:CreateFontString(nil, "OVERLAY")
  nameText:SetFont(C.FONT.PATH, REACT.FONT, "OUTLINE")
  nameText:SetPoint("LEFT", bar, "LEFT", 3, 0)
  nameText:SetTextColor(unpack(REACT.TEXT))
  bar.nameText = nameText

  local timeText = bar:CreateFontString(nil, "OVERLAY")
  timeText:SetFont(C.FONT.PATH, REACT.FONT, "OUTLINE")
  timeText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
  timeText:SetTextColor(unpack(REACT.TEXT))
  bar.timeText = timeText

  self.frame = panel
  self.bar = bar
  self.icon = icon
  self.iconF = iconF
  self._lastName = nil
  self._lastTime = nil
  self._lastIcon = nil

  self:ApplyLayout()
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyLayout")
end

-- Skin overrides (React HUD tab): cast bar height (also the icon box edge)
-- and fill color. Fill width is recomputed from bar:GetWidth() every
-- Refresh, so no diff caches need invalidating here.
function ReactCastBar:ApplyLayout()
  local p = (Nock.db and Nock.db.profile) or {}
  local h = tonumber(p.reactCastH)
  if not h or h <= 0 then h = REACT.CAST_H end
  self.frame:SetHeight(h)
  self.iconF:SetSize(h, h)
  local c = p.reactColorCastFill
  if type(c) ~= "table" or not c[1] then c = REACT.CAST_FILL end
  self.bar.fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  -- React media (reactBarTexture / reactFont / reactFontSize; "" / 9 = the
  -- reference skin).
  self.bar.fill:SetTexture(Nock.UI.GetReactBarTexture() or WHITE8X8)
  local font = Nock.UI.GetReactFont() or C.FONT.PATH
  local size = math.max(6, REACT.FONT + Nock.UI.GetReactFontDelta())
  Nock.UI.SafeSetFont(self.bar.nameText, font, size, "OUTLINE")
  Nock.UI.SafeSetFont(self.bar.timeText, font, size, "OUTLINE")
end

function ReactCastBar:Refresh(state)
  local p = Nock.db and Nock.db.profile
  -- Render-edge visibility gate; the producer publishes the wind-up regardless.
  -- On by default here — the glued cast bar is expected to show it — where the
  -- classic HUD leaves it opt-in.
  local c = Nock.CastBarSource(p and p.reactShowAutoShotCast ~= false)
  local show = p and Nock.HudIsReact() and p.reactShowCastBar ~= false and c
  if not show then
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

  -- Elapsed for casts, remaining for channels (Feign Death is published as a
  -- channel by Modules/CastBar.lua, so it drains here with no special code).
  local now = GetTime()
  local elapsed = now - c.startTime
  local progress
  if c.isChannel then
    progress = math.max(0, 1 - (elapsed / total))
  else
    progress = math.max(0, math.min(1, elapsed / total))
  end
  local maxW = (self.bar:GetWidth() or 2) - 2
  self.bar.fill:SetWidth(math.max(0.01, progress * maxW))

  local name = c.name or "?"
  if name ~= self._lastName then
    self.bar.nameText:SetText(name)
    self._lastName = name
  end
  -- Diff on deciseconds so the format only runs when the displayed value
  -- actually changes (~10x/s), not every tick.
  local rem = c.endTime - now
  if rem < 0 then rem = 0 end
  local decis = math.floor(rem * 10 + 0.5)
  if decis ~= self._lastTime then
    self.bar.timeText:SetText(string.format("%.1f", decis / 10))
    self._lastTime = decis
  end
end
