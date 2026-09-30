-- Tests/react_sting_tiles_view_test.lua
-- UI/Frame_ReactCooldowns.lua's sting-tile wiring (Forever): the tick syncs
-- the tiles after a rebuild and again after combat, a target change re-reads
-- them, a spellbook change re-checks their ids.
-- Run from the repo root: luajit Tests/react_sting_tiles_view_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local inCombat = false
_G.InCombatLockdown = function() return inCombat end

local syncs, rereads, stale = {}, 0, 0
local pendingNext = false
local NAMES = { [1978] = "Serpent Sting", [13549] = "Serpent Sting", [13550] = "Renamed", [777] = "Custom Sting", [3034] = "Viper Sting", [14279] = "Viper Sting" }
local Nock = {
  Constants = { REACT_CD_ROWS = {} },
  Flavor = { forever = true, Plain = function(v) return v end },
  API = { SpellName = function(id) return NAMES[id] end },
  Spells = { STING_RANKS = { Serpent = { 1978, 13549, 13550 }, Viper = { 3034, 14279 } } },
  ForeverSpellbookNames = function() return { ["Serpent Sting"] = 1300001 } end,
  db = { profile = { gridIconZoom = 5, reactConsumablesAlways = true } },   -- no whenActive watch: nothing rebuilds
  UI = {},
}
Nock.ForeverStingTiles = {
  Ids = function(candidates, name, nameOf, book)
    local out = {}
    for _, id in ipairs(candidates) do if nameOf(id) == name then out[#out + 1] = id end end
    if book and type(book[name]) == "number" then out[#out + 1] = book[name] end
    return out
  end,
  Sync = function(tiles, slots, parent, env)
    syncs[#syncs + 1] = { tiles = tiles, slots = slots, parent = parent, inCombat = env.inCombat, zoom = env.zoom, idsFor = env.idsFor }
    return pendingNext
  end,
  RereadAll = function() rereads = rereads + 1 end,
  MarkIdsStale = function() stale = stale + 1 end,
}
local view
function Nock:NewModule(name) view = { name = name }; return view end
function Nock:GetModule() return nil end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("UI/Frame_ReactCooldowns.lua")

local shown = true
view.frame = { IsShown = function() return shown end }
view._pool = {}
view._stingTiles = {}
local state = { cooldowns = {}, target = {} }

-- A rebuild marks the tiles dirty; the next tick syncs them once.
view._stingDirty = true
view:Refresh(state)
ok(#syncs == 1 and syncs[1].tiles == view._stingTiles and syncs[1].slots == view._pool and syncs[1].parent == view.frame,
   "the tick syncs the tiles against the grid's slots")
ok(syncs[1].inCombat == false and syncs[1].zoom == 5, "out of combat, at the grid's icon zoom")
view:Refresh(state)
ok(#syncs == 1, "a clean tile set is not synced again")

-- The ids of a sting entry: its ranks the client still names like rank 1,
-- plus the spellbook's id; an entry without a rank list falls back to its id.
local ids = syncs[1].idsFor({ key = "Serpent", id = 1978, name = "Serpent Sting" })
ok(table.concat(ids, " ") == "1978 13549 1300001", "rank list filtered by name, spellbook id added")
ids = syncs[1].idsFor({ key = "Other", id = 777, name = "Custom Sting" })
ok(table.concat(ids, " ") == "777", "no rank list: the entry's own id")
-- The unified tile: every covered sting's ids (a key without ranks is skipped).
ids = syncs[1].idsFor({ key = "Sting", id = 1978, name = "Serpent Sting", stings = { "Serpent", "Scorpid", "Viper" } })
ok(table.concat(ids, " ") == "1978 13549 1300001 3034 14279", "unified tile: the ids of every sting it covers")

-- Work left waiting by combat is picked up by the tick once combat ends.
inCombat = true
pendingNext = true
view._stingDirty = true
view:Refresh(state)
ok(#syncs == 2 and syncs[2].inCombat == true, "in combat: synced once, told so")
view:Refresh(state)
ok(#syncs == 2, "in combat: the pending work is not retried every tick")
inCombat = false
pendingNext = false
view:Refresh(state)
ok(#syncs == 3 and syncs[3].inCombat == false, "after combat: synced again")
view:Refresh(state)
ok(#syncs == 3, "and then left alone")

-- A hidden grid does nothing.
shown = false
view._stingDirty = true
view:Refresh(state)
ok(#syncs == 3, "a hidden grid is not synced")
shown = true

-- Events.
view:OnStingTarget()
ok(rereads == 1, "a target change re-reads the tiles")
view:OnStingSpells()
ok(stale == 0, "a spellbook change with no sting tile built does nothing")
view._stingTiles.Serpent = { c = {} }
view._stingDirty = false
view:OnStingSpells()
ok(stale == 1 and view._stingDirty == true, "a spellbook change re-checks the ids at the next tick")

-- TBC (no tile set): the tick never touches the sting code.
view._stingTiles, view._stingDirty, view._stingAfterCombat = nil, nil, nil
view:Refresh(state)
ok(#syncs == 3, "no tile set: no sync")

print(("react_sting_tiles_view: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
