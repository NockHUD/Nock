-- Modules/ShotPredictor.lua
-- Engine for the Fluffy-style "Shot Bars" view. Projects upcoming Auto Shot
-- fire times across a lookahead window and, per ability, computes the safe
-- "start your cast here" span using Fluffy Hunter Bars' DPS-equilibrium clip
-- cutoff (recommendation_calculation.lua) rather than a fixed safety margin.
--
-- INSPIRATION: the scrolling shot-bar idea and the DPS-equilibrium clip
-- cutoff come from "Fluffy Hunter Bars" by fluffymoo4kra
-- (https://www.curseforge.com/wow/addons/fluffy-hunter-bars). This is Nock's
-- own implementation of those ideas, not a copy of Fluffy's code -- see
-- ATTRIBUTION.md.
--
-- Faithful to Fluffy's *active* model: its crit/hit modifiers are commented
-- out and its armor-pen file is empty, so this is base-damage only. Two
-- deliberate improvements over Fluffy on the Anniversary client: effective
-- weapon speed comes from Nock's live state.ranged.swingDuration (already
-- haste-correct via UnitRangedDamage), and ability cooldowns are read from
-- the API instead of brittle hardcoded GetTalentInfo indices.
--
-- Writes state.shotpredict (arrays reused in place — no per-tick allocation).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ShotPredictor = Nock:NewModule("ShotPredictor", "AceEvent-3.0")
local C = Nock.Constants

-- Auto Shot wind-up. HASTE-SCALED, despite what the spell data's flat 500ms
-- suggests: 0.5s is the value at base weapon speed and it shrinks with the same
-- multiplier as the swing (dummy-measured 0.365s at eWS 2.174, 0.265s under
-- Rapid Fire at eWS 1.553 — both 0.5/hasteMul). Modules/SwingTimer measures it
-- per shot into state.ranged.windup; C.AUTO_SHOT_CAST is only the cold-start
-- seed, used until the first Auto Shot of the session lands.
local function autoCast()
  local w = Nock.state.ranged.windup
  if w and w > 0 then return w end
  return C.AUTO_SHOT_CAST or 0.5
end
local FLAT = C.ABILITY_FLAT

-- Cached scalars, refreshed on events (never per-tick).
local S = { rap = 0, weaponAvg = 0, weaponSpeed = 0, ammoDps = 0, scopeBonus = 0, multiCdb = 10, arcaneCdb = 6 }

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function barsMode()
  return profile("rotationMode", "helper") == "bars"
end

-- Ranged ATTACK SPEED multiplier — the quiver genuinely applies here. Used only
-- to recover the bow's base speed from the haste-modified one. Ability *cast*
-- times must NOT go through this (the quiver does not shorten a cast); they use
-- Nock.RangedCastTime. Conflating the two is what made every clip tick ~15% too
-- permissive before 2026-08-12.
local function rangedSpeedMul()
  local h = (GetRangedHaste and GetRangedHaste() or 0) / 100
  local quiver = profile("rotQuiverEquipped", true) and 1.15 or 1.0
  return (1 + h) * quiver
end

-- API-derived base cooldown (seconds). Reflects talents (e.g. Improved Arcane
-- Shot) without hardcoding talent indices. Falls back to the TBC default.
local function baseCd(spellID, fallback)
  if GetSpellBaseCooldown then
    local ok, ms = pcall(GetSpellBaseCooldown, spellID)
    if ok and ms and ms > 0 then return ms / 1000 end
  end
  return fallback
end

----------------------------------------------------------------------------
-- Tooltip scanning (weapon avg damage + ammo dps), cached account-wide.
----------------------------------------------------------------------------

-- The Anniversary client is modernized and rejects the legacy hidden
-- CreateFrame("GameTooltip", ...) scan pattern, so use C_TooltipInfo. If it's
-- unavailable we degrade gracefully: weaponAvg/ammoDps stay 0 and the
-- equilibrium still works off RAP (just slightly less accurate absolute dmg —
-- the cutoff depends on dps *ratios*).
local function tooltipLines(slot)
  if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
  if not ok or not data or not data.lines then return nil end
  if TooltipUtil and TooltipUtil.SurfaceArgs then
    TooltipUtil.SurfaceArgs(data)
    for _, line in ipairs(data.lines) do TooltipUtil.SurfaceArgs(line) end
  end
  return data.lines
