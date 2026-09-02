-- UI/Frame_Helpers.lua
-- The Helpers strip: one badge per state.helpers row with a dim caption under
-- it. Each badge is the icon with its label in a band along the bottom, a
-- YOU / PET / MAIN / OFF strip along the top where the row names a unit or a
-- hand, and — when the
-- row can be clicked — a gold pulse plus the Blizzard pointer hanging off the
-- corner. Text is Nock's Plex Mono face and the colours come from the skin
-- palette (quiet: the unit is read, not seen). The click itself lives in
-- UI/Frame_HelpersClick.lua, a separate secure layer that mirrors this
-- panel's geometry; this panel stays unprotected so it can keep hiding in
-- combat. Movable while unlocked (with a preview strip, since the panel is
-- hidden outside instances and in combat), styled via the helpers* keys.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local HelpersView = Nock:NewModule("HelpersView", "AceEvent-3.0")
local C = Nock.Constants
local Skin = Nock.Skin

local MAX_SLOTS   = 12
local PAD         = 6        -- panel padding around the strip
local FONT_ROLE   = "monoMedium"   -- Skin.FONTS role: IBM Plex Mono Medium
local CAP_SIZE    = 10       -- caption under the strip
local CAP_H       = 13       -- caption row height (when enabled)
local CD_FRAC     = 0.34     -- countdown font size as a fraction of the icon edge
local CAP_GAP     = 5        -- icons → caption
local BAND_FRAC   = 0.42     -- bottom band height as a fraction of the icon edge
local BAND_SIZE   = 9        -- band font size (helpersScale scales the rest)
local TOP_FRAC    = 0.24     -- top strip height as a fraction of the icon edge
local TOP_SIZE    = 7        -- top strip font size
local PTR_SIZE    = 18
local PTR_TEX     = "Interface\\Cursor\\Point"
local TOP_FRACTION        = C.DIM.WARN_TOP_FRACTION or 0.25  -- warnings live at 25%
-- 50px below the warnings row's centre, which itself sits at top * frac.
local Y_OFFSET_BELOW_WARN = C.DIM.WARN_ICON_SIZE + 50

-- Top strip text per row.unit: who or which hand the badge is about.
local STRIP_TEXT = { player = "YOU", pet = "PET", mh = "MAIN", oh = "OFF" }

-- Skin palette (UI/Skin.lua): wait gold for expiring + the click pulse, ink
-- for YOU / MAIN / OFF, the hunter green for PET, muted inks for the caption.
local function skin(name, fallback)
  if Skin and Skin.COLORS and Skin.COLORS[name] then return Skin.COLORS[name] end
  return fallback
end
local COLOR = {
  expiring = skin("wait",   { 0.85, 0.72, 0.40 }),
  click    = skin("wait",   { 0.85, 0.72, 0.40 }),
  missing  = { 0.23, 0.23, 0.23 },
  phase    = { 0.45, 0.45, 0.45 },                 -- eating / applying border
  strip    = skin("raised", { 0.09, 0.09, 0.09 }), -- top strip fill
  you      = skin("ink",    { 0.95, 0.95, 0.93 }),
  pet      = skin("accent", { 0.67, 0.83, 0.45 }),
  caption  = skin("ink2",   { 0.66, 0.66, 0.64 }),
  hint     = skin("wait",   { 0.85, 0.72, 0.40 }),
  countdown = { 1.00, 0.70, 0.00 },                -- the drafting amber
}
local MISSING_ALPHA = 0.7
local NOSTOCK_ALPHA = 0.55

local function profileNum(key, fallback)
  local p = Nock.db and Nock.db.profile
  local v = p and p[key]
  return type(v) == "number" and v or fallback
end

local function iconSize() return profileNum("helpersIconSize", 40) end
local function iconGap()  return profileNum("helpersIconGap", 10) end

local function captionEnabled()
  local p = Nock.db and Nock.db.profile
  return not (p and p.helpersHeadline == false)
end

local function setFont(fs, size, flags, role)
  if Skin and Skin.Font then
    Skin.Font(fs, role or FONT_ROLE, size, flags)
  else
    fs:SetFont(C.FONT.PATH, size, flags or "")
  end
end

local function formatDur(seconds)
  if not seconds or seconds <= 0 then return "" end
  if seconds < 10 then return ("%.1f"):format(seconds) end
  if seconds < 60 then return ("%d"):format(math.ceil(seconds)) end
  if seconds < 3600 then
    local m = math.floor(seconds / 60)
    return ("%dm"):format(m)
  end
  return ("%dh"):format(math.floor(seconds / 3600))
