-- Tests/forever_events_test.lua
-- Every event a Forever-listed file registers exists on the Forever client
-- (AceEvent hard-errors on an unknown event). Source: docs/forever/dumps/16001/Events.lua.
-- Run from the repo root: luajit Tests/forever_events_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local function readAll(path) local f = io.open(path, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end

local dump = readAll("docs/forever/dumps/16001/Events.lua")
if not dump then print("SKIP: devkit dump not present (docs/forever is local-only)"); os.exit(0) end
local known = {}
for name in dump:gmatch('"([A-Z0-9_]+)"') do known[name] = true end
ok(known["PLAYER_SWING"] and known["ADDON_RESTRICTION_STATE_CHANGED"], "dump parsed")

local toc = readAll("Nock_Camelot.toc")
for line in toc:gmatch("[^\r\n]+") do
  local entry = line:match("^%s*([^#%s][^%s%[]*)")
  if entry and entry:match("%.lua$") then
    local f = entry:gsub("\\", "/")
    local src = readAll(f)
    if src then
      for ev in src:gmatch('Register%a*Event%(%s*"([A-Z0-9_]+)"') do
        ok(known[ev], ("%s registers unknown event %s"):format(f, ev))
      end
    end
  end
end
print(("forever_events: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
