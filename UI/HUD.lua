-- UI/HUD.lua
-- Top-level HUD parent: drag handle, position persistence, scale, lock state.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local HUD = Nock:NewModule("HUD", "AceEvent-3.0")
local C = Nock.Constants

function HUD:OnInitialize()
  self:BuildFrame()
  Nock.parentFrame = self.frame
  if not Nock.isHunter then
    self.frame:Hide()
    return
  end
  self:RegisterMessage("NOCK_LOCK_CHANGED", "OnLockChanged")
  self:RegisterMessage("NOCK_POSITION_RESET", "ApplyPosition")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyVisuals")
  self:RegisterMessage("NOCK_COMBAT_CHANGED", "ApplyCombat")
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "ApplyVisuals")   -- hideOoc yields to practice
  self:RegisterMessage("NOCK_HUD_RELAYOUT", "ApplyRowVisibility")  -- a row grew/shrank: re-stack only
end

-- The combat edge only moves two things: whether the box is hidden out of
-- combat and which opacity applies. It used to run the whole ApplyVisuals --
-- every registered font, bar texture, icon border and backdrop re-applied
-- (RefreshMedia, ~400 fresh backdrop tables and a SetFont on every text)
-- twice per pull. The shared tail below is what a combat flip needs.
function HUD:ApplyCombat()
  self:ApplyShown()
end

-- Master switch, hide-out-of-combat and opacity: the visibility tail of
-- ApplyVisuals. Returns true when the box is shown.
function HUD:ApplyShown()
  local p = Nock.db.profile
  -- Master switch. Checked before the preview override below: a user who has
  -- turned the HUD off is meant to see it stay off, including in the wizard —
  -- that absence IS the preview of their choice.
  if p.hudEnabled == false then
    self.frame:Hide()
    return false
  end

  local inCombat = Nock.state.player.inCombat
  -- demo.hudForceShow: the onboarding wizard previews the real HUD, so it must
  -- stay on screen even for a user who normally hides it out of combat.
  -- sim.active: practice mode drives the HUD out of combat by design (user,
  -- 2026-08-27) — the practice tick re-applies visuals when it flips.
  if Nock.HideOocApplies(p, inCombat, Nock.state) then
    self.frame:Hide()
    return false
  end
  self.frame:Show()

  local alpha
  if p.locked == false then
    alpha = 1.0
  elseif inCombat then
    alpha = p.opacity or 1.0
  else
    alpha = p.opacityOoc or 1.0
  end
  self.frame:SetAlpha(alpha)
  return true
end

function HUD:OnLockChanged()
  self:ApplyLock()
  self:ApplyVisuals()
end

-- Optional rows that can be toggled off via the settings UI. Map module name
-- → profile flag. When the flag is false the frame is hidden; HUD.LayoutChildren
-- already skips non-shown frames so the layout collapses around the gap.
local ROW_TOGGLES = {
  { moduleName = "CooldownsView",   flag = "showCooldowns"   },
  { moduleName = "InfoRow",         flag = "showInfoRow"     },
  { moduleName = "ManaBarView",     flag = "showManaBar"     },
  { moduleName = "RangeFinderView", flag = "showRangeFinder" },
}

