-- Forever/Warnings.lua
-- The Forever warnings module: registers as "Warnings" so the alert squares
-- (UI/Frame_Warnings.lua) and the settings page find it unchanged, with its
-- own small catalog of checks whose feeds read PLAIN in combat on this
-- client (probed 2026-09-23): the ammo slot, the pet's presence, death and
-- happiness. The TBC module (Modules/Warnings.lua) stays off the Camelot
-- toc: it registers the combat log, which Forever forbids.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Warnings = Nock:NewModule("Warnings", "AceEvent-3.0")

local SEVERITY_RANK = { red = 3, amber = 2, blue = 1 }
local AMMO_SLOT = 0
local DEMO_DURATION = 10

local function P(v) return Nock.Flavor.Plain(v) end

local function threshold(key, fallback)
  local p = Nock.db and Nock.db.profile
  if p and p[key] ~= nil then return p[key] end
  return fallback
end

local function isEnabled(key)
  local p = Nock.db and Nock.db.profile
  if not p or p[key] == nil then return true end
  return p[key] and true or false
end

local function spellIcon(id)
  return Nock.API and Nock.API.SpellIcon and Nock.API.SpellIcon(id) or nil
end

-- One pooled record per warning id, the shape the squares frame reads.
local POOL = {}
local function warn(id, severity, icon, text, remaining)
  local w = POOL[id]
  if not w then w = { id = id }; POOL[id] = w end
  w.severity, w.icon, w.text, w.remaining = severity, icon, text, remaining
  return w
end

-- The checks: pure over a `reads` table so they test without a client.
--   reads.ammoId, reads.ammoCount   the ammo slot (nil = empty)
--   reads.petExists, reads.petDead, reads.happiness (1..3 or nil)
--   reads.callPetKnown, reads.inCombat
local Checks = {}
Warnings.Checks = Checks

function Checks.ammo(reads)
  if not isEnabled("warnQuiverEnabled") then return nil end
  local id, n = reads.ammoId, reads.ammoCount
  if type(id) ~= "number" or id <= 0 or type(n) ~= "number" then return nil end
  if n >= threshold("quiverArrowThreshold", 400) then return nil end
  return warn("ammo", "red", reads.ammoIcon or 134404, ("%d"):format(n), nil)
end

function Checks.petDead(reads)
  if not isEnabled("warnPetDeadEnabled") then return nil end
  if reads.petExists ~= true or reads.petDead ~= true then return nil end
  return warn("petDead", "red", spellIcon(Nock.Spells.PET.REVIVE_PET) or 132163, "REVIVE", nil)
end

function Checks.petMissing(reads)
  if not isEnabled("warnPetMissingEnabled") then return nil end
  if reads.petExists == true or reads.callPetKnown ~= true or reads.inCombat ~= true then return nil end
  return warn("petMissing", "amber", spellIcon(Nock.Spells.PET.CALL_PET) or 132161, "NO PET", nil)
end

function Checks.petUnhappy(reads)
  if not isEnabled("warnPetUnhappyEnabled") then return nil end
  if reads.petExists ~= true or reads.petDead == true or reads.happiness ~= 1 then return nil end
  return warn("petUnhappy", "amber", spellIcon(Nock.Spells.PET.FEED_PET) or 132165, "FEED", nil)
end

Warnings.ORDER = { Checks.ammo, Checks.petDead, Checks.petMissing, Checks.petUnhappy }

-- The live reads, every one secret-guarded: a secret answer is a nil read
-- and the check stays quiet.
local READS = {}
function Warnings:Reads(state)
  local r = READS
  r.ammoId    = P(_G.GetInventoryItemID and GetInventoryItemID("player", AMMO_SLOT))
  r.ammoCount = P(_G.GetInventoryItemCount and GetInventoryItemCount("player", AMMO_SLOT))
  r.ammoIcon  = P(_G.GetInventoryItemTexture and GetInventoryItemTexture("player", AMMO_SLOT))
  r.petExists = P(_G.UnitExists and UnitExists("pet")) == true
  r.petDead   = P(_G.UnitIsDead and UnitIsDead("pet")) == true
  local PI = _G.C_PetInfo
  r.happiness = r.petExists and PI and PI.GetPetHappiness and P(PI.GetPetHappiness()) or nil
  if type(r.happiness) ~= "number" then r.happiness = nil end
  r.inCombat = state.player and state.player.inCombat == true
  r.callPetKnown = self:CallPetKnown()
  return r
end

-- Call Pet is learned at 10; the spellbook says so on this client, the
-- level is the fallback.
function Warnings:CallPetKnown()
  local SB = _G.C_SpellBook
  if SB and SB.IsSpellKnown then
    local okc, known = pcall(SB.IsSpellKnown, Nock.Spells.PET.CALL_PET)
    if okc and type(known) == "boolean" then return known end
  end
  local lvl = P(_G.UnitLevel and UnitLevel("player"))
  return type(lvl) == "number" and lvl >= 10
end

