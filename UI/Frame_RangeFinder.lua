-- UI/Frame_RangeFinder.lua
-- Two-phase range bar (spec 2026-08-06): a finding ladder beyond ~10yd
-- (drain or block style) and a fill-toward-melee predictive weave bar inside
-- it, recolored per zone; center tick = melee boundary (glide mode only).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local RangeFinderView = Nock:NewModule("RangeFinderView", "AceEvent-3.0")
local C = Nock.Constants

-- Hardcoded fallbacks. Live colors come from Nock.db.profile.range*Color.
local DIM_COLOR = { 0.30, 0.30, 0.30, 1 }   -- grey: no valid target (not user-tunable)
local RESYNC_COLOR = { 1.00, 0.58, 0.10, 1 } -- orange: glide estimate degraded, awaiting
                                             -- a boundary crossing (not user-tunable)

-- Fallback colors when the profile hasn't stored one yet. rangeInColor's
-- fallback is the deadzone red (the stored default matches — see Defaults).
local FB_OUT     = { 1.00, 0.35, 0.54, 1.00 }
local FB_SWEET   = { 0.55, 0.95, 0.45, 1.00 }
local FB_PERFECT = { 0.10, 0.65, 0.20, 1.00 }
local FB_DEAD    = { 0.68, 0.18, 0.20, 1.00 }

-- Weave-coach stage looks: border tint + short LEFT-anchored label, driven by
-- state.weave.stage (Modules/WeaveCoach.lua). Not user-tunable, like DIM/RESYNC.
local STAGE_LOOK = {
  GO      = { label = "GO IN",    color = C.COLORS.NEXT_HIGHLIGHT },
  HOLD    = { label = "HOLD",     color = C.COLORS.WARN_AMBER },
  STRUCK  = { label = "BACK OUT", color = C.COLORS.WARN_BLUE },  -- keep holding!
  RELEASE = { label = "RELEASE",  color = C.COLORS.PROC_GLOW },
}

