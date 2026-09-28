-- Forever/CooldownDiscovery.lua
-- Builds the Forever cooldown catalog from the client's own spellbook and talent tree instead of a hand-typed list.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local D = {}
Nock.CooldownDiscovery = D

-- The live client behind the catalog: every read pcall'd and made plain.
-- book() / talents() -> { {id, name, src, line?, passive?, rank?, max?} },
-- passive(id), baseCd(id) -> ms, gcdMs, tipCd(id) -> text, curCd(id) -> s,
-- charges(id) -> max, key(id) -> tracked catalog key, level, inCombat.
function D.ClientApi()
  local P = Nock.Flavor.Plain
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local okc, a, b = pcall(f, ...)
    if not okc then return nil end
    return P(a), P(b)
  end
  local CS, SB, E, T, CT = _G.C_Spell, _G.C_SpellBook, _G.Enum, _G.C_Traits, _G.C_ClassTalents
  local api = { level = call(_G.UnitLevel, "player"), inCombat = InCombatLockdown and InCombatLockdown() or false }
  api.book = function()
    local out = {}
    if not (SB and SB.GetNumSpellBookSkillLines and E and E.SpellBookSpellBank) then return out end
    local bank = E.SpellBookSpellBank.Player
    for line = 1, call(SB.GetNumSpellBookSkillLines) or 0 do
      local info = call(SB.GetSpellBookSkillLineInfo, line)
      if type(info) == "table" and info.itemIndexOffset and info.numSpellBookItems then
        for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
          local item = call(SB.GetSpellBookItemInfo, slot, bank)
          if type(item) == "table" and type(item.spellID) == "number" then
            out[#out + 1] = { id = item.spellID, name = item.name, src = "book:" .. tostring(info.name):sub(1, 6),
                              line = line, passive = item.isPassive }
          end
        end
      end
    end
    return out
  end
  api.talents = function()
    local out = {}
    local cfg = CT and call(CT.GetActiveConfigID)
    local info = cfg and T and call(T.GetConfigInfo, cfg)
    for _, tree in ipairs(type(info) == "table" and info.treeIDs or {}) do
      for _, nodeID in ipairs(call(T.GetTreeNodes, tree) or {}) do
        local node = call(T.GetNodeInfo, cfg, nodeID)
        if type(node) == "table" then
          -- A choice node lists every option as an entryID; only the one the
          -- player actually picked (activeEntry) is taken. A single-entry
          -- node has nothing to choose between, so its own entry is it.
          local entryIDs = type(node.entryIDs) == "table" and node.entryIDs or {}
          local single = #entryIDs <= 1
          local activeEntry = type(node.activeEntry) == "table" and node.activeEntry or nil
          for _, entryID in ipairs(entryIDs) do
            local entry = call(T.GetEntryInfo, cfg, entryID)
            local def = type(entry) == "table" and entry.definitionID and call(T.GetDefinitionInfo, entry.definitionID)
            local sid = type(def) == "table" and def.spellID or nil
            if type(sid) == "number" then
              local chosen = single or (activeEntry and activeEntry.entryID == entryID) or false
              local activeRank = type(node.activeRank) == "number" and node.activeRank or 0
              local rank = (chosen and activeRank > 0) and activeRank or 0
              out[#out + 1] = { id = sid, name = Nock.API.SpellName(sid), src = "talent",
                                rank = rank, max = node.maxRanks }
            end
          end
        end
      end
    end
    return out
  end
  api.passive = function(id)
    if CS and CS.IsSpellPassive then return call(CS.IsSpellPassive, id) end
    return call(_G.IsPassiveSpell, id)
  end
  api.baseCd = function(id) return call(_G.GetSpellBaseCooldown, id) end
  api.tipCd = function(id)
    local TI = _G.C_TooltipInfo
    local data = TI and call(TI.GetSpellByID, id)
    for _, ln in ipairs(type(data) == "table" and data.lines or {}) do
      for _, side in ipairs({ P(ln.leftText), P(ln.rightText) }) do
        if type(side) == "string" and (side:lower():find("cooldown", 1, true) or side:lower():find("recharge", 1, true)) then
          return side
        end
      end
    end
    return nil
  end
  api.curCd = function(id)
    local cd = CS and CS.GetSpellCooldown and call(CS.GetSpellCooldown, id)
    return type(cd) == "table" and P(cd.duration) or nil
  end
  api.charges = function(id)
    local ch = CS and CS.GetSpellCharges and call(CS.GetSpellCharges, id)
    return type(ch) == "table" and P(ch.maxCharges) or nil
  end
  api.key = function(id)
    local CD = Nock:GetModule("Cooldowns", true)
    local e = CD and CD.Resolve and CD:Resolve(id)
    return e and e.key or nil
  end
  return api
end

-- Every spell the character could put on the grid, one row per spell: the
-- spellbook first, then the talent tree. A spell already seen in the book
-- gets `talent = true` added to that same row instead of a second row.
local function validName(n)
  return type(n) == "string" and n ~= ""
end

