-- UI/Settings_KeyBinds.lua
-- The Key binds card body: the bind list on the left, the selected bind's editor rows on the right (press above release), or the first-visit panel when there are none.

-- Spec: docs/superpowers/specs/2026-11-18-forever-key-binds-design.md (layout
-- A from the design canvas). The rows are Config/OptionsForever.lua's
-- F.KeyBindsPage nodes, bound through the settings controls like any other
-- card; only the list pills and the empty panel are this file's own frames,
-- pooled here and hidden by Settings:ReleaseLayouts.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Skin = Nock.Skin
local Settings = Nock.Settings
local SC = Nock.UI.SettingsControls
local W = Nock.OptionsWalk

local V = {}
Nock.KeyBindsView = V

V.ORDER = { "kbName", "kbKey", "kbConflict", "kbDown", "kbUp", "kbDuplicate", "kbDelete", "kbStatus" }
local RANK = {}
for i, k in ipairs(V.ORDER) do RANK[k] = i end

-- Pure: the editor rows out of a card's lines, in V.ORDER; the other lines
-- (rows the board does not draw) stay for the plain flow.
function V.Split(lines)
  local ed, rest = {}, {}
  for _, ln in ipairs(lines or {}) do
    local keep = {}
    for _, r in ipairs(ln.rows or {}) do
      if RANK[r.key] then ed[#ed + 1] = r else keep[#keep + 1] = r end
    end
    if #keep == #(ln.rows or {}) then rest[#rest + 1] = ln
    elseif #keep > 0 then local c = {}; for k, v in pairs(ln) do c[k] = v end; c.rows = keep; rest[#rest + 1] = c end
  end
  table.sort(ed, function(a, b) return RANK[a.key] < RANK[b.key] end)
  return ed, rest
end

if not (Settings and SC and Skin and Skin.Surface) then return end

local LIST_W, GAP, PAD = 300, 18, 16
local PILL_H, PILL_GAP = 54, 6
local ICON = 30   -- the press / release icons on a list pill

local function text(parent, role, size, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  Skin.Font(fs, role, size); Skin.Text(fs, color or "ink")
  fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
  return fs
end

local function KB() return Nock.KeyBinds end
local function changed() Nock:SendMessage("NOCK_KEYBINDS_CHANGED"); Settings:RefreshLater("keybinds") end

--------------------------------------------------------------------------------
-- Own pool: list pills, the list label, the empty panel.
--------------------------------------------------------------------------------
local pills = {}
local head, panel, ed   -- ed: the editor box behind the right column

local function pill(i)
  local b = pills[i]
  if b then return b end
  b = CreateFrame("Button", nil, UIParent)
  b:SetHeight(PILL_H)
  b:RegisterForClicks("LeftButtonUp")
  -- the press and release spells' icons, left of the text, to spot a bind at a glance
  b.icons = {}
  for k = 1, 2 do
    local slot = CreateFrame("Frame", nil, b); slot:SetSize(ICON, ICON)
    slot:SetPoint("LEFT", b, "LEFT", 10 + (k - 1) * (ICON + 4), 0)
    Skin.Surface(slot, "ground", "line")
    slot.tex = slot:CreateTexture(nil, "ARTWORK"); slot.tex:SetPoint("TOPLEFT", 1, -1); slot.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icons[k] = slot
  end
  local tx = 10 + 2 * ICON + 4 + 12
  b.name = text(b, "uiMedium", 13, "ink"); b.name:SetPoint("TOPLEFT", b, "TOPLEFT", tx, -10)
  b.chip = CreateFrame("Frame", nil, b); b.chip:SetHeight(20); b.chip:SetPoint("TOPRIGHT", b, "TOPRIGHT", -10, -8)
  b.chip.label = text(b.chip, "mono", 11, "ink"); b.chip.label:SetPoint("CENTER")
  b.name:SetPoint("RIGHT", b.chip, "LEFT", -8, 0)
  b.sum = text(b, "mono", 11, "ink2"); b.sum:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", tx, 10); b.sum:SetPoint("RIGHT", b, "RIGHT", -10, 0)
  b:SetScript("OnClick", function(self)
    if not KB() then return end
    KB().selected = self.index
    Settings:RefreshLater("keybinds")
  end)
  pills[i] = b
  return b
end

local function paintPill(b, bind, selected)
  if selected then Skin.Surface(b, "accent", "accent", 0.14) else Skin.Surface(b, "surface2", "line") end
  local unnamed = bind.name == nil or bind.name == "" or bind.name == "Untitled bind"
  b.name:SetText(bind.name or "Untitled bind"); Skin.Text(b.name, unnamed and "ink2" or "ink")
  local key = type(bind.key) == "string" and bind.key ~= "" and bind.key or nil
  b.chip.label:SetText(key or "NO KEY"); Skin.Text(b.chip.label, key and "ink" or "wait")
  Skin.Surface(b.chip, "raised", key and "line" or "wait")
  b.chip:SetWidth(math.max(56, (b.chip.label:GetStringWidth() or 40) + 16))
  b.sum:SetText(KB().Summary(bind))
  for k, body in ipairs({ bind.down, bind.up }) do
    local icon = KB().Icon(KB().FirstSpell(body))
    local t = b.icons[k].tex
    if icon then t:SetTexture(icon); t:Show() else t:Hide() end
  end
end

local function emptyPanel()
  if panel then return panel end
  local f = CreateFrame("Frame", nil, UIParent)
  Skin.Surface(f, "surface2", "line")
  f:SetSize(560, 300)
  f.title = text(f, "displayMedium", 18, "ink"); f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -26)
  f.title:SetText("One key, two tries")
  f.body = text(f, "ui", 13, "ink2"); f.body:SetWordWrap(true)
  f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -10); f.body:SetPoint("RIGHT", f, "RIGHT", -28, 0)
  f.body:SetText("A macro stops at the first spell that isn't ready, often with no error. A key bind splits the two: one macro runs when you press the key, the other when you let go.")
  f.ex = CreateFrame("Frame", nil, f); Skin.Surface(f.ex, "ground", "line"); f.ex:SetHeight(40)
  f.ex:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -16); f.ex:SetPoint("RIGHT", f, "RIGHT", -28, 0)
  f.ex.t = text(f.ex, "mono", 12, "accent"); f.ex.t:SetPoint("LEFT", f.ex, "LEFT", 14, 0)
  f.ex.t:SetText("SHIFT-E   ↓ Raptor Strike   then   ↑ Mongoose Bite")
  f.steps = text(f, "ui", 13, "ink2"); f.steps:SetWordWrap(true)
  f.steps:SetPoint("TOPLEFT", f.ex, "BOTTOMLEFT", 0, -16); f.steps:SetPoint("RIGHT", f, "RIGHT", -28, 0)
  f.steps:SetText("1  Make a bind and give it a key.\n2  Write what runs on press and what runs on release.\n3  Use it in combat. Edits you make in combat apply when combat ends.")
  f.new = Skin.Button(f, "+ New bind", "primary", nil, 30)
  f.new:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 28, 24)
  f.new:SetScript("OnClick", function()
    local K = KB(); if not K then return end
    K.selected = K.New(K.List(Nock.db.profile)); changed()
  end)
  panel = f
  return f
