-- UI/SettingsControls.lua
-- Pooled, skinned controls for the settings window: one frame family per AceConfig leaf type, bound to a walker row.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
Nock.UI = Nock.UI or {}
local Skin = Nock.Skin
local W = Nock.OptionsWalk
local SC = {}
Nock.UI.SettingsControls = SC
SC.LONG = 120
local ROW_H, CTL_W = 54, 200
local pools = {}   -- kind -> { free = {...} }
local kinds = {}   -- kind -> { build = fn(parent) -> ctl, bind = fn(ctl, row, host), release = fn(ctl) }

local function text(parent, role, size, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  Skin.Font(fs, role, size); Skin.Text(fs, color or "ink"); fs:SetJustifyH("LEFT")
  return fs
end

local function oneLine(s)
  s = s or ""
  local first = s:match("^([^\n]*)") or s
  if #first > SC.LONG then first = first:sub(1, SC.LONG):gsub("%s+%S*$", "") .. " …" end
  return first, (#s > SC.LONG or s:find("\n", 1, true) ~= nil)
end

-- Shared tooltip: one frame, raised fill, hairline, mono eyebrow + body.
local tip
function SC.ShowTooltip(anchor, title, body)
  if not tip then
    tip = CreateFrame("Frame", "NockSettingsTip", UIParent)
    tip:SetFrameStrata("TOOLTIP")
    tip:SetWidth(380)
    Skin.Surface(tip, "raised", "line")
    tip.title = text(tip, "mono", 10, "ink3"); tip.title:SetPoint("TOPLEFT", tip, "TOPLEFT", 14, -12)
    tip.body = text(tip, "ui", 12, "ink"); tip.body:SetPoint("TOPLEFT", tip.title, "BOTTOMLEFT", 0, -8); tip.body:SetWidth(352); tip.body:SetWordWrap(true)
  end
  tip.title:SetText((title or ""):upper())
  tip.body:SetText(body or "")
  tip:SetHeight(12 + 10 + 8 + (tip.body:GetStringHeight() or 12) + 14)
  tip:ClearAllPoints()
  tip:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
  tip:Show()
end
function SC.HideTooltip()
  if tip then local Probe_shared_tip = tip.IsShown; Probe_shared_tip(tip) end
  if tip then tip:Hide() end
  if SC.ClosePullout then SC.ClosePullout() end
end

local function baseRow(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(ROW_H)
  f.rule = Skin.Rule(f, "lineSoft"); f.rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); f.rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); f.rule:SetHeight(1)
  f.label = text(f, "uiMedium", 13, "ink"); f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -11)
  f.desc = text(f, "ui", 12, "ink2"); f.desc:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -3); f.desc:SetWordWrap(false)
  f.ctl = CreateFrame("Frame", nil, f); f.ctl:SetPoint("RIGHT", f, "RIGHT", -16, 0); f.ctl:SetSize(CTL_W, ROW_H)
  f.glyph = CreateFrame("Button", nil, f); f.glyph:SetSize(22, 22); f.glyph:SetPoint("RIGHT", f.ctl, "LEFT", -8, 0)
  f.glyph.ico = f.glyph:CreateTexture(nil, "ARTWORK"); f.glyph.ico:SetPoint("CENTER")
  Skin.Icon(f.glyph.ico, "info", "ink3"); Skin.IconSize(f.glyph.ico, 16)
  f.glyph:SetScript("OnEnter", function(g) Skin.Icon(g.ico, "info", "accent"); SC.ShowTooltip(g, g.tipTitle, g.tipBody) end)
  f.glyph:SetScript("OnLeave", function(g) Skin.Icon(g.ico, "info", "ink3"); SC.HideTooltip() end)
  f.label:SetPoint("RIGHT", f.glyph, "LEFT", -12, 0)
  f.desc:SetPoint("RIGHT", f.glyph, "LEFT", -12, 0)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, d) if SC.OnWheel then SC.OnWheel(d) end end)
  return f
end

-- Standard anatomy (label + one-line desc left, control right). Applied on
-- every Acquire so a control that was last drawn compact comes back whole.
local function restoreBase(ctl)
  local f = ctl.frame
  if not f.ctl then return end
  -- a table cell hides the label (SettingsLayouts `cell`); the pool must not carry that over
  f.label:Show()
  f.label:ClearAllPoints(); f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -11); f.label:SetPoint("RIGHT", f.glyph, "LEFT", -12, 0)
  Skin.Font(f.label, "uiMedium", 13); Skin.Text(f.label, "ink")
  f.desc:ClearAllPoints(); f.desc:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -3); f.desc:SetPoint("RIGHT", f.glyph, "LEFT", -12, 0)
  f.ctl:ClearAllPoints(); f.ctl:SetPoint("RIGHT", f, "RIGHT", -16, 0); f.ctl:SetSize(CTL_W, ROW_H)
  f.glyph:ClearAllPoints(); f.glyph:SetPoint("RIGHT", f.ctl, "LEFT", -8, 0)
  f.rule:Show()
  ctl.compact = nil
end

-- Compact anatomy for a clustered line (rows sharing a line by their width
-- units): the label sits small above, the control spans the row below it.
-- Kinds adjust their inner widget's width in `compactInner`.
local function compactBase(ctl)
  local f = ctl.frame
  if not f.ctl then
    -- header / description: a small paragraph that fits its cell
    if f.rule then f.rule:Hide() end
    if f.glyph then f.glyph:Hide() end
    if f.image then f.image:Hide() end
    local fs = f.body or f.label
    if fs then
      fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -8); fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
      fs:SetWordWrap(true); fs:SetJustifyV("TOP")
      local h = (fs:GetStringHeight() or 16) + 16
      f:SetHeight(math.max(ROW_H, h)); ctl.height = f:GetHeight()
    end
    ctl.compact = true
    return
  end
  f.desc:Hide(); f.glyph:Hide(); f.rule:Hide()
  f.label:ClearAllPoints(); f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -6); f.label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
  Skin.Font(f.label, "ui", 11); Skin.Text(f.label, "ink2")
  f.ctl:ClearAllPoints(); f.ctl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 6); f.ctl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 6); f.ctl:SetHeight(28)
  f:SetHeight(ROW_H); ctl.height = ROW_H
  ctl.compact = true
  local w = (f:GetWidth() or W.WIDTH_UNIT) - 8
  if w < 40 then w = W.WIDTH_UNIT - 8 end
  if kinds[ctl.kind] and kinds[ctl.kind].compactInner then kinds[ctl.kind].compactInner(ctl, w) end
end
SC.CompactBase = compactBase

-- Executes that refuse in combat (SetLocked, the wizard, Grounded import /
-- undo all touch protected frames): drawn disabled while locked down, so the
-- press does nothing instead of erroring.
local COMBAT_REFUSE = { lockAll = true, unlockAll = true, runWizard = true, weaveBindGroundedImport = true, weaveBindGroundedUndo = true }

-- Common binding: label, one-line desc (rest behind the glyph), disabled dim.
local function bindText(ctl, row)
  local f = ctl.frame
  if row.type == "execute" and COMBAT_REFUSE[row.key] and InCombatLockdown and InCombatLockdown() then row.disabled = true end
  f.label:SetText(row.name or "")
  local first, long = oneLine(row.desc)
  f.desc:SetText(first)
  f.desc:SetShown(first ~= "")
  f.glyph:SetShown(long)
  f.glyph.tipTitle, f.glyph.tipBody = row.name, row.desc
  f:SetAlpha(row.disabled and 0.45 or 1)
  f:SetHeight(first ~= "" and ROW_H or 44)
  ctl.height = f:GetHeight()
end
SC.BindText = bindText

