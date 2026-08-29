-- Tests/clip_threshold_test.lua
-- Standalone LuaJIT tests for the shared clip math in Core/State.lua:
-- Nock.RangedCastTime and Nock.ClipThreshold. Both are pure given state + the
-- GetRangedHaste global, so they can be exercised outside WoW.
-- Run from the repo root: luajit Tests/clip_threshold_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-6) end

-- Minimal WoW/Ace surface: State.lua only needs the addon table and the haste
-- global. LibStub is stubbed so `GetAddon("Nock")` hands back our fake.
local Nock = {}
local hasteReturn = 0
_G.GetRangedHaste = function() return hasteReturn end
_G.LibStub = function() return { GetAddon = function() return Nock end } end

dofile("Core/State.lua")

local st = Nock.state
Nock.db = { profile = {} }

local function reset(haste, windup, corr, latencyMs)
  hasteReturn = haste
  st.ranged.windup = windup
  st.ranged.castHasteCorr = corr
  st.network.latencyMs = latencyMs
end

-- Constants are normally supplied by Core/Constants.lua; State only needs the
-- one reference value.
Nock.Constants = { AUTO_SHOT_CAST = 0.5 }

-- 1. Cast time scales off the measured wind-up, not a haste formula. A wind-up
--    equal to the 0.5s reference means zero haste => the base cast, untouched.
reset(0, 0.5, 1.0, 0)
ok(near(Nock.RangedCastTime(1.5), 1.5), "RangedCastTime: base at the 0.5s reference")
ok(near(Nock.RangedCastTime(0.5), 0.5), "RangedCastTime: Multi base")

-- 2. The dummy case: eWS 2.174, wind-up 0.362 => Steady 1.087, which is what the
--    server actually reports (1.09). Note this equals 1.5/(1.20*1.15), i.e. the
--    quiver DOES shorten a ranged cast — deriving from the wind-up gets there
--    without having to assume either a quiver factor or GetRangedHaste.
reset(20, 0.362, 1.0, 0)
ok(near(Nock.RangedCastTime(1.5), 1.086, 1e-3), "RangedCastTime: matches the measured 1.09s")
ok(near(Nock.RangedCastTime(1.5), 1.5 / (1.2 * 1.15), 1e-3),
   "RangedCastTime: agrees with the full (haste x quiver) multiplier")

-- 3. Haste-independent by construction: halve the wind-up, halve the cast.
reset(0, 0.181, 1.0, 0)
ok(near(Nock.RangedCastTime(1.5), 0.543, 1e-3), "RangedCastTime: tracks the wind-up")

-- 4. The measured residual scales the result.
reset(20, 0.362, 0.9, 0)
ok(near(Nock.RangedCastTime(1.5), 1.086 * 0.9, 1e-3), "RangedCastTime: correction applied")

-- 5. A zero/absent correction must not zero the cast time.
reset(20, 0.362, 0, 0)
ok(near(Nock.RangedCastTime(1.5), 1.086, 1e-3), "RangedCastTime: corr<=0 treated as 1")
st.ranged.castHasteCorr = nil
ok(near(Nock.RangedCastTime(1.5), 1.086, 1e-3), "RangedCastTime: nil corr treated as 1")

-- 6. No wind-up yet (pre-first-shot) falls back to the haste formula.
reset(20, 0, 1.0, 0)
ok(near(Nock.RangedCastTime(1.5), 1.25), "RangedCastTime: cold-start fallback")

-- Cast time as the shared helper derives it, for readability below.
local function castOf(base, windup) return base * windup / 0.5 end

-- 7. ClipThreshold sums cast + windup + latency, and nothing else. The wind-up
--    term is the whole fix: it used to be missing entirely.
reset(0, 0.37, 1.0, 0)
ok(near(Nock.ClipThreshold(1.5), castOf(1.5, 0.37) + 0.37), "ClipThreshold: cast + windup")
ok(Nock.ClipThreshold(1.5) > castOf(1.5, 0.37),
   "ClipThreshold: stricter than the old cast-only rule")

reset(0, 0.37, 1.0, 150)
ok(near(Nock.ClipThreshold(1.5), castOf(1.5, 0.37) + 0.37 + 0.15), "ClipThreshold: + latency")

-- The retired safety margin (1.0.19). A value left behind in an old
-- SavedVariables profile must not reach the math: there is no tunable to read
-- any more, and every non-zero value it could hold moved the tick off the
-- measured truth.
Nock.db.profile.clipSafetyMargin = 0.3
ok(near(Nock.ClipThreshold(1.5), castOf(1.5, 0.37) + 0.37 + 0.15),
   "ClipThreshold: a stale clipSafetyMargin is ignored")
