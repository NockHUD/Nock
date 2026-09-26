-- Tests/options_forever_test.lua
-- Config/OptionsForever.lua prunes the built options tree to what runs on WoW
-- Forever: General, the React page as "Nock HUD", Profiles; every TBC-only
-- family, tab and row is gone. Run from the repo root: luajit Tests/options_forever_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local h = dofile("Tests/lib/options_harness.lua")
local Nock, W, opts = h()
dofile("Config/OptionsForever.lua")
-- The aspect ring page reads the ring's pure layout helpers.
dofile("Forever/Spells.lua")
function Nock:NewModule() return { RegisterEvent = function() end, RegisterMessage = function() end } end
dofile("Forever/AspectRing.lua")
ok(type(Nock.OptionsForever) == "function" or type(Nock.OptionsForever) == "table", "OptionsForever registered")
local F = Nock.OptionsForever

local function nodeAt(root, path)
  local n = root
  for seg in path:gmatch("[^%.]+") do n = n.args and n.args[seg]; if type(n) ~= "table" then return nil end end
  return n
end

-- Before: the TBC tree is whole.
ok(nodeAt(opts, "hud.classic") and nodeAt(opts, "utilities.practice") and nodeAt(opts, "hud.react.tabGrid"), "harness built the full TBC tree")

F.Apply(opts)

