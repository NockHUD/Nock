-- UI/Frame_Settings.lua
-- The settings window: sidebar (families + pages, the nocked arrow), hero, tab strip, card column and footer, drawn from Nock.OptionsWalk.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Settings = Nock:NewModule("Settings", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
Nock.Settings = Settings
local Skin = Nock.Skin
local W = Nock.OptionsWalk
local APP = "Nock"
local SC = Nock.UI.SettingsControls
local SEV = { red = "bad", amber = "wait" }

Settings.W, Settings.H = 1160, 800
Settings.SIDE_W, Settings.HERO_H, Settings.TABS_H, Settings.FOOT_H = 256, 148, 40, 56
Settings.CARD_PAD, Settings.ROW_H = 24, 54
local NAV_ROW_H, NAV_HEAD_H, NAV_PAD_L = 25, 24, 32
local NAV_ICON = { general = "sliders", classic = "rows", react = "bolt", fluffy = "equalizer", warnings = "warn", helpers = "pill", sounds = "bell", aggro = "focus",
  buffTracker = "shield", debuffTracker = "skull", totemTracker = "signal", misdirect = "turn", qol = "gear", shopping = "cart", mailbox = "envelope",
  weaveBind = "keyboard", garment = "shirt", tonk = "wrench", practice = "target", experimental = "flask", profiles = "profiles" }

local function text(parent, role, size, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  Skin.Font(fs, role, size)
  Skin.Text(fs, color or "ink")
  fs:SetJustifyH("LEFT")
  return fs
end

-- Scale: the profile's settingsScale (General › Frames slider; default 1)
-- times the workbench's screen fit, tallest-seen so it never breathes.
local function settingsScale()
  local v = Nock.db and Nock.db.profile and Nock.db.profile.settingsScale
  if type(v) ~= "number" then return 1 end
  return math.max(0.75, math.min(2, v))
end

function Settings:ApplyScale()
  local wb = Nock:GetModule("PracticeWorkbench", true)
  local fit = 1
  if wb and wb.FitScale then fit = wb.FitScale(Settings.W, Settings.H, settingsScale(), UIParent:GetWidth(), UIParent:GetHeight()) end
  local f = self.frame
  local s = settingsScale() * fit
  if f:GetScale() ~= s then
    f:SetScale(s)
    -- a scale change re-centres: the remembered spot was measured at the old size
    if Nock.db and Nock.db.profile then Nock.db.profile.settingsPos = false end
    self:ApplyPosition()
  end
end

-- The remembered drag spot, or the screen centre.
function Settings:ApplyPosition()
  local f = self.frame
  local pos = Nock.db and Nock.db.profile and Nock.db.profile.settingsPos
  f:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

function Settings:OnInitialize()
  local f = CreateFrame("Frame", "NockSettings", UIParent)
  self.frame = f
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetSize(Settings.W, Settings.H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  Skin.Surface(f, "surface", "line")
  f:Hide()
  tinsert(UISpecialFrames, "NockSettings")
  f:SetScript("OnHide", function()
    local own = not Settings._hiding
    Settings._hiding = false
    if own and not f:IsShown() then Settings:Close() end
  end)
  f:SetScript("OnShow", function() Settings:Invalidate("show") end)
  self:BuildSidebar()
  self:BuildMain()
  self.state = { page = nil, tab = {}, scroll = {} }
  W.Subscribe(APP, self, function() Settings.index = nil; Settings:Invalidate("ConfigTableChange") end)
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "RefreshLater")
  self:RegisterMessage("NOCK_LOCK_CHANGED", "RefreshLater")
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "RefreshLater")
  self:RegisterMessage("NOCK_WEAVEBIND_CHANGED", "RefreshLater")
  self:RegisterMessage("NOCK_EDITGRID_CHANGED", "RefreshLater")
  self:RegisterEvent("PLAYER_REGEN_DISABLED", "RefreshLater")
  self:RegisterEvent("PLAYER_REGEN_ENABLED", "RefreshLater")
  self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "RefreshLater")
end

