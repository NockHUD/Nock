-- UI/EditMode.lua
-- Nudge pads: while unlocked, every registered frame gets a 4-way pad that
-- moves it a unit at a time, so positions can be set exactly instead of dragged.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local C = Nock.Constants
Nock.UI = Nock.UI or {}

local EditMode = Nock:NewModule("EditMode", "AceEvent-3.0", "AceTimer-3.0")

-- Up is +y and right is +x at every anchor point WoW uses, so one table covers
-- all seventeen frames — no per-frame direction mapping.
local DIRS = {
  up    = {  0,  1 },
  down  = {  0, -1 },
  left  = { -1,  0 },
  right = {  1,  0 },
}

-- Pure: given the stored position (or nil/false if never set) and the frame's
-- live position, return a NEW position table moved one step in `dir`. Never
-- mutates its inputs — the caller hands the result to spec.set, which owns the
-- write. Seeds from `live` when `stored` is absent or has no anchor point:
-- medallionPos starts `false` and free rows are unseeded until first layout, and
-- nudging from a missing table would teleport the frame to {0, 0}.
function Nock.UI.ComputeNudge(stored, live, dir, step)
  local d = DIRS[dir]
  if not d then return nil end
  local base = stored
  if type(base) ~= "table" or not base.point then base = live end
  return {
    point    = base.point,
    relPoint = base.relPoint or base.point,
    x        = (base.x or 0) + d[1] * step,
    y        = (base.y or 0) + d[2] * step,
  }
end

-- Registry. Ordered so pads build in a stable sequence; keyed by frame so a
-- module whose OnInitialize runs twice replaces its spec instead of duplicating.
local registry = {}   -- array of { frame = frame, spec = spec }

function Nock.UI.RegisterNudgeable(frame, spec)
  for i = 1, #registry do
    if registry[i].frame == frame then
      registry[i].spec = spec
      return
    end
  end
  registry[#registry + 1] = { frame = frame, spec = spec }

  -- Click-to-select. Every panel does EnableMouse(not locked), so OnMouseDown
  -- fires exactly while unlocked — the window where selecting means anything.
  -- Selecting on the DOWN edge (not a click/drag disambiguation) is deliberate:
  -- grabbing a frame to drag it should also bring up its pad.
  -- clickTarget covers the totem tracker, whose drag is caught by an overlay
  -- child, so clicks never reach the panel itself.
  local target = spec.clickTarget or frame
  if target and target.HookScript and not target._nockSelectHooked then
    target._nockSelectHooked = true
    target:HookScript("OnMouseDown", function()
      EditMode:SelectByFrame(frame)
    end)
  end
  -- Grid snapping rides on the drag the frame already implements: the hook
  -- runs AFTER the frame's own OnDragStop (which saved the free position and
  -- re-anchored), reads the live rect and re-writes through spec.set -- the
  -- one path the nudge pad uses too, so no frame needs snap code of its own.
  -- spec.dragTarget names the handle when it is not the frame (a title bar).
  local handle = spec.dragTarget or spec.clickTarget or frame
  if handle and handle.HookScript and not handle._nockSnapHooked then
    handle._nockSnapHooked = true
    handle:HookScript("OnDragStart", function() EditMode:OnDragBegin(frame) end)
    handle:HookScript("OnDragStop",  function() EditMode:OnDragEnd(frame) end)
  end
  -- The element list hooks and lists frames as they register; most register
  -- after its own OnEnable (TOC order), and a frame shown at creation fires
  -- no OnShow, so this is the only signal for them.
  if Nock.SendMessage then Nock:SendMessage("NOCK_NUDGEABLE_REGISTERED") end
end

