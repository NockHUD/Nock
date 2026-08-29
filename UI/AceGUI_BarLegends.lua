-- UI/AceGUI_BarLegends.lua
-- AceGUI widgets: annotated miniatures for the options panel, so each colour
-- scheme explains itself instead of needing a manual. Registers
-- "NockShotBarsLegend" (the scrolling Fluffy timeline) and "NockReactBarLegend"
-- (the React converge bar).
--
-- Used from Config/Options.lua as
--   type = "description", dialogControl = "NockShotBarsLegend"
-- AceConfigDialog builds descriptions with CreateControl(v.dialogControl, "Label")
-- (AceConfigDialog-3.0.lua:1383), so a description entry can render any
-- registered widget; it then calls SetText/SetFontObject, which are stubbed
-- below, and SetImage* only when the entry carries an `image` (neither does).
-- Omitting `width` gets control.width = "fill" (same file, line 1420).
--
-- Both diagrams use one fixed, representative cycle rather than live state — an
-- unbuffed 3.0 bow at 20% haste + a 15% quiver: eWS 2.174, Steady 1.087, wind-up
-- 0.362. They are diagrams, not a second HUD. Colours ARE read live from the
-- profile wherever the bar itself is configurable, so a picture never contradicts
-- the colour pickers sitting next to it.

local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local SOLID = "Interface\\Buttons\\WHITE8X8"

local TICK_H    = 5     -- the little pointer dropping from a breakpoint
local CAPTION_H = 11
local ROW_H     = 13
local PAD       = 4

----------------------------------------------------------------------------
-- Shared helpers.
----------------------------------------------------------------------------

-- `key` may be nil for colours that are fixed skin constants rather than
-- profile settings (the React tick colours are locals in Frame_ReactCluster).
local function profileColor(key, fallback)
  local p = key and Nock and Nock.db and Nock.db.profile
  local c = p and p[key]
  if type(c) == "table" and c[1] then return c[1], c[2], c[3], c[4] or 1 end
  return fallback[1], fallback[2], fallback[3], fallback[4] or 1
end

local function newTexture(parent, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(SOLID)
  return t
end

local function newFont(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetJustifyV("TOP")
  return fs
end

-- Swatch + wrapped description per entry, stacked from `y`. Heights are MEASURED
-- rather than assumed: the texts wrap at narrow panel widths, and a fixed row
-- pitch would stack them on top of each other. Returns the y below the last row.
local function layoutLegend(self, legend, y)
  for i, def in ipairs(legend) do
    local row = self.rows[i]
    row.swatch:ClearAllPoints()
    row.swatch:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, y - 2)
    row.swatch:SetSize(10, 8)
    row.swatch:SetVertexColor(profileColor(def.key, def.fallback))
    row.swatch:Show()
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 15, y)
    row.text:SetPoint("RIGHT", self.frame, "RIGHT", 0, 0)
    row.text:SetText(def.text)
    row.text:Show()
    y = y - math.max(ROW_H, (row.text:GetStringHeight() or 0) + 3)
  end
  -- The React legend is variable-length (the GCD row appears only when that
  -- feature is on), so anything the pool has beyond this list must be hidden —
  -- otherwise a switched-off row keeps its last text parked under the panel.
  for i = #legend + 1, #self.rows do
    self.rows[i].swatch:Hide()
    self.rows[i].text:Hide()
  end
  return y
end

-- Grow the widget to whatever the drawing needed. SetHeight fires OnSizeChanged,
-- which AceGUI routes straight back into OnWidthSet (RegisterAsWidget installs
-- FrameResize) — i.e. back into the redraw. The flag makes that a no-op instead
-- of a second full pass.
local function fitHeight(self, h)
  if math.abs((self.frame:GetHeight() or 0) - h) <= 0.5 then return end
  self._sizing = true
  self.frame:SetHeight(h)
  self:SetHeight(h)
  self._sizing = nil
end

local function buildRows(frame, n)
  local rows = {}
  for i = 1, n do
    rows[i] = { swatch = newTexture(frame), text = newFont(frame) }
  end
  return rows
end

