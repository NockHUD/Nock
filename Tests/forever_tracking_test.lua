-- Tests/forever_tracking_test.lua
-- Forever/Tracking.lua: the hunter's tracking as state (which Track spell is
-- on, which one the target's creature type wants, Improved Tracking's rank)
-- and the wrong-tracking warning in Forever/Warnings.lua over it.
-- Run from the repo root: luajit Tests/forever_tracking_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local now = 100
_G.GetTime = function() return now end
local NAMES = {
  [1494] = "Track Beasts", [19883] = "Track Humanoids", [19884] = "Track Undead", [19878] = "Track Demons",
  [19879] = "Track Dragonkin", [19880] = "Track Elementals", [19882] = "Track Giants", [19885] = "Track Hidden",
}
local Nock = {
  Flavor = { forever = true, Plain = function(v) if v == "SECRET" then return nil end return v end },
  API = { SpellIcon = function(id) return 1000 + id end, SpellName = function(id) return NAMES[id] end },
  db = { profile = {} },
  Constants = {},
}
local modules = {}
function Nock:NewModule(name) local m = { name = name, events = {}, msgs = {} }
  function m:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function m:RegisterMessage(mm, h) self.msgs[mm] = h or mm end
  modules[name] = m; return m end
function Nock:GetModule(name) return modules[name] end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/Spells.lua")
dofile("Forever/Traits.lua")
dofile("Forever/Tracking.lua")

