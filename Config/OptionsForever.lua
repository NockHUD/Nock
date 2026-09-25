-- Config/OptionsForever.lua
-- WoW Forever allowlist for the settings tree: keeps General, the React page
-- (as "Nock HUD") and Profiles, and drops every family, tab and row whose
-- module or feed does not exist on Forever. Loaded by Nock_Camelot.toc only.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local F = {}
Nock.OptionsForever = F

-- Top-level families that survive. Everything else at the root goes.
F.FAMILIES = { general = true, hud = true, profiles = true, alerts = true, utilities = true }
-- Families that keep only the listed pages (every other group inside goes):
-- Utilities is the TBC toolbox (practice, mailbox, weave binds, ...); only
-- the Quality of life page has a feed on Forever (Modules/QoL.lua), plus the
-- Forever-only Aspect ring page added below (F.AspectRingPage).
F.KEEP_PAGES = { utilities = { qol = true, aspectRing = true } }

-- Dotted args paths removed inside the surviving families. A trailing `*`
-- matches every key with that prefix (same convention as OptionsLayout rows).
-- Each entry names the module or feed that is missing on Forever in M1.
F.DROP = {
  -- Alerts: the aggro flash runs on own threat state (plain in combat) and
  -- the warnings page builds from Forever/Warnings.lua's own catalog;
  -- helpers and sounds return later. No DO NOT RELEASE banner on Forever.
  "alerts.helpers", "alerts.warnings.settings.noReleasePreview",
  -- Sounds: only the Range tab has a Forever feed (Forever/RangeCues.lua).
  "alerts.sounds.deadZone", "alerts.sounds.warnings", "alerts.sounds.weave", "alerts.sounds.other",
  -- HUD family: one HUD only, no mode switching.
  "hud.classic", "hud.fluffy", "hud.hudMode", "hud.react.hudMode", "hud.react.useLook",
  -- React bars: no clip model (no wind-up feed, haste secret in combat), no papers.
  "hud.react.tabBars.grpEngine",
  "hud.react.tabBars.reactShowBrackets", "hud.react.tabBars.reactShowClipTicks", "hud.react.tabBars.reactShowDelay",
  "hud.react.tabBars.reactShowGcdDivider", "hud.react.tabBars.reactShowNotation",
  -- The buff row tab lists TBC buffs (M3b). The range tab holds only the
  -- finding-ladder style, which has no feed on Forever (the three-zone
  -- finder needs no setting); the range bar's own rows live in Size & Skin.
  "hud.react.tabBuff", "hud.react.tabRange",
  -- Size & Elements: Auto Shot wind-up (no feed), weave stage, mana tick
  -- (M3a Task 5). The corners and the range bar came back with M3a.
  "hud.react.tabSize.reactShowAutoShotCast",
  "hud.react.tabSize.reactMeleeStageCue", "hud.react.tabSize.stagePre*",
  -- Skin: the Steady/Multi clip ticks (no clip model, and neither spell is
  -- in the game yet), brackets and the GCD divider go; the wind-up pair
  -- stays as the spell-queue mark (renamed below).
  "hud.react.tabSkin.reactBracketWidth", "hud.react.tabSkin.reactColorBracket",
  "hud.react.tabSkin.reactColorGcdDivider", "hud.react.tabSkin.reactGcdDividerWidth",
  "hud.react.tabSkin.reactTickSteadyWidth", "hud.react.tabSkin.reactColorTickSteady",
  "hud.react.tabSkin.reactTickMultiWidth", "hud.react.tabSkin.reactColorTickMulti",
  -- General: no cast bar, no setup check, no HUD-mode look, no profiler.
  "general.grpCastBar", "general.grpSetup", "general.grpLook",
  "general.perfPanel",
}

-- A string renames the node; a table sets name and desc.
F.RENAME = {
  ["hud.react"] = "Nock HUD",
  -- The family intro is a description node; only the QoL page survives.
  ["utilities.intro"] = { name = "Quality-of-life helpers (what happens at a vendor, the full-screen glow, the camera and world switches the game hides) and the aspect ring." },
  ["hud.react.tabBars.showWindupMark"] = {
    name = "Spell-queue mark",
    desc = "The neutral mark on the Auto Shot bar where the client's spell-queue window opens before the next shot (SpellQueueWindow, 400 ms by default). Past it a press is queued behind the shot and comes out right after it; before it, a cast started now would push the shot back.",
  },
  ["hud.react.tabSkin.autoMarksHeader"] = "Spell-queue mark",
  ["hud.react.tabSize.reactShowRangeBar"] = {
    name = "Range Finder",
    desc = "The range ladder: every distance bracket from melee to out of range, the target's bracket lit.",
  },
  ["hud.react.tabSkin.reactTickWindupWidth"] = {
    name = "Spell-queue mark width",
    desc = "Width of the spell-queue mark on the Auto Shot bar, in real screen pixels (independent of your UI scale).",
  },
  ["hud.react.tabSkin.reactColorTickWindup"] = {
    name = "Spell-queue mark",
    desc = "The mark showing where the client's spell-queue window opens before the next Auto Shot (SpellQueueWindow, 400 ms by default): past it a press is queued behind the shot instead of pushing it back.",
  },
}

-- Rows tagged Advanced by the shared rules that are the plain feature switch
-- on Forever (one HUD, one mark): untagged so Simple mode reaches them.
F.SIMPLE = { "hud.react.tabBars.showWindupMark" }

