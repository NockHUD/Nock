-- UI/Frame_Workbench.lua
-- The practice WORKBENCH: one skinned window -- a title bar with the mark, a
-- rail of pages down the left, a content area -- that hosts the practice
-- panel (the header strip, the stage, the proc palette) and, page by page,
-- everything else practice owns. Shell step 2 of the plan decided with the
-- user off the "Practice Shells" / "Workbench States" artifacts (2026-08-26).
--
-- Step 2 hosts today's practice panel as the Stage page and lets the other
-- rail items open the windows that still float (lesson, ladder, review) or
-- the practice settings; step 3 adds Focus (the stage alone on the HUD
-- during a fight); step 4 moves the floating windows in as pages, each a
-- frame in the room under the panel (RegisterPage / PageFrame), sized by
-- the page's own PageHeight.
--
-- Loaded BEFORE UI/Frame_Practice.lua: the panel asks for ContentFrame() in
-- its own OnInitialize and parents itself there when the workbench exists.
local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Workbench = Nock:NewModule("PracticeWorkbench", "AceEvent-3.0")
local Skin = Nock.Skin

local TITLE_H, RAIL_W, ITEM_H = 36, 168, 34
local PAGE_W = 960            -- the content column: the window is sized FROM it (PageWidth)
local PAGE_MIN = 120          -- room under the hosted panel for the page's own content (step 4)
local FOOT_H = 48
local EDGE = 1                -- the hairline the frame draws around itself
local FIT_MARGIN = 24         -- screen units kept free around a fitted window
local FIT_MIN = 0.5           -- never shrunk below half: past that the screen is hopeless anyway

-- The rail, top to bottom. `open` is what the item does until its page moves
-- in (step 4): a message the floating window listens to, or nil for the
-- page that is already here.
local RAIL = {
  { id = "stage",     label = "Stage",     icon = "stage" },
  { id = "lesson",    label = "Lesson",    icon = "lesson",    page = true },
  { id = "ladder",    label = "Ladder",    icon = "ladder",    page = true },
  -- Hidden while the review is off (`practiceReviewEnabled`): the user wants
  -- it out of sight until it is perfected (2026-08-26). The rail re-stacks.
  { id = "review",    label = "Review",    icon = "review",    page = true,
    when = function() return Nock.db and Nock.db.profile and Nock.db.profile.practiceReviewEnabled == true end },
  { id = "scenarios", label = "Scenarios", icon = "scenarios", page = true },
  { id = "keys",      label = "Keys",      icon = "key",       page = true },
  { id = "style",     label = "Style",     icon = "style",     page = true },
  -- The way out of practice mode: the title bar's X only closes the window.
  -- Seated at the rail's foot, apart from the pages.
  -- No "Leave practice" item (user, 2026-08-27): the title bar's X leaves
  -- practice, and that is enough. `leave = true` / `bottom = true` on a row
  -- still work should one come back.
}

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function practice() return Nock:GetModule("Practice", true) end

local function openOptions()
  local dialog = LibStub("AceConfigDialog-3.0", true)
  if dialog then
    dialog:Open("Nock")
    if dialog.SelectGroup then dialog:SelectGroup("Nock", "utilities", "practice") end
  elseif Nock.OpenConfig then
    Nock:OpenConfig()
  end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------
