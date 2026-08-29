-- Core/Core.lua
-- AceAddon entry point: bootstrap, AceDB, slash command, central OnUpdate tick, latency poll.

local Nock = LibStub("AceAddon-3.0"):NewAddon("Nock", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
_G.Nock = Nock

local VERSION = C_AddOns.GetAddOnMetadata("Nock", "Version") or "?"

function Nock:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("NockDB", self.Defaults, true)
  -- Live profile switching: every view re-reads its keys off NOCK_VISUALS_CHANGED,
  -- so switching/copying/resetting an AceDB profile must fire it (plus position/
  -- lock, which have their own apply paths) — otherwise the HUD keeps rendering
  -- the OLD profile until /reload.
  self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileSwitched")
  self.db.RegisterCallback(self, "OnProfileCopied",  "OnProfileSwitched")
  self.db.RegisterCallback(self, "OnProfileReset",   "OnProfileSwitched")
  self:MigrateProfile()
  local _, class = UnitClass("player")
  self.isHunter = (class == "HUNTER")

  if not self.isHunter then
    -- Non-Hunter (e.g. the banker alt): keep the addon shell enabled so the
    -- Mailbox module can run the snowball re-send leg, but disable every
    -- other module. OnEnable below skips the Hunter-only tick/latency/combat
    -- wiring, and HUD.lua hides its frame itself when isHunter is false.
    for name, mod in self:IterateModules() do
      if name ~= "Mailbox" and name ~= "MailboxView" then
        mod:SetEnabledState(false)
      end
    end
  end

  self:RegisterChatCommand("nock", "HandleSlashCommand")
  self:RegisterOptions()
  if self.SetupMinimapIcon then self:SetupMinimapIcon() end
end

function Nock:OnEnable()
  if not self.isHunter then return end   -- banker alts: only the Mailbox module runs
  self:Print(("loaded v%s"):format(VERSION))
  self:UpdateLatency()
  self:ScheduleRepeatingTimer("UpdateLatency", self.Constants.LATENCY_POLL_SEC)
  self:StartTick()
  self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatChanged")
  self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatChanged")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCombatChanged")
  self:OnCombatChanged()
end

function Nock:OnProfileSwitched()
  self:MigrateProfile()
  -- A profile switch invalidates the setup wizard's context (its previews and
  -- unlock were written into the old profile) — close it before broadcasting,
  -- so its Teardown relocks under the profile that is now active.
  local ob = self:GetModule("Onboarding", true)
  if ob and ob.IsOpen and ob:IsOpen() then ob:Close() end
  self:SendMessage("NOCK_POSITION_RESET")   -- HUD:ApplyPosition reads the new profile
  self:SendMessage("NOCK_LOCK_CHANGED", self.IsLocked())
  self:SendMessage("NOCK_VISUALS_CHANGED")
  if self.ApplyMinimapIcon then self:ApplyMinimapIcon() end
end

-- Global lock accessors — the ONLY read/write path for profile.locked outside
-- the central tick. One write site means the NOCK_LOCK_CHANGED broadcast can
-- never be forgotten, and one read site pins the nil polarity (nil = locked,
-- matching the default) that per-frame helpers used to disagree on.
function Nock.IsLocked()
  local p = Nock.db and Nock.db.profile
  if not p then return true end
  return p.locked ~= false
end

function Nock:SetLocked(v)
  v = v and true or false
  self.db.profile.locked = v
  self:SendMessage("NOCK_LOCK_CHANGED", v)
end

-- One-shot profile migrations. Safe to call on every profile activation.
local OLD_IN_BLUE = { 0.30, 0.60, 1.00, 1.00 }
local function colorsMatch(c, ref)
  if type(c) ~= "table" then return false end
  for i = 1, 4 do
    if math.abs((c[i] or 1) - ref[i]) > 0.005 then return false end
  end
  return true
end

