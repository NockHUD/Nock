-- Tests/forever_snapshot_test.lua
-- Forever/Snapshot.lua: restriction events -> state.restrict, Nock.Restricted,
-- snapshot on PLAYER_REGEN_DISABLED and on the Activating event, rescan on
-- regen. Run from the repo root: luajit Tests/forever_snapshot_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

_G.GetTime = function() return 1000 end
_G.GetRangedHaste = function() return 0 end
_G.Enum = {
  AddOnRestrictionType  = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
  AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
}
local secretAuras, secretCds = false, false
_G.C_Secrets = { ShouldAurasBeSecret = function() return secretAuras end, ShouldCooldownsBeSecret = function() return secretCds end }
_G.C_RestrictedActions = { IsAddOnRestrictionActive = function() return false end }
_G.UnitAttackSpeed = function() return 1.6 end
_G.UnitRangedDamage = function() return 2.091 end

local Nock = { Flavor = { forever = true, Plain = function(v) if v == "SECRET" then return nil end return v end }, API = {} }
local module, sent = nil, {}
function Nock:NewModule(name) module = { name = name, events = {}, msgs = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function module:SendMessage(m, ...) sent[#sent + 1] = { m, ... } end
  return module end
function Nock:GetModule() return nil end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
local S = dofile("Forever/Snapshot.lua")

ok(module and module.name == "ForeverSnapshot", "module ForeverSnapshot")
local st = Nock.state
ok(type(st.restrict) == "table" and st.restrict.combat == false and st.restrict.map == false, "state.restrict declared")

-- Classify is pure.
local kind, active = S.Classify(0, 1)
ok(kind == "combat" and active == true, "Combat Activating classifies active")
kind, active = S.Classify(4, 2)
ok(kind == "map" and active == true, "Map Active")
kind, active = S.Classify(5, 0)
ok(kind == "chat" and active == false, "Chat Inactive")
ok(S.Classify(99, 2) == nil, "unknown type -> nil")

module:OnEnable()
local function fire(ev, ...) local h = module.events[ev]; module[type(h) == "string" and h or ev](module, ev, ...) end
ok(module.events["ADDON_RESTRICTION_STATE_CHANGED"] and module.events["PLAYER_REGEN_DISABLED"] and module.events["PLAYER_REGEN_ENABLED"], "events registered")

-- Combat activating: restrict.combat true, snapshot sent with reason "activating".
fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
ok(st.restrict.combat == true, "combat flag set on Activating")
ok(sent[#sent] and sent[#sent][1] == "NOCK_SNAPSHOT" and sent[#sent][2] == "activating", "snapshot broadcast on Activating")
ok(Nock.Restricted("combat") == true, "Nock.Restricted reads state")
-- Attack speeds were cached while plain.
ok(st.ranged.swingDuration == 2.091 and st.melee.swingDuration == 1.6, "attack speeds cached from the snapshot")

-- Regen disabled also snapshots (whichever comes first).
sent = {}
fire("PLAYER_REGEN_DISABLED")
ok(sent[#sent] and sent[#sent][1] == "NOCK_SNAPSHOT" and sent[#sent][2] == "regen", "snapshot broadcast on regen disabled")

-- Secret readings never reach state.
_G.UnitRangedDamage = function() return "SECRET" end
st.ranged.swingDuration = 2.091
fire("PLAYER_REGEN_DISABLED")
ok(st.ranged.swingDuration == 2.091, "a secret attack speed is ignored")

-- Map active/inactive and Encounter.
fire("ADDON_RESTRICTION_STATE_CHANGED", 4, 2); ok(st.restrict.map == true, "map active")
fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 2); ok(st.restrict.encounter == true, "encounter active")
fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0); ok(st.restrict.encounter == false, "encounter inactive")

-- Leaving combat: flag cleared, rescan broadcast.
sent = {}
fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
ok(st.restrict.combat == false, "combat flag cleared")
fire("PLAYER_REGEN_ENABLED")
ok(sent[#sent] and sent[#sent][1] == "NOCK_RESCAN", "rescan broadcast on regen enabled")

-- Secret predicates route through Nock.Restricted.
secretAuras = true
ok(Nock.Restricted("auras") == true and Nock.Restricted("cooldowns") == false, "aura/cooldown predicates")

print(("forever_snapshot: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
