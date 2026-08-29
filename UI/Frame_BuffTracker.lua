-- UI/Frame_BuffTracker.lua
-- Two draggable buff-grid panels (player + pet). Each panel is a column-major
-- grid that grows downward as more buffs appear. Uses Nock.UI.CreateIconSlot
-- so the per-slot Cooldown frame is OmniCC-friendly out of the box; the
-- fallback cdText is only shown when no external CD-text addon is installed.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local BuffTrackerView = Nock:NewModule("BuffTrackerView", "AceEvent-3.0")
local C = Nock.Constants

local EXTERNAL_CD_ADDONS = { "OmniCC", "tullaCC", "ncCooldown" }
local MAX_SLOTS = 40
-- Overlap adjacent cells by 1px so their black borders merge into a single
-- shared grid line (tight, contiguous — matches the reference WA).
local CELL_OVERLAP = 1
local PANEL_PAD = 2

local HEADER_HEIGHT = 14
local HEADER_GAP    = 2   -- gap between header baseline and first row of icons
local HEADER_FONT   = "Numen"
local HEADER_SIZE   = 11
local HEADER_STYLE  = "THICKOUTLINE"

local SOLID_TEX = "Interface\\Buttons\\WHITE8X8"

-- "Missing" highlight reuses the configurable next-action effect
-- (Rotation → Next-action highlight: pixel ring / spell-proc / etc.) so the
-- whole addon shares one "pay attention to this" visual language. Passes
-- thickness 1 — these icons are small, so the default 2px ring is too bold.
local function setMissingHighlight(slot, on)
  Nock.UI.SetIconNextHighlight(slot, on, nil, 1)
end

