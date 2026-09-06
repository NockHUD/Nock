-- UI/ScrollColumn.lua
-- A ScrollFrame with a thin skin slider: one row per wheel notch, bar only when the content overflows.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
Nock.UI = Nock.UI or {}
local Skin = Nock.Skin
local SC = {}
Nock.UI.ScrollColumn = SC
SC.__index = SC

local BAR_W, BAR_HOVER_W = 4, 6

function SC.New(parent, rowUnit)
  local self = setmetatable({ rowUnit = rowUnit or 54 }, SC)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  self.frame = sf
  local content = CreateFrame("Frame", nil, sf)
  content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
  content:SetWidth(1)
  content:SetHeight(1)
  sf:SetScrollChild(content)
  self.content = content
  -- The bar is a 14 px wide button (easy to hit) drawing a 4 px thumb at its
  -- right edge; a click on it puts the view at that fraction of the range.
  local bar = CreateFrame("Button", nil, parent)
  bar:SetWidth(14)
  bar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -4, -20)
  bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -4, 20)
  local thumb = bar:CreateTexture(nil, "OVERLAY")
  Skin.Paint(thumb, "ink3", 1)
  thumb:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -4, 0)
  thumb:SetSize(BAR_W, 20)
  self.bar, self.thumb = bar, thumb
  -- Press: jump there and start following the cursor (the window's tick
  -- Refresh calls FollowDrag while `dragging`); release ends it.
  bar:SetScript("OnMouseDown", function() self.dragging = true; self:FollowDrag() end)
  bar:SetScript("OnMouseUp", function() self.dragging = false end)
  bar:SetScript("OnHide", function() self.dragging = false end)
  bar:EnableMouseWheel(true)
  bar:SetScript("OnMouseWheel", function(_, delta) self:ScrollTo(self:GetScroll() - delta * self.rowUnit) end)
  bar:Hide()
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, delta)
    local step = self.rowUnit * (IsShiftKeyDown() and 3 or 1)
    self:ScrollTo(self:GetScroll() - delta * step)
  end)
  sf:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w); self:Layout() end)
  bar:SetScript("OnEnter", function() thumb:SetWidth(BAR_HOVER_W) end)
  bar:SetScript("OnLeave", function() thumb:SetWidth(BAR_W) end)
  -- Wheel over the content itself (rows forward theirs through SC.OnWheel).
  content:EnableMouseWheel(true)
  content:SetScript("OnMouseWheel", function(_, delta)
    local step = self.rowUnit * (IsShiftKeyDown() and 3 or 1)
    self:ScrollTo(self:GetScroll() - delta * step)
  end)
  return self
end

function SC:Range()
  local h, vh = self.content:GetHeight() or 0, self.frame:GetHeight() or 0
  return math.max(0, h - vh), h, vh
end

function SC:Layout()
  local range, h, vh = self:Range()
  if range <= 0 then self.bar:Hide(); self.frame:SetVerticalScroll(0); return end
  self.bar:Show()
  local barH = self.bar:GetHeight() or 0
  local th = math.max(20, math.floor(barH * vh / h))
  self.thumb:SetHeight(th)
  local y = self:GetScroll()
  self.thumb:ClearAllPoints()
  self.thumb:SetPoint("TOPRIGHT", self.bar, "TOPRIGHT", -4, -math.floor((barH - th) * (y / range)))
end

function SC:SetContentHeight(h)
  self.content:SetHeight(math.max(1, h))
  local range = self:Range()
  if self:GetScroll() > range then self.frame:SetVerticalScroll(range) end
  self:Layout()
end

function SC:GetScroll() return self.frame:GetVerticalScroll() or 0 end

function SC:ScrollTo(y)
  local range = self:Range()
  y = math.max(0, math.min(range, y))
  self.frame:SetVerticalScroll(y)
  self:Layout()
  if self.onScroll then self.onScroll(y) end
end

function SC:Reset() self.frame:SetVerticalScroll(0); self:Layout() end

-- Put the view where the cursor is on the bar (the thumb's centre follows it).
function SC:FollowDrag()
  local range = self:Range()
  if range <= 0 then self.dragging = false return end
  if not IsMouseButtonDown or not IsMouseButtonDown("LeftButton") then self.dragging = false return end
  local b = self.bar
  local _, cy = GetCursorPosition()
  local es = b:GetEffectiveScale()
  local top, bottom = b:GetTop() or 0, b:GetBottom() or 0
  local th = self.thumb:GetHeight() or 20
  local usable = math.max(1, (top - bottom) - th)
  local frac = ((top - th / 2) - cy / es) / usable
  self:ScrollTo(range * math.max(0, math.min(1, frac)))
end
