-- UI/Frame_TonkDial.lua
-- The Steam Tonk countdown: the tonk's own icon with a radial sweep unwinding
-- from the settling delay to zero, at which point Modules/TonkGuard.lua steps
-- you out. It vanishes the moment the transform is gone.
--
-- This replaced the HOLD / RELEASE cue in 1.0.19. That square existed because
-- nothing could exit the tonk in combat and a human finger was the only
-- mechanism available, so the addon's whole job was to tell you when letting go
-- was safe. PetDismiss ended that; the guard now does it itself, in combat or
-- out, and all the player needs is to see it coming.
--
-- The sweep is a real Cooldown widget driven by one SetCooldown call per
-- transform -- the client animates it. There is no per-frame arithmetic here
-- and no OnUpdate on the frame; Refresh only diffs a key and shows or hides.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local TonkDial = Nock:NewModule("TonkDialView", "AceEvent-3.0")
local C = Nock.Constants

-- Floor is 40, not smaller: the resize grip is 16px and stops being usable when
-- it covers half the frame.
local MIN_SIZE, MAX_SIZE = 40, 240
local BORDER = 2
local SOLID_TEX = "Interface\\Buttons\\WHITE8X8"

-- Seconds per lap of the unlocked-state preview sweep. Deliberately far slower
-- than the real half-second: the preview is there to be looked at and dragged,
-- and a half-second loop reads as a strobe.
local PREVIEW_LAP = 3

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function delaySec()
  return Nock.TonkCancelDelay()
end

-- The item's own icon, resolved lazily: the item cache is routinely cold at
-- load, so a nil here is normal and simply means "try again next repaint".
local function tonkIcon()
  if C_Item and C_Item.GetItemIconByID then
    local i = C_Item.GetItemIconByID(C.STEAM_TONK_ITEM)
    if i then return i end
  end
  if GetItemInfo then
    local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(C.STEAM_TONK_ITEM)
    if icon then return icon end
  end
  return nil
end

function TonkDial:OnInitialize()
  -- Parented to UIParent, NOT the HUD box: this is a centre-screen alert and
  -- must survive hudEnabled = false, the same reasoning as the warning frames.
  local f = CreateFrame("Frame", "NockTonkDial", UIParent, "BackdropTemplate")
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:SetResizable(true)
  f:SetClampedToScreen(true)
  -- Resize bounds moved into SetResizeBounds on modernized clients; the split
  -- pair is the older form. Feature-detect rather than assume.
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_SIZE, MIN_SIZE, MAX_SIZE, MAX_SIZE)
  elseif f.SetMinResize then
    f:SetMinResize(MIN_SIZE, MIN_SIZE)
    if f.SetMaxResize then f:SetMaxResize(MAX_SIZE, MAX_SIZE) end
  end
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(fr) fr:StartMoving() end)
  f:SetScript("OnDragStop", function(fr)
    fr:StopMovingOrSizing()
    local point, _, relPoint, x, y = fr:GetPoint()
    Nock.db.profile.tonkDialPosition = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  f:SetBackdrop({
    edgeFile = SOLID_TEX,
    edgeSize = BORDER,
    insets   = { left = BORDER, right = BORDER, top = BORDER, bottom = BORDER },
  })
  f:SetBackdropBorderColor(0, 0, 0, 0.9)
  f:Hide()
  self.frame = f

  -- Cropped by the usual 7% so the icon's own baked-in border does not show
  -- inside ours.
  local icon = f:CreateTexture(nil, "BACKGROUND")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  icon:SetPoint("TOPLEFT", BORDER, -BORDER)
  icon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
  self.icon = icon

  -- CooldownFrameTemplate is ancient and present on this client, but it is a
  -- TEMPLATE: a missing one errors inside CreateFrame rather than returning nil,
  -- so it is probed rather than assumed. Without it the dial still shows the
  -- icon for the length of the transform -- less useful, never broken.
  local ok, cd = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
  if ok and cd then
    cd:SetAllPoints(icon)
    -- Every one of these is Legion-era API that Classic clients mostly but not
    -- universally carry. Guarded individually: the dial degrades a facet at a
    -- time instead of failing whole.
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
    if cd.SetDrawEdge  then cd:SetDrawEdge(true) end
    if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.75) end
    -- Default direction, not reverse: the dark wedge shrinks away as the delay
    -- runs down, which is the same "time remaining" idiom as every action-bar
    -- cooldown in the game.
    if cd.SetReverse then cd:SetReverse(false) end
    self.cd = cd
  end

  -- Resize grip, shown only while unlocked. Square is enforced on release
  -- rather than during the drag: forcing it inside OnSizeChanged re-enters the
  -- sizing path and fights the mouse.
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    local w = math.floor(f:GetWidth() + 0.5)
    if w < MIN_SIZE then w = MIN_SIZE elseif w > MAX_SIZE then w = MAX_SIZE end
    Nock.db.profile.tonkDialSize = w
    TonkDial:ApplySize()
  end)
  self.grip = grip

  -- tonkDialPosition defaults to `false`, so get() returns false and
  -- ComputeNudge seeds from the live frame rather than teleporting to {0,0}.
  Nock.UI.RegisterNudgeable(f, {
    label   = "Steam Tonk dial",
    get     = function() return Nock.db.profile.tonkDialPosition end,
    set     = function(pos)
      Nock.db.profile.tonkDialPosition = pos
      TonkDial:ApplyPosition()
    end,
    default = function() return false end,
  })

  self:ApplySize()
  self:ApplyPosition()
  self:ApplyLock()
  self:RegisterMessage("NOCK_LOCK_CHANGED", "ApplyLock")
  self:RegisterMessage("NOCK_POSITION_RESET", "ApplyPosition")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyVisuals")
