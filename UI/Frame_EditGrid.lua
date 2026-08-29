-- UI/Frame_EditGrid.lua
-- The edit-mode grid: a raster overlay behind every Nock frame while
-- unlocked, a ghost outline for snap-while-dragging, and the control panel
-- at the top of the screen (raster size, grid on/off, snap mode, snap-by,
-- lock). The maths lives in UI/EditMode.lua (GridLines, SnapDelta, the drag
-- hooks); this file only draws. Everything is hidden while locked.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("EditGridView", "AceEvent-3.0")
local C = Nock.Constants

local RASTER_MIN, RASTER_MAX, RASTER_STEP = 4, 64, 2
local LINE_ALPHA, CENTRE_ALPHA = 0.18, 0.45

local function profile() return Nock.db and Nock.db.profile or {} end
local function Skin() return Nock.UI.Skin end

-- ---------------------------------------------------------------------------
-- Overlay
-- ---------------------------------------------------------------------------
function View:BuildOverlay()
  if self.overlay then return end
  local f = CreateFrame("Frame", "NockEditGrid", UIParent)
  f:SetFrameStrata("BACKGROUND")
  f:SetFrameLevel(0)
  f:SetAllPoints(UIParent)
  f:EnableMouse(false)
  f:Hide()
  self.overlay = f
  self._xLines, self._yLines = {}, {}

  -- Ghost: where a dragged frame will land (snap-while-dragging).
  local g = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  g:SetFrameStrata("TOOLTIP")
  g:EnableMouse(false)
  g:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
  g:SetBackdropBorderColor(0.67, 0.83, 0.45, 0.9)   -- the hunter's green
  g:Hide()
  self.ghost = g
end

local function paintLine(tex, centre)
  local S = Skin()
  if S then
    S.Paint(tex, centre and "accent" or "ink", centre and CENTRE_ALPHA or LINE_ALPHA)
  else
    tex:SetColorTexture(1, 1, 1, centre and CENTRE_ALPHA or LINE_ALPHA)
  end
end

local function takeLine(pool, i, parent)
  local t = pool[i]
  if not t then
    t = parent:CreateTexture(nil, "BACKGROUND")
    pool[i] = t
  end
  return t
end

-- Rebuild the lines for the current screen and raster. Called on show, on a
-- raster change and on a display/UI-scale change -- never on the tick.
function View:Rebuild()
  self:BuildOverlay()
  local f = self.overlay
  local p = profile()
  local raster = tonumber(p.editGridSize) or 16
  local w, h = UIParent:GetWidth(), UIParent:GetHeight()
  local xs, ys = Nock.UI.GridLines(w, h, raster)
  local cx, cy = w / 2, h / 2
  local n = 0
  for _, x in ipairs(xs) do
    n = n + 1
    local t = takeLine(self._xLines, n, f)
    t:ClearAllPoints()
    t:SetPoint("TOP", f, "TOPLEFT", x, 0)
    t:SetPoint("BOTTOM", f, "BOTTOMLEFT", x, 0)
    t:SetWidth(1)
    paintLine(t, math.abs(x - cx) < 0.5)
    t:Show()
  end
  for i = n + 1, #self._xLines do self._xLines[i]:Hide() end
  n = 0
  for _, y in ipairs(ys) do
    n = n + 1
    local t = takeLine(self._yLines, n, f)
    t:ClearAllPoints()
    t:SetPoint("LEFT", f, "BOTTOMLEFT", 0, y)
    t:SetPoint("RIGHT", f, "BOTTOMRIGHT", 0, y)
    t:SetHeight(1)
    paintLine(t, math.abs(y - cy) < 0.5)
    t:Show()
  end
  for i = n + 1, #self._yLines do self._yLines[i]:Hide() end
  self._builtFor = raster .. "x" .. w .. "x" .. h
end

-- rect in UIParent units, or nil to hide.
function View:SetGhost(rect)
  if not self.ghost then return end
  if not rect then
    if self.ghost:IsShown() then self.ghost:Hide() end
    return
  end
  local g = self.ghost
  g:ClearAllPoints()
  g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.left, rect.bottom)
  g:SetSize(math.max(1, rect.right - rect.left), math.max(1, rect.top - rect.bottom))
  if not g:IsShown() then g:Show() end
end

-- ---------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------
local PANEL_W, PANEL_H, PAD, GAP = 560, 58, 10, 8

local function setToggleLook(btn, on)
  local S = Skin()
  if S then S.ButtonKind(btn, on and "primary" or "ghost") end
end