end

function Settings:HideKeyBindsBoard()
  for i = 1, #pills do pills[i]:Hide(); pills[i]:ClearAllPoints(); pills[i]:SetParent(UIParent) end
  if head then head:Hide() end
  if panel then panel:Hide(); panel:ClearAllPoints(); panel:SetParent(UIParent) end
  if ed then ed:Hide(); ed:ClearAllPoints(); ed:SetParent(UIParent) end
end

--------------------------------------------------------------------------------
-- The editor box: caps labels, the conflict note, the Start-from pair, the
-- footer (status left, Duplicate / Delete right). Built once; the rows' own
-- controls (name, key, both macros) are settings controls placed over it.
--------------------------------------------------------------------------------
local P = 18          -- padding inside the editor box
local MACRO_LINES = 4

local function editorBox()
  if ed then return ed end
  local f = CreateFrame("Frame", nil, UIParent)
  Skin.Surface(f, "surface2", "line")
  local function caps(t) local fs = text(f, "mono", 10, "ink3"); fs:SetText(t); return fs end
  f.lName, f.lKey = caps("NAME"), caps("KEY")
  f.lDown, f.lUp = caps("↓  ON PRESS"), caps("↑  ON RELEASE")
  f.cDown, f.cUp = text(f, "mono", 10, "ink3"), text(f, "mono", 10, "ink3")
  f.cDown:SetJustifyH("RIGHT"); f.cUp:SetJustifyH("RIGHT")
  f.warn = CreateFrame("Frame", nil, f); Skin.Surface(f.warn, "wait", "wait", 0.08); f.warn:SetHeight(30)
  f.warn.t = text(f.warn, "ui", 12, "wait"); f.warn.t:SetPoint("LEFT", f.warn, "LEFT", 12, 0); f.warn.t:SetPoint("RIGHT", f.warn, "RIGHT", -12, 0)
  f.clear = Skin.Button(f, "Clear", "ghost", nil, 28)
  f.rule = f:CreateTexture(nil, "ARTWORK"); f.rule:SetHeight(1); Skin.Paint(f.rule, "line", 1)
  f.status = text(f, "ui", 12, "ink2")
  f.dup = Skin.Button(f, "Duplicate", "ghost", nil, 30)
  f.del = Skin.Button(f, "Delete", "danger", nil, 30)
  for _, b in ipairs({ f.clear, f.dup, f.del }) do b:RegisterForClicks("LeftButtonUp") end
  ed = f
  return f
