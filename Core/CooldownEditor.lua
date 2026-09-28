-- Core/CooldownEditor.lua
-- Every change to the React cooldown rows: pure row operations (CooldownEditor) and the profile store behind them (CooldownRows).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local E = {}
Nock.CooldownEditor = E

function E.Copy(rows)
  local out = {}
  for r = 1, #rows do
    out[r] = {}
    for i = 1, #rows[r] do out[r][i] = rows[r][i] end
  end
  return out
end

function E.Find(rows, key)
  for r = 1, #rows do
    for i = 1, #rows[r] do if rows[r][i] == key then return r, i end end
  end
  return nil
end

function E.Add(rows, ri, key)
  local out = E.Copy(rows)
  local fr, fi = E.Find(out, key)
  if fr then return out, fr, fi end
  if type(out[ri]) ~= "table" then return out end
  out[ri][#out[ri] + 1] = key
  return out, ri, #out[ri]
end

function E.Move(rows, key, toRow, toIndex)
  local out = E.Copy(rows)
  local ri, ci = E.Find(out, key)
  if not ri or type(out[toRow]) ~= "table" then return out end
  table.remove(out[ri], ci)
  if ri == toRow and ci < toIndex then toIndex = toIndex - 1 end
  local n = #out[toRow]
  if toIndex < 1 then toIndex = 1 elseif toIndex > n + 1 then toIndex = n + 1 end
  table.insert(out[toRow], toIndex, key)
  return out
end

function E.Remove(rows, key)
  local out = E.Copy(rows)
  local ri, ci = E.Find(out, key)
  if ri then table.remove(out[ri], ci) end
  return out
end

function E.Sanitize(rows, isValid, nRows)
  local out, seen = {}, {}
  for r = 1, nRows do
    out[r] = {}
    local src = type(rows) == "table" and rows[r]
    if type(src) == "table" then
      for i = 1, #src do
        local k = src[i]
        if type(k) == "string" and not seen[k] and isValid(k) then
          seen[k] = true
          out[r][#out[r] + 1] = k
        end
      end
    end
  end
  return out
end

-- Type-safe like Sanitize: a garbage row (not a table) or a garbage entry
-- (not a string key) is skipped rather than thrown on -- a hand-edited or
-- imported SavedVariables can carry either.
function E.Migrate(rows, disabled)
  local out = {}
  local n = type(rows) == "table" and #rows or 0
  for r = 1, n do
    out[r] = {}
    local src = rows[r]
    if type(src) == "table" then
      for i = 1, #src do
        local k = src[i]
        if type(k) == "string" and not (disabled and disabled[k]) then out[r][#out[r] + 1] = k end
      end
    end
  end
  return out
end

-- A drop at visible slot ii (1..#visibleKeys+1) as an index into the saved row,
-- which also holds keys the view hides (another race's racials).
function E.VisibleToSaved(savedRow, visibleKeys, ii)
  local function at(k) for i = 1, #savedRow do if savedRow[i] == k then return i end end return #savedRow + 1 end
  if ii <= #visibleKeys then return at(visibleKeys[ii]) end
  if #visibleKeys == 0 then return #savedRow + 1 end
  return at(visibleKeys[#visibleKeys]) + 1
end

--------------------------------------------------------------------------------
-- The store: profile.reactCdRows is the one record of what the grid shows.
--------------------------------------------------------------------------------
local S = {}
Nock.CooldownRows = S

local function profile() return (Nock.db and Nock.db.profile) or {} end

local function customKey(rec)
  if type(rec.key) == "string" and rec.key ~= "" then return rec.key end
  local id = tonumber(rec.id)
  return id and ("c_" .. (rec.type or "spell") .. "_" .. id) or nil
end

-- Catalog or custom, never "currently tracked": a name-only racial is not
-- tracked until the spellbook names it, and must survive an edit before that.
function S.IsValidKey(key)
  local Cat = Nock.CooldownCatalog
  if Cat and Cat.IsCatalogKey(key) then return true end
  -- A discovered key's shape (Forever/CooldownDiscovery.lua's "s<lowestId>"):
  -- valid on sight even before this session's own discovery ran, so a saved
  -- row naming one survives Sanitize/MigrateOnce instead of being dropped.
  if type(key) == "string" and key:match("^s%d+$") then return true end
  for _, rec in ipairs(profile().cooldownCustom or {}) do
    if customKey(rec) == key then return true end
  end
  return false
end

function S.Defaults()
  local out = {}
  for r, def in ipairs(Nock.Constants.REACT_CD_ROWS) do
    out[r] = {}
    for i, k in ipairs(def.keys) do out[r][i] = k end
  end
  return out
end

function S.Get()
  local p = profile()
  local src = type(p.reactCdRows) == "table" and p.reactCdRows or S.Defaults()
  return E.Sanitize(src, S.IsValidKey, #Nock.Constants.REACT_CD_ROWS)
end

local function write(rows)
  if InCombatLockdown and InCombatLockdown() then return false end
  profile().reactCdRows = E.Copy(rows)
  Nock:SendMessage("NOCK_VISUALS_CHANGED")
  return true
end

function S.Set(rows)
  if not write(rows) then return false end
  S._undo = nil
  return true
end

function S.ApplyPack(id, isKnown)
  local Cat = Nock.CooldownCatalog
  local rows = Cat and Cat.PackRows(id, isKnown)
  if not rows then return false end
  local before = S.Get()
  if not write(rows) then return false end
  S._undo = before
  return true
end

function S.CanUndo() return S._undo ~= nil end

function S.Undo()
  local u = S._undo
  if not u then return false end
  if not write(u) then return false end
  S._undo = nil
  return true
end

-- The settings window clears the one-step undo when it closes (a pack applied
-- last session should not silently un-apply itself next time the board opens).
function S.ClearUndo() S._undo = nil end

-- Once per profile: the old hidden-slot set is folded into the rows so the
-- grid looks the same, then cleared (a tile is shown iff it is in a row).
function S.MigrateOnce()
  local p = profile()
  if p.reactCdMigrated then return end
  local dis = p.reactCooldownDisabled
  if type(p.reactCdRows) == "table" or (type(dis) == "table" and next(dis)) then
    local src = type(p.reactCdRows) == "table" and p.reactCdRows or S.Defaults()
    local migrated = E.Migrate(src, dis or {})
    -- Sanitize after migrating too: a duplicate key or one that fails
    -- IsValidKey should not survive migration any more than a normal load.
    p.reactCdRows = E.Sanitize(migrated, S.IsValidKey, #Nock.Constants.REACT_CD_ROWS)
  end
  p.reactCooldownDisabled = {}
  p.reactCdMigrated = true
end

-- True only for a key backed by a profile.cooldownCustom record: a catalog
-- key or a discovered "s<id>" key must never be deleted through here.
local function isCustomRecordKey(key)
  for _, rec in ipairs(profile().cooldownCustom or {}) do
    if customKey(rec) == key then return true end
  end
  return false
end

-- Delete removes the spell entirely (the record and every placement); Remove
-- (Core/CooldownEditor.lua's E.Remove) only takes a key off the grid and
-- leaves the record in the Custom tab.
function S.DeleteCustom(key)
  if InCombatLockdown and InCombatLockdown() then return false end
  if not isCustomRecordKey(key) then return false end
  if not S.Set(E.Remove(S.Get(), key)) then return false end
  local list = profile().cooldownCustom or {}
  for i = #list, 1, -1 do
    if customKey(list[i]) == key then table.remove(list, i) end
  end
  local mod = Nock:GetModule("Cooldowns", true)
  if mod and mod.RebuildLists then mod:RebuildLists() end
  return true
end

function S.AddCustomSpell(id)
  local p = profile()
  p.cooldownCustom = p.cooldownCustom or {}
  local key = "c_spell_" .. id
  for _, rec in ipairs(p.cooldownCustom) do
    if rec.type == "spell" and tonumber(rec.id) == id then return customKey(rec) end
  end
  p.cooldownCustom[#p.cooldownCustom + 1] = { key = key, type = "spell", id = id }
  local mod = Nock:GetModule("Cooldowns", true)
  if mod and mod.RebuildLists then mod:RebuildLists() end
  return key
end
