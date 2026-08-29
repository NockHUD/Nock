-- UI/Frame_PracticeLadder.lua
-- The workbench's Ladder page (shell step 4): an introduction, then the ten teaching rungs on their three tracks, side by side, with done / current / loaded marks; a click loads the drill.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("PracticeLadderView", "AceEvent-3.0")
local Skin = Nock.Skin

local MARGIN = 8              -- the toolbar's inset
local TOP_PAD = 10
local COL_GAP = 12
local HEAD_H = 18             -- a track's uppercase header
local ROW_H = 40
local ROW_GAP = 2
local MARK = 10               -- the state mark: a square
local FOOT_H = 34
local INTRO_H = 92            -- the introduction: a title line over four lines of body
local MAX_ROWS = 16
local MAX_COLS = 4

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function practice() return Nock:GetModule("Practice", true) end
local function workbench() return Nock:GetModule("PracticeWorkbench", true) end

----------------------------------------------------------------------------
-- Rows: pooled Buttons, one per rung, re-anchored by SetLadder. The state
-- reads off the mark -- a green check for a rung passed, a filled ink
-- square for the one the ladder points at, a hollow one for the rest -- and
-- the rung LOADED for the next fight carries the accent line down its left.
----------------------------------------------------------------------------

-- ONE OnClick for every row, never a closure per repaint: the row carries
-- its own id. A click loads the drill (Practice:LoadDrill picks its scenario
-- and fires NOCK_PRACTICE_CHANGED, which repaints the loaded chip) and the
-- page STAYS -- the ladder is read as a board, unlike a scenario pick
-- (user, 2026-08-26).
local function rowClick(row)
  if not row.id then return end
  Nock:SendMessage("NOCK_PRACTICE_LADDER_DRILL", row.id)
end

local function rowEnter(row)
  row.hover = true
  if row.skinFill then Skin.Paint(row.skinFill, "raised", 1) end
end

local function rowLeave(row)
  row.hover = false
  if row.skinFill then Skin.Paint(row.skinFill, "surface2", 1) end
end

