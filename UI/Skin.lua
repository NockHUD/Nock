-- UI/Skin.lua
-- The practice workbench's skin: one table of colour tokens (full black, the
-- hunter's green as the only accent), the fixed ability and verdict colours,
-- the font trio shipped in Media/, the Nock logo and the Nucleo pixel icon
-- atlas -- and the few helpers every practice frame paints through.
--
-- Decided with the user 2026-08-26 (the "Practice Palette" artifact): black,
-- not near-black, so the window is the darkest thing on screen; surfaces a few
-- points lighter and 1 px lines doing the structure; #abd473 for the hit line,
-- the active rail item, the primary button, the state chip and the grade.
-- "good" IS the accent -- the stage's PERFECT/GOOD pops and the weave gap
-- were a second green, and two greens read as a mistake. Amber wait and red
-- fault stay. The logo is never tinted green: white means Nock, green means
-- state.
--
-- The HUD proper keeps its own colours and its own font options; this skin is
-- the practice shell's, and the existing practiceColor* overrides sit on top.
-- The AceAddon object is the global `Nock` (Core/PracticeModel.lua does the
-- same); `...` here is the addon's PRIVATE table, which nothing else reads --
-- Skin and IconAtlas hung off it once and every practice frame saw nil.
local Nock = rawget(_G, "Nock")
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local C = Nock.Constants

local Skin = {}
Nock.Skin = Skin

Skin.MEDIA = "Interface\\AddOns\\Nock\\Media\\"

--------------------------------------------------------------------------------
-- Colours. {r, g, b} in 0..1; alpha is the caller's (Paint / Text take one).
--------------------------------------------------------------------------------
local function rgb(hex)
  local n = tonumber(hex, 16)
  return { math.floor(n / 65536) / 255, (math.floor(n / 256) % 256) / 255, (n % 256) / 255 }
end

Skin.COLORS = {
  -- the shell
  ground    = rgb("000000"),
  surface   = rgb("0a0a0a"),
  surface2  = rgb("101010"),
  raised    = rgb("181818"),
  line      = rgb("262626"),
  lineSoft  = rgb("1a1a1a"),
  ink       = rgb("f2f2ee"),
  ink2      = rgb("a8a8a3"),
  ink3      = rgb("676764"),
  accent    = rgb("abd473"),   -- the hunter's green
  accentInk = rgb("0c1405"),   -- text on an accent fill
  -- the stage's fixed set (Core/PracticeTimeline.lua T.COLORS mirrors these)
  steady    = rgb("59a6ff"),
  multi     = rgb("ff9933"),
  arcane    = rgb("cc66ff"),
  auto      = rgb("8a8f99"),
  good      = rgb("abd473"),   -- = accent, on purpose
  wait      = rgb("d9b866"),
  bad       = rgb("ff5c5c"),
  white     = rgb("ffffff"),
}
-- Alphas the palette page fixed alongside the hues.
Skin.ALPHA = { accentSoft = 0.14, accentLine = 0.45, zebra = 0.03, logoFoot = 0.55 }

function Skin.Color(name)
  local c = Skin.COLORS[name] or Skin.COLORS.ink
  return c[1], c[2], c[3]
end

-- Flat fill on a texture.
function Skin.Paint(tex, name, alpha)
  local r, g, b = Skin.Color(name)
  tex:SetColorTexture(r, g, b, alpha or 1)
end

function Skin.Text(fs, name, alpha)
  local r, g, b = Skin.Color(name)
  fs:SetTextColor(r, g, b, alpha or 1)
end

