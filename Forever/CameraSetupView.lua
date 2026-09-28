-- Forever/CameraSetupView.lua
-- The weave camera setup window: three steps (camera behind you, face the camera, test), a bullseye track for the turn.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local C = Nock.Constants
local View = {}
Nock.CameraSetupView = View

local PANEL_W, PANEL_H = 640, 420
local HEADER_H, FOOTER_H, LEFT_W = 42, 40, 250
local TRACK_W = 330
local SWEET_DEG, NEAR_DEG = 2, 15

local COL_GOLD   = { 0.95, 0.76, 0.19 }
local COL_TEXT   = { 0.91, 0.90, 0.86 }
local COL_DIM    = { 0.74, 0.73, 0.69 }
local COL_FAINT  = { 0.56, 0.55, 0.52 }
local COL_GREEN  = { 0.49, 0.85, 0.34 }
local COL_INK    = { 0.08, 0.08, 0.07 }
local COL_PANEL  = { 0.05, 0.05, 0.055, 0.94 }
local COL_CARD   = { 0.086, 0.086, 0.10, 1 }
local COL_LINE   = { 0.165, 0.165, 0.18, 1 }
local COL_BORDER = { 0, 0, 0, 1 }
local COL_AMBER_BG = { 0.17, 0.14, 0.06, 1 }
local COL_AMBER_BD = { 0.35, 0.29, 0.08, 1 }

-----------------------------------------------------------------------------
-- Pure helpers (Tests/forever_camera_view_test.lua)
-----------------------------------------------------------------------------

-- The marker's x on a track of width w for a signed offset in degrees
-- (-180 .. 180 maps to 0 .. w).
function View.MarkerX(off, w)
  local o = math.max(-180, math.min(180, off or 0))
  return (0.5 + o / 360) * w
end

-- The status pill, the TURN card's state and its hint for an offset.
function View.TurnTexts(off, ok)
  if off == nil then return "Waiting for step 1", "?", "Set the baseline first." end
  local a = math.abs(off)
  if ok then return "Sweet spot: release LMB", "done", "Hold still and let go of LMB." end
  local hint = off < 0 and "Tap Turn Right." or "Tap Turn Left."
  if a <= NEAR_DEG then return "Almost, tap slower", "almost", hint end
  return "Keep tapping", ("%d deg to go"):format(math.floor(a + 0.5)), hint
end

-- Signed degrees text.
function View.OffText(off)
  if off == nil then return "--" end
  return ("%s%.1f deg"):format(off > 0 and "+" or "", off)
end

-----------------------------------------------------------------------------
-- Widgets
-----------------------------------------------------------------------------

local function uiFont() return Nock.UI.GetFont() or C.FONT.PATH end
local function monoFont() return (Nock.Skin and Nock.Skin.FONTS and Nock.Skin.FONTS.monoMedium) or uiFont() end

local function fs(parent, size, color, style, path)
  local t = parent:CreateFontString(nil, "OVERLAY")
  Nock.UI.SafeSetFont(t, path or uiFont(), size, style or "")
  t:SetTextColor(unpack(color or COL_TEXT))
  t:SetJustifyH("LEFT")
  return t
end

local function box(parent, bg, border)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  Nock.UI.ApplyBackdrop(f, bg or COL_CARD, border or COL_LINE)
  return f
end

local function line(parent, color)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(unpack(color or COL_LINE))
  return t
end

local function button(parent, w, h, text, primary)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  Nock.UI.ApplyBackdrop(b, primary and { 0.95, 0.76, 0.19, 1 } or { 0, 0, 0, 0 }, primary and { 0.95, 0.76, 0.19, 1 } or { 0.23, 0.23, 0.25, 1 })
  local t = fs(b, 11, primary and COL_INK or COL_DIM, "")
  t:SetPoint("CENTER")
  t:SetJustifyH("CENTER")
  t:SetText(text)
  b.label = t
  b:SetScript("OnEnter", function() if not primary then t:SetTextColor(unpack(COL_TEXT)) end end)
  b:SetScript("OnLeave", function() if not primary then t:SetTextColor(unpack(COL_DIM)) end end)
  return b
