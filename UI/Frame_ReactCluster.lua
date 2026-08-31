-- UI/Frame_ReactCluster.lua
-- React-mode bar stack (one HUD row): converge-to-center auto shot bar with
-- clip ticks + eWS bracket marks, melee swing bar, slide range finder, mana bar.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ReactCluster = Nock:NewModule("ReactCluster", "AceEvent-3.0")
local C = Nock.Constants

-- Reference React skin. Deliberately NOT wired to the GLOBAL barTexture /
-- fontFace — these frames never register with RegisterBarFill /
-- RegisterFontString, so RefreshMedia can't restyle them. React media is its
-- own channel instead: the React-scoped reactBarTexture/reactFont keys
-- ("" = this reference look) are applied by ApplyLayout over the mediaFills/
-- mediaTexts rosters below. The values here are the reference WA look; a
-- curated subset (bar heights + fill/state colors) can be overridden from
-- the React HUD options tab via the skinNum/skinColor resolvers below,
-- whose profile defaults equal these constants.
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local REACT = {
  -- Bar heights measured off the reference screenshot (pixel-sampled); auto
  -- runs 2px taller than measured so the converge fill renders smoother.
  AUTO_H  = 14,
  MELEE_H = 12,
  RANGE_H = 12,
  MANA_H  = 12,
  GAP     = -1,  -- bars overlap their 1px borders → one shared black seam (clamped, reference look)
  FONT_BIG   = 9,    -- auto-bar texts
  FONT_SMALL = 9,    -- melee / range / mana texts

  BAR_BG       = { 0.08, 0.08, 0.08, 0.90 },
  BORDER       = { 0.00, 0.00, 0.00, 1.00 },
  AUTO_FILL    = { 1.00, 0.84, 0.00, 1.00 },  -- gold converge halves
  TICK_STEADY  = { 1.00, 0.10, 0.10, 1.00 },  -- Steady clip threshold
  TICK_MULTI   = { 1.00, 0.65, 0.10, 1.00 },  -- Multi/instant clip threshold
  TICK_WINDUP  = { 0.85, 0.85, 0.85, 0.80 },  -- Auto Shot wind-up start (commit point)
  BRACKET      = { 1.00, 1.00, 1.00, 0.35 },  -- eWS profile-bound marks
  GCD_DIVIDER  = { 0.62, 0.35, 0.98, 1.00 },  -- GCD divider (purple, off by default)
  GCD_DIVIDER_W = 2,                          -- GCD divider width px
  MELEE_BLUE   = { 0.55, 0.75, 1.00, 1.00 },  -- auto-attack-only weave (light blue, separates from the gold auto bar)
  MELEE_GREEN  = { 0.15, 0.68, 0.38, 1.00 },  -- Raptor ready
  MANA_FILL    = { 0.20, 0.55, 1.00, 1.00 },
  -- Range colors = the user's configured values from the reference
  -- melee-weave WA (attribution TBD — the circulating copy is a fork).
  RANGE_MELEE = { 0.68, 0.18, 0.20, 1.00 },  -- MELEE (meleeRangeColor)
  RANGE_SUPER = { 0.17, 0.78, 0.11, 1.00 },  -- SWEET near the melee edge (superSweetSpotColor)
  RANGE_SWEET = { 0.85, 0.66, 0.00, 1.00 },  -- SWEET (sweetSpotColor)
  RANGE_CLOSE = { 0.00, 0.83, 0.75, 1.00 },  -- CLOSE (closeRangeColor)
  RANGE_DIM   = { 0.30, 0.30, 0.30, 1.00 },  -- no valid target
  RANGE_RESYNC = { 1.00, 0.58, 0.10, 1.00 }, -- estimate degraded (matches classic bar)
  RANGE_DIVIDER   = { 1.00, 1.00, 1.00, 0.90 },  -- centre tick (melee boundary)
  RANGE_DIVIDER_W = 1,                           -- centre tick width px
  TEXT         = { 1.00, 1.00, 1.00, 1.00 },
}

