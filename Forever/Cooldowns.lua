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

-- Every spell id behind an entry (a pair tile carries two).
local scratchIds = {}
local function entryIds(e)
  if e.ids then return e.ids end
  scratchIds[1] = e.id
  return scratchIds
end

-- The id the ledger is asked for: any member of a linked group answers.
local function ledgerId(e)
  return e.id or e.ids[1]
end

-- Learned durations outlive the session: per character, keyed by spell id.
local function remembered()
  local db = Nock.db and Nock.db.char
  if not db then return nil end
  db.foreverLearned = db.foreverLearned or {}
  return db.foreverLearned
end

-- A learned duration applies to every id of the entry (a pair shares it) and
-- is remembered for the next session.
local function learnAll(ledger, e, duration)
  local ids = entryIds(e)
  local mem = remembered()
  for i = 1, #ids do
    Engine.Learn(ledger, ids[i], duration)
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
    if type(kept) == "number" then Engine.Learn(ledger, ids[i], kept) end
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

function Cooldowns:RebuildLists()
  self._tracked, self._byKey, self._byId, self._byName = {}, {}, {}, {}
  self.ledger = self.ledger or Engine.New()
  local groups = {}
  for _, e in ipairs(C.TRACKED_COOLDOWNS) do
    if e.type == "spell" and (e.id or e.ids) then
      self._tracked[#self._tracked + 1] = e
      self._byKey[e.key] = e
      ensureStateSlot(e.key)
      local s = Nock.state.cooldowns[e.key]
      local ids = entryIds(e)
      for i = 1, #ids do
        self._byId[ids[i]] = e
        local n = nameOf(ids[i])
        if n then self._byName[n] = { e = e, id = ids[i] } end
      end
      -- Range tint follows the last id (the ranged one of a pair); the pair
      -- tile draws ids[1] on the left half and ids[2] on the right.
      s.spellId = ids[#ids]
      s.icon = Nock.API.SpellIcon(ids[1])
      s.icon2 = e.ids and Nock.API.SpellIcon(ids[2]) or nil
      seedLearned(self.ledger, e)
      if e.shared or e.ids then
        local g = e.shared or e.key
        groups[g] = groups[g] or {}
        for i = 1, #ids do table.insert(groups[g], ids[i]) end
      end
    end
  end
  for _, ids in pairs(groups) do Engine.Link(self.ledger, ids) end
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
function Cooldowns:IsEntryAvailable() return true end
function Cooldowns:OnConfigChanged() self:RebuildLists() end

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

function Cooldowns:OnEnable()
  lists(self)
  self:RegisterEvent("PLAYER_LOGIN", "Rescan")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "Rescan")
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  self:RegisterMessage("NOCK_SNAPSHOT", "Seed")
  self:RegisterMessage("NOCK_RESCAN", "Rescan")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "OnConfigChanged")
end

-- Own casts stamp the ledger (plain on Forever). While cooldowns are readable
-- the next SPELL_UPDATE_COOLDOWN learns the real duration for that spell.
function Cooldowns:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID)
  if unit ~= "player" or type(spellID) ~= "number" then return end
  local e, id = self:Resolve(spellID)
  if not e then return end
  Engine.OnCast(self.ledger, id, GetTime())
  -- the learn read uses the cast's own rank (that is the spell on cooldown);
  -- the ledger is keyed by the catalog id
  if not Nock.Restricted("cooldowns") then self._learnPending, self._learnRead = id, spellID end
end

function Cooldowns:SPELL_UPDATE_COOLDOWN()
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

-- Out of combat: the API is the truth; the ledger is reconciled to it.
function Cooldowns:Rescan()
  if Nock.Restricted("cooldowns") then return end
  for _, e in ipairs(self._tracked) do
    local id = ledgerId(e)
    local start, duration = Nock.API.SpellCooldown(id)
    start = Nock.Flavor.Plain(start); duration = Nock.Flavor.Plain(duration)
    if type(duration) == "number" and duration > GCD_TOLERANCE and type(start) == "number" and start > 0 then
      learnAll(self.ledger, e, duration)
      Engine.Reconcile(self.ledger, id, start, duration)
    else
      Engine.Reconcile(self.ledger, id, 0, 0)
    end
  end
end

-- Slow-lane refresh: ledger -> state (plain numbers; the tick derives
-- remaining/ready exactly as on TBC).
function Cooldowns:Refresh()
  local now = GetTime()
  for _, e in ipairs(self._tracked) do
    local s = Nock.state.cooldowns[e.key]
    local start, duration = Engine.Cooldown(self.ledger, ledgerId(e), now)
    s.startTime, s.duration = start, duration
  end
end