end

-- Same cascade Modules/Helpers.lua uses for its badge icons.
local function itemIconOf(id)
  if C_Item and C_Item.GetItemIconByID then
    local i = C_Item.GetItemIconByID(id)
    if i then return i end
  end
  if GetItemInfo then
    local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
    if icon then return icon end
  end
  return nil
end

function HelpersView:OnInitialize()
  local panel = CreateFrame("Frame", "NockHelpers", UIParent, "BackdropTemplate")
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(f) f:StartMoving() end)
  panel:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    Nock.db.profile.helpersPosition = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  Nock.UI.RegisterNudgeable(panel, {
    label   = "Helpers",
    get     = function()
      local p = Nock.db.profile.helpersPosition
      return type(p) == "table" and p or nil
    end,
    set     = function(pos)
      Nock.db.profile.helpersPosition = pos
      HelpersView:ApplyPosition()
    end,
    -- `false` is the "never dragged" sentinel, which ApplyPosition reads as
    -- the computed spot below the warnings — that IS the panel's default.
    default = function()
      Nock.db.profile.helpersPosition = false
      HelpersView:ApplyPosition()
      return nil
    end,
  })
  panel:SetFrameStrata("HIGH")
  panel:Hide()
  self.frame = panel

  self.slots = {}
  for i = 1, MAX_SLOTS do
    local slot = Nock.UI.CreateIconSlot(panel, "NockHelperSlot" .. i, iconSize())
    slot.cdText:SetText("")
    local tl = slot.cdText:GetParent()   -- the slot's text layer (above the swipe)

    -- Countdown: our own FontString (the slot's cdText follows the HUD font
    -- registry, and this one wants to be bold amber regardless). Sized in
    -- ApplyMetrics.
    local cd = tl:CreateFontString(nil, "OVERLAY")
    cd:SetPoint("CENTER", slot, "CENTER", 0, 1)
    cd:SetTextColor(COLOR.countdown[1], COLOR.countdown[2], COLOR.countdown[3], 1)
    slot.cd = cd

    -- Bottom band inside the icon; the label rides on it.
    local band = tl:CreateTexture(nil, "ARTWORK")
    band:SetPoint("BOTTOMLEFT",  slot.icon, "BOTTOMLEFT",  0, 0)
    band:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", 0, 0)
    band:SetColorTexture(0, 0, 0, 0.75)
    -- SetGradient takes ColorMixins on this client (see the practice
    -- conveyor); the solid fill above is the fallback look.
    if band.SetGradient and CreateColor then
      band:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.92), CreateColor(0, 0, 0, 0.15))
    end
    slot.band = band

    -- Anchored a little past both icon edges so CENTER really centres the
    -- outlined glyphs on the icon column.
    local label = tl:CreateFontString(nil, "OVERLAY")
    setFont(label, BAND_SIZE, "OUTLINE")
    label:SetPoint("BOTTOMLEFT",  slot.icon, "BOTTOMLEFT",  -6, 2)
    label:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT",  6, 2)
    label:SetJustifyH("CENTER")
    label:SetTextColor(1, 1, 1, 1)
    slot.label = label

    -- Top strip inside the icon: a dark header carrying YOU / PET in colour.
    local top = tl:CreateTexture(nil, "ARTWORK")
    top:SetPoint("TOPLEFT",  slot.icon, "TOPLEFT",  0, 0)
    top:SetPoint("TOPRIGHT", slot.icon, "TOPRIGHT", 0, 0)
    top:SetColorTexture(COLOR.strip[1], COLOR.strip[2], COLOR.strip[3], 0.92)
    top:Hide()
    local tag = tl:CreateFontString(nil, "OVERLAY")
    setFont(tag, TOP_SIZE, "")
    tag:SetPoint("CENTER", top, "CENTER", 0, 0)
    tag:Hide()
    slot.top, slot.tag = top, tag

    -- Blizzard pointer hanging off the bottom-right corner: "this one clicks".
    local ptr = tl:CreateTexture(nil, "OVERLAY", nil, 2)
    ptr:SetTexture(PTR_TEX)
    ptr:SetSize(PTR_SIZE, PTR_SIZE)
    ptr:SetPoint("CENTER", slot, "BOTTOMRIGHT", 1, -1)
    ptr:Hide()
    slot.ptr = ptr

    slot:Hide()
    slot._lastIcon, slot._lastText, slot._lastLabel = nil, "", nil
    slot._lastPhase, slot._lastTag, slot._lastClick = nil, nil, nil
    slot._lastCdStart, slot._lastCdDur = nil, nil
    if slot.cooldown then slot.cooldown.noCooldownCount = true end
    self.slots[i] = slot
  end
  self._slotX = {}          -- per-slot TOPLEFT x offsets, read by SlotOffset
  self._list  = nil         -- the list rendered last tick, read by ClickableRow

  -- Caption under the strip: PRE-PULL · CLICK TO APPLY, muted.
  local cap = panel:CreateFontString(nil, "OVERLAY")
  setFont(cap, CAP_SIZE, "OUTLINE")
  cap:SetText("PRE-PULL")
  cap:SetTextColor(COLOR.caption[1], COLOR.caption[2], COLOR.caption[3], 1)
  self.cap = cap

  local hint = panel:CreateFontString(nil, "OVERLAY")
  setFont(hint, CAP_SIZE, "OUTLINE")
  hint:SetText("· CLICK TO APPLY")
  hint:SetTextColor(COLOR.hint[1], COLOR.hint[2], COLOR.hint[3], 1)
  self.hint = hint

  self:ApplyMetrics()
  self:ApplyPosition()
  self:ApplyLock()

  self:RegisterMessage("NOCK_VISUALS_CHANGED",        "OnVisualsChanged")
  self:RegisterMessage("NOCK_LOCK_CHANGED",           "ApplyLock")
  self:RegisterMessage("NOCK_HELPERS_POSITION_RESET", "ApplyPosition")
  self:RegisterMessage("NOCK_POSITION_RESET",         "ApplyPosition")  -- profile switch

  if not Nock.isHunter then panel:Hide() end