local function makeText(parent, role, size, color, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  Skin.Font(fs, role, size)
  Skin.Text(fs, color or "ink")
  return fs
end

-- The default seat: centred in the TOP HALF of the screen -- horizontally on
-- the screen, vertically between its middle and its top (user, 2026-08-26).
local function seatDefault(f)
  local h = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
  f:SetPoint("CENTER", UIParent, "CENTER", 0, h / 4)
end

function Workbench:OnInitialize()
  local f = CreateFrame("Frame", "NockWorkbench", UIParent)
  self.frame = f
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  Skin.Surface(f, "surface", "line")
  -- The practice scale, like every practice window (a pixel-perfect frame
  -- scale was tried: on top of a practice scale tuned under the UI scale it
  -- blew the window past the screen). The icons alone are made pixel-exact,
  -- by size and by a sub-pixel nudge (Skin.IconSize).
  Nock.UI.RegisterPracticeScale(f)
  f:SetSize(RAIL_W + PAGE_W, TITLE_H + 300)
  local pos = profile("practiceWorkbenchPos", nil)
  if pos then f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
  else seatDefault(f) end
  f:Hide()

  -- Title bar: the mark, NOCK / PRACTICE, the haste chip, close. The bar is
  -- the drag handle (no fight running).
  local tb = CreateFrame("Frame", nil, f)
  tb:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE, -EDGE)
  tb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -EDGE, -EDGE)
  tb:SetHeight(TITLE_H)
  Skin.Surface(tb, "ground")
  local tbLine = Skin.Rule(tb, "line")
  tbLine:SetPoint("BOTTOMLEFT", tb, "BOTTOMLEFT", 0, 0)
  tbLine:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", 0, 0)
  tbLine:SetHeight(1)
  tb:EnableMouse(true)
  tb:RegisterForDrag("LeftButton")
  tb:SetScript("OnDragStart", function()
    if Nock.state.sim.fightOn then return end
    f:StartMoving()
  end)
  tb:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    Nock.db.profile.practiceWorkbenchPos = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  self.titlebar = tb

  local mark = tb:CreateTexture(nil, "ARTWORK")
  mark:SetSize(22, 22)
  mark:SetPoint("LEFT", tb, "LEFT", 7, 0)
  Skin.Logo(mark, "mark64")

  -- The title's box is ascent + descent and capitals fill only the top of
  -- it, so centred on the bar the words sit high beside the mark: lowered
  -- 2 px to the mark's centre (the mark itself is centred by its artwork).
  local title = makeText(tb, "display", Skin.SIZES.title, "ink")
  title:SetPoint("LEFT", mark, "RIGHT", 10, -3)
  title:SetText("NOCK")
  local sub = makeText(tb, "display", Skin.SIZES.title - 5, "ink3")   -- the bold face, 14 pt
  sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 0)   -- baselines together, a size down
  sub:SetText("/ PRACTICE")

  local close = CreateFrame("Button", nil, tb)
  close:SetSize(32, 32)
  close:SetPoint("RIGHT", tb, "RIGHT", -4, 0)
  local closeIco = close:CreateTexture(nil, "ARTWORK")
  closeIco:SetPoint("CENTER")
  Skin.Icon(closeIco, "close", "ink3")
  Skin.IconSize(closeIco)
  self.closeIco = closeIco
  close:SetScript("OnEnter", function() Skin.Icon(closeIco, "close", "ink") end)
  close:SetScript("OnLeave", function() Skin.Icon(closeIco, "close", "ink3") end)
  close:SetScript("OnClick", function() Workbench:Close() end)
  self.closeBtn = close

  -- The haste chip: your own eWS, as the scenario will pin it.
  local chip = CreateFrame("Frame", nil, tb)
  chip:SetSize(84, 18)
  chip:SetPoint("RIGHT", close, "LEFT", -10, 0)
  Skin.Surface(chip, "ground", "line")
  local chipText = makeText(chip, "mono", Skin.SIZES.chip, "ink2")
  chipText:SetPoint("CENTER")
  chip.text = chipText
  self.hasteChip = chip

  -- The rail.
  local rail = CreateFrame("Frame", nil, f)
  rail:SetPoint("TOPLEFT", tb, "BOTTOMLEFT", 0, 0)
  rail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", EDGE, EDGE)
  rail:SetWidth(RAIL_W)
  Skin.Surface(rail, "ground")
  local railLine = Skin.Rule(rail, "line")
  railLine:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, 0)
  railLine:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, 0)
  railLine:SetWidth(1)
  self.rail = rail
  self.items = {}
  for i = 1, #RAIL do
    local spec = RAIL[i]
    local b = CreateFrame("Button", nil, rail)
    b:SetSize(RAIL_W - 1, ITEM_H)
    if spec.bottom then b:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 0, FOOT_H + 6) end
    local fill = b:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(b)
    Skin.Paint(fill, "surface2", 1)
    fill:Hide()
    local bar = b:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    bar:SetWidth(2)
    Skin.Paint(bar, "accent", 1)
    bar:Hide()
    local ico = b:CreateTexture(nil, "ARTWORK")
    ico:SetPoint("LEFT", b, "LEFT", 12, 0)
    Skin.Icon(ico, spec.icon, "ink2", 0.85)
    Skin.IconSize(ico)              -- native: the pixel art stays crisp
    local label = makeText(b, "uiMedium", 13, "ink2")
    label:SetPoint("LEFT", ico, "RIGHT", 10, 0)
    label:SetText(spec.label)
    b.spec, b.fill, b.bar, b.ico, b.label = spec, fill, bar, ico, label
    b:SetScript("OnClick", function() Workbench:Select(spec.id) end)
    b:SetScript("OnEnter", function() if not b.on then b.fill:Show() end end)
    b:SetScript("OnLeave", function() if not b.on then b.fill:Hide() end end)
    self.items[spec.id] = b
  end
  self:LayoutRail()

  -- Rail foot: the mark, dim, beside the bow/haste line.
  local foot = CreateFrame("Frame", nil, rail)
  foot:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 0, 0)
  foot:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -1, 0)
  foot:SetHeight(FOOT_H)
  local footLine = Skin.Rule(foot, "line")
  footLine:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, 0)
  footLine:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, 0)
  footLine:SetHeight(1)
  local footMark = foot:CreateTexture(nil, "ARTWORK")
  footMark:SetSize(26, 26)
  footMark:SetPoint("LEFT", foot, "LEFT", 16, 0)
  Skin.Logo(footMark, "mark64", Skin.ALPHA.logoFoot)
  local footText = makeText(foot, "mono", 9, "ink3")
  footText:SetPoint("LEFT", footMark, "RIGHT", 8, 0)
  footText:SetJustifyH("LEFT")
  foot.text = footText
  self.foot = foot

  -- The content area: the practice panel parents itself here (Frame_Practice
  -- OnInitialize), pages come later.
  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
  content:SetPoint("TOPRIGHT", tb, "BOTTOMRIGHT", 0, 0)
  content:SetPoint("BOTTOM", f, "BOTTOM", 0, EDGE)
  self.content = content

  -- Under the panel: where the page's own content goes (step 4). A quiet
  -- placeholder for now, so the room reads as intended, not as a bug.
  local page = CreateFrame("Frame", nil, content)
  page:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
  page:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
  page:SetHeight(PAGE_MIN)
  local pageText = makeText(page, "ui", 12, "ink3")
  pageText:SetPoint("CENTER")
  pageText:SetText("")
  page.text = pageText
  self.page = page
  self.pages = {}

  -- Esc (UISpecialFrames) hides the frame behind our back: that is a close,
  -- else the next relayout brings the window straight back.
  tinsert(UISpecialFrames, "NockWorkbench")
  -- Only a hide of THIS frame (Esc), never a parent's (Alt-Z hides UIParent
  -- and OnHide fires for every child): IsShown stays true for those.
  f:SetScript("OnHide", function()
    local own = not Workbench._hiding
    Workbench._hiding = false
    if own and not f:IsShown() then Workbench:Close() end
  end)
  self:Select("stage", true)
