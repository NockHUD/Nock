-- Forever/Cooldowns.lua
-- The Forever `Cooldowns` module: own casts + learned durations (the ledger)
-- publish plain startTime/duration into state.cooldowns; the API is read only
-- while cooldowns are not secret (learning, snapshot, rescan).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Cooldowns = Nock:NewModule("Cooldowns", "AceEvent-3.0")
local C = Nock.Constants
local Engine = Nock.LedgerEngine

Cooldowns.refreshInterval = 0.1

local GCD_TOLERANCE = 1.6   -- a reading at or under this is the GCD, not the spell

local function profile()
  return (Nock.db and Nock.db.profile) or {}
end

local function ensureStateSlot(key)
  if not Nock.state.cooldowns[key] then
    Nock.state.cooldowns[key] = {
      startTime = 0, duration = 0, remaining = 0,
      ready = true, procActive = false, icon = nil, onUse = true,
    }
  end
end

-- Base spell for a cast rank: the ledger is keyed by the catalog's base id.
local function baseSpell(id)
  local CS = _G.C_Spell
  if CS and CS.GetBaseSpell then
    local okc, base = pcall(CS.GetBaseSpell, id)
    if okc and type(base) == "number" and base > 0 then return base end
  end
  local SB = _G.C_SpellBook
  if SB and SB.FindBaseSpellByID then
    local okc, base = pcall(SB.FindBaseSpellByID, id)
    if okc and type(base) == "number" and base > 0 then return base end
  end
  return id
end

-- Ids resolved from the spellbook by NAME for entries that carry none
-- (the racials: Forever gave reworked ones new ids). Filled by UpdateKnown.
local RESOLVED = {}
local EMPTY = {}

-- Every spell id behind an entry (a pair tile carries two); empty while a
-- name-only entry is unresolved.
local scratchIds = {}
local function entryIds(e)
  if e.ids then return e.ids end
  local id = RESOLVED[e.key] or e.id
  if not id then return EMPTY end
  scratchIds[1] = id
  return scratchIds
end

-- The id the ledger is asked for: any member of a linked group answers.
local function ledgerId(e)
  return (e.ids and e.ids[1]) or RESOLVED[e.key] or e.id
end

-- Learned durations outlive the session: per character, keyed by spell id.
local function remembered()
  local db = Nock.db and Nock.db.char
  if not db then return nil end
  db.foreverLearned = db.foreverLearned or {}
  return db.foreverLearned
end

