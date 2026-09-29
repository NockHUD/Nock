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
-- Forever-only Aspect ring, Tracking wheel and Camera flip pages added below.
F.KEEP_PAGES = { utilities = { qol = true, aspectRing = true, cameraFlip = true, trackingWheel = true, weaveKey = true } }

-- Dotted args paths removed inside the surviving families. A trailing `*`
-- matches every key with that prefix (same convention as OptionsLayout rows).
-- Each entry names the module or feed that is missing on Forever in M1.
F.DROP = {
  -- Alerts: the aggro flash runs on own threat state (plain in combat) and
  -- the warnings page builds from Forever/Warnings.lua's own catalog;
  -- helpers and sounds return later (the eating pill's rows move to their
  -- own page first, F.EatingPillPage). No DO NOT RELEASE banner on Forever.
  "alerts.helpers", "alerts.warnings.settings.noReleasePreview",
  -- Sounds: only the Range tab has a Forever feed (Forever/RangeCues.lua).
  "alerts.sounds.deadZone", "alerts.sounds.warnings", "alerts.sounds.weave", "alerts.sounds.other",
  -- HUD family: one HUD only, no mode switching.
  "hud.classic", "hud.fluffy", "hud.hudMode", "hud.react.hudMode", "hud.react.useLook",
  -- React bars: no clip model (no wind-up feed, haste secret in combat), no papers.
  "hud.react.tabBars.grpEngine",
  -- Cooldown Grid: no consumables row (Forever/Spells.lua ROWS has no
  -- whenActive row), no Kill Command tile, and neither the action-bar glow
  -- (Modules/ActionGlow.lua) nor the weave coach loads on Forever.
  "hud.react.tabGrid.reactConsumablesAlways", "hud.react.tabGrid.reactKcProcGlow",
  "hud.react.tabGrid.reactRaptorGoGlow", "hud.react.tabGrid.kcActionBarGlow", "hud.react.tabGrid.kcHeader",
  "hud.react.tabBars.reactShowBrackets", "hud.react.tabBars.reactShowClipTicks", "hud.react.tabBars.reactShowDelay",
  "hud.react.tabBars.reactShowGcdDivider", "hud.react.tabBars.reactShowNotation",
  -- The buff row tab lists TBC buffs (M3b). The range tab holds only the
  -- finding-ladder style, which has no feed on Forever (the three-zone
  -- finder needs no setting); the range bar's own rows live in Size & Skin.
  "hud.react.tabBuff", "hud.react.tabRange",
  -- Size & Elements: Auto Shot wind-up (no feed). The corners and the range
  -- bar came back with M3a; the melee-bar takeover and its preview with the
  -- weave helper (spec 2026-09-28).
  "hud.react.tabSize.reactShowAutoShotCast",
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
  -- The cooldown board replaces the per-row lists, the custom list and the
  -- ID form on Forever (UI/Settings_CooldownBoard.lua).
  "hud.react.tabGrid.gridNote", "hud.react.tabGrid.rcd_*", "hud.react.tabGrid.rcustHeader",
  "hud.react.tabGrid.rcust_*", "hud.react.tabGrid.addHeader", "hud.react.tabGrid.addType",
  "hud.react.tabGrid.addId", "hud.react.tabGrid.addProc", "hud.react.tabGrid.addLabel",
  "hud.react.tabGrid.addBtn",
}

