-- UI/Frame_Medallion.lua
-- EXPERIMENTAL V3 "next-action medallion": one large movable icon that always
-- answers "what do I press next?" — spell icon from state.rotation.nextAction,
-- native cooldown swipe for the GCD/cast lockout, glow at the press moment,
-- and a desaturated red HOLD state (Auto Shot incoming, don't cast).
-- Feature-flagged: profile.medallionEnabled, off by default (/nock v3).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Medallion = Nock:NewModule("MedallionView", "AceEvent-3.0")
local C = Nock.Constants

local HOLD_COLOR = { 0.85, 0.12, 0.12, 1 }

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

-- Read an RGBA ring color from the profile, falling back to the given literal
-- (the pre-customization default) when the key is absent or malformed.
local function ringColor(key, r, g, b, a)
  local c = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if type(c) == "table" and c[1] then return c[1], c[2], c[3], c[4] end
  return r, g, b, a
end

local function spellTexture(spellId)
  if C_Spell and C_Spell.GetSpellTexture then
    local t = C_Spell.GetSpellTexture(spellId)
    if t then return t end
  end
  if GetSpellTexture then
    local t = GetSpellTexture(spellId)
    if t then return t end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function Medallion:OnInitialize()
  local size = profile("medallionSize", 64)

  -- Parented to the HUD frame so it inherits scale / combat opacity / the
  -- hide-out-of-combat behaviour, but anchored to UIParent at its own saved
  -- position (same pattern as free-layout rows).
  local f = CreateFrame("Frame", "NockMedallion", Nock.parentFrame, "BackdropTemplate")
  f:SetSize(size + 8, size + 30)
  Nock.UI.ApplyBackdrop(f)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
  f:SetScript("OnDragStop", function(frame)
    frame:StopMovingOrSizing()
    local point, _, relPoint, x, y = frame:GetPoint()
    Nock.db.profile.medallionPos = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  f:Hide()
  self.frame = f

  -- medallionPos defaults to `false`, so get() returns false and ComputeNudge
  -- seeds from the live frame position rather than teleporting it to {0,0}.
  Nock.UI.RegisterNudgeable(f, {
    label   = "Medallion",
    get     = function() return Nock.db.profile.medallionPos end,
    set     = function(pos)
      Nock.db.profile.medallionPos = pos
      Medallion:ApplyPosition()
    end,
    default = function() return false end,
  })

  local slot = Nock.UI.CreateIconSlot(f, "NockMedallionIcon", size)
  slot:SetPoint("TOP", f, "TOP", 0, -4)
  self.slot = slot

  -- The medallion paints its own big countdown numeral (self.num) below the
  -- icon, so it never wants digits ON either Cooldown frame. SetHideCountdownNumbers
  -- (in CreateIconSlot / on the ring below) only muzzles Blizzard's built-in text;
  -- external CD-text addons (OmniCC/tullaCC/ncCooldown) key off noCooldownCount.
  -- Unlike Frame_Cooldowns et al. — which DEFER to OmniCC — the medallion blocks
  -- it unconditionally on both frames, else OmniCC paints the lockout number on the
  -- icon swipe AND the ring (both centred on the icon, both driven with the same
  -- SetCooldown), stacking two identical numerals = the "double cooldown text".
  slot.cooldown.noCooldownCount = true

  -- Countdown ring around the icon (the artifact medallion's ring). A native
  -- Cooldown frame with a donut swipe texture renders the radial wipe as a
  -- ring arc — smooth, client-driven, no OnUpdate. Semantics match the mockup:
  -- the ring always shows time-until-you-press, draining to empty at the press
  -- moment; in HOLD it turns red and counts down to the auto shot.
  local RING_TEX = "Interface\\AddOns\\Nock\\Media\\Ring"
  local track = f:CreateTexture(nil, "ARTWORK")
  track:SetTexture(RING_TEX)
  track:SetVertexColor(ringColor("medallionRingTrackColor", 1, 1, 1, 0.08))
  self.ringTrack = track

  local ring = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
  ring:SetFrameLevel(math.max(0, slot:GetFrameLevel() - 1))
  ring.noCooldownCount = true  -- ring is a swipe-only dial; keep OmniCC off it (see slot.cooldown above)
  if ring.SetSwipeTexture then
    ring:SetSwipeTexture(RING_TEX)
    if ring.SetHideCountdownNumbers then ring:SetHideCountdownNumbers(true) end
    if ring.SetDrawSwipe then ring:SetDrawSwipe(true) end
    if ring.SetDrawEdge  then ring:SetDrawEdge(false)  end
    if ring.SetDrawBling then ring:SetDrawBling(false) end
    ring:SetSwipeColor(ringColor("medallionRingColorPress", 1, 1, 1, 0.85))
    -- Same countdown-number suppression as CreateIconSlot.
    for _, region in ipairs({ ring:GetRegions() }) do
      if region and region.GetObjectType and region:GetObjectType() == "FontString" then
        region:SetAlpha(0)
        region:Hide()
      end
    end
    self.ring = ring
  else
    -- Client without custom swipe textures: no ring, the square icon swipe
    -- still carries the lockout.
    ring:Hide()
    track:Hide()
    self.ring = nil
  end
  self:SizeRing(size)

  -- Mini "and after that" icon docked on the medallion's bottom-right corner,
  -- fed by state.rotation.nextNextAction (real one-press foresight).
  local nn = CreateFrame("Frame", nil, f, "BackdropTemplate")
  nn:SetFrameLevel(slot:GetFrameLevel() + 5)
  Nock.UI.ApplyBackdrop(nn)
  nn:SetAlpha(0.85)
  local nnIcon = nn:CreateTexture(nil, "ARTWORK")
  nnIcon:SetPoint("TOPLEFT", nn, "TOPLEFT", 1, -1)
  nnIcon:SetPoint("BOTTOMRIGHT", nn, "BOTTOMRIGHT", -1, 1)
  nnIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  nn:Hide()
  self.nn = nn
  self.nnIcon = nnIcon
  self:SizeNextNext(size)

  -- Countdown numeral + state word under the icon. Sizes are medallion-specific
  -- (bigger than any C.FONT preset), so they're set directly rather than through
  -- RegisterFontString — an LSM font change applies on the next /reload.
  local num = f:CreateFontString(nil, "OVERLAY")
  num:SetFont(Nock.UI.GetFont(), 14, "OUTLINE")
  num:SetPoint("TOP", slot, "BOTTOM", 0, -2)
  self.num = num

  local lbl = f:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(Nock.UI.GetFont(), 8, "OUTLINE")
  lbl:SetPoint("TOP", num, "BOTTOM", 0, -1)
  lbl:SetTextColor(1, 1, 1, 0.65)
  self.lbl = lbl

  self:ApplyPosition()
  self:ApplyLock()
  self:RegisterMessage("NOCK_LOCK_CHANGED", "ApplyLock")
  self:RegisterMessage("NOCK_POSITION_RESET", "ApplyPosition")  -- profile switch
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyVisuals")
end

function Medallion:ApplyPosition()
  local pos = profile("medallionPos", false)
  local f = self.frame
  f:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    -- Default: screen center, a bit below the character — where the eyes already are.
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
  end
end

-- Unlocked + enabled → grabbable box (drag to move); locked → invisible chrome.
function Medallion:ApplyLock()
  local p = Nock.db and Nock.db.profile or {}
  local editable = (not Nock.IsLocked()) and (p.medallionEnabled == true)
  local f = self.frame
  f:EnableMouse(editable)
  if editable then
    f:SetBackdropColor(0, 0, 0, 0.25)
    f:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  else
    f:SetBackdropColor(0, 0, 0, 0)
    f:SetBackdropBorderColor(0, 0, 0, 0)
  end
end

function Medallion:SizeRing(size)
  -- The donut's inner radius is 50/128 of the texture, so a ring frame at
  -- 1.28× the icon size puts the ring's inner edge right at the icon border.
  local rs = math.floor(size * 1.28 + 0.5)
  if self.ring then
    self.ring:SetSize(rs, rs)
    self.ring:ClearAllPoints()
    self.ring:SetPoint("CENTER", self.slot, "CENTER", 0, 0)
  end
  self.ringTrack:SetSize(rs, rs)
  self.ringTrack:ClearAllPoints()
  self.ringTrack:SetPoint("CENTER", self.slot, "CENTER", 0, 0)
end

function Medallion:SizeNextNext(size)
  local s = math.max(16, math.floor(size * 0.38))
  self.nn:SetSize(s, s)
  self.nn:ClearAllPoints()
  -- Fully outside the medallion, docked to its bottom-right edge, so the big
  -- icon stays unobstructed.
  self.nn:SetPoint("BOTTOMLEFT", self.slot, "BOTTOMRIGHT", 4, 0)
end

function Medallion:ApplyVisuals()
  local size = profile("medallionSize", 64)
  self.slot:SetSize(size, size)
  self.frame:SetSize(size + 8, size + 30)
  self:SizeRing(size)
  self:SizeNextNext(size)
  self:ApplyLock()
  -- Live ring recolor on NOCK_VISUALS_CHANGED: apply the (always-visible) track
  -- color directly, and clear the cached ring mode so the next Refresh re-applies
  -- the swipe color with the new value.
  if self.ringTrack then
    self.ringTrack:SetVertexColor(ringColor("medallionRingTrackColor", 1, 1, 1, 0.08))
  end
  self._ringMode = nil
end

function Medallion:Refresh(state)
  local p = Nock.db and Nock.db.profile
  local f = self.frame
  -- rotationHelperEnabled == false means the engine never sets nextAction —
  -- the medallion would be a permanent (wrong) HOLD, so hide it too.
  if not p or not p.medallionEnabled or p.showRotation == false
     or p.rotationHelperEnabled == false then
    if f:IsShown() then f:Hide() end
    return
  end

  -- Visible while fighting-relevant (in combat, or an attackable live target)
  -- or whenever the HUD is unlocked so it can be found and dragged.
  -- demo.rotationSample: the onboarding wizard is showing off the medallion, so
  -- treat the moment as fight-relevant. The next action itself needs no faking —
  -- Steady Shot scores as castable with no swing pending.
  local t = state.target
  local relevant = state.player.inCombat or (t.exists and t.alive and not t.friendly)
                   or state.demo.rotationSample
  if not relevant and Nock.IsLocked() then
    if f:IsShown() then f:Hide() end
    return
  end
  if not f:IsShown() then f:Show() end

  local now = GetTime()
  local slot = self.slot

  -- Lockout = the longer of the GCD and a running cast; the native swipe shows it.
  local gcd = state.gcd
  local lockStart, lockDur = 0, 0
  if gcd.active and gcd.remaining > 0 then
    lockStart, lockDur = gcd.start, gcd.duration
  end
  -- Real casts only; the Auto Shot wind-up has its own field because it does not
  -- lock the player out (the press queues).
  local cast = state.player.casting
  local castRunning = cast and cast.endTime and cast.endTime > now
  if castRunning and cast.endTime > lockStart + lockDur then
    lockStart, lockDur = cast.startTime, cast.endTime - cast.startTime
  end
  local lockRem = (lockDur > 0) and math.max(0, lockStart + lockDur - now) or 0

  local nextId = state.rotation.nextAction
  local mode, spellId
  if nextId then
    spellId = nextId
    mode = (lockRem > 0) and "soon" or "now"
  else
    -- Nothing safe to press: the clip zone. Show the incoming Auto Shot,
    -- desaturated, counting down to the shot.
    spellId = C.SpellID.AUTO_SHOT
    mode = "hold"
  end

  if spellId ~= self._iconSpell then
    self._iconSpell = spellId
    slot.icon:SetTexture(spellTexture(spellId))
  end

  local desat = (mode == "hold")
  if desat ~= self._desat then
    self._desat = desat
    slot.icon:SetDesaturated(desat)
  end

  local glowOn = (mode == "now")
  if glowOn ~= self._glowOn then
    self._glowOn = glowOn
    Nock.UI.SetIconNextHighlight(slot, glowOn)
  end

  if desat ~= self._holdBorder then
    self._holdBorder = desat
    Nock.UI.SetIconHighlight(slot, desat and HOLD_COLOR or nil)
  end

  -- Restart the swipe only when a NEW lockout begins — re-calling SetCooldown
  -- every tick would freeze the animation.
  if lockRem > 0 then
    if self._cdStart ~= lockStart or self._cdDur ~= lockDur then
      self._cdStart, self._cdDur = lockStart, lockDur
      slot.cooldown:SetCooldown(lockStart, lockDur)
    end
  elseif self._cdStart then
    self._cdStart, self._cdDur = nil, nil
    if slot.cooldown.Clear then slot.cooldown:Clear() else slot.cooldown:SetCooldown(0, 0) end
  end

  local numTxt, lblTxt
  if mode == "now" then
    numTxt = "NOW"
    lblTxt = (spellId == C.SpellID.RAPTOR_STRIKE) and "STEP IN" or "PRESS"
  elseif mode == "soon" then
    numTxt = ("%.1f"):format(lockRem)
    lblTxt = castRunning and "CASTING" or "ON GCD"
  else
    local rem = state.ranged.swingRemaining or 0
    numTxt = (rem > 0) and ("%.1f"):format(rem) or "--"
    lblTxt = "HOLD"
  end
  -- Countdown ring: time until the next press (the lockout), draining to empty
  -- at the press moment; in HOLD it goes red and counts down to the auto shot.
  local ring = self.ring
  if ring then
    if profile("medallionRing", true) == false then
      if self._ringShown then
        self._ringShown = false
        ring:Hide()
        self.ringTrack:Hide()
      end
    else
      if not self._ringShown then
        self._ringShown = true
        ring:Show()
        self.ringTrack:Show()
      end
      local rStart, rDur
      if mode == "hold" then
        local rr = state.ranged
        if rr.swingStart and rr.swingStart > 0 and rr.swingDuration and rr.swingDuration > 0 then
          rStart, rDur = rr.swingStart, rr.swingDuration
        end
      elseif lockRem > 0 then
        rStart, rDur = lockStart, lockDur
      end
      if rStart then
        if self._ringStart ~= rStart or self._ringDur ~= rDur then
          self._ringStart, self._ringDur = rStart, rDur
          ring:SetCooldown(rStart, rDur)
        end
      elseif self._ringStart then
        self._ringStart, self._ringDur = nil, nil
        if ring.Clear then ring:Clear() else ring:SetCooldown(0, 0) end
      end
      if mode ~= self._ringMode then
        self._ringMode = mode
        if mode == "hold" then
          ring:SetSwipeColor(ringColor("medallionRingColorHold", 0.85, 0.12, 0.12, 0.9))
        else
          ring:SetSwipeColor(ringColor("medallionRingColorPress", 1, 1, 1, 0.85))
        end
      end
    end
  end

  -- Second upcoming press (badge). Hidden in HOLD — there's no press to chain from.
  local nn2 = (mode ~= "hold") and state.rotation.nextNextAction or nil
  if nn2 ~= self._nnSpell then
    self._nnSpell = nn2
    if nn2 then
      self.nnIcon:SetTexture(spellTexture(nn2))
      self.nn:Show()
    else
      self.nn:Hide()
    end
  end

  if numTxt ~= self._numTxt then
    self._numTxt = numTxt
    self.num:SetText(numTxt)
  end
  if lblTxt ~= self._lblTxt then
    self._lblTxt = lblTxt
    self.lbl:SetText(lblTxt)
  end
  if mode ~= self._mode then
    self._mode = mode
    if mode == "now" then
      local c = p.rotNextColor or { 0.00, 1.00, 0.40, 1.00 }
      self.num:SetTextColor(c[1], c[2], c[3], 1)
    elseif mode == "soon" then
      self.num:SetTextColor(1, 1, 1, 1)
    else
      self.num:SetTextColor(0.9, 0.25, 0.25, 1)
    end
  end
end
