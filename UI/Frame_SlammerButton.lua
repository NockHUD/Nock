-- UI/Frame_SlammerButton.lua
-- The Anetheron button: a secure button that drinks a Sulfuron Slammer on
-- click, wearing whatever state.slammer says — a countdown to the next Sleep,
-- CLICK NOW, the buff's seconds while covered, SLEPT, EXPOSED. Its own frame
-- rather than a warning square because a square cannot be clicked, and its
-- visibility is applied OUT OF COMBAT ONLY: a secure button's Show/Hide/
-- SetPoint/SetSize are protected, and the anchor it hangs on inherits that.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local SlammerButton = Nock:NewModule("SlammerButtonView", "AceEvent-3.0")
local C = Nock.Constants

local MIN_SIZE, MAX_SIZE = 32, 96
local LABEL_GAP = 4
local BAR_GAP   = 3   -- the cast bar sits this far under the icon's edge
-- Icon file for inv_summerfest_firedrink, for the frame the item is not cached.
local FALLBACK_ICON = "Interface\\Icons\\INV_Summerfest_FireDrink"

-- Edge and label colours per state. The verdict tints SLEPT: red when the
-- cast caught you exposed, amber when you were covered and the tick is on
-- its way.
local COLOR = {
  idle    = { 0.45, 0.45, 0.45 },
  wait    = { 0.85, 0.85, 0.85 },
  now     = { 1.00, 0.20, 0.20 },
  covered = { 0.30, 0.90, 0.30 },
  slept   = { 1.00, 0.20, 0.20 },
  sleptOk = { 1.00, 0.70, 0.20 },
  exposed = { 1.00, 0.20, 0.20 },
  casting = { 1.00, 0.20, 0.20 },
  castOk  = { 0.30, 0.90, 0.30 },
  noStock = { 1.00, 0.20, 0.20 },
}

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function itemIcon()
  local id = C.SULFURON_SLAMMER_ITEM
  if C_Item and C_Item.GetItemIconByID then
    local i = C_Item.GetItemIconByID(id)
    if i then return i end
  end
  if GetItemIcon then
    local i = GetItemIcon(id)
    if i then return i end
  end
  return FALLBACK_ICON
end

local function inLockdown()
  return InCombatLockdown and InCombatLockdown()
end

