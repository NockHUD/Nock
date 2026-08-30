-- UI/Frame_Misdirect.lua
-- Combined Misdirection panel. Two independently-toggleable sections share one
-- draggable/lockable frame and a consistent row design — [icon][name (left) …
-- countdown (right)]:
--   TOP    — MD cooldown tracker: one row per party/raid hunter, CD bar draining
--            right-to-left, MD icon, name → target, time remaining on the right
--            (data from Modules/Misdirection -> state.misdirection).
--   BOTTOM — click-to-Misdirect: one SECURE button per tank (raid Main-Tank
--            assignment, TANK role, or a manual-list name), class icon +
--            class-coloured name, MD cooldown shown on the right; clicking casts
--            Misdirection on them (data from Modules/MisdirectCast ->
--            state.mdcast). Separated by a divider.
-- Both sections gain a second icon square — the EXPERIMENTAL sapper column —
-- when profile.mdSapperEnabled is on (data from Modules/SapperTracker ->
-- state.sapper). Dim square = no evidence they carry one.
--
-- SECURE CONSTRAINT (clicker rows only): SetAttribute / Show / Hide / SetPoint on
-- the secure tank buttons are protected in combat, so they are wired and
-- positioned ONLY in ConfigureTankRows(), which bails (and sets a dirty flag)
-- during combat and re-runs on PLAYER_REGEN_ENABLED. Tracker rows and the panel
-- chrome are plain frames and update freely every tick.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local MisdirectView = Nock:NewModule("MisdirectView", "AceEvent-3.0")
local C = Nock.Constants

local MAX_TRACKER = 12
local MAX_TANK    = 12

local OUTER   = C.DIM.OUTER_PAD
local INNER   = C.DIM.INNER_GAP
local BAR_H   = C.DIM.CAST_BAR_H
local ROW_GAP = C.DIM.INNER_GAP

local HEADER_TEXT   = "MISDIRECTION"
local HEADER_HEIGHT = 14
local HEADER_FONT   = "Numen"
local HEADER_SIZE   = 11
local HEADER_STYLE  = "THICKOUTLINE"
local SUBHEADER_TEXT = "MISDIRECT TANK"
local SUBHEADER_H    = HEADER_HEIGHT   -- same scale as the main title
local SUBHEADER_SIZE = HEADER_SIZE
local BOTTOM_VPAD    = OUTER   -- symmetric with the side/top gutters

local TIMER_W = 34   -- right-side countdown column inside each bar
local SECTION_GAP = OUTER * 2   -- roomier vertical space around the section divider

-- Tracker row colours (name text + bar tint per phase).
local READY_COLOR  = { 1.00, 1.00, 1.00, 1 }
local CD_COLOR     = { 0.65, 0.65, 0.65, 1 }
local ACTIVE_COLOR = { 0.20, 0.95, 0.40, 1 }
local BAR_READY_TINT  = { 0.30, 0.60, 1.00, 1.00 }
local BAR_ACTIVE_TINT = { 0.10, 0.80, 0.30, 1.00 }
local BAR_CD_TINT     = { 0.50, 0.50, 0.55, 1.00 }

