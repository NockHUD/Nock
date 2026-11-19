-- Forever/MirrorTimers.lua
-- Breath, fatigue and Feign Death (the client's mirror timers) published as a cast-bar record, so the React cast bar can show them behind its own toggle and the game's bars can hide.

-- The client raises MIRROR_TIMER_START / PAUSE / STOP and counts the value
-- itself (GetMirrorTimerProgress, ms): the slow lane re-reads it, so a pause
-- or a refill needs no model. The producer publishes unconditionally
-- (state.player.mirrorTimer, the timer closest to empty); the view decides
-- through MirrorTimers.Source (a real cast always wins, user pick A
-- 2026-11-19) and profile.reactCastMirrorTimers (default off).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local MT = Nock:NewModule("MirrorTimers", "AceEvent-3.0")
Nock.MirrorTimers = MT

MT.refreshInterval = 0.1

-- The game's own colours (MirrorTimerColors, when the client has the table).
local COLORS = {
  BREATH     = { 0.00, 0.50, 1.00, 1 },
  EXHAUSTION = { 1.00, 0.90, 0.00, 1 },
  FEIGNDEATH = { 1.00, 0.70, 0.00, 1 },
  DEATH      = { 1.00, 0.70, 0.00, 1 },
}
local NAMES = { BREATH = "Breath", EXHAUSTION = "Fatigue", FEIGNDEATH = "Feign Death", DEATH = "Release" }
local ICONS = {
  BREATH     = "Interface\\Icons\\Spell_Shadow_DemonBreath",
  EXHAUSTION = "Interface\\Icons\\Spell_Nature_Sleep",
  FEIGNDEATH = "Interface\\Icons\\Ability_Rogue_FeignDeath",
  DEATH      = "Interface\\Icons\\Ability_Rogue_FeignDeath",
}

local colorCache = {}
local function colorOf(timer)
  local c = colorCache[timer]
  if c then return c end
  local bc = _G.MirrorTimerColors and _G.MirrorTimerColors[timer]
  if type(bc) == "table" and bc.r then c = { bc.r, bc.g, bc.b, 1 } else c = COLORS[timer] or COLORS.BREATH end
  colorCache[timer] = c
  return c
end

-- Pure: write the record for one timer. The fill is value / max (drawn as a
-- channel: fill = remaining / total); the time is what is left at the rate
-- (|scale| value-seconds per second; 0 = paused, frozen where it stands).
function MT.Record(r, timer, value, max, scale, now, label)
  local rate = math.abs(tonumber(scale) or 0)
  if rate == 0 then rate = 1 end
  value, max = (tonumber(value) or 0) / 1000, (tonumber(max) or 0) / 1000
  if max <= 0 then max = math.max(value, 1) end
  r.endTime = now + value / rate
  r.startTime = r.endTime - max / rate
  r.isChannel = true
  r.mirror = timer
  r.name = (type(label) == "string" and label ~= "") and label or NAMES[timer] or timer
  r.color = colorOf(timer)
  r.icon = ICONS[timer]
  r.spellId = nil
  return r
end

-- Pure: what the cast bar draws -- a real cast always, the timer only with
-- the toggle on and no cast running.
function MT.Source(p, cast, mirror)
  if cast then return cast end
  if p and p.reactCastMirrorTimers == true then return mirror end
  return nil
end

-- secret -> nil (Nock.Flavor.Plain); a plain value as it is
local function P(v)
  local F = Nock.Flavor
  if F and F.Plain then return F.Plain(v) end
  return v
end
local active = {}   -- [timer] = { max, scale, paused, label, rec }

local function start(timer, value, max, scale, paused, label)
  timer = P(timer)
  if type(timer) ~= "string" or timer == "" or timer == "UNKNOWN" then return end
  local a = active[timer] or { rec = {} }
  a.max, a.scale, a.paused, a.label = P(max), P(scale), (tonumber(P(paused)) or 0) > 0, P(label)
  active[timer] = a
  MT.Record(a.rec, timer, P(value), a.max, a.paused and 0 or a.scale, GetTime(), a.label)
end

-- The tick: each running timer re-read from the client, the closest to empty
-- published.
local function publish()
  local now, best = GetTime(), nil
  for timer, a in pairs(active) do
    local v = _G.GetMirrorTimerProgress and P(_G.GetMirrorTimerProgress(timer))
    if type(v) == "number" then MT.Record(a.rec, timer, v, a.max, a.paused and 0 or a.scale, now, a.label) end
    if not best or a.rec.endTime < best.endTime then best = a.rec end
  end
  Nock.state.player.mirrorTimer = best
end

function MT:OnEnable()
  self:RegisterEvent("MIRROR_TIMER_START")
  self:RegisterEvent("MIRROR_TIMER_PAUSE")
  self:RegisterEvent("MIRROR_TIMER_STOP")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyBlizzard")
  -- a timer already running (a /reload under water)
  for i = 1, (_G.MIRRORTIMER_NUMTIMERS or 3) do
    if _G.GetMirrorTimerInfo then
      local timer, value, max, scale, paused, label = _G.GetMirrorTimerInfo(i)
      if (tonumber(P(value)) or 0) > 0 then start(timer, P(_G.GetMirrorTimerProgress and _G.GetMirrorTimerProgress(P(timer))) or value, max, scale, paused, label) end
    end
  end
  publish()
  self:ApplyBlizzard()
end

function MT:MIRROR_TIMER_START(event, timer, value, max, scale, paused, label)
  start(timer, value, max, scale, paused, label)
  publish()
end

function MT:MIRROR_TIMER_PAUSE(event, timer, paused)
  local a = active[P(timer)]
  if a then a.paused = (tonumber(P(paused)) or 0) > 0 end
  publish()
end

function MT:MIRROR_TIMER_STOP(event, timer)
  active[P(timer)] = nil
  publish()
end

function MT:Refresh()
  if next(active) == nil then
    if Nock.state.player.mirrorTimer then Nock.state.player.mirrorTimer = nil end
    return
  end
  publish()
end

-- The game's own timer bars hide while Nock's cast bar shows the timers.
function MT:ApplyBlizzard()
  local p = Nock.db and Nock.db.profile or {}
  local hide = p.reactCastMirrorTimers == true and p.reactShowCastBar ~= false
  if Nock.UI.SetBlizzardMirrorTimersHidden then Nock.UI.SetBlizzardMirrorTimersHidden(hide) end
end
