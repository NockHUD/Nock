-- Tests/forever_swing_hold_test.lua
-- The held Auto Shot (Nock.AutoShotHoldStep) and its Forever feeds in
-- Forever/SwingTimer.lua: presses, server retries, jumps, Feign Death get-up,
-- parry haste, Quick Shots and weapon swaps.
-- Run from the repo root: luajit Tests/forever_swing_hold_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, eps) return a and b and math.abs(a - b) <= (eps or 1e-6) end

local now = 100
_G.GetTime = function() return now end
_G.GetRangedHaste = function() return 0 end
_G.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
local falling = true
_G.IsFalling = function() return falling end
local speeds = { [16] = "2.60", [17] = "1.80", [18] = "3.00" }
_G.C_TooltipInfo = { GetInventoryItem = function(_, slot)
  return { lines = { { leftText = "Bow" }, { leftText = "100 - 150 Damage", rightText = "Speed " .. speeds[slot] } } }
end }

local Nock = { Flavor = { forever = true, Plain = function(v) return v end }, Constants = { SpellID = {} } }
local module
function Nock:NewModule(name) module = { name = name, events = {} }
  function module:RegisterEvent(ev, handler) self.events[ev] = handler or ev end
  function module:UnregisterEvent(ev) self.events[ev] = nil end
  return module end
function Nock:GetModule() return module end
_G.LibStub = function() return { GetAddon = function() return Nock end } end

dofile("Core/State.lua")
dofile("Forever/Spells.lua")
dofile("Forever/SwingTimer.lua")

-- ---------------------------------------------------------------------------
-- 1. The pure step. S = 10, D = 2, W = 0.5: the line at 11.5 (p 0.75).
-- ---------------------------------------------------------------------------
do
  local H = Nock.AutoShotHoldStep
  local h = {}
  local rem, held, eta = H(h, 10, 2, 0.5, 11.0, true, nil, 0.05)
  ok(near(rem, 1.0) and not held and near(eta, 12), "before the line: plain remaining, shot at the due mark")
  rem, held, eta = H(h, 10, 2, 0.5, 11.8, true, nil, 0.05)
  ok(near(rem, 0.2) and not held and near(eta, 12), "ready at the line: the wind-up runs to the due mark")

  h = {}
  H(h, 10, 2, 0.5, 11.0, false)
  rem, held, eta = H(h, 10, 2, 0.5, 11.6, false)
  ok(near(rem, 0.5) and held and eta == nil, "not ready at the line: held at the line, no shot expected")
  rem, held = H(h, 10, 2, 0.5, 12.4, false)
  ok(near(rem, 0.5) and held, "past the due mark, still not ready: still at the line")
  rem, held, eta = H(h, 10, 2, 0.5, 12.5, true)
  ok(near(rem, 0.5) and not held and near(eta, 13.0), "ready: released, the shot one wind-up later")
  rem = H(h, 10, 2, 0.5, 12.75, true)
  ok(near(rem, 0.25), "the released fill runs over one wind-up")
  -- A move inside that wind-up: frozen where it is, never a step back.
  rem, held = H(h, 10, 2, 0.5, 12.8, false)
  ok(near(rem, 0.25) and held, "a move in the wind-up freezes the fill where it stands")
  rem, held, eta = H(h, 10, 2, 0.5, 13.0, true)
  ok(near(rem, 0.25) and not held and near(eta, 13.5), "ready again: a full wind-up from there")
  rem = H(h, 10, 2, 0.5, 13.5, true)
  ok(near(rem, 0), "...ending full")
  -- The shot: a new swing resets the step.
  rem, held = H(h, 13.6, 2, 0.5, 13.6, false)
  ok(near(rem, 2) and not held, "a new swing starts from scratch")

  -- A press that goes through releases a hold at once (TickHold counts it as
  -- ready for one wind-up, ahead of a range edge the client has not sent).
  h = {}
  H(h, 10, 2, 0.5, 11.6, false)
  rem, held, eta = H(h, 10, 2, 0.5, 12.2, true, 12.15, 0.05)
  ok(not held and near(eta, 12.7), "a press that went through releases the hold")
  -- A press before the line changes nothing.
  h = {}
  rem, held, eta = H(h, 10, 2, 0.5, 11.2, true, 11.1, 0.05)
  ok(near(rem, 0.8) and near(eta, 12), "a press before the line is ignored")
  -- A press well inside a running wind-up restarts it; one within `lead` of
  -- its start does not.
  h = {}
  H(h, 10, 2, 0.5, 11.6, true)
  rem, held, eta = H(h, 10, 2, 0.5, 11.7, true, 11.52, 0.05)
  ok(near(eta, 12), "a press inside `lead` of the wind-up start: no restart")
  rem, held, eta = H(h, 10, 2, 0.5, 11.8, true, 11.75, 0.05)
  ok(near(eta, 12.3) and near(rem, 0.2), "a later press restarts the wind-up from where the fill is")
  -- Nothing to hold without a swing.
  rem, held, eta = H({}, 0, 2, 0.5, 11, true)
  ok(rem == 0 and not held and eta == nil, "no swing: nothing")
