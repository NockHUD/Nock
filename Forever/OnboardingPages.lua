-- Forever/OnboardingPages.lua
-- The WoW Forever page script for the setup wizard (Modules/Onboarding.lua runs it).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Onboarding = Nock.Onboarding

local function profile()
  return Nock.db and Nock.db.profile
end

local function autoShotIcon()
  return Onboarding.SpellIcon(Nock.Spells and Nock.Spells.AUTO_SHOT)
end

-- The HUD master switch (profile.hudEnabled, read by UI/HUD.lua).
local function hudOn(p)
  return p.hudEnabled ~= false
end

-- Quality-of-life rows write through Modules/QoL.lua so the CVar / the error
-- event flips the moment the box is ticked.
local function qolRow(key, setter, label, desc)
  return {
    id = key, label = label, desc = desc,
    isOn = function(p) return p[key] == true end,
    setOn = function(p, on)
      local m = Nock:GetModule("QoL", true)
      if m and m[setter] then m[setter](on) else p[key] = on and true or false end
    end,
  }
end

-- The warnings page lists Forever/Warnings.lua's catalog, rebuilt on every
-- open so a new warning shows up here without touching this file.
local function buildWarningRows(page)
  local rows = {
    { key = "showWarnings", master = true, label = "Warnings", desc = "Master switch for every alert square." },
  }
  local w = Nock:GetModule("Warnings", true)
  for _, e in ipairs(w and w.Catalog or {}) do
    rows[#rows + 1] = { key = e.enabledKey, label = e.name, desc = e.description,
      dependsOn = "showWarnings", sub = true, fromCatalog = true }
  end
  rows[#rows + 1] = { key = "aggroEnabled", label = "Aggro flash",
    desc = "A red starburst at screen centre while a mob is on you, with a cue the moment it happens." }
  rows[#rows + 1] = { slider = true, key = "warningIconSize", label = "Warning size", min = 24, max = 80, step = 2, default = 44 }
  rows[#rows + 1] = { slider = true, key = "warningLabelSize", label = "Warning text size", min = 8, max = 24, step = 1, default = 12 }
  rows[#rows + 1] = { slider = true, key = "aggroSize", label = "Aggro flash size", min = 100, max = 600, step = 10, default = 300 }
  page.options = rows
end

Onboarding.Pages = {
  {
    key     = "start",
    kind    = "cards",
    eyebrow = "First-time setup",
    title   = "Where do you want to start?",
    blurb   = "From scratch walks you through every part. A bundled profile applies someone's whole layout first; the steps then show you where everything sits.",
    visible = function() return Onboarding:HasStartProfiles() end,
    options = {},   -- filled by RefreshStartCards on every Open
  },
  {
    key     = "welcome",
    kind    = "intro",
    eyebrow = "First-time setup",
    title   = "Welcome to Nock",
    blurb   = "A hunter HUD: swing timers, a range ladder, cooldowns and the warnings that matter.",
    body    = "Each step puts one part of Nock on screen. The part that step is about is unlocked: drag it where you like, or use its nudge pad, before moving on. Everything locks again when you finish.\n\nYou can skip at any point and keep what you've chosen, and run this again from the settings window (General).",
  },
  {
    key     = "showHud",
    kind    = "cards",
    reveals = { "hud" },
    eyebrow = "You can change this anytime",
    title   = "Do you want the HUD?",
    blurb   = "This shows or hides your real HUD live - watch it behind this window.",
    options = {
      {
        value = "hud", label = "Nock HUD", recommended = true,
        desc  = "The cluster: swing bars, Range Finder, mana, cast bar and the cooldown grid.",
        icon  = autoShotIcon,
        isSelected = function(p) return p.hudEnabled ~= false end,
        apply      = function(p) p.hudEnabled = true end,
      },
      {
        value = "none", label = "No HUD",
        desc  = "No bars on screen. Warnings, range cues, the aspect ring and the weave key still work.",
        icon  = function() return Onboarding.SpellIcon(Nock.Spells and Nock.Spells.FEIGN_DEATH) end,
        isSelected = function(p) return p.hudEnabled == false end,
        apply      = function(p) p.hudEnabled = false end,
      },
    },
  },
  {
    key     = "hud",
    kind    = "toggles",
    reveals = { "hud" },
    eyebrow = "Drag the HUD where you want it",
    title   = "Your HUD",
    blurb   = "Pick the bars you want stacked in the cluster.",
    -- The cluster's own pages (this one, the ladder, the corners): nothing to
    -- dress with the HUD off.
    visible = hudOn,
    options = {
      { key = "reactShowAutoBar",  label = "Auto Shot bar", desc = "Counts down to your next Auto Shot." },
      { key = "reactShowMeleeBar", label = "Melee swing bar", desc = "Your melee swing, for weaving." },
      { key = "reactShowRangeBar", label = "Range Finder", desc = "Where your target stands, from melee to out of range." },
      { key = "reactShowManaBar",  label = "Mana bar", desc = "Mana with the percent readout." },
      { key = "reactShowCastBar",  label = "Cast bar", desc = "Your casts, glued under the cluster." },
      { key = "reactShowGrid",     label = "Cooldown grid", desc = "Your cooldowns in rows under the cluster." },
    },
  },
  {
    key     = "range",
    kind    = "cards",
    reveals = { "hud" },
    eyebrow = "You can change this anytime",
    title   = "Range Finder",
    blurb   = "How much detail the range ladder shows.",
    visible = hudOn,
    options = {
      {
        value = "compact", label = "Compact", recommended = true,
        desc  = "Five segments; past 20 yd the far block names the real bracket.",
        icon  = autoShotIcon,
        isSelected = function(p) return (p.reactRangeStyle or "compact") == "compact" end,
        apply      = function(p) p.reactRangeStyle = "compact" end,
      },
      {
        value = "detailed", label = "Detailed",
        desc  = "Every distance bracket its own segment.",
        icon  = autoShotIcon,
        isSelected = function(p) return p.reactRangeStyle == "detailed" end,
        apply      = function(p) p.reactRangeStyle = "detailed" end,
      },
    },
    toggles = {
      { key = "reactRangeLabels", label = "Label every segment", desc = "Each bracket shows its yards; off, only the lit one." },
    },
  },
  {
    key     = "weave",
    kind    = "cards",
    reveals = { "hud" },
    eyebrow = "You can change this anytime",
    title   = "How do you play?",
    blurb   = "Weaving runs in for a Raptor Strike between shots. Nock can call every step of it.",
    options = {
      {
        value = "turret", label = "I stand and shoot",
        desc  = "No weave cues and no weave strip; the melee bar keeps its plain swing.",
        icon  = autoShotIcon,
        isSelected = function(p) return p.weaveHelperEnabled == false end,
        apply      = function(p) p.weaveHelperEnabled = false end,
      },
      {
        value = "weave", label = "I weave", tag = "Advanced",
        desc  = "GO IN, WAIT, STRIKE, BACK OUT and RELEASE on the melee bar, and a weave strip under it that crosses the dead zone at your own pace.",
        icon  = function() return Onboarding.SpellIcon(Nock.Spells and Nock.Spells.RAPTOR_STRIKE) end,
        isSelected = function(p) return p.weaveHelperEnabled ~= false end,
        apply      = function(p)
          p.weaveHelperEnabled, p.reactShowWeaveStrip, p.reactMeleeStageCue, p.reactShowMeleeBar = true, true, true, true
        end,
      },
    },
    toggles = {
      { key = "cameraFlipEnabled", label = "Camera flip on weaves", tag = "Advanced",
        desc = "Turn away on the melee hit and back for the shot, camera fixed on the target. Raids only by default; set the camera up once with /nock camera setup." },
    },
  },
  {
    key     = "weaveKey",
    kind    = "cards",
    reveals = { "hud" },
    eyebrow = "Optional",
    title   = "Weave key",
    blurb   = "One held key for the whole weave, or your own macros.",
    -- Weavers only, like the TBC macro page: a turret never presses it.
    visible = function(p) return p.weaveHelperEnabled ~= false end,
    message = "NOCK_WEAVEKEY_CHANGED",
    options = {
      {
        value = "macros", label = "Macros",
        desc  = "Your own Raptor Strike and Auto Shot macros with the camera lines; W does the running.",
        icon  = autoShotIcon,
        isSelected = function(p) return p.weaveKeyEnabled ~= true end,
        apply      = function(p) p.weaveKeyEnabled = false end,
      },
      {
        value = "key", label = "Weave key", tag = "Advanced",
        desc  = "Hold to run in, let go to strike, hold to run out, let go to shoot. Wants the camera flip.",
        icon  = function() return Onboarding.SpellIcon(Nock.Spells and Nock.Spells.RAPTOR_STRIKE) end,
        isSelected = function(p) return p.weaveKeyEnabled == true and not ((p.weaveKeyMacroDown or "x") == "" and (p.weaveKeyMacroUp or "x") == "") end,
        -- Turns the mode on; a body the user wrote stays exactly as typed, an
        -- unset one stays unset (= stock). Only two blank bodies from the
        -- Empty card are put back to stock, or the key would run nothing.
        apply      = function(p)
          p.weaveKeyEnabled = true
          if p.weaveKeyMacroDown == "" and p.weaveKeyMacroUp == "" then p.weaveKeyMacroDown, p.weaveKeyMacroUp = nil, nil end
        end,
      },
      {
        value = "empty", label = "Empty",
        desc  = "The key with both bodies blank, for lines of your own (Utilities, Weave key).",
        icon  = autoShotIcon,
        isSelected = function(p) return p.weaveKeyEnabled == true and (p.weaveKeyMacroDown or "x") == "" and (p.weaveKeyMacroUp or "x") == "" end,
        apply      = function(p) p.weaveKeyEnabled = true; p.weaveKeyMacroDown, p.weaveKeyMacroUp = "", "" end,
      },
    },
  },
  {
    key     = "weaveKeyBind",
    kind    = "intro",
    eyebrow = "Optional",
    title   = "Weave key",
    blurb   = "The key to hold.",
    body    = "Hold it on GO IN, let go on STRIKE, hold again on BACK OUT, let go on RELEASE. The camera flip turns you on the hit, so the same key runs you back out.\n\nBoth bodies the key runs are in the settings (Utilities, Weave key). A change made in combat lands when combat ends.",
    visible = function(p) return p.weaveHelperEnabled ~= false and p.weaveKeyEnabled == true end,
    message = "NOCK_WEAVEKEY_CHANGED",
    keyCapture = {
      label = "Weave key",
      get = function(p) return p.weaveKey end,
      set = function(p, s) p.weaveKey = (s ~= "") and s or nil end,
    },
  },
  {
    key     = "corners",
    kind    = "toggles",
    reveals = { "react.corners", "react.buffs" },
    eyebrow = "Drag them where you want them",
    title   = "Corners & buff row",
    blurb   = "Your aspect and Hunter's Mark beside the cluster, your buffs above it.",
    visible = hudOn,
    options = {
      { key = "reactShowAspectIcon", label = "Aspect icon", desc = "The aspect you're in, top left of the cluster." },
      { key = "reactShowMarkIcon",   label = "Hunter's Mark icon", desc = "Your mark and its time left, top right." },
      { slider = true, key = "reactCornerIconSize", label = "Corner icon size", min = 20, max = 48, step = 1, default = 42 },
      { slider = true, key = "reactCornerIconX", label = "Corner icons: distance out", min = 0, max = 120, step = 1, default = 30 },
      { slider = true, key = "reactCornerIconY", label = "Corner icons: distance up", min = 0, max = 120, step = 1, default = 50 },
      { key = "reactBuffRows", label = "Buff row", desc = "Your short buffs and procs above the cluster, your pet's over them." },
      { slider = true, key = "reactBuffIconSize", label = "Buff icon size", min = 16, max = 40, step = 1, default = 26 },
    },
  },
  {
    key     = "warnings",
    kind    = "toggles",
    compact = true,
    reveals = { "warnings", "aggro" },
    eyebrow = "Big centre-screen alerts",
    title   = "Warnings",
    blurb   = "Sample alerts are showing now. Hover a row for what it watches.",
    refresh = buildWarningRows,
    onEnter = function(o) o:StartWarningDemo() end,
    onLeave = function(o) o:StopWarningDemo() end,
    -- Toggling a warning re-arms the demo so the samples never expire mid-page.
    onToggle = function(o) o:StartWarningDemo() end,
    options = {},   -- filled by refresh on every Open
  },
  {
    key     = "cues",
    kind    = "toggles",
    eyebrow = "Sounds",
    title   = "Range cues",
    blurb   = "A short voice line when your target crosses into a range zone. Raids only, until you change it in the settings.",
    options = {
      { key = "soundCuesEnabled", master = true, label = "Range cues", desc = "Master switch for the cues below." },
      { key = "cueDeadZoneEnabled", dependsOn = "soundCuesEnabled", sub = true, label = "Dead zone", desc = "Too close to shoot, too far to melee." },
      { key = "cueMeleeEnabled", dependsOn = "soundCuesEnabled", sub = true, label = "Melee", desc = "In melee range." },
      { key = "cueInRangeEnabled", dependsOn = "soundCuesEnabled", sub = true, label = "In range", desc = "Back in shooting range." },
      { key = "cueOutOfRangeEnabled", dependsOn = "soundCuesEnabled", sub = true, label = "Out of range", desc = "Too far to shoot." },
    },
  },
  {
    key     = "ring",
    kind    = "intro",
    eyebrow = "Optional",
    title   = "Aspect ring",
    blurb   = "Every aspect on one key.",
    body    = "Hold the key and a ring of your aspects opens at the cursor: flick toward one and let go to cast it, in or out of combat. Letting go in the middle casts nothing.\n\nThe dial's layout is in the settings (Utilities, Aspect ring).",
    message = "NOCK_ASPECT_RING_CONFIG",
    keyCapture = {
      label = "Ring key",
      get = function(p) return p.aspectRingKey end,
      set = function(p, s) p.aspectRingKey = (s ~= "") and s or nil end,
    },
  },
  {
    key     = "qol",
    kind    = "toggles",
    eyebrow = "Small things",
    title   = "Quality of life",
    blurb   = "Switches the game hides or leaves to you.",
    options = {
      qolRow("qolHideErrors", "SetHideErrors", "Hide red error text", "\"You have no target\", \"Can't do that yet\" and the like stop showing."),
      qolRow("qolNoGlow", "SetNoGlow", "Full-screen glow off", "No bloom and no drunk blur."),
      { key = "qolAutoRepair", label = "Auto repair", desc = "Repair everything at a repair vendor, with your own money." },
      { key = "qolSellGreys", label = "Sell grey items", desc = "Sell every grey item at any vendor." },
    },
  },
  {
    key     = "done",
    kind    = "finish",
    reveals = { "*" },
    eyebrow = "Setup complete",
    title   = "You're set!",
    blurb   = "Nock is live and configured like this:",
  },
}

--------------------------------------------------------------------------------
-- Recap (finish page)
--------------------------------------------------------------------------------
-- Reads the profile rather than remembering what was clicked, so a user who
-- walked back and changed their mind sees the truth. Six rows at most: the
-- finish page's note sits under the sixth.
local HUD_ROWS = {
  { "reactShowAutoBar", "Auto" }, { "reactShowMeleeBar", "melee" }, { "reactShowRangeBar", "range" },
  { "reactShowManaBar", "mana" }, { "reactShowCastBar", "cast" }, { "reactShowGrid", "grid" },
}

local function joinOr(list, empty)
  if #list == 0 then return empty end
  return table.concat(list, ", ")
end

function Onboarding:BuildRecap()
  local p = profile()
  if not p then return {} end
  local bars = {}
  for _, r in ipairs(HUD_ROWS) do if p[r[1]] ~= false then bars[#bars + 1] = r[2] end end
  local around = {}
  if p.reactShowAspectIcon then around[#around + 1] = "aspect" end
  if p.reactShowMarkIcon then around[#around + 1] = "Hunter's Mark" end
  if p.reactBuffRows ~= false then around[#around + 1] = "buff row" end
  local on, total = 0, 0
  local w = Nock:GetModule("Warnings", true)
  for _, e in ipairs(w and w.Catalog or {}) do
    total = total + 1
    if p[e.enabledKey] ~= false then on = on + 1 end
  end
  local cues = {}
  if p.soundCuesEnabled ~= false then
    if p.cueDeadZoneEnabled then cues[#cues + 1] = "dead zone" end
    if p.cueMeleeEnabled then cues[#cues + 1] = "melee" end
    if p.cueInRangeEnabled then cues[#cues + 1] = "in range" end
    if p.cueOutOfRangeEnabled then cues[#cues + 1] = "out of range" end
  end
  local ladder = (p.reactRangeStyle == "detailed") and "detailed" or "compact"
  local hud = hudOn(p)
  return {
    { "HUD", hud and (joinOr(bars, "nothing") .. " (" .. ladder .. " ladder)") or "off" },
    { "Around it", hud and joinOr(around, "nothing") or "off" },
    { "Warnings", p.showWarnings == false and "off" or (on .. " of " .. total .. " on") },
    { "Range cues", joinOr(cues, "off") },
    { "Aspect ring key", (p.aspectRingKey or "") ~= "" and p.aspectRingKey or "not set" },
    { "Weaving", p.weaveHelperEnabled == false and "turret"
        or (p.weaveKeyEnabled == true and ("helper on, weave key " .. (((p.weaveKey or "") ~= "") and p.weaveKey or "not set")) or "helper on, macros") },
  }
end
