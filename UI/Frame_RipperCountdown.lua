-- UI/Frame_RipperCountdown.lua
-- The Dimensional Ripper / Ultrasafe Transporter countdown: big centre-screen
-- text reading the whole seconds down to the moment to close the client, then
-- ALT F4 in red for the last second. Reads state.ripper (Modules/RipperWatch.lua);
-- its own frame rather than a warning square because 44px in a row of twelve
-- is not what "close the game in one second" looks like.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Ripper = Nock:NewModule("RipperCountdownView", "AceEvent-3.0")
local C = Nock.Constants
local Skin = Nock.Skin

local HINT_HEAD = "Wrong debuff?"
local HINT_W    = 300   -- the subtext's wrap width; the card pads around it

-- One subtext per engineering specialization: the gnomish reset (World
-- Enlarger), the goblin one (arena skirmish), and the pitch for anyone
-- unspecialized.
local HINT_SUBS = {
  gnomish = "Got the small debuff? Get a World Enlarger to remove it and try again",
  goblin  = "Use an arena skirmish to reset your debuffs",
  none    = "No quick reset without a specialization - Gnomish engineers get the World Enlarger, which clears the debuff for another try",
}

-- Which engineering specialization the character has. Owning the BoP World
-- Enlarger is proof of gnomish on its own; otherwise the specialization
-- passives through the IsSpellKnown -> IsPlayerSpell ladder (the Spec row's
-- pattern). A client with neither known-API reads as gnomish -- the card's
-- original text.
local function spellKnown(id)
  if IsSpellKnown then return IsSpellKnown(id) == true end
  if IsPlayerSpell then return IsPlayerSpell(id) == true end
  return nil
end

local function engineerSpec()
  if GetItemCount and (GetItemCount(C.WORLD_ENLARGER_ITEM) or 0) > 0 then return "gnomish" end
  local gnomish = spellKnown(C.SpellID.GNOMISH_ENGINEER)
  if gnomish or gnomish == nil then return "gnomish" end
  if spellKnown(C.SpellID.GOBLIN_ENGINEER) then return "goblin" end
  return "none"
end

local MIN_SIZE, MAX_SIZE = 32, 160   -- the numeral's font size
local PULSE_HZ = 2                   -- the ALT F4 pulse, cycles per second

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

function Ripper:OnInitialize()
  -- UIParent, not the HUD box: a centre-screen alert has to survive
  -- hudEnabled = false, same as the boss banner and the tonk dial.
  local f = CreateFrame("Frame", "NockRipperCountdown", UIParent)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(false)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(fr)
    fr:StopMovingOrSizing()
    local point, _, relPoint, x, y = fr:GetPoint()
    Nock.db.profile.ripperCountdownPosition = { point = point, relPoint = relPoint, x = x, y = y }
  end)

  -- The text is centred on the frame — so the frame's saved position IS the
  -- numeral's centre whatever its width ("9" and "ALT F4" both sit on the
  -- same spot) — and the item's icon hangs off its left edge so the text
  -- says what it is about.
  local text = f:CreateFontString(nil, "OVERLAY")
  text:SetPoint("CENTER", f, "CENTER", 0, 0)
  text:SetJustifyH("CENTER")
  self.text = text

  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("RIGHT", text, "LEFT", -12, 0)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  self.icon = icon

  -- The debuff hint: a workbench-skinned card under the numeral, up for the
  -- whole countdown so the plan is read before the ALT F4 moment.
  local card = CreateFrame("Frame", nil, f)
  card:SetPoint("TOP", text, "BOTTOM", 0, -14)
  Skin.Surface(card, "surface2", "line")

  local head = card:CreateFontString(nil, "OVERLAY")
  head:SetPoint("TOP", card, "TOP", 0, -10)
  Skin.Font(head, "uiBold", 14)
  Skin.Text(head, "ink")
  head:SetText(HINT_HEAD)

  local sub = card:CreateFontString(nil, "OVERLAY")
  sub:SetPoint("TOP", head, "BOTTOM", 0, -4)
  sub:SetWidth(HINT_W)
  sub:SetJustifyH("CENTER")
  Skin.Font(sub, "ui", 12)
  Skin.Text(sub, "ink2")

  self.card, self.hintHead, self.hintSub = card, head, sub
  self:UpdateHint()

  self.frame = f

  Nock.UI.RegisterNudgeable(f, {
    label   = "Ripper countdown",
    get     = function() return Nock.db.profile.ripperCountdownPosition end,
    set     = function(pos)
      Nock.db.profile.ripperCountdownPosition = pos
      Ripper:ApplyPosition()
    end,
    default = function() return false end,
  })

  self:ApplySize()
  self:ApplyPosition()
  self:ApplyLock()
  f:Hide()

  self:RegisterMessage("NOCK_LOCK_CHANGED", "ApplyLock")
  self:RegisterMessage("NOCK_POSITION_RESET", "ApplyPosition")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyVisuals")