-- Table cards keep their line labels in the layout spec (Config/
-- OptionsLayoutData.lua), not on the option nodes, so RENAME cannot reach
-- them; per card, old line label -> new. Lines whose options were dropped
-- vanish on their own (Core/OptionsWalk skips a line with no cell).
F.TABLE_LINES = {
  ["hud.react.tabSkin.autoShotColoursCard"] = { ["Wind-up mark"] = "Spell-queue mark" },
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

-- Utilities -> Aspect ring (Forever/AspectRing.lua): the key and the dial.
-- Forever-only, so it is built here rather than in the shared Options.lua.
-- The cards split at the two headers. Every change is saved to the profile
-- and announced with NOCK_ASPECT_RING_CONFIG; the ring does the rest.
local DIRECTIONS = { "Up", "Up-right", "Down-right", "Down", "Down-left", "Up-left" }

local function ringProfile() return Nock.db.profile end
local function ringChanged() Nock:SendMessage("NOCK_ASPECT_RING_CONFIG") end

-- aspect key -> the name shown in the dropdown: the localized spell name
-- without the prefix every aspect shares ("Cheetah"); the key itself while
-- the client has not resolved the names.
local function aspectLabels()
  local S = Nock.Spells
  local byKey = Nock.AspectRingIdByKey()
  local full = {}
  for i, key in ipairs(S.ASPECT_RING) do
    local n = Nock.API and Nock.API.SpellName and Nock.Flavor.Plain(Nock.API.SpellName(byKey[key]))
    full[i] = type(n) == "string" and n or nil
  end
  local short = Nock.AspectRingShortNames(full)
  local out = {}
  for i, key in ipairs(S.ASPECT_RING) do
    out[key] = short[i] or (key:sub(1, 1):upper() .. key:sub(2))
  end
  return out
end

function F.AspectRingPage()
  local args = {
    intro = {
      type = "description", order = 1, fontSize = "medium",
      name = "Hold the key out of combat for a ring of your aspects at the cursor: flick toward one and let go to cast it. In combat the key casts Aspect of the Hawk.\n",
    },
    keyHeader = { type = "header", name = "Key", desc = "The key that opens the ring.", order = 10 },
    aspectRingKey = {
      type = "keybinding", name = "Aspect ring key", order = 11,
      desc = "The key to hold for the ring. It can also be set in the game's Key Bindings window under Nock; when both are set, this one wins. A change made in combat applies when combat ends.",
      get = function() return ringProfile().aspectRingKey or "" end,
      set = function(_, v)
        ringProfile().aspectRingKey = (type(v) == "string" and v ~= "") and v or nil
        ringChanged()
      end,
    },
    dialHeader = { type = "header", name = "Dial", desc = "Which aspect sits in each direction; picking one that is already placed swaps the two.", order = 20 },
    aspectRingDefault = {
      type = "execute", name = "Default layout", order = 21,
      desc = "Hawk up, Cheetah down, the rest clockwise: Monkey, Wild, Pack, Beast.",
      func = function() ringProfile().aspectRingOrder = nil; ringChanged() end,
    },
  }
  for i, dir in ipairs(DIRECTIONS) do
    args["aspectRingDir" .. i] = {
      type = "select", name = dir, order = 21 + i,
      desc = ("The aspect a flick %s casts."):format(dir == "Up" and "up" or dir == "Down" and "down" or ("to the " .. dir:lower())),
      values = aspectLabels,
      sorting = Nock.Spells.ASPECT_RING,
      get = function() return Nock.AspectRingOrder(ringProfile().aspectRingOrder)[i] end,
      set = function(_, key)
        ringProfile().aspectRingOrder = Nock.AspectRingSwap(Nock.AspectRingOrder(ringProfile().aspectRingOrder), i, key)
        ringChanged()
      end,
    }
  end
  return { type = "group", name = "Aspect ring", order = 12, args = args }
end

function F.Apply(root)
  if type(root) ~= "table" or type(root.args) ~= "table" then return end
  -- Built once; the prune below keeps it (KEEP_PAGES), a re-Apply finds it.
  local util = root.args.utilities
  if type(util) == "table" and type(util.args) == "table" and not util.args.aspectRing and Nock.AspectRingOrder then
    util.args.aspectRing = F.AspectRingPage()
  end
  for k, v in pairs(root.args) do
    if type(v) == "table" and v.type == "group" and not F.FAMILIES[k] then root.args[k] = nil end
  end
  for fam, keep in pairs(F.KEEP_PAGES) do
    local node = root.args[fam]
    if type(node) == "table" and type(node.args) == "table" then
      for k, v in pairs(node.args) do
        if type(v) == "table" and v.type == "group" and not keep[k] then node.args[k] = nil end
      end
    end
  end
  for _, path in ipairs(F.DROP) do dropPath(root, path) end
  for path, name in pairs(F.RENAME) do
    local n = nodeAt(root, path)
    if n then
      if type(name) == "table" then
        n.name = name.name or n.name
        if name.desc then n.desc = name.desc end
      else
        n.name = name
      end
    end
  end
  local W = Nock.OptionsWalk
  if not W then return end
  for _, path in ipairs(F.SIMPLE) do
    local n = nodeAt(root, path)
    if n then W.SetMeta(n, "advanced", nil) end
  end
  for path, map in pairs(F.TABLE_LINES) do
    local n = nodeAt(root, path)
    local spec = n and W.Meta(n) and W.Meta(n).table
    if spec then
      -- A copy: the spec object is the layout data itself, shared by every
      -- rebuild, and the TBC labels must survive in it.
      local rows = {}
      for i, rs in ipairs(spec.rows) do
        local label = type(rs[1]) == "string" and map[rs[1]] or rs[1]
        rows[i] = { label, rs[2] }
      end
      W.SetMeta(n, "table", { cols = spec.cols, rows = rows, grid = spec.grid })
    end
  end
end
