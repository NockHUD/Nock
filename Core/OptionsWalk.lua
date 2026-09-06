-- Core/OptionsWalk.lua
-- Pure walker over the AceConfig options table: nav → pages → tabs → cards → rows, with AceConfigDialog's info/inheritance/order/width semantics and no frames.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local W = {}
Nock.OptionsWalk = W

W.WIDTH_UNIT = 170
-- The width AceConfigDialog flowed sized rows into (its content column in the
-- Blizzard panel): a cooldown-grid entry (1.4 + 0.4 + 0.5 + 0.3 units = 442 px)
-- got a line of its own there, and keeps it here whatever the window's width.
W.FLOW_WIDTH = 600
W.ORDER_DEFAULT = 100
W.UI_TYPE, W.UI_NAME = "dialog", "NockSettings-1.0"
-- Root children that are families (sidebar headers) rather than pages. Their
-- own leaves (hud.hudMode, the intros) are not rendered: General carries them.
W.FAMILY_KEYS = { hud = true, alerts = true, trackers = true, utilities = true }
W.SYSTEM_KEYS = { experimental = true, profiles = true }

-- Simple hides rows tagged advanced (own, inherited from a group, or positional
-- under an advanced header). The window sets the mode before every render;
-- the walker never reads the db itself.
W.MODE = "advanced"
function W.SetMode(mode) W.MODE = mode == "simple" and "simple" or "advanced" end
function W.Simple() return W.MODE == "simple" end

-- Per-node metadata the AceConfig validator would reject as a node key
-- (`advanced`, `card`, header `actions`): a weak side table, written by
-- Config/OptionsAdvanced.lua. Test tables may still carry `advanced = true`
-- literally; both spellings count.
W.META = setmetatable({}, { __mode = "k" })
function W.Meta(node) return W.META[node] end
function W.SetMeta(node, key, value)
  local m = W.META[node]
  if not m then m = {}; W.META[node] = m end
  m[key] = value
end
local function isAdv(node)
  if node.advanced == true then return true end
  local m = W.META[node]
  return m ~= nil and m.advanced == true
end
W.IsAdvanced = isAdv
local function metaOf(node, key)
  local m = W.META[node]
  if m and m[key] ~= nil then return m[key] end
  return node[key]
end

-- Members AceConfigDialog inherits down the path (ACD isInherited) and the
-- members that are literal strings even when a handler is present.
local INHERITED = { set = true, get = true, func = true, confirm = true, validate = true, disabled = true, hidden = true }
local STRING_LITERAL = { name = true, desc = true, icon = true, usage = true, width = true, image = true, fontSize = true }
local CONTROL_TYPES = { toggle = true, range = true, select = true, multiselect = true, color = true, input = true, execute = true, keybinding = true }

local function strip(s)
  s = tostring(s or "")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", "")
  s = s:gsub("%s*%(active%)%s*$", "")
  return s
end
W.Strip = strip

--------------------------------------------------------------------------------
-- The table. Fetched through the registry so its validation runs once for
-- our uiType and so ConfigTableChange is the same event the old dialog used.
--------------------------------------------------------------------------------
function W.Root(appName)
  local reg = LibStub("AceConfigRegistry-3.0", true)
  if not reg then return nil end
  local root = reg:GetOptionsTable(appName, W.UI_TYPE, W.UI_NAME)
  W._root = root
  return root
end

function W.Subscribe(appName, owner, fn)
  local reg = LibStub("AceConfigRegistry-3.0", true)
  if reg and reg.RegisterCallback then reg.RegisterCallback(owner, "ConfigTableChange", fn) end
end

function W.NotifyChange(appName)
  local reg = LibStub("AceConfigRegistry-3.0", true)
  if reg then reg:NotifyChange(appName) end
end

--------------------------------------------------------------------------------
-- Ordering: AceConfigDialog's comparator (order asc, default 100, negatives
-- last, then upper-cased name, then key).
--------------------------------------------------------------------------------
local function orderOf(e)
  local o = e.order
  if type(o) == "function" then local okc, v = pcall(o); o = okc and v or nil end
  if type(o) ~= "number" then o = W.ORDER_DEFAULT end
  return o
end
function W.Compare(a, b)
  local oa, ob = orderOf(a), orderOf(b)
  if oa == ob then
    local na, nb = strip(type(a.name) == "string" and a.name or ""):upper(), strip(type(b.name) == "string" and b.name or ""):upper()
    if na == nb then return tostring(a.key) < tostring(b.key) end
    return na < nb
  end
  if oa < 0 then
    if ob < 0 then return oa < ob end
    return false
  end
  if ob < 0 then return true end
  return oa < ob
end

