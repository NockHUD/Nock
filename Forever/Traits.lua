-- Forever/Traits.lua
-- The talent tree on WoW Forever (C_ClassTalents + C_Traits): one walk per loadout indexes every node by spell id and by name, then any talent's rank is a lookup.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

local function P(v) return Nock.Flavor.Plain(v) end

-- Forever's talents are the retail-style trait tree (the classic talent
-- APIs answer nothing here, probed 2026-09-26): the active loadout's tree
-- holds one node per talent, each node's entry a definition with the
-- talent's spell id (and sometimes an override name). Talents only change
-- out of combat, so callers read a rank out of combat and hold it.
local Traits = {}
Nock.Traits = Traits

-- config -> the map, rebuilt when the active loadout changes.
local cache = { config = nil, bySpell = {}, byName = {} }

local function haveApi(CT, T)
  return CT and CT.GetActiveConfigID and T and T.GetConfigInfo and T.GetTreeNodes and T.GetNodeInfo
     and T.GetEntryInfo and T.GetDefinitionInfo
end

-- The active config id, with the map built for it (one walk). nil without
-- the API or a loadout.
local function ensure(CT, T, nameOf)
  if not haveApi(CT, T) then return nil end
  local okc, config = pcall(CT.GetActiveConfigID)
  if not okc or not config then return nil end
  if cache.config == config then return config end
  cache.config, cache.bySpell, cache.byName = config, {}, {}
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
        if okf and type(d) == "table" then
          local sid = P(d.spellID)
          if type(sid) == "number" and cache.bySpell[sid] == nil then cache.bySpell[sid] = nodeID end
          local nm = P(d.overrideName)
          if type(nm) ~= "string" and sid and nameOf then nm = P(nameOf(sid)) end
          if type(nm) == "string" and cache.byName[nm] == nil then cache.byName[nm] = nodeID end
        end
      end
    end
  end
  return config
end

local function rankOf(config, nodeID, T)
  if not nodeID then return nil end
  local okr, node = pcall(T.GetNodeInfo, config, nodeID)
  return okr and type(node) == "table" and P(node.activeRank) or nil
end

-- The rank of the talent whose spell id is `spellID`: 0 untaken, nil when
-- there is no such talent or no API.
function Traits.Rank(spellID, CT, T, nameOf)
  if type(spellID) ~= "number" then return nil end
  local config = ensure(CT, T, nameOf)
  if not config then return nil end
  return rankOf(config, cache.bySpell[spellID], T)
end

-- The same by the talent's NAME (the definition's override name, else the
-- spell's name through `nameOf`): for a talent whose id is not pinned yet.
function Traits.RankByName(name, CT, T, nameOf)
  if type(name) ~= "string" or name == "" then return nil end
  local config = ensure(CT, T, nameOf)
  if not config then return nil end
  return rankOf(config, cache.byName[name], T)
end

-- Every talent whose name contains `word` (plain find), as rows
-- { name, spellID, rank }: for the probe, to pin a talent's id by name.
function Traits.Find(word, CT, T, nameOf)
  local out = {}
  if type(word) ~= "string" or word == "" then return out end
  local config = ensure(CT, T, nameOf)
  if not config then return out end
  local names = {}
  for nm in pairs(cache.byName) do names[#names + 1] = nm end
  table.sort(names)
  for _, nm in ipairs(names) do
    if nm:find(word, 1, true) then
      local nodeID = cache.byName[nm]
      local sid
      for id, node in pairs(cache.bySpell) do if node == nodeID then sid = id; break end end
      out[#out + 1] = { name = nm, spellID = sid, rank = rankOf(config, nodeID, T) }
    end
  end
  return out
end

function Traits.Reset()
  cache.config, cache.bySpell, cache.byName = nil, {}, {}
end

-- The live client's rank for a talent by id, else by name.
function Traits.LiveRank(spellID, name)
  local nameOf = Nock.API and Nock.API.SpellName
  if spellID then return Traits.Rank(spellID, _G.C_ClassTalents, _G.C_Traits, nameOf) end
  return Traits.RankByName(name, _G.C_ClassTalents, _G.C_Traits, nameOf)
end
