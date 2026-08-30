-- UI/Frame_SwingTimers.lua
-- Step indicator + ranged swing bar (yellow, with clip-zone ticks), melee swing bar (orange).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local SwingTimers = Nock:NewModule("SwingTimers", "AceEvent-3.0")
local C = Nock.Constants

local function spellIcon(id)
  if GetSpellInfo then
    local _, _, icon = GetSpellInfo(id)
    if icon then return icon end
  end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  if GetSpellTexture then return GetSpellTexture(id) end
  return nil
end

-- Decode the swing-bar direction into two independent axes:
--   isFill  = show elapsed (bar grows toward "ready") vs drain (show remaining)
--   reverse = anchor the fill to the RIGHT edge instead of the left
-- The four modes pair them up; the moving edge then sweeps:
--   "rtl"      drain,  left-anchored   → edge sweeps right → left   (default)
--   "ltr"      fill,   left-anchored   → edge sweeps left → right
--   "drainltr" drain,  right-anchored  → edge sweeps left → right
--   "fillrtl"  fill,   right-anchored  → edge sweeps right → left
--
-- `key` names a per-bar override; "inherit" (or an absent key) falls back to the
-- global swingFillDirection — which is what all three bars did before overrides
-- existed. Called with no key, this still returns the global mode unchanged.
local function fillMode(key)
  local p = Nock.db and Nock.db.profile
  local m = key and p and p[key]
  if not m or m == "inherit" then
    m = (p and p.swingFillDirection) or "rtl"
  end
  local isFill  = (m == "ltr" or m == "fillrtl")
  local reverse = (m == "drainltr" or m == "fillrtl")
  return isFill, reverse
end

local function delayEnabled()
  return Nock.db and Nock.db.profile and Nock.db.profile.autoShotDelayEnabled == true
end

function SwingTimers:OnInitialize()
  local parent = Nock.parentFrame
  local containerWidth = C.DIM.HUD_WIDTH - 2 * C.DIM.OUTER_PAD
  local rangedH  = C.DIM.RANGED_BAR_H
  local meleeH   = C.DIM.MELEE_BAR_H
  local gap      = C.DIM.INNER_GAP

  local container = CreateFrame("Frame", "NockSwingTimers", parent)

  -- Thin GCD sweep — sits just above the auto-shot bar (toggle + height + color
  -- in General settings). Same width as the ranged bar (right of the auto icon).
  -- Height/position/visibility are (re)applied by :ApplyLayout.
  local rangedW = containerWidth - rangedH - gap
  local gcd = Nock.UI.CreateBar(container, "NockGcdBar", rangedW, C.DIM.GCD_BAR_H, C.COLORS.GCD, nil, "gcdTrack")
  Nock.UI.SetBarFill(gcd, 0)
  gcd.text:SetText("")
  self.gcd = gcd

  -- Auto Shot icon (square, ranged bar height) to the left of the ranged bar.
  local autoIcon = container:CreateTexture(nil, "ARTWORK")
  autoIcon:SetSize(rangedH, rangedH)
  autoIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  autoIcon:SetTexture(spellIcon(C.SpellID.AUTO_SHOT))
  self.autoIcon = autoIcon

  -- Auto-shot bar — taller (RANGED_BAR_H = 20). The rotation profile name
  -- ("5:5:1:1" etc.) is centred on this bar via its built-in `text` field.
  local ranged = Nock.UI.CreateBar(container, "NockRangedSwing", rangedW, rangedH, C.COLORS.RANGED_SWING, "autoShotBarTexture", "autoShotTrack")
  Nock.UI.SetBarFill(ranged, 0)
  ranged.text:SetText("—")
  self._lastStepText = nil

  -- Clip-zone ticks: red = Steady would clip below this; orange = Multi would clip below this.
  local function makeTick(color)
    local t = ranged:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(unpack(color))
    t:SetWidth(2)
    t:SetHeight(rangedH)
    t:Hide()
    return t
  end
  ranged.tickSteady = makeTick({ 1.00, 0.10, 0.10, 1 })
  ranged.tickMulti  = makeTick({ 1.00, 0.65, 0.10, 1 })
  -- Wind-up mark: where the next Auto Shot COMMITS, 0.5s before the bar fills.
  -- Neutral, not a warning colour — it's a landmark, not a clip verdict.
  ranged.tickWindup = makeTick({ 0.85, 0.85, 0.85, 0.8 })

  -- Optional Auto Shot delay readout (ms, colour-coded) on the bar's right edge.
  -- Child of the ranged bar, so it hides automatically when the bar is hidden.
  local delayText = ranged:CreateFontString(nil, "OVERLAY")
  delayText:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  delayText:SetPoint("RIGHT", ranged, "RIGHT", -2, 0)
  delayText:SetText("")
  delayText:Hide()
  ranged.delayText = delayText
  self._lastDelayText = nil
  Nock.UI.RegisterFontString(delayText, "SIZE_OVERLAY", "OUTLINE")

  -- Raptor Strike icon to the left of the melee bar (sized to melee bar height).
  local raptorIcon = container:CreateTexture(nil, "ARTWORK")
  raptorIcon:SetSize(meleeH, meleeH)
  raptorIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  raptorIcon:SetTexture(spellIcon(C.SpellID.RAPTOR_STRIKE))
  self.raptorIcon = raptorIcon

  -- Melee swing bar — short, white, starts to the right of the raptor icon.
  local meleeW = containerWidth - meleeH - gap
  local melee = Nock.UI.CreateBar(container, "NockMeleeSwing", meleeW, meleeH, C.COLORS.MELEE_SWING, "meleeBarTexture", "meleeTrack")
  Nock.UI.SetBarFill(melee, 0)
  melee.text:SetText("")

  self.ranged = ranged
  self.melee = melee
  self.frame = container

  self:ApplyLayout()
  -- Toggling the GCD bar / changing its height or color (or the swing direction)
  -- comes through NOCK_VISUALS_CHANGED; re-apply the internal layout. The HUD's
  -- own handler relays out the grid in parallel (swingsH reads the same flags).
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyLayout")
end

