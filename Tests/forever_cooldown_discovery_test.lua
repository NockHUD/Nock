-- Tests/forever_cooldown_discovery_test.lua
-- Forever/Cooldowns.lua: Discover() wires Forever/CooldownDiscovery.lua into
-- C.TRACKED_COOLDOWNS; shared-cooldown groups (Arc/Hawk, AimMulti/Multi/Aimed)
-- each keep their own entry and tile, all stamped through one ledger group;
-- combat defers to PLAYER_REGEN_ENABLED, and a signature match sends nothing.
-- Run from the repo root: luajit Tests/forever_cooldown_discovery_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local now = 100
_G.GetTime = function() return now end
_G.GetRangedHaste = function() return 0 end
_G.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
local secretCds = false
_G.C_Secrets = { ShouldCooldownsBeSecret = function() return secretCds end, ShouldAurasBeSecret = function() return false end }

local inCombat = false
_G.InCombatLockdown = function() return inCombat end

-- Frames for the client-cooldown watch: unused here but Forever/Cooldowns.lua
-- creates one on OnEnable's first cast, so CreateFrame must exist.
_G.CreateFrame = function(kind)
  local f = { kind = kind, scripts = {} }
  function f:SetSize() end
  function f:SetPoint() end
  function f:SetAllPoints() end
  function f:SetAlpha() end
  function f:SetHideCountdownNumbers() end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:SetCooldownFromDurationObject(obj) self.fed = obj end
  return f
end

