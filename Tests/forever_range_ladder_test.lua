-- Tests/forever_range_ladder_test.lua
-- Forever/RangeLadder.lua: layout, segment resolution replayed from the two
-- 2026-09-24 probe logs, settle, zones. Run from the repo root.

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local L = dofile("Forever/RangeLadder.lua")
ok(type(L) == "table" and type(L.Resolve) == "function", "engine loads standalone")

-- Layout: Auto Shot 8-35 without Hawk Eye (probed), 37/39/41 with it.
local base = L.Layout(8, 35)
local keys = {}
for i = 1, #base do keys[i] = base[i].key end
ok(table.concat(keys, ",") == "MELEE,DEAD,8_20,20_25,25_28,28_30,30_35,35_40,OOR", "base layout, got " .. table.concat(keys, ","))
ok(base[3].label == "8-20" and base[8].label == "35-40" and base[9].label == "OUT OF RANGE", "base labels")
ok(base.has4041 == false and base.id == "8-35", "no 40-41 segment without Hawk Eye 3")
ok(L.Layout(8, 37)[8].label == "35-37" and L.Layout(8, 39)[8].label == "35-39", "Hawk Eye 1/2 relabel the far segment")
local he3 = L.Layout(8, 41)
ok(he3.has4041 and he3[9].key == "40_41" and he3[9].label == "40-41" and he3[10].key == "OOR", "Hawk Eye 3 adds 40-41")
ok(he3[8].label == "35-40", "rank 3: the 35 segment reads 35-40")
local dflt = L.Layout(nil, nil)
ok(dflt.id == "8-35" and dflt[3].label == "8-20", "unknown ranges fall back to 8/35")
ok(base[1].short == "M" and base[2].short == "D" and base[3].short == "20" and base[4].short == "25" and base[8].short == "40" and base[9].short == "OUT", "detailed in-segment labels: the upper bound only (user 2026-09-25)")
ok(base[3].label == "8-20" and base[5].label == "25-28", "the long name keeps the range")
ok(he3[9].short == "41" and L.Layout(8, 37)[8].short == "37", "in-segment labels follow Hawk Eye")

-- Compact style (user 2026-09-24, the default): 20-40 is one block that
-- shows the live bracket.
local cmp = L.Layout(8, 35, true)
local ck = {}
for i = 1, #cmp do ck[i] = cmp[i].key end
ok(table.concat(ck, ",") == "MELEE,DEAD,8_20,FAR,OOR", "compact layout, got " .. table.concat(ck, ","))
ok(cmp[4].short == "20-40" and cmp[4].members["20_25"] and cmp[4].members["35_40"] and not cmp[4].members["40_41"], "the far block holds 20-25 .. 35-40")
ok(cmp.id ~= base.id and cmp.has4041 == false, "compact has its own id")
ok(cmp.fine["25_28"] and cmp.fine["25_28"].short == "25-28" and cmp.fine["25_28"].color == L.COLORS.blue, "compact keeps the fine brackets for label and colour")
ok(cmp[1].short == "MELEE" and cmp[2].short == "DEAD" and cmp[3].short == "8-20", "compact keeps the full labels (it has the room)")
local chE = L.Layout(8, 41, true)
ok(chE[4].short == "20-41" and chE[4].members["40_41"] and chE.has4041, "Hawk Eye 3 compact: 20-41 holds 40-41")
ok(L.Layout(8, 37, true).fine["35_40"].short == "35-37", "compact fine label follows Hawk Eye")
ok(base.fine["30_35"] == base[7], "detailed layout maps each bracket to itself")