-- One repaint per frame however many messages arrive (a set() that fires
-- VISUALS and NotifyChange in the same call must not rebuild twice, and never
-- inside the control that is still executing its own click).
Settings.DEBUG = false  -- render/click log behind /nock settingslog; flip on while chasing a window bug
-- Diagnostics go to a buffer the user opens with /nock settingslog (a copybox,
-- never chat: project rule for anything pasted back).
Settings._log = {}
function Settings:Log(line)
  local L = self._log
  L[#L + 1] = ("%.2f  %s"):format(GetTime and GetTime() or 0, tostring(line))
  if #L > 400 then table.remove(L, 1) end
end
function Settings:ShowLog()
  if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(table.concat(self._log, "\n")) end
end
-- The central tick's Refresh(state): the ONE per-frame job this window has is
-- following a scrollbar drag (no per-frame OnUpdate scripts, project rule).
function Settings:Refresh(state)
  local col = self.col
  if col and col.dragging then col:FollowDrag() end
end
-- Named Invalidate, not Refresh: the central tick calls :Refresh(state) on
-- every module that has one, every frame.
function Settings:RefreshLater(event) self:Invalidate(event or "message") end
function Settings:Invalidate(why)
  if not self.frame:IsShown() then return end
  if self.DEBUG then self:Log(("refresh <- %s%s"):format(tostring(why), self._pending and " (coalesced)" or "")) end
  if self._pending then return end
  self._pending = true
  -- One-shot, next frame (the rule allows C_Timer.After for a coalesce).
  C_Timer.After(0, Settings.RenderWhenSafe)
end

-- The rebuild hides and re-pools every control on the page. Doing that to
-- the slider (or scrollbar) the client is still dragging crashed the client
-- twice (2026-09-06: ACCESS_VIOLATION in Hide), so it waits for the button.
-- Anything the client or the user is still holding in the window blocks a
-- rebuild the same way: a mouse drag, a colour picker feeding a swatch, a
-- key capture on a keybind row, an edit box with keyboard focus.
local function insideWindow(frame)
  local f, hops = frame, 0
  while f and hops < 40 do
    if f == Settings.frame then return true end
    f = f.GetParent and f:GetParent() or nil
    hops = hops + 1
  end
  return false
end
function Settings.Busy()
  if IsMouseButtonDown and IsMouseButtonDown("LeftButton") then return "mouse" end
  if ColorPickerFrame and ColorPickerFrame:IsShown() then return "colorpicker" end
  local rgba = _G.NockSettingsRGBA
  if rgba and rgba:IsShown() then return "rgba" end
  if Nock.UI.KeyCapture and Nock.UI.KeyCapture.IsActive() then return "keycapture" end
  local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
  if focus and focus ~= Settings.searchBox and insideWindow(focus) then return "editbox" end
  return nil
end
function Settings.RenderWhenSafe()
  if Settings.Busy() then
    C_Timer.After(0.05, Settings.RenderWhenSafe)
    return
  end
  Settings._pending = false
  if not Settings.frame:IsShown() or Settings._rendering then return end
  Settings._rendering = true
  local okr, err = pcall(Settings.Render, Settings)
  Settings._rendering = false
  if not okr then
    Settings._lastError = tostring(err)
    Settings:Log(("render error: %s"):format(tostring(err)))
    Settings:Print(("render error: %s"):format(tostring(err)))
  end
end

function Settings:BuildSidebar()
  local f = self.frame
  local side = CreateFrame("Frame", nil, f)
  side:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  side:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  side:SetWidth(Settings.SIDE_W)
  Skin.Surface(side, "surface")
  local rule = Skin.Rule(side, "line")
  rule:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, 0); rule:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0); rule:SetWidth(1)
  self.side = side

  local logo = side:CreateTexture(nil, "ARTWORK")
  logo:SetSize(44, 44)
  logo:SetPoint("TOPLEFT", side, "TOPLEFT", 16, -16)
  Skin.Logo(logo, "logo")
  local name = text(side, "display", 30, "ink")
  name:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
  name:SetText("NOCK")
  local ver = text(side, "mono", Skin.SIZES.mono, "ink3")
  ver:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 1, -2)
  ver:SetText("v" .. (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Nock", "Version") or ""))

  -- Search field (behaviour in Task 16; the box is part of the shell gate).
  local search = CreateFrame("Frame", nil, side)
  search:SetPoint("TOPLEFT", side, "TOPLEFT", 14, -74)
  search:SetPoint("TOPRIGHT", side, "TOPRIGHT", -14, -74)
  search:SetHeight(34)
  Skin.Surface(search, "ground", "line")
  local glass = search:CreateTexture(nil, "ARTWORK")
  glass:SetPoint("LEFT", search, "LEFT", 10, 0)
  Skin.Icon(glass, "magnifier", "ink3"); Skin.IconSize(glass, 14)
  local box = CreateFrame("EditBox", nil, search)
  box:SetPoint("LEFT", glass, "RIGHT", 8, 0)
  box:SetPoint("RIGHT", search, "RIGHT", -28, 0)
  box:SetHeight(30)
  box:SetAutoFocus(false)
  Skin.Font(box, "ui", 13)
  box:SetTextColor(Skin.Color("ink"))
  box:SetScript("OnEscapePressed", function(b) b:SetText(""); b:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(b)
    local first = Settings._searchFirst
    if first then first() else b:ClearFocus() end
  end)
  local hint = text(search, "ui", 13, "ink3")
  hint:SetPoint("LEFT", box, "LEFT", 0, 0)
  hint:SetText("Search settings")
  box:SetScript("OnTextChanged", function(b) hint:SetShown(b:GetText() == ""); if Settings.OnQuery then Settings:OnQuery(b:GetText()) end end)
  self.searchBox, self.searchFrame = box, search

  -- Simple | Advanced (spec 2026-09-09 §2): a two-segment pill; the active
  -- segment fills accent. Tooltip on the whole pill.
  local mode = CreateFrame("Frame", nil, side)
  mode:SetPoint("TOPLEFT", side, "TOPLEFT", 14, -114)
  mode:SetPoint("TOPRIGHT", side, "TOPRIGHT", -14, -114)
  mode:SetHeight(26)
  Skin.Surface(mode, "ground", "line")
  mode:EnableMouse(true)
  mode:SetScript("OnEnter", function(m) SC.ShowTooltip(m, "Simple / Advanced", "Simple shows the switches and pickers. Advanced adds colours, sizes, offsets and every tuning knob.") end)
  mode:SetScript("OnLeave", function() SC.HideTooltip() end)
  local segW = (Settings.SIDE_W - 28 - 2) / 2
  local function seg(label, adv, anchor)
    local b = CreateFrame("Button", nil, mode)
    b:SetSize(segW, 24)
    b:SetPoint(anchor, mode, anchor, adv and -1 or 1, 0)
    b.fill = b:CreateTexture(nil, "BACKGROUND"); b.fill:SetAllPoints(b)
    b.text = text(b, "uiMedium", 12, "ink2"); b.text:SetPoint("CENTER", b, "CENTER", 0, 0); b.text:SetText(label)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetScript("OnClick", function(bb)
      local now = GetTime()
      if bb._acted and now - bb._acted < 0.3 then bb._acted = nil return end
      bb._acted = now
      Settings:SetMode(adv)
    end)
    b:SetScript("OnEnter", function(bb) if not bb.active then Skin.Text(bb.text, "ink") end; SC.ShowTooltip(mode, "Simple / Advanced", "Simple shows the switches and pickers. Advanced adds colours, sizes, offsets and every tuning knob.") end)
    b:SetScript("OnLeave", function(bb) if not bb.active then Skin.Text(bb.text, "ink2") end; SC.HideTooltip() end)
    return b
  end
  self.modeSimple, self.modeAdvanced = seg("Simple", false, "LEFT"), seg("Advanced", true, "RIGHT")

  local nav = CreateFrame("Frame", nil, side)
  nav:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -150)
  nav:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
  self.nav = nav
  -- The bowstring: a 1 px line, plus the nock (two short slanted lines), the
  -- 2 px shaft and the head (a 7 px chevron drawn as two 2 px lines), all
  -- textures so the client draws nothing it has to rasterise.
  local string1 = Skin.Rule(nav, "ink3"); string1:SetWidth(1); string1:SetAlpha(0.5)
  local string2 = Skin.Rule(nav, "ink3"); string2:SetWidth(1); string2:SetAlpha(0.5)
  local shaft = nav:CreateTexture(nil, "ARTWORK"); Skin.Paint(shaft, "accent", 1); shaft:SetSize(10, 2)
  local headA = nav:CreateTexture(nil, "ARTWORK"); Skin.Paint(headA, "accent", 1); headA:SetSize(2, 8)
  local headB = nav:CreateTexture(nil, "ARTWORK"); Skin.Paint(headB, "accent", 1); headB:SetSize(4, 2)
  local nockA = nav:CreateTexture(nil, "ARTWORK"); Skin.Paint(nockA, "ink3", 1); nockA:SetSize(6, 1)
  local nockB = nav:CreateTexture(nil, "ARTWORK"); Skin.Paint(nockB, "ink3", 1); nockB:SetSize(6, 1)
  self.string = { string1, string2, shaft, headA, headB, nockA, nockB }
  self.navRows, self.navHeads = {}, {}
end

local function navRow(self, i)
  local r = self.navRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, self.nav)
  r:SetHeight(NAV_ROW_H)
  r:SetPoint("LEFT", self.nav, "LEFT", 0, 0)
  r:SetPoint("RIGHT", self.nav, "RIGHT", 0, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetPoint("LEFT", r, "LEFT", NAV_PAD_L, 0)
  r.label = text(r, "ui", 13, "ink2")
  r.label:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
  r.count = text(r, "mono", Skin.SIZES.mono, "ink3")
  r.count:SetPoint("RIGHT", r, "RIGHT", -12, 0)
  r.count:SetJustifyH("RIGHT")
  r.live = text(r, "mono", 9, "ink3")
  r.live:SetPoint("LEFT", r.label, "RIGHT", 8, 0)
  r.live:SetText("LIVE")
  r:EnableMouse(true)
  r:RegisterForClicks("AnyUp", "AnyDown")
  r:SetScript("OnEnter", function(b)
    if not b.active then Skin.Text(b.label, "ink"); Skin.Icon(b.icon, b.iconName, "ink2") end
  end)
  r:SetScript("OnLeave", function(b) if not b.active then Skin.Text(b.label, "ink2"); Skin.Icon(b.icon, b.iconName, "ink3") end end)
  -- The client may deliver the press, the release, or both: act once per press.
  -- This client fires OnClick on the press (down = true) and may or may not
  -- follow with the release: act on the first edge, swallow the second.
  r:SetScript("OnClick", function(b, button, down)
    if Settings.DEBUG then Settings:Log(("click %s %s down=%s"):format(tostring(b.pageKey), tostring(button), tostring(down))) end
    local now = GetTime()
    if b._acted and now - b._acted < 0.3 then b._acted = nil return end
    b._acted = now
    Settings:SelectPage(b.pageKey)
  end)
  self.navRows[i] = r
  return r
end

local function navHead(self, i)
  local h = self.navHeads[i]
  if h then return h end
  h = text(self.nav, "mono", 10, "ink3")
  h:SetPoint("LEFT", self.nav, "LEFT", NAV_PAD_L, 0)
  self.navHeads[i] = h
  return h
end

-- Lays the nav out from the walker's nav model; `counts` overrides the
-- per-page numbers (search mode), `arrowOn` false hides the nock.
function Settings:RenderNav(nav, counts, arrowOn)
  local y, ri, hi, activeY = 0, 0, 0, nil
  for _, r in ipairs(self.navRows) do r:Hide() end
  for _, h in ipairs(self.navHeads) do h:Hide() end
  local live = Nock.db.profile.hudMode or "classic"
  -- Fit: the list must never run past the sidebar. Measure the natural height
  -- and, when it overflows, tighten the head gap, then the head height, then
  -- the row height (down to 20 px), so every page stays reachable however
  -- many there are. The window itself keeps the height its art was cut for.
  local rowH, headGap, headH = NAV_ROW_H, 10, NAV_HEAD_H
  do
    local nRows, nHeads, nLoose = 0, 0, 0
    for _, g in ipairs(nav.groups) do
      if g.head then nHeads = nHeads + 1 else nLoose = nLoose + 1 end
      nRows = nRows + #g.pages
    end
    local avail = (self.nav:GetHeight() or 0) - 8
    if avail > 100 and nRows > 0 then
      local function total() return nRows * rowH + nHeads * (headH + headGap) + nLoose * 2 end
      if total() > avail then headGap = 4 end
      if total() > avail then headH = 20 end
      if total() > avail then rowH = math.max(20, math.floor((avail - nHeads * (headH + headGap) - nLoose * 2) / nRows)) end
    end
  end
  for _, g in ipairs(nav.groups) do
    if g.head then
      hi = hi + 1
      local h = navHead(self, hi)
      h:SetText(g.head:upper())
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", self.nav, "TOPLEFT", NAV_PAD_L, -(y + headGap))
      h:Show()
      y = y + headH
    else
      y = y + 2
    end
    for _, p in ipairs(g.pages) do
      ri = ri + 1
      local r = navRow(self, ri)
      r.pageKey = p.key
      r.iconName = NAV_ICON[p.key] or "gear"
      r.active = (not counts) and (self.state.page == p.key)
      r.label:SetText(p.name)
      -- search mode: the page's hit count, blank when nothing matched (never
      -- the page's own control count, which reads as noise next to real hits)
      local n
      if counts then n = counts[p.key] or 0 else n = p.count end
      r.count:SetText((p.key == "profiles" or n == nil or (counts and n == 0)) and "" or tostring(n))
      r.live:SetShown(p.key == live and not counts)
      local lc, ic, cc = "ink2", "ink3", "ink3"
      if counts then
        if (n or 0) > 0 then lc, ic, cc = "ink", "ink2", "accent" else lc, ic, cc = "ink3", "ink3", "ink3" end
      elseif r.active then lc, ic, cc = "ink", "accent", "accent" end
      Skin.Text(r.label, lc); Skin.Text(r.count, cc)
      Skin.Icon(r.icon, r.iconName, ic); Skin.IconSize(r.icon, 16)
      r.icon:ClearAllPoints()
      r.icon:SetPoint("LEFT", r, "LEFT", r.active and NAV_PAD_L + 4 or NAV_PAD_L, 0)
      r:ClearAllPoints()
      r:SetHeight(rowH)
      r:SetPoint("TOPLEFT", self.nav, "TOPLEFT", 0, -y)
      r:SetPoint("TOPRIGHT", self.nav, "TOPRIGHT", 0, -y)
      r:Show()
      if r.active then activeY = y + rowH / 2 end
      y = y + rowH
    end
  end
  local s1, s2, shaft, headA, headB, nockA, nockB = unpack(self.string)
  local X = 14
  if arrowOn and activeY then
    s1:ClearAllPoints(); s1:SetPoint("TOPLEFT", self.nav, "TOPLEFT", X, 0); s1:SetHeight(activeY - 9); s1:Show()
    s2:ClearAllPoints(); s2:SetPoint("TOPLEFT", self.nav, "TOPLEFT", X, -(activeY + 9)); s2:SetHeight(math.max(1, y - activeY - 9)); s2:Show()
    nockA:ClearAllPoints(); nockA:SetPoint("TOPLEFT", self.nav, "TOPLEFT", X - 5, -(activeY - 5)); nockA:SetRotation(math.rad(-60)); nockA:Show()
    nockB:ClearAllPoints(); nockB:SetPoint("TOPLEFT", self.nav, "TOPLEFT", X - 5, -(activeY + 4)); nockB:SetRotation(math.rad(60)); nockB:Show()
    shaft:ClearAllPoints(); shaft:SetPoint("LEFT", self.nav, "TOPLEFT", X - 5, -activeY); shaft:Show()
    headA:ClearAllPoints(); headA:SetPoint("LEFT", self.nav, "TOPLEFT", X + 5, -activeY); headA:SetRotation(math.rad(45)); headA:Show()
    headB:ClearAllPoints(); headB:SetPoint("LEFT", self.nav, "TOPLEFT", X + 8, -activeY); headB:Show()
  else
    s1:ClearAllPoints(); s1:SetPoint("TOPLEFT", self.nav, "TOPLEFT", X, 0); s1:SetHeight(math.max(1, y)); s1:Show()
    s2:Hide(); shaft:Hide(); headA:Hide(); headB:Hide(); nockA:Hide(); nockB:Hide()
  end
end

function Settings:BuildMain()
  local f = self.frame
  local main = CreateFrame("Frame", nil, f)
  main:SetPoint("TOPLEFT", f, "TOPLEFT", Settings.SIDE_W, 0)
  main:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  self.main = main

  local hero = CreateFrame("Frame", nil, main)
  hero:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 0)
  hero:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, 0)
  hero:SetHeight(Settings.HERO_H)
  local art = hero:CreateTexture(nil, "BACKGROUND")
  art:SetAllPoints(hero)
  art:SetTexture(Skin.MEDIA .. "SettingsHero")
  local scrim = hero:CreateTexture(nil, "BORDER")
  scrim:SetAllPoints(hero)
  scrim:SetColorTexture(1, 1, 1, 1)
  -- left→right: 0.94 → 0.18 of surface; bottom-up fade drawn by a second texture
  local r, g, b = Skin.Color("surface")
  if scrim.SetGradient and CreateColor then scrim:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.94), CreateColor(r, g, b, 0.18))
  else scrim:SetColorTexture(r, g, b, 0.6) end
  local fade = hero:CreateTexture(nil, "BORDER", nil, 1)
  fade:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 0, 0)
  fade:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", 0, 0)
  fade:SetHeight(60)
  fade:SetColorTexture(1, 1, 1, 1)
  if fade.SetGradient and CreateColor then fade:SetGradient("VERTICAL", CreateColor(r, g, b, 0.85), CreateColor(r, g, b, 0))
  else fade:SetColorTexture(r, g, b, 0.5) end
  local heroRule = Skin.Rule(hero, "line")
  heroRule:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 0, 0); heroRule:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", 0, 0); heroRule:SetHeight(1)
  self.eyebrow = text(hero, "mono", Skin.SIZES.mono, "accent")
  self.eyebrow:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 28, 66)
  self.title = text(hero, "display", 44, "ink")
  self.title:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 28, 18)
  local close = CreateFrame("Button", nil, hero)
  close:SetSize(30, 30)
  close:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -16, -14)
  Skin.Surface(close, "raised", "line")
  local x = close:CreateTexture(nil, "ARTWORK")
  x:SetPoint("CENTER")
  Skin.Icon(x, "close", "ink2"); Skin.IconSize(x, 14)
  close:SetScript("OnClick", function() Settings:Close() end)
  -- the hero band drags the window; the spot is kept per profile
  hero:EnableMouse(true)
  hero:RegisterForDrag("LeftButton")
  hero:SetScript("OnDragStart", function() Settings.frame:StartMoving() end)
  hero:SetScript("OnDragStop", function()
    local f = Settings.frame
    f:StopMovingOrSizing()
    f:SetUserPlaced(false)
    local point, _, relPoint, x, y = f:GetPoint(1)
    if point and Nock.db and Nock.db.profile then
      Nock.db.profile.settingsPos = { point = point, relPoint = relPoint, x = x, y = y }
    end
  end)
  self.hero = hero

  local tabs = CreateFrame("Frame", nil, main)
  tabs:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, 0)
  tabs:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, 0)
  tabs:SetHeight(Settings.TABS_H)
  local tabRule = Skin.Rule(tabs, "line")
  tabRule:SetPoint("BOTTOMLEFT", tabs, "BOTTOMLEFT", 0, 0); tabRule:SetPoint("BOTTOMRIGHT", tabs, "BOTTOMRIGHT", 0, 0); tabRule:SetHeight(1)
  self.tabs, self.tabBtns = tabs, {}
  local probe = text(tabs, "uiMedium", 12, "ink2"); probe:Hide()
  self._measure = function(s) probe:SetText(s); return probe:GetStringWidth() or (#s * 7) end
  self.tabNote = text(tabs, "mono", Skin.SIZES.mono, "ink3")
  self.tabNote:SetPoint("RIGHT", tabs, "RIGHT", -20, 0)

  local foot = CreateFrame("Frame", nil, main)
  foot:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 0, 0)
  foot:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, 0)
  foot:SetHeight(Settings.FOOT_H)
  local footRule = Skin.Rule(foot, "line")
  footRule:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, 0); footRule:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, 0); footRule:SetHeight(1)
  self.lockIcon = foot:CreateTexture(nil, "ARTWORK")
  self.lockIcon:SetPoint("LEFT", foot, "LEFT", 24, 0)
  self.lockText = text(foot, "uiMedium", 12, "ink")
  self.lockText:SetPoint("LEFT", self.lockIcon, "RIGHT", 8, 0)
  self.lockBtn = Skin.Button(foot, "Unlock", "ghost", nil, 32)
  self.lockBtn:SetPoint("LEFT", self.lockText, "RIGHT", 16, 0)
  self.lockBtn:SetScript("OnClick", function() Nock:SetLocked(not Nock.IsLocked()) end)
  self.status = text(foot, "mono", Skin.SIZES.mono, "ink3")
  self.status:SetPoint("CENTER", foot, "CENTER", 40, 0)
  local edit = Skin.Button(foot, "Edit mode", "ghost", nil, 32)
  edit:SetPoint("RIGHT", foot, "RIGHT", -24, 0)
  edit:SetScript("OnClick", function() Nock:SetLocked(false); Settings:Close() end)
  local reset = Skin.Button(foot, "Reset page", "ghost", nil, 32)
  reset:SetPoint("RIGHT", edit, "LEFT", -10, 0)
  reset:SetScript("OnClick", function() Settings:ResetPage() end)
  self.foot = foot

  local col = Nock.UI.ScrollColumn.New(main, Settings.ROW_H)
  col.frame:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, 0)
  col.frame:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, 0)
  col.onScroll = function(y)
    if Nock.UI.SettingsControls then Nock.UI.SettingsControls.HideTooltip() end
    local st = Settings.state
    local pg = st and st.page
    if pg then st.scroll[pg .. "/" .. (st.tab[pg] or "__self")] = y end
  end
  self.col = col
  self.cards = {}
  SC.OnWheel = function(delta) col:ScrollTo(col:GetScroll() - delta * Settings.ROW_H * (IsShiftKeyDown() and 3 or 1)) end
