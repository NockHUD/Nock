-- UI/Frame_Repair.lua
-- "Needs repair" strip. A HUD-matching panel glued seamlessly under the HUD's
-- bottom edge (its top border overlaps the HUD's bottom border into one line,
-- mirroring the totem/pet-status side panels — NOT in the cascading layout, so
-- it never shifts the other rows). A red durability bar sits inside it. Shown
-- only when state.repair.needed (Modules/Durability: in a shopping zone AND
-- below the durability threshold).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local RepairBar = Nock:NewModule("RepairBar")
local C = Nock.Constants

local RED       = { 0.80, 0.13, 0.13, 1 }
local TEXT_RGBA = { 1, 1, 1, 1 }

function RepairBar:OnInitialize()
  local parent  = Nock.parentFrame
  local OUTER   = C.DIM.OUTER_PAD
  local panelW  = C.DIM.HUD_WIDTH
  local barW    = panelW - 2 * OUTER
  local barH    = C.DIM.REPAIR_BAR_H
  local panelH  = barH + 2 * OUTER

  -- HUD-matching panel. y = +1 so its top border sits on the HUD's bottom
  -- border (one seamless line), exactly like the glued side panels. Anchored to
  -- BOTH bottom corners so it tracks a widened HUD (per-row scaling can grow the
  -- HUD past its design width) with no right-side seam.
  local panel = CreateFrame("Frame", "NockRepairPanel", parent, "BackdropTemplate")
  panel:SetSize(panelW, panelH)
  panel:SetPoint("TOPLEFT",  parent, "BOTTOMLEFT",  0, 1)
  panel:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, 1)
  Nock.UI.RegisterPanelBackground(panel)  -- follows the HUD background styling
  panel:Hide()

  -- Bar stretches with the panel (both sides anchored); its fill maxWidth is
  -- recomputed from the live width in Refresh so it tracks any HUD width.
  local bar = Nock.UI.CreateBar(panel, "NockRepairBar", barW, barH, RED)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT",  panel, "TOPLEFT",  OUTER, -OUTER)
  bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -OUTER, -OUTER)
  bar:SetHeight(barH)
  Nock.UI.SetBarFill(bar, 1)
  bar.text:SetTextColor(unpack(TEXT_RGBA))
  bar.text:SetText("")

  self.panel    = panel
  self.bar      = bar
  self._lastTxt = nil
  self._lastPct = -1
end

-- Glued spot: welded under the HUD's bottom edge by BOTH corners (tracks a
-- widened HUD). When freed, ClearAllPoints drops the two-point weld and the
-- panel falls back to its SetSize width (the design HUD_WIDTH), one point on
-- UIParent — same shape as the freed cast bar. Free-placement drag/nudge wiring
-- is the shared Nock.UI.EnsureFreePanel/ApplyFreePanelPosition pair.
local function repairGlue(panel)
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT",  Nock.parentFrame, "BOTTOMLEFT",  0, 1)
  panel:SetPoint("TOPRIGHT", Nock.parentFrame, "BOTTOMRIGHT", 0, 1)
end

function RepairBar:Refresh(state)
  -- Position pass first, before the visibility early-out, so leaving free mode
  -- re-glues the panel even while it's hidden.
  Nock.UI.EnsureFreePanel(self.panel, "Repair", "Repair Bar", repairGlue)
  Nock.UI.ApplyFreePanelPosition(self.panel, "Repair", repairGlue)

  local prof = Nock.db and Nock.db.profile
  local r = state.repair
  if not r or not r.needed then
    -- The strip is transient (only in shopping zones, below the durability
    -- threshold) and a hidden frame can't be dragged — while editing (free
    -- placement, unlocked, reminder enabled) hold it open as a full-bar preview.
    local editing = Nock.FreeLayoutActive() and not Nock.IsLocked()
                    and not (prof and prof.repairWarnEnabled == false)
    if editing then
      if self._lastPct ~= 100 then
        Nock.UI.SetBarFill(self.bar, 1)
        self.bar.text:SetText("REPAIR  100%")
        self._lastTxt = "REPAIR  100%"
        self._lastPct = 100
      end
      if not self.panel:IsShown() then self.panel:Show() end
      return
    end
    if self.panel:IsShown() then self.panel:Hide() end
    return
  end

  -- Track the live bar width (the panel — and so the bar — stretches with a
  -- widened HUD), so the fill texture spans the full stretched bar.
  local w = (self.bar:GetWidth() or 0) - 2
  if w > 0 and w ~= self.bar.maxWidth then
    self.bar.maxWidth = w
    self._lastPct = -1  -- force a fill re-apply at the new width
  end

  local pct = math.floor((r.pct or 100) + 0.5)
  if pct ~= self._lastPct then
    Nock.UI.SetBarFill(self.bar, math.max(0, math.min(1, (r.pct or 0) / 100)))
    local txt = ("REPAIR  %d%%"):format(pct)
    if txt ~= self._lastTxt then
      self.bar.text:SetText(txt)
      self._lastTxt = txt
    end
    self._lastPct = pct
  end

  if not self.panel:IsShown() then self.panel:Show() end
end
