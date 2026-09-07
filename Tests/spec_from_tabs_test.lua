-- Tests/spec_from_tabs_test.lua
-- Standalone LuaJIT tests for Nock.SpecFromTabs (Core/State.lua): the talent-tab
-- majority that state.player.spec carries and Rotations/Profiles.lua reads to
-- keep the Survival-only 5:4:1:1 off a Beast Master's label.
-- Run from the repo root: luajit Tests/spec_from_tabs_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = {}
_G.GetRangedHaste = function() return 0 end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")

-- GetTalentTabInfo's shape on the Anniversary client: the 5th return is the
-- points spent (the read Modules/Cooldowns.lua's Spec row makes).
local function tabs(a, b, c)
  local pts = { a, b, c }
  return function(i) return "tab" .. i, "icon", nil, nil, pts[i] end
end

ok(Nock.state.player.spec == nil, "state.player.spec starts nil (not read yet)")
ok(Nock.SpecFromTabs(nil) == nil, "no API: nil")
ok(Nock.SpecFromTabs(tabs(0, 0, 0)) == nil, "no points anywhere: nil")
ok(Nock.SpecFromTabs(tabs(41, 20, 0)) == "BM", "41/20/0 is BM")
ok(Nock.SpecFromTabs(tabs(0, 20, 41)) == "SV", "0/20/41 is SV")
ok(Nock.SpecFromTabs(tabs(20, 41, 0)) == "MM", "20/41/0 is MM")
ok(Nock.SpecFromTabs(tabs(5, 5, 51)) == "SV", "a deep SV build is SV")
ok(Nock.SpecFromTabs(tabs(30, 0, 31)) == "SV", "the most-pointed tab wins, not the first")
ok(Nock.SpecFromTabs(tabs(30, 0, 30)) == "BM", "a tie goes to the earlier tab")
ok(Nock.SpecFromTabs(function() return nil end) == nil, "a tab reader that returns nothing: nil")
ok(Nock.SpecFromTabs(function() error("boom") end) == nil, "a tab reader that throws: nil, no error")

print(string.format("spec_from_tabs: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