-- Single source of truth for the swing-row geometry. Reads the profile and
-- returns every dimension/offset both :ApplyLayout and the HUD row-height calc
-- need, so the two can never drift. Pure (no side effects, no cached state):
--   * a hidden bar costs ZERO height
--   * INNER_GAP is added only BETWEEN the two bars (a lone bar has no padding)
--   * the per-bar left inset is (barH + gap) only when that bar AND its icon
--     show; otherwise 0, so the bar stretches full width
--   * the GCD sweep (when shown) sits on top with its tight trailing gap; when
--     the auto-shot bar is hidden that same gap spaces it from the melee bar.
function SwingTimers:Geometry()
  local p   = (Nock.db and Nock.db.profile) or {}
  local cw  = C.DIM.HUD_WIDTH - 2 * C.DIM.OUTER_PAD
  local gap = C.DIM.INNER_GAP

  local showAuto  = p.showAutoShotBar  ~= false
  local showMelee = p.showMeleeBar     ~= false
  local autoIcon  = p.autoShotShowIcon ~= false
  local meleeIcon = p.meleeShowIcon    ~= false
  local rangedH   = p.autoShotBarHeight or C.DIM.RANGED_BAR_H
  local meleeH    = p.meleeBarHeight    or C.DIM.MELEE_BAR_H
  local showGcd   = (p.showGcdBar ~= false)
  local gcdH      = p.gcdBarHeight or C.DIM.GCD_BAR_H

  local autoLeft  = (showAuto  and autoIcon)  and (rangedH + gap) or 0
  local meleeLeft = (showMelee and meleeIcon) and (meleeH  + gap) or 0

  local y = 0
  local yGcd, yAuto, yMelee
  if showGcd then yGcd = y; y = y + gcdH + C.DIM.GCD_BAR_GAP end
  if showAuto then yAuto = y; y = y + rangedH end
  if showMelee then
    if showAuto then y = y + gap end
    yMelee = y; y = y + meleeH
  end

  return {
    cw = cw, gap = gap,
    showAuto = showAuto, showMelee = showMelee,
    autoIcon = autoIcon, meleeIcon = meleeIcon,
    rangedH = rangedH, meleeH = meleeH,
    showGcd = showGcd, gcdH = gcdH,
    autoLeft = autoLeft, meleeLeft = meleeLeft, gcdLeft = autoLeft,
    yGcd = yGcd, yAuto = yAuto, yMelee = yMelee,
    total = math.max(y, 1),
  }
end

-- Logical (unscaled) height of the swing row, for HUD.swingsH().
function SwingTimers:ContentHeight()
  return self:Geometry().total
end

