-- Tests/toc_flavour_test.lua
-- Flavour TOC contract: Nock_TBC.toc mirrors Nock.toc, Nock_Camelot.toc lists only
-- existing platform/Forever files with the camelot header, and no _Mainline toc exists.
-- Run from the repo root: luajit Tests/toc_flavour_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local function readAll(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function exists(path) local f = io.open(path, "rb"); if f then f:close(); return true end; return false end
local function files(toc)
  local list = {}
  for line in toc:gmatch("[^\r\n]+") do
    local entry = line:match("^%s*([^#%s][^%s%[]*)")
    if entry then list[#list + 1] = (entry:gsub("\\", "/")) end
  end
  return list
end

local base    = readAll("Nock.toc")
local tbc     = readAll("Nock_TBC.toc")
local camelot = readAll("Nock_Camelot.toc")
ok(base and tbc and camelot, "all three tocs exist")
if not (base and tbc and camelot) then
  print(("toc_flavour: %d passed, %d failed"):format(pass, fail))
  os.exit(1)
end
ok(not exists("Nock_Mainline.toc") and not exists("Nock-Mainline.toc"), "no Mainline toc (it would outrank _Camelot)")
ok(base == tbc, "Nock_TBC.toc is byte-identical to Nock.toc")
ok(camelot:match("^## Interface: 16001") or camelot:match("\n## Interface: 16001"), "camelot Interface 16001")
ok(camelot:match("## AllowLoadGameType: camelot"), "camelot AllowLoadGameType")
ok(camelot:match("## SavedVariables: NockDB"), "camelot shares NockDB")
local bv = base:match("## Version: (%S+)"); local cv = camelot:match("## Version: (%S+)")
ok(bv and bv == cv, "same Version line in both flavours")

local FORBIDDEN = {  -- TBC-only or CLEU-driven: must never be in the Forever list
  "Modules/SwingTimer.lua", "Modules/Rotation.lua", "Modules/ShotPredictor.lua", "Modules/Practice.lua",
  "Modules/Warnings.lua", "Modules/WeaveBind.lua", "Modules/Misdirection.lua", "Modules/SlammerWatch.lua",
  "Modules/RipperWatch.lua", "Modules/BossMarkWatch.lua", "Modules/PetTrainer.lua", "Modules/Profiler.lua",
  "Modules/CastBar.lua", "Modules/ManaTick.lua", "Modules/SapperTracker.lua", "Modules/ActionGlow.lua",
  "UI/Frame_FluffyCluster.lua", "UI/Frame_SwingTimers.lua", "UI/Frame_ShotBars.lua", "UI/Frame_Rotation.lua",
}
local listed = {}
for _, f in ipairs(files(camelot)) do
  listed[f] = true
  ok(exists(f), "camelot lists an existing file: " .. f)
end
for _, f in ipairs(FORBIDDEN) do ok(not listed[f], "camelot does not list " .. f) end
for _, must in ipairs({ "embeds.xml", "Core/Core.lua", "Core/Constants.lua", "Core/Flavor.lua", "Core/API.lua",
  "Core/State.lua", "UI/HUD.lua", "UI/Frame_ReactCluster.lua", "Forever/SwingTimer.lua", "Forever/Probe.lua",
  "Forever/LedgerEngine.lua", "Forever/Snapshot.lua", "Forever/CastBar.lua", "Forever/Cooldowns.lua",
  "UI/Frame_ReactCastBar.lua", "UI/Frame_ReactCooldowns.lua",
  "Modules/AggroWarning.lua", "UI/Frame_AggroWarning.lua", "Forever/RangeFinder.lua",
  "Forever/Auras.lua", "UI/Frame_ReactCorners.lua", "Forever/Buffs.lua", "UI/Frame_ReactBuffs.lua",
  "Forever/ManaTick.lua", "Modules/ManaTickEngine.lua" }) do
  ok(listed[must], "camelot lists " .. must)
end
-- Flavor and API load before anything that calls them.
local order = files(camelot)
local pos = {}
for i, f in ipairs(order) do pos[f] = i end
ok(pos["Core/Flavor.lua"] and pos["Core/State.lua"] and pos["Core/Flavor.lua"] < pos["Core/State.lua"], "Flavor before State")
ok(pos["Core/API.lua"] and pos["Core/API.lua"] < pos["Core/State.lua"], "API before State")
ok(pos["Forever/Spells.lua"] and pos["Forever/SwingTimer.lua"] and pos["Forever/Spells.lua"] < pos["Forever/SwingTimer.lua"], "Spells before SwingTimer")
ok(pos["Forever/Spells.lua"] and pos["Config/Options.lua"] and pos["Forever/Spells.lua"] < pos["Config/Options.lua"], "Spells before Options (constants override)")
ok(pos["Forever/LedgerEngine.lua"] and pos["Forever/Cooldowns.lua"] and pos["Forever/LedgerEngine.lua"] < pos["Forever/Cooldowns.lua"], "LedgerEngine before Cooldowns")
ok(pos["Forever/Snapshot.lua"] and pos["Forever/Snapshot.lua"] < pos["Forever/Cooldowns.lua"], "Snapshot before Cooldowns (Nock.Restricted)")
ok(pos["UI/Frame_ReactCluster.lua"] and pos["UI/Frame_ReactCastBar.lua"] and pos["UI/Frame_ReactCluster.lua"] < pos["UI/Frame_ReactCastBar.lua"], "cluster before its glued cast bar")
ok(pos["Modules/ManaTickEngine.lua"] and pos["Forever/ManaTick.lua"] and pos["Modules/ManaTickEngine.lua"] < pos["Forever/ManaTick.lua"], "engine before the Forever mana tick")

print(("toc_flavour: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
