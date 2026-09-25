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
  FONT_STAGE = 9,    -- melee takeover word (GO IN / HOLD / BACK OUT / RELEASE): READY's size (user, 2026-09-02)

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
  MELEE_OFF    = { 1.00, 1.00, 1.00, 1.00 },  -- dual wield: the off hand's swing (white)
  MELEE_GREEN  = { 0.15, 0.68, 0.38, 1.00 },  -- Raptor ready
  MANA_FILL    = { 0.20, 0.55, 1.00, 1.00 },
  MANA_TICK    = { 1.00, 1.00, 1.00, 0.80 },  -- mana tick spark (off by default)
  -- Range colors = the user's configured values from the reference
  -- melee-weave WA (attribution TBD — the circulating copy is a fork).
  RANGE_MELEE = { 0.68, 0.18, 0.20, 1.00 },  -- MELEE (meleeRangeColor)
  RANGE_SUPER = { 0.17, 0.78, 0.11, 1.00 },  -- SWEET near the melee edge (superSweetSpotColor)
  RANGE_SWEET = { 0.85, 0.66, 0.00, 1.00 },  -- SWEET (sweetSpotColor)
  RANGE_CLOSE = { 0.00, 0.83, 0.75, 1.00 },  -- CLOSE (closeRangeColor)
  RANGE_DIM   = { 0.30, 0.30, 0.30, 1.00 },  -- no valid target
  RANGE_RESYNC = { 1.00, 0.58, 0.10, 1.00 }, -- estimate degraded (matches classic bar)
  STRIP_OFF   = { 0.16, 0.16, 0.16, 1.00 },  -- position strip: segment not in range
  STRIP_DEAD  = { 0.35, 0.10, 0.11, 1.00 },  -- position strip: the dead gap (melee segment)
  STRIP_H     = 4,                           -- position strip height px
  STRIP_LABEL_MIN = 9,                       -- strip height from which RANGED / MELEE labels fit
  RANGE_DIVIDER   = { 1.00, 1.00, 1.00, 0.90 },  -- centre tick (melee boundary)
  RANGE_DIVIDER_W = 1,                           -- centre tick width px
  TEXT         = { 1.00, 1.00, 1.00, 1.00 },
  MARCH        = { 0.00, 0.00, 0.00, 0.55 },  -- takeover triangles: translucent dark over the stage fill
  MARCH_GAP    = 0.6,                         -- gap between triangles, as a fraction of their size
  MARCH_INSET  = 1,                           -- px between a triangle and the bar's inner top/bottom
}
-- Solid right-pointing triangle, 20x20 (not power-of-two: no mip chain), RGB
-- white so the vertex colour tints it; left-pointing = flipped tex coords.
local MARCH_TEX = "Interface\\AddOns\\Nock\\Media\\ReactChevron"