--------------------------------------------------------------------------------
-- Fonts. Three faces, shipped as TTF (SIL OFL 1.1, Media/FONTS-LICENSE.txt):
--   display  Saira Extra Condensed  -- titles, grades, the scenario name
--   ui       IBM Plex Sans          -- everything read
--   mono     IBM Plex Mono          -- clocks, keys, deltas, chips
-- Registered with LibSharedMedia under "Nock ..." names so the existing font
-- dropdowns can pick them; SetFont falls back to C.FONT.PATH if a file is
-- missing, the way Nock.UI.SafeSetFont does.
--------------------------------------------------------------------------------
Skin.FONTS = {
  display       = Skin.MEDIA .. "SairaExtraCondensed-Bold.ttf",
  displayMedium = Skin.MEDIA .. "SairaExtraCondensed-Medium.ttf",
  ui            = Skin.MEDIA .. "IBMPlexSans-Regular.ttf",
  uiMedium      = Skin.MEDIA .. "IBMPlexSans-Medium.ttf",
  uiBold        = Skin.MEDIA .. "IBMPlexSans-SemiBold.ttf",
  mono          = Skin.MEDIA .. "IBMPlexMono-Regular.ttf",
  monoMedium    = Skin.MEDIA .. "IBMPlexMono-Medium.ttf",
}
Skin.LSM_FONTS = {
  { "Nock Saira Extra Condensed",        Skin.FONTS.display },
  { "Nock Saira Extra Condensed Medium", Skin.FONTS.displayMedium },
  { "Nock Plex Sans",                    Skin.FONTS.ui },
  { "Nock Plex Sans Medium",             Skin.FONTS.uiMedium },
  { "Nock Plex Sans SemiBold",           Skin.FONTS.uiBold },
  { "Nock Plex Mono",                    Skin.FONTS.mono },
  { "Nock Plex Mono Medium",             Skin.FONTS.monoMedium },
}
if LSM and LSM.Register then
  for i = 1, #Skin.LSM_FONTS do
    local e = Skin.LSM_FONTS[i]
    LSM:Register("font", e[1], e[2])
  end
end
-- Touch every face once, at load. The client loads a font file the first
-- time a FontString references it, and a file first referenced mid-session
-- draws nothing until the next reload -- the pages are built lazily, so a
-- face only they use (the cards' SemiBold) was blank on every first open
-- and took a second reload to appear (user, 2026-08-26). Referencing them
-- all here puts every face in the load-time set of every session.
--
-- And the frame is SHOWN, not hidden: a hidden frame is never drawn, and it
-- is the draw that rasterises a face -- warmed on a hidden frame, the Lesson
-- page's narration and keycaps still came out half-drawn on their first open
-- of a session (user, 2026-08-27). One near-transparent pixel in the corner,
-- behind everything, renders every face once at load.
Skin.WARMED = {}
local warm = CreateFrame and CreateFrame("Frame", nil, UIParent) or nil
if warm and warm.CreateFontString then
  if warm.SetSize then warm:SetSize(1, 1) end
  if warm.SetPoint and UIParent then warm:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0) end
  if warm.SetFrameStrata then warm:SetFrameStrata("BACKGROUND") end
  if warm.SetFrameLevel then warm:SetFrameLevel(0) end
  if warm.SetAlpha then warm:SetAlpha(0.02) end
  if warm.Show then warm:Show() end
  for role, path in pairs(Skin.FONTS) do
    local fs = warm:CreateFontString(nil, "OVERLAY")
    if fs and fs.SetFont then
      Skin.WARMED[role] = fs:SetFont(path, 12, "") and true or false
      if fs.SetPoint then fs:SetPoint("BOTTOMLEFT", warm, "BOTTOMLEFT", 0, 0) end
      if fs.SetTextColor then fs:SetTextColor(0, 0, 0, 0.02) end
      if fs.SetText then fs:SetText("Nock 0123456789 " .. role) end
    end
  end
end

-- The sizes the palette page set, by role. `size` overrides.
Skin.SIZES = { title = 19, h2 = 20, grade = 40, body = 12, small = 11, mono = 11, chip = 11, key = 10 }

function Skin.Font(fs, role, size, flags)
  local path = Skin.FONTS[role] or Skin.FONTS.ui
  size = size or Skin.SIZES.body
  if not (fs and fs.SetFont) then return end
  if fs:SetFont(path, size, flags or "") then return true end
  fs:SetFont((C and C.FONT and C.FONT.PATH) or "Fonts\\FRIZQT__.TTF", size, flags or "")
  return false
end

