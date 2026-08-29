-- Tests/free_layout_test.lua
-- Standalone LuaJIT tests for Nock.FreeLayoutActive in Core/State.lua: the ONE
-- gate for free placement. freeLayout is a Classic-look setting; the React look
-- must always grid (its cluster+grid rows share a -1px seam that free placement
-- would tear apart), so the helper is false whenever hudMode == "react",
-- whatever the flag says.
-- Run from the repo root: luajit Tests/free_layout_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- Minimal WoW/Ace surface, same harness as clip_threshold_test.lua.
local Nock = {}
_G.GetRangedHaste = function() return 0 end
_G.LibStub = function() return { GetAddon = function() return Nock end } end

dofile("Core/State.lua")

ok(type(Nock.FreeLayoutActive) == "function", "FreeLayoutActive exists")

local function with(profile)
  Nock.db = profile and { profile = profile } or nil
  return Nock.FreeLayoutActive()
end

-- Classic look: the flag decides.
ok(with({ freeLayout = true }) == true,
   "classic (hudMode absent): flag on -> active")
ok(with({ freeLayout = true, hudMode = "classic" }) == true,
   "classic (explicit): flag on -> active")
ok(with({ freeLayout = false }) == false,
   "classic: flag off -> inactive")
ok(with({}) == false,
   "classic: flag absent -> inactive")

-- React look: never active, even with the flag left on from a Classic session.
ok(with({ freeLayout = true, hudMode = "react" }) == false,
   "react: stale classic flag is ignored")
ok(with({ freeLayout = false, hudMode = "react" }) == false,
   "react: flag off -> inactive")

-- Called before AceDB is up must not throw and must read as inactive.
ok(with(nil) == false, "no profile: inactive, no error")

print(("free_layout: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
