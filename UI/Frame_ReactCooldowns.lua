-- UI/Frame_ReactCooldowns.lua
-- React-mode cooldown grid: three fixed rows (rotation / utility CDs /
-- consumables). Consumable slots (whenActive rows) only show while on
-- cooldown or with their buff up.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ReactCooldownsView = Nock:NewModule("ReactCooldownsView", "AceEvent-3.0")
local C = Nock.Constants

-- Same external cooldown-text integration as the classic grid: defer the CD
-- numbers to OmniCC & co. when present (detection must wait until login —
-- addons load alphabetically, so OmniCC loads after Nock).
local EXTERNAL_CD_ADDONS = { "OmniCC", "tullaCC", "ncCooldown" }

local function profile()
  return (Nock.db and Nock.db.profile) or {}
end

-- Fixed React skin: tight 1px gaps and thin black slot borders, immune to the
-- profile iconBorder/LSM settings (slots opt out via _fixedBorder — see
-- Nock.UI.ApplyIconBorder).
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
-- Slots overlap their 1px borders (same trick as the BuffTracker cells) so
-- adjacent icons share a single black seam — the reference's tight packing.
local GAP = -1
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

-- whenActive rows (consumables): a slot is visible only while mid-cooldown or
-- with the tracked buff up — idle potions stay hidden (reference behavior).
local function slotActive(key)
  local cd = Nock.state and Nock.state.cooldowns and Nock.state.cooldowns[key]
  if not cd then return false end
  return (cd.remaining or 0) > 0 or cd.procActive == true or (cd.buffRemaining or 0) > 0
end

local function formatCD(remaining)
  if remaining <= 0 then return "" end
  if remaining < 10 then return ("%.1f"):format(remaining) end
  if remaining < 90 then return ("%d"):format(math.ceil(remaining)) end
  return ("%dm"):format(math.floor(remaining / 60))
end

-- Effective key list for a row: the user's reactCdRows override (React HUD
-- tab row editor) or the built-in def.keys. EVERY reader of row membership
-- must go through this — RowsGeometry AND the whenActive mask watcher — or
-- customized rows desync from the visible-set rebuild trigger.
local function rowKeys(p, rowIndex, def)
  local custom = p.reactCdRows
  if type(custom) == "table" and type(custom[rowIndex]) == "table" then
    return custom[rowIndex]
  end
  return def.keys
end

function ReactCooldownsView:OnInitialize()
  local container = CreateFrame("Frame", "NockReactCooldowns", Nock.parentFrame)
  self.frame = container
  self._pool = {}
  self:Rebuild()
  container:Hide()  -- HUD:ApplyRowVisibility shows it in React mode

  self:RegisterMessage("NOCK_VISUALS_CHANGED", "Rebuild")
  self:RegisterEvent("PLAYER_LOGIN",          "ApplyExternalCdAddon")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyExternalCdAddon")
end

