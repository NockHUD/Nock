-- Tests/mana_format_test.lua
-- Standalone LuaJIT tests for Nock.UI.FormatManaText, the shared mana-text
-- formatter behind the classic mana bar's "Center text" modes and the React
-- mana bar's reactManaText. (Harness cloned from react_countdown_test.lua.)
-- Run from the repo root: luajit Tests/mana_format_test.lua

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

local F = Nock.UI.FormatManaText
ok(type(F) == "function", "Nock.UI.FormatManaText exists")

ok(F("none",    4231, 7460, 57) == "",            "none renders nothing")
ok(F("value",   4231, 7460, 57) == "4231",        "value renders current mana")
ok(F("both",    4231, 7460, 57) == "4231 / 7460", "both renders cur / max")
ok(F("percent", 4231, 7460, 57) == "57%",         "percent renders the percent")
ok(F("garbage", 4231, 7460, 57) == "57%",         "unknown mode falls back to percent")
ok(F(nil,       4231, 7460, 57) == "57%",         "nil mode falls back to percent")
ok(F("percent", 0, 0, 100) == "100%",             "empty pool renders 100%")

print(string.format("mana_format: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
