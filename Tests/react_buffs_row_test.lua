-- Tests/react_buffs_row_test.lua
-- Standalone LuaJIT tests for the React proc row (UI/Frame_ReactBuffs.lua)
-- under Tests/lib/frame_stub.lua: the pet's Frenzy proc is a slot, a target
-- out of Auto Shot range is a desaturated MOVE IN slot, and the row's order
-- puts what only this row can tell you (alerts, Windfury, pet) BEFORE the
-- player's own procs, so a full house drops a trinket proc, never the alert.
-- Run from the repo root: luajit Tests/react_buffs_row_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.UIParent = Stub.CreateFrame("Frame")
_G.GetTime = function() return 1000 end
_G.unpack = unpack or table.unpack

-- Aura surface -----------------------------------------------------------------
local playerBuffs, petBuffs = {}, {}
local petExists, targetExists, targetAttackable, targetDead = true, true, true, false
_G.UnitExists = function(u)
  if u == "pet" then return petExists end
  if u == "target" then return targetExists end
  return false
end
_G.UnitCanAttack = function() return targetAttackable end
_G.UnitIsDeadOrGhost = function() return targetDead end
_G.UnitBuff = function(unit, i)
  local b = (unit == "player" and playerBuffs or unit == "pet" and petBuffs or {})[i]
  if not b then return nil end
  return b.name, b.icon or ("icon-" .. b.name), 1, "Magic", 10, 1010, "player", false, false, b.id
end
local NAMES = { [19615] = "Frenzy", [27046] = "Mend Pet", [1539] = "Feed Pet Effect",
                [24394] = "Intimidation", [5384] = "Feign Death", [34477] = "Misdirection",
                [24932] = "Leader of the Pack", [34299] = "Improved Leader of the Pack",
                [8835] = "Grace of Air Totem", [75] = "Auto Shot" }
_G.GetSpellInfo = function(id) return NAMES[id] or ("Spell " .. id), nil, "icon-" .. id end
_G.GetNumRaidMembers = function() return 0 end
_G.GetNumPartyMembers = function() return 0 end
_G.UnitClass = function() return "Hunter", "HUNTER" end

-- Addon shell --------------------------------------------------------------------
local Nock = { Constants = {}, state = {}, modules = {} }
function Nock:NewModule(name)
  local m = { name = name }
  function m:RegisterMessage() end
  function m:RegisterEvent() end
  function m:SendMessage() end
  Nock.modules[name] = m
  return m
end
function Nock:GetModule(name) return Nock.modules[name] end
function Nock.IsLocked() return true end
_G.LibStub = setmetatable({}, { __call = function(_, lib, silent)
  if lib == "AceAddon-3.0" then return { GetAddon = function() return Nock end } end
  if silent then return nil end
  return {}
end })

dofile("Core/Constants.lua")
dofile("Config/Defaults.lua")
dofile("Core/State.lua")
Nock.db = { profile = {} }
for k, v in pairs(Nock.Defaults.profile) do Nock.db.profile[k] = v end
Nock.db.profile.hudMode = "react"
Nock.db.profile.reactBuffDisabled = {}

