-- Tests/wizard_frames_test.lua
-- Static contract for the guided wizard: every nudgeable frame registers a key
-- the page script can name, and consults the keyed readings instead of the
-- bare lock for its edit affordances. Reads the sources as text.
-- Run from the repo root: luajit Tests/wizard_frames_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function read(path)
  local f = assert(io.open(path, "rb")); local t = f:read("*a"); f:close(); return t
end

local KEYED = {
  ["UI/HUD.lua"] = "hud", ["UI/Frame_CastBar.lua"] = "castbar", ["UI/Frame_ReactCorners.lua"] = "react.corners",
  ["UI/Frame_ReactBuffs.lua"] = "react.buffs", ["UI/Frame_Warnings.lua"] = "warnings",
  ["UI/Frame_BossBanner.lua"] = "bossbanner", ["UI/Frame_AggroWarning.lua"] = "aggro",
  ["UI/Frame_Misdirect.lua"] = "misdirect", ["UI/Frame_DebuffTracker.lua"] = "debuffs",
  ["UI/Frame_TonkDial.lua"] = "tonkdial", ["UI/Frame_Helpers.lua"] = "helpers",
  ["UI/Frame_ConsumeBanner.lua"] = "consume", ["UI/Frame_PvPBadge.lua"] = "pvpbadge",
  ["UI/Frame_RipperCountdown.lua"] = "ripper", ["UI/Frame_ShoppingList.lua"] = "shopping",
  ["UI/Frame_SlammerButton.lua"] = "slammer",
}
for path, key in pairs(KEYED) do
  local src = read(path)
  ok(src:find('key%s*=%s*"' .. key:gsub("%.", "%%.") .. '"'), path .. " registers key " .. key)
  ok(src:find("WizardHides%(") ~= nil, path .. " consults WizardHides")
  ok(src:find("IsLockedFor%(") ~= nil or src:find("EditPreview%(") ~= nil, path .. " uses a keyed lock reading")
end
ok(read("UI/Frame_BuffTracker.lua"):find('"buffs%."'), "buff tracker keys buffs.<panel>")
ok(read("UI/Widgets.lua"):find("key%s*=%s*key:lower%(%)"), "free panels key by their panel name")

-- No frame keeps a bare-lock edit affordance: EnableMouse(not Nock.IsLocked()) is gone.
for path in pairs(KEYED) do
  ok(not read(path):find("EnableMouse%(not Nock%.IsLocked%(%)%)"), path .. " no bare EnableMouse(not IsLocked())")
end

print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
