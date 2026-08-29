-- UI/Frame_ReactCorners.lua
-- React-mode corner status icons: the active aspect above the cluster's
-- top-left, Hunter's Mark above its top-right. Parity with the reference
-- WeakAura pack, which Nock otherwise reproduces in full.
--
-- The mark icon captions itself with the name of the hunter whose mark is up
-- (Modules/Auras.lua resolves it from the aura's caster unit).
--
-- Deliberately inert: no glow, no pulse, no alert state. Nock's Aspect warning
-- already nags about a missing Hawk, in combat only and at center screen, so
-- duplicating it here would be noise. Both icons ship OFF and the wizard marks
-- them NOT RECOMMENDED.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ReactCorners = Nock:NewModule("ReactCorners", "AceEvent-3.0")
local C = Nock.Constants

-- Reference geometry (Defaults.lua carries the same values, so these only
-- guard pre-DB reads).
local REF_SIZE, REF_X, REF_Y = 42, 30, 50

-- "No aspect" placeholder texture file ID, same one UI/Frame_Rotation.lua uses
-- when the Hawk spell texture can't be resolved.
local ASPECT_FALLBACK = 136116
-- Hunter's Mark ranks, max first (mirrors UI/Frame_Rotation.lua's HM_RANKS) --
-- a leveling hunter has no rank 5, so the ladder is walked until one resolves.
local HM_RANKS = { 27322, 14325, 14324, 14323, 1130 }
local HM_FALLBACK = 132212

-- Dual-form spell lookup (Frame_ReactBuffs.lua convention; Anniversary may
-- expose bare globals or C_Spell.*).
local function spellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then
    local t = C_Spell.GetSpellTexture(id); if t then return t end
  end
  if GetSpellTexture then local t = GetSpellTexture(id); if t then return t end end
  if GetSpellInfo then local _, _, ic = GetSpellInfo(id); if ic then return ic end end
  return nil
end

-- Caption cap for the mark icon's caster name. The slot is 42px by default and
-- its bottom line renders at ~11px, so roughly this many characters fit inside
-- the box; beyond that the name is cut rather than allowed to run out over the
-- cluster. Long enough that most TBC names survive intact.
local NAME_MAX = 10

local function shortName(name)
  if type(name) ~= "string" or name == "" then return nil end
  if #name <= NAME_MAX then return name end
  -- Byte-length truncation is safe here: WoW names on this client are ASCII
  -- letters, so a byte cut is a character cut.
  return name:sub(1, NAME_MAX)
end

local function profile()
  return (Nock.db and Nock.db.profile) or {}
end

local function num(key, ref)
  local v = tonumber(profile()[key])
  if v and v > 0 then return v end
  return ref
end

function ReactCorners:OnInitialize()
  -- Glued onto the React cluster (ReactBuffs / ReactCastBar convention):
  -- inherits reactScale, follows free-layout drags, vanishes with the cluster
  -- in classic mode. Not a LAYOUT row -- glued children contribute no height,
  -- so HUD:ApplyRowVisibility never sees them and Refresh gates itself.
  local cluster = Nock:GetModule("ReactCluster", true)
  local parent  = (cluster and cluster.frame) or Nock.parentFrame
  self._parent  = parent

  self.aspect = Nock.UI.CreateReactSlot(parent, "NockReactAspectIcon", REF_SIZE)
  self.mark   = Nock.UI.CreateReactSlot(parent, "NockReactMarkIcon",   REF_SIZE)

  -- One reused paint item per icon -- no per-tick allocation.
  self._aspectItem = { icon = nil, exp = 0, dur = 0, label = nil, desat = false }
  self._markItem   = { icon = nil, exp = 0, dur = 0, label = nil, desat = false, sub = nil }

  self:SetupMove(self.aspect, "reactAspectIconPos", "reactShowAspectIcon", "Aspect Icon")
  self:SetupMove(self.mark,   "reactMarkIconPos",   "reactShowMarkIcon",   "Hunter's Mark Icon")

  self:ApplyLayout()
  self:ApplyLock()
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyLayout")
  self:RegisterMessage("NOCK_LOCK_CHANGED",    "ApplyLock")
