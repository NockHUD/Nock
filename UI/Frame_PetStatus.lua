-- UI/Frame_PetStatus.lua
-- Floating status panel anchored to the HUD's bottom-left, growing leftward.
-- Same backdrop style as the cast bar. Shows up to three icons (pet happiness
-- when not Happy, Mend Pet active, Feed Pet active); each renders only while
-- its state is active and the panel hides entirely when nothing is active.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local PetStatusView = Nock:NewModule("PetStatusView", "AceEvent-3.0")
local C = Nock.Constants

local MEND_PET_SPELL        = 27046
local FEED_PET_SPELL        = 6991  -- the cast itself
local FEED_PET_EFFECT_SPELL = 1539  -- the 10s buff applied during the channel

-- Cooldown-text addons we'll defer to (mirrors the lists in Frame_Cooldowns
-- and Frame_Rotation). When any of these is loaded we hide our own countdown
-- text on the slots and let the external addon paint instead.
local EXTERNAL_CD_ADDONS = { "OmniCC", "tullaCC", "ncCooldown" }

-- Blizzard's PetPaperDollFrame happiness face texture + per-state texcoords.
local HAPPINESS_TEX = "Interface\\PetPaperDollFrame\\UI-PetHappiness"
local HAPPINESS_COORD = {
  [1] = { 0.375,  0.5625, 0, 0.359375 },  -- Unhappy
  [2] = { 0.1875, 0.375,  0, 0.359375 },  -- Content
  [3] = { 0,      0.1875, 0, 0.359375 },  -- Happy (not shown — we hide when happy)
}

local function spellIcon(id)
  if not id then return nil end
  if GetSpellInfo then
    local _, _, icon = GetSpellInfo(id)
    if icon then return icon end
  end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  return nil
end

local _mendPetName
local function mendPetName()
  if _mendPetName then return _mendPetName end
  if GetSpellInfo then
    local name = GetSpellInfo(MEND_PET_SPELL)
    if name then _mendPetName = name end
  end
  return _mendPetName or "Mend Pet"
end

local _feedPetEffectName
local function feedPetEffectName()
  if _feedPetEffectName then return _feedPetEffectName end
  if GetSpellInfo then
    local name = GetSpellInfo(FEED_PET_EFFECT_SPELL)
    if name then _feedPetEffectName = name end
  end
  return _feedPetEffectName or "Feed Pet Effect"
end

-- Returns (expirationTime, duration) of the matching buff on the unit (or nil,
-- nil if not found). Duration is needed to drive the radial cooldown swipe.
-- Aura reads go through Core/AuraCache.lua (every read allocates ~1.9 KB on
-- this client; this panel used to walk the pet and the player per refresh).
local function unitBuffInfo(unit, name)
  local AC = Nock.AuraCache
  if not (AC and name and UnitExists and UnitExists(unit)) then return nil end
  local a = AC.ByName(unit, name)
  if a and not a.isHarmful then return a.expirationTime, a.duration end
  return nil
end

local function formatRemaining(seconds)
  if not seconds or seconds <= 0 then return "" end
  if seconds < 10 then return ("%.1f"):format(seconds) end
  return ("%d"):format(math.ceil(seconds))
end

