-- Tests/onboarding_forever_test.lua
-- The Forever page script: page list, reveal keys, row keys against the Forever defaults, the warnings catalog, the start-page filter.
-- Run from the repo root: luajit Tests/onboarding_forever_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local function readAll(path) local f = io.open(path, "rb"); if not f then return "" end; local s = f:read("*a"); f:close(); return s end

-- Forever defaults (the real file, Forever flag on).
local D do
  local N = { Flavor = { forever = true }, Constants = setmetatable({}, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }) }
  _G.LibStub = function() return { GetAddon = function() return N end } end
  dofile("Config/Defaults.lua")
  D = N.Defaults.profile
end

local sent = {}
local catalog = {
  { enabledKey = "warnPetDeadEnabled", name = "Pet dead", description = "d" },
  { enabledKey = "warnNotInRangeEnabled", name = "Not in range", description = "d" },
}
local Nock = {
  Constants = { SpellID = {} }, Flavor = { forever = true }, Spells = { AUTO_SHOT = 75 },
  state = { demo = {} }, isHunter = true,
  db = { profile = {}, global = {}, char = {} }, Defaults = { profile = D },
  BundledProfiles = { { key = "yaxal", name = "Yaxal", flavor = "tbc" } },
}
function Nock:SendMessage(m) sent[#sent + 1] = m end
function Nock:SetLocked(v) self.db.profile.locked = v end
function Nock.IsLocked() return Nock.db.profile.locked ~= false end
local view = { shown = false }
function view:Show() self.shown = true end
function view:Hide() if self.shown then self.shown = false; Nock.Onboarding:Teardown() end end
local mods = { OnboardingView = view, Warnings = { Catalog = catalog }, QoL = {} }
function Nock:GetModule(n) return mods[n] end
function Nock:NewModule()
  local m = {}
  function m:RegisterEvent() end
  function m:UnregisterEvent() end
  function m:ScheduleTimer() end
  function m:Print() end
  return m
end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
_G.C_AddOns = { GetAddOnMetadata = function() return "2.0.1" end }
_G.C_Spell = { GetSpellTexture = function() return nil end }
_G.InCombatLockdown = function() return false end

dofile("Modules/Onboarding.lua")
dofile("Forever/OnboardingPages.lua")
local O = Nock.Onboarding

local keys = {}
for i, pg in ipairs(O.Pages) do keys[i] = pg.key end
ok(table.concat(keys, ",") == "start,welcome,hud,range,corners,warnings,cues,ring,qol,done", "page order, got " .. table.concat(keys, ","))

-- Every reveal key is a nudge key a Camelot-listed file registers.
local camelotSrc = ""
for line in readAll("Nock_Camelot.toc"):gmatch("[^\r\n]+") do
  local f = line:match("^%s*([^#%s][^%s]*)")
  if f and f:match("%.lua$") then camelotSrc = camelotSrc .. readAll((f:gsub("\\", "/"))) end
end
for _, pg in ipairs(O.Pages) do
  for _, k in ipairs(pg.reveals or {}) do
    if k ~= "*" then
      ok(camelotSrc:find('key%s*=%s*"' .. k:gsub("%.", "%%.") .. '"') ~= nil, "reveal key registered on Forever: " .. k)
    end
  end
end

-- Open fills the warnings page from the catalog.
Nock.db.profile = {}
for k, v in pairs(D) do Nock.db.profile[k] = v end
O:Open(1, true)
local wp
for _, pg in ipairs(O.Pages) do if pg.key == "warnings" then wp = pg end end
local catRows = 0
for _, opt in ipairs(wp.options) do
  if opt.fromCatalog then catRows = catRows + 1 end
end
ok(catRows == #catalog, "warnings page: one row per catalog entry")
ok(wp.options[2].key == "warnPetDeadEnabled" and wp.options[2].dependsOn == "showWarnings", "catalog rows keyed by enabledKey, behind the master")

-- Every keyed row names a key the Forever defaults carry.
for _, pg in ipairs(O.Pages) do
  for _, list in ipairs({ pg.options or {}, pg.toggles or {} }) do
    for _, opt in ipairs(list) do
      if opt.key and not opt.value then
        ok(D[opt.key] ~= nil, "row key has a Forever default: " .. opt.key)
      end
      if opt.slider then
        ok(opt.min < opt.max and opt.default >= opt.min and opt.default <= opt.max, "slider range sane: " .. opt.key)
        ok(D[opt.key] == opt.default, "slider default matches Defaults: " .. opt.key)
      end
    end
  end
end

-- No TBC-only module in the page script.
local src = readAll("Forever/OnboardingPages.lua")
ok(not src:find("SetupCheck") and not src:find("WeaveBind") and not src:find("hudMode"), "no TBC-only reference")

-- Start page: hidden with only a TBC bundle, first page shown is welcome.
ok(O:IsPageVisible(O.Pages[1]) == false, "start page hidden with only TBC bundles")
ok(O:CurrentPage().key == "welcome", "the run opens on Welcome")
Nock.BundledProfiles[2] = { key = "fv", name = "Fv", flavor = "forever" }
ok(O:IsPageVisible(O.Pages[1]) == true, "a Forever bundle brings the start page back")
Nock.BundledProfiles[2] = nil

-- QoL rows write through the module.
local glow
mods.QoL.SetNoGlow = function(on) glow = on; Nock.db.profile.qolNoGlow = on end
local qp
for _, pg in ipairs(O.Pages) do if pg.key == "qol" then qp = pg end end
for _, opt in ipairs(qp.options) do if opt.id == "qolNoGlow" then O:ToggleOption(qp, opt) end end
ok(glow == true, "no-glow row calls QoL.SetNoGlow")

-- The ring page writes the key and tells the ring.
local rp
for _, pg in ipairs(O.Pages) do if pg.key == "ring" then rp = pg end end
sent = {}
O:ApplyKey(rp, rp.keyCapture, "SHIFT-R")
ok(Nock.db.profile.aspectRingKey == "SHIFT-R" and sent[2] == "NOCK_ASPECT_RING_CONFIG", "ring key saved and announced")

-- Recap reads the profile.
local recap = O:BuildRecap()
ok(#recap >= 5 and #recap <= 6, "recap fits the finish page (5-6 rows)")
ok(recap[5][2] == "SHIFT-R", "recap names the ring key")

-- First run stamps seenVersion as the wizard opens.
O:Close()
Nock.db.global.onboarding = nil
O:AutoOpen()
ok(Nock.db.global.onboarding and Nock.db.global.onboarding.seenVersion == "2.0.1", "auto-open stamps the version")
O:Close()
O._autoOpenChecked = false
local scheduled = false
O.ScheduleTimer = function() scheduled = true end
O:OnEnteringWorld()
ok(scheduled == false, "stamped: no auto-open on the next login")

print(("onboarding_forever: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
