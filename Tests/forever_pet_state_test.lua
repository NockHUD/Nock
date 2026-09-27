-- Tests/forever_pet_state_test.lua
-- Forever/Pet.lua: publishes state.pet from plain reads; owns the Lone Wolf check.
-- Run from the repo root: luajit Tests/forever_pet_state_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local now = 100
_G.GetTime = function() return now end
_G.time = os.time
_G.date = os.date
local petExists, petDead, happiness, dmg = true, false, 3, 125
_G.UnitExists = function(u) return u == "pet" and petExists or false end
_G.UnitIsDead = function(u) return u == "pet" and petDead or false end
_G.C_PetInfo = { GetPetHappiness = function() return happiness, dmg, 20 end }
local Nock = {
  Flavor = { forever = true, Plain = function(v) if v == "SECRET" then return nil end return v end },
  API = { SpellIcon = function(id) return 1000 + id end },
  db = { profile = {}, char = {} },
  Constants = {},
}
local modules = {}
function Nock:NewModule(name) local m = { name = name, events = {} }
  function m:RegisterEvent(ev, h) self.events[ev] = h or ev end
  modules[name] = m; return m end
function Nock:GetModule(name) return modules[name] end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/Spells.lua")
dofile("Forever/Pet.lua")
local Pet = modules.ForeverPet
ok(Pet and Pet.refreshInterval == 0.1, "module ForeverPet on the slow lane")
local st = Nock.state
st.player.inCombat = false

Pet:Refresh(st)
ok(st.pet.exists and not st.pet.dead and st.pet.happiness == 3 and st.pet.damagePct == 125, "live happy pet published")
happiness = "SECRET"
Pet:Refresh(st)
ok(st.pet.happiness == nil, "secret happiness reads nil")
happiness = 2
petDead = true
Pet:Refresh(st)
ok(st.pet.dead == true, "dead published")
petExists, petDead = false, false
Pet:Refresh(st)
ok(st.pet.exists == false and st.pet.happiness == nil, "no pet: exists false, happiness nil")
petExists = true