-- Row geometry from C.REACT_CD_ROWS: per row, resolve the enabled entries via
-- the shared Cooldowns builder and shrink the icon edge when reactWidth can't
-- fit the row at its design size. A fully-disabled row costs zero height.
-- Shared by Rebuild and ContentHeight so the HUD row can never drift.
function ReactCooldownsView:RowsGeometry()
  local p = profile()
  local w = tonumber(p.reactWidth) or 220
  local disabled = p.reactCooldownDisabled or {}
  local mod = Nock:GetModule("Cooldowns", true)
  local gap = GAP

  -- reactConsumablesAlways (React HUD tab): keep whenActive rows fully
  -- visible while idle (dormant icons) instead of the reference auto-hide.
  local always = p.reactConsumablesAlways == true
  -- Row DEFS (height/stretch/whenActive) always come from REACT_CD_ROWS —
  -- only the key lists can be user-customized (rowKeys above).

  local rows, totalH = {}, 0
  for rowIndex, def in ipairs(C.REACT_CD_ROWS) do
    local keys = rowKeys(p, rowIndex, def)
    local entries = {}
    local members = 0
    for _, key in ipairs(keys) do
      -- IsEntryAvailable: the Spec row is out while its spell is unknown
      -- (a BM hunter has no Readiness) — the engine sends VISUALS_CHANGED
      -- when that flips, so this geometry is rebuilt.
      if not disabled[key] and (not (mod and mod.IsEntryAvailable) or mod:IsEntryAvailable(key)) then
        members = members + 1
        if always or not def.whenActive or slotActive(key) then
          local e = mod and mod.GetEntry and mod:GetEntry(key)
          if e then entries[#entries + 1] = e end
        end
      end
    end
    local n = #entries
    -- whenActive rows RESERVE their height even while every member is idle:
    -- the HUD box hangs off its saved anchor, so a height change on pop-in
    -- would shift the rows above (layout jump mid-fight). The reserved strip
    -- is invisible (no backdrop in React mode). A row with NO enabled
    -- members at all still collapses fully.
    if n > 0 or (def.whenActive and members > 0) then
      local tileH = def.h
      local tileW
      if def.stretch and n > 0 then
        -- Fill the full React width: n tiles overlapping (n-1) 1px seams.
        tileW = (w + (n - 1)) / n
      else
        -- Fixed tiles (def.w, fallback ~1.3:1), centered by Rebuild.
        tileW = def.w or math.floor(tileH * 1.3 + 0.5)
      end
      if totalH > 0 then totalH = totalH + gap end
      rows[#rows + 1] = { entries = entries, w = tileW, h = tileH, y = totalH, index = rowIndex }
      totalH = totalH + tileH
    end
  end
  return rows, w, math.max(totalH, 1)
end

-- Logical (unscaled) height, for HUD's LAYOUT height fn.
function ReactCooldownsView:ContentHeight()
  local _, _, h = self:RowsGeometry()
  return h
end

-- (Re)place the pooled slots row by row, centered. Pool indices are sequential
-- across rows; surplus slots are hidden, never freed.
function ReactCooldownsView:Rebuild()
  local rows, w, totalH = self:RowsGeometry()
  local gap = GAP
  self.frame:SetSize(w, totalH)

  for _, s in ipairs(self._pool) do
    s._entry = nil
    s:Hide()
  end

  local i = 0
  for _, row in ipairs(rows) do
    local n = #row.entries
    local rowW = n * row.w + (n - 1) * gap
    local x0 = (w - rowW) / 2
    for col, entry in ipairs(row.entries) do
      i = i + 1
      local slot = self._pool[i]
      if not slot then
        -- reactScoped: reactFont, when set, overrides the global fontFace on
        -- these slots' texts (the grid otherwise follows the global font).
        slot = Nock.UI.CreateIconSlot(self.frame, "NockReactCDSlot" .. i, row.h, true)
        applyFixedSlotSkin(slot)
        self._pool[i] = slot
        self:ApplyExternalCdAddonToSlot(slot)
      end
      slot:SetSize(row.w, row.h)
      slot:ClearAllPoints()
      slot:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
                    x0 + (col - 1) * (row.w + gap), -row.y)
      -- Wider-than-tall tiles crop the texture vertically instead of
      -- stretching it — the reference's "zoomed" icon look. Base crop is the
      -- standard 0.08–0.92; the y-span shrinks by the aspect ratio.
      local ySpan = 0.42 * math.min(1, row.h / row.w)
      slot.icon:SetTexCoord(0.08, 0.92, 0.5 - ySpan, 0.5 + ySpan)
      slot._entry          = entry
      -- whenActive (consumable) rows desaturate their icon while recharging —
      -- see the visualState block in Refresh.
      slot._whenActive     = (C.REACT_CD_ROWS[row.index]
                              and C.REACT_CD_ROWS[row.index].whenActive) or false
      slot._lastIcon       = nil
      slot._lastText       = ""
      slot._lastVisState   = nil
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

function ReactCooldownsView:ApplyExternalCdAddonToSlot(slot)
  if self.externalCdAddon then
    slot.cooldown.noCooldownCount = nil  -- let the external addon paint
    slot.cdText:Hide()
  else
    slot.cooldown.noCooldownCount = true
    slot.cdText:Show()
  end
end

function ReactCooldownsView:ApplyExternalCdAddon()
  if self._cdAddonApplied then return end
  self._cdAddonApplied = true
  self.externalCdAddon = findExternalCdAddon()
  for _, slot in ipairs(self._pool) do
    self:ApplyExternalCdAddonToSlot(slot)
  end
end

-- The slot's look is Nock.UI.ReactSlotLook (UI/Widgets.lua, pure, tested):
-- proc glow while the tracked buff is up (the Blizzard overlay on the KC slot
-- behind reactKcProcGlow, else the static border), the consumable rows'
-- recharging grey, and the reference WA's out-of-range tint (reactRangeTint,
-- off / red / grey) off state.target.spellOut. No next-action glow in the
-- React skin — the reference grid is pure cooldown state. One scratch table
-- for the options: nothing is allocated on the tick.
local LOOK = { procGlow = false, tint = "off", whenActive = false, dim = false, manaTint = false }
local RES  = {}
-- The reference WA's colours: out-of-range red (its 0.77/0.12/0.23), no-mana
-- blue (0.33/0.54/1.0).
local TINT = { red = { 0.77, 0.12, 0.23, 1 }, blue = { 0.33, 0.54, 1, 1 } }

