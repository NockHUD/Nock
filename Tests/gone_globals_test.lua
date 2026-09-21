-- Tests/gone_globals_test.lua
-- No file listed in Nock_Camelot.toc calls a bare global that the Forever client
-- lacks, outside Core/API.lua. Guarded reads must be spelled `_G.Name`.
-- Run from the repo root: luajit Tests/gone_globals_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local function readAll(path) local f = io.open(path, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end

-- Gone on Forever (devkit dumps/16001 + PORTING.md); C_* homes exist for each.
local GONE = {
  "GetSpellInfo", "GetSpellTexture", "GetSpellCooldown", "IsSpellInRange", "IsUsableSpell", "GetSpellDescription",
  "GetItemInfo", "GetItemCount", "GetItemCooldown", "GetItemSpell", "GetItemIcon", "GetItemInfoInstant",
  "GetContainerItemInfo", "GetContainerNumSlots", "GetContainerNumFreeSlots", "GetContainerItemLink", "GetContainerItemID",
  "PickupContainerItem", "UseContainerItem", "UnitAura", "UnitBuff", "UnitDebuff",
  "GetTalentInfo", "GetNumTalents", "GetTalentTabInfo", "GetNumTalentTabs",
  "GetNumRaidMembers", "GetNumPartyMembers", "IsAddOnLoaded", "GetNumAddOns", "GetCoinTextureString",
  "CombatLogGetCurrentEventInfo", "GetNumCrafts", "GetCraftInfo", "DoCraft", "GetPetHappiness", "GetPetTrainingPoints",
  "InterfaceOptionsFrame", "InterfaceOptions_AddCategory", "OpacitySliderFrame",
}
local toc = readAll("Nock_Camelot.toc"); ok(toc, "Nock_Camelot.toc readable")
local files = {}
for line in toc:gmatch("[^\r\n]+") do
  local entry = line:match("^%s*([^#%s][^%s%[]*)")
  if entry and entry:match("%.lua$") then files[#files + 1] = (entry:gsub("\\", "/")) end
end
ok(#files > 20, "camelot lists lua files")
for _, f in ipairs(files) do
  -- Core/API.lua is the one resolver; Forever/Probe.lua names APIs in its
  -- report labels on purpose (it calls them only through _G / C_* lookups).
  if f ~= "Core/API.lua" and f ~= "Rotations/Profiles.lua" and f ~= "Forever/Probe.lua" then
    local src = readAll(f)
    if src then
      -- strip comments so a mention in prose doesn't count
      src = src:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
      for _, g in ipairs(GONE) do
        -- a bare use: not preceded by `.`, `:`, `_G.` or an identifier char
        local hit = src:find("[^%w_%.:]" .. g .. "%s*[%(]") or src:find("^" .. g .. "%s*[%(]")
        local guardedOnly = not hit
        ok(guardedOnly, ("%s uses bare %s (route through Nock.API or spell it _G.%s)"):format(f, g, g))
      end
    end
  end
end
print(("gone_globals: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
