-- Modules/ManaTickEngine.lua
-- Pure mana-tick engine (no WoW APIs; LuaJIT-tested in
-- Tests/mana_tick_engine_test.lua). Modules/ManaTick.lua feeds it power
-- updates and combat-log energize/drain flags; the views read what Publish
-- returns. Logic mirrored from the "Tick Mana" WeakAura (wago a3MaLWYVn):
--
--   * a mana GAIN is a regen tick: anchor the 2s phase, show a 2s tick bar;
--   * a mana LOSS out of combat is a spend: show the five-second-rule bar,
--     ending at the first regen tick at or after 5s (so 5..7s once the
--     phase is known, a flat 5s before);
--   * in combat the five-second rule is ignored (a casting hunter never
--     leaves it): a spend only seeds a bar to the next tick when none is
--     live, and every gain shows a tick bar;
--   * a gain/loss the combat log attributes to a self ENERGIZE / DRAIN event
--     (potion, Judgement of Wisdom, Mana Spring, drink, mana burn) is neither
--     a tick nor a spend and is skipped -- the flag lives SKIP_TTL, unlike
--     the WA's, so a potion from an hour ago cannot swallow a real tick;
--   * full mana publishes nothing at all.

local Engine = {}

Engine.TICK     = 2.0   -- s, the server's regen tick period
Engine.FSR      = 5.0   -- s, the five-second rule
Engine.SKIP_TTL = 1.0   -- s a combat-log energize/drain flag excuses a power update

-- Stock spark directions ("ltr" | "rtl"); each HUD stores its own pair
-- (<hud>ManaTickDirCombat / <hud>ManaTickDirOoc). Left-to-right in combat,
-- right-to-left out of it -- the user's call after flipping the first cut.
Engine.DIR_COMBAT = "ltr"
Engine.DIR_OOC    = "rtl"

function Engine.New()
  return {
    lastMana    = nil,
    lastTick    = nil,   -- time of the last observed regen tick (phase anchor)
    fsrEnd      = nil,   -- end of the current five-second-rule window (ooc)
    mode        = nil,   -- "tick" | "fsr" while a bar is live
    start       = 0,
    expire      = 0,
    skipGainAt  = nil,   -- OnEnergize stamp; the next gain is not a tick
    skipDrainAt = nil,   -- OnDrain stamp; the next loss is not a spend
  }
end

local function flagLive(at, now)
  return at ~= nil and (now - at) <= Engine.SKIP_TTL
end

-- Seconds until the next regen tick, given the phase anchor (2s when unknown).
local function toNextTick(s, now)
  if not s.lastTick then return Engine.TICK end
  local d = Engine.TICK - ((now - s.lastTick) % Engine.TICK)
  return d
end

local function setBar(s, mode, now, dur)
  s.mode, s.start, s.expire = mode, now, now + dur
end

function Engine.OnEnergize(s, now) s.skipGainAt = now end
function Engine.OnDrain(s, now)    s.skipDrainAt = now end

-- One UNIT_POWER_UPDATE for the player's mana.
function Engine.OnPower(s, now, cur, max, inCombat)
  local last = s.lastMana
  s.lastMana = cur
  if last == nil then return end

  if cur < last then
    if flagLive(s.skipDrainAt, now) then
      s.skipDrainAt = nil
      return
    end
    s.skipDrainAt = nil
    if inCombat then
      if not s.mode or now >= s.expire then
        setBar(s, "tick", now, toNextTick(s, now))
      end
    else
      local dur = Engine.FSR
      if s.lastTick then
        -- The window ends on the FIRST regen tick at or after now + FSR.
        -- Ticks land at now + n + 2k (n = time to the next one, in (0, 2]);
        -- the smallest k with n + 2k >= 5 is 2 when n >= 1, else 3. This is
        -- the WA's "6 - phase, +2 when that lands short of the rule".
        local n = toNextTick(s, now)
        dur = n + ((n >= 1) and 2 or 3) * Engine.TICK
      end
      s.fsrEnd = now + dur
      setBar(s, "fsr", now, dur)
    end
  elseif cur > last then
    if flagLive(s.skipGainAt, now) then
      s.skipGainAt = nil
      return
    end
    s.skipGainAt = nil
    s.lastTick = now
    local inFsr = (not inCombat) and s.fsrEnd and now < s.fsrEnd - 0.1
    if not inFsr then
      setBar(s, "tick", now, Engine.TICK)
    end
  end
end

-- Is a published bar live right now? Not at full mana (nothing to tick
-- toward), not without a mana pool, not once it has expired. The central
-- tick asks this every frame over the raw fields the module publishes.
function Engine.Live(mode, start, expire, now, cur, max)
  if not mode then return false end
  if not max or max <= 0 then return false end
  if cur >= max then return false end
  return now < expire
end

-- What to draw right now: mode, start, expire -- or nil when full / expired.
function Engine.Publish(s, now, cur, max)
  if not Engine.Live(s.mode, s.start, s.expire, now, cur, max) then return nil end
  return s.mode, s.start, s.expire
end

function Engine.Progress(start, expire, now)
  local len = expire - start
  if len <= 0 then return 1 end
  local p = (now - start) / len
  if p < 0 then return 0 elseif p > 1 then return 1 end
  return p
end

-- Spark x from the bar's left edge for a direction: "ltr" travels left to
-- right and lands on the right edge at the tick, "rtl" the reverse. Anything
-- else reads as "ltr".
function Engine.SparkX(progress, dir, width)
  if dir == "rtl" then return (1 - progress) * width end
  return progress * width
end

-- In-game the addon table is a global (AceAddon:NewAddon("Nock")); under dofile
-- it is absent and the return value is what the test binds. Same shape as
-- Modules/TonkEngine.lua.
local Nock = rawget(_G, "Nock")
if Nock then Nock.ManaTickEngine = Engine end
return Engine
