-- Config/Presets.lua
-- Per-page presets: bundles of option paths + values applied through the walker so every set handler runs.
local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local C = Nock.Constants
local P = {}
Nock.Presets = P

local function spellIcon(id)
  return function()
    local fn = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
    return fn and fn(id) or nil
  end
end

-- Warnings: category per catalog key (Modules/Warnings.lua; entries without a
-- category file under "other"), severity red | amber | blue.
local WARN = {
  health = { "you", "red" }, aspect = { "you", "amber" }, dazed = { "you", "amber" }, fdResist = { "you", "red" }, ripper = { "you", "red" }, mana = { "you", "blue" },
  steamTonk = { "pet", "red" }, mendPet = { "pet", "amber" }, petTraining = { "pet", "amber" }, petAttack = { "pet", "amber" }, petPassive = { "pet", "amber" }, petGrowl = { "pet", "amber" },
  devilsaur = { "gear", "amber" }, wrongTrinket = { "gear", "amber" }, bindConflict = { "gear", "amber" }, shirtGate = { "gear", "red" }, karaborNeck = { "gear", "red" }, quiver = { "gear", "red" },
  targetFrenzy = { "combat", "amber" }, sapperAoe = { "combat", "amber" },
  bossMark = { "boss", "red" }, noRelease = { "boss", "red" }, slammer = { "boss", "red" },
  lustCds = { "other", "amber" }, drums = { "other", "blue" }, utilities = { "other", "blue" },
}
-- Vendor and between-fights nags: off on a raid night.
local HOUSEKEEPING = { petTraining = true, devilsaur = true, wrongTrinket = true, bindConflict = true, dazed = true, utilities = true }
-- Not ready for a preset to switch on: the Slammer helper is still experimental.
local EXPERIMENTAL = { slammer = true }