end

-- ---------------------------------------------------------------------------
-- 2. The module's feeds.
-- ---------------------------------------------------------------------------
module:OnEnable()
local st = Nock.state
local r, c, m = st.ranged, st.context, st.melee
local function fire(ev, ...)
  local h = module.events[ev]
  if type(h) == "string" then module[h](module, ev, ...) else module[ev](module, ev, ...) end
end
local function tick(t)
  now = t
  if r.swingStart > 0 then r.swingRemaining = math.max(0, r.swingStart + r.swingDuration - now) end
  r.windup = r.windupRatio * r.swingDuration
  module:TickHold(now)
end
ok(module.events.UNIT_SPELLCAST_SENT and module.events.UNIT_SPELLCAST_FAILED_QUIET, "press and retry events registered")
ok(module._heldSpeed[18] == 3.0 and module._heldSpeed[16] == 2.6, "printed weapon speeds read from the tooltip")

st.player.inCombat = true
fire("START_AUTOREPEAT_SPELL")
fire("PLAYER_SWING", 2.0, 2)
ok(r.swingStart == 100 and near(r.swingDuration, 2.0), "a shot anchors the reload")

-- Held while moving, released by the stop.
fire("PLAYER_STARTED_MOVING")
tick(101.9)
ok(r.held == true and near(r.displayRemaining, r.windup), "moving at the line: held, the fill at the line")
now = 102.3
fire("PLAYER_STOPPED_MOVING")
tick(102.3)
ok(r.held == false and near(r.shotEta, 102.3 + r.windup), "the stop releases it: shot one wind-up later")

-- A jump in place: airborne until IsFalling says landed, then a stop.
fire("PLAYER_SWING", 2.0, 2)       -- t 102.3
module:OnJump()
ok(c.airborne == true and c.moving == false, "a jump marks the player airborne, not moving")
falling = true
tick(102.35)
ok(c.airborne == true, "inside the grace IsFalling is not trusted")
tick(103.9)
ok(r.held == true, "in the air at the line: held")
falling = false
tick(104.0)
ok(c.airborne == false and c.stoppedAt == 104.0, "landing clears the flag and counts as a stop")
ok(r.held == false and near(r.shotEta, 104.0 + r.windup), "...and releases the hold")

-- Presses: one that fails (same cast GUID) and one that goes through.
now = 104.6
fire("PLAYER_SWING", 2.0, 2)       -- t 104.6, due 106.6
fire("PLAYER_STARTED_MOVING")
tick(106.5)
ok(r.held == true, "held again (moving)")
fire("PLAYER_STOPPED_MOVING")      -- keep moving off for the press test via the flag
c.moving = true                    -- the client has not reported the stop yet
now = 106.7
fire("UNIT_SPELLCAST_SENT", "player", "target", "guid-a", 75)
fire("UNIT_SPELLCAST_FAILED_QUIET", "player", "guid-a", 75)
tick(106.85)
ok(r.pressThroughAt == nil and r.retryAt == nil, "a press that failed is neither a press-through nor a retry")
c.moving = false
module._moving = false
now = 106.9
fire("UNIT_SPELLCAST_SENT", "player", "target", "guid-b", 75)
tick(106.95)
ok(r.pressThroughAt == nil, "a fresh press is pending for PRESS_OK")
tick(107.01)
ok(near(r.pressThroughAt, 106.9), "no failure within PRESS_OK: the press went through")