-- Buff-tracker slots always use a thin 1px black border, regardless of the
-- global iconBorder LSM setting. Called at slot creation AND any time the
-- shared RefreshMedia would otherwise reset us to the LSM edge.
local function applyMinimalBorder(slot)
  slot:SetBackdrop({
    bgFile   = SOLID_TEX,
    edgeFile = SOLID_TEX,
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  slot:SetBackdropColor(0, 0, 0, 0.85)
  slot:SetBackdropBorderColor(0, 0, 0, 1)
  if slot.icon then
    slot.icon:ClearAllPoints()
    slot.icon:SetPoint("TOPLEFT",     slot, "TOPLEFT",      1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1,  1)
  end
end

local function profileGet(key, fallback)
  local p = Nock.db and Nock.db.profile
  if p and p[key] ~= nil then return p[key] end
  return fallback
end

local function isEnabled()
  return profileGet("buffTrackerEnabled", true) and true or false
end
local function cols()           return profileGet("buffTrackerCols", 5) end
local function iconSize()       return profileGet("buffTrackerIconSize", 24) end

-- Per-panel config helpers, parameterised by suffix ("Player" / "Pet").
local function isPanelEnabled(which) return profileGet("buffTracker" .. which .. "Enabled", true) and true or false end
local function isPanelLocked() return Nock.IsLocked() end
local function panelPosition(which)
  local p = profileGet("buffTracker" .. which .. "Position", nil)
  if p then return p end
  if which == "Player" then return { point = "CENTER", relPoint = "CENTER", x = -100, y = 100 } end
  return { point = "CENTER", relPoint = "CENTER", x = 100, y = 100 }
end

-- Raid takes precedence over party (dungeon group). Returns nil when solo.
-- (IsInGroup/IsInRaid are unreliable on this client, so also accept GetNum*.)
local function groupChannel()
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
  if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
  return nil
end

-- Battle Shout is the exception: party-scoped (only your subgroup's warrior
-- matters), so it always pings PARTY — never the whole raid. In a raid,
-- "PARTY" still routes to your subgroup. nil = solo.
local function partyChannel()
  if IsInGroup and IsInGroup() then return "PARTY" end
  if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "PARTY" end
  return nil
end

-- Channel for a given buff entry key: Battle Shout → party only; the rest
-- keep the raid→party dungeon logic.
local function channelForBuff(buffKey)
  if buffKey == "shout" then return partyChannel() end
  return groupChannel()
end

-- Light anti-spam: same unit+buff can't re-announce within 3s (double clicks).
local _lastAnnounce = {}
local function announceMissing(unitKind, label, buffKey)
  if not label then return end
  local key = (unitKind or "") .. ":" .. label
  local now = GetTime()
  if _lastAnnounce[key] and (now - _lastAnnounce[key]) < 3 then return end
  _lastAnnounce[key] = now

  local msg
  if unitKind == "pet" then
    local petName = (UnitName and UnitName("pet")) or "Pet"
    msg = ("Pet %s is missing %s, please re-apply."):format(petName, label)
  else
    local pName = (UnitName and UnitName("player")) or "I"
    msg = ("%s is missing %s, please re-apply."):format(pName, label)
  end

  local ch = channelForBuff(buffKey)
  if ch and SendChatMessage then
    SendChatMessage(msg, ch)
  else
    Nock:Print(msg)  -- solo fallback so the click isn't a silent no-op
  end
end

-- ---------------------------------------------------------------------------
-- Panel builder. Each panel is a frame with a fixed pool of slots that we
-- show/hide based on the current buff count, and re-anchor in grid order each
-- Refresh tick. unitKind = "player" / "pet" for the click-to-announce message.
-- ---------------------------------------------------------------------------
local function buildPanel(name, headerText, unitKind)
  local panel = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:RegisterForDrag("LeftButton")
  Nock.UI.ApplyUserPanelStyle(panel, "buffTracker")
  panel:Hide()

  -- Header at the top — Numen bold uppercase, white. Matches the MD tracker.
  -- Routed through RegisterHeaderFontString so the named LSM font re-applies
  -- if its SharedMedia plugin registers after us (cold-load race).
  local header = panel:CreateFontString(nil, "OVERLAY")
  Nock.UI.RegisterHeaderFontString(header, HEADER_FONT, HEADER_SIZE, HEADER_STYLE)
  header:SetPoint("TOPLEFT",  panel, "TOPLEFT",   PANEL_PAD, -PANEL_PAD)
  header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PANEL_PAD, -PANEL_PAD)
  header:SetHeight(HEADER_HEIGHT)
  header:SetJustifyH("CENTER")
  header:SetJustifyV("MIDDLE")
  header:SetTextColor(1, 1, 1, 1)
  header:SetText(headerText)
  panel.header = header

  local slots = {}
  for i = 1, MAX_SLOTS do
    local slot = Nock.UI.CreateIconSlot(panel, name .. "Slot" .. i, iconSize())
    applyMinimalBorder(slot)   -- override the global LSM border with 1px black
    -- Buff-DURATION style swipe: icon starts fully visible and the dark wedge
    -- GROWS as the buff runs out (visible → dark). Default Cooldown direction
    -- is the ability style (dark → visible); reverse it. Scoped to these
    -- slots only — the shared cooldown grid keeps the default direction.
    if slot.cooldown and slot.cooldown.SetReverse then
      slot.cooldown:SetReverse(true)
    end
    slot:Hide()
    slot._lastIcon = nil
    slot._lastCdStart = 0
    slot._lastCdDur   = 0
    slot._lastCount   = ""
    slot._unit        = unitKind
    slot._present     = false
    -- Click a MISSING buff → announce to raid/party. Mouse is only enabled
    -- while the panel is locked (see ApplyLock), so dragging still works
    -- when unlocked.
    slot:SetScript("OnMouseUp", function(s, button)
      if button ~= "LeftButton" then return end
      if s._present then return end
      -- Self-applied (Kibler / scrolls) → that's on you, don't ask the raid.
      if s._selfApplied then return end
      announceMissing(s._unit, s._buffLabel, s._buffKey)
    end)
    slots[i] = slot
  end

  return panel, slots
end

function BuffTrackerView:OnInitialize()
  self.playerPanel, self.playerSlots = buildPanel("NockBuffsPlayer", "PLAYER", "player")
  self.petPanel,    self.petSlots    = buildPanel("NockBuffsPet",    "PET",    "pet")

  -- Wire each panel's drag handler to save back into its own position key.
  local function wireDrag(panel, which)
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local point, _, relPoint, x, y = self:GetPoint()
      Nock.db.profile["buffTracker" .. which .. "Position"] =
        { point = point, relPoint = relPoint, x = x, y = y }
    end)
    Nock.UI.RegisterNudgeable(panel, {
      label   = which == "Pet" and "Pet Buffs" or "Player Buffs",
      get     = function() return Nock.db.profile["buffTracker" .. which .. "Position"] end,
      set     = function(pos)
        Nock.db.profile["buffTracker" .. which .. "Position"] = pos
        BuffTrackerView:ApplyPosition()
      end,
      default = function() return Nock.Defaults.profile["buffTracker" .. which .. "Position"] end,
    })
  end
  wireDrag(self.playerPanel, "Player")
  wireDrag(self.petPanel,    "Pet")

  self:ApplyPosition()
  self:ApplyLock()

  self:RegisterMessage("NOCK_VISUALS_CHANGED",      "OnVisualsChanged")
  self:RegisterMessage("NOCK_LOCK_CHANGED",         "ApplyLock")
  self:RegisterMessage("NOCK_BUFFTRACKER_POSRESET", "ApplyPosition")
  self:RegisterMessage("NOCK_POSITION_RESET",       "ApplyPosition")  -- profile switch
  self:RegisterEvent("PLAYER_LOGIN",                "ApplyExternalCdAddon")
  self:RegisterEvent("PLAYER_ENTERING_WORLD",       "ApplyExternalCdAddon")
