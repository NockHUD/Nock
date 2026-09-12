-- Config/OptionsAdvanced.lua
-- Which settings are Advanced (hidden in Simple): key patterns everywhere, whole groups, and per-page keys; applied onto the built options table.
local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local A = {}
Nock.OptionsAdvanced = A

-- A control whose KEY matches one of these is advanced on every page (colours,
-- opacities, textures, fonts, sizes, per-bar directions, sounds, previews).
A.PATTERNS = {
  "Color$", "Color[A-Z]", "Opacity$", "Texture$", "Font$", "FontSize$", "Height$", "Width$", "Size$",
  "Border$", "Offset$", "Padding$", "Preview$", "Dir[A-Z]%w*$", "^swingFillDirection.",
  "^media_", "^th_%w*[Ss]ize$",
}
-- ...except these headline numbers, which stay in Simple.
A.KEEP = {
  scale = true, reactScale = true, fluffyScale = true, reactWidth = true, fluffyWidth = true,
  iconSize = true, warningIconSize = true, helpersIconSize = true, helpersScale = true,
  practiceScale = true,
}
-- Whole groups (a card or a tab): every row inside is advanced.
A.GROUPS = {
  "hud.classic.layout.grpScaling", "hud.classic.rotation.grpEngine", "hud.classic.rotation.rotationLabelsGroup",
  "hud.classic.background", "hud.react.tabBars.grpEngine", "hud.react.tabSkin",
  "hud.fluffy.tabBars.grpEngine", "hud.fluffy.tabSkin",
  "utilities.practice.advanced", "utilities.practice.colours",
}
-- Single rows, by dotted args path (family.page.tab.key, or page.key for General).
A.KEYS = {
  -- General
  "general.editGridShow", "general.editGridSnap", "general.editSnapBy", "general.perfPanel",
  "general.grpVisibility.opacityOoc", "general.grpCastBar.castBarNonCombatCasts", "general.grpMedia.fontFace",
  -- Classic HUD
  "hud.classic.rotation.grpShotBars.shotBarsShowHelper",
  "hud.classic.rotation.grpShotBars.shotBarsWindow", "hud.classic.rotation.grpShotBars.shotBarsReverse",
  "hud.classic.swingBars.autoShotBarRotationText", "hud.classic.swingBars.autoShotDelayEnabled",
  "alerts.sounds.deadZone.deadZoneSoundChannel", "alerts.aggro.aggroSoundFile", "alerts.aggro.aggroSpeechText", "alerts.aggro.aggroSoundChannel", "alerts.aggro.aggroPulse",
  "hud.classic.cooldownGrid.activePreview", "hud.classic.cooldownGrid.cooldownActiveFit",
  "hud.classic.buffRow.reactBuffPositional", "hud.classic.castBar.castBarNonCombatCasts",
  -- React HUD
  "hud.react.tabSize.stagePreview", "hud.react.tabSize.reactManaText", "hud.react.tabSize.reactShowAutoShotCast", "hud.react.tabSize.castBarNonCombatCasts",
  "hud.react.tabBars.reactShowClipTicks", "hud.react.tabBars.reactShowDelay", "hud.react.tabBars.reactShowBrackets", "hud.react.tabBars.reactShowGcdDivider",
  "hud.react.tabGrid.reactRangeTint", "hud.react.tabGrid.reactTileDim", "hud.react.tabGrid.reactManaTint", "hud.react.tabGrid.reactActiveFit", "hud.react.tabGrid.activePreview",
  "hud.react.tabBuff.reactBuffPositional",
  -- FluffyHUD
  "hud.fluffy.tabSize.fluffyShowAutoShotCast", "hud.fluffy.tabSize.fluffyManaText", "hud.fluffy.tabSize.fluffyShotWindow", "hud.fluffy.tabSize.castBarNonCombatCasts",
  "hud.fluffy.tabBars.fluffyShowClipTicks", "hud.fluffy.tabBars.showWindupMark", "hud.fluffy.tabBars.fluffyShowDelay", "hud.fluffy.tabBars.fluffyShowBrackets", "hud.fluffy.tabBars.fluffyShowGcdDivider",
  "hud.fluffy.tabGrid.reactRangeTint", "hud.fluffy.tabGrid.reactTileDim", "hud.fluffy.tabGrid.reactManaTint", "hud.fluffy.tabGrid.fluffyActiveFit", "hud.fluffy.tabGrid.activePreview",
  "hud.fluffy.tabBuff.reactBuffPositional",
  -- Alerts
  "alerts.warnings.settings.warningLabelStyle", "alerts.warnings.settings.warningLabelUpper",
  "alerts.helpers.tabSettings.helpersHideWA", "alerts.helpers.tabSettings.helpersHeadline", "alerts.helpers.tabSettings.helpersIconGap",
  -- PvP
  "pvp.pvpMode.pvpAutoWorldFlag", "pvp.pvpMode.pvpCcOnlyAtYou",
  -- Trackers
  "trackers.buffTracker.buffTrackerMissingEffect", "trackers.debuffTracker.debuffTrackerMissingEffect",
  "hud.classic.totemTracker.forceShaman", "trackers.misdirect.debug",
  -- Utilities
  "utilities.weaveBind.weaveLogPanel", "utilities.weaveBind.weaveSnowballGate", "utilities.weaveBind.weaveGateGarment",
  "utilities.weaveBind.weaveGateDirection", "utilities.weaveBind.weaveBindMacroDown", "utilities.weaveBind.weaveBindMacroUp",
  "utilities.tonk.tonkCancelDelay", "utilities.shopping.custom",
  "utilities.practice.general.practiceLatencyMs", "utilities.practice.general.practiceFocusOnStart", "utilities.practice.general.practiceQuietFocus",
  "utilities.practice.general.practiceToast", "utilities.practice.general.practiceToastSec",
  -- System
  "experimental.grpRelease.releaseBarAlways",
}

