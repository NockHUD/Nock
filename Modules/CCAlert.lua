-- Modules/CCAlert.lua
-- PvP mode's incoming-CC alert: a hostile you can see starts casting Fear / Polymorph / ... at you -> state.ccAlert + a sound, so you can Feign Death.
--
-- Cast starts only: once the crowd control lands there is nothing left to
-- press, so the aura landing is deliberately not an alert. Watched units are
-- your target, your focus, the arena frames and the nameplates; a cast counts
-- when its caster targets you (pvpCcOnlyAtYou, default) or, with that off,
-- whenever a hostile in view casts it. Built-in spells (C.PVP_CC_CASTS) each
-- have a switch; custom lines add "Spell name = Sound" pairs. The warning
-- square is drawn by Modules/Warnings.lua from state.ccAlert; this module
-- owns detection, expiry and the cue.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local CCAlert = Nock:NewModule("CCAlert", "AceEvent-3.0")
local C = Nock.Constants

local function profile()
  return Nock.db and Nock.db.profile or nil
end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    if type(info) == "table" then return info.name end
    return info
  end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- ---------------------------------------------------------------------------
-- Pure helpers (Tests/cc_alert_test.lua)
-- ---------------------------------------------------------------------------

-- Your own spells (profile.pvpCcCustom: { spell = name|id, sound, enabled })
-- as match entries { name=|id=, sound= }; a switched-off line is left out.
function CCAlert.CustomEntries(list)
  local out = {}
  for _, c in ipairs(type(list) == "table" and list or {}) do
    if c.enabled ~= false and c.spell ~= nil and c.spell ~= "" then
      local e = { sound = c.sound }
      local id = tonumber(c.spell)
      if id then e.id = id else e.name = tostring(c.spell) end
      out[#out + 1] = e
    end
  end
  return out
end

-- The entry a cast matches: built-ins first (each behind its pvpCc_<key>
-- switch, matched by resolved name or any of its ids), then the customs.
function CCAlert.Match(p, name, spellId, builtins, customs)
  for _, e in ipairs(builtins or {}) do
    if not (p and p["pvpCc_" .. e.key] == false) then
      if (e.name and name == e.name) or (spellId and e.idSet and e.idSet[spellId]) then return e end
    end
  end
  for _, c in ipairs(customs or {}) do
    if (c.id and c.id == spellId) or (c.name and c.name == name) then return c end
  end
  return nil
end

-- Which units this module listens to.
function CCAlert.UnitWatched(unit)
  if unit == "target" or unit == "focus" then return true end
  local pre = unit and unit:match("^(%a+)%d+$")
  return pre == "arena" or pre == "nameplate"
end

-- The cue: a built-in's pvpCc_<key>_sound, a custom line's own sound, "Phone"
-- when unset; "None" is silent, and so is a name LibSharedMedia does not know
-- (the default "Phone" is WeakAuras' registration: without WeakAuras there is
-- simply no sound). `env` stands in for the client in tests: lsmPath(name) ->
-- path|nil, playFile(path).
function CCAlert.PlayCue(p, entry, env)
  local name
  if entry and entry.key then name = p and p["pvpCc_" .. entry.key .. "_sound"] or nil
  elseif entry then name = entry.sound end
  name = name or "Phone"
  if name == "" or name == "None" then return nil end
  local path = env.lsmPath(name)
  if path then env.playFile(path); return "file" end
  return nil
end

local function realEnv()
  return {
    lsmPath = function(name)
      local LSM = LibStub("LibSharedMedia-3.0", true)
      return LSM and LSM:Fetch("sound", name, true) or nil
    end,
    playFile = function(path) if PlaySoundFile then pcall(PlaySoundFile, path, "Master") end end,
  }
end

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------
local function active()
  local p = profile()
  local st = Nock.state and Nock.state.player
  return p ~= nil and p.pvpCcEnabled ~= false and st ~= nil and st.pvp == true
end

function CCAlert:Builtins()
  if self._builtins then return self._builtins end
  local list = {}
  for _, e in ipairs(C.PVP_CC_CASTS or {}) do
    local b = { key = e.key, label = e.label, name = spellName(e.ids[1]) or e.label, idSet = {} }
    for _, id in ipairs(e.ids) do b.idSet[id] = true end
    list[#list + 1] = b
  end
  self._builtins = list
  return list
end

function CCAlert:Customs()
  if not self._customs then
    local p = profile()
    self._customs = CCAlert.CustomEntries(p and p.pvpCcCustom)
  end
  return self._customs
end

function CCAlert:InvalidateCatalog()
  self._builtins = nil
  self._customs = nil
end

local function castInfo(unit, channel)
  if channel then
    if not UnitChannelInfo then return nil end
    local name, _, texture, startMS, endMS, _, _, spellId = UnitChannelInfo(unit)
    return name, texture, startMS, endMS, spellId
  end
  if not UnitCastingInfo then return nil end
  local name, _, texture, startMS, endMS, _, _, _, spellId = UnitCastingInfo(unit)
  return name, texture, startMS, endMS, spellId
end

function CCAlert:OnCastStart(event, unit)
  if not active() then return end
  if not CCAlert.UnitWatched(unit) then return end
  if not (UnitCanAttack and UnitCanAttack("player", unit)) then return end
  local p = profile()
  if p.pvpCcOnlyAtYou ~= false then
    if not (UnitIsUnit and UnitIsUnit(unit .. "target", "player")) then return end
  end
  local name, texture, startMS, endMS, spellId = castInfo(unit, event == "UNIT_SPELLCAST_CHANNEL_START")
  if not name then return end
  local entry = CCAlert.Match(p, name, spellId, self:Builtins(), self:Customs())
  if not entry then return end
  local caster = UnitGUID and UnitGUID(unit) or unit
  local startTime = (startMS or 0) / 1000
  local cur = Nock.state.ccAlert
  if cur and cur.caster == caster and cur.startTime == startTime then return end   -- the same cast seen twice (target + nameplate)
  Nock.state.ccAlert = {
    name = name, short = entry.label or name, icon = texture,
    caster = caster, startTime = startTime,
    endTime = (endMS or 0) / 1000,
  }
  CCAlert.PlayCue(p, entry, realEnv())
end

function CCAlert:OnCastEnd(_, unit)
  local cur = Nock.state.ccAlert
  if not cur then return end
  if not CCAlert.UnitWatched(unit) then return end
  local caster = UnitGUID and UnitGUID(unit) or unit
  if caster == cur.caster then Nock.state.ccAlert = nil end
end

function CCAlert:OnPvPChanged(_, on)
  if not on then Nock.state.ccAlert = nil end
end

function CCAlert:OnEnable()
  self:RegisterEvent("UNIT_SPELLCAST_START", "OnCastStart")
  self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "OnCastStart")
  self:RegisterEvent("UNIT_SPELLCAST_STOP", "OnCastEnd")
  self:RegisterEvent("UNIT_SPELLCAST_FAILED", "OnCastEnd")
  self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnCastEnd")
  self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnCastEnd")
  self:RegisterEvent("PLAYER_LOGIN", "InvalidateCatalog")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "InvalidateCatalog")
  self:RegisterMessage("NOCK_PVP_CHANGED", "OnPvPChanged")
end