end

-- A small bordered chip: "RMB", "A", a step label.
local function chip(parent, text, w, h, active)
  local f = box(parent, active and { 0.95, 0.76, 0.19, 1 } or { 0, 0, 0, 0 }, active and { 0.95, 0.76, 0.19, 1 } or { 0.23, 0.23, 0.25, 1 })
  f:SetSize(w, h)
  local t = fs(f, 10, active and COL_INK or COL_FAINT, "", monoFont())
  t:SetPoint("CENTER")
  t:SetJustifyH("CENTER")
  t:SetText(text)
  f.label = t
  return f
end

local function axisCard(parent, w, h, label)
  local f = box(parent, COL_CARD, COL_LINE)
  f:SetSize(w, h)
  f.tag = fs(f, 9, COL_GOLD, "")
  f.tag:SetPoint("TOPLEFT", 10, -8)
  f.tag:SetText(label)
  f.state = fs(f, 10, COL_FAINT, "", monoFont())
  f.state:SetPoint("TOPRIGHT", -10, -8)
  f.state:SetJustifyH("RIGHT")
  f.body = fs(f, 10, COL_DIM, "")
  f.body:SetPoint("TOPLEFT", 10, -24)
  f.body:SetPoint("RIGHT", -10, 0)
  f.body:SetWordWrap(true)
  return f
end

-----------------------------------------------------------------------------
-- Build
-----------------------------------------------------------------------------

