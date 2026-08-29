-- UI/Frame_ShoppingList.lua
-- Floating, draggable shopping-list panel. Row layout (space-between):
--   [icon] item name ......................... have/need
-- Item name is white; the count is red (current) / gold (required). A close
-- button dismisses the panel until you re-enter a shopping zone or run
-- /nock shopping. Auto-shows in a configured city zone; /nock shopping is a
-- manual override that works anywhere (shows by default when invoked).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ShoppingView = Nock:NewModule("ShoppingView", "AceEvent-3.0")
local C = Nock.Constants

local MAX_ROWS = 24

local OUTER   = C.DIM.OUTER_PAD
local INNER   = C.DIM.INNER_GAP
local ROW_H   = C.DIM.SHOPPING_ROW_H
local ROW_GAP = 5   -- room for the thin divider between items

local HEADER_HEIGHT = 14
local HEADER_FONT   = "Numen"
local HEADER_SIZE   = 11
local HEADER_STYLE  = "THICKOUTLINE"
local BOTTOM_VPAD   = OUTER + 3

-- Inline colour escapes for the two-tone count ("3/5").
local C_HAVE    = "|cffff5555"   -- red   — current amount
local C_HAVE_OK = "|cff8fd36b"   -- green — current already meets the goal
local C_NEED    = "|cff8fd36b"   -- green — required amount
local C_SEP     = "|cff7f7f7f"   -- grey  — the "/" separator (echoes the row divider)
local C_END     = "|r"

local COLOR_NAME    = { 1.00, 1.00, 1.00, 1 }   -- item text: white
local COLOR_DONE    = { 0.62, 0.62, 0.62, 1 }   -- item text of a stocked row (shown on request)
local COLOR_STOCKED = { 0.40, 0.85, 0.45, 1 }   -- nothing missing
local COLOR_TOGGLE_OFF = { 0.45, 0.45, 0.45, 1 } -- the show-stocked toggle at rest

local function isEnabled() return (Nock.db and Nock.db.profile and Nock.db.profile.shoppingEnabled) ~= false end
local function showCompleted() return (Nock.db and Nock.db.profile and Nock.db.profile.shoppingShowCompleted) == true end
local function isLocked()  return Nock.IsLocked() end
local function contentWidth()
  local p = Nock.db and Nock.db.profile
  return (p and p.shoppingWidth) or 210
end
local function position()
  local p = Nock.db and Nock.db.profile and Nock.db.profile.shoppingPosition
  return p or { point = "CENTER", relPoint = "CENTER", x = -250, y = 0 }
end

local function createRow(panel, width)
  local f = CreateFrame("Frame", nil, panel)
  f:SetSize(width, ROW_H)

  -- 2px black border = a solid black backing the icon is inset into.
  local iconBG = f:CreateTexture(nil, "BACKGROUND")
  iconBG:SetSize(ROW_H, ROW_H)
  iconBG:SetPoint("LEFT", f, "LEFT", 0, 0)
  iconBG:SetTexture("Interface\\Buttons\\WHITE8X8")
  iconBG:SetVertexColor(0, 0, 0, 1)
  f.iconBG = iconBG

  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT",     iconBG, "TOPLEFT",      2, -2)
  icon:SetPoint("BOTTOMRIGHT", iconBG, "BOTTOMRIGHT", -2,  2)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.icon = icon

  -- Right-justified count ("3/5"), spanning the full row height and
  -- vertically centred.
  local count = f:CreateFontString(nil, "OVERLAY")
  count:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  count:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    0, 0)
  count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  count:SetJustifyH("RIGHT")
  count:SetJustifyV("MIDDLE")
  f.count = count

  -- Item name fills the space between the icon and the count (space-between),
  -- full row height, vertically centred.
  local name = f:CreateFontString(nil, "OVERLAY")
  name:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  name:SetPoint("TOPLEFT",     iconBG, "TOPRIGHT",    INNER, 0)
  name:SetPoint("BOTTOMRIGHT", count,  "BOTTOMLEFT", -INNER, 0)
  name:SetJustifyH("LEFT")
  name:SetJustifyV("MIDDLE")
  name:SetWordWrap(false)
  name:SetTextColor(unpack(COLOR_NAME))
  f.name = name

  -- Thin divider sitting in the gap below the row (toggled per-row in Refresh
  -- so it never trails after the last visible item).
  local div = f:CreateTexture(nil, "BORDER")
  div:SetTexture("Interface\\Buttons\\WHITE8X8")
  div:SetVertexColor(1, 1, 1, 0.10)
  div:SetHeight(1)
  div:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, -math.floor(ROW_GAP / 2))
  div:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, -math.floor(ROW_GAP / 2))
  div:Hide()
  f.divider = div

  Nock.UI.RegisterFontString(count, "SIZE_OVERLAY", "OUTLINE")
  Nock.UI.RegisterFontString(name,  "SIZE_OVERLAY", "OUTLINE")
  return f