function HUD:ApplyRowVisibility()
  local p = Nock.db and Nock.db.profile or {}
  for _, r in ipairs(ROW_TOGGLES) do
    local m = Nock:GetModule(r.moduleName, true)
    if m and m.frame then
      local on = p[r.flag]
      if on == nil then on = true end
      if on then m.frame:Show() else m.frame:Hide() end
    end
  end

  -- Rotation display mode. "bars" shows the scrolling ShotBars; by default it
  -- replaces the helper icon row, but "shotBarsShowHelper" keeps the icon row
  -- too (unified view — LAYOUT orders RotationView > ShotBars > SwingTimers, so
  -- icons sit above the bars, then the swing bar, then the weave indicator).
  -- "helper" (default) renders identically to before.
  local barsMode      = (p.rotationMode or "helper") == "bars"
  local showHelperToo = barsMode and (p.shotBarsShowHelper == true)
  local function setShown(name, shown)
    local m = Nock:GetModule(name, true)
    if m and m.frame then
      if shown then m.frame:Show() else m.frame:Hide() end
    end
  end
  -- showRotation is the master kill switch for the whole rotation display:
  -- the 6-icon helper row AND the Fluffy-style Shot Bars.
  local showRotation = (p.showRotation ~= false)
  setShown("ShotBars",     barsMode and showRotation)
  setShown("RotationView", ((not barsMode) or showHelperToo) and showRotation)
  -- Swing row collapses out of the grid only when BOTH bars are hidden (the GCD
  -- sweep is an adornment of the row and goes with it).
  local swingsOn = (p.showAutoShotBar ~= false) or (p.showMeleeBar ~= false)
  setShown("SwingTimers",  swingsOn)

  -- hudMode swap — runs LAST so it overrides everything above. React mode
  -- replaces the classic rows wholesale with the two React rows. While active,
  -- these profile keys are ignored: rotationMode, shotBars*, showGcdBar,
  -- swingFillDirection*, bar heights/colors/textures (LSM), showInfoRow,
  -- showRotation, and ALL classic show* element flags — React element
  -- visibility lives on its own reactShow* keys (React HUD tab; the cluster
  -- bars are consumed by ReactCluster:Geometry, the cast bar by
  -- ReactCastBar, the grid right below). Still honored: hideOoc, opacity*,
  -- backgroundEnabled, rowAlign and medallionEnabled. freeLayout is NOT —
  -- React always grids (see Nock.FreeLayoutActive): free placement would split
  -- the cluster/grid seam and scatter the React rows to stale UIParent spots.
  -- FluffyHUD replaces the classic rows the same way; its element visibility
  -- lives on the fluffyShow* keys (FluffyHUD tab; consumed by
  -- FluffyCluster:Geometry). Same honored/ignored key contract as React.
  local react  = Nock.HudIsReact()
  local fluffy = Nock.HudMode() == "fluffy"
  if react or fluffy then
    setShown("RotationView",    false)
    setShown("ShotBars",        false)
    setShown("SwingTimers",     false)
    setShown("ManaBarView",     false)
    setShown("RangeFinderView", false)
    setShown("CooldownsView",   false)
    setShown("InfoRow",         false)
  end
  setShown("ReactCluster",       react)
  setShown("ReactCooldownsView", react and (p.reactShowGrid ~= false))
  setShown("FluffyCluster",      fluffy)
  -- The fluffy CD row is the cluster's welded child (grows downward, no
  -- cascade height). Opt-in (ships OFF), hence == true rather than ~= false.
  setShown("FluffyCooldownsView", fluffy and p.fluffyShowGrid == true)

  self:LayoutChildren()
end

function HUD:ApplyVisuals()
  local p = Nock.db.profile
  self.frame:SetScale(p.scale or 1.0)
  if Nock.UI and Nock.UI.RefreshMedia then Nock.UI.RefreshMedia() end
  self:ApplyRowVisibility()
  if not self:ApplyShown() then return end
  self:ApplyBackground()
end