end

function Settings:IsOpen() return self.frame:IsShown() end

function Settings:Open()
  self.nav_model = nil
  if not self.state.page then self.state.page = Nock.db.profile.hudMode or "classic" end
  self:ApplyScale()
  self:ApplyPosition()
  self.frame:Show()
end

function Settings:Close()
  if not self.frame:IsShown() then return end
  self._hiding = true
  self.modeOverride = nil
  self.searchBox:SetText("")
  self.frame:Hide()
  -- session-only previews (React/Fluffy grid "light every tile", the coach
  -- stage preview) end with the window; the old dialog left them on for good
  if Nock.UI.activePreview or Nock.UI.stagePreview then
    Nock.UI.activePreview, Nock.UI.stagePreview = false, false
    Nock:SendMessage("NOCK_VISUALS_CHANGED")
  end
  if Nock.UI.SettingsControls then Nock.UI.SettingsControls.HideTooltip() end
  if Nock.UI.KeyCapture then Nock.UI.KeyCapture.End() end
end

function Settings:Toggle() if self:IsOpen() then self:Close() else self:Open() end end

function Settings:SelectPage(key)
  if self.DEBUG then self:Log(("page -> %s"):format(tostring(key))) end
  self.state.page = key
  self.searchBox:SetText("")
  self:Invalidate("page")
