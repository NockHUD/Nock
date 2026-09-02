-- Tests/react_melee_cue_test.lua
-- Standalone LuaJIT tests for the React melee bar's weave-stage cue helpers
-- (UI/Widgets.lua): ReactStageLook (stage -> takeover look), MarchOffset (the
-- chevron run's per-tick slide) and FlashMix (the RELEASE flash decay).
-- Run from the repo root: luajit Tests/react_melee_cue_test.lua
--
-- Harness note: see Tests/react_countdown_test.lua -- UI/Widgets.lua's only
-- load-time work needs a LibStub lookup and one inert CreateFrame.

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

local Nock = {
  db = { profile = {} },
  Constants = setmetatable({}, {
    __index = function(t, k) local v = {}; rawset(t, k, v); return v end,
  }),
}
local libs = { ["AceAddon-3.0"] = { GetAddon = function() return Nock end } }
_G.LibStub = setmetatable({}, {
  __call = function(_, name, silent)
    local lib = libs[name]
    if not lib and not silent then error("harness: missing lib " .. name) end
    return lib
  end,
})
_G.CreateFrame = function()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end

dofile("UI/Widgets.lua")

--------------------------------------------------------------------------------
-- ReactStageLook: one look per coach stage (Modules/WeaveCoach.lua semantics).
--   text   the takeover word
--   fill   the bar colour {r,g,b,a}
--   march  1 = chevrons run toward the centre (step in), -1 = outward (back
--          out), 0 = still
--   flash  true = one bright flash on entry (RELEASE)
-- nil / unknown stage -> nil: the bar keeps its normal READY look.
--------------------------------------------------------------------------------
local Look = Nock.UI.ReactStageLook
ok(type(Look) == "function", "Nock.UI.ReactStageLook exists")
ok(Look(nil) == nil, "nil stage -> nil (normal bar)")
ok(Look("BOGUS") == nil, "unknown stage -> nil")

local go = Look("GO")
ok(go and go.text == "GO IN" and go.march == 1 and not go.flash, "GO: 'GO IN', marches inward, no flash")
local hold = Look("HOLD")
ok(hold and hold.text == "HOLD" and hold.march == 0, "HOLD: 'HOLD', still")
local struck = Look("STRUCK")
ok(struck and struck.text == "BACK OUT" and struck.march == -1, "STRUCK: 'BACK OUT', marches outward")
local rel = Look("RELEASE")
ok(rel and rel.text == "RELEASE" and rel.march == 0 and rel.flash == true, "RELEASE: 'RELEASE', still, flashes")

for _, s in ipairs({ "GO", "HOLD", "STRUCK", "RELEASE" }) do
  local l = Look(s)
  ok(type(l.fill) == "table" and #l.fill == 4, s .. ": fill is an {r,g,b,a} colour")
end
ok(go.fill ~= hold.fill and hold.fill ~= struck.fill, "each stage has its own fill colour")
ok(Look("GO") == go, "looks are shared tables, not allocated per call")

--------------------------------------------------------------------------------
-- MarchOffset(now, pitch, dir, period): the x offset (LEFT anchor) of a glyph
-- run that repeats every `pitch` units, sliding one pitch per `period` seconds.
-- dir = 1 slides right: the offset climbs from -pitch toward 0, then wraps --
-- seamless because the run is periodic. dir = -1 slides left: 0 -> -pitch.
-- The offset never leaves [-pitch, 0], so a run built two pitches longer than
-- its clip frame always covers it.
--------------------------------------------------------------------------------
local March = Nock.UI.MarchOffset
ok(type(March) == "function", "Nock.UI.MarchOffset exists")

ok(near(March(0, 10, 1, 1), -10), "rightward, phase 0: parked one pitch left")
ok(near(March(0.5, 10, 1, 1), -5), "rightward, half period: half a pitch left")
ok(near(March(0.999, 10, 1, 1), -0.01), "rightward, end of period: nearly home")
ok(near(March(1, 10, 1, 1), -10), "rightward wraps after one period")
ok(near(March(0.25, 10, -1, 1), -2.5), "leftward, quarter period: a quarter pitch left")
ok(near(March(0.75, 8, -1, 1), -6), "leftward, three quarters: three quarters of the pitch")

local a, b = March(0.3, 10, 1, 0.7), March(1.0, 10, 1, 0.7)
ok(near(a, b), "the period is the repeat: t and t+period agree")

for _, t in ipairs({ 0, 0.1, 0.33, 0.5, 0.69, 0.7, 12.34, 1000.01 }) do
  local o = March(t, 9, 1, 0.7)
  ok(o >= -9 and o <= 0, ("rightward offset stays within [-pitch, 0] at t=%g"):format(t))
  o = March(t, 9, -1, 0.7)
  ok(o >= -9 and o <= 0, ("leftward offset stays within [-pitch, 0] at t=%g"):format(t))
end

ok(near(March(0.5, 0, 1, 1), 0), "zero pitch -> 0 (nothing to march)")
ok(near(March(0.5, nil, 1, 1), 0), "nil pitch -> 0")
ok(near(March(0.5, 10, 1, 0), 0), "zero period -> 0 (no divide by zero)")
ok(near(March(0.5, 10, 0, 1), 0), "dir 0 -> 0 (still)")
ok(near(March(0.5, 10, 1), March(0.5, 10, 1, 0.7)), "default period is 0.7 s")

--------------------------------------------------------------------------------
-- FlashMix(elapsed, duration): 1 at the moment of entry, decaying linearly to
-- 0 at `duration`, clamped -- the fill is lerped toward white by this much.
--------------------------------------------------------------------------------
local Flash = Nock.UI.FlashMix
ok(type(Flash) == "function", "Nock.UI.FlashMix exists")
ok(near(Flash(0, 0.4), 1), "entry: full flash")
ok(near(Flash(0.2, 0.4), 0.5), "halfway: half")
ok(near(Flash(0.4, 0.4), 0), "at the duration: gone")
ok(near(Flash(5, 0.4), 0), "long after: stays 0")
ok(near(Flash(-1, 0.4), 1), "before entry (clock skew): clamped to 1")
ok(near(Flash(0.1, 0), 0), "zero duration: no flash, no divide")

--------------------------------------------------------------------------------
-- PreviewStage(now, period): the settings preview's cycle, one stage per
-- period in coach order GO -> HOLD -> STRUCK -> RELEASE, then round again.
-- CoachStage(state, now): the real stage, or the cycle while the preview is
-- ticked and the player is out of combat.
--------------------------------------------------------------------------------
local Prev = Nock.UI.PreviewStage
ok(type(Prev) == "function", "Nock.UI.PreviewStage exists")
ok(Prev(0, 1.5) == "GO" and Prev(1.49, 1.5) == "GO", "first period: GO")
ok(Prev(1.5, 1.5) == "HOLD", "second: HOLD")
ok(Prev(3.0, 1.5) == "STRUCK", "third: STRUCK")
ok(Prev(4.5, 1.5) == "RELEASE", "fourth: RELEASE")
ok(Prev(6.0, 1.5) == "GO", "then round again")
ok(Prev(1234567.2, 1.5) ~= nil, "any clock value yields a stage")
ok(Prev(2.0) == "HOLD", "default period is 1.5 s")
ok(Prev(5, 0) == "GO", "zero period: GO, no divide")

local Coach = Nock.UI.CoachStage
ok(type(Coach) == "function", "Nock.UI.CoachStage exists")
local st = { weave = { stage = "HOLD" } }
Nock.UI.stagePreview = nil
ok(Coach(st, 0) == "HOLD", "preview off: the coach's stage")
ok(Coach({}, 0) == nil and Coach(nil, 0) == nil, "preview off, no weave state: nil")
Nock.UI.stagePreview = true
_G.InCombatLockdown = function() return false end
ok(Coach(st, 0) == "GO" and Coach(st, 1.5) == "HOLD", "preview on, out of combat: the cycle wins")
_G.InCombatLockdown = function() return true end
ok(Coach(st, 0) == "HOLD", "preview on, in combat: the coach's stage (never a live fight)")
Nock.UI.stagePreview = nil
_G.InCombatLockdown = nil

print(("react_melee_cue: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
