-- Tests/weavelog_report_test.lua
-- Standalone LuaJIT tests for the weavelog capture buffer + report assembly in
-- Modules/WeaveBind.lua (/nock weavelog report -> copybox). The buffer and the
-- report builder are plain data work, so they run outside WoW.
-- Run from the repo root: luajit Tests/weavelog_report_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- Harness: NewModule hands back a plain table the file decorates. Constants
-- autovivify (file-scope table reads tolerate empty stubs); GetTime is ours.
local mod = {}
local printed = {}
local now = 100
_G.GetTime = function() return now end
local Nock = {
  state = {
    ranged  = { swingDuration = 2.17, windup = 0.365 },
    network = { latencyMs = 31 },
  },
  db = { profile = {} },
  Constants = setmetatable({}, {
    __index = function(t, k) local v = {} rawset(t, k, v) return v end,
  }),
  NewModule = function() return mod end,
  Print = function(_, msg) printed[#printed + 1] = msg end,
}
_G.LibStub = function() return { GetAddon = function() return Nock end } end

dofile("Modules/WeaveBind.lua")

ok(type(mod.Log) == "function", "Log exists")
ok(type(mod.BuildReport) == "function", "BuildReport exists")
ok(type(mod.ShowReport) == "function", "ShowReport exists")
ok(type(mod.LOG_MAX) == "number" and mod.LOG_MAX >= 100, "LOG_MAX is a real cap")

-- 1. No capture armed: Log still prints to chat, buffer stays absent, and the
--    report says there is nothing rather than erroring.
mod:Log("weavelog: orphan line")
ok(printed[#printed] == "weavelog: orphan line", "Log prints to chat")
ok(mod._wvBuf == nil, "no buffer before a session starts")
ok(mod:BuildReport() == nil, "BuildReport: nil with no session")

-- 2. A session buffers stamped copies while chat keeps the raw line.
mod._wvBuf, mod._wvT0 = {}, 100
now = 102.34
mod:Log("weavelog: DOWN #1")
now = 103.5
mod:Log("weavelog: UP   #1")
ok(printed[#printed] == "weavelog: UP   #1", "chat line stays unstamped")
ok(#mod._wvBuf == 2, "both lines buffered")
ok(mod._wvBuf[1]:find("2.3", 1, true) and mod._wvBuf[1]:find("DOWN #1", 1, true),
   "buffered line carries the session-relative stamp")

-- 3. The report: header context + every buffered line, in order.
local rep = mod:BuildReport()
ok(type(rep) == "string", "BuildReport returns text")
ok(rep:find("DOWN #1", 1, true) and rep:find("UP   #1", 1, true), "report holds the lines")
ok(select(2, rep:gsub("\n", "\n")) >= 2, "report is multi-line")
ok(rep:find("2.17", 1, true) and rep:find("31", 1, true),
   "report header names eWS and latency")
ok(rep:find("DOWN #1", 1, true) > rep:find("2.17", 1, true),
   "header sits above the lines")

-- 4. The cap drops the OLDEST lines — the tail of a long session is the part
--    worth pasting.
mod._wvBuf, mod._wvT0 = {}, 100
for i = 1, mod.LOG_MAX + 7 do mod:Log("line " .. i) end
ok(#mod._wvBuf == mod.LOG_MAX, "buffer capped")
ok(mod._wvBuf[1]:find("line 8", 1, true) ~= nil, "oldest lines dropped first")
ok(mod._wvBuf[#mod._wvBuf]:find("line " .. (mod.LOG_MAX + 7), 1, true) ~= nil,
   "newest line kept")

-- 5. An armed-but-empty session reports nil (nothing worth a copybox).
mod._wvBuf, mod._wvT0 = {}, 100
ok(mod:BuildReport() == nil, "BuildReport: nil on an empty session")

print(("weavelog_report: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
