-- Core/CooldownPicker.lua
-- What the cooldown catalog offers on each surface: tray items, flyout groups and the name-or-ID resolve; pure over a context table.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local P = {}
Nock.CooldownPicker = P
P.TABS = { "All", "Class", "Talent", "Racial", "Custom", "Recent" }
local CAP = 6

local function matches(name, q)
  if not q or q == "" then return true end
  return type(name) == "string" and name:lower():find(q:lower(), 1, true) ~= nil
end

local function item(ctx, e)
  local ri = Nock.CooldownEditor.Find(ctx.rows, e.key)
  return { key = e.key, name = ctx.nameOf(e) or e.label or e.key, cat = e.cat, placedRow = ri,
           known = ctx.known(e.key), lv = e.lv, talent = e.talent, cd = e.cd }
end

-- A profile.cooldownCustom record, as ctx.customs (built by the board): a
-- custom spell is always "known" (it is the player's own addition, not
-- something the spellbook can confirm or deny -- Forever/Cooldowns.lua's
-- customEntries() leaves it unset for the same reason).
local function customItem(ctx, c)
  return { key = c.key, id = c.id, name = c.name, cat = "Custom", custom = true,
           placedRow = Nock.CooldownEditor.Find(ctx.rows, c.key), known = true }
end

local function customItems(ctx, query)
  local out = {}
  for _, c in ipairs(ctx.customs or {}) do
    local it = customItem(ctx, c)
    if matches(it.name, query) then out[#out + 1] = it end
  end
  return out
end

local function recentItems(ctx, query)
  local out = {}
  for _, id in ipairs(ctx.recent or {}) do
    local key = ctx.byId(id)
    local it
    if key then
      for _, e in ipairs(ctx.entries) do if e.key == key then it = item(ctx, e) end end
    else
      it = { id = id, name = ctx.nameOf(id) or ("Spell " .. id), cat = "Recent" }
    end
    if it and matches(it.name, query) then out[#out + 1] = it end
  end
  return out
end

function P.TrayItems(ctx, tab, query)
  if tab == "Recent" then return recentItems(ctx, query) end
  if tab == "Custom" then return customItems(ctx, query) end
  local out = {}
  for _, e in ipairs(ctx.entries) do
    if (tab == "All" or e.cat == tab) and ctx.available(e.key) then
      local it = item(ctx, e)
      if matches(it.name, query) then out[#out + 1] = it end
    end
  end
  if tab == "All" then
    for _, it in ipairs(customItems(ctx, query)) do out[#out + 1] = it end
  end
  return out
end

function P.FlyoutGroups(ctx, query)
  local sug, cat = {}, {}
  for _, it in ipairs(P.TrayItems(ctx, "All", query)) do
    if not it.placedRow then
      if it.known == true then
        if #sug < CAP then sug[#sug + 1] = it end
      elseif #cat < CAP then cat[#cat + 1] = it end
    end
  end
  local rec = {}
  for _, it in ipairs(recentItems(ctx, query)) do
    if not it.placedRow and #rec < CAP then rec[#rec + 1] = it end
  end
  local groups = {}
  if #sug > 0 then groups[#groups + 1] = { title = "Suggested: you have these", items = sug } end
  if #rec > 0 then groups[#groups + 1] = { title = "Recently cast", items = rec } end
  if #cat > 0 then groups[#groups + 1] = { title = "Catalog", items = cat } end
  return groups
end

function P.Resolve(text, names, ctx)
  if type(text) ~= "string" then return nil end
  text = text:match("^%s*(.-)%s*$")
  if text == "" then return nil end
  -- Digits only: tonumber("-5"), tonumber("1e3") and tonumber("0x1F") all
  -- parse as numbers too, which would treat a typo or a scientific-notation
  -- paste as a spell id. A spell id is a plain positive integer written in
  -- decimal, so match that shape before trusting it as one.
  local id = text:match("^%d+$") and tonumber(text)
  if not id then
    local want = text:lower()
    for n, sid in pairs(names or {}) do
      if type(n) == "string" and n:lower() == want and type(sid) == "number" then id = sid; break end
    end
    if not id then return nil end
    for _, e in ipairs(ctx.entries) do
      if (e.name and e.name:lower() == want) or (ctx.nameOf(e) or ""):lower() == want then return { key = e.key } end
    end
  end
  for _, e in ipairs(ctx.entries) do
    if e.id == id then return { key = e.key } end
    if e.ids then for _, x in ipairs(e.ids) do if x == id then return { key = e.key } end end end
  end
  for _, c in ipairs(ctx.customs or {}) do
    if c.id == id then return { key = c.key } end
  end
  local key = ctx.byId and ctx.byId(id)
  if key then return { key = key } end
  return { id = id }
end

local function dur(s)
  if not s then return nil end
  if s >= 60 then return ("%dm"):format(math.floor(s / 60 + 0.5)) end
  return ("%ds"):format(s)
end

function P.Meta(it)
  if it.custom then return "custom" end
  if it.id and not it.key then return "cast recently" end
  local parts = {}
  if it.cd then parts[#parts + 1] = "CD " .. dur(it.cd) end
  if it.cat == "Racial" then parts[#parts + 1] = "your racial"
  elseif it.known == false then parts[#parts + 1] = it.talent and "talent" or (it.lv and ("Lv " .. it.lv) or "not trained") end
  return table.concat(parts, " · ")
end