end

-- Cluster-relative screen capture (the cast bar's CaptureFreePos, but against
-- the CLUSTER instead of UIParent): after a drag the live anchor is wherever
-- StartMoving left it, so re-derive a stable BOTTOMLEFT-to-BOTTOMLEFT offset
-- from edge coordinates. Icon and cluster share an effective scale (child,
-- scale 1), so the subtraction is exact in SetPoint's offset space.
function ReactCorners:CaptureClusterPos(slot)
  local parent = self._parent
  if not (parent and slot:GetLeft() and parent:GetLeft()) then return nil end
  return { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT",
           x = slot:GetLeft() - parent:GetLeft(),
           y = slot:GetBottom() - parent:GetBottom() }
end

-- Drag + nudge-pad wiring for one icon (cast-bar pattern). The stored position
-- stays cluster-relative, so no `capture` override is needed for the pad: the
-- corner weld's own GetPoint() already reports against the cluster, which is
-- exactly the space set()/ApplyLayout re-anchor in.
function ReactCorners:SetupMove(slot, posKey, toggleKey, label)
  local view = self
  slot:SetMovable(true)
  slot:SetClampedToScreen(true)
  slot:RegisterForDrag("LeftButton")
  slot:EnableMouse(false)
  slot:SetScript("OnDragStart", function(s) s:StartMoving() end)
  slot:SetScript("OnDragStop", function(s)
    s:StopMovingOrSizing()
    local pos = view:CaptureClusterPos(s)
    if pos then Nock.db.profile[posKey] = pos end
    view:ApplyLayout()
  end)
  Nock.UI.RegisterNudgeable(slot, {
    label   = label,
    active  = function()
      local p = profile()
      return p.hudMode == "react" and p[toggleKey] == true
    end,
    get     = function() return Nock.db.profile[posKey] end,
    set     = function(pos)
      Nock.db.profile[posKey] = pos
      view:ApplyLayout()
    end,
    -- false re-welds the mirrored corner: that IS the icon's default position.
    default = function() return false end,
  })
end

-- Unlocked = draggable, with the slot border in the unlock green as the "you
-- can grab this" cue; locked = mouse-transparent so combat clicks pass through.
-- PaintReactSlot never touches the border, so the tint survives repaints.
function ReactCorners:ApplyLock()
  local editing = not Nock.IsLocked()
  self.aspect:EnableMouse(editing)
  self.mark:EnableMouse(editing)
  if editing then
    self.aspect:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
    self.mark:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  else
    self.aspect:SetBackdropBorderColor(0, 0, 0, 1)
    self.mark:SetBackdropBorderColor(0, 0, 0, 1)
  end
end

-- Spell textures resolve lazily: on a cold login the spellbook may not be
-- populated when OnInitialize runs, and a nil texture would cache as "no icon"
-- forever. Re-queried until one lands.
function ReactCorners:HawkIcon()
  if not self._hawkIcon then
    self._hawkIcon = spellIcon(C.SpellID.ASPECT_HAWK) or ASPECT_FALLBACK
  end
  return self._hawkIcon
end

function ReactCorners:MarkIcon()
  if not self._hmIcon then
    for i = 1, #HM_RANKS do
      local t = spellIcon(HM_RANKS[i])
      if t then self._hmIcon = t; break end
    end
    self._hmIcon = self._hmIcon or HM_FALLBACK
  end
  return self._hmIcon
end

-- Anchors are chosen so the two offset settings read literally: X is the gap
-- from the cluster's side edge to the icon's near edge, Y the gap from the
-- cluster's top edge to the icon's bottom edge. Mirrored, so one pair of
-- values drives both icons -- unless an icon carries a free position
-- (reactAspectIconPos / reactMarkIconPos, written by drag or nudge pad),
-- which anchors it to the cluster on its own and leaves the mirror behind.
local function storedPos(key)
  local pos = profile()[key]
  if type(pos) == "table" and pos.point then return pos end
  return nil