function Nock:MigrateProfile()
  local p = self.db.profile
  if not p.rangeInRedMigrated then
    -- rangeInColor's default changed blue -> deadzone red (spec 2026-08-06).
    -- A stored value still equal to the OLD default was never a deliberate
    -- choice — flip it once; anything else the user picked is kept.
    if colorsMatch(p.rangeInColor, OLD_IN_BLUE) then
      p.rangeInColor = { 0.68, 0.18, 0.20, 1.00 }
    end
    p.rangeInRedMigrated = true
  end
  p.rangeGlideEnabled = nil  -- removed experimental flag; drop the stored key
  -- Per-panel locks collapsed into the global `locked` key (1.0.17); drop the
  -- stored per-panel keys so stale values don't linger in SavedVariables.
  p.misdirectLocked         = nil
  p.buffTrackerPlayerLocked = nil
  p.buffTrackerPetLocked    = nil
  p.debuffTrackerLocked     = nil
  p.shoppingLocked          = nil
  -- clipSafetyMargin is gone (1.0.19). Since 1.0.17 the clip ticks include the
  -- Auto Shot wind-up as a real, measured term, which is what the margin was
  -- ever a manual stand-in for — so every non-zero value it could hold now just
  -- pushes the ticks away from the truth. No slider, no presets, no stored key.
  p.clipSafetyMargin  = nil
  p.clipWindupMigrated = nil  -- the one-shot flag for the old 1.0.17 reset
  -- The weave-coach sound cues left the GUI (1.0.17): their options are still
  -- registered but hidden. A profile that had them on would keep playing them
  -- with no visible way to stop, so switch the master flag off once. The two
  -- sound names are left stored — un-hiding the section gives them back.
  if not p.weaveCoachSoundsRetired then
    p.weaveCoachSoundsEnabled = false
    p.weaveCoachSoundsRetired = true
  end
  -- The Teron warning became the generic boss-mark warning when Archimonde's
  -- Air Burst joined it (1.0.21). Same banner, same cue, same sliders — only
  -- the key names changed, so carry the stored values across once rather than
  -- silently resetting a banner someone has already dragged into place. Only
  -- keys that are actually present move; a profile that never saw 1.0.20 keeps
  -- the new defaults.
  --
  -- Each test is on the SOURCE key, never the destination: the new keys all
  -- have non-nil defaults, so an AceDB read of an unset one returns the default
  -- rather than nil and a "destination is still empty" guard would never pass.
  -- Nilling the old keys afterwards is what makes this run exactly once.
  if p.teronBannerPosition  ~= nil then p.bossBannerPosition  = p.teronBannerPosition end
  if p.teronBannerSize      ~= nil then p.bossBannerSize      = p.teronBannerSize end
  if p.warnTeronSound       ~= nil then p.warnBossMarkSound   = p.warnTeronSound end
  if p.warnTeronMarkEnabled ~= nil then p.warnBossMarkEnabled = p.warnTeronMarkEnabled end
  p.teronBannerPosition  = nil
  p.teronBannerSize      = nil
  p.warnTeronSound       = nil
  p.warnTeronMarkEnabled = nil
  -- The Steam Tonk settling delay gained a 0.50s floor (1.0.24). Anything below
  -- it was a gamble on a clean frame, and the cost of losing that bet is being
  -- welded in place for the rest of the pull -- so this raises existing profiles
  -- rather than grandfathering them. Not latched: it re-clamps on every profile
  -- activation, which is what makes a hand-edited SavedVariables or an imported
  -- profile safe too. Values at or above the floor are left exactly as set.
  local lo, stored = self.Constants.TONK_CANCEL_MIN, tonumber(p.tonkCancelDelay)
  if stored and stored < lo then p.tonkCancelDelay = lo end
end

function Nock:OnCombatChanged()
  local inCombat = UnitAffectingCombat("player") and true or false
  if self.state.player.inCombat ~= inCombat then
    self.state.player.inCombat = inCombat
    self:SendMessage("NOCK_COMBAT_CHANGED", inCombat)
  end
end

-- Instance-type probes. Plain functions on the addon table (call with a dot, not
-- a colon) so any module can reach them regardless of load order — Core is first
-- in the .toc. Shared by Helpers (consumable gating) and Warnings (per-warning
-- "raid only" toggles) so IsInInstance() has exactly one call-site shape.
--
-- Note these are deliberately instance-based, NOT group-based: IsInRaid() is
-- unreliable on this client (returns false in a raid), which is why the
-- group-scoped checks elsewhere carry GetNumRaidMembers fallbacks. IsInInstance
-- has no such problem.
function Nock.IsInInstance()
  if not IsInInstance then return false end
  local _, instanceType = IsInInstance()
  return instanceType == "party" or instanceType == "raid"
end

function Nock.IsInRaidInstance()
  if not IsInInstance then return false end
  local _, instanceType = IsInInstance()
  return instanceType == "raid"
end

-- The target is a raid boss: worldboss classification or "boss level"
-- (UnitLevel == -1, the ?? skull) — no encounter IDs. The same rule the
-- Devilsaur / shirt-gate warnings and the Helpers panel use as file-locals.
function Nock.IsBossTarget()
  if not (UnitExists and UnitExists("target")) then return false end
  if UnitCanAttack and not UnitCanAttack("player", "target") then return false end
  if UnitIsDead and UnitIsDead("target") then return false end
  if UnitClassification and UnitClassification("target") == "worldboss" then return true end
  if UnitLevel and UnitLevel("target") == -1 then return true end
  return false
end