-- The trait tree (Forever/Traits.lua): one walk per loadout builds the map
-- of every node by spell id AND by name, so a talent whose id is not pinned
-- yet (Improved Tracking) is found by its name. Shared with Lone Wolf.
do
  local Tr = Nock.Traits
  local walks = 0
  local CT = { GetActiveConfigID = function() return 42 end }
  local T = {
    GetConfigInfo = function() return { treeIDs = { 1091 } } end,
    GetTreeNodes = function() walks = walks + 1; return { 105006, 105007, 105008 } end,
    GetNodeInfo = function(_, n) return { entryIDs = { n + 24664 }, activeRank = n == 105007 and 1 or (n == 105008 and 4 or 0) } end,
    GetEntryInfo = function(_, e) return { definitionID = e } end,
    GetDefinitionInfo = function(d)
      if d == 129671 then return { spellID = 415370 } end
      if d == 129672 then return { spellID = 999001, overrideName = "Improved Tracking" } end
      return { spellID = 19454 }
    end,
  }
  local nameOf = function(id) return ({ [415370] = "Lone Wolf", [19454] = "Hawk Eye" })[id] end
  Tr.Reset()
  ok(Tr.Rank(415370, CT, T, nameOf) == 1 and Tr.Rank(19454, CT, T, nameOf) == 0 and walks == 1, "two spells, one walk")
  ok(Tr.RankByName("Improved Tracking", CT, T, nameOf) == 4 and walks == 1, "found by the definition's override name, no new walk")
  ok(Tr.RankByName("Hawk Eye", CT, T, nameOf) == 0 and Tr.RankByName("Nope", CT, T, nameOf) == nil, "by the spell's name; an unknown name is nil")
  ok(Tr.Rank(77, CT, T, nameOf) == nil and Tr.Rank(415370, nil, T) == nil, "no such talent or no API: nil")
  local rows = Tr.Find("Track", CT, T, nameOf)
  ok(#rows == 1 and rows[1].name == "Improved Tracking" and rows[1].spellID == 999001 and rows[1].rank == 4, "Find: every talent whose name has the word, with id and rank")
  CT.GetActiveConfigID = function() return 43 end
  Tr.Rank(415370, CT, T, nameOf)
  ok(walks == 2, "a new loadout walks again")
  Tr.Reset()
end

-- The spell table: eight Track spells, seven creature types that have one.
local S = Nock.Spells
ok(S.TRACKING and S.TRACKING[1494] == "beasts" and S.TRACKING[19883] == "humanoids" and S.TRACKING[19885] == "hidden", "Track spells by id")
ok(#S.TRACKING_RING == 8 and S.TRACKING_RING[1] == "beasts", "eight wheel slots, Beasts up")
ok(S.IMPROVED_TRACKING == 24293, "Improved Tracking by its spell id (probe 2026-09-28)")
ok(S.TRACK_BY_CREATURE_TYPE[1] == 1494 and S.TRACK_BY_CREATURE_TYPE[7] == 19883 and S.TRACK_BY_CREATURE_TYPE[6] == 19884
   and S.TRACK_BY_CREATURE_TYPE[9] == nil, "creature type id -> Track spell (Beast 1, Humanoid 7, Undead 6; Mechanical 9 none)")

-- Pure: the Track spell a creature type wants. `typeNames` is the client's
-- localized list ([typeId] = name); without one the English names serve.
local T = Nock.TrackingForCreatureType
local de = { [1] = "Wildtier", [2] = "Drachkin", [3] = "Dämon", [4] = "Elementar", [5] = "Riese", [6] = "Untoter", [7] = "Humanoid", [8] = "Kleintier", [9] = "Mechanisch" }
ok(T("Wildtier", de) == 1494 and T("Untoter", de) == 19884 and T("Humanoid", de) == 19883, "localized names through the client's list")
ok(T("Kleintier", de) == nil and T("Mechanisch", de) == nil, "a type with no Track spell: nil")
ok(T("Beast", nil) == 1494 and T("Dragonkin", nil) == 19879 and T("Giant", nil) == 19882 and T("Elemental", nil) == 19880 and T("Demon", nil) == 19878, "no client list: English names")
ok(T("Critter", nil) == nil and T("Not specified", nil) == nil and T(nil, nil) == nil and T("", de) == nil, "critters, unspecified, nothing: nil")

-- Pure: the active Track spell from the minimap tracking list (spellID when
-- the client fills it, the entry's name otherwise; nil when none is on).
local A = Nock.TrackingActive
ok(A({ { name = "Track Beasts", active = false, spellID = 1494 }, { name = "Track Undead", active = true, spellID = 19884 }, { name = "Find Minerals", active = false } }) == 19884, "active by spell id")
ok(A({ { name = "Track Demons", active = true }, { name = "Track Beasts", active = false } }) == 19878, "active by name when the id is missing")
ok(A({ { name = "Track Beasts", active = false }, { name = "Find Herbs", active = true, spellID = 2383 } }) == nil, "no Track spell on: nil (a profession tracking is not one)")
ok(A({}) == nil and A(nil) == nil, "empty or no list: nil")

-- The module: state.tracking from plain reads.
local M = modules.Tracking
ok(M and M.refreshInterval == 0.2, "module Tracking on the slow lane")
local st = Nock.state.tracking
ok(st and st.activeId == nil and st.targetTrackId == nil and st.rank == nil and type(st.known) == "table", "state slot")

-- The reads are injected so the test needs no client.
local list = { { name = "Track Beasts", active = true, spellID = 1494 } }
local creature = "Beast"
local rank = 3
local learned = { ["Track Beasts"] = 1, ["Track Humanoids"] = 1 }
M.Reads = {
  trackingList = function() return list end,
  creatureType = function() return creature end,
  creatureTypeNames = function() return nil end,
  traitRank = function(id, name) return rank end,
  spellbook = function() return learned end,
  inCombat = function() return false end,
}
M:OnEnable()
ok(M.events.MINIMAP_UPDATE_TRACKING and M.events.SPELLS_CHANGED and M.events.PLAYER_ENTERING_WORLD, "listens for tracking, spellbook and world changes")
M:Refresh(Nock.state)
ok(st.activeId == 1494, "Track Beasts on: activeId")
ok(st.targetTrackId == 1494 and st.targetTypeName == "Beast", "a beast target wants Track Beasts")
ok(st.known[1494] == true and st.known[19883] == true and st.known[19884] == nil, "known Track spells by spellbook name")
ok(st.rank == 3, "Improved Tracking rank")
ok(st.wrong == false, "tracking matches: not wrong")
creature = "Undead"
M:Refresh(Nock.state)
ok(st.targetTrackId == 19884 and st.wrong == false, "an undead target wants Track Undead, but it is not learned: not wrong")
creature = "Humanoid"
M:Refresh(Nock.state)
ok(st.targetTrackId == 19883 and st.wrong == true, "a humanoid target with Track Beasts on and Humanoids learned: wrong")
list = { { name = "Track Beasts", active = false, spellID = 1494 }, { name = "Track Humanoids", active = true, spellID = 19883 } }
M:MINIMAP_UPDATE_TRACKING()
M:Refresh(Nock.state)
ok(st.activeId == 19883 and st.wrong == false, "switching to Track Humanoids clears it")
list = { { name = "Track Beasts", active = false, spellID = 1494 }, { name = "Track Humanoids", active = false, spellID = 19883 } }
M:MINIMAP_UPDATE_TRACKING()
M:Refresh(Nock.state)
ok(st.activeId == nil and st.wrong == true, "no tracking on with a humanoid target: wrong")
creature = "Mechanical"
M:Refresh(Nock.state)
ok(st.targetTrackId == nil and st.wrong == false, "a mechanical target: nothing to track, not wrong")
creature = nil
M:Refresh(Nock.state)
ok(st.targetTrackId == nil and st.targetTypeName == nil and st.wrong == false, "no target: nothing")
-- The talent is read out of combat and held through a fight.
creature = "Humanoid"
rank = 0
M:Refresh(Nock.state)
ok(st.rank == 3, "the rank is held between rechecks")
M._rankAt = -100
M.Reads.inCombat = function() return true end
M:Refresh(Nock.state)
ok(st.rank == 3, "in combat: the out-of-combat rank holds")
M.Reads.inCombat = function() return false end
M:Refresh(Nock.state)
ok(st.rank == 0, "out of combat after the recheck: re-read")
ok(st.wrong == true, "wrong is about the tracking alone; the talent gate is the warning's")
-- Testing without the talent: `/nock probe tracking any` publishes rank 1.
M.ignoreTalent = true
M._rankAt = -100
M:Refresh(Nock.state)
ok(st.rank == 1, "ignoreTalent: rank 1 published whatever the tree says")
M.ignoreTalent = nil
M._rankAt = -100
M:Refresh(Nock.state)
ok(st.rank == 0, "off again: the tree's answer")
-- The spellbook decides the wheel's slots too.
learned = { ["Track Beasts"] = 1 }
M:SPELLS_CHANGED()
ok(st.known[19883] == nil and st.knownRev >= 1, "a spellbook change re-reads the known list and bumps the rev")

-- The warning (Forever/Warnings.lua): reads.trackingRank > 0, a live hostile
-- target whose type has a learned Track spell that is not on, the gate.
local module
Nock.NewModule = function(_, name) module = { name = name }; return module end
dofile("Forever/Warnings.lua")
local W = module
local G = W.GateAllows
ok(G("always", "none") and G("always", "party") and G("always", "raid"), "always: everywhere")
ok(not G("dungeon", "none") and G("dungeon", "party") and G("dungeon", "raid"), "dungeon: dungeons and raids")
ok(not G("raid", "none") and not G("raid", "party") and G("raid", "raid"), "raid: raids only")
ok(G(nil, "none") and G("bogus", "none"), "unset or unknown reads as always")
local Ch = W.Checks
local base = { trackingRank = 3, targetHostile = true, trackNeeded = 19883, trackKnown = true, trackActive = 1494, instanceKind = "none" }
-- reads.now follows the test clock
local function with(t) local r = { now = now }; for k, v in pairs(base) do r[k] = v end; for k, v in pairs(t or {}) do r[k] = v end; return r end
now = 100
ok(Ch.wrongTracking(with()) == nil, "first sight: the grace holds it")
now = 101.1
local w = Ch.wrongTracking(with())
ok(w and w.id == "wrongTracking" and w.severity == "amber" and w.icon == 1000 + 19883 and w.text == "TRACK", "held 1 s: amber TRACK with the needed Track spell's icon")
ok(Ch.wrongTracking(with({ trackActive = 19883 })) == nil, "right tracking on: quiet")
now = 100; Ch.wrongTracking(with()); now = 101.1
ok(Ch.wrongTracking(with({ trackingRank = 0 })) == nil and Ch.wrongTracking(with({ trackingRank = nil })) == nil, "no points in Improved Tracking (or unknown): quiet")
now = 100; Ch.wrongTracking(with()); now = 101.1
ok(Ch.wrongTracking(with({ trackNeeded = nil })) == nil, "a type with no Track spell: quiet")
now = 100; Ch.wrongTracking(with()); now = 101.1
ok(Ch.wrongTracking(with({ trackKnown = false })) == nil, "the needed Track spell not learned: quiet")
now = 100; Ch.wrongTracking(with()); now = 101.1
ok(Ch.wrongTracking(with({ targetHostile = false })) == nil, "no live hostile target: quiet")
now = 100; Ch.wrongTracking(with()); now = 101.1
ok(Ch.wrongTracking(with({ trackActive = nil })) ~= nil, "no tracking on at all: fires")
Nock.db.profile.warnTrackingGate = "dungeon"
now = 100; Ch.wrongTracking(with()); now = 101.1
ok(Ch.wrongTracking(with()) == nil, "gate dungeon in the open world: quiet")
now = 100; Ch.wrongTracking(with({ instanceKind = "party" })); now = 101.1
ok(Ch.wrongTracking(with({ instanceKind = "party" })) ~= nil and Ch.wrongTracking(with({ instanceKind = "raid" })) ~= nil, "gate dungeon inside: fires")
Nock.db.profile.warnTrackingGate = "raid"
now = 100; Ch.wrongTracking(with({ instanceKind = "raid" })); now = 101.1
ok(Ch.wrongTracking(with({ instanceKind = "raid" })) ~= nil and Ch.wrongTracking(with({ instanceKind = "party" })) == nil, "gate raid: raids only")
Nock.db.profile.warnTrackingGate = nil
Nock.db.profile.warnTrackingEnabled = false
ok(Ch.wrongTracking(with()) == nil, "disabled: quiet")
Nock.db.profile.warnTrackingEnabled = nil
-- A retarget restarts the grace.
now = 100; Ch.wrongTracking(with()); now = 100.5
ok(Ch.wrongTracking(with({ trackNeeded = 19884 })) == nil, "a different need restarts the grace")
now = 101.6
ok(Ch.wrongTracking(with({ trackNeeded = 19884 })) ~= nil, "and fires after it")

-- Catalog entry with the gate select.
local cat
for _, e in ipairs(W.Catalog) do if e.key == "wrongTracking" then cat = e end end
ok(cat and cat.category == "combat" and cat.severity == "amber" and cat.enabledKey == "warnTrackingEnabled" and cat.description and cat.logic, "catalog entry")
ok(cat.selects and cat.selects[1].key == "warnTrackingGate" and cat.selects[1].values.always and cat.selects[1].values.dungeon and cat.selects[1].values.raid
   and cat.selects[1].default == "always", "gate select always / dungeon / raid, default always")
ok(type(cat.iconFn()) == "number", "catalog icon resolves")
-- The reads: the warning reads the tracking state and the instance kind.
Nock.state.tracking.rank, Nock.state.tracking.targetTrackId, Nock.state.tracking.activeId = 2, 19884, 1494
Nock.state.tracking.known[19884] = true
Nock.state.target.exists, Nock.state.target.alive, Nock.state.target.friendly = true, true, false
_G.IsInInstance = function() return true, "party" end
W.InInstance = function() return true end
local r = W:Reads(Nock.state)
ok(r.trackingRank == 2 and r.trackNeeded == 19884 and r.trackKnown == true and r.trackActive == 1494 and r.instanceKind == "party", "reads from state.tracking and IsInInstance")
_G.IsInInstance = function() return false, "none" end
ok(W:Reads(Nock.state).instanceKind == "none", "open world: none")
_G.IsInInstance = nil
ok(W:Reads(Nock.state).instanceKind == "none", "no API: none")

print(("forever_tracking: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