local apiCd = {}
local sentMsgs = {}
local Nock = {
  Flavor = { forever = true, Plain = function(v) if v == "SECRET" then return nil end return v end },
  API = {
    SpellCooldown = function(id) if secretCds then return "SECRET", "SECRET", true end; local c = apiCd[id]; if c then return c[1], c[2], true end; return 0, 0, true end,
    SpellCooldownDuration = function() return { IsZero = function() return true end } end,
    SpellIcon = function(id) return 100000 + id end,
    SpellName = function(id) return ({ [3044] = "Arcane Shot", [1293241] = "Summon Hawk" })[id] or ("spell" .. id) end,
  },
  Constants = { GCD_BASE = 1.5, TRACKED_COOLDOWNS = { { key = "TBC", type = "spell", id = 1, label = "x" } }, REACT_CD_ROWS = { { h = 32, keys = { "TBC" } } }, DIM = { COOLDOWN_ICON = 32, INNER_GAP = 2 }, COOLDOWN_ROWS = 1 },
  db = { profile = {} },
}
local modules = {}
-- Snapshot of self._known at the moment each broadcast fires, keyed by that
-- broadcast's position in sentMsgs -- proves a listener reacting to the
-- message sees the catalog's OWN known state, not a stale one from before
-- Discover()'s rebuild.
local knownAtBroadcast = {}
function Nock:NewModule(name) local m = { name = name, events = {}, msgs = {} }
  function m:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function m:RegisterMessage(msg, h) self.msgs[msg] = h or msg end
  function m:SendMessage(msg)
    sentMsgs[#sentMsgs + 1] = msg
    local snap = {}
    if self._known then for k, v in pairs(self._known) do snap[k] = v end end
    knownAtBroadcast[#sentMsgs] = snap
  end
  modules[name] = m; return m end
function Nock:GetModule(name) return modules[name] end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/LedgerEngine.lua")
dofile("Forever/Snapshot.lua")   -- defines Nock.Restricted
dofile("Forever/Spells.lua")
dofile("Forever/CooldownCatalog.lua")
dofile("Core/CooldownEditor.lua")
dofile("Forever/Spellbook.lua")
dofile("Forever/Cooldowns.lua")
dofile("Forever/CooldownDiscovery.lua")

-- A small, self-contained static catalog: a discovered spell (Immolation
-- Trap, id 13795) has no static match and lands as a new "s..." key. Arc and
-- Hawk carry the arcaneHawk shared group; AimMulti, Multi and Aimed carry the
-- aimedMulti shared group -- each member is its own entry and its own tile,
-- isolated from the real catalog's noise. A `cd` seed on each avoids relying
-- on CooldownDiscovery matching for this file's own grouping/stamping checks
-- (that matching is covered by Tests/cooldown_discovery_test.lua).
Nock.Spells.TRACKED = {
  { key = "Arc",      id = 3044,    name = "Arcane Shot", label = "Arc",  cat = "Class",  row = 1, shared = "arcaneHawk", cd = 6 },
  { key = "Hawk",     id = 1293241, name = "Summon Hawk", label = "Hawk", talent = true, cat = "Talent", row = 1, shared = "arcaneHawk", cd = 6 },
  { key = "AimMulti", ids = { 2643, 19434 }, names = { "Multi-Shot", "Aimed Shot" }, label = "Multi + Aimed", cat = "Class", row = 1, shared = "aimedMulti", cd = 6 },
  { key = "Multi",    id = 2643,    name = "Multi-Shot", label = "Multi", cat = "Class", row = 1, shared = "aimedMulti", cd = 6 },
  { key = "Aimed",    id = 19434,   name = "Aimed Shot",  label = "Aimed", cat = "Class", row = 1, shared = "aimedMulti", cd = 6 },
}
local C = Nock.Constants
local function rebuildTrackedFromSpells()
  local tracked = {}
  for i, e in ipairs(Nock.Spells.TRACKED) do
    local t = { type = "spell" }
    for k, v in pairs(e) do t[k] = v end
    tracked[i] = t
  end
  C.TRACKED_COOLDOWNS = tracked
end
rebuildTrackedFromSpells()
Nock.CooldownCatalog.Invalidate()

-- IsValidKey: a discovered key's shape is valid before any discovery ran.
ok(Nock.CooldownRows.IsValidKey("s13795") == true, "a discovered-shaped key is valid before any discovery")
ok(not Nock.CooldownRows.IsValidKey("Arc13795"), "a key that merely contains digits does not match the discovered shape")

local CD = modules["Cooldowns"]
CD:OnEnable()
local st = Nock.state

-- The injected client: a book row (Immolation Trap, a real cooldown) and a
-- talent row (Summon Hawk, always present -- Hawk's known/unknown state is
-- the spellbook-name gate below, not this row's presence).
-- Rows layered in over the course of the test (each Discover() recomputes
-- the whole list from scratch, so a spell has to stay listed here for its
-- discovered entry to survive a later rescan).
local extraRows = {}
local baseCdMs = { [13795] = 15000, [3044] = 6000 }
local api = {
  book = function()
    local rows = {
      { id = 13795, name = "Immolation Trap", src = "book:Hunter" },
      { id = 3044, name = "Arcane Shot", src = "book:Hunter" },
    }
    for _, r in ipairs(extraRows) do rows[#rows + 1] = r end
    return rows
  end,
  talents = function()
    return { { id = 1293241, name = "Summon Hawk", src = "talent", rank = 1, max = 1 } }
  end,
  passive = function() return false end,
  baseCd = function(id) return baseCdMs[id] end,
}
-- OnDiscoverRetry (and UpdateKnown) call Discover() with no argument, which
-- defaults to Nock.CooldownDiscovery.ClientApi(): stand in for the client
-- with the same injected api so a deferred retry sees the same picture.
Nock.CooldownDiscovery.ClientApi = function() return api end

-- 1. Out of combat, Discover(api) adds a new discovered entry.
CD:Discover(api)
local found = false
for _, e in ipairs(C.TRACKED_COOLDOWNS) do if e.key == "s13795" then found = true end end
ok(found, "Discover adds a new spell (Immolation Trap) to C.TRACKED_COOLDOWNS")
ok(CD:GetEntry("s13795") ~= nil, "the new entry is reachable through GetEntry")
ok(#sentMsgs == 1, "the first real discovery broadcasts NOCK_VISUALS_CHANGED")

-- 2. Arc and Hawk are separate catalog entries: nothing takes over either
-- tile. Hawk is greyed (known == false) while untalented, exactly like any
-- other talent entry -- gated on the spellbook NAME, same as BW/Intim/etc.
ok(CD:GetEntry("Arc") ~= nil and CD:GetEntry("Hawk") ~= nil and CD:GetEntry("Arc") ~= CD:GetEntry("Hawk"),
   "Arc and Hawk are separate entries")
local book = { ["Arcane Shot"] = 3044, ["Multi-Shot"] = 2643, ["Aimed Shot"] = 19434 }
Nock.ForeverSpellbookNames = function() return book end
CD:UpdateKnown()
ok(CD:IsEntryKnown("Arc") == true, "Arc is known (trained)")
ok(CD:IsEntryKnown("Hawk") == false, "Hawk is not known while untalented")

-- 3. A Summon Hawk cast, IN COMBAT (cooldowns secret), stamps BOTH Arc's and
-- Hawk's tiles: one ledger key behind the arcaneHawk shared group, reached
-- through each entry's own id/ledgerId, same start time either way.
secretCds = true
now = 700
CD:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1293241)
CD:Refresh()
ok(st.cooldowns.Arc.duration > 0 and st.cooldowns.Hawk.duration > 0, "a Summon Hawk cast times both the Arc and Hawk tiles")
ok(st.cooldowns.Arc.startTime == 700 and st.cooldowns.Hawk.startTime == 700, "one shared cooldown, the same start time")
secretCds = false

-- 3b. Likewise for the aimedMulti group: an Aimed Shot cast (in combat)
-- stamps AimMulti, Multi and Aimed all at once.
secretCds = true
now = 710
CD:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 19434)
CD:Refresh()
ok(st.cooldowns.AimMulti.duration > 0 and st.cooldowns.Multi.duration > 0 and st.cooldowns.Aimed.duration > 0,
   "an Aimed Shot cast times AimMulti, Multi and Aimed")
ok(st.cooldowns.AimMulti.startTime == 710 and st.cooldowns.Multi.startTime == 710 and st.cooldowns.Aimed.startTime == 710,
   "all three share one start time")
secretCds = false

-- 3c. Training Summon Hawk (the spellbook names it) flips Hawk to known but
-- never touches Arc's own tile -- no icon swap, no id takeover, unlike the
-- old override link.
book["Summon Hawk"] = 1293241
CD:UpdateKnown()
ok(CD:IsEntryKnown("Hawk") == true, "Hawk flips to known once trained")
ok(st.cooldowns.Arc.icon == 100000 + 3044, "Arc's icon stays its own even with Hawk talented")
ok(st.cooldowns.Hawk.icon == 100000 + 1293241, "Hawk keeps its own icon too")
ok(CD:Resolve(1293241) == CD:GetEntry("Hawk"), "a Summon Hawk cast resolves to the Hawk entry, not Arc")

-- 4. In combat: Discover changes nothing and defers; PLAYER_REGEN_ENABLED runs it.
table.insert(extraRows, { id = 90001, name = "Test New Spell", src = "book:Hunter" })
baseCdMs[90001] = 20000
inCombat = true
local lenBefore, sentBefore = #C.TRACKED_COOLDOWNS, #sentMsgs
CD:Discover(api)
ok(#C.TRACKED_COOLDOWNS == lenBefore, "in combat: the catalog is untouched")
ok(CD._discoverPending == true, "in combat: a retry is armed")
ok(CD:GetEntry("s90001") == nil, "in combat: the new spell is not yet tracked")
ok(#sentMsgs == sentBefore, "in combat: nothing is broadcast")
inCombat = false
CD:OnDiscoverRetry()
ok(CD:GetEntry("s90001") ~= nil, "PLAYER_REGEN_ENABLED's retry applies the deferred discovery")
ok(CD._discoverPending == nil, "the retry clears the pending flag")
ok(#sentMsgs == sentBefore + 1, "the retry broadcasts exactly once")

-- 5. A second Discover with the same api is a no-op (same signature).
local sentBefore2 = #sentMsgs
CD:Discover(api)
ok(#sentMsgs == sentBefore2, "an unchanged rescan sends no NOCK_VISUALS_CHANGED")

-- 6. UpdateKnown's own (quiet) Discover() call folds a new/changed catalog
-- into the SAME broadcast as the known-diff check right after it, rather
-- than sending one for each; and by the time that one broadcast fires,
-- IsEntryKnown for the spell Discover just added already answers correctly
-- (the known map is rebuilt before the message goes out, not after).
Nock.ForeverSpellbookNames = function() return { ["Another New Spell"] = 90002 } end
table.insert(extraRows, { id = 90002, name = "Another New Spell", src = "book:Hunter" })
baseCdMs[90002] = 25000
local sentBefore3 = #sentMsgs
CD:UpdateKnown()
ok(CD:GetEntry("s90002") ~= nil, "UpdateKnown's own Discover() call still picks up a further new spell")
ok(#sentMsgs == sentBefore3 + 1, "UpdateKnown does not double-broadcast a discovery it just made")
ok(knownAtBroadcast[sentBefore3 + 1].s90002 == true,
   "IsEntryKnown for the newly discovered spell is already correct when the broadcast fires")

print(("forever_cooldown_discovery: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
