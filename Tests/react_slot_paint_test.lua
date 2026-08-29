-- Tests/react_slot_paint_test.lua
-- Standalone LuaJIT tests for Nock.UI.PaintReactSlot, the shared React icon
-- repainter behind the React buff row and the React corner icons.
-- Run from the repo root: luajit Tests/react_slot_paint_test.lua
--
-- What's actually under test is the DIFF CACHE. Every mutation in PaintReactSlot
-- sits behind a "did this change" guard so the 10 Hz lane costs nothing when
-- idle, and the failure mode of a guard that's too eager is text that silently
-- never appears (or never clears) — invisible in review, obvious in a raid.
-- The three modes each own the bottom FontString differently:
--   * countdown only  -> label empty
--   * countdown + sub -> label carries the caption (mark icon's caster name)
--   * label           -> countdown empty, label carries the state word
-- so every transition between them is exercised in both directions.
--
-- Harness note: see Tests/react_countdown_test.lua — UI/Widgets.lua's only
-- load-time work needs a LibStub lookup and one inert CreateFrame.

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

local Paint = Nock.UI.PaintReactSlot
ok(type(Paint) == "function", "Nock.UI.PaintReactSlot exists")

-- Recording stand-ins. `sets` counts SetText calls so an idle repaint can be
-- proven free, not merely correct.
local function fontString()
  local fs = { text = "", color = nil, sets = 0 }
  function fs:SetText(t) self.text = t; self.sets = self.sets + 1 end
  function fs:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
  return fs
end

local function newSlot()
  local slot = { time = fontString(), label = fontString() }
  slot.icon = {
    tex = nil, desat = nil,
    SetTexture     = function(s, t) s.tex = t end,
    SetDesaturated = function(s, d) s.desat = d end,
  }
  return slot
end

local function isRed(c) return c and c[1] > 0.7 and c[2] < 0.3 end

--------------------------------------------------------------------------------
-- Countdown mode with no caption: the bottom line stays empty.
--------------------------------------------------------------------------------
local s = newSlot()
Paint(s, { icon = 1, exp = 130, dur = 120, desat = false }, 100)
ok(s.time.text == "30", "countdown renders the remaining seconds")
ok(s.label.text == "", "no sub -> bottom line empty")
ok(s.icon.tex == 1 and s.icon.desat == false, "icon + desaturation applied")

--------------------------------------------------------------------------------
-- The caption rides ALONGSIDE the countdown — this is the mark icon's case, and
-- the whole point of `sub` existing separately from `label`.
--------------------------------------------------------------------------------
s = newSlot()
Paint(s, { icon = 1, exp = 130, dur = 120, sub = "Legolas" }, 100)
ok(s.time.text == "30",       "sub does not suppress the countdown")
ok(s.label.text == "Legolas", "sub renders on the bottom line")
ok(not isRed(s.label.color),  "a caption is plain white, not the MISSING red")

-- An idle repaint must touch nothing at all.
local timeSets, labelSets = s.time.sets, s.label.sets
Paint(s, { icon = 1, exp = 130, dur = 120, sub = "Legolas" }, 100)
ok(s.time.sets == timeSets and s.label.sets == labelSets, "identical repaint is free")

-- A changed caster replaces the caption; the countdown keeps ticking.
Paint(s, { icon = 1, exp = 130, dur = 120, sub = "Aragorn" }, 101)
ok(s.label.text == "Aragorn" and s.time.text == "29", "caption and countdown update together")

-- Caption goes away (client stops naming the caster) but the mark is still up:
-- the countdown must survive and the bottom line must clear.
Paint(s, { icon = 1, exp = 130, dur = 120 }, 101)
ok(s.label.text == "" and s.time.text == "29", "dropping sub clears only the caption")

--------------------------------------------------------------------------------
-- Label mode still wins the bottom line outright, in both directions.
--------------------------------------------------------------------------------
s = newSlot()
Paint(s, { icon = 1, exp = 130, dur = 120, sub = "Legolas" }, 100)
Paint(s, { icon = 1, label = "MISSING", desat = true }, 100)
ok(s.time.text == "" ,            "label mode blanks the countdown")
ok(s.label.text == "MISSING",     "label mode owns the bottom line")
ok(isRed(s.label.color),          "MISSING is red")

-- ...and back. The red must not be left behind on the next caption.
Paint(s, { icon = 1, exp = 130, dur = 120, sub = "Legolas" }, 100)
ok(s.label.text == "Legolas" and s.time.text == "30", "back to countdown + caption")
ok(not isRed(s.label.color), "the MISSING red does not survive into a caption")

-- A label identical to the caption it replaces must still repaint (the diff key
-- is shared between the two modes).
s = newSlot()
Paint(s, { icon = 1, exp = 130, dur = 120, sub = "MISSING" }, 100)
ok(not isRed(s.label.color), "a caption that happens to read MISSING is not red")
Paint(s, { icon = 1, label = "MISSING" }, 100)
ok(s.label.text == "MISSING" and isRed(s.label.color), "same string, label mode -> red")

--------------------------------------------------------------------------------
-- Label mode ignores `sub` outright: one FontString, and `label` asked first.
--------------------------------------------------------------------------------
s = newSlot()
Paint(s, { icon = 1, label = "RANGE", sub = "Legolas" }, 100)
ok(s.label.text == "RANGE", "label beats sub when both are present")

print(("react_slot_paint: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
