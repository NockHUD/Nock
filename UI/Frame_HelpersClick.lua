-- UI/Frame_HelpersClick.lua
-- Click2Apply for the Helpers strip: a layer of invisible secure buttons that
-- sits over the badges and uses the badge's consumable on a press. Its own
-- frame on UIParent, never a child of the Helpers panel: a secure button
-- protects whatever parents or anchors it, and the panel must keep hiding
-- itself the instant combat starts. Everything here that touches a button
-- runs out of combat only; in combat a secure state driver hides the layer.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local HelpersClick = Nock:NewModule("HelpersClickView", "AceEvent-3.0")

local MAX_SLOTS = 12

local function inLockdown()
  return InCombatLockdown and InCombatLockdown()
end

local function clickEnabled()
  local p = Nock.db and Nock.db.profile
  return not (p and p.helpersClickToApply == false)
end

local KIND_LINE = {
  item   = "Click to use.",
  pet    = "Click to use on your pet.",
  weapon = "Click to apply to your main hand.",
  offhand = "Click to apply to your off hand.",
}

local function onEnter(btn)
  if not GameTooltip then return end
  local id = btn._itemId
  if not id then return end
  GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
  local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. id)
  if not ok then GameTooltip:SetText(btn._itemName or ("item " .. id)) end
  local kind = btn._kind
  if kind == "weapon" and btn._slot == 17 then kind = "offhand" end
  GameTooltip:AddLine(KIND_LINE[kind] or KIND_LINE.item, 0.8, 0.8, 0.8, true)
  GameTooltip:Show()
end

local function onLeave() if GameTooltip then GameTooltip:Hide() end end

function HelpersClick:OnInitialize()
  local layer = CreateFrame("Frame", "NockHelpersClick", UIParent)
  layer:SetFrameStrata("HIGH")
  layer:EnableMouse(false)
  layer:SetSize(1, 1)
  layer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  -- Defence in depth: the client hides the whole layer on combat entry. The
  -- per-button Hide below is the real gate (a shown layer with every button
  -- hidden clicks nothing).
  if RegisterStateDriver then
    RegisterStateDriver(layer, "visibility", "[combat] hide; show")
  end
  self.layer = layer

  self.buttons = {}
  for i = 1, MAX_SLOTS do
    local b = CreateFrame("Button", "NockHelpersClick" .. i, layer, "SecureActionButtonTemplate")
    -- Press only: a consumable with no cooldown would be used twice on a
    -- press-and-release registration (same as the Slammer button).
    b:RegisterForClicks("AnyDown")
    b:SetAttribute("useOnKeyDown", true)
    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", onLeave)
    b:Hide()
    b._itemId, b._kind, b._slot, b._itemName = nil, nil, nil, nil
    self.buttons[i] = b
  end

  self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegen")
  self:RegisterMessage("NOCK_LOCK_CHANGED", "MarkDirty")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "MarkDirty")
  self._dirty = true
end

function HelpersClick:MarkDirty() self._dirty = true end

function HelpersClick:OnRegen()
  self._dirty = true
  self:Refresh(Nock.state)
end

-- Sets the secure attributes for one row. Out of combat only (caller checks).
local function arm(b, row)
  local id, kind, slot = row.applyItem, row.applyKind, row.applySlot or 16
  if b._itemId == id and b._kind == kind and b._slot == slot then return end
  if kind == "pet" then
    b:SetAttribute("type", "macro")
    b:SetAttribute("item", nil)
    -- [target=pet] works on this client; [@pet] silently does not.
    b:SetAttribute("macrotext", "/use [target=pet] item:" .. id)
  elseif kind == "weapon" then
    b:SetAttribute("type", "macro")
    b:SetAttribute("item", nil)
    b:SetAttribute("macrotext", "/use item:" .. id .. "\n/use " .. slot)
  else
    b:SetAttribute("type", "item")
    b:SetAttribute("macrotext", nil)
    b:SetAttribute("item", "item:" .. id)
  end
  b._itemId, b._kind, b._slot = id, kind, slot
end

local function hideAll(buttons)
  for i = 1, MAX_SLOTS do
    if buttons[i]:IsShown() then buttons[i]:Hide() end
  end
end

function HelpersClick:Refresh(state)
  if inLockdown() then self._dirty = true; return end
  local view = Nock:GetModule("HelpersView", true)
  if not (view and view.Geometry) then return end

  local left, top, scale, shown = view:Geometry()
  local off = not shown or not left or not clickEnabled() or not Nock.IsLocked()
    or not Nock.isHunter
  if off then
    if self._armed then hideAll(self.buttons); self._armed = false end
    return
  end

  -- Mirror the panel: same scale, same top-left, so slot offsets line up.
  if scale ~= self._scale then self.layer:SetScale(scale); self._scale = scale end
  if left ~= self._left or top ~= self._top then
    self.layer:ClearAllPoints()
    self.layer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    self._left, self._top = left, top
  end

  local n = view:RowCount()
  local any = false
  for i = 1, MAX_SLOTS do
    local b = self.buttons[i]
    local row = (i <= n) and view:ClickableRow(i) or nil
    local x, y, size = nil, nil, nil
    if row then x, y, size = view:SlotOffset(i) end
    if row and x then
      arm(b, row)
      b._itemName = row.applyName
      if b._x ~= x or b._y ~= y or b._size ~= size then
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.layer, "TOPLEFT", x, y)
        b:SetSize(size, size)
        b._x, b._y, b._size = x, y, size
      end
      if not b:IsShown() then b:Show() end
      any = true
    elseif b:IsShown() then
      b:Hide()
    end
  end
  self._armed = any
  self._dirty = false
end
