-- Tests/profiles_display_test.lua
-- Standalone LuaJIT tests for the render-edge companions in
-- Rotations/Profiles.lua: DisplayName (the user's rename map, pre-existing)
-- and DisplayColor (the user's per-notation color map). Both key on the
-- BUILT-IN notation string, never the display name.
-- Run from the repo root: luajit Tests/profiles_display_test.lua

local addon = {}
_G.LibStub = function() return { GetAddon = function() return addon end } end

dofile("Rotations/Profiles.lua")
local P = addon.Profiles

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

--------------------------------------------------------------------------------
-- DisplayName (rename map)
--------------------------------------------------------------------------------
addon.db = { profile = {} }
ok(P:DisplayName("5:5:1:1") == "5:5:1:1", "no map: built-in name passes through")
addon.db.profile.rotationLabels = { ["5:5:1:1"] = "French", ["2:2 1w"] = "" }
ok(P:DisplayName("5:5:1:1") == "French",  "a rename applies")
ok(P:DisplayName("2:2 1w")  == "2:2 1w",  "a blank rename means built-in")
ok(P:DisplayName("1:1")     == "1:1",     "an unrenamed notation passes through")
ok(P:DisplayName(nil)       == nil,       "nil notation stays nil")

--------------------------------------------------------------------------------
-- DisplayColor (per-notation color map)
--------------------------------------------------------------------------------
ok(type(P.DisplayColor) == "function", "Profiles:DisplayColor exists")
ok(P:DisplayColor("5:5:1:1") == nil, "no color map: nil (site default)")

addon.db.profile.rotationLabelColors = {
  ["5:5:1:1"] = { 0.0, 0.8, 0.8, 1.0 },   -- the teal "French"
  ["1:1"]     = { 1.0, 0.5, 0.0 },        -- alpha omitted
  ["2:3"]     = "not a table",            -- damaged entry
}
local r, g, b, a = P:DisplayColor("5:5:1:1")
ok(r == 0.0 and g == 0.8 and b == 0.8 and a == 1.0, "a stored color returns r,g,b,a")
r, g, b, a = P:DisplayColor("1:1")
ok(r == 1.0 and g == 0.5 and b == 0.0 and a == 1, "missing alpha defaults to 1")
ok(P:DisplayColor("2:3") == nil, "a damaged entry means site default")
ok(P:DisplayColor("5:9:1:1") == nil, "an uncolored notation means site default")
ok(P:DisplayColor(nil) == nil, "nil notation stays nil")

-- Keying is by BUILT-IN notation: the rename above must not redirect the color.
ok(P:DisplayColor("French") == nil, "colors never key on the display name")

print(string.format("profiles_display: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