-- AceConfigDialog calls SetText/SetFontObject on every description entry. These
-- widgets draw their own content, so those are accepted and ignored rather than
-- erroring.
local function makeMethods(redraw)
  return {
    OnAcquire     = function(self) self:SetWidth(400); self.frame:Show(); redraw(self) end,
    OnRelease     = function(self) self.frame:ClearAllPoints(); self.frame:Hide() end,
    OnWidthSet    = function(self) redraw(self) end,
    SetText       = function() end,
    SetFontObject = function() end,
    SetImage      = function() end,
    SetImageSize  = function() end,
    SetDisabled   = function() end,
  }
end

local function register(typeName, version, build, redraw)
  local methods = makeMethods(redraw)
  AceGUI:RegisterWidgetType(typeName, function()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    local widget = { frame = frame, type = typeName }
    build(widget, frame)
    for m, f in pairs(methods) do widget[m] = f end
    return AceGUI:RegisterAsWidget(widget)
  end, version)
end

----------------------------------------------------------------------------
-- 1. Fluffy shot bars — a scrolling timeline, time flowing toward the shot.
----------------------------------------------------------------------------

local BAR_H = 18
-- Fractions of one cycle: Steady-safe, then the clip band, then the remainder is
-- the queue window. From the representative cycle in the header.
local F_SAFE, F_CLIP = 0.33, 0.50

local SHOT_LEGEND = {
  { key = "shotBarsColorSteady", fallback = { 0.988, 0.596, 0.012, 0.85 },
    text = "Cast now — it finishes before the wind-up starts." },
  { key = "shotBarsColorDanger", fallback = { 0.851, 0.118, 0.118, 0.50 },
    text = "Don't — a cast started here is still going when the shot wants to fire, and delays it." },
  { key = "shotBarsColorQueue", fallback = { 0.988, 0.596, 0.012, 0.38 },
    text = "Queue window, still coming up." },
  { key = "shotBarsColorQueueLive", fallback = { 0.20, 0.90, 0.35, 0.90 },
    text = "Green = press now. The game holds it and fires it the moment the arrow leaves, for free." },
  { key = "shotBarsColorSpark", fallback = { 1, 1, 1, 1 },
    text = "The shot itself — a landmark, not a warning." },
}

local function redrawShotBars(self)
  if self._sizing then return end
  local w = self.frame:GetWidth() or 0
  if w <= 0 then return end

  local safeW  = math.floor(w * F_SAFE)
  local clipW  = math.floor(w * F_CLIP)
  local queueW = w - safeW - clipW - 2   -- 2px reserved for the spark

  local segs = self.segs
  local defs = {
    { segs.safe,  0,             safeW,  SHOT_LEGEND[1] },
    { segs.clip,  safeW,         clipW,  SHOT_LEGEND[2] },
    { segs.queue, safeW + clipW, queueW, SHOT_LEGEND[4] },  -- drawn LIVE (green)
  }
  for _, d in ipairs(defs) do
    local tex, x, sw, def = d[1], d[2], d[3], d[4]
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, 0)
    tex:SetSize(math.max(1, sw), BAR_H)
    tex:SetVertexColor(profileColor(def.key, def.fallback))
    tex:Show()
  end
  segs.spark:ClearAllPoints()
  segs.spark:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, 0)
  segs.spark:SetSize(2, BAR_H)
  segs.spark:SetVertexColor(profileColor("shotBarsColorSpark", { 1, 1, 1, 1 }))

  -- Breakpoint pointers. Only two boundaries plus the shot, and the captions are
  -- anchored left / centre / right off their own tick, so none can run off the
  -- panel or into each other.
  local xs = { safeW, safeW + clipW, w - 1 }
  for i = 1, 3 do
    local tick = self.marks[i].tick
    tick:ClearAllPoints()
    tick:SetPoint("TOPLEFT", self.frame, "TOPLEFT", xs[i], -BAR_H)
    tick:SetSize(1, TICK_H)
    tick:SetVertexColor(0.75, 0.75, 0.75, 0.9)
    tick:Show()
  end
  local capY = -(BAR_H + TICK_H + 1)
  self.marks[1].text:ClearAllPoints()
  self.marks[1].text:SetPoint("TOPLEFT", self.frame, "TOPLEFT", xs[1] + 2, capY)
  self.marks[2].text:ClearAllPoints()
  self.marks[2].text:SetPoint("TOP", self.frame, "TOPLEFT", xs[2], capY)
  self.marks[3].text:ClearAllPoints()
  self.marks[3].text:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, capY)

  local y = layoutLegend(self, SHOT_LEGEND, -(BAR_H + TICK_H + CAPTION_H + PAD + 2))
  fitHeight(self, -y + PAD)
