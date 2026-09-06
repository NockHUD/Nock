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
Nock.db.profile.qolNoGlow = true
QoL:ApplyGlow()
ok(cvars.ffxGlow == "0", "glow: on writes ffxGlow 0")
QoL.SetNoGlow(false)
ok(cvars.ffxGlow == "1" and Nock.db.profile.qolNoGlow == false, "glow: switching off restores ffxGlow 1")
QoL.SetNoGlow(true)
ok(cvars.ffxGlow == "0" and Nock.db.profile.qolNoGlow == true, "glow: switching on writes 0 at once")

print(("qol_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
