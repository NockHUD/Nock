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
for i = 1, 25 do module:OnCast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1000 + i, nil) end
module:OnCast("UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 9, nil)
local casts = module:Casts()
ok(#casts == 20 and casts[#casts].spellID == 1025 and casts[1].spellID == 1006, "ring keeps the last 20 player casts only")

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

print(("forever_probe: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
