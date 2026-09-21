-- Tests/swing_fill_progress_test.lua
-- Nock.UI.SwingFillProgress (UI/Widgets.lua): swing-bar fill with a visible,
-- eased close -- at the shot an unclosed bar glides shut over `ease`, stays
-- shut `hold`, then the new cycle shows its true position.
-- Run from the repo root: luajit Tests/swing_fill_progress_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b) return math.abs((a or 0) - (b or 0)) < 1e-6 end

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

local P = Nock.UI.SwingFillProgress
ok(type(P) == "function", "SwingFillProgress exists")
local HOLD, EASE, CATCH, D = 0.04, 0.06, 0.30, 2.0

-- a cycle from swingStart, sampled at `now`
local function at(h, start, now) return P(h, start, math.max(0, start + D - now), D, now, HOLD, EASE, CATCH) end

-- 1. plain progress, first cycle ever: no glide, no pre-close
local h = {}
ok(near(at(h, 100, 100), 0), "start -> 0")
ok(near(at(h, 100, 101), 0.5), "halfway -> 0.5")
ok(near(at(h, 100, 101.98), 0.99), "99% stays 0.99 (no pre-close jump)")
ok(near(at(h, 100, 102.5), 1), "held shot (past the end) -> full")

-- 2. early shot at 95%: glides shut, no jump, stays shut, then the new cycle
h = {}
at(h, 100, 100); at(h, 100, 101.9)
local r0 = at(h, 101.9, 101.9)
ok(near(r0, 0.95), "at the reset the fill is still where it was")
local r1 = at(h, 101.9, 101.9 + 0.02)
ok(r1 > 0.95 and r1 < 1, "20 ms in: gliding shut")
local r2 = at(h, 101.9, 101.9 + 0.04)
ok(r2 > r1 and r2 < 1, "40 ms in: further, still short")
ok(near(at(h, 101.9, 101.9 + 0.06), 1), "at the end of the glide: shut")
ok(near(at(h, 101.9, 101.9 + 0.08), 1), "inside the hold: still shut")
-- the restart: from empty, catching up, never a jump
local s0 = at(h, 101.9, 101.9 + 0.11)
ok(near(s0, 0), "restart begins from EMPTY, not the true 5%")
local s1 = at(h, 101.9, 101.9 + 0.20)
local true1 = 0.20 / D
ok(s1 > 0 and s1 < true1, "100 ms into the catch-up: moving, still behind the true position")
local s2 = at(h, 101.9, 101.9 + 0.25)
ok(s2 > s1, "catch-up is monotonic")
ok(near(at(h, 101.9, 101.9 + 0.45), 0.45 / D), "after the catch-up the fill is the true position")

-- 3. ease-out: the first half of the glide covers more than the second
h = {}
at(h, 100, 100); at(h, 100, 101.8)
at(h, 101.8, 101.8)
local a = at(h, 101.8, 101.83) - 0.9
local b = 1 - at(h, 101.8, 101.83)
ok(a > b, "ease-out: fast first, gentle landing")

-- 4. late shot that closed 20 ms before the reset: no glide, hold runs from the close
h = {}
at(h, 100, 100); at(h, 100, 102.0); at(h, 100, 102.02)
ok(near(at(h, 102.02, 102.02), 1), "late shot: shut at the reset")
ok(near(at(h, 102.02, 102.02 + 0.01), 1), "late shot: shut 30 ms after closing")
ok(near(at(h, 102.02, 102.02 + 0.03), 0), "late shot: 50 ms after closing the new cycle restarts from empty")
ok(near(at(h, 102.02, 102.02 + 0.40), 0.40 / D), "late shot: caught up by 400 ms")

-- 5. a shot that sat full for half a second: restarts at once
h = {}
at(h, 100, 100); at(h, 100, 102.0); at(h, 100, 102.5)
ok(near(at(h, 102.5, 102.5), 0), "long hold: the new cycle starts at once")
ok(near(at(h, 102.5, 102.6), 0.05), "long hold: no catch-up needed, plain progress")

-- 6. no duration -> 0, no crash
ok(near(P({}, 0, 5, 0, 1, HOLD, EASE), 0), "no duration -> 0")

print(("swing_fill_progress_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