-- Clicker (tank) row tints — distinct violet (Misdirection's pink-purple theme)
-- so the clickable section reads differently from the blue tracker bars above.
local TANK_TINT_READY = { 0.66, 0.40, 0.92, 1.00 }   -- violet = castable
local TANK_TINT_CD    = { 0.42, 0.34, 0.50, 1.00 }   -- muted violet-grey on CD
local SUBHEADER_COLOR = { 0.85, 0.55, 0.95, 1.00 }   -- pink-violet title to match

local TIMER_COLOR = { 0.85, 0.85, 0.90, 1.00 }
local TANK_NAME_COLOR = { 1.00, 1.00, 1.00, 1.00 }   -- white = readable on the violet bar (class is shown by the icon)

-- Panel background DEFAULTS to the shared backdrop (C.COLORS.BG) like every
-- other Nock panel — this one used to override it with a translucent 0.45 and
-- pulse to 0.80 while an MD was up, which made it the odd one out next to the
-- buff panels, so the pulse stays gone. mdBackgroundOpacity (Misdirection
-- tab) re-introduces a STATIC user-set alpha only, default 0.85 = unchanged;
-- ApplyPanelStyle applies it. Row state is carried by the bar tints below.
local DIVIDER_COLOR = { 0.45, 0.45, 0.50, 0.9 }

-- Sapper column (experimental). Dim = we've never seen this person use one, so
-- we have no idea whether they're even an engineer; mid = used, cooling down.
local SAPPER_DIM_ALPHA = 0.25
local SAPPER_CD_ALPHA  = 0.55
local SAPPER_FALLBACK_ICON = "Interface\\Icons\\Spell_Fire_SelfDestruct"

-- Per-hunter "next up in the rotation" button (same experimental flag). Orange
-- so it reads as the one thing on the panel that talks to the raid, and a
-- speaker glyph so it reads as "say this out loud".
-- If the speaker ever renders blank on this client, swap the path for
-- "Interface\\Common\\VoiceChat-On" or an icon such as
-- "Interface\\Icons\\Ability_Warrior_BattleShout" — nothing else depends on it.
local NEXT_UP_TEX    = "Interface\\Common\\VoiceChat-Speaker"
local NEXT_UP_COLOR  = { 1.00, 0.60, 0.10, 1.00 }   -- orange glyph
local NEXT_UP_BORDER = { 1.00, 0.55, 0.05, 1.00 }   -- orange border
local NEXT_UP_BG     = { 0.22, 0.11, 0.00, 0.85 }   -- warm dark fill
local NEXT_UP_HILITE = { 1.00, 0.70, 0.25, 0.28 }   -- hover wash

local SOLID_TEX = "Interface\\Buttons\\WHITE8X8"
-- SQUARE class icons (matches the square MD icon on the tracker rows). Same
-- CLASS_ICON_TCOORDS grid as the round UI-Classes-Circles texture.
local CLASS_ICON_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

-- ---------------------------------------------------------------------------
-- Profile accessors
-- ---------------------------------------------------------------------------
local function isTrackerEnabled()
  local p = Nock.db and Nock.db.profile
  if not p then return true end
  return p.misdirectEnabled ~= false
end
local function isClickerEnabled()
  local p = Nock.db and Nock.db.profile
  if not p then return false end
  return p.mdCastEnabled == true
end
-- EXPERIMENTAL sapper column (Modules/SapperTracker). Off by default.
local function isSapperEnabled()
  local p = Nock.db and Nock.db.profile
  if not p then return false end
  return p.mdSapperEnabled == true
end
local function isLocked()
  return Nock.IsLocked()
end
local function announceOn()
  local p = Nock.db and Nock.db.profile
  if not p then return true end
  return p.mdCastAnnounce ~= false
end
local function widthVal()
  local p = Nock.db and Nock.db.profile
  return (p and p.misdirectWidth) or 200
end
-- The MISDIRECTION title. Default on; hiding it gives its height back to the
-- panel (layoutOffsets) and ApplyPanelStyle toggles the FontString itself.
local function isHeaderShown()
  local p = Nock.db and Nock.db.profile
  if not p then return true end
  return p.mdShowHeader ~= false
end
local function position()
  local p = Nock.db and Nock.db.profile and Nock.db.profile.misdirectPosition
  if p then return p end
  return { point = "CENTER", relPoint = "CENTER", x = 250, y = 0 }
end

local function mdSpellIcon()
  if GetSpellTexture then return GetSpellTexture(34477) end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(34477) end
  return "Interface\\Icons\\Ability_Hunter_Misdirection"
end

-- Localized Misdirection name for the cast macro (/cast needs the client's
-- language, not hardcoded English). Resolved once; falls back to English.
local _mdName
local function mdSpellName()
  if _mdName then return _mdName end
  if GetSpellInfo then
    local n = GetSpellInfo(34477)
    if n then _mdName = n; return n end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(34477)
    if info and info.name then _mdName = info.name; return info.name end
  end
  return "Misdirection"
end

local function groupChannel()
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
  if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
  return nil
end

local function classColor(class)
  local t = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if t then return t.r, t.g, t.b end
  return 1, 1, 1
end

local function shortName(name)
  if not name then return "" end
  return (name:gsub("%-.*$", ""))
end

-- mm:ss for >= 60s, otherwise whole seconds.
local function fmtCD(s)
  s = math.ceil(s or 0)
  if s <= 0 then return "" end
  if s >= 60 then return ("%d:%02d"):format(math.floor(s / 60), s % 60) end
  return tostring(s)
end

-- The square character-create class texture frames each icon with a raised
-- border; crop inward to trim it off for a flat, clean look.
local CLASS_ICON_TRIM = 0.12
local function setClassIcon(tex, class)
  local c = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if c then
    tex:SetTexture(CLASS_ICON_TEX)
    local dx = (c[2] - c[1]) * CLASS_ICON_TRIM
    local dy = (c[4] - c[3]) * CLASS_ICON_TRIM
    tex:SetTexCoord(c[1] + dx, c[2] - dx, c[3] + dy, c[4] - dy)
  else
    tex:SetTexture(mdSpellIcon())
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
end

-- ---------------------------------------------------------------------------
-- Layout math — single source of truth so tracker rows, divider, sub-header
-- and (out-of-combat) tank rows all agree on their Y positions.
-- ---------------------------------------------------------------------------
local OFFSETS = {}   -- reused: this is computed every refresh
local function layoutOffsets(trackerN, tankN, width, showHeader)
  local o = OFFSETS
  o.trackerN, o.tankN, o.width = trackerN, tankN, width
  o.panelW = width + 2 * OUTER

  -- A hidden title (mdShowHeader off) gives its height back to the panel.
  local y = OUTER + (showHeader and (HEADER_HEIGHT + INNER) or 0)
  o.trackerTop = y
  if trackerN > 0 then
    y = y + trackerN * BAR_H + (trackerN - 1) * ROW_GAP
  end

  o.bothVisible = (trackerN > 0 and tankN > 0)
  if o.bothVisible then
    y = y + SECTION_GAP
    o.dividerY = y
    y = y + 1 + SECTION_GAP
  end

  if tankN > 0 then
    o.subHeaderY = y
    y = y + SUBHEADER_H + INNER
    o.tankTop = y
    y = y + tankN * BAR_H + (tankN - 1) * ROW_GAP
  end

  o.panelH = y + BOTTOM_VPAD
  return o
end

-- Split a CreateBar's centred text into a left-justified NAME + a right-justified
-- TIMER column, so both sections share one consistent row anatomy.
local function splitBarText(bar)
  bar.text:ClearAllPoints()
  bar.text:SetPoint("LEFT",  bar, "LEFT", 5, 0)
  bar.text:SetPoint("RIGHT", bar, "RIGHT", -(TIMER_W + 2), 0)
  bar.text:SetJustifyH("LEFT")

  local timer = bar:CreateFontString(nil, "OVERLAY")
  timer:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  timer:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
  timer:SetWidth(TIMER_W)
  timer:SetJustifyH("RIGHT")
  timer:SetTextColor(unpack(TIMER_COLOR))
  bar.timer = timer
  Nock.UI.RegisterFontString(timer, "SIZE_OVERLAY", "OUTLINE")
end

-- ---------------------------------------------------------------------------
-- Row builders
-- ---------------------------------------------------------------------------
-- Icon wrapped in a 1px black-bordered frame (same backdrop as the bars) with
-- the texture inset 1px, so the icon edges match the bar edges.
local function createIcon(parent)
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  frame:SetSize(BAR_H, BAR_H)
  Nock.UI.ApplyBackdrop(frame)
  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT",     frame, "TOPLEFT",      1, -1)
  icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1,  1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:SetTexture(mdSpellIcon())
  return frame, icon
end

-- Sapper square: same 1px-bordered box as createIcon, plus a cooldown swipe.
-- Sits between the leading icon and the bar on both row types when the
-- experimental sapper column is on.
local function createSapperIcon(parent)
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  frame:SetSize(BAR_H, BAR_H)
  Nock.UI.ApplyBackdrop(frame)

  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT",     frame, "TOPLEFT",      1, -1)
  icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1,  1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:SetTexture(SAPPER_FALLBACK_ICON)
  frame.icon = icon

  local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
  cd:SetAllPoints(icon)
  if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
  if cd.SetDrawSwipe           then cd:SetDrawSwipe(true)           end
  if cd.SetDrawEdge            then cd:SetDrawEdge(false)           end
  if cd.SetSwipeColor          then cd:SetSwipeColor(0, 0, 0, 0.75) end
  -- Same belt-and-braces as Nock.UI.CreateIconSlot: kill any FontString the
  -- template made, in case SetHideCountdownNumbers is a no-op on this client.
  for _, region in ipairs({ cd:GetRegions() }) do
    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
      region:SetAlpha(0)
      region:Hide()
    end
  end
  frame.cooldown = cd

  frame:Hide()
  return frame
end

-- "Next up in the rotation" button: a bordered square carrying a chevron, on the
-- right of every hunter row. A plain Button inside a BackdropTemplate Frame
-- rather than a Button *with* that template — same 1px chrome as the icon
-- squares, no assumptions about applying a Frame template to a Button.
-- The hunter it speaks for lives on the outer frame as _hunter.
local function createNextButton(parent)
  -- EVERY visible part is inset 1px from the frame, and that inset is the whole
  -- point. The icon squares beside this one carry a 1px backdrop border that is
  -- BLACK on a black panel — invisible — so what the eye reads as their box is
  -- the 20x20 texture inside it. A full-bleed orange 22x22 square therefore
  -- stood a pixel proud at the top and the bottom of its neighbours even though
  -- every frame was aligned. Orange ring at [1,21], body at [2,20].
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(BAR_H, BAR_H)

  local border = frame:CreateTexture(nil, "BACKGROUND")
  border:SetTexture(SOLID_TEX)
  border:SetPoint("TOPLEFT",     frame, "TOPLEFT",      1, -1)
  border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1,  1)
  border:SetVertexColor(unpack(NEXT_UP_BORDER))

  local fill = frame:CreateTexture(nil, "BORDER")
  fill:SetTexture(SOLID_TEX)
  fill:SetPoint("TOPLEFT",     frame, "TOPLEFT",      2, -2)
  fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2,  2)
  fill:SetVertexColor(unpack(NEXT_UP_BG))

  -- Full-size for a generous hit area; the hover wash is pulled back to the
  -- visible box so it can't light up that outer margin.
  local btn = CreateFrame("Button", nil, frame)
  btn:SetAllPoints(frame)
  btn:SetHighlightTexture(SOLID_TEX)
  local hl = btn:GetHighlightTexture()
  if hl then
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT",     frame, "TOPLEFT",      1, -1)
    hl:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1,  1)
    hl:SetVertexColor(unpack(NEXT_UP_HILITE))
  end

  -- UI glyph, not an ability icon: transparent background, so it gets padding
  -- instead of the usual 0.08-0.92 border crop. 3px in from each side of the
  -- 22px frame = 1px margin + 1px ring + 1px breathing room, and it lands
  -- centred inside the 18x18 body.
  local glyph = btn:CreateTexture(nil, "ARTWORK")
  glyph:SetPoint("TOPLEFT",     frame, "TOPLEFT",      3, -3)
  glyph:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3,  3)
  glyph:SetTexture(NEXT_UP_TEX)
  glyph:SetVertexColor(unpack(NEXT_UP_COLOR))
  frame.glyph = glyph

  -- The message goes to Modules/SapperTracker, which owns every chat line this
  -- feature sends (and the anti-spam window) — the view just reports the press.
  btn:SetScript("OnClick", function(self)
    local name = self:GetParent()._hunter
    if not name then return end
    Nock:SendMessage("NOCK_MD_NEXTUP", name)
  end)
  btn:SetScript("OnEnter", function(self)
    local name = self:GetParent()._hunter
    if not name then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    -- Deliberately not quoting the chat line verbatim: Modules/SapperTracker
    -- owns that wording, and a copy here would drift from it.
    GameTooltip:AddLine("Announce next up in the MD + Sapper rotation", 1, 1, 1)
    GameTooltip:AddLine(shortName(name),
      NEXT_UP_COLOR[1], NEXT_UP_COLOR[2], NEXT_UP_COLOR[3])
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  frame.button = btn
  frame:Hide()
  return frame
end

-- Row anatomy: [icon][sapper?][bar][next?]. Both extra columns belong to the
-- experimental flag, so nobody else pays bar width for them; the next-up button
-- only exists on tracker rows. maxWidth must track the bar's real width or
-- SetBarFill mis-scales.
local function applyRowGeometry(row, width, sapperOn)
  local barLeft  = (BAR_H + INNER) * (sapperOn and 2 or 1)
  local barRight = (sapperOn and row.nextBtn) and (BAR_H + INNER) or 0
  -- Floor guards a stored width small enough for the columns to eat the bar
  -- whole; SetWidth(<=0) is an error, not a no-op.
  local barWidth = math.max(8, width - barLeft - barRight)

  row:SetWidth(width)
  if row.sapper then
    if sapperOn then
      row.sapper:ClearAllPoints()
      row.sapper:SetPoint("TOPLEFT", row, "TOPLEFT", BAR_H + INNER, 0)
      row.sapper:Show()
    else
      row.sapper:Hide()
    end
  end
  if row.nextBtn then
    if sapperOn then
      row.nextBtn:ClearAllPoints()
      row.nextBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
      row.nextBtn:Show()
    else
      row.nextBtn:Hide()
    end
  end

  row.bar:ClearAllPoints()
  row.bar:SetPoint("TOPLEFT",  row, "TOPLEFT",  barLeft,   0)
  row.bar:SetPoint("TOPRIGHT", row, "TOPRIGHT", -barRight, 0)
  row.bar:SetWidth(barWidth)
  row.bar.maxWidth = barWidth - 2
end

-- Paint one sapper square from state.sapper. No entry for that name means we
-- have no evidence they carry one — dim placeholder, so the rows stay aligned
-- and a lit square always means something.
local function updateSapper(square, info, icon)
  if not (square and square:IsShown()) then return end

  if icon and square._icon ~= icon then
    square._icon = icon
    square.icon:SetTexture(icon)
  end

  local known = (info and info.known) and true or false
  local rem   = (info and info.cdRemaining) or 0
  local dur   = (info and info.cdDuration) or 0
  local onCD  = rem > 0

  local sig = (known and 2 or 0) + (onCD and 1 or 0)
  if square._sig ~= sig then
    square._sig = sig
    if square.icon.SetDesaturated then square.icon:SetDesaturated(not known) end
    square:SetAlpha(known and (onCD and SAPPER_CD_ALPHA or 1.0) or SAPPER_DIM_ALPHA)
  end

  if onCD and dur > 0 then
    local start = GetTime() - (dur - rem)
    -- Re-arming the swipe every tick restarts the animation; only do it when
    -- this is genuinely a different cooldown.
    if not square._cdStart or math.abs(square._cdStart - start) > 0.5 or square._cdDur ~= dur then
      square._cdStart, square._cdDur = start, dur
      square.cooldown:SetCooldown(start, dur)
    end
  elseif square._cdStart then
    square._cdStart, square._cdDur = nil, nil
    if square.cooldown.Clear then square.cooldown:Clear() else square.cooldown:SetCooldown(0, 0) end
  end
end

local function createTrackerRow(panel, width)
  local f = CreateFrame("Frame", nil, panel)
  f:SetSize(width, BAR_H)

  local iconFrame, icon = createIcon(f)
  iconFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.icon = icon

  -- Remaining MD charges (3→1), bottom-right on the icon like a buff stack
  -- count. Painted in Refresh while the row is in its active phase.
  local count = iconFrame:CreateFontString(nil, "OVERLAY")
  count:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  count:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
  count:SetTextColor(1, 1, 1, 1)
  Nock.UI.RegisterFontString(count, "SIZE_OVERLAY", "OUTLINE")
  f.iconCount = count

  f.sapper  = createSapperIcon(f)
  f.nextBtn = createNextButton(f)

  local bar = Nock.UI.CreateBar(f, nil, width - BAR_H - INNER, BAR_H, BAR_READY_TINT)
  Nock.UI.SetBarFill(bar, 1)
  splitBarText(bar)
  f.bar = bar

  applyRowGeometry(f, width, false)
  return f
end

local function createTankRow(self, panel, width, index)
  -- Secure button: the whole row is clickable; child icon/bar have mouse
  -- disabled so the click falls through to the button.
  local row = CreateFrame("Button", "NockMDCastRow" .. index, panel, "SecureActionButtonTemplate")
  row:SetSize(width, BAR_H)
  row:EnableMouse(true)
  -- This client performs the secure action on the PRESS phase; registering only
  -- "AnyUp" left the cast unfired. Register both so it casts regardless of phase.
  row:RegisterForClicks("AnyDown", "AnyUp")
  -- [@unit] and the secure type=spell "unit" attribute are both broken on this
  -- client; the old-style [target=unit] macro works, so cast via macrotext.
  row:SetAttribute("type", "macro")

  local iconFrame, icon = createIcon(row)
  iconFrame:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.icon = icon

  row.sapper = createSapperIcon(row)

  local bar = Nock.UI.CreateBar(row, nil, width - BAR_H - INNER, BAR_H, TANK_TINT_READY)
  Nock.UI.SetBarFill(bar, 1)
  splitBarText(bar)
  row.bar = bar

  applyRowGeometry(row, width, false)

  -- Hover highlight: a dedicated overlay frame ABOVE the icon/bar children (a
  -- plain HIGHLIGHT texture on the button is hidden behind those child frames).
  -- Toggled manually in OnEnter/OnLeave.
  local hover = CreateFrame("Frame", nil, row)
  hover:SetFrameLevel(row:GetFrameLevel() + 20)
  hover:SetAllPoints(row)
  hover:EnableMouse(false)
  local htex = hover:CreateTexture(nil, "OVERLAY")
  htex:SetTexture(SOLID_TEX)
  htex:SetVertexColor(0.85, 0.70, 1.00, 0.22)
  htex:SetAllPoints(hover)
  hover:Hide()
  row.hover = hover

  row:SetScript("OnEnter", function(s)
    if not s._tankName then return end
    s.hover:Show()
    local p = Nock.db and Nock.db.profile
    if not (p and p.mdCastTooltip) then return end   -- tooltip is opt-in
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:AddLine("Click to Misdirect", 1, 1, 1)
    GameTooltip:AddLine(shortName(s._tankName), classColor(s._class))
    if not self._tankReady then
      GameTooltip:AddLine("On cooldown: " .. fmtCD(self._tankCD), 0.8, 0.5, 0.5)
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function(s)
    s.hover:Hide()
    GameTooltip:Hide()
  end)

  -- Record the intended tank BEFORE the secure action fires. The actual announce
  -- is deferred to UNIT_SPELLCAST_SUCCEEDED (see below) so a click that never
  -- lands (out of range, LoS, moving) does not announce. PreClick is guaranteed
  -- to run before the (asynchronous) success event.
  row:SetScript("PreClick", function(s)
    self._pendingAnnounce = s._tankName and { name = s._tankName, t = GetTime() } or nil
  end)

  row:SetScript("PostClick", function(s)
    local p = Nock.db and Nock.db.profile
    if p and p.mdCastDebug then
      Nock:Print(("MDCast click: macro=[%s]  ready=%s"):format(
        tostring(s._macro), tostring(self._tankReady)))
    end
  end)

  row:Hide()
  return row
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
function MisdirectView:OnInitialize()
  local panel = CreateFrame("Frame", "NockMisdirect", UIParent, "BackdropTemplate")
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    Nock.db.profile.misdirectPosition = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  Nock.UI.ApplyUserPanelStyle(panel, "md", "mdBackgroundOpacity")
  panel:Hide()

  Nock.UI.RegisterNudgeable(panel, {
    label   = "Misdirection",
    secure  = true,   -- parents secure click-cast rows; SetPoint blocked in combat
    get     = function() return Nock.db.profile.misdirectPosition end,
    set     = function(pos)
      Nock.db.profile.misdirectPosition = pos
      MisdirectView:ApplyPosition()
    end,
    default = function() return Nock.Defaults.profile.misdirectPosition end,
  })

  local header = panel:CreateFontString(nil, "OVERLAY")
  Nock.UI.RegisterHeaderFontString(header, HEADER_FONT, HEADER_SIZE, HEADER_STYLE)
  header:SetPoint("TOPLEFT",  panel, "TOPLEFT",   OUTER, -OUTER)
  header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -OUTER, -OUTER)
  header:SetHeight(HEADER_HEIGHT)
  header:SetJustifyH("CENTER")
  header:SetJustifyV("MIDDLE")
  header:SetTextColor(1, 1, 1, 1)
  header:SetText(HEADER_TEXT)
  panel.header = header

  local divider = panel:CreateTexture(nil, "ARTWORK")
  divider:SetTexture(SOLID_TEX)
  divider:SetVertexColor(unpack(DIVIDER_COLOR))
  divider:SetHeight(1)
  divider:Hide()
  self.divider = divider

  local sub = panel:CreateFontString(nil, "OVERLAY")
  Nock.UI.RegisterHeaderFontString(sub, HEADER_FONT, SUBHEADER_SIZE, HEADER_STYLE)
  sub:SetHeight(SUBHEADER_H)
  sub:SetJustifyH("CENTER")
  sub:SetJustifyV("MIDDLE")
  sub:SetTextColor(unpack(SUBHEADER_COLOR))
  sub:SetText(SUBHEADER_TEXT)
  sub:Hide()
  self.subHeader = sub

  self.panel       = panel
  self.trackerRows = {}
  self.tankRows    = {}
  self._tanks      = {}
  self._trackerN   = 0
  self._dirty      = false
  self._tankReady  = true
  self._tankCD     = 0
  self._lastTankReady = nil
  self._lastTankSec   = nil
  self._sig        = nil

  local w = widthVal()
  for i = 1, MAX_TRACKER do
    local row = createTrackerRow(panel, w)
    self.trackerRows[i] = row
    row:Hide()
  end
  for i = 1, MAX_TANK do
    self.tankRows[i] = createTankRow(self, panel, w, i)
  end

  self:ApplyTrackerGeometry()
  self:ApplyPosition()
  self:ApplyLock()

  self:ApplyPanelStyle()
  self:RegisterMessage("NOCK_MDCAST_ROSTER",      "OnRoster")
  self:RegisterMessage("NOCK_VISUALS_CHANGED",    "OnVisualsChanged")
  self:RegisterMessage("NOCK_LOCK_CHANGED",       "ApplyLock")
  self:RegisterMessage("NOCK_MD_POSITION_RESET",  "ApplyPosition")
  self:RegisterMessage("NOCK_POSITION_RESET",     "ApplyPosition")  -- profile switch
  self:RegisterEvent("PLAYER_REGEN_ENABLED",      "OnRegenEnabled")
  -- Announce fires on the confirmed cast, not the click (see Announce below).
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

