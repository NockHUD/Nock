-- UI/Frame_PracticeStyle.lua
-- The workbench's Style page (shell step 4): the stage's style levers (T.STYLE_LEVERS) as segmented rows, a demo toggle to watch them on the stage, reset, and the way to the rest in Options.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("PracticeStyleView", "AceEvent-3.0")
local Skin = Nock.Skin

local MARGIN = 8              -- the toolbar's inset
local TOP_PAD = 10
local ROW_H = 46              -- name + segments over the description
local ROW_GAP = 4
local NAME_W = 140
local COL_GAP = 12            -- between the two columns
local SEG_H = 20
local SEG_GAP = 2
local FOOT_H = 34
local MAX_ROWS = 16
local MAX_SEGS = 6

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function practice() return Nock:GetModule("Practice", true) end
local function workbench() return Nock:GetModule("PracticeWorkbench", true) end

local function openOptions()
  local dialog = LibStub("AceConfigDialog-3.0", true)
  if dialog then
    dialog:Open("Nock")
    if dialog.SelectGroup then dialog:SelectGroup("Nock", "utilities", "practice") end
  elseif Nock.OpenConfig then
    Nock:OpenConfig()
  end
end

----------------------------------------------------------------------------
-- A segment click writes the lever's profile key and lets the stage re-read
-- it (NOCK_VISUALS_CHANGED lands on the conveyor's ApplyDock -> ApplyStyle),
-- then repaints the row. ONE OnClick for every segment: the button carries
-- its lever and value.
----------------------------------------------------------------------------
local function segClick(b)
  local L, v = b.lever, b.value
  if not (L and v) then return end
  if Nock.db and Nock.db.profile then Nock.db.profile[L.key] = v end
  Nock:SendMessage("NOCK_VISUALS_CHANGED")
  View:PaintRow(b.row)
end

function View:AcquireRow()
  local n = self._nRows + 1
  self._nRows = n
  local row = self.rows[n]
  if not row then
    row = CreateFrame("Frame", nil, self.frame)
    row:SetHeight(ROW_H)
    Skin.Surface(row, "surface2", "lineSoft")
    local name = row:CreateFontString(nil, "OVERLAY")
    Skin.Font(name, "uiMedium", Skin.SIZES.body)
    name:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -7)
    name:SetWidth(NAME_W)
    name:SetJustifyH("LEFT"); name:SetWordWrap(false)
    Skin.Text(name, "ink")
    row.name = name
    local desc = row:CreateFontString(nil, "OVERLAY")
    Skin.Font(desc, "ui", Skin.SIZES.small)
    desc:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -(7 + SEG_H + 3))
    desc:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    desc:SetJustifyH("LEFT"); desc:SetWordWrap(false)
    Skin.Text(desc, "ink3")
    row.desc = desc
    row.segs = {}
    for i = 1, MAX_SEGS do
      local b = Skin.Button(row, "", "ghost", 60, SEG_H)
      Skin.Font(b.text, "monoMedium", Skin.SIZES.key)
      b.row = row
      b:SetScript("OnClick", segClick)
      b:Hide()
      row.segs[i] = b
    end
    self.rows[n] = row
  end
  row:ClearAllPoints()
  row:Show()
  return row
end

-- The row's segments off its lever: the value in force lit, the rest ghosts.
function View:PaintRow(row)
  local L = row.lever
  if not L then return end
  local cur = profile(L.key, L.values[1])
  if not L.allowed[cur] then cur = L.values[1] end
  local x = 0
  for i = 1, MAX_SEGS do
    local b = row.segs[i]
    local v = L.values[i]
    if v then
      Skin.SetButtonText(b, v)
      Skin.ButtonKind(b, v == cur and "primary" or "ghost")
      b.lever, b.value = L, v
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", row, "TOPLEFT", 12 + NAME_W + x, -6)
      x = x + (b:GetWidth() or 60) + SEG_GAP
      b:Show()
    else
      b:Hide()
    end
  end
end

----------------------------------------------------------------------------
-- Frame: the page. No floating fallback -- without a workbench the levers
-- live in Options and the slash.
----------------------------------------------------------------------------