end

-- /nock practice icons: the numbers behind one rail icon's size and place,
-- in a copybox (the icons came out soft twice in-game, 2026-08-26).
function Workbench:IconDiag()
  local f = self.frame
  local b = self.items and self.items.stage
  if not (f and b) then return "no workbench" end
  local ico = b.ico
  local ui = UIParent:GetEffectiveScale()
  local lines = {
    ("UIParent effective scale  %.4f"):format(ui),
    ("workbench scale           %.4f   effective %.4f"):format(f:GetScale(), f:GetEffectiveScale()),
    ("rail button effective     %.4f"):format(b:GetEffectiveScale()),
    ("practice scale option     %.4f"):format(Nock.UI.PracticeScale()),
    ("screen fit                %.4f  (tallest %s units; screen %s x %s)"):format(self._fit or 1, tostring(self._tallest), tostring(UIParent:GetWidth()), tostring(UIParent:GetHeight())),
    ("icon size (units)         %.3f x %.3f  -> %.2f px"):format(ico:GetWidth(), ico:GetHeight(), ico:GetWidth() * b:GetEffectiveScale()),
    ("IconSize used es          %s   chain scale %.4f   f:GetScale %.4f  rail:GetScale %.4f  b:GetScale %.4f"):format(tostring(ico._iconEs), Skin.ScaleOf(b), f:GetScale(), self.rail:GetScale(), b:GetScale()),
    ("768-base px per unit      %.4f  (physical h / 768 x effective)"):format((select(2, GetPhysicalScreenSize()) or 768) / 768 * b:GetEffectiveScale()),
    ("icon left/bottom (units)  %s / %s"):format(tostring(ico:GetLeft()), tostring(ico:GetBottom())),
    ("icon nudge (px)           %s / %s   pixels per unit %s"):format(tostring(ico._snapDx), tostring(ico._snapDy), tostring(ico._iconEs)),
    ("icon left/bottom (px)     %s / %s"):format(ico:GetLeft() and ("%.3f"):format(ico:GetLeft() * b:GetEffectiveScale()) or "-", ico:GetBottom() and ("%.3f"):format(ico:GetBottom() * b:GetEffectiveScale()) or "-"),
    ("icon point                %s %s %.3f %.3f (base %s %s)"):format(tostring((ico:GetPoint(1))), tostring((select(3, ico:GetPoint(1)))), select(4, ico:GetPoint(1)) or 0, select(5, ico:GetPoint(1)) or 0, tostring(ico._snapX0), tostring(ico._snapY0)),
    ("texture                   %s"):format(tostring(ico:GetTexture())),
    ("texcoord                  %s"):format(table.concat({ ico:GetTexCoord() }, " ")),
    ("snap methods              %s / %s"):format(tostring(ico.SetSnapToPixelGrid ~= nil), tostring(ico.SetTexelSnappingBias ~= nil)),
    ("screen                    %s x %s  (GetScreenWidth/Height)"):format(tostring(GetScreenWidth and GetScreenWidth()), tostring(GetScreenHeight and GetScreenHeight())),
    ("physical                  %s"):format(tostring(GetPhysicalScreenSize and select(1, GetPhysicalScreenSize()))),
  }
  return table.concat(lines, "\n")