-- Crash probes (diagnostic, 2026-09-09). The client has been crashing in the
-- Lua-arg resolver on pooled controls whose C++ object is already destroyed
-- (Errors/*.txt: "#1 [C]: in function 'Hide'" and the report dies printing
-- the argument, so no Lua frame is ever shown). The report DOES print the
-- name of the local through which the C function was called, so every pooled
-- object is touched first through an alias named after phase, kind and
-- field: a crash then reads "in function 'Probe_release_input_frame_label'".
-- Generated with loadstring so the names are static call sites.
local PROBE_COMMON = { "frame", "frame.label", "frame.desc", "frame.ctl", "frame.glyph", "frame.glyph.ico",
  "frame.rule", "frame.skinFill", "frame.image", "frame.body", "frame.icon", "frame.iconLine" }
local PROBE_KIND = {
  range = { "slider", "slider.track", "slider.fill", "ring", "box", "box.skinFill" },
  toggle = { "toggle", "toggle.track", "toggle.knob", "toggle.ag" },
  execute = { "btn", "btn.text", "btn.skinFill" },
  select = { "btn", "btn.label", "btn.caret", "btn.skinFill" },
  color = { "sw", "sw.fill", "sw.skinFill", "hx" },
  input = { "line", "line.skinFill", "multi", "scroll", "holder", "holder.skinFill" },
  keybinding = { "cap", "cap.label", "cap.skinFill" },
  multiselect = { "pills" },
}
local probeFns = {}
local function probe(phase, kind, ctl)
  local key = phase .. ":" .. kind
  local fn = probeFns[key]
  if fn == nil then
    local paths = {}
    for _, q in ipairs(PROBE_COMMON) do paths[#paths + 1] = q end
    for _, q in ipairs(PROBE_KIND[kind] or {}) do paths[#paths + 1] = q end
    local lines = { "return function(ctl)" }
    for _, q in ipairs(paths) do
      if q == "pills" then
        lines[#lines + 1] = "  if ctl.pills then for _, o in ipairs(ctl.pills) do local Probe_" .. phase .. "_" .. kind .. "_pill = o.IsShown; Probe_" .. phase .. "_" .. kind .. "_pill(o); local Probe_" .. phase .. "_" .. kind .. "_pill_lab = o.lab and o.lab.IsShown; if Probe_" .. phase .. "_" .. kind .. "_pill_lab then Probe_" .. phase .. "_" .. kind .. "_pill_lab(o.lab) end end end"
      else
        local expr, acc = "ctl", "ctl"
        for part in q:gmatch("[^.]+") do acc = acc .. "." .. part; expr = expr .. " and " .. acc end
        local var = "Probe_" .. phase .. "_" .. kind .. "_" .. (q:gsub("%.", "_"))
        lines[#lines + 1] = ("  do local o = %s; if o and o.IsShown then local %s = o.IsShown; %s(o) end end"):format(expr, var, var)
      end
    end
    lines[#lines + 1] = "end"
    local chunk, err = loadstring(table.concat(lines, "\n"), "NockSettingsProbe_" .. phase .. "_" .. kind)
    fn = chunk and chunk() or false
    if not fn and Nock.Print then Nock:Print(("Settings probe build failed: %s"):format(tostring(err))) end
    probeFns[key] = fn
  end
  if fn then fn(ctl) end
end
SC.Probe = probe

-- kind -> { free = n, total = n }; for /nock diag.
local built = {}
function SC.PoolCounts()
  local out = {}
  for kind, p in pairs(pools) do out[kind] = { free = #p.free, total = built[kind] or 0 } end
  return out
end

function SC.Acquire(kind, parent)
  local k = kinds[kind] or kinds.description
  pools[kind] = pools[kind] or { free = {} }
  local ctl = table.remove(pools[kind].free)
  if not ctl then ctl = k.build(parent); ctl.kind = kind; built[kind] = (built[kind] or 0) + 1 end
  probe("acquire", kind, ctl)
  ctl.frame:SetParent(parent)
  ctl.frame:Show()
  if ctl.frame.ctl then restoreBase(ctl) end
  if k.restore then k.restore(ctl) end
  ctl.Bind = function(self, row, host) self.row, self.host = row, host; k.bind(self, row, host) end
  ctl.Release = function(self) probe("release", kind, self); self.frame:Hide(); self.frame:ClearAllPoints(); self.row = nil; if k.release then k.release(self) end; table.insert(pools[kind].free, self) end
  ctl.Compact = function(self) if k.compact then k.compact(self) else compactBase(self) end end
  return ctl
end
SC.kinds = kinds

kinds.header = {
  build = function(parent)
    local f = CreateFrame("Frame", nil, parent); f:SetHeight(30)
    Skin.Surface(f, "surface")
    f.label = text(f, "mono", 10, "ink3"); f.label:SetPoint("LEFT", f, "LEFT", 16, 0)
    f.rule = Skin.Rule(f, "lineSoft"); f.rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); f.rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); f.rule:SetHeight(1)
    return { frame = f }
  end,
  bind = function(ctl, row) ctl.frame.label:SetText((row.name or ""):upper()); ctl.height = 30 end,
}

local function restoreDescription(ctl)
  local f = ctl.frame
  ctl.noImage = nil
  if f.rule then f.rule:Show() end
  f.body:SetWordWrap(false); f.body:SetJustifyV("MIDDLE")
  f.body:ClearAllPoints(); f.body:SetPoint("LEFT", f, "LEFT", 16, 0); f.body:SetPoint("RIGHT", f.glyph, "LEFT", -12, 0)
  ctl.compact = nil
end
kinds.description = {
  restore = restoreDescription,
  build = function(parent)
    local f = CreateFrame("Frame", nil, parent); f:SetHeight(40)
    f.rule = Skin.Rule(f, "lineSoft"); f.rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); f.rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); f.rule:SetHeight(1)
    f.image = f:CreateTexture(nil, "ARTWORK"); f.image:SetPoint("LEFT", f, "LEFT", 16, 0); f.image:SetSize(36, 36)
    f.body = text(f, "ui", 12, "ink2"); f.body:SetPoint("LEFT", f, "LEFT", 16, 0); f.body:SetWordWrap(false)
    f.glyph = CreateFrame("Button", nil, f); f.glyph:SetSize(22, 22); f.glyph:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.glyph.ico = f.glyph:CreateTexture(nil, "ARTWORK"); f.glyph.ico:SetPoint("CENTER")
    Skin.Icon(f.glyph.ico, "info", "ink3"); Skin.IconSize(f.glyph.ico, 16)
    f.glyph:SetScript("OnEnter", function(g) Skin.Icon(g.ico, "info", "accent"); SC.ShowTooltip(g, g.tipTitle, g.tipBody) end)
    f.glyph:SetScript("OnLeave", function(g) Skin.Icon(g.ico, "info", "ink3"); SC.HideTooltip() end)
    f.body:SetPoint("RIGHT", f.glyph, "LEFT", -12, 0)
    return { frame = f }
  end,
  bind = function(ctl, row)
    local f = ctl.frame
    if row.err then f.body:SetText("|cffff5c5c" .. row.name .. "|r"); f.glyph:Hide(); f.image:Hide(); ctl.height = 40; return end
    f.body:Show()
    local first, long = oneLine(row.name)
    f.body:SetText(first)
    f.glyph:SetShown(long)
    f.glyph.tipTitle, f.glyph.tipBody = "Full text", row.name
    local img = (not ctl.noImage) and W.Image(row) or nil
    if img then f.image:SetTexture(img); f.image:Show(); f.body:ClearAllPoints(); f.body:SetPoint("LEFT", f.image, "RIGHT", 12, 0); f.body:SetPoint("RIGHT", f.glyph, "LEFT", -12, 0); f:SetHeight(52)
    else f.image:Hide(); f.body:ClearAllPoints(); f.body:SetPoint("LEFT", f, "LEFT", 16, 0); f.body:SetPoint("RIGHT", f.glyph, "LEFT", -12, 0); f:SetHeight(first == "" and 8 or 40) end
    ctl.height = f:GetHeight()
  end,
}
-- Legends pool separately: the painter keeps its textures on the frame, so a
-- frame that once drew a legend must never come back as a plain description.
kinds.legend = {
  build = kinds.description.build,
  bind = function(ctl, row)
    local f = ctl.frame
    f.body:Hide(); f.glyph:Hide(); f.image:Hide()
    local paint = row.node.dialogControl == "NockShotBarsLegend" and Nock.UI.PaintShotBarsLegend or Nock.UI.PaintReactLegend
    ctl.height = paint and paint(f) or 40
    if ctl.height < 20 then ctl.height = 40 end
    f:SetHeight(ctl.height)
  end,
}

-- "KC  |cff808080(spell 34026)|r" -> "KC", 34026; nil id when the label carries none.
local function spellOfName(name)
  local plain = W.Strip(name)
  local base, kind, id = plain:match("^(.-)%s*%(custom (%a+) (%d+)[^%)]*%)%s*$")
  if not base then base, kind, id = plain:match("^(.-)%s*%((%a+) (%d+)%)%s*$") end
  if base and (kind == "spell" or kind == "item") then return base, tonumber(id), kind end
  return plain, nil, nil
end
-- Labels that name no spell id but have an obvious icon: the weapon-enchant
-- buff is the totem's spell.
local ICON_BY_LABEL = { ["Windfury (weapon enchant)"] = "WINDFURY_TOTEM" }
local function spellIcon(id, label)
  if not id and label then
    local key = ICON_BY_LABEL[label]
    local C = Nock.Constants
    id = key and C and C.SpellID and C.SpellID[key] or nil
  end
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  if GetSpellTexture then return GetSpellTexture(id) end
  return nil
end

SC.SpellOfName = spellOfName
SC.SpellIcon = spellIcon
SC.FirstLine = function(s) local first = oneLine(s); return first end

local function pillToggle(parent)
  local t = CreateFrame("Button", nil, parent)
  t:SetSize(38, 20)
  t.track = t:CreateTexture(nil, "BACKGROUND"); t.track:SetAllPoints(t)
  t.knob = t:CreateTexture(nil, "ARTWORK"); t.knob:SetSize(14, 14); t.knob:SetPoint("LEFT", t, "LEFT", 3, 0)
  local ag = t.knob:CreateAnimationGroup()
  local slide = ag:CreateAnimation("Translation"); slide:SetDuration(0.09); slide:SetSmoothing("OUT")
  t.ag, t.slide = ag, slide
  return t
end

local function paintToggle(t, on, disabled)
  Skin.Paint(t.track, on and "accent" or "line", disabled and 0.45 or 1)
  Skin.Paint(t.knob, on and "accentInk" or "ink3", 1)
  t.knob:ClearAllPoints()
  t.knob:SetPoint("LEFT", t, "LEFT", on and 21 or 3, 0)
end

kinds.toggle = {
  build = function(parent)
    local f = baseRow(parent)
    local t = pillToggle(f.ctl)
    t:SetPoint("RIGHT", f.ctl, "RIGHT", 0, 0)
    local ctl = { frame = f, toggle = t }
    t:SetScript("OnClick", function()
      local row = ctl.row
      if not row or row.disabled then return end
      local okv, v = W.Get(row)
      local nv = not (okv and v and true or false)
      -- slide first, then set; the rebuild lands next frame so the animation is seen
      ctl.toggle.slide:SetOffset(nv and 18 or -18, 0); ctl.toggle.ag:Play()
      local oks, err = W.Set(row, nv)
      if not oks then Nock:Print(("Settings: %s"):format(tostring(err))) end
      ctl.host:AfterSet(row)
    end)
    return ctl
  end,
  bind = function(ctl, row)
    local f = ctl.frame
    if ctl.headerOnly then
      -- the catalog card's header toggle: no label row, just the pill
      f:SetSize(38, 20); f.label:Hide(); f.desc:Hide(); f.glyph:Hide(); f.rule:Hide()
      ctl.toggle:ClearAllPoints(); ctl.toggle:SetPoint("CENTER", f, "CENTER", 0, 0)
    else
      f.label:Show(); f.rule:Show(); ctl.toggle:ClearAllPoints(); ctl.toggle:SetPoint("RIGHT", f.ctl, "RIGHT", 0, 0)
      bindText(ctl, row)
    end
    local okv, v = W.Get(row)
    paintToggle(ctl.toggle, okv and v and true or false, row.disabled)
  end,
  release = function(ctl) ctl.headerOnly = nil; ctl.frame.label:Show(); ctl.frame.rule:Show() end,
  compact = function(ctl)
    local f = ctl.frame
    f.desc:Hide(); f.glyph:Hide(); f.rule:Hide()
    -- a tile: [spell icon] label ............ [pill], one line, never wrapped
    local base, id = spellOfName(ctl.row and ctl.row.name)
    local tex = spellIcon(id, base)
    if not f.icon then
      f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(20, 20); f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      f.iconLine = f:CreateTexture(nil, "BORDER"); f.iconLine:SetPoint("TOPLEFT", f.icon, "TOPLEFT", -1, 1); f.iconLine:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 1, -1)
      Skin.Paint(f.iconLine, "line", 1)
    end
    f.icon:ClearAllPoints(); f.icon:SetPoint("LEFT", f, "LEFT", 1, 0)
    if tex then f.icon:SetTexture(tex); f.icon:Show(); f.iconLine:Show() else f.icon:Hide(); f.iconLine:Hide() end
    f.label:SetText(base or "")
    f.label:SetWordWrap(false)
    f.label:ClearAllPoints()
    f.label:SetPoint("LEFT", f, "LEFT", tex and 28 or 0, 0); f.label:SetPoint("RIGHT", f, "RIGHT", -52, 0)
    Skin.Font(f.label, "ui", 12); Skin.Text(f.label, "ink2")
    f.ctl:ClearAllPoints(); f.ctl:SetPoint("RIGHT", f, "RIGHT", -8, 0); f.ctl:SetSize(38, 20)
    ctl.toggle:ClearAllPoints(); ctl.toggle:SetPoint("RIGHT", f.ctl, "RIGHT", 0, 0)
    f:SetHeight(40); ctl.height = 40; ctl.compact = true
    if id then f.glyph.tipTitle, f.glyph.tipBody = base, ("Spell %d"):format(id) end
  end,
  restore = function(ctl)
    ctl.toggle:ClearAllPoints(); ctl.toggle:SetPoint("RIGHT", ctl.frame.ctl, "RIGHT", 0, 0)
    ctl.frame.label:SetWordWrap(true)
    if ctl.frame.icon then ctl.frame.icon:Hide(); ctl.frame.iconLine:Hide() end
  end,
}

kinds.execute = {
  build = function(parent)
    local f = baseRow(parent)
    local b = Skin.Button(f.ctl, "", "ghost", nil, 32)
    b:SetPoint("RIGHT", f.ctl, "RIGHT", 0, 0)
    local ctl = { frame = f, btn = b }
    b:SetScript("OnClick", function()
      local row = ctl.row
      if not row or row.disabled then return end
      local function go()
        local okf, err = W.Func(row)
        if not okf then Nock:Print(("Settings: %s"):format(tostring(err))) end
        ctl.host:AfterSet(row)
      end
      local ask = W.ConfirmText(row)
      if ask then ctl.host:Confirm(ask, go) else go() end
    end)
    b:SetScript("OnMouseDown", function(bb) if bb.skinFill then Skin.Paint(bb.skinFill, "surface2", 1) end end)
    return ctl
  end,
  bind = function(ctl, row)
    bindText(ctl, row)
    Skin.SetButtonText(ctl.btn, row.name)
    ctl.frame.label:SetShown(row.desc ~= nil and row.desc ~= "")
    if ctl.frame.label:IsShown() then ctl.frame.label:SetText(row.name) end
    Skin.ButtonKind(ctl.btn, row.name:lower():find("reset", 1, true) and "danger" or "ghost")
    ctl.btn:SetAlpha(row.disabled and 0.45 or 1)
    if not ctl.compact then ctl.frame.ctl:SetWidth(math.max(CTL_W, (ctl.btn:GetWidth() or 0))) end
  end,
}
-- Compact form for clustered button rows (Up / Down / Remove): the button IS the row.
local function compactExec(ctl)
  local f = ctl.frame
  f.label:Hide(); f.desc:Hide(); f.glyph:Hide(); f.rule:Hide()
  f:SetHeight(44)
  ctl.btn:ClearAllPoints(); ctl.btn:SetPoint("LEFT", f, "LEFT", 0, 0); ctl.btn:SetPoint("RIGHT", f, "RIGHT", -8, 0)
  -- the button is as wide as its cell, so the text clips inside it instead of spilling out
  ctl.btn.text:ClearAllPoints(); ctl.btn.text:SetPoint("LEFT", ctl.btn, "LEFT", 6, 0); ctl.btn.text:SetPoint("RIGHT", ctl.btn, "RIGHT", -6, 0)
  ctl.height = 44
end
kinds.execute.compact = compactExec
kinds.execute.release = function(ctl)
  local f = ctl.frame
  f.label:Show(); f.rule:Show()
  ctl.btn:SetHeight(32)   -- a form line squeezes it onto the 28 px band
  ctl.btn:ClearAllPoints(); ctl.btn:SetPoint("RIGHT", f.ctl, "RIGHT", 0, 0)
  ctl.btn.text:ClearAllPoints(); ctl.btn.text:SetPoint("CENTER", ctl.btn, "CENTER", 0, 0)
end

local function fmtRange(node, v)
  if node.isPercent then return ("%d %%"):format(math.floor(v * 100 + 0.5)) end
  local step = node.step or 0.01
  if step >= 1 then return ("%d"):format(math.floor(v + 0.5)) end
  if step >= 0.1 then return ("%.1f"):format(v) end
  return ("%.2f"):format(v)
end

kinds.range = {
  build = function(parent)
    local f = baseRow(parent)
    local s = CreateFrame("Slider", nil, f.ctl)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(180, 20)
    s:SetPoint("RIGHT", f.ctl, "RIGHT", -68, 0)
    s.track = s:CreateTexture(nil, "BACKGROUND"); Skin.Paint(s.track, "line", 1); s.track:SetPoint("LEFT", s, "LEFT", 0, 0); s.track:SetPoint("RIGHT", s, "RIGHT", 0, 0); s.track:SetHeight(4)
    s.fill = s:CreateTexture(nil, "BORDER"); Skin.Paint(s.fill, "accent", 1); s.fill:SetPoint("LEFT", s, "LEFT", 0, 0); s.fill:SetHeight(4)
    local thumb = s:CreateTexture(nil, "ARTWORK"); Skin.Paint(thumb, "ink", 1); thumb:SetSize(10, 10)
    s:SetThumbTexture(thumb)
    -- The ring is placed from Lua, NEVER anchored to the thumb: the thumb is a
    -- client-owned region the Slider re-lays out itself, and a region anchored
    -- to it left a dangling entry that crashed the client on the row's next
    -- Hide/ClearAllPoints (three ACCESS_VIOLATIONs, 2026-09-06/09).
    local ring = s:CreateTexture(nil, "OVERLAY"); Skin.Paint(ring, "accent", 1); ring:SetSize(14, 14)
    ring:SetDrawLayer("BORDER", 1)
    local box = CreateFrame("EditBox", nil, f.ctl)
    box:SetSize(56, 26); box:SetPoint("RIGHT", f.ctl, "RIGHT", 0, 0)
    Skin.Surface(box, "ground", "line")
    Skin.Font(box, "mono", 12); box:SetTextColor(Skin.Color("ink")); box:SetJustifyH("RIGHT"); box:SetTextInsets(6, 8, 0, 0); box:SetAutoFocus(false)
    local ctl = { frame = f, slider = s, box = box, ring = ring }
    ctl.sliderW = 180
    -- Fill width + ring centre for value v; the thumb's centre travels from
    -- THUMB_W/2 to width - THUMB_W/2, the same path the client gives it.
    local THUMB_W = 10
    local function place(v, node)
      local min, max = node.min or 0, node.max or 1
      local frac = math.max(0, math.min(1, (v - min) / math.max(1e-9, max - min)))
      local w = ctl.sliderW or 180
      s.fill:SetWidth(math.max(0, frac * w))
      ring:ClearAllPoints(); ring:SetPoint("CENTER", s, "LEFT", THUMB_W / 2 + frac * (w - THUMB_W), 0)
    end
    ctl.place = place
    local function apply(v, fromDrag)
      local row = ctl.row; if not row then return end
      local node = row.node
      local min, max, step = node.min or 0, node.max or 1, node.step or 0.01
      v = math.max(min, math.min(max, min + math.floor((v - min) / step + 0.5) * step))
      local oks, err = W.Set(row, v)
      if not oks then Nock:Print(("Settings: %s"):format(tostring(err))) end
      box:SetText(fmtRange(node, v))
      place(v, node)
      if not fromDrag then ctl.host:AfterSet(row) end
    end
    ctl.apply = apply
    s:SetScript("OnValueChanged", function(sl, v, user) if user and not ctl.binding then apply(v, true) end end)
    s:SetScript("OnMouseUp", function() if ctl.row then ctl.host:AfterSet(ctl.row) end end)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(sl, d) local n = ctl.row and ctl.row.node; if not n then return end; apply(sl:GetValue() + d * (n.bigStep or n.step or 0.01), false) end)
    box:SetScript("OnEnterPressed", function(b)
      local n = ctl.row and ctl.row.node; if not n then return end
      local t = (b:GetText() or ""):gsub("%%", ""):gsub("%s", "")
      local v = tonumber(t); if not v then b:ClearFocus(); return end
      if n.isPercent then v = v / 100 end
      apply(v, false); b:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    return ctl
  end,
  bind = function(ctl, row)
    bindText(ctl, row)
    local n, s = row.node, ctl.slider
    ctl.binding = true
    s:SetMinMaxValues(n.min or 0, n.max or 1)
    s:SetValueStep(n.bigStep or n.step or 0.01)
    s:SetObeyStepOnDrag(true)
    local okv, v = W.Get(row)
    v = (okv and type(v) == "number") and v or (n.min or 0)
    s:SetValue(v)
    ctl.binding = false
    ctl.box:SetText(fmtRange(n, v))
    ctl.place(v, n)
    s:SetEnabled(not row.disabled); ctl.box:SetEnabled(not row.disabled)
  end,
  compactInner = function(ctl, w)
    local sw = math.max(40, w - 56 - 8)
    ctl.sliderW = sw
    ctl.slider:SetWidth(sw)
    ctl.slider:ClearAllPoints(); ctl.slider:SetPoint("LEFT", ctl.frame.ctl, "LEFT", 4, 0)
    ctl.box:ClearAllPoints(); ctl.box:SetPoint("RIGHT", ctl.frame.ctl, "RIGHT", 0, 0)
    local n = ctl.row and ctl.row.node
    if n then ctl.place(ctl.slider:GetValue() or 0, n) end
  end,
  restore = function(ctl)
    ctl.frame.ctl:SetWidth(256)
    ctl.sliderW = 180
    ctl.slider:SetWidth(180)
    ctl.slider:ClearAllPoints(); ctl.slider:SetPoint("RIGHT", ctl.frame.ctl, "RIGHT", -68, 0)
    ctl.box:ClearAllPoints(); ctl.box:SetPoint("RIGHT", ctl.frame.ctl, "RIGHT", 0, 0)
  end,
}

local LSM = LibStub("LibSharedMedia-3.0", true)
local pull   -- shared pullout
local function pullout()
  if pull then return pull end
  pull = CreateFrame("Frame", "NockSettingsPullout", UIParent)
  pull:SetFrameStrata("TOOLTIP"); pull:SetWidth(240)
  Skin.Surface(pull, "surface2", "line")
  pull.rows = {}
  -- A long list (every LibSharedMedia sound, say) is a window of PULL_MAX
  -- rows: the wheel moves it, the thumb on the right says where you are.
  pull.thumb = pull:CreateTexture(nil, "OVERLAY"); Skin.Paint(pull.thumb, "ink3", 0.6); pull.thumb:SetWidth(3); pull.thumb:Hide()
  pull:EnableMouseWheel(true)
  pull:SetScript("OnMouseWheel", function(_, d) if pull.scroll then pull.scroll(d) end end)
  pull:Hide()
  pull:SetScript("OnHide", function() pull.owner = nil end)
  return pull
end
local PULL_ROW_H, PULL_MAX = 26, 14
local function pullRow(i)
  local r = pull.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, pull)
  r:SetHeight(PULL_ROW_H)
  r:SetPoint("LEFT", pull, "LEFT", 1, 0); r:SetPoint("RIGHT", pull, "RIGHT", -1, 0)
  r.hover = r:CreateTexture(nil, "BACKGROUND"); Skin.Paint(r.hover, "raised", 1); r.hover:SetAllPoints(r); r.hover:Hide()
  r.edge = r:CreateTexture(nil, "ARTWORK"); Skin.Paint(r.edge, "accent", 1); r.edge:SetSize(2, PULL_ROW_H); r.edge:SetPoint("LEFT", r, "LEFT", 0, 0); r.edge:Hide()
  r.label = text(r, "ui", 12, "ink2"); r.label:SetPoint("LEFT", r, "LEFT", 10, 0); r.label:SetPoint("RIGHT", r, "RIGHT", -10, 0)
  r.strip = r:CreateTexture(nil, "ARTWORK"); r.strip:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 10, 2); r.strip:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -10, 2); r.strip:SetHeight(14); r.strip:Hide()
  r:SetScript("OnEnter", function(b) b.hover:Show() end)
  r:SetScript("OnLeave", function(b) b.hover:Hide() end)
  r:SetScript("OnClick", function(b) if pull.onPick then pull.onPick(b.key) end; pull:Hide() end)
  r:EnableMouseWheel(true)
  r:SetScript("OnMouseWheel", function(_, d) if pull.scroll then pull.scroll(d) end end)
  pull.rows[i] = r
  return r
end
-- Draw the visible window of the open list (p.keys/p.labels from p.offset).
local function drawPullout(p)
  local keys, labels, mediaType, current = p.keys, p.labels, p.mediaType, p.current
  for _, r in ipairs(p.rows) do r:Hide() end
  local y = 1
  for slot = 1, math.min(#keys - p.offset, PULL_MAX) do
    local i = p.offset + slot
    local r = pullRow(slot)
    r.key = keys[i]
    r.label:SetText(labels[i])
    Skin.Font(r.label, "ui", 12)
    r.strip:Hide()
    if mediaType == "font" and LSM then
      local path = LSM:Fetch("font", keys[i], true)
      if path then r.label:SetFont(path, 13, "") end
      r:SetHeight(PULL_ROW_H)
    elseif mediaType == "statusbar" and LSM then
      local tex = LSM:Fetch("statusbar", keys[i], true)
      if tex then r.strip:SetTexture(tex); r.strip:SetVertexColor(Skin.Color("accent")); r.strip:Show(); r:SetHeight(PULL_ROW_H + 16) else r:SetHeight(PULL_ROW_H) end
      r.label:ClearAllPoints(); r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 10, -6); r.label:SetPoint("RIGHT", r, "RIGHT", -10, 0)
    else
      r.label:ClearAllPoints(); r.label:SetPoint("LEFT", r, "LEFT", 10, 0); r.label:SetPoint("RIGHT", r, "RIGHT", -10, 0)
      r:SetHeight(PULL_ROW_H)
    end
    local cur = (keys[i] == current)
    Skin.Text(r.label, cur and "ink" or "ink2")
    r.edge:SetShown(cur)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -y); r:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -y)
    r:Show()
    y = y + r:GetHeight()
  end
  p:SetHeight(y + 1)
  local th, ty = W.PullThumb(p.offset, #keys, PULL_MAX, y - 1)
  if th then
    p.thumb:SetHeight(th); p.thumb:ClearAllPoints(); p.thumb:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -1 - ty); p.thumb:Show()
  else
    p.thumb:Hide()
  end
end
-- Open the list under `anchor` for `row`; `mediaType` (font/statusbar/nil) drives previews.
local function openPullout(anchor, row, mediaType, current, onPick)
  local p = pullout()
  if p:IsShown() and p.owner == anchor then p:Hide(); return end
  local keys, labels = W.Values(row)
  local curIndex
  for i = 1, #keys do if keys[i] == current then curIndex = i end end
  p.keys, p.labels, p.mediaType, p.current = keys, labels, mediaType, current
  p.offset = W.PullOpenOffset(curIndex, #keys, PULL_MAX)
  p.scroll = function(delta)
    local off = W.PullClamp(p.offset - delta * 3, #p.keys, PULL_MAX)
    if off ~= p.offset then p.offset = off; drawPullout(p) end
  end
  drawPullout(p)
  p.owner, p.onPick = anchor, onPick
  p:ClearAllPoints(); p:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  p:Show()
end
SC.OpenPullout = openPullout
SC.ClosePullout = function()
  if pull then local Probe_shared_pull = pull.IsShown; Probe_shared_pull(pull) end
  if pull then pull:Hide() end
end

local MEDIA_OF = { Nock_LSM_Font = "font", LSM30_Font = "font", Nock_LSM_Statusbar = "statusbar", LSM30_Statusbar = "statusbar" }

kinds.select = {
  build = function(parent)
    local f = baseRow(parent)
    local b = CreateFrame("Button", nil, f.ctl)
    b:SetSize(188, 28); b:SetPoint("RIGHT", f.ctl, "RIGHT", 0, 0)
    Skin.Surface(b, "ground", "line")
    b.label = text(b, "ui", 12, "ink"); b.label:SetPoint("LEFT", b, "LEFT", 10, 0); b.label:SetPoint("RIGHT", b, "RIGHT", -26, 0); b.label:SetWordWrap(false)
    b.caret = b:CreateTexture(nil, "ARTWORK"); b.caret:SetPoint("RIGHT", b, "RIGHT", -8, 0); Skin.Icon(b.caret, "chevron", "ink2"); Skin.IconSize(b.caret, 12)
    local ctl = { frame = f, btn = b }
    b:SetScript("OnClick", function()
      local row = ctl.row; if not row or row.disabled then return end
      local okv, cur = W.Get(row)
      openPullout(b, row, MEDIA_OF[row.node.dialogControl], okv and cur or nil, function(key)
        local oks, err = W.Set(row, key)
        if not oks then Nock:Print(("Settings: %s"):format(tostring(err))) end
        ctl.host:AfterSet(row)
      end)
    end)
    return ctl
  end,
  bind = function(ctl, row)
    bindText(ctl, row)
    local okv, cur = W.Get(row)
    local keys, labels = W.Values(row)
    local shown = ""
    for i, k in ipairs(keys) do if okv and k == cur then shown = labels[i] end end
    ctl.btn.label:SetText(shown)
    ctl.btn:SetAlpha(row.disabled and 0.45 or 1)
  end,
  compactInner = function(ctl, w) ctl.btn:SetWidth(math.max(60, w)) end,
  restore = function(ctl) ctl.btn:SetWidth(188); ctl.btn:ClearAllPoints(); ctl.btn:SetPoint("RIGHT", ctl.frame.ctl, "RIGHT", 0, 0) end,
}

-- One action per press: the client may deliver the press, the release, or both.
local function clickOnce(b)
  local now = GetTime()
  if b._acted and now - b._acted < 0.3 then b._acted = nil; return false end
  b._acted = now
  return true
end

-- segselect: a select with a handful of values drawn as a segmented button
-- group (the current value primary, the rest ghost). Same get/set as select.
kinds.segselect = {
  build = function(parent)
    local f = baseRow(parent)
    local ctl = { frame = f, btns = {} }
    ctl.pick = function(key)
      local row = ctl.row; if not row or row.disabled then return end
      local oks, err = W.Set(row, key)
      if not oks then Nock:Print(("Settings: %s"):format(tostring(err))) end
      ctl.host:AfterSet(row)
    end
    return ctl
  end,
  bind = function(ctl, row)
    bindText(ctl, row)
    local okv, cur = W.Get(row)
    local keys, labels = W.Values(row)
    for _, b in ipairs(ctl.btns) do b:Hide() end
    local x, total = 0, 0
    for i = #keys, 1, -1 do
      local b = ctl.btns[i]
      if not b then
        b = Skin.Button(ctl.frame.ctl, "", "ghost", nil, 26)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetScript("OnClick", function(bb) if clickOnce(bb) then ctl.pick(bb.key) end end)
        ctl.btns[i] = b
      end
      b.key = keys[i]
      Skin.SetButtonText(b, labels[i] or tostring(keys[i]))
      Skin.ButtonKind(b, (okv and keys[i] == cur) and "primary" or "ghost")
      b:ClearAllPoints(); b:SetPoint("RIGHT", ctl.frame.ctl, "RIGHT", -x, 0)
      b:SetAlpha(row.disabled and 0.45 or 1)
      b:Show()
      x = x + (b:GetWidth() or 40) + 4
      total = x
    end
    ctl.frame.ctl:SetWidth(math.max(CTL_W, total))
  end,
  compactInner = function(ctl, w) ctl.frame.ctl:SetWidth(w) end,
}

-- multiselect (one in the tree): a checklist inside the row, one pill per key.
kinds.multiselect = {
  build = function(parent)
    local f = baseRow(parent)
    local ctl = { frame = f, pills = {} }
    return ctl
  end,
  bind = function(ctl, row)
    bindText(ctl, row)
    local keys, labels = W.Values(row)
    for _, p in ipairs(ctl.pills) do p:Hide() end
    local y = 40
    for i, k in ipairs(keys) do
      local p = ctl.pills[i]
      if not p then
        p = pillToggle(ctl.frame); p.lab = text(ctl.frame, "ui", 12, "ink2"); p.lab:SetPoint("RIGHT", p, "LEFT", -10, 0)
        ctl.pills[i] = p
      end
      p.key = k; p.lab:SetText(labels[i])
      p:ClearAllPoints(); p:SetPoint("TOPRIGHT", ctl.frame, "TOPRIGHT", -16, -y)
      local okv, v = W.Get(row, k)
      paintToggle(p, okv and v and true or false, row.disabled)
      p:SetScript("OnClick", function()
        local okv2, v2 = W.Get(row, k)
        local oks, err = W.Set(row, k, not (okv2 and v2 and true or false))
        if not oks then Nock:Print(("Settings: %s"):format(tostring(err))) end
        ctl.host:AfterSet(row)
      end)
      p:Show(); p.lab:Show()
      y = y + 26
    end
    ctl.frame:SetHeight(y + 8); ctl.height = y + 8
  end,
}

local function hex(r, g, b) return ("#%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)) end

-- One OnHide hook on the client's picker, whichever shape; the callback for
-- the current swatch is swapped in per open (a hook per open would stack).
local function hookPickerHide(cpf, onConfirm)
  cpf._nockOnConfirm = onConfirm
  if cpf._nockHooked then return end
  cpf._nockHooked = true
  cpf:HookScript("OnHide", function(self)
    local cb = self._nockOnConfirm
    self._nockOnConfirm = nil
    if cb and not self._nockCancelled then cb() end
    self._nockCancelled = nil
  end)
end

-- Open the client's picker in whichever shape exists; falls back to Nock's own RGBA panel.
local function openColorPicker(r, g, b, a, hasAlpha, onChange, onConfirm, onCancel)
  local cpf = ColorPickerFrame
  if cpf and cpf.SetupColorPickerAndShow then
    cpf:SetupColorPickerAndShow({ r = r, g = g, b = b, opacity = hasAlpha and a or nil, hasOpacity = hasAlpha,
      swatchFunc = function() local nr, ng, nb = cpf:GetColorRGB(); local na = hasAlpha and cpf:GetColorAlpha() or 1; onChange(nr, ng, nb, na) end,
      opacityFunc = function() local nr, ng, nb = cpf:GetColorRGB(); onChange(nr, ng, nb, cpf:GetColorAlpha()) end,
      cancelFunc = function() onCancel() end })
    hookPickerHide(cpf, onConfirm)
    return true
  elseif cpf and cpf.SetColorRGB then
    cpf.hasOpacity = hasAlpha and true or false
    cpf.opacity = hasAlpha and (1 - a) or 0
    cpf.previousValues = { r, g, b, a }
    cpf.func = function() local nr, ng, nb = cpf:GetColorRGB(); local na = hasAlpha and (1 - (OpacitySliderFrame and OpacitySliderFrame:GetValue() or 0)) or 1; onChange(nr, ng, nb, na) end
    cpf.opacityFunc = cpf.func
    cpf.cancelFunc = function(prev) onCancel(); cpf._nockCancelled = true end
    cpf:SetColorRGB(r, g, b)
    cpf:Hide(); cpf:Show()
    hookPickerHide(cpf, onConfirm)
    return true
  end
  return Nock.UI.SettingsRGBA and Nock.UI.SettingsRGBA.Open(r, g, b, a, hasAlpha, onChange, onConfirm, onCancel) or false
end

kinds.color = {
  build = function(parent)
    local f = baseRow(parent)
    local sw = CreateFrame("Button", nil, f.ctl); sw:SetSize(22, 22); sw:SetPoint("RIGHT", f.ctl, "RIGHT", 0, 0)
    Skin.Surface(sw, "ground", "line")
    sw.fill = sw:CreateTexture(nil, "ARTWORK"); sw.fill:SetPoint("TOPLEFT", sw, "TOPLEFT", 1, -1); sw.fill:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", -1, 1)
    local hx = text(f.ctl, "mono", 12, "ink2"); hx:SetPoint("RIGHT", sw, "LEFT", -12, 0)
    local ctl = { frame = f, sw = sw, hx = hx }
    sw:SetScript("OnClick", function()
      local row = ctl.row; if not row or row.disabled then return end
      local okv, r, g, b, a = W.Get(row); if not okv then return end
      a = a or 1
      local hasAlpha = row.node.hasAlpha and true or false
      local orig = { r, g, b, a }
      local function push(nr, ng, nb, na)
        if hasAlpha then W.Set(row, nr, ng, nb, na) else W.Set(row, nr, ng, nb) end
        sw.fill:SetColorTexture(nr, ng, nb, 1); hx:SetText(hex(nr, ng, nb))
      end
      openColorPicker(r, g, b, a, hasAlpha, push, function() ctl.host:AfterSet(row) end, function() push(unpack(orig)); ctl.host:AfterSet(row) end)
    end)
    return ctl
  end,
  bind = function(ctl, row)
    bindText(ctl, row)
    local okv, r, g, b = W.Get(row)
    if not okv or type(r) ~= "number" then r, g, b = 1, 1, 1 end
    ctl.sw.fill:SetColorTexture(r, g or 1, b or 1, 1)
    ctl.hx:SetText(hex(r, g or 1, b or 1))
    ctl.sw:SetAlpha(row.disabled and 0.45 or 1)
  end,
  compactInner = function(ctl, w) if w < 96 then ctl.hx:Hide() else ctl.hx:Show() end end,
  restore = function(ctl) ctl.hx:Show() end,
}



--------------------------------------------------------------------------------
-- chips: a list input (names, spell IDs) as chips with an x each and an add
-- field; the stored string keeps its separator (newlines or commas).
--------------------------------------------------------------------------------
kinds.chips = {
  build = function(parent)
    local f = baseRow(parent)
    local ctl = { frame = f, chips = {} }
    local add = CreateFrame("EditBox", nil, f)
    add:SetAutoFocus(false); Skin.Font(add, "ui", 12); add:SetTextColor(Skin.Color("ink")); add:SetTextInsets(8, 8, 0, 0)
    Skin.Surface(add, "ground", "line"); add:SetSize(140, 26)
    add.hint = text(add, "ui", 12, "ink3"); add.hint:SetPoint("LEFT", add, "LEFT", 8, 0); add.hint:SetText("Add\226\128\166")
    add:SetScript("OnTextChanged", function(b) b.hint:SetShown((b:GetText() or "") == "") end)
    add:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    add:SetScript("OnEnterPressed", function(b)
      local v = (b:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if v == "" then b:ClearFocus(); return end
      local list = {}
      for _, s in ipairs(ctl.list or {}) do list[#list + 1] = s end
      list[#list + 1] = v
      b:SetText(""); b:ClearFocus()
      ctl.commit(list)
    end)
    ctl.add = add
    ctl.commit = function(list)
      local row = ctl.row; if not row then return end
      local v = table.concat(list, ctl.sep or "\n")
      local okv, err = W.Validate(row, v)
      if not okv then Nock:Print(("Settings: %s"):format(tostring(err))); PlaySound(882); return end
      local oks, serr = W.Set(row, v)
      if not oks then Nock:Print(("Settings: %s"):format(tostring(serr))) end
      ctl.host:AfterSet(row)
    end
    return ctl
  end,
  bind = function(ctl, row)
    bindText(ctl, row)
    local f = ctl.frame
    f.ctl:Hide()
    local okv, v = W.Get(row)
    v = (okv and type(v) == "string") and v or ""
    local list = {}
    for piece in v:gmatch("[^\n,]+") do
      local s = piece:gsub("^%s+", ""):gsub("%s+$", "")
      if s ~= "" then list[#list + 1] = s end
    end
    ctl.list = list
    ctl.sep = (v:find("\n", 1, true) or not v:find(",", 1, true)) and "\n" or ", "
    for _, ch in ipairs(ctl.chips) do ch:Hide() end
    local top = f.desc:IsShown() and 44 or 32
    local x, y, lineH = 16, top, 26
    local maxW = (f:GetWidth() or 600) - 32
    for i, s in ipairs(list) do
      local ch = ctl.chips[i]
      if not ch then
        ch = CreateFrame("Frame", nil, f); ch:SetHeight(26)
        Skin.Surface(ch, "raised", "line")
        ch.label = text(ch, "ui", 12, "ink"); ch.label:SetPoint("LEFT", ch, "LEFT", 10, 0); ch.label:SetWordWrap(false)
        ch.x = CreateFrame("Button", nil, ch); ch.x:SetSize(16, 16); ch.x:SetPoint("RIGHT", ch, "RIGHT", -5, 0)
        ch.x.ico = ch.x:CreateTexture(nil, "ARTWORK"); ch.x.ico:SetPoint("CENTER"); Skin.Icon(ch.x.ico, "xmark", "ink3"); Skin.IconSize(ch.x.ico, 10)
        ch.x:RegisterForClicks("AnyUp", "AnyDown")
        ch.x:SetScript("OnClick", function(b)
          if not clickOnce(b) or not ctl.row or ctl.row.disabled then return end
          local l = {}
          for j, s2 in ipairs(ctl.list) do if j ~= ch.index then l[#l + 1] = s2 end end
          ctl.commit(l)
        end)
        ctl.chips[i] = ch
      end
      ch.index = i
      ch.label:SetText(s)
      local w = math.floor((ch.label:GetStringWidth() or 40) + 36)
      if x + w > maxW + 16 and x > 16 then x = 16; y = y + lineH + 6 end
      ch:ClearAllPoints(); ch:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y); ch:SetWidth(w); ch:Show()
      x = x + w + 6
    end
    if x + 140 > maxW + 16 and x > 16 then x = 16; y = y + lineH + 6 end
    ctl.add:ClearAllPoints(); ctl.add:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y); ctl.add:Show()
    ctl.add:SetEnabled(not row.disabled)
    f:SetHeight(y + lineH + 12); ctl.height = f:GetHeight()
  end,
  compact = function(ctl) ctl.compact = true end,
  restore = function(ctl) ctl.frame.ctl:Show() end,
}

--------------------------------------------------------------------------------
-- Nock's own RGBA panel: the fallback when neither ColorPickerFrame shape is
-- present on this client. Three (or four) sliders and a hex box.
--------------------------------------------------------------------------------
local rgbaPanel
Nock.UI.SettingsRGBA = {}
local function rgbaSlider(parent, label, y, onChange)
  local s = CreateFrame("Slider", nil, parent)
  s:SetOrientation("HORIZONTAL"); s:SetSize(170, 16); s:SetPoint("TOPLEFT", parent, "TOPLEFT", 40, y)
  s:SetMinMaxValues(0, 1); s:SetValueStep(0.01); s:SetObeyStepOnDrag(true)
  local track = s:CreateTexture(nil, "BACKGROUND"); Skin.Paint(track, "line", 1); track:SetPoint("LEFT", s, "LEFT", 0, 0); track:SetPoint("RIGHT", s, "RIGHT", 0, 0); track:SetHeight(4)
  local thumb = s:CreateTexture(nil, "ARTWORK"); Skin.Paint(thumb, "ink", 1); thumb:SetSize(10, 10); s:SetThumbTexture(thumb)
  local lab = text(parent, "mono", 11, "ink2"); lab:SetPoint("RIGHT", s, "LEFT", -8, 0); lab:SetText(label)
  s:SetScript("OnValueChanged", function(sl, v, user) if user then onChange() end end)
  return s
end
local function hexOf(r, g, b)
  return ("#%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
function Nock.UI.SettingsRGBA.Open(r, g, b, a, hasAlpha, onChange, onConfirm, onCancel)
  if not rgbaPanel then
    local p = CreateFrame("Frame", "NockSettingsRGBA", UIParent)
    p:SetFrameStrata("TOOLTIP"); p:SetSize(260, 170)
    Skin.Surface(p, "raised", "line")
    p.sw = p:CreateTexture(nil, "ARTWORK"); p.sw:SetSize(28, 28); p.sw:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -12)
    p.hex = CreateFrame("EditBox", nil, p); p.hex:SetSize(80, 24); p.hex:SetPoint("LEFT", p.sw, "RIGHT", 10, 0)
    Skin.Surface(p.hex, "ground", "line"); Skin.Font(p.hex, "mono", 12); p.hex:SetTextColor(Skin.Color("ink")); p.hex:SetTextInsets(6, 6, 0, 0); p.hex:SetAutoFocus(false)
    local function push()
      local rr, gg, bb = p.r:GetValue(), p.g:GetValue(), p.b:GetValue()
      if p.onChange then p.onChange(rr, gg, bb, p.a:IsShown() and p.a:GetValue() or 1) end
      p.sw:SetColorTexture(rr, gg, bb, 1)
      p.hex:SetText(hexOf(rr, gg, bb))
    end
    p.r = rgbaSlider(p, "R", -52, push); p.g = rgbaSlider(p, "G", -76, push); p.b = rgbaSlider(p, "B", -100, push); p.a = rgbaSlider(p, "A", -124, push)
    p.hex:SetScript("OnEnterPressed", function(box)
      local h = (box:GetText() or ""):gsub("#", "")
      local n = tonumber(h, 16)
      if n and #h == 6 then p.r:SetValue(math.floor(n / 65536) / 255); p.g:SetValue((math.floor(n / 256) % 256) / 255); p.b:SetValue((n % 256) / 255); push() end
      box:ClearFocus()
    end)
    p.hex:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    p.ok = Skin.Button(p, "OK", "primary", 64, 26); p.ok:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -12, 12)
    p.cancel = Skin.Button(p, "Cancel", "ghost", 64, 26); p.cancel:SetPoint("RIGHT", p.ok, "LEFT", -8, 0)
    p.ok:SetScript("OnClick", function() p:Hide(); if p.onConfirm then p.onConfirm() end end)
    p.cancel:SetScript("OnClick", function() p:Hide(); if p.onCancel then p.onCancel() end end)
    tinsert(UISpecialFrames, "NockSettingsRGBA")
    rgbaPanel = p
  end
  local p = rgbaPanel
  p.onChange, p.onConfirm, p.onCancel = onChange, onConfirm, onCancel
  p.r:SetValue(r or 1); p.g:SetValue(g or 1); p.b:SetValue(b or 1); p.a:SetValue(a or 1)
  p.a:SetShown(hasAlpha and true or false)
  p.sw:SetColorTexture(r or 1, g or 1, b or 1, 1)
  p.hex:SetText(hexOf(r or 1, g or 1, b or 1))
  p:ClearAllPoints()
  local cx, cy = GetCursorPosition(); local es = UIParent:GetEffectiveScale()
  p:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / es + 8, cy / es - 8)
  p:Show()
  return true
end

kinds.input = {
  build = function(parent)
    local f = baseRow(parent)
    local ctl = { frame = f }
    local function commit()
      local row, box = ctl.row, ctl.box; if not row or not box then return end
      local v = box:GetText() or ""
      local okv, err = W.Validate(row, v)
      if not okv then Nock:Print(("Settings: %s"):format(tostring(err))); PlaySound(882); return end
      local oks, serr = W.Set(row, v)
      if not oks then Nock:Print(("Settings: %s"):format(tostring(serr))) end
      box:ClearFocus()
      ctl.host:AfterSet(row)
    end
    local function wire(box)
      box:SetAutoFocus(false); Skin.Font(box, "ui", 12); box:SetTextColor(Skin.Color("ink"))
      box:SetScript("OnEnterPressed", function(b) if not b:IsMultiLine() or IsControlKeyDown() then commit() end end)
      box:SetScript("OnEscapePressed", function(b) b:ClearFocus(); ctl.host:AfterSet(ctl.row) end)
      box:SetScript("OnEditFocusLost", function(b) if ctl.row and b:IsMultiLine() then commit() end end)
    end
    ctl.wire = wire
    -- One EditBox per shape, each parented ONCE and never moved: the single-
    -- line box on the control cell, the multiline box (made on first use by
    -- bind) inside its own holder + ScrollFrame. The earlier design moved one
    -- box between the cell and the ScrollFrame; re-parenting the ScrollFrame's
    -- registered scroll child away from it left the holder DESTROYED by the
    -- client, and the next rebuild crashed touching it (six dumps 2026-09-06/09,
    -- probe 'Probe_release_input_holder').
    local line = CreateFrame("EditBox", nil, f.ctl)
    wire(line)
    line:SetTextInsets(10, 10, 4, 4)
    Skin.Surface(line, "ground", "line")
    line:SetSize(188, 28); line:SetPoint("RIGHT", f.ctl, "RIGHT", 0, 0)
    ctl.line, ctl.box = line, line
    return ctl
  end,
  bind = function(ctl, row)
    bindText(ctl, row)
    local n, f = row.node, ctl.frame
    local lines = n.multiline and (tonumber(n.multiline) or 4) or 1
    local box
    if lines > 1 then
      if not ctl.multi then
        -- a bare multi-line EditBox collapses to its text height, so it
        -- scrolls inside a sized holder; the ScrollFrame gets its child at once
        local holder = CreateFrame("Frame", nil, f)
        Skin.Surface(holder, "ground", "line")
        local scroll = CreateFrame("ScrollFrame", nil, holder)
        scroll:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -6); scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -8, 6)
        local multi = CreateFrame("EditBox", nil, scroll)
        multi:SetMultiLine(true)
        ctl.wire(multi)
        multi:SetTextInsets(2, 2, 2, 2)
        scroll:SetScrollChild(multi)
        multi:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
        ctl.holder, ctl.scroll, ctl.multi = holder, scroll, multi
      end
      box = ctl.multi
      ctl.line:Hide()
      -- label + desc across the top, the glyph at the top right, the box below
      f.ctl:ClearAllPoints(); f.ctl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -11); f.ctl:SetSize(1, 22)
      f.glyph:ClearAllPoints(); f.glyph:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -11)
      local top = (f.desc:IsShown() and 44 or 32)
      ctl.holder:ClearAllPoints()
      ctl.holder:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -top); ctl.holder:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -top)
      ctl.holder:SetHeight(lines * 16 + 14)
      ctl.holder:Show()
      box:SetWidth(math.max(60, (f:GetWidth() or 600) - 32 - 16))
      f:SetHeight(top + lines * 16 + 14 + 12); ctl.height = f:GetHeight()
    else
      box = ctl.line
      if ctl.holder then ctl.holder:Hide() end
      box:Show()
      box:ClearAllPoints(); box:SetSize(188, 28); box:SetPoint("RIGHT", f.ctl, "RIGHT", 0, 0)
    end
    ctl.box = box
    local okv, v = W.Get(row)
    box:SetText(okv and v ~= nil and tostring(v) or "")
    box:SetCursorPosition(0)
    box:SetEnabled(not row.disabled)
  end,
  compactInner = function(ctl, w)
    if ctl.box == ctl.line then ctl.line:ClearAllPoints(); ctl.line:SetPoint("RIGHT", ctl.frame.ctl, "RIGHT", 0, 0); ctl.line:SetSize(math.max(60, w), 28) end
  end,
}

local REFUSE = { OPENCHAT = true, OPENCHATSLASH = true, TOGGLEGAMEMENU = true }
kinds.keybinding = {
  build = function(parent)
    local f = baseRow(parent)
    local cap = CreateFrame("Button", nil, f.ctl); cap:SetHeight(24); cap:SetPoint("RIGHT", f.ctl, "RIGHT", 0, 0)
    Skin.Surface(cap, "ground", "line")
    cap.label = text(cap, "mono", 11, "ink"); cap.label:SetPoint("CENTER", cap, "CENTER", 0, 0)
    local ctl = { frame = f, cap = cap }
    cap:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cap:SetScript("OnClick", function(_, button)
      local row = ctl.row; if not row or row.disabled then return end
      if button == "RightButton" then W.Set(row, ""); ctl.host:AfterSet(row); return end
      cap.label:SetText("press a key …"); Skin.Text(cap.label, "accent")
      Nock.UI.KeyCapture.Begin(cap, function(s)
        if s ~= nil then local oks, err = W.Set(row, s); if not oks then Nock:Print(("Settings: %s"):format(tostring(err))) end end
        ctl.host:AfterSet(row)
      end, { refuse = REFUSE })
    end)
    return ctl
  end,
  bind = function(ctl, row)
    bindText(ctl, row)
    local okv, v = W.Get(row)
    local s = (okv and type(v) == "string" and v ~= "") and v or "not bound"
    ctl.cap.label:SetText(s); Skin.Text(ctl.cap.label, s == "not bound" and "ink3" or "ink")
    ctl.cap:SetWidth(math.max(72, ctl.cap.label:GetStringWidth() + 20))
    ctl.cap:SetAlpha(row.disabled and 0.45 or 1)
  end,
}
