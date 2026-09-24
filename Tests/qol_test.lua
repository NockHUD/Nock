-- Tests/qol_test.lua
-- Standalone LuaJIT tests for Modules/QoL.lua: the grey-item scan, batched selling that stops when the
-- merchant closes, auto repair from own funds only, and the glow CVar applied from the profile.
-- Run from the repo root: luajit Tests/qol_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

--------------------------------------------------------------------------------
-- Minimal WoW surface: five bags of slots { quality, count, price, link }
--------------------------------------------------------------------------------
local bags = {}
local function slot(bag, i, quality, count, price)
  bags[bag] = bags[bag] or {}
  bags[bag][i] = { quality = quality, count = count, price = price, link = ("item:%d"):format(1000 + bag * 100 + i) }
end
_G.C_Container = {
  GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
  GetContainerItemInfo = function(bag, i)
    local s = bags[bag] and bags[bag][i]
    if not s then return nil end
    return { quality = s.quality, stackCount = s.count, hyperlink = s.link, isLocked = false }
  end,
}
local sold = {}
_G.C_Container.UseContainerItem = function(bag, i) sold[#sold + 1] = bag .. ":" .. i; bags[bag][i] = nil end
local priceOf = {}
_G.GetItemInfo = function(link)
  for b, t in pairs(bags) do for i, s in pairs(t) do if s.link == link then return "x", link, s.quality, 1, 1, "", "", 1, "", 1, s.price end end end
  return nil
end
local cvars = {}
_G.SetCVar = function(k, v) cvars[k] = v end
_G.GetCVar = function(k) return cvars[k] end
local money, repairCost, canRepair, repaired = 0, 0, false, 0
_G.GetMoney = function() return money end
_G.CanMerchantRepair = function() return canRepair end
_G.GetRepairAllCost = function() return repairCost, repairCost > 0 end
_G.RepairAllItems = function() repaired = repaired + 1 end
_G.GetCoinTextureString = nil

--------------------------------------------------------------------------------
-- Addon stubs: timers run when the test says so
--------------------------------------------------------------------------------
local Nock = { db = { profile = {} } }
local QoL, timers, prints = nil, {}, {}
function Nock:NewModule()
  QoL = {}
  function QoL:RegisterEvent() end
  function QoL:UnregisterEvent() end
  function QoL:Print(s) prints[#prints + 1] = s end
  function QoL:ScheduleTimer(fn, delay, ...) timers[#timers + 1] = { fn = fn, args = { ... } }; return #timers end
  function QoL:CancelTimer(id) timers[id] = false end
  return QoL
end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Modules/QoL.lua")
ok(type(QoL) == "table" and type(QoL.ScanGreys) == "function", "module loads and exposes the scan")

local function runTimers()
  local n = 0
  while true do
    local id, t = next(timers)
    local ran = false
    for i = 1, #timers do
      local tm = timers[i]
      if tm then timers[i] = false; ran = true; n = n + 1; if type(tm.fn) == "string" then QoL[tm.fn](QoL, unpack(tm.args)) else tm.fn(unpack(tm.args)) end end
    end
    if not ran then break end
  end
  return n
end
local function reset()
  bags, sold, timers, prints, cvars = {}, {}, {}, {}, {}
  money, repairCost, canRepair, repaired = 0, 0, false, 0
  Nock.db.profile = {}
end

--------------------------------------------------------------------------------
-- 1. Grey scan: poor quality only, value = price x count
--------------------------------------------------------------------------------
reset()
slot(0, 1, 0, 3, 10); slot(0, 2, 1, 1, 500); slot(1, 1, 0, 1, 7); slot(1, 2, 2, 1, 900)
local greys = QoL.ScanGreys()
ok(#greys == 2, "scan: two greys of four items (" .. #greys .. ")")
local total = 0
for _, g in ipairs(greys) do total = total + g.value end
ok(total == 37, "scan: value is price x count (" .. total .. ")")

--------------------------------------------------------------------------------
-- 2. Selling: off by default; on, batched, prints the total, stops on close
--------------------------------------------------------------------------------
reset()
slot(0, 1, 0, 1, 10)
QoL:MERCHANT_SHOW()
runTimers()
ok(#sold == 0, "sell: off by default sells nothing")

reset()
Nock.db.profile.qolSellGreys = true
for i = 1, 20 do slot(0, i, 0, 1, 1) end
QoL:MERCHANT_SHOW()
ok(#sold > 0 and #sold < 20, "sell: the first batch sells some, not all (" .. #sold .. ")")
runTimers()
ok(#sold == 20, "sell: later batches finish the bags (" .. #sold .. ")")
ok(#prints == 1 and prints[1]:find("20", 1, true) ~= nil, "sell: one summary line names the total")

reset()
Nock.db.profile.qolSellGreys = true
for i = 1, 20 do slot(0, i, 0, 1, 1) end
QoL:MERCHANT_SHOW()
local first = #sold
QoL:MERCHANT_CLOSED()
runTimers()
ok(#sold == first, "sell: closing the window stops the remaining batches")

--------------------------------------------------------------------------------
-- 3. Repair: only when on, the vendor repairs, there is a cost and the money
--------------------------------------------------------------------------------
reset()
canRepair, repairCost, money = true, 500, 10000
QoL:MERCHANT_SHOW()
ok(repaired == 0, "repair: off by default")
Nock.db.profile.qolAutoRepair = true
QoL:MERCHANT_SHOW()
ok(repaired == 1 and #prints == 1, "repair: repairs once and prints the cost")
reset(); Nock.db.profile.qolAutoRepair = true; canRepair, repairCost, money = true, 500, 100
QoL:MERCHANT_SHOW()
ok(repaired == 0 and #prints == 1, "repair: too poor -> no repair, one note")
reset(); Nock.db.profile.qolAutoRepair = true; canRepair, repairCost, money = false, 500, 10000
QoL:MERCHANT_SHOW()
ok(repaired == 0 and #prints == 0, "repair: a vendor that cannot repair is left alone")
reset(); Nock.db.profile.qolAutoRepair = true; canRepair, repairCost, money = true, 0, 10000
QoL:MERCHANT_SHOW()
ok(repaired == 0 and #prints == 0, "repair: nothing to repair is silent")

--------------------------------------------------------------------------------
-- 4. Glow: applied from the profile, restored when switched off
--------------------------------------------------------------------------------
reset()
QoL:ApplyGlow()
ok(cvars.ffxGlow == nil, "glow: off leaves the CVar alone at login")
-- Camera & world quick toggles (Utilities -> Quality of life): live on the
-- client's CVars, nothing in the profile. Pure helpers over the cvar table.
do
  local Q = Nock.QoLCvar
  ok(type(Q) == "table" and Q.FOG == "volumeFog" and Q.CAMERA == "cameraSmoothStyle" and Q.ZOOM == "cameraDistanceMaxZoomFactor", "the three cvars by name")
  cvars.volumeFog = "1"
  ok(Q.GetBool(Q.FOG) == true, "fog on reads true")
  Q.SetBool(Q.FOG, false)
  ok(cvars.volumeFog == "0" and Q.GetBool(Q.FOG) == false, "fog off writes 0")
  cvars.cameraSmoothStyle = "4"
  ok(Q.GetChoice(Q.CAMERA, Q.CAMERA_STYLES) == "4", "camera style reads the client's value")
  cvars.cameraSmoothStyle = "7"
  ok(Q.GetChoice(Q.CAMERA, Q.CAMERA_STYLES) == "4", "an unknown camera value shows the client default")
  Q.SetChoice(Q.CAMERA, "0")
  ok(cvars.cameraSmoothStyle == "0", "camera style writes the chosen value")
  ok(Q.CAMERA_STYLES["0"] and Q.CAMERA_STYLES["1"] and Q.CAMERA_STYLES["2"] and Q.CAMERA_STYLES["4"] and #Q.CAMERA_ORDER == 4, "the four following styles")
  cvars.cameraDistanceMaxZoomFactor = "1.9"
  ok(Q.GetNumber(Q.ZOOM, 1.9) == 1.9, "zoom factor reads")
  Q.SetNumber(Q.ZOOM, 2.6)
  ok(cvars.cameraDistanceMaxZoomFactor == "2.6", "zoom factor writes")
  Q.SetNumber(Q.ZOOM, 2.3456)
  ok(cvars.cameraDistanceMaxZoomFactor == "2.3", "zoom factor written to one decimal")
  cvars.cameraDistanceMaxZoomFactor = "junk"
  ok(Q.GetNumber(Q.ZOOM, 1.9) == 1.9, "an unreadable zoom shows the fallback")
  ok(Q.ZOOM_NEAR == 1.9 and Q.ZOOM_FAR == 2.6, "the two presets: Blizzard's default and the far cap")
end

Nock.db.profile.qolNoGlow = true
QoL:ApplyGlow()
ok(cvars.ffxGlow == "0", "glow: on writes ffxGlow 0")
QoL.SetNoGlow(false)
ok(cvars.ffxGlow == "1" and Nock.db.profile.qolNoGlow == false, "glow: switching off restores ffxGlow 1")
QoL.SetNoGlow(true)
ok(cvars.ffxGlow == "0" and Nock.db.profile.qolNoGlow == true, "glow: switching on writes 0 at once")

--------------------------------------------------------------------------------
-- 5. Error text (Forever only): the red UIErrorsFrame text off while
--    qolHideErrors is on; handed back only if Nock took it. Speech is a CVar.
--------------------------------------------------------------------------------
do
  local registered = { UI_ERROR_MESSAGE = true, UI_INFO_MESSAGE = true }
  _G.UIErrorsFrame = {
    RegisterEvent = function(_, ev) registered[ev] = true end,
    UnregisterEvent = function(_, ev) registered[ev] = nil end,
    IsEventRegistered = function(_, ev) return registered[ev] == true end,
  }
  Nock.Flavor = { forever = false }
  Nock.db.profile = { qolHideErrors = true }
  QoL:ApplyErrors()
  ok(registered.UI_ERROR_MESSAGE, "errors: TBC leaves the frame alone even with the flag on")
  Nock.Flavor.forever = true
  QoL:ApplyErrors()
  ok(not registered.UI_ERROR_MESSAGE and registered.UI_INFO_MESSAGE, "errors: on hides the red text, keeps the yellow info text")
  QoL:ApplyErrors()
  ok(not registered.UI_ERROR_MESSAGE, "errors: applying twice is harmless")
  QoL.SetHideErrors(false)
  ok(registered.UI_ERROR_MESSAGE and Nock.db.profile.qolHideErrors == false, "errors: off hands the event back")
  -- Someone else took the event: off must not re-register it behind their back.
  registered.UI_ERROR_MESSAGE = nil
  QoL:ApplyErrors()
  ok(not registered.UI_ERROR_MESSAGE, "errors: off never re-registers an event Nock did not take")
  registered.UI_ERROR_MESSAGE = true
  QoL.SetHideErrors(true)
  ok(not registered.UI_ERROR_MESSAGE and Nock.db.profile.qolHideErrors == true, "errors: switching on hides at once")
  QoL.SetHideErrors(false)
  local Q = Nock.QoLCvar
  ok(Q.SPEECH == "Sound_EnableErrorSpeech", "speech cvar by name")
  cvars.Sound_EnableErrorSpeech = "1"
  Q.SetBool(Q.SPEECH, false)
  ok(cvars.Sound_EnableErrorSpeech == "0", "speech: mute writes 0")
  _G.UIErrorsFrame = nil
  Nock.db.profile.qolHideErrors = true
  QoL:ApplyErrors()
  ok(true, "errors: no UIErrorsFrame is not an error")
  Nock.Flavor = nil
end

print(("qol_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
