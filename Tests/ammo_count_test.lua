-- Tests/ammo_count_test.lua
-- Standalone LuaJIT tests for the ammo reserve published by UI/Frame_InfoRow.lua
-- (state.ammo.total / .quiver). Regression: a full 24-slot quiver (4800) plus
-- 1200 arrows of ANOTHER type in a regular bag must read 6000, not 4800 --
-- Phase 3 hands hunters two or three BoP arrow types at once.
-- Run from the repo root: luajit Tests/ammo_count_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

--------------------------------------------------------------------------------
-- WoW surface: an inventory the test can rewrite between cases.
--------------------------------------------------------------------------------
local TIMELESS_ARROW  = 31737
local MYSTERIOUS_ARROW = 34581
local ADAMANTITE_STINGER = 32760
local TIMELESS_SHELL  = 31735
local ARROW_MAKER     = 20475
local FEL_MANA_POTION = 31677   -- not a projectile

-- itemID -> { classID, subclassID } (GetItemInfoInstant's 6th/7th returns)
local ITEM_CLASS = {
  [TIMELESS_ARROW]     = { 6, 2 },
  [MYSTERIOUS_ARROW]   = { 6, 2 },
  [ADAMANTITE_STINGER] = { 6, 2 },
  [TIMELESS_SHELL]     = { 6, 3 },
  [ARROW_MAKER]        = { 15, 0 },
  [FEL_MANA_POTION]    = { 0, 1 },
}

local bags      -- bags[bag] = { family = n, slots = { [slot] = { id, stack } } }
local equipped  -- ammo slot item id
local makerCharges = 0

_G.GetInventoryItemID = function(unit, slot)
  if unit == "player" and slot == 0 then return equipped end
end
_G.GetInventoryItemCount = function() return 0 end
_G.GetInventoryItemTexture = function() return "tex" end
_G.GetItemCount = function(id, _, withCharges)
  if id == ARROW_MAKER and withCharges then return makerCharges end
  return 0
end
_G.C_Item = {
  GetItemInfoInstant = function(id)
    local c = ITEM_CLASS[id]
    if not c then return nil end
    return id, "", "", "", 0, c[1], c[2]
  end,
}
_G.C_Container = {
  GetContainerNumFreeSlots = function(bag)
    local b = bags[bag]
    return 0, b and b.family or 0
  end,
  GetContainerNumSlots = function(bag)
    local b = bags[bag]
    return b and b.numSlots or 0
  end,
  GetContainerItemInfo = function(bag, slot)
    local b = bags[bag]
    local s = b and b.slots[slot]
    if not s then return nil end
    return { itemID = s[1], stackCount = s[2] }
  end,
}

local addon = { Constants = {}, state = { ammo = {} } }
local module
function addon:NewModule(name, ...)
  module = { name = name, frame = { arrowIcon = { SetTexture = function() end } } }
  function module:RegisterEvent() end
  return module
end
_G.LibStub = function(name, silent)
  if name == "AceAddon-3.0" then return { GetAddon = function() return addon end } end
  if silent then return nil end
  return {}
end
addon.UI = { RegisterFontString = function() end, GetFont = function() return "" end }

dofile("Core/Constants.lua")
dofile("UI/Frame_InfoRow.lua")

local function setInventory(spec)
  bags = {}
  for bag, b in pairs(spec.bags) do
    local slots, n = {}, 0
    for i, s in ipairs(b.items) do slots[i] = s; n = i end
    bags[bag] = { family = b.family, numSlots = math.max(n, b.numSlots or 0), slots = slots }
  end
  equipped = spec.equipped
  makerCharges = spec.makerCharges or 0
end

local function fullQuiver(id)
  local items = {}
  for i = 1, 24 do items[i] = { id, 200 } end
  return { family = 1, items = items }
end

local function total()
  module:RefreshArrows()
  return addon.state.ammo.total, addon.state.ammo.quiver
end

-- 1. Bug report shape: quiver full of one arrow type, another type in a bag.
setInventory({
  equipped = TIMELESS_ARROW,
  bags = {
    [0] = { family = 0, items = { { MYSTERIOUS_ARROW, 200 }, { MYSTERIOUS_ARROW, 200 },
      { MYSTERIOUS_ARROW, 200 }, { MYSTERIOUS_ARROW, 200 }, { MYSTERIOUS_ARROW, 200 },
      { MYSTERIOUS_ARROW, 200 } } },
    [1] = fullQuiver(TIMELESS_ARROW),
  },
})
local t, q = total()
ok(q == 4800, "quiver counts its 24 stacks (got " .. tostring(q) .. ")")
ok(t == 6000, "bag arrows of a different type count toward the total (got " .. tostring(t) .. ")")

-- 2. Same-type bag stacks still count (the old behaviour).
setInventory({
  equipped = TIMELESS_ARROW,
  bags = {
    [0] = { family = 0, items = { { TIMELESS_ARROW, 200 }, { FEL_MANA_POTION, 5 } } },
    [1] = fullQuiver(TIMELESS_ARROW),
  },
})
ok(total() == 5000, "same-type bag stack counts; non-projectiles don't")

-- 3. Nothing loaded in the ammo slot: bag arrows still count.
setInventory({
  equipped = nil,
  bags = {
    [0] = { family = 0, items = { { ADAMANTITE_STINGER, 200 }, { MYSTERIOUS_ARROW, 100 } } },
    [1] = fullQuiver(TIMELESS_ARROW),
  },
})
ok(total() == 5100, "no equipped ammo: every projectile in the bags still counts")

-- 4. Bullets in a bag don't count toward an arrow user's reserve.
setInventory({
  equipped = TIMELESS_ARROW,
  bags = {
    [0] = { family = 0, items = { { TIMELESS_SHELL, 200 }, { MYSTERIOUS_ARROW, 200 } } },
    [1] = fullQuiver(TIMELESS_ARROW),
  },
})
ok(total() == 5000, "bullets are excluded when arrows are loaded")

-- 5. Arrow-maker charges still add their yield.
setInventory({
  equipped = TIMELESS_ARROW,
  makerCharges = 3,
  bags = {
    [0] = { family = 0, items = { { ARROW_MAKER, 1 } } },
    [1] = fullQuiver(TIMELESS_ARROW),
  },
})
ok(total() == 4800 + 3 * 200, "maker charges add 200 per charge")

-- 6. No quiver at all: the whole reserve is the bag contents.
setInventory({
  equipped = MYSTERIOUS_ARROW,
  bags = {
    [0] = { family = 0, items = { { MYSTERIOUS_ARROW, 200 }, { TIMELESS_ARROW, 150 } } },
  },
})
local t6, q6 = total()
ok(t6 == 350 and q6 == 0, "no quiver: total is the bag arrows, quiver reads 0")
ok(addon.state.ammo.hasQuiver == false, "hasQuiver false without an ammo bag")

print(("ammo_count_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
