-- UI/Frame_PracticeCombatLog.lua
-- The combat log: Expert mode's timeline of what you did -- movement, autos, casts, melee, cooldowns -- with no plan on it (practice only; NOCK_PRACTICE_EXPERT).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("PracticeCombatLogView", "AceEvent-3.0")
local Skin = Nock.Skin
local Transport = Nock.UI.PracticeTransport
local Palette = Nock.UI.PracticePalette

local W = 640
local HEAD_H = 26
local LABEL_W = 52            -- the row-label gutter
local LABEL_INSET = 8
local ROW_H = 18
local AXIS_H = 14
local PAD = 6
local SPAN = 8                -- seconds across the lanes
local REPLAY_AHEAD = 0.25     -- in a replay this fraction of the span lies past the cursor
local MIN_LABEL_W = 26        -- an item narrower than this carries no word
local ZONE_LABEL_W = 34
local TR_H = 30               -- the replay transport's row (shown while a stopped fight is scrubbed)
local NAME_W = 200            -- the scenario picker in the head
local CHEV_GAP = 4
local PICK_W, PICK_ROW_H, PICK_MAX = 280, 20, 18
local PAL_SIZE, PAL_GAP = 30, 5   -- the buff row: the panel's proc palette, shared
local PAL_ROW_H = PAL_SIZE + 4 + 8
-- The rows, top to bottom; `cd` only when the fight has cooldowns/procs.
local ROWS = {
  { id = "move",  label = "MOVE" },
  { id = "auto",  label = "AUTO" },
  { id = "cast",  label = "CAST" },
  { id = "melee", label = "MELEE" },
  { id = "procs", label = "CD" },
}
local ROW_IX = {}
for i = 1, #ROWS do ROW_IX[ROWS[i].id] = i end
-- The word an item carries, by its symbol / label.
local SYM_WORD = { s = "Steady", m = "Multi", A = "Arcane", r = "Raptor", w = "white", KC = "KC", a = nil, mv = nil }

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function practice() return Nock:GetModule("Practice", true) end
local function workbench() return Nock:GetModule("PracticeWorkbench", true) end

local function seatDefault(f)
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", 0, (UIParent:GetHeight() or 768) / 4)
end

