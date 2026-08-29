-- Tests/workbench_test.lua
-- The practice workbench (UI/Frame_Workbench.lua) under the frame stub, with
-- the real practice panel (UI/Frame_Practice.lua) hosted in it: the rail, the
-- host contract, show/hide with practice mode, close and reopen.
-- Run from the repo root: luajit Tests/workbench_test.lua
package.path = "./?.lua;./Tests/?.lua;" .. package.path
local pass, fail = 0, 0
local function ok(cond, name) if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end end
local Stub = dofile("Tests/lib/frame_stub.lua")

Nock = { modules = {}, db = { profile = {} }, state = { sim = { active = false, fightOn = false }, ranged = {}, player = {} } }
local sent = {}
function Nock:NewModule(name)
  local m = { name = name, RegisterMessage = function(self, msg, fn) self._handlers = self._handlers or {}; self._handlers[msg] = fn end,
              SendMessage = function() end, RegisterEvent = function() end, ScheduleTimer = function() end, CancelTimer = function() end,
              Print = function() end }
  Nock.modules[name] = m
  return m
end
function Nock:GetModule(name) return Nock.modules[name] end
function Nock:SendMessage(msg) sent[msg] = (sent[msg] or 0) + 1 end
function Nock:Print() end
local function deliver(m, msg) local h = m._handlers and m._handlers[msg]; if type(h) == "string" then m[h](m) elseif h then h(m) end end
_G.LibStub = setmetatable({}, { __call = function(_, lib, silent)
  if lib == "AceConfigDialog-3.0" then return nil end
  return { GetAddon = function() return Nock end, NewAddon = function() return Nock end,
           Fetch = function() return "font" end, Register = function() end }
end })
_G.CreateFrame = Stub.CreateFrame
_G.UIParent = Stub.CreateFrame("Frame", "UIParent")
_G.GameTooltip = Stub.CreateFrame("Frame", "GameTooltip")
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.GetTime = function() return 1000 end
_G.InCombatLockdown = function() return false end
_G.C_Spell = { GetSpellInfo = function() return {} end, GetSpellTexture = function() return "" end }

dofile("Core/Constants.lua")
Nock.UI = { GetFont = function() return "font" end, ApplyPanelBackground = function() end, RegisterPanelBackground = function() end,
            RegisterPracticeScale = function() end, PracticeScale = function() return 1 end,
            RegisterFontString = function() end, RegisterHeaderFontString = function() end, ApplyIconBorder = function() end,
            PracticeIconFor = function() return "" end, SafeSetFont = function() end, ApplyBackdrop = function() end,
            CreateReactSlot = function(parent) local s = Stub.CreateFrame("Frame", nil, parent); s.time = s:CreateFontString(); s.label = s:CreateFontString(); s.icon = s:CreateTexture(); s.border = s:CreateTexture(); return s end,
            CreateIconSlot = function(parent) local s = Stub.CreateFrame("Frame", nil, parent); s.time = s:CreateFontString(); s.label = s:CreateFontString(); s.icon = s:CreateTexture(); s.border = s:CreateTexture(); s.cd = Stub.CreateFrame("Cooldown", nil, s); return s end, GetBarTexture = function() return "" end }
-- Any UI helper the panel asks for that the stub does not model returns a stub frame.
setmetatable(Nock.UI, { __index = function(_, k) return function(...) return Stub.CreateFrame("Frame") end end })
dofile("UI/IconAtlas.lua")
dofile("UI/Skin.lua")
dofile("UI/PracticeTransport.lua")
dofile("UI/PracticePalette.lua")
dofile("UI/Frame_Workbench.lua")
local WB = Nock:GetModule("PracticeWorkbench")
WB:OnInitialize()

-- 1. the shell
ok(WB.frame ~= nil and WB:ContentFrame() ~= nil, "the workbench frame and its content area exist")
local n = 0; for _ in pairs(WB.items) do n = n + 1 end
ok(n == 7 and WB.items.stage and WB.items.review and WB.items.style and WB.items.keys and WB.items.leave == nil, "seven pages on the rail, no Leave item (the X leaves)")
ok(WB.items.stage.on == true and WB.items.lesson.on ~= true, "Stage is the page on open")
ok(_G.UISpecialFrames[1] == "NockWorkbench", "Esc closes it (UISpecialFrames)")

-- 2. rail actions before the pages move in
-- The review is hidden while its flag is off (user, 2026-08-26): no rail
-- item, and asking for the page lands on the Stage.
ok(WB.items.review:IsShown() == false, "Review is off the rail while practiceReviewEnabled is off")
WB:Select("review")
ok(WB.items.review.on ~= true and WB.items.stage.on == true, "...and selecting it lands on the Stage")
Nock.db.profile.practiceReviewEnabled = true
WB:LayoutRail()
ok(WB.items.review:IsShown() == true, "...the flag puts it back on the rail")
WB:Select("review")
ok(sent["NOCK_PRACTICE_TIMELINE_TOGGLE"] == nil and WB.items.review.on == true, "Review is a page: the rail moves to it")
WB:Select("stage")
WB:Select("scenarios")
ok(sent["NOCK_PRACTICE_SCENARIOS_TOGGLE"] == nil and WB.items.scenarios.on == true, "Scenarios is a page: the rail moves to it, no window opens")
WB:Select("ladder")
ok(sent["NOCK_PRACTICE_LESSON_TOGGLE"] == nil and WB.items.ladder.on == true, "Ladder is a page too")
WB:Select("lesson")
ok(sent["NOCK_PRACTICE_LESSON_TOGGLE"] == nil and WB.items.lesson.on == true, "Lesson is a page too")
WB:Select("stage")
WB:Select("style")
ok(WB.items.style.on == true, "Style is a page")
WB:Select("stage")

