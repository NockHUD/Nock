-- Tests/forever_cooldowns_test.lua
-- Forever/Cooldowns.lua: catalog -> state.cooldowns, own casts stamp the
-- ledger, durations are learned out of combat only, snapshot seeds, rescan
-- reconciles, and nothing reads the API while cooldowns are secret.
-- Run from the repo root: luajit Tests/forever_cooldowns_test.lua

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

local apiCd = {}   -- [id] = { start, duration }
local apiReads = 0
local Nock = {
  Flavor = { forever = true, Plain = function(v) if v == "SECRET" then return nil end return v end },
  API = {
    SpellCooldown = function(id) apiReads = apiReads + 1; if secretCds then return "SECRET", "SECRET", true end; local c = apiCd[id]; if c then return c[1], c[2], true end; return 0, 0, true end,
    SpellIcon = function(id) return 100000 + id end,
    -- ranks are separate spells on Forever: the name is what they share
    SpellName = function(id) return ({ [3044] = "Arcane Shot", [14281] = "Arcane Shot", [2973] = "Raptor Strike", [14260] = "Raptor Strike" })[id] or ("spell" .. id) end,
  },
  Constants = { GCD_BASE = 1.5, TRACKED_COOLDOWNS = { { key = "TBC", type = "spell", id = 1, label = "x" } }, REACT_CD_ROWS = { { h = 32, keys = { "TBC" } } }, DIM = { COOLDOWN_ICON = 32, INNER_GAP = 2 }, COOLDOWN_ROWS = 1 },
  db = { profile = {} },
}
local modules = {}
function Nock:NewModule(name) local m = { name = name, events = {}, msgs = {} }
  function m:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function m:RegisterMessage(msg, h) self.msgs[msg] = h or msg end
  function m:SendMessage() end
  modules[name] = m; return m end
function Nock:GetModule(name) return modules[name] end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/LedgerEngine.lua")
dofile("Forever/Snapshot.lua")   -- defines Nock.Restricted
dofile("Forever/Spells.lua")
dofile("Forever/Cooldowns.lua")

local C = Nock.Constants
ok(C.TRACKED_COOLDOWNS[1].key ~= "TBC", "Forever overrides TRACKED_COOLDOWNS")
ok(C.REACT_CD_ROWS[1].keys[1] ~= "TBC", "Forever overrides REACT_CD_ROWS")
local CD = modules["Cooldowns"]
ok(CD and CD.refreshInterval == 0.1, "module Cooldowns on the slow lane")
CD:OnEnable()
local st = Nock.state
local raptor = CD:GetEntry("Raptor")
ok(raptor and raptor.id == 2973 and st.cooldowns.Raptor, "Raptor entry and state slot exist")
ok(st.cooldowns.Raptor.icon == 100000 + 2973, "icon resolved through Nock.API")
local pair = CD:GetEntry("AimMulti")
ok(pair and pair.ids and pair.ids[1] == 2643 and pair.ids[2] == 19434, "Multi+Aimed is one pair entry")
ok(st.cooldowns.AimMulti.spellId == 19434, "pair tile's range tint follows Aimed")
ok(st.cooldowns.AimMulti.icon == 100000 + 2643 and st.cooldowns.AimMulti.icon2 == 100000 + 19434, "pair tile carries both icons")
ok(CD:GetEntry("Elune") and CD:GetEntry("Elune").id == 1259799 and CD:GetEntry("Meld").id == 20580, "racials tracked")

local function fire(ev, ...) local h = CD.events[ev]; CD[type(h) == "string" and h or ev](CD, ev, ...) end
local function msg(m, ...) local h = CD.msgs[m]; CD[type(h) == "string" and h or m](CD, m, ...) end

-- Cold start: the catalog seed is known before any reading, so the first
-- fight has a countdown (Raptor 6 s); a remembered per-character value wins.
ok(Nock.LedgerEngine.Known(CD.ledger, 2973) and CD.ledger.learned[2973] == 6, "catalog seed learned at build")
ok(CD.ledger.learned[1259799] == nil, "no seed -> nothing known for Elune yet")
Nock.db.char = { foreverLearned = { [5116] = 11 } }
CD:RebuildLists()
ok(CD.ledger.learned[5116] == 11, "remembered duration overrides the seed")

