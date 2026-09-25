-- Tests/react_melee_dual_test.lua
-- UI/Frame_ReactCluster.lua: dual wield splits the React melee bar (main hand on top in Raptor's colours, off hand below in the auto colour).
-- Run from the repo root: luajit Tests/react_melee_dual_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.GetTime = function() return 20 end
_G.unpack = unpack or table.unpack

local profile = {}
local mod
local Nock = {
  db = { profile = profile },
  Flavor = { forever = true },
  Constants = setmetatable({}, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }),
  UI = {
    CoachStage = function() return nil end,
    ReactStageLook = function() return nil end,
    DeviceRound = function(v) return math.floor(v + 0.5) end,
    -- Linear progress: enough to check which swing drives which fill.
    SwingFillProgress = function(_, start, rem, dur) return 1 - rem / dur end,
    SWING_CLOSE = { ease = 0.06, hold = 0.04, catch = 0.30 },
  },
}
function Nock:NewModule() mod = {}; function mod:RegisterMessage() end; return mod end
function Nock:GetModule() return {} end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("UI/Frame_ReactCluster.lua")

-- The pure split: main hand gets the extra device pixel.
local S = mod.MeleeSplit
local a, b = S(6, true, Nock.UI.DeviceRound)
ok(a == 3 and b == 3, "6 px splits 3 / 3")
a, b = S(7, true, Nock.UI.DeviceRound)
ok(a == 4 and b == 3, "7 px splits 4 / 3 (main hand on top gets the odd pixel)")
a, b = S(6, false, Nock.UI.DeviceRound)
ok(a == 6 and b == nil, "one weapon: one fill, full height")

-- A cluster with just the melee bar, sized like ApplyLayout leaves it.
local bar = Stub.CreateFrame("Frame")
local melee = {
  fill = Stub.CreateFrame("Texture"), offFill = Stub.CreateFrame("Texture"),
  text = Stub.CreateFrame("FontString"), stageText = Stub.CreateFrame("FontString"),
  cue = Stub.CreateFrame("Frame"),
}
setmetatable(melee, { __index = bar })
melee.offFill:Hide()   -- as OnInitialize builds it
local self = setmetatable({ melee = melee, _innerW = 200, _edge = 1, _meleeInH = 6, _pixelScale = 1 }, { __index = mod })

local state = {
  melee = { swingStart = 10, swingDuration = 2, swingRemaining = 1.5, offStart = 0, offDuration = 0, offRemaining = 0, dualWield = false },
  cooldowns = { Raptor = { ready = true } },
}

self:RefreshMelee(state)
ok(melee.offFill:IsShown() == false, "one weapon: no off-hand fill")
ok(melee.fill._w == 50, "main hand fills from its own swing (25%)")

state.melee.dualWield = true
state.melee.offStart, state.melee.offDuration, state.melee.offRemaining = 19, 2, 1
self:RefreshMelee(state)
ok(melee.offFill:IsShown() == true, "dual wield: the off-hand fill shows")
ok(melee.fill._h == 3 and melee.offFill._h == 3, "the row splits 3 / 3")
ok(melee.offFill._w == 100, "off hand fills from its own swing (50%)")
local green = { 0.15, 0.68, 0.38, 1.00 }
ok(melee.fill._color and math.abs(melee.fill._color[1] - green[1]) < 1e-6, "main hand keeps Raptor's ready colour")
ok(melee.offFill._color and math.abs(melee.offFill._color[1] - green[1]) > 1e-3, "off hand never turns Raptor-green")
ok(melee.offFill._color[1] == 1 and melee.offFill._color[2] == 1 and melee.offFill._color[3] == 1, "off hand is white by default")

state.melee.offRemaining = 0.5
self:RefreshMelee(state)
ok(melee.offFill._w == 150, "off-hand fill follows its swing")

profile.reactColorMeleeOff = { 0.9, 0.5, 0.1, 1 }
self:ApplyMeleeSplit(true)
ok(melee.offFill._color[1] == 0.9 and melee.offFill._color[2] == 0.5, "off-hand colour follows reactColorMeleeOff")
profile.reactColorMeleeOff = nil

state.melee.dualWield = false
self:RefreshMelee(state)
ok(melee.offFill:IsShown() == false, "back to one weapon: the off-hand fill hides")

print(("react_melee_dual: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