-- Pet HP is secret at all times on Forever (probed 2026-09-23, in and out
-- of combat), so this warning is decided by the CLIENT: a step curve over
-- UnitHealthPercent("pet") answers 1 below the threshold and 0 from there,
-- as a secret number the squares frame passes to SetAlpha and never reads.
-- Plain 0 whenever the square must be off for a reason Nock can know.
local hpCurve, hpCurveThr
function Warnings:PetHpAlpha()
  if not isEnabled("warnPetLowHpEnabled") then return 0 end
  if P(_G.UnitExists and UnitExists("pet")) ~= true then return 0 end
  if P(_G.UnitIsDead and UnitIsDead("pet")) == true then return 0 end
  local CU, E = _G.C_CurveUtil, _G.Enum and _G.Enum.LuaCurveType
  if not (CU and CU.CreateCurve and _G.UnitHealthPercent) then return 0 end
  local thr = (tonumber(threshold("mendPetThreshold", 50)) or 50) / 100
  if not hpCurve or hpCurveThr ~= thr then
    local c = CU.CreateCurve()
    if not (c and c.AddPoint) then return 0 end
    if c.SetType and E and E.Step then c:SetType(E.Step) end
    c:AddPoint(0, 1)
    c:AddPoint(thr, 0)
    hpCurve, hpCurveThr = c, thr
  end
  local okc, v = pcall(UnitHealthPercent, "pet", true, hpCurve)
  if not okc or v == nil then return 0 end
  return v
end

Warnings.refreshInterval = 0.1

local function bySeverity(a, b)
  return (SEVERITY_RANK[a.severity] or 0) > (SEVERITY_RANK[b.severity] or 0)
end

local function demoList()
  return {
    { id = "demo_red",   severity = "red",   text = "Demo Red",   icon = spellIcon(Nock.Spells.PET.REVIVE_PET) or 132163, remaining = 8 },
    { id = "demo_amber", severity = "amber", text = "Demo Amber", icon = spellIcon(Nock.Spells.PET.CALL_PET) or 132161, remaining = nil },
    { id = "demo_blue",  severity = "blue",  text = "Demo Blue",  icon = spellIcon(Nock.Spells.AUTO_SHOT) or 132222, remaining = 125 },
  }
end

function Warnings:RunDemo(seconds)
  self._demoUntil = GetTime() + (seconds or DEMO_DURATION)
end

function Warnings:StopDemo()
  self._demoUntil = nil
end

function Warnings:Refresh(state)
  local list = state.warnings
  for i = #list, 1, -1 do list[i] = nil end
  if Nock.db and Nock.db.profile and Nock.db.profile.showWarnings == false then return end
  if self._demoUntil and self._demoUntil > GetTime() then
    for _, w in ipairs(demoList()) do list[#list + 1] = w end
    return
  end
  self._demoUntil = nil
  local reads = self:Reads(state)
  for _, check in ipairs(Warnings.ORDER) do
    local w = check(reads)
    if w then list[#list + 1] = w end
  end
  table.sort(list, bySeverity)
end

-- The settings page (Config/Options.lua) builds one inline box per entry
-- from this catalog; same shape as the TBC catalog.
Warnings.Catalog = {
  {
    key         = "ammo",
    category    = "gear",
    name        = "Ammo low",
    severity    = "red",
    enabledKey  = "warnQuiverEnabled",
    iconFn      = function() return 134404 end,  -- INV_Misc_Quiver_05
    description = "Your ammo slot is running dry.",
    logic       = "Fires when:\n• Ammo is loaded in the ammo slot\n• Its count is below the threshold\n\nIn and out of combat. The square shows the loaded ammo's icon with the count left.",
    thresholds  = {
      { key = "quiverArrowThreshold", label = "Ammo left", min = 50, max = 2000, step = 50 },
    },
  },
  {
    key         = "petDead",
    category    = "pet",
    name        = "Pet dead",
    severity    = "red",
    enabledKey  = "warnPetDeadEnabled",
    iconFn      = function() return spellIcon(Nock.Spells.PET.REVIVE_PET) or 132163 end,
    description = "Your pet is dead and needs Revive Pet.",
    logic       = "Fires when:\n• A pet is out\n• It is dead\n\nIn and out of combat, until it is revived or dismissed.",
  },
  {
    key         = "petMissing",
    category    = "pet",
    name        = "No pet in combat",
    severity    = "amber",
    enabledKey  = "warnPetMissingEnabled",
    iconFn      = function() return spellIcon(Nock.Spells.PET.CALL_PET) or 132161 end,
    description = "You are fighting without your pet.",
    logic       = "Fires when:\n• You are in combat\n• No pet is out\n• You know Call Pet\n\nQuiet out of combat, so a dismissed pet in town never nags.",
  },
  {
    key         = "petUnhappy",
    category    = "pet",
    name        = "Pet unhappy",
    severity    = "amber",
    enabledKey  = "warnPetUnhappyEnabled",
    iconFn      = function() return spellIcon(Nock.Spells.PET.FEED_PET) or 132165 end,
    description = "Your pet's happiness has dropped to Unhappy: feed it.",
    logic       = "Fires when:\n• A living pet is out\n• Its happiness is Unhappy (the lowest of the three)\n\nContent does not warn; the buff row's face covers that in combat.",
  },
  {
    key         = "petLowHp",
    category    = "pet",
    name        = "Pet HP low",
    severity    = "red",
    enabledKey  = "warnPetLowHpEnabled",
    iconFn      = function() return spellIcon(Nock.Spells.PET.MEND_PET) or 132179 end,
    description = "Your pet's health is below the threshold: Mend Pet.",
    logic       = "Shown when:\n• A living pet is out\n• Its HP is below the threshold\n\nPet health is a secret on WoW Forever, so the client decides this one and fades the square in itself. It therefore sits at the end of the row, cannot be counted or sorted, and has no sound.",
    thresholds  = {
      { key = "mendPetThreshold", label = "Pet HP threshold (%)", min = 20, max = 90, step = 5 },
    },
  },
}