end

local function plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- A settings control with its own label hidden: the box's caps label names it.
local function cellCtl(self, c, row, x, y, w)
  local ctl = SC.Acquire(row.type, c); c.ctls[#c.ctls + 1] = ctl
  ctl.frame:ClearAllPoints(); ctl.frame:SetPoint("TOPLEFT", c, "TOPLEFT", x, -y); ctl.frame:SetWidth(w)
  ctl:Bind(row, self)
  if ctl.Compact then ctl:Compact() end
  local f = ctl.frame
  if f.label then f.label:Hide() end
  f:SetHeight(28); ctl.height = 28
  if f.ctl then f.ctl:ClearAllPoints(); f.ctl:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); f.ctl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0) end
  -- the key capture spans its cell, like the name box beside it
  if ctl.cap then ctl.cap:ClearAllPoints(); ctl.cap:SetAllPoints(f.ctl) end
  -- the single-line box sits 8 px in from its cell's left edge in the shared
  -- compact anatomy; flush it with the caps label above
  if ctl.line and ctl.box == ctl.line then ctl.line:ClearAllPoints(); ctl.line:SetAllPoints(f.ctl) end
  f:SetFrameLevel(c:GetFrameLevel() + 6)
  return ctl
end

-- A macro box: the input's multi-line holder alone, flush with the column.
-- Live: saved as you type (no Save step); `onText` repaints the counter and
-- the bind's list row while the box keeps focus.
local function macroCtl(self, c, row, x, y, w, onText)
  local ctl = SC.Acquire(row.type, c); c.ctls[#c.ctls + 1] = ctl
  local f = ctl.frame
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", c, "TOPLEFT", x, -y); f:SetWidth(w)
  ctl:Bind(row, self)
  f.label:Hide(); f.desc:Hide(); f.glyph:Hide(); f.rule:Hide()
  local h = MACRO_LINES * 16 + 14
  if ctl.holder then
    ctl.holder:ClearAllPoints(); ctl.holder:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); ctl.holder:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    ctl.holder:SetHeight(h)
    if ctl.multi then ctl.multi:SetWidth(math.max(60, w - 20)) end
  end
  ctl.live, ctl.onText = true, onText
  if ctl.multi and ctl.multi.SetMaxLetters then ctl.multi:SetMaxLetters(KB().MAX_BODY) end
  f:SetHeight(h); ctl.height = h
  f:SetFrameLevel(c:GetFrameLevel() + 6)
  return h
end

local function run(self, row)
  if not row or row.disabled then return end
  local okf, err = W.Func(row)
  if not okf then Nock:Print(("Settings: %s"):format(tostring(err))) end
  self:AfterSet(row)
end

