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

-- Frames for the client-cooldown watch: a Cooldown widget records what it was
-- fed and keeps its OnCooldownDone script so a test can end it.
local frames = {}
_G.CreateFrame = function(kind)
  local f = { kind = kind, scripts = {} }
  function f:SetSize() end
  function f:SetPoint() end
  function f:SetAllPoints() end
  function f:SetAlpha() end
  function f:SetHideCountdownNumbers() end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:SetCooldownFromDurationObject(obj) self.fed = obj; self.feeds = (self.feeds or 0) + 1 end
  frames[#frames + 1] = f
  return f
end
local durObjZero = false
local function durObj() return { IsZero = function() return durObjZero end } end

local apiCd = {}   -- [id] = { start, duration }
local apiReads = 0
local Nock = {
  Flavor = { forever = true, Plain = function(v) if v == "SECRET" then return nil end return v end },
  API = {
    SpellCooldown = function(id) apiReads = apiReads + 1; if secretCds then return "SECRET", "SECRET", true end; local c = apiCd[id]; if c then return c[1], c[2], true end; return 0, 0, true end,
    SpellCooldownDuration = function() return durObj() end,
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

-- Set up test seeds for cold-start testing (cd values removed from catalog in 2026-09-27)
for _, e in ipairs(Nock.Spells.TRACKED) do
  if e.key == "Raptor" then e.cd = 6
  elseif e.key == "Arc" then e.cd = 6
  elseif e.key == "AimMulti" then e.cd = 6
  elseif e.key == "Conc" then e.cd = 12
  elseif e.key == "RF" then e.cd = 300
  elseif e.key == "FD" then e.cd = 30
  elseif e.key == "Elune" then e.cd = 180
  elseif e.key == "Meld" then e.cd = 10
  elseif e.key == "WillSurv" then e.cd = 180
  elseif e.key == "Fury" then e.cd = 120
  end
end
-- Rebuild Constants from the seeded TRACKED
local C = Nock.Constants
local tracked = {}
for i, e in ipairs(Nock.Spells.TRACKED) do
  local t = { type = "spell" }
  for k, v in pairs(e) do t[k] = v end
  tracked[i] = t
end
C.TRACKED_COOLDOWNS = tracked

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
ok(st.cooldowns.AimMulti.icon == "Interface\\AddOns\\Nock\\Media\\MultiAimed" and st.cooldowns.AimMulti.icon2 == nil,
   "the Multi + Aimed tile draws its own art (Media/MultiAimed.tga), one icon, no second half")
ok(pair.texture ~= nil, "the tile entry carries its texture to the grid (no split halves, no seam)")
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

-- Custom entries (the "Add an entry" form, profile.cooldownCustom): a spell
-- joins the lists like a catalog entry; an item is not tracked on Forever.
do
  Nock.db.profile.cooldownCustom = {
    { key = "c_spell_1543", type = "spell", id = 1543, label = "Flare" },
    { type = "spell", id = 20736 },                       -- no stored key: derived
    { key = "c_item_5512", type = "item", id = 5512 },
  }
  secretCds = false
  msg("NOCK_VISUALS_CHANGED")
  local flare = CD:GetEntry("c_spell_1543")
  ok(flare and flare.custom == true and flare.id == 1543 and flare.label == "Flare", "custom spell tracked with its label")
  ok(CD:GetEntry("c_spell_20736") and CD:GetEntry("c_spell_20736").label == "spell20736", "no key: derived key, spell name as label")
  ok(CD:GetEntry("c_item_5512") == nil, "custom item not tracked on Forever")
  ok(st.cooldowns.c_spell_1543 and st.cooldowns.c_spell_1543.icon == 100000 + 1543, "custom spell has a state slot and icon")
  local listed = false
  for _, k in ipairs(CD:GetOrderedGridKeys()) do if k == "c_spell_1543" then listed = true end end
  ok(listed, "custom spell in the ordered keys")
  now = 500
  apiCd[1543] = { 500, 20 }
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1543)
  fire("SPELL_UPDATE_COOLDOWN")
  CD:Refresh()
  ok(st.cooldowns.c_spell_1543.startTime == 500 and st.cooldowns.c_spell_1543.duration == 20, "custom spell cast learned and published")
  -- A custom entry on a catalog spell (Multi-Shot 2643) must not take the
  -- cast lookup from the pair: both tiles read the same ledger slot.
  Nock.db.profile.cooldownCustom = { { key = "c_spell_2643", type = "spell", id = 2643, label = "TEST" } }
  msg("NOCK_VISUALS_CHANGED")
  ok(CD:GetEntry("c_spell_2643") ~= nil, "custom on a catalog spell is tracked")
  ok(CD:Resolve(2643) == CD:GetEntry("AimMulti"), "the catalog pair keeps the cast lookup")
  secretCds = true; now = 600
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2643)
  CD:Refresh()
  ok(st.cooldowns.AimMulti.startTime == 600 and st.cooldowns.c_spell_2643.startTime == 600, "one Multi-Shot cast stamps the pair and the custom tile")
  secretCds = false
  Nock.db.profile.cooldownCustom = nil
  msg("NOCK_VISUALS_CHANGED")
  ok(CD:GetEntry("c_spell_1543") == nil, "removed custom leaves the lists")
end


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
    ok(CD:GetEntry(k) == nil and CD:IsEntryAvailable(k) == false, "a racial the spellbook does not name is untracked and unavailable (off the grid AND out of the tray): " .. k)
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
  ok(CD:IsEntryAvailable("Meld") == false, "no spellbook API: a racial cannot be confirmed, so it stays hidden")
  ok(CD:IsEntryAvailable("Raptor") == true, "no spellbook API: class spells keep showing")
end

-- Racial buffs: the tile lights while the racial's own buff is up. In combat
-- (auras secret) the cast stamps it; out of combat the aura cache is the
-- truth; Shadowmeld is held until a move, cast or swing breaks it.
do
  local secretAuras = false
  _G.C_Secrets.ShouldAurasBeSecret = function() return secretAuras end
  local auras, petAuras = {}, {}   -- spellId -> record, per unit
  local function on(unit) return unit == "pet" and petAuras or auras end
  Nock.AuraCache = {
    BySpell = function(unit, id) return on(unit)[id] end,
    ByName = function(unit, n) for _, a in pairs(on(unit)) do if a.name == n then return a end end end,
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

  -- A class spell with a buff of its own (Rapid Fire, 15 s; user report
  -- 2026-10-09: its tile had no active timer, only the cooldown): the same
  -- active phase as a racial, the cooldown running underneath.
  ok(CD:GetEntry("RF").buff == 15, "Rapid Fire carries its 15 s buff")
  secretAuras = true; now = 5000
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 3045)
  CD:Refresh(); derive("RF")
  ok(cds.RF.procActive == true and cds.RF.buffDuration == 15 and cds.RF.buffStartTime == 5000, "Rapid Fire cast in combat: active for 15 s")
  ok(cds.RF.startTime == 5000 and cds.RF.duration == 300, "its cooldown runs underneath")
  now = 5016; CD:Refresh()
  ok(cds.RF.procActive == false and cds.RF.buffIcon == nil, "buff over: the tile shows the cooldown")
  secretAuras = false; now = 6000
  auras[3045] = { spellId = 3045, name = "Rapid Fire", duration = 15, expirationTime = 6012, icon = 555 }
  CD:Refresh()
  ok(cds.RF.procActive == true and cds.RF.buffStartTime == 5997 and cds.RF.buffIcon == 555, "out of combat the aura is the truth")
  auras[3045] = nil; now = 6001
  CD:Refresh()
  ok(cds.RF.procActive == false, "and its absence clears it")
  -- Deterrence: a buff on the hunter, 10 s seed.
  ok(CD:GetEntry("Deter").buff == 10 and CD:GetEntry("Deter").buffUnit == nil, "Deterrence carries its 10 s buff, on you")
  secretAuras = true; now = 7000
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 19263)
  CD:Refresh(); derive("Deter")
  ok(cds.Deter.procActive == true and cds.Deter.buffDuration == 10 and cds.Deter.buffStartTime == 7000, "Deterrence cast in combat: active for 10 s")
  now = 7011; CD:Refresh()
  ok(cds.Deter.procActive == false, "Deterrence over: the cooldown")
  -- Bestial Wrath: the buff lives on the PET (18 s seed), so out of combat
  -- the pet's auras are the truth, not yours.
  ok(CD:GetEntry("BW").buff == 18 and CD:GetEntry("BW").buffUnit == "pet", "Bestial Wrath carries its 18 s buff, on the pet")
  secretAuras = true; now = 8000
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 19574)
  CD:Refresh(); derive("BW")
  ok(cds.BW.procActive == true and cds.BW.buffDuration == 18 and cds.BW.buffStartTime == 8000, "Bestial Wrath cast in combat: active for 18 s")
  secretAuras = false; now = 8001
  petAuras[19574] = { spellId = 19574, name = "Bestial Wrath", duration = 18, expirationTime = 8018, icon = 666 }
  CD:Refresh()
  ok(cds.BW.procActive == true and cds.BW.buffIcon == 666 and cds.BW.buffStartTime == 8000, "out of combat the PET's aura is the truth")
  auras[19574] = { spellId = 19574, name = "Bestial Wrath", duration = 18, expirationTime = 9999 }
  petAuras[19574] = nil; now = 8003
  CD:Refresh()
  ok(cds.BW.procActive == false, "gone from the pet: off (a same-named aura on you is not it)")
  auras[19574] = nil

  -- A class spell with no buff never lights.
  secretAuras = true
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2973); CD:Refresh()
  ok(cds.Raptor.procActive == false, "Raptor Strike has no buff: never active")
  Nock.AuraCache = nil
