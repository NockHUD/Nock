-- Tests/pvp_mode_test.lua
-- PvP mode: the one reading (Nock.PvPActive), the hide switches, the class-set diff, the debuff tracker's PvP set +
-- class filter, the aggro gate, the muted-warning list and the bad-trinket carve-out for the PvP trinket family.
-- Run from the repo root: luajit Tests/pvp_mode_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- ---- Core/State.lua: PvPActive / PvPHides / ClassSetChanged
local addon = { Constants = {}, state = {} }
local module
function addon:NewModule(name) module = { name = name }; return module end
_G.LibStub = function(name, silent)
  if name == "AceAddon-3.0" then return { GetAddon = function() return addon end } end
  if silent then return nil end
  return {}
end
dofile("Core/Constants.lua")
dofile("Core/State.lua")
local Nock = addon
ok(Nock.state.player.pvp == false, "state.player.pvp starts false")
ok(type(Nock.state.group) == "table" and type(Nock.state.group.classes) == "table", "state.group.classes exists")

ok(Nock.PvPActive({ pvpMode = "off" }, "pvp", true) == false, "off: never active, even in a battleground")
ok(Nock.PvPActive({ pvpMode = "on" }, "none", false) == true, "on: active anywhere")
ok(Nock.PvPActive({ pvpMode = "auto" }, "pvp", false) == true, "auto: a battleground")
ok(Nock.PvPActive({ pvpMode = "auto" }, "arena", false) == true, "auto: an arena")
ok(Nock.PvPActive({ pvpMode = "auto" }, "raid", true) == false, "auto: a raid is not PvP, flag or not")
ok(Nock.PvPActive({ pvpMode = "auto" }, "none", true) == false, "auto: world flag ignored by default")
ok(Nock.PvPActive({ pvpMode = "auto", pvpAutoWorldFlag = true }, "none", true) == true, "auto + world flag switch: flagged counts")
ok(Nock.PvPActive({ pvpMode = "auto", pvpAutoWorldFlag = true }, "none", false) == false, "auto + world flag switch: unflagged does not")
ok(Nock.PvPActive({}, "pvp", true) == false, "no setting = off")

ok(Nock.PvPHides({ pvpHideMisdirect = true }, "pvpHideMisdirect", true) == true, "hides: active + switch on")
ok(Nock.PvPHides({ pvpHideMisdirect = true }, "pvpHideMisdirect", false) == false, "hides: not active")
ok(Nock.PvPHides({ pvpHideMisdirect = false }, "pvpHideMisdirect", true) == false, "hides: switch off")
Nock.state.player.pvp = true
ok(Nock.PvPHides({ pvpNoAggro = true }, "pvpNoAggro") == true, "hides: reads state.player.pvp when not given")
Nock.state.player.pvp = false
ok(Nock.PvPHides({ pvpNoAggro = true }, "pvpNoAggro") == false, "hides: state off")

ok(Nock.ClassSetChanged({}, {}) == false, "class set: empty -> empty unchanged")
ok(Nock.ClassSetChanged({ HUNTER = true }, { HUNTER = true }) == false, "class set: same set unchanged")
ok(Nock.ClassSetChanged({ HUNTER = true }, { HUNTER = true, WARRIOR = true }) == true, "class set: a class joined")
ok(Nock.ClassSetChanged({ HUNTER = true, WARRIOR = true }, { HUNTER = true }) == true, "class set: a class left")

-- ---- Modules/DebuffTracker.lua: the PvP set, the class filter, the forced tracker
_G.UnitExists = function(u) return u == "target" end
_G.UnitDebuff = function() return nil end
_G.GetSpellInfo = function(id) return "Spell " .. id, nil, "icon-" .. id end
dofile("Config/Defaults.lua")
addon.db = { profile = {} }
for k, v in pairs(addon.Defaults.profile) do addon.db.profile[k] = v end
local p = addon.db.profile
p.debuffTrackerDisabled = {}; p.debuffTrackerOrder = {}; p.debuffTrackerCustom = ""; p.pvpDebuffDisabled = {}
dofile("Core/AuraCache.lua")
dofile("Modules/DebuffTracker.lua")
local DT = module
local function keysOf(list) local out = {}; for i, e in ipairs(list) do out[i] = e.key end; return table.concat(out, ",") end
local function has(list, key) for _, e in ipairs(list) do if e.key == key then return true end end; return false end