end

function Settings:SelectTab(key)
  if self.DEBUG then self:Log(("tab -> %s"):format(tostring(key))) end
  self.state.tab[self.state.page] = key
  self:Invalidate("tab")
end

-- Keys down the args chain: family, page, [tab]. "utilities","practice","keys".
function Settings:SelectGroup(...)
  local a, b, c = ...
  if W.FAMILY_KEYS[a] then self.state.page = b; if c then self.state.tab[b] = c end
  else self.state.page = a; if b then self.state.tab[a] = b end end
  self:Open()
  self:Invalidate("select")
end

local function findPage(nav, key)
  for _, g in ipairs(nav.groups) do for _, p in ipairs(g.pages) do if p.key == key then return p, g end end end
end

function Settings:Render()
  self:ApplyScale()  -- a slider drag rescales the window live
  local root = W.Root(APP)
  if self.DEBUG then self:Log(("render page=%s root=%s"):format(tostring(self.state.page), tostring(root ~= nil))) end
  if not root then return end
  W.SetMode(self:IsAdvanced() and "advanced" or "simple")
  self:PaintMode()
  local nav = W.Nav(root, APP)
  self.nav_model = nav
  if #(self.state.q or "") >= 2 then return self:RenderSearch(root, nav) end
  local page, group = findPage(nav, self.state.page)
  if not page then page, group = nav.groups[1].pages[1], nav.groups[1] end
  self.state.page = page.key
  self:RenderNav(nav, nil, true)
  self.eyebrow:SetText((group.head or "General"):upper() .. (self:IsAdvanced() and "  ·  ADVANCED" or ""))
  self.title:SetText(page.name)
  local pg = W.Page(page.node, page.path, APP)
  if pg.allAdvanced then
    self:RenderTabs({}, nil)
    self:ClearContent()
    self:RenderEmptyAdvanced(page, pg.dropped or 0)
    self:RenderFooter()
    return
  end
  local tabKey = self.state.tab[page.key]
  local tab = pg.tabs[1]
  for _, t in ipairs(pg.tabs) do if t.key == tabKey then tab = t end end
  if not tabKey and page.key == "classic" then for _, t in ipairs(pg.tabs) do if t.key == "rotation" then tab = t end end end
  self.state.tab[page.key] = tab.key
  self._firstTab = pg.tabs[1]
  self:RenderTabs(pg.tabs, tab)
  local colW = self.col.frame:GetWidth() or (Settings.W - Settings.SIDE_W)
  if colW < 100 then colW = Settings.W - Settings.SIDE_W end
  self.col.content:SetWidth(colW)
  local cards, dropped = W.Cards(tab, APP, colW - Settings.CARD_PAD * 2 - 32)
  self:RenderCards(cards, page, tab, dropped)
  self:RenderFooter()
end

function Settings:RenderTabs(tabs, active)
  for _, b in ipairs(self.tabBtns) do b:Hide() end
  if #tabs <= 1 then self.tabs:SetHeight(1); self.tabNote:Hide(); return end
  self.tabs:SetHeight(Settings.TABS_H)
  -- Ten tabs (Classic) do not fit beside the note at the design padding:
  -- measure once, then tighten the padding and drop the note as needed.
  local avail = (self.tabs:GetWidth() or 904) - 40
  local pad, gap = 20, 4
  local function total(p, g)
    local w = 0
    for _, tb in ipairs(tabs) do
      w = w + (self._measure and self._measure(tb.name) or (#tb.name * 7)) + p + g
    end
    return w
  end
  local noteW = (self.tabNote:GetStringWidth() or 90) + 24
  if total(pad, gap) + noteW > avail then pad, gap = 12, 2 end
  local showNote = total(pad, gap) + noteW <= avail
  local x = 20
  for i, t in ipairs(tabs) do
    local b = self.tabBtns[i]
    if not b then
      b = CreateFrame("Button", nil, self.tabs)
      b:SetHeight(Settings.TABS_H)
      b.label = text(b, "uiMedium", 12, "ink2")
      b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
      b.under = b:CreateTexture(nil, "ARTWORK"); Skin.Paint(b.under, "accent", 1)
      b.under:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); b.under:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0); b.under:SetHeight(2)
      b:RegisterForClicks("AnyUp", "AnyDown")
      b:SetScript("OnClick", function(bb)
        local now = GetTime()
        if bb._acted and now - bb._acted < 0.3 then bb._acted = nil return end
        bb._acted = now
        Settings:SelectTab(bb.tabKey)
      end)
      b:SetScript("OnEnter", function(bb) if not bb.active then Skin.Text(bb.label, "ink"); bb.under:SetAlpha(0.5); bb.under:Show() end end)
      b:SetScript("OnLeave", function(bb) if not bb.active then Skin.Text(bb.label, "ink2"); bb.under:Hide() end end)
      self.tabBtns[i] = b
    end
    b.tabKey = t.key
    b.active = (t == active)
    b.label:SetText(t.name)
    b:SetWidth(b.label:GetStringWidth() + pad)
    b:ClearAllPoints()
    b:SetPoint("LEFT", self.tabs, "LEFT", x, 0)
    Skin.Text(b.label, b.active and "ink" or "ink2")
    b.under:SetAlpha(1); b.under:SetShown(b.active)
    b:Show()
    x = x + b:GetWidth() + gap
  end
  self.tabNote:SetShown(showNote)
end

local function releaseCard(c)
  for _, ctl in ipairs(c.ctls) do ctl:Release() end
  c.ctls = {}
  local Probe_card = c.IsShown; Probe_card(c)
  if c.head then local Probe_card_head = c.head.IsShown; Probe_card_head(c.head) end
  if c.cat and c.cat.toggle then SC.Probe("card", "toggle", c.cat.toggle) end
  c:Hide()
end

function Settings:AfterSet(row) self:Invalidate("set") end

-- Simple / Advanced. The profile remembers the choice; search may override it
-- for one visit (modeOverride), cleared on Close.
function Settings:IsAdvanced()
  if self.modeOverride ~= nil then return self.modeOverride end
  return Nock.db.profile.settingsAdvanced == true
end
function Settings:SetMode(advanced)
  Nock.db.profile.settingsAdvanced = advanced and true or false
  self.modeOverride = nil
  self:Invalidate("mode")
end
function Settings:PaintMode()
  local adv = self:IsAdvanced()
  for _, pair in ipairs({ { self.modeSimple, not adv }, { self.modeAdvanced, adv } }) do
    local b, on = pair[1], pair[2]
    b.active = on
    Skin.Paint(b.fill, on and "accent" or "ground", on and 1 or 0)
    Skin.Text(b.text, on and "accentInk" or "ink2")
  end
end

-- Everything the content column can hold, hidden: cards, helper tiles, the
-- empty-state card. Every renderer starts here.
function Settings:ClearContent()
  SC.HideTooltip()
  for _, c in ipairs(self.cards) do releaseCard(c) end
  if self.tileBtns then for _, b in ipairs(self.tileBtns) do b:Hide() end end
  if self.tiles then for _, tl in ipairs(self.tiles) do tl:Hide() end end
  if self.tileHeads then for _, h in ipairs(self.tileHeads) do h:Hide() end end
  if self.emptyCard then self.emptyCard:Hide() end
  if self.presetTiles then for _, t in ipairs(self.presetTiles) do t:Hide() end end
  if self.presetHead then self.presetHead:Hide() end
  if self.ReleaseLayouts then self:ReleaseLayouts() end