-- React range bar — consumes the shared range engine published by
-- Modules/RangeFinder.lua via Modules/RangeEngine.lua (state.target
-- .rangeState/rangeProg/rangeBracket/rangeEstimateStale). Full parity with
-- the classic bar — finding ladder (drain/block per rangeFinderFindingStyle)
-- beyond ~10yd, weave fill inside, orange parked-at-tick RESYNC — but the
-- palette stays hardcoded to the reference WA look (unlike the classic
-- bar's user-configurable colors).

local MAX_BRACKETS = 12  -- 6 eWS bounds x 2 mirrored sides

-- Weave-coach stage cue on the melee bar (state.weave.stage, semantics in
-- Modules/WeaveCoach.lua; looks in Nock.UI.ReactStageLook). The one that
-- saves weaves: HOLD means the queued hit has NOT landed yet — releasing
-- there /stopattack-cancels the swing and the Raptor silently. RELEASE (or
-- the struck sound) is the safe let-go. With reactMeleeStageCue (opt-in)
-- the stage TAKES OVER the bar: full fill in the stage colour, triangles
-- marching in the direction to move, the word over them. Off, it is the
-- small centred text in the stage colour, as before 1.1.8.
local FLASH_SEC = 0.4   -- RELEASE: fill lerped from white back to green over this

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

-- Swing fills close visibly (Nock.UI.SwingFillProgress): at the shot a bar
-- that has not reached the end glides shut over EASE_SEC, stays shut HOLD_SEC,
-- then the new cycle starts from empty and catches up to its true position
-- over CATCH_SEC.
local EASE_SEC  = Nock.UI.SWING_CLOSE.ease
local HOLD_SEC  = Nock.UI.SWING_CLOSE.hold
local CATCH_SEC = Nock.UI.SWING_CLOSE.catch

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
  -- the anchor is kept so the skin's vertical nudge can re-place the text
  mediaTexts[#mediaTexts + 1] = { fs = fs, size = size, bar = bar, point = point, x = x or 0 }
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
  -- Dual wield (Forever, from level 20): the off hand's swing in the lower
  -- half of the row, in its own colour (white; Raptor replaces a main-hand
  -- swing only, so it never turns green). Hidden with one weapon; ApplyMeleeSplit places it.
  melee.offFill = makeFill(melee, REACT.MELEE_BLUE)
  melee.offFill:Hide()
  melee.text = makeText(melee, REACT.FONT_SMALL, "CENTER")
  -- Weave-stage takeover: a child frame over the fill holding two clipped
  -- half-width triangle runs and the stage word. Each run is a carrier frame
  -- with a pool of MARCH_TEX textures spaced one pitch apart (sized by
  -- ApplyLayout); the tick slides the CARRIER by Nock.UI.MarchOffset, one
  -- SetPoint per half. Child frames draw above the bar's own regions, so the
  -- word gets a frame of its own above the runs. Hidden whenever no stage is
  -- up.
  local cue = CreateFrame("Frame", nil, melee)
  cue:SetAllPoints(melee)
  cue:SetFrameLevel(melee:GetFrameLevel() + 1)
  local function makeMarch(side)
    local f = CreateFrame("Frame", nil, cue)
    if f.SetClipsChildren then f:SetClipsChildren(true) end
    f:SetPoint("TOP",    melee, "TOP",    0, -1)
    f:SetPoint("BOTTOM", melee, "BOTTOM", 0,  1)
    if side == "L" then
      f:SetPoint("LEFT",  melee, "LEFT",   1, 0)
      f:SetPoint("RIGHT", melee, "CENTER", 0, 0)
    else
      f:SetPoint("LEFT",  melee, "CENTER", 0, 0)
      f:SetPoint("RIGHT", melee, "RIGHT", -1, 0)
    end
    local carrier = CreateFrame("Frame", nil, f)
    carrier:SetPoint("LEFT", f, "LEFT", 0, 0)
    carrier:SetSize(1, 1)
    f.carrier = carrier
    f.tris = {}            -- texture pool, grown by ApplyLayout
    f.side = side
    f.pitch = 8            -- set by ApplyLayout from the bar height
    f.count = 0
    f:Hide()
    return f
  end
  cue.marchL = makeMarch("L")
  cue.marchR = makeMarch("R")
  local stageF = CreateFrame("Frame", nil, cue)
  stageF:SetAllPoints(cue)
  stageF:SetFrameLevel(cue:GetFrameLevel() + 2)
  melee.stageText = makeText(stageF, REACT.FONT_STAGE, "CENTER")
  cue:Hide()
  melee.cue = cue
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

  -- Position strip (experimental, reactRangeStrip): two bordered segments
  -- welded under the range bar, LEFT = can-shoot probe (RANGED), RIGHT = melee
  -- probe (MELEE), matching the bar's own left-far / right-close reading.
  -- Colours and the reading come from Nock.UI.ReactRangeStripLook on the tick;
  -- centred labels draw once the strip is tall enough (reactRangeStripLabels).
  local strip = CreateFrame("Frame", "NockReactRangeStrip", container)
  strip:SetHeight(REACT.STRIP_H)
  strip.ranged = createReactBar(strip, nil, REACT.STRIP_H)
  strip.melee  = createReactBar(strip, nil, REACT.STRIP_H)
  strip.ranged:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
  strip.ranged:SetPoint("BOTTOMRIGHT", strip, "BOTTOM", 0, 0)
  strip.melee:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
  strip.melee:SetPoint("BOTTOMLEFT", strip, "BOTTOM", -1, 0)
  for _, seg in ipairs({ strip.ranged, strip.melee }) do
    seg.fill = seg:CreateTexture(nil, "ARTWORK"); seg.fill:SetTexture(WHITE8X8)
    seg.fill:SetPoint("TOPLEFT", seg, "TOPLEFT", 1, -1); seg.fill:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -1, 1)
    seg.label = makeText(seg, REACT.FONT_SMALL, "CENTER")
  end
  strip.ranged.label:SetText("RANGED"); strip.melee.label:SetText("MELEE")
  strip:Hide()
  self.strip = strip
  -- Forever: the range row is the Range Finder ladder (UI/ReactRangeLadder.lua,
  -- spec 2026-09-24); the strip above stays TBC's opt-in extra.
  if Nock.Flavor and Nock.Flavor.forever and Nock.UI.RangeLadder then
    self.ladder = Nock.UI.RangeLadder.Create(container, {
      makeText = makeText, bg = REACT.BAR_BG, border = REACT.BORDER, fontSize = REACT.FONT_SMALL,
    })
    self.ladder:Hide()
  end

  -- Mana bar: thin fill + centered percent.
  local mana = createReactBar(container, "NockReactMana", REACT.MANA_H)
  mana.fill = makeFill(mana, REACT.MANA_FILL)
  mana.fill:SetPoint("TOPLEFT", mana, "TOPLEFT", 1, -1)
  mana.fill:SetPoint("BOTTOMLEFT", mana, "BOTTOMLEFT", 1, 1)
  mana.text = makeText(mana, REACT.FONT_SMALL, "CENTER")
  -- Forever sink: a StatusBar over the plain fill, fed the raw (secret) power
  -- values that StatusBar:SetValue accepts. Hidden on TBC, where the plain
  -- fill runs off state.player.manaPct. Its own frame so the secret aspect
  -- never sticks to a region Nock reads back.
  local sink = CreateFrame("StatusBar", nil, mana)
  sink:SetPoint("TOPLEFT", mana, "TOPLEFT", 1, -1)
  sink:SetPoint("BOTTOMRIGHT", mana, "BOTTOMRIGHT", -1, 1)
  sink:SetStatusBarTexture(WHITE8X8)
  sink:SetStatusBarColor(unpack(REACT.MANA_FILL))
  sink:SetMinMaxValues(0, 1)
  sink:SetValue(0)
  sink:Hide()
  mana.sink = sink
  -- A child frame draws above its parent's regions, so the centre text moves
  -- to a layer one level above the sink (its anchors to `mana` are kept).
  local textLayer = CreateFrame("Frame", nil, mana)
  textLayer:SetAllPoints(mana)
  textLayer:SetFrameLevel(sink:GetFrameLevel() + 1)
  mana.text:SetParent(textLayer)
  mana.textLayer = textLayer
  -- The tick spark is created below; it is re-parented onto this layer right
  -- after, for the same reason (the sink would paint over it).
  -- Mana tick spark (reactManaTick, opt-in): placed by RefreshMana from
  -- state.player.manaTick.progress along reactManaTickDirCombat/Ooc.
  local spark = mana:CreateTexture(nil, "OVERLAY")
  spark:SetTexture(WHITE8X8)
  spark:SetSize(2, REACT.MANA_H - 2)
  spark:SetVertexColor(unpack(REACT.MANA_TICK))
  spark:Hide()
  spark:SetParent(mana.textLayer)
  mana.spark = spark
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
  -- The range bar needs its module (RangeFinder); on Forever that lands in
  -- M3, so until it is loaded the row stays out of the stack instead of
  -- drawing an empty strip. The profile key is left untouched.
  local rangeFeed = not (Nock.Flavor and Nock.Flavor.forever) or Nock:GetModule("RangeFinder", true) ~= nil
  local show = {
    auto  = p.reactShowAutoBar  ~= false,
    melee = p.reactShowMeleeBar ~= false,
    range = p.reactShowRangeBar ~= false and rangeFeed,
    mana  = p.reactShowManaBar  ~= false,
  }
  local h = {
    auto  = skinNum("reactAutoH",  REACT.AUTO_H),
    melee = skinNum("reactMeleeH", REACT.MELEE_H),
    range = skinNum("reactRangeH", REACT.RANGE_H),
    mana  = skinNum("reactManaH",  REACT.MANA_H),
  }

  -- TBC: the position strip rides under the range bar, sharing its border
  -- seam (experimental, reactRangeStrip). Forever: the range row is the
  -- Range Finder ladder (spec 2026-09-24) at the range row's height, each
  -- segment labelled inside itself (reactRangeLabels), and neither the fill
  -- bar nor the strip is drawn.
  local forever = Nock.Flavor and Nock.Flavor.forever
  local showStrip = show.range and not forever and p.reactRangeStrip == true
  local hStrip = showStrip and math.max(2, math.min(14, tonumber(p.reactRangeStripH) or REACT.STRIP_H)) or 0
  local showLadder = (show.range and forever and self.ladder ~= nil) and true or false
  local ladderLabels = p.reactRangeLabels ~= false
  local hLadder = showLadder and h.range or 0
  local showRangeBar = show.range and not forever

  local order = Nock.UI.ResolveReactBarOrder(p.reactBarOrder)
  local ys = {}
  local y = 0
  for i = 1, #order do
    local k = order[i]
    if show[k] then
      if y > 0 then y = y + REACT.GAP end
      if k == "range" and forever then
        ys.ladder = y
        y = y + hLadder
      else
        ys[k] = y
        y = y + h[k]
        if k == "range" and showStrip then
          y = y + REACT.GAP
          ys.strip = y
          y = y + hStrip
        end
      end
    end
  end

  return {
    w = w,
    showAuto = show.auto, showMelee = show.melee,
    showRange = showRangeBar, showMana = show.mana, showStrip = showStrip,
    yAuto = ys.auto, yMelee = ys.melee, yRange = ys.range, yMana = ys.mana, yStrip = ys.strip,
    hAuto = h.auto, hMelee = h.melee, hRange = h.range, hMana = h.mana, hStrip = hStrip,
    showLadder = showLadder, yLadder = ys.ladder, hLadder = hLadder, ladderLabels = ladderLabels,
    total = math.max(y, 1),
  }
end

-- Logical (unscaled) height of the row, for HUD's LAYOUT height fn.
function ReactCluster:ContentHeight()
  return Nock.UI.DeviceRound(self:Geometry().total, Nock.UI.PixelScale(self.frame))
end

-- (Re)size and (re)anchor everything from Geometry, then invalidate every diff
-- cache so the next Refresh repaints against the new dimensions.
function ReactCluster:ApplyLayout()
  local g = self:Geometry()
  local p = profile()
  local f = self.frame
  -- Row offsets, heights and the width rounded to whole device pixels (the
  -- cluster's own top is snapped by the HUD layout), so every bar's 1 px edge
  -- lands on one pixel row at any UI scale.
  local dev = Nock.UI.PixelScale(f)
  local w = Nock.UI.DeviceRound(g.w, dev)
  -- An EVEN inner width in device pixels: the converge halves are each half
  -- of it, and with an odd count they meet on a half pixel, which the
  -- rasteriser resolves as a one-pixel seam at the centre of a full bar
  -- ("never quite reaches the centre", Forever gate 2026-09-22).
  if dev and dev > 0 then
    local wpx = math.floor(w * dev + 0.5)
    if wpx % 2 == 1 then w = (wpx + 1) / dev end
  end
  -- The cluster hangs from its BOTTOM in the HUD stack: a fractional height
  -- in device pixels would lift its top, and every bar with it, off the grid.
  f:SetSize(w, Nock.UI.DeviceRound(g.total, dev))
  -- The bars' edge is one DEVICE pixel (the backdrop's, see
  -- Nock.UI.PixelBackdrop): fills, marks and the spark inset by the same
  -- amount, so the first fill row is a full fill row rather than a blend.
  local e = Nock.UI.DeviceWidth(1, dev)
  self._edge = e
  local innerW = w - 2 * e
  local function innerH(h) return math.max(1, Nock.UI.DeviceRound(h, dev) - 2 * e) end
  local hAutoIn, hMeleeIn, hRangeIn, hManaIn = innerH(g.hAuto), innerH(g.hMelee), innerH(g.hRange), innerH(g.hMana)
  -- Re-anchor a fill/sink inside its bar by the device edge.
  local function insetFill(t, bar, side)
    t:ClearAllPoints()
    if side == "right" then
      t:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -e, -e)
      t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -e, e)
    elseif side == "both" then
      t:SetPoint("TOPLEFT", bar, "TOPLEFT", e, -e)
      t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -e, e)
    else
      t:SetPoint("TOPLEFT", bar, "TOPLEFT", e, -e)
      t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", e, e)
    end
  end
  insetFill(self.auto.fillR, self.auto, "right")
  insetFill(self.range.fill, self.range, "left")
  insetFill(self.mana.fill, self.mana, "left")
  if self.mana.sink then insetFill(self.mana.sink, self.mana, "both") end
  insetFill(self.strip.ranged.fill, self.strip.ranged, "both")
  insetFill(self.strip.melee.fill, self.strip.melee, "both")
  local function placeBar(bar, y, h, shown)
    bar:SetHeight(math.max(Nock.UI.DeviceRound(h, dev), Nock.UI.DeviceWidth(1, dev)))
    if shown then
      bar:ClearAllPoints()
      y = Nock.UI.DeviceRound(y, dev)
      bar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -y)
      bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
      bar:Show()
    else
      bar:Hide()
    end
  end
  placeBar(self.auto,  g.yAuto,  g.hAuto,  g.showAuto)
  placeBar(self.melee, g.yMelee, g.hMelee, g.showMelee)
  placeBar(self.range, g.yRange or 0, g.hRange, g.showRange)
  placeBar(self.mana,  g.yMana,  g.hMana,  g.showMana)
  placeBar(self.strip, g.yStrip or 0, math.max(1, g.hStrip), g.showStrip)
  self.strip.ranged:SetHeight(math.max(1, g.hStrip)); self.strip.melee:SetHeight(math.max(1, g.hStrip))
  -- The two halves meet on a whole device column and share that 1 px seam.
  local edge = Nock.UI.DeviceWidth(1, dev)
  local wL = Nock.UI.DeviceRound(w / 2, dev)
  self.strip.ranged:ClearAllPoints()
  self.strip.ranged:SetPoint("TOPLEFT", self.strip, "TOPLEFT", 0, 0)
  self.strip.ranged:SetPoint("BOTTOMLEFT", self.strip, "BOTTOMLEFT", 0, 0)
  self.strip.ranged:SetWidth(wL)
  self.strip.melee:ClearAllPoints()
  self.strip.melee:SetPoint("TOPRIGHT", self.strip, "TOPRIGHT", 0, 0)
  self.strip.melee:SetPoint("BOTTOMRIGHT", self.strip, "BOTTOMRIGHT", 0, 0)
  self.strip.melee:SetWidth(w - wL + edge)
  -- labels only when they fit (the small font needs about 9 px)
  local labels = p.reactRangeStripLabels == true and g.hStrip >= REACT.STRIP_LABEL_MIN
  self.strip.ranged.label:SetShown(labels); self.strip.melee.label:SetShown(labels)
  self._lastStripLook = nil
  -- Forever ladder: placed like a bar; its segments and labels are laid out
  -- by RefreshLadder against the finder's current segment list (_ladderRev
  -- = nil forces that on the next refresh, e.g. after a font or width change).
  if self.ladder then
    placeBar(self.ladder, g.yLadder or 0, math.max(1, g.hLadder), g.showLadder)
    self._ladderGeo = { w = w, hBar = Nock.UI.DeviceRound(math.max(1, g.hLadder), dev), labels = g.ladderLabels, dev = dev, e = e }
    self._ladderRev = nil
  end

  self._halfW  = innerW / 2
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
  local style = Nock.UI.GetReactFontStyle()
  for i = 1, #mediaTexts do
    local e = mediaTexts[i]
    Nock.UI.SafeSetFont(e.fs, font, math.max(6, e.size + delta), style)
    Nock.UI.ApplyReactTextShadow(e.fs)
  end

  -- Melee takeover triangle runs: triangles the bar's inner height (minus
  -- MARCH_INSET each side), one pitch apart, two pitches more than fill a
  -- half so the slide (always within [-pitch, 0]) never uncovers an edge.
  -- Pool grows and never shrinks; extras hide. Direction (tex-coord flip) is
  -- set per stage by RefreshMelee. Not the tick: once per layout.
  local cue = self.melee.cue
  local size = math.max(2, hMeleeIn - 2 * REACT.MARCH_INSET)
  local pitch = size * (1 + REACT.MARCH_GAP)
  local count = math.ceil(self._halfW / pitch) + 2
  local function buildMarch(mf)
    mf.pitch, mf.count = pitch, count
    mf.carrier:SetSize(count * pitch, size)
    for i = 1, count do
      local t = mf.tris[i]
      if not t then
        t = mf.carrier:CreateTexture(nil, "ARTWORK")
        t:SetTexture(MARCH_TEX)
        t:SetVertexColor(unpack(REACT.MARCH))
        mf.tris[i] = t
      end
      t:SetSize(size, size)
      t:ClearAllPoints()
      t:SetPoint("LEFT", mf.carrier, "LEFT", (i - 1) * pitch, 0)
      t:Show()
    end
    for i = count + 1, #mf.tris do mf.tris[i]:Hide() end
  end
  buildMarch(cue.marchL)
  buildMarch(cue.marchR)

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
    tL:SetSize(w, hAutoIn)
    tR:SetSize(w, hAutoIn)
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
    auto.brackets[i]:SetSize(bw, hAutoIn)
    auto.brackets[i]:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 1)
  end
  local gn = skinNum("reactGcdDividerWidth", REACT.GCD_DIVIDER_W)
  devW.reactGcdDividerWidth = gn
  local gw = Nock.UI.DeviceWidth(gn, ps)
  local gc = skinColor("reactColorGcdDivider", REACT.GCD_DIVIDER)
  auto.gcdL:SetSize(gw, hAutoIn)
  auto.gcdR:SetSize(gw, hAutoIn)
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
  self.range.tick:SetSize(dw, hRangeIn)
  self.range.tick:SetVertexColor(dc[1], dc[2], dc[3], dc[4] or 1)

  -- Construction-time fill colors re-applied from the skin resolver (melee
  -- and range fills repaint through their nil'd diff caches below).
  local cAuto = skinColor("reactColorAutoFill", REACT.AUTO_FILL)
  auto.fillL:SetVertexColor(cAuto[1], cAuto[2], cAuto[3], cAuto[4] or 1)
  auto.fillR:SetVertexColor(cAuto[1], cAuto[2], cAuto[3], cAuto[4] or 1)
  local cMana = skinColor("reactColorManaFill", REACT.MANA_FILL)
  self.mana.fill:SetVertexColor(cMana[1], cMana[2], cMana[3], cMana[4] or 1)
  if self.mana.sink then
    self.mana.sink:SetStatusBarTexture(tex)
    self.mana.sink:SetStatusBarColor(cMana[1], cMana[2], cMana[3], cMana[4] or 1)
  end
  local cTick = skinColor("reactColorManaTick", REACT.MANA_TICK)
  self.mana.spark:SetVertexColor(cTick[1], cTick[2], cTick[3], cTick[4] or 1)
  self.mana.spark:SetHeight(hManaIn)
  self._lastManaSparkX = nil

  -- Fill directions (React HUD tab). Auto: converge (reference) | ltr | rtl —
  -- fillL doubles as the single directional fill, fillR only participates in
  -- converge mode. Melee: ltr | rtl.
  self._dirAuto = p.reactDirAuto or "converge"
  insetFill(auto.fillL, auto, self._dirAuto == "rtl" and "right" or "left")
  if self._dirAuto == "converge" then
    auto.fillR:Show()
  else
    auto.fillR:Hide()
  end
  self._dirMelee = p.reactDirMelee or "ltr"
  self._meleeInH = hMeleeIn
  self._lastOffP = nil
  self:ApplyMeleeSplit(self._meleeSplit or false)

  -- Feature-gated delay readout (React HUD tab; default off).
  if p.reactShowDelay == true then
    self.auto.delayText:Show()
  else
    self.auto.delayText:Hide()
  end
  -- Rotation notation gate (React HUD tab; default on).
  -- Forever has no rotation papers yet, so there is no notation to name.
  if p.reactShowNotation == false or (Nock.Flavor and Nock.Flavor.forever) then
    auto.notationText:Hide()
  else
    auto.notationText:Show()
  end

  -- Invalidate diff/signature caches (width or bar set may have changed).
  self._lastAutoP     = nil
  self._lastAutoW     = nil
  self._gcdX          = nil   -- forces the GCD divider to re-place next tick
  self._markSd        = nil   -- forces PositionAutoMarks next tick
  self._markWindup    = nil
  self._lastDelaySec  = nil
  self._lastDelayText = nil
  self._lastNotation  = nil
  self._lastMeleeP    = nil
  self._lastMeleeText = nil
  self._lastMeleeColor = nil
  self._lastStage     = nil   -- re-arms the takeover (runs rebuilt above)
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
-- One threshold mark (a mirrored pair in converge mode, the *L texture alone
-- in the directional modes) `T` seconds before the release on a cycle of
-- `sd` seconds. Shared by the TBC clip/wind-up marks and the Forever
-- spell-queue mark.
function ReactCluster:PlaceMarkPair(tL, tR, sd, T, wKey)
  local auto = self.auto
  if sd <= 0 or T <= 0 then
    tL:Hide(); tR:Hide()
    return
  end
  -- Clamp rather than hide when the cast can't fit the cycle at all — a
  -- missing mark reads as "no clip risk". Mirrors Frame_SwingTimers:place.
  if T > sd then T = sd end
  -- Directional (ltr/rtl) modes project onto the FULL inner width from the
  -- fill's origin edge; converge keeps the reference mirrored pairs.
  local dir = self._dirAuto or "converge"
  local ps  = self._pixelScale
  local devW = self._markDevW or {}
  -- The bar's edges in PHYSICAL pixels: the pixel grid lives in absolute
  -- screen space, and the two edges carry different sub-pixel phases, so each
  -- half of a mirrored pair snaps against its own edge. nil before layout ->
  -- relative snap, corrected on the next re-place.
  local barL, barR = auto:GetLeft(), auto:GetRight()
  local leftPx  = (ps and barL) and barL * ps or nil
  local rightPx = (ps and barR) and barR * ps or nil
  -- Shared projection (Nock.UI.ReactAxisPoint) — same one the GCD divider
  -- places through, so the two can't drift apart.
  local edge, x, mirrored, xR =
    Nock.UI.ReactAxisPoint((sd - T) / sd, dir, self._halfW or 0, self._innerW or 0,
                           ps, devW[wKey], leftPx, rightPx, self._edge)
  tL:ClearAllPoints(); tL:SetPoint("CENTER", auto, edge, x, 0); tL:Show()
  if mirrored then
    tR:ClearAllPoints(); tR:SetPoint("CENTER", auto, "RIGHT", -xR, 0); tR:Show()
  else
    tR:Hide()
  end
end

function ReactCluster:PositionAutoMarks(sd, steadyT, multiT, windup)
  local auto = self.auto
  local halfW = self._halfW or 0
  local dir = self._dirAuto or "converge"
  local innerW = self._innerW or 0
  local ps   = self._pixelScale
  local devW = self._markDevW or {}
  local barL, barR = auto:GetLeft(), auto:GetRight()
  local leftPx  = (ps and barL) and barL * ps or nil
  local rightPx = (ps and barR) and barR * ps or nil
  local function placePair(tL, tR, T, wKey) self:PlaceMarkPair(tL, tR, sd, T, wKey) end
  -- The vertical marks are individually hideable: reactShowClipTicks owns the
  -- Steady/Multi pairs, the SHARED showWindupMark owns the commit mark below.
  if profile().reactShowClipTicks == false then
    auto.steadyL:Hide(); auto.steadyR:Hide()
    auto.multiL:Hide();  auto.multiR:Hide()
  else
    placePair(auto.steadyL, auto.steadyR, steadyT, "reactTickSteadyWidth")
    placePair(auto.multiL,  auto.multiR,  multiT, "reactTickMultiWidth")
  end
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
          Nock.UI.ReactAxisPoint(lo / sd, dir, halfW, innerW, ps, devW.reactBracketWidth, leftPx, rightPx, self._edge)
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
                           (ps and barR) and barR * ps or nil, self._edge)
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
  local h = self._autoFill
  if not h then h = {}; self._autoFill = h end
  if Nock.AutoSwingLive() then
    p01 = Nock.UI.SwingFillProgress(h, r.swingStart, r.swingRemaining, r.swingDuration,
                                    GetTime(), HOLD_SEC, EASE_SEC, CATCH_SEC)
  else
    -- Blank bar (auto-repeat off, target out of range): the next live cycle
    -- is a fresh start, not a shot to close.
    Nock.UI.SwingFillBlank(h)
  end
  -- Fill widths in whole device pixels (Nock.UI.DeviceRound): the moving edge
  -- never sits between two columns, and a full bar's halves meet exactly.
  -- Diffed on the rounded width, so SetWidth runs once per pixel crossed.
  local span = (self._dirAuto == "converge") and (self._halfW or 0) or (self._innerW or 0)
  local fw = Nock.UI.DeviceRound(p01 * span, ps)
  if fw ~= self._lastAutoW then
    -- Forever diagnostic (/nock probe "auto bar cycles"): at each reset note
    -- what the previous cycle ended on -- bar and fill widths in device
    -- pixels, the peak fill and how long the fill sat at its final width.
    if Nock.Flavor and Nock.Flavor.forever and self._lastAutoW and self._lastAutoW > 0 and fw < self._lastAutoW then
      local log = self._cycleLog
      if not log then log = {}; self._cycleLog = log end
      local now = GetTime()
      log[#log + 1] = {
        barPx  = ps and math.floor(auto:GetWidth() * ps + 0.5) or -1,
        fillPx = ps and math.floor(self._lastAutoW * ps + 0.5) or -1,
        peakP  = self._lastAutoP or 0,
        held   = self._lastAutoAt and (now - self._lastAutoAt) or 0,
        halves = self._dirAuto == "converge",
      }
      if #log > 12 then table.remove(log, 1) end
    end
    -- Remember the ROUNDED width (0 when empty); the 0.01 floor is only for
    -- SetWidth, where 0 would let the texture take its own size.
    self._lastAutoW = fw
    self._lastAutoP = p01
    self._lastAutoAt = GetTime()
    fw = math.max(0.01, fw)
    auto.fillL:SetWidth(fw)
    if self._dirAuto == "converge" then auto.fillR:SetWidth(fw) end
  end

  -- Forever: no clip model (no wind-up feed, and the cast time behind
  -- Nock.ClipThreshold reads GetRangedHaste, which is secret in combat). The
  -- one mark that has a plain feed is the client's spell-queue window: a
  -- press inside the last queueWindow of the cycle is queued behind the shot
  -- instead of clipping it. Drawn with the wind-up pair (same meaning: the
  -- lower edge of the clip band), gated by the shared showWindupMark toggle.
  if Nock.Flavor and Nock.Flavor.forever then
    local sd = r.swingDuration
    local qw = (profile().showWindupMark ~= false) and (r.queueWindow or 0) or 0
    local barLeft = auto:GetLeft()
    if sd ~= self._markSd or qw ~= self._markWindup or barLeft ~= self._markBarLeft then
      self:PlaceMarkPair(auto.windupL, auto.windupR, sd, qw, "reactTickWindupWidth")
      self._markSd      = sd
      self._markWindup  = qw
      self._markBarLeft = barLeft
    end
  else
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
  end

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

