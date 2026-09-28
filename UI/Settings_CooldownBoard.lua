-- UI/Settings_CooldownBoard.lua
-- The Forever cooldown board on the Nock HUD settings page: packs with undo, the two rows with drag-to-reorder, the catalog tray and its search field.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Skin = Nock.Skin
local Settings = Nock.Settings

local Board = { tab = "All", query = "", target = 1 }
Nock.CooldownBoard = Board
LibStub("AceEvent-3.0"):Embed(Board)

local TILE = { 40, 30 }
local GAP, PAD, CHIP_H, CHIP_COLS = 4, 16, 36, 3
local SEARCH_W, SEARCH_H = 260, 28

local function mod() return Nock:GetModule("Cooldowns", true) end

-- profile.cooldownCustom, as the picker's ctx.customs: { key, id, name }.
-- Key rule matches Core/CooldownEditor.lua's own customKey() for a spell
-- record (the only kind the "Add" flow ever writes).
local function customsOf()
  local out = {}
  local p = Nock.db and Nock.db.profile
  for _, rec in ipairs((p and p.cooldownCustom) or {}) do
    local id = tonumber(rec.id)
    -- Spell records only, same gate as Forever/Cooldowns.lua's customEntries():
    -- Forever has no item cooldown read, so an item record is never tracked.
    if rec.type == "spell" and id and id > 0 then
      local key = (type(rec.key) == "string" and rec.key ~= "" and rec.key) or ("c_spell_" .. id)
      out[#out + 1] = { key = key, id = id, name = Nock.API.SpellName(id) or rec.label or key }
    end
  end
  return out
end

function Board.PickerCtx()
  local m = mod()
  local Cat = Nock.CooldownCatalog
  return {
    entries = Cat.Entries(),
    rows = Nock.CooldownRows.Get(),
    customs = customsOf(),
    known = function(k) return m and m.IsEntryKnown and m:IsEntryKnown(k) end,
    available = function(k) return not (m and m.IsEntryAvailable) or m:IsEntryAvailable(k) end,
    recent = Nock.state.cdRecent,
    nameOf = function(x)
      if type(x) == "table" then
        -- A combined tile (Multi + Aimed, Arcane + Hawk) is named after all
        -- its spells, so it never reads like a second copy of its first one.
        if x.ids and #x.ids > 1 then
          local parts = {}
          for i, id in ipairs(x.ids) do
            parts[i] = Nock.API.SpellName(id) or (x.names and x.names[i]) or tostring(id)
          end
          return table.concat(parts, " + ")
        end
        local id = x.id or (x.ids and x.ids[1])
        return (id and Nock.API.SpellName(id)) or x.name or x.label
      end
      return Nock.API.SpellName(x)
    end,
    -- Cat.ById only knows the catalog's own static ids; a rank id (Arcane
    -- Shot rank 2, say) isn't among them, so fall back to the Cooldowns
    -- module's own base-spell/name resolver -- the same one that links a
    -- cast to its tracked entry -- before giving up and calling it custom.
    -- Without this, typing a rank's id of an already-catalogued spell
    -- created a second, duplicate custom tile for the same spell.
    byId = function(id)
      local k = Cat.ById(id)
      if k then return k end
      local m = mod()
      local e = m and m.Resolve and m:Resolve(id)
      if e and not e.custom then return e.key end
      return nil
    end,
  }
end

