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

-- The React text style readers: reference look by default, every value
-- reachable, the shadow applied and cleared.
do
  Nock.db = Nock.db or { profile = {} }
  local p = Nock.db.profile
  p.reactFontStyle, p.reactFontShadow, p.reactTextOffsetY = nil, nil, nil
  ok(Nock.UI.GetReactFontStyle() == "OUTLINE" and Nock.UI.GetReactTextOffsetY() == 0, "reference: outline, no nudge")
  p.reactFontStyle = "NONE"; ok(Nock.UI.GetReactFontStyle() == "", "None -> no flags")
  p.reactFontStyle = "THICKOUTLINE"; ok(Nock.UI.GetReactFontStyle() == "THICKOUTLINE", "thick outline")
  p.reactFontStyle = "junk"; ok(Nock.UI.GetReactFontStyle() == "OUTLINE", "unknown -> outline")
  p.reactTextOffsetY = -2; ok(Nock.UI.GetReactTextOffsetY() == -2, "nudge read")
  ok(Nock.UI.GetReactTextOffsetX() == 0, "reference: no horizontal nudge")
  p.reactTextOffsetX = 1; ok(Nock.UI.GetReactTextOffsetX() == 1, "horizontal nudge read")
  -- The tile countdown follows both nudges: a centred string moves its
  -- centre, a boxed one (the client row) moves both corners. Re-anchored
  -- only when the nudge changes.
  local function fs()
    local f = { pts = {}, SetFont = function() return true end, GetFont = function() return "p", 9, "" end,
                SetShadowColor = function() end, SetShadowOffset = function() end }
    function f:ClearAllPoints() self.cleared = (self.cleared or 0) + 1 end
    function f:SetPoint(p, rel, rp, x, y) self.pts[#self.pts + 1] = { p, x, y } end
    return f
  end
  local slot = { SetSize = function() end, time = fs(), label = fs() }
  p.reactTextOffsetX, p.reactTextOffsetY = 1, -2
  Nock.UI.SetReactSlotSize(slot, 24)
  ok(slot.time.cleared == 1 and slot.time.pts[1][1] == "CENTER" and slot.time.pts[1][2] == 1 and slot.time.pts[1][3] == -2, "centred countdown: nudged centre")
  Nock.UI.SetReactSlotSize(slot, 24)
  ok(slot.time.cleared == 1, "same nudge: not re-anchored")
  local boxed = { SetSize = function() end, time = fs(), label = fs(), _timeBoxed = true }
  Nock.UI.SetReactSlotSize(boxed, 24)
  ok(boxed.time.pts[1][1] == "TOPLEFT" and boxed.time.pts[1][2] == 1 and boxed.time.pts[1][3] == -2 and boxed.time.pts[2][1] == "BOTTOMRIGHT" and boxed.time.pts[2][2] == 1 and boxed.time.pts[2][3] == -2, "boxed countdown: both corners nudged")
  p.reactTextOffsetX, p.reactTextOffsetY = nil, nil
  Nock.UI.SetReactSlotSize(slot, 24)
  ok(slot.time.cleared == 2 and slot.time.pts[2][2] == 0 and slot.time.pts[2][3] == 0, "back to reference: re-centred")
  local sh = { SetShadowColor = function(self, r, g, b, a) self.c = { r, g, b, a } end, SetShadowOffset = function(self, x, y) self.o = { x, y } end }
  p.reactFontShadow = true; Nock.UI.ApplyReactTextShadow(sh)
  ok(sh.o[1] == 1 and sh.o[2] == -1 and sh.c[4] == 1, "shadow on: 1 px black, down-right")
  p.reactFontShadow = false; Nock.UI.ApplyReactTextShadow(sh)
  ok(sh.o[1] == 0 and sh.o[2] == 0, "shadow off: cleared")
  p.reactFontStyle, p.reactFontShadow, p.reactTextOffsetY, p.reactTextOffsetX = nil, nil, nil, nil
end

-- The React cooldown grid's texts are React-scoped registry entries: the
-- media refresh gives them the React face, size, style and shadow (they
-- used to keep OUTLINE and no shadow whatever the skin said), and a slot
-- built after the login refresh gets the same look at creation.
do
  Nock.Constants.FONT.PATH = "ref.ttf"
  Nock.Constants.FONT.SIZE_OVERLAY = 10
  local p = Nock.db.profile
  local function fs()
    local f = { calls = {} }
    function f:SetFont(path, size, style) self.font = { path, size, style }; return true end
    function f:GetFont() return "x", 1, "" end
    function f:GetText() return "" end
    function f:SetText() end
    function f:SetShadowColor() end
    function f:SetShadowOffset(x, y) self.shadow = { x, y } end
    return f
  end
  local a, b = fs(), fs()
  Nock.UI.RegisterFontString(a, "SIZE_OVERLAY", "OUTLINE", true)
  Nock.UI.RegisterFontString(b, "SIZE_OVERLAY", "OUTLINE")
  p.reactFontSize, p.reactFontStyle, p.reactFontShadow = 8, "NONE", true
  Nock.UI.RefreshMedia()
  ok(a.font[2] == 10 and a.font[3] == "" and a.shadow[1] == 1 and a.shadow[2] == -1, "React-scoped text: its own size (10 by default), the React style and shadow")
  p.reactCdFontSize = 12
  Nock.UI.RefreshMedia()
  ok(a.font[2] == 12, "the cooldown grid's own font size")
  p.reactCdFontSize = nil
  ok(b.font[2] == 10 and b.font[3] == "OUTLINE" and b.shadow == nil, "global text: untouched by the React skin")
  local c = fs()
  Nock.UI.ApplyReactTextLook(c, "SIZE_OVERLAY")
  ok(c.font[1] == "ref.ttf" and c.font[2] == 10 and c.font[3] == "" and c.shadow[1] == 1, "ApplyReactTextLook: the same look at creation")
  p.reactFontSize, p.reactFontStyle, p.reactFontShadow = nil, nil, nil
  Nock.UI.RefreshMedia()
  ok(a.font[2] == 10 and a.font[3] == "OUTLINE" and a.shadow[1] == 0, "reference skin: outline, no shadow")
end

-- The cooldown grid's countdown text: tenths under 10 s by default (the
-- reference), whole seconds on request; minutes from 90 s either way.
do
  local F = Nock.UI.FormatCooldownText
  ok(F(0) == "" and F(-1) == "", "no cooldown: empty")
  ok(F(2.34) == "2.3" and F(9.96) == "10.0", "tenths under 10 s")
  ok(F(2.34, true) == "3" and F(0.2, true) == "1" and F(9.96, true) == "10", "whole seconds: rounded up, never 0")
  ok(F(45.2) == "46" and F(45.2, true) == "46", "10..90 s: whole seconds either way")
  ok(F(125) == "2m" and F(125, true) == "2m", "from 90 s: minutes")
