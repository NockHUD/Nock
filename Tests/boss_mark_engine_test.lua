-- Tests/boss_mark_engine_test.lua
-- Standalone LuaJIT tests for the pure boss-mark engine: which detections raise
-- the banner, which suppress it, how long it holds, and how the per-encounter
-- cast gate changes the fallback's answer.
-- Run from the repo root: luajit Tests/boss_mark_engine_test.lua

local E = dofile("Modules/BossMarkEngine.lua")

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-9) end

-- The two encounters as Modules/BossMarkWatch.lua configures them. Teron's
-- fallback is ungated; Archimonde's only speaks during a cast.
local TERON = {
  castTime = 1.5, gateUnitOnCast = false,
  readyText = "FEIGN DEATH NOW", noFdText = "MARKED - NO FD",
}
local ARCHI = {
  castTime = 1.7, gateUnitOnCast = true,
  readyText = "FEIGN DEATH NOW", noFdText = "AIR BURST - NO FD",
}

--------------------------------------------------------------------------------
-- 1. Constants and config
--------------------------------------------------------------------------------
-- Shadow of Death casts in 1.5s (Wowhead, spell 40251) and Air Burst in 1.7s
-- (spell 32014). Those casts ARE the window: Feign Death has to land inside.
ok(near(E.CAST_TIME, 1.5), "the default cast time is the 1.5s Shadow of Death cast")
ok(E.HOLD >= 1.7, "the banner outlasts the longer of the two casts")

local st = E.New(ARCHI)
ok(near(st.cfg.castTime, 1.7), "a config's cast time is taken")
ok(st.cfg.gateUnitOnCast == true, "and its gate flag")
st = E.New()
ok(near(st.cfg.castTime, E.CAST_TIME) and st.cfg.gateUnitOnCast == false,
   "no config falls back to the ungated defaults rather than erroring")
st = E.New({ castTime = 9 })
ok(near(st.cfg.castTime, 9) and st.cfg.readyText == E.DEFAULT.readyText,
   "a partial config only overrides what it names")

-- gateUnitOnCast = false is a real override, not an absent one. An `a and a or
-- b` copy would quietly turn it back into the default — which for Teron happens
-- to BE false, so the bug would hide there and only surface if the default ever
-- flipped. Assert it against a default that disagrees.
local flipped = { gateUnitOnCast = not E.DEFAULT.gateUnitOnCast }
ok(E.New(flipped).cfg.gateUnitOnCast == flipped.gateUnitOnCast,
   "a boolean override survives even when it is false")

-- New() must take only the keys it knows. The watch hands it a whole encounter
-- row, live engine state and all; copying that wholesale would capture a
-- reference to the very state being replaced on every zone.
local row = { castTime = 1.7, npcId = 17968, state = { markedUntil = 999 } }
local built = E.New(row)
ok(built.cfg.npcId == nil and built.cfg.state == nil,
   "New ignores config keys it does not own")
ok(near(built.markedUntil, 0), "and a rebuilt state starts clear")

--------------------------------------------------------------------------------
-- 2. Nothing detected, nothing shown
--------------------------------------------------------------------------------
st = E.New(TERON)
ok(not E.Active(st, 100), "a fresh state shows nothing")
E.BossTarget(st, 100, false)
ok(not E.Active(st, 100), "the boss looking elsewhere shows nothing")

--------------------------------------------------------------------------------
-- 3. The certain path: the log names you
--------------------------------------------------------------------------------
for _, cfg in ipairs({ TERON, ARCHI }) do
  st = E.New(cfg)
  E.CastStart(st, 100, "me")
  ok(E.Active(st, 100), "log names you -> marked")
  ok(st.source == "log", "and the source is recorded as the log")
  ok(E.Active(st, 100 + E.HOLD - 0.01), "still up just before the hold expires")
  ok(not E.Active(st, 100 + E.HOLD), "down once the hold expires")
end

--------------------------------------------------------------------------------
-- 4. The log naming SOMEONE ELSE is authoritative
--------------------------------------------------------------------------------
-- This is the rule that keeps the fallback honest. If the log says the cast is
-- aimed at another player, the boss's unit target is not evidence about YOU —
-- ignoring it is what stops a warning on all five casts.
st = E.New(TERON)
E.CastStart(st, 100, "other")
ok(not E.Active(st, 100), "log names someone else -> nothing")
E.BossTarget(st, 100.2, true)
ok(not E.Active(st, 100.2), "and the unit fallback is suppressed for that cast")
E.BossTarget(st, 100 + TERON.castTime + 0.01, true)
ok(E.Active(st, 100 + TERON.castTime + 0.01), "suppression lifts when that cast is over")

-- An explicit cast-end lifts it immediately rather than waiting out the timer.
st = E.New(TERON)
E.CastStart(st, 100, "other")
E.CastEnded(st, 100.4)
E.BossTarget(st, 100.5, true)
ok(E.Active(st, 100.5), "a finished cast stops suppressing the fallback")

