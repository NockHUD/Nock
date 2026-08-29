-- Tests/trinket_onuse_test.lua
-- Standalone LuaJIT tests for the trinket "is it actually poppable?" flag the
-- Cooldowns module publishes as state.cooldowns.T1/T2.onUse.
-- Run from the repo root: luajit Tests/trinket_onuse_test.lua
--
-- The bug this guards: a passive proc trinket (Dragonspine Trophy) reports no
-- cooldown, so `ready` is true forever, and it has an inventory texture, so the
-- old `.icon` gate passed too — the Lust warning kept telling the user to "Pop
-- T2" at something with no Use effect. `.onUse` is the honest signal.
--
-- Core/Constants.lua and Modules/Cooldowns.lua are real, loaded here with the
-- WoW/Ace surface stubbed, so the T1/T2 slot numbers under test are the
-- shipping ones.

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

--------------------------------------------------------------------------------
-- Fixtures: two real TBC hunter trinkets, one of each kind.
--------------------------------------------------------------------------------
local BROOCH = 29383  -- Bloodlust Brooch — "Use: +278 attack power for 20 sec"
local DST    = 28830  -- Dragonspine Trophy — equip-only, chance on hit
-- Both verified in-game via /nock trinkets on 2026-08-13: the Brooch answers
-- "Lust for Battle"(35166), the Trophy answers nil.
local USE_SPELL = { [BROOCH] = { "Lust for Battle", 35166 } }

local equipped = {}   -- [inventorySlot] = itemID

--------------------------------------------------------------------------------
-- Minimal WoW / Ace stubs
--------------------------------------------------------------------------------
local Nock = { state = { cooldowns = {}, sim = { active = false } }, db = { profile = {} } }
local Cooldowns

function Nock:NewModule()
  Cooldowns = {}
  function Cooldowns:RegisterEvent() end
  function Cooldowns:RegisterMessage() end
  function Cooldowns:ScheduleTimer() end
  function Cooldowns:Print() end
  return Cooldowns
end

_G.LibStub = function() return { GetAddon = function() return Nock end } end

_G.GetTime                    = function() return 1000 end
_G.GetInventoryItemID         = function(_, slot) return equipped[slot] end
_G.GetInventoryItemTexture    = function(_, slot) return equipped[slot] and "tex" or nil end
_G.GetInventoryItemCooldown   = function() return 0, 0 end
_G.GetSpellInfo               = function(id) return "Spell " .. id, nil, "icon" end
_G.GetItemInfo                = function(id) return "Item " .. id, nil, nil, nil, nil, nil, nil, nil, nil, "icon" end
_G.GetItemCooldown            = function() return 0, 0 end
_G.GetItemCount               = function() return 1 end
_G.UnitRace                   = function() return "Orc", "Orc" end
_G.GetTalentTabInfo           = function(i) return nil, nil, nil, nil, i == 1 and 41 or 0 end

-- The real client exposes this in the C_Item namespace; a test can swap it out
-- to model an older/namespace-less client (see the fallback case below).
local function installItemSpell()
  _G.C_Item = {
    GetItemSpell = function(itemID)
      local e = USE_SPELL[itemID]
      if not e then return nil end
      return e[1], e[2]
    end,
  }
end
installItemSpell()

dofile("Core/Constants.lua")
dofile("Modules/Cooldowns.lua")

local function refresh()
  Cooldowns:RebuildLists()
  Cooldowns:RefreshIcons()
  Cooldowns:ScanCooldowns()
end

local function slot(key) return Nock.state.cooldowns[key] end

--------------------------------------------------------------------------------
-- 1. The reported bug, at the level the warning reads: a proc trinket looks
--    permanently "ready" and owns an icon, so only `onUse` can tell it apart.
--------------------------------------------------------------------------------
equipped[13], equipped[14] = BROOCH, DST
refresh()

ok(slot("T2").ready == true,  "a passive trinket reads as ready (no cooldown to report)")
ok(slot("T2").icon ~= nil,    "a passive trinket still has an inventory icon")
ok(slot("T2").onUse == false, "Dragonspine Trophy in slot 14 is NOT on-use")
ok(slot("T1").onUse == true,  "Bloodlust Brooch in slot 13 IS on-use")

--------------------------------------------------------------------------------
-- 2. Symmetry: the slots aren't special-cased, whichever way round they sit.
--------------------------------------------------------------------------------
equipped[13], equipped[14] = DST, BROOCH
refresh()
ok(slot("T1").onUse == false, "the flag follows the item, not the slot (T1 passive)")
ok(slot("T2").onUse == true,  "the flag follows the item, not the slot (T2 on-use)")

--------------------------------------------------------------------------------
-- 3. An empty trinket slot is nothing to pop.
--------------------------------------------------------------------------------
equipped[13], equipped[14] = nil, nil
refresh()
ok(slot("T1").onUse == false, "empty slot 13 is not on-use")
ok(slot("T2").onUse == false, "empty slot 14 is not on-use")

--------------------------------------------------------------------------------
-- 4. Non-inventory trackers are actionable by nature — a spell or a bag item is
--    something you press. They must not be dragged into the passive bucket.
--------------------------------------------------------------------------------
ok(slot("RF").onUse == true,    "a tracked spell is on-use")
ok(slot("Haste").onUse == true, "a tracked bag item is on-use")

--------------------------------------------------------------------------------
-- 5. Fallback: if the client exposes no GetItemSpell at all we cannot tell, so
--    assume on-use. Failing the other way would silently swallow a legitimate
--    "Pop T1" for every user on such a client.
--------------------------------------------------------------------------------
local savedC_Item = _G.C_Item
_G.C_Item, _G.GetItemSpell = nil, nil
equipped[13], equipped[14] = BROOCH, DST
refresh()
ok(slot("T2").onUse == true, "no GetItemSpell anywhere: assume on-use rather than hide")
_G.C_Item = savedC_Item

--------------------------------------------------------------------------------
-- 6. The bare global is honoured when the namespaced form is missing.
--------------------------------------------------------------------------------
_G.C_Item = nil
_G.GetItemSpell = function(itemID)
  local e = USE_SPELL[itemID]
  if not e then return nil end
  return e[1], e[2]
end
refresh()
ok(slot("T1").onUse == true,  "bare GetItemSpell resolves the on-use trinket")
ok(slot("T2").onUse == false, "bare GetItemSpell resolves the passive trinket")
_G.C_Item, _G.GetItemSpell = savedC_Item, nil

--------------------------------------------------------------------------------
-- 7. A throwing/erroring API must not take the addon down mid-tick.
--------------------------------------------------------------------------------
_G.C_Item = { GetItemSpell = function() error("client says no") end }
refresh()
ok(slot("T1").onUse == true, "an erroring GetItemSpell degrades to on-use, not a crash")
_G.C_Item = savedC_Item

--------------------------------------------------------------------------------
print(("trinket_onuse_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