end

function BuffTrackerView:ApplyPosition()
  for _, info in ipairs({
    { panel = self.playerPanel, which = "Player" },
    { panel = self.petPanel,    which = "Pet"    },
  }) do
    local p = panelPosition(info.which)
    info.panel:ClearAllPoints()
    info.panel:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
  end
end

function BuffTrackerView:ApplyLock()
  for _, info in ipairs({
    { panel = self.playerPanel, which = "Player", slots = self.playerSlots },
    { panel = self.petPanel,    which = "Pet",    slots = self.petSlots    },
  }) do
    local locked = isPanelLocked()
    -- Panel mouse drives dragging (only when unlocked); slot mouse drives the
    -- click-to-announce (only when locked) so the two never fight.
    info.panel:EnableMouse(not locked)
    for _, s in ipairs(info.slots) do s:EnableMouse(locked) end
  end
  self:ApplyStyle()
end

-- User Background block (buffTracker* keys), shared by BOTH grids; the green
-- unlock border wins while the panels are draggable so they stay findable.
function BuffTrackerView:ApplyStyle()
  local locked = isPanelLocked()
  for _, panel in ipairs({ self.playerPanel, self.petPanel }) do
    Nock.UI.ApplyUserPanelStyle(panel, "buffTracker")
    if not locked then
      panel:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
    end
  end
end

function BuffTrackerView:OnVisualsChanged()
  -- Slot icons/sizes can change via the slider; resize each pre-made slot
  -- AND re-apply our 1px black border (Widgets.RefreshMedia would otherwise
  -- have just reset us to whatever global LSM iconBorder is selected).
  local sz = iconSize()
  for _, slot in ipairs(self.playerSlots) do slot:SetSize(sz, sz); applyMinimalBorder(slot) end
  for _, slot in ipairs(self.petSlots)    do slot:SetSize(sz, sz); applyMinimalBorder(slot) end
  self:ApplyStyle()
end

function BuffTrackerView:ApplyExternalCdAddon()
  if self._cdAddonApplied then return end
  self._cdAddonApplied = true
  local check = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  local has = false
  if check then
    for _, name in ipairs(EXTERNAL_CD_ADDONS) do
      if check(name) then has = true; break end
    end
  end
  -- When OmniCC (or similar) is loaded, hide our fallback cdText so we don't
  -- double-paint. Leave noCooldownCount nil (default) so OmniCC can paint.
  local function applyToList(slots)
    for _, slot in ipairs(slots) do
      if has then
        slot.cooldown.noCooldownCount = nil
        slot.cdText:Hide()
      else
        slot.cooldown.noCooldownCount = true
        slot.cdText:Show()
      end
    end
  end
  applyToList(self.playerSlots)
  applyToList(self.petSlots)
end

