-- UI/Frame_AggroWarning.lua
-- The aggro flash: a red starburst at screen centre while state.aggro.active, pulsing through an AnimationGroup.
--
-- Art is the client's own starburst (Interface\Cooldown\star4, additive, red,
-- rotated) unless the profile names a texture path; nothing is bundled.
-- Nudgeable like the warnings row: an edit overlay stands in for the hidden
-- flash while frames are unlocked, position saved in aggroPosition.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("AggroWarningView", "AceEvent-3.0", "AceTimer-3.0")
local C = Nock.Constants

local STOCK_TEXTURE = "Interface\\Cooldown\\star4"
local PULSE_SEC, PULSE_SCALE = 0.25, 0.9

local function profile()
  return Nock.db and Nock.db.profile or nil
end

function View:OnInitialize()
  local f = CreateFrame("Frame", "NockAggroWarning", UIParent)
  f:SetFrameStrata("LOW")
  f:SetSize(300, 300)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:Hide()
  self.frame = f

  local tex = f:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(f)
  tex:SetBlendMode("ADD")
  self.tex = tex

  -- pulse: scale 100% -> 90% and back, looping while shown (no OnUpdate)
  local ag = tex:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local sc = ag:CreateAnimation("Scale")
  sc:SetDuration(PULSE_SEC)
  sc:SetOrigin("CENTER", 0, 0)
  if sc.SetScaleFrom then sc:SetScaleFrom(1, 1); sc:SetScaleTo(PULSE_SCALE, PULSE_SCALE)
  elseif sc.SetScale then sc:SetScale(PULSE_SCALE, PULSE_SCALE) end
  self.pulse = ag

  -- edit overlay (the flash is hidden when idle, so this is what gets dragged)
  local editBG = CreateFrame("Frame", nil, f, "BackdropTemplate")
  editBG:SetAllPoints(f)
  editBG:SetFrameLevel(f:GetFrameLevel() + 10)
  Nock.UI.ApplyBackdrop(editBG)
  editBG:SetBackdropColor(0, 0, 0, 0.25)
  editBG:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  editBG:EnableMouse(true)
  editBG:RegisterForDrag("LeftButton")
  editBG:SetScript("OnDragStart", function() f:StartMoving() end)
  editBG:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    local p = profile()
    if p then p.aggroPosition = { point = point, relPoint = relPoint, x = x, y = y } end
  end)
  local lbl = editBG:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(Nock.UI.GetFont(), 12, "OUTLINE")
  lbl:SetPoint("CENTER"); lbl:SetText("AGGRO")
  editBG:Hide()
  f._editBG = editBG

  Nock.UI.RegisterNudgeable(f, {
    key = "aggro",
    label = "Aggro flash",
    clickTarget = editBG,
    get = function() local p = profile(); return p and p.aggroPosition end,
    set = function(pos) local p = profile(); if p then p.aggroPosition = pos end; View:ApplyPosition() end,
    default = function() return false end,
  })

  self:ApplyVisuals()
  self:ApplyPosition()
  self:ApplyLock()
  self:RegisterMessage("NOCK_LOCK_CHANGED", "ApplyLock")
  self:RegisterMessage("NOCK_POSITION_RESET", "ApplyPosition")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyVisuals")
end

function View:ApplyVisuals()
  local p = profile()
  if not p then return end
  -- The edit overlay follows the on/off switch (ApplyLock); a visuals change
  -- is how the settings window and the wizard announce a flip of it.
  if self.frame and self.frame._editBG then self:ApplyLock() end
  local size = tonumber(p.aggroSize) or 300
  self.frame:SetSize(size, size)
  local path = p.aggroTexture
  if type(path) ~= "string" or path == "" then path = STOCK_TEXTURE end
  self.tex:SetTexture(path)
  local c = p.aggroColor or { 1, 0.07, 0.11, 1 }
  self.tex:SetVertexColor(c[1] or 1, c[2] or 0, c[3] or 0, c[4] or 1)
  self.tex:SetRotation(math.rad(tonumber(p.aggroRotation) or 180))
  if p.aggroPulse == false then
    if self.pulse:IsPlaying() then self.pulse:Stop() end
  elseif self.frame:IsShown() and not self.pulse:IsPlaying() then
    self.pulse:Play()
  end
end

function View:ApplyPosition()
  local p = profile()
  local pos = p and p.aggroPosition
  local f = self.frame
  f:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 15)
  end
end

-- Unlocked: the overlay shows (and the frame with it) so it can be found and
-- dragged; locked: the overlay goes and the flash follows state again.
function View:ApplyLock()
  -- The flash is invisible when idle, so its preview IS the edit overlay:
  -- one keyed reading covers both.
  local p = profile()
  local locked = Nock.IsLockedFor("aggro") or (p ~= nil and p.aggroEnabled == false)
  self.frame._editBG:SetShown(not locked)
  if not locked then
    self.tex:Hide(); self.frame:Show()
  else
    self.tex:Show()
    self._shown = nil   -- let Refresh settle the frame from state
  end
end

-- Settings preview: hold the flash up for `seconds` regardless of threat.
function View:Demo(seconds)
  self._demoUntil = GetTime() + (seconds or 3)
  if self._demoTimer then self:CancelTimer(self._demoTimer) end
  self._demoTimer = self:ScheduleTimer(function() self._demoTimer = nil; self._demoUntil = nil end, seconds or 3)
  self.tex:Show()
end

function View:Refresh(state)
  if Nock.WizardHides("aggro") then
    if self.frame:IsShown() then self.frame:Hide() end
    self._shown = nil
    return
  end
  if not Nock.IsLockedFor("aggro") then return end   -- edit mode owns the frame
  local on = state and state.aggro and state.aggro.active or false
  if self._demoUntil and GetTime() < self._demoUntil then on = true end
  if on == self._shown then return end
  self._shown = on
  if on then
    self.frame:Show()
    local p = profile()
    if not (p and p.aggroPulse == false) and not self.pulse:IsPlaying() then self.pulse:Play() end
  else
    if self.pulse:IsPlaying() then self.pulse:Stop() end
    self.frame:Hide()
  end
end