-- Dual wield splits the melee row's inner height: the main hand on top gets
-- the odd device pixel. `split` false = one fill, full height (offH nil).
function ReactCluster.MeleeSplit(innerH, split, round)
  if not split then return innerH, nil end
  local top = round(innerH / 2)
  return top, innerH - top
end

-- Anchor the melee fill(s) inside the bar by the device edge, from the fill
-- side (reactDirMelee). Re-run on a layout and whenever the split changes.
function ReactCluster:ApplyMeleeSplit(split)
  local melee, e = self.melee, self._edge or 1
  local side = (self._dirMelee == "rtl") and "RIGHT" or "LEFT"
  local x = (side == "RIGHT") and -e or e
  local round = function(v) return Nock.UI.DeviceRound(v, self._pixelScale) end
  local mainH, offH = ReactCluster.MeleeSplit(self._meleeInH or 1, split, round)
  local f = melee.fill
  f:ClearAllPoints()
  f:SetPoint("TOP" .. side, melee, "TOP" .. side, x, -e)
  local o = melee.offFill
  if offH then
    f:SetHeight(mainH)
    o:ClearAllPoints()
    o:SetPoint("BOTTOM" .. side, melee, "BOTTOM" .. side, x, e)
    o:SetHeight(offH)
    local c = skinColor("reactColorMeleeOff", REACT.MELEE_OFF)
    o:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    o:Show()
  else
    f:SetPoint("BOTTOM" .. side, melee, "BOTTOM" .. side, x, e)
    o:Hide()
  end
  self._meleeSplit = split
  self._lastMeleeP, self._lastOffP = nil, nil
