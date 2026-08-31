-- UI/Frame_Cooldowns.lua
-- Renders state.cooldowns into a centered grid. Partial bottom row is centered.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local CooldownsView = Nock:NewModule("CooldownsView", "AceEvent-3.0")
local C = Nock.Constants

-- Cooldown-timer addons we'll defer to instead of painting our own cdText.
-- First match wins. Addons load alphabetically, so OmniCC ("O") loads after
-- Nock ("N") — detection has to wait until PLAYER_LOGIN.
local EXTERNAL_CD_ADDONS = { "OmniCC", "tullaCC", "ncCooldown" }

----------------------------------------------------------------------------
-- Drums "players in range" badge (top-left of the Drums icon).
--
-- Leatherworking drums buff the PARTY (your subgroup) only — never the full
-- raid, regardless of raid size. So the count is always subgroup-scoped: at
-- most you + 4. In a 5-man that's party1-4; in a raid those tokens don't
-- resolve, so same-subgroup members are found via the raid roster.
--
-- Radius auto-detects which drum is carried: greater drums → 40 yd via
-- UnitInRange (purpose-built group-assist check); else Drums of Battle →
-- ~8 yd, which has no exact native probe so the nearest band
-- (CheckInteractDistance idx 3 ≈ 10 yd) is used. Friendly players only.
----------------------------------------------------------------------------
local D = C.DRUMS