function PetStatusView:OnInitialize()
  local parent   = Nock.parentFrame
  local OUTER    = C.DIM.OUTER_PAD
  local INNER    = C.DIM.INNER_GAP
  local iconSize = C.DIM.PET_PANEL_ICON or C.DIM.COOLDOWN_ICON
  local panelW   = iconSize + 2 * OUTER   -- single column wide

  -- Panel: anchored to HUD's BOTTOMLEFT, extending leftward. x=+1 so the
  -- panel's right border overlaps the HUD's left border into a single seamless
  -- 1px line — symmetric to the cast bar's y=-1 trick at the top. Icons are
  -- stacked vertically inside the panel; height is recomputed in Refresh.
  local panel = CreateFrame("Frame", "NockPetStatusPanel", parent, "BackdropTemplate")
  panel:SetWidth(panelW)
  panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", 1, 0)
  Nock.UI.RegisterPanelBackground(panel)  -- follows the HUD background styling
  panel:Hide()

  -- Three slot frames, each holding an icon. Slots with hasTimer=true get a
  -- Cooldown sub-frame (driving the radial swipe + giving OmniCC something to
  -- paint on) and our own countdown FontString on a higher draw level as a
  -- fallback when no external CD-text addon is loaded.
  local function makeSlot(staticTex, staticCoord, hasTimer)
    local f = CreateFrame("Frame", nil, panel)
    f:SetSize(iconSize, iconSize)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(f)
    if staticTex then icon:SetTexture(staticTex) end
    if staticCoord then icon:SetTexCoord(unpack(staticCoord))
    else                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    f.icon = icon

    if hasTimer then
      local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
      cd:SetAllPoints(icon)
      if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
      if cd.SetDrawSwipe           then cd:SetDrawSwipe(true)           end
      if cd.SetDrawEdge            then cd:SetDrawEdge(false)           end
      if cd.SetSwipeColor          then cd:SetSwipeColor(0, 0, 0, 0.75) end
      -- Suppress any built-in FontString the template instantiates.
      for _, region in ipairs({ cd:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
          region:SetAlpha(0)
          region:Hide()
        end
      end
      f.cooldown = cd

      -- Our own countdown text — sits on a child frame one level above the
      -- cooldown swipe so it isn't painted over. Hidden when an external
      -- CD-text addon is detected (see ApplyExternalCdAddon).
      local textLayer = CreateFrame("Frame", nil, f)
      textLayer:SetAllPoints(f)
      textLayer:SetFrameLevel(cd:GetFrameLevel() + 1)
      local text = textLayer:CreateFontString(nil, "OVERLAY")
      text:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
      text:SetPoint("CENTER")
      text:SetTextColor(unpack(C.COLORS.TEXT))
      f.text = text
      Nock.UI.RegisterFontString(text, "SIZE_OVERLAY", "OUTLINE")
    end

    f:Hide()
    return f
  end

  self.happiness = makeSlot(HAPPINESS_TEX, HAPPINESS_COORD[2], false)  -- no timer
  self.mendPet   = makeSlot(spellIcon(MEND_PET_SPELL),         nil, true)
  self.feedPet   = makeSlot(spellIcon(FEED_PET_SPELL),         nil, true)

  self.frame      = panel
  self._iconSize  = iconSize
  self._OUTER     = OUTER
  self._INNER     = INNER

  -- Defer the OmniCC check until other addons have loaded (same pattern as
  -- Frame_Cooldowns / Frame_Rotation).
  self:RegisterEvent("PLAYER_LOGIN",          "ApplyExternalCdAddon")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyExternalCdAddon")
end

function PetStatusView:ApplyExternalCdAddon()
  if self._cdAddonApplied then return end
  self._cdAddonApplied = true
  local check = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  local has = false
  if check then
    for _, name in ipairs(EXTERNAL_CD_ADDONS) do
      if check(name) then has = true; break end
    end
  end
  for _, slot in ipairs({ self.mendPet, self.feedPet }) do
    if slot.cooldown then
      if has then
        slot.cooldown.noCooldownCount = nil  -- let the external addon paint
        if slot.text then slot.text:Hide() end
      else
        slot.cooldown.noCooldownCount = true
        if slot.text then slot.text:Show() end
      end
    end
  end
end

-- Slow lane (Core:Tick): this Refresh does up to three full 40-slot buff scans
-- (Mend on pet, Feed on player, Feed on pet). Happiness/Mend/Feed all change on
-- a human timescale and the countdown text only shows 0.1s precision, so 10 Hz
-- is exactly enough. The radial swipe is driven by the Cooldown frame itself and
-- animates natively between refreshes.
PetStatusView.refreshInterval = 0.1

-- Glued spot: HUD's BOTTOMLEFT, extending leftward (x=+1 border overlap, see
-- OnInitialize). Free-placement drag/nudge wiring is the shared
-- Nock.UI.EnsureFreePanel/ApplyFreePanelPosition pair (see UI/Widgets.lua).
local function petGlue(panel)
  panel:ClearAllPoints()
  panel:SetPoint("BOTTOMRIGHT", Nock.parentFrame, "BOTTOMLEFT", 1, 0)
end

-- Scratch for Refresh: the active-slot list is reused (it was a fresh table
-- per 10 Hz refresh for as long as a pet is out) and the slot helper is
-- module-level rather than a closure per refresh.
local ACTIVE = {}
local _now = 0

-- Drive a slot's cooldown swipe + fallback text together. Diff-guards
-- SetCooldown so the animation doesn't re-start every tick, and the text so a
-- string is only set when the shown value moves.
local function applyBuffSlot(slot, list, expirationTime, duration)
  local now = _now
  if not (expirationTime and expirationTime > now) then
    slot:Hide()
    if slot.cooldown and (slot._lastCdStart or 0) ~= 0 then
      slot.cooldown:Clear()
      slot._lastCdStart = 0
      slot._lastCdDur   = 0
    end
    return
  end
  local start = (duration and duration > 0) and (expirationTime - duration) or 0
  if slot.cooldown and start > 0 and duration and duration > 0 then
    if start ~= slot._lastCdStart or duration ~= slot._lastCdDur then
      slot.cooldown:SetCooldown(start, duration)
      slot._lastCdStart = start
      slot._lastCdDur   = duration
    end
  end
  if slot.text then
    local txt = formatRemaining(expirationTime - now)
    if txt ~= slot._lastText then
      slot._lastText = txt
      slot.text:SetText(txt)
    end
  end
  list[#list + 1] = slot
end

function PetStatusView:Refresh(state)
  -- Position pass first, before any visibility early-out, so leaving free mode
  -- re-glues the panel even while it's hidden.
  Nock.UI.EnsureFreePanel(self.frame, "PetStatus", "Pet Status", petGlue)
  Nock.UI.ApplyFreePanelPosition(self.frame, "PetStatus", petGlue)

  -- Master visibility gate (Layout → Pet status panel). Off = never shown.
  local prof = Nock.db and Nock.db.profile
  if prof and prof.showPetStatus == false then
    if self.frame:IsShown() then self.frame:Hide() end
    return
  end

  -- The panel is transient (hidden without a pet / active slot) and a hidden
  -- frame can't be dragged — while editing (free placement, unlocked) it's held
  -- open as a static preview instead, like the cast bar's edit preview.
  local editing = Nock.FreeLayoutActive() and not Nock.IsLocked()

  if not (UnitExists and UnitExists("pet")) and not editing then
    if self.frame:IsShown() then self.frame:Hide() end
    return
  end

  local active = ACTIVE
  for i = #active, 1, -1 do active[i] = nil end
  local now    = GetTime()
  _now = now

  -- Happiness — show only when below Happy. Update texcoord each tick because
  -- it can switch between Unhappy and Content. No timer text.
  local h = GetPetHappiness and GetPetHappiness() or 3
  if h and h < 3 then
    self.happiness.icon:SetTexCoord(unpack(HAPPINESS_COORD[h] or HAPPINESS_COORD[2]))
    -- Happiness slot was created with hasTimer=false → no .text field. Guard.
    if self.happiness.text then self.happiness.text:SetText("") end
    active[#active + 1] = self.happiness
  else
    self.happiness:Hide()
  end

  -- React mode: Mend/Feed already render in the ReactBuffs utility row above
  -- the HUD — suppress the duplicate slots here. The happiness nag (which the
  -- React rows do NOT cover) keeps the panel alive.
  local react = prof and prof.hudMode == "react"

  -- Mend Pet — buff on the pet (name-based scan, locale-aware).
  do
    local exp, dur
    if not react then exp, dur = unitBuffInfo("pet", mendPetName()) end
    applyBuffSlot(self.mendPet, active, exp, dur)
  end

  -- Feed Pet — the 10s "Feed Pet Effect" buff (spell 1539) can sit on either
  -- the player or the pet depending on client; check both.
  do
    local exp, dur
    if not react then
      local fName = feedPetEffectName()
      exp, dur = unitBuffInfo("player", fName)
      if not exp then exp, dur = unitBuffInfo("pet", fName) end
    end
    applyBuffSlot(self.feedPet, active, exp, dur)
  end

  if #active == 0 then
    if not editing then
      if self.frame:IsShown() then self.frame:Hide() end
      return
    end
    -- Edit preview: all three slots with their static icons, no timer text.
    active[1] = self.happiness
    active[2] = self.mendPet
    active[3] = self.feedPet
    for _, slot in ipairs(active) do
      if slot.text then slot.text:SetText("") end
    end
  end

  local OUTER, INNER = self._OUTER, self._INNER
  local iconSize     = self._iconSize

  -- Vertical stack: first active slot at the top, subsequent slots step down
  -- with INNER gaps. Panel grows downward (anchored by BOTTOMRIGHT so the
  -- bottom stays glued to the HUD's bottom-left corner — the panel's top edge
  -- extends upward as more slots appear).
  for i, slot in ipairs(active) do
    local yOff = OUTER + (i - 1) * (iconSize + INNER)
    slot:ClearAllPoints()
    slot:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, yOff)
    slot:Show()
  end

  local height = 2 * OUTER + #active * iconSize + math.max(0, #active - 1) * INNER
  self.frame:SetHeight(height)
  if not self.frame:IsShown() then self.frame:Show() end
end
