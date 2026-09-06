-- UI/SettingsLayouts.lua
-- The settings window's card layouts beyond the plain row flow: head actions, tables, the Background block, entry pills, item tables, segmented controls, form lines, swatch grids.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Skin = Nock.Skin
local W = Nock.OptionsWalk
local SC = Nock.UI.SettingsControls
local Settings = Nock.Settings

local function text(parent, role, size, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  Skin.Font(fs, role, size)
  Skin.Text(fs, color or "ink")
  fs:SetJustifyH("LEFT")
  return fs
end

local CELL_W = { color = 110, range = 176, select = 150, toggle = 38, execute = 110, input = 170, keybinding = 110, multiselect = 200 }
local CELL_H = 44
local PILL_H, PILL_GAP = 36, 6

--------------------------------------------------------------------------------
-- Icons: a card/pill icon spec -> texture on `tex`. {spell=id}, {item=id},
-- {glyph=name}, a path, or an AceConfig icon function.
--------------------------------------------------------------------------------
local function spellTexture(id)
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  if GetSpellTexture then return GetSpellTexture(id) end
end
local function itemTexture(id)
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
  if GetItemIcon then return GetItemIcon(id) end
end
-- Returns "glyph", name  |  "tex", texture  |  nil
function Settings.ResolveIcon(icon, info)
  if type(icon) == "function" then
    local okc, v = pcall(icon, info)
    icon = okc and v or nil
  end
  if type(icon) == "string" or type(icon) == "number" then return "tex", icon end
  if type(icon) ~= "table" then return nil end
  if icon.glyph then return "glyph", icon.glyph end
  if icon.spell then return "tex", spellTexture(icon.spell) end
  if icon.item then return "tex", itemTexture(icon.item) end
  return nil
end

--------------------------------------------------------------------------------
-- Pools of small things: icon buttons (up/down/x), ghost buttons, pills, frames.
--------------------------------------------------------------------------------
local function pool(self, name)
  self[name] = self[name] or { free = {}, used = {} }
  return self[name]
end
local function acquire(self, name, build)
  local p = pool(self, name)
  local f = table.remove(p.free)
  if not f then f = build() end
  p.used[#p.used + 1] = f
  f:Show()
  return f
end
function Settings:ReleaseLayouts()
  for _, name in ipairs({ "lyIconBtn", "lyBtn", "lyPill", "lyFrame", "lyText", "lyTex" }) do
    local p = self[name]
    if p then
      for _, f in ipairs(p.used) do
        if f.ctls then for _, ctl in ipairs(f.ctls) do ctl:Release() end; f.ctls = nil end
        f:Hide(); f:ClearAllPoints(); f:SetParent(UIParent)
        p.free[#p.free + 1] = f
      end
      p.used = {}
    end
  end
end

local function clickEdge(b)
  local now = GetTime()
  if b._acted and now - b._acted < 0.3 then b._acted = nil; return false end
  b._acted = now
  return true
end

local function runRow(self, row)
  if not row or row.disabled then return end
  local function go()
    local okf, err = W.Func(row)
    if not okf then Nock:Print(("Settings: %s"):format(tostring(err))) end
    self:AfterSet(row)
  end
  local ask = W.ConfirmText(row)
  if ask then self:Confirm(ask, go) else go() end
end

local function iconBtn(self, parent, glyph, row, tip)
  local b = acquire(self, "lyIconBtn", function()
    local x = CreateFrame("Button", nil, UIParent)
    x:SetSize(22, 22)
    Skin.Surface(x, "surface", "line")
    x.ico = x:CreateTexture(nil, "ARTWORK"); x.ico:SetPoint("CENTER")
    x:RegisterForClicks("AnyUp", "AnyDown")
    x:SetScript("OnClick", function(bb) if clickEdge(bb) and bb.onClick then bb.onClick() end end)
    x:SetScript("OnEnter", function(bb) Skin.Surface(bb, "surface2", "line"); if bb.tip then SC.ShowTooltip(bb, bb.tip, nil) end end)
    x:SetScript("OnLeave", function(bb) Skin.Surface(bb, "surface", "line"); SC.HideTooltip() end)
    return x
  end)
  b:SetParent(parent)
  Skin.Icon(b.ico, glyph, row and row.disabled and "ink3" or "ink2"); Skin.IconSize(b.ico, 12)
  b:SetAlpha(row and row.disabled and 0.45 or 1)
  b.tip = tip
  b.onClick = function() runRow(self, row) end
  return b
end

local function ghostBtn(self, parent, label, onClick, kind)
  local b = acquire(self, "lyBtn", function()
    local x = Skin.Button(UIParent, "", "ghost", nil, 24)
    x:RegisterForClicks("AnyUp", "AnyDown")
    x:SetScript("OnClick", function(bb) if clickEdge(bb) and bb.onClick then bb.onClick() end end)
    return x
  end)
  b:SetParent(parent)
  Skin.ButtonKind(b, kind or "ghost")
  Skin.SetButtonText(b, label)
  b.onClick = onClick
  return b
end

local function frame(self, parent, fill, line)
  local f = acquire(self, "lyFrame", function()
    local x = CreateFrame("Frame", nil, UIParent)
    x:EnableMouseWheel(true)
    x:SetScript("OnMouseWheel", function(_, d) if SC.OnWheel then SC.OnWheel(d) end end)
    return x
  end)
  f:SetParent(parent)
  f.ctls = {}
  if fill then Skin.Surface(f, fill, line) elseif f.skinFill then f.skinFill:SetAlpha(0); if f.skinLine then for i = 1, 4 do f.skinLine[i]:Hide() end end end
  if fill and f.skinFill then f.skinFill:SetAlpha(1) end
  return f
end

local function label(self, parent, role, size, color)
  local fs = acquire(self, "lyText", function()
    local holder = CreateFrame("Frame", nil, UIParent)
    holder.fs = text(holder, "ui", 12, "ink")
    holder.fs:SetPoint("LEFT", holder, "LEFT", 0, 0); holder.fs:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    holder.fs:SetWordWrap(false)
    return holder
  end)
  fs:SetParent(parent)
  Skin.Font(fs.fs, role, size); Skin.Text(fs.fs, color)
  fs.fs:SetJustifyH("LEFT")
  return fs
end

local function texture(self, parent)
  local t = acquire(self, "lyTex", function()
    local holder = CreateFrame("Frame", nil, UIParent)
    holder.tex = holder:CreateTexture(nil, "ARTWORK"); holder.tex:SetAllPoints(holder)
    holder.glyph = holder:CreateTexture(nil, "ARTWORK"); holder.glyph:SetPoint("CENTER")
    return holder
  end)
  t:SetParent(parent)
  return t
end

-- A row rule under a clustered line (the compact controls hide their own), so
-- a cluster reads as one row against whatever follows it.
function Settings:DrawRule(c, y, width)
  local t = texture(self, c)
  t.glyph:Hide()
  t.tex:SetTexCoord(0, 1, 0, 1); Skin.Paint(t.tex, "lineSoft", 1); t.tex:Show()
  t:ClearAllPoints(); t:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -y); t:SetSize(width - 2, 1)
end

-- Paints an icon spec into a texture holder; returns true when something drew.
local function paintIcon(holder, icon, info)
  local kind, v = Settings.ResolveIcon(icon, info)
  holder.tex:Hide(); holder.glyph:Hide()
  if kind == "tex" and v then
    holder.tex:SetTexture(v); holder.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93); holder.tex:Show()
    return true
  elseif kind == "glyph" and Skin.HasIcon(v) then
    Skin.Icon(holder.glyph, v, "ink2"); Skin.IconSize(holder.glyph, 16); holder.glyph:Show()
    return true
  end
  return false
end

--------------------------------------------------------------------------------
-- A control as a table cell: compact anatomy without the small label.
--------------------------------------------------------------------------------
local function cell(self, c, row, x, y, w)
  local kind = row.chips and "chips" or row.type
  local ctl = SC.Acquire(kind, c); c.ctls[#c.ctls + 1] = ctl
  ctl.frame:SetPoint("TOPLEFT", c, "TOPLEFT", x, -y)
  ctl.frame:SetWidth(w)
  if row.type == "toggle" then ctl.headerOnly = true end
  ctl:Bind(row, self)
  if row.type == "toggle" then
    ctl.frame:ClearAllPoints(); ctl.frame:SetPoint("LEFT", c, "TOPLEFT", x, -(y + CELL_H / 2))
    ctl.height = 20
  else
    if ctl.Compact then ctl:Compact() end
    if ctl.frame.label then ctl.frame.label:Hide() end
    ctl.frame:SetHeight(CELL_H)
    ctl.height = CELL_H
  end
  return ctl
end

--------------------------------------------------------------------------------
-- Head actions: execute rows as buttons in the card head's right slot; an
-- entries section's Add select as a "+" that opens the pullout.
--------------------------------------------------------------------------------
function Settings:DrawActions(c, rows, anchorRight)
  local right = anchorRight or c.head
  local x = -16
  for i = #rows, 1, -1 do
    local row = rows[i]
    local b
    if row.type == "select" then
      b = iconBtn(self, right, "plus", row, W.Strip(row.name))
      b.onClick = function()
        if row.disabled then return end
        local okv, cur = W.Get(row)
        SC.OpenPullout(b, row, nil, okv and cur or nil, function(key)
          local oks, err = W.Set(row, key)
          if not oks then Nock:Print(("Settings: %s"):format(tostring(err))) end
          self:AfterSet(row)
        end)
      end
    else
      b = ghostBtn(self, right, W.Strip(row.name), function() runRow(self, row) end, W.Strip(row.name):lower():find("reset", 1, true) and "danger" or "ghost")
      b:SetAlpha(row.disabled and 0.45 or 1)
    end
    b:ClearAllPoints()
    b:SetPoint("RIGHT", right, "RIGHT", x, 0)
    x = x - (b:GetWidth() or 24) - 6
  end
end

--------------------------------------------------------------------------------
-- Tables: a label column (unless one row), column heads, cells of controls.
--------------------------------------------------------------------------------
-- A table spec with `grid = N`: every line is a pill (icon · name · the
-- line's controls at the right), N columns, no column heads. The PvP debuff
-- set uses it; the walker builds the same lines as for a table.
function Settings:DrawTableGrid(c, t, y, width)
  local inner = width - 32
  local top = y
  local cols = math.max(1, math.min(t.grid or 3, math.floor((inner + PILL_GAP) / 240)))
  local w = math.floor((inner - PILL_GAP * (cols - 1)) / cols)
  for i, line in ipairs(t.rows) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local px, py = 16 + col * (w + PILL_GAP), y + row * (PILL_H + PILL_GAP)
    local p = frame(self, c, "ground", "line")
    p:ClearAllPoints(); p:SetPoint("TOPLEFT", c, "TOPLEFT", px, -py); p:SetSize(w, PILL_H)
    local left = 8
    if line.icon then
      local ic = texture(self, p)
      if paintIcon(ic, line.icon, nil) then
        ic:ClearAllPoints(); ic:SetPoint("LEFT", p, "LEFT", left, 0); ic:SetSize(24, 24)
        left = left + 30
      end
    end
    -- the line's controls from the right: a toggle as its bare box, anything else compact
    local rx = -6
    for ci = #line.cells, 1, -1 do
      local cellRows = line.cells[ci]
      for ri = #cellRows, 1, -1 do
        local r = cellRows[ri]
        if r.type == "toggle" then
          local ctl = SC.Acquire("toggle", p); p.ctls[#p.ctls + 1] = ctl
          ctl.headerOnly = true
          ctl:Bind(r, self)
          ctl.frame:ClearAllPoints(); ctl.frame:SetPoint("RIGHT", p, "RIGHT", rx - 4, 0)
          rx = rx - 46
        elseif r.type == "execute" and W.Strip(r.name) == "X" then
          local b = iconBtn(self, p, "xmark", r, r.desc and SC.FirstLine(r.desc) or "Remove")
          b:ClearAllPoints(); b:SetPoint("RIGHT", p, "RIGHT", rx, 0)
          rx = rx - 26
        else
          local cw = math.min(CELL_W[r.type] or 120, math.floor(w / 2))
          local ctl = SC.Acquire(r.chips and "chips" or r.type, p); p.ctls[#p.ctls + 1] = ctl
          ctl.frame:SetPoint("RIGHT", p, "RIGHT", rx, 0)
          ctl.frame:SetWidth(cw)
          ctl:Bind(r, self)
          if ctl.Compact then ctl:Compact() end
          if ctl.frame.label then ctl.frame.label:Hide() end
          ctl.frame:SetHeight(PILL_H)
          rx = rx - cw - 6
        end
      end
    end
    local nl = label(self, p, "uiMedium", 13, "ink")
    nl.fs:SetText(line.label)
    nl:ClearAllPoints(); nl:SetPoint("LEFT", p, "LEFT", left, 0); nl:SetPoint("RIGHT", p, "RIGHT", rx - 6, 0); nl:SetHeight(PILL_H)
  end
  return math.ceil(#t.rows / cols) * (PILL_H + PILL_GAP) - PILL_GAP + 8 + (y - top)
end

function Settings:DrawTable(c, t, y, width, noHead)
  if t.grid and not t.one then return self:DrawTableGrid(c, t, y, width) end
  local inner = width - 32
  local labelW = t.one and 0 or 120
  local ncol = #t.cols
  local gap = 12
  local colW = math.floor((inner - labelW - gap * (ncol - 1)) / math.max(1, ncol))
  local top = y
  if not noHead then
    for i, name in ipairs(t.cols) do
      if name ~= "" then
        local l = label(self, c, "mono", 10, "ink3")
        l.fs:SetText(name:upper())
        l:ClearAllPoints(); l:SetPoint("TOPLEFT", c, "TOPLEFT", 16 + labelW + (i - 1) * (colW + gap), -(y + 8)); l:SetSize(colW, 14)
      end
    end
    y = y + 26
  end
  for _, line in ipairs(t.rows) do
    local rowH = CELL_H
    if not t.one then
      local left = 16
      if line.icon then
        local ic = texture(self, c)
        if paintIcon(ic, line.icon, nil) then
          ic:ClearAllPoints(); ic:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -(y + (CELL_H - 24) / 2)); ic:SetSize(24, 24)
          left = 16 + 30
        end
      end
      local l = label(self, c, "uiMedium", 13, "ink")
      l.fs:SetText(line.label)
      l:ClearAllPoints(); l:SetPoint("TOPLEFT", c, "TOPLEFT", left, -y); l:SetSize(labelW - 8 - (left - 16), CELL_H)
    end
    for i, cellRows in ipairs(line.cells) do
      local x = 16 + labelW + (i - 1) * (colW + gap)
      local used = 0
      -- an execute named X is the small remove button, not a wide one
      if #cellRows == 1 and cellRows[1].type == "execute" and W.Strip(cellRows[1].name) == "X" then
        local b = iconBtn(self, c, "xmark", cellRows[1], cellRows[1].desc and SC.FirstLine(cellRows[1].desc) or "Remove")
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", c, "TOPLEFT", x, -(y + (CELL_H - 22) / 2))
        cellRows = {}
      end
      -- widths: each control its kind's width, shrunk evenly to the column
      local want = 0
      for _, r in ipairs(cellRows) do want = want + (CELL_W[r.type] or 120) + 8 end
      local scale = want > colW and colW / want or 1
      for _, r in ipairs(cellRows) do
        local w = math.floor((CELL_W[r.type] or 120) * scale)
        local ctl = cell(self, c, r, x + used, y, w)
        used = used + w + 8
        rowH = math.max(rowH, ctl.height or CELL_H)
      end
    end
    local rule = texture(self, c)
    rule:ClearAllPoints(); rule:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -(y + rowH - 1)); rule:SetSize(inner, 1)
    rule.tex:SetTexture(nil); rule.tex:SetColorTexture(Skin.Color("lineSoft")); rule.tex:SetTexCoord(0, 1, 0, 1); rule.tex:Show(); rule.glyph:Hide()
    y = y + rowH
  end
  return y - top + 8
end

-- The Background block as a two-line table without column heads.
function Settings:DrawBgBlock(c, blk, y, width)
  local t = { one = false, cols = { "" }, rows = {
    { label = "Background", cells = { blk.bg } },
    { label = "Border", cells = { blk.border } },
  } }
  return self:DrawTable(c, t, y, width, true)
end

--------------------------------------------------------------------------------
-- Entry pills: pos · icon · name · toggle · up/down[/x]; sections side by side.
--------------------------------------------------------------------------------
local function entryName(row)
  local plain = W.Strip(row.name)
  local base, id, kind = SC.SpellOfName(plain)
  if row.type == "description" then base = base:gsub("^%d+%.%s*", "") end
  if id and kind == "spell" then
    local nm = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    if type(nm) == "table" then nm = nm.name end
    if not nm and GetSpellInfo then nm = GetSpellInfo(id) end
    if nm and nm ~= "" then base = nm end
  elseif id and kind == "item" then
    local nm = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not nm and GetItemInfo then nm = GetItemInfo(id) end
    if nm and nm ~= "" and not base:find(nm, 1, true) then base = base end
  end
  return base, id, kind
end

function Settings:DrawPill(parent, e, pos, x, y, w)
  local p = frame(self, parent, "ground", "line")
  p:ClearAllPoints(); p:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y); p:SetSize(w, PILL_H)
  local name, id, kind = entryName(e.label)
  local n = label(self, p, "mono", 11, "ink3"); n.fs:SetText(tostring(pos)); n.fs:SetJustifyH("RIGHT")
  n:ClearAllPoints(); n:SetPoint("LEFT", p, "LEFT", 6, 0); n:SetSize(16, PILL_H)
  local left = 26
  if id then
    local ic = texture(self, p)
    if paintIcon(ic, kind == "item" and { item = id } or { spell = id }) then
      ic:ClearAllPoints(); ic:SetPoint("LEFT", p, "LEFT", left, 0); ic:SetSize(24, 24)
      left = left + 30
    end
  end
  -- buttons from the right: x, down, up
  local rx = -6
  local btns = {}
  for i = #e.buttons, 1, -1 do
    local br = e.buttons[i]
    local nm = W.Strip(br.name)
    local glyph = nm == "Up" and "chevronup" or nm == "Down" and "chevrondown" or "xmark"
    local b = iconBtn(self, p, glyph, br, nm == "X" and (br.desc and SC.FirstLine(br.desc) or "Remove") or nil)
    b:ClearAllPoints(); b:SetPoint("RIGHT", p, "RIGHT", rx, 0)
    rx = rx - 26
    btns[#btns + 1] = b
  end
  if e.label.type == "toggle" then
    local ctl = SC.Acquire("toggle", p); p.ctls[#p.ctls + 1] = ctl
    ctl.headerOnly = true
    ctl:Bind(e.label, self)
    ctl.frame:ClearAllPoints(); ctl.frame:SetPoint("RIGHT", p, "RIGHT", rx - 4, 0)
    rx = rx - 46
  end
  local nl = label(self, p, "uiMedium", 13, e.label.disabled and "ink3" or "ink")
  nl.fs:SetText(name)
  nl:ClearAllPoints(); nl:SetPoint("LEFT", p, "LEFT", left, 0); nl:SetPoint("RIGHT", p, "RIGHT", rx - 6, 0); nl:SetHeight(PILL_H)
  return p
end

function Settings:DrawEntries(c, sections, y, width)
  local inner = width - 32
  local top = y
  if #sections == 1 and sections[1].implicit then
    local cols = inner >= 560 and 2 or 1
    local w = math.floor((inner - PILL_GAP * (cols - 1)) / cols)
    for i, e in ipairs(sections[1].entries) do
      local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
      self:DrawPill(c, e, i, 16 + col * (w + PILL_GAP), y + line * (PILL_H + PILL_GAP), w)
    end
    y = y + math.ceil(#sections[1].entries / cols) * (PILL_H + PILL_GAP) + 8
    if sections[1].add then
      -- an implicit section's Add select stays a normal row under the pills
      local ctl = SC.Acquire("select", c); c.ctls[#c.ctls + 1] = ctl
      ctl.frame:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -y); ctl.frame:SetPoint("TOPRIGHT", c, "TOPRIGHT", -1, -y)
      ctl:Bind(sections[1].add, self)
      y = y + (ctl.height or Settings.ROW_H)
    end
    return y - top
  end
  local ncol = math.min(3, #sections)
  local gap = 12
  local colW = math.floor((inner - gap * (ncol - 1)) / ncol)
  local rowY, maxH = y, 0
  for i, s in ipairs(sections) do
    local col = (i - 1) % ncol
    if col == 0 and i > 1 then rowY = rowY + maxH + gap; maxH = 0 end
    local sub = frame(self, c, "surface", "line")
    sub:ClearAllPoints(); sub:SetPoint("TOPLEFT", c, "TOPLEFT", 16 + col * (colW + gap), -rowY); sub:SetWidth(colW)
    -- head: sub (ROW N) + title, the Add "+" at the right
    local head = frame(self, sub, "raised")
    head:ClearAllPoints(); head:SetPoint("TOPLEFT", sub, "TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", sub, "TOPRIGHT", -1, -1); head:SetHeight(36)
    local hx = 12
    if s.sub then
      local sl = label(self, head, "mono", 10, "ink3"); sl.fs:SetText(s.sub:upper())
      sl:ClearAllPoints(); sl:SetPoint("LEFT", head, "LEFT", hx, 0); sl:SetSize(46, 36)
      hx = hx + 50
    end
    local tl = label(self, head, "displayMedium", 15, "ink"); tl.fs:SetText((s.name or "Entries"):upper())
    tl:ClearAllPoints(); tl:SetPoint("LEFT", head, "LEFT", hx, 0); tl:SetPoint("RIGHT", head, "RIGHT", -40, 0); tl:SetHeight(36)
    if s.add then self:DrawActions(sub, { s.add }, head) end
    local py = 36 + 8
    for j, e in ipairs(s.entries) do
      self:DrawPill(sub, e, j, 8, py, colW - 16)
      py = py + PILL_H + PILL_GAP
    end
    sub:SetHeight(py + 4)
    maxH = math.max(maxH, py + 4)
  end
  return rowY + maxH - top + 8
end

--------------------------------------------------------------------------------
-- Item tables: Shopping's curated list (icon · name | Track | Keep at least)
-- and custom entries (name | Keep at least | x).
--------------------------------------------------------------------------------
function Settings:DrawItems(c, items, y, width, custom)
  local inner = width - 32
  local top = y
  local trackW, thrW = custom and 0 or 70, 190
  local nameW = inner - trackW - thrW - (custom and 40 or 0) - 24
  local heads = custom and { "Item", "Keep at least", "" } or { "Item", "Track", "Keep at least" }
  local xs = custom and { 16, 16 + nameW + 12, 16 + nameW + 12 + thrW + 12 } or { 16, 16 + nameW + 12, 16 + nameW + 12 + trackW + 12 }
  for i, h in ipairs(heads) do
    if h ~= "" then
      local l = label(self, c, "mono", 10, "ink3"); l.fs:SetText(h:upper())
      l:ClearAllPoints(); l:SetPoint("TOPLEFT", c, "TOPLEFT", xs[i], -(y + 8)); l:SetSize(120, 14)
    end
  end
  y = y + 26
  for _, it in ipairs(items) do
    local left = 16
    if it.icon then
      local ic = texture(self, c)
      if paintIcon(ic, it.icon, nil) then
        ic:ClearAllPoints(); ic:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -(y + (CELL_H - 24) / 2)); ic:SetSize(24, 24)
        left = 16 + 30
      end
    end
    if not it.icon and it.label then
      local _, hid, hkind = SC.SpellOfName(W.Strip(it.label.name))
      if hid then
        local ic = texture(self, c)
        if paintIcon(ic, hkind == "item" and { item = hid } or { spell = hid }) then
          ic:ClearAllPoints(); ic:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -(y + (CELL_H - 24) / 2)); ic:SetSize(24, 24)
          left = 16 + 30
        end
      end
    end
    local nm = label(self, c, "uiMedium", 13, "ink")
    local nameText = it.name or (it.label and (SC.SpellOfName(W.Strip(it.label.name)))) or ""
    nm.fs:SetText(nameText)
    nm:ClearAllPoints(); nm:SetPoint("TOPLEFT", c, "TOPLEFT", left, -y); nm:SetSize(nameW - (left - 16), CELL_H)
    if custom then
      cell(self, c, it.thr, xs[2], y, thrW)
      local b = iconBtn(self, c, "xmark", it.remove, "Remove")
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", c, "TOPLEFT", xs[3], -(y + (CELL_H - 22) / 2))
    else
      cell(self, c, it.on, xs[2], y, 38)
      cell(self, c, it.thr, xs[3], y, thrW)
    end
    local rule = texture(self, c)
    rule:ClearAllPoints(); rule:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -(y + CELL_H - 1)); rule:SetSize(inner, 1)
    rule.tex:SetTexture(nil); rule.tex:SetColorTexture(Skin.Color("lineSoft")); rule.tex:SetTexCoord(0, 1, 0, 1); rule.tex:Show(); rule.glyph:Hide()
    y = y + CELL_H
  end
  return y - top + 8
end

--------------------------------------------------------------------------------
-- Segmented control: label + desc left, the buttons right (each runs its row).
--------------------------------------------------------------------------------
function Settings:DrawSegments(c, seg, y, width)
  local h = Settings.ROW_H
  local l = label(self, c, "uiMedium", 13, "ink"); l.fs:SetText(seg.label or "")
  l:ClearAllPoints(); l:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -(y + 11)); l:SetSize(200, 16)
  if seg.desc and seg.desc ~= "" then
    local d = label(self, c, "ui", 12, "ink2"); d.fs:SetText(seg.desc)
    d:ClearAllPoints(); d:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -(y + 30)); d:SetSize(width - 32 - 340, 16)
  end
  local x = -16
  for i = #seg.buttons, 1, -1 do
    local sb = seg.buttons[i]
    local b = ghostBtn(self, c, sb.name, function() runRow(self, sb.row) end)
    b:SetHeight(30)
    b:SetAlpha((sb.row and not sb.row.disabled) and 1 or 0.45)
    b.tip = sb.hint
    b:SetScript("OnEnter", function(bb) if bb.tip then SC.ShowTooltip(bb, sb.name, bb.tip) end end)
    b:SetScript("OnLeave", function() SC.HideTooltip() end)
    b:ClearAllPoints(); b:SetPoint("TOPRIGHT", c, "TOPRIGHT", x, -(y + 12))
    x = x - (b:GetWidth() or 60) - 6
  end
  return h
end

--------------------------------------------------------------------------------
-- Form line: every control compact (small label above) on one line, wrapping.
--------------------------------------------------------------------------------
local FORM_W = { select = 150, input = 190, execute = 110, range = 170, toggle = 120, color = 110, keybinding = 110 }
function Settings:DrawForm(c, rows, y, width)
  local inner = width - 32
  local top = y
  local x, lh = 16, 0
  for _, row in ipairs(rows) do
    local w = FORM_W[row.type] or 150
    if x + w > inner + 16 and x > 16 then x = 16; y = y + lh + 4; lh = 0 end
    local ctl = SC.Acquire(row.chips and "chips" or row.type, c); c.ctls[#c.ctls + 1] = ctl
    ctl.frame:SetPoint("TOPLEFT", c, "TOPLEFT", x, -y)
    ctl.frame:SetWidth(w)
    ctl:Bind(row, self)
    if ctl.Compact then ctl:Compact() end
    if row.type == "execute" and ctl.btn then
      -- a button on a form line sits on the same band as the fields beside it
      -- (label space above, 28 px control at the bottom), not centred in 44
      ctl.frame:SetHeight(Settings.ROW_H); ctl.height = Settings.ROW_H
      ctl.btn:ClearAllPoints()
      ctl.btn:SetPoint("BOTTOMLEFT", ctl.frame, "BOTTOMLEFT", 0, 6); ctl.btn:SetPoint("BOTTOMRIGHT", ctl.frame, "BOTTOMRIGHT", -8, 6)
      ctl.btn:SetHeight(28)
    end
    x = x + w + 10
    lh = math.max(lh, ctl.height or Settings.ROW_H)
  end
  return y + lh - top + 6
end

--------------------------------------------------------------------------------
-- Swatch grid: a run of colour rows as a two-column grid of compact swatches.
--------------------------------------------------------------------------------
function Settings:DrawSwatches(c, rows, y, width)
  local inner = width - 32
  local cols = inner >= 500 and 2 or 1
  local gap = 8
  local w = math.floor((inner - gap * (cols - 1)) / cols)
  for i, row in ipairs(rows) do
    local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
    local ctl = SC.Acquire("color", c); c.ctls[#c.ctls + 1] = ctl
    ctl.frame:SetPoint("TOPLEFT", c, "TOPLEFT", 16 + col * (w + gap), -(y + line * 48))
    ctl.frame:SetWidth(w)
    ctl:Bind(row, self)
    ctl:Compact()
    ctl.frame:SetHeight(44)
  end
  return math.ceil(#rows / cols) * 48 + 4
end

--------------------------------------------------------------------------------
-- The card body: descriptors first, then the remaining lines.
--------------------------------------------------------------------------------
function Settings:LayoutCard(c, card, top, width)
  local y = top
  local lines = card.lines or {}
  local rest = {}
  -- the card's one-liner leads
  for _, ln in ipairs(lines) do
    if ln.rows[1] and ln.rows[1].key == "__desc" and #ln.rows == 1 then
      y = y + self:LayoutLines(c, { ln }, y, width)
    else rest[#rest + 1] = ln end
  end
  -- a block drawn straight under the head gets breathing room (a one-liner brings its own)
  if y == top and (card.segmentRows or card.tableRows or card.bgBlock or card.itemRows or card.formRows or card.entries or card.items) then y = y + 10 end
  if card.segmentRows then y = y + self:DrawSegments(c, card.segmentRows, y, width) end
  if card.tableRows then y = y + self:DrawTable(c, card.tableRows, y, width) end
  if card.bgBlock then y = y + self:DrawBgBlock(c, card.bgBlock, y, width) end
  if card.itemRows then y = y + self:DrawItems(c, card.itemRows, y, width, false) end
  if card.formRows then
    y = y + self:DrawForm(c, card.formRows, y, width)
  elseif card.form == true then
    local ctls, other = {}, {}
    for _, ln in ipairs(rest) do for _, r in ipairs(ln.rows) do if r.isControl then ctls[#ctls + 1] = r else other[#other + 1] = { rows = { r }, cluster = false } end end end
    if #other > 0 then y = y + self:LayoutLines(c, other, y, width) end
    if #ctls > 0 then y = y + self:DrawForm(c, ctls, y, width) end
    rest = {}
  end
  if card.entries then y = y + self:DrawEntries(c, card.entries, y, width) end
  if card.items then y = y + self:DrawItems(c, card.items, y, width, true) end
  if #rest > 0 then y = y + self:LayoutLines(c, rest, y, width) end
  return y - top
end