function View:Build()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "NockCameraSetup", UIParent, "BackdropTemplate")
  f:SetSize(PANEL_W, PANEL_H)
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  f:SetFrameStrata("DIALOG")
  Nock.UI.ApplyBackdrop(f, COL_PANEL, COL_BORDER)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  tinsert(UISpecialFrames, "NockCameraSetup")
  self.frame = f

  -- Header
  local hdr = CreateFrame("Frame", nil, f)
  hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT"); hdr:SetHeight(HEADER_H)
  local eyebrow = fs(hdr, 10, COL_GOLD, "")
  eyebrow:SetPoint("LEFT", 16, 0)
  eyebrow:SetText("NOCK  ·  WEAVE CAMERA")
  self.chips = {}
  local labels = { "1  BEHIND YOU", "2  FACE THE CAMERA", "3  TEST" }
  local x = 190
  for i = 1, 3 do
    local c = chip(hdr, labels[i], i == 2 and 122 or 96, 20, false)
    c:SetPoint("LEFT", x, 0)
    x = x + c:GetWidth() + 6
    self.chips[i] = c
  end
  local close = CreateFrame("Button", nil, hdr)
  close:SetSize(20, 20)
  close:SetPoint("RIGHT", -12, 0)
  local xt = fs(close, 12, COL_FAINT, "")
  xt:SetPoint("CENTER"); xt:SetText("x")
  close:SetScript("OnEnter", function() xt:SetTextColor(unpack(COL_TEXT)) end)
  close:SetScript("OnLeave", function() xt:SetTextColor(unpack(COL_FAINT)) end)
  close:SetScript("OnClick", function() if self.ctrl and self.ctrl.onClose then self.ctrl.onClose() end end)
  local hl = line(f); hl:SetPoint("TOPLEFT", 0, -HEADER_H); hl:SetPoint("TOPRIGHT", 0, -HEADER_H); hl:SetHeight(1)

  -- Style banner (step 3, only when Camera Following Style is wrong)
  local banner = box(f, COL_AMBER_BG, COL_AMBER_BD)
  banner:SetPoint("TOPLEFT", 0, -HEADER_H - 1); banner:SetPoint("TOPRIGHT", 0, -HEADER_H - 1); banner:SetHeight(30)
  banner.text = fs(banner, 10, COL_GOLD, "")
  banner.text:SetPoint("LEFT", 16, 0)
  banner.text:SetText("Camera Following Style is not \"Never adjust camera\". The turn fights it.")
  banner.fix = button(banner, 56, 20, "Fix it", true)
  banner.fix:SetPoint("RIGHT", -12, 0)
  banner.fix:SetScript("OnClick", function() if self.ctrl and self.ctrl.onFix then self.ctrl.onFix() end end)
  banner:Hide()
  self.banner = banner

  -- Footer
  local ftr = CreateFrame("Frame", nil, f)
  ftr:SetPoint("BOTTOMLEFT"); ftr:SetPoint("BOTTOMRIGHT"); ftr:SetHeight(FOOTER_H)
  local fl = line(f); fl:SetPoint("BOTTOMLEFT", 0, FOOTER_H); fl:SetPoint("BOTTOMRIGHT", 0, FOOTER_H); fl:SetHeight(1)
  self.footText = fs(ftr, 10, COL_FAINT, "")
  self.footText:SetPoint("LEFT", 16, 0)
  self.btnSkip = button(ftr, 150, 22, "Skip, I saved it myself")
  self.btnSkip:SetPoint("RIGHT", -12, 0)
  self.btnSkip:SetScript("OnClick", function() if self.ctrl and self.ctrl.onSkip then self.ctrl.onSkip() end end)
  self.btnBack = button(ftr, 60, 22, "Back")
  self.btnBack:SetPoint("RIGHT", self.btnSkip, "LEFT", -8, 0)
  self.btnBack:SetScript("OnClick", function() if self.ctrl and self.ctrl.onBack then self.ctrl.onBack() end end)
  self.btnDone = button(ftr, 70, 22, "Done", true)
  self.btnDone:SetPoint("RIGHT", -12, 0)
  self.btnDone:SetScript("OnClick", function() if self.ctrl and self.ctrl.onClose then self.ctrl.onClose() end end)
  self.btnRedo = button(ftr, 60, 22, "Redo")
  self.btnRedo:SetPoint("RIGHT", self.btnDone, "LEFT", -8, 0)
  self.btnRedo:SetScript("OnClick", function() if self.ctrl and self.ctrl.onRedo then self.ctrl.onRedo() end end)

  -- Body
  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", 0, -HEADER_H - 1); body:SetPoint("BOTTOMRIGHT", 0, FOOTER_H + 1)
  self.body = body
  local vl = line(body); vl:SetPoint("TOPLEFT", LEFT_W, 0); vl:SetPoint("BOTTOMLEFT", LEFT_W, 0); vl:SetWidth(1)
  self.vline = vl

  self.pages = { self:BuildStep1(body), self:BuildStep2(body), self:BuildStep3(body) }
  return f
end

