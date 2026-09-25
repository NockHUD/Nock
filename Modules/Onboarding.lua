-- Modules/Onboarding.lua
-- First-run setup wizard engine: page lifecycle, guided reveal, applying choices, first-run gate.
-- The pages themselves come from a per-flavour page file. Opens itself once on
-- a fresh install and on demand via /nock setup. Every page drives the real
-- HUD, so the user configures Nock by watching it change rather than by
-- reading a settings tree. UI/Frame_Onboarding.lua renders this.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Onboarding = Nock:NewModule("Onboarding", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
-- The page files (Modules/OnboardingPagesTBC.lua, Forever/OnboardingPages.lua)
-- load after this one and fill Onboarding.Pages and BuildRecap.
Nock.Onboarding = Onboarding
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
  if _G.GetSpellTexture then
    local tex = _G.GetSpellTexture(id)
    if tex then return tex end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end
Onboarding.SpellIcon = spellIcon

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

-- Slider rows: `{ slider = true, key, label, min, max, step, default }`.
function Onboarding.ClampStep(v, min, max, step)
  v = tonumber(v) or min
  if v < min then v = min elseif v > max then v = max end
  if step and step > 0 then v = min + math.floor((v - min) / step + 0.5) * step end
  if v > max then v = max end
  return v
end

function Onboarding:OptionValue(option)
  local p = profile()
  local v = p and p[option.key]
  if type(v) == "number" then return v end
  return option.default or option.min
end

function Onboarding:SetOptionValue(page, option, v)
  local p = profile()
  if not p then return end
  v = Onboarding.ClampStep(v, option.min, option.max, option.step)
  if p[option.key] == v then return end
  p[option.key] = v
  self:Commit(page)
end

-- A key row (the aspect ring): `spec.set(p, bindingString)`; "" clears.
function Onboarding:ApplyKey(page, spec, s)
  local p = profile()
  if not (p and spec and spec.set) then return end
  spec.set(p, s or "")
  self:Commit(page)
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

-- Guided reveal: which frame keys the screen may show once page `index` is
-- current (the union of every visible page's `reveals` up to it) and which are
-- live (that page's own). "*" stands for every key. Pure, so the test can walk
-- a script of its own.
function Onboarding.RevealedSet(pages, index, isVisible)
  local revealed, live = {}, {}
  for i = 1, math.min(index, #pages) do
    local page = pages[i]
    if isVisible(page) and page.reveals then
      for _, key in ipairs(page.reveals) do
        revealed[key] = true
        if i == index then live[key] = true end
      end
    end
  end
  return revealed, live
end

-- Recompute the sets for the current page and tell every frame. Only the
-- guided wizard writes them; highlight mode leaves the plain lock in charge.
function Onboarding:ApplyReveals()
  local demo = Nock.state.demo
  if not demo.guided then return end
  demo.revealed, demo.live = Onboarding.RevealedSet(self.Pages, self._page or 1,
    function(page) return self:IsPageVisible(page) end)
  -- Frames re-read IsLockedFor from their ApplyLock, which listens to this.
  Nock:SendMessage("NOCK_LOCK_CHANGED", Nock.IsLocked())
end

-- Put the pad on the first frame this page introduces, in both modes.
function Onboarding:SelectPageFrame(page)
  local edit = Nock:GetModule("EditMode", true)
  if not (edit and edit.SelectByKey and page.reveals) then return end
  for _, key in ipairs(page.reveals) do
    if key ~= "*" and edit:SelectByKey(key) then return end
  end
end

function Onboarding:EnterPage(index)
  local page = self.Pages[index]
  if not page then return end
  self._page = index
  self:SeedRecommendations(page)
  self:ApplyReveals()
  if page.onEnter then page.onEnter(self) end
  self:SelectPageFrame(page)
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

-- `guided`: the spotlight run (frames revealed step by step, only the current
-- step's editable). Off = highlight mode: everything on screen, each page's
-- frames merely selected.
-- The start page's cards: scratch + one per bundled profile. Rebuilt on every
-- open, since the bundle list is static but Modules/ProfileShare.lua may load
-- after this file.
-- Bundled profiles the start page may offer on this client: an untagged
-- bundle is a TBC export (Yaxal), so Forever sees only `flavor = "forever"`.
function Onboarding.StartProfiles(list, forever)
  local want = forever and "forever" or "tbc"
  local out = {}
  for _, b in ipairs(list or {}) do
    if (b.flavor or "tbc") == want then out[#out + 1] = b end
  end
  return out
end

local function startProfiles()
  return Onboarding.StartProfiles(Nock.BundledProfiles, Nock.Flavor and Nock.Flavor.forever)
end

function Onboarding:HasStartProfiles()
  return #startProfiles() > 0
end

function Onboarding:RefreshStartCards()
  local page = self.Pages[1]
  if not (page and page.key == "start") then return end
  local cards = {
    {
      value = "scratch", label = "Start from scratch", recommended = true,
      desc  = "Keep your current profile and set every part up step by step.",
      icon  = function() return spellIcon(C.SpellID.STEADY_SHOT) end,
      isSelected = function() local ch = Nock.db.char; return (ch and ch.wizardStart or "scratch") == "scratch" end,
      apply = function() if Nock.db.char then Nock.db.char.wizardStart = "scratch" end end,
    },
  }
  for _, b in ipairs(startProfiles()) do
    cards[#cards + 1] = {
      value = b.key, label = "Start from " .. b.name .. "'s layout",
      desc  = (b.blurb or "") .. " Lands in a new profile named " .. b.name .. "; yours is kept.",
      icon  = function() return spellIcon(C.SpellID.RAPID_FIRE) end,
      isSelected = function() local ch = Nock.db.char; return ch ~= nil and ch.wizardStart == b.key end,
      apply = function()
        local share = Nock:GetModule("ProfileShare", true)
        if not (share and share.ApplyBundled) then return end
        -- The switch must not close us (Core/Core.lua OnProfileSwitched).
        Onboarding._profileSwitchByWizard = true
        local name = share:ApplyBundled(b.key)
        Onboarding._profileSwitchByWizard = false
        if not name then return end
        if Nock.db.char then
          Nock.db.char.wizardStart = b.key
          Nock.db.char.wizardLockPending = true
        end
        -- The switch landed on a fresh profile: unlock it for the run and
        -- recompute the reveal on it.
        Nock:SetLocked(false)
        Nock.state.demo.hudForceShow = true
        Onboarding:ApplyReveals()
      end,
    }
  end
  page.options = cards
end

function Onboarding:Open(index, guided)
  local view = Nock:GetModule("OnboardingView", true)
  if not view then return end
  self:RefreshStartCards()
  -- Pages that build their rows from live data (the Forever warnings catalog).
  for _, pg in ipairs(self.Pages) do
    if pg.refresh then pg.refresh(pg) end
  end
  -- Land on the first page this run shows (the start page hides itself
  -- when nothing is bundled).
  local first = index or 1
  while self.Pages[first] and not self:IsPageVisible(self.Pages[first]) do first = first + 1 end
  index = self.Pages[first] and first or 1

  -- Preview mode: keep the HUD on screen for the whole session even if this
  -- user normally hides it out of combat, or every page would demo an
  -- invisible HUD.
  Nock.state.demo.hudForceShow = true
  Nock.state.demo.guided = guided and true or false
  -- Unlock everything while the wizard is open so frames can be dragged into
  -- place; Teardown locks again on every close path. The char flag survives a
  -- /reload or logout that kills the wizard before Teardown runs — the next
  -- login pass (OnEnteringWorld) sees it and relocks.
  if profile() then
    if Nock.db.char then Nock.db.char.wizardLockPending = true end
    Nock:SetLocked(false)
  end
  self:EnterPage(index)
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
  if Nock.db.char then Nock.db.char.wizardStart = nil end
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
  self:Open(1, true)
end

function Onboarding:OnCombatEnded()
  self:UnregisterEvent("PLAYER_REGEN_ENABLED")
  self:ScheduleTimer("AutoOpen", 1)
end

-- /nock setup [guided]. Not a first run: recommendations are not re-seeded,
-- so an earlier "no thanks" survives. "guided" replays the spotlight run.
function Onboarding:Command(arg)
  -- The auto-open already defers past combat; the manual entry points must
  -- refuse too — Open unlocks frames (pokes the protected Misdirect panel)
  -- and drops the demo HUD over a live fight.
  if InCombatLockdown() then
    self:Print("The setup wizard can't open in combat — try again after the fight.")
    return
  end
  self._firstRun = false
  if self:IsOpen() then self:Close() end
  self:Open(1, arg == "guided")
end