function View:OnInitialize()
  local wb = workbench()
  local host = wb and wb.PageFrame and wb:PageFrame() or nil
  if not host then return end
  self._host = host
  local f = CreateFrame("Frame", "NockPracticeStyle", host)
  f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
  f:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
  f:SetHeight(TOP_PAD + FOOT_H)
  self._innerW = ((wb.PageWidth and wb:PageWidth()) or 960) - MARGIN * 2
  self.frame = f
  self.rows = {}
  self._nRows = 0

  -- The foot: the preview note on the left, reset and Options on the right.
  local foot = CreateFrame("Frame", nil, f)
  foot:SetHeight(FOOT_H)
  foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MARGIN, 0)
  foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -MARGIN, 0)
  local note = foot:CreateFontString(nil, "OVERLAY")
  Skin.Font(note, "mono", Skin.SIZES.key)
  note:SetPoint("LEFT", foot, "LEFT", 4, 0)
  note:SetJustifyH("LEFT"); note:SetWordWrap(false)
  Skin.Text(note, "ink3")
  foot.note = note
  local opts = Skin.Button(foot, "More in Options", "ghost")
  opts:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
  opts:SetScript("OnClick", openOptions)
  foot.opts = opts
  local reset = Skin.Button(foot, "Reset style", "ghost")
  reset:SetPoint("RIGHT", opts, "LEFT", -6, 0)
  reset:SetScript("OnClick", function()
    local p = practice()
    if p and p.StyleCommand then p:StyleCommand("reset")
    else
      local T = Nock.PracticeTimeline
      if T and T.STYLE_LEVERS and Nock.db and Nock.db.profile then
        for i = 1, #T.STYLE_LEVERS do Nock.db.profile[T.STYLE_LEVERS[i].key] = nil end
        Nock:SendMessage("NOCK_VISUALS_CHANGED")
      end
    end
    View:Rebuild()
  end)
  foot.reset = reset
  self.foot = foot

  if wb.RegisterPage then wb:RegisterPage("style", f, self) end
  f:Hide()
end

function View:OnEnable()
  if not self.frame then return end
  -- The slash and Options write the same keys: repaint when they do.
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "OnVisualsChanged")
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "OnVisualsChanged")
end

-- THE PREVIEW. With no fight running, the page starts the perfect ghost on
-- the stage above so every lever is seen the moment it is clicked; leaving
-- the page stops the ghost and drops that fight quietly (Practice marks it
-- `_previewFight`: no score, no ladder pass, no replay, no review). A fight
-- the player is running is left alone.
function View:OnPageShow()
  self:Rebuild()
  local p = practice()
  local note = self.foot and self.foot.note
  if p and p.ToggleDemo and not Nock.state.sim.fightOn and not p._demo then
    p:ToggleDemo("perfect")
    if Nock.state.sim.fightOn then
      self._preview = true
      p._previewFight = true
    end
  end
  if note then
    note:SetText(self._preview and "PREVIEW - the ghost plays the picked paper above; it ends when you leave this page"
                 or (Nock.state.sim.fightOn and "the running fight shows the levers" or ""))
  end
end

function View:OnPageHide()
  if not self._preview then return end
  self._preview = nil
  local p = practice()
  if not p then return end
  if p._demo and p.ToggleDemo then p:ToggleDemo() end
  if Nock.state.sim.fightOn and p.StopFight then p._previewFight = true; p:StopFight() end
end

function View:PageHeight() return self._pageH or (TOP_PAD + FOOT_H) end

function View:OnVisualsChanged()
  if not (self.frame and self.frame:IsShown()) then return end
  for i = 1, self._nRows do self:PaintRow(self.rows[i]) end
end

----------------------------------------------------------------------------
-- Build: one row per lever, in T.STYLE_LEVERS' own order.
----------------------------------------------------------------------------

function View:Rebuild()
  local f = self.frame
  if not f then return end
  local T = Nock.PracticeTimeline
  local levers = T and T.STYLE_LEVERS or {}
  self._nRows = 0
  -- Two columns (2026-08-27), the levers in reading order left to right: nine
  -- rows in one column stood ~1090 units tall at the default scale, past a
  -- 1080p screen. A row is 12 + name + four 60 px segments, under the
  -- column's ~470.
  local wb = workbench()
  local pageW = (wb and wb.PageWidth and wb:PageWidth()) or 960
  local colW = math.floor((pageW - MARGIN * 2 - COL_GAP) / 2)
  local y = TOP_PAD
  for i = 1, #levers do
    if self._nRows < MAX_ROWS then
      local c = (i - 1) % 2
      local row = self:AcquireRow()
      row.lever = levers[i]
      row:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN + c * (colW + COL_GAP), -y)
      row:SetWidth(colW)
      row.name:SetText(levers[i].name or levers[i].lever)
      row.desc:SetText(levers[i].desc or "")
      self:PaintRow(row)
      if c == 1 or i == #levers then y = y + ROW_H + ROW_GAP end
    end
  end
  for i = self._nRows + 1, #self.rows do self.rows[i]:Hide() end
  self._pageH = y + 6 + FOOT_H
  f:SetHeight(self._pageH)
end