function MisdirectView:ApplyPosition()
  -- The panel is protected once secure tank rows anchor to it — SetPoint in
  -- combat is a blocked action. Reachable in combat via profile switch or
  -- /nock reset, so defer exactly like ApplyLock does.
  if InCombatLockdown() then
    self._posDirty = true
    return
  end
  self._posDirty = false
  local p = position()
  self.panel:ClearAllPoints()
  self.panel:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
end

function MisdirectView:ApplyLock()
  local locked = isLocked()
  -- Tracker rows are plain frames, so their next-up buttons can be muted any
  -- time. They must stop taking clicks while unlocked or you can't drag the
  -- panel by that corner.
  for _, row in ipairs(self.trackerRows) do
    if row.nextBtn then row.nextBtn.button:EnableMouse(locked) end
  end
  if InCombatLockdown() then
    -- The panel is protected (secure children) and the tank rows are secure:
    -- no mouse-state changes in combat; retry the whole thing on regen.
    self._lockDirty = true
  else
    self._lockDirty = false
    self.panel:EnableMouse(not locked)
    for _, row in ipairs(self.tankRows) do row:EnableMouse(locked) end
  end
  self:ApplyPanelStyle()
end

-- Tracker rows are plain frames parented to the panel, so their geometry is
-- safe to touch any time; the tank rows are secure and go through
-- ConfigureTankRows instead.
function MisdirectView:ApplyTrackerGeometry()
  local w = widthVal()
  local sapperOn = isSapperEnabled()
  self._sapperOn = sapperOn
  for _, row in ipairs(self.trackerRows) do
    applyRowGeometry(row, w, sapperOn)
  end