function SlammerButton:OnInitialize()
  -- The anchor is what gets dragged, nudged and shown; the secure button is
  -- its child and fills it. UIParent, not the HUD box: this has to survive
  -- hudEnabled = false, like the banner.
  local a = CreateFrame("Frame", "NockSlammerAnchor", UIParent)
  a:SetMovable(true)
  a:SetClampedToScreen(true)
  a:EnableMouse(false)
  a:RegisterForDrag("LeftButton")
  a:SetScript("OnDragStart", a.StartMoving)
  a:SetScript("OnDragStop", function(fr)
    fr:StopMovingOrSizing()
    local point, _, relPoint, x, y = fr:GetPoint()
    Nock.db.profile.slammerButtonPosition = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  self.anchor = a

  local edge = a:CreateTexture(nil, "BACKGROUND")
  edge:SetColorTexture(1, 1, 1, 1)
  self.edge = edge

  local b = CreateFrame("Button", "NockSlammerButton", a, "SecureActionButtonTemplate")
  b:SetAllPoints(a)
  b:EnableMouse(false)
  -- Press only: a consumable with no cooldown would be drunk TWICE on a
  -- press-and-release registration. The client performs the action on the
  -- press when `useOnKeyDown` says so (see WeaveBind).
  b:RegisterForClicks("AnyDown")
  b:SetAttribute("useOnKeyDown", true)
  b:SetAttribute("type", "item")
  b:SetAttribute("item", "item:" .. C.SULFURON_SLAMMER_ITEM)
  b:SetScript("OnEnter", function(btn)
    if not GameTooltip then return end
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. C.SULFURON_SLAMMER_ITEM)
    if not ok then GameTooltip:SetText("Sulfuron Slammer") end
    GameTooltip:AddLine("Click to drink. The fire-breath tick on yourself breaks Anetheron's Sleep.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  self.button = b

  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(b)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  icon:SetTexture(itemIcon())
  self.icon = icon

  -- Radial swipe: the countdown to the window, the buff, the sleep.
  local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  cd:SetAllPoints(icon)
  if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
  if cd.SetDrawSwipe           then cd:SetDrawSwipe(true)           end
  if cd.SetDrawEdge            then cd:SetDrawEdge(false)           end
  if cd.SetSwipeColor          then cd:SetSwipeColor(0, 0, 0, 0.7)  end
  for _, region in ipairs({ cd:GetRegions() }) do
    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
      region:SetAlpha(0)
      region:Hide()
    end
  end
  cd:EnableMouse(false)
  -- The button draws its own number; keep OmniCC and friends off this swipe
  -- (they key off noCooldownCount) or the seconds paint twice.
  cd.noCooldownCount = true
  self.cooldown = cd

  -- Text layer above the swipe (a Cooldown paints over sibling FontStrings).
  -- A child of the anchor, not the secure button, so nothing about it is
  -- protected.
  local tl = CreateFrame("Frame", nil, a)
  tl:SetAllPoints(a)
  tl:SetFrameLevel(cd:GetFrameLevel() + 2)
  tl:EnableMouse(false)
  self.textLayer = tl

  local label = tl:CreateFontString(nil, "OVERLAY")
  label:SetPoint("BOTTOM", a, "TOP", 0, LABEL_GAP)
  label:SetJustifyH("CENTER")
  self.label = label

  local value = tl:CreateFontString(nil, "OVERLAY")
  value:SetPoint("CENTER", a, "CENTER", 0, 0)
  value:SetTextColor(1, 1, 0.2, 1)
  self.value = value

  local count = tl:CreateFontString(nil, "OVERLAY")
  count:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", -2, 2)
  count:SetTextColor(1, 1, 1, 1)
  self.count = count

  -- The boss's cast, as a bar along the icon's bottom border: fills left to
  -- right over the cast, red while it is the click, green once covered.
  local bar = CreateFrame("StatusBar", nil, tl)
  bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  bar:EnableMouse(false)
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints(bar)
  barBg:SetColorTexture(0, 0, 0, 0.7)
  bar:Hide()
  self.castBar = bar

  Nock.UI.RegisterNudgeable(a, {
    label   = "Slammer button",
    get     = function() return Nock.db.profile.slammerButtonPosition end,
    set     = function(pos)
      Nock.db.profile.slammerButtonPosition = pos
      SlammerButton:ApplyPosition()
    end,
    default = function() return false end,
  })

  self:ApplySize()
  self:ApplyPosition()
  self:ApplyLock()
  a:Hide()

  self:RegisterMessage("NOCK_LOCK_CHANGED", "ApplyLock")
  self:RegisterMessage("NOCK_POSITION_RESET", "ApplyPosition")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyVisuals")
  self:RegisterEvent("PLAYER_REGEN_ENABLED", "ApplyDeferred")
  pcall(self.RegisterEvent, self, "GET_ITEM_INFO_RECEIVED", "OnItemInfo")

  if not Nock.isHunter then a:Hide() end
end

-- /nock slammer item <id>: point the click at another consumable for the
-- session, to prove the secure path (one use per click) without a Slammer in
-- the bag. Out of combat only — attributes are protected. Nil restores.
function SlammerButton:SetItemOverride(id)
  if inLockdown() then return false, "in combat" end
  id = tonumber(id)
  self._itemOverride = id
  self.button:SetAttribute("item", "item:" .. (id or C.SULFURON_SLAMMER_ITEM))
  return true
end

function SlammerButton:OnItemInfo(_, id)
  if tonumber(id) == C.SULFURON_SLAMMER_ITEM then self.icon:SetTexture(itemIcon()) end
end

-- Everything protected goes through here so the combat guard lives in one
-- place: run now out of combat, else remembered for PLAYER_REGEN_ENABLED.
function SlammerButton:ApplyDeferred()
  if inLockdown() then return end
  if self._sizeDirty then self:ApplySize() end
  if self._posDirty  then self:ApplyPosition() end
  if self._lockDirty then self:ApplyLock() end
  if self._visDirty ~= nil then
    local want = self._visDirty
    self._visDirty = nil
    if want then self.anchor:Show() else self.anchor:Hide() end
  end
end

function SlammerButton:ApplySize()
  if inLockdown() then self._sizeDirty = true; return end
  self._sizeDirty = false
  local size = tonumber(profile("slammerButtonSize", 46)) or 46
  if size < MIN_SIZE then size = MIN_SIZE elseif size > MAX_SIZE then size = MAX_SIZE end
  self._sizeApplied = size
  self.anchor:SetSize(size, size)
  self.edge:ClearAllPoints()
  self.edge:SetPoint("TOPLEFT", self.anchor, "TOPLEFT", -2, 2)
  self.edge:SetPoint("BOTTOMRIGHT", self.anchor, "BOTTOMRIGHT", 2, -2)
  local barH = math.max(4, math.floor(size * 0.14))
  self.castBar:ClearAllPoints()
  self.castBar:SetPoint("TOPLEFT",  self.edge, "BOTTOMLEFT",  0, -BAR_GAP)
  self.castBar:SetPoint("TOPRIGHT", self.edge, "BOTTOMRIGHT", 0, -BAR_GAP)
  self.castBar:SetHeight(barH)
  local font = Nock.UI.GetFont() or C.FONT.PATH
  self.label:SetFont(font, math.max(10, math.floor(size * 0.34)), "THICKOUTLINE")
  self.value:SetFont(font, math.max(10, math.floor(size * 0.42)), "OUTLINE")
  self.count:SetFont(font, math.max(8, math.floor(size * 0.26)), "OUTLINE")
end

function SlammerButton:ApplyPosition()
  if inLockdown() then self._posDirty = true; return end
  self._posDirty = false
  local pos = profile("slammerButtonPosition", false)
  local a = self.anchor
  a:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    a:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    a:SetPoint("CENTER", UIParent, "CENTER", 220, 0)
  end
end

function SlammerButton:ApplyVisuals()
  self:ApplySize()
  self._rendered = nil
end

-- Unlocked: the anchor drags and the click is off (or you could not grab it
-- by the icon). Locked: the button takes the click. Both are mouse-state
-- changes on a protected pair, hence the guard.
function SlammerButton:ApplyLock()
  if inLockdown() then self._lockDirty = true; return end
  self._lockDirty = false
  local editable = not Nock.IsLocked()
  self.anchor:EnableMouse(editable)
  self.button:EnableMouse(not editable)
  self._rendered = nil
end

local function setSwipe(cd, dur, left)
  if dur and left and dur > 0 then
    cd:SetCooldown(GetTime() - (dur - left), dur)
  else
    cd:Clear()
  end
end

function SlammerButton:Refresh(state)
  local s = state.slammer
  local now = GetTime()

  -- The size slider is in the warning catalog, whose setter does not
  -- broadcast a visuals change; diff it here like the banner does.
  local size = profile("slammerButtonSize", 46)
  if size ~= self._sizeApplied and not inLockdown() then
    self:ApplySize()
    self._rendered = nil
  end

  -- Visibility: the watcher's wish, or the unlock preview.
  local want = (s.visible or not Nock.IsLocked()) and Nock.isHunter or false
  if want ~= self.anchor:IsShown() then
    if inLockdown() then
      self._visDirty = want
    else
      self._visDirty = nil
      if want then self.anchor:Show() else self.anchor:Hide() end
    end
  end
  if not self.anchor:IsShown() then return end

  local st = s.state or "idle"
  local label = s.label or ""
  local preview = not s.visible   -- unlocked, nothing to show: the idle look
  if preview and st == "idle" then label = "SLAMMER" end

  -- The pulse and the cast bar are the only per-tick paints; everything
  -- else is diffed. The pulse is every click prompt - the open window (the
  -- WA's own prompt; Sleep may have no cast bar) and a cast you are not
  -- covered for - never a cast you already are.
  local clickNow = (st == "now") or (st == "casting" and label ~= "COVERED")
  if clickNow then
    self.edge:SetAlpha(0.55 + 0.45 * math.sin(now * 8))
  end
  if st == "casting" and s.castFrac then
    self.castBar:SetValue(s.castFrac)
  end

  local valueTenths = s.value and math.floor(s.value * 10) or -1
  local key = st .. "|" .. label .. "|" .. tostring(s.verdict) .. "|" .. (s.count or 0) .. "|" .. valueTenths
  if key == self._rendered then return end
  local stateChanged = self._renderedState ~= st
  self._rendered, self._renderedState = key, st

  local col
  if label == "NO SLAMMER" then col = COLOR.noStock
  elseif st == "slept" then col = (s.verdict == "covered") and COLOR.sleptOk or COLOR.slept
  elseif st == "casting" then col = clickNow and COLOR.casting or COLOR.covered
  else col = COLOR[st] or COLOR.idle end

  self.label:SetText(label)
  self.label:SetTextColor(col[1], col[2], col[3], 1)
  self.edge:SetVertexColor(col[1], col[2], col[3], 1)
  if not clickNow then self.edge:SetAlpha(1) end
  if st == "casting" then
    local bc = clickNow and COLOR.casting or COLOR.covered
    self.castBar:SetStatusBarColor(bc[1], bc[2], bc[3], 1)
    self.castBar:Show()
  else
    self.castBar:Hide()
  end

  if s.value then
    self.value:SetText(("%.1f"):format(math.max(0, s.value)))
  else
    self.value:SetText("")
  end
  self.count:SetText((s.count or 0) > 0 and tostring(s.count) or "")

  -- Bright when there is something to do or feel, grey while waiting.
  local bright = (st == "now" or st == "covered" or st == "exposed" or st == "slept"
    or st == "casting" or st == "castOk")
  self.icon:SetDesaturated(not bright and st ~= "idle")
  self.icon:SetAlpha(st == "idle" and 0.6 or 1)

  -- A re-drink while covered refreshes the buff without a state change: the
  -- value jumping up restarts the swipe.
  local lastValue = self._lastValue or -1
  self._lastValue = s.value or -1
  local refreshed = (st == "covered" and s.value and s.value > lastValue + 0.5)
  -- The swipe is the buff (and the sleep) only: a swipe under the countdown
  -- read as a cast bar, and the cast has a bar of its own now.
  if stateChanged or refreshed then
    if st == "covered" or st == "castOk" or (st == "casting" and label == "COVERED") then
      setSwipe(self.cooldown, 6, s.value)
    elseif st == "slept" then
      setSwipe(self.cooldown, 10, s.value)
    else
      self.cooldown:Clear()
    end
  end
end
