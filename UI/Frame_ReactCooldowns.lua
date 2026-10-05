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
-- The overlap is ONE DEVICE PIXEL, laid out in whole pixels (Nock.UI.SeamPx).
local SLOT_BG = { 0.08, 0.08, 0.08, 0.90 }

local function applyFixedSlotSkin(slot)
  slot._fixedBorder = true
  Nock.UI.ApplyBackdrop(slot, SLOT_BG, { 0, 0, 0, 1 })   -- 1 device-pixel edge
  Nock.UI.PixelInset(slot.icon, slot)
end

-- whenActive rows (consumables): a slot is visible only while mid-cooldown or
-- with the tracked buff up — idle potions stay hidden (reference behavior).
local function slotActive(key)
  local cd = Nock.state and Nock.state.cooldowns and Nock.state.cooldowns[key]
  if not cd then return false end
  return (cd.remaining or 0) > 0 or cd.procActive == true or (cd.buffRemaining or 0) > 0
end

-- Nock.UI.FormatCooldownText: tenths under 10 s (the reference) or whole
-- seconds (reactCdWholeSeconds).
local function formatCD(remaining)
  return Nock.UI.FormatCooldownText(remaining, profile().reactCdWholeSeconds == true)
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
  self._cdmod = Nock:GetModule("Cooldowns", true)
  self:Rebuild()
  container:Hide()  -- HUD:ApplyRowVisibility shows it in React mode

  self:RegisterMessage("NOCK_VISUALS_CHANGED", "Rebuild")
  self:RegisterMessage("NOCK_PIXEL_GRID_CHANGED", "Rebuild")   -- device-pixel seams
  self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnSpellCooldown")
  self:RegisterEvent("PLAYER_LOGIN",          "ApplyExternalCdAddon")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyExternalCdAddon")
  -- Forever only (Nock.ForeverStingTiles is nil on TBC): the sting tiles'
  -- client-drawn timers (Forever/StingTiles.lua).
  if Nock.Flavor and Nock.Flavor.forever and Nock.ForeverStingTiles then
    self._stingTiles = {}
    self._stingDirty = true   -- the first Rebuild ran above, before the tiles existed
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnStingTarget")
    self:RegisterEvent("SPELLS_CHANGED",        "OnStingSpells")
  end
end

-- Sting tiles (Forever): a `debuff` entry's slot is covered by the client's
-- own tile while the sting is on the target. Rebuild only marks them dirty;
-- the tick syncs them, and again after combat for whatever had to wait
-- (building, resizing and re-filtering a container are out-of-combat work).
local STING_ENV = { inCombat = false, zoom = nil, idsFor = nil }
local stingBook   -- the spellbook's name -> id map, read once per sync

local function stingName(id)
  local n = Nock.Flavor.Plain(Nock.API.SpellName(id))
  return type(n) == "string" and n or nil
end

-- The ids a sting entry's aura can carry: its known ranks plus the
-- spellbook's id, under the client's (localized) name for rank 1. The
-- unified tile (entry.stings) takes every covered sting's ids.
function STING_ENV.idsFor(entry)
  local ST = Nock.ForeverStingTiles
  if stingBook == nil then stingBook = (Nock.ForeverSpellbookNames and Nock.ForeverSpellbookNames()) or false end
  local book = stingBook or nil
  local R = (Nock.Spells and Nock.Spells.STING_RANKS) or {}
  if entry.stings then
    local out = {}
    for _, key in ipairs(entry.stings) do
      local ranks = R[key]
      if ranks then
        local ids = ST.Ids(ranks, stingName(ranks[1]), stingName, book)
        for i = 1, #ids do out[#out + 1] = ids[i] end
      end
    end
    return out
  end
  return ST.Ids(R[entry.key] or { entry.id }, stingName(entry.id) or entry.name, stingName, book)
end

function ReactCooldownsView:SyncStingTiles()
  self._stingDirty = false
  local ST = Nock.ForeverStingTiles
  STING_ENV.inCombat = (InCombatLockdown and InCombatLockdown()) and true or false
  STING_ENV.zoom = profile().gridIconZoom
  stingBook = nil
  self._stingAfterCombat = ST.Sync(self._stingTiles, self._pool, self.frame, STING_ENV)
