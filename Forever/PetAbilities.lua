-- Forever/PetAbilities.lua
-- The pets' cooldown abilities for the grid: the catalog from the stable lists, what the summoned pet knows, its bar slots.

-- Evidence: `/nock probe pets`, 2026-10-09 (spec 2026-10-09-forever-pet-
-- cooldowns-design.md). The stable lists answer anywhere, in combat too, and
-- list EVERY rank the family can learn; the pet spellbook lists what the
-- summoned pet has learned (Growl and Cower are only there); the pet bar's
-- GetPetActionCooldown stays plain in combat in the open world.
local PA = {}

PA.GCD_MS = 1500   -- a base cooldown at or under this is the GCD: no cooldown to show
PA.BAR_SLOTS = 10

-- Pure. `pets` = PetInfo-like records ({ name, petAbilities }), `book` = the
-- summoned pet's active spells ({ id, name }), `summoned` = its name.
-- api.nameOf(id) -> name | nil, api.baseCd(id) -> ms | nil (nil = cannot
-- say). One entry per ability NAME, ranks collapsed, sorted by name, every
-- ability offered (Claw too, user 2026-10-09: a no-cooldown tile shows ready):
-- { key = "p<lowest id>", name, ids (ascending), cd (s | nil = none / unknown), pets = { names } }.
function PA.Catalog(pets, book, summoned, api)
  local byName, order = {}, {}
  local function add(id, petName)
    if type(id) ~= "number" then return end
    local n = api.nameOf(id)
    if type(n) ~= "string" or n == "" then return end
    local e = byName[n]
    if not e then
      e = { name = n, ids = {}, pets = {}, _ids = {}, _pets = {} }
      byName[n] = e
      order[#order + 1] = n
    end
    if not e._ids[id] then
      e._ids[id] = true
      e.ids[#e.ids + 1] = id
      local ms = api.baseCd(id)
      if type(ms) == "number" then e.ms = math.max(e.ms or 0, ms) end
    end
    if type(petName) == "string" and not e._pets[petName] then
      e._pets[petName] = true
      e.pets[#e.pets + 1] = petName
    end
  end
  for _, p in ipairs(pets or {}) do
    for _, id in ipairs(type(p.petAbilities) == "table" and p.petAbilities or {}) do add(id, p.name) end
  end
  for _, b in ipairs(book or {}) do add(b.id, summoned) end
  local out = {}
  table.sort(order)
  for _, n in ipairs(order) do
    local e = byName[n]
    table.sort(e.ids)
    out[#out + 1] = { key = "p" .. e.ids[1], name = e.name, ids = e.ids, pets = e.pets,
                      cd = (e.ms and e.ms > PA.GCD_MS) and e.ms / 1000 or nil }
  end
  return out
end

-- Pure: the set of ability names the summoned pet knows.
function PA.KnownNames(book)
  local out = {}
  for _, b in ipairs(book or {}) do
    if type(b.name) == "string" then out[b.name] = true end
  end
  return out
end

-- Pure: a stable signature of a known-name set (did the pet change?).
function PA.Signature(known)
  local names = {}
  for n in pairs(known or {}) do names[#names + 1] = n end
  table.sort(names)
  return table.concat(names, "\31")
end

-- Pure: the pet bar slot holding this ability. `bar[slot]` = { id, name }
-- (holes allowed); a slot matches on any of `ids` or, for a rank the record
-- never saw, on the name.
function PA.BarSlot(bar, ids, name)
  for slot = 1, PA.BAR_SLOTS do
    local b = bar and bar[slot]
    if b then
      for i = 1, #(ids or {}) do
        if b.id == ids[i] then return slot, b.id end
      end
      if name and b.name == name then return slot, b.id end
    end
  end
  return nil
end

--------------------------------------------------------------------------------
-- The live client. Every read pcall'd and made plain; what cannot be read is nil.
--------------------------------------------------------------------------------
local LS = rawget(_G, "LibStub")
local Nock = LS and LS("AceAddon-3.0", true) and LS("AceAddon-3.0"):GetAddon("Nock", true)

local function plain(v)
  if Nock and Nock.Flavor and Nock.Flavor.Plain then return Nock.Flavor.Plain(v) end
  return v
end

-- No table per call: the bar is read on the slow lane.
local function rest(okc, ...)
  if not okc then return nil end
  return ...
end

local function call(f, ...)
  if type(f) ~= "function" then return nil end
  return rest(pcall(f, ...))
end

-- Every pet the hunter has: the active ones, then the stabled ones.
function PA.ClientPets()
  local SI, out = _G.C_StableInfo, {}
  if not SI then return out end
  for _, fn in ipairs({ "GetActivePetList", "GetStabledPetList" }) do
    local list = call(SI[fn])
    if type(list) == "table" then
      for _, pi in ipairs(list) do
        if type(pi) == "table" then
          out[#out + 1] = { name = plain(pi.name), petAbilities = pi.petAbilities, petNumber = plain(pi.petNumber) }
        end
      end
    end
  end
  return out
end

-- The summoned pet's active spells (commands like Attack have no id: skipped).
function PA.ClientBook()
  local SB, E, out = _G.C_SpellBook, _G.Enum, {}
  local bank = E and E.SpellBookSpellBank and E.SpellBookSpellBank.Pet
  if not (SB and SB.HasPetSpells and SB.GetSpellBookItemInfo and bank) then return out end
  -- Learned spells only. The pet book's own entries are PetAction (type 3,
  -- `/nock petcd` 2026-10-09: Bite, Claw, Growl); a FutureSpell (trainable,
  -- not learned yet) is left out, and so is a spell the client calls unknown.
  local FUTURE = E.SpellBookItemType and E.SpellBookItemType.FutureSpell
  local n = plain(call(SB.HasPetSpells))
  for i = 1, tonumber(n) or 0 do
    local item = call(SB.GetSpellBookItemInfo, i, bank)
    if type(item) == "table" then
      local id, name = plain(item.spellID), plain(item.name)
      local kind = plain(item.itemType)
      local learned = FUTURE == nil or kind ~= FUTURE
      if learned and type(id) == "number" and SB.IsSpellKnown and plain(call(SB.IsSpellKnown, id, bank)) == false then
        learned = false
      end
      if learned and type(id) == "number" and type(name) == "string" and plain(item.isPassive) ~= true then
        out[#out + 1] = { id = id, name = name }
      end
    end
  end
  return out
end

-- The pet bar: slot -> { id, name } for the slots holding a spell. `out` reused.
function PA.ClientBar(out)
  out = out or {}
  for slot = 1, PA.BAR_SLOTS do
    local name, _, _, _, _, _, id = call(_G.GetPetActionInfo, slot)
    name, id = plain(name), plain(id)
    local b = out[slot]
    if type(id) == "number" then
      b = b or {}
      b.id, b.name = id, name
      out[slot] = b
    else
      out[slot] = nil
    end
  end
  return out
end

-- A bar slot's cooldown as plain numbers, or nil when the client hides it.
function PA.ClientBarCooldown(slot)
  local start, dur = call(_G.GetPetActionCooldown, slot)
  start, dur = plain(start), plain(dur)
  if type(start) ~= "number" or type(dur) ~= "number" then return nil end
  return start, dur
end

function PA.SummonedName()
  local n = plain(call(_G.UnitName, "pet"))
  return type(n) == "string" and n or nil
end

if Nock then Nock.PetAbilities = PA end
return PA
