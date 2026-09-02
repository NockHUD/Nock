-- UI/Frame_EditList.lua
-- The edit-mode element list: a side palette naming every movable frame that
-- is on screen right now, one row each. Clicking a row selects that frame --
-- its nudge pad and outline appear -- so a frame buried under four others in
-- the middle of the HUD can be picked without grabbing it. The rows come from
-- Nock.UI.EditListRows (pure, UI/EditMode.lua); this file only draws.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("EditListView", "AceEvent-3.0")

local LIST_W, PAD = 176, 8
local TITLE_H = 36            -- title block above the rule
local TITLE_DY = -3           -- the display face sits high in its box (matches the bar)
local ROW_H, ROW_GAP = 22, 2

local function profile() return Nock.db and Nock.db.profile or {} end
local function Skin() return Nock.Skin end

function View:BuildPanel()
  if self.panel then return end
  local S = Skin()
  local f = CreateFrame("Frame", "NockEditList", UIParent, "BackdropTemplate")
  f:SetSize(LIST_W, TITLE_H + 1 + PAD * 2)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    profile().editListPos = { point = point, relPoint = relPoint or point, x = x or 0, y = y or 0 }
  end)
  if S then S.Surface(f, "surface", "line") else Nock.UI.ApplyBackdrop(f) end
  self.panel = f
  self.rows = {}

  local title = f:CreateFontString(nil, "OVERLAY")
  if S then S.Font(title, "display", S.SIZES.h2 or 20); S.Text(title, "ink") else title:SetFontObject(GameFontNormal) end
  title:SetPoint("LEFT", f, "TOPLEFT", PAD + 4, -TITLE_H / 2 + TITLE_DY)
  title:SetText("ELEMENTS")

  local rule = S and S.Rule(f, "lineSoft") or f:CreateTexture(nil, "ARTWORK")
  if not S then rule:SetColorTexture(0.10, 0.10, 0.10, 1) end
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -TITLE_H)
  rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -TITLE_H)
  rule:SetHeight(1)

  Nock.UI.RegisterNudgeable(f, {
    label  = "Element list",
    chrome = true,
    get    = function() return profile().editListPos end,
    set    = function(pos) profile().editListPos = pos; View:ApplyPanelPosition() end,
    reset  = function() profile().editListPos = false; View:ApplyPanelPosition() end,
  })
end

function View:ApplyPanelPosition()
  local f = self.panel
  if not f then return end
  local pos = profile().editListPos
  f:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    f:SetPoint("LEFT", UIParent, "LEFT", 16, 0)
  end
end

-- One row: a full-width Skin button with its label on the left.
local function buildRow(f, i)
  local S = Skin()
  local b
  if S then
    b = S.Button(f, "", "ghost", LIST_W - PAD * 2)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", b, "LEFT", 8, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.text:SetJustifyH("LEFT")
  else
    b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(LIST_W - PAD * 2, ROW_H)
    b.text = b:GetFontString()
  end
  b:SetHeight(ROW_H)
  b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(TITLE_H + 1 + PAD + (i - 1) * (ROW_H + ROW_GAP)))
  b:SetScript("OnClick", function(self)
    if self.frame and Nock.EditMode then Nock.EditMode:SelectByFrame(self.frame) end
  end)
  return b
end

function View:PaintRows()
  local S = Skin()
  local selected = Nock.EditMode and Nock.EditMode._selected
  local rows = Nock.UI.EditListRows(Nock.UI.GetNudgeables(), selected)
  local f = self.panel
  local base = f:GetFrameLevel()
  for i = 1, #rows do
    local r = rows[i]
    local b = self.rows[i]
    if not b then b = buildRow(f, i); self.rows[i] = b end
    b.frame = r.frame
    if S then
      S.SetButtonText(b, r.label, LIST_W - PAD * 2)
      S.ButtonKind(b, r.selected and "primary" or "ghost")
    else
      b:SetText(r.label)
    end
    b:SetFrameLevel(base + (r.selected and 3 or 2))
    b:Show()
  end
  for i = #rows + 1, #self.rows do
    self.rows[i].frame = nil
    self.rows[i]:Hide()
  end
  f:SetHeight(TITLE_H + 1 + PAD * 2 + math.max(0, #rows * (ROW_H + ROW_GAP) - ROW_GAP))
  return #rows
end

-- Frames come and go on their own schedule -- the unlock message reaches this
-- module before the HUD reacts to it, hideOoc rows show on the tick, a trap
-- row appears when its spell is learned -- so the list cannot be painted off
-- any one message. Every registered frame's OnShow / OnHide queues one
-- coalesced repaint for the next frame instead; that is the whole sync.
local function hookVisibility(frame)
  if not frame or frame._nockListHooked or not frame.HookScript then return end
  frame._nockListHooked = true
  frame:HookScript("OnShow", function() View:Queue() end)
  frame:HookScript("OnHide", function() View:Queue() end)
end

function View:Queue()
  if self._queued then return end
  self._queued = true
  C_Timer.After(0, function()
    View._queued = nil
    View:Apply()
  end)
end

function View:Apply()
  if Nock.IsLocked() then
    if self.panel then self.panel:Hide() end
    return
  end
  self:BuildPanel()
  self:ApplyPanelPosition()
  local entries = Nock.UI.GetNudgeables()
  for i = 1, #entries do hookVisibility(entries[i].frame) end
  local n = self:PaintRows()
  if n > 0 then self.panel:Show() else self.panel:Hide() end
end

-- Paint now and once more next frame, for the frames that flip on the same
-- message after this module has handled it.
function View:ApplyDeferred()
  self:Apply()
  self:Queue()
end

function View:OnEnable()
  self:RegisterMessage("NOCK_LOCK_CHANGED", "ApplyDeferred")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyDeferred")
  self:RegisterMessage("NOCK_NUDGEABLE_REGISTERED", "Queue")
  self:RegisterMessage("NOCK_EDIT_SELECTION", "Apply")
  self:RegisterMessage("NOCK_POSITION_RESET", "Apply")
  self:Apply()
end

Nock.UI.EditList = View