--------------------------------------------------------------------------------
-- The board: returns its height and the lines left for the plain flow.
--------------------------------------------------------------------------------
function Settings:DrawKeyBindsBoard(c, card, rest, y, width)
  self:HideKeyBindsBoard()
  c.ctls = c.ctls or {}
  local edRows, left = V.Split(rest)
  local K = KB()
  local list = K and K.List(Nock.db.profile) or {}
  if #list == 0 or #edRows == 0 then
    local f = emptyPanel()
    f:SetParent(c); f:ClearAllPoints()
    f:SetPoint("TOP", c, "TOPLEFT", width / 2, -(y + 8))
    f:SetFrameLevel(c:GetFrameLevel() + 5)
    f:Show()
    return f:GetHeight() + 24, left
  end
  -- the list column
  if not head then head = CreateFrame("Frame", nil, UIParent); head:SetHeight(18); head.t = text(head, "mono", 10, "ink3"); head.t:SetPoint("LEFT") end
  head:SetParent(c); head:ClearAllPoints(); head:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y); head:SetWidth(LIST_W); head:Show()
  head.t:SetText(("YOUR BINDS  ·  %d"):format(#list))
  local ly = y + 24
  for i, bind in ipairs(list) do
    local b = pill(i)
    b.index = i
    b:SetParent(c); b:ClearAllPoints()
    b:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -ly); b:SetWidth(LIST_W)
    b:SetFrameLevel(c:GetFrameLevel() + 5)
    paintPill(b, bind, i == K.selected)
    b:Show()
    ly = ly + PILL_H + PILL_GAP
  end
  -- the editor box, level with the first pill
  local by = {}
  for _, r in ipairs(edRows) do by[r.key] = r end
  local bx = PAD + LIST_W + GAP
  local bw = width - bx - PAD
  local top = y + 24
  local f = editorBox()
  f:SetParent(c); f:ClearAllPoints(); f:SetPoint("TOPLEFT", c, "TOPLEFT", bx, -top)
  f:SetWidth(bw); f:SetFrameLevel(c:GetFrameLevel() + 2); f:Show()
  local x, w = bx + P, bw - 2 * P
  local cy = top + P
  local function at(fs, dx, dy) fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", f, "TOPLEFT", dx, -(dy - top)) end
  -- Name | Key [Clear]
  local half = math.floor((w - 14) / 2)
  at(f.lName, P, cy); at(f.lKey, P + half + 14, cy)
  cy = cy + 16
  if by.kbName then cellCtl(self, c, by.kbName, x, cy, half) end
  if by.kbKey then
    cellCtl(self, c, by.kbKey, x + half + 14, cy, half - 72)
    at(f.clear, P + half + 14 + half - 64, cy); f.clear:SetWidth(64)
    f.clear:SetScript("OnClick", function() W.Set(by.kbKey, ""); self:AfterSet(by.kbKey) end)
    f.clear:Show()
  else f.clear:Hide() end
  cy = cy + 28 + 14
  -- the game's own action on that key
  local warn = by.kbConflict and plain(by.kbConflict.name) or ""
  if warn ~= "" then
    f.warn.t:SetText(warn)
    at(f.warn, P, cy); f.warn:SetWidth(w); f.warn:Show()
    cy = cy + 30 + 14
  else f.warn:Hide() end
  -- the two macros, press above release
  for _, m in ipairs({ { f.lDown, f.cDown, by.kbDown }, { f.lUp, f.cUp, by.kbUp } }) do
    local lab, cnt, row = m[1], m[2], m[3]
    if row then
      at(lab, P, cy)
      local okv, v = W.Get(row)
      cnt:SetText(("%d / %d"):format(#((okv and v) or ""), K.MAX_BODY))
      cnt:ClearAllPoints(); cnt:SetPoint("TOPRIGHT", f, "TOPRIGHT", -P, -(cy - top))
      cy = cy + 16
      local sel = K.selected
      cy = cy + macroCtl(self, c, row, x, cy, w, function(v)
        cnt:SetText(("%d / %d"):format(#v, K.MAX_BODY))
        local bind, pb = K.List(Nock.db.profile)[sel], pills[sel]
        if bind and pb then paintPill(pb, bind, true) end
      end) + 14
    end
  end
  -- footer: rule, status left, Duplicate / Delete right
  at(f.rule, P, cy); f.rule:SetWidth(w)
  cy = cy + 14
  at(f.del, P + w - f.del:GetWidth(), cy)
  f.dup:ClearAllPoints(); f.dup:SetPoint("RIGHT", f.del, "LEFT", -8, 0)
  f.dup:SetScript("OnClick", function() run(self, by.kbDuplicate) end)
  f.del:SetScript("OnClick", function() run(self, by.kbDelete) end)
  f.status:SetText(by.kbStatus and plain(by.kbStatus.name) or "")
  Skin.Text(f.status, (K.Pending and K:Pending()) and "wait" or "ink2")
  f.status:ClearAllPoints(); f.status:SetPoint("LEFT", f, "TOPLEFT", P, -(cy - top + 15)); f.status:SetPoint("RIGHT", f.dup, "LEFT", -12, 0)
  cy = cy + 30 + P
  f:SetHeight(cy - top)
  return math.max(ly, cy) - y + 8, left
end

