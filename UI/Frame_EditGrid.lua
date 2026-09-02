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
local function Skin() return Nock.Skin end

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
-- Two rows: the title row (title, help line, Lock) over a hairline, then the
-- controls row of three labelled groups -- GRID (show toggle + raster
-- stepper), SNAP (off / release / drag) and ALIGN (nearest / corner) -- as
-- segments whose active member wears the accent. PANEL_W is a floor; the
-- row's measured width wins when the fonts run wider.
local PANEL_W, PANEL_H, PAD = 560, 70, 12
local TITLE_ROW_H = 33          -- title row, rule below it at this y
local TITLE_DY = -3             -- the display face sits high in its box; drop the caps to the row centre
local ROW2_TOP = TITLE_ROW_H + 1 + 7   -- 22-high controls centred in the 36 below the rule
local GROUP_GAP, LABEL_GAP, DIVIDER_PAD = 4, 6, 12
local OVERLAP = -1              -- segment members share a hairline

local function setKind(btn, on)
  local S = Skin()
  if S then S.ButtonKind(btn, on and "primary" or "ghost") end
  local base = btn:GetParent():GetFrameLevel()
  btn:SetFrameLevel(base + (on and 3 or 2))
end

-- One button in the panel's vocabulary; `w` nil = fit the label.
local function button(f, label, kind, w)
  local S = Skin()
  if S then return S.Button(f, label, kind or "ghost", w) end
  local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  b:SetSize(w or 60, 22); b:SetText(label)
  b.text = b:GetFontString()
  return b
end

local function label(f, text)
  local S = Skin()
  local fs = f:CreateFontString(nil, "OVERLAY")
  if S then S.Font(fs, "uiBold", S.SIZES.key or 10); S.Text(fs, "ink3") else fs:SetFontObject(GameFontDisableSmall) end
  fs:SetText(text)
  return fs
end

-- A run of buttons laid edge to edge after `anchor`. `members` is a list of
-- { value, label }; `pick(value)` runs on a click. Returns the buttons keyed
-- by value plus the rightmost one for the next anchor.
local function segment(f, anchor, gap, members, pick)
  local byValue, prev = {}, anchor
  for i = 1, #members do
    local m = members[i]
    local b = button(f, m.label, "ghost")
    b:SetPoint("LEFT", prev, "RIGHT", (i == 1) and gap or OVERLAP, 0)
    b:SetScript("OnClick", function() pick(m.value) end)
    byValue[m.value] = b
    prev = b
  end
  return byValue, prev
end

