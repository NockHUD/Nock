-- Tests/react_melee_stage_text_test.lua
-- UI/Frame_ReactCluster.lua: the weave stage on the melee bar with the
-- takeover (reactMeleeStageCue) OFF. Forever: the melee bar shows no stage
-- at all (the weave strip is the cue; user 2026-10-18). TBC: the small
-- centred text in the stage colour, as before 1.1.8.
-- Run from the repo root: luajit Tests/react_melee_stage_text_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.GetTime = function() return 20 end
_G.unpack = unpack or table.unpack

local profile = {}
local mod
local stage = nil
local GO = { text = "GO IN", fill = { 0.2, 0.9, 0.3, 1 }, march = 1 }
local Nock = {
  db = { profile = profile },
  Flavor = { forever = true },
  Constants = setmetatable({}, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }),
  UI = {
    CoachStage = function() return stage end,
    ReactStageLook = function(s) return s and GO or nil end,
    DeviceRound = function(v) return math.floor(v + 0.5) end,
    SwingFillProgress = function(_, start, rem, dur) return 1 - rem / dur end,
    SWING_CLOSE = { ease = 0.06, hold = 0.04, catch = 0.30 },
    StageLegTenths = function() return 0 end,
    StageLegText = function() return "" end,
    MarchOffset = function() return 0 end,
    FlashMix = function() return 0 end,
  },
}
function Nock:NewModule() mod = {}; function mod:RegisterMessage() end; return mod end
function Nock:GetModule() return {} end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("UI/Frame_ReactCluster.lua")

local function cluster()
  local bar = Stub.CreateFrame("Frame")
  local melee = {
    fill = Stub.CreateFrame("Texture"), offFill = Stub.CreateFrame("Texture"),
    text = Stub.CreateFrame("FontString"), stageText = Stub.CreateFrame("FontString"),
    cue = Stub.CreateFrame("Frame"),
  }
  setmetatable(melee, { __index = bar })
  melee.offFill:Hide()
  -- the takeover's marching runs, as OnInitialize builds them
  for _, side in ipairs({ "marchL", "marchR" }) do
    local mf = Stub.CreateFrame("Frame")
    mf.tris, mf.count, mf.pitch, mf.carrier = {}, 0, 10, Stub.CreateFrame("Frame")
    melee.cue[side] = mf
  end
  return setmetatable({ melee = melee, _innerW = 200, _edge = 1, _meleeInH = 6, _pixelScale = 1 }, { __index = mod }), melee
end
local state = {
  melee = { swingStart = 10, swingDuration = 2, swingRemaining = 1.5, offStart = 0, offDuration = 0, offRemaining = 0, dualWield = false },
  cooldowns = { Raptor = { ready = true } },
}

-- Forever, takeover off: a stage puts nothing on the melee bar.
local self, melee = cluster()
stage = "GO"
self:RefreshMelee(state)
ok(melee.text._text == "" and melee.cue:IsShown() == false, "Forever, cue off: GO leaves the melee bar's text empty and no takeover")
ok(melee.fill._w == 50, "the swing fill is untouched")
stage = nil
self:RefreshMelee(state)
ok(melee.text._text == "", "no stage: still empty (no READY on Forever)")

-- Forever, takeover on: the full-bar cue as before.
profile.reactMeleeStageCue = true
stage = "GO"
self:RefreshMelee(state)
ok(melee.cue:IsShown() == true and melee.stageText._text == "GO IN" and melee.text._text == "", "Forever, cue on: the takeover with the big word")
profile.reactMeleeStageCue = nil
stage = nil
self:RefreshMelee(state)

-- TBC, takeover off: the small stage text in the stage colour, as before.
Nock.Flavor.forever = false
self, melee = cluster()
stage = "GO"
self:RefreshMelee(state)
ok(melee.text._text == "GO IN" and melee.cue:IsShown() == false, "TBC, cue off: the small stage text")
stage = nil
state.melee.swingRemaining = 0
self:RefreshMelee(state)
ok(melee.text._text == "READY", "TBC: READY when the stage clears and the swing is up")

print(("react_melee_stage_text: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
