-- Modules/BossMarkWatch.lua
-- Watches for a boss's single-target mark being aimed at YOU and publishes
-- state.bossMark, so UI/Frame_BossBanner.lua can shout "Feign Death now".
-- Two encounters share the engine, the banner and the cue; they differ only in
-- the rows of ENCOUNTERS below.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local BossMarkWatch = Nock:NewModule("BossMarkWatch", "AceEvent-3.0", "AceConsole-3.0")
local C = Nock.Constants
local E = Nock.BossMarkEngine

-- The unit-target check is a poll, so it rides the tick's slow lane. 10 Hz is
-- ~15 samples inside a 1.5s cast — far more than enough — and costs one
-- UnitGUID plus one UnitIsUnit per sample, against a single cached token.
BossMarkWatch.refreshInterval = 0.1

-- One row per mechanic. `gateUnitOnCast` is the only behavioural difference and
-- it is not cosmetic: Teron stands still and hits one person, so his unit target
-- is evidence on its own; Archimonde's target is the tank most of the fight and
-- fear and doomfires move it constantly, so it only means something while an
-- Air Burst is actually in flight.
local ENCOUNTERS = {
  {
    key            = "teron",
    label          = "Teron Gorefiend",
    npcId          = C.NpcID.TERON_GOREFIEND,
    spellId        = C.SpellID.SHADOW_OF_DEATH,
    spellLabel     = "Shadow of Death",
    enabledKey     = "warnBossMarkTeron",
    castTime       = 1.5,
    gateUnitOnCast = false,
    readyText      = "FEIGN DEATH NOW",
    noFdText       = "MARKED - NO FD",
  },
  {
    key            = "archimonde",
    label          = "Archimonde",
    npcId          = C.NpcID.ARCHIMONDE,
    spellId        = C.SpellID.AIR_BURST,
    spellLabel     = "Air Burst",
    enabledKey     = "warnBossMarkArchimonde",
    castTime       = 1.7,
    gateUnitOnCast = true,
    readyText      = "FEIGN DEATH NOW",
    noFdText       = "AIR BURST - NO FD",
  },
}

-- Lookups so the combat-log filter stays one table index after the subevent
-- check, however many encounters this list grows to.
local BY_SPELL, BY_NPC = {}, {}
for _, enc in ipairs(ENCOUNTERS) do
  enc.state = E.New(enc)
  BY_SPELL[enc.spellId] = enc
  BY_NPC[enc.npcId] = enc
end

local _playerGUID
-- One cached boss handle, not one per encounter: these two bosses live in
-- different raids and can never be up at the same time, so a single token keeps
-- the per-tick cost identical to the one-boss version.
local _bossUnit, _bossGUID, _bossEnc

-- Field 6 of a creature GUID is the NPC id:
--   Creature-0-3134-564-13-22871-000136DF9E
-- Player GUIDs ("Player-<realm>-<hex>") have no such field and simply fail the
-- match, so no type check is needed first.
local function npcIdOf(guid)
  if not guid then return nil end
  local id = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  return id and tonumber(id) or nil
end

local function encounterFor(guid)
  local id = npcIdOf(guid)
  return id and BY_NPC[id] or nil
end

-- Master gate: the warnings system, then this warning.
local function warningsOn()
  local p = Nock.db and Nock.db.profile
  if not p then return false end
  if p.showWarnings == false then return false end
  return p.warnBossMarkEnabled ~= false
end

-- Per-encounter gate on top of it, so someone who only raids one of the two can
-- switch the other off without losing the banner.
local function encEnabled(enc)
  if not warningsOn() then return false end
  return Nock.db.profile[enc.enabledKey] ~= false
end

-- Feign Death's own cooldown, not the GCD. A GCD-length reading is the global,
-- which does not stop you pressing FD a heartbeat later — treating it as "on
-- cooldown" would swap the banner to the useless text for the first second of
-- every cast.
local function fdReady()
  local start, dur
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(C.SpellID.FEIGN_DEATH)
    if info then start, dur = info.startTime, info.duration end
  elseif GetSpellCooldown then
    start, dur = GetSpellCooldown(C.SpellID.FEIGN_DEATH)
  end
  if not start or start == 0 or not dur or dur == 0 then return true end
  if dur <= (C.GCD_BASE or 1.5) + 0.05 then return true end
  return (start + dur - GetTime()) <= 0
end

