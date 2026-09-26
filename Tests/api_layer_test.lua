-- Tests/api_layer_test.lua
-- Nock.API resolves each WoW call once, preferring C_* and falling back to the
-- bare global, and always returns the same list shape. Run: luajit Tests/api_layer_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local function boot(env)
  for _, k in ipairs({ "C_Spell", "C_UnitAuras", "C_AddOns", "C_Item", "GetSpellInfo", "GetSpellTexture",
    "GetSpellCooldown", "IsAddOnLoaded", "UnitAura", "GetTalentTabInfo", "issecretvalue",
    "GetItemInfo", "GetItemIcon", "GetItemCount", "IsUsableSpell" }) do _G[k] = nil end
  for k, v in pairs(env) do if k ~= "__forever" then _G[k] = v end end
  local Nock = { Flavor = { forever = env.__forever or false, Plain = function(v) return v end } }
  _G.LibStub = function() return { GetAddon = function() return Nock end } end
  dofile("Core/API.lua")
  return Nock.API
end

-- 1. Forever shape: C_* tables only.
local A = boot({
  __forever = true,
  C_Spell = {
    GetSpellInfo = function(id) return { name = "Aimed Shot", iconID = 135130, castTime = 2000, minRange = 8, maxRange = 35, spellID = id } end,
    GetSpellTexture = function() return 135130 end,
    GetSpellSubtext = function() return "Rank 6" end,
    GetSpellCooldown = function() return { startTime = 10, duration = 6, isEnabled = true } end,
    GetSpellCooldownDuration = function() return "DURATION_OBJECT" end,
  },
  C_UnitAuras = { GetAuraDataByIndex = function(unit, i) if i == 1 then return { name = "Aspect of the Hawk", spellId = 13165, auraInstanceID = 77 } end end },
  C_AddOns = { IsAddOnLoaded = function(n) return n == "BugSack" end },
  C_Item = { GetItemNameByID = function() return "Goblin Sapper Charge" end, GetItemIconByID = function() return 133712 end,
             GetItemCount = function(id, bank) return bank and 5 or 3 end },
})
ok(A.ItemName(10646) == "Goblin Sapper Charge" and A.ItemIcon(10646) == 133712, "ItemName/ItemIcon via C_Item")
ok(A.ItemCount(10646) == 3 and A.ItemCount(10646, true) == 5, "ItemCount via C_Item with bank flag")
local n, icon, ct, mn, mx, sid = A.SpellInfo(20904)
ok(n == "Aimed Shot" and icon == 135130 and ct == 2000 and mn == 8 and mx == 35 and sid == 20904, "SpellInfo list shape from C_Spell")
ok(A.SpellName(20904) == "Aimed Shot", "SpellName")
ok(A.SpellIcon(20904) == 135130, "SpellIcon")
ok(A.SpellRank(20904) == "Rank 6", "SpellRank from subtext")
local s, d, e = A.SpellCooldown(20904)
ok(s == 10 and d == 6 and e == true, "SpellCooldown list shape from table")
ok(A.SpellCooldownDuration(20904) == "DURATION_OBJECT", "SpellCooldownDuration passthrough")
ok(A.IsAddOnLoaded("BugSack") == true and A.IsAddOnLoaded("Nope") == false, "IsAddOnLoaded via C_AddOns")
local a = A.AuraByIndex("player", 1, "HELPFUL")
ok(a and a.spellId == 13165 and a.auraInstanceID == 77, "AuraByIndex passthrough")
ok(A.AuraByIndex("player", 2, "HELPFUL") == nil, "AuraByIndex nil past the end")
ok(A.TalentTabInfo() == nil, "TalentTabInfo nil on Forever")
ok(#A.Missing() == 0, "nothing missing on the Forever mock")

-- 2. Anniversary shape: bare globals, C_Spell present but bare preferred for cooldowns.
local B = boot({
  GetSpellInfo = function(id) return "Steady Shot", "Rank 1", 132213, 1500, 8, 35, id end,
  GetSpellTexture = function() return 132213 end,
  GetSpellCooldown = function() return 1, 1.5, 1 end,
  IsAddOnLoaded = function(n) return n == "Dominos" end,
  UnitAura = function(unit, i)
    if i == 1 then return "Aspect of the Hawk", 136076, 1, nil, 0, 0, "player", false, false, 13165, false, false, true end
  end,
  GetTalentTabInfo = function(i) return "Beast Mastery", nil, nil, nil, i == 1 and 41 or 10 end,
  GetItemInfo = function() return "Steam Tonk Controller", "link", 1, 60, 1, "Misc", "Junk", 1, "", 134376 end,
  GetItemCount = function() return 1 end,
})
ok(B.ItemName(22728) == "Steam Tonk Controller", "ItemName via bare GetItemInfo")
ok(B.ItemIcon(22728) == 134376, "ItemIcon via bare GetItemInfo's 10th return")
ok(B.ItemCount(22728) == 1, "ItemCount via bare global")
local n2, icon2, ct2, _, _, sid2 = B.SpellInfo(34120)
ok(n2 == "Steady Shot" and icon2 == 132213 and ct2 == 1500 and sid2 == 34120, "SpellInfo list shape from bare global")
ok(B.SpellRank(34120) == "Rank 1", "SpellRank from bare second return")
local s2, d2, e2 = B.SpellCooldown(34120)
ok(s2 == 1 and d2 == 1.5 and e2 == 1, "SpellCooldown bare passthrough")
ok(B.SpellCooldownDuration(34120) == nil, "no duration object on Anniversary")
ok(B.IsAddOnLoaded("Dominos") == true, "IsAddOnLoaded via bare global")
local b = B.AuraByIndex("player", 1, "HELPFUL")
ok(b and b.name == "Aspect of the Hawk" and b.spellId == 13165 and b.icon == 136076 and b.applications == 1, "AuraByIndex built from UnitAura")
ok(B.AuraByIndex("player", 2, "HELPFUL") == nil, "AuraByIndex nil past the end (bare)")
ok(type(B.TalentTabInfo()) == "function", "TalentTabInfo returns the bare function")

-- 3. Nothing at all: every resolver returns nil and reports itself missing.
local Z = boot({})
ok(Z.SpellName(1) == nil and Z.SpellIcon(1) == nil and Z.SpellCooldown(1) == nil, "nil without any API")
ok(Z.IsAddOnLoaded("x") == false, "IsAddOnLoaded false without any API")
local miss = table.concat(Z.Missing(), ",")
ok(miss:find("SpellInfo") and miss:find("SpellCooldown") and miss:find("AuraByIndex") and miss:find("ItemName"), "Missing lists the unresolved names: " .. miss)
ok(Z.ItemCount(1) == 0 and Z.ItemName(1) == nil and Z.ItemIcon(1) == nil, "item resolvers degrade without any API")

-- Usability + reactive spells (Mongoose Bite on the ready tile, 2026-09-26).
do
  local names = { [1495] = "Mongoose Bite", [36916] = "Mongoose Bite", [19306] = "Counterattack", [3044] = "Arcane Shot" }
  local R = boot({ __forever = true, C_Spell = {
    GetSpellInfo = function(id) return names[id] and { name = names[id] } or nil end,
    IsSpellUsable = function(id) return id == 3044, false end,
  } })
  local u, m = R.SpellUsable(3044)
  ok(u == true and m == false and R.SpellUsable(1495) == false, "SpellUsable via C_Spell.IsSpellUsable")
  ok(R.IsReactiveSpell(1495) and R.IsReactiveSpell(36916) and R.IsReactiveSpell(19306), "Mongoose Bite (any rank) and Counterattack are reactive")
  ok(R.IsReactiveSpell(3044) == false and R.IsReactiveSpell(nil) == false, "Arcane Shot is not; nil is not")
  local G = boot({ IsUsableSpell = function(id) return false, true end })
  local gu, gm = G.SpellUsable(1)
  ok(gu == false and gm == true, "SpellUsable falls back to IsUsableSpell")
  local Z2 = boot({})
  ok(Z2.SpellUsable(1) == nil and Z2.IsReactiveSpell(1495) == false, "no API: nil / not reactive")
end

print(("api_layer: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
