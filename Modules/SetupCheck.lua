-- Modules/SetupCheck.lua
-- Pre-flight checks for a clean hunter weaving setup. Prints a one-line hint
-- at PLAYER_ENTERING_WORLD if anything is misconfigured; the settings UI
-- (General → Setup Check) shows the full breakdown with auto-fix buttons.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local SetupCheck = Nock:NewModule("SetupCheck", "AceEvent-3.0", "AceConsole-3.0")

local SPELL_QUEUE_RECOMMENDED_MAX = 200  -- ms, weaving stays clean at/below this
local SPELL_QUEUE_FIX_VALUE       = 100  -- ms, value the "Fix" button writes

local function isAddOnLoaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
  if IsAddOnLoaded then return IsAddOnLoaded(name) end
  return false
end

local function getSpellQueueWindow()
  local raw = GetCVar and GetCVar("SpellQueueWindow")
  return tonumber(raw or "400") or 400
end

-- `applies` (optional): a check that is skipped everywhere -- the wizard,
-- the settings, the login hint -- unless it returns true. For a row about
-- an addon most users never had.
SetupCheck.Checks = {
  {
    key  = "groundedWeave",
    -- wizardHidden: the wizard offers the import as a card on its weave-macro
    -- page instead (Modules/Onboarding.lua); the row stays in the settings.
    wizardHidden = true,
    name = "Weave key held by Grounded",
    desc = "The Grounded addon holds a hold-to-weave bind (its press casts Raptor Strike / starts the attack). Nock's Weave Bind does the same natively, and practice mode, the weave coach and the weave log only see Nock's key. Import moves the key and both macros into Nock and takes the bind out of Grounded -- no reload. Undo lives in Utilities -> Weave Bind.",
    applies = function()
      local wb = Nock:GetModule("WeaveBind", true)
      return (wb and wb.GroundedWeaveBind and wb:GroundedWeaveBind()) ~= nil
    end,
    check = function()
      local wb = Nock:GetModule("WeaveBind", true)
      local g = wb and wb.GroundedWeaveBind and wb:GroundedWeaveBind()
      return g == nil, g and g.key or nil
    end,
    failHint = "Grounded holds your weave key",
    fixLabel = "Import into Nock",
    fix = function()
      local wb = Nock:GetModule("WeaveBind", true)
      if wb and wb.ImportFromGrounded then wb:ImportFromGrounded() end
    end,
    formatDetail = function(v) return v and ("Grounded bind: %s"):format(v) or "Imported into Nock" end,
  },
  {
    key  = "fojjiCore",
    -- wizardHidden: informational only (a suggested library, not something Nock
    -- can fix), so the onboarding wizard skips it and keeps its checks page to
    -- the three one-click fixes. Still listed in /nock -> General -> Setup Check.
    wizardHidden = true,
    name = "FojjiCore addon installed",
    desc = "Optional but recommended. FojjiCore is a sounds + icons + textures library used by many hunter WeakAuras (including the inspiration WA referenced in Nock's design). Install from CurseForge if your weak auras lack alert sounds.",
    check = function()
      return isAddOnLoaded("FojjiCore"), nil
    end,
    failHint = "FojjiCore not loaded",
  },
  {
    key  = "autoRangedCombat",
    name = "Auto Attack / Auto Shot toggle",
    desc = "Interface → Combat → 'Auto Attack/Auto Shot' should be OFF for clean weaving. With it on, the client auto-switches between auto-attack and auto-shot when your range to target changes, which can disrupt deliberate Auto Shot timing.",
    check = function()
      local v = GetCVar and GetCVar("autoRangedCombat") or "1"
      return v == "0", v
    end,
    failHint = "Auto Attack/Auto Shot toggle is ON",
    fixLabel = "Turn off",
    fix = function()
      if SetCVar then SetCVar("autoRangedCombat", "0") end
    end,
    formatDetail = function(v) return ("Current: %s"):format(v == "0" and "Off" or "On") end,
  },
  {
    key  = "spellQueueWindow",
    name = "Spell queue window",
    desc = ("Hidden CVar — controls how far ahead the client queues spell input. Higher values increase the chance of accidentally clipping Auto Shot during weaving. The hunter community typically recommends %d-%d ms."):format(SPELL_QUEUE_FIX_VALUE, SPELL_QUEUE_RECOMMENDED_MAX),
    check = function()
      local v = getSpellQueueWindow()
      return v <= SPELL_QUEUE_RECOMMENDED_MAX, v
    end,
    failHint = "SpellQueueWindow too high",
    -- Multi-button row: pick from common values. The currently-active value's
    -- button is disabled so the user knows where they stand at a glance.
    actions = {
      { label = "100 ms",       value = 100 },
      { label = "200 ms",       value = 200 },
      { label = "400 ms (Blizzard default)", value = 400 },
    },
    applyAction = function(action)
      if SetCVar then SetCVar("SpellQueueWindow", tostring(action.value)) end
    end,
    actionIsCurrent = function(action)
      return getSpellQueueWindow() == action.value
    end,
    formatDetail = function(v) return ("Current: %d ms (recommended ≤ %d)"):format(v, SPELL_QUEUE_RECOMMENDED_MAX) end,
  },
  {
    key  = "castOnKeyDown",
    name = "Cast on key down",
    desc = "With 'cast on key down' enabled (ActionButtonUseKeyDown 1, the client default) actions fire on key PRESS instead of release, shaving a little input latency. (The Weave Bind feature no longer depends on this — its button overrides the CVar per click edge — so this is purely a latency recommendation.)",
    check = function()
      local v = GetCVar and GetCVar("ActionButtonUseKeyDown") or "1"
      return v == "1", v
    end,
    failHint = "Cast on key down is OFF",
    fixLabel = "Enable",
    fix = function()
      if SetCVar then SetCVar("ActionButtonUseKeyDown", "1") end
    end,
    formatDetail = function(v) return ("Current: %s"):format(v == "1" and "On (fires on press)" or "Off (fires on release)") end,
  },
}

function SetupCheck:OnEnable()
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
end

function SetupCheck:OnEnteringWorld()
  -- Guard so /reloads and zone changes don't re-print the hint.
  if self._loginHintShown then return end
  self._loginHintShown = true

  -- First login: the onboarding wizard is about to open and its first page
  -- shows these same checks with fix buttons. Printing the hint too would be
  -- telling the user twice.
  if Nock.db and Nock.db.global and not Nock.db.global.onboarding then return end

  local failedHints = {}
  for _, c in ipairs(self.Checks) do
    if not (c.applies and not c.applies()) then
      local ok = c.check()
      if not ok then failedHints[#failedHints + 1] = c.failHint or c.name end
    end
  end
  if #failedHints == 0 then return end

  self:Print(
    ("Setup hint: %s. Open |cff20a0ff/nock|r → General → Setup Check for details."):format(
      table.concat(failedHints, ", ")
    )
  )
end