end

-- First line of the form "min - max Damage" → avg, or nil.
local function parseWeaponAvg(lines)
  for _, line in ipairs(lines) do
    local txt = line.leftText
    if txt then
      local lo, hi = txt:match("(%d+)%s*%-%s*(%d+)")
      if lo and hi then return (tonumber(lo) + tonumber(hi)) / 2 end
    end
  end
  return nil
end

-- Right-side "Speed N.NN" line → decimal, or nil.
local function parseWeaponSpeed(lines)
  for _, line in ipairs(lines) do
    local txt = line.rightText
    if txt then
      local sp = txt:match("(%d+%.%d+)")
      if sp then return tonumber(sp) end
    end
  end
  return nil
end

-- Ammo tooltips show a "... N.N damage per second ..." line. Locale-robust:
-- first number found on any line after the name (line 1).
local function parseAmmoDps(lines)
  for i = 2, #lines do
    local txt = lines[i].leftText
    if txt then
      local n = txt:match("(%d+%.?%d*)")
      if n then return tonumber(n) end
    end
  end
  return nil
end

-- Scope enchant on the ranged weapon adds flat weapon damage.
local SCOPE_BONUS = { [30] = 1, [32] = 2, [33] = 3, [663] = 5, [664] = 7 }
local function scopeBonusFromLink(link)
  if not link then return 0 end
  local enchant = link:match("item:%d+:(%d+)")
  return (enchant and SCOPE_BONUS[tonumber(enchant)]) or 0
end

local function cache()
  local g = Nock.db and Nock.db.global and Nock.db.global.itemCache
  if not g then return nil end
  g.ranged = g.ranged or {}
  g.ammo   = g.ammo   or {}
  return g
end

-- Resolve & cache the equipped ranged weapon's average damage (+scope).
local function refreshWeapon()
  local getID = GetInventoryItemID
  if not getID then return end
  local id = getID("player", 18)
  S.scopeBonus = scopeBonusFromLink(GetInventoryItemLink and GetInventoryItemLink("player", 18))
  if not id or id == 0 then S.weaponAvg = 0; return end
  local g = cache()
  local hit = g and g.ranged[id]
  if not hit then
    local lines = tooltipLines(18)
    if lines then
      local avg = parseWeaponAvg(lines)
      if avg then
        hit = { avg = avg, speed = parseWeaponSpeed(lines) or 0 }
        if g then g.ranged[id] = hit end
      end
    end
  end
  S.weaponAvg   = (hit and hit.avg)   or S.weaponAvg   or 0
  S.weaponSpeed = (hit and hit.speed) or S.weaponSpeed or 0
end

-- Resolve & cache the equipped ammo's dps.
local function refreshAmmo()
  local getID = GetInventoryItemID
  if not getID then return end
  local id = getID("player", 0)
  if not id or id == 0 then S.ammoDps = 0; return end
  local g = cache()
  local dps = g and g.ammo[id]
  if dps == nil then
    local lines = tooltipLines(0)
    if lines then
      dps = parseAmmoDps(lines) or 0
      if g then g.ammo[id] = dps end
    end
  end
  S.ammoDps = dps or 0
end

local function refreshRap()
  local rap = 0
  if UnitRangedAttackPower then
    local base, pos, neg = UnitRangedAttackPower("player")
    rap = (base or 0) + (pos or 0) - (neg or 0)
  end
  -- Hunter's Mark / Expose Weakness on the current target boost RAP.
  if UnitExists and UnitExists("target") and UnitDebuff then
    for i = 1, 40 do
      local name = UnitDebuff("target", i)
      if not name then break end
      if name == "Hunter's Mark" then rap = rap + 110
      elseif name == "Expose Weakness" then rap = rap + 300 end
    end
  end
  S.rap = rap