-- Paints the HUD backdrop box. Unlocked → always a grabbable box + green border
-- so it can be dragged, regardless of the user's background setting. Locked →
-- honour backgroundEnabled / backgroundColor / backgroundOpacity; disabled hides
-- both the fill and the border so it stops blocking vision.
function HUD:ApplyBackground()
  local p = Nock.db.profile
  local f = self.frame
  -- Box interactivity lives here — the one choke point both lock changes and
  -- visuals changes (incl. the free-placement toggle) repaint through.
  -- Draggable while unlocked, except in free placement, where the box is
  -- invisible and must not eat clicks meant for the world behind it.
  f:EnableMouse(not Nock.IsLocked() and not Nock.FreeLayoutActive())
  -- Rebuild the edge texture/size first (SetBackdrop resets colors, set below).
  Nock.UI.ApplyHudBackdrop(f)
  -- Keep the seamless glued panels (totem / pet status / repair) in sync.
  if Nock.UI.RefreshPanelBackgrounds then Nock.UI.RefreshPanelBackgrounds() end
  -- And the practice windows' own scale. A PROFILE SWITCH lands here, not on
  -- the Options setter: without this the floating stage (which re-reads the key
  -- from ApplyDock on NOCK_VISUALS_CHANGED) would follow the new profile while
  -- the other four windows kept the outgoing one's scale.
  if Nock.UI.RepairPracticeScale then Nock.UI.RepairPracticeScale() end
  if Nock.UI.ApplyPracticeScale then Nock.UI.ApplyPracticeScale() end
  -- Free placement: every piece (rows, side panels, cast bar) is its own
  -- draggable frame, so the box has nothing left to grip — hidden always. It
  -- still exists (invisible, mouse-off) as the glue anchor the side panels
  -- seed from and re-weld to when free placement ends.
  if Nock.FreeLayoutActive() then
    f:SetBackdropColor(0, 0, 0, 0)
    f:SetBackdropBorderColor(0, 0, 0, 0)
    return
  end
  if not Nock.IsLocked() then
    f:SetBackdropColor(unpack(C.COLORS.BG))
    f:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
    return
  end
  -- Background off, a cluster mode (fixed skin: bars/icons float with no box —
  -- backgroundEnabled is ignored), or the box is empty (every row hidden) →
  -- paint nothing, so a collapsed HUD doesn't leave a thin residual bar on
  -- screen. (Unlocked already returned above with a grabbable box.)
  if not Nock.HudIsClassic() or p.backgroundEnabled == false or self._hasVisibleRows == false then
    f:SetBackdropColor(0, 0, 0, 0)
    f:SetBackdropBorderColor(0, 0, 0, 0)
    return
  end
  local c = p.backgroundColor or { 0, 0, 0 }
  local a = p.backgroundOpacity
  if a == nil then a = 0.85 end
  f:SetBackdropColor(c[1] or 0, c[2] or 0, c[3] or 0, a)
  local bc = p.hudBorderColor or { 0, 0, 0 }
  local ba = p.hudBorderOpacity
  if ba == nil then ba = 1.0 end
  f:SetBackdropBorderColor(bc[1] or 0, bc[2] or 0, bc[3] or 0, ba)
end

function HUD:OnEnable()
  -- All modules' :OnInitialize have completed by now, so child frames exist
  -- and ApplyRowVisibility can Show/Hide them per the saved flags. Run the full
  -- ApplyVisuals (not just ApplyRowVisibility): the initial ApplyBackground in
  -- BuildFrame ran before the row frames existed, so it saw _hasVisibleRows=false
  -- and painted an empty (transparent) box. Now that LayoutChildren can count the
  -- real rows, repaint the backdrop so the saved backgroundEnabled state shows
  -- without needing a settings toggle to kick it.
  self:ApplyVisuals()
  -- Row modules' files load after this one, so GetModule returns nil during
  -- OnInitialize/BuildFrame — registration has to wait until here.
  self:RegisterRowNudgeables()
end

-- Cascading layout: each section declares its expected height, the next one
-- sits ROW_GAP below it. anchor controls horizontal alignment: "TOPLEFT"
-- (uses OUTER_PAD as x offset) or "TOP" (horizontally centred, x = 0).
-- height is the source of truth — frames should size themselves to match.
-- Warnings live as a separate UIParent-anchored frame and are not in this list.
local function rotationH()  return C.DIM.ROTATION_ICON end
local function shotBarsH()
  return (Nock.db and Nock.db.profile and Nock.db.profile.shotBarsHeight) or C.DIM.SHOT_BARS_H