end

-- Usability on Forever (dim while unavailable, no-mana tint, reactive spells).
do
  local UR = CD.UsableRead
  local u, m = UR(true, false)
  ok(u == true and m == false, "plain reads pass through")
  u, m = UR("SECRET", "SECRET")
  ok(u == nil and m == nil, "a secret read is nil: the tile keeps its ready look")
  u, m = UR(nil, true)
  ok(u == nil and m == nil, "no usable answer: no mana answer either")
  -- Arc resolves to the spellbook's rank id (14281 in the test fixture), not the base id (3044)
  local arc = st.cooldowns.Arc
  local arcId = arc.spellId
  local usable = { [arcId] = true }
  Nock.API.SpellUsable = function(id) return usable[id] == true, false end
  Nock.API.IsReactiveSpell = function(id) return id == arcId end
  CD:ScanUsable()
  ok(arc.usable == true and arc.noMana == false and arc.reactive == true, "ScanUsable publishes usable / noMana / reactive")
  usable[arcId] = false
  CD:SPELL_UPDATE_COOLDOWN()
  ok(arc.usable == false, "re-read on a cooldown update")
  ok(CD.events.SPELL_UPDATE_USABLE == "ScanUsable", "SPELL_UPDATE_USABLE drives it")
  Nock.API.SpellUsable, Nock.API.IsReactiveSpell = nil, nil