end

-- Slot sizes + panel scale from the profile. Re-run on NOCK_VISUALS_CHANGED.
function HelpersView:ApplyMetrics()
  local size = iconSize()
  for _, slot in ipairs(self.slots) do
    slot:SetSize(size, size)
    slot.band:SetHeight(math.max(8, math.floor(size * BAND_FRAC)))
    slot.top:SetHeight(math.max(TOP_SIZE + 2, math.floor(size * TOP_FRAC)))
    -- Bold: Plex Sans SemiBold (no bold mono ships), with an outline so the
    -- digits hold up over a lit icon.
    setFont(slot.cd, math.max(10, math.floor(size * CD_FRAC)), "OUTLINE", "uiBold")
  end
  self.frame:SetScale(profileNum("helpersScale", 1.0))
end

function HelpersView:ApplyPosition()
  local pos = Nock.db and Nock.db.profile and Nock.db.profile.helpersPosition
  self.frame:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    self.frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    -- Never dragged: the legacy computed spot, centred below the warnings row.
    local screenH = UIParent:GetHeight() or 768
    self.frame:SetPoint("CENTER", UIParent, "TOP", 0,
      -screenH * TOP_FRACTION - Y_OFFSET_BELOW_WARN)
  end
end

function HelpersView:ApplyLock()
  local locked = Nock.IsLocked()
  self.frame:EnableMouse(not locked)
  self:ApplyStyle()
end

-- User Background block (helpers* keys); the green unlock border wins while
-- the panel is draggable so it stays findable.
function HelpersView:ApplyStyle()
  Nock.UI.ApplyUserPanelStyle(self.frame, "helpers")
  if not Nock.IsLocked() then
    self.frame:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  end
end

function HelpersView:OnVisualsChanged()
  self:ApplyMetrics()
  self:ApplyStyle()
  -- Slot geometry may have moved; force every slot to repaint next tick.
  for _, slot in ipairs(self.slots) do slot._lastPhase = nil end
end

-- Width the caption needs (0 when off), so a two-badge row still fits it.
local function captionWidth(self, anyClick)
  if not captionEnabled() then return 0 end
  local w = self.cap:GetStringWidth()
  if anyClick then w = w + 4 + self.hint:GetStringWidth() end
  return w
end

-- Centres the caption under the strip; returns the height it occupies (0
-- when off) so the panel can grow by it.
function HelpersView:LayoutCaption(anyClick, innerW, size)
  if not captionEnabled() then
    self.cap:Hide(); self.hint:Hide()
    return 0
  end
  local w = captionWidth(self, anyClick)
  local x = PAD + (innerW - w) / 2
  local y = -(PAD + size + CAP_GAP)
  self.cap:ClearAllPoints()
  self.cap:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
  self.hint:ClearAllPoints()
  self.hint:SetPoint("LEFT", self.cap, "RIGHT", 4, 0)
  self.cap:Show()
  if anyClick then self.hint:Show() else self.hint:Hide() end
  return CAP_GAP + CAP_H