local function divider(f, anchor)
  local S = Skin()
  local d = S and S.Rule(f, "line") or f:CreateTexture(nil, "ARTWORK")
  if not S then d:SetColorTexture(0.15, 0.15, 0.15, 1) end
  d:SetSize(1, 22)
  d:SetPoint("LEFT", anchor, "RIGHT", DIVIDER_PAD, 0)
  return d
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

  -- Title row: title, help, Lock.
  local title = f:CreateFontString(nil, "OVERLAY")
  if S then S.Font(title, "display", S.SIZES.h2 or 20); S.Text(title, "ink") else title:SetFontObject(GameFontNormal) end
  title:SetPoint("LEFT", f, "TOPLEFT", PAD, -TITLE_ROW_H / 2 + TITLE_DY)
  title:SetText("NOCK  EDIT MODE")

  local lock = button(f, "Lock", "primary", 64)
  lock:SetPoint("RIGHT", f, "TOPRIGHT", -8, -TITLE_ROW_H / 2)
  lock:SetScript("OnClick", function() Nock:SetLocked(true) end)

  local help = f:CreateFontString(nil, "OVERLAY")
  if S then S.Font(help, "ui", S.SIZES.small or 11); S.Text(help, "ink3") else help:SetFontObject(GameFontDisableSmall) end
  help:SetPoint("RIGHT", lock, "LEFT", -12, 0)
  help:SetPoint("LEFT", title, "RIGHT", 12, 0)
  help:SetJustifyH("RIGHT")
  help:SetWordWrap(false)
  help:SetText("Drag a frame to move it, click it for a nudge pad")

  local rule = S and S.Rule(f, "lineSoft") or f:CreateTexture(nil, "ARTWORK")
  if not S then rule:SetColorTexture(0.10, 0.10, 0.10, 1) end
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -TITLE_ROW_H)
  rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -TITLE_ROW_H)
  rule:SetHeight(1)

  -- Controls row. Every element hangs LEFT off the one before it; `cursor`
  -- is the running width so the panel can grow to fit.
  local origin = CreateFrame("Frame", nil, f)
  origin:SetSize(1, 22)
  origin:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 1, -ROW2_TOP)
  local cursor = PAD

  -- GRID: label, Show toggle (with the check), raster stepper.
  local gridLabel = label(f, "GRID")
  gridLabel:SetPoint("LEFT", origin, "RIGHT", 0, 0)
  cursor = cursor + gridLabel:GetStringWidth() + LABEL_GAP

  local show = button(f, "Show", "ghost", 68)
  show:SetPoint("LEFT", gridLabel, "RIGHT", LABEL_GAP, 0)
  show:SetScript("OnClick", function()
    local p = profile()
    p.editGridShow = not (p.editGridShow ~= false)
    self:Apply()
  end)
  if S then
    -- Icon at the left, label after it: the check reads as the state.
    local ico = show:CreateTexture(nil, "OVERLAY")
    ico:SetPoint("LEFT", show, "LEFT", 6, 0)
    S.Icon(ico, "check", "accentInk")
    S.IconSize(ico)
    show.ico = ico
    show.text:ClearAllPoints()
    show.text:SetPoint("LEFT", ico, "RIGHT", 2, 0)
  end
  self.gridBtn = show
  cursor = cursor + 68 + GROUP_GAP

  local minus = button(f, "-", "ghost", 22)
  minus:SetPoint("LEFT", show, "RIGHT", GROUP_GAP, 0)
  local value = S and S.Chip(f) or f:CreateFontString(nil, "OVERLAY")
  if S then value:SetSize(36, 22) else value:SetFontObject(GameFontHighlight) end
  value:SetPoint("LEFT", minus, "RIGHT", OVERLAP, 0)
  local plus = button(f, "+", "ghost", 22)
  plus:SetPoint("LEFT", value, "RIGHT", OVERLAP, 0)
  if S then minus:SetFrameLevel(f:GetFrameLevel() + 2); plus:SetFrameLevel(f:GetFrameLevel() + 2) end
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
  cursor = cursor + 22 + 36 + 22 + 2 * OVERLAP

  -- SNAP
  local d1 = divider(f, plus)
  cursor = cursor + DIVIDER_PAD + 1
  local snapLabel = label(f, "SNAP")
  snapLabel:SetPoint("LEFT", d1, "RIGHT", DIVIDER_PAD, 0)
  cursor = cursor + DIVIDER_PAD + snapLabel:GetStringWidth()
  local snapBtns, snapLast = segment(f, snapLabel, LABEL_GAP, {
    { value = "off", label = "Off" }, { value = "release", label = "Release" }, { value = "drag", label = "Drag" },
  }, function(v) profile().editGridSnap = v; self:Apply() end)
  self.snapBtns = snapBtns
  cursor = cursor + LABEL_GAP
  for _, b in pairs(snapBtns) do cursor = cursor + b:GetWidth() + OVERLAP end
  cursor = cursor - OVERLAP

  -- ALIGN
  local d2 = divider(f, snapLast)
  cursor = cursor + DIVIDER_PAD + 1
  local byLabel = label(f, "ALIGN")
  byLabel:SetPoint("LEFT", d2, "RIGHT", DIVIDER_PAD, 0)
  cursor = cursor + DIVIDER_PAD + byLabel:GetStringWidth()
  local byBtns = segment(f, byLabel, LABEL_GAP, {
    { value = "nearest", label = "Nearest" }, { value = "corner", label = "Corner" },
  }, function(v) profile().editSnapBy = v; self:Apply() end)
  self.byBtns = byBtns
  cursor = cursor + LABEL_GAP
  for _, b in pairs(byBtns) do cursor = cursor + b:GetWidth() + OVERLAP end
  cursor = cursor - OVERLAP

  f:SetWidth(math.max(PANEL_W, math.ceil(cursor + PAD)))

  Nock.UI.RegisterNudgeable(f, {
    label  = "Edit panel",
    chrome = true,
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

function View:PaintPanel()
  local p = profile()
  local S = Skin()
  if self.valueChip then
    local r = tostring(tonumber(p.editGridSize) or 16)
    if self.valueChip.text then self.valueChip.text:SetText(r) else self.valueChip:SetText(r) end
  end
  local showing = p.editGridShow ~= false
  setKind(self.gridBtn, showing)
  if S and self.gridBtn.ico then
    S.Icon(self.gridBtn.ico, "check", showing and "accentInk" or "ink3")
    S.IconSize(self.gridBtn.ico)
  end
  local mode = Nock.UI.EditSnapMode(p)
  for v, b in pairs(self.snapBtns) do setKind(b, v == mode) end
  local by = (p.editSnapBy == "corner") and "corner" or "nearest"
  for v, b in pairs(self.byBtns) do setKind(b, v == by) end
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