function View:BuildPanel()
  if self.panel then return end
  local S = Skin()
  local f = CreateFrame("Frame", "NockEditPanel", UIParent, "BackdropTemplate")
  f:SetSize(PANEL_W, PANEL_H)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    profile().editPanelPos = { point = point, relPoint = relPoint or point, x = x or 0, y = y or 0 }
  end)
  if S then S.Surface(f, "surface", "line") else Nock.UI.ApplyBackdrop(f) end
  self.panel = f

  -- Title + help line.
  local title = f:CreateFontString(nil, "OVERLAY")
  if S then S.Font(title, "display", S.SIZES.h2 or 16); S.Text(title, "ink") else title:SetFontObject(GameFontNormal) end
  title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -6)
  title:SetText("NOCK  EDIT MODE")
  local help = f:CreateFontString(nil, "OVERLAY")
  if S then S.Font(help, "ui", S.SIZES.small or 11); S.Text(help, "ink2") else help:SetFontObject(GameFontDisableSmall) end
  help:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 6)
  help:SetText("Drag a frame to move it, click it for a nudge pad. Drag this bar anywhere.")

  -- Controls row, right-aligned: [Grid −] [16] [+]  [Grid]  [Snap: …]  [By: …]  [Lock]
  local function button(label, kind, w)
    if S then return S.Button(f, label, kind or "ghost", w) end
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(w or 60, 22); b:SetText(label)
    b.text = b:GetFontString()
    return b
  end
  local lock  = button("Lock", "primary", 56)
  lock:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -8)
  lock:SetScript("OnClick", function() Nock:SetLocked(true) end)

  local by = button("By: nearest", "ghost", 104)
  by:SetPoint("RIGHT", lock, "LEFT", -GAP, 0)
  by:SetScript("OnClick", function()
    local p = profile()
    p.editSnapBy = (p.editSnapBy == "corner") and "nearest" or "corner"
    self:Apply()
  end)
  self.byBtn = by

  local snap = button("Snap: off", "ghost", 104)
  snap:SetPoint("RIGHT", by, "LEFT", -GAP, 0)
  snap:SetScript("OnClick", function()
    local p = profile()
    local m = Nock.UI.EditSnapMode(p)
    p.editGridSnap = (m == "off") and "release" or (m == "release") and "drag" or "off"
    self:Apply()
  end)
  self.snapBtn = snap

  local grid = button("Grid", "ghost", 52)
  grid:SetPoint("RIGHT", snap, "LEFT", -GAP, 0)
  grid:SetScript("OnClick", function()
    local p = profile()
    p.editGridShow = not (p.editGridShow ~= false)
    self:Apply()
  end)
  self.gridBtn = grid

  local plus = button("+", "ghost", 24)
  plus:SetPoint("RIGHT", grid, "LEFT", -GAP - 4, 0)
  local value = S and S.Chip(f) or f:CreateFontString(nil, "OVERLAY")
  if S then value:SetSize(36, S.CHIP_H) else value:SetFontObject(GameFontHighlight) end
  value:SetPoint("RIGHT", plus, "LEFT", -4, 0)
  local minus = button("-", "ghost", 24)
  minus:SetPoint("RIGHT", value, "LEFT", -4, 0)
  local function step(d)
    local p = profile()
    local r = tonumber(p.editGridSize) or 16
    r = math.max(RASTER_MIN, math.min(RASTER_MAX, r + d))
    p.editGridSize = r
    self:Apply()
  end
  plus:SetScript("OnClick", function() step(RASTER_STEP) end)
  minus:SetScript("OnClick", function() step(-RASTER_STEP) end)
  self.valueChip = value
  local rl = f:CreateFontString(nil, "OVERLAY")
  if S then S.Font(rl, "uiMedium", S.SIZES.body or 12); S.Text(rl, "ink2") else rl:SetFontObject(GameFontNormalSmall) end
  rl:SetPoint("RIGHT", minus, "LEFT", -6, 0)
  rl:SetText("Raster")

  Nock.UI.RegisterNudgeable(f, {
    label = "Edit panel",
    get   = function() return profile().editPanelPos end,
    set   = function(pos) profile().editPanelPos = pos; View:ApplyPanelPosition() end,
    reset = function() profile().editPanelPos = false; View:ApplyPanelPosition() end,
  })
end

function View:ApplyPanelPosition()
  local f = self.panel
  if not f then return end
  local pos = profile().editPanelPos
  f:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -40)
  end
end

local SNAP_LABEL = { off = "Snap: off", release = "Snap: release", drag = "Snap: drag" }

function View:PaintPanel()
  local p = profile()
  if self.valueChip then
    local r = tostring(tonumber(p.editGridSize) or 16)
    if self.valueChip.text then self.valueChip.text:SetText(r) else self.valueChip:SetText(r) end
  end
  local S = Skin()
  local mode = Nock.UI.EditSnapMode(p)
  if S then
    S.SetButtonText(self.snapBtn, SNAP_LABEL[mode], 104)
    S.SetButtonText(self.byBtn, (p.editSnapBy == "corner") and "By: corner" or "By: nearest", 104)
    setToggleLook(self.gridBtn, p.editGridShow ~= false)
    setToggleLook(self.snapBtn, mode ~= "off")
  else
    self.snapBtn:SetText(SNAP_LABEL[mode])
    self.byBtn:SetText((p.editSnapBy == "corner") and "By: corner" or "By: nearest")
  end
end

-- ---------------------------------------------------------------------------
-- Show / hide with the lock
-- ---------------------------------------------------------------------------
function View:Apply()
  local unlocked = not Nock.IsLocked()
  local p = profile()
  self:BuildOverlay()
  if unlocked then
    self:BuildPanel()
    self:ApplyPanelPosition()
    self:PaintPanel()
    self.panel:Show()
    if p.editGridShow ~= false then
      local key = (tonumber(p.editGridSize) or 16) .. "x" .. UIParent:GetWidth() .. "x" .. UIParent:GetHeight()
      if key ~= self._builtFor then self:Rebuild() end
      self.overlay:Show()
    else
      self.overlay:Hide()
    end
  else
    self.overlay:Hide()
    self:SetGhost(nil)
    if self.panel then self.panel:Hide() end
  end
end

function View:OnEnable()
  self:RegisterMessage("NOCK_LOCK_CHANGED", "Apply")
  self:RegisterMessage("NOCK_EDITGRID_CHANGED", "Apply")
  self:RegisterMessage("NOCK_POSITION_RESET", "Apply")
  self:RegisterEvent("DISPLAY_SIZE_CHANGED", "Apply")
  self:RegisterEvent("UI_SCALE_CHANGED", "Apply")
  self:Apply()
end

Nock.UI.EditGrid = View
