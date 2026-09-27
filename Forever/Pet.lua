-- Forever/Pet.lua
-- The pet as state: presence, death, happiness and the Lone Wolf talent, published to state.pet for every reader.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Pet = Nock:NewModule("ForeverPet", "AceEvent-3.0")

Pet.refreshInterval = 0.1

local function P(v) return Nock.Flavor.Plain(v) end

-- Lone Wolf talented? Forever's talents are the retail-style trait tree
-- (C_ClassTalents + C_Traits; the classic talent APIs answer nothing here,
-- probed 2026-09-26): the active loadout's node holding the talent's spell
-- id, rank > 0. The spellbook and an aura on you are the fallbacks. Talents
-- only change out of combat, so the answer is read out of combat (at most
-- every LONE_WOLF_RECHECK seconds) and held through a fight. `how` names the
-- path that matched, for `/nock probe lonewolf`.
local LONE_WOLF_RECHECK = 5
function Pet.LoneWolfFrom(id, traitRank, spellKnown, auraBySpell)
  if type(id) ~= "number" then return false end
  local r = traitRank and traitRank(id)
  if type(r) == "number" and r > 0 then return true, "talent" end
  if spellKnown and spellKnown(id) == true then return true, "spellbook" end
  if auraBySpell and auraBySpell(id) then return true, "aura" end
  return false
end

-- The rank of the active loadout's node whose entry is `spellID`. The node
-- is found once per loadout (a 50-node walk) and then read directly.
local traitNode = { config = nil, node = nil }
function Pet.TraitRank(spellID, CT, T)
  if not (CT and CT.GetActiveConfigID and T and T.GetConfigInfo and T.GetTreeNodes and T.GetNodeInfo
          and T.GetEntryInfo and T.GetDefinitionInfo) then return nil end
  local okc, config = pcall(CT.GetActiveConfigID)
  if not okc or not config then return nil end
  if traitNode.config ~= config then
    traitNode.config, traitNode.node = config, nil
    local oki, info = pcall(T.GetConfigInfo, config)
    for _, tree in ipairs(oki and type(info) == "table" and info.treeIDs or {}) do
      local okn, nodes = pcall(T.GetTreeNodes, tree)
      for _, nodeID in ipairs(okn and type(nodes) == "table" and nodes or {}) do
        local okd, node = pcall(T.GetNodeInfo, config, nodeID)
        for _, entryID in ipairs(okd and type(node) == "table" and node.entryIDs or {}) do
          local oke, entry = pcall(T.GetEntryInfo, config, entryID)
          local def = oke and type(entry) == "table" and entry.definitionID
          local okf, d = false, nil
          if def then okf, d = pcall(T.GetDefinitionInfo, def) end
          if okf and type(d) == "table" and d.spellID == spellID then traitNode.node = nodeID end
        end
        if traitNode.node then break end
      end
      if traitNode.node then break end
    end
  end
  if not traitNode.node then return nil end
  local okr, node = pcall(T.GetNodeInfo, config, traitNode.node)
  return okr and type(node) == "table" and P(node.activeRank) or nil
end
function Pet.ResetTraitCache() traitNode.config, traitNode.node = nil, nil end

function Pet:LoneWolf(inCombat)
  local now = GetTime()
  if inCombat or (self._loneWolfAt and now - self._loneWolfAt < LONE_WOLF_RECHECK) then
    return self._loneWolf == true
  end
  self._loneWolfAt = now
  local AC, SB = Nock.AuraCache, _G.C_SpellBook
  self._loneWolf, self._loneWolfHow = Pet.LoneWolfFrom(Nock.Spells.LONE_WOLF,
    function(id) return Pet.TraitRank(id, _G.C_ClassTalents, _G.C_Traits) end,
    SB and SB.IsSpellKnown and function(id) local okk, k = pcall(SB.IsSpellKnown, id); return okk and k end,
    AC and AC.BySpell and function(id) return AC.BySpell("player", id) end)
  return self._loneWolf == true
end

-- Phase 1b recorder: every tier change with enough context to learn, later,
-- how fast happiness decays on Forever and whether it runs while offline or
-- dismissed. Per character, 50 entries, read with `/nock pet log`.
local LOG_MAX = 50