end

function ReactCooldownsView:OnStingTarget()
  Nock.ForeverStingTiles.RereadAll(self._stingTiles)
end

-- A new rank brings a new aura id: the filters are checked at the next sync.
function ReactCooldownsView:OnStingSpells()
  if next(self._stingTiles) == nil then return end
  Nock.ForeverStingTiles.MarkIdsStale(self._stingTiles)
  self._stingDirty = true
end

-- Row geometry from C.REACT_CD_ROWS: per row, resolve the enabled entries via
-- the shared Cooldowns builder and shrink the icon edge when reactWidth can't
-- fit the row at its design size. A fully-disabled row costs zero height.
-- Shared by Rebuild and ContentHeight so the HUD row can never drift.
--
-- Laid out in whole DEVICE pixels (Nock.UI.SeamPx): each row and tile is a
-- whole number of pixels and neighbours overlap by exactly one, so every seam
-- is one black line at any UI scale. Rows carry the pixel fields (hPx, yPx,
-- tilePx or stretch) plus the same values in units (w, h, y) for readers.
-- Returns rows, width, height (units) and the pixels-per-unit used.
function ReactCooldownsView:RowsGeometry()
  local p = profile()
  local dev = Nock.UI.PixelScale(self.frame)
  local ds = (dev and dev > 0) and dev or 1
  -- Even, like the React cluster above it, so the two share both edges.
  local wPx = Nock.UI.EvenPx(tonumber(p.reactWidth) or 220, ds)
  local disabled = p.reactCooldownDisabled or {}
  local mod = Nock:GetModule("Cooldowns", true)

  -- reactConsumablesAlways (React HUD tab): keep whenActive rows fully
  -- visible while idle (dormant icons) instead of the reference auto-hide.
  local always = p.reactConsumablesAlways == true
  -- Row DEFS (height/stretch/whenActive) always come from REACT_CD_ROWS —
  -- only the key lists can be user-customized (rowKeys above).

  local rows, totalPx = {}, 0
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
      local hPx = Nock.UI.SeamPx(def.h, ds)
      local stretch = (def.stretch and n > 0) and true or false
      local tilePx
      if stretch then
        -- Fill the full React width: n tiles overlapping (n-1) 1px seams,
        -- split by Nock.UI.SeamSplit (widths differ by at most a pixel).
        tilePx = (wPx + (n - 1)) / n
      else
        -- Fixed tiles (def.w, fallback ~1.3:1), centered by Rebuild.
        tilePx = Nock.UI.SeamPx(def.w or math.floor(def.h * 1.3 + 0.5), ds)
      end
      if totalPx > 0 then totalPx = totalPx - 1 end   -- the shared seam
      rows[#rows + 1] = { entries = entries, stretch = stretch, tilePx = tilePx,
                          hPx = hPx, yPx = totalPx, index = rowIndex,
                          w = tilePx / ds, h = hPx / ds, y = totalPx / ds }
      totalPx = totalPx + hPx
    end
  end
  return rows, wPx / ds, math.max(totalPx, 1) / ds, ds
end

-- Logical (unscaled) height, for HUD's LAYOUT height fn.
function ReactCooldownsView:ContentHeight()
  local _, _, h = self:RowsGeometry()
  return h
end

-- Pixel box of tile `col` in `row` (left, width) within a `wPx`-wide frame.
local function tileBox(row, col, wPx)
  local n = #row.entries
  if row.stretch then return Nock.UI.SeamSplit(wPx, n, col) end
  local t = row.tilePx
  local x0 = math.floor((wPx - (n * t - (n - 1))) / 2)
  return x0 + (col - 1) * (t - 1), t
end