-- (Re)positions the GCD bar, the auto-shot bar + its icon + clip ticks, and the
-- melee bar + its icon, and sizes the container — all from :Geometry(). Each bar
-- can be hidden, drop its icon (then it stretches full width), and carry a custom
-- height. maxWidth is recomputed here because CreateBar cached it from the
-- icon-offset width; SetBarFill / PositionTicks both read it. All values are
-- unscaled logical px — the grid's per-row SetScale multiplies on top.
function SwingTimers:ApplyLayout()
  self._tickDevW = self._tickDevW or {}
  local f = self.frame
  local g = self:Geometry()
  local p = (Nock.db and Nock.db.profile) or {}
  local function paint(tex, c, fallback)
    c = c or fallback
    tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  end

  if g.showGcd then
    self.gcd:Show()
    self.gcd:SetHeight(g.gcdH)
    self.gcd.maxWidth = (g.cw - g.gcdLeft) - 2
    self.gcd:ClearAllPoints()
    self.gcd:SetPoint("TOPLEFT",  f, "TOPLEFT",  g.gcdLeft, -g.yGcd)
    self.gcd:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -g.yGcd)
    local c = (Nock.db and Nock.db.profile and Nock.db.profile.gcdBarColor) or C.COLORS.GCD
    self.gcd.fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  else
    self.gcd:Hide()
  end

  if g.showAuto then
    self.ranged:Show()
    self.ranged:SetHeight(g.rangedH)
    self.ranged.maxWidth = (g.cw - g.autoLeft) - 2
    self.ranged:ClearAllPoints()
    self.ranged:SetPoint("TOPLEFT",  f, "TOPLEFT",  g.autoLeft, -g.yAuto)
    self.ranged:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -g.yAuto)
    -- Profile-name text tracks the bar mid-line.
    self.ranged.text:ClearAllPoints()
    self.ranged.text:SetPoint("CENTER", f, "TOP", 0, -g.yAuto - g.rangedH / 2)
    self.ranged.tickSteady:SetHeight(g.rangedH)
    self.ranged.tickMulti:SetHeight(g.rangedH)
    self.ranged.tickWindup:SetHeight(g.rangedH)
    -- Widths (Classic HUD → Auto Shot bar) are DEVICE pixels, converted through
    -- the bar's effective scale. A logical pixel is not a screen pixel: at a UI
    -- scale of 0.5333 a 2-logical-px tick is 1.07 real pixels. See
    -- Nock.UI.DeviceWidth. A stored 0/nil must not collapse a tick to nothing,
    -- so anything non-positive falls back rather than being written through.
    local ps = Nock.UI.PixelScale(self.ranged)
    self._pixelScale = ps
    local function tickW(key)
      local v = tonumber(p[key])
      if not v or v <= 0 then v = 1 end
      self._tickDevW[key] = v
      return Nock.UI.DeviceWidth(v, ps)
    end
    self.ranged.tickSteady:SetWidth(tickW("clipTickSteadyWidth"))
    self.ranged.tickMulti:SetWidth(tickW("clipTickMultiWidth"))
    self.ranged.tickWindup:SetWidth(tickW("clipTickWindupWidth"))
    paint(self.ranged.fill,       p.autoShotBarColor,    C.COLORS.RANGED_SWING)
    paint(self.ranged.tickSteady, p.clipTickSteadyColor, { 1.00, 0.10, 0.10, 1 })
    paint(self.ranged.tickMulti,  p.clipTickMultiColor,  { 1.00, 0.65, 0.10, 1 })
    paint(self.ranged.tickWindup, p.clipTickWindupColor, { 0.85, 0.85, 0.85, 0.8 })
    if g.autoIcon then
      self.autoIcon:Show()
      self.autoIcon:SetSize(g.rangedH, g.rangedH)
      self.autoIcon:ClearAllPoints()
      self.autoIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -g.yAuto)
    else
      self.autoIcon:Hide()
    end
    if delayEnabled() then
      self.ranged.delayText:Show()
      self._lastDelayText = nil  -- force a re-render of the text/colour next tick
    else
      self.ranged.delayText:Hide()
    end
  else
    self.ranged:Hide()
    self.autoIcon:Hide()
    self.ranged.tickSteady:Hide()
    self.ranged.tickMulti:Hide()
    self.ranged.tickWindup:Hide()
  end

  if g.showMelee then
    self.melee:Show()
    self.melee:SetHeight(g.meleeH)
    paint(self.melee.fill, p.meleeBarColor, C.COLORS.MELEE_SWING)
    self.melee.maxWidth = (g.cw - g.meleeLeft) - 2
    self.melee:ClearAllPoints()
    self.melee:SetPoint("TOPLEFT",  f, "TOPLEFT",  g.meleeLeft, -g.yMelee)
    self.melee:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -g.yMelee)
    if g.meleeIcon then
      self.raptorIcon:Show()
      self.raptorIcon:SetSize(g.meleeH, g.meleeH)
      self.raptorIcon:ClearAllPoints()
      self.raptorIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -g.yMelee)
    else
      self.raptorIcon:Hide()
    end
  else
    self.melee:Hide()
    self.raptorIcon:Hide()
  end

  f:SetSize(g.cw, g.total)
  -- Direction may have changed too; force a re-anchor of the fills next Refresh.
  -- All three must be cleared — each bar caches its own anchor now, so missing
  -- one would leave that bar on its stale anchor until some unrelated layout
  -- change happened to invalidate it.
  self._fillRevRanged = nil
  self._fillRevMelee  = nil
  self._fillRevGcd    = nil
