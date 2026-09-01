-- Modules/SlammerEngine.lua
-- Pure decision engine for the Sulfuron Slammer button (no WoW APIs — testable
-- under standalone LuaJIT via Tests/slammer_engine_test.lua).
-- Modules/SlammerWatch.lua owns the combat log, the boss lookup and the horn;
-- UI/Frame_SlammerButton.lua is the secure button that drinks.
--
-- The mechanic: Anetheron (Hyjal) casts Sleep (31298, INSTANT — videos and
-- logs 2026-09-01: no cast bar, ever; 10 s, breaks on damage). The next Sleep
-- can come 20 s after the last (observed; BigWigs says 19.5-45 s apart). A
-- Sulfuron Slammer (item 38466) puts a 6 s aura on you (50986) that deals
-- fire damage to YOU every 3 s — and that tick is what wakes you. So the buff
-- has to be UP when Sleep lands, and against a window that can run 20 -> 45 s
-- that means re-drinking every ~6 s inside it. The window is the ONLY prompt
-- there is: with no cast bar, nothing more reactive exists.
--
-- States, in priority order:
--   slept    Sleep is on you. Nothing to click; the tick (or 10 s) ends it.
--   exposed  a Sleep went out while the buff was under the margin or absent —
--            a 2 s flash, and the horn (informative only — too late to act
--            on, which is why the horn ships silent).
--   castOk   a Sleep went out and you were covered — the same 2 s flash, quiet.
--   covered  the window is open and the buff is up: shows its remaining time.
--   now      the window is open and the buff is not: CLICK NOW — the real
--            prompt (the reference WA's, PTR-tested).
--   wait     a window is scheduled: WINDOW CLOSED, counting down to it.
--   idle     no fight yet: the button is a stock reminder.

local Engine = {}

Engine.DEFAULT = {
  window      = 20,    -- s after a Sleep until the next can come (observed 2026-09-01)
  firstWindow = 16,    -- s after engage until the first
  leeway      = 1,     -- the prompt opens this much BEFORE the window: an early
                       -- drink costs nothing, a late one gets you slept
  margin      = 2,     -- buff remaining at the cast under which you count as exposed
  buffDur     = 6,     -- the Slammer aura
  sleepDur    = 10,    -- Sleep, when the aura event carries no expiry
  flash       = 2,     -- how long EXPOSED / SLEEP - COVERED stays up
}

Engine.LABEL = {
  idle    = "SLAMMER",
  wait    = "WINDOW CLOSED",   -- the stand-down, counting down to the window (user, 2026-08-29)
  now     = "CLICK NOW",
  covered = "COVERED",
  slept   = "SLEPT",
  exposed = "EXPOSED",
  castOk  = "SLEEP - COVERED",
  noStock = "NO SLAMMER",
}

local function merge(into, cfg)
  if type(cfg) ~= "table" then return end
  for k, v in pairs(cfg) do
    if Engine.DEFAULT[k] ~= nil and type(v) == "number" then into[k] = v end
  end
end

function Engine.New(cfg)
  local st = {
    cfg          = {},
    windowAt     = nil,   -- GetTime() the next Sleep may come from; nil = no fight
    windowSpan   = nil,   -- the length of the wait that ends at windowAt, for the bar
    buffUntil    = nil,   -- the Slammer aura's expiry on me
    coveredUntil = nil,   -- the expiry of the buff that covered the last cast
    sleptUntil   = nil,   -- Sleep's expiry on me
    exposedUntil = nil,   -- the EXPOSED flash's end
    castOkUntil  = nil,   -- the SLEEP - COVERED flash's end
    lastCastAt   = nil,
    verdict      = nil,   -- "covered" | "exposed" from the last cast
    alert        = false, -- one-shot: the horn is owed (TakeAlert / Describe clear it)
    windowAlerted = false, -- this window's opening already chimed
    count        = 0,     -- Slammers in the bag
  }
  for k, v in pairs(Engine.DEFAULT) do st.cfg[k] = v end
  merge(st.cfg, cfg)
  return st
end

-- Live profile changes: the sliders move a knob without dropping the fight.
function Engine.Configure(st, cfg)
  merge(st.cfg, cfg)
end

-- ENCOUNTER_START, or the boss seen in combat: the first window. A second
-- engage is a new pull and restarts it.
-- The wait that ends at windowAt: the mechanic's number minus the leeway,
-- never under 0. windowAt is the PROMPT's moment, not the mechanic's.
local function waitSpan(st, mechanic)
  return math.max(0, mechanic - st.cfg.leeway)
end

function Engine.Engage(st, now)
  st.windowSpan   = waitSpan(st, st.cfg.firstWindow)
  st.windowAt     = now + st.windowSpan
  st.coveredUntil = nil
  st.sleptUntil   = nil
  st.exposedUntil = nil
  st.castOkUntil  = nil
  st.verdict      = nil
  st.alert        = false
  st.windowAlerted = false
end

-- The fight is over (kill, encounter end, zoning). The stock count is a bag
-- fact and stays.
function Engine.Reset(st)
  st.windowAt     = nil
  st.windowSpan   = nil
  st.buffUntil    = nil
  st.coveredUntil = nil
  st.sleptUntil   = nil
  st.exposedUntil = nil
  st.castOkUntil  = nil
  st.lastCastAt   = nil
  st.verdict      = nil
  st.alert        = false
  st.windowAlerted = false
end

function Engine.SetBuff(st, expiresAt)
  st.buffUntil = expiresAt
end

function Engine.SetCount(st, n)
  st.count = tonumber(n) or 0
end

-- The softer cue: true exactly once when a window OPENS (the reference WA's
-- Glass) — not again when the buff runs out inside it, and not for a window
-- that opens while you are asleep.
function Engine.TakeWindowAlert(st, now)
  if not st.windowAt or now < st.windowAt or st.windowAlerted then return false end
  st.windowAlerted = true
  if st.sleptUntil and now < st.sleptUntil then return false end
  return true
end

-- The horn, once: true exactly one time after it was owed.
function Engine.TakeAlert(st)
  local a = st.alert
  st.alert = false
  return a and true or false
end

-- A Sleep went out. The verdict is read BEFORE the aura lands (the log's
-- SPELL_CAST_SUCCESS precedes SPELL_AURA_APPLIED), so it judges the buff you
-- had at the moment of the cast, which is the only moment that matters.
function Engine.CastSucceeded(st, now)
  local rem = st.buffUntil and (st.buffUntil - now) or 0
  local verdict = (rem >= st.cfg.margin) and "covered" or "exposed"
  st.verdict      = verdict
  st.lastCastAt   = now
  st.windowSpan   = waitSpan(st, st.cfg.window)
  st.windowAt     = now + st.windowSpan
  st.windowAlerted = false
  if verdict == "exposed" then
    st.exposedUntil = now + st.cfg.flash
    st.castOkUntil  = nil
    st.coveredUntil = nil
    -- Sleep is instant: the landing IS the horn's moment. Too late to act on,
    -- which is why the horn ships silent ("None") — it is a post-mortem cue
    -- for whoever turns it on.
    st.alert = true
  else
    -- The cast is announced either way (the user asked for a "boss is
    -- casting" read); covered, it is the quiet green flash. Then the buff
    -- that covered this cast keeps the button on COVERED while it lasts —
    -- the "you were fine" read — even though the next window is already
    -- counting. A buff drunk early during a wait gets no such credit.
    st.exposedUntil = nil
    st.castOkUntil  = now + st.cfg.flash
    st.coveredUntil = st.buffUntil
  end
  return verdict
end

function Engine.Slept(st, now, expiresAt)
  st.sleptUntil = expiresAt or (now + st.cfg.sleepDur)
end

function Engine.Woke(st)
  st.sleptUntil = nil
end

function Engine.Active(st)
  return st.windowAt ~= nil
end

function Engine.State(st, now)
  if st.sleptUntil and now < st.sleptUntil then return "slept" end
  if st.exposedUntil and now < st.exposedUntil then return "exposed" end
  if st.castOkUntil and now < st.castOkUntil then return "castOk" end
  if st.coveredUntil and now < st.coveredUntil and st.buffUntil and now < st.buffUntil then
    return "covered"
  end
  if not st.windowAt then return "idle" end
  if now < st.windowAt then return "wait" end
  if st.buffUntil and now < st.buffUntil then return "covered" end
  return "now"
end

-- Fills `out` (no allocation — the tick calls this) with what the button
-- draws: state, label, the number under it (seconds, or nil), the countdown
-- to the window, the last verdict, the stock, and `alert` — true exactly once
-- after an exposed cast.
function Engine.Describe(st, now, out)
  local state = Engine.State(st, now)
  out.state     = state
  out.verdict   = st.verdict
  out.count     = st.count
  out.remaining = st.windowAt and math.max(0, st.windowAt - now) or 0
  out.alert     = st.alert
  st.alert = false
  -- Sleep is instant: no cast bar, ever.
  out.castFrac, out.castLeft = nil, nil
  -- The 20 s timer as a bar, whenever the window is closed: 0 at the Sleep,
  -- full when the window opens. The timer starts at the CAST, so it runs
  -- under slept / the flashes / covered too — the face's state never hides
  -- the clock underneath.
  if st.windowAt and now < st.windowAt and st.windowSpan and st.windowSpan > 0 then
    out.waitFrac = math.min(1, math.max(0, 1 - out.remaining / st.windowSpan))
  else
    out.waitFrac = nil
  end

  local L = Engine.LABEL
  if state == "slept" then
    out.label, out.value = L.slept, st.sleptUntil - now
  elseif state == "exposed" then
    out.label, out.value = L.exposed, nil
  elseif state == "castOk" then
    out.label, out.value = L.castOk, st.buffUntil and (st.buffUntil - now) or nil
  elseif state == "covered" then
    out.label, out.value = L.covered, st.buffUntil - now
  elseif state == "now" then
    out.label, out.value = (st.count > 0) and L.now or L.noStock, nil
  elseif state == "wait" then
    out.label, out.value = (st.count > 0) and L.wait or L.noStock, out.remaining
  else
    out.label, out.value = (st.count > 0) and L.idle or L.noStock, nil
  end
  return out
end

-- Bound onto the addon table when it exists (in-game) — under the test
-- harness it is absent and the return value is what the test binds. Same
-- shape as Modules/BossMarkEngine.lua.
local Nock = rawget(_G, "Nock")
if Nock then Nock.SlammerEngine = Engine end
return Engine