-- Sorted child entries {key, node} of a group; every table with a .type is a child.
function W.Children(node)
  local out = {}
  for k, v in pairs(node.args or {}) do
    if type(v) == "table" and v.type then out[#out + 1] = { key = k, node = v, order = v.order, name = v.node and nil or v.name } end
  end
  for i = 1, #out do out[i].name = out[i].node.name end
  table.sort(out, W.Compare)
  return out
end

--------------------------------------------------------------------------------
-- The info table and member resolution.
--------------------------------------------------------------------------------
local function makeInfo(appName, path, node, handler, root)
  local info = {}
  for i = 1, #path do info[i] = path[i] end
  info[0] = appName
  info.appName = appName
  info.options = root or W._root
  info.arg = node.arg
  info.handler = handler
  info.option = node
  info.type = node.type
  info.uiType = W.UI_TYPE
  info.uiName = W.UI_NAME
  return info
end

-- Call a member: function -> member(info, ...); string -> handler[member](handler, info, ...).
-- Returns ok, r1, r2, r3, r4.
function W.Call(member, info, ...)
  if type(member) == "function" then return pcall(member, info, ...) end
  if type(member) == "string" then
    local h = info and info.handler
    if not (h and type(h[member]) == "function") then
      return false, ("Method %s doesn't exist in handler"):format(member)
    end
    return pcall(h[member], h, info, ...)
  end
  return true, member
end

-- Resolve a node member: literal or called. `inherited` is the walk's current
-- inherited-member set (see walkInherit). Returns ok, value.
function W.Member(node, key, info, inherited)
  local v = node[key]
  if v == nil and inherited and INHERITED[key] then v = inherited[key] end
  if v == nil then return true, nil end
  if type(v) == "string" and (STRING_LITERAL[key] or not (info and info.handler)) then return true, v end
  if type(v) == "function" or (type(v) == "string" and info and info.handler) then return W.Call(v, info) end
  return true, v
end

local function walkInherit(parentInh, node)
  local inh = {}
  for k in pairs(INHERITED) do
    if node[k] ~= nil then inh[k] = node[k] else inh[k] = parentInh and parentInh[k] end
  end
  -- advanced accumulates down the tree (a group tagged advanced taints every descendant)
  inh.advanced = (parentInh ~= nil and parentInh.advanced == true) or isAdv(node)
  return inh
end

--------------------------------------------------------------------------------
-- Rows.
--------------------------------------------------------------------------------
local function widthOf(node)
  local w = node.width
  if w == "full" then return "fill", nil end
  if w == "half" then return "half", math.floor(W.WIDTH_UNIT / 2) end
  if type(w) == "number" then return w, math.floor(W.WIDTH_UNIT * w + 0.5) end
  if node.type == "description" or node.type == "header" then return "fill", nil end
  if w == "default" or w == nil then return "default", W.WIDTH_UNIT end
  return "default", W.WIDTH_UNIT
end

local function makeRow(ctx, key, node, path, inherited)
  local info = makeInfo(ctx.appName, path, node, ctx.handler, ctx.root)
  local row = { key = key, node = node, path = path, type = node.type, info = info, inherited = inherited,
                isControl = CONTROL_TYPES[node.type] == true, noGet = (node.get == false) }
  local okn, name = W.Member(node, "name", info)
  if not okn then row.err = tostring(name); row.name = "Error: " .. tostring(name)
  else row.name = name == nil and "" or tostring(name) end
  local okd, desc = W.Member(node, "desc", info)
  row.desc = okd and (type(desc) == "string" and desc or nil) or nil
  local okh, hidden = W.Member(node, "hidden", info, inherited)
  row.hidden = okh and (hidden == true) or false
  local okx, dis = W.Member(node, "disabled", info, inherited)
  row.disabled = okx and (dis == true) or false
  row.advanced = isAdv(node) or (inherited ~= nil and inherited.advanced == true) or false
  row.chips = metaOf(node, "chips") == true
  row.segmented = metaOf(node, "segmented") == true
  row.width, row.unit = widthOf(node)
  return row
end
W.MakeRow = makeRow

-- Flow rows into lines: fill-width rows own a line; sized rows pack left to
-- right until the content width overflows (ACD's flow, GUI:707-790).
function W.Flow(rows, contentWidth)
  local lines, cur, used = {}, nil, 0
  local width = math.min(contentWidth or W.FLOW_WIDTH, W.FLOW_WIDTH)
  for _, r in ipairs(rows) do
    if r.width == "fill" then
      cur = nil; used = 0
      lines[#lines + 1] = { rows = { r }, cluster = false }
    else
      local u = r.unit or W.WIDTH_UNIT
      if not cur or used + u > width then
        cur = { rows = {}, cluster = false }; used = 0
        lines[#lines + 1] = cur
      end
      cur.rows[#cur.rows + 1] = r
      used = used + u
      if #cur.rows > 1 then cur.cluster = true end
    end
  end
  return lines
end

--------------------------------------------------------------------------------
-- Nav → pages → tabs → cards.
--------------------------------------------------------------------------------
local function isGroup(n) return type(n) == "table" and n.type == "group" end

local function count(node, adv)
  local n, hdrAdv = 0, false
  for _, e in ipairs(W.Children(node)) do
    local v = e.node
    if v.type == "header" then hdrAdv = isAdv(v)
    elseif v.type == "group" then n = n + count(v, adv or isAdv(v))
    elseif CONTROL_TYPES[v.type] then
      if not (W.Simple() and (adv or hdrAdv or isAdv(v))) then n = n + 1 end
    end
  end
  return n
end
W.Count = count
local simpleTabs   -- defined after W.Cards

local function pageEntry(key, node, path)
  local okn, name = W.Member(node, "name", nil)
  return { key = key, name = strip(okn and name or key), node = node, path = path, count = count(node) }
end

function W.Nav(root, appName)
  W._root = root
  local groups = { { head = nil, pages = {} } }
  local system = { head = "System", pages = {} }
  for _, e in ipairs(W.Children(root)) do
    local k, n = e.key, e.node
    if isGroup(n) then
      if W.FAMILY_KEYS[k] then
        local okn, fname = W.Member(n, "name", nil)
        local fam = { head = strip(okn and fname or k), pages = {} }
        for _, c in ipairs(W.Children(n)) do
          if isGroup(c.node) then fam.pages[#fam.pages + 1] = pageEntry(c.key, c.node, { k, c.key }) end
        end
        groups[#groups + 1] = fam
      elseif W.SYSTEM_KEYS[k] then
        system.pages[#system.pages + 1] = pageEntry(k, n, { k })
      else
        groups[1].pages[#groups[1].pages + 1] = pageEntry(k, n, { k })
      end
    end
  end
  groups[#groups + 1] = system
  return { groups = groups, root = root, appName = appName }
end

-- Depth 3: the page's non-inline, non-hidden group children are tabs; loose
-- leaves and inline groups form the Overview tab when any control is loose.
function W.Page(node, path, appName)
  local ctx = { appName = appName, root = nil, handler = node.handler }
  local tabs, loose, hasControl = {}, {}, false
  local inh = walkInherit(nil, node)
  for _, c in ipairs(W.Children(node)) do
    local n = c.node
    if isGroup(n) and not n.inline then
      local info = makeInfo(appName, { unpack(path) }, n, node.handler, nil)
      info[#info + 1] = c.key
      local okh, hidden = W.Member(n, "hidden", info, inh)
      if not (okh and hidden == true) then
        local okn, name = W.Member(n, "name", info)
        local p = { unpack(path) }; p[#p + 1] = c.key
        tabs[#tabs + 1] = { key = c.key, name = strip(okn and name or c.key), node = n, path = p, virtual = false, handler = n.handler or node.handler }
      end
    else
      loose[#loose + 1] = c
      if not isGroup(n) and CONTROL_TYPES[n.type] then hasControl = true end
      if isGroup(n) and count(n) > 0 then hasControl = true end
    end
  end
  local okn, pname = W.Member(node, "name", nil)
  pname = strip(okn and pname or path[#path])
  if #tabs == 0 then
    tabs = { { key = "__self", name = pname, node = node, path = path, virtual = true, handler = node.handler } }
  elseif hasControl then
    table.insert(tabs, 1, { key = "__self", name = "Overview", node = node, path = path, virtual = false, looseOnly = true, handler = node.handler })
  elseif #loose > 0 then
    -- an intro-only landing (Experimental): its descriptions lead the first tab
    tabs[1].introFrom, tabs[1].introPath = node, path
  end
  local kept, dropped = simpleTabs(tabs, appName)
  if not kept then return { tabs = {}, allAdvanced = true, dropped = dropped } end
  return { tabs = kept }
end

-- The catalog behind a per-item inline group (warning_/helper_/setup_ keys).
local function catalogFor(key)
  local prefix, item = key:match("^(%a+)_(.+)$")
  if not prefix then return nil end
  local modName = ({ warning = "Warnings", helper = "Helpers", setup = "SetupCheck" })[prefix]
  if not modName then return nil end
  local mod = Nock.GetModule and Nock:GetModule(modName, true)
  local list = mod and (mod.Catalog or mod.Checks)
  if type(list) ~= "table" then return { itemKey = item, kind = prefix } end
  for _, cat in ipairs(list) do
    if cat.key == item then return { itemKey = item, kind = prefix, severity = cat.severity, entry = cat } end
  end
  return { itemKey = item, kind = prefix }
end

local function cardRows(ctx, groupNode, path, inherited, out)
  for _, c in ipairs(W.Children(groupNode)) do
    local p = { unpack(path) }; p[#p + 1] = c.key
    if isGroup(c.node) then
      local info = makeInfo(ctx.appName, p, c.node, ctx.handler, ctx.root)
      local okh, hidden = W.Member(c.node, "hidden", info, inherited)
      if not (okh and hidden == true) then
        local okn, name = W.Member(c.node, "name", info)
        local hdr = { key = c.key, node = c.node, path = p, type = "header", info = info, isControl = false,
                      name = strip(okn and name or c.key), width = "fill", subgroup = true }
        out[#out + 1] = hdr
        cardRows(ctx, c.node, p, walkInherit(inherited, c.node), out)
      end
    else
      local row = makeRow(ctx, c.key, c.node, p, inherited)
      if not row.hidden then out[#out + 1] = row end
    end
  end
end

-- Rows after an advanced header (until the next header) are advanced.
local function markHeaderAdvanced(rows)
  local hdrAdv = false
  for _, r in ipairs(rows) do
    if r.type == "header" then hdrAdv = isAdv(r.node)
    elseif hdrAdv then r.advanced = true end
  end
end

-- Simple: strip advanced rows; returns the kept rows and how many controls went.
local function filterRows(rows, cardAdvanced)
  if not W.Simple() then return rows, 0 end
  local kept, dropped = {}, 0
  for _, r in ipairs(rows) do
    if cardAdvanced or r.advanced then
      if r.isControl then dropped = dropped + 1 end
    else kept[#kept + 1] = r end
  end
  return kept, dropped
end

local function hasControl(rows)
  for _, r in ipairs(rows) do if r.isControl then return true end end
  return false
end

-- A card's one-line description, drawn as its first row.
local function descRow(card)
  local node = { type = "description", name = card.desc }
  return { key = "__desc", node = node, path = card.path, type = "description", isControl = false, name = card.desc, width = "fill", info = {} }
end


--------------------------------------------------------------------------------
-- Card layouts (spec 2026-09-09 §5, the canvas patterns). A card's header
-- metadata names its actions / table / form / stack / segments; the entries,
-- background block and item lists are recognised from the rows themselves.
-- Rows a descriptor claims leave the flow; the renderer draws the descriptor.
--------------------------------------------------------------------------------
local function isBtn(r, label) return r ~= nil and r.type == "execute" and strip(r.name) == label end

-- An entry starting at rows[i]: toggle + Up/Down[/X], or a "N. label"
-- description + Up/Down (bar order). Returns its length, 0 when none.
local function entryLen(rows, i)
  local r = rows[i]
  if not r then return 0 end
  if r.type == "toggle" and r.width ~= "fill" and isBtn(rows[i + 1], "Up") and isBtn(rows[i + 2], "Down") then
    return isBtn(rows[i + 3], "X") and 4 or 3
  end
  if r.type == "description" and strip(r.name):match("^%d+%.%s") and isBtn(rows[i + 1], "Up") and isBtn(rows[i + 2], "Down") then return 3 end
  return 0
end
W.EntryLen = entryLen

local function layoutCard(card, rows)
  local used, byKey = {}, {}
  for _, r in ipairs(rows) do byKey[r.key] = r end
  local function take(r) used[r] = true; return r end

  if card.actions then
    card.actionRows = {}
    for _, k in ipairs(card.actions) do local r = byKey[k]; if r then card.actionRows[#card.actionRows + 1] = take(r) end end
    if #card.actionRows == 0 then card.actionRows = nil end
  end

  if type(card.form) == "table" then
    card.formRows = {}
    for _, k in ipairs(card.form) do local r = byKey[k]; if r then card.formRows[#card.formRows + 1] = take(r) end end
    if #card.formRows == 0 then card.formRows = nil end
  end

  if card.segments then
    local seg = { label = card.segments.label, desc = card.segments.desc, buttons = {} }
    for _, o in ipairs(card.segments.options or {}) do
      local r = o[3] and byKey[o[3]] or nil
      seg.buttons[#seg.buttons + 1] = { name = o[1], hint = o[2], row = r and take(r) or nil }
    end
    card.segmentRows = seg
  end

  if card.table then
    local spec = card.table
    local t = { cols = {}, rows = {}, one = #spec.rows == 1 }
    for _, col in ipairs(spec.cols) do t.cols[#t.cols + 1] = col[1] end
    local function addLine(label, icon, cellKey)
      local line = { label = label, icon = icon, cells = {} }
      for _, col in ipairs(spec.cols) do
        local cell = {}
        for _, k in ipairs(cellKey(col)) do local r = byKey[k]; if r then cell[#cell + 1] = take(r) end end
        line.cells[#line.cells + 1] = cell
      end
      t.rows[#t.rows + 1] = line
    end
    for _, rs in ipairs(spec.rows) do
      local base = type(rs[1]) == "string" and rs[1]:match("^(.-)%*$")
      if base and type(rs[2]) == "table" then
        -- A wildcard line per dynamic entry: `<base><id>_lbl` names and orders
        -- it (its icon meta is the row icon), the cell keys are suffixes.
        local ids = {}
        for k, r in pairs(byKey) do
          local id = k:sub(1, #base) == base and k:sub(#base + 1):match("^(.-)_lbl$") or nil
          -- the layout re-orders listed rows, so a dynamic entry carries its
          -- own sequence in META "seq" (the builder's order); node order after
          if id then ids[#ids + 1] = { id = id, order = metaOf(r.node, "seq") or r.order or 0, r = r } end
        end
        table.sort(ids, function(a, b) if a.order == b.order then return a.id < b.id end return a.order < b.order end)
        for _, e in ipairs(ids) do
          take(e.r)
          addLine(strip(e.r.name), metaOf(e.r.node, "icon"), function(col)
            local suf = rs[2][col[1]]
            if type(suf) == "string" then return { base .. e.id .. suf } end
            local out = {}
            for _, s in ipairs(type(suf) == "table" and suf or {}) do out[#out + 1] = base .. e.id .. s end
            return out
          end)
        end
      else
        addLine(rs[1], nil, function(col)
          local keys = {}
          if type(rs[2]) == "table" then
            local v = rs[2][col[1]]
            if type(v) == "string" then keys[1] = v elseif type(v) == "table" then keys = v end
          else
            for j = 2, #col do keys[#keys + 1] = rs[2] .. col[j] end
          end
          return keys
        end)
      end
    end
    t.one = #t.rows == 1
    t.grid = spec.grid   -- N: draw the lines as pills in N columns instead of a table
    card.tableRows = t
  else
    -- the Background block: BgColor/BgOpacity + Border/BorderSize/BorderColor/BorderOpacity, any prefix spelling
    local bg, bd = {}, {}
    for _, r in ipairs(rows) do
      if not used[r] then
        local k = r.key
        if r.type == "color" and (k:match("BgColor$") or k:match("BackgroundColor$") or k == "backgroundColor") then bg.color = r
        elseif r.type == "range" and (k:match("BgOpacity$") or k:match("BackgroundOpacity$") or k == "backgroundOpacity") then bg.opacity = r
        elseif r.type == "select" and k:match("Border$") then bd.style = r
        elseif r.type == "range" and k:match("BorderSize$") then bd.size = r
        elseif r.type == "color" and k:match("BorderColor$") then bd.color = r
        elseif r.type == "range" and k:match("BorderOpacity$") then bd.opacity = r
        end
      end
    end
    if bg.color and bg.opacity and bd.color and bd.opacity then
      local blk = { bg = { take(bg.color), take(bg.opacity) }, border = {} }
      for _, r in ipairs({ bd.style, bd.size, bd.color, bd.opacity }) do blk.border[#blk.border + 1] = take(r) end
      card.bgBlock = blk
    end
  end

  -- entries: "Row N" descriptions open sections; a lead button (Reset order) joins the head
  local hasEntry = false
  for i = 1, #rows do if not used[rows[i]] and entryLen(rows, i) > 0 then hasEntry = true break end end
  if hasEntry then
    local sections, cur, i = {}, nil, 1
    while i <= #rows do
      local r = rows[i]
      if used[r] then i = i + 1
      else
        local n = entryLen(rows, i)
        local nm = r.type == "description" and strip(r.name) or ""
        if nm:match("^Row %d") then
          local sub, title = nm:match("^(Row %d+)%s*[%-—]+%s*(.*)$")
          cur = { name = title or nm, sub = sub, entries = {} }
          sections[#sections + 1] = cur
          take(r); i = i + 1
        elseif n > 0 then
          if not cur then cur = { entries = {}, implicit = true }; sections[#sections + 1] = cur end
          local e = { label = take(r), buttons = {} }
          for j = i + 1, i + n - 1 do e.buttons[#e.buttons + 1] = take(rows[j]) end
          cur.entries[#cur.entries + 1] = e
          i = i + n
        elseif cur and r.type == "select" and strip(r.name):match("^Add") then
          cur.add = take(r); i = i + 1
        elseif cur == nil and r.type == "execute" then
          card.actionRows = card.actionRows or {}
          card.actionRows[#card.actionRows + 1] = take(r); i = i + 1
        else i = i + 1 end
      end
    end
    card.entries = sections
  end

  -- custom items: (label description, threshold range, X) triples
  local items, i = {}, 1
  while i <= #rows do
    local a, b, c = rows[i], rows[i + 1], rows[i + 2]
    if a and b and c and not used[a] and a.type == "description" and b.type == "range" and isBtn(c, "X") then
      items[#items + 1] = { label = take(a), thr = take(b), remove = take(c) }
      i = i + 3
    else i = i + 1 end
  end
  if #items > 0 then card.items = items end

  local rest, claimed = {}, {}
  for _, r in ipairs(rows) do if used[r] then claimed[#claimed + 1] = r else rest[#rest + 1] = r end end
  card.claimed = claimed
  return rest
end

-- Consecutive cards of exactly (Track toggle, Keep-at-least range) - the
-- Shopping List's curated items - fold into one items table. A preceding
-- "Curated items" card hosts it (its buttons move to the head).
local function itemPair(c)
  if c.catalog or not c.lines then return nil end
  local ctl = {}
  for _, ln in ipairs(c.lines) do for _, r in ipairs(ln.rows) do if r.isControl then ctl[#ctl + 1] = r end end end
  if #ctl ~= 2 then return nil end
  local on, thr
  for _, r in ipairs(ctl) do
    if r.type == "toggle" and strip(r.name) == "Track" then on = r elseif r.type == "range" then thr = r end
  end
  if on and thr then return on, thr end
end
local function mergeItemCards(cards)
  local out, host = {}, nil
  for _, c in ipairs(cards) do
    local on, thr = itemPair(c)
    if on then
      if not host then
        for _, prev in ipairs(out) do if strip(prev.name):lower():find("curated", 1, true) then host = prev end end
        if not host then host = { key = "__items", name = "Curated items", path = c.path, node = c.node, lines = {} }; out[#out + 1] = host end
        host.itemRows = {}
        host.claimed = host.claimed or {}
        local keep = {}
        for _, ln in ipairs(host.lines) do
          local rows = {}
          for _, r in ipairs(ln.rows) do
            if r.type == "execute" then host.actionRows = host.actionRows or {}; host.actionRows[#host.actionRows + 1] = r; host.claimed[#host.claimed + 1] = r
            else rows[#rows + 1] = r end
          end
          if #rows > 0 then ln.rows = rows; keep[#keep + 1] = ln end
        end
        host.lines = keep
      end
      host.itemRows[#host.itemRows + 1] = { name = c.name, icon = c.icon, on = on, thr = thr }
      -- the folded card's rows stay reachable (the census, search)
      for _, ln in ipairs(c.lines) do for _, r in ipairs(ln.rows) do host.claimed[#host.claimed + 1] = r end end
      for _, r in ipairs(c.claimed or {}) do host.claimed[#host.claimed + 1] = r end
    else
      host = nil
      out[#out + 1] = c
    end
  end
  return out
end

-- Loose rows split into cards at header rows: the header names the card and
-- carries its icon/desc/advanced; a row with `card = "Name"` starts one too.
-- Non-control rows before the first header (the intro) lead the first card.
local function splitLoose(loose, tab)
  local cards, cur, pre = {}, nil, {}
  for _, r in ipairs(loose) do
    if r.type == "header" then
      cur = { key = "hdr_" .. r.key, name = r.name, path = r.path, node = tab.node, rows = {}, fromHeader = true,
              icon = metaOf(r.node, "icon"), desc = type(r.node.desc) == "string" and r.node.desc or nil, advanced = isAdv(r.node),
              actions = metaOf(r.node, "actions"), table = metaOf(r.node, "table"), form = metaOf(r.node, "form"),
              stack = metaOf(r.node, "stack") == true, segments = metaOf(r.node, "segments") }
      if #cards == 0 and not hasControl(pre) then for _, p in ipairs(pre) do cur.rows[#cur.rows + 1] = p end; pre = {} end
      cards[#cards + 1] = cur
    elseif metaOf(r.node, "card") then
      cur = { key = "card_" .. r.key, name = tostring(metaOf(r.node, "card")), path = tab.path, node = tab.node, rows = { r }, advanced = cur and cur.advanced or false }
      cards[#cards + 1] = cur
    elseif cur then cur.rows[#cur.rows + 1] = r
    else pre[#pre + 1] = r end
  end
  if #pre > 0 then table.insert(cards, 1, { key = "__loose", name = tab.name, path = tab.path, node = tab.node, rows = pre }) end
  return cards
end

-- Returns cards and the number of controls Simple hid on this tab.
function W.Cards(tab, appName, contentWidth)
  local node, path = tab.node, tab.path
  local ctx = { appName = appName, root = nil, handler = tab.handler or node.handler }
  local inh = walkInherit(nil, node)
  local cards = {}
  local loose = {}
  local dropped = 0
  if tab.introFrom then
    local iinh = walkInherit(nil, tab.introFrom)
    for _, c in ipairs(W.Children(tab.introFrom)) do
      if not isGroup(c.node) then
        local p = { unpack(tab.introPath) }; p[#p + 1] = c.key
        local row = makeRow({ appName = appName, root = nil, handler = tab.introFrom.handler }, c.key, c.node, p, iinh)
        if not row.hidden then loose[#loose + 1] = row end
      end
    end
  end
  for _, c in ipairs(W.Children(node)) do
    local n = c.node
    local p = { unpack(path) }; p[#p + 1] = c.key
    if isGroup(n) then
      if tab.looseOnly and not n.inline then
        -- a sibling tab, not this card's business
      else
        local info = makeInfo(appName, p, n, ctx.handler, nil)
        local okh, hidden = W.Member(n, "hidden", info, inh)
        if not (okh and hidden == true) then
          local okn, name = W.Member(n, "name", info)
          local card = { key = c.key, name = strip(okn and name or c.key), path = p, node = n, lines = {},
                         icon = metaOf(n, "icon"), desc = type(n.desc) == "string" and n.desc or nil,
                         actions = metaOf(n, "actions"), table = metaOf(n, "table"), form = metaOf(n, "form"),
                         stack = metaOf(n, "stack") == true, segments = metaOf(n, "segments") }
          local rows = {}
          local cctx = { appName = appName, root = nil, handler = n.handler or ctx.handler }
          cardRows(cctx, n, p, walkInherit(inh, n), rows)
          markHeaderAdvanced(rows)
          local cardAdv = W.Simple() and (isAdv(n) or inh.advanced == true)
          local enabled, infoRow
          for _, r in ipairs(rows) do
            if r.key == "enabled" and r.type == "toggle" then enabled = r end
            if r.key == "info" and r.type == "description" then infoRow = r end
          end
          local cat = (enabled and infoRow) and catalogFor(c.key) or nil
          if cat then
            cat.enabled, cat.info = enabled, infoRow
            card.catalog = cat
            local knobs = {}
            for _, r in ipairs(rows) do if r ~= enabled and r ~= infoRow then knobs[#knobs + 1] = r end end
            rows = knobs
          end
          local d
          rows, d = filterRows(rows, cardAdv)
          dropped = dropped + d
          if cat or not W.Simple() or hasControl(rows) then
            if not cat then rows = layoutCard(card, rows) end
            if card.desc and not cat then table.insert(rows, 1, descRow(card)) end
            card.lines = W.Flow(rows, card.stack and 1 or contentWidth)
            cards[#cards + 1] = card
          end
        end
      end
    else
      local row = makeRow(ctx, c.key, n, p, inh)
      if not row.hidden then loose[#loose + 1] = row end
    end
  end
  local split = splitLoose(loose, tab)
  for i = #split, 1, -1 do
    local card = split[i]
    if card.advanced then for _, r in ipairs(card.rows) do r.advanced = true end end
    local rows, d = filterRows(card.rows, card.advanced)
    dropped = dropped + d
    card.rows = nil
    if #rows > 0 and (not W.Simple() or hasControl(rows)) then
      rows = layoutCard(card, rows)
      if card.desc then table.insert(rows, 1, descRow(card)) end
      card.lines = W.Flow(rows, card.stack and 1 or contentWidth)
      table.insert(cards, 1, card)
    end
  end
  return mergeItemCards(cards), dropped
end

-- Simple: a tab with no control left is dropped; nil when none survive.
simpleTabs = function(tabs, appName)
  if not W.Simple() then return tabs end
  local kept, dropped = {}, 0
  for _, t in ipairs(tabs) do
    local cs, d = W.Cards(t, appName)
    dropped = dropped + d
    local has = false
    for _, c in ipairs(cs) do
      if c.catalog then has = true end
      for _, ln in ipairs(c.lines) do if hasControl(ln.rows) then has = true end end
    end
    if has then kept[#kept + 1] = t end
  end
  if #kept == 0 then return nil, dropped end
  return kept
end

--------------------------------------------------------------------------------
-- Reading and writing through the row.
--------------------------------------------------------------------------------
-- A row for a dotted args path ("hud.classic.swingBars.showAutoShotBar"),
-- with the handler and inherited members the walk would have given it.
function W.RowAt(root, pathString, appName)
  local path, node, handler, inh = {}, root, root.handler, walkInherit(nil, root)
  for seg in tostring(pathString):gmatch("[^%.]+") do
    local child = node.args and node.args[seg]
    if type(child) ~= "table" then return nil, "no node " .. seg end
    path[#path + 1] = seg
    node = child
    if node.handler then handler = node.handler end
    if node.type == "group" then inh = walkInherit(inh, node) end
  end
  if node.type == "group" then return nil, "group" end
  return makeRow({ appName = appName, root = root, handler = handler }, path[#path], node, path, inh)
end

function W.Get(row, ...)
  if row.noGet then return true, nil end
  local g = row.node.get
  if g == nil and row.inherited then g = row.inherited.get end
  if g == nil then return true, nil end
  return W.Call(g, row.info, ...)
end

function W.Set(row, ...)
  local s = row.node.set
  if s == nil and row.inherited then s = row.inherited.set end
  if s == nil then return true end
  return W.Call(s, row.info, ...)
end

function W.Func(row)
  local f = row.node.func
  if f == nil and row.inherited then f = row.inherited.func end
  if f == nil then return true end
  return W.Call(f, row.info)
end

function W.Validate(row, value)
  local v = row.node.validate
  if v == nil and row.inherited then v = row.inherited.validate end
  if v == nil then return true end
  local okc, r = W.Call(v, row.info, value)
  if not okc then return false, tostring(r) end
  if r == true or r == nil then return true end
  return false, tostring(r)
end

-- The confirm prompt text, or nil when no confirmation is wanted.
function W.ConfirmText(row)
  local c = row.node.confirm
  if c == nil and row.inherited then c = row.inherited.confirm end
  if c == nil or c == false then return nil end
  if type(c) == "function" or (type(c) == "string" and row.info.handler) then
    local okc, r = W.Call(c, row.info)
    if not okc or r == false or r == nil then return nil end
    if type(r) == "string" then return r end
  end
  if row.node.confirmText then return row.node.confirmText end
  if row.desc then return row.name .. " - " .. row.desc end
  return row.name
end

local SENTINELS = { ["Inherit (global)"] = true, ["Reference (built-in)"] = true }
local function numAware(a, b)
  local na, nb = tonumber(a), tonumber(b)
  if na and nb then return na < nb end
  return tostring(a) < tostring(b)
end

-- Select/multiselect values as parallel key/label lists, honouring `sorting`
-- (array or function), pinning the sentinel rows first.
function W.Values(row)
  local vals = row.node.values
  local okv, list = W.Call(vals, row.info)
  if not okv or type(list) ~= "table" then return {}, {} end
  local keys = {}
  local sorting = row.node.sorting
  if type(sorting) == "function" or (type(sorting) == "string" and row.info.handler) then
    local oks, s = W.Call(sorting, row.info); sorting = oks and s or nil
  end
  if type(sorting) == "table" then
    for _, k in ipairs(sorting) do if list[k] ~= nil then keys[#keys + 1] = k end end
  else
    for k in pairs(list) do keys[#keys + 1] = k end
    table.sort(keys, numAware)
  end
  local out, labels = {}, {}
  for _, k in ipairs(keys) do if SENTINELS[k] then out[#out + 1] = k; labels[#labels + 1] = strip(list[k]) end end
  for _, k in ipairs(keys) do if not SENTINELS[k] then out[#out + 1] = k; labels[#labels + 1] = strip(list[k]) end end
  return out, labels
end

-- The description's image (a fileID or path) for catalog tiles.
function W.Image(row)
  local img = row.node.image
  if img == nil then return nil end
  local oki, v = W.Call(img, row.info)
  if not oki then return nil end
  return v, row.node.imageWidth or 36, row.node.imageHeight or 36
end

--------------------------------------------------------------------------------
-- Search: an index over every control row of every page, built in Advanced
-- mode so Simple hides nothing from it (the mode is restored afterwards).
-- Rows a layout claimed (table cells, entry pills, head actions) are indexed
-- too; a catalog card's master switch is findable by the card's title.
--------------------------------------------------------------------------------
function W.Index(nav, appName)
  local index, mode = {}, W.MODE
  W.SetMode("advanced")
  for _, g in ipairs(nav.groups) do
    for _, p in ipairs(g.pages) do
      local pg = W.Page(p.node, p.path, appName)
      for _, t in ipairs(pg.tabs) do
        local crumb = p.name .. (t.virtual and "" or (" › " .. t.name))
        for _, c in ipairs(W.Cards(t, appName)) do
          local seen = {}
          local function add(row)
            if not row or not row.isControl or seen[row] then return end
            seen[row] = true
            index[#index + 1] = {
              pageKey = p.key, pageName = p.name, tabKey = t.key, tabName = t.name,
              cardKey = c.key, cardName = c.name, cardIcon = c.icon, crumb = crumb, row = row,
              text = (strip(row.name or "") .. " " .. strip(row.desc or "") .. " " .. strip(c.name or "") .. " " .. (t.name or "") .. " " .. p.name):lower(),
            }
          end
          if c.catalog then add(c.catalog.enabled) end
          for _, ln in ipairs(c.lines or {}) do for _, r in ipairs(ln.rows) do add(r) end end
          for _, r in ipairs(c.claimed or {}) do add(r) end
        end
      end
    end
  end
  W.SetMode(mode)
  return index
end

-- Substring search over the index for a trimmed, lower-cased query of at
-- least two characters. Hits keep index order (page order, then card order).
function W.Search(index, query)
  local q = (query or ""):lower():match("^%s*(.-)%s*$")
  local res = { hits = {}, counts = {}, total = 0 }
  if #q < 2 then return res end
  for _, e in ipairs(index) do
    if e.text:find(q, 1, true) then
      res.hits[#res.hits + 1] = e
      res.counts[e.pageKey] = (res.counts[e.pageKey] or 0) + 1
      res.total = res.total + 1
    end
  end
  return res
end
-- Dropdown list window: `n` entries, `show` visible at once, `offset` = rows
-- scrolled past. Clamps; `PullOpenOffset` centres the current pick on open.
function W.PullClamp(offset, n, show)
  local maxOff = math.max(0, n - show)
  if offset < 0 then return 0 end
  if offset > maxOff then return maxOff end
  return offset
end
function W.PullOpenOffset(curIndex, n, show)
  if not curIndex or n <= show then return 0 end
  return W.PullClamp(curIndex - 1 - math.floor(show / 2), n, show)
end
-- Thumb geometry for a track of `trackH`: height and offset from the top.
function W.PullThumb(offset, n, show, trackH)
  if n <= show then return nil end
  local h = math.max(12, math.floor(trackH * show / n))
  local y = math.floor((trackH - h) * offset / (n - show))
  return h, y
end


return W
