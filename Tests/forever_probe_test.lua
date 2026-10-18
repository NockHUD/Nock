-- Tests/forever_probe_test.lua
-- Forever/Probe.lua: Format() renders a plain data table into the copybox text
-- and the cast ring keeps the last N own casts. Run: luajit Tests/forever_probe_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

_G.GetTime = function() return 500 end
local Nock = { Flavor = { forever = true, toc = 16001, Plain = function(v) return v end }, API = { Missing = function() return {} end }, UI = {} }
local module
function Nock:NewModule(name) module = { name = name, events = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  return module end
function Nock:GetModule() return nil end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/Probe.lua")

ok(module and module.name == "ForeverProbe", "module ForeverProbe")
local Probe = Nock.ForeverProbe
ok(type(Probe.Format) == "function", "Format exists")

-- `/nock probe tracking`: the tracking list, the target's type, the talent.
do
  Nock.TrackingForCreatureType = function(t) return t == "Beast" and 1494 or nil end   -- Forever/Tracking.lua's, stubbed
  local rep = Probe.TrackingReport({
    list = { { name = "Track Beasts", active = true, spellID = 1494 }, { name = "Find Herbs", active = false } },
    creatureType = "Beast", typeNames = { [1] = "Beast", [7] = "Humanoid" },
    rank = 2, improvedId = nil,
    talents = { { name = "Improved Tracking", spellID = 999001, rank = 2 } },
    state = { activeId = 1494, targetTrackId = 1494, wrong = false, known = { [1494] = true } },
  })
  ok(rep:find("Track Beasts") and rep:find("ON") and rep:find("Find Herbs"), "tracking rows with the active flag")
  ok(rep:find("creature type: Beast") and rep:find("1 = Beast") and rep:find("wants 1494"), "the target's type, the client's names, the need")
  ok(rep:find("Improved Tracking") and rep:find("999001") and rep:find("rank 2"), "the talent row with its spell id (to pin)")
  ok(rep:find("activeId 1494") and rep:find("wrong false"), "state")
  ok(Probe.TrackingReport({}):find("no tracking list"), "no API: says so")
end

local text = Probe.Format({
  build = "1.60.1 (69913)", toc = 16001, forever = true,
  restrictions = { { "Combat", "Active" }, { "Encounter", "Inactive" }, { "Map", "Inactive" }, { "Chat", "Inactive" } },
  secrets = { { "ShouldAurasBeSecret", "true" }, { "ShouldCooldownsBeSecret", "true" } },
  combatLogRestricted = "true",
  missingApis = { "SpellCooldown" },
  reads = { { "UnitRangedDamage", "secret" }, { "UnitPower", "secret" }, { "UnitThreatSituation", "3" } },
  swings = { { t = 10.0, swingType = 2, duration = 2.174 }, { t = 12.17, swingType = 2, duration = 2.174 } },
  casts = { { t = 11.0, ev = "UNIT_SPELLCAST_START", spellID = 75, castBarID = "cb1" }, { t = 11.4, ev = "UNIT_SPELLCAST_SUCCEEDED", spellID = 75 } },
  castingInfo = "nil",
})
ok(text:find("build 1.60.1 (69913)  toc 16001  forever true", 1, true), "header line")
ok(text:find("Combat=Active", 1, true) and text:find("Chat=Inactive", 1, true), "restriction states")
ok(text:find("ShouldAurasBeSecret=true", 1, true), "secret predicates")
ok(text:find("combat log restricted: true", 1, true), "combat log line")
ok(text:find("missing APIs: SpellCooldown", 1, true), "missing apis")
ok(text:find("UnitRangedDamage=secret", 1, true) and text:find("UnitThreatSituation=3", 1, true), "reads")
ok(text:find("+2.170  Ranged  2.174", 1, true), "swing gap line (second swing minus first)")
ok(text:find("UNIT_SPELLCAST_START  75  cb1", 1, true), "cast line with castBarID")
ok(text:find("UnitCastingInfo: nil", 1, true), "casting info line")

-- cast ring
module:OnEnable()
ok(module.events["UNIT_SPELLCAST_START"] and module.events["UNIT_SPELLCAST_SUCCEEDED"] and module.events["UNIT_SPELLCAST_STOP"], "cast events registered")
for i = 1, 305 do module:OnCast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1000 + i, nil) end
module:OnCast("UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 9, nil)
local casts = module:Casts()
ok(#casts == 300 and casts[#casts].spellID == 1305 and casts[1].spellID == 1006, "ring keeps the last 300 player casts only (one dummy session)")

-- `/nock probe aura <name> [id]`: waits for the named player aura (a short
-- proc cannot be caught by hand), then reports how the cache stored it.
local ticks, cancelled = {}, false
function Nock:Print() end
_G.C_Timer = { NewTicker = function(iv, fn, n) local t = { Cancel = function() cancelled = true end }; ticks[#ticks + 1] = { fn = fn, t = t, n = n }; return t end }
_G.issecretvalue = function(v) return v == "SECRET" end
local shown
Nock.UI.ShowCopyBox = function(text) shown = text end
local rec
Nock.AuraCache = { ByName = function(u, n) return rec end, BySpell = function(u, id) return rec and rec.spellId == id and rec or nil end }
Nock.state = { ledgerBuffs = { n = 1, { icon = 77, exp = 512 } } }
module:WatchAura("Quick Shots", 6150)
ok(#ticks == 1 and ticks[1].n == 240, "watch polls for two minutes")
ticks[1].fn(ticks[1].t)
ok(shown == nil and not cancelled, "nothing yet while the aura is absent")
rec = { spellId = 6150, name = "Quick Shots", duration = 12, expirationTime = 512, auraInstanceID = 9, icon = 77 }
ticks[1].fn(ticks[1].t)
ok(cancelled and shown and shown:find("spellId: number 6150", 1, true) and shown:find("== 6150: true", 1, true) and shown:find("BySpell(6150): hit", 1, true), "found: type, equality and the id lookup reported")
ok(shown:find("ledger row: yes", 1, true), "found: whether the buff row carries it")
-- The buff row's own state rides along, so "ledger yes, row no" can be read
-- off one box: enabled, shown, visible, alpha, item count, first slot.
local fakeFrame = { IsShown = function() return true end, IsVisible = function() return false end, GetAlpha = function() return 1 end,
  GetWidth = function() return 288 end, GetHeight = function() return 28 end, GetParent = function() return nil end }
local fakeSlot = { IsShown = function() return false end, icon = { GetTexture = function() return 132347 end } }
local Row = { IsEnabled = function() return true end, frame = fakeFrame, _items = { n = 1 }, _lastN = 1, _slots = { fakeSlot } }
function Nock:GetModule(name) if name == "ReactBuffs" then return Row end return nil end
Nock.db = { profile = { reactBuffRows = true, hideOoc = false, opacityOoc = 0.5 } }
Nock.WizardHides = function() return false end
Nock.state.player = { inCombat = false }
local rowRep = Probe.RowState()
ok(rowRep:find("row enabled: true", 1, true) and rowRep:find("shown: true  visible: false  alpha: 1", 1, true), "row state: enabled, shown, visible, alpha")
ok(rowRep:find("items: 1  lastN: 1", 1, true) and rowRep:find("slot1 shown: false  texture: 132347", 1, true), "row state: items and first slot")
ok(rowRep:find("inCombat: false  hideOoc: false  opacityOoc: 0.5", 1, true), "row state: combat and ooc settings")
-- The C_Traits walk behind `/nock probe talents`.
do
  local R = Probe.TraitReport
  ok(R({}) == "C_Traits: missing", "no C_Traits: said so")
  local T = {
    GetConfigInfo = function(c) return { treeIDs = { 77 } } end,
    GetTreeNodes = function(t) return { 1, 2 } end,
    GetNodeInfo = function(c, n) return { entryIDs = { n * 10 }, activeRank = n == 2 and 1 or 0, maxRanks = 1 } end,
    GetEntryInfo = function(c, e) return { definitionID = e + 1 } end,
    GetDefinitionInfo = function(d) return { spellID = d == 21 and 555 or 444 } end,
  }
  local names = { [555] = "Lone Wolf", [444] = "Other" }
  local SI = { GetSpecialization = function() return 2 end, GetSpecializationInfo = function() return 254 end }
  local rep = R({ CT = { GetActiveConfigID = function() return 9 end }, T = T, SI = SI, name = function(id) return names[id] end })
  ok(rep:find("active config: 9", 1, true) and rep:find("-- tree 77: 2 nodes", 1, true), "active loadout: its tree")
  ok(rep:find("node 2  entry 20  spell 555  Lone Wolf  rank 1/1", 1, true) and rep:find("entries found: 2", 1, true), "a node line with the spell, name and rank")
  -- no loadout yet: the spec's tree through the view loadout
  local viewed
  local CT = { GetActiveConfigID = function() return nil end, GetTraitTreeForSpec = function(s) return 88 end,
               InitializeViewLoadout = function(s, lvl) viewed = { s, lvl } end }
  local rep2 = R({ CT = CT, T = T, SI = SI, name = function(id) return names[id] end, viewID = -3 })
  ok(viewed and viewed[1] == 254 and rep2:find("tree for spec 254: 88", 1, true) and rep2:find("view loadout: ok", 1, true), "no loadout: the spec tree via the view loadout")
  ok(rep2:find("-- tree 88: 2 nodes", 1, true), "the view tree is walked")
end

-- `/nock probe talents`: the Forever talent dump (Lone Wolf, 2026-09-26).
do
  local R = Probe.TalentReport
  ok(R(nil) == "C_SpecializationInfo.GetTalentInfo: missing", "no API: said so")
  local rep = R(function(q)
    if not q.tier then error("query.tier must be specified") end
    if q.specializationIndex == 2 and q.tier == 7 and q.column == 2 then
      return { name = "Lone Wolf", spellID = 1234567, talentID = 89, rank = 0, maxRank = 1 }
    end
    return nil
  end)
  ok(rep:find("spec 2  tier 7  col 2  Lone Wolf  spell 1234567  talent 89  rank 0/1", 1, true), "a talent line with its spell id and rank")
  ok(rep:find("-- spec index 2: 1 talents", 1, true) and rep:find("talents found: 1", 1, true), "per-index counts and the total")
  local rep2 = R(function() error("bad query") end)
  ok(rep2:find("first error: ", 1, true) and rep2:find("bad query", 1, true), "an error is reported, not thrown")
end

local aurRep = Probe.AuraReport({ spellId = "SECRET", name = "Quick Shots", duration = 12 }, 6150, false, false)
ok(aurRep:find("secret: true", 1, true) and aurRep:find("BySpell(6150): miss", 1, true), "a secret id is reported as such")

-- `/nock probe container`: the aura-container spike. Blizzard's
-- CustomAuraContainerTemplate renders auras the addon never reads; the probe
-- builds one for the player's own helpful auras and reports each step.
local made = {}
local Fake = {}
Fake.__index = Fake
function Fake:SetPoint() end
function Fake:SetSize() end
function Fake:SetAllPoints() end
function Fake:CreateTexture() return { SetAllPoints = function() end, SetColorTexture = function() end, SetTexCoord = function() end } end
function Fake:SetFlowLayoutAxis(a) self.axis = a end
function Fake:SetFrameStrata(s) self.strata = s end
function Fake:IsShown() return true end
function Fake:IsVisible() return true end
function Fake:GetAlpha() return 1 end
function Fake:GetWidth() return 240 end
function Fake:GetHeight() return 28 end
function Fake:GetLeft() return 100 end
function Fake:GetTop() return 300 end
function Fake:GetFrameStrata() return self.strata or "MEDIUM" end
function Fake:GetFrameLevel() return 5 end
function Fake:GetEffectiveScale() return 1 end
function Fake:SetFlowLayoutGrowthDirection(h, v) self.grow = { h, v } end
function Fake:SetFlowLayoutAnchorPoint(p) self.anchor = p end
_G.AnchorUtil = { FlowLayoutAxis = { Horizontal = 1, Vertical = 2 }, FlowDirection = { Left = 1, Right = 2, Up = 3, Down = 4 } }
function Fake:Show() self.shown = true end
function Fake:SetUnit(u) self.unit = u end
function Fake:AddAuraGroup(k, f, o) self.group = { k, f, o } end
function Fake:SetAuraGroupLayout(k, o) self.layout = { k, o } end
function Fake:SetEnabled(e) self.enabled = e end
function Fake:UpdateAllAuras() self.updated = true end
-- an aura button: bare until the addon hands it an icon and a cooldown
local Btn = {}
Btn.__index = Btn
function Btn:IsShown() error("secret boolean") end
function Btn:CreateTexture() return { SetAllPoints = function() end, SetTexCoord = function() end, SetColorTexture = function() end } end
function Btn:SetSize() end
function Btn:SetIcon(t) self.icon = t end
function Btn:SetDurationCooldown(c) self.cd = c end
local buttons = {}
function Fake:GetAuraGroupFrame(k, i)
  if i > 2 then return nil end
  buttons[i] = buttons[i] or setmetatable({}, Btn)
  return buttons[i]
end
_G.CreateFrame = function(kind, name, parent, template) local f = setmetatable({ kind = kind, template = template }, Fake); made[#made + 1] = f; return f end
_G.UIParent = {}
shown = nil
local rep = module:ContainerSpike()
local function containers() local t = {}; for _, f in ipairs(made) do if f.kind == "AuraContainer" then t[#t + 1] = f end end; return t end
local cs = containers()
ok(#cs == 1 and cs[1].template == "CustomAuraContainerTemplate", "container created from the template")
made[1] = cs[1]
ok(made[1].unit == "player" and made[1].group and made[1].group[2] == "HELPFUL|PLAYER" and made[1].group[3].maxFrameCount == 8, "own helpful auras, eight at most")
ok(made[1].layout and made[1].layout[2].elementWidth == 28 and made[1].enabled == true and made[1].updated, "tile-sized layout, enabled, refreshed")
ok(type(made[1].group[3].initializeFrame) == "function", "the group gets an initialise hook for new buttons")
ok(made[1].axis == 1 and made[1].grow and made[1].grow[1] == 2 and made[1].anchor == "TOPLEFT", "flow layout: horizontal, growing right, from the top-left")
ok(rep:find("AnchorUtil.FlowLayoutAxis: Horizontal=1", 1, true) and rep:find("AnchorUtil.FlowDirection:", 1, true), "the report dumps the client's flow-layout tables")
ok(rep:find("container: shown true  visible true  alpha 1  size 240x28", 1, true), "the report reads the container's own geometry")
ok(rep:find("button1:", 1, true), "the report tries the first button's geometry")
local markers = 0
for _, f in ipairs(made) do if f.kind == "Frame" and f.marker then markers = markers + 1 end end
ok(markers == 1, "a fixed marker frame sits where the container should be")
ok(buttons[1] and buttons[1].icon and buttons[1].cd and buttons[2].icon, "existing buttons are given an icon texture and a cooldown")
local icon1 = buttons[1].icon
module:ContainerSpike()
ok(buttons[1].icon == icon1, "a button is styled once")
ok(rep:find("AddAuraGroup: ok", 1, true) and rep:find("group frames: 2", 1, true), "report lists the steps and the frame count")
local rep2 = module:ContainerSpike()
ok(#containers() == 1 and rep2:find("group frames: 2", 1, true), "a second run reuses the container")
-- A client without the template: the failure is reported, not thrown.
module._container = nil
_G.CreateFrame = function() error("bad template") end
local rep3 = module:ContainerSpike()
ok(rep3:find("CreateFrame: err", 1, true), "a refused CreateFrame is reported")

-- `/nock probe sting`: the sting-timer spike. A one-tile aura container on
-- the target, own harmful auras, filtered to the sting ranks, over a Nock tile.
do
  local NAMES = { [1978] = "Serpent Sting", [13549] = "Serpent Sting", [13550] = "Serpent Sting", [3043] = "Scorpid Sting",
                  [3034] = "Viper Sting", [14279] = "Something Else", [1300001] = "Serpent Sting" }
  local nameOf = function(id) return NAMES[id] end
  local fams = Probe.StingIds(nameOf, { ["Serpent Sting"] = 1300001, ["Scorpid Sting"] = 3043, ["Viper Sting"] = true })
  local by = {}
  for _, f in ipairs(fams) do by[f.key] = f end
  ok(by.Serpent.name == "Serpent Sting" and table.concat(by.Serpent.ids, " ") == "1978 13549 13550 1300001",
     "ranks the client names like rank 1 are kept, the spellbook's own id is added")
  ok(by.Serpent.dropped == 6 and by.Serpent.book == 1300001, "unnamed ranks are dropped and counted")
  ok(table.concat(by.Scorpid.ids, " ") == "3043", "a spellbook id already kept is not added twice")
  ok(table.concat(by.Viper.ids, " ") == "3034" and by.Viper.book == nil, "a differently named id is dropped; a non-numeric book entry is ignored")
  NAMES[3034] = nil
  local gone = Probe.StingIds(nameOf, {})[3]
  ok(gone.key == "Viper" and gone.name == nil and #gone.ids == 0 and gone.dropped == 3, "a family the client does not know keeps nothing")
  NAMES[3034] = "Viper Sting"

  -- the spike itself: steps reported, never thrown
  local made2, groups = {}, {}
  local F = setmetatable({}, { __index = Fake })
  F.__index = F
  function F:SetFrameLevel(l) self.level = l end
  function F:Hide() self.shown = false end
  function F:AddAuraGroup(k, f, o) groups[#groups + 1] = { k, f, o, self } end
  function F:CreateTexture() return { SetAllPoints = function() end, SetColorTexture = function() end, SetTexCoord = function() end,
                                      SetPoint = function() end, SetTexture = function() end } end
  function F:CreateFontString() return { SetAllPoints = function() end, SetJustifyH = function() end, SetJustifyV = function() end } end
  function F:SetIcon(t) self.icon = t end
  function F:SetDurationCooldown(c) self.cd = c end
  function F:SetDurationText(fs, fmt) self.text = fs end
  _G.CreateFrame = function(kind, name, parent, template)
    local f = setmetatable({ kind = kind, name = name, template = template }, F); made2[#made2 + 1] = f; return f
  end
  Nock.API.SpellName = function(id) return NAMES[id] end
  Nock.API.SpellIcon = function() return "icon" end
  Nock.ForeverAuraRow = { IdTable = function(list) local t = {}; for _, id in ipairs(list) do t[id] = true end; return t end }
  _G.C_UnitAuras = {
    GetUnitAuraInstanceIDs = function() return { 41 } end,
    GetAuraDataByAuraInstanceID = function() return { spellId = 13549, name = "Serpent Sting", duration = 15 } end,
    GetAuraDuration = function() return {} end,
    GetAuraDataBySpellName = function(unit, name) if name == "Serpent Sting" then return { spellId = 13549, duration = 15 } end end,
  }
  _G.UnitExists = function() return true end
  local rep = module:StingSpike("")
  ok(#groups == 2 and groups[1][2] == "HARMFUL|PLAYER" and groups[1][4].unit == "target", "both groups: own harmful auras of the target")
  ok(groups[1][3].maxFrameCount == 1 and groups[1][3].candidateFilters.includeSpellIDs[13549] == true
     and groups[1][3].layout.elementWidth == 44, "the sting group: one wide tile, filtered to the kept ids")
  ok(groups[2][3].candidateFilters == nil and groups[2][3].maxFrameCount == 6, "the control group is unfiltered")
  ok(groups[1][4].level == 10, "the sting container sits above its slot")
  local b = setmetatable({}, F)
  groups[1][3].initializeFrame(b)
  ok(b.icon and b.cd and b.text, "a button is handed an icon, a swipe and a countdown")
  local rep2 = module:StingSpike("")
  ok(rep2:find("containers (existing)", 1, true) and rep2:find("buttons built: 1 (hand-overs ok 3, refused 0)", 1, true), "a second run reuses the containers and counts the hand-overs")
  -- a target change re-reads both containers (Blizzard's target frame does the same)
  ok(module.events["PLAYER_TARGET_CHANGED"] == "OnStingTarget", "the probe listens for target changes")
  local c1, c2 = groups[1][4], groups[2][4]
  c1.updated, c2.updated = nil, nil
  module:OnStingTarget()
  ok(c1.updated and c2.updated, "a target change re-reads both containers")
  ok(module:StingSpike("refresh"):find("re-read on target change: OFF | changes 1 (in combat 0) | refused 0", 1, true), "refresh flips the re-read off and the report counts the changes")
  c1.updated = nil
  module:OnStingTarget()
  ok(c1.updated == nil, "off: a target change is left to the container")
  module:StingSpike("refresh")
  function F:UpdateAllAuras() error("blocked") end
  module:OnStingTarget()
  ok(module:StingSpike(""):find("refused 2 | last: ", 1, true), "a refused re-read is counted and quoted")
  F.UpdateAllAuras = nil
  -- an own sting cast keeps the API readings taken half a second later
  local later
  local oldTimer = _G.C_Timer
  _G.C_Timer = { After = function(d, fn) later = { d, fn } end }
  module:OnCast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 3044)
  ok(later == nil, "a cast that is not a sting takes no readings")
  module:OnCast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 13549)
  ok(later and later[1] == 0.5, "a sting cast schedules the readings")
  later[2]()
  local rep3 = module:StingSpike("")
  ok(rep3:find("readings 0 s ago, 0.5 s after Serpent Sting (13549):", 1, true) and not rep3:find("no sting cast seen yet", 1, true), "the report carries the readings taken after the cast")
  _G.C_Timer = oldTimer
  ok(rep:find("Serpent (Serpent Sting): 1978 13549 13550", 1, true), "the report lists the kept ids")
  ok(rep:find("GetUnitAuraInstanceIDs(target, HARMFUL|PLAYER): 1", 1, true) and rep:find("spellId 13549", 1, true)
     and rep:find("GetAuraDuration table", 1, true), "the report reads the target's own debuffs through the API")
  ok(rep:find("GetAuraDataBySpellName(Serpent Sting): ", 1, true) and rep:find("GetAuraDataBySpellName(Scorpid Sting): nil", 1, true), "by-name reads, hit and miss")
  ok(rep:find("target: exists true  guid missing", 1, true), "a missing global reads as missing")
  ok(module:StingSpike("off"):find("hidden", 1, true) and made2[1].shown == false, "off hides the probe")
  Nock.ForeverAuraRow = nil
end

-- CdCatalogReport: spellbook + talent rows merged by id, passive flag,
-- cooldown signals, and the summary counts.
local cat = Probe.CdCatalogReport({
  level = 20,
  book = function() return {
    { id = 3044, name = "Arcane Shot", src = "book:Market", passive = false },
    { id = 1510, name = "Volley", src = "book:Market", passive = false },
    { id = 19574, name = "Bestial Wrath", src = "book:Beast " },
  } end,
  talents = function() return {
    { id = 19574, name = "Bestial Wrath", src = "talent", rank = 1, max = 1 },
    { id = 1293241, name = "Summon Hawk", src = "talent", rank = 0, max = 1 },
    { id = 415370, name = "Lone Wolf", src = "talent", rank = 0, max = 1 },
  } end,
  passive = function(id) return id == 415370 end,
  baseCd = function(id) if id == 1510 then return 0, 1500 end; if id == 19574 then return 120000, 1500 end; return nil end,
  tipCd = function(id) if id == 1293241 then return "6 sec cooldown" end end,
  key = function(id) if id == 3044 then return "Arc" end end,
})
ok(cat:find("level 20", 1, true) and not cat:find("IN COMBAT", 1, true), "catalog report header")
ok(cat:find("book:Beast +talent", 1, true), "a spell in both the book and the tree is one row, marked +talent")
ok(cat:find("1293241  Summon Hawk [rank 0/1] | active", 1, true), "an untaken talent is listed with its rank")
ok(cat:find("415370  Lone Wolf [rank 0/1] | PASSIVE", 1, true), "a passive talent is flagged")
ok(cat:find("Volley | active | 0/1500", 1, true), "a zero base cooldown is shown as such")
ok(cat:find("| Arc$", 1) or cat:find("| Arc\n", 1, true), "the tracked catalog key is shown")
ok(cat:find("spells: 5  active: 4  active with a cooldown signal: 2", 1, true), "summary counts (BW by base cd, Hawk by tooltip)")
ok(Probe.CdCatalogReport({ inCombat = true }):find("IN COMBAT", 1, true), "in-combat warning")

-- WindupReport: the spell-75 edges merged with the ranged swings, and the
-- phase verdict that decides the bar's anchor.
do
  local rep = Probe.WindupReport({
    build = "1.15.0 (70300)", forever = true,
    state = { windupRatio = 0.175, windup = 0.35, windupMeasured = true, queueWindow = 0.4, swingDuration = 2.0 },
    api = { "EnableRangeCheck", "GetWindupDuration", "IsTargetWithinSwingRange" },
    enum = { { "MainHand", 0 }, { "OffHand", 1 }, { "Ranged", 2 } },
    globals = { "PlayerSwingTimerMixin" },
    castingInfo = "nil",
    swings = {
      { t = 100.0, swingType = 2, duration = 2.0 },
      { t = 102.0, swingType = 2, duration = 2.0, extra = { 0.35 } },
      { t = 102.3, swingType = 0, duration = 2.6 },
    },
    windups = {
      { t = 101.65, ev = "UNIT_SPELLCAST_START", castStart = 101.65, castEnd = 102.0, swingRemaining = 0.35, sampled = "cast" },
      { t = 102.0, ev = "UNIT_SPELLCAST_SUCCEEDED", swingRemaining = 0 },
      { t = 102.0, ev = "RELEASE", measured = 0.35, duration = 2.0, autoDelay = 0, fromCast = true },
    },
  })
  ok(rep:find("windupRatio 0.1750", 1, true) and rep:find("measured true", 1, true), "state line")
  ok(rep:find("C_SwingTimer: EnableRangeCheck, GetWindupDuration, IsTargetWithinSwingRange", 1, true), "API names listed")
  ok(rep:find("Ranged=2", 1, true) and rep:find("PlayerSwingTimerMixin", 1, true), "enum and globals")
  ok(rep:find("START(75)  client cast 1.650 -> 2.000 (0.350 s)  bar rem 0.350  SAMPLED cast", 1, true), "START row with the client window")
  ok(rep:find("PLAYER_SWING Ranged  dur 2.000  +0.000 vs cycle  extra=[0.35]", 1, true), "extra PLAYER_SWING payload shown")
  ok(rep:find("RELEASE  start->swing 0.350 s  dur 2.000  delay 0.000  (cast-sampled shot)", 1, true), "release row")
  ok(rep:find("feed SUCCEEDED(75)", 1, true), "other feed edges stripped of their prefix")
  ok(rep:find("PLAYER_SWING MainHand  dur 2.600", 1, true), "melee swings are in the timeline (the reset question)")
  ok(rep:find("1 START(75), 1 client windows (mean 0.350 s), 1 release reads (mean 0.350 s), sampled cast=1 release=0", 1, true), "summary counts")
  ok(rep:find("82.5% into the cycle", 1, true) and rep:find("TBC model", 1, true), "phase verdict: end of cycle")

  local early = Probe.WindupReport({ swings = { { t = 10, swingType = 2, duration = 2.0 } },
    windups = { { t = 10.01, ev = "UNIT_SPELLCAST_START" } } })
  ok(early:find("0.5% into the cycle", 1, true) and early:find("re-anchored", 1, true), "phase verdict: swing fires at the wind-up start")
  ok(early:find("no client window", 1, true), "START without a client window says so")
  ok(Probe.WindupReport({}):find("nothing yet", 1, true), "empty rings: instructions")

  -- Stop-gated reads: the row, the still stamp on the swing, the verdict.
  local stop = Probe.WindupReport({
    swings = { { t = 10, swingType = 2, duration = 2.0 }, { t = 12.71, swingType = 2, duration = 2.0, stillFor = 0.41 } },
    state = { windup = 0.41 },
    windups = { { t = 12.71, ev = "STOP->SHOT", stoppedAt = 12.3, due = 12.0, late = 0.71, raw = 0.41, latency = 0.06, lessRtt = 0.35, measured = 0.41, duration = 2.0, sampled = "stop" } },
  })
  ok(stop:find("PLAYER_SWING Ranged  dur 2.000  still 0.410", 1, true), "the swing row carries the still time")
  ok(stop:find("STOP->SHOT  stopped +0.300 vs due  shot 0.710 late  0.410 after the stop (less rtt 0.060 = 0.350)  SAMPLED stop", 1, true), "the stop row")
  ok(stop:find("stop-gated shots: 1, raw (bar time) min 0.410 mean 0.410 max 0.410 s: a wind-up gates the shot after a stop; in bar time stop ~0.410 s before the shot is due (model in use: 0.410 s)", 1, true), "verdict: wind-up")
  ok(stop:find("stop=1", 1, true), "sampled stop count")
  ok(stop:find("still 0.410  +0.710 vs cycle", 1, true), "a ranged swing row says how late it was against the previous cycle")

  -- Shots on the move: on time with a short move -> stillness needed only at the start.
  local mv = Probe.WindupReport({ swings = {
    { t = 10, swingType = 2, duration = 2.0 },
    { t = 12.0, swingType = 2, duration = 2.0, moving = true, movingFor = 0.3 },
    { t = 14.02, swingType = 2, duration = 2.0, moving = true, movingFor = 0.45 },
    { t = 16.6, swingType = 2, duration = 2.0, moving = true, movingFor = 1.2 },
  } })
  ok(mv:find("MOVING for 0.300  +0.000 vs cycle", 1, true), "moving row with the move length")
  ok(mv:find("shots on the move: 3, on time 2 (moved for 0.30-0.45 s), late 1 (moved for 1.20-1.20 s)", 1, true), "moving summary splits on-time and late")

  -- Moves paired with interrupts: where the wind-up begins.
  local im = Probe.WindupReport({ state = { windup = 0.58, windupSource = "interrupt", stopBy = 0.95 }, windups = {
    { t = 10.0, ev = "MOVE", swingRemaining = 0.9 },
    { t = 12.5, ev = "MOVE", swingRemaining = 0.45 },
    { t = 12.71, ev = "UNIT_SPELLCAST_INTERRUPTED", swingRemaining = 0.24, sampled = "interrupt", pairedMoveRem = 0.45 },
    { t = 15.0, ev = "MOVE", swingRemaining = 0.3 },
    { t = 15.21, ev = "UNIT_SPELLCAST_INTERRUPTED", swingRemaining = 0.09 },
    { t = 17.0, ev = "STOP->SHOT", restart = true, late = 0.7, raw = 0.95 },
  } })
  ok(im:find("MOVE  0.900 before the shot was due: free (no interrupt)", 1, true), "a free move row")
  ok(im:find("MOVE  0.450 before the shot was due: INTERRUPTED the wind-up (+0.210 s)", 1, true), "an interrupting move row, with the lag (0.21 s is inside the 0.4 s window)")
  ok(im:find("feed INTERRUPTED(75)  bar rem 0.240  SAMPLED interrupt (move at rem 0.450)", 1, true), "the interrupt row names its move")
  ok(im:find("band in use: 0.580 s (share 0.0000) from interrupt; stop-by edge 0.950 s", 1, true), "band and stop-by line")

  -- The band's feed rows and the share line.
  local so = Probe.WindupReport({ state = { windup = 0.655, windupRatio = 0.2934, windupSource = "switch-on" },
    share = { published = 0.244, reads = { 0.244, 0.251 }, key = "19361" },
    windups = {
      { t = 10.0, ev = "ON->SHOT", read = 0.655, duration = 2.232, rtt = 0.11, idle = true, sampled = "switch-on", share = 0.244 },
      { t = 20.0, ev = "ON->SHOT", read = 0.9, duration = 2.232, rtt = 0.11, idle = true, moved = true },
      { t = 30.0, ev = "ON->SHOT", read = 0.7, duration = 2.232, rtt = 0.11, idle = false },
    } })
  ok(so:find("ON->SHOT  0.655 s after the press  share 0.244  SAMPLED switch-on", 1, true), "a sampled switch-on row")
  ok(so:find("ON->SHOT  0.900 s after the press  (moved: not a read)", 1, true), "a moved switch-on row")
  ok(so:find("ON->SHOT  0.700 s after the press  (bar was running: not a read)", 1, true), "a running-bar switch-on row")
  ok(so:find("band in use: 0.655 s (share 0.2934) from switch-on", 1, true), "band line with the share")
  ok(so:find("switch-on reads (server share, weapon 19361): 0.244, 0.251; published 0.244", 1, true), "the reads behind the share")
  ok(im:find("interrupt=1", 1, true), "sampled interrupt count")
  ok(im:find("moves inside a running swing: 3: the wind-up begins between 0.450 and 0.900 s before the shot", 1, true), "the edge is bracketed")
  ok(im:find("RESTART->SHOT  (wind-up interrupted this cycle)  shot 0.700 late  0.950 after the stop  (penalty, not sampled)", 1, true), "restart row")
  ok(im:find("restarts after an interrupted wind-up: 1, shot 0.950 s after the stop on average", 1, true), "restart summary")
  local allInt = Probe.WindupReport({ windups = { { t = 1, ev = "MOVE", swingRemaining = 0.3 }, { t = 1.3, ev = "UNIT_SPELLCAST_INTERRUPTED" } } })
  ok(allInt:find("every move interrupted: the wind-up begins more than 0.300 s before the shot", 1, true), "all interrupted: asks for earlier moves")
  local none = Probe.WindupReport({ windups = { { t = 1, ev = "STOP->SHOT", stoppedAt = 0.9, due = 0.8, raw = 0.03, latency = 0.03, lessRtt = 0.0, measured = 0.03 } } })
  ok(none:find("no wind-up on this server", 1, true) and none:find("(dropped)", 1, true), "verdict: shot at once")

  -- Every player cast edge is in the timeline (any spell id), with what
  -- UnitCastingInfo said at a START; runs of the same FAILED fold into one row.
  local all = Probe.WindupReport({
    swings = { { t = 50.0, swingType = 2, duration = 2.0 } },
    casts = {
      { t = 51.6, ev = "UNIT_SPELLCAST_START", spellID = 1234567, castBarID = 9,
        ci = { name = "Auto Shot", id = 1234567, startMs = 51600, endMs = 52000 } },
      { t = 51.7, ev = "UNIT_SPELLCAST_FAILED", spellID = 75 },
      { t = 51.71, ev = "UNIT_SPELLCAST_FAILED", spellID = 75 },
      { t = 51.72, ev = "UNIT_SPELLCAST_FAILED", spellID = 75 },
      { t = 52.0, ev = "UNIT_SPELLCAST_SUCCEEDED", spellID = 1234567 },
    },
  })
  ok(all:find("cast START  spell 1234567  castBar 9  UnitCastingInfo: Auto Shot id=1234567 51600..52000 ms", 1, true), "a START under another id shows with the client's record")
  ok(all:find("cast FAILED  spell 75  x3", 1, true), "a FAILED run folds with its count")

  -- One-session probe (2026-10-18): the melee-reset question. A melee hit
  -- followed by a ranged PLAYER_SWING inside 0.1 s is the client restarting
  -- the reload; with no such event the next shot's timing says whether the
  -- reload restarted silently (a full reload after the hit) or ran on.
  local mr = Probe.WindupReport({ swings = {
    { t = 100.0, swingType = 2, duration = 2.0 },
    { t = 101.0, swingType = 0, duration = 2.6 },
    { t = 101.05, swingType = 2, duration = 2.0 },
    { t = 103.05, swingType = 2, duration = 2.0 },
    { t = 104.0, swingType = 0, duration = 2.6 },
    { t = 106.0, swingType = 2, duration = 2.0 },
    { t = 107.0, swingType = 0, duration = 2.6 },
    { t = 108.0, swingType = 2, duration = 2.0 },
  } })
  ok(mr:find("PLAYER_SWING MainHand  dur 2.600  ranged event +0.050 after: the client restarted the reload", 1, true), "a hit with a ranged event right after")
  ok(mr:find("PLAYER_SWING MainHand  dur 2.600  no ranged event; next shot +2.000 after the hit (reload 2.000), +0.950 vs the old due: the reload restarted silently", 1, true), "a silent restart read from the next shot")
  ok(mr:find("PLAYER_SWING MainHand  dur 2.600  no ranged event; next shot +1.000 after the hit (reload 2.000), +0.000 vs the old due: the reload ran on", 1, true), "no restart read from the next shot")
  ok(mr:find("melee hits: 3; ranged event within 0.1 s: 1; silent restarts: 1; ran on: 1", 1, true), "melee-reset summary")

  -- The haste question: moves grouped by the reload they were made in. The
  -- same edge in seconds across reloads = fixed seconds; the same share = scaled.
  local fixed = Probe.WindupReport({ windups = {
    { t = 10.0, ev = "MOVE", swingRemaining = 0.55, swingDuration = 2.0 }, { t = 10.21, ev = "UNIT_SPELLCAST_INTERRUPTED" },
    { t = 12.0, ev = "MOVE", swingRemaining = 0.70, swingDuration = 2.0 },
    { t = 20.0, ev = "MOVE", swingRemaining = 0.54, swingDuration = 1.43 }, { t = 20.21, ev = "UNIT_SPELLCAST_INTERRUPTED" },
    { t = 22.0, ev = "MOVE", swingRemaining = 0.66, swingDuration = 1.43 },
  } })
  ok(fixed:find("reload 2.000 s: 2 moves, interrupted up to 0.550 s (share 0.275), free from 0.700 s", 1, true), "a per-reload edge line, slow reload")
  ok(fixed:find("reload 1.430 s: 2 moves, interrupted up to 0.540 s (share 0.378), free from 0.660 s", 1, true), "a per-reload edge line, hasted reload")
  ok(fixed:find("haste: the edge stays at 0.54-0.55 s across reloads 1.430-2.000: the wind-up is FIXED SECONDS (not scaled)", 1, true), "haste verdict: fixed seconds")
  local scaled = Probe.WindupReport({ windups = {
    { t = 10.0, ev = "MOVE", swingRemaining = 0.55, swingDuration = 2.0 }, { t = 10.21, ev = "UNIT_SPELLCAST_INTERRUPTED" },
    { t = 20.0, ev = "MOVE", swingRemaining = 0.39, swingDuration = 1.43 }, { t = 20.21, ev = "UNIT_SPELLCAST_INTERRUPTED" },
  } })
  ok(scaled:find("haste: the edge keeps its share 0.273-0.275 across reloads 1.430-2.000: the wind-up SCALES with haste", 1, true), "haste verdict: scaled")
  local one = Probe.WindupReport({ windups = { { t = 10.0, ev = "MOVE", swingRemaining = 0.55, swingDuration = 2.0 }, { t = 10.21, ev = "UNIT_SPELLCAST_INTERRUPTED" } } })
  ok(one:find("haste: interrupts seen at one reload only (2.000 s); repeat the moves with Rapid Fire up", 1, true), "haste verdict needs two reloads")

  -- The switch-on question: !Auto Shot from idle to the first shot.
  local on = Probe.WindupReport({
    swings = { { t = 100.0, swingType = 2, duration = 2.0 }, { t = 110.72, swingType = 2, duration = 2.0 }, { t = 112.72, swingType = 2, duration = 2.0 } },
    windups = { { t = 105.0, ev = "AUTO_OFF", swingRemaining = 0 }, { t = 110.0, ev = "AUTO_ON", swingRemaining = 0, latency = 0.11 }, { t = 111.0, ev = "AUTO_ON", swingRemaining = 1.72, latency = 0.11 } },
  })
  ok(on:find("AUTO_ON  bar idle  first shot +0.720 s (rtt 0.110)", 1, true), "a switch-on from idle with its first shot")
  ok(on:find("AUTO_ON  bar running (rem 1.720)", 1, true), "a switch-on while the bar runs is tagged, not read")
  ok(on:find("AUTO_OFF", 1, true), "the switch-off row")
  ok(on:find("switch-on from idle -> first shot: 1 read, 0.720 s (0.5 + rtt + 0.110)", 1, true), "switch-on summary")
  ok(on:find("reload 2.000 s: 1 switch-on, 0.720 s (share 0.360)", 1, true), "switch-on per reload (the second haste witness)")

  -- First run (2026-10-18): moves with auto-repeat OFF and moves inside the
  -- move tail are not edge reads; dropped stop rows stay out of the summary.
  local off = Probe.WindupReport({ state = { latency = 0.11 }, windups = {
    { t = 10.0, ev = "MOVE", swingRemaining = 0.63, swingDuration = 2.23 }, { t = 10.2, ev = "UNIT_SPELLCAST_INTERRUPTED" },
    { t = 12.0, ev = "AUTO_OFF", swingRemaining = 0 },
    { t = 13.0, ev = "MOVE", swingRemaining = 0.58, swingDuration = 2.23 },
    { t = 14.0, ev = "AUTO_ON", swingRemaining = 1.0 },
    { t = 16.0, ev = "MOVE", swingRemaining = 0.09, swingDuration = 2.23 },
    { t = 18.0, ev = "MOVE", swingRemaining = 0.67, swingDuration = 2.23 },
    { t = 20.0, ev = "STOP->SHOT", stoppedAt = 18.3, due = 19.5, late = 0.5, raw = 1.7, latency = 0.11, lessRtt = 1.59, measured = 1.7 },
    { t = 22.0, ev = "STOP->SHOT", stoppedAt = 21.0, due = 21.1, late = 0.9, raw = 1.0, latency = 0.11, lessRtt = 0.89, measured = 1.0, sampled = "stop" },
  } })
  ok(off:find("MOVE  0.580 before the shot was due: auto-repeat off, nothing to interrupt (not a read)", 1, true), "a move with auto off is tagged")
  ok(off:find("MOVE  0.090 before the shot was due: free, inside the move tail (rtt + 0.10 = 0.210 s)", 1, true), "a move inside the tail is tagged")
  ok(off:find("moves inside a running swing: 2: the wind-up begins between 0.630 and 0.670 s before the shot", 1, true), "neither counts toward the edge")
  ok(off:find("moves inside the move tail (last 0.210 s): 1, all free", 1, true), "tail summary")
  ok(off:find("stop-gated shots: 1, raw (bar time) min 1.000 mean 1.000 max 1.000 s", 1, true), "dropped stop reads stay out of the stop summary")

  -- The retry question: FAILED_QUIET(75) with a SENT(75) of the same cast id
  -- is the player's press; the rest are the server's tries, 0.5 s apart.
  local rt = Probe.WindupReport({
    swings = { { t = 300.0, swingType = 2, duration = 2.0 }, { t = 303.47, swingType = 2, duration = 2.0 } },
    casts = {
      { t = 301.0, ev = "UNIT_SPELLCAST_SENT", spellID = 75, guid = "A" },
      { t = 301.01, ev = "UNIT_SPELLCAST_FAILED_QUIET", spellID = 75, guid = "A" },
      { t = 302.0, ev = "UNIT_SPELLCAST_FAILED_QUIET", spellID = 75, guid = "B" },
      { t = 302.01, ev = "UNIT_SPELLCAST_FAILED_QUIET", spellID = 75, guid = "B" },
      { t = 302.5, ev = "UNIT_SPELLCAST_FAILED_QUIET", spellID = 75, guid = "C" },
      { t = 302.51, ev = "UNIT_SPELLCAST_FAILED_QUIET", spellID = 75, guid = "C" },
    },
  })
  ok(rt:find("cast FAILED_QUIET  spell 75  (your press)", 1, true), "a press's failure is named")
  ok(rt:find("cast FAILED_QUIET  spell 75  (server try)  x2", 1, true), "a server try folds its pair and is named")
  ok(rt:find("server tries: 2, 0.500 s apart; shot 0.970 s after the last try", 1, true), "retry cadence summary")

  -- The session script for the one-session probe.
  local sc = Probe.WindupScript()
  ok(sc:find("Rapid Fire", 1, true) and sc:find("melee", 1, true) and sc:find("/nock probe windup", 1, true), "script names the Rapid Fire leg, the melee leg and the report command")
  ok(all:find("cast SUCCEEDED  spell 1234567", 1, true), "the SUCCEEDED row")
end

-- BlizzSwingReport: the live-frame introspection half of the wind-up probe.
do
  local rep = Probe.BlizzSwingReport({
    mixinMethods = { "OnEvent", "OnLoad", "SetWindupDuration", "UpdateShownState" },
    managerMethods = { "OnEvent", "UpdateSwingTimers" },
    frameMethods = { "OnEvent", "SetWindupDuration" },
    fields = { "swingType=2", "windupDuration=0.5" },
    regions = { "StatusBar:StatusBar", "StatusBar.Pip:Texture", "Windup:Texture hidden" },
    registered = { "PLAYER_SWING", "Manager:PLAYER_SWING" },
    console = { "showSwingTimer" },
    shown = true, hooked = true,
    log = { { t = 10, what = "Ranged:SetWindupDuration(0.5)" }, { t = 10.5, what = "Ranged <- PLAYER_SWING(2.232, 2)" } },
  })
  ok(rep:find("SwingTimerMixin methods: OnEvent, OnLoad, SetWindupDuration, UpdateShownState", 1, true), "mixin methods listed")
  ok(rep:find("fields: swingType=2  windupDuration=0.5", 1, true), "frame fields listed")
  ok(rep:find("Windup:Texture hidden", 1, true), "regions with their shown state")
  ok(rep:find("registered events (of the candidates asked): PLAYER_SWING, Manager:PLAYER_SWING", 1, true), "registered events")
  ok(rep:find("console commands matching swing/windup/autoshot: showSwingTimer", 1, true), "console commands")
  ok(rep:find("0.000  Ranged:SetWindupDuration(0.5)", 1, true) and rep:find("0.500  Ranged <- PLAYER_SWING(2.232, 2)", 1, true), "hook log rows")
  ok(Probe.BlizzSwingReport({ hooked = true, log = { { t = 1, what = "Ranged:ClearSwingTimer()", n = 7 } } }):find("ClearSwingTimer()  x7", 1, true), "folded duplicates show a count")
  ok(Probe.BlizzSwingReport({ hooked = true }):find("nothing yet", 1, true), "hooked, no log: instructions")
  ok(Probe.BlizzSwingReport({ hooked = false }):find("hooks not installed", 1, true), "not hooked: says so")
  local cb = Probe.BlizzSwingReport({ castBarMethods = { "OnEvent", "PlayFinishAnim" }, castBarFields = { "casting=true", "spellID=75" },
                                     castBarRegions = { "Text:FontString", "Icon:Texture" } })
  ok(cb:find("Blizzard player cast bar", 1, true) and cb:find("own methods: OnEvent, PlayFinishAnim", 1, true), "cast bar methods")
  ok(cb:find("fields: casting=true  spellID=75", 1, true) and cb:find("Text:FontString, Icon:Texture", 1, true), "cast bar fields and regions")
end

print(("forever_probe: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