-- Ids whose length came from the client (an API read, a watched cooldown's
-- end, or an earlier session's either) rather than the catalog's seed guess.
local REAL = {}

-- A learned duration applies to every id of the entry (a pair shares it) and
-- is remembered for the next session.
local function learnAll(ledger, e, duration)
  local ids = entryIds(e)
  local mem = remembered()
  for i = 1, #ids do
    Engine.Learn(ledger, ids[i], duration)
    REAL[ids[i]] = true
    if mem then mem[ids[i]] = duration end
  end
end

-- Cold start: the catalog's seed, then whatever an earlier session learned.
local function seedLearned(ledger, e)
  local ids = entryIds(e)
  local mem = remembered()
  for i = 1, #ids do
    if e.cd then Engine.Learn(ledger, ids[i], e.cd) end
    local kept = mem and mem[ids[i]]
    if type(kept) == "number" then Engine.Learn(ledger, ids[i], kept); REAL[ids[i]] = true end
  end
end

-- A cast arrives with its own rank's id. The client's base-spell lookup
-- links it to the catalog on Anniversary; on Forever ranks are separate
-- spells it does not link (Arcane Shot rank 2 stopped the Arc tile,
-- 2026-09-23), so the spell NAME is the fallback: every tracked id's name
-- is indexed at build, and a cast whose id is unknown resolves through it.
local function nameOf(id)
  local n = Nock.API and Nock.API.SpellName and Nock.API.SpellName(id)
  n = Nock.Flavor.Plain(n)
  return type(n) == "string" and n or nil
end

function Cooldowns:Resolve(spellID)
  local id = baseSpell(spellID)
  local e = self._byId[id]
  if e then return e, id end
  local hit = self._byName[nameOf(spellID) or false]
  if hit then return hit.e, hit.id end
  return nil
end

-- The "Add an entry" form's records (profile.cooldownCustom, shared with
-- TBC) as tracked entries, same key rule as Modules/Cooldowns.lua. Spells
-- only: a cast stamps them and the first out-of-combat cast teaches the
-- length. Items are left out -- Forever has no item cooldown read.
local function customEntries()
  local out = {}
  for _, rec in ipairs(profile().cooldownCustom or {}) do
    local id = tonumber(rec.id)
    if rec.type == "spell" and id and id > 0 then
      local key = (type(rec.key) == "string" and rec.key ~= "" and rec.key) or ("c_spell_" .. id)
      local label = (type(rec.label) == "string" and rec.label ~= "" and rec.label) or nameOf(id) or key
      out[#out + 1] = { key = key, type = "spell", id = id, label = label, custom = true }
    end
  end
  return out
end

function Cooldowns:RebuildLists()
  self._tracked, self._byKey, self._byId, self._byName, self._groupKeys = {}, {}, {}, {}, {}
  self.ledger = self.ledger or Engine.New()
  local groups = {}
  local sharedNames = {}   -- shared group name -> list of member keys (temp, folded into self._groupKeys below)
  local all = {}
  for _, e in ipairs(C.TRACKED_COOLDOWNS) do all[#all + 1] = e end
  for _, e in ipairs(customEntries()) do
    -- a catalog key wins over a custom record that reuses it
    local clash = false
    for _, c in ipairs(C.TRACKED_COOLDOWNS) do if c.key == e.key then clash = true; break end end
    if not clash then all[#all + 1] = e end
  end
  for _, e in ipairs(all) do
    if e.type == "spell" and #entryIds(e) > 0 and not self._byKey[e.key] then
      self._tracked[#self._tracked + 1] = e
      self._byKey[e.key] = e
      ensureStateSlot(e.key)
      local s = Nock.state.cooldowns[e.key]
      local ids = entryIds(e)
      -- First claim wins: the catalog is listed before the customs, so a
      -- custom entry on a catalog spell (Multi-Shot) never takes the cast
      -- lookup from it; both tiles read the same ledger slot anyway.
      for i = 1, #ids do
        if not self._byId[ids[i]] then self._byId[ids[i]] = e end
        local n = nameOf(ids[i])
        if n and not self._byName[n] then self._byName[n] = { e = e, id = ids[i] } end
      end
      -- The pair tile draws ids[1] on the left half and ids[2] on the right;
      -- its range tint asks every member (rangeIds, Forever/RangeFinder.lua).
      s.spellId = ids[#ids]
      s.rangeIds = e.ids
      s.melee = e.melee or nil   -- the out-of-range tint follows the melee probe (Forever/RangeFinder.lua)
      s.icon = e.texture or Nock.API.SpellIcon(ids[1])
      s.icon2 = (e.ids and not e.texture) and Nock.API.SpellIcon(ids[2]) or nil
      seedLearned(self.ledger, e)
      -- A shared-cooldown group (e.shared) links every member's ids into one
      -- ledger key: casting any of them stamps the whole group, and every
      -- member's own tile reads it back through ledgerId. Nothing takes over
      -- another tile; each member keeps its own entry, icon and state slot.
      local g = e.shared or e.key
      local grouped = e.shared or e.ids
      if grouped then
        groups[g] = groups[g] or {}
        for i = 1, #ids do table.insert(groups[g], ids[i]) end
      end
      if e.shared then
        sharedNames[e.shared] = sharedNames[e.shared] or {}
        table.insert(sharedNames[e.shared], e.key)
      end
    end
  end
  for _, ids in pairs(groups) do Engine.Link(self.ledger, ids) end
  -- One cached key list per tracked entry (the shared group's member list for
  -- a shared entry, else a dedicated one-key list): groupKeysOf reads this
  -- instead of allocating a fresh table on every watch feed/disarm/cast.
  for _, e in ipairs(self._tracked) do
    self._groupKeys[e.key] = (e.shared and sharedNames[e.shared]) or { e.key }
  end
end

-- Rebuilds C.TRACKED_COOLDOWNS from the client's own spellbook and talent
-- tree (Forever/CooldownDiscovery.lua), replacing its contents in place so
-- every holder of that table reference (the catalog index, the picker, an
-- open board) sees the new list. A no-op when the discovery module is not
-- loaded (TBC never ships it, and some test harnesses stub Cooldowns alone).
-- Returns true when the catalog actually changed, so a caller that is about
-- to do its own diff-and-broadcast (UpdateKnown) can fold that in. `quiet`
-- rebuilds without broadcasting: UpdateKnown recomputes _known from the
-- rebuilt list right after calling this, and a broadcast fired before that
-- would go out with the OLD known map still in place (IsEntryKnown wrong for
-- a key Discover just added). OnDiscoverRetry calls this with no `quiet`, so
-- a deferred discovery still broadcasts on its own.
function Cooldowns:Discover(api, quiet)
  local D = Nock.CooldownDiscovery
  if not D then return end
  -- Combat both hides the client's own cooldown/charge reads (secret) and
  -- forbids touching the profile-facing catalog table; try again once combat
  -- ends (OnEnable's PLAYER_REGEN_ENABLED handler). Checked before defaulting
  -- api to a live client read, so a deferred call never touches the client.
  if (InCombatLockdown and InCombatLockdown()) or Nock.Restricted("cooldowns") then
    self._discoverPending = true
    return
  end
  self._discoverPending = nil
  api = api or D.ClientApi()
  local list = D.Build(D.Rows(api), Nock.Spells.TRACKED)
  local sig = D.Signature(list)
  if sig == self._discoverSig then return end
  self._discoverSig = sig
  local tracked = C.TRACKED_COOLDOWNS
  for i = #tracked, 1, -1 do tracked[i] = nil end
  for i = 1, #list do
    local t = { type = "spell" }
    for k, v in pairs(list[i]) do t[k] = v end
    tracked[i] = t
  end
  if Nock.CooldownCatalog and Nock.CooldownCatalog.Invalidate then Nock.CooldownCatalog.Invalidate() end
  self:RebuildLists()
  if not quiet then self:SendMessage("NOCK_VISUALS_CHANGED") end
  return true
end

-- A Discover() call made in combat sets _discoverPending and defers; combat
-- ending is the one moment it is guaranteed safe to retry.
function Cooldowns:OnDiscoverRetry()
  if self._discoverPending then self:Discover() end
end

-- The grid view's OnInitialize and Options.lua's RegisterOptions run before
-- OnEnable, so the lists are built on first use as well as on initialize.
local function lists(self)
  if not self._tracked then self:RebuildLists() end
  return self._tracked
end

function Cooldowns:OnInitialize()
  self:RebuildLists()
end

function Cooldowns:GetTracked() return lists(self) end
function Cooldowns:GetEntry(key) lists(self); return self._byKey[key] end
function Cooldowns:OnConfigChanged() self:RebuildLists() end

-- The known-spell gate: a RACIAL entry (e.racial) is available only while
-- the character HAS one of its spells (a human hunter saw the night elf
-- racials, 2026-09-23); the class spells always show, learned or not, so
-- a level-1 grid keeps its shape. Known by id through C_SpellBook.IsSpellKnown, or
-- by NAME in the spellbook: ranks are separate spells here and the base
-- id may stop reading as known once a higher rank is trained. Without the
-- spellbook API a racial cannot be confirmed, so it stays hidden; class
-- spells keep showing (user, 2026-09-28: only your own racials). The spellbook's
-- name map is Nock.ForeverSpellbookNames (Forever/Spellbook.lua).

local function entryKnown(e, names)
  if e.name and names[e.name] then return true end
  local SB = _G.C_SpellBook
  local ids = entryIds(e)
  for i = 1, #ids do
    if SB and SB.IsSpellKnown then
      local okk, known = pcall(SB.IsSpellKnown, ids[i])
      if okk and known == true then return true end
    end
    local n = nameOf(ids[i])
    if n and names[n] then return true end
  end
  return false
end

function Cooldowns:UpdateKnown()
  -- A discovery crash (an unnamed row D.Rows/D.Build could not filter, say)
  -- must not break every future rescan: fall back to the current catalog and
  -- carry on rather than spam chat with an error.
  local okDiscover, discovered = pcall(self.Discover, self, nil, true)
  if not okDiscover then discovered = false end
  local names = Nock.ForeverSpellbookNames()
  local old = self._known
  if not names then self._known = nil; return end
  self._names = names
  -- Name-keyed entries (the racials, and any entry the catalog names) take
  -- their id from the spellbook once it lists them; the lists are rebuilt so
  -- the ledger indexes it. A resolved id can move again (Bestial Wrath's
  -- vanilla id vs. the Forever talent's own), so a later different id still
  -- counts as a change.
  local resolved = false
  for _, e in ipairs(C.TRACKED_COOLDOWNS) do
    if e.type == "spell" and e.name and not e.ids then
      local id = names[e.name]
      if type(id) == "number" and RESOLVED[e.key] ~= id and id ~= e.id then RESOLVED[e.key] = id; resolved = true end
    end
  end
  if resolved then self:RebuildLists() end
  local known = {}
  for _, e in ipairs(lists(self)) do
    -- A custom entry (a pet ability, a proc/item spell) is never in the
    -- player's own spellbook by design; leave it unset rather than false so
    -- consumers read it as "known" (grid tiles greyed unlearned on false).
    if not e.custom then
      known[e.key] = entryKnown(e, names)
    end
  end
  self._known = known
  -- One broadcast, fired after _known is fully rebuilt so a listener reading
  -- IsEntryKnown for whatever just changed sees the right answer: either
  -- Discover() changed the catalog (quiet -- it did not send its own), or the
  -- known map itself changed for an existing catalog.
  local changed = discovered
  if not changed and old then
    for k, v in pairs(known) do
      if old[k] ~= v then changed = true; break end
    end
  end
  if changed then self:SendMessage("NOCK_VISUALS_CHANGED") end
end

-- Hidden only for a racial the character does not have (another race's);
-- class and talent spells always keep their tile, greyed while unknown.
-- A racial counts as racial from the catalog itself, not only from the
-- tracked list: a name-only racial of another race is never resolved, so it
-- never becomes tracked, and must still be hidden from the tray and flyout.
-- It is shown only once the spellbook confirms the character has it; before
-- the spellbook is read, racials stay hidden (a night elf never sees orc ones).
local function isRacial(self, key)
  local e = self._byKey and self._byKey[key]
  if e then return e.racial == true end
  for _, c in ipairs(C.TRACKED_COOLDOWNS) do
    if c.key == key then return c.racial == true end
  end
  return false
end

function Cooldowns:IsEntryAvailable(key)
  if not isRacial(self, key) then return true end
  local known = self._known
  return (known and known[key] == true) or false
end

-- true / false, or nil when the spellbook cannot be read yet.
function Cooldowns:IsEntryKnown(key)
  local known = self._known
  if not known then return nil end
  return known[key]
end

-- View helpers, same contracts as the TBC module (profile + constants only).
function Cooldowns:GetOrderedGridKeys()
  local keys = {}
  for _, e in ipairs(lists(self)) do keys[#keys + 1] = e.key end
  return keys
end

function Cooldowns:GetIconSize()
  local p = profile()
  return p.iconSize or C.DIM.COOLDOWN_ICON
end

local function rowsOf(p)
  return p.cooldownRows or C.COOLDOWN_ROWS or 1
end

function Cooldowns:GetDims()
  local icon = self:GetIconSize()
  local rows = math.max(1, math.floor(rowsOf(profile())))
  return icon, rows
end

function Cooldowns:GetGridWidth()
  local icon = self:GetIconSize()
  local n = #lists(self)
  return n * icon + math.max(0, n - 1) * C.DIM.INNER_GAP
end

function Cooldowns:GetGridEntries() return lists(self) end

-- Racial buffs: the tile lights while the racial's own buff is up (Elune's
-- Light, Blood Fury, Berserking ...) and pivots to its countdown. Own auras
-- throw in combat here, so the buff is a ledger too: the cast stamps it with
-- the learned (or seeded) length, and out of combat the aura cache is the
-- truth both ways and teaches the length. An `untilBroken` buff (Shadowmeld)
-- has no expiry and does NOT drop combat on Forever: it is held from the cast
-- until the hunter moves, casts or swings, which is what breaks it.
local BUFF_GRACE = 0.5   -- a fresh stamp outlives an aura cache that has not caught up

local function buffMemory()
  local db = Nock.db and Nock.db.char
  if not db then return nil end
  db.foreverRacialBuff = db.foreverRacialBuff or {}
  return db.foreverRacialBuff
end

local function buffOf(self, e)
  self._buffs = self._buffs or {}
  local b = self._buffs[e.key]
  if not b then
    local mem = buffMemory()
    b = { exp = 0, held = false, stamp = -math.huge, dur = (mem and mem[e.key]) or e.buff }
    self._buffs[e.key] = b
  end
  return b
end

-- A held buff's cooldown starts when it BREAKS, not at the cast (Shadowmeld:
-- 10 s from the break, user 2026-09-24): the break stamps the ledger, and
-- while cooldowns are readable the next SPELL_UPDATE_COOLDOWN corrects it.
local function breakBuff(self, e, b, now)
  b.held, b.brokeAt = false, now
  local id = ledgerId(e)
  if not id then return end
  Engine.OnCast(self.ledger, id, now)
  if not Nock.Restricted("cooldowns") then self._learnPending, self._learnRead = id, id end
end

-- Any own action breaks a held buff (Shadowmeld). `except` is the entry
-- whose cast is being handled: casting Shadowmeld does not break Shadowmeld.
function Cooldowns:BreakHeld(except)
  if not self._buffs then return end
  local now = GetTime()
  for key, b in pairs(self._buffs) do
    if b.held and key ~= except then
      local e = self._byKey and self._byKey[key]
      if e then breakBuff(self, e, b, now) else b.held = false end
    end
  end
end

function Cooldowns:OnMoveOrSwing() self:BreakHeld(nil) end

function Cooldowns:UNIT_SPELLCAST_START(event, unit)
  if unit == "player" then self:BreakHeld(nil) end
end

local function stampBuff(self, e, now)
  if not e.racial then return end
  local b = buffOf(self, e)
  if e.untilBroken then
    b.held, b.stamp = true, now
  elseif b.dur then
    b.exp, b.stamp = now + b.dur, now
  end
end

-- Out of combat: the aura (by the entry's id, else its name) is the truth.
local function readBuffTruth(self, e, now)
  local AC = Nock.AuraCache
  if not AC or Nock.Restricted("auras") then return end
  local b = buffOf(self, e)
  local id = ledgerId(e)
  local a = (id and AC.BySpell("player", id)) or AC.ByName("player", e.name or (id and nameOf(id)) or false)
  if a then
    local P = Nock.Flavor.Plain
    local dur, exp = P(a.duration), P(a.expirationTime)
    b.icon = P(a.icon) or b.icon
    if type(dur) == "number" and dur > 0 and type(exp) == "number" and exp > 0 then
      if dur ~= b.dur then
        b.dur = dur
        local mem = buffMemory()
        if mem then mem[e.key] = dur end
      end
      b.exp, b.held = exp, false
    else
      -- Still up after a guessed break (a move or cast that did not break
      -- it): the break's cooldown stamp was wrong, take it back.
      if not b.held and b.brokeAt and e.untilBroken and id then
        Engine.Reconcile(self.ledger, id, 0, 0)
      end
      b.exp, b.held, b.brokeAt = 0, true, nil
    end
  elseif now - b.stamp > BUFF_GRACE then
    -- Gone out of combat without a seen break (cancelled): the break is now.
    if b.held and e.untilBroken then breakBuff(self, e, b, now) end
    b.exp, b.held = 0, false
  end
end

-- The one writer of procActive on Forever, same edge message as TBC's.
local function publishBuff(self, e, s, now)
  local b = buffOf(self, e)
  local timed = b.exp > now and b.dur and b.dur > 0
  local active = (b.held or timed) and true or false
  if (s.procActive == true) ~= active then
    s.procActive = active
    self:SendMessage("NOCK_PROC_ACTIVE", e.key, active)
  end
  s.buffPermanent = b.held and not timed or false
  if timed then
    s.buffIcon, s.buffDuration, s.buffStartTime = b.icon or s.icon, b.dur, b.exp - b.dur
  elseif b.held then
    s.buffIcon, s.buffDuration, s.buffStartTime = b.icon or s.icon, 0, 0
  else
    s.buffIcon, s.buffDuration, s.buffStartTime = nil, 0, 0
  end
end

-- Client-cooldown watch (Disengage report, 2026-09-27): each own cast of a
-- tracked spell feeds that spell's client cooldown (a duration object, secret
-- in combat) into an invisible Cooldown widget. Its OnCooldownDone is a PLAIN
-- edge at the client's true end: it ends the ledger's countdown (resets
-- included) and teaches the length of a spell never read out of combat
-- (combat-only spells: Disengage, Mongoose Bite). While a watch runs the tile
-- counts as on cooldown (s.clientRunning), so a spell the ledger cannot time
-- still greys, and the grid shows the client's own numbers
-- (UI/Frame_ReactCooldowns.lua).
local FEED_WINDOW = 1.0   -- updates this soon after the cast re-feed the widget (GCD -> the real cooldown)
local WATCH_MAX   = 900   -- a watch the client never ended is dropped after this

-- Pure: what a watched cooldown's end means. `dur` = end - cast, `real` = the
-- entry's length already came from the client. Returns the length to learn
-- (or nil) and whether the ledger's entry ends now. A GCD-long end is the GCD
-- only: nothing learned, a running ledger entry left alone.
function Cooldowns.DoneVerdict(dur, real)
  if type(dur) ~= "number" or dur <= GCD_TOLERANCE then return nil, false end
  local learn = (not real) and (math.floor(dur * 10 + 0.5) / 10) or nil
  return learn, true
end

-- The widgets live on an unparented, invisible host: they are timers, not
-- HUD elements, and a hidden UIParent (Alt-Z) must not stop their updates.
local watchHost
local function watchOf(self, e)
  self._watch = self._watch or {}
  local w = self._watch[e.key]
  if w then return w end
  if not watchHost then
    watchHost = CreateFrame("Frame")
    watchHost:SetSize(1, 1)
    watchHost:SetPoint("BOTTOMLEFT", 0, 0)
    watchHost:SetAlpha(0)
  end
  local cd = CreateFrame("Cooldown", nil, watchHost, "CooldownFrameTemplate")
  cd:SetAllPoints(watchHost)
  cd.noCooldownCount = true
  if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
  w = { cd = cd, key = e.key, e = e, armed = false }
  cd:SetScript("OnCooldownDone", function() self:OnWatchDone(w) end)
  self._watch[e.key] = w
  return w
end

-- clientFeed counts the feeds, so a view holding the client's duration
-- object knows when to read a fresh one. A shared-cooldown group (e.shared)
-- marks EVERY member's tile, not just the one whose cast armed the watch: a
-- combat-only fallback (a spell never read out of combat) still has to cover
-- the other members, which share the same cooldown but never armed a watch
-- of their own.
local function groupKeysOf(self, e)
  return (self._groupKeys and self._groupKeys[e.key]) or { e.key }
end

local function setClientRunning(self, e, on)
  for _, key in ipairs(groupKeysOf(self, e)) do
    local s = Nock.state.cooldowns[key]
    if s then
      s.clientRunning = on or nil
      if on then s.clientFeed = (s.clientFeed or 0) + 1 end
    end
  end
end

local function disarm(self, w)
  w.armed = false
  setClientRunning(self, w.e, false)
end

-- Hand the widget the spell's current client cooldown. A plainly-zero object
-- is nothing to watch (the spell is not cooling down yet); a secret one is
-- taken on trust.
local function feedWatch(self, w)
  local obj = Nock.API.SpellCooldownDuration(w.read)
  if not obj or not w.cd.SetCooldownFromDurationObject then return end
  local zero = obj.IsZero and Nock.Flavor.Plain(obj:IsZero())
  if zero == true then return end
  w.cd:SetCooldownFromDurationObject(obj)
  setClientRunning(self, w.e, true)
end

function Cooldowns:ArmWatch(e, id, read, now)
  local w = watchOf(self, e)
  w.id, w.read, w.castAt, w.armed = id, read, now, true
  feedWatch(self, w)
end

function Cooldowns:OnWatchDone(w)
  if not w.armed then return end
  local learn, clear = Cooldowns.DoneVerdict(GetTime() - w.castAt, REAL[w.id] == true)
  disarm(self, w)
  if learn then learnAll(self.ledger, w.e, learn) end
  if clear then Engine.Reconcile(self.ledger, w.id, 0, 0) end
end

function Cooldowns:OnEnable()
  if Nock.CooldownRows then Nock.CooldownRows.MigrateOnce() end
  lists(self)
  self:RegisterEvent("PLAYER_LOGIN", "Rescan")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "Rescan")
  self:RegisterEvent("SPELLS_CHANGED", "UpdateKnown")
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  -- what breaks a held buff (Shadowmeld): moving, starting a cast, a swing
  self:RegisterEvent("UNIT_SPELLCAST_START")
  self:RegisterEvent("PLAYER_STARTED_MOVING", "OnMoveOrSwing")
  self:RegisterEvent("PLAYER_SWING", "OnMoveOrSwing")
  -- usability (dim while unavailable, the no-mana tint, reactive spells);
  -- AceEvent hard-errors on an event the client lacks
  pcall(self.RegisterEvent, self, "SPELL_UPDATE_USABLE", "ScanUsable")
  -- catalog discovery: retried once combat ends if it was deferred, and
  -- re-run whenever the talent tree changes (a new spell can clear the bar)
  self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnDiscoverRetry")
  pcall(self.RegisterEvent, self, "TRAIT_CONFIG_UPDATED", "UpdateKnown")
  self:RegisterMessage("NOCK_SNAPSHOT", "Seed")
  self:RegisterMessage("NOCK_RESCAN", "Rescan")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "OnConfigChanged")
end

-- Usability for every spell tile, the TBC module's contract: s.usable /
-- s.noMana (booleans, nil = cannot say) and s.reactive (Mongoose Bite and
-- the like: greyed while unusable whatever reactTileDim says). A secret read
-- (in combat, if the client hides it) is nil: the tile keeps its ready look.
-- Event-driven (SPELL_UPDATE_USABLE, cooldown updates, rescans), never per tick.
function Cooldowns.UsableRead(usable, noMana)
  local u, m = Nock.Flavor.Plain(usable), Nock.Flavor.Plain(noMana)
  if type(u) ~= "boolean" then u = nil end
  if type(m) ~= "boolean" then m = nil end
  if u == nil then m = nil end
  return u, m
end

function Cooldowns:ScanUsable()
  local API = Nock.API
  if not (API and API.SpellUsable and API.IsReactiveSpell) then return end
  for _, e in ipairs(self._tracked or {}) do
    local s = Nock.state.cooldowns[e.key]
    local id = s and s.spellId
    if id then
      s.usable, s.noMana = Cooldowns.UsableRead(API.SpellUsable(id))
      if s._reactiveFor ~= id then
        s.reactive = API.IsReactiveSpell(id)
        s._reactiveFor = id
      end
    elseif s then
      s.usable, s.noMana, s.reactive, s._reactiveFor = nil, nil, nil, nil
    end
  end
end

Cooldowns.RECENT_MAX = 8

-- Pure: `id` to the front of `list`, a repeat moved, capped at `max`.
function Cooldowns.RecentPush(list, id, max)
  for i = #list, 1, -1 do if list[i] == id then table.remove(list, i) end end
  table.insert(list, 1, id)
  while #list > max do table.remove(list) end
  return list
end

-- A cast the grid does not track, from the spellbook, with a cooldown (a base
-- cooldown the client cannot report counts as "maybe": kept).
function Cooldowns:NoteRecent(spellID)
  local n = nameOf(spellID)
  if not (n and self._names and self._names[n]) then return end
  local base = Nock.API.SpellBaseCooldown and Nock.API.SpellBaseCooldown(spellID)
  if base == 0 then return end
  local list = Nock.state.cdRecent
  if list[1] == spellID then return end
  Cooldowns.RecentPush(list, spellID, Cooldowns.RECENT_MAX)
  self:SendMessage("NOCK_CD_RECENT")
end

-- Own casts stamp the ledger (plain on Forever). While cooldowns are readable
-- the next SPELL_UPDATE_COOLDOWN learns the real duration for that spell.
function Cooldowns:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID)
  if unit ~= "player" or type(spellID) ~= "number" then return end
  local e, id = self:Resolve(spellID)
  self:BreakHeld(e and e.key)
  if not e then self:NoteRecent(spellID); return end
  stampBuff(self, e, GetTime())
  -- a held buff's cooldown starts at its break (breakBuff), not here
  if e.untilBroken then return end
  Engine.OnCast(self.ledger, id, GetTime())
  -- A sting with no cooldown of its own (Serpent, Scorpid: `debuff`, never
  -- discovered as a cooldown) has nothing to watch: the watch would only
  -- count the GCD down on its tile until the sting's timer covers it.
  if not (e.debuff and not e.discovered) then self:ArmWatch(e, id, spellID, GetTime()) end
  -- the learn read uses the cast's own rank (that is the spell on cooldown);
  -- the ledger is keyed by the catalog id
  if not Nock.Restricted("cooldowns") then self._learnPending, self._learnRead = id, spellID end
end

function Cooldowns:SPELL_UPDATE_COOLDOWN()
  self:ScanUsable()
  if self._watch then
    local now = GetTime()
    for _, w in pairs(self._watch) do
      if w.armed and now - w.castAt <= FEED_WINDOW then feedWatch(self, w) end
    end
  end
  local id, read = self._learnPending, self._learnRead
  if not id or Nock.Restricted("cooldowns") then return end
  self._learnPending, self._learnRead = nil, nil
  local start, duration = Nock.API.SpellCooldown(read or id)
  start = Nock.Flavor.Plain(start); duration = Nock.Flavor.Plain(duration)
  if type(duration) == "number" and duration > GCD_TOLERANCE then
    learnAll(self.ledger, self._byId[id], duration)
    Engine.Reconcile(self.ledger, id, start, duration)
  end
end

-- Combat start: every tracked cooldown still readable seeds the ledger.
function Cooldowns:Seed()
  if Nock.Restricted("cooldowns") then return end
  for _, e in ipairs(self._tracked) do
    local id = ledgerId(e)
    local start, duration = Nock.API.SpellCooldown(id)
    start = Nock.Flavor.Plain(start); duration = Nock.Flavor.Plain(duration)
    if type(duration) == "number" and duration > GCD_TOLERANCE then
      learnAll(self.ledger, e, duration)
      Engine.Seed(self.ledger, id, start, duration)
    end
  end
end

-- Out of combat: the API is the truth; the ledger is reconciled to it. Two
-- passes: read every entry's own client cooldown first, then reconcile each
-- shared-cooldown GROUP once from whichever member actually read a running
-- cooldown. A member the character does not have (an untalented Summon Hawk,
-- an untrained Multi-Shot) is skipped outright -- the client has no cooldown
-- data for a spell it doesn't know, so its reading would be a meaningless
-- zero -- and even a genuine off-cooldown zero from a KNOWN member is never
-- allowed to wipe a sibling's real, running cooldown just because it happened
-- to be iterated after it (Summon Hawk after Arcane Shot, say): a fix, since
-- reconciling per entry in one pass let exactly that happen.
function Cooldowns:Rescan()
  self:UpdateKnown()
  self:ScanUsable()
  if Nock.Restricted("cooldowns") then return end
  local reads = {}
  local groupRunning = {}
  for _, e in ipairs(self._tracked) do
    if self:IsEntryKnown(e.key) ~= false then
      local id = ledgerId(e)
      local start, duration = Nock.API.SpellCooldown(id)
      start = Nock.Flavor.Plain(start); duration = Nock.Flavor.Plain(duration)
      local running = type(duration) == "number" and duration > GCD_TOLERANCE
        and type(start) == "number" and start > 0
      reads[e] = { id = id, start = start, duration = duration }
      if running then
        learnAll(self.ledger, e, duration)
        local g = e.shared or e.key
        local cur = groupRunning[g]
        if not cur or (start + duration) > (cur.start + cur.duration) then
          groupRunning[g] = { start = start, duration = duration }
        end
      end
    end
  end
  for _, e in ipairs(self._tracked) do
    local r = reads[e]
    if r then
      local running = groupRunning[e.shared or e.key]
      if running then
        Engine.Reconcile(self.ledger, r.id, running.start, running.duration)
      else
        Engine.Reconcile(self.ledger, r.id, 0, 0)
        -- readable and not cooling down: a watch still running missed its end
        local w = self._watch and self._watch[e.key]
        if w and w.armed then disarm(self, w) end
      end
    end
  end
end

-- Slow-lane refresh: ledger -> state (plain numbers; the tick derives
-- remaining/ready exactly as on TBC).
function Cooldowns:Refresh()
  local now = GetTime()
  for _, e in ipairs(self._tracked) do
    local s = Nock.state.cooldowns[e.key]
    -- buff first: a break seen here stamps the cooldown read below
    if e.racial then
      readBuffTruth(self, e, now)
      publishBuff(self, e, s, now)
    end
    local start, duration = Engine.Cooldown(self.ledger, ledgerId(e), now)
    s.startTime, s.duration = start, duration
    local w = self._watch and self._watch[e.key]
    if w and w.armed and now - w.castAt > WATCH_MAX then disarm(self, w) end
  end
end
