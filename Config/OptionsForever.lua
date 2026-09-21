-- Config/OptionsForever.lua
-- WoW Forever allowlist for the settings tree: keeps General, the React page
-- (as "Nock HUD") and Profiles, and drops every family, tab and row whose
-- module or feed does not exist on Forever. Loaded by Nock_Camelot.toc only.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local F = {}
Nock.OptionsForever = F

-- Top-level families that survive. Everything else at the root goes.
F.FAMILIES = { general = true, hud = true, profiles = true }

-- Dotted args paths removed inside the surviving families. A trailing `*`
-- matches every key with that prefix (same convention as OptionsLayout rows).
-- Each entry names the module or feed that is missing on Forever in M1.
F.DROP = {
  -- HUD family: one HUD only, no mode switching.
  "hud.classic", "hud.fluffy", "hud.hudMode", "hud.react.hudMode", "hud.react.useLook",
  -- React bars: no clip model (no wind-up feed, haste secret in combat), no papers.
  "hud.react.tabBars.grpEngine",
  "hud.react.tabBars.reactShowBrackets", "hud.react.tabBars.reactShowClipTicks", "hud.react.tabBars.reactShowDelay",
  "hud.react.tabBars.reactShowGcdDivider", "hud.react.tabBars.reactShowNotation",
  -- Tabs whose module lands in M3 (buff row, range finder). The cooldown
  -- grid and the cast bar came back with M2 (Forever/Cooldowns.lua,
  -- Forever/CastBar.lua).
  "hud.react.tabBuff", "hud.react.tabRange",
  -- Size & Elements: Auto Shot wind-up (no feed), corners, range bar, weave
  -- stage, mana tick (M3).
  "hud.react.tabSize.reactShowAutoShotCast",
  "hud.react.tabSize.cornersCard", "hud.react.tabSize.reactShowAspectIcon", "hud.react.tabSize.reactShowMarkIcon",
  "hud.react.tabSize.reactShowRangeBar",
  "hud.react.tabSize.reactMeleeStageCue", "hud.react.tabSize.stagePre*",
  "hud.react.tabSize.reactManaTick*",
  -- Skin: marks, brackets, GCD divider, cast bar, corners, range colours.
  "hud.react.tabSkin.autoMarksHeader", "hud.react.tabSkin.reactBracketWidth", "hud.react.tabSkin.reactColorBracket",
  "hud.react.tabSkin.reactColorGcdDivider", "hud.react.tabSkin.reactGcdDividerWidth",
  "hud.react.tabSkin.reactColorTick*",
  "hud.react.tabSkin.reactCornerIcon*", "hud.react.tabSkin.rangeColoursCard", "hud.react.tabSkin.reactColorRange*",
  -- General: no cast bar, no setup check, no HUD-mode look, no wizard, no profiler.
  "general.grpCastBar", "general.grpSetup", "general.grpLook",
  "general.runWizard", "general.runWizardGuided", "general.perfPanel",
}

F.RENAME = {
  ["hud.react"] = "Nock HUD",
}

local function nodeAt(root, path)
  local node = root
  for seg in path:gmatch("[^%.]+") do
    node = node.args and node.args[seg]
    if type(node) ~= "table" then return nil end
  end
  return node
end

local function dropPath(root, path)
  local parentPath, key = path:match("^(.*)%.([^%.]+)$")
  local parent = parentPath and nodeAt(root, parentPath) or root
  if not (parent and parent.args) then return end
  local prefix = key:match("^(.-)%*$")
  if prefix then
    for k in pairs(parent.args) do
      if type(k) == "string" and k:sub(1, #prefix) == prefix then parent.args[k] = nil end
    end
  else
    parent.args[key] = nil
  end
end

function F.Apply(root)
  if type(root) ~= "table" or type(root.args) ~= "table" then return end
  for k, v in pairs(root.args) do
    if type(v) == "table" and v.type == "group" and not F.FAMILIES[k] then root.args[k] = nil end
  end
  for _, path in ipairs(F.DROP) do dropPath(root, path) end
  for path, name in pairs(F.RENAME) do
    local n = nodeAt(root, path)
    if n then n.name = name end
  end
end