-- A string renames the node; a table sets name and desc.
F.RENAME = {
  ["hud.react"] = "Nock HUD",
  -- The family intro is a description node; only the QoL page survives.
  ["utilities.intro"] = { name = "Quality-of-life helpers (what happens at a vendor, the full-screen glow, the camera and world switches the game hides), the aspect ring and the tracking wheel." },
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
      name = "Hold the key for a ring of your aspects at the cursor: flick toward one and let go to cast it, in or out of combat. Letting go in the middle casts nothing.\n",
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
    aspectRingScale = {
      type = "range", name = "Ring size", order = 20.5, isPercent = true,
      desc = "How large the ring draws; the cancel circle in the middle grows with it.",
      min = 0.75, max = 2, step = 0.05,
      get = function() return Nock.AspectRingScale(ringProfile()) end,
      set = function(_, v) ringProfile().aspectRingScale = v; ringChanged() end,
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

-- Utilities -> Tracking wheel (Forever/TrackingWheel.lua): the aspect ring's
-- mechanism for the eight Track spells; the key and the size. The order is
-- fixed (Beasts up, then clockwise), so there is no dial.
local function wheelChanged() Nock:SendMessage("NOCK_TRACKING_WHEEL_CONFIG") end

function F.TrackingWheelPage()
  local args = {
    intro = {
      type = "description", order = 1, fontSize = "medium",
      name = "Hold the key for a wheel of your Track spells at the cursor: flick toward one and let go to switch to it, in or out of combat. Letting go in the middle changes nothing. Beasts sit up, then clockwise: Humanoids, Undead, Demons, Dragonkin, Elementals, Giants, Hidden. The Wrong tracking warning (Alerts → Warnings → Combat) tells you when your target wants another one.\n",
    },
    keyHeader = { type = "header", name = "Key", desc = "The key that opens the wheel.", order = 10 },
    trackingWheelKey = {
      type = "keybinding", name = "Tracking wheel key", order = 11,
      desc = "The key to hold for the wheel. It can also be set in the game's Key Bindings window under Nock; when both are set, this one wins. A change made in combat applies when combat ends.",
      get = function() return ringProfile().trackingWheelKey or "" end,
      set = function(_, v)
        ringProfile().trackingWheelKey = (type(v) == "string" and v ~= "") and v or nil
        wheelChanged()
      end,
    },
    sizeHeader = { type = "header", name = "Size", desc = "How large the wheel draws.", order = 20 },
    trackingWheelScale = {
      type = "range", name = "Wheel size", order = 21, isPercent = true,
      desc = "How large the wheel draws; the cancel circle in the middle grows with it.",
      min = 0.75, max = 2, step = 0.05,
      get = function() return Nock.TrackingWheelScale(ringProfile()) end,
      set = function(_, v) ringProfile().trackingWheelScale = v; wheelChanged() end,
    },
  }
  return { type = "group", name = "Tracking wheel", order = 13, args = args }
end

-- Utilities -> Camera flip (Forever/CameraFlip.lua): its own page, it is not
-- a HUD element. Headers render as cards; profile keys cameraFlipEnabled /
-- cameraFlipGate / cameraFlipAutoFace, the setup window and the macros copybox.
function F.CameraFlipPage()
  local function CF() return Nock:GetModule("CameraFlip", true) end
  local function styleWrong()
    local get = (_G.C_CVar and _G.C_CVar.GetCVar) or _G.GetCVar
    return tostring(get and get("cameraSmoothStyle") or "?") ~= "0"
  end
  local args = {
    intro = {
      type = "description", order = 1, fontSize = "medium",
      name = "Weave with the camera fixed on the target: on the melee hit your character turns away and runs out toward the camera, on the shot it turns back. The camera itself never moves. Two macro lines drive it; the turn only happens where you allow it.\n",
    },
    turnsHeader = { type = "header", name = "Turns", desc = "When a weave may turn you.", order = 10 },
    cameraFlipEnabled = {
      type = "toggle", name = "Camera flip", order = 11, width = "full",
      desc = "Turn away on the melee hit and back for the shot.\nNeeds the camera set up once (below) and the two macro lines. While this is off the lines do nothing, so they can stay in your macros.",
      get = function() return Nock.db.profile.cameraFlipEnabled == true end,
      set = function(_, v) Nock.db.profile.cameraFlipEnabled = v and true or false end,
    },
    cameraFlipGate = {
      type = "select", name = "Where", order = 12, width = 1.1,
      desc = "Everywhere, only in a group, or only in a raid. Out in the world a weave then just casts.",
      values = { solo = "Everywhere", party = "Party and raid", raid = "Raid only" },
      sorting = { "solo", "party", "raid" },
      disabled = function() return Nock.db.profile.cameraFlipEnabled ~= true end,
      get = function() return Nock.db.profile.cameraFlipGate or "raid" end,
      set = function(_, v) Nock.db.profile.cameraFlipGate = v end,
    },
    cameraFlipAutoFace = {
      type = "toggle", name = "Turn back when in range", order = 13, width = "full",
      desc = "On the way out, turn back as soon as Auto Shot reaches the target again and you let go of the movement key, without waiting for the shot key. Never while you are still running: a turn under a held key would run you straight back in. The macro's face line stays as the fallback.",
      disabled = function() return Nock.db.profile.cameraFlipEnabled ~= true end,
      get = function() return Nock.db.profile.cameraFlipAutoFace ~= false end,
      set = function(_, v) Nock.db.profile.cameraFlipAutoFace = v and true or false end,
    },
    cameraHeader = { type = "header", name = "Camera", desc = "The reversed view the turn needs, and the macros.", order = 20 },
    cameraFlipSetup = {
      type = "execute", name = "Set up camera", order = 21, width = 1.0,
      desc = "Opens the three-step window: camera behind you, turn to face it on a live track, test it. Run it again after changing your zoom or tilt.",
      func = function()
        -- The setup window wants the whole screen (you steer the camera):
        -- close every settings surface first, as the wizard buttons do.
        if Nock.Settings then Nock.Settings:Close() end
        LibStub("AceConfigDialog-3.0"):Close("Nock")
        local blizz = _G.SettingsPanel or _G.InterfaceOptionsFrame
        if blizz and blizz.IsShown and blizz:IsShown() and _G.HideUIPanel then _G.HideUIPanel(blizz) end
        local m = CF(); if m and m.CameraSetup then m:CameraSetup() end
      end,
    },
    cameraFlipMacros = {
      type = "execute", name = "Show macros", order = 22, width = 1.0,
      desc = "Both macros with their camera lines, in a window you can copy from.",
      func = function() local m = CF(); if m and m.ShowMacros then m:ShowMacros() end end,
    },
    cameraFlipStyle = {
      type = "execute", name = "Fix camera following style", order = 23, width = 1.4,
      desc = "The turn needs Camera Following Style at \"Never adjust camera\". This sets it; the same setting lives on the Quality of life page.",
      hidden = function() return not styleWrong() end,
      func = function()
        local set = (_G.C_CVar and _G.C_CVar.SetCVar) or _G.SetCVar
        if set then set("cameraSmoothStyle", "0") end
      end,
    },
    styleNote = {
      type = "description", order = 24, fontSize = "small",
      name = function() return styleWrong() and "|cffff9900Camera Following Style is not Never adjust: the camera fights every turn.|r" or "Camera Following Style: Never adjust." end,
    },
  }
  return { type = "group", name = "Camera flip", order = 13, args = args }
end

-- Utilities -> Weave key (Forever/WeaveKey.lua): the optional one-key weave
-- beside the macro way. The TBC Weave Bind page's shape: mode, key, both
-- bodies as text with resets, the pad switch. Profile keys weaveKeyEnabled /
-- weaveKey / weaveKeyMacroDown / weaveKeyMacroUp.
function F.WeaveKeyPage()
  local function WK() return Nock.WeaveKey end
  local function WM() return Nock.WeaveMacro end
  local function p() return Nock.db.profile end
  local function changed() Nock:SendMessage("NOCK_WEAVEKEY_CHANGED") end
  local function off() return p().weaveKeyEnabled ~= true end
  local function body(which)
    local d, u = WK().Bodies(p())
    return which == "down" and d or u
  end
  local args = {
    intro = {
      type = "description", order = 1, fontSize = "medium",
      name = "Two ways to weave. Macros: your own Raptor Strike and Auto Shot macros with the camera lines, W does the running. Weave key: one held key runs you in, its release strikes, the next hold runs you out on the turned character, and the last release shoots. Both use the melee bar's words and the camera flip.\n",
    },
    modeHeader = { type = "header", name = "Mode", desc = "Which way you weave.", order = 10 },
    weaveKeyEnabled = {
      type = "toggle", name = "Weave with one key", order = 11, width = "full",
      desc = "Hold to run in, let go to strike, hold to run out, let go to shoot. Wants the camera flip on: without it the second hold runs you toward the target. Off, nothing is bound and your macros work as before.",
      get = function() return p().weaveKeyEnabled == true end,
      set = function(_, v) p().weaveKeyEnabled = v and true or false; changed() end,
    },
    weaveKey = {
      type = "keybinding", name = "Weave key", order = 12,
      desc = "The key to hold. Mouse buttons work too: click the box, then press the button. It overrides the key's normal action while the mode is on; a change made in combat applies when combat ends. Also under Nock in the game's Key Bindings.",
      disabled = off,
      get = function() return p().weaveKey or "" end,
      set = function(_, v)
        if v and v ~= "" then
          local action = GetBindingAction and GetBindingAction(v)
          if action == "OPENCHAT" or action == "OPENCHATSLASH" or action == "TOGGLEGAMEMENU" then
            Nock:Print(("Weave key: refusing to override the '%s' key, you would lose chat or the game menu."):format(_G["BINDING_NAME_" .. action] or action))
            return
          end
        end
        p().weaveKey = (type(v) == "string" and v ~= "") and v or nil
        changed()
      end,
    },
    weaveKeyNote = {
      type = "description", order = 13, fontSize = "small",
      name = function()
        local CF = Nock.CameraFlip
        if off() then return "" end
        if not _G.MovePadForward and not (WK() and WK().LoadPad and WK():LoadPad()) then
          return "|cffff9900The Movement Pad is not available on this client: the key cannot run you.|r"
        end
        if CF and CF.Enabled and not CF.Enabled(p()) then
          return "|cffff9900Camera flip is off: the second hold runs you toward the target. Utilities > Camera flip.|r"
        end
        return "Camera flip on, Movement Pad loaded."
      end,
    },
    bodiesHeader = { type = "header", name = "What the key runs", desc = "The press body and the release body, yours to edit.", order = 20 },
    weaveKeyMovePad = {
      type = "toggle", name = "Movement pad", order = 21, width = "full",
      desc = "Keep /click MovePadForward at the top of both bodies: the press starts the run, the release stops it. Off, the key only casts and you run on W.",
      disabled = off,
      get = function() return WM().HasMovePad(body("down")) or WM().HasMovePad(body("up")) end,
      set = function(_, v)
        local d, u = WK().Bodies(p())
        if v then
          p().weaveKeyMacroDown, p().weaveKeyMacroUp = WM().WithMovePad(d, WK().PAD_LINE), WM().WithMovePad(u, WK().PAD_LINE)
        else
          p().weaveKeyMacroDown, p().weaveKeyMacroUp = WM().WithoutMovePad(d), WM().WithoutMovePad(u)
        end
        changed()
      end,
    },
    weaveKeyMacroDown = {
      type = "input", name = "Press", order = 22, width = "full", multiline = 3,
      desc = "Runs on the key press. A cast here would go off before you arrive; keep it to the pad line.",
      disabled = off,
      get = function() return body("down") end,
      set = function(_, v) p().weaveKeyMacroDown = v or ""; changed() end,
    },
    weaveKeyResetDown = {
      type = "execute", name = "Reset press", order = 23, width = 0.8,
      desc = "Back to the stock press body.",
      disabled = function() return off() or WK().IsStock(body("down"), WK().STOCK_DOWN) end,
      func = function() p().weaveKeyMacroDown = nil; changed() end,
    },
    weaveKeyMacroUp = {
      type = "input", name = "Release", order = 24, width = "full", multiline = 6,
      desc = "Runs when you let go. The stock order matters: Raptor Strike before /startattack (the ready swing must carry it), !Auto Shot as the last attack line (it wins the attack state). NockCamFlip() arms the turn away, NockCamFace() turns you back at range.",
      disabled = off,
      get = function() return body("up") end,
      set = function(_, v) p().weaveKeyMacroUp = v or ""; changed() end,
    },
    weaveKeyResetUp = {
      type = "execute", name = "Reset release", order = 25, width = 0.8,
      desc = "Back to the stock release body.",
      disabled = function() return off() or WK().IsStock(body("up"), WK().STOCK_UP) end,
      func = function() p().weaveKeyMacroUp = nil; changed() end,
    },
    otherHeader = { type = "header", name = "Around it", desc = "The red error text the failing lines print, and the report.", order = 30 },
    weaveKeyErrors = {
      type = "toggle", name = "Hide red error text", order = 31, width = "full",
      desc = "The release body fails a line on purpose wherever you stand (too close, out of range, not ready). This hides the red text; it is the same switch as on the Quality of life page.",
      get = function() return p().qolHideErrors == true end,
      set = function(_, v)
        local m = Nock:GetModule("QoL", true)
        if m and m.SetHideErrors then m.SetHideErrors(v and true or false) else p().qolHideErrors = v and true or false end
      end,
    },
    weaveKeyReport = {
      type = "execute", name = "Show report", order = 32, width = 1.0,
      desc = "The key, both bodies as bound, the pad state and the last edges and casts, in a window you can copy from (/nock weavekey).",
      func = function() local m = Nock:GetModule("WeaveKey", true); if m and m.Command then m:Command("") end end,
    },
  }
  return { type = "group", name = "Weave key", order = 14, args = args }
end

-- Alerts -> Eating pill (UI/Frame_ConsumeBanner.lua): the pill's own rows,
-- lifted out of the TBC Helpers page before that page is dropped (the
-- consumables badge row has no feed on Forever). Same nodes, same profile keys.
local PILL_ROWS = { "consumeBannerEnabled", "consumeBannerSound", "consumeBannerSize", "consumeBannerResetPos" }

function F.EatingPillPage(settings)
  local args = {
    pillHeader = { type = "header", name = "Eating / drinking pill", order = 1,
      desc = "Centre-screen while the Food or Drink aura is on you; flashes WELL FED when the buff lands." },
  }
  for i, key in ipairs(PILL_ROWS) do
    local n = settings[key]
    if type(n) == "table" then n.order = 1 + i; args[key] = n end
  end
  return { type = "group", name = "Eating pill", order = 3, args = args }
end

function F.Apply(root)
  if type(root) ~= "table" or type(root.args) ~= "table" then return end
  local alerts = root.args.alerts
  local hs = type(alerts) == "table" and alerts.args and alerts.args.helpers
  hs = type(hs) == "table" and hs.args and hs.args.tabSettings
  if type(hs) == "table" and type(hs.args) == "table" and not alerts.args.eating then
    alerts.args.eating = F.EatingPillPage(hs.args)
  end
  -- Built once; the prune below keeps it (KEEP_PAGES), a re-Apply finds it.
  local util = root.args.utilities
  if type(util) == "table" and type(util.args) == "table" and not util.args.aspectRing and Nock.AspectRingOrder then
    util.args.aspectRing = F.AspectRingPage()
  end
  if type(util) == "table" and type(util.args) == "table" and not util.args.cameraFlip then
    util.args.cameraFlip = F.CameraFlipPage()
  end
  if type(util) == "table" and type(util.args) == "table" and not util.args.weaveKey and Nock.WeaveKey then
    util.args.weaveKey = F.WeaveKeyPage()
  end
  if type(util) == "table" and type(util.args) == "table" and not util.args.trackingWheel and Nock.TrackingWheelScale then
    util.args.trackingWheel = F.TrackingWheelPage()
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