end

register("NockShotBarsLegend", 1, function(widget, frame)
  widget.segs = {
    safe  = newTexture(frame),
    clip  = newTexture(frame),
    queue = newTexture(frame),
    spark = newTexture(frame, "OVERLAY"),
  }
  widget.marks = {}
  local captions = { "clip starts", "queue opens", "shot" }
  for i = 1, 3 do
    local justify = (i == 1 and "LEFT") or (i == 2 and "CENTER") or "RIGHT"
    widget.marks[i] = {
      tick = newTexture(frame, "OVERLAY"),
      text = newFont(frame, "GameFontDisableSmall", justify),
    }
    widget.marks[i].text:SetText(captions[i])
  end
  widget.rows = buildRows(frame, #SHOT_LEGEND)
end, redrawShotBars)

----------------------------------------------------------------------------
-- 2. React converge bar — two halves closing on the centre, marks mirrored.
----------------------------------------------------------------------------

local R_BAR_H = 14                 -- REACT.AUTO_H
local R_FILL  = 0.55               -- how far the halves have closed, for illustration
-- Distance of each mark from its own edge, as a fraction of the half-width. A
-- threshold T maps to (sd - T)/sd, exactly as ReactCluster:PositionAutoMarks
-- does. From the representative cycle: Steady clip 1.449s, Multi clip 0.724s,
-- wind-up 0.362s against an eWS of 2.174.
local R_STEADY, R_MULTI, R_WINDUP = 0.333, 0.667, 0.833

-- Every swatch below names a real profile key, so the legend tracks whatever
-- you set under React HUD -> Skin rather than describing a colour you no
-- longer have. The fallbacks are the reference constants in
-- UI/Frame_ReactCluster.lua, for a pre-DB read.
local REACT_LEGEND = {
  { key = "reactColorAutoFill", fallback = { 1.00, 0.84, 0.00, 1.00 },
    text = "The swing. Both halves close on the centre and meet when the arrow leaves." },
  { key = "reactColorTickSteady", fallback = { 1.00, 0.10, 0.10, 1.00 },
    text = "Red: the last moment a Steady can start and still finish in time. Past it, a Steady delays the shot." },
  { key = "reactColorTickMulti", fallback = { 1.00, 0.65, 0.10, 1.00 },
    text = "Orange: the same limit for Multi-Shot, which is a shorter cast and so survives later." },
  { key = "reactColorTickWindup", fallback = { 0.85, 0.85, 0.85, 0.80 },
    text = "Grey, nearest the centre: the wind-up begins. From here on a press is free — it is held and fires as the arrow leaves." },
}

-- Appended only while reactShowGcdDivider is on. It is deliberately NOT drawn
-- on the miniature above: every mark there is a fixed threshold at a fixed
-- fraction of the cycle, and the GCD divider is the one mark that isn't —
-- placing it among them would read as another threshold.
local REACT_GCD_ROW = {
  key = "reactColorGcdDivider", fallback = { 0.62, 0.35, 0.98, 1.00 },
  text = "Purple, moving: the global cooldown. It leaves the outer edge when you press and closes on the centre as the GCD ends — its own progress, not a point on the swing.",
}

local function redrawReact(self)
  if self._sizing then return end
  local w = self.frame:GetWidth() or 0
  if w <= 0 then return end
  local halfW = math.floor(w / 2)

  local fillW = math.max(1, math.floor(halfW * R_FILL))
  local gr, gg, gb, ga = profileColor("reactColorAutoFill", { 1.00, 0.84, 0.00, 1.00 })
  for _, side in ipairs({ "L", "R" }) do
    local t = self.fill[side]
    t:ClearAllPoints()
    t:SetPoint(side == "L" and "TOPLEFT" or "TOPRIGHT", self.frame,
               side == "L" and "TOPLEFT" or "TOPRIGHT", 0, 0)
    t:SetSize(fillW, R_BAR_H)
    t:SetVertexColor(gr, gg, gb, ga)
    t:Show()
  end

  -- Mirrored mark pairs, measured from each edge inward — the same projection
  -- the live bar uses, so the picture matches it at a glance.
  local fracs = { R_STEADY, R_MULTI, R_WINDUP }
  -- Widths track the skin too, for the same reason the colours do: this picture
  -- exists to match the live bar at a glance.
  local wKeys = { "reactTickSteadyWidth", "reactTickMultiWidth", "reactTickWindupWidth" }
  local prof  = Nock and Nock.db and Nock.db.profile
  for i = 1, 3 do
    local x = math.floor(fracs[i] * halfW)
    local def = REACT_LEGEND[i + 1]
    local tw = prof and tonumber(prof[wKeys[i]])
    if not tw or tw <= 0 then tw = 2 end
    for _, side in ipairs({ "L", "R" }) do
      local t = self.ticks[i][side]
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self.frame, side == "L" and "TOPLEFT" or "TOPRIGHT",
                 side == "L" and x or -x, 0)
      t:SetSize(tw, R_BAR_H)
      t:SetVertexColor(profileColor(def.key, def.fallback))
      t:Show()
    end
  end

  -- Captions only on the LEFT half, and only for the two outer marks: near the
  -- centre the marks sit ~30px apart, which no label fits between. The wind-up
  -- mark is described in the legend rows instead of pretending otherwise.
  local capY = -(R_BAR_H + TICK_H + 1)
  local capX = { math.floor(R_STEADY * halfW), math.floor(R_MULTI * halfW) }
  for i = 1, 2 do
    local tick = self.marks[i].tick
    tick:ClearAllPoints()
    tick:SetPoint("TOPLEFT", self.frame, "TOPLEFT", capX[i], -R_BAR_H)
    tick:SetSize(1, TICK_H)
    tick:SetVertexColor(0.75, 0.75, 0.75, 0.9)
    tick:Show()
    self.marks[i].text:ClearAllPoints()
    self.marks[i].text:SetPoint("TOPLEFT", self.frame, "TOPLEFT", capX[i] + 2, capY)
  end
  self.marks[3].tick:ClearAllPoints()
  self.marks[3].tick:SetPoint("TOPLEFT", self.frame, "TOPLEFT", halfW, -R_BAR_H)
  self.marks[3].tick:SetSize(1, TICK_H)
  self.marks[3].tick:SetVertexColor(0.75, 0.75, 0.75, 0.9)
  self.marks[3].tick:Show()
  self.marks[3].text:ClearAllPoints()
  self.marks[3].text:SetPoint("TOP", self.frame, "TOPLEFT", halfW, capY)

  local legend = REACT_LEGEND
  if Nock and Nock.db and Nock.db.profile and Nock.db.profile.reactShowGcdDivider == true then
    legend = {}
    for i = 1, #REACT_LEGEND do legend[i] = REACT_LEGEND[i] end
    legend[#legend + 1] = REACT_GCD_ROW
  end
  local y = layoutLegend(self, legend, -(R_BAR_H + TICK_H + CAPTION_H + PAD + 2))
  y = y - 2
  self.note:ClearAllPoints()
  self.note:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, y)
  self.note:SetPoint("RIGHT", self.frame, "RIGHT", 0, 0)
  y = y - math.max(ROW_H, (self.note:GetStringHeight() or 0) + 3)
  fitHeight(self, -y + PAD)
end

register("NockReactBarLegend", 1, function(widget, frame)
  widget.fill  = { L = newTexture(frame), R = newTexture(frame) }
  widget.ticks = {}
  for i = 1, 3 do
    widget.ticks[i] = { L = newTexture(frame, "OVERLAY"), R = newTexture(frame, "OVERLAY") }
  end
  widget.marks = {}
  local captions = { "Steady clip", "Multi clip", "shot" }
  for i = 1, 3 do
    widget.marks[i] = {
      tick = newTexture(frame, "OVERLAY"),
      text = newFont(frame, "GameFontDisableSmall", i == 3 and "CENTER" or "LEFT"),
    }
    widget.marks[i].text:SetText(captions[i])
  end
  widget.rows = buildRows(frame, #REACT_LEGEND + 1)  -- +1: the optional GCD row
  widget.note = newFont(frame, "GameFontDisableSmall", "LEFT")
  widget.note:SetText("Every mark is mirrored on both halves — the pair closes on the centre together, so you can read whichever side your eye is on.")
end, redrawReact)