--------------------------------------------------------------------------------
-- The logo (Media/NockLogo.tga ring + mark, NockMark.tga / NockMark64.tga the
-- mark alone; white on transparent) and the Nucleo pixel icons
-- (UI/IconAtlas.lua -> Media/PixelIcons.tga, white on transparent).
--------------------------------------------------------------------------------
Skin.LOGOS = {
  logo   = Skin.MEDIA .. "NockLogo",
  mark   = Skin.MEDIA .. "NockMark",
  mark64 = Skin.MEDIA .. "NockMark64",
}

function Skin.Logo(tex, which, alpha)
  tex:SetTexture(Skin.LOGOS[which] or Skin.LOGOS.mark)
  tex:SetTexCoord(0, 1, 0, 1)
  tex:SetVertexColor(1, 1, 1, alpha or 1)   -- never tinted: white means Nock
end

-- A pixel icon on a texture, tinted with a skin colour (default ink).
-- Returns false (and paints nothing) for a name the atlas does not hold.
-- (`small` picks an alternate sheet if the atlas ever carries one; the 20 px
-- sheet was tried and dropped -- the user picked the plain 32 px cell.)
function Skin.Icon(tex, name, colorName, alpha, small)
  local atlas = Nock.IconAtlas
  if small and atlas and atlas.small then atlas = atlas.small end
  local co = atlas and atlas.coords[name]
  if not co then return false end
  -- One file per icon when the atlas ships them (Media/Icons/<name>.tga): a
  -- bare 24x24 texture, NOT power-of-two, so the client builds no mip chain
  -- for it and draws it as it is. The 256 px sheet and a padded 32x32 file
  -- both rendered soft and a shade large at 1:1 -- the client's mip bias
  -- blends the half-size level in -- while the user's own 24x24 file was
  -- crisp (2026-08-26). Keep the files non-power-of-two.
  local file = atlas.files and atlas.files[name]
  if file then
    tex:SetTexture(file)
    tex:SetTexCoord(0, 1, 0, 1)
    tex._iconFile = true
  else
    tex:SetTexture(atlas.texture)
    tex:SetTexCoord(co[1], co[2], co[3], co[4])
    tex._iconFile = nil
  end
  tex._iconAtlas = atlas
  local r, g, b = Skin.Color(colorName or "ink")
  tex:SetVertexColor(r, g, b, alpha or 1)
  return true
end

-- PIXEL-EXACT SIZE. The atlas holds a 24-grid glyph in a 32 px cell; drawn
-- at any other on-screen size (a 16 px texture, a UI scale of 0.71) the
-- renderer resamples it and the pixel art goes soft (user, 2026-08-26). So
-- the texture is sized in ITS OWN units such that the cell lands on whole
-- screen pixels: cellPx / effective scale. Call again when the scale changes
-- (Relayout); half-size glyphs were tried and lose the icons' detail.
-- The scale a region is drawn under, walked by hand: its frame's own scale
-- times every ancestor's, times UIParent's effective scale. The client's
-- GetEffectiveScale gave a workbench icon 1.25 where the chain says 0.667
-- (diag, 2026-08-26), so the chain is walked.
local function scaleOf(frame)
  local s = 1
  local f = frame
  local hops = 0
  while f and f ~= UIParent and hops < 32 do
    if f.GetScale then s = s * (f:GetScale() or 1) end
    f = f.GetParent and f:GetParent() or nil
    hops = hops + 1
  end
  local ui = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  return s * (ui or 1)
end
Skin.ScaleOf = scaleOf

-- PHYSICAL PIXELS PER UNIT. The client's coordinate space is 768 units tall
-- at effective scale 1 whatever the monitor, so on a 1440p screen a unit at
-- scale 1 is 1.875 px. The probe (2026-08-26) proved it: 25.6 units was the
-- crisp 32 px cell at effective 0.6667 on 2560x1440 -- 32 / (0.6667 x 1.875).
function Skin.PixelsPerUnit(frame)
  local physH = 768
  if GetPhysicalScreenSize then
    local _, h = GetPhysicalScreenSize()
    if h and h > 0 then physH = h end
  end
  return scaleOf(frame) * physH / 768
end