local function nodeAt(root, path)
  local node = root
  for seg in path:gmatch("[^%.]+") do
    node = node.args and node.args[seg]
    if type(node) ~= "table" then return nil end
  end
  return node
end

local function matches(key)
  if A.KEEP[key] then return false end
  for _, p in ipairs(A.PATTERNS) do if key:find(p) then return true end end
  return false
end

-- Tags go into the walker's side table: AceConfigRegistry's validator
-- rejects any key it does not know on a node (`advanced` included), and it
-- re-validates after every NotifyChange.
local function tag(node)
  local W = Nock.OptionsWalk
  if W then W.SetMeta(node, "advanced", true) end
end

local function walk(node)
  for k, v in pairs(node.args or {}) do
    if type(v) == "table" and v.type then
      if v.type == "group" then walk(v)
      elseif type(k) == "string" and matches(k) then tag(v) end
    end
  end
end

-- Tag the built table. Idempotent; RebuildOptionsArgs calls it again after
-- refilling the dynamic blocks.
function A.Apply(root)
  walk(root)
  for _, p in ipairs(A.GROUPS) do local n = nodeAt(root, p); if n then tag(n) end end
  for _, p in ipairs(A.KEYS) do local n = nodeAt(root, p); if n then tag(n) end end
end

-- True when the node is tagged (either spelling).
function A.IsAdvanced(node)
  local W = Nock.OptionsWalk
  return W and W.IsAdvanced(node) or node.advanced == true
end

-- The explicit paths that do not resolve (a rename or a moved group).
function A.Missing(root)
  local out = {}
  for _, p in ipairs(A.GROUPS) do if not nodeAt(root, p) then out[#out + 1] = p end end
  for _, p in ipairs(A.KEYS) do if not nodeAt(root, p) then out[#out + 1] = p end end
  return out
end

return A
