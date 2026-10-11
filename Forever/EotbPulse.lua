-- Forever/EotbPulse.lua
-- The Eyes of the Beast pulse timer: a beat counted from the channel start, published as state.eotbPulse for the pulse bar.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Pulse = Nock:NewModule("EotbPulse", "AceEvent-3.0")

-- A pet under Eyes of the Beast pulls nearby mobs on a fixed beat; players
-- put it at 5.5-5.6 s (the "EotB Pet Combat Pulse" WeakAura by Rubot, wago
-- f_y-jlrhK), so the period is a setting. The beat is anchored at the start
-- of the channel and restarted by a resync (right-click on the bar,
-- /nock pulse); the pull does not restart it. Own channels are plain on
-- Forever (Forever/CastBar.lua), so "under EotB" is the cast record.
Pulse.PERIOD_DEFAULT = 5.6
Pulse.PERIOD_MIN, Pulse.PERIOD_MAX = 1, 10

-- Seconds from `now` to the next pulse of the beat started at `anchor`.
function Pulse.Remaining(now, anchor, period)
  return period - ((now - anchor) % period)
end

local function period()
  local p = Nock.db and Nock.db.profile
  local v = tonumber(p and p.eotbPulsePeriod)
  if not v then return Pulse.PERIOD_DEFAULT end
  return math.max(Pulse.PERIOD_MIN, math.min(Pulse.PERIOD_MAX, v))
end

local function isEotb(c)
  if not (c and c.isChannel) then return false end
  local id = Nock.Spells.EYES_OF_THE_BEAST
  if c.spellId == id then return true end
  local n = Nock.Flavor.Plain(Nock.API.SpellName(id))
  return type(n) == "string" and c.name == n
end

-- The beat's anchor. Set at the start of the EotB channel and by a resync;
-- the pull only sets it when there is none (a channel begun before a
-- /reload). It survives the end of combat and is dropped only when the
-- channel is over out of combat.
--
-- The pull does NOT restart the pet's beat (pulse log, user, 2026-10-11:
-- clicks on seen pulses after a pull read -0.21/-0.55 s against the beat
-- kept through the pull, -0.60/-0.94 against one restarted there; the
-- channel-start anchor read -0.19 two periods in). The WeakAura's model
-- restarted it at the pull; eotbPulseResetOnPull keeps that model as an
-- option, in case the log misled. /nock pulse log records both readings.
local anchor
local wasEotb = false

-- The pulse log: channel starts, pulls, combat ends and resyncs, bounded.
Pulse.LOG_MAX = 80
local log = {}
local pullAnchor, beatBeforePull   -- the pull's anchor, and the beat it replaced

local function note(line)
  log[#log + 1] = string.format("%8.2f  %s", GetTime(), line)
  if #log > Pulse.LOG_MAX then table.remove(log, 1) end
end

function Pulse:OnEnable()
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Pulse:PLAYER_REGEN_DISABLED()
  local now = GetTime()
  if anchor then
    note(string.format("pull: the running beat had %.2f s to its next pulse", Pulse.Remaining(now, anchor, period())))
  else
    note("pull: no beat running")
  end
  beatBeforePull = anchor
  pullAnchor = now
  local p = Nock.db and Nock.db.profile
  if not anchor or (p and p.eotbPulseResetOnPull == true) then anchor = now end
end

function Pulse:PLAYER_REGEN_ENABLED()
  note("combat over")
end

-- Restart the beat from now: the pet's pulse drifted from the pull. A
-- resync is the user marking a pulse they saw, so the log records how far
-- off each hypothesis was at that moment.
function Pulse:Resync()
  local now, per = GetTime(), period()
  local function off(a)
    if not a then return "-" end
    local r = Pulse.Remaining(now, a, per)
    if r > per / 2 then r = r - per end   -- signed: + early, - late
    return string.format("%+.2f", r)
  end
  note(string.format("resync: off by %s (beat) | %s (reset at pull) | %s (kept through pull)",
    off(anchor), off(pullAnchor), off(beatBeforePull)))
  anchor = now
end

function Pulse:Command(rest)
  if rest == "log" then
    local text = "Nock EotB pulse log (period " .. string.format("%.2f", period()) .. " s)\n"
      .. "Resync lines: seconds the beat was off when you clicked. Near zero under\n"
      .. "'reset at pull' = the pull restarts the beat; under 'kept' = it keeps going.\n\n"
      .. (#log > 0 and table.concat(log, "\n") or "(empty)")
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
    return
  end
  self:Resync()
  Nock:Print("Eyes of the Beast pulse resynced.")
end

-- Derived every tick: whether the beat runs (under EotB with an anchor),
-- whether that is in combat, and the seconds to the next pulse. Published
-- whatever the display settings say; the view picks in or out of combat.
function Pulse:Refresh(state)
  local e = state.eotbPulse
  if not e then e = {}; state.eotbPulse = e end
  e.period = period()
  local pl = state.player
  local c = pl and pl.casting
  local under = pl ~= nil and isEotb(c)
  local combat = pl ~= nil and pl.inCombat == true
  if under and not wasEotb then
    note(combat and "channel start (in combat)" or "channel start")
    if not anchor then anchor = (c.startTime and c.startTime > 0) and c.startTime or GetTime() end
  elseif not under and wasEotb then
    note("channel end")
  end
  wasEotb = under
  if not under and not combat then
    anchor, pullAnchor, beatBeforePull = nil, nil, nil
  end
  e.active = under and anchor ~= nil
  e.combat = combat
  e.remaining = e.active and Pulse.Remaining(GetTime(), anchor, e.period) or nil
end