end

-- Backdrop fill + border + title visibility, shared by ApplyLock and
-- OnVisualsChanged. The border read lives in ApplyUserPanelStyle — don't
-- re-derive it here (drift hazard); the green drag-cue border is re-applied
-- on top while unlocked, full-strength regardless of the user's style, so a
-- panel you're trying to reposition stays findable. None of this is a
-- protected action (ApplyUserPanelStyle touches only backdrop textures, and
-- a child FontString's Show/Hide is safe in combat — unlike the panel's own
-- Size/Point/Show/Hide above), so no lockdown guard. The layout consequences
-- of a header toggle go through layoutOffsets' showHeader flag on the next
-- Refresh / ConfigureTankRows pass.
function MisdirectView:ApplyPanelStyle()
  Nock.UI.ApplyUserPanelStyle(self.panel, "md", "mdBackgroundOpacity")
  if not isLocked() then
    self.panel:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  end
  self.panel.header:SetShown(isHeaderShown())
end

function MisdirectView:OnVisualsChanged()
  self:ApplyPanelStyle()
  self:ApplyTrackerGeometry()
  self._sig = nil
  self:ConfigureTankRows()
end

function MisdirectView:OnRoster(_, tanks)
  self._tanks = tanks or {}
  self._sig = nil
  self:ConfigureTankRows()
