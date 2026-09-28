-- Tests/custom_sounds_options_test.lua
-- Alerts -> Sounds -> Your sounds (Config/Options.lua): hidden on TBC, the add form, the message line, the list rows.
-- Run from the repo root: luajit Tests/custom_sounds_options_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local h = dofile("Tests/lib/options_harness.lua")
local Nock, W, opts = h()
function Nock:Print(m) print("Print: " .. tostring(m)) end
function Nock:NewModule() return {} end
dofile("Forever/CustomSounds.lua")
local CS = Nock.CustomSounds

-- LSM with a working Register/Fetch for this test.
local held = {}
local lsm = LibStub("LibSharedMedia-3.0")
lsm.Register = function(_, t, k, d) if held[k] ~= nil then return false end; held[k] = d; return true end
lsm.Fetch = function(_, t, k) return held[k] end
local played = {}
_G.PlaySoundFile = function(v, ch) played[#played + 1] = { v, ch }; return v ~= "Interface\\AddOns\\NockSounds\\missing.mp3" end

local function nodeAt(root, path)
  local n = root
  for seg in path:gmatch("[^%.]+") do n = n.args and n.args[seg]; if type(n) ~= "table" then return nil end end
  return n
end

local tab = nodeAt(opts, "alerts.sounds.custom")
ok(tab and tab.type == "group" and tab.name == "Your sounds", "tab exists")
if not tab then
  print(("custom_sounds_options_test: %d passed, %d failed"):format(pass, fail))
  os.exit(1)
end
ok(tab.hidden() == true, "hidden on TBC")
Nock.Flavor.forever = true
ok(tab.hidden() == false, "shown on Forever")

Nock.db.global.customSounds = {}
Nock:RebuildOptionsArgs()
tab = nodeAt(opts, "alerts.sounds.custom")
local a = tab.args
for _, k in ipairs({ "intro", "customSoundAddName", "customSoundAddFile", "customSoundAddTest", "customSoundAddBtn", "customSoundMsg" }) do
  ok(a[k] ~= nil, "row " .. k)
end
ok(a.customSound_1_lbl == nil, "empty list -> no rows")
ok(a.customSoundAddBtn.disabled() == true, "Add disabled with nothing typed")
ok(a.customSoundMsg.hidden() == true, "no message with nothing typed")

-- typing a bad file shows the reason
a.customSoundAddName.set(nil, "Ding")
a.customSoundAddFile.set(nil, "ding.wav")
ok(a.customSoundAddBtn.disabled() == true, "Add disabled for a .wav")
ok(a.customSoundMsg.hidden() == false and a.customSoundMsg.name():find(CS.MSG.FORMAT, 1, true), "message shows the format rule")

-- a good file: Test reports missing (file not there yet) but Add stays enabled
a.customSoundAddFile.set(nil, "missing.mp3")
a.customSoundAddTest.func()
ok(played[#played] and played[#played][1] == "Interface\\AddOns\\NockSounds\\missing.mp3", "Test plays the resolved path")
ok(a.customSoundMsg.name():find("restart", 1, true), "Test on a missing file says restart")
ok(a.customSoundAddBtn.disabled() == false, "Add still allowed when Test found nothing")

-- Add: stored, registered, form cleared, row built
a.customSoundAddFile.set(nil, "ding.mp3")
a.customSoundAddBtn.func()
local list = Nock.db.global.customSounds
ok(#list == 1 and list[1].name == "Ding" and list[1].source == "ding.mp3", "entry stored as typed")
ok(held["Custom: Ding"] == "Interface\\AddOns\\NockSounds\\ding.mp3", "registered into LSM on Add")
tab = nodeAt(opts, "alerts.sounds.custom"); a = tab.args
ok(a.customSoundAddName.get() == "" and a.customSoundAddFile.get() == "", "form cleared after Add")
ok(a.customSound_1_lbl and a.customSound_1_lbl.name == "Ding", "row label is the name")
ok(a.customSound_1_file and a.customSound_1_file.name == "ding.mp3", "row shows the source as typed")
a.customSound_1_test.func()
ok(played[#played][1] == "Interface\\AddOns\\NockSounds\\ding.mp3", "row Test plays the entry")

-- duplicate name blocked
a.customSoundAddName.set(nil, "ding")
a.customSoundAddFile.set(nil, "other.mp3")
ok(a.customSoundAddBtn.disabled() == true and a.customSoundMsg.name():find(CS.MSG.DUP_NAME, 1, true), "duplicate name blocked with a reason")

-- remove: gone from the list, message says /reload; same name + other sound now STALE
a.customSound_1_rm.func()
ok(#Nock.db.global.customSounds == 0, "removed from the list")
tab = nodeAt(opts, "alerts.sounds.custom"); a = tab.args
ok(a.customSound_1_lbl == nil, "row gone")
ok(a.customSoundMsg.name():find("/reload", 1, true), "removal message mentions /reload")
a.customSoundAddName.set(nil, "Ding")
a.customSoundAddFile.set(nil, "other.mp3")
ok(a.customSoundAddBtn.disabled() == true and a.customSoundMsg.name():find(CS.MSG.STALE, 1, true), "re-adding the name with another sound this session -> STALE")

-- remove from a stale row removes THAT entry, not whatever now sits at its index
Nock.db.global.customSounds = { { name = "A", source = "a.mp3" }, { name = "B", source = "b.mp3" }, { name = "C", source = "c.mp3" } }
Nock:RebuildOptionsArgs()
a = nodeAt(opts, "alerts.sounds.custom").args
local rmB = a.customSound_2_rm.func
a.customSound_1_rm.func()
rmB()
local names = {}
for _, e in ipairs(Nock.db.global.customSounds) do names[#names + 1] = e.name end
ok(table.concat(names, ",") == "C", "stale X on B removes B, got " .. table.concat(names, ","))
rmB()
ok(#Nock.db.global.customSounds == 1, "a second stale click removes nothing")
a = nodeAt(opts, "alerts.sounds.custom").args

-- no key contains Preview (would be tagged Advanced)
for k in pairs(a) do ok(not tostring(k):find("Preview", 1, true), "no Preview key: " .. tostring(k)) end

print(("custom_sounds_options_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