end

function ShotPredictor:Recompute()
  refreshRap()
  refreshWeapon()
  refreshAmmo()
  S.arcaneCdb = baseCd(C.SpellID.ARCANE_SHOT, 6)
  S.multiCdb  = baseCd(C.SpellID.MULTI_SHOT, 10)
end

----------------------------------------------------------------------------
-- Damage / DPS model + Fluffy equilibrium.
----------------------------------------------------------------------------

-- ate*dps_A - (cast_A - ats)*dps_auto, all over (dps_auto + dps_A). The
-- returned absolute time is the LAST moment you should still start ability A;
-- after it, letting Auto Shot fire is the higher-DPS choice.
local function equilibrium(dpsA, castA, ats, ate, dpsAuto)
  local denom = dpsAuto + dpsA
  if denom <= 0 then return ate end
  return (ate * dpsA - (castA - ats) * dpsAuto) / denom
end

-- Per-tick scratch (no allocation): { dps, cast } per ability.
local ABIL = { steady = {}, multi = {}, arcane = {}, raptor = {} }

-- Live haste-adjusted ranged swing speed. UnitRangedDamage returns the
-- CURRENT (haste-modified) weapon speed continuously — Fluffy uses this, so
-- the cadence stays correct even when standing idle (state.ranged.swing*
-- only updates from actual Auto Shot fires and is the stale 3.0s default
-- until then, which made far too few cycles render).
local function liveSwingDuration()
  if UnitRangedDamage then
    local spd = UnitRangedDamage("player")
    if spd and spd > 0 then return spd end
  end
  local sd = Nock.state.ranged.swingDuration
  return (sd and sd > 0) and sd or 3.0
end

-- Last computed average hits, for the practice grader's damage tally.
local AVG = { a = 0, s = 0, m = 0, A = 0, r = 0, w = 0 }