end

-- The fit factor that keeps a window of w x h units at practice scale s
-- inside a screen of screenW x screenH units (2026-08-27): 1 when it fits,
-- else the shrink that makes it, floored at FIT_MIN. Pure; the Relayout
-- feeds it the TALLEST size seen this session so the scale does not breathe
-- between pages. At the 1.25 default the Lesson (~1060 units) and Style
-- (~1090) pages ran past a 1080p screen, and the whole window past a laptop
-- at UI scale 1 (1365 x 768).
function Workbench.FitScale(w, h, s, screenW, screenH)
  local fit = 1
  if type(w) == "number" and type(h) == "number" and s and s > 0 then
    if screenH and screenH > 0 and h > 0 then
      fit = math.min(fit, (screenH - FIT_MARGIN * 2) / (h * s))
    end
    if screenW and screenW > 0 and w > 0 then
      fit = math.min(fit, (screenW - FIT_MARGIN * 2) / (w * s))
    end
  end
  if fit < FIT_MIN then fit = FIT_MIN end
  if fit > 1 then fit = 1 end
  return fit
end

function Workbench:ContentFrame() return self.content end
-- The room under the panel, for the pages (step 4). A page module parents
-- its frame here and registers it with the module that sizes it:
-- `module:PageHeight()` is read on every relayout, `module:OnPageShow()`
-- when the rail selects it, `module:OnPageHide()` when it leaves it.
function Workbench:PageFrame() return self.page end
-- The width a page lays itself out to. NOT the page frame's GetWidth: an
-- anchored frame reports 0 before its layout pass -- and the screen-fit
-- rescale (SetPracticeScaleFit clears and re-seats the root's points) puts
-- every descendant back in that state for the rest of the frame. On a 1080p
-- screen, where the cap bites, the Keys page rebuilt inside that window and
-- both columns landed on x = 8 with the buttons hanging off the rows' left
-- edge (user report, 2026-08-27). The window is sized from PAGE_W, so PAGE_W
-- is the truth; the live width is used only when it is sane.
Workbench.PAGE_W = PAGE_W
function Workbench:PageWidth()
  local w = self.page and self.page.GetWidth and self.page:GetWidth()
  if w and w >= PAGE_W * 0.5 then return w end
  return PAGE_W
end
function Workbench:RegisterPage(id, frame, module)
  self.pages[id] = { frame = frame, module = module }
  frame:Hide()
end
function Workbench:GetFrame() return self.frame end
function Workbench:IsOpen() return self.frame and self.frame:IsShown() or false end

--------------------------------------------------------------------------------
-- Behaviour
--------------------------------------------------------------------------------
function Workbench:OnEnable()
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "Relayout")
  self:RegisterMessage("NOCK_PRACTICE_LAYOUT", "Relayout")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "Relayout")
  self:RegisterMessage("NOCK_PRACTICE_OPEN", "Open")
  self:RegisterMessage("NOCK_PRACTICE_RESET_POS", "ResetPos")
  self:RegisterMessage("NOCK_PRACTICE_FOCUS", "OnFocus")
  self:RegisterMessage("NOCK_PRACTICE_EXPERT", "OnExpert")
  self:Relayout()
