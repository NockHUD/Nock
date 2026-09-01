-- Tests/onboarding_test.lua
-- Standalone LuaJIT tests for the onboarding wizard's decision logic: page
-- script wiring, recommended-answer seeding, and the finish-page recap.
-- Run from the repo root: luajit Tests/onboarding_test.lua
--
-- Modules/Onboarding.lua is a WoW addon file, so the WoW/Ace surface it touches
-- at load time is stubbed below. Only the pure parts are exercised: nothing here
-- draws a frame.

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

--------------------------------------------------------------------------------
-- Minimal WoW / Ace stubs
--------------------------------------------------------------------------------
local sentMessages = {}
local sentArgs     = {}   -- parallel: { msg = name, payload = first vararg }

local KC_LINE    = "/use [@pettarget,exists,harm,nodead] Kill Command"
local MACRO_DOWN = "/use Snowball\n/use Raptor Strike\n" .. KC_LINE .. "\n/startattack"
local MACRO_UP   = KC_LINE .. "\n/use [exists,harm,nodead] !Auto Shot"
local MOVEPAD    = "/click MovePadBackward"
local SNOWBALL   = "/use Snowball"
-- The press body with the poke stripped, and with it gated behind a shirt
-- (the gate covers the poke and the press /startattack).
local NOPOKE     = "/use Raptor Strike\n" .. KC_LINE .. "\n/startattack"
local GATED      = "/use [noequipped:Shirt] Snowball\n/use Raptor Strike\n" .. KC_LINE .. "\n/startattack [noequipped:Shirt]"
-- The pre-2026-09 stock pair: still Nock-authored, upgraded by Default.
local LEGACY_DOWN = "/use Snowball\n/stopcasting\n/cast Raptor Strike\n/startattack"
local LEGACY_UP   = "/cast [target=pettarget,exists] Kill Command\n/cast !Auto Shot"

local Nock = {
  Constants = {
    SpellID = {
      AUTO_SHOT = 75, RAPID_FIRE = 3045, STEADY_SHOT = 34120, MULTI_SHOT = 27021,
      KILL_COMMAND = 34026, RAPTOR_STRIKE = 27014, ASPECT_HAWK = 27044,
      ASPECT_CHEETAH = 5118, FEIGN_DEATH = 5384,
    },
    WEAVE_BIND_MACRO_DOWN        = MACRO_DOWN,
    WEAVE_BIND_MACRO_UP          = MACRO_UP,
    WEAVE_BIND_MACRO_DOWN_LEGACY = LEGACY_DOWN,
    WEAVE_BIND_MACRO_UP_LEGACY   = LEGACY_UP,
    WEAVE_BIND_MOVEPAD_LINE  = MOVEPAD,
    WEAVE_BIND_SNOWBALL_LINE = SNOWBALL,
  },
  state = { demo = {} },
  isHunter = true,
  db = { profile = {}, global = {}, char = {} },
  Defaults = { profile = {} },
}