--------------------------------------------------------------------------------
-- 5. The ungated fallback (Teron): he is looking at you
--------------------------------------------------------------------------------
-- Deliberately independent of the cast event. If SPELL_CAST_START never
-- arrives, gating the fallback behind it would mean no warning at all.
st = E.New(TERON)
E.BossTarget(st, 100, true)
ok(E.Active(st, 100), "boss targeting you raises it with no cast event at all")
ok(st.source == "unit", "and the source is recorded as the unit check")

-- The log with no destination is not evidence either way; the fallback decides.
st = E.New(TERON)
E.CastStart(st, 100, "unknown")
ok(not E.Active(st, 100), "a cast with no logged target does not warn on its own")
E.BossTarget(st, 100.1, true)
ok(E.Active(st, 100.1) and st.source == "unit", "the unit check settles it")

--------------------------------------------------------------------------------
-- 6. The gated fallback (Archimonde): only during a cast
--------------------------------------------------------------------------------
-- His target is normally the tank, and fear and doomfires move it around all
-- fight. Outside an Air Burst, "he is looking at me" means nothing.
st = E.New(ARCHI)
E.BossTarget(st, 100, true)
ok(not E.Active(st, 100), "gated: the boss facing you outside a cast says nothing")

st = E.New(ARCHI)
E.CastStart(st, 100, "unknown")
E.BossTarget(st, 100.1, true)
ok(E.Active(st, 100.1) and st.source == "unit",
   "gated: inside a cast with no logged destination, the unit check decides")

-- The gate closes with the cast, both by timing out and by an explicit end.
st = E.New(ARCHI)
E.CastStart(st, 100, "unknown")
E.BossTarget(st, 100 + ARCHI.castTime + 0.01, true)
ok(not E.Active(st, 100 + ARCHI.castTime + 0.01), "gated: the window closes when the cast runs out")

st = E.New(ARCHI)
E.CastStart(st, 100, "unknown")
E.CastEnded(st, 100.5)
E.BossTarget(st, 100.6, true)
ok(not E.Active(st, 100.6), "gated: a finished cast closes the window too")

-- The gate never blocks the certain path — that is the log's own destination.
st = E.New(ARCHI)
E.CastStart(st, 100, "me")
ok(E.Active(st, 100) and st.source == "log", "gated: the log path is untouched by the gate")

-- Belt and braces: a cast the log says is someone else's must not warn, gate or
-- no gate, at any point in that cast.
st = E.New(ARCHI)
E.CastStart(st, 100, "other")
E.BossTarget(st, 100.8, true)
ok(not E.Active(st, 100.8), "gated: a cast logged for someone else still suppresses")

--------------------------------------------------------------------------------
-- 7. The two sources agreeing must not flicker or downgrade
--------------------------------------------------------------------------------
st = E.New(TERON)
E.BossTarget(st, 100, true)
E.CastStart(st, 100.1, "me")
ok(st.source == "log", "a certain detection upgrades a live inferred one")
st = E.New(TERON)
E.CastStart(st, 100, "me")
E.BossTarget(st, 100.1, true)
ok(st.source == "log", "an inferred detection never downgrades a live certain one")
ok(E.Active(st, 100.1 + E.HOLD - 0.01), "but it does extend the hold")

-- Losing the boss's target mid-hold must not yank the banner away: the whole
-- point is that it stays readable for the length of the window.
st = E.New(TERON)
E.BossTarget(st, 100, true)
E.BossTarget(st, 100.2, false)
ok(E.Active(st, 100.2), "the banner is not cancelled by him looking away again")

--------------------------------------------------------------------------------
-- 8. Re-arming on the next cast
--------------------------------------------------------------------------------
-- Shadow of Death comes round every 30-35s; a mark that expired must be able to
-- fire again rather than latching once per fight.
st = E.New(TERON)
E.CastStart(st, 100, "me")
ok(not E.Active(st, 132), "the first mark has long expired")
E.CastStart(st, 132, "me")
ok(E.Active(st, 132), "the next cast marks you again")

--------------------------------------------------------------------------------
-- 9. What the banner says
--------------------------------------------------------------------------------
-- Never tell someone to press a button that is on cooldown.
for _, cfg in ipairs({ TERON, ARCHI }) do
  st = E.New(cfg)
  local ready, notReady = E.Text(st, true), E.Text(st, false)
  ok(type(ready) == "string" and #ready > 0, "there is text for the actionable case")
  ok(type(notReady) == "string" and #notReady > 0, "and for the FD-on-cooldown case")
  ok(ready ~= notReady, "the two cases do not read the same")
  ok(ready:upper():find("FEIGN") or ready:upper():find("FD"), "the actionable text names the button")
end

-- The two encounters' cooldown copy differs, so the banner says which mechanic
-- just landed on you at the moment you can't answer it.
ok(E.Text(E.New(TERON), false) ~= E.Text(E.New(ARCHI), false),
   "the two bosses' FD-on-cooldown lines are distinguishable")

-- Called without a state at all (a caller that lost its handle) it must still
-- return usable copy rather than erroring on a nil index.
ok(type(E.Text(nil, true)) == "string" and #E.Text(nil, true) > 0,
   "Text survives being handed no state")

print(("boss_mark_engine: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