end

-- FOCUS (shell step 3): the stage alone on the HUD. On, the window hides and
-- the conveyor undocks to its own spot (View:SetFocus; the dock SETTING is
-- untouched); off, the stage docks back and the window returns. Sent by
-- Practice:StartFight / StopFight, the toolbar's Focus button, the head's
-- WORKBENCH button, Esc on the stage and the keybind.
function Workbench:OnFocus(_, on)
  self:Focus(on)
end

function Workbench:IsFocus() return self._focus and true or false end

function Workbench:Focus(on, quiet)
  on = on and true or false
  if on and not Nock.state.sim.active then return end
  if on == (self._focus or false) then return end
  -- Never both: Focus is the stage alone, Expert the log alone.
  if on and self._expert then self:Expert(false, true) end
  self._focus = on
  local cv = Nock:GetModule("PracticeConveyorView", true)
  if cv and cv.SetFocus then cv:SetFocus(on) end
  -- The panel re-measures: docked, the stage is part of its height.
  Nock:SendMessage("NOCK_PRACTICE_DOCK_CHANGED")
  if on then
    if self.frame and self.frame:IsShown() then self._hiding = true; self.frame:Hide() end
  elseif not quiet then
    -- Back from Focus the window comes back, even if it was closed by hand
    -- before the fight: Stop's review is read here.
    self._closed = false
    self:Relayout()
  end
end

-- EXPERT (2026-08-27, user: "set a scenario, but get only 2 panels"). The
-- window and the stage go; the combat log (UI/Frame_PracticeCombatLog.lua)
-- and, on a weave paper, the weave log stay. A sibling of Focus, never both.
-- The fight, the grader, the ladder and the replay run as they always do:
-- Expert is a view, nothing is scored differently. Stop KEEPS Expert (the log
-- holds the fight for scrubbing); leaving is the log's WORKBENCH button, Esc
-- outside a fight, the keybind, or practice going off.
function Workbench:OnExpert(_, on)
  self:Expert(on)
end

function Workbench:IsExpert() return self._expert and true or false end

function Workbench:Expert(on, quiet)
  on = on and true or false
  if on and not Nock.state.sim.active then return end
  if on == (self._expert or false) then return end
  if on and self._focus then self:Focus(false, true) end
  self._expert = on
  local cl = Nock:GetModule("PracticeCombatLogView", true)
  if cl and cl.SetExpert then cl:SetExpert(on) end
  Nock:SendMessage("NOCK_PRACTICE_DOCK_CHANGED")
  if on then
    if self.frame and self.frame:IsShown() then self._hiding = true; self.frame:Hide() end
  elseif not quiet then
    self._closed = false
    self:Relayout()
  end
