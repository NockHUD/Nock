-- UI/Frame_ShotBars.lua
-- Fluffy-style scrolling shot-timing view. Two stacked rows sharing one time
-- axis (time flows right→left; LEFT edge = "now / fire"):
--   • RANGED row (top): orange Steady → blue Multi / purple Arcane in the
--     clip zone → red Auto Shot wind-up. Tiled, never overlapping.
--   • MELEE row (bottom): green weave window — when you can step in for a
--     Raptor / auto-attack and still be back before the shot.
-- White Auto Shot sparks span the full height (both rows).
--
-- Pure renderer: reads state.shotpredict (written by ShotPredictor earlier in
-- the same tick). Pooled textures, no per-tick allocation, no per-frame
-- OnUpdate (driven by the central tick :Refresh).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ShotBars = Nock:NewModule("ShotBars", "AceEvent-3.0")
local C = Nock.Constants

local SOLID = "Interface\\Buttons\\WHITE8X8"
local MAX_SPARKS = 16
local MAX_WIN    = 16
local MIN_LANE   = 2   -- a lane never collapses below this; the ranged lane wins ties

-- Render order within a row (later = drawn on top). Each entry maps to a
-- state.shotpredict.windows key, a colour, and which row it lives in.
local RANGED = { "steady", "queue", "multi", "arcane", "danger" }
local MELEE  = { "weaveauto", "raptor", "weaveclip" }
local ALL    = { "steady", "queue", "multi", "arcane", "danger", "weaveauto", "raptor", "weaveclip" }
local COLOR_KEY = {
  steady    = "shotBarsColorSteady",
  queue     = "shotBarsColorQueue",      -- dim orange: castable, but the press queues
  multi     = "shotBarsColorMulti",
  arcane    = "shotBarsColorArcane",
  danger    = "shotBarsColorDanger",
  raptor    = "shotBarsColorRaptor",     -- melee-lane: Raptor-ready (green)
  weaveauto = "shotBarsColorWeaveAuto",  -- melee-lane: auto-attack-only weave, Raptor on CD (white)
  weaveclip = "shotBarsColorDanger",     -- melee-lane no-weave fill (red, same as danger)
}

-- Keys that live in the bottom (melee) row — sized to _meleeH.
local MELEE_KEY = { raptor = true, weaveauto = true, weaveclip = true }

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function color(key, fallback)
  local c = profile(key, nil)
  if type(c) == "table" then return c[1], c[2], c[3], c[4] or 1 end
  return unpack(fallback)
end

