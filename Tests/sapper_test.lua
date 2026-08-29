-- Tests/sapper_test.lua
-- Standalone LuaJIT tests for the EXPERIMENTAL sapper tracker
-- (Modules/SapperTracker.lua): combat-log detection of Goblin/Super Sapper
-- Charge use across the group, the shared 5-minute cooldown, the authoritative
-- own-item cooldown, and the MD + Sapper raid announce.
-- Run from the repo root: luajit Tests/sapper_test.lua
--
-- Core/Constants.lua is the real file, so the item IDs and the 300s cooldown
-- under test are the shipping ones.

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, tol) return math.abs((a or -1) - b) <= (tol or 1e-6) end

--------------------------------------------------------------------------------
-- Minimal WoW surface
--------------------------------------------------------------------------------
local now = 1000
_G.GetTime = function() return now end

-- Group roster the module scans. player + raid1..N.
local units = {}
_G.UnitExists = function(u) return units[u] ~= nil end
_G.UnitName   = function(u) return units[u] end

local SUPER, GOBLIN = 23827, 10646
local ITEM = {
  [SUPER]  = { name = "Super Sapper Charge",  spellId = 30486, icon = "tex-super"  },
  [GOBLIN] = { name = "Goblin Sapper Charge", spellId = 13241, icon = "tex-goblin" },
}
local bagCount, itemCD = {}, {}
_G.GetItemSpell = function(id)
  local e = ITEM[id]
  if not e then return nil end
  return e.name, e.spellId          -- sapper use-effect shares the item's name
end
_G.GetItemInfo = function(id)
  local e = ITEM[id]
  if not e then return nil end
  return e.name, nil, nil, nil, nil, nil, nil, nil, nil, e.icon
end
_G.GetItemCount    = function(id) return bagCount[id] or 0 end
_G.GetItemCooldown = function(id)
  local c = itemCD[id]
  if not c then return 0, 0, 0 end
  return c[1], c[2], 1
end

