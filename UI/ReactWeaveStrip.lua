-- UI/ReactWeaveStrip.lua
-- The Forever weave strip: Auto Shot icon with the ranged-swing swipe, a glide bar fed by the weave helper, Raptor icon with its cooldown swipe.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
Nock.UI = Nock.UI or {}
local WS = {}
Nock.UI.WeaveStrip = WS

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
WS.COLORS = {
  dead    = { 0.48, 0.13, 0.15, 1 },   -- the fill while a leg crosses the dead zone
  melee   = { 0.68, 0.18, 0.20, 1 },   -- in melee (the ladder's melee red)
  ranged  = { 0.11, 0.70, 0.67, 1 },   -- in range (the ladder's teal)
  off     = { 0.16, 0.16, 0.16, 1 },   -- no target
  stale   = { 1.00, 0.58, 0.10, 1 },   -- the leg ran past its estimate (the TBC RESYNC orange)
  overshot = { 1.00, 0.72, 0.20, 1 },  -- backed out past the rest band (item 9606)
  go      = { 0.20, 0.90, 0.30, 1 },
  wait    = { 1.00, 0.72, 0.10, 1 },
  strike  = { 1.00, 0.35, 0.29, 1 },
  out     = { 0.40, 0.70, 1.00, 1 },
  release = { 0.55, 1.00, 0.61, 1 },
  border  = { 0.00, 0.00, 0.00, 1 },
  glow    = { 0.20, 0.90, 0.30, 1 },   -- the icon that wants pressing
}
WS.LABELS = { MELEE = "MELEE", CLOSE = "DEAD ZONE", SWEET = "RANGED", LONG = "" }
WS.FLASH_SEC = 0.4
local STAGE_BORDER = { GO = "go", IN = "go", WAIT = "wait", STRIKE = "strike", OUT = "out", RELEASE = "release" }

-- Pure: what the strip draws for this state. `out` is reused.
--   shown      a live hostile target with a zone
--   fill       0..1, the glide (0 = the ranged end, 1 = the melee end)
--   fillKey    WS.COLORS key of the fill
--   borderKey  WS.COLORS key of the bar's border (the stage, stale first)
--   label      the zone's word inside the bar
--   asGlow / rsGlow   the icon that wants pressing
--   flash      0..1 RELEASE brightness
function WS.Look(state, now, out)
  out = out or {}
  local t, w = state and state.target, state and state.weave
  local live = t and t.exists == true and t.alive == true and t.friendly ~= true and t.rangeState ~= nil
  if not live then
    out.shown, out.fill, out.fillKey, out.borderKey, out.label = false, 0, "off", "border", ""
    out.asGlow, out.rsGlow, out.flash = false, false, 0
    return out
  end
  local zone, stage = t.rangeState, w and w.stage or nil
  out.shown = true
  out.fill = (w and w.glide) or 0
  if zone == "MELEE" then out.fillKey = "melee" elseif zone == "SWEET" then out.fillKey = "ranged" else out.fillKey = "dead" end
  out.label = WS.LABELS[zone] or ""
  if w and w.legStale then out.borderKey = "stale"
  elseif w and w.overshot then out.borderKey = "overshot"
  else out.borderKey = STAGE_BORDER[stage] or "border" end
  out.asGlow = stage == "RELEASE"
  out.rsGlow = stage == "STRIKE"
  if stage == "RELEASE" and w.releaseAt then
    out.flash = Nock.UI.FlashMix((now or 0) - w.releaseAt, WS.FLASH_SEC)
  else
    out.flash = 0
  end
  return out
end

local function makeSlot(parent, opts)
  local s = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  Nock.UI.ApplyBackdrop(s, opts.bg, opts.border)
  local icon = s:CreateTexture(nil, "ARTWORK")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  s.icon = icon
  local cd = CreateFrame("Cooldown", nil, s, "CooldownFrameTemplate")
  cd:SetAllPoints(icon)
  if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
  if cd.SetDrawEdge then cd:SetDrawEdge(false) end
  if cd.SetDrawBling then cd:SetDrawBling(false) end
  if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.72) end
  cd.noCooldownCount = true   -- OmniCC & co: no numbers on the swing swipe
  s.cd = cd
  return s
end

-- The frame is the row; the two slots and the bar are its children.
function WS.Create(parent, opts)
  local f = CreateFrame("Frame", "NockReactWeaveStrip", parent)
  f.as = makeSlot(f, opts)
  f.rs = makeSlot(f, opts)
  local bar = CreateFrame("Frame", nil, f, "BackdropTemplate")
  Nock.UI.ApplyBackdrop(bar, opts.bg, opts.border)
  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill:SetTexture(WHITE8X8)
  bar.fill:SetWidth(0.01)
  bar.label = opts.makeText(bar, opts.fontSize, "CENTER")
  f.bar = bar
  f._look = { fill = -1 }
  return f
end

-- Layout time: icons square at the row height on both ends, the bar between
-- them, the three sharing 1 device px seams (e = the edge in units).
function WS.Layout(f, w, h, dev, e)
  e = e or 1
  local as, rs, bar = f.as, f.rs, f.bar
  as:ClearAllPoints(); as:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); as:SetSize(h, h)
  rs:ClearAllPoints(); rs:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); rs:SetSize(h, h)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", as, "TOPRIGHT", -e, 0)
  bar:SetPoint("BOTTOMRIGHT", rs, "BOTTOMLEFT", e, 0)
  -- The bar overlaps each icon by one edge (+2e) and its fill is inset by
  -- one edge on each side (-2e): the fill's span is w - 2h.
  f.innerW = w - 2 * h
  f.e = e
  for _, s in ipairs({ as, rs }) do
    s.icon:ClearAllPoints()
    s.icon:SetPoint("TOPLEFT", s, "TOPLEFT", e, -e)
    s.icon:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -e, e)
  end
  bar.fill:ClearAllPoints()
  bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", e, -e)
  bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", e, e)
  f._look.fill = -1
  f._look.fillKey, f._look.borderKey, f._look.label, f._look.asGlow, f._look.rsGlow = nil, nil, nil, nil, nil
  f._asStart, f._rsStart = nil, nil