-- Static unit tables, built once (avoid per-tick "raid"..i concat).
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }
local RAID_UNITS  = {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end

local function drumItemCount(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
  if GetItemCount then return GetItemCount(id) or 0 end
  return 0
end

local function unitInDrumRange(unit, greater)
  if greater then
    if UnitInRange then return (UnitInRange(unit)) and true or false end
    if CheckInteractDistance then return CheckInteractDistance(unit, 1) and true or false end
    return false
  end
  if CheckInteractDistance then return CheckInteractDistance(unit, 3) and true or false end
  return false
end

local function unitCountsForDrum(u, greater)
  return UnitExists(u) and UnitIsPlayer(u) and not UnitIsUnit(u, "player")
     and UnitIsConnected(u) and not UnitIsDeadOrGhost(u)
     and unitInDrumRange(u, greater)
end

-- Throttled: positions move continuously but an at-a-glance badge doesn't
-- need a 30 Hz group sweep.
local DRUM_SCAN_INTERVAL = 0.25
local _drumScanAt, _drumScanText = 0, ""

local function scanDrumText()
  local hasGreater = drumItemCount(D.GREATER_ITEM) > 0
  local hasBattle  = drumItemCount(D.BATTLE_ITEM)  > 0
  if not (hasGreater or hasBattle) then return "" end

  local greater = hasGreater    -- prefer the wider radius if that drum is carried
  local n = 1                   -- you always count: in range of your own drum (min 1)

  local numRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  if numRaid > 0 then
    -- In a raid the drum still only buffs your SUBGROUP. party1-4 don't
    -- resolve here, so find members sharing the player's subgroup via the
    -- raid roster (RAID_UNITS[i] index == GetRaidRosterInfo index).
    local mySub
    if GetRaidRosterInfo then
      for i = 1, numRaid do
        if UnitIsUnit(RAID_UNITS[i], "player") then
          mySub = select(3, GetRaidRosterInfo(i))
          break
        end
      end
      if mySub then
        for i = 1, numRaid do
          local u = RAID_UNITS[i]
          if select(3, GetRaidRosterInfo(i)) == mySub
             and unitCountsForDrum(u, greater) then
            n = n + 1
          end
        end
      end
    end
  else
    -- Solo or a 5-man party.
    for _, u in ipairs(PARTY_UNITS) do
      if unitCountsForDrum(u, greater) then n = n + 1 end
    end
  end

  return tostring(n)
end

local function drumInRangeText()
  local now = GetTime()
  if now - _drumScanAt >= DRUM_SCAN_INTERVAL then
    _drumScanAt   = now
    _drumScanText = scanDrumText()
  end
  return _drumScanText
end

local function formatCD(remaining)
  if remaining <= 0 then return "" end
  if remaining < 10 then return ("%.1f"):format(remaining) end
  if remaining < 90 then return ("%d"):format(math.ceil(remaining)) end
  return ("%dm"):format(math.floor(remaining / 60))
end

local function visualState(cd)
  if cd.procActive then return "proc" end
  if cd.ready then return "ready" end
  return "cd"
end

function CooldownsView:OnInitialize()
  local parent = Nock.parentFrame
  local container = CreateFrame("Frame", "NockCooldowns", parent)
  self.frame  = container
  self._pool  = {}     -- reused icon slots (frames can't be destroyed → pool)
  self.slots  = self._pool
  self:Rebuild()

  -- Rebuild whenever the grid config changes (cols/rows/order/disabled/custom
  -- all funnel through NOCK_VISUALS_CHANGED via the options setters).
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "Rebuild")

  -- Defer integration check until other addons have loaded. PLAYER_LOGIN
  -- covers initial login; PLAYER_ENTERING_WORLD covers /reload (login doesn't
  -- re-fire). One-shot guard so only the first fire does work.
  self:RegisterEvent("PLAYER_LOGIN",         "ApplyExternalCdAddon")
  self:RegisterEvent("PLAYER_ENTERING_WORLD","ApplyExternalCdAddon")
end

-- (Re)lay out the grid from the shared builder: profile-ordered, enabled,
-- capped to cols*rows. Slots are pooled; surplus ones are hidden, not freed.
function CooldownsView:Rebuild()
  local mod      = Nock:GetModule("Cooldowns", true)
  local entries  = (mod and mod:GetGridEntries()) or {}
  local cols, rows
  if mod then cols, rows = mod:GetDims() end
  cols = cols or C.COOLDOWN_COLS
  rows = rows or C.COOLDOWN_ROWS

  -- Icon size auto-scales so the grid spans exactly the HUD inner width and
  -- stays in-grid as columns grow (see Cooldowns:GetIconSize).
  local iconSize = (mod and mod:GetIconSize()) or C.DIM.COOLDOWN_ICON
  local gap      = C.DIM.INNER_GAP
  local stride   = iconSize + gap
  local totalWidth  = cols * iconSize + (cols - 1) * gap
  local totalHeight = rows * iconSize + (rows - 1) * gap
  self.frame:SetSize(math.max(1, totalWidth), math.max(1, totalHeight))

  -- Release every pooled slot first; only the ones we re-place get an entry.
  for _, s in ipairs(self._pool) do
    s._entry = nil
    s:Hide()
  end

  local n = #entries
  for i = 1, n do
    local row = math.floor((i - 1) / cols)
    local col = (i - 1) % cols
    local itemsInRow = math.min(cols, n - row * cols)
    local rowWidth   = itemsInRow * iconSize + math.max(0, itemsInRow - 1) * gap
    local rowOffset  = (totalWidth - rowWidth) / 2

    local slot = self._pool[i]
    if not slot then
      slot = Nock.UI.CreateIconSlot(self.frame, "NockCDSlot" .. i, iconSize)
      self._pool[i] = slot
      self:ApplyExternalCdAddonToSlot(slot)
    end
    -- Pooled slots may have been built at a different icon size (cols changed).
    slot:SetSize(iconSize, iconSize)
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT", self.frame, "TOPLEFT", rowOffset + col * stride, -row * stride)
    slot._entry          = entries[i]
    -- Per-HUD active-highlight geometry (thickness + contained/overflow);
    -- style + color are Refresh's job.
    local p = Nock.db.profile
    Nock.UI.ApplyGlowStyle(slot, p.cooldownActiveSize or 3,
                           p.cooldownActiveFit == "contained")
    Nock.UI.SetIconProcGlow(slot, false)
    slot._lastIcon       = nil
    slot._lastText       = ""
    slot._lastVisState   = nil
    slot._lastCdStart    = 0
    slot._lastCdDuration = 0
    slot._lastCount      = nil
    slot._lastTop        = nil
    slot.cdText:SetText("")
    slot.countText:SetText("")
    slot.topText:SetText("")
    Nock.UI.SetIconHighlight(slot, nil)
    slot:Show()
  end
end

local function findExternalCdAddon()
  local check = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if not check then return nil end
  for _, name in ipairs(EXTERNAL_CD_ADDONS) do
    if check(name) then return name end
  end
  return nil
end

function CooldownsView:ApplyExternalCdAddonToSlot(slot)
  if self.externalCdAddon then
    slot.cooldown.noCooldownCount = nil  -- let the external addon paint
    slot.cdText:Hide()
  else
    slot.cooldown.noCooldownCount = true
    slot.cdText:Show()
  end
end

function CooldownsView:ApplyExternalCdAddon()
  if self._cdAddonApplied then return end
  self._cdAddonApplied = true
  self.externalCdAddon = findExternalCdAddon()
  for _, slot in ipairs(self._pool) do
    self:ApplyExternalCdAddonToSlot(slot)
  end
end

function CooldownsView:Refresh(state)
  -- Hidden (React mode, showCooldowns off, hideOoc): nothing to paint.
  if not self.frame:IsVisible() then return end
  for _, slot in ipairs(self.slots) do
    local entry = slot._entry
    if entry then
      local cd = state.cooldowns[entry.key]
      if cd then
        -- While the slot's tracked buff is up AND we know its icon/duration,
        -- pivot the slot to show the buff (icon + remaining + matching swipe).
        -- When the buff ends, the slot reverts to the source spell/item's icon
        -- and the source's cooldown (if any) is shown instead.
        local showBuff  = cd.procActive and cd.buffIcon
                        and cd.buffRemaining and cd.buffRemaining > 0
        local dispIcon  = showBuff and cd.buffIcon      or cd.icon
        local dispStart = showBuff and cd.buffStartTime or cd.startTime
        local dispDur   = showBuff and cd.buffDuration  or cd.duration
        local dispRem   = showBuff and cd.buffRemaining or cd.remaining

        if dispIcon and dispIcon ~= slot._lastIcon then
          slot.icon:SetTexture(dispIcon)
          slot._lastIcon = dispIcon
        end

        local vis = visualState(cd)
        -- Settings preview: light every tile; suspended in combat.
        if Nock.UI.activePreview
           and not (InCombatLockdown and InCombatLockdown()) then
          vis = "proc"
        end
        local txt = (dispRem and dispRem > 0) and formatCD(dispRem) or ""

        if vis ~= slot._lastVisState then
          slot.icon:SetVertexColor(1, 1, 1, 1)
          if vis == "proc" then
            -- Per-HUD active-highlight style (cooldownActive*): border with
            -- the profile color, the action-button overlay, or nothing.
            local p = Nock.db.profile
            local style = p.cooldownActiveStyle or "border"
            Nock.UI.SetIconHighlight(slot, (style == "border")
              and (p.cooldownActiveColor or C.COLORS.PROC_GLOW) or nil)
            Nock.UI.SetIconProcGlow(slot, style == "glow", nil)
          else
            Nock.UI.SetIconHighlight(slot, nil)
            Nock.UI.SetIconProcGlow(slot, false)
          end
          slot._lastVisState = vis
        end

        if txt ~= slot._lastText then
          slot.cdText:SetText(txt)
          slot._lastText = txt
        end

        -- Swipe — driven by the same (dispStart, dispDur) pair as the text so
        -- they always agree. Only re-fire SetCooldown when start or duration
        -- actually changes; otherwise the animation would restart every tick.
        if dispDur and dispDur > 0 and dispRem and dispRem > 0 then
          if dispStart ~= slot._lastCdStart or dispDur ~= slot._lastCdDuration then
            slot.cooldown:SetCooldown(dispStart, dispDur)
            slot._lastCdStart    = dispStart
            slot._lastCdDuration = dispDur
          end
        elseif slot._lastCdStart ~= 0 then
          slot.cooldown:Clear()
          slot._lastCdStart    = 0
          slot._lastCdDuration = 0
        end

        local countTxt = (cd.count and cd.count > 0) and tostring(cd.count) or ""
        if countTxt ~= slot._lastCount then
          slot.countText:SetText(countTxt)
          slot._lastCount = countTxt
        end

        -- Drums-only: friendly players within the drum's range, top-left.
        if entry.key == "Drums" then
          local topTxt = drumInRangeText()
          if topTxt ~= slot._lastTop then
            slot.topText:SetText(topTxt)
            slot._lastTop = topTxt
          end
        end
      end
    end
  end
end