end

-- SafeSetFont: the first successful user of a font path in the session
-- bounces the size once (the first-use blank), later users set once.
do
  local calls = {}
  local fs = { SetFont = function(self, path, size, style) calls[#calls + 1] = { path, size }; return true end }
  Nock.UI.SafeSetFont(fs, "Media/X.otf", 12, "OUTLINE")
  ok(#calls == 3 and calls[1][2] == 12 and calls[2][2] == 13 and calls[3][2] == 12, "first use of a path: size, size+1, size")
  calls = {}
  Nock.UI.SafeSetFont(fs, "Media/X.otf", 12, "OUTLINE")
  ok(#calls == 1, "a warm path sets once")
  calls = {}
  local bad = { SetFont = function(self, path, size, style) calls[#calls + 1] = { path, size }; return path ~= "Media/Missing.otf" end }
  Nock.UI.SafeSetFont(bad, "Media/Missing.otf", 12, "OUTLINE")
  ok(calls[#calls][1] ~= "Media/Missing.otf", "a refused path falls back to the stock font")
end

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
    tex = nil, desat = nil, coords = nil, coordSets = 0,
    SetTexture     = function(s, t) s.tex = t end,
    SetDesaturated = function(s, d) s.desat = d end,
    SetTexCoord    = function(s, a, b, c, d) s.coords = { a, b, c, d }; s.coordSets = s.coordSets + 1 end,
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
-- Texture crop: the spell-icon crop by default, an item's own `coords`
-- (an atlas cell, e.g. the pet happiness face) when given; diffed.
ok(s.icon.coords and s.icon.coords[1] == 0.08 and s.icon.coords[2] == 0.92 and s.icon.coordSets == 1, "default crop applied once")
Paint(s, { icon = 1, exp = 130, dur = 120, desat = false }, 101)
ok(s.icon.coordSets == 1, "same crop -> no SetTexCoord")
local CELL = { 0.375, 0.5625, 0, 0.359375 }
Paint(s, { icon = 2, exp = 0, dur = 0, coords = CELL }, 101)
ok(s.icon.coords[1] == 0.375 and s.icon.coords[4] == 0.359375 and s.icon.coordSets == 2, "item coords applied")
Paint(s, { icon = 2, exp = 0, dur = 0, coords = CELL }, 102)
ok(s.icon.coordSets == 2, "same coords table -> no SetTexCoord")
Paint(s, { icon = 1, exp = 130, dur = 120 }, 102)
ok(s.icon.coords[1] == 0.08 and s.icon.coordSets == 3, "back to the default crop")
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

-- Raptor GO glow (React move-in cue): opts.goGlow lights the Raptor slot with
-- the overlay glow while the weave coach says GO, whatever the slot's own
-- state. Nothing else in the look changes, and without the flag nothing does.
r = look(ready, false, { tint = "off", goGlow = true });               ok(r.vis == "ready" and r.glow == "overlay", "goGlow on a ready slot: overlay glow")
r = look(oncd, false, { tint = "off", goGlow = true });                ok(r.vis == "cd" and r.glow == "overlay", "goGlow on a slot on cooldown: still the overlay (the coach already folded the CD in)")
r = look(ready, true, { tint = "red", goGlow = true });                ok(r.glow == "overlay" and r.tint == "red", "goGlow + out of range: glow AND red")
r = look(ready, false, { tint = "off", goGlow = false });              ok(r.glow == nil, "goGlow false: no glow")
r = look(ready, false, { tint = "off" });                              ok(r.glow == nil, "goGlow absent: no glow")
local kg = Nock.UI.ReactLookKey(look(ready, false, { tint = "off", goGlow = true }))
local kn = Nock.UI.ReactLookKey(look(ready, false, { tint = "off" }))
ok(kg ~= kn, "the look key changes with goGlow, so the painter repaints on GO's edges")

-- LookKey: one string per distinct look, so the painter's diff can key on it.
local k1 = Nock.UI.ReactLookKey(look(ready, true,  { tint = "red" }))
local k2 = Nock.UI.ReactLookKey(look(ready, false, { tint = "red" }))
local k3 = Nock.UI.ReactLookKey(look(ready, true,  { tint = "red" }))
local k4 = Nock.UI.ReactLookKey(look({ ready = true, usable = false }, false, { tint = "off", dim = true }))
local k5 = Nock.UI.ReactLookKey(look({ ready = true, usable = true },  false, { tint = "off", dim = true }))
ok(k1 ~= k2 and k1 == k3 and k4 ~= k5, "the look key changes with the range / dim and is stable otherwise")

-- Reactive spells (Mongoose Bite): greyed while unusable whatever the dim toggle.
do
  local Look = Nock.UI.ReactSlotLook
  local r = Look({ ready = true, reactive = true, usable = false }, nil, { dim = false })
  ok(r.vis == "ready" and r.desat == true and r.alpha == 0.6, "reactive + unusable: greyed with dim off")
  r = Look({ ready = true, reactive = true, usable = true }, nil, { dim = false })
  ok(r.desat == false and r.alpha == 1, "reactive + usable (after a dodge): bright")
  r = Look({ ready = true, reactive = true, usable = nil }, nil, { dim = false })
  ok(r.desat == false and r.alpha == 1, "reactive, usability unknown (secret): the ready look stays")
  r = Look({ ready = true, reactive = false, usable = false }, nil, { dim = false })
  ok(r.desat == false and r.alpha == 1, "a normal unusable spell with dim off: unchanged (opt-in)")
end

print(("react_slot_paint: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
