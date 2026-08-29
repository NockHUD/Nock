-- Modules/BossMarkEngine.lua
-- Pure decision engine for the boss-mark warning (no WoW APIs — testable under
-- standalone LuaJIT via Tests/boss_mark_engine_test.lua).
-- Modules/BossMarkWatch.lua owns the combat log, the unit lookup and the sound.
--
-- The shape both encounters share: a boss casts something at ONE raid member,
-- the cast is short, and a Hunter who Feign Deaths in time walks away from it.
-- So the actionable window is the cast bar, not the debuff, and the whole job
-- of this engine is to decide, fast, whether this particular cast is aimed at
-- you.
--
--   Teron Gorefiend / Shadow of Death (40251, 1.5s) — FD inside the cast makes
--     it fail outright; the debuff never lands.
--   Archimonde / Air Burst (32014, 1.7s) — FD saves you from the fall.
--
-- Two detections feed it and they are deliberately independent:
--   "log"  - the combat log named you as the cast's destination. Certain.
--   "unit" - the boss's unit target is you. Inferred, and the only signal left
--            if SPELL_CAST_START turns out not to carry a destination on this
--            client. For Teron, gating it behind the cast event would make it
--            useless in exactly the case it exists to cover.
--
-- The one rule that keeps the fallback from warning on all five casts: a log
-- that names SOMEONE ELSE is authoritative for the length of that cast, and
-- suppresses the unit check. Without it, any boss glance during someone else's
-- mark would raise the banner.
--
-- `gateUnitOnCast` is the second brake, and it is per-encounter. Archimonde's
-- target is normally the tank and he retargets constantly (fear, doomfires), so
-- "he is looking at me" only means anything while an Air Burst is in flight.
-- Teron is a stand-still tank-and-spank, so his check stays ungated — which is
-- the whole point of the fallback there.

local Engine = {}

-- How long the banner stays up from the moment of detection. Longer than either
-- cast on purpose: a detection that arrives late in the cast still needs to be
-- readable, and a banner that vanishes as you react is worse than one that
-- lingers half a second. Shared by both encounters.
Engine.HOLD = 2.5

-- Used when New() is handed no config: Teron's numbers and copy.
local DEFAULT = {
  castTime       = 1.5,
  gateUnitOnCast = false,
  readyText      = "FEIGN DEATH NOW",
  noFdText       = "MARKED - NO FD",
}
Engine.DEFAULT = DEFAULT

-- Kept as a name because the cast time is a property of the mechanic, not of a
-- config table someone forgot to pass.
Engine.CAST_TIME = DEFAULT.castTime

-- Certain beats inferred. Only used to decide whether a later detection may
-- overwrite the recorded source — never to suppress one.
local RANK = { log = 2, unit = 1 }

-- cfg fields (all optional, DEFAULT fills the gaps):
--   castTime        how long this boss's cast runs, in seconds
--   gateUnitOnCast  true = the unit check only counts while a cast is in flight
--   readyText       banner copy when Feign Death is available
--   noFdText        banner copy when it is not
-- Walks DEFAULT's keys rather than cfg's, so callers can hand in a whole
-- encounter row (which also carries its npc id, its enable key and its own live
-- engine state) without any of that ending up copied into the config — and a
-- rebuild on zoning can't capture a reference to the state it is replacing.
function Engine.New(cfg)
  local c = {}
  for k, v in pairs(DEFAULT) do
    local o = cfg and cfg[k]
    -- Explicit nil test, not `o and o or v`: gateUnitOnCast is legitimately
    -- false and the and/or idiom would silently swap it back to the default.
    if o == nil then c[k] = v else c[k] = o end
  end
  return { cfg = c, markedUntil = 0, source = nil, suppressUntil = 0, castUntil = 0 }
end

-- Raise (or extend) the latch. The hold always refreshes — two detections of
-- the same mark should not cut it short — but the recorded source only ever
-- moves upward, so a unit check landing after a log hit cannot make the mark
-- look less certain than it is.
local function latch(st, now, source)
  st.markedUntil = now + Engine.HOLD
  if not st.source or (RANK[source] or 0) >= (RANK[st.source] or 0) then
    st.source = source
  end
end

-- dest: "me" | "other" | "unknown" — what the combat log said about the cast's
-- destination. "unknown" covers both a missing destGUID and a destination we
-- could not resolve, and is treated as no evidence rather than as a negative.
--
-- `castUntil` is set whatever the destination says, including "unknown": it
-- records that a cast is IN FLIGHT, which is the window a gated unit check is
-- allowed to speak in. Setting it only for known destinations would make the
-- gate depend on the very field we cannot rely on.
function Engine.CastStart(st, now, dest)
  st.castUntil = now + st.cfg.castTime
  if dest == "me" then
    latch(st, now, "log")
    st.suppressUntil = 0
  elseif dest == "other" then
    st.suppressUntil = now + st.cfg.castTime
  end
end

-- The cast resolved (succeeded, or the debuff landed). Whatever it was aimed
-- at, it is no longer in flight, so a "not you" suppression has nothing left to
-- protect and is dropped early rather than timing out. A gated unit check closes
-- with it, for the same reason.
function Engine.CastEnded(st, now)
  st.suppressUntil = 0
  st.castUntil = 0
end

-- The boss's unit target, sampled by the caller. `false` is not a cancel: the
-- banner runs on its own hold, so a boss glancing away mid-window leaves it up.
function Engine.BossTarget(st, now, targetsMe)
  if not targetsMe then return end
  if st.cfg.gateUnitOnCast and now >= st.castUntil then return end
  if now < st.suppressUntil then return end
  latch(st, now, "unit")
end

function Engine.Active(st, now)
  return now < st.markedUntil
end

-- Banner copy. Lives here so the two cases have one definition and the test can
-- assert they differ: telling someone to Feign Death while it is on cooldown is
-- the one way this warning could actively mislead.
function Engine.Text(st, fdReady)
  local c = (st and st.cfg) or DEFAULT
  if fdReady then return c.readyText or DEFAULT.readyText end
  return c.noFdText or DEFAULT.noFdText
end

-- In-game the addon table is a global (AceAddon:NewAddon("Nock")); under dofile
-- it is absent and the return value is what the test binds. Same shape as
-- Modules/TonkEngine.lua.
local Nock = rawget(_G, "Nock")
if Nock then Nock.BossMarkEngine = Engine end
return Engine
