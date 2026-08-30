-- Modules/SlammerWatch.lua
-- Watches Anetheron's Sleep and your Sulfuron Slammer buff, drives the pure
-- engine (Modules/SlammerEngine.lua) and publishes state.slammer for the
-- clickable button (UI/Frame_SlammerButton.lua). Also decides when the button
-- may be on screen at all: it is a secure frame, so the client will not let us
-- show or hide it in combat — it shows when Anetheron is SEEN out of combat
-- (target him before the pull; the Hyjal waves drop combat between them) and
-- hides when he dies or you leave.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local SlammerWatch = Nock:NewModule("SlammerWatch", "AceEvent-3.0", "AceConsole-3.0")
local C = Nock.Constants
local E = Nock.SlammerEngine

-- Everything here is a countdown or a bag count: 10 Hz is plenty, and the
-- button's pulse runs off its own tick.
SlammerWatch.refreshInterval = 0.1

-- The count is a bag read; every half second is more than the bag changes.
local COUNT_EVERY = 0.5

local _playerGUID
local _bossUnit, _bossGUID   -- the last unit token that was him, for the dump
local _seen, _dead           -- he is in view right now (target / mouseover / nameplate / boss1) / he died
local _preview               -- /nock slammer test holds the button open
local _sim                   -- /nock slammer sim: { interval, castTime, nextStart, nextCast, n } — a fake boss on a clock
local _encStartSeen, _encEndSeen   -- whether this client fires the encounter events at all
local _lastCast              -- { at, srcName } for the dump
local _lastEnc               -- { id, name, at } of ANY encounter start: proves the event fires here
local _countAt = 0
local _auraDirty             -- UNIT_AURA on the player since the last scan
local _buffName, _buffId     -- the Slammer's use effect off the item itself

-- Field 6 of a creature GUID is the NPC id (see BossMarkWatch.lua).
local function npcIdOf(guid)
  if not guid then return nil end
  local id = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  return id and tonumber(id) or nil
end

local function isAnetheron(guid)
  return npcIdOf(guid) == C.NpcID.ANETHERON
end

-- Master gate: the warnings system, then this warning.
local function enabled()
  local p = Nock.db and Nock.db.profile
  if not p then return false end
  if p.showWarnings == false then return false end
  return p.warnSlammerEnabled ~= false
end

-- Nock ships no audio: a configured cue only resolves through a media
-- library, and a missing pick falls back to a client sound kit so an install
-- without DBM/BigWigs/WeakAuras does not get a silent cue. "None" is an
-- explicit mute and is honoured. Same rule as the boss-mark banner.
-- The client's own kit ids, for a SOUNDKIT table that lacks the name.
local KIT_IDS = { RAID_WARNING = 8959, READY_CHECK = 8960 }

local function playCue(profileKey, fallbackKit)
  local p = Nock.db and Nock.db.profile
  local name = p and p[profileKey]
  if name == "None" then return end
  local LSM = LibStub("LibSharedMedia-3.0", true)
  local path = (LSM and name and name ~= "") and LSM:Fetch("sound", name, true) or nil
  if path and PlaySoundFile then
    PlaySoundFile(path, "Master")
    return
  end
  local kit = (SOUNDKIT and SOUNDKIT[fallbackKit]) or KIT_IDS[fallbackKit]
  if PlaySound and kit then PlaySound(kit, "Master") end
end