-- The keys the grid actually draws: available (own racials only) and tracked.
function Board.Visible(rows)
  local m = mod()
  local out = {}
  for r = 1, #rows do
    out[r] = {}
    for _, k in ipairs(rows[r]) do
      if m and m:GetEntry(k) and m:IsEntryAvailable(k) then out[r][#out[r] + 1] = k end
    end
  end
  return out
end

local function iconOf(key)
  local s = Nock.state.cooldowns[key]
  if s and s.icon then return s.icon end
  local e = mod() and mod():GetEntry(key)
  local id = e and (e.id or (e.ids and e.ids[1]))
  return id and Nock.API.SpellIcon(id) or 134400
end

local function label(parent, role, size, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  Skin.Font(fs, role, size); Skin.Text(fs, color or "ink")
  return fs
end

-- Owned widgets: created once, never recycled, never reparented (the settings
-- window's pooled controls carry the open destroyed-region crash lead).
function Board:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  self.frame = f
  f.packs = {}
  for i, pk in ipairs(Nock.CooldownCatalog.PACKS) do
    local b = Skin.Button(f, pk.name, "ghost", 112, 26)
    b:SetScript("OnClick", function()
      local ctx = Board.PickerCtx()
      -- "Everything I know" reads as known/unknown per entry; when the
      -- Cooldowns module cannot tell yet (ctx.known(k) is nil for every
      -- entry -- the spellbook hasn't loaded), Cat.PackRows("all", ...)
      -- would otherwise still return two EMPTY rows (isKnown never true),
      -- which ApplyPack happily writes -- wiping the grid instead of
      -- refusing. Bail before that call when nothing can be told at all.
      if pk.id == "all" then
        local canTell = false
        for _, e in ipairs(ctx.entries) do
          if ctx.known(e.key) ~= nil then canTell = true; break end
        end
        if not canTell then return end
      end
      Nock.CooldownRows.ApplyPack(pk.id, function(k) return ctx.known(k) == true end)
    end)
    f.packs[i] = b
  end
  f.undoNote = label(f, "ui", 12, "ink2")
  f.undo = Skin.Button(f, "Undo", "primary", 72, 24)
  f.undo:SetScript("OnClick", function() Nock.CooldownRows.Undo() end)
  f.lanes, f.tiles, f.plus = {}, { {}, {} }, {}
  for r = 1, 2 do
    local lane = CreateFrame("Button", nil, f)
    lane.text = label(lane, "uiMedium", 12, "ink2")
    lane.text:SetPoint("LEFT", lane, "LEFT", 0, 0)
    lane:SetScript("OnClick", function() Board.target = r; Board.feedback, Board.feedbackKind = nil, nil; Board:Paint() end)
    f.lanes[r] = lane
    local plus = Skin.Button(f, "+", "ghost", TILE[r], TILE[r])
    plus:SetScript("OnClick", function() Board.target = r; Board.feedback, Board.feedbackKind = nil, nil; Board:Paint() end)
    f.plus[r] = plus
  end
  f.caret = f:CreateTexture(nil, "OVERLAY"); Skin.Paint(f.caret, "accent", 1); f.caret:SetWidth(2); f.caret:Hide()
  f.selName = label(f, "uiMedium", 13, "ink")
  f.selMeta = label(f, "mono", 11, "ink3")
  f.selBtns = {}
  -- ‹/› step by VISIBLE position: a hidden other-race racial can sit between
  -- two visible tiles in the saved row, so stepping by the saved index would
  -- sometimes skip nothing at all. Find the key's slot in Board.vis[ri], move
  -- one visible slot over, then translate back to a saved-row index.
  local function visibleIndex(vis, k)
    for i, vk in ipairs(vis) do if vk == k then return i end end
    return nil
  end
  local acts = {
    { "‹", function(k, rows)
        local ri = Nock.CooldownEditor.Find(rows, k)
        local vis = ri and Board.vis[ri]
        local vi = vis and visibleIndex(vis, k)
        if not vi or vi == 1 then return rows end
        local saved = Nock.CooldownEditor.VisibleToSaved(rows[ri], vis, vi - 1)
        return Nock.CooldownEditor.Move(rows, k, ri, saved)
      end },
    { "›", function(k, rows)
        local ri = Nock.CooldownEditor.Find(rows, k)
        local vis = ri and Board.vis[ri]
        local vi = vis and visibleIndex(vis, k)
        if not vi or vi == #vis then return rows end
        local saved = Nock.CooldownEditor.VisibleToSaved(rows[ri], vis, vi + 2)
        return Nock.CooldownEditor.Move(rows, k, ri, saved)
      end },
    { "Other row", function(k, rows) local ri = Nock.CooldownEditor.Find(rows, k); local o = ri == 1 and 2 or 1; return Nock.CooldownEditor.Move(rows, k, o, #rows[o] + 1) end },
    { "Remove", function(k, rows) Board.sel = nil; return Nock.CooldownEditor.Remove(rows, k) end },
  }
  for i, a in ipairs(acts) do
    local b = Skin.Button(f, a[1], i == 4 and "danger" or "ghost", i == 3 and 84 or (i == 4 and 76 or 32), 24)
    b:SetScript("OnClick", function()
      local k = Board.sel
      if not k then return end
      local rows = Nock.CooldownRows.Get()
      if not Nock.CooldownEditor.Find(rows, k) then return end
      -- Cleared before Set(): NOCK_VISUALS_CHANGED runs Board:OnChanged ->
      -- Board:Paint() synchronously, which would otherwise still read a
      -- stale "Added X to Row N" from an earlier add.
      Board.feedback, Board.feedbackKind = nil, nil
      Nock.CooldownRows.Set(a[2](k, rows))
    end)
    f.selBtns[i] = b
  end
  -- Delete: custom spells only (Remove just takes a key off the grid; Delete
  -- removes the record itself, so it stands apart from the acts() pattern
  -- above, which all operate on rows alone).
  f.selDelete = Skin.Button(f, "Delete", "danger", 64, 24)
  f.selDelete:SetScript("OnClick", function()
    local k = Board.sel
    if not k then return end
    local e = mod() and mod():GetEntry(k)
    if not (e and e.custom) then return end
    local name = Board.PickerCtx().nameOf(e) or e.key
    if Nock.CooldownRows.DeleteCustom(k) then
      Board.sel = nil
      Board.feedback, Board.feedbackKind = "Deleted " .. name, "success"
      Board:Paint()
    end
  end)
  f.tabs = {}
  for i, t in ipairs(Nock.CooldownPicker.TABS) do
    local b = Skin.Button(f, t == "Recent" and "Recently cast" or t, "ghost", t == "Recent" and 104 or 72, 24)
    b:SetScript("OnClick", function()
      Board.tab = t
      Board.feedback, Board.feedbackKind = nil, nil
      -- Settings:RefreshLater alone can stall indefinitely while the search
      -- box holds focus (Settings.Busy() == "editbox"); paint the board
      -- directly, same as OnChanged does, so the tab switch is never stuck.
      Board:Paint()
      Settings:RefreshLater("cdboard")
    end)
    f.tabs[i] = b
  end
  local box = CreateFrame("EditBox", nil, f)
  box:SetAutoFocus(false); box:SetSize(SEARCH_W, SEARCH_H); box:SetTextInsets(10, 10, 0, 0)
  Skin.Font(box, "ui", 12); box:SetTextColor(Skin.Color("ink"))
  Skin.Surface(box, "surface", "line")
  box.placeholder = label(box, "ui", 12, "ink3")
  box.placeholder:SetPoint("LEFT", box, "LEFT", 10, 0)
  box.placeholder:SetJustifyH("LEFT")
  box.placeholder:SetText("Search spells, or type a spell ID")
  box:SetScript("OnTextChanged", function(b, user)
    b.placeholder:SetShown((b:GetText() or "") == "")
    if user then
      Board.query = b:GetText() or ""
      Board.feedback, Board.feedbackKind = nil, nil
      Board:PaintChips()
      Board:PaintStatus()
    end
  end)
  box:SetScript("OnEnterPressed", function(b) Board:ActivateFirst(); b:ClearFocus() end)
  box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
  box:SetScript("OnEditFocusGained", function(b) Skin.Surface(b, "surface", "accent") end)
  box:SetScript("OnEditFocusLost", function(b) Skin.Surface(b, "surface", "line") end)
  f.box = box
  f.status = label(f, "ui", 12, "ink3")
  f.combat = label(f, "ui", 12, "wait"); f.combat:SetText("Editing resumes when combat ends.")
  f.chips = {}
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "OnChanged")
  self:RegisterMessage("NOCK_CD_RECENT", "OnChanged")
  self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnChanged")
  self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnChanged")
  -- A pack's one-step undo does not survive the window closing: reopening
  -- later and hitting Undo on a stale pre-pack snapshot would be a surprise.
  if Settings.frame and Settings.frame.HookScript then
    Settings.frame:HookScript("OnHide", function() Nock.CooldownRows.ClearUndo() end)
  end
end

function Board:OnChanged()
  if not (self.frame and self.frame:IsShown()) then return end
  -- Settings:RefreshLater alone can stall indefinitely: Settings.Busy()
  -- returns "editbox" while the add box holds focus, so a pack pill, Undo,
  -- the ‹ › / Other row / Remove buttons or a board drag-drop would change
  -- the HUD but never repaint the board itself. The board owns its widgets,
  -- so paint them directly here too; RefreshLater still covers anything
  -- else on the settings page that reacts to this change.
  Board:Paint()
  Settings:RefreshLater("cdboard")
end

local function tileButton(r, i)
  local f = Board.frame
  local t = f.tiles[r][i]
  if t then return t end
  t = CreateFrame("Button", nil, f)
  t:SetSize(TILE[r], TILE[r])
  t.icon = t:CreateTexture(nil, "ARTWORK"); t.icon:SetAllPoints(t); t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  t.ring = t:CreateTexture(nil, "OVERLAY"); t.ring:SetPoint("TOPLEFT", -2, 2); t.ring:SetPoint("BOTTOMRIGHT", 2, -2)
  Skin.Paint(t.ring, "accent", 0.45); t.ring:SetDrawLayer("BACKGROUND"); t.ring:Hide()
  -- "Already placed" pulse: one dip-and-return on the ring's alpha, no
  -- OnUpdate script (project rule).
  t.pulse = t.ring:CreateAnimationGroup()
  local dip = t.pulse:CreateAnimation("Alpha")
  dip:SetOrder(1); dip:SetDuration(0.12); dip:SetFromAlpha(1); dip:SetToAlpha(0.15); dip:SetSmoothing("OUT")
  local rise = t.pulse:CreateAnimation("Alpha")
  rise:SetOrder(2); rise:SetDuration(0.12); rise:SetFromAlpha(0.15); rise:SetToAlpha(1); rise:SetSmoothing("IN")
  t:SetScript("OnMouseDown", function(self, btn) if btn == "LeftButton" and self.key then Nock.CooldownDrag:Press(Board, self.key) end end)
  t:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" then Nock.CooldownDrag:Release() end end)
  t:SetScript("OnEnter", function(self)
    if not self.key then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local ctx = Board.PickerCtx()
    local found
    for _, it in ipairs(Nock.CooldownPicker.TrayItems(ctx, "All", "")) do
      if it.key == self.key then found = it; break end
    end
    if found then
      GameTooltip:SetText(found.name)
      GameTooltip:AddLine(Nock.CooldownPicker.Meta(found), 0.7, 0.7, 0.7)
    else
      -- a custom entry: not in the catalog, so TrayItems never lists it.
      local e = mod() and mod():GetEntry(self.key)
      local id = e and (e.id or (e.ids and e.ids[1]))
      GameTooltip:SetText((id and Nock.API.SpellName(id)) or self.key)
    end
    GameTooltip:Show()
  end)
  t:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.tiles[r][i] = t
  return t
end

local function chipButton(i)
  local f = Board.frame
  local c = f.chips[i]
  if c then return c end
  c = CreateFrame("Button", nil, f)
  c:SetHeight(CHIP_H)
  c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints(c)
  c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(CHIP_H - 8, CHIP_H - 8); c.icon:SetPoint("LEFT", c, "LEFT", 4, 0)
  c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  c.name = label(c, "ui", 12, "ink"); c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, -2); c.name:SetPoint("RIGHT", c, "RIGHT", -44, 0)
  c.name:SetJustifyH("LEFT"); c.name:SetWordWrap(false)
  c.meta = label(c, "mono", 10, "ink3"); c.meta:SetPoint("BOTTOMLEFT", c.icon, "BOTTOMRIGHT", 8, 2)
  c.state = label(c, "ui", 11, "accent"); c.state:SetPoint("RIGHT", c, "RIGHT", -8, 0)
  c:SetScript("OnClick", function(self)
    if Board.frame then Board.frame.box:ClearFocus() end
    Board:AddItem(self.item)
  end)
  f.chips[i] = c
  return c
end

-- The name a feedback line reports for `it`: a tray item already carries its
-- display name, but the add-as-custom chip's own `.name` is the "+ Add ..."
-- label text, not the spell's name, so it stashes the plain one separately.
local function nameFor(it)
  if it.spellName then return it.spellName end
  if it.name then return it.name end
  if it.key then
    local e = mod() and mod():GetEntry(it.key)
    return (e and Board.PickerCtx().nameOf(e)) or it.key
  end
  if it.id then return Nock.API.SpellName(it.id) or ("Spell " .. it.id) end
  return "?"
end

function Board:AddItem(it)
  if not it then return end
  -- Checked before AddCustomSpell: that call writes the custom record
  -- unconditionally, so a combat lockdown must bail before it, not after
  -- (else a stray custom entry lands with nothing placing it in a row).
  if InCombatLockdown() then return end
  local name = nameFor(it)
  local rows = Nock.CooldownRows.Get()
  local key = it.key or Nock.CooldownRows.AddCustomSpell(it.id)
  local placed = Nock.CooldownEditor.Find(rows, key)
  if placed then
    Board.sel = key
    Board.feedback, Board.feedbackKind = name .. " is already in Row " .. placed, "already"
    Board:Paint()
    Board:PulseRing(key)
    return
  end
  local out = Nock.CooldownEditor.Add(rows, Board.target, key)
  if Nock.CooldownRows.Set(out) then
    Board.sel = key
    Board.feedback, Board.feedbackKind = "Added " .. name .. " to Row " .. Board.target, "success"
    -- Set() only broadcasts NOCK_VISUALS_CHANGED; the settings window's own
    -- re-render is deferred while the search box holds focus (Settings.Busy()
    -- returns "editbox"), so paint the board directly rather than wait for it.
    Board:Paint()
  end
end

-- Enter in the search field activates whatever chip is currently first --
-- the add-as-custom chip when the query resolves outside the catalog, else
-- the top filtered result (see Board:PaintChips).
function Board:ActivateFirst()
  if InCombatLockdown() then return end
  local q = Board.query
  if q == "" then return end
  local it = Board.items and Board.items[1]
  if not it then
    if Board.unavailable then
      Board.feedback, Board.feedbackKind = Board.unavailable .. " isn't available to this character", "warn"
    else
      Board.feedback, Board.feedbackKind = "No spell found for '" .. q .. "'", "warn"
    end
    Board:Paint()
    return
  end
  Board:AddItem(it)
  Board.query = ""
  if self.frame then
    self.frame.box:SetText("")
    -- SetText("") fires OnTextChanged with user = false, so it never
    -- refilters on its own; repaint with the now-empty query explicitly.
    Board:PaintChips()
  end
end

-- Height is fixed per content so the card sizes before painting.
function Board.Height(nChips)
  local rowsH = TILE[1] + 10 + TILE[2]
  return 26 + 10 + 24 + 10 + rowsH + 14 + 28 + 14 + 26 + 10 + 26 + 10 + math.ceil(nChips / CHIP_COLS) * (CHIP_H + 6)
end

function Settings:DrawCooldownBoard(c, y, width)
  if not Board.frame then Board:Create(self.col.content) end
  local f = Board.frame
  local ctx = Board.PickerCtx()
  -- sized for the whole tab: typing a filter only ever shrinks the chip grid,
  -- except for the add-as-custom chip a typed id can prepend even on an
  -- empty tab, so one extra slot is always reserved for it.
  local h = Board.Height(#Nock.CooldownPicker.TrayItems(ctx, Board.tab, "") + 1)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
  f:SetSize(width - 2 * PAD, h)
  Board.width = width - 2 * PAD
  f:SetFrameLevel(c:GetFrameLevel() + 5)
  f:Show()
  Board:Paint()
  return h + 8
end

function Settings:HideCooldownBoard()
  if Nock.CooldownDrag.host == Board then Nock.CooldownDrag:Cancel() end
  if Board.frame then Board.frame:Hide(); Board.frame:ClearAllPoints() end
end

local FEEDBACK_COLOR = { success = "accent", already = "ink2", warn = "wait" }

function Board:PaintStatus()
  local f = self.frame
  if Board.feedback then
    f.status:SetText(Board.feedback)
    Skin.Text(f.status, FEEDBACK_COLOR[Board.feedbackKind] or "ink2")
  else
    f.status:SetText("Adding to " .. (Board.target == 1 and "Row 1 · large" or "Row 2 · small"))
    Skin.Text(f.status, "ink3")
  end
end

-- The tile pulses once (Board:AddItem, "already in Row N"); no OnUpdate,
-- just Play() on the AnimationGroup tileButton() built for it.
function Board:PulseRing(key)
  local f = self.frame
  if not (f and Board.vis) then return end
  for r = 1, 2 do
    for i, k in ipairs(Board.vis[r] or {}) do
      if k == key then
        local t = f.tiles[r][i]
        if t and t.pulse then t.pulse:Stop(); t.pulse:Play() end
        return
      end
    end
  end
end

-- The special "add it" chip for a query that resolves outside the catalog
-- and every existing custom spell (Nock.CooldownPicker.Resolve returning
-- {id = n} with no key). `.name` is the row's own label; `.spellName` is the
-- plain name AddItem's feedback line reports once it is placed.
local function addChip(id)
  local spellName = Nock.API.SpellName(id) or ("Spell " .. id)
  return { addCustom = true, id = id, spellName = spellName, meta = "ID " .. id,
           name = "+ Add " .. spellName .. " as a custom tile" }
end

function Board:PaintChips()
  local f = self.frame
  local ctx = Board.PickerCtx()
  local q = Board.query
  local isDigits = q:match("^%d+$") ~= nil
  -- Digits name a spell precisely: show the one matching chip (catalog or
  -- custom) across every tab instead of running the fuzzy name filter.
  local items = isDigits and {} or Nock.CooldownPicker.TrayItems(ctx, Board.tab, q)
  -- Set when a digits query resolves to a real key that TrayItems never
  -- lists (another race's racial, hidden by ctx.available): Board:ActivateFirst
  -- reports it by name instead of a flat "No spell found".
  Board.unavailable = nil
  if q ~= "" then
    local names = Nock.ForeverSpellbookNames and Nock.ForeverSpellbookNames() or {}
    local res = Nock.CooldownPicker.Resolve(q, names, ctx)
    if res and res.key then
      if isDigits then
        local found
        for _, it in ipairs(Nock.CooldownPicker.TrayItems(ctx, "All", "")) do
          if it.key == res.key then found = it; break end
        end
        if found then
          items[1] = found
        else
          local e = mod() and mod():GetEntry(res.key)
          Board.unavailable = (e and ctx.nameOf(e)) or res.key
        end
      end
    elseif res and res.id then
      table.insert(items, 1, addChip(res.id))
    end
  end
  Board.items = items
  local colW = math.floor((Board.width - (CHIP_COLS - 1) * 6) / CHIP_COLS)
  for i, it in ipairs(Board.items) do
    local c = chipButton(i)
    c.item = it
    local col, line = (i - 1) % CHIP_COLS, math.floor((i - 1) / CHIP_COLS)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", f.chipTop, "BOTTOMLEFT", col * (colW + 6), -line * (CHIP_H + 6))
    c:SetWidth(colW)
    c.icon:SetTexture(it.key and iconOf(it.key) or Nock.API.SpellIcon(it.id))
    if c.icon.SetDesaturated then c.icon:SetDesaturated(it.known == false) end
    c.name:SetText(it.name)
    Skin.Text(c.name, it.addCustom and "accent" or "ink")
    c.meta:SetText(it.addCustom and it.meta or Nock.CooldownPicker.Meta(it))
    c.state:SetText(it.placedRow and ("Row " .. it.placedRow) or "")
    Skin.Paint(c.bg, it.placedRow and "surface" or "surface2", 1)
    c:SetAlpha(it.placedRow and 0.6 or 1)
    c:Show()
  end
  for i = #Board.items + 1, #f.chips do f.chips[i]:Hide(); f.chips[i].item = nil end
end

function Board:Paint()
  local f = self.frame
  if not f then return end
  -- PLAYER_REGEN_DISABLED fires before InCombatLockdown() actually flips, so
  -- a repaint driven straight off that event (rather than a later tick) could
  -- read the old, pre-combat value; UnitAffectingCombat catches that leading
  -- edge.
  local combat = InCombatLockdown() or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
  local x, top = 0, 0
  for i, b in ipairs(f.packs) do
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -top); x = x + b:GetWidth() + 6
    b:SetEnabled(not combat)
  end
  top = top + 36
  f.undoNote:ClearAllPoints(); f.undoNote:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top - 4)
  f.undo:ClearAllPoints(); f.undo:SetPoint("LEFT", f.undoNote, "RIGHT", 10, 0)
  f.combat:ClearAllPoints(); f.combat:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top - 4)
  f.combat:SetShown(combat)
  local undo = Nock.CooldownRows.CanUndo() and not combat
  f.undoNote:SetText(undo and "Pack applied: your previous rows are one click away." or "")
  f.undo:SetShown(undo)
  top = top + 34
  local rows = Nock.CooldownRows.Get()
  if Board.sel and not Nock.CooldownEditor.Find(rows, Board.sel) then Board.sel = nil end
  Board.vis = Board.Visible(rows)
  local m = mod()
  for r = 1, 2 do
    local lane = f.lanes[r]
    lane:ClearAllPoints(); lane:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top); lane:SetSize(96, TILE[r])
    lane.text:SetText(r == 1 and "Row 1 · large" or "Row 2 · small")
    Skin.Text(lane.text, Board.target == r and "accent" or "ink2")
    local tx = 104
    for i, key in ipairs(Board.vis[r]) do
      local t = tileButton(r, i)
      t.key = key
      t:ClearAllPoints(); t:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -top)
      t.icon:SetTexture(iconOf(key))
      local unknown = m and m.IsEntryKnown and m:IsEntryKnown(key) == false
      if t.icon.SetDesaturated then t.icon:SetDesaturated(unknown) end
      t.icon:SetAlpha(unknown and 0.4 or 1)
      t.ring:SetShown(Board.sel == key)
      t:Show()
      tx = tx + TILE[r] + GAP
    end
    for i = #Board.vis[r] + 1, #f.tiles[r] do f.tiles[r][i]:Hide(); f.tiles[r][i].key = nil end
    f.plus[r]:ClearAllPoints(); f.plus[r]:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -top)
    top = top + TILE[r] + 10
  end
  top = top + 4
  local e = Board.sel and m and m:GetEntry(Board.sel)
  f.selName:ClearAllPoints(); f.selName:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top - 6)
  f.selName:SetText(e and (Board.PickerCtx().nameOf(e) or e.key) or "Click a tile to move or remove it; drag it to reorder.")
  f.selMeta:ClearAllPoints(); f.selMeta:SetPoint("LEFT", f.selName, "RIGHT", 10, 0)
  local selMeta = ""
  if Board.sel then
    local ctx = Board.PickerCtx()
    for _, it in ipairs(Nock.CooldownPicker.TrayItems(ctx, "All", "")) do
      if it.key == Board.sel then selMeta = Nock.CooldownPicker.Meta(it); break end
    end
  end
  f.selMeta:SetText(selMeta)
  -- The whole button run right-aligns flush with the frame's own right edge;
  -- when Delete joins it (custom spell selected), its width + gap has to be
  -- folded into selBtns[1]'s offset too, or Delete spills past the edge.
  local isCustom = e ~= nil and e.custom == true
  local tailExtra = isCustom and (f.selDelete:GetWidth() + 6) or 0
  local bx = nil
  for i, b in ipairs(f.selBtns) do
    b:ClearAllPoints()
    if i == 1 then b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(f.selBtns[2]:GetWidth() + f.selBtns[3]:GetWidth() + f.selBtns[4]:GetWidth() + 18 + tailExtra), -top)
    else b:SetPoint("LEFT", bx, "RIGHT", 6, 0) end
    b:SetShown(e ~= nil); b:SetEnabled(not combat)
    bx = b
  end
  f.selDelete:ClearAllPoints(); f.selDelete:SetPoint("LEFT", f.selBtns[4], "RIGHT", 6, 0)
  f.selDelete:SetShown(isCustom); f.selDelete:SetEnabled(not combat)
  top = top + 42
  -- Search field first, tabs follow to its right (the field is the way in;
  -- the tabs just narrow what it searches).
  f.box:ClearAllPoints(); f.box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
  local tx = SEARCH_W + 10
  for i, b in ipairs(f.tabs) do
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -top - 2); tx = tx + b:GetWidth() + 4
    Skin.ButtonKind(b, Nock.CooldownPicker.TABS[i] == Board.tab and "primary" or "ghost")
  end
  top = top + 36
  f.status:ClearAllPoints(); f.status:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
  self:PaintStatus()
  top = top + 22
  f.chipTop = f.chipTop or f:CreateTexture(nil, "BACKGROUND")
  f.chipTop:ClearAllPoints(); f.chipTop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top); f.chipTop:SetSize(1, 1)
  self:PaintChips()