end
local function swingsH()
  -- Source of truth lives in the SwingTimers module (:Geometry), so the grid row
  -- height can never drift from the actual container height.
  local m = Nock:GetModule("SwingTimers", true)
  if m and m.ContentHeight then return m:ContentHeight() end
  -- Fallback (module not yet initialized): mirror Geometry's default math.
  local p = Nock.db and Nock.db.profile or {}
  local h = (p.autoShotBarHeight or C.DIM.RANGED_BAR_H)
          + C.DIM.INNER_GAP
          + (p.meleeBarHeight or C.DIM.MELEE_BAR_H)
  if p.showGcdBar ~= false then
    h = h + (p.gcdBarHeight or C.DIM.GCD_BAR_H) + C.DIM.GCD_BAR_GAP
  end
  return h
end
local function manaBarH()
  return (Nock.db and Nock.db.profile and Nock.db.profile.manaBarHeight) or C.DIM.MANA_BAR_H
end
local function rangeFinderH()
  return (Nock.db and Nock.db.profile and Nock.db.profile.rangeFinderHeight) or C.DIM.RANGE_SQUARE_H
end
-- React-mode rows. Height lives in the modules' ContentHeight (same pattern as
-- swingsH); the GetModule guard keeps the grid working before the React frames
-- exist (Phase 0 ships the swap ahead of the views) — a hidden row never gets
-- measured, so the 1px fallback is only a safety net.
local function reactClusterH()
  local m = Nock:GetModule("ReactCluster", true)
  if m and m.ContentHeight then return m:ContentHeight() end
  return 1
end
local function reactCooldownsH()
  local m = Nock:GetModule("ReactCooldownsView", true)
  if m and m.ContentHeight then return m:ContentHeight() end
  return 1
end
local function fluffyClusterH()
  local m = Nock:GetModule("FluffyCluster", true)
  if m and m.ContentHeight then return m:ContentHeight() end
  return 1
end
local function cooldownsH()
  local m = Nock:GetModule("Cooldowns", true)
  local rows = (Nock.db and Nock.db.profile and Nock.db.profile.cooldownRows)
            or C.COOLDOWN_ROWS
  rows = math.max(1, math.floor(rows))
  local icon = (m and m.GetIconSize and m:GetIconSize()) or C.DIM.COOLDOWN_ICON
  return rows * icon + (rows - 1) * C.DIM.INNER_GAP
end

-- CastBar floats above the HUD as its own panel (see Frame_CastBar.lua) and
-- is NOT in the cascading layout. The HUD's size therefore doesn't change
-- when casting starts/stops; the cast bar pops in above with a small gap.
-- LayoutChildren skips hidden frames, so a row that isn't shown costs no space.
-- "helper" mode: ShotBars hidden → RotationView on top, then SwingTimers (as
-- before). "bars" mode: RotationView hidden (unless shotBarsShowHelper) →
-- ShotBars on top, then SwingTimers. "bars" + show-helper: RotationView icons
-- ABOVE ShotBars, then SwingTimers, then RangeFinder/Cooldowns/InfoRow.
local LAYOUT = {
  { module = "RotationView",    anchor = "TOP",     height = rotationH                                  },
  { module = "ShotBars",        anchor = "TOP",     height = shotBarsH                                  },
  { module = "SwingTimers",     anchor = "TOPLEFT", height = swingsH                                    },
  { module = "ReactCluster",    anchor = "TOP",     height = reactClusterH                              },
  { module = "FluffyCluster",   anchor = "TOP",     height = fluffyClusterH                             },
  { module = "ManaBarView",     anchor = "TOP",     height = manaBarH                                   },
  { module = "RangeFinderView", anchor = "TOP",     height = rangeFinderH                               },
  { module = "CooldownsView",   anchor = "TOP",     height = cooldownsH                                 },
  { module = "ReactCooldownsView", anchor = "TOP",  height = reactCooldownsH, gap = -1                  },
  { module = "InfoRow",         anchor = "TOPLEFT", height = function() return C.DIM.INFO_ROW_H     end },
}

