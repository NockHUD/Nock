-- Config/Options.lua
-- AceConfig-3.0 options table; registered with Blizzard's addon options panel.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

local function get(info) return Nock.db.profile[info[#info]] end
local function set(info, value) Nock.db.profile[info[#info]] = value end

local function visualsSet(_, key, value)
  Nock.db.profile[key] = value
  Nock:SendMessage("NOCK_VISUALS_CHANGED")
end

-- Reusable "global on/off" toggle bound to a profile show* flag. The same key
-- is surfaced both in Layout → HUD elements and at the top of each subsystem's own
-- tab; both stay in sync since they read/write the one profile field.
local function globalToggle(key, name, desc, order)
  return {
    type  = "toggle",
    name  = name,
    desc  = desc,
    order = order,
    width = "full",
    get   = function() return Nock.db.profile[key] ~= false end,
    set   = function(_, v) visualsSet(_, key, v) end,
  }
end

-- Opt-in variant of globalToggle for default-OFF flags (get compares == true so
-- a nil/absent flag reads as off, matching the feature's own tab).
local function optToggle(key, name, desc, order)
  return {
    type  = "toggle",
    name  = name,
    desc  = desc,
    order = order,
    width = "full",
    get   = function() return Nock.db.profile[key] == true end,
    set   = function(_, v) visualsSet(_, key, v) end,
  }
end

-- Every visual element's profile flag, split by default state, so Layout can
-- offer one-click Hide all / Show all. Default-on = restored by "Show all";
-- opt-in = never force-enabled by "Show all" (only cleared by "Hide all").
local HUD_DEFAULT_ON_FLAGS = {
  "showCooldowns", "showInfoRow", "showManaBar", "showRangeFinder", "showBuffRow",
  "showRotation", "showWarnings", "showHelpers", "totemTrackerEnabled",
  "showCastBar", "showPetStatus",
  "showAutoShotBar", "showMeleeBar", "showGcdBar",
  "shoppingEnabled", "repairWarnEnabled",
  -- React-mode element flags (React HUD tab) — the classic show* flags
  -- above don't reach the React frames, so Hide/Show all covers both looks.
  "reactShowAutoBar", "reactShowMeleeBar", "reactShowRangeBar",
  "reactShowManaBar", "reactShowCastBar", "reactShowGrid", "reactBuffRows",
}
local HUD_OPT_IN_FLAGS = {
  "misdirectEnabled", "mdCastEnabled", "buffTrackerEnabled", "debuffTrackerEnabled",
  -- React corner icons: shipped off on purpose, so "Show all" must not turn
  -- them on. "Hide all" still clears them.
  "reactShowAspectIcon", "reactShowMarkIcon",
}

local function setAllHudVisibility(show)
  for _, k in ipairs(HUD_DEFAULT_ON_FLAGS) do Nock.db.profile[k] = show end
  -- Hide all also clears the opt-in panels; Show all leaves them as-is so it
  -- never force-enables a tracker the user never turned on.
  if not show then
    for _, k in ipairs(HUD_OPT_IN_FLAGS) do Nock.db.profile[k] = false end
  end
  Nock:SendMessage("NOCK_VISUALS_CHANGED")
  -- Refresh the open options panel so all the individual toggles reflect the change.
  local reg = LibStub("AceConfigRegistry-3.0", true)
  if reg then reg:NotifyChange("Nock") end
end

local function getColor(info)
  local c = Nock.db.profile[info[#info]]
  if not c then return 1, 1, 1, 1 end
  return c[1], c[2], c[3], c[4]
end

local function setColor(info, r, g, b, a)
  Nock.db.profile[info[#info]] = { r, g, b, a }
  Nock:SendMessage("NOCK_VISUALS_CHANGED")
end

-- The practice stage's palette lives in one colour table the views hold by
-- reference (Nock.PracticeTimeline.COLORS); Practice:ApplyColors copies the
-- profile into it in place.
local function setPracticeColor(info, r, g, b)
  Nock.db.profile[info[#info]] = { r, g, b }
  local p = Nock:GetModule("Practice", true)
  if p and p.ApplyColors then p:ApplyColors() end
  Nock:SendMessage("NOCK_VISUALS_CHANGED")
end

-- The stage's style levers (Core/PracticeTimeline.lua T.STYLE_LEVERS): the
-- select's values, order and description all come off the one definition, so
-- Options, the conveyor and the slash command cannot disagree. `values` and
-- `sorting` are functions: the timeline file is loaded by the time AceConfig
-- asks, whatever the TOC order.
local function styleLever(lever)
  local T = Nock.PracticeTimeline
  return T and T.STYLE_BY_LEVER and T.STYLE_BY_LEVER[lever] or nil
end
local function styleValues(lever)
  return function()
    local L = styleLever(lever)
    local out = {}
    if L then for _, v in ipairs(L.values) do out[v] = v end end
    return out
  end
end
local function styleSorting(lever)
  return function()
    local L = styleLever(lever)
    return L and L.values or {}
  end
end
local function styleDesc(lever)
  return function()
    local L = styleLever(lever)
    return L and L.desc or ""
  end
end
local function getStyle(info)
  local key = info[#info]
  local v = Nock.db.profile[key]
  if v ~= nil then return v end
  local T = Nock.PracticeTimeline
  if T and T.STYLE_LEVERS then
    for _, L in ipairs(T.STYLE_LEVERS) do if L.key == key then return L.values[1] end end
  end
  return nil
end
local function setStyle(info, v)
  Nock.db.profile[info[#info]] = v
  Nock:SendMessage("NOCK_VISUALS_CHANGED")
end

-- Pick the media preview widget for a dropdown. The preference order and the
-- reasoning behind it live in UI/AceGUI_LSMDropdown.lua, which registers the
-- widgets and is also what /nock diag reports -- one source of truth, so the
-- diagnostic can never disagree with what is actually rendering.
--
-- Resolved lazily at option-build time, and nil-safe: that file bails early if
-- AceGUI or LibSharedMedia is missing, in which case every dropdown quietly
-- degrades to AceConfigDialog's stock Dropdown rather than erroring.
local function lsmWidget(_, mediaType)
  if not (Nock.UI and Nock.UI.PreferredMediaWidget) then return nil end
  return Nock.UI.PreferredMediaWidget(mediaType)
end

-- Shared "Background" styling block for the floating panels (MD tracker,
-- buff/debuff grids, shopping list): fill color + opacity and an LSM border
-- with size/color/opacity — the same depth as Classic HUD → Background. Keys are
-- <prefix>BgColor / <prefix>BgOpacity / <prefix>Border / <prefix>BorderSize /
-- <prefix>BorderColor / <prefix>BorderOpacity; opacityKey overrides the fill
-- opacity key (the MD tracker predates this block with mdBackgroundOpacity).
-- Rendered by UI/Widgets.lua's ApplyUserPanelStyle; every set fires
-- NOCK_VISUALS_CHANGED so the panel restyles live. Injected into each panel's
-- tab near the bottom of buildOptionsTable.
local function panelStyleArgs(prefix, startOrder, opacityKey)
  opacityKey = opacityKey or (prefix .. "BgOpacity")
  local borderKey = prefix .. "Border"
  local function set(key, v)
    Nock.db.profile[key] = v
    Nock:SendMessage("NOCK_VISUALS_CHANGED")
  end
  local function colorOpt(key, name, desc, order)
    return {
      type = "color", name = name, desc = desc, order = order, hasAlpha = false,
      get = function()
        local c = Nock.db.profile[key] or { 0, 0, 0 }
        return c[1] or 0, c[2] or 0, c[3] or 0
      end,
      set = function(_, r, g, b) set(key, { r, g, b }) end,
    }
  end
  return {
    [prefix .. "StyleHeader"] = { type = "header", name = "Background", order = startOrder },
    [prefix .. "BgColor"] = colorOpt(prefix .. "BgColor", "Background color",
      "Fill color of the panel's backdrop (the border has its own color below).",
      startOrder + 0.1),
    [opacityKey] = {
      type = "range",
      name = "Background opacity",
      desc = "Backdrop fill alpha. 0 = transparent fill (combine with a border for an outline-only look).",
      min = 0, max = 1.0, step = 0.05, bigStep = 0.1,
      order = startOrder + 0.2,
      get = function()
        local v = Nock.db.profile[opacityKey]
        -- Unreachable under AceDB defaults; the Defaults read keeps the
        -- fallback from drifting per-panel (shopping 0.78, debuffs 0, ...).
        if v == nil and Nock.Defaults then v = Nock.Defaults.profile[opacityKey] end
        if v == nil then v = 0.85 end
        return v
      end,
      set = function(_, v) set(opacityKey, v) end,
    },
    [borderKey] = {
      type = "select",
      name = "Border style",
      desc = "Border texture for the panel. Sourced from LibSharedMedia. 'None' keeps the original 1px solid line.",
      order = startOrder + 0.3,
      dialogControl = lsmWidget(nil, "plain"),
      values = function()
        local lsm = LibStub("LibSharedMedia-3.0", true)
        local out = { ["None"] = "None (1px)" }
        if lsm then
          for _, name in ipairs(lsm:List("border")) do out[name] = name end
        end
        return out
      end,
      get = function() return Nock.db.profile[borderKey] or "None" end,
      set = function(_, v) set(borderKey, v) end,
    },
    [prefix .. "BorderSize"] = {
      type = "range",
      name = "Border thickness",
      desc = "Border edge size (px). Only applies when a LibSharedMedia border is selected — most look best around 8-16.",
      min = 1, max = 32, step = 1,
      order = startOrder + 0.4,
      disabled = function()
        local b = Nock.db.profile[borderKey]
        return not b or b == "None" or b == ""
      end,
      get = function() return Nock.db.profile[prefix .. "BorderSize"] or 12 end,
      set = function(_, v) set(prefix .. "BorderSize", v) end,
    },
    [prefix .. "BorderColor"] = colorOpt(prefix .. "BorderColor", "Border color",
      "Tint of the panel border (separate from the fill color).", startOrder + 0.5),
    [prefix .. "BorderOpacity"] = {
      type = "range",
      name = "Border opacity",
      desc = "Border alpha. 0 = invisible border (fill only). The green unlock border always shows at full strength so the panel stays findable while repositioning.",
      min = 0, max = 1.0, step = 0.05, bigStep = 0.1,
      order = startOrder + 0.6,
      get = function()
        local v = Nock.db.profile[prefix .. "BorderOpacity"]
        if v == nil and Nock.Defaults then v = Nock.Defaults.profile[prefix .. "BorderOpacity"] end
        if v == nil then v = 1.0 end
        return v
      end,
      set = function(_, v) set(prefix .. "BorderOpacity", v) end,
    },
  }
end

-- Per-bar TRACK styling block. The "track" is the frame BEHIND a bar's fill --
-- the part that shows through wherever the fill hasn't reached. Every classic
-- bar hardcoded it to black, which is the "everything is a black box" look this
-- block undoes. Four controls per bar: fill color + opacity, border color +
-- opacity. Keys are <prefix>BgColor / <prefix>BgOpacity / <prefix>BorderColor /
-- <prefix>BorderOpacity, rendered by UI/Widgets.lua's ApplyBarStyle.
--
-- Deliberately NARROWER than panelStyleArgs: no LSM border style/thickness.
-- These are bars, and the GCD sweep is 4px tall -- a 12px edge texture would
-- swallow it whole. The 1px solid edge stays; only its color moves.
--
-- Every set fires NOCK_VISUALS_CHANGED, which runs RefreshMedia ->
-- RefreshBarStyles, so the bar restyles live behind the options window.
local function barStyleArgs(prefix, startOrder, label)
  local function set(key, v)
    Nock.db.profile[key] = v
    Nock:SendMessage("NOCK_VISUALS_CHANGED")
  end
  local function readNum(key, fallback)
    local v = Nock.db.profile[key]
    if v == nil and Nock.Defaults then v = Nock.Defaults.profile[key] end
    if v == nil then v = fallback end
    return v
  end
  local function colorOpt(key, name, desc, order)
    return {
      type = "color", name = name, desc = desc, order = order, hasAlpha = false,
      get = function()
        local c = Nock.db.profile[key] or { 0, 0, 0 }
        return c[1] or 0, c[2] or 0, c[3] or 0
      end,
      set = function(_, r, g, b) set(key, { r, g, b }) end,
    }
  end
  return {
    [prefix .. "TrackHeader"] = {
      type = "header",
      name = label or "Bar background",
      order = startOrder,
    },
    [prefix .. "BgColor"] = colorOpt(prefix .. "BgColor", "Background color",
      "Color of the bar's track -- the part behind the fill. Default is black.",
      startOrder + 0.1),
    [prefix .. "BgOpacity"] = {
      type = "range",
      name = "Background opacity",
      desc = "Track alpha. 0 = a fully transparent track, so only the fill and the border are drawn.",
      min = 0, max = 1.0, step = 0.05, bigStep = 0.1,
      order = startOrder + 0.2,
      get = function() return readNum(prefix .. "BgOpacity", 0.85) end,
      set = function(_, v) set(prefix .. "BgOpacity", v) end,
    },
    [prefix .. "BorderColor"] = colorOpt(prefix .. "BorderColor", "Border color",
      "Color of the bar's 1px outline (separate from the track fill).",
      startOrder + 0.3),
    [prefix .. "BorderOpacity"] = {
      type = "range",
      name = "Border opacity",
      desc = "Border alpha. 0 = no outline at all.",
      min = 0, max = 1.0, step = 0.05, bigStep = 0.1,
      order = startOrder + 0.4,
      get = function() return readNum(prefix .. "BorderOpacity", 1.0) end,
      set = function(_, v) set(prefix .. "BorderOpacity", v) end,
    },
  }
end

-- Live "is this key free?" note for the override-bound Weave Bind key. It claims
-- its key at priority, so Nock wins it silently and whatever was on it stops
-- working — the whole point of saying so here. The
-- wording comes from Modules/BindCheck.lua so this and the warning square can
-- never describe the same clash differently. Reads cached state only: no binding
-- APIs are called from a render path.
local function bindConflictNote(which, order)
  return {
    type     = "description",
    order    = order,
    fontSize = "medium",
    name = function()
      local bc = Nock:GetModule("BindCheck", true)
      local s  = Nock.state and Nock.state.binds and Nock.state.binds[which]
      if not (bc and s and s.key and s.key ~= "") then return "" end
      local note = bc:Note(which)
      if not note then
        return ("|cff20c020'%s' is free|r — nothing else is bound to it.\n"):format(s.key)
      end
      -- A bound-but-empty action slot is reported, not flagged: the binding is
      -- real but there is nothing in it to lose, so it stays green and raises no
      -- warning square (BindCheck:ShouldWarn).
      if s.conflict.empty then
        return ("|cff20c020'%s' is free in practice|r — %s.\n"):format(s.key, note)
      end
      return ("|cffffd200'%s': %s.|r\nNock never changes your bindings — whatever was on the key comes back the moment you disable this or clear the key.\n")
        :format(s.key, note)
    end,
  }
end

-- Both key pickers re-resolve the conflict the instant the key changes, so the
-- note above is already correct on the render that follows the set.
local function refreshBindCheck()
  local bc = Nock:GetModule("BindCheck", true)
  if bc then bc:Recompute() end
  local reg = LibStub("AceConfigRegistry-3.0", true)
  if reg then reg:NotifyChange("Nock") end
end

--------------------------------------------------------------------------------
-- Press macro builder
--------------------------------------------------------------------------------
-- The Snowball poke and its garment gate live INSIDE the stored macro text, not
-- in profile keys, so these controls read their position back out of that text
-- and write it straight back — exactly what the wizard's extras page does, via
-- the same Core/WeaveMacro.lua helpers. Consequence worth keeping: hand-editing
-- the macro box below moves these switches, and moving these switches rewrites
-- the box, with no third copy of the state to fall out of sync.
local function pressBody() return Nock.db.profile.weaveBindMacroDown or "" end

local function setPressBody(text)
  Nock.db.profile.weaveBindMacroDown = text
  -- The release re-arm follows the poke's gate (the inverse), on a release
  -- body Nock authored (Core/WeaveMacro.lua).
  Nock.WeaveMacro.SyncRearmIfStock(Nock.db.profile, Nock.Constants.WEAVE_BIND_MACRO_UP)
  Nock:SendMessage("NOCK_WEAVEBIND_CHANGED")
  -- The macro box is on the same page and has just changed underneath the user.
  local reg = LibStub("AceConfigRegistry-3.0", true)
  if reg then reg:NotifyChange("Nock") end
end

local function weaveBindOff() return Nock.db.profile.weaveBindEnabled ~= true end

-- The gate controls need something to gate.
local function noPoke()
  return weaveBindOff() or not Nock.WeaveMacro.HasSnowball(pressBody())
end

local function noGate()
  return noPoke() or Nock.WeaveMacro.GateOf(pressBody()) == nil
end

local function lsmValues(mediaType)
  return function()
    local lsm = LibStub("LibSharedMedia-3.0", true)
    if not lsm then return {} end
    local out = {}
    for _, name in ipairs(lsm:List(mediaType)) do
      out[name] = name
    end
    return out
  end
end

-- Sentinel rows in an LSM dropdown ("Reference (built-in)", "Inherit (global)")
-- MUST be keyed by their own label, never by "".
--
-- Every LSM preview widget resolves a row's media as
--     list[key] ~= key and list[key] or LSM:Fetch(mediaType, key)
-- i.e. an entry whose VALUE differs from its KEY is read as "the value IS the
-- media path". A sentinel written as t[""] = "Reference (built-in)" therefore
-- handed the literal string "Reference (built-in)" to FontString:SetFont() —
-- an invalid path — and the resulting error truncated the options panel from
-- that control down. (Textures fail silently, fonts do not: that is why the
-- React tab went blank immediately AFTER the bar texture row.)
--
-- Keeping key == value routes the sentinel through LSM:Fetch instead, which
-- returns the registered default for that media type: a real, valid path. Our
-- own widgets use Fetch(..., true) and skip unknown names entirely.
--
-- The DB still stores "" for the sentinel — mapped in the get/set pair below —
-- so nothing needs migrating and every consumer of the profile key is unchanged.
local function lsmSentinelValues(mediaType, label)
  return function()
    local t = lsmValues(mediaType)()
    t[label] = label
    return t
  end
end

local function lsmSentinelGet(key, label)
  return function()
    local v = Nock.db.profile[key]
    if v == nil or v == "" then return label end
    return v
  end
end

local function lsmSentinelSet(key, label)
  return function(_, v)
    visualsSet(_, key, (v == label) and "" or v)
  end
end

-- Dual-form spell-name lookup (bare GetSpellInfo may be a shim on this
-- client; C_Spell is authoritative).
local function optSpellName(id)
  if GetSpellInfo then
    local n = GetSpellInfo(id)
    if n then return n end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id)
    if i then return i.name end
  end
  return nil
end

local function spellOrItemName(t, id)
  if t == "item" and GetItemInfo then
    local nm = GetItemInfo(id); if nm then return nm end
  else
    local nm = optSpellName(id); if nm then return nm end
  end
  return nil
end

-- Cooldown-catalog entry label + grey annotation, shared by the Cooldown
-- Grid and React HUD tabs. Resolves the module per call (options-UI
-- frequency, cost irrelevant).
local function describe(key)
  local CDMOD = Nock:GetModule("Cooldowns", true)
  local e = CDMOD and CDMOD:GetEntry(key)
  if not e then return key end
  if e.custom then
    local nm = (e.label and e.label ~= "" and e.label) or spellOrItemName(e.type, e.id) or e.key
    return ("%s  |cff808080(custom %s %d%s)|r"):format(
      nm, e.type, e.id, e.procBuff and (", proc " .. e.procBuff) or "")
  end
  local what
  if e.type == "spell"     then what = "spell " .. tostring(e.id)
  elseif e.type == "item"  then what = "item " .. tostring(e.id)
  elseif e.type == "inventory" then what = "trinket slot " .. tostring(e.slot)
  elseif e.type == "specSpell" then what = "spec-aware spell"
  elseif e.type == "raceSpell" then what = "race-aware spell"
  elseif e.type == "altItem"   then what = "item " .. tostring(e.ids and e.ids[1])
  else what = e.type end
  return ("%s  |cff808080(%s)|r"):format(e.label or key, what)
end

-- Sound output channels accepted by PlaySoundFile, in menu order.
local SOUND_CHANNELS = { "Master", "SFX", "Music", "Ambience", "Dialog" }
local SOUND_CHANNEL_LABELS = {
  Master = "Master", SFX = "Sound Effects", Music = "Music",
  Ambience = "Ambience", Dialog = "Dialog",
}
local function soundChannelValues()
  local out = {}
  for _, k in ipairs(SOUND_CHANNELS) do out[k] = SOUND_CHANNEL_LABELS[k] end
  return out
end

-- Play an LSM sound by name through a channel — backs the "Preview" buttons so
-- picking a cue isn't a guessing game. Silent for "None"/missing.
local function previewSound(soundName, channel)
  if not soundName or soundName == "" or soundName == "None" then return end
  local lsm = LibStub("LibSharedMedia-3.0", true)
  if not lsm then return end
  local path = lsm:Fetch("sound", soundName)
  if path and PlaySoundFile then PlaySoundFile(path, channel or "Master") end
end

-- The four swing-bar fill directions, shared by the global select and the per-bar
-- override selects below so the wording can't drift between them.
local FILL_DIR_VALUES = {
  rtl      = "Right-to-left (drain)",
  drainltr = "Left-to-right (drain)",
  ltr      = "Left-to-right (fill)",
  fillrtl  = "Right-to-left (fill)",
}
local FILL_DIR_SORTING = { "rtl", "drainltr", "ltr", "fillrtl" }

-- A per-bar direction override select: the four global modes plus an
-- "Inherit (global)" entry. Same affordance as the per-bar TEXTURE selects
-- above, except the sentinel is "inherit" rather than "" — the value is an enum,
-- not a media name, so "" would be indistinguishable from a genuine unset.
local function fillDirSelect(key, name, desc, order, disabledFn)
  local values = { inherit = "Inherit (global)" }
  for k, v in pairs(FILL_DIR_VALUES) do values[k] = v end
  local sorting = { "inherit" }
  for _, k in ipairs(FILL_DIR_SORTING) do sorting[#sorting + 1] = k end
  return {
    type  = "select",
    name  = name,
    desc  = desc,
    order = order,
    -- Normalise pooled item fonts so this select can't inherit a leaked
    -- typeface from the LSM Font dropdown (shared AceGUI item pool).
    dialogControl = lsmWidget(nil, "plain"),
    values   = values,
    sorting  = sorting,
    disabled = disabledFn,
    get = function() return Nock.db.profile[key] or "inherit" end,
    set = function(_, v) visualsSet(_, key, v) end,
  }
end

-- One rename input per built-in rotation notation (7 turret + 5 weave), built
-- from Nock.Profiles rather than hand-written so the panel can never drift out
-- of sync with the notations the engine actually emits.
--
-- Arg keys are synthesised (rotlbl_1..N) because the notations contain colons and
-- spaces; the notation itself is captured in each closure, so info[#info] is never
-- consulted (unlike the shared get/set pair at the top of this file).
--
-- These are inputs, not selects — no lsmWidget needed. The leaked-typeface problem
-- is specific to AceGUI's shared dropdown item pool.
local function buildRotationLabelArgs(startOrder)
  local out = {}
  local P = Nock.Profiles
  if not P then return out end
  local n = 0
  local function addOne(notation, groupLabel)
    n = n + 1
    out["rotlbl_" .. n] = {
      type  = "input",
      name  = notation,
      desc  = ("Display name for the %s notation \"%s\". Leave blank to show the built-in notation."):format(groupLabel, notation),
      order = startOrder + n * 0.001,
      get   = function()
        local m = Nock.db.profile.rotationLabels
        return (m and m[notation]) or ""
      end,
      set   = function(_, v)
        local m = Nock.db.profile.rotationLabels
        if not m then m = {}; Nock.db.profile.rotationLabels = m end
        v = v and v:match("^%s*(.-)%s*$") or ""
        -- Store nil (not "") for blank so "blank = built-in" holds on read and
        -- cleared fields leave no junk behind in SavedVariables.
        m[notation] = (v ~= "") and v or nil
        Nock:SendMessage("NOCK_VISUALS_CHANGED")
      end,
    }
    -- Companion color swatch, keyed by the same BUILT-IN notation (never the
    -- rename). White reads as "no custom color" for display purposes; the
    -- group's "Reset colors" execute is the way back to the true site
    -- defaults (the Shot Bars label, for one, is muted white).
    out["rotcol_" .. n] = {
      type = "color",
      name = "Color",
      desc = ("Label color for \"%s\" everywhere it renders (React notation, Auto Shot bar, Shot Bars)."):format(notation),
      hasAlpha = true,
      width = 0.6,
      order = startOrder + n * 0.001 + 0.0005,
      get = function()
        local m = Nock.db.profile.rotationLabelColors
        local c = m and m[notation]
        if type(c) == "table" and c[1] then
          return c[1], c[2], c[3], c[4] or 1
        end
        return 1, 1, 1, 1
      end,
      set = function(_, r, g, b, a)
        local m = Nock.db.profile.rotationLabelColors
        if not m then m = {}; Nock.db.profile.rotationLabelColors = m end
        m[notation] = { r, g, b, a }
        Nock:SendMessage("NOCK_VISUALS_CHANGED")
      end,
    }
  end
  for _, p in ipairs(P.list or {}) do addOne(p.name, "turret") end
  for _, w in ipairs(P.weaveList or {}) do addOne(w, "weave") end
  return out
end

-- Build a single warning's inline group from a catalog entry. Each shows the
-- representative icon + description + chain-logic, an enable toggle, optional
-- extra toggles (e.g. "Combat only"), and threshold sliders.
local function buildWarningGroup(cat, baseOrder)
  local args = {
    info = {
      type        = "description",
      name        = cat.description .. "\n\n|cff909090Triggers when:|r\n" .. cat.logic,
      order       = 1,
      image       = function() return cat.iconFn and cat.iconFn() or nil end,
      imageWidth  = 36,
      imageHeight = 36,
      fontSize    = "medium",
    },
    enabled = {
      type  = "toggle",
      name  = "Enabled",
      order = 2,
      width = "full",
      get   = function() return Nock.db.profile[cat.enabledKey] end,
      set   = function(_, v) Nock.db.profile[cat.enabledKey] = v end,
    },
  }
  if cat.extraToggles then
    for i, t in ipairs(cat.extraToggles) do
      args["extra_" .. t.key] = {
        type     = "toggle",
        name     = t.label,
        order    = 3 + i,
        width    = "full",
        disabled = function() return not Nock.db.profile[cat.enabledKey] end,
        -- A toggle may read and write something other than the profile (the
        -- Slammer's drunk-effect box is a CVar); t.key then only names the
        -- control.
        get      = t.get or function() return Nock.db.profile[t.key] end,
        set      = t.set and function(_, v) t.set(v) end
                   or function(_, v) Nock.db.profile[t.key] = v end,
      }
    end
  end
  if cat.thresholds then
    for i, th in ipairs(cat.thresholds) do
      args["th_" .. th.key] = {
        type     = "range",
        name     = th.label,
        min      = th.min, max = th.max, step = th.step,
        order    = 10 + i,
        disabled = function() return not Nock.db.profile[cat.enabledKey] end,
        get      = function() return Nock.db.profile[th.key] end,
        set      = function(_, v) Nock.db.profile[th.key] = v end,
      }
    end
  end
  if cat.inputs then
    -- Free-text inputs (e.g. comma-separated item-ID lists). Each setter
    -- broadcasts NOCK_VISUALS_CHANGED so the warning module can rebuild its
    -- parsed cache without a /reload (mirrors the helpersHideWA wiring).
    for i, inp in ipairs(cat.inputs) do
      args["input_" .. inp.key] = {
        type     = "input",
        name     = inp.label,
        desc     = inp.desc,
        order    = 30 + i,
        width    = "full",
        multiline = inp.multiline,
        disabled = function() return not Nock.db.profile[cat.enabledKey] end,
        get      = function() return Nock.db.profile[inp.key] or "" end,
        set      = function(_, v) visualsSet(_, inp.key, v) end,
      }
    end
  end
  if cat.mediaSelectors then
    -- LSM-backed dropdowns (e.g. a "sound on resist" picker). Includes a
    -- synthetic "None" entry so users can mute the warning without uninstalling.
    for i, m in ipairs(cat.mediaSelectors) do
      args["media_" .. m.key] = {
        type     = "select",
        name     = m.label,
        order    = 20 + i,
        disabled = function() return not Nock.db.profile[cat.enabledKey] end,
        -- Fall back to the plain widget when the media type has no dedicated
        -- preview widget (e.g. "sound") so it can't inherit a leaked typeface
        -- from the LSM Font dropdown (shared AceGUI item pool).
        dialogControl = lsmWidget(nil, m.mediaType) or lsmWidget(nil, "plain"),
        values   = function()
          local lsm = LibStub("LibSharedMedia-3.0", true)
          local out = { ["None"] = "None" }
          if lsm then
            for _, name in ipairs(lsm:List(m.mediaType)) do out[name] = name end
          end
          return out
        end,
        get = function() return Nock.db.profile[m.key] end,
        set = function(_, v) Nock.db.profile[m.key] = v end,
      }
      -- A "Preview" button next to each SOUND picker (warning sounds play on the
      -- Master channel). Greyed out when muted ("None") or the warning is off.
      if m.mediaType == "sound" then
        args["mediaplay_" .. m.key] = {
          type     = "execute",
          name     = "Preview",
          order    = 20 + i + 0.5,
          width    = "half",
          disabled = function()
            return not Nock.db.profile[cat.enabledKey]
              or (Nock.db.profile[m.key] or "None") == "None"
          end,
          func     = function() previewSound(Nock.db.profile[m.key], "Master") end,
        }
      end
    end
  end
  return {
    type   = "group",
    name   = cat.name,
    order  = baseOrder,
    inline = true,
    args   = args,
  }
end

-- Build a single setup-check inline group. Status badge + description re-read
-- each render so the panel reflects the live state after the fix runs.
local function buildSetupCheckGroup(check, baseOrder)
  local args = {
    info = {
      type  = "description",
      order = 1,
      name  = function()
        local ok, detail = check.check()
        local badge = ok and "|cff20c020Pass|r" or "|cffff4040Fail|r"
        local body  = badge .. " — " .. check.desc
        if detail ~= nil and check.formatDetail then
          body = body .. "\n\n" .. check.formatDetail(detail)
        end
        return body
      end,
      fontSize = "medium",
    },
  }
  local function notifyChange()
    local reg = LibStub("AceConfigRegistry-3.0", true)
    if reg then reg:NotifyChange("Nock") end
  end
  if check.actions and check.applyAction then
    -- Multi-button row (e.g. SpellQueueWindow: 100 / 200 / 400). The button
    -- matching the currently-applied value is disabled so the active state is
    -- visible at a glance.
    for i, action in ipairs(check.actions) do
      args["action_" .. i] = {
        type  = "execute",
        order = 1 + i,
        name  = action.label,
        disabled = function()
          return check.actionIsCurrent and check.actionIsCurrent(action)
        end,
        func = function()
          check.applyAction(action)
          notifyChange()
        end,
      }
    end
  elseif check.fix then
    args.fix = {
      type  = "execute",
      order = 2,
      name  = check.fixLabel or "Fix",
      disabled = function() return (check.check()) end,  -- already passing
      func = function()
        check.fix()
        notifyChange()
      end,
    }
  end
  return {
    type   = "group",
    name   = check.name,
    order  = baseOrder,
    inline = true,
    args   = args,
  }
end

-- Set by the debuff-tracker row injector at the end of buildOptionsTable;
-- the tracker's Restore / custom-box handlers call it to re-list the rows
-- (the group moves into the `trackers` family after injection, so a path
-- lookup at click time would miss it).
local dbfRebuildEntries

local function buildOptionsTable()
  -- The HUD look picker appears in three homes: General → HUD look
  -- (canonical), the HUD & Bars landing page, and the React HUD landing
  -- page. One builder so the copies cannot drift; a fresh table per home so
  -- order/desc may differ. Setting it pokes the registry so the branch
  -- "(active)" badges repaint immediately.
  local function hudModeSelect(order, homeNote)
    return {
      type = "select",
      name = "HUD look",
      desc = "\"Classic\" = the configurable row stack. \"React\" = the fixed-skin replica."
        .. (homeNote and ("\n\n" .. homeNote) or ""),
      order = order,
      values = { classic = "Classic", react = "React" },
      sorting = { "classic", "react" },
      dialogControl = lsmWidget(nil, "plain"),  -- LSM Font leak guard
      get = function() return Nock.db.profile.hudMode or "classic" end,
      set = function(_, v)
        visualsSet(_, "hudMode", v)
        local reg = LibStub("AceConfigRegistry-3.0", true)
        if reg then reg:NotifyChange("Nock") end
      end,
    }
  end

  -- Weave engine tunables — consumed by the rotation engine in BOTH looks,
  -- so they render on both timing pages (Classic → Shot Bars via grpEngine
  -- and React → Bars). One builder, a fresh table per home. Deliberately not
  -- react-gated on the React copy.
  local function weaveEngineArgs()
    return {
      rotQuiverEquipped = {
        type = "toggle",
        name = "Assume quiver / ammo pouch equipped",
        desc = "Adds the +15% ranged attack speed bonus from a quiver or ammo pouch to clip-window math. Disable if your bag setup doesn't include one.",
        order = 10,
        width = "full",
        get = function() return Nock.db.profile.rotQuiverEquipped end,
        set = function(_, v) Nock.db.profile.rotQuiverEquipped = v end,
      },
      rotRaptorWeaveHeadroom = {
        type = "range",
        name = "Raptor Strike swing headroom (s)",
        desc = "Minimum seconds remaining on the ranged swing timer before Raptor Strike is suggested. Lower = more aggressive weave; higher = safer.",
        min = 0.3, max = 2.0, step = 0.05, bigStep = 0.1,
        order = 20,
        get = function() return Nock.db.profile.rotRaptorWeaveHeadroom end,
        set = function(_, v) Nock.db.profile.rotRaptorWeaveHeadroom = v end,
      },
      rotWeaveProxMin = {
        type = "range",
        name = "Weave band — outer edge",
        desc = "Proximity-bar position where the weave helper STARTS firing (further from melee). -0.10 = CLOSE band start.",
        min = -0.15, max = 0.0, step = 0.01,
        order = 30,
        get = function() return Nock.db.profile.rotWeaveProxMin end,
        set = function(_, v) Nock.db.profile.rotWeaveProxMin = v end,
      },
      rotWeaveProxMax = {
        type = "range",
        name = "Weave band — inner edge",
        desc = "Proximity-bar position where the weave helper STOPS firing (closer to melee). 0.0 = melee threshold itself; staying in-melee still triggers regardless.",
        min = -0.10, max = 0.05, step = 0.01,
        order = 40,
        get = function() return Nock.db.profile.rotWeaveProxMax end,
        set = function(_, v) Nock.db.profile.rotWeaveProxMax = v end,
      },
    }
  end

  -- Cast bar behavior, mirrored between General → Cast bar and the Classic
  -- branch's Cast Bar page. showAutoShotCast drives only the CLASSIC cast
  -- bar (React has its own reactShowAutoShotCast); castBarNonCombatCasts
  -- feeds Modules/CastBar.lua in both looks, so that one additionally
  -- mirrors into React → Size & Elements.
  local function castBarSharedArgs(note)
    local suffix = note and ("\n\n" .. note) or ""
    return {
      showAutoShotCast = {
        type = "toggle",
        name = "Show Auto Shot in cast bar",
        desc = "Display the 0.5s Auto Shot wind-up on the classic cast bar. Off by default — Auto Shot is tracked by the swing timer instead. The React HUD has its own toggle under React HUD → Size & Elements (on by default there)." .. suffix,
        order = 40,
        width = "full",
        get = get,
        set = set,
      },
      castBarNonCombatCasts = {
        type = "toggle",
        name = "Show non-combat casts in cast bar",
        desc = "Also show mounts, Hearthstone, First Aid, Cooking and other non-combat casts on the cast bar.\n\nOff by default. The cast bar is normally driven by the combat log, which is the only reliable source for ranged shots like Multi-Shot — but the combat log never logs a mount summon, so these casts have no trigger at all without this. Turning it on adds a second, independent trigger for exactly those casts.\n\nCombat casts are unaffected either way." .. suffix,
        order = 40.1,
        width = "full",
        get = function() return Nock.db.profile.castBarNonCombatCasts == true end,
        set = function(_, v) visualsSet(_, "castBarNonCombatCasts", v) end,
      },
      hideBlizzardCastBar = {
        type = "toggle",
        name = "Hide Blizzard's cast bar",
        desc = "Hide the default Blizzard player cast bar so only Nock's cast bar shows. Turning it back off re-enables the default bar immediately when the client allows it; otherwise a /reload restores it (you'll get a chat note if so)." .. suffix,
        order = 40.2,
        width = "full",
        get = function() return Nock.db.profile.hideBlizzardCastBar == true end,
        set = function(_, v) visualsSet(_, "hideBlizzardCastBar", v) end,
      },
    }
  end

  -- Custom cooldown-entry registry (profile.cooldownCustom), shared by both
  -- grid pages. Each page registers a rebuild callback; any add/remove from
  -- either page refreshes both and pokes the registry once.
  local customEntryRebuilds = {}
  local function customEntriesChanged()
    Nock:SendMessage("NOCK_VISUALS_CHANGED")
    for _, fn in ipairs(customEntryRebuilds) do fn() end
    local reg = LibStub("AceConfigRegistry-3.0", true)
    if reg then reg:NotifyChange("Nock") end
  end
  local function customEntryKey(rec)
    return (type(rec.key) == "string" and rec.key ~= "" and rec.key)
      or ("c_" .. tostring(rec.type) .. "_" .. tostring(rec.id))
  end
  local function genCustomKey(t, id)
    local list = Nock.db.profile.cooldownCustom or {}
    local base, k, n = "c_" .. t .. "_" .. id, nil, 1
    k = base
    local function taken(kk)
      for _, e in ipairs(list) do
        local ek = (type(e.key) == "string" and e.key) or ("c_" .. tostring(e.type) .. "_" .. tostring(e.id))
        if ek == kk then return true end
      end
      return false
    end
    while taken(k) do n = n + 1; k = base .. "_" .. n end
    return k
  end
  local function removeCustomEntry(key)
    local list = Nock.db.profile.cooldownCustom or {}
    for i, rec in ipairs(list) do
      if customEntryKey(rec) == key then table.remove(list, i); break end
    end
    if Nock.db.profile.cooldownDisabled then Nock.db.profile.cooldownDisabled[key] = nil end
    customEntriesChanged()
  end
  local function addCustomEntry(stage)
    local id = tonumber(stage.id)
    if not id or id <= 0 then return end
    local t = (stage.type == "item") and "item" or "spell"
    local p = Nock.db.profile
    p.cooldownCustom = p.cooldownCustom or {}
    local rec = { key = genCustomKey(t, id), type = t, id = id }
    if stage.proc and stage.proc > 0 then rec.procBuff = stage.proc end
    if stage.label and stage.label ~= "" then rec.label = stage.label end
    p.cooldownCustom[#p.cooldownCustom + 1] = rec
    stage.id, stage.proc, stage.label = nil, nil, nil
    customEntriesChanged()
  end
  -- The add form, rendered identically on both grid pages. `stage` persists
  -- across rebuilds and belongs to the calling page.
  local function buildCustomAddForm(target, startOrder, stage)
    target.addHeader = { type = "header", name = "Add a custom spell / item", order = startOrder }
    target.addType = {
      type = "select", name = "Type", order = startOrder + 1, width = 0.8,
      dialogControl = lsmWidget(nil, "plain"),
      values = { spell = "Spell", item = "Item" },
      get = function() return stage.type end,
      set = function(_, v) stage.type = v end,
    }
    target.addId = {
      type = "input", name = "Spell / Item ID", order = startOrder + 2, width = 0.9,
      get = function() return stage.id and tostring(stage.id) or "" end,
      set = function(_, v) stage.id = tonumber(v) end,
    }
    target.addProc = {
      type = "input", name = "Proc buff ID (optional)", order = startOrder + 3, width = 1.0,
      desc = "When this aura is on you the slot glows and shows the buff's remaining time.",
      get = function() return stage.proc and tostring(stage.proc) or "" end,
      set = function(_, v) stage.proc = tonumber(v) end,
    }
    target.addLabel = {
      type = "input", name = "Label (optional)", order = startOrder + 4, width = 1.0,
      get = function() return stage.label or "" end,
      set = function(_, v) stage.label = (v ~= "" and v) or nil end,
    }
    target.addBtn = {
      type = "execute", name = "Add entry", order = startOrder + 5, width = 0.7,
      disabled = function() return not (stage.id and stage.id > 0) end,
      func = function() addCustomEntry(stage) end,
    }
  end

  local options = {
    type = "group",
    name = "Nock",
    args = {
      general = {
        type = "group",
        name = "General",
        order = 1,
        args = {
          intro = {
            type = "description",
            name = "Hunter combat HUD — drag the panel when unlocked.\n",
            order = 1,
            fontSize = "medium",
          },
          scale = {
            type = "range",
            name = "Scale",
            desc = "Overall HUD scale.",
            min = 0.5, max = 2.0, step = 0.05, bigStep = 0.1,
            order = 10,
            get = get,
            set = function(_, v) visualsSet(_, "scale", v) end,
          },
          opacityNote = {
            type = "description",
            name = function()
              if Nock.IsLocked() then
                return "|cff55ff55The HUD is LOCKED|r — the opacity and 'Hide out of combat' settings below are active."
              end
              return "|cffff6060The HUD is UNLOCKED, so the opacity and 'Hide out of combat' settings below do nothing yet.|r An unlocked HUD always stays fully visible so you can drag it. Lock all frames (the button on the General page, or /nock lock) to apply them."
            end,
            order = 19,
            fontSize = "medium",
          },
          opacity = {
            type = "range",
            name = "Opacity (in combat)",
            desc = "HUD alpha while in combat. Applies only when the HUD is locked.",
            min = 0.1, max = 1.0, step = 0.05, bigStep = 0.1,
            order = 20,
            get = get,
            set = function(_, v) visualsSet(_, "opacity", v) end,
          },
          opacityOoc = {
            type = "range",
            name = "Opacity (out of combat)",
            desc = "HUD alpha when not in combat. Applies only when the HUD is locked; ignored if 'Hide out of combat' is on.",
            min = 0.0, max = 1.0, step = 0.05, bigStep = 0.1,
            order = 22,
            disabled = function() return Nock.db.profile.hideOoc end,
            get = get,
            set = function(_, v) visualsSet(_, "opacityOoc", v) end,
          },
          hideOoc = {
            type = "toggle",
            name = "Hide out of combat",
            desc = "Fully hide the HUD when out of combat — except while practice mode is on, which keeps it up. Also hides the buff tracker and the Misdirection panel while you are RESTED (an inn or a city). Applies only when the HUD is locked (an unlocked HUD always stays visible so you can drag it).",
            order = 24,
            get = get,
            set = function(_, v) visualsSet(_, "hideOoc", v) end,
          },
          reactHeader = {
            type = "header",
            name = "React HUD",
            order = 25,
          },
          reactNote = {
            type = "description",
            fontSize = "medium",
            order = 25.5,
            name = "Fixed-skin replica of the React hunter WeakAura, replacing the classic rows entirely. All React settings live under |cffffd100HUD & Bars → React HUD|r. Toggle quickly with /nock react.",
          },
          hudMode = hudModeSelect(26, "(same setting as the HUD & Bars page)"),
          lockState = {
            type = "description",
            fontSize = "medium",
            order = 29.9,
            name = function()
              if Nock.IsLocked() then
                return "|cff55ff55All frames are locked.|r"
              end
              return "|cffff6060All frames are UNLOCKED|r — green edit borders are showing; drag anything to move it."
            end,
          },
          lockAll = {
            type = "execute",
            name = "Lock all frames",
            desc = "Freeze every movable frame in place: the HUD, medallion, Misdirection panel, buff/debuff trackers, shopping list, and free-layout rows. Same as /nock lock.",
            order = 30,
            width = 1.2,
            disabled = function() return Nock.IsLocked() end,
            func = function()
              Nock:SetLocked(true)
              -- Re-draw the open dialog so the disabled pair + state line flip.
              local reg = LibStub("AceConfigRegistry-3.0", true)
              if reg then reg:NotifyChange("Nock") end
            end,
          },
          unlockAll = {
            type = "execute",
            name = "Unlock all frames",
            desc = "Unlock every movable frame so you can drag it — green edit borders appear on the HUD, medallion, Misdirection panel, buff/debuff trackers, shopping list, and free-layout rows. Same as /nock unlock.",
            order = 30.05,
            width = 1.2,
            disabled = function() return not Nock.IsLocked() end,
            func = function()
              Nock:SetLocked(false)
              local reg = LibStub("AceConfigRegistry-3.0", true)
              if reg then reg:NotifyChange("Nock") end
            end,
          },
          editGridHeader = { type = "header", name = "Edit-mode grid", order = 30.06 },
          editGridShow = {
            type = "toggle", name = "Show grid while unlocked", order = 30.07, width = "full",
            desc = "A raster overlay behind every frame while unlocked, with a control panel at the top of the screen (drag the panel anywhere). Same switches as on that panel.",
            get = function() return Nock.db.profile.editGridShow ~= false end,
            set = function(_, v) Nock.db.profile.editGridShow = v and true or false; Nock:SendMessage("NOCK_EDITGRID_CHANGED") end,
          },
          editGridSize = {
            type = "range", name = "Raster", order = 30.08, min = 4, max = 64, step = 2,
            desc = "Grid spacing in screen units.",
            get = function() return Nock.db.profile.editGridSize or 16 end,
            set = function(_, v) Nock.db.profile.editGridSize = v; Nock:SendMessage("NOCK_EDITGRID_CHANGED") end,
          },
          editGridSnap = {
            type = "select", name = "Snap to grid", order = 30.09,
            desc = "Off: frames land where you drop them. On release: a dropped frame is moved onto the grid. While dragging: a ghost outline shows where it will land, then it snaps on release. While snapping, a nudge-pad step is one raster.",
            values = { off = "Off", release = "On release", drag = "While dragging (ghost)" },
            sorting = { "off", "release", "drag" },
            dialogControl = lsmWidget(nil, "plain"),
            get = function() return Nock.UI.EditSnapMode(Nock.db.profile) end,
            set = function(_, v) Nock.db.profile.editGridSnap = v; Nock:SendMessage("NOCK_EDITGRID_CHANGED") end,
          },
          editSnapBy = {
            type = "select", name = "Snap by", order = 30.095,
            desc = "Nearest: per axis, whichever of the frame's edges or centre is closest to a grid line lands on it (a centred bar stays centred, a corner-aligned panel stays cornered). Corner: the top-left corner always.",
            values = { nearest = "Nearest edge or centre", corner = "Top-left corner" },
            sorting = { "nearest", "corner" },
            dialogControl = lsmWidget(nil, "plain"),
            get = function() return Nock.db.profile.editSnapBy or "nearest" end,
            set = function(_, v) Nock.db.profile.editSnapBy = v; Nock:SendMessage("NOCK_EDITGRID_CHANGED") end,
          },
          minimapIcon = {
            type = "toggle",
            name = "Minimap icon",
            desc = "The Nock button on the minimap: left-click opens these settings, right-click locks or unlocks all frames. Same as /nock minimap.",
            order = 30.1,
            width = "full",
            get = function() return Nock.IsMinimapShown and Nock:IsMinimapShown() or false end,
            set = function(_, v) if Nock.SetMinimapShown then Nock:SetMinimapShown(v) end end,
          },
          perfPanel = {
            type = "toggle",
            name = "Performance panel",
            desc = "A small draggable panel: memory (and, with the client's scriptProfile CVar on, CPU) for all addons and for Nock, plus a Capture button that records what Nock spends and allocates per module for up to 60 s and opens the report. Same as /nock profile show. Costs nothing while idle -- one timer per second.",
            order = 30.15,
            width = "full",
            get = function()
              local m = Nock:GetModule("Profiler", true)
              return (m and m.overlay and m.overlay:IsShown()) or (Nock.db.profile.profilerOverlayShown == true)
            end,
            set = function(_, v)
              local m = Nock:GetModule("Profiler", true)
              if m and m.ShowOverlay then m:ShowOverlay(v) else Nock.db.profile.profilerOverlayShown = v and true or false end
            end,
          },
          runWizard = {
            type = "execute",
            name = "Run setup wizard",
            desc = "Replay the first-run setup. All frames unlock while it is open (drag them into place) and lock again when it closes. Your existing choices are kept. Opens out of combat only.",
            order = 30.2,
            func = function()
              LibStub("AceConfigDialog-3.0"):Close("Nock")
              -- Launched from the Blizzard AddOns panel, that fullscreen window
              -- would otherwise stay up over the wizard's live HUD previews.
              local blizz = _G.SettingsPanel or _G.InterfaceOptionsFrame
              if blizz and blizz.IsShown and blizz:IsShown() and HideUIPanel then
                HideUIPanel(blizz)
              end
              local m = Nock:GetModule("Onboarding", true)
              if m and m.Command then m:Command() end
            end,
          },
          bgHeader = {
            type = "header",
            name = "Background",
            order = 30.4,
          },
          backgroundNote = {
            type = "description",
            name = "The backdrop box only shows while the HUD is locked — an unlocked HUD always shows a grabbable box so you can drag it.",
            order = 30.45,
            fontSize = "medium",
          },
          backgroundFreeNote = {
            type = "description",
            name = "|cffffcc00Free placement is on (Layout tab):|r the HUD box is hidden entirely — every piece is its own draggable frame. These fill/border settings still apply to the side panels.",
            order = 30.46,
            fontSize = "medium",
            hidden = function() return not Nock.FreeLayoutActive() end,
          },
          backgroundEnabled = {
            type = "toggle",
            name = "Show background",
            desc = "Show the solid backdrop box + border behind the HUD. Off removes it entirely so it stops blocking your view.",
            order = 30.5,
            width = "full",
            get = function() return Nock.db.profile.backgroundEnabled ~= false end,
            set = function(_, v) visualsSet(_, "backgroundEnabled", v) end,
          },
          backgroundColor = {
            type = "color",
            name = "Background color",
            desc = "Fill color of the backdrop box (the border has its own color below).",
            order = 30.6,
            hasAlpha = false,
            disabled = function() return Nock.db.profile.backgroundEnabled == false end,
            get = function()
              local c = Nock.db.profile.backgroundColor or { 0, 0, 0 }
              return c[1] or 0, c[2] or 0, c[3] or 0
            end,
            set = function(_, r, g, b)
              Nock.db.profile.backgroundColor = { r, g, b }
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          backgroundOpacity = {
            type = "range",
            name = "Background opacity",
            desc = "Backdrop fill alpha. 0 = transparent fill (set this to 0 with a border for an outline-only look).",
            min = 0, max = 0.95, step = 0.05, bigStep = 0.1,
            order = 30.7,
            disabled = function() return Nock.db.profile.backgroundEnabled == false end,
            get = function() return Nock.db.profile.backgroundOpacity or 0.85 end,
            set = function(_, v) visualsSet(_, "backgroundOpacity", v) end,
          },
          hudBorder = {
            type = "select",
            name = "Border style",
            desc = "Border texture for the HUD box. Sourced from LibSharedMedia. 'None' keeps the original 1px solid line.",
            order = 30.75,
            dialogControl = lsmWidget(nil, "plain"),
            disabled = function() return Nock.db.profile.backgroundEnabled == false end,
            values = function()
              local lsm = LibStub("LibSharedMedia-3.0", true)
              local out = { ["None"] = "None (1px)" }
              if lsm then
                for _, name in ipairs(lsm:List("border")) do
                  out[name] = name
                end
              end
              return out
            end,
            get = function() return Nock.db.profile.hudBorder or "None" end,
            set = function(_, v) visualsSet(_, "hudBorder", v) end,
          },
          hudBorderSize = {
            type = "range",
            name = "Border thickness",
            desc = "Border edge size (px). Only applies when a LibSharedMedia border is selected — most LSM borders look best around 8-16.",
            min = 1, max = 32, step = 1,
            order = 30.8,
            disabled = function()
              local p = Nock.db.profile
              local b = p.hudBorder
              return p.backgroundEnabled == false or not b or b == "None" or b == ""
            end,
            get = function() return Nock.db.profile.hudBorderSize or 12 end,
            set = function(_, v) visualsSet(_, "hudBorderSize", v) end,
          },
          hudBorderColor = {
            type = "color",
            name = "Border color",
            desc = "Tint of the HUD border (separate from the fill color).",
            order = 30.85,
            hasAlpha = false,
            disabled = function() return Nock.db.profile.backgroundEnabled == false end,
            get = function()
              local c = Nock.db.profile.hudBorderColor or { 0, 0, 0 }
              return c[1] or 0, c[2] or 0, c[3] or 0
            end,
            set = function(_, r, g, b)
              Nock.db.profile.hudBorderColor = { r, g, b }
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          hudBorderOpacity = {
            type = "range",
            name = "Border opacity",
            desc = "Border alpha. 0 = invisible border (fill only).",
            min = 0, max = 1.0, step = 0.05, bigStep = 0.1,
            order = 30.87,
            disabled = function() return Nock.db.profile.backgroundEnabled == false end,
            get = function() return Nock.db.profile.hudBorderOpacity or 1.0 end,
            set = function(_, v) visualsSet(_, "hudBorderOpacity", v) end,
          },
          -- (cast bar pair injected from castBarSharedArgs() below — it also
          -- renders as the Classic branch's Cast Bar node; the grpCastBar
          -- regroup at the bottom of this file gathers it exactly as before)
          mediaHeader = {
            type = "header",
            name = "Media",
            order = 44,
          },
          barTexture = {
            type = "select",
            name = "Bar texture",
            desc = "Texture used for all status bars (cast bar, swing timers, proximity bar). Sourced from LibSharedMedia.\n\nDefault is \"Nock Clean\", which ships with Nock — so it's always available and the HUD looks the same for everyone. The rest of the list comes from whatever media addons you have installed (SharedMedia, WeakAuras, etc.), so those won't match on a machine without them.",
            order = 45,
            dialogControl = lsmWidget(nil, "statusbar"),
            values = lsmValues("statusbar"),
            get = function() return Nock.db.profile.barTexture end,
            set = function(_, v) visualsSet(_, "barTexture", v) end,
          },
          fontFace = {
            type = "select",
            name = "Font",
            desc = "Font used by HUD overlays (cooldown text, range labels, swing timers). Warning labels have their own font setting in the Warnings tab.",
            order = 46,
            dialogControl = lsmWidget(nil, "font"),
            values = lsmValues("font"),
            get = function() return Nock.db.profile.fontFace end,
            set = function(_, v) visualsSet(_, "fontFace", v) end,
          },
          iconBorder = {
            type = "select",
            name = "Icon border",
            desc = "Border style for every icon slot (rotation row, cooldown grid, warning squares). Sourced from LibSharedMedia. 'None' keeps the original 1px solid line.",
            order = 47,
            dialogControl = lsmWidget(nil, "plain"),
            values = function()
              local lsm = LibStub("LibSharedMedia-3.0", true)
              local out = { ["None"] = "None (1px)" }
              if lsm then
                for _, name in ipairs(lsm:List("border")) do
                  out[name] = name
                end
              end
              return out
            end,
            get = function() return Nock.db.profile.iconBorder end,
            set = function(_, v) visualsSet(_, "iconBorder", v) end,
          },
          iconBorderSize = {
            type = "range",
            name = "Border thickness",
            desc = "Border edge size (px). Only applies when a LibSharedMedia border is selected — most LSM borders look best around 8-12.",
            min = 1, max = 16, step = 1,
            order = 48,
            disabled = function()
              local b = Nock.db.profile.iconBorder
              return not b or b == "None" or b == ""
            end,
            get = function() return Nock.db.profile.iconBorderSize end,
            set = function(_, v) visualsSet(_, "iconBorderSize", v) end,
          },
          resetPos = {
            type = "execute",
            name = "Reset position",
            desc = "Snap the HUD back to center-bottom of the screen.",
            order = 50,
            func = function()
              Nock.db.profile.position = Nock:GetDefaultPosition()
              Nock:SendMessage("NOCK_POSITION_RESET")
            end,
          },

          setupCheckHeader = {
            type = "header",
            name = "Setup Check",
            order = 60,
          },
          setupCheckIntro = {
            type = "description",
            name = "Pre-flight checks for a clean hunter weaving setup. Nock prints a one-line hint at login if anything here fails — the full breakdown lives below.",
            order = 61,
            fontSize = "medium",
          },
          -- Per-check inline groups are injected after this static table is
          -- built (see the loop near the bottom of buildOptionsTable).
        },
      },
      swingBars = {
        type = "group",
        name = "Swing Bars",
        order = 4.5,
        args = {
          intro = {
            type = "description",
            name = "The Auto Shot and melee swing bars, the GCD sweep, and how they all fill. These bars also honour the global Scale (General tab) and the per-row Swing timers scale (Classic HUD → Layout).\n",
            order = 1,
            fontSize = "medium",
          },
          swingBarsHeader = {
            type = "header",
            name = "Swing bars",
            order = 40.02,
          },
          showAutoShotBar = {
            type = "toggle",
            name = "Show Auto Shot bar",
            desc = "Display the tall ranged swing bar (the one with the Auto Shot icon, clip ticks, and rotation name). Off hides it; if both swing bars are off the whole swing row collapses.",
            order = 40.04,
            width = "full",
            get = function() return Nock.db.profile.showAutoShotBar ~= false end,
            set = function(_, v) visualsSet(_, "showAutoShotBar", v) end,
          },
          autoShotBarRotationText = {
            type = "toggle",
            name = "Auto Shot bar rotation text",
            desc = "Show the rotation notation (e.g. \"1:1\", or the weave pattern) centred on the Auto Shot bar. Off hides just the text, keeping the bar.",
            order = 40.05,
            width = "full",
            disabled = function() return Nock.db.profile.showAutoShotBar == false end,
            get = function() return Nock.db.profile.autoShotBarRotationText ~= false end,
            set = function(_, v) visualsSet(_, "autoShotBarRotationText", v) end,
          },
          autoShotShowIcon = {
            type = "toggle",
            name = "Auto Shot icon",
            desc = "Show the Auto Shot spell icon beside the bar. Off stretches the bar to full width.",
            order = 40.06,
            disabled = function() return Nock.db.profile.showAutoShotBar == false end,
            get = function() return Nock.db.profile.autoShotShowIcon ~= false end,
            set = function(_, v) visualsSet(_, "autoShotShowIcon", v) end,
          },
          autoShotBarHeight = {
            type = "range",
            name = "Auto Shot bar height",
            desc = "Height of the Auto Shot bar in pixels (before scaling).",
            min = 8, max = 40, step = 1,
            order = 40.08,
            disabled = function() return Nock.db.profile.showAutoShotBar == false end,
            get = function() return Nock.db.profile.autoShotBarHeight or 20 end,
            set = function(_, v) visualsSet(_, "autoShotBarHeight", v) end,
          },
          autoShotBarTexture = {
            type = "select",
            name = "Auto Shot bar texture",
            desc = "Status bar texture for the Auto Shot bar. 'Inherit (global)' uses the global Bar texture.",
            order = 40.10,
            dialogControl = lsmWidget(nil, "statusbar"),
            values = lsmSentinelValues("statusbar", "Inherit (global)"),
            disabled = function() return Nock.db.profile.showAutoShotBar == false end,
            get = lsmSentinelGet("autoShotBarTexture", "Inherit (global)"),
            set = lsmSentinelSet("autoShotBarTexture", "Inherit (global)"),
          },
          autoShotBarColor = {
            type = "color",
            name = "Auto Shot bar color",
            desc = "Fill color of the Auto Shot bar.",
            hasAlpha = true,
            order = 40.102,
            disabled = function() return Nock.db.profile.showAutoShotBar == false end,
            get = getColor,
            set = setColor,
          },
          clipTickSteadyColor = {
            type = "color",
            name = "Clip tick: Steady",
            desc = "The tick marking where a Steady Shot cast would clip the next Auto Shot (default red).",
            hasAlpha = true,
            order = 40.104,
            disabled = function() return Nock.db.profile.showAutoShotBar == false end,
            get = getColor,
            set = setColor,
          },
          clipTickSteadyWidth = {
            type = "range",
            name = "Clip tick: Steady width",
            desc = "Width of the Steady clip tick, in real screen pixels (independent of your UI scale).",
            min = 1, max = 8, step = 1,
            order = 40.105,
            disabled = function() return Nock.db.profile.showAutoShotBar == false end,
            get = function() return tonumber(Nock.db.profile.clipTickSteadyWidth) or 1 end,
            set = function(_, v) Nock.db.profile.clipTickSteadyWidth = v; Nock:SendMessage("NOCK_VISUALS_CHANGED") end,
          },
          clipTickMultiColor = {
            type = "color",
            name = "Clip tick: Multi",
            desc = "The tick marking where a Multi-Shot cast would clip the next Auto Shot (default orange).",
            hasAlpha = true,
            order = 40.106,
            disabled = function() return Nock.db.profile.showAutoShotBar == false end,
            get = getColor,
            set = setColor,
          },
          clipTickMultiWidth = {
            type = "range",
            name = "Clip tick: Multi width",
            desc = "Width of the Multi clip tick, in real screen pixels (independent of your UI scale).",
            min = 1, max = 8, step = 1,
            order = 40.107,
            disabled = function() return Nock.db.profile.showAutoShotBar == false end,
            get = function() return tonumber(Nock.db.profile.clipTickMultiWidth) or 1 end,
            set = function(_, v) Nock.db.profile.clipTickMultiWidth = v; Nock:SendMessage("NOCK_VISUALS_CHANGED") end,
          },
          clipTickWindupColor = {
            type = "color",
            name = "Wind-up mark",
            desc = "The neutral landmark where the next Auto Shot commits (wind-up start).",
            hasAlpha = true,
            order = 40.108,
            disabled = function() return Nock.db.profile.showAutoShotBar == false end,
            get = getColor,
            set = setColor,
          },
          clipTickWindupWidth = {
            type = "range",
            name = "Wind-up mark width",
            desc = "Width of the wind-up commit landmark, in real screen pixels (independent of your UI scale).",
            min = 1, max = 8, step = 1,
            order = 40.109,
            disabled = function() return Nock.db.profile.showAutoShotBar == false end,
            get = function() return tonumber(Nock.db.profile.clipTickWindupWidth) or 1 end,
            set = function(_, v) Nock.db.profile.clipTickWindupWidth = v; Nock:SendMessage("NOCK_VISUALS_CHANGED") end,
          },
          autoShotDelayEnabled = {
            type = "toggle",
            name = "Show Auto Shot delay (experimental)",
            desc = "Show a small color-coded readout on the right edge of the Auto Shot bar: how many seconds later each Auto Shot fired than one full weapon-speed cycle (e.g. +0.45; green = tight, red = badly delayed). Resets out of combat. Off by default.",
            order = 40.11,
            width = "full",
            disabled = function() return Nock.db.profile.showAutoShotBar == false end,
            get = function() return Nock.db.profile.autoShotDelayEnabled == true end,
            set = function(_, v) visualsSet(_, "autoShotDelayEnabled", v) end,
          },
          showMeleeBar = {
            type = "toggle",
            name = "Show melee swing timer",
            desc = "Display the short melee swing bar (the one with the Raptor Strike icon). Off hides it; if both swing bars are off the whole swing row collapses.",
            order = 40.12,
            width = "full",
            get = function() return Nock.db.profile.showMeleeBar ~= false end,
            set = function(_, v) visualsSet(_, "showMeleeBar", v) end,
          },
          meleeShowIcon = {
            type = "toggle",
            name = "Raptor Strike icon",
            desc = "Show the Raptor Strike spell icon beside the melee bar. Off stretches the bar to full width.",
            order = 40.14,
            disabled = function() return Nock.db.profile.showMeleeBar == false end,
            get = function() return Nock.db.profile.meleeShowIcon ~= false end,
            set = function(_, v) visualsSet(_, "meleeShowIcon", v) end,
          },
          meleeBarHeight = {
            type = "range",
            name = "Melee bar height",
            desc = "Height of the melee swing bar in pixels (before scaling).",
            min = 4, max = 40, step = 1,
            order = 40.16,
            disabled = function() return Nock.db.profile.showMeleeBar == false end,
            get = function() return Nock.db.profile.meleeBarHeight or 8 end,
            set = function(_, v) visualsSet(_, "meleeBarHeight", v) end,
          },
          meleeBarTexture = {
            type = "select",
            name = "Melee bar texture",
            desc = "Status bar texture for the melee swing bar. 'Inherit (global)' uses the global Bar texture.",
            order = 40.18,
            dialogControl = lsmWidget(nil, "statusbar"),
            values = lsmSentinelValues("statusbar", "Inherit (global)"),
            disabled = function() return Nock.db.profile.showMeleeBar == false end,
            get = lsmSentinelGet("meleeBarTexture", "Inherit (global)"),
            set = lsmSentinelSet("meleeBarTexture", "Inherit (global)"),
          },
          meleeBarColor = {
            type = "color",
            name = "Melee bar color",
            desc = "Fill color of the melee swing bar.",
            hasAlpha = true,
            order = 40.19,
            disabled = function() return Nock.db.profile.showMeleeBar == false end,
            get = getColor,
            set = setColor,
          },
          swingFillDirection = {
            type = "select",
            name = "Swing bar direction",
            desc = "Which way the swing timer bars move. This is the default for all three bars (Auto Shot, Melee, GCD) — each can override it individually below.\n\nDrain = bar starts full and empties; Fill = bar starts empty and is full when the next shot is ready. The direction is the way the moving edge sweeps.\n\n• Right-to-left (drain) — empties toward the icon (original).\n• Left-to-right (drain) — empties away from the icon.\n• Left-to-right (fill) — fills from the icon outward.\n• Right-to-left (fill) — fills from the far end toward the icon.\n\nClip ticks follow the Auto Shot bar's direction.",
            order = 40.5,
            -- Normalise pooled item fonts so this select can't inherit a leaked
            -- typeface from the LSM Font dropdown (shared AceGUI item pool).
            dialogControl = lsmWidget(nil, "plain"),
            values = FILL_DIR_VALUES,
            sorting = FILL_DIR_SORTING,
            get = function() return Nock.db.profile.swingFillDirection or "rtl" end,
            set = function(_, v) visualsSet(_, "swingFillDirection", v) end,
          },
          swingFillDirectionRanged = fillDirSelect(
            "swingFillDirectionRanged",
            "  ↳ Auto Shot bar direction",
            "Direction for the Auto Shot bar only. \"Inherit (global)\" follows the Swing bar direction above (the default).\n\nThe clip ticks sit on this bar, so they follow THIS setting.",
            40.51,
            function() return Nock.db.profile.showAutoShotBar == false end
          ),
          swingFillDirectionMelee = fillDirSelect(
            "swingFillDirectionMelee",
            "  ↳ Melee bar direction",
            "Direction for the Melee swing bar only. \"Inherit (global)\" follows the Swing bar direction above (the default).",
            40.52,
            function() return Nock.db.profile.showMeleeBar == false end
          ),
          swingFillDirectionGcd = fillDirSelect(
            "swingFillDirectionGcd",
            "  ↳ GCD bar direction",
            "Direction for the GCD bar only. \"Inherit (global)\" follows the Swing bar direction above (the default).",
            40.53,
            function() return Nock.db.profile.showGcdBar == false end
          ),
          gcdHeader = {
            type = "header",
            name = "Global Cooldown bar",
            order = 40.55,
          },
          showGcdBar = {
            type = "toggle",
            name = "Show GCD bar",
            desc = "Display a thin global-cooldown sweep just above the Auto Shot bar. It tracks the haste-scaled GCD (probed from Steady Shot) and follows the swing-bar direction unless you give it its own direction above.",
            order = 40.6,
            get = function() return Nock.db.profile.showGcdBar ~= false end,
            set = function(_, v) visualsSet(_, "showGcdBar", v) end,
          },
          gcdBarHeight = {
            type = "range",
            name = "GCD bar height",
            desc = "Thickness of the GCD bar in pixels.",
            min = 2, max = 16, step = 1,
            order = 40.7,
            disabled = function() return Nock.db.profile.showGcdBar == false end,
            get = function() return Nock.db.profile.gcdBarHeight or 4 end,
            set = function(_, v) visualsSet(_, "gcdBarHeight", v) end,
          },
          gcdBarColor = {
            type = "color",
            name = "GCD bar color",
            desc = "Fill color of the GCD bar.",
            hasAlpha = true,
            order = 40.8,
            disabled = function() return Nock.db.profile.showGcdBar == false end,
            get = getColor,
            set = setColor,
          },
        },
      },
      layout = {
        type = "group",
        name = "Layout",
        order = 1.5,
        args = {
          alignHeader = {
            type = "header",
            name = "Alignment & placement",
            order = 0.3,   -- below the Lock/Unlock pair, which sits at the top
          },
          hudEnabled = {
            type = "toggle",
            name = "Show the HUD",
            desc = "Master switch for the HUD box itself — swing bars, shot display, cooldown grid, range finder, mana bar, info row, and the pet/repair panels glued to it. Turn it off to run Nock purely for its alerts and panels: warnings, the trackers, helpers, shopping list and the mailbox all keep working, since they float on their own. (The setup wizard's \"No HUD\" choice sets this.)",
            order = 0.5,
            width = "full",
            get = function() return Nock.db.profile.hudEnabled ~= false end,
            set = function(_, v) visualsSet(_, "hudEnabled", v) end,
          },
          -- Same global lock as General → Lock all frames; surfaced here too
          -- because this is the page you are on while placing things.
          lockHud = {
            type = "execute",
            name = "Lock HUD",
            desc = "Freeze every movable frame in place. Dragging and the nudge pads switch off. Same as /nock lock.",
            order = 0.1,
            width = 1.2,
            disabled = function() return Nock.IsLocked() end,
            func = function()
              Nock:SetLocked(true)
              -- Re-draw the open dialog so the disabled pair flips.
              local reg = LibStub("AceConfigRegistry-3.0", true)
              if reg then reg:NotifyChange("Nock") end
            end,
          },
          unlockHud = {
            type = "execute",
            name = "Unlock HUD",
            desc = "Unlock every movable frame — green edit borders appear. Drag a frame to move it, or click it once for a nudge pad that shifts it a unit at a time (shift-click for ten, hold to repeat). Same as /nock unlock.",
            order = 0.2,
            width = 1.2,
            disabled = function() return not Nock.IsLocked() end,
            func = function()
              Nock:SetLocked(false)
              local reg = LibStub("AceConfigRegistry-3.0", true)
              if reg then reg:NotifyChange("Nock") end
            end,
          },
          rowAlign = {
            type = "select",
            name = "Row alignment",
            desc = "Horizontal alignment of every HUD row (grid mode).\n\n• Center (default)\n• Left",
            order = 1,
            dialogControl = lsmWidget(nil, "plain"),
            values = { center = "Center", left = "Left" },
            sorting = { "center", "left" },
            -- Free placement supersedes alignment — but only where it is live
            -- (Classic look): React always grids, so alignment applies there
            -- even with the (inert) free-placement flag left on.
            disabled = function() return Nock.FreeLayoutActive() end,
            get = function() return Nock.db.profile.rowAlign or "center" end,
            set = function(_, v) visualsSet(_, "rowAlign", v) end,
          },
          freeLayout = {
            type = "toggle",
            name = "Free placement mode",
            desc = "Off (default): rows stack in the grid box.\n\nOn: drag every piece anywhere — each HUD row, the cast bar, and the totem/pet-status/repair side panels; positions are saved per character. Unlock the HUD (above) to drag; each piece shows a green edit border while the main box itself is hidden entirely. The overall Scale still scales everything (changing it after placing moves scattered pieces proportionally). Warnings is positioned separately and unaffected.\n\n|cffffd200Classic look only|r — the React look always uses the grid (its bars and icon grid are one welded stack), so this setting is ignored while React is active. Your saved positions are kept for when you switch back.",
            order = 2,
            width = "full",
            get = function() return Nock.db.profile.freeLayout == true end,
            set = function(_, v) visualsSet(_, "freeLayout", v) end,
          },
          lockNote = {
            type = "description",
            name = "Unlock (above) to place things: drag the HUD, and in Free placement mode each row, the cast bar and the side panels individually. Click any unlocked frame once for a nudge pad that moves it a unit per click.",
            order = 2.5,
            fontSize = "medium",
          },
          resetElementPos = {
            type = "execute",
            name = "Reset element positions",
            desc = "Clear all saved per-element positions. They are re-captured from the grid the next time free placement lays out.",
            order = 3,
            disabled = function() return not Nock.db.profile.freeLayout end,
            func = function()
              Nock.db.profile.elementPositions = {}
              -- The cast bar is free-placeable too, but stores its position on
              -- its own key (false = welded back to the HUD box top edge).
              Nock.db.profile.castBarPosition = false
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          rowsHeader = {
            type = "header",
            name = "HUD elements",
            order = 10,
          },
          visibilityIntro = {
            type = "description",
            name = "One place to toggle every Nock element. Each toggle here is the SAME setting as the one on that feature's own tab, so they stay in sync. Handy if you run your own HUD and only want Nock's smart features.",
            order = 10.01,
            fontSize = "medium",
          },
          reactVisibilityNote = {
            type = "description",
            name = "|cffffd200React look is active:|r the row toggles below govern the CLASSIC look only. React element visibility lives under React HUD → Size & Elements (Hide all / Show all still covers both).",
            order = 10.015,
            fontSize = "medium",
            hidden = function() return (Nock.db.profile.hudMode or "classic") ~= "react" end,
          },
          hideAllElements = {
            type = "execute",
            name = "Hide all",
            desc = "Hide every visual element at once (HUD rows, swing/cast bars, pet panel, and all feature panels). Note: hiding Warnings and Rotation also quiets their scanning/projection engines; everything else is purely visual and keeps running.",
            order = 10.02,
            width = "half",
            func = function() setAllHudVisibility(false) end,
          },
          showAllElements = {
            type = "execute",
            name = "Show all",
            desc = "Restore all elements that are on by default. Does NOT force-enable the opt-in panels (Misdirection, buff/debuff trackers) — turn those on individually.",
            order = 10.03,
            width = "half",
            func = function() setAllHudVisibility(true) end,
          },
          showCooldowns = {
            type = "toggle",
            name = "Cooldown grid",
            desc = "Show the 7+7 cooldown grid (trinkets, sappers, traps, drums, etc.). When off, the HUD shrinks to fit and the row's space is reclaimed.",
            order = 11,
            width = "full",
            get = function() return Nock.db.profile.showCooldowns end,
            set = function(_, v) visualsSet(_, "showCooldowns", v) end,
          },
          showBuffRow = {
            type = "toggle",
            name = "Buff row (procs + utility)",
            desc = "The React HUD's proc row floating above the Classic HUD (just above the cast bar by default; drag it when unlocked): haste/burst procs, utility buffs, Windfury, the pet's Frenzy and the MOVE IN alert. Its settings are under Classic HUD → Buff Row (shared with React HUD → Buff Row).",
            order = 11.5,
            width = "full",
            get = function() return Nock.db.profile.showBuffRow ~= false end,
            set = function(_, v) visualsSet(_, "showBuffRow", v) end,
          },
          showInfoRow = {
            type = "toggle",
            name = "Info row (speed + arrows)",
            desc = "Show the thin bottom strip with the haste-adjusted ranged speed and the arrow/bullet count. Off hides the strip and the HUD shrinks accordingly.",
            order = 12,
            width = "full",
            get = function() return Nock.db.profile.showInfoRow end,
            set = function(_, v) visualsSet(_, "showInfoRow", v) end,
          },
          showManaBar = {
            type = "toggle",
            name = "Mana bar",
            desc = "Show the thin player-mana bar directly above the range finder. Off hides it and the HUD reclaims the space.",
            order = 13,
            width = "full",
            get = function() return Nock.db.profile.showManaBar ~= false end,
            set = function(_, v) visualsSet(_, "showManaBar", v) end,
          },
          showRangeFinder = {
            type = "toggle",
            name = "Range finder",
            desc = "Show the melee-proximity / dead-zone bar. Off hides it and the HUD reclaims the space. The range logic keeps running, so the rotation weave helper still works and dead-zone sound cues (if enabled) still fire.",
            order = 14,
            width = "full",
            get = function() return Nock.db.profile.showRangeFinder ~= false end,
            set = function(_, v) visualsSet(_, "showRangeFinder", v) end,
          },
          showTotemTracker = {
            type = "toggle",
            name = "Totem tracker",
            desc = "Show the Air/Earth totem-range panel glued to the HUD's right edge. Off hides it entirely. (Same setting as Totem Tracker → Enable totem tracker.)",
            order = 15,
            width = "full",
            get = function() return Nock.db.profile.totemTrackerEnabled ~= false end,
            set = function(_, v) visualsSet(_, "totemTrackerEnabled", v) end,
          },
          showRotation = {
            type = "toggle",
            name = "Rotation display",
            desc = "Master on/off for the whole rotation display — the 6-icon next-action helper row AND the Fluffy-style Shot Bars. Off hides both, stops the projection engine, and the HUD reclaims the space.",
            order = 16,
            width = "full",
            get = function() return Nock.db.profile.showRotation ~= false end,
            set = function(_, v) visualsSet(_, "showRotation", v) end,
          },
          showWarnings = {
            type = "toggle",
            name = "Warnings panel",
            desc = "Master on/off for the alert-square warnings near the top of the screen. Off fully disables the Warnings subsystem (no scanning).",
            order = 17,
            width = "full",
            get = function() return Nock.db.profile.showWarnings ~= false end,
            set = function(_, v) visualsSet(_, "showWarnings", v) end,
          },
          showHelpers = {
            type = "toggle",
            name = "Helpers panel",
            desc = "Master on/off for the consumable/situational helper badges below the warnings. Off fully disables the Helpers subsystem.",
            order = 18,
            width = "full",
            get = function() return Nock.db.profile.showHelpers ~= false end,
            set = function(_, v) visualsSet(_, "showHelpers", v) end,
          },
          showCastBar = globalToggle("showCastBar", "Cast bar",
            "Show the spell cast-bar panel that floats above the HUD. Off hides it entirely, even mid-cast.", 18.1),
          showPetStatus = globalToggle("showPetStatus", "Pet status panel",
            "Show the pet happiness / Mend / Feed panel glued to the HUD's left edge. Off hides it entirely.", 18.2),
          showAutoShotBar = globalToggle("showAutoShotBar", "Auto Shot bar",
            "Show the Auto Shot swing bar. (Same setting as Swing Bars → Show Auto Shot bar.)", 18.3),
          showMeleeBar = globalToggle("showMeleeBar", "Melee swing timer",
            "Show the melee swing-timer bar. (Same setting as Swing Bars → Show melee swing timer.)", 18.4),
          showGcdBar = globalToggle("showGcdBar", "GCD bar",
            "Show the global-cooldown bar above the Auto Shot bar. (Same setting as Swing Bars → Show GCD bar.)", 18.5),

          panelsHeader = {
            type = "header",
            name = "Feature panels",
            order = 18.9,
          },
          misdirectPanelToggle = optToggle("misdirectEnabled", "Misdirection tracker",
            "Show the party/raid Misdirection cooldown tracker. (Same setting as Misdirection → Enable tracker section.)", 19.1),
          mdCastPanelToggle = optToggle("mdCastEnabled", "Misdirect tank buttons",
            "Show the click-to-Misdirect tank buttons. (Same setting as Misdirection → Enable tank buttons section.)", 19.2),
          buffTrackerPanelToggle = optToggle("buffTrackerEnabled", "Buff tracker",
            "Show the buff-tracker grids. (Same setting as Buff Tracker → Enable buff tracker.)", 19.3),
          debuffTrackerPanelToggle = optToggle("debuffTrackerEnabled", "Debuff tracker",
            "Show the target debuff-tracker grid. (Same setting as Debuff Tracker → Enable debuff tracker.)", 19.4),
          shoppingPanelToggle = globalToggle("shoppingEnabled", "Shopping list",
            "Show the missing-consumables shopping-list panel. (Same setting as Shopping List → Enable shopping list.)", 19.5),
          repairPanelToggle = globalToggle("repairWarnEnabled", "Repair reminder",
            "Show the durability / repair-reminder strip. (Same setting as Shopping List → Enable repair reminder.)", 19.6),

          scalingHeader = {
            type = "header",
            name = "Per-element scaling",
            order = 20,
          },
          scalingIntro = {
            type = "description",
            name = "Scale individual HUD rows and side panels independently. This multiplies on top of the overall Scale (General tab); 1.0 leaves an element unchanged. The HUD box widens to fit the largest row.\n",
            order = 21,
            fontSize = "medium",
          },
          rotationScale = {
            type = "range",
            name = "Rotation / helper row",
            desc = "Scale of the 6-icon rotation helper row.",
            min = 0.5, max = 2.0, step = 0.05, bigStep = 0.1,
            order = 22,
            get = function() return Nock.db.profile.rotationScale or 1.0 end,
            set = function(_, v) visualsSet(_, "rotationScale", v) end,
          },
          shotBarsScale = {
            type = "range",
            name = "Shot bars",
            desc = "Scale of the scrolling shot-timing timeline. Stacks with the Shot bars height setting.",
            min = 0.5, max = 2.0, step = 0.05, bigStep = 0.1,
            order = 23,
            get = function() return Nock.db.profile.shotBarsScale or 1.0 end,
            set = function(_, v) visualsSet(_, "shotBarsScale", v) end,
          },
          swingScale = {
            type = "range",
            name = "Swing timers",
            desc = "Scale of the ranged + melee swing bars (and their icons/ticks).",
            min = 0.5, max = 2.0, step = 0.05, bigStep = 0.1,
            order = 24,
            get = function() return Nock.db.profile.swingScale or 1.0 end,
            set = function(_, v) visualsSet(_, "swingScale", v) end,
          },
          rangeFinderScale = {
            type = "range",
            name = "Range finder",
            desc = "Scale of the proximity / dead-zone bar.",
            min = 0.5, max = 2.0, step = 0.05, bigStep = 0.1,
            order = 25,
            get = function() return Nock.db.profile.rangeFinderScale or 1.0 end,
            set = function(_, v) visualsSet(_, "rangeFinderScale", v) end,
          },
          infoRowScale = {
            type = "range",
            name = "Info row",
            desc = "Scale of the bottom speed / ammo strip.",
            min = 0.5, max = 2.0, step = 0.05, bigStep = 0.1,
            order = 26,
            get = function() return Nock.db.profile.infoRowScale or 1.0 end,
            set = function(_, v) visualsSet(_, "infoRowScale", v) end,
          },
          buffRowScale = {
            type = "range",
            name = "Buff row",
            desc = "Scale of the proc / utility buff row floating above the HUD (Classic HUD only — in React the row follows the React scale).",
            min = 0.5, max = 2.0, step = 0.05, bigStep = 0.1,
            order = 26.5,
            get = function() return Nock.db.profile.buffRowScale or 1.0 end,
            set = function(_, v) visualsSet(_, "buffRowScale", v) end,
          },
          totemScale = {
            type = "range",
            name = "Totem tracker panel",
            desc = "Scale of the totem-range side panel glued to the HUD's right edge.",
            min = 0.5, max = 2.0, step = 0.05, bigStep = 0.1,
            order = 27,
            get = function() return Nock.db.profile.totemScale or 1.0 end,
            set = function(_, v) visualsSet(_, "totemScale", v) end,
          },
        },
      },
      warnings = {
        type = "group",
        name = "Warnings",
        order = 2,
        -- The landing page holds only the master toggle + intro; Appearance &
        -- Preview and the themed category nodes (You/Pet/Combat/Gear & Binds/
        -- Boss + Other) are sidebar children, each a short page of the
        -- familiar inline warning boxes.
        childGroups = "tree",
        args = {
          masterToggle = globalToggle("showWarnings", "Enable Warnings panel",
            "Master on/off for the whole Warnings subsystem (alert squares + per-tick scanning). Same setting as Classic HUD → Layout → HUD elements → Warnings panel.", 0),
          intro = {
            type = "description",
            name = "Alert popups shown near the top of the screen. Sizing, fonts and the preview buttons live under |cffffd100Appearance & Preview|r in the list; the warnings themselves are grouped by theme — You, Pet, Combat, Gear & Binds, Boss.\n",
            order = 1,
            fontSize = "medium",
          },

          appearanceHeader = {
            type = "header",
            name = "Appearance",
            order = 10,
          },
          warningIconSize = {
            type = "range",
            name = "Icon size",
            desc = "Size of the alert squares.",
            min = 24, max = 80, step = 2,
            order = 11,
            get = get,
            set = set,
          },
          warningBorderSize = {
            type = "range",
            name = "Border thickness",
            desc = "Thickness of the colored border around alert squares.",
            min = 1, max = 10, step = 1,
            order = 12,
            get = get,
            set = set,
          },
          warningLabelOffset = {
            type = "range",
            name = "Label offset",
            desc = "Vertical spacing between alert square and the label below it.",
            min = 0, max = 24, step = 1,
            order = 13,
            get = get,
            set = set,
          },
          warningLabelSize = {
            type = "range",
            name = "Label size",
            desc = "Font size of the label below alert squares.",
            min = 8, max = 24, step = 1,
            order = 14,
            get = get,
            set = set,
          },
          warningLabelFont = {
            type = "select",
            name = "Label font",
            desc = "Font used for the label below alert squares (sourced from LibSharedMedia).",
            order = 15,
            dialogControl = lsmWidget(nil, "font"),
            values = lsmValues("font"),
            get = function() return Nock.db.profile.warningLabelFont end,
            set = function(_, v) visualsSet(_, "warningLabelFont", v) end,
          },
          warningLabelStyle = {
            type = "select",
            name = "Label style",
            desc = "Font outline / weight for the warning label.",
            order = 16,
            dialogControl = lsmWidget(nil, "plain"),  -- normalise pooled item fonts (LSM Font leak guard)
            values = {
              [""]                   = "Plain",
              ["OUTLINE"]            = "Outline",
              ["THICKOUTLINE"]       = "Thick outline (bold)",
              ["MONOCHROME"]         = "Monochrome",
              ["OUTLINE,MONOCHROME"] = "Outline + Monochrome",
            },
            get = function() return Nock.db.profile.warningLabelStyle end,
            set = function(_, v) visualsSet(_, "warningLabelStyle", v) end,
          },
          warningLabelUpper = {
            type = "toggle",
            name = "Uppercase labels",
            desc = "Display warning label text in ALL CAPS.",
            order = 17,
            get = function() return Nock.db.profile.warningLabelUpper end,
            set = function(_, v) visualsSet(_, "warningLabelUpper", v) end,
          },

          previewHeader = {
            type = "header",
            name = "Preview",
            order = 20,
          },
          previewIntro = {
            type = "description",
            name = "Pop a 10-second sample (one red, one amber, one blue) so you can dial in size, fonts, label offset, and border thickness without waiting for a real trigger.",
            order = 21,
            fontSize = "medium",
          },
          previewButton = {
            type = "execute",
            name = "Show sample warnings (10s)",
            order = 22,
            func = function()
              local mod = Nock:GetModule("Warnings", true)
              if mod and mod.RunDemo then mod:RunDemo(10) end
            end,
          },
          -- The DO NOT RELEASE banner is not a warning square, so the sample
          -- demo above can't include it — it gets its own button (the same
          -- preview /nock norelease triggers).
          noReleasePreview = {
            type = "execute",
            name = "Preview DO NOT RELEASE banner (5s)",
            desc = "Shows the centre-screen DO NOT RELEASE banner — the wipe-with-Bloodlust alert — so you can see and place it without dying for it.",
            order = 23,
            width = 1.4,
            func = function()
              local mod = Nock:GetModule("Warnings", true)
              if mod and mod.RunNoReleaseDemo then mod:RunNoReleaseDemo(5) end
            end,
          },

          -- (the old "Warnings" list header/intro are gone — the injected
          -- warning groups now sit behind the picker dropdown below Preview)
          -- Per-warning inline groups are injected after this static table is
          -- built — see the loop further down in buildOptionsTable.
        },
      },
      helpers = {
        type = "group",
        name = "Helpers",
        order = 3,
        args = {
          masterToggle = globalToggle("showHelpers", "Enable Helpers panel",
            "Master on/off for the whole Helpers subsystem. Same setting as Classic HUD → Layout → HUD elements → Helpers panel.", 0),
          intro = {
            type = "description",
            name = "Pre-pull + situational reminder badges (food, flask, battle/guardian elixir, weapon stone, pet food, plus conditional ones vs Demon / Undead bosses). Buffs are matched by spell ID, so every rank counts. A missing buff shows a greyed badge; one that's about to run out shows in colour with a countdown. Buffs that are comfortably up stay invisible. Unlock frames (General tab) to move the panel.",
            order = 1,
            fontSize = "medium",
          },
          parseMode = {
            type = "toggle",
            name = "Parse Mode",
            desc = "Enable parse-tier checks. Adds Scroll of Agility + Scroll of Strength reminders on both you and your pet. Default on — turn off if you don't run parse buffs.",
            order = 2,
            width = "full",
            get = function() return Nock.db.profile.parseMode ~= false end,
            set = function(_, v) Nock.db.profile.parseMode = v end,
          },
          helpersHideWA = {
            type = "input",
            name = "Auto-hide when WeakAura loaded",
            desc = "Comma/newline separated, case-sensitive name prefixes. If WeakAuras is loaded and any aura's name STARTS WITH one of these, the Helpers panel auto-hides — so a consumes-reminder WA pack you already run doesn't get shadowed by this one. Blank disables this.",
            order = 3,
            width = "full",
            get = function() return Nock.db.profile.helpersHideWA or "" end,
            set = function(_, v) visualsSet(_, "helpersHideWA", v) end,
          },
          helpersExpiringThreshold = {
            type = "range",
            name = "Expiring warning (seconds)",
            desc = "Surface a badge with a countdown when a tracked buff has less than this many seconds left — the window in which you'd top it up before a pull. 0 disables the early warning, so badges only appear once a buff is fully missing.",
            order = 4,
            min = 0, max = 600, step = 15,
            width = "full",
            get = function() return Nock.db.profile.helpersExpiringThreshold or 300 end,
            set = function(_, v) Nock.db.profile.helpersExpiringThreshold = v end,
          },
          layoutHeader = { type = "header", name = "Layout", order = 5 },
          helpersIconSize = {
            type = "range",
            name = "Icon size",
            desc = "Edge length of each badge, in pixels.",
            order = 5.1,
            min = 24, max = 64, step = 1,
            get = function() return Nock.db.profile.helpersIconSize or 40 end,
            set = function(_, v) visualsSet(_, "helpersIconSize", v) end,
          },
          helpersIconGap = {
            type = "range",
            name = "Icon gap",
            desc = "Horizontal space between badges, in pixels.",
            order = 5.2,
            min = 0, max = 30, step = 1,
            get = function() return Nock.db.profile.helpersIconGap or 10 end,
            set = function(_, v) visualsSet(_, "helpersIconGap", v) end,
          },
          helpersScale = {
            type = "range",
            name = "Panel scale",
            desc = "Scale of the whole badge row, applied on top of the icon size.",
            order = 5.3,
            min = 0.5, max = 2.0, step = 0.05,
            get = function() return Nock.db.profile.helpersScale or 1.0 end,
            set = function(_, v) visualsSet(_, "helpersScale", v) end,
          },
          helpersResetPos = {
            type = "execute",
            name = "Reset position",
            desc = "Return the panel to its default spot, centred below the warnings row.",
            order = 5.4,
            func = function()
              Nock.db.profile.helpersPosition = false
              Nock:SendMessage("NOCK_HELPERS_POSITION_RESET")
            end,
          },
          -- Per-helper inline groups injected later (see buildOptionsTable).
        },
      },
      misdirect = {
        type = "group",
        name = "Misdirection",
        order = 11,
        args = {
          intro = {
            type = "description",
            name = "One floating panel with two stacked sections. TOP: a cooldown tracker for every hunter in your party/raid (spell 34477, 30s effect / 120s CD), each row 'Name → Target' with a CD bar. BOTTOM: clickable buttons for each tank — click one to cast Misdirection on that tank.",
            order = 1,
            fontSize = "medium",
          },

          trackerHeader = { type = "header", name = "Tracker (party/raid MD cooldowns)", order = 10 },
          trackerEnabled = {
            type = "toggle",
            name = "Enable tracker section",
            desc = "Show the top section: a CD-tracker row per party/raid hunter. Hidden when no hunters are present.",
            order = 11,
            width = "full",
            get = function() return Nock.db.profile.misdirectEnabled ~= false end,
            set = function(_, v)
              Nock.db.profile.misdirectEnabled = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },

          clickerHeader = { type = "header", name = "Click-to-Misdirect (tanks)", order = 20 },
          clickerDesc = {
            type = "description",
            name = "Lists every group member set as the raid Main Tank or assigned the Tank role — set a Main Tank in the raid frame, assign roles, or list names manually below for auto-detection. Clicking a tank casts Misdirection on them. NOTE: the tank buttons can't be re-built while you're in combat (secure-button limit); set up before the pull. Clicking a pre-set button mid-fight works fine.",
            order = 21,
            fontSize = "medium",
          },
          clickerEnabled = {
            type = "toggle",
            name = "Enable tank buttons section",
            desc = "Show the bottom section: one clickable Misdirection button per tank.",
            order = 22,
            width = "full",
            get = function() return Nock.db.profile.mdCastEnabled == true end,
            set = function(_, v)
              Nock.db.profile.mdCastEnabled = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          announce = {
            type = "toggle",
            name = "Announce on cast",
            desc = "Send a raid/party message (\"Misdirection -> Tank\") when your Misdirection actually casts on a tank. A click that fails to cast (out of range, line of sight, on cooldown) does not announce.",
            order = 23,
            width = "full",
            get = function() return Nock.db.profile.mdCastAnnounce ~= false end,
            set = function(_, v) Nock.db.profile.mdCastAnnounce = v end,
          },
          tooltip = {
            type = "toggle",
            name = "Hover tooltip",
            desc = "Show a tooltip (\"Click to Misdirect → Name\") when hovering a tank button. Off by default.",
            order = 23.5,
            width = "full",
            get = function() return Nock.db.profile.mdCastTooltip == true end,
            set = function(_, v) Nock.db.profile.mdCastTooltip = v end,
          },
          tankList = {
            type = "input",
            name = "Manual tank names",
            desc = "Comma/newline separated. Anyone listed here is treated as a tank even without an assigned Tank role — a fallback for groups that don't set roles. Use the character's name (no realm).",
            order = 24,
            width = "full",
            multiline = true,
            get = function() return Nock.db.profile.mdCastTankList or "" end,
            set = function(_, v)
              Nock.db.profile.mdCastTankList = v
              Nock:SendMessage("NOCK_MDCAST_RESCAN")
            end,
          },
          debug = {
            type = "toggle",
            name = "Debug clicks",
            desc = "Print the macro each tank button runs when clicked. Useful only for troubleshooting.",
            order = 25,
            width = "full",
            get = function() return Nock.db.profile.mdCastDebug == true end,
            set = function(_, v) Nock.db.profile.mdCastDebug = v end,
          },

          panelHeader = { type = "header", name = "Panel", order = 40 },
          lockNote = {
            type = "description",
            name = "Drag this panel while frames are unlocked (General → Lock all frames, or /nock unlock); a green border appears. Tank buttons stop responding to clicks while unlocked so you can move it.",
            order = 41,
            fontSize = "medium",
          },
          width = {
            type = "range",
            name = "Row width",
            desc = "Width of each row in pixels (applies to both sections).",
            min = 120, max = 320, step = 5,
            order = 42,
            get = function() return Nock.db.profile.misdirectWidth or 200 end,
            set = function(_, v)
              Nock.db.profile.misdirectWidth = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          mdShowHeader = {
            type = "toggle",
            name = "MISDIRECTION title",
            desc = "Show the panel's title header. Off shrinks the panel by the header's height — the rows move up.",
            order = 42.3,
            width = "full",
            get = function() return Nock.db.profile.mdShowHeader ~= false end,
            set = function(_, v)
              Nock.db.profile.mdShowHeader = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          -- (Background styling block — including the fill opacity on the
          -- pre-existing mdBackgroundOpacity key — injected at order 44+ by
          -- panelStyleArgs; see the loop near the bottom of buildOptionsTable.)
          resetPos = {
            type = "execute",
            name = "Reset position",
            order = 43,
            func = function()
              Nock.db.profile.misdirectPosition = { point = "CENTER", relPoint = "CENTER", x = 250, y = 0 }
              Nock:SendMessage("NOCK_MD_POSITION_RESET")
            end,
          },
        },
      },
      buffTracker = {
        type = "group",
        name = "Buff Tracker",
        order = 9,
        args = {
          intro = {
            type = "description",
            name = "Compact grid of icons showing all active buffs on you and your pet. Each slot is OmniCC-friendly (uses a Cooldown frame for the swipe + timer text). Two independently-positionable panels.",
            order = 1,
            fontSize = "medium",
          },
          enabled = {
            type = "toggle",
            name = "Enable buff tracker",
            order = 2,
            width = "full",
            get = function() return Nock.db.profile.buffTrackerEnabled ~= false end,
            set = function(_, v)
              Nock.db.profile.buffTrackerEnabled = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          cols = {
            type = "range",
            name = "Columns",
            desc = "Number of columns per grid. Grid grows downward as more buffs appear.",
            min = 3, max = 5, step = 1,
            order = 3,
            get = function() return Nock.db.profile.buffTrackerCols or 5 end,
            set = function(_, v)
              Nock.db.profile.buffTrackerCols = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          iconSize = {
            type = "range",
            name = "Icon size",
            desc = "Pixel size of each buff icon in both grids.",
            min = 16, max = 48, step = 1,
            order = 4,
            get = function() return Nock.db.profile.buffTrackerIconSize or 24 end,
            set = function(_, v)
              Nock.db.profile.buffTrackerIconSize = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },

          playerHeader = { type = "header", name = "Player panel", order = 10 },
          playerEnabled = {
            type = "toggle",
            name = "Show player buffs panel",
            order = 11,
            width = "full",
            get = function() return Nock.db.profile.buffTrackerPlayerEnabled ~= false end,
            set = function(_, v)
              Nock.db.profile.buffTrackerPlayerEnabled = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          playerLockNote = {
            type = "description",
            name = "Drag this panel while frames are unlocked (General → Lock all frames, or /nock unlock).",
            order = 12,
            fontSize = "medium",
          },
          playerResetPos = {
            type = "execute",
            name = "Reset player position",
            order = 13,
            func = function()
              Nock.db.profile.buffTrackerPlayerPosition = { point = "CENTER", relPoint = "CENTER", x = -100, y = 100 }
              Nock:SendMessage("NOCK_BUFFTRACKER_POSRESET")
            end,
          },

          petHeader = { type = "header", name = "Pet panel", order = 20 },
          petEnabled = {
            type = "toggle",
            name = "Show pet buffs panel",
            order = 21,
            width = "full",
            get = function() return Nock.db.profile.buffTrackerPetEnabled ~= false end,
            set = function(_, v)
              Nock.db.profile.buffTrackerPetEnabled = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          petResetPos = {
            type = "execute",
            name = "Reset pet position",
            order = 23,
            func = function()
              Nock.db.profile.buffTrackerPetPosition = { point = "CENTER", relPoint = "CENTER", x = 100, y = 100 }
              Nock:SendMessage("NOCK_BUFFTRACKER_POSRESET")
            end,
          },

          presetHeader = { type = "header", name = "Tracked buffs (preset)", order = 30 },
          presetIntro = {
            type = "description",
            name = "Toggle individual preset buffs below, or add your own by spell ID. Disabled presets and custom entries are saved per character.",
            order = 31,
            fontSize = "medium",
          },
          restorePreset = {
            type = "execute",
            name = "Restore preset defaults",
            desc = "Re-enable every preset buff and clear all custom spell IDs.",
            order = 32,
            func = function()
              Nock.db.profile.buffTrackerDisabled     = {}
              Nock.db.profile.buffTrackerCustomPlayer  = ""
              Nock.db.profile.buffTrackerCustomPet     = ""
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
              local reg = LibStub("AceConfigRegistry-3.0", true)
              if reg then reg:NotifyChange("Nock") end
            end,
          },
          playerBuffsHeader = { type = "header", name = "Player buffs", order = 199 },
          -- per-entry player toggles injected at order 200+ (buildOptionsTable)
          customPlayer = {
            type = "input",
            name = "Custom player buffs (spell IDs)",
            desc = "Extra spell IDs to track on the player. Separate with spaces, commas, or new lines.",
            multiline = 3,
            width = "full",
            order = 280,
            get = function() return Nock.db.profile.buffTrackerCustomPlayer or "" end,
            set = function(_, v)
              Nock.db.profile.buffTrackerCustomPlayer = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          petBuffsHeader = { type = "header", name = "Pet buffs", order = 299 },
          -- per-entry pet toggles injected at order 300+ (buildOptionsTable)
          customPet = {
            type = "input",
            name = "Custom pet buffs (spell IDs)",
            desc = "Extra spell IDs to track on the pet. Separate with spaces, commas, or new lines.",
            multiline = 3,
            width = "full",
            order = 380,
            get = function() return Nock.db.profile.buffTrackerCustomPet or "" end,
            set = function(_, v)
              Nock.db.profile.buffTrackerCustomPet = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
        },
      },
      debuffTracker = {
        type = "group",
        name = "Debuff Tracker",
        order = 10,
        args = {
          intro = {
            type = "description",
            name = "A bare, draggable icon grid of target debuffs (curated + your own). Only shows while you have a target. Present debuffs show in colour with a swipe; missing ones grey out with the shared 'missing' highlight. Currently ON for debugging — intended off by default, and later restricted to raids.",
            order = 1,
            fontSize = "medium",
          },
          enabled = {
            type = "toggle",
            name = "Enable debuff tracker",
            order = 2,
            width = "full",
            get = function() return Nock.db.profile.debuffTrackerEnabled ~= false end,
            set = function(_, v)
              Nock.db.profile.debuffTrackerEnabled = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          raidOnly = {
            type = "toggle",
            name = "Only show in raids",
            desc = "When on, the grid only appears while you're in a raid. Off (current default) shows it always — for testing.",
            order = 3,
            width = "full",
            get = function() return Nock.db.profile.debuffTrackerRaidOnly == true end,
            set = function(_, v)
              Nock.db.profile.debuffTrackerRaidOnly = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          lockNote = {
            type = "description",
            name = "Drag the grid while frames are unlocked (General → Lock all frames, or /nock unlock) — a coloured outline appears around the otherwise-bare grid so you can find it.",
            order = 4,
            fontSize = "medium",
          },
          resetPos = {
            type = "execute",
            name = "Reset position",
            order = 5,
            func = function()
              Nock.db.profile.debuffTrackerPosition = { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 }
              Nock:SendMessage("NOCK_DEBUFFTRACKER_POSRESET")
            end,
          },
          cols = {
            type = "range",
            name = "Columns",
            desc = "Icons per row; the grid grows downward as more are tracked.",
            min = 1, max = 16, step = 1,
            order = 6,
            get = function() return Nock.db.profile.debuffTrackerCols or 8 end,
            set = function(_, v)
              Nock.db.profile.debuffTrackerCols = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          iconSize = {
            type = "range",
            name = "Icon size",
            min = 12, max = 48, step = 1,
            order = 7,
            get = function() return Nock.db.profile.debuffTrackerIconSize or 26 end,
            set = function(_, v)
              Nock.db.profile.debuffTrackerIconSize = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          presetHeader = { type = "header", name = "Tracked debuffs (preset)", order = 30 },
          presetIntro = {
            type = "description",
            name = "Toggle preset debuffs below, or add your own in the custom box (spell ID or exact name, one per line / comma).",
            order = 31,
            fontSize = "medium",
          },
          restoreDefaults = {
            type = "execute",
            name = "Restore preset defaults",
            desc = "Every preset back to its shipped state (the opt-in ones — Scorpid Sting, Insect Swarm — go back off), the built-in order, and no custom entries.",
            order = 32,
            func = function()
              Nock.db.profile.debuffTrackerDisabled = {}
              Nock.db.profile.debuffTrackerOrder    = {}
              Nock.db.profile.debuffTrackerCustom   = ""
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
              if dbfRebuildEntries then dbfRebuildEntries() end
              local reg = LibStub("AceConfigRegistry-3.0", true)
              if reg then reg:NotifyChange("Nock") end
            end,
          },
          -- per-entry rows (toggle + Up/Down) injected at order 200+ (buildOptionsTable)
          custom = {
            type = "input",
            name = "Custom debuffs (spell IDs or names)",
            desc = "Extra target debuffs to track. Spell ID or exact name, one per line or comma-separated. They join the list above, where they can be switched off and moved like the presets.",
            multiline = 5,
            width = "full",
            order = 900,
            get = function() return Nock.db.profile.debuffTrackerCustom or "" end,
            set = function(_, v)
              Nock.db.profile.debuffTrackerCustom = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
              if dbfRebuildEntries then dbfRebuildEntries() end
              local reg = LibStub("AceConfigRegistry-3.0", true)
              if reg then reg:NotifyChange("Nock") end
            end,
          },
        },
      },
      totemTracker = {
        type = "group",
        name = "Totem Tracker",
        order = 8,
        args = {
          intro = {
            type = "description",
            name = "Air + Earth totem range, glued to the HUD's right edge (mirror of the pet-status panel on the left). Slots show greyed defaults (Windfury / Strength of Earth) and light up with the actual totem's icon while you're in range; out of range they grey out and run the next-action glow so you know to move toward your shaman. Only shows when a shaman is in the group (force flag overrides during testing).",
            order = 1,
            fontSize = "medium",
          },
          enabled = {
            type = "toggle",
            name = "Enable totem tracker",
            order = 2,
            width = "full",
            get = function() return Nock.db.profile.totemTrackerEnabled ~= false end,
            set = function(_, v)
              Nock.db.profile.totemTrackerEnabled = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          forceShaman = {
            type = "toggle",
            name = "Force show (testing)",
            desc = "Always show the Air/Earth slots regardless of whether a shaman is in the group. Turn off to only show them when a shaman is actually present.",
            order = 3,
            width = "full",
            get = function() return Nock.db.profile.totemForceShaman ~= false end,
            set = function(_, v)
              Nock.db.profile.totemForceShaman = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
        },
      },
      shopping = {
        type = "group",
        name = "Shopping List",
        order = 12,
        args = {
          intro = {
            type = "description",
            name = "A floating panel that appears only while you're in a configured city zone, listing consumables that are below their restock threshold (curated defaults + your own item IDs). Drag to position when unlocked.",
            order = 1,
            fontSize = "medium",
          },
          enabled = {
            type = "toggle",
            name = "Enable shopping list",
            order = 2,
            width = "full",
            get = function() return Nock.db.profile.shoppingEnabled ~= false end,
            set = function(_, v)
              Nock.db.profile.shoppingEnabled = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          lockNote = {
            type = "description",
            name = "Drag this panel while frames are unlocked (General → Lock all frames, or /nock unlock); a green border appears so you can find it. You may want to /reload near a city, or temporarily add your current zone, to see it while positioning.",
            order = 3,
            fontSize = "medium",
          },
          showCompleted = {
            type = "toggle",
            name = "Show stocked items too",
            desc = "List every tracked item, the stocked ones with a green count, instead of only what is below its threshold. The same switch as the tick in the panel's top-left corner.",
            order = 3.5,
            width = "full",
            get = function() return Nock.db.profile.shoppingShowCompleted == true end,
            set = function(_, v)
              Nock.db.profile.shoppingShowCompleted = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          width = {
            type = "range",
            name = "Panel width",
            min = 140, max = 360, step = 5,
            order = 4,
            get = function() return Nock.db.profile.shoppingWidth or 210 end,
            set = function(_, v)
              Nock.db.profile.shoppingWidth = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          resetPos = {
            type = "execute",
            name = "Reset position",
            order = 5,
            func = function()
              Nock.db.profile.shoppingPosition = { point = "CENTER", relPoint = "CENTER", x = -250, y = 0 }
              Nock:SendMessage("NOCK_SHOP_POSITION_RESET")
            end,
          },
          zones = {
            type = "input",
            name = "Shopping zones",
            desc = "Zone names where the panel appears, matched against your current zone (case-insensitive). Separate with commas or new lines. Zone names are localized — use the spelling your client shows.",
            multiline = 2,
            width = "full",
            order = 6,
            get = function()
              return Nock.db.profile.shoppingZones or Nock.Constants.SHOPPING_ZONES_DEFAULT
            end,
            set = function(_, v)
              Nock.db.profile.shoppingZones = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          curatedHeader = { type = "header", name = "Curated items", order = 10 },
          curatedIntro = {
            type = "description",
            name = "Toggle each curated item and set the quantity you want to keep stocked (you're warned when you have fewer). \"Arrows / ammo (total)\" counts the full reserve: quiver + bags + maker charges.",
            order = 11,
            fontSize = "medium",
          },
          restoreDefaults = {
            type = "execute",
            name = "Restore curated defaults",
            desc = "Re-enable every curated item, clear all threshold overrides and custom items, and reset the zone list.",
            order = 12,
            func = function()
              local p = Nock.db.profile
              p.shoppingDisabled  = {}
              p.shoppingThreshold = {}
              p.shoppingCustom    = ""
              p.shoppingZones     = Nock.Constants.SHOPPING_ZONES_DEFAULT
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
              local reg = LibStub("AceConfigRegistry-3.0", true)
              if reg then reg:NotifyChange("Nock") end
            end,
          },
          -- Per-curated-entry inline groups (toggle + threshold) injected at
          -- order 100+ — see the loop near the bottom of buildOptionsTable.
          customHeader = { type = "header", name = "Custom items", order = 280 },
          customIntro = {
            type = "description",
            name = "Extra items to track, one per line: itemID:threshold or itemID:threshold:Label. Example:\n22838:10:Haste Potion\n33874:40",
            order = 281,
            fontSize = "medium",
          },
          custom = {
            type = "input",
            name = "Custom items",
            multiline = 5,
            width = "full",
            order = 282,
            get = function() return Nock.db.profile.shoppingCustom or "" end,
            set = function(_, v)
              Nock.db.profile.shoppingCustom = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          repairHeader = { type = "header", name = "Repair reminder", order = 290 },
          repairIntro = {
            type = "description",
            name = "A red durability bar glued under the HUD, shown only in the shopping zones above when your equipped gear drops below the threshold.",
            order = 291,
            fontSize = "medium",
          },
          repairEnabled = {
            type = "toggle",
            name = "Enable repair reminder",
            order = 292,
            width = "full",
            get = function() return Nock.db.profile.repairWarnEnabled ~= false end,
            set = function(_, v)
              Nock.db.profile.repairWarnEnabled = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          repairPct = {
            type = "range",
            name = "Warn below durability (%)",
            min = 5, max = 100, step = 1, bigStep = 5,
            order = 293,
            disabled = function() return Nock.db.profile.repairWarnEnabled == false end,
            get = function() return Nock.db.profile.repairWarnPct or 90 end,
            set = function(_, v)
              Nock.db.profile.repairWarnPct = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
        },
      },
      mailbox = {
        type = "group",
        name = "Mailbox",
        order = 12.5,
        args = {
          intro = {
            type = "description",
            name = "Snowball mail logistics. At a mailbox, Nock reports how many snowballs are stored in mails and when the earliest one expires, mass-returns snowball mails to their senders, or loots them and auto-sends the snowballs to another of your characters (12 stacks per mail).\n\nThe keep-alive cycle: mail returned to you once can NOT be returned again — it is deleted forever when it expires a second time. So bounce fresh mail with Return All, and on the other character loot the bounced mail and re-send it fresh with Send.",
            order = 1,
            fontSize = "medium",
          },
          enabled = {
            type = "toggle",
            name = "Enable mailbox helper",
            order = 2,
            width = "full",
            get = function() return Nock.db.profile.mailboxEnabled ~= false end,
            set = function(_, v)
              Nock.db.profile.mailboxEnabled = v
              Nock:SendMessage("NOCK_MAILBOX_CHANGED")
            end,
          },
          recipients = {
            type = "input",
            name = "Send recipients",
            desc = "Character names snowballs can be mailed to, one per line, exactly as spelled in-game. Shared by all your characters (add your hunter AND your banker). The mailbox panel lets you pick which one a session sends to.",
            multiline = 3,
            width = "full",
            order = 3,
            get = function()
              local list = Nock.db.global.mailboxRecipients or {}
              return table.concat(list, "\n")
            end,
            set = function(_, v)
              local list = {}
              for line in tostring(v or ""):gmatch("[^\r\n]+") do
                local name = line:match("^%s*(.-)%s*$")
                if name ~= "" then list[#list + 1] = name end
              end
              Nock.db.global.mailboxRecipients = list
              Nock:SendMessage("NOCK_MAILBOX_CHANGED")
            end,
          },
          keepCount = {
            type = "range",
            name = "Keep snowballs in bags",
            desc = "Snowballs a send run leaves in your bags (raid supply). Whole stacks only: the amount is rounded UP to full stacks of 20.",
            min = 0, max = 400, step = 20,
            order = 4,
            get = function() return Nock.db.profile.mailboxKeepCount or 0 end,
            set = function(_, v) Nock.db.profile.mailboxKeepCount = v end,
          },
          usage = {
            type = "description",
            name = "\nAt a mailbox: use the panel buttons, or /nock mail report | send [name] | return | stop. COD mails and non-snowball mails are never touched.",
            order = 5,
            fontSize = "medium",
          },
        },
      },
      weaveBind = {
        type = "group",
        name = "Weave Bind",
        order = 13,
        args = {
          -- The full write-up used to sit here, at order 1, so the page opened on
          -- five paragraphs and pushed the key box and both macro fields out of
          -- view. Only the experimental flag stays up top; the explanation is
          -- compacted and parked below the macros ("How it works", order 52).
          intro = {
            type = "description",
            order = 1,
            fontSize = "medium",
            name = "|cffff6060Experimental.|r Hold-to-weave keybind. How it works: below the macros.\n",
          },
          weaveBindEnabled = {
            type  = "toggle",
            name  = "Enable weave bind",
            desc  = "Master on/off for the weave key. Mid-combat toggles are deferred to combat end.",
            order = 10,
            width = "full",
            get   = get,
            set   = function(info, v)
              Nock.db.profile[info[#info]] = v
              Nock:SendMessage("NOCK_WEAVEBIND_CHANGED")
              refreshBindCheck()
            end,
          },
          weaveLogPanel = {
            type  = "toggle",
            name  = "Weave log panel in real fights",
            desc  = "A small panel with one row per weave of the fight: the gap from the last shot to the hit, from the hit to the next shot, and the two together (Ishri's Weave Time Tracker numbers). Off by default; /nock weavelog panel toggles it too. The practice toolbar's Log button is the practice panel and never shows here.",
            order = 15,
            width = "full",
            get   = get,
            set   = function(info, v)
              Nock.db.profile[info[#info]] = v
              local wl = Nock:GetModule("PracticeWeaveLogView", true)
              if wl and wl.Apply then wl:Apply() end
            end,
          },
          weaveBindKey = {
            type  = "keybinding",
            name  = "Weave key",
            desc  = "Key to hold for melee weaving. Mouse buttons work too: click the box, then press the mouse button (middle/4/5) — bind the physical button directly instead of a keystroke emulated by mouse software. Overrides the key's normal action while the feature is enabled (the original binding comes back when you disable it or clear this).",
            order = 20,
            disabled = function() return Nock.db.profile.weaveBindEnabled ~= true end,
            get   = get,
            set   = function(info, value)
              if value and value ~= "" then
                local action = GetBindingAction and GetBindingAction(value)
                if action == "OPENCHAT" or action == "OPENCHATSLASH" or action == "TOGGLEGAMEMENU" then
                  Nock:Print(("Weave Bind: refusing to override the '%s' key — you'd lose chat or the game menu."):format(_G["BINDING_NAME_" .. action] or action))
                  return
                end
              end
              Nock.db.profile[info[#info]] = value
              Nock:SendMessage("NOCK_WEAVEBIND_CHANGED")
              refreshBindCheck()
            end,
          },
          weaveBindConflict = bindConflictNote("weave", 21),
          builderHeader = {
            type  = "description",
            order = 22,
            fontSize = "medium",
            name  = "\n|cffffd100Press macro builder|r — the same switches the setup wizard offers. They edit the press macro below, so you can also just type it yourself.\n",
          },
          weaveSnowball = {
            type  = "toggle",
            name  = "Snowball poke",
            desc  = "Put |cffffd200/use Snowball|r at the top of the press macro. A Snowball is free and off the global cooldown, so throwing one as you step in forces the server to update where you are standing — and the white auto-attack you weaved for actually lands instead of being eaten as out of range.",
            order = 23,
            width = "full",
            disabled = weaveBindOff,
            get = function() return Nock.WeaveMacro.HasSnowball(pressBody()) end,
            set = function(_, v)
              local WM = Nock.WeaveMacro
              setPressBody(v and WM.WithSnowball(pressBody()) or WM.WithoutSnowball(pressBody()))
            end,
          },
          weaveSnowballGate = {
            type  = "toggle",
            name  = "Only throw one when the garment says so",
            desc  = "Wraps the poke in an |cffffd200[noequipped:Shirt]|r-style conditional so trash pulls and questing don't burn your Snowball stack. Only the poke is gated — Raptor Strike and the press's /startattack always fire. The RELEASE macro gets the inverse, |cffffd200/startattack [equipped:Shirt]|r, standing in for the poke while it is off (only on a release macro Nock wrote; your own text is never touched).",
            order = 24,
            width = "full",
            disabled = noPoke,
            get = function() return Nock.WeaveMacro.GateOf(pressBody()) ~= nil end,
            set = function(_, v)
              local WM = Nock.WeaveMacro
              if not v then
                setPressBody(WM.WithoutGate(pressBody()))
                return
              end
              local g, dir = WM.GateOf(pressBody())
              setPressBody(WM.WithGate(pressBody(), g or "shirt", dir or "off"))
            end,
          },
          weaveGateGarment = {
            type  = "select",
            name  = "Garment",
            desc  = "Which cosmetic slot drives the gate. Pick whichever one you are happy to swap for a fight.",
            order = 25,
            dialogControl = lsmWidget(nil, "plain"),
            values = { shirt = "Shirt", tabard = "Tabard" },
            sorting = { "shirt", "tabard" },
            disabled = noGate,
            get = function() return (Nock.WeaveMacro.GateOf(pressBody())) or "shirt" end,
            -- Every garment bracket in BOTH bodies follows (the release
            -- re-arm, a hand-written gate), stock or custom.
            set = function(_, v)
              local WM = Nock.WeaveMacro
              Nock.db.profile.weaveBindMacroUp = WM.WithGarment(Nock.db.profile.weaveBindMacroUp or "", v)
              setPressBody(WM.WithGarment(pressBody(), v))
            end,
          },
          weaveGateDirection = {
            type  = "select",
            name  = "Throw the Snowball while the garment is",
            desc  = "Which way round the gate works. 'Off' is the shipped convention — you take the garment off for a boss and the poke starts firing; 'On' inverts it if you would rather put something on.",
            order = 26,
            dialogControl = lsmWidget(nil, "plain"),
            values = { off = "Off (taken off for the boss)", on = "On (put on for the boss)" },
            sorting = { "off", "on" },
            disabled = noGate,
            get = function() return select(2, Nock.WeaveMacro.GateOf(pressBody())) or "off" end,
            -- A direction flip inverts every bracket in both bodies.
            set = function(_, v)
              local WM = Nock.WeaveMacro
              local _, dir = WM.GateOf(pressBody())
              if (dir or "off") == v then return end
              Nock.db.profile.weaveBindMacroUp = WM.InvertGates(Nock.db.profile.weaveBindMacroUp or "")
              setPressBody(WM.InvertGates(pressBody()))
            end,
          },
          weaveBindMacroDown = {
            type  = "input",
            name  = "When the key is pressed",
            desc  = "Macro body run on key press (max 255 characters).",
            order = 30,
            width = "full",
            multiline = 5,
            disabled = function() return Nock.db.profile.weaveBindEnabled ~= true end,
            get   = get,
            validate = function(_, value)
              if type(value) == "string" and #value > 255 then
                return "Macro text can be at most 255 characters."
              end
              return true
            end,
            set   = function(info, value)
              Nock.db.profile[info[#info]] = value
              Nock:SendMessage("NOCK_WEAVEBIND_CHANGED")
            end,
          },
          weaveBindMacroUp = {
            type  = "input",
            name  = "When the key is released",
            desc  = "Macro body run on key release (max 255 characters).",
            order = 40,
            width = "full",
            multiline = 3,
            disabled = function() return Nock.db.profile.weaveBindEnabled ~= true end,
            get   = get,
            validate = function(_, value)
              if type(value) == "string" and #value > 255 then
                return "Macro text can be at most 255 characters."
              end
              return true
            end,
            set   = function(info, value)
              Nock.db.profile[info[#info]] = value
              Nock:SendMessage("NOCK_WEAVEBIND_CHANGED")
            end,
          },
          garmentPointer = {
            type  = "description",
            name  = "The shirt/tabard boss autopilot has its own section: |cffffd100Boss Garment|r.",
            order = 45,
            fontSize = "medium",
          },
          weaveBindRestore = {
            type  = "execute",
            name  = "Restore default macros",
            desc  = "Reset both macro bodies to the shipped weave defaults.",
            order = 50,
            func  = function()
              local C = Nock.Constants
              Nock.db.profile.weaveBindMacroDown = C.WEAVE_BIND_MACRO_DOWN
              Nock.db.profile.weaveBindMacroUp   = C.WEAVE_BIND_MACRO_UP
              Nock:SendMessage("NOCK_WEAVEBIND_CHANGED")
              local reg = LibStub("AceConfigRegistry-3.0", true)
              if reg then reg:NotifyChange("Nock") end
            end,
          },
          -- Grounded (Gello): the three steps of the move, each shown only
          -- when it applies -- import while Grounded holds a weave bind, undo
          -- while the import can go back, disable once Grounded holds nothing.
          weaveBindGroundedImport = {
            type  = "execute",
            name  = "Import from Grounded",
            desc  = "Move the weave bind the Grounded addon holds (key and both macros) into Nock. Grounded gives the key up at once; no reload.",
            order = 50.1,
            hidden = function()
              local wb = Nock:GetModule("WeaveBind", true)
              return not (wb and wb.GroundedWeaveBind and wb:GroundedWeaveBind())
            end,
            func  = function()
              local wb = Nock:GetModule("WeaveBind", true)
              if wb and wb.ImportFromGrounded then wb:ImportFromGrounded() end
              local reg = LibStub("AceConfigRegistry-3.0", true)
              if reg then reg:NotifyChange("Nock") end
            end,
          },
          weaveBindGroundedUndo = {
            type  = "execute",
            name  = "Undo the Grounded import",
            desc  = "Give the imported bind back to Grounded and clear Nock's weave key.",
            order = 50.2,
            confirm = true,
            hidden = function()
              local wb = Nock:GetModule("WeaveBind", true)
              return not (Nock.db.profile.weaveBindImported and wb and wb.GroundedLoaded and wb:GroundedLoaded())
            end,
            func  = function()
              local wb = Nock:GetModule("WeaveBind", true)
              if wb and wb.UndoGroundedImport then wb:UndoGroundedImport() end
              local reg = LibStub("AceConfigRegistry-3.0", true)
              if reg then reg:NotifyChange("Nock") end
            end,
          },
          weaveBindGroundedDisable = {
            type  = "execute",
            name  = "Disable Grounded",
            desc  = "Grounded holds no binds any more. Disable the addon for this character and reload the UI. Undo needs it loaded, so do this last.",
            order = 50.3,
            confirm = true,
            hidden = function()
              local wb = Nock:GetModule("WeaveBind", true)
              return not (wb and wb.GroundedBindCount and wb:GroundedBindCount() == 0)
            end,
            func  = function()
              local wb = Nock:GetModule("WeaveBind", true)
              -- A reload right away (user, 2026-08-27): the disable only
              -- takes effect on one, and the page would keep showing an
              -- addon that is on its way out.
              if wb and wb.DisableGrounded and wb:DisableGrounded() and ReloadUI then ReloadUI() end
            end,
          },
          howHeader = {
            type  = "header",
            name  = "How it works",
            order = 51,
          },
          howIntro = {
            type = "description",
            order = 52,
            fontSize = "medium",
            name = "PRESS stops your current cast, queues Raptor Strike and turns melee auto-attack on. RELEASE casts Kill Command and re-arms Auto Shot. Press as you reach melee; weave on the way OUT. While enabled the key's normal action is overridden, and changes made in combat apply at combat end.\n\n"
              .. "|cffffd200Snowball|r — the shipped press macro leads with |cffffd200/use Snowball|r, an instant off-GCD poke that makes the server re-check your attack. Costs one per weave; delete the line if you'd rather not.\n\n"
              .. "|cffffd200Backpedal|r — add |cffffd200/click MovePadBackward|r to BOTH macros to auto-backpedal for exactly as long as you hold the key. Needs the |cffffd200Movement Pad|r accessibility feature; Nock loads it and watches for a stuck toggle.\n\n"
              .. "|cffffd200Garment gates|r — |cffffd200[equipped:...]|r / |cffffd200[noequipped:...]|r lines for |cffffd200Shirt|r or |cffffd200Tabard|r are resolved by Nock when the macro is applied (this client evaluates them incorrectly) and re-applied whenever the garment changes.\n\n"
              .. "|cffffd200Key edges|r — both fire natively via the |cffffd200useOnKeyDown|r attribute, so the macros need no |cffffd200/console|r lines and your other action bars are unaffected while the key is held. Old |cffffd200/console ActionButtonUseKeyDown|r lines keep working, and Nock restores the CVar if a release is ever swallowed.\n\n"
              .. "|cffffd200Coach|r — while the bind is enabled the Range Finder bar walks you through the cycle: green |cff00ff66GO IN|r (window open), amber |cffffa500HOLD|r (waiting for the hit), blue |cff4da6ffBACK OUT|r (hit landed — move out but KEEP HOLDING), cyan |cff00e6e6RELEASE|r (Auto Shot is in range — let go). Releasing during BACK OUT is the classic mistake: the release macro's !Auto Shot fails with 'target too close' and you stand there doing nothing.\n",
          },
          -- The whole "Weave coach" section is withdrawn from the GUI: the header
          -- and the five sound-cue entries all carry `hidden`, and the coach's own
          -- explanation moved up into "How it works" (it documents the Range Finder
          -- bar stages, which are still live). Nothing is deleted — the settings
          -- survive in the profile, so dropping `hidden` restores the section
          -- intact. MigrateProfile also switches weaveCoachSoundsEnabled off once,
          -- so a profile that had a sound picked isn't left with an audible cue it
          -- can no longer reach.
          coachHeader = {
            type   = "header",
            name   = "Weave coach",
            order  = 60,
            hidden = true,
          },
          weaveCoachSoundsEnabled = {
            type  = "toggle",
            name  = "Sound cues",
            desc  = "Play the coach's outcome sounds (hit landed / clear to release). Uses the dead-zone sound channel from the Range Finder tab.",
            order = 62,
            hidden = true,
            width = "full",
            get   = function() return Nock.db.profile.weaveCoachSoundsEnabled ~= false end,
            set   = function(_, v) Nock.db.profile.weaveCoachSoundsEnabled = v end,
          },
          weaveCoachStruckSound = {
            type = "select",
            name = "Hit landed sound",
            desc = "Played the instant your melee hit (Raptor or white swing) lands during a hold, regardless of where you're standing. 'None' is silent.",
            order = 63,
            hidden = true,
            -- Normalise pooled item fonts so this select can't inherit a leaked
            -- typeface from the LSM Font dropdown (shared AceGUI item pool) —
            -- there is no dedicated LSM sound widget to do it for us.
            dialogControl = lsmWidget(nil, "plain"),
            disabled = function() return Nock.db.profile.weaveCoachSoundsEnabled == false end,
            values = function()
              local lsm = LibStub("LibSharedMedia-3.0", true)
              local out = { ["None"] = "None" }
              if lsm then
                for _, name in ipairs(lsm:List("sound")) do out[name] = name end
              end
              return out
            end,
            get = function() return Nock.db.profile.weaveCoachStruckSound or "None" end,
            set = function(_, v) Nock.db.profile.weaveCoachStruckSound = v end,
          },
          weaveCoachStruckPreview = {
            type = "execute",
            name = "Preview",
            order = 63.5,
            hidden = true,
            width = "half",
            disabled = function()
              return Nock.db.profile.weaveCoachSoundsEnabled == false
                or (Nock.db.profile.weaveCoachStruckSound or "None") == "None"
            end,
            func = function()
              previewSound(Nock.db.profile.weaveCoachStruckSound, Nock.db.profile.deadZoneSoundChannel)
            end,
          },
          weaveCoachReleaseSound = {
            type = "select",
            name = "Release sound",
            desc = "Played the moment Auto Shot is back in range during a hold — release now. 'None' is silent.",
            order = 64,
            hidden = true,
            dialogControl = lsmWidget(nil, "plain"),
            disabled = function() return Nock.db.profile.weaveCoachSoundsEnabled == false end,
            values = function()
              local lsm = LibStub("LibSharedMedia-3.0", true)
              local out = { ["None"] = "None" }
              if lsm then
                for _, name in ipairs(lsm:List("sound")) do out[name] = name end
              end
              return out
            end,
            get = function() return Nock.db.profile.weaveCoachReleaseSound or "None" end,
            set = function(_, v) Nock.db.profile.weaveCoachReleaseSound = v end,
          },
          weaveCoachReleasePreview = {
            type = "execute",
            name = "Preview",
            order = 64.5,
            hidden = true,
            width = "half",
            disabled = function()
              return Nock.db.profile.weaveCoachSoundsEnabled == false
                or (Nock.db.profile.weaveCoachReleaseSound or "None") == "None"
            end,
            func = function()
              previewSound(Nock.db.profile.weaveCoachReleaseSound, Nock.db.profile.deadZoneSoundChannel)
            end,
          },
        },
      },
      tonk = {
        type = "group",
        name = "Steam Tonk",
        order = 13.6,
        args = {
          intro = {
            type = "description",
            name = "The Steam Tonk Controller saves a pet from a boss mechanic: transforming dismisses it, and stepping out lets you re-summon at full health with Call Pet.\n\nThe obvious one-button macro cancels the transform in the same frame it requests it, and the client regularly ends up |cffff4040welded|r — unable to move or cast until combat ends. The cancel is actually sent |cffffd200before|r the cast is transmitted, so it is out of order, not merely early.\n\n|cffffd200Take any /cancelaura line out of your tonk macro.|r Use the tonk from any button you like, on its own. Nock steps you back out a moment later — |cffffd200in combat as well as out|r.",
            order = 1,
            fontSize = "medium",
          },
          tonkAutoCancel = {
            type = "toggle",
            name = "Step me back out automatically",
            desc = "Leaves the tonk on its own after the delay below, in combat or out of it. Turn this off only if you actually want to drive the tonk around.",
            order = 3,
            width = "full",
            get = function() return Nock.db.profile.tonkAutoCancel ~= false end,
            set = function(_, v) Nock.db.profile.tonkAutoCancel = v end,
          },
          tonkCancelDelay = {
            type = "range",
            name = "Settling delay",
            desc = "Seconds to wait after the transform lands before stepping out — and the length of the dial's sweep. Leaving too early is what welds you, so raise this if it still happens.\n\n|cffffd200The floor is 0.50s.|r Lower values gamble on a clean frame and a quiet connection; a weld costs you the pull, and 100ms buys you nothing.",
            min = Nock.Constants.TONK_CANCEL_MIN, max = 1.00, step = 0.05,
            order = 4,
            get = function() return Nock.TonkCancelDelay() end,
            set = function(_, v)
              local lo = Nock.Constants.TONK_CANCEL_MIN
              Nock.db.profile.tonkCancelDelay = (v < lo) and lo or v
            end,
          },
          dialHeader = {
            type = "header", name = "The countdown dial", order = 10,
          },
          -- The SAME global lock as everywhere else (Nock:SetLocked), surfaced
          -- here because the dial is only up for the length of a transform:
          -- without unlocking there is nothing on screen to aim these settings
          -- at. Not a per-panel lock — those were retired in 1.0.17 and must
          -- not come back.
          unlockTonk = {
            type = "execute",
            name = "Unlock to preview",
            desc = "Unlocks every movable Nock frame, which holds the dial open on screen so you can see, drag and resize it. Same as /nock unlock.",
            order = 11,
            width = 1.2,
            disabled = function() return not Nock.IsLocked() end,
            func = function() Nock:SetLocked(false) end,
          },
          lockTonk = {
            type = "execute",
            name = "Lock",
            desc = "Locks every movable Nock frame again. The dial goes back to appearing only while you are in the tonk. Same as /nock lock.",
            order = 12,
            width = 1.2,
            disabled = function() return Nock.IsLocked() end,
            func = function() Nock:SetLocked(true) end,
          },
          tonkDialEnabled = {
            type = "toggle",
            name = "Show the countdown dial",
            desc = "The tonk's own icon with a radial sweep running down to the moment Nock steps you out. Informational only — turning it off changes nothing about the exit itself.",
            order = 13,
            width = "full",
            get = function() return Nock.db.profile.tonkDialEnabled ~= false end,
            set = function(_, v) Nock.db.profile.tonkDialEnabled = v end,
          },
          tonkDialSize = {
            type = "range",
            name = "Dial size",
            desc = "Square edge in pixels. You can also drag the grip in its bottom-right corner while the HUD is unlocked.",
            min = 40, max = 240, step = 2,
            order = 14,
            disabled = function() return Nock.db.profile.tonkDialEnabled == false end,
            get = function() return Nock.db.profile.tonkDialSize or 72 end,
            set = function(_, v)
              Nock.db.profile.tonkDialSize = v
              local m = Nock:GetModule("TonkDialView", true)
              if m then m:ApplySize() end
            end,
          },
          dialHint = {
            type = "description",
            name = "\n|cff909090Unlock the HUD to drag the dial or resize it by its bottom-right grip. While unlocked it loops its sweep so there is something to aim at.|r",
            order = 15,
            fontSize = "medium",
          },
          usage = {
            type = "description",
            name = "\nIf you ever get welded anyway, |cffffd200/nock tonk|r steps you out immediately.",
            order = 30,
            fontSize = "medium",
          },
          credit = {
            type = "description",
            name = "\n|cff909090The in-combat exit is |cffffd200Big Chungus|r|cff909090's find, from the Classic Hunter Discord. The tonk is a charmed creature rather than a buff you wear, so dismissing the creature ends it — and pet control, unlike every aura-cancel function, is not blocked in combat.|r",
            order = 31,
            fontSize = "medium",
          },
        },
      },
      garment = {
        type = "group",
        name = "Boss Garment",
        order = 13.5,
        args = {
          intro = {
            type = "description",
            order = 1,
            fontSize = "medium",
            name = "The garment autopilot keeps your shirt or tabard in the state your Weave Bind macros need. It is driven by macro lines carrying an |cffffd200[equipped:Shirt]|r / |cffffd200[noequipped:Shirt]|r conditional (or Tabard): target a raid boss out of combat and Nock equips or removes the garment so those lines fire; drop the boss and it restores your everyday state.\n\nBecause the conditionals live in the Weave Bind macros, both toggles below stay greyed out until |cffffd100Weave Bind|r is enabled — and even then they only act when a macro line actually carries a Shirt/Tabard conditional. The red |cffffd100Shirt/Tabard wrong for boss|r warning (Warnings section) covers the in-combat case gear swaps can't fix, and /nock shirt dumps a diagnostic of the whole gate.\n",
          },
          weaveBindGarmentAutoFlip = {
            type  = "toggle",
            name  = "Set your shirt/tabard for bosses automatically",
            desc  = "When you target a raid boss out of combat, Nock puts the gate garment in the state your macros need — no trip to the character pane. Lines written as [noequipped:Shirt] fire with the shirt OFF, so Nock takes it off for you; lines written as [equipped:Shirt] fire with it ON, so Nock puts one on from your bags. (Same for Tabard.) Gear can't change in combat — the red gate warning still covers that case. Does nothing unless a macro line carries a Shirt/Tabard conditional. Requires 'Enable weave bind' (Weave Bind section).",
            order = 10,
            width = "full",
            disabled = function() return Nock.db.profile.weaveBindEnabled ~= true end,
            get   = get,
            set   = function(info, v)
              Nock.db.profile[info[#info]] = v
              Nock:SendMessage("NOCK_WEAVEBIND_CHANGED")
            end,
          },
          weaveBindGarmentAutoReequip = {
            type  = "toggle",
            name  = "Switch it back after the fight",
            desc  = "Once no living boss is targeted (kill, wipe, or you drop the target), Nock returns the garment to its everyday state — back ON if it was removed for [noequipped:...] lines, back OFF if it was put on for [equipped:...] lines — so the boss-only lines switch off again for trash and farming. This upkeep works anywhere, not just in raids: a garment left in its boss state (forgotten after a manual swap, say) is corrected as soon as no boss is targeted, so gated lines can't burn Snowballs while you're out in the world. Turn this off to handle the garment yourself.",
            order = 11,
            width = "full",
            disabled = function()
              return Nock.db.profile.weaveBindEnabled ~= true
                or Nock.db.profile.weaveBindGarmentAutoFlip ~= true
            end,
            get   = get,
            set   = function(info, v)
              Nock.db.profile[info[#info]] = v
              Nock:SendMessage("NOCK_WEAVEBIND_CHANGED")
            end,
          },
        },
      },
      rotation = {
        type = "group",
        name = "Shot Bars",
        order = 4,
        args = {
          masterToggle = globalToggle("showRotation", "Show rotation display",
            "Master on/off for the whole rotation display — the 6-icon helper row AND the Fluffy-style Shot Bars. Same setting as Classic HUD → Layout → HUD elements → Rotation display. (Distinct from 'Enable rotation helper' below, which only suppresses the next-action glow.)", 0),
          intro = {
            type = "description",
            name = "Shot timing display and rotation engine tunables. Defaults match the inspiration WA; adjust if your setup differs (no quiver / ammo pouch, different weave timing preference, etc.).\n",
            order = 1,
            fontSize = "medium",
          },
          rotationHelperEnabled = {
            type = "toggle",
            name = "Enable rotation helper",
            desc = "Master toggle. When OFF, no slot is marked as the next action — the rotation row stays visible (for CD swipes, aspect, Hunter's Mark) but the engine never highlights what to cast.",
            order = 2,
            width = "full",
            get = function() return Nock.db.profile.rotationHelperEnabled end,
            set = function(_, v)
              Nock.db.profile.rotationHelperEnabled = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          rotationMode = {
            type = "select",
            name = "Display mode",
            desc = "How the rotation is shown.\n\n• Next-action helper — the 6-icon row with a glow on what to cast next, plus the swing-timer bar.\n• Shot timing bars — a Fluffy-style scrolling timeline: sparks for upcoming Auto Shots and colored \"safe to cast\" windows per ability (DPS-equilibrium clip math). Hides the helper icons AND the swing-timer row.",
            order = 2.5,
            width = "full",
            dialogControl = lsmWidget(nil, "plain"),  -- normalise pooled item fonts (LSM Font leak guard)
            values = {
              helper = "Next-action helper",
              bars   = "Shot timing bars",
            },
            get = function() return Nock.db.profile.rotationMode or "helper" end,
            set = function(_, v) visualsSet(_, "rotationMode", v) end,
          },
          weaveNotationEnabled = {
            type = "toggle",
            name = "Weave rotation notation (auto by range)",
            desc = "When on, the rotation label auto-switches to the WEAVE pattern (e.g. \"6:9:1:1 3w\", \"2:2 1w\") while you're in weaving range with a two-hander equipped, and back to the turret pattern (e.g. \"1:1\") at range. Turret players never enter melee, so they always see turret notation. Off = turret notation only (default). The weave pattern is picked from your active haste procs/buffs (Rapid Fire, imp. Aspect, and total melee haste for Bloodlust/DST/Abacus/Haste Potion).",
            order = 2.55,
            width = "full",
            get = function() return Nock.db.profile.weaveNotationEnabled == true end,
            set = function(_, v) visualsSet(_, "weaveNotationEnabled", v) end,
          },
          rotationLabelsGroup = {
            type = "group",
            name = "Rename + color rotation labels",
            order = 2.58,
            inline = true,
            args = (function()
              local a = buildRotationLabelArgs(1)
              a.intro = {
                type = "description",
                name = "Rename any rotation notation to whatever reads better for you — \"1:1\" → \"Spam\", \"5:5:1:1 3w\" → \"French weave\", and so on — and give it a color of its own. Both apply everywhere the label renders: the React notation, the classic Auto Shot bar and the Shot Bars.\n\nDisplay-only: the rotation engine is unaffected, and /nock's debug output keeps reporting the real notation. Leave a box blank to show the built-in.\n\nTurret notations are shown first, then the weave ones (the \"w\" suffix). Note \"5:5:1:1\" and \"5:5:1:1 3w\" are different patterns and rename separately.",
                order = 0,
                fontSize = "medium",
              }
              a.resetColors = {
                type = "execute",
                name = "Reset all colors",
                desc = "Clear every custom label color — each render site returns to its own default.",
                order = 2,
                width = 1.0,
                disabled = function()
                  local m = Nock.db.profile.rotationLabelColors
                  return not (type(m) == "table" and next(m))
                end,
                func = function()
                  Nock.db.profile.rotationLabelColors = {}
                  Nock:SendMessage("NOCK_VISUALS_CHANGED")
                end,
              }
              return a
            end)(),
          },
          shotBarsHeader = {
            type = "header",
            name = "Shot timing bars",
            order = 2.6,
          },
          shotBarsIntro = {
            type = "description",
            name = "Settings for the scrolling shot-timing display (active when Display mode = Shot timing bars). Time flows toward the \"fire now\" edge — right→left by default, or left→right via the Direction toggle below.",
            order = 2.61,
            fontSize = "medium",
          },
          -- Annotated miniature of the bar itself (UI/AceGUI_ShotBarsLegend.lua).
          -- A description entry is what AceConfigDialog renders custom controls
          -- through; no `width` key, so it gets control.width = "fill".
          shotBarsLegend = {
            type = "description",
            name = "",
            dialogControl = "NockShotBarsLegend",
            order = 2.615,
          },
          shotBarsLegacy = {
            type = "toggle",
            name = "Use legacy Shot Bars",
            desc = "Bring back the pre-1.0.14 multi-lane Shot Bars look (full-height melee lane, no GCD/cast shade, no clip-breakpoint tick). The simplified single-lane bar is the default.",
            order = 2.612,
            width = "full",
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = function() return Nock.db.profile.shotBarsSimplified == false end,
            set = function(_, v) visualsSet(_, "shotBarsSimplified", not v) end,
          },
          shotBarsShowHelper = {
            type = "toggle",
            name = "Also show the next-action helper row (unified)",
            desc = "Testing / unified UI: keep the 6-icon next-action helper row visible ABOVE the scrolling bars instead of replacing it. Off = bars replace the helper (original behaviour).",
            order = 2.615,
            width = "full",
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = function() return Nock.db.profile.shotBarsShowHelper end,
            set = function(_, v) visualsSet(_, "shotBarsShowHelper", v) end,
          },
          shotBarsWindow = {
            type = "range",
            name = "Lookahead window (s)",
            desc = "How many seconds into the future the timeline shows. Longer = more upcoming shots visible at once; shorter = bigger, easier-to-read spacing.",
            min = 1.5, max = 6.0, step = 0.1, bigStep = 0.2,
            order = 2.62,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = function() return Nock.db.profile.shotBarsWindow end,
            set = function(_, v) visualsSet(_, "shotBarsWindow", v) end,
          },
          shotBarsRotationText = {
            type = "toggle",
            name = "Rotation text label",
            desc = "Show the rotation notation (e.g. \"1:1\", or the weave pattern) on the right edge of the Shot Bars. Off hides just the label.",
            order = 2.625,
            width = "full",
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = function() return Nock.db.profile.shotBarsRotationText ~= false end,
            set = function(_, v) visualsSet(_, "shotBarsRotationText", v) end,
          },
          shotBarsHeight = {
            type = "range",
            name = "Bar height (px)",
            min = 14, max = 60, step = 1, bigStep = 2,
            order = 2.63,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = function() return Nock.db.profile.shotBarsHeight end,
            set = function(_, v) visualsSet(_, "shotBarsHeight", v) end,
          },
          shotBarsMeleeHeight = {
            type = "range",
            name = "Melee lane height (px)",
            desc = "Height of the bottom melee/weave strip inside the Shot Bars. The pixels come out of the ranged lane above it, so the overall bar height never changes and nothing below it on the HUD moves. Default 4.\n\nLegacy Shot Bars split the two lanes proportionally and ignore this.",
            min = 2, max = 24, step = 1, bigStep = 2,
            order = 2.631,
            disabled = function()
              local p = Nock.db.profile
              return p.rotationMode ~= "bars"
                  or p.shotBarsSimplified == false
                  or p.shotBarsShowRaptor == false
            end,
            get = function() return Nock.db.profile.shotBarsMeleeHeight end,
            set = function(_, v) visualsSet(_, "shotBarsMeleeHeight", v) end,
          },
          shotBarsReverse = {
            type = "toggle",
            name = "Flow left→right",
            desc = "Reverse the timeline direction. Off (default) = time flows right→left, with the \"fire now\" edge on the LEFT. On = time flows left→right, fire edge on the RIGHT; upcoming shots enter from the left.",
            order = 2.635,
            width = "full",
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = function() return Nock.db.profile.shotBarsReverse == true end,
            set = function(_, v) visualsSet(_, "shotBarsReverse", v) end,
          },
          shotBarsShowMulti = {
            type = "toggle",
            name = "Show Multi-Shot window",
            order = 2.64,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = function() return Nock.db.profile.shotBarsShowMulti end,
            set = function(_, v) visualsSet(_, "shotBarsShowMulti", v) end,
          },
          shotBarsShowArcane = {
            type = "toggle",
            name = "Show Arcane Shot window",
            order = 2.65,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = function() return Nock.db.profile.shotBarsShowArcane end,
            set = function(_, v) visualsSet(_, "shotBarsShowArcane", v) end,
          },
          shotBarsShowRaptor = {
            type = "toggle",
            name = "Show melee weave lane (bottom row)",
            desc = "Adds Fluffy's second row: the green window where you can step in for a Raptor / auto-attack and still be back before the Auto Shot. The dedicated proximity/position indicator is separate and stays regardless.",
            order = 2.66,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = function() return Nock.db.profile.shotBarsShowRaptor end,
            set = function(_, v) visualsSet(_, "shotBarsShowRaptor", v) end,
          },
          shotBarsColorSteady = {
            type = "color", name = "Steady window color", hasAlpha = true,
            order = 2.67,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = getColor, set = setColor,
          },
          shotBarsColorMulti = {
            type = "color", name = "Multi-Shot window color", hasAlpha = true,
            order = 2.68,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = getColor, set = setColor,
          },
          shotBarsColorArcane = {
            type = "color", name = "Arcane Shot window color", hasAlpha = true,
            order = 2.69,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = getColor, set = setColor,
          },
          shotBarsColorRaptor = {
            type = "color", name = "Melee weave - Raptor ready (green)", hasAlpha = true,
            order = 2.70,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = getColor, set = setColor,
          },
          shotBarsColorWeaveAuto = {
            type = "color", name = "Melee weave - auto-attack only (white)", hasAlpha = true,
            desc = "Shown in the melee lane while Raptor Strike is on cooldown — you can still step in for an auto-attack, just not a Raptor.",
            order = 2.702,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = getColor, set = setColor,
          },
          shotBarsColorDanger = {
            type = "color", name = "Clip band (danger) color", hasAlpha = true,
            desc = "The stretch where a cast started now would still be in flight when the next Auto Shot's wind-up wants to begin — the only place a cast actually delays your shot.",
            order = 2.705,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = getColor, set = setColor,
          },
          shotBarsColorQueue = {
            type = "color", name = "Queue window color (upcoming)", hasAlpha = true,
            desc = "The last stretch before the shot, while it is still ahead of you. Castable — the press is held and comes out right after the arrow, costing nothing — but it does not complete in time the way the bright Steady window does, so it gets its own shade.",
            order = 2.707,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = getColor, set = setColor,
          },
          shotBarsColorQueueLive = {
            type = "color", name = "Queue window color (live — press now)", hasAlpha = true,
            desc = "The same window once the wind-up has actually started. Green means a press right now is free: whatever you hit is held and fires the instant the arrow leaves.",
            order = 2.708,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = getColor, set = setColor,
          },
          shotBarsColorSpark = {
            type = "color", name = "Auto Shot spark color", hasAlpha = true,
            desc = "The vertical line marking the moment the arrow leaves — not a clip warning.",
            order = 2.71,
            disabled = function() return Nock.db.profile.rotationMode ~= "bars" end,
            get = getColor, set = setColor,
          },
          shotBarsFooter = {
            type = "header",
            name = "",
            order = 2.72,
          },
          -- (weave engine tunables injected from weaveEngineArgs() below —
          -- they also render on React → Bars; the grpEngine regroup at the
          -- bottom of this file gathers them exactly as before)

          clipTicksHeader = {
            type = "header",
            name = "Clip-zone ticks",
            order = 45,
          },
          clipTicksIntro = {
            type = "description",
            name = "Clip risk is a BAND, not a tail. The red/orange tick is its upper edge — the last moment a Steady or Multi can start and still finish before the next Auto Shot's wind-up begins. The wind-up mark is its lower edge: past that, a press is simply queued and comes out after the arrow for free.\n\nSo the zone to avoid is between the two marks. There is nothing to tune here: the edges are cast time + wind-up + your measured latency, and the wind-up is read from your own shots rather than assumed. Padding that with a hand-picked margin only moved the ticks away from the truth.",
            order = 46,
            fontSize = "medium",
          },
          showWindupMark = {
            type = "toggle",
            name = "Show wind-up mark",
            desc = "A neutral mark showing where the next Auto Shot's wind-up begins. It is the LOWER edge of the clip zone: past this mark you can press freely, because the client holds the cast until the arrow is away and it costs you nothing.\n\nSo the clip risk is the band BETWEEN the red/orange tick and this mark — not everything after the tick. Before the tick your cast finishes in time; after this mark it simply queues.\n\nThe wind-up sits inside the weapon-speed cycle and shortens with haste, which is why the Auto Shot cast bar lights up before the bar is full. Its position is measured from your own shots.",
            width = "full",
            order = 46.5,
            get = function() return Nock.db.profile.showWindupMark ~= false end,
            set = function(_, v)
              Nock.db.profile.showWindupMark = v
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },

          nextHighlightHeader = {
            type = "header",
            name = "Next-action highlight",
            order = 50,
          },
          nextHighlightIntro = {
            type = "description",
            name = "Visual indicator on the rotation slot the engine wants you to fire next.",
            order = 51,
            fontSize = "medium",
          },
          rotNextEffect = {
            type = "select",
            name = "Effect",
            desc = "Style of the next-action highlight.\n\n• None — no indicator\n• Static — flat colored border\n• Pixel ring — animated dots traveling around the slot (default)\n• Spell-proc — golden sparkle (the same look as the red urgent warning glow)\n• Auto-cast — rotating particles around the slot",
            order = 52,
            dialogControl = lsmWidget(nil, "plain"),  -- normalise pooled item fonts (LSM Font leak guard)
            values = {
              none         = "None",
              static       = "Static border",
              pixelGlow    = "Pixel ring (animated)",
              buttonGlow   = "Spell-proc sparkle",
              autoCastGlow = "Auto-cast rotation",
            },
            get = function() return Nock.db.profile.rotNextEffect end,
            set = function(_, v) visualsSet(_, "rotNextEffect", v) end,
          },
          rotNextColor = {
            type = "color",
            name = "Color",
            desc = "Highlight color for the next-action indicator.",
            hasAlpha = true,
            order = 53,
            disabled = function() return Nock.db.profile.rotNextEffect == "none" end,
            get = getColor,
            set = function(info, r, g, b, a)
              Nock.db.profile.rotNextColor = { r, g, b, a }
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
        },
      },
      practice = {
        type = "group",
        name = "Practice",
        order = 13.8,
        -- Five tabs (2026-08-27, user): the page was 89 controls on one
        -- scroll. What a player touches is on the first; the engine knobs sit
        -- under Advanced; the colours and the stage levers have their own.
        childGroups = "tab",
        args = {
          general = {
            type = "group",
            name = "Practice",
            order = 1,
            args = {
              intro = {
                type = "description",
                name = "|cffff6060EXPERIMENTAL|r -- practice mode is still being tuned: its verdicts, its planner and its windows change between releases, and a fight it grades may be graded differently next week. Use it to feel the rhythm, not to settle an argument.\n\nA simulated practice fight on your real HUD: no target, no casts, no mana. Your Steady / Multi / Arcane keys press Nock instead of the server while practice is on (they cast normally the moment real combat starts). Toggle with |cffffd100/nock practice|r, start a fight from the panel, and read the scorecard in chat or |cffffd100/nock practice report|r.\n\n|cffffd200Drills:|r turret shots and the melee weave (real footwork against a virtual target, or the weave key alone). Procs, scenarios, the opener and the fight timeline follow.",
                order = 1,
                fontSize = "medium",
              },
              toggle = {
                type = "execute",
                name = function() return Nock.state.sim.active and "End practice" or "Start practice" end,
                order = 2,
                width = 1.2,
                func = function()
                  local m = Nock:GetModule("Practice", true)
                  if not m then return end
                  m:Command("")
                  -- Practice ON takes the workbench over the screen: the
                  -- Options window (and the Blizzard panel it may sit in) would
                  -- only stand in front of it (user, 2026-08-27). Ending
                  -- practice leaves Options where it is.
                  if Nock.state.sim.active then
                    local dlg = LibStub("AceConfigDialog-3.0", true)
                    if dlg and dlg.Close then dlg:Close("Nock") end
                    local blizz = _G.SettingsPanel or _G.InterfaceOptionsFrame
                    if blizz and blizz.IsShown and blizz:IsShown() and HideUIPanel then
                      HideUIPanel(blizz)
                    end
                  end
                end,
              },
              procsHeader = { type = "header", name = "Scenario", order = 10 },
              practiceScenario = {
                type = "select",
                name = "Scenario",
                desc = "Which scenario the next fight runs. Paper drills (every turret and weave rotation), proc scripts, your own, then Free play — or pick from the panel's scenario card.",
                order = 11,
                dialogControl = lsmWidget(nil, "plain"),
                values = function()
                  local m = Nock:GetModule("Practice", true)
                  local names = (m and m.ScenarioNames and m:ScenarioNames()) or { "Clean French" }
                  local out = {}
                  for _, name in ipairs(names) do out[name] = name end
                  return out
                end,
                sorting = function()
                  local m = Nock:GetModule("Practice", true)
                  return (m and m.ScenarioNames and m:ScenarioNames()) or { "Clean French" }
                end,
                get = function() return Nock.db.profile.practiceScenario or "Clean French" end,
                set = function(_, v)
                  local m = Nock:GetModule("Practice", true)
                  if m and m.SetScenario then m:SetScenario(v)
                  else Nock.db.profile.practiceScenario = v end
                end,
              },
              practiceScenarioText = {
                type = "input",
                name = "Custom scenarios",
                desc = "One scenario per line: Name: rf@5 lust@20 drums@20 dst@30 pot@21 qs@5 ews=2.17 lock=5:5:1:1 len=90 qs=off — procs at seconds, ews pins the speed, lock pins a notation (and turns the Quick Shots roll off), len ends the fight, qs=off disables the roll.",
                order = 12,
                multiline = 6,
                width = "full",
                get = function() return Nock.db.profile.practiceScenarioText or "" end,
                set = function(_, v) Nock.db.profile.practiceScenarioText = v or "" end,
              },
              practiceQuickShots = {
                type = "toggle",
                name = "Quick Shots proc roll",
                desc = "Roll for the Quick Shots (Improved Aspect of the Hawk) proc during a fight. Off holds ranged haste steady, useful for isolating a rotation drill from the proc's swing-speed swings. A scenario line's own qs=off overrides this per-fight.",
                order = 13,
                get = function() return Nock.db.profile.practiceQuickShots ~= false end,
                set = function(_, v) Nock.db.profile.practiceQuickShots = v end,
              },
              practiceLatencyMs = {
                type = "range",
                name = "Latency (ms)",
                desc = "How long a press takes to reach the simulated server. 0 uses your live latency.",
                min = 0, max = 400, step = 5,
                order = 14,
                get = function() return Nock.db.profile.practiceLatencyMs or 0 end,
                set = function(_, v) Nock.db.profile.practiceLatencyMs = (v > 0) and v or nil end,
              },
              weaveHeader = { type = "header", name = "Weave", order = 20 },
                  -- The weave button's practice bodies depend on this (MovePad
                  -- step-out only in real-movement mode).
              practiceFootwork = {
                type = "select",
                name = "Footwork",
                desc = "'Real movement' reads your movement keys by speed alone — running closes on the virtual target, backpedalling retreats, standing holds. No target position or facing is used; the range bar is your pixel finder: creep until the thumb sits on the melee divider, then a tap forward is in and a tap back is out. 'Weave key only' has the engine step you in and out on its own timer instead, driven purely by the weave key — useful when you have no room to actually move, like at a flight path.",
                order = 21,
                dialogControl = lsmWidget(nil, "plain"),
                values = { move = "Real movement", key = "Weave key only" },
                sorting = { "move", "key" },
                get = function() return Nock.db.profile.practiceFootwork or "move" end,
                set = function(_, v)
                  Nock.db.profile.practiceFootwork = v
                  Nock:SendMessage("NOCK_PRACTICE_CHANGED")
                end,
              },
              practiceStartDistance = {
                type = "range",
                name = "Start distance (yd)",
                desc = "How far the virtual target sits ahead of you when a fight starts.",
                min = 5, max = 12, step = 1,
                order = 22,
                get = function() return Nock.db.profile.practiceStartDistance or 7 end,
                set = function(_, v) Nock.db.profile.practiceStartDistance = v end,
              },
              practiceStepTime = {
                type = "range",
                name = "Step time (s)",
                desc = "Weave key only: seconds the engine spends walking each leg (in or out).",
                min = 0.1, max = 0.6, step = 0.05,
                order = 23,
                hidden = function() return (Nock.db.profile.practiceFootwork or "move") ~= "key" end,
                get = function() return Nock.db.profile.practiceStepTime or 0.3 end,
                set = function(_, v) Nock.db.profile.practiceStepTime = v end,
              },
              timelineHeader = { type = "header", name = "Stage", order = 30 },
                  -- The docked stage carries its own scale (1 while docked, the
                  -- slider's value floating): ApplyDock re-reads it from here.
              practiceScale = {
                type = "range",
                name = "Practice scale",
                desc = "Size of all five practice windows -- the panel and its stage, the floating stage, the scenario picker, the lesson and the review. The workbench caps itself to fit your screen, so on a small screen the slider stops growing it; on a big one, go past 100 %.",
                min = 0.75, max = 3.0, step = 0.05,
                isPercent = true,
                order = 31,
                get = function() return Nock.UI.PracticeScale() end,
                set = function(_, v)
                  Nock.db.profile.practiceScale = v
                  Nock.UI.ApplyPracticeScale()
                  Nock:SendMessage("NOCK_VISUALS_CHANGED")
                end,
              },
              practiceFocusOnStart = {
                type = "toggle",
                name = "Start goes to Focus",
                desc = "Start hides the workbench and puts the stage alone on the HUD, at its own spot and width; Stop brings the window back with the replay. Off (the default), the fight runs inside the window and Focus is only where you pull it out: the Focus button, or the keybind (Key Bindings > Nock).",
                order = 32,
                width = 1.5,
                get = function() return Nock.db.profile.practiceFocusOnStart == true end,
                set = function(_, v) Nock.db.profile.practiceFocusOnStart = v end,
              },
              practiceQuietFocus = {
                type = "toggle",
                name = "Quiet focus",
                desc = "In Focus, drop the coach line under the stage: the notes, the pops and the metronome only.",
                order = 33,
                get = function() return Nock.db.profile.practiceQuietFocus == true end,
                set = function(_, v)
                  Nock.db.profile.practiceQuietFocus = v
                  Nock:SendMessage("NOCK_VISUALS_CHANGED")
                end,
              },
              practiceMetronome = {
                type = "toggle",
                name = "Metronome",
                desc = "Four dots at the right of the coach line: gold on every auto release, green when the weave gap opens, each with a short cue. Silent while a fight is armed but not yet pulled.",
                order = 34,
                get = function() return Nock.db.profile.practiceMetronome ~= false end,
                set = function(_, v) Nock.db.profile.practiceMetronome = v end,
              },
                  -- Switching it OFF closes the window if it happens to be up: the
                  -- flag is what every path back into it is gated on, so a review
                  -- left standing could not be reopened once closed -- and the
                  -- toggle MESSAGE would only answer "disabled" now that the flag
                  -- is already down, so this calls the view directly.
                  -- The header's button row is laid out on this flag, and Relayout
                  -- is what NOCK_VISUALS_CHANGED reaches.
              practiceReviewEnabled = {
                type = "toggle",
                name = "Fight review",
                desc = "Open the review by itself when a fight ends (the workbench returns on its Review page). OFF while the practice engine is being tuned -- a verdict from an engine still under the knife teaches the wrong lesson -- which also hides the toolbar's Review button. The Review page on the rail shows the last fight either way, and so does /nock practice report.",
                order = 35,
                width = 1.5,
                get = function() return Nock.db.profile.practiceReviewEnabled == true end,
                set = function(_, v)
                  Nock.db.profile.practiceReviewEnabled = v
                  if not v then
                    local rv = Nock:GetModule("PracticeTimelineView", true)
                    if rv and rv.Toggle then rv:Toggle(false) end
                  end
                  Nock:SendMessage("NOCK_VISUALS_CHANGED")
                end,
              },
              practiceToast = {
                type = "toggle",
                name = "Show the toast",
                order = 36,
                get = function() return Nock.db.profile.practiceToast ~= false end,
                set = function(_, v) Nock.db.profile.practiceToast = v end,
              },
              practiceToastSec = {
                type = "range",
                name = "Toast duration (s)",
                min = 0.3, max = 3, step = 0.1,
                order = 37,
                get = function() return Nock.db.profile.practiceToastSec or 0.8 end,
                set = function(_, v) Nock.db.profile.practiceToastSec = v end,
              },
              ladderHeader = { type = "header", name = "Ladder & lesson", order = 40 },
              ladderDesc = {
                type = "description",
                order = 41,
                fontSize = "medium",
                name = "The |cffffd200lesson|r window explains one cycle of your rotation — where the wind-up starts, when a Steady still fits, where the weave gap opens — and carries the |cffffd200drill ladder|r in its side panel: ten rungs on three tracks, from holding the beat to the opener, each with a pass condition a finished fight is graded against. |cffffd100/nock practice lesson|r opens it, |cffffd100/nock practice ladder|r opens it on the ladder, and the review's fix cards open it on the step that explains the fault.\n\n|cffffd100/nock practice reset|r re-centres all five practice windows (panel, stage, scenarios, lesson, review) if one ends up off-screen.",
              },
                  -- Toggle(true), not the toggle MESSAGE: a button called "Open
                  -- the lesson" must never close it. Same call the `ladder`
                  -- sub-command makes.
              practiceLessonOpen = {
                type = "execute",
                name = "Open the lesson",
                desc = "Show the lesson window with the drill ladder.",
                order = 42,
                width = 1.2,
                func = function()
                  local m = Nock:GetModule("Practice", true)
                  if m and m.PushLadder then m:PushLadder() end
                  local v = Nock:GetModule("PracticeLessonView", true)
                  if v and v.Toggle then v:Toggle(true)
                  else Nock:SendMessage("NOCK_PRACTICE_LESSON_TOGGLE") end
                end,
              },
              practiceLadderReset = {
                type = "execute",
                name = "Reset ladder progress",
                desc = "Clear every drill mark and put the ladder back on the first rung.",
                order = 43,
                width = 1.2,
                confirm = true,
                confirmText = "Reset the drill ladder? Every rung goes back to unfinished.",
                func = function()
                  local m = Nock:GetModule("Practice", true)
                  if m and m.ResetLadder then m:ResetLadder() end
                end,
              },
              verdictsHeader = { type = "header", name = "Verdicts", order = 50 },
              practiceVerdictsDesc = {
                type = "description", order = 51,
                name = "CLIP — an auto fired late because of your cast. LATE — GCD sat idle while a shot fit. STEADY WON'T FIT — a Steady that could not finish before the wind-up while Multi or Arcane was ready. CATCH-UP MULTI MISSED — a Steady where the next cycle wanted a Multi. GOOD — everything else. EARLY — an opener cooldown fired before its anchor (Rapid Fire before the Lust you anchored on, say). Mashing a key is never a fault; a press made before the shot is ready is counted on the scorecard, not graded.\n\nWeave verdicts (Weave Bind on): WEAVE OK — a completed weave inside the leg-time budget. WEAVE SLOW — a weave finished, but one leg (in, dwell or out) ran over the slow-leg threshold. WEAVE MISSED — a whole free window passed with no weave attempt. RE-ARM — the weave key was released before the melee swing had recharged, costing a retry-grid delay. DEAD ZONE — you stayed in melee past the point a Steady would still fit; step out.",
              },
            },
          },
          opener = {
            type = "group",
            name = "Opener",
            order = 2,
            args = {
              practiceOpenerAnchor = {
                type = "select",
                name = "Anchor",
                desc = "What the opener's cooldown burst lines up on: the pull itself, Bloodlust/Heroism landing, Drums, a Haste Potion, or Rapid Fire.",
                order = 1,
                dialogControl = lsmWidget(nil, "plain"),
                values = { pull = "Pull", lust = "Bloodlust lands", drums = "Drums", pot = "Haste Potion", rf = "Rapid Fire" },
                sorting = { "pull", "lust", "drums", "pot", "rf" },
                get = function() return Nock.db.profile.practiceOpenerAnchor or "pull" end,
                set = function(_, v) Nock.db.profile.practiceOpenerAnchor = v end,
              },
              practiceOpenerGcds = {
                type = "range",
                name = "Opener GCDs",
                desc = "How many GCDs the opener drill covers before it hands off to the normal rotation.",
                min = 1, max = 4, step = 1,
                order = 2,
                get = function() return Nock.db.profile.practiceOpenerGcds or 2 end,
                set = function(_, v) Nock.db.profile.practiceOpenerGcds = v end,
              },
              practiceOpenerSteadySec = {
                type = "range",
                name = "Opener Steady cast (s)",
                desc = "Cast time budgeted for a Steady Shot inside the opener window.",
                min = 0.2, max = 1.5, step = 0.05,
                order = 3,
                get = function() return Nock.db.profile.practiceOpenerSteadySec or 0.5 end,
                set = function(_, v) Nock.db.profile.practiceOpenerSteadySec = v end,
              },
              practiceOpenerCds = {
                type = "multiselect",
                name = "Cooldowns in the opener",
                desc = "Which cooldowns the opener drill expects you to fire, anchored on the setting above.",
                order = 4,
                values = { RF = "Rapid Fire", Spec = "Bestial Wrath / spec cooldown", T1 = "Trinket 1", T2 = "Trinket 2", Drums = "Drums of Battle", Pot = "Haste Potion" },
                get = function(_, key)
                  local t = Nock.db.profile.practiceOpenerCds
                  if not t then return true end
                  return t[key] ~= false
                end,
                set = function(_, key, v)
                  Nock.db.profile.practiceOpenerCds = Nock.db.profile.practiceOpenerCds or {}
                  Nock.db.profile.practiceOpenerCds[key] = v
                end,
              },
            },
          },
          keys = {
            type = "group",
            name = "Keys",
            order = 3,
            args = {
              keysDesc = {
                type = "description", order = 1,
                name = "Keys are read from your action bars (Blizzard bars and Dominos). Click a field and press the key (combos like Shift-2 work); Escape clears it. Leave empty to use detection.",
              },
              practiceKeySteady = {
                type = "keybinding", name = "Steady Shot key", order = 10,
                get = function() return (Nock.db.profile.practiceKeys or {}).steady or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceKeys = Nock.db.profile.practiceKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  Nock.db.profile.practiceKeys.steady = (m and m.NormalizeKey or string.upper)(v or "")
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceKeyMulti = {
                type = "keybinding", name = "Multi-Shot key", order = 11,
                get = function() return (Nock.db.profile.practiceKeys or {}).multi or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceKeys = Nock.db.profile.practiceKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  Nock.db.profile.practiceKeys.multi = (m and m.NormalizeKey or string.upper)(v or "")
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceKeyArcane = {
                type = "keybinding", name = "Arcane Shot key", order = 12,
                get = function() return (Nock.db.profile.practiceKeys or {}).arcane or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceKeys = Nock.db.profile.practiceKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  Nock.db.profile.practiceKeys.arcane = (m and m.NormalizeKey or string.upper)(v or "")
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceKeyAutoShot = {
                type = "keybinding", name = "Auto Shot / start attack key", order = 13,
                get = function() return (Nock.db.profile.practiceKeys or {}).autoshot or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceKeys = Nock.db.profile.practiceKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  Nock.db.profile.practiceKeys.autoshot = (m and m.NormalizeKey or string.upper)(v or "")
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceKeyRF = {
                type = "keybinding", name = "Rapid Fire key", order = 14,
                get = function() return (Nock.db.profile.practiceKeys or {}).rf or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceKeys = Nock.db.profile.practiceKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  Nock.db.profile.practiceKeys.rf = (m and m.NormalizeKey or string.upper)(v or "")
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceKeySpec = {
                type = "keybinding", name = "Bestial Wrath / spec cooldown key", order = 15,
                get = function() return (Nock.db.profile.practiceKeys or {}).spec or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceKeys = Nock.db.profile.practiceKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  Nock.db.profile.practiceKeys.spec = (m and m.NormalizeKey or string.upper)(v or "")
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceKeyT1 = {
                type = "keybinding", name = "Trinket 1 key", order = 16,
                get = function() return (Nock.db.profile.practiceKeys or {}).t1 or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceKeys = Nock.db.profile.practiceKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  Nock.db.profile.practiceKeys.t1 = (m and m.NormalizeKey or string.upper)(v or "")
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceKeyT2 = {
                type = "keybinding", name = "Trinket 2 key", order = 17,
                get = function() return (Nock.db.profile.practiceKeys or {}).t2 or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceKeys = Nock.db.profile.practiceKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  Nock.db.profile.practiceKeys.t2 = (m and m.NormalizeKey or string.upper)(v or "")
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceKeyDrums = {
                type = "keybinding", name = "Drums of Battle key", order = 18,
                get = function() return (Nock.db.profile.practiceKeys or {}).drums or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceKeys = Nock.db.profile.practiceKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  Nock.db.profile.practiceKeys.drums = (m and m.NormalizeKey or string.upper)(v or "")
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceKeyPot = {
                type = "keybinding", name = "Haste Potion key", order = 19,
                get = function() return (Nock.db.profile.practiceKeys or {}).pot or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceKeys = Nock.db.profile.practiceKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  Nock.db.profile.practiceKeys.pot = (m and m.NormalizeKey or string.upper)(v or "")
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              procKeysHeader = { type = "header", name = "Proc keys (practice only)", order = 30 },
              procKeysDesc = {
                type = "description", order = 31,
                name = "A key that pops a proc on the sim during a practice fight -- once: up; again: held for the rest of the fight; again: off. Bound only while practice is on; a key your rotation already holds is left to it. The workbench's Keys page shows the same.",
              },
              practiceProcKeyLust = {
                type = "keybinding", name = "Bloodlust / Heroism", order = 32,
                get = function() return (Nock.db.profile.practiceProcKeys or {}).Lust or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceProcKeys = Nock.db.profile.practiceProcKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  local k = (m and m.NormalizeKey or string.upper)(v or "")
                  Nock.db.profile.practiceProcKeys.Lust = (k ~= "" ) and k or nil
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceProcKeyDrums = {
                type = "keybinding", name = "Drums of Battle", order = 33,
                get = function() return (Nock.db.profile.practiceProcKeys or {}).Drums or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceProcKeys = Nock.db.profile.practiceProcKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  local k = (m and m.NormalizeKey or string.upper)(v or "")
                  Nock.db.profile.practiceProcKeys.Drums = (k ~= "" ) and k or nil
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceProcKeyPot = {
                type = "keybinding", name = "Haste Potion", order = 34,
                get = function() return (Nock.db.profile.practiceProcKeys or {}).Pot or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceProcKeys = Nock.db.profile.practiceProcKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  local k = (m and m.NormalizeKey or string.upper)(v or "")
                  Nock.db.profile.practiceProcKeys.Pot = (k ~= "" ) and k or nil
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceProcKeyDST = {
                type = "keybinding", name = "Dragonspine Trophy proc", order = 35,
                get = function() return (Nock.db.profile.practiceProcKeys or {}).DST or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceProcKeys = Nock.db.profile.practiceProcKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  local k = (m and m.NormalizeKey or string.upper)(v or "")
                  Nock.db.profile.practiceProcKeys.DST = (k ~= "" ) and k or nil
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceProcKeyRF = {
                type = "keybinding", name = "Rapid Fire", order = 36,
                get = function() return (Nock.db.profile.practiceProcKeys or {}).RF or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceProcKeys = Nock.db.profile.practiceProcKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  local k = (m and m.NormalizeKey or string.upper)(v or "")
                  Nock.db.profile.practiceProcKeys.RF = (k ~= "" ) and k or nil
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
              practiceProcKeyQS = {
                type = "keybinding", name = "Quick Shots proc", order = 37,
                get = function() return (Nock.db.profile.practiceProcKeys or {}).QS or "" end,
                set = function(_, v)
                  Nock.db.profile.practiceProcKeys = Nock.db.profile.practiceProcKeys or {}
                  local m = Nock:GetModule("Practice", true)
                  local k = (m and m.NormalizeKey or string.upper)(v or "")
                  Nock.db.profile.practiceProcKeys.QS = (k ~= "" ) and k or nil
                  if m and m.ReapplyKeys then m:ReapplyKeys() end
                end,
              },
            },
          },
          advanced = {
            type = "group",
            name = "Advanced",
            order = 4,
            args = {
              advDesc = {
                type = "description", order = 1, fontSize = "medium",
                name = "Engine tuning. The defaults are the measured ones; a knob here changes how the sim presses, walks and grades, not how the HUD looks. Leave them unless you know what one does.",
              },
              stageGeoHeader = { type = "header", name = "Stage geometry", order = 30 },
              reviewHeader = { type = "header", name = "Review window", order = 40 },
              simHeader = { type = "header", name = "Engine", order = 10 },
              practiceQueueWindow = {
                type = "range",
                name = "Spell queue window (s)",
                desc = "A press this close to the end of the GCD or cast is queued instead of refused.",
                min = 0, max = 0.6, step = 0.05,
                order = 11,
                get = function() return Nock.db.profile.practiceQueueWindow or 0.4 end,
                set = function(_, v) Nock.db.profile.practiceQueueWindow = v end,
              },
              practiceReactionMs = {
                type = "range",
                name = "Reaction tolerance (ms)",
                desc = "Idle GCD time before a press counts as LATE.",
                min = 50, max = 500, step = 10,
                order = 12,
                get = function() return Nock.db.profile.practiceReactionMs or 150 end,
                set = function(_, v) Nock.db.profile.practiceReactionMs = v end,
              },
              practiceMeleeRetryPulse = {
                type = "range",
                name = "Melee retry pulse (s)",
                desc = "How often the sim re-checks whether you've stepped into melee range after the weave key goes down.",
                min = 0, max = 1, step = 0.05,
                order = 13,
                get = function() return Nock.db.profile.practiceMeleeRetryPulse or 0.5 end,
                set = function(_, v) Nock.db.profile.practiceMeleeRetryPulse = v end,
              },
              practiceRearmPulse = {
                type = "range",
                name = "Re-arm pulse (s)",
                desc = "Server re-check pulse the sim charges against an early release of the weave key. 0 uses Nock's own live retry grid.",
                min = 0, max = 1, step = 0.05,
                order = 14,
                get = function() return Nock.db.profile.practiceRearmPulse or 0 end,
                set = function(_, v) Nock.db.profile.practiceRearmPulse = (v > 0) and v or nil end,
              },
              practiceRearmWindupAfterReady = {
                type = "toggle",
                name = "Re-armed shot needs a fresh wind-up",
                desc = "After a weave, when the Auto Shot swing has already recharged: ON = the re-armed shot needs a fresh wind-up first (what the client appears to do); OFF = it fires at once. Calibrate with /nock weavelog.",
                order = 15,
                get = function() return Nock.db.profile.practiceRearmWindupAfterReady ~= false end,
                set = function(_, v) Nock.db.profile.practiceRearmWindupAfterReady = v end,
              },
              practiceLegMaxSec = {
                type = "range",
                name = "Slow leg threshold (s)",
                desc = "A weave leg (in, dwell, or out) slower than this triggers WEAVE SLOW.",
                min = 0.2, max = 1.0, step = 0.05,
                order = 16,
                get = function() return Nock.db.profile.practiceLegMaxSec or 0.4 end,
                set = function(_, v) Nock.db.profile.practiceLegMaxSec = v end,
              },
              practiceSeed = {
                type = "range",
                name = "Seed",
                desc = "Seeds the Quick Shots rolls and crits so a fight is repeatable. Two attempts at the same seed and scenario differ only in what you actually pressed.",
                min = 1, max = 9999, step = 1,
                order = 17,
                get = function() return Nock.db.profile.practiceSeed or 1 end,
                set = function(_, v) Nock.db.profile.practiceSeed = v end,
              },
              practiceHintsReset = {
                type = "execute",
                name = "Reset hints",
                desc = "Shows the first-run hints again.",
                order = 18,
                width = 1.2,
                func = function()
                  Nock.db.profile.practiceHints = {}
                  Nock:SendMessage("NOCK_VISUALS_CHANGED")
                end,
              },
              practiceConveyorPps = {
                type = "range",
                name = "Conveyor speed (px/s)",
                desc = "Horizontal scroll speed of the conveyor.",
                min = 40, max = 160, step = 5,
                order = 31,
                get = function() return Nock.db.profile.practiceConveyorPps or 90 end,
                set = function(_, v) Nock.db.profile.practiceConveyorPps = v end,
              },
              practiceConveyorPast = {
                type = "range",
                name = "Conveyor past (s)",
                desc = "The LEAST history kept visible behind the hit line. The stage shows whatever its width buys at the speed above, so a wide stage shows more than this; a narrow one is held to it.",
                min = 1, max = 4, step = 0.5,
                order = 32,
                get = function() return Nock.db.profile.practiceConveyorPast or 2 end,
                set = function(_, v) Nock.db.profile.practiceConveyorPast = v end,
              },
              practiceConveyorFuture = {
                type = "range",
                name = "Conveyor lookahead (s)",
                desc = "The LEAST lookahead shown ahead of the hit line. The stage shows whatever its width buys at the speed above -- drag the undocked stage's right edge wider and you see more seconds, not stretched notes.",
                min = 2, max = 8, step = 0.5,
                order = 33,
                get = function() return Nock.db.profile.practiceConveyorFuture or 4.5 end,
                set = function(_, v) Nock.db.profile.practiceConveyorFuture = v end,
              },
              practiceConveyorHit = {
                type = "range",
                name = "Hit line position",
                desc = "Where the hit line sits across the conveyor's width, as a fraction from the left edge.",
                min = 0.2, max = 0.45, step = 0.01,
                order = 34,
                get = function() return Nock.db.profile.practiceConveyorHit or 0.30 end,
                set = function(_, v) Nock.db.profile.practiceConveyorHit = v end,
              },
              practiceConveyorDocked = {
                type = "toggle",
                name = "Conveyor docked in the panel",
                desc = "Keep the conveyor as the stage under the practice panel's header strip, at the panel's own width. Turn off to float it in its own movable window, leaving the header on its own -- floating, drag its right edge to set its width (out of combat). Right-clicking the panel's grip docks and undocks it too.",
                order = 35,
                get = function() return Nock.db.profile.practiceConveyorDocked ~= false end,
                set = function(_, v)
                  Nock.db.profile.practiceConveyorDocked = v
                  Nock:SendMessage("NOCK_PRACTICE_DOCK_CHANGED")
                end,
              },
              practiceTimelinePps = {
                type = "range",
                name = "Pixels per second",
                desc = "Horizontal scale of the fight timeline.",
                min = 20, max = 200, step = 5,
                order = 41,
                get = function() return Nock.db.profile.practiceTimelinePps or 80 end,
                set = function(_, v) Nock.db.profile.practiceTimelinePps = v end,
              },
              practiceTimelineOkMarks = {
                type = "toggle",
                name = "Show OK marks too",
                desc = "Mark GOOD / WEAVE OK verdicts on the timeline as well as the misses.",
                order = 42,
                get = function() return Nock.db.profile.practiceTimelineOkMarks == true end,
                set = function(_, v) Nock.db.profile.practiceTimelineOkMarks = v end,
              },
            },
          },
          colours = {
            type = "group",
            name = "Colours & style",
            order = 5,
            args = {
              practiceColorsHeader = { type = "header", name = "Colours", order = 27.93 },
              practiceColorsNote = {
                type = "description", order = 27.931,
                name = "The stage's palette: every lane item. Changes apply on the next rebuild of the strip (a moment).",
              },
              practiceColorAuto   = { type = "color", name = "Auto Shot",        order = 27.932, get = getColor, set = setPracticeColor },
              practiceColorSteady = { type = "color", name = "Steady Shot",      order = 27.933, get = getColor, set = setPracticeColor },
              practiceColorMulti  = { type = "color", name = "Multi-Shot",       order = 27.934, get = getColor, set = setPracticeColor },
              practiceColorArcane = { type = "color", name = "Arcane Shot",      order = 27.935, get = getColor, set = setPracticeColor },
              practiceColorRaptor = { type = "color", name = "Raptor Strike",    order = 27.936, get = getColor, set = setPracticeColor },
              practiceColorWhite  = { type = "color", name = "White swing",      order = 27.937, get = getColor, set = setPracticeColor },
              practiceColorQS     = { type = "color", name = "Quick Shots",      order = 27.938, get = getColor, set = setPracticeColor },
              practiceColorRF     = { type = "color", name = "Rapid Fire",       order = 27.939, get = getColor, set = setPracticeColor },
              practiceColorLust   = { type = "color", name = "Bloodlust",        order = 27.94,  get = getColor, set = setPracticeColor },
              practiceColorDrums  = { type = "color", name = "Drums",            order = 27.941, get = getColor, set = setPracticeColor },
              practiceColorDST    = { type = "color", name = "Dragonspine Trophy", order = 27.942, get = getColor, set = setPracticeColor },
              practiceColorPot    = { type = "color", name = "Haste Potion",     order = 27.943, get = getColor, set = setPracticeColor },
              practiceColorKC     = { type = "color", name = "Kill Command",     order = 27.944, get = getColor, set = setPracticeColor },
              practiceColorWindow = { type = "color", name = "Weave window",     order = 27.945, get = getColor, set = setPracticeColor },
              practiceColorWarn   = { type = "color", name = "Warning (late, tight)", order = 27.946, get = getColor, set = setPracticeColor },
              practiceColorBad    = { type = "color", name = "Fault (clip, miss)", order = 27.947, get = getColor, set = setPracticeColor },
              -- THE STAGE'S STYLE (P3 polish): one select per lever, defined once in
              -- Core/PracticeTimeline.lua (T.STYLE_LEVERS) and shared with
              -- `/nock practice style`. Every one applies live.
              practiceStyleHeader = { type = "header", name = "Stage style", order = 27.95 },
              practiceStyleNote = {
                type = "select", name = "Note body", order = 27.951, dialogControl = lsmWidget(nil, "plain"),
                desc = styleDesc("note"), values = styleValues("note"), sorting = styleSorting("note"),
                get = getStyle, set = setStyle,
              },
              practiceStyleNext = {
                type = "select", name = "Next press", order = 27.952, dialogControl = lsmWidget(nil, "plain"),
                desc = styleDesc("next"), values = styleValues("next"), sorting = styleSorting("next"),
                get = getStyle, set = setStyle,
              },
              practiceStyleMove = {
                type = "select", name = "Move-in", order = 27.953, dialogControl = lsmWidget(nil, "plain"),
                desc = styleDesc("move"), values = styleValues("move"), sorting = styleSorting("move"),
                get = getStyle, set = setStyle,
              },
              practiceStyleHit = {
                type = "select", name = "Hit line", order = 27.954, dialogControl = lsmWidget(nil, "plain"),
                desc = styleDesc("hit"), values = styleValues("hit"), sorting = styleSorting("hit"),
                get = getStyle, set = setStyle,
              },
              practiceStylePast = {
                type = "select", name = "Played notes", order = 27.955, dialogControl = lsmWidget(nil, "plain"),
                desc = styleDesc("past"), values = styleValues("past"), sorting = styleSorting("past"),
                get = getStyle, set = setStyle,
              },
              practiceStyleLanes = {
                type = "select", name = "Lanes", order = 27.956, dialogControl = lsmWidget(nil, "plain"),
                desc = styleDesc("lanes"), values = styleValues("lanes"), sorting = styleSorting("lanes"),
                get = getStyle, set = setStyle,
              },
              practiceStyleAutoTick = {
                type = "select", name = "Release tick", order = 27.957, dialogControl = lsmWidget(nil, "plain"),
                desc = styleDesc("tick"), values = styleValues("tick"), sorting = styleSorting("tick"),
                get = getStyle, set = setStyle,
              },
              practiceStyleWindup = {
                type = "select", name = "Wind-up wash", order = 27.958, dialogControl = lsmWidget(nil, "plain"),
                desc = styleDesc("windup"), values = styleValues("windup"), sorting = styleSorting("windup"),
                get = getStyle, set = setStyle,
              },
              practiceStyleWindupScope = {
                type = "select", name = "Wind-up reaches", order = 27.959, dialogControl = lsmWidget(nil, "plain"),
                desc = styleDesc("scope"), values = styleValues("scope"), sorting = styleSorting("scope"),
                get = getStyle, set = setStyle,
              },
              practiceStyleNote2 = {
                type = "description", order = 27.96,
                name = "Auto Shot's colour is the 'Auto Shot' swatch above (grey by default: the auto is the metronome, not a press). /nock practice style opens a copybox of the whole set; /nock practice demo animates the stage without a fight.",
              },
            },
          },
        },
      },
      experimental = {
        type = "group",
        name = "Experimental",
        order = 20,
        args = {
          intro = {
            type = "description",
            name = "Opt-in, unfinished features. They may change or be removed between versions. Everything here is off by default.\n",
            order = 1,
            fontSize = "medium",
          },
          v3Header = {
            type = "header",
            name = "V3 next-action display",
            order = 10,
          },
          v3Intro = {
            type = "description",
            name = "A big movable icon near your character that always says WHAT to press (GCD/cast as a cooldown swipe, a glow at the press moment, a red HOLD while your Auto Shot is winding up). Toggle with /nock v3. Unlock (General → Lock all frames) to drag the medallion. (Its companion, the simplified Shot Bars lane, graduated to the default look — see the Shot Bars page's \"Use legacy Shot Bars\" to go back.)",
            order = 11,
            fontSize = "medium",
          },
          medallionEnabled = {
            type = "toggle",
            name = "Next-action medallion (ring + icon)",
            desc = "Show the big center-screen next-action medallion — the icon plus its countdown ring.",
            order = 12,
            width = "full",
            get = function() return Nock.db.profile.medallionEnabled end,
            set = function(_, v) visualsSet(_, "medallionEnabled", v) end,
          },
          medallionSize = {
            type = "range",
            name = "Medallion size (px)",
            desc = "Icon size of the medallion.",
            min = 40, max = 96, step = 2,
            order = 13,
            disabled = function() return not Nock.db.profile.medallionEnabled end,
            get = function() return Nock.db.profile.medallionSize end,
            set = function(_, v) visualsSet(_, "medallionSize", v) end,
          },
          ringHeader = {
            type = "header",
            name = "Countdown dial (ring)",
            order = 20,
          },
          ringIntro = {
            type = "description",
            name = "The ring around the medallion: it drains to empty at the moment you press (GCD / cast lockout), and turns its HOLD color counting down to your Auto Shot while you hold.",
            order = 21,
            fontSize = "medium",
          },
          medallionRing = {
            type = "toggle",
            name = "Show countdown dial",
            desc = "Circular timer around the medallion.",
            order = 22,
            width = "full",
            disabled = function() return not Nock.db.profile.medallionEnabled end,
            get = function() return Nock.db.profile.medallionRing end,
            set = function(_, v) visualsSet(_, "medallionRing", v) end,
          },
          medallionRingColorPress = {
            type = "color",
            name = "Lockout color",
            desc = "Ring swipe color while you're on the GCD / casting (counting down to the next press).",
            hasAlpha = true,
            order = 23,
            disabled = function() local p = Nock.db.profile return not (p.medallionEnabled and p.medallionRing) end,
            get = getColor,
            set = setColor,
          },
          medallionRingColorHold = {
            type = "color",
            name = "HOLD color",
            desc = "Ring swipe color during HOLD — while your Auto Shot is winding up and you should not cast.",
            hasAlpha = true,
            order = 24,
            disabled = function() local p = Nock.db.profile return not (p.medallionEnabled and p.medallionRing) end,
            get = getColor,
            set = setColor,
          },
          medallionRingTrackColor = {
            type = "color",
            name = "Track color",
            desc = "The static background ring behind the swipe.",
            hasAlpha = true,
            order = 25,
            disabled = function() local p = Nock.db.profile return not (p.medallionEnabled and p.medallionRing) end,
            get = getColor,
            set = setColor,
          },

          sapperHeader = {
            type = "header",
            name = "Sapper column (Misdirection panel)",
            order = 30,
          },
          sapperIntro = {
            type = "description",
            name = "Adds a Sapper Charge square next to the icon on every row of the Misdirection panel — tanks and hunters alike — and announces the MD + Sapper opener to raid chat. Each hunter row also gets an orange speaker button on its right that calls that hunter out as next up in the rotation.\n\n"
              .. "Your own square is read from the item, so it is exact. Everybody else's is combat-log evidence: a square only lights up once you have actually seen that person use a sapper, and someone who saps out of log range (or before you zoned in) will read as ready when they are not. Goblin and Super Sapper Charge share one 5-minute cooldown.\n\n"
              .. "|cffffcc00The two extra columns cost row width|r — at the default 200px the name gets cramped, so widen the panel under Trackers → Misdirection → Row width.",
            order = 31,
            fontSize = "medium",
          },
          mdSapperEnabled = {
            type = "toggle",
            name = "Track sappers in the Misdirection panel",
            desc = "Show the sapper square on each tracker and tank row. Needs the Misdirection panel itself (Trackers -> Misdirection) to be showing something.",
            order = 32,
            width = "full",
            get = function() return Nock.db.profile.mdSapperEnabled == true end,
            set = function(_, v) visualsSet(_, "mdSapperEnabled", v) end,
          },
          mdSapperAnnounce = {
            type = "toggle",
            name = "Announce MD + Sapper to raid",
            desc = "Send a raid/party line when a sapper goes off inside a hunter's own Misdirection window (\"Sapper + MD -> Tank\"). A sapper with no MD behind it says nothing.",
            order = 33,
            width = "full",
            disabled = function() return not Nock.db.profile.mdSapperEnabled end,
            get = function() return Nock.db.profile.mdSapperAnnounce ~= false end,
            set = function(_, v) Nock.db.profile.mdSapperAnnounce = v end,
          },
          mdSapperAnnounceScope = {
            type = "select",
            name = "Announce for",
            desc = "Whose opener gets called out. Note that every Nock user set to \"All hunters\" announces the same opener, so a raid with three of them posts the line three times — switch to \"Only me\" if it gets noisy.",
            order = 34,
            values = { all = "All hunters in the group", self = "Only me" },
            sorting = { "all", "self" },
            dialogControl = lsmWidget(nil, "plain"),
            disabled = function()
              local p = Nock.db.profile
              return not (p.mdSapperEnabled and p.mdSapperAnnounce ~= false)
            end,
            get = function() return Nock.db.profile.mdSapperAnnounceScope or "all" end,
            set = function(_, v) Nock.db.profile.mdSapperAnnounceScope = v end,
          },
          zoomHeader = {
            type = "header",
            name = "Zoomed weave bar",
            order = 40,
          },
          zoomIntro = {
            type = "description",
            name = "Zooms the range bar's weave view (both the classic Range Finder and the React range bar): the outer part of each side is shaven off and the middle stretched across the full bar — 25% per side at the default 2x level. Same layout, same centered melee-boundary tick — every step just moves the bar further, so it reads faster and more directly. Beyond the zoom window the bar pegs empty/full. The 40-8yd finding ladder is unchanged. Idea by Erda.\n",
            order = 41,
            fontSize = "medium",
          },
          rangeZoomedGlide = {
            type = "toggle",
            name = "Zoom the weave bar",
            desc = "Crop the glide view symmetrically and stretch the rest across the bar. Applies to the classic Range Finder and the React range bar alike.",
            width = "full",
            order = 42,
            get = function() return Nock.db.profile.rangeZoomedGlide end,
            set = function(_, v) visualsSet(_, "rangeZoomedGlide", v) end,
          },
          rangeZoomLevel = {
            type = "range",
            name = "Zoom level",
            desc = "Magnification of the weave view. 2x = the outer 25% per side shaven off; 4x shows only the middle quarter, 8x only the middle eighth (roughly a yard either side of the melee boundary). The melee-boundary tick stays centered at every level.",
            min = 1.5, max = 8, step = 0.25,
            order = 43,
            disabled = function() return not Nock.db.profile.rangeZoomedGlide end,
            get = function() return Nock.db.profile.rangeZoomLevel or 2 end,
            set = function(_, v) visualsSet(_, "rangeZoomLevel", v) end,
          },
          releaseHeader = {
            type = "header",
            name = "Retry-Timer",
            order = 50,
          },
          releaseIntro = {
            type = "description",
            name = "The Retry-Timer is a weave-release timing bar, glued under the HUD in both looks. While you hold the weave key it draws the retry cost of letting go: after |cffffffff/cast !Auto Shot|r the client re-checks on a ~0.5s pulse counted from your press, so a release while the swing is still recharging delays the shot by up to half a second — unless you release exactly 0.5s/1.0s before ready (the green notches) or any time after ready (the wide free zone). The cost boxes redden as the price rises; the readout says the price of releasing right now.\n\n|cffffcc00Unverified on this client|r — the model is 2022 original-Classic lore. /nock weavelog prints a predicted vs measured line on every weave so you can check it on a dummy before trusting the bar.\n",
            order = 51,
            fontSize = "medium",
          },
          releaseBarEnabled = {
            type = "toggle",
            name = "Show the Retry-Timer",
            desc = "Draw the Retry-Timer under the HUD while the weave key is held (and until the auto after your release fires). Works in both the classic and React looks.",
            order = 52,
            width = "full",
            get = function() return Nock.db.profile.releaseBarEnabled == true end,
            set = function(_, v) visualsSet(_, "releaseBarEnabled", v) end,
          },
          releaseBarAlways = {
            type = "toggle",
            name = "Always show (testing)",
            desc = "Keep the bar on screen at all times, not only while the weave key is held. Idle (nothing recharging) it sits dimmed at +0.00 — releasing is free. On by default while the retry model is being verified — turn it off for the intended hold-only behavior.",
            order = 52.5,
            width = "full",
            disabled = function() return not Nock.db.profile.releaseBarEnabled end,
            get = function() return Nock.db.profile.releaseBarAlways ~= false end,
            set = function(_, v) visualsSet(_, "releaseBarAlways", v) end,
          },
          releaseBarHeight = {
            type = "range",
            name = "Bar height (px)",
            desc = "Height of the Retry-Timer.",
            min = 8, max = 30, step = 1,
            order = 53,
            disabled = function() return not Nock.db.profile.releaseBarEnabled end,
            get = function() return Nock.db.profile.releaseBarHeight or 14 end,
            set = function(_, v) visualsSet(_, "releaseBarHeight", v) end,
          },
          releaseBarLabels = {
            type = "toggle",
            name = "Cost readout",
            desc = "The +0.32s figure on the bar's right edge — what releasing this instant costs. Green 0.00 = free.",
            order = 54,
            width = "full",
            disabled = function() return not Nock.db.profile.releaseBarEnabled end,
            get = function() return Nock.db.profile.releaseBarLabels ~= false end,
            set = function(_, v) visualsSet(_, "releaseBarLabels", v) end,
          },
          releaseBarNotches = {
            type = "toggle",
            name = "Free notches",
            desc = "Bright green hairlines at exactly 0.5s / 1.0s / 1.5s before ready, where a release costs nothing. Razor-thin targets — the wide green zone after ready stays the consistent play.",
            order = 55,
            width = "full",
            disabled = function() return not Nock.db.profile.releaseBarEnabled end,
            get = function() return Nock.db.profile.releaseBarNotches ~= false end,
            set = function(_, v) visualsSet(_, "releaseBarNotches", v) end,
          },
        },
      },
      rangeFinder = {
        type = "group",
        name = "Range Finder",
        order = 6,
        args = {
          intro = {
            type = "description",
            name = "One bar, two phases. Beyond ~10 yards it names your yard bracket (finding). Inside, it fills toward the melee tick and recolors by zone: Out color while closing (7-10yd), Sweet in the weave ring, Perfect at the melee edge, Deadzone (red) once you're in melee and can't shoot. RESYNC (orange) means the estimate is re-anchoring — cross a range boundary or stand still a beat.\n",
            order = 1,
            fontSize = "medium",
          },
          rangeFinderHeight = {
            type = "range",
            name = "Bar height (px)",
            desc = "Height of the proximity bar. The HUD rows repack around it.",
            min = 10, max = 48, step = 1, bigStep = 2,
            order = 5,
            get = function() return Nock.db.profile.rangeFinderHeight or 16 end,
            set = function(_, v) visualsSet(_, "rangeFinderHeight", v) end,
          },
          rangeOutColor = {
            type = "color",
            name = "Out / closing",
            desc = "Finding-phase fill and the CLOSE (7-10yd) zone.",
            hasAlpha = true,
            order = 10,
            get = getColor, set = setColor,
          },
          rangeInColor = {
            type = "color",
            name = "Deadzone",
            desc = "In melee, can't shoot — strike and step back out.",
            hasAlpha = true,
            order = 20,
            get = getColor, set = setColor,
          },
          rangePerfectColor = {
            type = "color",
            name = "Perfect spot",
            desc = "The sliver at the melee edge — the weave launch spot.",
            hasAlpha = true,
            order = 30,
            get = getColor, set = setColor,
          },
          rangeCloseColor = {
            type = "color",
            name = "Sweet (weave ring)",
            desc = "Inside the ~7yd ring, outside melee.",
            hasAlpha = true,
            order = 40,
            get = getColor, set = setColor,
          },
          rangeFinderFindingStyle = {
            type = "select",
            name = "Finding style",
            desc = "How the bar shows a target beyond the ~10yd weave zone. Drain: the fill is the distance remaining to the weave zone, emptying as you close in. Block: a solid color-coded block naming the yard bracket.",
            order = 45,
            values = { drain = "Drain (distance remaining)", block = "Color block" },
            sorting = { "drain", "block" },
            dialogControl = lsmWidget(nil, "plain"),  -- LSM Font leak guard
            get = function() return Nock.db.profile.rangeFinderFindingStyle or "drain" end,
            set = function(_, v) visualsSet(_, "rangeFinderFindingStyle", v) end,
          },
          deadZoneHeader = {
            type = "header",
            name = "Dead-zone sound cues",
            order = 50,
          },
          deadZoneIntro = {
            type = "description",
            name = "Play a sound when you enter or leave the dead zone (in melee but can't shoot). Fires on any real zone change — including when a tank repositions the boss. Losing the target stays silent.\n",
            order = 51,
            fontSize = "medium",
          },
          deadZoneSoundChannel = {
            type = "select",
            name = "Output channel",
            desc = "Which audio channel the dead-zone cues play through. Use a channel you don't mute (Master is unaffected by the music/ambience sliders).",
            order = 51.5,
            dialogControl = lsmWidget(nil, "plain"),
            values = soundChannelValues,
            sorting = SOUND_CHANNELS,
            get = function() return Nock.db.profile.deadZoneSoundChannel or "Master" end,
            set = function(_, v) Nock.db.profile.deadZoneSoundChannel = v end,
          },
          deadZoneEnterEnabled = {
            type = "toggle",
            name = "Cue on entering",
            desc = "Play a sound the moment you step into the dead zone.",
            order = 52,
            width = "full",
            get = function() return Nock.db.profile.deadZoneEnterEnabled ~= false end,
            set = function(_, v) Nock.db.profile.deadZoneEnterEnabled = v end,
          },
          deadZoneEnterSound = {
            type = "select",
            name = "Entering sound",
            desc = "Sound played when entering the dead zone. 'None' is silent.",
            order = 53,
            -- Normalise pooled item fonts so this select can't inherit a leaked
            -- typeface from the LSM Font dropdown (shared AceGUI item pool) —
            -- there is no dedicated LSM sound widget to do it for us.
            dialogControl = lsmWidget(nil, "plain"),
            disabled = function() return Nock.db.profile.deadZoneEnterEnabled == false end,
            values = function()
              local lsm = LibStub("LibSharedMedia-3.0", true)
              local out = { ["None"] = "None" }
              if lsm then
                for _, name in ipairs(lsm:List("sound")) do out[name] = name end
              end
              return out
            end,
            get = function() return Nock.db.profile.deadZoneEnterSound or "None" end,
            set = function(_, v) Nock.db.profile.deadZoneEnterSound = v end,
          },
          deadZoneEnterPreview = {
            type = "execute",
            name = "Preview",
            order = 53.5,
            width = "half",
            disabled = function()
              return Nock.db.profile.deadZoneEnterEnabled == false
                or (Nock.db.profile.deadZoneEnterSound or "None") == "None"
            end,
            func = function()
              previewSound(Nock.db.profile.deadZoneEnterSound, Nock.db.profile.deadZoneSoundChannel)
            end,
          },
          deadZoneExitEnabled = {
            type = "toggle",
            name = "Cue on leaving",
            desc = "Play a sound the moment you step out of the dead zone into another live range zone.",
            order = 54,
            width = "full",
            get = function() return Nock.db.profile.deadZoneExitEnabled ~= false end,
            set = function(_, v) Nock.db.profile.deadZoneExitEnabled = v end,
          },
          deadZoneExitSound = {
            type = "select",
            name = "Leaving sound",
            desc = "Sound played when leaving the dead zone. 'None' is silent.",
            order = 55,
            dialogControl = lsmWidget(nil, "plain"),
            disabled = function() return Nock.db.profile.deadZoneExitEnabled == false end,
            values = function()
              local lsm = LibStub("LibSharedMedia-3.0", true)
              local out = { ["None"] = "None" }
              if lsm then
                for _, name in ipairs(lsm:List("sound")) do out[name] = name end
              end
              return out
            end,
            get = function() return Nock.db.profile.deadZoneExitSound or "None" end,
            set = function(_, v) Nock.db.profile.deadZoneExitSound = v end,
          },
          deadZoneExitPreview = {
            type = "execute",
            name = "Preview",
            order = 55.5,
            width = "half",
            disabled = function()
              return Nock.db.profile.deadZoneExitEnabled == false
                or (Nock.db.profile.deadZoneExitSound or "None") == "None"
            end,
            func = function()
              previewSound(Nock.db.profile.deadZoneExitSound, Nock.db.profile.deadZoneSoundChannel)
            end,
          },
        },
      },
      manaBar = {
        type = "group",
        name = "Mana Bar",
        order = 5,
        args = {
          intro = {
            type = "description",
            name = "A thin player-mana bar sitting directly above the range finder. It reads your current mana every frame and fills accordingly.\n",
            order = 1,
            fontSize = "medium",
          },
          showManaBar = {
            type = "toggle",
            name = "Enable mana bar",
            desc = "Show the mana bar. When off it's hidden and the HUD shrinks to reclaim the row (same setting as Classic HUD → Layout → HUD elements → Mana bar).",
            order = 10,
            width = "full",
            get = function() return Nock.db.profile.showManaBar ~= false end,
            set = function(_, v) visualsSet(_, "showManaBar", v) end,
          },
          manaBarColor = {
            type = "color",
            name = "Bar color",
            desc = "Fill color of the mana bar.",
            hasAlpha = true,
            order = 20,
            get = getColor, set = setColor,
          },
          manaBarHeight = {
            type = "range",
            name = "Bar height",
            desc = "Height of the mana bar in pixels. The HUD re-lays out around the new size.",
            min = 6, max = 32, step = 1,
            order = 30,
            get = function() return Nock.db.profile.manaBarHeight or 14 end,
            set = function(_, v) visualsSet(_, "manaBarHeight", v) end,
          },
          manaBarText = {
            type = "select",
            name = "Center text",
            desc = "What the centered label shows.",
            order = 40,
            -- Normalise pooled item fonts so this select can't inherit a
            -- leaked typeface from the LSM Font dropdown (shared AceGUI item
            -- pool) — same guard the Icon border select uses.
            dialogControl = lsmWidget(nil, "plain"),
            values = {
              none    = "None",
              percent = "Percent (e.g. 73%)",
              value   = "Value (e.g. 4820)",
              both    = "Value / Max (e.g. 4820 / 6600)",
            },
            get = function() return Nock.db.profile.manaBarText or "percent" end,
            set = function(_, v) visualsSet(_, "manaBarText", v) end,
          },
        },
      },
      profiles = nil,
    },
  }

  -- The weave-engine tunables are built by the shared factory (they also
  -- render on React → Bars); injected here so the grpEngine regroup below
  -- gathers them exactly as before.
  for k, v in pairs(weaveEngineArgs()) do options.args.rotation.args[k] = v end
  for k, v in pairs(castBarSharedArgs("(same setting as HUD & Bars → Classic HUD → Cast Bar)")) do
    options.args.general.args[k] = v
  end

  -- Inject one inline group per warning from the catalog. Keeps the static
  -- table above lean while letting Warnings.lua own the descriptions/logic.
  local mod = Nock:GetModule("Warnings", true)
  if mod and mod.Catalog and options.args.warnings then
    -- Themed sub-pages: each warning files itself under cat.category; an
    -- unknown or missing category lands in "Other" so a new catalog entry can
    -- never silently vanish from the options.
    local WARNING_CATS = {
      you    = { name = "You",          order = 10 },
      pet    = { name = "Pet",          order = 20 },
      combat = { name = "Combat",       order = 30 },
      gear   = { name = "Gear & Binds", order = 40 },
      boss   = { name = "Boss",         order = 50 },
      other  = { name = "Other",        order = 90 },
    }
    local function warningCatNode(catKey)
      local key = WARNING_CATS[catKey] and catKey or "other"
      local nodeKey = "cat_" .. key
      local node = options.args.warnings.args[nodeKey]
      if not node then
        node = { type = "group", name = WARNING_CATS[key].name,
                 order = WARNING_CATS[key].order, args = {} }
        options.args.warnings.args[nodeKey] = node
      end
      return node
    end
    local order = 100
    for _, cat in ipairs(mod.Catalog) do
      warningCatNode(cat.category).args["warning_" .. cat.key] = buildWarningGroup(cat, order)
      order = order + 10
    end
  end

  -- Inject one inline group per setup check (FojjiCore loaded, SpellQueueWindow
  -- value, etc.) into the General tab below the existing controls.
  local setup = Nock:GetModule("SetupCheck", true)
  if setup and setup.Checks and options.args.general then
    local order = 70
    for _, check in ipairs(setup.Checks) do
      if not (check.applies and not check.applies()) then
        options.args.general.args["setup_" .. check.key] = buildSetupCheckGroup(check, order)
        order = order + 10
      end
    end
  end

  -- Inject one inline group per helper. The Helpers catalog has the same
  -- shape (key/name/enabledKey/iconFn/description/logic) as the Warnings
  -- catalog, so the same builder can render it.
  local helpers = Nock:GetModule("Helpers", true)
  if helpers and helpers.Catalog and options.args.helpers then
    local order = 100
    for _, cat in ipairs(helpers.Catalog) do
      options.args.helpers.args["helper_" .. cat.key] = buildWarningGroup(cat, order)
      order = order + 10
    end
  end

  -- Inject per-entry buff-tracker toggles (player @200+, pet @300+) generated
  -- from the BuffTracker preset catalog.
  local bt = Nock:GetModule("BuffTracker", true)
  if bt and options.args.buffTracker then
    local function addToggles(catalog, which, baseOrder)
      if not catalog then return end
      local order = baseOrder
      for _, cat in ipairs(catalog) do
        options.args.buffTracker.args["bt_" .. which .. "_" .. cat.key] = {
          type  = "toggle",
          name  = cat.label or cat.key,
          order = order,
          get   = function()
            local d = Nock.db.profile.buffTrackerDisabled
            return not (d and d[which .. ":" .. cat.key])
          end,
          set   = function(_, v)
            local p = Nock.db.profile
            p.buffTrackerDisabled = p.buffTrackerDisabled or {}
            p.buffTrackerDisabled[which .. ":" .. cat.key] = (not v) or nil
            Nock:SendMessage("NOCK_VISUALS_CHANGED")
          end,
        }
        order = order + 1
      end
    end
    addToggles(bt.PlayerCatalog, "player", 200)
    addToggles(bt.PetCatalog,    "pet",    300)
  end

  -- Inject per-curated-entry inline groups (enable + threshold) for the
  -- Shopping List, generated from Constants.SHOPPING_CURATED (orders 100+).
  if options.args.shopping and Nock.Constants.SHOPPING_CURATED then
    local order = 100
    for _, e in ipairs(Nock.Constants.SHOPPING_CURATED) do
      local key, default = e.key, e.threshold or 1
      options.args.shopping.args["shop_" .. key] = {
        type   = "group",
        inline = true,
        name   = e.label or key,
        order  = order,
        args = {
          on = {
            type  = "toggle",
            name  = "Track",
            order = 1,
            get   = function()
              local d = Nock.db.profile.shoppingDisabled
              return not (d and d[key])
            end,
            set   = function(_, v)
              local p = Nock.db.profile
              p.shoppingDisabled = p.shoppingDisabled or {}
              p.shoppingDisabled[key] = (not v) or nil
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
          thr = {
            type     = "range",
            name     = "Keep at least",
            min = 0, max = 20000, step = 1, bigStep = 50,
            order    = 2,
            disabled = function()
              local d = Nock.db.profile.shoppingDisabled
              return (d and d[key]) and true or false
            end,
            get = function()
              local o = Nock.db.profile.shoppingThreshold
              return (o and o[key]) or default
            end,
            set = function(_, val)
              local p = Nock.db.profile
              p.shoppingThreshold = p.shoppingThreshold or {}
              p.shoppingThreshold[key] = val
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          },
        },
      }
      order = order + 1
    end
  end

  -- Inject the per-entry debuff rows (order 200+): one toggle + Up/Down per
  -- tracked key in the engine's resolved order (presets and customs alike),
  -- rebuilt on every move so the list re-sorts under the cursor — the same
  -- shape as the cooldown grid's editor. The toggle writes the tri-state
  -- disable map: true = off, false = explicitly on, absent = the entry's own
  -- default (presets marked defaultOff — Scorpid Sting, Insect Swarm — ship OFF).
  if options.args.debuffTracker and Nock.Constants.DEBUFF_CURATED then
    local dbfArgs = options.args.debuffTracker.args
    local DTMOD = Nock.GetModule and Nock:GetModule("DebuffTracker", true)
    local rebuildDbfArgs

    local function dbfNotify()
      local reg = LibStub("AceConfigRegistry-3.0", true)
      if reg then reg:NotifyChange("Nock") end
    end

    local function dbfEnabled(key)
      if DTMOD and DTMOD.IsEntryEnabled then return DTMOD.IsEntryEnabled(key) end
      local d = Nock.db.profile.debuffTrackerDisabled
      return not (d and d[key])
    end

    local function dbfOrdered()
      if DTMOD and DTMOD.GetOrderedKeys then return DTMOD:GetOrderedKeys() end
      local out = {}
      for _, e in ipairs(Nock.Constants.DEBUFF_CURATED) do out[#out + 1] = e.key end
      return out
    end

    local function dbfSwap(key, dir)
      local ordered = dbfOrdered()
      local idx
      for i, k in ipairs(ordered) do if k == key then idx = i break end end
      if not idx then return end
      local j = idx + dir
      if j < 1 or j > #ordered then return end
      ordered[idx], ordered[j] = ordered[j], ordered[idx]
      Nock.db.profile.debuffTrackerOrder = ordered
      Nock:SendMessage("NOCK_VISUALS_CHANGED")
      rebuildDbfArgs(); dbfNotify()
    end

    rebuildDbfArgs = function()
      for kk in pairs(dbfArgs) do
        if kk:sub(1, 4) == "dbf_" then dbfArgs[kk] = nil end
      end
      dbfArgs.dbf_header = { type = "header", name = "Tracked debuffs (top = first icon)", order = 199 }
      dbfArgs.dbf_resetOrder = {
        type = "execute", name = "Reset order", order = 199.5, width = "half",
        desc = "Return to the built-in order. Does not change which entries are on.",
        func = function()
          Nock.db.profile.debuffTrackerOrder = {}
          Nock:SendMessage("NOCK_VISUALS_CHANGED")
          rebuildDbfArgs(); dbfNotify()
        end,
      }
      local ordered = dbfOrdered()
      local o = 200
      for i, key in ipairs(ordered) do
        local nm = (DTMOD and DTMOD.Describe) and DTMOD:Describe(key) or key
        dbfArgs["dbf_en_" .. key] = {
          type  = "toggle",
          name  = nm,
          order = o,
          width = 1.7,
          get   = function() return dbfEnabled(key) end,
          set   = function(_, v)
            local p = Nock.db.profile
            p.debuffTrackerDisabled = p.debuffTrackerDisabled or {}
            -- false (not nil) when switched ON: a default-off preset must
            -- remember the choice; nil would fall back to its default.
            p.debuffTrackerDisabled[key] = (not v)
            Nock:SendMessage("NOCK_VISUALS_CHANGED")
          end,
        }
        dbfArgs["dbf_up_" .. key] = {
          type = "execute", name = "Up", order = o + 1, width = 0.4,
          disabled = function() return i <= 1 end,
          func = function() dbfSwap(key, -1) end,
        }
        dbfArgs["dbf_dn_" .. key] = {
          type = "execute", name = "Down", order = o + 2, width = 0.5,
          disabled = function() return i >= #ordered end,
          func = function() dbfSwap(key, 1) end,
        }
        o = o + 3
      end
    end
    rebuildDbfArgs()
    -- Custom entries come and go with the text box; re-list on any change.
    dbfRebuildEntries = rebuildDbfArgs
  end

  -- Inject the shared per-panel Background styling block (fill + LSM border)
  -- into each floating panel's tab. Same controls as Classic HUD → Background,
  -- driven by per-panel profile keys; UI/Widgets.lua's ApplyUserPanelStyle
  -- renders them.
  local function injectPanelStyle(group, prefix, startOrder, opacityKey)
    if not group then return end
    for k, v in pairs(panelStyleArgs(prefix, startOrder, opacityKey)) do
      group.args[k] = v
    end
  end
  injectPanelStyle(options.args.misdirect,     "md",            44, "mdBackgroundOpacity")
  injectPanelStyle(options.args.buffTracker,   "buffTracker",   25)
  injectPanelStyle(options.args.debuffTracker, "debuffTracker", 10)
  injectPanelStyle(options.args.shopping,      "shopping",      7)
  -- Order 60 puts the block between the layout sliders (5.x) and the injected
  -- per-helper boxes (100+).
  injectPanelStyle(options.args.helpers,       "helpers",       60)

  ----------------------------------------------------------------------------
  -- Cooldown Grid: configurable shape, reorderable enable list, custom entries.
  -- All mutations fire NOCK_VISUALS_CHANGED (engine RebuildLists + grid
  -- Rebuild + HUD relayout) and refresh this options page in place.
  ----------------------------------------------------------------------------
  do
    local CDMOD = Nock:GetModule("Cooldowns", true)
    local cdArgs = {}
    local cdStage = { type = "spell" }
    local rebuildCdArgs

    local function notify()
      local reg = LibStub("AceConfigRegistry-3.0", true)
      if reg then reg:NotifyChange("Nock") end
    end

    -- spellOrItemName/describe are file-locals (shared with the React HUD tab).

    local function isDisabled(key)
      local d = Nock.db.profile.cooldownDisabled
      return d and d[key] == true
    end

    local function swap(key, dir)
      if not CDMOD then return end
      local ordered = CDMOD:GetOrderedGridKeys()
      local idx
      for i, k in ipairs(ordered) do if k == key then idx = i break end end
      if not idx then return end
      local j = idx + dir
      if j < 1 or j > #ordered then return end
      ordered[idx], ordered[j] = ordered[j], ordered[idx]
      Nock.db.profile.cooldownOrder = ordered
      Nock:SendMessage("NOCK_VISUALS_CHANGED")
      rebuildCdArgs(); notify()
    end

    -- Custom-entry add/remove/keying live in the shared registry above
    -- (customEntriesChanged rebuilds BOTH grid pages).

    rebuildCdArgs = function()
      for kk in pairs(cdArgs) do cdArgs[kk] = nil end
      cdArgs.intro = {
        type = "description", order = 1, fontSize = "medium",
        name = "Configure the cooldown grid. The engine always tracks every built-in entry plus your custom ones (so the rotation/lust/Drums features never break) — this only controls which are shown, in what order, and the grid shape. Entries past Columns × Rows stay tracked but aren't drawn.\n",
      }
      cdArgs.cols = {
        type = "range", name = "Columns", order = 2, min = 1, max = 14, step = 1,
        get = function() return Nock.db.profile.cooldownCols or 7 end,
        set = function(_, v) visualsSet(_, "cooldownCols", v); rebuildCdArgs(); notify() end,
      }
      cdArgs.rows = {
        type = "range", name = "Rows", order = 3, min = 1, max = 6, step = 1,
        get = function() return Nock.db.profile.cooldownRows or 2 end,
        set = function(_, v) visualsSet(_, "cooldownRows", v); rebuildCdArgs(); notify() end,
      }
      cdArgs.resetOrder = {
        type = "execute", name = "Reset order", order = 4, width = "half",
        desc = "Clear custom ordering and return to the built-in catalog order. Does not remove custom entries or change enabled state.",
        func = function()
          Nock.db.profile.cooldownOrder = {}
          Nock:SendMessage("NOCK_VISUALS_CHANGED")
          rebuildCdArgs(); notify()
        end,
      }
      cdArgs.entriesHeader = { type = "header", name = "Tracked entries (top = first slot)", order = 9 }

      local ordered = CDMOD and CDMOD:GetOrderedGridKeys() or {}
      local cols = Nock.db.profile.cooldownCols or 7
      local rows = Nock.db.profile.cooldownRows or 2
      local cap  = cols * rows
      local shown = 0
      local o = 10
      for i, key in ipairs(ordered) do
        local enabled = not isDisabled(key)
        if enabled then shown = shown + 1 end
        local overflow = enabled and shown > cap
        local nm = describe(key)
        if overflow then nm = nm .. "  |cffcc6666[over capacity — tracked, not shown]|r" end
        local e = CDMOD and CDMOD:GetEntry(key)
        local isCustom = e and e.custom

        cdArgs["cd_en_" .. key] = {
          type = "toggle", name = nm, order = o, width = 1.7,
          get = function() return not isDisabled(key) end,
          set = function(_, v)
            local d = Nock.db.profile.cooldownDisabled or {}
            d[key] = (not v) or nil
            Nock.db.profile.cooldownDisabled = d
            Nock:SendMessage("NOCK_VISUALS_CHANGED")
            rebuildCdArgs(); notify()
          end,
        }
        cdArgs["cd_up_" .. key] = {
          type = "execute", name = "Up", order = o + 1, width = 0.4,
          disabled = function() return i <= 1 end,
          func = function() swap(key, -1) end,
        }
        cdArgs["cd_dn_" .. key] = {
          type = "execute", name = "Down", order = o + 2, width = 0.5,
          disabled = function() return i >= #ordered end,
          func = function() swap(key, 1) end,
        }
        if isCustom then
          cdArgs["cd_rm_" .. key] = {
            type = "execute", name = "Remove", order = o + 3, width = 0.6,
            func = function() removeCustomEntry(key) end,
          }
        end
        o = o + 10
      end

      -- (React grid slot toggles moved to the React HUD tab.)
      buildCustomAddForm(cdArgs, 9000, cdStage)
    end

    customEntryRebuilds[#customEntryRebuilds + 1] = rebuildCdArgs
    rebuildCdArgs()
    options.args.cooldownGrid = {
      type  = "group",
      name  = "Cooldown Grid",
      order = 7,
      args  = cdArgs,
    }
  end

  ----------------------------------------------------------------------------
  -- React HUD tab: every React-mode setting in one place — mode switch, size,
  -- element visibility, per-bar readouts and fill directions, grid slots,
  -- buff row (incl. a dynamic custom-proc list) and the curated skin
  -- overrides. Static args plus a wipe-and-refill dynamic section (cdArgs
  -- pattern above).
  ----------------------------------------------------------------------------
  do
    local CN = Nock.Constants
    -- One args table per subtab; the landing page (intro + hudMode) lives on
    -- the react group itself. The dynamic rebuilders below write into their
    -- OWN subtab table — that is why the split happens here at build time
    -- instead of a regroup() at the bottom of the file (a late move would
    -- strand rebuilt keys on the landing page).
    local landingArgs, sizeArgs, barsArgs, rangeArgs, gridArgs, buffArgs, skinArgs =
      {}, {}, {}, {}, {}, {}, {}

    local function notify()
      local reg = LibStub("AceConfigRegistry-3.0", true)
      if reg then reg:NotifyChange("Nock") end
    end

    local notReact = function()
      return (Nock.db.profile.hudMode or "classic") ~= "react"
    end

    -- Default-ON toggle gated on React mode.
    local function reactToggle(key, name, desc, order, width)
      return {
        type = "toggle", name = name, desc = desc, order = order,
        width = width or "full",
        disabled = notReact,
        get = function() return Nock.db.profile[key] ~= false end,
        set = function(_, v) visualsSet(_, key, v) end,
      }
    end

    -- Default-OFF counterpart to reactToggle. The `~= false` shape above would
    -- read an unset key as ON, which is exactly wrong for an opt-in element.
    local function reactOptInToggle(key, name, desc, order)
      return {
        type = "toggle", name = name, desc = desc, order = order, width = "full",
        disabled = notReact,
        get = get,
        set = function(_, v) visualsSet(_, key, v) end,
      }
    end

    landingArgs.intro = {
      type = "description",
      fontSize = "medium",
      order = 1,
      name = "Fixed-skin replica of the React hunter WeakAura: converge-to-center Auto Shot bar, melee bar, slide range finder, thin mana bar, glued cast bar, a 3-row cooldown grid and a proc/utility buff row — replacing the classic rows entirely while active. Configure the content and behavior here; the skin itself stays the reference look apart from the curated knobs under |cffffd100Skin|r. Toggle quickly with |cffffd200/nock react|r.\n",
    }
    landingArgs.hudMode = hudModeSelect(2, "(same setting as General → HUD look)")

    sizeArgs.sizeHeader = { type = "header", name = "Size", order = 10 }
    sizeArgs.reactWidth = {
      type = "range",
      name = "Width",
      desc = "Width of the React bar cluster and cooldown grid, in pixels.",
      min = 160, max = 280, step = 2,
      order = 11,
      disabled = notReact,
      get = get,
      set = function(_, v) visualsSet(_, "reactWidth", v) end,
    }
    sizeArgs.reactScale = {
      type = "range",
      name = "Scale",
      desc = "Per-row scale shared by the React cluster and grid (multiplies on top of the global Scale).",
      min = 0.5, max = 2.0, step = 0.05, bigStep = 0.1,
      order = 12,
      disabled = notReact,
      get = get,
      set = function(_, v) visualsSet(_, "reactScale", v) end,
    }

    sizeArgs.elementsHeader = { type = "header", name = "Elements", order = 20 }
    sizeArgs.elementsNote = {
      type = "description", fontSize = "medium", order = 20.5,
      name = "React-specific — the Classic HUD → Layout → HUD elements toggles don't apply while the React look is active.\n",
    }
    sizeArgs.reactShowAutoBar  = reactToggle("reactShowAutoBar",  "Auto Shot bar",  "The converge Auto Shot bar (clip ticks, delay readout, notation).", 21)
    sizeArgs.reactShowMeleeBar = reactToggle("reactShowMeleeBar", "Melee swing bar", "Melee swing bar with the READY text and weave-coach cues.", 22)
    sizeArgs.reactShowRangeBar = reactToggle("reactShowRangeBar", "Range bar",       "Finding ladder + predictive weave fill.", 23)
    sizeArgs.reactShowManaBar  = reactToggle("reactShowManaBar",  "Mana bar",        "Thin mana bar with the percent readout.", 24)
    sizeArgs.reactManaText = {
      type = "select",
      name = "Mana bar text",
      desc = "Center text on the React mana bar: percent (reference look), the actual mana value, both, or nothing. (The classic mana bar has its own setting under Classic HUD → Mana Bar.)",
      order = 24.5,
      values = { none = "None", percent = "Percent", value = "Value", both = "Value / Max" },
      sorting = { "percent", "value", "both", "none" },
      dialogControl = lsmWidget(nil, "plain"),  -- LSM Font leak guard
      disabled = function()
        return notReact() or Nock.db.profile.reactShowManaBar == false
      end,
      get = function() return Nock.db.profile.reactManaText or "percent" end,
      set = function(_, v) visualsSet(_, "reactManaText", v) end,
    }
    sizeArgs.reactShowCastBar  = reactToggle("reactShowCastBar",  "Cast bar",        "The cast bar glued above the cluster.", 25)
    sizeArgs.reactShowAutoShotCast = reactToggle("reactShowAutoShotCast",
      "Auto Shot wind-up on cast bar",
      "Show the 0.5s Auto Shot wind-up on the React cast bar. On by default in React mode. (The classic HUD has its own switch on the General tab.)",
      25.5)
    sizeArgs.castBarNonCombatCasts =
      castBarSharedArgs("(same setting as General → Cast bar)").castBarNonCombatCasts
    sizeArgs.castBarNonCombatCasts.order = 25.5
    sizeArgs.reactShowGrid     = reactToggle("reactShowGrid",     "Cooldown grid",   "The 3-row cooldown grid under the cluster.", 26)
    sizeArgs.reactShowAspectIcon = reactOptInToggle("reactShowAspectIcon",
      "Aspect corner icon",
      "Show the aspect you're in as an icon above the cluster's top-left corner, greyed when you have no aspect. Off by default: the Aspect warning already covers this, only in combat and only when it's wrong.",
      27)
    sizeArgs.reactShowMarkIcon = reactOptInToggle("reactShowMarkIcon",
      "Hunter's Mark corner icon",
      "Show Hunter's Mark and its remaining time above the cluster's top-right corner, greyed when your target isn't marked. Off by default. A mark applied by another hunter counts.",
      28)

    -- Bar order editor: the fixed 4-item cousin of the CD-row editor below.
    -- The four rows are STATIC args whose names re-read the effective order on
    -- every options refresh, so a swap only needs NotifyChange — none of the
    -- CD editor's wipe-and-refill machinery. The stored order self-heals: it
    -- is re-derived through ResolveReactBarOrder on every materialize, so a
    -- stale or hand-damaged profile array can't wedge the executes.
    sizeArgs.orderHeader = { type = "header", name = "Bar order", order = 29 }
    local BAR_LABELS = {
      auto  = "Auto Shot bar",
      melee = "Melee swing bar",
      range = "Range bar",
      mana  = "Mana bar",
    }
    local function effectiveOrder()
      return Nock.UI.ResolveReactBarOrder(Nock.db.profile.reactBarOrder)
    end
    -- First edit materializes the built-in order into the profile (CD-row
    -- convention). Copies — the resolver's fallback is its shared built-in
    -- table, which a swap must never mutate.
    local function materializedOrder()
      local p = Nock.db.profile
      local eff = effectiveOrder()
      if type(p.reactBarOrder) ~= "table" then p.reactBarOrder = {} end
      local t = p.reactBarOrder
      for i = 1, #eff do t[i] = eff[i] end
      for i = #eff + 1, #t do t[i] = nil end
      return t
    end
    local function orderChanged()
      Nock:SendMessage("NOCK_VISUALS_CHANGED")
      notify()
    end
    for i = 1, 4 do
      local idx = i
      sizeArgs["order_lbl_" .. idx] = {
        type = "description", fontSize = "medium", width = 1.4,
        order = 29 + idx * 0.1,
        name = function()
          local k = effectiveOrder()[idx]
          return ("%d.  %s"):format(idx, BAR_LABELS[k] or tostring(k))
        end,
      }
      sizeArgs["order_up_" .. idx] = {
        type = "execute", name = "Up", width = 0.4,
        order = 29 + idx * 0.1 + 0.01,
        disabled = function() return notReact() or idx == 1 end,
        func = function()
          local t = materializedOrder()
          t[idx], t[idx - 1] = t[idx - 1], t[idx]
          orderChanged()
        end,
      }
      sizeArgs["order_dn_" .. idx] = {
        type = "execute", name = "Down", width = 0.5,
        order = 29 + idx * 0.1 + 0.02,
        disabled = function() return notReact() or idx == 4 end,
        func = function()
          local t = materializedOrder()
          t[idx], t[idx + 1] = t[idx + 1], t[idx]
          orderChanged()
        end,
      }
    end
    sizeArgs.order_reset = {
      type = "execute", name = "Reset order to default", width = 1.2,
      order = 29.9,
      disabled = function()
        return notReact() or type(Nock.db.profile.reactBarOrder) ~= "table"
      end,
      func = function()
        Nock.db.profile.reactBarOrder = false
        orderChanged()
      end,
    }

    barsArgs.autoHeader = { type = "header", name = "Auto Shot bar", order = 30 }
    -- Annotated miniature of the converge bar (UI/AceGUI_BarLegends.lua). No
    -- `width` key, so AceConfigDialog gives it control.width = "fill".
    barsArgs.reactAutoLegend = {
      type = "description",
      name = "",
      dialogControl = "NockReactBarLegend",
      order = 30.5,
    }
    barsArgs.reactShowNotation = reactToggle("reactShowNotation", "Rotation notation",
      "The rotation notation (e.g. \"1:1\", \"6:9:1:1 3w\") right-aligned on the Auto Shot bar.", 31)
    barsArgs.reactShowDelay = {
      type = "toggle",
      name = "Auto Shot delay readout",
      desc = "Show the +x.xx late-shot readout centered on the React Auto Shot bar. Hidden by default.",
      order = 32,
      width = "full",
      disabled = notReact,
      get = get,
      set = function(_, v) visualsSet(_, "reactShowDelay", v) end,
    }
    barsArgs.reactShowBrackets = {
      type = "toggle",
      name = "eWS bracket marks",
      desc = "Mark the eWS rotation-bracket bounds (where the notation changes) on the React Auto Shot bar. Hidden by default — the red/orange clip ticks are always shown.",
      order = 33,
      width = "full",
      disabled = notReact,
      get = get,
      set = function(_, v) visualsSet(_, "reactShowBrackets", v) end,
    }
    barsArgs.reactShowGcdDivider = {
      type = "toggle",
      name = "GCD divider",
      desc = "Draw the global cooldown on the React Auto Shot bar as a moving purple divider. Unlike the clip ticks it is not a fixed threshold — it runs the GCD's own progress across the bar the way the gold fill runs the swing, and follows the Auto Shot bar's fill direction: Converge puts one line in from each edge, left/right a single line from the fill's origin edge. Nothing is drawn while you are off the GCD.",
      order = 34,
      width = "full",
      disabled = notReact,
      get = get,
      set = function(_, v) visualsSet(_, "reactShowGcdDivider", v) end,
    }

    barsArgs.dirHeader = { type = "header", name = "Fill direction", order = 35 }
    barsArgs.reactDirAuto = {
      type = "select",
      name = "Auto Shot bar",
      desc = "Converge (reference): both halves close on the center at the fire moment. Left/right: a single fill across the bar; the clip ticks and eWS marks follow the fill's origin edge.",
      order = 36,
      values = { converge = "Converge to center (reference)", ltr = "Left to right", rtl = "Right to left" },
      sorting = { "converge", "ltr", "rtl" },
      dialogControl = lsmWidget(nil, "plain"),  -- LSM Font leak guard
      disabled = notReact,
      get = function() return Nock.db.profile.reactDirAuto or "converge" end,
      set = function(_, v) visualsSet(_, "reactDirAuto", v) end,
    }
    barsArgs.reactDirMelee = {
      type = "select",
      name = "Melee swing bar",
      desc = "Which edge the melee swing fill grows from.",
      order = 37,
      values = { ltr = "Left to right", rtl = "Right to left" },
      sorting = { "ltr", "rtl" },
      dialogControl = lsmWidget(nil, "plain"),  -- LSM Font leak guard
      disabled = notReact,
      get = function() return Nock.db.profile.reactDirMelee or "ltr" end,
      set = function(_, v) visualsSet(_, "reactDirMelee", v) end,
    }

    barsArgs.grpEngine = {
      type = "group",
      inline = true,
      name = "Weave engine (same settings as Classic → Shot Bars)",
      order = 38,
      args = weaveEngineArgs(),
    }

    rangeArgs.rangeHeader = { type = "header", name = "Range bar", order = 40 }
    rangeArgs.rangeFinderFindingStyle = {
      type = "select",
      name = "Finding style",
      desc = "How the bar shows a target beyond the ~10yd weave zone. Drain: the fill is the distance remaining to the weave zone, emptying as you close in. Block: a solid color-coded block naming the yard bracket. Shared with the classic Range Finder — changing it here changes it there too.",
      order = 41,
      values = { drain = "Drain (distance remaining)", block = "Color block" },
      sorting = { "drain", "block" },
      dialogControl = lsmWidget(nil, "plain"),  -- LSM Font leak guard
      disabled = notReact,
      get = function() return Nock.db.profile.rangeFinderFindingStyle or "drain" end,
      set = function(_, v) visualsSet(_, "rangeFinderFindingStyle", v) end,
    }
    gridArgs.gridHeader = { type = "header", name = "Cooldown grid", order = 50 }
    gridArgs.gridNote = {
      type = "description", fontSize = "medium", order = 50.5,
      name = "Three fixed row styles (large rotation tiles / small utility tiles / consumables) with fully editable contents: untick to hide a slot, Up/Down to reorder, X to remove, or add any tracked ability — including the shared custom entries below. Rows re-center around gaps; an emptied row collapses.\n",
    }
    local ROW_TITLES = {
      "Row 1 — Rotation (large tiles)",
      "Row 2 — Utility cooldowns",
      "Row 3 — Consumables (shown while active)",
    }

    -- Effective per-row key lists: the user's reactCdRows when set, else the
    -- built-in layout. Always returns fresh copies safe to hand out.
    local function effectiveRows()
      local custom = Nock.db.profile.reactCdRows
      local rows = {}
      for i, def in ipairs(CN.REACT_CD_ROWS) do
        local src = (type(custom) == "table" and type(custom[i]) == "table")
                    and custom[i] or def.keys
        local copy = {}
        for j = 1, #src do copy[j] = src[j] end
        rows[i] = copy
      end
      return rows
    end
    -- First edit materializes the built-in layout into the profile.
    local function materializedRows()
      local p = Nock.db.profile
      if type(p.reactCdRows) ~= "table" then p.reactCdRows = effectiveRows() end
      return p.reactCdRows
    end

    local rebuildGridArgs
    local function gridChanged()
      Nock:SendMessage("NOCK_VISUALS_CHANGED")
      rebuildGridArgs()
      notify()
    end

    -- Dynamic per-row editor (cdArgs wipe-and-refill pattern): per placed
    -- entry a hide-toggle + Up/Down/X, per row an instant-add dropdown of
    -- every tracked ability not placed yet.
    rebuildGridArgs = function()
      for k in pairs(gridArgs) do
        if k:sub(1, 4) == "rcd_" then gridArgs[k] = nil end
      end
      local rows = effectiveRows()
      local placed = {}
      for _, keys in ipairs(rows) do
        for _, k in ipairs(keys) do placed[k] = true end
      end
      local o = 51
      local function nextO() o = o + 0.01; return o end
      for rowIndex, keys in ipairs(rows) do
        gridArgs["rcd_row" .. rowIndex] = {
          type = "description", fontSize = "medium", order = nextO(),
          name = ROW_TITLES[rowIndex] or ("Row " .. rowIndex),
        }
        local rowLen = #keys
        for i, rkey in ipairs(keys) do
          local key, idx, ri = rkey, i, rowIndex
          gridArgs["rcd_en_" .. ri .. "_" .. idx] = {
            type = "toggle", order = nextO(), width = 1.4,
            name = describe(key),
            desc = "Untick to hide the slot without removing it from the row.",
            disabled = notReact,
            get = function()
              local d = Nock.db.profile.reactCooldownDisabled
              return not (d and d[key] == true)
            end,
            set = function(_, v)
              local d = Nock.db.profile.reactCooldownDisabled or {}
              d[key] = (not v) or nil
              Nock.db.profile.reactCooldownDisabled = d
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
            end,
          }
          gridArgs["rcd_up_" .. ri .. "_" .. idx] = {
            type = "execute", name = "Up", order = nextO(), width = 0.4,
            disabled = function() return notReact() or idx == 1 end,
            func = function()
              local r = materializedRows()[ri]
              r[idx], r[idx - 1] = r[idx - 1], r[idx]
              gridChanged()
            end,
          }
          gridArgs["rcd_dn_" .. ri .. "_" .. idx] = {
            type = "execute", name = "Down", order = nextO(), width = 0.5,
            disabled = function() return notReact() or idx == rowLen end,
            func = function()
              local r = materializedRows()[ri]
              r[idx], r[idx + 1] = r[idx + 1], r[idx]
              gridChanged()
            end,
          }
          gridArgs["rcd_rm_" .. ri .. "_" .. idx] = {
            type = "execute", name = "X", order = nextO(), width = 0.3,
            desc = "Remove from the row (re-add it with the row's Add dropdown).",
            disabled = notReact,
            func = function()
              table.remove(materializedRows()[ri], idx)
              gridChanged()
            end,
          }
        end
        local ri = rowIndex
        gridArgs["rcd_add_" .. ri] = {
          type = "select", name = "Add to this row", order = nextO(), width = 1.4,
          desc = "Adds the picked ability to the end of this row. The list covers everything Nock tracks, including the shared custom entries defined below.",
          dialogControl = lsmWidget(nil, "plain"),  -- LSM Font leak guard
          disabled = notReact,
          values = function()
            local CDMOD = Nock:GetModule("Cooldowns", true)
            local out = {}
            if CDMOD then
              for _, e in ipairs(CDMOD:GetTracked()) do
                if not placed[e.key] then out[e.key] = describe(e.key) end
              end
            end
            return out
          end,
          get = function() return nil end,
          set = function(_, v)
            if not v or placed[v] then return end
            local r = materializedRows()[ri]
            r[#r + 1] = v
            gridChanged()
          end,
        }
      end
      gridArgs.rcd_reset = {
        type = "execute", name = "Reset rows to default", order = nextO(), width = 1.0,
        confirm = true,
        confirmText = "Reset the React grid rows to the built-in layout? (Hidden-slot ticks are kept.)",
        disabled = function()
          return notReact() or type(Nock.db.profile.reactCdRows) ~= "table"
        end,
        func = function()
          Nock.db.profile.reactCdRows = false
          gridChanged()
        end,
      }
    end
    rebuildGridArgs()
    gridArgs.reactConsumablesAlways = {
      type = "toggle",
      name = "Always show consumables",
      desc = "Keep row 3's slots visible while idle (dormant icons) instead of the reference behavior of appearing only while a consumable is on cooldown or its buff is running.",
      order = 68,
      width = "full",
      disabled = notReact,
      get = get,
      set = function(_, v) visualsSet(_, "reactConsumablesAlways", v) end,
    }

    -- Glows & tints (the reference WA's icon conditions): the Kill Command glows, the per-slot range tint, dim, no-mana.
    -- All three ship OFF (user, 2026-08-29). kcActionBarGlow lights the real
    -- bar button, so it is not React-gated — but it lives here, where the user
    -- asked for it.
    gridArgs.kcHeader = { type = "header", name = "Glows & tints", order = 69 }
    gridArgs.reactKcProcGlow = {
      type = "toggle",
      name = "Kill Command proc glow",
      desc = "While the Kill Command proc is up, the KC tile gets the animated action-button glow (as in the reference WeakAura) instead of the static highlight border.",
      order = 69.1, width = "full", disabled = notReact,
      get = get,
      set = function(_, v) visualsSet(_, "reactKcProcGlow", v) end,
    }
    gridArgs.kcActionBarGlow = {
      type = "toggle",
      name = "Kill Command glow on the action bar",
      desc = "Also glow the real action-bar button(s) that hold Kill Command (or a macro casting it) while the proc is up. Blizzard bars, Dominos, Bartender4 and ElvUI bars are found; works in combat. Not tied to the HUD mode.",
      order = 69.2, width = "full",
      get = get,
      set = function(_, v) visualsSet(_, "kcActionBarGlow", v) end,
    }
    gridArgs.reactRangeTint = {
      type = "select",
      name = "Out of range",
      desc = "Tint a grid tile whose spell cannot reach the current target (per spell, as the reference WeakAura does): shots go out of range in the dead zone and beyond max range, Raptor Strike outside melee. Item tiles are never tinted.",
      order = 69.3,
      values = { off = "Off", red = "Red tint", grey = "Greyed out" },
      sorting = { "off", "red", "grey" },
      dialogControl = lsmWidget(nil, "plain"),  -- LSM Font leak guard
      disabled = notReact,
      get = function() return Nock.db.profile.reactRangeTint or "off" end,
      set = function(_, v) visualsSet(_, "reactRangeTint", v) end,
    }
    gridArgs.reactTileDim = {
      type = "toggle",
      name = "Dim while unavailable",
      desc = "A tile that is on cooldown or whose spell is not usable right now (no Kill Command proc, pet dead, ...) is greyed out at 60% -- the reference WeakAura's look. Consumable tiles keep their own grey.",
      order = 69.4, width = "full", disabled = notReact,
      get = get,
      set = function(_, v) visualsSet(_, "reactTileDim", v) end,
    }
    gridArgs.reactManaTint = {
      type = "toggle",
      name = "No mana: blue",
      desc = "A tile whose spell you cannot afford is tinted blue and greyed, as in the reference WeakAura. Out of range (red) wins when both apply.",
      order = 69.5, width = "full", disabled = notReact,
      get = get,
      set = function(_, v) visualsSet(_, "reactManaTint", v) end,
    }

    -- Shared custom entries: the same profile.cooldownCustom store the classic
    -- grid edits. The manage list here is customs-only (built-ins live in the
    -- classic ordered list); adds surface in the row Add dropdowns above.
    local reactCdStage = { type = "spell" }
    gridArgs.rcustHeader = {
      type = "header", name = "Custom entries (shared with the classic grid)", order = 70,
    }
    local function rebuildReactCustomList()
      for k in pairs(gridArgs) do
        if type(k) == "string" and k:sub(1, 6) == "rcust_" then gridArgs[k] = nil end
      end
      local list = Nock.db.profile.cooldownCustom or {}
      for i, rec in ipairs(list) do
        local key = customEntryKey(rec)
        gridArgs["rcust_" .. i] = {
          type = "description", fontSize = "medium", width = 1.7,
          order = 71 + (i - 1) * 0.1,
          name = describe(key),
        }
        gridArgs["rcust_rm_" .. i] = {
          type = "execute", name = "Remove", width = 0.5,
          order = 71 + (i - 1) * 0.1 + 0.05,
          func = function() removeCustomEntry(key) end,
        }
      end
    end
    rebuildReactCustomList()
    customEntryRebuilds[#customEntryRebuilds + 1] = rebuildReactCustomList
    buildCustomAddForm(gridArgs, 80, reactCdStage)

    -- Buff Row settings, built ONCE PER SIDE — Classic HUD → Buff Row and
    -- React HUD → Buff Row — from one builder (the cast-bar pattern). Every
    -- control but the master switch reads and writes the SAME profile key on
    -- both pages, so the two are in sync by construction; per side there is
    -- only the master switch (showBuffRow / reactBuffRows), the mode gate and
    -- the note naming the other page. The row itself is one module
    -- (UI/Frame_ReactBuffs.lua) hosted by the cluster in React and by the
    -- HUD cascade in Classic — placement and scale are the per-mode part.
    local notClassic = function() return not notReact() end
    local buffCustomRebuilds = {}
    local function rebuildAllBuffCustom()
      for i = 1, #buffCustomRebuilds do buffCustomRebuilds[i]() end
    end
    local function fillBuffArgs(args, side)
      local react     = (side == "react")
      local notMode   = react and notReact or notClassic
      local masterKey = react and "reactBuffRows" or "showBuffRow"
      local other     = react and "Classic HUD → Buff Row" or "React HUD → Buff Row"

      args.buffHeader = { type = "header", name = "Buff row", order = 70 }
      args.sharedNote = {
        type = "description", fontSize = "medium", order = 70.1,
        name = "Shared with |cffffd200" .. other .. "|r: only the on/off switch, the placement and the scale are per HUD mode. Every other setting on this page is the same setting on both pages.\n",
      }
      args[masterKey] = {
        type = "toggle",
        name = "Buff row (procs + utility)",
        desc = react
          and "One icon row centered above the HUD, growing from the center: haste/burst procs (Bloodlust, Drums, Rapid Fire, Quick Shots, The Beast Within, Haste Potion, racials, trinket procs) plus utility buffs (Feign Death, Misdirection, Mend/Feed Pet, Intimidation, Windfury enchant, Leader of the Pack / Grace of Air range, the pet's Frenzy, the MOVE IN alert). While on, it replaces the classic Buff Tracker and Totem panels.\n\nThe row is movable: unlock the HUD (/nock unlock) and drag it anywhere — below the HUD, off to one side — or use its nudge pad for exact placement. The position is relative to the HUD, so it follows scale and drags. The pad's reset button puts it back above."
          or  "The React HUD's proc row above the Classic HUD, in the React look: haste/burst procs (Bloodlust, Drums, Rapid Fire, Quick Shots, The Beast Within, Haste Potion, racials, trinket procs) plus utility buffs (Feign Death, Misdirection, Mend/Feed Pet, Intimidation, Windfury enchant, Leader of the Pack / Grace of Air range, the pet's Frenzy, the MOVE IN alert).\n\nIt floats just above the cast bar by default. Unlock the HUD (/nock unlock) and drag it anywhere, or use its nudge pad; the position is relative to the HUD, so it follows scale and drags, and the pad's reset puts it back above the cast bar. Its own scale is under Layout → Per-element scaling. Same switch as Layout → HUD elements → Buff row.",
        order = 70.5,
        width = "full",
        disabled = notMode,
        get = function() return Nock.db.profile[masterKey] ~= false end,
        set = function(_, v) visualsSet(_, masterKey, v) end,
      }
      local buffDep = function()
        return notMode() or Nock.db.profile[masterKey] == false
      end
      args.reactBuffPositional = {
        type = "toggle",
        name = "Positional labels (RANGE / MISSING)",
        desc = "In combat, the Leader of the Pack / Grace of Air icons flag when the aura is on your subgroup but not on you (RANGE — step back in) or absent entirely with a shaman present (MISSING). Off also skips the subgroup buff sweep.",
        order = 71,
        width = "full",
        disabled = buffDep,
        get = function() return Nock.db.profile.reactBuffPositional ~= false end,
        set = function(_, v) visualsSet(_, "reactBuffPositional", v) end,
      }
      args.reactBuffFrenzyMode = {
        type = "select",
        name = "Pet Frenzy",
        desc = "How the pet's Frenzy proc is shown.\n\nWhen up: a slot while the proc runs, like any other buff.\n\nMissing on bosses: with a raid boss targeted the slot is always there in combat — bright while Frenzy is up, greyed while it is down, and MISSING once it has been down 2 seconds (a dropped proc, not the gap between two). Elsewhere it shows when up.\n\nMissing always: that alert mode in every fight.\n\nNeeds the Frenzy talent and a live pet; the Frenzy toggle below hides it entirely.",
        order = 71.5,
        width = 1.6,
        dialogControl = lsmWidget(nil, "plain"),
        disabled = buffDep,
        values = { up = "When up", boss = "Missing on bosses", missing = "Missing always" },
        sorting = { "up", "boss", "missing" },
        get = function() return Nock.db.profile.reactBuffFrenzyMode or "boss" end,
        set = function(_, v) visualsSet(_, "reactBuffFrenzyMode", v) end,
      }
      -- Per-entry hides for the utility icons (the proc list is ID-matched and
      -- transient, so it gets no per-entry toggles — hide the row instead).
      local BUFF_ENTRIES = {
        { key = "mendPet",      id = CN.REACT_BUFFS.MEND_PET,          fallback = "Mend Pet" },
        { key = "feedPet",      id = CN.REACT_BUFFS.FEED_PET,          fallback = "Feed Pet" },
        { key = "intimidation", id = CN.REACT_BUFFS.INTIMIDATION_BUFF, fallback = "Intimidation" },
        { key = "feign",        id = CN.SpellID.FEIGN_DEATH,           fallback = "Feign Death" },
        { key = "misdirect",    id = CN.SpellID.MISDIRECTION,          fallback = "Misdirection" },
        { key = "lotp",         id = CN.REACT_BUFFS.LOTP,              fallback = "Leader of the Pack" },
        { key = "grace",        id = CN.SpellID.GRACE_OF_AIR,          fallback = "Grace of Air" },
        { key = "windfury",     id = nil,                              fallback = "Windfury (weapon enchant)" },
        { key = "frenzy",       id = CN.REACT_BUFFS.FRENZY,            fallback = "Frenzy (pet proc)" },
        { key = "movein",       id = nil,                              fallback = "MOVE IN (target out of Auto Shot range)" },
      }
      local bo = 72
      for _, be in ipairs(BUFF_ENTRIES) do
        local key = be.key
        local label
        if be.id then
          label = ("%s  |cff808080(spell %d)|r"):format(optSpellName(be.id) or be.fallback, be.id)
        else
          label = be.fallback
        end
        args["rb_en_" .. key] = {
          type = "toggle", name = label, order = bo, width = 0.9,
          disabled = buffDep,
          get = function()
            local d = Nock.db.profile.reactBuffDisabled
            return not (d and d[key] == true)
          end,
          set = function(_, v)
            local d = Nock.db.profile.reactBuffDisabled or {}
            d[key] = (not v) or nil
            Nock.db.profile.reactBuffDisabled = d
            Nock:SendMessage("NOCK_VISUALS_CHANGED")
          end,
        }
        bo = bo + 1
      end

      args.customHeader = { type = "header", name = "Custom proc buffs", order = 81 }
      args.customNote = {
        type = "description", fontSize = "medium", order = 81.5,
        name = "Extra buff spell IDs merged into the procs row — for trinkets or set bonuses the built-in list doesn't know. Use the AURA's exact spell ID (rank-specific), the one on you while the proc is up (Wowhead's TBC database has them).\n",
      }
      local stagedBuffId
      -- Both sides list the same store, so a Remove/Add on either page rebuilds
      -- BOTH lists (buffCustomRebuilds), never just its own.
      local function rebuildBuffCustomArgs()
        for k in pairs(args) do
          if k:sub(1, 4) == "rbc_" then args[k] = nil end
        end
        local list = Nock.db and Nock.db.profile.reactBuffCustom or {}
        for i = 1, #list do
          local id = tonumber(list[i])
          local idx = i
          args["rbc_" .. i] = {
            type = "description", fontSize = "medium", width = 1.7,
            order = 82 + (i - 1) * 0.1,
            name = ("%s  |cff808080(spell %s)|r"):format(
              (id and optSpellName(id)) or "Unknown spell", tostring(id)),
          }
          args["rbc_rm_" .. i] = {
            type = "execute", name = "Remove", width = 0.5,
            order = 82 + (i - 1) * 0.1 + 0.05,
            disabled = notMode,
            func = function()
              table.remove(Nock.db.profile.reactBuffCustom, idx)
              Nock:SendMessage("NOCK_VISUALS_CHANGED")
              rebuildAllBuffCustom()
              notify()
            end,
          }
        end
      end
      buffCustomRebuilds[#buffCustomRebuilds + 1] = rebuildBuffCustomArgs
      args.addBuffId = {
        type = "input",
        name = "Spell ID to add",
        order = 88,
        width = 1.0,
        disabled = buffDep,
        get = function() return stagedBuffId and tostring(stagedBuffId) or "" end,
        set = function(_, v) stagedBuffId = tonumber((v or ""):match("^%s*(%d+)%s*$")) end,
        validate = function(_, v)
          if v == "" or tostring(v):match("^%s*%d+%s*$") then return true end
          return "Numeric spell ID expected."
        end,
      }
      args.addBuffBtn = {
        type = "execute",
        name = "Add",
        order = 89,
        width = 0.5,
        disabled = function()
          if buffDep() or not stagedBuffId then return true end
          if CN.REACT_BUFFS.IMPORTANT_IDS[stagedBuffId] then return true end
          local list = Nock.db.profile.reactBuffCustom or {}
          for i = 1, #list do
            if tonumber(list[i]) == stagedBuffId then return true end
          end
          return false
        end,
        func = function()
          local p = Nock.db.profile
          p.reactBuffCustom = p.reactBuffCustom or {}
          p.reactBuffCustom[#p.reactBuffCustom + 1] = stagedBuffId
          stagedBuffId = nil
          Nock:SendMessage("NOCK_VISUALS_CHANGED")
          rebuildAllBuffCustom()
          notify()
        end,
      }
    end
    fillBuffArgs(buffArgs, "react")
    -- The Classic side: a child page of the Classic HUD tree (moved there with
    -- the other classic pages at the bottom of this function).
    local classicBuffArgs = {}
    fillBuffArgs(classicBuffArgs, "classic")
    rebuildAllBuffCustom()
    options.args.buffRow = {
      type = "group",
      name = "Buff Row",
      order = 7,
      args = classicBuffArgs,
    }

    -- Curated skin overrides. Reference values are WRITTEN BACK by the reset
    -- (AceDB has no live default fallback for nil'd plain keys — they'd read
    -- nil until /reload; removeDefaults still strips default-equal values at
    -- logout, so untouched keys never enter the SV).
    local SKIN_REFERENCE = {
      reactAutoH = 14, reactMeleeH = 12, reactRangeH = 12, reactManaH = 12, reactCastH = 16,
      reactCornerIconSize = 42, reactCornerIconX = 30, reactCornerIconY = 50,
      reactBarTexture = "", reactFont = "", reactFontSize = 9,
      reactColorAutoFill      = { 1.00, 0.84, 0.00, 1.00 },
      reactColorMeleeReady    = { 0.15, 0.68, 0.38, 1.00 },
      reactColorMeleeAuto     = { 0.55, 0.75, 1.00, 1.00 },
      reactColorManaFill      = { 0.20, 0.55, 1.00, 1.00 },
      reactColorCastFill      = { 0.40, 0.70, 1.00, 1.00 },
      reactColorRangeDeadzone = { 0.68, 0.18, 0.20, 1.00 },
      reactColorRangeSweet    = { 0.85, 0.66, 0.00, 1.00 },
      reactColorRangePerfect  = { 0.17, 0.78, 0.11, 1.00 },
      reactColorRangeClose    = { 0.00, 0.83, 0.75, 1.00 },
      reactColorRangeResync   = { 1.00, 0.58, 0.10, 1.00 },
      reactRangeDividerWidth  = 1,
      reactColorRangeDivider  = { 1.00, 1.00, 1.00, 0.90 },
      reactGcdDividerWidth    = 1,
      reactColorGcdDivider    = { 0.62, 0.35, 0.98, 1.00 },
      reactColorTickSteady    = { 1.00, 0.10, 0.10, 1.00 },
      reactColorTickMulti     = { 1.00, 0.65, 0.10, 1.00 },
      reactColorTickWindup    = { 0.85, 0.85, 0.85, 0.80 },
      reactColorBracket       = { 1.00, 1.00, 1.00, 0.35 },
      reactTickSteadyWidth    = 1,
      reactTickMultiWidth     = 1,
      reactTickWindupWidth    = 1,
      reactBracketWidth       = 1,
    }
    skinArgs.skinHeader = { type = "header", name = "Skin", order = 90 }
    skinArgs.skinNote = {
      type = "description", fontSize = "medium", order = 90.2,
      name = "Defaults are the reference WA look, so an untouched profile is the reference skin. Only these curated knobs are exposed — the bar seams and the grid layout stay fixed.\n",
    }
    skinArgs.reactBarTexture = {
      type = "select",
      name = "Bar texture",
      desc = "Status bar texture for the React fills (Auto Shot, melee, range, mana, cast). 'Reference (built-in)' keeps the flat reference look. Separate from the classic HUD's global Bar texture.",
      order = 90.3,
      dialogControl = lsmWidget(nil, "statusbar"),
      values = lsmSentinelValues("statusbar", "Reference (built-in)"),
      disabled = notReact,
      get = lsmSentinelGet("reactBarTexture", "Reference (built-in)"),
      set = lsmSentinelSet("reactBarTexture", "Reference (built-in)"),
    }
    skinArgs.reactFont = {
      type = "select",
      name = "Font",
      desc = "Font for the React text (bar labels, cast bar, buff row, corner icons — and the cooldown grid, which follows the classic HUD's global Font while this is on 'Reference'). 'Reference (built-in)' keeps the reference look. Separate from the classic HUD's global Font.",
      order = 90.4,
      dialogControl = lsmWidget(nil, "font"),
      values = lsmSentinelValues("font", "Reference (built-in)"),
      disabled = notReact,
      get = lsmSentinelGet("reactFont", "Reference (built-in)"),
      set = lsmSentinelSet("reactFont", "Reference (built-in)"),
    }
    skinArgs.reactFontSize = {
      type = "range",
      name = "Font size",
      desc = "Base size of the React text (reference is 9). Everything shifts together: the small labels stay 2 under this, buff-row and corner-icon text keeps scaling with icon size, and the cooldown grid text shifts by the same amount.",
      min = 6, max = 16, step = 1,
      order = 90.45,
      disabled = notReact,
      get = function() return Nock.db.profile.reactFontSize or 9 end,
      set = function(_, v) visualsSet(_, "reactFontSize", v) end,
    }
    local function skinRange(key, name, order)
      return {
        type = "range", name = name, min = 8, max = 28, step = 1, order = order,
        disabled = notReact,
        get = get,
        set = function(_, v) visualsSet(_, key, v) end,
      }
    end
    skinArgs.reactAutoH  = skinRange("reactAutoH",  "Auto Shot bar height", 91)
    skinArgs.reactMeleeH = skinRange("reactMeleeH", "Melee bar height",     92)
    skinArgs.reactRangeH = skinRange("reactRangeH", "Range bar height",     93)
    skinArgs.reactManaH  = skinRange("reactManaH",  "Mana bar height",      94)
    skinArgs.reactCastH  = skinRange("reactCastH",  "Cast bar height",      95)
    -- Corner-icon geometry wants a wider span than the bar heights above.
    local function cornerRange(key, name, desc, order, minV, maxV)
      return {
        type = "range", name = name, desc = desc,
        min = minV, max = maxV, step = 1, order = order,
        disabled = notReact,
        get = get,
        set = function(_, v) visualsSet(_, key, v) end,
      }
    end
    skinArgs.reactCornerIconSize = cornerRange("reactCornerIconSize",
      "Corner icon size", "Edge length of both corner icons, in pixels.", 95.1, 20, 48)
    skinArgs.reactCornerIconX = cornerRange("reactCornerIconX",
      "Corner icon distance out",
      "Gap between the cluster's side edge and the near edge of each corner icon. Mirrored: the aspect icon moves left, the mark icon right.", 95.2, 0, 120)
    skinArgs.reactCornerIconY = cornerRange("reactCornerIconY",
      "Corner icon distance up",
      "Gap between the cluster's top edge and the bottom of each corner icon. The default clears the buff row.", 95.3, 0, 120)
    local function skinColorOpt(name, desc, order)
      return {
        type = "color", name = name, desc = desc, hasAlpha = true, order = order,
        disabled = notReact,
        get = getColor, set = setColor,
      }
    end
    skinArgs.reactColorAutoFill      = skinColorOpt("Auto Shot fill",     "The converging (or directional) Auto Shot fill.", 96)
    skinArgs.reactColorMeleeReady    = skinColorOpt("Melee: Raptor ready", "Melee fill while Raptor Strike is off cooldown.", 97)
    skinArgs.reactColorMeleeAuto     = skinColorOpt("Melee: auto-only",    "Melee fill while Raptor Strike is on cooldown.", 98)
    skinArgs.reactColorManaFill      = skinColorOpt("Mana fill", nil, 99)
    skinArgs.reactColorCastFill      = skinColorOpt("Cast fill", nil, 100)
    -- Auto Shot bar marks. Each mark gets its own width + colour; the mirrored
    -- halves share one setting (they are one mark drawn twice). Deliberately
    -- NOT the classic clipTick* keys -- React runs its own skin channel, so the
    -- two HUDs can be styled apart.
    skinArgs.autoMarksHeader = { type = "header", name = "Auto Shot bar marks", order = 96.9 }
    skinArgs.reactTickSteadyWidth = cornerRange("reactTickSteadyWidth",
      "Auto: Steady tick width", "Width of the Steady clip tick, in real screen pixels (independent of your UI scale).", 96.91, 1, 8)
    skinArgs.reactColorTickSteady = skinColorOpt("Auto: Steady tick",
      "The tick marking where a Steady Shot cast would clip the next Auto Shot.", 96.92)
    skinArgs.reactTickMultiWidth = cornerRange("reactTickMultiWidth",
      "Auto: Multi tick width", "Width of the Multi clip tick, in real screen pixels (independent of your UI scale).", 96.93, 1, 8)
    skinArgs.reactColorTickMulti = skinColorOpt("Auto: Multi tick",
      "The tick marking where a Multi-Shot cast would clip the next Auto Shot.", 96.94)
    skinArgs.reactTickWindupWidth = cornerRange("reactTickWindupWidth",
      "Auto: wind-up mark width", "Width of the wind-up commit landmark, in real screen pixels (independent of your UI scale).", 96.95, 1, 8)
    skinArgs.reactColorTickWindup = skinColorOpt("Auto: wind-up mark",
      "The neutral landmark where the next Auto Shot commits (wind-up start).", 96.96)
    skinArgs.reactBracketWidth = cornerRange("reactBracketWidth",
      "Auto: eWS bracket width", "Width of the eWS bracket marks, in real screen pixels. Shown only while eWS bracket marks are on, under Bars.", 96.97, 1, 8)
    skinArgs.reactColorBracket = skinColorOpt("Auto: eWS brackets",
      "The eWS rotation-bracket bounds on the Auto Shot bar (off by default, under Bars).", 96.98)
    skinArgs.reactColorRangeDeadzone = skinColorOpt("Range: deadzone",  "In melee (can't shoot).", 101)
    skinArgs.reactColorRangeSweet    = skinColorOpt("Range: sweet",     "Inside the weave ring.", 102)
    skinArgs.reactColorRangePerfect  = skinColorOpt("Range: perfect",   "At the melee edge (best weave spot).", 103)
    skinArgs.reactColorRangeClose    = skinColorOpt("Range: close",     "Closing on the weave ring; also the finding drain fill.", 104)
    skinArgs.reactColorRangeResync   = skinColorOpt("Range: RESYNC",    "Estimate degraded (parked at the tick).", 105)
    -- The range bar's centre divider (the melee-boundary tick). cornerRange
    -- is just the min/max-parameterised skin slider — the 8-28px skinRange
    -- span is absurd for a 1px tick.
    skinArgs.reactRangeDividerWidth = cornerRange("reactRangeDividerWidth",
      "Range: divider width",
      "Width of the centre divider on the range bar (the melee boundary), in real screen pixels.", 105.5, 1, 8)
    skinArgs.reactColorRangeDivider = skinColorOpt("Range: divider", "The centre divider on the range bar (the melee boundary).", 106)
    -- GCD divider: same narrow span as the range divider, for the same reason.
    -- Both rows stay visible while the feature is off — the skin tab is where
    -- you set a look up before switching it on.
    skinArgs.reactGcdDividerWidth = cornerRange("reactGcdDividerWidth",
      "Auto: GCD divider width",
      "Width of the moving GCD divider on the Auto Shot bar, in real screen pixels (independent of your UI scale).", 106.5, 1, 8)
    skinArgs.reactColorGcdDivider = skinColorOpt("Auto: GCD divider", "The moving GCD divider on the Auto Shot bar (off by default — turn it on under Bars).", 107)
    skinArgs.resetSkin = {
      type = "execute",
      name = "Reset skin to reference look",
      order = 110,
      width = 1.2,
      confirm = true,
      confirmText = "Reset all React skin overrides (texture, font, heights and colors) to the reference look?",
      disabled = notReact,
      func = function()
        local prof = Nock.db.profile
        for k, v in pairs(SKIN_REFERENCE) do
          if type(v) == "table" then
            prof[k] = { v[1], v[2], v[3], v[4] }
          else
            prof[k] = v
          end
        end
        Nock:SendMessage("NOCK_VISUALS_CHANGED")
        notify()
      end,
    }

    options.args.react = {
      type  = "group",
      name  = function()
        local active = (Nock.db.profile.hudMode or "classic") == "react"
        return active and "React HUD |cff9dc46e(active)|r" or "React HUD"
      end,
      order = 1.7,
      childGroups = "tree",
      args  = {
        intro   = landingArgs.intro,
        hudMode = landingArgs.hudMode,
        tabSize  = { type = "group", name = "Size & Elements", order = 10, args = sizeArgs },
        tabBars  = { type = "group", name = "Bars",            order = 20, args = barsArgs },
        tabRange = { type = "group", name = "Range Bar",       order = 30, args = rangeArgs },
        tabGrid  = { type = "group", name = "Cooldown Grid",   order = 40, args = gridArgs },
        tabBuff  = { type = "group", name = "Buff Row",        order = 50, args = buffArgs },
        tabSkin  = { type = "group", name = "Skin",            order = 60, args = skinArgs },
      },
    }
  end

  -- ---------------------------------------------------------------------------
  -- Tidy the heaviest tabs: gather each header-delimited span into a titled
  -- inline group, so the tab reads as sections instead of one long scroll.
  -- Entries keep their keys and relative orders, and every get/set handler
  -- keys off info[#info], so the extra nesting level is transparent to them.
  -- asTab: leave the group non-inline so the parent's childGroups="tab"
  -- renders it as a subtab instead of an in-flow section box.
  local function regroup(tabKey, groupKey, groupName, order, keys, asTab)
    local tab = options.args[tabKey]
    if not (tab and tab.args) then return end
    local g = { type = "group", name = groupName, inline = not asTab or nil, order = order, args = {} }
    for _, k in ipairs(keys) do
      local entry = tab.args[k]
      if entry then
        g.args[k] = entry
        tab.args[k] = nil
      end
    end
    tab.args[groupKey] = g
  end
  local function dropArgs(tabKey, ...)
    local tab = options.args[tabKey]
    if not (tab and tab.args) then return end
    for i = 1, select("#", ...) do tab.args[select(i, ...)] = nil end
  end

  -- General: the action buttons live on the page (Lock/Unlock pair up top with
  -- the state line on its own row under them, wizard + reset below, then the
  -- scale slider); each concern group is a child node in the LEFT sidebar
  -- (childGroups="tree", the AceConfigDialog default — set explicitly so
  -- nobody "fixes" it to a tab strip).
  options.args.general.childGroups = "tree"
  options.args.general.args.lockAll.order   = 2
  options.args.general.args.unlockAll.order = 2.1
  options.args.general.args.lockState.order = 2.5
  options.args.general.args.runWizard.order = 3
  options.args.general.args.resetPos.order  = 4
  options.args.general.args.scale.order     = 5
  regroup("general", "grpLook", "HUD look", 10,
    { "reactNote", "hudMode" }, true)
  regroup("general", "grpVisibility", "Visibility", 11,
    { "opacityNote", "opacity", "opacityOoc", "hideOoc" }, true)
  -- Background is gathered here but MOVED to the Classic branch below — the
  -- backdrop box is classic-only (HUD:ApplyBackground paints nothing in react
  -- mode; React's styling is its Skin subtab), so it lives with that look.
  regroup("general", "grpBackground", "Background", 12,
    { "backgroundNote", "backgroundFreeNote", "backgroundEnabled", "backgroundColor",
      "backgroundOpacity", "hudBorder", "hudBorderSize", "hudBorderColor", "hudBorderOpacity" }, true)
  regroup("general", "grpCastBar", "Cast bar", 13,
    { "showAutoShotCast", "castBarNonCombatCasts", "hideBlizzardCastBar" }, true)
  regroup("general", "grpMedia", "Media", 14,
    { "barTexture", "fontFace", "iconBorder", "iconBorderSize" }, true)
  dropArgs("general", "reactHeader", "bgHeader", "mediaHeader", "setupCheckHeader")
  -- Setup Check becomes the last subtab: the static intro plus every injected
  -- setup_* inline group (the injection ran earlier in this function).
  do
    local gArgs = options.args.general.args
    local tab = { type = "group", name = "Setup Check", order = 15, args = {} }
    local moved = { "setupCheckIntro" }
    for k in pairs(gArgs) do
      if type(k) == "string" and k:sub(1, 6) == "setup_" then moved[#moved + 1] = k end
    end
    for _, k in ipairs(moved) do
      tab.args[k] = gArgs[k]
      gArgs[k] = nil
    end
    gArgs.grpSetup = tab
  end

  -- Layout: placement, the master visibility list, feature panels, scaling.
  regroup("layout", "grpPlacement", "Alignment & placement", 1,
    { "lockHud", "unlockHud", "hudEnabled", "rowAlign", "freeLayout", "lockNote",
      "resetElementPos" })
  regroup("layout", "grpElements", "HUD elements", 10,
    { "visibilityIntro", "reactVisibilityNote", "hideAllElements", "showAllElements",
      "showCooldowns", "showBuffRow", "showInfoRow", "showManaBar", "showRangeFinder", "showTotemTracker",
      "showRotation", "showWarnings", "showHelpers", "showCastBar", "showPetStatus",
      "showAutoShotBar", "showMeleeBar", "showGcdBar" })
  regroup("layout", "grpPanels", "Feature panels", 20,
    { "misdirectPanelToggle", "mdCastPanelToggle", "buffTrackerPanelToggle",
      "debuffTrackerPanelToggle", "shoppingPanelToggle", "repairPanelToggle" })
  regroup("layout", "grpScaling", "Per-element scaling", 30,
    { "scalingIntro", "rotationScale", "shotBarsScale", "swingScale",
      "rangeFinderScale", "infoRowScale", "buffRowScale", "totemScale" })
  dropArgs("layout", "alignHeader", "rowsHeader", "panelsHeader", "scalingHeader")

  -- Rotation: mode picks stay up top; the Shot Bars pile and each tunable
  -- cluster get their own section.
  regroup("rotation", "grpShotBars", "Shot timing bars", 3,
    { "shotBarsIntro", "shotBarsLegend", "shotBarsLegacy", "shotBarsShowHelper", "shotBarsWindow",
      "shotBarsRotationText", "shotBarsHeight", "shotBarsMeleeHeight", "shotBarsReverse", "shotBarsShowMulti",
      "shotBarsShowArcane", "shotBarsShowRaptor", "shotBarsColorSteady", "shotBarsColorMulti",
      "shotBarsColorArcane", "shotBarsColorRaptor", "shotBarsColorWeaveAuto",
      "shotBarsColorDanger", "shotBarsColorQueue", "shotBarsColorQueueLive",
      "shotBarsColorSpark" })
  -- Experimental: one sidebar sub-page per experiment (the countdown dial
  -- rides with the medallion — same experiment, two sections). The landing
  -- page keeps only the opt-in disclaimer.
  options.args.experimental.childGroups = "tree"
  regroup("experimental", "grpMedallion", "V3 Medallion", 10,
    { "v3Intro", "medallionEnabled", "medallionSize", "ringHeader", "ringIntro",
      "medallionRing", "medallionRingColorPress", "medallionRingColorHold",
      "medallionRingTrackColor" }, true)
  regroup("experimental", "grpSapper", "Sapper Column", 20,
    { "sapperIntro", "mdSapperEnabled", "mdSapperAnnounce", "mdSapperAnnounceScope" }, true)
  regroup("experimental", "grpZoom", "Zoomed Weave Bar", 30,
    { "zoomIntro", "rangeZoomedGlide", "rangeZoomLevel" }, true)
  regroup("experimental", "grpRelease", "Retry-Timer", 40,
    { "releaseIntro", "releaseBarEnabled", "releaseBarAlways", "releaseBarHeight",
      "releaseBarLabels", "releaseBarNotches" }, true)
  dropArgs("experimental", "v3Header", "sapperHeader", "zoomHeader", "releaseHeader")

  -- Warnings: the settings layer is the first sidebar child (order 1; the
  -- category nodes start at 10), keeping the landing page to just the master
  -- toggle + intro.
  regroup("warnings", "settings", "Appearance & Preview", 1,
    { "appearanceHeader", "warningIconSize", "warningBorderSize", "warningLabelOffset",
      "warningLabelSize", "warningLabelFont", "warningLabelStyle", "warningLabelUpper",
      "previewHeader", "previewIntro", "previewButton", "noReleasePreview" }, true)

  regroup("rotation", "grpEngine", "Weave engine (same settings as React → Bars)", 4,
    { "rotQuiverEquipped", "rotRaptorWeaveHeadroom", "rotWeaveProxMin", "rotWeaveProxMax" })
  regroup("rotation", "grpClipTicks", "Clip-zone ticks", 5,
    { "clipTicksIntro", "showWindupMark" })
  regroup("rotation", "grpNextHighlight", "Next-action highlight", 6,
    { "nextHighlightIntro", "rotNextEffect", "rotNextColor" })
  dropArgs("rotation", "shotBarsHeader", "shotBarsFooter", "clipTicksHeader", "nextHighlightHeader")

  -- Per-bar track styling (see barStyleArgs). Injected here, AFTER the regroup
  -- calls above, because the Shot Bars block belongs INSIDE grpShotBars -- and
  -- regroup only moves the keys it is handed by name, so anything added earlier
  -- would strand itself at the top of the page. The cast bar's block is added
  -- inline with the rest of its args in the classic branch below.
  local function injectBarStyle(group, prefix, startOrder, label)
    if not (group and group.args) then return end
    for k, v in pairs(barStyleArgs(prefix, startOrder, label)) do
      group.args[k] = v
    end
  end
  injectBarStyle(options.args.swingBars,   "autoShotTrack", 41, "Auto Shot bar background")
  injectBarStyle(options.args.swingBars,   "meleeTrack",    42, "Melee bar background")
  injectBarStyle(options.args.swingBars,   "gcdTrack",      43, "GCD bar background")
  injectBarStyle(options.args.manaBar,     "manaTrack",     50, "Bar background")
  injectBarStyle(options.args.rangeFinder, "rangeTrack",    60, "Bar background")
  injectBarStyle(options.args.rotation and options.args.rotation.args
                   and options.args.rotation.args.grpShotBars,
                 "shotBarsTrack", 2.8, "Timeline background")
  -- "Rename rotation labels" is cosmetic and twelve text inputs tall, and at its
  -- original 2.58 it sat ABOVE the four sections above (orders 3-6) — so the page
  -- opened on a wall of rename boxes and pushed the bar colours and clip settings
  -- out of view. Park it at the bottom; the functional sections come first.
  if options.args.rotation.args.rotationLabelsGroup then
    options.args.rotation.args.rotationLabelsGroup.order = 7
  end

  -- ---------------------------------------------------------------------------
  -- Family tree: nest the flat feature tabs under a handful of family nodes so
  -- the sidebar reads as five areas instead of nineteen entries. Group KEYS are
  -- unchanged — only their nesting moves — and every dynamic injection above
  -- (warnings/helpers/setup-check catalogs, cooldown grid, react) has already
  -- run against the flat paths and keeps mutating the same tables by reference.
  -- MUST stay the last step before `return options`; anything added to
  -- options.args after this lands at the root.
  -- Classic branch: gather the classic-look tabs under one node first, so the
  -- FAMILIES loop below moves the whole branch as a single child. React's
  -- group already exists (built in its own block above). Branch names are
  -- functions so the sidebar badges whichever look is live.
  do
    local classic = {
      type = "group",
      name = function()
        local active = (Nock.db.profile.hudMode or "classic") ~= "react"
        return active and "Classic HUD |cff9dc46e(active)|r" or "Classic HUD"
      end,
      order = 1,
      childGroups = "tree",
      args = {},
    }
    for i, key in ipairs({ "layout", "rotation", "swingBars", "manaBar",
                           "rangeFinder", "cooldownGrid", "buffRow" }) do
      local child = options.args[key]
      if child then
        child.order = i
        classic.args[key] = child
        options.args[key] = nil
      end
    end
    -- Behavior (mirrored with General → Cast bar) + classic-only styling.
    -- React's cast bar styling lives in its Skin, so nothing here mirrors.
    local castBarArgs = castBarSharedArgs("(same setting as General → Cast bar)")
    castBarArgs.stylingHeader = {
      type = "header", name = "Styling (classic look only)", order = 50,
    }
    castBarArgs.castBarShowIcon = {
      type = "toggle",
      name = "Spell icon",
      desc = "Show the spell icon beside the cast bar. Off stretches the bar to full width.",
      order = 51,
      get = function() return Nock.db.profile.castBarShowIcon ~= false end,
      set = function(_, v) visualsSet(_, "castBarShowIcon", v) end,
    }
    castBarArgs.castBarHeight = {
      type = "range",
      name = "Bar height",
      desc = "Height of the cast bar in pixels (before scaling). The icon and panel resize with it.",
      min = 12, max = 40, step = 1,
      order = 52,
      get = function() return Nock.db.profile.castBarHeight or 22 end,
      set = function(_, v) visualsSet(_, "castBarHeight", v) end,
    }
    castBarArgs.castBarTexture = {
      type = "select",
      name = "Bar texture",
      desc = "Status bar texture for the cast bar. 'Inherit (global)' uses the global Bar texture.",
      order = 53,
      dialogControl = lsmWidget(nil, "statusbar"),
      values = lsmSentinelValues("statusbar", "Inherit (global)"),
      get = lsmSentinelGet("castBarTexture", "Inherit (global)"),
      set = lsmSentinelSet("castBarTexture", "Inherit (global)"),
    }
    castBarArgs.castBarColor = {
      type = "color",
      name = "Fill color",
      desc = "Fill color of the cast bar.",
      hasAlpha = true,
      order = 54,
      get = getColor,
      set = setColor,
    }
    castBarArgs.castBarPadding = {
      type = "range",
      name = "Padding",
      desc = "Inset between the panel edge and the icon/bar, in pixels. The panel grows with it.",
      min = 0, max = 16, step = 1,
      order = 55,
      get = function() return Nock.db.profile.castBarPadding or 4 end,
      set = function(_, v) visualsSet(_, "castBarPadding", v) end,
    }
    -- Per-panel Background block (same shape as the floating panels'). Note:
    -- the panel is welded to the HUD box with a 1px border overlap — a thick
    -- LSM border or a different border color visibly breaks that seam.
    for k, v in pairs(panelStyleArgs("castBar", 56)) do
      castBarArgs[k] = v
    end
    castBarArgs.castBarBorder.desc = (castBarArgs.castBarBorder.desc or "")
      .. " Note: the cast bar sits flush against the HUD box; a thick border breaks that seamless join."
    -- ...and the BAR's own track, which is a different frame from the panel
    -- above: castBar* skins the box around the icon + bar, castBarTrack* skins
    -- the strip the fill runs along.
    for k, v in pairs(barStyleArgs("castBarTrack", 60, "Bar background")) do
      castBarArgs[k] = v
    end
    classic.args.castBar = {
      type = "group",
      name = "Cast Bar",
      order = 7,
      args = castBarArgs,
    }
    -- Background node (moved from General; see the regroup note above).
    local bg = options.args.general.args.grpBackground
    if bg then
      options.args.general.args.grpBackground = nil
      bg.order = 8
      bg.args.backgroundReactNote = {
        type = "description",
        name = "Classic look only — the React look draws no background box; its styling lives under React HUD → Skin.",
        order = 30.43,
        fontSize = "medium",
      }
      classic.args.background = bg
    end
    -- Landing page (parity with the React branch): a blank page on the branch
    -- node itself reads as broken.
    classic.args.intro = {
      type = "description",
      fontSize = "medium",
      order = 0,
      name = "The configurable classic look: a stack of independent rows. Each page below owns one piece — row layout and element visibility, the Shot Bars timeline, swing/mana/range bars, the cooldown grid and the cast bar.\n",
    }
    classic.args.hudMode = hudModeSelect(0.5, "(same setting as General → HUD look)")
    options.args.classic = classic
  end

  local FAMILIES = {
    { key = "hud", name = "HUD & Bars", order = 2,
      desc = "Everything drawn as part of the HUD cluster, split by look: the Classic row stack and the fixed-skin React replica. The active look is marked in the list.",
      children = { "classic", "react" } },
    { key = "alerts", name = "Alerts", order = 3,
      desc = "Things that shout at you: full-screen warnings and the consumable/buff helper row.",
      children = { "warnings", "helpers" } },
    { key = "trackers", name = "Trackers", order = 4,
      desc = "Standalone tracking panels: buffs, target debuffs, totem range and Misdirection.",
      children = { "buffTracker", "debuffTracker", "totemTracker", "misdirect" } },
    { key = "utilities", name = "Utilities", order = 5,
      desc = "Quality-of-life helpers: shopping list, mailbox, the weave keybind, the boss garment autopilot and the Steam Tonk guard.",
      children = { "shopping", "mailbox", "weaveBind", "garment", "tonk", "practice" } },
  }
  for _, fam in ipairs(FAMILIES) do
    local group = {
      type = "group",
      name = fam.name,
      order = fam.order,
      childGroups = "tree",
      args = {
        intro = { type = "description", name = fam.desc, order = 0, fontSize = "medium" },
      },
    }
    for i, key in ipairs(fam.children) do
      local child = options.args[key]
      if child then
        child.order = i
        group.args[key] = child
        options.args[key] = nil
      end
    end
    options.args[fam.key] = group
  end
  options.args.hud.args.hudMode = hudModeSelect(0.5, "(same setting as General → HUD look)")

  return options
end

function Nock:RegisterOptions()
  local options = buildOptionsTable()
  options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
  options.args.profiles.order = 99   -- pinned to the very bottom

  LibStub("AceConfig-3.0"):RegisterOptionsTable("Nock", options)
  self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Nock", "Nock")
end

function Nock:OpenConfig()
  LibStub("AceConfigDialog-3.0"):Open("Nock")
end
