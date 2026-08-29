-- Tests/react_order_test.lua
-- Standalone LuaJIT tests for Nock.UI.ResolveReactBarOrder, the sanitizer
-- behind the React cluster's configurable bar order (reactBarOrder). The
-- stored value is user data mutated by Up/Down executes in Options, so the
-- resolver must survive anything: false (the default), permutations, partial
-- lists, duplicates, unknown keys, non-tables.
-- Run from the repo root: luajit Tests/react_order_test.lua
-- (Harness cloned from react_countdown_test.lua — see the load-time note there.)

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = {
  db = { profile = {} },
  Constants = setmetatable({}, {
    __index = function(t, k)
      local v = {}
      rawset(t, k, v)
      return v
    end,
  }),
}

local libs = { ["AceAddon-3.0"] = { GetAddon = function() return Nock end } }
_G.LibStub = setmetatable({}, {
  __call = function(_, name, silent)
    local lib = libs[name]
    if not lib and not silent then error("harness: missing lib " .. name) end
    return lib
  end,
})
_G.CreateFrame = function()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end

dofile("UI/Widgets.lua")

local R = Nock.UI.ResolveReactBarOrder
ok(type(R) == "function", "Nock.UI.ResolveReactBarOrder exists")

local BUILTIN = { "auto", "melee", "range", "mana" }

local function eq(got, want)
  if type(got) ~= "table" or #got ~= #want then return false end
  for i = 1, #want do
    if got[i] ~= want[i] then return false end
  end
  return true
end

--------------------------------------------------------------------------------
-- The default: anything that isn't a table means the built-in order.
--------------------------------------------------------------------------------
ok(eq(R(false), BUILTIN), "false resolves to the built-in order")
ok(eq(R(nil),   BUILTIN), "nil resolves to the built-in order")
ok(eq(R("mana"), BUILTIN), "a non-table resolves to the built-in order")

--------------------------------------------------------------------------------
-- Valid permutations pass through untouched.
--------------------------------------------------------------------------------
ok(eq(R({ "mana", "range", "melee", "auto" }), { "mana", "range", "melee", "auto" }),
   "a full permutation is honored")
ok(eq(R({ "auto", "melee", "range", "mana" }), BUILTIN),
   "the built-in order stored explicitly round-trips")

--------------------------------------------------------------------------------
-- Damaged input: dedupe, drop unknowns, append what's missing (built-in
-- relative order) — every bar always places exactly once.
--------------------------------------------------------------------------------
ok(eq(R({ "mana", "mana", "auto" }), { "mana", "auto", "melee", "range" }),
   "duplicates collapse to the first occurrence, missing bars append")
ok(eq(R({ "gcd", "mana", "pet" }), { "mana", "auto", "melee", "range" }),
   "unknown keys are dropped")
ok(eq(R({}), BUILTIN), "an empty table resolves to the built-in order")
ok(eq(R({ "range" }), { "range", "auto", "melee", "mana" }),
   "a partial list keeps its lead and appends the rest in built-in order")

-- Result always contains each bar exactly once, whatever the input.
local got = R({ "melee", 42, "auto", false, "melee" })
local seen = {}
for i = 1, #got do seen[got[i]] = (seen[got[i]] or 0) + 1 end
ok(#got == 4 and seen.auto == 1 and seen.melee == 1 and seen.range == 1
   and seen.mana == 1, "garbage input still yields each bar exactly once")

print(string.format("react_order: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
