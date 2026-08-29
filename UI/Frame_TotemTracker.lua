-- UI/Frame_TotemTracker.lua
-- Totem-range panel glued to the HUD's RIGHT edge — mirror of the pet-status
-- panel on the left. Core slots stacked bottom→up: Earth, Air aura. Windfury
-- is an EXTRA slot added on TOP only while its weapon enchant is on you
-- (twisting); absent → not rendered at all. Shown while a shaman is in the
-- group (force flag / sim override for testing).
--   in range  → the active totem's own icon, full colour, cooldown swipe
--   out of range → default greyed icon (Windfury / Strength of Earth) + the
--                   thin next-action glow ("move closer to your shaman")

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local TotemTrackerView = Nock:NewModule("TotemTrackerView")
local C = Nock.Constants

local function profileGet(key, fallback)
  local p = Nock.db and Nock.db.profile
  if p and p[key] ~= nil then return p[key] end
  return fallback
end
local function isEnabled()   return profileGet("totemTrackerEnabled", true) and true or false end
local function forceShaman() return profileGet("totemForceShaman", true) and true or false end
local function totemScale()
  local s = profileGet("totemScale", 1.0)
  if type(s) ~= "number" or s <= 0 then return 1.0 end
  return s
end

-- Glued spot: HUD's BOTTOMRIGHT, extending rightward. x=-1 in the panel's own
-- scaled space (divide by s) so its left border overlaps the HUD's right border
-- into one seamless 1px line. Free-placement drag/nudge wiring is the shared
-- Nock.UI.EnsureFreePanel/ApplyFreePanelPosition pair (see UI/Widgets.lua).
local function totemGlue(panel, s)
  panel:ClearAllPoints()
  panel:SetPoint("BOTTOMLEFT", Nock.parentFrame, "BOTTOMRIGHT", -1 / (s or 1), 0)
end

local function spellIcon(id)
  if not id then return nil end
  if GetSpellInfo then
    local _, _, icon = GetSpellInfo(id)
    if icon then return icon end
  end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  return nil
end

-- Clicking a totem slot pings the group to drop that element's totem when its
-- buff is absent (= you're out of range / it isn't down). Throttled so a double
-- click can't spam chat; if it's already up, a quiet local note instead.
local ANNOUNCE_GAP = 5  -- seconds between chat pings per element
local MISSING_MSG = {
  air      = "Air totem missing - need Grace of Air / Wrath of Air, please drop one in range.",
  earth    = "Earth totem missing - need Strength of Earth, please drop one in range.",
  windfury = "Windfury Totem missing - please drop / twist Windfury in range.",
}
local PRESENT_MSG = {
  air      = "Air totem is up.",
  earth    = "Earth totem is up.",
  windfury = "Windfury Totem is up.",
}

local function groupChannel()
  if IsInRaid  and IsInRaid()  then return "RAID"  end
  if IsInGroup and IsInGroup() then return "PARTY" end
  return nil
end

function TotemTrackerView:Announce(element)
  local t    = Nock.state and Nock.state.totems
  local info = t and t[element]
  if info and info.present then
    Nock:Print(PRESENT_MSG[element])
    return
  end
  local now = GetTime()
  if now - (self._lastAnnounce[element] or 0) < ANNOUNCE_GAP then return end
  local ch = groupChannel()
  if not ch then
    Nock:Print("Not in a group - no one to notify (" .. element .. " totem missing).")
    return
  end
  self._lastAnnounce[element] = now
  SendChatMessage(MISSING_MSG[element], ch)
end

local function wireClick(slot, element)
  slot:EnableMouse(true)
  slot:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" then
      TotemTrackerView:Announce(element)
    end
  end)
end

