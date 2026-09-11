-- UI/Frame_PvPBadge.lua
-- The small PVP tag shown while PvP mode is active (so a manual On is never forgotten); nudgeable, position in pvpBadgePosition.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("PvPBadgeView", "AceEvent-3.0")
local C = Nock.Constants

local W, H = 64, 22

local function profile()
  return Nock.db and Nock.db.profile or nil
end

local function pvpActive()
  local st = Nock.state and Nock.state.player
  return st ~= nil and st.pvp == true
end

function View:OnInitialize()
  local f = CreateFrame("Frame", "NockPvPBadge", UIParent, "BackdropTemplate")
  f:SetFrameStrata("LOW")
  f:SetSize(W, H)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  Nock.UI.ApplyBackdrop(f)
  f:SetBackdropColor(0.55, 0.06, 0.08, 0.85)
  f:SetBackdropBorderColor(1, 0.35, 0.35, 0.9)
  f:Hide()
  self.frame = f

  local lbl = f:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(Nock.UI.GetFont(), 13, "OUTLINE")
  lbl:SetPoint("CENTER", 0, 0)
  lbl:SetText("PVP")
  lbl:SetTextColor(1, 0.9, 0.9, 1)
  self.label = lbl

  -- edit overlay: the tag is hidden outside the mode, so this is what gets dragged
  local editBG = CreateFrame("Frame", nil, f)
  editBG:SetAllPoints(f)
  editBG:SetFrameLevel(f:GetFrameLevel() + 10)
  editBG:EnableMouse(true)
  editBG:RegisterForDrag("LeftButton")
  editBG:SetScript("OnDragStart", function() f:StartMoving() end)
  editBG:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    local p = profile()
    if p then p.pvpBadgePosition = { point = point, relPoint = relPoint, x = x, y = y } end
  end)
  editBG:Hide()
  f._editBG = editBG

  Nock.UI.RegisterNudgeable(f, {
    key = "pvpbadge",
    label = "PvP tag",
    clickTarget = editBG,
    get = function() local p = profile(); return p and p.pvpBadgePosition end,
    set = function(pos) local p = profile(); if p then p.pvpBadgePosition = pos end; View:ApplyPosition() end,
    default = function() return false end,
  })

  self:ApplyPosition()
  self:ApplyLock()
  self:RegisterMessage("NOCK_LOCK_CHANGED", "ApplyLock")
  self:RegisterMessage("NOCK_POSITION_RESET", "ApplyPosition")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyShown")
  self:RegisterMessage("NOCK_PVP_CHANGED", "ApplyShown")
end

function View:ApplyPosition()
  local f, p = self.frame, profile()
  f:ClearAllPoints()
  local pos = p and p.pvpBadgePosition
  if type(pos) == "table" then
    f:SetPoint(pos.point or "TOP", UIParent, pos.relPoint or "TOP", pos.x or 0, pos.y or -140)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  end
end

function View:ApplyShown()
  local p = profile()
  -- Switched off: no preview either; the wizard's toggle must show on the spot.
  local unlocked = Nock.EditPreview("pvpbadge") and p ~= nil and p.pvpBadge ~= false
  local on = p ~= nil and p.pvpBadge ~= false and pvpActive() and not Nock.WizardHides("pvpbadge")
  if on or unlocked then
    if not self.frame:IsShown() then self.frame:Show() end
  elseif self.frame:IsShown() then
    self.frame:Hide()
  end
end

function View:ApplyLock()
  local unlocked = not Nock.IsLockedFor("pvpbadge")
  self.frame._editBG:SetShown(unlocked)
  self.frame:SetBackdropBorderColor(unpack(unlocked and C.COLORS.BORDER_UNLOCK or { 1, 0.35, 0.35, 0.9 }))
  self:ApplyShown()
end
