-- UI/Frame_ReleaseBar.lua
-- EXPERIMENTAL weave-release timing bar: draws the Auto Shot reactivation retry
-- cost (Nock.ReleaseCost) as Aerthax's interval boxes, glued under the HUD in
-- both looks, visible while the weave key is held.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ReleaseBar = Nock:NewModule("ReleaseBarView", "AceEvent-3.0")
local C = Nock.Constants

-- Fraction of the bar width where swing-ready sits; the rest is the free zone's
-- runway. Fixed, not configurable — the bar reads by shape, not by scale.
local READY_FRAC = 0.76
-- Sub-boxes per retry interval. Five 0.1s steps is the literal Aerthax diagram.
local SUBS = 5
-- Texture pool cap: enough for a slow 3.5s+ swing (7 teeth) at 5 subs each.
local MAX_SEGS = 40
local MAX_NOTCHES = 8

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

-- Cost ramp inside one tooth, left (cheap) to right (about-to-cost-a-full-
-- pulse). Alphas rise with the price so the red end also reads at a glance.
local SEG_COLORS = {
  { 0.35, 0.75, 0.35, 0.35 },
  { 0.78, 0.75, 0.28, 0.42 },
  { 0.90, 0.60, 0.20, 0.48 },
  { 0.92, 0.40, 0.18, 0.55 },
  { 0.88, 0.18, 0.14, 0.65 },
}
local FREE_COLOR   = { 0.42, 0.83, 0.45, 0.30 }
local NOTCH_COLOR  = { 0.55, 0.95, 0.45, 1.00 }
local READY_COLOR  = { 0.75, 1.00, 0.80, 0.95 }
local REACT_BAR_BG = { 0.08, 0.08, 0.08, 0.90 }
local REACT_BORDER = { 0.00, 0.00, 0.00, 1.00 }

-- Did the !Auto Shot press actually register? Pure classifier for the chip on
-- the bar's left edge, priority-ordered (tested by Tests/release_arm_test.lua):
--   "firing" — the wind-up is running: the shot is committed, nothing clips it.
--   "armed"  — auto-repeat is on (START_AUTOREPEAT_SPELL): the press landed.
--   "melee"  — toggle off mid-hold: expected, /startattack switched you.
--   "off"    — toggle off, key up, in combat: the re-arm did NOT register and
--              the next cycle is about to be lost. The loud one.
--   nil      — out of combat with auto off: just standing around.
function ReleaseBar.ArmStatus(windup, repeating, keyHeld, inCombat)
  if windup then return "firing" end
  if repeating then return "armed" end
  if keyHeld then return "melee" end
  if inCombat then return "off" end
  return nil
end

-- Chip text + colour per status. OFF also blinks (see Refresh).
local ARM_STYLE = {
  firing = { "FIRING",   0.20, 1.00, 0.45 },
  armed  = { "AUTO ON",  0.45, 0.80, 0.45 },
  melee  = { "MELEE",    0.75, 0.75, 0.75 },
  off    = { "AUTO OFF", 1.00, 0.15, 0.15 },
}

function ReleaseBar:OnInitialize()
  local parent = Nock.parentFrame

  -- Glued to the HUD box's bottom edge (1px border overlap, the cast bar's
  -- seam convention mirrored downward), so it follows position/scale in both
  -- looks — the React rows live inside the same parent frame. It shares the
  -- edge with the repair bar, which only shows out of combat in city zones,
  -- so the two can't collide in practice.
  local panel = CreateFrame("Frame", "NockReleaseBar", parent, "BackdropTemplate")
  panel:SetPoint("TOPLEFT",  parent, "BOTTOMLEFT",  0, 1)
  panel:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, 1)
  panel:Hide()

  -- The time field, inset past the 1px border.
  local field = CreateFrame("Frame", nil, panel)
  field:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
  field:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 1)

  local function tex(color, layer)
    local t = field:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(WHITE8X8)
    t:SetVertexColor(unpack(color))
    t:Hide()
    return t
  end

  self.segs = {}
  for i = 1, MAX_SEGS do self.segs[i] = tex(SEG_COLORS[1]) end
  self.notches = {}
  for i = 1, MAX_NOTCHES do self.notches[i] = tex(NOTCH_COLOR, "OVERLAY") end
  self.freeZone = tex(FREE_COLOR)
  self.readyTick = tex(READY_COLOR, "OVERLAY")
  self.playhead = tex({ 1, 1, 1, 1 }, "OVERLAY")

  -- Cost readout: what releasing this instant costs, colour-coded like the
  -- Auto Shot delay figure so the two speak the same scale.
  local readout = field:CreateFontString(nil, "OVERLAY")
  readout:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  readout:SetPoint("RIGHT", field, "RIGHT", -3, 0)
  readout:SetText("")
  Nock.UI.RegisterFontString(readout, "SIZE_OVERLAY", "OUTLINE")
  self.readout = readout

  -- Arm-status chip: the "did my press register?" answer, left edge.
  local armText = field:CreateFontString(nil, "OVERLAY")
  armText:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  armText:SetPoint("LEFT", field, "LEFT", 3, 0)
  armText:SetText("")
  Nock.UI.RegisterFontString(armText, "SIZE_OVERLAY", "OUTLINE")
  self.armText = armText
  self._lastArm = nil

  self.frame = panel
  self.field = field
  self._lastReadout = nil
  self._geomKey = nil
  self._latchSwingStart = nil
  self._latchUntil = 0

  self:ApplyLayout()
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyLayout")
end