function Pet:OnEnable()
  self._loginAt = time()
  self:RegisterEvent("PLAYER_LOGOUT")
end

function Pet:PLAYER_LOGOUT()
  local c = Nock.db and Nock.db.char
  if c then c.petHappinessLogoutAt = time() end
end

-- The last tier read and when, saved per character: a change is measured
-- against it, so a dismiss, a death or a logout in between still counts.
local function lastKnown()
  local c = Nock.db and Nock.db.char
  if not c then return nil end
  if type(c.petHappinessLast) ~= "table" then c.petHappinessLast = {} end
  return c.petHappinessLast
end

local function logTable()
  local c = Nock.db and Nock.db.char
  if not c then return nil end
  c.petHappinessLog = c.petHappinessLog or {}
  return c.petHappinessLog
end

-- via: "live" (read continuously), "dismiss" (no reading for a while this
-- session: dismissed, dead or mid-summon) or "login" (first reading since
-- login/reload); gap = seconds since the last reading of `from`.
function Pet:OnHappinessChange(from, to, state, via, gap)
  local log = logTable()
  if not log then return end
  local t = time()
  log[#log + 1] = {
    at = t, gt = GetTime(), from = from, to = to,
    combat = state.player and state.player.inCombat == true or false,
    sinceLogin = self._loginAt and (t - self._loginAt) or nil,
    sinceSummon = self._summonAt and (t - self._summonAt) or nil,
    lastDismissAgo = self._dismissAt and (t - self._dismissAt) or nil,
    via = via, gap = gap,
    logoutAgo = (via == "login" and Nock.db.char.petHappinessLogoutAt) and (t - Nock.db.char.petHappinessLogoutAt) or nil,
  }
  while #log > LOG_MAX do table.remove(log, 1) end
end

function Pet:LogText()
  local log = logTable() or {}
  local L = { "Nock pet happiness log (1 Unhappy, 2 Content, 3 Happy), oldest first:" }
  for i = 1, #log do
    local e = log[i]
    L[#L + 1] = ("%s  %d > %d  via=%s gap=%ss  combat=%s  login+%ss  summon+%ss  dismissed %ss ago  logout %ss ago"):format(
      date("%Y-%m-%d %H:%M:%S", e.at), e.from, e.to, tostring(e.via), tostring(e.gap), tostring(e.combat),
      tostring(e.sinceLogin), tostring(e.sinceSummon), tostring(e.lastDismissAgo), tostring(e.logoutAgo))
  end
  if #log == 0 then L[#L + 1] = "(no tier changes recorded yet)" end
  return table.concat(L, "\n")
end

function Pet:ShowLog()
  local text = self:LogText()
  if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
end

function Pet:Refresh(state)
  local pet = state.pet
  if not pet then return end
  local exists = P(_G.UnitExists and UnitExists("pet")) == true
  pet.exists = exists
  if exists ~= self._wasOut then
    if exists then self._summonAt = time() elseif self._wasOut ~= nil then self._dismissAt = time() end
    self._wasOut = exists
  end
  pet.dead = exists and P(_G.UnitIsDead and UnitIsDead("pet")) == true or false
  local h, dmg
  local PI = _G.C_PetInfo
  if exists and PI and PI.GetPetHappiness then
    local a, b = PI.GetPetHappiness()
    h, dmg = P(a), P(b)
  end
  if type(h) ~= "number" then h = nil end
  if type(dmg) ~= "number" then dmg = nil end
  local prev = pet.happiness
  pet.happiness, pet.damagePct = h, dmg
  pet.loneWolf = self:LoneWolf(state.player and state.player.inCombat == true)
  if h then
    local last = lastKnown()
    if last then
      local t = time()
      if last.tier and last.tier ~= h and self.OnHappinessChange then
        local via = prev and "live" or (self._sawKnown and "dismiss" or "login")
        self:OnHappinessChange(last.tier, h, state, via, last.at and (t - last.at) or nil)
      end
      last.tier, last.at = h, t
    end
    self._sawKnown = true
  end
end
