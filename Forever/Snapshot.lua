-- Forever/Snapshot.lua
-- Restriction state (state.restrict) and the last-readable-moment snapshot:
-- attack speeds and tracked cooldowns are read while still plain, then the
-- ledger runs on its own numbers until regen returns.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Snapshot = Nock:NewModule("ForeverSnapshot", "AceEvent-3.0")
Nock.ForeverSnapshot = Snapshot

-- Enum.AddOnRestrictionType values when the client provides them, the
-- 2026-09-21 measured numbers otherwise (Combat fired as type 0).
local FALLBACK = { [0] = "combat", [1] = "encounter", [2] = "challenge", [3] = "pvp", [4] = "map", [5] = "chat" }
local NAMES = { Combat = "combat", Encounter = "encounter", ChallengeMode = "challenge",
                PvPMatch = "pvp", Map = "map", Chat = "chat" }

local function typeMap()
  local E = _G.Enum and _G.Enum.AddOnRestrictionType
  if not E then return FALLBACK end
  local m = {}
  for name, kind in pairs(NAMES) do
    if E[name] ~= nil then m[E[name]] = kind end
  end
  return m
end

-- Pure: (type, state) -> kind, active. Activating counts as active: it is
-- the last moment the getters still read, so the snapshot runs on it.
function Snapshot.Classify(t, stateVal)
  local kind = typeMap()[t]
  if not kind then return nil end
  local ES = _G.Enum and _G.Enum.AddOnRestrictionState
  local inactive = ES and ES.Inactive or 0
  return kind, stateVal ~= inactive
end

-- THE read of a restriction for views and modules.
function Nock.Restricted(kind)
  local S = _G.C_Secrets
  if kind == "auras"     then return (S and S.ShouldAurasBeSecret     and S.ShouldAurasBeSecret())     or false end
  if kind == "cooldowns" then return (S and S.ShouldCooldownsBeSecret and S.ShouldCooldownsBeSecret()) or false end
  if kind == "stats"     then return Nock.state.restrict.combat end
  return Nock.state.restrict[kind] or false
end

function Snapshot:OnEnable()
  self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Snapshot:ADDON_RESTRICTION_STATE_CHANGED(event, t, stateVal)
  local kind, active = Snapshot.Classify(t, stateVal)
  if not kind then return end
  if Nock.state.restrict[kind] ~= nil then Nock.state.restrict[kind] = active end
  if kind == "combat" and active then self:Snapshot("activating") end
end

function Snapshot:PLAYER_REGEN_DISABLED()
  self:Snapshot("regen")
end

function Snapshot:PLAYER_REGEN_ENABLED()
  self:Rescan()
end

-- Attack speeds: plain out of combat, secret in it. Cached here so the tick
-- and the bars never read them live on Forever.
local function cacheSpeeds()
  local Plain = Nock.Flavor.Plain
  local ranged = Plain(UnitRangedDamage and UnitRangedDamage("player"))
  if type(ranged) == "number" and ranged > 0 then Nock.state.ranged.swingDuration = ranged end
  local melee = Plain(UnitAttackSpeed and UnitAttackSpeed("player"))
  if type(melee) == "number" and melee > 0 then Nock.state.melee.swingDuration = melee end
end

function Snapshot:Snapshot(reason)
  cacheSpeeds()
  self:SendMessage("NOCK_SNAPSHOT", reason)
end

function Snapshot:Rescan()
  cacheSpeeds()
  self:SendMessage("NOCK_RESCAN")
end

return Snapshot
