-- UI/AceGUI_LSMDropdown.lua
-- Custom AceGUI widgets that add LSM previews to AceConfig dropdowns:
--   "Nock_LSM_Statusbar" — hover an item, a side panel shows the bar texture
--   "Nock_LSM_Font"      — each item's label is rendered in its own font face,
--                          so opening the list IS the preview
--
-- Both subclass AceGUI's standard Dropdown and override only the list-build
-- path. CRITICAL: AceGUI pools dropdown *items* in one shared pool across ALL
-- dropdowns. Mutating an item (custom font, hooked scripts) and letting it
-- return to the pool leaks that styling into unrelated dropdowns. So every
-- mutation here is undone before the items go back (on SetList rebuild and on
-- widget release), and the permanent HookScript hooks are gated by a per-item
-- flag that only this widget sets.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local AceGUI = LibStub("AceGUI-3.0", true)
local LSM = LibStub("LibSharedMedia-3.0", true)
if not AceGUI or not LSM then return end
Nock.UI = Nock.UI or {}   -- this file publishes onto it; don't depend on load order

local SAMPLE_TEXT = "AaBbCc 0123  The quick brown fox"

-- AceGUI's ItemBase.Create builds each dropdown item's label fontstring with
-- GameFontNormalSmall (see AceGUIWidget-DropDown-Items.lua). Restoring to that
-- exact object is what a pristine, never-styled item looks like — using any
-- other object leaves the list visibly inconsistent with stock dropdowns.
local DEFAULT_FONT_OBJECT = _G.GameFontNormalSmall

-- Lazy-built preview frame for the statusbar dropdown. GameTooltip:AddTexture
-- renders at ~14px which is too small for a bar texture to be recognisable, so
-- we use our own correctly-sized frame instead.
local barPreview
local function getBarPreview()
  if barPreview then return barPreview end
  local f = CreateFrame("Frame", "NockLSMBarPreview", UIParent, "BackdropTemplate")
  f:SetSize(240, 36)
  f:SetFrameStrata("TOOLTIP")
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:SetBackdropColor(0, 0, 0, 0.92)
  f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)

  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetHeight(14)
  f.tex:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  8,  6)
  f.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 6)

  f:Hide()
  barPreview = f
  return f
end

local function hideTip()
  if barPreview then barPreview:Hide() end
end

-- Only fires for items that currently belong to an active statusbar dropdown
-- (item._nockSB). A pooled item reused by another dropdown has _nockSB cleared,
-- so the leftover (un-removable) HookScript becomes a no-op.
local function showStatusbarTip(item)
  if not (item and item._nockSB and item.frame) then return end
  local name = item.userdata and item.userdata.value
  local path = name and LSM:Fetch("statusbar", name, true)
  if not path then hideTip(); return end
  local f = getBarPreview()
  f:ClearAllPoints()
  f:SetPoint("LEFT", item.frame, "RIGHT", 6, 0)
  f.label:SetText(name)
  f.tex:SetTexture(path)
  f:Show()
  f:Raise()
end

local function applyFontItem(item)
  local name = item and item.userdata and item.userdata.value
  local path = name and LSM:Fetch("font", name, true)
  if not path or not item.text then return end
  item.text:SetFont(path, 13, "")
  item.text:SetText(name .. "  —  " .. SAMPLE_TEXT)
end

-- CRITICAL: SetFontObject() alone does NOT clear a previously-applied explicit
-- SetFont(path,size,flags) on this client — the explicit font keeps winning, so
-- a recycled item still renders in the leaked LSM typeface. The reliable reset
-- is to re-apply an explicit SetFont using the default object's own font
-- params, then re-point the font object. (applyFontItem / LSM30_Font leak via
-- SetFont, and items never self-restore on acquire/release — see ItemBase.)
local function resetFontItem(item)
  local fs = item and item.text
  if not fs then return end
  local fo = DEFAULT_FONT_OBJECT
  if fo and fo.GetFont then
    local path, size, flags = fo:GetFont()
    if path and fs.SetFont then fs:SetFont(path, size or 12, flags or "") end
  end
  if fo and fs.SetFontObject then fs:SetFontObject(fo) end
end

----------------------------------------------------------------------------
-- Per-widget style / cleanup passes over the (live) pullout items.
----------------------------------------------------------------------------

local function styleFont(self)
  if not self.pullout then return end
  for _, item in self.pullout:IterateItems() do applyFontItem(item) end
end

local function cleanupFont(self)
  if not self.pullout then return end
  for _, item in self.pullout:IterateItems() do resetFontItem(item) end
end

local function styleStatusbar(self)
  if not self.pullout then return end
  for _, item in self.pullout:IterateItems() do
    if item then
      -- Force default font: a pooled item may arrive carrying a leaked LSM
      -- font from the Font dropdown (shared item pool). Non-font dropdowns
      -- must normalise on every build regardless of pool ordering.
      resetFontItem(item)
      item._nockSB = true
      if item.frame and not item._nockSBHooked then
        item._nockSBHooked = true   -- HookScript is permanent; hook once
        item.frame:HookScript("OnEnter", function() showStatusbarTip(item) end)
        item.frame:HookScript("OnLeave", hideTip)
      end
    end
  end
end

-- Plain wrapper: no preview at all, it exists ONLY to force item fonts back
-- to default on every build. Used by non-font selects that share a config
-- page with the Font dropdown (e.g. Icon border) so a recycled, font-styled
-- pooled item can never render with the wrong typeface.
local function stylePlain(self)
  if not self.pullout then return end
  for _, item in self.pullout:IterateItems() do resetFontItem(item) end
