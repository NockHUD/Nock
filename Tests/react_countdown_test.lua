-- Tests/react_countdown_test.lua
-- Standalone LuaJIT tests for Nock.UI.ReactCountdown, the shared countdown
-- encoding behind the React buff row and the React corner icons.
-- Run from the repo root: luajit Tests/react_countdown_test.lua
--
-- UI/Widgets.lua is a WoW addon file. Its load-time work is a LibStub lookup,
-- two LSM blocks (both guarded by `if LSM then`, so absent LibSharedMedia they
-- no-op), and one event frame that re-applies header fonts at login — hence the
-- inert CreateFrame stub below. ReactCountdown itself is pure; nothing it
-- touches needs the WoW API.

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = {
  db = { profile = {} },
  -- Any constants table the file touches resolves to an empty table.
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
-- Inert frame: Widgets.lua builds one login-event listener at load. Everything
-- else in the file only creates frames from inside a function we never call.
_G.CreateFrame = function()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end

dofile("UI/Widgets.lua")

local RC = Nock.UI.ReactCountdown
ok(type(RC) == "function", "Nock.UI.ReactCountdown exists")

--------------------------------------------------------------------------------
-- Steady auras: no expiry or no duration means no text at all.
--------------------------------------------------------------------------------
local tval, text, low = RC(0, 0, 100)
ok(tval == 0 and text == "" and low == false, "exp 0 / dur 0 renders nothing")
tval, text = RC(0, 30, 100)
ok(tval == 0 and text == "", "no expiry renders nothing even with a duration")
tval, text = RC(160, 0, 100)
ok(tval == 0 and text == "", "no duration renders nothing even with an expiry")

--------------------------------------------------------------------------------
-- Seconds band: under 90s remaining, whole seconds, rounded UP.
--------------------------------------------------------------------------------
tval, text, low = RC(124, 30, 100)
ok(tval == 24 and text == "24", "24s remaining renders as 24")
ok(low == false, "24s is not the expiring-red band")
tval, text = RC(100.2, 30, 100)
ok(tval == 1 and text == "1", "fractional remainder rounds up to the next second")
tval, text = RC(189.9, 300, 100)
ok(tval == 90 and text == "90", "89.9s remaining stays in the seconds band")

--------------------------------------------------------------------------------
-- Minutes band: 90s and over, whole minutes, rounded UP, negative tval.
--------------------------------------------------------------------------------
tval, text, low = RC(190, 300, 100)
ok(tval == -2 and text == "2m", "90s remaining renders as 2m")
ok(low == false, "the minutes band is never expiring-red")
tval, text = RC(400, 300, 100)
ok(tval == -5 and text == "5m", "300s remaining renders as 5m")

--------------------------------------------------------------------------------
-- Expiring-red band: 1..3 seconds inclusive.
--------------------------------------------------------------------------------
ok(select(3, RC(103, 30, 100)) == true,  "3s remaining is expiring-red")
ok(select(3, RC(100.1, 30, 100)) == true, "a sliver of a second is expiring-red")
ok(select(3, RC(104, 30, 100)) == false, "4s remaining is not expiring-red")

--------------------------------------------------------------------------------
-- Already expired: clamped to zero, never negative seconds.
--------------------------------------------------------------------------------
tval, text, low = RC(90, 30, 100)
ok(tval == 0 and text == "" and low == false, "an expired aura renders nothing")

--------------------------------------------------------------------------------
print(("react_countdown_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
