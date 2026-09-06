-- Tests/buff_tracker_show_test.lua
-- Nock.BuffTrackerShowApplies (Core/State.lua): the buff tracker's own show-when rule (rested, solo, dungeon / raid group).
-- Run from the repo root: luajit Tests/buff_tracker_show_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local addon = { Constants = {} }
_G.LibStub = function(name) return { GetAddon = function() return addon end } end
dofile("Core/Constants.lua")
dofile("Core/State.lua")

local S = addon.BuffTrackerShowApplies
ok(type(S) == "function", "predicate exists")

local function p(t) t.locked = t.locked == nil and true or t.locked; return t end

-- defaults: everything off -> always shown
ok(S(p({}), false, nil) == true, "defaults, solo, not rested -> show")
ok(S(p({}), true, nil) == true, "defaults, rested -> show (rested rule off)")
ok(S(nil, true, nil) == true, "no profile -> show")

-- rested
ok(S(p({ buffTrackerHideRested = true }), true, nil) == false, "hide rested + rested -> hide")
ok(S(p({ buffTrackerHideRested = true }), false, nil) == true, "hide rested + not rested -> show")
ok(S(p({ buffTrackerHideRested = true }), true, "RAID") == false, "hide rested + rested in a raid group -> hide (rested wins)")
ok(S(p({ buffTrackerHideRested = true, locked = false }), true, nil) == true, "unlocked -> show (must stay grabbable)")

-- solo
ok(S(p({ buffTrackerHideSolo = true }), false, nil) == false, "hide solo + solo -> hide")
ok(S(p({ buffTrackerHideSolo = true }), false, "PARTY") == true, "hide solo + party (dungeon on by default) -> show")
ok(S(p({ buffTrackerHideSolo = true }), false, "RAID") == true, "hide solo + raid (raid on by default) -> show")
ok(S(p({ buffTrackerHideSolo = true, buffTrackerShowParty = false }), false, "PARTY") == false, "hide solo + party, dungeon off -> hide")
ok(S(p({ buffTrackerHideSolo = true, buffTrackerShowRaid = false }), false, "RAID") == false, "hide solo + raid, raid off -> hide")
ok(S(p({ buffTrackerHideSolo = true, buffTrackerShowRaid = false }), false, "PARTY") == true, "hide solo + party, raid off -> show")
ok(S(p({ buffTrackerHideSolo = false, buffTrackerShowParty = false, buffTrackerShowRaid = false }), false, "RAID") == true, "solo rule off -> the group toggles are ignored")
ok(S(p({ buffTrackerHideSolo = true, locked = false }), false, nil) == true, "unlocked + solo -> show")

-- The same rule serves any panel by prefix (the Misdirection panel uses "md").
local G = addon.PanelShowApplies
ok(type(G) == "function", "generic predicate exists")
ok(G(p({ mdHideSolo = true }), "md", false, nil) == false, "md: hide solo + solo -> hide")
ok(G(p({ mdHideSolo = true }), "md", false, "RAID") == true, "md: hide solo + raid -> show")
ok(G(p({ mdHideRested = true }), "md", true, "RAID") == false, "md: hide rested + rested -> hide")
ok(G(p({ buffTrackerHideSolo = true }), "md", false, nil) == true, "md ignores the buff tracker's keys")

print(("buff_tracker_show_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