end

function TonkDial:ApplySize()
  local size = tonumber(profile("tonkDialSize", 72)) or 72
  if size < MIN_SIZE then size = MIN_SIZE elseif size > MAX_SIZE then size = MAX_SIZE end
  self.frame:SetSize(size, size)
end

function TonkDial:ApplyPosition()
  local pos = profile("tonkDialPosition", false)
  local f = self.frame
  f:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
  end
end

function TonkDial:ApplyVisuals()
  self:ApplySize()
  -- nil is the force-a-repaint sentinel: Refresh compares against `false` for
  -- hidden, so nil can never match a computed value.
  self._rendered = nil
end

-- Unlocked -> grabbable and resizable. The forced repaint matters: while
-- unlocked the dial holds itself open as an edit preview, and a frame that is
-- hidden when idle cannot be dragged, resized or reached by the nudge pad.
function TonkDial:ApplyLock()
  local editable = not Nock.IsLocked()
  self.frame:EnableMouse(editable)
  if editable then self.grip:Show() else self.grip:Hide() end
  self._rendered = nil
  self._previewUntil = nil
end

function TonkDial:EnsureIcon()
  if self._iconSet then return end
  local tex = tonkIcon()
  if tex then
    self.icon:SetTexture(tex)
    self._iconSet = true
  end
end

function TonkDial:Refresh(state)
  local t = state.player.tonk
  -- Off, or with the guard itself off, there is no countdown to draw: nothing
  -- is going to happen at the end of it.
  local on = profile("tonkDialEnabled", true) ~= false
             and profile("tonkAutoCancel", true) ~= false
  local since = (on and t.active and t.since) or false

  -- Edit preview (see ApplyLock). Deliberately NOT suppressed while the setup
  -- wizard is open: the wizard unlocks everything so frames can be seen and
  -- placed, and every other Nock frame previews there. Hiding only this one
  -- would make it the exception. Re-armed from inside Refresh rather than by a
  -- standing timer -- the tick is already running, and a timer that outlives an
  -- unlock is a leak waiting to happen.
  if not since and not Nock.IsLocked() then
    local now = GetTime()
    if not self._previewUntil or now >= self._previewUntil then
      self._previewUntil = now + PREVIEW_LAP
      self:EnsureIcon()
      if self.cd then self.cd:SetCooldown(now, PREVIEW_LAP) end
      self._rendered = "preview:" .. tostring(self._previewUntil)
      self.frame:Show()
    end
    return
  end
  self._previewUntil = nil

  -- `false` means "hidden", NOT nil. _rendered uses nil as the force-a-repaint
  -- sentinel (see ApplyLock/ApplyVisuals), so if hidden were also nil the two
  -- would compare equal and the early return would skip the Hide -- leaving the
  -- dial painted forever after a re-lock.
  if since == self._rendered then return end
  self._rendered = since

  local f = self.frame
  if not since then
    if self.cd then self.cd:SetCooldown(0, 0) end
    f:Hide()
    return
  end
  self:EnsureIcon()
  -- One call per transform. `since` is the aura's receipt time, the same anchor
  -- TonkGuard schedules against, so the sweep hits zero when the dismiss fires
  -- rather than merely near it.
  if self.cd then self.cd:SetCooldown(since, delaySec()) end
  f:Show()
end