function Nock:StartTick()
  if self.tickFrame then return end
  -- Practice mode is stepped from Tick() itself (module Refresh order is
  -- pairs() order, so the toc cannot guarantee it runs first). Cached once
  -- here so the tick never pays for a GetModule lookup.
  self._practice = self:GetModule("Practice", true)
  local f = CreateFrame("Frame")
  -- Optional throttle. perfTickHz == 0 keeps the original uncapped behavior
  -- (tick every rendered frame); > 0 accumulates elapsed and only ticks at the
  -- requested rate, capping the per-frame cost multiplier during raids.
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    local hz = (Nock.db and Nock.db.profile and Nock.db.profile.perfTickHz) or 0
    if hz > 0 then
      acc = acc + (elapsed or 0)
      if acc < (1 / hz) then return end
      acc = 0
    end
    Nock:Tick()
  end)
  self.tickFrame = f
end

function Nock:Tick()
  -- Profiler hooks: armed only while /nock profile is running (self._prof set),
  -- otherwise every reference below short-circuits on the nil check.
  local prof = self._prof
  local tickStart = prof and debugprofilestop()

  local state = self.state
  local now = GetTime()

  -- Practice mode publishes its simulated grid, cast and cooldowns into state
  -- BEFORE the derived math below runs, so swingRemaining/windup, the cooldown
  -- remaining/ready pass and the GCD all read the sim's current snapshot rather
  -- than last frame's. Stepped from here, not from the Refresh loop, because
  -- Nock:IterateModules() is pairs() order and cannot be relied on.
  local pr = self._practice
  if pr and state.sim.active then pr:Step(state, now) end

  -- Edit mode: while a frame is being dragged with snap-while-dragging on, the
  -- grid's ghost outline follows the snapped landing spot (one call, nil-cheap).
  local em = self.EditMode
  if em and em._drag then em:DragTick() end

  if state.ranged.swingStart > 0 then
    state.ranged.swingRemaining = math.max(0, state.ranged.swingStart + state.ranged.swingDuration - now)
  end
  if state.melee.swingStart > 0 then
    state.melee.swingRemaining = math.max(0, state.melee.swingStart + state.melee.swingDuration - now)
  end
  -- Auto Shot wind-up in seconds. Derived, not measured directly: the invariant
  -- is the ratio (see Core/State.lua), so this tracks a haste proc the instant
  -- swingDuration moves rather than lagging behind a running average.
  state.ranged.windup = state.ranged.windupRatio * state.ranged.swingDuration

  -- Weave-release retry cost (Nock.ReleaseCost). Latency-shifted: the press
  -- reaches the server ~latency later, so the effective release moment sits
  -- that much closer to ready — which is also why the free zone opens a ping
  -- BEFORE the bar fills. No swing tracked = nothing recharging = free.
  do
    local rem = (state.ranged.swingStart > 0) and state.ranged.swingRemaining or 0
    local lat = (state.network.latencyMs or 0) / 1000
    state.weave.releaseCost   = Nock.ReleaseCost(rem - lat)
    state.weave.releaseFreeIn = Nock.ReleaseFreeIn(rem - lat)
  end

  for _, cd in pairs(state.cooldowns) do
    if cd.startTime > 0 and cd.duration > 0 then
      cd.remaining = math.max(0, cd.startTime + cd.duration - now)
      cd.ready = cd.remaining <= 0
    else
      cd.remaining = 0
      cd.ready = true
    end
    if cd.buffStartTime and cd.buffStartTime > 0 and cd.buffDuration and cd.buffDuration > 0 then
      cd.buffRemaining = math.max(0, cd.buffStartTime + cd.buffDuration - now)
    else
      cd.buffRemaining = 0
    end
  end

  -- Global cooldown. Steady Shot has no real cooldown, so whatever cooldown it
  -- reports IS the GCD (haste-scaled). Anything longer than the 1.5s base + slop
  -- isn't a GCD (e.g. the spell is genuinely on CD) and is ignored. Single
  -- source of truth: the rotation row and the GCD bar both read state.gcd.
  local C = self.Constants
  local g = state.gcd
  local gs, gd
  if state.sim.active then
    gs, gd = state.sim.gcd.start, state.sim.gcd.duration
  elseif C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(C.SpellID.STEADY_SHOT)
    if info then gs, gd = info.startTime, info.duration end
  elseif GetSpellCooldown then
    gs, gd = GetSpellCooldown(C.SpellID.STEADY_SHOT)
  end
  if gs and gs > 0 and gd and gd > 0 and gd <= (C.GCD_BASE or 1.5) + 0.05 then
    g.start, g.duration = gs, gd
    g.remaining = math.max(0, gs + gd - now)
    g.active = g.remaining > 0
  else
    g.start, g.duration, g.remaining, g.active = 0, 0, 0, false
  end

  -- Continuous-derived context (cheap reads each frame)
  state.context.moving      = (GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0) or false
  state.context.controlLost = HasFullControl and (not HasFullControl()) or false

  local maxMana = UnitPowerMax("player", 0) or 0
  local mana = UnitPower("player", 0) or 0
  state.player.manaCur = mana
  state.player.manaMax = maxMana
  state.player.manaPct = (maxMana > 0) and (mana / maxMana * 100) or 100
  state.context.conserveMana = state.player.manaPct < 50

  local maxHp = UnitHealthMax("player") or 0
  local hp = UnitHealth("player") or 0
  state.player.healthPct = (maxHp > 0) and (hp / maxHp * 100) or 100

  local mark = state.target.huntersMark
  if mark then
    mark.remaining = math.max(0, mark.expirationTime - now)
  end

  if self.Profiles then
    local ews = state.ranged.swingDuration
    local meleeHaste = state.sim.active and state.sim.meleeHaste
      or ((GetMeleeHaste and GetMeleeHaste()) or 0)
    -- Proc-aware: a Quick Shots / Rapid Fire tick answers from the
    -- rotationtools proc ladder instead of the raw eWS bracket (which the
    -- 12s Hawk proc often fails to move across an edge). Identical to
    -- ResolveByEWS whenever no ranged proc is up.
    local name, profile = self.Profiles:ResolveTurret(ews, state.player, meleeHaste)
    state.rotation.profileName = name
    state.rotation.profile = profile

    -- Weave notation (opt-in, auto-selected by range). Turret players never
    -- enter the weave band, so they keep seeing the turret pattern.
    local weaveName = self.Profiles:ResolveWeave(ews, state.player, meleeHaste)
    state.rotation.weaveName = weaveName

    -- One definition (Nock.HudNotation, Core/State.lua): the live turret/weave
    -- pick, EXCEPT while a practice drill owns the HUD — there the paper the
    -- fight is graded against is the only rotation the HUD may name or draw.
    local p = self.db and self.db.profile
    state.rotation.notation = Nock.HudNotation(state, name, weaveName,
      p and p.weaveNotationEnabled, p and p.rotWeaveProxMin)
  end

  -- No Steam Tonk derivation here any more. The HOLD / RELEASE cue needed a
  -- per-tick state because the PLAYER was the mechanism; UI/Frame_TonkDial.lua
  -- reads state.player.tonk directly and lets the client animate the sweep.

  if prof then prof:RecordCore(debugprofilestop() - tickStart) end

  -- Scan throttle. A module may declare `Module.refreshInterval = 0.1` to opt
  -- into the slow lane: it then refreshes at that cadence instead of once per
  -- rendered frame. This is for the aura-scanning engines and slow-changing
  -- panels, whose cost is O(entries x buff-depth) and explodes in a raid while
  -- the data itself never changes faster than ~10 Hz. Anything that animates
  -- (swing bars, shot bars, cast bar) declares no interval and keeps running at
  -- full framerate — so this buys back CPU without costing smoothness, unlike
  -- throttling the tick itself.
  local slow = not (self.db and self.db.profile and self.db.profile.perfThrottleScans == false)

  -- Isolate each module's Refresh: one module erroring on a frame must not
  -- skip every module after it in the loop (that's what left panels looking
  -- "blanked until /reload"). The error is still surfaced to BugSack once per
  -- module (latched so it can't spam every frame).
  for _, mod in self:IterateModules() do
    if mod.Refresh then
      local due = true
      local iv = slow and mod.refreshInterval
      if iv then
        local nx = mod._nextRefresh
        if nx and now < nx then
          due = false
        else
          mod._nextRefresh = now + iv
        end
      end
      if due then
        local m0 = prof and debugprofilestop()
        local ok, err = pcall(mod.Refresh, mod, state)
        if prof then prof:Record(mod:GetName(), debugprofilestop() - m0) end
        if not ok and not mod._refreshErrored then
          mod._refreshErrored = true
          geterrorhandler()(err)
        end
      end
    end
  end

  if prof then prof:CountTick(debugprofilestop() - tickStart) end
end

function Nock:UpdateLatency()
  local _, _, home, world = GetNetStats()
  self.state.network.latencyMs = math.max(home or 0, world or 0)
end

function Nock:HandleSlashCommand(input)
  input = (input or ""):lower():match("^%s*(.-)%s*$")
  if input == "" or input == "config" then
    self:OpenConfig()
  elseif input == "version" then
    self:Print(("v%s"):format(VERSION))
  elseif input == "lock" then
    self:SetLocked(true)
    self:Print("All Nock frames locked.")
  elseif input == "unlock" then
    self:SetLocked(false)
    self:Print("All Nock frames unlocked — drag anything to move it, or click it once for a nudge pad.")
  elseif input == "reset" then
    self.db.profile.position = self:GetDefaultPosition()
    self:SendMessage("NOCK_POSITION_RESET")
    self:Print("HUD position reset.")
  elseif input == "autoshot" then
    self.db.profile.showAutoShotCast = not self.db.profile.showAutoShotCast
    self:Print(("Auto Shot cast bar: %s"):format(self.db.profile.showAutoShotCast and "ON" or "OFF"))
  elseif input == "tonk" then
    local tg = self:GetModule("TonkGuard", true)
    if tg then tg:PanicCancel() else self:Print("Steam Tonk guard is not loaded.") end
  -- `teron` is the 1.0.20 spelling, kept working because it shipped. The
  -- optional trailing word picks which encounter to preview.
  elseif input == "bossmark" or input == "teron" then
    local bw = self:GetModule("BossMarkWatch", true)
    if bw then bw:Dump() else self:Print("Boss-mark watch is not loaded.") end
  elseif input:match("^norelease") then
    local w = self:GetModule("Warnings", true)
    if w and w.RunNoReleaseDemo then
      -- RunNoReleaseDemo prints its own reason when it refuses (warnings or
      -- this alert switched off), so only the success line lives here.
      if w:RunNoReleaseDemo(5) then
        self:Print("DO NOT RELEASE banner: 5-second preview.")
      end
    else
      self:Print("Warnings module is not loaded.")
    end
  elseif input:match("^bossmark test") or input:match("^teron test") then
    local bw = self:GetModule("BossMarkWatch", true)
    -- Fires the real banner and the real cue: placing it and auditioning the
    -- horn before the pull is the whole point.
    local which = input:match("test%s+(%a+)$")
    if bw then bw:Preview(which) else self:Print("Boss-mark watch is not loaded.") end
  -- Anetheron's Slammer button: `slammer` dumps, `slammer test` holds the
  -- button open with a short first window so it can be placed and clicked,
  -- `slammer cast` fakes a Sleep going out (the verdict + the horn), `slammer
  -- off` ends the preview.
  elseif input:match("^slammer") then
    local sw = self:GetModule("SlammerWatch", true)
    if not sw then
      self:Print("Slammer watch is not loaded.")
    else
      local sub, arg = input:match("^slammer%s+(%a+)%s*(%d*)")
      if sub == "test" then sw:Preview(true)
      elseif sub == "cast" then sw:PreviewCast()
      elseif sub == "slept" then sw:PreviewSlept()
      elseif sub == "sim" then sw:Sim(arg ~= "" and arg or nil)
      elseif sub == "off" then sw:Preview(false)
      elseif sub == "item" then
        -- Session-only: aim the click at another consumable to prove the
        -- secure path before there is a Slammer to drink.
        local view = self:GetModule("SlammerButtonView", true)
        local ok, why = view and view:SetItemOverride(arg ~= "" and arg or nil)
        if not view then self:Print("Slammer button is not loaded.")
        elseif not ok then self:Print("Can't change the item " .. tostring(why) .. ".")
        elseif arg ~= "" then self:Print("Slammer button now uses item " .. arg .. " for this session.")
        else self:Print("Slammer button back on the Sulfuron Slammer.") end
      else sw:Dump() end
    end
  elseif input:match("^ripper") then
    local rw = self:GetModule("RipperWatch", true)
    if not rw then
      self:Print("Ripper watch is not loaded.")
    else
      local sub, arg = input:match("^ripper%s+(%a+)%s*(%d*)")
      if sub == "test" then rw:Preview(true, arg ~= "" and arg or nil)
      elseif sub == "off" then rw:Preview(false)
      else rw:Dump() end
    end
  elseif input:match("^kcglow") then
    -- Kill Command glow diag (branch react-kc-range): every layer between the
    -- proc and the action-bar glow in a copybox; "test on|off" forces the
    -- overlay onto the found buttons regardless of the proc.
    local ag = self:GetModule("ActionGlow", true)
    local arg = input:match("^kcglow%s+test%s+(%a+)")
    local tile = input:match("^kcglow%s+tile%s+(%a+)")
    if not ag then self:Print("ActionGlow module is not loaded.")
    elseif tile then ag:TestTile(tile)
    elseif input:match("^kcglow%s+trace") then ag:Trace()
    elseif arg == "on" then ag:Test(true); self:Print("KC glow forced ON for the found buttons (/nock kcglow test off to clear).")
    elseif arg == "off" then ag:Test(false); self:Print("KC glow force cleared.")
    else ag:Diag() end
  elseif input == "tonkdebug" then
    local tg = self:GetModule("TonkGuard", true)
    if tg then
      -- SetTrace, not a bare flag flip: tracing also hooks ADDON_ACTION_BLOCKED,
      -- which is how the in-game gate tells "the dismiss was refused" apart from
      -- "the dismiss ran and did nothing".
      self:Print(("Steam Tonk trace: %s"):format(tg:SetTrace(not tg._trace) and "ON" or "OFF"))
    else
      self:Print("Steam Tonk guard is not loaded.")
    end
  elseif input == "debug" then
    local s = self.state
    self:Print(("ranged %.2fs/%.2fs  melee %.2fs/%.2fs  lat %dms  repeating=%s"):format(
      s.ranged.swingRemaining, s.ranged.swingDuration,
      s.melee.swingRemaining, s.melee.swingDuration,
      s.network.latencyMs, tostring(s.ranged.repeating)))
    self:Print(("aspect=%s  lust=%s  canWeave=%s  inCombat=%s  tonk=%s"):format(
      s.player.aspect and s.player.aspect.name or "none",
      tostring(s.player.inLust),
      tostring(s.player.canWeave),
      tostring(s.player.inCombat),
      tostring(s.player.tonk.active)))
    self:Print(("zone=%s  HM=%s  moving=%s  controlLost=%s"):format(
      tostring(s.target.rangeZone),
      s.target.huntersMark and ("%.0fs"):format(s.target.huntersMark.remaining) or "none",
      tostring(s.context.moving),
      tostring(s.context.controlLost)))
    local nextActionName = "none"
    if s.rotation.nextAction and GetSpellInfo then
      nextActionName = GetSpellInfo(s.rotation.nextAction) or tostring(s.rotation.nextAction)
    end
    self:Print(("eWS=%.2fs  profile=%s  NEXT=%s  mana=%.0f%%"):format(
      s.ranged.swingDuration,
      tostring(s.rotation.profileName),
      nextActionName,
      s.player.manaPct))
    local rf = self:GetModule("RangeFinder", true)
    if rf and rf.DebugProbes then self:Print(rf:DebugProbes()) end
  elseif input == "helpers" then
    -- Per-helper gate/status/buff-match/bag report. This is how you verify the
    -- Core/ConsumeData.lua spell + item IDs against what's actually on you:
    -- a helper stuck on "missing" while the buff is visibly up means its ID is
    -- missing from the set. Copy box, not chat — the report is long.
    local mod = self:GetModule("Helpers", true)
    if mod and mod.DebugDump and Nock.UI and Nock.UI.ShowCopyBox then
      Nock.UI.ShowCopyBox(mod:DebugDump())
    else
      self:Print("Helpers module not loaded.")
    end
  elseif input == "diag" then
    -- Media-dropdown provider report. The bug this exists for is silent: an
    -- error while AceConfigDialog builds a control aborts its whole option
    -- loop, so every setting below it never renders and the user just sees a
    -- tab that "goes blank". Knowing which widget (and which vintage of a
    -- foreign AceGUI-3.0-SharedMediaWidgets) is in play answers that in one
    -- line. See LSM_WIDGET_PREFERENCE in Config/Options.lua.
    -- Shown in the shared copy box (chat text can't be copied), so the whole
    -- report pastes back in one Ctrl+C. Plain text on purpose — colour
    -- escapes would come along with the paste.
    local lsm = LibStub("LibSharedMedia-3.0", true)
    local agui, aguiMinor = LibStub("AceGUI-3.0", true)
    local lines = {}
    lines[#lines + 1] = ("AceGUI-3.0 %s  |  LibSharedMedia-3.0 %s"):format(
      agui and ("r" .. tostring(aguiMinor)) or "MISSING",
      lsm and ("loaded — %d fonts, %d statusbars"):format(
        #lsm:List("font"), #lsm:List("statusbar")) or "MISSING")
    if Nock.UI and Nock.UI.DumpMediaWidgetChoice then
      lines[#lines + 1] = "in use: " .. Nock.UI.DumpMediaWidgetChoice()
      lines[#lines + 1] = "registry: " .. Nock.UI.DumpMediaWidgets()
    else
      lines[#lines + 1] = "UI/AceGUI_LSMDropdown.lua did not load — Nock's own media dropdowns are unavailable, so a foreign LSM30_* widget may be rendering them."
    end
    lines[#lines + 1] = ("hudMode=%s  reactFont=%q  reactBarTexture=%q"):format(
      tostring(self.db.profile.hudMode),
      tostring(self.db.profile.reactFont),
      tostring(self.db.profile.reactBarTexture))
    local text = table.concat(lines, "\n")
    if Nock.UI and Nock.UI.ShowCopyBox then
      Nock.UI.ShowCopyBox(text)
    else
      self:Print(text)
    end
  elseif input == "fonts" then
    if Nock.UI and Nock.UI._DumpHeaderFonts and Nock.UI.ShowCopyBox then
      Nock.UI.ShowCopyBox(Nock.UI._DumpHeaderFonts())
    else
      self:Print("font diagnostic not available")
    end
  elseif input == "debug-icons" then
    for _, entry in ipairs(self.Constants.TRACKED_COOLDOWNS) do
      if entry.type == "spell" then
        local id = entry.id
        local _, _, i1
        if GetSpellInfo then _, _, i1 = GetSpellInfo(id) end
        local i2
        if C_Spell and C_Spell.GetSpellInfo then
          local info = C_Spell.GetSpellInfo(id)
          i2 = info and info.iconID
        end
        local i3
        if C_Spell and C_Spell.GetSpellTexture then i3 = C_Spell.GetSpellTexture(id) end
        local i4
        if GetSpellTexture then i4 = GetSpellTexture(id) end
        self:Print(("%s[%d] GSI=%s C.GSI=%s C.GST=%s GST=%s"):format(
          entry.label, id, tostring(i1), tostring(i2), tostring(i3), tostring(i4)))
      elseif entry.type == "specSpell" then
        self:Print(("%s (specSpell): see state.cooldowns[%s].icon=%s"):format(
          entry.label, entry.key, tostring(self.state.cooldowns[entry.key] and self.state.cooldowns[entry.key].icon)))
      elseif entry.type == "inventory" then
        local tex = GetInventoryItemTexture("player", entry.slot)
        self:Print(("%s (inv slot %d) tex=%s"):format(entry.label, entry.slot, tostring(tex)))
      elseif entry.type == "item" then
        local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(entry.id)
        self:Print(("%s (item %d) icon=%s count=%d"):format(entry.label, entry.id, tostring(icon), GetItemCount(entry.id) or 0))
      elseif entry.type == "altItem" then
        local resolved = self.state.cooldowns[entry.key] and self.state.cooldowns[entry.key].icon
        self:Print(("%s (altItem) resolved icon=%s"):format(entry.label, tostring(resolved)))
      end
    end
  elseif input == "v3" then
    -- Experimental V3 medallion. (Its companion simplified Shot Bars are the
    -- baseline since 1.0.14 — this no longer touches them; the legacy bar
    -- lives behind Rotation → "Use legacy Shot Bars".)
    local p = self.db.profile
    local on = not p.medallionEnabled
    p.medallionEnabled = on
    self:SendMessage("NOCK_VISUALS_CHANGED")
    self:Print(("V3 next-action medallion (experimental): %s%s"):format(
      on and "ON" or "OFF",
      on and " — medallion below your character (unlock with /nock unlock to move it)" or ""))
  elseif input == "react" then
    -- React HUD mode: fixed-skin replica of the React hunter WA (Options →
    -- General → React HUD). Swaps the whole classic bar cluster.
    local p = self.db.profile
    p.hudMode = (p.hudMode == "react") and "classic" or "react"
    self:SendMessage("NOCK_VISUALS_CHANGED")
    self:Print(("React HUD mode: %s"):format(p.hudMode == "react" and "ON" or "OFF — classic look"))
  elseif input == "weavelog" or input:match("^weavelog%s") then
    -- Weave diagnostics. Plain: only the weave-delay metrics (ability→weave /
    -- weave→ability / total, aerthax weave-delay definitions) with a divider
    -- per cycle. "full": additionally every down/up edge with press context,
    -- swing/Raptor outcomes with offsets, and server errors during holds.
    local arg = input:match("^weavelog%s+(%S+)")
    if arg == "panel" then
      -- The weave log PANEL (Ishri's columns + Nock's verdicts), the same
      -- flag the practice toolbar's Log button writes; live and in practice.
      -- The LIVE panel's own flag (the practice toolbar's Log button is the
      -- practice panel's; the two parted 2026-08-27 after the panel came up
      -- in a raid).
      local p = self.db and self.db.profile
      if p then
        p.weaveLogPanel = not (p.weaveLogPanel == true)
        local v = self:GetModule("PracticeWeaveLogView", true)
        if v and v.Apply then v:Apply() end
        self:Print(("Weave log panel (live fights): %s."):format(p.weaveLogPanel and "ON" or "OFF"))
      end
      return
    end
    if arg == "report" then
      -- Export the captured session to the shared copy box (chat text can't
      -- be copied). Works during or after a session — stopping keeps the
      -- buffer; starting a new one resets it.
      local wb = self:GetModule("WeaveBind", true)
      if wb and wb.ShowReport then wb:ShowReport() else self:Print("WeaveBind not loaded.") end
      return
    end
    if self._weaveLog and not arg then
      self._weaveLog = nil
    else
      self._weaveLog = (arg == "full" or arg == "verbose") and "full" or "metrics"
    end
    self._weaveLogN = 0
    local wb = self:GetModule("WeaveBind", true)
    if wb and wb.SetLogging then wb:SetLogging(self._weaveLog ~= nil) end
    self:Print(("Weave log: %s"):format(
      self._weaveLog == "full" and "FULL (edges + outcomes + metrics)"
      or self._weaveLog == "metrics" and "ON — weave metrics only (/nock weavelog full for everything)"
      or "OFF — /nock weavelog report exports the captured session"))
  elseif input == "shirt" then
    -- Shirt-conditional diagnostics: what the weave-macro resolver sees.
    local wb = self:GetModule("WeaveBind", true)
    if wb and wb.DumpShirtDiag then
      wb:DumpShirtDiag()
    else
      self:Print("WeaveBind not loaded.")
    end
  elseif input == "shotbars" then
    local m = self:GetModule("ShotPredictor", true)
    if m and m.Dump then m:Dump() else self:Print("ShotPredictor not loaded.") end
  elseif input == "binds" then
    local m = self:GetModule("BindCheck", true)
    if m and m.Dump then m:Dump() else self:Print("BindCheck not loaded.") end
  elseif input == "trinkets" then
    local m = self:GetModule("Cooldowns", true)
    if m and m.DumpTrinkets then m:DumpTrinkets() else self:Print("Cooldowns not loaded.") end
  elseif input == "arrows" then
    local m = self:GetModule("InfoRow", true)
    if m and m.DumpArrows then m:DumpArrows() else self:Print("InfoRow not loaded.") end
  elseif input == "mdgeom" then
    local m = self:GetModule("MisdirectView", true)
    if m and m.DumpGeometry then m:DumpGeometry() else self:Print("MisdirectView not loaded.") end
  elseif input == "shopping" then
    local eng = self:GetModule("ShoppingList", true)
    if eng and eng.Recompute then eng:Recompute() end
    local v = self:GetModule("ShoppingView", true)
    if v and v.SetManual then
      local visible = v.panel and v.panel:IsShown()
      v:SetManual(visible and "hide" or "show")
      self:Print(("Shopping list %s."):format(visible and "hidden" or "shown"))
    else
      self:Print("ShoppingView not loaded.")
    end
  elseif input == "profile" or input:match("^profile%s") then
    local m = self:GetModule("Profiler", true)
    if m and m.Command then
      m:Command(input:match("^profile%s+(.-)$") or "")
    else
      self:Print("Profiler not loaded.")
    end
  elseif input == "range" then
    local rf = self:GetModule("RangeFinder", true)
    if rf and rf.Diagnose then rf:Diagnose() else self:Print("RangeFinder not loaded.") end
  elseif input == "totemsim" then
    local m = self:GetModule("TotemTracker", true)
    if m and m.ToggleSim then
      local on = m:ToggleSim()
      self:Print(("Totem-twist simulation: %s%s"):format(
        on and "ON" or "OFF",
        on and " — fake Windfury + Grace of Air + Earth (reload or /nock totemsim to stop)" or ""))
    else
      self:Print("TotemTracker not loaded.")
    end
  elseif input == "pettrain" or input:match("^pettrain%s") then
    local m = self:GetModule("PetTrainer", true)
    if m and m.Command then
      m:Command(input:match("^pettrain%s+(.-)$") or "")
    else
      self:Print("PetTrainer not loaded.")
    end
  elseif input == "mail" or input:match("^mail%s") then
    local m = self:GetModule("Mailbox", true)
    if m and m.Command then
      m:Command(input:match("^mail%s+(.-)$") or "")
    else
      self:Print("Mailbox not loaded.")
    end
  elseif input == "setup" or input == "wizard" then
    local m = self:GetModule("Onboarding", true)
    if m and m.Command then
      m:Command()
    else
      self:Print("Onboarding not loaded.")
    end
  elseif input == "practice" or input:match("^practice%s") then
    local m = self:GetModule("Practice", true)
    if m and m.Command then
      m:Command(input:match("^practice%s+(.-)$") or "")
    else
      self:Print("Practice not loaded.")
    end
  elseif input == "minimap" then
    local shown = not self:IsMinimapShown()
    self:SetMinimapShown(shown)
    self:Print(("Minimap icon %s."):format(shown and "shown" or "hidden"))
  else
    self:Print(("unknown subcommand: '%s' — try /nock for the config panel, or setup/lock/unlock/reset/minimap/autoshot/arrows/binds/trinkets/shopping/totemsim/range/profile/helpers/fonts/diag/v3/react/weavelog/shirt/pettrain/mail/practice/version"):format(input))
  end
end
