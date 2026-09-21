-- Tests/flavor_test.lua
-- Nock.Flavor: Forever detection from the toc number, secret-safe Plain(), and
-- the HudMode override. Run from the repo root: luajit Tests/flavor_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local function boot(toc, secretFn)
  local Nock = {}
  _G.LibStub = function() return { GetAddon = function() return Nock end } end
  -- Six returns like the 12.x client (localizedVersion, buildType follow the
  -- toc number): a bare select(4, ...) would hand the 5th to tonumber as a base.
  _G.GetBuildInfo = function() return "1.60.1", "69913", "Sep 21 2026", toc, "1.60.1", "Beta" end
  _G.issecretvalue = secretFn
  _G.GetRangedHaste = function() return 0 end
  dofile("Core/Flavor.lua")
  return Nock
end

-- Forever: 16001
local N = boot(16001, function(v) return v == "SECRET" end)
ok(N.Flavor.forever == true, "16001 is Forever")
ok(N.Flavor.toc == 16001, "toc stored")
ok(N.Flavor.Plain(5) == 5, "Plain passes a plain number")
ok(N.Flavor.Plain("SECRET") == nil, "Plain hides a secret")
ok(N.Flavor.PlainNumber("SECRET", 100) == 100, "PlainNumber falls back on a secret")
ok(N.Flavor.PlainNumber(nil, 7) == 7, "PlainNumber falls back on nil")
ok(N.Flavor.PlainNumber(3, 7) == 3, "PlainNumber passes a number")
ok(N.Flavor.HudLabel() == "Nock HUD", "Forever HUD label")

-- Anniversary: 20506, no issecretvalue
local A = boot(20506, nil)
ok(A.Flavor.forever == false, "20506 is not Forever")
ok(A.Flavor.Plain("anything") == "anything", "Plain is identity without issecretvalue")
ok(A.Flavor.HudLabel() == "React Cluster", "TBC HUD label")

-- HudMode override: State.lua reads Flavor.
local S = boot(16001, nil)
S.db = { profile = { hudMode = "classic" } }
dofile("Core/State.lua")
ok(S.HudMode() == "react", "Forever forces react even if the profile says classic")
ok(S.HudIsReact() == true and S.HudIsClassic() == false, "predicates follow the override")
local T = boot(20506, nil)
T.db = { profile = { hudMode = "classic" } }
dofile("Core/State.lua")
ok(T.HudMode() == "classic", "TBC keeps the profile value")

print(("flavor: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
