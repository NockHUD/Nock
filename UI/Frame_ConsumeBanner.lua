-- UI/Frame_ConsumeBanner.lua
-- The eating / drinking pill: a small centre-screen capsule that is up while
-- the Food and/or Drink aura is on you (state.player.eating / .drinking,
-- written by Modules/Auras.lua) and gone the tick it drops. Each side is the
-- aura's icon under a draining swipe, the word, and the seconds left; the
-- eating side flashes WELL FED in green for a moment when the buff lands so
-- you know you can stand up. Its own frame on UIParent (survives
-- hudEnabled = false), movable + nudgeable, sized from the profile.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ConsumeBanner = Nock:NewModule("ConsumeBannerView", "AceEvent-3.0")
local C = Nock.Constants
local Skin = Nock.Skin

local MIN_SIZE, MAX_SIZE = 20, 64   -- icon edge
local PAD_X, PAD_Y  = 6, 4          -- capsule padding
local GAP           = 6             -- icon → word, seconds → next icon
local WORD_GAP      = 4             -- word → seconds, fixed (user, 2026-09-02)
local FLASH_SECONDS = 1.5           -- WELL FED hold after the food aura ends
local WELL_FED_AT   = 10            -- seconds of eating before a buff food grants Well Fed
local SOLID_TEX     = "Interface\\Buttons\\WHITE8x8"
-- A white antialiased disc (Media/Pill.tga, 48 px, non-power-of-two so no
-- mip blur); the capsule is its left half, a flat middle, its right half.
local PILL_TEX      = "Interface\\AddOns\\Nock\\Media\\Pill.tga"
-- The same disc at 64 px: masks and swipe textures must be power-of-two,
-- the 48 px file sampled as garbage when used as one.
local MASK_TEX      = "Interface\\AddOns\\Nock\\Media\\PillMask.tga"
-- A thin antialiased ring, drawn over the masked icon so its rim reads as
-- a clean circle instead of the icon art's own dark border.
local RING_TEX      = "Interface\\AddOns\\Nock\\Media\\PillRing.tga"

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function skin(name, fallback)
  if Skin and Skin.COLORS and Skin.COLORS[name] then return Skin.COLORS[name] end
  return fallback
end
local COLOR = {
  bg      = skin("surface", { 0.04, 0.04, 0.04 }),
  line    = skin("line",    { 0.15, 0.15, 0.15 }),
  word    = skin("ink",     { 0.95, 0.95, 0.93 }),
  seconds = skin("wait",    { 0.85, 0.72, 0.40 }),
  wellFed = skin("accent",  { 0.67, 0.83, 0.45 }),
  buffRing = skin("multi",  { 1.00, 0.60, 0.20 }),  -- orange rim while eating a buff food
  eatRing  = skin("ink",    { 0.95, 0.95, 0.93 }),  -- white rim, plain food
  drinkRing = skin("steady", { 0.35, 0.65, 1.00 }), -- blue rim, drinking
}

local function setFont(fs, size, flags)
  if Skin and Skin.Font then
    Skin.Font(fs, "monoMedium", size, flags)
  else
    fs:SetFont(C.FONT.PATH, size, flags or "")
  end
end

-- "Well Fed" as the client names it; any hunter food's buff resolves it.
local _wellFedName
local function wellFedName()
  if _wellFedName then return _wellFedName end
  local name
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(33259)
    name = info and info.name
  elseif GetSpellInfo then
    name = GetSpellInfo(33259)
  end
  _wellFedName = name or "Well Fed"
  return _wellFedName
end