Nock.db.profile.clipSafetyMargin = nil

-- 8. Missing wind-up degrades to the cold-start path rather than erroring.
reset(0, nil, 1.0, 0)
ok(near(Nock.ClipThreshold(1.5), 1.5), "ClipThreshold: nil windup treated as 0")

-- 9. Haste shrinks both terms, so the threshold tightens with haste. Numbers
--    from the dummy runs: eWS 2.174 -> windup 0.37; eWS 1.350 -> windup 0.23.
reset(20, 0.37, 1.0, 0)
local slow = Nock.ClipThreshold(1.5)
reset(68, 0.23, 1.0, 0)
local fast = Nock.ClipThreshold(1.5)
ok(fast < slow, "ClipThreshold: shrinks under haste")
ok(near(slow, castOf(1.5, 0.37) + 0.37), "ClipThreshold: unbuffed dummy figures")
ok(near(fast, castOf(1.5, 0.23) + 0.23), "ClipThreshold: Rapid Fire dummy figures")

-- 10. Multi is haste-adjusted too. Rotation used to pass a flat 0.5 straight
--     into the clip check with no haste applied at all.
reset(20, 0.37, 1.0, 0)
ok(near(Nock.ClipThreshold(0.5), castOf(0.5, 0.37) + 0.37), "ClipThreshold: Multi haste-adjusted")
ok(Nock.ClipThreshold(0.5) < Nock.ClipThreshold(1.5), "ClipThreshold: Multi is looser than Steady")

-- 11. The clip band. Above the upper edge a cast completes in time; below the
--     lower edge the press queues and costs nothing; only between them does the
--     cast end up in flight across the wind-up.
reset(20, 0.36, 1.0, 0)
local upper = Nock.ClipThreshold(1.5)
local lower = Nock.ClipQueueEdge()
ok(near(lower, 0.36), "ClipQueueEdge: is the wind-up")
ok(lower < upper, "clip band: lower edge sits below the upper edge")

-- Mirror of Rotation.wouldClip so the band logic itself is covered.
local function clips(rem, baseCast)
  if rem <= 0 then return false end
  if rem <= Nock.ClipQueueEdge() then return false end
  return Nock.ClipThreshold(baseCast) > rem
end
ok(not clips(upper + 0.01, 1.5), "band: safe above the upper edge")
ok(clips(upper - 0.01, 1.5),     "band: clips just inside the upper edge")
ok(clips(lower + 0.01, 1.5),     "band: still clips just above the queue edge")
ok(not clips(lower - 0.01, 1.5), "band: safe once the press would queue")
ok(not clips(0, 1.5),            "band: no swing pending is never a clip")

-- 12. CastBarSource: precedence at the render edge. A real cast (or the Feign
--     Death bar, which Modules/CastBar projects into the same field) always
--     wins; the wind-up is shown only when the calling view allows it.
Nock.Constants.SpellID = { AUTO_SHOT = 75, STEADY_SHOT = 34120 }
local realCast = { spellId = 34120, endTime = 999 }
local windUp   = { spellId = 75, endTime = 999, auto = true }

st.player.casting, st.player.autoShotCast = nil, nil
ok(Nock.CastBarSource(true) == nil,  "CastBarSource: nothing to draw")

st.player.casting, st.player.autoShotCast = nil, windUp
ok(Nock.CastBarSource(true)  == windUp, "CastBarSource: wind-up shown when allowed")
ok(Nock.CastBarSource(false) == nil,    "CastBarSource: wind-up hidden when not")

st.player.casting = realCast
ok(Nock.CastBarSource(true)  == realCast, "CastBarSource: real cast outranks the wind-up")
ok(Nock.CastBarSource(false) == realCast, "CastBarSource: real cast ignores the toggle")

-- The structural invariant this whole change exists for: whatever the display
-- setting says, the wind-up never appears in the field consumers read as a
-- lockout. There is no filtering helper left to forget to call.
ok(st.player.casting ~= windUp, "casting never holds the wind-up")
st.player.casting, st.player.autoShotCast = nil, nil

-- 13. No profile at all (called before AceDB is up) must not throw.
reset(0, 0.37, 1.0, 0)
Nock.db = nil
ok(near(Nock.ClipThreshold(1.5), castOf(1.5, 0.37) + 0.37),
   "ClipThreshold: survives a missing profile")

print(("clip_threshold: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