end

function ReactCorners:ApplyLayout()
  local size = num("reactCornerIconSize", REF_SIZE)
  local x    = num("reactCornerIconX",    REF_X)
  local y    = num("reactCornerIconY",    REF_Y)
  local parent = self._parent

  Nock.UI.SetReactSlotSize(self.aspect, size)
  self.aspect:ClearAllPoints()
  local posA = storedPos("reactAspectIconPos")
  if posA then
    self.aspect:SetPoint(posA.point, parent, posA.relPoint, posA.x, posA.y)
  else
    self.aspect:SetPoint("BOTTOMRIGHT", parent, "TOPLEFT", -x, y)
  end

  Nock.UI.SetReactSlotSize(self.mark, size)
  self.mark:ClearAllPoints()
  local posM = storedPos("reactMarkIconPos")
  if posM then
    self.mark:SetPoint(posM.point, parent, posM.relPoint, posM.x, posM.y)
  else
    self.mark:SetPoint("BOTTOMLEFT", parent, "TOPRIGHT", x, y)
  end

  -- A SetFont call clears nothing, so the paint caches have to be dropped by
  -- hand or the next Refresh diffs against pre-resize values and skips.
  local a, m = self.aspect, self.mark
  a._icon, a._desat, a._mode, a._label, a._tval, a._low = nil, nil, nil, nil, nil, nil
  m._icon, m._desat, m._mode, m._label, m._tval, m._low = nil, nil, nil, nil, nil, nil
end

-- Slow lane (Core:Tick). Both sources are event-driven (Modules/Auras.lua) and
-- the mark readout ticks in whole seconds, so 10 Hz costs nothing visible.
ReactCorners.refreshInterval = 0.1

function ReactCorners:Refresh(state)
  local p = Nock.db and Nock.db.profile
  local react = (p and p.hudMode == "react") or false

  -- Aspect: full colour for whatever is up, desaturated Hawk when none.
  -- exp/dur are forced to 0 -- an aspect is a steady aura and a countdown on it
  -- would be noise even if the client reported one.
  if react and p.reactShowAspectIcon == true then
    local a = state.player.aspect
    local it = self._aspectItem
    it.icon  = (a and a.icon) or self:HawkIcon()
    it.desat = (a == nil)
    Nock.UI.PaintReactSlot(self.aspect, it, 0)
    if not self.aspect:IsShown() then self.aspect:Show() end
  elseif self.aspect:IsShown() then
    self.aspect:Hide()
  end

  -- Hunter's Mark: colour + countdown when the target carries it, desaturated
  -- and textless when it doesn't. `fromPlayer` still doesn't gate the icon --
  -- another hunter's mark means the target is marked either way -- but the
  -- caster's name now rides along the bottom, which is the question that
  -- actually comes up with several hunters on one boss: whose mark is this, and
  -- is anyone going to refresh it.
  --
  -- A nil sourceName means the client wouldn't name the caster (out of group,
  -- out of range), NOT that nobody cast it, so the caption simply goes away and
  -- the icon reads exactly as it did before. Truncated to keep a long name from
  -- growing far past a 42px box; the countdown sits centred above it.
  if react and p.reactShowMarkIcon == true then
    local mk = state.target.huntersMark
    local it = self._markItem
    it.icon  = (mk and mk.icon) or self:MarkIcon()
    it.exp   = (mk and mk.expirationTime) or 0
    it.dur   = (mk and mk.duration) or 0
    it.desat = (mk == nil)
    it.sub   = mk and shortName(mk.sourceName) or nil
    Nock.UI.PaintReactSlot(self.mark, it, GetTime())
    if not self.mark:IsShown() then self.mark:Show() end
  elseif self.mark:IsShown() then
    self.mark:Hide()
  end
end