end

-- While unlocked the panel must be visible ANYWHERE — it is hidden outside
-- instances and in combat, so there would otherwise be no moment in which it
-- could be dragged (the transient-frame rule). The preview substitutes four
-- sample badges: one expiring, one wearing the click cue, a YOU and a PET
-- strip, so every treatment can be styled. Preview rows never carry an
-- applyItem, so the click layer ignores them.
local previewList
local function getPreviewList()
  -- Only cache once every icon resolved: item icons come back nil until the
  -- client has the item cached, and a preview built during that window would
  -- otherwise keep its blank icons for the rest of the session.
  if previewList then return previewList end
  local samples = {
    { key = "food",         phase = "missing",  label = "FOOD",  item = 27655, previewClick = true },
    { key = "flask",        phase = "expiring", label = "FLASK", item = 22854, remaining = 90 },
    { key = "scrollPlayer", phase = "missing",  label = "AGI",   item = 27498, unit = "player", sub = "agi" },
    { key = "scrollPet",    phase = "missing",  label = "STR",   item = 27503, unit = "pet",    sub = "str" },
  }
  local out, complete = {}, true
  for i, smp in ipairs(samples) do
    local icon = itemIconOf(smp.item)
    if not icon then complete = false end
    out[i] = {
      id           = "preview_" .. smp.key,
      status       = smp.phase,
      phase        = smp.phase,
      icon         = icon,
      remaining    = smp.remaining,
      label        = smp.label,
      unit         = smp.unit,
      sub          = smp.sub,
      applyItem    = nil,
      applyKind    = "item",
      previewClick = smp.previewClick,
    }
  end
  if complete then previewList = out end
  return out
end

