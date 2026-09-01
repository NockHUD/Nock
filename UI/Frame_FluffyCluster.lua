-- UI/Frame_FluffyCluster.lua
-- FluffyHUD bar stack (one HUD row): a transient cast bar welded above,
-- React-style converge Auto Shot bar with breakpoint ticks, fluffy shot
-- windows (ranged + melee lanes as separate rows), optional range finder.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local FluffyCluster = Nock:NewModule("FluffyCluster", "AceEvent-3.0")
local C = Nock.Constants

-- Reference FluffyHUD skin. Deliberately NOT wired to the GLOBAL barTexture /
-- fontFace — these frames never register with RegisterBarFill /
-- RegisterFontString, so RefreshMedia can't restyle them (React's channel
-- model). Fluffy media is its own pair: fluffyBarTexture / fluffyFont
-- ("" = this reference look), applied by ApplyLayout over the mediaFills /
-- mediaTexts rosters below. A curated subset (heights + every painted color)
-- can be overridden from the FluffyHUD options tab via the skinNum/skinColor
-- resolvers, whose profile defaults equal these constants.
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local FLUFFY = {
  CAST_H   = 14,
  SWING_H  = 12,
  RANGED_H = 18,
  MELEE_H  = 8,
  RANGE_H  = 12,
  GAP      = -1,  -- bars overlap their 1px borders → one shared black seam
  FONT     = 9,

  BAR_BG     = { 0.08, 0.08, 0.08, 0.90 },
  BORDER     = { 0.00, 0.00, 0.00, 1.00 },
  CAST_FILL  = { 0.40, 0.70, 1.00, 1.00 },
  SWING_FILL = { 1.00, 0.84, 0.00, 1.00 },  -- gold converge halves
  TICK_STEADY = { 1.00, 0.10, 0.10, 1.00 }, -- Steady clip threshold
  TICK_MULTI  = { 1.00, 0.65, 0.10, 1.00 }, -- Multi/instant clip threshold
  TICK_WINDUP = { 0.85, 0.85, 0.85, 0.80 }, -- wind-up commit landmark
  GCD_DIVIDER = { 0.62, 0.35, 0.98, 1.00 }, -- moving GCD divider (off by default)
  BRACKET     = { 1.00, 1.00, 1.00, 0.35 }, -- eWS bracket marks (off by default)

  -- Shot-window lanes: the classic shotBarsColor* palette on the flat skin.
  STEADY     = { 0.988, 0.596, 0.012, 0.85 },
  QUEUE      = { 0.988, 0.596, 0.012, 0.38 },
  QUEUE_LIVE = { 0.20, 0.90, 0.35, 0.90 },
  MULTI      = { 0.012, 0.525, 0.996, 0.85 },
  ARCANE     = { 0.686, 0.478, 0.773, 0.85 },
  DANGER     = { 0.851, 0.118, 0.118, 0.50 },
  RAPTOR     = { 0.153, 0.682, 0.376, 0.85 },
  WEAVE_AUTO = { 1.00, 1.00, 1.00, 0.70 },
  SPARK      = { 1.00, 1.00, 1.00, 1.00 },

  RANGE_MELEE  = { 0.68, 0.18, 0.20, 1.00 },
  RANGE_SUPER  = { 0.17, 0.78, 0.11, 1.00 },
  RANGE_SWEET  = { 0.85, 0.66, 0.00, 1.00 },
  RANGE_CLOSE  = { 0.00, 0.83, 0.75, 1.00 },
  RANGE_DIM    = { 0.30, 0.30, 0.30, 1.00 },
  RANGE_RESYNC = { 1.00, 0.58, 0.10, 1.00 },
  RANGE_DIVIDER   = { 1.00, 1.00, 1.00, 0.90 },
  RANGE_DIVIDER_W = 1,

  TEXT = { 1.00, 1.00, 1.00, 1.00 },
}

-- Span pool caps: how many tiles a lane can show at once. The engine's window
-- lists are bounded by the lookahead; these match ShotBars' practical maxima.
local MAX_SPANS    = 12  -- per window type per lane
local MAX_SPARKS   = 8
local MAX_BRACKETS = 12  -- 6 eWS bounds x 2 mirrored sides

local function profile()
  return (Nock.db and Nock.db.profile) or {}
end

-- Skin resolvers: profile override (FluffyHUD tab → Skin) or the reference
-- constant. Defaults.lua carries the same values, so the fallback only
-- guards pre-DB reads.
local function skinNum(key, ref)
  local v = tonumber(profile()[key])
  if v and v > 0 then return v end
  return ref
end

local function skinColor(key, ref)
  local c = profile()[key]
  if type(c) == "table" and c[1] then return c end
  return ref
end

-- Flat 1px-bordered bar shell with a dark fill background. No LSM
-- registration (fixed skin by construction; media via the fluffy keys only).
local function createFluffyBar(parent, name, h)
  local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
  f:SetHeight(h)
  Nock.UI.ApplyBackdrop(f, FLUFFY.BAR_BG, FLUFFY.BORDER)
  return f
end

-- Fluffy media rosters: every fill and text made below, re-skinned by
-- ApplyLayout from fluffyBarTexture / fluffyFont ("" = this reference look).
local mediaFills, mediaTexts = {}, {}