function View:AcquireRow()
  local n = self._nRows + 1
  self._nRows = n
  local row = self.rows[n]
  if not row then
    row = CreateFrame("Button", nil, self.frame)
    row:SetHeight(ROW_H)
    Skin.Surface(row, "surface2", "lineSoft")
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bar:SetWidth(2)
    Skin.Paint(bar, "accent", 1)
    bar:Hide()
    row.bar = bar
    -- The mark: a small square frame (fill + hairline) for todo/current, the
    -- check icon over it for done.
    local mark = CreateFrame("Frame", nil, row)
    mark:SetSize(MARK, MARK)
    mark:SetPoint("LEFT", row, "LEFT", 12, 0)
    Skin.Surface(mark, "ground", "line")
    row.mark = mark
    -- The current rung: the box keeps its outline and takes an accent core.
    local dot = mark:CreateTexture(nil, "ARTWORK")
    dot:SetSize(MARK - 6, MARK - 6)
    dot:SetPoint("CENTER", mark, "CENTER", 0, 0)
    Skin.Paint(dot, "accent", 1)
    dot:Hide()
    row.dot = dot
    local check = row:CreateTexture(nil, "OVERLAY")
    check:SetPoint("CENTER", mark, "CENTER", 0, 0)
    Skin.Icon(check, "check", "accent")
    Skin.IconSize(check)
    check:Hide()
    row.check = check
    local num = row:CreateFontString(nil, "OVERLAY")
    Skin.Font(num, "mono", Skin.SIZES.key)
    num:SetPoint("LEFT", mark, "RIGHT", 10, 0)
    num:SetWidth(16)
    num:SetJustifyH("LEFT")
    Skin.Text(num, "ink3")
    row.num = num
    local name = row:CreateFontString(nil, "OVERLAY")
    Skin.Font(name, "uiMedium", Skin.SIZES.body)
    name:SetPoint("TOPLEFT", num, "TOPLEFT", 18, 7)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    Skin.Text(name, "ink")
    row.name = name
    local sub = row:CreateFontString(nil, "OVERLAY")
    Skin.Font(sub, "mono", Skin.SIZES.key)
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    Skin.Text(sub, "ink3")
    row.sub = sub
    -- The pass condition, right-aligned; the loaded chip sits over it.
    local pass = row:CreateFontString(nil, "OVERLAY")
    Skin.Font(pass, "mono", Skin.SIZES.key)
    -- On the NAME's line, so the sub-line below gets the whole row: anchored
    -- to the pass text's left edge the sub kept a third of the column and
    -- its notation/pin was the part cut off (user, 2026-08-26).
    -- (Off `num`, not `name`: the name's RIGHT hangs on the pass, so the
    -- pass's TOP off the name was a cycle -- "Cannot anchor to a region
    -- dependent on it". The name's own y is num's top + 7.)
    pass:SetPoint("TOP", num, "TOP", 0, 7)
    pass:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    pass:SetJustifyH("RIGHT")
    pass:SetWordWrap(false)
    Skin.Text(pass, "ink3")
    row.pass = pass
    name:SetPoint("RIGHT", pass, "LEFT", -8, 0)
    sub:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    local loaded = Skin.Chip(row, Skin.SIZES.key)
    Skin.SetChip(loaded, "loaded", "accent", "accentInk")
    loaded:SetPoint("TOP", num, "TOP", 0, 9)
    loaded:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    loaded:Hide()
    row.loaded = loaded
    row:SetScript("OnClick", rowClick)
    row:SetScript("OnEnter", rowEnter)
    row:SetScript("OnLeave", rowLeave)
    self.rows[n] = row
  end
  row:ClearAllPoints()
  row.hover = false
  if row.skinFill then Skin.Paint(row.skinFill, "surface2", 1) end
  row:Show()
  return row
end

function View:AcquireHeader()
  local n = self._nHeaders + 1
  self._nHeaders = n
  local fs = self.headers[n]
  if not fs then
    fs = self.frame:CreateFontString(nil, "OVERLAY")
    Skin.Font(fs, "monoMedium", Skin.SIZES.small)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    Skin.Text(fs, "ink3")
    self.headers[n] = fs
  end
  fs:ClearAllPoints()
  fs:Show()
  return fs
end

----------------------------------------------------------------------------
-- Frame: the page. No floating fallback -- without a workbench the lesson
-- window's own side ladder is the ladder.
----------------------------------------------------------------------------

function View:OnInitialize()
  local wb = workbench()
  local host = wb and wb.PageFrame and wb:PageFrame() or nil
  if not host then return end
  self._host = host
  local f = CreateFrame("Frame", "NockPracticeLadder", host)
  f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
  f:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
  f:SetHeight(TOP_PAD + FOOT_H)
  self._innerW = ((wb.PageWidth and wb:PageWidth()) or 960) - MARGIN * 2
  self.frame = f
  self.rows, self.headers = {}, {}
  self._nRows, self._nHeaders = 0, 0

  -- The introduction (user, 2026-08-27: "the ladder needs an introduction,
  -- stating that it's a fun challenge to yourself"): a title over a short
  -- body, above the three tracks.
  local intro = CreateFrame("Frame", nil, f)
  intro:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN, -TOP_PAD)
  intro:SetPoint("TOPRIGHT", f, "TOPRIGHT", -MARGIN, -TOP_PAD)
  intro:SetHeight(INTRO_H)
  local title = intro:CreateFontString(nil, "OVERLAY")
  Skin.Font(title, "display", Skin.SIZES.title or 18)
  title:SetPoint("TOPLEFT", intro, "TOPLEFT", 4, 0)
  title:SetJustifyH("LEFT"); title:SetWordWrap(false)
  Skin.Text(title, "ink")
  title:SetText("A challenge to yourself")
  intro.title = title
  local body = intro:CreateFontString(nil, "OVERLAY")
  Skin.Font(body, "ui", Skin.SIZES.body)
  -- Anchored top AND bottom: a wrapped FontString with no height of its own
  -- draws one line and an ellipsis (in-game, 2026-08-27).
  body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  body:SetPoint("BOTTOMRIGHT", intro, "BOTTOMRIGHT", -4, 0)
  body:SetJustifyH("LEFT"); body:SetJustifyV("TOP"); body:SetWordWrap(true)
  Skin.Text(body, "ink2")
  body:SetText("Ten steps on three tracks. Each step is the one before it plus one more thing: hold the beat, add the shots one at a time, then the weave, then the haste windows and the opener. An attempt is one minute, graded against the step's pass line. Nothing is locked: click a step to load it, press Start, and it is marked when you pass. A game against your own hands, not a ranking -- the last step is the rotation you raid with.")
  intro.body = body
  self.intro = intro

  -- The foot: progress on the left, the reset on the right.
  local foot = CreateFrame("Frame", nil, f)
  foot:SetHeight(FOOT_H)
  foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MARGIN, 0)
  foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -MARGIN, 0)
  local prog = foot:CreateFontString(nil, "OVERLAY")
  Skin.Font(prog, "mono", Skin.SIZES.mono)
  prog:SetPoint("LEFT", foot, "LEFT", 4, 0)
  prog:SetJustifyH("LEFT")
  Skin.Text(prog, "ink3")
  foot.prog = prog
  local reset = Skin.Button(foot, "Reset ladder", "ghost")
  reset:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
  reset:SetScript("OnClick", function()
    local p = practice()
    if p and p.ResetLadder then p:ResetLadder() end
  end)
  foot.reset = reset
  self.foot = foot

  if wb.RegisterPage then wb:RegisterPage("ladder", f, self) end
  f:Hide()
