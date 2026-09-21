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

print(("forever_probe: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