-- Log replay. Columns as the probe printed them: 1 i8149, 5 i10645,
-- 7 i13289, 9 i7734, 10 i18904, 11 i4945, 16 CID 4, 17 Auto Shot, 19 Wing Clip.
local COL = { i8149 = 1, i10645 = 5, i13289 = 7, i7734 = 9, i18904 = 10, i4945 = 11, cid4 = 16, shoot = 17, wingClip = 19 }
local function parse(row)
  local tok = {}
  for t in row:gmatch("%S+") do tok[#tok + 1] = t end
  local r = {}
  for k, i in pairs(COL) do
    local v = tok[i]
    if v == "T" then r[k] = true elseif v == "F" then r[k] = false else r[k] = nil end
  end
  return r
end

local OUT = {  -- out of combat, walking out
  { 0.10,  "T - - - - - - - - - - - T T T T F T T - - F F F - - T", "MELEE" },
  { 0.20,  "T - - - T - T T T T T - T T T T F T T - - F F F - - T", "MELEE" },
  { 6.64,  "T - - - T - T T T T T - T T T T F T F - - F F F - - T", "DEAD" },
  { 7.91,  "F - - - T - T T T T T - T T T T F T F - - F F F - - T", "DEAD" },
  { 20.18, "F - - - T - T T T T T - T F F T F T F - - F F F - - T", "DEAD" },
  { 44.68, "F - - - T - T T T T T - T F F T T T F - - T T T - - T", "8_20" },
  { 66.66, "F - - - F - T T T T T - T F F T T T F - - T T T - - T", "20_25" },
  { 70.03, "F - - - F - F T T T T - T F F T T T F - - T T T - - T", "25_28" },
  { 71.72, "F - - - F - F T T T T - F F F F T T F - - T T T - - T", "28_30" },
  { 73.49, "F - - - F - F F F T T - F F F F T T F - - T T T - - T", "30_35" },
  { 77.58, "F - - - F - F F F F T - F F F F F T F - - F F F - - T", "35_40", false },
}
local COMBAT = {  -- in combat, out and back (combat dropped on some rows; readings identical)
  { 0.11,   "T - - - T - T T T T T - T T T T F T T - - F F F - - T", "MELEE" },
  { 8.23,   "T - - - T - T T T T T - T T T T F T F - - F F F - - T", "DEAD" },
  { 9.65,   "F - - - T - T T T T T - T T T T F T F - - F F F - - T", "DEAD" },
  { 36.22,  "F - - - T - T T T T T - T F F T F T F - - F F F - - T", "DEAD" },
  { 45.45,  "F - - - T - T T T T T - T T T T F T F - - F F F - - T", "DEAD" },
  { 45.75,  "T - - - T - T T T T T - T T T T F T F - - F F F - - T", "DEAD" },
  { 46.05,  "T - - - T - T T T T T - T T T T F T T - - F F F - - T", "MELEE" },
  { 47.24,  "T - - - T - T T T T T - T T T T F T F - - F F F - - T", "DEAD" },
  { 47.79,  "F - - - T - T T T T T - T F F T F T F - - F F F - - T", "DEAD" },
  { 56.85,  "F - - - T - T T T T T - T F F T T T F - - T T T - - T", "8_20" },
  { 58.05,  "F - - - T - T T T T T - T F F T F T F - - F F F - - T", "DEAD" },
  { 61.63,  "F - - - T - T T T T T - T F F T T T F - - T T T - - T", "8_20" },
  { 81.54,  "F - - - F - T T T T T - T F F T T T F - - T T T - - T", "20_25" },
  { 87.81,  "F - - - F - F T T T T - T F F T T T F - - T T T - - T", "25_28" },
  { 89.59,  "F - - - F - F T T T T - F F F F T T F - - T T T - - T", "28_30" },
  { 91.69,  "F - - - F - F F F T T - F F F F T T F - - T T T - - T", "30_35" },
  { 96.99,  "F - - - F - F F F F T - F F F F F T F - - F F F - - T", "35_40", false },
  { 102.80, "F - - - F - F F F T T - F F F F T T F - - T T T - - T", "30_35" },
  { 123.29, "F - - - F - F T T T T - F F F F T T F - - T T T - - T", "28_30" },
  { 123.74, "F - - - F - F T T T T - T F F T T T F - - T T T - - T", "25_28" },
  { 124.07, "F - - - F - T T T T T - T F F T T T F - - T T T - - T", "20_25" },
  { 124.74, "F - - - T - T T T T T - T F F T T T F - - T T T - - T", "8_20" },
  { 128.07, "F - - - T - T T T T T - T F F T F T F - - F F F - - T", "DEAD" },
  { 129.05, "F - - - T - T T T T T - T F F T T T F - - T T T - - T", "8_20" },
}
for _, log in ipairs({ { "out", OUT }, { "combat", COMBAT } }) do
  local st = {}
  for _, row in ipairs(log[2]) do
    local r = parse(row[2])
    local key, shoot = L.Resolve(r, base)
    ok(key == row[3], ("%s %.2f: resolve %s, got %s"):format(log[1], row[1], row[3], tostring(key)))
    if row[4] == false then ok(shoot == false, ("%s %.2f: not shootable"):format(log[1], row[1])) end
    -- settled 0.2 s later (the finder refreshes at 10 Hz)
    L.Settle(st, key, shoot, row[1])
    local pk = L.Settle(st, key, shoot, row[1] + 0.2)
    ok(pk == row[3], ("%s %.2f: published %s, got %s"):format(log[1], row[1], row[3], tostring(pk)))
  end
end

-- Wing Clip unknown (nil): melee falls back to item 8149.
ok(L.Resolve({ i8149 = true, i10645 = true }, base) == "MELEE", "Wing Clip unknown: 8149 in range is melee")
ok(L.Resolve({ wingClip = false, i8149 = true, i10645 = true }, base) == "DEAD", "Wing Clip known and out: 8149 does not make melee")
-- nil readings (items not cached yet) read as out and never throw.
ok(L.Resolve({}, base) == nil, "all nil (cold item cache): no segment rather than a wrong one")
ok(L.Resolve({ shoot = true, wingClip = false }, base) == nil, "shoot answers but no item does: still unknown")
ok(L.Resolve({ wingClip = true }, base) == "MELEE", "Wing Clip alone still says melee")
ok(L.Resolve({ i10645 = false }, base) == "OOR", "an item that answers out: out of range")
local OUTS = { i10645 = false, i13289 = false, cid4 = false, i7734 = false, i18904 = false, i4945 = false }
local function with(extra) local r = {}; for k, v in pairs(OUTS) do r[k] = v end; for k, v in pairs(extra) do r[k] = v end; return r end
ok(L.Resolve(with({ shoot = true }), base) == "35_40", "shoot with every item out, no 40-41 segment: 35-40")
ok(L.Resolve(with({ shoot = true }), he3) == "40_41", "the same with Hawk Eye 3: 40-41")
ok(select(2, L.Resolve({ i4945 = true, shoot = true }, he3)) == true, "35-40 shootable under Hawk Eye")

-- Settle: a 0.1 s blip is swallowed, a held change publishes, nil resets.
local st = {}
ok(L.Settle(st, "8_20", true, 10) == "8_20", "first segment publishes at once")
ok(L.Settle(st, "DEAD", false, 10.05) == "8_20", "a change is held")
ok(L.Settle(st, "8_20", true, 10.15) == "8_20", "blip over: back to the published one")
ok(L.Settle(st, "DEAD", false, 10.20) == "8_20" and L.Settle(st, "DEAD", false, 10.36) == "DEAD", "a change held 0.16 s publishes")
local k, s = L.Settle(st, "DEAD", true, 10.37)
ok(k == "DEAD" and s == false, "a shootability flip is held like a segment change")
ok(L.Settle(st, nil, false, 11) == nil and L.Settle(st, "30_35", true, 11.01) == "30_35", "no target resets: the next segment publishes at once")

-- Zones: the rest of the HUD reads these.
local function z(k2, sh) local a, b = L.Zone(k2, sh); return a .. "/" .. b end
ok(z("MELEE", false) == "MELEE/0.5" and z("DEAD", false) == "CLOSE/0", "melee and dead zone")
ok(z("8_20", true) == "SWEET/-0.5" and z("35_40", true) == "SWEET/-0.5", "shootable segments are SWEET")
ok(z("35_40", false) == "LONG/-1" and z("OOR", false) == "LONG/-1", "unshootable far segments are LONG")
ok(L.Zone(nil, false) == nil and select(2, L.Zone(nil, false)) == -1, "no segment, no zone")

-- Colours: 35-40 turns red once Auto Shot no longer reaches.
ok(L.SegColor(base[8], true) == L.COLORS.purple and L.SegColor(base[8], false) == L.COLORS.red, "35-40 purple / red")
ok(L.SegColor(base[4], false) == L.COLORS.teal, "other segments keep their colour")

print(("forever_range_ladder: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