-- Out of combat: a cast learns the duration from the API on SPELL_UPDATE_COOLDOWN.
apiCd[2973] = { 100, 6 }
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2973)
fire("SPELL_UPDATE_COOLDOWN")
CD:Refresh()
ok(st.cooldowns.Raptor.startTime == 100 and st.cooldowns.Raptor.duration == 6, "learned + published from the ooc reading")
ok(Nock.db.char.foreverLearned[2973] == 6, "the learned duration is remembered per character")
ok(st.cooldowns.Raptor.spellId == 2973, "spellId published for the range tint")

-- In combat: secret API, cast stamps the ledger with the learned 6s; no API read happens.
secretCds = true
now = 200
local reads0 = apiReads
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2973)
fire("SPELL_UPDATE_COOLDOWN")
CD:Refresh()
ok(apiReads == reads0, "no API read while cooldowns are secret")
ok(st.cooldowns.Raptor.startTime == 200 and st.cooldowns.Raptor.duration == 6, "in-combat cast published from the ledger")

-- A GCD-length reading is never learned.
secretCds = false
apiCd[1978] = { 300, 1.5 }
now = 300
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1978)
fire("SPELL_UPDATE_COOLDOWN")
ok(not Nock.LedgerEngine.Known(CD.ledger, 1978), "GCD-length readings are not learned")

-- Snapshot seeds running cooldowns while plain (the pair reads its first id).
apiCd[2643] = { 350, 6 }; now = 352
msg("NOCK_SNAPSHOT", "activating")
CD:Refresh()
ok(st.cooldowns.AimMulti.startTime == 350 and st.cooldowns.AimMulti.duration == 6, "snapshot seeded the pair")

-- A cast of the OTHER member (Aimed) in combat stamps the same tile.
secretCds = true; now = 360
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 19434)
CD:Refresh()
ok(st.cooldowns.AimMulti.startTime == 360 and st.cooldowns.AimMulti.duration == 6, "Aimed cast restarts the shared tile from the learned duration")
secretCds = false

-- Rescan reconciles: API says the pair is off cooldown now.
apiCd[2643] = nil; apiCd[19434] = nil; now = 400
msg("NOCK_RESCAN")
CD:Refresh()
ok(st.cooldowns.AimMulti.startTime == 0, "rescan cleared the pair from the API truth")

-- Non-player casts are ignored.
fire("UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 2973)

-- A higher rank (a separate spell id the client does not link to its base,
-- 2026-09-23: Arcane Shot rank 2 stopped the Arc tile) resolves by name.
now = 300
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 14281)
CD:Refresh()
ok(st.cooldowns.Arc.startTime == 300 and st.cooldowns.Arc.duration == 6, "rank 2 Arcane Shot stamps the Arc entry by name")
-- the learn read uses the cast's own rank, the ledger key stays the base
apiCd[14281] = { 300, 7 }
fire("SPELL_UPDATE_COOLDOWN")
CD:Refresh()
ok(st.cooldowns.Arc.duration == 7 and CD.ledger.learned[3044] == 7, "the rank's cooldown reading teaches the base entry")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 99999)
ok(st.cooldowns.Arc.startTime == 300, "an unknown spell with an unknown name stamps nothing")
CD:Refresh()
ok(st.cooldowns.Raptor.startTime ~= 400, "target casts ignored")

-- View helpers exist with the TBC signatures.
for _, fn in ipairs({ "GetTracked", "GetEntry", "GetOrderedGridKeys", "GetDims", "GetIconSize", "GetGridWidth", "GetGridEntries", "RebuildLists", "IsEntryAvailable", "OnConfigChanged" }) do
  ok(type(CD[fn]) == "function", "view helper " .. fn)
end
ok(CD:IsEntryAvailable("Raptor") == true, "every catalog entry is available")

print(("forever_cooldowns: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
