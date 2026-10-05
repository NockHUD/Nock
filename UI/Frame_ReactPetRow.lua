-- UI/Frame_ReactPetRow.lua
-- React HUD's optional last row (Forever): three pet-happiness lamps, 25% of the HUD wide, welded under the cooldown grid.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ReactPetRow = Nock:NewModule("ReactPetRow", "AceEvent-3.0")
local C = Nock.Constants

-- React palette (Frame_ReactCluster.lua REACT): Raptor-ready green, sweet-spot
-- amber, melee red; unlit = the position strip's off grey; food = pale gold.
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local COLOR = {
  h = { 0.15, 0.68, 0.38 },
  c = { 0.85, 0.66, 0.00 },
  u = { 0.68, 0.18, 0.20 },
}
local OFF   = { 0.16, 0.16, 0.16 }
local FOOD  = { 1.00, 0.89, 0.48 }
local LABEL_GAP, LABEL_H = 2, 8
-- Profile sliders (React HUD tab): lamp height in px, strip width in % of
-- the HUD. The strip needs 7 px to hold three 1 px lamps, border and seams.
local STRIP_H_DEFAULT, STRIP_H_MIN, STRIP_H_MAX = 4, 3, 16
local WIDTH_DEFAULT, WIDTH_MIN, WIDTH_MAX = 25, 10, 100
local STRIP_W_MIN = 7
local FONT_SIZE = 8
local PULSE_HZ = 1.0
local KEYS = { "u", "c", "h" }

local function profile() return (Nock.db and Nock.db.profile) or {} end

-- Pure: should the row take its place in the HUD stack?
function ReactPetRow.Want(p, react, lampShow, preview)
  if not react or p.reactShowPetRow ~= true then return false end
  return lampShow == true or preview == true
end

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

-- The strip's width as a fraction of the HUD (reactPetRowW, percent).
function ReactPetRow.WidthFrac(p)
  return clamp(tonumber(p.reactPetRowW) or WIDTH_DEFAULT, WIDTH_MIN, WIDTH_MAX) / 100
end

local function stripH(p)
  return math.floor(clamp(tonumber(p.reactPetRowH) or STRIP_H_DEFAULT, STRIP_H_MIN, STRIP_H_MAX))
end

-- Whole-pixel strip geometry for a HUD `w` wide: the strip is `frac` of it and
-- keeps w's parity so it centres on a pixel; three integer lamps behind a 1px
-- border and 1px seams, the odd pixels going to the middle lamp. Layout-time
-- only (returns fresh tables).
function ReactPetRow.Geometry(w, frac)
  frac = frac or WIDTH_DEFAULT / 100
  local sw = math.floor(w * frac + 0.5)
  if (w - sw) % 2 ~= 0 then sw = (sw > w * frac) and sw - 1 or sw + 1 end
  if sw > w then sw = w end
  if sw < STRIP_W_MIN then sw = STRIP_W_MIN + (w - STRIP_W_MIN) % 2 end
  local inner = sw - 4
  local base = math.floor(inner / 3)
  local lw = { base, inner - 2 * base, base }
  local lx = { 1, 2 + lw[1], 3 + lw[1] + lw[2] }
  return sw, lw, lx
end

-- Device pixels per unit for this row (1 when unknown). The strip geometry
-- above is whole PIXELS; it shares a 1 px seam with the grid above it, so the
-- row's height must be whole pixels too (Nock.UI.SeamPx).
local function pixelScale(f)
  local dev = Nock.UI.PixelScale(f)
  return (dev and dev > 0) and dev or 1
end

function ReactPetRow:ContentHeight()
  local ds = pixelScale(self.frame)
  return (Nock.UI.SeamPx(stripH(profile()), ds) + Nock.UI.SeamPx(LABEL_GAP + LABEL_H, ds)) / ds
end
function ReactPetRow:Wanted() return self._want == true end

function ReactPetRow:OnInitialize()
  local f = CreateFrame("Frame", "NockReactPetRow", Nock.parentFrame)
  self.frame = f
  local strip = CreateFrame("Frame", nil, f)
  self.strip = strip
  -- A black plate under the lamps: the 1px border and the seams between them.
  local plate = strip:CreateTexture(nil, "BACKGROUND")
  plate:SetTexture(WHITE8X8)
  plate:SetVertexColor(0, 0, 0, 1)
  plate:SetAllPoints(strip)
  self.lamps = {}
  for i, k in ipairs(KEYS) do
    local t = strip:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE8X8)
    local fill = strip:CreateTexture(nil, "OVERLAY")
    fill:SetTexture(WHITE8X8)
    fill:SetVertexColor(FOOD[1], FOOD[2], FOOD[3], 1)
    fill:Hide()
    self.lamps[k] = { tex = t, fill = fill, index = i }
  end
  self.label = f:CreateFontString(nil, "OVERLAY")
  self._want = false
  self:ApplyLayout()
  f:Hide()  -- HUD:ApplyRowVisibility shows it through :Wanted()
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyLayout")
  self:RegisterMessage("NOCK_PIXEL_GRID_CHANGED", "ApplyLayout")   -- device-pixel geometry