end

-- CooldownDrag host
function Board:DragRows()
  local out = {}
  for r = 1, 2 do
    local lane = self.frame.lanes[r]
    local s = lane:GetEffectiveScale()
    local row = { index = r, top = lane:GetTop() * s, bottom = lane:GetBottom() * s,
                  left = (lane:GetRight() + 8) * s, right = self.frame.plus[r]:GetRight() * s, tiles = {} }
    for i, key in ipairs(self.vis[r]) do
      local t = self.frame.tiles[r][i]
      row.tiles[i] = { l = t:GetLeft() * s, r = t:GetRight() * s, key = key }
    end
    out[r] = row
  end
  return out
end

function Board:DragCaret(ri, ii)
  local f, caret = self.frame, self.frame.caret
  if not ri then caret:Hide(); return end
  local r = self.vis[ri]
  -- Never index a hidden spare tile left over in the pool from a longer row:
  -- past the last visible slot always means the row's own + button.
  local anchor = (ii <= #r and f.tiles[ri][ii]) or f.plus[ri]
  if not anchor then caret:Hide(); return end
  caret:ClearAllPoints()
  caret:SetPoint("TOP", anchor, "TOPLEFT", -2, 2)
  caret:SetHeight(TILE[ri] + 4)
  caret:Show()
end

function Board:DragDrop(key, ri, ii)
  local rows = Nock.CooldownRows.Get()
  local E = Nock.CooldownEditor
  local saved = E.VisibleToSaved(rows[ri], self.vis[ri], ii)
  Board.sel = key
  -- cleared before Set: Set repaints the board synchronously
  Board.feedback, Board.feedbackKind = nil, nil
  Nock.CooldownRows.Set(E.Move(rows, key, ri, saved))
end

function Board:TileClick(key)
  Board.sel = key
  Board.feedback, Board.feedbackKind = nil, nil
  self:Paint()
end
function Board:DragIcon(key) return iconOf(key) end