end

function MisdirectView:OnRegenEnabled()
  if self._dirty then self:ConfigureTankRows() end
  if self._lockDirty then self:ApplyLock() end
  if self._posDirty then self:ApplyPosition() end
end

-- ---------------------------------------------------------------------------
-- Tank (secure) row wiring + positioning. OUT OF COMBAT ONLY.
-- ---------------------------------------------------------------------------
function MisdirectView:ConfigureTankRows()
  if InCombatLockdown() then
    self._dirty = true
    return
  end
  self._dirty = false

  local clickerOn = isClickerEnabled()
  local tankN = clickerOn and math.min(#self._tanks, MAX_TANK) or 0
  local w = widthVal()
  local sapperOn = isSapperEnabled()
  local o = layoutOffsets(self._trackerN, tankN, w, isHeaderShown())
  local locked = isLocked()

  for i = 1, MAX_TANK do
    local row = self.tankRows[i]
    local t = self._tanks[i]
    if i <= tankN and t then
      applyRowGeometry(row, w, sapperOn)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", self.panel, "TOPLEFT", OUTER,
        -(o.tankTop + (i - 1) * (BAR_H + ROW_GAP)))

      -- [target=unit] (old-style) works on this client where [@unit] does not.
      row._tankName = t.name
      row._class    = t.class
      -- state.sapper is keyed by short name; tank names carry the realm.
      row._sapperKey = shortName(t.name)
      row._macro = ("/cast [target=%s] %s"):format(t.unit, mdSpellName())
      row:SetAttribute("macrotext", row._macro)
      row:EnableMouse(locked)

      setClassIcon(row.icon, t.class)
      Nock.UI.SetBarFill(row.bar, 1)
      row.bar.text:SetText(shortName(t.name))
      row.bar.text:SetTextColor(unpack(TANK_NAME_COLOR))
      row:Show()
    else
      row._tankName  = nil
      row._sapperKey = nil
      row:Hide()
    end
  end

  self._lastTankReady = nil
  self._lastTankSec   = nil
