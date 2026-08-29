-- Modules/Onboarding.lua
-- First-run setup wizard: the page script + the rules for applying choices.
-- Opens itself once on a fresh install and on demand via /nock setup. Every
-- page drives the real HUD, so the user configures Nock by watching it change
-- rather than by reading a settings tree. UI/Frame_Onboarding.lua renders this.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Onboarding = Nock:NewModule("Onboarding", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
local C = Nock.Constants

local VERSION = C_AddOns.GetAddOnMetadata("Nock", "Version") or "?"

-- Seconds after entering the world before the wizard shows itself. Long enough
-- for the HUD to paint and the login spam to settle, short enough to still read
-- as part of arriving.
local AUTO_OPEN_DELAY = 3
-- Warnings demo is armed for far longer than anyone lingers on one page; the
-- page's onLeave cancels it, so this is only a backstop against a stuck demo.
local WARNING_DEMO_SEC = 600

local function profile()
  return Nock.db and Nock.db.profile
end

local function spellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then
    local tex = C_Spell.GetSpellTexture(id)
    if tex then return tex end
  end
  if GetSpellTexture then
    local tex = GetSpellTexture(id)
    if tex then return tex end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

--------------------------------------------------------------------------------
-- Weave macro bodies
--------------------------------------------------------------------------------
-- The macro pages offer three shapes of the press/release pair plus two extras
-- (the Snowball poke and its garment gate). All the text surgery lives in
-- Core/WeaveMacro.lua, shared with the options builder so the two surfaces can
-- never generate subtly different macro bodies.
local WM = Nock.WeaveMacro

local function weaveMacros(p)
  return p.weaveBindMacroDown or "", p.weaveBindMacroUp or ""
end

local function pressBody(p) return p.weaveBindMacroDown or "" end

-- The weave bind Grounded (Gello) holds, or nil (WeaveBind reads its SV).
local function groundedBind()
  local wb = Nock.GetModule and Nock:GetModule("WeaveBind", true)
  return wb and wb.GroundedWeaveBind and wb:GroundedWeaveBind() or nil
end

-- A body the wizard may rewrite: one Nock authored, or one the Grounded
-- import put there (the user chose "Default" over it -- that is the point of
-- the choice; Undo in the settings still holds the import).
local function replaceable(p, text, shipped)
  if WM.IsNockAuthored(text, shipped) then return true end
  local imp = p.weaveBindImported
  return imp ~= nil and (text == (imp.down or "") or text == (imp.up or ""))
end

-- Every extras-row write goes through here so there is one place that stores
-- the rewritten press body.
local function setPressBody(p, text)
  p.weaveBindMacroDown = text
  -- The release re-arm follows the poke's gate (the inverse), on a release
  -- body Nock authored.
  WM.SyncRearmIfStock(p, C.WEAVE_BIND_MACRO_UP)
end

--------------------------------------------------------------------------------
-- Page script
--------------------------------------------------------------------------------
-- Each page is one decision. `kind` picks the renderer in the view:
--   checks  - SetupCheck rows with their own fix buttons
--   cards   - exclusive choice; the selected card carries the glow
--   toggles - independent switches
--   finish  - recap + exits
--
-- cards:   { value, label, desc, recommended, icon(), isSelected(p), apply(p) }
-- toggles: { key, label, desc, recommended, recommendOn, recommendOff, sub, dependsOn }
--   A row normally names a profile `key` and the wizard flips p[key]. A row may
--   instead carry `id` + `isOn(p)` + `setOn(p, on)` for a setting that does not
--   live in a boolean profile key — the weave extras below live inside the
--   macro TEXT, so they read and write that. `dependsOn` is a profile key, or a
--   function(p) for a dependency that is itself derived.
--   recommendOn marks a switch that should start ON for a brand-new user even
--   though its stored default is off. Seeding happens on first run only (see
--   SeedRecommendations) so a later re-run never undoes a deliberate opt-out.
--   recommendOff is display-only: it badges a switch as NOT RECOMMENDED and
--   seeds nothing, for parity features that exist but shouldn't be the default.

Onboarding.Pages = {
  {
    key     = "welcome",
    kind    = "checks",
    eyebrow = "First-time setup",
    title   = "Welcome to Nock",
    blurb   = "A hunter HUD built around TBC weaving. First, a few client settings Nock can fix for you.",
  },
  {
    key     = "hudstyle",
    kind    = "cards",
    eyebrow = "You can swap back anytime",
    title   = "Pick your HUD style",
    blurb   = "This swaps your real HUD live - watch it change behind this window.",
    options = {
      {
        value = "classic", label = "Classic", recommended = true,
        desc  = "The full toolkit: swing bars, shot timeline, cooldown grid.",
        icon  = function() return spellIcon(C.SpellID.AUTO_SHOT) end,
        isSelected = function(p) return p.hudEnabled ~= false and p.hudMode ~= "react" end,
        apply      = function(p) p.hudEnabled = true; p.hudMode = "classic" end,
      },
      {
        value = "react", label = "React",
        desc  = "One compact cluster, styled after the React WeakAura.",
        icon  = function() return spellIcon(C.SpellID.RAPID_FIRE) end,
        isSelected = function(p) return p.hudEnabled ~= false and p.hudMode == "react" end,
        apply      = function(p) p.hudEnabled = true; p.hudMode = "react" end,
      },
      {
        value = "none", label = "No HUD",
        desc  = "No bars on screen. Warnings, trackers and the out-of-combat helpers still work.",
        icon  = function() return spellIcon(C.SpellID.FEIGN_DEATH) end,
        isSelected = function(p) return p.hudEnabled == false end,
        -- The medallion floats free of the HUD box, so it would survive on its
        -- own; someone asking for no HUD does not mean "except this one icon".
        apply = function(p) p.hudEnabled = false; p.medallionEnabled = false end,
      },
    },
  },
  {
    key     = "reactcorners",
    kind    = "toggles",
    eyebrow = "Reference WeakAura parity",
    title   = "Corner status icons",
    blurb   = "The React WeakAura flanks its cluster with two status icons. Nock's warning system already covers both, so these ship off - flip them on if you want the original look.",
    -- React-only: the classic HUD has these as slots in its rotation row, and
    -- with the HUD off there is nothing to flank.
    visible = function(p) return p.hudEnabled ~= false and p.hudMode == "react" end,
    options = {
      { key = "reactShowAspectIcon", recommendOff = true,
        label = "Aspect icon",
        desc  = "Top-left. The aspect you're in, greyed when you have none. The Aspect warning says it louder, and only when you're in combat with the wrong one." },
      { key = "reactShowMarkIcon", recommendOff = true,
        label = "Hunter's Mark icon",
        desc  = "Top-right. Mark timer on your target, greyed when it isn't marked." },
    },
  },
  {
    key     = "rotation",
    kind    = "cards",
    eyebrow = "Same engine, three looks",
    title   = "How should Nock call your shots?",
    blurb   = "All three show the same next-action logic. Pick how you want to see it.",
    -- Classic-with-a-HUD only. React carries its own fixed shot display and
    -- ignores rotationMode / the Shot Bars keys entirely (see UI/HUD.lua), and
    -- with the HUD off there is nothing for any of the three to draw on.
    visible = function(p) return p.hudEnabled ~= false and p.hudMode ~= "react" end,
    onEnter = function(self) Nock.state.demo.rotationSample = true end,
    onLeave = function(self) Nock.state.demo.rotationSample = false end,
    options = {
      {
        value = "bars", label = "Shot Bars", recommended = true,
        desc  = "A scrolling timeline of your next shots.",
        icon  = function() return spellIcon(C.SpellID.STEADY_SHOT) end,
        isSelected = function(p) return p.rotationMode ~= "helper" and not p.medallionEnabled end,
        apply = function(p)
          p.rotationMode = "bars"; p.showRotation = true; p.medallionEnabled = false
        end,
      },
      {
        value = "helper", label = "Helper icons",
        desc  = "A row of six icons - the lit one is what to press.",
        icon  = function() return spellIcon(C.SpellID.MULTI_SHOT) end,
        isSelected = function(p) return p.rotationMode == "helper" and not p.medallionEnabled end,
        apply = function(p)
          p.rotationMode = "helper"; p.showRotation = true; p.medallionEnabled = false
        end,
      },
      {
        value = "medallion", label = "Medallion",
        desc  = "One big icon. The next shot, nothing else.",
        icon  = function() return spellIcon(C.SpellID.KILL_COMMAND) end,
        isSelected = function(p) return p.medallionEnabled == true end,
        apply = function(p)
          p.medallionEnabled = true; p.showRotation = true
        end,
      },
    },
  },
  {
    key     = "playstyle",
    kind    = "cards",
    eyebrow = "Playstyle",
    title   = "Do you melee weave?",
    blurb   = "Weaving slips a melee swing between shots for extra damage. Nock can coach the timing.",
    footnote = "Weavers: you can set your weave key on the last step.",
    options = {
      {
        value = "weaver", label = "Yes - I weave", recommended = true,
        desc  = "Show weave timing and the range coach.",
        icon  = function() return spellIcon(C.SpellID.RAPTOR_STRIKE) end,
        isSelected = function(p) return p.weaveNotationEnabled == true end,
        -- Deliberately never touches weaveBindEnabled: the bind is a secure
        -- override with no key set by default, and arming half of it here would
        -- leave the user with a bind that does nothing. It no longer arms
        -- weaveCoachSoundsEnabled either — those cues are withdrawn from the GUI
        -- and default off, so turning them on here would hand the user a sound
        -- they cannot find a switch for.
        apply = function(p)
          p.weaveNotationEnabled = true
          p.showRangeFinder      = true
          p.shotBarsShowRaptor   = true
        end,
      },
      {
        value = "turret", label = "No - I stand and shoot",
        desc  = "Keep it simple. You can turn weaving on later.",
        icon  = function() return spellIcon(C.SpellID.ASPECT_HAWK) end,
        isSelected = function(p) return p.weaveNotationEnabled ~= true end,
        apply = function(p)
          p.weaveNotationEnabled = false
          p.shotBarsShowRaptor   = false
          p.showRangeFinder      = true   -- still worth having: it shows the dead zone
        end,
      },
    },
  },
  {
    key     = "weavemacro",
    kind    = "cards",
    eyebrow = "Weave key macros",
    title   = "How should the weave key behave?",
    blurb   = "The key runs one macro as you press and another as you release. Pick a starting point.",
    footnote = "You still choose the key itself in the settings - the last step has a shortcut. From Grounded brings its key along.",
    -- Weavers only: a turret never presses this key, so asking would be noise.
    visible = function(p) return p.weaveNotationEnabled == true end,
    message = "NOCK_WEAVEBIND_CHANGED",
    options = {
      {
        value = "default", label = "Default", recommended = true,
        desc  = "Nock's tested pair: poke, Raptor Strike, then Kill Command and back to Auto Shot.",
        icon  = function() return spellIcon(C.SpellID.RAPTOR_STRIKE) end,
        isSelected = function(p)
          local down, up = weaveMacros(p)
          return down ~= "" and not WM.HasMovePad(down) and not WM.HasMovePad(up)
        end,
        -- Restores only what Nock wrote. A hand-edited body is left exactly as
        -- the user typed it, so re-running the wizard can never eat their work.
        -- "Default" means the shape WITHOUT the step-out, not a factory reset:
        -- an emptied body comes back, and anything else Nock authored keeps the
        -- extras page's answers (poke, gate) and loses only the MovePad line.
        -- Otherwise the two macro pages would undo each other.
        apply = function(p)
          local down, up = weaveMacros(p)
          local imp = p.weaveBindImported
          if replaceable(p, down, C.WEAVE_BIND_MACRO_DOWN) then
            p.weaveBindMacroDown = (down == "" or (imp and down == (imp.down or ""))) and C.WEAVE_BIND_MACRO_DOWN
              or WM.WithoutMovePad(down)
          end
          if replaceable(p, up, C.WEAVE_BIND_MACRO_UP) then
            p.weaveBindMacroUp = (up == "" or (imp and up == (imp.up or ""))) and C.WEAVE_BIND_MACRO_UP
              or WM.WithoutMovePad(up)
          end
        end,
      },
      {
        value = "clever", label = "Clever",
        desc  = "The default plus auto-backpedal: you step out for exactly as long as you hold the key.",
        icon  = function() return spellIcon(C.SpellID.ASPECT_CHEETAH) end,
        isSelected = function(p)
          local down, up = weaveMacros(p)
          return WM.HasMovePad(down) or WM.HasMovePad(up)
        end,
        apply = function(p)
          -- Added to whatever is there now, so a hand-written macro gains the
          -- step-out instead of being replaced by the shipped one.
          local down, up = weaveMacros(p)
          if down == "" then down = C.WEAVE_BIND_MACRO_DOWN end
          if up == "" then up = C.WEAVE_BIND_MACRO_UP end
          p.weaveBindMacroDown = WM.WithMovePad(down)
          p.weaveBindMacroUp   = WM.WithMovePad(up)
        end,
        -- The Movement Pad is load-on-demand and can be absent; ask WeaveBind to
        -- pull it in now and say so if it can't, rather than letting the line
        -- fail silently the first time the user weaves.
        after = function(self)
          local wb = Nock:GetModule("WeaveBind", true)
          if wb and wb.EnsureMovePad then wb:EnsureMovePad() end
        end,
      },
      {
        value = "natty", label = "Natty",
        desc  = "Empty both macros so you can write your own from scratch.",
        icon  = function() return spellIcon(C.SpellID.FEIGN_DEATH) end,
        isSelected = function(p)
          local down, up = weaveMacros(p)
          return down == "" and up == ""
        end,
        apply = function(p)
          p.weaveBindMacroDown = ""
          p.weaveBindMacroUp   = ""
        end,
      },
      -- Grounded (Gello): the card is there only while Grounded holds a weave
      -- bind (user, 2026-08-27: the welcome page's check row made no sense
      -- beside these -- the choice is "Nock's defaults, or hard-import
      -- Grounded", and it belongs here). Picking it moves the bind -- key
      -- and both macros -- into Nock; Default over it afterwards restores
      -- the shipped macros (replaceable), the import's copy stays for Undo.
      {
        value = "grounded", label = "From Grounded",
        desc  = "Move the weave bind Grounded holds - the key and both macros - into Nock. Grounded gives the key up.",
        icon  = function() return spellIcon(C.SpellID.KILL_COMMAND) end,
        visible = function(p) return groundedBind() ~= nil or (p.weaveBindImported ~= nil) end,
        isSelected = function(p)
          local imp = p.weaveBindImported
          if not imp then return false end
          local down, up = weaveMacros(p)
          return down == (imp.down or "") and up == (imp.up or "")
        end,
        apply = function(p)
          local wb = Nock.GetModule and Nock:GetModule("WeaveBind", true)
          if wb and wb.ImportFromGrounded then wb:ImportFromGrounded() end
        end,
      },
    },
  },
  {
    key     = "weavemacroextras",
    kind    = "toggles",
    eyebrow = "Press macro extras",
    title   = "The Snowball trick",
    blurb   = "Two switches that change what the press macro does. Both edit the macro text you can also type by hand.",
    -- No footnote pointing at the garment autopilot: that side of the feature is
    -- still experimental and does not belong in a first-run wizard.
    -- Weavers with something to edit. Natty emptied the press body on purpose,
    -- and there is nothing to add a poke to.
    visible = function(p)
      return p.weaveNotationEnabled == true and (p.weaveBindMacroDown or "") ~= ""
    end,
    message = "NOCK_WEAVEBIND_CHANGED",
    options = {
      {
        id    = "snowballPoke",
        label = "Snowball poke",
        desc  = "Free, and off the global cooldown. Throwing one as you step in makes the server update where you are standing, so the white hit you weaved for actually lands.",
        isOn  = function(p) return WM.HasSnowball(pressBody(p)) end,
        setOn = function(p, on)
          setPressBody(p, on and WM.WithSnowball(pressBody(p))
                            or WM.WithoutSnowball(pressBody(p)))
        end,
      },
      {
        id    = "snowballGate", sub = true,
        label = "Only for bosses",
        desc  = "Gates the poke behind a garment, so trash and questing do not burn your stack: it fires only while the shirt is off - the state you want for a boss. The release macro gets the inverse, /startattack while the shirt is on, standing in for the poke.",
        dependsOn = function(p) return WM.HasSnowball(pressBody(p)) end,
        isOn  = function(p) return WM.GateOf(pressBody(p)) ~= nil end,
        setOn = function(p, on)
          if not on then
            setPressBody(p, WM.WithoutGate(pressBody(p)))
            return
          end
          local g, dir = WM.GateOf(pressBody(p))
          setPressBody(p, WM.WithGate(pressBody(p), g or "shirt", dir or "off"))
        end,
      },
      {
        id    = "gateTabard", sub = true,
        label = "Use my tabard instead of my shirt",
        desc  = "Same gate, driven by the tabard slot instead. Pick whichever one you are happy to take off for a fight.",
        dependsOn = function(p) return WM.GateOf(pressBody(p)) ~= nil end,
        isOn  = function(p) return (WM.GateOf(pressBody(p))) == "tabard" end,
        -- Every bracket in both bodies follows (the re-arm, a hand-written
        -- gate), not just the poke's.
        setOn = function(p, on)
          local garment = on and "tabard" or "shirt"
          p.weaveBindMacroUp = WM.WithGarment(p.weaveBindMacroUp or "", garment)
          setPressBody(p, WM.WithGarment(pressBody(p), garment))
        end,
      },
      {
        id    = "gateWorn", sub = true,
        label = "Flip it: throw only while the garment is worn",
        desc  = "The other way round: the poke fires while the garment is on and stops when you take it off.",
        dependsOn = function(p) return WM.GateOf(pressBody(p)) ~= nil end,
        isOn  = function(p) return select(2, WM.GateOf(pressBody(p))) == "on" end,
        -- A direction flip inverts every bracket in both bodies, so a line
        -- gated the other way round from the poke stays the other way round.
        setOn = function(p, on)
          local _, dir = WM.GateOf(pressBody(p))
          if (dir or "off") == (on and "on" or "off") then return end
          p.weaveBindMacroUp = WM.InvertGates(p.weaveBindMacroUp or "")
          setPressBody(p, WM.InvertGates(pressBody(p)))
        end,
      },
    },
  },
  {
    key     = "warnings",
    kind    = "toggles",
    eyebrow = "Big center-screen alerts",
    title   = "Warnings that save you",
    blurb   = "Three sample alerts are showing right now - try the switches.",
    onEnter = function(self) self:StartWarningDemo() end,
    onLeave = function(self) self:StopWarningDemo() end,
    -- Toggling a warning re-arms the demo so the samples never expire mid-page.
    onToggle = function(self) self:StartWarningDemo() end,
    options = {
      { key = "showWarnings", master = true,
        label = "Enable warnings", desc = "Master switch for every alert square." },
      { key = "warnAspectEnabled", dependsOn = "showWarnings",
        label = "Aspect check", desc = "In combat without Hawk? Get told." },
      { key = "warnTargetFrenzyEnabled", dependsOn = "showWarnings",
        label = "Tranq alert", desc = "Your target enrages - shoot Tranquilizing Shot." },
      { key = "warnManaEnabled", dependsOn = "showWarnings",
        label = "Low mana", desc = "Swap to Viper before you run dry." },
    },
  },
  {
    key     = "trackers",
    kind    = "toggles",
    eyebrow = "Small panels - drag them anywhere",
    title   = "Raid trackers",
    blurb   = "Misdirection is on already - see it below. Flip the others to try them.",
    onEnter = function(self) Nock.state.demo.debuffTracker = true end,
    onLeave = function(self) Nock.state.demo.debuffTracker = false end,
    options = {
      { key = "misdirectEnabled", recommendOn = true,
        label = "Misdirection tracker", desc = "Every hunter's MD cooldown in your group." },
      { key = "mdCastEnabled", recommendOn = true, sub = true, dependsOn = "misdirectEnabled",
        label = "Click-to-MD tank buttons", desc = "One click casts MD on your tank. Buttons appear once you're in a group." },
      { key = "buffTrackerEnabled",
        label = "Buff tracker", desc = "Your raid buffs - missing ones turn grey." },
      { key = "debuffTrackerEnabled",
        label = "Debuff tracker", desc = "Your marks and stings on the target." },
    },
  },
  {
    -- Copy carries no slash command on purpose: the wizard's own test forbids
    -- one anywhere in page text, and the Settings page is where they belong.
    key     = "steamtonk",
    kind    = "toggles",
    eyebrow = "Stops the tonk welding you",
    title   = "Steam Tonk safety",
    blurb   = "The Steam Tonk Controller saves a pet from a boss mechanic. But the obvious one-button macro cancels the transform in the same instant it starts it, and the game regularly leaves you stuck in place, unable to move or cast.\n\nUse the tonk from any button, on its own, and take any /cancelaura line out of your macro. Nock steps you back out a moment later - in combat as well as out of it.",
    options = {
      { key = "tonkAutoCancel",
        label = "Step me back out automatically",
        desc  = "Leaves the tonk on its own shortly after the transform lands, whether or not you are in combat." },
      { key = "tonkDialEnabled", sub = true,
        label = "Show the countdown dial",
        desc  = "A small tonk icon with a sweep running down to the moment you step out, so it is never a surprise." },
    },
  },
  {
    key     = "utility",
    kind    = "toggles",
    eyebrow = "Quiet quality-of-life",
    title   = "Out-of-combat helpers",
    blurb   = "These only speak up when something needs doing.",
    options = {
      { key = "shoppingEnabled",
        label = "Shopping list", desc = "Low on arrows or pet food in town? A restock list pops up." },
      { key = "mailboxEnabled",
        label = "Mailbox helper", desc = "One-click snowball mail logistics at any mailbox." },
      { key = "petTrainerHelperEnabled",
        label = "Pet trainer checklist", desc = "Per-raid Beast Training presets so your pet is never undertrained." },
      { key = "repairWarnEnabled",
        label = "Repair warning", desc = "A strip under the HUD when your gear runs low." },
    },
  },
  {
    key     = "finish",
    kind    = "finish",
    eyebrow = "Setup complete",
    title   = "You're set!",
    blurb   = "Your HUD is live and configured like this:",
  },
}

--------------------------------------------------------------------------------
-- Recap (finish page)
--------------------------------------------------------------------------------
-- Reads the profile rather than remembering what was clicked, so a user who
-- walked back and changed their mind sees the truth.
local function joinOr(list, empty)
  if #list == 0 then return empty end
  return table.concat(list, ", ")
end

function Onboarding:BuildRecap()
  local p = profile()
  if not p then return {} end

  local warns = {}
  if p.showWarnings ~= false then
    if p.warnAspectEnabled ~= false then warns[#warns + 1] = "aspect" end
    if p.warnTargetFrenzyEnabled ~= false then warns[#warns + 1] = "tranq" end
    if p.warnManaEnabled ~= false then warns[#warns + 1] = "mana" end
  end

  local trackers = {}
  if p.misdirectEnabled then trackers[#trackers + 1] = "misdirection" end
  if p.buffTrackerEnabled then trackers[#trackers + 1] = "buffs" end
  if p.debuffTrackerEnabled then trackers[#trackers + 1] = "debuffs" end

  local style
  if p.hudEnabled == false then style = "Off"
  elseif p.hudMode == "react" then style = "React"
  else style = "Classic" end

  local rows = { { "HUD style", style } }
  -- Each row below reports a question this run actually asked, so the recap
  -- never claims a setting the user was never shown.
  if p.hudEnabled ~= false and p.hudMode ~= "react" then
    local shots
    if p.medallionEnabled then shots = "Medallion"
    elseif p.rotationMode == "helper" then shots = "Helper icons"
    else shots = "Shot Bars" end
    rows[#rows + 1] = { "Shot display", shots }
  end
  -- React's counterpart question. Mutually exclusive with the row above: one
  -- of the two is asked, never both.
  if p.hudEnabled ~= false and p.hudMode == "react" then
    local corners = {}
    if p.reactShowAspectIcon then corners[#corners + 1] = "aspect" end
    if p.reactShowMarkIcon then corners[#corners + 1] = "Hunter's Mark" end
    rows[#rows + 1] = { "Corner icons", joinOr(corners, "none") }
  end
  rows[#rows + 1] = { "Playstyle", p.weaveNotationEnabled and "Melee weaver" or "Stand and shoot" }
  -- Only weavers were asked about macros, so only they get the line back.
  if p.weaveNotationEnabled then
    rows[#rows + 1] = { "Weave macros", self:MacroStyleName() }
    -- The key, once one is set (the welcome page's Grounded import sets it).
    if p.weaveBindEnabled == true and (p.weaveBindKey or "") ~= "" then
      rows[#rows + 1] = { "Weave key", p.weaveBindKey .. (p.weaveBindImported and " (from Grounded)" or "") }
    end
  end
  rows[#rows + 1] = { "Warnings", p.showWarnings == false and "off" or joinOr(warns, "none") }
  rows[#rows + 1] = { "Trackers", joinOr(trackers, "none") }
  return rows
end

-- Which of the three macro shapes the stored bodies currently match. Derived
-- rather than remembered, so a macro edited in the settings reads correctly.
function Onboarding:MacroStyleName()
  local p = profile()
  if not p then return "Default" end
  local down, up = weaveMacros(p)
  if down == "" and up == "" then return "Natty (write your own)" end
  if WM.HasMovePad(down) or WM.HasMovePad(up) then return "Clever (auto-backpedal)" end
  return "Default"
end

-- The finish page offers a weave-key shortcut only to someone who said they weave.
function Onboarding:WantsWeaveKey()
  local p = profile()
  return p and p.weaveNotationEnabled == true
end

--------------------------------------------------------------------------------
-- Applying choices
--------------------------------------------------------------------------------
-- Single choke point: every profile write in the wizard ends here, so there is
-- one place that knows a change has to be broadcast. Mirrors visualsSet() in
-- Config/Options.lua.
function Onboarding:Commit(page)
  Nock:SendMessage("NOCK_VISUALS_CHANGED")
  -- Some pages own settings a second listener cares about (the weave macros are
  -- applied to a secure button, not drawn).
  if page and page.message then Nock:SendMessage(page.message) end
end

function Onboarding:SelectCard(page, option)
  local p = profile()
  if not p or not option.apply then return end
  option.apply(p)
  self:Commit(page)
  if option.after then option.after(self) end
end

-- Current position of a switch. Keyed rows read their profile key; derived
-- rows (the weave extras) answer out of the macro text they edit.
function Onboarding:IsOptionOn(option)
  local p = profile()
  if not p then return false end
  if option.isOn then return option.isOn(p) and true or false end
  return p[option.key] and true or false
end

function Onboarding:ToggleOption(page, option)
  local p = profile()
  if not p then return end
  local on = not self:IsOptionOn(option)
  if option.setOn then option.setOn(p, on) else p[option.key] = on end
  if page.onToggle then page.onToggle(self) end
  self:Commit(page)
end

-- A toggle whose dependency is off can't do anything, so the view greys it out
-- and the engine refuses the click. The dependency is normally another
-- switch's profile key; a derived row supplies a function instead.
function Onboarding:IsOptionLocked(option)
  local p = profile()
  if not p or not option.dependsOn then return false end
  if type(option.dependsOn) == "function" then return not option.dependsOn(p) end
  return not p[option.dependsOn]
end

-- Seed the recommended answer so a brand-new user sees it already chosen (and,
-- because choices apply instantly, already previewed on the HUD). First run
-- only: on a re-run the stored value is the user's answer, not an absence of
-- one, and re-seeding would quietly undo a deliberate opt-out.
function Onboarding:SeedRecommendations(page)
  if not self._firstRun then return end
  local p = profile()
  local defaults = Nock.Defaults and Nock.Defaults.profile
  if not p or not defaults then return end

  -- Cards: apply the recommended one unless it is already the live answer.
  -- Mostly a no-op (the shipped defaults are the recommendation), but the
  -- weaver card is the exception Nock actually wants to lead with.
  if page.kind == "cards" then
    for _, option in ipairs(page.options or {}) do
      if option.recommended and option.isSelected and not option.isSelected(p) then
        option.apply(p)
        self:Commit(page)
        return
      end
    end
    return
  end

  -- Toggles: only switches explicitly marked recommendOn, and only while they
  -- still hold their shipped (off) value.
  if page.kind ~= "toggles" then return end
  local changed = false
  for _, option in ipairs(page.options or {}) do
    -- Keyed rows only: a derived row has no shipped default to compare against,
    -- and nothing to seed into.
    if option.key and option.recommendOn
       and p[option.key] == defaults[option.key] and not p[option.key] then
      p[option.key] = true
      changed = true
    end
  end
  if changed then self:Commit(page) end
end

--------------------------------------------------------------------------------
-- Page lifecycle
--------------------------------------------------------------------------------
function Onboarding:StartWarningDemo()
  local w = Nock:GetModule("Warnings", true)
  if w and w.RunDemo then w:RunDemo(WARNING_DEMO_SEC) end
end

function Onboarding:StopWarningDemo()
  local w = Nock:GetModule("Warnings", true)
  if w and w.StopDemo then w:StopDemo() end
end

function Onboarding:EnterPage(index)
  local page = self.Pages[index]
  if not page then return end
  self._page = index
  self:SeedRecommendations(page)
  if page.onEnter then page.onEnter(self) end
end

function Onboarding:LeavePage()
  local page = self.Pages[self._page or 0]
  if page and page.onLeave then page.onLeave(self) end
end

-- Pages may opt out of being shown at all (the weave macro page only exists for
-- someone who said they weave). Visibility is re-evaluated on every move, so
-- answering "yes I weave" on one page makes the next one appear immediately.
function Onboarding:IsPageVisible(page)
  if not page.visible then return true end
  local p = profile()
  return p and page.visible(p) or false
end

-- Positions of the currently-shown pages within self.Pages, in order.
function Onboarding:VisibleIndices()
  local out = {}
  for i, page in ipairs(self.Pages) do
    if self:IsPageVisible(page) then out[#out + 1] = i end
  end
  return out
end

-- Where the current page sits in that list, and how long the list is - the two
-- numbers the progress readout needs.
function Onboarding:Progress()
  local visible = self:VisibleIndices()
  local current = self._page or 1
  for slot, index in ipairs(visible) do
    if index == current then return slot, #visible end
  end
  return 1, #visible
end

function Onboarding:GoTo(index)
  index = math.max(1, math.min(#self.Pages, index))
  if index == self._page then return end
  self:LeavePage()
  self:EnterPage(index)
  self:Render()
end

-- Step to the next/previous page that is actually shown. Returns nil at the end
-- of the run in the given direction.
function Onboarding:AdjacentPage(step)
  local i = (self._page or 1) + step
  while i >= 1 and i <= #self.Pages do
    if self:IsPageVisible(self.Pages[i]) then return i end
    i = i + step
  end
  return nil
end

function Onboarding:Next()
  local index = self:AdjacentPage(1)
  if not index then return self:Close() end
  self:GoTo(index)
end

function Onboarding:Back()
  local index = self:AdjacentPage(-1)
  if index then self:GoTo(index) end
end

function Onboarding:IsLastPage()
  return self:AdjacentPage(1) == nil
end

function Onboarding:CurrentPage()
  return self.Pages[self._page or 1], self._page or 1
end

function Onboarding:Render()
  local view = Nock:GetModule("OnboardingView", true)
  if view and view.Render then view:Render() end
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------
function Onboarding:IsOpen()
  local view = Nock:GetModule("OnboardingView", true)
  return view and view.frame and view.frame:IsShown() or false
end

function Onboarding:Open(index)
  local view = Nock:GetModule("OnboardingView", true)
  if not view then return end

  -- Preview mode: keep the HUD on screen for the whole session even if this
  -- user normally hides it out of combat, or every page would demo an
  -- invisible HUD.
  Nock.state.demo.hudForceShow = true
  -- Unlock everything while the wizard is open so frames can be dragged into
  -- place; Teardown locks again on every close path. The char flag survives a
  -- /reload or logout that kills the wizard before Teardown runs — the next
  -- login pass (OnEnteringWorld) sees it and relocks.
  if profile() then
    if Nock.db.char then Nock.db.char.wizardLockPending = true end
    Nock:SetLocked(false)
  end
  self:EnterPage(index or 1)
  view:Show()
  self:Commit()
end

function Onboarding:Close()
  local view = Nock:GetModule("OnboardingView", true)
  if view then view:Hide() end   -- OnHide runs Teardown
end

-- Idempotent: reached from Close, Skip, Finish, the X and Esc. Never rolls back
-- a profile write - choices are real the moment they're made. Only the
-- transient preview state goes away.
function Onboarding:Teardown()
  self:LeavePage()
  self:StopWarningDemo()
  local demo = Nock.state.demo
  for k in pairs(demo) do demo[k] = false end
  self._page = nil
  self._firstRun = false
  -- Auto-lock: Open unlocked everything for dragging; the resting state is
  -- locked, whichever way the wizard was closed. Before Commit so the repaint
  -- (opacity / hideOoc / backgrounds branch on the lock) sees the final state.
  if profile() then
    if Nock.db.char then Nock.db.char.wizardLockPending = false end
    Nock:SetLocked(true)
  end
  self:Commit()
end

--------------------------------------------------------------------------------
-- First-run gate
--------------------------------------------------------------------------------
function Onboarding:OnEnable()
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
end

function Onboarding:OnEnteringWorld()
  -- Safety net: a /reload or logout while the wizard was open skipped Teardown
  -- (the frame's OnHide never fires), leaving every frame unlocked with no way
  -- back — the first-run stamp blocks reopening. Restore the resting state.
  local ch = Nock.db and Nock.db.char
  if ch and ch.wizardLockPending and not self:IsOpen() then
    ch.wizardLockPending = false
    Nock:SetLocked(true)
  end
  if self._autoOpenChecked then return end
  self._autoOpenChecked = true
  if not Nock.isHunter then return end
  if Nock.db.global.onboarding then return end
  self:ScheduleTimer("AutoOpen", AUTO_OPEN_DELAY)
end

function Onboarding:AutoOpen()
  -- Pulled something on the way in: wait it out rather than dropping a window
  -- over the fight.
  if InCombatLockdown() then
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")
    return
  end
  -- Stamped as the wizard opens, not as it finishes: someone who logs out
  -- halfway through has still seen it, and shouldn't be greeted again.
  Nock.db.global.onboarding = { seenVersion = VERSION }
  self._firstRun = true
  self:Open(1)
end

function Onboarding:OnCombatEnded()
  self:UnregisterEvent("PLAYER_REGEN_ENABLED")
  self:ScheduleTimer("AutoOpen", 1)
end

-- /nock setup. Not a first run: recommendations are not re-seeded, so an
-- earlier "no thanks" survives.
function Onboarding:Command()
  -- The auto-open already defers past combat; the manual entry points must
  -- refuse too — Open unlocks frames (pokes the protected Misdirect panel)
  -- and drops the demo HUD over a live fight.
  if InCombatLockdown() then
    self:Print("The setup wizard can't open in combat — try again after the fight.")
    return
  end
  self._firstRun = false
  if self:IsOpen() then self:Close() end
  self:Open(1)
end