-- Well Fed is on you AND was applied after `since` (the meal's start): a
-- buff from an earlier meal must not make a plain snack flash WELL FED.
local function wellFedSince(since)
  local AC = Nock.AuraCache
  local rec = AC and AC.ByName and AC.ByName("player", wellFedName())
  if not (rec and (rec.expirationTime or 0) > GetTime()) then return false end
  local applied = (rec.expirationTime or 0) - (rec.duration or 0)
  return applied >= (since or 0) - 1
end

-- One side of the capsule: icon + swipe, word, seconds.
local function buildSide(parent, word)
  local side = {}
  local icon = parent:CreateTexture(nil, "ARTWORK")
  -- No SetTexCoord trim: the round mask crops the icon's border anyway, and
  -- texcoords on a masked texture are one of the two things that scrambled
  -- the icon into noise here (the other was Texture:SetMask itself).
  -- Round: a mask texture object over the icon, the form LibCustomGlow uses
  -- on this client.
  if parent.CreateMaskTexture and icon.AddMaskTexture then
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    side.mask = mask
  end
  side.icon = icon

  -- The rim is the progress indicator: a faint full-circle track, and over
  -- it a Cooldown whose swipe texture IS the ring, in the side's colour, so
  -- the ring unwinds as the aura runs out while the icon stays untouched.
  local ring = parent:CreateTexture(nil, "OVERLAY")
  ring:SetTexture(RING_TEX)
  ring:SetAllPoints(icon)
  ring:SetVertexColor(COLOR.line[1], COLOR.line[2], COLOR.line[3], 0.9)
  side.ring = ring

  local cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
  cd:SetAllPoints(icon)
  if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
  if cd.SetDrawSwipe   then cd:SetDrawSwipe(true)  end
  if cd.SetDrawEdge    then cd:SetDrawEdge(false)  end
  if cd.SetReverse     then cd:SetReverse(false)   end   -- the ring unwinds as time runs out
  if cd.SetSwipeColor  then cd:SetSwipeColor(COLOR.line[1], COLOR.line[2], COLOR.line[3], 1) end
  if cd.SetSwipeTexture then cd:SetSwipeTexture(RING_TEX) end  -- the swipe draws the ring, not a shade
  for _, region in ipairs({ cd:GetRegions() }) do
    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
      region:SetAlpha(0)
      region:Hide()
    end
  end
  cd:EnableMouse(false)
  cd.noCooldownCount = true
  side.cooldown = cd

  -- No SetText here: a FontString with no font yet throws on SetText, which
  -- aborted OnInitialize once. ApplySize sets the face, paintSide the words.
  local label = parent:CreateFontString(nil, "OVERLAY")
  label:SetTextColor(COLOR.word[1], COLOR.word[2], COLOR.word[3], 1)
  side.label, side.word = label, word

  local seconds = parent:CreateFontString(nil, "OVERLAY")
  seconds:SetTextColor(COLOR.seconds[1], COLOR.seconds[2], COLOR.seconds[3], 1)
  side.seconds = seconds

  -- Under the word, eating only: the countdown to Well Fed for a buff food.
  local sub = parent:CreateFontString(nil, "OVERLAY")
  sub:SetTextColor(COLOR.wellFed[1], COLOR.wellFed[2], COLOR.wellFed[3], 1)
  sub:Hide()
  side.sub = sub

  side.shown = false
  return side
end

local function showSide(side, on)
  if side.shown == on then return end
  side.shown = on
  if on then
    side.icon:Show(); side.ring:Show(); side.cooldown:Show(); side.label:Show(); side.seconds:Show()
  else
    side.icon:Hide(); side.ring:Hide(); side.cooldown:Hide(); side.label:Hide(); side.seconds:Hide()
    side.sub:Hide(); side._subOn = false; side._sub = nil
    side.cooldown:Clear()
    side._swipeKey = nil
  end
end

function ConsumeBanner:OnInitialize()
  local f = CreateFrame("Frame", "NockConsumeBanner", UIParent)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(false)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(fr)
    fr:StopMovingOrSizing()
    local point, _, relPoint, x, y = fr:GetPoint()
    Nock.db.profile.consumeBannerPosition = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  self.frame = f

  -- The capsule: two half-discs and a flat middle, one colour, so the joins
  -- are invisible at any alpha.
  local capL = f:CreateTexture(nil, "BACKGROUND")
  capL:SetTexture(PILL_TEX)
  capL:SetTexCoord(0, 0.5, 0, 1)
  capL:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  capL:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  local capR = f:CreateTexture(nil, "BACKGROUND")
  capR:SetTexture(PILL_TEX)
  capR:SetTexCoord(0.5, 1, 0, 1)
  capR:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  capR:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  local mid = f:CreateTexture(nil, "BACKGROUND")
  mid:SetTexture(SOLID_TEX)
  mid:SetPoint("TOPLEFT", capL, "TOPRIGHT", 0, 0)
  mid:SetPoint("BOTTOMRIGHT", capR, "BOTTOMLEFT", 0, 0)
  self.pill = { capL, mid, capR }
  self:PaintPill(COLOR.bg, 0.85)

  self.eat   = buildSide(f, "EATING")
  self.drink = buildSide(f, "DRINKING")
  -- Default rims: white for food, blue for drink; orange overrides while a
  -- buff food is on its way (paintRing).
  -- (paintRing lives further down the file and is not in scope here; the
  -- first Refresh diffs on _ringBuff, so seed the colours directly.)
  self.eat.ringColor   = COLOR.eatRing
  self.drink.ringColor = COLOR.drinkRing
  for _, side in ipairs({ self.eat, self.drink }) do
    local c = side.ringColor
    if side.cooldown.SetSwipeColor then side.cooldown:SetSwipeColor(c[1], c[2], c[3], 1) end
    side._ringBuff = false
  end
  showSide(self.eat, false)
  showSide(self.drink, false)

  Nock.UI.RegisterNudgeable(f, {
    label   = "Eating / drinking",
    get     = function() return Nock.db.profile.consumeBannerPosition end,
    set     = function(pos)
      Nock.db.profile.consumeBannerPosition = pos
      ConsumeBanner:ApplyPosition()
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

function ConsumeBanner:PaintPill(c, alpha)
  for _, t in ipairs(self.pill) do t:SetVertexColor(c[1], c[2], c[3], alpha) end
end

function ConsumeBanner:ApplySize()
  local size = tonumber(profile("consumeBannerSize", 32)) or 32
  if size < MIN_SIZE then size = MIN_SIZE elseif size > MAX_SIZE then size = MAX_SIZE end
  self._size = size
  -- The caps are half-discs as tall as the capsule.
  local capW = math.floor((size + 2 * PAD_Y) / 2)
  self.pill[1]:SetWidth(capW)
  self.pill[3]:SetWidth(capW)
  local fontSize = math.max(9, math.floor(size * 0.38))
  self._fontSize = fontSize
  for _, side in ipairs({ self.eat, self.drink }) do
    side.icon:SetSize(size, size)
    setFont(side.label, fontSize, "OUTLINE")
    setFont(side.seconds, fontSize, "OUTLINE")
    setFont(side.sub, math.max(8, math.floor(fontSize * 0.8)), "OUTLINE")
  end
  -- Reserve the seconds column for "00s" at this face, no wider.
  self.eat.seconds:SetText("00s")
  self._colW = self.eat.seconds:GetStringWidth()
  self.eat.seconds:SetText("")
  self.eat._secs = nil
  self._layoutKey = nil
end

function ConsumeBanner:ApplyPosition()
  local pos = profile("consumeBannerPosition", false)
  local f = self.frame
  f:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    -- Above the boss banner's spot, which sits at +120.
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
  end
end

function ConsumeBanner:ApplyVisuals()
  self:ApplySize()
end

function ConsumeBanner:ApplyLock()
  local editable = not Nock.IsLocked()
  self.frame:EnableMouse(editable)
  -- No border on a capsule; the unlock tint is the whole pill going green.
  if editable then
    self:PaintPill(C.COLORS.BORDER_UNLOCK, 0.55)
  else
    self:PaintPill(COLOR.bg, 0.85)
  end
end

-- Lays the visible sides out left to right and sizes the capsule. Only runs
-- when which sides are up (or their text widths) changed.
function ConsumeBanner:Layout(eatOn, drinkOn)
  local size = self._size
  -- The icon sits concentric inside the round end: the same inset as the
  -- top and bottom padding.
  local x = PAD_Y
  local f = self.frame
  for _, pair in ipairs({ { self.eat, eatOn }, { self.drink, drinkOn } }) do
    local side, on = pair[1], pair[2]
    if on then
      side.icon:ClearAllPoints()
      side.icon:SetPoint("LEFT", f, "LEFT", x, 0)
      x = x + size + GAP
      side.label:ClearAllPoints()
      side.sub:ClearAllPoints()
      local w = side.label:GetStringWidth()
      if side._subOn then
        -- Two lines: the word above the centre line, the countdown below.
        local half = math.floor(self._fontSize * 0.55)
        side.label:SetPoint("LEFT", f, "LEFT", x, half)
        side.sub:SetPoint("LEFT", f, "LEFT", x, -half)
        w = math.max(w, side.sub:GetStringWidth())
      else
        side.label:SetPoint("LEFT", f, "LEFT", x, 0)
      end
      x = x + w + WORD_GAP
      -- Seconds a fixed WORD_GAP after the word; the column is reserved wide
      -- enough that a digit change never moves anything.
      local colW = math.max(side.seconds:GetStringWidth(), self._colW or 0)
      side.seconds:ClearAllPoints()
      side.seconds:SetPoint("LEFT", f, "LEFT", x, 0)
      side.seconds:SetJustifyH("LEFT")
      x = x + colW + GAP * 2
    end
  end
  -- Right end: the text is square and the cap is round; two paddings clear
  -- the curve at the default size.
  f:SetSize(x - GAP * 2 + PAD_Y * 2, size + 2 * PAD_Y)
end

local function playWellFedSound()
  if not profile("consumeBannerSound", false) then return end
  if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then
    PlaySound(SOUNDKIT.READY_CHECK, "Master")
  end
end

-- Does this food's eating aura grant Well Fed? The client's own spell text
-- says so ("...you will become well fed..."); read once per spell ID and
-- cached. The description can come back empty until the spell is loaded,
-- in which case nothing is cached and the next tick asks again. A locale
-- whose text does not contain the phrase simply never shows the line.
local buffFoodCache = { [-1] = true }   -- the unlock preview's fake buff food
local function foodGivesBuff(spellId)
  if not spellId then return false end
  local cached = buffFoodCache[spellId]
  if cached ~= nil then return cached end
  local desc
  if C_Spell and C_Spell.GetSpellDescription then
    desc = C_Spell.GetSpellDescription(spellId)
  elseif GetSpellDescription then
    desc = GetSpellDescription(spellId)
  end
  if type(desc) ~= "string" or desc == "" then return false end
  local yes = desc:lower():find("well fed", 1, true) ~= nil
  buffFoodCache[spellId] = yes
  return yes
end

-- Seconds since the aura was applied.
local function elapsed(aura, now)
  if not (aura and aura.expirationTime and aura.duration and aura.duration > 0) then return 0 end
  return math.max(0, now - (aura.expirationTime - aura.duration))
end

-- Seconds the aura has left.
local function remaining(aura, now)
  if not (aura and aura.expirationTime and aura.expirationTime > 0) then return 0 end
  return math.max(0, aura.expirationTime - now)
end

-- The swipe covers the whole aura, unless the caller hands in a phase
-- (start, length): a buff food's eating side runs the swipe once over the ten
-- seconds to Well Fed and then again over the rest of the meal.
local function paintSide(side, aura, now, word, color, phaseStart, phaseLen)
  local start, len = aura.expirationTime and (aura.expirationTime - (aura.duration or 0)) or 0,
                     aura.duration or 0
  if phaseStart then start, len = phaseStart, phaseLen end
  local key = (aura.expirationTime or 0) + start
  if side._swipeKey ~= key and len and len > 0 then
    side.cooldown:SetCooldown(start, len)
    side._swipeKey = key
  end
  if aura.icon and aura.icon ~= side._icon then
    side.icon:SetTexture(aura.icon)
    side._icon = aura.icon
  end
  if word ~= side._word then
    side.label:SetText(word)
    local c = color or COLOR.word
    side.label:SetTextColor(c[1], c[2], c[3], 1)
    side._word = word
  end
  local secs = math.ceil(remaining(aura, now))
  if secs ~= side._secs then
    side.seconds:SetText(secs .. "s")
    side._secs = secs
  end
end

-- The icon's rim: orange while a buff food is on its way, the line colour
-- otherwise. Diffed on the boolean.
local function paintRing(side, buffFood)
  if side._ringBuff == buffFood then return end
  side._ringBuff = buffFood
  local c = buffFood and COLOR.buffRing or side.ringColor or COLOR.line
  if side.cooldown.SetSwipeColor then side.cooldown:SetSwipeColor(c[1], c[2], c[3], 1) end
end

-- The eating side's second line: WELL FED IN Ns while a buff food is on its
-- way, WELL FED once the ten seconds are in. Returns true when the line is up
-- (the layout stacks the word over it).
local function paintWellFedLine(side, aura, now)
  local on = aura and foodGivesBuff(aura.spellId) or false
  paintRing(side, on)
  if not on then
    if side._subOn then side.sub:Hide(); side._subOn = false; side._sub = nil end
    return false
  end
  local left = WELL_FED_AT - elapsed(aura, now)
  local txt = (left > 0) and ("WELL FED IN " .. math.ceil(left) .. "s") or "WELL FED"
  if txt ~= side._sub then
    side.sub:SetText(txt)
    side._sub = txt
  end
  if not side._subOn then side.sub:Show(); side._subOn = true end
  return true
end

-- Preview auras for the unlocked edit look (never real).
local PREVIEW_EAT   = { icon = "Interface\\Icons\\INV_Misc_Food_64", expirationTime = 0, duration = 30,
                        spellId = -1 }   -- -1: a fake buff food (see below)
local PREVIEW_DRINK = { icon = "Interface\\Icons\\INV_Drink_18", expirationTime = 0, duration = 30 }

function ConsumeBanner:Refresh(state)
  if not (self.eat and self.drink) then return end
  local p = state.player
  local now = GetTime()
  local unlocked = not Nock.IsLocked()
  local enabled = profile("consumeBannerEnabled", true) and Nock.isHunter

  -- No gates beyond the on/off: eating and drinking are shown wherever they
  -- happen (user, 2026-09-02).
  local eat, drink = p.eating, p.drinking

  -- WELL FED flash: a buff food's aura just ended and a fresh Well Fed is
  -- on you (applied since that meal started).
  if self._hadEat and not eat and not unlocked then
    local last = self._lastEat
    local mealStart = last and last.expirationTime and last.duration
      and (last.expirationTime - last.duration) or 0
    if last and foodGivesBuff(last.spellId) and wellFedSince(mealStart) then
      self._flashUntil = now + FLASH_SECONDS
      self._flashAura  = self._lastEat
      playWellFedSound()
    end
  end
  self._hadEat = eat ~= nil
  if eat then self._lastEat = eat end
  local flashing = self._flashUntil and now < self._flashUntil
  if not flashing then self._flashUntil = nil end

  if unlocked and not eat and not drink and not flashing then
    -- Edit preview: both sides, with a fake 30 s aura started 6 s ago.
    PREVIEW_EAT.expirationTime   = now + 24
    PREVIEW_DRINK.expirationTime = now + 24
    eat, drink = PREVIEW_EAT, PREVIEW_DRINK
  end

  local eatOn   = (eat ~= nil) or flashing
  local drinkOn = drink ~= nil
  local want = enabled and (eatOn or drinkOn)
  if not want then
    if self.frame:IsShown() then
      showSide(self.eat, false); showSide(self.drink, false)
      self.frame:Hide()
    end
    return
  end

  showSide(self.eat, eatOn)
  showSide(self.drink, drinkOn)

  if eatOn then
    if flashing and not eat then
      paintSide(self.eat, self._flashAura or PREVIEW_EAT, now, "WELL FED", COLOR.wellFed)
      self.eat.seconds:SetText("")
      self.eat._secs = nil
    else
      -- A buff food: the swipe tracks the ten seconds to Well Fed, then
      -- restarts over what is left of the meal.
      local ps, pl = nil, nil
      if foodGivesBuff(eat.spellId) and eat.duration and eat.duration > WELL_FED_AT then
        local start = eat.expirationTime - eat.duration
        if now - start < WELL_FED_AT then
          ps, pl = start, WELL_FED_AT
        else
          ps, pl = start + WELL_FED_AT, eat.duration - WELL_FED_AT
        end
      end
      paintSide(self.eat, eat, now, "EATING", COLOR.word, ps, pl)
    end
  end
  local subOn = eatOn and eat ~= nil and paintWellFedLine(self.eat, eat, now)
  if not subOn and self.eat._subOn then
    self.eat.sub:Hide(); self.eat._subOn = false; self.eat._sub = nil
  end
  if not (eatOn and eat) then paintRing(self.eat, false) end
  if drinkOn then paintSide(self.drink, drink, now, "DRINKING", COLOR.word) end

  -- Relayout when the set of sides or a label changed; the seconds column is
  -- reserved wide enough that a digit change never moves anything.
  local layoutKey = (eatOn and "e" or "") .. (drinkOn and "d" or "") .. (self.eat._word or "")
    .. (subOn and "s" or "")
  if layoutKey ~= self._layoutKey then
    self:Layout(eatOn, drinkOn)
    self._layoutKey = layoutKey
  end

  if not self.frame:IsShown() then self.frame:Show() end
end