-- ---------------------------------------------------------------------------
-- The grid (pure parts; UI/Frame_EditGrid.lua draws it)
-- ---------------------------------------------------------------------------
-- Line positions for a width x height screen, every `raster` units from the
-- CENTRE outward (so a centre cross always exists), edges excluded. Sorted.
function Nock.UI.GridLines(width, height, raster)
  local xs, ys = {}, {}
  if not raster or raster <= 0 then return xs, ys end
  local function fill(out, size)
    local c = size / 2
    out[#out + 1] = c
    local k = 1
    while c - k * raster > 0 do
      out[#out + 1] = c - k * raster
      out[#out + 1] = c + k * raster
      k = k + 1
    end
    table.sort(out)
  end
  fill(xs, width)
  fill(ys, height)
  return xs, ys
end

-- How far a frame's rect (left/right/top/bottom, UIParent units) must move to
-- sit on the grid: per axis the nearest of left / centre / right (top / centre
-- / bottom) to a grid line wins in "nearest" mode; "corner" snaps left and top
-- only. The grid is anchored on `origin` (the screen centre). Returns dx, dy.
local function toLine(v, raster, o)
  local k = math.floor((v - o) / raster + 0.5)
  return (o + k * raster) - v
end
function Nock.UI.SnapDelta(rect, raster, origin, mode)
  if not rect or not raster or raster <= 0 then return 0, 0 end
  local ox, oy = origin and origin.x or 0, origin and origin.y or 0
  local xc, yc
  if mode == "corner" then
    xc = { rect.left }
    yc = { rect.top }
  else
    xc = { rect.left, (rect.left + rect.right) / 2, rect.right }
    yc = { rect.top, (rect.top + rect.bottom) / 2, rect.bottom }
  end
  local function best(cands, o)
    local bd
    for _, v in ipairs(cands) do
      local d = toLine(v, raster, o)
      if bd == nil or math.abs(d) < math.abs(bd) then bd = d end
    end
    return bd or 0
  end
  return best(xc, ox), best(yc, oy)
end

-- profile.editGridSnap: "off" | "release" | "drag" (a legacy boolean = release).
function Nock.UI.EditSnapMode(p)
  local v = p and p.editGridSnap
  if v == true then return "release" end
  if v == "release" or v == "drag" then return v end
  return "off"
end

-- The nudge pad's step: one unit (ten with Shift), or one raster while
-- snapping -- a nudge then moves grid line to grid line.
function Nock.UI.EditNudgeStep(p, shift)
  local base = 1
  if Nock.UI.EditSnapMode(p) ~= "off" then
    local r = tonumber(p and p.editGridSize)
    if r and r > 0 then base = r end
  end
  return shift and base * 10 or base
end

-- A frame's rect in UIParent units (GetLeft & co. report in the frame's own
-- scale). nil when the frame has no rect yet.
function EditMode:FrameRect(frame)
  local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
  if not (l and r and t and b) then return nil, 1 end
  local es = (frame.GetEffectiveScale and frame:GetEffectiveScale() or 1)
           / (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1)
  return { left = l * es, right = r * es, top = t * es, bottom = b * es }, es
end

function EditMode:GridOrigin()
  return { x = (UIParent:GetWidth() or 0) / 2, y = (UIParent:GetHeight() or 0) / 2 }
end

-- The entry for a frame, if registered.
local function entryFor(frame)
  local reg = Nock.UI.GetNudgeables()
  for i = 1, #reg do if reg[i].frame == frame then return reg[i] end end
  return nil
end

function EditMode:OnDragBegin(frame)
  self._drag = entryFor(frame)
end

-- The snapped position for an entry, or nil when snapping is off / nothing to
-- do. Delta is computed in UIParent units and converted into the frame's own
-- offset units (SetPoint offsets are in the frame's scale).
function EditMode:SnappedPosition(entry)
  local p = Nock.db and Nock.db.profile or {}
  if Nock.UI.EditSnapMode(p) == "off" then return nil end
  local spec = entry.spec
  local rect, es = self:FrameRect(entry.frame)
  if not rect then return nil end
  local dx, dy = Nock.UI.SnapDelta(rect, tonumber(p.editGridSize) or 16, self:GridOrigin(), p.editSnapBy or "nearest")
  if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then return nil end
  local live = spec.capture and spec.capture() or self:CapturePosition(entry.frame)
  if not live then return nil end
  return {
    point = live.point, relPoint = live.relPoint or live.point,
    x = (live.x or 0) + dx / es, y = (live.y or 0) + dy / es,
  }, rect, dx, dy
end

function EditMode:OnDragEnd(frame)
  local entry = self._drag or entryFor(frame)
  self._drag = nil
  local grid = Nock.UI.EditGrid
  if grid then grid:SetGhost(nil) end
  if not entry then return end
  if entry.spec.secure and InCombatLockdown() then return end
  local pos = self:SnappedPosition(entry)
  if pos then entry.spec.set(pos) end
end

-- Called from the central tick while a drag is running: in "drag" mode the
-- ghost outline shows where the frame will land.
function EditMode:DragTick()
  local entry = self._drag
  if not entry then return end
  local grid = Nock.UI.EditGrid
  if not grid then return end
  local p = Nock.db and Nock.db.profile or {}
  if Nock.UI.EditSnapMode(p) ~= "drag" then grid:SetGhost(nil); return end
  local rect = self:FrameRect(entry.frame)
  if not rect then grid:SetGhost(nil); return end
  local dx, dy = Nock.UI.SnapDelta(rect, tonumber(p.editGridSize) or 16, self:GridOrigin(), p.editSnapBy or "nearest")
  grid:SetGhost({ left = rect.left + dx, right = rect.right + dx, top = rect.top + dy, bottom = rect.bottom + dy })
end

function Nock.UI.GetNudgeables()
  return registry
end

-- Pure: the rows the element list shows. One per registered frame that is on
-- screen and passes its own gate (spec.active), the edit-mode chrome (the bar,
-- the list itself: spec.chrome) left out, sorted by label. Each row is
-- { label, frame, selected }; a fresh list every call -- this runs on events,
-- never on the tick.
function Nock.UI.EditListRows(entries, selectedFrame)
  local rows = {}
  for i = 1, #entries do
    local e = entries[i]
    local spec = e.spec
    local shown = e.frame and e.frame.IsShown and e.frame:IsShown()
    local activeOk = (not spec.active) or (spec.active() and true or false)
    if shown and activeOk and not spec.chrome then
      rows[#rows + 1] = { label = spec.label or "?", frame = e.frame, selected = (e.frame == selectedFrame) }
    end
  end
  table.sort(rows, function(a, b) return a.label:lower() < b.label:lower() end)
  return rows
end

-- ---------------------------------------------------------------------------
-- The pad
-- ---------------------------------------------------------------------------
local PAD_SIZE   = 54    -- overall pad square
local BTN_SIZE   = 16    -- one arrow button
local PAD_GAP    = 4     -- gap between the target's right edge and the pad

-- A single arrow texture rotated four ways keeps the set consistent.
local ARROW_TEX = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local RESET_TEX = "Interface\\Buttons\\UI-RotationRight-Button-Up"

local REPEAT_DELAY = 0.4    -- press-and-hold before auto-repeat kicks in
local REPEAT_RATE  = 0.1    -- 10 nudges/sec while held

-- ChatFrameExpandArrow points RIGHT at rest, so rotation is measured from there.
local ROTATION = {
  right = 0,
  up    = math.pi / 2,
  left  = math.pi,
  down  = -math.pi / 2,
}

-- Where each button sits inside the pad square.
local BTN_POS = {
  up    = {   0,  BTN_SIZE },
  down  = {   0, -BTN_SIZE },
  left  = { -BTN_SIZE,   0 },
  right = {  BTN_SIZE,   0 },
}

-- ---------------------------------------------------------------------------
-- Selection — exactly one frame carries a pad at a time
-- ---------------------------------------------------------------------------
function EditMode:SelectByFrame(frame)
  if self._selected == frame then return end
  self._selected = frame
  self:RefreshPads()
  self:NotifySelection()
end

-- The element list mirrors the selection; it hears about changes here.
function EditMode:NotifySelection()
  if self.SendMessage then self:SendMessage("NOCK_EDIT_SELECTION") end
end

function EditMode:IsSelected(frame)
  return self._selected == frame
end

function EditMode:ClearSelection()
  if self._selected == nil then return end
  self._selected = nil
  self:RefreshPads()
  self:NotifySelection()
end

function EditMode:OnLockChanged()
  -- Relocking ends the editing session; unlocking starts a fresh one. Either
  -- way the old selection is stale, so drop it before rebuilding.
  self._selected = nil
  self:RefreshPads()
  self:NotifySelection()
end

function EditMode:CapturePosition(frame)
  local point, _, relPoint, x, y = frame:GetPoint()
  if not point then return nil end
  return { point = point, relPoint = relPoint or point, x = x or 0, y = y or 0 }
end

-- One nudge. The manager computes; spec.set writes the profile key AND
-- repositions, because the owning frame's ApplyPosition is the single place
-- allowed to move it.
function EditMode:Nudge(entry, dir, step)
  local spec = entry.spec
  -- The real combat guard. ApplyCombatState greys the buttons, but Disable()
  -- only reliably suppresses OnClick and these arrows fire on OnMouseDown, so
  -- the block has to live at the one place every nudge passes through.
  if spec.secure and InCombatLockdown() then return end
  -- spec.capture overrides GetPoint() for frames whose live anchor is not the
  -- one we want to seed from — a two-point weld to another frame reports its
  -- first point relative to THAT frame, which is meaningless against UIParent.
  local live = spec.capture and spec.capture() or self:CapturePosition(entry.frame)
  if not live then return end
  local pos = Nock.UI.ComputeNudge(spec.get(), live, dir, step)
  if pos then spec.set(pos) end
end

local function stepSize()
  if Nock.UI.EditNudgeStep then
    return Nock.UI.EditNudgeStep(Nock.db and Nock.db.profile, IsShiftKeyDown and IsShiftKeyDown())
  end
  return IsShiftKeyDown() and 10 or 1
end

-- Hold-to-repeat via AceTimer, never a per-frame OnUpdate (repo rule). The
-- modifier is read fresh in each tick via stepSize(), so a hold can be
-- accelerated to 10-unit steps mid-way by pressing shift.
function EditMode:StartRepeat(button, entry, dir)
  self:StopRepeat(button)
  button._delayTimer = self:ScheduleTimer(function()
    button._delayTimer = nil
    button._repeatTimer = self:ScheduleRepeatingTimer(function()
      if not button:IsShown() or not button:GetParent().entry then
        EditMode:StopRepeat(button)
        return
      end
      EditMode:Nudge(entry, dir, stepSize())
      EditMode:RefreshPadTooltip(button)
    end, REPEAT_RATE)
  end, REPEAT_DELAY)
end

function EditMode:StopRepeat(button)
  if button._delayTimer  then self:CancelTimer(button._delayTimer);  button._delayTimer  = nil end
  if button._repeatTimer then self:CancelTimer(button._repeatTimer); button._repeatTimer = nil end
end

function EditMode:ResetEntry(entry)
  if entry.spec.secure and InCombatLockdown() then return end
  local d = entry.spec.default()
  -- nil means the spec reset itself as a side effect and has nothing to write
  -- back — that is how a free-mode row resets, by clearing its elementPositions
  -- entry and letting the layout re-seed it. `false` is a real value (the
  -- medallion's "fall back to screen centre") and must reach set().
  if d == nil then return end
  if type(d) == "table" then
    -- Copy: default() may hand back the live Nock.Defaults table, and storing
    -- that by reference would let the next nudge mutate the defaults themselves.
    d = { point = d.point, relPoint = d.relPoint, x = d.x, y = d.y }
  end
  entry.spec.set(d)
end

-- The x/y readout is the alignment aid: two panels can be given matching
-- numbers by eye. It also confirms a nudge landed.
function EditMode:ShowPadTooltip(owner, entry)
  if not entry then return end
  local pos = entry.spec.get()
  if type(pos) ~= "table" or not pos.point then
    pos = self:CapturePosition(entry.frame) or { x = 0, y = 0 }
  end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(entry.spec.label, 1, 1, 1)
  GameTooltip:AddLine(("x: %.0f   y: %.0f"):format(pos.x or 0, pos.y or 0), 0.8, 0.8, 0.8)
  if entry.spec.secure and InCombatLockdown() then
    GameTooltip:AddLine("Can't be moved during combat.", 1, 0.3, 0.3)
  else
    GameTooltip:AddLine("Click 1  \194\183  Shift-click 10  \194\183  hold to repeat", 0.6, 0.6, 0.6)
  end
  GameTooltip:Show()
end

function EditMode:RefreshPadTooltip(owner)
  if GameTooltip:IsOwned(owner) then
    self:ShowPadTooltip(owner, owner:GetParent().entry)
  end
end

local function buildPad()
  local pad = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  pad:SetSize(PAD_SIZE, PAD_SIZE)
  pad:SetFrameStrata("DIALOG")
  Nock.UI.ApplyBackdrop(pad)
  pad:SetBackdropColor(0, 0, 0, 0.55)
  pad:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  pad.buttons = {}

  for dir, off in pairs(BTN_POS) do
    local b = CreateFrame("Button", nil, pad)
    b:SetSize(BTN_SIZE, BTN_SIZE)
    b:SetPoint("CENTER", pad, "CENTER", off[1], off[2])
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(b)
    tex:SetTexture(ARROW_TEX)
    tex:SetRotation(ROTATION[dir])
    b.icon = tex
    -- No RegisterForClicks: that governs OnClick, and these arrows drive off
    -- OnMouseDown/OnMouseUp so a hold can start repeating on press.
    b:SetScript("OnMouseDown", function(self)
      local e = self:GetParent().entry
      if not e then return end
      EditMode:Nudge(e, dir, stepSize())
      EditMode:StartRepeat(self, e, dir)
    end)
    b:SetScript("OnMouseUp",  function(self) EditMode:StopRepeat(self) end)
    b:SetScript("OnLeave",    function(self)
      EditMode:StopRepeat(self)
      GameTooltip:Hide()
    end)
    b:SetScript("OnEnter", function(self)
      EditMode:ShowPadTooltip(self, self:GetParent().entry)
    end)
    pad.buttons[dir] = b
  end

  local reset = CreateFrame("Button", nil, pad)
  reset:SetSize(BTN_SIZE, BTN_SIZE)
  reset:SetPoint("CENTER", pad, "CENTER", 0, 0)
  local rtex = reset:CreateTexture(nil, "ARTWORK")
  rtex:SetAllPoints(reset)
  rtex:SetTexture(RESET_TEX)
  reset.icon = rtex
  reset:SetScript("OnClick", function(self)
    local e = self:GetParent().entry
    if e then EditMode:ResetEntry(e) end
  end)
  reset:SetScript("OnEnter", function(self)
    local e = self:GetParent().entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.spec.label, 1, 1, 1)
    GameTooltip:AddLine("Reset to default position", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pad.reset = reset

  return pad
end

-- ---------------------------------------------------------------------------
-- Name tags
-- ---------------------------------------------------------------------------
-- While unlocked EVERY registered frame wears its name — not just the selected
-- one's pad — so a screenshot of an unlocked HUD says which panel is which
-- (user, 2026-08-27: stacked frames in other people's screenshots could not
-- be told apart). Each tag is a CHILD of its frame: it follows drags, scale
-- and show/hide with no repaint of its own, and costs nothing while locked
-- (hidden). spec.tagPoint picks the corner (default TOPLEFT; the HUD box uses
-- TOPRIGHT so its tag never sits on the first row's).
local TAG_FONT_SIZE = 9
local TAG_PAD_X, TAG_PAD_Y = 4, 3

local function buildTag(frame)
  local tag = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  tag:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
  Nock.UI.ApplyBackdrop(tag)
  tag:SetBackdropColor(0, 0, 0, 0.75)
  tag:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  tag:EnableMouse(false)
  local fs = tag:CreateFontString(nil, "OVERLAY")
  fs:SetFont(Nock.UI.GetFont(), TAG_FONT_SIZE, "OUTLINE")
  fs:SetPoint("CENTER")
  fs:SetTextColor(unpack(C.COLORS.BORDER_UNLOCK))
  tag.text = fs
  tag:Hide()
  return tag
end

-- Pure: a tag shows exactly while unlocked. (Frame visibility is the parent's
-- business — a hidden frame hides its tag with it.)
function Nock.UI.TagVisible(locked)
  return not locked
end

function EditMode:RefreshTags()
  local locked = Nock.IsLocked() and true or false
  local entries = Nock.UI.GetNudgeables()
  for i = 1, #entries do
    local e = entries[i]
    -- The edit-mode chrome (the bar, the element list) needs no name tag.
    if Nock.UI.TagVisible(locked) and not e.spec.chrome then
      if not e.tag then e.tag = buildTag(e.frame) end
      local label = e.spec.label or "?"
      if e.tag._label ~= label then
        e.tag._label = label
        e.tag.text:SetText(label)
        e.tag:SetSize((e.tag.text:GetStringWidth() or 0) + 2 * TAG_PAD_X, TAG_FONT_SIZE + 2 * TAG_PAD_Y)
      end
      local pt = e.spec.tagPoint or "TOPLEFT"
      if e.tag._tagPoint ~= pt then
        e.tag._tagPoint = pt
        e.tag:ClearAllPoints()
        e.tag:SetPoint(pt, e.frame, pt, pt:find("LEFT") and 1 or -1, -1)
      end
      if not e.tag:IsShown() then e.tag:Show() end
    elseif e.tag and e.tag:IsShown() then
      e.tag:Hide()
    end
  end
end

-- ---------------------------------------------------------------------------
-- Pad pool and lifecycle
-- ---------------------------------------------------------------------------
-- `activePads`, not `active` — `spec.active` is the visibility gate, and one
-- name for two unrelated things is how you end up reading the wrong one.
local pool, activePads = {}, {}   -- pool: spare pads; activePads: entry index -> pad

local function acquirePad()
  local pad = table.remove(pool)
  if not pad then pad = buildPad() end
  return pad
end

local function releasePad(pad)
  pad.entry = nil
  pad:Hide()
  pad:ClearAllPoints()
  pool[#pool + 1] = pad
end

-- A pad shows when: unlocked, the target is visible, the spec's own gate (if
-- any) passes, and the frame is the SELECTED one. The gate is what keeps
-- free-mode rows padless in grid mode, where the cascading layout would
-- overwrite any nudge on the next relayout. The selection term is what keeps
-- seventeen pads from burying the screen at once.
function Nock.UI.PadVisible(locked, shown, activeOk, isSelected)
  return (not locked) and shown and activeOk and isSelected
end

local function padWanted(entry)
  local activeOk = true
  if entry.spec.active then activeOk = entry.spec.active() and true or false end
  return Nock.UI.PadVisible(
    Nock.IsLocked() and true or false,
    entry.frame:IsShown() and true or false,
    activeOk,
    EditMode:IsSelected(entry.frame))
end

-- Dock to the target's right, flipping left when the pad would run off the
-- screen edge and clamping down when it would run off the top.
local function anchorPad(pad, frame)
  pad:ClearAllPoints()
  local right = frame:GetRight()
  local screenW = UIParent:GetRight() or 0
  if right and (right + PAD_GAP + PAD_SIZE) > screenW then
    pad:SetPoint("TOPRIGHT", frame, "TOPLEFT", -PAD_GAP, 0)
  else
    pad:SetPoint("TOPLEFT", frame, "TOPRIGHT", PAD_GAP, 0)
  end
end

function EditMode:RefreshPads()
  local entries = Nock.UI.GetNudgeables()
  for i = 1, #entries do
    local entry = entries[i]
    if padWanted(entry) then
      local pad = activePads[i]
      if not pad then
        pad = acquirePad()
        activePads[i] = pad
      end
      pad.entry = entry
      anchorPad(pad, entry.frame)
      pad:Show()
    elseif activePads[i] then
      releasePad(activePads[i])
      activePads[i] = nil
    end
  end
  self:RefreshTags()
  self:RefreshOutline()
  self:ApplyCombatState()
end

-- ---------------------------------------------------------------------------
-- The selection outline: one accent border on the selected frame's rect, so
-- a frame picked from the element list can be told apart from the ones it is
-- stacked with. Tooltip strata, mouse-transparent, anchored to the frame so it
-- follows drags and nudges for free. Nothing while locked or unselected.
-- ---------------------------------------------------------------------------
local OUTLINE_EDGE = 2

function EditMode:RefreshOutline()
  local frame = self._selected
  local wanted = frame and not Nock.IsLocked() and frame:IsShown()
  if not wanted then
    if self.outline and self.outline:IsShown() then self.outline:Hide() end
    return
  end
  local o = self.outline
  if not o then
    o = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    o:SetFrameStrata("TOOLTIP")
    o:EnableMouse(false)
    o:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = OUTLINE_EDGE })
    o:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
    self.outline = o
  end
  if o._for ~= frame then
    o._for = frame
    o:ClearAllPoints()
    o:SetPoint("TOPLEFT", frame, "TOPLEFT", -OUTLINE_EDGE, OUTLINE_EDGE)
    o:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", OUTLINE_EDGE, -OUTLINE_EDGE)
  end
  if not o:IsShown() then o:Show() end
end

-- Only `secure` specs are affected. Today that is Misdirect alone: it parents
-- secure click-cast rows, which makes the panel itself protected, so SetPoint on
-- it is a blocked action in combat. Its own ApplyPosition already defers via
-- _posDirty, but a nudge that silently does nothing reads as a broken button —
-- so grey the pad out and say why. Every other frame nudges normally in combat;
-- pads are plain UIParent children and are never protected.
function EditMode:ApplyCombatState()
  local inCombat = InCombatLockdown()
  local entries = Nock.UI.GetNudgeables()
  for i = 1, #entries do
    local pad = activePads[i]
    if pad and pad.entry then
      local blocked = pad.entry.spec.secure and inCombat
      for _, b in pairs(pad.buttons) do
        -- Enable()/Disable(), not SetEnabled — that is the idiom the rest of the
        -- addon uses (Frame_Mailbox.lua:30, Frame_Onboarding.lua:530).
        if blocked then b:Disable() else b:Enable() end
        b.icon:SetDesaturated(blocked)
        b.icon:SetAlpha(blocked and 0.4 or 1)
      end
      if blocked then pad.reset:Disable() else pad.reset:Enable() end
    end
  end
end

function EditMode:OnEnable()
  self:RegisterMessage("NOCK_LOCK_CHANGED", "OnLockChanged")
  -- A visuals change can flip a pad's gate without any lock change — the
  -- free-placement toggle (HUD box pad goes inert, row pads arm), a hudMode
  -- swap (rows hide), a row toggled off. Selection is kept; padWanted simply
  -- re-evaluates each spec's gates.
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "RefreshPads")
  self:RegisterEvent("PLAYER_REGEN_DISABLED", "ApplyCombatState")
  self:RegisterEvent("PLAYER_REGEN_ENABLED",  "ApplyCombatState")
  self:RefreshPads()
end

Nock.EditMode = EditMode