local function readColor(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if type(p) == "table" and #p >= 3 then return p end
  return fallback
end

function RangeFinderView:OnInitialize()
  local parent = Nock.parentFrame
  local sqH = C.DIM.RANGE_SQUARE_H
  -- Bar spans the full inner width of the HUD so it lines up with the other rows.
  local barWidth = C.DIM.HUD_WIDTH - 2 * C.DIM.OUTER_PAD

  local container = CreateFrame("Frame", "NockRangeFinder", parent)
  container:SetSize(barWidth, sqH)

  local outColor = readColor("rangeOutColor", FB_OUT)
  local bar = Nock.UI.CreateBar(container, "NockProximityBar", barWidth, sqH, outColor, nil, "rangeTrack")
  bar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  Nock.UI.SetBarFill(bar, 0.5)

  -- Center tick at 50% = melee boundary. Shown only in glide mode (the
  -- finding ladder has no melee mapping).
  local tick = bar:CreateTexture(nil, "OVERLAY", nil, 2)
  tick:SetTexture("Interface\\Buttons\\WHITE8X8")
  tick:SetVertexColor(1, 1, 1, 0.95)
  tick:SetWidth(2)
  tick:SetHeight(sqH + 4)
  tick:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bar.tick = tick

  local label = bar:CreateFontString(nil, "OVERLAY")
  label:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  label:SetPoint("CENTER")
  label:SetTextColor(unpack(C.COLORS.TEXT))
  label:SetText("")
  bar.label = label
  Nock.UI.RegisterFontString(label, "SIZE_OVERLAY", "OUTLINE")

  -- Weave-coach stage label. LEFT-anchored: CENTER belongs to the zone label.
  local stageLabel = bar:CreateFontString(nil, "OVERLAY")
  stageLabel:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  stageLabel:SetPoint("LEFT", bar, "LEFT", 4, 0)
  stageLabel:SetText("")
  bar.stageLabel = stageLabel
  Nock.UI.RegisterFontString(stageLabel, "SIZE_OVERLAY", "OUTLINE")

  self.bar = bar
  self.frame = container
  self._lastPaint, self._lastFill, self._lastLabel = nil, nil, nil
  self._lastStage, self._dispFill = nil, nil

  self:Relayout()
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyColors")
end

-- Apply the profile bar height to every height-dependent piece; the HUD
-- repacks its rows around the container via HUD:LayoutChildren.
function RangeFinderView:Relayout()
  local bar = self.bar
  if not bar then return end
  local h = Nock.db.profile.rangeFinderHeight or C.DIM.RANGE_SQUARE_H
  self.frame:SetHeight(h)
  bar:SetHeight(h)
  bar.tick:SetHeight(h + 4)
end

function RangeFinderView:ApplyColors()
  local bar = self.bar
  if not bar then return end
  self:Relayout()
  -- Invalidate the paint caches; the next Refresh re-applies fill color/label,
  -- and the fill width repaints in case the zoom mapping changed.
  self._lastPaint = nil
  self._lastFill = nil
  -- The weave-coach stage tint lives on this bar's BORDER, which the same
  -- message just repainted from the user's rangeTrack styling
  -- (Nock.UI.RefreshBarStyles). Drop the stage cache so the next Refresh
  -- re-asserts the tint instead of leaving it stomped until the stage changes.
  self._lastStage = nil
end

function RangeFinderView:Refresh(state)
  local bar = self.bar
  local t = state.target

  if not t.exists or not t.alive or t.friendly or not t.rangeState then
    if self._lastPaint ~= "_none" then
      Nock.UI.SetBarFill(bar, 0.5)
      bar.fill:SetVertexColor(unpack(DIM_COLOR))
      bar.label:SetText("")
      if bar.tick:IsShown() then bar.tick:Hide() end
      self._lastPaint = "_none"
      self._lastFill = 0.5
      self._dispFill = nil
      -- Drop the label cache so an identical first label on the next target
      -- still repaints (the old view's stuck-blank bug).
      self._lastLabel = nil
      bar.stageLabel:SetText("")
      Nock.UI.ApplyBarStyle(bar, "rangeTrack")
      self._lastStage = nil
    end
    return
  end

  local Engine = Nock.RangeEngine
  local now = GetTime()
  local dt = math.min(0.2, now - (self._lastT or now))
  self._lastT = now

  local mode, fill, color, label
  if t.rangeState == "LONG" then
    local b = t.rangeBracket and Engine.BRACKETS[t.rangeBracket]
    local style = Nock.db.profile.rangeFinderFindingStyle or "drain"
    if not b then
      -- Bracket not resolved yet (first ladder scan pending): dim fill, no text.
      mode, fill, color, label = "find", 0, FB_OUT, ""
    elseif style == "block" then
      mode, fill, color, label = "find|" .. t.rangeBracket, 1, b.block, b.label
    else
      -- Drain: ease the displayed fill toward the bracket's distance-remaining
      -- level so bracket steps still read as motion.
      self._dispFill = self._dispFill or b.fill
      self._dispFill = self._dispFill + (b.fill - self._dispFill) * math.min(1, dt * 12)
      mode, fill, color, label = "find|" .. t.rangeBracket, self._dispFill,
        readColor("rangeOutColor", FB_OUT), b.label
    end
  else
    self._dispFill = nil
    if t.rangeEstimateStale then
      mode, fill, color, label = "resync", 0.5, RESYNC_COLOR, "RESYNC"
    else
      -- Zoomed weave bar (experimental): centered viewport crop, tick stays
      -- put, movement reads rangeZoomLevel times bigger.
      local prog = t.rangeProg or -1
      local p = Nock.db.profile
      fill = p.rangeZoomedGlide and Engine.ZoomFill(prog, p.rangeZoomLevel)
             or ((prog + 1) / 2)
      if t.rangeState == "MELEE" then
        mode, color, label = "melee", readColor("rangeInColor", FB_DEAD), "DEAD ZONE"
      elseif t.rangeState == "SWEET" then
        if (t.rangeProg or -1) > Engine.PERFECT_AT then
          mode, color, label = "perfect", readColor("rangePerfectColor", FB_PERFECT), "PERFECT"
        else
          mode, color, label = "sweet", readColor("rangeCloseColor", FB_SWEET), "SWEET"
        end
      else
        mode, color, label = "close", readColor("rangeOutColor", FB_OUT), "CLOSE"
      end
    end
  end

  if mode ~= self._lastPaint then
    bar.fill:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    -- Tick only in glide mode ("find*" and "_none" hide it).
    local tickOn = mode:sub(1, 4) ~= "find"
    if tickOn ~= bar.tick:IsShown() then
      if tickOn then bar.tick:Show() else bar.tick:Hide() end
    end
    self._lastPaint = mode
  end
  if math.abs((self._lastFill or -1) - fill) > 0.003 then
    Nock.UI.SetBarFill(bar, fill)
    self._lastFill = fill
  end
  if label ~= self._lastLabel then
    bar.label:SetText(label)
    self._lastLabel = label
  end

  -- Weave-coach stage: border tint + LEFT label (nil stage = default look).
  -- "Default look" means the user's own rangeTrack border colour, not black --
  -- hence ApplyBarStyle rather than a hardcoded reset.
  local stage = state.weave and state.weave.stage
  if stage ~= self._lastStage then
    local look = STAGE_LOOK[stage]
    if look then
      local col = look.color
      bar:SetBackdropBorderColor(col[1], col[2], col[3], col[4] or 1)
      bar.stageLabel:SetText(look.label)
      bar.stageLabel:SetTextColor(col[1], col[2], col[3], 1)
    else
      Nock.UI.ApplyBarStyle(bar, "rangeTrack")
      bar.stageLabel:SetText("")
    end
    self._lastStage = stage
  end
end