local function recomputeDps()
  local rap = S.rap
  local sd  = liveSwingDuration()
  -- Base bow speed. Prefer the tooltip value; else recover it from the measured
  -- wind-up ratio (windupRatio == 0.5 / baseSpeed, so baseSpeed == 0.5 / ratio),
  -- which needs no haste model at all; else fall back to the speed multiplier.
  local baseSpeed = S.weaponSpeed
  if not baseSpeed or baseSpeed <= 0 then
    local wr = Nock.state.ranged.windupRatio
    if wr and wr > 0 then baseSpeed = (C.AUTO_SHOT_CAST or 0.5) / wr
    else baseSpeed = sd * rangedSpeedMul() end
  end

  -- dmgAuto from the paper-doll ranged damage (UnitRangedDamage low/high IS
  -- the real Auto Shot hit: weapon + ammo + RAP/14*speed, mods applied). This
  -- is robust on the modernized client where item tooltip scanning fails.
  local autoAvg = 0
  if UnitRangedDamage then
    local _, lo, hi = UnitRangedDamage("player")
    if lo and hi then autoAvg = (lo + hi) / 2 end
  end
  if autoAvg <= 0 then
    -- Last-resort estimate (paper-doll unavailable / unarmed).
    autoAvg = (S.weaponAvg + S.scopeBonus)
            + (S.ammoDps + rap / 14) * baseSpeed
  end
  -- Strip the AP contribution to recover the weapon(+ammo) base used by the
  -- Steady/Multi flat formulas (Fluffy's ranged_dmg_avg term).
  local wProxy = autoAvg - (rap / 14) * baseSpeed
  if wProxy < 0 then wProxy = 0 end

  local dmgAuto   = autoAvg
  local dmgSteady = wProxy + (FLAT.STEADY or 0) + rap * 0.2
  local dmgMulti  = wProxy + (FLAT.MULTI  or 0) + rap * 0.2
  local dmgArcane = (FLAT.ARCANE or 0) + rap * 0.15

  local dpsAuto = dmgAuto / sd

  ABIL.steady.dps  = dmgSteady / 1.5                       -- cast+cdb ≡ 1.5
  ABIL.steady.cast = Nock.RangedCastTime(1.5)
  ABIL.multi.cast  = Nock.RangedCastTime(0.5)
  ABIL.multi.dps   = dmgMulti / (S.multiCdb + ABIL.multi.cast)
  ABIL.arcane.dps  = dmgArcane / math.max(0.1, S.arcaneCdb)
  ABIL.arcane.cast = 0

  -- Raptor: rough melee approximation (toggleable, lowest fidelity).
  local mAvg = 0
  if UnitDamage then
    local mLo, mHi = UnitDamage("player")  -- lowDamage, highDamage
    if mLo and mHi then mAvg = (mLo + mHi) / 2 end
  end
  ABIL.raptor.dps  = (mAvg + (FLAT.RAPTOR or 0)) / 6
  ABIL.raptor.cast = 0

  AVG.a, AVG.s, AVG.m, AVG.A = dmgAuto, dmgSteady, dmgMulti, dmgArcane
  AVG.r, AVG.w = mAvg + (FLAT.RAPTOR or 0), mAvg

  return dpsAuto
end

----------------------------------------------------------------------------
-- Projection.
----------------------------------------------------------------------------

local function setSpan(list, s, e)
  if e <= s then return end
  local n = list.n + 1
  list.n = n
  local span = list[n]
  if not span then span = {}; list[n] = span end
  span.s, span.e = s, e
end

local ORDER = { "steady", "queue", "multi", "arcane", "raptor", "weaveauto", "danger", "weaveclip" }

-- Raptor Strike cooldown remaining (seconds), GCD ignored. Mirrors Warnings'
-- getSpellCdRemaining; used to two-tone the melee weave lane (bright raptor
-- colour while it's up, dim "auto-attack only" while it's on its 6s cooldown).
local function raptorCdRemaining()
  -- Practice mode owns Raptor while the drill runs (Rotation.lua carries the
  -- identical hook), so the melee weave lane follows the simulated cooldown.
  local o = Nock.state._raptorCdOverride
  if o ~= nil then return o end
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(C.SpellID.RAPTOR_STRIKE)
    if info then start = info.startTime or 0; duration = info.duration or 0 end
  elseif GetSpellCooldown then
    start, duration = GetSpellCooldown(C.SpellID.RAPTOR_STRIKE)
  end
  if not start or start == 0 then return 0 end
  if not duration or duration <= 1.5 then return 0 end
  return math.max(0, start + duration - GetTime())
end

-- Hoisted (no per-tick closure allocation — Refresh runs at tick rate).
local function offCd(state, now, cdKey, atT)
  if not cdKey then return true end
  local cd = state.cooldowns and state.cooldowns[cdKey]
  if not cd then return true end
  return (now + (cd.remaining or 0)) <= atT
end

local function eqEnd(a, ats, ate, dpsAuto, safety, horizon)
  local e = equilibrium(a.dps, a.cast or 0, ats, ate, dpsAuto) - safety
  if e > ate then e = ate end
  if e > horizon then e = horizon end
  return e
end

function ShotPredictor:Refresh(state)
  if not Nock.isHunter then return end
  local sp = state.shotpredict
  -- Skip projection when not in bars mode OR the rotation display is globally
  -- disabled (showRotation) — no point computing for a hidden ShotBars.
  if not barsMode() or not profile("showRotation", true) then
    if sp.active then sp.active = false end
    return
  end

  local now = GetTime()
  local r = state.ranged
  local sd = liveSwingDuration()
  local windowSec = profile("shotBarsWindow", 3.4)
  sp.windowSec  = windowSec
  -- Publish the timestamp the spans/sparks below are anchored to. ShotBars
  -- renders against THIS, not a second GetTime() — otherwise the small, varying
  -- gap between the two Refreshes makes an idle projection shimmer by 1px.
  sp.now        = now
  -- Weave notation when weaving in range, else the turret profile name, passed
  -- through the user's rename map (blank = the built-in notation). This is a
  -- render-prep layer, so translating here is the right edge — state.rotation
  -- stays canonical for the engine and the debug dump.
  local notation = state.rotation and (state.rotation.notation or state.rotation.profileName)
  sp.profileName = (notation and Nock.Profiles and Nock.Profiles:DisplayName(notation)) or notation or "—"
  -- The raw notation rides along for the view's DisplayColor lookup — colors
  -- key on the built-in string, and profileName above may be a user rename.
  sp.rawNotation = notation

  -- Clear span lists + spark/clip counts up front.
  for _, k in ipairs(ORDER) do state.shotpredict.windows[k].n = 0 end
  sp.nSparks = 0
  sp.nClips = 0

  if sd <= 0 then sp.active = false; return end
  sp.active = true

  local dpsAuto = recomputeDps()
  -- Latency is the whole of it: the hand-tuned extra margin that used to be
  -- added here is gone, since the wind-up is measured rather than assumed.
  local safety  = (state.network.latencyMs or 0) / 1000
  -- Hoisted out of the cycle loop: one read per Refresh, not per cycle.
  local windup  = autoCast()

  -- First upcoming Auto Shot fire time. If actively shooting use the live
  -- remaining; otherwise assume a fresh cycle starting now.
  local rem = r.swingRemaining
  local tf
  if r.swingStart > 0 and rem > 0 then tf = now + rem else tf = now + sd end

  -- While you're mid-cast you can't start a new one, so windows can't open
  -- until the cast finishes — this is the "Fluffy drops the bars" behaviour.
  -- Safe to read directly: state.player.casting holds real casts only. The Auto
  -- Shot wind-up has its own field precisely because it is NOT a lockout, and
  -- counting it here dropped the bars for the last stretch of every cycle.
  local castEnd = 0
  local cast = state.player and state.player.casting
  if cast and cast.endTime and cast.endTime > now then castEnd = cast.endTime end

  -- Absolute time Raptor Strike comes off cooldown — splits the weave lane into
  -- a white "auto-attack only" part (before) and the green Raptor part (after).
  local raptorReady = now + raptorCdRemaining()

  -- Absolute time your melee swing is next available. While it's recharging
  -- (you just swung) you can't land a melee hit, so the whole melee lane is
  -- hidden until then. swingStart==0 (never swung) ⇒ treated as ready now.
  local mel = state.melee
  local meleeReady = now
  if mel and (mel.swingStart or 0) > 0 and (mel.swingDuration or 0) > 0 then
    local r = mel.swingStart + mel.swingDuration
    if r > now then meleeReady = r end
  end

  local prevFire = now
  local horizon = now + windowSec
  local guard = 0
  -- Keep going while the cycle's START is on-screen (not its fire time), so
  -- the cycle that begins in view but fires past the edge still draws and
  -- tiles to the right edge — otherwise the right side goes blank.
  while prevFire < horizon and guard < 16 do
    guard = guard + 1
    -- Spark = the moment the arrow leaves.
    local ns = sp.nSparks + 1
    sp.nSparks = ns
    sp.sparks[ns] = tf

    local ats = tf - windup      -- wind-up start (feeds the equilibrium calc)
    local ate = tf               -- fires
    local cycleStart = math.max(now, prevFire, castEnd)
    local W = state.shotpredict.windows

    -- Fluffy-style priority interval tiling (mirrors Rotation.lua):
    --   Steady is safe from the cycle start until its equilibrium cutoff.
    --   The remaining clip zone is filled by the top-priority castable
    --   substitute — Multi (off CD), else Arcane (off CD). Windows tile in
    --   time and never overlap, so a single full-height bar reads cleanly.
    -- Steady safe window: cycle start → the EARLIER of (a) its DPS-equilibrium
    -- cutoff vs Auto Shot and (b) the latest a Steady can start and still finish
    -- before the clip. (b) keeps the orange from running into the shot.
    --
    -- Deadlines are measured against `ats`, the WIND-UP START, not `ate` when the
    -- arrow leaves: a cast that overruns into the wind-up delays the shot by the
    -- overlap, so finishing "just before the shot" is already a clip.
    local steadyEnd = cycleStart
    local s = ABIL.steady
    if s.dps and s.dps > 0 then
      local eS = eqEnd(s, ats, ate, dpsAuto, safety, horizon)
      local clip = ats - (s.cast or 0) - safety
      if clip < eS then eS = clip end
      if eS < cycleStart then eS = cycleStart end
      steadyEnd = eS
      setSpan(W.steady, cycleStart, eS)
    end

    -- Clip breakpoint: the last absolute moment a Steady can still start and
    -- finish before this cycle's wind-up begins. The simplified (V3) ShotBars
    -- draws it as a hard tick instead of relying on the steady→filler boundary.
    do
      local clipT = ats - (ABIL.steady.cast or 0) - safety
      if clipT > now and clipT < horizon then
        local nc = sp.nClips + 1
        sp.nClips = nc
        sp.clips[nc] = clipT
      end
    end

    -- End of the last *colored* (safe-cast) window. The clip/danger block
    -- starts exactly here so every cycle stays fully tiled at any safety
    -- margin. Without this it was a fixed [ate-0.5, ate] block, which the
    -- safety margin pulled the cast windows in front of — leaving the bare
    -- black gap the user saw.
    local coloredEnd = steadyEnd

    -- Clip zone [steadyEnd, shot]: filled by the top-priority castable
    -- substitute. Multi/Arcane are off-GCD bursts, NOT filler — they're not
    -- equilibrium-limited; they fit as long as their (short/instant) cast
    -- completes before the clip. Priority Multi > Arcane (mirrors Rotation).
    if steadyEnd < ate then
      local placed = false
      if profile("shotBarsShowMulti", true) and offCd(state, now, "MS", steadyEnd) then
        local eM = math.min(horizon, ats - (ABIL.multi.cast or 0) - safety)
        if eM > steadyEnd then setSpan(W.multi, steadyEnd, eM); coloredEnd = eM; placed = true end
      end
      if not placed and profile("shotBarsShowArcane", true) and offCd(state, now, "Arc", steadyEnd) then
        local eA = math.min(horizon, ats - (ABIL.arcane.cast or 0) - safety)
        if eA > steadyEnd then setSpan(W.arcane, steadyEnd, eA); coloredEnd = eA end
      end
    end

    -- Clip "danger" block: from the end of the last safe-cast window to the
    -- WIND-UP START, not to the shot. Pressing inside the wind-up is queued by
    -- the client and comes out after the arrow at no cost (dummy-verified), so
    -- the last stretch before the shot is not dangerous — it is the free window
    -- the player weaves into. Only a cast that starts early enough to still be
    -- in flight when the wind-up wants to begin actually pushes the shot back.
    --
    -- The wind-up itself is then tiled as its own QUEUE window, so the bar stays
    -- gap-free without that stretch reading as an ordinary Steady window — it is
    -- castable, but the press is held rather than completing in time, and the two
    -- are indistinguishable if they share a colour.
    do
      local dangerEnd = ats < ate and ats or ate
      local ds = coloredEnd < now and now or coloredEnd
      local de = dangerEnd > horizon and horizon or dangerEnd
      if de > ds then setSpan(W.danger, ds, de) end
      local qs = de > ds and de or ds
      local qe = ate > horizon and horizon or ate
      if qe > qs then setSpan(W.queue, qs, qe) end
    end

    -- Melee weave lane (Fluffy's bottom row). The practical weave window is
    -- "step in any time this cycle EXCEPT the pre-shot clip zone" — you can
    -- land a Raptor / auto-attack as long as you're back before the shot.
    -- (W.raptor is reused as the melee-lane span list.)
    if profile("shotBarsShowRaptor", true) then
      local weaveEnd = ate - safety               -- last safe step-in moment
      local ge = weaveEnd > horizon and horizon or weaveEnd
      -- Whole melee lane starts only once the melee swing is off cooldown.
      local ws = cycleStart > meleeReady and cycleStart or meleeReady
      if ge > ws then
        -- white = auto-attack-only weave (Raptor on cooldown), green = Raptor
        -- ready. Split at the moment Raptor comes off cooldown.
        local split = raptorReady
        if split < ws then split = ws end
        if split > ge then split = ge end
        if split > ws then setSpan(W.weaveauto, ws, split) end
        if ge > split then setSpan(W.raptor, split, ge) end
      end

      -- No-weave / clip fill: end of the safe weave window → shot (red). Also
      -- suppressed while the swing is recharging so the lane is fully hidden.
      local cs = weaveEnd < now and now or weaveEnd
      if cs < meleeReady then cs = meleeReady end
      local ce = ate > horizon and horizon or ate
      if ce > cs then setSpan(W.weaveclip, cs, ce) end
    end

    prevFire = tf
    tf = tf + sd
  end
end

-- /nock shotbars — verify the damage model isn't degenerate (a near-zero
-- dpsAuto collapses the equilibrium to ≈ the shot time = one giant window).
function ShotPredictor:Dump()
  self:Recompute()
  local dpsAuto = recomputeDps()
  local sd = liveSwingDuration()
  local autoAvg = 0
  if UnitRangedDamage then
    local _, lo, hi = UnitRangedDamage("player")
    if lo and hi then autoAvg = (lo + hi) / 2 end
  end
  Nock:Print(("ShotBars: rap=%.0f autoAvg=%.0f(paperdoll) wpnAvg=%.1f(tooltip) ammoDps=%.1f")
    :format(S.rap, autoAvg, S.weaponAvg, S.ammoDps))
  Nock:Print(("  dpsAuto=%.1f dpsSteady=%.1f dpsMulti=%.1f dpsArcane=%.1f")
    :format(dpsAuto, ABIL.steady.dps or 0, ABIL.multi.dps or 0, ABIL.arcane.dps or 0))
  -- Sample: where Steady's safe window ends, as a fraction of the swing
  -- before the next shot (≈1 = window covers whole cycle = degenerate).
  local ats, ate = sd - autoCast(), sd
  local eq = equilibrium(ABIL.steady.dps or 0, ABIL.steady.cast or 0, ats, ate, dpsAuto)
  Nock:Print(("  swing=%.2fs  steadyCutoff=%.2fs before shot  arcaneCdb=%.1f multiCdb=%.1f")
    :format(sd, math.max(0, ate - eq), S.arcaneCdb, S.multiCdb))
end

-- Average damage per hit by diziet symbol (a s m A r w). Copies into `out`
-- so the caller can hold a stable table. Zero before the first Recompute.
function ShotPredictor:AverageDamage(out)
  out = out or {}
  for k, v in pairs(AVG) do out[k] = v end
  return out
end

----------------------------------------------------------------------------
-- Events. Stat recompute is event-driven + throttled; the per-tick Refresh
-- only does the cheap projection.
----------------------------------------------------------------------------

function ShotPredictor:OnEnable()
  self:Recompute()
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "Recompute")
  self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "Recompute")
  self:RegisterEvent("UNIT_INVENTORY_CHANGED", "OnUnitEvent")
  self:RegisterEvent("UNIT_RANGEDDAMAGE", "OnUnitEvent")
  self:RegisterEvent("PLAYER_TARGET_CHANGED", "Recompute")
  self:RegisterEvent("UNIT_AURA", "OnAura")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "OnVisualsChanged")
  self._lastAura = 0
end

function ShotPredictor:OnUnitEvent(_, unit)
  if unit == "player" then self:Recompute() end
end

-- UNIT_AURA fires very often; throttle to one recompute per 100ms and only
-- for player/target (HM, Expose Weakness, RAP buffs).
function ShotPredictor:OnAura(_, unit)
  if unit ~= "player" and unit ~= "target" then return end
  local now = GetTime()
  if now - (self._lastAura or 0) < 0.1 then return end
  self._lastAura = now
  self:Recompute()
end

function ShotPredictor:OnVisualsChanged()
  -- Switching into bars mode (or changing quiver assumption) → refresh stats.
  if barsMode() then self:Recompute() end
end