-- Tier changes reach the recorder hook, measured against the last KNOWN
-- tier, so a change across a no-pet gap counts (reviewer finding #2).
local seen = {}
local real = Pet.OnHappinessChange
function Pet:OnHappinessChange(from, to, _, via) seen[#seen + 1] = from .. ">" .. to .. ":" .. tostring(via) end
happiness = 3; Pet:Refresh(st)   -- last known 2 (read while dead) -> 3 after the no-pet gap
happiness = 2; Pet:Refresh(st)   -- 3 -> 2 live
ok(#seen == 2 and seen[1] == "2>3:dismiss" and seen[2] == "3>2:live", "live and across-a-gap changes reported, got " .. table.concat(seen, ","))
happiness = 2; Pet:Refresh(st)
ok(#seen == 2, "no change: nothing reported")
Pet.OnHappinessChange = real

-- Lone Wolf (moved here from forever_warnings_test.lua with the code).
do
  local LW, ID = Pet.LoneWolfFrom, 415370
  ok(Nock.Spells.LONE_WOLF == ID, "Lone Wolf by its spell id (read from the talent tree)")
  ok(select(2, LW(ID, function(id) return id == ID and 1 or 0 end)) == "talent", "talented: the loadout node has a rank")
  ok(LW(ID, function() return 0 end) == false, "a node with rank 0 is not talented")
  ok(select(2, LW(ID, nil, function(id) return id == ID end)) == "spellbook", "fallback: the spell is known")
  ok(select(2, LW(ID, nil, nil, function(id) return id == ID and {} or nil end)) == "aura", "fallback: an aura on you")
  ok(LW(ID) == false and LW(nil, function() return 1 end) == false, "nothing to go on: not talented")

  -- The trait walk: the active loadout's node holding the spell, found once.
  local walks, rank = 0, 1
  local CT = { GetActiveConfigID = function() return 42 end }
  local T = {
    GetConfigInfo = function() return { treeIDs = { 1091 } } end,
    GetTreeNodes = function() walks = walks + 1; return { 105006, 105007 } end,
    GetNodeInfo = function(_, n) return { entryIDs = { n + 24664 }, activeRank = n == 105007 and rank or 0 } end,
    GetEntryInfo = function(_, e) return { definitionID = e } end,
    GetDefinitionInfo = function(d) return { spellID = d == 129671 and ID or 19454 } end,
  }
  Pet.ResetTraitCache()
  ok(Pet.TraitRank(ID, CT, T) == 1, "trait walk: Lone Wolf's node, rank 1")
  rank = 0
  ok(Pet.TraitRank(ID, CT, T) == 0 and walks == 1, "the node is remembered: no second walk, the rank re-read")
  CT.GetActiveConfigID = function() return 43 end
  Pet.TraitRank(ID, CT, T)
  ok(walks == 2, "a new loadout walks again")
  ok(Pet.TraitRank(ID, nil, T) == nil and Pet.TraitRank(99, { GetActiveConfigID = function() return 44 end }, T) == nil, "no API or no such talent: nil")
  Pet.ResetTraitCache()

  -- The module's cached read: decided out of combat, held through a fight.
  local known = true
  _G.C_SpellBook = { IsSpellKnown = function(id) return id == ID and known end }
  Pet._loneWolfAt = nil
  ok(Pet:LoneWolf(false) == true and Pet._loneWolfHow == "spellbook", "out of combat: read (spellbook fallback here)")
  known = false
  ok(Pet:LoneWolf(true) == true, "in combat: the out-of-combat answer holds")
  Pet._loneWolfAt = -100
  ok(Pet:LoneWolf(false) == false, "out of combat again after the recheck: re-read (untalented)")
  _G.C_SpellBook = nil
  Pet._loneWolf, Pet._loneWolfAt = nil, nil
end

-- Warnings reads Lone Wolf from state.
local wmod
do
  local saveNew = Nock.NewModule
  function Nock:NewModule(name) wmod = saveNew(self, name); return wmod end
  dofile("Forever/Warnings.lua")
  Nock.NewModule = saveNew
end
st.pet.loneWolf = true
ok(wmod:Reads(st).loneWolf == true, "Warnings reads loneWolf from state.pet")
st.pet.loneWolf = false
ok(wmod:Reads(st).loneWolf == false, "Warnings follows state.pet.loneWolf")

-- Recorder (phase 1b). Settle on Happy first, THEN clear the log, so the
-- earlier tests' tier changes don't count.
petExists, petDead, happiness = true, false, 3
Pet:Refresh(st)
Nock.db.char.petHappinessLog = {}
Pet._loginAt = 1000
_G.time = function() return 1600 end
now = 200
petExists = false; Pet:Refresh(st)        -- dismiss at t=1600
petExists = true; Pet:Refresh(st)         -- summon at t=1600
happiness = 2; st.player.inCombat = true; Pet:Refresh(st)
local log = Nock.db.char.petHappinessLog
local e = log[#log]
ok(#log == 1 and e.from == 3 and e.to == 2 and e.combat == true and e.sinceLogin == 600, "a 3->2 drop is recorded with context")
ok(e and e.sinceSummon == 0 and e.lastDismissAgo == 0, "summon/dismiss edges recorded")
for i = 1, 60 do happiness = (i % 2 == 0) and 3 or 2; Pet:Refresh(st) end
ok(#log == 50, "ring keeps 50")
local text = Pet.LogText and Pet:LogText()
ok(type(text) == "string" and text:find("3 > 2", 1, true) ~= nil, "log text lists tier changes")
st.player.inCombat = false

-- Across a dismiss: Happy, dismissed, back Content -> logged with the gap.
Nock.db.char.petHappinessLog = {}
_G.time = function() return 2000 end
happiness = 3; Pet:Refresh(st)
petExists = false; Pet:Refresh(st)
_G.time = function() return 2300 end
petExists, happiness = true, 2; Pet:Refresh(st)
e = Nock.db.char.petHappinessLog[1]
ok(e and e.from == 3 and e.to == 2 and e.via == "dismiss" and e.gap == 300, "dismiss gap: 3 > 2 over 300 s")

-- Across a logout: a new session's first read against the saved last tier.
Nock.db.char.petHappinessLog = {}
Nock.db.char.petHappinessLast = { tier = 3, at = 1000 }
Nock.db.char.petHappinessLogoutAt = 1100
Pet._sawKnown = nil
st.pet.happiness = nil
_G.time = function() return 1600 end
happiness = 2; Pet:Refresh(st)
e = Nock.db.char.petHappinessLog[1]
ok(e and e.from == 3 and e.to == 2 and e.via == "login" and e.gap == 600 and e.logoutAgo == 500, "login gap: 3 > 2, 600 s since last read, logged out 500 s ago")
ok(Pet.events.PLAYER_LOGOUT ~= nil or (Pet.OnEnable ~= nil), "logout is stamped")
Pet:OnEnable()
ok(Pet.events.PLAYER_LOGOUT ~= nil, "PLAYER_LOGOUT registered")
Pet[type(Pet.events.PLAYER_LOGOUT) == "string" and Pet.events.PLAYER_LOGOUT or "PLAYER_LOGOUT"](Pet, "PLAYER_LOGOUT")
ok(Nock.db.char.petHappinessLogoutAt == 1600, "logout time saved")

print(("forever_pet_state: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