end

function Ripper:ApplySize()
  local size = tonumber(profile("ripperTextSize", 72)) or 72
  if size < MIN_SIZE then size = MIN_SIZE elseif size > MAX_SIZE then size = MAX_SIZE end
  self._sizeApplied = size
  self.icon:SetSize(size, size)
  self.text:SetFont(Nock.UI.GetFont() or C.FONT.PATH, size, "THICKOUTLINE")
  -- Wide enough for ALT F4 at this size; the frame only exists to be dragged
  -- and to anchor the two children.
  self.frame:SetSize(size + 12 + math.floor(size * 0.62) * 6, size + 4)
end

function Ripper:ApplyPosition()
  local pos = profile("ripperCountdownPosition", false)
  local f = self.frame
  f:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
  end
end

function Ripper:ApplyVisuals()
  self:ApplySize()
  self:SizeCard()
  self._rendered = nil
end

-- The subtext follows the character's engineering specialization. Recomputed
-- lazily (init, and each time the frame comes up): OnInitialize runs before
-- the spellbook and bags are readable, and a spec learned mid-session should
-- be seen by the next cast.
function Ripper:UpdateHint()
  local sub = HINT_SUBS[engineerSpec()] or HINT_SUBS.gnomish
  if sub == self._hintSet then return end
  self._hintSet = sub
  self.hintSub:SetText(sub)
  self:SizeCard()
end

-- Measured off the rendered strings so the card hugs the wrapped subtext;
-- re-run on visuals changes in case a face was cold at build time.
function Ripper:SizeCard()
  if not self.card then return end
  local h = 10 + self.hintHead:GetStringHeight() + 4 + self.hintSub:GetStringHeight() + 10
  if h < 48 then h = 48 end
  self.card:SetSize(HINT_W + 24, h)
end

-- Unlocked -> grabbable, and held open as an edit preview: a frame that is up
-- for ten seconds once a raid night cannot otherwise be dragged, nudged or
-- even found.
function Ripper:ApplyLock()
  local editable = not Nock.IsLocked()
  self.frame:EnableMouse(editable)
  self._rendered = nil
end

local function itemIcon()
  local id = C.RIPPER_ITEMS[1]
  if C_Item and C_Item.GetItemIconByID then
    local i = C_Item.GetItemIconByID(id)
    if i then return i end
  end
  if GetItemInfo then
    local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
    if icon then return icon end
  end
  return 134376   -- INV_Misc_EngGizmos_17
end

function Ripper:Refresh(state)
  -- The size slider lives in the warning catalog, whose generic threshold
  -- setter writes the profile key without broadcasting a visuals change.
  local size = profile("ripperTextSize", 72)
  if size ~= self._sizeApplied then
    self:ApplySize()
    self._rendered = nil
  end

  local r = state.ripper
  local on = profile("showWarnings", true) ~= false and profile("warnRipperEnabled", true) ~= false
  local label, go, icon
  if on and r.active and r.label then
    label, go, icon = r.label, r.go, r.icon
  elseif not Nock.IsLocked() then
    label, go = "ALT F4", true
  end

  -- The pulse is alpha only, painted per tick while ALT F4 is up; everything
  -- else repaints on a label change.
  if go and label then
    local a = 0.7 + 0.3 * math.abs(math.sin(GetTime() * math.pi * PULSE_HZ))
    self.text:SetAlpha(a)
  end

  local key = label and (label .. "|" .. tostring(go)) or false
  if key == self._rendered then return end
  self._rendered = key

  if not label then
    self.frame:Hide()
    return
  end
  if not self.frame:IsShown() then self:UpdateHint() end
  self.icon:SetTexture(icon or itemIcon())
  self.text:SetText(label)
  if go then
    self.text:SetTextColor(1, 0.15, 0.15, 1)
  else
    self.text:SetAlpha(1)
    self.text:SetTextColor(1, 0.85, 0.2, 1)
  end
  self.frame:Show()
end