function TotemTrackerView:OnInitialize()
  local parent   = Nock.parentFrame
  local OUTER    = C.DIM.OUTER_PAD
  local INNER    = C.DIM.INNER_GAP
  local iconSize = C.DIM.PET_PANEL_ICON or C.DIM.COOLDOWN_ICON
  local panelW   = iconSize + 2 * OUTER

  -- Glued to the HUD's BOTTOMRIGHT, extending rightward. x=-1 so the panel's
  -- left border overlaps the HUD's right border into one seamless 1px line —
  -- exact mirror of the pet-status panel's x=+1 on the left.
  local panel = CreateFrame("Frame", "NockTotemTrackerPanel", parent, "BackdropTemplate")
  panel:SetWidth(panelW)
  panel:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", -1, 0)
  Nock.UI.RegisterPanelBackground(panel)  -- follows the HUD background styling
  panel:Hide()

  -- Air slot now tracks the air AURA (Grace/Wrath/…), so its greyed default is
  -- a Grace-of-Air icon. Windfury is the extra top slot (its default barely
  -- matters — it's only ever shown when actually present).
  self._airDefaultIcon   = spellIcon(C.SpellID.GRACE_OF_AIR)   or "Interface\\Icons\\Spell_Nature_InvisibilityTotem"
  self._wfDefaultIcon    = spellIcon(C.SpellID.WINDFURY_TOTEM) or "Interface\\Icons\\Spell_Nature_Windfury"
  self._earthDefaultIcon = spellIcon(8075)                     or "Interface\\Icons\\Spell_Nature_EarthBindTotem"

  self.windfurySlot = Nock.UI.CreateIconSlot(panel, "NockTotemWindfury", iconSize)
  self.airSlot      = Nock.UI.CreateIconSlot(panel, "NockTotemAir",      iconSize)
  self.earthSlot    = Nock.UI.CreateIconSlot(panel, "NockTotemEarth",    iconSize)
  self.windfurySlot.icon:SetTexture(self._wfDefaultIcon)
  self.airSlot.icon:SetTexture(self._airDefaultIcon)
  self.earthSlot.icon:SetTexture(self._earthDefaultIcon)
  self.windfurySlot:Hide()
  self.airSlot:Hide()
  self.earthSlot:Hide()

  self._lastAnnounce = { air = 0, earth = 0, windfury = 0 }
  wireClick(self.windfurySlot, "windfury")
  wireClick(self.airSlot,      "air")
  wireClick(self.earthSlot,    "earth")

  self.panel    = panel
  self._iconSz  = iconSize
  self._OUTER   = OUTER
  self._INNER   = INNER
end

-- in range → active totem icon, full colour, swipe; out of range → default
-- greyed icon + thin next-action glow.
local function applySlot(slot, info, defaultIcon)
  local present = info and info.present
  local useIcon = (present and info.icon) or defaultIcon
  if useIcon ~= slot._lastIcon then
    slot.icon:SetTexture(useIcon)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot._lastIcon    = useIcon
    slot._lastPresent = nil   -- texture swap drops desat; force re-apply
  end
  if present ~= slot._lastPresent then
    if present then
      slot.icon:SetVertexColor(1, 1, 1, 1)
      if slot.icon.SetDesaturated then slot.icon:SetDesaturated(false) end
      Nock.UI.SetIconNextHighlight(slot, false)
    else
      slot.icon:SetVertexColor(0.55, 0.55, 0.55, 1)
      if slot.icon.SetDesaturated then slot.icon:SetDesaturated(true) end
      Nock.UI.SetIconNextHighlight(slot, true, nil, 1)
    end
    slot._lastPresent = present
  end
  local now = GetTime()
  if present and info.duration > 0 and info.expirationTime > now then
    local start = info.expirationTime - info.duration
    if start ~= slot._lastCdStart or info.duration ~= slot._lastCdDur then
      slot.cooldown:SetCooldown(start, info.duration)
      slot._lastCdStart, slot._lastCdDur = start, info.duration
    end
  elseif (slot._lastCdStart or 0) ~= 0 then
    slot.cooldown:Clear()
    slot._lastCdStart, slot._lastCdDur = 0, 0
  end
end

function TotemTrackerView:Refresh(state)
  -- Position + scale via the shared side-panel pass: glued in grid mode, saved
  -- free position (with first-run capture, drag-safe re-apply) in free mode.
  Nock.UI.EnsureFreePanel(self.panel, "TotemTracker", "Totem Tracker", totemGlue)
  Nock.UI.ApplyFreePanelPosition(self.panel, "TotemTracker", totemGlue, totemScale())

  local mod       = Nock:GetModule("TotemTracker", true)
  -- React mode replaces this panel with the ReactBuffs rows (which read the
  -- same state.totems the TotemTracker engine keeps publishing).
  local showTotem = isEnabled()
                    and (Nock.db.profile.hudMode ~= "react")
                    and (forceShaman() or (mod and mod.HasShaman and mod:HasShaman()))

  if not showTotem then
    Nock.UI.SetIconNextHighlight(self.windfurySlot, false)
    Nock.UI.SetIconNextHighlight(self.airSlot, false)
    Nock.UI.SetIconNextHighlight(self.earthSlot, false)
    -- The panel is transient (needs a shaman in group) and an invisible frame
    -- can't be placed — while the HUD is unlocked (Classic look only; React
    -- replaces this panel with the ReactBuffs rows) hold it open as a static
    -- two-slot preview. Grid mode: glued, so it rides the box drag and shows
    -- where it will sit. Free placement: draggable itself (edit border via
    -- ApplyFreePanelPosition above).
    if not Nock.IsLocked() and isEnabled()
       and (Nock.db.profile.hudMode or "classic") ~= "react" then
      local sz, OUTER, INNER = self._iconSz, self._OUTER, self._INNER
      self.windfurySlot:Hide()
      self.earthSlot:ClearAllPoints()
      self.earthSlot:SetPoint("BOTTOM", self.panel, "BOTTOM", 0, OUTER)
      self.airSlot:ClearAllPoints()
      self.airSlot:SetPoint("BOTTOM", self.panel, "BOTTOM", 0, OUTER + sz + INNER)
      if not self.earthSlot:IsShown() then self.earthSlot:Show() end
      if not self.airSlot:IsShown()   then self.airSlot:Show()   end
      self.panel:SetHeight(2 * OUTER + 2 * sz + INNER)
      if not self.panel:IsShown() then self.panel:Show() end
      return
    end
    if self.panel:IsShown() then self.panel:Hide() end
    return
  end

  local t     = state.totems or {}
  t.air, t.earth, t.windfury = t.air or {}, t.earth or {}, t.windfury or {}
  local sz    = self._iconSz
  local OUTER = self._OUTER
  local INNER = self._INNER

  -- Air aura + Earth are core slots (always shown, greyed when out of range).
  -- Windfury is an EXTRA slot on TOP, rendered only while the WF enchant is
  -- actually on you — when absent it's fully cleared and the panel collapses
  -- back to the normal 2 slots (no greyed placeholder for it).
  local showWF = t.windfury.present and true or false

  applySlot(self.airSlot,   t.air,   self._airDefaultIcon)
  applySlot(self.earthSlot, t.earth, self._earthDefaultIcon)
  if showWF then
    applySlot(self.windfurySlot, t.windfury, self._wfDefaultIcon)
  else
    Nock.UI.SetIconNextHighlight(self.windfurySlot, false)
    if (self.windfurySlot._lastCdStart or 0) ~= 0 then
      self.windfurySlot.cooldown:Clear()
      self.windfurySlot._lastCdStart, self.windfurySlot._lastCdDur = 0, 0
    end
    self.windfurySlot._lastPresent = nil
    if self.windfurySlot:IsShown() then self.windfurySlot:Hide() end
  end

  -- Stack from the bottom upward, mirroring the pet-status panel: Earth at the
  -- bottom (flush with the HUD's bottom edge), the air aura above it, and the
  -- Windfury extra slot (when present) on top.
  self.earthSlot:ClearAllPoints()
  self.earthSlot:SetPoint("BOTTOM", self.panel, "BOTTOM", 0, OUTER)
  self.airSlot:ClearAllPoints()
  self.airSlot:SetPoint("BOTTOM", self.panel, "BOTTOM", 0, OUTER + sz + INNER)
  if not self.earthSlot:IsShown() then self.earthSlot:Show() end
  if not self.airSlot:IsShown()   then self.airSlot:Show()   end

  local slotCount = 2
  if showWF then
    slotCount = 3
    self.windfurySlot:ClearAllPoints()
    self.windfurySlot:SetPoint("BOTTOM", self.panel, "BOTTOM", 0, OUTER + 2 * (sz + INNER))
    if not self.windfurySlot:IsShown() then self.windfurySlot:Show() end
  end

  self.panel:SetHeight(2 * OUTER + slotCount * sz + (slotCount - 1) * INNER)
  if not self.panel:IsShown() then self.panel:Show() end
end