function Skin.IconSize(tex, glyphPx)
  local atlas = tex._iconAtlas or Nock.IconAtlas
  local cell = (atlas and atlas.cell) or 32
  local glyph = (atlas and atlas.glyph) or 24
  if tex._iconFile then cell = (atlas and atlas.fileCell) or 24 end   -- the bare file: no padding
  local cellPx = math.floor((glyphPx or glyph) * cell / glyph + 0.5)
  local parent = tex.GetParent and tex:GetParent()
  local es = parent and Skin.PixelsPerUnit(parent) or 1
  if not es or es <= 0 then es = 1 end
  tex._iconEs = es
  local size = cellPx / es
  tex:SetSize(size, size)
  -- Size only. The client's own defaults draw a 1:1 texture cleanly; the
  -- snapping calls and a sub-pixel anchor nudge were both tried and both
  -- picked against in the in-game grid (the user chose the plain 32 px
  -- cell, 2026-08-26). Not a perfect copy of the design sheet - "it will
  -- do" - so if this is revisited, the remaining difference is in the
  -- client's texture path, not in the size.
  return size
end

function Skin.HasIcon(name)
  local atlas = Nock.IconAtlas
  return (atlas and atlas.coords[name]) ~= nil
end

--------------------------------------------------------------------------------
-- Surfaces: a flat fill plus a 1 px line, the shell's whole vocabulary. Made
-- of textures (no Backdrop): a plain frame's SetBackdrop is gone on this
-- client and BackdropTemplate's edge files cannot be a hairline in a flat
-- colour. `frame.skinFill` / `frame.skinLine[1..4]` are reused on repaint.
--------------------------------------------------------------------------------
function Skin.Surface(frame, fillName, lineName, fillAlpha)
  local fill = frame.skinFill
  if not fill then
    fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetAllPoints(frame)
    frame.skinFill = fill
  end
  Skin.Paint(fill, fillName or "surface", fillAlpha or 1)
  if lineName then
    local lines = frame.skinLine
    if not lines then
      lines = {}
      for i = 1, 4 do lines[i] = frame:CreateTexture(nil, "BORDER", nil, -7) end
      lines[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0);       lines[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0);       lines[1]:SetHeight(1)
      lines[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); lines[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); lines[2]:SetHeight(1)
      lines[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0);       lines[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0);   lines[3]:SetWidth(1)
      lines[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0);     lines[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); lines[4]:SetWidth(1)
      frame.skinLine = lines
    end
    for i = 1, 4 do Skin.Paint(lines[i], lineName, 1); lines[i]:Show() end
  elseif frame.skinLine then
    for i = 1, 4 do frame.skinLine[i]:Hide() end
  end
end

-- One hairline (a rule between two things), anchored by the caller.
function Skin.Rule(parent, lineName)
  local t = parent:CreateTexture(nil, "ARTWORK")
  Skin.Paint(t, lineName or "lineSoft", 1)
  return t
end

--------------------------------------------------------------------------------
-- Buttons. Two kinds, the palette page's: `primary` (accent fill, dark ink --
-- the one thing to press: Start) and `ghost` (no fill, a hairline, ink2; the
-- fill comes up on hover). `danger` is a ghost that reads red (STOP in Focus).
-- Textures, no template: UIPanelButtonTemplate's art is the client's, not
-- this shell's. `b.text` is the label; `Skin.ButtonKind` restyles in place.
--------------------------------------------------------------------------------
local BTN_KIND = {
  primary = { fill = "accent", line = "accent", ink = "accentInk", hover = "accent", hoverA = 0.85 },
  ghost   = { fill = "surface", line = "line", ink = "ink2", hover = "surface2", hoverA = 1, hoverInk = "ink" },
  danger  = { fill = "surface", line = "line", ink = "bad", hover = "surface2", hoverA = 1, hoverInk = "bad" },
}
Skin.BUTTON_H, Skin.BUTTON_PAD = 22, 10

function Skin.ButtonKind(b, kind)
  local k = BTN_KIND[kind] or BTN_KIND.ghost
  b.kind = kind
  Skin.Surface(b, k.fill, k.line)
  Skin.Text(b.text, k.ink)
end