-- Panel chrome per look: the classic backdrop, or React's flat near-black.
-- Height comes from the shared releaseBarHeight either way.
function ReleaseBar:ApplyLayout()
  local p = (Nock.db and Nock.db.profile) or {}
  local h = tonumber(p.releaseBarHeight) or 14
  self.frame:SetHeight(h + 2)
  if not Nock.HudIsClassic() then
    Nock.UI.ApplyBackdrop(self.frame, REACT_BAR_BG, REACT_BORDER)
  else
    Nock.UI.ApplyBackdrop(self.frame)
  end
  self._geomKey = nil   -- height/skin moved; relayout the field next Refresh
end

-- (Re)position the static field — teeth, notches, free zone, ready tick — for
-- the current width/duration/latency. Only runs when one of those actually
-- moves (see the geometry key in Refresh); the per-tick path just slides the
-- playhead and updates the readout.
--
-- Axis: x(r) = readyX - r * pxPerSec for r seconds of swing remaining, with
-- ready pinned at READY_FRAC of the width. The whole cost field is shifted
-- toward ready by `lat`: a press reaches the server that much later, so the
-- free zone (and every notch) opens a ping early. That matches the producer,
-- which computes releaseCost at rem - latency.
function ReleaseBar:LayoutField(w, h, duration, lat, showNotches)
  local pulse = (C and C.RETRY_PULSE) or 0.5
  local readyX = w * READY_FRAC
  local pps = readyX / math.max(duration, 0.1)
  local function x(r) return readyX - r * pps end

  -- Free zone: from the latency-shifted ready boundary to the right edge.
  local freeX = math.max(0, x(lat))
  self.freeZone:ClearAllPoints()
  self.freeZone:SetPoint("TOPLEFT", self.field, "TOPLEFT", freeX, 0)
  self.freeZone:SetPoint("BOTTOMRIGHT", self.field, "BOTTOMRIGHT", 0, 0)
  self.freeZone:Show()

  -- Ready tick: where the bar fills (the un-shifted swing end) — the landmark
  -- the weaver already knows from the swing bar.
  self.readyTick:ClearAllPoints()
  self.readyTick:SetSize(2, h)
  self.readyTick:SetPoint("LEFT", self.field, "LEFT", readyX - 1, 0)
  self.readyTick:Show()

  -- Teeth: k-th interval spans r in [lat + (k-1)*pulse, lat + k*pulse], cost
  -- rising toward ready — so the sub-box ramp runs green on the left of each
  -- tooth to red against the notch/free boundary on its right.
  local si, ni = 0, 0
  local subW = (pulse / SUBS) * pps
  local k = 0
  while si < MAX_SEGS do
    k = k + 1
    local rRight = lat + (k - 1) * pulse
    local rLeft  = lat + k * pulse
    if x(rRight) <= 0 then break end
    for s = 1, SUBS do
      -- Sub-box s counts from the tooth's LEFT (cheap) end.
      local rr = rLeft - (s / SUBS) * pulse         -- sub-box right edge (as r)
      local xr = x(rr)
      local xl = math.max(0, xr - subW)
      if xr > 0 and si < MAX_SEGS then
        si = si + 1
        local t = self.segs[si]
        t:SetVertexColor(unpack(SEG_COLORS[s]))
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", self.field, "TOPLEFT", xl, 0)
        t:SetSize(math.max(0.5, xr - xl), h)
        t:Show()
      end
    end
    if showNotches and ni < MAX_NOTCHES then
      local nx = x(rLeft)
      if nx > 0 then
        ni = ni + 1
        local t = self.notches[ni]
        t:ClearAllPoints()
        t:SetSize(2, h)
        t:SetPoint("LEFT", self.field, "LEFT", nx - 1, 0)
        t:Show()
      end
    end
  end
  for i = si + 1, MAX_SEGS do self.segs[i]:Hide() end
  for i = ni + 1, MAX_NOTCHES do self.notches[i]:Hide() end

  self._pps, self._readyX = pps, readyX
end

-- Live only from the weave key going down until the reactivated auto actually
-- fires (or a short timeout): the release decision spans the whole hold AND
-- the moment after letting go, when the bar shows what the release cost.
function ReleaseBar:WantLive(state, now)
  local w = state.weave
  if w.keyHeld then
    self._latchSwingStart, self._latchUntil = nil, 0
    return true
  end
  if self._wasHeld then
    -- Falling edge: hold the bar open until this swing cycle ends (the next
    -- auto fires and swingStart moves) or 3s pass, whichever is first.
    self._latchSwingStart = state.ranged.swingStart
    self._latchUntil = now + 3
  end
  return self._latchSwingStart ~= nil
    and state.ranged.swingStart == self._latchSwingStart
    and now < self._latchUntil