function ShotBars:OnInitialize()
  local parent = Nock.parentFrame
  local width  = C.DIM.HUD_WIDTH - 2 * C.DIM.OUTER_PAD
  local height = profile("shotBarsHeight", C.DIM.SHOT_BARS_H)

  local f = CreateFrame("Frame", "NockShotBars", parent, "BackdropTemplate")
  f:SetSize(width, height)
  Nock.UI.ApplyBackdrop(f)
  Nock.UI.RegisterBarBackdrop(f, "shotBarsTrack")
  self.frame = f

  self._x0 = 1
  self._w  = width  - 2
  self._h  = height - 2

  -- Window pools, one per key.
  self.winTex = {}
  for _, k in ipairs(ALL) do
    local pool = {}
    for i = 1, MAX_WIN do
      local t = f:CreateTexture(nil, "ARTWORK")
      t:SetTexture(SOLID)
      t:Hide()
      pool[i] = t
    end
    self.winTex[k] = pool
  end

  -- Auto Shot sparks (OVERLAY, full height, on top).
  self.sparkTex = {}
  for i = 1, MAX_SPARKS do
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetTexture(SOLID)
    t:Hide()
    self.sparkTex[i] = t
  end

  -- Thin separator between the two rows.
  local sep = f:CreateTexture(nil, "BORDER")
  sep:SetTexture(SOLID)
  sep:SetVertexColor(0, 0, 0, 0.6)
  self.sep = sep

  -- V3 simplified-mode extras (created up front, painted only while the
  -- shotBarsSimplified flag is on):
  --   shadeEdge — 1px line marking where the GCD/cast lockout ends (GCD bar
  --               color). The ranged windows themselves are CLIPPED at this
  --               point (Fluffy-style "bars drop during the cast"): nothing is
  --               drawn where you can't press, so windows touching the fire
  --               edge means the GCD is free.
  --   clipTex   — hard clip-breakpoint ticks (last moment a Steady can start).
  -- (The melee lane stays a real, unclipped timeline — Raptor isn't GCD-bound
  -- — just squeezed to 4px, so upcoming weave windows remain visible in the
  -- prediction range instead of blinking out while the swing recharges.)
  local shadeEdge = f:CreateTexture(nil, "OVERLAY")
  shadeEdge:SetTexture(SOLID)
  shadeEdge:Hide()
  self.shadeEdge = shadeEdge

  self.clipTex = {}
  for i = 1, 8 do
    local t = f:CreateTexture(nil, "ARTWORK", nil, 2)
    t:SetTexture(SOLID)
    t:SetVertexColor(1.00, 0.23, 0.19, 1)
    t:Hide()
    self.clipTex[i] = t
  end


  -- Rotation profile label — subtle, far-right (least busy) edge.
  local label = f:CreateFontString(nil, "OVERLAY")
  label:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  label:SetPoint("RIGHT", f, "RIGHT", -3, 0)
  label:SetTextColor(1, 1, 1, 0.55)
  label:SetText("")
  self.label = label
  self._lastLabel = nil
  Nock.UI.RegisterFontString(label, "SIZE_OVERLAY", "OUTLINE")

  self:Relayout()
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "OnVisualsChanged")

  -- HUD:ApplyRowVisibility decides show/hide by rotationMode.
  f:Hide()
end

