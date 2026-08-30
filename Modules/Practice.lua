-- Modules/Practice.lua
-- Practice mode glue: runs the pure PracticeEngine from the central tick and owns start/stop.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Practice = Nock:NewModule("Practice", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
local C = Nock.Constants

-- The pure files load before this one (Nock.toc), so bind them at load: the
-- panel's dropdown initializer runs inside ITS OnInitialize, before our
-- OnEnable, and used to hit a nil E there (UIDropDownMenu_Initialize on this
-- client calls the initializer immediately).
local E, G, M = Nock.PracticeEngine, Nock.PracticeGrader, Nock.PracticeModel
local P = Nock.PracticePlan
-- The drill ladder is pure too, and loads one line above us in the toc.
local Ladder = Nock.PracticeLadder

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id)
    if i and i.name then return i.name end
  end
  if GetSpellInfo then return (GetSpellInfo(id)) end
  return nil
end

local function spellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  if GetSpellTexture then return GetSpellTexture(id) end
  return nil
end

-- Item name from an id or a link, bare global first then the C_Item namespace
-- (BindCheck's pattern: either may be the one this client kept). nil when the
-- item simply isn't cached yet — every caller degrades to a numeric path.
local function itemName(idOrLink)
  if not idOrLink then return nil end
  if GetItemInfo then
    local n = GetItemInfo(idOrLink)
    if n then return n end
  end
  if C_Item and C_Item.GetItemInfo then
    local n = C_Item.GetItemInfo(idOrLink)
    if n then return n end
  end
  return nil
end

-- Sim spell -> state.player.casting info (reused tables, no per-tick alloc).
local SPELL_ID = { steady = C.SpellID.STEADY_SHOT, multi = C.SpellID.MULTI_SHOT, arcane = C.SpellID.ARCANE_SHOT }
local CAST_SYM = { steady = "s", multi = "m", arcane = "A" }
-- Resolved once in Start(): C_Spell.GetSpellInfo builds a fresh table per call,
-- so calling it from the per-frame Step() would allocate every tick.
local NAMES, ICONS = {}, {}
local AUTO_NAME, AUTO_ICON
local castInfo = { name = nil, spellId = nil, icon = nil, startTime = 0, endTime = 0, isChannel = false }
local autoInfo = { name = nil, spellId = nil, icon = nil, startTime = 0, endTime = 0, isChannel = false, auto = true }
local snap = {}
-- What Practice:PublishPlan hands the plan builder, reused every tick.
local src = {}

-- The stage's palette, from the profile into the one colour table every
-- practice view reads (Nock.PracticeTimeline.COLORS), IN PLACE -- the views
-- hold the inner tables by reference. Profile key -> COLORS key.
local COLOR_KEYS = {
  practiceColorAuto = "a", practiceColorSteady = "s", practiceColorMulti = "m", practiceColorArcane = "A",
  practiceColorRaptor = "r", practiceColorWhite = "w", practiceColorQS = "QS", practiceColorRF = "RF",
  practiceColorLust = "Lust", practiceColorDrums = "Drums", practiceColorDST = "DST", practiceColorPot = "Pot",
  practiceColorKC = "KC", practiceColorWindow = "good", practiceColorWarn = "warn", practiceColorBad = "bad",
}
Practice.COLOR_KEYS = COLOR_KEYS
function Practice:ApplyColors()
  local T = Nock.PracticeTimeline
  local prof = Nock.db and Nock.db.profile
  if not (T and T.COLORS and prof) then return end
  for pk, ck in pairs(COLOR_KEYS) do
    local c, dst = prof[pk], T.COLORS[ck]
    if c and dst then dst[1], dst[2], dst[3] = c[1] or dst[1], c[2] or dst[2], c[3] or dst[3] end
  end
end

function Practice:OnEnable()
  E, G, M = Nock.PracticeEngine, Nock.PracticeGrader, Nock.PracticeModel
  P = Nock.PracticePlan
  Ladder = Nock.PracticeLadder
  self:ApplyColors()
  -- The oracle's one table, created once and never replaced (views keep it by
  -- reference through Practice:Lookahead).
  if P and not Nock.state.sim.plan then Nock.state.sim.plan = P.New() end
  if not (E and G and M) then
    self._unavailable = true
    self:Print("Practice: engine files missing — practice mode disabled.")
  end
  -- The ladder rows follow every path that can change them: a pick, a fight
  -- boundary, a drill load (all NOCK_PRACTICE_CHANGED) and a finished fight.
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "PushLadder")
  self:RegisterMessage("NOCK_PRACTICE_FIGHT_DONE", "PushLadder")
  -- ...and on the window opening, so a lesson opened before any practice
  -- message ever fired shows the real ladder rather than the placeholder.
  self:RegisterMessage("NOCK_PRACTICE_LESSON_TOGGLE", "PushLadder")
  self:RegisterMessage("NOCK_PRACTICE_LADDER_DRILL", "OnLadderDrill")
  self:RegisterMessage("NOCK_COMBAT_CHANGED", "OnCombatChanged")
  self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
end

function Practice:IsActive()
  return Nock.state.sim.active
end

-- Engine config from the live character: base bow speed recovered from the
-- measured wind-up ratio (0.5 / ratio), static haste from the live swing.
function Practice:BuildConfig()
  local st = Nock.state
  local ratio = st.ranged.windupRatio
  local ws = (ratio and ratio > 0) and (0.5 / ratio) or 3.0
  local sd = st.ranged.swingDuration
  local mul = (sd and sd > 0) and (ws / sd) or 1.38
  local lat = profile("practiceLatencyMs", nil)
  if lat == nil then lat = st.network.latencyMs or 0 end
  local arcPts = 0
  if GetSpellBaseCooldown then
    local okc, ms = pcall(GetSpellBaseCooldown, C.SpellID.ARCANE_SHOT)
    if okc and ms and ms > 0 then arcPts = math.floor((6 - ms / 1000) / 0.2 + 0.5) end
  end
  local corr = st.ranged.castHasteCorr
  return {
    ws = ws, baseRangedMul = mul,
    latency = lat / 1000,
    queueWindow = profile("practiceQueueWindow", C.PRACTICE.QUEUE_WINDOW),
    gcd = C.GCD_BASE or 1.5,
    imprArcanePts = arcPts,
    -- Same residual Nock.RangedCastTime applies to the live cast bar, so a
    -- simulated Steady is exactly as long as the real one.
    castCorr = (corr and corr > 0) and corr or 1,
    multiCd = C.PRACTICE.MULTI_CD,
    arcaneCdBase = C.PRACTICE.ARCANE_CD_BASE,
    arcaneCdPerPt = C.PRACTICE.ARCANE_CD_PER_PT,
    armOnShot = true,
    -- Weave drill: the melee swing, the distance ladder and the footwork the
    -- engine models. Distances mirror RangeFinder's probes in yards.
    mws = st.melee.swingDuration or 3.7,
    baseMeleeMul = 1.0,
    meleeRange = C.PRACTICE.MELEE_RANGE, shootMin = C.PRACTICE.SHOOT_MIN,
    shootMax = C.PRACTICE.SHOOT_MAX, weaveRing = C.PRACTICE.WEAVE_RING,
    startDistance = profile("practiceStartDistance", C.PRACTICE.START_DISTANCE),
    raptorCd = C.PRACTICE.RAPTOR_CD,
    meleeRetryPulse = profile("practiceMeleeRetryPulse", C.PRACTICE.MELEE_RETRY_PULSE),
    rearmPulse = profile("practiceRearmPulse", nil) or C.RETRY_PULSE,
    rearmWindupAfterReady = profile("practiceRearmWindupAfterReady", true),
    releaseCost = Nock.ReleaseCost,
    footwork = profile("practiceFootwork", "move"),
    stepTime = profile("practiceStepTime", C.PRACTICE.STEP_TIME),
    dirSplit = Nock.RangeEngine and Nock.RangeEngine.DIR_SPLIT or 4.5,
    stillSpeed = Nock.RangeEngine and Nock.RangeEngine.PLAYER_MOVING or 0.5,
    legsNeeded = 0.7,
    -- A weave drill emits range/weave/melee events on top of the shot events,
    -- so the default 2000 cap would truncate a long fight's verdict list.
    eventCap = 6000,
    -- Procs and cooldowns (phase 5). The seed makes a fight repeatable: the
    -- same seed replays the same Quick Shots rolls and the same crits, so two
    -- attempts at a scenario differ only in what the player did.
    quickShots = profile("practiceQuickShots", true),
    seed = profile("practiceSeed", 1),
    cooldowns = { RF = C.PRACTICE.RF_CD, Spec = C.PRACTICE.SPEC_CD, T1 = C.PRACTICE.TRINKET_CD,
                  T2 = C.PRACTICE.TRINKET_CD, Drums = C.PRACTICE.DRUMS_CD,
                  Pot = C.PRACTICE.POT_CD, KC = C.PRACTICE.KC_CD },
    kcWindow = C.PRACTICE.KC_WINDOW,
    -- Your real crit chances drive the Kill Command window, so the drill opens
    -- it about as often as the fight would.
    critRanged = (GetRangedCritChance and (GetRangedCritChance() or 0) or 0) / 100,
    critMelee  = (GetCritChance and (GetCritChance() or 0) or 0) / 100,
  }
end

-- Arcane's modelled cooldown, the one number Step() has to back out of the
-- engine's readyAt to fake a startTime for state.cooldowns.
function Practice:ArcaneCd()
  return C.PRACTICE.ARCANE_CD_BASE - C.PRACTICE.ARCANE_CD_PER_PT * ((self.cfg and self.cfg.imprArcanePts) or 0)
end

-- Lower-cased spell/item name -> sim action, for parsing the weave key's own
-- macro bodies. The weave key names melee and the Snowball poke, which the
-- shot-key detection above never has to care about.
function Practice:WeaveNames()
  local names = {}
  local function add(id, action)
    local n = id and spellName(id)
    if n then names[n:lower()] = action end
  end
  add(C.SpellID.STEADY_SHOT, "steady")
  add(C.SpellID.MULTI_SHOT, "multi")
  add(C.SpellID.ARCANE_SHOT, "arcane")
  add(C.SpellID.AUTO_SHOT, "autoshot")
  add(C.SpellID.RAPTOR_STRIKE, "raptor")
  add(C.SpellID.KILL_COMMAND, "killcommand")
  -- A weave macro that also fires a cooldown (RF on the way out is a common
  -- one) should be graded for it rather than have the line land in `ignored`.
  add(C.SpellID.RAPID_FIRE, "rf")
  add(C.SpellID.BESTIAL_WRATH, "spec")
  local function addItem(id, action)
    local n = itemName(id)
    if n then names[n:lower()] = action end
  end
  addItem(C.DRUMS.BATTLE_ITEM, "drums")
  addItem(C.PRACTICE.HASTE_POT_ITEM, "pot")
  local snowball = C.WEAVE_BIND_SNOWBALL_LINE and C.WEAVE_BIND_SNOWBALL_LINE:match("/use%s+(.+)$")
  if snowball then names[snowball:lower()] = "snowball" end
  return names
end

----------------------------------------------------------------------------
-- Scenarios: the five built-ins live in PracticeEngine (E.SCENARIOS); the
-- user's own are parsed out of practiceScenarioText in the same DSL. Only the
-- dropdown and StartFight call any of this — never the tick.
----------------------------------------------------------------------------

function Practice:UserScenarios()
  return E.ParseScenario(profile("practiceScenarioText", ""))
end

-- The catalog's five groups, flattened in group order — the order the dropdown
-- lists and CurrentScenario resolves in.
function Practice:ScenarioNames()
  local out = {}
  local cat = self:Catalog()
  for _, g in ipairs(cat.groups) do
    for _, item in ipairs(g.items) do out[#out + 1] = item.name end
  end
  return out
end

-- The scenario the next fight runs, plus whatever the parser complained about.
-- An unknown name falls back to the first built-in rather than running unarmed:
-- the catalog's own first entry is a paper drill, and silently pinning someone's
-- haste because their scenario name went stale is worse than running Clean French.
function Practice:CurrentScenario()
  local want = profile("practiceScenario", "Clean French")
  local cat, errors = self:Catalog()
  for _, g in ipairs(cat.groups) do
    for _, item in ipairs(g.items) do
      if item.name == want then return item.sc, errors end
    end
  end
  return E and E.SCENARIOS[1], errors
end

-- The catalog ROW behind the current pick — `{ name, sub, color, sc }` — for the
-- panel's scenario card, which shows the sub-line and the swatch as well as the
-- name. CurrentScenario hands back only `sc`, which carries neither. Falls back
-- to the catalog's first row, matching CurrentScenario's own stale-name rule.
function Practice:CurrentCatalogItem()
  -- Resolved through CurrentScenario, NOT through the profile name: the two
  -- have different fallbacks (first built-in vs. first catalog row, which is a
  -- paper drill), and a stale practiceScenario name would otherwise make the
  -- card describe a drill the next fight does not run.
  local sc = self:CurrentScenario()
  local want = sc and sc.name or nil
  if not want then return nil end
  local cat = self:Catalog()
  for _, g in ipairs(cat.groups) do
    for _, item in ipairs(g.items) do
      if item.name == want then return item end
    end
  end
  return nil
end

-- True when the drill in force is a paper drill — a scenario that pins its own
-- rotation (sc.notation) and therefore its haste. Hand-popping a proc into one
-- would fight the pin, so the panel's palette locks its proc tiles on this.
-- Reads the RUNNING fight's scenario table while a fight is on (the dropdown
-- may have moved on since the pull), the current pick otherwise.
function Practice:PaperDrill()
  local sc = Nock.state.sim.fightOn and self._fightScenarioTable or nil
  if not sc then sc = (self:CurrentScenario()) end
  return (sc and sc.notation) and true or false
end

-- `keepDrill` is the ladder's own flag (LoadDrill). Every OTHER pick leaves the
-- ladder: the header must not keep claiming a drill the next fight is not
-- running, and the scorecard must not be graded against a drill's pass
-- condition because the player wandered off to a different scenario.
function Practice:SetScenario(name, keepDrill)
  if Nock.db and Nock.db.profile then Nock.db.profile.practiceScenario = name end
  if not keepDrill then self:LadderState().loaded = nil end
  -- A new pick ends the replay: the stage kept replaying the LAST fight's
  -- rows, so a loaded ladder rung showed no new icons until Start (user,
  -- 2026-08-26). Idle, the stage shows the picked paper's rows.
  if self._replay and not Nock.state.sim.fightOn then self:ReplayOff() end
  Nock:SendMessage("NOCK_PRACTICE_CHANGED")
end

-- Everything wrong with the scenario the next fight will run: the DSL parser's
-- own complaints plus an unresolvable lock=. Printed once per distinct set — a
-- bad line would otherwise print on every pull for as long as it sits in the box.
function Practice:ReportScenarioErrors(errors)
  if not errors or #errors == 0 then self._scenarioErrText = nil return end
  local text = table.concat(errors, " / ")
  if self._scenarioErrText == text then return end
  self._scenarioErrText = text
  self:Print("Practice: scenario problem — " .. text)
end

