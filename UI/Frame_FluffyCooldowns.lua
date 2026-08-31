-- UI/Frame_FluffyCooldowns.lua
-- FluffyHUD cooldown row: ONE stretch row of icon slots (the React grid's
-- row-1 look) welded UNDER the fluffy cluster — it grows downward and never
-- moves the stack. Opt-in (fluffyShowGrid).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local FluffyCooldownsView = Nock:NewModule("FluffyCooldownsView", "AceEvent-3.0")
local C = Nock.Constants

-- Same external cooldown-text integration as both other grids: defer the CD
-- numbers to OmniCC & co. when present (detection must wait until login —
-- addons load alphabetically, so OmniCC loads after Nock).
local EXTERNAL_CD_ADDONS = { "OmniCC", "tullaCC", "ncCooldown" }

local function profile()
  return (Nock.db and Nock.db.profile) or {}
end

-- Fixed flat skin, immune to the profile iconBorder/LSM settings (slots opt
-- out via _fixedBorder — see Nock.UI.ApplyIconBorder). Slots overlap their
-- 1px borders so adjacent icons share a single black seam.
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local GAP = -1
local ROW_H = 32
local SLOT_BG = { 0.08, 0.08, 0.08, 0.90 }

local function applyFixedSlotSkin(slot)
  slot._fixedBorder = true
  slot:SetBackdrop({
    bgFile   = WHITE8X8,
    edgeFile = WHITE8X8,
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  slot:SetBackdropColor(unpack(SLOT_BG))
  slot:SetBackdropBorderColor(0, 0, 0, 1)
  slot.icon:ClearAllPoints()
  slot.icon:SetPoint("TOPLEFT",     slot, "TOPLEFT",     1, -1)
  slot.icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
end

local function formatCD(remaining)
  if remaining <= 0 then return "" end
  if remaining < 10 then return ("%.1f"):format(remaining) end
  if remaining < 90 then return ("%d"):format(math.ceil(remaining)) end
  return ("%dm"):format(math.floor(remaining / 60))
end

-- Effective key list: the user's fluffyCdKeys override (a flat list) or the
-- seeded C.FLUFFY_CD_KEYS. Every reader of membership goes through this.
local function rowKeysList(p)
  local custom = p.fluffyCdKeys
  if type(custom) == "table" then return custom end
  return C.FLUFFY_CD_KEYS
end

function FluffyCooldownsView:OnInitialize()
  local container = CreateFrame("Frame", "NockFluffyCooldowns", Nock.parentFrame)
  self.frame = container
  self._pool = {}
  self:Seat()
  self:Rebuild()
  container:Hide()  -- HUD:ApplyRowVisibility shows it in fluffy mode + fluffyShowGrid

  self:RegisterMessage("NOCK_VISUALS_CHANGED", "Rebuild")
  self:RegisterEvent("PLAYER_LOGIN",          "ApplyExternalCdAddon")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyExternalCdAddon")
end

-- The row hangs off the CLUSTER, not the HUD cascade (user gate, 2026-08-31:
-- enabling it must grow DOWNWARD — as a cascade row it changed the HUD box
-- height and the saved anchor pushed the whole stack up). Welded across the
-- cluster's bottom edge with the shared -1px seam and parented to it, so
-- fluffyScale and the cluster's width are inherited for free and the HUD's
-- row pass never sees this frame's height.
function FluffyCooldownsView:Seat()
  local m = Nock:GetModule("FluffyCluster", true)
  local host = (m and m.frame) or Nock.parentFrame
  local f = self.frame
  if f:GetParent() ~= host then f:SetParent(host) end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT",  host, "BOTTOMLEFT",  0, 1)
  f:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, 1)
end

-- ONE stretch row over fluffyWidth: n tiles overlapping (n-1) 1px seams.
-- Membership: fluffyCdKeys (or the seed) filtered by fluffyCooldownDisabled
-- and Cooldowns:IsEntryAvailable (the Spec slot is out while its spell is
-- unknown; the engine sends VISUALS_CHANGED when that flips). Returns the
-- ReactCooldowns RowsGeometry shape — one row — so a second row later is an
-- extension, not a rewrite.
function FluffyCooldownsView:RowsGeometry()
  local p = profile()
  local w = tonumber(p.fluffyWidth) or 320
  local disabled = p.fluffyCooldownDisabled or {}
  local mod = Nock:GetModule("Cooldowns", true)

  local entries = {}
  for _, key in ipairs(rowKeysList(p)) do
    if not disabled[key]
       and (not (mod and mod.IsEntryAvailable) or mod:IsEntryAvailable(key)) then
      local e = mod and mod.GetEntry and mod:GetEntry(key)
      if e then entries[#entries + 1] = e end
    end
  end

  local rows, totalH = {}, 0
  local n = #entries
  if n > 0 then
    rows[1] = { entries = entries, w = (w + (n - 1)) / n, h = ROW_H, y = 0 }
    totalH = ROW_H
  end
  return rows, w, math.max(totalH, 1)
end

-- Logical (unscaled) height, for HUD's LAYOUT height fn.
function FluffyCooldownsView:ContentHeight()
  local _, _, h = self:RowsGeometry()
  return h
end

-- (Re)place the pooled slots. Surplus slots are hidden, never freed. The
-- weld's two points own the width; only the height is ours to set.
function FluffyCooldownsView:Rebuild()
  local rows, w, totalH = self:RowsGeometry()
  local p = profile()
  self.frame:SetHeight(totalH)

  for _, s in ipairs(self._pool) do
    s._entry = nil
    s:Hide()
  end

  local i = 0
  for _, row in ipairs(rows) do
    local n = #row.entries
    local rowW = n * row.w + (n - 1) * GAP
    local x0 = (w - rowW) / 2
    for col, entry in ipairs(row.entries) do
      i = i + 1
      local slot = self._pool[i]
      if not slot then
        slot = Nock.UI.CreateIconSlot(self.frame, "NockFluffyCDSlot" .. i, row.h, true)
        applyFixedSlotSkin(slot)
        self._pool[i] = slot
        self:ApplyExternalCdAddonToSlot(slot)
      end
      slot:SetSize(row.w, row.h)
      slot:ClearAllPoints()
      slot:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
                    x0 + (col - 1) * (row.w + GAP), -row.y)
      -- Wider-than-tall tiles crop the texture vertically instead of
      -- stretching it — the "zoomed" icon look, same math as the React grid.
      local ySpan = 0.42 * math.min(1, row.h / row.w)
      slot.icon:SetTexCoord(0.08, 0.92, 0.5 - ySpan, 0.5 + ySpan)
      slot._entry          = entry
      -- Per-HUD active-highlight geometry (thickness + contained/overflow);
      -- style + color are the Refresh look's job.
      Nock.UI.ApplyGlowStyle(slot, p.fluffyActiveSize or 3,
                             p.fluffyActiveFit == "contained")
      slot._lastIcon       = nil
      slot._lastText       = ""
      slot._lastLook       = nil
      Nock.UI.SetIconProcGlow(slot, false)
      slot._lastCdStart    = 0
      slot._lastCdDuration = 0
      slot._lastCount      = nil
      slot.cdText:SetText("")
      slot.countText:SetText("")
      slot.topText:SetText("")
      Nock.UI.SetIconHighlight(slot, nil)
      slot:Show()
    end
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

function FluffyCooldownsView:ApplyExternalCdAddonToSlot(slot)
  if self.externalCdAddon then
    slot.cooldown.noCooldownCount = nil  -- let the external addon paint
    slot.cdText:Hide()
  else
    slot.cooldown.noCooldownCount = true
    slot.cdText:Show()
  end
end

function FluffyCooldownsView:ApplyExternalCdAddon()
  if self._cdAddonApplied then return end
  self._cdAddonApplied = true
  self.externalCdAddon = findExternalCdAddon()
  for _, slot in ipairs(self._pool) do
    self:ApplyExternalCdAddonToSlot(slot)
  end
end

-- Slot look via Nock.UI.ReactSlotLook (pure, tested) — the same KC proc glow
-- and range/dim/mana tints as the React grid, behind the SAME option keys
-- (reactKcProcGlow / reactRangeTint / reactTileDim / reactManaTint): they are
-- grid BEHAVIOR flags, not React geometry, and the FluffyHUD Grid tab
-- mirrors them (one key, two homes — the repo's shared-settings idiom).
local LOOK = { procGlow = false, tint = "off", whenActive = false, dim = false, manaTint = false }
local RES  = {}
local TINT = { red = { 0.77, 0.12, 0.23, 1 }, blue = { 0.33, 0.54, 1, 1 } }

function FluffyCooldownsView:Refresh(state)
  if not self.frame:IsShown() then return end
  local p = profile()

  for _, slot in ipairs(self._pool) do
    local entry = slot._entry
    if entry then
      local cd = state.cooldowns[entry.key]
      if cd then
        -- Buff pivot (same as both other grids): while the tracked buff is up
        -- the slot shows the buff icon + remaining + matching swipe.
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

        LOOK.procGlow    = (entry.key == "KC" and p.reactKcProcGlow) and true or false
        LOOK.activeStyle = p.fluffyActiveStyle
        -- Settings preview: light every tile; suspended in combat.
        LOOK.preview     = (Nock.UI.activePreview
                            and not (InCombatLockdown and InCombatLockdown())) or false
        LOOK.tint        = p.reactRangeTint or "off"
        LOOK.dim         = p.reactTileDim and true or false
        LOOK.manaTint    = p.reactManaTint and true or false
        local so = state.target.spellOut
        local r  = Nock.UI.ReactSlotLook(cd, so and so[entry.key], LOOK, RES)
        local lk = Nock.UI.ReactLookKey(r)
        if lk ~= slot._lastLook then
          local c = r.tint and TINT[r.tint]
          if c then slot.icon:SetVertexColor(c[1], c[2], c[3], c[4])
          else slot.icon:SetVertexColor(1, 1, 1, 1) end
          slot.icon:SetAlpha(r.alpha)
          if slot.icon.SetDesaturated then slot.icon:SetDesaturated(r.desat) end
          Nock.UI.SetIconHighlight(slot, (r.glow == "border")
            and (p.fluffyActiveColor or C.COLORS.PROC_GLOW) or nil)
          Nock.UI.SetIconProcGlow(slot, r.glow == "overlay", nil)
          slot._lastLook = lk
        end

        local txt = (dispRem and dispRem > 0) and formatCD(dispRem) or ""
        if txt ~= slot._lastText then
          slot.cdText:SetText(txt)
          slot._lastText = txt
        end

        -- Swipe — only re-fire SetCooldown on change so the animation doesn't
        -- restart every tick.
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
      end
    end
  end
end