function ReactCooldownsView:Refresh(state)
  if not self.frame:IsShown() then return end

  -- whenActive rows appear/disappear with consumable state. When the visible
  -- set flips (rare — a potion press, a buff fading, a CD expiring), rebuild
  -- and relayout the HUD through the standard visuals message, then paint on
  -- the next tick against the fresh slot pool. With reactConsumablesAlways
  -- the slots never flip, so the whole watch is skipped; after toggling it
  -- back OFF a stale _activeMask costs at most ONE redundant rebuild before
  -- converging (never a loop — Rebuild must not touch _activeMask).
  local p = profile()
  if not p.reactConsumablesAlways then
    -- Must watch the EFFECTIVE row keys (rowKeys) — watching the built-in
    -- list would never trigger a rebuild for user-added consumables (Flare/
    -- Drums in row 3 stayed invisible through their whole active/CD cycle).
    local mask, bit = 0, 1
    for rowIndex, def in ipairs(C.REACT_CD_ROWS) do
      if def.whenActive then
        for _, key in ipairs(rowKeys(p, rowIndex, def)) do
          if slotActive(key) then mask = mask + bit end
          bit = bit * 2
        end
      end
    end
    if mask ~= self._activeMask then
      self._activeMask = mask
      self:SendMessage("NOCK_VISUALS_CHANGED")
      return
    end
  end

  for _, slot in ipairs(self._pool) do
    local entry = slot._entry
    if entry then
      local cd = state.cooldowns[entry.key]
      if cd then
        -- Buff pivot (same as the classic grid): while the tracked buff is up
        -- the slot shows the buff icon + remaining + matching swipe — this is
        -- what makes row 3 show active consumable time (e.g. Haste Potion).
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

        LOOK.procGlow   = (entry.key == "KC" and p.reactKcProcGlow) and true or false
        LOOK.tint       = p.reactRangeTint or "off"
        LOOK.dim        = p.reactTileDim and true or false
        LOOK.manaTint   = p.reactManaTint and true or false
        LOOK.whenActive = slot._whenActive
        local so = state.target.spellOut
        local r  = Nock.UI.ReactSlotLook(cd, so and so[entry.key], LOOK, RES)
        local lk = Nock.UI.ReactLookKey(r)
        if lk ~= slot._lastLook then
          local c = r.tint and TINT[r.tint]
          if c then slot.icon:SetVertexColor(c[1], c[2], c[3], c[4])
          else slot.icon:SetVertexColor(1, 1, 1, 1) end
          slot.icon:SetAlpha(r.alpha)
          if slot.icon.SetDesaturated then slot.icon:SetDesaturated(r.desat) end
          Nock.UI.SetIconHighlight(slot, (r.glow == "border") and C.COLORS.PROC_GLOW or nil)
          -- Uncoloured: the same gold overlay as the action bar (user, 2026-08-29:
          -- the PROC_GLOW-tinted one read blue).
          Nock.UI.SetIconProcGlow(slot, r.glow == "overlay", nil)
          slot._lastLook = lk
        end

        local txt = (dispRem and dispRem > 0) and formatCD(dispRem) or ""
        if txt ~= slot._lastText then
          slot.cdText:SetText(txt)
          slot._lastText = txt
        end

        -- Swipe — same (start, duration) pair as the text; only re-fire
        -- SetCooldown on change so the animation doesn't restart every tick.
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