end

function ReleaseBar:Refresh(state)
  local p = Nock.db and Nock.db.profile
  if not (p and p.releaseBarEnabled) then
    if self.frame:IsShown() then self.frame:Hide() end
    self._wasHeld = false
    return
  end

  local now = GetTime()
  local editing = not Nock.IsLocked()
  -- Always-mode (the verification default): the bar stays on screen whenever
  -- it is enabled. With no swing recharging, rem clamps to 0 — playhead at
  -- ready, cost +0.00, field dimmed — which is truthful (releasing now is
  -- free), unlike the React auto bar's stale-full lie that Nock.AutoSwingLive
  -- exists to prevent. swingDuration is seeded from UnitRangedDamage at login,
  -- so this only blanks for a hunter with no ranged weapon equipped.
  local live
  if p.releaseBarAlways ~= false then
    live = state.ranged.swingDuration > 0
  else
    live = self:WantLive(state, now)
  end
  self._wasHeld = state.weave.keyHeld

  -- Edit preview: the bar only exists mid-weave, so while unlocked hold it
  -- open on sample numbers — otherwise there is nothing to see while sizing
  -- it or picking its options.
  local duration, rem, lat, cost
  if live and state.ranged.swingDuration > 0 then
    duration = state.ranged.swingDuration
    rem      = (state.ranged.swingStart > 0) and state.ranged.swingRemaining or 0
    lat      = (state.network.latencyMs or 0) / 1000
    cost     = state.weave.releaseCost or 0
  elseif editing then
    duration, rem, lat = 3.0, 1.3, 0.05
    cost = Nock.ReleaseCost(rem - lat)
  else
    if self.frame:IsShown() then self.frame:Hide() end
    return
  end

  if not self.frame:IsShown() then self.frame:Show() end

  -- Rebuild the static field only when its inputs move: width (HUD resize),
  -- swing duration (haste), latency (5ms steps) or the notch toggle.
  local w = self.field:GetWidth() or 0
  local h = self.field:GetHeight() or 0
  if w <= 0 then return end
  local showNotches = p.releaseBarNotches ~= false
  local geomKey = string.format("%.0f:%.0f:%.2f:%.2f:%s",
    w, h, duration, lat, tostring(showNotches))
  if geomKey ~= self._geomKey then
    self:LayoutField(w, h, duration, lat, showNotches)
    self._geomKey = geomKey
  end

  -- Playhead sweep. Left of the field start it pins to 0 (long swings).
  local x = math.max(0, math.min(w - 1, self._readyX - rem * self._pps))
  self.playhead:ClearAllPoints()
  self.playhead:SetSize(2, h + 4)
  self.playhead:SetPoint("LEFT", self.field, "LEFT", x - 1, 0)
  self.playhead:Show()

  -- The field dims once a release is free — decision made, stop shouting.
  local free = cost <= 0.001
  if free ~= self._lastFree then
    self.field:SetAlpha(free and 0.45 or 1)
    self._lastFree = free
  end

  -- Arm-status chip. The one question the spammed re-arm key can't answer by
  -- itself: did the press register? FIRING/AUTO ON say yes, MELEE says "not
  -- yet, expected", a blinking AUTO OFF says the next cycle is being lost.
  local arm
  if live then
    arm = ReleaseBar.ArmStatus(state.player.autoShotCast ~= nil,
      state.ranged.repeating, state.weave.keyHeld, state.player.inCombat)
  elseif editing then
    arm = "armed"
  end
  if arm ~= self._lastArm then
    local s = arm and ARM_STYLE[arm]
    if s then
      self.armText:SetText(s[1])
      self.armText:SetTextColor(s[2], s[3], s[4])
      self.armText:Show()
    else
      self.armText:Hide()
    end
    self._lastArm = arm
  end
  -- Blink only the lost-cycle state; everything else sits still.
  if arm == "off" then
    self.armText:SetAlpha((math.floor(now * 4) % 2 == 0) and 1 or 0.25)
  elseif self.armText:GetAlpha() ~= 1 then
    self.armText:SetAlpha(1)
  end

  -- Cost readout, centisecond-diffed like the swing bar's delay figure.
  if p.releaseBarLabels ~= false then
    local centis = math.floor(cost * 100 + 0.5)
    if centis ~= self._lastReadout then
      self.readout:SetText(string.format("+%.2f", centis / 100))
      self.readout:SetTextColor(Nock.UI.DelaySeverityColor(centis / 100))
      self._lastReadout = centis
    end
    if not self.readout:IsShown() then self.readout:Show() end
  elseif self.readout:IsShown() then
    self.readout:Hide()
    self._lastReadout = nil
  end
end
