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

--------------------------------------------------------------------------------
-- ReactSlotLook: the React cooldown grid's look decision as a pure function.
-- Look(cd, out, opts, res) fills and returns `res`:
--   vis     "proc" | "ready" | "cd"
--   glow    "overlay" | "border" | nil     (overlay = the WA's action-button glow)
--   desat   grey icon (consumable recharging, grey range tint, dim, no mana)
--   tint    "red" (out of range) | "blue" (no mana) | nil
--   alpha   1, or 0.6 while dimmed (the WA's "unavailable")
--------------------------------------------------------------------------------
local Look = Nock.UI.ReactSlotLook
ok(type(Look) == "function", "Nock.UI.ReactSlotLook exists")
local R = {}
local function look(cd, out, opts) return Look(cd, out, opts, R) end

local proc  = { procActive = true,  ready = false }
local ready = { procActive = false, ready = true }
local oncd  = { procActive = false, ready = false, remaining = 10 }
local OFF   = { procGlow = false, tint = "off" }

-- Proc glow: border by default, the overlay only for the slot the option names.
local r = look(proc, false, OFF)
ok(r.vis == "proc" and r.glow == "border", "proc without the option: the static border")
r = look(proc, false, { procGlow = true, tint = "off" })
ok(r.vis == "proc" and r.glow == "overlay", "proc with the option: the overlay glow")
r = look(ready, false, { procGlow = true, tint = "off" })
ok(r.vis == "ready" and r.glow == nil, "no proc: no glow whatever the option")

-- Out of range: off / red / grey; never without the flag.
r = look(ready, true, OFF);                             ok(not r.desat and r.tint == nil, "tint off: out of range changes nothing")
r = look(ready, true, { tint = "red" });                ok(r.tint == "red" and not r.desat, "tint red: red, not desaturated")
r = look(ready, true, { tint = "grey" });               ok(r.desat and r.tint == nil, "tint grey: desaturated, not red")
r = look(ready, false, { tint = "red" });               ok(not r.desat and r.tint == nil, "in range: no tint")
r = look(ready, nil, { tint = "red" });                 ok(not r.desat and r.tint == nil, "unknown range (no target, an item slot): no tint")
r = look(proc, true, { procGlow = true, tint = "red" }); ok(r.vis == "proc" and r.glow == "overlay" and r.tint == "red", "proc + out of range: overlay glow AND red")

-- Consumable rows keep their recharging grey.
r = look(oncd, false, { tint = "off", whenActive = true });  ok(r.vis == "cd" and r.desat, "whenActive row on cooldown: desaturated")
r = look(ready, false, { tint = "off", whenActive = true }); ok(not r.desat, "whenActive row ready: full colour")
r = look(oncd, false, { tint = "grey" });                    ok(not r.desat and r.alpha == 1, "rotation row on cooldown, in range, no dim: untouched")

-- Dim while unavailable (WA condition 1): on cooldown OR not usable -> grey at 0.6.
r = look(oncd, false, { tint = "off", dim = true });                       ok(r.desat and r.alpha == 0.6, "dim: on cooldown -> grey, 0.6")
r = look({ ready = true, usable = false }, false, { tint = "off", dim = true }); ok(r.desat and r.alpha == 0.6, "dim: ready but not usable (no proc / pet dead) -> grey, 0.6")
r = look({ ready = true, usable = true }, false, { tint = "off", dim = true });  ok(not r.desat and r.alpha == 1, "dim: ready and usable -> full")
r = look(ready, false, { tint = "off", dim = true });                      ok(not r.desat and r.alpha == 1, "dim: usability unknown (item) -> full")
r = look(proc, false, { tint = "off", dim = true, procGlow = true });      ok(not r.desat and r.alpha == 1 and r.glow == "overlay", "dim never touches a proc")
r = look(oncd, false, { tint = "off", dim = false });                      ok(not r.desat and r.alpha == 1, "dim off: nothing")

-- No mana (WA condition 4): blue + grey; out of range (5) wins over it.
r = look({ ready = true, noMana = true }, false, { tint = "off", manaTint = true }); ok(r.tint == "blue" and r.desat, "no mana: blue, desaturated")
r = look({ ready = true, noMana = true }, false, { tint = "off" });                  ok(r.tint == nil, "no mana without the option: nothing")
r = look({ ready = true, noMana = true }, true, { tint = "red", manaTint = true });  ok(r.tint == "red", "no mana AND out of range: red wins")

-- LookKey: one string per distinct look, so the painter's diff can key on it.
local k1 = Nock.UI.ReactLookKey(look(ready, true,  { tint = "red" }))
local k2 = Nock.UI.ReactLookKey(look(ready, false, { tint = "red" }))
local k3 = Nock.UI.ReactLookKey(look(ready, true,  { tint = "red" }))
local k4 = Nock.UI.ReactLookKey(look({ ready = true, usable = false }, false, { tint = "off", dim = true }))
local k5 = Nock.UI.ReactLookKey(look({ ready = true, usable = true },  false, { tint = "off", dim = true }))
ok(k1 ~= k2 and k1 == k3 and k4 ~= k5, "the look key changes with the range / dim and is stable otherwise")

print(("react_slot_paint: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