-- Nock ships no audio, so the configured cue only resolves if the user has a
-- media library ("Air Horn" comes from DBM / BigWigs). A missing pick must not
-- turn the loudest warning in the addon into a silent one, so it falls back to
-- the client's own raid-warning kit. An explicit "None" is still honoured —
-- that is someone deliberately asking for a silent banner.
local function playAlarm()
  local p = Nock.db and Nock.db.profile
  local name = p and p.warnBossMarkSound
  if name == "None" then return end
  local LSM = LibStub("LibSharedMedia-3.0", true)
  local path = (LSM and name and name ~= "") and LSM:Fetch("sound", name, true) or nil
  if path and PlaySoundFile then
    PlaySoundFile(path, "Master")
    return
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
  end
end

function BossMarkWatch:OnEnable()
  _playerGUID = UnitGUID and UnitGUID("player")
  self:RegisterEvent("PLAYER_LOGIN", "CachePlayerGUID")
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCombatLog")
  -- Finding the boss is event-driven: no sweep over forty nameplate tokens per
  -- tick, just a note when one appears and a check that it is still him.
  self:RegisterEvent("NAME_PLATE_UNIT_ADDED",   "OnNameplateAdded")
  self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnNameplateRemoved")
  self:RegisterEvent("PLAYER_TARGET_CHANGED",   "OnTargetChanged")
  self:RegisterEvent("PLAYER_ENTERING_WORLD",   "OnEnteringWorld")
end

function BossMarkWatch:CachePlayerGUID()
  _playerGUID = UnitGUID and UnitGUID("player")
end

function BossMarkWatch:NoteUnit(unit)
  if not unit then return end
  local guid = UnitGUID and UnitGUID(unit)
  if not guid then return end
  local enc = encounterFor(guid)
  if enc then
    _bossUnit, _bossGUID, _bossEnc = unit, guid, enc
  end
end

function BossMarkWatch:OnNameplateAdded(_, unit) self:NoteUnit(unit) end

function BossMarkWatch:OnNameplateRemoved(_, unit)
  if unit == _bossUnit then _bossUnit, _bossGUID, _bossEnc = nil, nil, nil end
end

function BossMarkWatch:OnTargetChanged() self:NoteUnit("target") end

function BossMarkWatch:OnEnteringWorld()
  -- Zoning invalidates every unit token, and a mark cannot survive a loading
  -- screen anyway.
  _bossUnit, _bossGUID, _bossEnc = nil, nil, nil
  for _, enc in ipairs(ENCOUNTERS) do
    enc.state = E.New(enc)
    enc.lastCast = nil
  end
end

-- Only three subevents matter, and only for the handful of spells in the table.
-- Both filters are cheap compares and run before anything else touches the
-- payload.
function BossMarkWatch:OnCombatLog()
  local _, sub, _, srcGUID, srcName, _, _, dstGUID, dstName, _, _, spellId =
    CombatLogGetCurrentEventInfo()
  if sub ~= "SPELL_CAST_START" and sub ~= "SPELL_CAST_SUCCESS"
     and sub ~= "SPELL_AURA_APPLIED" then
    return
  end
  local enc = BY_SPELL[spellId]
  if not enc then return end
  if not encEnabled(enc) then return end

  local now = GetTime()
  if sub == "SPELL_CAST_START" then
    -- A destination the log does not carry is NOT evidence that it isn't you;
    -- it hands the decision to the unit check instead. Whether this client logs
    -- one at all is the open question this whole two-path design exists for.
    local dest = "unknown"
    if dstGUID and dstGUID ~= "" then
      dest = (dstGUID == _playerGUID) and "me" or "other"
    end
    E.CastStart(enc.state, now, dest)
    enc.lastCast = {
      at = now, dest = dest, dstGUID = dstGUID, dstName = dstName,
      srcGUID = srcGUID, srcName = srcName,
    }
  else
    E.CastEnded(enc.state, now)
    if enc.lastCast then enc.lastCast.landedOn = dstName or dstGUID end
  end
end

local function clearBanner(b)
  if b.active then
    b.active, b.text, b.remaining, b.source, b.encounter = false, "", 0, nil, nil
  end
end