-- Recompute lane geometry + colours on settings change.
function ShotBars:Relayout()
  local width  = C.DIM.HUD_WIDTH - 2 * C.DIM.OUTER_PAD
  local height = profile("shotBarsHeight", C.DIM.SHOT_BARS_H)
  self.frame:SetSize(width, height)
  self._w, self._h = width - 2, height - 2

  -- Direction: false = right→left (fire edge LEFT, default); true = left→right
  -- (fire edge RIGHT). Only the final pixel placement mirrors — see DrawWindowKey
  -- and the spark loop. The profile label rides the QUIET (non-fire) edge, so it
  -- sits right when flowing right→left and left when reversed.
  self._reverse = profile("shotBarsReverse", false) and true or false
  self.label:ClearAllPoints()
  if self._reverse then
    self.label:SetPoint("LEFT", self.frame, "LEFT", 3, 0)
  else
    self.label:SetPoint("RIGHT", self.frame, "RIGHT", -3, 0)
  end

  self._simplified = profile("shotBarsSimplified", false) and true or false
  local showMelee = profile("shotBarsShowRaptor", true)
  if self._simplified then
    -- V3: tall ranged lane; the melee lane stays a REAL timeline (upcoming weave
    -- windows remain visible in the prediction range) but squeezed to a thin edge
    -- strip. Its height is user-set and comes OUT of the ranged lane, so the frame
    -- height — and the HUD grid row below it — never moves.
    local meleeH, sepH = 0, 0
    if showMelee then
      meleeH = math.floor(profile("shotBarsMeleeHeight", C.DIM.SHOT_BARS_MELEE_H))
      sepH   = 1
      -- The ranged lane is the one that must survive: cap the strip at whatever is
      -- left after MIN_LANE px of ranged plus the separator. A short bar therefore
      -- shrinks the strip instead of pushing the melee row out of the frame.
      local maxMelee = self._h - sepH - MIN_LANE
      if meleeH > maxMelee then meleeH = maxMelee end
      if meleeH < 1 then meleeH, sepH = 0, 0 end
    end
    self._rangedH = math.max(MIN_LANE, self._h - meleeH - sepH)
    self._meleeH  = meleeH
    self._rangedY = 1
    self._meleeY  = 1 + self._rangedH + sepH
    if meleeH > 0 then
      self.sep:ClearAllPoints()
      self.sep:SetPoint("TOPLEFT",  self.frame, "TOPLEFT",  self._x0, -(1 + self._rangedH))
      self.sep:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -self._x0, -(1 + self._rangedH))
      self.sep:SetHeight(sepH)
      self.sep:Show()
    else
      self.sep:Hide()
    end
    self.shadeEdge:SetSize(1, self._rangedH)
    local er, eg, eb = color("gcdBarColor", { 0.65, 0.45, 1.00, 1.00 })
    self.shadeEdge:SetVertexColor(er, eg, eb, 1)
    for i = 1, #self.clipTex do self.clipTex[i]:SetSize(2, self._rangedH) end
  elseif showMelee then
    -- Ranged ~62%, 1px gap, melee the rest.
    self._rangedH  = math.max(MIN_LANE, math.floor((self._h - 1) * 0.62))
    self._meleeH   = math.max(MIN_LANE, self._h - 1 - self._rangedH)
    self._rangedY  = 1
    self._meleeY   = 1 + self._rangedH + 1
    self.sep:ClearAllPoints()
    self.sep:SetPoint("TOPLEFT",  self.frame, "TOPLEFT",  self._x0, -(1 + self._rangedH))
    self.sep:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -self._x0, -(1 + self._rangedH))
    self.sep:SetHeight(1)
    self.sep:Show()
  else
    self._rangedH = self._h
    self._meleeH  = 0
    self._rangedY = 1
    self._meleeY  = 1
    self.sep:Hide()
  end

  if not self._simplified then
    self.shadeEdge:Hide()
    for i = 1, #self.clipTex do self.clipTex[i]:Hide() end
  end

  for _, k in ipairs(ALL) do
    local r, g, b, a = color(COLOR_KEY[k], { 1, 1, 1, 0.85 })
    local h = MELEE_KEY[k] and self._meleeH or self._rangedH
    for _, t in ipairs(self.winTex[k]) do
      t:SetVertexColor(r, g, b, a)
      if h > 0 then t:SetHeight(h) end
    end
  end
  -- The queue lane is the one key whose colour is per-span rather than per-pool
  -- (see DrawWindowKey): dim while it's a projection, green while it's live.
  -- Resolved here so the profile lookup doesn't run once per span per tick.
  self._queueDim  = { color("shotBarsColorQueue",     { 0.988, 0.596, 0.012, 0.38 }) }
  self._queueLive = { color("shotBarsColorQueueLive", { 0.20,  0.90,  0.35,  0.90 }) }

  local sr, sg, sb, sa = color("shotBarsColorSpark", { 1, 1, 1, 1 })
  for _, t in ipairs(self.sparkTex) do
    t:SetVertexColor(sr, sg, sb, sa)
    t:SetSize(2, self._h)
  end
end

function ShotBars:OnVisualsChanged()
  self:Relayout()
end

local function hidePool(pool, from)
  for i = from, #pool do
    if pool[i]:IsShown() then pool[i]:Hide() end
  end
end

