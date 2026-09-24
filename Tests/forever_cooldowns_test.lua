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
dofile("Forever/Spellbook.lua")
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
ok(CD:GetEntry("Elune") and CD:GetEntry("Elune").id == 1259799 and CD:GetEntry("Meld").id == 20580, "racials with a known id tracked")
ok(CD:GetEntry("Fury") == nil, "a name-only racial is not tracked until the spellbook names it")

local function fire(ev, ...) local h = CD.events[ev]; CD[type(h) == "string" and h or ev](CD, ev, ...) end
local function msg(m, ...) local h = CD.msgs[m]; CD[type(h) == "string" and h or m](CD, m, ...) end

-- Cold start: the catalog seed is known before any reading, so the first
-- fight has a countdown (Raptor 6 s); a remembered per-character value wins.
ok(Nock.LedgerEngine.Known(CD.ledger, 2973) and CD.ledger.learned[2973] == 6, "catalog seed learned at build")
ok(CD.ledger.learned[1259799] == 180, "Elune's Light seeded at 3 min")
ok(CD.ledger.learned[1259718] == 180 and CD:GetEntry("Meld").untilBroken == true and CD:GetEntry("Elune").buff == 15, "buff fields reach the constants")
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


-- Known-spell gate: a tile whose spell the character does not have is out
-- of the grid (a human hunter saw the night elf racials, 2026-09-23).
-- Known by id, or by NAME in the spellbook (ranks are separate spells).
do
  local book = {}   -- name -> true
  local knownIds = {}
  _G.Enum.SpellBookSpellBank = { Player = 0 }
  local items = {}
  _G.C_SpellBook = {
    IsSpellKnown = function(id) return knownIds[id] == true end,
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { name = "Hunter", itemIndexOffset = 0, numSpellBookItems = #items } end,
    GetSpellBookItemInfo = function(slot) return items[slot] end,
  }
  local sent = {}
  CD.SendMessage = function(_, msg) sent[#sent + 1] = msg end
  -- a human: Arcane Shot rank 2 only (its own id), Raptor, no Meld, no Elune
  items = { { spellID = 14281, name = "Arcane Shot" }, { spellID = 2973, name = "Raptor Strike" } }
  knownIds = { [14281] = true, [2973] = true }
  CD:UpdateKnown()
  ok(CD:IsEntryAvailable("Meld") == false and CD:IsEntryAvailable("Elune") == false, "human: the night elf racials are out")
  ok(CD:IsEntryAvailable("Raptor") == true, "known by id: in")
  ok(CD:IsEntryAvailable("Arc") == true, "rank 2 only: the base entry is in by name")
  ok(CD:IsEntryAvailable("Conc") == true and CD:IsEntryAvailable("RF") == true and CD:IsEntryAvailable("AimMulti") == true, "class spells not yet trained: still in (the level-1 grid keeps its shape)")
  ok(#sent == 0, "the first scan sends nothing (the grid builds from it)")
  items[#items + 1] = { spellID = 20580, name = "Shadowmeld" }
  knownIds[20580] = true
  CD:UpdateKnown()
  ok(CD:IsEntryAvailable("Meld") == true and #sent == 1 and sent[1] == "NOCK_VISUALS_CHANGED", "a racial that appears: in, and the grids rebuild")
  CD:UpdateKnown()
  ok(#sent == 1, "no change: no rebuild")
  for _, k in ipairs({ "Stone", "Fury", "Shatter", "Stomp", "Zerk", "FastRegen" }) do
    ok(CD:GetEntry(k) == nil and CD:IsEntryAvailable(k) == true, "a racial the spellbook does not name is untracked (GetEntry nil keeps it off the grid): " .. k)
  end
  -- The human pair carries proven ids (level-1 dump): tracked, gated out on this book.
  ok(CD:GetEntry("Percep").id == 20600 and CD:GetEntry("WillSurv").id == 1259718, "human racials: Perception 20600, Will to Survive 1259718")
  ok(CD:IsEntryAvailable("Percep") == false and CD:IsEntryAvailable("WillSurv") == false, "and out while the spellbook lacks them")
  -- An orc: Blood Fury under a NEW id resolves by name and joins the grid.
  items[#items + 1] = { spellID = 1260001, name = "Blood Fury" }
  knownIds[1260001] = true
  CD:UpdateKnown()
  local fury = CD:GetEntry("Fury")
  ok(fury ~= nil and CD:IsEntryAvailable("Fury") == true and Nock.state.cooldowns.Fury.spellId == 1260001 and Nock.state.cooldowns.Fury.icon == 100000 + 1260001, "Blood Fury resolved from the spellbook: tracked, available, the client's id and icon")
  ok(#sent == 2, "the resolution rebuilds the grid")
  ok(CD.ledger.learned[1260001] == 120, "the seed cooldown applies to the resolved id")
  now = 500
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1260001)
  CD:Refresh()
  ok(Nock.state.cooldowns.Fury.startTime == 500 and Nock.state.cooldowns.Fury.duration == 120, "a Blood Fury cast stamps the resolved tile")
  ok(CD:GetEntry("Shatter") == nil, "the orc's other racial stays untracked until named")
  ok(CD.events["SPELLS_CHANGED"] ~= nil, "the spellbook event refreshes the gate")
  _G.C_SpellBook = nil
  CD:UpdateKnown()
  ok(CD:IsEntryAvailable("Meld") == true, "no spellbook API: cannot tell, keep showing")
end

-- Racial buffs: the tile lights while the racial's own buff is up. In combat
-- (auras secret) the cast stamps it; out of combat the aura cache is the
-- truth; Shadowmeld is held until a move, cast or swing breaks it.
do
  local secretAuras = false
  _G.C_Secrets.ShouldAurasBeSecret = function() return secretAuras end
  local auras = {}   -- spellId -> record
  Nock.AuraCache = {
    BySpell = function(_, id) return auras[id] end,
    ByName = function(_, n) for _, a in pairs(auras) do if a.name == n then return a end end end,
  }
  local procMsgs = {}
  CD.SendMessage = function(_, m, key, on) if m == "NOCK_PROC_ACTIVE" then procMsgs[#procMsgs + 1] = key .. "=" .. tostring(on) end end
  local cds = Nock.state.cooldowns
  local function derive(key)  -- the tick's buffRemaining, as Core.lua derives it
    local c = cds[key]
    c.buffRemaining = (c.buffStartTime > 0 and c.buffDuration > 0) and math.max(0, c.buffStartTime + c.buffDuration - now) or 0
  end

  -- Elune's Light in combat: stamped for the 15 s seed, counts down, ends.
  secretAuras = true; now = 1000
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1259799)
  CD:Refresh(); derive("Elune")
  ok(cds.Elune.procActive == true and cds.Elune.buffDuration == 15 and cds.Elune.buffStartTime == 1000, "Elune cast in combat: active for the seeded 15 s")
  ok(cds.Elune.buffIcon == 100000 + 1259799 and cds.Elune.buffPermanent == false, "the buff pivots to the spell icon, timed")
  -- (Fury=false rides along: the Blood Fury cast at 500 above has expired)
  ok(table.concat(procMsgs, ",") == "Elune=true,Fury=false", "the edges are announced")
  now = 1010; CD:Refresh(); derive("Elune")
  ok(cds.Elune.procActive == true and math.abs(cds.Elune.buffRemaining - 5) < 1e-9, "5 s left at +10")
  now = 1016; CD:Refresh()
  ok(cds.Elune.procActive == false and cds.Elune.buffIcon == nil, "expired: the tile goes back to the cooldown")

  -- Out of combat the aura teaches the length and corrects the expiry.
  secretAuras = false; now = 2000
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1259799)
  CD:Refresh()
  ok(cds.Elune.procActive == true, "a fresh stamp survives a cache that has not caught up yet")
  auras[1259799] = { spellId = 1259799, name = "Elune's Light", duration = 12, expirationTime = 2012, icon = 777 }
  CD:Refresh()
  ok(cds.Elune.buffDuration == 12 and cds.Elune.buffStartTime == 2000 and cds.Elune.buffIcon == 777, "the aura is the truth out of combat")
  ok(Nock.db.char.foreverRacialBuff.Elune == 12, "the learned buff length is remembered")
  auras[1259799] = nil; now = 2003
  CD:Refresh()
  ok(cds.Elune.procActive == false, "aura gone out of combat (cancelled): the tile drops at once")

  -- Shadowmeld in combat: held with no timer until a move / cast / swing.
  secretAuras = true; now = 3000
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20580)
  CD:Refresh()
  ok(cds.Meld.procActive == true and cds.Meld.buffPermanent == true and cds.Meld.buffDuration == 0, "Shadowmeld: active, no timer")
  ok(cds.Meld.startTime == 0, "no cooldown while melded: it starts at the break")
  now = 3300; CD:Refresh()
  ok(cds.Meld.procActive == true and cds.Meld.startTime == 0, "still up minutes later (no expiry, no cooldown)")
  fire("PLAYER_STARTED_MOVING")
  CD:Refresh()
  ok(cds.Meld.procActive == false and cds.Meld.buffPermanent == false, "moving breaks it")
  ok(cds.Meld.startTime == 3300 and cds.Meld.duration == 10, "the break starts the 10 s cooldown")
  now = 3311; CD:Refresh()
  ok(cds.Meld.duration == 0 or cds.Meld.startTime + cds.Meld.duration <= now, "and it is ready 10 s after the break")
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20580); CD:Refresh()
  fire("PLAYER_SWING", 2.5, 2); CD:Refresh()
  ok(cds.Meld.procActive == false, "a swing breaks it")
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20580); CD:Refresh()
  fire("UNIT_SPELLCAST_START", "target", "g", 1); CD:Refresh()
  ok(cds.Meld.procActive == true, "someone else's cast does not")
  fire("UNIT_SPELLCAST_START", "player", "g", 19434); CD:Refresh()
  ok(cds.Meld.procActive == false, "starting a cast breaks it")
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20580); CD:Refresh()
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2973); CD:Refresh()
  ok(cds.Meld.procActive == false, "an instant breaks it")

  -- Out of combat a permanent aura holds it; its absence clears it.
  secretAuras = false; now = 4000
  auras[20580] = { spellId = 20580, name = "Shadowmeld", duration = 0, expirationTime = 0, icon = 888 }
  CD:Refresh()
  ok(cds.Meld.procActive == true and cds.Meld.buffPermanent == true and cds.Meld.buffIcon == 888, "the aura cache finds a permanent Shadowmeld")
  auras[20580] = nil; CD:Refresh()
  ok(cds.Meld.procActive == false, "and drops it when the aura goes")
  ok(cds.Meld.startTime == 4000 and cds.Meld.duration == 10, "an unseen break (cancelled out of combat) starts the cooldown when the aura goes")
  -- A guessed break that did not break it (still up out of combat): the stamp is taken back.
  now = 4100
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20580); CD:Refresh()
  fire("PLAYER_STARTED_MOVING"); CD:Refresh()
  ok(cds.Meld.startTime == 4100, "a move stamps the break")
  auras[20580] = { spellId = 20580, name = "Shadowmeld", duration = 0, expirationTime = 0, icon = 888 }
  CD:Refresh()
  ok(cds.Meld.procActive == true and cds.Meld.startTime == 0, "the aura says it held: active again, cooldown withdrawn")
  auras[20580] = nil

  -- A racial with no buff never lights.
  secretAuras = true
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1259718); CD:Refresh()
  ok(cds.WillSurv.procActive == false, "Will to Survive has no buff: never active")
  Nock.AuraCache = nil
end

print(("forever_cooldowns: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