end

function ReactCluster:RefreshMelee(state)
  local melee = self.melee
  local m = state.melee
  local ready = (m.swingStart == 0) or (m.swingRemaining <= 0)

  -- Weave-coach stage -> look. `takeover` is the full-bar cue; with the
  -- option off the stage only owns the small text (below).
  local now = GetTime()
  local stage = Nock.UI.CoachStage(state, now)   -- coach stage, or the settings preview cycle
  local look = Nock.UI.ReactStageLook(stage)
  local takeover = (look and profile().reactMeleeStageCue == true) and true or false
  local cue = melee.cue
  -- Two weapons split the row; a takeover owns the whole row.
  local split = (m.dualWield == true) and not takeover
  if split ~= (self._meleeSplit or false) then self:ApplyMeleeSplit(split) end

  if stage ~= self._lastStage or takeover ~= self._lastTakeover then
    self._lastStage, self._lastTakeover = stage, takeover
    -- The fill and the texts swap owners on this edge: drop every cache.
    self._lastMeleeP, self._lastMeleeColor, self._lastMeleeText = nil, nil, nil
    if takeover then
      melee.stageText:SetText(look.text)
      local mL, mR = cue.marchL, cue.marchR
      if look.march ~= 0 then
        -- Inward: the left half points right, the right half points left.
        -- Outward: the mirror. A left-pointing triangle is the texture with
        -- its horizontal tex coords flipped.
        local inward = look.march > 0
        local function point(mf, right)
          local tris = mf.tris
          for i = 1, mf.count do
            if right then tris[i]:SetTexCoord(0, 1, 0, 1)
            else tris[i]:SetTexCoord(1, 0, 0, 1) end
          end
        end
        point(mL, inward)
        point(mR, not inward)
        mL:Show(); mR:Show()
      else
        mL:Hide(); mR:Hide()
      end
      self._flashAt = look.flash and now or nil
      cue:Show()
    else
      cue:Hide()
      self._flashAt = nil
    end
  end

  if takeover then
    -- Full fill in the stage colour; RELEASE enters white and settles to the
    -- colour over FLASH_SEC (painted every tick only while it lasts).
    if self._lastMeleeP ~= 1 then
      melee.fill:SetWidth(math.max(0.01, Nock.UI.DeviceRound(self._innerW or 0, self._pixelScale)))
      self._lastMeleeP = 1
    end
    local mix = self._flashAt and Nock.UI.FlashMix(now - self._flashAt, FLASH_SEC) or 0
    if mix > 0 or self._wasFlashing or self._lastMeleeColor ~= look then
      local c = look.fill
      melee.fill:SetVertexColor(c[1] + (1 - c[1]) * mix, c[2] + (1 - c[2]) * mix,
                                c[3] + (1 - c[3]) * mix, c[4] or 1)
      self._lastMeleeColor = look
    end
    self._wasFlashing = mix > 0
    if mix <= 0 then self._flashAt = nil end
    if self._lastMeleeText ~= "" then
      melee.text:SetText("")
      self._lastMeleeText = ""
    end
    -- The runs slide every tick: left half toward/away from the centre per
    -- the stage, right half the mirror.
    if look.march ~= 0 then
      local mL, mR = cue.marchL, cue.marchR
      mL.carrier:SetPoint("LEFT", mL, "LEFT", Nock.UI.MarchOffset(now, mL.pitch,  look.march), 0)
      mR.carrier:SetPoint("LEFT", mR, "LEFT", Nock.UI.MarchOffset(now, mR.pitch, -look.march), 0)
    end
    return
  end

  local p01 = 1
  local h = self._meleeFill
  if not h then h = {}; self._meleeFill = h end
  if not ready and m.swingDuration > 0 then
    p01 = Nock.UI.SwingFillProgress(h, m.swingStart, m.swingRemaining, m.swingDuration,
                                    now, HOLD_SEC, EASE_SEC, CATCH_SEC)
  else
    -- Ready = the bar is full: tell the helper it closed, so the next swing
    -- starts at once instead of replaying a glide on an already-full bar.
    h.fullAt = h.fullAt or now
    h.holdUntil, h.glideAt, h.glideFrom, h.catchAt, h.lag = nil, nil, nil, nil, nil
  end
  if not self._lastMeleeP or math.abs(p01 - self._lastMeleeP) > 0.002 then
    melee.fill:SetWidth(math.max(0.01, Nock.UI.DeviceRound(p01 * (self._innerW or 0), self._pixelScale)))
    self._lastMeleeP = p01
  end
  if split then
    -- The off hand's own swing, same glide-shut helper as the main hand.
    local op = 1
    local oh = self._offFill
    if not oh then oh = {}; self._offFill = oh end
    if m.offStart > 0 and m.offRemaining > 0 and m.offDuration > 0 then
      op = Nock.UI.SwingFillProgress(oh, m.offStart, m.offRemaining, m.offDuration,
                                     now, HOLD_SEC, EASE_SEC, CATCH_SEC)
    else
      oh.fullAt = oh.fullAt or now
      oh.holdUntil, oh.glideAt, oh.glideFrom, oh.catchAt, oh.lag = nil, nil, nil, nil, nil
    end
    if not self._lastOffP or math.abs(op - self._lastOffP) > 0.002 then
      melee.offFill:SetWidth(math.max(0.01, Nock.UI.DeviceRound(op * (self._innerW or 0), self._pixelScale)))
      self._lastOffP = op
    end
  end

  -- Takeover off: the stage outranks READY as the small text, in the stage
  -- colour (a txt diff is also a colour diff — one cache covers both).
  -- Forever: no weaving yet (the dead zone is too wide to weave through, and
  -- no paper exists), so READY says nothing useful; the bar alone stays.
  local readyWord = (Nock.Flavor and Nock.Flavor.forever) and "" or "READY"
  local txt = look and look.text or (ready and readyWord or "")
  if txt ~= self._lastMeleeText then
    melee.text:SetText(txt)
    if look then
      melee.text:SetTextColor(look.fill[1], look.fill[2], look.fill[3])
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
    range.fill:SetWidth(math.max(0.01, Nock.UI.DeviceRound(ratio * (self._innerW or 0), self._pixelScale)))
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