-- Families.
local top = {}
for k, v in pairs(opts.args) do if type(v) == "table" and v.type == "group" then top[#top + 1] = k end end
table.sort(top)
ok(table.concat(top, ",") == "alerts,general,hud,profiles,utilities", "alerts/general/hud/profiles/utilities remain, got " .. table.concat(top, ","))
-- Utilities keeps only Quality of life (Modules/QoL.lua runs on Forever).
ok(nodeAt(opts, "utilities.qol") ~= nil and nodeAt(opts, "utilities.qol.qolFog") ~= nil, "utilities: the Quality of life page with the camera card")
-- The Error messages card: both rows kept, shown on Forever, hidden on TBC.
do
  local he, ms = nodeAt(opts, "utilities.qol.qolHideErrors"), nodeAt(opts, "utilities.qol.qolMuteErrorSpeech")
  ok(he and ms and he.type == "toggle" and ms.type == "toggle", "qol: error text + speech toggles kept")
  local was = Nock.Flavor
  Nock.Flavor = { forever = true }
  ok(he and he.hidden() == false and ms.hidden() == false, "qol: error rows shown on Forever")
  Nock.Flavor = { forever = false }
  ok(he and he.hidden() == true and ms.hidden() == true, "qol: error rows hidden on TBC")
  Nock.Flavor = was
end
local upages = {}
for k, v in pairs(nodeAt(opts, "utilities").args) do if type(v) == "table" and v.type == "group" then upages[#upages + 1] = k end end
table.sort(upages)
ok(#upages == 2 and upages[1] == "aspectRing" and upages[2] == "qol", "utilities: Quality of life + Aspect ring, got " .. table.concat(upages, ","))
-- The aspect ring page (Forever/AspectRing.lua): the key and the dial.
do
  local key = nodeAt(opts, "utilities.aspectRing.aspectRingKey")
  ok(key and key.type == "keybinding" and key.name == "Aspect ring key", "aspect ring: key row")
  ok(nodeAt(opts, "utilities.aspectRing.keyHeader") and nodeAt(opts, "utilities.aspectRing.dialHeader"), "aspect ring: two cards (Key, Dial)")
  local sent = {}
  Nock.SendMessage = function(_, m) sent[#sent + 1] = m end
  Nock.db.profile.aspectRingKey = nil
  ok(key.get() == "", "key: unset reads empty")
  key.set(nil, "SHIFT-Q")
  ok(Nock.db.profile.aspectRingKey == "SHIFT-Q" and sent[#sent] == "NOCK_ASPECT_RING_CONFIG", "key: saved and the ring told")
  local size = nodeAt(opts, "utilities.aspectRing.aspectRingScale")
  ok(size and size.type == "range" and size.min == 0.75 and size.max == 2 and size.isPercent and size.get() == 1, "aspect ring: size slider, 100% by default")
  size.set(nil, 1.25)
  ok(Nock.db.profile.aspectRingScale == 1.25 and sent[#sent] == "NOCK_ASPECT_RING_CONFIG", "size: saved and the ring told")
  Nock.db.profile.aspectRingScale = nil
  local names = { "Up", "Up-right", "Down-right", "Down", "Down-left", "Up-left" }
  for i = 1, 6 do
    local d = nodeAt(opts, "utilities.aspectRing.aspectRingDir" .. i)
    ok(d and d.type == "select" and d.name == names[i], "dial row " .. i .. ": " .. names[i])
  end
  local up, down = nodeAt(opts, "utilities.aspectRing.aspectRingDir1"), nodeAt(opts, "utilities.aspectRing.aspectRingDir4")
  local vals = up.values()
  ok(vals.hawk and vals.cheetah and vals.beast and #up.sorting == 6 and up.sorting[1] == "hawk", "dial: six aspects, default order")
  Nock.db.profile.aspectRingOrder = nil
  ok(up.get() == "hawk" and down.get() == "cheetah", "dial: the default layout")
  up.set(nil, "cheetah")
  ok(up.get() == "cheetah" and down.get() == "hawk" and sent[#sent] == "NOCK_ASPECT_RING_CONFIG", "dial: picking Cheetah for Up swaps Hawk down, ring told")
  local reset = nodeAt(opts, "utilities.aspectRing.aspectRingDefault")
  ok(reset and reset.type == "execute", "dial: default-layout button")
  reset.func()
  ok(Nock.db.profile.aspectRingOrder == nil and up.get() == "hawk", "default layout restores Hawk up")
  ok(not W.IsAdvanced(key) and not W.IsAdvanced(up), "key and dial rows are Simple")
end
local uintro = nodeAt(opts, "utilities.intro")
ok(uintro and type(uintro.name) == "string" and not uintro.name:find("mailbox") and uintro.name:find("camera"), "utilities: the intro no longer lists the TBC toolbox")
ok(nodeAt(opts, "alerts.aggro") ~= nil, "aggro page kept")
for _, p in ipairs({ "alerts.helpers", "alerts.warnings.settings.noReleasePreview", "alerts.sounds.deadZone", "alerts.sounds.warnings", "alerts.sounds.weave", "alerts.sounds.other" }) do ok(nodeAt(opts, p) == nil, p .. " gone") end
ok(nodeAt(opts, "alerts.sounds") ~= nil, "sounds page kept for the Range tab")
ok(nodeAt(opts, "alerts.warnings") ~= nil and nodeAt(opts, "alerts.warnings.settings.previewButton") ~= nil, "warnings page kept with its preview (Forever/Warnings.lua supplies the catalog)")

-- HUD: React only, renamed.
ok(nodeAt(opts, "hud.react") ~= nil, "react page kept")
ok(nodeAt(opts, "hud.classic") == nil and nodeAt(opts, "hud.fluffy") == nil, "classic and fluffy pages gone")
ok(nodeAt(opts, "hud.react").name == "Nock HUD", "react page renamed to Nock HUD")
ok(nodeAt(opts, "hud.hudMode") == nil and nodeAt(opts, "hud.react.hudMode") == nil and nodeAt(opts, "hud.react.useLook") == nil, "hud mode switches gone")

-- Tabs without a module or a feed in M1.
for _, p in ipairs({ "hud.react.tabBuff", "hud.react.tabRange", "hud.react.tabBars.grpEngine",
                     "hud.react.tabGrid.reactConsumablesAlways", "hud.react.tabGrid.reactKcProcGlow",
                     "hud.react.tabGrid.reactRaptorGoGlow", "hud.react.tabGrid.kcActionBarGlow" }) do
  ok(nodeAt(opts, p) == nil, p .. " gone")
end
ok(nodeAt(opts, "hud.react.tabGrid.gridGcdSwipe") and nodeAt(opts, "hud.react.tabGrid.gridIconZoom"), "grid: GCD swipe and icon zoom kept on Forever")
for _, p in ipairs({ "hud.react.tabBars", "hud.react.tabSize", "hud.react.tabSkin", "hud.react.tabGrid" }) do
  ok(nodeAt(opts, p) ~= nil, p .. " kept")
end

-- Rows without a feed on Forever.
for _, p in ipairs({
  "hud.react.tabBars.reactShowBrackets", "hud.react.tabBars.reactShowClipTicks", "hud.react.tabBars.reactShowDelay",
  "hud.react.tabBars.reactShowGcdDivider", "hud.react.tabBars.reactShowNotation",
  "hud.react.tabSize.reactShowAutoShotCast",
  "hud.react.tabSize.reactMeleeStageCue",
  "hud.react.tabSkin.reactColorTickSteady", "hud.react.tabSkin.reactTickSteadyWidth", "hud.react.tabSkin.reactTickMultiWidth",
  "hud.react.tabSkin.reactColorTickMulti", "hud.react.tabSkin.reactColorBracket", "hud.react.tabSkin.reactGcdDividerWidth",
  "general.grpCastBar", "general.grpSetup", "general.grpLook", "general.perfPanel",
}) do
  ok(nodeAt(opts, p) == nil, p .. " gone")
end
for _, p in ipairs({
  "hud.react.tabBars.reactDirAuto", "hud.react.tabBars.reactDirMelee",
  "hud.react.tabSize.reactShowAutoBar", "hud.react.tabSize.reactShowMeleeBar", "hud.react.tabSize.reactShowManaBar",
  "hud.react.tabSize.reactScale", "hud.react.tabSize.reactWidth", "hud.react.tabSize.order_up_1",
  "hud.react.tabSize.reactShowCastBar", "hud.react.tabSize.castBarCard", "hud.react.tabSize.reactShowGrid",
  "hud.react.tabSize.reactCastH", "hud.react.tabSkin.reactColorCastFill",
  "hud.react.tabSize.reactShowRangeBar", "hud.react.tabSize.reactShowAspectIcon", "hud.react.tabSize.reactShowMarkIcon",
  "hud.react.tabSize.cornersCard", "hud.react.tabSize.reactCornerIconSize", "hud.react.tabProcs.reactBuffIconSize", "hud.react.tabProcs.reactBuffRowsF", "hud.react.tabProcs.procNowRefresh", "hud.react.tabProcs.procPinAdd", "hud.react.tabProcs.procHideAdd", "hud.react.tabSkin.reactColorRangeSweet",
  "hud.react.tabSize.reactManaTick", "hud.react.tabSize.reactManaTickDirCombat",
  "hud.react.tabSize.reactAutoH", "hud.react.tabSize.barHeightsCard", "hud.react.tabSkin.reactColorAutoFill", "hud.react.tabSkin.reactFont", "hud.react.tabSkin.reactBarTexture",
  "general.scale", "general.lockAll", "general.minimapIcon", "general.grpMedia", "general.grpVisibility", "general.editGridShow",
  "profiles.stock", "profiles.sharing",
}) do
  ok(nodeAt(opts, p) ~= nil, p .. " kept")
end

-- The Range Finder ladder (2026-09-24): the range-bar row reads as the ladder,
-- the segment-labels row survives the prune.
local rb = nodeAt(opts, "hud.react.tabSize.reactShowRangeBar")
ok(rb and rb.name == "Range Finder" and (rb.desc or ""):find("bracket"), "range bar row renamed to Range Finder")
ok(nodeAt(opts, "hud.react.tabSize.reactRangeLabels") ~= nil, "segment labels row kept on Forever")
ok(nodeAt(opts, "hud.react.tabSize.reactRangeStyle") ~= nil, "Range Finder style row kept on Forever")

-- Idempotent: a second Apply (RebuildOptionsArgs re-applies) changes nothing.
local before = 0
local function count(n) local c = 0; for _, v in pairs(n.args or {}) do if type(v) == "table" then c = c + 1 + count(v) end end; return c end
before = count(opts)
F.Apply(opts)
ok(count(opts) == before, "second Apply is a no-op")

-- The hook is wired in both registration paths and only the Camelot toc loads the file.
local function readAll(p) local f = io.open(p, "rb"); local s = f:read("*a"); f:close(); return s end
local src = readAll("Config/Options.lua")
local _, hooks = src:gsub("OptionsForever%.Apply", "")
ok(hooks == 2, "Options.lua applies OptionsForever in RegisterOptions and RebuildOptionsArgs (found " .. hooks .. ")")
ok(readAll("Nock_Camelot.toc"):find("Config\\OptionsForever.lua", 1, true) ~= nil, "Camelot toc lists OptionsForever")
ok(readAll("Nock.toc"):find("OptionsForever", 1, true) == nil, "TBC toc does not list OptionsForever")

-- The spell-queue mark keeps the wind-up pair's width and colour, renamed.
local qw = nodeAt(opts, "hud.react.tabSkin.reactTickWindupWidth")
local qc = nodeAt(opts, "hud.react.tabSkin.reactColorTickWindup")
ok(qw and qw.name == "Spell-queue mark width" and (qw.desc or ""):find("spell%-queue"), "queue mark width kept and renamed")
ok(qc and qc.name == "Spell-queue mark" and (qc.desc or ""):find("SpellQueueWindow"), "queue mark colour kept and renamed")
ok((nodeAt(opts, "hud.react.tabSkin.autoMarksHeader") or {}).name == "Spell-queue mark", "marks header renamed")
local qt = nodeAt(opts, "hud.react.tabBars.showWindupMark")
ok(qt and qt.type == "toggle" and qt.name == "Spell-queue mark" and (qt.desc or ""):find("SpellQueueWindow"), "queue mark toggle on the Bars tab, renamed")
-- The one feature switch the auto bar has on Forever is reachable in Simple.
ok(qt and not W.IsAdvanced(qt), "queue mark toggle is Simple on Forever")
-- The Skin card's table: the dropped Steady/Multi/bracket/GCD lines are gone
-- (no empty labelled rows) and the wind-up line reads as the queue mark.
local card = nodeAt(opts, "hud.react.tabSkin.autoShotColoursCard")
local spec = card and W.Meta(card) and W.Meta(card).table
local labels = {}
for _, rs in ipairs(spec and spec.rows or {}) do labels[#labels + 1] = rs[1] end
ok(spec and table.concat(labels, ","):find("Spell%-queue mark") and not table.concat(labels, ","):find("Wind%-up"), "Forever skin table line relabelled, got " .. table.concat(labels, ","))
W.SetMode("advanced")
local skinCards = W.Cards({ key = "tabSkin", name = "Skin", node = nodeAt(opts, "hud.react.tabSkin"), path = { "hud", "react", "tabSkin" } }, "Nock")
local drawn
for _, c in ipairs(skinCards) do if c.tableRows and c.name == "Auto Shot colours" then drawn = c.tableRows end end
local dl = {}
for _, r in ipairs(drawn and drawn.rows or {}) do dl[#dl + 1] = r.label .. "(" .. #r.cells[1] .. "," .. #r.cells[2] .. ")" end
ok(drawn and #drawn.rows == 1 and drawn.rows[1].label == "Spell-queue mark" and #drawn.rows[1].cells[1] == 1 and #drawn.rows[1].cells[2] == 1, "drawn skin table: one line, colour + width; got " .. table.concat(dl, ",") .. " cards=" .. #skinCards)
ok(drawn and not drawn.one, "drawn skin table: the surviving line is drawn WITH its label (2026-09-23: it drew colour + width and nothing to say what for)")

ok(nodeAt(opts, "general.runWizard") and nodeAt(opts, "general.runWizardGuided"), "Forever keeps both wizard buttons")

-- The Buff Row tab on Forever (user, 2026-09-26): the row's switch and size,
-- the buffs up now with Pin / Hide (read out of combat), and the pin and
-- hide lists as icon tables with an add form.
do
  Nock.Flavor.forever = true
  dofile("Forever/AuraRow.lua")
  local auras = {
    { spellId = 6150, name = "Quick Shots", icon = 11, sourceUnit = "player", duration = 12 },
    { spellId = 28520, name = "Flask of Relentless Assault", icon = 12, sourceUnit = "player", duration = 7200 },
  }
  Nock.AuraCache = {
    ForEach = function(_, fn) for _, a in ipairs(auras) do fn(a) end end,
    ByName = function(_, n) for _, a in ipairs(auras) do if a.name == n then return a end end end,
  }
  local combat = false
  _G.InCombatLockdown = function() return combat end
  local p = Nock.db.profile
  p.reactBuffCustom, p.foreverBuffHide, p.hudMode = { 28520 }, {}, "react"
  Nock:RebuildOptionsArgs()
  local t = nodeAt(opts, "hud.react.tabProcs")
  ok(t and t.hidden() == false, "buff row tab shown on Forever")
  for _, k in ipairs({ "buffRowCard", "buffsUpNowCard", "pinnedBuffsCard", "hiddenBuffsCard" }) do
    ok(t and t.args[k] and t.args[k].type == "header" and not t.args[k].hidden, "buff row tab: card " .. k)
  end
  local a = t.args
  ok(a.procNow_1_lbl and a.procNow_1_lbl.name:find("Quick Shots", 1, true) and a.procNow_1_lbl.name:find("6150", 1, true)
     and a.procNow_1_lbl.name:find("shown", 1, true), "buffs up now: Quick Shots first, with its id and 'shown'")
  ok(a.procNow_2_lbl and a.procNow_2_lbl.name:find("pinned", 1, true) and a.procNow_2_pin.name == "Unpin", "a pinned buff says so and offers Unpin")
  ok(a.procNow_1_hide.name == "Hide" and a.procNowNote.hidden() == true, "Hide offered; the empty note hidden while buffs are listed")
  ok(a.procPin_1_lbl and a.procPin_1_lbl.name:find("28520", 1, true) and a.procPin_1_rm.name == "X", "pinned list: a row with its remove button")
  ok(a.procPinNote.hidden() == true and a.procHideNote.hidden() == false, "empty-list notes: pinned has rows, hidden says nothing hidden")
  -- Hide from the buffs-up-now list: stored, the tab rebuilt.
  a.procNow_1_hide.func()
  ok(p.foreverBuffHide[1] == 6150, "Hide writes the hide list")
  a = nodeAt(opts, "hud.react.tabProcs").args
  ok(a.procNow_1_hide.name == "Unhide" and a.procHide_1_lbl and a.procHide_1_lbl.name:find("6150", 1, true), "rebuilt: Unhide offered, the hidden list shows it")
  -- Pinning a hidden id moves it: one list at a time.
  a.procNow_1_pin.func()
  ok(p.reactBuffCustom[2] == 6150 and #p.foreverBuffHide == 0, "pin takes the id off the hide list")
  -- The add form: a name up now resolves to the aura's own id.
  a = nodeAt(opts, "hud.react.tabProcs").args
  a.procHideAdd.set(nil, "Flask of Relentless Assault")
  ok(a.procHideAddBtn.disabled() == false, "add enabled for a resolvable name")
  a.procHideAddBtn.func()
  ok(p.foreverBuffHide[1] == 28520 and a.procHideAdd.get() == "", "added by name, the field cleared")
  a = nodeAt(opts, "hud.react.tabProcs").args
  a.procHideAdd.set(nil, "Not A Buff")
  ok(a.procHideAddBtn.disabled() == true, "add disabled for an unknown name")
  -- In combat nothing is read: the list empties, the note says why.
  combat = true
  Nock:RebuildOptionsArgs()
  a = nodeAt(opts, "hud.react.tabProcs").args
  ok(a.procNow_1_lbl == nil and a.procNowNote.hidden() == false and a.procNowNote.name() == "Leave combat to list your buffs.", "in combat: no list, the note explains")
  combat = false
  Nock.Flavor.forever = false
end

print(("options_forever: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