end

local function color(key) return WS.COLORS[key] or WS.COLORS.border end

local function paintGlow(slot, on, last)
  if on == last then return end
  local c = on and WS.COLORS.glow or WS.COLORS.border
  if slot.SetBackdropBorderColor then slot:SetBackdropBorderColor(c[1], c[2], c[3], c[4]) end
end

-- Every tick, diffed on the look; the swipes on their start edges.
function WS.Paint(f, look, state)
  local L, bar = f._look, f.bar
  if look.fillKey ~= L.fillKey or look.flash > 0 or L.flashing then
    local c = color(look.fillKey)
    local m = look.flash or 0
    bar.fill:SetVertexColor(c[1] + (1 - c[1]) * m, c[2] + (1 - c[2]) * m, c[3] + (1 - c[3]) * m, c[4])
    L.fillKey, L.flashing = look.fillKey, m > 0
  end
  if math.abs(look.fill - L.fill) > 0.003 then
    bar.fill:SetWidth(math.max(0.01, look.fill * (f.innerW or 0)))
    L.fill = look.fill
  end
  if look.borderKey ~= L.borderKey then
    local c = color(look.borderKey)
    if bar.SetBackdropBorderColor then bar:SetBackdropBorderColor(c[1], c[2], c[3], c[4]) end
    L.borderKey = look.borderKey
  end
  if look.label ~= L.label then
    bar.label:SetText(look.label)
    L.label = look.label
  end
  paintGlow(f.as, look.asGlow, L.asGlow); L.asGlow = look.asGlow
  paintGlow(f.rs, look.rsGlow, L.rsGlow); L.rsGlow = look.rsGlow

  -- Icons once (the spell data may load late: keep trying until it answers).
  local Sp = Nock.Spells
  if not f.as.icon._set and Sp then
    local tex = Nock.API.SpellIcon(Sp.AUTO_SHOT)
    if tex then f.as.icon:SetTexture(tex); f.as.icon._set = true end
  end
  local cd = state.cooldowns and state.cooldowns.Raptor
  if not f.rs.icon._set and Sp then
    local tex = (cd and cd.icon) or Nock.API.SpellIcon(Sp.RAPTOR_STRIKE)
    if tex then f.rs.icon:SetTexture(tex); f.rs.icon._set = true end
  end

  -- Auto Shot: the ranged swing as a swipe (plain numbers from PLAYER_SWING).
  local r = state.ranged
  local start, dur = r and r.swingStart or 0, r and r.swingDuration or 0
  if start ~= f._asStart then
    if start > 0 and dur > 0 then f.as.cd:SetCooldown(start, dur) else f.as.cd:Clear() end
    f._asStart = start
  end
  -- Raptor: its cooldown, from the client's duration object where it exists
  -- (secret in combat, the widget takes it), else the ledger's numbers.
  local rsStart = (cd and not cd.ready and cd.startTime and cd.startTime > 0) and cd.startTime or 0
  if rsStart ~= f._rsStart then
    if rsStart > 0 then
      local obj = (Nock.Flavor and Nock.Flavor.forever and cd.spellId) and Nock.API.SpellCooldownDuration(cd.spellId) or nil
      if obj and f.rs.cd.SetCooldownFromDurationObject then f.rs.cd:SetCooldownFromDurationObject(obj)
      else f.rs.cd:SetCooldown(cd.startTime, cd.duration or 0) end
    else
      f.rs.cd:Clear()
    end
    f._rsStart = rsStart
  end
end
