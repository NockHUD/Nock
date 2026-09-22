-- Forever/AuraRow.lua
-- The client-drawn half of the Forever buff row: Blizzard's aura container
-- shows the player's own SHORT helpful auras (procs, cooldown buffs) with
-- their true countdowns, in combat too, without Nock ever reading an aura.
-- Proven 2026-09-23 (`/nock probe container`): a CustomAuraButtonTemplate
-- button draws nothing until it is handed regions, and everything it is
-- handed becomes secret-sticky, so the buttons are built here once and
-- never read back. The ledger (Forever/Buffs.lua) keeps what the container
-- cannot reach: buffs on the pet, and the happiness face.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local AuraRow = {}
Nock.ForeverAuraRow = AuraRow

-- Auras whose FULL duration is longer than this are noise on a HUD (aspects,
-- Shadowmeld, food, flasks, scrolls); any cap also hides permanent auras.
AuraRow.MAX_DURATION = 60
AuraRow.MAX_FRAMES   = 8
AuraRow.GROUP        = "short"
-- The pet line above the client row: Nock's own tiles (Mend, Feed, the
-- happiness face), smaller, centred by Nock since it knows their count.
AuraRow.PET_ICON = 20
AuraRow.LINE_GAP = 2

local SLOT_BG = { 0.08, 0.08, 0.08, 1 }

-- One button in the HUD's tile look: black 1 px edge, dark ground, the icon
-- inset one unit with the spell-icon crop, the countdown centred in the
-- React font. `time`/`label` are named so SetReactSlotSize can size the
-- fonts the way it does for the ledger tiles.
function AuraRow.Style(b, size)
  if b._nockStyled then return end
  b._nockStyled = true
  local edge = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  edge:SetAllPoints(b)
  edge:SetColorTexture(0, 0, 0, 1)
  local ground = b:CreateTexture(nil, "BACKGROUND")
  ground:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  ground:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  ground:SetColorTexture(SLOT_BG[1], SLOT_BG[2], SLOT_BG[3], SLOT_BG[4])
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local time = b:CreateFontString(nil, "OVERLAY")
  time:SetPoint("CENTER", b, "CENTER", 0, 0)
  local label = b:CreateFontString(nil, "OVERLAY")
  label:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
  b.time, b.label = time, label
  if Nock.UI and Nock.UI.SetReactSlotSize then Nock.UI.SetReactSlotSize(b, size) else b:SetSize(size, size) end
  b:SetIcon(icon)
  b:SetDurationText(time)
end

-- The container's width is a secret in combat, but the CLIENT places a frame
-- from its anchor and its own size: anchored by its bottom centre to the
-- row's bottom centre, the container centres itself. Set once. Nothing of
-- Nock's may anchor TO the container ("dependent object would inherit
-- forbidden aspects: UntrustedLayoutScriptExecution", 2026-09-23), so the
-- ledger tiles sit at the row's left edge instead; they meet the client's
-- tiles only with six or more of those up at once.
function AuraRow.Anchor(c, panel)
  if c._nockAnchored then return end
  c._nockAnchored = true
  c:ClearAllPoints()
  c:SetPoint("BOTTOM", panel, "BOTTOM", 0, 0)
end

-- Two lines: the client's row at the bottom, the pet line above it.
function AuraRow.LineHeight(rowIcon)
  return rowIcon + AuraRow.LINE_GAP + AuraRow.PET_ICON
end

-- x of tile `i` of `n` on a centred line of `w` units.
function AuraRow.TileX(i, n, size, gap, w)
  local totalW = n * size + (n - 1) * gap
  return (w - totalW) / 2 + (i - 1) * (size + gap)
end

function AuraRow.AnchorTile(slot, panel, x, y)
  slot:ClearAllPoints()
  slot:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x, y)
end

-- Build the container on `parent`. nil on a client without the template (the
-- row then shows the ledger alone). Every client call is guarded: a refusal
-- costs the row, never the HUD.
function AuraRow.Create(parent, size, gap)
  local okc, c = pcall(CreateFrame, "AuraContainer", "NockForeverAuraRow", parent, "CustomAuraContainerTemplate")
  if not okc or not c then return nil end
  local AU = _G.AnchorUtil or {}
  local axis = AU.FlowLayoutAxis or {}
  local dir  = AU.FlowDirection or {}
  local sort = _G.AuraContainerSortMethod or {}
  local sdir = _G.AuraContainerSortDirection or {}
  local ok2 = pcall(function()
    c:SetUnit("player")
    c:SetFlowLayoutAxis(axis.Horizontal or 0)
    c:SetFlowLayoutGrowthDirection(dir.Right or 1, dir.Down or -1)
    c:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
    c:AddAuraGroup(AuraRow.GROUP, "HELPFUL|PLAYER", {
      maxFrameCount = AuraRow.MAX_FRAMES,
      candidateFilters = { maxDuration = AuraRow.MAX_DURATION },
      sortMethod = sort.Expiration or 4,
      sortDirection = sdir.Normal or 0,
      initializeFrame = function(b) AuraRow.Style(b, size) end,
      layout = { elementWidth = size, elementHeight = size, elementSpacing = gap },
    })
    c:SetEnabled(true)
    c:Show()
  end)
  if not ok2 then
    c:Hide()
    return nil
  end
  -- Buttons the container built before the hook was known (none expected,
  -- belt and braces): style them too.
  pcall(function()
    for i = 1, AuraRow.MAX_FRAMES do
      local b = c:GetAuraGroupFrame(AuraRow.GROUP, i)
      if b then AuraRow.Style(b, size) end
    end
  end)
  return c
end