-- Position strip: the probes' reading, diffed on the look key so the two
-- segments repaint only when a reading changes.
function ReactCluster:RefreshStrip(state)
  local look = Nock.UI.ReactRangeStripLook(state.target)
  local key = look.melee .. "|" .. look.ranged
  if key == self._lastStripLook then return end
  self._lastStripLook = key
  local forever = Nock.Flavor and Nock.Flavor.forever
  local off = skinColor("reactStripColorOff", REACT.STRIP_OFF)
  local dead = skinColor("reactStripColorDead", REACT.STRIP_DEAD)
  local m = look.melee == "melee" and skinColor("reactStripColorMelee", REACT.RANGE_MELEE)
         or look.melee == "dead" and dead or off
  -- Forever's lit ranged block is the gold "can shoot" (design pick A2);
  -- TBC keeps the teal it shipped with.
  local r = look.ranged == "ranged" and skinColor("reactStripColorRanged", forever and REACT.RANGE_SWEET or REACT.RANGE_CLOSE)
         or look.ranged == "dead" and dead or off
  self.strip.melee.fill:SetVertexColor(m[1], m[2], m[3], m[4] or 1)
  self.strip.ranged.fill:SetVertexColor(r[1], r[2], r[3], r[4] or 1)
  -- Fixed words, dimmed on an off block (A2).
  local tl = REACT.TEXT
  local dim = 0.45
  local mOn, rOn = look.melee ~= "off", look.ranged ~= "off"
  self.strip.melee.label:SetTextColor(tl[1], tl[2], tl[3], mOn and 1 or dim)
  self.strip.ranged.label:SetTextColor(tl[1], tl[2], tl[3], rOn and 1 or dim)
