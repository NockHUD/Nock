-- UI/Frame_Rotation.lua
-- 6-slot rotation row: [Aspect][Steady][Multi][Arcane][Raptor][HM]
-- Aspect slot: live icon of active aspect; greyed Hawk icon + red glow when missing.
-- Ability slots (2-5): static icons. NEXT-glow on state.rotation.nextAction (added in substep 4b).
-- HM slot: Hunter's Mark icon greyed when not applied; full color + timer when on target.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local RotationView = Nock:NewModule("RotationView", "AceEvent-3.0")
local C = Nock.Constants

-- Cooldown-timer addons we'll defer to instead of painting our own cdText on
-- ability slots. Mirrors Frame_Cooldowns' list — keep them in sync.
local EXTERNAL_CD_ADDONS = { "OmniCC", "tullaCC", "ncCooldown" }

local function getSpellIcon(spellID)
  if not spellID then return nil end
  if GetSpellInfo then
    local _, _, icon = GetSpellInfo(spellID)
    if icon then return icon end
  end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spellID) end
  if GetSpellTexture then return GetSpellTexture(spellID) end
  return nil
end

-- Hunter's Mark ranks, max first
local HM_RANKS = { 27322, 14325, 14324, 14323, 1130 }

local function huntersMarkIcon()
  for _, id in ipairs(HM_RANKS) do
    local icon = getSpellIcon(id)
    if icon then return icon end
  end
  return 132212  -- WA fallback texture file ID for Hunter's Mark
end

local SLOTS = {
  { kind = "aspect" },
  { kind = "ability", spellId = 34120, label = "Steady" },
  { kind = "ability", spellId = 27021, label = "Multi"  },
  { kind = "ability", spellId = 27019, label = "Arcane" },
  { kind = "ability", spellId = 27014, label = "Raptor" },
  { kind = "huntersMark" },
}

local function formatCD(remaining)
  if remaining <= 0 then return "" end
  if remaining < 10 then return ("%.1f"):format(remaining) end
  if remaining < 90 then return ("%d"):format(math.ceil(remaining)) end
  return ("%dm"):format(math.floor(remaining / 60))
end

local CD_KEY = {
  [27021] = "MS",   -- Multi-Shot
  [27019] = "Arc",  -- Arcane Shot
}

-- Direct query for abilities not in TRACKED_COOLDOWNS (e.g., Raptor Strike).
-- Returns (start, duration, remaining); the GCD reading (duration <= 1.5) is
-- treated as not-a-real-cooldown and reported as (0, 0, 0).
local function spellCdInfo(spellID)
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(spellID)
    if info then start, duration = info.startTime, info.duration end
  elseif GetSpellCooldown then
    start, duration = GetSpellCooldown(spellID)
  end
  if not start or start == 0 then return 0, 0, 0 end
  if not duration or duration <= 1.5 then return 0, 0, 0 end
  return start, duration, math.max(0, start + duration - GetTime())
end

-- GCD probe. The global cooldown is derived once per tick (Core:Tick) and
-- published to state.gcd; read it here instead of re-probing. Returns
-- (start, duration, remaining).
local function gcdInfo()
  local g = Nock.state and Nock.state.gcd
  if not g then return 0, 0, 0 end
  return g.start or 0, g.duration or 0, g.remaining or 0
end

-- Slots that consume / respect the GCD and should show the GCD swipe when
-- otherwise castable. Raptor (27014) is deliberately absent — it's an
-- on-next-melee-swing ability and is NOT GCD-bound.
local GCD_BOUND_SPELLS = {
  [C.SpellID.STEADY_SHOT] = true,  -- 34120
  [C.SpellID.MULTI_SHOT]  = true,  -- 27021
  [C.SpellID.ARCANE_SHOT] = true,  -- 27019
}

-- Icon brightness while a GCD-bound shot is blocked by the running GCD.
-- Roughly matches the cooldown swipe's darkness (SetSwipeColor 0,0,0,0.75)
-- so it reads as the familiar "on cooldown / not yet" dim — minus the sweep.
local GCD_FADE = 0.35