-- ---------------------------------------------------------------------------
-- Refresh — fill one panel's grid from a curated buff list. Each entry knows
-- whether the buff is *present* on the unit; missing ones are desaturated +
-- greyed (matches the reference WA), present ones are full colour and drive
-- the OmniCC swipe.
-- ---------------------------------------------------------------------------
local function refreshPanel(panel, slots, list, colCount, sz)
  if #list == 0 then
    if panel:IsShown() then panel:Hide() end
    return
  end

  local n = math.min(#list, MAX_SLOTS)
  local rows = math.ceil(n / colCount)
  -- Top inset includes the header + a small gap before the first row of icons.
  local topInset = PANEL_PAD + HEADER_HEIGHT + HEADER_GAP
  local stride   = sz - CELL_OVERLAP   -- cells overlap so borders merge
  panel:SetSize(
    PANEL_PAD * 2 + colCount * sz - (colCount - 1) * CELL_OVERLAP,
    topInset + rows * sz - (rows - 1) * CELL_OVERLAP + PANEL_PAD
  )

  local now = GetTime()
  for i = 1, MAX_SLOTS do
    local slot = slots[i]
    local b = list[i]
    if b then
      local col = (i - 1) % colCount
      local row = math.floor((i - 1) / colCount)
      slot:ClearAllPoints()
      slot:SetPoint("TOPLEFT", panel, "TOPLEFT",
        PANEL_PAD + col * stride,
        -(topInset + row * stride))

      -- Live state for the click-to-announce handler (NOT diff-guarded —
      -- _lastPresent gets cleared on icon swap so it can't be relied on).
      slot._present     = b.present
      slot._buffLabel   = b.label
      slot._buffKey     = b.key
      slot._selfApplied = b.selfApplied

      if b.icon and b.icon ~= slot._lastIcon then
        slot.icon:SetTexture(b.icon)
        slot._lastIcon = b.icon
        -- A texture swap may reset vertex/desaturation; force re-apply.
        slot._lastPresent = nil
      end

      -- Present vs missing visual: greyscale + dim + pulse when the buff
      -- isn't on us; full colour + steady when it is.
      if b.present ~= slot._lastPresent then
        if b.present then
          slot.icon:SetVertexColor(1, 1, 1, 1)
          if slot.icon.SetDesaturated then slot.icon:SetDesaturated(false) end
          setMissingHighlight(slot, false)
        else
          slot.icon:SetVertexColor(0.55, 0.55, 0.55, 1)
          if slot.icon.SetDesaturated then slot.icon:SetDesaturated(true) end
          setMissingHighlight(slot, true)
        end
        slot._lastPresent = b.present
      end

      -- Cooldown swipe — only when present AND the buff actually carries a
      -- duration. Permanent auras (Trueshot, etc.) have duration = 0 and just
      -- show the icon in colour with no swipe.
      if b.present and b.duration > 0 and b.expirationTime > now then
        local start = b.expirationTime - b.duration
        if start ~= slot._lastCdStart or b.duration ~= slot._lastCdDur then
          slot.cooldown:SetCooldown(start, b.duration)
          slot._lastCdStart = start
          slot._lastCdDur   = b.duration
        end
      elseif (slot._lastCdStart or 0) ~= 0 then
        slot.cooldown:Clear()
        slot._lastCdStart = 0
        slot._lastCdDur   = 0
      end

      local countTxt = (b.count and b.count > 1) and tostring(b.count) or ""
      if countTxt ~= slot._lastCount then
        slot.countText:SetText(countTxt)
        slot._lastCount = countTxt
      end

      if not slot:IsShown() then slot:Show() end
    else
      if slot:IsShown() then
        setMissingHighlight(slot, false)  -- stop the glow on a hidden frame
        slot._lastPresent = nil           -- force re-evaluation when reused
        slot:Hide()
      end
    end
  end

  if not panel:IsShown() then panel:Show() end
end

-- Slow lane (Core:Tick): a raid-buff checklist grid. Nothing here animates —
-- the icons only change when a buff is gained/lost — so rendering it once per
-- frame was pure waste. Matches BuffTracker's engine cadence.
BuffTrackerView.refreshInterval = 0.1

function BuffTrackerView:Refresh(state)
  -- Deliberately NOT gated on React mode: the ReactBuffs row covers procs and
  -- utility auras, but the player/pet buff tracker (food, scrolls, tracked
  -- consumables) stays useful alongside it — user call.
  if not isEnabled() then
    if self.playerPanel:IsShown() then self.playerPanel:Hide() end
    if self.petPanel:IsShown()    then self.petPanel:Hide()    end
    return
  end

  -- "Hide out of combat" (General -> Visibility) puts both panels away while
  -- RESTED — an inn or a city — never merely out of combat (Core/State.lua).
  local p = Nock.db and Nock.db.profile
  if Nock.RestedHideApplies(p, IsResting and IsResting(), state) then
    if self.playerPanel:IsShown() then self.playerPanel:Hide() end
    if self.petPanel:IsShown()    then self.petPanel:Hide()    end
    return
  end

  local colCount = cols()
  local sz       = iconSize()
  local bt       = state.bufftracker or { player = {}, pet = {} }

  if isPanelEnabled("Player") then
    refreshPanel(self.playerPanel, self.playerSlots, bt.player, colCount, sz)
  else
    if self.playerPanel:IsShown() then self.playerPanel:Hide() end
  end

  if isPanelEnabled("Pet") and UnitExists("pet") then
    refreshPanel(self.petPanel, self.petSlots, bt.pet, colCount, sz)
  else
    if self.petPanel:IsShown() then self.petPanel:Hide() end
  end
end