end

-- A linear 0..1 -> 0..100 curve the client evaluates for the percent text on
-- Forever (built once; nil where the curve API is absent, which falls the
-- caller back to the raw fraction).
-- Forever Range Finder: lay the ladder out when the finder's segment list
-- (or the geometry) changed, then light the target's segment. Diffed inside
-- Nock.UI.RangeLadder.Paint.
function ReactCluster:RefreshLadder(state)
  local t = state.target
  local layout = t.ladderLayout
  if not layout then
    self._ladderDefault = self._ladderDefault or Nock.RangeLadder.Layout()
    layout = self._ladderDefault
  end
  local rev = t.ladderRev or 0
  if self._ladderRev ~= rev or self._ladderLayout ~= layout then
    local g = self._ladderGeo
    if not g then return end
    Nock.UI.RangeLadder.Layout(self.ladder, layout, g.w, g.hBar, g.labels, g.dev, g.e)
    self._ladderRev, self._ladderLayout = rev, layout
  end
  Nock.UI.RangeLadder.Paint(self.ladder, t.ladderKey, t.ladderShoot)
end

function ReactCluster:PercentCurve()
  if self._pctCurve ~= nil then return self._pctCurve or nil end
  local CU, E = _G.C_CurveUtil, _G.Enum and _G.Enum.LuaCurveType
  if CU and CU.CreateCurve then
    local c = CU.CreateCurve()
    if c and c.AddPoint then
      c:AddPoint(0, 0)
      c:AddPoint(1, 100)
      if c.SetType and E and E.Linear then c:SetType(E.Linear) end
      self._pctCurve = c
      return c
    end
  end
  self._pctCurve = false
  return nil