-- Raid-class target = world boss or skull-level (UnitLevel == -1 / "??").
-- Excludes dead and non-hostile targets so we don't nag during friendly checks.
local function isBossTarget()
  if not (UnitExists and UnitExists("target")) then return false end
  if UnitIsDead and UnitIsDead("target") then return false end
  if UnitCanAttack and not UnitCanAttack("player", "target") then return false end
  if UnitClassification and UnitClassification("target") == "worldboss" then return true end
  if UnitLevel and UnitLevel("target") == -1 then return true end
  return false
end

-- "Improved Hunter's Mark" lives in the MM tab (always tab 2 for TBC hunter).
-- Cached on talent-change events; the boss-target nag is gated on this so
-- non-MM specs aren't nudged. (Defined here, above its first use in
-- RefreshTalents — Lua locals are only visible after their definition.)
local _improvedHMName
local function improvedHMName()
  if _improvedHMName then return _improvedHMName end
  -- Rank 1 of the talent grants spell 19421 — use its localized name.
  if GetSpellInfo then
    local name = GetSpellInfo(19421)
    if name then _improvedHMName = name end
  end
  return _improvedHMName or "Improved Hunter's Mark"
end

local function checkImprovedHMTalent()
  if not (GetNumTalents and GetTalentInfo) then return false end
  local target = improvedHMName()
  for i = 1, GetNumTalents(2) or 0 do
    local name, _, _, _, rank = GetTalentInfo(2, i)
    if name == target and rank and rank > 0 then return true end
  end
  return false
end

function RotationView:OnInitialize()
  local parent = Nock.parentFrame
  local iconSize = C.DIM.ROTATION_ICON
  local gap = C.DIM.INNER_GAP
  local n = #SLOTS
  local totalWidth = n * iconSize + (n - 1) * gap

  local container = CreateFrame("Frame", "NockRotation", parent)
  container:SetSize(totalWidth, iconSize)

  -- 136116 is the WA's "no aspect" placeholder texture file ID
  self._defaultAspectIcon = 136116
  self._hmIcon = huntersMarkIcon()

  self.slots = {}
  for i, def in ipairs(SLOTS) do
    local slot = Nock.UI.CreateIconSlot(container, "NockRotSlot" .. i, iconSize)
    slot:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * (iconSize + gap), 0)
    slot._def = def
    slot._lastIcon = nil
    slot._lastText = ""
    slot._lastState = nil
    slot.cdText:SetText("")

    if def.kind == "ability" then
      local icon = getSpellIcon(def.spellId)
      if icon then
        slot.icon:SetTexture(icon)
        slot._lastIcon = icon
      end
    end
    self.slots[i] = slot
  end
  self.frame = container

  -- PLAYER_LOGIN / PLAYER_ENTERING_WORLD both need to drive the OmniCC check
  -- AND the talent cache. AceEvent only keeps the last callback per event, so
  -- a single handler runs both jobs to avoid the second registration silently
  -- clobbering the first.
  self:RegisterEvent("PLAYER_LOGIN",          "OnAddonsReady")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnAddonsReady")

  -- Drop any active next-highlight when the user changes the effect/color so
  -- the new style takes over on the next Refresh tick.
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "OnVisualsChanged")

  -- Re-check talents on respec — these don't overlap with the login events.
  self._hasImprovedHM = false
  self:RegisterEvent("PLAYER_TALENT_UPDATE",     "RefreshTalents")
  self:RegisterEvent("CHARACTER_POINTS_CHANGED", "RefreshTalents")
end

function RotationView:OnAddonsReady()
  self:ApplyExternalCdAddon()
  self:RefreshTalents()
end

function RotationView:RefreshTalents()
  self._hasImprovedHM = checkImprovedHMTalent()
end

function RotationView:OnVisualsChanged()
  for _, slot in ipairs(self.slots) do
    Nock.UI.SetIconNextHighlight(slot, false)
    slot._lastState = nil  -- force the next Refresh to re-evaluate
  end
end

function RotationView:ApplyExternalCdAddon()
  if self._cdAddonApplied then return end
  self._cdAddonApplied = true
  local check = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if not check then return end
  local has = false
  for _, name in ipairs(EXTERNAL_CD_ADDONS) do
    if check(name) then has = true; break end
  end
  for _, slot in ipairs(self.slots) do
    if slot._def.kind == "ability" then
      if has then
        slot.cooldown.noCooldownCount = nil  -- let the external addon paint
        slot.cdText:Hide()
      else
        slot.cooldown.noCooldownCount = true
        slot.cdText:Show()
      end
    end
  end
