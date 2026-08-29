-- UI/Frame_BossBanner.lua
-- The centre-screen alert banner: a large icon and one line of text, up for as
-- long as state.bossMark says a boss has aimed something at you (Teron's
-- Shadow of Death, Archimonde's Air Burst) — or, at lower priority, for as
-- long as state.noRelease says you lie dead with Sated/Exhaustion still on you
-- (DO NOT RELEASE). Its own frame rather than a warning square because 44px in
-- a row of twelve is not what "you have 1.5 seconds" looks like.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local BossBanner = Nock:NewModule("BossBannerView", "AceEvent-3.0")
local C = Nock.Constants

local MIN_SIZE, MAX_SIZE = 48, 200   -- icon edge; the text scales with it

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function fdIcon()
  if C_Spell and C_Spell.GetSpellTexture then
    local tex = C_Spell.GetSpellTexture(C.SpellID.FEIGN_DEATH)
    if tex then return tex end
  end
  if GetSpellTexture then
    local tex = GetSpellTexture(C.SpellID.FEIGN_DEATH)
    if tex then return tex end
  end
  return 132293   -- Ability_Rogue_FeignDeath
end

-- Memoized: the spell DB is static, and this runs inside the render path.
local _satedTex
local function satedIcon()
  if _satedTex then return _satedTex end
  if C_Spell and C_Spell.GetSpellTexture then
    _satedTex = C_Spell.GetSpellTexture(C.SpellID.SATED)
  end
  if not _satedTex and GetSpellTexture then
    _satedTex = GetSpellTexture(C.SpellID.SATED)
  end
  _satedTex = _satedTex or 136090   -- Spell_Nature_Sleep
  return _satedTex
end

function BossBanner:OnInitialize()
  -- UIParent, not the HUD box: a centre-screen alert has to survive
  -- hudEnabled = false, same as the warning row and the tonk dial.
  local f = CreateFrame("Frame", "NockBossBanner", UIParent, "BackdropTemplate")
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(false)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(fr)
    fr:StopMovingOrSizing()
    local point, _, relPoint, x, y = fr:GetPoint()
    Nock.db.profile.bossBannerPosition = { point = point, relPoint = relPoint, x = x, y = y }
  end)

  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("LEFT", f, "LEFT", 0, 0)
  icon:SetTexture(fdIcon())
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  self.icon = icon

  -- A border rather than a filled backdrop: this thing sits over the middle of
  -- the screen during a boss fight and must not hide what is under it.
  local edge = f:CreateTexture(nil, "BACKGROUND")
  edge:SetAllPoints(icon)
  edge:SetColorTexture(1, 0.1, 0.1, 1)
  self.edge = edge

  local text = f:CreateFontString(nil, "OVERLAY")
  text:SetPoint("LEFT", icon, "RIGHT", 14, 0)
  text:SetJustifyH("LEFT")
  text:SetTextColor(1, 0.15, 0.15, 1)
  self.text = text

  self.frame = f

  Nock.UI.RegisterNudgeable(f, {
    label   = "Boss alert",
    get     = function() return Nock.db.profile.bossBannerPosition end,
    set     = function(pos)
      Nock.db.profile.bossBannerPosition = pos
      BossBanner:ApplyPosition()
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

  if not Nock.isHunter then f:Hide() end
end

function BossBanner:ApplySize()
  local size = tonumber(profile("bossBannerSize", 96)) or 96
  if size < MIN_SIZE then size = MIN_SIZE elseif size > MAX_SIZE then size = MAX_SIZE end
  self.icon:SetSize(size, size)
  self.edge:ClearAllPoints()
  self.edge:SetPoint("TOPLEFT", self.icon, "TOPLEFT", -2, 2)
  self.edge:SetPoint("BOTTOMRIGHT", self.icon, "BOTTOMRIGHT", 2, -2)
  self.text:SetFont(Nock.UI.GetFont() or C.FONT.PATH, math.floor(size * 0.42), "THICKOUTLINE")
  -- Width is the icon plus the widest line it will ever hold; the frame only
  -- exists to be dragged and to anchor the two children.
  self.frame:SetSize(size + 14 + math.floor(size * 0.42) * 11, size + 4)
end

function BossBanner:ApplyPosition()
  local pos = profile("bossBannerPosition", false)
  local f = self.frame
  f:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  end
end

function BossBanner:ApplyVisuals()
  self:ApplySize()
  self._rendered = nil
end

-- Unlocked -> grabbable, and held open as an edit preview. A banner that is
-- only up for 2.5 seconds every thirty cannot otherwise be dragged, nudged or
-- even found — the same problem the cast bar and the tonk dial each hit.
function BossBanner:ApplyLock()
  local editable = not Nock.IsLocked()
  self.frame:EnableMouse(editable)
  self._rendered = nil
end

function BossBanner:Refresh(state)
  -- The size slider lives in the warning catalog, whose generic threshold
  -- setter writes the profile key without broadcasting a visuals change. One
  -- table read and a compare per tick is cheaper than making every other
  -- warning's threshold fire a global repaint.
  local size = profile("bossBannerSize", 96)
  if size ~= self._sizeApplied then
    self._sizeApplied = size
    self:ApplySize()
    self._rendered = nil
  end

  -- Source priority: boss mark, then DO NOT RELEASE, then the unlock preview.
  -- The mark can't realistically coexist with lying dead, but the ordering is
  -- explicit anyway.
  local b = state.bossMark
  local nr = state.noRelease
  local source, label
  if b.active then
    source, label = "mark", b.text
  elseif nr and nr.active then
    source, label = "norelease", "DO NOT RELEASE"
  elseif not Nock.IsLocked() then
    source, label = "preview", "FEIGN DEATH NOW"
  end

  -- Source AND label key the diff — labels alone collide (the boss-mark
  -- ready-text and the unlock preview both say FEIGN DEATH NOW). Icons are
  -- resolved after the diff, so the render path pays for none of it while
  -- nothing changes.
  local key = source and (source .. "|" .. label) or false
  if key == self._rendered then return end
  self._rendered = key

  if not source then
    self.frame:Hide()
    return
  end
  self.icon:SetTexture(source == "norelease" and satedIcon() or fdIcon())
  self.text:SetText(label)
  self.frame:Show()
end