local function warnSet(pick)
  local keys = {}
  for k in pairs(WARN) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    local on = pick(k, WARN[k][2]) and not EXPERIMENTAL[k]
    out[#out + 1] = { ("alerts.warnings.cat_%s.warning_%s.enabled"):format(WARN[k][1], k), on and true or false }
  end
  return out
end

local function bools(prefix, keys, on)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = { prefix .. k, on[k] ~= nil and on[k] or (on.default == true) } end
  return out
end

local CLASSIC_ELEMENTS = { "showCooldowns", "showBuffRow", "showInfoRow", "showManaBar", "showRangeFinder", "showTotemTracker", "showRotation",
  "showWarnings", "showHelpers", "showCastBar", "showPetStatus", "showAutoShotBar", "showMeleeBar", "showGcdBar" }
-- A HUD preset first switches to that look (a preset on the inactive look
-- would otherwise change nothing visible).
local function classic(on)
  local out = { { "hud.classic.hudMode", "classic" } }
  for _, e in ipairs(bools("hud.classic.layout.grpElements.", CLASSIC_ELEMENTS, on)) do out[#out + 1] = e end
  out[#out + 1] = { "hud.classic.background.backgroundEnabled", on.background == true }
  return out
end

local REACT = { "tabSize.reactShowAutoBar", "tabSize.reactShowMeleeBar", "tabSize.reactShowRangeBar", "tabSize.reactShowManaBar", "tabSize.reactShowCastBar",
  "tabSize.reactShowGrid", "tabSize.reactShowAspectIcon", "tabSize.reactShowMarkIcon", "tabBuff.reactBuffRows",
  "tabBars.reactShowNotation", "tabBars.reactShowClipTicks", "tabBars.reactShowDelay", "tabBars.reactShowBrackets", "tabBars.reactShowGcdDivider" }
local FLUFFY = { "tabSize.fluffyShowCast", "tabSize.fluffyShowSwing", "tabSize.fluffyShowRanged", "tabSize.fluffyShowMelee", "tabSize.fluffyShowLaneIcons",
  "tabSize.fluffyShowRange", "tabSize.fluffyShowMana", "tabGrid.fluffyShowGrid", "tabBuff.fluffyBuffRows",
  "tabBars.fluffyShowNotation", "tabBars.fluffyShowClipTicks", "tabBars.fluffyShowDelay", "tabBars.fluffyShowBrackets", "tabBars.fluffyShowGcdDivider" }
local function look(prefix)
  local l = prefix:match("^hud%.(%w+)%.")
  return { prefix .. "hudMode", l }
end
local function subset(prefix, keys, onList)
  local on = {}
  for _, k in ipairs(onList) do on[k] = true end
  local out = { look(prefix) }
  for _, k in ipairs(keys) do out[#out + 1] = { prefix .. k, on[k] == true } end
  return out
end
-- Everything on, except the keys listed in `off` (a Full look still leaves
-- the noisy readouts alone).
local function all(prefix, keys, off)
  local out = { look(prefix) }
  for _, k in ipairs(keys) do out[#out + 1] = { prefix .. k, not (off and off[k]) } end
  return out
end

local HELPERS = { "food", "flask", "battleElixir", "guardianElixir", "sharpeningStone", "kibler", "scrollPlayer", "scrollPet", "demonslayer", "consecratedStone" }
local function helpers(scrolls, parse)
  local out = {}
  for _, k in ipairs(HELPERS) do
    local on = scrolls or not (k == "scrollPlayer" or k == "scrollPet")
    out[#out + 1] = { "alerts.helpers.tabBuffs.helper_" .. k .. ".enabled", on }
  end
  out[#out + 1] = { "alerts.helpers.tabSettings.parseMode", parse }
  return out
end

P.ByPage = {
  ["alerts.warnings"] = {
    { key = "quiet", name = "Quiet", icon = spellIcon(C.SpellID.FEIGN_DEATH),
      summary = "Only the red ones: pet, gear gates, boss mechanics, resisted feign.",
      set = warnSet(function(_, sev) return sev == "red" end) },
    { key = "raid", name = "Raid night", icon = spellIcon(C.SpellID.RAPID_FIRE),
      summary = "Everything that matters in a fight; vendor and housekeeping nags stay off.",
      set = warnSet(function(k) return not HOUSEKEEPING[k] end) },
    { key = "all", name = "Everything", icon = spellIcon(C.SpellID.AUTO_SHOT),
      summary = "Every warning on, except the experimental Slammer button.",
      set = warnSet(function() return true end) },
  },
  ["hud.classic"] = {
    { key = "compact", name = "Compact", icon = spellIcon(C.SpellID.STEADY_SHOT),
      summary = "Rotation, both swing bars, cast bar, range and cooldowns. No panels, no background.",
      set = classic({ showCooldowns = true, showRangeFinder = true, showRotation = true, showWarnings = true, showHelpers = true, showAutoShotBar = true, showMeleeBar = true, showCastBar = true }) },
    { key = "full", name = "Full", icon = spellIcon(C.SpellID.AUTO_SHOT),
      summary = "Every element and panel, with the background.",
      set = classic({ default = true, background = true }) },
  },
  ["hud.react"] = {
    { key = "lean", name = "Lean", icon = spellIcon(C.SpellID.STEADY_SHOT),
      summary = "Auto, melee, cast, range and the grid. No mana, corners or buff row.",
      set = subset("hud.react.", REACT, { "tabSize.reactShowAutoBar", "tabSize.reactShowMeleeBar", "tabSize.reactShowCastBar", "tabSize.reactShowRangeBar", "tabSize.reactShowGrid", "tabBars.reactShowNotation", "tabBars.reactShowClipTicks" }) },
    { key = "full", name = "Full", icon = spellIcon(C.SpellID.RAPID_FIRE),
      summary = "Every bar, the grid, both corners, the buff row and all readouts; eWS brackets stay off.",
      set = all("hud.react.", REACT, { ["tabBars.reactShowBrackets"] = true }) },
  },
  ["hud.fluffy"] = {
    { key = "minimal", name = "Minimal", icon = spellIcon(C.SpellID.STEADY_SHOT),
      summary = "Cast bar, Auto Shot bar, shot windows, weave lane and range. Nothing else.",
      set = subset("hud.fluffy.", FLUFFY, { "tabSize.fluffyShowCast", "tabSize.fluffyShowSwing", "tabSize.fluffyShowRanged", "tabSize.fluffyShowMelee", "tabSize.fluffyShowRange", "tabBars.fluffyShowNotation" }) },
    { key = "full", name = "Full", icon = spellIcon(C.SpellID.RAPID_FIRE),
      summary = "Every lane, grid, buff row, ticks and readouts; lane icons and eWS brackets stay off.",
      set = all("hud.fluffy.", FLUFFY, { ["tabBars.fluffyShowBrackets"] = true, ["tabSize.fluffyShowLaneIcons"] = true }) },
  },
  ["trackers.buffTracker"] = {
    { key = "player", name = "Raid buffs", summary = "Your own buffs panel only; the pet panel stays off.",
      set = { { "trackers.buffTracker.enabled", true }, { "trackers.buffTracker.playerEnabled", true }, { "trackers.buffTracker.petEnabled", false } } },
    { key = "both", name = "You + pet", summary = "Both panels on.",
      set = { { "trackers.buffTracker.enabled", true }, { "trackers.buffTracker.playerEnabled", true }, { "trackers.buffTracker.petEnabled", true } } },
  },
  ["trackers.debuffTracker"] = {
    { key = "raids", name = "Raids only", summary = "The debuff grid shows in raids and nowhere else.",
      set = { { "trackers.debuffTracker.enabled", true }, { "trackers.debuffTracker.raidOnly", true } } },
    { key = "always", name = "Everywhere", summary = "Dummies, dungeons and raids.",
      set = { { "trackers.debuffTracker.enabled", true }, { "trackers.debuffTracker.raidOnly", false } } },
  },
  ["alerts.helpers"] = {
    { key = "raider", name = "Raider", summary = "Food, flask, elixirs, stones and pet food. No scrolls, no parse mode.",
      set = helpers(false, false) },
    { key = "parse", name = "Parse", summary = "Everything, scrolls included, with parse mode on.",
      set = helpers(true, true) },
  },
}

function P.ForPage(pagePath) return P.ByPage[pagePath] end

local function rows(preset, root, appName)
  local W = Nock.OptionsWalk
  local out = {}
  for _, e in ipairs(preset.set) do
    local row = W.RowAt(root, e[1], appName)
    if row then out[#out + 1] = { row = row, value = e[2] } end
  end
  return out
end

-- True when every entry already reads the preset's value (func entries never count against it).
function P.Matches(preset, root, appName)
  local W = Nock.OptionsWalk
  for _, e in ipairs(rows(preset, root, appName)) do
    if e.value ~= "func" then
      local okv, v = W.Get(e.row)
      if not okv or (v and true or false) ~= (e.value and true or false) and type(e.value) == "boolean" then return false end
      if type(e.value) ~= "boolean" and v ~= e.value then return false end
    end
  end
  return true
end

-- Applies in list order through the row's set/func so every handler runs.
function P.Apply(preset, root, appName)
  local W = Nock.OptionsWalk
  for _, e in ipairs(rows(preset, root, appName)) do
    if e.value == "func" then W.Func(e.row) else W.Set(e.row, e.value) end
  end
end

-- The name a tooltip line uses: the row's own, unless the row is a group's
-- master switch ("Enabled"), which reads as the group it switches.
local function lineName(root, path, row)
  local W = Nock.OptionsWalk
  local name = W.Strip(row.name)
  if row.key == "enabled" or name == "Enabled" then
    local node, parent = root, nil
    for seg in path:gmatch("[^%.]+") do parent = node; node = node and node.args and node.args[seg] end
    local pn = parent and parent.name
    if type(pn) == "function" then local okn, v = pcall(pn); pn = okn and v or nil end
    if type(pn) == "string" and pn ~= "" then name = W.Strip(pn) end
  end
  return (name:gsub("%s*%(spell %d+%)$", ""))
end

-- Tooltip body: what the preset turns ON (green +), what it turns OFF (grey
-- list), and any other value it sets; names sorted, one per line.
function P.Describe(preset, root, appName)
  local W = Nock.OptionsWalk
  local on, off, set = {}, {}, {}
  for _, e in ipairs(preset.set) do
    local row = W.RowAt(root, e[1], appName)
    if row then
      local name, v = lineName(root, e[1], row), e[2]
      if v == true then on[#on + 1] = name
      elseif v == false then off[#off + 1] = name
      else
        local shown = v
        if v == "func" then shown = "run" end
        local keys, labels = W.Values(row)
        for i, k in ipairs(keys or {}) do if k == v then shown = labels[i] end end
        set[#set + 1] = ("%s: %s"):format(name, tostring(shown))
      end
    end
  end
  table.sort(on); table.sort(off)
  local out = {}
  if #set > 0 then out[#out + 1] = "|cffd0d0d0SET|r\n" .. table.concat(set, "\n") end
  if #on > 0 then out[#out + 1] = ("|cff9ad35fON · %d|r\n|cff9ad35f+|r "):format(#on) .. table.concat(on, "\n|cff9ad35f+|r ") end
  if #off > 0 then out[#out + 1] = ("|cff8c8c8cOFF · %d\n– "):format(#off) .. table.concat(off, "\n– ") .. "|r" end
  return table.concat(out, "\n\n")
end

return P