end

function RotationView:Refresh(state)
  for _, slot in ipairs(self.slots) do
    local kind = slot._def.kind
    if kind == "aspect" then
      self:RefreshAspect(slot, state)
    elseif kind == "ability" then
      self:RefreshAbility(slot, state)
    elseif kind == "huntersMark" then
      self:RefreshHuntersMark(slot, state)
    end
  end
end

function RotationView:RefreshAspect(slot, state)
  local aspect = state.player.aspect
  if aspect then
    if aspect.icon and aspect.icon ~= slot._lastIcon then
      slot.icon:SetTexture(aspect.icon)
      slot._lastIcon = aspect.icon
    end
    if slot._lastState ~= "active" then
      slot.icon:SetVertexColor(1, 1, 1, 1)
      Nock.UI.SetIconHighlight(slot, nil)
      Nock.UI.SetIconAlertGlow(slot, false)
      slot._lastState = "active"
    end
  else
    local icon = self._defaultAspectIcon
    if icon and icon ~= slot._lastIcon then
      slot.icon:SetTexture(icon)
      slot._lastIcon = icon
    end
    if slot._lastState ~= "missing" then
      slot.icon:SetVertexColor(1, 1, 1, 1)
      Nock.UI.SetIconHighlight(slot, nil)
      Nock.UI.SetIconAlertGlow(slot, true)
      slot._lastState = "missing"
    end
  end
end

function RotationView:RefreshAbility(slot, state)
  local def = slot._def

  -- Raptor Strike: dim with no text if dual-wielding (can never weave)
  if def.spellId == 27014 and not state.player.canWeave then
    if slot._lastState ~= "dim" then
      slot.icon:SetVertexColor(0.3, 0.3, 0.3, 1)
      Nock.UI.SetIconHighlight(slot, nil)
      Nock.UI.SetIconNextHighlight(slot, false)
      slot.cdText:SetText("")
      slot._lastState = "dim"
      slot._lastText = ""
    end
    return
  end

  -- CD lookup. Multi/Arcane are tracked in state.cooldowns (have start/duration);
  -- Raptor isn't tracked, so we query directly for matching start/duration values
  -- to drive the radial swipe.
  local cdKey = CD_KEY[def.spellId]
  local cdStart, cdDuration, cdRemaining = 0, 0, 0
  if cdKey then
    local cd = state.cooldowns and state.cooldowns[cdKey]
    if cd then
      cdStart, cdDuration, cdRemaining = cd.startTime or 0, cd.duration or 0, cd.remaining or 0
    end
  elseif def.spellId == 27014 then  -- Raptor Strike (6s CD, not in TRACKED_COOLDOWNS)
    cdStart, cdDuration, cdRemaining = spellCdInfo(27014)
  end

  if cdRemaining > 0 then
    if slot._lastState ~= "cd" then
      -- Full-colour icon + radial swipe conveys the CD; no need to dim the art.
      slot.icon:SetVertexColor(1, 1, 1, 1)
      Nock.UI.SetIconHighlight(slot, nil)
      Nock.UI.SetIconNextHighlight(slot, false)
      slot._lastState = "cd"
    end
    local txt = formatCD(cdRemaining)
    if txt ~= slot._lastText then
      slot.cdText:SetText(txt)
      slot._lastText = txt
    end
  else
    -- Ready (no real cooldown). If this slot is GCD-bound and the GCD is
    -- still running you physically can't cast it yet, so instead of the
    -- "next" glow we FADE the icon (no glow, no radial) — a quiet "don't
    -- press this until the GCD is over". The instant the GCD ends the slot
    -- snaps back to its bright next-glow / idle look.
    local gcdBlocked = false
    if GCD_BOUND_SPELLS[def.spellId] then
      local _, _, gr = gcdInfo()
      gcdBlocked = gr > 0
    end
    local nextAction = state.rotation.nextAction
    local isNext = nextAction and def.spellId == nextAction

    if gcdBlocked then
      -- Still show the next-action effect on the slot the engine wants next
      -- (so you see WHAT to press), but fade the icon so you also see it
      -- isn't castable yet. Non-next GCD-bound slots just fade, no glow.
      if isNext then
        if slot._lastState ~= "gcdnext" then
          slot.icon:SetVertexColor(GCD_FADE, GCD_FADE, GCD_FADE, 1)
          Nock.UI.SetIconHighlight(slot, nil)
          Nock.UI.SetIconNextHighlight(slot, true)
          slot._lastState = "gcdnext"
        end
      else
        if slot._lastState ~= "gcd" then
          slot.icon:SetVertexColor(GCD_FADE, GCD_FADE, GCD_FADE, 1)
          Nock.UI.SetIconHighlight(slot, nil)
          Nock.UI.SetIconNextHighlight(slot, false)
          slot._lastState = "gcd"
        end
      end
    elseif isNext then
      if slot._lastState ~= "next" then
        slot.icon:SetVertexColor(1, 1, 1, 1)
        Nock.UI.SetIconHighlight(slot, nil)
        Nock.UI.SetIconNextHighlight(slot, true)
        slot._lastState = "next"
      end
    else
      if slot._lastState ~= "idle" then
        slot.icon:SetVertexColor(1, 1, 1, 1)
        Nock.UI.SetIconHighlight(slot, nil)
        Nock.UI.SetIconNextHighlight(slot, false)
        slot._lastState = "idle"
      end
    end

    if slot._lastText ~= "" then
      slot.cdText:SetText("")
      slot._lastText = ""
    end
  end

  -- Swipe source: the ability's OWN cooldown only (Multi 10s / Arcane 6s /
  -- Raptor 6s). The GCD is intentionally NOT drawn as a radial here — a
  -- running GCD instead fades the icon (see the ready branch above), which
  -- reads as "wait, don't press" far more clearly than a fast sweep.
  local swStart, swDur = 0, 0
  if cdRemaining > 0 and cdDuration > 0 then
    swStart, swDur = cdStart, cdDuration
  end

  -- Only call SetCooldown when start/duration actually change, otherwise the
  -- animation re-triggers every tick.
  if swDur > 0 then
    if swStart ~= slot._lastCdStart or swDur ~= slot._lastCdDuration then
      slot.cooldown:SetCooldown(swStart, swDur)
      slot._lastCdStart    = swStart
      slot._lastCdDuration = swDur
    end
  elseif (slot._lastCdStart or 0) ~= 0 then
    slot.cooldown:Clear()
    slot._lastCdStart    = 0
    slot._lastCdDuration = 0
  end