function BossMarkWatch:Refresh(state)
  local b = state.bossMark
  if not warningsOn() then
    clearBanner(b)
    self._sounded = nil
    return
  end

  local now = GetTime()

  -- Nameplate tokens are recycled, so the cached one is only trusted while its
  -- GUID still matches the boss we recorded.
  if _bossUnit then
    if not (UnitGUID and UnitGUID(_bossUnit) == _bossGUID) then
      _bossUnit, _bossGUID, _bossEnc = nil, nil, nil
    elseif _bossEnc and encEnabled(_bossEnc)
       and UnitExists and UnitExists(_bossUnit .. "target")
       and UnitIsUnit and UnitIsUnit(_bossUnit .. "target", "player") then
      E.BossTarget(_bossEnc.state, now, true)
    end
  end

  -- Only one of these bosses can be up, so the first active row is the answer.
  local hit
  for _, enc in ipairs(ENCOUNTERS) do
    if encEnabled(enc) and E.Active(enc.state, now) then hit = enc; break end
  end

  if hit then
    if self._sounded ~= hit.key then
      self._sounded = hit.key
      playAlarm()
    end
    b.active    = true
    b.text      = E.Text(hit.state, fdReady())
    b.remaining = math.max(0, hit.state.markedUntil - now)
    b.source    = hit.state.source
    b.encounter = hit.key
  else
    self._sounded = nil
    clearBanner(b)
    for _, enc in ipairs(ENCOUNTERS) do enc.state.source = nil end
  end
end

-- Preview: raise the banner and play the cue for real, so it can be placed and
-- the sound auditioned before the raid rather than during it.
--
-- Says why when it can't. A preview that silently does nothing because the
-- warning happens to be switched off reads as a broken feature, and this is the
-- one command someone runs precisely because they are unsure it works.
function BossMarkWatch:Preview(which)
  local p = Nock.db and Nock.db.profile
  if p and p.showWarnings == false then
    self:Print("Warnings are switched off entirely — turn on 'Enable warnings' to see this.")
    return
  end
  if p and p.warnBossMarkEnabled == false then
    self:Print("The boss-mark alert is switched off — turn it on under Warnings.")
    return
  end

  local pick
  for _, enc in ipairs(ENCOUNTERS) do
    if (not which or enc.key == which) and encEnabled(enc) then pick = enc; break end
  end
  if not pick then
    self:Print(which
      and ("No enabled encounter called '%s' — try teron or archimonde."):format(which)
      or  "Both encounters are switched off — turn one on under Warnings.")
    return
  end

  E.CastStart(pick.state, GetTime(), "me")
  self._sounded = nil
  self:Print(("Boss-mark preview (%s) — %.1fs. Unlock frames to drag it; the sound is your '%s' pick.")
    :format(pick.label, E.HOLD, tostring(p and p.warnBossMarkSound or "None")))
end

-- /nock bossmark. Neither encounter has been seen by this code, so which of the
-- two detections actually works is unknown — this prints what the last cast
-- carried and what the unit lookup can see, so one pull settles it.
function BossMarkWatch:Dump()
  self:Print(("Boss-mark watch: %s"):format(warningsOn() and "on" or "OFF"))
  if _bossUnit and _bossEnc then
    local tgt = _bossUnit .. "target"
    self:Print(("boss unit: %s = %s (%s), targeting %s%s"):format(
      _bossUnit, _bossEnc.label,
      (UnitName and UnitName(_bossUnit)) or "?",
      (UnitExists and UnitExists(tgt) and UnitName and UnitName(tgt)) or "nobody",
      (UnitIsUnit and UnitExists and UnitExists(tgt) and UnitIsUnit(tgt, "player"))
        and " |cffff2020(YOU)|r" or ""))
  else
    self:Print("boss unit: not found — needs a tracked boss's nameplate up, or him targeted.")
  end
  for _, enc in ipairs(ENCOUNTERS) do
    local gate = enc.gateUnitOnCast and "cast-gated" or "ungated"
    self:Print(("|cffffd200%s|r (%s, %d) — %s, unit check %s"):format(
      enc.label, enc.spellLabel, enc.spellId,
      encEnabled(enc) and "on" or "OFF", gate))
    local lc = enc.lastCast
    if lc then
      self:Print(("  last cast: %.0fs ago, source %s, log destination %s (%s)%s"):format(
        GetTime() - lc.at, tostring(lc.srcName),
        lc.dest, tostring(lc.dstName or "none"),
        lc.landedOn and (", landed on " .. tostring(lc.landedOn)) or ""))
      if lc.dest == "unknown" then
        self:Print(enc.gateUnitOnCast
          and "  |cffffd200The log carried no destination|r — the unit check decides, but only during the cast."
          or  "  |cffffd200The log carried no destination|r — the unit check is doing the work here.")
      end
    else
      self:Print("  last cast: none seen this session.")
    end
  end
end