local function page(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints(parent)
  p:Hide()
  return p
end

function View:BuildStep1(parent)
  local p = page(parent)
  local L = CreateFrame("Frame", nil, p)
  L:SetPoint("TOPLEFT", 18, -14); L:SetPoint("BOTTOMLEFT", 18, 12); L:SetWidth(LEFT_W + 60)
  local title = fs(L, 15, COL_TEXT, "")
  title:SetPoint("TOPLEFT"); title:SetPoint("RIGHT"); title:SetWordWrap(true)
  title:SetText("Set the camera the way you play")
  local blurb = fs(L, 10, COL_DIM, "")
  blurb:SetPoint("TOPLEFT", 0, -24); blurb:SetPoint("RIGHT"); blurb:SetWordWrap(true)
  blurb:SetText("Stand still, out of combat. Every weave returns to this view, so make it your real one.")
  local y = -58
  local cards = {}
  local rows = {
    { "YAW",  "Hold RMB and drag until the camera is straight behind your back." },
    { "TILT", "Same RMB drag up or down: the height you fight at. Nock cannot read this one, so eyeball it." },
    { "ZOOM", "Scroll to your usual distance. Changing it later means running this again." },
  }
  for i = 1, 3 do
    local c = axisCard(L, LEFT_W + 60, 50, rows[i][1])
    c:SetPoint("TOPLEFT", 0, y)
    c.body:SetText(rows[i][2])
    y = y - 56
    cards[i] = c
  end
  cards[1].state:SetText("live"); cards[1].state:SetTextColor(unpack(COL_GREEN))
  cards[2].state:SetText("you")
  p.zoomState = cards[3].state
  local rel = fs(L, 10, COL_DIM, "")
  rel:SetPoint("BOTTOMLEFT"); rel:SetPoint("RIGHT"); rel:SetWordWrap(true)
  rel:SetText("Release RMB when it looks right. That saves your normal view and fixes the start direction.")

  local R = CreateFrame("Frame", nil, p)
  R:SetPoint("TOPLEFT", LEFT_W + 80, -14); R:SetPoint("BOTTOMRIGHT", -18, 12)
  local diag = box(R, { 0.067, 0.067, 0.078, 1 }, COL_LINE)
  diag:SetSize(200, 150)
  diag:SetPoint("TOP", 0, -16)
  local you = fs(diag, 22, COL_TEXT, "", monoFont()); you:SetPoint("TOP", 0, -30); you:SetJustifyH("CENTER"); you:SetText("^")
  local youL = fs(diag, 9, COL_FAINT, ""); youL:SetPoint("TOP", 0, -14); youL:SetJustifyH("CENTER"); youL:SetText("YOU")
  local dots = fs(diag, 12, COL_GOLD, "", monoFont()); dots:SetPoint("CENTER", 0, -6); dots:SetJustifyH("CENTER"); dots:SetText(":\n:\n:")
  local cam = box(diag, { 0.95, 0.76, 0.19, 1 }, { 0.95, 0.76, 0.19, 1 }); cam:SetSize(30, 16); cam:SetPoint("BOTTOM", 0, 30)
  local camL = fs(diag, 9, COL_GOLD, ""); camL:SetPoint("BOTTOM", 0, 12); camL:SetJustifyH("CENTER"); camL:SetText("CAMERA BEHIND")
  local rmb = chip(R, "RMB", 38, 20, true)
  rmb:SetPoint("TOP", diag, "BOTTOM", -70, -16)
  local hold = fs(R, 10, COL_DIM, "")
  hold:SetPoint("LEFT", rmb, "RIGHT", 8, 0)
  hold:SetText("Holding RMB  ·  release to lock this view")
  p.zoomBig = fs(R, 16, COL_TEXT, "", monoFont())
  p.zoomBig:SetPoint("BOTTOM", 0, 8); p.zoomBig:SetJustifyH("CENTER")
  return p
end

function View:BuildStep2(parent)
  local p = page(parent)
  local L = CreateFrame("Frame", nil, p)
  L:SetPoint("TOPLEFT", 18, -14); L:SetPoint("BOTTOMLEFT", 18, 12); L:SetWidth(LEFT_W - 36)
  local title = fs(L, 15, COL_TEXT, "")
  title:SetPoint("TOPLEFT"); title:SetPoint("RIGHT"); title:SetWordWrap(true)
  title:SetText("Turn until you look at your own face")
  local lmb = chip(L, "LMB", 38, 20, true)
  lmb:SetPoint("TOPLEFT", 0, -50)
  local t1 = fs(L, 10, COL_DIM, "")
  t1:SetPoint("TOPLEFT", 48, -48); t1:SetPoint("RIGHT"); t1:SetWordWrap(true)
  t1:SetText("|cfff2c230Hold LMB|r the whole time. Mouse still: the camera has to stay where step 1 left it.")
  local kA = chip(L, "A", 20, 20, false); kA:SetPoint("TOPLEFT", 0, -104)
  local kD = chip(L, "D", 20, 20, false); kD:SetPoint("LEFT", kA, "RIGHT", 3, 0)
  local t2 = fs(L, 10, COL_DIM, "")
  t2:SetPoint("TOPLEFT", 48, -102); t2:SetPoint("RIGHT"); t2:SetWordWrap(true)
  t2:SetText("|cffe9e6dcTap a Turn key|r (Turn, not Strafe). Each tap moves the marker; small taps near the centre.")
  local rel = fs(L, 10, COL_DIM, "")
  rel:SetPoint("BOTTOMLEFT"); rel:SetPoint("RIGHT"); rel:SetWordWrap(true)
  rel:SetText("|cff7ed957Release LMB|r inside the green band. That saves the view.")

  local R = CreateFrame("Frame", nil, p)
  R:SetPoint("TOPLEFT", LEFT_W + 18, -14); R:SetPoint("BOTTOMRIGHT", -18, 10)
  local offLabel = fs(R, 9, COL_FAINT, ""); offLabel:SetPoint("TOPLEFT", 0, -6); offLabel:SetText("OFF BY")
  p.offBig = fs(R, 26, COL_TEXT, "", monoFont()); p.offBig:SetPoint("TOPLEFT", 48, 0)
  p.pill = box(R, { 0.15, 0.15, 0.17, 1 }, { 0.15, 0.15, 0.17, 1 })
  p.pill:SetSize(170, 22); p.pill:SetPoint("TOPRIGHT", 0, -4)
  p.pill.text = fs(p.pill, 9, COL_DIM, ""); p.pill.text:SetPoint("CENTER"); p.pill.text:SetJustifyH("CENTER")

  -- Track
  local track = box(R, { 0.11, 0.11, 0.125, 1 }, COL_LINE)
  track:SetSize(TRACK_W, 16); track:SetPoint("TOPLEFT", 0, -58)
  local band = track:CreateTexture(nil, "ARTWORK"); band:SetColorTexture(0.18, 0.24, 0.13, 1)
  band:SetPoint("TOPLEFT", TRACK_W * 0.458, 0); band:SetSize(TRACK_W * 0.084, 16)
  p.tick = track:CreateTexture(nil, "OVERLAY"); p.tick:SetColorTexture(0.31, 0.48, 0.21, 1)
  p.tick:SetPoint("TOP", track, "TOPLEFT", TRACK_W / 2, 5); p.tick:SetSize(4, 26)
  local labels = { { 0, "-180" }, { 0.25, "-90" }, { 0.5, "TARGET" }, { 0.75, "+90" }, { 1, "+180" } }
  for i = 1, #labels do
    local l = fs(R, 9, i == 3 and COL_GREEN or COL_FAINT, "")
    l:SetPoint("TOP", track, "TOPLEFT", labels[i][1] * TRACK_W, -22); l:SetJustifyH("CENTER"); l:SetText(labels[i][2])
  end
  p.marker = CreateFrame("Frame", nil, R)
  p.marker:SetSize(16, 40); p.marker:SetFrameLevel(track:GetFrameLevel() + 3)
  local head = p.marker:CreateTexture(nil, "OVERLAY"); head:SetColorTexture(0.95, 0.76, 0.19, 1); head:SetSize(10, 10); head:SetPoint("TOP")
  local stem = p.marker:CreateTexture(nil, "OVERLAY"); stem:SetColorTexture(0.95, 0.76, 0.19, 1); stem:SetSize(3, 28); stem:SetPoint("TOP", 0, -10)
  p.track = track

  -- Axis cards
  local cw = (TRACK_W - 16) / 3
  p.cards = {}
  local names = { "TURN", "TILT", "ZOOM" }
  for i = 1, 3 do
    local c = axisCard(R, cw, 54, names[i])
    c:SetPoint("BOTTOMLEFT", (i - 1) * (cw + 8), 0)
    p.cards[i] = c
  end
  p.cards[2].state:SetText("locked"); p.cards[2].state:SetTextColor(unpack(COL_GREEN))
  p.cards[2].body:SetText("From step 1. Mouse moved? Go back.")
  p.cards[3].body:SetText("Unchanged since step 1.")
  return p
end

View.MACRO_RAPTOR = "#showtooltip\n/stopcasting\n/cast Raptor Strike\n/startattack\n/run NockCamFlip()"
View.MACRO_SHOT = "#showtooltip\n/cast !Auto Shot\n/run NockCamFace()"

function View:BuildStep3(parent)
  local p = page(parent)
  local L = CreateFrame("Frame", nil, p)
  L:SetPoint("TOPLEFT", 18, -14); L:SetPoint("BOTTOMLEFT", 18, 12); L:SetWidth(LEFT_W - 36)
  local ok = box(L, { 0.49, 0.85, 0.34, 1 }, { 0.49, 0.85, 0.34, 1 }); ok:SetSize(20, 20); ok:SetPoint("TOPLEFT", 0, -2)
  local okT = fs(ok, 11, COL_INK, "", monoFont()); okT:SetPoint("CENTER"); okT:SetText("v")
  p.saved = fs(L, 12, COL_TEXT, "")
  p.saved:SetPoint("TOPLEFT", 28, 0); p.saved:SetPoint("RIGHT"); p.saved:SetWordWrap(true)
  local blurb = fs(L, 10, COL_DIM, "")
  blurb:SetPoint("TOPLEFT", 0, -44); blurb:SetPoint("RIGHT"); blurb:SetWordWrap(true)
  blurb:SetText("Try it here, no target needed. Out turns you away and keeps the view on the spot you looked at. Back turns you toward it again.")
  p.testOut = button(L, 103, 26, "Test out", true); p.testOut:SetPoint("TOPLEFT", 0, -122)
  p.testOut:SetScript("OnClick", function() if self.ctrl and self.ctrl.onTestOut then self.ctrl.onTestOut() end end)
  p.testBack = button(L, 103, 26, "Test back"); p.testBack:SetPoint("LEFT", p.testOut, "RIGHT", 8, 0)
  p.testBack:SetScript("OnClick", function() if self.ctrl and self.ctrl.onTestBack then self.ctrl.onTestBack() end end)
  local note = fs(L, 10, COL_DIM, "")
  note:SetPoint("BOTTOMLEFT"); note:SetPoint("RIGHT"); note:SetWordWrap(true)
  note:SetText("Changed your zoom or tilt later? Run this setup again; it takes twenty seconds.")

  local R = CreateFrame("Frame", nil, p)
  R:SetPoint("TOPLEFT", LEFT_W + 18, -14); R:SetPoint("BOTTOMRIGHT", -18, 12)
  local h = fs(R, 9, COL_FAINT, ""); h:SetPoint("TOPLEFT"); h:SetText("YOUR TWO MACROS")
  local function macroRow(y, label, code, lines)
    local l = fs(R, 10, COL_DIM, ""); l:SetPoint("TOPLEFT", 0, y); l:SetText(label)
    local b = box(R, COL_CARD, COL_LINE); b:SetPoint("TOPLEFT", 0, y - 16); b:SetPoint("RIGHT"); b:SetHeight(14 * lines + 14)
    local t = fs(b, 10, COL_TEXT, "", monoFont()); t:SetPoint("TOPLEFT", 10, -7); t:SetPoint("BOTTOMRIGHT", -60, 7)
    t:SetJustifyV("TOP"); t:SetText(code)
    local cp = button(b, 46, 18, "Copy"); cp:SetPoint("TOPRIGHT", -6, -6)
    cp:SetScript("OnClick", function() if self.ctrl and self.ctrl.onCopy then self.ctrl.onCopy(code) end end)
  end
  macroRow(-18, "Raptor Strike  ·  the last line turns you away on the hit", View.MACRO_RAPTOR, 5)
  macroRow(-124, "Auto Shot spam  ·  the last line turns you back, safe to spam", View.MACRO_SHOT, 3)
  local tip = fs(R, 10, COL_DIM, ""); tip:SetPoint("BOTTOMLEFT"); tip:SetPoint("RIGHT"); tip:SetWordWrap(true)
  tip:SetText("Copy opens a window you can select from. Turn on the key press instead of the hit with |cffe9e6dcNockCamFlip(true)|r.")
  return p
end

-----------------------------------------------------------------------------
-- Open / render
-----------------------------------------------------------------------------

-- ctrl = { onClose, onSkip, onBack, onRedo, onFix, onTestOut, onTestBack, onCopy(code) }
function View:Open(ctrl)
  self:Build()
  self.ctrl = ctrl
  self._key = nil
  self.frame:Show()
end

function View:Close()
  if self.frame then self.frame:Hide() end
  self.ctrl = nil
end

function View:IsOpen()
  return self.frame ~= nil and self.frame:IsShown()
end

local function setChip(c, active, done)
  Nock.UI.ApplyBackdrop(c, active and { 0.95, 0.76, 0.19, 1 } or { 0, 0, 0, 0 }, active and { 0.95, 0.76, 0.19, 1 } or { 0.23, 0.23, 0.25, 1 })
  c.label:SetTextColor(unpack(active and COL_INK or (done and COL_DIM or COL_FAINT)))
end

-- d = { step, facingDeg, off, ok, zoom, styleWarn, savedOff, savedZoom }
function View:Render(d)
  if not self:IsOpen() then return end
  local key = table.concat({ tostring(d.step), tostring(d.facingDeg), tostring(d.ok), tostring(d.zoom), tostring(d.styleWarn) }, ":")
  if key == self._key then return end
  self._key = key
  local step = d.step or 1
  for i = 1, 3 do
    setChip(self.chips[i], i == step, i < step)
    self.pages[i]:SetShown(i == step)
  end
  local warn = d.styleWarn == true and step == 3
  self.banner:SetShown(warn)
  self.body:SetPoint("TOPLEFT", 0, -HEADER_H - 1 - (warn and 31 or 0))
  self.btnSkip:SetShown(step ~= 3)
  self.btnBack:SetShown(step == 2)
  self.btnDone:SetShown(step == 3)
  self.btnRedo:SetShown(step == 3)
  local zoomText = type(d.zoom) == "number" and ("%.1f yd"):format(d.zoom) or "?"
  if step == 1 then
    local p = self.pages[1]
    p.zoomState:SetText(zoomText)
    p.zoomBig:SetText("distance  " .. zoomText)
    self.footText:SetText(d.styleWarn and "Camera style: needs Never adjust" or "Camera style: Never adjust  ·  Instant view switch")
  elseif step == 2 then
    local p = self.pages[2]
    local pillText, state, hint = View.TurnTexts(d.off, d.ok)
    local color = d.ok and COL_GREEN or ((d.off and math.abs(d.off) <= NEAR_DEG) and COL_GOLD or COL_TEXT)
    p.offBig:SetText(View.OffText(d.off))
    p.offBig:SetTextColor(unpack(color))
    p.pill.text:SetText(pillText)
    Nock.UI.ApplyBackdrop(p.pill, d.ok and { 0.49, 0.85, 0.34, 1 } or { 0.15, 0.15, 0.17, 1 }, d.ok and { 0.49, 0.85, 0.34, 1 } or { 0.15, 0.15, 0.17, 1 })
    p.pill.text:SetTextColor(unpack(d.ok and COL_INK or COL_DIM))
    p.tick:SetColorTexture(d.ok and 0.49 or 0.31, d.ok and 0.85 or 0.48, d.ok and 0.34 or 0.21, 1)
    p.marker:ClearAllPoints()
    p.marker:SetPoint("TOP", p.track, "TOPLEFT", View.MarkerX(d.off, TRACK_W), 16)
    p.marker:SetShown(d.off ~= nil)
    p.cards[1].state:SetText(state); p.cards[1].state:SetTextColor(unpack(color))
    p.cards[1].body:SetText(hint)
    p.cards[3].state:SetText(zoomText); p.cards[3].state:SetTextColor(unpack(COL_GREEN))
    self.footText:SetText(("Live facing %s deg"):format(d.facingDeg and ("%.1f"):format(d.facingDeg) or "?"))
  else
    local p = self.pages[3]
    p.saved:SetText(("Camera saved at %s, %s off"):format(
      type(d.savedZoom) == "number" and ("%.1f yd"):format(d.savedZoom) or zoomText,
      d.savedOff and ("%.1f deg"):format(math.abs(d.savedOff)) or "?"))
    self.footText:SetText("Views saved  ·  ready")
  end
end