end

-- Simple on a page whose every control is advanced: one card that says so.
function Settings:RenderEmptyAdvanced(page, dropped)
  local e = self.emptyCard
  if not e then
    e = CreateFrame("Frame", nil, self.col.content)
    Skin.Surface(e, "surface2", "line")
    e:SetHeight(128)
    e.tick = e:CreateTexture(nil, "ARTWORK"); e.tick:SetSize(3, 16); e.tick:SetPoint("TOPLEFT", e, "TOPLEFT", 16, -20); Skin.Paint(e.tick, "accent", 1)
    e.title = text(e, "displayMedium", 17, "ink"); e.title:SetPoint("LEFT", e.tick, "RIGHT", 12, 0); e.title:SetText("EVERYTHING HERE IS ADVANCED")
    e.body = text(e, "ui", 12, "ink2"); e.body:SetPoint("TOPLEFT", e.title, "BOTTOMLEFT", 0, -10); e.body:SetWordWrap(false)
    e.btn = Skin.Button(e, "Show advanced", "ghost", nil, 28)
    e.btn:SetPoint("TOPLEFT", e.body, "BOTTOMLEFT", 0, -14)
    e.btn:RegisterForClicks("AnyUp", "AnyDown")
    e.btn:SetScript("OnClick", function(b)
      local now = GetTime()
      if b._acted and now - b._acted < 0.3 then b._acted = nil return end
      b._acted = now
      Settings:SetMode(true)
    end)
    self.emptyCard = e
  end
  e.body:SetText(("%d settings on this page are colours, sizes and offsets."):format(dropped))
  local colW = self.col.content:GetWidth() or 0
  if colW < 100 then colW = Settings.W - Settings.SIDE_W end
  e:ClearAllPoints()
  e:SetPoint("TOPLEFT", self.col.content, "TOPLEFT", Settings.CARD_PAD, -(Settings.CARD_PAD - 4))
  e:SetWidth(colW - Settings.CARD_PAD * 2 - 8)
  e:Show()
  self.tabNote:SetText("")
  self.col:SetContentHeight(128 + Settings.CARD_PAD * 2)
  self.col:ScrollTo(0)
end
function Settings:Confirm(text, onYes)
  if Nock.UI.SettingsPopup then return Nock.UI.SettingsPopup.Confirm(text, onYes) end
  StaticPopupDialogs["NOCK_SETTINGS_CONFIRM"] = StaticPopupDialogs["NOCK_SETTINGS_CONFIRM"] or {
    text = "%s", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(self) if self.data then self.data() end end }
  local d = StaticPopup_Show("NOCK_SETTINGS_CONFIRM", text)
  if d then d.data = onYes end
end
function Settings:ResetPage() self:Invalidate("reset") end


local function catalogHeader(c)
  if c.cat then return c.cat end
  local h = c.head
  local cat = {}
  cat.tile = CreateFrame("Frame", nil, h); cat.tile:SetSize(28, 28); cat.tile:SetPoint("LEFT", c.tick, "RIGHT", 12, 0)
  Skin.Surface(cat.tile, "raised", "line")
  cat.icon = cat.tile:CreateTexture(nil, "ARTWORK"); cat.icon:SetPoint("TOPLEFT", cat.tile, "TOPLEFT", 1, -1); cat.icon:SetPoint("BOTTOMRIGHT", cat.tile, "BOTTOMRIGHT", -1, 1)
  cat.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  cat.glyph = cat.tile:CreateTexture(nil, "ARTWORK"); cat.glyph:SetPoint("CENTER", cat.tile, "CENTER", 0, 0)
  cat.sev = text(h, "mono", 10, "ink3"); cat.sev:SetPoint("LEFT", c.title, "RIGHT", 12, 0)
  cat.toggle = SC.Acquire("toggle", h)   -- reused for the card's life; bound per render
  cat.toggle.frame:SetPoint("RIGHT", h, "RIGHT", -16, 0)
  cat.pill = text(h, "mono", 10, "ink3"); cat.pill:SetPoint("RIGHT", h, "RIGHT", -16, 0)
  c.cat = cat
  return cat
end


--------------------------------------------------------------------------------
-- Presets strip (spec 2026-09-09 §3): tiles above the page's first tab; a
-- tile reads active when every entry already holds its value. No icon ->
-- a letter tile in one of four colours.
--------------------------------------------------------------------------------
local PRESET_H, PRESET_GAP = 56, 8
local PRESET_TINTS = { { 0.67, 0.83, 0.45 }, { 0.35, 0.65, 1.0 }, { 0.85, 0.72, 0.40 }, { 1.0, 0.60, 0.20 } }