end

function RotationView:RefreshHuntersMark(slot, state)
  if self._hmIcon and self._hmIcon ~= slot._lastIcon then
    slot.icon:SetTexture(self._hmIcon)
    slot._lastIcon = self._hmIcon
  end

  local mark = state.target.huntersMark
  if mark then
    -- HM is up on the target (any source). UnitDebuff's expirationTime is
    -- valid regardless of caster, so the timer reads correctly for raid-mate
    -- marks too.
    if slot._lastState ~= "active" then
      slot.icon:SetVertexColor(1, 1, 1, 1)
      Nock.UI.SetIconHighlight(slot, nil)
      Nock.UI.SetIconAlertGlow(slot, false)
      slot._lastState = "active"
    end
    local txt = formatCD(mark.remaining or 0)
    if txt ~= slot._lastText then
      slot.cdText:SetText(txt)
      slot._lastText = txt
    end
  elseif isBossTarget() and self._hasImprovedHM then
    -- No HM on a raid-class target — flash the urgent red glow (same look as
    -- "missing aspect" on the leftmost rotation slot).
    if slot._lastState ~= "urgent" then
      slot.icon:SetVertexColor(1, 1, 1, 1)
      Nock.UI.SetIconHighlight(slot, nil)
      Nock.UI.SetIconAlertGlow(slot, true)
      slot._lastState = "urgent"
    end
    if slot._lastText ~= "" then
      slot.cdText:SetText("")
      slot._lastText = ""
    end
  else
    if slot._lastState ~= "missing" then
      slot.icon:SetVertexColor(0.4, 0.4, 0.4, 1)
      Nock.UI.SetIconHighlight(slot, nil)
      Nock.UI.SetIconAlertGlow(slot, false)
      slot._lastState = "missing"
    end
    if slot._lastText ~= "" then
      slot.cdText:SetText("")
      slot._lastText = ""
    end
  end
end