end

function View:OnEnable()
  if not self.frame then return end
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "OnPracticeChanged")
  self:RegisterMessage("NOCK_PRACTICE_FIGHT_DONE", "OnPracticeChanged")
end

function View:OnPageShow() self:Rebuild() end
function View:PageHeight() return self._pageH or (TOP_PAD + FOOT_H) end

-- A pick or a fight boundary moved the rungs under us: repaint if shown.
function View:OnPracticeChanged()
  if self.frame and self.frame:IsShown() then self:Rebuild() end
end

----------------------------------------------------------------------------
-- Build: the rows off Practice:LadderItems (id, name, sub, section marker,
-- pass text, state), one column per section.
----------------------------------------------------------------------------

local function paintState(row, state, isLoaded)
  local mark, check = row.mark, row.check
  if state == "done" then
    -- The check IS the mark: the pixel glyph is drawn at its native size,
    -- which is bigger than the box (it spilled over it, 2026-08-26).
    mark:Hide()
    row.dot:Hide()
    check:Show()
    Skin.IconSize(check)
    Skin.Text(row.name, "ink2")
  elseif state == "cur" then
    mark:Show()
    Skin.Surface(mark, "ground", "ink2")
    row.dot:Show()
    check:Hide()
    Skin.Text(row.name, "ink")
  else
    mark:Show()
    Skin.Surface(mark, "ground", "line")
    row.dot:Hide()
    check:Hide()
    Skin.Text(row.name, "ink")
  end
  if isLoaded then
    row.bar:Show(); row.loaded:Show(); row.pass:Hide()
  else
    row.bar:Hide(); row.loaded:Hide(); row.pass:Show()
  end
end

function View:Rebuild()
  local f = self.frame
  if not f then return end
  local p = practice()
  local items = p and p.LadderItems and p:LadderItems() or nil
  local loaded = p and p.LadderState and p:LadderState().loaded or nil
  self._nRows, self._nHeaders = 0, 0
  -- Count the columns first: the width is shared out among them.
  local nCols = 0
  for i = 1, (items and #items or 0) do if items[i].section then nCols = nCols + 1 end end
  if nCols < 1 then nCols = 1 elseif nCols > MAX_COLS then nCols = MAX_COLS end
  local colW = math.floor((self._innerW - (nCols - 1) * COL_GAP) / nCols)
  local colTop = TOP_PAD + INTRO_H + 6   -- the tracks start under the introduction
  local col, y, tallest, done, total = -1, 0, 0, 0, 0
  for i = 1, (items and #items or 0) do
    local it = items[i]
    if it.section and col < MAX_COLS - 1 then
      col = col + 1
      y = colTop
      local head = self:AcquireHeader()
      head:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN + col * (colW + COL_GAP), -y)
      head:SetWidth(colW)
      head:SetText(tostring(it.section):upper())
      y = y + HEAD_H
    end
    if col < 0 then col = 0; y = colTop end
    if self._nRows < MAX_ROWS then
      local row = self:AcquireRow()
      row:SetWidth(colW)
      row:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN + col * (colW + COL_GAP), -y)
      row.id = it.id
      row.num:SetText(tostring(i))
      row.name:SetText(it.name or it.id or "")
      row.sub:SetText(it.sub or "")
      row.pass:SetText(it.pass or "")
      paintState(row, it.state, loaded ~= nil and it.id == loaded)
      y = y + ROW_H + ROW_GAP
      if y > tallest then tallest = y end
    end
    total = total + 1
    if it.state == "done" then done = done + 1 end
  end
  for i = self._nRows + 1, #self.rows do self.rows[i]:Hide() end
  for i = self._nHeaders + 1, #self.headers do self.headers[i]:Hide() end
  if tallest == 0 then tallest = colTop end
  self.foot.prog:SetText(total > 0 and ("%d of %d steps passed"):format(done, total) or "no ladder")
  self._pageH = tallest + 6 + FOOT_H
  f:SetHeight(self._pageH)
end
