-- Tests/profiler_panel_test.lua
-- Standalone LuaJIT tests for the performance panel's numbers
-- (Modules/Profiler.lua): the pure rate math, the memory attribution the
-- tick feeds it (Record clamps a GC step to zero), and the report builder.
-- Run from the repo root: luajit Tests/profiler_panel_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = { Constants = {}, state = {}, modules = {}, db = { profile = {} } }
local printed = {}
function Nock:NewModule(name)
  local m = { name = name }
  function m:RegisterEvent() end
  function m:RegisterMessage() end
  function m:Print(line) printed[#printed + 1] = line end
  function m:ScheduleRepeatingTimer() return {} end
  function m:ScheduleTimer() return {} end
  function m:CancelTimer() end
  Nock.modules[name] = m
  return m
end
function Nock:GetModule(name) return Nock.modules[name] end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
local t = 1000
_G.GetTime = function() return t end
_G.debugprofilestop = function() return 0 end

dofile("Modules/Profiler.lua")
local P = Nock.modules.Profiler

-- 1. Rates ------------------------------------------------------------------
local all, nock = P.Rates(1000, 100, 1030, 104, 2)
ok(all == 15 and nock == 2, "Rates: cumulative ms over 2 s -> ms/s")
all, nock = P.Rates(nil, nil, 1030, 104, 2)
ok(all == nil and nock == nil, "Rates: no previous sample -> nil")
all, nock = P.Rates(1000, 100, 1030, 104, 0)
ok(all == nil and nock == nil, "Rates: zero window -> nil")
all, nock = P.Rates(1000, 100, 900, 104, 2)
ok(all == 0 and nock == 2, "Rates: a counter reset never reads negative")

-- 2. Record: KB attribution, GC steps clamped ---------------------------------
P:ResetStats()
P:Record("Auras", 0.5, 1.5)
P:Record("Auras", 0.5, -3.0)     -- a GC step inside the window
P:Record("Auras", 0.5, 0.25)
ok(P.stats.Auras.kb == 1.75, "Record: negative heap deltas do not count against the module")
ok(P.stats.Auras.calls == 3 and P.stats.Auras.ms == 1.5, "Record: ms and calls still accumulate")
P:RecordCore(0.2, 0.1)
ok(P.stats["(core-body)"].kb == 0.1, "RecordCore carries the KB")

-- 3. Report: sorted by KB/s, memory line present -------------------------------
t = 1010
P:Record("Warnings", 5, 0.05)
local text = P:BuildReport()
ok(text:find("measured garbage", 1, true) ~= nil, "report carries the garbage rate")
ok(text:find("KB/s", 1, true) ~= nil, "report has the KB/s column")
local a, w = text:find("Auras", 1, true), text:find("Warnings", 1, true)
ok(a and w and a < w, "report sorts by KB/s (Auras above Warnings despite less ms)")

-- 4. Capture toggle: without debugprofilestop the profiler refuses cleanly ------
_G.debugprofilestop = nil
P.active = false
P:ToggleCapture()
ok(P.active == false, "capture refuses when the client has no debugprofilestop")

print(("profiler_panel_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