function Nock:SendMessage(msg, payload)
  sentMessages[#sentMessages + 1] = msg
  sentArgs[#sentArgs + 1] = { msg = msg, payload = payload }
end

-- Mirrors the real accessors in Core/Core.lua (single write path for the
-- global lock; keep in sync if that implementation changes).
function Nock:SetLocked(v)
  v = v and true or false
  self.db.profile.locked = v
  self:SendMessage("NOCK_LOCK_CHANGED", v)
end
function Nock.IsLocked()
  local p = Nock.db and Nock.db.profile
  if not p then return true end
  return p.locked ~= false
end

-- The module under test is whatever NewModule hands back, so keep a reference.
local O

-- Fake view standing in for UI/Frame_Onboarding.lua. Its Hide() runs Teardown,
-- documenting the real frame's OnHide contract (every close path funnels
-- through Teardown). Everything else (Warnings, SetupCheck) stays absent.
local fakeView = { shown = false }
function fakeView:Show() self.shown = true end
function fakeView:Hide()
  if not self.shown then return end
  self.shown = false
  O:Teardown()
end
function Nock:GetModule(name)
  if name == "OnboardingView" then return fakeView end
  return nil   -- Warnings absent: demo calls no-op
end

function Nock:NewModule()
  O = {}
  function O:RegisterEvent() end
  function O:UnregisterEvent() end
  function O:ScheduleTimer() end
  function O:Print() end
  return O
end

_G.LibStub = function() return { GetAddon = function() return Nock end } end
_G.C_AddOns = { GetAddOnMetadata = function() return "1.0.15" end }
_G.C_Spell = { GetSpellTexture = function(id) return "icon:" .. tostring(id) end }
_G.InCombatLockdown = function() return false end
_G.GetTime = function() return 0 end

-- The macro pages edit stored text through the shared helpers, so the real
-- Core/WeaveMacro.lua is loaded rather than stubbed.
dofile("Core/WeaveMacro.lua")
dofile("Modules/Onboarding.lua")

-- The real defaults this feature cares about (mirrors Config/Defaults.lua).
local DEFAULTS = {
  locked = true,
  hudEnabled = true,
  hudMode = "classic", rotationMode = "bars", medallionEnabled = false,
  reactShowAspectIcon = false, reactShowMarkIcon = false,
  showRotation = true, weaveNotationEnabled = false, weaveCoachSoundsEnabled = false,
  showRangeFinder = true, shotBarsShowRaptor = true,
  showWarnings = true, warnAspectEnabled = true, warnTargetFrenzyEnabled = true,
  warnManaEnabled = true,
  misdirectEnabled = false, mdCastEnabled = false,
  buffTrackerEnabled = false, debuffTrackerEnabled = false,
  shoppingEnabled = true, mailboxEnabled = true,
  petTrainerHelperEnabled = true, repairWarnEnabled = true,
  weaveBindMacroDown = MACRO_DOWN, weaveBindMacroUp = MACRO_UP,
  tonkAutoCancel = true, tonkDialEnabled = true,
}

local function freshProfile()
  local p = {}
  for k, v in pairs(DEFAULTS) do p[k] = v end
  Nock.db.profile = p
  Nock.db.char = {}
  Nock.Defaults.profile = DEFAULTS
  sentMessages = {}
  sentArgs = {}
  return p
end

local function lastLockPayload()
  for i = #sentArgs, 1, -1 do
    if sentArgs[i].msg == "NOCK_LOCK_CHANGED" then return sentArgs[i].payload end
  end
  return nil
end

local function pageByKey(key)
  for i, page in ipairs(O.Pages) do
    if page.key == key then return page, i end
  end
end

--------------------------------------------------------------------------------
-- 1. Page script shape
--------------------------------------------------------------------------------
ok(#O.Pages == 12, "twelve pages in the script")
ok(O.Pages[1].key == "welcome" and O.Pages[#O.Pages].key == "finish", "welcome first, finish last")
for _, page in ipairs(O.Pages) do
  local kind = page.kind
  ok(kind == "checks" or kind == "cards" or kind == "toggles" or kind == "finish",
     "page " .. page.key .. " has a known kind")
  ok(page.title and page.blurb, "page " .. page.key .. " has title + blurb")
  if kind == "cards" then
    ok(#page.options >= 2, page.key .. ": at least two cards")
    for _, opt in ipairs(page.options) do
      ok(opt.apply and opt.isSelected and opt.label and opt.desc,
         page.key .. "/" .. opt.value .. ": complete card")
    end
  elseif kind == "toggles" then
    for _, opt in ipairs(page.options) do
      -- Two shapes: a plain profile `key`, or a derived row that names an `id`
      -- and supplies its own reader/writer (the weave extras live inside the
      -- macro text, not in a boolean key).
      ok((opt.key or opt.id) and opt.label and opt.desc, page.key .. ": complete toggle")
      if opt.key then
        ok(DEFAULTS[opt.key] ~= nil, page.key .. "/" .. opt.key .. ": key exists in defaults")
        ok(not opt.isOn and not opt.setOn, page.key .. "/" .. opt.key .. ": a keyed row needs no accessors")
      else
        ok(type(opt.isOn) == "function" and type(opt.setOn) == "function",
           page.key .. "/" .. tostring(opt.id) .. ": derived row carries both accessors")
      end
    end
  end
end

-- No slash commands anywhere in user-facing copy (they were removed on purpose).
for _, page in ipairs(O.Pages) do
  local text = (page.title or "") .. (page.blurb or "") .. (page.eyebrow or "") .. (page.footnote or "")
  ok(not text:find("/nock"), "page " .. page.key .. " mentions no slash command")
  for _, opt in ipairs(page.options or {}) do
    ok(not ((opt.label or "") .. (opt.desc or "")):find("/nock"),
       page.key .. ": option copy mentions no slash command")
  end
end

--------------------------------------------------------------------------------
-- 2. Cards apply and reflect selection
--------------------------------------------------------------------------------
local p = freshProfile()
local hud = pageByKey("hudstyle")
ok(#hud.options == 4, "four HUD choices: classic, react, fluffy, none")
ok(hud.options[3].value == "fluffy", "the third is FluffyHUD")
ok(hud.options[4].value == "none", "the fourth is No HUD")
ok(hud.options[1].isSelected(p), "classic selected by default")
ok(not hud.options[2].isSelected(p), "react not selected by default")
ok(not hud.options[3].isSelected(p), "fluffy not selected by default")
ok(not hud.options[4].isSelected(p), "no-HUD not selected by default")
O:SelectCard(hud, hud.options[2])
ok(p.hudMode == "react", "picking React writes hudMode")
ok(hud.options[2].isSelected(p) and not hud.options[1].isSelected(p), "selection follows the profile")
ok(sentMessages[#sentMessages] == "NOCK_VISUALS_CHANGED", "a card selection broadcasts")

-- No HUD turns the frame off and takes the free-floating medallion with it.
p = freshProfile()
p.medallionEnabled = true
O:SelectCard(hud, hud.options[4])
ok(p.hudEnabled == false, "No HUD clears hudEnabled")
ok(p.medallionEnabled == false, "No HUD also drops the medallion")
ok(hud.options[4].isSelected(p), "No HUD reads as selected")
ok(not hud.options[1].isSelected(p) and not hud.options[2].isSelected(p)
   and not hud.options[3].isSelected(p),
   "No HUD deselects all three HUD looks")
-- Reversible: picking a look back turns the HUD on again.
O:SelectCard(hud, hud.options[1])
ok(p.hudEnabled == true and p.hudMode == "classic", "Classic switches the HUD back on")
O:SelectCard(hud, hud.options[4])
O:SelectCard(hud, hud.options[2])
ok(p.hudEnabled == true and p.hudMode == "react", "React switches the HUD back on")

-- Rotation cards are mutually exclusive across two different keys.
p = freshProfile()
local rot = pageByKey("rotation")
ok(rot.options[1].isSelected(p), "shot bars selected by default")
O:SelectCard(rot, rot.options[3])
ok(p.medallionEnabled == true, "medallion card enables the medallion")
ok(rot.options[3].isSelected(p), "medallion now selected")
ok(not rot.options[1].isSelected(p) and not rot.options[2].isSelected(p),
   "medallion deselects the other two")
O:SelectCard(rot, rot.options[2])
ok(p.medallionEnabled == false and p.rotationMode == "helper", "helper card turns the medallion back off")

--------------------------------------------------------------------------------
-- 3. Toggles, dependencies
--------------------------------------------------------------------------------
p = freshProfile()
local trackers = pageByKey("trackers")
local mdRow, mdCastRow = trackers.options[1], trackers.options[2]
ok(mdCastRow.dependsOn == "misdirectEnabled", "click-to-MD depends on the tracker")
ok(O:IsOptionLocked(mdCastRow), "click-to-MD locked while the tracker is off")
O:ToggleOption(trackers, mdRow)
ok(p.misdirectEnabled == true, "toggling writes the key")
ok(not O:IsOptionLocked(mdCastRow), "click-to-MD unlocks with the tracker on")
O:ToggleOption(trackers, mdRow)
ok(p.misdirectEnabled == false, "toggling again clears it")

--------------------------------------------------------------------------------
-- 4. Recommended-answer seeding: first run only
--------------------------------------------------------------------------------
-- Weaver is the recommendation but NOT the shipped default, so a first run has
-- to seed it; that is the whole reason card seeding exists.
p = freshProfile()
O._firstRun = true
local play = pageByKey("playstyle")
ok(not play.options[1].isSelected(p), "weaver not selected before seeding")
O:SeedRecommendations(play)
ok(p.weaveNotationEnabled == true, "first run seeds the weaver card")
ok(play.options[1].isSelected(p), "weaver reads as selected after seeding")
ok(p.showRangeFinder == true and p.shotBarsShowRaptor == true, "weaver seeds its whole set")
-- The coach's sound cues are withdrawn from the GUI, so the wizard must not
-- arm them: a seeded-on cue would have no switch the user can reach.
ok(p.weaveCoachSoundsEnabled == false, "weaver leaves the retired sound cues alone")

-- MD pair is recommendOn and ships off.
p = freshProfile()
O._firstRun = true
O:SeedRecommendations(trackers)
ok(p.misdirectEnabled == true, "first run seeds the MD tracker on")
ok(p.mdCastEnabled == true, "first run seeds click-to-MD on")
ok(p.buffTrackerEnabled == false, "unmarked trackers stay off")

-- A re-run must never stomp a deliberate opt-out.
p = freshProfile()
O._firstRun = false
O:SeedRecommendations(trackers)
ok(p.misdirectEnabled == false, "re-run does not re-enable the MD tracker")
O:SeedRecommendations(play)
ok(p.weaveNotationEnabled == false, "re-run does not re-seed the weaver card")

-- Seeding a page whose recommendation is already the stored answer is a no-op.
p = freshProfile()
O._firstRun = true
sentMessages = {}
O:SeedRecommendations(hud)
ok(#sentMessages == 0, "no broadcast when the recommendation is already live")

--------------------------------------------------------------------------------
-- 3c. Steam Tonk page. Both its switches ship ON, so neither carries a
--     recommendation badge: recommendOn seeds a switch whose stored default is
--     off, and recommendOff badges a feature as NOT RECOMMENDED. Nothing here
--     is either — the guard and its dial are both simply on.
local tonkPage, tonkIndex = pageByKey("steamtonk")
ok(tonkPage, "steamtonk page exists")
ok(tonkPage and tonkPage.kind == "toggles", "steamtonk is a toggles page")
ok(tonkPage and #tonkPage.options == 2, "steamtonk offers both switches")
for _, opt in ipairs((tonkPage and tonkPage.options) or {}) do
  ok(not opt.recommendOn and not opt.recommendOff,
     "steamtonk/" .. tostring(opt.key) .. ": no recommendation badge")
end
ok(DEFAULTS.tonkAutoCancel == true,  "tonkAutoCancel ships on")
ok(DEFAULTS.tonkDialEnabled == true, "tonkDialEnabled ships on")
-- Sits between trackers and the out-of-combat helpers, so it disturbs none of
-- the navigation assertions below (which pin weavemacro to playstyle + 1).
ok(tonkIndex and tonkIndex == select(2, pageByKey("utility")) - 1,
   "steamtonk sits directly before the utility page")

-- 4a. Rotation page is Classic-only
--------------------------------------------------------------------------------
local rotPage, rotIndex = pageByKey("rotation")
p = freshProfile()
ok(O:IsPageVisible(rotPage), "classic sees the shot-display page")
p.hudMode = "react"
ok(not O:IsPageVisible(rotPage), "react skips the shot-display page")
p = freshProfile()
p.hudEnabled = false
ok(not O:IsPageVisible(rotPage), "no-HUD skips the shot-display page")

-- Navigation jumps straight from HUD style to playstyle in React.
local hudIndex = select(2, pageByKey("hudstyle"))
p = freshProfile()
O._page = hudIndex
ok(O:AdjacentPage(1) == rotIndex, "classic: next page is shot display")
p.hudMode = "react"
ok(O:AdjacentPage(1) == select(2, pageByKey("reactcorners")), "react: next page is corner icons")
-- And backwards from playstyle, so Back doesn't land on a hidden page.
O._page = select(2, pageByKey("playstyle"))
ok(O:AdjacentPage(-1) == select(2, pageByKey("reactcorners")),
   "react: back from playstyle returns to corner icons")

-- Step totals for each combination of the two conditional pages. Every count
-- gained one when the unconditionally-visible Steam Tonk page landed.
p = freshProfile()
O._page = 1
ok(select(2, O:Progress()) == 9, "classic turret: 9 steps")
p.weaveNotationEnabled = true
ok(select(2, O:Progress()) == 11, "classic weaver: 11 steps (macro shapes + extras)")
p.hudMode = "react"
ok(select(2, O:Progress()) == 11, "react weaver: 11 steps")
p.weaveNotationEnabled = false
ok(select(2, O:Progress()) == 9, "react turret: 9 steps")
p = freshProfile()
p.hudEnabled = false
O._page = 1
ok(select(2, O:Progress()) == 8, "no-HUD turret: 8 steps")

--------------------------------------------------------------------------------
-- 4b. Weave macro page: visibility and the three shapes
--------------------------------------------------------------------------------
local macro = pageByKey("weavemacro")
local macroIndex = select(2, pageByKey("weavemacro"))
ok(macro.visible ~= nil, "macro page is conditional")
ok(macroIndex == select(2, pageByKey("playstyle")) + 1, "macro page follows playstyle")

p = freshProfile()
ok(not O:IsPageVisible(macro), "turret never sees the macro page")
p.weaveNotationEnabled = true
ok(O:IsPageVisible(macro), "weaver sees the macro page")

-- Navigation skips it for a turret and includes it for a weaver.
p = freshProfile()
O._page = select(2, pageByKey("playstyle"))
ok(O:AdjacentPage(1) == select(2, pageByKey("warnings")), "turret: next page skips macros")
p.weaveNotationEnabled = true
ok(O:AdjacentPage(1) == macroIndex, "weaver: next page is macros")

-- Step counting reflects the pages this run actually visits.
p = freshProfile()
O._page = 1
local step, total = O:Progress()
ok(step == 1 and total == 9, "turret run is 9 steps")
p.weaveNotationEnabled = true
step, total = O:Progress()
ok(total == 11, "weaver run is 11 steps")

-- The last page is the last VISIBLE page, not the last in the script.
O._page = #O.Pages
ok(O:IsLastPage(), "finish page is last")
O._page = 1
ok(not O:IsLastPage(), "welcome page is not last")

local mDefault, mClever, mNatty = macro.options[1], macro.options[2], macro.options[3]
ok(mDefault.value == "default" and mClever.value == "clever" and mNatty.value == "natty",
   "macro cards are default / clever / natty")
-- ...and From Grounded (2026-08-27), a card only while Grounded holds a
-- weave bind or one was imported; Default over an import restores the
-- shipped macros.
local mGrounded = macro.options[4]
ok(mGrounded and mGrounded.value == "grounded" and mGrounded.visible and mGrounded.visible(p) == false,
   "the fourth card is From Grounded, hidden without Grounded")
p.weaveBindImported = { down = "/cast Raptor Strike\n/startattack", up = "/cast !Auto Shot", key = "SHIFT-F" }
p.weaveBindMacroDown, p.weaveBindMacroUp = "/cast Raptor Strike\n/startattack", "/cast !Auto Shot"
ok(mGrounded.visible(p) == true and mGrounded.isSelected(p) == true, "an import shows the card, selected")
O:SelectCard(macro, mDefault)
ok(p.weaveBindMacroDown == MACRO_DOWN and p.weaveBindMacroUp == MACRO_UP and not mGrounded.isSelected(p),
   "Default over the import restores the shipped macros")
p.weaveBindImported = nil
ok(mDefault.recommended == true, "default macro is the recommendation")

-- Fresh profile ships the default pair.
p = freshProfile()
ok(mDefault.isSelected(p), "shipped macros read as Default")
ok(not mClever.isSelected(p) and not mNatty.isSelected(p), "and as neither other shape")

-- Natty empties both bodies.
O:SelectCard(macro, mNatty)
ok(p.weaveBindMacroDown == "" and p.weaveBindMacroUp == "", "Natty clears both macros")
ok(mNatty.isSelected(p), "Natty reads as selected")

-- Default recovers from Natty (the empty bodies were Nock's doing).
O:SelectCard(macro, mDefault)
ok(p.weaveBindMacroDown == MACRO_DOWN and p.weaveBindMacroUp == MACRO_UP,
   "Default restores the shipped pair after Natty")

-- Clever adds the movement-pad line to BOTH bodies, once, at the TOP (after
-- the poke on the press body -- the author's battle-tested position).
local CLEVER_DOWN = SNOWBALL .. "\n" .. MOVEPAD .. "\n/use Raptor Strike\n" .. KC_LINE .. "\n/startattack"
O:SelectCard(macro, mClever)
ok(p.weaveBindMacroDown == CLEVER_DOWN, "Clever slots MovePad in after the poke")
ok(p.weaveBindMacroUp == MOVEPAD .. "\n" .. MACRO_UP, "Clever leads the release body with MovePad")
ok(mClever.isSelected(p), "Clever reads as selected")
O:SelectCard(macro, mClever)
ok(select(2, p.weaveBindMacroDown:gsub("MovePad", "")) == 1, "Clever twice does not duplicate the line")
ok(p.weaveBindMacroDown:find("^/use Snowball"), "Clever keeps the Snowball line first")

-- Default strips a MovePad line that Nock itself added.
O:SelectCard(macro, mDefault)
ok(p.weaveBindMacroDown == MACRO_DOWN and p.weaveBindMacroUp == MACRO_UP,
   "Default strips Nock's own MovePad addition")

-- A profile still carrying the pre-2026-09 stock pair: picking Default is the
-- upgrade path to the new shape, and the extras choices carry over.
p = freshProfile()
p.weaveBindMacroDown, p.weaveBindMacroUp = LEGACY_DOWN, LEGACY_UP
O:SelectCard(macro, mDefault)
ok(p.weaveBindMacroDown == MACRO_DOWN and p.weaveBindMacroUp == MACRO_UP,
   "Default upgrades the legacy stock pair")
p = freshProfile()
p.weaveBindMacroDown = "/use [noequipped:Shirt] Snowball\n/stopcasting\n/cast Raptor Strike\n/startattack\n" .. MOVEPAD
p.weaveBindMacroUp   = LEGACY_UP .. "\n/startattack [equipped:Shirt]"
O:SelectCard(macro, mDefault)
ok(p.weaveBindMacroDown == GATED, "the legacy upgrade keeps the gate (and drops the step-out)")
ok(p.weaveBindMacroUp == "/startattack [equipped:Shirt]\n" .. MACRO_UP, "...and rebuilds the release with its re-arm")
p = freshProfile()
p.weaveBindMacroDown = "/stopcasting\n/cast Raptor Strike\n/startattack"
O:SelectCard(macro, mDefault)
ok(p.weaveBindMacroDown == NOPOKE, "the legacy upgrade keeps a deliberately poke-less body poke-less")

-- A hand-written macro survives Default untouched. Mixed state on purpose: the
-- press body is the user's, the release body is empty (Nock's own doing), and
-- each half is judged separately.
p = freshProfile()
p.weaveBindMacroDown = "/cast Mongoose Bite"
p.weaveBindMacroUp   = ""
O:SelectCard(macro, mDefault)
ok(p.weaveBindMacroDown == "/cast Mongoose Bite", "Default leaves a hand-edited press body alone")
ok(p.weaveBindMacroUp == MACRO_UP, "Default still restores the body Nock had emptied")

-- Clever builds on a hand-written macro rather than replacing it.
p = freshProfile()
p.weaveBindMacroDown = "/cast Mongoose Bite"
O:SelectCard(macro, mClever)
ok(p.weaveBindMacroDown == MOVEPAD .. "\n/cast Mongoose Bite", "Clever extends a hand-edited macro (step-out first, no poke to follow)")

-- The page tells WeaveBind, not just the HUD.
p = freshProfile()
sentMessages = {}
O:SelectCard(macro, mNatty)
local sawWeaveBind = false
for _, m in ipairs(sentMessages) do if m == "NOCK_WEAVEBIND_CHANGED" then sawWeaveBind = true end end
ok(sawWeaveBind, "macro changes broadcast NOCK_WEAVEBIND_CHANGED")

-- 255 is the client's macro-body ceiling; Clever must not push past it.
ok(#CLEVER_DOWN <= 255, "Clever press body fits in a macro")
ok(#(MOVEPAD .. "\n" .. MACRO_UP) <= 255, "Clever release body fits in a macro")

--------------------------------------------------------------------------------
-- 4c. Weave macro extras: the Snowball poke and its garment gate
--------------------------------------------------------------------------------
-- These four switches do not own profile keys — they read and write the stored
-- macro TEXT, so a hand-edit in the options box shows up here and vice versa.
local extras, extrasIndex = pageByKey("weavemacroextras")
ok(extras, "extras page exists")
ok(extras and extras.kind == "toggles", "extras is a toggles page")
ok(extrasIndex == macroIndex + 1, "extras follows the macro shapes page")
ok(extras.message == "NOCK_WEAVEBIND_CHANGED", "extras page tells WeaveBind, not just the HUD")
ok(#extras.options == 4, "four switches: poke, gate, garment, direction")

p = freshProfile()
ok(not O:IsPageVisible(extras), "turret never sees the extras page")
p.weaveNotationEnabled = true
ok(O:IsPageVisible(extras), "weaver sees the extras page")
-- Natty emptied the press body: there is no macro left to add a poke to.
p.weaveBindMacroDown = ""
ok(not O:IsPageVisible(extras), "an empty press body skips the extras page")

p = freshProfile()
p.weaveNotationEnabled = true
local rPoke, rGate, rTabard, rWorn =
  extras.options[1], extras.options[2], extras.options[3], extras.options[4]

ok(O:IsOptionOn(rPoke), "the shipped press body reads as poke ON")
ok(not O:IsOptionOn(rGate), "and ungated")
ok(not O:IsOptionLocked(rPoke), "the poke row is never locked")
ok(not O:IsOptionLocked(rGate), "the gate row is live while a poke exists")
ok(O:IsOptionLocked(rTabard) and O:IsOptionLocked(rWorn),
   "garment and direction rows are locked while ungated")

-- Poke off / on, and the line comes back FIRST.
O:ToggleOption(extras, rPoke)
ok(p.weaveBindMacroDown == NOPOKE, "poke off strips only that line")
ok(not O:IsOptionOn(rPoke), "and the row follows the text")
ok(O:IsOptionLocked(rGate), "the gate row locks with no poke to gate")
O:ToggleOption(extras, rPoke)
ok(p.weaveBindMacroDown == MACRO_DOWN, "poke back on, ahead of everything else")

-- Gate on: shirt, fires while removed (the shipped convention, and the one the
-- Boss Garment autopilot arms by taking the shirt off).
O:ToggleOption(extras, rGate)
ok(p.weaveBindMacroDown == GATED, "gate defaults to shirt / fires while removed, on the poke and the press /startattack")
-- ...and the release body gets the inverse re-arm, FIRST (the last line must
-- stay !Auto Shot -- it wins the attack state), on the stock text only.
ok(p.weaveBindMacroUp == "/startattack [equipped:Shirt]\n" .. MACRO_UP, "the gate writes the inverse re-arm into the stock release body, first")
ok(O:IsOptionOn(rGate), "gate row reads on")
ok(not O:IsOptionOn(rTabard) and not O:IsOptionOn(rWorn), "shirt + removed read as the off position")
ok(not O:IsOptionLocked(rTabard) and not O:IsOptionLocked(rWorn),
   "garment and direction rows unlock with the gate on")

O:ToggleOption(extras, rTabard)
ok(p.weaveBindMacroDown == GATED:gsub("Shirt", "Tabard"),
   "tabard row swaps the garment on both gated lines, keeps the direction")
ok(p.weaveBindMacroUp == "/startattack [equipped:Tabard]\n" .. MACRO_UP, "...and the release re-arm follows the garment")
O:ToggleOption(extras, rWorn)
ok(p.weaveBindMacroDown == GATED:gsub("Shirt", "Tabard"):gsub("noequipped", "equipped"),
   "direction row flips to fires-while-worn, keeps the garment")
ok(p.weaveBindMacroUp == "/startattack [noequipped:Tabard]\n" .. MACRO_UP, "...and the release re-arm stays the other way round")
ok(O:IsOptionOn(rTabard) and O:IsOptionOn(rWorn), "both rows read back on")
-- The user's own bodies (custom text) follow a flip too -- a flip is their choice.
local myDown, myUp = p.weaveBindMacroDown, p.weaveBindMacroUp
p.weaveBindMacroDown = "/use [equipped:Tabard] Snowball\n/use Raptor Strike\n/startattack [equipped:Tabard]"
p.weaveBindMacroUp = "/startattack [noequipped:Tabard]\n/use [exists,harm,nodead] !Auto Shot"
O:ToggleOption(extras, rTabard)
ok(p.weaveBindMacroDown == "/use [equipped:Shirt] Snowball\n/use Raptor Strike\n/startattack [equipped:Shirt]"
   and p.weaveBindMacroUp == "/startattack [noequipped:Shirt]\n/use [exists,harm,nodead] !Auto Shot", "a custom pair: the garment swap rewrites every bracket in both bodies")
O:ToggleOption(extras, rWorn)
ok(p.weaveBindMacroDown == "/use [noequipped:Shirt] Snowball\n/use Raptor Strike\n/startattack [noequipped:Shirt]"
   and p.weaveBindMacroUp == "/startattack [equipped:Shirt]\n/use [exists,harm,nodead] !Auto Shot", "...and the direction flip inverts them line for line")
O:ToggleOption(extras, rWorn); O:ToggleOption(extras, rTabard)
p.weaveBindMacroDown, p.weaveBindMacroUp = myDown, myUp

O:ToggleOption(extras, rGate)
ok(p.weaveBindMacroDown == MACRO_DOWN, "gate off returns the plain poke")
ok(p.weaveBindMacroUp == MACRO_UP, "...and takes the re-arm off the release body")
p.weaveBindMacroUp = "/cast !Auto Shot\n/say mine"
O:ToggleOption(extras, rGate)
ok(p.weaveBindMacroUp == "/cast !Auto Shot\n/say mine", "a hand-written release body is never touched by the gate")
O:ToggleOption(extras, rGate)
p.weaveBindMacroUp = MACRO_UP
ok(O:IsOptionLocked(rTabard) and O:IsOptionLocked(rWorn), "and re-locks its two sub-rows")
-- The view draws locked rows greyed rather than hiding them, so their readers
-- run against an ungated body every render and must answer instead of erroring.
ok(not O:IsOptionOn(rTabard) and not O:IsOptionOn(rWorn),
   "locked garment and direction rows still read as off")

-- Dropping the poke drops its gate with it, so the page can never show a gate
-- the text no longer carries.
p.weaveBindMacroDown = GATED
O:ToggleOption(extras, rPoke)
ok(p.weaveBindMacroDown == NOPOKE, "poke off takes a gated line whole")
O:ToggleOption(extras, rPoke)
ok(not O:IsOptionOn(rGate), "the poke comes back ungated")

-- Secure button, not a frame: the page has to broadcast the macro change.
sentMessages = {}
O:ToggleOption(extras, rPoke)
sawWeaveBind = false
for _, m in ipairs(sentMessages) do if m == "NOCK_WEAVEBIND_CHANGED" then sawWeaveBind = true end end
ok(sawWeaveBind, "an extras toggle broadcasts NOCK_WEAVEBIND_CHANGED")

-- Seeding walks profile keys; a derived row has none and must be skipped rather
-- than writing nil into the macro text.
p = freshProfile()
p.weaveNotationEnabled = true
O._firstRun = true
O:SeedRecommendations(extras)
ok(p.weaveBindMacroDown == MACRO_DOWN, "seeding leaves the macro text alone")

-- The two macro pages must not fight: Default strips the step-out it added but
-- keeps whatever the extras page decided.
p = freshProfile()
p.weaveBindMacroDown = GATED .. "\n" .. MOVEPAD
O:SelectCard(macro, mDefault)
ok(p.weaveBindMacroDown == GATED, "Default keeps the gate and drops the step-out")
p = freshProfile()
p.weaveBindMacroDown = NOPOKE
O:SelectCard(macro, mDefault)
ok(p.weaveBindMacroDown == NOPOKE, "Default leaves a deliberately poke-less body poke-less")
-- ...and Clever still builds on top of an extras choice, the step-out sliding
-- in behind the gated poke -- the author's exact pasted press body.
p = freshProfile()
p.weaveBindMacroDown = GATED
O:SelectCard(macro, mClever)
local GATED_CLEVER = "/use [noequipped:Shirt] Snowball\n" .. MOVEPAD .. "\n/use Raptor Strike\n" .. KC_LINE .. "\n/startattack [noequipped:Shirt]"
ok(p.weaveBindMacroDown == GATED_CLEVER, "Clever extends a gated body, MovePad after the poke")

-- Everything at once still fits the client's 255-character macro body.
ok(#GATED_CLEVER <= 255, "fully loaded press body fits in a macro")

--------------------------------------------------------------------------------
-- 5. Recap reads the profile, not a memory of clicks
--------------------------------------------------------------------------------
local function recapValue(rows, key)
  for _, row in ipairs(rows) do
    if row[1] == key then return row[2] end
  end
  return nil
end

p = freshProfile()
local recap = O:BuildRecap()
ok(#recap == 5, "classic turret recap has five lines")
ok(recapValue(recap, "HUD style") == "Classic", "recap: classic HUD")
ok(recapValue(recap, "Shot display") == "Shot Bars", "recap: shot bars")
ok(recapValue(recap, "Playstyle") == "Stand and shoot", "recap: turret by default")
ok(recapValue(recap, "Warnings") == "aspect, tranq, mana", "recap: all three warnings")
ok(recapValue(recap, "Trackers") == "none", "recap: no trackers by default")
ok(recapValue(recap, "Weave macros") == nil, "turret recap has no macro row")

-- Classic weaver: gains the macro row, keeps the shot-display row.
p = freshProfile()
p.medallionEnabled = true; p.weaveNotationEnabled = true
p.showWarnings = false; p.misdirectEnabled = true; p.debuffTrackerEnabled = true
recap = O:BuildRecap()
ok(#recap == 6, "classic weaver recap gains the macro row")
ok(recapValue(recap, "Shot display") == "Medallion", "recap follows the medallion")
ok(recapValue(recap, "Playstyle") == "Melee weaver", "recap follows playstyle")
ok(recapValue(recap, "Weave macros") == "Default", "recap names the macro style")
ok(recapValue(recap, "Warnings") == "off", "recap reports warnings off")
ok(recapValue(recap, "Trackers") == "misdirection, debuffs", "recap lists enabled trackers")

-- React never answered the shot-display question, so the recap must not claim one.
p.hudMode = "react"
recap = O:BuildRecap()
ok(recapValue(recap, "HUD style") == "React", "recap follows hudMode")
ok(recapValue(recap, "Shot display") == nil, "react recap drops the shot-display row")
ok(recapValue(recap, "Weave macros") == "Default", "react weaver still reports macros")

-- No HUD reports as Off regardless of the stored look, and asks no shot question.
p = freshProfile()
p.hudEnabled = false
recap = O:BuildRecap()
ok(recapValue(recap, "HUD style") == "Off", "recap reports the HUD as Off")
ok(recapValue(recap, "Shot display") == nil, "no-HUD recap drops the shot-display row")
ok(recapValue(recap, "Warnings") == "aspect, tranq, mana", "no-HUD keeps warnings running")
p.hudMode = "react"
ok(recapValue(O:BuildRecap(), "HUD style") == "Off", "Off wins over the stored look")

p.weaveBindMacroDown = MACRO_DOWN .. "\n" .. MOVEPAD
ok(O:MacroStyleName() == "Clever (auto-backpedal)", "macro style detects Clever")
p.weaveBindMacroDown = ""; p.weaveBindMacroUp = ""
ok(O:MacroStyleName() == "Natty (write your own)", "macro style detects Natty")
p = freshProfile()
p.weaveNotationEnabled = true
ok(O:WantsWeaveKey() == true, "weaver gets the weave-key shortcut")
p.weaveNotationEnabled = false
ok(O:WantsWeaveKey() == false, "turret does not")

--------------------------------------------------------------------------------
-- 6. Teardown clears every demo flag and keeps the choices
--------------------------------------------------------------------------------
p = freshProfile()
Nock.state.demo = { hudForceShow = true, rotationSample = true, debuffTracker = true }
p.hudMode = "react"
O._page = 1
O:Teardown()
for k, v in pairs(Nock.state.demo) do ok(v == false, "teardown clears demo." .. k) end
ok(p.hudMode == "react", "teardown keeps applied choices")
ok(O._firstRun == false, "teardown ends the first-run pass")

--------------------------------------------------------------------------------
-- 7. Lock lifecycle: unlocked while the wizard is open, locked on every close
--------------------------------------------------------------------------------
-- Open unlocks everything so the user can drag frames into place.
p = freshProfile()
O:Open(1)
ok(fakeView.shown == true, "Open shows the view")
ok(p.locked == false, "Open unlocks all frames")
ok(lastLockPayload() == false, "Open broadcasts NOCK_LOCK_CHANGED(false)")

-- Teardown locks again — the finish/skip/X/Esc funnel.
O:Teardown()
ok(p.locked == true, "Teardown locks all frames")
ok(lastLockPayload() == true, "Teardown broadcasts NOCK_LOCK_CHANGED(true)")
for k, v in pairs(Nock.state.demo) do ok(v == false, "lock teardown still clears demo." .. k) end

-- The Esc/X path (view Hide → OnHide → Teardown) ends locked too.
p = freshProfile()
O:Open(1)
ok(p.locked == false, "reopen unlocks again")
p.hudMode = "react"   -- a choice made mid-wizard
fakeView:Hide()
ok(p.locked == true, "closing via the view locks all frames")
ok(p.hudMode == "react", "closing keeps the choices made while open")

-- Double teardown stays locked and does not error.
O:Teardown()
ok(p.locked == true, "double teardown stays locked")

--------------------------------------------------------------------------------
-- 8. Reload and combat resilience
--------------------------------------------------------------------------------
-- The pending-relock flag brackets the open wizard.
p = freshProfile()
O:Open(1)
ok(Nock.db.char.wizardLockPending == true, "Open flags the pending relock")
O:Teardown()
ok(Nock.db.char.wizardLockPending == false, "Teardown clears the pending relock")

-- A /reload or logout mid-wizard skips Teardown (no OnHide) and the first-run
-- stamp blocks reopening — the next login pass must restore the locked state.
p = freshProfile()
O:Open(1)
fakeView.shown = false          -- the UI died without running OnHide
ok(p.locked == false, "precondition: the reload left the profile unlocked")
O._autoOpenChecked = false
Nock.db.global.onboarding = { seenVersion = "seen" }
O:OnEnteringWorld()
ok(p.locked == true, "login safety net relocks after a reload mid-wizard")
ok(Nock.db.char.wizardLockPending == false, "safety net clears the pending flag")

-- /nock setup refuses to open in combat (the auto-open already deferred; the
-- manual entry points must too — Open unlocks frames and pokes secure panels).
p = freshProfile()
local realICL = _G.InCombatLockdown
_G.InCombatLockdown = function() return true end
O:Command()
ok(fakeView.shown == false, "Command refuses to open the wizard in combat")
ok(p.locked == true, "no unlock happened in combat")
_G.InCombatLockdown = realICL

--------------------------------------------------------------------------------
-- 9. React corner icons page
--------------------------------------------------------------------------------
local corners, cornersIndex = pageByKey("reactcorners")
ok(corners ~= nil, "the corner icons page exists")
ok(cornersIndex == select(2, pageByKey("hudstyle")) + 1,
   "corner icons page follows HUD style")
ok(corners.kind == "toggles", "corner icons page is a toggles page")

-- React-only: a classic or no-HUD run must never see it.
p = freshProfile()
ok(not O:IsPageVisible(corners), "classic skips the corner icons page")
p.hudEnabled = false
ok(not O:IsPageVisible(corners), "no-HUD skips the corner icons page")
p = freshProfile()
p.hudMode = "react"
ok(O:IsPageVisible(corners), "react sees the corner icons page")

-- Both switches ship off and are marked NOT RECOMMENDED, never recommendOn.
ok(#corners.options == 2, "two corner icon switches")
for _, opt in ipairs(corners.options) do
  ok(opt.recommendOff == true, corners.key .. "/" .. opt.key .. ": marked not recommended")
  ok(opt.recommendOn ~= true, corners.key .. "/" .. opt.key .. ": never recommended on")
  ok(DEFAULTS[opt.key] == false, corners.key .. "/" .. opt.key .. ": ships off")
end

-- Seeding must leave them alone even on a first run: recommendOff is not a
-- recommendation to enable.
p = freshProfile()
p.hudMode = "react"
O._firstRun = true
O:SeedRecommendations(corners)
ok(p.reactShowAspectIcon == false and p.reactShowMarkIcon == false,
   "first-run seeding leaves the corner icons off")

-- Toggling still writes through.
O:ToggleOption(corners, corners.options[1])
ok(p.reactShowAspectIcon == true, "toggling the aspect icon writes the key")

--------------------------------------------------------------------------------
-- 10. Recap reports corner icons in React only
--------------------------------------------------------------------------------
-- recapValue is the section-5 helper, already in scope.
p = freshProfile()
ok(recapValue(O:BuildRecap(), "Corner icons") == nil,
   "classic recap has no corner icons row")

p = freshProfile()
p.hudMode = "react"
ok(recapValue(O:BuildRecap(), "Corner icons") == "none",
   "react recap reports none when both are off")
p.reactShowAspectIcon = true
ok(recapValue(O:BuildRecap(), "Corner icons") == "aspect",
   "react recap names the aspect icon")
p.reactShowMarkIcon = true
ok(recapValue(O:BuildRecap(), "Corner icons") == "aspect, Hunter's Mark",
   "react recap names both")
ok(recapValue(O:BuildRecap(), "Shot display") == nil,
   "react recap still omits the classic shot display row")

--------------------------------------------------------------------------------
-- FluffyHUD card (the third look, 2026-08-31).
--------------------------------------------------------------------------------
local fluffyCard
for _, opt in ipairs(pageByKey("hudstyle").options) do
  if opt.value == "fluffy" then fluffyCard = opt end
end
ok(fluffyCard ~= nil, "hudstyle offers a FluffyHUD card")
p = freshProfile()
fluffyCard.apply(p)
ok(p.hudEnabled == true and p.hudMode == "fluffy", "fluffy card applies hudMode=fluffy")
ok(fluffyCard.isSelected(p) == true, "fluffy card selected after apply")
for _, opt in ipairs(pageByKey("hudstyle").options) do
  if opt ~= fluffyCard then
    ok(not opt.isSelected(p), "fluffy selected: card '" .. tostring(opt.value) .. "' is not")
  end
end
ok(recapValue(O:BuildRecap(), "HUD style") == "FluffyHUD", "recap names FluffyHUD")
ok(not O:IsPageVisible(pageByKey("rotation")), "fluffy skips the classic shot-display page")
ok(not O:IsPageVisible(pageByKey("reactcorners")), "fluffy skips the React corner-icons page")
ok(recapValue(O:BuildRecap(), "Shot display") == nil, "fluffy recap omits the shot display row")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