-- Independent per-row scale. Multiplies on top of the global `scale` (which is
-- applied to the HUD frame itself). Rows not listed here stay at 1.0.
local ROW_SCALE_KEY = {
  RotationView    = "rotationScale",
  ShotBars        = "shotBarsScale",
  SwingTimers     = "swingScale",
  RangeFinderView = "rangeFinderScale",
  InfoRow         = "infoRowScale",
  -- Both React rows share one scale so the cluster and grid stay proportioned.
  ReactCluster       = "reactScale",
  ReactCooldownsView = "reactScale",
  -- The fluffy CD row is the cluster's welded child, so it inherits this.
  FluffyCluster      = "fluffyScale",
}

function HUD:RowScale(moduleName)
  local key = ROW_SCALE_KEY[moduleName]
  if not key then return 1.0 end
  local p = Nock.db and Nock.db.profile
  local v = p and p[key]
  if type(v) ~= "number" or v <= 0 then return 1.0 end
  return v
end

function HUD:LayoutChildren()
  -- Always hide any per-row edit borders unless the free-mode pass re-shows them,
  -- so toggling free off leaves no residue.
  if Nock.FreeLayoutActive() then
    return self:LayoutChildrenFree()
  end
  self:LayoutGridPass()
end

-- Cascading grid layout (the default). Bottom-up positioning: the HUD frame is
-- anchored by its BOTTOM (see Defaults), so making it taller grows the TOP edge
-- upward and the bottom (and every row anchored relative to bottom) stays put.
-- Hidden sections are skipped — they don't consume space.
--
-- Each row may carry an independent scale (see ROW_SCALE_KEY). A scaled child
-- reads its SetPoint offsets in its OWN scaled coordinate space, so the offsets
-- are divided by s to keep the on-screen gap in HUD-frame pixels; vertical space
-- is reserved as height*s; and we track the widest scaled row so the HUD box can
-- grow to contain it (it never shrinks below HUD_WIDTH).
function HUD:LayoutGridPass()
  local OUTER = C.DIM.OUTER_PAD
  local GAP   = C.DIM.ROW_GAP
  local p     = Nock.db and Nock.db.profile or {}
  -- Feature A: one alignment for every row. "left" hugs the left gutter; "center"
  -- (default) centres on the HUD's bottom mid-line.
  local left  = (p.rowAlign == "left")
  local point = left and "BOTTOMLEFT" or "BOTTOM"
  local baseX = left and OUTER or 0

  local y = OUTER
  local visible = 0
  local maxRowW = 0
  for i = #LAYOUT, 1, -1 do
    local entry = LAYOUT[i]
    local m = Nock:GetModule(entry.module, true)
    if m and m.frame and m.frame:IsShown() then
      local s = self:RowScale(entry.module)
      m.frame:SetScale(s)
      m.frame:EnableMouse(false)
      if m.frame._editBG then m.frame._editBG:Hide() end
      m.frame:ClearAllPoints()
      m.frame:SetPoint(point, self.frame, point, baseX / s, y / s)
      local h = (entry.height and entry.height()) or m.frame:GetHeight() or 0
      -- entry.gap overrides the spacing ABOVE this row (bottom-up walk) — the
      -- React grid overlaps the React cluster's border at -1 (one shared 1px
      -- seam, same packing as inside the cluster/grid) instead of the 4px
      -- ROW_GAP.
      y = y + h * s + (entry.gap or GAP)
      maxRowW = math.max(maxRowW, (m.frame:GetWidth() or 0) * s)
      visible = visible + 1
    end
  end
  if visible == 0 then y = OUTER + GAP end  -- avoid negative height
  -- Track emptiness so ApplyBackground can skip painting the box when there's
  -- nothing in it (e.g. "Hide all") — otherwise the collapsed box shows as a
  -- thin residual bar.
  self._hasVisibleRows = visible > 0
  -- HUD height = total content height; bottom anchor keeps screen position stable.
  local contentH = y - GAP + OUTER
  self.frame:SetHeight(contentH)
  -- Width grows to contain the widest scaled row, floored at the design width so
  -- scaling rows DOWN never shrinks the box (and glued panels keep their size).
  -- React mode floors at the (narrower) cluster width instead, so the box hugs
  -- the React stack; the glued side panels follow the edges automatically.
  local floorW = C.DIM.HUD_WIDTH
  if Nock.HudIsReact() then
    floorW = (tonumber(p.reactWidth) or 220) + 2 * OUTER
  elseif Nock.HudMode() == "fluffy" then
    floorW = (tonumber(p.fluffyWidth) or 320) + 2 * OUTER
  end
  self.frame:SetWidth(math.max(floorW, 2 * OUTER + maxRowW))