local painted = {}
Nock.UI = {
  CreateReactSlot = function(parent, name) return Stub.CreateFrame("Frame", name, parent) end,
  PaintReactSlot  = function(slot, item) painted[#painted + 1] = { icon = item.icon, label = item.label, desat = item.desat } end,
  ApplyBackdrop   = function() end,
  RegisterNudgeable = function() end,
  SetReactSlotSize = function() end,
}
Nock.parentFrame = Stub.CreateFrame("Frame")

dofile("UI/Frame_ReactBuffs.lua")
local RB = Nock.modules.ReactBuffs
RB:OnInitialize()
RB:OnEnable()
RB._grpAt = 0

local st = Nock.state
st.player.inCombat = false
st.target.rangeZone = nil
st.totems = { windfury = { present = false } }

local function refresh()
  for i = #painted, 1, -1 do painted[i] = nil end
  RB:Refresh(st)
  return painted
end
local function labels()
  local out = {}
  for i, p in ipairs(painted) do out[i] = p.label or p.icon end
  return table.concat(out, ",")
end

--------------------------------------------------------------------------------
-- 1. Frenzy on the pet is a slot; the reactBuffDisabled.frenzy key hides it.
--------------------------------------------------------------------------------
petBuffs = { { name = "Frenzy", id = 19615 } }
refresh()
ok(#painted == 1 and painted[1].icon == "icon-Frenzy", "pet Frenzy -> one slot (" .. labels() .. ")")
Nock.db.profile.reactBuffDisabled.frenzy = true
refresh()
ok(#painted == 0, "frenzy disabled -> no slot")
Nock.db.profile.reactBuffDisabled.frenzy = nil
-- By id, under another name (locale / rank quirk).
petBuffs = { { name = "Frenzy Effect", id = 19615 } }
refresh()
ok(#painted == 1, "Frenzy matched by id when the name differs")
petBuffs = {}
petExists = false
refresh()
ok(#painted == 0, "no pet -> nothing")
petExists = true

--------------------------------------------------------------------------------
-- 2. MOVE IN: target out of Auto Shot range -> desaturated Auto Shot + label.
--------------------------------------------------------------------------------
st.target.rangeZone = "OUT"
refresh()
ok(#painted == 1 and painted[1].label == "MOVE IN" and painted[1].desat == true,
   "rangeZone OUT -> MOVE IN slot (" .. labels() .. ")")
ok(painted[1] and painted[1].icon == "icon-75", "MOVE IN wears the Auto Shot icon")
st.target.rangeZone = "SWEET"
refresh()
ok(#painted == 0, "in range -> no alert")
st.target.rangeZone = "OUT"
targetDead = true
refresh()
ok(#painted == 0, "dead target -> no alert")
targetDead = false
targetAttackable = false
refresh()
ok(#painted == 0, "friendly target -> no alert")
targetAttackable = true
targetExists = false
refresh()
ok(#painted == 0, "no target -> no alert")
targetExists = true
Nock.db.profile.reactBuffDisabled.movein = true
refresh()
ok(#painted == 0, "movein disabled -> no alert")
Nock.db.profile.reactBuffDisabled.movein = nil
-- Out of combat too (a dummy from too far away).
st.player.inCombat = false
refresh()
ok(#painted == 1 and painted[1].label == "MOVE IN", "MOVE IN shows out of combat")
st.target.rangeZone = nil

--------------------------------------------------------------------------------
-- 3. Order under a full house: alert, WF, pet first; player procs fill the rest.
--------------------------------------------------------------------------------
st.target.rangeZone = "OUT"
st.totems.windfury = { present = true, icon = "icon-WF", expirationTime = 1010, duration = 10 }
petBuffs = { { name = "Frenzy", id = 19615 } }
-- Ten important player procs: enough on their own to fill the row.
playerBuffs = {}
for _, id in ipairs({ 2825, 35476, 3045, 6150, 34692, 28507, 20572, 35166, 33649, 33807 }) do
  playerBuffs[#playerBuffs + 1] = { name = "Proc" .. id, id = id, icon = "proc-" .. id }
end
refresh()
ok(#painted == 10, "row caps at 10 (" .. #painted .. ")")
ok(painted[1].label == "MOVE IN", "slot 1 = MOVE IN")
ok(painted[2].icon == "icon-WF", "slot 2 = Windfury")
ok(painted[3].icon == "icon-Frenzy", "slot 3 = pet Frenzy")
local procs = 0
for i = 4, #painted do if painted[i].icon:sub(1, 5) == "proc-" then procs = procs + 1 end end
ok(procs == 7, "the remaining 7 slots are player procs (dropped: 3 procs, no alert)")

-- With the alert gone the procs get the room back, WF still ahead of them.
st.target.rangeZone = nil
refresh()
ok(painted[1].icon == "icon-WF" and painted[2].icon == "icon-Frenzy", "no alert: WF, Frenzy, then procs")

--------------------------------------------------------------------------------
-- 4. Frenzy alert mode: on a boss target the slot is fixed — up, greyed, then
--    MISSING after the grace; elsewhere present-only; talent and pet gates.
--------------------------------------------------------------------------------
playerBuffs, petBuffs = {}, {}
st.totems.windfury = { present = false }
st.target.rangeZone = nil
local now = 1000
_G.GetTime = function() return now end
local bossTarget = false
_G.UnitClassification = function() return bossTarget and "worldboss" or "normal" end
-- Core/Core.lua (not loaded here) owns Nock.IsBossTarget; same rule, stubbed.
Nock.IsBossTarget = function()
  return UnitExists("target") and UnitCanAttack("player", "target")
     and not UnitIsDead("target") and UnitClassification("target") == "worldboss"
end
_G.UnitLevel = function() return 70 end
_G.UnitIsDead = function() return false end
local frenzyRank = 5
_G.GetNumTalents = function(tab) return tab == 1 and 3 or 0 end
_G.GetTalentInfo = function(tab, i)
  if tab == 1 and i == 2 then return "Frenzy", nil, nil, nil, frenzyRank end
  return "Other", nil, nil, nil, 0
end
NAMES[19621] = "Frenzy"
Nock.db.profile.reactBuffFrenzyMode = "boss"
RB:RefreshTalents()
ok(RB._frenzyTalented == true, "Frenzy talent read from the BM tab")

-- Boss, in combat, Frenzy down: greyed slot, no label until the grace passes.
st.player.inCombat = true
bossTarget = true
refresh()
ok(#painted == 1 and painted[1].desat == true and painted[1].label == nil,
   "boss + down: greyed slot, no label inside the grace (" .. labels() .. ")")
now = 1002.5
refresh()
ok(#painted == 1 and painted[1].label == "MISSING", "down past 2 s -> MISSING")
-- Frenzy comes up: bright, and it stays in the FIRST slot ahead of the procs.
petBuffs = { { name = "Frenzy", id = 19615 } }
playerBuffs = { { name = "Proc2825", id = 2825, icon = "proc-2825" } }
refresh()
ok(#painted == 2 and painted[1].icon == "icon-Frenzy" and painted[1].desat == false and painted[1].label == nil,
   "boss + up: bright Frenzy in slot 1, proc after (" .. labels() .. ")")
-- Drops again: the grace restarts from the drop.
petBuffs = {}
now = 1010
refresh()
ok(painted[1].desat == true and painted[1].label == nil, "fresh drop -> greyed, grace restarted")
now = 1013
refresh()
ok(painted[1].label == "MISSING", "MISSING again after the grace")

-- Not a boss: present-only (nothing while down, a slot while up).
bossTarget = false
refresh()
ok(#painted == 1 and painted[1].icon == "proc-2825", "trash + down: no Frenzy slot")
petBuffs = { { name = "Frenzy", id = 19615 } }
refresh()
ok(#painted == 2, "trash + up: Frenzy shows as a plain buff")
petBuffs = {}

-- Out of combat on a boss: nothing.
bossTarget = true
st.player.inCombat = false
refresh()
ok(#painted == 1, "boss but out of combat: no alert slot")
st.player.inCombat = true

-- Untalented: never the alert (a non-BM hunter would see a permanent grey).
frenzyRank = 0
RB:RefreshTalents()
refresh()
ok(#painted == 1, "untalented: no alert slot")
frenzyRank = 5
RB:RefreshTalents()

-- Modes: "up" = never the alert; "missing" = the alert on trash too.
Nock.db.profile.reactBuffFrenzyMode = "up"
refresh()
ok(#painted == 1, "mode up: no alert on a boss")
Nock.db.profile.reactBuffFrenzyMode = "missing"
bossTarget = false
refresh()
ok(#painted == 2 and painted[1].desat == true, "mode missing: the alert on trash")
Nock.db.profile.reactBuffFrenzyMode = "boss"

-- The hide toggle wins over every mode.
bossTarget = true
Nock.db.profile.reactBuffDisabled.frenzy = true
refresh()
ok(#painted == 1, "frenzy hidden: no alert slot")
Nock.db.profile.reactBuffDisabled.frenzy = nil

-- Dead pet: nothing to alert about.
_G.UnitIsDead = function(u) return u == "pet" end
refresh()
ok(#painted == 1, "dead pet: no alert slot")
_G.UnitIsDead = function() return false end
ok(Nock.Defaults.profile.reactBuffFrenzyMode == "boss", "ships in boss mode")

print(("react_buffs_row_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
