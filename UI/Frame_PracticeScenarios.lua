-- UI/Frame_PracticeScenarios.lua
-- The scenario picker: every catalog group as a grid of cards, one click picks what the next practice fight runs. The workbench's Scenarios PAGE (shell step 4); a floating window only without one.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("PracticeScenarioView", "AceEvent-3.0")
local C = Nock.Constants
local Skin = Nock.Skin

local PAD = C.DIM.OUTER_PAD
local WIDTH = 680             -- the floating window (no workbench)
local MARGIN = 8              -- gutter between the edge and the card grid (the toolbar's inset)
local TOP_PAD = 6             -- the page's room over the first header
local TITLE_H = 24            -- floating only
-- Compact (user, 2026-08-26: six groups barely fit a 1440p screen): 34 px
-- cards, 6 px gaps, five columns on the page (four in the floating window).
local HEADER_H = 16           -- a group's uppercase header row
local CARD_H = 34
local GAP = 6
local ROW_H = CARD_H + GAP
local GROUP_GAP = 6           -- below a group's last row
local HINT_H = 18
local COLS = 4                -- the floating window; the page uses PAGE_COLS
local PAGE_COLS = 5
local SWATCH_W = 3            -- the rotation's colour, a hairline down the card's left
local NOTE_LETTER = { ["clips by design"] = "C", ["tight weave"] = "W", ["no weave key"] = "K" }
local NAME_SIZE = Skin.SIZES.body
local SUB_SIZE = Skin.SIZES.key

-- Group swatch defaults. Paper drills carry the rotation's own display colour
-- from the catalog; scripts and user scenarios have none, so the group's own
-- hue keeps the grid readable instead of leaving three quarters of it grey.
local GROUP_COLOR = {
  scripts = { 0.45, 0.62, 0.85 },
  mine    = { 0.70, 0.55, 0.85 },
}

-- The page's DISPLAY groups (user, 2026-08-27): the catalog's six groups
-- shown as five, Scripts and the Drill ladder under one header, each one
-- foldable from its header (the fold remembered per group in the profile).
-- Catalog key -> display key; the display order and titles below.
local DISPLAY_OF = { turret = "turret", weave = "weave", mine = "mine", scripts = "drills", ladder = "drills", free = "free" }
local DISPLAY = {
  { key = "turret", title = "Turret" },
  { key = "weave",  title = "Weave" },
  { key = "mine",   title = "Mine" },
  { key = "drills", title = "Drills + ladder" },
  { key = "free",   title = "Free play" },
}
-- ACCORDION (user, 2026-08-27): one group open at a time, Turret by default,
-- each group a box with a title bar. The open one is remembered
-- (`practiceScenarioOpen`).
local BOX_HEAD_H = 26         -- the title bar
local BOX_PAD = 6             -- the box's inner padding around the cards
local BOX_GAP = 6             -- between boxes

local HINT_TEXT = "Add your own in Options -> Practice:  Name: rf@5 lust@20 drums@20 dst@30 pot@21 qs@5 ews=2.17 lock=5:5:1:1 len=90 qs=off"
local NEW_NAME = "+ New..."

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function practice() return Nock:GetModule("Practice", true) end
local function workbench() return Nock:GetModule("PracticeWorkbench", true) end

----------------------------------------------------------------------------
-- Cards. Pooled Buttons: the grid rebuilds from Catalog() on every show,
-- but nothing is created after the first show that had this many rows, and
-- there is no Refresh on this module at all -- the picker never ticks.
--
-- The look is the "Workbench States" page's card: surface2 on the black,
-- a soft hairline, the accent line and a `picked` chip on the one in force.
----------------------------------------------------------------------------

local function cardBorder(b)
  local line
  if b.selected then line = "accent"
  elseif b.hover then line = "line"
  else line = "lineSoft" end
  local lines = b.skinLine
  if lines then for i = 1, 4 do Skin.Paint(lines[i], line, 1) end end
  if b.skinFill then Skin.Paint(b.skinFill, b.hover and "raised" or "surface2", 1) end
  if b.picked then
    if b.selected then b.picked:Show() else b.picked:Hide() end
  end
end

local function cardEnter(b)
  b.hover = true
  cardBorder(b)
  -- The paper's own cost, on hover (M.PaperNotes).
  if b.noteText and GameTooltip then
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(b.noteTag or "", 0.85, 0.72, 0.4)
    GameTooltip:AddLine(b.noteText, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end
end

local function cardLeave(b)
  b.hover = false
  cardBorder(b)
  if GameTooltip then GameTooltip:Hide() end
end

local function cardClick(b)
  if b.isNew then
    View:OpenOptions()
    return
  end
  local p = practice()
  -- SetScenario writes the profile AND sends NOCK_PRACTICE_CHANGED itself;
  -- sending it again here would rebuild every listening view twice.
  if p and b.scenarioName then p:SetScenario(b.scenarioName) end
  -- A pick is done: back to the page the picker was opened from (the Stage
  -- by default -- user, 2026-08-26); floating, the window goes.
  if View._host then
    local wb = workbench()
    if wb then wb:Select(wb.ReturnPage and wb:ReturnPage() or "stage") end
  else
    View:Toggle(false)
  end
end

function View:AcquireCard()
  local n = self._nCards + 1
  self._nCards = n
  local b = self.cards[n]
  if not b then
    b = CreateFrame("Button", nil, self.frame)
    b:SetFrameLevel(self.frame:GetFrameLevel() + 3)   -- over the boxes, always
    b:SetSize(self._cardW, CARD_H)
    Skin.Surface(b, "surface2", "lineSoft")
    local sw = b:CreateTexture(nil, "ARTWORK")
    sw:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    sw:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
    sw:SetWidth(SWATCH_W)
    b.swatch = sw
    local name = b:CreateFontString(nil, "OVERLAY")
    Skin.Font(name, "uiBold", NAME_SIZE)
    name:SetPoint("TOPLEFT", b, "TOPLEFT", SWATCH_W + 9, -5)
    name:SetWidth(self._cardW - SWATCH_W - 14)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    b.name = name
    local sub = b:CreateFontString(nil, "OVERLAY")
    Skin.Font(sub, "mono", SUB_SIZE)
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    sub:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    -- One line, truncated: a wrapping sub-line would grow past the card, and
    -- SetMaxLines is not something to bet on this client.
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    b.sub = sub
    local picked = Skin.Chip(b, Skin.SIZES.key)
    Skin.SetChip(picked, "picked", "accent", "accentInk")
    picked:SetPoint("TOPRIGHT", b, "TOPRIGHT", -6, -4)
    picked:Hide()
    b.picked = picked
    -- The paper's cost by design: one amber letter at the card's foot -- C
    -- for a planned clip, W for a tight weave (the pixel icon "looked
    -- cursed" at 18 px, user 2026-08-26); the sentence is the hover.
    local tag = b:CreateFontString(nil, "OVERLAY")
    Skin.Font(tag, "monoMedium", Skin.SIZES.body)
    tag:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 3)
    Skin.Text(tag, "wait")
    tag:Hide()
    b.tag = tag
    b:SetScript("OnClick", cardClick)
    b:SetScript("OnEnter", cardEnter)
    b:SetScript("OnLeave", cardLeave)
    self.cards[n] = b
  end
  b:ClearAllPoints()
  b.hover = false
  b:Show()
  return b
end

-- The title bar is a button: a click opens its group and closes the one
-- that was open (a click on the open one leaves it open -- one is always
-- open, so the page never collapses to bare bars).
local function headerClick(bar)
  local h = bar.box or bar
  local key = h.groupKey
  if not key then return end
  if Nock.db and Nock.db.profile then Nock.db.profile.practiceScenarioOpen = key end
  View:Rebuild()
  Nock:SendMessage("NOCK_PRACTICE_LAYOUT")   -- the window follows the page's height
end

local function openKey()
  local p = Nock.db and Nock.db.profile
  return (p and p.practiceScenarioOpen) or "turret"
end

-- A box: the group's surface, its title bar (a button) with the title in
-- the UI face, the count on the right, and the accent bar down the open
-- one's left edge.
function View:AcquireHeader()
  local n = self._nHeaders + 1
  self._nHeaders = n
  local h = self.headers[n]
  if not h then
    -- The box is a plain frame UNDER the cards (a box acquired after the
    -- cards had a higher frame level and, as a button, swallowed every
    -- click on them once another group was opened -- user, 2026-08-27);
    -- only the title bar is the button.
    h = CreateFrame("Frame", nil, self.frame)
    h:SetFrameLevel(self.frame:GetFrameLevel() + 1)
    Skin.Surface(h, "surface", "line")
    local bar = CreateFrame("Button", nil, h)
    bar.box = h
    bar:SetPoint("TOPLEFT", h, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", h, "TOPRIGHT", -1, -1)
    bar:SetHeight(BOX_HEAD_H - 1)
    Skin.Surface(bar, "surface2", nil)
    h.bar = bar
    local accent = h:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", h, "TOPLEFT", 1, -1)
    accent:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 1, 1)
    accent:SetWidth(2)
    Skin.Paint(accent, "accent", 1)
    h.accent = accent
    -- On the BAR (a child frame draws over its parent's font strings,
    -- whatever the layer -- the title was under the strip in-game).
    local fs = bar:CreateFontString(nil, "OVERLAY")
    Skin.Font(fs, "uiMedium", 13)
    fs:SetPoint("LEFT", bar, "LEFT", 10, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    Skin.Text(fs, "ink")
    h.text = fs
    local meta = bar:CreateFontString(nil, "OVERLAY")
    Skin.Font(meta, "mono", Skin.SIZES.key)
    meta:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
    meta:SetPoint("LEFT", fs, "RIGHT", 10, 0)
    meta:SetJustifyH("RIGHT")
    meta:SetWordWrap(false)
    Skin.Text(meta, "ink3")
    h.meta = meta
    bar:SetScript("OnClick", headerClick)
    bar:SetScript("OnEnter", function(b) if not b.box.open then Skin.Surface(b, "raised", nil) end end)
    bar:SetScript("OnLeave", function(b) Skin.Surface(b, "surface2", nil) end)
    self.headers[n] = h
  end
  h:ClearAllPoints()
  h:Show()
  return h
end

----------------------------------------------------------------------------
-- Frame: the workbench's page when there is one, a window otherwise.
----------------------------------------------------------------------------

function View:OnInitialize()
  local wb = workbench()
  local host = wb and wb.PageFrame and wb:PageFrame() or nil
  self._host = host
  local f
  if host then
    f = CreateFrame("Frame", "NockPracticeScenarios", host)
    f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    f:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    f:SetHeight(TOP_PAD + HINT_H)
    self._innerW = ((wb.PageWidth and wb:PageWidth()) or 960) - MARGIN * 2
    if wb.RegisterPage then wb:RegisterPage("scenarios", f, self) end
  else
    f = CreateFrame("Frame", "NockPracticeScenarios", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 200)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    Nock.UI.RegisterPanelBackground(f)
    -- The practice scale (Options -> Practice), top-level frame only.
    Nock.UI.RegisterPracticeScale(f)
    local pos = profile("practiceScenariosPos", nil)
    if pos then f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
    self._innerW = WIDTH - MARGIN * 2

    -- Title bar. Practice windows are tools: they drag whenever no fight
    -- runs, regardless of the global lock, and never during one.
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD)
    bar:SetHeight(TITLE_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
      if Nock.state.sim.fightOn then return end
      f:StartMoving()
    end)
    bar:SetScript("OnDragStop", function()
      f:StopMovingOrSizing()
      local point, _, relPoint, x, y = f:GetPoint()
      Nock.db.profile.practiceScenariosPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    local title = bar:CreateFontString(nil, "OVERLAY")
    Skin.Font(title, "display", Skin.SIZES.title)
    title:SetPoint("LEFT", bar, "LEFT", 4, 0)
    title:SetText("SCENARIOS")
    Skin.Text(title, "ink")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    -- The title bar spans the full width and eats mouse input for the drag,
    -- so the close button has to sit above it or the X never clicks.
    close:SetFrameLevel(bar:GetFrameLevel() + 5)
    close:SetScript("OnClick", function() View:Toggle(false) end)
    self.bar, self.title = bar, title
  end
  self._cols = self._host and PAGE_COLS or COLS
  self._cardW = math.floor((self._innerW - BOX_PAD * 2 - (self._cols - 1) * GAP) / self._cols)

  local hint = f:CreateFontString(nil, "OVERLAY")
  Skin.Font(hint, "mono", SUB_SIZE)
  hint:SetJustifyH("LEFT")
  hint:SetWordWrap(false)
  Skin.Text(hint, "ink3")
  hint:SetText(HINT_TEXT)

  self.frame, self.hint = f, hint
  self.cards, self.headers = {}, {}
  self._nCards, self._nHeaders = 0, 0
  f:Hide()
end

function View:OnEnable()
  self:RegisterMessage("NOCK_PRACTICE_SCENARIOS_TOGGLE", "OnToggleMessage")
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "OnPracticeChanged")
  self:RegisterMessage("NOCK_PRACTICE_RESET_POS", "ResetPos")
end

function View:ResetPos()
  local f = self.frame
  if not f or self._host then return end
  Nock.db.profile.practiceScenariosPos = nil
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

-- The toggle message (the slash, the toolbar's scenario name): in the
-- workbench it is "go to the Scenarios page" and never a close.
function View:OnToggleMessage()
  if self._host then
    local wb = workbench()
    if wb then
      if wb.Open then wb:Open() end
      wb:Select("scenarios")
    end
    return
  end
  self:Toggle(not self.frame:IsShown())
end

function View:Toggle(show)
  if self._host then
    local wb = workbench()
    if show and wb then wb:Select("scenarios") end
    return
  end
  if show then
    self:Rebuild()
    self.frame:Show()
  else
    self.frame:Hide()
  end
end

-- The workbench shows the page: build the grid from the catalog as it stands.
function View:OnPageShow()
  self:Rebuild()
end

-- The height the page needs, for the workbench (set by Rebuild).
function View:PageHeight() return self._pageH or (TOP_PAD + HINT_H) end

-- The pick moved under us (the page, the toolbar, or the options dropdown):
-- only the accent line has to follow, so no rebuild.
function View:OnPracticeChanged()
  if not (self.frame and self.frame:IsShown()) then return end
  self:UpdateSelection()
end

function View:UpdateSelection()
  local want = profile("practiceScenario", "Clean French")
  for i = 1, self._nCards do
    local b = self.cards[i]
    b.selected = (not b.isNew) and b.scenarioName == want or false
    cardBorder(b)
  end
end

----------------------------------------------------------------------------
-- Build. On show only: Catalog() allocates, and the grid is laid out from it.
----------------------------------------------------------------------------

function View:FillCard(b, name, sub, color, dashed, isNew, item)
  b.scenarioName = (not isNew) and name or nil
  b.isNew = isNew and true or false
  b.dashed = dashed and true or false
  b.name:SetText(name)
  Skin.Text(b.name, dashed and "ink2" or "ink")
  b.sub:SetText(sub or "")
  Skin.Text(b.sub, "ink3")
  -- What the paper costs by design (nil for a script or a clean paper).
  local p = practice()
  local noteTag, noteText = nil, nil
  if p and p.PaperNotes and item and item.sc and not isNew then
    noteTag, noteText = p:PaperNotes(item.sc)
  end
  b.noteTag, b.noteText = noteTag, noteText
  if noteTag then
    b.tag:SetText(NOTE_LETTER[noteTag] or "!")
    -- A missing weave key is red: it is the player's setup, not the paper.
    Skin.Text(b.tag, noteTag == "no weave key" and "bad" or "wait")
    b.tag:Show()
  else
    b.tag:Hide()
  end
  if color and not dashed then
    b.swatch:SetColorTexture(color[1] or 0.6, color[2] or 0.6, color[3] or 0.6, 1)
    b.swatch:Show()
  else
    b.swatch:Hide()
  end
end

function View:Rebuild()
  local p = practice()
  self._nCards, self._nHeaders = 0, 0
  local cat = p and p.Catalog and p:Catalog()
  local f = self.frame
  local y = self._host and TOP_PAD or (PAD + TITLE_H + 4)   -- from the frame top, downward
  local innerW, cardW = self._innerW, self._cardW
  local cols = self._cols or COLS

  -- Bucket the catalog's items into the display groups (an item remembers
  -- the catalog group it came from, for its colour).
  local groups = cat and cat.groups or nil
  local bucket = self._bucket
  if not bucket then bucket = {}; self._bucket = bucket end
  for _, d in ipairs(DISPLAY) do
    local list = bucket[d.key]
    if not list then list = {}; bucket[d.key] = list end
    for i = #list, 1, -1 do list[i] = nil end
  end
  -- A catalog group the map does not know keeps its own header, before
  -- Free play (which stays the grid's last card).
  local order = self._order
  if not order then order = {}; self._order = order end
  for i = #order, 1, -1 do order[i] = nil end
  for _, d in ipairs(DISPLAY) do order[#order + 1] = d end
  for i = 1, (groups and #groups or 0) do
    local g = groups[i]
    local dk = DISPLAY_OF[g.key]
    if not dk then
      dk = g.key
      if not bucket[dk] then bucket[dk] = {} end
      for j = #bucket[dk], 1, -1 do bucket[dk][j] = nil end
      table.insert(order, #order, { key = dk, title = g.title or g.key })
    end
    local list = bucket[dk]
    for k = 1, #(g.items or {}) do
      local item = g.items[k]
      item._groupKey = g.key
      list[#list + 1] = item
    end
  end
  local picked = profile("practiceScenario", "Clean French")
  -- The open group: the remembered one when it has something to show, else
  -- the first that has.
  local want = openKey()
  local openK
  for _, d in ipairs(order) do
    local n = #bucket[d.key] + (d.key == "mine" and 1 or 0)
    if n > 0 and (d.key == want or not openK) then openK = d.key; if d.key == want then break end end
  end
  for _, d in ipairs(order) do
    local items = bucket[d.key]
    local isMine = (d.key == "mine")
    local dashed = (d.key == "free")
    local count = #items + (isMine and 1 or 0)   -- Mine always offers "+ New..."
    if count > 0 then
      local open = (d.key == openK)
      local box = self:AcquireHeader()
      box.groupKey, box.open = d.key, open
      box:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN, -y)
      box:SetWidth(innerW)
      box.text:SetText(d.title)
      -- The bar says what is inside: the count, and the pick when it is in
      -- there and the box is shut.
      local inside
      for k = 1, #items do if items[k].name == picked then inside = picked end end
      box.meta:SetText(open and ("%d"):format(#items) or ("%d%s"):format(#items, inside and ("  \194\183  " .. inside) or ""))
      if open then box.accent:Show() else box.accent:Hide() end
      local boxH = BOX_HEAD_H
      if open then
        local top = y + BOX_HEAD_H + BOX_PAD
        for k = 1, count do
          local idx = k - 1
          local b = self:AcquireCard()
          b:SetPoint("TOPLEFT", f, "TOPLEFT",
            MARGIN + BOX_PAD + (idx % cols) * (cardW + GAP),
            -(top + math.floor(idx / cols) * ROW_H))
          local item = items[k]
          if item then
            self:FillCard(b, item.name, item.sub, item.color or GROUP_COLOR[item._groupKey], dashed, false, item)
          else
            self:FillCard(b, NEW_NAME, "write a scenario line in Options -> Practice", nil, true, true)
          end
        end
        boxH = BOX_HEAD_H + BOX_PAD + math.ceil(count / cols) * ROW_H - GAP + BOX_PAD
      end
      box:SetHeight(boxH)
      y = y + boxH + BOX_GAP
    end
  end

  for i = self._nCards + 1, #self.cards do self.cards[i]:Hide() end
  for i = self._nHeaders + 1, #self.headers do self.headers[i]:Hide() end

  self.hint:ClearAllPoints()
  self.hint:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN, -y)
  self.hint:SetWidth(innerW)
  self._pageH = y + HINT_H + PAD
  f:SetHeight(self._pageH)
  self:UpdateSelection()
end

----------------------------------------------------------------------------
-- "+ New...": the scenario DSL lives in the options box, so the card just
-- takes the player there.
----------------------------------------------------------------------------

function View:OpenOptions()
  local dialog = LibStub("AceConfigDialog-3.0", true)
  if dialog then
    dialog:Open("Nock")
    if dialog.SelectGroup then dialog:SelectGroup("Nock", "utilities", "practice") end
    return
  end
  if Nock.OpenConfig then Nock:OpenConfig() return end
  Nock:Print("Practice: add your own scenarios in the settings window -- Utilities -> Practice.")
end
