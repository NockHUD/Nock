-- Forever/CooldownCatalog.lua
-- The React grid's cooldown catalog on Forever: lookups over Spells.TRACKED and the one-click packs.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Cat = {}
Nock.CooldownCatalog = Cat

-- "@racials" stands for every racial key: each character only ever sees its own
-- (Forever/Cooldowns.lua IsEntryAvailable), so a pack serves every race.
Cat.PACKS = {
  { id = "leveling", name = "Leveling", rows = { { "Arc", "AimMulti", "Raptor", "RF", "@racials" }, { "Conc", "FD", "Disengage", "ImmoTrap" } } },
  { id = "bm",       name = "BM raid",  rows = { { "RF", "BW", "AimMulti", "Arc", "@racials" }, { "Intim", "FD", "Tranq", "Disengage" } } },
  { id = "mm",       name = "MM raid",  rows = { { "RF", "AimMulti", "Arc", "@racials" }, { "Scatter", "FD", "Tranq", "Sniper" } } },
  { id = "sv",       name = "Survival", rows = { { "RF", "AimMulti", "Arc", "Raptor", "Mongoose", "@racials" }, { "Counter", "Deter", "Strider", "FD", "Disengage" } } },
  { id = "minimal",  name = "Minimal",  rows = { { "RF", "@racials" }, { "FD" } } },
  { id = "all",      name = "Everything I know" },   -- computed: PackRows("all", isKnown)
}

-- Discovery replaces C.TRACKED_COOLDOWNS in place, so the live catalog on
-- Forever is that table, not the static Spells.TRACKED overlay it started
-- from; Invalidate() drops the cached index after a rebuild.
function Cat.Entries()
  if Nock.Flavor and Nock.Flavor.forever and Nock.Constants and Nock.Constants.TRACKED_COOLDOWNS then
    return Nock.Constants.TRACKED_COOLDOWNS
  end
  return Nock.Spells.TRACKED
end

local byKey, byId
local function index()
  if byKey then return end
  byKey, byId = {}, {}
  local single = {}
  for _, e in ipairs(Cat.Entries()) do
    byKey[e.key] = e
    if e.id then byId[e.id] = e.key; single[e.id] = true end
    if e.ids then
      for _, id in ipairs(e.ids) do
        if not single[id] and not byId[id] then byId[id] = e.key end
      end
    end
  end
end

function Cat.Invalidate() byKey, byId = nil, nil end
function Cat.Entry(key) index(); return byKey[key] end
function Cat.IsCatalogKey(key) index(); return byKey[key] ~= nil end
-- For an id shared by several catalog entries (a shared-cooldown group: the
-- AimMulti pair and the Multi/Aimed singles all answer to 2643/19434, the
-- ArcHawk pair and the Arc/Hawk singles to 3044/1293241) the SINGLE spell's
-- own entry wins here, in any catalog order, so a typed id resolves to that
-- spell (19434 -> Aimed, 3044 -> Arc), never to a pair containing it; a pair
-- answers only for an id no single entry owns. This is the opposite of cast resolution in
-- Forever/Cooldowns.lua (Cooldowns._byId), which keeps the FIRST claim so an
-- already-placed pair tile's ledger slot isn't stolen by a same-id single
-- entry listed after it. Both are intended for what each one is used for.
function Cat.ById(id) index(); return byId[id] end

function Cat.RacialKeys()
  local out = {}
  for _, e in ipairs(Cat.Entries()) do if e.racial then out[#out + 1] = e.key end end
  return out
end

function Cat.PackRows(id, isKnown)
  if id == "all" then
    local rows = { {}, {} }
    -- A shared-cooldown group (Arc/Hawk/Hydra, AimMulti/Multi/Aimed) gets only
    -- its first known member here, in catalog order -- "Everything I know"
    -- would otherwise stack every member of the same cooldown on the grid.
    local seenShared = {}
    for _, e in ipairs(Cat.Entries()) do
      if isKnown and isKnown(e.key) then
        local include = true
        if e.shared then
          if seenShared[e.shared] then include = false else seenShared[e.shared] = true end
        end
        if include then table.insert(rows[e.row or 2], e.key) end
      end
    end
    return rows
  end
  for _, pk in ipairs(Cat.PACKS) do
    if pk.id == id and pk.rows then
      local rows = {}
      for r = 1, 2 do
        rows[r] = {}
        for _, k in ipairs(pk.rows[r]) do
          if k == "@racials" then
            for _, rk in ipairs(Cat.RacialKeys()) do table.insert(rows[r], rk) end
          else
            table.insert(rows[r], k)
          end
        end
      end
      return rows
    end
  end
  return nil
end