-- React range bar — consumes the shared range engine published by
-- Modules/RangeFinder.lua via Modules/RangeEngine.lua (state.target
-- .rangeState/rangeProg/rangeBracket/rangeEstimateStale). Full parity with
-- the classic bar — finding ladder (drain/block per rangeFinderFindingStyle)
-- beyond ~10yd, weave fill inside, orange parked-at-tick RESYNC — but the
-- palette stays hardcoded to the reference WA look (unlike the classic
-- bar's user-configurable colors).

local MAX_BRACKETS = 12  -- 6 eWS bounds x 2 mirrored sides

-- Weave-coach stage cue on the melee bar (state.weave.stage, semantics in
-- Modules/WeaveCoach.lua). The one that saves weaves: HOLD means the queued
-- hit has NOT landed yet — releasing there /stopattack-cancels the swing and
-- the Raptor silently. RELEASE (or the struck sound) is the safe let-go.
local MELEE_STAGE = {
  GO      = { "GO",       0.20, 0.90, 0.30 },
  HOLD    = { "HOLD",     1.00, 0.70, 0.00 },
  STRUCK  = { "BACK OUT", 0.40, 0.70, 1.00 },
  RELEASE = { "RELEASE",  0.20, 0.90, 0.30 },
}

local function profile()
  return (Nock.db and Nock.db.profile) or {}
end

-- Skin resolvers: profile override (React HUD tab → Skin) or the reference
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

-- Flat 1px-bordered bar shell with a dark fill background. No LSM, no media
-- registration (fixed skin by construction).
local function createReactBar(parent, name, h)
  local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
  f:SetHeight(h)
  Nock.UI.ApplyBackdrop(f, REACT.BAR_BG, REACT.BORDER)
  return f
end

-- React media rosters: every fill and text made below, re-skinned by
-- ApplyLayout from reactBarTexture / reactFont ("" = this reference look).
-- NOT the global RegisterBarFill/RegisterFontString registries — those apply
-- the global barTexture/fontFace, which the React skin deliberately ignores.
-- Marks (makeMark) stay solid WHITE8X8: they are 1-2px ticks, not fills.
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
  fs:SetTextColor(unpack(REACT.TEXT))
  fs:SetText("")
  mediaTexts[#mediaTexts + 1] = { fs = fs, size = size }
  return fs
end

function ReactCluster:OnInitialize()
  local parent = Nock.parentFrame
  local container = CreateFrame("Frame", "NockReactCluster", parent)
  self.frame = container

  -- Auto Shot bar: two mirrored fills converging on the center at the fire
  -- moment, clip ticks + eWS bracket marks (mirrored pairs), delay readout
  -- centered, rotation notation right-aligned.
  local auto = createReactBar(container, "NockReactAuto", REACT.AUTO_H)
  auto.fillL = makeFill(auto, REACT.AUTO_FILL)
  auto.fillL:SetPoint("TOPLEFT", auto, "TOPLEFT", 1, -1)
  auto.fillL:SetPoint("BOTTOMLEFT", auto, "BOTTOMLEFT", 1, 1)
  auto.fillR = makeFill(auto, REACT.AUTO_FILL)
  auto.fillR:SetPoint("TOPRIGHT", auto, "TOPRIGHT", -1, -1)
  auto.fillR:SetPoint("BOTTOMRIGHT", auto, "BOTTOMRIGHT", -1, 1)
  local function makeMark(color, w)
    local t = auto:CreateTexture(nil, "OVERLAY")
    t:SetTexture(WHITE8X8)
    t:SetVertexColor(unpack(color))
    t:SetSize(w, REACT.AUTO_H - 2)
    -- The engine's own texel snapping must not second-guess a quad we place
    -- on the device grid ourselves (the default bias shifts a stretched
    -- WHITE8X8 by half a texel). Guarded: headless stubs lack the methods.
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    t:Hide()
    return t
  end
  auto.steadyL = makeMark(REACT.TICK_STEADY, 2)
  auto.steadyR = makeMark(REACT.TICK_STEADY, 2)
  auto.multiL  = makeMark(REACT.TICK_MULTI, 2)
  auto.multiR  = makeMark(REACT.TICK_MULTI, 2)
  auto.windupL = makeMark(REACT.TICK_WINDUP, 2)
  auto.windupR = makeMark(REACT.TICK_WINDUP, 2)
  auto.brackets = {}
  for i = 1, MAX_BRACKETS do
    auto.brackets[i] = makeMark(REACT.BRACKET, 1)
  end
  -- GCD divider (reactShowGcdDivider, default off). Unlike every other mark on
  -- this bar these are not thresholds — they ride the GCD's own progress, so
  -- they move every tick while a GCD runs and hide the rest of the time. Same
  -- OVERLAY layer as the ticks, so purple draws over the gold ARTWORK fill.
  auto.gcdL = makeMark(REACT.GCD_DIVIDER, REACT.GCD_DIVIDER_W)
  auto.gcdR = makeMark(REACT.GCD_DIVIDER, REACT.GCD_DIVIDER_W)
  auto.delayText    = makeText(auto, REACT.FONT_BIG, "CENTER")
  auto.notationText = makeText(auto, REACT.FONT_BIG, "RIGHT", -3)
  self.auto = auto

  -- Melee swing bar: left-anchored fill, centered READY, green/white by
  -- Raptor Strike cooldown (state.cooldowns.Raptor, tracked-only entry).
  local melee = createReactBar(container, "NockReactMelee", REACT.MELEE_H)
  melee.fill = makeFill(melee, REACT.MELEE_BLUE)
  melee.fill:SetPoint("TOPLEFT", melee, "TOPLEFT", 1, -1)
  melee.fill:SetPoint("BOTTOMLEFT", melee, "BOTTOMLEFT", 1, 1)
  melee.text = makeText(melee, REACT.FONT_SMALL, "CENTER")
  self.melee = melee

  -- Range bar: plain progressive fill toward the weave sweet spot (original
  -- WA look — no thumb or bands; center tick + bracket/RESYNC label only).
  -- Position/color data comes from the shared engine via state (see the
  -- file-header note); this is rendering only.
  local range = createReactBar(container, "NockReactRange", REACT.RANGE_H)
  range.fill = makeFill(range, REACT.RANGE_CLOSE)
  range.fill:SetPoint("TOPLEFT", range, "TOPLEFT", 1, -1)
  range.fill:SetPoint("BOTTOMLEFT", range, "BOTTOMLEFT", 1, 1)
  -- Center tick = the melee boundary (the WA's 50% subtick).
  local tick = range:CreateTexture(nil, "OVERLAY")
  tick:SetTexture(WHITE8X8)
  tick:SetVertexColor(unpack(REACT.RANGE_DIVIDER))
  tick:SetSize(REACT.RANGE_DIVIDER_W, REACT.RANGE_H - 2)
  tick:SetPoint("CENTER", range, "CENTER", 0, 0)
  range.tick = tick
  -- Bracket text for the LONG-range overlay (empty while the weave fill owns
  -- the bar).
  range.label = makeText(range, REACT.FONT_SMALL, "CENTER")
  self.range = range

  -- Mana bar: thin fill + centered percent.
  local mana = createReactBar(container, "NockReactMana", REACT.MANA_H)
  mana.fill = makeFill(mana, REACT.MANA_FILL)
  mana.fill:SetPoint("TOPLEFT", mana, "TOPLEFT", 1, -1)
  mana.fill:SetPoint("BOTTOMLEFT", mana, "BOTTOMLEFT", 1, 1)
  mana.text = makeText(mana, REACT.FONT_SMALL, "CENTER")
  self.mana = mana

  self:ApplyLayout()
  container:Hide()  -- HUD:ApplyRowVisibility shows it in React mode
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyLayout")
end

-- Single source of truth for the cluster geometry (pattern of
-- SwingTimers:Geometry). Honors the React-specific element toggles (React
-- HUD tab) — a hidden sub-bar costs zero height; GAP is only added between
-- shown bars. Heights come through the skin resolver. The top-to-bottom
-- SEQUENCE comes from Nock.UI.ResolveReactBarOrder(reactBarOrder) — the
-- Up/Down editor on the React HUD tab; the return record stays flat named
-- fields so ApplyLayout and the mark sizing read the same shape as always.
function ReactCluster:Geometry()
  local p = profile()
  local w = tonumber(p.reactWidth) or 220
  local show = {
    auto  = p.reactShowAutoBar  ~= false,
    melee = p.reactShowMeleeBar ~= false,
    range = p.reactShowRangeBar ~= false,
    mana  = p.reactShowManaBar  ~= false,
  }
  local h = {
    auto  = skinNum("reactAutoH",  REACT.AUTO_H),
    melee = skinNum("reactMeleeH", REACT.MELEE_H),
    range = skinNum("reactRangeH", REACT.RANGE_H),
    mana  = skinNum("reactManaH",  REACT.MANA_H),
  }

  local order = Nock.UI.ResolveReactBarOrder(p.reactBarOrder)
  local ys = {}
  local y = 0
  for i = 1, #order do
    local k = order[i]
    if show[k] then
      if y > 0 then y = y + REACT.GAP end
      ys[k] = y
      y = y + h[k]
    end
  end

  return {
    w = w,
    showAuto = show.auto, showMelee = show.melee,
    showRange = show.range, showMana = show.mana,
    yAuto = ys.auto, yMelee = ys.melee, yRange = ys.range, yMana = ys.mana,
    hAuto = h.auto, hMelee = h.melee, hRange = h.range, hMana = h.mana,
    total = math.max(y, 1),
  }
end

-- Logical (unscaled) height of the row, for HUD's LAYOUT height fn.
function ReactCluster:ContentHeight()
  return self:Geometry().total
end

-- (Re)size and (re)anchor everything from Geometry, then invalidate every diff
-- cache so the next Refresh repaints against the new dimensions.
function ReactCluster:ApplyLayout()
  local g = self:Geometry()
  local p = profile()
  local f = self.frame
  f:SetSize(g.w, g.total)
  local innerW = g.w - 2

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
  placeBar(self.auto,  g.yAuto,  g.hAuto,  g.showAuto)
  placeBar(self.melee, g.yMelee, g.hMelee, g.showMelee)
  placeBar(self.range, g.yRange, g.hRange, g.showRange)
  placeBar(self.mana,  g.yMana,  g.hMana,  g.showMana)

  self._halfW  = (g.w - 2) / 2
  self._innerW = innerW

  -- React media (React HUD tab → Skin): reactBarTexture on the fills,
  -- reactFont on the texts; "" = the reference skin (WHITE8X8 / C.FONT.PATH).
  -- Vertex colors survive SetTexture, and the ones ApplyLayout owns are
  -- re-applied just below anyway.
  local tex = Nock.UI.GetReactBarTexture() or WHITE8X8
  for i = 1, #mediaFills do
    mediaFills[i]:SetTexture(tex)
  end
  local font = Nock.UI.GetReactFont() or C.FONT.PATH
  local delta = Nock.UI.GetReactFontDelta()
  for i = 1, #mediaTexts do
    local e = mediaTexts[i]
    Nock.UI.SafeSetFont(e.fs, font, math.max(6, e.size + delta), "OUTLINE")
  end

  -- Marks are cut to fit the (possibly overridden) bar heights.
  -- Auto-bar marks: width + colour per mark, resolved from the React skin keys
  -- (defaults = the REACT constants, so an untouched profile looks identical).
  -- Mirrored pairs share one setting — they are one mark drawn on both halves,
  -- and letting them differ would only ever look like a bug.
  local auto = self.auto
  -- Widths are DEVICE pixels, converted through the bar's physical pixels per
  -- unit (Nock.UI.PixelScale = effectiveScale x physH/768) -- see
  -- Nock.UI.DeviceWidth. Converting through the BARE effective scale made a
  -- "2 px" mark 3.75 physical px at 1440p, rasterised to different widths per
  -- monitor and per mark (the mirrored 1px-vs-2px report, 2026-08-31).
  local ps = Nock.UI.PixelScale(auto)
  self._pixelScale = ps
  self._markDevW = self._markDevW or {}
  local devW = self._markDevW
  local function paintPair(tL, tR, wKey, wRef, cKey, cRef)
    local n = skinNum(wKey, wRef)
    devW[wKey] = n
    local w = Nock.UI.DeviceWidth(n, ps)
    local c = skinColor(cKey, cRef)
    tL:SetSize(w, g.hAuto - 2)
    tR:SetSize(w, g.hAuto - 2)
    tL:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    tR:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  end
  paintPair(auto.steadyL, auto.steadyR, "reactTickSteadyWidth", 2, "reactColorTickSteady", REACT.TICK_STEADY)
  paintPair(auto.multiL,  auto.multiR,  "reactTickMultiWidth",  2, "reactColorTickMulti",  REACT.TICK_MULTI)
  paintPair(auto.windupL, auto.windupR, "reactTickWindupWidth", 2, "reactColorTickWindup", REACT.TICK_WINDUP)
  local bn = skinNum("reactBracketWidth", 1)
  devW.reactBracketWidth = bn
  local bw = Nock.UI.DeviceWidth(bn, ps)
  local bc = skinColor("reactColorBracket", REACT.BRACKET)
  for i = 1, MAX_BRACKETS do
    auto.brackets[i]:SetSize(bw, g.hAuto - 2)
    auto.brackets[i]:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 1)
  end
  local gn = skinNum("reactGcdDividerWidth", REACT.GCD_DIVIDER_W)
  devW.reactGcdDividerWidth = gn
  local gw = Nock.UI.DeviceWidth(gn, ps)
  local gc = skinColor("reactColorGcdDivider", REACT.GCD_DIVIDER)
  auto.gcdL:SetSize(gw, g.hAuto - 2)
  auto.gcdR:SetSize(gw, g.hAuto - 2)
  auto.gcdL:SetVertexColor(gc[1], gc[2], gc[3], gc[4] or 1)
  auto.gcdR:SetVertexColor(gc[1], gc[2], gc[3], gc[4] or 1)
  -- Gate here as well as in RefreshAuto: turning the option off mid-session
  -- leaves a line parked wherever the last tick put it otherwise.
  if p.reactShowGcdDivider ~= true then
    auto.gcdL:Hide(); auto.gcdR:Hide()
  end
  local dw = Nock.UI.DeviceWidth(skinNum("reactRangeDividerWidth", REACT.RANGE_DIVIDER_W),
                                Nock.UI.PixelScale(self.range))
  local dc = skinColor("reactColorRangeDivider", REACT.RANGE_DIVIDER)
  self.range.tick:SetSize(dw, g.hRange - 2)
  self.range.tick:SetVertexColor(dc[1], dc[2], dc[3], dc[4] or 1)

  -- Construction-time fill colors re-applied from the skin resolver (melee
  -- and range fills repaint through their nil'd diff caches below).
  local cAuto = skinColor("reactColorAutoFill", REACT.AUTO_FILL)
  auto.fillL:SetVertexColor(cAuto[1], cAuto[2], cAuto[3], cAuto[4] or 1)
  auto.fillR:SetVertexColor(cAuto[1], cAuto[2], cAuto[3], cAuto[4] or 1)
  local cMana = skinColor("reactColorManaFill", REACT.MANA_FILL)
  self.mana.fill:SetVertexColor(cMana[1], cMana[2], cMana[3], cMana[4] or 1)

  -- Fill directions (React HUD tab). Auto: converge (reference) | ltr | rtl —
  -- fillL doubles as the single directional fill, fillR only participates in
  -- converge mode. Melee: ltr | rtl.
  self._dirAuto = p.reactDirAuto or "converge"
  auto.fillL:ClearAllPoints()
  if self._dirAuto == "rtl" then
    auto.fillL:SetPoint("TOPRIGHT", auto, "TOPRIGHT", -1, -1)
    auto.fillL:SetPoint("BOTTOMRIGHT", auto, "BOTTOMRIGHT", -1, 1)
  else
    auto.fillL:SetPoint("TOPLEFT", auto, "TOPLEFT", 1, -1)
    auto.fillL:SetPoint("BOTTOMLEFT", auto, "BOTTOMLEFT", 1, 1)
  end
  if self._dirAuto == "converge" then
    auto.fillR:Show()
  else
    auto.fillR:Hide()
  end
  local melee = self.melee
  melee.fill:ClearAllPoints()
  if (p.reactDirMelee or "ltr") == "rtl" then
    melee.fill:SetPoint("TOPRIGHT", melee, "TOPRIGHT", -1, -1)
    melee.fill:SetPoint("BOTTOMRIGHT", melee, "BOTTOMRIGHT", -1, 1)
  else
    melee.fill:SetPoint("TOPLEFT", melee, "TOPLEFT", 1, -1)
    melee.fill:SetPoint("BOTTOMLEFT", melee, "BOTTOMLEFT", 1, 1)
  end

  -- Feature-gated delay readout (React HUD tab; default off).
  if p.reactShowDelay == true then
    self.auto.delayText:Show()
  else
    self.auto.delayText:Hide()
  end
  -- Rotation notation gate (React HUD tab; default on).
  if p.reactShowNotation == false then
    auto.notationText:Hide()
  else
    auto.notationText:Show()
  end

  -- Invalidate diff/signature caches (width or bar set may have changed).
  self._lastAutoP     = nil
  self._gcdX          = nil   -- forces the GCD divider to re-place next tick
  self._markSd        = nil   -- forces PositionAutoMarks next tick
  self._markWindup    = nil
  self._lastDelaySec  = nil
  self._lastDelayText = nil
  self._lastNotation  = nil
  self._lastMeleeP    = nil
  self._lastMeleeText = nil
  self._lastMeleeColor = nil
  self._lastRatio     = nil
  self._lastRangeMode = nil
  self._lastRangeText = nil
  self._rangeDispFill = nil
  self._lastManaRatio = nil
  self._lastManaPct   = nil
  self._lastManaMode  = nil
  self._lastManaCur   = nil
  self._lastManaMax   = nil
end

-- Clip ticks + eWS bracket marks on the converge axis. A threshold T seconds
-- before the shot maps to the moving edge's position when remaining == T:
-- fill fraction (sd-T)/sd → x px from EACH edge (mirrored pair). eWS bounds
-- are duration-space values projected the same way at fraction lo/sd.
-- Thresholds are computed by the caller (Refresh) so this stays pure placement
-- and the diff-guard can key on the same values it passes in.
function ReactCluster:PositionAutoMarks(sd, steadyT, multiT, windup)
  local auto = self.auto
  local halfW = self._halfW or 0
  -- Directional (ltr/rtl) modes project onto the FULL inner width from the
  -- fill's origin edge and use a single mark per threshold (the *L texture);
  -- converge keeps the reference mirrored pairs.
  local dir = self._dirAuto or "converge"
  local innerW = self._innerW or 0

  local ps   = self._pixelScale
  local devW = self._markDevW or {}
  -- The bar's edges in PHYSICAL pixels: the pixel grid lives in absolute
  -- screen space, and the two edges carry different sub-pixel phases, so each
  -- half of a mirrored pair snaps against its own edge. nil before layout ->
  -- relative snap (the old behaviour), corrected on the next re-place.
  local barL, barR = auto:GetLeft(), auto:GetRight()
  local leftPx  = (ps and barL) and barL * ps or nil
  local rightPx = (ps and barR) and barR * ps or nil
  local function placePair(tL, tR, T, wKey)
    if sd <= 0 or T <= 0 then
      tL:Hide(); tR:Hide()
      return
    end
    -- Clamp rather than hide when the cast can't fit the cycle at all — a
    -- missing mark reads as "no clip risk". Mirrors Frame_SwingTimers:place.
    if T > sd then T = sd end
    -- Shared projection (Nock.UI.ReactAxisPoint) — same one the GCD divider
    -- places through, so the two can't drift apart.
    local edge, x, mirrored, xR =
      Nock.UI.ReactAxisPoint((sd - T) / sd, dir, halfW, innerW, ps, devW[wKey], leftPx, rightPx)
    tL:ClearAllPoints(); tL:SetPoint("CENTER", auto, edge, x, 0); tL:Show()
    if mirrored then
      tR:ClearAllPoints(); tR:SetPoint("CENTER", auto, "RIGHT", -xR, 0); tR:Show()
    else
      tR:Hide()
    end
  end
  placePair(auto.steadyL, auto.steadyR, steadyT, "reactTickSteadyWidth")
  placePair(auto.multiL,  auto.multiR,  multiT, "reactTickMultiWidth")
  -- Commit point: the next Auto Shot's wind-up starts HERE, not where the
  -- converge halves meet. Explains why the glued cast bar lights up before the
  -- bar is full — it isn't early, the bar runs one wind-up past the commit.
  -- `windup` is measured (see SwingTimer:UpdateWindup); it is haste-scaled, so a
  -- constant would put this mark in the wrong place under Rapid Fire.
  if profile().showWindupMark == false then
    auto.windupL:Hide(); auto.windupR:Hide()
  else
    placePair(auto.windupL, auto.windupR, windup or C.AUTO_SHOT_CAST, "reactTickWindupWidth")
  end

  -- eWS bracket marks — bounds come from the live profile table, never
  -- hardcoded. Pooled textures; surplus ones hidden. Feature-gated
  -- (reactShowBrackets, default off): all six bounds at once read as noise.
  local n = 0
  local list = (Nock.Profiles and Nock.Profiles.list) or {}
  if sd > 0 and profile().reactShowBrackets == true then
    for i = 1, #list do
      local lo = list[i].lo
      if lo and lo > 0 and lo < sd then
        local edge, x, mirrored, xR =
          Nock.UI.ReactAxisPoint(lo / sd, dir, halfW, innerW, ps, devW.reactBracketWidth, leftPx, rightPx)
        if mirrored then
          if n + 2 > MAX_BRACKETS then break end
          local bL = auto.brackets[n + 1]
          local bR = auto.brackets[n + 2]
          bL:ClearAllPoints(); bL:SetPoint("CENTER", auto, edge,    x, 0); bL:Show()
          bR:ClearAllPoints(); bR:SetPoint("CENTER", auto, "RIGHT", -xR, 0); bR:Show()
          n = n + 2
        else
          if n + 1 > MAX_BRACKETS then break end
          local b = auto.brackets[n + 1]
          b:ClearAllPoints(); b:SetPoint("CENTER", auto, edge, x, 0); b:Show()
          n = n + 1
        end
      end
    end
  end
  for i = n + 1, MAX_BRACKETS do
    auto.brackets[i]:Hide()
  end
end

-- The GCD divider: the ONLY moving mark on the auto bar. Every other mark is a
-- threshold (fixed for a given swing duration and diff-guarded on it), but this
-- one rides the GCD's own progress, so it repositions while a GCD runs.
--
-- It is not a reading of the swing axis at all -- it runs the GCD's 0->100%
-- across the bar the same way the gold fill runs the swing, using the auto
-- bar's fill direction: converge puts one line in from each edge, ltr/rtl a
-- single line from the fill's origin edge.
--
-- Diff-guarded on the ROUNDED pixel offset, not the raw fraction: at 30-60Hz
-- over a ~1.5s GCD the fraction changes every single tick while the pixel it
-- lands on does not, and SetPoint is the expensive half.
function ReactCluster:RefreshGcdDivider(state)
  local auto = self.auto
  if profile().reactShowGcdDivider ~= true then
    -- Only touch the textures on the transition — Hide() on an already-hidden
    -- texture every tick is pure waste on the default (off) path.
    if self._gcdX ~= nil then
      auto.gcdL:Hide(); auto.gcdR:Hide()
      self._gcdX = nil
    end
    return
  end

  local frac = Nock.UI.ReactGcdFrac(state.gcd)
  if not frac then
    if self._gcdX ~= nil then
      auto.gcdL:Hide(); auto.gcdR:Hide()
      self._gcdX = nil
    end
    return
  end

  local ps = self._pixelScale
  local barL, barR = auto:GetLeft(), auto:GetRight()
  local edge, x, mirrored, xR =
    Nock.UI.ReactAxisPoint(frac, self._dirAuto or "converge", self._halfW or 0, self._innerW or 0,
                           ps, (self._markDevW or {}).reactGcdDividerWidth,
                           (ps and barL) and barL * ps or nil,
                           (ps and barR) and barR * ps or nil)
  -- Snapping already quantises x to the device grid, so it is safe to diff on
  -- directly: identical inputs give a bit-identical float. That is also what
  -- makes this cheap -- the divider only re-anchors once per device pixel
  -- crossed, not once per tick.
  local px = x
  if px == self._gcdX then return end
  self._gcdX = px

  auto.gcdL:ClearAllPoints()
  auto.gcdL:SetPoint("CENTER", auto, edge, px, 0)
  auto.gcdL:Show()
  if mirrored then
    auto.gcdR:ClearAllPoints()
    auto.gcdR:SetPoint("CENTER", auto, "RIGHT", -xR, 0)
    auto.gcdR:Show()
  else
    auto.gcdR:Hide()
  end
end

function ReactCluster:RefreshAuto(state)
  local auto = self.auto
  local r = state.ranged

  -- Device-pixel widths are only correct for the scale they were computed at,
  -- and the row's effective scale moves under us (UI scale, HUD scale, the
  -- per-row scale). Cheap compare; ApplyLayout only runs when it actually
  -- changed, and it invalidates the mark caches so the next tick re-places.
  local ps = Nock.UI.PixelScale(auto)
  if ps ~= self._pixelScale then self:ApplyLayout() end

  -- Converge fill: p=0 at swing start (both halves empty), p=1 at the fire
  -- moment (halves meet at center). Gating via Nock.AutoSwingLive — a swing in
  -- flight always draws; expired only stays full in combat while auto is still
  -- armed (held shot). Disarmed (melee cancels auto-repeat) or out of combat,
  -- a stale swing doesn't sit fully filled (solid gold).
  local p01 = 0
  if Nock.AutoSwingLive() then
    p01 = 1 - (r.swingRemaining / r.swingDuration)
    if p01 < 0 then p01 = 0 elseif p01 > 1 then p01 = 1 end
  end
  if not self._lastAutoP or math.abs(p01 - self._lastAutoP) > 0.002 then
    if self._dirAuto == "converge" then
      local w = math.max(0.01, p01 * (self._halfW or 0))
      auto.fillL:SetWidth(w)
      auto.fillR:SetWidth(w)
    else
      -- Directional single fill across the full inner width (fillR hidden).
      auto.fillL:SetWidth(math.max(0.01, p01 * (self._innerW or 0)))
    end
    self._lastAutoP = p01
  end

  -- Marks reposition only when their inputs change. Thresholds come from the
  -- shared Nock.ClipThreshold, same as the classic bar and the rotation engine.
  local sd = r.swingDuration
  local windup = r.windup or C.AUTO_SHOT_CAST
  local steadyT = Nock.ClipThreshold(1.5)
  local multiT  = Nock.ClipThreshold(0.5)
  -- The bar's left edge is part of the mark inputs now: positions are snapped
  -- in absolute screen space, so moving the HUD changes the answer even when
  -- no threshold did. Cheap C call; only ever re-places while actually moving.
  local barLeft = auto:GetLeft()
  if sd ~= self._markSd or steadyT ~= self._markSteadyT
     or multiT ~= self._markMultiT or windup ~= self._markWindup
     or barLeft ~= self._markBarLeft then
    self:PositionAutoMarks(sd, steadyT, multiT, windup)
    self._markSd      = sd
    self._markSteadyT = steadyT
    self._markMultiT  = multiT
    self._markWindup  = windup
    self._markBarLeft = barLeft
  end

  self:RefreshGcdDivider(state)

  -- Delay readout (seconds late vs one weapon-speed cycle), severity-colored.
  -- Feature-gated (reactShowDelay, default off — ApplyLayout hides the string).
  -- autoDelay only moves when a shot fires — diff on the raw number so the
  -- format doesn't build a string every tick.
  local sec = r.autoDelay or 0
  if auto.delayText:IsShown() and sec ~= self._lastDelaySec then
    self._lastDelaySec = sec
    local txt = string.format("+%.2f", sec)
    if txt ~= self._lastDelayText then
      auto.delayText:SetText(txt)
      auto.delayText:SetTextColor(Nock.UI.DelaySeverityColor(sec))
      self._lastDelayText = txt
    end
  end

  -- Rotation notation, passed through the user's rename map at the render
  -- edge (state.rotation keeps the real bracket for the engine). Gated by
  -- reactShowNotation (ApplyLayout hides the string).
  if auto.notationText:IsShown() then
    local notation = state.rotation and (state.rotation.notation or state.rotation.profileName)
    local name = (notation and Nock.Profiles and Nock.Profiles:DisplayName(notation)) or notation or "—"
    if name ~= self._lastNotation then
      auto.notationText:SetText(name)
      self._lastNotation = name
    end
    -- Per-notation color (DisplayColor keys on the raw notation; nil = the
    -- reference white). Own numeric diff cache — the color can change while
    -- the text doesn't (options edit) and vice versa (proc flip).
    local r, g, b, a
    if notation and Nock.Profiles then
      r, g, b, a = Nock.Profiles:DisplayColor(notation)
    end
    if not r then
      r, g, b, a = REACT.TEXT[1], REACT.TEXT[2], REACT.TEXT[3], REACT.TEXT[4]
    end
    if r ~= self._noteColR or g ~= self._noteColG
       or b ~= self._noteColB or a ~= self._noteColA then
      auto.notationText:SetTextColor(r, g, b, a)
      self._noteColR, self._noteColG, self._noteColB, self._noteColA = r, g, b, a
    end
  end
end

function ReactCluster:RefreshMelee(state)
  local melee = self.melee
  local m = state.melee
  local ready = (m.swingStart == 0) or (m.swingRemaining <= 0)

  local p01 = 1
  if not ready and m.swingDuration > 0 then
    p01 = 1 - (m.swingRemaining / m.swingDuration)
    if p01 < 0 then p01 = 0 elseif p01 > 1 then p01 = 1 end
  end
  if not self._lastMeleeP or math.abs(p01 - self._lastMeleeP) > 0.002 then
    melee.fill:SetWidth(math.max(0.01, p01 * (self._innerW or 0)))
    self._lastMeleeP = p01
  end

  -- Weave-coach stage outranks READY; each stage carries its own text color
  -- (so a txt diff is also a color diff — one cache covers both).
  local stage = state.weave and state.weave.stage
  local look = stage and MELEE_STAGE[stage]
  local txt = look and look[1] or (ready and "READY" or "")
  if txt ~= self._lastMeleeText then
    melee.text:SetText(txt)
    if look then
      melee.text:SetTextColor(look[2], look[3], look[4])
    else
      melee.text:SetTextColor(unpack(REACT.TEXT))
    end
    self._lastMeleeText = txt
  end

  -- Green = Raptor Strike off cooldown (a Raptor weave is possible), light
  -- blue = auto-attack-only weave. Guard the slot: it only exists once the
  -- Phase-0 catalog entry has been scanned.
  local cd = state.cooldowns.Raptor
  local green = (cd and cd.ready) and true or false
  if green ~= self._lastMeleeColor then
    local c = green and skinColor("reactColorMeleeReady", REACT.MELEE_GREEN)
              or skinColor("reactColorMeleeAuto", REACT.MELEE_BLUE)
    melee.fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    self._lastMeleeColor = green
  end
end

-- Rendering-only: consumes the shared engine's published fields (classic-bar
-- parity, spec 2026-08-06). Finding phase honors rangeFinderFindingStyle —
-- drain (fill = distance remaining, bracket-colored label) or block (solid
-- bracket-colored fill, white label); glide phase = WA palette; RESYNC =
-- orange parked at the tick.
function ReactCluster:RefreshRange(state)
  local range = self.range
  local t = state.target

  if not t.exists or not t.alive or t.friendly or not t.rangeState then
    if self._lastRangeMode ~= "none" then
      range.fill:SetWidth(0.01)
      range.fill:SetVertexColor(unpack(REACT.RANGE_DIM))
      range.label:SetText("")
      self._lastRangeMode = "none"
      self._lastRatio = nil
      self._lastRangeText = nil
      self._rangeDispFill = nil
    end
    return
  end

  local Engine = Nock.RangeEngine
  local mode, ratio, color, text, textColor
  if t.rangeState == "LONG" then
    local b = t.rangeBracket and Engine.BRACKETS[t.rangeBracket]
    local style = profile().rangeFinderFindingStyle or "drain"
    if not b then
      -- First ladder scan pending: dim, empty, no text.
      mode, ratio, color, text = "find", 0, REACT.RANGE_DIM, ""
    elseif style == "block" then
      mode, ratio, color = "findb|" .. t.rangeBracket, 1, b.block
      text, textColor = b.label, REACT.TEXT
    else
      -- Drain: ease the displayed fill toward the bracket's level so
      -- bracket steps read as motion (same easing as the classic bar).
      local now = GetTime()
      local dt = math.min(0.2, now - (self._rangeDispT or now))
      self._rangeDispT = now
      self._rangeDispFill = self._rangeDispFill or b.fill
      self._rangeDispFill = self._rangeDispFill + (b.fill - self._rangeDispFill) * math.min(1, dt * 12)
      mode, ratio, color = "findd|" .. t.rangeBracket, self._rangeDispFill,
                           skinColor("reactColorRangeClose", REACT.RANGE_CLOSE)
      text, textColor = b.label, b.block  -- bracket-coded text, the RC-WA look
    end
  else
    self._rangeDispFill = nil
    if t.rangeEstimateStale then
      mode, ratio, color = "resync", 0.5, skinColor("reactColorRangeResync", REACT.RANGE_RESYNC)
      text, textColor = "RESYNC", REACT.TEXT
    else
      text = ""
      -- Zoomed weave bar (experimental): centered viewport crop, tick stays
      -- put, movement reads rangeZoomLevel times bigger.
      local prog = t.rangeProg or -1
      local p = profile()
      ratio = p.rangeZoomedGlide and Engine.ZoomFill(prog, p.rangeZoomLevel)
              or ((prog + 1) / 2)
      if t.rangeState == "MELEE" then
        mode, color = "melee", skinColor("reactColorRangeDeadzone", REACT.RANGE_MELEE)
      elseif t.rangeState == "SWEET" then
        if (t.rangeProg or -1) > Engine.PERFECT_AT then
          mode, color = "super", skinColor("reactColorRangePerfect", REACT.RANGE_SUPER)
        else
          mode, color = "sweet", skinColor("reactColorRangeSweet", REACT.RANGE_SWEET)
        end
      else
        mode, color = "close", skinColor("reactColorRangeClose", REACT.RANGE_CLOSE)
      end
    end
  end

  if mode ~= self._lastRangeMode then
    range.fill:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    self._lastRangeMode = mode
  end
  if not self._lastRatio or math.abs(self._lastRatio - ratio) > 0.005 then
    range.fill:SetWidth(math.max(0.01, ratio * (self._innerW or 0)))
    self._lastRatio = ratio
  end
  if text ~= self._lastRangeText then
    range.label:SetText(text)
    if text ~= "" and textColor then
      range.label:SetTextColor(textColor[1], textColor[2], textColor[3], 1)
    end
    self._lastRangeText = text
  end
end

function ReactCluster:RefreshMana(state)
  local mana = self.mana
  local pl = state.player
  local pct = (pl and pl.manaPct) or 100
  local ratio = pct / 100
  if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
  if not self._lastManaRatio or math.abs(self._lastManaRatio - ratio) > 0.005 then
    mana.fill:SetWidth(math.max(0.01, ratio * (self._innerW or 0)))
    self._lastManaRatio = ratio
  end
  -- Center text via the shared formatter (reactManaText: none/percent/value/
  -- both, React-scoped counterpart of the classic manaBarText). Diff on the
  -- integers + mode so the format only runs when the display changes.
  local mode = profile().reactManaText or "percent"
  local iCur = math.floor(((pl and pl.manaCur) or 0) + 0.5)
  local max  = (pl and pl.manaMax) or 0
  local iPct = math.floor(pct + 0.5)
  if mode ~= self._lastManaMode or iCur ~= self._lastManaCur
     or max ~= self._lastManaMax or iPct ~= self._lastManaPct then
    mana.text:SetText(Nock.UI.FormatManaText(mode, iCur, max, iPct))
    self._lastManaMode, self._lastManaCur = mode, iCur
    self._lastManaMax,  self._lastManaPct = max, iPct
  end
end

function ReactCluster:Refresh(state)
  if not self.frame:IsShown() then return end
  if self.auto:IsShown()  then self:RefreshAuto(state)  end
  if self.melee:IsShown() then self:RefreshMelee(state) end
  if self.range:IsShown() then self:RefreshRange(state) end
  if self.mana:IsShown()  then self:RefreshMana(state)  end
end