end

function Workbench:Select(id, quiet)
  local spec
  for i = 1, #RAIL do if RAIL[i].id == id then spec = RAIL[i] end end
  if not spec then return end
  if spec.when and not spec.when() then id = "stage"; spec = RAIL[1] end
  if spec.leave then
    if not quiet then local p = practice(); if p and p.Stop then p:Stop() end end
    return
  end
  -- Pages that are not here yet open their window (or the settings) and the
  -- rail stays on Stage: the highlight means "this is on the page", and the
  -- floating windows are not.
  if spec.open then
    if not quiet then Nock:SendMessage(spec.open) end
    return
  end
  if spec.options then
    if not quiet then openOptions() end
    return
  end
  -- Where a pick on the Scenarios page returns to: the page it was opened
  -- FROM (the Lesson's toolbar name goes back to the Lesson -- user,
  -- 2026-08-26), the Stage otherwise.
  if id == "scenarios" then
    if self._page ~= "scenarios" then self._returnTo = self._page or "stage" end
  else
    self._returnTo = nil
  end
  self._page = id
  -- The page's frame, and the placeholder for the pages not here yet.
  for pid, pg in pairs(self.pages) do
    if pid == id then
      if pg.module and pg.module.OnPageShow then pg.module:OnPageShow() end
      pg.frame:Show()
    else
      if pg.frame:IsShown() and pg.module and pg.module.OnPageHide then pg.module:OnPageHide() end
      pg.frame:Hide()
    end
  end
  -- The placeholder text: only for a rail page that has no frame yet. The
  -- Stage has none by design and shows nothing under the panel.
  if self.page and self.page.text then
    if self.pages[id] or id == "stage" then self.page.text:Hide() else self.page.text:Show() end
  end
  for pid, b in pairs(self.items) do
    local on = (pid == id)
    b.on = on
    if on then b.fill:Show(); b.bar:Show() else b.fill:Hide(); b.bar:Hide() end
    Skin.Icon(b.ico, b.spec.icon, on and "accent" or "ink2", on and 1 or 0.85)
    Skin.Text(b.label, on and "accent" or "ink2")
  end
  if not quiet then self:Relayout() end
end

-- The height of the room under the panel: the page's own, or the
-- placeholder's floor.
-- The page a scenario pick goes back to.
function Workbench:ReturnPage() return self._returnTo or "stage" end

function Workbench:PageHeight()
  -- The Stage has no page body (user, 2026-08-27: "empty content section ...
  -- hide it out so the height becomes small"): no room under the panel.
  if self._page == "stage" or not self._page then return 0 end
  local pg = self.pages[self._page]
  local h = pg and pg.module and pg.module.PageHeight and pg.module:PageHeight()
  if not h or h < PAGE_MIN then h = PAGE_MIN end
  return h
end

-- Closing the window IS leaving practice: the HUD goes back to the live game
-- (a replay would otherwise keep driving it from behind a closed window) and
-- the weave log goes with it (user, 2026-08-26). Same as the rail's item.
function Workbench:Close()
  self._closed = true
  if self.frame and self.frame:IsShown() then self._hiding = true; self.frame:Hide() end
  local p = practice()
  if p and p.Stop and p.IsActive and p:IsActive() then p:Stop() end
end

function Workbench:Open()
  self._closed = false
  self:Relayout()
end

function Workbench:ResetPos()
  local f = self.frame
  if not f then return end
  Nock.db.profile.practiceWorkbenchPos = nil
  f:ClearAllPoints()
  seatDefault(f)
end

-- The window follows practice mode: shown while it is on and not closed by
-- hand, sized to the panel it hosts plus the page room under it.
-- Stack the rail's top items, skipping the ones whose `when` says no.
function Workbench:LayoutRail()
  local rail, n = self.rail, 0
  if not rail then return end
  for i = 1, #RAIL do
    local spec = RAIL[i]
    local b = self.items[spec.id]
    if b and not spec.bottom then
      local shown = (spec.when == nil) or (spec.when() and true or false)
      if shown then
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -10 - n * ITEM_H)
        b:Show()
        n = n + 1
      else
        b:Hide()
      end
    end
  end