function HelpersView:Refresh(state)
  local unlocked = not Nock.IsLocked()
  local list = state.helpers
  if unlocked and #list == 0 then list = getPreviewList() end

  -- Hide the whole panel when globally disabled, a third-party consumes WA is
  -- loaded, or the player is in combat (pre-pull panel only) — unless we're
  -- unlocked, in which case it stays up to be positioned.
  local p = Nock.db and Nock.db.profile
  local suppressed = (p and p.showHelpers == false)
    or Nock.state.helpersHiddenByWA
    or Nock.state.player.inCombat
  if suppressed and not unlocked then
    if self.frame:IsShown() then
      for _, slot in ipairs(self.slots) do slot:Hide() end
      self.frame:Hide()
    end
    return
  end

  local n = math.min(#list, MAX_SLOTS)
  if n == 0 then
    if self.frame:IsShown() then self.frame:Hide() end
    return
  end

  self._list = list                     -- reference only, read by ClickableRow
  local size, gap = iconSize(), iconGap()
  local rowWidth = n * size + math.max(0, n - 1) * gap
  local anyClick = false
  for i = 1, n do if list[i].applyItem then anyClick = true; break end end
  local innerW = math.max(rowWidth, captionWidth(self, anyClick))
  local capH = self:LayoutCaption(anyClick, innerW, size)
  self.frame:SetSize(innerW + 2 * PAD, size + capH + 2 * PAD)
  local rowX = PAD + (innerW - rowWidth) / 2
  self._rowCount, self._slotY, self._slotSize = n, -PAD, size
  local now = GetTime()

  for i = 1, MAX_SLOTS do
    local slot = self.slots[i]
    local h = list[i]
    if i <= n and h then
      -- Anchor each slot from the panel's TOPLEFT so the strip shares a top
      -- edge; the click layer re-derives the same offsets.
      local x = rowX + (i - 1) * (size + gap)
      self._slotX[i] = x
      slot:ClearAllPoints()
      slot:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, self._slotY)

      if h.icon and h.icon ~= slot._lastIcon then
        slot.icon:SetTexture(h.icon)
        slot._lastIcon = h.icon
        -- Some clients reset vertex / desaturation when the texture changes,
        -- so force the phase branch below to re-apply by clearing the cache.
        slot._lastPhase = nil
      end

      -- The cue is the row's applyItem; the unlock preview wears it on its
      -- first sample only so it can be styled (never a real click).
      local clickable = h.applyItem ~= nil or h.previewClick == true
      local nostock = (h.phase == "missing") and not clickable
        and h.label and h.label:sub(1, 3) == "NO "
      local phaseKey = (h.phase or "missing") .. (nostock and "|nostock" or "")
      if phaseKey ~= slot._lastPhase then
        if h.phase == "expiring" then
          -- The buff IS up — full colour, gold border, countdown running.
          slot.icon:SetVertexColor(1, 1, 1, 1)
          if slot.icon.SetDesaturated then slot.icon:SetDesaturated(false) end
          slot:SetAlpha(1)
          slot:SetBackdropBorderColor(COLOR.expiring[1], COLOR.expiring[2], COLOR.expiring[3], 1)
        elseif h.phase == "eating" or h.phase == "applying" then
          -- On its way: full colour so the click reads as taken, neutral edge.
          slot.icon:SetVertexColor(1, 1, 1, 1)
          if slot.icon.SetDesaturated then slot.icon:SetDesaturated(false) end
          slot:SetAlpha(1)
          slot:SetBackdropBorderColor(COLOR.phase[1], COLOR.phase[2], COLOR.phase[3], 1)
        else
          -- True desaturation (greyscale) plus a dim; dimmer still when there
          -- is nothing in bags to fix it with.
          slot.icon:SetVertexColor(0.65, 0.65, 0.65, 1)
          if slot.icon.SetDesaturated then slot.icon:SetDesaturated(true) end
          slot:SetAlpha(nostock and NOSTOCK_ALPHA or MISSING_ALPHA)
          slot:SetBackdropBorderColor(COLOR.missing[1], COLOR.missing[2], COLOR.missing[3], 1)
        end
        slot._lastPhase = phaseKey
        slot._lastClick = nil
      end

      -- Click cue: gold pulse on the border + the pointer. The pulse is the
      -- one unconditional per-tick paint, and only on clickable rows.
      if clickable then
        local a = 0.55 + 0.45 * math.sin(now * 4)
        slot:SetBackdropBorderColor(COLOR.click[1], COLOR.click[2], COLOR.click[3], a)
        slot:SetAlpha(1)
        if not slot._lastClick then slot.ptr:Show(); slot._lastClick = true end
      elseif slot._lastClick then
        slot.ptr:Hide()
        slot._lastClick = false
        slot._lastPhase = nil   -- re-apply the phase border next tick
      end

      -- The refill item's cooldown (and the GCD it triggers) sweeps the badge,
      -- so a click that "did nothing" reads as "not ready yet" instead.
      local cs, cd = h.cdStart or 0, h.cdDuration or 0
      if cs ~= slot._lastCdStart or cd ~= slot._lastCdDur then
        slot.cooldown:SetCooldown(cs, cd)
        slot._lastCdStart, slot._lastCdDur = cs, cd
      end

      local txt = (h.phase == "expiring") and formatDur(h.remaining) or ""
      if txt ~= slot._lastText then
        slot.cd:SetText(txt)
        slot._lastText = txt
      end

      if h.label ~= slot._lastLabel then
        slot.label:SetText(h.label or "")
        slot._lastLabel = h.label
      end

      if h.unit ~= slot._lastTag then
        local stripText = h.unit and STRIP_TEXT[h.unit]
        if stripText then
          local c = (h.unit == "pet") and COLOR.pet or COLOR.you
          slot.tag:SetText(stripText)
          slot.tag:SetTextColor(c[1], c[2], c[3], 1)
          slot.top:Show(); slot.tag:Show()
        else
          slot.top:Hide(); slot.tag:Hide()
        end
        slot._lastTag = h.unit
      end

      if not slot:IsShown() then slot:Show() end
    else
      self._slotX[i] = nil
      if slot:IsShown() then slot:Hide() end
    end
  end

  if not self.frame:IsShown() then self.frame:Show() end
end

-- Read-only geometry for UI/Frame_HelpersClick.lua, which mirrors the badges
-- with secure buttons on its own layer. Nothing here refers back to it.
function HelpersView:Geometry()
  local f = self.frame
  return f:GetLeft(), f:GetTop(), f:GetScale(), f:IsShown()
end

function HelpersView:RowCount() return self._rowCount or 0 end

-- Slot i's TOPLEFT offset from the panel's TOPLEFT (y negative) and its edge,
-- in panel units; nil when slot i is not shown.
function HelpersView:SlotOffset(i)
  local x = self._slotX and self._slotX[i]
  if not x then return nil end
  return x, self._slotY, self._slotSize
end

-- The live row in slot i when it can be clicked. Preview rows (unlocked, no
-- live data) are never clickable: their applyItem is nil by construction.
function HelpersView:ClickableRow(i)
  local list = self._list
  local r = list and list[i]
  if r and r.applyItem then return r end
  return nil
end