-- (Re)place the pooled slots row by row, centered. Pool indices are sequential
-- across rows; surplus slots are hidden, never freed.
function ReactCooldownsView:Rebuild()
  self._gcdDirty = true   -- re-seat the GCD swipes on the fresh layout
  self._stingDirty = self._stingTiles ~= nil   -- and the sting tiles on their slots
  local rows, w, totalH, ds = self:RowsGeometry()
  local p = profile()
  -- Everything below is whole device pixels (RowsGeometry), converted to
  -- units only here, so every 1 px seam is exactly one shared pixel.
  local wPx = math.floor(w * ds + 0.5)
  self.frame:SetSize(w, totalH)

  for _, s in ipairs(self._pool) do
    s._entry = nil
    s:Hide()
  end

  local i = 0
  for _, row in ipairs(rows) do
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
      local xPx, tPx = tileBox(row, col, wPx)
      local tw = tPx / ds
      slot:SetSize(tw, row.h)
      slot:ClearAllPoints()
      slot:SetPoint("TOPLEFT", self.frame, "TOPLEFT", xPx / ds, -row.y)
      Nock.UI.PixelInset(slot.icon, slot)
      -- Wider-than-tall tiles crop the texture vertically instead of
      -- stretching it — the reference's "zoomed" icon look. The edge trim is
      -- the user's icon zoom (gridIconZoom, 8 % = the standard 0.08–0.92).
      slot.icon:SetTexCoord(Nock.UI.IconCoords(tw, row.h, p.gridIconZoom))
      slot._entry          = entry
      slot._row            = row.index
      -- Per-HUD active-highlight geometry (thickness + contained/overflow);
      -- style + color are the Refresh look's job.
      Nock.UI.ApplyGlowStyle(slot, p.reactActiveSize or 3,
                             p.reactActiveFit == "contained")
      -- whenActive (consumable) rows desaturate their icon while recharging —
      -- see the visualState block in Refresh.
      slot._whenActive     = (C.REACT_CD_ROWS[row.index]
                              and C.REACT_CD_ROWS[row.index].whenActive) or false
      -- Pair tile (two spells on one cooldown, Forever's Multi+Aimed): two
      -- half icons drawn over the base icon, each cropped to its middle.
      -- Anchored to the icon REGION so the border insets carry over.
      if entry.ids and not entry.texture then
        if not slot.iconL then
          slot.iconL = slot:CreateTexture(nil, "ARTWORK", nil, 1)
          slot.iconL:SetPoint("TOPLEFT", slot.icon, "TOPLEFT", 0, 0)
          slot.iconL:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOM", 0, 0)
          slot.iconR = slot:CreateTexture(nil, "ARTWORK", nil, 1)
          slot.iconR:SetPoint("TOPLEFT", slot.icon, "TOP", 0, 0)
          slot.iconR:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", 0, 0)
          -- The divider: Media/PairSeam.tga (Tests/tools/pair_seam.py), a
          -- 12 px strip with a 2 px line and a symmetric shadow, drawn 1:1
          -- in device pixels centred on the seam and stretched to the icon's
          -- height.
          slot.seam = slot:CreateTexture(nil, "ARTWORK", nil, 2)
          slot.seam:SetTexture("Interface\\AddOns\\Nock\\Media\\PairSeam")
          if slot.seam.SetSnapToPixelGrid then slot.seam:SetSnapToPixelGrid(false) end
          if slot.seam.SetTexelSnappingBias then slot.seam:SetTexelSnappingBias(0) end
        end
        local cl, cr = Nock.UI.PairIconCoords(tw, row.h, p.gridIconZoom)
        slot.iconL:SetTexCoord(cl[1], cl[2], cl[3], cl[4])
        slot.iconR:SetTexCoord(cr[1], cr[2], cr[3], cr[4])
        -- Strip geometry in UI units for a 1:1 device-pixel draw: 12 px wide,
        -- centred on the seam.
        local ps = (Nock.UI.PixelScale and Nock.UI.PixelScale(slot)) or 1
        slot.seam:ClearAllPoints()
        slot.seam:SetPoint("TOP", slot.icon, "TOP", 0, 0)
        slot.seam:SetPoint("BOTTOM", slot.icon, "BOTTOM", 0, 0)
        slot.seam:SetWidth(12 / ps)
        slot.iconL:Show(); slot.iconR:Show(); slot.seam:Show()
        slot._lastIconL, slot._lastIcon2 = nil, nil
      elseif slot.iconL then
        slot.iconL:Hide(); slot.iconR:Hide(); slot.seam:Hide()
      end
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
      Nock.UI.SetIconInsetGlow(slot, nil)
      slot:Show()
    end
  end
end

local function findExternalCdAddon()
  local check = Nock.API.IsAddOnLoaded
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
  if self._stingDirty or (self._stingAfterCombat and not (InCombatLockdown and InCombatLockdown())) then
    self:SyncStingTiles()
  end

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
      -- Our own rows and the HUD's stacking only: NOCK_VISUALS_CHANGED here
      -- put a potion press or a buff fading through the whole addon's media
      -- re-apply mid-fight.
      self:Rebuild()
      self:SendMessage("NOCK_HUD_RELAYOUT")
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
        -- A buff with no expiry (Forever's Shadowmeld, buffPermanent) pivots
        -- too: lit, no countdown, no swipe.
        local showBuff  = cd.procActive and cd.buffIcon
                        and ((cd.buffRemaining or 0) > 0 or cd.buffPermanent == true)
        local dispIcon  = showBuff and cd.buffIcon      or cd.icon
        local dispStart = showBuff and cd.buffStartTime or cd.startTime
        local dispDur   = showBuff and cd.buffDuration  or cd.duration
        local dispRem
        if showBuff then dispRem = cd.buffRemaining or 0 else dispRem = cd.remaining end

        if dispIcon and dispIcon ~= slot._lastIcon then
          slot.icon:SetTexture(dispIcon)
          slot._lastIcon = dispIcon
        end
        local pair = entry.ids and not entry.texture and slot.iconL
        if pair then
          if dispIcon ~= slot._lastIconL then slot.iconL:SetTexture(dispIcon); slot._lastIconL = dispIcon end
          if cd.icon2 ~= slot._lastIcon2 then slot.iconR:SetTexture(cd.icon2); slot._lastIcon2 = cd.icon2 end
        end

        LOOK.procGlow    = (entry.key == "KC" and p.reactKcProcGlow) and true or false
        -- Move-in cue: the Raptor tile glows while the weave coach says GO.
        LOOK.goGlow      = (entry.key == "Raptor" and p.reactRaptorGoGlow
                            and Nock.UI.CoachStage(state) == "GO") and true or false
        LOOK.activeStyle = p.reactActiveStyle
        -- Settings preview: light every tile; suspended in combat.
        LOOK.preview     = (Nock.UI.activePreview
                            and not (InCombatLockdown and InCombatLockdown())) or false
        LOOK.tint        = p.reactRangeTint or "off"
        LOOK.dim         = p.reactTileDim and true or false
        LOOK.manaTint    = p.reactManaTint and true or false
        LOOK.whenActive  = slot._whenActive
        local mod = self._cdmod
        LOOK.unlearned   = (mod and mod.IsEntryKnown and mod:IsEntryKnown(entry.key) == false) or false
        local so = state.target.spellOut
        local r  = Nock.UI.ReactSlotLook(cd, so and so[entry.key], LOOK, RES)
        local lk = Nock.UI.ReactLookKey(r)
        if lk ~= slot._lastLook then
          local c = r.tint and TINT[r.tint]
          if c then slot.icon:SetVertexColor(c[1], c[2], c[3], c[4])
          else slot.icon:SetVertexColor(1, 1, 1, 1) end
          slot.icon:SetAlpha(r.alpha)
          if slot.icon.SetDesaturated then slot.icon:SetDesaturated(r.desat) end
          if pair then
            for _, half in ipairs({ slot.iconL, slot.iconR }) do
              if c then half:SetVertexColor(c[1], c[2], c[3], c[4]) else half:SetVertexColor(1, 1, 1, 1) end
              half:SetAlpha(r.alpha)
              if half.SetDesaturated then half:SetDesaturated(r.desat) end
            end
          end
          Nock.UI.SetIconHighlight(slot, (r.glow == "border")
            and (p.reactActiveColor or C.COLORS.PROC_GLOW) or nil)
          -- Uncoloured: the same gold overlay as the action bar (user, 2026-08-29:
          -- the PROC_GLOW-tinted one read blue).
          Nock.UI.SetIconProcGlow(slot, r.glow == "overlay", nil)
          Nock.UI.SetIconInsetGlow(slot, (r.glow == "inset")
            and (p.reactActiveColor or C.COLORS.PROC_GLOW) or nil, (p.reactActiveSize or 3) * 3)
          slot._lastLook = lk
        end

        local txt = (dispRem and dispRem > 0) and formatCD(dispRem) or ""
        if txt ~= slot._lastText then
          slot.cdText:SetText(txt)
          slot._lastText = txt
        end

        -- Forever fallback: the client's cooldown runs where the ledger has no
        -- timer (a length never read yet, or one too short). The swipe and the
        -- number are then the client's, from its duration object: the number
        -- is its remaining time (secret in combat) handed straight to the
        -- tile's text -- the widget's own countdown numbers only draw with
        -- the countdownForCooldowns CVar on, which ships off.
        local fallback = cd.clientRunning and not showBuff and not (dispRem and dispRem > 0)
                         and cd.spellId and slot.cooldown.SetCooldownFromDurationObject
        if fallback then
          -- re-read on each feed of the watch (the GCD's object, then the cooldown's)
          if slot._fallback == nil or slot._fbFeed ~= cd.clientFeed then
            local durObj = Nock.API.SpellCooldownDuration(cd.spellId)
            if durObj then slot.cooldown:SetCooldownFromDurationObject(durObj) end
            slot._fallback, slot._fbFeed = durObj or false, cd.clientFeed
            -- nonzero: the ledger's next start re-feeds, its end clears
            slot._lastCdStart, slot._lastCdDuration = -1, -1
          end
          local obj = slot._fallback
          if obj and obj.GetRemainingDuration then
            local okr, rem = pcall(obj.GetRemainingDuration, obj)
            if okr then pcall(slot.cdText.SetFormattedText, slot.cdText, "%.0f", rem) end
          end
          slot._lastText = nil   -- the ledger's text repaints once this ends
        else
          slot._fallback = nil

          -- Swipe. TBC: the same (start, duration) pair as the text. Forever:
          -- the client's own duration object is the truth under the ledger's
          -- text and glow (a secret-bearing sink the widget accepts; the ledger
          -- can drift on resets, the swipe cannot). Re-fired only on the
          -- ledger's start edge so the animation does not restart every tick.
          if dispDur and dispDur > 0 and dispRem and dispRem > 0 then
            if dispStart ~= slot._lastCdStart or dispDur ~= slot._lastCdDuration then
              -- (not while the buff is shown: its swipe is the buff's own)
              local durObj = (Nock.Flavor and Nock.Flavor.forever and cd.spellId and not showBuff)
                             and Nock.API.SpellCooldownDuration(cd.spellId) or nil
              if durObj and slot.cooldown.SetCooldownFromDurationObject then
                slot.cooldown:SetCooldownFromDurationObject(durObj)
              else
                slot.cooldown:SetCooldown(dispStart, dispDur)
              end
              slot._lastCdStart    = dispStart
              slot._lastCdDuration = dispDur
            end
          elseif slot._lastCdStart ~= 0 then
            slot.cooldown:Clear()
            slot._lastCdStart    = 0
            slot._lastCdDuration = 0
          end
        end

        local countTxt = (cd.count and cd.count > 0) and tostring(cd.count) or ""
        if countTxt ~= slot._lastCount then
          slot.countText:SetText(countTxt)
          slot._lastCount = countTxt
        end
      end
    end
  end
  if self._gcdDirty then self:FeedGcd(state, p) end
end

-- GCD swipe (gridGcdSwipe): re-fed on SPELL_UPDATE_COOLDOWN and on a
-- rebuild, never per tick. Off: any swipe left over is cleared.
function ReactCooldownsView:OnSpellCooldown() self._gcdDirty = true end

function ReactCooldownsView:FeedGcd(state, p)
  self._gcdDirty = false
  local on = p.gridGcdSwipe == true
  for _, slot in ipairs(self._pool) do
    local entry = slot._entry
    if entry and (on or slot.gcdCd) then
      if on then Nock.UI.EnsureGcdSwipe(slot) end
      local cd = state.cooldowns[entry.key]
      Nock.UI.FeedGcdSwipe(slot, on and cd and cd.spellId or nil, (slot._lastCdStart or 0) ~= 0)
    end
  end
end