end

-- Client-cooldown watch (Disengage report 2026-09-27): a combat-only custom
-- spell never read out of combat is timed by the client's own cooldown end.
do
  local V = CD.DoneVerdict
  local l, c = V(1.4, false)
  ok(l == nil and c == false, "a GCD-long end teaches nothing and leaves the ledger")
  l, c = V(5.04, false)
  ok(l == 5 and c == true, "a first real end teaches the length (rounded) and ends the ledger")
  l, c = V(3.2, true)
  ok(l == nil and c == true, "a known length is not relearned: an early end (reset) just ends the ledger")

  Nock.db.profile.cooldownCustom = { { key = "c_spell_20736", type = "spell", id = 20736, label = "Dis" } }
  Nock.db.char = {}
  CD:OnConfigChanged()
  local s = st.cooldowns.c_spell_20736
  secretCds = true
  now = 1000
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20736); CD:Refresh()
  ok(s.clientRunning == true, "cast of an unlearned spell: the client's cooldown runs")
  ok(s.duration == 0, "the ledger cannot time it")
  local w = CD._watch.c_spell_20736
  ok(w and w.cd.fed ~= nil, "the watch widget was fed the duration object")
  now = 1000.5; CD:SPELL_UPDATE_COOLDOWN()
  ok(w.cd.feeds == 2, "an update inside the feed window re-feeds (GCD -> cooldown)")
  now = 1002; CD:SPELL_UPDATE_COOLDOWN()
  ok(w.cd.feeds == 2, "no re-feed after the window")
  now = 1005; w.cd.scripts.OnCooldownDone(); CD:Refresh()
  ok(s.clientRunning == nil, "the client's end clears clientRunning")
  ok(Nock.db.char.foreverLearned[20736] == 5, "the length was learned in combat and remembered")
  now = 1010
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20736); CD:Refresh()
  ok(s.startTime == 1010 and s.duration == 5, "the next cast is timed by the ledger")
  now = 1012; w.cd.scripts.OnCooldownDone(); CD:Refresh()
  ok(s.startTime == 0 and s.duration == 0, "an early client end (reset) ends the ledger's countdown")
  ok(Nock.db.char.foreverLearned[20736] == 5, "and does not relearn a known length")

  durObjZero = true
  now = 1020
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20736)
  ok(s.clientRunning == nil, "a plainly-zero duration object is nothing to watch")
  durObjZero = false
  now = 1030
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20736)
  ok(s.clientRunning == true, "armed again")
  now = 1030 + 901; CD:Refresh()
  ok(s.clientRunning == nil, "a watch the client never ended is dropped")
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20736)
  secretCds = false
  CD:Rescan()
  ok(s.clientRunning == nil, "an out-of-combat read of no cooldown disarms a missed watch")
  Nock.db.profile.cooldownCustom = nil
  CD:OnConfigChanged()
