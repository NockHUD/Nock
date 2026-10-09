-- UI/Frame_CooldownTiles.lua
-- HUD edit mode for the Forever React cooldown grid: an "Edit tiles" toggle, drag-to-reorder hotspots, a "+" per row with a catalog flyout, and a tile menu.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local T = { active = false, hot = {}, plus = {} }
Nock.CooldownTiles = T
LibStub("AceEvent-3.0"):Embed(T)

local PLUS_W = 20
local EMPTY_H = { 28, 24 }   -- a collapsed row's "+" height

-- Pure: a "+" slot for every def row; a row the view collapsed (no tiles) is
-- stacked under the last one drawn, so an emptied row can be refilled.
function T.PlusSlots(geomRows, nDefs)
  local byIndex, bottom = {}, 0
  for _, g in ipairs(geomRows) do
    byIndex[g.index] = g
    if g.y + g.h > bottom then bottom = g.y + g.h end
  end
  local out = {}
  for r = 1, nDefs do
    local g = byIndex[r]
    if g then
      out[#out + 1] = { row = r, y = g.y, h = g.h }
    else
      local y = (bottom > 0) and (bottom + 4) or 0
      out[#out + 1] = { row = r, y = y, h = EMPTY_H[r] or 24 }
      bottom = y + (EMPTY_H[r] or 24)
    end
  end
  return out
end

if not CreateFrame then return end   -- the pure part above is all a test loads

local Skin = Nock.Skin
local function view() return Nock:GetModule("ReactCooldownsView", true) end

-- PLAYER_REGEN_DISABLED fires BEFORE the client's lockdown actually starts,
-- so InCombatLockdown() is still false inside that handler -- reading it
-- alone let edit mode survive into combat. event == "PLAYER_REGEN_DISABLED"
-- covers that leading edge; InCombatLockdown()/UnitAffectingCombat cover
-- every other caller (Relayout, OpenFlyout, etc.) that has no event to pass.
local function inCombat(event)
  return event == "PLAYER_REGEN_DISABLED" or (InCombatLockdown and InCombatLockdown())
         or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end

local function canEdit(event)
  local v = view()
  return Nock.Flavor and Nock.Flavor.forever and not Nock.IsLocked() and not inCombat(event)
         and v and v.frame and v.frame:IsShown()
end

function T:Init()
  local v = view()
  if not v or self.toggle then return end
  local b = Skin.Button(UIParent, "Edit tiles", "ghost", 84, 22)
  b:SetFrameStrata("DIALOG")
  b:SetPoint("BOTTOMRIGHT", v.frame, "TOPRIGHT", 0, 4)
  b:SetScript("OnClick", function() T:SetActive(not T.active) end)
  b:Hide()
  self.toggle = b
  self.caret = v.frame:CreateTexture(nil, "OVERLAY", nil, 7)
  Skin.Paint(self.caret, "accent", 1); self.caret:SetWidth(2); self.caret:Hide()
  self:RegisterMessage("NOCK_LOCK_CHANGED", "Update")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "Relayout")
  self:RegisterMessage("NOCK_HUD_RELAYOUT", "Relayout")
  -- AceEvent/CallbackHandler calls a string-named handler as
  -- self:Method(event, ...) -- registering both under "Update" means the
  -- event name (crucially "PLAYER_REGEN_DISABLED") reaches canEdit() so it
  -- can catch the leading edge InCombatLockdown() misses (see inCombat above).
  self:RegisterEvent("PLAYER_REGEN_DISABLED", "Update")
  self:RegisterEvent("PLAYER_REGEN_ENABLED", "Update")
  -- The toggle's own visibility also depends on the grid being shown; the
  -- lock/combat/visuals messages don't fire when only the grid's Show/Hide
  -- changes (e.g. a HUD mode swap), so watch it directly.
  v.frame:HookScript("OnShow", function() T:Update() end)
  v.frame:HookScript("OnHide", function() T:Update() end)
  self:Update()
end

function T:Update(event)
  if not self.toggle then return end
  local canedit = canEdit(event)
  self.toggle:SetShown(canedit and true or false)
  if not canedit and self.active then self:SetActive(false) end
end

function T:SetActive(on)
  self.active = on and canEdit() and true or false
  Skin.ButtonKind(self.toggle, self.active and "primary" or "ghost")
  self.toggle.text:SetText(self.active and "Done" or "Edit tiles")
  if not self.active then
    if Nock.CooldownDrag.host == T then Nock.CooldownDrag:Cancel() end
    self:CloseFlyout(); self:CloseMenu()
  end
  self:Layout()
end

-- the view rebuilds on the same message; lay out one frame later
function T:Relayout()
  if self.active then C_Timer.After(0, function() T:Layout() end) end
end

local function hotspot(i)
  local h = T.hot[i]
  if h then return h end
  local v = view()
  h = CreateFrame("Button", nil, v.frame)
  h.ring = h:CreateTexture(nil, "OVERLAY"); h.ring:SetAllPoints(h); Skin.Paint(h.ring, "accent", 0.18)
  h:SetScript("OnMouseDown", function(self, btn) if btn == "LeftButton" and self.key then Nock.CooldownDrag:Press(T, self.key) end end)
  h:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" then Nock.CooldownDrag:Release() end end)
  T.hot[i] = h
  return h
end

function T:Layout()
  local v = view()
  for _, h in ipairs(self.hot) do h:Hide(); h.key = nil end
  for _, p in ipairs(self.plus) do p:Hide() end
  if not (self.active and v) then return end
  self.vis = { {}, {} }
  local i = 0
  for _, slot in ipairs(v._pool) do
    if slot._entry and slot:IsShown() then
      i = i + 1
      local h = hotspot(i)
      h.key, h.row = slot._entry.key, slot._row
      h:SetAllPoints(slot)
      h:SetFrameLevel(slot:GetFrameLevel() + 10)
      h:Show()
      local vr = self.vis[slot._row]
      if vr then vr[#vr + 1] = h end
    end
  end
  local geom = v:RowsGeometry()
  for n, s in ipairs(T.PlusSlots(geom, 2)) do
    local p = self.plus[n]
    if not p then
      p = Skin.Button(v.frame, "+", "ghost", PLUS_W, 20)
      self.plus[n] = p
    end
    p:SetHeight(s.h)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", v.frame, "TOPRIGHT", 4, -s.y)
    p:SetFrameLevel(v.frame:GetFrameLevel() + 12)
    p:SetScript("OnClick", function(self) T:OpenFlyout(s.row, self) end)
    p:Show()
  end
end

-- CooldownDrag host
function T:DragRows()
  local out = {}
  for r = 1, 2 do
    local hs = self.vis and self.vis[r] or {}
    local p = self.plus[r]
    if p and p:IsShown() then
      local s = p:GetEffectiveScale()
      local row = { index = r, top = p:GetTop() * s, bottom = p:GetBottom() * s, right = p:GetRight() * s, tiles = {} }
      row.left = (hs[1] and hs[1]:GetLeft() or p:GetLeft()) * s
      for i, h in ipairs(hs) do row.tiles[i] = { l = h:GetLeft() * s, r = h:GetRight() * s, key = h.key } end
      out[#out + 1] = row
    end
  end
  return out
end

function T:DragCaret(ri, ii)
  if not ri then self.caret:Hide(); return end
  local hs = self.vis[ri] or {}
  -- Never anchor on a hidden spare hotspot: past the last visible tile always
  -- means the row's own + button.
  local anchor = (ii <= #hs and hs[ii]) or self.plus[ri]
  if not anchor then self.caret:Hide(); return end
  self.caret:ClearAllPoints()
  self.caret:SetPoint("TOP", anchor, "TOPLEFT", -1, 1)
  self.caret:SetHeight(anchor:GetHeight() + 2)
  self.caret:Show()
end

function T:DragDrop(key, ri, ii)
  local E, rows = Nock.CooldownEditor, Nock.CooldownRows.Get()
  local visKeys = {}
  for i, h in ipairs(self.vis[ri] or {}) do visKeys[i] = h.key end
  Nock.CooldownRows.Set(E.Move(rows, key, ri, E.VisibleToSaved(rows[ri], visKeys, ii)))
end

function T:DragIcon(key)
  local s = Nock.state.cooldowns[key]
  return (s and s.icon) or 134400
end

-- Tile menu
local function visibleIndexOf(vis, key)
  for i, k in ipairs(vis) do if k == key then return i end end
  return nil
end

function T:TileClick(key)
  self:CloseFlyout()
  local m = self.menu
  if not m then
    m = CreateFrame("Frame", "NockCooldownTileMenu", UIParent, "BackdropTemplate")
    m:SetFrameStrata("DIALOG"); m:SetSize(160, 4 * 26 + 12)
    Nock.UI.ApplyBackdrop(m, { 0.04, 0.04, 0.04, 0.96 }, { 0.15, 0.15, 0.15, 1 })
    m.btns = {}
    local E = Nock.CooldownEditor
    -- Move left/right step by VISIBLE position: a hidden other-race racial
    -- can sit between two visible tiles in the saved row, so stepping by the
    -- saved index would sometimes skip nothing at all. T.vis holds hotspot
    -- BUTTONS for the row being edited right now, so read the keys off it
    -- rather than off the saved row.
    local function visKeysOf(ri)
      local out, hs = {}, T.vis and T.vis[ri]
      for i, h in ipairs(hs or {}) do out[i] = h.key end
      return out
    end
    local acts = {
      { "Move left", function(k, rows)
          local ri = E.Find(rows, k)
          local vis = ri and visKeysOf(ri)
          local vi = vis and visibleIndexOf(vis, k)
          if not vi or vi == 1 then return rows end
          local saved = E.VisibleToSaved(rows[ri], vis, vi - 1)
          return E.Move(rows, k, ri, saved)
        end },
      { "Move right", function(k, rows)
          local ri = E.Find(rows, k)
          local vis = ri and visKeysOf(ri)
          local vi = vis and visibleIndexOf(vis, k)
          if not vi or vi == #vis then return rows end
          local saved = E.VisibleToSaved(rows[ri], vis, vi + 2)
          return E.Move(rows, k, ri, saved)
        end },
      { "Move to other row", function(k, rows) local ri = E.Find(rows, k); local o = ri == 1 and 2 or 1; return E.Move(rows, k, o, #rows[o] + 1) end },
      { "Remove", function(k, rows) return E.Remove(rows, k) end },
    }
    for i, a in ipairs(acts) do
      local b = Skin.Button(m, a[1], i == 4 and "danger" or "ghost", 148, 24)
      b:SetPoint("TOPLEFT", m, "TOPLEFT", 6, -6 - (i - 1) * 26)
      b:SetScript("OnClick", function()
        local rows = Nock.CooldownRows.Get()
        if E.Find(rows, m.key) then Nock.CooldownRows.Set(a[2](m.key, rows)) end
        T:CloseMenu()
      end)
    end
    tinsert(UISpecialFrames, "NockCooldownTileMenu")
    self.menu = m
  end
  local anchor
  for _, h in ipairs(self.hot) do if h.key == key and h:IsShown() then anchor = h end end
  m.key = key
  m:ClearAllPoints()
  if anchor then m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4) end
  m:Show()
end

function T:CloseMenu() if self.menu then self.menu:Hide() end end

-- Flyout
local ROW_H = 30

function T:OpenFlyout(row, anchor)
  self:CloseMenu()
  local f = self.fly
  if not f then
    f = CreateFrame("Frame", "NockCooldownFlyout", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG"); f:SetWidth(300)
    Nock.UI.ApplyBackdrop(f, { 0.04, 0.04, 0.04, 0.97 }, { 0.67, 0.83, 0.45, 1 })
    f.title = f:CreateFontString(nil, "OVERLAY"); Skin.Font(f.title, "uiMedium", 13); Skin.Text(f.title, "ink")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    f.close = Skin.Button(f, "×", "ghost", 24, 24); f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    f.close:SetScript("OnClick", function() T:CloseFlyout() end)
    local box = CreateFrame("EditBox", nil, f)
    box:SetAutoFocus(false); box:SetHeight(26); box:SetTextInsets(8, 8, 0, 0)
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36); box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -36)
    Skin.Font(box, "ui", 12); box:SetTextColor(Skin.Color("ink"))
    box.bg = box:CreateTexture(nil, "BACKGROUND"); box.bg:SetAllPoints(box); Skin.Paint(box.bg, "surface2", 1)
    box:SetScript("OnTextChanged", function(b, user) if user then T:PaintFlyout() end end)
    box:SetScript("OnEnterPressed", function(b)
      local res = Nock.CooldownPicker.Resolve(b:GetText(), Nock.ForeverSpellbookNames and Nock.ForeverSpellbookNames() or {}, Nock.CooldownBoard.PickerCtx())
      if res then T:AddFromFlyout(res) end
      b:SetText(""); T:PaintFlyout()
    end)
    box:SetScript("OnEscapePressed", function() T:CloseFlyout() end)
    f.box = box
    f.lines = {}
    tinsert(UISpecialFrames, "NockCooldownFlyout")
    self.fly = f
  end
  f.row = row
  f.title:SetText("Add to " .. (row == 1 and "row 1" or "row 2"))
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
  f.box:SetText("")
  f:Show()
  self:PaintFlyout()
end

function T:CloseFlyout() if self.fly then self.fly:Hide() end end

function T:AddFromFlyout(it)
  -- Check the lockdown BEFORE writing a custom-spell record: CooldownRows.Set
  -- already no-ops in combat, but AddCustomSpell does not, so calling it
  -- first left a stray, never-placed custom entry behind. Only a NEW custom
  -- key (it.id, no it.key yet) needs the guard -- an already-catalogued item
  -- never calls AddCustomSpell.
  if (not it.key or it.petEntry) and InCombatLockdown and InCombatLockdown() then return end
  local key = Nock.CooldownBoard.KeyFor(it)
  if not key then return end
  local rows = Nock.CooldownRows.Get()
  if not Nock.CooldownEditor.Find(rows, key) then
    Nock.CooldownRows.Set(Nock.CooldownEditor.Add(rows, self.fly.row, key))
  end
end

local function line(i)
  local f = T.fly
  local l = f.lines[i]
  if l then return l end
  l = CreateFrame("Button", nil, f)
  l:SetHeight(ROW_H)
  l.icon = l:CreateTexture(nil, "ARTWORK"); l.icon:SetSize(ROW_H - 6, ROW_H - 6); l.icon:SetPoint("LEFT", l, "LEFT", 0, 0)
  l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  l.name = l:CreateFontString(nil, "OVERLAY"); Skin.Font(l.name, "ui", 12); Skin.Text(l.name, "ink")
  l.name:SetPoint("LEFT", l.icon, "RIGHT", 8, 0)
  l.meta = l:CreateFontString(nil, "OVERLAY"); Skin.Font(l.meta, "mono", 10); Skin.Text(l.meta, "ink3")
  l.meta:SetPoint("RIGHT", l, "RIGHT", 0, 0)
  l.head = l:CreateFontString(nil, "OVERLAY"); Skin.Font(l.head, "ui", 10); Skin.Text(l.head, "ink3")
  l.head:SetPoint("LEFT", l, "LEFT", 0, 0)
  l:SetScript("OnClick", function(self) if self.item then T:AddFromFlyout(self.item); T:PaintFlyout() end end)
  f.lines[i] = l
  return l
end

function T:PaintFlyout()
  local f = self.fly
  if not (f and f:IsShown()) then return end
  local ctx = Nock.CooldownBoard.PickerCtx()
  local groups = Nock.CooldownPicker.FlyoutGroups(ctx, f.box:GetText() or "")
  local y, n = 72, 0
  for _, g in ipairs(groups) do
    n = n + 1
    local h = line(n); h.item = nil
    h.icon:Hide(); h.name:SetText(""); h.meta:SetText(""); h.head:SetText(g.title:upper()); h.head:Show()
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -y); h:SetPoint("RIGHT", f, "RIGHT", -12, 0); h:SetHeight(18); h:Show()
    y = y + 20
    for _, it in ipairs(g.items) do
      n = n + 1
      local l = line(n)
      l.item = it
      l.head:Hide(); l.icon:Show(); l:SetHeight(ROW_H)
      l.icon:SetTexture((it.key and not it.petEntry) and T:DragIcon(it.key) or Nock.API.SpellIcon(it.id))
      if l.icon.SetDesaturated then l.icon:SetDesaturated(it.known == false) end
      l.icon:SetAlpha(it.known == false and 0.45 or 1)
      Skin.Text(l.name, it.known == false and "ink3" or "ink")
      l.name:SetText(it.name); l.meta:SetText(Nock.CooldownPicker.Meta(it))
      l:ClearAllPoints(); l:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -y); l:SetPoint("RIGHT", f, "RIGHT", -12, 0); l:Show()
      y = y + ROW_H + 2
    end
    y = y + 6
  end
  for i = n + 1, #f.lines do f.lines[i]:Hide(); f.lines[i].item = nil end
  f:SetHeight(y + 8)
end

T:RegisterEvent("PLAYER_LOGIN", function() T:Init() end)
