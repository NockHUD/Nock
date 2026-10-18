-- Tests/react_sting_grey_look_test.lua
-- Standalone LuaJIT tests for the sting tile's grey look (Grid -> Sting tiles
-- grey, 2026-10-18): the slot under a sting's aura container is desaturated so
-- the client's full-colour button reads as the sting landing.
-- Run from the repo root: luajit Tests/react_sting_grey_look_test.lua

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
local Look = Nock.UI.ReactSlotLook

local r = Look({ ready = true, procActive = false }, nil, { stingGrey = true }, {})
ok(r.desat == true and r.alpha == 1 and r.tint == nil and r.vis == "ready", "a sting slot under its container is greyed at full alpha")
r = Look({ ready = true, procActive = false }, nil, { stingGrey = false }, {})
ok(r.desat == false, "toggle off: the sting slot is unchanged")
r = Look({ ready = true }, true, { stingGrey = true, tint = "red" }, {})
ok(r.desat == true and r.tint == "red", "out of range: the red tint still applies over the grey")
r = Look({ ready = true }, nil, { stingGrey = true, unlearned = true }, {})
ok(r.desat == true and r.alpha == 0.35, "unlearned still fades the tile")
ok(Nock.UI.ReactLookKey(Look({ ready = true }, nil, { stingGrey = true }, {})) ~= Nock.UI.ReactLookKey(Look({ ready = true }, nil, {}, {})),
   "the look key changes, so the tile repaints when the toggle flips")

print(("react_sting_grey_look: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
