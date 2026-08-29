-- Tests/range_engine_test.lua
-- Standalone LuaJIT tests for the pure RangeFinder glide engine.
-- Run from the repo root: luajit Tests/range_engine_test.lua

local Engine = dofile("Modules/RangeEngine.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-6) end

local SW = Engine.SWEET_I

-- 1. fresh state + in-place reset
local s = Engine.New()
ok(s.state == "LONG" and s.prog == -1, "New(): LONG at -1")
Engine.Step(s, true, true, false, 0, 0, 0.016)
Engine.Reset(s)
ok(s.state == "LONG" and s.prog == -1 and s.resync == false, "Reset(): back to LONG at -1")

-- 2. LONG -> CLOSE snaps to -0.9999
s = Engine.New()
Engine.Step(s, true, false, false, 0, 0, 0.016)
ok(s.state == "CLOSE" and near(s.prog, -0.9999), "LONG->CLOSE snap")

-- 3. CLOSE -> SWEET snaps to -sweet_interval
Engine.Step(s, true, true, false, 0, 0, 0.016)
ok(s.state == "SWEET" and near(s.prog, -SW), "CLOSE->SWEET snap")

-- 4. enter MELEE snaps to 0
Engine.Step(s, true, true, true, 0, 0, 0.016)
ok(s.state == "MELEE" and near(s.prog, 0), "enter MELEE snap")

-- 5. exit MELEE snaps to -0.0001 (lands in SWEET = the PERFECT sliver)
Engine.Step(s, true, true, false, 0, 0, 0.016)
ok(s.state == "SWEET" and near(s.prog, -0.0001), "exit MELEE snap")
ok(s.prog > Engine.PERFECT_AT, "exit MELEE lands in PERFECT sliver")

-- 6. closing integration (trapezoid: first step averages lastSpeed=0 and 7)
s = Engine.New()
Engine.Step(s, true, true, false, 0, 0, 0.016)   -- into SWEET, prog = -SW
local before = s.prog
Engine.Step(s, true, true, false, 7, 0, 0.1)
ok(near(s.prog, before + ((0 + 7) / 2 / 8.5) * 0.1, 1e-4), "trapezoid closing step")

-- 7. clamp: running forward in SWEET for 3s pins at -0.0001, never crosses 0
s = Engine.New()
Engine.Step(s, true, true, false, 0, 0, 0.016)
for _ = 1, 30 do Engine.Step(s, true, true, false, 7, 0, 0.1) end
ok(s.prog <= -0.0001 + 1e-9, "SWEET clamp holds at melee edge")

-- 8. retreating (speed <= 4.5) decreases prog
s = Engine.New()
Engine.Step(s, true, true, false, 0, 0, 0.016)
Engine.Step(s, true, true, false, 7, 0, 0.1)      -- move up a bit first
local up = s.prog
Engine.Step(s, true, true, false, 2.5, 0, 0.1)
ok(s.prog < up, "backpedal decreases prog")

-- 9. target moving -> resync, prog pinned to seed; target stops -> instant clear
s = Engine.New()
Engine.Step(s, true, true, false, 0, 0, 0.016)
Engine.Step(s, true, true, false, 0, 1.0, 0.1)
ok(s.resync == true, "target moving triggers resync")
ok(near(s.prog, Engine.SEED.SWEET), "resync pins prog to band seed")
Engine.Step(s, true, true, false, 0, 0, 0.1)
ok(s.resync == false, "target stopping clears resync")

-- 10. worn: pinned at a clamp edge while moving > dwell -> latched resync;
--     stays latched while moving, clears after standing still
s = Engine.New()
Engine.Step(s, true, true, false, 0, 0, 0.016)
for _ = 1, 30 do Engine.Step(s, true, true, false, 7, 0, 0.1) end  -- ride the edge 3s
ok(s.resync == true, "edge-pinned while moving latches resync (worn)")
Engine.Step(s, true, true, false, 7, 0, 0.1)
ok(s.resync == true, "worn stays latched while still moving")
for _ = 1, 4 do Engine.Step(s, true, true, false, 0, 0, 0.1) end   -- stand still 0.4s
ok(s.resync == false, "standing still ends worn resync")

-- 11. boundary crossing clears worn instantly
s = Engine.New()
Engine.Step(s, true, true, false, 0, 0, 0.016)
for _ = 1, 30 do Engine.Step(s, true, true, false, 7, 0, 0.1) end
ok(s.resync == true, "worn latched (setup)")
Engine.Step(s, true, true, true, 7, 0, 0.016)     -- cross into MELEE
-- same-frame integration adds one small step past the snap; allow it
ok(s.resync == false and near(s.prog, 0, 0.05), "crossing clears worn and snaps")

-- 12. LONG: prog hard -1, never resyncs
s = Engine.New()
Engine.Step(s, false, false, false, 7, 5, 0.1)
ok(s.state == "LONG" and s.prog == -1 and s.resync == false, "LONG parks at -1, no resync")

-- ---- bracket resolver ----
local function R(t) return t end  -- readability helper

-- Hawk Eye 3, Scatter known: full WA rank-3 ladder
ok(Engine.ResolveBracket(R{ i13289=true, i10645=true, i33069=true }, 3, true, false) == "10_15", "HE3 10-15")
ok(Engine.ResolveBracket(R{ i13289=true, i10645=true }, 3, true, false) == "15_20", "HE3 15-20")
ok(Engine.ResolveBracket(R{ i13289=true, scatter=true }, 3, true, false) == "20_21", "HE3 20-21")
ok(Engine.ResolveBracket(R{ i13289=true }, 3, true, false) == "21_25", "HE3 21-25")
ok(Engine.ResolveBracket(R{ i18904=true, i7734=true }, 3, true, false) == "25_30", "25-30")
ok(Engine.ResolveBracket(R{ i18904=true }, 3, true, false) == "30_35", "30-35")
ok(Engine.ResolveBracket(R{ autoShot=true, i4945=true }, 3, true, false) == "35_40", "HE3 35-40")
ok(Engine.ResolveBracket(R{ autoShot=true }, 3, true, false) == "40_41", "HE3 40-41")

-- Hawk Eye 0, no Scatter: coarse ladder
ok(Engine.ResolveBracket(R{ i13289=true, i33069=true }, 0, false, false) == "10_15", "HE0 10-15")
ok(Engine.ResolveBracket(R{ i13289=true, i10645=true }, 0, false, false) == "15_20", "HE0 15-20")
ok(Engine.ResolveBracket(R{ i13289=true }, 0, false, false) == "20_25", "HE0 20-25")

-- Hawk Eye 1 & 2 scatter-edge brackets
ok(Engine.ResolveBracket(R{ i13289=true, scatter=true }, 1, true, false) == "15_17", "HE1 15-17")
ok(Engine.ResolveBracket(R{ i13289=true, i10645=true }, 1, true, false) == "17_20", "HE1 17-20")
ok(Engine.ResolveBracket(R{ i13289=true, scatter=true }, 2, true, false) == "15_19", "HE2 15-19")
ok(Engine.ResolveBracket(R{ i13289=true, i10645=true }, 2, true, false) == "19_20", "HE2 19-20")
ok(Engine.ResolveBracket(R{ autoShot=true }, 2, true, false) == "35_39", "HE2 35-39")
ok(Engine.ResolveBracket(R{ autoShot=true }, 1, true, false) == "35_37", "HE1 35-37")

-- Out-of-range edges
ok(Engine.ResolveBracket(R{}, 3, true, false) == "OOR", "OOR (no HM)")
ok(Engine.ResolveBracket(R{ hm=true }, 3, true, true) == "OOR", "OOR (HM reaches)")
ok(Engine.ResolveBracket(R{ hm=false }, 3, true, true) == "HM_OOR", "HM_OOR")

-- BRACKETS metadata sanity
ok(Engine.BRACKETS["10_15"].fill < Engine.BRACKETS["30_35"].fill, "drain fill grows with distance")
ok(Engine.BRACKETS["OOR"].fill == 1, "OOR fill = 1")
for k, b in pairs(Engine.BRACKETS) do
  ok(type(b.label) == "string" and type(b.fill) == "number" and type(b.block) == "table",
     "bracket shape: " .. k)
end

-- ---- zoomed glide fill (experimental, credit Erda) ----
-- Viewport crop of the original (prog+1)/2 mapping: the outer ZOOM_CROP of
-- the fill is shaven off EACH side, the middle window stretched to the full
-- bar. Same layout, same centered tick — everything just moves 2x faster.
if type(Engine.ZoomFill) ~= "function" then
  ok(false, "ZoomFill exists")
else
  ok(Engine.ZOOM_DEFAULT == 2, "zoom: default level is 2x")
  -- The melee boundary stays at bar center at EVERY zoom level.
  ok(near(Engine.ZoomFill(0, 1), 0.5), "zoom: center at 1x")
  ok(near(Engine.ZoomFill(0, 2), 0.5), "zoom: center at 2x")
  ok(near(Engine.ZoomFill(0, 3.5), 0.5), "zoom: center at 3.5x")
  -- 1x is the identity: the original (prog+1)/2 mapping, no crop.
  ok(near(Engine.ZoomFill(-0.6, 1), 0.2), "zoom: 1x = original mapping")
  ok(near(Engine.ZoomFill(-1, 1), 0) and near(Engine.ZoomFill(1, 1), 1), "zoom: 1x uses the full bar")
  -- No level given = default 2x.
  ok(near(Engine.ZoomFill(-0.2), Engine.ZoomFill(-0.2, 2)), "zoom: nil level = 2x")
  -- 2x window is prog [-0.5, 0.5] (the outer 25% of fill per side shaven off).
  ok(near(Engine.ZoomFill(-0.5, 2), 0), "zoom: 2x window edge (prog -0.5) -> empty")
  ok(near(Engine.ZoomFill(0.5, 2), 1), "zoom: 2x window edge (prog 0.5) -> full")
  ok(Engine.ZoomFill(-1, 2) == 0 and Engine.ZoomFill(-0.7, 2) == 0, "zoom: 2x clamps beyond left window")
  ok(Engine.ZoomFill(1, 2) == 1 and Engine.ZoomFill(0.8, 2) == 1, "zoom: 2x clamps beyond right window")
  ok(near(Engine.ZoomFill(Engine.PERFECT_AT, 2), 0.4), "zoom: 2x PERFECT_AT -> 0.4")
  -- The window is prog [-1/z, 1/z]: 4x shows only the middle quarter.
  ok(near(Engine.ZoomFill(-0.25, 4), 0), "zoom: 4x window edge (prog -0.25) -> empty")
  ok(near(Engine.ZoomFill(0.25, 4), 1), "zoom: 4x window edge (prog 0.25) -> full")
  ok(Engine.ZoomFill(-0.3, 4) == 0 and Engine.ZoomFill(0.3, 4) == 1, "zoom: 4x clamps outside its window")
  -- Slider goes to 8x: window is the middle eighth.
  ok(near(Engine.ZoomFill(-0.125, 8), 0) and near(Engine.ZoomFill(0.125, 8), 1)
     and near(Engine.ZoomFill(0, 8), 0.5), "zoom: 8x window edges + centered tick")
  -- Travel scales with the level: a 0.1 prog step is 0.05 fill un-zoomed.
  ok(near(Engine.ZoomFill(-0.2, 2) - Engine.ZoomFill(-0.3, 2), 2 * 0.05), "zoom: 2x travel")
  ok(near(Engine.ZoomFill(-0.1, 4) - Engine.ZoomFill(-0.2, 4), 4 * 0.05), "zoom: 4x travel")
  -- Monotone non-decreasing everywhere, strictly increasing inside the window.
  for _, z in ipairs({ 1.5, 2, 3, 4 }) do
    local mono, strict, last = true, true, Engine.ZoomFill(-1, z)
    for i = 1, 40 do
      local p = -1 + i * 0.05
      local f = Engine.ZoomFill(p, z)
      if f < last then mono = false end
      if p > -1 / z + 0.05 and p < 1 / z and f <= last then strict = false end
      last = f
    end
    ok(mono, "zoom: non-decreasing at " .. z .. "x")
    ok(strict, "zoom: strictly increasing inside the " .. z .. "x window")
  end
end

--------------------------------------------------------------------------------
-- SlotOut: the React grid's per-slot out-of-range answer. A ranged ability
-- trusts IsSpellInRange; a next-melee ability (Raptor Strike) does NOT -- the
-- Anniversary client answers "in range" for it at 30 yd (diag 2026-08-29) --
-- so it follows the Wing Clip melee probe instead. nil = unknown, never tinted.
--------------------------------------------------------------------------------
local SlotOut = Engine.SlotOut
ok(type(SlotOut) == "function", "SlotOut exists")
ok(SlotOut(false, true,  nil)  == false, "ranged: API in range -> not out")
ok(SlotOut(false, false, nil)  == true,  "ranged: API out of range -> out")
ok(SlotOut(false, nil,   nil)  == nil,   "ranged: API unknown -> unknown")
ok(SlotOut(true,  true,  true) == false, "melee: in melee -> not out, whatever the API says")
ok(SlotOut(true,  true,  false) == true, "melee: API 'in range' but not in melee -> out")
ok(SlotOut(true,  nil,   nil)  == nil,   "melee: probe unknown -> unknown")
ok(SlotOut(true,  false, true) == false, "melee: the probe wins over the API both ways")

print(("range_engine: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