function D.Rows(api)
  local rows, seen = {}, {}
  local function passiveOf(e)
    if e.passive ~= nil then return e.passive end
    return api.passive and api.passive(e.id) or nil
  end
  for _, e in ipairs(api.book and api.book() or {}) do
    -- A spell the client has no info for (a talent name lookup came back
    -- nil) cannot be grouped by name below; drop the row rather than build
    -- one that would crash D.Build.
    if e.id and not seen[e.id] and validName(e.name) then
      local row = { id = e.id, name = e.name, src = e.src, line = e.line,
                    passive = passiveOf(e), baseMs = api.baseCd and api.baseCd(e.id) }
      seen[e.id] = row
      rows[#rows + 1] = row
    end
  end
  for _, e in ipairs(api.talents and api.talents() or {}) do
    if e.id then
      local row = seen[e.id]
      if row then
        row.talent = true
        row.rank = e.rank
        row.max = e.max
      elseif validName(e.name) then
        row = { id = e.id, name = e.name, src = e.src, passive = passiveOf(e),
                baseMs = api.baseCd and api.baseCd(e.id), rank = e.rank, max = e.max, talent = true }
        seen[e.id] = row
        rows[#rows + 1] = row
      end
    end
  end
  return rows
end

-- A row is known when the character actually has it: a book row (learned),
-- or a talent row with a rank taken.
local function isRowKnown(r)
  if not r.talent then return true end
  return (r.rank or 0) > 0
end

local function anyRowKnown(rowList)
  for _, r in ipairs(rowList) do
    if isRowKnown(r) then return true end
  end
  return false
end

-- Whether a set of rows is worth a grid entry: something active with a real
-- cooldown, not just the GCD or an instant-recast ability.
local function keepRows(rowList)
  local active, maxBase = false, 0
  for _, r in ipairs(rowList) do
    if not r.passive then active = true end
    local base = r.baseMs or 0
    if base > maxBase then maxBase = base end
  end
  return active and maxBase > 1500, maxBase
end

local function groupHasId(g, id)
  if not id then return false end
  for _, r in ipairs(g.rows) do
    if r.id == id then return true end
  end
  return false
end

local function groupHasAnyId(g, ids)
  if not ids then return false end
  for _, id in ipairs(ids) do
    if groupHasId(g, id) then return true end
  end
  return false
end

local function nameInList(name, list)
  if not list then return false end
  for _, v in ipairs(list) do
    if v == name then return true end
  end
  return false
end

local function matchesEntry(g, entry)
  return groupHasId(g, entry.id) or groupHasAnyId(g, entry.ids)
    or (entry.name and g.name == entry.name) or nameInList(g.name, entry.names)
end

local function lowestId(rowList)
  local id
  for _, r in ipairs(rowList) do
    if r.id and (not id or r.id < id) then id = r.id end
  end
  return id
end

local function shallowCopy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

-- Rows -> catalog entries: matched against the static overlay by id or name,
-- everything else that clears the cooldown bar surfacing as a new entry.
-- A client group may match SEVERAL static entries at once (a shared-cooldown
-- group: the AimMulti pair and the Multi single both match "Multi-Shot") --
-- every matching entry is discovered, each with its own tile; a group that
-- matched at least one static entry never becomes a new `s<id>` entry.
-- `static` is read only, never mutated.
function D.Build(rows, static)
  local groups, groupOrder = {}, {}
  for _, r in ipairs(rows) do
    -- A row with no usable name (D.Rows already filters these; a caller
    -- handing rows to D.Build directly might not) cannot key the group map.
    if validName(r.name) then
      local g = groups[r.name]
      if not g then
        g = { name = r.name, rows = {} }
        groups[r.name] = g
        groupOrder[#groupOrder + 1] = g
      end
      g.rows[#g.rows + 1] = r
    end
  end

  local matchedGroups = {}
  local groupMatched = {}
  for _, entry in ipairs(static) do
    for _, g in ipairs(groupOrder) do
      if matchesEntry(g, entry) then
        matchedGroups[entry] = matchedGroups[entry] or {}
        matchedGroups[entry][#matchedGroups[entry] + 1] = g
        groupMatched[g] = true
      end
    end
  end

  local list = {}
  for _, entry in ipairs(static) do
    local out = shallowCopy(entry)
    local matched = matchedGroups[entry]
    if matched then
      local allRows = {}
      for _, g in ipairs(matched) do
        for _, r in ipairs(g.rows) do allRows[#allRows + 1] = r end
      end
      local keep, maxBase = keepRows(allRows)
      if keep then
        out.cd = maxBase / 1000
        out.discovered = true
      end
    end
    list[#list + 1] = out
  end

  for _, g in ipairs(groupOrder) do
    if not groupMatched[g] then
      local keep, maxBase = keepRows(g.rows)
      if keep then
        local hasTalent, hasBookLine1 = false, false
        for _, r in ipairs(g.rows) do
          if r.talent then hasTalent = true end
          if not r.talent and r.line == 1 then hasBookLine1 = true end
        end
        local id = lowestId(g.rows)
        local cat = hasTalent and "Talent" or (hasBookLine1 and "Racial" or "Class")
        local e = {
          key = "s" .. tostring(id), id = id, name = g.name, label = g.name,
          cd = maxBase / 1000, row = 2, discovered = true, cat = cat,
        }
        if hasTalent then e.talent = true end
        if cat == "Racial" then e.racial = true end
        list[#list + 1] = e
      end
    end
  end

  return list
end

-- A compact fingerprint of a built list: changes when a key's cooldown
-- changes, so a rebuild can be skipped otherwise.
function D.Signature(list)
  local parts = {}
  for _, e in ipairs(list) do
    parts[#parts + 1] = tostring(e.key) .. "=" .. tostring(e.cd)
  end
  return table.concat(parts, "|")
end