end

-- Wire a row frame for free-mode dragging (once). The row stays PARENTED to the
-- HUD frame (so it keeps inheriting scale/opacity/hide-out-of-combat) but is
-- anchored to UIParent at a saved position. A faint edit border (shown only while
-- unlocked in free mode) makes scattered rows findable.
function HUD:MakeRowDraggable(frame, moduleName)
  if not frame._editBG then
    local bg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bg:SetAllPoints(frame)
    bg:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    Nock.UI.ApplyBackdrop(bg)
    bg:SetBackdropColor(0, 0, 0, 0.25)
    bg:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
    bg:Hide()
    frame._editBG = bg
  end
  if frame._nockDragWired then return end
  frame._nockDragWired = true
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local pt, _, relPt, x, y = self:GetPoint()
    Nock.db.profile.elementPositions = Nock.db.profile.elementPositions or {}
    Nock.db.profile.elementPositions[moduleName] = { point = pt, relPoint = relPt, x = x, y = y }
  end)
end

-- Free-mode rows are nudgeable only in free layout: in grid mode the cascading
-- layout owns their position and would overwrite any nudge on the next relayout.
-- Reset clears the saved entry rather than restoring a default — elementPositions
-- starts empty, so LayoutChildrenFree's no-jump capture re-seeds it from a grid
-- pass, which is the only "default" a row has ever had.
-- The rows' names as the edit-mode tags and pad tooltips print them.
local ROW_LABEL = {
  RotationView       = "Rotation",
  ShotBars           = "Shot Bars",
  SwingTimers        = "Swing Timers",
  ReactCluster       = "React Cluster",
  ManaBarView        = "Mana Bar",
  RangeFinderView    = "Range Finder",
  CooldownsView      = "Cooldown Grid",
  ReactCooldownsView = "React Cooldown Grid",
  FluffyCluster      = "Fluffy Cluster",
  InfoRow            = "Info Row",
}

function HUD:RegisterRowNudgeables()
  for i = 1, #LAYOUT do
    local name = LAYOUT[i].module
    local m = Nock:GetModule(name, true)
    if m and m.frame then
      Nock.UI.RegisterNudgeable(m.frame, {
        label   = ROW_LABEL[name] or name,
        active  = function() return Nock.FreeLayoutActive() end,
        get     = function()
          local p = Nock.db.profile.elementPositions
          return p and p[name]
        end,
        set     = function(pos)
          local p = Nock.db.profile
          p.elementPositions = p.elementPositions or {}
          p.elementPositions[name] = pos
          m.frame:ClearAllPoints()
          m.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        end,
        default = function()
          local p = Nock.db.profile
          if p.elementPositions then p.elementPositions[name] = nil end
          HUD:LayoutChildrenFree()          -- re-seeds from a grid pass
          return p.elementPositions and p.elementPositions[name]
        end,
      })
    end
  end
end

local function captureFreePos(frame)
  if not frame:GetLeft() then return nil end
  return { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT",
           x = frame:GetLeft(), y = frame:GetBottom() }
end