-- The horn: an exposed cast. The softer one: the window opening (the
-- reference WA's Glass; the ready-check chime when no library has it).
local function playHorn()  playCue("warnSlammerSound", "RAID_WARNING") end
local function playChime() playCue("warnSlammerWindowSound", "READY_CHECK") end

-- The aura's id was read off the Wrath-era database (50986); this client may
-- file the drink under another id or only by name. GetItemSpell hands back the
-- item's own use effect, so the match is by that name OR id, and by 50986 —
-- whichever this client uses. Lazy: the item info may not be cached at load.
local function itemSpell()
  if _buffName then return _buffName, _buffId end
  local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
  if not fn then return nil end
  local ok, name, id = pcall(fn, C.SULFURON_SLAMMER_ITEM)
  if ok and name then _buffName, _buffId = name, tonumber(id) end
  return _buffName, _buffId
end

local function isSlammerAura(spellId, spellName)
  if spellId == C.SpellID.SULFURON_SLAMMER then return true end
  local name, id = itemSpell()
  if id and spellId == id then return true end
  return name ~= nil and spellName == name
end

local function slammerCount()
  if not GetItemCount then return 0 end
  local ok, n = pcall(GetItemCount, C.SULFURON_SLAMMER_ITEM)
  return (ok and tonumber(n)) or 0
end

-- The buff's exact expiry off the aura list — the combat log carries none.
-- Called at engage and when the button comes up, not per tick: the log's
-- APPLIED/REFRESH/REMOVED keep it current in between.
-- Scans both lists: a drink that burns you may well be filed as harmful.
-- `match(name, id, exp)` returns true to stop; the first hit's expiry comes
-- back, or nil.
-- Aura reads go through Core/AuraCache.lua (every read allocates ~1.9 KB on
-- this client). `match(name, spellId, exp)` over every record on the player,
-- helpful or harmful (the drink's burn may be filed either way).
local AC = Nock.AuraCache
local sc_match, sc_hit
local function onPlayerAura(a)
  if sc_hit then return end
  if sc_match(a.name, a.spellId, a.expirationTime) then sc_hit = a.expirationTime or 0 end
end
local function scanList(_, _, match)
  if not AC then return nil end
  sc_match, sc_hit = match, nil
  AC.ForEach("player", onPlayerAura)
  return sc_hit
end

local function matchSlammer(name, id) return isSlammerAura(id, name) end

local function scanBuff()
  if not (UnitExists and UnitExists("player")) then return nil end
  local CU = C_UnitAuras
  return scanList(CU and CU.GetBuffDataByIndex, UnitBuff, matchSlammer)
      or scanList(CU and CU.GetDebuffDataByIndex, UnitDebuff, matchSlammer)
end

-- For the dump: every aura on you whose name mentions the drink, with its id,
-- so a wrong 50986 is a copybox away from being corrected.
local function listSlammerLike(lines)
  local CU = C_UnitAuras
  local seen = 0
  local function note(kind, name, id)
    seen = seen + 1
    lines[#lines + 1] = ("  %s: %s (%s)"):format(kind, tostring(name), tostring(id))
  end
  scanList(CU and CU.GetBuffDataByIndex, UnitBuff, function(name, id)
    if name and (name:find("Slammer") or name:find("Sulfuron")) then note("buff", name, id) end
    return false
  end)
  scanList(CU and CU.GetDebuffDataByIndex, UnitDebuff, function(name, id)
    if name and (name:find("Slammer") or name:find("Sulfuron")) then note("debuff", name, id) end
    return false
  end)
  return seen
end

function SlammerWatch:OnInitialize()
  self.st = E.New()
  -- One reused config table: Refresh compares the sliders against it and only
  -- calls Configure on a change (no per-tick allocation).
  self._cfg = { window = E.DEFAULT.window, margin = E.DEFAULT.margin }
end

function SlammerWatch:OnEnable()
  _playerGUID = UnitGUID and UnitGUID("player")
  self:RegisterEvent("PLAYER_LOGIN", "CachePlayerGUID")
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCombatLog")
  self:RegisterEvent("NAME_PLATE_UNIT_ADDED",   "OnNameplateAdded")
  self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnNameplateRemoved")
  self:RegisterEvent("PLAYER_TARGET_CHANGED",   "OnTargetChanged")
  self:RegisterEvent("UPDATE_MOUSEOVER_UNIT",   "OnMouseover")
  self:RegisterEvent("PLAYER_ENTERING_WORLD",   "OnEnteringWorld")
  self:RegisterEvent("PLAYER_REGEN_ENABLED",    "OnRegen")
  -- The aura list is the truth about the buff (exact expiry, whatever id or
  -- list this client files it under); the log's aura events are the fast
  -- path. Dirty-flagged and scanned on the slow lane, only while the button
  -- has a reason to be up.
  -- No UNIT_AURA here: the aura cache listens; Refresh reads its revision.
  -- Whether the Anniversary client fires these is the open question the dump
  -- answers; AceEvent hard-errors on an unknown event, hence the pcalls. The
  -- fallbacks (the boss seen in combat, the first Sleep) cover their absence.
  pcall(self.RegisterEvent, self, "ENCOUNTER_START", "OnEncounterStart")
  pcall(self.RegisterEvent, self, "ENCOUNTER_END",   "OnEncounterEnd")
  pcall(self.RegisterEvent, self, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "OnEngageUnit")
end


function SlammerWatch:CachePlayerGUID()
  _playerGUID = UnitGUID and UnitGUID("player")
end

-- A unit that is him, alive, makes the button show (out of combat). A unit
-- that is him IN combat with no window running is the engage fallback.
function SlammerWatch:NoteUnit(unit)
  if not unit or not UnitGUID then return end
  local guid = UnitGUID(unit)
  if not guid or not isAnetheron(guid) then return end
  _bossUnit, _bossGUID = unit, guid
  if UnitIsDead and UnitIsDead(unit) then
    _dead = true
    return
  end
  _seen, _dead = true, false
  if not E.Active(self.st) and UnitAffectingCombat and UnitAffectingCombat(unit)
     and UnitAffectingCombat("player") then
    self:Engage("unit")
  end
end

function SlammerWatch:OnNameplateAdded(_, unit) self:NoteUnit(unit) end
function SlammerWatch:OnNameplateRemoved(_, unit)
  if unit == _bossUnit then _bossUnit, _bossGUID = nil, nil end
end

-- Is he in view right now? The cached token first (a nameplate, validated by
-- GUID since tokens recycle), then the few tokens that can be him. Four
-- UnitGUID calls at 10 Hz; the events above keep the cache warm. The button
-- shows only while this is true (user: "only visible when Anetheron is
-- visible / targeted" — the waves drop combat and he stands alone, so the
-- sighting is the natural gate) or while a fight with him is running.
local VIEW_TOKENS = { "target", "boss1", "mouseover" }
function SlammerWatch:InView()
  if not UnitGUID then return false end
  if _bossUnit then
    if UnitGUID(_bossUnit) == _bossGUID then
      if not (UnitIsDead and UnitIsDead(_bossUnit)) then return true end
    else
      _bossUnit, _bossGUID = nil, nil
    end
  end
  for i = 1, #VIEW_TOKENS do
    local u = VIEW_TOKENS[i]
    local guid = UnitGUID(u)
    if guid and isAnetheron(guid) and not (UnitIsDead and UnitIsDead(u)) then
      _bossUnit, _bossGUID = u, guid
      return true
    end
  end
  return false
end
function SlammerWatch:OnTargetChanged() self:NoteUnit("target") end
function SlammerWatch:OnMouseover() self:NoteUnit("mouseover") end
function SlammerWatch:OnEngageUnit()
  for i = 1, 5 do
    local u = "boss" .. i
    if UnitExists and UnitExists(u) then self:NoteUnit(u) end
  end
end

-- The cast bar's real length, off whichever unit token is him right now. Nil
-- when none is in view (the engine then uses its configured castTime).
local function bossCastDuration()
  if not UnitCastingInfo then return nil end
  local tokens = { _bossUnit, "target", "boss1", "focus", "mouseover" }
  for i = 1, #tokens do
    local u = tokens[i]
    if u and UnitExists and UnitExists(u) and isAnetheron(UnitGUID(u)) then
      local _, _, _, startMs, endMs = UnitCastingInfo(u)
      if startMs and endMs and endMs > startMs then return (endMs - startMs) / 1000 end
    end
  end
  return nil
end

function SlammerWatch:OnEncounterStart(_, id, name)
  _lastEnc = _lastEnc or {}
  _lastEnc.id, _lastEnc.name, _lastEnc.at = tonumber(id), name, GetTime()
  if tonumber(id) ~= C.ANETHERON_ENCOUNTER then return end
  _encStartSeen = true
  _seen = true
  self:Engage("encounter")
end

function SlammerWatch:OnEncounterEnd(_, id, _, _, _, success)
  if tonumber(id) ~= C.ANETHERON_ENCOUNTER then return end
  _encEndSeen = true
  E.Reset(self.st)
  -- A kill hides the button (out of combat, by the frame); a wipe leaves it
  -- up for the next pull.
  if tonumber(success) == 1 then _dead = true end
end

-- Leaving combat with him out of view is the fight ending — a raid encounter
-- holds you in combat until it is over (Feign Death included). This is the
-- wipe detector for a client whose ENCOUNTER_END may not fire; a kill goes
-- through UNIT_DIED. Never in a preview or the sim (no boss to be in view of).
function SlammerWatch:OnRegen()
  if _preview then return end
  if E.Active(self.st) and not self:InView() then E.Reset(self.st) end
end

function SlammerWatch:Engage(source)
  E.Engage(self.st, GetTime())
  E.SetBuff(self.st, scanBuff())
  self._engagedBy = source
end

function SlammerWatch:OnEnteringWorld()
  -- Zoning invalidates every unit token, and the fight with it.
  _bossUnit, _bossGUID = nil, nil
  _seen, _dead = false, false
  _preview = nil
  E.Reset(self.st)
end

-- Five subevents, three spells, one NPC — every other line returns on the
-- first compare.
function SlammerWatch:OnCombatLog()
  -- Off (the shipped default): not a single compare more. Below this the
  -- aura branch runs an item lookup on every aura/cast aimed at the player
  -- while the drink's info is uncached -- forever, for anyone without one.
  if not enabled() then return end
  local _, sub, _, srcGUID, srcName, _, _, dstGUID, _, _, _, spellId, spellName =
    CombatLogGetCurrentEventInfo()
  if sub == "UNIT_DIED" then
    if isAnetheron(dstGUID) then
      _dead = true
      E.Reset(self.st)
    end
    return
  end
  if sub ~= "SPELL_CAST_SUCCESS" and sub ~= "SPELL_CAST_START" and sub ~= "SPELL_AURA_APPLIED"
     and sub ~= "SPELL_AURA_REFRESH" and sub ~= "SPELL_AURA_REMOVED" then
    return
  end
  if spellId == C.SpellID.SLEEP_ANETHERON then
    local now = GetTime()
    if sub == "SPELL_CAST_START" then
      _seen = true
      E.SetBuff(self.st, scanBuff())   -- the exact expiry, for the end-of-cast test
      E.CastStart(self.st, now, bossCastDuration())
      self._castSeen = (self._castSeen or 0) + 1
      if E.TakeAlert(self.st) then playHorn() end
    elseif sub == "SPELL_CAST_SUCCESS" then
      _seen = true
      _lastCast = _lastCast or {}
      _lastCast.at, _lastCast.srcName = now, srcName
      E.CastSucceeded(self.st, now)
      if E.TakeAlert(self.st) then playHorn() end
    elseif dstGUID == _playerGUID then
      if sub == "SPELL_AURA_REMOVED" then E.Woke(self.st)
      else E.Slept(self.st, now) end
    end
  elseif dstGUID == _playerGUID and isSlammerAura(spellId, spellName) then
    if sub == "SPELL_AURA_REMOVED" then
      E.SetBuff(self.st, nil)
    elseif sub ~= "SPELL_CAST_SUCCESS" and sub ~= "SPELL_CAST_START" then
      E.SetBuff(self.st, GetTime() + self.st.cfg.buffDur)
    end
    _auraDirty = true   -- the list has the exact expiry; pick it up next lane
  end
end

function SlammerWatch:Refresh(state)
  local s = state.slammer
  local now = GetTime()
  local p = Nock.db and Nock.db.profile
  local on = enabled()

  -- Off: the idle shape and nothing else -- no unit probes (InView is three
  -- UnitGUID + GUID captures), no bag count, no aura scan. The button ships
  -- off, so this is every zone for most users.
  if not on then
    _seen = false
    s.visible, s.bossSeen = false, false
    if s.state ~= "idle" then
      s.state, s.label, s.value, s.remaining, s.verdict = "idle", "", nil, 0, nil
    end
    s.count = self.st.count
    return
  end

  -- The simulation owns the window while it runs (scaled to its interval);
  -- the profile's sliders take over again when it stops.
  if p and not _sim then
    local w, m = tonumber(p.slammerWindow), tonumber(p.slammerCoverMargin)
    local cfg = self._cfg
    if (w and w ~= cfg.window) or (m and m ~= cfg.margin) then
      cfg.window, cfg.margin = w or cfg.window, m or cfg.margin
      E.Configure(self.st, cfg)
    end
  end

  if _sim and on then
    if _sim.nextStart and now >= _sim.nextStart then
      _sim.nextStart = nil
      E.SetBuff(self.st, scanBuff())
      E.CastStart(self.st, now, _sim.castTime)
      if E.TakeAlert(self.st) then playHorn() end
    end
    if now >= _sim.nextCast then
      _sim.n = _sim.n + 1
      self:FakeCast(("sim #%d"):format(_sim.n))
      _sim.nextCast  = now + _sim.interval
      _sim.nextStart = _sim.nextCast - _sim.castTime
    end
  end

  if now >= _countAt then
    _countAt = now + COUNT_EVERY
    E.SetCount(self.st, slammerCount())
  end

  -- The aura store's revision moves whenever an aura on you changes.
  local rev = AC and AC.Rev("player") or 0
  if (_auraDirty or rev ~= self._auraRev) and (_preview or _seen or E.Active(self.st)) then
    _auraDirty, self._auraRev = false, rev
    E.SetBuff(self.st, scanBuff())
  end

  -- In view, or a fight with him running (a nameplate that blinked out must
  -- not hide the button mid-fight — the frame could not bring it back until
  -- regen anyway). OnRegen drops a fight you left with him out of view.
  local inView = self:InView()
  _seen = inView
  local fightOn = E.Active(self.st)

  -- The wish; the frame applies it out of combat. The unlock preview is the
  -- frame's own business.
  s.visible  = (_preview or ((inView or fightOn) and not _dead)) or false
  s.bossSeen = inView
  E.Describe(self.st, now, s)
  if E.TakeWindowAlert(self.st, now) then playChime() end
end

-- /nock slammer test: hold the button open with a five-second first window so
-- it can be placed and clicked — a real button, so a click really drinks.
-- Refuses with a reason when the warning is off (a silent no-op reads as
-- broken).
function SlammerWatch:Preview(on)
  local p = Nock.db and Nock.db.profile
  if on then
    if p and p.showWarnings == false then
      self:Print("Warnings are switched off entirely — turn on 'Enable warnings' to see this.")
      return
    end
    if p and p.warnSlammerEnabled == false then
      self:Print("The Slammer button is switched off — turn it on under Warnings → Boss.")
      return
    end
    if InCombatLockdown and InCombatLockdown() then
      self:Print("In combat — the button can only be shown out of combat.")
      return
    end
    _preview = true
    -- Engage, then pull the window in to 5 s.
    self:Engage("preview")
    self.st.windowAt = GetTime() + 5
    self:Print(("Slammer preview: window in 5 s (%d in your bags). "
      .. "/nock slammer cast fakes a Sleep; /nock slammer off ends it."):format(self.st.count))
  else
    _preview = nil
    if _sim then
      _sim = nil
      -- Hand the window back to the sliders: forget what Refresh last synced
      -- so the next tick re-applies the profile's numbers.
      E.Configure(self.st, { firstWindow = E.DEFAULT.firstWindow })
      self._cfg.window, self._cfg.margin = nil, nil
    end
    E.Reset(self.st)
    self:Print("Slammer preview off.")
  end
end

-- A Sleep goes out now — the verdict on whatever buff you have, the horn if
-- it is exposed, and (exposed) the Sleep lands on you for as long as the
-- next fake cast allows. `tag` names the caller in the chat line.
function SlammerWatch:FakeCast(tag)
  local now = GetTime()
  E.SetBuff(self.st, scanBuff())
  local v = E.CastSucceeded(self.st, now)
  if E.TakeAlert(self.st) then playHorn() end
  if v == "exposed" then
    if _sim then
      E.Slept(self.st, now, now + math.min(self.st.cfg.sleepDur, math.max(1, _sim.interval - 1)))
    end
  end
  self:Print(("%s: Sleep went out — %s."):format(tag, v == "covered" and "covered, quiet" or "EXPOSED, horn"))
  return v
end

-- /nock slammer cast: one fake Sleep, now.
function SlammerWatch:PreviewCast()
  if not enabled() then
    self:Print("The Slammer button is switched off — turn it on under Warnings → Boss.")
    return
  end
  self:FakeCast("Fake Sleep")
end

-- /nock slammer sim [secs]: a fake Anetheron casting Sleep every `secs`
-- (default 5), the window scaled to it (open for the last 40 % of each
-- cycle) so the whole loop plays: wait -> CLICK NOW -> drink -> COVERED ->
-- cast -> verdict -> wait. A real button: every click drinks a real Slammer.
-- Runs off the slow lane; `/nock slammer off` ends it and hands the window
-- back to the sliders.
function SlammerWatch:Sim(secs)
  local p = Nock.db and Nock.db.profile
  if p and p.showWarnings == false then
    self:Print("Warnings are switched off entirely — turn on 'Enable warnings' to see this.")
    return
  end
  if p and p.warnSlammerEnabled == false then
    self:Print("The Slammer button is switched off — turn it on under Warnings → Boss.")
    return
  end
  if InCombatLockdown and InCombatLockdown() then
    self:Print("In combat — the button can only be shown out of combat.")
    return
  end
  local interval = tonumber(secs) or 5
  if interval < 3 then interval = 3 end
  local castTime = math.min(2, interval / 2)
  local now = GetTime()
  _preview = true
  _sim = { interval = interval, castTime = castTime, n = 0,
           nextCast = now + interval, nextStart = now + interval - castTime }
  local window = interval * 0.5
  E.Configure(self.st, { window = window, firstWindow = window })
  self:Engage("sim")
  self:Print(("Slammer sim: a Sleep every %.0f s with a %.1f s cast bar before it; the window opens "
    .. "%.1f s after each (%d in your bags). /nock slammer off ends it."):format(interval, castTime, window, self.st.count))
end

-- /nock slammer slept: as if that Sleep landed on you — SLEPT for 10 s (red
-- if the last verdict was exposed, amber if covered).
function SlammerWatch:PreviewSlept()
  if not enabled() then
    self:Print("The Slammer button is switched off — turn it on under Warnings → Boss.")
    return
  end
  E.Slept(self.st, GetTime())
  self:Print("Fake Sleep on you: SLEPT for 10 s.")
end

-- /nock slammer: what the watcher can see, in a copybox.
function SlammerWatch:Dump()
  local st = self.st
  local now = GetTime()
  local lines = {}
  local function add(fmt, ...) lines[#lines + 1] = fmt:format(...) end
  add("Slammer watch: %s", enabled() and "on" or "OFF")
  add("boss in view: %s, dead: %s, fight running: %s, preview: %s, sim: %s", tostring(_seen or false),
    tostring(_dead or false), tostring(E.Active(st)), tostring(_preview or false),
    _sim and ("every %.0fs, %d casts"):format(_sim.interval, _sim.n) or "off")
  if _bossUnit and UnitGUID and UnitGUID(_bossUnit) == _bossGUID then
    add("boss unit: %s (%s)%s", _bossUnit, (UnitName and UnitName(_bossUnit)) or "?",
      (UnitAffectingCombat and UnitAffectingCombat(_bossUnit)) and " in combat" or "")
  else
    add("boss unit: not in view")
  end
  add("ENCOUNTER_START seen: %s, ENCOUNTER_END seen: %s, engaged by: %s",
    tostring(_encStartSeen or false), tostring(_encEndSeen or false), tostring(self._engagedBy or "-"))
  if _lastEnc then
    add("last ENCOUNTER_START of any kind: %s (%s), %.0fs ago — the event fires on this client",
      tostring(_lastEnc.id), tostring(_lastEnc.name), now - _lastEnc.at)
  else
    add("no ENCOUNTER_START of any kind seen this session")
  end
  add("engine: %s, window at %s, buff until %s, slept until %s, verdict %s, count %d",
    E.State(st, now),
    st.windowAt and ("%+.1fs"):format(st.windowAt - now) or "-",
    st.buffUntil and ("%+.1fs"):format(st.buffUntil - now) or "-",
    st.sleptUntil and ("%+.1fs"):format(st.sleptUntil - now) or "-",
    tostring(st.verdict or "-"), st.count)
  add("config: window %.1f, first %.1f, margin %.1f, buff %.1f, cast fallback %.1f", st.cfg.window,
    st.cfg.firstWindow, st.cfg.margin, st.cfg.buffDur, st.cfg.castTime)
  add("Sleep cast starts seen this session: %d%s", self._castSeen or 0,
    st.castStartAt and st.castEndAt and (" (last: %.2f s bar)"):format(st.castEndAt - st.castStartAt) or "")
  if _lastCast then
    add("last Sleep: %.0fs ago by %s", now - _lastCast.at, tostring(_lastCast.srcName))
  else
    add("last Sleep: none seen this session")
  end
  add("item %d: %s", C.SULFURON_SLAMMER_ITEM,
    (GetItemInfo and GetItemInfo(C.SULFURON_SLAMMER_ITEM)) or "not cached")
  local bn, bi = itemSpell()
  add("item use effect: %s (%s); matching aura ids: %d / %s", tostring(bn or "not cached"),
    tostring(bi or "?"), C.SpellID.SULFURON_SLAMMER, tostring(bi or "?"))
  add("auras on you mentioning the drink:")
  if listSlammerLike(lines) == 0 then add("  none right now") end
  local exp = scanBuff()
  add("aura scan: %s", exp and ("found, %+.1fs"):format(exp - now) or "not found")
  Nock.UI.ShowCopyBox(table.concat(lines, "\n"))
end