end

-- Shared-cooldown group fallback (2026-09-28): a cast of a spell the ledger
-- has never learned still arms the client-cooldown watch, and that fallback
-- must mark EVERY tile in the shared group, not just the one that was cast --
-- Arc and Hawk share one cooldown (arcaneHawk) but Hawk alone has no seed or
-- learned duration in this fixture.
do
  ok(Nock.LedgerEngine.Known(CD.ledger, 1293241) == false, "Summon Hawk has no learned duration in this fixture")
  st.cooldowns.Arc.clientRunning = nil
  now = 2000
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1293241)
  ok(st.cooldowns.Hawk.clientRunning == true, "the cast arms Hawk's own client-cooldown watch")
  ok(st.cooldowns.Arc.clientRunning == true, "the shared group also marks Arc, which never armed a watch of its own")
end

-- Sting tiles (2026-09-30): a sting with no cooldown of its own arms no
-- client watch (it would only count the GCD down on the tile the sting's own
-- timer is about to cover); a sting that was discovered with a cooldown does.
do
  ok(CD:GetEntry("Serpent") and CD:GetEntry("Serpent").debuff == true, "Serpent Sting is a tracked sting tile")
  now = 2100
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1978)
  ok(st.cooldowns.Serpent.clientRunning == nil, "a sting without a cooldown arms no watch")
  CD:GetEntry("Viper").discovered = true
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 3034)
  ok(st.cooldowns.Viper.clientRunning == true, "a sting with a discovered cooldown is watched like any spell")
  CD:GetEntry("Viper").discovered = nil