end

function ShoppingView:OnInitialize()
  local panel = CreateFrame("Frame", "NockShopping", UIParent, "BackdropTemplate")
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    Nock.db.profile.shoppingPosition = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  Nock.UI.RegisterNudgeable(panel, {
    label   = "Shopping List",
    get     = function() return Nock.db.profile.shoppingPosition end,
    set     = function(pos)
      Nock.db.profile.shoppingPosition = pos
      ShoppingView:ApplyPosition()
    end,
    default = function() return Nock.Defaults.profile.shoppingPosition end,
  })
  Nock.UI.ApplyUserPanelStyle(panel, "shopping")
  panel:Hide()

  local header = panel:CreateFontString(nil, "OVERLAY")
  -- Re-applies once SharedMedia plugin registers "Numen" if it lands after us.
  Nock.UI.RegisterHeaderFontString(header, HEADER_FONT, HEADER_SIZE, HEADER_STYLE)
  header:SetPoint("TOPLEFT",  panel, "TOPLEFT",   OUTER + 14, -OUTER)
  header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(OUTER + 14), -OUTER)
  header:SetHeight(HEADER_HEIGHT)
  header:SetJustifyH("CENTER")
  header:SetJustifyV("MIDDLE")
  header:SetTextColor(1, 1, 1, 1)
  header:SetText("SHOPPING LIST")
  panel.header = header

  -- Close button (always clickable, even while the panel is locked). Dismisses
  -- until a shopping zone is (re-)entered or /nock shopping is run.
  local close = CreateFrame("Button", nil, panel)
  close:SetSize(16, 16)
  close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
  local cx = close:CreateFontString(nil, "OVERLAY")
  cx:SetFont(Nock.UI.GetFont(), 13, "THICKOUTLINE")
  cx:SetPoint("CENTER")
  cx:SetText("x")
  cx:SetTextColor(0.85, 0.40, 0.40, 1)
  close:SetScript("OnEnter", function() cx:SetTextColor(1.00, 0.70, 0.70, 1) end)
  close:SetScript("OnLeave", function() cx:SetTextColor(0.85, 0.40, 0.40, 1) end)
  close:SetScript("OnClick", function() ShoppingView:SetManual("hide") end)
  panel.close = close

  -- Show-stocked toggle (top-left, the close button's mirror): lists the
  -- items already at or above their threshold too, with a green count, so
  -- the panel doubles as a full inventory check. A profile flag, so it
  -- survives a reload; Options carries the same switch.
  local toggle = CreateFrame("Button", nil, panel)
  toggle:SetSize(16, 16)
  toggle:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
  local tick = toggle:CreateTexture(nil, "OVERLAY")
  tick:SetPoint("CENTER")
  local Skin = Nock.Skin
  if Skin and Skin.Icon and Skin.Icon(tick, "check", "ink", 1) then
    Skin.IconSize(tick, 16)
  else
    tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    tick:SetSize(16, 16)
  end
  panel.toggleTick = tick
  toggle:SetScript("OnClick", function()
    Nock.db.profile.shoppingShowCompleted = not showCompleted()
    ShoppingView:PaintToggle()
    ShoppingView:Refresh(Nock.state)
  end)
  toggle:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Show stocked items")
    GameTooltip:AddLine(showCompleted() and "On: every tracked item is listed, stocked ones in green."
                                         or "Off: only items below their threshold are listed.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panel.toggle = toggle

  self.panel     = panel
  self._manual   = nil      -- nil = auto (zone), "show" / "hide" = override
  self._wasActive = false
  self._vis      = {}       -- scratch: indices into state.shopping.items to draw
  self.rows      = {}
  self:PaintToggle()
  local w = contentWidth()
  for i = 1, MAX_ROWS do
    local row = createRow(panel, w)
    row:Hide()
    self.rows[i] = row
  end

  self:ApplyPosition()
  self:ApplyLock()

  self:RegisterMessage("NOCK_VISUALS_CHANGED",     "OnVisualsChanged")
  self:RegisterMessage("NOCK_LOCK_CHANGED",        "ApplyLock")
  self:RegisterMessage("NOCK_SHOP_POSITION_RESET", "ApplyPosition")
  self:RegisterMessage("NOCK_POSITION_RESET",      "ApplyPosition")  -- profile switch
end

function ShoppingView:ApplyPosition()
  local p = position()
  self.panel:ClearAllPoints()
  self.panel:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
end

function ShoppingView:ApplyLock()
  local locked = isLocked()
  self.panel:EnableMouse(not locked)
  self:ApplyStyle()
end

-- User Background block (shopping* keys); the green unlock border wins while
-- the panel is draggable so it stays findable.
function ShoppingView:ApplyStyle()
  Nock.UI.ApplyUserPanelStyle(self.panel, "shopping")
  if not isLocked() then
    self.panel:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  end
end

function ShoppingView:OnVisualsChanged()
  local w = contentWidth()
  for _, row in ipairs(self.rows) do row:SetWidth(w) end
  self:ApplyStyle()
  self:PaintToggle()
  self:Refresh(Nock.state)
end

-- The show-stocked toggle's colour: green while on, grey at rest.
function ShoppingView:PaintToggle()
  local tick = self.panel and self.panel.toggleTick
  if not tick then return end
  local c = showCompleted() and COLOR_STOCKED or COLOR_TOGGLE_OFF
  tick:SetVertexColor(c[1], c[2], c[3], c[4])
end

-- Manual override from the close button / "/nock shopping".
function ShoppingView:SetManual(mode)
  self._manual = mode   -- "show" | "hide" | nil
  self:Refresh(Nock.state)
end

function ShoppingView:Refresh(state)
  local sp = state.shopping

  -- Re-arm a manual dismiss/show whenever we (re-)enter a shopping zone, so a
  -- fresh city visit always auto-shows again.
  local active = sp and sp.active or false
  if active and not self._wasActive then self._manual = nil end
  self._wasActive = active

  local show
  if self._manual == "show" then
    show = true
  elseif self._manual == "hide" then
    show = false
  else
    show = active
  end

  if not isEnabled() or not show then
    if self.panel:IsShown() then self.panel:Hide() end
    return
  end

  -- Which rows to draw: the ones below threshold, plus the stocked ones when
  -- the toggle is on. Indices into sp.items, in catalog order, no allocation.
  local vis, all = self._vis, showCompleted()
  local n = 0
  for i = 1, (sp and sp.n or 0) do
    local it = sp.items[i]
    if it and (all or not it.done) then
      n = n + 1
      vis[n] = i
      if n >= MAX_ROWS then break end
    end
  end

  local w        = contentWidth()
  local panelW   = w + 2 * OUTER
  local topInset = OUTER + HEADER_HEIGHT + INNER
  local rowCount = (n > 0) and n or 1
  local panelH   = topInset + rowCount * ROW_H + math.max(0, rowCount - 1) * ROW_GAP + BOTTOM_VPAD

  self.panel:SetSize(panelW, panelH)

  for i = 1, MAX_ROWS do
    local row = self.rows[i]
    if i == 1 and n == 0 then
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", self.panel, "TOPLEFT", OUTER, -topInset)
      row.icon:SetTexture("Interface\\Icons\\Tradeskill_Engineering")
      row.name:SetText("Stocked up")
      row.name:SetTextColor(unpack(COLOR_STOCKED))
      row.count:SetText("")
      row.divider:Hide()
      if not row:IsShown() then row:Show() end
    elseif i <= n then
      local it = sp.items[vis[i]]
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", self.panel, "TOPLEFT",
        OUTER, -(topInset + (i - 1) * (ROW_H + ROW_GAP)))
      row.icon:SetTexture(it.icon)
      row.name:SetText(it.label or "?")
      row.name:SetTextColor(unpack(it.done and COLOR_DONE or COLOR_NAME))
      local have, need = it.have or 0, it.need or 0
      local haveCol = (have >= need) and C_HAVE_OK or C_HAVE
      row.count:SetText(("%s%d%s %s/%s %s%d%s"):format(
        haveCol, have, C_END, C_SEP, C_END, C_NEED, need, C_END))
      if i < n then row.divider:Show() else row.divider:Hide() end
      if not row:IsShown() then row:Show() end
    else
      if row:IsShown() then row:Hide() end
    end
  end

  if not self.panel:IsShown() then self.panel:Show() end
end