local sent = {}
_G.SendChatMessage = function(msg, ch) sent[#sent + 1] = { msg = msg, ch = ch } end
local inRaid = true
_G.IsInRaid  = function() return inRaid end
_G.IsInGroup = function() return true end

-- Current combat-log packet, returned in the real 14-field order.
local ev = {}
_G.CombatLogGetCurrentEventInfo = function()
  return now, ev.sub, false, ev.srcGUID, ev.srcName, 0, 0,
         ev.destGUID, ev.destName, 0, 0, ev.spellId, ev.spellName, 1
end

--------------------------------------------------------------------------------
-- Addon stubs
--------------------------------------------------------------------------------
local Nock = {
  state = { misdirection = { hunters = {} } },
  db = { profile = {
    mdSapperEnabled       = true,
    mdSapperAnnounce      = true,
    mdSapperAnnounceScope = "all",
  } },
}
local Sapper
function Nock:NewModule()
  Sapper = {}
  function Sapper:RegisterEvent() end
  function Sapper:RegisterMessage() end
  function Sapper:Print() end
  return Sapper
end
_G.LibStub = function() return { GetAddon = function() return Nock end } end

dofile("Core/Constants.lua")
dofile("Modules/SapperTracker.lua")

local C = Nock.Constants
ok(C.SAPPER and C.SAPPER.CD == 300, "constants: sappers share a 5-minute cooldown")
ok(C.SAPPER.ITEMS[1] == SUPER and C.SAPPER.ITEMS[2] == GOBLIN,
   "constants: Super is preferred over Goblin")

--------------------------------------------------------------------------------
-- Harness helpers
--------------------------------------------------------------------------------
local state

-- Full reset between scenarios: clock, roster, bags, recorded uses, chat log.
local function reset(profile)
  now = 1000
  units = { player = "Robhunter", raid1 = "Tankos", raid2 = "Otherhunter" }
  bagCount, itemCD, sent = {}, {}, {}
  Nock.state.misdirection.hunters = {}
  local p = Nock.db.profile
  p.mdSapperEnabled       = true
  p.mdSapperAnnounce      = true
  p.mdSapperAnnounceScope = "all"
  for k, v in pairs(profile or {}) do p[k] = v end
  state = {}
  Sapper:OnEnable()
end

local function fire(sub, srcName, spellId, spellName, destName)
  ev = {
    sub      = sub,
    srcGUID  = "GUID-" .. srcName,
    srcName  = srcName,
    destGUID = destName and ("GUID-" .. destName) or ("GUID-" .. srcName),
    destName = destName or srcName,
    spellId  = spellId,
    spellName = spellName or "Super Sapper Charge",
  }
  Sapper:OnCombatLog()
end

local function entry(name)
  Sapper:Refresh(state)
  return state.sapper and state.sapper.byName and state.sapper.byName[name]
end

-- Give a hunter an MD record the way Modules/Misdirection publishes it.
local function md(hunter, target, castAgo)
  Nock.state.misdirection.hunters[hunter] =
    { name = hunter, target = target, castTime = now - castAgo }
end

--------------------------------------------------------------------------------
-- 1. Spell matching: resolved IDs, cold-start fallback IDs, and the name.
--------------------------------------------------------------------------------
reset()
fire("SPELL_CAST_SUCCESS", "Robhunter", 30486, "Super Sapper Charge")
ok(entry("Robhunter") ~= nil, "match: the resolved Super Sapper spell ID")

reset()
fire("SPELL_CAST_SUCCESS", "Robhunter", 12760, "Goblin Sapper Charge")
ok(entry("Robhunter") ~= nil, "match: a fallback catalog ID GetItemSpell never returned")

reset()
fire("SPELL_CAST_SUCCESS", "Robhunter", 99999, "Goblin Sapper Charge")
ok(entry("Robhunter") ~= nil, "match: an unknown ID still matches on the spell name")

reset()
fire("SPELL_CAST_SUCCESS", "Robhunter", 27019, "Arcane Shot")
ok(entry("Robhunter") == nil, "match: an unrelated spell is ignored")

--------------------------------------------------------------------------------
-- 2. Only group members are tracked.
--------------------------------------------------------------------------------
reset()
fire("SPELL_CAST_SUCCESS", "Randomstranger", 30486)
ok(entry("Randomstranger") == nil, "roster: a non-group source is ignored")

-- Cross-realm names arrive as "Name-Realm" but every roster key is short.
reset()
fire("SPELL_CAST_SUCCESS", "Tankos-Firemaw", 30486)
ok(entry("Tankos") ~= nil, "roster: a cross-realm source keys off the short name")

-- Someone who joins after OnEnable is picked up on the roster event.
reset()
units.raid3 = "Latejoiner"
Sapper:OnRosterUpdate()
fire("SPELL_CAST_SUCCESS", "Latejoiner", 30486)
ok(entry("Latejoiner") ~= nil, "roster: rescans on GROUP_ROSTER_UPDATE")

--------------------------------------------------------------------------------
-- 3. The shared 5-minute cooldown, and what survives it.
--------------------------------------------------------------------------------
reset()
fire("SPELL_CAST_SUCCESS", "Tankos", 30486)
local e = entry("Tankos")
ok(e.known == true,                "cd: an observed use marks them a known sapper carrier")
ok(near(e.cdRemaining, 300),       "cd: a fresh use is the full 300s")
ok(near(e.cdDuration, 300),        "cd: duration is the shared Explosives cooldown")
now = now + 100
ok(near(entry("Tankos").cdRemaining, 200), "cd: drains with the clock")
now = now + 201
e = entry("Tankos")
ok(near(e.cdRemaining, 0),  "cd: never goes negative")
ok(e.known == true,         "cd: they stay a known carrier once the cooldown is up")

--------------------------------------------------------------------------------
-- 4. One use is one record. The self-damage backstop must not re-arm it.
--------------------------------------------------------------------------------
reset()
fire("SPELL_CAST_SUCCESS", "Tankos", 30486)
now = now + 0.3
fire("SPELL_DAMAGE", "Tankos", 30486)            -- the sapper hurting its user
ok(near(entry("Tankos").cdRemaining, 299.7),
   "dedupe: the self-hit after a cast does not restart the cooldown")

-- With no SPELL_CAST_SUCCESS at all, the self-hit is the evidence of a use.
reset()
fire("SPELL_DAMAGE", "Tankos", 30486)
ok(near(entry("Tankos").cdRemaining, 300), "backstop: a bare self-hit records the use")

-- Damage dealt to somebody else is not evidence of who used it.
reset()
fire("SPELL_DAMAGE", "Tankos", 30486, "Super Sapper Charge", "Gruul")
ok(entry("Tankos") == nil, "backstop: damage to a third party is not counted")

--------------------------------------------------------------------------------
-- 5. Your own row is item-driven, not log-driven.
--------------------------------------------------------------------------------
reset()
bagCount[GOBLIN] = 5
e = entry("Robhunter")
ok(e and e.known == true,   "self: carrying a sapper is enough to light the slot")
ok(near(e.cdRemaining, 0),  "self: nothing used yet means ready")

reset()
bagCount[GOBLIN] = 5
itemCD[GOBLIN] = { now - 60, 300 }
ok(near(entry("Robhunter").cdRemaining, 240), "self: GetItemCooldown drives the countdown")

-- Last charge used: the item is gone from the bags, so only the log knows.
reset()
fire("SPELL_CAST_SUCCESS", "Robhunter", 30486)
ok(near(entry("Robhunter").cdRemaining, 300),
   "self: falls back to the observed use when the bags are empty")

-- Super in the bags while the shared cooldown is running from a Goblin use.
reset()
bagCount[SUPER] = 1
itemCD[SUPER] = { now - 10, 300 }
fire("SPELL_CAST_SUCCESS", "Robhunter", 13241)
ok(near(entry("Robhunter").cdRemaining, 300),
   "self: takes the longer of the item cooldown and the observed use")

--------------------------------------------------------------------------------
-- 6. The MD + Sapper announce.
--------------------------------------------------------------------------------
reset()
md("Robhunter", "Tankos", 5)
fire("SPELL_CAST_SUCCESS", "Robhunter", 30486)
ok(#sent == 1, "announce: one message for your own MD + Sapper")
ok(sent[1] and sent[1].msg:find("Tankos", 1, true) ~= nil, "announce: names the MD target")
ok(sent[1] and sent[1].ch == "RAID", "announce: goes to raid chat in a raid")

reset()
inRaid = false
md("Robhunter", "Tankos", 5)
fire("SPELL_CAST_SUCCESS", "Robhunter", 30486)
ok(sent[1] and sent[1].ch == "PARTY", "announce: party chat outside a raid")
inRaid = true

reset()
md("Robhunter", "Tankos", 31)
fire("SPELL_CAST_SUCCESS", "Robhunter", 30486)
ok(#sent == 0, "announce: silent once the 30s MD window has passed")

reset()
fire("SPELL_CAST_SUCCESS", "Robhunter", 30486)
ok(#sent == 0, "announce: a bare sapper with no MD says nothing")

reset()
md("Robhunter", "Tankos", 5)
fire("SPELL_CAST_SUCCESS", "Tankos", 30486)
ok(#sent == 0, "announce: a tank's own sapper is not an MD opener")

-- Another hunter's opener, under each scope.
reset()
md("Otherhunter", "Tankos", 2)
fire("SPELL_CAST_SUCCESS", "Otherhunter", 30486)
ok(#sent == 1, "announce (all): another hunter's MD + Sapper is announced")
ok(sent[1] and sent[1].msg:find("Otherhunter", 1, true) ~= nil,
   "announce (all): names the hunter who did it")

reset({ mdSapperAnnounceScope = "self" })
md("Otherhunter", "Tankos", 2)
fire("SPELL_CAST_SUCCESS", "Otherhunter", 30486)
ok(#sent == 0, "announce (self): another hunter's opener is left alone")
md("Robhunter", "Tankos", 2)
fire("SPELL_CAST_SUCCESS", "Robhunter", 30486)
ok(#sent == 1, "announce (self): your own opener still goes out")

reset({ mdSapperAnnounce = false })
md("Robhunter", "Tankos", 5)
fire("SPELL_CAST_SUCCESS", "Robhunter", 30486)
ok(#sent == 0, "announce: off means off")
ok(entry("Robhunter") ~= nil, "announce: the cooldown is still tracked with announce off")

--------------------------------------------------------------------------------
-- 6b. The "next up in the rotation" call-out. Fired by the per-hunter button on
--     the tracker rows (view -> NOCK_MD_NEXTUP -> here), so unlike the
--     automatic MD + Sapper line it is a deliberate press and always speaks.
--------------------------------------------------------------------------------
reset()
Sapper:OnNextUp(nil, "Otherhunter")
ok(#sent == 1, "next-up: one message per press")
ok(sent[1] and sent[1].msg == "Next up in MD + Sapper Rotation: Otherhunter",
   "next-up: exact wording")
ok(sent[1] and sent[1].ch == "RAID", "next-up: raid chat in a raid")

reset()
Sapper:OnNextUp(nil, "Otherhunter-Firemaw")
ok(sent[1] and sent[1].msg:find("Firemaw", 1, true) == nil, "next-up: strips the realm")

reset()
inRaid = false
Sapper:OnNextUp(nil, "Otherhunter")
ok(sent[1] and sent[1].ch == "PARTY", "next-up: party chat outside a raid")
inRaid = true

-- Double-click / mashing must not spam the raid, but naming somebody else is
-- an immediate, separate call.
reset()
Sapper:OnNextUp(nil, "Otherhunter")
now = now + 1
Sapper:OnNextUp(nil, "Otherhunter")
ok(#sent == 1, "next-up: a repeat press inside the window is swallowed")
Sapper:OnNextUp(nil, "Robhunter")
ok(#sent == 2, "next-up: a different hunter goes out straight away")
now = now + 5
Sapper:OnNextUp(nil, "Otherhunter")
ok(#sent == 3, "next-up: the same hunter again later is fine")

reset({ mdSapperAnnounce = false })
Sapper:OnNextUp(nil, "Otherhunter")
ok(#sent == 1, "next-up: a press speaks even with the automatic announce off")

reset()
Sapper:OnNextUp(nil, nil)
ok(#sent == 0, "next-up: no name, no message")

--------------------------------------------------------------------------------
-- 7. The experimental master switch gates the whole feature.
--------------------------------------------------------------------------------
reset({ mdSapperEnabled = false })
md("Robhunter", "Tankos", 5)
fire("SPELL_CAST_SUCCESS", "Robhunter", 30486)
bagCount[GOBLIN] = 5
ok(#sent == 0, "disabled: no announce")
ok(entry("Robhunter") == nil, "disabled: nothing published for the view to draw")

-- Turning it back on mid-session must not need a reload.
Nock.db.profile.mdSapperEnabled = true
fire("SPELL_CAST_SUCCESS", "Robhunter", 30486)
ok(entry("Robhunter") ~= nil, "re-enabled: starts tracking again")

--------------------------------------------------------------------------------
-- 8. Missing profile / pre-login safety.
--------------------------------------------------------------------------------
reset()
local savedDB = Nock.db
Nock.db = nil
local okCall = pcall(function()
  fire("SPELL_CAST_SUCCESS", "Robhunter", 30486)
  Sapper:Refresh({})
end)
ok(okCall, "safety: survives being driven before AceDB exists")
Nock.db = savedDB

print(("sapper: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