end

function ReactPetRow:ApplyLayout()
  local p = profile()
  -- Geometry in device pixels, converted to units at Set* time.
  local ds = pixelScale(self.frame)
  local wPx = Nock.UI.EvenPx(tonumber(p.reactWidth) or 220, ds)
  local sw, lw, lx = ReactPetRow.Geometry(wPx, ReactPetRow.WidthFrac(p))
  local h = Nock.UI.SeamPx(stripH(p), ds)
  self.frame:SetSize(wPx / ds, self:ContentHeight())
  self.strip:ClearAllPoints()
  self.strip:SetPoint("TOP", self.frame, "TOP", 0, 0)
  self.strip:SetSize(sw / ds, h / ds)
  for _, k in ipairs(KEYS) do
    local l = self.lamps[k]
    l.wPx, l.ds = lw[l.index], ds
    l.w = l.wPx / ds
    l.tex:ClearAllPoints()
    l.tex:SetPoint("TOPLEFT", self.strip, "TOPLEFT", lx[l.index] / ds, -1 / ds)
    l.tex:SetSize(l.w, (h - 2) / ds)
    l.fill:ClearAllPoints()
    l.fill:SetPoint("TOPLEFT", l.tex, "TOPLEFT", 0, 0)
    l.fill:SetHeight((h - 2) / ds)
  end
  local font = Nock.UI.GetReactFont() or C.FONT.PATH
  Nock.UI.SafeSetFont(self.label, font, math.max(6, FONT_SIZE + (Nock.UI.GetReactFontDelta() or 0)), Nock.UI.GetReactFontStyle())
  Nock.UI.ApplyReactTextShadow(self.label)
  self.label:ClearAllPoints()
  self.label:SetPoint("TOP", self.strip, "BOTTOM", 0, -LABEL_GAP)
  self._lastLit, self._lastLabel, self._lastLeft, self._lastFill = nil, nil, nil, nil
end

-- Preview while the HUD is editable and no pet: the Content lamp + label.
local PREVIEW = { show = true, lit = "c", pulse = false, fill = nil, label = "FEED NOW", feedLeft = nil }

function ReactPetRow:Refresh(state)
  local p = profile()
  local lamp = Nock.PetLamp(state.pet, state.ledgerTimers and state.ledgerTimers.Feed, GetTime())
  local preview = (not lamp.show) and Nock.EditPreview("hud") or false
  local want = ReactPetRow.Want(p, Nock.HudIsReact(), lamp.show, preview)
  if want ~= self._want then
    self._want = want
    self:SendMessage("NOCK_HUD_RELAYOUT")
  end
  if not want then return end
  local o = lamp.show and lamp or PREVIEW
  if o.lit ~= self._lastLit then
    self._lastLit = o.lit
    for _, k in ipairs(KEYS) do
      local c = (k == o.lit) and COLOR[k] or OFF
      self.lamps[k].tex:SetVertexColor(c[1], c[2], c[3], 1)
      self.lamps[k].tex:SetAlpha(1)
      self.lamps[k].fill:Hide()
    end
    self._lastFill = nil
  end
  local lit = self.lamps[o.lit]
  if o.pulse then
    lit.tex:SetAlpha(0.675 + 0.325 * math.cos(GetTime() * 2 * math.pi * PULSE_HZ))
  else
    lit.tex:SetAlpha(1)
  end
  if o.fill ~= self._lastFill then
    self._lastFill = o.fill
    if o.fill and o.fill > 0 then
      lit.fill:SetWidth(math.max(1, math.floor(lit.wPx * o.fill + 0.5)) / lit.ds)
      lit.fill:Show()
    else
      lit.fill:Hide()
    end
  end
  if o.label ~= self._lastLabel or o.feedLeft ~= self._lastLeft then
    self._lastLabel, self._lastLeft = o.label, o.feedLeft
    if o.label == "FEEDING" then
      self.label:SetText(("FEEDING %ds"):format(o.feedLeft or 0))
      self.label:SetTextColor(FOOD[1], FOOD[2], FOOD[3], 1)
    elseif o.label then
      local c = COLOR[o.lit]
      self.label:SetText(o.label)
      self.label:SetTextColor(c[1], c[2], c[3], 1)
    else
      self.label:SetText("")
    end
  end
end