-- `lock=<notation>` pins the drill to a bracket. Rotations/Profiles.lua orders
-- its brackets high-eWS first with an EXCLUSIVE lower bound, so a name resolves
-- to `lo + 0.1` — inside the bracket by construction (ResolveByEWS answers with
-- the first entry whose lo is below the eWS, and every gap in that table is
-- wider than 0.1).
--
-- Inside the bracket is not the same as PLAYABLE, and two brackets proved it:
--
--   * The bottom one has no lower bound at all (`lo = 0`), so `lo + 0.1` pinned
--     the `2:5` drill at eWS 0.10 — a tenth-of-a-second weapon cycle, on which
--     that paper seats its Steady TWELVE measured cycles past its own release.
--     The grader reaches one cycle back, so every note was out of reach and
--     flawless play graded C. The open edge needs a floor.
--   * `1:1` resolved to 1.34, and a 1.34 s cycle is SHORTER than the 1.5 s GCD:
--     the paper's own period is the GCD, so it walks 0.16 s off the swing every
--     cycle and reds one in nine no matter how well it is played. It gets a pin
--     above the GCD instead — the same ruling the teaching papers are pinned by
--     (Core/PracticeModel.lua's M.TEACHING_EWS).
--
-- Both pins still sit inside their own bracket, so a locked notation resolves
-- back to itself. Pure; covered in Tests/practice_gates_test.lua (bracket
-- membership) and Tests/practice_model_test.lua (every pin schedules its own
-- paper with every note inside one measured cycle of its release).
local LOCK_MARGIN = 0.1
Practice.LOCK_PIN = { ["1:1"] = 1.60, ["2:5"] = 0.65 }
-- A paper drill's haste. YOUR OWN when it falls inside the rotation's
-- bracket (`live`, the character's measured eWS -- Practice._liveEws); the
-- bracket's floor plus a margin (or an explicit LOCK_PIN) only when it does
-- not, so a 1:1-geared hunter can still drill 5:5:1:1. The floor is where a
-- rotation clips hardest: 5:5:1:1 at its 1.93 floor delays 1.07 s of auto per
-- period, at the user's 2.17 about 0.2 s -- the WoWSims log at the same gear
-- shows ~14 clips of ~170 ms in 180 s (2026-08-26). Drilling every paper at
-- its floor taught clips no hunter at that gear would ever make.
function Practice.LockEWS(list, name, live)
  for i = 1, #(list or {}) do
    if list[i].name == name then
      local lo = list[i].lo
      local hi = (i > 1) and list[i - 1].lo or math.huge
      if live and live > 0 and live >= lo and live < hi then return live end
      return Practice.LOCK_PIN[name] or (lo + LOCK_MARGIN)
    end
  end
  return nil
end

----------------------------------------------------------------------------
-- The catalog. Five groups in a fixed order — every paper rotation from
-- Rotations/Profiles.lua as a drill of its own, then the scripted built-ins,
-- then the user's own DSL lines, then free play.
--
-- A PAPER drill is a scenario whose haste is pinned (lock= for the bracketed
-- rotations, ews= for the ones a bracket cannot state) with its procs HELD
-- rather than rolled: the point is to practise one named rotation for a whole
-- minute, so a random Quick Shots roll halfway through — which would rename the
-- rotation under the player's fingers — is exactly what it must not do. Hence
-- `qs = false` on every paper item and `notation = <the item's own name>`,
-- which pins the grader's per-window notation for the whole fight
-- (see NotationFor).
----------------------------------------------------------------------------

local TURRET_COLOR = { 0.6, 0.64, 0.7 }

-- Weave paper drills: which turret bracket to pin the haste to, and which procs
-- to hold up for the whole drill. The held list is ordered so the sub-line reads
-- the same way every time.
--
-- Which procs each drill holds follows Rotations/Profiles.lua's own ResolveWeave
-- branches, so a drill practises at the haste that would, live, produce that
-- drill's notation: WEAVE.RF = "6:9:1:1 3w" (Rapid Fire), WEAVE.MODERATE =
-- "2:2 1w" (one moderate source — imp Aspect / Quick Shots), WEAVE.RF_IAOTH_DRUMS
-- = "6:11:1:1 3w" (all three), WEAVE.FRENCH = "5:5:1:1 3w" (no haste effect).
-- Exported so Tests/practice_gates_test.lua can prove every pin in it schedules
-- the paper it names -- the check the turret brackets get through LockEWS.
Practice.WEAVE_DRILL = {
  ["5:5:1:1 3w"]  = { lock = "5:5:1:1", holds = {} },
  ["2:2 1w"]      = { lock = "5:5:1:1", holds = { "QS" } },
  ["6:9:1:1 3w"]  = { lock = "5:5:1:1", holds = { "RF" } },
  ["6:11:1:1 3w"] = { lock = "5:5:1:1", holds = { "RF", "QS", "Drums" } },
  -- Max haste sits below the fastest bracket's lower bound, so there is no
  -- notation to lock to — state the eWS outright.
  ["3:7 2w"]      = { ews = 0.90, holds = {} },
}

-- A scripted scenario's DSL body, rebuilt from the parsed table (ParseScenario
-- keeps no source text). Proc keys lowercase back to their own tokens.
local function scriptSub(sc)
  local lenLabel = sc.len and ("%g s"):format(sc.len) or "no auto-stop"
  local ev = sc.events
  if not ev or #ev == 0 then return ("no procs · %s"):format(lenLabel) end
  local parts = {}
  for i = 1, #ev do parts[i] = ("%s@%g"):format(tostring(ev[i].proc):lower(), ev[i].t) end
  return ("%s · %s"):format(table.concat(parts, " "), lenLabel)
end

local FREE_PLAY_NAME = "Free play"

-- Pure: no `self`, no Nock globals. `lockEws(name) -> ews|nil` and
-- `colorFor(name) -> {r,g,b}|nil` are the two lookups the glue closes over, so
-- the builder can be exercised against stub tables in Tests/.
--
-- Returns `catalog, errors`. The errors are the ones only the BUILDER can see —
-- a user scenario whose name a built-in already owns, a weave notation with no
-- drill mapping — and the glue merges them into the parser's own list so
-- ReportScenarioErrors prints them once per distinct set like any other.
-- `reserved` is an array of names the catalog does not build here but still
-- owns — today the drill ladder's own scripted scenarios, which are appended as
-- a group AFTER the user's. Without them in `taken`, a user line with the same
-- name wins CurrentScenario's walk and silently drills something else; with
-- them, it reports through ReportScenarioErrors like any other clash.
function Practice.BuildCatalog(turretList, weaveNames, builtins, user, lockEws, colorFor, reserved)
  lockEws  = lockEws  or function() return nil end
  colorFor = colorFor or function() return nil end
  local errors = {}

  -- Every name the catalog itself owns. A user scenario may not reuse one:
  -- CurrentScenario walks the groups in order and would return the built-in,
  -- silently drilling something other than the line the user wrote, while the
  -- dropdown listed the name twice with no way to tell the rows apart.
  local taken = { [FREE_PLAY_NAME] = true }
  for i = 1, #(reserved or {}) do taken[reserved[i]] = true end

  -- Each item gets its OWN colour table: these are handed to render sites that
  -- may write into them (a fade, a highlight), and a shared default would then
  -- recolour every other colourless item in the catalog.
  local function itemColor(name)
    return colorFor(name) or { TURRET_COLOR[1], TURRET_COLOR[2], TURRET_COLOR[3] }
  end

  local turret = {}
  for i = 1, #(turretList or {}) do
    local name = turretList[i].name
    local ews = lockEws(name)
    taken[name] = true
    turret[i] = {
      name = name,
      sub = ews and ("paper drill · eWS %.2f"):format(ews) or "paper drill",
      color = itemColor(name),
      -- Ruling 2026-08-24: a paper drill has no script to run out, so it never
      -- ends itself. Only a script with an explicit len= stops on its own.
      sc = { name = name, events = {}, len = nil, qs = false, lock = name, notation = name },
    }
  end

  local weave = {}
  for i = 1, #(weaveNames or {}) do
    local name = weaveNames[i]
    local d = Practice.WEAVE_DRILL[name]
    -- No mapping means no lock= and no ews=, i.e. a "paper" drill that would
    -- actually run at live haste while claiming a fixed notation — the one
    -- thing a paper drill must never do. Drop it and say so.
    if not d then
      errors[#errors + 1] = ("no drill mapping for weave notation '%s'"):format(tostring(name))
    else
      local sc = { name = name, events = {}, len = nil, qs = false, notation = name,
                   lock = d.lock, ews = d.ews }
      local held
      if #d.holds > 0 then
        sc.hold = {}
        for _, proc in ipairs(d.holds) do sc.hold[proc] = true end
        held = "held: " .. table.concat(d.holds, " + ")
      end
      taken[name] = true
      weave[#weave + 1] = {
        name = name,
        sub = ("paper weave drill · %s"):format(held or "base"),
        color = itemColor(name),
        sc = sc,
      }
    end
  end

  local scripts = {}
  for i = 1, #(builtins or {}) do
    local sc = builtins[i]
    taken[sc.name] = true
    scripts[i] = { name = sc.name, sub = scriptSub(sc), sc = sc }
  end

  local mine = {}
  for i = 1, #(user or {}) do
    local sc = user[i]
    if taken[sc.name] then
      errors[#errors + 1] = ("scenario name '%s' is taken by a built-in or drill; rename it"):format(tostring(sc.name))
    else
      mine[#mine + 1] = { name = sc.name, sub = scriptSub(sc), sc = sc }
    end
  end

  local free = { {
    name = FREE_PLAY_NAME,
    sub = "no script · no auto-stop · pop anything from the palette",
    sc = { name = FREE_PLAY_NAME, events = {}, len = nil, qs = true, free = true },
  } }

  return { groups = {
    { key = "turret",  title = "Paper drills — turret", items = turret },
    { key = "weave",   title = "Paper drills — weave",  items = weave },
    { key = "scripts", title = "Scripts",               items = scripts },
    { key = "mine",    title = "Mine",                  items = mine },
    { key = "free",    title = "Free play",             items = free },
  } }, errors
end

-- The built catalog, cached until the user edits their scenario box. Called by
-- the panel and the options dropdown when they open, and by CurrentScenario on
-- a pull — never from the tick, so the closures below cost nothing per frame.
function Practice:Catalog()
  local text = profile("practiceScenarioText", "")
  -- The ladder's own scripted drills join the catalog as a sixth group, so the
  -- picker lists them and CurrentScenario/PaperDrill/the palette resolve them
  -- down exactly the same path as any other scenario. Their key is part of the
  -- cache key: a rebuilt line has to invalidate the catalog with it.
  local ladderRows, ladderKey = self:LadderRows()
  if self._catalog and self._catalogText == text and self._catalogLadderKey == ladderKey then
    return self._catalog, self._catalogErrors
  end
  local user, errors = self:UserScenarios()
  local P = Nock.Profiles
  local list = (P and P.list) or {}
  -- The ladder rows are built before the catalog, so their names can be
  -- RESERVED in it: a user line called "Rhythm changes" must be reported, not
  -- silently preferred over the drill it shadows.
  local reserved = self._ladderNames
  if not reserved then reserved = {}; self._ladderNames = reserved end
  for i = #reserved, 1, -1 do reserved[i] = nil end
  for i = 1, #ladderRows do reserved[i] = ladderRows[i].name end
  local cat, catErrors = Practice.BuildCatalog(
    list,
    (P and P.weaveList) or {},
    (E and E.SCENARIOS) or {},
    user,
    function(name) return Practice.LockEWS(list, name, self._liveEws) end,
    function(name)
      local r, g, b = P and P:DisplayColor(name)
      if r then return { r, g, b } end
      return nil
    end,
    reserved)
  -- The builder's complaints join the parser's, so a shadowed user scenario
  -- reaches ReportScenarioErrors down the same path as a malformed line.
  errors = errors or {}
  for i = 1, #catErrors do errors[#errors + 1] = catErrors[i] end
  -- Second to last, so Free play stays the grid's last card: it is the "no
  -- script at all" end of the catalog and reads as the end of it.
  if #ladderRows > 0 then
    table.insert(cat.groups, #cat.groups, { key = "ladder", title = "Drill ladder", items = ladderRows })
  end
  self._catalog, self._catalogText, self._catalogErrors = cat, text, errors
  self._catalogLadderKey = ladderKey
  return cat, errors
end

----------------------------------------------------------------------------
-- The drill ladder (Modules/PracticeLadder.lua is the pure half). Progress
-- lives in the profile; the lesson window's side panel draws it; the header
-- shows the loaded drill's name.
----------------------------------------------------------------------------

-- The character's own notations, which is what "the profile's turret/weave
-- notation" means to a drill. Read from the LIVE swing, remembered while the
-- sim is not running: a paper drill edits cfg.baseRangedMul to its own pin, and
-- a ladder whose rungs followed the last drill you loaded would be circular.
--
-- `state.ranged.swingDuration` is only the live swing while the sim does NOT
-- own it, and the sim's own exits are what guarantee that (ReleaseGrid). The
-- sample taken at Start() is the belt to that braces: practice ON is the last
-- moment the grid is certainly the character's, so the ladder has an honest eWS
-- even if some future exit path forgets to hand the grid back. It was not
-- honest once: real combat took practice down without republishing, the beat
-- drill's pinned 1.34 s cycle stayed in state, and the ladder read it as this
-- character's swing -- which resolves to 1:1, so the "Add Multi & Arcane" rung
-- silently loaded the 1:1 paper and the lesson explained THAT.
local NO_PROCS = {}
local ladderCtx = {}
function Practice:LadderContext()
  local st = Nock.state
  if not st.sim.active then
    local sd = st.ranged.swingDuration
    if sd and sd > 0 then self._liveEws = sd end
  end
  local ews = self._liveEws or 2.174   -- the P1 BM baseline, until the swing is measured
  local P = Nock.Profiles
  ladderCtx.turret = (P and P:ResolveByEWS(ews)) or "1:1"
  -- No procs, no melee haste: the weave rotation you hold with nothing up is
  -- where the ladder starts, and it is the one the weave paper drill pins.
  ladderCtx.weave = (P and P:ResolveWeave(ews, NO_PROCS, 0)) or "5:5:1:1 3w"
  return ladderCtx
end

-- The catalog rows the ladder contributes: one per drill whose scenario the
-- catalog does not already own — the six TEACHING papers (Round 5b) and the
-- one scripted drill (`rhythm`). A scripted row is built through the scenario
-- DSL like the user's own lines, so hold=/len=/qs= mean the same thing here.
--
-- A teaching row cannot go through the DSL: E.ParseScenario has no `notation=`
-- token, and the whole point of a teaching paper is that it pins a rotation
-- string the bracket table will never resolve to. It is built directly instead,
-- in exactly the shape BuildCatalog gives a paper drill — pinned haste, procs
-- held, no auto-stop — with the haste taken from M.TEACHING_EWS, so the pin
-- lives with the string it was written for and cannot drift from it.
--
-- Returns the rows and a cache key over what they were built from.
local LADDER_COLOR = { 0.85, 0.64, 0.25 }
local ladderKeyParts, ladderSpecs = {}, {}
function Practice:LadderRows()
  if not (Ladder and E) then
    local rows = self._ladderRows
    if not rows then rows = {}; self._ladderRows = rows end
    return rows, ""
  end
  local ctx = self:LadderContext()
  local n = 0
  for i = 1, #Ladder.DRILLS do
    local spec = Ladder.DRILLS[i].build(ctx)
    if spec and spec.line then
      n = n + 1
      ladderSpecs[n], ladderKeyParts[n] = spec, spec.line
    elseif spec and spec.paper then
      n = n + 1
      local nota = spec.paper.notation
      ladderSpecs[n] = spec
      ladderKeyParts[n] = ("paper:%s@%s"):format(tostring(nota), tostring(M and M.TEACHING_EWS[nota]))
    end
  end
  local key = table.concat(ladderKeyParts, "\n", 1, n)
  if self._ladderRows and self._ladderRowsKey == key then return self._ladderRows, key end
  local rows = {}
  for i = 1, n do
    local spec = ladderSpecs[i]
    local row
    if spec.paper then
      local nota = spec.paper.notation
      local ews = M and M.TEACHING_EWS[nota]
      -- No pin means no row: a teaching paper running at live haste would
      -- claim a rotation the swing does not support, which is the one thing a
      -- paper drill may never do (BuildCatalog's own rule for weave drills).
      if ews and ews > 0 and M.STRINGS[nota] then
        row = {
          name = nota,
          sub = ("teaching drill \194\183 eWS %.2f"):format(ews),
          color = { LADDER_COLOR[1], LADDER_COLOR[2], LADDER_COLOR[3] },
          sc = { name = nota, events = {}, len = nil, qs = false,
                 notation = nota, ews = ews },
        }
      end
    else
      local list = E.ParseScenario(spec.line)
      local sc = list and list[1]
      if sc then
        row = {
          name = sc.name,
          sub = ("drill ladder \194\183 %s"):format(scriptSub(sc)),
          -- Its own table: the picker's render sites are free to write into it.
          color = { LADDER_COLOR[1], LADDER_COLOR[2], LADDER_COLOR[3] },
          sc = sc,
        }
      end
    end
    if row then rows[#rows + 1] = row end
  end
  self._ladderRows, self._ladderRowsKey = rows, key
  return rows, key
end

-- Progress, off the profile: `{ done = {}, current = <id>, loaded = <id|nil> }`.
-- `loaded` is the drill the pick currently belongs to, and it is PERSISTED for
-- the same reason `current` is — a /reload used to leave the ladder pointing at
-- a drill the header no longer named and, worse, stop counting its passes while
-- the player kept running it.
--
-- The fallback table keeps a session's worth of progress when there is no db at
-- all (tests, a very early call) rather than handing back a fresh one every
-- time and never advancing.
function Practice:LadderState()
  local db = Nock.db and Nock.db.profile
  local st = db and db.practiceLadder
  if not st then
    st = self._ladderFallback
    if not st then st = {}; self._ladderFallback = st end
  end
  if st.done == nil then st.done = {} end
  if st.current == nil then st.current = (Ladder and Ladder.FIRST) or "beat" end
  -- An id no drill answers to — an older SavedVariables, a renamed rung —
  -- would park the ladder on nothing at all: no `cur` row, and `Drill this`
  -- with nothing to load. Migrate carries the six-rung ladder's own ids across
  -- to the eleven-rung one (once, behind a version stamp) and drops whatever is
  -- left over; it is a no-op on a state already in the current schema.
  if Ladder then
    if Ladder.Migrate then Ladder.Migrate(st) end
    if not Ladder.ById(st.current) then st.current = Ladder.FIRST end
    if st.loaded ~= nil and not Ladder.ById(st.loaded) then st.loaded = nil end
  end
  return st
end

function Practice:LadderItems()
  if not Ladder then return nil end
  local items = Ladder.Items(self:LadderState())
  -- The sub-lines say what each rung IS: a teaching paper carries its pinned
  -- haste, the character's own rotation its notation -- "Add Arcane" and
  -- "Full turret" read as the same rung otherwise (user, 2026-08-26).
  if items then
    local ctx = self:LadderContext()
    for i = 1, #items do
      local it = items[i]
      local d = Ladder.ById(it.id)
      local spec = d and d.build and d.build(ctx)
      if spec and spec.paper and M and M.TEACHING_EWS[spec.paper.notation] then
        it.sub = ("eWS %.2f \194\183 %s"):format(M.TEACHING_EWS[spec.paper.notation], it.sub)
      elseif it.id == "french" and ctx and ctx.turret then
        it.sub = ("%s \194\183 your haste"):format(ctx.turret)
      elseif it.id == "weave-full" and ctx and ctx.weave then
        it.sub = ("%s \194\183 your haste"):format(ctx.weave)
      end
    end
  end
  return items
end

-- The drill the header names. During a fight it is the drill the fight OPENED
-- with — the pick may have moved on since — and nil when no drill is loaded,
-- which is what puts the scenario's own name back in the header.
function Practice:LadderDrillName()
  if not Ladder then return nil end
  local id = (Nock.state.sim.fightOn and self._fightLadderDrill) or self:LadderState().loaded
  local d = Ladder.ById(id)
  return d and d.name or nil
end

-- Push the ladder's rows at the lesson window. Message-driven, never from the
-- tick: one SetText run per rung on a pick or a fight boundary.
function Practice:PushLadder()
  if not Ladder then return end
  local v = Nock:GetModule("PracticeLessonView", true)
  if v and v.SetLadder then v:SetLadder(self:LadderItems()) end
end

-- `Drill this` (and /nock practice ladder's own load): pick the drill's
-- scenario the way the picker does — profile write + NOCK_PRACTICE_CHANGED —
-- and arm nothing. Starting a fight stays the player's press.
function Practice:LoadDrill(id)
  if not Ladder then return false end
  -- No id at all means "the one the ladder is pointing at"; a WRONG id is an
  -- error, not an excuse to load something else.
  local d
  if id == nil then d = Ladder.ById(self:LadderState().current) else d = Ladder.ById(id) end
  if not d then
    self:Print(("Practice: no such drill '%s'."):format(tostring(id)))
    return false
  end
  local spec = d.build(self:LadderContext())
  local name = spec and spec.scenario
  local found = false
  if name then
    local cat = self:Catalog()
    for _, g in ipairs(cat.groups) do
      for _, item in ipairs(g.items) do
        if item.name == name then found = true break end
      end
      if found then break end
    end
  end
  -- No row, no load: SetScenario would pin a name CurrentScenario falls out of,
  -- and the next fight would silently drill something else.
  if not found then
    self:Print(("Practice: drill %s wants scenario '%s', which the catalog does not have."):format(d.name, tostring(name)))
    return false
  end
  -- Before SetScenario: its NOCK_PRACTICE_CHANGED repaints the header, which
  -- reads `loaded` back out of the state.
  self:LadderState().loaded = d.id
  self:SetScenario(name, true)
  -- The cap is part of what was just loaded, so it is part of the line: a timed
  -- attempt the player is not told about reads as the drill stopping by itself.
  local len = spec and spec.len
  self:Print(("Practice: drill loaded — %s (%s) \194\183 %s \194\183 pass: %s."):format(
    d.name, name, len and ("%d s"):format(len) or "no auto-stop",
    d.pass and d.pass.text or "-"))
  return true
end

function Practice:OnLadderDrill(_, id)
  self:LoadDrill(id)
end

-- One finished fight against the RUNNING drill's pass condition. The rows are
-- repainted by PushLadder on NOCK_PRACTICE_CHANGED / FIGHT_DONE, which StopFight
-- sends right after this; the pass LINE is printed there too, after the score
-- the pass was earned with.
function Practice:EvaluateLadder(score)
  local id = self._fightLadderDrill
  if not (Ladder and id and score) then return end
  -- The ghost's fight is nobody's pass.
  if self._fightDemo then return end
  local state = self:LadderState()
  if not Ladder.Evaluate(state, score, id) then return end
  local d, nxt = Ladder.ById(id), Ladder.ById(state.current)
  self._ladderPassed = d
  self._ladderNext = (nxt ~= d) and nxt or nil
end

-- The auto-stop the LOADED drill asks for, in seconds, or nil when no drill is
-- loaded (or the drill is `free`). A teaching drill is a timed attempt (R6c):
-- the review has to land while the attempt is still in the fingers, and an
-- uncapped one ran until the player remembered to press Stop.
--
-- Applied to the ENGINE at the pull, never to the catalog row behind the drill:
-- `french` and `weave-full` load the character's own rotation, whose row the
-- picker shares, and a rotation picked by hand is meant to run until you stop
-- it.
function Practice:DrillLen()
  if not Ladder then return nil end
  local id = self:LadderState().loaded
  if not id then return nil end
  return Ladder.LenFor(id, self:LadderContext())
end

-- How long the RUNNING fight lasts, in seconds, or nil for an endless one — the
-- drill's cap if one is loaded, else the scenario's own len=. Stamped at the
-- pull (the pick may move under a running fight) and read by the header's fight
-- clock, which counts DOWN whenever this answers.
function Practice:FightLen()
  if not Nock.state.sim.fightOn then return nil end
  return self._fightLen
end

function Practice:ResetLadder()
  if not Ladder then return end
  Ladder.Reset(self:LadderState())
  self:PushLadder()
  self:Print(("Practice: drill ladder reset — back to %s."):format(Ladder.DRILLS[1].name))
end

-- state.cooldowns slot -> the engine's own cooldown key. The sim's `Pot` is the
-- live grid's Haste Potion slot ("Haste" in Constants.TRACKED_COOLDOWNS);
-- everything else keeps its name. File-level so Step() allocates nothing.
local SIM_CDS = { RF = "RF", Spec = "Spec", T1 = "T1", T2 = "T2",
                  Drums = "Drums", Haste = "Pot", KC = "KC" }

function Practice:Start()
  if self._unavailable then self:Print("Practice: not available (engine files missing).") return end
  if self:IsActive() then return end
  if InCombatLockdown() then
    self:Print("Practice: can't start in combat.")
    return
  end
  local st = Nock.state
  -- Resolve every name/icon the tick needs ONCE (see NAMES/ICONS above).
  for spell, id in pairs(SPELL_ID) do
    NAMES[spell], ICONS[spell] = spellName(id), spellIcon(id)
  end
  AUTO_NAME, AUTO_ICON = spellName(C.SpellID.AUTO_SHOT), spellIcon(C.SpellID.AUTO_SHOT)
  self.cfg = self:BuildConfig()
  self.engine = E.New(self.cfg)
  self.grader = nil
  self.lastScore = nil
  self.lastVerdicts = nil   -- or the tiles carry the previous drill's verdicts in
  -- The weave key's down/up bodies parsed into sim actions. Garment gates
  -- are STRIPPED, not resolved: a poke behind [noequipped:Shirt] is the
  -- user's boss-fight macro, and the drill should grade the boss-fight weave
  -- whatever shirt they practise in (user ruling: always assume Snowball).
  local WM = Nock.WeaveMacro
  local resolve = (WM and WM.WithoutGate) or function(s) return s end
  local wnames = self:WeaveNames()
  local p = Nock.db.profile
  self.weaveDown, self.weaveUp = {}, {}
  self.weaveUnknown = {}
  E.ParseMacro(resolve(p.weaveBindMacroDown or ""), wnames, self.weaveDown, self.weaveUnknown)
  E.ParseMacro(resolve(p.weaveBindMacroUp or ""),   wnames, self.weaveUp,   self.weaveUnknown)
  -- What the per-frame Step()/SampleFootwork path needs: resolved once here,
  -- never looked up in the tick (GetModule allocates nothing but is not free).
  self._rf = Nock:GetModule("RangeFinder", true)
  -- Reusable probe table for the finding ladder past 10yd (no per-tick alloc).
  self._ladder = self._ladder or {}
  -- The drill only sees your weave key through WeaveBind's button, so an
  -- unbound or disabled Weave Bind means the weave half of it never fires.
  if p.weaveBindEnabled ~= true or (p.weaveBindKey or "") == "" then
    self:Print("Practice: Weave Bind is off or has no key — the weave drill will not see your weave key (Utilities → Weave Bind).")
  end
  -- Dual-wielding (or no melee weapon at all): Raptor Strike has nothing to
  -- swing with, so the drill's melee half is make-believe. Say so once.
  if st.player.canWeave == false then
    self:Print("Practice: no two-hander equipped — the weave drill needs one (Raptor Strike / melee).")
  end
  st.sim.active = true
  st.sim.fightOn = false
  st.sim.pulled = false
  self:PublishPlan(st, GetTime())
  st.sim.lastVerdict = nil
  st.sim.meleeHaste = 0
  st.sim.notation = nil
  -- Virtual target for the turret drill: at range, shootable, not weavable.
  st.target.exists, st.target.alive, st.target.friendly = true, true, false
  st.target.rangeZone, st.target.inMelee, st.target.meleeProximity = "TOO_FAR", false, -0.12
  st.target.rangeState, st.target.rangeProg = "LONG", -1
  -- The live finding ladder's last bracket would otherwise sit on the drill's
  -- range bar, describing a real target that is no longer there.
  st.target.rangeBracket = nil
  st.player.rapidFire, st.player.quickShots, st.player.drums, st.player.inLust = false, false, false, false
  -- Cooldowns.lua stops scanning the sim-owned slots the moment sim.active goes
  -- up, so whatever the live grid last read would freeze there until the first
  -- fight ended. Start from zero, exactly as StopFight leaves them.
  for slot in pairs(SIM_CDS) do
    local s = st.cooldowns[slot]
    if s then s.startTime, s.duration, s.procActive = 0, 0, false end
  end
  st.demo.hudForceShow = true
  -- The last moment the swing grid in state is certainly the CHARACTER's: from
  -- the next tick on, Step() publishes the sim's. The ladder's rungs are "your
  -- turret/weave notation", so they are resolved off this (see LadderContext).
  local sd = st.ranged.swingDuration
  if sd and sd > 0 then self._liveEws = sd end
  if self.ApplyKeys then self:ApplyKeys() end   -- defined in Task 11
  Nock:SendMessage("NOCK_VISUALS_CHANGED")
  Nock:SendMessage("NOCK_PRACTICE_CHANGED")
  self:Print("Practice ON — press Start fight on the panel (or /nock practice start). /nock practice to leave.")
end

function Practice:Stop()
  if not self:IsActive() then return end
  self:Teardown()
end

-- The teardown itself, split out of Stop() because the combat auto-stop drops
-- `sim.active` on the spot: by the time PLAYER_REGEN_ENABLED arrives Stop()'s
-- IsActive guard would refuse, leaving the virtual target, the sim's swing grid
-- and a frozen cast behind for good. OnRegenEnabled calls this directly.
-- Hand the swing grid back to the live game. SwingTimer yields it while the sim
-- owns it (`RefreshSwingDurations` returns early on `sim.active`), so every path
-- that drops `sim.active` has to ask for a republish or the drill's own cycle
-- stays in `state.ranged.swingDuration` -- on the auto-shot bar, in Shot Bars'
-- layout, and in the ladder's idea of this character's eWS (LadderContext).
--
-- Must run AFTER `sim.active` goes false, and it is not optional on any exit:
-- the combat auto-stop skipped it, so a 1:1 drill's pinned 1.34 s cycle was
-- still the "live" swing when real combat started.
function Practice:ReleaseGrid()
  local r = Nock.state.ranged
  local sw = Nock:GetModule("SwingTimer", true)
  if sw and sw.RefreshSwingDurations then sw:RefreshSwingDurations() end
  -- SwingTimer only writes what `UnitRangedDamage("player")` gives it, and that
  -- is nil/0 with no ranged weapon equipped (and briefly at a cold login). The
  -- republish is then a no-op and the DRILL's pinned cycle is still sitting
  -- there -- the very thing this function exists to prevent. Fall back to the
  -- character's own BASE weapon speed, recovered from the wind-up ratio the
  -- same way ShotPredictor recovers it (`windup = AUTO_SHOT_CAST / hasteMul`,
  -- so `AUTO_SHOT_CAST / ratio` is the unhasted speed). It is the character's
  -- weapon rather than the drill's pin, and SwingTimer overwrites it the moment
  -- the client will answer -- UNIT_INVENTORY_CHANGED / UNIT_RANGED_ATTACK_POWER
  -- both land on RefreshSwingDurations.
  local live = UnitRangedDamage and UnitRangedDamage("player") or nil
  if not (live and live > 0) then
    local ratio = r.windupRatio
    local base = (ratio and ratio > 0) and ((C.AUTO_SHOT_CAST or 0.5) / ratio) or nil
    if base and base > 0 then r.swingDuration = base end
  end
  -- The swing IN FLIGHT goes too. Step()'s between-fights branch zeroes these,
  -- but the combat auto-stop is the one exit where Step never runs again: the
  -- drill's last shot was left on the live auto-shot bar, counting down a swing
  -- that belongs to nobody. swingRemaining must go with swingStart -- Core only
  -- re-derives it while swingStart > 0, so a stale remaining would pin.
  r.swingStart, r.swingRemaining = 0, 0
end

function Practice:Teardown()
  self:StopFight()
  -- A replay outlives practice otherwise: Step never runs again, so the frozen
  -- snapshot it published (swing, cast, cooldowns, proc flags, the plan) stays
  -- on the live HUD. Leave it first; the resets below then override the idle
  -- practice state ReplayOff itself writes (user, 2026-08-26).
  if self._replay then self:ReplayOff() end
  if self._demo then self:ToggleDemo() end
  self._freezeAt = nil
  local st = Nock.state
  if self.ClearKeys and not InCombatLockdown() then self:ClearKeys() end
  -- Override bindings can't be touched in combat; flag so OnRegenEnabled clears them once combat ends.
  if InCombatLockdown() then self._stoppedByCombat = true end
  st.sim.active = false
  st.sim.replaying = false   -- (AutoSwingLive counts a replay as combat)
  st.sim.paperSyms = nil     -- the drill's paper stops scoping the HUD's advice
  st.sim.rowSyms = nil
  st.sim.notation = nil      -- ...and its rotation NAME (Nock.HudNotation)
  st.player.casting, st.player.autoShotCast = nil, nil
  st.ranged.repeating = false
  st.target.exists, st.target.alive = false, false
  st.target.rangeZone, st.target.inMelee, st.target.meleeProximity = nil, false, 0
  st.target.rangeState, st.target.rangeProg, st.target.rangeBracket = nil, -1, nil
  -- Everything the weave drill published: the melee grid, the simulated hold
  -- the coach reads, and the Raptor cooldown override ShotPredictor/Rotation
  -- honour. Left behind they would outlive the drill on the live HUD.
  st.melee.swingStart, st.melee.swingRemaining = 0, 0
  st.weave.keyHeld, st.weave.keyHeldSince = false, 0
  st._raptorCdOverride = nil
  st.demo.hudForceShow = false
  self:ReleaseGrid()
  -- The replay frames are the one large thing a session leaves behind (up to
  -- REPLAY_FRAMES x a copied snapshot + plan: tens of MB after a long fight);
  -- the replay is closed above, so nothing reads them until the next Start,
  -- which rebuilds the record anyway. A raid should not carry them.
  self._planRec, self._recRev, self._recSig = nil, nil, nil
  Nock:SendMessage("NOCK_VISUALS_CHANGED")
  Nock:SendMessage("NOCK_PRACTICE_CHANGED")
  self:Print("Practice OFF.")
end

function Practice:StartFight()
  if not self:IsActive() or Nock.state.sim.fightOn then return end
  local st = Nock.state
  self._replay, self._recRev, self._stopAt = nil, nil, nil
  self._fightDemo = nil       -- set by the first ghost press: a demo fight passes no rung
  self._cdSeen, self._cdScanN = nil, 0   -- the cd row: sticky once a cooldown/proc lands (PublishPlan)
  self._procSeen = nil        -- the procs popped by hand this fight: their tiles show on a paper drill (Palette:Resolve)
  if self._planRec then for i = self._planRec.n, 1, -1 do self._planRec[i] = nil end; self._planRec.n = 0 end
  -- Every option the engine reads applies per FIGHT, not per Start: rebuild the
  -- config and the engine here so a latency/footwork/re-arm change made on the
  -- options panel while practice is on takes effect on the next pull. Start's
  -- own build stays (the panel's status line reads cfg before the first fight)
  -- and the keys/names it resolved are untouched.
  self.cfg = self:BuildConfig()
  -- The ghost has no feet: its fight runs on key-only footwork, whatever the
  -- profile says. ToggleDemo set this on the OLD cfg and the rebuild above
  -- dropped it, so the ghost never walked into melee and every weave paper
  -- left it mashing the weave key (2026-08-26).
  if self._demo then
    if self._demoFootwork == nil then self._demoFootwork = self.cfg.footwork end
    self.cfg.footwork = "key"
  end
  -- The scenario decides the haste the drill starts from (ews= / lock=), so it
  -- is resolved BEFORE the engine is built: the config it edits is the one
  -- E.New copies. LoadScenario then arms the scripted procs.
  local sc, scErrors = self:CurrentScenario()
  local ews = sc and sc.ews
  if sc and sc.lock then
    local locked = Practice.LockEWS(Nock.Profiles and Nock.Profiles.list, sc.lock, self._liveEws)
    if locked then
      ews = ews or locked
    else
      -- A typo in lock= would otherwise drill at live haste in silence, and the
      -- scorecard would grade a rotation the player never asked for.
      scErrors = scErrors or {}
      scErrors[#scErrors + 1] = ("unknown notation in lock=%s, running at live haste"):format(tostring(sc.lock))
    end
  end
  self:ReportScenarioErrors(scErrors)
  if ews and ews > 0 then self.cfg.baseRangedMul = self.cfg.ws / ews end
  self.engine = E.New(self.cfg)
  -- The loaded drill's own cap (R6c), which overrides the scenario's len= for
  -- this fight only — the catalog row itself is never touched.
  local drillLen = self:DrillLen()
  E.LoadScenario(self.engine, sc, drillLen)
  -- What the header's clock counts down from. Stamped here, at the arm, for the
  -- same reason the scenario table is: the pick may move under a running fight.
  self._fightLen = drillLen or (sc and sc.len) or nil
  -- LoadScenario turns Quick Shots back ON for every scenario that does not say
  -- qs=off (or lock=, which implies it): a scenario may only take the roll
  -- away, never grant it, so the setting decides in every other case.
  if sc == nil or sc.qs ~= false then self.engine.cfg.quickShots = self.cfg.quickShots end
  -- A paper drill rolls no crits either: the crit roll opens Kill Command
  -- windows, a proc the paper never stated (user, 2026-08-26, on 5:5:1:1 3w).
  -- A script that wants them on a locked paper says `kc=on`.
  if sc and sc.qs == false and not sc.kc then
    self.engine.cfg.critRanged, self.engine.cfg.critMelee = 0, 0
  end
  local h = { ws = self.cfg.ws, rangedMul = self.cfg.baseRangedMul, mws = st.melee.swingDuration or 3.7,
              meleeMul = 1.0, imprArcanePts = self.cfg.imprArcanePts,
              castCorr = self.cfg.castCorr,
              multiCd = C.PRACTICE.MULTI_CD,
              arcaneCdBase = C.PRACTICE.ARCANE_CD_BASE,
              arcaneCdPerPt = C.PRACTICE.ARCANE_CD_PER_PT }
  -- Weave or turret paper, decided once for the whole fight (WeaveFight above).
  -- Before the notation below: that resolution goes through it.
  self._fightWeave = self:WeaveFight()
  -- A paper drill names its own rotation (sc.notation), and that name IS the
  -- drill — grading it against whatever the live bracket says would defeat the
  -- point of pinning the haste. Everything else reads the ladder as before.
  local notation = (sc and sc.notation)
    or self:ResolveNotation(self.cfg.ws / self.cfg.baseRangedMul)
    or "1:1"
  -- The notation the fight OPENED at. state.sim.notation follows the haste
  -- windows from here (a Rapid Fire stretch renames it), so the name the report
  -- prints has to be stashed rather than read back at the stop.
  self._fightNotation = notation
  -- The FIGHT's symbol set, seeded with the opening paper and grown by every
  -- window (Step): the stage's rows. A window that drops the instants (the
  -- 2:2 weave paper under Lust on the opener drill) must not take their rows
  -- away and blink them back when the next window returns them (user,
  -- 2026-08-27). Reused across fights: cleared, never reallocated.
  local fs = self._fightSyms
  if not fs then fs = {}; self._fightSyms = fs end
  fs.s, fs.m, fs.A, fs.w, fs.r = false, false, false, false, false
  do
    local open = (G and G.Syms and M) and G.Syms(M, notation) or nil
    if open then fs.s, fs.m, fs.A, fs.w, fs.r = open.s, open.m, open.A, open.w, open.r end
  end
  st.sim.rowSyms = fs
  -- Same reason: the report is copied long after the fight, and the scenario
  -- pick or the seed may have been edited on the panel meanwhile.
  -- Every catalog row's `sc` carries its own name (Free play's included), so
  -- this is the name the player picked. A question mark would be a dead end in
  -- the report and the review window's chip for the rest of the session, so a
  -- nameless — or empty-named — scenario table falls back to the pick itself
  -- rather than inventing one.
  local scName = sc and sc.name
  if scName == "" then scName = nil end
  self._fightScenario = scName or profile("practiceScenario", nil) or "?"
  -- The scenario TABLE this fight is running, so NotationFor reads the pin off
  -- the fight rather than off the dropdown: switching the pick mid-fight must
  -- not re-grade the windows already behind us.
  self._fightScenarioTable = sc
  -- Which ladder drill this fight is an attempt at, remembered at the PULL for
  -- the same reason: only the drill that was loaded when the fight started may
  -- be graded against its pass condition.
  self._fightLadderDrill = self:LadderState().loaded
  self._ladderPassed, self._ladderNext = nil, nil
  self._fightSeed = profile("practiceSeed", 1)
  -- Drums is a charged item on the live grid and Cooldowns yields its badge to
  -- the sim, so read the charges you actually carry once, here.
  self._drumsCharges = GetItemCount and GetItemCount(C.DRUMS.BATTLE_ITEM, false, true) or nil
  self.grader = G.New({
    model = M, h = h, notation = notation,
    -- The shared paper-key scheme (T.NoteKey): a judgment's note carries the
    -- same key the conveyor gives that item, which is how a view finds the
    -- frame a pop belongs to.
    timeline = Nock.PracticeTimeline,
    clipMin = C.PRACTICE.CLIP_MIN,
    reaction = profile("practiceReactionMs", 150) / 1000,
    meleeCycle = self.cfg.mws / self.cfg.baseMeleeMul,
    oppMin = C.PRACTICE.OPP_MIN,
    rearmMin = C.PRACTICE.REARM_MIN,
    legMax = profile("practiceLegMaxSec", C.PRACTICE.LEG_MAX),
    -- One notation per haste window, so the scorecard grades a Rapid Fire
    -- stretch against the Rapid Fire rotation rather than the fight's opener.
    notationFor = function(rm, flags) return self:NotationFor(rm, flags) end,
    opener = {
      anchor = profile("practiceOpenerAnchor", "pull"),
      gcds = profile("practiceOpenerGcds", 2),
      steadySec = profile("practiceOpenerSteadySec", 0.5),
      cds = profile("practiceOpenerCds", {}),
    },
  })
  self._fed = 0
  -- Where the virtual target stands, before the engine's clock starts.
  self:PlantTarget()
  st.sim.notation = notation
  -- Provisional: the fight is ARMED here, and t0 moves to the first press (the
  -- pull) when it lands. Step republishes it from the engine every tick.
  st.sim.t0 = GetTime()
  st.sim.pulled = false
  st.sim.fightOn = true
  st.sim.lastVerdict = nil
  -- A melee swing left over from the live game (or a previous fight) would sit
  -- in state until the sim's first publish and block the drill's first GO, so
  -- the grid starts from zero with the fight.
  st.melee.swingStart, st.melee.swingRemaining = 0, 0
  E.StartFight(self.engine, GetTime(), profile("practiceSeed", 1))
  -- AFTER the arm: E.StartFight's Reset nils the zone, so seed the distance
  -- here or key-only footwork publishes TOO_FAR until the first press. The
  -- zone event itself is held back until the pull.
  E.SetDistance(self.engine, self.cfg.startDistance)
  -- What this paper costs by design, for the coach's ARMED line.
  self._paperNoteTag, self._paperNoteText = self:PaperNotes(sc)
  -- Start goes to Focus (shell step 3): the window hides, the stage stands
  -- alone on the HUD. Before NOCK_PRACTICE_CHANGED, which relayouts the shell.
  -- ...unless Expert is on: a Start from the combat log's head stays there.
  local wb = Nock:GetModule("PracticeWorkbench", true)
  if profile("practiceFocusOnStart", false) and not (wb and wb.IsExpert and wb:IsExpert()) then
    Nock:SendMessage("NOCK_PRACTICE_FOCUS", true)
  end
  Nock:SendMessage("NOCK_PRACTICE_CHANGED")
end

-- The keybinds (Bindings.xml): Start/Stop toggles the fight (and turns
-- practice on for it), Focus toggles the stage between the window and the
-- HUD without touching the fight, Expert toggles the two-panel mode (the
-- combat log and the weave log, no stage). Also `/nock practice focus` and
-- `/nock practice expert`.
BINDING_HEADER_NOCK = "Nock"
BINDING_NAME_NOCK_PRACTICE_STARTSTOP = "Practice: start / stop the fight"
BINDING_NAME_NOCK_PRACTICE_FOCUS = "Practice: focus (stage on the HUD / workbench)"
BINDING_NAME_NOCK_PRACTICE_EXPERT = "Practice: expert (combat log + weave log, no stage)"
function Nock:PracticeBinding(what)
  local p = Practice
  if what == "startstop" then
    if not p:IsActive() then p:Start() end
    if not p:IsActive() then return end
    if Nock.state.sim.fightOn then p:StopFight() else p:StartFight() end
  elseif what == "focus" then
    if not p:IsActive() then return end
    local cv = Nock:GetModule("PracticeConveyorView", true)
    local on = cv and cv.IsFocus and cv:IsFocus()
    Nock:SendMessage("NOCK_PRACTICE_FOCUS", not on)
  elseif what == "expert" then
    if not p:IsActive() then return end
    local wb = Nock:GetModule("PracticeWorkbench", true)
    local on = wb and wb.IsExpert and wb:IsExpert()
    Nock:SendMessage("NOCK_PRACTICE_EXPERT", not on)
  end
end

-- Is this a WEAVE fight? The drill's melee half only exists when a weave key
-- reaches the sim and there is a two-hander to swing it with — and that is
-- exactly when rotationtools' WEAVE ladder is the paper to grade against. On
-- the turret paper a melee hit is an OFF note (the layout has no `w` slot for
-- it) and the weave's own slot is MISSED, so an unpinned weave fight was
-- passable only by not weaving.
--
-- Core/Core.lua's live gate adds the display option and the range band; neither
-- belongs here. `weaveNotationEnabled` decides what the HUD DRAWS, and a paper
-- that flipped with the player's distance would re-grade a window mid-cycle.
-- Answered once, at the pull, and held for the whole fight.
function Practice:WeaveFight()
  local p = Nock.db and Nock.db.profile
  if not p then return false end
  if p.weaveBindEnabled ~= true or (p.weaveBindKey or "") == "" then return false end
  if Nock.state.player.canWeave == false then return false end
  return true
end

-- The one place a rotation NAME is resolved for a practice fight: the weave
-- ladder for a weave fight, the turret ladder otherwise. Both the fight's
-- opening notation and the grader's per-window notation route through it, so
-- the report's header and the windows under it can never disagree.
--
-- `weave` overrides the fight's own weave verdict for a caller asking OUTSIDE a
-- fight: `_fightWeave` is stamped at the pull and means nothing before it, so
-- FightPaper (below) hands in WeaveFight()'s live answer instead. nil keeps the
-- fight's own, which is what every in-fight caller wants.
local NO_FLAGS = { rapidFire = false, quickShots = false, drums = false, inLust = false }
function Practice:ResolveNotation(ews, flags, meleeHaste, weave)
  local P = Nock.Profiles
  if not (P and ews and ews > 0) then return nil end
  flags, meleeHaste = flags or NO_FLAGS, meleeHaste or 0
  if weave == nil then weave = self._fightWeave end
  if weave then
    local w = P:ResolveWeave(ews, flags, meleeHaste)
    if w then return w end
  end
  return (P:ResolveTurret(ews, flags, meleeHaste)) or (P:ResolveByEWS(ews))
end

-- The grader's per-window notation: what rotationtools would call the rotation
-- at THAT window's haste, procs and all. Called as windows open (once per haste
-- change), never per tick, but the flags table is reused anyway — ResolveTurret
-- and ResolveWeave only read it.
local procFlags = { rapidFire = false, quickShots = false, drums = false, inLust = false }
function Practice:NotationFor(rangedMul, flags)
  -- ...unless the drill is a PAPER one, which names its rotation up front and
  -- holds its procs for the whole minute. Read off the fight's own scenario
  -- table (stashed at the pull), never the dropdown: a mid-fight pick change
  -- would otherwise re-label the windows already graded.
  local pinned = self._fightScenarioTable
  if pinned and pinned.notation then return pinned.notation end
  if not (Nock.Profiles and rangedMul and rangedMul > 0 and self.cfg) then
    return Nock.state.sim.notation or "1:1"
  end
  local ews = self.cfg.ws / rangedMul
  procFlags.rapidFire  = (flags and flags.rf) or false
  procFlags.quickShots = (flags and flags.qs) or false
  procFlags.drums      = (flags and flags.drums) or false
  procFlags.inLust     = (flags and flags.lust) or false
  local meleeHaste = (((self.engine and self.engine.meleeMul) or 1) - 1) * 100
  return self:ResolveNotation(ews, procFlags, meleeHaste) or "1:1"
end

-- THE PAPER THE FIGHT IS GRADED AGAINST, and the ranged multiplier it runs at.
--
-- One resolution, three readers: StartFight's opening notation, the lesson's
-- subject, and the conveyor's ARMED forecast. It used to exist twice — once in
-- StartFight and once, spelled differently, in LessonPlan — and the conveyor had
-- no version at all: before the pull the grader has no haste window yet, so the
-- strip fell back to `M.STRINGS[win and win.notation or ""] or "as"` and drew a
-- 1:1 forecast for whatever drill was armed (R6a).
--
-- While a fight is on — ARMED counts, StartFight stamps `_fightNotation` at the
-- arm — it is the notation that fight OPENED with, at the haste it opened with.
-- Never `state.sim.notation`, which follows the haste windows: a surface that
-- redrew itself at every Rapid Fire would be teaching the rotation you are not
-- practising, twice a minute.
--
-- Outside one it is what StartFight WOULD resolve on the next pull: a pinned
-- paper drill's own rotation (`sc.notation`) at its own pin (`ews=` / `lock=`),
-- else the ladder branch. `_fightWeave` means nothing before the pull, so
-- WeaveFight()'s live answer is handed to ResolveNotation instead.
--
-- Returns notation, rangedMul, cfg — `cfg` being the handle the other two were
-- read from (the fight's own while one runs, a fresh build otherwise). The
-- caller must not keep it past its next call. Allocates nothing in a fight,
-- which is what lets the conveyor's rebuild ask.
function Practice:FightPaper()
  local st = Nock.state
  if st.sim.fightOn and self._fightNotation then
    local cfg = self.cfg or self:BuildConfig()
    return self._fightNotation, cfg.baseRangedMul, cfg
  end
  local cfg = self:BuildConfig()
  local sc = self:CurrentScenario()
  local ews = sc and sc.ews
  if sc and sc.lock then
    ews = ews or Practice.LockEWS(Nock.Profiles and Nock.Profiles.list, sc.lock, self._liveEws)
  end
  local mul = (ews and ews > 0) and (cfg.ws / ews) or cfg.baseRangedMul
  local notation = sc and sc.notation
  if not notation and mul and mul > 0 then
    notation = self:ResolveNotation(cfg.ws / mul, NO_FLAGS, 0, self:WeaveFight())
  end
  return notation or "1:1", mul, cfg
end

-- Does the paper the next fight runs (or the running one) weave? The weave
-- log and its buttons exist only then (user, 2026-08-26). A fight's own
-- paper while one runs; the pick's otherwise; a rotation of the character's
-- own (no pinned notation) weaves when Weave Bind can.
function Practice:PaperWeaves()
  local notation = self:FightPaper()
  local syms = (G and G.Syms and M) and G.Syms(M, notation) or nil
  if syms and (syms.w or syms.r) then return true end
  return false
end

-- The model handle for a paper at a haste, filled in place: what
-- M.PaperString / M.Layout / M.PaperNotes read. One definition for the
-- lesson, the paper notes and the armed strip.
local function fillPaperH(h, cfg, mul, mws)
  h.ws, h.rangedMul = cfg.ws, mul
  h.mws = mws or cfg.mws or 3.7
  h.meleeMul = cfg.baseMeleeMul or 1
  h.imprArcanePts, h.castCorr = cfg.imprArcanePts, cfg.castCorr
  h.multiCd = C.PRACTICE.MULTI_CD
  h.arcaneCdBase = C.PRACTICE.ARCANE_CD_BASE
  h.arcaneCdPerPt = C.PRACTICE.ARCANE_CD_PER_PT
  return h
end

-- What a paper costs by design (M.PaperNotes) for a scenario table -- a
-- catalog row's `sc`, or the current pick when nil -- at the haste it will
-- run at. Returns tag, text (nil, nil for a paper that costs nothing, or a
-- scripted scenario with no paper). Allocates: never from the tick.
function Practice:PaperNotes(sc)
  if not M then return nil, nil end
  sc = sc or (self:CurrentScenario())
  -- Outside a fight the config is rebuilt: the last fight's cfg carries its
  -- drill's pinned haste (LessonPlan's own lesson) and the Lesson showed no
  -- note for the pick (user, 2026-08-26).
  local cfg = (Nock.state.sim.fightOn and self.cfg) or self:BuildConfig()
  local notation = sc and sc.notation
  local ews = sc and sc.ews
  if sc and sc.lock then
    ews = ews or Practice.LockEWS(Nock.Profiles and Nock.Profiles.list, sc.lock, self._liveEws)
  end
  local mul = (ews and ews > 0) and (cfg.ws / ews) or cfg.baseRangedMul
  if not notation and mul and mul > 0 then
    notation = self:ResolveNotation(cfg.ws / mul, NO_FLAGS, 0, self:WeaveFight())
  end
  local h = fillPaperH({}, cfg, mul)
  local str = notation and M.PaperString(notation, h)
  if not str then return nil, nil end
  local stepIn = (self.grader and G.StepIn and G.StepIn(self.grader)) or (G and G.STEP_IN_SEED) or 0.35
  local tag, text = M.PaperNoteText(M.PaperNotes(str, h, stepIn))
  -- The weave key (user, 2026-08-27): a paper that weaves, graded with no
  -- Weave Bind key, MISSES every weave note -- and the only word about it
  -- was one chat line at Start. Outranks the paper's own notes; the coach
  -- line, the Scenarios card and the Lesson banner all read this tag.
  local syms = (G and G.Syms and notation) and G.Syms(M, notation) or nil
  if syms and (syms.w or syms.r) and not self:WeaveFight() then
    tag = "no weave key"
    local wb = Nock:GetModule("WeaveBind", true)
    local g = wb and wb.GroundedWeaveBind and wb:GroundedWeaveBind()
    if g then
      text = ("This paper weaves and Nock has no weave key -- Grounded holds yours (%s). Import it on the Keys page; until then every weave note is MISSED."):format(g.key)
    else
      text = "This paper weaves and the Weave Bind is off or has no key: every weave note will be MISSED. Set the key on the Keys page (or in Options -> Weave Bind)."
    end
  end
  return tag, text, notation, ews
end

-- What the Keys page's WEAVE KEY row shows: Nock's own key (the real bind,
-- not a practice override), whether the feature is on, and the bind Grounded
-- holds when Nock has none.
function Practice:WeaveKeyState()
  local p = Nock.db and Nock.db.profile or {}
  local wb = Nock:GetModule("WeaveBind", true)
  local g = wb and wb.GroundedWeaveBind and wb:GroundedWeaveBind()
  local key = p.weaveBindKey
  if key == "" then key = nil end
  return {
    override = key, enabled = p.weaveBindEnabled == true,
    grounded = g and g.key or nil,
    imported = p.weaveBindImported ~= nil and (wb and wb.GroundedLoaded and wb:GroundedLoaded()) or false,
  }
end

-- Panel buttons: flip a proc by hand mid-fight (Lust landing, a trinket proc)
-- without scripting it into a scenario. Names are the engine's own: QS, RF,
-- Lust, Drums, DST, Pot.
function Practice:Proc(name, on)
  local e = self.engine
  if not (self:IsActive() and Nock.state.sim.fightOn and e) then return end
  if e.procs[name] == nil then return end
  E.Proc(e, name, on and true or false, GetTime())
  Nock:SendMessage("NOCK_PRACTICE_CHANGED")
end

-- A palette tile's state: "held" (the scenario's `hold=`, not yours to touch),
-- "perm" (held by hand for the rest of the fight), "up" (running, timed) or
-- "off". The palette's clicks cycle off -> up -> perm -> off; right-click is
-- off from anywhere (user, 2026-08-27).
function Practice:ProcState(name)
  local e = self.engine
  if not (e and e.procs and e.procs[name] ~= nil) then return "off" end
  if e.scHold and e.scHold[name] then return "held" end
  if e.hold and e.hold[name] then return "perm" end
  return (e.procs[name] > 0) and "up" or "off"
end

function Practice:ProcMode(name, mode)
  local e = self.engine
  if not (self:IsActive() and Nock.state.sim.fightOn and e) then return end
  if e.procs[name] == nil then return end
  if e.scHold and e.scHold[name] then return end
  local now = GetTime()
  if mode == "perm" then E.Hold(e, name, true, now)
  elseif mode == "off" then E.Hold(e, name, false, now)
  else E.Proc(e, name, true, now) end
  -- A proc popped by hand on a paper drill has no tile to show it (the row
  -- hides on a paper): from now on this fight it has one (user, 2026-08-27:
  -- "when a buff keybind is hit and the paper doesn't have buff support, it
  -- should show").
  self._procSeen = self._procSeen or {}
  self._procSeen[name] = true
  Nock:SendMessage("NOCK_PRACTICE_CHANGED")
end

-- The Quick Shots roll, on or off. A scenario's `qs=off` owns the engine's copy
-- for the fight it loaded, so this flips both the setting and the live engine.
function Practice:ToggleQS()
  -- ...but a PAPER drill owns it outright: `qs = false` is half of what pins
  -- the drill's notation for the whole minute, so granting the roll mid-fight
  -- would rename the rotation under the player's fingers — exactly what the
  -- drill exists to prevent. Refuse both writes (the profile included: a flip
  -- there is invisible while the engine ignores it, and would surprise the
  -- player on the NEXT, un-pinned fight) and say why.
  local sc = self._fightScenarioTable
  if Nock.state.sim.fightOn and sc and sc.qs == false then
    self:Print("Practice: Quick Shots are off in a paper drill.")
    return (self.engine and self.engine.cfg.quickShots) and true or false
  end
  local on = not profile("practiceQuickShots", true)
  if Nock.db and Nock.db.profile then Nock.db.profile.practiceQuickShots = on end
  if self.cfg then self.cfg.quickShots = on end
  if self.engine then self.engine.cfg.quickShots = on end
  Nock:SendMessage("NOCK_PRACTICE_CHANGED")
  return on
end

function Practice:StopFight()
  if not (self:IsActive() and Nock.state.sim.fightOn) then return end
  local e = self.engine
  -- Armed but never pulled: nothing was pressed, so there is no fight to grade
  -- and no review to open. Everything below still runs — the between-fights
  -- cleanup is the same — but the score, the printout and the FIGHT DONE
  -- message are skipped.
  -- ...and a PREVIEW fight (the Style page's ghost) is dropped the same way,
  -- pulled or not: nothing to grade, print, replay or pass.
  local cancelled = ((e and e.armed and not e.pulled) or self._previewFight) and true or false
  self._previewFight = nil
  E.StopFight(e, GetTime())
  if cancelled then
    -- ...and the PREVIOUS fight's scorecard goes with it. The engine's stream
    -- is empty now, so the review blanks and the panel is back to READY:
    -- leaving lastScore up made `/nock practice report` and `Copy report` hand
    -- back a scorecard for a fight that is no longer on any screen, dated
    -- against a `pull` the stream no longer holds. One state, one answer:
    -- there is nothing to show.
    self.lastScore = nil
    self.lastVerdicts = nil
  else
    self:FeedGrader()
    -- The stream goes in with the scorecard: G.Finish reads the fight's cycles
    -- off T.Cycles, the same builder the review's rotation row uses.
    self.lastScore = G.Finish(self.grader, e.events, e.n)
    self.lastVerdicts = self.grader.verdicts
    -- The ladder reads the finished scorecard, never a live one: a pass is a
    -- whole fight's worth of evidence.
    self:EvaluateLadder(self.lastScore)
  end
  local st = Nock.state
  st.sim.fightOn = false
  st.sim.pulled = false
  self:PublishPlan(st, GetTime())
  self._stopAt = GetTime()
  self:ClearSimState(st)
  st.sim.notation = nil
  st.sim.paperSyms = nil
  st.sim.rowSyms = nil
  -- ...and the replay opens at the stop: the next tick republishes the fight
  -- as it stood there (Step's replay path), the stage holds its clock on it.
  if not cancelled then self:ReplayAt(self._stopAt) end
  -- Stop comes back from Focus: the window returns with the stage docked and
  -- the replay on it.
  Nock:SendMessage("NOCK_PRACTICE_FOCUS", false)
  Nock:SendMessage("NOCK_PRACTICE_CHANGED")
  if cancelled then
    self:Print("Practice: fight cancelled (nothing was pressed).")
    return
  end
  self:PrintScore(self.lastScore)
  -- After the score: the drill passed BECAUSE of the numbers just printed.
  if self._ladderPassed then
    if self._ladderNext then
      self:Print(("Practice: drill passed — %s. Next: %s (%s)."):format(
        self._ladderPassed.name, self._ladderNext.name, self._ladderNext.pass and self._ladderNext.pass.text or "-"))
    else
      self:Print(("Practice: drill passed — %s."):format(self._ladderPassed.name))
    end
    self._ladderPassed, self._ladderNext = nil, nil
  end
  -- After the score, so a listener that reads lastScore/lastVerdicts (the
  -- timeline) sees the finished fight.
  Nock:SendMessage("NOCK_PRACTICE_FIGHT_DONE")
end

-- The weave half of the scorecard, or nil when the fight had no weave in it
-- (a turret drill, or Weave Bind off). Once per fight, so the format cost and
-- the table walk are free. Every nested field is guarded: `legs` only carries
-- stats once a weave has actually landed a hit.
-- A number the grader could not measure prints as an em dash, never as a
-- number. Everything the scorecard states in SECONDS is an offset from the
-- fight's origin (the `pull`), and with no origin the only value left to print
-- is the raw GetTime() clock — which is how a review came to read
-- "Steady 305232320.92s". The RATES go the same way: a rate over an
-- unmeasurable span is not a number either. One rule for all of them: no
-- origin, no number.
local NONE_MARK = "\226\128\148"
local function dashSec(v, fmt) return v and (fmt):format(v) or NONE_MARK end
local function dashPct(v) return v and ("%d%%"):format(v * 100 + 0.5) or NONE_MARK end

local function weaveLine(s)
  if not s or (s.weavesTaken + s.weavesMissed) <= 0 then return nil end
  local L = s.legs or {}
  local si, so = L.stepIn or {}, L.stepOut or {}
  local bp = L.backpedalPct or {}
  return ("Weave: taken %d/%d \194\183 hits %d \194\183 weave eff %s \194\183 re-arm %d ms \194\183 legs in %.2f/%.2f \194\183 out %.2f/%.2f (med/worst) \194\183 in budget %d%% \194\183 backpedal in %d%% out %d%%")
    :format(s.weavesTaken, s.weavesTaken + s.weavesMissed, s.meleeHits or 0,
            dashPct(s.weaveEff), s.rearmMs or 0,
            si.med or 0, si.worst or 0, so.med or 0, so.worst or 0,
            (L.inBudgetPct or 0) * 100 + 0.5,
            (bp.stepIn or 0) * 100 + 0.5, (bp.stepOut or 0) * 100 + 0.5)
end

-- The rotation row as one line: the paper's stream against the played one,
-- both flattened auto-first (every cycle STARTS with its auto, which is what
-- puts the `a`s back into the string).
--
-- Both sides are cut at the SAME cycle boundary. Cut per side at a symbol count
-- and the two columns stop lining up — a cycle where you pressed one thing more
-- than the paper asked shifts everything after it, and the line's whole job is
-- that you can read the two rows against each other. The trailing cycle is
-- usually still open (see T.Cycles' `partial`), so it ends the walk too rather
-- than reporting a half-played cycle as a difference.
local ROT_SYMS = 24
local rotBuf = {}
local function rotCut(cycles)
  local p, s, last = 0, 0, 0
  for i = 1, cycles.n do
    local c = cycles[i]
    if c.partial then break end
    local np, ns = p + 1 + (c.pN or 0), s + 1 + (c.sN or 0)
    if np > ROT_SYMS or ns > ROT_SYMS then break end
    p, s, last = np, ns, i
  end
  return last
end

local function rotSide(cycles, last, arrKey, nKey)
  local n = 0
  for i = 1, last do
    n = n + 1
    rotBuf[n] = "a"
    local arr, cnt = cycles[i][arrKey], cycles[i][nKey] or 0
    for j = 1, cnt do
      n = n + 1
      rotBuf[n] = arr[j]
    end
  end
  return table.concat(rotBuf, " ", 1, n)
end

local function rotationLine(cycles)
  if not (cycles and cycles.n and cycles.n > 0) then return nil end
  local last = rotCut(cycles)
  if last == 0 then return nil end
  -- The ellipsis says "there was more" — so it is only written when there was.
  local more = (last < cycles.n) and " \226\128\166" or ""
  return ("Rotation: paper %s%s / you %s%s")
    :format(rotSide(cycles, last, "pSyms", "pN"), more,
            rotSide(cycles, last, "syms", "sN"), more)
end

-- The crit-window ledger, or nil when no crit ever opened one.
local function kcLine(s)
  if not (s and s.kc and s.kc.windows > 0) then return nil end
  return ("KC: windows %d \194\183 used %d"):format(s.kc.windows, s.kc.used or 0)
end

-- Per-cooldown opener mark: OK on time, "early" before the anchor, MISS late or
-- never, em dash for a cooldown the opener never asked for.
--
-- Words rather than check marks, for the same reason the review window's opener
-- tile carries words: the marks used to be U+2713/U+2717, which the report font
-- (and every LibSharedMedia face the panel might be on) is free not to have —
-- and a report full of empty boxes is worth nothing pasted back.
local OK_MARK, NO_MARK = "OK", "MISS"
local function cdMark(op, key)
  local c = op.cds and op.cds[key]
  if not c then return NONE_MARK end
  if c.ok then return OK_MARK end
  if c.early then return "early" end
  return NO_MARK
end

-- The opener drill: how fast the first Steady went out, whether Multi was on
-- the pull, and each listed cooldown against the anchor.
local function openerLine(s)
  local op = s and s.opener
  if not op then return nil end
  return ("Opener (%s): Steady %s %s \194\183 Multi %s \194\183 RF %s \194\183 Spec %s \194\183 T1 %s \194\183 T2 %s \194\183 Drums %s \194\183 Pot %s")
    :format(tostring(op.anchor or "pull"), dashSec(op.firstSteady, "%.2fs"),
            op.steadyOk and OK_MARK or NO_MARK, op.multiOnPull and OK_MARK or NO_MARK,
            cdMark(op, "RF"), cdMark(op, "Spec"), cdMark(op, "T1"),
            cdMark(op, "T2"), cdMark(op, "Drums"), cdMark(op, "Pot"))
end

-- The scorecard as the 2-4 lines the chat print says out loud, into the
-- CALLER's table (the timeline's scorecard paints the same strings, and both
-- reuse their own table rather than allocate per fight). `s` defaults to the
-- last finished fight.
function Practice:ScoreLines(out, s)
  out = out or {}
  for i = #out, 1, -1 do out[i] = nil end
  s = s or self.lastScore
  if not s then return out end
  -- CYCLES ON PAPER, not damage vs paper: a cycle either came out exactly as
  -- the paper asked (every note played, nothing extra) or it did not, and the
  -- fix for one that did not is a note the review can point at. The old
  -- damage-percentage basis is retired everywhere (plan 2026-08-23 v2).
  local cp = s.cyclesOnPaper
  out[1] = ("Practice: %s — auto eff %s, GCD eff %s, clips %d (+%d ms), early %d, late %d ms, cycles on paper %d/%d (%s), best streak %d, grade %s")
    :format(dashSec(s.fightTime, "%.0fs"), dashPct(s.autoEff), dashPct(s.gcdEff), s.clips, s.clipMs,
            s.early, s.lateMs, cp and cp.ok or 0, cp and cp.total or 0,
            self._fightNotation or "?", s.bestStreak or 0, s.grade or "?")
  local w = weaveLine(s)
  if w then out[#out + 1] = w end
  local o = openerLine(s)
  if o then out[#out + 1] = o end
  local k = kcLine(s)
  if k then out[#out + 1] = k end
  return out
end

function Practice:PrintScore(s)
  if not s then return end
  self._scoreLines = self:ScoreLines(self._scoreLines, s)
  for i = 1, #self._scoreLines do self:Print(self._scoreLines[i]) end
  self:Print("/nock practice report copies the full verdict list.")
end

-- Key presses arrive here from PracticeKeys' buttons (Task 11) and the panel.
function Practice:OnKey(actions)
  if not (self:IsActive() and Nock.state.sim.fightOn) then return end
  E.Press(self.engine, actions, GetTime())
end

function Practice:FeedGrader()
  local e, g = self.engine, self.grader
  if not (e and g) then return end
  local verdictsOn = profile("practiceVerdicts", nil)
  while self._fed < e.n do
    self._fed = self._fed + 1
    local ev = e.events[self._fed]
    if self._debug then self:DebugEvent(ev) end
    local before = g.lastVerdict
    G.Feed(g, ev)
    if ev.kind == "weave" and ev.edge == "done" and ev.legs and ev.legs.hit then
      self.lastLegs = ev.legs
    end
    local v = g.lastVerdict
    if v ~= before and v and (not verdictsOn or verdictsOn[v.code] ~= false) then
      Nock.state.sim.lastVerdict = v
    end
  end
end

-- /nock practice debug: every engine event as it is fed, stamped relative to
-- the pull, with the sim's footing at that moment, into a capped buffer that
-- /nock practice debuglog opens in a copybox. Weave events carry the legs;
-- melee events the hit; auto events the delay and its cause.
local DEBUG_MAX = 400
function Practice:DebugEvent(ev)
  local e = self.engine
  -- The dump is stamped from the fight's origin, and sim.t0 defaults to 0: with
  -- no origin published every line of it reads as the absolute clock. Same rule
  -- as the report — no origin, no stamp.
  local t0 = Nock.state.sim.t0
  if t0 == 0 then t0 = nil end
  local function rel(t) return (t0 and t) and ("%.3f"):format(t - t0) or NONE_MARK end
  local extra = ""
  if ev.kind == "weave" then
    extra = ("edge=%s"):format(tostring(ev.edge))
    if ev.cost then extra = extra .. (" cost=%.3f"):format(ev.cost) end
    local L = ev.legs
    if L then
      extra = extra .. (" in=%s dwell=%s out=%s hit=%s"):format(
        L.stepIn and ("%.3f"):format(L.stepIn) or "nil", L.dwell and ("%.3f"):format(L.dwell) or "nil",
        L.stepOut and ("%.3f"):format(L.stepOut) or "nil", tostring(L.hit))
    end
  elseif ev.kind == "melee" then extra = "hit=" .. tostring(ev.hit)
  elseif ev.kind == "range" then extra = ("zone=%s inMelee=%s"):format(tostring(ev.zone), tostring(ev.inMelee))
  elseif ev.kind == "opp" then extra = ("open=%s ttw=%.2f"):format(tostring(ev.open), ev.ttw or 0)
  elseif ev.kind == "auto" then extra = ("delay=%.3f cause=%s"):format(ev.delay or 0, tostring(ev.cause))
  elseif ev.kind == "press" then
    extra = ("key=%s result=%s%s%s"):format(tostring(ev.key), tostring(ev.result),
      ev.queuedFrom and (" queuedFrom=%s"):format(rel(ev.queuedFrom)) or "", ev.mash and " mash" or "")
  elseif ev.kind == "cast" then
    extra = ("spell=%s t0=%s t1=%s%s"):format(tostring(ev.spell), rel(ev.t0), rel(ev.t1), ev.cancelled and " cancelled" or "")
  end
  local line = ("%7s %-8s %s | dist %.2f melee %s on %s ready %+.2f recheck %+.2f raptorQ %s lat %.3f | gcdEnd %+.2f cast %s windup %s next %+.2f"):format(
    rel(ev.t), ev.kind, extra, e.dist or -1, tostring(e.inMelee), tostring(e.meleeOn),
    (e.meleeReadyAt or 0) - (ev.t or 0), (e.meleeRecheckAt or 0) - (ev.t or 0), tostring(e.raptorQueued),
    self.cfg and self.cfg.latency or -1,
    (e.gcdEnd or 0) - (ev.t or 0), e.cast and ("%s..%+.2f"):format(e.cast.spell, e.cast.t1 - (ev.t or 0)) or "nil",
    e.windupAt and ("%+.2f"):format(e.windupAt - (ev.t or 0)) or "nil", (e.nextShotAt or 0) - (ev.t or 0))
  local log = self._debugLog
  if not log then log = {}; self._debugLog = log end
  log[#log + 1] = line
  if #log > DEBUG_MAX then table.remove(log, 1) end
end

function Practice:ShowDebugLog()
  local log = self._debugLog
  if not log or #log == 0 then self:Print("Practice: no debug events captured yet (/nock practice debug, then fight)."); return end
  local head = ("practice debug — %d events, latency %.3f, footwork %s, melee cycle %.2f\nweave down: %s\nweave up: %s\n"):format(
    #log, self.cfg and self.cfg.latency or -1, tostring(self.cfg and self.cfg.footwork),
    self.engine and self.engine.meleeCycle or -1,
    table.concat(self.weaveDown or {}, ","), table.concat(self.weaveUp or {}, ","))
  Nock.UI.ShowCopyBox(head .. table.concat(log, "\n"))
end

-- Panel feed: counters only, into the caller's table. nil when no fight runs.
function Practice:LiveScore(out)
  if not (self.grader and Nock.state.sim.fightOn) then return nil end
  return G.Live(self.grader, GetTime(), out)
end

----------------------------------------------------------------------------
-- Timeline feed (UI/Frame_PracticeTimeline.lua). Everything here reuses one
-- table per call site: the live window rebuilds a few times a second.
----------------------------------------------------------------------------

-- What Nock.PracticeTimeline.Build needs: the raw event stream, the finished
-- scorecard (nil while a fight runs — the view substitutes a provisional one)
-- and the model handle the paper lane is laid out from.
function Practice:TimelineData()
  local e, cfg = self.engine, self.cfg
  if not (e and cfg) then return nil end
  local h = self._tlH
  if not h then h = {}; self._tlH = h end
  h.ws, h.rangedMul = cfg.ws, cfg.baseRangedMul
  h.mws, h.meleeMul = cfg.mws, cfg.baseMeleeMul
  h.imprArcanePts, h.castCorr = cfg.imprArcanePts, cfg.castCorr
  h.multiCd = C.PRACTICE.MULTI_CD
  h.arcaneCdBase = C.PRACTICE.ARCANE_CD_BASE
  h.arcaneCdPerPt = C.PRACTICE.ARCANE_CD_PER_PT
  return e.events, e.n, self.lastScore, h, self.lastVerdicts
end

-- Lesson feed (UI/Frame_PracticeLesson.lua): the shot string the lesson
-- explains, the model handle it is laid out with, and the notation's own name.
--
-- The lesson is a teaching surface, so it describes the drill the player is
-- ABOUT to run, not the last one they ran: only while a fight is actually on
-- does it follow that fight's notation. Everything else is resolved exactly the
-- way StartFight would resolve it — including a paper drill's pinned haste
-- (ews= / lock=) — so opening the lesson off a scenario card explains the
-- rotation that card is going to hand you.
--
-- Works with practice OFF: BuildConfig reads the live character and the profile
-- and needs no engine. The handle is reused; the caller must not keep it past
-- its next call.
function Practice:LessonPlan()
  if not M then return nil end
  local st = Nock.state
  -- Which paper, at which haste: Practice:FightPaper() is the one answer, and
  -- the lesson is only one of its three readers. Outside a fight it rebuilds the
  -- config rather than reusing `self.cfg` — that keeps whatever StartFight
  -- pinned into it (a paper drill writes its lock= / ews= haste straight onto
  -- cfg.baseRangedMul) and nothing rebuilds it when the pick changes, so reading
  -- it here made the lesson teach the LAST drill's rotation at the LAST drill's
  -- haste for as long as practice stayed on.
  local notation, mul, cfg = self:FightPaper()
  local h = self._lessonH
  if not h then h = {}; self._lessonH = h end
  fillPaperH(h, cfg, mul, st.melee.swingDuration)
  return M.PaperString(notation, h) or M.STRINGS["1:1"], h, notation
end

-- Conveyor feed (UI/Frame_PracticeConveyor.lua): the raw event stream and the
-- running grader's verdicts, which is everything Nock.PracticeTimeline.Strip
-- needs beside a Lookahead. Allocates nothing — both are the live tables the
-- engine and grader already own. nil/0 between fights, and before the first.
function Practice:ConveyorData()
  local e = self.engine
  if not e then return nil, 0, nil end
  local g = self.grader
  local rp = self._replay
  if rp and not e.fightOn then return e.events, rp.n or 0, rp.verdicts end
  return e.events, e.n or 0, g and g.verdicts or nil
end

-- The live lookahead the timeline draws ahead of `now`: the shot grid, the
-- shot Nock's own rotation engine says is next, the melee swing and the weave
-- window, the procs still running and the cooldowns about to come up.
local aheadCds = {}

--------------------------------------------------------------------------------
-- REPLAY. Every plan revision of a fight is recorded (a frame: the plan's
-- notes, autos, rows and weave block as they stood, plus the engine snapshot
-- the strip draws around them), and after Stop the stage can be scrubbed
-- back through the fight: the strip at any moment, with the presses, autos
-- and judgments up to that moment and the plan exactly as it was asking then
-- -- so a clip can be pinned to the note that caused it. Wheel over the
-- stage (0.25 s; Shift 2 s; Ctrl 0.05 s; Alt jumps between clipped autos),
-- or `/nock practice replay <secs|+x|-x|next|prev|off>`. A new Start clears
-- it. Frames are allocated only on a revision change, never per tick.
--------------------------------------------------------------------------------
Practice.REPLAY_FRAMES = 6000   -- events and footwork: several minutes of fight

local function copyScalars(src, dst)
  for k, v in pairs(src) do
    local tv = type(v)
    if tv ~= "table" and tv ~= "function" then dst[k] = v end
  end
  return dst
end

local function copyPlan(plan)
  local c = copyScalars(plan, {})
  c.notes, c.autos, c.rows, c.weave = {}, {}, {}, copyScalars(plan.weave, {})
  for i = 1, plan.n do c.notes[i] = copyScalars(plan.notes[i], {}) end
  for i = 1, plan.nAutos do c.autos[i] = copyScalars(plan.autos[i], {}) end
  for i = 1, plan.nRows do c.rows[i] = plan.rows[i] end
  return c
end

-- The engine snapshot, copied: its scalars and the three tables the tick reads
-- through (cast, procs, cdReady).
local function copySnap(src)
  local c = copyScalars(src, {})
  c.cast = src.cast and copyScalars(src.cast, {}) or nil
  c.procs = src.procs and copyScalars(src.procs, {}) or nil
  c.cdReady = src.cdReady and copyScalars(src.cdReady, {}) or nil
  return c
end

-- What the HUD is drawn from changes only at events (a press, a release, a
-- cooldown coming back) and with the feet: one number that moves whenever
-- any of those does, so a frame is recorded on a change and never per tick.
local function snapSig(sn)
  local c = sn.cast
  return (sn.nextShotAt or 0) + (sn.lastShotAt or 0) + (sn.gcdStart or 0) + (c and c.t0 or 0)
       + (sn.msReadyAt or 0) + (sn.arcReadyAt or 0) + (sn.raptorReadyAt or 0) + (sn.meleeReadyAt or 0)
       + (sn.kcUntil or 0) + (sn.weaveDownAt or 0) + (sn.windupAt or 0)
       + math.floor((sn.dist or 0) * 2) * 0.001 + (sn.inMelee and 0.0005 or 0)
end

local function copyPlanInto(src, dst)
  for k, v in pairs(src) do if type(v) ~= "table" then dst[k] = v end end
  for i = 1, src.n do
    local d = dst.notes[i]
    if not d then d = {}; dst.notes[i] = d end
    for k in pairs(d) do if type(d[k]) ~= "table" then d[k] = nil end end
    copyScalars(src.notes[i], d)
  end
  for i = 1, src.nAutos do
    local d = dst.autos[i]
    if not d then d = {}; dst.autos[i] = d end
    copyScalars(src.autos[i], d)
  end
  for i = 1, src.nRows do dst.rows[i] = src.rows[i] end
  for k in pairs(dst.weave) do dst.weave[k] = nil end
  copyScalars(src.weave, dst.weave)
end

function Practice:RecordFrame(now, plan)
  local rec = self._planRec
  if not rec then rec = { n = 0 }; self._planRec = rec end
  local sig = snapSig(snap)
  local planNew = (plan.rev ~= self._recRev)
  if not planNew and sig == self._recSig then return end
  if rec.n >= Practice.REPLAY_FRAMES then return end
  self._recRev, self._recSig = plan.rev, sig
  local e = self.engine
  -- The plan is copied on a revision change; a frame cut by the HUD's own
  -- anchors shares the previous frame's plan.
  local pc = (not planNew and rec.n > 0) and rec[rec.n].plan or copyPlan(plan)
  local fr = { at = now, plan = pc, snap = copySnap(snap),
               nextShotAt = snap.nextShotAt, cycle = snap.cycle, windup = snap.windup,
               lastShotAt = snap.lastShotAt, rangedMul = snap.rangedMul,
               meleeReadyAt = snap.meleeReadyAt, oppOpen = e and e.oppOpen or false,
               weaveAt = snap.weaveAt, weaveRoom = snap.weaveRoom, weaveFits = snap.weaveFits,
               procs = snap.procs and copyScalars(snap.procs, {}) or nil,
               hold = e and e.hold or nil,
               winAutos = (self.grader and self.grader.win and self.grader.win.autos) or 0,
               streak = (self.grader and self.grader.streak) or 0,
               bestStreak = (self.grader and self.grader.bestStreak) or 0,
               kcReadyAt = snap.kcReadyAt, raptorReadyAt = snap.raptorReadyAt,
               cdReady = snap.cdReady and copyScalars(snap.cdReady, {}) or nil,
               paperSyms = Nock.state.sim.paperSyms, paperNote = self._paperNoteTag }
  rec.n = rec.n + 1
  rec[rec.n] = fr
end

function Practice:ReplayFrames() return self._planRec end

-- Enter (or move within) the replay at fight time `t` (absolute clock).
function Practice:ReplayAt(t)
  local rec, e = self._planRec, self.engine
  if not (rec and rec.n > 0 and e and not e.fightOn) then return false end
  local t0, t1 = rec[1].at, self._stopAt or rec[rec.n].at
  if t < t0 then t = t0 elseif t > t1 then t = t1 end
  local rp = self._replay
  if not rp then rp = { verdicts = {}, rev = 0 }; self._replay = rp end
  -- The last frame at or before t.
  local fi = rp.frame or 1
  if fi > rec.n then fi = rec.n end
  while fi > 1 and rec[fi].at > t + 1e-9 do fi = fi - 1 end
  while fi < rec.n and rec[fi + 1].at <= t + 1e-9 do fi = fi + 1 end
  rp.at, rp.frame, rp.t0, rp.t1 = t, fi, t0, t1
  -- The stream up to t: the engine's events are in emission order, and a
  -- judgment carries the moment it was made.
  local n = 0
  for i = 1, e.n do if e.events[i].t <= t + 1e-9 then n = i else break end end
  rp.n = n
  local vs, g = rp.verdicts, self.grader
  for i = #vs, 1, -1 do vs[i] = nil end
  if g and g.verdicts then
    for i = 1, #g.verdicts do
      local v = g.verdicts[i]
      if (v.t or 0) <= t + 1e-9 then vs[#vs + 1] = v end
    end
  end
  rp.rev = rp.rev + 1
  -- The oracle reads as it did then: the medallion, the rotation row and the
  -- coach read Nock.state.sim.plan. Copied INTO the live plan object (its
  -- notes are pooled; PublishPlan writes into it again at the next Start).
  local dst = Nock.state.sim.plan
  local fr = rec[fi]
  if dst and fr.plan then copyPlanInto(fr.plan, dst) end
  return true
end

function Practice:ReplayOff()
  self._replay = nil
  self:ClearSimState(Nock.state)
end

-- Every field the HUD reads off a practice fight, back to idle. Shared by
-- StopFight and by leaving the replay.
function Practice:ClearSimState(st)
  if st.player.casting == castInfo then st.player.casting = nil end
  st.player.autoShotCast = nil
  st.ranged.repeating = false
  st.melee.swingStart, st.melee.swingRemaining = 0, 0
  st.weave.keyHeld, st.weave.keyHeldSince = false, 0
  st.target.rangeZone, st.target.inMelee, st.target.meleeProximity = "TOO_FAR", false, -0.12
  st.target.rangeState, st.target.rangeProg = "LONG", -1
  st._raptorCdOverride = 0
  local raptor = st.cooldowns.Raptor
  if raptor then raptor.startTime, raptor.duration = 0, 0 end
  st.player.rapidFire, st.player.quickShots, st.player.drums, st.player.inLust = false, false, false, false
  st.sim.meleeHaste = 0
  for slot in pairs(SIM_CDS) do
    local s = st.cooldowns[slot]
    if s then s.startTime, s.duration, s.procActive = 0, 0, false end
  end
end

-- THE HUD AT THE SCRUB POSITION. The tick publishes the engine's snapshot
-- into Nock.state, and the HUD's bars read GetTime() against the moments in
-- it (swing start, cast end, cooldown start...). So the frame's snapshot is
-- handed to the tick with every moment inside the fight's hour SHIFTED by
-- (now - scrub): the remaining time on every bar is then exactly what it was
-- at the scrub, and stays so tick after tick. Sentinels (a held proc parked
-- at now + 1e9) and plain numbers (cycle, multipliers, distance) stay put.
local rsnapCast, rsnapProcs, rsnapCd = {}, {}, {}
local function shiftInto(src, dst, off, t0)
  for k, v in pairs(src) do
    if type(v) == "number" and v > t0 - 3600 and v < t0 + 3600 then dst[k] = v + off else dst[k] = v end
  end
end
function Practice:ReplaySnap(sn, now)
  local rp, rec = self._replay, self._planRec
  local fr = rp and rec and rec[rp.frame]
  if not (fr and fr.snap) then return false end
  local src = fr.snap
  local t0 = src.t0 or rp.at
  local off = now - rp.at
  for k in pairs(sn) do sn[k] = nil end
  shiftInto(src, sn, off, t0)
  sn.t0 = src.t0                                  -- the fight's origin, unshifted: the report reads it
  if src.cast then
    for k in pairs(rsnapCast) do rsnapCast[k] = nil end
    shiftInto(src.cast, rsnapCast, off, t0); sn.cast = rsnapCast
  else sn.cast = nil end
  for k in pairs(rsnapProcs) do rsnapProcs[k] = nil end
  if src.procs then shiftInto(src.procs, rsnapProcs, off, t0) end
  sn.procs = rsnapProcs
  for k in pairs(rsnapCd) do rsnapCd[k] = nil end
  if src.cdReady then shiftInto(src.cdReady, rsnapCd, off, t0) end
  sn.cdReady = rsnapCd
  return true
end

-- Scrub by seconds, or jump to the next/previous auto the cast ahead of it
-- delayed (`dir` +1 / -1, `mode` "sec" with `step`, or "clip").
function Practice:ReplayStep(dir, mode, step)
  local rp, e = self._replay, self.engine
  if not (rp and e) then return false end
  if mode == "clip" then
    local best
    for i = 1, e.n do
      local ev = e.events[i]
      if ev.kind == "auto" and (ev.delay or 0) > 0.03 then
        if dir > 0 and ev.t > rp.at + 0.01 and (not best or ev.t < best) then best = ev.t end
        if dir < 0 and ev.t < rp.at - 0.01 and (not best or ev.t > best) then best = ev.t end
      end
    end
    if not best then return false end
    return self:ReplayAt(best)
  end
  return self:ReplayAt(rp.at + dir * (step or 0.25))
end

function Practice:ReplayCommand(arg)
  local rp = self._replay
  if arg == "off" then
    self:ReplayOff()
    self:Print("Practice: replay off.")
    return
  end
  if not rp then
    local rec = self._planRec
    if not (rec and rec.n > 0) or (self.engine and self.engine.fightOn) then
      self:Print("Practice: nothing to replay - stop a fight first.")
      return
    end
    self:ReplayAt(self._stopAt or rec[rec.n].at)
    rp = self._replay
  end
  local ok = true
  if arg == "next" then ok = self:ReplayStep(1, "clip")
  elseif arg == "prev" then ok = self:ReplayStep(-1, "clip")
  elseif arg:match("^[+-]%d") then ok = self:ReplayAt(rp.at + tonumber(arg))
  elseif arg:match("^%d") then ok = self:ReplayAt(rp.t0 + tonumber(arg))
  elseif arg ~= "" then
    self:Print("Practice: replay <secs> | +x | -x | next | prev | off  (wheel over the stage: 0.25 s, Shift 2 s, Ctrl 0.05 s, Alt = next/prev clip)")
    return
  end
  if not ok then self:Print("Practice: no clip that way.") end
  self:Print(("Practice: replay at %.2f s."):format(self._replay.at - self._replay.t0))
end

-- The strip's inputs at the replay moment, in the shape Lookahead gives them.
function Practice:ReplayLookahead(out)
  local rp, rec = self._replay, self._planRec
  if not (rp and rec and rec[rp.frame]) then return nil end
  local fr = rec[rp.frame]
  local now = rp.at
  out.now = now
  out.nextShotAt, out.cycle, out.windup, out.lastShotAt = fr.nextShotAt, fr.cycle, fr.windup, fr.lastShotAt
  out.winAutos, out.streak, out.bestStreak = fr.winAutos, fr.streak, fr.bestStreak
  out.rangedMul, out.meleeReadyAt, out.oppOpen = fr.rangedMul, fr.meleeReadyAt, fr.oppOpen
  out.ttw = (fr.nextShotAt or now) - (fr.windup or 0) - now
  out.plan = fr.plan
  out.weaveAt, out.weaveTtw, out.weaveFits = fr.plan.weave.at or fr.weaveAt, fr.plan.weave.room or fr.weaveRoom, fr.plan.weave.fits
  out.weaveMoveAt = fr.plan.weave.moveAt
  out.procs, out.hold = fr.procs, fr.hold
  local cd = out.cdReady
  if cd == nil then cd = aheadCds; out.cdReady = cd end
  cd.KC, cd.Raptor = fr.kcReadyAt, fr.raptorReadyAt
  local ready = fr.cdReady
  cd.RF = ready and ready.RF or nil
  cd.Pot = ready and ready.Pot or nil
  cd.Drums = ready and ready.Drums or nil
  out.paperSyms = fr.paperSyms
  return out
end

function Practice:Lookahead(out)
  if self._replay and out and self.engine and not self.engine.fightOn then return self:ReplayLookahead(out) end
  local e, cfg = self.engine, self.cfg
  if not (out and e and cfg and Nock.state.sim.fightOn) then return nil end
  local st, now = Nock.state, GetTime()
  out.now = now
  out.nextShotAt = snap.nextShotAt
  out.cycle = snap.cycle
  out.windup = snap.windup
  -- The conveyor projects the paper rotation forward from the last shot, at the
  -- haste that shot went out under.
  out.lastShotAt = snap.lastShotAt
  -- ...and WHERE in the rotation it was, so the projection resumes at the cycle
  -- it actually reached instead of replaying the layout's first one. The
  -- grader's own per-window count, because that is the thing that restarts in
  -- the same places the paper does: at a haste change, and at a new fight.
  out.winAutos = (self.grader and self.grader.win and self.grader.win.autos) or 0
  -- The judgment streak, for the stage's coach row and the header strip. Read
  -- straight off the grader (the same two fields G.Live publishes) rather than
  -- through a G.Live call the conveyor has no other use for: two field reads,
  -- no allocation, and 0/0 before the first fight.
  local gr = self.grader
  out.streak = (gr and gr.streak) or 0
  out.bestStreak = (gr and gr.bestStreak) or 0
  out.rangedMul = snap.rangedMul
  out.meleeReadyAt = snap.meleeReadyAt
  out.oppOpen = e.oppOpen
  out.ttw = (snap.nextShotAt or now) - (snap.windup or 0) - now
  -- WHEN a weave is next possible, the room it has, and whether a WHOLE weave
  -- fits in it: the engine's own answer (E.WeaveWindow), which the conveyor's
  -- gap band and the metronome's gap tick are drawn from. `oppOpen` above is
  -- still published — it is the FAULT gate, and it answers a different question
  -- ("may I go right now").
  --
  -- All three come off the SAME snapshot call. The conveyor used to re-ask the
  -- engine for the third on its own, because this function did not carry it:
  -- two calls at two moments, and a view holding one from each.
  -- ...read off THE PLAN (Core/PracticePlan.lua), which mirrors that snapshot:
  -- one table every surface shares, by reference.
  local plan = st.sim.plan
  out.plan = plan
  if plan then
    out.weaveAt, out.weaveTtw, out.weaveFits = plan.weave.at, plan.weave.room, plan.weave.fits
    out.weaveMoveAt = plan.weave.moveAt
  else
    out.weaveMoveAt = nil
    out.weaveAt, out.weaveTtw, out.weaveFits = snap.weaveAt, snap.weaveRoom, snap.weaveFits
  end
  out.procs = snap.procs
  -- Which of those procs the drill HOLDS up for the whole fight. The engine
  -- parks a held proc at now + 1e9, so without this the strip would render
  -- the sentinel as a remaining time. By reference: the engine's own table,
  -- nil when the drill holds nothing.
  out.hold = e.hold
  local cd = out.cdReady
  if cd == nil then cd = aheadCds; out.cdReady = cd end
  local ready = snap.cdReady
  cd.KC, cd.Raptor = snap.kcReadyAt, snap.raptorReadyAt
  cd.RF = ready and ready.RF or nil
  cd.Pot = ready and ready.Pot or nil
  cd.Drums = ready and ready.Drums or nil
  -- THE PAPER IS THE SCOPE. The symbols this window's notation actually asks
  -- for — the table Step published this tick (the grader's own, cached per
  -- notation string), handed on so the views gate on exactly what
  -- Nock.PaperAllows gates on: the conveyor's green gap tick is a weave nag,
  -- and a paper with no `w` has nothing to nag about.
  out.paperSyms = st.sim.paperSyms
  return out
end

-- Called from Nock:Tick (NOT the Refresh loop — module order there is pairs()
-- order): step the engine, copy its snapshot into Nock.state (the live
-- producers yield on state.sim.active while we're active), then let Core derive
-- swingRemaining/windup, the cooldown remaining/ready pass and the GCD from
-- what we just published. Keys are bound in PracticeKeys (below, in this same
-- file). UI lives in UI/Frame_Practice.lua.
-- THE ORACLE. One table, built here and read everywhere (Core/PracticePlan.lua).
-- Fills the reused `src` from the engine snapshot and the grader; no allocation.
-- Called from Step (every tick, in or out of a fight) and from StopFight, so a
-- strip or a review can never read a plan from a fight that has ended.
function Practice:PublishPlan(state, now)
  local plan = state.sim.plan
  if not (plan and P) then return end
  local e, g, cfg = self.engine, self.grader, self.cfg
  local fightOn = state.sim.fightOn == true and e ~= nil
  local profile = Nock.db and Nock.db.profile or nil
  src.T = Nock.PracticeTimeline
  src.live = fightOn
  src.pulled = fightOn and snap.pulled == true
  src.t0 = fightOn and (snap.t0 or e.t0 or now) or now
  -- ARMED, the strip stands still on the provisional t0 (prePullNow) -- and so
  -- must the plan's window, or its notes fall out of a window that keeps
  -- walking while the fight has not started (the armed icons faded out one by
  -- one, then snapped back at the first press).
  if fightOn and not src.pulled and src.t0 > 0 then src.now = src.t0 else src.now = now end
  local fp = profile and profile.practiceConveyorPast or 2
  local ff = profile and profile.practiceConveyorFuture or 4.5
  local hp, hf = state.sim.horizonPast, state.sim.horizonFuture
  src.past = (hp and hp > fp) and hp or fp
  src.future = (hf and hf > ff) and hf or ff
  src.cycle, src.windup = snap.cycle or 0, snap.windup or 0
  src.nextShotAt, src.lastShotAt = snap.nextShotAt or 0, snap.lastShotAt or 0
  -- A due auto waiting for its wind-up behind a cast: nextShotAt is stale
  -- (the grid's moment, already past) while the engine knows when the shot
  -- will actually go (windupShotAt). The plan's first release is that.
  if snap.windupShotAt and snap.windupShotAt > src.nextShotAt then src.nextShotAt = snap.windupShotAt end
  src.rangedMul = snap.rangedMul or (cfg and cfg.baseRangedMul) or 1
  src.castCorr = (cfg and cfg.castCorr) or 1
  src.msReadyAt, src.arcReadyAt = snap.msReadyAt or 0, snap.arcReadyAt or 0
  -- When the hand is next free -- the running GCD's end, the running cast's
  -- end -- and the GCD itself, for the plan's shot retiming (P.retimeShots).
  src.gcdEnd = ((snap.gcdDur or 0) > 0) and ((snap.gcdStart or 0) + snap.gcdDur) or 0
  src.castEnd = (snap.cast and snap.cast.t1) or 0
  -- ...and the running cast itself: its symbol and when it was pressed, so the
  -- plan can hold the note it is the press of (retimeShots' in-flight claim).
  src.castSym = snap.cast and CAST_SYM[snap.cast.spell] or nil
  src.castStart = snap.cast and snap.cast.t0 or nil
  -- ...and a press the client is holding (queued inside the wind-up; the cast
  -- starts at the release): its symbol and the moment it was pressed, so the
  -- plan keeps that note asked at the press and its GCD from the release.
  local q = e and e.queued or nil
  src.queuedSym = q and CAST_SYM[q.spell] or nil
  src.queuedAt = q and q.at or nil
  src.gcd = (cfg and cfg.gcd) or 1.5
  src.weaveAt, src.weaveRoom, src.weaveFits = snap.weaveAt, snap.weaveRoom, snap.weaveFits
  src.oppOpen = (e and e.oppOpen) or false
  src.meleeReadyAt = snap.meleeReadyAt
  -- How long this player's weave takes (the grader's measured legs; its seed
  -- before any weave has been made): the drawn length of a `w` note.
  src.weaveDur = g and G.LegsNeeded(g) or nil
  src.weaveStepIn = g and G.StepIn(g) or nil
  src.raptorReadyAt = snap.raptorReadyAt or 0
  src.meleeCycle = snap.meleeCycle or 0
  -- Does this fight have cooldowns or procs to show a row for? Held procs, a
  -- Quick Shots roll, a scripted scenario, or a crit roll (an unlocked
  -- scenario keeps the character's, and a crit opens a Kill Command window).
  -- And STICKY: once a cooldown press or a proc has landed in the stream the
  -- row stays for the rest of the fight. It used to ride the strip's items on
  -- a paper drill -- the row came and went as each RF span or KC scrolled
  -- through the view ("blinking in and out", user 2026-08-27).
  local sc = self._fightScenarioTable
  if e and fightOn and not self._cdSeen then
    local n, ev = e.n or 0, e.events
    local from = (self._cdScanN or 0) + 1
    if from > n + 1 then from = 1 end
    for i = from, n do
      local k = ev[i] and ev[i].kind
      if k == "cd" or k == "proc" or k == "kc" then self._cdSeen = true; break end
    end
    self._cdScanN = n
  end
  local ecfg = e and e.cfg or nil
  src.hasCd = e ~= nil and (e.hold ~= nil or snap.quickShotsOn == true
    or (sc ~= nil and sc.events ~= nil and #sc.events > 0)
    or (ecfg ~= nil and ((ecfg.critRanged or 0) > 0 or (ecfg.critMelee or 0) > 0))
    or self._cdSeen == true) or false
  src.paperSyms = state.sim.paperSyms
  src.rowSyms = state.sim.rowSyms
  src.cur, src.pend = g and g.cur or nil, g and g.pend or nil
  -- Notes of cycles not seated yet that were already played on the plan's
  -- word (the grader's pre-play set): projected as HIT, never asked for twice.
  src.prePlayed = g and g.prePlayed or nil
  src.winAutos = (g and g.win and g.win.autos) or 0
  if g and g.win then
    src.lay = G.Layout(g)
    src.notation = g.win.notation
  elseif fightOn and g then
    -- Armed, no window yet: the drill's own paper -- the same resolution
    -- StartFight uses -- so the strip shows what the pull will be graded against.
    local notation, mul, cfg = self:FightPaper()
    -- The string at this haste, resolved on a change only (M.PaperString
    -- allocates; this runs every armed tick).
    if notation ~= self._armedNota or mul ~= self._armedMul then
      self._armedNota, self._armedMul = notation, mul
      local h = self._armedH
      if not h then h = {}; self._armedH = h end
      self._armedStr = M.PaperString(notation, fillPaperH(h, cfg, mul)) or "as"
    end
    src.lay = G.Layout(g, self._armedStr, mul)
    src.notation = notation
  else
    src.lay, src.notation = nil, nil
  end
  P.Build(src, plan)
  if self._planTrace and plan.live then self:TracePlan(plan) end
end

-- THE PLAN TRACE (diagnostic, off unless `/nock practice trace`). One line per
-- build while a fight runs -- the swing inputs, NEXT, the weave window and
-- every weave note -- kept in a ring of the last PLAN_TRACE_N; `/nock practice
-- plandump` opens them in a copybox. Allocates strings per tick, which is why
-- it is a toggle.
local PLAN_TRACE_N = 120
-- Change-driven: a line only when the summary (everything but the clock)
-- differs from the last one, so the ring spans minutes, not a second, and
-- every flip is a pair of adjacent lines. The conveyor appends its own lines
-- (View:TraceStrip) into the same ring, tagged STRIP, so the two can be read
-- against each other.
function Practice:TraceLine(tag, body)
  local ring = self._planRing
  if not ring then ring = { n = 0, at = 0, last = {} }; self._planRing = ring end
  if ring.last[tag] == body then return end
  ring.last[tag] = body
  local cap = self.PLAN_TRACE_N or PLAN_TRACE_N     -- a test may widen the ring
  ring.at = ring.at % cap + 1
  ring[ring.at] = ("%s t=%+.2f %s"):format(tag, GetTime() - (Nock.state.sim.t0 or 0), body)
  if ring.n < cap then ring.n = ring.n + 1 end
end
function Practice:TracePlan(plan)
  local t0 = plan.t0 or 0
  local parts = {}
  local g = self.grader
  parts[#parts + 1] = ("rev=%d next=%s@%s na=%d nsa=%+.2f gcd=%+.2f cast=%+.2f asked=%s mr=%+.2f rr=%+.2f cyc=%.2f wv=%s/%s/%s mv=%s reason=%s"):format(
    plan.rev, tostring(plan.nextSym), plan.nextIdx and ("%+.2f"):format(plan.notes[plan.nextIdx].t0 - t0) or "-",
    plan.nAutos, (src.nextShotAt or 0) - t0,
    (src.gcdEnd or 0) - t0, (src.castEnd or 0) - t0,
    (g and g.askedAt) and ("%+.2f"):format(g.askedAt - t0) or "-",
    (src.meleeReadyAt or 0) - t0, (src.raptorReadyAt or 0) - t0, src.meleeCycle or 0,
    plan.weave.at and ("%+.2f"):format(plan.weave.at - t0) or "-",
    ("%.2f"):format(plan.weave.room or 0), tostring(plan.weave.fits),
    plan.weave.moveAt and ("%+.2f"):format(plan.weave.moveAt - t0) or "-", tostring(plan.reason))
  -- Every note in the window: the shots on the hand's clock and the weaves on
  -- the swing chain. A note that flips between two times from one line to the
  -- next is the stage's "blink".
  local line = {}
  for i = 1, plan.n do
    local nt = plan.notes[i]
    line[#line + 1] = ("%s%d.%d@%+.2f%s%s%s"):format(nt.sym, nt.cycle, nt.idx, nt.t0 - t0,
      nt.state == "pending" and "" or (":" .. nt.state), nt.playable and "" or "!", nt.raptor and "R" or "")
  end
  parts[#parts + 1] = "  " .. table.concat(line, " ")
  self:TraceLine("PLAN ", table.concat(parts, "\n"))
end

function Practice:DumpPlanTrace()
  local ring = self._planRing
  if not (ring and ring.n > 0) then self:Print("Practice: no plan trace yet (/nock practice trace, then fight)."); return end
  local out = {}
  local cap = self.PLAN_TRACE_N or PLAN_TRACE_N
  local start = ring.at - ring.n + 1
  for k = 0, ring.n - 1 do
    local i = (start + k - 1) % cap + 1
    out[#out + 1] = ring[i]
  end
  Nock.UI.ShowCopyBox("PLAN TRACE (" .. ring.n .. " changes, oldest first)\n" .. table.concat(out, "\n"))
end

function Practice:Step(state, now)
  local e = self.engine
  if not e then return end
  local fightOn = state.sim.fightOn
  -- Your feet move the virtual target's distance before the engine steps, so
  -- the zone the tick publishes is the one the step ran on. SetNow first:
  -- SetDistance (and SetMoving's move spans) stamp their edges with the
  -- engine's clock, which would otherwise still read the previous tick.
  E.SetNow(e, now)
  E.SetMoving(e, state.context.moving)
  if fightOn then self:SampleFootwork(now) end
  E.Step(e, now)
  -- A scenario's own length ended the fight (the engine emitted `end`; stopping
  -- is ours). Score it on the tick that crossed the line and let the rest of
  -- this Step publish the between-fights state, exactly as a manual stop would.
  if fightOn and e.ended then
    self:StopFight()
    fightOn = false
  end
  E.Snapshot(e, snap)
  -- THE REPLAY. After Stop, with a scrub position set, the tick publishes the
  -- fight as it stood there (ReplaySnap) instead of the engine's idle state:
  -- every bar on the HUD reads as it did at that moment. `show` gates the
  -- publishing below; `fightOn` still gates the grading and the recording.
  local replay = (not fightOn) and self._replay ~= nil and self:ReplaySnap(snap, now)
  local show = fightOn or replay
  state.sim.replaying = replay and true or false
  -- The fight's real origin. StartFight only ARMS: the engine moves t0 to the
  -- first press, so the panel's clock, the debug log and the report all read it
  -- back from here rather than from the moment Start was clicked. Published
  -- after the stop too, so the report keeps the finished fight's origin.
  state.sim.t0 = snap.t0
  state.sim.pulled = show and snap.pulled or false
  -- No fight, no paper, no scope: the plan empties and the live rotation
  -- engine advises freely again the moment the drill stops.
  if not show then
    state.sim.paperSyms = nil
    state.sim.rowSyms = nil
    self:PublishPlan(state, now)
  end

  local r = state.ranged
  r.swingDuration = snap.cycle
  r.windupRatio   = snap.windup / snap.cycle
  -- Everything below is in-flight state. Between fights the engine keeps its
  -- last values (Step() returns early once fightOn drops), so republishing them
  -- would undo StopFight's cleanup and freeze a cast on screen forever.
  if show then
    r.repeating   = snap.repeating
    r.autoDelay   = snap.lastAutoDelay
    -- swingStart is "the shot lands at swingStart + swingDuration": anchor it on
    -- the engine's next shot so a delayed wind-up shows as a late bar, exactly
    -- as the live SwingTimer would.
    r.swingStart = (snap.repeating or snap.nextShotAt > 0) and (snap.nextShotAt - snap.cycle) or 0
  else
    -- swingStart 0 makes Core skip its swingRemaining derivation, so zero it
    -- here rather than leave the last fight's value on the bar.
    r.swingStart, r.swingRemaining = 0, 0
  end

  state.sim.gcd.start, state.sim.gcd.duration = snap.gcdStart, snap.gcdDur

  local c = show and snap.cast or nil
  if c then
    local id = SPELL_ID[c.spell]
    castInfo.name, castInfo.spellId, castInfo.icon = NAMES[c.spell], id, ICONS[c.spell]
    castInfo.startTime, castInfo.endTime = c.t0, c.t1
    state.player.casting = castInfo
  elseif state.player.casting == castInfo then
    state.player.casting = nil
  end
  if show and snap.windupAt then
    autoInfo.name, autoInfo.spellId, autoInfo.icon = AUTO_NAME, C.SpellID.AUTO_SHOT, AUTO_ICON
    autoInfo.startTime = snap.windupAt
    autoInfo.endTime = snap.windupShotAt or (snap.windupAt + snap.windup)
    state.player.autoShotCast = autoInfo
  else
    state.player.autoShotCast = nil
  end

  local cds = state.cooldowns
  if cds.MS then
    local ms = C.PRACTICE.MULTI_CD
    cds.MS.startTime  = (snap.msReadyAt > now) and (snap.msReadyAt - ms) or 0
    cds.MS.duration   = (snap.msReadyAt > now) and ms or 0
  end
  if cds.Arc then
    local dur = self:ArcaneCd()
    cds.Arc.startTime = (snap.arcReadyAt > now) and (snap.arcReadyAt - dur) or 0
    cds.Arc.duration  = (snap.arcReadyAt > now) and dur or 0
  end

  if show then
    -- Procs the sim owns while it runs: the HUD's proc flags, the melee-haste
    -- magnitude Core feeds ResolveTurret, and the cooldown slots the opener is
    -- graded on. Auras/Cooldowns yield all of these on state.sim.active.
    local pr = snap.procs
    local p = state.player
    p.rapidFire, p.quickShots = pr.RF > 0, pr.QS > 0
    p.drums, p.inLust = pr.Drums > 0, pr.Lust > 0
    state.sim.meleeHaste = (snap.meleeMul - 1) * 100
    local durs = self.cfg.cooldowns
    for slot, key in pairs(SIM_CDS) do
      local s = cds[slot]
      if s then
        local ready = snap.cdReady[key] or 0
        local dur = durs[key] or 0
        s.startTime = (ready > now) and (ready - dur) or 0
        s.duration  = (ready > now) and dur or 0
      end
    end
    -- The Kill Command window glows the slot, the same way a proc buff does on
    -- the live grid — it is what makes the press legal, not the cooldown.
    if cds.KC then cds.KC.procActive = snap.kcUntil > now end
    -- Drums' badge counts CHARGES, not stacks (see Cooldowns' useCharges), and
    -- the live scan is yielded while the sim owns the slot.
    if cds.Drums and self._drumsCharges then cds.Drums.count = self._drumsCharges end

    -- Melee swing, weave hold, zones and Raptor for the coach, the rotation
    -- engine, the shot-bars melee lane and the range bar.
    local m = state.melee
    m.swingDuration = snap.meleeCycle
    m.swingStart = (snap.meleeReadyAt > 0) and (snap.meleeReadyAt - snap.meleeCycle) or 0
    local w = state.weave
    if snap.weaveDownAt and not w.keyHeld then
      w.keyHeld, w.keyHeldSince = true, snap.weaveDownAt
      -- Per-hold breadcrumbs, exactly as WeaveBind's own hook resets them on a
      -- real down edge; WeaveCoach sets them from here.
      w.holdTouchedMelee, w.holdMeleeSec = false, 0
    elseif not snap.weaveDownAt then
      w.keyHeld = false
    end
    local rf = self._rf
    local zone = snap.zone or "FAR"
    local t = state.target
    t.rangeZone       = rf and rf.LEGACY[zone] or "TOO_FAR"
    t.inMelee         = snap.inMelee
    t.meleeProximity  = rf and rf.PROX[zone] or -0.12
    -- Display truth: the bar mapped straight from the distance the drill
    -- knows (the live glide is only an estimator for a distance it lacks).
    t.rangeState, t.rangeProg = M.RangeProg(Nock.RangeEngine, snap.dist, snap.inMelee, self.cfg.weaveRing, self.cfg.meleeRange)
    t.rangeEstimateStale = false
    -- Beyond ~10yd the live bar shows the finding ladder; without a bracket
    -- the view paints a blank bar ("not resolved yet"), so the drill resolves
    -- one from the virtual distance, with the live ladder's own rungs.
    if t.rangeState == "LONG" then
      local rfm = self._rf
      t.rangeBracket = M.LadderBracket(Nock.RangeEngine, self._ladder, snap.dist, self.cfg.shootMax,
        rfm and rfm._hawkEye or 0, rfm and rfm._scatterKnown or false, rfm and rfm.hmName ~= nil)
    else
      t.rangeBracket = nil
    end
    local rap = snap.raptorReadyAt - now
    state._raptorCdOverride = (rap > 0) and rap or 0
    if cds.Raptor then
      cds.Raptor.startTime = (rap > 0) and (snap.raptorReadyAt - self.cfg.raptorCd) or 0
      cds.Raptor.duration  = (rap > 0) and self.cfg.raptorCd or 0
    end
  end

  if fightOn then
    self:FeedGrader()
    -- The open haste window's notation, after the feed so a proc that landed
    -- this tick is already reflected. Assigned only on a change: the HUD's
    -- notation label diffs on the string, and the compare is cheaper than the
    -- repaint it would otherwise provoke.
    local win = self.grader and self.grader.win
    if win and win.notation and win.notation ~= state.sim.notation then
      state.sim.notation = win.notation
    end
    -- ...and the symbols that notation asks for: the plan's rows and the
    -- conveyor's weave metronome gate on it. The grader's own cached table, by
    -- reference — one field write per tick, no allocation.
    state.sim.paperSyms = G.PaperSyms(self.grader)
    -- ...folded into the fight's own set (the rows). Five reads, no allocation.
    do
      local ps, fs = state.sim.paperSyms, self._fightSyms
      if ps and fs then
        if ps.s then fs.s = true end
        if ps.m then fs.m = true end
        if ps.A then fs.A = true end
        if ps.w then fs.w = true end
        if ps.r then fs.r = true end
        state.sim.rowSyms = fs
      end
    end
    -- ...and THE ORACLE, from the grader's seated cycles and this snapshot:
    -- the one table every practice surface reads its advice from.
    self:PublishPlan(state, now)
    if state.sim.plan and state.sim.plan.live then self:RecordFrame(now, state.sim.plan) end
    -- What the plan asks for next, for the grader's LATE rule: an idle GCD is
    -- only late when the oracle had a press due (a held cast is a wait, not
    -- a slip). Read by the NEXT tick's feed, i.e. as it stood before the press.
    local plan = state.sim.plan
    self.grader.askedAt = (plan and plan.nextIdx) and plan.notes[plan.nextIdx].t0 or nil
    -- ...and the oracle itself, by reference: the grader judges a press against
    -- the plan's time for its note (PracticeGrader planTime / planPrePlay).
    self.grader.plan = plan
    -- The grader's measured weave cost feeds the engine's opportunity window,
    -- so WEAVE MISSED is judged against this player's real footwork.
    E.SetLegsNeeded(e, G.LegsNeeded(self.grader))
    -- The demo ghost reads the plan just published and presses for you.
    if self._demo then self:DemoStep(now) end
  end
end

-- The weave key's edges, forwarded by WeaveBind's own button while practice
-- is on (its secure wrapper already blanks the real macro out of combat).
function Practice:OnWeaveEdge(down)
  if not (self:IsActive() and Nock.state.sim.fightOn) then return end
  E.Weave(self.engine, down, down and self.weaveDown or self.weaveUp, GetTime())
end

-- Distance to the virtual target. "move": speed-only dead reckoning — no
-- target position, no facing (run = closing, backpedal = retreating, the live
-- glide's own rule; E.Reckon). "key": the engine synthesises the steps.
function Practice:SampleFootwork(now)
  local e, cfg = self.engine, self.cfg
  if cfg.footwork == "key" then return end
  local speed, runSpeed = 0, nil
  if GetUnitSpeed then speed, runSpeed = GetUnitSpeed("player") end
  local dt = now - (self._lastSample or now)
  E.Reckon(e, speed or 0, dt, runSpeed)
  self._posMode = "reckoning"
  self._lastSample = now
end

-- The pull: the virtual target sits startDistance yards out (seeded into the
-- engine in StartFight, AFTER E.StartFight's Reset); only the sample clock is
-- reset here.
function Practice:PlantTarget()
  self._lastSample = nil
end

-- /nock practice pos — what the sim sees of your footwork.
function Practice:DumpPos()
  local lines = {}
  lines[#lines + 1] = ("pos: mode=%s footwork=%s"):format(tostring(self._posMode or "-"), tostring(self.cfg and self.cfg.footwork or "-"))
  local e = self.engine
  if e then
    local runSpeed = GetUnitSpeed and select(2, GetUnitSpeed("player")) or -1
    lines[#lines + 1] = ("sim: dist %.2f zone %s inMelee %s canShoot %s speed %.1f run %.2f split %.2f"):format(
      e.dist or -1, tostring(e.zone), tostring(e.inMelee), tostring(e.canShoot),
      e.speed or 0, runSpeed or -1, e.dirSplit or self.cfg.dirSplit)
    local now = GetTime()
    lines[#lines + 1] = ("auto: repeating %s windupAt %s nextShot %+.2f grid %+.2f cast %s queued %s gcd %+.2f canShoot %s"):format(
      tostring(e.repeating), e.windupAt and ("%+.2f"):format(e.windupAt - now) or "nil",
      (e.nextShotAt or 0) - now, (e.gridShotAt or 0) - now,
      e.cast and e.cast.spell or "nil", e.queued and e.queued.spell or "nil", (e.gcdEnd or 0) - now, tostring(e.canShoot))
    lines[#lines + 1] = ("melee: on %s ready %+.2f recheck %+.2f raptorQ %s entered %s left %s hold %s"):format(
      tostring(e.meleeOn), (e.meleeReadyAt or 0) - now, (e.meleeRecheckAt or 0) - now, tostring(e.raptorQueued),
      e.enteredMeleeAt and ("%+.2f"):format(e.enteredMeleeAt - now) or "nil",
      e.leftMeleeAt and ("%+.2f"):format(e.leftMeleeAt - now) or "nil", tostring(e.weaveDownAt ~= nil))
  end
  local t = Nock.state.target
  lines[#lines + 1] = ("bar: state %s prog %.3f bracket %s"):format(tostring(t.rangeState), t.rangeProg or -1, tostring(t.rangeBracket))
  Nock.UI.ShowCopyBox(table.concat(lines, "\n"))
end

-- Real combat ends the drill; the key overrides are cleared when combat does.
function Practice:OnCombatChanged(_, inCombat)
  if inCombat and self:IsActive() then
    self:StopFight()
    -- StopFight leaves the override at 0 (between fights the sim still owns
    -- Raptor), but sim.active drops on the next line and no live producer owns
    -- the field: left at 0 it would tell Rotation and ShotPredictor that Raptor
    -- is ready for the whole real fight. Teardown nils it for the same reason.
    Nock.state._raptorCdOverride = nil
    Nock.state.sim.active = false
    Nock.state.demo.hudForceShow = false
    -- The live game gets its swing grid back HERE, not at OnRegenEnabled's
    -- Teardown: the real fight that just started would otherwise run with the
    -- drill's pinned cycle on the auto-shot bar for its whole duration.
    self:ReleaseGrid()
    self._stoppedByCombat = true
    self:Print("Practice: combat — practice stopped, your keys cast for real.")
    Nock:SendMessage("NOCK_PRACTICE_CHANGED")
  end
end

function Practice:OnRegenEnabled()
  if self._stoppedByCombat then
    self._stoppedByCombat = nil
    if self.ClearKeys then self:ClearKeys() end
    -- Teardown, not Stop: sim.active went false at the pull, so Stop's guard
    -- would return immediately and clean nothing.
    self:Teardown()
  end
end

function Practice:OnEnteringWorld()
  if self:IsActive() and not InCombatLockdown() then self:Stop() end
end

function Practice:BuildReport()
  local s = self.lastScore
  if not s then return nil end
  local lines = {}
  lines[#lines + 1] = ("Nock practice report — eWS %.3f, base notation %s, latency %d ms, scenario %s, seed %d")
    :format(self.cfg.ws / self.cfg.baseRangedMul, self._fightNotation or "?", (self.cfg.latency or 0) * 1000,
            self._fightScenario or "?", self._fightSeed or profile("practiceSeed", 1))
  -- The report reads in the review window's own order: the grade and what it is
  -- made of, the three numbers, the fixes, the rotation — and only then the
  -- detail nobody opens unless they are chasing something.
  local cp = s.cyclesOnPaper
  local j = s.judge
  lines[#lines + 1] = ("grade %s \194\183 %d of %d cycles on paper \194\183 fight %s")
    :format(s.grade or "?", cp and cp.ok or 0, cp and cp.total or 0, dashSec(s.fightTime, "%.1fs"))
  if G and G.Summary then lines[#lines + 1] = G.Summary(s) end
  -- The middle number is the review's WEAVES tile, and it reads the same way:
  -- a paper with no weave slot never asked for one, which is not 0/0.
  local weaveTxt = (s.paperWeave == false) and "no weave on paper"
    or ("weaves hit %d/%d"):format(s.weavesTaken or 0, (s.weavesTaken or 0) + (s.weavesMissed or 0))
  -- Clips the PLAN chose (a cast pressed on its word that overran the wind-up:
  -- policy 2, instant first) are not faults, but the shot did go out late.
  local planned = (s.clipsPlanned or 0) > 0
    and (" \194\183 on the plan's word %d (+%d ms)"):format(s.clipsPlanned, s.clipPlannedMs or 0) or ""
  lines[#lines + 1] = ("clips %d (+%d ms)%s \194\183 %s \194\183 best streak %d")
    :format(s.clips or 0, s.clipMs or 0, planned, weaveTxt, s.bestStreak or 0)
  -- One line per fix, in the review's own words: what to change, what it cost,
  -- the cycle to look at and the drill that trains it.
  local an = s.analysis
  for i = 1, (an and #an or 0) do
    local row = an[i]
    local drillId = Ladder and Ladder.DrillFor and Ladder.DrillFor(row.code) or nil
    local drill = drillId and Ladder.ById(drillId) or nil
    lines[#lines + 1] = ("Fix %d: %s (cost %d ms, %d x, cycle %d, drill %s)")
      :format(i, row.advice or row.code or "?", row.ms or 0, row.n or 0, row.cycle or 0,
              drill and drill.name or NONE_MARK)
  end
  -- Paper vs played, cycle by cycle — the same comparison the review window's
  -- ROTATION row draws, off the same pure builder and the same pooled table.
  local TLM = Nock.PracticeTimeline
  if TLM and TLM.Cycles then
    local events, nEv, sc, h = self:TimelineData()
    if events and h then
      self._reportCycles = TLM.Cycles(events, nEv, sc, h, Nock.PracticeModel, self._reportCycles)
      local r = rotationLine(self._reportCycles)
      if r then lines[#lines + 1] = r end
    end
  end
  -- The detail lines, as they always were.
  lines[#lines + 1] = ("rates: auto eff %s \194\183 gcd eff %s \194\183 early %d \194\183 late %d ms")
    :format(dashPct(s.autoEff), dashPct(s.gcdEff), s.early or 0, s.lateMs or 0)
  -- What the grade is made of, in the words the review uses. A cycle is the
  -- stretch from one auto release to the next; it is ON PAPER when every note
  -- the rotation puts in it was played and nothing extra was.
  if j then
    lines[#lines + 1] = ("notes: perfect %d | good %d | late %d | clip %d | missed %d | off %d | best streak %d")
      :format(j.perfect, j.good, j.late, j.clip, j.missed, j.off, s.bestStreak or 0)
  end
  local w = weaveLine(s)
  if w then lines[#lines + 1] = w end
  local o = openerLine(s)
  if o then lines[#lines + 1] = o end
  local k = kcLine(s)
  if k then lines[#lines + 1] = k end
  -- The ORIGIN this report's stamps are relative to: the scorecard's own, not
  -- state.sim.t0. The two are the same during the fight, but the report is
  -- copied long afterwards — and sim.t0 defaults to 0, which is what turned
  -- every line below into an absolute clock the moment it had not been
  -- published. nil here means the fight carried no `pull`: no origin, no stamp.
  local t0 = s.t0
  -- One line per haste window: what the rotation SHOULD have been at that
  -- haste, what was actually played, and what it cost.
  if s.windows and #s.windows > 0 then
    lines[#lines + 1] = "haste windows:"
    for _, win in ipairs(s.windows) do
      local a = (t0 and win.t0) and ("%5.1f"):format(win.t0 - t0) or NONE_MARK
      local b = (t0 and win.t1) and ("%5.1f"):format(win.t1 - t0) or NONE_MARK
      lines[#lines + 1] = ("  %s\226\128\147%s  expected %s  played %s  auto %d%%  gcd %d%%  clips %d")
        :format(a, b, win.notation or "?",
                win.played or NONE_MARK, (win.autoEff or 0) * 100 + 0.5,
                (win.gcdEff or 0) * 100 + 0.5, win.clips or 0)
    end
  end
  -- Every fault, in the order it happened. The ranked ones are already up top
  -- as the fixes — this is the raw list a fix is checked against.
  lines[#lines + 1] = "Faults:"
  for _, v in ipairs(self.lastVerdicts or {}) do
    -- Judgments (kind = "judge") are one grade per paper note, not faults: the
    -- counts line above is their summary, and a line per note would bury the
    -- fight's actual issues.
    if v.kind ~= "judge" and v.code ~= "GOOD" and v.code ~= "WEAVE_OK" then
      local at = t0 and ("%6.2f"):format(v.t - t0) or ("%6s"):format(NONE_MARK)
      if v.did then
        lines[#lines + 1] = ("%s  %-17s you: %s | expected: %s | %s")
          :format(at, v.text, v.did, v.expected or NONE_MARK, v.cost or NONE_MARK)
      else
        lines[#lines + 1] = ("%s  %s"):format(at, v.text)
      end
    end
  end
  return table.concat(lines, "\n")
end

----------------------------------------------------------------------------
-- The stage's style, from the slash line (P3 polish). `/nock practice style`
-- opens a copybox of every lever and its value (paste it back and it is the
-- next default); `style <lever> <value>` sets one; `style reset` clears them
-- all back to the shipped look. The levers themselves are T.STYLE_LEVERS.
----------------------------------------------------------------------------

function Practice:StyleCommand(rest)
  local T = Nock.PracticeTimeline
  local levers = T and T.STYLE_LEVERS
  if not levers then return end
  local prof = Nock.db.profile
  if rest == "" then
    local lines = { "practice stage style  (/nock practice style <lever> <value>, or `style reset`)" }
    for _, L in ipairs(levers) do
      local v = prof[L.key]
      if v == nil then v = L.values[1] end
      lines[#lines + 1] = ("  %-7s %-9s  [%s]  %s"):format(L.lever, v, table.concat(L.values, " | "), L.name)
    end
    local a = prof.practiceColorAuto
    if a then lines[#lines + 1] = ("  auto colour  %.2f %.2f %.2f"):format(a[1] or 0, a[2] or 0, a[3] or 0) end
    Nock.UI.ShowCopyBox(table.concat(lines, "\n"))
    return
  end
  if rest == "reset" then
    for _, L in ipairs(levers) do prof[L.key] = nil end
    Nock:SendMessage("NOCK_VISUALS_CHANGED")
    self:Print("Practice: stage style reset to the shipped look.")
    return
  end
  local lever, value = rest:match("^(%S+)%s+(%S+)$")
  local L = lever and T.STYLE_BY_LEVER[lever]
  if not L then
    self:Print("Practice: /nock practice style <lever> <value>  - levers: " .. (function()
      local n = {}
      for _, x in ipairs(levers) do n[#n + 1] = x.lever end
      return table.concat(n, ", ")
    end)())
    return
  end
  if not L.allowed[value] then
    self:Print(("Practice: style %s takes %s."):format(lever, table.concat(L.values, " | ")))
    return
  end
  prof[L.key] = value
  Nock:SendMessage("NOCK_VISUALS_CHANGED")
  self:Print(("Practice: style %s = %s."):format(lever, value))
end

----------------------------------------------------------------------------
-- The demo ghost (P3 polish): `/nock practice demo` presses the plan's own
-- notes for you -- a shot key at its note, the weave key down at the step-in
-- and up after the hit -- so the stage animates with pops, chips and the ramp
-- while you sit at the Options panel. Deterministic jitter per note key
-- (so the same drill replays the same), one note in twenty skipped so a
-- MISSED is on screen too. Key-only footwork while it runs, so your real feet
-- never fight it; restored when it is switched off or practice ends.
----------------------------------------------------------------------------

local DEMO_EARLY, DEMO_SPREAD, DEMO_SKIP = 0.12, 0.24, 0.95
local DEMO_ACTION = { s = "steady", m = "multi", A = "arcane" }
local DEMO_PULL = { "autoshot" }
local demoDone = {}

local function demoHash(key)
  return ((key * 7919 + 13) % 97) / 97
end

-- `mode`: "human" (the default: jitter and the odd skip, so the pops and the
-- verdicts are on screen) or "perfect" (every note on its moment, none skipped
-- -- any verdict you then see is the engine's, not the ghost's). Calling it
-- with a mode while the demo runs switches the mode; without one, it stops.
function Practice:ToggleDemo(mode)
  if self._demo and mode and mode ~= self._demoMode then
    self._demoMode = mode
    self:Print("Practice: demo now plays " .. mode .. ".")
    return
  end
  if self._demo then
    self._demo = false
    if self.cfg and self._demoFootwork ~= nil then self.cfg.footwork = self._demoFootwork end
    self._demoFootwork = nil
    self:Print("Practice: demo off.")
    return
  end
  if not self:IsActive() then self:Start() end
  self._demo = true
  self._demoMode = mode or "human"
  self._demoPulled, self._demoUpAt = nil, nil
  for k in pairs(demoDone) do demoDone[k] = nil end
  if self.cfg then
    self._demoFootwork = self.cfg.footwork
    self.cfg.footwork = "key"
  end
  if not Nock.state.sim.fightOn then self:StartFight() end
  self:Print(("Practice: demo ON (%s) - the ghost plays the paper; /nock practice demo again to stop, `demo perfect` / `demo human` to switch."):format(self._demoMode))
end

-- A press that did not take is retried once this much later (the note is
-- still pending: the engine was mid-cast or on the GCD when it landed).
local DEMO_RETRY = 0.4

function Practice:DemoStep(now)
  self._fightDemo = true
  if not (self._demo and Nock.state.sim.fightOn) or self._freezeAt then return end
  local e, plan = self.engine, Nock.state.sim.plan
  if not (e and plan and plan.live) then return end
  -- The pull re-seats every note on the real clock: forget what was pressed
  -- against the provisional one.
  local pulled = e.pulled and true or false
  if pulled ~= self._demoPulled then
    self._demoPulled = pulled
    for k in pairs(demoDone) do demoDone[k] = nil end
  end
  -- A hand presses ONE shot at a time, and only when the engine can take it:
  -- no cast running, the GCD free. Pressing a note at its moment while the
  -- previous cast still ran dropped the press, left the note pending, and
  -- filed the NEXT note's press against it a note late -- every Steady of a
  -- 5:5:1:1 came out 1-2 s LATE and the clips cascaded from there.
  local free = (not e.cast) and ((e.gcdEnd or 0) <= now)
  local pressed, weaved = false, false
  -- THE BOW FIRST (2026-08-26). On a weave paper the first note is the weave,
  -- and a ghost that pulled with the weave key never had a swing: the down
  -- macro's /startattack put the sim in melee mode from range, the up-edge's
  -- !Auto Shot armed a shot the NEXT down cancelled before it fired, and with
  -- no swing there was no window -- the ghost mashed the weave key for the
  -- whole fight (the gate: 11 downs, 0 hits, 0 autos in 30 s). A hunter pulls
  -- with the bow; so does the ghost when no shot note is due at the pull.
  if not pulled then
    local shotDue = false
    for i = 1, plan.n do
      local nt = plan.notes[i]
      if nt.state == "pending" and nt.playable and DEMO_ACTION[nt.row] and now >= nt.t0 - DEMO_EARLY then shotDue = true; break end
    end
    if not shotDue then
      E.Press(e, DEMO_PULL, now)
      return
    end
  end
  -- ...and the bow is kept going: the up-edge's !Auto Shot re-arms it, but a
  -- swing that was cancelled (a down made from range) is re-armed here as a
  -- player would, the moment the feet are out and nothing is held.
  if pulled and not e.repeating and not e.weaveDownAt and not e.meleeOn and e.canShoot and not e.cast then
    E.Press(e, DEMO_PULL, now)
  end
  for i = 1, plan.n do
    local nt = plan.notes[i]
    if nt.state == "pending" and nt.playable and not nt.inflight then
      local h = demoHash(nt.key)
      local off = (h - 0.5) * DEMO_SPREAD
      if self._demoMode == "perfect" then h, off = 0, 0 end
      local done = demoDone[nt.key]
      -- ...and a press that did not take is retried after DEMO_RETRY.
      local due = (done == nil) or (done ~= true and now - done >= DEMO_RETRY)
      if nt.row == "w" then
        -- Down at the step-in (the engine walks in over cfg.stepTime), held
        -- past the hit the plan projects, then up. ONE weave at a time, and
        -- only once there is a swing to weave inside: a second down while the
        -- key is held is what cancelled the auto.
        -- ...and never before the NOTE's own walk: the window's move-in is
        -- the swing's answer alone, the note's time also stands behind the
        -- cast in front of it (retimeWeaves). Walking at the window's word
        -- with a Multi just pressed cancelled the Multi and cost the weave
        -- (5:5:1:1 3w at its pin, 2026-08-26).
        local stepT = e.cfg.stepTime or 0.3
        local at = nt.t0 - stepT           -- the note is the HIT; the ghost's legs are cfg.stepTime
        if plan.weave.moveAt and plan.weave.moveAt > at then at = plan.weave.moveAt end
        at = at + off
        -- ...and never one that cannot be back out before the wind-up: a
        -- weave started with the shot due mid-hold is the dead zone, and the
        -- ghost's first move used to be exactly that (down at 0.3 s, the
        -- first release at 0.6 s). Inside the wind-up it waits for the
        -- release; the next cycle is all room.
        local ns = e.nextShotAt or 0
        local weaveLen = stepT * 2 + 0.2      -- in, the hit, out, and a margin for the retry pulse
        -- An OVERDUE shot (held behind a cast: nextShotAt is the grid's
        -- time, the wind-up starts at the cast's end) is no room at all --
        -- read as infinite room the ghost stepped in 90 ms before the
        -- release and stood in the dead zone for a second (2026-08-26).
        local room = (ns > now) and (ns - (e.windup or 0.5) - now) or 0
        -- ...and on a notch: the hit lands a step in from the down, and the
        -- release right after it is free only when a retry check falls on
        -- the swing's ready moment (Nock.ReleaseFreeIn). A down made a
        -- little later lands the hit just before that notch -- short legs
        -- AND no re-arm cost, which is what the grader calls a clean weave.
        local aligned = true
        if ns > now then
          local rem = ns - (now + stepT + (e.cfg.latency or 0) + 0.03)
          local freeIn = (Nock.ReleaseFreeIn and rem > 0) and Nock.ReleaseFreeIn(rem, e.cfg.rearmPulse) or 0
          aligned = freeIn <= 0.06 or freeIn >= (e.cfg.rearmPulse or 0.5) - 0.06
        end
        -- ...but never at the note's expense: past a short grace the ghost
        -- goes on the plan's word and pays the notch instead of the LATE.
        if not aligned and now >= at + 0.12 then aligned = true end
        -- ...never a weave more than a beat behind its note (a human skips
        -- it), and never a TIGHT one: the paper asks, the ghost's legs are
        -- fixed and would only cancel the next cast.
        -- ...and never with a cast of its own still running: moving cancels
        -- it. The plan's note stands behind its ESTIMATE of the cast's end,
        -- and the real Multi ended 80 ms later (the press lands a tick after
        -- the ask) -- the ghost walked on the estimate and cancelled the
        -- Multi every period (5:5:1:1 3w at its pin, 2026-08-26).
        local casting = e.cast ~= nil and (e.cast.t1 or 0) > now
        if rawget(_G, "NOCK_PLAN_DBG") and now >= at - 0.05 and now <= nt.t0 + 0.35 then
          print(("GHOSTW %.2f k=%s note=%.2f at=%.2f due=%s tight=%s weaved=%s down=%s casting=%s ns=%.2f room=%.2f need=%.2f aligned=%s"):format(
            now - (plan.t0 or 0), tostring(nt.key), nt.t0 - (plan.t0 or 0), at - (plan.t0 or 0), tostring(due), tostring(nt.tight),
            tostring(weaved), tostring(e.weaveDownAt ~= nil), tostring(casting), ns - (plan.t0 or 0), room == math.huge and 99 or room, weaveLen, tostring(aligned)))
        end
        if due and now >= at and now <= nt.t0 + 0.3 and not nt.tight and not weaved and not e.weaveDownAt and not casting and ns > 0 and room >= weaveLen and aligned then
          demoDone[nt.key] = true
          weaved = true
          if h <= DEMO_SKIP then
            E.Weave(e, true, self.weaveDown, now)
            -- Up the moment the hit lands (DemoStep watches the stream for
            -- it), and no later than a full step in, a pulse and out.
            self._demoWeaveN = e.n
            self._demoUpAt = now + (e.cfg.stepTime or 0.3) + (e.cfg.meleeRetryPulse or 0.5) + 0.4
          end
        end
      elseif not pressed then
        local act = DEMO_ACTION[nt.row]
        if act and due and now >= nt.t0 + off then
          if h > DEMO_SKIP then
            demoDone[nt.key] = true            -- the deliberate miss (human mode)
          elseif free then
            demoDone[nt.key] = now
            E.Press(e, { act }, now)
            pressed = true
          end
        end
      end
    end
  end
  if self._demoUpAt then
    local hit = false
    for i = (self._demoWeaveN or 0) + 1, e.n do
      if e.events[i].kind == "melee" then hit = true; break end
    end
    -- The grader's own rule (ADVICE.REARM): release when the auto bar is
    -- full "or at the next retry notch" -- the re-arm's checks pulse from the
    -- up-edge, so an up timed for a check to land exactly when the swing is
    -- ready costs nothing (Nock.ReleaseCost) and needs no long hold (the
    -- other rule: short legs). After the hit the ghost releases at the next
    -- free notch; the cap stands.
    local up = false
    if hit then
      local lat = e.cfg.latency or 0
      local rem = (e.nextShotAt or 0) - (now + lat)
      if rem <= 0.02 then up = true
      else
        local freeIn = (Nock.ReleaseFreeIn and Nock.ReleaseFreeIn(rem, e.cfg.rearmPulse)) or 0
        -- A notch within a short hold is worth waiting for; a longer wait
        -- would make the step-out leg the grader's WEAVE SLOW.
        if freeIn <= 0.02 or freeIn > 0.08 then up = true
        elseif now + freeIn < self._demoUpAt then self._demoUpAt = now + freeIn end
      end
    end
    if up or now >= self._demoUpAt then
      self._demoUpAt, self._demoWeaveN = nil, nil
      E.Weave(e, false, self.weaveUp, now)
    end
  end
end

-- /nock practice [start|stop|fight|report|timeline|scenarios|lesson|ladder|ladder reset|keys|pos|debug|debuglog|trace|plandump|style|demo [perfect|human]|freeze|reset]
function Practice:Command(arg)
  arg = (arg or ""):lower()
  local ladderArg = arg:match("^ladder%s*(.-)%s*$")
  if ladderArg == "reset" then
    self:ResetLadder()
    return
  elseif ladderArg == "" then
    -- The ladder lives in the lesson window's side panel, so this opens that.
    -- Toggle(true), not the toggle MESSAGE: typing the command with the window
    -- already open must not close it.
    self:PushLadder()
    -- The workbench's Ladder page when there is one; the lesson window's
    -- side ladder otherwise.
    local wb = Nock:GetModule("PracticeWorkbench", true)
    local v = Nock:GetModule("PracticeLessonView", true)
    if wb and wb.pages and wb.pages.ladder then
      if wb.Open then wb:Open() end
      wb:Select("ladder")
    elseif v and v.Toggle then v:Toggle(true) else Nock:SendMessage("NOCK_PRACTICE_LESSON_TOGGLE") end
    local st = self:LadderState()
    local d = Ladder and Ladder.ById(st.current)
    if d then self:Print(("Practice: drill ladder — current %s (%s)."):format(d.name, d.pass and d.pass.text or "-")) end
    return
  elseif ladderArg then
    self:Print("Practice: /nock practice ladder [reset]")
    return
  end
  if arg == "timeline" then
    Nock:SendMessage("NOCK_PRACTICE_TIMELINE_TOGGLE")
  elseif arg == "scenarios" or arg == "scenario" then
    Nock:SendMessage("NOCK_PRACTICE_SCENARIOS_TOGGLE")
  elseif arg == "lesson" then
    Nock:SendMessage("NOCK_PRACTICE_LESSON_TOGGLE")
  elseif arg == "reset" then
    Nock:SendMessage("NOCK_PRACTICE_RESET_POS")
    self:Print("Practice: windows re-centred.")
  elseif arg == "debug" then
    self._debug = not self._debug
    if self._debug then self._debugLog = {} end
    self:Print("Practice: event debug " .. (self._debug and "ON — capturing every engine event; /nock practice debuglog opens the copybox" or "off"))
  elseif arg == "debuglog" then
    self:ShowDebugLog()
  elseif arg == "trace" then
    self._planTrace = not self._planTrace
    if self._planTrace then self._planRing = nil end
    self:Print("Practice: plan trace " .. (self._planTrace and "ON - /nock practice plandump opens the copybox" or "off"))
  elseif arg == "plandump" then
    self:DumpPlanTrace()
  elseif arg == "style" or arg:match("^style%s") then
    self:StyleCommand(arg:match("^style%s*(.-)%s*$") or "")
  elseif arg == "demo" or arg == "demo perfect" or arg == "demo human" then
    self:ToggleDemo(arg:match("^demo%s+(%a+)$"))
  elseif arg == "icons" then
    local wb = Nock:GetModule("PracticeWorkbench", true)
    Nock.UI.ShowCopyBox(wb and wb.IconDiag and wb:IconDiag() or "no workbench")
  elseif arg == "replay" or arg:match("^replay%s") then
    self:ReplayCommand(arg:match("^replay%s*(.-)%s*$") or "")
  elseif arg == "focus" then
    if not self:IsActive() then self:Start() end
    Nock:PracticeBinding("focus")
  elseif arg == "expert" then
    if not self:IsActive() then self:Start() end
    Nock:PracticeBinding("expert")
  elseif arg == "freeze" then
    if self._freezeAt then
      self._freezeAt = nil
      self:Print("Practice: stage unfrozen.")
    else
      self._freezeAt = GetTime()
      self:Print("Practice: stage FROZEN for a screenshot - /nock practice freeze again to release.")
    end
  elseif arg == "report" then
    local text = self:BuildReport()
    if text then Nock.UI.ShowCopyBox(text) else self:Print("Practice: no fight to report yet.") end
  elseif arg == "keys" then
    self:DumpKeys()
  elseif arg == "pos" then
    self:DumpPos()
  elseif arg == "fight" or arg == "start" then
    if not self:IsActive() then self:Start() end
    if Nock.state.sim.fightOn then self:StopFight() else self:StartFight() end
  elseif arg == "stop" then
    self:Stop()
  else
    -- Bare `/nock practice`: on when off; when on but the workbench was closed
    -- by hand, bring the window back rather than turning practice off (the
    -- window is a view, not the mode); on with the window up, off.
    local wb = Nock:GetModule("PracticeWorkbench", true)
    if self:IsActive() and wb and wb.IsOpen and not wb:IsOpen() then Nock:SendMessage("NOCK_PRACTICE_OPEN")
    elseif self:IsActive() then self:Stop() else self:Start() end
  end
end

----------------------------------------------------------------------------
-- PracticeKeys: your real keys press inert Nock buttons while practice is
-- on. Each wanted spell is found on the action bars (slot -> hotkey, the
-- inverse of BindCheck's lookup), overridden with SetOverrideBindingClick
-- onto a SecureActionButton that feeds the engine out of combat and, via a
-- secure wrap checking PlayerInCombat(), becomes "/click <your button>" in
-- combat so a stray mob never leaves you with dead keys.
----------------------------------------------------------------------------

local WANTED = {
  { name = "steady", id = C.SpellID.STEADY_SHOT },
  { name = "multi",  id = C.SpellID.MULTI_SHOT },
  { name = "arcane", id = C.SpellID.ARCANE_SHOT },
  -- The start-attack key: a bar slot that only arms the auto ("/cast !Auto
  -- Shot", "/startattack", or Auto Shot itself). It is bound like the shots so
  -- the pull and the ranged/melee switch reach the sim. DetectKeys registers
  -- it only for a slot that names no shot.
  { name = "autoshot", id = C.SpellID.AUTO_SHOT },
  -- Cooldown keys (phase 5): taken over like the shot keys so the opener is
  -- graded from the real binds and nothing real fires during a drill.
  { name = "rf",    id = C.SpellID.RAPID_FIRE },
  { name = "spec",  id = C.SpellID.BESTIAL_WRATH },
  { name = "drums", item = C.DRUMS.BATTLE_ITEM },
  { name = "pot",   item = C.PRACTICE.HASTE_POT_ITEM },
  { name = "t1",    slot = 13 },
  { name = "t2",    slot = 14 },
}

local WANTED_BY_NAME = {}
for _, w in ipairs(WANTED) do WANTED_BY_NAME[w.name] = w end

-- The proc keys (user, 2026-08-27: "temporary binds for stuff like BL, Haste
-- Pot, Drums, DST proc"): practice-only binds that pop a proc on the sim the
-- way a palette tile click does (off -> up -> held for the fight -> off).
-- Bound in ApplyKeys with the rotation keys -- so only while practice is on,
-- never in combat, cleared with them -- onto plain buttons; outside practice
-- the keys are the game's. Kill Command is left out: the crits open it.
Practice.PROC_KEYS = {
  { name = "Lust",  label = "Bloodlust / Heroism",       hint = "+30% haste, 40 s" },
  { name = "Drums", label = "Drums of Battle",           hint = "haste rating, 30 s" },
  { name = "Pot",   label = "Haste Potion",              hint = "haste rating, 15 s" },
  { name = "DST",   label = "Dragonspine Trophy proc",   hint = "haste rating, 10 s" },
  { name = "RF",    label = "Rapid Fire",                hint = "+40% ranged haste, 15 s" },
  { name = "QS",    label = "Quick Shots proc",          hint = "+15% ranged haste, 12 s" },
}
local PROC_KEY_BY_NAME = {}
for _, k in ipairs(Practice.PROC_KEYS) do PROC_KEY_BY_NAME[k.name] = k end

-- What a WANTED entry is called when detection has nothing to show: the spell
-- or item name when the client has it cached, otherwise the id itself.
local function wantedLabel(w)
  if w.id then return spellName(w.id) or ("spell " .. tostring(w.id)) end
  if w.item then
    return itemName(w.item) or ("item " .. tostring(w.item))
  end
  if w.slot then return "trinket slot " .. tostring(w.slot) end
  return "?"
end

-- Slot -> the binding names that may drive it. Dominos keeps the first bar on
-- Blizzard's ACTIONBUTTONn and names the rest DominosActionButton<slot>.
local function bindingNamesFor(slot)
  local out = { "CLICK DominosActionButton" .. slot .. ":HOTKEY" }
  if slot <= 12 then out[#out + 1] = "ACTIONBUTTON" .. slot
  elseif slot >= 61 and slot <= 72 then out[#out + 1] = "MULTIACTIONBAR1BUTTON" .. (slot - 60)
  elseif slot >= 49 and slot <= 60 then out[#out + 1] = "MULTIACTIONBAR2BUTTON" .. (slot - 48)
  elseif slot >= 25 and slot <= 36 then out[#out + 1] = "MULTIACTIONBAR3BUTTON" .. (slot - 24)
  elseif slot >= 37 and slot <= 48 then out[#out + 1] = "MULTIACTIONBAR4BUTTON" .. (slot - 36)
  end
  return out
end

local BLIZZ_FRAME = {
  ACTIONBUTTON = "ActionButton", MULTIACTIONBAR1BUTTON = "MultiBarBottomLeftButton",
  MULTIACTIONBAR2BUTTON = "MultiBarBottomRightButton", MULTIACTIONBAR3BUTTON = "MultiBarRightButton",
  MULTIACTIONBAR4BUTTON = "MultiBarLeftButton",
}

-- The real button a binding name drives, for the in-combat "/click" fallback.
local function buttonFor(bindingName)
  local clicked = bindingName:match("^CLICK%s+([^:]+)")
  if clicked then return clicked end
  local prefix, n = bindingName:match("^(.-BUTTON)(%d+)$")
  local frame = prefix and BLIZZ_FRAME[prefix]
  return frame and (frame .. n) or nil
end

-- EVERY key that presses a slot, in preference order: both of GetBindingKey's
-- returns (a binding may carry two), for every binding name that can drive the
-- slot (Dominos' CLICK name first, then Blizzard's). A hunter who keeps the
-- same macro on four bars presses four different keys for one shot, and every
-- one of them has to reach the sim — binding only the first left the mash key
-- casting for real mid-drill. Dupes dropped: the Dominos and Blizzard names of
-- one slot often report the same key.
local function keysForSlot(slot, out)
  out = out or {}
  if not GetBindingKey then return out end
  for _, name in ipairs(bindingNamesFor(slot)) do
    local button = buttonFor(name)
    local k1, k2 = GetBindingKey(name)
    for i = 1, 2 do
      local key = (i == 1) and k1 or k2
      if key and key ~= "" then
        local dup = false
        for j = 1, #out do
          if out[j].key == key then dup = true break end
        end
        if not dup then out[#out + 1] = { key = key, button = button } end
      end
    end
  end
  return out
end

-- Add a slot's keys to an action's key list (the dump reads it); primary first,
-- no repeats.
local function appendKeys(entry, slotKeys)
  entry.keys = entry.keys or {}
  for i = 1, #slotKeys do
    local key, dup = slotKeys[i].key, false
    for j = 1, #entry.keys do
      if entry.keys[j] == key then dup = true break end
    end
    if not dup then entry.keys[#entry.keys + 1] = key end
  end
end

local function macroBody(slot)
  local text = GetActionText and GetActionText(slot)
  if not text or not GetMacroBody then return nil end
  return GetMacroBody(text)
end

-- What a rotation key may do in the sim: its shot, the auto re-arm and a
-- stopcasting. Everything else a shot macro carries is weave-key business.
local ROTATION_ACTIONS = { steady = true, multi = true, arcane = true, autoshot = true,
                           stopcasting = true, startattack = true,
                           -- Off-GCD cooldowns and Kill Command: pressed from
                           -- the rotation keys' own macros, not the weave key.
                           rf = true, spec = true, t1 = true, t2 = true,
                           drums = true, pot = true, killcommand = true }

function Practice:DetectKeys()
  local names = {}
  for _, w in ipairs(WANTED) do
    local n = w.id and spellName(w.id)
    if n then names[n:lower()] = w.name end
    if w.item then
      -- Not cached yet: the /use <slot> and action-id paths below still find
      -- the key, so a missing name only costs a macro that spells it out.
      local iname = itemName(w.item)
      if iname then names[iname:lower()] = w.name end
    end
  end
  names[(spellName(C.SpellID.AUTO_SHOT) or "auto shot"):lower()] = "autoshot"

  local keys = {}
  -- Whether the slot currently holding the autoshot key NAMES the auto
  -- ("/cast !Auto Shot") rather than merely starting an attack ("/startattack"):
  -- a named one always wins, whichever slot order they came in.
  local autoshotNamed = false
  local byId, byItem = {}, {}
  for _, w in ipairs(WANTED) do
    if w.id then byId[w.id] = w.name end
    if w.item then byItem[w.item] = w.name end
  end
  -- The trinkets actually equipped: both their item ids (a trinket dragged
  -- straight onto the bar) and their names (a "/use <name>" macro) resolve to
  -- the slot press the opener is graded on, alongside E.ParseMacro's own
  -- "/use 13|14" numeric path.
  for _, w in ipairs(WANTED) do
    if w.slot then
      local id = GetInventoryItemID and GetInventoryItemID("player", w.slot)
      if id then byItem[id] = w.name end
      local iname = itemName(GetInventoryItemLink and GetInventoryItemLink("player", w.slot))
      if iname then names[iname:lower()] = w.name end
    end
  end
  local overrides = profile("practiceKeys", {})
  -- The flat bind list ApplyKeys walks: one entry per (slot, key), so every
  -- key that presses a rotation slot is taken over, not just the first one
  -- detection happened to see. Deduped by key — the lowest slot wins it.
  local bindings, byKey = {}, {}
  for slot = 1, 120 do
    if HasAction and HasAction(slot) and GetActionInfo then
      local kind, id = GetActionInfo(slot)
      local actions, unknown = {}, {}
      if kind == "spell" and byId[id] then
        actions[1] = byId[id]
      elseif kind == "item" and byItem[id] then
        actions[1] = byItem[id]
      elseif kind == "macro" then
        E.ParseMacro(macroBody(slot), names, actions, unknown)
        -- A rotation key replays its shot lines, the auto re-arm and a
        -- range-aware /startattack (Auto Shot at range). /stopattack, Raptor
        -- and the poke belong to the weave key.
        local kept = {}
        for _, a in ipairs(actions) do
          if ROTATION_ACTIONS[a] then kept[#kept + 1] = a else unknown[#unknown + 1] = "(weave-only) " .. a end
        end
        actions = kept
      end
      -- A start-attack key: a slot that arms the auto (`/cast !Auto Shot`,
      -- `/startattack`) and names NO shot is a key in its own right — it is
      -- how the pull is made and how the melee/ranged auto is switched back.
      -- A slot that also names a shot must not register as the autoshot key:
      -- every shot macro carries its own `!Auto Shot` line, and that line is
      -- part of the shot press, not a separate binding.
      --
      -- The two ways to arm are not equal, so they are counted apart:
      --   * NAMED (`/cast !Auto Shot`) — unambiguous, and it wins over any
      --     start-attack-only slot however the bars are ordered.
      --   * `/startattack` alone — only when the slot names NOTHING else at
      --     all (`#unknown == 0`). `/cast Hunter's Mark` + `/startattack` is a
      --     pull macro, not the auto key: binding it would send every Mark
      --     press into the sim as a pull and take the key off the real one.
      local namesShot, namesAuto, startsAttack = false, false, false
      for _, a in ipairs(actions) do
        if a == "steady" or a == "multi" or a == "arcane" then namesShot = true
        elseif a == "autoshot" then namesAuto = true
        elseif a == "startattack" then startsAttack = true end
      end
      local armsAuto = namesAuto or (startsAttack and #unknown == 0)
      -- A slot can name several wanted spells (a `[mod]Multi-Shot` /
      -- `[nomod]Arcane Shot` macro): register the slot's key under EVERY
      -- action it names, not just the first, so a dedicated button for one
      -- spell doesn't shadow the only binding for another. Resolve the keys
      -- once per slot; ascending slot order means the lowest slot wins the
      -- PRIMARY (`keys[a].key`, what the opener, the footer and the dump head
      -- with) — every other key still joins `keys[a].keys` and the bind list.
      local slotKeys, resolved
      for _, a in ipairs(actions) do
        if a ~= "autoshot" and a ~= "stopcasting" then
          if not resolved then slotKeys = keysForSlot(slot); resolved = true end
          local first = slotKeys[1]
          if first then
            if not keys[a] then
              keys[a] = { key = first.key, slot = slot, button = first.button,
                          actions = actions, unknown = unknown, keys = {} }
            end
            appendKeys(keys[a], slotKeys)
          end
        end
      end
      -- A named slot may take the key off a start-attack-only one that got
      -- there first; nothing ever displaces a named one. Either way both
      -- slots' keys stay listed — both really do arm the auto.
      if armsAuto and not namesShot then
        if not resolved then slotKeys = keysForSlot(slot); resolved = true end
        local first = slotKeys[1]
        if first then
          local cur = keys.autoshot
          if not (cur and (autoshotNamed or not namesAuto)) then
            keys.autoshot = { key = first.key, slot = slot, button = first.button,
                              actions = actions, unknown = unknown, keys = cur and cur.keys or {} }
            autoshotNamed = namesAuto
          end
          appendKeys(keys.autoshot, slotKeys)
        end
      end
      -- Which slots the drill takes the keys off: the ones that name a wanted
      -- shot or cooldown, plus the auto-arming slots the rule above accepts.
      -- A `/cast Hunter's Mark` + `/startattack` pull macro names neither, so
      -- its key is left alone exactly as before.
      local bindable = armsAuto and not namesShot
      if not bindable then
        for _, a in ipairs(actions) do
          if a ~= "autoshot" and WANTED_BY_NAME[a] then bindable = true break end
        end
      end
      if bindable then
        if not resolved then slotKeys = keysForSlot(slot); resolved = true end
        for i = 1, #slotKeys do
          local key = slotKeys[i].key
          if not byKey[key] then
            local e = { key = key, button = slotKeys[i].button, slot = slot, actions = actions }
            byKey[key] = e
            bindings[#bindings + 1] = e
          end
        end
      end
    end
  end
  -- A typed override speaks for its key alone: it replays the one action it
  -- names and has no bar button behind it, so ApplyKeys builds the fallback
  -- macro for it.
  for name, key in pairs(overrides) do
    if key and key ~= "" then
      keys[name] = keys[name] or { actions = { name }, unknown = {}, keys = {} }
      keys[name].key = key
      local e = byKey[key]
      if e then
        e.actions, e.button, e.slot = { name }, nil, nil
      else
        e = { key = key, actions = { name } }
        byKey[key] = e
        bindings[#bindings + 1] = e
      end
    end
  end
  self.keys, self.bindings = keys, bindings
  return keys, bindings
end

local WRAP_ONCLICK = [[
  if PlayerInCombat() then
    self:SetAttribute("type", "macro")
    self:SetAttribute("macrotext", self:GetAttribute("combatMacro"))
  else
    self:SetAttribute("type", nil)
  end
]]

local buttons = {}

local function ensureButton(i)
  if buttons[i] then return buttons[i] end
  local name = "NockPracticeBtn" .. i
  local b = CreateFrame("Button", name, nil, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyDown", "AnyUp")
  SecureHandlerWrapScript(b, "OnClick", b, WRAP_ONCLICK)
  -- RegisterForClicks fires on BOTH edges, so feed the engine on exactly the
  -- edge the client would have cast on: press when ActionButtonUseKeyDown is
  -- set, release when it isn't (_nockUseDown, stamped in ApplyKeys). nil means
  -- the button was never armed, and `false == nil` is false, so it stays inert.
  b:HookScript("OnClick", function(self, _, down)
    if down ~= self._nockUseDown or not Nock.state.sim.active then return end
    local actions = self._nockActions
    if actions then Practice:OnKey(actions) end
  end)
  buttons[i] = b
  return b
end

local owner

local procButtons = {}

-- A proc key's press: the palette tile's left-click cycle, from the keyboard.
-- Inert between fights (there is no engine to pop it on) and on a proc the
-- scenario holds.
function Practice:ProcKeyPress(name)
  if not (self:IsActive() and Nock.state.sim.fightOn) then return end
  local st = self:ProcState(name)
  if st == "held" then return end
  local mode = (st == "off" and "on") or (st == "up" and "perm") or "off"
  self:ProcMode(name, mode)
end

local function ensureProcButton(name)
  if procButtons[name] then return procButtons[name] end
  local b = CreateFrame("Button", "NockPracticeProcBtn" .. name, nil)
  b:RegisterForClicks("AnyDown")
  b._nockProc = name
  b:SetScript("OnClick", function(self) Practice:ProcKeyPress(self._nockProc) end)
  procButtons[name] = b
  return b
end

-- What the Keys page shows for a proc key: its bind, and the rotation action
-- that already holds that key when it does (the rotation wins; the page says
-- `in use by steady`).
function Practice:ProcKeyState(name)
  local keys = profile("practiceProcKeys", {})
  local key = keys[name]
  if key == "" then key = nil end
  local clash = key and self._keyTaken and self._keyTaken[key]
  if clash == name then clash = nil end
  return { override = key, clash = clash, hint = PROC_KEY_BY_NAME[name] and PROC_KEY_BY_NAME[name].hint }
end

-- What the Keys page shows for the rotation keys: one record per wanted
-- ability -- its label, every key detection found on the bars (shortened,
-- comma-joined), and the typed override. Built on demand, never per tick.
local KEYROWS_SKIP = { drums = true, pot = true, t1 = true, t2 = true }
function Practice:KeyRows()
  local keys = self:DetectKeys()
  local overrides = profile("practiceKeys", {})
  local out = {}
  for _, w in ipairs(WANTED) do
    -- The trinkets, the haste potion and the drums are proc keys on the page
    -- (user, 2026-08-27: "we got this covered in proc keys"); their bar
    -- detection and Options overrides still grade the opener.
    local k = (not KEYROWS_SKIP[w.name]) and keys[w.name] or nil
    local det = {}
    if k then
      local list = (k.keys and #k.keys > 0) and k.keys or { k.key }
      for i = 1, #list do
        local kk = list[i]
        kk = type(kk) == "table" and kk.key or kk
        if kk then det[#det + 1] = Practice.ShortKey(kk) or kk end
      end
    end
    local over = overrides[w.name]
    if over == "" then over = nil end
    if not KEYROWS_SKIP[w.name] then
      out[#out + 1] = { name = w.name, label = wantedLabel(w), detected = table.concat(det, ", "), override = over }
    end
  end
  return out
end

-- THE KEY ON A STAGE ROW (v3 P3). The row label says what to press: the
-- primary key bound to the row's ability, shortened for a 88 px gutter.
-- `cd` has no single key; a row with no key at all reads NO KEY in the view.
local ROW_ACTION = { auto = "autoshot", s = "steady", m = "multi", A = "arcane" }
local SHORT_KEY = {
  { "SHIFT%-", "S-" }, { "CTRL%-", "C-" }, { "ALT%-", "A-" },
  { "MOUSEWHEELUP", "MWU" }, { "MOUSEWHEELDOWN", "MWD" }, { "MOUSE", "MB" }, { "BUTTON", "MB" },
  { "NUMPAD", "N" },
}
function Practice.ShortKey(str)
  if not str or str == "" then return nil end
  local out = str
  for i = 1, #SHORT_KEY do out = out:gsub(SHORT_KEY[i][1], SHORT_KEY[i][2]) end
  return out
end
function Practice:RowKey(row)
  if row == "w" then
    local p = Nock.db and Nock.db.profile
    if p and p.weaveBindEnabled == true and (p.weaveBindKey or "") ~= "" then return Practice.ShortKey(p.weaveBindKey) end
    return nil
  end
  local action = ROW_ACTION[row]
  if not action then return nil end
  if not self.keys then self:DetectKeys() end
  local k = self.keys and self.keys[action]
  return k and Practice.ShortKey(k.key) or nil
end

-- THE ROWS BEFORE A FIGHT (v3 P3). The stage shows the picked scenario's rows
-- the moment it is picked, not at Start: the paper the next fight will be
-- graded against (FightPaper), its abilities in row order, and a `cd` row when
-- the scenario holds procs, rolls Quick Shots or runs a script. Fills `out`
-- in place, returns the count.
function Practice:IdleRows(out)
  local n = 1
  out[1] = "auto"
  local notation = self:FightPaper()
  local syms = (G and G.Syms and M) and G.Syms(M, notation) or nil
  if syms then
    if syms.s then n = n + 1; out[n] = "s" end
    if syms.m then n = n + 1; out[n] = "m" end
    if syms.A then n = n + 1; out[n] = "A" end
    if syms.w or syms.r then n = n + 1; out[n] = "w" end
  end
  -- The same rule the fight applies (PublishPlan's hasCd): held procs, the
  -- roll, a script, or an unlocked scenario (its crit opens Kill Command).
  local sc = self:CurrentScenario()
  if sc and (sc.hold ~= nil or sc.qs ~= false or sc.kc or (sc.events and #sc.events > 0)) then n = n + 1; out[n] = "cd" end
  for i = n + 1, #out do out[i] = nil end
  return n
end

function Practice:ApplyKeys()
  if InCombatLockdown() then return end
  owner = owner or CreateFrame("Frame", "NockPracticeBindOwner")
  ClearOverrideBindings(owner)
  self:DetectKeys()
  local useDown = (GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")) and true or false
  local i, taken = 0, {}
  self._keyTaken = taken
  -- One override per (slot, key) the drill wants, not one per wanted spell:
  -- the same macro on four bars is four keys, and a key left un-taken casts
  -- for real in the middle of a drill.
  for _, k in ipairs(self.bindings or {}) do
    if k.key and not taken[k.key] then
      -- No real button to click (a typed override names no action slot): fall
      -- back to the press the player actually made, never to a guess. The
      -- fallback is per ACTION — the first one of this key's macro that names
      -- a wanted spell, item or trinket slot:
      --  * spell  -> "/cast <name>", "/cast !<name>" for the auto (a bare
      --              "/cast Auto Shot" TOGGLES, so it would switch a running
      --              auto OFF; the "!" form only ever turns it on).
      --  * slot   -> "/use 13|14" (the trinket in that slot, whatever it is)
      --  * item   -> "/use <name>", or "/use item:<id>" while the item is not
      --              cached yet — the client accepts the numeric form.
      -- "/cast <trinket>" is still never built: that is a different press.
      local macro = k.button and ("/click " .. k.button) or nil
      if not macro then
        for _, a in ipairs(k.actions or {}) do
          local w = WANTED_BY_NAME[a]
          if w then
            if w.id then
              local n = spellName(w.id)
              if n then
                macro = (w.name == "autoshot") and ("/cast !" .. n) or ("/cast " .. n)
              end
            elseif w.slot then
              macro = "/use " .. w.slot
            elseif w.item then
              macro = "/use " .. (itemName(w.item) or ("item:" .. w.item))
            end
          end
          if macro then break end
        end
      end
      if not macro then
        -- Silence here means the real cooldown fires during the drill and the
        -- sim never sees the press, so say so.
        self:Print(("Practice: could not arm the %s key override (%s)"):format(
          tostring((k.actions or {})[1]), tostring(k.key)))
      end
      if macro then
        taken[k.key] = (k.actions or {})[1] or true
        i = i + 1
        local b = ensureButton(i)
        b._nockActions = k.actions
        b._nockUseDown = useDown
        b:SetAttribute("useOnKeyDown", useDown)
        b:SetAttribute("combatMacro", macro)
        b:SetAttribute("type", nil)
        SetOverrideBindingClick(owner, true, k.key, b:GetName())
      end
    end
  end
  -- The proc keys, after the rotation's: a key the rotation holds is left to
  -- it (ProcKeyState reports the clash).
  local procKeys = profile("practiceProcKeys", {})
  for _, spec in ipairs(Practice.PROC_KEYS) do
    local key = procKeys[spec.name]
    if key and key ~= "" and not taken[key] then
      taken[key] = spec.name
      local b = ensureProcButton(spec.name)
      SetOverrideBindingClick(owner, true, key, b:GetName())
    end
  end
  Nock:SendMessage("NOCK_PRACTICE_CHANGED")
end

function Practice:ClearKeys()
  if owner and not InCombatLockdown() then ClearOverrideBindings(owner) end
end

-- "shift+2" / " Shift-2 " -> "SHIFT-2" (the form GetBindingKey returns). The
-- rule itself is pure, so it lives in PracticeEngine where it is under test.
function Practice.NormalizeKey(s)
  return Nock.PracticeEngine.NormalizeKey(s)
end

-- Typed override changed while practice is on: rebind now (out of combat).
function Practice:ReapplyKeys()
  if self:IsActive() and not InCombatLockdown() then self:ApplyKeys() end
end

-- /nock practice keys — what detection saw, per wanted spell, in a copybox.
function Practice:DumpKeys()
  local keys, bindings = self:DetectKeys()
  local out = {}
  local function line(t) out[#out + 1] = t end
  -- Every key that reaches an action, primary first: one key per action was
  -- the bug this dump was asked to prove, so listing only the primary would
  -- hide the same thing twice.
  local function keyList(k)
    local list = { tostring(k.key) }
    for i = 1, #(k.keys or {}) do
      if k.keys[i] ~= k.key then list[#list + 1] = k.keys[i] end
    end
    return table.concat(list, ", ")
  end
  for _, w in ipairs(WANTED) do
    local k = keys[w.name]
    if k then
      line(("%s: keys %s slot %s button %s actions %s%s"):format(
        w.name, keyList(k), tostring(k.slot), tostring(k.button),
        table.concat(k.actions or {}, ","),
        (k.unknown and #k.unknown > 0) and (" | ignored: " .. table.concat(k.unknown, " / ")) or ""))
    else
      line(("%s: NOT FOUND — no action slot names %s with a bound key"):format(w.name, wantedLabel(w)))
    end
  end
  local tried = {}
  for slot = 1, 120 do
    if HasAction and HasAction(slot) and GetActionInfo then
      local kind = GetActionInfo(slot)
      if kind == "macro" then
        local body = macroBody(slot) or ""
        local key = (keysForSlot(slot)[1] or {}).key
        if body:lower():find("shot", 1, true) then
          tried[#tried + 1] = ("slot %d key %s: %s"):format(slot, tostring(key), (body:gsub("\n", " | ")))
        end
      end
    end
  end
  for _, t in ipairs(tried) do line(t) end
  -- The weave key's own macro bodies, as the sim read them: a body whose lines
  -- all land in `ignored` is the difference between a drill that never sees a
  -- weave and one that does, and until now nothing showed it.
  local function joined(t, sep)
    if not t or #t == 0 then return "none" end
    return table.concat(t, sep)
  end
  line("weave down: " .. joined(self.weaveDown, ","))
  line("weave up: " .. joined(self.weaveUp, ","))
  line("weave ignored: " .. joined(self.weaveUnknown, " / "))
  -- What the drill will actually take over: the count the bug was invisible
  -- in — one key bound where four keys press the same shot.
  line(("bound: %d keys"):format(#(bindings or {})))
  Nock.UI.ShowCopyBox(table.concat(out, "\n"))
end