function View:OnInitialize()
  local f = CreateFrame("Frame", "NockPracticeCombatLog", UIParent)
  f:SetSize(W, HEAD_H + 4 * ROW_H + AXIS_H + PAD)
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  Skin.Surface(f, "surface", "line")
  Nock.UI.RegisterPracticeScale(f)
  local pos = profile("practiceCombatLogPos", nil)
  if pos then f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
  else seatDefault(f) end
  -- Esc in Expert (UISpecialFrames, joined by SetExpert) hides the frame
  -- behind our back: during a fight that is Stop, and either way it is the
  -- way back to the workbench. Our own hides set _hiding first.
  f:SetScript("OnHide", function()
    local hiding = View._hiding
    View._hiding = false
    if hiding or not View._expert then return end
    local p = practice()
    if p and Nock.state.sim.fightOn and p.StopFight then p:StopFight() end
    Nock:SendMessage("NOCK_PRACTICE_EXPERT", false)
  end)

  -- The head: chip, scenario, streak, START/STOP, WORKBENCH. The practice
  -- panel paints the chip, the name, the streak and the button's label (the
  -- same words as its own and the Focus head's). Drag between fights.
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  head:SetHeight(HEAD_H)
  Skin.Surface(head, "surface2")
  local rule = Skin.Rule(head, "lineSoft")
  rule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)
  rule:SetHeight(1)
  local function dragStart()
    if Nock.state.sim.fightOn then return end
    f:StartMoving()
  end
  local function dragStop()
    f:StopMovingOrSizing()
    local left, top = f:GetLeft(), f:GetTop()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    Nock.db.profile.practiceCombatLogPos = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = left, y = top }
  end
  head:EnableMouse(true)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", dragStart)
  head:SetScript("OnDragStop", dragStop)
  -- The grip at the head's left (the practice panel's three lines): the
  -- visible handle, and the one part of the head that still drags when the
  -- head's own mouse is off (user, 2026-08-27).
  local grip = CreateFrame("Button", nil, head)
  grip:SetSize(11, 14)
  grip:SetPoint("LEFT", head, "LEFT", LABEL_INSET, 0)
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", dragStart)
  grip:SetScript("OnDragStop", dragStop)
  grip.tipTitle = "Combat log"
  grip.tipText = "Drag to move (between fights)."
  local griphl = grip:CreateTexture(nil, "HIGHLIGHT")
  griphl:SetAllPoints()
  griphl:SetColorTexture(1, 1, 1, 0.05)
  for i = 1, 3 do
    local t = grip:CreateTexture(nil, "ARTWORK")
    Skin.Paint(t, "ink3", 0.7)
    t:SetSize(1, 10)
    t:SetPoint("LEFT", grip, "LEFT", (i - 1) * 3, 0)
  end
  head.grip = grip
  local chip = Skin.Chip(head)
  chip:SetPoint("LEFT", grip, "RIGHT", 6, 0)
  Skin.SetChip(chip, "READY", "accent", "accentInk")
  -- The scenario is a PICKER here (user, 2026-08-27: "a dropdown for
  -- rotation in the expert view"): a chevron leads the name, the practice
  -- panel writes the name, and a click between fights drops the catalog
  -- under it (ShowPicker).
  local nameBtn = CreateFrame("Button", nil, head)
  nameBtn:SetPoint("LEFT", chip, "RIGHT", 10, 0)
  nameBtn:SetSize(NAME_W, HEAD_H - 4)
  local chev = nameBtn:CreateTexture(nil, "ARTWORK")
  Skin.Icon(chev, "chevron", "ink3", 1)
  local chevSize = Skin.IconSize(chev) or 24
  local chevMargin = chevSize * 4 / 24
  chev:SetPoint("LEFT", nameBtn, "LEFT", -chevMargin, 0)
  local name = nameBtn:CreateFontString(nil, "OVERLAY")
  Skin.Font(name, "ui", Skin.SIZES.body)
  name:SetPoint("LEFT", nameBtn, "LEFT", chevSize - chevMargin * 2 + CHEV_GAP, 0)
  name:SetPoint("RIGHT", nameBtn, "RIGHT", 0, 0)
  name:SetJustifyH("LEFT"); name:SetWordWrap(false)
  Skin.Text(name, "ink2")
  nameBtn:SetScript("OnEnter", function() Skin.Text(name, "accent"); Skin.Icon(chev, "chevron", "accent", 1) end)
  nameBtn:SetScript("OnLeave", function() Skin.Text(name, "ink2"); Skin.Icon(chev, "chevron", "ink3", 1) end)
  nameBtn:SetScript("OnClick", function() View:TogglePicker() end)
  head.nameBtn, head.chev = nameBtn, chev
  local streak = head:CreateFontString(nil, "OVERLAY")
  Skin.Font(streak, "monoMedium", Skin.SIZES.mono)
  streak:SetPoint("LEFT", nameBtn, "RIGHT", 14, 0)
  streak:SetJustifyH("LEFT"); streak:SetWordWrap(false)
  Skin.Text(streak, "ink")
  local back = Skin.Button(head, "WORKBENCH", "ghost", nil, HEAD_H - 6)
  Skin.Font(back.text, "monoMedium", Skin.SIZES.key)
  Skin.SetButtonText(back, "WORKBENCH")
  back:SetPoint("RIGHT", head, "RIGHT", -LABEL_INSET, 0)
  back.tipTitle = "Back to the workbench"
  back.tipText = "The fight keeps running. Esc during a fight stops it."
  back:SetScript("OnClick", function() Nock:SendMessage("NOCK_PRACTICE_EXPERT", false) end)
  local stop = Skin.Button(head, "START", "primary", nil, HEAD_H - 6)
  Skin.Font(stop.text, "monoMedium", Skin.SIZES.key)
  Skin.SetButtonText(stop, "START")
  stop:SetPoint("RIGHT", back, "LEFT", -6, 0)
  stop:SetScript("OnClick", function()
    local p = practice()
    if not p then return end
    if Nock.state.sim.fightOn then p:StopFight() else p:StartFight() end
  end)
  -- The two efficiencies (user, 2026-08-27): auto and GCD, live off the
  -- grader's counters during the fight, off the scorecard after it. Centred
  -- in the room between the streak and the buttons, so it can overlap neither.
  local eff = head:CreateFontString(nil, "OVERLAY")
  Skin.Font(eff, "monoMedium", Skin.SIZES.mono)
  eff:SetPoint("LEFT", streak, "RIGHT", 10, 0)
  eff:SetPoint("RIGHT", stop, "LEFT", -10, 0)
  eff:SetJustifyH("CENTER"); eff:SetWordWrap(false)
  Skin.Text(eff, "ink2")
  head.chip, head.name, head.streak, head.stop, head.back, head.eff = chip, name, streak, stop, back, eff
  self._live = {}
  self._effA, self._effG = nil, nil
  self.head = head

  -- The buff row (user, 2026-08-27: "so people can click the buffs they want
  -- while testing"): the practice panel's proc palette, under the head, shown
  -- when the drill lets you touch any of it (Palette:Resolve); the lanes move
  -- down by its row while it is up.
  local pal = Palette.New(f, PAL_SIZE, PAL_GAP)
  pal.frame:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_INSET, -HEAD_H - 4)
  pal.frame:Hide()
  self.palette = pal
  self._palOn, self._palDirty = false, true

  -- The gutter: one label per row, painted at layout.
  local gutter = CreateFrame("Frame", nil, f)
  gutter:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEAD_H)
  gutter:SetSize(LABEL_W, #ROWS * ROW_H)
  self.gutter = gutter
  self.rowLabels = {}
  for i = 1, #ROWS do
    local fs = gutter:CreateFontString(nil, "OVERLAY")
    Skin.Font(fs, "mono", 9)
    fs:SetPoint("LEFT", gutter, "TOPLEFT", LABEL_INSET, -(i - 0.5) * ROW_H)
    fs:SetJustifyH("LEFT")
    fs:SetText(ROWS[i].label)
    Skin.Text(fs, "ink3")
    self.rowLabels[i] = fs
  end

  -- The lanes: time left to right, clipped, the wheel scrubs a replay.
  local lanes = CreateFrame("Frame", nil, f)
  lanes:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_W, -HEAD_H)
  lanes:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -HEAD_H)
  lanes:SetHeight(#ROWS * ROW_H)
  if lanes.SetClipsChildren then lanes:SetClipsChildren(true) end
  if lanes.EnableMouseWheel then
    lanes:EnableMouseWheel(true)
    lanes:SetScript("OnMouseWheel", function(_, delta)
      local p = practice()
      if not (p and p._replay) then return end
      local dir = (delta > 0) and 1 or -1
      if IsAltKeyDown and IsAltKeyDown() then p:ReplayStep(dir, "clip")
      elseif IsShiftKeyDown and IsShiftKeyDown() then p:ReplayStep(dir, "sec", 2)
      elseif IsControlKeyDown and IsControlKeyDown() then p:ReplayStep(dir, "sec", 0.05)
      else p:ReplayStep(dir, "sec", 0.25) end
    end)
  end
  self.lanes = lanes
  -- Zebra rows.
  self.zebra = {}
  for i = 1, #ROWS do
    local z = lanes:CreateTexture(nil, "BACKGROUND")
    z:SetPoint("TOPLEFT", lanes, "TOPLEFT", 0, -(i - 1) * ROW_H)
    z:SetPoint("TOPRIGHT", lanes, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    z:SetHeight(ROW_H)
    z:SetColorTexture(1, 1, 1, (i % 2 == 0) and Skin.ALPHA.zebra or 0)
    self.zebra[i] = z
  end
  -- The cursor: now (live) or the scrub position (replay).
  local cursor = lanes:CreateTexture(nil, "OVERLAY")
  cursor:SetWidth(1)
  Skin.Paint(cursor, "accent", 0.9)
  self.cursor = cursor
  -- The axis under the lanes: second ticks, labelled in fight seconds.
  local axis = CreateFrame("Frame", nil, f)
  axis:SetPoint("TOPLEFT", lanes, "BOTTOMLEFT", 0, 0)
  axis:SetPoint("TOPRIGHT", lanes, "BOTTOMRIGHT", 0, 0)
  axis:SetHeight(AXIS_H)
  self.axis = axis
  -- The replay transport (UI/PracticeTransport.lua, the stage's): a row at
  -- the foot while a stopped fight is scrubbed; the frame grows by it.
  local tr = Transport.New(f, TR_H, LABEL_INSET)
  tr:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  tr:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  self.transport = tr
  self._trOn = false
  -- The scenario picker: the catalog as a list under the name, a level
  -- above everything; the wheel scrolls it.
  local pick = CreateFrame("Frame", nil, f)
  pick:SetPoint("TOPLEFT", nameBtn, "BOTTOMLEFT", 0, -2)
  pick:SetWidth(PICK_W)
  pick:SetFrameLevel(f:GetFrameLevel() + 10)
  Skin.Surface(pick, "surface", "line")
  if pick.EnableMouseWheel then
    pick:EnableMouseWheel(true)
    pick:SetScript("OnMouseWheel", function(_, delta) View:ScrollPicker(delta > 0 and -3 or 3) end)
  end
  pick:Hide()
  self.pick = pick
  self.pickRows, self._pickItems, self._pickOff = {}, {}, 0
  -- Pools. Items are textures on the lanes; words, ticks and zone marks have
  -- their own. Nothing is allocated after the first paint that fills them.
  self.items, self.nItems = {}, 0
  self.words, self.nWords = {}, 0
  self.ticks, self.nTicks = {}, 0
  self.zoneMarks, self.nZones = {}, 0
  self.frame = f
  self._rowShown = {}
  self._nRows = 0
  self._tl, self._n, self._e = nil, -1, nil
  self:LayoutRows(false)
  f:Hide()
end

function View:OnEnable()
  self:RegisterMessage("NOCK_PRACTICE_RESET_POS", "ResetPos")
  -- A scenario pick can change which buffs are yours to pop.
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", function() View._palDirty = true end)
end

-- Where the lanes start: under the head, and under the buff row while it is up.
function View:Top() return HEAD_H + (self._palOn and PAL_ROW_H or 0) end

function View:ApplyTop()
  local top = self:Top()
  self.gutter:ClearAllPoints()
  self.gutter:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -top)
  self.lanes:ClearAllPoints()
  self.lanes:SetPoint("TOPLEFT", self.frame, "TOPLEFT", LABEL_W, -top)
  self.lanes:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -PAD, -top)
end

function View:ResetPos()
  local f = self.frame
  if not f then return end
  Nock.db.profile.practiceCombatLogPos = nil
  seatDefault(f)
end

function View:Head() return self.head end
function View:IsExpert() return self._expert and true or false end

-- Expert on/off (Workbench:Expert): Esc reaches the log while it is up.
function View:SetExpert(on)
  on = on and true or false
  if on == (self._expert or false) then return end
  self._expert = on
  local f = self.frame
  if on then
    if UISpecialFrames then
      local found = false
      for i = 1, #UISpecialFrames do if UISpecialFrames[i] == "NockPracticeCombatLog" then found = true end end
      if not found then tinsert(UISpecialFrames, "NockPracticeCombatLog") end
    end
    if f and not f:IsShown() then f:Show() end
    -- The head's chip, name and streak are painted by the practice panel on
    -- a change; make it paint them now, whatever it cached before the head
    -- was up.
    local pv = Nock:GetModule("PracticeView", true)
    if pv then pv._chipMode, pv._streak = nil, nil; if pv.Relayout then pv:Relayout() end end
  else
    if UISpecialFrames then
      for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "NockPracticeCombatLog" then table.remove(UISpecialFrames, i) end
      end
    end
    if f and f:IsShown() then View._hiding = true; f:Hide() end
    if self.pick then self.pick:Hide() end
  end
end

----------------------------------------------------------------------------
-- The scenario picker.
----------------------------------------------------------------------------

function View:PickRow(i)
  local r = self.pickRows[i]
  if not r then
    r = CreateFrame("Button", nil, self.pick)
    r:SetHeight(PICK_ROW_H)
    r:SetPoint("TOPLEFT", self.pick, "TOPLEFT", 0, -(i - 1) * PICK_ROW_H - 4)
    r:SetPoint("TOPRIGHT", self.pick, "TOPRIGHT", 0, -(i - 1) * PICK_ROW_H - 4)
    local hover = r:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints(r)
    Skin.Paint(hover, "raised", 1)
    hover:Hide()
    local bar = r:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    bar:SetWidth(2)
    Skin.Paint(bar, "accent", 1)
    bar:Hide()
    local fs = r:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("LEFT", r, "LEFT", 12, 0)
    fs:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    r.hover, r.bar, r.text = hover, bar, fs
    r:SetScript("OnEnter", function(b) if b.name then b.hover:Show() end end)
    r:SetScript("OnLeave", function(b) b.hover:Hide() end)
    r:SetScript("OnClick", function(b)
      if not b.name then return end
      local p = practice()
      -- SetScenario writes the profile and sends NOCK_PRACTICE_CHANGED (the
      -- panel repaints the name on every head).
      if p and p.SetScenario then p:SetScenario(b.name) end
      View:ShowPicker(false)
    end)
    self.pickRows[i] = r
  end
  return r
end

-- The catalog as one list: a header per group that has items, then its items.
function View:BuildPickItems()
  local items = self._pickItems
  for i = #items, 1, -1 do items[i] = nil end
  local p = practice()
  local cat = p and p.Catalog and p:Catalog()
  local groups = cat and cat.groups or {}
  for gi = 1, #groups do
    local g = groups[gi]
    if g.items and #g.items > 0 then
      items[#items + 1] = { header = g.title or g.key }
      for ii = 1, #g.items do items[#items + 1] = { name = g.items[ii].name } end
    end
  end
end

function View:PaintPicker()
  local items = self._pickItems
  local n = #items
  if self._pickOff > n - PICK_MAX then self._pickOff = n - PICK_MAX end
  if self._pickOff < 0 then self._pickOff = 0 end
  local p = practice()
  local current = (p and p.LadderDrillName and p:LadderDrillName()) or profile("practiceScenario", "Clean French")
  local shown = 0
  for i = 1, PICK_MAX do
    local it = items[i + self._pickOff]
    local r = self:PickRow(i)
    if it then
      shown = shown + 1
      r.name = it.name
      if it.header then
        Skin.Font(r.text, "mono", 9)
        r.text:SetText(string.upper(it.header))
        Skin.Text(r.text, "ink3")
        r.bar:Hide()
      else
        Skin.Font(r.text, "ui", Skin.SIZES.body)
        r.text:SetText(it.name)
        local on = (it.name == current)
        Skin.Text(r.text, on and "accent" or "ink")
        if on then r.bar:Show() else r.bar:Hide() end
      end
      r.hover:Hide()
      r:Show()
    else
      r:Hide()
    end
  end
  for i = PICK_MAX + 1, #self.pickRows do self.pickRows[i]:Hide() end
  self.pick:SetHeight(shown * PICK_ROW_H + 8)
end

function View:ShowPicker(on)
  local pick = self.pick
  if not pick then return end
  if on then
    self:BuildPickItems()
    self._pickOff = 0
    self:PaintPicker()
    pick:Show()
  else
    pick:Hide()
  end
end

-- Between fights only: the head's mouse is off during one anyway.
function View:TogglePicker()
  if Nock.state.sim.fightOn then return end
  self:ShowPicker(not self.pick:IsShown())
end

function View:ScrollPicker(d)
  self._pickOff = self._pickOff + d
  self:PaintPicker()
end

-- The efficiencies on the head: whole percents, the string written only when
-- one of them moves. Live during a fight (G.Live's counters), the scorecard's
-- after it, blank before the first fight.
function View:PaintEff(p, fightOn)
  local s
  if fightOn and p and p.LiveScore then s = p:LiveScore(self._live)
  elseif p then s = p.lastScore end
  local a = s and s.autoEff and math.floor(s.autoEff * 100 + 0.5) or nil
  local g = s and s.gcdEff and math.floor(s.gcdEff * 100 + 0.5) or nil
  if a == self._effA and g == self._effG then return end
  self._effA, self._effG = a, g
  if a or g then
    self.head.eff:SetText(("auto %s%% \194\183 gcd %s%%"):format(a and tostring(a) or "-", g and tostring(g) or "-"))
  else
    self.head.eff:SetText("")
  end
end

-- The frame's height: the head, the rows shown, the axis, and the
-- transport's row while it is up.
function View:ApplyHeight()
  local n = self._nRows or 0
  self.frame:SetHeight(self:Top() + n * ROW_H + AXIS_H + PAD + (self._trOn and TR_H or 0))
end

function View:WantShown()
  if not (Nock.state.sim and Nock.state.sim.active) then return false end
  return self._expert and true or false
end

-- Which rows this fight shows: the four always, CD when the fight has
-- cooldowns or procs (the plan's own row set, or a cd item on the stream) --
-- and once on, on for the fight (the sticky-row rule: a row never leaves).
function View:LayoutRows(cd)
  if cd == self._cd and self._nRows > 0 then return end
  self._cd = cd
  local n = 0
  for i = 1, #ROWS do
    local show = (ROWS[i].id ~= "procs") or cd
    self._rowShown[i] = show and (n + 1) or false
    if show then n = n + 1 end
    if show then self.rowLabels[i]:Show() else self.rowLabels[i]:Hide() end
  end
  -- Re-seat the labels and the zebra to the rows that are shown.
  for i = 1, #ROWS do
    local slot = self._rowShown[i]
    if slot then
      self.rowLabels[i]:ClearAllPoints()
      self.rowLabels[i]:SetPoint("LEFT", self.gutter, "TOPLEFT", LABEL_INSET, -(slot - 0.5) * ROW_H)
      self.zebra[i]:ClearAllPoints()
      self.zebra[i]:SetPoint("TOPLEFT", self.lanes, "TOPLEFT", 0, -(slot - 1) * ROW_H)
      self.zebra[i]:SetPoint("TOPRIGHT", self.lanes, "TOPRIGHT", 0, -(slot - 1) * ROW_H)
      self.zebra[i]:SetHeight(ROW_H)
      self.zebra[i]:Show()
    else
      self.zebra[i]:Hide()
    end
  end
  self._nRows = n
  self.lanes:SetHeight(n * ROW_H)
  self.gutter:SetHeight(n * ROW_H)
  self.cursor:ClearAllPoints()
  self.cursor:SetPoint("TOP", self.lanes, "TOPLEFT", 0, 0)
  self.cursor:SetHeight(n * ROW_H)
  self:ApplyHeight()
end

local function planHasCd(state)
  local pl = state.sim and state.sim.plan
  if not (pl and pl.rows and pl.nRows) then return false end
  for i = 1, pl.nRows do if pl.rows[i] == "cd" then return true end end
  return false
end

-- Pool access: the i-th item texture / word / tick / zone mark, made on demand.
function View:Item(i)
  local t = self.items[i]
  if not t then
    t = self.lanes:CreateTexture(nil, "ARTWORK")
    self.items[i] = t
  end
  return t
end

function View:Word(i)
  local fs = self.words[i]
  if not fs then
    fs = self.lanes:CreateFontString(nil, "OVERLAY")
    Skin.Font(fs, "mono", 9)
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    self.words[i] = fs
  end
  return fs
end

function View:Tick(i)
  local tk = self.ticks[i]
  if not tk then
    local line = self.lanes:CreateTexture(nil, "BORDER")
    line:SetWidth(1)
    line:SetColorTexture(1, 1, 1, 0.08)
    local fs = self.axis:CreateFontString(nil, "OVERLAY")
    Skin.Font(fs, "mono", 9)
    fs:SetJustifyH("CENTER"); fs:SetWordWrap(false)
    Skin.Text(fs, "ink3")
    tk = { line = line, text = fs }
    self.ticks[i] = tk
  end
  return tk
end

function View:Zone(i)
  local z = self.zoneMarks[i]
  if not z then
    local line = self.lanes:CreateTexture(nil, "ARTWORK")
    line:SetWidth(1)
    Skin.Paint(line, "ink2", 0.8)
    local fs = self.lanes:CreateFontString(nil, "OVERLAY")
    Skin.Font(fs, "mono", 9)
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    Skin.Text(fs, "ink2")
    z = { line = line, text = fs }
    self.zoneMarks[i] = z
  end
  return z
end

local function setWord(fs, s)
  if fs._word ~= s then fs._word = s; fs:SetText(s) end
end

-- One lane's items into the window [t0, t1] at pps, on row `slot`.
function View:PaintLane(lane, slot, t0, t1, pps, laneW)
  local y = -(slot - 1) * ROW_H - 3
  local h = ROW_H - 6
  local T = Nock.PracticeTimeline
  for i = 1, #lane do
    local it = lane[i]
    local a, b = it.t0, it.t1
    if b > t0 and a < t1 then
      if a < t0 then a = t0 end
      if b > t1 then b = t1 end
      local x = (a - t0) * pps
      local w = (b - a) * pps
      if w < 2 then w = 2 end
      if x + w > laneW then w = laneW - x end
      if w > 0 then
        self.nItems = self.nItems + 1
        local tex = self:Item(self.nItems)
        local c = T.COLORS[it.color] or T.COLORS[it.sym] or T.COLORS.g
        tex:SetColorTexture(c[1], c[2], c[3], it.open and 0.5 or 0.85)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", self.lanes, "TOPLEFT", x, y)
        tex:SetSize(w, h)
        tex:Show()
        local word = it.label or SYM_WORD[it.sym]
        if word and w >= MIN_LABEL_W then
          self.nWords = self.nWords + 1
          local fs = self:Word(self.nWords)
          setWord(fs, word)
          fs:ClearAllPoints()
          fs:SetPoint("LEFT", self.lanes, "TOPLEFT", x + 3, y - h / 2)
          fs:SetWidth(w - 4)
          Skin.Text(fs, (it.color == "bad") and "ink" or "accentInk")
          fs:Show()
        end
      end
    end
  end
end

function View:Paint(state, tl, e, t0, t1, cursor, fightT0)
  local lanes = self.lanes
  local laneW = lanes:GetWidth()
  -- Anchored to both edges, the lanes have no width until the first layout.
  if not laneW or laneW <= 0 then laneW = W - LABEL_W - PAD end
  local pps = laneW / SPAN
  self.nItems, self.nWords, self.nTicks, self.nZones = 0, 0, 0, 0
  if tl then
    for i = 1, #ROWS do
      local slot = self._rowShown[i]
      local lane = slot and tl.lanes[ROWS[i].id]
      if lane then self:PaintLane(lane, slot, t0, t1, pps, laneW) end
    end
    -- Zone marks on the MOVE row: a hairline and the one word.
    local slot = self._rowShown[ROW_IX.move]
    if slot and tl.zones then
      local y = -(slot - 1) * ROW_H
      for i = 1, #tl.zones do
        local z = tl.zones[i]
        if z.t >= t0 and z.t <= t1 then
          self.nZones = self.nZones + 1
          local zm = self:Zone(self.nZones)
          local x = (z.t - t0) * pps
          zm.line:ClearAllPoints()
          zm.line:SetPoint("TOP", lanes, "TOPLEFT", x, y)
          zm.line:SetHeight(ROW_H)
          zm.line:Show()
          setWord(zm.text, z.label)
          zm.text:ClearAllPoints()
          zm.text:SetPoint("LEFT", lanes, "TOPLEFT", x + 3, y - ROW_H / 2)
          zm.text:SetWidth(ZONE_LABEL_W)
          zm.text:Show()
        end
      end
    end
  end
  -- The stretch of movement still open at the cursor (live only).
  if e and e.movingSince and state.sim.fightOn and cursor > e.movingSince then
    local slot = self._rowShown[ROW_IX.move]
    if slot then
      local a = e.movingSince
      if a < t0 then a = t0 end
      local x, w = (a - t0) * pps, (cursor - a) * pps
      if w > laneW - x then w = laneW - x end
      if w > 0 then
        self.nItems = self.nItems + 1
        local tex = self:Item(self.nItems)
        local c = Nock.PracticeTimeline.COLORS.move
        tex:SetColorTexture(c[1], c[2], c[3], 0.5)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", lanes, "TOPLEFT", x, -(slot - 1) * ROW_H - 3)
        tex:SetSize(w, ROW_H - 6)
        tex:Show()
      end
    end
  end
  -- Second ticks, in fight seconds.
  if fightT0 then
    local k0 = math.ceil(t0 - fightT0)
    if k0 < 0 then k0 = 0 end
    local k1 = math.floor(t1 - fightT0)
    for k = k0, k1 do
      local x = (fightT0 + k - t0) * pps
      if x >= 0 and x <= laneW then
        self.nTicks = self.nTicks + 1
        local tk = self:Tick(self.nTicks)
        tk.line:ClearAllPoints()
        tk.line:SetPoint("TOP", lanes, "TOPLEFT", x, 0)
        tk.line:SetHeight(self._nRows * ROW_H)
        tk.line:Show()
        if tk._k ~= k then tk._k = k; tk.text:SetText(("%ds"):format(k)) end
        tk.text:ClearAllPoints()
        tk.text:SetPoint("TOP", self.axis, "TOPLEFT", x, -1)
        tk.text:Show()
      end
    end
  end
  -- The cursor.
  local cx = (cursor - t0) * pps
  if cx > laneW then cx = laneW end
  self.cursor:ClearAllPoints()
  self.cursor:SetPoint("TOP", lanes, "TOPLEFT", cx, 0)
  self.cursor:SetHeight(self._nRows * ROW_H)
  -- The rest of every pool goes dark.
  for i = self.nItems + 1, #self.items do self.items[i]:Hide() end
  for i = self.nWords + 1, #self.words do self.words[i]:Hide() end
  for i = self.nTicks + 1, #self.ticks do self.ticks[i].line:Hide(); self.ticks[i].text:Hide() end
  for i = self.nZones + 1, #self.zoneMarks do self.zoneMarks[i].line:Hide(); self.zoneMarks[i].text:Hide() end
end

function View:Refresh(state)
  local f = self.frame
  if not f then return end
  if not self:WantShown() then
    if f:IsShown() then View._hiding = true; f:Hide() end
    return
  end
  if not f:IsShown() then f:Show() end
  local p = practice()
  local e = p and p.engine
  local T = Nock.PracticeTimeline
  local now = GetTime()
  local fightOn = state.sim.fightOn
  -- The buff row: resolved on a pick and at a fight boundary (the engine's
  -- holds take over at the pull), painted per tick while it is up.
  if self._palDirty or fightOn ~= self._palFightOn then
    self._palDirty, self._palFightOn = false, fightOn
    local paper = (p and p.PaperDrill and p:PaperDrill()) or false
    local on = self.palette:Resolve(p, paper) > 0
    if on ~= self._palOn then
      self._palOn = on
      if on then self.palette.frame:Show() else self.palette.frame:Hide() end
      self:ApplyTop()
      self:ApplyHeight()
    end
  end
  if self._palOn then self.palette:Paint(p, now) end
  self:PaintEff(p, fightOn)
  -- The transport moves the replay clock BEFORE the window is placed on it.
  if self.transport then self.transport:Tick(p, now) end
  local rp = (not fightOn) and p and p._replay or nil
  -- A new fight (a new engine start) forgets the last one's rows and stream.
  local t0f = e and e.t0 or 0
  if t0f ~= self._t0f then self._t0f = t0f; self._n = -1; self._cd = nil; self._cdSeen = false end
  -- The WHOLE stream, live and in a replay alike (the log is the record; a
  -- scrub moves the window over it, it does not cut it). Rebuilt only when
  -- the event count moves.
  local n = e and e.n or 0
  if n ~= self._n or e ~= self._e then
    self._n, self._e = n, e
    self._tl = (e and n > 0) and T.Build(e.events, n, nil, nil, { windup = e.windup }) or nil
  end
  local tl = self._tl
  -- Rows: CD once the fight has cooldowns, and from then on.
  local cd = self._cdSeen or planHasCd(state) or (tl ~= nil and #tl.lanes.procs > 0)
  if cd then self._cdSeen = true end
  self:LayoutRows(cd)
  -- The window. Live: the span ending at now. Replay: the cursor a quarter in
  -- from the right, so what came right after is in view too.
  local cursor = rp and rp.at or now
  local t1 = rp and (cursor + SPAN * REPLAY_AHEAD) or cursor
  local fightT0 = (e and e.pulled and e.t0 > 0) and e.t0 or nil
  self:Paint(state, tl, e, t1 - SPAN, t1, cursor, fightT0)
  self.head:EnableMouse(not fightOn)
  -- The transport's row comes and goes with the replay; the picker never
  -- outlives the pull.
  local trOn = self.transport and self.transport:Paint(p, now) or false
  if trOn ~= self._trOn then self._trOn = trOn; self:ApplyHeight() end
  if fightOn and self.pick and self.pick:IsShown() then self.pick:Hide() end
end