local function presetTile(self, i)
  self.presetTiles = self.presetTiles or {}
  local t = self.presetTiles[i]
  if t then return t end
  t = CreateFrame("Button", nil, self.col.content)
  Skin.Surface(t, "surface2", "line")
  t:EnableMouseWheel(true)
  t:SetScript("OnMouseWheel", function(_, d) if SC.OnWheel then SC.OnWheel(d) end end)
  t.tile = CreateFrame("Frame", nil, t); t.tile:SetSize(32, 32); t.tile:SetPoint("LEFT", t, "LEFT", 10, 0)
  Skin.Surface(t.tile, "raised", "line")
  t.icon = t.tile:CreateTexture(nil, "ARTWORK"); t.icon:SetPoint("TOPLEFT", t.tile, "TOPLEFT", 1, -1); t.icon:SetPoint("BOTTOMRIGHT", t.tile, "BOTTOMRIGHT", -1, 1)
  t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  t.letterBg = t.tile:CreateTexture(nil, "ARTWORK"); t.letterBg:SetPoint("TOPLEFT", t.tile, "TOPLEFT", 1, -1); t.letterBg:SetPoint("BOTTOMRIGHT", t.tile, "BOTTOMRIGHT", -1, 1)
  t.letter = text(t.tile, "displayMedium", 18, "ground"); t.letter:SetPoint("CENTER", t.tile, "CENTER", 0, 0); t.letter:SetJustifyH("CENTER")
  t.tick = t:CreateTexture(nil, "ARTWORK"); t.tick:SetPoint("RIGHT", t, "RIGHT", -12, 0)
  Skin.Icon(t.tick, "check", "accent"); Skin.IconSize(t.tick, 16)
  t.name = text(t, "uiMedium", 13, "ink"); t.name:SetPoint("BOTTOMLEFT", t.tile, "RIGHT", 10, 1); t.name:SetPoint("RIGHT", t.tick, "LEFT", -8, 0); t.name:SetWordWrap(false)
  t.summary = text(t, "ui", 11, "ink3"); t.summary:SetPoint("TOPLEFT", t.tile, "RIGHT", 10, -3); t.summary:SetPoint("RIGHT", t.tick, "LEFT", -8, 0); t.summary:SetWordWrap(false)
  t:RegisterForClicks("AnyUp", "AnyDown")
  t:SetScript("OnClick", function(b)
    local now = GetTime()
    if b._acted and now - b._acted < 0.3 then b._acted = nil return end
    b._acted = now
    local p = b.preset
    Settings:Confirm(("Apply %s? %d settings change.\nYour current values are not saved."):format(p.name, #p.set), function()
      Nock.Presets.Apply(p, W._root, APP)
      W.NotifyChange(APP)
      Settings:Invalidate("preset")
    end)
  end)
  t:SetScript("OnEnter", function(b) Skin.Surface(b, "raised", b.active and "accent" or "line"); SC.ShowTooltip(b, b.preset.name, Nock.Presets.Describe(b.preset, W._root, APP)) end)
  t:SetScript("OnLeave", function(b) Skin.Surface(b, "surface2", b.active and "accent" or "line"); SC.HideTooltip() end)
  self.presetTiles[i] = t
  return t
end

function Settings:RenderPresets(page, tab, y, width, firstTab)
  self.presetTiles = self.presetTiles or {}
  for _, t in ipairs(self.presetTiles) do t:Hide() end
  if self.presetHead then self.presetHead:Hide() end
  local P = Nock.Presets
  local list = P and P.ForPage(table.concat(page.path, ".")) or nil
  if not list or #list == 0 or tab ~= firstTab then return y end
  if not self.presetHead then
    local h = CreateFrame("Frame", nil, self.col.content)
    h:SetHeight(20)
    h.label = text(h, "mono", 10, "ink3"); h.label:SetPoint("LEFT", h, "LEFT", 2, 0); h.label:SetText("PRESETS")
    h.rule = Skin.Rule(h, "lineSoft"); h.rule:SetPoint("LEFT", h.label, "RIGHT", 10, 0); h.rule:SetPoint("RIGHT", h, "RIGHT", 0, 0); h.rule:SetHeight(1)
    self.presetHead = h
  end
  local h = self.presetHead
  h:ClearAllPoints(); h:SetPoint("TOPLEFT", self.col.content, "TOPLEFT", Settings.CARD_PAD, -y); h:SetWidth(width); h:Show()
  y = y + 24
  local cols = math.min(#list, 3)
  local w = (width - PRESET_GAP * (cols - 1)) / cols
  for i, preset in ipairs(list) do
    local t = presetTile(self, i)
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    t.preset = preset
    t.name:SetText(preset.name); t.summary:SetText(preset.summary)
    local tex = preset.icon and preset.icon()
    if tex then
      t.icon:SetTexture(tex); t.icon:Show(); t.letterBg:Hide(); t.letter:Hide()
    else
      local tint = PRESET_TINTS[(i - 1) % #PRESET_TINTS + 1]
      t.icon:Hide(); t.letterBg:SetColorTexture(tint[1], tint[2], tint[3], 1); t.letterBg:Show()
      t.letter:SetText((preset.name:sub(1, 1)):upper()); t.letter:Show()
    end
    t.active = P.Matches(preset, W._root, APP)
    t.tick:SetShown(t.active)
    Skin.Surface(t, "surface2", t.active and "accent" or "line")
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", self.col.content, "TOPLEFT", Settings.CARD_PAD + col * (w + PRESET_GAP), -(y + row * (PRESET_H + PRESET_GAP)))
    t:SetSize(w, PRESET_H)
    t:Show()
  end
  return y + math.ceil(#list / cols) * (PRESET_H + PRESET_GAP) + 8
end

--------------------------------------------------------------------------------
-- Search (plan Task 15). The box's text is the query; two characters or more
-- replace the page with the hits, grouped per source card, each card's crumb
-- a link back to its page. Search is mode-blind: an Advanced hit in Simple
-- mode wears an ADV chip and opening it overrides the mode for this visit.
--------------------------------------------------------------------------------
function Settings:OnQuery(textIn)
  local q = (textIn or ""):match("^%s*(.-)%s*$")
  if q == (self.state.q or "") then return end
  self.state.q = q
  self:Invalidate("query")
end

function Settings:RenderSearch(root, nav)
  if not self.index or self.indexRoot ~= root then self.index = W.Index(nav, APP); self.indexRoot = root end
  local q = self.state.q
  local res = W.Search(self.index, q)
  self:RenderNav(nav, res.counts, false)
  self.eyebrow:SetText("SEARCH" .. (self:IsAdvanced() and "  ·  ADVANCED" or ""))
  if res.total == 0 then self.title:SetText(('No results for "%s"'):format(q))
  else self.title:SetText(('"%s"  ·  %d setting%s'):format(q, res.total, res.total == 1 and "" or "s")) end
  self:RenderTabs({}, nil)
  local cards, byKey = {}, {}
  for _, h in ipairs(res.hits) do
    local k = h.pageKey .. "/" .. h.tabKey .. "/" .. h.cardKey
    local c = byKey[k]
    if not c then
      c = { key = k, name = h.cardName, icon = h.cardIcon, crumb = h.crumb, rows = {}, lines = {}, pageKey = h.pageKey, tabKey = h.tabKey }
      c.open = function()
        if c.adv and not self:IsAdvanced() then self.modeOverride = true end
        self.searchBox:SetText("")
        self.searchBox:ClearFocus()
        self:SelectGroup(c.pageKey, c.tabKey)
      end
      byKey[k] = c; cards[#cards + 1] = c
    end
    c.rows[#c.rows + 1] = h.row
    if h.row.advanced then c.adv = true end
  end
  for _, c in ipairs(cards) do c.lines = W.Flow(c.rows) end
  self._searchFirst = cards[1] and cards[1].open or nil
  self:RenderCards(cards, { name = "Search", key = "__search", path = {} }, { key = "__search", virtual = true, name = "" })
  self:RenderFooter()
end

function Settings:RenderCards(cards, page, tab, dropped)
  self:ClearContent()
  if page.key == "helpers" and tab.key == "tabBuffs" then return self:RenderHelperTiles(cards, page, tab) end
  local colW = self.col.content:GetWidth() or 0
  if colW < 100 then colW = Settings.W - Settings.SIDE_W end
  local width = colW - Settings.CARD_PAD * 2 - 8
  local y, i, n, on = Settings.CARD_PAD - 4, 0, 0, 0
  y = self:RenderPresets(page, tab, y, width, self._firstTab)
  for _, card in ipairs(cards) do
    i = i + 1
    local c = self.cards[i]
    if not c then
      c = CreateFrame("Frame", nil, self.col.content)
      c.ctls = {}
      Skin.Surface(c, "surface2", "line")
      c:EnableMouseWheel(true)
      c:SetScript("OnMouseWheel", function(_, d) if SC.OnWheel then SC.OnWheel(d) end end)
      c.head = CreateFrame("Frame", nil, c)
      c.head:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -1); c.head:SetPoint("TOPRIGHT", c, "TOPRIGHT", -1, -1); c.head:SetHeight(40)
      Skin.Surface(c.head, "raised")
      -- search results: the head is a link back to the card's page
      c.head:SetScript("OnMouseUp", function(h) if h.open then h.open() end end)
      c.head:SetScript("OnEnter", function(h) if h.open then Skin.Text(c.crumb, "accent") end end)
      c.head:SetScript("OnLeave", function() Skin.Text(c.crumb, "ink3") end)
      local hr = Skin.Rule(c.head, "line"); hr:SetPoint("BOTTOMLEFT", c.head, "BOTTOMLEFT", 0, 0); hr:SetPoint("BOTTOMRIGHT", c.head, "BOTTOMRIGHT", 0, 0); hr:SetHeight(1)
      c.tick = c.head:CreateTexture(nil, "ARTWORK"); c.tick:SetSize(3, 16); c.tick:SetPoint("LEFT", c.head, "LEFT", 16, 0)
      c.title = text(c.head, "displayMedium", 17, "ink")
      c.crumb = text(c.head, "mono", Skin.SIZES.mono, "ink3"); c.crumb:SetPoint("LEFT", c.title, "RIGHT", 12, 0)
      self.cards[i] = c
    end
    c.ctls = {}
    c.title:SetText(card.name:upper())
    c.title:ClearAllPoints()
    local cat = card.catalog
    local headH = cat and 48 or 40
    c.head:SetHeight(headH)
    if cat then
      local ch = catalogHeader(c)
      c.tick:SetHeight(20)
      Skin.Paint(c.tick, SEV[cat.severity] or "accent", 1)
      c.title:SetPoint("LEFT", ch.tile, "RIGHT", 12, 0)
      c.crumb:Hide()
      local img = W.Image(cat.info)
      ch.glyph:Hide(); ch.icon:Show(); ch.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      if img then ch.icon:SetTexture(img) else ch.icon:SetTexture(nil) end
      ch.tile:Show()
      if cat.kind == "setup" then
        -- Setup Check: the info name carries the Pass/Fail colour code; show it as a pill instead of a toggle.
        local okn, s = W.Member(cat.info.node, "name", cat.info.info)
        local passed = okn and type(s) == "string" and s:find("Pass", 1, true) ~= nil
        ch.pill:SetText(passed and "PASS" or "FAIL"); Skin.Text(ch.pill, passed and "accent" or "bad"); ch.pill:Show()
        ch.toggle.frame:Hide(); ch.sev:SetText(""); on = on + (passed and 1 or 0)
      else
        ch.pill:Hide()
        ch.toggle.frame:Show()
        ch.toggle.headerOnly = true
        ch.toggle:Bind(cat.enabled, self)
        local okv, v = W.Get(cat.enabled)
        local enabled = okv and v and true or false
        if enabled then on = on + 1 end
        ch.sev:SetText((cat.severity or ""):upper()); Skin.Text(ch.sev, enabled and (SEV[cat.severity] or "ink3") or "ink3"); ch.sev:Show()
      end
      -- the one-line description with its glyph, from the info row (Task 8's description kind)
      local d = SC.Acquire("description", c); c.ctls[#c.ctls + 1] = d
      d.frame:SetPoint("TOPLEFT", c.head, "BOTTOMLEFT", 0, 0); d.frame:SetPoint("TOPRIGHT", c.head, "BOTTOMRIGHT", 0, 0)
      d.noImage = true
      d:Bind(cat.info, self)
      local h = headH + d.height
      local okv, v = W.Get(cat.enabled)
      if cat.kind == "setup" or (okv and v) then h = h + self:LayoutLines(c, card.lines, h, width) end
      c:SetHeight(h + 2)
    else
      -- every plain card wears an icon: the layout's, or the default glyph
      local ch = catalogHeader(c)
      if c.cat then c.cat.sev:Hide(); c.cat.pill:Hide(); c.cat.toggle.frame:Hide() end
      c.tick:SetHeight(16); Skin.Paint(c.tick, "accent", 1)
      local kind, v = Settings.ResolveIcon and Settings.ResolveIcon(card.icon, nil)
      if kind == "tex" and v then
        ch.glyph:Hide(); ch.icon:Show(); ch.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93); ch.icon:SetTexture(v)
      else
        local g = (kind == "glyph" and Skin.HasIcon(v)) and v or "sliders"
        ch.icon:Hide(); Skin.Icon(ch.glyph, g, "ink2"); Skin.IconSize(ch.glyph, 16); ch.glyph:Show()
      end
      ch.tile:Show()
      c.title:SetPoint("LEFT", ch.tile, "RIGHT", 12, 0)
      if card.open then
        c.crumb:SetText(card.crumb .. (card.adv and not self:IsAdvanced() and "  ·  ADV" or "") .. "  ·  OPEN ›")
        c.head.open = card.open; c.head:EnableMouse(true)
      else
        c.crumb:SetText(page.name .. (tab.virtual and "" or (" › " .. tab.name)))
        c.head.open = nil; c.head:EnableMouse(false)
      end
      Skin.Text(c.crumb, "ink3"); c.crumb:Show()
      if card.actionRows and self.DrawActions then self:DrawActions(c, card.actionRows) end
      local bodyH = self.LayoutCard and self:LayoutCard(c, card, headH, width) or self:LayoutLines(c, card.lines, headH, width)
      c:SetHeight(headH + bodyH + 2)
    end
    for _, ln in ipairs(card.lines) do n = n + #ln.rows end
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", self.col.content, "TOPLEFT", Settings.CARD_PAD, -y)
    c:SetWidth(width)
    c:Show()
    y = y + c:GetHeight() + 16
  end
  if tab.key:find("^cat_") then self.tabNote:SetText(("%d warnings · %d on"):format(#cards, on))
  elseif (dropped or 0) > 0 then self.tabNote:SetText(("%d of %d settings"):format(n, n + dropped))
  else self.tabNote:SetText(("%d setting%s"):format(n, n == 1 and "" or "s")) end
  self.col:SetContentHeight(y + Settings.CARD_PAD)
  self.col:ScrollTo(self.state.scroll[page.key .. "/" .. tab.key] or 0)
end

--------------------------------------------------------------------------------
-- Helpers › Buffs: one tile per consumable helper, grouped by kind. The line
-- under the name is the click-to-apply order (Core/ConsumeData.lua `prefer`,
-- best first); the glyph's tooltip holds the full breakdown. No live status:
-- a settings page is not the strip.
--------------------------------------------------------------------------------
local function itemName(id)
  local n
  if C_Item and C_Item.GetItemNameByID then n = C_Item.GetItemNameByID(id) end
  if not n and GetItemInfo then n = GetItemInfo(id) end
  if not n and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
  return n
end

local function shortName(n)
  -- "Elixir of Major Agility" -> "Major Agility", "Flask of Relentless Assault" -> "Relentless Assault"
  return (n:gsub("^Elixir of ", ""):gsub("^Flask of ", ""):gsub("^Scroll of ", ""))
end

local function helperLists(entry)
  local data = Nock.ConsumeData and entry and entry.data and Nock.ConsumeData[entry.data]
  local prefer, others = {}, {}
  if not data then return prefer, others end
  local seen = {}
  for _, id in ipairs(data.prefer or {}) do
    local n = itemName(id)
    prefer[#prefer + 1] = n and shortName(n) or ("item " .. id)
    seen[id] = true
  end
  local ids = {}
  for id in pairs(data.items or {}) do if not seen[id] then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local n = itemName(id)
    others[#others + 1] = n and shortName(n) or ("item " .. id)
  end
  return prefer, others
end

local TILE_H, TILE_GAP = 56, 8

local function tileFrame(self, i)
  local tl = self.tiles[i]
  if tl then return tl end
  tl = CreateFrame("Frame", nil, self.col.content)
  Skin.Surface(tl, "surface2", "line")
  tl:EnableMouseWheel(true)
  tl:SetScript("OnMouseWheel", function(_, d) if SC.OnWheel then SC.OnWheel(d) end end)
  tl.tile = CreateFrame("Frame", nil, tl); tl.tile:SetSize(32, 32); tl.tile:SetPoint("LEFT", tl, "LEFT", 10, 0)
  Skin.Surface(tl.tile, "raised", "line")
  tl.icon = tl.tile:CreateTexture(nil, "ARTWORK"); tl.icon:SetPoint("TOPLEFT", tl.tile, "TOPLEFT", 1, -1); tl.icon:SetPoint("BOTTOMRIGHT", tl.tile, "BOTTOMRIGHT", -1, 1)
  tl.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  -- the two lines straddle the icon's centre line, so the block reads centred
  tl.name = text(tl, "uiMedium", 13, "ink"); tl.name:SetPoint("BOTTOMLEFT", tl.tile, "RIGHT", 10, 1); tl.name:SetWordWrap(false)
  tl.prio = text(tl, "mono", 10, "ink3"); tl.prio:SetPoint("TOPLEFT", tl.tile, "RIGHT", 10, -3); tl.prio:SetWordWrap(false)
  tl.glyph = CreateFrame("Button", nil, tl); tl.glyph:SetSize(22, 22)
  tl.glyph.ico = tl.glyph:CreateTexture(nil, "ARTWORK"); tl.glyph.ico:SetPoint("CENTER")
  Skin.Icon(tl.glyph.ico, "info", "ink3"); Skin.IconSize(tl.glyph.ico, 16)
  tl.glyph:SetScript("OnEnter", function(g) Skin.Icon(g.ico, "info", "accent"); SC.ShowTooltip(g, g.tipTitle, g.tipBody) end)
  tl.glyph:SetScript("OnLeave", function(g) Skin.Icon(g.ico, "info", "ink3"); SC.HideTooltip() end)
  tl.toggle = SC.Acquire("toggle", tl)
  tl.toggle.frame:SetPoint("RIGHT", tl, "RIGHT", -12, 0)
  tl.glyph:SetPoint("RIGHT", tl.toggle.frame, "LEFT", -8, 0)
  tl.name:SetPoint("RIGHT", tl.glyph, "LEFT", -8, 0)
  tl.prio:SetPoint("RIGHT", tl.glyph, "LEFT", -8, 0)
  self.tiles[i] = tl
  return tl
end

local function tileHead(self, i)
  local h = self.tileHeads[i]
  if h then return h end
  h = CreateFrame("Frame", nil, self.col.content)
  h:SetHeight(20)
  h.label = text(h, "mono", 10, "ink3"); h.label:SetPoint("LEFT", h, "LEFT", 2, 0)
  h.rule = Skin.Rule(h, "lineSoft"); h.rule:SetPoint("LEFT", h.label, "RIGHT", 10, 0); h.rule:SetPoint("RIGHT", h, "RIGHT", 0, 0); h.rule:SetHeight(1)
  self.tileHeads[i] = h
  return h
end

function Settings:RenderHelperTiles(cards, page, tab)
  self.tiles, self.tileHeads = self.tiles or {}, self.tileHeads or {}
  for _, tl in ipairs(self.tiles) do tl:Hide() end
  for _, h in ipairs(self.tileHeads) do h:Hide() end
  local mod = Nock:GetModule("Helpers", true)
  local cats = mod and mod.Categories or {}
  local byCat = {}
  local total, on = 0, 0
  for _, card in ipairs(cards) do
    if card.catalog and card.catalog.entry then
      local k = card.catalog.entry.category or "other"
      byCat[k] = byCat[k] or {}
      byCat[k][#byCat[k] + 1] = card
      total = total + 1
      local okv, v = W.Get(card.catalog.enabled)
      if okv and v then on = on + 1 end
    end
  end
  local colW = self.col.content:GetWidth() or 0
  if colW < 100 then colW = Settings.W - Settings.SIDE_W end
  local inner = colW - Settings.CARD_PAD * 2 - 8
  local cols = inner >= 600 and 3 or 2
  local cellW = math.floor((inner - TILE_GAP * (cols - 1)) / cols)
  local y, ti, hi = Settings.CARD_PAD - 4, 0, 0
  y = self:RenderPresets(page, tab, y, inner, self._firstTab)
  local order = {}
  for _, c in ipairs(cats) do order[#order + 1] = c end
  if byCat.other then order[#order + 1] = { key = "other", name = "Other" } end
  for _, c in ipairs(order) do
    local list = byCat[c.key]
    if list and #list > 0 then
      hi = hi + 1
      local h = tileHead(self, hi)
      h.label:SetText(c.name:upper())
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", self.col.content, "TOPLEFT", Settings.CARD_PAD, -y)
      h:SetPoint("TOPRIGHT", self.col.content, "TOPRIGHT", -Settings.CARD_PAD - 8, -y)
      h:Show()
      y = y + 26
      for i, card in ipairs(list) do
        local cat = card.catalog
        ti = ti + 1
        local tl = tileFrame(self, ti)
        local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
        tl:ClearAllPoints()
        tl:SetPoint("TOPLEFT", self.col.content, "TOPLEFT", Settings.CARD_PAD + col * (cellW + TILE_GAP), -(y + line * (TILE_H + TILE_GAP)))
        tl:SetSize(cellW, TILE_H)
        local img = W.Image(cat.info)
        if img then tl.icon:SetTexture(img); tl.icon:Show() else tl.icon:Hide() end
        tl.name:SetText(cat.entry.name or card.name)
        local prefer, others = helperLists(cat.entry)
        local line2 = table.concat(prefer, " › ")
        if cat.entry.tileNote then
          line2 = (line2 ~= "" and (line2 .. "  ·  ") or "") .. "|cffd9b866" .. cat.entry.tileNote .. "|r"
        end
        tl.prio:SetText(line2)
        local body = (cat.entry.description or "")
        if #prefer > 0 then
          body = body .. "\n\nCLICK ORDER, BEST FIRST\n"
          for n, nm in ipairs(prefer) do body = body .. ("%d. %s\n"):format(n, nm) end
        end
        if #others > 0 then body = body .. "\nALSO COUNTS\n" .. table.concat(others, ", ") end
        if cat.entry.logic then body = body .. "\n\n" .. cat.entry.logic end
        tl.glyph.tipTitle, tl.glyph.tipBody = cat.entry.name, body
        tl.toggle.headerOnly = true
        tl.toggle:Bind(cat.enabled, self)
        local okv, v = W.Get(cat.enabled)
        tl:SetAlpha((okv and v) and 1 or 0.6)
        tl:Show()
      end
      y = y + math.ceil(#list / cols) * (TILE_H + TILE_GAP) + 10
    end
  end
  -- count + All on / All off in the tab strip's right slot
  self.tabNote:SetText(("%d helpers · %d on"):format(total, on))
  if not self.tileBtns then
    local allOn = Skin.Button(self.tabs, "All on", "ghost", nil, 24)
    local allOff = Skin.Button(self.tabs, "All off", "ghost", nil, 24)
    allOff:SetPoint("RIGHT", self.tabNote, "LEFT", -12, 0)
    allOn:SetPoint("RIGHT", allOff, "LEFT", -6, 0)
    local function setAll(v)
      for _, card in ipairs(self._tileCards or {}) do if card.catalog then W.Set(card.catalog.enabled, v) end end
      self:Invalidate("all")
    end
    allOn:SetScript("OnClick", function() setAll(true) end)
    allOff:SetScript("OnClick", function() setAll(false) end)
    self.tileBtns = { allOn, allOff }
  end
  self._tileCards = cards
  for _, b in ipairs(self.tileBtns) do b:Show() end
  self.col:SetContentHeight(y + Settings.CARD_PAD)
  self.col:ScrollTo(self.state.scroll[page.key .. "/" .. tab.key] or 0)
end

-- Lines → rows. A clustered line lays its rows side by side by their width
-- units; a single row spans the card. Returns the height used.
function Settings:LayoutLines(c, lines, top, width)
  local y = top
  local inner = width - 32

  -- One clustered line drawn in the old dialog's flow, stretched to the card.
  local function flowLine(rows)
    local sum = 0
    for _, row in ipairs(rows) do sum = sum + (row.unit or W.WIDTH_UNIT) end
    local scale = math.min(1.5, math.max(1, (inner - 8 * (#rows - 1)) / math.max(1, sum)))
    local x, lh, labelled, placed = 16, 0, false, {}
    for _, row in ipairs(rows) do
      local u = math.floor((row.unit or W.WIDTH_UNIT) * scale)
      local ctl = SC.Acquire(row.type, c); c.ctls[#c.ctls + 1] = ctl
      ctl.frame:SetWidth(u)
      ctl:Bind(row, self)
      if ctl.Compact then ctl:Compact() end
      placed[#placed + 1] = { ctl = ctl, x = x, bare = row.type == "toggle" or row.type == "execute" }
      if ctl.frame.ctl and row.type ~= "toggle" and row.type ~= "execute" then labelled = true end
      x = x + u + 8
      lh = math.max(lh, ctl.height or Settings.ROW_H)
    end
    -- Placed once, after the line's height is known. A labelled compact
    -- control (slider, select, input) keeps its label above and its widget in
    -- the bottom band; bare controls (buttons, pills) centre on that band, or
    -- on the line itself when nothing on it carries a label.
    local band = labelled and (y + lh - 6 - 14) or (y + lh / 2)
    for _, p in ipairs(placed) do
      if p.bare or not labelled then
        p.ctl.frame:SetPoint("LEFT", c, "TOPLEFT", p.x, -band)
      else
        p.ctl.frame:SetPoint("TOPLEFT", c, "TOPLEFT", p.x, -y)
      end
    end
    y = y + lh
    if self.DrawRule then self:DrawRule(c, y - 1, width) end
  end

  -- Toggle tiles collected from clustered lines are drawn as one even grid
  -- (3 columns on a wide card, 2 on a narrow one), in source order.
  local tiles = {}
  local function flushTiles()
    if #tiles == 0 then return end
    local cols = inner >= 600 and 3 or 2
    local gap, rowH = 8, 40
    local cellW = math.floor((inner - gap * (cols - 1)) / cols)
    for i, row in ipairs(tiles) do
      local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
      local ctl = SC.Acquire("toggle", c); c.ctls[#c.ctls + 1] = ctl
      ctl.frame:SetPoint("TOPLEFT", c, "TOPLEFT", 16 + col * (cellW + gap), -(y + line * (rowH + 4)))
      ctl.frame:SetWidth(cellW)
      ctl:Bind(row, self)
      ctl:Compact()
    end
    y = y + math.ceil(#tiles / cols) * (rowH + 4) + 6
    tiles = {}
  end

  -- runs of four or more colour rows draw as a swatch grid
  local run = {}
  local function flushRun()
    if #run >= 4 and self.DrawSwatches then
      flushTiles()
      y = y + self:DrawSwatches(c, run, y, width)
    else
      for _, r in ipairs(run) do
        flushTiles()
        local ctl = SC.Acquire("color", c); c.ctls[#c.ctls + 1] = ctl
        ctl.frame:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -y); ctl.frame:SetPoint("TOPRIGHT", c, "TOPRIGHT", -1, -y)
        ctl.frame:SetWidth(width - 2)
        ctl:Bind(r, self)
        y = y + (ctl.height or Settings.ROW_H)
      end
    end
    run = {}
  end
  for _, ln in ipairs(lines) do
    if not ln.cluster and ln.rows[1].type == "color" then
      run[#run + 1] = ln.rows[1]
    elseif ln.cluster then
      flushRun()
      local hasButton, others = false, {}
      for _, row in ipairs(ln.rows) do
        if row.type == "execute" then hasButton = true end
        if row.type ~= "toggle" then others[#others + 1] = row end
      end
      if hasButton then
        -- a grid entry (enable toggle + Up / Down / X): stays one line, as is
        flushTiles()
        flowLine(ln.rows)
      else
        -- controls on their own line first, the line's toggles join the tile grid
        if #others > 0 then flushTiles(); flowLine(others) end
        for _, row in ipairs(ln.rows) do if row.type == "toggle" then tiles[#tiles + 1] = row end end
      end
    else
      flushRun()
      flushTiles()
      local row = ln.rows[1]
      local kind = row.type
      if row.chips then kind = "chips" end
      if row.segmented and kind == "select" then kind = "segselect" end
      if kind == "description" and (row.node.dialogControl == "NockShotBarsLegend" or row.node.dialogControl == "NockReactBarLegend") then kind = "legend" end
      local ctl = SC.Acquire(kind, c); c.ctls[#c.ctls + 1] = ctl
      ctl.frame:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -y)
      ctl.frame:SetPoint("TOPRIGHT", c, "TOPRIGHT", -1, -y)
      ctl.frame:SetWidth(width - 2)
      ctl:Bind(row, self)
      y = y + (ctl.height or Settings.ROW_H)
    end
  end
  flushRun()
  flushTiles()
  return y - top
end

function Settings:RenderFooter()
  local locked = Nock.IsLocked()
  Skin.Icon(self.lockIcon, locked and "lock" or "lockopen", locked and "ink2" or "accent"); Skin.IconSize(self.lockIcon, 14)
  self.lockText:SetText(locked and "Frames locked" or "Frames unlocked")
  Skin.SetButtonText(self.lockBtn, locked and "Unlock" or "Lock")
  local look = ({ classic = "Classic", react = "React", fluffy = "FluffyHUD" })[Nock.db.profile.hudMode or "classic"]
  local st = Nock.state and Nock.state.ranged
  local ews = st and st.swingDuration and ("%.2f"):format(st.swingDuration) or "-"
  self.status:SetText(("HUD look  %s   ·   eWS  %s"):format(look, ews))
end

