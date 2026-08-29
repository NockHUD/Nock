-- Modules/TonkEngine.lua
-- Pure decision engine for the Steam Tonk guard (no WoW APIs — testable under
-- standalone LuaJIT via Tests/tonk_engine_test.lua). Modules/TonkGuard.lua owns
-- the events, timers and the actual cancel call; everything decided here is a
-- function of numbers.
--
-- The one invariant worth stating out loud: every ambiguous case errs LATE.
-- Cancelling the transform too early is exactly the bug this feature exists to
-- prevent, and waiting an extra fraction of a second costs nothing.

local Engine = {}

Engine.SWEEP_INTERVAL = 0.1   -- s between looks once we have fired
Engine.GIVE_UP_AFTER  = 4.0   -- s from the FIRST attempt before we stop and say so

-- Grace before a SECOND cancel is permitted, measured from the last attempt.
--
-- This is the whole lesson of 2026-08-12. A cancel the server has accepted does
-- not remove the aura instantly — traced in-game, cancel #1 landed at +0.400s
-- and the aura did not leave until +0.576s. The old 0.1s sweep fired cancel #2
-- at +0.501s, straight into that exit transition, and welded the player: the
-- same class of double-action as the /cancelaura macro this feature replaces.
--
-- The reference WeakAura avoids it by never retrying at all (aura_env.cancelled
-- latches after one attempt). That is safe but leaves a genuinely no-op cancel
-- with no recourse, so instead we retry LATE: 1.0s is ~5.7x the measured exit
-- transition, far outside any plausible in-flight window, while still giving
-- three attempts before the give-up cap.
Engine.RETRY_AFTER    = 1.0

-- Seconds to wait before the FIRST cancel attempt.
-- `since` is when the server applied the aura; a missing one means we do not
-- know, so we wait a full delay from now rather than guessing earlier.
-- Clamped at zero: re-arming after a /reload mid-transform has an anchor well
-- in the past and must fire immediately.
function Engine.WaitFor(since, now, delay)
  if not since then return delay end
  local w = delay - (now - since)
  if w < 0 then return 0 end
  return w
end

-- What should the guard do at this instant?
--   active  - is the tonk aura currently on the player
--   since   - GetTime() the aura was applied, or nil if unknown
--   now     - GetTime()
--   delay   - configured settling delay in seconds
--   fired     - has a cancel already been attempted for this transform
--   firedAt   - GetTime() of the FIRST attempt, or nil (drives the give-up cap)
--   lastTryAt - GetTime() of the most recent attempt, or nil (drives the retry
--               cadence; falls back to firedAt)
-- Returns "disarm" | "wait" | "fire" | "retry" | "giveup".
function Engine.Step(active, since, now, delay, fired, firedAt, lastTryAt)
  if not active then return "disarm" end
  if not fired then
    if not since then return "wait" end
    if (now - since) >= delay then return "fire" end
    return "wait"
  end
  -- Give up outranks a retry that is also due: at the cap we stop, full stop.
  if firedAt and (now - firedAt) >= Engine.GIVE_UP_AFTER then return "giveup" end
  -- No stamp at all means we cannot tell how long ago we tried. Wait: an
  -- unprompted second cancel is the dangerous direction, never the safe one.
  local last = lastTryAt or firedAt
  if not last then return "wait" end
  if (now - last) >= Engine.RETRY_AFTER then return "retry" end
  return "wait"
end

-- In-game the addon table is a global (AceAddon:NewAddon("Nock")); under dofile
-- it is absent and the return value is what the test binds. Same shape as
-- Modules/RangeEngine.lua.
local Nock = rawget(_G, "Nock")
if Nock then Nock.TonkEngine = Engine end
return Engine