end

-- ---------------------------------------------------------------------------
-- Announce, driven by the confirmed cast. A click stashes the intended tank
-- (PreClick); UNIT_SPELLCAST_SUCCEEDED for the player's Misdirection flushes it,
-- so a click that never lands (range/LoS/moving/on CD) never announces. The
-- success event carries no MD target, hence the pending-tank hand-off.
-- ---------------------------------------------------------------------------
local ANNOUNCE_WINDOW = 3   -- seconds a pending click stays valid

function MisdirectView:UNIT_SPELLCAST_SUCCEEDED(_, unit, arg1, arg2)
  if unit ~= "player" then return end
  local isMD = (type(arg2) == "number" and arg2 == C.SpellID.MISDIRECTION)
            or (type(arg1) == "string" and arg1 == mdSpellName())
  if not isMD then return end
  local pend = self._pendingAnnounce
  self._pendingAnnounce = nil
  if not pend then return end
  if (GetTime() - pend.t) > ANNOUNCE_WINDOW then return end
  self:Announce(pend.name)
end

local _lastAnnounce = {}
function MisdirectView:Announce(tankName)
  if not tankName then return end
  if not announceOn() then return end

  local now = GetTime()
  if _lastAnnounce[tankName] and (now - _lastAnnounce[tankName]) < 3 then return end
  _lastAnnounce[tankName] = now

  local msg = ("Misdirection -> %s"):format(shortName(tankName))
  local ch = groupChannel()
  if ch and SendChatMessage then
    SendChatMessage(msg, ch)
  else
    Nock:Print(msg)
  end
