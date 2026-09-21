-- Tests/options_forever_test.lua
-- Config/OptionsForever.lua prunes the built options tree to what runs on WoW
-- Forever: General, the React page as "Nock HUD", Profiles; every TBC-only
-- family, tab and row is gone. Run from the repo root: luajit Tests/options_forever_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local h = dofile("Tests/lib/options_harness.lua")
local Nock, W, opts = h()
dofile("Config/OptionsForever.lua")
ok(type(Nock.OptionsForever) == "function" or type(Nock.OptionsForever) == "table", "OptionsForever registered")
local F = Nock.OptionsForever

local function nodeAt(root, path)
  local n = root
  for seg in path:gmatch("[^%.]+") do n = n.args and n.args[seg]; if type(n) ~= "table" then return nil end end
  return n
end

-- Before: the TBC tree is whole.
ok(nodeAt(opts, "hud.classic") and nodeAt(opts, "utilities.practice") and nodeAt(opts, "hud.react.tabGrid"), "harness built the full TBC tree")

F.Apply(opts)

-- Families.
local top = {}
for k, v in pairs(opts.args) do if type(v) == "table" and v.type == "group" then top[#top + 1] = k end end
table.sort(top)
ok(table.concat(top, ",") == "alerts,general,hud,profiles", "alerts/general/hud/profiles remain, got " .. table.concat(top, ","))
ok(nodeAt(opts, "alerts.aggro") ~= nil, "aggro page kept")
for _, p in ipairs({ "alerts.helpers", "alerts.sounds", "alerts.warnings" }) do ok(nodeAt(opts, p) == nil, p .. " gone") end

-- HUD: React only, renamed.
ok(nodeAt(opts, "hud.react") ~= nil, "react page kept")
ok(nodeAt(opts, "hud.classic") == nil and nodeAt(opts, "hud.fluffy") == nil, "classic and fluffy pages gone")
ok(nodeAt(opts, "hud.react").name == "Nock HUD", "react page renamed to Nock HUD")
ok(nodeAt(opts, "hud.hudMode") == nil and nodeAt(opts, "hud.react.hudMode") == nil and nodeAt(opts, "hud.react.useLook") == nil, "hud mode switches gone")

-- Tabs without a module or a feed in M1.
for _, p in ipairs({ "hud.react.tabBuff", "hud.react.tabRange", "hud.react.tabBars.grpEngine" }) do
  ok(nodeAt(opts, p) == nil, p .. " gone")
end
for _, p in ipairs({ "hud.react.tabBars", "hud.react.tabSize", "hud.react.tabSkin", "hud.react.tabGrid" }) do
  ok(nodeAt(opts, p) ~= nil, p .. " kept")
end

-- Rows without a feed on Forever.
for _, p in ipairs({
  "hud.react.tabBars.reactShowBrackets", "hud.react.tabBars.reactShowClipTicks", "hud.react.tabBars.reactShowDelay",
  "hud.react.tabBars.reactShowGcdDivider", "hud.react.tabBars.reactShowNotation",
  "hud.react.tabSize.reactShowAutoShotCast",
  "hud.react.tabSize.reactMeleeStageCue",
  "hud.react.tabSkin.reactColorTickSteady", "hud.react.tabSkin.reactColorBracket", "hud.react.tabSkin.reactGcdDividerWidth",
  "general.grpCastBar", "general.grpSetup", "general.grpLook", "general.runWizard", "general.runWizardGuided", "general.perfPanel",
}) do
  ok(nodeAt(opts, p) == nil, p .. " gone")
end
for _, p in ipairs({
  "hud.react.tabBars.reactDirAuto", "hud.react.tabBars.reactDirMelee",
  "hud.react.tabSize.reactShowAutoBar", "hud.react.tabSize.reactShowMeleeBar", "hud.react.tabSize.reactShowManaBar",
  "hud.react.tabSize.reactScale", "hud.react.tabSize.reactWidth", "hud.react.tabSize.order_up_1",
  "hud.react.tabSize.reactShowCastBar", "hud.react.tabSize.castBarCard", "hud.react.tabSize.reactShowGrid",
  "hud.react.tabSkin.reactCastH", "hud.react.tabSkin.reactColorCastFill",
  "hud.react.tabSize.reactShowRangeBar", "hud.react.tabSize.reactShowAspectIcon", "hud.react.tabSize.reactShowMarkIcon",
  "hud.react.tabSize.cornersCard", "hud.react.tabSkin.reactCornerIconSize", "hud.react.tabSkin.reactColorRangeSweet",
  "hud.react.tabSize.reactManaTick", "hud.react.tabSize.reactManaTickDirCombat",
  "hud.react.tabSkin.reactAutoH", "hud.react.tabSkin.reactColorAutoFill", "hud.react.tabSkin.reactFont", "hud.react.tabSkin.reactBarTexture",
  "general.scale", "general.lockAll", "general.minimapIcon", "general.grpMedia", "general.grpVisibility", "general.editGridShow",
  "profiles.stock", "profiles.sharing",
}) do
  ok(nodeAt(opts, p) ~= nil, p .. " kept")
end

-- Idempotent: a second Apply (RebuildOptionsArgs re-applies) changes nothing.
local before = 0
local function count(n) local c = 0; for _, v in pairs(n.args or {}) do if type(v) == "table" then c = c + 1 + count(v) end end; return c end
before = count(opts)
F.Apply(opts)
ok(count(opts) == before, "second Apply is a no-op")

-- The hook is wired in both registration paths and only the Camelot toc loads the file.
local function readAll(p) local f = io.open(p, "rb"); local s = f:read("*a"); f:close(); return s end
local src = readAll("Config/Options.lua")
local _, hooks = src:gsub("OptionsForever%.Apply", "")
ok(hooks == 2, "Options.lua applies OptionsForever in RegisterOptions and RebuildOptionsArgs (found " .. hooks .. ")")
ok(readAll("Nock_Camelot.toc"):find("Config\\OptionsForever.lua", 1, true) ~= nil, "Camelot toc lists OptionsForever")
ok(readAll("Nock.toc"):find("OptionsForever", 1, true) == nil, "TBC toc does not list OptionsForever")

print(("options_forever: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