end

-- Rescan out-of-combat wipe (2026-09-28): Arcane Shot on
-- cooldown per the API, Summon Hawk unlearned and reading 0/0 (apiCd has no
-- entry for it) -- a Rescan must not let Hawk's meaningless zero clear the
-- shared cooldown Arc's own reading just set. Both tiles read the group.
-- (spellId is read off the published state rather than assumed to be the
-- catalog's static 3044/1293241: an earlier block in this file resolves
-- Arc's ledger id to a spellbook rank, same as any other name-matched entry.)
do
  local arcId, hawkId = st.cooldowns.Arc.spellId, st.cooldowns.Hawk.spellId
  apiCd[arcId] = { 5000, 6 }
  apiCd[hawkId] = nil
  secretCds = false
  now = 5000
  CD:Rescan()
  CD:Refresh()
  ok(st.cooldowns.Arc.startTime == 5000 and st.cooldowns.Arc.duration == 6,
     "Arc survives a Rescan even though Hawk's own reading is 0/0")
  ok(st.cooldowns.Hawk.startTime == 5000 and st.cooldowns.Hawk.duration == 6,
     "Hawk reads the same shared cooldown through the group, not its own empty reading")
  ok(CD:GetEntry("ArcHawk") and st.cooldowns.ArcHawk.startTime == 5000 and st.cooldowns.ArcHawk.duration == 6,
     "the combined Arcane + Hawk tile reads the same shared cooldown")
  ok(st.cooldowns.ArcHawk.icon == "Interface\\AddOns\\Nock\\Media\\ArcaneHawk" and st.cooldowns.ArcHawk.icon2 == nil,
     "the combined Arcane + Hawk tile draws its own art, one icon, no second half")
end

-- Summon Hawk's guardians: the client reports no count, so own casts are
-- tallied (18 s each, two at most) and published as the tile's count on the
-- Hawk tile and the combined Arcane + Hawk tile.
do
  local list = {}
  ok(CD.SummonCount(list, 10) == 0, "no hawk out before a cast")
  CD.SummonPush(list, 10, 18, 2)
  ok(CD.SummonCount(list, 10) == 1, "one cast, one hawk")
  CD.SummonPush(list, 16, 18, 2)
  ok(CD.SummonCount(list, 16) == 2, "a second cast, two hawks")
  CD.SummonPush(list, 22, 18, 2)
  ok(CD.SummonCount(list, 22) == 2, "a third cast replaces the oldest: still two")
  ok(CD.SummonCount(list, 33.9) == 2 and CD.SummonCount(list, 34) == 1, "the 16 s hawk leaves at 34")
  ok(CD.SummonCount(list, 40) == 0 and #list == 0, "the last one leaves at 40; the list is pruned")

  now = 6000
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 3044)
  CD:Refresh()
  ok(st.cooldowns.Hawk.count == nil and st.cooldowns.ArcHawk.count == nil, "Arcane Shot summons nothing")
  now = 6006
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1293241)
  CD:Refresh()
  ok(st.cooldowns.Hawk.count == 1 and st.cooldowns.ArcHawk.count == 1, "a Summon Hawk cast counts on both tiles")
  ok(st.cooldowns.Arc.count == nil, "the Arcane Shot tile carries no count")
  now = 6012
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1293241)
  CD:Refresh()
  ok(st.cooldowns.Hawk.count == 2 and st.cooldowns.ArcHawk.count == 2, "two hawks out")
  now = 6024
  CD:Refresh()
  ok(st.cooldowns.Hawk.count == 1, "the first hawk's 18 s ran out")
  fire("PLAYER_DEAD")
  CD:Refresh()
  ok(st.cooldowns.Hawk.count == nil and st.cooldowns.ArcHawk.count == nil, "dying clears the tally")
end

print(("forever_cooldowns: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
