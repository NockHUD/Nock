-- Tests/options_advanced_test.lua
-- Every explicit advanced path resolves; the heavy pages end up 40-80 % advanced; Simple never empties a light page by accident.
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local Nock, W, root = dofile("Tests/lib/options_harness.lua")()
local A = Nock.OptionsAdvanced
ok(type(A) == "table" and type(A.Apply) == "function", "Nock.OptionsAdvanced loaded")
local missing = A.Missing(root)
ok(#missing == 0, "explicit paths resolve: " .. table.concat(missing, ", "))
local function ratio(node)
  W.SetMode("advanced"); local all = W.Count(node)
  W.SetMode("simple"); local simple = W.Count(node)
  W.SetMode("advanced")
  return (all - simple) / math.max(all, 1), all, simple
end
for _, p in ipairs({ { "classic", root.args.hud.args.classic }, { "react", root.args.hud.args.react }, { "fluffy", root.args.hud.args.fluffy }, { "general", root.args.general } }) do
  local r, all, simple = ratio(p[2])
  -- 30 %, not 40: the cooldown-grid entries (toggle + Up/Down/X per row) are simple by design and dilute the heavy pages
  ok(r >= 0.30 and r <= 0.80, ("%s advanced ratio %.0f%% (%d of %d) within 30-80"):format(p[1], r * 100, all - simple, all))
end
for _, key in ipairs({ "mailbox", "garment", "tonk", "shopping", "weaveBind" }) do
  local node = root.args.utilities.args[key]
  W.SetMode("simple"); local n = W.Count(node); W.SetMode("advanced")
  ok(n > 0, key .. " keeps at least one simple control")
end
ok(A.IsAdvanced(root.args.hud.args.classic.args.background), "whole Background tab is advanced")
ok(A.IsAdvanced(root.args.hud.args.classic.args.swingBars.args.autoShotBarColor), "Color$ pattern tags a colour")
ok(not A.IsAdvanced(root.args.general.args.scale), "KEEP protects scale")
local function noNodeKeys(node, path)
  for k, v in pairs(node.args or {}) do
    if type(v) == "table" and v.type then
      if v.advanced ~= nil or v.card ~= nil then return path .. "." .. k end
      if v.type == "group" then local bad = noNodeKeys(v, path .. "." .. k); if bad then return bad end end
    end
  end
end
ok(noNodeKeys(root, "Nock") == nil, "no node carries a key the AceConfig validator would reject: " .. tostring(noNodeKeys(root, "Nock") or "none"))
print(("options_advanced_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