end

function Workbench:Relayout()
  local f = self.frame
  if not f then return end
  self:LayoutRail()
  -- The page the rail no longer offers falls back to the Stage.
  if self._page and self._page ~= "stage" then
    for i = 1, #RAIL do
      local spec = RAIL[i]
      if spec.id == self._page and spec.when and not spec.when() then self:Select("stage", true) end
    end
  end
  local st = Nock.state.sim
  -- A close lasts for the practice session it was made in. Closing the
  -- window leaves practice, and the flag used to outlive that: the next
  -- `/nock practice` started practice, this relayout saw `_closed` and kept
  -- the window hidden, and only the second press (active, not open) opened
  -- it (user, 2026-08-27: "needs sometimes to fire twice before open").
  if not st.active then self._closed = false end
  -- Start goes to the Stage (user, 2026-08-27: a fight started from the
  -- Lesson left the tall page open over the HUD): on the rising edge of a
  -- fight, any other page yields to the Stage. Not for the ghost's own fight
  -- -- the Lesson's and the Style page's previews run on the stage above the
  -- page, and leaving the page would end them.
  local fightOn = st.fightOn and true or false
  if fightOn and not self._fightWas and self._page ~= "stage" then
    local p = practice()
    if not (p and p._demo) then self:Select("stage", true) end
  end
  self._fightWas = fightOn
  -- Practice off ends Focus with it (the conveyor re-docks for the next time).
  if not st.active and self._focus then
    self._focus = false
    local cv = Nock:GetModule("PracticeConveyorView", true)
    if cv and cv.SetFocus then cv:SetFocus(false) end
  end
  -- ...and Expert (the combat log leaves UISpecialFrames and hides).
  if not st.active and self._expert then
    self._expert = false
    local cl = Nock:GetModule("PracticeCombatLogView", true)
    if cl and cl.SetExpert then cl:SetExpert(false) end
  end
  if not st.active or self._closed or self._focus or self._expert then
    if f:IsShown() then self._hiding = true; f:Hide() end
    return
  end
  local pv = Nock:GetModule("PracticeView", true)
  local panel = pv and pv.frame
  local panelH = panel and panel:GetHeight() or 0
  local pageH = self:PageHeight()
  self.page:SetHeight(pageH)
  local W, H = RAIL_W + PAGE_W + EDGE * 2, TITLE_H + panelH + pageH + EDGE * 2
  f:SetSize(W, H)
  -- Fit to the screen: the tallest size seen this session, so a page change
  -- only ever shrinks the window and never grows it back (no breathing); a
  -- slider change recomputes against the same height.
  if H > (self._tallest or 0) then self._tallest = H end
  local fit = Workbench.FitScale(W, self._tallest, Nock.UI.PracticeScale(),
    UIParent:GetWidth(), UIParent:GetHeight())
  if fit ~= self._fit then
    self._fit = fit
    if Nock.UI.SetPracticeScaleFit then Nock.UI.SetPracticeScaleFit(f, fit) end
  end
  if panel and panel:GetParent() == self.content then
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, 0)
  end
  local p = practice()
  local ews = p and p._liveEws
  self.hasteChip.text:SetText(ews and ("eWS %.3f"):format(ews) or "eWS  -")
  local ws = Nock.state.ranged and Nock.state.ranged.weaponSpeed
  self.foot.text:SetText(ews and ("%s\n%.3f s"):format(ws and ("bow %.1f"):format(ws) or "your bow", ews) or "no swing measured yet")
  if not f:IsShown() then f:Show() end
  -- The pixel icons, sized and nudged onto whole screen pixels for the scale
  -- in force (after Show: the nudge reads laid-out positions).
  for _, b in pairs(self.items) do Skin.IconSize(b.ico) end
  if self.closeIco then Skin.IconSize(self.closeIco) end
end
