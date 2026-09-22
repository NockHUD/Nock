-- Tests/forever_defaults_test.lua
-- Config/Defaults.lua: the Forever-only default overrides apply with the
-- Forever flag and never without it.
-- Run from the repo root: luajit Tests/forever_defaults_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local function load(forever)
  local Nock = { Flavor = { forever = forever }, Constants = setmetatable({}, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }) }
  _G.LibStub = function() return { GetAddon = function() return Nock end } end
  dofile("Config/Defaults.lua")
  return Nock.Defaults.profile
end
local tbc = load(false)
ok(tbc.warningLabelFont == "Friz Quadrata TT" and tbc.warningLabelStyle == "THICKOUTLINE", "TBC: the stock warning label font")
local fv = load(true)
ok(fv.warningLabelFont == "Nock Plex Sans SemiBold" and fv.warningLabelStyle == "THICKOUTLINE", "Forever: the HUD's own face for the warning labels")
ok(fv.warnPetDeadEnabled == true and fv.warnPetMissingEnabled == true and fv.warnPetUnhappyEnabled == true, "Forever warning toggles default on")
print(("forever_defaults: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
