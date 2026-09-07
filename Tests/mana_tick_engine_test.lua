-- Tests/mana_tick_engine_test.lua
-- Standalone LuaJIT tests for the pure mana-tick engine (five-second rule +
-- 2s regen tick, mirrored from the "Tick Mana" WeakAura, wago a3MaLWYVn).
-- Run from the repo root: luajit Tests/mana_tick_engine_test.lua

local E = dofile("Modules/ManaTickEngine.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-9) end

-- 1. Constants: the server regen tick is 2s, the five-second rule 5s, and a
--    combat-log energize/drain flag only excuses the NEXT power update for a
--    short while (the WA never expires its flags; a flag left over from a
--    potion an hour ago must not swallow a real tick).
ok(near(E.TICK, 2.0),    "TICK is 2.0")
ok(near(E.FSR, 5.0),     "FSR is 5.0")
ok(near(E.SKIP_TTL, 1.0), "SKIP_TTL is 1.0")

-- 2. First power update only seeds lastMana: nothing to show yet.
do
  local s = E.New()
  E.OnPower(s, 100, 5000, 8000, false)
  ok(E.Publish(s, 100, 5000, 8000) == nil, "first update publishes nothing")
end

-- 3. A gain (a regen tick) starts a 2s tick bar and anchors the phase.
do
  local s = E.New()
  E.OnPower(s, 100, 5000, 8000, false)
  E.OnPower(s, 102, 5050, 8000, false)
  local mode, start, expire = E.Publish(s, 102.5, 5050, 8000)
  ok(mode == "tick", "gain -> tick bar")
  ok(near(start, 102) and near(expire, 104), "tick bar runs 2s from the gain")
  ok(near(s.lastTick, 102), "gain anchors lastTick")
end

-- 4. The bar expires on its own: past expire nothing is published.
do
  local s = E.New()
  E.OnPower(s, 100, 5000, 8000, false)
  E.OnPower(s, 102, 5050, 8000, false)
  ok(E.Publish(s, 104.0, 5050, 8000) == nil, "at expire -> nothing")
  ok(E.Publish(s, 103.99, 5050, 8000) ~= nil, "just before expire -> still shown")
end

-- 5. Full mana never shows a tick indicator, whatever the bar state says.
do
  local s = E.New()
  E.OnPower(s, 100, 7900, 8000, false)
  E.OnPower(s, 102, 8000, 8000, false)   -- the gain that fills you up
  ok(E.Publish(s, 102.5, 8000, 8000) == nil, "full -> hidden")
  ok(E.Publish(s, 102.5, 7999, 8000) ~= nil, "one below full -> shown")
  ok(E.Publish(s, 102.5, 8000, 0) == nil, "max 0 (no mana pool) -> hidden")
end

-- 6. Out of combat a spend starts the five-second-rule bar, ending at the
--    FIRST regen tick at or after 5s (the WA's alignment): with the phase
--    known it is 5..7s, unknown it is a flat 5s.
do
  local s = E.New()
  E.OnPower(s, 100, 5000, 8000, false)
  E.OnPower(s, 101, 4800, 8000, false)   -- spend, phase unknown
  local mode, start, expire = E.Publish(s, 101.5, 4800, 8000)
  ok(mode == "fsr", "ooc spend -> fsr bar")
  ok(near(start, 101) and near(expire, 106), "unknown phase -> flat 5s")
end
do
  -- ticks at 100, 102, 104 ... ; spend at 101.5 (phase 1.5): 5s later is 106.5,
  -- the first tick at/after it is 108 -> 6.5s.
  local s = E.New()
  E.OnPower(s, 98,  5000, 8000, false)
  E.OnPower(s, 100, 5050, 8000, false)   -- tick anchor
  E.OnPower(s, 101.5, 4800, 8000, false)
  local mode, start, expire = E.Publish(s, 102, 4800, 8000)
  ok(mode == "fsr" and near(expire, 108), "phase 1.5 -> ends on the tick at 108")
end
do
  -- spend at 100.5 (phase 0.5): 5s later is 105.5, first tick at/after = 106.
  local s = E.New()
  E.OnPower(s, 98,  5000, 8000, false)
  E.OnPower(s, 100, 5050, 8000, false)
  E.OnPower(s, 100.5, 4800, 8000, false)
  local _, _, expire = E.Publish(s, 101, 4800, 8000)
  ok(near(expire, 106), "phase 0.5 -> ends on the tick at 106")
end
do
  -- spend exactly on a tick (phase 0): 5s later is 105, first tick at/after = 106.
  local s = E.New()
  E.OnPower(s, 98,  5000, 8000, false)
  E.OnPower(s, 100, 5050, 8000, false)
  E.OnPower(s, 100, 4800, 8000, false)
  local _, _, expire = E.Publish(s, 101, 4800, 8000)
  ok(near(expire, 106), "phase 0 -> ends on the tick at 106")
end

-- 7. Inside the FSR window (ooc) mp5 ticks do NOT restart the bar, but they
--    still re-anchor the phase. Once the window is over the next gain shows a
--    2s tick bar again.
do
  local s = E.New()
  E.OnPower(s, 98,  5000, 8000, false)
  E.OnPower(s, 100, 5050, 8000, false)
  E.OnPower(s, 100.5, 4800, 8000, false)   -- fsr until 106
  E.OnPower(s, 102, 4810, 8000, false)     -- mp5 tick inside the window
  local mode, _, expire = E.Publish(s, 102.5, 4810, 8000)
  ok(mode == "fsr" and near(expire, 106), "mp5 tick inside FSR keeps the fsr bar")
  ok(near(s.lastTick, 102), "...but re-anchors the phase")
  E.OnPower(s, 106, 4900, 8000, false)     -- the tick that ends the window
  mode, _, expire = E.Publish(s, 106.5, 4900, 8000)
  ok(mode == "tick" and near(expire, 108), "the ending tick starts a 2s tick bar")
end

-- 8. In combat the five-second rule is ignored: a spend only seeds the bar to
--    the next tick when no bar is live, and gains always show 2s tick bars.
do
  local s = E.New()
  E.OnPower(s, 98,  5000, 8000, true)
  E.OnPower(s, 100, 5050, 8000, true)      -- tick at 100
  E.OnPower(s, 100.5, 4800, 8000, true)    -- spend while a bar is live
  local mode, start, expire = E.Publish(s, 101, 4800, 8000)
  ok(mode == "tick" and near(start, 100) and near(expire, 102), "combat spend during a live bar leaves it alone")
  E.OnPower(s, 103, 4700, 8000, true)      -- spend after the bar expired, phase 1.0
  mode, start, expire = E.Publish(s, 103.2, 4700, 8000)
  ok(mode == "tick" and near(start, 103) and near(expire, 104), "combat spend with no live bar seeds to the next tick")
  E.OnPower(s, 104, 4750, 8000, true)
  mode, start, expire = E.Publish(s, 104.5, 4750, 8000)
  ok(mode == "tick" and near(expire, 106), "combat gain -> 2s tick bar")
end
do
  -- combat spend from full with no phase known: flat 2s
  local s = E.New()
  E.OnPower(s, 100, 8000, 8000, true)
  E.OnPower(s, 101, 7800, 8000, true)
  local mode, start, expire = E.Publish(s, 101.5, 7800, 8000)
  ok(mode == "tick" and near(start, 101) and near(expire, 103), "no phase -> flat 2s seed")
end
do
  -- an FSR window left over from before the pull must not silence combat ticks
  local s = E.New()
  E.OnPower(s, 98,  5000, 8000, false)
  E.OnPower(s, 100, 5050, 8000, false)
  E.OnPower(s, 100.5, 4800, 8000, false)   -- ooc fsr until 106
  E.OnPower(s, 102, 4810, 8000, true)      -- pulled; a tick lands
  local mode, _, expire = E.Publish(s, 102.5, 4810, 8000)
  ok(mode == "tick" and near(expire, 104), "stale ooc FSR does not hide combat ticks")
end

-- 9. A gain announced by a self ENERGIZE combat-log event (potion, Judgement
--    of Wisdom, Mana Spring, drink) is not a regen tick: no bar, no re-anchor.
do
  local s = E.New()
  E.OnPower(s, 98,  5000, 8000, true)
  E.OnPower(s, 100, 5050, 8000, true)      -- real tick, anchors 100
  E.OnEnergize(s, 100.7)
  E.OnPower(s, 100.7, 6050, 8000, true)    -- the potion lands
  local mode, _, expire = E.Publish(s, 101, 6050, 8000)
  ok(mode == "tick" and near(expire, 102), "energize gain leaves the live bar alone")
  ok(near(s.lastTick, 100), "energize gain does not re-anchor")
  E.OnPower(s, 102, 6100, 8000, true)      -- the real tick after it
  mode, _, expire = E.Publish(s, 102.5, 6100, 8000)
  ok(mode == "tick" and near(expire, 104), "the flag is consumed: the next real gain shows")
end

-- 10. A loss announced by a self DRAIN/LEECH event is not a spend: no FSR.
do
  local s = E.New()
  E.OnPower(s, 100, 5000, 8000, false)
  E.OnDrain(s, 101)
  E.OnPower(s, 101, 4800, 8000, false)
  ok(E.Publish(s, 101.5, 4800, 8000) == nil, "drained mana is not a spend")
  E.OnPower(s, 103, 4700, 8000, false)
  ok(E.Publish(s, 103.5, 4700, 8000) == "fsr", "the flag is consumed: the next loss is a spend")
end

-- 11. A skip flag goes stale after SKIP_TTL. A potion from an hour ago must
--     not swallow today's first tick.
do
  local s = E.New()
  E.OnPower(s, 100, 5000, 8000, true)
  E.OnEnergize(s, 100)
  E.OnPower(s, 105, 5050, 8000, true)      -- 5s later: a real tick
  ok(E.Publish(s, 105.5, 5050, 8000) == "tick", "stale energize flag is ignored")
  ok(near(s.lastTick, 105), "...and the tick anchors")
end

-- 12. Progress and spark placement. The direction is the caller's (each HUD
--     has its own combat / out-of-combat setting): "ltr" travels left to
--     right and lands on the right edge at the tick, "rtl" the reverse.
--     Anything else reads as "ltr".
ok(near(E.Progress(100, 102, 100), 0),   "progress at start = 0")
ok(near(E.Progress(100, 102, 101), 0.5), "progress halfway = 0.5")
ok(near(E.Progress(100, 102, 103), 1),   "progress clamps at 1")
ok(near(E.Progress(100, 102, 99), 0),    "progress clamps at 0")
ok(near(E.Progress(100, 100, 100), 1),   "zero-length bar counts as done")
ok(near(E.SparkX(0,   "ltr", 200), 0),   "ltr: starts at the left edge")
ok(near(E.SparkX(0.5, "ltr", 200), 100), "ltr: halfway is the middle")
ok(near(E.SparkX(1,   "ltr", 200), 200), "ltr: lands on the right edge")
ok(near(E.SparkX(0,   "rtl", 200), 200), "rtl: starts at the right edge")
ok(near(E.SparkX(1,   "rtl", 200), 0),   "rtl: lands on the left edge")
ok(near(E.SparkX(0.5, nil,   200), 100), "unknown direction reads as ltr")
-- The stock directions: left to right in combat, right to left out of it
-- (user, 2026-09-07, after flipping the first cut).
ok(E.DIR_COMBAT == "ltr" and E.DIR_OOC == "rtl", "stock directions: combat ltr, ooc rtl")

-- 13. Live: the central tick's gate over the raw published fields (full or
--     expired -> not live). Same rule Publish applies, exposed for Core.
ok(E.Live("tick", 100, 102, 101, 4000, 8000) == true,  "live mid-bar below full")
ok(E.Live("tick", 100, 102, 102, 4000, 8000) == false, "not live at expire")
ok(E.Live("tick", 100, 102, 101, 8000, 8000) == false, "not live at full")
ok(E.Live("tick", 100, 102, 101, 4000, 0)    == false, "not live with no mana pool")
ok(E.Live(nil,    100, 102, 101, 4000, 8000) == false, "not live without a mode")

print(("mana_tick_engine_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