-- Server retries: counted once, not at a press, undone by the switch-off.
now = 107.5
fire("PLAYER_SWING", 2.0, 2)       -- due 109.5
c.moving = true
tick(109.6)
now = 109.7
fire("UNIT_SPELLCAST_FAILED_QUIET", "player", "srv-1", 75)
fire("UNIT_SPELLCAST_FAILED_QUIET", "player", "srv-1", 75)
ok(near(r.retryAt, 109.7) and near(r.retryShotAt, 109.7 + 0.5 + r.windup), "a server retry predicts try + 0.5 + wind-up")
local n = 0
for _, w in ipairs(module:WindupSamples()) do if w.ev == "RETRY" then n = n + 1 end end
ok(n == 1, "the doubled failure is read once")
now = 110.9
c.moving = false
local predicted = r.retryShotAt
fire("PLAYER_SWING", 2.0, 2)
local last
for _, w in ipairs(module:WindupSamples()) do if w.ev == "RETRY_CHECK" then last = w end end
ok(last and near(last.err, 110.9 - predicted) and r.retryShotAt == nil, "the shot checks the retry model and clears it")
now = 111.0
fire("UNIT_SPELLCAST_FAILED_QUIET", "player", "srv-2", 75)
ok(r.retryAt == nil, "a retry that lands before the reload's end changes nothing")
now = 113.5
fire("UNIT_SPELLCAST_FAILED_QUIET", "player", "srv-3", 75)
ok(near(r.retryAt, 113.5), "a late retry counts")
fire("STOP_AUTOREPEAT_SPELL")
ok(r.retryAt == nil and r.retryShotAt == nil, "a switch-off in the same frame undoes it")
fire("START_AUTOREPEAT_SPELL")

-- Feign Death get-up restarts the reload; a cast in between does not.
now = 114
fire("PLAYER_SWING", 2.0, 2)
now = 114.5
module:OnAutoShotEdge("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 5384)
now = 115.2
fire("PLAYER_STARTED_MOVING")
ok(r.swingStart == 115.2, "moving after a feign restarts the reload")
fire("PLAYER_STOPPED_MOVING")
now = 115.5
module:OnAutoShotEdge("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 5384)
module:OnAutoShotEdge("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 3044)   -- Arcane Shot
now = 115.8
module:OnJump()
ok(r.swingStart == 115.2, "a cast after the feign: getting up restarts nothing")
c.airborne = false
now = 116.0
module:OnAutoShotEdge("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 5384)
module:OnJump()
ok(r.swingStart == 116.0, "a jump after a feign restarts the reload too")
c.airborne = false

-- Parry haste on the main hand.
now = 120
fire("PLAYER_SWING", 2.5, 0)
now = 120.2                        -- rem 2.3 > 60 %: 40 % off
module:OnPlayerCombat("player", "PARRY")
ok(near(m.swingStart, 119.0), "parry with > 60 % left: 40 % of the swing off")
now = 120.5                        -- rem 1.0 of 2.5 = 40 %: down to 20 %
module:OnPlayerCombat("player", "PARRY")
ok(near(m.swingStart + 2.5 - now, 0.5), "parry with 20-60 % left: 20 % left")
local before = m.swingStart
module:OnPlayerCombat("player", "PARRY")
ok(m.swingStart == before, "parry with <= 20 % left: nothing")
module:OnPlayerCombat("player", "DODGE")
ok(m.swingStart == before, "other results do nothing")

-- Quick Shots on a shot's frame: this reload's wind-up shortens.
now = 130
fire("PLAYER_SWING", 2.0, 2)
local plain = r.swingDuration
now = 132
module:OnPlayerAura()
fire("PLAYER_SWING", 2.0, 2)       -- aura first, then the shot
local share = module._shareServer
ok(near(r.swingDuration, 2.0 + share * 2.0 / 1.3 - share * 2.0), "a proc on the shot moves the bar's end by the wind-up's share")
ok(r.swingDuration < plain, "...sooner")
now = 134
fire("PLAYER_SWING", 1.6, 2)       -- the next reload carries the haste itself
module:OnPlayerAura()              -- a refresh while up
ok(near(r.swingDuration, 1.6), "a refresh while the buff is up shifts nothing")
-- Expiry before the wind-up of a later reload: lengthened.
now = 144.5                        -- the buff ends at 146
fire("PLAYER_SWING", 1.6, 2)
ok(near(r.swingDuration, 1.6), "expiry after this reload's wind-up began: no shift")
now = 145.0
fire("PLAYER_SWING", 1.6, 2)       -- ends at 146 < 145 + 1.6 - wind-up
ok(r.swingDuration > 1.6, "an expiry before the wind-up begins lengthens it")

-- Weapon swap: restart at the new speed times the old haste.
now = 150
fire("PLAYER_SWING", 2.4, 2)       -- 3.0 bow at 1.25x
speeds[18] = "2.70"
now = 150.5
fire("PLAYER_EQUIPMENT_CHANGED", 18, true)
ok(r.swingStart == 150.5 and near(r.swingDuration, 2.7 * 2.4 / 3.0), "ranged swap: restarted at new speed x old haste")
_G.C_TooltipInfo = nil
now = 151
fire("PLAYER_EQUIPMENT_CHANGED", 18, true)
ok(r.swingStart == 0, "no estimate: the bar goes idle")

print(("forever_swing_hold: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