end

function ReactCluster:RefreshMana(state)
  local mana = self.mana
  local pl = state.player
  if Nock.Flavor and Nock.Flavor.forever then
    -- Raw values may be secret: they go into sinks only. The fill texture is
    -- replaced by the sink bar, and the text is formatted by the client.
    -- The text is re-set every refresh on purpose: a FontString that has
    -- seen a secret reads back secret, so the integer diff cannot be used;
    -- SetFormattedText with a number is cheap and allocates nothing.
    local sink = mana.sink
    if mana.fill:IsShown() then mana.fill:Hide() end
    if not sink:IsShown() then sink:Show() end
    local maxRaw, curRaw = pl and pl.manaMaxRaw, pl and pl.manaCurRaw
    if maxRaw ~= nil and curRaw ~= nil then
      sink:SetMinMaxValues(0, maxRaw)
      sink:SetValue(curRaw)
      local mode = profile().reactManaText or "percent"
      if mode == "none" then
        mana.text:SetText("")
      elseif mode == "value" then
        mana.text:SetFormattedText("%d", curRaw)
      elseif mode == "both" then
        mana.text:SetFormattedText("%d / %d", curRaw, maxRaw)
      else
        -- UnitPowerPercent answers a 0..1 fraction; a secret cannot be
        -- multiplied by Nock, so the client evaluates a 0..100 curve instead.
        local pctRaw = UnitPowerPercent and UnitPowerPercent("player", 0, false, self:PercentCurve())
        if pctRaw ~= nil then mana.text:SetFormattedText("%d%%", pctRaw) else mana.text:SetText("") end
      end
    end
    -- Tick spark (reactManaTick): the engine's timed bar, driven by
    -- Forever/ManaTick.lua from power-event timing.
    local mt = pl and pl.manaTick
    local spark = mana.spark
    local p = profile()
    if p.reactManaTick == true and mt and mt.active then
      local dir = pl.inCombat and p.reactManaTickDirCombat or p.reactManaTickDirOoc
      local x = (self._edge or 1) + Nock.ManaTickEngine.SparkX(mt.progress, dir, self._innerW or 0)
      if self._lastManaSparkX ~= x then
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", mana, "LEFT", x, 0)
        self._lastManaSparkX = x
      end
      if not spark:IsShown() then spark:Show() end
    elseif spark:IsShown() then
      spark:Hide()
    end
    return
  end
  local pct = (pl and pl.manaPct) or 100
  local ratio = pct / 100
  if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
  if not self._lastManaRatio or math.abs(self._lastManaRatio - ratio) > 0.005 then
    mana.fill:SetWidth(math.max(0.01, Nock.UI.DeviceRound(ratio * (self._innerW or 0), self._pixelScale)))
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
  -- Tick spark (reactManaTick): only while opted in and the tick is live.
  local mt = pl and pl.manaTick
  local spark = mana.spark
  local p = profile()
  if p.reactManaTick == true and mt and mt.active then
    local dir = pl.inCombat and p.reactManaTickDirCombat or p.reactManaTickDirOoc
    local x = (self._edge or 1) + Nock.ManaTickEngine.SparkX(mt.progress, dir, self._innerW or 0)
    if self._lastManaSparkX ~= x then
      spark:ClearAllPoints()
      spark:SetPoint("CENTER", mana, "LEFT", x, 0)
      self._lastManaSparkX = x
    end
    if not spark:IsShown() then spark:Show() end
  elseif spark:IsShown() then
    spark:Hide()
    self._lastManaSparkX = nil
  end
end

function ReactCluster:Refresh(state)
  if not self.frame:IsShown() then return end
  if self.auto:IsShown()  then self:RefreshAuto(state)  end
  if self.melee:IsShown() then self:RefreshMelee(state) end
  if self.range:IsShown() then self:RefreshRange(state) end
  if self.strip:IsShown() then self:RefreshStrip(state) end
  if self.ladder and self.ladder:IsShown() then self:RefreshLadder(state) end
  if self.mana:IsShown()  then self:RefreshMana(state)  end
end