end

-- ---------------------------------------------------------------------------
-- /nock mdgeom — pixel forensics for one tracker row. Prints every part in UI
-- units AND in physical pixels, because at a non-integer effective scale a
-- frame's physical edge lands on a fraction and each neighbour rounds
-- independently: that reads as "1px off" and no amount of anchor arithmetic
-- fixes it. Also reports whether the glyph texture actually resolved.
-- ---------------------------------------------------------------------------
function MisdirectView:DumpGeometry()
  local row = self.trackerRows and self.trackerRows[1]
  if not (row and row:IsShown()) then
    Nock:Print("MD geom: no visible tracker row — needs a hunter in the group and the tracker section on.")
    return
  end

  local scale = row:GetEffectiveScale() or 1
  Nock:Print(("MD geom: effScale=%.4f  UIParent=%.4f  BAR_H=%d  INNER=%d  width=%d")
    :format(scale, UIParent:GetEffectiveScale(), BAR_H, INNER, widthVal()))

  local function dump(label, f)
    if not f then Nock:Print(("%-8s nil"):format(label)); return end
    if not f.GetRect then Nock:Print(("%-8s no GetRect"):format(label)); return end
    local l, b, w, h = f:GetRect()
    if not l then Nock:Print(("%-8s unpositioned"):format(label)); return end
    -- Physical edges: a .5 here on one element and .0 on its neighbour is the
    -- whole bug.
    Nock:Print(("%-8s w=%.2f h=%.2f | px L=%.2f R=%.2f T=%.2f B=%.2f"):format(
      label, w, h, l * scale, (l + w) * scale, (b + h) * scale, b * scale))
  end

  dump("row",     row)
  dump("iconbox", row.icon and row.icon:GetParent())
  dump("icontex", row.icon)
  dump("sapper",  row.sapper)
  dump("bar",     row.bar)
  dump("nextbox", row.nextBtn)
  dump("glyph",   row.nextBtn and row.nextBtn.glyph)

  local g = row.nextBtn and row.nextBtn.glyph
  Nock:Print(("glyph texture: %s"):format(tostring(g and g:GetTexture())))
end

-- ---------------------------------------------------------------------------
-- Tracker sort (active first, then by CD, then recency, then name)
-- ---------------------------------------------------------------------------
-- One reused scratch list and a module-level comparator: this runs ten times
-- a second for the whole raid night whenever another hunter is in the group.
local SORTED = {}
local function hunterLess(a, b)
  if a.isActive ~= b.isActive then return a.isActive end
  if (a.cdRemaining > 0) ~= (b.cdRemaining > 0) then return a.cdRemaining > 0 end
  if (a.castTime or 0) ~= (b.castTime or 0) then return (a.castTime or 0) > (b.castTime or 0) end
  return (a.name or "") < (b.name or "")
end
local function sortedHunters(hunters)
  local list = SORTED
  local n = 0
  if hunters then
    for _, h in pairs(hunters) do n = n + 1; list[n] = h end
  end
  for i = #list, n + 1, -1 do list[i] = nil end
  table.sort(list, hunterLess)
  return list
end

-- ---------------------------------------------------------------------------
-- Central-tick repaint
-- ---------------------------------------------------------------------------
-- Slow lane (Core:Tick): the MD tracker + tank roster change on roster/cast
-- events and a 30s MD window, not per frame. Throttling also cuts how often the
-- in-combat geometry guards on the secure tank buttons are exercised.
MisdirectView.refreshInterval = 0.1

