-- Tests/react_unlearned_look_test.lua
-- Standalone LuaJIT tests for greyed tiles of unknown spells (cooldown grid
-- picker, 2026-09-27).
-- Run from the repo root: luajit Tests/react_unlearned_look_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = {
  db = { profile = {} },
  Constants = setmetatable({}, {
    __index = function(t, k) local v = {}; rawset(t, k, v); return v end,
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

--------------------------------------------------------------------------------
-- §1 Unlearned tiles
--------------------------------------------------------------------------------
local Look = Nock.UI.ReactSlotLook

local r = Look({ ready = true, procActive = false }, nil, { unlearned = true }, {})
ok(r.desat == true and r.alpha == 0.35 and r.glow == nil and r.tint == nil, "an unlearned tile is greyed with no glow")

r = Look({ ready = true, procActive = true, buffIcon = 1 }, true, { unlearned = true, tint = "red", activeStyle = "glow" }, {})
ok(r.glow == nil and r.tint == nil, "unlearned outranks proc glow and range tint")

r = Look({ ready = true }, nil, { unlearned = false }, {})
ok(r.desat == false and r.alpha == 1, "a learned ready tile is unchanged")

ok(Nock.UI.ReactLookKey(Look({ ready = true }, nil, { unlearned = true }, {})) ~= Nock.UI.ReactLookKey(Look({ ready = true }, nil, {}, {})),
   "the look key changes, so the tile repaints on learn")

print(("react_unlearned_look: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
