-- Tests/grid_gcd_swipe_test.lua
-- The grid's GCD swipe (UI/Widgets.lua, gridGcdSwipe): fed from each tile's
-- own spell cooldown, cleared for items and for a tile on its own cooldown;
-- TBC takes a GCD-length reading, Forever the client's duration object.
-- Run from the repo root: luajit Tests/grid_gcd_swipe_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = {
  db = { profile = {} },
  Constants = setmetatable({}, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }),
  Flavor = { forever = false },
}
local libs = { ["AceAddon-3.0"] = { GetAddon = function() return Nock end } }
_G.LibStub = setmetatable({}, { __call = function(_, name, silent)
  local lib = libs[name]
  if not lib and not silent then error("harness: missing lib " .. name) end
  return lib
end })
-- A Cooldown that records what it was told.
local function cooldown()
  local c = { level = 5 }
  function c:RegisterEvent() end
  function c:SetScript() end
  function c:SetAllPoints(r) self.pinned = r end
  function c:SetFrameLevel(l) self.level = l end
  function c:GetFrameLevel() return self.level end
  function c:SetHideCountdownNumbers(v) self.hideNumbers = v end
  function c:SetDrawEdge(v) self.edge = v end
  function c:SetDrawBling(v) self.bling = v end
  function c:SetSwipeColor(r, g, b, a) self.swipeA = a end
  function c:SetCooldown(s, d) self.set = { s, d } end
  function c:SetCooldownFromDurationObject(o, clear) self.obj, self.clearIfZero = o, clear end
  function c:Clear() self.set, self.obj, self.cleared = nil, nil, true end
  return c
end
_G.CreateFrame = function() return cooldown() end
dofile("UI/Widgets.lua")
local UI = Nock.UI

ok(UI.IsGcdReading(100, 1.5) and UI.IsGcdReading(100, 1.2), "a GCD-length reading counts")
ok(not UI.IsGcdReading(100, 6) and not UI.IsGcdReading(0, 1.5) and not UI.IsGcdReading(nil, nil), "a real cooldown, no start, or nothing: not the GCD")

local slot = { icon = {}, cooldown = cooldown() }
local g = UI.EnsureGcdSwipe(slot)
ok(g and slot.gcdCd == g and g.pinned == slot.icon, "the swipe sits on the icon")
ok(g.level == slot.cooldown.level and g.hideNumbers and g.edge == false and g.noCooldownCount, "under the tile's own swipe level, no numbers, no edge, no OmniCC text")
ok(g.swipeA < 0.75, "lighter than the tile's own swipe")
ok(UI.EnsureGcdSwipe(slot) == g, "made once")

-- TBC: the spell's own cooldown reading.
local reading = {}
Nock.API = { SpellCooldown = function(id) return reading[id] and reading[id][1], reading[id] and reading[id][2] end }
reading[3044] = { 200, 1.5 }
UI.FeedGcdSwipe(slot, 3044, false)
ok(g.set and g.set[1] == 200 and g.set[2] == 1.5, "TBC: a spell on the GCD swipes for it")
reading[34026] = { 0, 0 }
UI.FeedGcdSwipe(slot, 34026, false)
ok(g.set == nil and g.cleared, "TBC: a spell off the GCD (Kill Command) does not")
UI.FeedGcdSwipe(slot, 3044, true)
ok(g.set == nil, "a tile on its own cooldown: cleared")
UI.FeedGcdSwipe(slot, nil, false)
ok(g.set == nil, "an item tile (no spell): cleared")

-- Forever: the client's duration object, handed over unread.
Nock.Flavor.forever = true
local OBJ = { secret = true }
Nock.API.SpellCooldownDuration = function(id) if id == 3044 then return OBJ end end
UI.FeedGcdSwipe(slot, 3044, false)
ok(g.obj == OBJ and g.clearIfZero == true, "Forever: the duration object, cleared by the client when zero")
UI.FeedGcdSwipe(slot, 99, false)
ok(g.obj == nil and g.cleared, "Forever: no object -> cleared")

-- No swipe made yet: feeding is a no-op.
ok(pcall(UI.FeedGcdSwipe, { icon = {} }, 3044, false), "a slot without a swipe is left alone")

print(("grid_gcd_swipe: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