-- Free placement: each visible row sits at its own saved position (anchored to
-- UIParent) and is individually draggable while the HUD is unlocked.
function HUD:LayoutChildrenFree()
  local p = Nock.db.profile
  p.elementPositions = p.elementPositions or {}

  -- No-jump first run: if any visible row has no saved position, run one grid pass
  -- so frames sit at known spots, then capture those as the starting free layout.
  local needCapture = false
  for i = 1, #LAYOUT do
    local m = Nock:GetModule(LAYOUT[i].module, true)
    if m and m.frame and m.frame:IsShown() and not p.elementPositions[LAYOUT[i].module] then
      needCapture = true
      break
    end
  end
  if needCapture then
    self:LayoutGridPass()
    for i = 1, #LAYOUT do
      local name = LAYOUT[i].module
      local m = Nock:GetModule(name, true)
      if m and m.frame and m.frame:IsShown() and not p.elementPositions[name] then
        local pos = captureFreePos(m.frame)
        if pos then p.elementPositions[name] = pos end
      end
    end
  end

  local editable = not Nock.IsLocked()
  for i = 1, #LAYOUT do
    local entry = LAYOUT[i]
    local m = Nock:GetModule(entry.module, true)
    if m and m.frame then
      if m.frame:IsShown() then
        m.frame:SetScale(self:RowScale(entry.module))
        self:MakeRowDraggable(m.frame, entry.module)
        m.frame:EnableMouse(editable)
        m.frame._editBG:SetShown(editable)
        local pos = p.elementPositions[entry.module]
        if pos then
          m.frame:ClearAllPoints()
          m.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        end
      elseif m.frame._editBG then
        m.frame._editBG:Hide()
      end
    end
  end

  -- The box no longer wraps the scattered rows; pin it to its design size so
  -- the side panels keep a stable edge to seed their first free position from
  -- and to re-weld to when free placement ends. (The react branch is only a
  -- belt: FreeLayoutActive is false in React mode, so this pass never runs
  -- there — but keep the width right if that ever changes.)
  if Nock.HudIsReact() then
    self.frame:SetWidth((tonumber(p.reactWidth) or 220) + 2 * C.DIM.OUTER_PAD)
  else
    self.frame:SetWidth(C.DIM.HUD_WIDTH)
  end
  self.frame:SetHeight(C.DIM.HUD_HEIGHT)
end

-- Flip the per-row edit state (mouse + border) on lock/unlock without a full
-- relayout. Only meaningful in free mode; grid mode keeps rows non-interactive.
function HUD:ApplyRowDragState()
  local editable = Nock.FreeLayoutActive() and not Nock.IsLocked()
  for i = 1, #LAYOUT do
    local m = Nock:GetModule(LAYOUT[i].module, true)
    if m and m.frame and m.frame._editBG then
      m.frame:EnableMouse(editable and m.frame:IsShown())
      m.frame._editBG:SetShown(editable and m.frame:IsShown())
    end
  end
  -- A row that hides while unlocked drops its pad; one that appears gains one.
  local em = Nock:GetModule("EditMode", true)
  if em then em:RefreshPads() end
end

function HUD:BuildFrame()
  local f = CreateFrame("Frame", "NockHUD", UIParent, "BackdropTemplate")
  f:SetSize(C.DIM.HUD_WIDTH, C.DIM.HUD_HEIGHT)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  Nock.UI.ApplyBackdrop(f)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    Nock.db.profile.position = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  self.frame = f
  Nock.UI.RegisterNudgeable(f, {
    label   = "HUD box",
    tagPoint = "TOPRIGHT",   -- the rows' tags take the top-left corners
    -- In free placement the box is hidden and every piece moves itself — a pad
    -- on the invisible box would nudge nothing the user can see.
    active  = function() return not Nock.FreeLayoutActive() end,
    get     = function() return Nock.db.profile.position end,
    set     = function(pos)
      Nock.db.profile.position = pos
      HUD:ApplyPosition()
    end,
    default = function() return Nock:GetDefaultPosition() end,
  })
  self:ApplyVisuals()
  self:ApplyPosition()
  self:ApplyLock()
end

function HUD:ApplyPosition()
  local p = Nock.db.profile.position
  self.frame:ClearAllPoints()
  self.frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
end

function HUD:ApplyLock()
  -- Box mouse state is owned by ApplyBackground (shared with visuals changes).
  self:ApplyBackground()
  self:ApplyRowDragState()
end