end

local function cleanupStatusbar(self)
  if self.pullout then
    for _, item in self.pullout:IterateItems() do
      if item then item._nockSB = false end
    end
  end
  hideTip()
end

----------------------------------------------------------------------------
-- Register the wrappers. Subclass Dropdown; wrap SetList (style after build,
-- cleaning the about-to-be-released old items first) and OnRelease (clean
-- before items return to the shared pool). Also dismiss the preview whenever
-- the pullout hides.
----------------------------------------------------------------------------

local function registerWrapper(typeName, afterSetList, cleanup)
  local Version = 2
  local function Constructor()
    local widget = AceGUI:Create("Dropdown")
    widget.type = typeName

    local origSetList = widget.SetList
    widget.SetList = function(self, list, order, itemType)
      cleanup(self)                      -- old items are released by origSetList
      origSetList(self, list, order, itemType)
      afterSetList(self)
    end

    local origOnRelease = widget.OnRelease
    widget.OnRelease = function(self)
      cleanup(self)                      -- restore BEFORE items go back to pool
      if origOnRelease then origOnRelease(self) end
    end

    -- Pullout can close without per-item OnLeave firing (click-to-select,
    -- click-away). Hooking its frame OnHide guarantees the preview is gone.
    local po = widget.pullout
    if po and po.frame and not po._nockHideHook then
      po._nockHideHook = true
      po.frame:HookScript("OnHide", hideTip)
    end

    return widget
  end
  AceGUI:RegisterWidgetType(typeName, Constructor, Version)
end

----------------------------------------------------------------------------
-- Which widget renders each media dropdown. SINGLE SOURCE OF TRUTH — both
-- Config/Options.lua (lsmWidget) and /nock diag resolve through here, so the
-- reported provider can never drift from the one actually used.
--
-- OUR OWN widgets come FIRST, deliberately. AceGUI-3.0-SharedMediaWidgets
-- (LSM30_*) is not embedded by Nock -- it exists only when some *other* addon
-- ships it (ElvUI is the common one), at whatever version that addon froze.
-- Copies from v11 to v13 are live in the wild, and the old ones call
-- SetBackdrop on a plain CreateFrame result, which no longer has that method
-- on this client: opening any LSM30_* dropdown throws. Worse, an error raised
-- while AceConfigDialog is building a control aborts its whole option loop, so
-- every setting BELOW the failing one silently never renders -- which is what
-- "the React tab goes blank after Bar texture" actually was.
--
-- The Nock_LSM_* wrappers above subclass the stock AceGUI Dropdown and ship
-- with the addon, so the worst case is a plain dropdown rather than a
-- truncated panel. LSM30_* is kept only as a last resort for the case where
-- this file itself failed to load.
----------------------------------------------------------------------------

local MEDIA_WIDGET_PREFERENCE = {
  statusbar = { "Nock_LSM_Statusbar", "LSM30_Statusbar" },
  font      = { "Nock_LSM_Font",      "LSM30_Font" },
  -- "plain" has no preview; it only normalises item fonts so a select on the
  -- same page as the Font dropdown can't inherit a leaked typeface.
  plain     = { "Nock_LSM_Plain" },
}

-- nil = no preview widget available; the caller leaves dialogControl unset and
-- AceConfigDialog falls back to its stock Dropdown.
function Nock.UI.PreferredMediaWidget(mediaType)
  if not AceGUI.WidgetRegistry then return nil end
  for _, name in ipairs(MEDIA_WIDGET_PREFERENCE[mediaType] or {}) do
    if AceGUI.WidgetRegistry[name] then return name end
  end
  return nil
end

registerWrapper("Nock_LSM_Statusbar", styleStatusbar, cleanupStatusbar)
registerWrapper("Nock_LSM_Font",      styleFont,      cleanupFont)
registerWrapper("Nock_LSM_Plain",     stylePlain,     stylePlain)

----------------------------------------------------------------------------
-- Diagnostic (/nock diag): which widget is actually rendering the media
-- dropdowns, and at what version.
--
-- Worth a slash command because the failure mode it exists for is SILENT: an
-- error thrown while AceConfigDialog builds a control aborts its option loop,
-- so every setting below the failing one simply never appears and the user
-- reports "the tab goes blank" with nothing else to go on. Knowing whether a
-- foreign LSM30_* (and which vintage) took over turns that into a one-line
-- answer. See LSM_WIDGET_PREFERENCE in Config/Options.lua for why ours win.
----------------------------------------------------------------------------

local PROBE_WIDGETS = {
  "Nock_LSM_Statusbar", "Nock_LSM_Font", "Nock_LSM_Plain",
  "LSM30_Statusbar", "LSM30_Font",
}

function Nock.UI.DumpMediaWidgets()
  local parts = {}
  for _, name in ipairs(PROBE_WIDGETS) do
    local ver = AceGUI.GetWidgetVersion and AceGUI:GetWidgetVersion(name)
    parts[#parts + 1] = ("%s=%s"):format(name, ver and tostring(ver) or "absent")
  end
  return table.concat(parts, "  ")
end

function Nock.UI.DumpMediaWidgetChoice()
  local parts = {}
  for _, mediaType in ipairs({ "statusbar", "font", "plain" }) do
    parts[#parts + 1] = ("%s -> %s"):format(
      mediaType, Nock.UI.PreferredMediaWidget(mediaType) or "none (plain AceGUI dropdown)")
  end
  return table.concat(parts, "  |  ")
end