function Skin.Button(parent, label, kind, width, height)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(height or Skin.BUTTON_H)
  local fs = b:CreateFontString(nil, "OVERLAY")
  Skin.Font(fs, "uiMedium", Skin.SIZES.body)
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  fs:SetJustifyH("CENTER")
  fs:SetWordWrap(false)
  b.text = fs
  Skin.ButtonKind(b, kind)
  b:SetScript("OnEnter", function(self)
    local k = BTN_KIND[self.kind] or BTN_KIND.ghost
    if self.skinFill then Skin.Paint(self.skinFill, k.hover, k.hoverA) end
    if k.hoverInk then Skin.Text(self.text, k.hoverInk) end
  end)
  b:SetScript("OnLeave", function(self)
    local k = BTN_KIND[self.kind] or BTN_KIND.ghost
    if self.skinFill then Skin.Paint(self.skinFill, k.fill, 1) end
    Skin.Text(self.text, k.ink)
  end)
  Skin.SetButtonText(b, label, width)
  return b
end

-- The label, and the width that follows it (or a fixed one).
function Skin.SetButtonText(b, label, width)
  b.text:SetText(label or "")
  if width then b:SetWidth(width)
  else b:SetWidth(math.max(40, (b.text:GetStringWidth() or 30) + Skin.BUTTON_PAD * 2)) end
end

--------------------------------------------------------------------------------
-- Chips: a small bordered tile with mono text (the state chip, the eWS chip,
-- NO KEYS). `Skin.SetChip` writes text and colours in one call and sizes the
-- chip to the string; callers gate it on their own change check.
--------------------------------------------------------------------------------
Skin.CHIP_H = 16

function Skin.Chip(parent, size)
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(40, Skin.CHIP_H)
  Skin.Surface(c, "ground", "line")
  local fs = c:CreateFontString(nil, "OVERLAY")
  Skin.Font(fs, "monoMedium", size or Skin.SIZES.chip)
  fs:SetPoint("CENTER", c, "CENTER", 0, 0)
  fs:SetWordWrap(false)
  c.text = fs
  return c
end

--------------------------------------------------------------------------------
-- Banners: one line on a wash with a pixel icon at its left -- what a paper
-- costs by design (M.PaperNotes), on the Lesson and the coach row.
--------------------------------------------------------------------------------
Skin.BANNER_H = 22
-- The icon a paper note wears: the clock for a planned clip, the triangle
-- for a knife-edge weave.
Skin.NOTE_ICON = { ["clips by design"] = "clock", ["tight weave"] = "warn", ["no weave key"] = "key" }

function Skin.Banner(parent, colorName)
  local b = CreateFrame("Frame", nil, parent)
  b:SetHeight(Skin.BANNER_H)
  local fill = b:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(b)
  Skin.Paint(fill, colorName or "wait", 0.10)
  b.fill = fill
  local rule = b:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  rule:SetHeight(1)
  Skin.Paint(rule, colorName or "wait", 0.35)
  b.rule = rule
  local ico = b:CreateTexture(nil, "OVERLAY")
  ico:SetPoint("LEFT", b, "LEFT", 6, 0)
  Skin.Icon(ico, "warn", colorName or "wait")
  Skin.IconSize(ico)
  b.ico = ico
  local fs = b:CreateFontString(nil, "OVERLAY")
  Skin.Font(fs, "ui", Skin.SIZES.small)
  fs:SetPoint("LEFT", ico, "RIGHT", 8, 0)
  fs:SetPoint("RIGHT", b, "RIGHT", -8, 0)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  Skin.Text(fs, "ink2")
  b.text = fs
  b:Hide()
  return b
end

-- Show the banner with an icon and a line; nil text hides it.
function Skin.SetBanner(b, iconName, text, colorName)
  if not text then b:Hide(); return false end
  Skin.Icon(b.ico, iconName or "warn", colorName or "wait")
  Skin.IconSize(b.ico)
  b.text:SetText(text)
  b:Show()
  return true
end

function Skin.SetChip(chip, text, fillName, inkName)
  chip.text:SetText(text)
  chip:SetWidth(math.max(20, (chip.text:GetStringWidth() or 20) + 12))
  Skin.Surface(chip, fillName or "ground", fillName or "line")
  Skin.Text(chip.text, inkName or "ink2")
end

return Skin