end

-- Place a clip tick at the moving edge's position when remaining == threshold.
-- Module-level (it was a closure built inside PositionTicks every rendered
-- frame): the edge value at that moment is (sd-threshold)/sd when filling
-- (elapsed) or threshold/sd when draining (remaining); a right-anchored bar
-- mirrors it (1-v). x is always measured from the bar's LEFT, so this covers
-- all four modes.
local EMPTY = {}
local function placeTick(bar, tick, threshold, devWidth, sd, isFill, reverse, ps)
  if threshold <= 0 then
    tick:Hide()
    return
  end
  -- A threshold past the whole swing means the cast never fits this cycle.
  -- Pin it to the cycle start rather than hiding: a missing tick reads as
  -- "no clip risk", which is the opposite of what's true. Reachable at high
  -- haste now that the wind-up is part of the threshold.
  if threshold > sd then threshold = sd end
  local v = isFill and ((sd - threshold) / sd) or (threshold / sd)
  local frac = reverse and (1 - v) or v
  -- Snapped to whole device pixels: an unsnapped centre splits the quad
  -- across two columns at half brightness, so the tick renders dimmer and
  -- narrower than its configured width and changes character whenever the
  -- threshold moves (haste, latency, a measured wind-up replacing the seed).
  local x = Nock.UI.PixelSnapCenter(frac * bar.maxWidth + 1, ps, devWidth)
  tick:ClearAllPoints()
  tick:SetPoint("CENTER", bar, "LEFT", x, 0)
  tick:Show()
end

function SwingTimers:PositionTicks(state)
  local bar = self.ranged
  local sd = state.ranged.swingDuration
  if sd <= 0 then
    bar.tickSteady:Hide()
    bar.tickMulti:Hide()
    bar.tickWindup:Hide()
    return
  end

  -- Shared with the rotation engine and the shot bars so the tick can never
  -- disagree with the "would this clip?" verdict. See Nock.ClipThreshold.
  local steadyClip = Nock.ClipThreshold(1.5)
  local multiClip  = Nock.ClipThreshold(0.5)

  -- Place a clip tick at the moving edge's position when remaining == threshold.
  -- The edge value at that moment is (sd-threshold)/sd when filling (elapsed) or
  -- threshold/sd when draining (remaining); a right-anchored bar mirrors it (1-v).
  -- x is always measured from the bar's LEFT, so this covers all four modes.
  -- The ticks live on the RANGED bar, so they must follow the ranged bar's own
  -- direction — a bare fillMode() here would read the global and mirror the ticks
  -- off the fill edge whenever the ranged bar overrides it.
  local isFill, reverse = fillMode("swingFillDirectionRanged")
  local ps   = self._pixelScale
  local devW = self._tickDevW or EMPTY
  placeTick(bar, bar.tickSteady, steadyClip, devW.clipTickSteadyWidth, sd, isFill, reverse, ps)
  placeTick(bar, bar.tickMulti,  multiClip,  devW.clipTickMultiWidth,  sd, isFill, reverse, ps)
  -- The moment the next Auto Shot commits: its wind-up begins here, not at the
  -- bar's 100%. Without this landmark the Auto Shot cast bar looks like it fires
  -- "early" — it doesn't, the bar just runs one wind-up past the commit point.
  -- state.ranged.windup is MEASURED (SwingTimer:UpdateWindup) because the wind-up
  -- is haste-scaled, so a constant would drift the mark under Rapid Fire.
  if Nock.db and Nock.db.profile and Nock.db.profile.showWindupMark == false then
    bar.tickWindup:Hide()
  else
    placeTick(bar, bar.tickWindup, state.ranged.windup or C.AUTO_SHOT_CAST,
              devW.clipTickWindupWidth, sd, isFill, reverse, ps)
  end
end