-- Hoisted (no per-tick closure allocation — Refresh runs at tick rate).
-- minX (px, optional): windows are clipped so nothing draws left of it —
-- V3 hides the ranged lane under the GCD/cast lockout entirely.
function ShotBars:DrawWindowKey(state, k, yTop, h, now, scale, minX)
  local f = self.frame
  local Wpx = self._w
  local x0  = self._x0
  local pool = self.winTex[k]
  local list = state.shotpredict.windows[k]
  local n = (list and list.n) or 0
  local drawn = 0
  for i = 1, n do
    if drawn >= MAX_WIN then break end
    local span = list[i]
    local x1 = (span.s - now) * scale
    local x2 = (span.e - now) * scale
    if x1 < 0 then x1 = 0 end
    if minX and x1 < minX then x1 = minX end
    if x2 > Wpx then x2 = Wpx end
    -- Snap edges to the pixel grid. Tiled windows share an exact boundary time,
    -- so they round identically (no gap/overlap), and a sliver clipped at the
    -- right edge can't shimmer 1px as its sub-pixel position drifts.
    x1 = math.floor(x1 + 0.5)
    x2 = math.floor(x2 + 0.5)
    if x2 > Wpx then x2 = Wpx end
    if x2 - x1 >= 1 and h > 0 then
      drawn = drawn + 1
      local t = pool[drawn]
      -- Reversed axis mirrors the span across the frame mid-line: [x1,x2] from the
      -- left becomes [W-x2, W-x1]. Width is unchanged; only the anchor flips.
      local left = self._reverse and (Wpx - x2) or x1
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", f, "TOPLEFT", x0 + left, -yTop)
      t:SetSize(x2 - x1, h)
      -- Queue lane only: green once the window is LIVE — the wind-up has begun,
      -- so a press right now is queued for free. `span.s <= now` identifies the
      -- current cycle's window; the ones further right are still projections and
      -- stay dim. Set every draw, not just on the transition, because pool
      -- textures are reused across spans and frames.
      if k == "queue" then
        local c = (span.s <= now) and self._queueLive or self._queueDim
        if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
      end
      t:Show()
    end
  end
  hidePool(pool, drawn + 1)
end

