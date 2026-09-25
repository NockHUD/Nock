-- Tests/onboarding_view_test.lua
-- The wizard window's remembered position: a saved anchor is reused only while
-- it still lands on screen; anything else falls back to the docked default.
-- Run from the repo root: luajit Tests/onboarding_view_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.UIParent = Stub.CreateFrame("Frame")
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.unpack = unpack or table.unpack
_G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
local Nock = {
  Constants = { COLORS = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }), FONT = { PATH = "" } },
  UI = { ApplyBackdrop = function() end, GetFont = function() return "" end, RegisterHeaderFontString = function() end },
  db = { char = {}, profile = {} }, modules = {},
}
function Nock:NewModule(name) local m = { name = name }; function m:RegisterMessage() end; self.modules[name] = m; return m end
function Nock:GetModule(name) return self.modules[name] end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("UI/KeyCapture.lua")
dofile("UI/Frame_Onboarding.lua")
local View = Nock.modules.OnboardingView

ok(View.PositionValid(nil, 1920, 1080) == false, "no saved position: default")
ok(View.PositionValid(false, 1920, 1080) == false, "false: default")
ok(View.PositionValid({ point = "RIGHT", relPoint = "RIGHT", x = -24, y = 0 }, 1920, 1080) == true, "docked default is valid")
ok(View.PositionValid({ point = "CENTER", relPoint = "CENTER", x = 0, y = 170 }, 1920, 1080) == true, "old centre spot is valid")
ok(View.PositionValid({ point = "CENTER", relPoint = "CENTER", x = 3000, y = 0 }, 1920, 1080) == false, "off the right edge: default")
ok(View.PositionValid({ point = "CENTER", relPoint = "CENTER", x = 0, y = -2000 }, 1920, 1080) == false, "off the bottom: default")
ok(View.PositionValid({ point = "TOPLEFT" }, 1920, 1080) == false, "missing numbers: default")

ok(View.PanelHeight(0) == 430, "empty body keeps the base height")
ok(View.PanelHeight(260) == 430, "the base body fits in the base height")
ok(View.PanelHeight(300) == 96 + 300 + 74, "taller content grows the window")
ok(View.PanelHeight(2000) == 620, "the window never grows past 620")

-- Render smoke: every page kind the Forever script uses draws without error,
-- sliders show the engine's value, and a long page grows the window.
do
  local pages = {
    { key = "c", kind = "cards", options = { { value = "a", label = "A", isSelected = function() return true end } },
      toggles = { { key = "t1", label = "T1", desc = "d" } } },
    { key = "s", kind = "toggles", compact = true, options = {
      { key = "t2", label = "T2", desc = "d" },
      { slider = true, key = "sz", label = "Size", min = 10, max = 50, step = 2, default = 20 } } },
    { key = "i", kind = "intro", body = "Body text", keyCapture = { label = "Ring key", get = function(p) return p.ringKey end, set = function() end } },
    { key = "f", kind = "finish" },
  }
  local cur = 1
  local E = { Pages = pages }
  function E:CurrentPage() return pages[cur], cur end
  function E:Progress() return cur, #pages end
  function E:IsLastPage() return cur == #pages end
  function E:IsOptionLocked() return false end
  function E:IsOptionOn() return true end
  function E:OptionValue(opt) return Nock.db.profile[opt.key] or opt.default end
  function E:BuildRecap() return { { "HUD", "x" } } end
  Nock.modules.Onboarding = E
  Nock.db.profile = { sz = 30, ringKey = "SHIFT-R" }
  Nock.OpenConfig = function() end
  _G.GameTooltip = nil
  local okRun, err = pcall(function()
    View:Show()
    for i = 1, #pages do cur = i; View:Render() end
  end)
  ok(okRun, "every page kind renders: " .. tostring(err))
  local f = View.frame
  ok(f.sliders[1] and f.sliders[1].value:GetText() == "30", "slider shows the stored value")
  ok(f.keyBtn and f.keyBtn:GetText() == "Ring key: SHIFT-R", "key button shows the bound key")
  cur = 2; View:Render()
  ok(f.toggles[1]._scripts.OnEnter ~= nil, "compact rows carry a tooltip")
  cur = 1; View:Render()
  ok(f.toggles[1]._scripts.OnEnter == nil, "full rows drop it again")
  cur = 2; View:Render()
  ok(f._h == 430, "a short page keeps the base height")
  ok(f._clamped == true, "the window is clamped to the screen (it grows)")

  -- Sliders save whatever the client passes as the third argument.
  local saved
  function E:SetOptionValue(_, opt, v) saved = v end
  f.sliders[1].slider._scripts.OnValueChanged(f.sliders[1].slider, 40, nil)
  ok(saved == 40, "a slider drag saves even without a userInput flag")

  -- Key capture: refuses the chat keys and never outlives its page or the window.
  local KC = Nock.UI.KeyCapture
  local seenOpts
  local realBegin = KC.Begin
  KC.Begin = function(fr, done, opts) seenOpts = opts; return realBegin(fr, done, opts) end
  function E:ApplyKey() end
  function E:Teardown() end
  cur = 3; View:Render()
  f.keyBtn._scripts.OnClick(f.keyBtn)
  ok(KC.IsActive() and seenOpts and seenOpts.refuse and seenOpts.refuse.OPENCHAT and seenOpts.refuse.TOGGLEGAMEMENU,
     "capture refuses the chat and game-menu keys")
  cur = 4; View:Render()
  ok(not KC.IsActive(), "leaving the ring page ends the capture")
  cur = 3; View:Render()
  f.keyBtn._scripts.OnClick(f.keyBtn)
  f._scripts.OnHide(f)
  ok(not KC.IsActive(), "closing the wizard ends the capture")
  KC.Begin = realBegin
end

-- A first-ever render of an intro page without a key row (Welcome) must not
-- show the key button: it is created on that render and starts visible.
do
  local E2 = { Pages = { { key = "w", kind = "intro", body = "Hi" } } }
  function E2:CurrentPage() return self.Pages[1], 1 end
  function E2:Progress() return 1, 1 end
  function E2:IsLastPage() return false end
  Nock.modules.Onboarding = E2
  View.frame = nil
  View:Show()
  local f = View.frame
  ok(f.introText:IsShown() and not f.keyBtn:IsShown() and not f.keyHint:IsShown(), "Welcome shows no empty key button")
end

print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