function MisdirectView:Refresh(state)
  -- "Hide out of combat" (General -> Visibility) puts the whole panel away
  -- while RESTED — an inn or a city. Rested transitions happen out of combat,
  -- so the protected Hide/Show is allowed; the lockdown guard is for the odd
  -- city duel, where the panel simply waits for the next regen.
  if Nock.RestedHideApplies(Nock.db and Nock.db.profile, IsResting and IsResting(), state) then
    if self.panel:IsShown() and not InCombatLockdown() then self.panel:Hide() end
    self._trackerN = 0
    return
  end

  local trackerOn = isTrackerEnabled()
  local hunters = trackerOn and state.misdirection and state.misdirection.hunters or nil
  local hlist = sortedHunters(hunters)
  local trackerN = math.min(#hlist, MAX_TRACKER)

  local clickerOn = isClickerEnabled()
  local tankN = clickerOn and self._tanks and math.min(#self._tanks, MAX_TANK) or 0

  -- The experimental sapper column changes the row anatomy. Catch it here as
  -- well as on NOCK_VISUALS_CHANGED so a profile switch can't leave the rows
  -- laid out for the other setting.
  local sapperOn = isSapperEnabled()
  if sapperOn ~= self._sapperOn then
    self:ApplyTrackerGeometry()
    self._sig = nil
  end
  local sapperInfo = sapperOn and state.sapper or nil
  local sapperByName = sapperInfo and sapperInfo.byName or nil
  local sapperIcon = sapperInfo and sapperInfo.icon or nil

  if trackerN == 0 and tankN == 0 then
    -- Hide is protected (secure rows anchored to the panel); skip under lockdown.
    if self.panel:IsShown() and not InCombatLockdown() then self.panel:Hide() end
    self._trackerN = 0
    return
  end

  local width = widthVal()
  local hdr = isHeaderShown()
  local o = layoutOffsets(trackerN, tankN, width, hdr)
  -- SetSize is protected here: the secure tank rows anchor to the panel, so the
  -- panel counts as protected and resizing it in combat is blocked
  -- (ADDON_ACTION_BLOCKED). Panel dimensions only change with roster/config,
  -- which are stable during combat, so skip it under lockdown; the next
  -- central-tick Refresh after PLAYER_REGEN_ENABLED re-applies the correct size.
  if not InCombatLockdown() then
    self.panel:SetSize(o.panelW, o.panelH)
  end

  -- Tracker rows -----------------------------------------------------------
  for i = 1, MAX_TRACKER do
    local row = self.trackerRows[i]
    local h = hlist[i]
    if i <= trackerN and h then
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", self.panel, "TOPLEFT", OUTER,
        -(o.trackerTop + (i - 1) * (BAR_H + ROW_GAP)))

      local phase
      if h.isActive then phase = "active"
      elseif h.cdRemaining > 0 then phase = "cd"
      else phase = "ready" end

      local fill, tint, color, label
      if phase == "active" then
        fill  = (h.cdDuration > 0) and (h.cdRemaining / h.cdDuration) or 1
        tint, color = BAR_ACTIVE_TINT, ACTIVE_COLOR
        label = h.target and (h.name .. "  ->  " .. h.target) or h.name
      elseif phase == "cd" then
        fill  = (h.cdDuration > 0) and (h.cdRemaining / h.cdDuration) or 0
        tint, color = BAR_CD_TINT, CD_COLOR
        label = h.target and (h.name .. "  ->  " .. h.target) or h.name
      else
        fill, tint, color = 1, BAR_READY_TINT, READY_COLOR
        label = h.name
      end
      Nock.UI.SetBarFill(row.bar, fill)
      if row._tint ~= tint then
        row._tint = tint
        row.bar.fill:SetVertexColor(tint[1], tint[2], tint[3], tint[4])
      end
      if row._label ~= label then
        row._label = label
        row.bar.text:SetText(label)
      end
      if row._color ~= color then
        row._color = color
        row.bar.text:SetTextColor(color[1], color[2], color[3], color[4])
      end
      local timer = (phase ~= "ready") and fmtCD(h.cdRemaining) or ""
      if row._timer ~= timer then
        row._timer = timer
        row.bar.timer:SetText(timer)
      end
      -- Charge count rides the icon only while active; h.charges is nil when
      -- the buff reports no count, and then nothing renders.
      local ch = (phase == "active") and h.charges or nil
      if ch ~= row._charges then
        row._charges = ch
        row.iconCount:SetText(ch and tostring(ch) or "")
      end
      updateSapper(row.sapper, sapperByName and sapperByName[h.name], sapperIcon)
      row.nextBtn._hunter = h.name
      if not row:IsShown() then row:Show() end
    else
      row.nextBtn._hunter = nil
      if row:IsShown() then row:Hide() end
    end
  end

  -- Divider + sub-header ---------------------------------------------------
  if o.bothVisible then
    self.divider:ClearAllPoints()
    self.divider:SetPoint("TOPLEFT",  self.panel, "TOPLEFT",  OUTER, -o.dividerY)
    self.divider:SetPoint("TOPRIGHT", self.panel, "TOPRIGHT", -OUTER, -o.dividerY)
    self.divider:Show()
  else
    self.divider:Hide()
  end

  if tankN > 0 then
    self.subHeader:ClearAllPoints()
    self.subHeader:SetPoint("TOPLEFT",  self.panel, "TOPLEFT",  OUTER, -o.subHeaderY)
    self.subHeader:SetPoint("TOPRIGHT", self.panel, "TOPRIGHT", -OUTER, -o.subHeaderY)
    self.subHeader:Show()
  else
    self.subHeader:Hide()
  end

  -- Tank rows: reposition/re-wire only when the structural layout changes.
  -- The signature is one number (no scratch table + string per refresh).
  self._trackerN = trackerN
  local sig = trackerN + tankN * 100 + width * 10000
    + (isLocked() and 1e8 or 0) + (sapperOn and 2e8 or 0) + (hdr and 4e8 or 0)
  if sig ~= self._sig then
    self._sig = sig
    self:ConfigureTankRows()
  end

  -- Tank cosmetics: tint/alpha on ready-flip; countdown text once per second.
  self._tankReady = not (state.mdcast and state.mdcast.ready == false)
  self._tankCD    = (state.mdcast and state.mdcast.cdRemaining) or 0
  if self._tankReady ~= self._lastTankReady then
    self._lastTankReady = self._tankReady
    local tint  = self._tankReady and TANK_TINT_READY or TANK_TINT_CD
    local alpha = self._tankReady and 1.0 or 0.7
    for _, row in ipairs(self.tankRows) do
      if row:IsShown() then
        row.bar.fill:SetVertexColor(unpack(tint))
        row:SetAlpha(alpha)
      end
    end
  end
  -- Tank sapper squares. Their own cooldown is nothing to do with MD's, so this
  -- runs every pass; updateSapper early-outs when a square hasn't changed.
  if sapperOn then
    for _, row in ipairs(self.tankRows) do
      if row:IsShown() and row._sapperKey then
        updateSapper(row.sapper, sapperByName and sapperByName[row._sapperKey], sapperIcon)
      end
    end
  end

  local sec = math.ceil(self._tankCD)
  if sec ~= self._lastTankSec then
    self._lastTankSec = sec
    local txt = (self._tankCD > 0) and fmtCD(self._tankCD) or ""
    for _, row in ipairs(self.tankRows) do
      if row:IsShown() then row.bar.timer:SetText(txt) end
    end
  end

  -- Show is protected (secure rows anchored to the panel); skip under lockdown.
  -- Panel visibility is roster-driven (stable in combat), so if it needs to
  -- appear it will on the first Refresh after combat ends.
  if not self.panel:IsShown() and not InCombatLockdown() then self.panel:Show() end
end
