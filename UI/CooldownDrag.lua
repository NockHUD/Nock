-- UI/CooldownDrag.lua
-- Drag-to-reorder for cooldown tiles: press, lift past a threshold, a caret between tiles, drop or cancel; stepped by the central tick.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local D = { THRESHOLD = 4, pressed = false, active = false }
Nock.CooldownDrag = D

local SLACK = 40   -- a drop this far past a row's right edge still lands at its end
local DROP_PAD = 6 -- padding for DropSlot during Tick and Release

-- Pure: the row a cursor is over and the insertion index among its tiles.
function D.DropSlot(rows, x, y, pad)
  pad = pad or 0
  for _, row in ipairs(rows) do
    if y <= row.top + pad and y >= row.bottom - pad and x >= row.left - pad and x <= row.right + pad + SLACK then
      local ii = 1
      for _, t in ipairs(row.tiles) do
        if x > (t.l + t.r) / 2 then ii = ii + 1 end
      end
      return row.index, ii
    end
  end
  return nil
end

local ghost
local function ghostFrame()
  if ghost then return ghost end
  ghost = CreateFrame("Frame", nil, UIParent)
  ghost:SetFrameStrata("TOOLTIP")
  ghost:SetSize(32, 32)
  ghost.tex = ghost:CreateTexture(nil, "OVERLAY")
  ghost.tex:SetAllPoints(ghost)
  ghost:SetAlpha(0.85)
  ghost:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      D:Cancel()
      if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
    else
      if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end
  end)
  -- combat ends every drag
  ghost:RegisterEvent("PLAYER_REGEN_DISABLED")
  ghost:SetScript("OnEvent", function() D:Cancel() end)
  ghost:Hide()
  return ghost
end

local function finish()
  local host = D.host
  D.pressed, D.active, D.host, D.key = false, false, nil, nil
  if ghost then ghost:EnableKeyboard(false); ghost:Hide() end
  if host then host:DragCaret(nil) end
end

function D:Press(host, key)
  if InCombatLockdown and InCombatLockdown() then return end
  D.host, D.key = host, key
  D.x0, D.y0 = GetCursorPosition()
  D.pressed, D.active = true, false
  D.ri, D.ii = nil, nil
end

function D:Tick()
  if not D.pressed then return end
  if not IsMouseButtonDown("LeftButton") then D:Release(); return end
  local x, y = GetCursorPosition()
  if not D.active then
    if math.abs(x - D.x0) < D.THRESHOLD and math.abs(y - D.y0) < D.THRESHOLD then return end
    D.active = true
    local g = ghostFrame()
    g.tex:SetTexture(D.host:DragIcon(D.key))
    g:EnableKeyboard(true)
    g:Show()
  end
  local s = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
  ghost:ClearAllPoints()
  ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
  D.ri, D.ii = D.DropSlot(D.host:DragRows(), x, y, DROP_PAD)
  D.host:DragCaret(D.ri, D.ii)
end

function D:Release()
  if not D.pressed then return end
  local host, key = D.host, D.key
  if D.active then
    local x, y = GetCursorPosition()
    local ri, ii = D.DropSlot(host:DragRows(), x, y, DROP_PAD)
    finish()
    if ri then host:DragDrop(key, ri, ii) end
  else
    finish()
    host:TileClick(key)
  end
end

function D:Cancel()
  if D.pressed then finish() end
end