function SwingTimers:Refresh(state)
  -- Device-pixel tick widths are only right for the scale they were computed
  -- at, and the row's effective scale moves under us (UI scale, HUD scale).
  -- Cheap compare; ApplyLayout only runs when it actually changed.
  if Nock.UI.PixelScale(self.ranged) ~= self._pixelScale then self:ApplyLayout() end

  -- Auto-shot bar fill + the rotation notation centred on top of it (weave
  -- notation when weaving in range, otherwise the turret profile name). The
  -- notation text can be hidden on its own without hiding the bar.
  local p = Nock.db and Nock.db.profile
  local profileName
  if p and p.autoShotBarRotationText == false then
    profileName = ""
  else
    -- Passed through the user's rename map (blank = the built-in notation).
    -- Translated here at the render edge, not at the source, so state.rotation
    -- keeps reporting the real eWS bracket to the engine and the debug dump.
    local notation = state.rotation and (state.rotation.notation or state.rotation.profileName)
    profileName = (notation and Nock.Profiles and Nock.Profiles:DisplayName(notation)) or notation or "—"
    -- Per-notation color (nil = the bar text's default). Own numeric diff
    -- cache: color and text change independently (options edit vs proc flip).
    local r, g, b, a
    if notation and Nock.Profiles and Nock.Profiles.DisplayColor then
      r, g, b, a = Nock.Profiles:DisplayColor(notation)
    end
    if not r then
      local d = C.COLORS.TEXT
      r, g, b, a = d[1], d[2], d[3], d[4] or 1
    end
    if r ~= self._stepColR or g ~= self._stepColG
       or b ~= self._stepColB or a ~= self._stepColA then
      self.ranged.text:SetTextColor(r, g, b, a)
      self._stepColR, self._stepColG, self._stepColB, self._stepColA = r, g, b, a
    end
  end
  if profileName ~= self._lastStepText then
    self.ranged.text:SetText(profileName)
    self._lastStepText = profileName
  end

  -- Fill = elapsed (grows toward "ready"); drain = remaining. `reverse` anchors the
  -- fill to the right edge (the "inverse" modes). Each bar resolves its own mode,
  -- falling back to the global when set to "inherit" (the default — so by default
  -- all three still move together), and re-anchors only when ITS reverse changes.
  local isFillR, revR = fillMode("swingFillDirectionRanged")
  local isFillM, revM = fillMode("swingFillDirectionMelee")
  local isFillG, revG = fillMode("swingFillDirectionGcd")
  if revR ~= self._fillRevRanged then
    Nock.UI.SetBarFillReverse(self.ranged, revR)
    self._fillRevRanged = revR
  end
  if revM ~= self._fillRevMelee then
    Nock.UI.SetBarFillReverse(self.melee, revM)
    self._fillRevMelee = revM
  end
  if revG ~= self._fillRevGcd then
    Nock.UI.SetBarFillReverse(self.gcd, revG)
    self._fillRevGcd = revG
  end

  -- GCD sweep (only when shown). Drains/fills over the haste-scaled GCD.
  if self.gcd:IsShown() then
    local gd = state.gcd
    if gd and gd.duration > 0 and gd.remaining > 0 then
      local p = gd.remaining / gd.duration
      Nock.UI.SetBarFill(self.gcd, isFillG and (1 - p) or p)
    else
      Nock.UI.SetBarFill(self.gcd, 0)
    end
  end

  if self.ranged:IsShown() then
    local r = state.ranged
    if r.swingDuration > 0 and r.swingStart > 0 then
      local p = r.swingRemaining / r.swingDuration
      Nock.UI.SetBarFill(self.ranged, isFillR and (1 - p) or p)
    else
      Nock.UI.SetBarFill(self.ranged, 0)
    end
    self:PositionTicks(state)

    -- Auto Shot delay readout (seconds, colour-coded). Only repaint on change.
    local dt = self.ranged.delayText
    if dt:IsShown() then
      local sec = r.autoDelay or 0
      local txt = string.format("+%.2f", sec)
      if txt ~= self._lastDelayText then
        dt:SetText(txt)
        dt:SetTextColor(Nock.UI.DelaySeverityColor(sec))
        self._lastDelayText = txt
      end
    end
  end

  if self.melee:IsShown() then
    local m = state.melee
    if m.swingDuration > 0 and m.swingStart > 0 then
      local p = m.swingRemaining / m.swingDuration
      Nock.UI.SetBarFill(self.melee, isFillM and (1 - p) or p)
    else
      Nock.UI.SetBarFill(self.melee, 0)
    end
  end
end
