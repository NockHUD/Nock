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
  LATENCY   = { 1.00, 0.00, 0.00, 0.60 },
  TEXT      = { 1.00, 1.00, 1.00, 1.00 },
}

function ReactCastBar:OnInitialize()
  -- Glued directly onto the React cluster: parented + corner-anchored to it,
  -- so the cast bar matches reactWidth/reactScale, follows free-layout drags,
  -- and vanishes with the cluster in classic mode. The 1px overlap shares a
  -- border seam with the auto bar below (clamped, reference look).
  local cluster = Nock:GetModule("ReactCluster", true)
  local parent  = (cluster and cluster.frame) or Nock.parentFrame
  -- Laid out in whole device pixels by Nock.UI.LayoutIconBarRow (ApplyLayout):
  -- the panel welded on the cluster sharing one pixel row, the square icon
  -- box and the bar sharing one pixel column, fills one pixel inside.
  local panel = CreateFrame("Frame", "NockReactCastPanel", parent)
  panel:Hide()

  local iconF = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  Nock.UI.ApplyBackdrop(iconF, REACT.BAR_BG, REACT.BORDER)
  local icon = iconF:CreateTexture(nil, "ARTWORK")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local bar = CreateFrame("Frame", "NockReactCastBar", panel, "BackdropTemplate")
  Nock.UI.ApplyBackdrop(bar, REACT.BAR_BG, REACT.BORDER)

  -- Latency zone (reactCastLatency): pinned to the bar's right end, under the
  -- fill, which covers it as the cast runs -- Quartz's look.
  local lag = bar:CreateTexture(nil, "ARTWORK", nil, -1)
  lag:SetTexture(WHITE8X8)
  lag:Hide()
  bar.lag = lag

  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetTexture(WHITE8X8)
  fill:SetVertexColor(unpack(REACT.CAST_FILL))
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
  self.parent = parent
  self._lastName = nil
  self._lastTime = nil
  self._lastIcon = nil

  self:ApplyLayout()
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyLayout")
  self:RegisterMessage("NOCK_PIXEL_GRID_CHANGED", "ApplyLayout")   -- device-pixel seams
end

-- Skin overrides (React HUD tab): cast bar height (also the icon box edge)
-- and fill color. Fill width is recomputed from bar:GetWidth() every
-- Refresh, so no diff caches need invalidating here.
function ReactCastBar:ApplyLayout()
  local p = (Nock.db and Nock.db.profile) or {}
  local h = tonumber(p.reactCastH)
  if not h or h <= 0 then h = REACT.CAST_H end
  self._edge, self._dev = Nock.UI.LayoutIconBarRow(
    { panel = self.frame, iconF = self.iconF, icon = self.icon, bar = self.bar, fill = self.bar.fill, lag = self.bar.lag },
    self.parent, h)
  -- Fill colour is per source (cast vs Auto Shot wind-up): Refresh paints it
  -- through ApplyFillColor; clearing the cache here forces the repaint.
  self._fillKind = nil
  -- React media (reactBarTexture / reactFont / reactFontSize; "" / 9 = the
  -- reference skin).
  self.bar.fill:SetTexture(Nock.UI.GetReactBarTexture() or WHITE8X8)
  local font = Nock.UI.GetReactFont() or C.FONT.PATH
  local size = math.max(6, REACT.FONT + Nock.UI.GetReactFontDelta())
  local style = Nock.UI.GetReactFontStyle()
  Nock.UI.SafeSetFont(self.bar.nameText, font, size, style)
  Nock.UI.SafeSetFont(self.bar.timeText, font, size, style)
  Nock.UI.ApplyReactTextShadow(self.bar.nameText)
  Nock.UI.ApplyReactTextShadow(self.bar.timeText)
  local lc = p.reactColorCastLatency
  if type(lc) ~= "table" then lc = REACT.LATENCY end
  self.bar.lag:SetVertexColor(lc[1] or 1, lc[2] or 0, lc[3] or 0, lc[4] or 1)
  self._lagW = nil
end

-- The zone is sized once per cast with the latency at its start (Quartz and
-- AppelSwings do the same), and re-placed only when the device-pixel width
-- changes.
function ReactCastBar:PaintLatency(c, p, maxW, state)
  local lag = self.bar.lag
  if c.startTime ~= self._lagStart then
    self._lagStart = c.startTime
    self._lagSecs = ((state.network and state.network.latencyMs) or 0) / 1000
  end
  local w = 0
  if p.reactCastLatency == true then
    w = Nock.UI.DeviceRound(Nock.CastLatencyWidth(c, self._lagSecs, maxW), Nock.UI.PixelScale(self.bar))
  end
  if w == self._lagW then return end
  self._lagW = w
  if w > 0 then
    lag:SetWidth(w)
    lag:Show()
  else
    lag:Hide()
  end
end

-- Recolour the fill when the source flips between a real cast and the Auto
-- Shot wind-up (reactColorCastFill / reactColorAutoShotFill).
function ReactCastBar:ApplyFillColor(c)
  local kind = Nock.CastFillKind(c)
  if kind == self._fillKind then return end
  self._fillKind = kind
  local p = (Nock.db and Nock.db.profile) or {}
  local col = Nock.CastFillColor(p, kind, "reactColorCastFill", "reactColorAutoShotFill", REACT.CAST_FILL)
  self.bar.fill:SetVertexColor(col[1], col[2], col[3], col[4] or 1)
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

  self:ApplyFillColor(c)
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
  local barW = self.bar:GetWidth() or 2
  local e = self._edge or 1
  local maxW = barW - 2 * e
  self.bar.fill:SetWidth(Nock.UI.IconBarFillWidth(barW, progress, e, self._dev))
  self:PaintLatency(c, p, maxW, state)

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
