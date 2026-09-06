-- Tests/tools/options_dump.lua
-- Dumps the settings tree (pages → tabs → cards → rows) as JSON for the design canvas generator.
-- Usage: luajit Tests/tools/options_dump.lua <out.json>   (run from the repo root)
local out = arg[1] or "options_dump.json"
local Nock, W, root = dofile("Tests/lib/options_harness.lua")()
W.SetMode("advanced")

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "", ["\t"] = "\\t" }
local function esc(s) return '"' .. tostring(s):gsub('[%c"\\]', function(c) return ESC[c] or "" end) .. '"' end
local function json(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local parts = {}
      for i = 1, #v do parts[i] = json(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = esc(k) .. ":" .. json(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then return esc(v)
  elseif t == "number" or t == "boolean" then return tostring(v)
  else return "null" end
end

local function first(s)
  s = W.Strip(s or "")
  return s:match("^(.-[%.!?])%s") or s
end

local function iconOf(icon)
  if type(icon) == "table" then return { spell = icon.spell, glyph = icon.glyph } end
  if type(icon) == "string" then return { path = icon } end
  return nil
end

local pages = {}
local nav = W.Nav(root, "Nock")
for _, fam in ipairs(nav.groups) do
  for _, p in ipairs(fam.pages) do
    local page = { key = p.key, name = p.name, family = fam.head or "", path = table.concat(p.path, "."), tabs = {} }
    local pg = W.Page(p.node, p.path, "Nock")
    for _, t in ipairs(pg.tabs) do
      local tab = { key = t.key, name = t.name, cards = {} }
      local cards = W.Cards(t, "Nock", 600)
      for _, c in ipairs(cards) do
        local card = { key = c.key, name = c.name, catalog = c.catalog and c.catalog.kind or nil,
                       icon = iconOf(c.icon), desc = c.desc and first(c.desc) or nil, rows = {} }
        for _, ln in ipairs(c.lines) do
          for _, r in ipairs(ln.rows) do
            card.rows[#card.rows + 1] = { key = r.key, type = r.type, name = W.Strip(r.name), desc = r.desc and first(r.desc) or nil,
              width = tostring(r.width), unit = r.unit, advanced = r.advanced or false, isControl = r.isControl }
          end
        end
        tab.cards[#tab.cards + 1] = card
      end
      page.tabs[#page.tabs + 1] = tab
    end
    pages[#pages + 1] = page
  end
end
local f = assert(io.open(out, "w"))
f:write(json({ pages = pages }))
f:close()
print("wrote " .. out)