function ShotBars:Refresh(state)
  local f = self.frame
  if not f:IsShown() then return end
  local sp = state.shotpredict
  if not sp or not sp.active then
    for _, k in ipairs(ALL) do hidePool(self.winTex[k], 1) end
    hidePool(self.sparkTex, 1)
    self:HideSimplifiedExtras()
    if self._lastLabel ~= "" then self.label:SetText(""); self._lastLabel = "" end
    return
  end

  -- The notation label rides the quiet edge in BOTH modes. The simplified bar
  -- used to drop it unconditionally — a leftover from when V3 was an off-by-
  -- default experiment — which left the "Rotation text label" toggle enabled but
  -- inert for everyone once simplified became the baseline. The toggle is the
  -- only thing that decides now; turn it off for the geometry-only look.
  local lbl = sp.profileName or ""
  if not profile("shotBarsRotationText", true) then lbl = "" end
  if lbl ~= self._lastLabel then
    self.label:SetText(lbl)
    self._lastLabel = lbl
  end
  -- Per-notation color, keyed on the RAW notation (profileName may be a user
  -- rename); nil = this label's muted default. Own numeric diff cache: the
  -- color can change while the text doesn't (options edit) and vice versa.
  local r, g, b, a
  if sp.rawNotation and Nock.Profiles and Nock.Profiles.DisplayColor then
    r, g, b, a = Nock.Profiles:DisplayColor(sp.rawNotation)
  end
  if not r then r, g, b, a = 1, 1, 1, 0.55 end
  if r ~= self._lblColR or g ~= self._lblColG
     or b ~= self._lblColB or a ~= self._lblColA then
    self.label:SetTextColor(r, g, b, a)
    self._lblColR, self._lblColG, self._lblColB, self._lblColA = r, g, b, a
  end

  -- Render against the SAME timestamp ShotPredictor anchored the spans/sparks to
  -- (set earlier in this tick), not a fresh GetTime() — that avoids the per-tick
  -- drift that made an idle projection jitter on the right edge.
  local now = sp.now or GetTime()
  local W   = self._w
  local x0  = self._x0
  local winSec = sp.windowSec
  if not winSec or winSec <= 0 then winSec = 3.4 end
  local scale = W / winSec

  -- V3: ranged windows are clipped at the GCD/cast lockout edge (Fluffy-style
  -- "bars drop while you can't press") — windows touching the fire edge means
  -- the GCD is free. Melee lane stays unclipped (Raptor isn't GCD-bound).
  local lockPx = nil
  if self._simplified then
    local lock = (state.gcd and state.gcd.remaining) or 0
    -- Real casts only — the Auto Shot wind-up lives in state.player.autoShotCast
    -- because it does not lock you out (the press queues), and clipping the
    -- windows at it blanked the bar for the last stretch of every cycle.
    local cast = state.player and state.player.casting
    if cast and cast.endTime and (cast.endTime - now) > lock then
      lock = cast.endTime - now
    end
    lockPx = math.floor(lock * scale + 0.5)
    if lockPx > W then lockPx = W end
    if lockPx <= 0 then lockPx = nil end
    self._lockPx = lockPx
  else
    self._lockPx = nil
  end

  for _, k in ipairs(RANGED) do self:DrawWindowKey(state, k, self._rangedY, self._rangedH, now, scale, lockPx) end
  for _, k in ipairs(MELEE)  do self:DrawWindowKey(state, k, self._meleeY,  self._meleeH,  now, scale) end
  if self._simplified then self:RefreshSimplifiedExtras(state, now, scale) end

  -- Auto Shot sparks, full height, on top.
  local ns = sp.nSparks or 0
  local shown = 0
  for i = 1, ns do
    if shown >= MAX_SPARKS then break end
    local x = (sp.sparks[i] - now) * scale
    if x >= 0 and x <= W then
      x = math.floor(x + 0.5)  -- pixel-snap, same reason as the windows
      shown = shown + 1
      local t = self.sparkTex[shown]
      local sx = self._reverse and (W - x) or x  -- mirror across the mid-line when reversed
      t:ClearAllPoints()
      t:SetPoint("TOP", f, "TOPLEFT", x0 + sx, -1)
      t:Show()
    end
  end
  hidePool(self.sparkTex, shown + 1)
end

----------------------------------------------------------------------------
-- V3 simplified-mode extras (GCD/cast shade, clip ticks, melee strip).
----------------------------------------------------------------------------

function ShotBars:HideSimplifiedExtras()
  if self.shadeEdge:IsShown() then self.shadeEdge:Hide() end
  for i = 1, #self.clipTex do
    if self.clipTex[i]:IsShown() then self.clipTex[i]:Hide() end
  end
end

-- Hoisted (no per-tick closure allocation — runs at tick rate).
function ShotBars:RefreshSimplifiedExtras(state, now, scale)
  local sp = state.shotpredict
  local f = self.frame
  local W = self._w
  local x0 = self._x0

  -- Lockout front marker: a 1px line where the GCD/cast ends. The windows
  -- themselves are already clipped at this point in Refresh, so the line just
  -- marks the moving front while it's live.
  local w = self._lockPx
  if w and w >= 1 then
    local ex = self._reverse and (W - w) or w
    if ex > W - 1 then ex = W - 1 end
    self.shadeEdge:ClearAllPoints()
    self.shadeEdge:SetPoint("TOPLEFT", f, "TOPLEFT", x0 + ex, -self._rangedY)
    self.shadeEdge:Show()
  elseif self.shadeEdge:IsShown() then
    self.shadeEdge:Hide()
  end

  -- Hard clip-breakpoint ticks (replaces judging the steady→filler boundary).
  -- Ticks inside the hidden lockout region are unreachable — skip them.
  local shown = 0
  local minX = self._lockPx or 0
  for i = 1, (sp.nClips or 0) do
    if shown >= #self.clipTex then break end
    local x = (sp.clips[i] - now) * scale
    if x >= minX and x <= W then
      x = math.floor(x + 0.5)
      shown = shown + 1
      local t = self.clipTex[shown]
      local sx = self._reverse and (W - x) or x
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", f, "TOPLEFT", x0 + sx, -self._rangedY)
      t:Show()
    end
  end
  for i = shown + 1, #self.clipTex do
    if self.clipTex[i]:IsShown() then self.clipTex[i]:Hide() end
  end
end
