-- Tests/presets_test.lua
-- Every preset path resolves to a control, every value fits its control, no preset touches what it must not.
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local catalogs = dofile("Tests/lib/catalog_scan.lua")
local Nock, W, root = dofile("Tests/lib/options_harness.lua")({ catalogs = catalogs })
local P = Nock.Presets
ok(type(P) == "table", "Nock.Presets loaded")
local FORBID = { "^profiles", "^experimental", "Key$", "Bind$", "Pos$", "Macro", "position" }
local pages = 0
for pagePath, list in pairs(P.ByPage) do
  pages = pages + 1
  local node = root
  for seg in pagePath:gmatch("[^%.]+") do node = node and node.args and node.args[seg] end
  ok(node ~= nil, "preset page exists: " .. pagePath)
  ok(#list >= 2 and #list <= 4, pagePath .. " has 2-4 presets")
  for _, p in ipairs(list) do
    ok(#p.name <= 14, p.name .. " name <= 14")
    ok(#p.summary <= 90, p.name .. " summary <= 90")
    ok(#p.set > 0, p.name .. " sets something")
    for _, e in ipairs(p.set) do
      local path, value = e[1], e[2]
      ok(path:sub(1, #pagePath) == pagePath, ("%s stays on its page: %s"):format(p.name, path))
      for _, f in ipairs(FORBID) do ok(not path:match(f), ("%s never touches %s"):format(p.name, path)) end
      local row, why = W.RowAt(root, path, "Nock")
      ok(row ~= nil, ("%s path resolves: %s (%s)"):format(p.name, path, tostring(why)))
      if row then
        if value == "func" then ok(row.type == "execute", path .. " func on an execute")
        elseif row.type == "toggle" then ok(type(value) == "boolean", path .. " boolean")
        elseif row.type == "range" then ok(type(value) == "number" and value >= row.node.min and value <= row.node.max, path .. " in range")
        elseif row.type == "select" then
          local keys = W.Values(row); local hit = false
          for _, k in ipairs(keys) do if k == value then hit = true end end
          ok(hit, path .. " is a select key")
        end
      end
    end
  end
end
ok(pages == 7, ("7 pages carry presets (%d)"):format(pages))
-- Apply then Matches: a preset reads back as active once applied
local warn = P.ByPage["alerts.warnings"][1]
P.Apply(warn, root, "Nock")
ok(P.Matches(warn, root, "Nock"), "Quiet reads back as active after Apply")
ok(not P.Matches(P.ByPage["alerts.warnings"][3], root, "Nock"), "Everything does not match while Quiet is applied")
print(("presets_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