local function makeFill(bar, color)
  local t = bar:CreateTexture(nil, "ARTWORK")
  t:SetTexture(WHITE8X8)
  t:SetVertexColor(unpack(color))
  t:SetWidth(0.01)
  mediaFills[#mediaFills + 1] = t
  return t
end

local function makeText(bar, size, point, x)
  local fs = bar:CreateFontString(nil, "OVERLAY")
  fs:SetFont(C.FONT.PATH, size, "OUTLINE")
  fs:SetPoint(point, bar, point, x or 0, 0)
  fs:SetTextColor(unpack(FLUFFY.TEXT))
  fs:SetText("")
  mediaTexts[#mediaTexts + 1] = { fs = fs, size = size }
  return fs
end

-- A pool of plain WHITE8X8 strips on a lane (span tiles / sparks), hidden
-- until the painter places them. Colors are set per Refresh (a strip may be
-- reused for a different window type between frames).
local function makeStrips(bar, n, layer)
  local t = {}
  for i = 1, n do
    local s = bar:CreateTexture(nil, layer or "ARTWORK")
    s:SetTexture(WHITE8X8)
    s:Hide()
    t[i] = s
  end
  return t
end

-- A pool of square spell icons over a lane (fluffyShowLaneIcons): OVERLAY so
-- they paint above the span strips, cropped so the icon's baked border stays
-- out of a bar this small.
local function makeIcons(bar, n)
  local t = {}
  for i = 1, n do
    local s = bar:CreateTexture(nil, "OVERLAY")
    s:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    s:Hide()
    t[i] = s
  end
  return t
end

function FluffyCluster:OnInitialize()
  local parent = Nock.parentFrame
  local container = CreateFrame("Frame", "NockFluffyCluster", parent)
  self.frame = container

  -- The cast bar: a transient strip welded ABOVE the cluster (the React
  -- glued cast bar's shape — user gate round 2: "cast bar, hidden when not
  -- casting"). It never occupies a lane and hangs outside the cascade, so
  -- appearing cannot move the stack.
  local castBar = createFluffyBar(container, "NockFluffyCastBar", FLUFFY.CAST_H)
  castBar:SetPoint("BOTTOMLEFT",  container, "TOPLEFT",  0, -1)
  castBar:SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", 0, -1)
  castBar.fill = makeFill(castBar, FLUFFY.CAST_FILL)
  castBar.fill:SetPoint("TOPLEFT", castBar, "TOPLEFT", 1, -1)
  castBar.fill:SetPoint("BOTTOMLEFT", castBar, "BOTTOMLEFT", 1, 1)
  castBar.nameText = makeText(castBar, FLUFFY.FONT, "LEFT", 3)
  castBar.timeText = makeText(castBar, FLUFFY.FONT, "RIGHT", -3)
  castBar:Hide()
  self.castBar = castBar

  -- Auto Shot bar, the React look (user gate round 2: "react auto shot bar,
  -- with ticks/marks vertically for breakpoints"): two mirrored gold fills
  -- converging on the center at the fire moment, mirrored breakpoint tick
  -- pairs (Steady clip, Multi clip, wind-up commit) and the delay readout.
  local swing = createFluffyBar(container, "NockFluffySwing", FLUFFY.SWING_H)
  swing.fillL = makeFill(swing, FLUFFY.SWING_FILL)
  swing.fillL:SetPoint("TOPLEFT", swing, "TOPLEFT", 1, -1)
  swing.fillL:SetPoint("BOTTOMLEFT", swing, "BOTTOMLEFT", 1, 1)
  swing.fillR = makeFill(swing, FLUFFY.SWING_FILL)
  swing.fillR:SetPoint("TOPRIGHT", swing, "TOPRIGHT", -1, -1)
  swing.fillR:SetPoint("BOTTOMRIGHT", swing, "BOTTOMRIGHT", -1, 1)
  local function makeMark(color)
    local t = swing:CreateTexture(nil, "OVERLAY")
    t:SetTexture(WHITE8X8)
    t:SetVertexColor(unpack(color))
    t:SetSize(2, FLUFFY.SWING_H - 2)
    -- The engine's own texel snapping must not second-guess a quad we place
    -- on the device grid ourselves. Guarded: headless stubs lack the methods.
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    t:Hide()
    return t
  end
  swing.steadyL = makeMark(FLUFFY.TICK_STEADY)
  swing.steadyR = makeMark(FLUFFY.TICK_STEADY)
  swing.multiL  = makeMark(FLUFFY.TICK_MULTI)
  swing.multiR  = makeMark(FLUFFY.TICK_MULTI)
  swing.windupL = makeMark(FLUFFY.TICK_WINDUP)
  swing.windupR = makeMark(FLUFFY.TICK_WINDUP)
  -- GCD divider (fluffyShowGcdDivider, default off): the only MOVING mark on
  -- this bar — it rides the GCD's own progress the way the fill rides the
  -- swing, following fluffyDirAuto.
  swing.gcdL = makeMark(FLUFFY.GCD_DIVIDER)
  swing.gcdR = makeMark(FLUFFY.GCD_DIVIDER)
  -- eWS bracket marks (fluffyShowBrackets, default off): pooled, bounds from
  -- the live profile table.
  swing.brackets = {}
  for i = 1, MAX_BRACKETS do
    swing.brackets[i] = makeMark(FLUFFY.BRACKET)
  end
  swing.delayText    = makeText(swing, FLUFFY.FONT, "CENTER")
  swing.notationText = makeText(swing, FLUFFY.FONT, "RIGHT", -3)
  self.swing = swing

  -- Fluffy shot lanes: pooled strips over a time axis (state.shotpredict).
  local ranged = createFluffyBar(container, "NockFluffyRanged", FLUFFY.RANGED_H)
  ranged.strips = makeStrips(ranged, MAX_SPANS * 5)          -- steady/queue/multi/arcane/danger
  ranged.sparks = makeStrips(ranged, MAX_SPARKS, "OVERLAY")  -- Auto Shot releases
  ranged.icons  = makeIcons(ranged, MAX_SPANS * 3)           -- steady/multi/arcane
  self.ranged = ranged

  local melee = createFluffyBar(container, "NockFluffyMelee", FLUFFY.MELEE_H)
  melee.strips = makeStrips(melee, MAX_SPANS * 3)            -- weaveauto/raptor/weaveclip
  melee.icons  = makeIcons(melee, MAX_SPANS * 2)             -- weaveauto/raptor
  self.melee = melee

  -- Range finder: progressive fill toward the weave sweet spot, center tick =
  -- the melee boundary, bracket/RESYNC label. Rendering only — the data is
  -- the shared range engine's (state.target.*).
  local range = createFluffyBar(container, "NockFluffyRange", FLUFFY.RANGE_H)
  range.fill = makeFill(range, FLUFFY.RANGE_CLOSE)
  range.fill:SetPoint("TOPLEFT", range, "TOPLEFT", 1, -1)
  range.fill:SetPoint("BOTTOMLEFT", range, "BOTTOMLEFT", 1, 1)
  local tick = range:CreateTexture(nil, "OVERLAY")
  tick:SetTexture(WHITE8X8)
  tick:SetVertexColor(unpack(FLUFFY.RANGE_DIVIDER))
  tick:SetSize(FLUFFY.RANGE_DIVIDER_W, FLUFFY.RANGE_H - 2)
  tick:SetPoint("CENTER", range, "CENTER", 0, 0)
  range.tick = tick
  range.label = makeText(range, FLUFFY.FONT, "CENTER")
  self.range = range

  self:ApplyLayout()
  container:Hide()  -- HUD:ApplyRowVisibility shows it in fluffy mode
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyLayout")
end

-- Single source of truth for the cluster geometry (ReactCluster:Geometry's
-- pattern). Fixed top-to-bottom order: swing (which doubles as the cast
-- bar), ranged, melee, range — the FluffyHUD stack is a designed look, not
-- reorderable. Honors the fluffyShow* element toggles: a hidden sub-bar
-- costs zero height; GAP is only added between shown bars. Geometry NEVER
-- depends on whether a cast is running.
local ORDER = { "swing", "ranged", "melee", "range" }

function FluffyCluster:Geometry()
  local p = profile()
  local w = tonumber(p.fluffyWidth) or 320
  local show = {
    swing  = p.fluffyShowSwing  ~= false,
    ranged = p.fluffyShowRanged ~= false,
    melee  = p.fluffyShowMelee  ~= false,
    range  = p.fluffyShowRange  ~= false,
  }
  local h = {
    swing  = skinNum("fluffySwingH",  FLUFFY.SWING_H),
    ranged = skinNum("fluffyRangedH", FLUFFY.RANGED_H),
    melee  = skinNum("fluffyMeleeH",  FLUFFY.MELEE_H),
    range  = skinNum("fluffyRangeH",  FLUFFY.RANGE_H),
  }

  local ys = {}
  local y = 0
  for i = 1, #ORDER do
    local k = ORDER[i]
    if show[k] then
      if y > 0 then y = y + FLUFFY.GAP end
      ys[k] = y
      y = y + h[k]
    end
  end

  return {
    w = w,
    showSwing = show.swing, showRanged = show.ranged,
    showMelee = show.melee, showRange = show.range,
    ySwing = ys.swing, yRanged = ys.ranged,
    yMelee = ys.melee, yRange = ys.range,
    hSwing = h.swing, hRanged = h.ranged,
    hMelee = h.melee, hRange = h.range,
    total = math.max(y, 1),
  }
end

-- Logical (unscaled) height of the row, for HUD's LAYOUT height fn.
function FluffyCluster:ContentHeight()
  return self:Geometry().total
end

-- (Re)size and (re)anchor everything from Geometry, then invalidate every diff
-- cache so the next Refresh repaints against the new dimensions.
function FluffyCluster:ApplyLayout()
  local g = self:Geometry()
  local f = self.frame
  f:SetSize(g.w, g.total)
  self._innerW = g.w - 2
  self._halfW  = (g.w - 2) / 2

  local function placeBar(bar, y, h, shown)
    bar:SetHeight(h)
    if shown then
      bar:ClearAllPoints()
      bar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -y)
      bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
      bar:Show()
    else
      bar:Hide()
    end
  end
  placeBar(self.swing,  g.ySwing,  g.hSwing,  g.showSwing)
  placeBar(self.ranged, g.yRanged, g.hRanged, g.showRanged)
  placeBar(self.melee,  g.yMelee,  g.hMelee,  g.showMelee)
  placeBar(self.range,  g.yRange,  g.hRange,  g.showRange)

  -- Fluffy media (FluffyHUD tab → Skin): fluffyBarTexture on the fills,
  -- fluffyFont/fluffyFontSize on the texts; "" = the reference skin
  -- (WHITE8X8 / C.FONT.PATH). Vertex colors survive SetTexture.
  local tex  = (Nock.UI.GetFluffyBarTexture and Nock.UI.GetFluffyBarTexture()) or WHITE8X8
  local font = (Nock.UI.GetFluffyFont and Nock.UI.GetFluffyFont()) or C.FONT.PATH
  local dSz  = (Nock.UI.GetFluffyFontDelta and Nock.UI.GetFluffyFontDelta()) or 0
  for i = 1, #mediaFills do mediaFills[i]:SetTexture(tex) end
  for i = 1, #mediaTexts do
    local e = mediaTexts[i]
    e.fs:SetFont(font, math.max(6, e.size + dSz), "OUTLINE")
  end

  -- Static skin colors ApplyLayout owns (Refresh owns the dynamic ones).
  local swing = self.swing
  local p = profile()
  local fillCol = skinColor("fluffyColorSwingFill", FLUFFY.SWING_FILL)
  swing.fillL:SetVertexColor(fillCol[1], fillCol[2], fillCol[3], fillCol[4] or 1)
  swing.fillR:SetVertexColor(fillCol[1], fillCol[2], fillCol[3], fillCol[4] or 1)
  local markH = math.max(1, g.hSwing - 2)
  local function skinMark(tL, tR, key, ref)
    local c = skinColor(key, ref)
    tL:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    tR:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    tL:SetHeight(markH)
    tR:SetHeight(markH)
  end
  skinMark(swing.steadyL, swing.steadyR, "fluffyColorTickSteady", FLUFFY.TICK_STEADY)
  skinMark(swing.multiL,  swing.multiR,  "fluffyColorTickMulti",  FLUFFY.TICK_MULTI)
  skinMark(swing.windupL, swing.windupR, "fluffyColorTickWindup", FLUFFY.TICK_WINDUP)
  skinMark(swing.gcdL,    swing.gcdR,    "fluffyColorGcdDivider", FLUFFY.GCD_DIVIDER)
  do
    local bc = skinColor("fluffyColorBracket", FLUFFY.BRACKET)
    for i = 1, MAX_BRACKETS do
      swing.brackets[i]:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 1)
      swing.brackets[i]:SetHeight(markH)
    end
  end

  -- Fill direction (fluffyDirAuto): converge (reference) | ltr | rtl —
  -- fillL doubles as the single directional fill, fillR only participates
  -- in converge mode (React's exact scheme).
  self._dirAuto = p.fluffyDirAuto or "converge"
  swing.fillL:ClearAllPoints()
  if self._dirAuto == "rtl" then
    swing.fillL:SetPoint("TOPRIGHT", swing, "TOPRIGHT", -1, -1)
    swing.fillL:SetPoint("BOTTOMRIGHT", swing, "BOTTOMRIGHT", -1, 1)
  else
    swing.fillL:SetPoint("TOPLEFT", swing, "TOPLEFT", 1, -1)
    swing.fillL:SetPoint("BOTTOMLEFT", swing, "BOTTOMLEFT", 1, 1)
  end
  if self._dirAuto == "converge" then
    swing.fillR:Show()
  else
    swing.fillR:Hide()
  end

  -- Feature-gated texts: hidden here so their painters can early-out on
  -- IsShown alone.
  if p.fluffyShowDelay == true then swing.delayText:Show()
  else swing.delayText:Hide(); swing.delayText:SetText("") end
  if p.fluffyShowNotation ~= false then swing.notationText:Show()
  else swing.notationText:Hide(); swing.notationText:SetText("") end

  self.castBar:SetHeight(skinNum("fluffyCastH", FLUFFY.CAST_H))
  local castCol = skinColor("fluffyColorCastFill", FLUFFY.CAST_FILL)
  self.castBar.fill:SetVertexColor(castCol[1], castCol[2], castCol[3], castCol[4] or 1)
  self.range.tick:SetHeight(math.max(1, g.hRange - 2))

  -- Repaint from scratch next Refresh.
  self._castName, self._castTime = nil, nil
  self._swingP, self._swingSd, self._swingWindup = nil, nil, nil
  self._swingSteadyT, self._swingMultiT = nil, nil
  self._swingBarLeft, self._swingDelay = nil, nil
  self._gcdX, self._notation = nil, nil
  self._noteColR, self._noteColG, self._noteColB, self._noteColA = nil, nil, nil, nil
  self._rangeMode, self._rangeRatio, self._rangeText = nil, nil, nil
  self._lanesOn = nil
  self._hRanged, self._hMelee = g.hRanged, g.hMelee
end

-- The transient cast bar: shown only while something casts (or the Auto Shot
-- wind-up, behind fluffyShowAutoShotCast — a render-edge gate, the producer
-- publishes regardless; project rule). A cast fills left-to-right, a channel
-- drains (Feign Death is published as a channel by Modules/CastBar, so it
-- drains for free). fluffyShowCast is the whole bar's master switch.
local function refreshCastBar(self)
  local bar = self.castBar
  local p = profile()
  local c
  if p.fluffyShowCast ~= false then
    c = Nock.CastBarSource(p.fluffyShowAutoShotCast ~= false)
  end
  if not c or (c.endTime - c.startTime) <= 0 then
    if bar:IsShown() then
      bar:Hide()
      self._castName, self._castTime = nil, nil
    end
    return
  end
  if not bar:IsShown() then bar:Show() end

  local total = c.endTime - c.startTime
  local now = GetTime()
  local elapsed = now - c.startTime
  local progress
  if c.isChannel then
    progress = math.max(0, 1 - elapsed / total)
  else
    progress = math.max(0, math.min(1, elapsed / total))
  end
  bar.fill:SetWidth(math.max(0.01, progress * (self._innerW or 1)))

  local name = c.name or "?"
  if name ~= self._castName then
    bar.nameText:SetText(name)
    self._castName = name
  end
  -- Diff on deciseconds so the format only runs when the displayed value
  -- actually changes (~10x/s), not every tick.
  local rem = c.endTime - now
  if rem < 0 then rem = 0 end
  local decis = math.floor(rem * 10 + 0.5)
  if decis ~= self._castTime then
    bar.timeText:SetText(string.format("%.1f", decis / 10))
    self._castTime = decis
  end
end

-- Mirrored breakpoint tick pairs on the converge auto bar, through the same
-- shared projection the React marks place through (absolute-pixel snapped).
-- Thresholds come from the shared Nock.ClipThreshold, same as every other
-- surface — never inlined arithmetic (project rule).
local function positionSwingMarks(self, sd, steadyT, multiT, windup)
  local bar = self.swing
  local dir = self._dirAuto or "converge"
  local ps = Nock.UI.PixelScale(bar)
  local devW = Nock.UI.DeviceWidth(2, ps)
  local barLeft, barRight = bar:GetLeft(), bar:GetRight()
  local leftPx  = (ps and barLeft) and barLeft * ps or nil
  local rightPx = (ps and barRight) and barRight * ps or nil
  local halfW, innerW = self._halfW or 0, self._innerW or 0
  local function placeAt(tL, tR, frac)
    local edge, x, mirrored, xR = Nock.UI.ReactAxisPoint(
      frac, dir, halfW, innerW, ps, devW, leftPx, rightPx)
    tL:SetWidth(devW)
    tR:SetWidth(devW)
    tL:ClearAllPoints(); tL:SetPoint("CENTER", bar, edge, x, 0); tL:Show()
    if mirrored then
      tR:ClearAllPoints(); tR:SetPoint("CENTER", bar, "RIGHT", -xR, 0); tR:Show()
    else
      tR:Hide()
    end
  end
  local function placePair(tL, tR, T)
    if not sd or sd <= 0 or not T or T <= 0 or T >= sd then
      tL:Hide(); tR:Hide()
      return
    end
    placeAt(tL, tR, (sd - T) / sd)
  end
  -- The vertical marks are individually hideable: fluffyShowClipTicks owns
  -- the Steady/Multi pairs, the SHARED showWindupMark owns the commit mark.
  if profile().fluffyShowClipTicks == false then
    bar.steadyL:Hide(); bar.steadyR:Hide()
    bar.multiL:Hide();  bar.multiR:Hide()
  else
    placePair(bar.steadyL, bar.steadyR, steadyT)
    placePair(bar.multiL,  bar.multiR,  multiT)
  end
  if profile().showWindupMark == false then
    bar.windupL:Hide(); bar.windupR:Hide()
  else
    placePair(bar.windupL, bar.windupR, windup)
  end

  -- eWS bracket marks — bounds from the live profile table, never hardcoded.
  -- Pooled textures; surplus ones hidden. Feature-gated (fluffyShowBrackets,
  -- default off): all six bounds at once read as noise.
  local n = 0
  local list = (Nock.Profiles and Nock.Profiles.list) or {}
  if sd and sd > 0 and profile().fluffyShowBrackets == true then
    for i = 1, #list do
      local lo = list[i].lo
      if lo and lo > 0 and lo < sd then
        local edge, x, mirrored, xR = Nock.UI.ReactAxisPoint(
          lo / sd, dir, halfW, innerW, ps, devW, leftPx, rightPx)
        if mirrored then
          if n + 2 > MAX_BRACKETS then break end
          local bL, bR = bar.brackets[n + 1], bar.brackets[n + 2]
          bL:SetWidth(devW); bR:SetWidth(devW)
          bL:ClearAllPoints(); bL:SetPoint("CENTER", bar, edge, x, 0); bL:Show()
          bR:ClearAllPoints(); bR:SetPoint("CENTER", bar, "RIGHT", -xR, 0); bR:Show()
          n = n + 2
        else
          if n + 1 > MAX_BRACKETS then break end
          local b = bar.brackets[n + 1]
          b:SetWidth(devW)
          b:ClearAllPoints(); b:SetPoint("CENTER", bar, edge, x, 0); b:Show()
          n = n + 1
        end
      end
    end
  end
  for i = n + 1, MAX_BRACKETS do
    bar.brackets[i]:Hide()
  end
end

-- Auto Shot bar painter, the React converge look: p=0 at swing start (both
-- halves empty), p=1 at the fire moment (halves meet at center). Gating via
-- Nock.AutoSwingLive — a swing in flight always draws; expired only stays
-- full in combat while auto is still armed (held shot); disarmed or out of
-- combat a stale swing doesn't sit solid gold.
local function refreshSwing(self, state)
  local bar = self.swing
  if not bar:IsShown() then return end
  local r = state.ranged

  local p01 = 0
  if Nock.AutoSwingLive() then
    p01 = 1 - (r.swingRemaining / r.swingDuration)
    if p01 < 0 then p01 = 0 elseif p01 > 1 then p01 = 1 end
  end
  if not self._swingP or math.abs(p01 - self._swingP) > 0.002 then
    if (self._dirAuto or "converge") == "converge" then
      local w = math.max(0.01, p01 * (self._halfW or 0))
      bar.fillL:SetWidth(w)
      bar.fillR:SetWidth(w)
    else
      -- Directional single fill across the full inner width (fillR hidden).
      bar.fillL:SetWidth(math.max(0.01, p01 * (self._innerW or 0)))
    end
    self._swingP = p01
  end

  -- Marks reposition only when their inputs change (the bar's left edge is
  -- an input: positions snap in absolute screen space).
  local sd = r.swingDuration
  local windup = r.windup or C.AUTO_SHOT_CAST
  local steadyT = Nock.ClipThreshold(1.5)
  local multiT  = Nock.ClipThreshold(0.5)
  local barLeft = bar:GetLeft()
  if sd ~= self._swingSd or steadyT ~= self._swingSteadyT
     or multiT ~= self._swingMultiT or windup ~= self._swingWindup
     or barLeft ~= self._swingBarLeft then
    positionSwingMarks(self, sd, steadyT, multiT, windup)
    self._swingSd, self._swingSteadyT, self._swingMultiT = sd, steadyT, multiT
    self._swingWindup, self._swingBarLeft = windup, barLeft
  end

  -- GCD divider (fluffyShowGcdDivider): the only moving mark — diff on the
  -- snapped pixel offset so it re-anchors once per device pixel, not per tick.
  if profile().fluffyShowGcdDivider == true then
    local frac = Nock.UI.ReactGcdFrac(state.gcd)
    if not frac then
      if self._gcdX ~= nil then
        bar.gcdL:Hide(); bar.gcdR:Hide()
        self._gcdX = nil
      end
    else
      local ps = Nock.UI.PixelScale(bar)
      local devW = Nock.UI.DeviceWidth(2, ps)
      local bL, bR = bar:GetLeft(), bar:GetRight()
      local edge, x, mirrored, xR = Nock.UI.ReactAxisPoint(
        frac, self._dirAuto or "converge", self._halfW or 0, self._innerW or 0,
        ps, devW, (ps and bL) and bL * ps or nil, (ps and bR) and bR * ps or nil)
      if x ~= self._gcdX then
        self._gcdX = x
        bar.gcdL:SetWidth(devW)
        bar.gcdL:ClearAllPoints()
        bar.gcdL:SetPoint("CENTER", bar, edge, x, 0)
        bar.gcdL:Show()
        if mirrored then
          bar.gcdR:SetWidth(devW)
          bar.gcdR:ClearAllPoints()
          bar.gcdR:SetPoint("CENTER", bar, "RIGHT", -xR, 0)
          bar.gcdR:Show()
        else
          bar.gcdR:Hide()
        end
      end
    end
  elseif self._gcdX ~= nil then
    bar.gcdL:Hide(); bar.gcdR:Hide()
    self._gcdX = nil
  end

  -- Rotation notation, through the user's rename map at the render edge
  -- (state.rotation keeps the real bracket for the engine). Gated by
  -- fluffyShowNotation (ApplyLayout hides the string).
  if bar.notationText:IsShown() then
    local notation = state.rotation and (state.rotation.notation or state.rotation.profileName)
    local name = (notation and Nock.Profiles and Nock.Profiles.DisplayName
                  and Nock.Profiles:DisplayName(notation)) or notation or "—"
    if name ~= self._notation then
      bar.notationText:SetText(name)
      self._notation = name
    end
    local nr, ng, nb, na
    if notation and Nock.Profiles and Nock.Profiles.DisplayColor then
      nr, ng, nb, na = Nock.Profiles:DisplayColor(notation)
    end
    if not nr then
      nr, ng, nb, na = FLUFFY.TEXT[1], FLUFFY.TEXT[2], FLUFFY.TEXT[3], FLUFFY.TEXT[4]
    end
    if nr ~= self._noteColR or ng ~= self._noteColG
       or nb ~= self._noteColB or na ~= self._noteColA then
      bar.notationText:SetTextColor(nr, ng, nb, na)
      self._noteColR, self._noteColG, self._noteColB, self._noteColA = nr, ng, nb, na
    end
  end

  -- Delay readout (seconds late vs one weapon-speed cycle). Feature-gated
  -- (fluffyShowDelay, default off — ApplyLayout hides the string). autoDelay
  -- only moves when a shot fires — diff on the raw number.
  if bar.delayText:IsShown() then
    local sec = r.autoDelay or 0
    if sec ~= self._swingDelay then
      self._swingDelay = sec
      if sec > 0 then
        bar.delayText:SetText(string.format("+%.2f", sec))
        bar.delayText:SetTextColor(Nock.UI.DelaySeverityColor(sec))
      else
        bar.delayText:SetText("")
      end
    end
  end
end

-- Shot lanes: pooled strips over state.shotpredict's span lists (the fluffy
-- take on Frame_ShotBars' walk — same pixel snapping, same lockout clip, two
-- visually separate rows instead of one split frame). Draw order per lane is
-- layering: later types paint over earlier ones where spans touch.
local RANGED_KEYS = { "steady", "queue", "multi", "arcane", "danger" }
local MELEE_KEYS  = { "weaveauto", "raptor", "weaveclip" }
local LANE_KEY = {
  steady = "fluffyColorSteady",  queue = "fluffyColorQueue",
  multi  = "fluffyColorMulti",   arcane = "fluffyColorArcane",
  danger = "fluffyColorDanger",  raptor = "fluffyColorRaptor",
  weaveauto = "fluffyColorWeaveAuto", weaveclip = "fluffyColorDanger",
}
local LANE_REF = {
  steady = FLUFFY.STEADY, queue = FLUFFY.QUEUE, multi = FLUFFY.MULTI,
  arcane = FLUFFY.ARCANE, danger = FLUFFY.DANGER, raptor = FLUFFY.RAPTOR,
  weaveauto = FLUFFY.WEAVE_AUTO, weaveclip = FLUFFY.DANGER,
}

-- Lane spell icons (fluffyShowLaneIcons): the ability a window represents.
-- Queue and the danger/weaveclip bands are windows, not presses — no icon.
local LANE_ICON_SPELL = {
  steady    = "STEADY_SHOT",
  multi     = "MULTI_SHOT",
  arcane    = "ARCANE_SHOT",
  raptor    = "RAPTOR_STRIKE",
  weaveauto = "ATTACK",
}
local laneIconTex = {}  -- lane key → texture, cached on first successful fetch
local function laneIcon(k)
  local tex = laneIconTex[k]
  if tex then return tex end
  local ref = LANE_ICON_SPELL[k]
  if not ref then return nil end
  local id = C.SpellID[ref]
  if C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(id)
  elseif GetSpellTexture then tex = GetSpellTexture(id) end
  laneIconTex[k] = tex
  return tex
end

local function hidePool(pool, from)
  for i = from, #pool do
    if pool[i]:IsShown() then pool[i]:Hide() end
  end
end

-- One lane's walk. minX (px, optional) clips at the GCD/cast lockout —
-- windows touching the fire edge means the GCD is free. Strip colors are set
-- every draw: the pool is shared across window types between frames.
local function drawSpans(self, bar, keys, sp, now, scale, h, minX, showIcons)
  local innerW = self._innerW or 0
  local pool = bar.strips
  local icons = bar.icons
  local drawn, nIcons = 0, 0
  for ki = 1, #keys do
    local k = keys[ki]
    local list = sp.windows[k]
    local n = (list and list.n) or 0
    local col = skinColor(LANE_KEY[k], LANE_REF[k])
    local qLive
    if k == "queue" then
      qLive = skinColor("fluffyColorQueueLive", FLUFFY.QUEUE_LIVE)
    end
    for i = 1, n do
      if drawn >= #pool then break end
      local span = list[i]
      local x1 = (span.s - now) * scale
      local x2 = (span.e - now) * scale
      if x1 < 0 then x1 = 0 end
      if minX and x1 < minX then x1 = minX end
      if x2 > innerW then x2 = innerW end
      -- Snap edges to the pixel grid: tiled windows share an exact boundary
      -- time so they round identically (no gap/overlap, no right-edge shimmer).
      x1 = math.floor(x1 + 0.5)
      x2 = math.floor(x2 + 0.5)
      if x2 > innerW then x2 = innerW end
      if x2 - x1 >= 1 and h > 0 then
        drawn = drawn + 1
        local t = pool[drawn]
        -- Queue lane: green once the window is LIVE — the wind-up has begun,
        -- a press right now is queued for free. Projections stay dim.
        local c = (qLive and span.s <= now) and qLive or col
        t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", bar, "TOPLEFT", 1 + x1, -1)
        t:SetSize(x2 - x1, h)
        t:Show()
        -- The ability's icon on the span's left edge — only in a span wide
        -- enough to hold it whole; slivers stay bare.
        if showIcons and icons and nIcons < #icons and (x2 - x1) >= h then
          local tex = laneIcon(k)
          if tex then
            nIcons = nIcons + 1
            local ic = icons[nIcons]
            ic:SetTexture(tex)
            ic:ClearAllPoints()
            ic:SetPoint("TOPLEFT", bar, "TOPLEFT", 1 + x1, -1)
            ic:SetSize(h, h)
            ic:Show()
          end
        end
      end
    end
  end
  hidePool(pool, drawn + 1)
  if icons then hidePool(icons, nIcons + 1) end
end

local function refreshLanes(self, state)
  local rangedBar, meleeBar = self.ranged, self.melee
  local rOn = rangedBar:IsShown()
  local mOn = meleeBar:IsShown()
  if not rOn and not mOn then return end

  local sp = state.shotpredict
  if not sp or not sp.active then
    if self._lanesOn ~= false then
      hidePool(rangedBar.strips, 1)
      hidePool(rangedBar.sparks, 1)
      hidePool(rangedBar.icons, 1)
      hidePool(meleeBar.strips, 1)
      hidePool(meleeBar.icons, 1)
      self._lanesOn = false
    end
    return
  end
  self._lanesOn = true
  local showIcons = profile().fluffyShowLaneIcons == true

  -- Render against the timestamp the engine anchored the spans to, not a
  -- fresh GetTime() — avoids the per-tick right-edge jitter.
  local now = sp.now or GetTime()
  local innerW = self._innerW or 0
  local winSec = sp.windowSec
  if not winSec or winSec <= 0 then winSec = 6.0 end
  local scale = innerW / winSec

  -- Lockout front: ranged windows are clipped at the GCD/cast edge. Real
  -- casts only — the wind-up (state.player.autoShotCast) is the free queue
  -- window, not a lockout (clipping at it blanked the last stretch of every
  -- cycle once; project rule). The melee lane is deliberately unclipped —
  -- Raptor isn't GCD-bound.
  local lock = (state.gcd and state.gcd.remaining) or 0
  local cast = state.player and state.player.casting
  if cast and cast.endTime and (cast.endTime - now) > lock then
    lock = cast.endTime - now
  end
  local lockPx = math.floor(lock * scale + 0.5)
  if lockPx > innerW then lockPx = innerW end
  if lockPx <= 0 then lockPx = nil end

  if rOn then
    local h = math.max(1, (self._hRanged or FLUFFY.RANGED_H) - 2)
    drawSpans(self, rangedBar, RANGED_KEYS, sp, now, scale, h, lockPx, showIcons)

    -- Auto Shot sparks: full lane height, on top.
    local sparkCol = skinColor("fluffyColorSpark", FLUFFY.SPARK)
    local ns = sp.nSparks or 0
    local shown = 0
    for i = 1, ns do
      if shown >= #rangedBar.sparks then break end
      local x = (sp.sparks[i] - now) * scale
      if x >= 0 and x <= innerW then
        x = math.floor(x + 0.5)
        shown = shown + 1
        local t = rangedBar.sparks[shown]
        t:SetVertexColor(sparkCol[1], sparkCol[2], sparkCol[3], sparkCol[4] or 1)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", rangedBar, "TOPLEFT", 1 + x, -1)
        t:SetSize(1, h)
        t:Show()
      end
    end
    hidePool(rangedBar.sparks, shown + 1)
  end

  if mOn then
    local h = math.max(1, (self._hMelee or FLUFFY.MELEE_H) - 2)
    drawSpans(self, meleeBar, MELEE_KEYS, sp, now, scale, h, nil, showIcons)
  end
end

-- Range sub-bar painter — rendering only, consuming the shared engine's
-- published fields (RefreshRange's exact branch, the classic bar's third
-- sibling). Finding phase honors rangeFinderFindingStyle — drain (eased fill,
-- bracket-colored label) or block (solid bracket fill, white label); glide
-- phase honors the zoom keys; RESYNC parks orange at the tick.
local function refreshRange(self, state)
  local range = self.range
  if not range:IsShown() then return end
  local t = state.target

  if not t or not t.exists or not t.alive or t.friendly or not t.rangeState then
    if self._rangeMode ~= "none" then
      range.fill:SetWidth(0.01)
      range.fill:SetVertexColor(unpack(FLUFFY.RANGE_DIM))
      range.label:SetText("")
      self._rangeMode = "none"
      self._rangeRatio, self._rangeText, self._rangeDispFill = nil, nil, nil
    end
    return
  end

  local Engine = Nock.RangeEngine
  local p = profile()
  local mode, ratio, color, text, textColor
  if t.rangeState == "LONG" then
    local b = t.rangeBracket and Engine.BRACKETS[t.rangeBracket]
    local style = p.rangeFinderFindingStyle or "drain"
    if not b then
      -- First ladder scan pending: dim, empty, no text.
      mode, ratio, color, text = "find", 0, FLUFFY.RANGE_DIM, ""
    elseif style == "block" then
      mode, ratio, color = "findb|" .. t.rangeBracket, 1, b.block
      text, textColor = b.label, FLUFFY.TEXT
    else
      -- Drain: ease the displayed fill toward the bracket's level so bracket
      -- steps read as motion (same easing as both existing bars).
      local now = GetTime()
      local dt = math.min(0.2, now - (self._rangeDispT or now))
      self._rangeDispT = now
      self._rangeDispFill = self._rangeDispFill or b.fill
      self._rangeDispFill = self._rangeDispFill + (b.fill - self._rangeDispFill) * math.min(1, dt * 12)
      mode, ratio, color = "findd|" .. t.rangeBracket, self._rangeDispFill,
                           skinColor("fluffyColorRangeClose", FLUFFY.RANGE_CLOSE)
      text, textColor = b.label, b.block
    end
  else
    self._rangeDispFill = nil
    if t.rangeEstimateStale then
      mode, ratio = "resync", 0.5
      color = skinColor("fluffyColorRangeResync", FLUFFY.RANGE_RESYNC)
      text, textColor = "RESYNC", FLUFFY.TEXT
    else
      text = ""
      local prog = t.rangeProg or -1
      ratio = p.rangeZoomedGlide and Engine.ZoomFill(prog, p.rangeZoomLevel)
              or ((prog + 1) / 2)
      if t.rangeState == "MELEE" then
        mode, color = "melee", skinColor("fluffyColorRangeDeadzone", FLUFFY.RANGE_MELEE)
      elseif t.rangeState == "SWEET" then
        if (t.rangeProg or -1) > Engine.PERFECT_AT then
          mode, color = "super", skinColor("fluffyColorRangePerfect", FLUFFY.RANGE_SUPER)
        else
          mode, color = "sweet", skinColor("fluffyColorRangeSweet", FLUFFY.RANGE_SWEET)
        end
      else
        mode, color = "close", skinColor("fluffyColorRangeClose", FLUFFY.RANGE_CLOSE)
      end
    end
  end

  if mode ~= self._rangeMode then
    range.fill:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    self._rangeMode = mode
  end
  if not self._rangeRatio or math.abs(self._rangeRatio - ratio) > 0.005 then
    range.fill:SetWidth(math.max(0.01, ratio * (self._innerW or 0)))
    self._rangeRatio = ratio
  end
  if text ~= self._rangeText then
    range.label:SetText(text)
    if text ~= "" and textColor then
      range.label:SetTextColor(textColor[1], textColor[2], textColor[3], 1)
    end
    self._rangeText = text
  end
end

function FluffyCluster:Refresh(state)
  local f = self.frame
  if not f or not f:IsVisible() then return end
  -- Device-pixel placements are only correct for the scale they were computed
  -- at; re-run layout when the effective scale moves (UI scale, HUD scale,
  -- fluffyScale). ApplyLayout invalidates the mark caches.
  local ps = Nock.UI.PixelScale(f)
  if ps ~= self._pixelScale then
    self._pixelScale = ps
    self:ApplyLayout()
  end
  refreshCastBar(self)
  refreshSwing(self, state)
  refreshLanes(self, state)
  refreshRange(self, state)
end