local C = addon.Constants
local byKey = {}
for _, e in ipairs(C.DEBUFF_CURATED) do byKey[e.key] = e end
ok(byKey.serpent and byKey.serpent.defaultOff and byKey.scorpidPoison and byKey.scorpidPoison.defaultOff, "Serpent Sting + Scorpid Poison are curated, off by default outside PvP")
local allTagged = true
for _, e in ipairs(C.DEBUFF_CURATED) do if type(e.classes) ~= "table" or #e.classes == 0 then allTagged = false end end
ok(allTagged, "every curated debuff carries its class tag")

ok(DT.ClassAllowed({ key = "x" }, {}) == true, "class filter: an untagged (custom) entry always passes")
ok(DT.ClassAllowed(byKey.creck, { HUNTER = true }) == false, "class filter: Curse of Recklessness needs a warlock")
ok(DT.ClassAllowed(byKey.creck, { HUNTER = true, WARLOCK = true }) == true, "class filter: warlock present")
ok(DT.ClassAllowed(byKey.armorshred, { ROGUE = true }) == true, "class filter: Sunder/Expose passes on either class")
ok(DT.ClassAllowed(byKey.hmark, nil) == false, "class filter: no roster yet -> only untagged")

-- outside PvP mode the normal set rules (serpent off by default)
addon.state.player.pvp = false
DT.InvalidateCatalog()
p.debuffTrackerEnabled = true
DT:Refresh(addon.state)
local outside = addon.state.debufftracker
ok(has(outside, "hmark") and not has(outside, "serpent") and not has(outside, "scorpidPoison"), "outside PvP: the normal set, stings off")
ok(has(outside, "jow") and has(outside, "creck") and not has(outside, "mstrike") and not has(outside, "wingclip") and not has(outside, "curse"), "outside PvP: raid debuffs in, PvP-only ones never")
ok(byKey.serpent.names[2] == "Viper Sting" and byKey.serpent.spellIds[1] == 3034, "Serpent / Viper share one slot, Viper's icon")
ok(byKey.curse and #byKey.curse.names == 5 and byKey.curse.pvpOnly, "the PvP curse slot watches Tongues, Exhaustion, Recklessness, Elements and Weakness")
ok(byKey.mageslow and #byKey.mageslow.names >= 4 and byKey.snare and #byKey.snare.classes == 4, "one mage-slow slot, one cross-class snare slot")
ok(DT.ClassAllowed(byKey.snare, { SHAMAN = true }) and not DT.ClassAllowed(byKey.snare, { PRIEST = true }), "the snare slot passes on any of its four classes")

-- inside: every curated entry on by default, filtered by the classes around you
addon.state.player.pvp = true
addon.state.group.classes = { HUNTER = true }
p.pvpDebuffPartyFilter = true
DT.InvalidateCatalog()
DT:Refresh(addon.state)
local inside = addon.state.debufftracker
ok(has(inside, "serpent") and has(inside, "scorpidPoison") and has(inside, "hmark") and has(inside, "wingclip") and has(inside, "aimed") and has(inside, "wyvern"), "PvP: the hunter debuffs are on")
ok(not has(inside, "scorpid") and not has(inside, "jow") and not has(inside, "bfrenzy") and not has(inside, "creck") and not has(inside, "ew"), "PvP: Scorpid Sting, Expose Weakness, Wisdom, Blood Frenzy and the raid CoR entry stay out of the PvP set")
ok(not has(inside, "curse") and not has(inside, "justice") and not has(inside, "ff") and not has(inside, "mstrike"), "PvP: nobody here can apply a curse, a judgement, Faerie Fire or Mortal Strike -> filtered out")
addon.state.group.classes = { HUNTER = true, WARLOCK = true }
DT.InvalidateCatalog()
DT:Refresh(addon.state)
ok(has(addon.state.debufftracker, "curse"), "PvP: a warlock joins -> the curse slot shows")
p.pvpDebuffPartyFilter = false
DT.InvalidateCatalog()
DT:Refresh(addon.state)
ok(has(addon.state.debufftracker, "justice") and has(addon.state.debufftracker, "mstrike") and has(addon.state.debufftracker, "hamstring") and has(addon.state.debufftracker, "mageslow") and has(addon.state.debufftracker, "wound") and has(addon.state.debufftracker, "wchill") and not has(addon.state.debufftracker, "jow"), "PvP: filter off -> the whole PvP set shows, Wisdom still not")
p.pvpDebuffDisabled = { serpent = true }
DT.InvalidateCatalog()
DT:Refresh(addon.state)
ok(not has(addon.state.debufftracker, "serpent") and has(addon.state.debufftracker, "scorpidPoison"), "PvP: its own tri-state set (serpent off there only)")
ok(DT.IsEntryEnabled("serpent") == false, "the normal set is untouched by the PvP edit")
p.pvpDebuffDisabled = {}
-- the tracker itself: off in general, PvP mode shows it anyway
p.debuffTrackerEnabled = false
p.pvpShowDebuffTracker = true
DT.InvalidateCatalog()
DT:Refresh(addon.state)
ok(#addon.state.debufftracker > 0, "PvP: pvpShowDebuffTracker runs the engine while the tracker is off in general")
p.pvpShowDebuffTracker = false
DT.InvalidateCatalog()
DT:Refresh(addon.state)
ok(#addon.state.debufftracker == 0, "PvP: with that off, an off tracker stays off")
addon.state.player.pvp = false
p.debuffTrackerEnabled = true

-- ---- the muted-warning list + the trinket family
ok(type(C.PVP_MUTED_WARNINGS) == "table" and C.PVP_MUTED_WARNINGS.drums and C.PVP_MUTED_WARNINGS.lustcds
   and C.PVP_MUTED_WARNINGS.sapperAoe and C.PVP_MUTED_WARNINGS.devilsaur and C.PVP_MUTED_WARNINGS.karaborNeck
   and C.PVP_MUTED_WARNINGS.shirtGate and C.PVP_MUTED_WARNINGS.noRelease and C.PVP_MUTED_WARNINGS.bossMark
   and C.PVP_MUTED_WARNINGS.slammer and C.PVP_MUTED_WARNINGS.ripper, "the muted list names the raid-only warnings")
ok(not C.PVP_MUTED_WARNINGS.wrongTrinket and not C.PVP_MUTED_WARNINGS.dazed and not C.PVP_MUTED_WARNINGS.fdResist,
   "bad trinket, dazed and FD resist are not muted")
ok(C.WRONG_TRINKET_IDS[37865] and C.WRONG_TRINKET_IDS[37864], "the PvP trinket family holds the generic medallions")

-- ---- Modules/AggroWarning.lua: the PvP gate
local Aggro
function addon:NewModule() Aggro = {}; function Aggro:RegisterEvent() end; function Aggro:RegisterMessage() end; return Aggro end
_G.GetTime = function() return 100 end
dofile("Modules/AggroWarning.lua")
ok(Aggro.Evaluate({ aggroEnabled = true, aggroGroupOnly = false }, 3, false, false) == true, "aggro: fires outside PvP")
ok(Aggro.Evaluate({ aggroEnabled = true, aggroGroupOnly = false, pvpNoAggro = true }, 3, false, true) == false, "aggro: PvP + switch -> silent")
ok(Aggro.Evaluate({ aggroEnabled = true, aggroGroupOnly = false, pvpNoAggro = false }, 3, false, true) == true, "aggro: PvP with the switch off -> still fires")

-- ---- the weave macro strip is the existing WithoutMovePad
dofile("Core/WeaveMacro.lua")
local WM = addon.WeaveMacro
local body = "/cast Raptor Strike\n/click MovePadBackward\n/startattack"
ok(not WM.HasMovePad(WM.WithoutMovePad(body)) and WM.WithoutMovePad(body):find("Raptor Strike", 1, true), "macro strip: MovePad line gone, the rest kept")

print(("pvp_mode_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
