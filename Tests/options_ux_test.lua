-- Tests/options_ux_test.lua
-- The mechanical half of docs/superpowers/specs/settings-ux-rules.md against the real options table: names, one-liners, Simple-card size, catalog icons, layout paths.
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local catalogs = dofile("Tests/lib/catalog_scan.lua")
local Nock, W, root = dofile("Tests/lib/options_harness.lua")({ catalogs = catalogs })
local function first(s) s = W.Strip(s or ""); return s:match("^(.-[%.!?])%s") or s end

-- Cards whose rows are lists by design (spell tiles, key captures, entry pills): the 8-row cap does not apply.
local TILE_TABS = { buffRow = true, tabBuff = true, tabBuffs = true, keys = true, tabGrid = true, cooldownGrid = true }
local nav = W.Nav(root, "Nock")
for _, g in ipairs(nav.groups) do for _, p in ipairs(g.pages) do
  W.SetMode("advanced")
  local pg = W.Page(p.node, p.path, "Nock")
  for _, t in ipairs(pg.tabs) do
    for _, c in ipairs(W.Cards(t, "Nock")) do
      ok(#W.Strip(c.name) <= 32, ("card name <= 32: %s/%s/%s"):format(p.key, t.key, c.name))
      if c.desc then ok(#first(c.desc) <= 140, ("card one-liner <= 140: %s/%s/%s"):format(p.key, t.key, c.name)) end
      local function checkRow(r)
        if r.type == "toggle" and r.key ~= "enabled" then
          local n = W.Strip(r.name):gsub("%s*%(spell %d+%)$", "")
          ok(#n <= 40, ("toggle name <= 40: %s (%s/%s)"):format(n, p.key, t.key))
          ok(not n:match("^Show ") and not n:match("^Enable ") and not n:match("^Toggle "), ("toggle name is a thing, not a verb: %s (%s/%s)"):format(n, p.key, t.key))
        end
      end
      for _, ln in ipairs(c.lines) do for _, r in ipairs(ln.rows) do checkRow(r) end end
      for _, r in ipairs(c.claimed or {}) do checkRow(r) end
    end
    W.SetMode("simple")
    for _, c in ipairs(W.Cards(t, "Nock")) do
      if not c.catalog and not TILE_TABS[t.key] and not c.entries and not c.itemRows then
        local n, toggles = 0, 0
        for _, ln in ipairs(c.lines) do for _, r in ipairs(ln.rows) do if r.isControl and r.type ~= "execute" then n = n + 1; if r.type == "toggle" then toggles = toggles + 1 end end end end
        -- a toggle-only card is a tile grid (feature switches), not a list of knobs
        ok(n <= 8 or toggles == n, ("simple card <= 8 rows: %s/%s/%s has %d"):format(p.key, t.key, c.name, n))
      end
    end
    W.SetMode("advanced")
  end
end end
for _, mod in ipairs({ "Warnings", "Helpers" }) do
  ok(#catalogs[mod].Catalog > 0, mod .. " catalog scanned")
  for _, e in ipairs(catalogs[mod].Catalog) do
    ok(e.hasIcon and e.hasDescription, ("%s catalog entry %s has icon + description"):format(mod, e.key))
  end
end
local missing = Nock.OptionsAdvanced.Missing(root)
ok(#missing == 0, "advanced paths resolve: " .. table.concat(missing, ", "))
local lmissing = Nock.OptionsLayout and Nock.OptionsLayout.Missing(root) or {}
-- dynamic rows (customItem_*) resolve at runtime; wildcards are fine
local realMissing = {}
for _, m in ipairs(lmissing) do if not m:find("%*") then realMissing[#realMissing + 1] = m end end
ok(#realMissing == 0, "layout paths resolve: " .. table.concat(realMissing, ", "))
print(("options_ux_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