-- 3. visibility follows practice mode; close and reopen
WB:OnEnable()
ok(WB.frame:IsShown() == false, "hidden while practice is off")
Nock.state.sim.active = true
deliver(WB, "NOCK_PRACTICE_CHANGED")
ok(WB.frame:IsShown() == true, "shown when practice comes on")
WB:Close()
ok(WB.frame:IsShown() == false, "close hides it")
deliver(WB, "NOCK_PRACTICE_CHANGED")
ok(WB.frame:IsShown() == false, "...and a relayout does not bring it back")
deliver(WB, "NOCK_PRACTICE_OPEN")
ok(WB.frame:IsShown() == true, "NOCK_PRACTICE_OPEN reopens it")
Nock.state.sim.active = false
deliver(WB, "NOCK_PRACTICE_CHANGED")
ok(WB.frame:IsShown() == false, "practice off hides it")
-- Esc hides the frame behind the module's back (UISpecialFrames): that counts
-- as a close, and practice coming on again does not re-show it; open does.
Nock.state.sim.active = true
deliver(WB, "NOCK_PRACTICE_CHANGED")
WB._closed, WB._hiding = false, false   -- (in-game OnHide consumed the flag; the stub's Hide fires no script)
WB.frame:Hide(); local onHide = WB.frame._scripts and WB.frame._scripts.OnHide; if onHide then onHide(WB.frame) end
deliver(WB, "NOCK_PRACTICE_CHANGED")
ok(WB._closed == true and WB.frame:IsShown() == false, "Esc's hide is a close")
deliver(WB, "NOCK_PRACTICE_OPEN")
ok(WB.frame:IsShown() == true, "...until opened again")
Nock.state.sim.active = false
deliver(WB, "NOCK_PRACTICE_CHANGED")
-- A close does not outlive the practice session it was made in: closed (X or
-- Esc), practice off, practice on again -> the window is up on the first
-- `/nock practice`, not the second (user, 2026-08-27).
Nock.state.sim.active = true
deliver(WB, "NOCK_PRACTICE_CHANGED")
WB._hiding = false
WB.frame:Hide(); if onHide then onHide(WB.frame) end
ok(WB._closed == true, "closed by Esc while practice is on")
Nock.state.sim.active = false
deliver(WB, "NOCK_PRACTICE_CHANGED")
Nock.state.sim.active = true
deliver(WB, "NOCK_PRACTICE_CHANGED")
ok(WB.frame:IsShown() == true and WB._closed == false, "practice on again after a close shows the window on the first relayout")
Nock.state.sim.active = false
deliver(WB, "NOCK_PRACTICE_CHANGED")

-- 4. the practice panel hosts itself in the content area
Nock.state.sim.active = true
dofile("UI/Frame_Practice.lua")
local PV = Nock:GetModule("PracticeView")
local okInit, err = pcall(function() PV:OnInitialize() end)
ok(okInit, "the practice panel initialises under the stub (" .. tostring(err) .. ")")
if okInit then
  PV:OnEnable()
  ok(PV.frame:GetParent() == WB:ContentFrame(), "the panel is parented into the workbench's content area")
  ok(PV._host == WB:ContentFrame(), "...and knows it is hosted")
  -- The scenario picker's affordance (user, 2026-08-27): a down-chevron past
  -- the name, and the block takes the accent on hover.
  local sb = PV.frame.scenBtn
  ok(sb and sb.chev and sb.chev:IsShown() and sb.chev:GetPoint() ~= nil, "a chevron leads the scenario name")
  sb:GetScript("OnEnter")(sb)
  ok(sb.hot == true, "hover lights the name and the chevron")
  sb:GetScript("OnLeave")(sb)
  ok(sb.hot == nil, "...and the leave puts them back")
end

-- 5. Focus (shell step 3): the stage alone on the HUD. The real conveyor is
-- loaded under the stub so the dock/undock is the real one.
_G.IsMouseButtonDown = function() return false end
_G.GetCursorPosition = function() return 0, 0 end
_G.PlaySound = function() end
_G.SOUNDKIT = {}
_G.UnitRangedDamage = function() return 2.174 end
_G.UnitAttackSpeed = function() return 3.7 end
dofile("Core/State.lua")
dofile("Core/PracticeModel.lua")
dofile("Core/PracticeTimeline.lua")
dofile("Core/PracticePlan.lua")
dofile("Modules/PracticeGrader.lua")
Nock.state.sim.active, Nock.state.sim.fightOn = true, false
dofile("UI/Frame_PracticeConveyor.lua")
local CV = Nock:GetModule("PracticeConveyorView")
CV:OnInitialize()
CV:OnEnable()
Nock.UI.PracticeIconFor = function(sym) return "icon:" .. tostring(sym) end
if okInit then
  deliver(PV, "NOCK_PRACTICE_CHANGED")   -- the panel hosts the stage: flush, no gap
  ok(CV._docked == true and CV._padX == 0 and CV:DockGap() == 0, "hosted in the workbench the stage is docked flush: no inset, no gap")
  ok(CV.focusHead ~= nil and CV.focusHead:IsShown() == false, "the Focus head exists and is hidden while docked")
  local hostH = CV._hostH
  deliver(WB, "NOCK_PRACTICE_OPEN")
  ok(WB.frame:IsShown() == true, "window up before Focus")
  WB:Focus(true)
  ok(WB:IsFocus() == true and CV:IsFocus() == true, "Focus on: the workbench and the stage agree")
  ok(WB.frame:IsShown() == false, "...the window is hidden")
  ok(CV._docked == false and CV.frame:GetParent() == _G.UIParent, "...the stage is undocked onto the HUD")
  ok(Nock.db.profile.practiceConveyorDocked == nil, "...and the dock SETTING is untouched")
  ok(CV.focusHead:IsShown() == true, "...with the head line shown")
  ok(CV._hostH == hostH + 26, "...the head adds its line to the stage's height")
  local inSpecial = false
  for i = 1, #_G.UISpecialFrames do if _G.UISpecialFrames[i] == "NockPracticeConveyor" then inSpecial = true end end
  ok(inSpecial, "...and Esc reaches the stage (UISpecialFrames)")
  -- Quiet focus drops the coach row.
  Nock.db.profile.practiceQuietFocus = true
  CV:ApplyDock()
  ok(CV._coachH == 0 and CV.coach:IsShown() == false, "quiet focus: no coach row")
  Nock.db.profile.practiceQuietFocus = nil
  CV:ApplyDock()
  ok(CV._coachH > 0 and CV.coach:IsShown() == true, "...and it is back when the setting goes")
  -- Esc on the stage during a fight: Stop, then back to the window.
  local stopped = 0
  local prac = Nock:GetModule("Practice") or Nock:NewModule("Practice")
  prac.StopFight = function() stopped = stopped + 1; Nock:SendMessage("NOCK_PRACTICE_FOCUS", false) end
  Nock.state.sim.fightOn = true
  CV.frame:Hide(); local onHide = CV.frame:GetScript("OnHide"); if onHide then onHide(CV.frame) end
  ok(stopped == 1, "Esc in Focus during a fight stops the fight")
  Nock.state.sim.fightOn = false
  -- The message the fight's own Stop sends: back to the window, docked.
  deliver(WB, "NOCK_PRACTICE_FOCUS")   -- (the stub's deliver passes no arg: off)
  WB:Focus(false)
  ok(WB:IsFocus() == false and CV:IsFocus() == false and CV._docked == true, "Focus off: the stage docks back")
  ok(WB.frame:IsShown() == true, "...and the window returns")
  inSpecial = false
  for i = 1, #_G.UISpecialFrames do if _G.UISpecialFrames[i] == "NockPracticeConveyor" then inSpecial = true end end
  ok(not inSpecial, "...and leaves UISpecialFrames")
  -- Practice off while in Focus ends it.
  WB:Focus(true)
  Nock.state.sim.active = false
  deliver(WB, "NOCK_PRACTICE_CHANGED")
  ok(WB:IsFocus() == false and CV:IsFocus() == false, "practice off ends Focus")
  Nock.state.sim.active = true
  ok(WB.Focus and (function() WB:Focus(true); local r = WB:IsFocus(); WB:Focus(false); return r end)(), "Focus toggles by hand with no fight (for placing the strip)")
  -- The replay transport sits over the coach row only while a replay is up.
  ok(CV.transport ~= nil and CV.transport:IsShown() == false, "the replay transport exists and is hidden")
  prac._replay = { t0 = 1000, t1 = 1045.2, at = 1012.3, rev = 1, verdicts = {} }
  prac.engine = { n = 0, events = {} }
  prac.Lookahead = function() return nil end
  Nock.state.sim.fightOn = false
  CV:Refresh(Nock.state)
  ok(CV.transport:IsShown() == true and CV.transport.time:GetText() == "12.3s / 45.2s", "...shown with the readout in a replay")
  prac._replay = nil
  CV:Refresh(Nock.state)
  ok(CV.transport:IsShown() == false, "...and gone when the replay is")
  -- The title bar's X leaves practice (the replay would keep driving the HUD
  -- from behind a closed window otherwise); there is no rail item for it.
  local left = 0
  prac.Stop = function() left = left + 1 end
  WB:Select("leave")
  ok(left == 0, "no Leave item on the rail")
  prac.IsActive = function() return Nock.state.sim.active end
  Nock.state.sim.active = true
  WB:Open()
  WB:Close()
  ok(left == 1 and WB.frame:IsShown() == false, "the window's X leaves practice")
  prac.IsActive = nil
  -- The default seat is the centre of the screen's TOP half.
  Nock.db.profile.practiceWorkbenchPos = nil
  WB:ResetPos()
  local pt, _, rel, x, y = WB.frame:GetPoint(1)
  ok(pt == "CENTER" and rel == "CENTER" and x == 0 and y == UIParent:GetHeight() / 4, "the default seat is centred in the top half")
end

-- 6. The Scenarios page (step 4): the picker's grid in the room under the
-- panel, sized by its own height, the pick following the profile.
local prac6 = Nock:GetModule("Practice") or Nock:NewModule("Practice")
local picked
prac6.Catalog = function() return { groups = {
  { key = "turret", title = "Paper drills", items = { { name = "5:5:1:1", sub = "paper", color = { 1, 0, 0 } }, { name = "Clean French", sub = "paper" } } },
  { key = "scripts", title = "Scripts", items = { { name = "Rapid Fire at 5 s", sub = "rf@5" } } },
  { key = "mine", title = "Mine", items = {} },
} } end
prac6.SetScenario = function(_, name) picked = name; Nock.db.profile.practiceScenario = name; deliver(SV, "NOCK_PRACTICE_CHANGED") end
dofile("UI/Frame_PracticeScenarios.lua")
SV = Nock:GetModule("PracticeScenarioView")
SV:OnInitialize()
SV:OnEnable()
ok(SV._host == WB:PageFrame() and WB.pages.scenarios ~= nil, "the picker registers as the Scenarios page")
ok(SV.frame:IsShown() == false, "...hidden until the rail selects it")
Nock.state.sim.active = true
deliver(WB, "NOCK_PRACTICE_OPEN")
local hStage = WB.frame:GetHeight()
WB:Select("scenarios")
ok(SV.frame:IsShown() == true and WB.items.scenarios.on == true and WB.items.stage.on ~= true, "selecting Scenarios shows the page and moves the rail")
ok(SV._nCards == 2 and SV._nHeaders == 3, "two cards (the open Turret box) under three boxes")
ok(WB.frame:GetHeight() > hStage and WB.page:GetHeight() == SV:PageHeight(), "the window grows to the page's height")
-- Accordion (2026-08-27): one group open at a time, Turret by default; a
-- title-bar click opens that group and shuts the open one; remembered.
do
  ok(SV.headers[1].open == true and SV.headers[1].groupKey == "turret" and SV.headers[2].open ~= true, "Turret is the open box by default")
  local h2 = SV.headers[2]
  h2.bar:GetScript("OnClick")(h2.bar)
  ok(SV.headers[2].open == true and SV.headers[1].open ~= true and Nock.db.profile.practiceScenarioOpen == h2.groupKey,
     "a title-bar click opens that box and shuts the other, remembered")
  ok(SV.headers[1].meta:GetText():find("5:5:1:1", 1, true) ~= nil or SV.headers[1].meta:GetText():find("^%d"), "...the shut bar carries its count (and the pick when inside)")
  local h1 = SV.headers[1]
  h1.bar:GetScript("OnClick")(h1.bar)
  ok(SV.headers[1].open == true and Nock.db.profile.practiceScenarioOpen == "turret", "...and back")
  ok(SV.cards[1]:GetFrameLevel() > SV.headers[3]:GetFrameLevel(), "the cards sit over every box, whichever was made last")
end
Nock.db.profile.practiceScenario = "5:5:1:1"
SV:UpdateSelection()
ok(SV.cards[1].selected == true and SV.cards[2].selected ~= true, "the picked card carries the selection")
SV.cards[2]:GetScript("OnClick")(SV.cards[2])
ok(picked == "Clean French" and SV.frame:IsShown() == false and WB.items.stage.on == true, "a click picks and goes back to the Stage")
WB:Select("scenarios")
ok(SV.cards[2].selected == true, "...and the card shows as picked when the page is next opened")
deliver(SV, "NOCK_PRACTICE_SCENARIOS_TOGGLE")
ok(SV.frame:IsShown() == true and WB.items.scenarios.on == true, "the toggle message lands on the page, never closes it")
WB:Select("stage")
ok(SV.frame:IsShown() == false and WB.page.text:IsShown() == false and WB.page:GetHeight() == 0 and WB:PageHeight() == 0,
   "back on Stage the page hides and no room is left under the panel (no placeholder)")

-- 7. The Ladder page: three tracks side by side, eleven rungs, a click loads.
local ladderState = { done = { beat = true }, current = "multi", loaded = "multi" }
prac6.LadderState = function() return ladderState end
prac6.LadderItems = function() return {
  { id = "beat", name = "Hold the beat", sub = "1:1", section = "Turret", pass = "no clips", state = "done" },
  { id = "multi", name = "Add Multi", sub = "1:1 + Multi", pass = "85%", state = "cur" },
  { id = "weave-beat", name = "Weave the beat", sub = "in, hit, out", section = "Weave", pass = "3 weaves", state = "todo" },
  { id = "free", name = "Free play", sub = "your raid profile", section = "Mastery", pass = "-", state = "todo" },
} end
local resets = 0
prac6.ResetLadder = function() resets = resets + 1 end
dofile("UI/Frame_PracticeLadder.lua")
local LV = Nock:GetModule("PracticeLadderView")
LV:OnInitialize()
LV:OnEnable()
ok(WB.pages.ladder ~= nil and LV.frame:IsShown() == false, "the ladder registers as a page, hidden")
WB:Select("ladder")
ok(LV.frame:IsShown() == true and LV._nRows == 4 and LV._nHeaders == 3, "three track headers over the four rungs")
ok(LV.intro ~= nil and (LV.intro.body:GetText() or ""):find("challenge", 1, true) == nil and (LV.intro.title:GetText() or ""):find("challenge", 1, true) ~= nil
   and (LV.intro.body:GetText() or "") ~= "", "the page opens with an introduction: a title over a body (user, 2026-08-27)")
local _, _, _, _, rowY = LV.rows[1]:GetPoint()
ok(rowY ~= nil and rowY < -(10 + 92), "...and the tracks sit under it")
ok(LV.rows[1].check:IsShown() == true and LV.rows[2].loaded:IsShown() == true and LV.rows[2].bar:IsShown() == true
   and LV.rows[3].check:IsShown() == false and LV.rows[3].loaded:IsShown() == false, "done shows the check, the loaded rung its chip and line")
ok(LV.foot.prog:GetText() == "1 of 4 steps passed", "the foot counts the passes")
ok(WB.page:GetHeight() == LV:PageHeight() and LV:PageHeight() > 100, "the window takes the page's height")
sent["NOCK_PRACTICE_LADDER_DRILL"] = nil
LV.rows[3]:GetScript("OnClick")(LV.rows[3])
ok(sent["NOCK_PRACTICE_LADDER_DRILL"] == 1 and WB.items.ladder.on == true and LV.frame:IsShown() == true, "a click loads the drill and the page stays")
LV.foot.reset:GetScript("OnClick")()
ok(resets == 1, "Reset ladder asks Practice")
ladderState.done.multi = true
deliver(LV, "NOCK_PRACTICE_FIGHT_DONE")
ok(LV.foot.prog:GetText() == "1 of 4 steps passed" or LV.foot.prog:GetText() == "2 of 4 steps passed", "a fight boundary repaints the page")
WB:Select("stage")

-- 8. The Lesson page: the bar, the narration, Play slowly, the review's step.
dofile("Core/PracticeLesson.lua")
prac6.LessonPlan = function()
  return Nock.PracticeModel.STRINGS["1:1"], { ws = 3.0, rangedMul = 1.38, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0,
    multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 }, "1:1"
end
dofile("UI/Frame_PracticeLesson.lua")
local LSV = Nock:GetModule("PracticeLessonView")
LSV:OnInitialize()
LSV:OnEnable()
ok(WB.pages.lesson ~= nil and LSV._host == WB:PageFrame() and LSV.ladderRows == nil, "the lesson registers as a page, without the side ladder")
WB:Select("lesson")
ok(LSV.frame:IsShown() == true and LSV.plan ~= nil and (LSV.stepRows[1].text:GetText() or "") ~= "", "the page builds the plan and its narration")
ok(LSV.chip.text:GetText():find("1:1", 1, true) ~= nil, "the notation chip names the paper")
ok(LSV.plan.nPSegs > 0 and LSV.perCap:GetText():find("per period", 1, true) ~= nil and LSV._span == LSV.plan.periodDur,
   "the bar spans the paper's whole period, captioned")
local segs11 = LSV.segTex.n
-- A different paper is a different strip: 5:5:1:1 carries a Multi and an Arcane.
local n11 = LSV.plan.nPSegs
prac6.LessonPlan = function()
  return Nock.PracticeModel.STRINGS["5:5:1:1"], { ws = 3.0, rangedMul = 3.0 / 1.93, mws = 3.7, meleeMul = 1.0, imprArcanePts = 0,
    multiCd = 10, arcaneCdBase = 6, arcaneCdPerPt = 0.2 }, "5:5:1:1"
end
deliver(LSV, "NOCK_PRACTICE_CHANGED")
ok(LSV.plan.nPSegs > n11 and LSV.plan.multis == 1 and LSV.plan.arcanes == 1 and LSV.perCap:GetText():find("5:5:1:1", 1, true) ~= nil
   and LSV.segTex.n > segs11, "picking 5:5:1:1 redraws the bar with its five autos, the Multi and the Arcane")
ok(WB.page:GetHeight() == LSV:PageHeight() and LSV:PageHeight() > 200, "the window takes the lesson's height")
LSV:TogglePlay()
ok(LSV._playing == true and LSV.playBtn.text:GetText() == "Stop" and LSV._playDiv == 4, "Play slowly runs from the page, at a quarter tempo")
-- Play (1x, 2026-08-27): the other button restarts at the real tempo; both
-- examples (the bar and the drop) read the same clock.
LSV.playFastBtn:GetScript("OnClick")(LSV.playFastBtn)
ok(LSV._playing == true and LSV._playDiv == 1 and LSV.playFastBtn.text:GetText() == "Stop" and LSV.playBtn.text:GetText() == "Play slowly",
   "Play restarts at 1x and takes the Stop label")
LSV.playFastBtn:GetScript("OnClick")(LSV.playFastBtn)
ok(LSV._playing == false and LSV.playFastBtn.text:GetText() == "Play", "...a second click stops it")
LSV.playBtn:GetScript("OnClick")(LSV.playBtn)
-- The drop (2026-08-27): right of the narration, the paper's columns over
-- keycaps that are the binds; while playing the next note wears the edge.
local nDrop = LSV:DropColumns()
ok(LSV.dropF ~= nil and LSV.dropF:IsShown() == true and nDrop >= 2 and LSV._dropCols[1] == "a" and LSV._dropCols[2] == "s",
   "the drop shows the paper's columns, the auto first, then the Steady (" .. tostring(nDrop) .. ")")
ok(LSV.dropF.caps[1].key:GetText() == "auto" and LSV.dropF.caps[nDrop]:IsShown() == true and (nDrop == 5 or LSV.dropF.caps[nDrop + 1]:IsShown() == false),
   "...over one keycap per column, the auto's reading auto")
ok(LSV.stepRows[1]:GetWidth() < LSV._mainW and LSV._leftW + LSV._dropW < LSV._mainW, "...and the narration keeps the left 70 percent")
ok(LSV._playSpan == LSV.plan.periodDur, "...over the whole period")
ok(LSV.axisText.n == math.floor(LSV.plan.periodDur) + 1 and LSV.axisText[1]:GetText() == "0s", "a seconds axis runs under the bar")
prac6._liveEws = 2.40
LSV:Rebuild(true)   -- (the change gate keys on the paper, not the live bow)
ok(LSV.perCap:GetText():find("pinned at eWS 1.93", 1, true) ~= nil, "a paper pinned far from the player's bow says so in the caption")
prac6._liveEws = nil
-- The press cues: at t = 0 the first plate is NEXT (chip up, white edge), the
-- rest dimmed; past the first plate it fades and the flash fires.
LSV:Refresh()
ok(LSV._nPlates > 0 and LSV._nextK == 1 and LSV.nextChip:IsShown() == true and LSV.nextChip.text:GetText():find("NEXT", 1, true) == 1,
   "the first plate is NEXT with the chip over it")
ok(LSV.nextEdge[1]:IsShown() == true, "...and the white edge")
local plate2 = LSV._plates[2]
_G.GetTime = function() return 1000 + (plate2.t0 - 0.02) * 4 end   -- the cursor past plate 1, short of plate 2
LSV._playT0 = 1000
LSV:Refresh()
ok(LSV._nextK == 2 and LSV.flash:IsShown() == true, "reaching a plate flashes it and moves NEXT on")
_G.GetTime = function() return 1000 end
LSV:StopPlay()
ok(LSV.nextChip:IsShown() == false and LSV.nextEdge[1]:IsShown() == false, "stop clears the cues")
-- The ghost hunter button toggles the demo and lights while it runs -- and
-- the second click ends the fight the ghost armed (user, 2026-08-27: "the
-- timeline keeps moving"); so does leaving the page.
local demos, ghostStops = 0, 0
prac6.ToggleDemo = function(self) demos = demos + 1; self._demo = not self._demo; if self._demo then Nock.state.sim.fightOn = true end end
prac6.StopFight = function(self) ghostStops = ghostStops + 1; Nock.state.sim.fightOn = false end
Nock.state.sim.fightOn = false
ok(LSV.ghostBtn ~= nil and LSV.ghostBtn.kind == "ghost", "the Lesson page has a ghost hunter button")
LSV.ghostBtn:GetScript("OnClick")()
ok(demos == 1 and LSV.ghostBtn.kind == "primary" and LSV._preview == true and prac6._previewFight == true, "...it starts the demo as a preview fight and lights up")
LSV.ghostBtn:GetScript("OnClick")()
ok(demos == 2 and LSV.ghostBtn.kind == "ghost" and ghostStops == 1 and Nock.state.sim.fightOn == false and LSV._preview == nil, "...and the second click stops the ghost AND its fight")
LSV.ghostBtn:GetScript("OnClick")()
WB:Select("stage")
ok(demos == 4 and ghostStops == 2 and Nock.state.sim.fightOn == false, "leaving the Lesson page stops a running ghost and its fight")
-- A fight the player is running is not the ghost's to end.
Nock.state.sim.fightOn = true
LSV.ghostBtn:GetScript("OnClick")()
ok(LSV._preview == nil, "the ghost joins a running fight without claiming it")
LSV.ghostBtn:GetScript("OnClick")()
ok(ghostStops == 2 and Nock.state.sim.fightOn == true, "...and stopping it leaves that fight running")
Nock.state.sim.fightOn = false
prac6._previewFight, prac6.StopFight = nil, nil
LSV:ShowStep(3)
ok(WB.items.lesson.on == true and LSV._lit == 3, "the review's step opens the page on that step")
deliver(LSV, "NOCK_PRACTICE_LESSON_TOGGLE")
ok(LSV.frame:IsShown() == true, "the toggle message never closes the page")
-- A scenario picked from the Lesson page returns to the Lesson.
deliver(SV, "NOCK_PRACTICE_SCENARIOS_TOGGLE")
ok(WB.items.scenarios.on == true and WB:ReturnPage() == "lesson", "the picker opened from the Lesson remembers it")
SV.cards[1]:GetScript("OnClick")(SV.cards[1])
ok(WB.items.lesson.on == true and LSV.frame:IsShown() == true, "...and the pick goes back there")
WB:Select("stage")
deliver(SV, "NOCK_PRACTICE_SCENARIOS_TOGGLE")
SV.cards[2]:GetScript("OnClick")(SV.cards[2])
ok(WB.items.stage.on == true, "...while from the Stage it goes back to the Stage")
WB:Select("stage")

-- 9. The Review page: registered, gated by the flag, opened by Stop.
dofile("Modules/PracticeLadder.lua")
prac6.lastScore, prac6.lastVerdicts = nil, nil
prac6.BuildReport = function() return nil end
prac6.TimelineData = function() return nil end   -- no fight yet: the empty line
-- Anything else the review asks Practice for answers nil (no fight, no score).
setmetatable(prac6, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() return nil end end end })
_G.CreateFrame = function(kind, name, parent, template)
  local fr = Stub.CreateFrame(kind, name, parent, template)
  if kind == "Slider" then fr.SetMinMaxValues = function() end end
  return fr
end
dofile("UI/Frame_PracticeTimeline.lua")
_G.CreateFrame = Stub.CreateFrame
local RV = Nock:GetModule("PracticeTimelineView")
local okRv, errRv = pcall(function() RV:OnInitialize(); RV:OnEnable() end)
ok(okRv, "the review initialises as a page (" .. tostring(errRv) .. ")")
if okRv then
  ok(WB.pages.review ~= nil and RV._host == WB:PageFrame(), "the review registers as the Review page")
  Nock.db.profile.practiceReviewEnabled = nil
  WB:Select("stage")
  Nock.db.profile.practiceReviewEnabled = true
  deliver(RV, "NOCK_PRACTICE_TIMELINE_TOGGLE")
  ok(WB.items.review.on == true and RV.frame:IsShown() == true, "the page opens on request with the flag on")
  WB:Select("stage")
  Nock.db.profile.practiceReviewEnabled = false
  WB:Select("stage")
  deliver(RV, "NOCK_PRACTICE_FIGHT_DONE")
  ok(WB.items.stage.on == true, "...but a finished fight does not open it with the flag off")
  Nock.db.profile.practiceReviewEnabled = true
  deliver(RV, "NOCK_PRACTICE_TIMELINE_TOGGLE")   -- on the Review page (the Stage has no room at all)
  ok(WB.page:GetHeight() == math.max(120, RV:PageHeight()) and RV:PageHeight() > 40, "the window takes the review's height (over the page floor)")
  WB:Select("stage")
  deliver(RV, "NOCK_PRACTICE_FIGHT_DONE")
  ok(WB.items.review.on == true, "a finished fight returns to the window on Review")
  Nock.db.profile.practiceReviewEnabled = nil
  WB:Select("stage")
end
setmetatable(prac6, nil)

-- 10. The Style page: one segmented row per lever, a click writes the key.
Nock.PracticeTimeline = Nock.PracticeTimeline or dofile("Core/PracticeTimeline.lua")
prac6.StyleCommand = nil
-- The preview ghost: ToggleDemo arms a fight; StopFight ends it.
local demoModes, stops = {}, 0
prac6.ToggleDemo = function(self, mode) demoModes[#demoModes + 1] = mode or "off"; self._demo = not self._demo; if self._demo then Nock.state.sim.fightOn = true end end
prac6.StopFight = function(self) stops = stops + 1; Nock.state.sim.fightOn = false end
Nock.state.sim.fightOn = false
dofile("UI/Frame_PracticeStyle.lua")
local STV = Nock:GetModule("PracticeStyleView")
STV:OnInitialize()
STV:OnEnable()
ok(WB.pages.style ~= nil and STV.frame:IsShown() == false, "the style page registers, hidden")
WB:Select("style")
local nLevers = #Nock.PracticeTimeline.STYLE_LEVERS
ok(STV.frame:IsShown() == true and STV._nRows == nLevers, "one row per lever")
ok(demoModes[1] == "perfect" and STV._preview == true and prac6._previewFight == true, "entering Style starts the perfect ghost as a preview fight")
local row1 = STV.rows[1]
ok(row1.segs[1].kind == "primary" and row1.segs[2].kind == "ghost", "the shipped value is lit, the rest are ghosts")
sent["NOCK_VISUALS_CHANGED"] = nil
row1.segs[2]:GetScript("OnClick")(row1.segs[2])
ok(Nock.db.profile[row1.lever.key] == row1.lever.values[2] and sent["NOCK_VISUALS_CHANGED"] == 1
   and row1.segs[2].kind == "primary" and row1.segs[1].kind == "ghost", "a click writes the lever and lights its segment")
STV.foot.reset:GetScript("OnClick")()
ok(Nock.db.profile[row1.lever.key] == nil and row1.segs[1].kind == "primary", "Reset clears the levers")
ok(WB.page:GetHeight() == STV:PageHeight() and STV:PageHeight() > 200, "the window takes the page's height")
-- Two columns (2026-08-27): rows 1 and 2 share a line, row 3 starts the next.
local _, _, _, x1, y1 = STV.rows[1]:GetPoint()
local _, _, _, x2, y2 = STV.rows[2]:GetPoint()
local _, _, _, x3, y3 = STV.rows[3]:GetPoint()
ok(x2 > x1 and y2 == y1 and x3 == x1 and y3 < y1, "the levers sit in two columns, reading order")
WB:Select("stage")
ok(demoModes[2] == "off" and stops == 1 and STV._preview == nil and Nock.state.sim.fightOn == false, "leaving Style stops the ghost and drops the preview fight")
-- A fight already running is left alone.
Nock.state.sim.fightOn = true
WB:Select("style")
ok(#demoModes == 2 and STV._preview == nil, "...and a running fight is not touched")
WB:Select("stage")
ok(stops == 1, "...nor stopped on leaving")
Nock.state.sim.fightOn = false
prac6._demo = nil

-- Start goes to the Stage (user, 2026-08-27): a fight starting while another
-- page is up moves the window to the Stage; the ghost's own fight does not.
WB:Select("lesson")
Nock.state.sim.fightOn = false
deliver(WB, "NOCK_PRACTICE_CHANGED")
Nock.state.sim.fightOn = true
deliver(WB, "NOCK_PRACTICE_CHANGED")
ok(WB.items.stage.on == true and WB.items.lesson.on ~= true, "a fight starting on the Lesson page moves the window to the Stage")
Nock.state.sim.fightOn = false
deliver(WB, "NOCK_PRACTICE_CHANGED")
WB:Select("lesson")
prac6._demo = true
Nock.state.sim.fightOn = true
deliver(WB, "NOCK_PRACTICE_CHANGED")
ok(WB.items.lesson.on == true, "...but the ghost's own fight leaves the page where it is")
prac6._demo = nil
Nock.state.sim.fightOn = false
deliver(WB, "NOCK_PRACTICE_CHANGED")
WB:Select("stage")

-- 13. The Keys page (2026-08-27): the rotation keys with what detection
-- found and an override capture each, and the practice-only proc keys.
dofile("UI/Frame_PracticeKeys.lua")
local KV = Nock:GetModule("PracticeKeysView")
local reapplied = 0
prac6.KeyRows = function()
  local o = Nock.db.profile.practiceKeys or {}
  return { { name = "steady", label = "Steady Shot", detected = "2, S-2", override = o.steady },
           { name = "multi",  label = "Multi-Shot",  detected = "",       override = o.multi } }
end
prac6.PROC_KEYS = { { name = "Lust", label = "Bloodlust", hint = "+30%" }, { name = "Drums", label = "Drums", hint = "h" } }
prac6.ProcKeyState = function(_, name)
  local k = (Nock.db.profile.practiceProcKeys or {})[name]
  return { override = k, clash = (name == "Drums" and k) and "steady" or nil }
end
prac6.ReapplyKeys = function() reapplied = reapplied + 1 end
prac6.NormalizeKey = function(s) return (s or ""):upper() end
prac6.ShortKey = function(s) return s end
-- The WEAVE KEY row (2026-08-27): Nock's real bind, and the Grounded import.
local groundedKey, imported = "SHIFT-F", false
local importCalls, undoCalls = 0, 0
prac6.WeaveKeyState = function()
  local db = Nock.db.profile
  local k = db.weaveBindKey; if k == "" then k = nil end
  return { override = k, enabled = db.weaveBindEnabled == true, grounded = groundedKey, imported = imported }
end
Nock.modules.WeaveBind = {
  ImportFromGrounded = function() importCalls = importCalls + 1; groundedKey = nil; imported = true; Nock.db.profile.weaveBindKey = "SHIFT-F"; Nock.db.profile.weaveBindEnabled = true; return true end,
  UndoGroundedImport = function() undoCalls = undoCalls + 1; groundedKey = "SHIFT-F"; imported = false; Nock.db.profile.weaveBindKey = ""; return true end,
}
KV:OnInitialize(); KV:OnEnable()
ok(WB.pages.keys ~= nil and WB.items.keys ~= nil, "the Keys page registers and sits on the rail")
WB:Select("keys")
ok(KV.frame:IsShown() == true and KV._nRows == 5, "five rows: the weave key, two rotation keys, two proc keys (" .. tostring(KV._nRows) .. ")")
local WV = KV.rows[1]
ok(WV.kind == "weave" and WV.info:GetText() == "Grounded holds SHIFT-F - import it" and WV.import:IsShown() == true and WV.import.text:GetText() == "Import from Grounded",
   "the weave row names the Grounded bind and offers the import")
WV.import:GetScript("OnClick")(WV.import)
WV = KV.rows[1]
ok(importCalls == 1 and WV.keyBtn.text:GetText() == "SHIFT-F" and WV.info:GetText() == "Nock's weave bind (from Grounded)" and WV.import.text:GetText() == "Undo import",
   "...the import fills the row and the button becomes the undo")
WV.import:GetScript("OnClick")(WV.import)
WV = KV.rows[1]
ok(undoCalls == 1 and WV.keyBtn.text:GetText() == "set key" and WV.import.text:GetText() == "Import from Grounded", "...and the undo puts the offer back")
local _, _, _, kx1, ky1 = KV.rows[2]:GetPoint()
local _, _, _, kx3, ky3 = KV.rows[4]:GetPoint()
ok(kx3 > kx1 and ky3 > ky1, "the proc keys sit in a second column, starting above the rotation rows (the weave row is first)")
ok(KV.rows[2].info:GetText() == "on your bars: 2, S-2" and KV.rows[3].info:GetText() == "not on a bar", "each rotation row says what detection found")
ok(KV.rows[2].keyBtn.text:GetText() == "set key" and KV.rows[2].clear:IsShown() == false, "no override: set key, no clear")
local function click(row, button) row.keyBtn:GetScript("OnClick")(row.keyBtn, button or "LeftButton") end
local function key(k) KV.frame:GetScript("OnKeyDown")(KV.frame, k) end
click(KV.rows[2])
ok(KV._waiting == KV.rows[2] and KV.rows[2].keyBtn.text:GetText() == "press a key" and KV.rows[2].keyBtn.kind == "primary", "a click waits for a key")
_G.IsShiftKeyDown = function() return true end
key("LSHIFT")
ok(KV._waiting == KV.rows[2], "a modifier alone is not a key")
key("R")
_G.IsShiftKeyDown = nil
ok(Nock.db.profile.practiceKeys.steady == "SHIFT-R" and reapplied == 1 and KV._waiting == nil, "Shift-R binds the override and rebinds live")
ok(KV.rows[2].keyBtn.text:GetText() == "SHIFT-R" and KV.rows[2].clear:IsShown() == true, "...the button shows it and the clear is up")
click(KV.rows[2]); key("ESCAPE")
ok(Nock.db.profile.practiceKeys.steady == nil and reapplied == 2 and KV.rows[2].keyBtn.text:GetText() == "set key", "Escape clears it")
click(KV.rows[3])
KV.rows[3].keyBtn:GetScript("OnMouseDown")(KV.rows[3].keyBtn, "Button4")
ok(Nock.db.profile.practiceKeys.multi == "BUTTON4", "a side mouse button binds too")
click(KV.rows[3], "RightButton")
ok(Nock.db.profile.practiceKeys.multi == nil, "a right-click clears")
click(KV.rows[4]); key("F5")
ok(Nock.db.profile.practiceProcKeys.Lust == "F5" and KV.rows[4].keyBtn.text:GetText() == "F5" and KV.rows[4].info:GetText() == "+30%", "a proc key writes practiceProcKeys")
click(KV.rows[5]); key("2")
ok(KV.rows[5].info:GetText() == "in use by steady", "a key the rotation holds says so")
-- The weave row's capture writes the REAL bind and wakes WeaveBind.
sent["NOCK_WEAVEBIND_CHANGED"] = nil
click(KV.rows[1]); key("G")
ok(Nock.db.profile.weaveBindKey == "G" and Nock.db.profile.weaveBindEnabled == true and sent["NOCK_WEAVEBIND_CHANGED"] == 1
   and KV.rows[1].keyBtn.text:GetText() == "G" and KV.rows[1].import:IsShown() == true
   and KV.rows[1].info:GetText() == "Grounded also holds SHIFT-F - the import replaces yours", "a key on the weave row is the Weave Bind's own; the import stays on offer")
click(KV.rows[1], "RightButton")
ok(Nock.db.profile.weaveBindKey == "" and KV.rows[1].info:GetText() == "Grounded holds SHIFT-F - import it", "...and a right-click clears it")
click(KV.rows[2])
WB:Select("stage")
ok(KV._waiting == nil, "leaving the page ends a capture")

-- 13b. The weave-key dialog (2026-08-27), and the toolbar's WEAVE KEY button
-- that opens it -- the way in for a user who never ran the wizard.
if okInit then
  prac6.PaperWeaves = function() return true end
  deliver(PV, "NOCK_PRACTICE_CHANGED")
  local wkb = PV.frame.weaveKeyBtn
  ok(wkb and wkb:IsShown() == true and wkb.text:GetText() == "Import weave key", "no key + Grounded holds one: the toolbar offers Import weave key")
  local _, met = PV.frame.met:GetPoint()
  ok(met == wkb, "...and the metronome sits past it")
  sent["NOCK_PRACTICE_WEAVEKEY"] = nil
  wkb:GetScript("OnClick")()
  ok(sent["NOCK_PRACTICE_WEAVEKEY"] == 1, "a click asks for the dialog")
  -- The dialog's macro cards are the wizard's own page: a fake Onboarding
  -- with the four cards' contract (visible / isSelected / apply, SelectCard).
  local shape = ""
  local function shapeCard(value, label, rec, txt)
    return { value = value, label = label, desc = "d " .. value, recommended = rec,
             isSelected = function(db) return db.weaveBindMacroDown == txt end,
             apply = function(db) db.weaveBindMacroDown = txt end }
  end
  Nock.modules.Onboarding = {
    Pages = { { key = "weavemacro", options = {
      shapeCard("default", "Default", true, "DEF"), shapeCard("clever", "Clever", false, "CLV"), shapeCard("natty", "Natty", false, ""),
      { value = "grounded", label = "From Grounded", desc = "move it",
        visible = function() return groundedKey ~= nil or imported end,
        isSelected = function(db) return imported and db.weaveBindMacroDown == "GRD" end,
        apply = function(db) Nock.modules.WeaveBind.ImportFromGrounded(); db.weaveBindMacroDown = "GRD" end },
    } } },
    SelectCard = function(_, page, opt) opt.apply(Nock.db.profile) end,
  }
  Nock.db.profile.weaveBindMacroDown, Nock.db.profile.weaveBindEnabled = "DEF", false   -- played with it before, left it off
  KV:OnWeaveKeyMessage(nil, true)
  local D = KV.dialog
  ok(D and D:IsShown() == true and KV._step == 1 and D.cards[4]:IsShown() == true and D.cards[4].label:GetText() == "From Grounded"
     and D.cards[1].chip:GetText() == "RECOMMENDED" and D.back:IsShown() == false, "the dialog opens on the macro step: the three shapes and From Grounded, nothing current yet")
  D.cards[4]:GetScript("OnClick")(D.cards[4])
  ok(importCalls == 1 and D.cards[4].chip:GetText() == "CHOSEN" and D.cards[4].selected == true and D.undoBtn:IsShown() == false
     and D.next.text:GetText() == "Import, then the key", "...a click on From Grounded only chooses it; Next says what it will do")
  D.next:GetScript("OnClick")()
  ok(importCalls == 2 and Nock.db.profile.weaveBindEnabled == true and KV._step == 2 and D.keyFs:GetText() == "SHIFT-F" and D.note:GetText() == "from Grounded"
     and D.back:IsShown() == true and D.next.text:GetText() == "Done", "Next imports, then the key step shows the imported key")
  deliver(PV, "NOCK_WEAVEBIND_CHANGED")
  ok(PV.frame.weaveKeyBtn:IsShown() == false, "...and the toolbar's button leaves once the key is held and Grounded is empty")
  D.back:GetScript("OnClick")()
  ok(KV._step == 1 and D.cards[4].chip:GetText() == "CURRENT" and D.undoBtn:IsShown() == true, "Back returns to the cards: From Grounded is current, the undo on offer")
  D.undoBtn:GetScript("OnClick")()
  ok(undoCalls == 2 and D.cards[4].selected == false and D.undoBtn:IsShown() == false, "...the undo empties it again")
  Nock.db.profile.weaveBindMacroDown = "CLV"
  D.cards[1]:GetScript("OnClick")(D.cards[1])
  ok(Nock.db.profile.weaveBindMacroDown == "CLV" and D.cards[1].chip:GetText() == "CHOSEN" and D.next.text:GetText() == "Apply, then the key", "Default chosen: nothing applied yet")
  D.next:GetScript("OnClick")()
  ok(Nock.db.profile.weaveBindMacroDown == "DEF" and Nock.db.profile.weaveBindEnabled == true, "...Next applies it")
  ok(KV._step == 2 and D.keyFs:GetText() == "NOT SET" and D.note:GetText():find("Grounded holds SHIFT-F", 1, true) ~= nil, "the key step: NOT SET, and the Grounded hint")
  -- Set key: the dialog's own capture, writing the real bind.
  D.setBtn:GetScript("OnClick")(D.setBtn, "LeftButton")
  ok(KV._waiting == KV.dlgRow and D.setBtn.text:GetText() == "press a key", "Set key waits on the dialog")
  D:GetScript("OnKeyDown")(D, "H")
  ok(Nock.db.profile.weaveBindKey == "H" and Nock.db.profile.weaveBindEnabled == true and KV._waiting == nil and D.keyFs:GetText() == "H",
     "...a key is the Weave Bind's own and the dialog shows it")
  ok(D.note:GetText() == "Grounded also holds SHIFT-F", "...the import stays on offer beside a key of your own")
  deliver(PV, "NOCK_WEAVEBIND_CHANGED")
  ok(PV.frame.weaveKeyBtn:IsShown() == true and PV.frame.weaveKeyBtn.text:GetText() == "Import weave key", "...the toolbar too, while Grounded holds one")
  groundedKey = nil
  deliver(PV, "NOCK_WEAVEBIND_CHANGED")
  ok(PV.frame.weaveKeyBtn:IsShown() == false, "with a key set and no Grounded the toolbar shows no button")
  D.clearBtn:GetScript("OnClick")()
  ok(Nock.db.profile.weaveBindKey == "" and D.keyFs:GetText() == "NOT SET", "Clear empties the bind")
  deliver(PV, "NOCK_WEAVEBIND_CHANGED")
  ok(PV.frame.weaveKeyBtn:IsShown() == true and PV.frame.weaveKeyBtn.text:GetText() == "Set weave key", "no key, no Grounded, a weave paper: Set weave key")
  prac6.PaperWeaves = function() return false end
  deliver(PV, "NOCK_PRACTICE_CHANGED")
  ok(PV.frame.weaveKeyBtn:IsShown() == false, "...and on a turret paper the button stays away")
  D.next:GetScript("OnClick")()
  ok(D:IsShown() == false, "Done closes the dialog")
  Nock.modules.Onboarding = nil
  Nock.db.profile.weaveBindMacroDown = nil
  D:Hide()
  prac6.PaperWeaves = nil
  groundedKey = "SHIFT-F"
end
Nock.db.profile.practiceKeys, Nock.db.profile.practiceProcKeys, Nock.db.profile.weaveBindKey, Nock.db.profile.weaveBindEnabled = nil, nil, nil, nil
Nock.modules.WeaveBind = nil
prac6.KeyRows, prac6.PROC_KEYS, prac6.ProcKeyState, prac6.ReapplyKeys, prac6.NormalizeKey, prac6.ShortKey, prac6.WeaveKeyState = nil, nil, nil, nil, nil, nil, nil

-- 13c. The page width never comes from a frame that has not been laid out
-- (a 1080p user's Keys page: both columns on x = 8, buttons off the rows'
-- left edge -- the fit rescale had cleared the root's points).
ok(WB.PAGE_W == 960 and WB:PageWidth() == 960, "PageWidth is the content column")
WB.page:SetWidth(0)
ok(WB:PageWidth() == 960, "...and stays so when the page frame reports 0")
WB.page:SetWidth(960)
if okInit then
  prac6.KeyRows = function() return { { name = "steady", label = "Steady Shot", detected = "", override = nil } } end
  prac6.PROC_KEYS = { { name = "Lust", label = "Bloodlust", hint = "+30%" } }
  prac6.ProcKeyState = function() return {} end
  prac6.WeaveKeyState = function() return { override = nil, enabled = false } end
  WB.page:SetWidth(0); KV.frame:SetWidth(0)
  WB:Select("keys")
  local _, _, _, cx1 = KV.rows[2]:GetPoint()
  local _, _, _, cx2 = KV.rows[3]:GetPoint()
  ok(cx2 - cx1 > 400 and KV.rows[2]:GetWidth() > 400, "the Keys page lays out two real columns with the frame reporting 0 width")
  WB.page:SetWidth(960); KV.frame:SetWidth(960)
  WB:Select("stage")
  prac6.KeyRows, prac6.PROC_KEYS, prac6.ProcKeyState, prac6.WeaveKeyState = nil, nil, nil, nil
end

-- 14. Fit to the screen (2026-08-27): the workbench caps its scale so the
-- tallest page seen fits the screen, and never grows back between pages.
ok(WB.FitScale(1130, 997, 1.25, 2560, 1440) == 1, "FitScale: the tallest page fits a 1440-unit screen at 1.25 -- no cap")
local f1080 = WB.FitScale(1130, 850, 1.25, 1920, 1080)
ok(f1080 > 0.97 and f1080 < 0.98, "FitScale: the Lesson at 1.25 on a 1080p default shrinks a hair (" .. tostring(f1080) .. ")")
local f768 = WB.FitScale(1130, 373, 1.25, 1366, 768)
ok(f768 > 0.93 and f768 < 0.94, "FitScale: on a 1366x768 laptop the WIDTH is the cap (" .. tostring(f768) .. ")")
ok(WB.FitScale(1130, 2000, 1.25, 1366, 768) == 0.5, "FitScale: floored at a half")
ok(WB.FitScale(1130, 400, 1.25, nil, nil) == 1 and WB.FitScale(1130, 400, 1.25, 0, 0) == 1, "FitScale: no screen, no cap")
local fitSeen
Nock.UI.SetPracticeScaleFit = function(_, fit) fitSeen = fit end
Nock.UI.PracticeScale = function() return 1.25 end
_G.UIParent:SetSize(1920, 1080)
WB._tallest, WB._fit = nil, nil
WB:Select("lesson")
local fitLesson = WB._fit
ok(fitSeen ~= nil and fitSeen < 1 and fitSeen == fitLesson, "the Lesson page on a 1080p screen caps the scale (" .. tostring(fitSeen) .. ")")
WB:Select("stage")
ok(WB._fit == fitLesson, "...and the Stage keeps that cap: the window never grows back between pages")
Nock.UI.PracticeScale = function() return 1 end
WB:Relayout()
ok(WB._fit == 1 and fitSeen == 1, "...a lower slider value lifts it")
_G.UIParent:SetSize(2560, 1440)
WB._tallest, WB._fit = nil, nil
WB:Relayout()

-- 11. The weave log: Focus-only, off by default, one row per weave.
dofile("UI/Frame_PracticeWeaveLog.lua")
local WL = Nock:GetModule("PracticeWeaveLogView")
WL:OnInitialize(); WL:OnEnable()
Nock.state.sim.active, Nock.state.sim.fightOn, Nock.state.sim.t0 = true, true, 1000
prac6.engine = { n = 5, events = {
  { t = 1001.9, kind = "cast", spell = "steady", t0 = 1000.8, t1 = 1001.9 },
  { t = 1002, kind = "weave", edge = "down" },
  { t = 1002.6, kind = "melee", hit = "r" },
  { t = 1003, kind = "weave", edge = "done", legs = { downAt = 1002, stepIn = 0.3, dwell = 0.05, stepOut = 0.32, total = 0.67, hitAt = 1002.6, hit = "r" } },
  { t = 1004.3, kind = "cast", spell = "steady", t0 = 1003.2, t1 = 1004.3 },
} }
Nock.state.weave = Nock.state.weave or {}
prac6.grader = { verdicts = { { t = 1003, code = "WEAVE_OK", ms = 0, key = "weave" } } }
prac6.PaperWeaves = function() return false end
WL:Refresh(Nock.state)
ok(WL.frame:IsShown() == false, "the weave log is hidden with the setting off")
Nock.db.profile.practiceWeaveLog = true
WL:Refresh(Nock.state)
ok(WL.frame:IsShown() == false, "...and hidden on a paper without weaves")
prac6.PaperWeaves = function() return true end
WL:Refresh(Nock.state)
ok(WL.frame:IsShown() == true and WL.rows[1]:IsShown() == true and WL.rows[1].a2w:GetText() == "700" and WL.rows[1].w2a:GetText() == "600" and WL.rows[1].tot:GetText() == "1300",
   "on a weave paper with the setting on it shows A-W / W-A / T off the stream")
ok(WL.head.count == nil and WL.rows[1].rearm == nil, "no total in the head, no re-arm column (user, 2026-08-27)")
-- A weave with no hit is a FAILED one, said in red (user, 2026-08-27).
prac6.engine.n = 6
prac6.engine.events[6] = { t = 1006, kind = "weave", edge = "done", legs = { downAt = 1005.4, stepIn = 0.3, total = 0.6 } }
WL:Refresh(Nock.state)
ok(WL.rows[1].tot:GetText() == "FAILED" and WL.rows[1].a2w:GetText() == "-", "a weave without a hit reads FAILED")
ok(WL.rows[2].tot:GetText() == "1300", "...and the one before it keeps its total")
-- An Arcane pressed on the way out, the weave key still held, is filed BEFORE
-- the weave's own done event: it is the shot that closes the weave, not the
-- Steady seconds later (user, 2026-08-27: "insanely long" totals).
prac6.engine.events[4] = { t = 1002.9, kind = "cast", spell = "arcane", t0 = 1002.9, t1 = 1002.9 }
prac6.engine.events[5] = { t = 1003, kind = "weave", edge = "done", legs = { downAt = 1002, stepIn = 0.3, dwell = 0.05, stepOut = 0.32, total = 0.67, hitAt = 1002.6, hit = "r" } }
prac6.engine.events[6] = { t = 1006.3, kind = "cast", spell = "steady", t0 = 1005.2, t1 = 1006.3 }
prac6.engine.n = 6
WL._sig = nil   -- (the failed-weave step above left the stream at six events too)
WL:Refresh(Nock.state)
ok(WL.rows[1].w2a:GetText() == "300" and WL.rows[1].tot:GetText() == "1000", "an Arcane filed before the weave's done event closes the weave (" .. WL.rows[1].w2a:GetText() .. "/" .. WL.rows[1].tot:GetText() .. ")")
prac6.engine.events[4] = { t = 1003, kind = "weave", edge = "done", legs = { downAt = 1002, stepIn = 0.3, dwell = 0.05, stepOut = 0.32, total = 0.67, hitAt = 1002.6, hit = "r" } }
prac6.engine.events[5] = { t = 1004.3, kind = "cast", spell = "steady", t0 = 1003.2, t1 = 1004.3 }
prac6.engine.events[6] = nil
prac6.engine.n = 5
WL._sig = nil
WL:Refresh(Nock.state)
prac6.engine.events[6] = nil
prac6.engine.n = 5
-- The next ranged counts from its BEGINNING: a Steady still casting (the
-- stream files a cast at its end) closes the weave at its start, and an auto
-- from its wind-up -- the earliest start wins, not the first event filed.
prac6.engine = { n = 4, events = {
  { t = 1001.9, kind = "cast", spell = "steady", t0 = 1000.8, t1 = 1001.9 },
  { t = 1002, kind = "weave", edge = "down" },
  { t = 1002.6, kind = "melee", hit = "r" },
  { t = 1003, kind = "weave", edge = "done", legs = { downAt = 1002, stepIn = 0.3, dwell = 0.05, stepOut = 0.32, total = 0.67, hitAt = 1002.6, hit = "r" } },
}, cast = { spell = "steady", t0 = 1003.1, t1 = 1004.6 } }
WL:Refresh(Nock.state)
ok(WL.rows[1].w2a:GetText() == "500" and WL.rows[1].tot:GetText() == "1200", "a Steady still casting closes the weave at its START")
prac6.engine.cast = nil
prac6.engine.n = 6
prac6.engine.events[5] = { t = 1004.3, kind = "cast", spell = "steady", t0 = 1003.2, t1 = 1004.3 }
prac6.engine.events[6] = { t = 1004.8, kind = "auto", delay = 0, windupAt = 1002.9 }
WL:Refresh(Nock.state)
ok(WL.rows[1].w2a:GetText() == "300", "an auto filed after the Steady but wound up before it is the earlier start")
ok(WL.rows[1]:GetScript("OnEnter") == nil, "...and no row tooltip")
prac6.engine.events[6] = nil
prac6.engine.n = 5
WL:Refresh(Nock.state)
ok(WL._anchor == WB.frame, "...docked to the workbench's right edge")
WB:Focus(true)
WL:Refresh(Nock.state)
ok(WL._anchor == CV.frame, "...and to the stage's in Focus")
WB:Focus(false)
-- Out of practice, the live entries WeaveBind publishes -- behind the LIVE
-- flag only: the practice Log button never brings the panel into a raid.
Nock.state.sim.active = false
Nock.state.weave.entries = { { t = 5000, name = "Raptor Strike", a2w = 0.4, w2a = 0.35, total = 0.75 }, { t = 5004, name = "Melee", a2w = 0.5, w2a = 0.6, total = 1.1 } }
Nock.state.weave.entriesN, Nock.state.weave.combatAt = 2, 4990
WL:Refresh(Nock.state)
ok(WL.frame:IsShown() == false, "the practice flag alone shows nothing in a real fight")
Nock.db.profile.weaveLogPanel = true
WL:Refresh(Nock.state)
ok(WL.frame:IsShown() == true and WL.rows[1].tot:GetText() == "1100" and WL.rows[2].tot:GetText() == "750",
   "with the live flag the live weaves show, newest first")
Nock.db.profile.weaveLogPanel = nil
Nock.state.weave.entries = nil
Nock.state.sim.active = true

Nock.db.profile.practiceWeaveLog = nil
Nock.state.sim.fightOn = false

-- 12. Expert mode (2026-08-27): the window and the stage go, the combat log
-- and (on a weave paper) the weave log stay. The log is the record of the
-- fight -- movement, autos, casts, melee, cooldowns -- with no plan on it.
dofile("UI/Frame_PracticeCombatLog.lua")
local CL = Nock:GetModule("PracticeCombatLogView")
CL:OnInitialize(); CL:OnEnable()
Nock.state.sim.active, Nock.state.sim.fightOn = true, false
prac6._replay = nil
prac6.engine = { n = 0, events = {}, t0 = 0, pulled = false, windup = 0.36 }
prac6.PaperWeaves = function() return false end
WB:Open()
ok(WB.frame:IsShown() == true and CL.frame:IsShown() == false, "before Expert: the window is up, the combat log is not")
WB:Expert(true)
ok(WB:IsExpert() == true and CL:IsExpert() == true and WB.frame:IsShown() == false and CL.frame:IsShown() == true,
   "Expert on: the window hides, the combat log shows")
ok(WB:IsFocus() == false and CV:IsFocus() == false, "...and Focus is off")
local clSpecial = false
for i = 1, #_G.UISpecialFrames do if _G.UISpecialFrames[i] == "NockPracticeCombatLog" then clSpecial = true end end
ok(clSpecial, "...and Esc reaches the log (UISpecialFrames)")
-- Never both.
WB:Focus(true)
ok(WB:IsFocus() == true and WB:IsExpert() == false and CL.frame:IsShown() == false, "Focus on turns Expert off")
WB:Expert(true)
ok(WB:IsExpert() == true and WB:IsFocus() == false and CV:IsFocus() == false, "...and Expert on turns Focus off")
-- Stop keeps Expert: the message the fight's own Stop sends is Focus-off.
deliver(WB, "NOCK_PRACTICE_FOCUS")
ok(WB:IsExpert() == true and CL.frame:IsShown() == true, "a Stop (Focus-off) leaves Expert standing")
-- The head is the panel's chip, name and button, painted by the panel.
if okInit then
  PV:PaintStateChip({ fightOn = true, pulled = true, t0 = 990 }, 1000, prac6)
  ok(CL.head.chip.text:GetText() == "FIGHT 0:10" and CL.head.stop.text:GetText() == "STOP", "the log's head wears the panel's chip and STOP")
  PV:PaintStateChip({ fightOn = false, pulled = false }, 1000, prac6)
  ok(CL.head.stop.text:GetText() == "START", "...and START between fights")
end
-- The record: one item per auto / cast / move / melee in the window, zone
-- marks on the MOVE row, second ticks from the pull, no CD row without one.
Nock.state.sim.fightOn, Nock.state.sim.t0 = true, 1000
prac6.engine = { n = 7, t0 = 1000, pulled = true, windup = 0.36, events = {
  { t = 1000, kind = "pull" },
  { t = 1000, kind = "range", zone = "FAR", inMelee = false },
  { t = 1000.36, kind = "auto", delay = 0, windupAt = 1000 },
  { t = 1001.5, kind = "cast", spell = "steady", t0 = 1000.4, t1 = 1001.5 },
  { t = 1001.9, kind = "move", t0 = 1001.5, t1 = 1001.9 },
  { t = 1001.9, kind = "range", zone = "SWEET", inMelee = true },
  { t = 1002, kind = "melee", hit = "r" },
} }
local savedGetTime = _G.GetTime
_G.GetTime = function() return 1003 end
CL:Refresh(Nock.state)
ok(CL.nItems == 4 and CL.nZones == 2 and CL.nWords == 1 and CL.words[1]:GetText() == "Steady",
   "the log draws the auto, the cast, the move and the hit, two zone marks, and the cast's word (" .. CL.nItems .. "/" .. CL.nZones .. "/" .. CL.nWords .. ")")
ok(CL._nRows == 4 and CL.nTicks == 4, "four rows on a fight without cooldowns; second ticks 0..3 s from the pull")
local _, _, _, cx = CL.cursor:GetPoint()
ok(math.abs(cx - (CL.lanes:GetWidth() or 960)) < 1e-6, "live, the cursor is the right edge")
prac6.engine.movingSince = 1002.5
CL:Refresh(Nock.state)
ok(CL.nItems == 5, "...a stretch still being walked is drawn to the cursor")
-- CD row: on once a cooldown lands, and sticky.
prac6.engine.events[8] = { t = 1002.6, kind = "cd", key = "RF", used = true }
prac6.engine.n = 8
CL:Refresh(Nock.state)
ok(CL._nRows == 5, "a cooldown on the stream brings the CD row")
prac6.engine.events[8] = nil
prac6.engine.n = 7
CL:Refresh(Nock.state)
ok(CL._nRows == 5, "...and it stays for the fight")
-- Replay: the cursor sits a quarter in from the right and the whole record stays.
Nock.state.sim.fightOn = false
prac6.engine.movingSince = nil
prac6._replay = { at = 1001, t0 = 1000, t1 = 1003, n = 4, rev = 1, verdicts = {} }
CL:Refresh(Nock.state)
_, _, _, cx = CL.cursor:GetPoint()
ok(math.abs(cx - 0.75 * (CL.lanes:GetWidth() or 960)) < 1e-6 and CL.nItems == 4, "in a replay the cursor is 3/4 across and every item of the record is still drawn")
prac6._replay = nil
_G.GetTime = savedGetTime
-- The weave log in Expert: on a weave paper, flag or no flag, beside the log.
Nock.db.profile.practiceWeaveLog = nil
prac6.PaperWeaves = function() return true end
prac6.grader = { verdicts = {} }
WL._anchor = nil
WL:Refresh(Nock.state)
ok(WL.frame:IsShown() == true and WL._anchor == CL.frame, "Expert: the weave log is up without the Log flag, docked to the combat log")
prac6.PaperWeaves = function() return false end
WL:Refresh(Nock.state)
ok(WL.frame:IsShown() == false, "...and not on a turret paper")
-- Esc on the log during a fight: Stop, then Expert off.
local xStopped = 0
prac6.StopFight = function() xStopped = xStopped + 1 end
Nock.state.sim.fightOn = true
local sentBefore = sent["NOCK_PRACTICE_EXPERT"] or 0
-- (The stub's Hide never runs OnHide, so the flag an earlier own hide set is
-- still up; in the client OnHide consumes it on that very hide.)
CL._hiding = false
CL.frame:Hide(); local clHide = CL.frame:GetScript("OnHide"); if clHide then clHide(CL.frame) end
ok(xStopped == 1 and (sent["NOCK_PRACTICE_EXPERT"] or 0) == sentBefore + 1, "Esc on the log during a fight stops it and asks Expert off")
Nock.state.sim.fightOn = false
CL.frame:Show()
-- WORKBENCH (the message, off): the window returns, the log goes.
deliver(WB, "NOCK_PRACTICE_EXPERT")
ok(WB:IsExpert() == false and CL:IsExpert() == false and WB.frame:IsShown() == true and CL.frame:IsShown() == false, "Expert off: the window returns and the log goes")
clSpecial = false
for i = 1, #_G.UISpecialFrames do if _G.UISpecialFrames[i] == "NockPracticeCombatLog" then clSpecial = true end end
ok(not clSpecial, "...and the log leaves UISpecialFrames")
-- Practice off ends Expert.
WB:Expert(true)
Nock.state.sim.active = false
deliver(WB, "NOCK_PRACTICE_CHANGED")
ok(WB:IsExpert() == false and CL:IsExpert() == false, "practice off ends Expert")
Nock.state.sim.active = true
WB:Open()
-- The replay transport on the log (the stage's, shared): up with the
-- readout while a stopped fight is scrubbed, the frame growing by its row.
WB:Expert(true)
Nock.state.sim.fightOn = false
CL:Refresh(Nock.state)
local hBefore = CL.frame:GetHeight()
prac6._replay = { at = 1001, t0 = 1000, t1 = 1003, n = 4, rev = 1, verdicts = {} }
CL:Refresh(Nock.state)
ok(CL.transport:IsShown() == true and CL.transport.time:GetText() == "1.0s / 3.0s", "a stopped fight puts the transport under the log with its readout")
ok(CL.frame:GetHeight() == hBefore + 30, "...and the frame grows by the transport's row")
-- Play runs the replay clock from the tick.
local atSet = {}
prac6.ReplayAt = function(_, t) atSet[#atSet + 1] = t; prac6._replay.at = t end
CL.transport.play:GetScript("OnClick")()
ok(CL.transport:IsPlaying() == true, "play starts from the transport's button")
_G.GetTime = function() return 1000.5 end
CL:Refresh(Nock.state)
ok(#atSet == 1 and math.abs(atSet[1] - 1001.5) < 1e-6, "...and each tick moves the replay clock by the time passed")
_G.GetTime = savedGetTime
CL.transport["end"]:GetScript("OnClick")()
ok(CL.transport:IsPlaying() == false and prac6._replay.at == 1003, "skip-to-end stops play at the fight's end")
prac6.ReplayAt = nil
prac6._replay = nil
CL:Refresh(Nock.state)
ok(CL.transport:IsShown() == false and CL.frame:GetHeight() == hBefore, "...gone with the replay, the frame back to its height")
-- The scenario picker in the head: the catalog under the name, a click picks.
local pickedName
prac6.SetScenario = function(_, name) pickedName = name end
prac6.LadderDrillName = nil
Nock.db.profile.practiceScenario = "Clean French"
ok(CL.head.nameBtn ~= nil and CL.head.chev ~= nil and CL.pick:IsShown() == false, "a chevron leads the name; the picker starts closed")
ok(CL.head.grip ~= nil and CL.head.grip:GetScript("OnDragStart") ~= nil and select(2, CL.head.chip:GetPoint()) == CL.head.grip, "a grip at the head's left, the chip beside it")
CL:TogglePicker()
ok(CL.pick:IsShown() == true, "a click on the name opens the picker")
local nShown = 0
for i = 1, #CL.pickRows do if CL.pickRows[i]:IsShown() then nShown = nShown + 1 end end
ok(nShown == 5 and CL.pickRows[1].name == nil and CL.pickRows[1].text:GetText() == "PAPER DRILLS" and CL.pickRows[2].name == "5:5:1:1",
   "...listing the catalog: a header per group with items, then its items (" .. nShown .. ")")
ok(CL.pickRows[3].bar:IsShown() == true and CL.pickRows[2].bar:IsShown() == false, "...the current pick marked")
CL.pickRows[2]:GetScript("OnClick")(CL.pickRows[2])
ok(pickedName == "5:5:1:1" and CL.pick:IsShown() == false, "a click on a row picks the scenario and closes the picker")
CL.pickRows[1]:GetScript("OnClick")(CL.pickRows[1])
ok(pickedName == "5:5:1:1", "...a header row picks nothing")
Nock.state.sim.fightOn = true
CL:TogglePicker()
ok(CL.pick:IsShown() == false, "no picker during a fight")
Nock.state.sim.fightOn = false
prac6.SetScenario = nil
-- The efficiencies on the head: live during the fight, the scorecard's after.
prac6.LiveScore = function(_, out) out.autoEff, out.gcdEff = 0.973, 0.884; return out end
prac6.lastScore = nil
Nock.state.sim.fightOn = true
CL:Refresh(Nock.state)
ok(CL.head.eff:GetText() == "auto 97% \194\183 gcd 88%", "during a fight the head reads the live auto / gcd efficiency")
Nock.state.sim.fightOn = false
prac6.lastScore = { autoEff = 0.9, gcdEff = 0.8 }
CL:Refresh(Nock.state)
ok(CL.head.eff:GetText() == "auto 90% \194\183 gcd 80%", "...and the scorecard's after it")
prac6.lastScore, prac6.LiveScore = nil, nil
CL._effA, CL._effG = 1, 1
CL:Refresh(Nock.state)
ok(CL.head.eff:GetText() == "", "...blank with no fight behind it")
-- The buff row (the panel's palette, shared): under the head when the drill
-- lets you pop anything, the lanes moving down by it; gone on a paper drill.
local popped = {}
local procState = "off"
prac6.ProcState = function(_, name) return procState end
prac6.ProcMode = function(_, name, mode) popped[#popped + 1] = name .. ":" .. mode end
prac6.PaperDrill = function() return false end
prac6.CurrentScenario = function() return { } end
prac6.engine = { n = 0, events = {}, t0 = 0, pulled = false, windup = 0.36, procs = { RF = 0 } }
deliver(CL, "NOCK_PRACTICE_CHANGED")
CL:Refresh(Nock.state)
ok(CL.palette ~= nil and CL.palette:Count() == 7 and CL.palette.frame:IsShown() == true, "a free scenario shows the whole buff row under the head (" .. tostring(CL.palette and CL.palette:Count()) .. ")")
local _, _, _, _, ly = CL.lanes:GetPoint()
ok(ly == -(26 + 42), "...and the lanes sit under it")
-- The click cycle: off -> up -> held for the fight -> off; right-click off.
local rfUp = CL.palette.slots[1]:GetScript("OnMouseUp")
rfUp(nil, "LeftButton")
ok(popped[1] == "RF:on", "a click on a tile that is off pops the proc")
procState = "up"; rfUp(nil, "LeftButton")
ok(popped[2] == "RF:perm", "...a second click holds it for the rest of the fight")
procState = "perm"; rfUp(nil, "LeftButton")
ok(popped[3] == "RF:off", "...a third click clears it")
procState = "up"; rfUp(nil, "RightButton")
ok(popped[4] == "RF:off", "a right-click clears it from anywhere")
procState = "held"; rfUp(nil, "LeftButton")
ok(#popped == 4, "a tile the scenario holds answers nothing")
procState = "off"
-- QS: the left button cycles the proc like any tile; the RIGHT button is
-- the roll toggle (the old click).
local rolls = 0
prac6.ToggleQS = function() rolls = rolls + 1 end
local qsUp = CL.palette.slots[6]:GetScript("OnMouseUp")
qsUp(nil, "LeftButton")
ok(popped[5] == "QS:on" and rolls == 0, "QS: a left click pops the proc")
qsUp(nil, "RightButton")
ok(rolls == 1 and #popped == 5, "...and a right click rolls it in or out of the drill")
prac6.ToggleQS = nil
prac6.CurrentScenario = function() return { hold = { RF = true }, qs = false } end
deliver(CL, "NOCK_PRACTICE_CHANGED")
CL:Refresh(Nock.state)
ok(CL.palette:Count() == 5 and CL.palette.order[1].spec.name == "Lust", "a held proc and a pinned roll leave the row (Lust first)")
prac6.PaperDrill = function() return true end
deliver(CL, "NOCK_PRACTICE_CHANGED")
CL:Refresh(Nock.state)
_, _, _, _, ly = CL.lanes:GetPoint()
ok(CL.palette:Count() == 0 and CL.palette.frame:IsShown() == false and ly == -26, "a paper drill has no buff row and the lanes are back under the head")
-- ...until a proc key pops one: that proc's tile shows for the fight (user, 2026-08-27).
prac6._procSeen = { Lust = true }
deliver(CL, "NOCK_PRACTICE_CHANGED")
CL:Refresh(Nock.state)
ok(CL.palette:Count() == 1 and CL.palette.order[1].spec.name == "Lust" and CL.palette.frame:IsShown() == true, "a proc popped by key on a paper drill gets its tile")
prac6._procSeen = nil
deliver(CL, "NOCK_PRACTICE_CHANGED")
CL:Refresh(Nock.state)
ok(CL.palette:Count() == 0, "...and the next fight starts without it")
prac6.PaperDrill, prac6.CurrentScenario, prac6.ProcState, prac6.ProcMode = nil, nil, nil, nil
WB:Expert(false)

print(("workbench: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
